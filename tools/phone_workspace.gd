extends Node
## The phone's own screen, stood on this desk: **the A16W's glass, at its own density and its own shape, with the
## whole program running in it and the glass's own furniture drawn round the edges** - the four corners the display
## takes away, the band the camera is cut into, and the band the system keeps along the foot.
##
## **What this is beside `touch_hud_workspace`, because both exist and neither replaces the other.** That one stands
## the phone's *furniture* up by hand in the 2D workspace so it can be pushed about with a mouse: it builds the bar,
## the dock and the strip out of the scene's own nodes, presses nothing, and lays them in whatever room the editor
## window happens to have. This one runs the **program** - the real HUD, the real furniture, the real pages, the
## real probe block - inside a window whose own room is the phone's. A change to the phone's arrangement can then be
## judged by looking at it and using it, rather than by reading a block off a device.
##
## **The window itself is the phone, and that is the whole of the design.** Every figure the program's chrome is
## worked out from is asked of the window it is in: a row's height is a millimetre floor turned into pixels by the
## density and **divided by the window's own canvas scale**, and the room is the window's visible rectangle. A
## window of the glass's own size, drawn up by the project's own content scale (`PhoneHud.apply_if`, the door the
## program itself hands a device's window to), answers 1.62 - which is the phone's answer - and 1444 by 666, which is
## the room the device reports. So the phone is *stated* through the two doors a test uses (`force_density` and
## `force_display`, both answered by `PhoneHud.MEASURED_SCREENS`), and the window is asked for the glass's size.
##
## **Why the program is put in the window rather than in a view of its own.** The obvious alternative - the program
## inside a `SubViewport` of the phone's size, shown on this desk at a fraction - was built and measured, and it
## makes the program's own instruments lie: `InView` and `Topmost` compare a control against the **root** viewport's
## rectangle, which is the rule they are written to, and in that nesting the root is the desk - so every control in
## a perfectly placed phone is named as standing off a 1600 by 900 screen it is not on. A screen whose own report
## cannot be trusted is worth nothing, which is the reason this tool is a window and not a picture.
##
## **A desk too small to hold the glass is said out loud rather than worked around.** The A16W lying is 2340 by 1080
## and this scene asks the window for exactly that; a desk that cannot hold it keeps the window it has, and the room
## then is this desk's rather than the phone's - a phone drawn at a fraction lays out at that fraction, so shrinking
## it to fit would be a picture of a phone nobody has. What is on the screen is stated either way, so a person can
## see which of the two they are looking at. **Running this from the editor's own Game panel does exactly that**:
## the panel is smaller than a phone, so run the scene on its own for the phone's own room.
##
## **It draws the glass and decides nothing.** Every figure round the program is asked of `PhoneHud` - the glass and
## its usable rectangle, the corner it rounds, the two bands - and every one of them is asked for *this* room, so
## the 118 px corner the display states is drawn as the 73 px the program's own plates are rounded by. Nothing here
## presses a key or moves a page: the program is the program, and this is a desk to stand it on.
##
##     res://tools/phone_workspace.tscn                  the phone as this desk's window is held - lying down
##     ... -- --standing                                the same phone held upright
##     ... -- --lying                                   the default, said out loud

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const PhoneHudScript := preload("res://scripts/phone_hud.gd")
const TouchInputScript := preload("res://scripts/touch_input.gd")

## The density the panel of the phone this view is about reports, which is half of what makes a row a thumb's height.
const PHONE_DPI := 450.0

## The verbs this tool has. A value here never begins with `--`, so every `--` word is a verb.
const VERBS: PackedStringArray = ["--standing", "--lying"]

## The shape silence means.
##
## **Lying, and this is the one place this file departs from its sibling's own default.** `phone_screen` stands
## upright unless it is told otherwise, because that is the way up every reading in this project was taken at until
## the lying ones were written down. This tool is named for the device rather than for the layout, and the device
## this project is aimed at was measured **lying** - the pass that drives it reports `user_rotation=1` with
## auto-rotate off - which is also the shape its camera band, its foot band and its rounded corner were measured in.
## A view whose whole point is "look like my phone" should open with the phone as it is held.
const DEFAULT_SHAPE := "lying"

## How long the program is given to boot before this scene reads the screen and says what it found. The same four
## seconds its sibling waits, and for the same reason: a reading taken before the chrome has settled is a reading of
## the front door in pieces.
const BOOT_SECONDS := 4.0

## **What is drawn where the glass is not.** A display physically takes its corners away, so a person looking at
## this phone must see the corner cut rather than the program's own painting.
const OUTSIDE := Color(0.02, 0.02, 0.025, 1.0)

## The band the camera is cut into, and the band the system keeps along the foot: a wash rather than a cut, because
## what a person needs to see there is *where the device's furniture is*, not what is under it.
const CAMERA_WASH := Color(1.0, 0.78, 0.36, 0.22)
const FOOT_WASH := Color(0.45, 0.8, 1.0, 0.2)

var _shape: String = DEFAULT_SHAPE
var _glass: Vector2i = Vector2i.ZERO
var _usable: Rect2i = Rect2i()
var _app: Node = null
## The room the program came out with, read off its own viewport once it has settled - which is the program's own
## arithmetic and is only known after the window has been given its size.
var _room: Vector2i = Vector2i.ZERO
## The wash colours and the corner cuts are built once, after the room is known, so that everything drawn round the
## program is in the room's own pixels.
var _glass_layer: CanvasLayer = null
var _caption: Label = null


func _ready() -> void:
	var asked := PackedStringArray(OS.get_cmdline_user_args())
	var complaint: String = unknown_verb(asked)
	if not complaint.is_empty():
		print("PHONE WORKSPACE %s" % complaint)
		get_tree().quit(1)
		return
	_shape = shape_from(asked)
	# **The glass and its furniture are asked of the one table and not stated here.** A shape this project has not
	# measured hands back a glass of nothing, and that is said rather than drawn: a phone nobody has measured
	# standing in front of a person as if it had been is the fault this whole family of tables exists to stop.
	_glass = PhoneHudScript.measured_glass(_shape)
	_usable = PhoneHudScript.measured_usable(_shape)
	if _glass == Vector2i.ZERO:
		print("PHONE WORKSPACE: %s is not a shape this project has measured, so there is no phone to stand" % _shape)
		get_tree().quit(1)
		return
	_state_the_device()
	_ask_for_the_glasss_window()
	_app = MainScene.instantiate()
	_app.name = "App"
	add_child(_app)
	# Let the program lay itself out and settle: this is a reading, and a reading taken mid-settle is a reading of
	# nothing. Two frames past the wait, because the chrome is placed on the frame after its own contents are.
	await get_tree().create_timer(BOOT_SECONDS).timeout
	await RenderingServer.frame_post_draw
	_room = Vector2i(get_viewport().get_visible_rect().size)
	_draw_the_glass()
	_say_what_is_standing()


## State the device this view is about, through the doors a test uses - and **the glass and its safe area together**,
## because either half alone is a lie: a screen with no furniture leaves every band answering zero, and furniture
## with no screen takes its share of whatever monitor is at hand.
func _state_the_device() -> void:
	PhoneHudScript.force_density(PHONE_DPI)
	PhoneHudScript.force_display(_glass, _usable)
	TouchInputScript.force(TouchInputScript.Answer.FINGER)


## Ask the window Godot opened for the glass's own size, and say where the desk cannot give it.
##
## The window is the phone, so its size *is* the room: asked and answered, the program lays out at the device's own
## room; refused, it lays out at this desk's and the two are named rather than confused. The margin left for the
## window's own frame and the desk's taskbar is a guess a person can see the sense of; a window that ends up clipped
## is worse than one that ends up small, because a clipped phone loses the part of its bar a person is looking at.
func _ask_for_the_glasss_window() -> void:
	var window: Window = get_window()
	var desk: Vector2i = DisplayServer.screen_get_size(window.current_screen)
	var holdable: Vector2i = desk - Vector2i(96, 128)
	if _glass.x <= holdable.x and _glass.y <= holdable.y:
		window.size = _glass
		return
	print(
		"PHONE WORKSPACE: this desk's screen is %d by %d and cannot hold the %d by %d phone at its own size, so the window is left as it is - the room below is this desk's and not the phone's"
		% [desk.x, desk.y, _glass.x, _glass.y]
	)


## The four corners the display takes away, and the two bands it keeps - each asked of the module that owns it, for
## **this** room.
##
## The display's own 118 px corner is 73 px of a lying room and 129 of a standing one, and the camera's 100 px of
## glass is 62 px of the room it leaves - so every figure here is `PhoneHud`'s answer for the room the program
## actually came out with, rather than a second conversion that could round the other way. The corners are drawn on
## a `CanvasLayer` above the HUD's own, because the HUD's chrome is on a layer and a layer draws above everything
## outside one whatever order the nodes were added in: a corner drawn under a menu bar is not a corner.
func _draw_the_glass() -> void:
	_glass_layer = CanvasLayer.new()
	_glass_layer.name = "TheGlass"
	_glass_layer.layer = 100
	add_child(_glass_layer)

	# Each corner as the square less the quarter of a circle: the region a person sees when they look at the corner
	# of a display that rounds it away. **The four regions are `PhoneHud`'s own** - the same call the 2D workspace's
	# frame draws with - so the corner cut out of the glass here and the corner the bar's plate is rounded with are
	# one figure rather than two. A display that rounds nothing hands back no region at all, and none is drawn.
	var which: int = 0
	for cut: PackedVector2Array in PhoneHudScript.corners_cut_out(_room, _glass):
		var removed := Polygon2D.new()
		removed.name = "CutCorner%d" % which
		removed.polygon = cut
		removed.color = OUTSIDE
		_glass_layer.add_child(removed)
		which += 1

	# **The camera is one band along one edge, and it turns with the device**: lying, the A16W keeps the room's first
	# 62 px to its left; standing, the top 62 px. Four candidates are built and the three with no extent are nothing
	# at all, because which edge it is on is the device's answer rather than something to work out here.
	var band: Vector4i = PhoneHudScript.cutout_here(_room)
	for side: Dictionary in [
		{ "size": Vector2i(band.x, _room.y), "at": Vector2i(0, 0) },
		{ "size": Vector2i(_room.x, band.y), "at": Vector2i(0, 0) },
		{ "size": Vector2i(band.z, _room.y), "at": Vector2i(_room.x - band.z, 0) },
		{ "size": Vector2i(_room.x, band.w), "at": Vector2i(0, _room.y - band.w) },
	]:
		var band_size: Vector2i = side["size"]
		if band_size.x > 0 and band_size.y > 0:
			_glass_layer.add_child(_a_band(side["at"], band_size, CAMERA_WASH))

	var foot: int = PhoneHudScript.kept_foot(_room)
	if foot > 0:
		_glass_layer.add_child(_a_band(Vector2i(0, _room.y - foot), Vector2i(_room.x, foot), FOOT_WASH))

	# The figures, written in the foot band - **the one strip of this screen the program itself keeps clear** - so
	# that the caption covers nothing a person is meant to press, and shows by standing there where that strip is.
	_caption = Label.new()
	_caption.name = "Figures"
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_caption.add_theme_font_size_override(&"font_size", maxi(mini(int(float(foot) * 0.7), 24), 9))
	_caption.add_theme_color_override(&"font_color", Color(0.92, 0.95, 1.0, 0.95))
	_caption.position = Vector2(6.0, maxf(float(_room.y - foot), 0.0))
	_caption.size = Vector2(maxf(float(_room.x) - 12.0, 1.0), float(foot))
	_glass_layer.add_child(_caption)


## One band of the glass as a wash a person can see the edge of.
func _a_band(at: Vector2i, size: Vector2i, wash: Color) -> ColorRect:
	var plate := ColorRect.new()
	plate.color = wash
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.position = Vector2(at)
	plate.size = Vector2(size)
	return plate


## **The reading, in the program's own words and in this view's.** The block is the HUD's - the same block a device
## publishes, including the room it came out with beside the glass it was told about - so what a person reads here
## can be held against what the phone itself printed; and the lines below are the figures this view itself chose,
## each asked of the module that owns it.
##
## **The window's own size is printed beside the glass's, and nothing is worked out from it.** Those two being equal
## is exactly what makes the room the phone's, and a person can see that at a glance; a second copy of the project's
## stretch arithmetic here could disagree with the program it claims to be checking.
func _say_what_is_standing() -> void:
	var hud: Node = _find_scripted(_app, "hud.gd")
	if hud == null:
		print("PHONE WORKSPACE: main.tscn holds no HUD, so there is no block to say about this screen")
	else:
		hud.call(&"_say_the_screen")
	var scale: float = PhoneHudScript.canvas_scale(get_window())
	var band: Vector4i = PhoneHudScript.cutout_here(_room)
	if _caption != null:
		_caption.text = (
			"%s - the glass %d x %d, the room %d x %d at %.2f; camera %d of the room, foot %d, corner %d"
			% [
				_shape,
				_glass.x,
				_glass.y,
				_room.x,
				_room.y,
				scale,
				band.x,
				PhoneHudScript.kept_foot(_room),
				PhoneHudScript.rounded_corner(_room),
			]
		)
	print(
		"PHONE WORKSPACE: the %s phone, %d by %d, at %.0f dpi; the window is %d by %d and its room is %d by %d at %.2f"
		% [_shape, _glass.x, _glass.y, PHONE_DPI, get_window().size.x, get_window().size.y, _room.x, _room.y, scale]
	)
	print(
		"PHONE WORKSPACE: the glass keeps - camera %s, foot %d of the glass and %d of the room, corner %d of the glass and %d of the room"
		% [
			str(band),
			PhoneHudScript.stated_foot(),
			PhoneHudScript.kept_foot(_room),
			PhoneHudScript.stated_corner(),
			PhoneHudScript.rounded_corner(_room),
		]
	)
	# **And the one thing that decides whether any of it is the phone's arrangement.** A window of the glass's own
	# size is what makes the room the device's, so a desk that could not give it is named here rather than left for a
	# person to notice; nothing is worked out from the two, because they are printed side by side and the comparison
	# is the person's own.
	if get_window().size != _glass:
		print(
			"PHONE WORKSPACE: the window is %d by %d where the glass is %d by %d, so the room above is this desk's arrangement and not the phone's"
			% [get_window().size.x, get_window().size.y, _glass.x, _glass.y]
		)


## Which way up the line asks the phone to be: `--standing` is the other way up from the way silence means, and
## `--lying` says the default out loud. **Neither is a rotation**: a rotation is a number, and the shapes are named
## the way the block names them (`shape=lying`), so a person reading one screen and one log reads one vocabulary.
static func shape_from(asked: PackedStringArray) -> String:
	return "standing" if "--standing" in asked else DEFAULT_SHAPE


## A `--word` this tool does not have, as a sentence ready to print - or nothing when every one of them is known.
## A typo is refused rather than ignored, for the reason the sibling tool gives in as many words: `--standing` with
## one letter wrong would otherwise stand the wrong phone up and say nothing about having done it.
static func unknown_verb(asked: PackedStringArray) -> String:
	for word: String in asked:
		if word.begins_with("--") and not VERBS.has(word):
			return "%s is not one of this tool's verbs: --standing, --lying" % word
	return ""


## The node running a given script, found by walking down from the program - the same search the sibling tools make,
## because where the HUD lives inside `main.tscn` is that scene's business and not this tool's.
static func _find_scripted(root: Node, script_name: String) -> Node:
	if root == null:
		return null
	var script: Script = root.get_script() as Script
	if script != null and script.resource_path.ends_with(script_name):
		return root
	for child: Node in root.get_children():
		var found: Node = _find_scripted(child, script_name)
		if found != null:
			return found
	return null


## Hand the real display and the real device question back, so a run leaves this desk as it found it.
func _exit_tree() -> void:
	PhoneHudScript.force_density(0.0)
	PhoneHudScript.force_display(Vector2i.ZERO, Rect2i())
	TouchInputScript.force(TouchInputScript.Answer.AUTO)
