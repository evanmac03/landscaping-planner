class_name GrowingSeason
extends RefCounted
## How long the season is: the window between the last frost of spring and the first frost of autumn,
## and which food crops have the time to finish inside it.
##
## The site's climate is two dates, and a gardener states them as two dates: "our last frost is
## around the twentieth of May and the first one comes in early October". Everything else about a
## growing season is arithmetic on that pair - how many days it runs, and whether a crop that takes
## a stated number of days from sowing to harvest has that many to spare before the frost returns.
##
## Two things this joins, and neither of them invented here:
##
## * **`PlantSpecies.maturity_days`** - the days from sowing to the first harvest, a fact the
##   catalogue either states or does not.
## * **The site's own frost dates**, kept with the drawing beside its latitude, because they are the
##   same kind of fact. This is the one thing that turns "this crop takes seventy-five days" from a
##   number into an answer: seventy-five days of *what*.
##
## **What it does not claim to do is say when to sow.** That is a different question - it needs a
## start date and a succession of them, and it belongs to the planner that asks it. This module only
## measures the season and checks a crop against its length, so that whatever asks about sowing has a
## season to sow into.
##
## The checks reuse `PlantSuitability`'s verdicts - good, tolerated, wrong, unknown - borrowed rather
## than restated, so a page can show a season verdict and a light verdict in the same four colours.
## And the same rule holds as everywhere else in the food garden: **a question nobody answered is
## skipped, not green.** A crop that records no time to maturity, or a drawing that states no season,
## is UNKNOWN - never a comfortable green fit that was never actually checked.

const PlantSpeciesScript := preload("res://scripts/plant_species.gd")
const PlantSuitabilityScript := preload("res://scripts/plant_suitability.gd")
const SunReportScript := preload("res://scripts/vis/sun_report.gd")

## The four verdicts, borrowed from the suitability check so there is one vocabulary and one set of
## colours in the whole program.
const GOOD := PlantSuitabilityScript.GOOD
const TOLERATED := PlantSuitabilityScript.TOLERATED
const UNSUITABLE := PlantSuitabilityScript.UNSUITABLE
const UNKNOWN := PlantSuitabilityScript.UNKNOWN

## The last day of the year a frost date can fall on. A leap year is the longest a year gets, and a
## frost date is stated to the day rather than to the year, so this is the ceiling a date is clamped
## to rather than a claim about which year it is.
const MAX_DAY := 366

## How close to the first frost a crop may cut it and still be a comfortable fit. A crop whose last
## day lands within a fortnight of the frost is **tolerated** rather than good: it finishes in a kind
## year and is cut off in a cold one, and "tolerated" is exactly that answer. A fortnight is stated
## plainly and is a convention, not a measurement.
const TIGHT_DAYS := 14

## What a page says when there is no season to measure.
const NO_SEASON := "the growing season is not stated"


# --- the pair -----------------------------------------------------------------------------


## Whether a number is a day of the year this program will store (1..366). Zero is not a day: it is
## "not stated".
static func is_day(day: int) -> bool:
	return day >= 1 and day <= MAX_DAY


## Whether a pair of frost dates is a growing season: both stated as days, and the first frost after
## the last. A season that ends before it begins is not a short season - it is two dates somebody
## typed the wrong way round, and it is answered with "not stated" rather than a negative count.
static func is_stated(last_frost: int, first_frost: int) -> bool:
	return is_day(last_frost) and is_day(first_frost) and first_frost > last_frost


## How many days the season runs, from the last frost to the first. Zero when the pair is not a
## season, rather than a negative number of days.
static func length_days(last_frost: int, first_frost: int) -> int:
	if not is_stated(last_frost, first_frost):
		return 0
	return first_frost - last_frost


## A frost date as a person writes it: "20 May". Empty for a date that is not stated.
static func day_words(day: int) -> String:
	if not is_day(day):
		return ""
	return SunReportScript.day_words(day)


# --- the season in words ------------------------------------------------------------------


## The season in one sentence: "The growing season runs about 145 days, from 20 May to 5 October."
## A pair that is not a season is reported as not stated, because that is the truth about it.
static func season_text(last_frost: int, first_frost: int) -> String:
	if not is_stated(last_frost, first_frost):
		return NO_SEASON
	return "The growing season runs about %d days, from %s to %s." % [
		length_days(last_frost, first_frost), day_words(last_frost), day_words(first_frost),
	]


# --- whether a crop has time to finish ----------------------------------------------------


## Whether a crop has room to finish in a season.
##
## Returns the same shape the other food checks return, so a page can show a season answer beside a
## light answer: `{verdict, ok, certain, colour, findings, summary, label, species, days, stated}`.
## `findings` is one row per question that was asked, in the `{key, label, wanted, found, outcome,
## because, brief}` shape, and `days` is the season length in days.
##
## **A question nobody answered is skipped, not green:** a crop that records no time to maturity is
## UNKNOWN with no findings, and so is a drawing whose season is not stated - the season check has
## nothing to say about it rather than finding a fit that was never checked.
static func check(
	crop: PlantSpecies, last_frost: int, first_frost: int
) -> Dictionary:
	var findings: Array[Dictionary] = []
	if not is_stated(last_frost, first_frost) or crop == null:
		return _result(UNKNOWN, findings, crop, last_frost, first_frost)
	var fit: Dictionary = _fit_finding(crop, last_frost, first_frost)
	if not fit.is_empty():
		findings.append(fit)
	if findings.is_empty():
		return _result(UNKNOWN, findings, crop, last_frost, first_frost)
	return _result(_worst(findings), findings, crop, last_frost, first_frost)


static func _fit_finding(crop: PlantSpecies, last_frost: int, first_frost: int) -> Dictionary:
	if crop == null or crop.maturity_days <= 0:
		return {}
	var season: int = length_days(last_frost, first_frost)
	var need: int = crop.maturity_days
	var wanted: String = crop.maturity_text()
	var found: String = "%d days" % season
	if need > season:
		return _finding(
			"season", "the season", wanted, found, UNSUITABLE,
			"it needs %s and the growing season is only %s" % [wanted, found],
			"the season is too short"
		)
	if season - need <= TIGHT_DAYS:
		return _finding(
			"season", "the season", wanted, found, TOLERATED,
			"it needs %s of a %s season, so it finishes only just before the frost" % [wanted, found],
			"only %d days to spare" % (season - need)
		)
	return _finding(
		"season", "the season", wanted, found, GOOD,
		"it needs %s and the growing season is %s" % [wanted, found],
		"fits the season"
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


## The worst outcome among the findings, which is the verdict. Asked of `PlantSuitability` rather than
## carried here: one ordering rule, so a red ring and a red row cannot come to different verdicts.
static func _worst(findings: Array[Dictionary]) -> int:
	return PlantSuitabilityScript.worst_of(findings)


static func _result(
	verdict: int, findings: Array[Dictionary], crop: PlantSpecies, last_frost: int, first_frost: int
) -> Dictionary:
	var stated: bool = is_stated(last_frost, first_frost)
	var first: Dictionary = _first_not(findings, verdict)
	var title: String = crop.display_name() if crop != null else "this crop"
	return {
		"verdict": verdict,
		"ok": verdict != UNSUITABLE,
		"certain": verdict == GOOD or verdict == TOLERATED,
		"colour": PlantSuitabilityScript.colour_of(verdict),
		"findings": findings,
		"summary": _summary(verdict, first, title, stated),
		"label": _label(verdict, first, stated),
		"species": title,
		"days": length_days(last_frost, first_frost),
		"stated": stated,
	}


static func _first_not(findings: Array[Dictionary], outcome: int) -> Dictionary:
	for finding: Dictionary in findings:
		if int(finding.get("outcome", GOOD)) == outcome:
			return finding
	return findings[0] if not findings.is_empty() else {}


# --- saying it ----------------------------------------------------------------------------


static func _summary(verdict: int, first: Dictionary, title: String, season_stated: bool) -> String:
	if not season_stated:
		return "The growing season is not stated, so %s cannot be checked." % title
	if first.is_empty():
		return "%s does not record a time to maturity, so there is nothing to check." % title
	match verdict:
		UNSUITABLE:
			return "%s will not finish in the season: %s." % [title, String(first.get("because", ""))]
		TOLERATED:
			return "%s may finish, but %s." % [title, String(first.get("because", ""))]
	return "%s has time to finish in the season." % title


static func _label(verdict: int, first: Dictionary, season_stated: bool) -> String:
	if not season_stated:
		return NO_SEASON
	if first.is_empty():
		return "no time to maturity stated"
	match verdict:
		UNSUITABLE:
			return String(first.get("brief", "too slow for the season"))
		TOLERATED:
			return String(first.get("brief", "only just fits"))
	return "fits the season"


static func summary_of(result: Dictionary) -> String:
	return String(result.get("summary", ""))


static func label_of(result: Dictionary) -> String:
	return String(result.get("label", ""))


static func colour_from(result: Dictionary) -> Color:
	return PlantSuitabilityScript.colour_from(result)


static func verdict_name(verdict: int) -> String:
	return PlantSuitabilityScript.verdict_name(verdict)


# --- the crops of a season ------------------------------------------------------------------


## Every food crop in the catalogue, checked against one season, best first: the answer to "what
## will ripen here". One row per edible species, in `{id, title, needed, days, verdict, colour,
## summary, label}` shape, sorted by verdict and then by botanical name so the list is the same twice
## running.
##
## Only edible species are listed: a question about what will finish has no row for a boxwood.
static func rows(catalogue: PlantCatalogue, last_frost: int, first_frost: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if catalogue == null:
		return out
	for plant: PlantSpecies in catalogue.all():
		if not plant.is_edible():
			continue
		var verdict: Dictionary = check(plant, last_frost, first_frost)
		out.append({
			"id": plant.id,
			"title": plant.display_name(),
			"needed": plant.maturity_text(),
			"days": int(verdict["days"]),
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


## Those rows as the lines a list control shows: the crop and how the season answers it. The line is
## the row's own `label` rather than a format assembled here, so the list and the summary cannot say
## two different things.
static func row_texts(catalogue: PlantCatalogue, last_frost: int, first_frost: int) -> Array[String]:
	var out: Array[String] = []
	for row: Dictionary in rows(catalogue, last_frost, first_frost):
		out.append("%s: %s" % [String(row["title"]), String(row["label"])])
	return out


## How many crops of each verdict a season has, for a summary line.
static func counts(rows_list: Array) -> Dictionary:
	var out: Dictionary = {GOOD: 0, TOLERATED: 0, UNSUITABLE: 0, UNKNOWN: 0}
	for row: Dictionary in rows_list:
		var level: int = int(row.get("verdict", UNKNOWN))
		out[level] = int(out[level]) + 1
	return out


## "9 crops: 8 have time to finish, 1 cannot be checked." A season with no food crop in the catalogue
## says so rather than reading as a season nothing grows in.
static func describe_rows(rows_list: Array) -> String:
	if rows_list.is_empty():
		return "no crops are recorded in this plant list"
	var held: Dictionary = counts(rows_list)
	var parts: PackedStringArray = PackedStringArray()
	parts.append("%d have time to finish" % int(held.get(GOOD, 0)))
	var thin: int = int(held.get(TOLERATED, 0))
	if thin > 0:
		parts.append("%d only just fit" % thin)
	var wrong: int = int(held.get(UNSUITABLE, 0))
	if wrong > 0:
		parts.append("%d will not finish" % wrong)
	var unknown: int = int(held.get(UNKNOWN, 0))
	if unknown > 0:
		parts.append("%d cannot be checked" % unknown)
	return "%d crop%s: %s." % [
		rows_list.size(), "" if rows_list.size() == 1 else "s", ", ".join(parts)
	]