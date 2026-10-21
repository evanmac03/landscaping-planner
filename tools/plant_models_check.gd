extends Node3D
## A dev tool: every plant model this project ships, standing in a row, lit and in front of a camera.
##
## A model is the one asset nothing else can check for you - the tests measure it, and nobody can
## see a spire that is really a bush from an AABB. This puts one of each in the scene so a person can
## look, and so `run_scene` can photograph them.
##
## Run it: `res://tools/plant_models_check.tscn`.

const ModelsScript := preload("res://tools/plant_models.gd")
const PlanStyleScript := preload("res://scripts/plan_style.gd")

## One of each, biggest first, spaced by the widest of them.
const SPACING := 3.4


func _ready() -> void:
	var ids: Array = ModelsScript.IDS.duplicate()
	var count: int = ids.size()
	var span: float = SPACING * float(count - 1)

	for i: int in range(count):
		var id: String = ids[i]
		var path: String = ModelsScript.path_for(id)
		var packed: PackedScene = ResourceLoader.load(path, "PackedScene") as PackedScene
		if packed == null:
			push_warning("no model at %s" % path)
			continue
		var model: Node3D = packed.instantiate() as Node3D
		model.name = id.capitalize()
		model.position = Vector3(SPACING * float(i) - span * 0.5, 0.0, 0.0)
		add_child(model)

		var label := Label3D.new()
		label.name = "Label"
		label.text = "%s (%.2f m)" % [id, (PlanStyleScript.spec_for(path)["size"] as Vector2).x]
		label.font_size = 64
		label.pixel_size = 0.006
		label.position = Vector3(0.0, 0.05, 1.4)
		model.add_child(label)

	_light()
	_camera()


func _light() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 1.1
	sun.rotation_degrees = Vector3(-52.0, -34.0, 0.0)
	add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.76, 0.82, 0.88)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.78, 0.84)
	env.ambient_light_energy = 0.85
	var world := WorldEnvironment.new()
	world.name = "World"
	world.environment = env
	add_child(world)


func _camera() -> void:
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.fov = 55.0
	camera.position = Vector3(0.0, 4.6, 14.0)
	camera.look_at_from_position(camera.position, Vector3(0.0, 1.6, 0.0), Vector3.UP)
	camera.current = true
	add_child(camera)