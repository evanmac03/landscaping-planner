extends Node
## Tests for reading a surveyor's own file: metes and bounds, a coordinate point
## list, the unit a distance was stated in, and the refusals that keep a
## mis-read survey off the drawing.

const SurveyFile := preload("res://scripts/draft/survey_file.gd")
const Units := preload("res://scripts/draft/units.gd")

const FOOT := 0.3048
const WIDTH_FT := 50.0
const DEPTH_FT := 120.0
## 50.00 ft x 120.00 ft, in metres.
const AREA_M2 := WIDTH_FT * FOOT * DEPTH_FT * FOOT
const PERIMETER_M := 2.0 * (WIDTH_FT + DEPTH_FT) * FOOT


func _lot_text() -> String:
	return "\n".join(PackedStringArray([
		"name: 12 Maple Street",
		"units: ft",
		"# frontage, side, rear, side back to the start",
		"N 90 0 0 E, 50.00",
		"N 0 0 0 E, 120.00",
		"N 90 0 0 W, 50.00",
		"S 0 0 0 W, 120.00",
	]))


func _point_text() -> String:
	return "\n".join(PackedStringArray([
		"units: m",
		"0, 0",
		"15.24, 0",
		"15.24, 36.576",
		"0, 36.576",
	]))


# --- metes and bounds ---------------------------------------------------------------


func test_a_four_leg_lot_reads_closes_and_measures() -> void:
	var parsed := SurveyFile.read_text(_lot_text())
	assert(bool(parsed["ok"]), String(parsed["reason"]))
	assert(String(parsed["kind"]) == SurveyFile.METES, "bearings and distances are metes and bounds")
	assert((parsed["legs"] as Array).size() == 4, "four legs")
	assert(bool(parsed["traverse"]["closed"]), "cardinal legs come back to the start exactly")
	assert(is_equal_approx(float(parsed["area_m2"]), AREA_M2), "the area is the lot's own")
	assert(is_equal_approx(float(parsed["perimeter_m"]), PERIMETER_M), "the perimeter is the walk")
	assert(String(parsed["title"]) == "12 Maple Street", "the name line is the survey's title")
	assert(String(parsed["units"]) == "ft", "the header states the unit for every line")


func test_the_report_says_the_parcel_is_sound() -> void:
	var parsed := SurveyFile.read_text(_lot_text())
	assert(SurveyFile.is_sound(parsed), "a closed, simple, plausible parcel is sound")
	var lines := SurveyFile.report_lines(parsed)
	assert(lines.size() == 4, "four checks, one line each")
	for line: String in lines:
		assert(line.begins_with("PASS"), "nothing to report: " + line)


func test_a_leg_written_in_one_breath_reads() -> void:
	var text := "units: ft\nN45-30-15E 100.00\n"
	var parsed := SurveyFile.read_text(text)
	assert(bool(parsed["ok"]), String(parsed["reason"]))
	var expected := 45.0 + 30.0 / 60.0 + 15.0 / 3600.0
	assert(is_equal_approx(float(parsed["legs"][0]["azimuth"]), expected), "the bearing reads")
	assert(is_equal_approx(float(parsed["legs"][0]["distance"]), 100.0 * FOOT), "the distance reads in feet")


func test_a_bearing_with_a_degree_symbol_and_spaces_reads() -> void:
	var parsed := SurveyFile.read_text("units: m\nN 45°30'15\" E 100.00\n")
	assert(bool(parsed["ok"]), String(parsed["reason"]))
	var expected := 45.0 + 30.0 / 60.0 + 15.0 / 3600.0
	assert(is_equal_approx(float(parsed["legs"][0]["azimuth"]), expected), "the bearing reads past its spaces")
	assert(is_equal_approx(float(parsed["legs"][0]["distance"]), 100.0), "the distance reads in metres")


func test_a_distance_can_state_its_own_unit() -> void:
	var parsed := SurveyFile.read_text("N 90 0 0 E, 50.00, ft\nN 0 0 0 E, 120.00, ft\n")
	assert(bool(parsed["ok"]), String(parsed["reason"]))
	assert(String(parsed["units"]) == "ft", "the line's own unit is the survey's unit")
	assert(is_equal_approx(float(parsed["legs"][0]["distance"]), 50.0 * FOOT))


func test_two_units_in_one_file_are_each_read_in_their_own() -> void:
	var parsed := SurveyFile.read_text("N 90 0 0 E, 50.00, ft\nN 90 0 0 E, 10.00, m\n")
	assert(bool(parsed["ok"]), String(parsed["reason"]))
	assert(String(parsed["units"]) == "mixed", "a file in two units says so")
	assert(is_equal_approx(float(parsed["legs"][0]["distance"]), 50.0 * FOOT))
	assert(is_equal_approx(float(parsed["legs"][1]["distance"]), 10.0), "metres stay metres")


# --- units --------------------------------------------------------------------------


func test_the_us_survey_foot_is_its_own_length() -> void:
	var parsed := SurveyFile.read_text(_lot_text().replace("units: ft", "units: usft"))
	assert(bool(parsed["ok"]), String(parsed["reason"]))
	var expected := WIDTH_FT * Units.US_SURVEY_FOOT * DEPTH_FT * Units.US_SURVEY_FOOT
	assert(is_equal_approx(float(parsed["area_m2"]), expected), "the survey foot is longer than the foot")
	assert(float(parsed["area_m2"]) > AREA_M2 + 0.001,
		"and the difference is real: %f vs %f" % [float(parsed["area_m2"]), AREA_M2])


func test_a_file_that_does_not_say_its_units_is_refused() -> void:
	var parsed := SurveyFile.read_text("N 90 0 0 E, 50.00\n")
	assert(not bool(parsed["ok"]), "a distance with no unit is not read")
	assert(String(parsed["reason"]) == "line 1: say what unit the distances are in",
		"the refusal names the line and what is missing")


func test_a_unit_nobody_knows_is_refused() -> void:
	var parsed := SurveyFile.read_text("E 90 0 0 E, 50.00, furlong\n")
	assert(not bool(parsed["ok"]), "an unknown unit stops the read")


# --- refusals -----------------------------------------------------------------------


func test_a_line_that_is_neither_a_bearing_nor_a_coordinate_is_refused_with_its_number() -> void:
	var parsed := SurveyFile.read_text("units: m\n0, 0\nbanana, 12.00\n")
	assert(not bool(parsed["ok"]), "a line nobody can read stops the read")
	assert(String(parsed["reason"]) == "line 3: \"banana, 12.00\" is neither a bearing nor a coordinate",
		"the refusal quotes the line and numbers it")


func test_bearings_and_coordinates_cannot_be_mixed() -> void:
	var metes_first := SurveyFile.read_text("units: m\nN 90 0 0 E, 10.00\n0, 0\n")
	assert(not bool(metes_first["ok"]), "a coordinate after bearings stops the read")
	var points_first := SurveyFile.read_text("units: m\n0, 0\nN 90 0 0 E, 10.00\n")
	assert(not bool(points_first["ok"]), "a bearing after coordinates stops the read")


func test_an_empty_file_is_refused() -> void:
	var parsed := SurveyFile.read_text("# nothing here but a comment\n\n")
	assert(not bool(parsed["ok"]), "a file with no data in it stops the read")
	assert(String(parsed["reason"]) == "the file has no bearings and no coordinates in it")


func test_an_azimuth_list_is_a_leg_list_when_the_file_says_so() -> void:
	var text := "\n".join(PackedStringArray([
		"units: m",
		"kind: metes",
		"90, 15.24",
		"0, 36.576",
		"270, 15.24",
		"180, 36.576",
	]))
	var parsed := SurveyFile.read_text(text)
	assert(bool(parsed["ok"]), String(parsed["reason"]))
	assert(String(parsed["kind"]) == SurveyFile.METES, "a bare number is an azimuth once the file says so")
	assert((parsed["legs"] as Array).size() == 4, "four legs")
	assert(is_equal_approx(float(parsed["area_m2"]), AREA_M2), "the same lot, turned into azimuths")


func test_a_kind_nobody_knows_is_refused() -> void:
	var parsed := SurveyFile.read_text("kind: polygon\nunits: m\n0, 0\n")
	assert(not bool(parsed["ok"]), "a kind the reader does not have stops the read")


func test_a_missing_file_is_refused_rather_than_raising() -> void:
	var parsed := SurveyFile.of_file("user://there-is-no-such-survey.txt")
	assert(not bool(parsed["ok"]), "a path a person typed may not exist")
	assert(String(parsed["reason"]).contains("no survey file"), "and it says so")


# --- coordinate point lists ---------------------------------------------------------


func test_a_coordinate_list_reads_as_points() -> void:
	var parsed := SurveyFile.read_text(_point_text())
	assert(bool(parsed["ok"]), String(parsed["reason"]))
	assert(String(parsed["kind"]) == SurveyFile.POINTS, "two numbers a line are a point")
	assert((parsed["raw_points"] as Array).size() == 4, "four corners")
	assert(is_equal_approx(float(parsed["area_m2"]), AREA_M2), "the same lot, listed as points")
	assert(SurveyFile.is_sound(parsed), "a simple rectangle is sound")


func test_north_goes_negative_z_in_model_space() -> void:
	var parsed := SurveyFile.read_text(_point_text())
	var points: PackedVector2Array = parsed["points"]
	assert(is_equal_approx(points[1].x, 15.24) and is_equal_approx(points[1].y, 0.0),
		"east is +x along the frontage")
	assert(is_equal_approx(points[2].y, -36.576), "north is -z, so a plan needs no flip")


func test_a_self_intersecting_parcel_is_not_sound() -> void:
	var bowtie := "units: m\n0, 0\n10, 10\n10, 0\n0, 10\n"
	var parsed := SurveyFile.read_text(bowtie)
	assert(bool(parsed["ok"]), "it reads; it is the drawing that is wrong")
	assert(not SurveyFile.is_sound(parsed), "a parcel that crosses itself blocks the import")
	var lines := SurveyFile.report_lines(parsed)
	var failures := 0
	for line: String in lines:
		if line.begins_with("FAIL"):
			failures += 1
	assert(failures == 1, "exactly one check fails, and it is the one that matters")


# --- closure and cross-checks -------------------------------------------------------


func test_a_loose_traverse_is_a_warning_not_a_refusal() -> void:
	var loose := "\n".join(PackedStringArray([
		"units: ft",
		"N 90 0 0 E, 50.00",
		"N 0 0 0 E, 120.00",
		"N 90 0 0 W, 50.00",
		"S 0 0 0 W, 120.50",
	]))
	var parsed := SurveyFile.read_text(loose)
	assert(bool(parsed["ok"]), String(parsed["reason"]))
	assert(not bool(parsed["traverse"]["closed"]), "half a foot of misclosure is not closed")
	assert(SurveyFile.is_sound(parsed), "a warning does not block a survey")
	var warned := false
	for line: String in SurveyFile.report_lines(parsed):
		if line.begins_with("WARN") and line.contains("closure"):
			warned = true
	assert(warned, "the closure is reported as a warning")


func test_a_stated_area_is_cross_checked() -> void:
	var matching := SurveyFile.read_text(_lot_text() + "\narea: 557.42 m2\n")
	assert(is_equal_approx(float(matching["stated_area_m2"]), 557.42), "the stated area is read")
	var agreeing := SurveyFile.read_text(_lot_text() + "\narea: 557.42 m2\n")
	var disagreed := false
	for line: String in SurveyFile.report_lines(agreeing):
		if line.contains("Area cross-check") and line.begins_with("WARN"):
			disagreed = true
	assert(not disagreed, "a stated area within half a percent agrees")
	var wrong := SurveyFile.read_text(_lot_text() + "\narea: 100 m2\n")
	var flagged := false
	for line: String in SurveyFile.report_lines(wrong):
		if line.contains("Area cross-check") and line.begins_with("WARN"):
			flagged = true
	assert(flagged, "an area that disagrees is flagged")


func test_an_area_in_acres_is_read() -> void:
	var parsed := SurveyFile.read_text(_lot_text() + "\narea: 1 acre\n")
	assert(is_equal_approx(float(parsed["stated_area_m2"]), Units.ACRE), "an acre is an acre")


# --- provenance and words -----------------------------------------------------------


func test_a_survey_survives_the_file_format() -> void:
	var parsed := SurveyFile.read_text(_lot_text())
	var again := SurveyFile.from_dict(SurveyFile.to_dict(parsed))
	assert(bool(again["ok"]), "a survey read out of a file is a survey")
	assert(String(again["kind"]) == SurveyFile.METES)
	assert((again["legs"] as Array).size() == 4)
	assert(is_equal_approx(float(again["area_m2"]), AREA_M2), "the area is recomputed, not carried")
	assert(String(again["title"]) == "12 Maple Street", "the title travels with it")


func test_the_geometry_is_recomputed_rather_than_believed() -> void:
	var data := SurveyFile.to_dict(SurveyFile.read_text(_lot_text()))
	data["stated_area_m2"] = 0.0
	var again := SurveyFile.from_dict(data)
	assert(is_equal_approx(float(again["area_m2"]), AREA_M2),
		"a file cannot carry a stale area")


func test_describe_names_the_legs_and_the_area() -> void:
	var words := SurveyFile.describe(SurveyFile.read_text(_lot_text()))
	assert(words.begins_with("4 legs"), "it says how many legs: " + words)
	assert(words.contains("m2"), "and the area it comes to: " + words)
	var refused := SurveyFile.describe(SurveyFile.read_text("banana, 12.00\n"))
	assert(refused.contains("neither a bearing nor a coordinate"), "a refusal reads as its reason: " + refused)


func test_a_header_nobody_knows_is_kept_as_a_note() -> void:
	var parsed := SurveyFile.read_text("surveyor: J. Doe\nunits: ft\nN 90 0 0 E, 50.00\n")
	assert(bool(parsed["ok"]), "an unknown header does not stop the read")
	var notes: Array = parsed["notes"]
	assert(notes.has("surveyor: J. Doe"), "and it is not silently dropped")
	var lines := SurveyFile.report_lines(parsed)
	assert(lines.has("NOTE: surveyor: J. Doe"), "the note reaches the report")