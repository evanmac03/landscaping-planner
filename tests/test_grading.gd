extends Node
## The ground's own heights: spot levels, contours and slope arrows.
##
## This is the module on its own - the records, the arithmetic, the check and the marks those records
## put on the plan. The tools that pick the points are tested in `test_grading_tools.gd`, the page in
## `test_grading_window.gd`, and the join to the menu in `test_hud_grading.gd`.
##
## The rule under most of what is here: **a level is a stated fact, a fall is arithmetic on two levels
## and a run, and a slope arrow is an intention**. An arrow that contradicts the levels it is drawn
## between is the whole reason the check exists, and an arrow with no levels at its ends is *unchecked*
## rather than wrong - which is why findings and notes are two lists and not one.

const GradingScript := preload("res://scripts/draft/grading.gd")
const LayerSetScript := preload("res://scripts/draft/layer_set.gd")
const EntityScript := preload("res://scripts/draft/draft_entity.gd")
const UnitsScript := preload("res://scripts/draft/units.gd")

const SPOT := GradingScript.SPOT
const CONTOUR := GradingScript.CONTOUR
const SLOPE := GradingScript.SLOPE


# --- helpers --------------------------------------------------------------------------


## A straight contour from (0, y) across to (x, y).
func _flat_contour(id: int, level: float, y: float, x: float = 10.0) -> Dictionary:
	return GradingScript.make_contour(id, level, PackedVector2Array([Vector2(0.0, y), Vector2(x, y)]))


## A drawing with a level at each end of a six metre run: the top at 102.35, the bottom at 101.95, so
## the ground falls 0.40 m over 6 m = 6.667%.
func _sloping_set() -> Dictionary:
	var set := GradingScript.empty_set()
	GradingScript.add_record(set, SPOT, GradingScript.make_spot(1, Vector2.ZERO, 102.35))
	GradingScript.add_record(set, SPOT, GradingScript.make_spot(2, Vector2(6.0, 0.0), 101.95))
	return set


func _findings(set: Dictionary) -> Array:
	return GradingScript.check(set).get("findings", [])


func _notes(set: Dictionary) -> Array:
	return GradingScript.check(set).get("notes", [])


## True when any finding contains `part`, so a test can look for the sentence rather than for the whole
## of it - the wording of a place or a number is not what this file is pinning.
func _some_finding_has(findings: Array, part: String) -> bool:
	for one in findings:
		if String(one).contains(part):
			return true
	return false


func _some_note_has(notes: Array, part: String) -> bool:
	for one in notes:
		if String(one).contains(part):
			return true
	return false


# --- the kinds ---------------------------------------------------------------------------


func test_every_kind_has_its_own_layer_and_its_own_noun() -> void:
	assert(GradingScript.KINDS == [SPOT, CONTOUR, SLOPE], str(GradingScript.KINDS))
	assert(GradingScript.KIND_NAMES.size() == 3, "every kind is called something")
	assert(GradingScript.kind_names() == ["spot level", "contour", "slope arrow"],
		str(GradingScript.kind_names()))
	for kind: String in GradingScript.KINDS:
		assert(GradingScript.is_kind(kind), kind)
		assert(GradingScript.kind_for_name(GradingScript.kind_name(kind)) == kind, kind)
	assert(not GradingScript.is_kind("levels"), "a level is not a kind of record")
	assert(not GradingScript.is_kind(""), "and neither is nothing")
	assert(GradingScript.kind_name("nonsense") == "nonsense", "an unknown kind is worded as itself")


func test_a_spot_a_contour_and_an_arrow_land_on_three_layers() -> void:
	# Three layers rather than two, because an arrow states a fall and a contour states a level: a
	# drawing has to be able to switch one off without the other.
	assert(GradingScript.layer_for(SPOT) == LayerSetScript.GRADING_SPOT, "a spot lands on its own layer")
	assert(GradingScript.layer_for(CONTOUR) == LayerSetScript.GRADING_CONTOUR, "a contour on its own")
	assert(GradingScript.layer_for(SLOPE) == LayerSetScript.GRADING_SLOPE, "and an arrow on its own")
	var names := [GradingScript.layer_for(SPOT), GradingScript.layer_for(CONTOUR),
		GradingScript.layer_for(SLOPE)]
	var unique := {}
	for name: StringName in names:
		unique[name] = true
	assert(unique.size() == 3, "and no two of them are the same layer")


# --- the records -------------------------------------------------------------------------


func test_a_set_starts_empty_and_says_so() -> void:
	var set := GradingScript.empty_set()
	assert(set.has(SPOT) or set.has("spots"), "the set always holds all three keys")
	assert(GradingScript.count_of(set) == 0, "and starts with nothing in it")
	assert(GradingScript.summary(set) == "nothing on this drawing is graded yet", GradingScript.summary(set))
	assert(GradingScript.describe(set) == "no grading", GradingScript.describe(set))
	var checked := GradingScript.check(set)
	assert(bool(checked["ok"]), "a drawing with no grading has nothing wrong with it")
	assert((checked["findings"] as Array).is_empty(), "and nothing to report")
	assert(_some_note_has(checked["notes"], "no spot level on this drawing states a number"),
		str(checked["notes"]))


func test_an_id_is_one_past_the_highest_and_not_the_count() -> void:
	# A record that was taken off the drawing must not have its number handed to a different one while
	# a record above it is still there: the count and the ids part company the moment one is removed.
	var set := GradingScript.empty_set()
	assert(GradingScript.next_id(set, SPOT) == 1, "the first is 1")
	GradingScript.add_record(set, SPOT, GradingScript.make_spot(1, Vector2.ZERO, 1.0))
	assert(GradingScript.next_id(set, SPOT) == 2, "the second is 2")
	GradingScript.add_record(set, SPOT, GradingScript.make_spot(2, Vector2(1.0, 0.0), 2.0))
	GradingScript.add_record(set, SPOT, GradingScript.make_spot(3, Vector2(2.0, 0.0), 3.0))
	assert(GradingScript.remove_record(set, SPOT, 2), "the middle one comes off")
	assert(GradingScript.count_of(set) == 2, "leaving two")
	assert(GradingScript.next_id(set, SPOT) == 4, "and the next is 4, not the count of 2")
	assert(GradingScript.next_id(set, CONTOUR) == 1, "the kinds count their own, so a contour starts at 1")
	assert(int(GradingScript.record_for(set, SPOT, 1).get("id", 0)) == 1, "a record is found by id")
	assert(GradingScript.record_for(set, SPOT, 7).is_empty(), "and one that is not there is nothing")
	assert(not GradingScript.remove_record(set, SPOT, 7), "so removing it does nothing")


# --- levels and falls ---------------------------------------------------------------------


func test_a_level_is_written_in_the_drawings_own_units() -> void:
	assert(GradingScript.level_words(102.35) == "102.35 m", GradingScript.level_words(102.35))
	var units := UnitsScript.new()
	units.system = UnitsScript.System.IMPERIAL
	var feet: String = GradingScript.level_words(102.35, units)
	assert(feet.contains("ft"), "an imperial drawing says a level in feet: " + feet)


func test_a_fall_is_a_percentage_and_a_ratio() -> void:
	assert(GradingScript.percent_words(2.5) == "falling 2.5% (1 in 40)", GradingScript.percent_words(2.5))
	assert(GradingScript.percent_words(6.6667) == "falling 6.7% (1 in 15)",
		GradingScript.percent_words(6.6667))
	assert(GradingScript.percent_words(-1.0) == "rising 1% (1 in 100)",
		"a negative fall rises: " + GradingScript.percent_words(-1.0))
	assert(GradingScript.percent_words(0.0) == "flat", GradingScript.percent_words(0.0))
	assert(GradingScript.percent_words(NAN) == "no fall", "a fall that is not a number is no fall")
	assert(GradingScript.percent_words(INF) == "no fall", "and neither is one that is not finite")
	assert(GradingScript.fall_words(2.5, 6.0) == "falling 2.5% (1 in 40) over 6.0 m",
		GradingScript.fall_words(2.5, 6.0))


func test_a_spot_level_is_found_at_a_point_when_it_stands_close_enough() -> void:
	var spots := GradingScript.spots_of(_sloping_set())
	var found := GradingScript.level_at(Vector2(0.1, 0.0), spots)
	assert(bool(found["ok"]), "a level 0.1 m away is at that point")
	assert(is_equal_approx(float(found["level"]), 102.35), str(found["level"]))
	var missing := GradingScript.level_at(Vector2(20.0, 0.0), spots)
	assert(not bool(missing["ok"]), "and one 20 m away is not")
	assert(String(missing["reason"]).contains("no spot level stands within"), String(missing["reason"]))


func test_a_fall_needs_a_level_at_each_end_and_names_the_one_that_is_missing() -> void:
	var set := _sloping_set()
	var spots := GradingScript.spots_of(set)
	var halves := GradingScript.fall_between(Vector2.ZERO, Vector2(3.0, 0.0), spots)
	assert(not bool(halves["ok"]), "the middle of the run has no level on it")
	assert(String(halves["reason"]).contains("no spot level stands"), String(halves["reason"]))
	var whole := GradingScript.fall_between(Vector2.ZERO, Vector2(6.0, 0.0), spots)
	assert(bool(whole["ok"]), "but end to end there is one: " + String(whole["reason"]))
	assert(is_equal_approx(float(whole["run"]), 6.0), str(whole["run"]))
	assert(is_equal_approx(float(whole["rise"]), 0.4), "the top is 0.40 m above the bottom")
	assert(is_equal_approx(float(whole["percent"]), 0.4 / 6.0 * 100.0), str(whole["percent"]))
	var too_close := GradingScript.fall_between(Vector2.ZERO, Vector2(0.01, 0.0), spots)
	assert(not bool(too_close["ok"]), "and a run with no length has no fall")
	assert(String(too_close["reason"]).contains("have no fall between them"), String(too_close["reason"]))


# --- the check ----------------------------------------------------------------------------


func test_an_arrow_that_contradicts_the_levels_at_its_ends_is_a_finding() -> void:
	var set := _sloping_set()
	GradingScript.add_record(set, SLOPE,
		GradingScript.make_slope(1, Vector2.ZERO, Vector2(6.0, 0.0), 2.5))
	var findings := _findings(set)
	assert(_some_finding_has(findings, "the arrow at (0, 0) says falling 2.5% (1 in 40)"),
		"the arrow's own statement is in the finding: " + str(findings))
	assert(_some_finding_has(findings, "the levels at its ends say falling 6.7%"),
		"beside what the levels work out to: " + str(findings))
	# The same arrow stating what the levels say is a drawing that agrees with itself.
	var agreed := _sloping_set()
	GradingScript.add_record(agreed, SLOPE,
		GradingScript.make_slope(1, Vector2.ZERO, Vector2(6.0, 0.0), 0.4 / 6.0 * 100.0))
	assert(_findings(agreed).is_empty(), str(_findings(agreed)))
	assert(bool(GradingScript.check(agreed)["ok"]), "and the check is happy with it")


func test_an_arrow_with_no_levels_at_its_ends_is_unchecked_rather_than_wrong() -> void:
	# "This is wrong" and "this could not be checked" are two different sentences, and a designer acts
	# on them differently - so they are two lists.
	var set := GradingScript.empty_set()
	GradingScript.add_record(set, SLOPE,
		GradingScript.make_slope(1, Vector2.ZERO, Vector2(6.0, 0.0), 2.0))
	var checked := GradingScript.check(set)
	assert(bool(checked["ok"]), "nothing is wrong with it: " + str(checked["findings"]))
	assert((checked["findings"] as Array).is_empty(), "so there is no finding")
	assert(_some_note_has(checked["notes"], "the arrow at (0, 0) is unchecked"), str(checked["notes"]))
	assert(_some_note_has(checked["notes"], "no spot level stands within"), "and the note names why")


func test_two_contours_at_one_level_are_a_finding() -> void:
	var set := GradingScript.empty_set()
	GradingScript.add_record(set, CONTOUR, _flat_contour(1, 100.0, 0.0))
	GradingScript.add_record(set, CONTOUR, _flat_contour(2, 100.0, 4.0))
	var findings := _findings(set)
	assert(_some_finding_has(findings, "two contours are both at 100.0 m"), str(findings))
	assert(_some_finding_has(findings, "a level is one line"), "and the finding says why that is wrong")


func test_two_contours_of_different_levels_that_cross_are_a_finding() -> void:
	var set := GradingScript.empty_set()
	GradingScript.add_record(set, CONTOUR, _flat_contour(1, 100.0, 0.0, 10.0))
	GradingScript.add_record(set, CONTOUR, GradingScript.make_contour(
		2, 101.0, PackedVector2Array([Vector2(5.0, -5.0), Vector2(5.0, 5.0)])))
	var findings := _findings(set)
	assert(_some_finding_has(findings, "contours cross each other at (5, 0)"), str(findings))
	# A contour on the far side of the drawing is a drawing that is fine.
	var apart := GradingScript.empty_set()
	GradingScript.add_record(apart, CONTOUR, _flat_contour(1, 100.0, 0.0, 10.0))
	GradingScript.add_record(apart, CONTOUR, GradingScript.make_contour(
		2, 101.0, PackedVector2Array([Vector2(20.0, -5.0), Vector2(20.0, 5.0)])))
	assert(_findings(apart).is_empty(), str(_findings(apart)))


func test_a_spot_that_disagrees_with_the_contour_it_stands_on_is_a_finding() -> void:
	var set := GradingScript.empty_set()
	GradingScript.add_record(set, CONTOUR, _flat_contour(1, 100.0, 0.0))
	GradingScript.add_record(set, SPOT, GradingScript.make_spot(1, Vector2(5.0, 0.02), 102.35))
	var findings := _findings(set)
	assert(_some_finding_has(findings, "the spot at 102.35 m stands on the 100.0 m contour"),
		str(findings))
	# The same spot stating the contour's own level is agreeing with it.
	var agreed := GradingScript.empty_set()
	GradingScript.add_record(agreed, CONTOUR, _flat_contour(1, 100.0, 0.0))
	GradingScript.add_record(agreed, SPOT, GradingScript.make_spot(1, Vector2(5.0, 0.02), 100.0))
	assert(_findings(agreed).is_empty(), str(_findings(agreed)))


func test_a_level_that_is_not_a_number_is_a_finding_rather_than_a_silent_zero() -> void:
	var set := GradingScript.empty_set()
	GradingScript.add_record(set, SPOT, GradingScript.make_spot(1, Vector2(2.0, 3.0), NAN))
	var findings := _findings(set)
	assert(_some_finding_has(findings, "the spot level at (2, 3) is not a number"), str(findings))
	var levels := GradingScript.high_low(GradingScript.spots_of(set))
	assert(int(levels["statements"]) == 0, "and it states no level as far as any figure is concerned")
	assert(not bool(levels["ok"]), "so there is nothing to say the ground runs between")
	assert(not bool(GradingScript.check(set)["ok"]), "so the drawing does not agree with itself")


func test_the_report_knows_how_far_the_ground_runs_and_how_steep_it_is() -> void:
	var set := _sloping_set()
	GradingScript.add_record(set, CONTOUR, _flat_contour(1, 101.5, 3.0))
	var notes := _notes(set)
	assert(_some_note_has(notes, "the levels run from 101.95 m to 102.35 m, 0.4 m apart"),
		str(notes))
	assert(_some_note_has(notes, "the steepest fall between two spot levels is falling 6.7% (1 in 15)"),
		str(notes))
	var figures := GradingScript.measurement(set)
	assert(int(figures["spots"]) == 2, "two spots")
	assert(int(figures["contours"]) == 1, "a contour")
	assert(int(figures["slopes"]) == 0, "and no arrows")
	assert(int(figures["stated_levels"]) == 2, "both spot levels state a number")


# --- the words --------------------------------------------------------------------------


func test_the_summary_counts_what_is_there_and_says_how_high_and_low() -> void:
	var set := _sloping_set()
	GradingScript.add_record(set, CONTOUR, _flat_contour(1, 101.5, 3.0))
	GradingScript.add_record(set, SLOPE,
		GradingScript.make_slope(1, Vector2.ZERO, Vector2(6.0, 0.0), 6.6667))
	assert(GradingScript.summary(set) == (
		"2 spot levels, a contour and a slope arrow on this drawing, running from 101.95 m to 102.35 m"
	), GradingScript.summary(set))
	assert(GradingScript.record_words(SPOT, GradingScript.spots_of(set)[0]) == "102.35 m at (0, 0)",
		GradingScript.record_words(SPOT, GradingScript.spots_of(set)[0]))
	assert(GradingScript.record_words(CONTOUR, GradingScript.contours_of(set)[0]) == (
		"101.5 m contour, 2 points"
	), GradingScript.record_words(CONTOUR, GradingScript.contours_of(set)[0]))
	assert(GradingScript.record_words(SLOPE, GradingScript.slopes_of(set)[0]) == (
		"slope arrow falling 6.7% (1 in 15) over 6.0 m"
	), GradingScript.record_words(SLOPE, GradingScript.slopes_of(set)[0]))


func test_the_schedule_reads_one_row_per_record_with_the_kind_and_the_id_on_it() -> void:
	var set := _sloping_set()
	GradingScript.add_record(set, CONTOUR, _flat_contour(1, 101.5, 3.0))
	var rows := GradingScript.schedule(set)
	assert(rows.size() == 3, str(rows.size()))
	assert(String(rows[0]["kind"]) == SPOT and int(rows[0]["id"]) == 1, str(rows[0]))
	assert(String(rows[0]["text"]) == "102.35 m   (0, 0)", String(rows[0]["text"]))
	assert(String(rows[2]["kind"]) == CONTOUR, str(rows[2]))
	assert(String(rows[2]["text"]) == "101.5 m   2 points   10.0 m", String(rows[2]["text"]))
	var lines := GradingScript.schedule_lines(set)
	assert(lines.size() == 3, "and one line for each row")
	assert(lines[0] == String(rows[0]["text"]), "saying the same words")


# --- the marks on the plan ------------------------------------------------------------------


func test_a_spot_is_a_mark_and_a_label_and_both_say_what_they_stand_for() -> void:
	var set := _sloping_set()
	var spot: Dictionary = GradingScript.spots_of(set)[0]
	var drawn := GradingScript.entities_for(SPOT, spot, 100.0)
	assert(drawn.size() == 2, "a mark and a label: %d" % drawn.size())
	var mark: DraftEntity = drawn[0]
	var label: DraftEntity = drawn[1]
	assert(mark.kind == EntityScript.Kind.CIRCLE, "the mark is a circle")
	assert(label.kind == EntityScript.Kind.TEXT, "and the label is text")
	for entity: DraftEntity in drawn:
		assert(GradingScript.is_grading_entity(entity), "both carry what they stand for")
		assert(GradingScript.kind_of_entity(entity) == SPOT, "which kind they are")
		assert(GradingScript.id_of_entity(entity) == 1, "and which record")
		assert(entity.layer == LayerSetScript.GRADING_SPOT, "and land on the spot layer")
	assert(String(label.meta.get("text", "")).contains("102.35"),
		"the level is written on it: " + String(label.meta.get("text", "")))
	assert(is_equal_approx(float(label.meta.get("height", 0.0)), GradingScript.LABEL_MM),
		"at a paper size, the way every other note is")


func test_a_contour_is_a_line_and_a_label_and_an_arrow_is_a_line_a_head_and_a_label() -> void:
	var set := GradingScript.empty_set()
	GradingScript.add_record(set, CONTOUR, _flat_contour(1, 101.5, 0.0))
	var line := GradingScript.entities_for(CONTOUR, GradingScript.contours_of(set)[0], 100.0)
	assert(line.size() == 2, "a contour is a line and its level: %d" % line.size())
	assert((line[0] as DraftEntity).kind == EntityScript.Kind.POLYLINE, "the line is a polyline")
	var arrow := GradingScript.entities_for(
		SLOPE, GradingScript.make_slope(1, Vector2.ZERO, Vector2(6.0, 0.0), 2.5), 100.0)
	assert(arrow.size() == 3, "an arrow is its shaft, its head and its fall: %d" % arrow.size())
	assert((arrow[0] as DraftEntity).kind == EntityScript.Kind.LINE, "the shaft is a line")
	assert((arrow[1] as DraftEntity).kind == EntityScript.Kind.POLYLINE, "the head is a bent line")
	for entity: DraftEntity in arrow:
		assert(GradingScript.kind_of_entity(entity) == SLOPE, "all of it stands for the arrow")
		assert(entity.layer == LayerSetScript.GRADING_SLOPE, "and all of it is on the arrow layer")


func test_a_record_too_short_to_be_anything_draws_nothing() -> void:
	# A contour of one point is not a line and an arrow of no length has no fall: neither may leave a
	# mark on the plan, because a mark with no record behind it is a drawing that cannot be read.
	assert(GradingScript.entities_for(CONTOUR, GradingScript.make_contour(
		1, 100.0, PackedVector2Array([Vector2.ZERO])), 100.0).is_empty(), "a contour of one point")
	assert(GradingScript.entities_for(SLOPE, GradingScript.make_slope(
		1, Vector2.ZERO, Vector2.ZERO, 2.0), 100.0).is_empty(), "an arrow of no length")


func test_a_label_is_a_paper_size_so_a_plan_and_its_plot_agree() -> void:
	# The same reason a dimension's arrowheads are: a note is a mark on the drawing, not a thing in a
	# garden. A plot twice as far out is a note twice as large on the ground and the same size on paper.
	var spot: Dictionary = GradingScript.spots_of(_sloping_set())[0]
	var at_100 := GradingScript.entities_for(SPOT, spot, 100.0)
	var at_200 := GradingScript.entities_for(SPOT, spot, 200.0)
	var small: float = (at_100[0] as DraftEntity).params[2]
	var large: float = (at_200[0] as DraftEntity).params[2]
	assert(large > small, "the mark is bigger on the ground at the smaller scale")
	assert(is_equal_approx(large, small * 2.0), "and exactly twice, because the paper has not moved")


# --- the file -------------------------------------------------------------------------------


func test_a_set_survives_a_json_round_trip() -> void:
	var set := _sloping_set()
	GradingScript.add_record(set, CONTOUR, GradingScript.make_contour(
		1, 101.5, PackedVector2Array([Vector2(0.0, 0.0), Vector2(3.0, 1.0), Vector2(6.0, 0.0)]), true))
	GradingScript.add_record(set, SLOPE,
		GradingScript.make_slope(1, Vector2.ZERO, Vector2(6.0, 0.0), 6.6667))
	var written := JSON.stringify(GradingScript.to_dict(set))
	var parser := JSON.new()
	assert(parser.parse(written) == OK, "the set writes as JSON: " + written)
	var read := GradingScript.from_dict(parser.data)
	assert(GradingScript.count_of(read) == 4, str(GradingScript.count_of(read)))
	assert(GradingScript.summary(read) == GradingScript.summary(set), GradingScript.summary(read))
	var contour: Dictionary = GradingScript.contours_of(read)[0]
	assert(bool(contour["closed"]), "a closed contour is still closed")
	assert((contour["points"] as PackedVector2Array).size() == 3, "and every point is still there")
	assert(is_equal_approx((contour["points"] as PackedVector2Array)[1].x, 3.0), "at its own place")
	assert(GradingScript.schedule_lines(read) == GradingScript.schedule_lines(set),
		"so the schedule reads the same both ways")
	assert(int(GradingScript.record_for(read, SPOT, 2).get("id", 0)) == 2, "and the ids come back")


func test_a_record_that_is_not_one_is_dropped_and_a_level_that_is_not_a_number_is_kept() -> void:
	var read := GradingScript.from_dict({
		"spots": [
			{"id": 1, "at": [1.0, 2.0], "level": 3.5},
			"not a record",
			{"at": [0.0, 0.0], "level": 1.0},
			{"id": 2, "at": [4.0, 5.0], "level": "high"},
		],
		"contours": [{"id": 1, "level": 1.0, "points": [0.0, 0.0]}],
		"slopes": [{"id": 1, "a": [0.0, 0.0], "b": [0.0, 0.0], "percent": 2.0}],
	})
	assert(GradingScript.spots_of(read).size() == 2, "two of the four spots are records")
	assert(GradingScript.contours_of(read).is_empty(), "a contour of one point is not a contour")
	assert(GradingScript.slopes_of(read).is_empty(), "and an arrow of no length is not an arrow")
	var odd: Dictionary = GradingScript.spots_of(read)[1]
	assert(is_nan(float(odd["level"])), "a level that is not a number survives as exactly that")
	# Because a spot with no level is a mark on the drawing a person has to be told about, rather than
	# one this can quietly remove.
	assert(_some_finding_has(_findings(read), "is not a number"), str(_findings(read)))
	assert(GradingScript.from_dict({}).is_empty() == false, "a file with nothing in it reads as empty")
	assert(GradingScript.count_of(GradingScript.from_dict({})) == 0, "with no records")


func test_a_record_set_that_is_nothing_at_all_reads_as_empty_rather_than_throwing() -> void:
	var nonsense: Dictionary = {"spots": "a list of things", "contours": 3, "slopes": null}
	assert(GradingScript.count_of(GradingScript.from_dict(nonsense)) == 0, "nothing in it is a record")
	assert(GradingScript.summary(GradingScript.from_dict(nonsense)) == (
		"nothing on this drawing is graded yet"
	), GradingScript.summary(GradingScript.from_dict(nonsense)))