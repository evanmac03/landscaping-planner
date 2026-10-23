class_name CropRotation
extends RefCounted
## What a food crop should and should not be grown with: the family it follows, and the family it
## stands beside.
##
## `PlantSpecies` already carries the one field this needs - `family`, the group a crop rotates with -
## and until now nothing read it. A kitchen gardener asks two questions of it, and they are the whole
## of this module:
##
## * **In turn** - *the same family shall not follow itself in the same bed.* That is the law of crop
##   rotation in a sentence: a brassica after a brassica shares its pests and its diseases year on
##   year, so a bed wants a different family each time round. Everything else is a preference, and the
##   one preference worth stating is that a **legume** as the predecessor is a good thing - beans and
##   peas leave the ground richer than they found it, which is why they are planted into a rotation
##   rather than at its end.
## * **Together** - what a crop gets on with standing beside it. This is *companion planting*, and it
##   is mostly convention rather than science, so the table below is deliberately short and the module
##   says so: it holds the pairings a seed packet or a kitchen garden book would repeat, and it claims
##   no more than that. The one pairing worth heeding is the allium beside the legume, which is the
##   one that is not folklore.
##
## The four verdicts are `PlantSuitability`'s - good, tolerated, wrong, unknown - borrowed rather than
## restated, so a rotation verdict and a suitability verdict and a sun verdict are the same four words
## in the same four colours wherever they meet on a page.
##
## **A question nobody answered is skipped, not answered.** A crop that names no family cannot be
## rotated and is not called good; a bed whose history nobody has stated leaves the turn unchecked;
## and a crop with nothing asked about it comes back **unknown**, never green - the same honesty
## `PlantSuitability` and `CropSun` keep, because a green ring for a check that never ran is the one
## answer this must not give.

const PlantSpeciesScript := preload("res://scripts/plant_species.gd")
const PlantSuitabilityScript := preload("res://scripts/plant_suitability.gd")

## The four verdicts, borrowed from the suitability check so there is one vocabulary and one set of
## colours in the whole program.
const GOOD := PlantSuitabilityScript.GOOD
const TOLERATED := PlantSuitabilityScript.TOLERATED
const UNSUITABLE := PlantSuitabilityScript.UNSUITABLE
const UNKNOWN := PlantSuitabilityScript.UNKNOWN

# --- the families -------------------------------------------------------------------------
#
# Re-exported so a caller building a bed's history or a crop's neighbour writes the family the same
# way the catalogue does, rather than reaching past this module into `PlantSpecies`.


const FAMILY_NONE := PlantSpeciesScript.FAMILY_NONE
const BRASSICA := PlantSpeciesScript.BRASSICA
const NIGHTSHADE := PlantSpeciesScript.NIGHTSHADE
const LEGUME := PlantSpeciesScript.LEGUME
const ALLIUM := PlantSpeciesScript.ALLIUM
const ROOT_CROP := PlantSpeciesScript.ROOT_CROP
const CUCURBIT := PlantSpeciesScript.CUCURBIT
const LEAFY := PlantSpeciesScript.LEAFY
const FRUITING := PlantSpeciesScript.FRUITING
const HERB_FAMILY := PlantSpeciesScript.HERB_FAMILY

## The families a bed can be rotated through, in the order the catalogue names them. A person choosing
## "what grew here last" is choosing one of these, or leaving it unstated.
const FAMILIES := [
	BRASSICA, NIGHTSHADE, LEGUME, ALLIUM, ROOT_CROP, CUCURBIT, LEAFY, FRUITING, HERB_FAMILY,
]

## The pairings that are **said to** grow well together: an unordered list, read as a symmetry so the
## table cannot disagree with itself about which way round a pairing goes.
##
## Deliberately short. Companion planting is a tradition carried on seed packets and in kitchen garden
## books, and the honest thing is to hold the pairings a person would recognise - the legume with the
## leafy and the brassica and the squash, the allium with the carrot, a herb among the fruiting crops -
## rather than to invent a matrix. Nothing here claims a yield.
const COMPANION_GOOD := [
	[LEGUME, LEAFY],
	[LEGUME, BRASSICA],
	[LEGUME, CUCURBIT],
	[LEGUME, ROOT_CROP],
	[LEGUME, NIGHTSHADE],
	[ALLIUM, ROOT_CROP],
	[ALLIUM, LEAFY],
	[BRASSICA, LEAFY],
	[BRASSICA, ROOT_CROP],
	[HERB_FAMILY, NIGHTSHADE],
	[HERB_FAMILY, CUCURBIT],
	[HERB_FAMILY, BRASSICA],
	[HERB_FAMILY, FRUITING],
	[HERB_FAMILY, LEAFY],
]

## The pairings that should be kept apart. One entry, and it is the one worth having: an **allium**
## stunts a **legume**, which is the companion pairing a gardener acts on rather than repeats.
const COMPANION_BAD := [
	[LEGUME, ALLIUM],
]


# --- the families as words ------------------------------------------------------------------


## A family as a person would say it: "brassica". Empty for `FAMILY_NONE`, which is a plant nobody
## rotates rather than a family called nothing.
static func family_words(family: StringName) -> String:
	return String(PlantSpeciesScript.FAMILY_NAMES.get(family, ""))


## The article a word wants: "an allium", "a brassica". Here rather than open-coded at each sentence,
## so "an allium after an allium" does not come out as "a allium after a allium".
static func article(word: String) -> String:
	if word.is_empty():
		return ""
	return "an" if "aeiou".contains(word.substr(0, 1).to_lower()) else "a"


## Every family there is, in the catalogue's order, as `StringName`s - what a page offers in the
## "what grew here last" dropdown.
static func families() -> Array[StringName]:
	var out: Array[StringName] = []
	for family: StringName in FAMILIES:
		out.append(family)
	return out


# --- the companions of a family -------------------------------------------------------------


## The families this one grows well beside, in the table's own order. Empty for a family nobody has.
static func good_neighbours(family: StringName) -> Array[StringName]:
	return _partners(family, COMPANION_GOOD)


## The families this one should be kept from, in the table's own order. Empty for a plant nobody
## rotates.
static func bad_neighbours(family: StringName) -> Array[StringName]:
	return _partners(family, COMPANION_BAD)


static func _partners(family: StringName, table: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	if family.is_empty():
		return out
	for pair: Array in table:
		var left: StringName = pair[0]
		var right: StringName = pair[1]
		if left == family and not out.has(right):
			out.append(right)
		elif right == family and not out.has(left):
			out.append(left)
	return out


## What a crop gets on with, in one line for a page: "grows well beside leafy, brassica and cucurbit;
## should be kept from allium". Empty for a plant nobody rotates.
static func companion_line(family: StringName) -> String:
	if family.is_empty():
		return ""
	var friends: Array[StringName] = good_neighbours(family)
	var foes: Array[StringName] = bad_neighbours(family)
	var parts: PackedStringArray = PackedStringArray()
	if not friends.is_empty():
		parts.append("grows well beside %s" % _list_words(_words_of(friends)))
	if not foes.is_empty():
		parts.append("should be kept from %s" % _list_words(_words_of(foes)))
	return "; ".join(parts)


static func _words_of(group: Array[StringName]) -> Array:
	var out: Array = []
	for family: StringName in group:
		out.append(family_words(family))
	return out


## A list as a person says it: "a, b and c". Empty list, empty string.
static func _list_words(words: Array) -> String:
	if words.is_empty():
		return ""
	if words.size() == 1:
		return String(words[0])
	return "%s and %s" % [
		", ".join(PackedStringArray(words.slice(0, words.size() - 1))), String(words[words.size() - 1])
	]


# --- the check ----------------------------------------------------------------------------


## Whether a crop should follow a stated family in a bed, and how it gets on with what stands beside.
##
## Returns the same shape `PlantSuitability.check` and `CropSun.check` return, so a page can show any
## of them side by side: `{verdict, ok, certain, colour, findings, summary, label, species, place,
## family, previous}`. `findings` is one row per question that was asked, in the same `{key, label,
## wanted, found, outcome, because, brief}` shape.
##
## **A question nobody answered is skipped, not answered.** A crop that names no family is not rotated
## (there is nothing to rotate), a bed whose history is unstated leaves the turn unchecked, and a
## neighbour with no stated pairing is passed over. Only when nothing at all could be asked does the
## verdict fall to unknown - and never to a green that says nothing was wrong when nothing was asked.
static func check(
	crop: PlantSpecies,
	previous_family: StringName = FAMILY_NONE,
	beside: Array = [],
	place: String = "this spot"
) -> Dictionary:
	var findings: Array[Dictionary] = []
	if crop == null:
		return _result(UNKNOWN, [], null, place, previous_family)
	var turn: Dictionary = turn_finding(crop, previous_family)
	if not turn.is_empty():
		findings.append(turn)
	var seen: Array[StringName] = []
	for raw: Variant in beside:
		var family: StringName = StringName(raw)
		if family.is_empty() or seen.has(family):
			continue
		seen.append(family)
		var company: Dictionary = companion_finding(crop.family, family)
		if not company.is_empty():
			findings.append(company)
	if findings.is_empty():
		return _result(UNKNOWN, findings, crop, place, previous_family)
	return _result(_worst(findings), findings, crop, place, previous_family)


## The turn: whether this crop's family may follow the stated one. Empty when it cannot be asked -
## the crop names no family, or nobody has said what grew here before.
static func turn_finding(crop: PlantSpecies, previous_family: StringName) -> Dictionary:
	if crop == null or crop.family.is_empty() or previous_family.is_empty():
		return {}
	var mine: String = family_words(crop.family)
	var before: String = family_words(previous_family)
	var found: String = "%s last year" % before
	if crop.family == previous_family:
		return _finding(
			"turn", "rotation", mine, found, UNSUITABLE,
			"%s %s after %s %s shares the same pests and diseases, so it wants a different family here" % [
				article(mine), mine, article(before), before
			],
			"same family twice"
		)
	if previous_family == LEGUME:
		return _finding(
			"turn", "rotation", mine, found, GOOD,
			"a legume went before it and leaves the ground richer than it found it",
			"after a legume"
		)
	return _finding(
		"turn", "rotation", mine, found, GOOD,
		"%s %s has not grown here, so this is a fresh start" % [article(mine), mine], "a fresh family"
	)


## How this crop's family gets on with one other family. Empty when there is no stated pairing to
## report - which is most pairs, and passing them over is right: a companion list is not a place to
## invent an opinion about everything, only about what somebody has said.
static func companion_finding(crop_family: StringName, beside_family: StringName) -> Dictionary:
	if crop_family.is_empty() or beside_family.is_empty() or crop_family == beside_family:
		return {}
	var mine: String = family_words(crop_family)
	var other: String = family_words(beside_family)
	var found: String = "beside %s" % other
	if _has_pair(COMPANION_BAD, crop_family, beside_family):
		return _finding(
			"company", "company", mine, found, UNSUITABLE,
			"a %s beside a %s does not grow well, and it is worth keeping them apart" % [mine, other],
			"kept from %s" % other
		)
	if _has_pair(COMPANION_GOOD, crop_family, beside_family):
		return _finding(
			"company", "company", mine, found, GOOD,
			"a %s and a %s grow well together" % [mine, other], "good beside %s" % other
		)
	return {}


static func _has_pair(table: Array, a: StringName, b: StringName) -> bool:
	for pair: Array in table:
		if (pair[0] == a and pair[1] == b) or (pair[0] == b and pair[1] == a):
			return true
	return false


static func _finding(
	key: String, label: String, wanted: String, found: String, outcome: int, because: String,
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


## The worst outcome among the findings, which is the verdict. The same ordering rule as
## `PlantSuitability`: something against the crop outranks a gap, and a gap outranks a thin margin.
static func _worst(findings: Array[Dictionary]) -> int:
	var seen_unknown := false
	var seen_tolerated := false
	for finding: Dictionary in findings:
		var outcome: int = int(finding.get("outcome", UNKNOWN))
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
	verdict: int, findings: Array[Dictionary], crop: PlantSpecies, place: String,
	previous_family: StringName
) -> Dictionary:
	var first: Dictionary = _first_not(findings, verdict)
	var title: String = crop.display_name() if crop != null else "this crop"
	return {
		"verdict": verdict,
		"ok": verdict != UNSUITABLE,
		"certain": verdict == GOOD or verdict == TOLERATED,
		"colour": PlantSuitabilityScript.colour_of(verdict),
		"findings": findings,
		"summary": _summary(verdict, first, title, place, crop),
		"label": _label(verdict, first),
		"species": title,
		"place": place,
		"family": family_words(crop.family) if crop != null else "",
		"previous": family_words(previous_family),
	}


static func _first_not(findings: Array[Dictionary], outcome: int) -> Dictionary:
	for finding: Dictionary in findings:
		if int(finding.get("outcome", GOOD)) == outcome:
			return finding
	return findings[0] if not findings.is_empty() else {}


# --- saying it ----------------------------------------------------------------------------


static func _summary(
	verdict: int, first: Dictionary, title: String, place: String, crop: PlantSpecies
) -> String:
	if first.is_empty():
		if crop == null or crop.family.is_empty():
			return "%s does not say which family it belongs to, so it cannot be rotated." % title
		return "%s cannot be rotated at %s: nothing says what grew there before." % [title, place]
	match verdict:
		UNSUITABLE:
			return "%s should not go at %s: %s." % [title, place, String(first.get("because", ""))]
		UNKNOWN:
			return "%s cannot be checked at %s: %s." % [title, place, String(first.get("because", ""))]
		TOLERATED:
			return "%s would go at %s, but %s." % [title, place, String(first.get("because", ""))]
	return "%s follows on well at %s." % [title, place]


static func _label(verdict: int, first: Dictionary) -> String:
	if first.is_empty():
		return "cannot be checked"
	# A good verdict still carries its reason here - "after a legume" and "a fresh family" are two
	# different good answers, and the list a person reads should say which one it is.
	if verdict == GOOD:
		return String(first.get("brief", "follows on well"))
	match verdict:
		UNSUITABLE:
			return String(first.get("brief", "same family twice"))
		TOLERATED:
			return String(first.get("brief", "only just"))
	return String(first.get("brief", "cannot be checked"))


static func summary_of(result: Dictionary) -> String:
	return String(result.get("summary", ""))


static func label_of(result: Dictionary) -> String:
	return String(result.get("label", ""))


static func colour_from(result: Dictionary) -> Color:
	return PlantSuitabilityScript.colour_from(result)


static func verdict_name(verdict: int) -> String:
	return PlantSuitabilityScript.verdict_name(verdict)


# --- what would follow in a bed -------------------------------------------------------------


## Every crop in the catalogue, checked against one bed's stated history, best first: the answer to
## "what should grow here next". One row per edible species, in `{id, title, family, after, verdict,
## colour, summary, label}` shape, sorted by verdict and then by botanical name so the list is the
## same twice running.
##
## Only edible species are listed: a question about what to grow has no row for a boxwood.
static func rows(
	catalogue: PlantCatalogue, previous_family: StringName = FAMILY_NONE, beside: Array = [],
	place: String = "this spot"
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if catalogue == null:
		return out
	for plant: PlantSpecies in catalogue.all():
		if not plant.is_edible():
			continue
		var verdict: Dictionary = check(plant, previous_family, beside, place)
		out.append({
			"id": plant.id,
			"title": plant.display_name(),
			"family": family_words(plant.family),
			"after": family_words(previous_family),
			"verdict": int(verdict["verdict"]),
			"colour": verdict["colour"],
			"summary": String(verdict["summary"]),
			"label": String(verdict["label"]),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["verdict"]) != int(b["verdict"]):
			return int(a["verdict"]) < int(b["verdict"])
		return String(a["title"]) < String(b["title"]))
	return out


## Those rows as the lines a list control shows: the crop and how the bed answers it. The line is the
## row's own `label` rather than a format assembled here, so the list and the summary cannot say two
## different things.
static func row_texts(
	catalogue: PlantCatalogue, previous_family: StringName = FAMILY_NONE, beside: Array = [],
	place: String = "this spot"
) -> Array[String]:
	var out: Array[String] = []
	for row: Dictionary in rows(catalogue, previous_family, beside, place):
		out.append("%s: %s" % [String(row["title"]), String(row["label"])])
	return out


## How many crops of each verdict a bed has, for a summary line.
static func counts(rows_list: Array) -> Dictionary:
	var out: Dictionary = {GOOD: 0, TOLERATED: 0, UNSUITABLE: 0, UNKNOWN: 0}
	for row: Dictionary in rows_list:
		var level: int = int(row.get("verdict", UNKNOWN))
		out[level] = int(out[level]) + 1
	return out


## "9 crops: 6 follow on well, 2 should not, 1 cannot be checked." A bed with no edible crop in the
## catalogue says so rather than reading as a bed nothing grows in.
static func describe_rows(rows_list: Array) -> String:
	if rows_list.is_empty():
		return "no crops are recorded in this plant list"
	var held: Dictionary = counts(rows_list)
	var parts: PackedStringArray = PackedStringArray()
	parts.append("%d follow on well" % int(held.get(GOOD, 0)))
	var thin: int = int(held.get(TOLERATED, 0))
	if thin > 0:
		parts.append("%d are thin" % thin)
	var wrong: int = int(held.get(UNSUITABLE, 0))
	if wrong > 0:
		parts.append("%d should not" % wrong)
	var unknown: int = int(held.get(UNKNOWN, 0))
	if unknown > 0:
		parts.append("%d cannot be checked" % unknown)
	return "%d crop%s: %s." % [
		rows_list.size(), "" if rows_list.size() == 1 else "s", ", ".join(parts)
	]