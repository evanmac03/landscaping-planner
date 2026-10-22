extends Node2D
## A live pass over the model export: the real yard, written out as a `.glb` and as a `.gltf`, and the
## one thing the two formats do not do the same.
##
## This is a development tool, not part of the game. It instances the **real main scene** and exports
## the **real yard** through the shipped exporter, so the yard, the fence, the planting, the derived
## solids and the material tables are all the ones somebody is actually looking at. A patio is drawn on
## the new-hard layer first, because the paving material is the one in this project whose pictures are
## files - so it is the one that shows what the two formats do differently.
##
## The File menu's own door (`_menu_save_model`) opens a save dialog and cannot be driven from here;
## what it does with the answer - add the extension, hand the path to the exporter, put the sentence on
## the status line - is what `tests/test_vis_yard_export.gd` checks.
##
## Run `res://scenes/model_demo.tscn`.

const MAIN := preload("res://scenes/main.tscn")
const Exporter := preload("res://scripts/vis/yard_exporter.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")

const GLB_PATH := "user://model-demo.glb"
const GLTF_PATH := "user://model-demo.gltf"

## Frames to let the yard settle before it is written: the derived builder rebuilds on a debounce, and
## the procedural textures generate on a thread. What goes out is what is standing, so both are waited
## for rather than poked at.
const SETTLE_FRAMES := 20


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	var derived: Node = main.get_node_or_null(^"Derived")
	var controller: Node = main.get_node_or_null(^"DraftController")
	if derived == null or controller == null:
		print("no derived builder or no drafting controller in the main scene")
		return

	print("--- what the exporter takes to be the design ---")
	for root: Node in Exporter.design_roots(main.get_node(^"ViewController")):
		print("  ", root.name, " (", root.get_class(), ") holding ", root.get_child_count(), " children")
	print("  and nothing else: not the player, not the cameras, not the sun")

	print("--- a patio on the new-hard layer, so the model has a textured solid in it ---")
	controller.document.add(
		Entity.make_polyline(PackedVector2Array([
			Vector2(-6.0, -4.0), Vector2(-1.0, -4.0), Vector2(-1.0, 0.0), Vector2(-6.0, 0.0),
		]), true),
		LayerSet.NEW_HARDSCAPE
	)
	var frames := 0
	while frames < SETTLE_FRAMES:
		await get_tree().process_frame
		frames += 1
	print("  the builder says: ", derived.describe())

	for path: String in [GLB_PATH, GLTF_PATH]:
		print("--- ", path.get_file(), " ---")
		var report: Dictionary = Exporter.export_scene(main, path)
		for line: String in Exporter.report_lines(report):
			print("  ", line)
		print("  written to ", ProjectSettings.globalize_path(path))
		print("  meshes read back out of the file: ", _meshes_in(path))

	print("--- the one thing the two formats do not do the same ---")
	print("  the .glb's images:   ", _images(_json_chunk(GLB_PATH)))
	print("  the .gltf's images:  ", _images(_read(GLTF_PATH)))
	print("  a .glb embeds a picture in itself (a bufferView); a .gltf writes down where the picture")
	print("  lives inside this project (a uri) and leaves it there - so a .gltf opens in another")
	print("  program with its geometry and its colours, and none of its textures.")


## The images block of a model's JSON, cut short: enough to see whether it embeds or names.
func _images(json: String) -> String:
	var at := json.find("\"images\"")
	if at < 0:
		return "(none at all)"
	var block := json.substr(at, 260)
	var where := "embedded" if block.contains("bufferView") else "named"
	return "%d entries, %s: %s" % [block.count("{\"name\""), where, block.substr(0, 170)]


## The JSON chunk of a `.glb`: a header, a JSON chunk, a binary chunk.
func _json_chunk(path: String) -> String:
	var bytes := _bytes(path)
	if bytes.size() < 20 or bytes.slice(0, 4).get_string_from_utf8() != "glTF":
		return ""
	return bytes.slice(20, 20 + int(bytes.decode_u32(12))).get_string_from_utf8()


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _bytes(path: String) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return bytes


## How many meshes the written file holds, counted by Godot's own reader rather than by the writer:
## the one thing worth saying about an export is that another program reading it finds the garden.
func _meshes_in(path: String) -> int:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(path, state) != OK:
		return -1
	var scene: Node = document.generate_scene(state)
	var count := 0
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			count += 1
		for child: Node in node.get_children():
			stack.append(child)
	scene.free()
	return count