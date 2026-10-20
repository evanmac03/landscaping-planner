extends Node
## Tests for the client presentation: the quality budgets, the sun, the camera rig,
## the still's record, and the reversibility of the whole mode.
##
## What is deliberately *not* tested here is the rendering itself. A still is
## verified by looking at one (it is the deliverable, and its honesty is a matter of
## eyes), and everything around it - the size asked for, the filter applied, the
## record written, whether the session came back the way it was - is numbers, and
## numbers are tested.

const Tier := preload("res://scripts/vis/presentation_tier.gd")
const SunStudyScript := preload("res://scripts/vis/sun_study.gd")
const OrbitCameraScript := preload("res://scripts/vis/orbit_camera.gd")
const DirectorScript := preload("res://scripts/vis/presentation_director.gd")
const ExporterScript := preload("res://scripts/vis/still_exporter.gd")
const SidecarScript := preload("res://scripts/vis/still_sidecar.gd")

## A rig built the way the scene builds it, so the names this test relies on are the
## names the scene uses. A rig under any other names is a rig the camera cannot find.
func _rig() -> Node3D:
	var rig := Node3D.new()
	rig.name = "OrbitRig"
	rig.set_script(OrbitCameraScript)
	var arm := Node3D.new()
	arm.name = "Arm"
	var elevation := Node3D.new()
	elevation.name = "Elevation"
	var boom := Node3D.new()
	boom.name = "Boom"
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.fov = 32.0
	rig.add_child(arm)
	arm.add_child(elevation)
	elevation.add_child(boom)
	boom.add_child(camera)
	add_child(rig)
	return rig


# --- the quality budgets --------------------------------------------------------------


func test_an_unknown_tier_gets_the_working_budget() -> void:
	# Recoverable, where an empty dictionary would leave the renderer with no shadow
	# map at all and no way to say so.
	assert(Tier.look(999) == Tier.LOOKS[Tier.WORKING])


func test_every_tier_has_a_name_and_a_way_back_from_it() -> void:
	for tier in Tier.CHOICES:
		var tier_name: String = Tier.name_of(tier)
		assert(not tier_name.is_empty())
		assert(Tier.by_name(tier_name) == tier)


func test_only_the_still_supersamples() -> void:
	# The interactive tiers render at the screen's own size: supersampling them would
	# cost four times the pixels to look at a preview nobody is going to print.
	assert(int(Tier.look(Tier.STILL)["supersample"]) > 1)
	assert(int(Tier.look(Tier.PRESENTATION)["supersample"]) == 1)
	assert(int(Tier.look(Tier.WORKING)["supersample"]) == 1)


func test_a_better_tier_costs_more_and_buys_sharper_shadows() -> void:
	var working: Dictionary = Tier.look(Tier.WORKING)
	var still: Dictionary = Tier.look(Tier.STILL)
	# A smaller shadow range means more texels per metre of garden, which is the
	# whole reason to pay for the still.
	assert(float(still["shadow_max_distance"]) < float(working["shadow_max_distance"]))
	assert(not bool(working["ssao"]))
	assert(bool(still["ssao"]))


# --- the sun --------------------------------------------------------------------------


func test_the_solstice_declination_is_the_obliquity_of_the_earth() -> void:
	# Within a tenth of a degree of 23.44: the approximation is a cosine, and this is
	# the one day of the year it should be exactly right.
	assert(absf(SunStudyScript.declination(172) - 23.44) < 0.1)
	assert(absf(SunStudyScript.declination(355) + 23.44) < 0.5)


func test_a_summer_noon_is_high_and_southerly_in_the_northern_hemisphere() -> void:
	var sun: Dictionary = SunStudyScript.position(44.6, 172, 12.0)
	assert(bool(sun["is_up"]))
	# A midsummer noon at 44.6 N is about 68 degrees up - high, but never overhead.
	assert(float(sun["altitude_deg"]) > 60.0)
	assert(float(sun["altitude_deg"]) < 90.0)
	# Southerly: north is 0 and south is 180.
	assert(float(sun["azimuth_deg"]) > 160.0)
	assert(float(sun["azimuth_deg"]) < 200.0)


func test_the_same_moment_gives_the_same_sun() -> void:
	var first: Dictionary = SunStudyScript.position(51.5, 200, 15.25)
	var second: Dictionary = SunStudyScript.position(51.5, 200, 15.25)
	assert(first == second)


func test_a_midnight_sun_is_below_the_horizon_and_says_so() -> void:
	var sun: Dictionary = SunStudyScript.position(44.6, 355, 0.0)
	assert(not bool(sun["is_up"]))
	assert(float(sun["altitude_deg"]) < 0.0)
	assert(SunStudyScript.describe(44.6, 355, 0.0).contains("below the horizon"))


func test_aiming_the_sun_at_a_sun_that_is_down_leaves_the_light_alone() -> void:
	var light := DirectionalLight3D.new()
	add_child(light)
	var before: Transform3D = light.transform
	var aimed: bool = SunStudyScript.apply(light, 44.6, 355, 0.0)
	assert(not aimed)
	# Not "moved somewhere harmless": not moved. A light under the ground is a state
	# somebody then has to notice.
	assert(light.transform == before)
	light.queue_free()


func test_aiming_the_sun_puts_it_above_the_garden_on_the_sunny_side() -> void:
	var light := DirectionalLight3D.new()
	add_child(light)
	var sun: Dictionary = SunStudyScript.position(44.6, 172, 12.0)
	assert(SunStudyScript.apply(light, 44.6, 172, 12.0))
	# Above the ground, since the sun is up.
	assert(light.position.y > 0.0)
	# And on the bearing the study gives, which is southerly: +Z is south in this
	# project's model space (north is -Z).
	assert(light.position.z > 0.0)
	assert(light.position.length() > 1.0)
	light.queue_free()


# --- the camera rig -------------------------------------------------------------------


func test_framing_a_bigger_box_pulls_the_camera_further_back() -> void:
	var rig := _rig()
	rig.frame(AABB(Vector3(-4, 0, -3), Vector3(8, 3, 6)))
	var near: float = rig.distance()
	rig.frame(AABB(Vector3(-20, 0, -15), Vector3(40, 3, 30)))
	var far: float = rig.distance()
	assert(near > 0.0)
	assert(far > near)
	rig.queue_free()


func test_framing_never_puts_the_camera_inside_its_own_clamp() -> void:
	var rig := _rig()
	# A speck: the arithmetic wants to put the camera almost on top of it.
	rig.frame(AABB(Vector3(-0.01, 0, -0.01), Vector3(0.02, 0.02, 0.02)))
	assert(rig.distance() >= rig.min_distance)
	rig.frame(AABB(Vector3(-500, 0, -500), Vector3(1000, 10, 1000)))
	assert(rig.distance() <= rig.max_distance)
	rig.queue_free()


## The clamp, stated in the terms the rig talks in — degrees above the ground — and
## then checked against the one fact that matters: the camera is above the thing it
## looks at. A clamp applied to the wrong sign passes a self-consistent check either
## way, and holds the camera under the garden while claiming to hold it 5 to 85 degrees
## up; this test is the one that fails when that happens.
func test_the_pitch_clamp_holds_at_both_ends_with_the_camera_above() -> void:
	var rig := _rig()
	# The boom has to be out for "above the pivot" to mean anything: a camera that is
	# still sitting on the pivot is at the pivot's own height whatever the pitch.
	rig.set_distance(12.0)
	for drag: Vector2 in [Vector2(0.0, -100000.0), Vector2(0.0, 100000.0)]:
		rig.orbit(drag)
		var above: float = float(rig.state()["pitch_deg"])
		assert(above >= rig.min_elevation_deg - 0.001, str(above))
		assert(above <= rig.max_elevation_deg + 0.001, str(above))
		assert(
			rig.camera.global_position.y > rig.global_position.y,
			"camera at %s, pivot at %s" % [rig.camera.global_position, rig.global_position]
		)
	rig.queue_free()


func test_framing_puts_the_camera_above_the_garden_looking_down_at_it() -> void:
	var rig := _rig()
	rig.frame(AABB(Vector3(-14, 0, -10), Vector3(28, 6, 20)))
	# Above the ground, and above the pivot's own height, so the sight line runs down
	# toward the middle of what was framed rather than across it.
	assert(rig.camera.global_position.y > 1.0)
	assert(rig.camera.global_position.y > rig.global_position.y)
	# The pivot is the centre of the box, so the garden is what the frame is centred on.
	assert(rig.global_position.is_equal_approx(Vector3(0.0, 3.0, 0.0)))
	rig.queue_free()


func test_dollying_is_proportional_and_clamped() -> void:
	var rig := _rig()
	rig.set_distance(10.0)
	rig.dolly(-1.0)
	assert(rig.distance() > 10.0)
	# One notch out and one notch back in returns to where it started, which is what
	# proportional dolly means.
	rig.dolly(1.0)
	assert(absf(rig.distance() - 10.0) < 0.001)
	for notch in 40:
		rig.dolly(-1.0)
	assert(rig.distance() <= rig.max_distance)
	rig.queue_free()


func test_yaw_wraps_and_truck_moves_the_pivot_over_the_ground() -> void:
	var rig := _rig()
	rig.orbit(Vector2(100.0, 0.0))
	assert(absf(rad_to_deg(rig.arm.rotation.y)) > 0.0)
	var before: Vector3 = rig.global_position
	rig.truck(Vector2(2.0, 0.0))
	assert(rig.global_position != before)
	# Working the ground plane: a pan never lifts the pivot or drops it.
	assert(is_equal_approx(rig.global_position.y, before.y))
	rig.queue_free()


# --- the still's size and record ------------------------------------------------------


func test_a_still_is_rendered_at_the_supersample_size() -> void:
	assert(ExporterScript.render_size_for(Vector2i(1920, 1080)) == Vector2i(3840, 2160))
	assert(ExporterScript.render_size_for(Vector2i(4, 3)) == Vector2i(8, 6))


func test_flattening_removes_transparency_and_leaves_the_paper() -> void:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	image.set_pixel(0, 0, Color(1, 0, 0, 1))
	var flat: Image = ExporterScript.flatten_over(image, Color(0.9, 0.9, 0.9))
	assert(flat.get_format() == Image.FORMAT_RGB8)
	# The untouched corner is paper, not black - which is the bug this exists to stop,
	# because a viewer that shows a transparent PNG as black shows a proposal as a
	# black rectangle.
	var paper: Color = flat.get_pixel(3, 3)
	# Within one step of eight bits: 0.9 is not representable in an 8-bit channel, so a
	# test that demanded the exact colour would be testing the colour space rather than
	# the composite.
	assert(absf(paper.r - 0.9) < 1.0 / 255.0, str(paper))
	assert(absf(paper.g - 0.9) < 1.0 / 255.0)
	assert(absf(paper.b - 0.9) < 1.0 / 255.0)
	# And opaque, which is the whole point of the pass.
	assert(paper.a == 1.0)
	# The opaque source pixel survives the composite untouched.
	assert(flat.get_pixel(0, 0).is_equal_approx(Color(1, 0, 0)))


func test_a_flat_image_is_recognised_as_a_failed_render() -> void:
	# The failure this guards is not a crash: the viewport came back the right size,
	# the record was written, the file was saved, and the picture is a grey rectangle.
	# A named guard, because "it did not error" was mistaken for "it worked" once.
	var cleared := Image.create(64, 36, false, Image.FORMAT_RGBA8)
	cleared.fill(Color(0.298, 0.298, 0.298, 1.0))
	assert(ExporterScript.looks_blank(cleared), "a uniform image is a blank render")
	# A *transparent* image is blank too: the 2D layer renders arrive that way, and an
	# all-transparent still is nothing drawn.
	var clear_alpha := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	clear_alpha.fill(Color(0, 0, 0, 0))
	assert(ExporterScript.looks_blank(clear_alpha))
	# And the flattened form of it, which is the shape that actually reaches the check
	# on the 2D path.
	var opaque := Image.create(16, 16, false, Image.FORMAT_RGB8)
	opaque.fill(Color(0.945, 0.937, 0.906))
	assert(ExporterScript.looks_blank(opaque))


func test_one_drawn_pixel_is_not_a_blank_render() -> void:
	# The guard must be right about *small* features as well as large ones, which is
	# why it reads the whole image instead of sampling a grid. A layer render that is
	# mostly empty is legitimate - a single wash patch on an otherwise untouched layer
	# is a result, and refusing it would be this function's own false positive.
	var image := Image.create(512, 288, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.298, 0.298, 0.298, 1.0))
	# At (117, 205): neither of those is a multiple of the step a grid of twelve
	# samples per axis would have used, so a sampled guard misses this pixel and
	# reports a picture as blank.
	image.set_pixel(117, 205, Color(0.42, 0.55, 0.28, 1.0))
	assert(not ExporterScript.looks_blank(image), "one drawn pixel is not a blank render")
	# A one-step difference counts too: it is a drawn feature, not flat colour.
	var subtle := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	subtle.fill(Color(0.5, 0.5, 0.5, 1.0))
	subtle.set_pixel(3, 61, Color(0.5, 0.5, 0.5 + 1.0 / 255.0, 1.0))
	assert(not ExporterScript.looks_blank(subtle))


func test_a_format_that_is_not_eight_bit_still_gets_an_answer() -> void:
	# Half-float channels cannot be compared byte by byte, so that path falls back to
	# sampling rather than answering "no" to everything.
	var flat := Image.create(32, 32, false, Image.FORMAT_RGBAH)
	flat.fill(Color(0.2, 0.4, 0.6, 1.0))
	assert(ExporterScript.looks_blank(flat))
	var drawn := Image.create(32, 32, false, Image.FORMAT_RGBAH)
	drawn.fill(Color(0.2, 0.4, 0.6, 1.0))
	drawn.set_pixel(0, 0, Color(1, 0, 0, 1.0))
	assert(not ExporterScript.looks_blank(drawn))


func test_a_still_name_carries_the_day_it_was_taken() -> void:
	var name: String = ExporterScript.timestamp_name("presentation")
	assert(name.begins_with("presentation-"))
	# Eight digits of date and six of time, so a folder of stills sorts into the order
	# the pictures were made by file name alone.
	var parts: PackedStringArray = name.split("-")
	assert(parts.size() == 3, name)
	assert(parts[1].length() == 8, parts[1])
	assert(parts[1].is_valid_int())
	assert(parts[2].length() == 6, parts[2])
	assert(parts[2].is_valid_int())


func test_a_record_carries_everything_it_promises() -> void:
	var record: Dictionary = SidecarScript.record(
		"3D presentation", Vector2i(3840, 2160), 2, "Still (proposal)",
		SunStudyScript.position(44.6, 172, 16.0), {"eye": Vector3.ZERO}, 100.0, 17
	)
	for key in SidecarScript.KEYS:
		assert(record.has(key), key)
	assert(record["output_px"] == [3840, 2160])
	assert(record["supersample"] == 2)
	assert(record["document"]["entities"] == 17)
	# The version that drew the picture: a renderer change is the one thing that
	# silently changes a picture.
	assert(not String(record["godot"]).is_empty())


func test_a_record_round_trips_through_a_file() -> void:
	var record: Dictionary = SidecarScript.record(
		"3D presentation", Vector2i(1920, 1080), 2, "Still (proposal)",
		SunStudyScript.position(44.6, 172, 16.0), {"eye": Vector3(1, 2, 3)}, 100.0, 4
	)
	var png_path := "user://proposals/test-round-trip.png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://proposals"))
	var written: String = SidecarScript.write(png_path, record)
	assert(written.ends_with(".json"))
	var read_back: Dictionary = SidecarScript.read(png_path)
	assert(read_back.get("tier", "") == "Still (proposal)")
	assert(read_back.get("supersample", 0) == 2)
	# A record that is not there is reported as absent rather than as empty-ish.
	assert(SidecarScript.read("user://proposals/no-such-still.png").is_empty())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(written))


# --- the whole mode is reversible -----------------------------------------------------


func test_presentation_restores_everything_it_changed() -> void:
	var scene := Node3D.new()
	add_child(scene)
	var light := DirectionalLight3D.new()
	light.name = "Sun"
	light.directional_shadow_max_distance = 77.0
	light.shadow_blur = 0.25
	scene.add_child(light)
	var environment := WorldEnvironment.new()
	environment.name = "WorldEnvironment"
	environment.environment = Environment.new()
	environment.environment.ssao_enabled = false
	environment.environment.ssao_intensity = 3.0
	scene.add_child(environment)
	var director := Node3D.new()
	director.name = "Presentation"
	director.set_script(DirectorScript)
	scene.add_child(director)
	director.sun = light
	director.world_environment = environment
	director.orbit = _rig()

	# What was current before: the presentation must give this camera back.
	var flight := Camera3D.new()
	flight.name = "FlightCamera"
	scene.add_child(flight)
	flight.current = true

	assert(director.begin(Tier.STILL))
	assert(director.is_active())
	# The still budget is in force.
	assert(is_equal_approx(light.directional_shadow_max_distance, 30.0))
	assert(environment.environment.ssao_enabled)

	director.end()
	assert(not director.is_active())
	# Every property back, to the value it had rather than to a sensible default.
	assert(is_equal_approx(light.directional_shadow_max_distance, 77.0))
	assert(is_equal_approx(light.shadow_blur, 0.25))
	assert(not environment.environment.ssao_enabled)
	assert(is_equal_approx(environment.environment.ssao_intensity, 3.0))
	assert(get_viewport().get_camera_3d() == flight)
	scene.queue_free()


func test_changing_the_tier_twice_still_restores_the_original() -> void:
	# The bug this catches: recording the value again on the second change, so the
	# session is restored to the *first* presentation's budget instead of to what the
	# designer had.
	var scene := Node3D.new()
	add_child(scene)
	var light := DirectionalLight3D.new()
	light.directional_shadow_max_distance = 88.0
	scene.add_child(light)
	var director := Node3D.new()
	director.set_script(DirectorScript)
	scene.add_child(director)
	director.sun = light
	director.orbit = _rig()

	director.begin(Tier.PRESENTATION)
	director.set_tier(Tier.STILL)
	director.set_tier(Tier.WORKING)
	director.end()
	assert(is_equal_approx(light.directional_shadow_max_distance, 88.0))
	scene.queue_free()


func test_ending_a_presentation_that_never_started_is_harmless() -> void:
	var director := Node3D.new()
	director.set_script(DirectorScript)
	add_child(director)
	director.end()
	assert(not director.is_active())
	director.queue_free()


func test_a_presentation_with_no_camera_is_refused_and_not_entered() -> void:
	# Half-entering is the failure mode worth a test: the mode would be on with no way
	# to look at anything, and the working tools hidden behind it.
	var director := Node3D.new()
	director.set_script(DirectorScript)
	add_child(director)
	assert(not director.begin(Tier.PRESENTATION))
	assert(not director.is_active())
	director.queue_free()


func test_the_sun_settings_the_panel_reads_are_the_ones_that_get_applied() -> void:
	var director := Node3D.new()
	director.set_script(DirectorScript)
	add_child(director)
	var light := DirectionalLight3D.new()
	add_child(light)
	director.sun = light
	director.latitude = 51.5
	director.day_of_year = 100
	director.hour = 9.0
	assert(director.apply_sun(51.5, 100, 9.0))
	assert(director.sun_settings() == SunStudyScript.position(51.5, 100, 9.0))
	director.queue_free()