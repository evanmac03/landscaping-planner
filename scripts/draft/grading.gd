class_name Grading
extends RefCounted
## The ground's own heights: **spot levels**, **contours** and **slope arrows**.
##
## The two layers for this have been in the preset set since the layer set was written - `200-GRADE-CONT`
## and `201-GRADE-SPOT` - and until now nothing authored them: a DXF or a plat could put contours on the
## plan and no command in this program could draw one. This is that command's module.
##
## ## What is a fact, what is arithmetic, and what is a check
##
## * A **spot level** is a *stated fact*: a number at a place. It is never derived from anything and
##   nothing here invents one. A level that is not a number is refused by name rather than read as zero,
##   because zero is a real elevation above a real datum.
## * A **contour** is a line at one level. Two contours at the same level are one line drawn twice, and
##   two contours of different levels crossing each other cannot both be right - both are things the
##   drawing is asked about rather than things this module has an opinion about.
## * A **fall** is arithmetic on two levels and a run: a percentage with no run between it and the next
##   level is a number about nothing, so it is refused rather than shown. The sign convention is a
##   designer's: **a positive fall is downhill** from the first point to the second, so a `2.0%` arrow
##   runs down its own direction and a `-2.0%` one runs up it.
## * A **slope arrow** is an *intention* - this paving is to fall 2% - where a spot level is what the
##   ground *is*. Where both are known the module **compares** them and names the disagreement; it never
##   quietly prefers one. An arrow with no spot at its ends is not wrong, it is unchecked, and the
##   report says which of the two it is.
##
## ## What this does not do
##
## The garden's 3D ground is flat and stays flat: a level here is a fact about the plan rather than a
## surface the app moves geometry onto. Grading a site properly is a surface - a TIN, a cut-and-fill
## volume, a drainage analysis - and half of one would be worse than none. What this does is what a plan
## is asked for: where the levels are, what the ground falls between them, and whether the numbers on
## the drawing agree with each other.
##
## Elevations are metres above **whatever benchmark the person designing is using**. The module never
## asks and never states a datum, because a datum belongs to a survey rather than to a garden plan - and
## nothing here cares whether `102.35` is a metre above a sea, a kerb or a front step.

const Geom := preload("res://scripts/draft/geom2d.gd")
const LayerSetScript := preload("res://scripts/draft/layer_set.gd")
const EntityScript := preload("res://scripts/draft/draft_entity.gd")
const StyleScript := preload("res://scripts/draft/line_style.gd")

const SPOT := "spot"
const CONTOUR := "contour"
const SLOPE := "slope"
const KINDS: Array[String] = [SPOT, CONTOUR, SLOPE]

## What each kind is called in a sentence, one place so a button, a menu line and a report cannot
## call the same thing three different names.
const KIND_NAMES := {
	SPOT: "spot level",
	CONTOUR: "contour",
	SLOPE: "slope arrow",
}

## And which layer each kind lands on. A slope arrow has a layer of its own rather than sharing the
## contour layer, because the two are read for different things: a contour states a level and an arrow
## states a fall, and a drawing that has to be switched off one at a time needs them apart.
##
## A function rather than a table, because a constant cannot be built out of another script's constants
## in GDScript - and the layer names are the layer set's to own.
static func layer_for(kind: String) -> StringName:
	if kind == SPOT:
		return LayerSetScript.GRADING_SPOT
	if kind == SLOPE:
		return LayerSetScript.GRADING_SLOPE
	return LayerSetScript.GRADING_CONTOUR

## The spot's mark and the arrow's head are drawn at a *paper* size, so a plan and its plot agree
## about how big a level mark is the same way a dimension's arrowheads do.
const SPOT_SYMBOL_MM := 1.6
const SPOT_MIN_RADIUS := 0.02
const LABEL_MM := 2.5
const ARROW_MM := 3.0

## How far apart two levels have to be to be two levels, in metres. 10 mm: the same distance the
## tracing stance fits a line to, and far below any fall anybody designs to.
const LEVEL_TOLERANCE := 0.01
## A spot this close to a contour is *standing on* it, and its level is expected to agree with it.
const ON_CONTOUR_M := 0.10
## A spot this close to an end of an arrow is at that end, so the arrow can be checked against it.
const END_TOLERANCE_M := 0.35
## A run shorter than this has no fall to state: a percentage over nothing is a divide by zero.
const MIN_RUN_M := 0.05
## How far a stated fall may be from the fall the levels work out to, in percentage points. A tenth of
## a percent: a drawing that rounds 2.04% to 2% is agreeing with itself, and one that writes 3% where
## the levels say 6% is not.
const SLOPE_AGREEMENT_PERCENT := 0.1
## The steepest fall a slope arrow may state, in percent. 100% is one in one - a 45 degree slope - and
## a garden path steeper than that is a retaining wall, so a number past it is a mistyped one.
const MAX_PERCENT := 100.0
const MIN_CONTOUR_POINTS := 2
const MAX_RECORDS := 400

## Every entity this module draws carries what it stands for, so taking a record off the drawing can
## find every mark and every label it put there - and so a mark cannot be mistaken for geometry the
## designer drew by hand.
const META_KIND := "grading_kind"
const META_ID := "grading_id"


# --- kinds ---------------------------------------------------------------------------


static func is_kind(value: String) -> bool:
	return KINDS.has(value)


## The words for a kind: "spot level", "contour", "slope arrow".
static func kind_name(kind: String) -> String:
	return String(KIND_NAMES.get(kind, kind))


static func kind_names() -> Array[String]:
	var out: Array[String] = []
	for kind: String in KINDS:
		out.append(kind_name(kind))
	return out


## The kind a name shown in a drop-down stands for, or "" when nothing does.
static func kind_for_name(shown: String) -> String:
	for kind: String in KINDS:
		if kind_name(kind) == shown:
			return kind
	return ""


# --- the records ----------------------------------------------------------------------


## The whole record set, as the document holds it.
static func empty_set() -> Dictionary:
	return {"spots": [], "contours": [], "slopes": []}


static func make_spot(id: int, at: Vector2, level: float) -> Dictionary:
	return {"id": id, "at": at, "level": level}


static func make_contour(id: int, level: float, points: PackedVector2Array,
		closed: bool = false) -> Dictionary:
	return {"id": id, "level": level, "points": points, "closed": closed}


static func make_slope(id: int, a: Vector2, b: Vector2, percent: float) -> Dictionary:
	return {"id": id, "a": a, "b": b, "percent": percent}


## The records of one kind, as an Array of Dictionaries. The set always holds all three keys, so a
## caller never has to ask whether it does.
static func records_of(records: Dictionary, kind: String) -> Array:
	var held = records.get(_key_for(kind), [])
	return held if held is Array else []


static func spots_of(records: Dictionary) -> Array:
	return records_of(records, SPOT)


static func contours_of(records: Dictionary) -> Array:
	return records_of(records, CONTOUR)


static func slopes_of(records: Dictionary) -> Array:
	return records_of(records, SLOPE)


static func count_of(records: Dictionary) -> int:
	return spots_of(records).size() + contours_of(records).size() + slopes_of(records).size()


static func record_for(records: Dictionary, kind: String, id: int) -> Dictionary:
	for entry in records_of(records, kind):
		var record: Dictionary = entry
		if int(record.get("id", 0)) == id:
			return record
	return {}


## The id the next record of a kind gets: one past the highest in use, never the count. A record that
## was taken off the drawing must not have its number handed to a different one, because the entities
## it drew have gone with it and the next mark would inherit nothing but confusion.
static func next_id(records: Dictionary, kind: String) -> int:
	var highest := 0
	for entry in records_of(records, kind):
		highest = maxi(highest, int((entry as Dictionary).get("id", 0)))
	return highest + 1


static func add_record(records: Dictionary, kind: String, record: Dictionary) -> bool:
	if not is_kind(kind) or count_of(records) >= MAX_RECORDS:
		return false
	(records[_key_for(kind)] as Array).append(record)
	return true


static func remove_record(records: Dictionary, kind: String, id: int) -> bool:
	var held: Array = records_of(records, kind)
	for index in held.size():
		var record: Dictionary = held[index]
		if int(record.get("id", 0)) == id:
			held.remove_at(index)
			return true
	return false


# --- levels and falls -----------------------------------------------------------------


## A level in words, in the drawing's own units. Every level anywhere - on the plan, in the report, in
## the schedule - comes through here, so a plan cannot end up with two spellings of one height.
static func level_words(level: float, units: DraftUnits = null) -> String:
	return DraftUnits.or_default(units).format_length(level)


## A fall in words without its run: "falling 2.5% (1 in 40)".
##
## The ratio is the other way a designer says the same thing, and it is not the same number: 2.5% is
## 1 in 40. Zero is "flat" rather than "0.0% (1 in infinity)", which is a sentence about nothing.
static func percent_words(percent: float) -> String:
	if is_nan(percent) or not is_finite(percent):
		return "no fall"
	if absf(percent) < 0.05:
		return "flat"
	var direction := "falling" if percent > 0.0 else "rising"
	return "%s %s%% (1 in %s)" % [direction, _number(absf(percent), 1), _number(100.0 / absf(percent), 1)]


## A fall with the run it happens over: "falling 2.5% (1 in 40) over 6.20 m".
static func fall_words(percent: float, run: float, units: DraftUnits = null) -> String:
	return "%s over %s" % [percent_words(percent),
		DraftUnits.or_default(units).format_length(run)]


## The level of the spot standing at a point, if one does.
##
## This is how an arrow's ends and a contour's line find their levels: a spot within
## `END_TOLERANCE_M` of the point *is* at that point, because that is how a designer sets one out - a
## marker at each end of the arrow, and no arithmetic about the middle.
static func level_at(point: Vector2, spots: Array, tolerance: float = END_TOLERANCE_M) -> Dictionary:
	var best := {}
	var best_distance := tolerance
	for entry in spots:
		var spot: Dictionary = entry
		var at := Vector2(spot.get("at", Vector2.ZERO))
		var distance := at.distance_to(point)
		if distance <= best_distance:
			best = spot
			best_distance = distance
	if best.is_empty():
		return {"ok": false, "reason": "no spot level stands within %s of that point"
			% DraftUnits.length_words(tolerance)}
	var level := float(best.get("level", NAN))
	if _bad_level(level):
		return {"ok": false, "reason": "the spot level there is not a number"}
	return {"ok": true, "reason": "", "level": level, "spot": best}


## The fall from one point to another, worked out from the spot levels at them.
##
## Returns `{ok, reason, run, rise, percent, words}`. `rise` is positive downhill, and the fall is
## `rise / run`, which is the number a designer writes on the arrow.
static func fall_between(a: Vector2, b: Vector2, spots: Array) -> Dictionary:
	var run := a.distance_to(b)
	if run < MIN_RUN_M:
		return _no_fall("two points closer than %s apart have no fall between them"
			% DraftUnits.length_words(MIN_RUN_M))
	var from := level_at(a, spots)
	if not bool(from["ok"]):
		return _no_fall("the level at %s: %s" % [_point_words(a), String(from["reason"])])
	var to := level_at(b, spots)
	if not bool(to["ok"]):
		return _no_fall("the level at %s: %s" % [_point_words(b), String(to["reason"])])
	var rise := float(from["level"]) - float(to["level"])
	var percent := rise / run * 100.0
	return {
		"ok": true, "reason": "", "run": run, "rise": rise, "percent": percent,
		"from_level": float(from["level"]), "to_level": float(to["level"]),
	}


## The lowest and the highest spot level on the drawing, and how far the ground runs between them.
static func high_low(spots: Array) -> Dictionary:
	var low := NAN
	var high := NAN
	var low_at := Vector2.ZERO
	var high_at := Vector2.ZERO
	var stated := 0
	for entry in spots:
		var spot: Dictionary = entry
		var level := float(spot.get("level", NAN))
		if _bad_level(level):
			continue
		stated += 1
		var at := Vector2(spot.get("at", Vector2.ZERO))
		if is_nan(low) or level < low:
			low = level
			low_at = at
		if is_nan(high) or level > high:
			high = level
			high_at = at
	if stated == 0:
		return {"ok": false, "reason": "no spot level on this drawing states a number",
			"statements": 0}
	return {
		"ok": true, "reason": "", "statements": stated,
		"low": low, "high": high, "fall": high - low,
		"low_at": low_at, "high_at": high_at,
	}


## The steepest fall between any two spot levels, the ground's total drop, and how many of each kind
## of record the drawing holds. The figures the Site menu line and the report are made of.
static func measurement(records: Dictionary, units: DraftUnits = null) -> Dictionary:
	var spots := spots_of(records)
	var levels := high_low(spots)
	var steepest := _steepest(spots)
	var figures := {
		"spots": spots.size(),
		"contours": contours_of(records).size(),
		"slopes": slopes_of(records).size(),
		"stated_levels": int(levels.get("statements", 0)),
		"ok": bool(levels["ok"]),
		"low": float(levels.get("low", NAN)),
		"high": float(levels.get("high", NAN)),
		"fall": float(levels.get("fall", NAN)),
		"low_words": "",
		"high_words": "",
		"fall_words": "",
		"steepest": steepest,
	}
	if bool(levels["ok"]):
		figures["low_words"] = level_words(float(levels["low"]), units)
		figures["high_words"] = level_words(float(levels["high"]), units)
		figures["fall_words"] = DraftUnits.or_default(units).format_length(float(levels["fall"]))
	return figures


# --- the check ------------------------------------------------------------------------


## Everything the drawing is asked about its own grading. Returns
## `{ok, findings, notes, measurement}`.
##
## A **finding** is something wrong: a contour crossed by another, two contours at one level, a spot
## that disagrees with the contour it stands on, an arrow that contradicts the levels at its ends, a
## level that is not a number. A **note** is something worth knowing: how far the ground runs, how
## steep the steepest fall is, and which arrows cannot be checked. The two are separate because "this
## is wrong" and "this is unchecked" are different sentences and a designer acts on them differently.
static func check(records: Dictionary, units: DraftUnits = null) -> Dictionary:
	var findings: Array[String] = []
	var notes: Array[String] = []
	var spots := spots_of(records)
	var contours := contours_of(records)
	var slopes := slopes_of(records)

	for entry in spots:
		var spot: Dictionary = entry
		if _bad_level(float(spot.get("level", NAN))):
			findings.append("the spot level at %s is not a number"
				% _point_words(Vector2(spot.get("at", Vector2.ZERO))))

	# Two contours at one level: a level is a line, and two of them are one line drawn twice.
	for first in contours.size():
		for second in range(first + 1, contours.size()):
			var a: Dictionary = contours[first]
			var b: Dictionary = contours[second]
			var a_level := float(a.get("level", NAN))
			var b_level := float(b.get("level", NAN))
			if _bad_level(a_level) or _bad_level(b_level):
				findings.append("a contour on this drawing states no level")
				continue
			if absf(a_level - b_level) <= LEVEL_TOLERANCE:
				findings.append("two contours are both at %s: a level is one line"
					% level_words(a_level, units))
				continue
			# Contours of different levels crossing cannot both be right.
			var crossing := _crossing(a, b)
			if crossing.is_finite():
				findings.append("the %s and the %s contours cross each other at %s"
					% [level_words(a_level, units), level_words(b_level, units),
						_point_words(crossing)])

	# A contour has to be a line, and a spot standing on one is expected to agree with it.
	for entry in contours:
		var contour: Dictionary = entry
		var points: PackedVector2Array = _points_of(contour)
		var level := float(contour.get("level", NAN))
		if points.size() < MIN_CONTOUR_POINTS:
			findings.append("a contour at %s is not a line" % level_words(level, units))
			continue
		if _bad_level(level):
			continue
		for spot_entry in spots:
			var spot: Dictionary = spot_entry
			var at := Vector2(spot.get("at", Vector2.ZERO))
			var spot_level := float(spot.get("level", NAN))
			if _bad_level(spot_level) or not _stands_on(at, points):
				continue
			if absf(spot_level - level) > LEVEL_TOLERANCE:
				findings.append("the spot at %s stands on the %s contour"
					% [level_words(spot_level, units), level_words(level, units)])

	# An arrow is checked against the levels at its own ends, and says so when there are none.
	for entry in slopes:
		var slope: Dictionary = entry
		var stated := float(slope.get("percent", NAN))
		var a := Vector2(slope.get("a", Vector2.ZERO))
		var b := Vector2(slope.get("b", Vector2.ZERO))
		var run := a.distance_to(b)
		if run < MIN_RUN_M:
			findings.append("a slope arrow at %s has no length, so it states no fall"
				% _point_words(a))
			continue
		if _bad_level(stated):
			findings.append("the slope arrow at %s states no fall" % _point_words(a))
			continue
		var measured := fall_between(a, b, spots)
		if not bool(measured["ok"]):
			notes.append("the arrow at %s is unchecked: %s"
				% [_point_words(a), String(measured["reason"])])
			continue
		if absf(float(measured["percent"]) - stated) > SLOPE_AGREEMENT_PERCENT:
			findings.append("the arrow at %s says %s and the levels at its ends say %s"
				% [_point_words(a), percent_words(stated), percent_words(float(measured["percent"]))])

	var figures := measurement(records, units)
	if bool(figures["ok"]):
		notes.append("the levels run from %s to %s, %s apart" % [
			String(figures["low_words"]), String(figures["high_words"]), String(figures["fall_words"])])
	else:
		notes.append("no spot level on this drawing states a number")
	var steepest: Dictionary = figures["steepest"]
	if bool(steepest.get("ok", false)):
		notes.append("the steepest fall between two spot levels is %s"
			% fall_words(float(steepest["percent"]), float(steepest["run"]), units))

	return {"ok": findings.is_empty(), "findings": findings, "notes": notes, "measurement": figures}


# --- words and rows -------------------------------------------------------------------


## One line saying what the drawing is graded with, or that nothing is.
static func summary(records: Dictionary, units: DraftUnits = null) -> String:
	var figures := measurement(records, units)
	if count_of(records) == 0:
		return "nothing on this drawing is graded yet"
	var parts: Array[String] = []
	# Only the kinds this drawing actually has: "2 spot levels, no contours and a slope arrow" is a
	# sentence about two absences, and a line that has to be read twice to find out what is on the
	# drawing is a line that is not doing its job.
	for pair: Array in [
		[int(figures["spots"]), "spot level"],
		[int(figures["contours"]), "contour"],
		[int(figures["slopes"]), "slope arrow"],
	]:
		if int(pair[0]) > 0:
			parts.append(_count_words(int(pair[0]), String(pair[1])))
	var line := "%s on this drawing" % _join_words(parts)
	if bool(figures["ok"]):
		line += ", running from %s to %s" % [String(figures["low_words"]), String(figures["high_words"])]
	return line


## One line per record, the way a schedule reads.
static func schedule(records: Dictionary, units: DraftUnits = null) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for entry in spots_of(records):
		var spot: Dictionary = entry
		var level := float(spot.get("level", NAN))
		var at := Vector2(spot.get("at", Vector2.ZERO))
		rows.append({
			"kind": SPOT, "kind_name": kind_name(SPOT), "id": int(spot.get("id", 0)),
			"level": level, "level_words": level_words(level, units),
			"at": at, "at_words": _point_words(at),
			"text": "%s   %s" % [level_words(level, units), _point_words(at)],
		})
	for entry in contours_of(records):
		var contour: Dictionary = entry
		var level := float(contour.get("level", NAN))
		var points: PackedVector2Array = _points_of(contour)
		var length := Geom.polygon_perimeter(points, bool(contour.get("closed", false)))
		rows.append({
			"kind": CONTOUR, "kind_name": kind_name(CONTOUR), "id": int(contour.get("id", 0)),
			"level": level, "level_words": level_words(level, units),
			"length": length,
			"text": "%s   %s   %s" % [level_words(level, units),
				_count_words(points.size(), "point"), DraftUnits.or_default(units).format_length(length)],
		})
	for entry in slopes_of(records):
		var slope: Dictionary = entry
		var a := Vector2(slope.get("a", Vector2.ZERO))
		var b := Vector2(slope.get("b", Vector2.ZERO))
		var percent := float(slope.get("percent", NAN))
		rows.append({
			"kind": SLOPE, "kind_name": kind_name(SLOPE), "id": int(slope.get("id", 0)),
			"percent": percent, "run": a.distance_to(b),
			"text": "%s   over %s   at %s" % [percent_words(percent),
				DraftUnits.or_default(units).format_length(a.distance_to(b)), _point_words(a)],
		})
	return rows


static func schedule_lines(records: Dictionary, units: DraftUnits = null) -> Array[String]:
	var out: Array[String] = []
	for row in schedule(records, units):
		out.append(String(row["text"]))
	return out


## One record in words, the way the list on the page reads it.
static func record_words(kind: String, record: Dictionary, units: DraftUnits = null) -> String:
	if kind == SPOT:
		return "%s at %s" % [level_words(float(record.get("level", NAN)), units),
			_point_words(Vector2(record.get("at", Vector2.ZERO)))]
	if kind == CONTOUR:
		return "%s contour, %s" % [level_words(float(record.get("level", NAN)), units),
			_count_words(_points_of(record).size(), "point")]
	var a := Vector2(record.get("a", Vector2.ZERO))
	var b := Vector2(record.get("b", Vector2.ZERO))
	return "%s %s over %s" % [kind_name(SLOPE), percent_words(float(record.get("percent", NAN))),
		DraftUnits.or_default(units).format_length(a.distance_to(b))]


## One line naming the drawing's grading, for a log or a demonstration.
static func describe(records: Dictionary, units: DraftUnits = null) -> String:
	if count_of(records) == 0:
		return "no grading"
	return "%s: %s" % [summary(records, units), "; ".join(schedule_lines(records, units))]


# --- the marks on the plan ------------------------------------------------------------


## Every entity a record puts on the drawing: the mark and its label. One list, so nothing that
## stamps a record can stamp half of one.
static func entities_for(kind: String, record: Dictionary, plot_scale: float,
		units: DraftUnits = null) -> Array:
	if kind == SPOT:
		return spot_entities(record, plot_scale, units)
	if kind == CONTOUR:
		return contour_entities(record, plot_scale, units)
	if kind == SLOPE:
		return slope_entities(record, plot_scale, units)
	return []


## A spot level: a small circle at the point and the level beside it.
##
## The mark is drawn at a paper size rather than at a ground size, because a spot level is a mark on a
## drawing rather than a thing in a garden - the same reason a fixture is drawn at a paper size.
static func spot_entities(spot: Dictionary, plot_scale: float, units: DraftUnits = null) -> Array:
	var id := int(spot.get("id", 0))
	var at := Vector2(spot.get("at", Vector2.ZERO))
	var out: Array = []
	var mark := EntityScript.make_circle(at, maxf(SPOT_MIN_RADIUS, _paper_metres(SPOT_SYMBOL_MM, plot_scale)))
	_stamp(mark, SPOT, id)
	out.append(mark)
	var lift := _paper_metres(LABEL_MM, plot_scale)
	var label := _label(at + Vector2(lift * 0.9, -lift * 0.5),
		level_words(float(spot.get("level", NAN)), units), SPOT, id, plot_scale)
	out.append(label)
	return out


## A contour: the line, and its level written at the middle of it.
static func contour_entities(contour: Dictionary, plot_scale: float, units: DraftUnits = null) -> Array:
	var id := int(contour.get("id", 0))
	var points: PackedVector2Array = _points_of(contour)
	if points.size() < MIN_CONTOUR_POINTS:
		return []
	var out: Array = []
	var line := EntityScript.make_polyline(points, bool(contour.get("closed", false)))
	_stamp(line, CONTOUR, id)
	out.append(line)
	var lift := _paper_metres(LABEL_MM, plot_scale)
	var middle: Vector2 = Geom.point_along(points, 0.5)
	var label := _label(middle + Vector2(lift * 0.4, -lift * 0.6),
		level_words(float(contour.get("level", NAN)), units), CONTOUR, id, plot_scale)
	out.append(label)
	return out


## A slope arrow: the line along the fall, a head at the low end, and the fall written beside it.
##
## The head is at the **second** point because the sign convention says the first point is the top:
## an arrow that runs downhill draws the way water would, which is the reading a plan wants.
static func slope_entities(slope: Dictionary, plot_scale: float, _units: DraftUnits = null) -> Array:
	var id := int(slope.get("id", 0))
	var a := Vector2(slope.get("a", Vector2.ZERO))
	var b := Vector2(slope.get("b", Vector2.ZERO))
	if a.distance_to(b) < MIN_RUN_M:
		return []
	var out: Array = []
	var shaft := EntityScript.make_line(a, b)
	_stamp(shaft, SLOPE, id)
	out.append(shaft)
	var head := _arrow_head(a, b, _paper_metres(ARROW_MM, plot_scale))
	var barbs := EntityScript.make_polyline(head, false)
	_stamp(barbs, SLOPE, id)
	out.append(barbs)
	var lift := _paper_metres(LABEL_MM, plot_scale)
	var middle := (a + b) * 0.5
	var label := _label(middle + Vector2(lift * 0.5, -lift * 0.8),
		percent_words(float(slope.get("percent", NAN))), SLOPE, id, plot_scale)
	out.append(label)
	return out


static func is_grading_entity(entity) -> bool:
	return entity != null and String(entity.meta.get(META_KIND, "")) != ""


static func kind_of_entity(entity) -> String:
	return String(entity.meta.get(META_KIND, "")) if entity != null else ""


static func id_of_entity(entity) -> int:
	return int(entity.meta.get(META_ID, 0)) if entity != null else 0


# --- persistence ----------------------------------------------------------------------


## The set as a plain dictionary. Points are written as flat numbers, because a `PackedVector2Array`
## has no shape a JSON file can hold - the same reason a zone's ring is written flat.
static func to_dict(records: Dictionary) -> Dictionary:
	var spots: Array = []
	for entry in spots_of(records):
		var spot: Dictionary = entry
		var at := Vector2(spot.get("at", Vector2.ZERO))
		spots.append({"id": int(spot.get("id", 0)), "at": [at.x, at.y],
			"level": float(spot.get("level", NAN))})
	var contours: Array = []
	for entry in contours_of(records):
		var contour: Dictionary = entry
		contours.append({
			"id": int(contour.get("id", 0)),
			"level": float(contour.get("level", NAN)),
			"closed": bool(contour.get("closed", false)),
			"points": _flat(_points_of(contour)),
		})
	var slopes: Array = []
	for entry in slopes_of(records):
		var slope: Dictionary = entry
		var a := Vector2(slope.get("a", Vector2.ZERO))
		var b := Vector2(slope.get("b", Vector2.ZERO))
		slopes.append({"id": int(slope.get("id", 0)), "a": [a.x, a.y], "b": [b.x, b.y],
			"percent": float(slope.get("percent", NAN))})
	return {"spots": spots, "contours": contours, "slopes": slopes}


## A set read back out of a file. A record that is not one is **dropped rather than invented**, like a
## zone that is not a zone: a level that is not a number is the one thing that survives, because a
## spot with no level is a mark on the drawing that a person has to be told about rather than one this
## can quietly remove.
static func from_dict(data: Dictionary) -> Dictionary:
	var records := empty_set()
	if not (data is Dictionary):
		return records
	records["spots"] = _spots_from(data.get("spots", []))
	records["contours"] = _contours_from(data.get("contours", []))
	records["slopes"] = _slopes_from(data.get("slopes", []))
	return records


## A level out of a file. A level that is not a number is **NAN rather than zero**: a spot with no
## level is a mark on the drawing a person has to be told about, and reading "high" as 0.00 m would be
## this program quietly inventing an elevation. The same goes for a slope's percent.
static func _level_from(held) -> float:
	if held is float or held is int:
		return float(held)
	return NAN


static func _spots_from(held) -> Array:
	var out: Array = []
	if not (held is Array):
		return out
	for entry in (held as Array):
		if not (entry is Dictionary):
			continue
		var record: Dictionary = entry
		if not (record.get("id") is float or record.get("id") is int):
			continue
		out.append(make_spot(int(record["id"]), _vector(record.get("at", null)),
			_level_from(record.get("level", null))))
	return out


static func _contours_from(held) -> Array:
	var out: Array = []
	if not (held is Array):
		return out
	for entry in (held as Array):
		if not (entry is Dictionary):
			continue
		var record: Dictionary = entry
		if not (record.get("id") is float or record.get("id") is int):
			continue
		var points := _points_from(record.get("points", null))
		if points.size() < MIN_CONTOUR_POINTS:
			continue
		out.append(make_contour(int(record["id"]), _level_from(record.get("level", null)),
			points, bool(record.get("closed", false))))
	return out


static func _slopes_from(held) -> Array:
	var out: Array = []
	if not (held is Array):
		return out
	for entry in (held as Array):
		if not (entry is Dictionary):
			continue
		var record: Dictionary = entry
		if not (record.get("id") is float or record.get("id") is int):
			continue
		var a := _vector(record.get("a", null))
		var b := _vector(record.get("b", null))
		if a.distance_to(b) < MIN_RUN_M:
			continue
		out.append(make_slope(int(record["id"]), a, b, _level_from(record.get("percent", null))))
	return out


# --- private --------------------------------------------------------------------------


## The key a kind's records are held under.
static func _key_for(kind: String) -> String:
	if kind == CONTOUR:
		return "contours"
	if kind == SLOPE:
		return "slopes"
	return "spots"


static func _bad_level(level: float) -> bool:
	return is_nan(level) or not is_finite(level)


static func _no_fall(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "run": 0.0, "rise": NAN, "percent": NAN}


## The steepest fall between any two spot levels, or an empty answer when there are fewer than two.
static func _steepest(spots: Array) -> Dictionary:
	var best := {}
	for first in spots.size():
		for second in range(first + 1, spots.size()):
			var a := Vector2((spots[first] as Dictionary).get("at", Vector2.ZERO))
			var b := Vector2((spots[second] as Dictionary).get("at", Vector2.ZERO))
			var fall := fall_between(a, b, spots)
			if not bool(fall["ok"]):
				continue
			if best.is_empty() or absf(float(fall["percent"])) > absf(float(best["percent"])):
				best = fall
	if best.is_empty():
		return {"ok": false, "reason": "there are not two spot levels to measure a fall between"}
	return best


## Where two contours cross, or Vector2.INF when they do not. A crossing exactly on a shared end is
## still a crossing: two lines of different levels meeting at a point is the same defect as cutting
## through each other.
static func _crossing(a: Dictionary, b: Dictionary) -> Vector2:
	var first: PackedVector2Array = _points_of(a)
	var second: PackedVector2Array = _points_of(b)
	for i in _segments(first, bool(a.get("closed", false))):
		for j in _segments(second, bool(b.get("closed", false))):
			var hit := Geom.segment_segment(first[i], first[i + 1], second[j], second[j + 1])
			if bool(hit.get("hit", false)):
				return Vector2(hit["point"])
	return Vector2.INF


## A spot is standing on a contour when it is within `ON_CONTOUR_M` of one of its segments.
static func _stands_on(at: Vector2, points: PackedVector2Array) -> bool:
	for index in _segments(points, false):
		if Geom.distance_to_segment(at, points[index], points[index + 1]) <= ON_CONTOUR_M:
			return true
	return false


## The starting index of every segment of a line, which is what keeps a closed line's last segment
## from being forgotten in two different places.
static func _segments(points: PackedVector2Array, closed: bool) -> Array:
	var out: Array = []
	for index in maxi(points.size() - 1, 0):
		out.append(index)
	if closed and points.size() > 2:
		out.append(points.size() - 1)
	return out


## The two barbs of an arrowhead at `tip`, coming back along the shaft.
static func _arrow_head(from: Vector2, tip: Vector2, size: float) -> PackedVector2Array:
	var back := (from - tip).normalized()
	if back == Vector2.ZERO:
		back = Vector2.LEFT
	var sideways := Vector2(back.y, -back.x)
	return PackedVector2Array([
		tip + (back + sideways).normalized() * size,
		tip,
		tip + (back - sideways).normalized() * size,
	])


## How many model metres one paper millimetre is at a plot scale. 1:100 means a paper millimetre is
## 100 mm of ground.
static func _paper_metres(paper_mm: float, plot_scale: float) -> float:
	return StyleScript.model_width_m(paper_mm, plot_scale)


## A text entity this module owns, sized in paper millimetres the way every other note is. The label
## is stored upright: a level written along a contour reads well on a plot and this program's own plan
## draws every label squarely, and the plan and the sheet are not allowed to disagree about a note.
static func _label(at: Vector2, text: String, kind: String, id: int, _plot_scale: float) -> DraftEntity:
	var entity := EntityScript.make_text(at, text)
	entity.meta["height"] = LABEL_MM
	_stamp(entity, kind, id)
	return entity


static func _stamp(entity: DraftEntity, kind: String, id: int) -> void:
	entity.layer = layer_for(kind)
	entity.meta[META_KIND] = kind
	entity.meta[META_ID] = id


## A number in words: a whole number reads as itself, so "3 points" is not "3.0 points", and anything
## else is rounded to the digits asked for.
static func _number(value: float, digits: int) -> String:
	if is_nan(value) or not is_finite(value):
		return "?"
	if is_equal_approx(value, roundf(value)) and absf(value) < 1.0e9:
		return str(int(roundf(value)))
	return String.num(value, digits)


static func _point_words(at: Vector2) -> String:
	return "(%s, %s)" % [_number(at.x, 2), _number(at.y, 2)]


## "a spot level" or "3 spot levels".
static func _count_words(count: int, noun: String) -> String:
	if count <= 0:
		return "no %ss" % noun
	if count == 1:
		return "a %s" % noun
	return "%d %ss" % [count, noun]


static func _join_words(parts: Array[String]) -> String:
	if parts.size() <= 1:
		return "" if parts.is_empty() else parts[0]
	return "%s and %s" % [", ".join(parts.slice(0, parts.size() - 1)), parts[parts.size() - 1]]


static func _points_of(record: Dictionary) -> PackedVector2Array:
	var held = record.get("points", null)
	return held if held is PackedVector2Array else PackedVector2Array()


static func _flat(points: PackedVector2Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for point: Vector2 in points:
		out.append(point.x)
		out.append(point.y)
	return out


## A flat run of numbers back into points, refusing an odd count rather than dropping the last one.
static func _points_from(held) -> PackedVector2Array:
	var out := PackedVector2Array()
	if not (held is PackedFloat64Array or held is Array):
		return out
	var flat := PackedFloat64Array(held)
	if flat.size() % 2 != 0:
		return PackedVector2Array()
	for index in range(0, flat.size(), 2):
		out.append(Vector2(flat[index], flat[index + 1]))
	return out


static func _vector(held) -> Vector2:
	if held is Vector2:
		return held
	if held is PackedFloat64Array or held is Array:
		var flat := PackedFloat64Array(held)
		if flat.size() >= 2:
			return Vector2(flat[0], flat[1])
	return Vector2.ZERO