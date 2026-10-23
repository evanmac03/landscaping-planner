class_name SowingPlanner
extends RefCounted
## When to sow, and when the crop is ready: the calendar half of the growing season.
##
## `GrowingSeason` answers whether a crop *has* time to finish inside the window between the last frost
## of spring and the first frost of autumn. That is the yes-or-no question. This answers the two that
## follow from it and are the ones a gardener actually works to:
##
## * **When can I sow it?** A crop takes a stated number of days from sowing to its first harvest, and
##   the season ends on a stated day, so the last day it may be sown is `first_frost - maturity_days`.
##   Together with the last frost - the earliest safe day to sow anything tender - that pair is the
##   crop's **sowing window**, and it is the one number a seed packet never prints because it depends on
##   where you are.
##
## * **When will it be ready?** A day of sowing plus the days to maturity is a day of harvest, and it
##   either lands before the first frost or it does not.
##
## And, because a kitchen garden is not planted once:
##
## * **How do I keep it coming?** Sowing the same crop again every few weeks - a **succession** - moves
##   that harvest on rather than letting it all ripen at once. This is arithmetic too: sow every so many
##   days from the first sowing while the sowing date still has time to ripen before the frost, and what
##   comes out is a list of sowing dates and the harvest span they cover.
##
## Three things it joins, none invented here:
##
## * **`PlantSpecies.maturity_days`** - the days from sowing to first harvest, a fact the catalogue
##   either states or does not.
## * **The site's own frost dates**, kept on the drawing beside the latitude (see `GrowingSeason`).
## * So everything here is arithmetic on those, and the planting date a person chooses.
##
## The verdict vocabulary is `PlantSuitability`'s - good, tolerated, wrong, unknown - borrowed rather
## than restated, so a sowing answer and a light answer come out in the same four words and colours. And
## the rule holds as everywhere else in the food garden: **a question nobody answered is skipped, not
## green.** A crop that records no time to maturity, or a drawing that states no season, or a sowing
## date that is not a day, is UNKNOWN - never a comfortable fit that was never actually checked.
##
## **What it does not claim:** that a sown seed will germinate, or that a stated day to maturity is more
## than a guide. It says "sown on this day a crop that takes seventy-five days is ready about this day,
## and that is before the frost" - arithmetic on two stated facts, and no more.

const PlantSpeciesScript := preload("res://scripts/plant_species.gd")
const PlantSuitabilityScript := preload("res://scripts/plant_suitability.gd")
const GrowingSeasonScript := preload("res://scripts/growing_season.gd")
const SunReportScript := preload("res://scripts/vis/sun_report.gd")

## The four verdicts, borrowed from the suitability check so there is one vocabulary and one set of
## colours in the whole program.
const GOOD := PlantSuitabilityScript.GOOD
const TOLERATED := PlantSuitabilityScript.TOLERATED
const UNSUITABLE := PlantSuitabilityScript.UNSUITABLE
const UNKNOWN := PlantSuitabilityScript.UNKNOWN

## The last day of the year a sowing or a harvest can fall on. A leap year is the longest a year gets,
## and a date here is stated to the day rather than to the year, so this is the ceiling it is clamped to
## rather than a claim about which year it is.
const MAX_DAY := 366

## How close to the first frost a crop may ripen and still be a comfortable fit. A harvest within a
## fortnight of the frost finishes in a kind year and is cut off in a cold one, which is exactly the
## answer "tolerated". The same convention `GrowingSeason` uses, stated once more where it is applied.
const TIGHT_DAYS := 14

## The days between one sowing of a crop and the next, when a gardener wants it coming rather than all
## at once. Three weeks is the traditional interval for a salad crop - long enough that the rows do not
## overlap, short enough that there is always something to cut - and it is offered as a starting point,
## not a law.
const DEFAULT_INTERVAL := 21

## What a succession interval may be. A day is the finest a person plans in; four months is longer than
## any kitchen succession and marks the point where the number stops being a plan.
const MIN_INTERVAL := 1
const MAX_INTERVAL := 120

## The most sowings a succession is worked out to. A year of weekly sowings is fifty-two, which is more
## than any garden needs and enough that the loop is bounded rather than trusting an interval.
const MAX_SOWINGS := 52

## What the module says when there is nothing to work out, each naming the one fact that is missing.
const NO_SEASON := "the growing season is not stated"
const NO_MATURITY := "no time to maturity stated"
const NO_WINDOW := "no sowing date would ripen before the first frost"
const NO_CROP := "there is no crop to sow"


# --- days and dates -----------------------------------------------------------------------


## Whether a number is a day of the year this program will store (1..366). Zero is not a day: it is
## "not stated".
static func is_day(day: int) -> bool:
	return day >= 1 and day <= MAX_DAY


## A day of the year as a person writes it: "20 May". Empty for a day that is not stated.
static func day_words(day: int) -> String:
	if not is_day(day):
		return ""
	return SunReportScript.day_words(day)


# --- the sowing window --------------------------------------------------------------------


## The last day a crop that takes `maturity_days` may be sown and still ripen before the first frost:
## `first_frost - maturity_days`. Zero when the frost or the time to maturity is not stated.
static func last_sow_day(first_frost: int, maturity_days: int) -> int:
	if not is_day(first_frost) or maturity_days <= 0:
		return 0
	return first_frost - maturity_days


## The span of days a crop may be sown on and still finish: the earliest safe sowing - the last frost -
## through the last one that ripens in time.
##
## Returns `{stated, first, last, days, reason}`. `stated` is false when there is no window at all, and
## `reason` then names why - no season, no time to maturity, or a crop too slow to sow anywhere in it.
## `days` is how many sowing days the window holds, which is what a gardener is really weighing.
static func sow_window(last_frost: int, first_frost: int, maturity_days: int) -> Dictionary:
	if not GrowingSeasonScript.is_stated(last_frost, first_frost):
		return {"stated": false, "first": 0, "last": 0, "days": 0, "reason": NO_SEASON}
	if maturity_days <= 0:
		return {"stated": false, "first": 0, "last": 0, "days": 0, "reason": NO_MATURITY}
	var last: int = first_frost - maturity_days
	if last < last_frost:
		return {"stated": false, "first": 0, "last": 0, "days": 0, "reason": NO_WINDOW}
	return {"stated": true, "first": last_frost, "last": last, "days": last - last_frost + 1, "reason": ""}


## The sowing window in one phrase, for a page: "sow any time from 20 May to 1 August", "sow on 20 May"
## for a one-day window, or the reason there is no window.
static func window_text(last_frost: int, first_frost: int, maturity_days: int) -> String:
	var window: Dictionary = sow_window(last_frost, first_frost, maturity_days)
	if not bool(window["stated"]):
		return String(window["reason"])
	if int(window["days"]) == 1:
		return "sow on %s" % day_words(int(window["first"]))
	return "sow any time from %s to %s" % [
		day_words(int(window["first"])), day_words(int(window["last"]))
	]


## The day a crop sown on `sow` is ready: the sowing day plus the days to maturity. Zero when either
## is not stated. May fall after the year turns, which the wording below says out loud.
static func ready_day(sow: int, maturity_days: int) -> int:
	if not is_day(sow) or maturity_days <= 0:
		return 0
	return sow + maturity_days


## "ready about 19 July", or "ready after the year turns" for a harvest past the end of the year, or ""
## when there is nothing to say.
static func _ready_text(day: int) -> String:
	if day <= 0:
		return ""
	if not is_day(day):
		return "ready after the year turns"
	return "ready about %s" % day_words(day)


## "on 19 July", or "after the year turns". The clause form, for a sentence that already has a verb.
static func _when_text(day: int) -> String:
	if not is_day(day):
		return "after the year turns"
	return "on %s" % day_words(day)


# --- the check ----------------------------------------------------------------------------


## Whether a crop sown on `sow` ripens before the first frost, and whether that is a safe day to sow.
##
## Returns the same shape the other food checks return, so a page can show a sowing answer beside a
## light answer: `{verdict, ok, certain, colour, findings, summary, label, species, sow, sow_text, ready,
## ready_text, window}`. `findings` is one row per question that was asked, in the `{key, label, wanted,
## found, outcome, because, brief}` shape.
##
## Two questions, and **a question nobody answered is skipped, not answered**: the crop's own time to
## maturity missing means there is nothing to work out and the verdict is UNKNOWN with no findings, and
## so does a drawing whose season is not stated or a sowing date that is not a day.
static func check(
	crop: PlantSpecies, last_frost: int, first_frost: int, sow: int
) -> Dictionary:
	var findings: Array[Dictionary] = []
	if (
		crop == null or crop.maturity_days <= 0
		or not GrowingSeasonScript.is_stated(last_frost, first_frost) or not is_day(sow)
	):
		return _result(UNKNOWN, findings, crop, last_frost, first_frost, sow)
	findings.append(_finish_finding(crop, first_frost, sow))
	findings.append(_sow_finding(last_frost, sow))
	return _result(_worst(findings), findings, crop, last_frost, first_frost, sow)


## Whether the crop ripens before the frost, and by how much. A harvest after the first frost is
## UNSUITABLE; one within a fortnight of it is TOLERATED; anything earlier is GOOD.
static func _finish_finding(crop: PlantSpecies, first_frost: int, sow: int) -> Dictionary:
	var ready: int = sow + crop.maturity_days
	var wanted: String = crop.maturity_text()
	var found: String = _ready_text(ready)
	if ready > first_frost:
		return _finding(
			"finish", "ripening", wanted, found, UNSUITABLE,
			"it would ripen %s, after the first frost on %s" % [_when_text(ready), day_words(first_frost)],
			"ripens too late"
		)
	var spare: int = first_frost - ready
	if spare <= TIGHT_DAYS:
		var tail: String = (
			"on the very day of the first frost" if spare == 0
			else "only %d days before the first frost" % spare
		)
		return _finding(
			"finish", "ripening", wanted, found, TOLERATED,
			"it would ripen %s, %s" % [_when_text(ready), tail],
			"only just ripens"
		)
	return _finding(
		"finish", "ripening", wanted, found, GOOD,
		"it would ripen %s, %d days before the first frost" % [_when_text(ready), spare],
		"ripens in time"
	)


## Whether the sowing date is a safe one. Sowing before the last frost is a gamble the frosts may
## settle either way, so it is TOLERATED rather than refused: hardy crops do fine and tender ones die.
static func _sow_finding(last_frost: int, sow: int) -> Dictionary:
	var showed: String = day_words(sow)
	if sow < last_frost:
		return _finding(
			"sow", "the sowing date", "", showed, TOLERATED,
			"it would be sown on %s, before the last frost on %s" % [showed, day_words(last_frost)],
			"sown before the last frost"
		)
	return _finding(
		"sow", "the sowing date", "", showed, GOOD,
		"it would be sown on %s, after the last frost on %s" % [showed, day_words(last_frost)],
		"sown after the last frost"
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
	verdict: int, findings: Array[Dictionary], crop: PlantSpecies,
	last_frost: int, first_frost: int, sow: int
) -> Dictionary:
	var title: String = crop.display_name() if crop != null else "this crop"
	var stated: bool = GrowingSeasonScript.is_stated(last_frost, first_frost)
	var has_time: bool = crop != null and crop.maturity_days > 0
	var has_sow: bool = is_day(sow)
	var first: Dictionary = _first_not(findings, verdict)
	var ready: int = ready_day(sow, crop.maturity_days) if (has_time and has_sow) else 0
	return {
		"verdict": verdict,
		"ok": verdict != UNSUITABLE,
		"certain": verdict == GOOD or verdict == TOLERATED,
		"colour": PlantSuitabilityScript.colour_of(verdict),
		"findings": findings,
		"summary": _summary(verdict, first, title, stated, has_time, has_sow, ready, sow),
		"label": _label(verdict, first, stated, has_time, has_sow),
		"species": title,
		"sow": sow,
		"sow_text": day_words(sow),
		"ready": ready,
		"ready_text": _ready_text(ready),
		"window": sow_window(last_frost, first_frost, crop.maturity_days if crop != null else 0),
	}


static func _first_not(findings: Array[Dictionary], outcome: int) -> Dictionary:
	for finding: Dictionary in findings:
		if int(finding.get("outcome", GOOD)) == outcome:
			return finding
	return findings[0] if not findings.is_empty() else {}


# --- saying it ----------------------------------------------------------------------------


static func _summary(
	verdict: int, first: Dictionary, title: String, stated: bool, has_time: bool, has_sow: bool,
	ready: int, sow: int
) -> String:
	if not stated:
		return "The growing season is not stated, so there is no sowing date to work out for %s." % title
	if not has_time:
		return "%s does not record a time to maturity, so there is nothing to work out." % title
	if not has_sow:
		return "%s has no sowing date to check." % title
	var sow_words: String = day_words(sow)
	match verdict:
		UNSUITABLE:
			return "%s sown on %s would not finish: %s." % [
				title, sow_words, String(first.get("because", ""))
			]
		TOLERATED:
			return "%s may be sown on %s, but %s." % [title, sow_words, String(first.get("because", ""))]
	return "%s sown on %s is %s." % [title, sow_words, _ready_text(ready)]


static func _label(verdict: int, first: Dictionary, stated: bool, has_time: bool, has_sow: bool) -> String:
	if not stated:
		return NO_SEASON
	if not has_time:
		return NO_MATURITY
	if not has_sow:
		return "no sowing date"
	match verdict:
		UNSUITABLE:
			return String(first.get("brief", "ripens too late"))
		TOLERATED:
			return String(first.get("brief", "only just ripens"))
	return "ripens in time"


static func summary_of(result: Dictionary) -> String:
	return String(result.get("summary", ""))


static func label_of(result: Dictionary) -> String:
	return String(result.get("label", ""))


static func colour_from(result: Dictionary) -> Color:
	return PlantSuitabilityScript.colour_from(result)


static func verdict_name(verdict: int) -> String:
	return PlantSuitabilityScript.verdict_name(verdict)


# --- succession ---------------------------------------------------------------------------


## Sow the same crop again every `interval` days, from `first_sow` while the sowing day still has time
## to ripen before the first frost. The sowing days themselves, in order; empty when there is no season,
## no time to maturity, or no day to begin on that ripens in time.
static func sowings(
	first_sow: int, last_frost: int, first_frost: int, maturity_days: int, interval: int
) -> Array[int]:
	var out: Array[int] = []
	if not is_day(first_sow) or not GrowingSeasonScript.is_stated(last_frost, first_frost):
		return out
	if maturity_days <= 0:
		return out
	var every: int = clampi(interval, MIN_INTERVAL, MAX_INTERVAL)
	var last_safe: int = last_sow_day(first_frost, maturity_days)
	var day: int = first_sow
	while is_day(day) and day <= last_safe and out.size() < MAX_SOWINGS:
		out.append(day)
		day += every
	return out


## A succession as a fact: `{stated, sowings, count, first_sow, last_sow, first_ready, last_ready,
## interval, reason}`. `stated` is false and `reason` names why when there is nothing to work out.
static func succession(
	crop: PlantSpecies, last_frost: int, first_frost: int, first_sow: int, interval: int
) -> Dictionary:
	var days: Array[int] = []
	var reason: String = ""
	var maturity: int = crop.maturity_days if crop != null else 0
	if crop == null:
		reason = NO_CROP
	elif not GrowingSeasonScript.is_stated(last_frost, first_frost):
		reason = NO_SEASON
	elif maturity <= 0:
		reason = NO_MATURITY
	else:
		days = sowings(first_sow, last_frost, first_frost, maturity, interval)
		if days.is_empty():
			reason = NO_WINDOW
	var count: int = days.size()
	var first_day: int = days[0] if count > 0 else 0
	var last_day: int = days[count - 1] if count > 0 else 0
	return {
		"stated": count > 0,
		"sowings": days,
		"count": count,
		"first_sow": first_day,
		"last_sow": last_day,
		"first_ready": (first_day + maturity) if count > 0 else 0,
		"last_ready": (last_day + maturity) if count > 0 else 0,
		"interval": clampi(interval, MIN_INTERVAL, MAX_INTERVAL),
		"reason": reason,
	}


## A succession in one sentence: "Sow every 21 days from 20 May: 4 sowings, the last on 1 August,
## cropping from 4 August to 13 October." A single sowing is said as one, and no succession at all
## gives its reason rather than an empty list.
static func succession_text(
	crop: PlantSpecies, last_frost: int, first_frost: int, first_sow: int, interval: int
) -> String:
	var plan: Dictionary = succession(crop, last_frost, first_frost, first_sow, interval)
	var count: int = int(plan["count"])
	if count <= 0:
		return String(plan["reason"])
	if count == 1:
		return "Sow on %s: one sowing, %s." % [
			day_words(int(plan["first_sow"])), _ready_text(int(plan["first_ready"]))
		]
	return "Sow every %d days from %s: %d sowings, the last on %s, cropping from %s to %s." % [
		int(plan["interval"]), day_words(int(plan["first_sow"])), count, day_words(int(plan["last_sow"])),
		day_words(int(plan["first_ready"])), day_words(int(plan["last_ready"])),
	]


# --- the crops of a sowing day ------------------------------------------------------------


## Every food crop in the catalogue, checked against one sowing day, best first: the answer to "what can
## I sow now". One row per edible species, in `{id, title, needed, ready, verdict, colour, summary,
## label}` shape, sorted by verdict and then by botanical name so the list is the same twice running.
##
## Only edible species are listed: a question about what to sow has no row for a boxwood.
static func rows(catalogue: PlantCatalogue, last_frost: int, first_frost: int, sow: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if catalogue == null:
		return out
	for plant: PlantSpecies in catalogue.all():
		if not plant.is_edible():
			continue
		var verdict: Dictionary = check(plant, last_frost, first_frost, sow)
		out.append({
			"id": plant.id,
			"title": plant.display_name(),
			"needed": plant.maturity_text(),
			"ready": String(verdict["ready_text"]),
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


## Those rows as the lines a list control shows: the crop and how the sowing day answers it. The line is
## the row's own `label` rather than a format assembled here, so the list and the summary cannot say two
## different things.
static func row_texts(catalogue: PlantCatalogue, last_frost: int, first_frost: int, sow: int) -> Array[String]:
	var out: Array[String] = []
	for row: Dictionary in rows(catalogue, last_frost, first_frost, sow):
		out.append("%s: %s" % [String(row["title"]), String(row["label"])])
	return out


## How many crops of each verdict a sowing day has, for a summary line.
static func counts(rows_list: Array) -> Dictionary:
	var out: Dictionary = {GOOD: 0, TOLERATED: 0, UNSUITABLE: 0, UNKNOWN: 0}
	for row: Dictionary in rows_list:
		var level: int = int(row.get("verdict", UNKNOWN))
		out[level] = int(out[level]) + 1
	return out


## "9 crops: 5 ripens in time, 1 only just makes it, 2 are too late, 1 cannot be checked." A list with
## no food crop says so rather than reading as a sowing day nothing grows from.
static func describe_rows(rows_list: Array) -> String:
	if rows_list.is_empty():
		return "no crops are recorded in this plant list"
	var held: Dictionary = counts(rows_list)
	var parts: PackedStringArray = PackedStringArray()
	parts.append("%d ripen in time" % int(held.get(GOOD, 0)))
	var thin: int = int(held.get(TOLERATED, 0))
	if thin > 0:
		parts.append("%d only just make it" % thin)
	var wrong: int = int(held.get(UNSUITABLE, 0))
	if wrong > 0:
		parts.append("%d are too late" % wrong)
	var unknown: int = int(held.get(UNKNOWN, 0))
	if unknown > 0:
		parts.append("%d cannot be checked" % unknown)
	return "%d crop%s: %s." % [
		rows_list.size(), "" if rows_list.size() == 1 else "s", ", ".join(parts)
	]