extends Node
## Tests for the editing commands as the controller runs them: picking a shape,
## trimming it, extending it, offsetting it, rounding it, erasing it.
##
## The controller is built with its parts but no scene tree, and the commands are
## driven through `edit_at()`, which takes a model point rather than a screen
## point - the same split that lets the picking be tested without a canvas.

const Ctrl := preload("res://scripts/draft/draft_controller.gd")
const Tool := preload("res://scripts/draft/draft_tool.gd")
const Document := preload("res://scripts/draft/draft_document.gd")
const SnapScript := preload("res://scripts/draft/snap_engine.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")

const EditKind := Ctrl.EditKind


func _controller():
	var controller = Ctrl.new()
	controller.document = Document.new()
	controller.snap = SnapScript.new()
	controller.tool = Tool.new()
	return controller


func _line(x0: float, y0: float, x1: float, y1: float):
	return Entity.make_line(Vector2(x0, y0), Vector2(x1, y1))


# --- taking and leaving a command -----------------------------------------------------


func test_no_command_is_in_hand_until_one_is_taken() -> void:
	var controller = _controller()
	assert(not controller.is_editing())
	assert(controller.current_edit() == EditKind.NONE)
	assert(not controller.drawing, "and the tools are not armed either")
	controller.free()


func test_taking_an_edit_command_arms_the_tools() -> void:
	var controller = _controller()
	controller.arm_edit(EditKind.TRIM)
	assert(controller.is_editing())
	assert(controller.drawing, "an edit needs the drawing surface, so it arms it")
	assert(controller.status().contains("Trim"), "and the line says which command")
	controller.free()


func test_choosing_a_drawing_tool_puts_the_edit_away() -> void:
	var controller = _controller()
	controller.arm_edit(EditKind.FILLET)
	controller.set_tool(Tool.Kind.LINE)
	assert(not controller.is_editing(), "a drawing tool and an edit cannot both be in hand")
	controller.free()


func test_putting_the_tools_away_puts_the_edit_away_too() -> void:
	var controller = _controller()
	controller.arm_edit(EditKind.ERASE)
	controller.set_drawing(false)
	assert(not controller.is_editing())
	controller.free()


func test_escape_backs_out_of_a_half_made_edit_without_losing_the_command() -> void:
	var controller = _controller()
	controller.document.add(_line(0, 0, 10, 0), LayerSet.NEW_HARDSCAPE)
	controller.arm_edit(EditKind.OFFSET)
	controller.edit_at(Vector2(5, 0))
	assert(controller.status().contains("side and distance"), "the first pick has landed")
	controller.cancel()
	assert(controller.is_editing(), "the command is still in hand")
	assert(controller.status().contains("pick the shape"), "but it is waiting for the first pick again")
	controller.free()


# --- what the status line says --------------------------------------------------------


func test_the_status_line_prompts_the_next_pick() -> void:
	var controller = _controller()
	controller.arm_edit(EditKind.FILLET)
	assert(controller.status().contains("first line"))
	controller.document.add(_line(0, 0, 10, 0), LayerSet.NEW_HARDSCAPE)
	controller.edit_at(Vector2(5, 0))
	assert(controller.status().contains("second line"))
	assert(controller.status().contains("radius"), "and the radius it will round with")
	controller.free()


func test_a_fillet_radius_that_is_not_a_length_is_refused() -> void:
	var controller = _controller()
	assert(not controller.set_fillet_radius(0.0))
	assert(not controller.set_fillet_radius(-1.0))
	assert(controller.set_fillet_radius(0.25))
	assert(is_equal_approx(controller.fillet_radius, 0.25))
	controller.free()


# --- erase ------------------------------------------------------------------------


func test_erasing_takes_the_picked_shape_off_the_drawing() -> void:
	var controller = _controller()
	controller.document.add(_line(0, 0, 10, 0), LayerSet.NEW_HARDSCAPE)
	controller.arm_edit(EditKind.ERASE)
	controller.edit_at(Vector2(5, 0.05))
	assert(controller.document.count() == 0, "the line is gone")
	controller.free()


func test_erasing_nothing_says_so() -> void:
	var controller = _controller()
	controller.document.add(_line(0, 0, 10, 0), LayerSet.NEW_HARDSCAPE)
	controller.arm_edit(EditKind.ERASE)
	controller.edit_at(Vector2(5, 5))
	assert(controller.document.count() == 1, "nothing was picked, so nothing went")
	assert(controller.last_message.contains("nothing"), "and it said so")
	controller.free()


func test_an_annotation_cannot_be_erased() -> void:
	var controller = _controller()
	controller.document.add(
		Entity.make_text(Vector2(5, 0), "patio"), LayerSet.TEXT
	)
	controller.arm_edit(EditKind.ERASE)
	controller.edit_at(Vector2(5, 0))
	assert(controller.document.count() == 1, "a note is not a site feature to erase")
	controller.free()


# --- trim -------------------------------------------------------------------------


func test_trimming_cuts_a_line_where_something_crosses_it() -> void:
	var controller = _controller()
	controller.document.add(_line(0, 0, 10, 0), LayerSet.NEW_HARDSCAPE)
	controller.document.add(_line(5, -1, 5, 1), LayerSet.NEW_HARDSCAPE)
	controller.arm_edit(EditKind.TRIM)
	controller.edit_at(Vector2(7, 0))
	assert(controller.document.count() == 2, "the cutter and one kept piece remain")
	var found := false
	for entity in controller.document.entities():
		if entity.kind == Entity.Kind.LINE and is_equal_approx(entity.point(0).x, 0.0):
			found = true
			assert(is_equal_approx(entity.point(1).x, 5.0), "the line stops at the cut")
	assert(found, "the piece on the far side of the pick was kept")
	controller.free()


# --- extend -----------------------------------------------------------------------


func test_extending_grows_a_line_to_the_shape_beyond_it() -> void:
	var controller = _controller()
	controller.document.add(_line(0, 0, 5, 0), LayerSet.NEW_HARDSCAPE)
	controller.document.add(_line(10, -1, 10, 1), LayerSet.NEW_HARDSCAPE)
	controller.arm_edit(EditKind.EXTEND)
	controller.edit_at(Vector2(4.8, 0))
	var grown := false
	for entity in controller.document.entities():
		if entity.kind == Entity.Kind.LINE and is_equal_approx(entity.point(0).x, 0.0):
			grown = true
			assert(is_equal_approx(entity.point(1).x, 10.0), "it reached the wall")
	assert(grown, "the line it was pointed at is still there, longer")
	assert(controller.document.count() == 2)
	controller.free()


# --- offset -----------------------------------------------------------------------


func test_offsetting_adds_a_new_shape_and_keeps_the_old_one() -> void:
	var controller = _controller()
	controller.document.add(_line(0, 0, 10, 0), LayerSet.NEW_HARDSCAPE)
	controller.arm_edit(EditKind.OFFSET)
	controller.edit_at(Vector2(5, 0))
	assert(controller.document.count() == 1, "the first pick only chooses the shape")
	controller.edit_at(Vector2(5, 1))
	assert(controller.document.count() == 2, "the second makes the offset")
	var offset_found := false
	for entity in controller.document.entities():
		if entity.kind == Entity.Kind.LINE and is_equal_approx(entity.point(0).y, 1.0):
			offset_found = true
	assert(offset_found, "the offset sits the distance the click was away")
	controller.free()


func test_offsetting_to_the_other_side_goes_the_other_way() -> void:
	var controller = _controller()
	controller.document.add(_line(0, 0, 10, 0), LayerSet.NEW_HARDSCAPE)
	controller.arm_edit(EditKind.OFFSET)
	controller.edit_at(Vector2(5, 0))
	controller.edit_at(Vector2(5, -2))
	var offset_found := false
	for entity in controller.document.entities():
		if entity.kind == Entity.Kind.LINE and is_equal_approx(entity.point(0).y, -2.0):
			offset_found = true
	assert(offset_found, "the pick side is the side it offsets to")
	controller.free()


# --- fillet -----------------------------------------------------------------------


func test_filleting_replaces_a_corner_with_an_arc_and_two_short_lines() -> void:
	var controller = _controller()
	controller.document.add(_line(0, 0, 10, 0), LayerSet.NEW_HARDSCAPE)
	controller.document.add(_line(10, 0, 10, 10), LayerSet.NEW_HARDSCAPE)
	controller.set_fillet_radius(1.0)
	controller.arm_edit(EditKind.FILLET)
	controller.edit_at(Vector2(5, 0))
	controller.edit_at(Vector2(10, 5))
	assert(controller.document.count() == 3, "two trimmed lines and the arc")
	var arcs := 0
	for entity in controller.document.entities():
		if entity.kind == Entity.Kind.ARC:
			arcs += 1
	assert(arcs == 1, "exactly one arc was added")
	controller.free()


func test_filleting_needs_two_different_lines() -> void:
	var controller = _controller()
	controller.document.add(_line(0, 0, 10, 0), LayerSet.NEW_HARDSCAPE)
	controller.arm_edit(EditKind.FILLET)
	controller.edit_at(Vector2(5, 0))
	controller.edit_at(Vector2(8, 0))
	assert(controller.document.count() == 1, "the same line twice rounds nothing")
	assert(controller.last_message.contains("different"), "and it says why")
	controller.free()


# --- rotate -----------------------------------------------------------------------


## Turning replaces the shape rather than leaving a second one beside it. Offsetting makes a pair and
## keeps both, because offset is a drawing aid; turning something changes the thing that is there.
## The id survives too, so whatever else refers to the shape - a fill, a zone, the undo stack's idea
## of what is on the sheet - still finds it.
func test_turning_replaces_the_shape_rather_than_copying_it() -> void:
	var controller = _controller()
	var id: int = controller.document.add(_line(1, 0, 2, 0), LayerSet.NEW_HARDSCAPE)
	controller.arm_edit(EditKind.ROTATE)
	controller.edit_at(Vector2(1.5, 0.0))
	assert(controller.document.count() == 1, "the first pick only chooses the shape")
	controller.edit_at(Vector2(0, 0))
	assert(controller.document.count() == 1, "the second only sets the pivot")
	controller.edit_at(Vector2(0, 5))
	assert(controller.document.count() == 1, "and the third turns it in place")
	var turned = controller.document.get_entity(id)
	assert(turned != null, "it is still the same shape on the sheet")
	assert(turned.point(0).is_equal_approx(Vector2(0, 1)), "a click due north is a quarter turn")
	assert(turned.point(1).is_equal_approx(Vector2(0, 2)), "so +x became +y")
	controller.free()


func test_a_turn_is_one_undoable_step() -> void:
	var controller = _controller()
	controller.document.add(_line(1, 0, 2, 0), LayerSet.NEW_HARDSCAPE)
	controller.arm_edit(EditKind.ROTATE)
	controller.edit_at(Vector2(1.5, 0.0))
	controller.edit_at(Vector2(0, 0))
	controller.edit_at(Vector2(0, 5))
	assert(controller.document.undo_last(), "a turn can be taken back")
	var back = controller.document.entities()[0]
	assert(back.point(1).is_equal_approx(Vector2(2, 0)), "and one step puts the whole shape back")
	controller.free()


func test_turning_nothing_says_so() -> void:
	var controller = _controller()
	controller.document.add(_line(0, 0, 10, 0), LayerSet.NEW_HARDSCAPE)
	controller.arm_edit(EditKind.ROTATE)
	controller.edit_at(Vector2(5, 5))
	assert(controller.document.count() == 1, "nothing was picked, so nothing turned")
	assert(controller.last_message.contains("nothing"), "and it said so")
	controller.free()


## The angle is the *bearing* of the third click, not a drag from the shape, so clicking back along
## the pivot is a turn of nothing and is refused rather than recorded as a step that did nothing.
func test_a_click_on_the_pivot_is_a_turn_of_nothing_and_is_refused() -> void:
	var controller = _controller()
	controller.document.add(_line(1, 0, 2, 0), LayerSet.NEW_HARDSCAPE)
	controller.arm_edit(EditKind.ROTATE)
	controller.edit_at(Vector2(1.5, 0.0))
	controller.edit_at(Vector2(0, 0))
	controller.edit_at(Vector2(0, 0))
	assert(controller.last_message.contains("nothing"), "turning by nothing is refused")
	assert(controller.document.entities()[0].point(1).is_equal_approx(Vector2(2, 0)), "unchanged")
	controller.free()


func test_the_status_line_prompts_each_of_the_turns_three_picks() -> void:
	var controller = _controller()
	controller.arm_edit(EditKind.ROTATE)
	assert(controller.status().contains("shape to turn"))
	controller.document.add(_line(1, 0, 2, 0), LayerSet.NEW_HARDSCAPE)
	controller.edit_at(Vector2(1.5, 0.0))
	assert(controller.status().contains("point to turn it about"))
	controller.edit_at(Vector2(0, 0))
	assert(controller.status().contains("direction to turn it to"))
	controller.edit_at(Vector2(0, 5))
	assert(controller.last_message.contains("90.0"), "and it reports the angle it turned by")
	controller.free()


# --- the layer lock -----------------------------------------------------------------


## The one door every editing command picks through. A locked shape is still on the sheet, so the
## command is not given a different shape by accident: it is told there is nothing to pick.
func test_a_locked_shape_is_not_picked_by_any_edit_command() -> void:
	var controller = _controller()
	controller.document.add(_line(0, 0, 10, 0), LayerSet.NEW_HARDSCAPE)
	controller.document.layers.set_locked(LayerSet.NEW_HARDSCAPE, true)
	controller.arm_edit(EditKind.ERASE)
	controller.edit_at(Vector2(5, 0.05))
	assert(controller.document.count() == 1, "a locked shape is not erased")
	assert(controller.last_message.contains("nothing"), "and the line says so")

	# Offset picks through the same door, so it is refused for the same reason.
	controller.arm_edit(EditKind.OFFSET)
	controller.edit_at(Vector2(5, 0.0))
	assert(controller.document.count() == 1, "and it is not offset either")
	assert(controller.last_message.contains("nothing"))
	controller.free()


## Locking one layer does not freeze the drawing: a locked shape is still on the sheet and still
## visible, and everything on the other layers stays perfectly editable.
func test_a_locked_layer_does_not_freeze_the_rest_of_the_drawing() -> void:
	var controller = _controller()
	controller.document.add(_line(0, 0, 10, 0), LayerSet.NEW_HARDSCAPE)
	controller.document.layers.set_locked(LayerSet.NEW_HARDSCAPE, true)
	controller.document.add(_line(0, 1, 10, 1), LayerSet.NEW_BED)
	controller.arm_edit(EditKind.ERASE)
	controller.edit_at(Vector2(5, 1.0))
	assert(controller.document.count() == 1, "the unlocked shape was picked and erased")
	assert(controller.document.entities()[0].layer == LayerSet.NEW_HARDSCAPE,
		"and the locked one is the shape left alone")
	controller.free()


## A locked layer is not one you can add to either. Drawing a line and finding it on the layer you
## had just locked would be the worst of both states: protected and unprotected at once.
##
## Driven through `_commit`, which is the one door a finished shape goes out by - both `click` and
## `finish` hand their shape to it - and with the same dictionary they hand over.
func test_nothing_is_drawn_onto_a_locked_layer() -> void:
	var controller = _controller()
	controller.set_layer(LayerSet.NEW_BED)
	controller.document.layers.set_locked(LayerSet.NEW_BED, true)
	controller._commit({"entity": _line(0, 0, 4, 0), "measure": null})
	assert(controller.document.count() == 0, "no line was added")
	assert(controller.last_message.contains("locked"), "and the line says why")
	assert(controller.document.layers.is_locked(LayerSet.NEW_BED), "the lock still stands")
	# And the very same commit lands once the lock is off, so the refusal was the lock and not the call.
	controller.document.layers.set_locked(LayerSet.NEW_BED, false)
	controller._commit({"entity": _line(0, 0, 4, 0), "measure": null})
	assert(controller.document.count() == 1, "and it lands with the lock off")
	controller.free()


# --- staying out of the way -------------------------------------------------------


func test_an_editing_command_does_nothing_with_no_command_in_hand() -> void:
	var controller = _controller()
	controller.document.add(_line(0, 0, 10, 0), LayerSet.NEW_HARDSCAPE)
	# edit_at with no command armed is a no-op rather than a crash.
	controller.edit_at(Vector2(5, 0))
	assert(controller.document.count() == 1)
	controller.free()