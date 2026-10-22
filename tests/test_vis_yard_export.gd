extends Node
## Tests for the garden going out as a model: which nodes are the design, what a `.glb` carries that a
## `.gltf` cannot, and the door the File menu opens.
##
## Everything here builds its own little scene out of the **real** `Yard` and `DerivedBuilder` types
## rather than loading `main.tscn`: the two questions under test are which nodes are the design and
## what the writer makes of them, and neither needs the game - or a window - to answer. Nothing enters
## a tree, so no `_ready` runs and no fence is built; a `Yard` built here is an empty `Node3D` wearing
## the right script with exactly the meshes a test puts in it. That is all `design_roots` looks at, and
## it is what lets the counts below be exact.
##
## The one thing that cannot be checked this way - that the real yard writes a model a person can open
## - is checked against the running game by the audit and `tools/model_demo.gd`.

const ExporterScript := preload("res://scripts/vis/yard_exporter.gd")
const YardScript := preload("res://scripts/yard.gd")
const DerivedScript := preload("res://scripts/vis/derived_builder.gd")
const HudScript := preload("res://scripts/hud.gd")
const ControllerScript := preload("res://scripts/draft/draft_controller.gd")

## Everything a test here writes goes under this name, swept away first and last, so a test that failed
## halfway through cannot become the next one's evidence.
const PREFIX := "test-yard-export-"


# --- the little scenes these tests are about ---------------------------------------------


## One piece of geometry on a mesh of its own, drawn with `material` when one is given.
func _box(material: Material = null) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1, 1, 1)
	if material != null:
		mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	return instance


## A yard with `boxes` pieces of geometry standing in it.
func _yard(boxes: int = 1) -> Node3D:
	var yard := YardScript.new()
	yard.name = "Yard"
	for _i in boxes:
		yard.add_child(_box())
	return yard


## A scene of the shape the exporter looks for: the yard, the solids derived from the drawing, and
## something that is plainly not the design.
func _scene(boxes: int = 1, with_person: bool = false) -> Node3D:
	var main := Node3D.new()
	main.name = "Main"
	main.add_child(_yard(boxes))
	var derived := DerivedScript.new()
	derived.name = "Derived"
	main.add_child(derived)
	if with_person:
		var person := _box()
		person.name = "Player"
		main.add_child(person)
	return main


## A small picture to put on a material, made rather than shipped: these tests are about where a
## picture ends up, not about which picture it is.
func _swatch() -> Image:
	var image := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.6, 0.3))
	return image


# --- paths, and reading back what was written --------------------------------------------


func _path(tag: String, extension: String) -> String:
	return "user://%s%s.%s" % [PREFIX, tag, extension]


func _forget() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with(PREFIX):
			dir.remove(entry)
		entry = dir.get_next()
	dir.list_dir_end()


## Every file this run made with a given ending, so a test can ask for "a .bin beside it" without
## writing down what the exporter called the buffer.
func _files_ending(suffix: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open("user://")
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with(PREFIX) and entry.ends_with(suffix):
			out.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	return out


## The JSON chunk of a `.glb`, which is where what a binary model really carries is written down. A
## GLB is a header, a JSON chunk and a binary chunk; the first two are enough to read.
func _glb_json(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "the model is there")
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	assert(bytes.size() > 20, "a model with a body")
	assert(bytes.slice(0, 4).get_string_from_utf8() == "glTF", "and a glTF's own magic word")
	return bytes.slice(20, 20 + int(bytes.decode_u32(12))).get_string_from_utf8()


func _text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "the file is there")
	var words := file.get_as_text()
	file.close()
	return words


## How many meshes a written model holds, read back through the reader Godot ships. This is the
## strongest thing that can be said about an export - that another program reading it finds the garden
## - and it is said by the reader rather than by the writer, which is the point.
func _meshes_in(path: String) -> int:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(document.append_from_file(path, state) == OK, "the model reads back")
	var scene: Node = document.generate_scene(state)
	var count := 0
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			count += 1
		for child: Node in node.get_children():
			stack.append(child)
	# A scene generated off a file is a `Node` nothing owns, and the runner reports one still standing
	# as a resource in use - so it is handed back here rather than left to the collector.
	scene.free()
	return count


# --- which nodes are the design ----------------------------------------------------------


## The design is the yard and the solids derived from the drawing, and the exporter knows them by
## **type** rather than by name - which is what keeps the person walking round the garden out of the
## model, and what makes a renamed builder still count.
func test_the_design_is_the_yard_and_the_solids_and_not_the_person_in_it() -> void:
	var main := _scene(2, true)
	var roots: Array[Node] = ExporterScript.design_roots(main)
	assert(roots.size() == 2, "%d roots, not three" % roots.size())
	assert(roots[0] is YardScript, "the yard, in the order it stands in the scene")
	assert(roots[1] is DerivedScript, "and the solids derived from the drawing")
	var report: Dictionary = ExporterScript.export_roots(roots, _path("design", "glb"))
	assert(bool(report["ok"]), String(report.get("reason", "the export refused")))
	assert(int(report["meshes"]) == 2, "two meshes went out: %d" % int(report["meshes"]))
	assert((report["roots"] as Array).size() == 2, "and the report says which roots they were")
	assert(String((report["roots"] as Array)[0]) == "Yard", str(report["roots"]))
	# And both of them are really in the file. The two roots are siblings here, as they are in the game,
	# and the count above is taken off the nodes rather than off the written model - so without the
	# single root `_one_root` makes, this reads back one mesh and the derived half of the garden is
	# silently absent. See `test_the_two_halves_of_the_garden_are_one_root_in_the_file`.
	assert(_meshes_in(_path("design", "glb")) == 2, "and both came back out of the file")
	main.free()
	_forget()


## The garden is written under **one** root, because glTF's scene is a list of roots and a reader may
## instantiate the first and no more - Godot's does. A model written as the yard beside the builder
## therefore reads back as the yard alone: the paving, the deck and the beds the drawing implies would
## be in the file and in nobody's hands, which is the half of the garden a client would notice missing.
##
## Written from the shape the game really has - two siblings under a scene root named `Main` - rather
## than from a helper that gathers them, because gathering them is the thing under test.
func test_the_two_halves_of_the_garden_are_one_root_in_the_file() -> void:
	var main := _scene(2)
	var roots: Array[Node] = ExporterScript.design_roots(main)
	var path := _path("one-root", "glb")
	var report: Dictionary = ExporterScript.export_scene(main, path)
	assert(bool(report["ok"]), String(report.get("reason", "the export refused")))
	assert(int(report["meshes"]) == 2, "two meshes stand in it: %d" % int(report["meshes"]))
	assert(_meshes_in(path) == 2, "and a reader that takes the file's own scene finds both")

	# The file itself says so: one scene, holding one root node.
	var parsed: Variant = JSON.parse_string(_glb_json(path))
	assert(parsed is Dictionary, "the model's own JSON chunk")
	var scenes: Array = (parsed as Dictionary).get("scenes", [])
	assert(scenes.size() == 1, "%d scenes in the file" % scenes.size())
	assert((scenes[0] as Dictionary).get("nodes", []).size() == 1, "and one root node in it")
	# Not that it matters to a reader: the evidence above is what the roots are named in the report.
	assert((report["roots"] as Array).size() == roots.size(), "the report still names the design nodes")
	main.free()
	_forget()


## The extension is the only thing that decides the format - `.glb` and `.gltf` are the same data in two
## containers, and a second setting for it would be a setting that can disagree with the file name.
func test_the_extension_is_what_decides_the_format() -> void:
	assert(ExporterScript.format_for("a/yard.glb") == "glb")
	assert(ExporterScript.format_for("a/yard.gltf") == "gltf")
	assert(ExporterScript.format_for("a/YARD.GLB") == "glb", "a name typed in capitals is the same name")
	assert(ExporterScript.format_for("a/yard.obj") == "", "and a format this does not write is neither")
	assert(ExporterScript.format_for("a/yard") == "", "as is a name with no extension at all")


## A name that is not a model format is refused by name, because a file nothing opens is worse than a
## refusal the person can act on.
func test_a_name_that_is_not_a_model_format_is_refused() -> void:
	var main := _scene()
	var path := _path("wrong", "obj")
	var report: Dictionary = ExporterScript.export_scene(main, path)
	assert(not bool(report["ok"]), "an .obj is not a model this writes")
	var reason := String(report["reason"])
	assert(reason.contains("glb") and reason.contains("gltf"), reason)
	assert(not FileAccess.file_exists(path), "and nothing was written")
	main.free()


## A scene with no yard in it has nothing to write, and says which rather than failing.
func test_a_scene_with_no_yard_has_no_model_to_write() -> void:
	var empty := Node3D.new()
	empty.name = "Main"
	assert(ExporterScript.design_roots(empty).is_empty(), "nothing in it is the design")
	var report: Dictionary = ExporterScript.export_scene(empty, _path("nothing", "glb"))
	assert(not bool(report["ok"]))
	assert(String(report["reason"]).contains("no yard"), String(report["reason"]))
	assert(not FileAccess.file_exists(_path("nothing", "glb")), "and nothing was written")
	empty.free()


## A yard with nothing standing in it is refused too: an empty model is not an export, and one a person
## could not tell from a failure is the worst of both.
func test_a_yard_with_nothing_standing_in_it_is_refused() -> void:
	var main := Node3D.new()
	main.name = "Main"
	main.add_child(_yard(0))
	var path := _path("bare", "glb")
	var report: Dictionary = ExporterScript.export_scene(main, path)
	assert(not bool(report["ok"]))
	assert(String(report["reason"]).contains("no geometry"), String(report["reason"]))
	assert(not FileAccess.file_exists(path), "no empty model was left behind")
	main.free()


# --- what goes out -----------------------------------------------------------------------


## A binary model is one file, and the geometry in it is the geometry that was standing - which is said
## by reading the file back rather than by trusting the write.
func test_a_binary_model_is_one_file_and_carries_the_geometry() -> void:
	var main := _scene(3)
	var path := _path("binary", "glb")
	var report: Dictionary = ExporterScript.export_scene(main, path)
	assert(bool(report["ok"]), String(report.get("reason", "the export refused")))
	assert(report["format"] == "glb", String(report["format"]))
	assert(FileAccess.file_exists(path), "the file a person named is there")
	assert((report["files"] as Array).size() == 1, "and nothing else beside it: %s" % str(report["files"]))
	assert(int(report["bytes"]) > 0, "and it has something in it")
	assert(_meshes_in(path) == 3, "three meshes went out and came back")
	assert(_glb_json(path).contains("\"meshes\""), "the file says it has meshes")
	main.free()
	_forget()


## The difference between the two formats, and the one loss this writer cannot avoid. A `.glb` puts its
## pictures inside itself; a `.gltf` writes down where each one lives *inside this project* and leaves
## it there, so it opens in another program with its colours and none of its textures.
##
## Read off the two files rather than off the report, because the report is the thing being checked.
func test_a_binary_model_carries_its_pictures_and_a_text_one_only_names_them() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(_swatch())
	var main := Node3D.new()
	main.name = "Main"
	var yard := _yard(0)
	yard.add_child(_box(material))
	main.add_child(yard)

	var binary := _path("pictures", "glb")
	var report: Dictionary = ExporterScript.export_scene(main, binary)
	assert(bool(report["ok"]), String(report.get("reason", "the export refused")))
	assert(int(report["pictures"]) == 1, "one picture is standing on it: %d" % int(report["pictures"]))
	assert(int(report["undrawn"]) == 0, "and it has been drawn, so it can be written")
	assert((report["left_out"] as Array).is_empty(), "a .glb leaves nothing out: %s" % str(report["left_out"]))
	var inside := _glb_json(binary)
	assert(inside.contains("\"images\""), "the picture is inside the file")
	var images := inside.substr(inside.find("\"images\""), 400)
	assert(not images.contains("\"uri\""), "embedded rather than pointed at: " + images)

	var text_path := _path("pictures", "gltf")
	var named: Dictionary = ExporterScript.export_scene(main, text_path)
	assert(bool(named["ok"]), String(named.get("reason", "the export refused")))
	assert((named["files"] as Array).size() == 2, "a text model is two files: %s" % str(named["files"]))
	assert(_files_ending(".bin").size() == 1, "the buffer is a .bin beside it")
	assert((named["left_out"] as Array).size() == 1, "and the picture is named as a loss: %s" % str(named["left_out"]))
	assert(
		ExporterScript.describe(named).contains("named rather than carried"),
		ExporterScript.describe(named)
	)
	assert(_text(text_path).contains("\"uri\""), "which is what the file itself says")
	main.free()
	_forget()


## What the report counts, and that the size it states is the size of the files it names. A number a
## person is told is a number they act on, so it is checked against the folder rather than against the
## writer's own idea of it.
func test_the_report_names_the_files_and_the_size_is_their_size() -> void:
	var main := _scene(4)
	var path := _path("counted", "gltf")
	var report: Dictionary = ExporterScript.export_scene(main, path)
	assert(bool(report["ok"]), String(report.get("reason", "the export refused")))
	assert(int(report["meshes"]) == 4, "%d meshes for four boxes" % int(report["meshes"]))
	assert(int(report["materials"]) == 0, "and no material on any of them: %d" % int(report["materials"]))
	assert((report["roots"] as Array).size() == 2, "two roots went in")
	var folder := path.get_base_dir()
	var counted := 0
	for name: Variant in report["files"] as Array:
		var full := folder.path_join(String(name))
		assert(FileAccess.file_exists(full), "the report names a file that is really there: %s" % full)
		counted += int(FileAccess.open(full, FileAccess.READ).get_length())
	assert(int(report["bytes"]) == counted, "%d bytes, and the files come to %d" % [int(report["bytes"]), counted])
	assert(counted > 0, "and there is something in them")
	main.free()
	_forget()


## A model written over one that is already there is still a whole model. A `.gltf` keeps its buffer in
## a file beside itself, and writing the same name again leaves that buffer exactly where it was - so a
## report that named only what *appeared* on this pass would hand a person half of what they are giving
## away, and leave them wondering why the model opens empty on somebody else's machine.
func test_writing_over_a_model_still_names_every_file_it_is_made_of() -> void:
	var main := _scene(2)
	var path := _path("again", "gltf")
	var first: Dictionary = ExporterScript.export_scene(main, path)
	assert(bool(first["ok"]), String(first.get("reason", "the export refused")))
	assert((first["files"] as Array).size() == 2, "the text model and its buffer: %s" % str(first["files"]))
	var again: Dictionary = ExporterScript.export_scene(main, path)
	assert(bool(again["ok"]), String(again.get("reason", "the export refused")))
	assert(
		(again["files"] as Array).size() == 2,
		"and the second export is made of the same two: %s" % str(again["files"])
	)
	assert(String((again["files"] as Array)[0]) == path.get_file(), "the one that was asked for comes first")
	assert(int(again["bytes"]) == int(first["bytes"]), "and the size still counts both of them")
	assert(ExporterScript.describe(again).contains("in 2 files"), ExporterScript.describe(again))
	main.free()
	_forget()


## A picture is counted as one of two things and never assumed away: one that can be written, or one
## that cannot. A generated texture - this project's lawn, ground and timber are all `NoiseTexture2D`s -
## has no image until it has been drawn once, and a test cannot say when that will be, so what is
## asserted is that both kinds are *on the report* and that a drawn one is in the right bucket.
func test_a_filled_picture_slot_is_counted_whether_or_not_it_can_be_written_yet() -> void:
	var drawn := StandardMaterial3D.new()
	drawn.albedo_texture = ImageTexture.create_from_image(_swatch())
	var generated := StandardMaterial3D.new()
	var noise := NoiseTexture2D.new()
	noise.noise = FastNoiseLite.new()
	generated.albedo_texture = noise

	var main := Node3D.new()
	main.name = "Main"
	var yard := _yard(0)
	yard.add_child(_box(drawn))
	yard.add_child(_box(generated))
	main.add_child(yard)

	var report: Dictionary = ExporterScript.export_scene(main, _path("slots", "glb"))
	assert(bool(report["ok"]), String(report.get("reason", "the export refused")))
	var counted := int(report["pictures"]) + int(report["undrawn"])
	assert(counted == 2, "both filled slots are on the report: %d" % counted)
	assert(int(report["pictures"]) >= 1, "the one that has been drawn is one of them")
	main.free()
	_forget()


## An export is not an edit: the garden is read and a file is written, and the yard is left standing
## exactly as it was - nothing added, nothing taken away, no geometry moved.
func test_an_export_leaves_the_yard_standing_as_it_found_it() -> void:
	var main := _scene(2)
	var yard: Node3D = main.get_node("Yard")
	var box: MeshInstance3D = yard.get_child(0)
	var mesh: Mesh = box.mesh
	var children := yard.get_child_count()
	var report: Dictionary = ExporterScript.export_scene(main, _path("untouched", "glb"))
	assert(bool(report["ok"]), String(report.get("reason", "the export refused")))
	assert(yard.get_child_count() == children, "the same number of things standing")
	assert(box.mesh == mesh, "and the geometry is the same geometry")
	assert(is_equal_approx(box.position.length(), 0.0), "and nothing has been moved")
	main.free()
	_forget()


# --- what the report says ----------------------------------------------------------------


## The two losses a report can name, and the sentence a person reads for each.
##
## Driven with reports built by hand rather than by an export, because telling a picture that has been
## drawn from one that has not is a question about the *moment*, and a test that waited for a texture
## to generate would be a test that fails on a fast machine.
func test_a_report_names_the_losses_it_had() -> void:
	assert(ExporterScript.describe(ExporterScript._refused("no")) == "no", "a refusal is its reason")

	var named := {
		"ok": true, "reason": "", "format": "gltf",
		"roots": ["Yard", "Derived"] as Array[String],
		"files": ["yard.gltf", "yard0.bin"], "bytes": 1024,
		"meshes": 3, "materials": 2, "pictures": 4, "undrawn": 0,
		"left_out": [] as Array[String],
	}
	named["left_out"] = ExporterScript._left_out(named)
	var line: String = ExporterScript.describe(named)
	assert(line.contains("3 meshes"), line)
	assert(line.contains("2 materials"), line)
	assert(line.contains("in 2 files"), line)
	assert(line.contains("4 pictures named rather than carried"), line)

	# The same pictures, undrawn, are a loss in *either* format - and are not the same loss, so they are
	# not the same sentence.
	var waiting := named.duplicate()
	waiting["format"] = "glb"
	waiting["files"] = ["yard.glb"]
	waiting["pictures"] = 0
	waiting["undrawn"] = 4
	waiting["left_out"] = ExporterScript._left_out(waiting)
	assert((waiting["left_out"] as Array).size() == 1, str(waiting["left_out"]))
	assert(String((waiting["left_out"] as Array)[0]).contains("plain colour"), str(waiting["left_out"]))
	assert(ExporterScript.describe(waiting).contains("not drawn yet"), ExporterScript.describe(waiting))

	# And the lines a page shows: what went out, where it is, what is in it, and the one thing a model
	# never carries - said every time, because it is not a fault but a fact about gardens.
	var lines: Array[String] = ExporterScript.report_lines(named)
	assert(lines.size() == 4, "%d lines" % lines.size())
	assert(lines[0] == line, "the first line is the one-liner")
	assert(lines[1].contains("yard.gltf") and lines[1].contains("yard0.bin"), lines[1])
	assert(lines[2].contains("3 meshes"), lines[2])
	assert(lines[3].contains("no sun"), lines[3])
	assert(lines[3].contains("lights it"), lines[3])


# --- the HUD's door ----------------------------------------------------------------------


## The door the menu reaches, driven the way the dialog drives it.
##
## The HUD is put under the scene **without entering a tree**, so none of its own furniture is built
## and no window is shown. That is the only way this can be tested and it is enough: what is under test
## is where the export is pointed, not how the HUD looks.
func test_the_hud_door_writes_the_model_and_gives_a_bare_name_its_extension() -> void:
	var main := _scene()
	var hud = HudScript.new()
	main.add_child(hud)
	var stem := "user://" + PREFIX + "hud"
	hud._on_model_export_chosen(stem)
	assert(FileAccess.file_exists(stem + ".glb"), "the name a person typed, given the binary extension")
	assert(not FileAccess.file_exists(stem), "and nothing written to the nameless one")
	main.free()
	_forget()


## A name that already names a format is not given a second one, and the text format really does put
## its buffer beside itself - the two files a person has to keep together.
func test_a_name_that_already_names_a_format_is_left_alone() -> void:
	var main := _scene()
	var hud = HudScript.new()
	main.add_child(hud)
	var path := _path("named", "gltf")
	hud._on_model_export_chosen(path)
	assert(FileAccess.file_exists(path), "the name it was given")
	assert(not FileAccess.file_exists(path + ".glb"), "not .gltf.glb, which nothing would open")
	assert(_files_ending(".bin").size() == 1, "and the text model brought a buffer with it")
	main.free()
	_forget()


## The reporting goes on the drawing's status line, where every other thing this program says about
## what it has just done goes - and where `Edit > What just happened...` keeps it.
func test_the_status_line_says_what_went_out() -> void:
	var main := _scene(2)
	var hud = HudScript.new()
	main.add_child(hud)
	var controller = ControllerScript.new()
	hud._draft = controller
	hud._on_model_export_chosen("user://" + PREFIX + "status.glb")
	assert(controller.last_message.contains("2 meshes"), controller.last_message)
	assert(controller.last_message.contains(".glb"), controller.last_message)
	assert(controller.last_message.contains("the yard went out"), controller.last_message)
	main.free()
	controller.free()
	_forget()


func test_the_file_menu_offers_writing_the_yard_out() -> void:
	var entry: Dictionary = _entry(&"file.model_out")
	assert(String(entry["label"]) == "Save the yard as a 3D model...", String(entry["label"]))
	assert(StringName(entry["method"]) == &"_menu_save_model", String(entry["method"]))
	assert(StringName(entry["needs"]) == HudScript.NEEDS_NOTHING,
		"the yard stands whatever is on the plan, so this asks nothing of the drawing")
	var listed := false
	for item: Dictionary in HudScript.items_for("File"):
		if StringName(item.get("id", &"")) == &"file.model_out":
			listed = true
	assert(listed, "and it is in the File menu, with the other things that leave the program")


## The menu entry with an id, out of the bar's own plan.
func _entry(id: StringName) -> Dictionary:
	for entry: Dictionary in HudScript.menu_entries():
		if StringName(entry.get("id", &"")) == id:
			return entry
	assert(false, "no menu entry with id %s" % String(id))
	return {}


# --- finding the design in a scene that is itself nested ----------------------------------


## The game's root node is not always the top of the tree. Every tool that instances `main.tscn` -
## `tools/model_demo.gd`, `tools/audit.gd`, the rest - puts it *below* a node of its own, so a search
## that walked to the top and looked there would find the tool and no yard in it. This is that shape,
## and it is built outside a tree so nothing under it runs a `_ready`.
##
## What it catches is a refusal that says "there is no yard in this scene" about a scene that has one.
func test_the_design_is_found_under_a_scene_nested_inside_another() -> void:
	var tool := Node.new()
	tool.name = "DemoTool"
	var scene := _scene(2)
	tool.add_child(scene)
	var inside: Node = scene.get_node("Yard").get_child(0)

	var roots: Array[Node] = ExporterScript.design_roots(inside)
	assert(roots.size() == 2, "%d roots found from a node inside a nested scene" % roots.size())
	assert(roots[0] is YardScript, "the yard")
	assert(roots[1] is DerivedScript, "and the solids")
	var path := _path("nested", "glb")
	var report: Dictionary = ExporterScript.export_scene(inside, path)
	assert(bool(report["ok"]), String(report.get("reason", "the export refused")))
	assert(_meshes_in(path) == 2, "and both meshes went out")
	tool.free()
	_forget()


## A node with nothing above it and nothing of the design in it has no model, and says so rather than
## walking into the engine's own nodes looking for one.
func test_a_node_with_no_design_above_or_below_it_has_none() -> void:
	var lone := Node.new()
	lone.name = "Tool"
	var deep := Node.new()
	lone.add_child(deep)
	assert(ExporterScript.design_roots(deep).is_empty(), "nothing above it is a design either")
	lone.free()