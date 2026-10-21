class_name PlantModels
extends RefCounted
## The plant models the 3D view draws, one asset per shape the drawing already speaks.
##
## The catalogue describes a plant and `PlantSymbols` decides the *shape* it is drawn as on the plan:
## conifer, grass, groundcover, vine, fern, canopy, shrub, bed. The 3D view had three props for all
## nine of them, so a spruce was drawn as a conifer on paper and stood in the garden as a maple's
## crown. These are the models that close that gap.
##
## They are real `.gltf` assets, built here from primitives and written straight into
## `res://assets/plants/`, so the project carries no `.blend`, needs no download, and a person can
## regenerate one from this file instead of hunting for where it came from. A downloaded model drops
## in the same way: a `.gltf` or `.glb` on disk, a `PlanStyle.SYMBOLS` entry, and the species'
## `model_scene` pointing at it.
##
## **A model is the size its `PlanStyle.SYMBOLS` entry says it is.** `PlantPlacement` plants an
## instance at `spread / spec.size.x`, so the declared footprint is what every plant's real size is
## computed from - a model rebuilt at a different size without its declaration moving would come out
## the wrong size in the garden, and nothing on screen would look broken. `tests/test_plant_models.gd`
## holds the two together by *measuring the asset on disk*, never by trusting the table.

const OUT_DIR := "res://assets/plants"

## Colours, as plain values rather than the project's noise-textured materials: a texture cannot
## travel in a `.gltf` written from here, and a downloaded model arrives with its own materials
## anyway. What matters to the rest of the program is the path, the footprint and the symbol.
const BARK := Color(0.28, 0.19, 0.12)
const NEEDLES := Color(0.16, 0.31, 0.18)
const FOLIAGE := Color(0.26, 0.45, 0.22)
const BLADE := Color(0.52, 0.58, 0.31)
const FROND := Color(0.21, 0.40, 0.20)
const LEAF := Color(0.30, 0.50, 0.26)
## The ground of a planted bed, darker than the leaves lying on it so the bed reads as soil.
const SOIL := Color(0.35, 0.28, 0.20)
## The bloom the painted plan already washes a bed with, so the model and the painting agree about
## what a flowering clump is coloured.
const BLOOM := Color(0.89, 0.42, 0.60)

## Every model this file builds, in the order a report lists them.
const IDS := ["conifer", "grass", "groundcover", "vine", "fern", "perennial"]

## One material per colour for the whole build, so a model with fourteen blades is not fourteen
## materials in the file.
static var _materials: Dictionary = {}


## The path a model is written to.
static func path_for(id: String) -> String:
	return "%s/%s.gltf" % [OUT_DIR, id]


## Build every model and write it. Returns one row per model:
## `{id, path, ok, reason, bytes, parts, width_m, height_m, depth_m}`.
##
## Measured after the build and before the node is freed, because "how big did that come out" is the
## one number this file cannot be trusted to have got right by writing it down.
static func run() -> Array[Dictionary]:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var rows: Array[Dictionary] = []
	for id: String in IDS:
		var root: Node3D = build(id)
		_seat(root)
		var box: AABB = _bounds(root)
		var row: Dictionary = _write(root, path_for(id))
		row["id"] = id
		row["parts"] = root.get_child_count()
		row["width_m"] = snappedf(box.size.x, 0.01)
		row["depth_m"] = snappedf(box.size.z, 0.01)
		row["height_m"] = snappedf(box.end.y, 0.01)
		# The number its `PlanStyle.SYMBOLS` entry has to carry: the widest way the model stands, in
		# metres, because the plan footprint is one size and a plant is scaled to its spread by it.
		row["footprint_m"] = snappedf(maxf(box.size.x, box.size.z), 0.01)
		root.free()
		rows.append(row)
	return rows


## One model, or `null` for a name this file does not build.
static func build(id: String) -> Node3D:
	match id:
		"conifer":
			return _build_conifer()
		"grass":
			return _build_grass()
		"groundcover":
			return _build_groundcover()
		"vine":
			return _build_vine()
		"fern":
			return _build_fern()
		"perennial":
			return _build_perennial()
	return null


# --- the models --------------------------------------------------------------------------------


## A spruce: a tapered trunk under four overlapping cone tiers. 2.60 m across and 5.90 m tall, which
## is the declared footprint - the widest tier is the widest thing in the model.
static func _build_conifer() -> Node3D:
	var root: Node3D = _root("Conifer")
	_part(root, "Trunk", _cone(0.13, 1.0, 12), BARK, Vector3(0.0, 0.5, 0.0))
	# radius, height, centre height
	var tiers: Array[Vector3] = [
		Vector3(1.30, 2.20, 1.15),
		Vector3(1.05, 2.00, 2.55),
		Vector3(0.75, 1.70, 3.90),
		Vector3(0.43, 1.40, 5.20),
	]
	for i: int in range(tiers.size()):
		var tier: Vector3 = tiers[i]
		_part(root, "Tier%d" % (i + 1), _cone(tier.x, tier.y, 14), NEEDLES, Vector3(0.0, tier.z, 0.0))
	return root


## An ornamental grass: a mound with a ring of blades fanning out of it and a shorter ring inside
## them. The blades are placed from the index rather than from a random number, so the same model
## comes out of every build and a regenerated asset is not a different plant.
##
## A clump of grass is *wider than it is tall*, and this one is deliberately built so: the blades lean
## well out rather than standing up, which is what keeps a grass drawn at the height of a shrub in the
## 3D view from being a shrub. Half the blades at the circumference gives the clump a middle as well
## as an edge, because a ring of spikes reads as a starfish rather than as a tuft.
static func _build_grass() -> Node3D:
	var root: Node3D = _root("Grass")
	_part(root, "Mound", _sphere(0.34, 0.34), LEAF, Vector3(0.0, 0.07, 0.0), _squash(0.40))
	var blades: int = 22
	for i: int in range(blades):
		var theta: float = TAU * float(i) / float(blades)
		var outward := Vector3(cos(theta), 0.0, sin(theta))
		var lean: float = deg_to_rad(20.0 + 12.0 * float((i * 3) % 4) / 3.0)
		var basis := Basis(Vector3(sin(theta), 0.0, -cos(theta)), lean)
		var up: Vector3 = basis * Vector3.UP
		var reach: float = 0.10 + 0.06 * float((i * 7) % 3) / 2.0
		var height: float = 0.68
		var pos: Vector3 = outward * reach + up * (height * 0.5 - 0.02)
		_part(root, "Blade%d" % (i + 1), _cone(0.05, height, 5), BLADE, pos, basis)
	# A short inner ring, because a clump of grass is dense in the middle rather than a ring of spikes.
	for i: int in range(8):
		var theta: float = TAU * float(i) / 8.0 + 0.4
		var axis := Vector3(sin(theta), 0.0, -cos(theta))
		var basis := Basis(axis, deg_to_rad(12.0))
		var pos: Vector3 = Vector3(cos(theta), 0.0, sin(theta)) * 0.06 + Vector3(0.0, 0.28, 0.0)
		_part(root, "Inner%d" % (i + 1), _cone(0.045, 0.56, 5), BLADE, pos, basis)
	return root


## A groundcover: a mat with leaves lying on it, deliberately low - a groundcover that stands up
## would be drawn at the height of a shrub in every view that reads the model.
static func _build_groundcover() -> Node3D:
	var root: Node3D = _root("Groundcover")
	# The mat is deliberately flatter and darker than the leaves on it: a mat and its own leaves at one
	# height read as a single pancake, which is what the first version of this model was.
	_part(root, "Mat", _sphere(0.30, 0.30), FOLIAGE, Vector3(0.0, 0.05, 0.0), _squash(0.30))
	for i: int in range(14):
		var theta: float = TAU * float(i) / 14.0
		var reach: float = 0.06 + 0.18 * float((i * 3) % 4) / 3.0
		var pos := Vector3(cos(theta) * reach, 0.11, sin(theta) * reach)
		_part(root, "Leaf%d" % (i + 1), _sphere(0.13, 0.26), LEAF, pos, _squash(0.22))
	return root


## A climber: a stem with foliage up it. It stands as tall as a climber's own growth rather than as
## wide as its spread, which is the one shape in this file that is taller than it is broad.
static func _build_vine() -> Node3D:
	var root: Node3D = _root("Vine")
	_part(root, "Stem", _cone(0.03, 1.70, 8), BARK, Vector3(0.0, 0.85, 0.0))
	for i: int in range(7):
		var side: float = 1.0 if i % 2 == 0 else -1.0
		var pos := Vector3(
			side * (0.16 + 0.10 * float(i % 3) / 2.0),
			0.32 + 0.20 * float(i),
			0.12 * float((i * 5) % 3) - 0.12
		)
		_part(root, "Leaf%d" % (i + 1), _sphere(0.20, 0.40), LEAF, pos, _squash(0.55))
	return root


## A fern: a short crown with nine fronds arching out of it, each one rising along its own leaned
## axis so the clump opens upward the way a fern does.
static func _build_fern() -> Node3D:
	var root: Node3D = _root("Fern")
	_part(root, "Crown", _sphere(0.14, 0.14), BARK, Vector3(0.0, 0.05, 0.0), _squash(0.50))
	# Two rings: the fronds a fern throws out, and the shorter ones standing up inside them.
	for i: int in range(11):
		var theta: float = TAU * float(i) / 11.0
		var outward := Vector3(cos(theta), 0.0, sin(theta))
		var lean: float = deg_to_rad(46.0 + 12.0 * float((i * 2) % 3) / 2.0)
		var basis := Basis(Vector3(sin(theta), 0.0, -cos(theta)), lean)
		var up: Vector3 = basis * Vector3.UP
		var pos: Vector3 = outward * 0.05 + up * 0.31
		_part(root, "Frond%d" % (i + 1), _cone(0.05, 0.66, 6), FROND, pos, basis)
	for i: int in range(5):
		var theta: float = TAU * float(i) / 5.0 + 0.5
		var outward := Vector3(cos(theta), 0.0, sin(theta))
		var lean: float = deg_to_rad(28.0)
		var basis := Basis(Vector3(sin(theta), 0.0, -cos(theta)), lean)
		var up: Vector3 = basis * Vector3.UP
		var pos: Vector3 = outward * 0.03 + up * 0.21
		_part(root, "Inner%d" % (i + 1), _cone(0.045, 0.44, 6), FROND, pos, basis)
	return root


## A flowering perennial, which is the shape the plan has always drawn as a **planted bed**: the
## catalogue gives every perennial, annual, bulb and herb the `bed` symbol, and a bed's plan footprint
## is the *prop's own oblong* rather than a disc (`PlantSymbols.is_round`, and the 2.60 x 1.40 m the
## raised bed occupied before this).
##
## So the model is a planting of that size and shape rather than a round clump of one plant: a round
## model under an oblong symbol stands in the garden as something other than what is on the paper, and
## `PlantPlacement` sizes all sixty of those species by this one footprint.
static func _build_perennial() -> Node3D:
	var root: Node3D = _root("Perennial")
	# The bed's own ground: 2.60 m across and 1.40 m deep, flat, because a bed is flat. An ellipsoid
	# rather than a box so the bed has no corner a plant would never grow in.
	_part(
		root, "Soil", _sphere(1.30, 1.30), SOIL, Vector3(0.0, 0.12, 0.0),
		Basis.from_scale(Vector3(1.0, 0.16, 1.4 / 2.6))
	)
	# Two rows of leaves over it, planted from the index so a rebuild is the same bed.
	for i: int in range(12):
		var column: int = i % 6
		var row: int = floori(float(i) / 6.0)
		var x: float = -1.04 + 0.42 * float(column)
		var z: float = -0.34 + 0.68 * float(row)
		var lean: float = deg_to_rad(16.0 + 14.0 * float((i * 3) % 4) / 3.0)
		var way: float = 1.0 if i % 2 == 0 else -1.0
		var basis := Basis(Vector3(0.0, 0.0, 1.0), lean * way) * _squash(0.45)
		_part(root, "Leaf%d" % (i + 1), _sphere(0.20, 0.40), LEAF, Vector3(x, 0.17, z), basis)
	# Stems rising out of the leaves with a bloom on each: scattered rather than in rows, because a bed
	# of one perennial is not a grid.
	var blooms: int = 9
	for i: int in range(blooms):
		var x: float = -1.05 + 2.10 * float(i % 5) / 4.0
		var z: float = -0.40 + 0.80 * float((i * 3) % 3) / 2.0
		var height: float = 0.40 + 0.24 * float((i * 5) % 4) / 3.0
		_part(root, "Stem%d" % (i + 1), _cone(0.014, height, 5), FROND, Vector3(x, height * 0.5 + 0.12, z))
		_part(root, "Bloom%d" % (i + 1), _sphere(0.075, 0.15), BLOOM, Vector3(x, height + 0.18, z))
	return root


# --- writing it out ----------------------------------------------------------------------------


## Stand the model on the ground: a leaned blade reaches a little below the origin it was placed at,
## and a prop whose lowest point is under zero is planted that far into the lawn. Nothing in the
## program would report that - it would just look slightly wrong forever - so it is fixed here, at
## the one moment the model's own bounds are known.
static func _seat(root: Node3D) -> void:
	var box: AABB = _bounds(root)
	if absf(box.position.y) < 0.0005:
		return
	for child: Node in root.get_children():
		var part := child as Node3D
		if part != null:
			part.position.y -= box.position.y


## Write one built model as a `.gltf`. Godot's own `GLTFDocument` does the writing, which is why the
## assets need no Blender and no export step a person has to remember.
##
## The buffers go beside the file as a `.bin` - that is what glTF separate means - and both files are
## the asset: the `.bin` is not a leftover.
static func _write(root: Node3D, path: String) -> Dictionary:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var appended: int = doc.append_from_scene(root, state)
	if appended != OK:
		return {"ok": false, "reason": "the model would not append (%d)" % appended, "bytes": 0, "path": path}
	var written: int = doc.write_to_filesystem(state, path)
	if written != OK:
		return {"ok": false, "reason": "the model would not be written (%d)" % written, "bytes": 0, "path": path}
	var bytes: int = 0
	var f := FileAccess.open(path, FileAccess.READ)
	if f != null:
		bytes = f.get_length()
		f.close()
	return {"ok": true, "reason": "", "bytes": bytes, "path": path}


# --- primitives --------------------------------------------------------------------------------


static func _root(model_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = model_name
	return root


static func _part(
	parent: Node3D,
	part_name: String,
	mesh: Mesh,
	colour: Color,
	pos: Vector3,
	basis: Basis = Basis.IDENTITY
) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.material_override = _material(colour)
	part.transform = Transform3D(basis, pos)
	parent.add_child(part)
	return part


static func _material(colour: Color) -> StandardMaterial3D:
	var key: String = colour.to_html()
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.9
	_materials[key] = mat
	return mat


static func _cone(bottom_radius: float, height: float, segments: int) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	return mesh


static func _sphere(radius: float, height: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.rings = 8
	return mesh


## A leaf or a mat is a sphere flattened along the world's up.
static func _squash(factor: float) -> Basis:
	return Basis.from_scale(Vector3(1.0, factor, 1.0))


## The model's own bounding box, measured from the meshes rather than guessed.
static func _bounds(root: Node3D) -> AABB:
	var found := false
	var box := AABB()
	for child: Node in root.get_children():
		var part := child as MeshInstance3D
		if part == null or part.mesh == null:
			continue
		var local: AABB = part.mesh.get_aabb()
		for corner: int in range(8):
			var point: Vector3 = part.transform * local.get_endpoint(corner)
			if not found:
				box = AABB(point, Vector3.ZERO)
				found = true
			else:
				box = box.expand(point)
	return box