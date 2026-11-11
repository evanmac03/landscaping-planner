extends Node
## What this program's own interface looks like on a phone: held up in front of a person rather than
## asserted, so that "the words are legible now" is something seen rather than something read.
##
## A development tool rather than part of the game. It **states the device** - a dense touchscreen, through
## `PhoneHud.force_density` and `TouchInput.force`, the same doors a test uses - reads this machine's own
## answer first so the two can be compared, draws the canvas up, and then instances `main.tscn`, which puts
## the front door up on its own. The console prints the same sizes as arithmetic, so a number can be quoted.
##
##     run `res://tools/phone_gui_probe.tscn` and LOOK at the window
##     this device      touchscreen no, 144 dpi, a 29 px row comes to 5.12 mm, so a thumb is needed: no
##     the phone        a legible capital is TEXT_MM, which is 25 px of layout at 1.62 drawn at 384.6 dpi
##     a page's note    was 12 px, is 25 px   (grown from what the page laid it out at)
##     a page's title   was 20 px, is 42 px   (a page keeps its shape rather than collapsing)
##     a page's button  was 12 px, is 25 px, in a row 61.7 px tall
##     the menu bar     was 15 px, is 31 px
##
## **The device is deliberately left stated for the length of the run**, because the whole point of this tool
## is the window a person looks at - so it is closed by hand rather than waited for. Nothing outside this
## process is affected: a test run is its own process and its own reading.

const PhoneHudScript := preload("res://scripts/phone_hud.gd")
const TouchInputScript := preload("res://scripts/touch_input.gd")

## The phone this program is aimed at: 2340 x 1080 on a 6.7 inch screen, 450 dots to the inch to the
## platform. The number here is the one the arithmetic is exercised at, and the canvas scale the
## demonstration draws at.
##
## **What this tool states is the device, not the room.** Godot's embedded game refuses a change of the
## window's size, so the window stays the editor's own and the canvas under it is not the phone's 1444 by
## 666 - it is a little narrower, which wraps a page's sentences earlier than the phone would and so makes a
## page come out taller here than there. A page that fits this window fits the phone; a page that does not
## is not yet an answer about the phone, and the phone itself is the instrument for that. `PageLayout.measure`
## takes a viewport size as an argument for exactly that reason.
const PHONE_DPI := 384.6
const PHONE_SCALE := 1.62

var _app: Node = null
var _hud: Node = null


func _ready() -> void:
	# This machine's own answer, read **before** a phone is stated for the program below, so the honest
	# reading survives to be compared against the demonstrated one - the same order `phone_hud_demo` keeps.
	var here_dpi: float = PhoneHudScript.dpi()
	var touch: bool = TouchInputScript.has_a_touchscreen()
	var desk_mm: float = PhoneHudScript.millimetres(TouchInputScript.DESK_ROW_PX, 1.0, here_dpi)
	var thumb: bool = TouchInputScript.answered_by_a_thumb(
		touch, here_dpi, desk_mm, PhoneHudScript.TOUCH_MM
	)
	print("this device      touchscreen %s, %.0f dpi, a %.0f px row comes to %.2f mm, so a thumb is needed: %s" % [
		"yes" if touch else "no", here_dpi, TouchInputScript.DESK_ROW_PX, desk_mm, "yes" if thumb else "no",
	])
	print("the phone        a legible capital is %.1f mm, which is %d px of layout at %.2f drawn at %.1f dpi" % [
		PhoneHudScript.TEXT_MM,
		PhoneHudScript.font_size(PHONE_SCALE, PHONE_DPI),
		PHONE_SCALE,
		PHONE_DPI,
	])

	# State that this is a phone. The window is drawn up here - the program would not, because as far as *it*
	# is concerned this is a desk - and the device is forced so that the passes under it do the sizing the
	# window below shows and the lines printed here read back.
	PhoneHudScript.force_density(PHONE_DPI)
	TouchInputScript.force(TouchInputScript.Answer.FINGER)
	PhoneHudScript.apply_if(get_window(), true)

	_app = load("res://scenes/main.tscn").instantiate()
	_app.name = "App"
	add_child(_app)
	for _i: int in 4:
		await get_tree().process_frame

	_hud = _find_scripted(_app, "hud.gd")
	_report_the_front_door()
	_report_the_chrome()
	print("")
	print("PHONE GUI: the window above is what a phone is given - the words are sized with the buttons")


## The front door stands up on its own when the program starts, so it is the page a person sees first and the
## one to read the page rules off: a note is the body size grown legible, a heading stays bigger than it, and
## a button is the flat size a thumb is told, in the row it has to be hit in.
func _report_the_front_door() -> void:
	var door: Node = _find_scripted(_app, "start_window.gd")
	if door == null:
		print("the front door    not in this scene")
		return
	var note: Label = _first(door, "Label") as Label
	var heading: Label = _first(door, "Label", 1) as Label
	var button: Button = _first(door, "Button") as Button
	print("a page's note    was %s, is %s" % [
		_written(note, PhoneHudScript.DESK_TEXT), _drawn(note),
	])
	if heading != null:
		print("a page's title   is %s - a page keeps its shape rather than collapsing onto one size" % _drawn(heading))
	if button != null:
		print("a page's button  was %s, is %s, in a row %.1f px tall" % [
			PhoneHudScript.DESK_TEXT, _drawn(button), button.custom_minimum_size.y,
		])


## The chrome this HUD draws for itself: the menu bar over the whole window, and the first words on whichever
## panel is always on screen beside the palette.
func _report_the_chrome() -> void:
	if _hud == null:
		print("the chrome        no HUD in this scene")
		return
	var bar: Control = _first(_hud, "MenuBar") as Control
	if bar != null:
		print("the menu bar     is %s" % _drawn(bar))
	for menu: Window in _every_popup(_hud):
		print("a menu's items   %s are %s" % [menu.get_path(), _drawn(menu)])
	var panel: Node = _hud.find_child("Presentation", true, false)
	var caption: Label = _first(panel, "Label") as Label if panel != null else null
	if caption != null:
		print("a panel's words  are %s" % _drawn(caption))


## The size a control's words are drawn at, as the number on the control - which is what a person sees
## rather than what the arithmetic asked for.
func _drawn(control: Node) -> String:
	var sized: Control = control as Control
	if sized != null:
		return "%d px" % sized.get_theme_font_size(&"font_size")
	var window: Window = control as Window
	if window != null:
		return "%d px" % window.get_theme_font_size(&"font_size", StringName(window.get_class()))
	return "not stated"


## What a control's words would have been drawn at had the page not been fitted, for the comparison line.
func _written(control: Node, desk: int) -> String:
	var sized: Control = control as Control
	if sized == null:
		return "%d px" % desk
	# The size the page itself asked for is remembered under the key `PhoneHud` grows from, so it is read
	# from there rather than worked out a second time here.
	var remembered: Variant = sized.get_meta(PhoneHudScript.DRAWN_AT, desk)
	return "%d px" % int(remembered)


## The first node under a root of a given class, found by the class rather than by a node path a scene edit
## would move out from under this tool. `skip` passes over the ones before it.
func _first(root: Node, kind: String, skip: int = 0) -> Node:
	if root == null:
		return null
	var seen: int = 0
	for node: Node in root.find_children("*", kind, true, false):
		if seen >= skip:
			return node
		seen += 1
	return null


## Every pop-up under a root, with the path it lives at: a menu is a `Window` rather than a `Control`, so it
## is not found by the class search above, and which pop-up is which is the whole question when one of them
## comes out at the size of a desk.
func _every_popup(root: Node) -> Array[Window]:
	var found: Array[Window] = []
	if root == null:
		return found
	for node: Node in root.find_children("*", "", true, false):
		var window: Window = node as Window
		if window != null and window is Popup:
			found.append(window)
	return found


## The first node under the app carrying a given script, found by the script rather than by a node path.
func _find_scripted(root: Node, file: String) -> Node:
	if root == null:
		return null
	for node: Node in root.find_children("*", "", true, false):
		var script: Script = node.get_script()
		if script != null and String(script.resource_path).ends_with(file):
			return node
	return null