extends Node3D
## A dev tool: every model pulled from an outside pack, laid out in rows to be looked at.
##
## A downloaded model is the one asset nothing in this project can vouch for: the tests measure it,
## and an AABB cannot tell a plant from a scatter card. This puts one of each on the ground, at the
## scale planting would give a 1.5 m plant, over a 1 m tile, so a person can see what a garden would
## get - and so `run_scene` can photograph it.
##
## Run it: `res://tools/downloads_check.tscn`.

const PlanStyleScript := preload("res://scripts/plan_style.gd")

## The pack being looked at. Point it at any folder holding `.glb` files, or folders per model.
const DIR := "res://assets/plants/kenney"

const COLUMNS := 6
const COL_SPACING := 2.6
const ROW_SPACING := 3.4

## The spread a model is shown against - the footprint planting would scale it to.
const SHOWN_SPREAD := 1.5


func _ready() -> void:
	var entries: Array = _entries()
	var rows: int = floori(float(entries.size() + COLUMNS - 1) / float(COLUMNS))
	for i: int in range(entries.size()):
		var col: int = i % COLUMNS
		var row: int = floori(float(i) / float(COLUMNS))
		var x: float = COL_SPACING * float(col) - COL_SPACING * float(COLUMNS - 1) * 0.5
		var z: float = ROW_SPACING * float(row) - ROW_SPACING * float(rows - 1) * 0.5
		_slot(entries[i], Vector3(x, 0.0, z))

	_ground(rows)
	_light()
	_camera()


## Every model in the pack folder: a `<id>.glb` beside this file, or a folder holding `<id>_1k.gltf`.
## Two layouts, because that is how the packs ship: Poly Haven puts a model and its textures in a
## folder per asset, Kenney puts one self-contained .glb next to its siblings.
func _entries() -> Array:
	var out: Array = []
	var root: DirAccess = DirAccess.open(DIR)
	if root == null:
		push_warning("no pack folder at %s" % DIR)
		return out
	for file: String in root.get_files():
		if file.ends_with(".glb"):
			out.append({"id": file.get_basename(), "path": "%s/%s" % [DIR, file]})
	for id: String in root.get_directories():
		var path: String = "%s/%s/%s_1k.gltf" % [DIR, id, id]
		if ResourceLoader.exists(path):
			out.append({"id": id, "path": path})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["id"] as String) < (b["id"] as String))
	return out


## The bounding box of every mesh under a node, in the node's own space, and its triangle count.
func measure(path: String) -> Array:
	var packed: PackedScene = ResourceLoader.load(path, "PackedScene") as PackedScene
	if packed == null:
		return [null, 0]
	var node: Node3D = packed.instantiate() as Node3D
	var acc: Array = [null, 0]
	_bounds(node, Transform3D(), acc)
	node.free()
	return acc


func _bounds(node: Node3D, xf: Transform3D, acc: Array) -> void:
	xf = xf * node.transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		var box: AABB = xf * mesh.get_aabb()
		acc[0] = box if acc[0] == null else (acc[0] as AABB).merge(box)
		acc[1] += int(float(mesh.get_faces().size()) / 3.0)
	for child in node.get_children():
		if child is Node3D:
			_bounds(child, xf, acc)


func _slot(entry: Dictionary, at: Vector3) -> void:
	var path: String = entry["path"]
	var packed: PackedScene = ResourceLoader.load(path, "PackedScene") as PackedScene
	if packed == null:
		push_warning("no scene at %s" % path)
		return
	var model: Node3D = packed.instantiate() as Node3D
	model.name = (entry["id"] as String).capitalize()
	model.position = at
	var measured: Array = measure(path)
	var box: AABB = measured[0]
	# Planting scales a model so its footprint becomes the plant's spread. Do the same, so what is on
	# screen is the size a garden would get. The footprint is the model's own, measured: the number
	# that will go in the style table is this one, not one typed in by hand.
	var footprint: float = 0.0
	if box != null:
		footprint = maxf(box.size.x, box.size.z)
	var factor: float = SHOWN_SPREAD / maxf(footprint, 0.001)
	model.scale = Vector3.ONE * factor
	add_child(model)

	# The label belongs to the scene, not to the model: on the model it would be scaled with it, and
	# the first version of this tool printed 30 labels on top of each other.
	#
	# It says the id and nothing else. The measurements are printed below and read there: a line of
	# them is wider than the column spacing, so labels that carried the numbers smeared into one
	# another across the row and named nothing.
	var label := Label3D.new()
	label.name = "Label%s" % (entry["id"] as String).capitalize()
	label.text = entry["id"]
	label.font_size = 48
	label.pixel_size = 0.0035
	label.position = at + Vector3(0.0, 0.55, -1.15)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	print("%s  |  %s" % [entry["id"], _describe(box, measured[1])])


## One line of measurements: the numbers the style table needs, and the triangle count that says
## whether a garden of them can be drawn.
func _describe(box: AABB, tris: int) -> String:
	if box == null:
		return "no meshes"
	return "w %.2f d %.2f h %.2f base %.3f   %d tris" % [
		box.size.x, box.size.z, box.size.y, box.position.y, tris]


## A 1 m tile under every slot, so a model's size can be read off the ground.
func _ground(rows: int) -> void:
	var plane := MeshInstance3D.new()
	plane.name = "Ground"
	var slab := BoxMesh.new()
	slab.size = Vector3(COL_SPACING * float(COLUMNS) + 1.0, 0.02, ROW_SPACING * float(rows) + 1.0)
	plane.mesh = slab
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.34, 0.39, 0.33)
	plane.material_override = mat
	add_child(plane)

	for i: int in range(COLUMNS):
		for j: int in range(rows):
			var tile := MeshInstance3D.new()
			tile.name = "Tile%d_%d" % [i, j]
			var square := BoxMesh.new()
			square.size = Vector3(1.0, 0.03, 1.0)
			tile.mesh = square
			tile.position = Vector3(
				COL_SPACING * float(i) - COL_SPACING * float(COLUMNS - 1) * 0.5,
				0.01,
				ROW_SPACING * float(j) - ROW_SPACING * float(rows - 1) * 0.5)
			var tile_mat := StandardMaterial3D.new()
			tile_mat.albedo_color = Color(0.62, 0.66, 0.58)
			tile.material_override = tile_mat
			add_child(tile)


func _light() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 1.15
	sun.rotation_degrees = Vector3(-48.0, -38.0, 0.0)
	add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.76, 0.82, 0.88)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.78, 0.84)
	env.ambient_light_energy = 0.9
	var world := WorldEnvironment.new()
	world.name = "World"
	world.environment = env
	add_child(world)


func _camera() -> void:
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.fov = 50.0
	camera.position = Vector3(0.0, 11.0, 15.5)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.0, 0.0), Vector3.UP)
	camera.current = true
	add_child(camera)