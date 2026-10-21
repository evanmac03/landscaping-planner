extends Node2D
## A live pass over the sun and shadow study: a season of moments, what the stated height casts at
## each, the sun aimed at one of them, and a still rendered for each.
##
## This is a development tool, not part of the game. It instances the **real main scene** and drives the
## **real page** through the buttons its own captions name, so the report, the page, the HUD, the
## presentation and the renderer are all the shipped ones, and it prints every step. What is left on
## screen is the garden with the study's own summary over it.
##
## Run `res://scenes/sun_study_demo.tscn`.
##
## Two of the moments are *also* rendered, because a study's stills are the feature a client sees - but
## only two: a demonstration that needed a minute of GPU to make its point would not be run. The season
## the page is first given is printed in full, dark hours and grazing hours included, because those are
## the rows that say the most about what the page will and will not claim.

const MAIN := preload("res://scenes/main.tscn")
const SunReportScript := preload("res://scripts/vis/sun_report.gd")
const TierScript := preload("res://scripts/vis/presentation_tier.gd")

## The two moments that are rendered: the year's tallest sun and its lowest, at the same hour. This is
## the comparison a shadow study is asked for - the same garden, six months apart - and two stills are
## enough to show it.
const JUNE_NOON := 172
const DECEMBER_NOON := 355
const NOON := 12.0
## How many frames to wait for a study of stills before giving up on it. Frames rather than seconds,
## because a tool that blocks forever on a refused render is worse than one that reports it.
const WAIT_FRAMES := 2400

var _stills_written: Array[String] = []


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	var hud: Node = main.get_node_or_null(^"Hud")
	if hud == null or hud.presentation == null:
		print("no HUD, or no presentation for the HUD to study the sun from")
		return
	var presentation: Node = hud.presentation
	presentation.still_written.connect(_on_still_written)
	presentation.set_tier(TierScript.STILL)
	presentation.frame_yard()
	await _settle()
	print("the site is ", presentation.site_text())
	print("the Present menu's own line before anything: ", hud._sun_text())

	print("--- opening the page ---")
	hud.open_sun_window()
	var page: Node = hud._sun_window
	print("the page is up: ", hud.is_sun_window_open())
	print("  it opens on: ", page.hint())
	print("  and the file names its stills would take: ", page.still_names())

	print("--- a season: \"Study a December day\" ---")
	print("pressing it: ", _press(hud, "Study a December day"))
	print("  ", page.report_summary())
	for row: Dictionary in page.study_rows():
		print("  ", row["text"])
	print("  the days it covers: ", page.day_lines())
	print("  of its ", page.moment_count(), " moments ", page.renderable_moments().size(),
		" have the sun up; the page would render exactly those")

	print("--- and the study this pass will render: the year's two noons ---")
	page.clear_moments()
	_add_moment(hud, JUNE_NOON, NOON)
	_add_moment(hud, DECEMBER_NOON, NOON)
	print("  ", page.report_summary())
	for text: String in page.row_texts():
		print("  ", text)
	# One row chosen, the way a person clicks one, so the buttons that need a choice are alive.
	_choose(page, 0)
	print("  chosen: ", _words(page.selected_moment()))
	print("  and aiming is now possible: ", page.apply_enabled(),
		", rendering: ", page.render_enabled())

	print("--- aiming the sun at each of them ---")
	# The three captures are taken with the HUD put away, so that what is compared is the garden rather
	# than the panel's own status line: a text label changing is not a shadow moving.
	hud.visible = false
	var aimed: bool = _press(hud, "Aim the sun at it")
	await _settle()
	var june := _shot()
	var june_sun: Dictionary = presentation.sun_settings()
	print("pressing \"Aim the sun at it\": ", aimed, "  -> ", page.said())
	print("  the sun stands ", "%.1f°" % float(june_sun["altitude_deg"]), " up, bearing ",
		"%.1f°" % float(june_sun["azimuth_deg"]))
	print("  what ", page.height_words(), " casts at noon in June: ",
		page.study_rows()[0]["shadow_words"])
	# The control, and the reason it is here: a second capture of the very same moment. A scene that was
	# still cross-fading, or breathing, would move pixels here too - and every count below would then be
	# measuring the fade rather than the sun.
	await _settle()
	var still := _shot()
	_choose(page, 1)
	print("pressing it again: ", _press(hud, "Aim the sun at it"), "  -> ", page.said())
	await _settle()
	var december := _shot()
	var december_sun: Dictionary = presentation.sun_settings()
	hud.visible = true
	print("  the sun stands ", "%.1f°" % float(december_sun["altitude_deg"]), " up, bearing ",
		"%.1f°" % float(december_sun["azimuth_deg"]))
	print("  between the two views, ", _changed_sampled(june, december),
		" sampled pixels of the whole garden changed, against ",
		_changed_sampled(june, still), " between two captures of the *same* moment")
	print("  which is the two suns, and not the screen moving under them")

	print("--- rendering one still per moment ---")
	print("pressing \"Render the stills\": ", _press(hud, "Render the stills"))
	var waited: int = 0
	while hud._sun_render_index < page.renderable_moments().size() and waited < WAIT_FRAMES:
		await get_tree().process_frame
		waited += 1
	for path: String in _stills_written:
		print("  wrote ", path.get_file())
	print("  ", page.said(), "  (after ", waited, " frames)")
	print("  which is ", _stills_written.size(), " of the study's ", page.moment_count(), " moments")

	print("--- what the bar says now ---")
	print("  ", hud._sun_text())
	print("  and the page's own summary: ", page.report_summary())

	print("--- putting it away ---")
	print("pressing \"Close\": ", _press(hud, "Close"))
	print("the page is up: ", hud.is_sun_window_open())
	for found: Node in _every_window(main):
		var rect := Rect2i((found as Window).position, (found as Window).size)
		print("  window ", found.name, " is ", "shown" if found.visible else "put away", " at ", rect)
	_show_summary(page)
	await _settle()
	var shot := _shot()
	DirAccess.make_dir_recursive_absolute("res://preview")
	shot.save_png("res://preview/sun_study_demo.png")
	print("the screen is ", shot.get_size(), ", saved to res://preview/sun_study_demo.png")


## Add the moment the two fields describe, through the page's own button.
func _add_moment(hud: Node, day: int, hour: float) -> void:
	hud._sun_window.set_day(day)
	hud._sun_window.set_hour(hour)
	print("  adding ", day, " at ", hour, ": ", _press(hud, "Add the moment"),
		"  -> ", hud._sun_window.said())


## Choose a row of the study the way a click does, by emitting the list's own signal.
func _choose(page: Node, index: int) -> void:
	var list: ItemList = _list(page, "Moments")
	if list != null:
		list.item_selected.emit(index)


func _list(page: Node, node_name: String) -> ItemList:
	for found: Node in page.find_children(node_name, "ItemList", true, false):
		return found as ItemList
	return null


## A moment in the report's own words, so the print does not have to know what is in one.
func _words(moment: Dictionary) -> String:
	return SunReportScript.moment_words(moment)


## Two frames and a drawn frame, so a capture is of a settled screen.
func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _shot() -> Image:
	return get_viewport().get_texture().get_image()


## How many pixels changed between two captures, sampled on a grid. A whole 1600 x 900 frame read pixel
## by pixel is slow, and what is being asked is "did the garden change" rather than "by how much": a
## moved shadow is thousands of sampled pixels and a still screen is none.
func _changed_sampled(before: Image, after: Image, step: int = 4) -> int:
	var changed := 0
	for y in range(0, after.get_height(), step):
		for x in range(0, after.get_width(), step):
			if not before.get_pixel(x, y).is_equal_approx(after.get_pixel(x, y)):
				changed += 1
	return changed


## Every `Window` under a node, however deep, because the ones that matter here are built in code and
## hang off the HUD rather than sitting in the scene file.
func _every_window(under: Node) -> Array[Window]:
	var found: Array[Window] = []
	for child: Node in under.get_children():
		if child is Window:
			found.append(child as Window)
		found.append_array(_every_window(child))
	return found


## Press a button on the sun page by the caption a person reads, so the pass goes through the same
## signal the program does rather than calling the handler behind it. Every still the study writes is
## collected by `_on_still_written`, which is the only place their names come from.
func _press(hud: Node, caption: String) -> bool:
	var window: Node = hud._sun_window
	if window == null:
		return false
	for found: Node in window.find_children("*", "Button", true, false):
		var button := found as Button
		if button.text == caption:
			button.pressed.emit()
			return true
	return false


func _on_still_written(path: String) -> void:
	_stills_written.append(path)


## Lay the study's own summary over the running game, so the session's screenshot is the feature: the
## numbers are the page's, not this tool's, and the panel beside them is the real one.
func _show_summary(page: Node) -> void:
	var layer := CanvasLayer.new()
	layer.name = "SunSummary"
	layer.layer = 8
	var panel := PanelContainer.new()
	panel.position = Vector2(16.0, 16.0)
	panel.custom_minimum_size = Vector2(720.0, 0.0)
	layer.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var heading := Label.new()
	heading.text = "A season of sun, and what %s casts" % page.height_words()
	column.add_child(heading)
	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = page.report_summary() + "\n" + "\n".join(PackedStringArray(page.row_texts()))
	column.add_child(body)
	var stills := Label.new()
	stills.text = "%d stills written, named for the moments they show: %s" % [
		_stills_written.size(), ", ".join(PackedStringArray(_still_names())),
	]
	column.add_child(stills)
	add_child(layer)


func _still_names() -> Array[String]:
	var names: Array[String] = []
	for path: String in _stills_written:
		names.append(path.get_file())
	return names