extends Control

## A still of the addon's own deciduous plant, generated in 2D and in 3D, side by side.
##
## A dev tool, not part of the program: it answers "what does this addon actually make?" with a picture.
##
## **The plant is the addon's, not this file's.** Both halves load the author's built-in `deciduous_2D`
## and `deciduous_3D` presets - his L-systems, his angles, his colours - rather than an axiom invented
## here, which would only be a fact about this file. The first version of this demo used the nodes'
## defaults (axiom "X", step 5) and showed a seedling; the presets are what a person means by a tree.
##
## **`load_preset` only assigns fields.** The geometry is built in `_ready`, from the axiom and rules the
## node held *then*, so a preset has to be followed by a rebuild or the plant is redrawn from the old
## system at the new step. Each node is rebuilt through its own path: `_ready()` again for the generator,
## then `current_step` at its maximum, then `_draw()` for the 3D mesh. The author calls `_ready()` and
## `_draw()` by hand himself (his `_process` does it for wind), so this is his convention, not a trick.
##
## Two additions of mine, both named because they are not the addon's: the leaf texture - it ships
## `Assets/leaf.png` and every built-in preset leaves the field null, so a leaf is a bare quad without
## this - and the camera, framed from the plant's own measured bounding box rather than from a guess.
##
## The still is written by the program, so it can be run from a shell with `GODOT_MCP_RUNTIME=0` and
## needs no editor bridge - which matters, because a headless run of `execute_script` binds this
## project's runtime port and takes it from a real game session.

const Plant2DScript := preload("res://addons/PlantGenerator/2D/plant2D.gd")
const Plant3DScript := preload("res://addons/PlantGenerator/3D/plant3D.gd")

const PRESET_2D := "deciduous_2D"
const PRESET_3D := "deciduous_3D"
const LEAF := "res://addons/PlantGenerator/Assets/leaf.png"

const PANE := Vector2i(800, 900)
const PAPER := Color(0.16, 0.18, 0.2)
const SETTLE_SECONDS := 0.6

var _plant_2d: Node2D
var _plant_3d: MeshInstance3D


func _ready() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_child(_the_2d_pane())
	row.add_child(_the_3d_pane())

	# A plant builds over frames. Reading its mesh the instant it is added is what made the first
	# version frame a 40-unit plant from two units away.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	_frame_the_3d_plant()
	await get_tree().create_timer(0.2).timeout

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	var shot: Image = get_viewport().get_texture().get_image()
	var where: String = ProjectSettings.globalize_path("res://build/plants_2d_and_3d.png")
	var saved: int = shot.save_png(where)
	print("PLANT wrote %s (%dx%d): %s" % [
		where, shot.get_width(), shot.get_height(), "ok" if saved == OK else "SAVE FAILED %d" % saved
	])
	get_tree().quit()


## The 2D half: the author's deciduous system, rebuilt at its full step.
##
## No scaling is applied. His preset states a branch length of 20 units for a plant 14 steps deep, and
## the previous version's x6 was compensating for a *default* plant being small - so the honest thing is
## to draw his geometry at its own size and look at what comes out.
func _the_2d_pane() -> Control:
	var pane := SubViewportContainer.new()
	pane.stretch = true
	pane.custom_minimum_size = Vector2(PANE)
	var view := SubViewport.new()
	view.size = PANE
	view.transparent_bg = false
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	pane.add_child(view)

	var paper := ColorRect.new()
	paper.color = PAPER
	paper.size = Vector2(PANE)
	view.add_child(paper)

	var plant: Node2D = Plant2DScript.new()
	view.add_child(plant)
	plant.load_preset(PRESET_2D)
	plant._ready()
	plant.current_step = plant.max_steps
	plant.leaf_texture = load(LEAF)
	plant.position = Vector2(float(PANE.x) * 0.5, float(PANE.y) - 20.0)
	# **Scaled down, and stated as an addition of mine.** His 2D preset is a plant 14 steps deep with a
	# branch length of 20 units, which does not fit this pane at its own scale. The 2D half has no
	# bounding box to measure, unlike the 3D half, so this number came from the still twice: x1.0 filled
	# the pane with a canopy whose trunk was below the bottom edge, and x0.3 left a shrub in the corner.
	# Half of his own scale sits between the two readings, which is how a number with no owner is set.
	plant.scale = Vector2(0.55, 0.55)
	_plant_2d = plant
	print("PLANT 2D: preset '%s', axiom '%s', step %d of %d, branch length %s" % [
		PRESET_2D, plant.axiom, plant.current_step, plant.max_steps, plant.branch_length
	])
	return pane


## The 3D half. `own_world_3d` keeps this pane's world to itself and the light lives inside it, so the
## pane is a self-contained studio rather than one borrowing whatever the rest of the scene provides.
func _the_3d_pane() -> Control:
	var pane := SubViewportContainer.new()
	pane.stretch = true
	pane.custom_minimum_size = Vector2(PANE)
	var view := SubViewport.new()
	view.size = PANE
	view.own_world_3d = true
	view.transparent_bg = false
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	pane.add_child(view)

	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = PAPER
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.79, 0.85)
	environment.ambient_light_energy = 1.0
	world.environment = environment
	view.add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, -38.0, 0.0)
	sun.light_energy = 1.4
	view.add_child(sun)

	var plant: MeshInstance3D = Plant3DScript.new()
	view.add_child(plant)
	plant.load_preset(PRESET_3D)
	plant._ready()
	plant.current_step = plant.max_steps
	plant.leaf_texture = load(LEAF)
	plant._draw()
	_plant_3d = plant
	print("PLANT 3D: preset '%s', axiom '%s', step %d of %d, branch length %s" % [
		PRESET_3D, plant.axiom, plant.current_step, plant.max_steps, plant.branch_length
	])
	return pane


## Stand a camera where it frames the plant that actually exists, and say what it measured.
func _frame_the_3d_plant() -> void:
	if _plant_3d == null:
		return
	var box: AABB = _plant_3d.get_aabb()
	print("PLANT 3D after %s s: mesh %s, bounding box %s" % [SETTLE_SECONDS, _plant_3d.mesh, box])
	if box.size.y <= 0.0:
		print("PLANT 3D: the plant has built no geometry, so there is nothing to frame")
		return
	# **Aimed at the plant's own centre, not at the world origin.** A tree built around a trunk that
	# spreads 142 units wide has its middle nowhere near x=0 - the first version put the camera at the
	# origin and cropped the crown off the top of the pane. The distance comes from the widest dimension
	# and the camera looks at the box's centre, so the framing follows the plant and not a guess.
	var camera := Camera3D.new()
	camera.fov = 45.0
	var middle: Vector3 = box.get_center()
	var reach: float = maxf(maxf(box.size.x, box.size.y), box.size.z)
	if reach <= 0.0:
		reach = 1.0
	camera.position = middle + Vector3(0.0, 0.0, reach * 1.45)
	var view: SubViewport = _plant_3d.get_parent() as SubViewport
	if view != null:
		view.add_child(camera)
		camera.look_at(middle, Vector3.UP)
		camera.current = true
	print("PLANT 3D: camera at %s looking at the centre %s, reach %s" % [camera.position, middle, reach])
