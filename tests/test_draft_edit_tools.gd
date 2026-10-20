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


# --- staying out of the way -------------------------------------------------------


func test_an_editing_command_does_nothing_with_no_command_in_hand() -> void:
	var controller = _controller()
	controller.document.add(_line(0, 0, 10, 0), LayerSet.NEW_HARDSCAPE)
	# edit_at with no command armed is a no-op rather than a crash.
	controller.edit_at(Vector2(5, 0))
	assert(controller.document.count() == 1)
	controller.free()