extends Node
## Tests for putting an imported survey on the drawing: what lands, on which
## layer, as how many undo steps, and what is refused.
##
## The controller is built with its parts but no scene tree, so these are about the
## decisions an import makes rather than about a file dialog.

const Ctrl := preload("res://scripts/draft/draft_controller.gd")
const Tool := preload("res://scripts/draft/draft_tool.gd")
const Document := preload("res://scripts/draft/draft_document.gd")
const SnapScript := preload("res://scripts/draft/snap_engine.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const SurveyFile := preload("res://scripts/draft/survey_file.gd")

const FOOT := 0.3048
const LOT_AREA_M2 := 50.0 * FOOT * 120.0 * FOOT


func _controller():
	var controller = Ctrl.new()
	controller.document = Document.new()
	controller.snap = SnapScript.new()
	controller.tool = Tool.new()
	return controller


func _lot() -> Dictionary:
	return SurveyFile.read_text("\n".join(PackedStringArray([
		"name: 12 Maple Street",
		"units: ft",
		"N 90 0 0 E, 50.00",
		"N 0 0 0 E, 120.00",
		"N 90 0 0 W, 50.00",
		"S 0 0 0 W, 120.00",
	])))


func _loose() -> Dictionary:
	return SurveyFile.read_text("\n".join(PackedStringArray([
		"units: ft",
		"N 90 0 0 E, 50.00",
		"N 0 0 0 E, 120.00",
		"N 90 0 0 W, 50.00",
		"S 0 0 0 W, 120.50",
	])))


# --- what lands -----------------------------------------------------------------------


func test_a_sound_survey_lands_on_the_property_layer() -> void:
	var controller = _controller()
	var taken: Dictionary = controller.import_survey(_lot())
	assert(bool(taken["ok"]), String(taken["reason"]))
	assert(controller.document.count() == 1, "a parcel is one shape, not four lines")
	var entity = controller.document.entities()[0]
	assert(String(entity.layer) == String(LayerSet.SURVEY_PROPERTY), "it lands on the property layer")
	assert(entity.is_closed(), "a parcel is a ring")
	assert(is_equal_approx(absf(entity.area()), LOT_AREA_M2), "and it is the lot's own area")
	controller.free()


func test_the_import_is_one_undo_step() -> void:
	var controller = _controller()
	controller.import_survey(_lot())
	assert(controller.document.count() == 1)
	assert(controller.document.undo_last(), "one Ctrl+Z takes the import back off")
	assert(controller.document.count() == 0, "and nothing of it is left")
	controller.free()


func test_an_import_leaves_the_drawing_unsaved() -> void:
	var controller = _controller()
	controller.import_survey(_lot())
	assert(controller.dirty, "a drawing that has gained a survey has changed")
	controller.free()


func test_the_status_line_says_what_was_imported() -> void:
	var controller = _controller()
	controller.import_survey(_lot())
	assert(controller.last_message.begins_with("imported 4 legs"),
		"the drawing says what it took: " + controller.last_message)
	controller.free()


# --- what is refused ------------------------------------------------------------------


func test_a_parcel_that_crosses_itself_is_refused() -> void:
	var controller = _controller()
	var bowtie := SurveyFile.read_text("units: m\n0, 0\n10, 10\n10, 0\n0, 10\n")
	var taken: Dictionary = controller.import_survey(bowtie)
	assert(not bool(taken["ok"]), "a tracing error does not go on the drawing")
	assert(controller.document.count() == 0, "and nothing is added")
	assert(String(taken["reason"]).contains("checks"), "the refusal names the checks: " + String(taken["reason"]))
	controller.free()


func test_a_survey_that_could_not_be_read_is_refused_with_its_reason() -> void:
	var controller = _controller()
	var bad := SurveyFile.read_text("banana, 12.00\n")
	var taken: Dictionary = controller.import_survey(bad)
	assert(not bool(taken["ok"]))
	assert(String(taken["reason"]) == String(bad["reason"]), "the reader's own words are the refusal")
	assert(controller.document.count() == 0)
	controller.free()


func test_a_survey_with_no_outline_cannot_be_placed() -> void:
	var controller = _controller()
	var line := SurveyFile.read_text("units: m\n0, 0\n1, 1\n")
	var taken: Dictionary = controller.import_survey(line)
	assert(not bool(taken["ok"]), "two points are not a parcel")
	assert(controller.document.count() == 0)
	controller.free()


# --- a warning is not a refusal -------------------------------------------------------


func test_a_loose_survey_is_taken_and_its_warning_is_not_a_refusal() -> void:
	var controller = _controller()
	assert(not SurveyFile.is_sound(_loose()) == false, "a warning is still sound")
	var taken: Dictionary = controller.import_survey(_loose())
	assert(bool(taken["ok"]), "half a foot of misclosure does not keep a survey off the plan")
	assert(controller.document.count() == 1)
	controller.free()


func test_a_sentence_can_be_put_on_the_status_line() -> void:
	var controller = _controller()
	controller.note("there is no survey file at C:/nowhere.txt")
	assert(controller.status().contains("no survey file"), "the drawing answers for what it was asked")
	controller.free()