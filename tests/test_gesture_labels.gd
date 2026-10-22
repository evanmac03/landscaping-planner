extends Node
## Tests for the words the gestures are recorded under, and for the join between the undo history and
## the named revisions.
##
## The history itself is held down alone in `test_gesture_history.gd`. What this file is about is the
## other half: that the *acts* - a drawing tool, an editing command, an import, a watering, a lock -
## say what they are when they record a gesture, and that a revision can say how much has happened
## since it was taken.
##
## The controller is built with its parts and no scene tree, as the editing and watering commands are
## tested: none of this needs a canvas, because a label is bookkeeping rather than a picture.

const Ctrl := preload("res://scripts/draft/draft_controller.gd")
const Tool := preload("res://scripts/draft/draft_tool.gd")
const Document := preload("res://scripts/draft/draft_document.gd")
const SnapScript := preload("res://scripts/draft/snap_engine.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const Irrigation := preload("res://scripts/draft/irrigation.gd")
const Lighting := preload("res://scripts/draft/lighting.gd")
const LogScript := preload("res://scripts/draft/revision_log.gd")
const History := preload("res://scripts/draft/gesture_history.gd")
const Hud := preload("res://scripts/hud.gd")

const EditKind := Ctrl.EditKind


func _controller():
	var controller = Ctrl.new()
	controller.document = Document.new()
	controller.snap = SnapScript.new()
	controller.tool = Tool.new()
	return controller


func _line(x0: float, y0: float, x1: float, y1: float):
	return Entity.make_line(Vector2(x0, y0), Vector2(x1, y1))


## A nine metre square: two throws each way, so a spray zone comes out the textbook nine heads.
func _bed(metres: float = 9.0) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(metres, 0.0), Vector2(metres, metres), Vector2(0.0, metres),
	])


## One shape in the shape table, as any of the three readers fills it.
func _shape() -> Dictionary:
	return {
		"kind": "LINE", "layer": LayerSet.UNDERLAY,
		"points": PackedVector2Array([Vector2(0.0, 0.0), Vector2(2.0, 0.0)]),
		"bulges": PackedFloat64Array(), "closed": false,
		"words": "", "height": 0.0, "arc": Vector2.ZERO,
	}


## What a reader hands the controller: a table with something drawable in it.
func _plan() -> Dictionary:
	return {"ok": true, "shapes": [_shape()], "underlay": true}


# --- the acts name themselves ---------------------------------------------------------


func test_drawing_a_line_names_the_gesture() -> void:
	var controller = _controller()
	controller.set_drawing(true)
	# A polyline rather than a line: a line commits on its second pick, and there is no canvas here to
	# hand the pick to. A shape that is finished by hand goes through `finish()`, which is the same door
	# the palette's Finish button uses.
	controller.arm(Tool.Kind.POLYLINE)
	controller.tool.click(Vector2(0.0, 0.0))
	controller.tool.click(Vector2(4.0, 0.0))
	controller.finish()
	assert(controller.document.count() == 1, "the polyline is on the drawing")
	assert(controller.document.undo_label() == "drawing a new polyline",
		"and the undo says which shape it would take back: %s" % controller.document.undo_label())
	controller.free()


func test_every_drawing_tool_reads_as_a_sentence() -> void:
	# The words come from the tool, so a tool renamed or a word that reads badly shows up here as the
	# undo button's own line. "a aligned dimension" is the mistake this is here to catch.
	var controller = _controller()
	for kind: int in [Tool.Kind.LINE, Tool.Kind.POLYLINE, Tool.Kind.CIRCLE, Tool.Kind.ARC]:
		controller.document.begin_gesture("drawing a new %s" % Tool.label_for(kind).to_lower())
		assert(controller.document.undo_label() == "drawing a new %s" % Tool.label_for(kind).to_lower())
	assert("drawing a new %s" % Tool.label_for(Tool.Kind.DIMENSION).to_lower()
		== "drawing a new aligned dimension")
	assert("drawing a new %s" % Tool.label_for(Tool.Kind.DIMENSION_RADIUS).to_lower()
		== "drawing a new radial dimension")
	assert("drawing a new %s" % Tool.label_for(Tool.Kind.DIMENSION_ANGULAR).to_lower()
		== "drawing a new angular dimension")
	controller.free()


func test_erasing_names_the_gesture() -> void:
	var controller = _controller()
	controller.document.add(_line(0.0, 0.0, 10.0, 0.0), LayerSet.NEW_HARDSCAPE)
	controller.arm_edit(EditKind.ERASE)
	controller.edit_at(Vector2(5.0, 0.0))
	assert(controller.document.count() == 0, "the shape is off the drawing")
	assert(controller.document.undo_label() == "erasing")
	controller.free()


func test_turning_a_shape_names_the_gesture() -> void:
	var controller = _controller()
	controller.document.add(_line(1.0, 0.0, 2.0, 0.0), LayerSet.NEW_HARDSCAPE)
	controller.arm_edit(EditKind.ROTATE)
	controller.edit_at(Vector2(1.5, 0.0))
	controller.edit_at(Vector2(0.0, 0.0))
	controller.edit_at(Vector2(0.0, 5.0))
	assert(controller.document.undo_label() == "turning a shape")
	controller.free()


func test_moving_and_copying_name_their_gestures() -> void:
	var controller = _controller()
	controller.document.add(_line(1, 0, 2, 0), LayerSet.NEW_HARDSCAPE)
	controller.arm_edit(EditKind.MOVE)
	controller.edit_at(Vector2(1.5, 0.0))
	controller.edit_at(Vector2(0, 0))
	controller.edit_at(Vector2(0, 5))
	assert(controller.document.undo_label() == "moving a shape",
		"a move says so: %s" % controller.document.undo_label())
	controller.arm_edit(EditKind.COPY)
	controller.edit_at(Vector2(1.5, 5.0))
	controller.edit_at(Vector2(0, 0))
	controller.edit_at(Vector2(5, 0))
	assert(controller.document.undo_label() == "copying a shape",
		"and so does a copy: %s" % controller.document.undo_label())
	assert(controller.document.count() == 2, "which leaves two shapes rather than one")
	controller.free()


func test_simplifying_names_the_gesture() -> void:
	var controller = _controller()
	var polyline := Entity.make_polyline(PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(5.0, 0.0), Vector2(5.0, 0.002), Vector2(10.0, 0.0),
	]), false)
	controller.document.add(polyline, LayerSet.NEW_HARDSCAPE)
	var report = controller.plan_simplify()
	assert(controller.apply_simplify(report) == 1, "the redundant point comes out")
	assert(controller.document.undo_label() == "simplifying the drawing")
	controller.free()


func test_each_reader_names_its_own_import() -> void:
	var controller = _controller()
	controller.import_dxf(_plan())
	assert(controller.document.undo_label() == "importing a DXF underlay",
		"the reader that read it is what says what it was: %s" % controller.document.undo_label())
	controller.import_osm(_plan())
	assert(controller.document.undo_label() == "importing a site map")
	controller.import_landxml(_plan())
	assert(controller.document.undo_label() == "importing a LandXML plat")
	assert(controller.document.count() == 3, "three files, three shapes, three gestures")
	controller.free()


func test_watering_names_its_gestures() -> void:
	var controller = _controller()
	controller.set_irrigation_supply(120.0, 350.0)
	assert(controller.document.undo_label() == "stating the water supply")
	var watered: Dictionary = controller.water_area(_bed(), Irrigation.SPRAY)
	assert(bool(watered["ok"]), "the bed takes a spray zone: %s" % String(watered.get("reason", "")))
	assert(controller.document.undo_label() == "watering an area")
	controller.remove_zone(1)
	assert(controller.document.undo_label() == "taking the water off an area")
	controller.free()


func test_lighting_names_its_gestures() -> void:
	var controller = _controller()
	controller.set_lighting_transformer(100.0, 12.0)
	assert(controller.document.undo_label() == "stating the transformer")
	var lit: Dictionary = controller.light_area(_bed(), Lighting.WELL)
	assert(bool(lit["ok"]), "the bed takes a well-light circuit: %s" % String(lit.get("reason", "")))
	assert(controller.document.undo_label() == "lighting an area")
	controller.remove_circuit(1)
	assert(controller.document.undo_label() == "taking the lighting off an area")
	controller.free()


func test_locking_a_layer_names_the_layer() -> void:
	var controller = _controller()
	controller.set_layer(LayerSet.NEW_HARDSCAPE)
	var hud := Hud.new()
	hud._draft = controller
	var layer_name: StringName = controller.current_layer()
	assert(not String(layer_name).is_empty(), "there is a layer in hand to lock: %s" % layer_name)
	hud.set_layer_locked(true)
	assert(controller.document.undo_label() == "locking %s" % layer_name,
		"a lock says which layer it is: %s" % controller.document.undo_label())
	hud.set_layer_locked(false)
	assert(controller.document.undo_label() == "unlocking %s" % layer_name)
	hud.free()
	controller.free()


# --- the join with the named revisions ------------------------------------------------


func test_a_revision_keeps_the_gesture_it_was_taken_at() -> void:
	var controller = _controller()
	controller.document.begin_gesture("drawing a new line")
	controller.document.add(_line(0.0, 0.0, 10.0, 0.0), LayerSet.NEW_HARDSCAPE)
	var revision: Dictionary = controller.capture_revision("sent to the client")
	assert(int(revision["serial"]) == 1, "the revision is taken at the drawing's first gesture")
	assert(controller.revisions.record_at(0).get("serial") == 1, "and that is what it keeps")
	assert(controller.gestures_since_text(0) == "nothing has been done to the drawing since")
	controller.arm_edit(EditKind.ERASE)
	controller.edit_at(Vector2(5.0, 0.0))
	assert(controller.gestures_since_text(0) == "1 gesture since",
		"one act since it was recorded: %s" % controller.gestures_since_text(0))
	controller.arm_edit(EditKind.ERASE)
	controller.edit_at(Vector2(0.0, 0.0))
	assert(controller.gestures_since_text(0) == "1 gesture since",
		"and an act that found nothing to do is not a gesture: %s" % controller.gestures_since_text(0))
	controller.free()


func test_the_gestures_since_a_revision_are_the_difference_of_two_numbers() -> void:
	var controller = _controller()
	controller.document.begin_gesture("drawing a new line")
	controller.document.add(_line(0.0, 0.0, 10.0, 0.0), LayerSet.NEW_HARDSCAPE)
	controller.capture_revision("the lot")
	for index in 3:
		controller.document.begin_gesture("gesture %d" % index)
		controller.document.add(_line(0.0, 1.0 + index, 5.0, 1.0 + index), LayerSet.NEW_HARDSCAPE)
	assert(controller.document.gesture_serial() == 4)
	assert(controller.gestures_since_text(0) == "3 gestures since")
	controller.capture_revision("after the changes")
	assert(controller.gestures_since_text(1) == "nothing has been done to the drawing since",
		"a revision taken at the drawing's own moment is at nothing since")
	assert(controller.gestures_since_text(0) == "3 gestures since", "and the older one still counts")
	controller.free()


func test_a_revision_recorded_before_gestures_were_counted_says_so() -> void:
	var log: DraftRevisionLog = LogScript.make()
	log.capture({"entities": {}, "order": []}, "an old history")
	var controller = _controller()
	controller.revisions = log
	assert(controller.gestures_since_text(0) == "recorded before gestures were counted",
		"not known is not the same claim as nothing: %s" % controller.gestures_since_text(0))
	assert(controller.gestures_since_text(4) == "", "and a revision that is not there has nothing to say")
	controller.free()


func test_putting_a_revision_back_is_one_named_gesture() -> void:
	var controller = _controller()
	controller.document.begin_gesture("drawing a new line")
	controller.document.add(_line(0.0, 0.0, 10.0, 0.0), LayerSet.NEW_HARDSCAPE)
	controller.capture_revision("the lot")
	controller.arm_edit(EditKind.ERASE)
	controller.edit_at(Vector2(5.0, 0.0))
	assert(controller.document.count() == 0)
	assert(controller.restore_revision(0), "the revision goes back on the drawing")
	assert(controller.document.count() == 1, "with its shape")
	assert(controller.document.undo_label() == "putting a revision back",
		"and undoing that puts the drawing that was there a moment ago back: %s"
			% controller.document.undo_label())
	controller.free()


# --- what the buttons say -------------------------------------------------------------


func test_an_undo_button_says_the_gesture_it_would_undo() -> void:
	assert(Hud._gesture_tooltip("Undo", "erasing", &"draft_undo") == "Undo erasing (Ctrl+Z)",
		Hud._gesture_tooltip("Undo", "erasing", &"draft_undo"))
	assert(Hud._gesture_tooltip("Redo", "drawing a new line", &"draft_redo")
		== "Redo drawing a new line (Ctrl+Y)")
	assert(Hud._gesture_tooltip("Undo", History.UNNAMED, &"draft_undo") == "Undo an edit (Ctrl+Z)",
		"an act nobody named still says as much as it can")


func test_a_button_with_nothing_to_do_says_so_rather_than_nothing() -> void:
	assert(Hud._gesture_tooltip("Undo", "", &"draft_undo") == "nothing to undo (Ctrl+Z)",
		Hud._gesture_tooltip("Undo", "", &"draft_undo"))
	assert(Hud._gesture_tooltip("Redo", "", &"draft_redo") == "nothing to redo (Ctrl+Y)",
		"a button that cannot say why would otherwise look broken")