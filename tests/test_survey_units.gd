extends Node
## Tests for the units a survey is reported in.
##
## A survey's file states what its numbers are *in*; the drawing states what it *says* them in, and on
## an imperial drawing those are two different things. Everything a person reads about a survey - the
## one-line description and every check the engine made - is worded in the drawing's own units, in the
## one place either an area or a length is turned into words.

const Survey := preload("res://scripts/draft/survey.gd")
const SurveyFile := preload("res://scripts/draft/survey_file.gd")
const Units := preload("res://scripts/draft/units.gd")
const Ctrl := preload("res://scripts/draft/draft_controller.gd")
const Document := preload("res://scripts/draft/draft_document.gd")
const SnapScript := preload("res://scripts/draft/snap_engine.gd")
const Tool := preload("res://scripts/draft/draft_tool.gd")
const Hud := preload("res://scripts/hud.gd")

const FOOT := 0.3048
const LOT_AREA_M2 := 50.0 * FOOT * 120.0 * FOOT


# --- helpers --------------------------------------------------------------------------


func _imperial():
	var units = Units.new()
	units.system = Units.System.IMPERIAL
	return units


func _lot_text() -> String:
	return "\n".join(PackedStringArray([
		"units: ft",
		"N 90 0 0 E, 50.00",
		"N 0 0 0 E, 120.00",
		"N 90 0 0 W, 50.00",
		"S 0 0 0 W, 120.00",
	]))


func _controller():
	var controller = Ctrl.new()
	controller.document = Document.new()
	controller.snap = SnapScript.new()
	controller.tool = Tool.new()
	return controller


func _extent_line(parsed: Dictionary) -> String:
	for line: String in SurveyFile.report_lines(parsed):
		if line.contains("Parcel extent"):
			return line
	return ""


func _area_line(parsed: Dictionary) -> String:
	for line: String in SurveyFile.report_lines(parsed):
		if line.contains("Area cross-check"):
			return line
	return ""


# --- the words a report is made of ----------------------------------------------------


func test_a_survey_read_with_no_drawing_is_still_reported_in_metres() -> void:
	var parsed := SurveyFile.read_text(_lot_text())
	assert(bool(parsed["ok"]), String(parsed["reason"]))
	var words := SurveyFile.describe(parsed)
	assert(words.contains(" m2"), "the metric default is unchanged: " + words)
	assert(words.contains(" m around"), "and the perimeter now says what it is in: " + words)
	assert(_extent_line(parsed).contains("m2"), "the extent check is in metres too: " + _extent_line(parsed))


func test_a_survey_on_an_imperial_drawing_is_reported_in_feet() -> void:
	var parsed := SurveyFile.read_text(_lot_text(), {"display_units": _imperial()})
	assert(bool(parsed["ok"]), String(parsed["reason"]))
	var words := SurveyFile.describe(parsed)
	assert(words.contains("ft2"), "an imperial drawing is told about square feet: " + words)
	assert(not words.contains("m2"), "and is never told about square metres: " + words)
	assert(words.contains(" ft around"), "the perimeter is in feet: " + words)


func test_the_extent_check_is_worded_in_the_units_the_read_was_given() -> void:
	var metric := SurveyFile.read_text(_lot_text())
	var imperial := SurveyFile.read_text(_lot_text(), {"display_units": _imperial()})
	assert(_extent_line(metric).contains("m2"), "metres by default: " + _extent_line(metric))
	assert(_extent_line(imperial).contains("ft2"), "feet on an imperial drawing: " + _extent_line(imperial))
	assert(not _extent_line(imperial).contains("m2"),
		"and not both at once: " + _extent_line(imperial))


func test_a_stated_area_is_compared_in_the_drawings_own_units() -> void:
	var stated := _lot_text() + "\narea: 6000 ft2\n"
	var imperial := SurveyFile.read_text(stated, {"display_units": _imperial()})
	assert(_area_line(imperial).contains("ft2"), "both sides of the comparison are in feet: "
		+ _area_line(imperial))
	assert(not _area_line(imperial).contains("m2"), "and neither is in metres: " + _area_line(imperial))


func test_a_lot_is_compared_against_the_same_bounds_in_either_system() -> void:
	var metric := SurveyFile.read_text(_lot_text() + "\narea: 557.42 m2\n")
	var imperial := SurveyFile.read_text(_lot_text() + "\narea: 6000 ft2\n", {"display_units": _imperial()})
	assert(SurveyFile.is_sound(metric), "a lot stated in its own area agrees")
	assert(SurveyFile.is_sound(imperial), "and so does the same lot stated in feet")
	assert(is_equal_approx(float(metric["stated_area_m2"]), LOT_AREA_M2),
		"a stated area is stored in the model's own unit whatever it was written in")


# --- the two checks on their own ------------------------------------------------------


func test_an_area_check_is_worded_in_the_units_it_is_handed() -> void:
	var imperial = _imperial()
	var extent: Dictionary = Survey.check_extent(Rect2(0, 0, 20, 15), Survey.MIN_LOT_AREA_M2,
		Survey.MAX_LOT_AREA_M2, imperial)
	assert(String(extent["message"]).contains("ft2"), "the extent sentence is in feet: " + String(extent["message"]))
	assert(String(extent["area_text"]).contains("ft2"), "and it carries the area's own words")
	assert(String(extent["status"]) == "pass", "the bounds are still model areas, so the verdict is unchanged")

	var check: Dictionary = Survey.check_area(557.4182, 557.4182, Survey.AREA_TOLERANCE, imperial)
	assert(String(check["message"]).contains("ft2"), "both figures are in feet: " + String(check["message"]))
	assert(not String(check["message"]).contains("m2"), "and neither is in metres")


func test_a_check_with_no_units_handed_over_is_worded_in_metres() -> void:
	var extent: Dictionary = Survey.check_extent(Rect2(0, 0, 20, 15))
	assert(String(extent["message"]).contains("m2"), "the metre default: " + String(extent["message"]))
	var check: Dictionary = Survey.check_area(557.4182, 557.4182)
	assert(String(check["message"]).contains("m2"), "the metre default: " + String(check["message"]))


# --- the one place the units are resolved ---------------------------------------------


func test_the_units_are_resolved_in_one_place() -> void:
	assert(Units.or_default(null).format_area(1.0) == "1 m2", "no units is the metre")
	assert(Units.or_default(_imperial()).format_area(1.0) == "10.8 ft2", "units handed over are used")


func test_a_length_written_for_a_caller_with_no_drawing_carries_its_unit() -> void:
	var words := Units.length_words(357.4182)
	assert(words.ends_with(" m"), "a survey's perimeter says what it is in: " + words)
	assert(words.begins_with("357.4"), "and it is worded at the drawing's own precision: " + words)
	assert(Units.length_words(3.0).ends_with(" m"),
		"and so does a whole length: " + Units.length_words(3.0))


func test_a_survey_read_out_of_a_saved_file_is_worded_in_the_drawing_it_is_going_on() -> void:
	var data := SurveyFile.to_dict(SurveyFile.read_text(_lot_text()))
	var imperial := SurveyFile.from_dict(data, {"display_units": _imperial()})
	assert(SurveyFile.describe(imperial).contains("ft2"),
		"the units were never in the file, so the reader says which drawing it is: "
			+ SurveyFile.describe(imperial))
	assert(SurveyFile.describe(SurveyFile.from_dict(data)).contains("m2"),
		"and with no drawing to hand it is metres")


# --- the drawing's own end -----------------------------------------------------------


func test_the_controller_reports_an_import_in_the_units_the_survey_was_read_in() -> void:
	var controller = _controller()
	var parsed := SurveyFile.read_text(_lot_text(), {"display_units": _imperial()})
	var taken: Dictionary = controller.import_survey(parsed)
	assert(bool(taken["ok"]), String(taken["reason"]))
	assert(controller.last_message.contains("ft2"),
		"the drawing says what it took, in its own units: " + controller.last_message)
	assert(not controller.last_message.contains("m2"),
		"and never names a unit it is not drawn in: " + controller.last_message)
	controller.free()


func test_the_hud_reads_a_survey_in_the_units_of_the_drawing_it_is_going_on() -> void:
	var controller = _controller()
	controller.document.units.system = Units.System.IMPERIAL
	var hud = Hud.new()
	hud._draft = controller
	var options: Dictionary = hud._survey_read_options()
	assert(options.has("display_units"), "the read is told what the drawing says units in")
	assert(int((options["display_units"] as DraftUnits).system) == int(Units.System.IMPERIAL),
		"and it is the drawing's own units, not a default")
	hud.free()
	controller.free()


func test_a_hud_with_no_drawing_asks_the_reader_for_its_own_default() -> void:
	var hud = Hud.new()
	var options: Dictionary = hud._survey_read_options()
	assert(options.is_empty(), "with no drawing there is nothing to word a report in")
	hud.free()