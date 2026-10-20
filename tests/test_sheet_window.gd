extends Node
## Tests for the sheet setup window: one row per sheet, the form of the sheet in hand, and the intents
## a person's clicks turn into.
##
## Built by hand and driven through the same methods the controls are wired to, so there is no scene
## tree, no HUD, no drawing and no plotter. The window owns none of those things: it shows what it was
## handed by `set_sheets`, and everything a person does leaves as a signal for the HUD to answer.

const WindowScript := preload("res://scripts/sheet_window.gd")
const SheetSetScript := preload("res://scripts/draft/sheet_set.gd")


## A window showing a two-sheet set, as `DraftController.sheet_rows()` describes one.
func _window() -> SheetWindow:
	var window: SheetWindow = WindowScript.new()
	window.build()
	window.set_identity("Riverbend", "2026-05-04")
	window.set_sheets(_rows())
	return window


func _row(index: int, title: String, number: String, portrait: bool = false) -> Dictionary:
	return {
		"index": index, "title": title, "number": number, "revision": "",
		"sheet": "A3", "scale": 100.0, "legend": true, "portrait": portrait,
		"current": index == 0, "description": "%s  %s  1:100 on A3" % [number, title],
	}


func _rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = [_row(0, "Layout plan", "L1.1"), _row(1, "Planting plan", "L1.2")]
	return rows


## What the window announced, in the order it announced it.
func _record(window: SheetWindow) -> Array:
	var seen: Array = []
	window.field_changed.connect(
		func(index: int, field: String, value: Variant) -> void: seen.append([index, field, value])
	)
	window.identity_changed.connect(
		func(field: String, value: String) -> void: seen.append([-1, field, value])
	)
	window.sheet_added.connect(func() -> void: seen.append(["added"]))
	window.sheet_removed.connect(func(index: int) -> void: seen.append(["removed", index]))
	window.sheet_selected.connect(func(index: int) -> void: seen.append(["selected", index]))
	window.plot_requested.connect(func(index: int) -> void: seen.append(["plot", index]))
	window.plot_set_requested.connect(func() -> void: seen.append(["plot set"]))
	window.closed.connect(func() -> void: seen.append(["closed"]))
	return seen


# --- what it shows --------------------------------------------------------------------


func test_the_rows_the_drawing_describes_are_the_rows_listed() -> void:
	var window: SheetWindow = _window()
	assert(window.row_count() == 2)
	assert(window.list_texts() == ["L1.1  Layout plan", "L1.2  Planting plan"], str(window.list_texts()))
	assert(window.selected_index() == 0, "the first sheet is the one in hand")
	assert(window.field_text("title") == "Layout plan")
	assert(window.field_text("number") == "L1.1")
	window.free()


func test_the_form_is_filled_from_the_sheet_in_hand() -> void:
	var window: SheetWindow = _window()
	window.select(1)
	assert(window.field_text("title") == "Planting plan", "the form follows the list")
	assert(window.field_text("number") == "L1.2")
	assert(window.field_text("revision") == "")
	assert(window.sheet_choice() == "A3")
	assert(window.scale_choice() == 100.0)
	assert(window.flag("legend"), "and the flags follow it too")
	assert(not window.flag("portrait"))
	window.free()


func test_a_sheet_turned_portrait_shows_it_turned() -> void:
	var window: SheetWindow = _window()
	window.set_sheets([_row(0, "Layout plan", "L1.1", true)])
	assert(window.flag("portrait"), "the box is ticked for a portrait sheet")
	window.free()


func test_the_status_line_is_the_sheet_s_own_line_until_a_plot_says_otherwise() -> void:
	var window: SheetWindow = _window()
	assert(window.status_text().contains("L1.1"), window.status_text())
	window.say("plotted 2 of 2 sheets")
	assert(window.status_text() == "plotted 2 of 2 sheets", "what just happened outranks what it is")
	window.free()


func test_an_empty_form_says_nothing_rather_than_failing() -> void:
	var window: SheetWindow = WindowScript.new()
	window.build()
	# A HUD that has not been given a drawing yet: every control has to exist and none of them may be
	# pressed into a crash.
	assert(window.row_count() == 0)
	assert(window.selected_row().is_empty())
	assert(not window.type_field("title", "x"), "there is no such field to type in")
	assert(not window.tick_flag("colour", true), "nor such a flag")
	assert(window.status_text() == "")
	window.free()


# --- what a person does ---------------------------------------------------------------


func test_typing_a_field_announces_the_sheet_it_belongs_to() -> void:
	var window: SheetWindow = _window()
	var seen: Array = _record(window)
	window.select(1)
	assert(window.type_field("title", "Planting plan rev B"))
	assert(seen == [[1, "title", "Planting plan rev B"]], str(seen))
	window.free()


func test_choosing_paper_and_scale_announce_what_was_chosen() -> void:
	var window: SheetWindow = _window()
	var seen: Array = _record(window)
	assert(window.choose_sheet("A1"))
	assert(window.choose_scale(200.0))
	assert(not window.choose_sheet("B9"), "a sheet the plotter does not know is not chosen")
	assert(not window.choose_scale(33.0), "nor a ratio off the ladder")
	assert(window.tick_flag("portrait", true))
	assert(seen.size() == 3, str(seen))
	assert(seen[0] == [0, "sheet", "A1"], str(seen[0]))
	assert(seen[1] == [0, "scale", 200.0], str(seen[1]))
	assert(seen[2] == [0, "portrait", true], str(seen[2]))
	window.free()


func test_the_project_and_the_date_are_announced_for_the_whole_set() -> void:
	var window: SheetWindow = _window()
	var seen: Array = _record(window)
	assert(window.type_identity("project", "Maple Street"))
	assert(window.type_identity("date", "2026-06-01"))
	assert(not window.type_identity("soil", "sandy"), "there is no such shared field")
	assert(seen == [[-1, "project", "Maple Street"], [-1, "date", "2026-06-01"]], str(seen))
	window.free()


func test_adding_and_removing_announce_themselves() -> void:
	var window: SheetWindow = _window()
	var seen: Array = _record(window)
	window.select(1)
	window.sheet_removed.emit(window.selected_index())
	assert(seen == [["removed", 1]], str(seen))
	window.sheet_added.emit()
	assert(seen.size() == 2 and seen[1][0] == "added", str(seen))
	window.free()


func test_plotting_announces_which_sheet_and_whether_the_whole_set() -> void:
	var window: SheetWindow = _window()
	var seen: Array = _record(window)
	window.select(1)
	window.plot_requested.emit(window.selected_index())
	window.plot_set_requested.emit()
	assert(seen == [["plot", 1], ["plot set"]], str(seen))
	window.free()


# --- what may not happen --------------------------------------------------------------


## Filling the form must not read back as an edit. If it did, every refresh would announce the fields the
## window just wrote, the controller would write them again, and the set would rebuild under the cursor on
## every keystroke.
func test_filling_the_form_announces_nothing() -> void:
	var window: SheetWindow = _window()
	var seen: Array = _record(window)
	window.set_sheets(_rows())
	window.set_identity("Riverbend", "2026-05-04")
	window.select(1)
	# Moving the form from one sheet to another is the HUD's own act, not a person's, so it announces
	# nothing either: the HUD asked for it and already knows.
	assert(seen.is_empty(), "no edit is announced by filling the form: %s" % str(seen))
	window.free()


func test_the_selection_survives_the_rows_being_replaced() -> void:
	# A field is edited, the HUD writes it back and re-describes the set: the form must still be showing
	# the sheet the person was working on rather than jumping to the first one.
	var window: SheetWindow = _window()
	window.select(1)
	var changed: Array[Dictionary] = _rows()
	changed[1]["description"] = "L1.2  Planting plan rev B  1:100 on A3"
	window.set_sheets(changed)
	assert(window.selected_index() == 1, "the same sheet is still in the form")
	assert(window.field_text("title") == "Planting plan")
	window.set_sheets([])
	assert(window.row_count() == 0, "and a set that is gone leaves an empty form rather than a crash")
	window.free()


func test_a_paper_size_is_named_by_its_size_as_well_as_its_name() -> void:
	# "A3" means nothing to somebody who has only ever bought paper in inches, so the drop-down says both.
	assert(WindowScript.sheet_label("A3") == "A3  (420 x 297 mm)", WindowScript.sheet_label("A3"))
	assert(WindowScript.sheet_label("A4") == "A4  (297 x 210 mm)", WindowScript.sheet_label("A4"))