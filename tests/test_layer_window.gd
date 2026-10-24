extends Node
## The layers page: every layer on the drawing, the search that narrows them, and the two acts a person
## takes on one here - locking it against editing, and making it the layer new shapes are drawn on.
##
## The page is built by hand rather than popped up, because `popup_centered` needs a window server and a
## test process has not got one. Being shown is the window's own `visible` flag, and every test makes
## its own page and controller and frees them - an unfreed Node is a resource still in use at the end of
## the run.

const WindowScript := preload("res://scripts/layer_window.gd")
const ControllerScript := preload("res://scripts/draft/draft_controller.gd")
const DocumentScript := preload("res://scripts/draft/draft_document.gd")
const ToolScript := preload("res://scripts/draft/draft_tool.gd")
const LayersScript := preload("res://scripts/draft/layer_set.gd")


## A bare controller with a fresh drawing on it: the same thing `test_layer_dialog.gd` drives.
func _controller() -> ControllerScript:
	var controller: ControllerScript = ControllerScript.new()
	controller.document = DocumentScript.new()
	controller.tool = ToolScript.new()
	return controller


func test_the_page_lists_every_layer_the_drawing_has() -> void:
	var controller := _controller()
	var page: WindowScript = WindowScript.new()
	page.build()
	page.bind(controller)
	var total: int = controller.document.layers.layers().size()
	assert(total > 1, "a new drawing has more than one layer to choose between")
	assert(page.shown_count() == total, str(page.shown_count()))
	assert(page.list_rows().size() == total, "and one row for each")
	assert(page.search_field() != null, "with a box to search them by")
	assert(page.layers_list() != null)
	page.free()
	controller.free()


func test_typing_a_word_narrows_the_list_and_clearing_brings_it_back() -> void:
	var controller := _controller()
	var page: WindowScript = WindowScript.new()
	page.build()
	page.bind(controller)
	page.type_search("new-bed")
	assert(page.shown_count() == 1, str(page.shown_count()))
	assert(page.selected_layer() == LayersScript.NEW_BED)
	assert(page.list_rows()[0].contains(String(LayersScript.NEW_BED)))
	page.type_search("")
	assert(
		page.shown_count() == controller.document.layers.layers().size(),
		"emptying the box is the way back to every layer"
	)
	page.free()
	controller.free()


func test_locking_the_chosen_layer_is_one_undoable_step() -> void:
	var controller := _controller()
	var page: WindowScript = WindowScript.new()
	page.build()
	page.bind(controller)
	assert(page.select_layer(LayersScript.NEW_BED))
	assert(page.toggle_lock(), "it is locked now")
	assert(page.status_text().contains("Locked"), page.status_text())
	assert(controller.document.is_layer_locked(LayersScript.NEW_BED))
	var marks_the_row := false
	for row: String in page.list_rows():
		if row.contains(String(LayersScript.NEW_BED)) and row.contains("[locked]"):
			marks_the_row = true
	assert(marks_the_row, "the row for the locked layer says so")
	assert(controller.document.undo_last(), "the lock is one undo step")
	assert(not controller.document.is_layer_locked(LayersScript.NEW_BED))
	page.free()
	controller.free()


func test_making_the_chosen_layer_current_goes_through_the_controller() -> void:
	var controller := _controller()
	var page: WindowScript = WindowScript.new()
	page.build()
	page.bind(controller)
	assert(page.select_layer(LayersScript.NEW_BED))
	assert(page.make_current())
	assert(controller.current_layer() == LayersScript.NEW_BED)
	assert(page.status_text().contains("new shapes"), page.status_text())
	page.free()
	controller.free()


func test_a_search_that_finds_nothing_says_so_and_acts_on_nothing() -> void:
	var controller := _controller()
	var page: WindowScript = WindowScript.new()
	page.build()
	page.bind(controller)
	page.type_search("zzz-nothing")
	assert(page.shown_count() == 0)
	assert(page.status_text().contains("No layer matches"), page.status_text())
	assert(page.selected_layer() == &"")
	# An act with nothing chosen does nothing rather than reaching through a missing layer.
	assert(not page.toggle_lock())
	assert(not page.make_current())
	page.free()
	controller.free()


func test_nothing_on_the_page_takes_the_keyboard_but_the_search_box() -> void:
	var controller := _controller()
	var page: WindowScript = WindowScript.new()
	page.build()
	page.bind(controller)
	assert(page.search_field() is LineEdit, "the box is the one control that types")
	assert(page.layers_list().focus_mode == Control.FOCUS_NONE)
	for child in page.get_node("Column/Actions").get_children():
		assert((child as Control).focus_mode == Control.FOCUS_NONE, "no button takes the keyboard")
	assert((page.get_node("Column/CloseRow/Close") as Control).focus_mode == Control.FOCUS_NONE)
	page.free()
	controller.free()


func test_a_lock_and_a_change_of_current_layer_are_announced_apart() -> void:
	var controller := _controller()
	var page: WindowScript = WindowScript.new()
	page.build()
	page.bind(controller)
	var announced: Array[int] = []
	page.layers_changed.connect(func() -> void: announced.append(1))
	assert(page.select_layer(LayersScript.NEW_BED))
	page.toggle_lock()
	page.make_current()
	assert(announced.size() == 2, "a lock and a change of current layer are two announcements")
	page.free()
	controller.free()