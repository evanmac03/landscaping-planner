extends Node
## Tests for selection as the controller runs it: arming the band, the two-corner
## gesture, the two modes, and what putting the tools away does to a selection.
##
## The controller is built with its parts but no scene tree, and the band is driven
## through `select_at()`, which takes a model point - the same split that lets the
## editing commands be tested without a canvas.

const Ctrl := preload("res://scripts/draft/draft_controller.gd")
const Tool := preload("res://scripts/draft/draft_tool.gd")
const Document := preload("res://scripts/draft/draft_document.gd")
const SnapScript := preload("res://scripts/draft/snap_engine.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const Select := preload("res://scripts/draft/draft_select.gd")

const EditKind := Ctrl.EditKind


func _controller():
	var controller = Ctrl.new()
	controller.document = Document.new()
	controller.snap = SnapScript.new()
	controller.tool = Tool.new()
	controller.arm_select(Select.MODE_WINDOW)
	return controller


func _add(controller, entity, layer: StringName = LayerSet.NEW_BED) -> int:
	return controller.document.add(entity, layer)


func _line(x0: float, y0: float, x1: float, y1: float):
	return Entity.make_line(Vector2(x0, y0), Vector2(x1, y1))


# --- the band -------------------------------------------------------------------------


func test_the_band_takes_two_corners() -> void:
	var controller = _controller()
	assert(controller.selection_mode() == Select.MODE_WINDOW)
	assert(controller.selected_count() == 0)
	var first: Dictionary = controller.select_at(Vector2(0.0, 0.0))
	assert(not bool(first["ok"]), "one corner is not a band")
	assert(int(first["progress"]) == 1, "the band is waiting for its opposite corner")
	assert(controller.selected_count() == 0, "and nothing is selected yet")
	controller.free()


func test_a_completed_band_selects_what_is_inside_it() -> void:
	var controller = _controller()
	var inside := _add(controller, _line(2.0, 2.0, 8.0, 8.0))
	_add(controller, _line(20.0, 20.0, 30.0, 30.0))
	var caught: Dictionary = controller.select_at(Vector2(0.0, 0.0))
	assert(not bool(caught["ok"]))
	caught = controller.select_at(Vector2(10.0, 10.0))
	assert(bool(caught["ok"]), String(caught["reason"]))
	assert(controller.selection() == [inside], "only what was wholly inside: %s" % str(controller.selection()))
	assert(controller.selected_count() == 1)
	assert(int(caught["progress"]) == 0, "and the band is finished")
	controller.free()


func test_the_mode_decides_what_a_band_catches() -> void:
	var controller = _controller()
	var poking := _add(controller, _line(2.0, 2.0, 12.0, 8.0))
	controller.select_at(Vector2(0.0, 0.0))
	controller.select_at(Vector2(10.0, 10.0))
	assert(controller.selected_count() == 0, "a window does not take a shape that pokes out")

	assert(controller.set_select_mode(Select.MODE_CROSSING), "the mode can be changed")
	controller.clear_selection()
	controller.select_at(Vector2(0.0, 0.0))
	controller.select_at(Vector2(10.0, 10.0))
	assert(controller.selection() == [poking], "and then the same band takes it")
	controller.free()


func test_a_mode_nobody_has_is_refused() -> void:
	var controller = _controller()
	assert(not controller.set_select_mode(&"lasso"), "there is no third mode")
	assert(controller.selection_mode() == Select.MODE_WINDOW, "and the mode is not moved by asking")
	controller.free()


func test_a_band_with_no_area_is_refused_and_the_corner_is_kept() -> void:
	var controller = _controller()
	_add(controller, _line(2.0, 2.0, 8.0, 8.0))
	controller.select_at(Vector2(0.0, 0.0))
	var refused: Dictionary = controller.select_at(Vector2(0.0, 0.0))
	assert(not bool(refused["ok"]), "a double click is not a window")
	assert(String(refused["reason"]) == "a selection band with no area")
	assert(int(refused["progress"]) == 1, "the first corner is still there to finish from")
	var finished: Dictionary = controller.select_at(Vector2(10.0, 10.0))
	assert(bool(finished["ok"]), "so the next real corner completes the band")
	assert(controller.selected_count() == 1)
	controller.free()


func test_the_status_line_says_the_mode_the_pick_and_the_count() -> void:
	var controller = _controller()
	_add(controller, _line(2.0, 2.0, 8.0, 8.0))
	var waiting := controller.status()
	assert(waiting.contains("Window selection"), "the line names the mode: " + waiting)
	assert(waiting.contains("pick the first corner"), "and what the next click is for: " + waiting)
	controller.select_at(Vector2(0.0, 0.0))
	assert(controller.status().contains("pick the opposite corner"), "then it asks for the corner")
	controller.select_at(Vector2(10.0, 10.0))
	assert(controller.status().contains("1 selected"), "then it says what it caught: " + controller.status())
	controller.free()


func test_the_drawing_says_what_was_selected() -> void:
	var controller = _controller()
	_add(controller, _line(2.0, 2.0, 8.0, 8.0))
	controller.select_at(Vector2(0.0, 0.0))
	controller.select_at(Vector2(10.0, 10.0))
	assert(controller.last_message == "1 shape selected (window)", controller.last_message)
	controller.free()


# --- living with the selection --------------------------------------------------------


func test_escape_drops_a_half_made_band_and_keeps_the_selection() -> void:
	var controller = _controller()
	var inside := _add(controller, _line(2.0, 2.0, 8.0, 8.0))
	controller.select_at(Vector2(0.0, 0.0))
	controller.select_at(Vector2(10.0, 10.0))
	controller.select_at(Vector2(30.0, 30.0))
	controller.cancel()
	assert(controller.selected_count() == 1, "the selection that was made stays: %s" % str(controller.selection()))
	assert(controller.selection() == [inside])
	# The next click starts a band rather than completing the one escape dropped.
	var restart: Dictionary = controller.select_at(Vector2(0.0, 0.0))
	assert(int(restart["progress"]) == 1, "and the band starts again")
	controller.free()


func test_choosing_another_tool_ends_the_selection() -> void:
	var controller = _controller()
	_add(controller, _line(2.0, 2.0, 8.0, 8.0))
	controller.select_at(Vector2(0.0, 0.0))
	controller.select_at(Vector2(10.0, 10.0))
	assert(controller.selected_count() == 1)
	controller.set_tool(Tool.Kind.LINE)
	assert(controller.selected_count() == 0,
		"a highlight no command can act on is a lie about what is in hand")
	controller.free()


func test_putting_the_tools_away_ends_the_selection() -> void:
	var controller = _controller()
	_add(controller, _line(2.0, 2.0, 8.0, 8.0))
	controller.select_at(Vector2(0.0, 0.0))
	controller.select_at(Vector2(10.0, 10.0))
	assert(controller.selected_count() == 1)
	controller.set_drawing(false)
	assert(controller.selected_count() == 0, "the tools are away, so there is nothing to select for")
	controller.free()


func test_taking_an_edit_command_puts_the_band_away() -> void:
	var controller = _controller()
	controller.arm_edit(EditKind.ERASE)
	assert(not controller.is_editing() == false, "the command is in hand")
	assert(controller.selection_mode() == Select.MODE_WINDOW, "the mode it was left in is remembered")
	var back: bool = controller.arm_select(Select.MODE_CROSSING)
	assert(back, "and taking a mode back puts the band in hand")
	assert(not controller.is_editing(), "which means the edit command is put away")
	assert(controller.selection_mode() == Select.MODE_CROSSING)
	controller.free()


func test_an_edit_command_outranks_the_band() -> void:
	var controller = _controller()
	var line := _add(controller, _line(2.0, 2.0, 8.0, 8.0))
	controller.arm_select(Select.MODE_WINDOW)
	controller.arm_edit(EditKind.ERASE)
	# In hand: an erase. The band must not answer the click.
	controller.edit_at(Vector2(5.0, 5.0))
	assert(controller.document.count() == 0, "the shape was erased, so the pick was the edit's")
	assert(line > 0)
	controller.free()


# --- selecting everything -------------------------------------------------------------


## Select-all is a selection, and a selection is the first step of changing something, so it leaves
## a locked layer out for the same reason an editing command cannot pick one.
func test_select_all_leaves_out_a_locked_layer() -> void:
	var controller = _controller()
	_add(controller, _line(1.0, 1.0, 2.0, 2.0))
	_add(controller, _line(3.0, 3.0, 4.0, 4.0), LayerSet.NEW_PLANTING)
	assert(controller.select_all() == 2, "nothing is protected yet")
	controller.document.layers.set_locked(LayerSet.NEW_PLANTING, true)
	assert(controller.select_all() == 1, "a locked layer is left out of select-all")
	assert(controller.document.count() == 2, "and is still on the drawing")
	controller.free()


## The band is the other way a selection is made, and it reads the same door.
func test_a_band_does_not_catch_a_locked_layer() -> void:
	var controller = _controller()
	_add(controller, _line(1.0, 1.0, 2.0, 2.0))
	_add(controller, _line(3.0, 3.0, 4.0, 4.0), LayerSet.NEW_PLANTING)
	controller.document.layers.set_locked(LayerSet.NEW_PLANTING, true)
	controller.select_at(Vector2(0.0, 0.0))
	controller.select_at(Vector2(5.0, 5.0))
	var caught := controller.selection()
	assert(caught.size() == 1, "only the unlocked shape was caught")
	assert(caught[0] == 1, "and it is the one on the bed layer")
	controller.free()


func test_select_all_takes_everything_on_a_visible_layer() -> void:
	var controller = _controller()
	var one := _add(controller, _line(1.0, 1.0, 2.0, 2.0))
	var two := _add(controller, _line(3.0, 3.0, 4.0, 4.0))
	var hidden := _add(controller, _line(5.0, 5.0, 6.0, 6.0), LayerSet.NEW_PLANTING)
	controller.document.layers.set_visible(LayerSet.NEW_PLANTING, false)
	assert(controller.select_all() == 2, "two shapes: the hidden layer is not on the sheet")
	assert(controller.selection() == [one, two])
	assert(controller.is_selected(one) and controller.is_selected(two))
	assert(not controller.is_selected(hidden), "a shape on a hidden layer is not taken")
	assert(controller.last_message == "2 shapes selected (window)", controller.last_message)
	controller.free()


func test_select_all_on_an_empty_drawing_selects_nothing_and_says_so() -> void:
	var controller = _controller()
	assert(controller.select_all() == 0)
	assert(controller.last_message == "0 shapes selected (window)", controller.last_message)
	controller.free()


func test_the_selected_shapes_can_be_read_back_and_measured() -> void:
	var controller = _controller()
	var inside := _add(controller, _line(1.0, 1.0, 4.0, 5.0))
	_add(controller, _line(50.0, 50.0, 60.0, 60.0))
	controller.select_at(Vector2(0.0, 0.0))
	controller.select_at(Vector2(10.0, 10.0))
	var chosen := controller.selected_entities()
	assert(chosen.size() == 1)
	assert(int(chosen[0].id) == inside, "the shape that was caught, not the one that was not")
	assert(controller.selection_bounds() == Rect2(1.0, 1.0, 3.0, 4.0),
		"a band of the selection's own: %s" % str(controller.selection_bounds()))
	controller.free()


func test_a_selection_outlives_nothing_it_cannot_find() -> void:
	var controller = _controller()
	var doomed := _add(controller, _line(1.0, 1.0, 4.0, 5.0))
	controller.select_at(Vector2(0.0, 0.0))
	controller.select_at(Vector2(10.0, 10.0))
	assert(controller.selected_count() == 1)
	controller.document.remove(doomed)
	assert(controller.selected_count() == 1, "the id is still remembered")
	assert(controller.selected_entities().is_empty(), "but a shape that has gone is not handed back")
	assert(controller.selection_bounds() == Rect2(), "and it has no bounds to speak of")
	controller.free()