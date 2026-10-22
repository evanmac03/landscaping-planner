extends Node
## Tests for the drawing going out as a DXF: the controller's door, the HUD's, and the fact that an
## export leaves the drawing exactly as it found it.
##
## The controller is built with its parts and no scene tree, as the DXF *import's* tests are, so what
## is under test here is the join between a drawing and the writer. The writer's own arithmetic - the
## reflection, the units, the bulges, the arc handedness - has its own file (`test_dxf_writer.gd`).

const Ctrl := preload("res://scripts/draft/draft_controller.gd")
const Tool := preload("res://scripts/draft/draft_tool.gd")
const Document := preload("res://scripts/draft/draft_document.gd")
const SnapScript := preload("res://scripts/draft/snap_engine.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const DxfScript := preload("res://scripts/draft/dxf_file.gd")
const UnitsScript := preload("res://scripts/draft/units.gd")
const HudScript := preload("res://scripts/hud.gd")


func _controller():
	var controller = Ctrl.new()
	controller.document = Document.new()
	controller.snap = SnapScript.new()
	controller.tool = Tool.new()
	return controller


## A drawing with a paved edge and a bed on it.
func _drawing(controller) -> void:
	controller.document.add(Entity.make_line(Vector2(0, 0), Vector2(10, 0)), LayerSet.NEW_HARDSCAPE)
	controller.document.add(Entity.make_circle(Vector2(5, 5), 3.0), LayerSet.NEW_BED)


## A path of its own per test, so one test's file cannot be another's evidence.
func _path(tag: String) -> String:
	return "user://test-dxf-export-%s.dxf" % tag


## Taking a drawing's controller down again. A controller built outside the tree is a `Node` nothing
## owns, and the runner reports one still standing as a resource in use, which fails the verdict - so
## every test here hands its own back.
func _done(controller, hud = null) -> void:
	if hud != null:
		hud.free()
	if controller != null:
		controller.free()


# --- the controller's door ---------------------------------------------------------------


## What goes out is a file the reader can read: the same geometry, in metres, on the way back in.
func test_a_drawing_is_written_and_reads_back() -> void:
	var controller = _controller()
	_drawing(controller)
	var path := _path("round")
	var written: Dictionary = controller.export_dxf(path)
	assert(bool(written["ok"]), String(written.get("reason", "the export refused")))
	var back := DxfScript.of_file(path)
	assert(bool(back["ok"]), String(back["reason"]))
	assert(back["units"] == "metres")
	var shapes: Array = back["shapes"]
	assert(shapes.size() == 2, "%d shapes came back" % shapes.size())
	var line: Dictionary = shapes[0]
	assert(line["kind"] == "LINE")
	var points: PackedVector2Array = line["points"]
	assert(points[1].is_equal_approx(Vector2(10, 0)), "ten metres of paving: %s" % str(points[1]))
	# Read back in the ordinary way it is a tracing aid, which is what an import of one's own export
	# is: something to draw over rather than a second copy of the design.
	assert(line["layer"] == LayerSet.UNDERLAY, String(line["layer"]))
	assert(float((shapes[1] as Dictionary)["radius"]) == 3.0, "and the bed is still three metres across")
	_done(controller)


## An export is not an edit. Nothing is added, nothing is taken away, and there is no undo step to
## take back - which is the difference between sending the drawing out and importing a file in.
func test_an_export_leaves_the_drawing_as_it_found_it() -> void:
	var controller = _controller()
	_drawing(controller)
	var before: Array[DraftEntity] = controller.document.entities()
	var count: int = controller.document.count()
	controller.export_dxf(_path("untouched"))
	assert(controller.document.count() == count, "the same number of shapes")
	for at in before.size():
		var was: DraftEntity = before[at]
		var now: DraftEntity = controller.document.entities()[at]
		assert(now.kind == was.kind, "shape %d is still a %s" % [at, was.kind_name()])
		assert(now.params == was.params, "shape %d did not move" % at)
		assert(now.layer == was.layer, "shape %d did not change layer" % at)
	_done(controller)


## The drawing's own units are the file's: a drawing whose dimensions read in feet goes out in feet,
## or the file would contradict the sheet plotted from it.
func test_the_file_is_written_in_the_drawings_own_units() -> void:
	var controller = _controller()
	_drawing(controller)
	controller.document.units.system = UnitsScript.System.IMPERIAL
	var path := _path("imperial")
	controller.export_dxf(path)
	var back := DxfScript.of_file(path)
	assert(bool(back["ok"]), String(back["reason"]))
	assert(back["units"] == "feet", String(back["units"]))
	# And it is ten metres on the way back, because the file said what its numbers meant.
	var points: PackedVector2Array = (back["shapes"] as Array)[0]["points"]
	assert(points[1].is_equal_approx(Vector2(10, 0)), str(points[1]))
	_done(controller)


## A drawing with nothing on it that plots is refused rather than written: an empty file is not an
## export, and one that a person could not tell from a failure is worse than no file.
func test_a_drawing_with_nothing_to_export_is_refused() -> void:
	var controller = _controller()
	var path := _path("empty")
	var written: Dictionary = controller.export_dxf(path)
	assert(not bool(written["ok"]))
	assert(String(written["reason"]).contains("nothing"), String(written["reason"]))
	assert(not FileAccess.file_exists(path), "and no empty file was left behind")
	_done(controller)


func test_the_status_line_says_what_went_out() -> void:
	var controller = _controller()
	_drawing(controller)
	controller.export_dxf(_path("status"))
	assert(controller.last_message.contains("exported"), controller.last_message)
	assert(controller.last_message.contains("metres"), controller.last_message)
	assert(controller.last_message.contains("2 records"), controller.last_message)
	_done(controller)


## What could not be written is named in the status line rather than left for a person to notice by
## counting the shapes in somebody else's program.
func test_what_was_left_out_is_named() -> void:
	var controller = _controller()
	_drawing(controller)
	controller.document.add(
		Entity.make_dimension(Vector2(0, 0), Vector2(5, 0)), LayerSet.DIMENSION
	)
	controller.export_dxf(_path("left-out"))
	assert(controller.last_message.contains("left out"), controller.last_message)
	assert(controller.last_message.contains("dimension"), controller.last_message)
	_done(controller)


# --- the HUD's door ----------------------------------------------------------------------


func test_the_file_menu_offers_writing_the_drawing_out() -> void:
	var entry: Dictionary = _entry(&"file.dxf_out")
	assert(String(entry["label"]) == "Save the drawing as a DXF...", String(entry["label"]))
	assert(StringName(entry["method"]) == &"_menu_save_dxf", String(entry["method"]))
	# And it is in the File menu, with the other things that go to or come from somebody else.
	var listed := false
	for item: Dictionary in HudScript.items_for("File"):
		if StringName(item.get("id", &"")) == &"file.dxf_out":
			listed = true
	assert(listed, "the menu bar offers it")


## The menu entry with an id, out of the bar's own plan.
func _entry(id: StringName) -> Dictionary:
	for entry: Dictionary in HudScript.menu_entries():
		if StringName(entry.get("id", &"")) == id:
			return entry
	assert(false, "no menu entry with id %s" % String(id))
	return {}


## The dialog's filter is not a promise: a name typed without an extension is a file nothing on the
## machine will open, and the person who typed it has no way to tell that from one that worked.
func test_the_hud_door_gives_the_file_the_extension_it_needs() -> void:
	var controller = _controller()
	_drawing(controller)
	var hud = HudScript.new()
	hud._draft = controller
	var stem := "user://test-dxf-export-hud"
	hud._on_dxf_export_chosen(stem)
	assert(FileAccess.file_exists(stem + ".dxf"), "the name a person typed, given the extension")
	assert(not FileAccess.file_exists(stem), "and nothing written to the nameless one")
	# A HUD built outside the tree has to be taken down again, with its controller, or the runner
	# reports one of them as still held.
	_done(controller, hud)


func test_a_name_that_already_has_the_extension_is_not_given_two() -> void:
	var controller = _controller()
	_drawing(controller)
	var hud = HudScript.new()
	hud._draft = controller
	var path := "user://test-dxf-export-named.dxf"
	hud._on_dxf_export_chosen(path)
	assert(FileAccess.file_exists(path))
	assert(not FileAccess.file_exists(path + ".dxf"), "not .dxf.dxf")
	_done(controller, hud)