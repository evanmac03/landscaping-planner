extends Node
## What a finger gets on a phone, measured at the real HUD: the canvas scale it is drawn at, the height and
## text size of the palette button that measured 2.3 mm before, and what *this* device would be told.
##
## A development tool rather than part of the game. It **states the device** - a dense touchscreen, through
## `PhoneHud.force_density` and `TouchInput.force`, the same doors a test uses - reading this machine's own
## answer first so the two can be compared, and then instances `main.tscn` at a phone's canvas scale and
## reads the palette button back in millimetres. Run `scenes/phone_hud_demo.tscn` and read the console:
##
##     window scale      drawn up by 1.35, canvas 1185 x 666 of a 1600 x 900 window
##     this device       touchscreen no, 144 dpi, a 29 px row comes to 5.12 mm, so a thumb is needed: no
##     as applied       384.6 dpi at 1.35 scale, so the row is 61.7 px of layout, text 26 px
##     the phone         384.6 dpi, the same row is 61.7 px = 5.50 mm, text 26 px = 1.62 mm
##     before            a row of 29 px was 2.59 mm and text 12 px about 0.7 mm
##     PHONE HUD: the palette answers at 5.5 mm on the phone's screen, sized from that screen's own density
##
## The `this device` line is the honest one: a desk monitor is not a thumb's device, and a density of 144
## is what says so. The `as applied` line is the same question asked of the device the program was *told*
## it is, and it is what the button measured back must equal - so the verdict is the program's own wiring
## rather than this file's arithmetic done twice.

const PhoneHudScript := preload("res://scripts/phone_hud.gd")
const TouchInputScript := preload("res://scripts/touch_input.gd")

## The phone this program is aimed at: 2340 x 1080 on a 6.7 inch screen. Measured on the device itself,
## which reports 450 dots to the inch; the number here is the one the arithmetic is exercised at.
const PHONE_DPI := 384.6

## The row and the text a desk was drawn with, for the comparison.
const DESK_ROW := 29.0
const DESK_FONT := 12.0

var _app: Node = null
var _hud: Node = null


func _ready() -> void:
	# What this device would be told, from its own readings - read **before** a phone is stated for the
	# program below, so the honest number survives to be compared against the demonstrated one. The rule is
	# a touchscreen and a *density*, not an operating system, so a desk can be told what a phone would be
	# told; the numbers read back below are then the program's own rather than this file's arithmetic twice.
	var here_dpi: float = PhoneHudScript.dpi()
	var touch: bool = TouchInputScript.has_a_touchscreen()
	var desk_mm: float = PhoneHudScript.millimetres(TouchInputScript.DESK_ROW_PX, 1.0, here_dpi)
	var thumb: bool = TouchInputScript.answered_by_a_thumb(
		touch, here_dpi, desk_mm, PhoneHudScript.TOUCH_MM
	)

	# State that this is a phone: a dense touchscreen, which is what every rule below is built on. The window
	# is drawn up here - the program would not, because as far as *it* is concerned this is a desk - and the
	# device is forced so that `_size_palette_for_a_finger` (which asks `on_a_finger_here`) does the sizing
	# the measurement below reads back.
	PhoneHudScript.force_density(PHONE_DPI)
	TouchInputScript.force(TouchInputScript.Answer.FINGER)
	PhoneHudScript.apply_if(get_window(), true)

	_app = load("res://scenes/main.tscn").instantiate()
	_app.name = "App"
	add_child(_app)
	for i in 3:
		await get_tree().process_frame

	_hud = _find_scripted(_app, "hud.gd")
	var button: Button = null if _hud == null else _find_button(_hud, "draft_polyline")
	if button == null:
		_put_the_device_back()
		print("PHONE HUD: no palette button in main.tscn")
		get_tree().quit(1)
		return

	var window: Window = get_window()
	var shown: Vector2 = window.get_visible_rect().size
	print("window scale      drawn up by %.2f, canvas %d x %d of a %d x %d window" % [
		window.content_scale_factor, int(shown.x), int(shown.y), int(window.size.x), int(window.size.y),
	])

	# What this device would be told (read at the very top, before a phone was stated for it): the question
	# the program asks itself, which no longer mentions an operating system.
	print("this device       touchscreen %s, %.0f dpi, a %.0f px row comes to %.2f mm, so a thumb is needed: %s" % [
		"yes" if touch else "no",
		here_dpi,
		TouchInputScript.DESK_ROW_PX,
		desk_mm,
		"yes" if thumb else "no",
	])

	var row: float = button.custom_minimum_size.y
	var text: float = float(button.get_theme_font_size("font_size"))
	var scale: float = PhoneHudScript.canvas_scale(window)
	if scale <= 0.0:
		scale = window.content_scale_factor
	# What the device the program was told it is asks for - the number the wiring above actually applied,
	# and what the button measured back should be. The button's own height is `row`, read a line ago.
	var here: float = PhoneHudScript.row_height(scale, PhoneHudScript.dpi())
	print("as applied        %.1f dpi at %.2f scale, so the row is %.1f px of layout, text %.0f px" % [
		PhoneHudScript.dpi(), scale, row, text,
	])
	# And what the phone's own density asks for, from the same arithmetic the wiring uses.
	var there: float = PhoneHudScript.row_height(scale, PHONE_DPI)
	var there_text: int = PhoneHudScript.font_size(scale, PHONE_DPI)
	var row_mm: float = PhoneHudScript.millimetres(there, scale, PHONE_DPI)
	var text_mm: float = PhoneHudScript.millimetres(
		float(there_text) * PhoneHudScript.CAP_RATIO, scale, PHONE_DPI
	)
	print("the phone         %.1f dpi, the same row is %.1f px = %.2f mm, text %d px = %.2f mm" % [
		PHONE_DPI, there, row_mm, there_text, text_mm,
	])
	print("before            a row of %.0f px was %.2f mm and text %.0f px about %.1f mm" % [
		DESK_ROW,
		PhoneHudScript.millimetres(DESK_ROW, scale, PHONE_DPI),
		DESK_FONT,
		PhoneHudScript.millimetres(DESK_FONT * PhoneHudScript.CAP_RATIO, scale, PHONE_DPI),
	])

	var scaled: bool = is_equal_approx(window.content_scale_factor, PhoneHudScript.UI_SCALE)
	var wired: bool = (
		is_equal_approx(row, here)
		and text == float(PhoneHudScript.font_size(scale, PhoneHudScript.dpi()))
	)
	var roomy: bool = row_mm >= PhoneHudScript.TOUCH_MM - 0.01
	var legible: bool = text_mm >= PhoneHudScript.TEXT_MM - 0.01
	if not scaled:
		print("PHONE HUD: the window is drawn at %.2f, not the %.2f a phone asks for" % [
			window.content_scale_factor, PhoneHudScript.UI_SCALE,
		])
	if not wired:
		print("PHONE HUD: the button is %.1f px, not the %.1f its own density asks for" % [row, here])
	if not roomy or not legible:
		print("PHONE HUD: on that phone the row is %.2f mm and the text %.2f mm" % [row_mm, text_mm])
	var ok: bool = scaled and wired and roomy and legible
	print("PHONE HUD: %s" % (
		"the palette answers at %.1f mm on the phone's screen, sized from that screen's own density" % row_mm
		if ok else "A THUMB WOULD MISS"
	))
	_put_the_device_back()
	await get_tree().process_frame
	get_tree().quit(0 if ok else 1)


## Put the device back the way it was found, so this process does not leave a forced phone behind it.
func _put_the_device_back() -> void:
	PhoneHudScript.force_density(0.0)
	TouchInputScript.force(TouchInputScript.Answer.AUTO)


## The first node under the app carrying a given script, found by the script rather than by a node path
## that a scene edit would move out from under this tool.
func _find_scripted(root: Node, file: String) -> Node:
	for node: Node in root.find_children("*", "", true, false):
		var script: Script = node.get_script()
		if script != null and String(script.resource_path).ends_with(file):
			return node
	return null


## A palette button by the action it stands for, which is the name the HUD gives it.
func _find_button(hud: Node, button_name: String) -> Button:
	return hud.find_child(button_name, true, false) as Button
