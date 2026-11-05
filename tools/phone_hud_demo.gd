extends Node
## What a finger gets on a phone, measured at the real HUD: the canvas scale it is drawn at, and the
## height and text size of the palette button that measured 2.3 mm before.
##
## A development tool rather than part of the game. It instances `main.tscn` with the device forced to a
## phone - before the scene is made, because the HUD reads the window's scale when the window is made
## and sizes its palette once - and then reads the button back and converts it to millimetres. Run
## `scenes/phone_hud_demo.tscn` and read the console:
##
##     window scale      drawn up by 1.35, canvas 1185 x 666 of a 1600 x 900 window
##     palette row       51.4 px of layout, 5.50 mm on a 384.6 dpi screen, text 21 px
##     before            a row of 29 px was 2.30 mm and text 12 px about 1.0 mm
##     PHONE HUD: a palette button is 5.5 mm and its text reads at 1.6 mm on the phone's screen
##
## The density is the one thing a desktop cannot lend: this machine has its own, so the millimetres
## printed here are the phone's arithmetic run with the phone's density. Whether that phone agrees is
## what the device is for.

const PhoneHudScript := preload("res://scripts/phone_hud.gd")
const PhoneFilesScript := preload("res://scripts/phone_files.gd")

## The phone this program is aimed at: 2340 x 1080 on a 6.7 inch screen.
const PHONE_DPI := 384.6

## The row and the text a desk was drawn with, for the comparison.
const DESK_ROW := 29.0
const DESK_FONT := 12.0

var _app: Node = null
var _hud: Node = null


func _ready() -> void:
	PhoneFilesScript.force(PhoneFilesScript.Device.PHONE)
	_app = load("res://scenes/main.tscn").instantiate()
	_app.name = "App"
	add_child(_app)
	for i in 3:
		await get_tree().process_frame

	_hud = _find_scripted(_app, "hud.gd")
	var button: Button = null if _hud == null else _find_button(_hud, "draft_polyline")
	if button == null:
		print("PHONE HUD: no palette button in main.tscn")
		get_tree().quit(1)
		return

	var window: Window = get_window()
	var shown: Vector2 = window.get_visible_rect().size
	print("window scale      drawn up by %.2f, canvas %d x %d of a %d x %d window" % [
		window.content_scale_factor, int(shown.x), int(shown.y), int(window.size.x), int(window.size.y),
	])

	var row: float = button.custom_minimum_size.y
	var text: float = float(button.get_theme_font_size("font_size"))
	var scale: float = PhoneHudScript.canvas_scale(window)
	if scale <= 0.0:
		scale = window.content_scale_factor
	# What this machine's own density asks for, which is what the wiring above actually applied. A desk
	# says 96 dpi, where five and a half millimetres is a fifth of the row a phone gets - so the applied
	# number here is small and correct, and it is not the number the phone will use.
	var here: float = PhoneHudScript.row_height(scale, PhoneHudScript.dpi())
	print("this machine      %.1f dpi at %.2f scale, so the row is %.1f px of layout, text %.0f px" % [
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


## A palette button by the action it stands for, which is the name the HUD gives it.
func _find_button(hud: Node, button_name: String) -> Button:
	return hud.find_child(button_name, true, false) as Button
