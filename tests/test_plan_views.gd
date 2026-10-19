extends Node
## Checks the two overhead views really are two projections of one dataset.
##
## What matters here is that the flat plan's coordinate system agrees with the
## orthographic 3D camera, and that a prop's plan footprint is derived from the
## prop itself rather than from a second table that could drift.

const TOLERANCE := 0.0001


func test_plan_canvas_matches_the_orthographic_framing() -> void:
	var canvas := PlanCanvas.new()
	canvas.apply_view(Vector2(2.0, -3.0), 40.0, Vector2(1600.0, 900.0))
	# The plan draws one screen pixel per (height / plan_size) metre, which is
	# exactly what the orthographic camera's size means.
	assert(is_equal_approx(canvas.pixels_per_metre, 900.0 / 40.0))
	assert(is_equal_approx(canvas.pixels_per_metre, ViewMath.pixels_per_metre(900.0, 40.0)))
	canvas.free()


func test_plan_canvas_puts_the_focus_at_the_screen_centre() -> void:
	var canvas := PlanCanvas.new()
	canvas.apply_view(Vector2(2.0, -3.0), 40.0, Vector2(1600.0, 900.0))
	assert(canvas.world_to_screen(Vector3(2.0, 0.0, -3.0)).is_equal_approx(Vector2(800.0, 450.0)))
	canvas.free()


func test_plan_canvas_round_trips_screen_and_world() -> void:
	var canvas := PlanCanvas.new()
	canvas.apply_view(Vector2.ZERO, 23.0, Vector2(1600.0, 900.0))
	var world := Vector2(7.25, -4.5)
	var screen: Vector2 = canvas.world_to_screen(Vector3(world.x, 0.0, world.y))
	assert(canvas.screen_to_world(screen).is_equal_approx(world))
	canvas.free()


func test_plan_canvas_orientation_matches_the_overhead_camera() -> void:
	var canvas := PlanCanvas.new()
	canvas.apply_view(Vector2.ZERO, 23.0, Vector2(1600.0, 900.0))
	# Screen +y is world +z (south) and screen +x is world +x (east), so world -Z
	# reads as "up" the plan exactly as it does through the 3D camera.
	assert(canvas.world_to_screen(Vector3(0.0, 0.0, -5.0)).y < \
		canvas.world_to_screen(Vector3(0.0, 0.0, 5.0)).y)
	assert(canvas.world_to_screen(Vector3(-5.0, 0.0, 0.0)).x < \
		canvas.world_to_screen(Vector3(5.0, 0.0, 0.0)).x)
	canvas.free()


func test_plan_footprint_comes_from_the_prop_scene() -> void:
	var tree: Node3D = load("res://scenes/props/tree.tscn").instantiate()
	assert(tree.scene_file_path == "res://scenes/props/tree.tscn")
	assert(is_equal_approx(PlanStyle.footprint_radius(tree), 1.85))
	tree.free()

	var shrub: Node3D = load("res://scenes/props/shrub.tscn").instantiate()
	assert(is_equal_approx(PlanStyle.footprint_radius(shrub), 0.75))
	shrub.free()

	var bed: Node3D = load("res://scenes/props/flower_bed.tscn").instantiate()
	assert(is_equal_approx(PlanStyle.footprint_radius(bed), 1.3))
	bed.free()


func test_plan_footprint_scales_with_the_instance() -> void:
	var tree: Node3D = load("res://scenes/props/tree.tscn").instantiate()
	tree.scale = Vector3(2.0, 2.0, 2.0)
	assert(is_equal_approx(PlanStyle.footprint_radius(tree), 3.7))
	tree.free()


func test_unknown_prop_still_gets_a_usable_footprint() -> void:
	# A prop added to the yard but not yet described by the style table must still
	# be drawn and still be grabbable.
	var plain := Node3D.new()
	var spec: Dictionary = PlanStyle.spec_for(plain.scene_file_path)
	assert(spec == PlanStyle.PLACEHOLDER)
	assert(PlanStyle.footprint_radius(plain) > 0.0)
	plain.free()


func test_plan_colours_are_keyed_by_the_3d_material() -> void:
	var lawn: Material = load("res://resources/materials/lawn.tres")
	assert(PlanStyle.colour_for_material(lawn) == \
		PlanStyle.COLOURS["res://resources/materials/lawn.tres"])
	# The 3D materials are noise-textured, so their albedo is white; the plan
	# palette has to come from the lookup rather than the material's own colour.
	assert(PlanStyle.colour_for_material(lawn) != lawn.albedo_color)
	assert(PlanStyle.colour_for_material(null) == PlanStyle.UNKNOWN_COLOUR)


func test_every_3d_material_has_a_plan_colour() -> void:
	# Guards against adding a material to the yard and forgetting the plan palette,
	# which would silently draw part of the design in the unknown grey.
	for path: String in PlanStyle.COLOURS.keys():
		assert(ResourceLoader.exists(path), "%s is missing" % path)
	var files: Array = []
	var dir := DirAccess.open("res://resources/materials")
	assert(dir != null)
	for file_name in dir.get_files():
		if file_name.ends_with(".tres"):
			files.append("res://resources/materials/" + file_name)
	assert(files.size() >= 12)
	for path: String in files:
		assert(PlanStyle.COLOURS.has(path), "no plan colour for %s" % path)