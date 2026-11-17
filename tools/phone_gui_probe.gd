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
##     the phone        a legible capital is TEXT_MM, which is 29 px of layout at 1.62 drawn at 450 dpi
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
const HudProbeScript := preload("res://scripts/hud_probe.gd")

## The phone this program is aimed at: 2340 x 1080 on a 6.7 inch screen, and **450** dots to the inch - what
## the A16W reports of itself, and the number `phone_hud_demo` and `phone_touch_sweep` both state.
##
## **384.6 was an estimate of the same device, and stating it was a fault rather than a near-miss.** This file's
## own doc said 450 while its constant said 384.6, and the tool derives the floor a target must reach and the
## floor words must be legible at from the density it *forces* - so both floors came out about 15% low, and a
## reading that is too lenient is the one that misses faults rather than one that invents them. One device, one
## number: the three tools that state a phone now state the same one.
##
## **What this tool states is the device, not the room.** Godot's embedded game refuses a change of the
## window's size, so the window stays the editor's own and the canvas under it is not the phone's 1444 by
## 666 - it is a little narrower, which wraps a page's sentences earlier than the phone would and so makes a
## page come out taller here than there. A page that fits this window fits the phone; a page that does not
## is not yet an answer about the phone, and the phone itself is the instrument for that. `PageLayout.measure`
## takes a viewport size as an argument for exactly that reason.
const PHONE_DPI := 450.0
const PHONE_SCALE := 1.62

var _app: Node = null
var _hud: Node = null


## What a finger would be asked to hit on the window above, once it has been drawn up the way a phone draws it.
##
## The questions the probe asks on a real device are asked here too, so that they can be *read on a desk*: how big
## each target is, how far apart two neighbours are, whether one stands in a band the device keeps for itself, and
## whether its words are big enough for the screen. The floor for the targets is `PhoneHud`'s own reading - the
## same millimetres the program lays its rows out at - so this judges against the number the program obeys rather
## than against a second opinion about thumbs.
##
## **The room is this window's and not the phone's.** Godot's embedded game refuses a change of the window's size,
## so the numbers below are a phone's *sizes* in a window that is not a phone's shape. A page that fits here fits
## there; one that does not is not yet an answer about the phone, and the device itself remains the instrument for
## that - the probe's own `small`, `close`, `unsafe` and `tiny` lines read off `probe.log` say what the phone
## really holds.
func _report_the_targets() -> void:
	if _hud == null:
		return
	var root: Control = _hud.get_node_or_null(^"Root") as Control
	if root == null:
		return
	var scale: float = PhoneHudScript.canvas_scale(get_window())
	var density: float = PhoneHudScript.dpi()
	var least: int = roundi(PhoneHudScript.row_height(scale, density))
	# The bands a system keeps belong to a phone's own display, so there are none to read from this window: the
	# promise `DisplayServer` makes here is about a monitor, and comparing it with this window names every control
	# along a whole side for nothing. The rule that judges a control against those bands has its own tests, and it
	# is read off a real device through the probe's `unsafe` lines. That is why this tool does not call them: the
	# rule reads the *platform's* promise, and this window is a monitor.
	print("")
	print(
		(
			"--- what a finger would be asked to hit (a target should be %d px; this window has no bands to keep) ---"
			% least
		)
	)
	var found: int = 0
	for line: String in HudProbeScript.small_lines(root, "the window", least):
		print("  " + line)
		found += 1
	for line: String in HudProbeScript.close_lines(root, "the window"):
		print("  " + line)
		found += 1
	for line: String in HudProbeScript.tiny_lines(root, "the window", scale, density):
		print("  " + line)
		found += 1
	# And the one touch question a window that is the wrong shape can still answer honestly: whether any control's
	# words want more room than the box they are drawn in. A caption losing words does it at every size, which is
	# why this one is asked here rather than only on the device.
	for line: String in HudProbeScript.clipped_lines(root, "the window"):
		print("  " + line)
		found += 1
	if found == 0:
		print("  every target is big enough, clear of its neighbours, legible and showing all of its words")


func _ready() -> void:
	# This machine's own answer, read **before** a phone is stated for the program below, so the honest
	# reading survives to be compared against the demonstrated one - the same order `phone_hud_demo` keeps.
	var here_dpi: float = PhoneHudScript.dpi()
	var touch: bool = TouchInputScript.has_a_touchscreen()
	var desk_mm: float = PhoneHudScript.millimetres(TouchInputScript.DESK_ROW_PX, 1.0, here_dpi)
	var thumb: bool = TouchInputScript.answered_by_a_thumb(touch, here_dpi, desk_mm, PhoneHudScript.TOUCH_MM)
	print(
		"this device      touchscreen %s, %.0f dpi, a %.0f px row comes to %.2f mm, so a thumb is needed: %s"
		% ["yes" if touch else "no", here_dpi, TouchInputScript.DESK_ROW_PX, desk_mm, "yes" if thumb else "no"]
	)
	print(
		"the phone        a legible capital is %.1f mm, which is %d px of layout at %.2f drawn at %.1f dpi"
		% [PhoneHudScript.TEXT_MM, PhoneHudScript.font_size(PHONE_SCALE, PHONE_DPI), PHONE_SCALE, PHONE_DPI]
	)

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
	_report_the_targets()
	await _report_the_menus()
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
	print("a page's note    was %s, is %s" % [_written(note, PhoneHudScript.DESK_TEXT), _drawn(note)])
	if heading != null:
		print("a page's title   is %s - a page keeps its shape rather than collapsing onto one size" % _drawn(heading))
	if button != null:
		print(
			"a page's button  was %s, is %s, in a row %.1f px tall"
			% [PhoneHudScript.DESK_TEXT, _drawn(button), button.custom_minimum_size.y]
		)


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
	# The panel is over a third of a phone's width, so a phone is given it **put away** and the Present menu's
	# own row brings it back. This is the line that says which of the two the window above is showing, and how
	# much of the canvas the panel would take if it were up.
	var shown: Control = panel as Control
	var up: bool = shown != null and shown.is_visible_in_tree()
	var taken: Vector2 = shown.size if shown != null else Vector2.ZERO
	var state: String = "on the screen" if up else "put away"
	print("the panel        is %s, %d x %d px of the canvas" % [state, int(taken.x), int(taken.y)])


## What a page's picker menus give a thumb **once the page is up**, beside what the same kind of menu gives
## before anyone has opened the page it is on.
##
## The question this settles: the menu list above reports most of them at 16 px, which is the size a desk
## draws them at - because a page's menus are fitted when the page is *opened*, not when the page is built.
## So the two readings here are the same kind of menu before and after, and what is reported is the **row**:
## the band a thumb actually hits, which is not the font size and cannot be read off one.
func _report_the_menus() -> void:
	if _hud == null:
		return
	_hud.call(&"open_ground_window")
	for _i: int in 4:
		await get_tree().process_frame
	var opened: Window = _the_open_page()
	if opened == null:
		print("a page's menus   no page was opened, so there is nothing to read")
		return
	var menus: Array[PopupMenu] = _picker_menus(opened)
	if menus.is_empty():
		print("a page's menus   the page it opened has no pickers on it")
	else:
		print("a page's menus   the page has %d pickers; the first of them:" % menus.size())
		await _report_one_menu(menus[0], "open page    ")
	var shut: Node = _hud.find_child("SnapWindow", true, false)
	for menu: PopupMenu in _picker_menus(shut):
		await _report_one_menu(menu, "never opened ")


## The page the HUD has up: the visible `Window` among its own children, which is how a page is found by
## something that did not open it.
func _the_open_page() -> Window:
	for node: Node in _hud.get_children():
		var page: Window = node as Window
		if page != null and page.visible:
			return page
	return null


## Every picker's menu under a root: the menu an `OptionButton` opens is not a node in the tree, so it is
## asked for rather than searched for.
func _picker_menus(root: Node) -> Array[PopupMenu]:
	var found: Array[PopupMenu] = []
	if root == null:
		return found
	for node: Node in root.find_children("*", "OptionButton", true, false):
		var picker: OptionButton = node as OptionButton
		if picker != null:
			found.append(picker.get_popup())
	return found


## One menu, read as it is **drawn** rather than as it is configured: the band a thumb hits is the menu's
## own height shared among its items, less the frame the panel stylebox draws around them. The menu has to
## be up for the engine to have sized it at all, which is why this pops it and waits a frame.
##
## **Measured this way because the obvious instrument lies.** Copying a menu's font size onto a menu of this
## tool's own and reading `get_contents_minimum_size` answered 27 px for a menu drawn at 16 px and 27 px
## again for one drawn at 47: a `font_size` override does not move a fresh `PopupMenu`'s contents size, so
## that reading was the default theme's row both times. An instrument that answers the same for two
## different menus is not measuring anything.
func _report_one_menu(menu: PopupMenu, what: String) -> void:
	if menu == null:
		return
	menu.popup()
	await get_tree().process_frame
	var items: int = menu.get_item_count()
	var box: StyleBox = menu.get_theme_stylebox(&"panel")
	var frame: float = 0.0 if box == null else box.get_margin(SIDE_TOP) + box.get_margin(SIDE_BOTTOM)
	var row: float = 0.0 if items <= 0 else (float(menu.size.y) - frame) / float(items)
	var mm: float = PhoneHudScript.millimetres(row, PHONE_SCALE, PHONE_DPI)
	print(
		"a page's menus   %s  font %d px, %d items, menu %d px less a %d px frame = %.1f px a row = %.2f mm  (%s)"
		% [
			what,
			menu.get_theme_font_size(&"font_size"),
			items,
			menu.size.y,
			int(frame),
			row,
			mm,
			"a thumb's row" if mm >= PhoneHudScript.TOUCH_MM - 0.01 else "UNDER A THUMB",
		]
	)
	menu.hide()


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
