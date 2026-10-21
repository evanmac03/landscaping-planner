extends Node
## Tests for the sheet set as the controller runs it: the set on the drawing, the paper the drawing is
## set up at, and the files a sheet and a whole set plot to.
##
## The controller is built with its parts but no scene tree, exactly as the fill and selection tools are.
## The one thing these tests touch outside memory is `user://sheets`, and each of them takes its own
## files away again.

const Ctrl := preload("res://scripts/draft/draft_controller.gd")
const Tool := preload("res://scripts/draft/draft_tool.gd")
const Document := preload("res://scripts/draft/draft_document.gd")
const SnapScript := preload("res://scripts/draft/snap_engine.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const SheetSetScript := preload("res://scripts/draft/sheet_set.gd")
const Irrigation := preload("res://scripts/draft/irrigation.gd")


func _controller():
	var controller = Ctrl.new()
	controller.document = Document.new()
	controller.snap = SnapScript.new()
	controller.tool = Tool.new()
	controller.document.add(
		Entity.make_rectangle(Vector2(0.0, 0.0), Vector2(12.0, 8.0)), LayerSet.NEW_BED
	)
	return controller


## A sheet is written to disk to be looked at, so the test takes it away again: a plot left behind in
## the user's folder is a file nobody asked for.
func _discard(path: String) -> void:
	if not path.is_empty():
		DirAccess.remove_absolute(path)


func _sheet_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_buffer(file.get_length()).get_string_from_utf8()
	file.close()
	return text


# --- the set the drawing owns ---------------------------------------------------------


func test_a_new_drawing_plots_as_one_sheet() -> void:
	var controller = _controller()
	assert(controller.sheet_set().count() == 1, "a drawing plots as at least one sheet")
	assert(controller.sheet == "A3")
	assert(controller.plot_scale == 100.0)
	assert(controller.sheet_number == controller.sheet_set().numbers()[0])
	controller.free()


func test_the_sheet_size_and_the_scale_are_one_thing_wherever_they_are_chosen() -> void:
	var controller = _controller()
	# The File menu sets the drawing's paper through the controller, and the sheet window edits the set.
	# Both are the same act, and this is what stops the two from disagreeing.
	assert(controller.set_sheet_size("A1"))
	assert(controller.sheet == "A1")
	assert(controller.sheet_set().sheet(0)["sheet"] == "A1", "and the set says so too")
	assert(not controller.set_sheet_size("B9"), "a sheet the plotter does not know is refused")
	assert(controller.sheet == "A1", "and refusing changes nothing")
	assert(controller.set_plot_scale(200.0))
	assert(controller.sheet_set().sheet(0)["scale"] == 200.0)
	assert(not controller.set_plot_scale(0.0), "there is no zero scale")
	controller.free()


func test_a_second_sheet_is_numbered_and_titled_after_the_one_in_hand() -> void:
	var controller = _controller()
	controller.drawing_title = "Layout plan"
	controller.save_sheet()
	var index: int = controller.add_sheet()
	assert(index == 1)
	assert(controller.sheet_set().count() == 2)
	assert(controller.sheet_set().numbers() == ["L1.1", "L1.2"], str(controller.sheet_set().numbers()))
	assert(controller.sheet_number == "L1.2", "the new sheet is the one in hand")
	assert(controller.drawing_title == "Layout plan", "and it is titled after the sheet it came from")
	# Adding a sheet is a change to the drawing, so it undoes like one.
	assert(controller.document.undo_last())
	assert(controller.document.sheets.count() == 1)
	controller.free()


func test_choosing_a_sheet_moves_the_drawing_onto_its_paper() -> void:
	var controller = _controller()
	controller.add_sheet("Planting plan")
	assert(controller.set_sheet_field(1, "sheet", "A2"))
	assert(controller.set_sheet_field(1, "scale", 200.0))
	assert(controller.set_sheet_field(1, "portrait", true))
	assert(controller.sheet == "A2", "editing the current sheet moves the live paper with it")
	# Back to the first sheet: the drawing is set up as *that* sheet, not as the last one touched.
	assert(controller.load_sheet(0))
	assert(controller.sheet == "A3")
	assert(controller.plot_scale == 100.0)
	assert(not controller.portrait)
	assert(controller.drawing_title == "Landscaping Plan", controller.drawing_title)
	assert(not controller.load_sheet(7), "there is no such sheet to load")
	controller.free()


func test_the_current_sheet_titles_the_drawing_and_says_which_sheet_it_is() -> void:
	var controller = _controller()
	controller.add_sheet()
	assert(controller.set_sheet_field(1, "title", "Irrigation plan"))
	assert(controller.set_sheet_field(1, "revision", "B"))
	assert(controller.drawing_title == "Irrigation plan", "the DRAWING row is the sheet's own title")
	assert(controller.revision == "B", "and the revision is the sheet's")
	var rows: Array[Dictionary] = controller.sheet_rows()
	assert(rows.size() == 2)
	assert(bool(rows[1]["current"]), "the row in hand says so")
	assert(not bool(rows[0]["current"]))
	assert(String(rows[1]["description"]).contains("rev B"), String(rows[1]["description"]))
	controller.free()


func test_the_last_sheet_cannot_be_taken_away() -> void:
	var controller = _controller()
	assert(not controller.remove_sheet(0))
	assert(controller.sheet_set().count() == 1)
	assert(controller.last_message.contains("at least one sheet"), controller.last_message)
	controller.add_sheet()
	assert(controller.remove_sheet(0))
	assert(controller.sheet_set().count() == 1)
	assert(controller.sheet_set().current()["sheet"] == "A3", "the sheet left is the one in hand")
	controller.free()


# --- plotting -------------------------------------------------------------------------


func test_plotting_one_sheet_writes_that_sheet() -> void:
	var controller = _controller()
	controller.drawing_title = "Layout plan"
	controller.save_sheet()
	controller.add_sheet("Planting plan")
	assert(controller.set_sheet_field(1, "scale", 200.0))
	var path: String = controller.plot_sheet(1)
	assert(not path.is_empty(), controller.last_message)
	var text: String = _sheet_text(path)
	assert(text.begins_with("%PDF"), "a real PDF")
	assert(text.contains("Planting plan"), "the sheet's own title is on it")
	assert(text.contains("L1.2"), "and its drawing number")
	assert(text.contains("1:200"), "and the scale it was drawn at")
	assert(path.contains("L1-2"), "the file is named after the sheet, so two sheets do not collide")
	_discard(path)
	controller.free()


func test_plotting_a_sheet_that_is_not_there_writes_nothing() -> void:
	var controller = _controller()
	assert(controller.plot_sheet(4).is_empty())
	assert(controller.last_message.contains("no such sheet"), controller.last_message)
	controller.free()


## A zone is stored with the drawing, so the sheet's irrigation schedule needs no argument the way the
## planting list does: the controller reads it off the drawing it is plotting.
func test_a_watered_drawing_carries_its_irrigation_schedule_on_the_sheet() -> void:
	var controller = _controller()
	controller.set_irrigation_supply(60.0, 350.0)
	var bed: Dictionary = controller.waterable_areas()[0]
	var watered: Dictionary = controller.water_area(bed["outline"], Irrigation.SPRAY)
	assert(bool(watered["ok"]), String(watered.get("reason", "")))
	assert(controller.irrigation_rows().size() == 1, "one zone on the drawing")
	var path: String = controller.plot_sheet(0)
	assert(not path.is_empty(), controller.last_message)
	var text: String = _sheet_text(path)
	assert(text.contains("IRRIGATION SCHEDULE"), "the sheet carries the schedule")
	assert(text.contains("Zone 1"), "naming the zone it waters")
	assert(text.contains("will run"), "with what the module says about it")
	_discard(path)
	controller.free()


## An unwatered drawing gets no irrigation table rather than an empty one.
func test_a_drawing_that_is_not_watered_carries_no_irrigation_schedule() -> void:
	var controller = _controller()
	var path: String = controller.plot_sheet(0)
	assert(not path.is_empty(), controller.last_message)
	assert(not _sheet_text(path).contains("IRRIGATION SCHEDULE"))
	_discard(path)
	controller.free()


func test_plotting_the_set_writes_every_sheet_and_moves_nothing() -> void:
	var controller = _controller()
	controller.add_sheet("Planting plan")
	controller.set_sheet_field(1, "sheet", "A1")
	controller.load_sheet(0)
	var written: Array[String] = controller.plot_set()
	assert(written.size() == 2, "one file per sheet: %s" % str(written))
	assert(written[0] != written[1], "and each of them is its own file")
	assert(controller.last_message == "plotted 2 of 2 sheets", controller.last_message)
	# Plotting the set is not a way of moving the drawing: whoever plotted it is still on the sheet they
	# were working on.
	assert(controller.sheet == "A3", controller.sheet)
	assert(controller.sheet_set().current_index() == 0)
	assert(_sheet_text(written[1]).contains("L1.2"), "the second file is the second sheet")
	assert(_sheet_text(written[1]).contains("1:100"), "at its own scale, not the first sheet's")
	for path: String in written:
		_discard(path)
	controller.free()


func test_an_empty_drawing_plots_nothing_however_many_sheets_it_has() -> void:
	var controller = _controller()
	controller.document.clear()
	controller.add_sheet()
	assert(controller.plot_set().is_empty())
	assert(controller.last_message == "nothing to plot", controller.last_message)
	controller.free()


# --- the sheets travel in the file ----------------------------------------------------


func test_the_sheets_are_written_with_the_drawing_and_read_back() -> void:
	var path := "user://drawings/sheet-set-test.json"
	var controller = _controller()
	controller.project_name = "Riverbend"
	controller.drawing_title = "Layout plan"
	controller.save_sheet()
	controller.add_sheet("Planting plan")
	controller.set_sheet_field(1, "sheet", "A2")
	controller.set_sheet_field(1, "revision", "C")
	controller.set_sheet_field(1, "portrait", true)
	assert(bool(controller.save_drawing(path)["ok"]))
	var opened = Ctrl.new()
	opened.document = Document.new()
	opened.snap = SnapScript.new()
	opened.tool = Tool.new()
	assert(opened.open_drawing(path), opened.last_message)
	assert(opened.sheet_set().count() == 2, "the set came out of the file with the drawing")
	assert(opened.sheet_set().current()["sheet"] == "A2", "at A2")
	assert(opened.sheet == "A2", "and the drawing is set up as that sheet")
	assert(opened.revision == "C", "with its revision")
	assert(opened.portrait, "and its paper turned")
	assert(opened.drawing_title == "Planting plan")
	assert(opened.project_name == "Riverbend")
	assert(opened.sheet_set().project == "Riverbend", "the project is part of the set")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	controller.free()
	opened.free()


func test_a_drawing_from_before_sets_existed_opens_as_one_sheet() -> void:
	# Version 5 is the file before sheets: it is read for everything it has, and one sheet at the
	# drawing's own size stands in rather than a set of none.
	var controller = _controller()
	var saved: Dictionary = controller.document.to_dict()
	assert(int(saved["version"]) == 10, "this build writes version 10")
	saved["version"] = 5
	saved.erase("sheets")
	var legacy: DraftDocument = Document.from_dict(saved)
	assert(legacy.sheets.count() == 1, "one sheet")
	assert(legacy.sheets.sheet(0)["sheet"] == SheetSetScript.DEFAULT_SHEET)
	controller.free()