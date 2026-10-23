class_name CropSun
extends RefCounted
## Whether a food crop gets the sun it needs where it is going.
##
## `PlantSuitability` answers whether a plant belongs where it is going, and it asks about **light**
## as one of five properties - the plant's `sun` bit against the place's stated level. A crop is the
## one kind of plant for which that single bit is not enough: "full sun" is the letter of the
## requirement, but a tomato wants *six hours* of it and a lettuce will crop on four, and a designer
## choosing where to put the tomatoes is asking an hours question.
##
## Three things this joins, and none of them invented here:
##
## * **The stated light level, turned into hours.** A plan states ground in the three bands a person
##   uses - full sun, part shade, full shade - and this is the one place those words are given an hours
##   span. It is a convention, stated plainly, not a measurement: the mapping is written in `LEVEL_HOURS`.
## * **The crop's own requirement**, `PlantSpecies.sun_hours` - a fact about the plant the catalogue
##   either states or does not.
## * **The site's own day length**, from `SunStudy` by way of `SunReport`: how long the sun is up at the
##   garden's latitude at midsummer. This is the **ceiling** no spot can beat, and it is what turns "this
##   spot gets five hours" into an answer you can act on - a crop wanting eight hours at a latitude whose
##   longest day is seven is not badly sited, it is in the wrong country.
##
## **What it does not claim to do is measure the shade of a thing.** How many hours a particular bed
## actually gets depends on the wall beside it and the tree over it, and the sun study's own doc is
## clear that a study of one stated height is not that. So this reads the level a designer *stated*
## for the ground, says what band that stands for, and puts the site's day length beside it. It never
## says "this bed gets 5.2 hours"; it says "this bed is stated as part shade, which is three to six
## hours, and a tomato wants six".
##
## The verdict vocabulary is `PlantSuitability`'s - good, tolerated, wrong, unknown - borrowed rather
## than restated, so a page can show a light verdict and a suitability verdict in the same four colours
## and the same four words.

const PlantSpeciesScript := preload("res://scripts/plant_species.gd")
const PlantSuitabilityScript := preload("res://scripts/plant_suitability.gd")
const SunStudyScript := preload("res://scripts/vis/sun_study.gd")
const SunReportScript := preload("res://scripts/vis/sun_report.gd")

## The four verdicts, borrowed from the suitability check so there is one vocabulary and one set of
## colours in the whole program.
const GOOD := PlantSuitabilityScript.GOOD
const TOLERATED := PlantSuitabilityScript.TOLERATED
const UNSUITABLE := PlantSuitabilityScript.UNSUITABLE
const UNKNOWN := PlantSuitabilityScript.UNKNOWN

## The hours of direct sun each stated light level stands for, as a **range**, because the words a
## plan states ground in are bands and not measurements.
##
## The boundaries meet at six and at three, which is the horticultural convention a seed packet uses:
## "full sun" is six hours or more, "part shade" is three to six, and "full shade" is under three. A
## crop wanting exactly six hours in part shade lands on the boundary and is reported **tolerated**
## rather than refused - because a spot stated as part shade may well be getting its six, and the
## honest answer to a band that ends where the requirement begins is "this is thin".
const LEVEL_HOURS := {
	PlantSpeciesScript.FULL_SUN: Vector2(6.0, 24.0),
	PlantSpeciesScript.PART_SHADE: Vector2(3.0, 6.0),
	PlantSpeciesScript.FULL_SHADE: Vector2(0.0, 3.0),
}


# --- the bands ----------------------------------------------------------------------------


## The hours a stated light level stands for, as `Vector2(low, high)`, or `Vector2.ZERO` for a level
## nobody has.
static func band(level: int) -> Vector2:
	return LEVEL_HOURS.get(level, Vector2.ZERO)


## A stated light level as the hours it stands for, in words: "6 hours or more". Empty for a level
## nobody has.
static func band_text(level: int) -> String:
	match level:
		PlantSpeciesScript.FULL_SUN:
			return "6 hours or more"
		PlantSpeciesScript.PART_SHADE:
			return "3 to 6 hours"
		PlantSpeciesScript.FULL_SHADE:
			return "under 3 hours"
	return ""


# --- the site's own ceiling ---------------------------------------------------------------


## How long the sun is up at a site on a day of the year, in hours.
static func daylight_hours(site: Dictionary, day_of_year: int) -> float:
	if site.is_empty():
		return 0.0
	var hours: Dictionary = SunStudyScript.daylight_for(site, SunStudyScript.moment(day_of_year, 12.0))
	return float(hours["day_length_hours"])


## The year's longest day at a site, and the day it falls on: the most daylight anywhere outdoors at
## that latitude can have, which is the ceiling a crop's requirement is checked against.
##
## The two solstices only, which is where the longest day of the year always is: scanning all 365 days
## would give the same answer and a page that did it every frame would be a page nobody could use.
## Returns `{day_of_year, hours}`, or `{day_of_year: 0, hours: 0.0}` for a site nobody stated.
static func longest_day(site: Dictionary) -> Dictionary:
	if site.is_empty():
		return {"day_of_year": 0, "hours": 0.0}
	var best_day: int = SunReportScript.JUNE_SOLSTICE
	var best_hours: float = -1.0
	for day: int in [SunReportScript.JUNE_SOLSTICE, SunReportScript.DECEMBER_SOLSTICE]:
		var hours: float = daylight_hours(site, day)
		if hours > best_hours:
			best_hours = hours
			best_day = day
	return {"day_of_year": best_day, "hours": best_hours}


## The site's ceiling in one line, for a page: "the longest day is 21 June, with 15.4 hours of
## daylight". Empty when there is no site.
static func season_line(site: Dictionary) -> String:
	if site.is_empty():
		return ""
	var longest: Dictionary = longest_day(site)
	return "the longest day is %s, with %.1f hours of daylight" % [
		SunReportScript.day_words(int(longest["day_of_year"])), float(longest["hours"]),
	]


# --- the check ----------------------------------------------------------------------------


## Whether a crop gets the sun it needs at a place.
##
## Returns the same shape `PlantSuitability.check` returns, so a page can show the two side by side:
## `{verdict, ok, certain, colour, findings, summary, label, species, place, hours, band_text}`.
## `findings` is one row per question that was asked, in the same `{key, label, wanted, found, outcome,
## because, brief}` shape.
##
## Two questions, and **a question nobody answered is skipped, not answered**:
## the crop's own requirement missing means there is nothing to check and the verdict is unknown with
## no findings, and a site nobody stated skips the season without turning it grey.
static func check(
	crop: PlantSpecies, profile: TerrainProfile, site: Dictionary = {}, place: String = "this spot"
) -> Dictionary:
	var findings: Array[Dictionary] = []
	if crop == null:
		return _result(UNKNOWN, [], null, place, profile)
	var sun: Dictionary = _sun_finding(crop, profile)
	if not sun.is_empty():
		findings.append(sun)
	var season: Dictionary = _season_finding(crop, site)
	if not season.is_empty():
		findings.append(season)
	# Nothing to ask is not "good": a crop that states no sun requirement has not been checked, and a
	# green verdict for a question that never ran is the one answer this must not give.
	if findings.is_empty():
		return _result(UNKNOWN, findings, crop, place, profile)
	return _result(_worst(findings), findings, crop, place, profile)


## Check the crop that is already in the ground at a point, against the map the site's conditions are
## kept in - the counterpart of `PlantSuitability.check_at`.
static func check_at(crop: PlantSpecies, zone_map: ZoneMap, site: Dictionary, point: Vector2) -> Dictionary:
	if zone_map == null:
		return check(crop, TerrainProfile.make(), site, "this spot")
	var spot: Dictionary = zone_map.profile_at(point)
	return check(crop, spot["profile"], site, String(spot["place"]))


static func _sun_finding(crop: PlantSpecies, profile: TerrainProfile) -> Dictionary:
	if crop == null or crop.sun_hours_tenths <= 0:
		return {}
	var wanted: String = crop.sun_hours_text()
	if profile == null or not profile.has("sun"):
		return _finding(
			"sun_hours", "sun", wanted, "not stated", UNKNOWN,
			"nothing says how much sun this spot gets", "the plan doesn't say the sun"
		)
	var span: Vector2 = band(profile.sun_level())
	var shown: String = band_text(profile.sun_level())
	var need: float = crop.sun_hours()
	if need <= span.x:
		return _finding(
			"sun_hours", "sun", wanted, shown, GOOD,
			"it wants %s and this spot is %s" % [wanted, shown], shown
		)
	if need <= span.y:
		return _finding(
			"sun_hours", "sun", wanted, shown, TOLERATED,
			"it wants %s and this spot gets %s, so it is thin" % [wanted, shown],
			"wants %s, gets %s" % [wanted, shown]
		)
	return _finding(
		"sun_hours", "sun", wanted, shown, UNSUITABLE,
		"it wants %s and this spot gets only %s" % [wanted, shown],
		"wants %s, gets %s" % [wanted, shown]
	)


static func _season_finding(crop: PlantSpecies, site: Dictionary) -> Dictionary:
	if crop == null or crop.sun_hours_tenths <= 0 or site.is_empty():
		return {}
	var longest: Dictionary = longest_day(site)
	var hours: float = float(longest["hours"])
	var found: String = "%.1f hours" % hours
	var wanted: String = crop.sun_hours_text()
	if crop.sun_hours() > hours:
		return _finding(
			"season", "the season", wanted, found, UNSUITABLE,
			"even at midsummer this site has only %s of daylight" % found,
			"the site has too short a day"
		)
	return _finding(
		"season", "the season", wanted, found, GOOD,
		"the year's longest day has %s of daylight, so %s is there to be had" % [found, wanted],
		found
	)


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
	verdict: int, findings: Array[Dictionary], crop: PlantSpecies, place: String, profile: TerrainProfile
) -> Dictionary:
	var first: Dictionary = _first_not(findings, verdict)
	var title: String = crop.display_name() if crop != null else "this crop"
	var level: int = profile.sun_level() if profile != null and profile.has("sun") else 0
	return {
		"verdict": verdict,
		"ok": verdict != UNSUITABLE,
		"certain": verdict == GOOD or verdict == TOLERATED,
		"colour": PlantSuitabilityScript.colour_of(verdict),
		"findings": findings,
		"summary": _summary(verdict, first, title, place),
		"label": _label(verdict, first),
		"species": title,
		"place": place,
		"hours": band(level),
		"band_text": band_text(level),
	}


static func _first_not(findings: Array[Dictionary], outcome: int) -> Dictionary:
	for finding: Dictionary in findings:
		if int(finding.get("outcome", GOOD)) == outcome:
			return finding
	return findings[0] if not findings.is_empty() else {}


# --- saying it ----------------------------------------------------------------------------


static func _summary(verdict: int, first: Dictionary, title: String, place: String) -> String:
	if first.is_empty():
		return "%s does not say how much sun it wants, so there is nothing to check at %s." % [
			title, place
		]
	match verdict:
		UNSUITABLE:
			return "%s will not crop at %s: %s." % [title, place, String(first.get("because", ""))]
		UNKNOWN:
			return "%s cannot be checked at %s: %s." % [title, place, String(first.get("because", ""))]
		TOLERATED:
			return "%s may crop at %s, but %s." % [title, place, String(first.get("because", ""))]
	return "%s has the sun it wants at %s." % [title, place]


static func _label(verdict: int, first: Dictionary) -> String:
	if first.is_empty():
		return "no sun stated"
	match verdict:
		UNSUITABLE:
			return String(first.get("brief", "not enough sun"))
		TOLERATED:
			return String(first.get("brief", "only just enough sun"))
		UNKNOWN:
			return String(first.get("brief", "the plan doesn't say the sun"))
	return "enough sun"


static func summary_of(result: Dictionary) -> String:
	return String(result.get("summary", ""))


static func label_of(result: Dictionary) -> String:
	return String(result.get("label", ""))


static func colour_from(result: Dictionary) -> Color:
	return PlantSuitabilityScript.colour_from(result)


static func verdict_name(verdict: int) -> String:
	return PlantSuitabilityScript.verdict_name(verdict)


# --- the crops of a place -----------------------------------------------------------------


## Every crop in the catalogue, checked against one place, best first: the answer to "what will crop
## in this bed". One row per edible species, in `{id, title, verdict, colour, summary, label, needed,
## found}` shape, sorted by verdict and then by botanical name so the list is the same twice running.
##
## Only edible species are listed: a question about what will crop has no row for a boxwood.
static func rows(catalogue: PlantCatalogue, profile: TerrainProfile, site: Dictionary = {}, place: String = "this spot") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if catalogue == null:
		return out
	for plant: PlantSpecies in catalogue.all():
		if not plant.is_edible():
			continue
		var verdict: Dictionary = check(plant, profile, site, place)
		out.append({
			"id": plant.id,
			"title": plant.display_name(),
			"needed": plant.sun_hours_text(),
			"verdict": int(verdict["verdict"]),
			"colour": verdict["colour"],
			"summary": String(verdict["summary"]),
			"label": String(verdict["label"]),
			"found": String(verdict["band_text"]),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["verdict"]) != int(b["verdict"]):
			return int(a["verdict"]) < int(b["verdict"])
		return String(a["title"]) < String(b["title"]))
	return out


## Those rows as the lines a list control shows: the crop and how the place answers it. The line is
## the row's own `label` - which already carries what the crop wants and what it gets - rather than a
## format assembled here, so the list and the summary cannot say two different things.
static func row_texts(catalogue: PlantCatalogue, profile: TerrainProfile, site: Dictionary = {}, place: String = "this spot") -> Array[String]:
	var out: Array[String] = []
	for row: Dictionary in rows(catalogue, profile, site, place):
		out.append("%s: %s" % [String(row["title"]), String(row["label"])])
	return out


## How many crops of each verdict a place has, for a summary line.
static func counts(rows_list: Array) -> Dictionary:
	var out: Dictionary = {GOOD: 0, TOLERATED: 0, UNSUITABLE: 0, UNKNOWN: 0}
	for row: Dictionary in rows_list:
		var level: int = int(row.get("verdict", UNKNOWN))
		out[level] = int(out[level]) + 1
	return out


## "9 crops: 4 will crop here, 3 are thin, 2 will not." A place with no edible crop in the catalogue
## says so rather than reading as a place nothing grows in.
static func describe_rows(rows_list: Array) -> String:
	if rows_list.is_empty():
		return "no crops are recorded in this plant list"
	var held: Dictionary = counts(rows_list)
	var parts: PackedStringArray = PackedStringArray()
	parts.append("%d will crop here" % int(held.get(GOOD, 0)))
	var thin: int = int(held.get(TOLERATED, 0))
	if thin > 0:
		parts.append("%d are thin" % thin)
	var wrong: int = int(held.get(UNSUITABLE, 0))
	if wrong > 0:
		parts.append("%d will not" % wrong)
	var unknown: int = int(held.get(UNKNOWN, 0))
	if unknown > 0:
		parts.append("%d cannot be checked" % unknown)
	return "%d crop%s: %s." % [
		rows_list.size(), "" if rows_list.size() == 1 else "s", ", ".join(parts)
	]