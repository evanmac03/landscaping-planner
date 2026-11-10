extends Node
## What a ten-inch tablet gets: the two answers that make a tablet a tablet, and the palette measured at the
## screen's own density rather than at a phone's.
##
## A development tool rather than part of the game. It opens a window the size of a tablet in landscape,
## states the tablet's density and that a tablet is answered with a finger - neither of which a desktop can
## lend - instances `main.tscn`, and then reads the palette back and converts it to millimetres. A tablet is
## the device that is sized for a thumb and *not* drawn up: its own scale already has the room, and drawing
## it up would cost it a third of its drawing area for nothing.
##
## Run `scenes/tablet_demo.tscn` and read the console:
##
##     window           1600 x 900, canvas 1600 x 900 of it
##     answers          a thumb is needed: yes, drawn up: no
##     palette panel    507.0 px wide, its column wants 467.0 -> FITS
##     palette row      65.0 px of layout = 5.50 mm on a 300 dpi screen
##     TABLET: sized for a thumb at the tablet's own scale, and the canvas was not drawn up
##
## The window comes back 1600 by 900 because the scene runner pins it and because the project's own stretch
## base is 1600 by 900: a tablet's window is shown at its own resolution, but the canvas inside it is that
## base, so the *width* measured here - the one every fit below is against - is the width a tablet gets.
## What a tablet changes is the two numbers above them: the density the millimetres are measured with, and
## whether the canvas is drawn up at all.

const PhoneHudScript := preload("res://scripts/phone_hud.gd")
const TouchInputScript := preload("res://scripts/touch_input.gd")

## A ten-inch Android tablet in landscape: 2560 x 1600 at 300 dots to the inch.
const TABLET_SIZE := Vector2i(2560, 1600)
const TABLET_DPI := 300.0

var _app: Node = null


func _ready() -> void:
	get_window().size = TABLET_SIZE
	await get_tree().process_frame
	# Stated, not read: a desktop cannot lend a tablet's density, and a desk's own screen is not a finger's.
	PhoneHudScript.force_density(TABLET_DPI)
	TouchInputScript.force(TouchInputScript.Answer.FINGER)

	_app = load("res://scenes/main.tscn").instantiate()
	_app.name = "App"
	add_child(_app)
	for i in 3:
		await get_tree().process_frame

	var window: Window = get_window()
	var shown: Vector2 = window.get_visible_rect().size
	print("window           %d x %d, canvas %d x %d of it" % [
		int(window.size.x), int(window.size.y), int(shown.x), int(shown.y),
	])

	var finger: bool = PhoneHudScript.on_a_finger_here()
	var zoomed: bool = PhoneHudScript.zooming_here()
	print("answers          a thumb is needed: %s, drawn up: %s" % [
		"yes" if finger else "no", "yes" if zoomed else "no",
	])

	var hud: Node = _find_scripted(_app, "hud.gd")
	var palette: Control = null if hud == null else hud.get_node_or_null("%Palette") as Control
	var column: Control = null if hud == null else hud.get_node_or_null("%PaletteColumn") as Control
	if palette == null or column == null:
		print("TABLET: no palette in main.tscn")
		get_tree().quit(1)
		return
	var wants: float = column.get_combined_minimum_size().x
	var has: float = palette.size.x
	var fits: bool = wants <= has + 0.5
	print("palette panel    %.1f px wide, its column wants %.1f -> %s" % [
		has, wants, "FITS" if fits else "TOO WIDE",
	])

	var button: Button = null if hud == null else hud.find_child("draft_polyline", true, false) as Button
	var row_mm: float = 0.0
	if button != null:
		var scale: float = PhoneHudScript.canvas_scale(window)
		row_mm = PhoneHudScript.millimetres(button.custom_minimum_size.y, scale, TABLET_DPI)
		print("palette row      %.1f px of layout = %.2f mm on a %d dpi screen" % [
			button.custom_minimum_size.y, row_mm, int(TABLET_DPI),
		])

	var sized: bool = row_mm >= PhoneHudScript.TOUCH_MM - 0.01
	var ok: bool = finger and not zoomed and fits and sized
	print("TABLET: %s" % (
		"sized for a thumb at the tablet's own scale, and the canvas was not drawn up"
		if ok else "A TABLET WOULD GET THE WRONG DEVICE"
	))
	PhoneHudScript.force_density(0.0)
	TouchInputScript.force(TouchInputScript.Answer.AUTO)
	await get_tree().process_frame
	get_tree().quit(0 if ok else 1)


## The first node under the app carrying a given script, found by the script rather than by a node path
## that a scene edit would move out from under this tool.
func _find_scripted(root: Node, file: String) -> Node:
	for node: Node in root.find_children("*", "", true, false):
		var script: Script = node.get_script()
		if script != null and String(script.resource_path).ends_with(file):
			return node
	return null
