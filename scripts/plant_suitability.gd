class_name PlantSuitability
extends RefCounted
## Whether a plant belongs where it is about to be planted.
##
## The answer is a **verdict plus the reasons for it**, never just a colour: a designer who sees a red
## ring has to know *what* the ground does that the plant dislikes before they can decide whether to
## move the plant or to fix the ground. Every property that could be compared is compared on its own
## and reported on its own, and the verdict is the worst of them.
##
## Four verdicts, because two would be dishonest:
##
## * `GOOD` - every property the plan states matches. A generous plant list would be all greens; this
##   is the confident one.
## * `TOLERATED` - nothing is against it, but something is not ideal: a plant that wants more water
##   than the spot holds will live on an irrigation line. A designer needs to know that, and calling
##   it a failure would teach them to ignore red rings.
## * `UNSUITABLE` - a property is against it. This is the red ring.
## * `UNKNOWN` - the plan does not say what the ground is like. **This is not "fine"**: it is the
##   honest state of a plan nobody has described, and it is what prompts a designer to state it. A
##   check that read silence as "average" would hand out confident greens for a garden it knows
##   nothing about.
##
## **A question nobody answered is skipped, not answered.** If the plant's catalogue entry does not
## say which soils it takes, soil is not asked about at all; if the plan does not say what the soil
## is, it is reported as unknown. The two gaps are different, and only the second one is the
## designer's to fix.
##
## This checker never blocks anything. See `PlantPlacement` - the plant goes in the ground and the
## ring tells the truth about it, because the software's job is to inform the designer, not to
## overrule them.

const PlantSpeciesScript := preload("res://scripts/plant_species.gd")
const TerrainProfileScript := preload("res://scripts/terrain_profile.gd")
const PlantPlacementScript := preload("res://scripts/plant_placement.gd")

# --- the verdicts -------------------------------------------------------------------------

const GOOD := 0
const TOLERATED := 1
const UNSUITABLE := 2
const UNKNOWN := 3

const VERDICT_NAMES := {
	GOOD: "good",
	TOLERATED: "tolerated",
	UNSUITABLE: "wrong",
	UNKNOWN: "unknown",
}

## Green, amber, red, grey. The grey is not decoration: it is the "I cannot tell you" answer, and it
## has to be visibly not green or a designer reads a check that never ran as a pass.
const GOOD_COLOUR := Color(0.24, 0.78, 0.36)
const TOLERATED_COLOUR := Color(0.95, 0.72, 0.16)
const UNSUITABLE_COLOUR := Color(0.93, 0.24, 0.20)
const UNKNOWN_COLOUR := Color(0.70, 0.72, 0.76)

# --- the rules ----------------------------------------------------------------------------

## How a place's moisture meets a plant's water need.
##
## Horticulture, not arithmetic. Asking for *less* water than the ground holds is not the mirror image
## of asking for more: a drought-tolerant plant in a wet bed rots at the crown and dies, while a
## thirsty plant in a dry bed can be carried by irrigation and by watering it in for a season. So
## both directions can be `UNSUITABLE`, but the milder mismatch in each direction - medium where it
## wants low, or medium where it wants high - is something a designer works around, and it is
## `TOLERATED` rather than a failure.
##
## Indexed by the species' need, valued by the levels it accepts.
const MOISTURE_RULE := {
	PlantSpeciesScript.WATER_LOW: {
		GOOD: [PlantSpeciesScript.WATER_LOW],
		TOLERATED: [PlantSpeciesScript.WATER_MEDIUM],
		UNSUITABLE: [PlantSpeciesScript.WATER_HIGH],
	},
	PlantSpeciesScript.WATER_MEDIUM: {
		GOOD: [PlantSpeciesScript.WATER_MEDIUM],
		TOLERATED: [PlantSpeciesScript.WATER_HIGH],
		UNSUITABLE: [PlantSpeciesScript.WATER_LOW],
	},
	PlantSpeciesScript.WATER_HIGH: {
		GOOD: [PlantSpeciesScript.WATER_HIGH],
		TOLERATED: [PlantSpeciesScript.WATER_MEDIUM],
		UNSUITABLE: [PlantSpeciesScript.WATER_LOW],
	},
}


# --- the check ----------------------------------------------------------------------------


## Compare one species against one place. `place` names the area for the sentence that comes back.
##
## Returns `{verdict, ok, certain, colour, findings, summary, label, species, place, conditions}`.
## `findings` is one row per property that was asked about:
## `{key, label, wanted, found, outcome, because, brief}`.
static func check(species: PlantSpecies, profile: TerrainProfile, place: String = "this spot") -> Dictionary:
	var findings: Array[Dictionary] = []
	if species == null or profile == null:
		return _result(UNKNOWN, [], species, place, profile)
	findings.append(_sun_finding(species, profile))
	findings.append(_moisture_finding(species, profile))
	var soil: Dictionary = _soil_finding(species, profile)
	if not soil.is_empty():
		findings.append(soil)
	var drainage: Dictionary = _drainage_finding(species, profile)
	if not drainage.is_empty():
		findings.append(drainage)
	var zone: Dictionary = _zone_finding(species, profile)
	if not zone.is_empty():
		findings.append(zone)
	return _result(_worst(findings), findings, species, place, profile)


## Check a point against the map the site's conditions are stored in. The whole point of the map:
## the same plant dropped two metres to the left can be a different answer.
static func check_at(species: PlantSpecies, zone_map: ZoneMap, point: Vector2) -> Dictionary:
	if zone_map == null:
		return check(species, TerrainProfile.make(), "this spot")
	var spot: Dictionary = zone_map.profile_at(point)
	return check(species, spot["profile"], String(spot["place"]))


## The worst outcome among the findings, which is the verdict.
##
## The order is **not** the numeric order: a property that is against the plant outranks a gap, and a
## gap outranks a tolerated mismatch, because "the plan does not say how wet this is" is a thing the
## designer can go and fix and a mild mismatch is not.
static func _worst(findings: Array[Dictionary]) -> int:
	var seen_unknown := false
	var seen_tolerated := false
	for finding: Dictionary in findings:
		var outcome: int = finding.get("outcome", UNKNOWN)
		if outcome == UNSUITABLE:
			return UNSUITABLE
		if outcome == UNKNOWN:
			seen_unknown = true
		elif outcome == TOLERATED:
			seen_tolerated = true
	if seen_unknown:
		return UNKNOWN
	if seen_tolerated:
		return TOLERATED
	return GOOD


static func _result(
	verdict: int,
	findings: Array[Dictionary],
	species: PlantSpecies,
	place: String,
	profile: TerrainProfile
) -> Dictionary:
	var first: Dictionary = _first_not(findings, verdict)
	var title: String = species.display_name() if species != null else "this plant"
	return {
		"verdict": verdict,
		"ok": verdict != UNSUITABLE,
		"certain": verdict == GOOD or verdict == TOLERATED,
		"colour": colour_of(verdict),
		"findings": findings,
		"summary": _summary(verdict, first, title, place, profile),
		"label": _label(verdict, first),
		"species": title,
		"place": place,
		"conditions": profile.describe() if profile != null else "",
	}


## The first finding with that outcome, or the first finding at all, or an empty one.
static func _first_not(findings: Array[Dictionary], outcome: int) -> Dictionary:
	for finding: Dictionary in findings:
		if finding.get("outcome", GOOD) == outcome:
			return finding
	return findings[0] if not findings.is_empty() else {}


static func colour_of(verdict: int) -> Color:
	match verdict:
		GOOD:
			return GOOD_COLOUR
		TOLERATED:
			return TOLERATED_COLOUR
		UNSUITABLE:
			return UNSUITABLE_COLOUR
	return UNKNOWN_COLOUR


static func verdict_name(verdict: int) -> String:
	return String(VERDICT_NAMES.get(verdict, "unknown"))


# --- one property at a time ---------------------------------------------------------------


static func _sun_finding(species: PlantSpecies, profile: TerrainProfile) -> Dictionary:
	var wanted: String = species.sun_text()
	if not profile.has("sun"):
		return _finding(
			"sun", "light", wanted, "not stated", UNKNOWN,
			"nothing says how much sun this spot gets", "the plan doesn't say the sun"
		)
	var level: int = profile.sun_level()
	var found: String = profile.text_of("sun")
	if species.takes_sun(level):
		return _finding(
			"sun", "light", wanted, found, GOOD,
			"it takes %s and this spot is in %s" % [wanted, found], found
		)
	return _finding(
		"sun", "light", wanted, found, UNSUITABLE,
		"it wants %s and this spot is in %s" % [wanted, found], "wants %s" % wanted
	)


static func _moisture_finding(species: PlantSpecies, profile: TerrainProfile) -> Dictionary:
	var wanted: String = species.water_text()
	if not profile.has("moisture"):
		return _finding(
			"moisture", "moisture", wanted, "not stated", UNKNOWN,
			"nothing says how wet this spot stays", "the plan doesn't say how wet it is"
		)
	var level: int = profile.moisture_level()
	var found: String = profile.text_of("moisture")
	var rule: Dictionary = MOISTURE_RULE.get(species.water, {})
	var outcome: int = GOOD
	for candidate: int in [GOOD, TOLERATED, UNSUITABLE]:
		if (rule.get(candidate, []) as Array).has(level):
			outcome = candidate
	if outcome == GOOD:
		return _finding(
			"moisture", "moisture", wanted, found, GOOD,
			"it wants %s and this spot stays %s" % [wanted, found], found
		)
	if outcome == TOLERATED:
		return _finding(
			"moisture", "moisture", wanted, found, TOLERATED,
			"it will live on ground that %s" % _wet_words(level, species.water),
			"wants %s, not %s" % [wanted, found]
		)
	return _finding(
		"moisture", "moisture", wanted, found, UNSUITABLE,
		_wet_words(level, species.water), _wet_words(level, species.water, true)
	)


## Which way the water is wrong, in the words a designer would use.
static func _wet_words(level: int, need: int, brief: bool = false) -> String:
	if level < need:
		return "wants more water than this spot holds" if not brief else "wants more water"
	return "wants sharper drainage than this spot has" if not brief else "wants sharper drainage"


static func _soil_finding(species: PlantSpecies, profile: TerrainProfile) -> Dictionary:
	if species.soils.is_empty():
		# The catalogue does not say. Asking the question anyway would report the plant as wrong on
		# every soil it has no opinion about.
		return {}
	var wanted: String = species.soil_text()
	if not profile.has("soil"):
		return _finding(
			"soil", "soil", wanted, "not stated", UNKNOWN,
			"nothing says what the soil is", "the plan doesn't say the soil"
		)
	var found: String = profile.text_of("soil")
	if species.soils.has(profile.soil_name()):
		return _finding(
			"soil", "soil", wanted, found, GOOD,
			"it grows on %s and this spot is %s" % [wanted, found], found
		)
	return _finding(
		"soil", "soil", wanted, found, UNSUITABLE,
		"it grows on %s and this spot is %s" % [wanted, found], "not for %s" % found
	)


static func _drainage_finding(species: PlantSpecies, profile: TerrainProfile) -> Dictionary:
	if species.drainage >= PlantSpeciesScript.DRAINS_ANY:
		return {}
	var wanted: String = species.drainage_text()
	if not profile.has("drainage"):
		return _finding(
			"drainage", "drainage", wanted, "not stated", UNKNOWN,
			"nothing says how freely this spot drains", "the plan doesn't say how it drains"
		)
	var found: String = profile.text_of("drainage")
	if (species.drainage & profile.drainage_level()) != 0:
		return _finding(
			"drainage", "drainage", wanted, found, GOOD,
			"it takes %s and this spot is %s" % [wanted, found], found
		)
	return _finding(
		"drainage", "drainage", wanted, found, UNSUITABLE,
		"it takes %s and this spot is %s" % [wanted, found], "not where it is %s" % found
	)


## Hardiness is asked about **only when the place states a zone of its own**.
##
## A site's zone is a fact about the site, stated once, and a plan that has not stated it must not
## turn every ring grey - so an unstated zone is skipped, not called unknown. When a *place* does
## state one, it is a frost pocket or a sheltered court that is colder or warmer than the rest of the
## garden, and then the species' hardiness range is exactly the right thing to compare against.
static func _zone_finding(species: PlantSpecies, profile: TerrainProfile) -> Dictionary:
	if not profile.has("zone") or profile.zone() <= 0:
		return {}
	if not species.hardy_in(profile.zone()):
		return _finding(
			"zone", "hardiness", "zone %d-%d" % [species.zone_min, species.zone_max],
			"zone %d" % profile.zone(), UNSUITABLE,
			"it is hardy to zone %d and this spot is zone %d" % [species.zone_min, profile.zone()],
			"not hardy here"
		)
	return _finding(
		"zone", "hardiness", "zone %d-%d" % [species.zone_min, species.zone_max],
		"zone %d" % profile.zone(), GOOD,
		"it is hardy to zone %d and this spot is zone %d" % [species.zone_min, profile.zone()],
		"zone %d" % profile.zone()
	)


static func _finding(
	key: String,
	label: String,
	wanted: String,
	found: String,
	outcome: int,
	because: String,
	brief: String
) -> Dictionary:
	return {
		"key": key,
		"label": label,
		"wanted": wanted,
		"found": found,
		"outcome": outcome,
		"because": because,
		"brief": brief,
	}


# --- saying it ----------------------------------------------------------------------------


## The sentence that goes in a status line: what the plant is and what this spot does for it.
static func _summary(
	verdict: int,
	first: Dictionary,
	title: String,
	place: String,
	profile: TerrainProfile
) -> String:
	match verdict:
		UNSUITABLE:
			return "%s is the wrong plant for %s: %s." % [title, place, String(first.get("because", ""))]
		UNKNOWN:
			return "%s cannot be checked at %s: %s." % [title, place, String(first.get("because", ""))]
		TOLERATED:
			return "%s will live at %s, but %s." % [title, place, String(first.get("because", ""))]
	if profile == null or profile.is_empty():
		return "%s suits %s." % [title, place]
	return "%s suits %s (%s)." % [title, place, profile.describe()]


## The few words drawn beside the ring at the cursor, where there is no room for a sentence.
static func _label(verdict: int, first: Dictionary) -> String:
	match verdict:
		UNSUITABLE:
			return String(first.get("brief", "wrong for this spot"))
		TOLERATED:
			return String(first.get("brief", "will live here"))
		UNKNOWN:
			return String(first.get("brief", "the plan doesn't say"))
	return "suits this spot"


## Read back out of a result, for callers that only kept the dictionary.
static func summary_of(result: Dictionary) -> String:
	return String(result.get("summary", ""))


static func label_of(result: Dictionary) -> String:
	return String(result.get("label", ""))


static func colour_from(result: Dictionary) -> Color:
	var colour: Variant = result.get("colour", null)
	return colour if colour is Color else UNKNOWN_COLOUR


# --- the planting that is already in the ground -------------------------------------------


## Check every plant already placed on the plan against the map, for the audit a designer runs after
## the fact - the yard that was planted before anybody described the ground.
##
## A plant with no species recorded is counted and **named as a gap**, not skipped: the shipped yard
## has thirty of them, and an audit that quietly passed them would be reporting on a third of the
## planting.
##
## Returns `{rows, counts, planted, unnamed, text}`. `counts` is per verdict, `rows` is
## `{node, name, species_id, title, at, verdict, colour, summary}` in the order the yard lists them.
static func audit(catalogue: PlantCatalogue, yard: Node3D, zone_map: ZoneMap) -> Dictionary:
	var rows: Array[Dictionary] = []
	var counts: Dictionary = {GOOD: 0, TOLERATED: 0, UNSUITABLE: 0, UNKNOWN: 0}
	var unnamed: int = 0
	if yard == null:
		return {"rows": rows, "counts": counts, "planted": 0, "unnamed": 0, "text": "no yard to check"}
	for node: Node3D in PlantPlacementScript.planted(yard):
		# The plan's metres are the yard's own - a planted prop hangs straight off `Yard/Plants` - so
		# the global position is the point the zone map is asked about. A node that is not in the
		# scene yet (a caller auditing a yard it has just built, a test) is read from its own
		# position instead: asking a detached node for a global transform is an engine error and
		# answers zero, which would silently audit every plant as if it stood at the origin.
		var where: Vector3 = node.global_position if node.is_inside_tree() else node.position
		var point := Vector2(where.x, where.z)
		var species_id: StringName = PlantPlacementScript.species_of(node)
		if species_id.is_empty():
			unnamed += 1
			continue
		var species: PlantSpecies = null
		if catalogue != null:
			species = catalogue.get_species(species_id)
		if species == null:
			unnamed += 1
			continue
		var verdict: Dictionary = check_at(species, zone_map, point)
		var level: int = int(verdict["verdict"])
		counts[level] = int(counts[level]) + 1
		rows.append({
			"node": node,
			"name": String(node.name),
			"species_id": species_id,
			"title": species.display_name(),
			"at": point,
			"verdict": level,
			"colour": verdict["colour"],
			"summary": verdict["summary"],
		})
	return {
		"rows": rows,
		"counts": counts,
		"planted": rows.size() + unnamed,
		"unnamed": unnamed,
		"text": describe_audit(rows.size() + unnamed, counts, unnamed),
	}


## "3 plants: 2 suit their spot, 1 is in the wrong place."
##
## An audit of a planting list that names nothing says so in one clause rather than "0 suit their
## spot": the shipped yard is thirty props with no species on them, and a report that leads with a
## zero about a check that could not run is a report nobody reads twice.
static func describe_audit(planted: int, counts: Dictionary, unnamed: int = 0) -> String:
	if planted <= 0:
		return "no plants on the plan to check"
	var checked: int = planted - unnamed
	if checked <= 0:
		return "%d plant%s, and not one says which species it is" % [
			planted, "" if planted == 1 else "s"
		]
	var parts: PackedStringArray = PackedStringArray()
	parts.append("%d suit their spot" % int(counts.get(GOOD, 0)))
	var tolerated: int = int(counts.get(TOLERATED, 0))
	if tolerated > 0:
		parts.append("%d will live but are not ideal" % tolerated)
	var wrong: int = int(counts.get(UNSUITABLE, 0))
	if wrong > 0:
		parts.append("%d %s in the wrong place" % [wrong, "is" if wrong == 1 else "are"])
	var unknown: int = int(counts.get(UNKNOWN, 0))
	if unknown > 0:
		parts.append("%d cannot be checked" % unknown)
	if unnamed > 0:
		parts.append("%d have no species recorded" % unnamed)
	return "%d plant%s: %s." % [
		planted, "" if planted == 1 else "s", ", ".join(parts)
	]


## The audit's wrong and tolerated rows as lines, worst first, for a report somebody reads.
static func audit_lines(result: Dictionary, limit: int = 20) -> Array[String]:
	var rows: Array = result.get("rows", [])
	var ranked: Array[Dictionary] = []
	for row: Variant in rows:
		if not (row is Dictionary):
			continue
		if int(row.get("verdict", GOOD)) in [UNSUITABLE, TOLERATED]:
			ranked.append(row)
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("verdict", GOOD)) > int(b.get("verdict", GOOD)))
	var out: Array[String] = []
	for row: Dictionary in ranked:
		if out.size() >= limit:
			out.append("... and %d more" % (ranked.size() - limit))
			break
		out.append("%s - %s" % [String(row.get("title", "")), String(row.get("summary", ""))])
	return out