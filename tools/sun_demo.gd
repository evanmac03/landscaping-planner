extends Node
## A sun path: the same garden, from the same camera, once an hour through a day.
##
## A development tool rather than part of the game. It instances `main.tscn` and drives the
## real presentation - the real yard, the real sun light, the real camera, the real exporter -
## so what it renders is what a client would be shown, and nothing here can disagree with the
## panel. Run `scenes/sun_demo.tscn` and it does the rest: it writes one still an hour into
## `res://preview/sun-demo/`, prints a table of what the study said, and then lays the day out
## as a labelled sheet so a screenshot of the session is the demonstration.
##
## The point of it is the thing a single shadow cannot show: a plan is read all year and a
## shadow study is read across a day, and the two questions a client asks - "will it be in
## shade by four" and "will it be in shade in June" - are answered by the same numbers.

const SunStudyScript := preload("res://scripts/vis/sun_study.gd")
const TierScript := preload("res://scripts/vis/presentation_tier.gd")

## The hours to render, on the site's own clock. Morning, midday and evening, twice.
const HOURS: Array[float] = [8.0, 10.0, 12.0, 14.0, 16.0, 18.0]
## The tier to render at. The still tier, because this is a picture somebody keeps: it buys the
## supersample, the sharper shadows and the stylised drawing that a proposal wants.
const TIER := TierScript.STILL
## One still's size, and how many of them go in a row on the sheet.
const STILL_SIZE := Vector2i(960, 540)
const COLUMNS := 3
## Where the stills land. Gitignored with the rest of `preview/`: a picture of output goes
## stale the moment the exporter changes, and then disagrees with the code in silence.
const OUT_DIR := "res://preview/sun-demo"
## How long to wait for a still before giving up on it. Frames, not seconds, because a tool
## that blocks forever on a refused render is worse than one that reports it.
const WAIT_FRAMES := 900

var _app: Node = null
var _director: Node3D = null


func _ready() -> void:
	_app = load("res://scenes/main.tscn").instantiate()
	_app.name = "App"
	add_child(_app)
	# Two frames: one for the app's own `_ready`, one for its presenter to adopt the site off
	# the drawing, which is what makes this a demonstration of the feature rather than of a
	# hard-coded latitude.
	await get_tree().process_frame
	await get_tree().process_frame
	_director = _app.get_node_or_null("Presentation") as Node3D
	if _director == null:
		print("sun_demo: main.tscn has no Presentation node")
		return
	# The tier the demo renders at, and how far the shadows reach from where the camera stands:
	# the two numbers that decide whether a picture has a shadow in it at all.
	_director.set_tier(TIER)
	await _render_day()


## How far the presentation camera stands from the middle of the garden, in metres.
func _camera_distance() -> float:
	var bounds: Rect2 = _director.yard.get_bounds()
	var centre := Vector3(
		bounds.position.x + bounds.size.x * 0.5, 0.0, bounds.position.y + bounds.size.y * 0.5
	)
	return _director.orbit.camera.global_position.distance_to(centre)


func _render_day() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var site: Dictionary = _director.current_site()
	var day: int = _director.day_of_year
	var light: Dictionary = SunStudyScript.daylight_for(site, SunStudyScript.moment(day, 12.0))
	print("site %s, day %d" % [_director.site_text(), day])
	print("sunrise %s, sunset %s, day length %.2f h" % [
		SunStudyScript.clock_text(light["sunrise_clock_hour"]),
		SunStudyScript.clock_text(light["sunset_clock_hour"]),
		light["day_length_hours"],
	])
	var cells: Array[Dictionary] = []
	for hour in HOURS:
		var moment: Dictionary = SunStudyScript.moment(day, hour)
		if not _director.apply_sun(site, moment):
			print("%s  the sun is below the horizon" % SunStudyScript.clock_text(hour))
			continue
		if cells.is_empty():
			# After the first framing, so the distance is the framed one rather than whatever
			# the camera happened to be at when the scene loaded.
			_director.frame_yard()
			await get_tree().process_frame
			print("camera stands %.1f m from the garden; shadows are drawn to %.1f m" % [
				_camera_distance(), _director.sun.directional_shadow_max_distance,
			])
		var sun: Dictionary = _director.sun_settings()
		print("%s  altitude %5.1f°  bearing %5.1f°  solar %5.2f h  declination %5.2f°" % [
			SunStudyScript.clock_text(hour),
			sun["altitude_deg"], sun["azimuth_deg"], sun["solar_hour"], sun["declination_deg"],
		])
		var still: Dictionary = await _one_still(hour)
		if still.is_empty():
			continue
		cells.append(still)
	if cells.is_empty():
		print("sun_demo: no hour produced a still")
		return
	_show_sheet(cells)


## One hour: frame the garden, render a still, and copy it out of the proposals folder.
##
## Returns the cell for the sheet, or an empty dictionary when the render was refused - a
## refusal is reported and skipped rather than left as a hole in the sheet.
func _one_still(hour: float) -> Dictionary:
	_director.frame_yard()
	var written: Array[String] = []
	var refused: Array[String] = []
	var on_written := func(path: String) -> void: written.append(path)
	var on_refused := func(reason: String) -> void: refused.append(reason)
	_director.still_written.connect(on_written)
	_director.still_failed.connect(on_refused)
	# Not awaited: `render_still` is a coroutine that reports by signal, so waiting for the
	# signal is how a caller learns it finished - and it is the only way to learn *why*.
	_director.render_still(STILL_SIZE)
	var waited: int = 0
	while written.is_empty() and refused.is_empty() and waited < WAIT_FRAMES:
		await get_tree().process_frame
		waited += 1
	_director.still_written.disconnect(on_written)
	_director.still_failed.disconnect(on_refused)
	if not refused.is_empty():
		print("%s  refused: %s" % [SunStudyScript.clock_text(hour), refused[0]])
		return {}
	if written.is_empty():
		print("%s  no still came back in %d frames" % [SunStudyScript.clock_text(hour), WAIT_FRAMES])
		return {}
	var target: String = "%s/%02d.png" % [OUT_DIR, int(hour)]
	DirAccess.copy_absolute(written[0], ProjectSettings.globalize_path(target))
	var image: Image = Image.load_from_file(target)
	if image == null:
		print("%s  the still could not be read back" % SunStudyScript.clock_text(hour))
		return {}
	var sun: Dictionary = _director.sun_settings()
	return {
		"texture": ImageTexture.create_from_image(image),
		"caption": "%s   sun %.0f° up, bearing %.0f°" % [
			SunStudyScript.clock_text(hour), sun["altitude_deg"], sun["azimuth_deg"],
		],
	}


## Lay the day out over the running game, so the session's own screenshot is the sun path.
func _show_sheet(cells: Array[Dictionary]) -> void:
	var layer := CanvasLayer.new()
	layer.name = "SunSheet"
	layer.layer = 8
	var background := ColorRect.new()
	background.color = Color(0.08, 0.08, 0.1)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(background)
	var heading := Label.new()
	heading.text = "A day in the garden — %s" % _director.site_text()
	heading.position = Vector2(16.0, 8.0)
	layer.add_child(heading)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.position = Vector2(16.0, 40.0)
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	layer.add_child(grid)
	for cell in cells:
		var column := VBoxContainer.new()
		var picture := TextureRect.new()
		picture.texture = cell["texture"]
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.custom_minimum_size = Vector2(505.0, 284.0)
		column.add_child(picture)
		var caption := Label.new()
		caption.text = cell["caption"]
		column.add_child(caption)
		grid.add_child(column)
	add_child(layer)