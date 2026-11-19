extends Node
## A phone's screen, laid out on this desk: the A16W's glass, its density, its camera and its foot band, stated
## through the same doors a test uses, with `main.tscn` inside a window of exactly the phone's size.
##
## **This is the layout half of a phone question answered without the phone.** Measured 2026-11-18: an afternoon
## went on one sighting that needed the glass in hand at every step, while the layout itself - which plate stands
## where, what the palette cuts, whether a page fits - is arithmetic this desk can do once it is *told* what the
## glass is. The device is stated the way `phone_hud_demo` states its density: `PhoneHud.force_display` for the
## screen and its camera, `PhoneHud.force_density`, `TouchInput.force`, and the foot band from `PhoneHud.KEPT_FEET`
## - which the stated screen unlocks, because that table is keyed by the glass it was measured on.
##
## **The window is the glass, and the room follows from it.** `main.tscn`'s HUD lays out against its own window's
## visible rectangle, so a window of 1080 by 2340 with the canvas drawn up by `PhoneHud.UI_SCALE` is the 1185 by
## 2567 room the phone reports - the same relationship the glass and the room have on the device. A picture of
## this window is therefore 1080 by 2340 and is the phone's screen, square for square.
##
## **What it cannot answer, and says so in its output.** A desk has no system bars: this screen has no navigation
## band and no status bar, and the phone's furniture here is *stated* rather than read. So a picture of this scene
## is a picture of the program's own drawing. The glass stays the arbiter for what a person actually sees, and the
## bands a device draws over the program are not on this screen at all - `--band` is the instrument for those.
##
## Run it with a renderer: a headless run draws nothing and answers no picture.
##
##     res://tools/phone_screen.tscn                        the board, in a phone-shaped window
##     ... -- --shot res://build/phone_screen.png           write the screen at its own size, then quit
##     ... -- --shot                                       write it to `TO_SCREEN` and quit
##     ... -- --door                                        leave the front door up instead of the board

const PhoneHudScript := preload("res://scripts/phone_hud.gd")
const TouchInputScript := preload("res://scripts/touch_input.gd")
const BlankPictureScript := preload("res://scripts/blank_picture.gd")

## The phone this program is aimed at, as its own report states it: the glass, its camera cut into the top 100 px,
## and the density its panel is measured at. **All three go together** - a stated screen on a desk that is not also
## told its density answers nothing at all, because `on_a_finger_here` asks a touchscreen *and* a dense panel.
## **The glass and the usable rectangle, for each way up the board can be held.**
##
## Every number here was read off the A16W's own block rather than derived: standing it reports 1080 by 2340 with
## the cutout at the top (`display l=0 t=100`), and lying it reports 2340 by 1080 with the cutout turned to the
## **left** (`display l=100 t=0`, the same 100 px the notch is worth, now standing at the left edge). The usable
## rectangle is the whole glass less that inset, which is the shape `PhoneHud.force_display` takes.
##
## The *room* is not here, because it is the program's own arithmetic and not a statement: a window of the lying
## glass with the project's own stretch gives 1444 by 666, which is exactly what the device reports (`scale=1.62`,
## being min(2340/1600, 1080/900) * 1.35) - so both ways up are reproduced from the display alone.
const SHAPES: Dictionary = {
	"standing": { "glass": Vector2i(1080, 2340), "usable": Rect2i(0, 100, 1080, 2240) },
	"lying": { "glass": Vector2i(2340, 1080), "usable": Rect2i(100, 0, 2240, 1080) },
}
const PHONE_DPI := 450.0

## The verbs this tool has. Everything after a verb is its own value, and a value here never begins with `--`.
const VERBS: PackedStringArray = ["--shot", "--door", "--standing", "--lying"]

## Where a bare `--shot` writes, so an unasked-for path still leaves the picture somewhere findable.
const TO_SCREEN := "res://build/phone_screen.png"

## How long the program is given to lay out before anything is pressed or photographed. It boots in about three
## seconds on this desk, and a picture taken before its chrome has settled is a picture of the front door in
## pieces - which is the fault every reading in this project that was taken too early has had.
const BOOT_SECONDS := 4.0

## And how long it is given to reach the board after the escape, which is a page being put away.
const PUT_AWAY_SECONDS := 1.5

var _phone: Window = null
var _screen: SubViewportContainer = null
var _view: SubViewport = null
var _app: Node = null
## The display this run states, from `SHAPES` and the line's own way-up. Held rather than looked up at each use so
## that the window, the title and the two lines that name the glass cannot come to disagree about it.
var _glass: Vector2i = Vector2i(1080, 2340)
var _usable: Rect2i = Rect2i(0, 100, 1080, 2240)


func _ready() -> void:
	var asked := PackedStringArray(OS.get_cmdline_user_args())
	var complaint: String = unknown_verb(asked)
	if not complaint.is_empty():
		print("PHONE SCREEN %s" % complaint)
		get_tree().quit(1)
		return
	# **Which way up the board is being asked about**, from the line: `--lying` states the phone on its side, and
	# standing is what silence means. The glass and the usable rectangle come from the one table, because a display
	# stated half one way up and half the other is exactly the lie that taking both halves avoids.
	var place: Dictionary = SHAPES[shape_from(asked)]
	_glass = place["glass"]
	_usable = place["usable"]
	_state_the_device()

	_phone = Window.new()
	_phone.title = "the A16W's glass, %d by %d" % [_glass.x, _glass.y]
	_phone.size = _glass
	# **The project's own stretch is handed on, not copied.** A `Window` made at runtime starts with canvas scaling
	# switched off, so a 1080 by 2340 window given only the canvas factor came out an **800 by 1733** room - the
	# window divided by 1.35 and nothing else, measured 2026-11-18 - and the cutout and the foot band then took
	# their shares of that wrong room (74 px and 31 px instead of 110 and 46). The root window is where the
	# project's own base size and stretch mode live, so the phone's window is given that one's own answers, and the
	# room that follows is the 1185 by 2567 the device reports: 1080 / (min(1080/1600, 2340/900) * 1.35) is 1185.
	var root: Window = get_window()
	_phone.content_scale_size = root.content_scale_size
	_phone.content_scale_mode = root.content_scale_mode
	_phone.content_scale_aspect = root.content_scale_aspect
	add_child(_phone)
	# The canvas drawn up by the project's own scale, through the door the program itself uses: `apply_if` is what
	# `PhoneHud.apply` calls, so what this window is given is what a phone's window is given and nothing new.
	PhoneHudScript.apply_if(_phone, true)

	# **The program hangs inside a `SubViewport`, because the two facts come from two different things.** A
	# `Window` is what makes `canvas_scale` answer the phone's 0.91, and the fitting is sized by it: the palette's
	# own rectangles are byte-identical to the device's only because of it (measured 2026-11-18). A `Window` is
	# also *unreadable* - an embedded one is composited into its parent, so its texture came out an empty 15 KB of
	# one flat colour. A `SubViewport` renders to a texture of its own at any size, and a `SubViewportContainer`
	# with `stretch` hands it exactly the window's visible rectangle, which is the room. So the room is the
	# container's and the scale is the window's, and nothing here restates either.
	_screen = SubViewportContainer.new()
	_screen.stretch = true
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_phone.add_child(_screen)
	_view = SubViewport.new()
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# **Everything the program opens is embedded inside this view.** A `SubViewport` embeds nothing by default, so
	# a page - and the front door's own sheet - both being `Window`s, became separate OS windows drawn nowhere this
	# view could be read, and holding the keyboard focus besides (the blocks showed the front door's backdrop and
	# no sheet, measured 2026-11-18). A phone's window embeds its pages, so this one does too, and a picture then
	# holds what a person would be looking at.
	_view.gui_embed_subwindows = true
	_screen.add_child(_view)
	# A colour was laid under the program while this scene was being built, because a `SubViewport` that renders
	# and a program that draws *into* it look identical on paper: both are a flat rectangle of one colour. That
	# marker is gone now that the nesting is known to be right - a picture that lies is worse than no picture - and
	# the run's own verdicts above are what says whether the view holds anything.
	_app = load("res://scenes/main.tscn").instantiate()
	_app.name = "App"
	_view.add_child(_app)
	await get_tree().create_timer(BOOT_SECONDS).timeout

	# The front door is what the program shows first, and the board is reached the way a person reaches it - the
	# program's own escape ladder, through a real key rather than a second door written here.
	if not asked.has("--door"):
		_press_escape()
		await get_tree().create_timer(PUT_AWAY_SECONDS).timeout

	# **And the block is asked for again, because a picture and a block have to be of the same moment.** The HUD
	# publishes one as a page is *shown* and not as one is put away, so the block above is the front door's - and
	# a reading of a screen that has since changed is the fault every instrument in this project warns about. This
	# asks the HUD to say the screen again through its own door rather than reading a second one out here.
	var hud: Node = _find_scripted(_app, "hud.gd")
	if hud == null:
		print("PHONE SCREEN: main.tscn holds no HUD, so the block above is the launch one and not this screen's")
	else:
		hud._say_the_screen()

	# **Two of the block's checks cannot be the phone's here, and the run says so rather than dropping them.**
	# `InView` compares a control with the **root viewport's** rectangle - deliberately, because that is the rule
	# that found the phone's own view buttons drawn off the glass - and the finger floor is converted through the
	# same room (`hud_probe`). A phone's root window *is* the glass; a desk's root window is the desk, so here
	# every control of a 2567-tall phone room is named past the foot of a shorter window, and the floor comes out
	# scaled by the wrong ratio - 144 where the device itself states 107, which is 1600 / 1185 of it (measured
	# 2026-11-18). Those three lines are this window's numbers and not the device's, and a phone's own block is
	# the arbiter for them: it reports none. Every other line above is the phone's, line for line.
	print(
		"PHONE SCREEN: the offscreen, page-edge and small lines above are this desk's own %d by %d window"
		% [get_window().size.x, get_window().size.y]
	)
	print("PHONE SCREEN: rather than the glass, so a phone's own block is the arbiter for those three.")

	# **The block above is the reading this scene exists to make possible**, and it is the program's own words:
	# a run says whether the room, the bands and the foot are the phone's before any picture is taken.
	print("PHONE SCREEN: a %d by %d window, and the program's own block above it" % [_glass.x, _glass.y])

	var shot: String = shot_path(asked)
	if shot.is_empty():
		# **A run with no `--shot` still has to end.** The block above *is* the reading, and a scene that simply
		# returned left the process up for ever - measured 2026-11-19, a bare run printed its block and was then
		# killed by a five-minute ceiling, having never quit. The program is put away first, in the same order every
		# other ending here uses, so the notifications land on a tree that still holds them.
		await _leave_the_app_standing()
		_put_the_device_back()
		get_tree().quit()
		return
	await RenderingServer.frame_post_draw
	var picture: Image = _view.get_texture().get_image()
	# **The project's own judgement of a picture**, comparing every byte in one place: a sampled grid has twice
	# missed a real mark here. A picture with nothing on it is written all the same - a person looking at it is
	# the strongest reading there is - but the run says what it wrote rather than leaving it to be discovered.
	var view_verdict: String = BlankPictureScript.why(picture)
	var desk_verdict: String = BlankPictureScript.why(get_window().get_texture().get_image())
	print("PHONE SCREEN: the view:      %s" % ("shows something" if view_verdict.is_empty() else view_verdict))
	print("PHONE SCREEN: this run's own window: %s" % ("shows something" if desk_verdict.is_empty() else desk_verdict))
	# **Where the program actually drew**, which no picture can say: a `SubViewport` is a viewport of its own, and
	# the program answering a room from inside it is the only proof that this is where it is drawing. A number of
	# children of one means the program is the only thing in there, and the colour laid under it is behind.
	print(
		"PHONE SCREEN: the program's viewport is `%s`, and the view holds %d child(ren)"
		% [_app.get_viewport().name, _view.get_child_count()]
	)
	# **The run's own window too**, because an embedded window is composited into it: this picture says whether a
	# glass taller than the desk's screen is drawn whole, scaled to fit, or cut off - three answers that look the
	# same in a log and different in a picture.
	var in_the_window: Image = get_window().get_texture().get_image()
	if in_the_window != null and not in_the_window.is_empty():
		in_the_window.save_png(shot.replace(".png", "-in-the-window.png"))
	if picture == null or picture.is_empty():
		print("PHONE SCREEN: nothing at all came back from the view, so no picture was written.")
		await _leave_the_app_standing()
		_put_the_device_back()
		get_tree().quit(1)
		return
	picture.save_png(shot)
	# **The picture is the canvas, not the glass.** A `SubViewport` is read before the window's scale is applied,
	# so what is written is the room's own pixels - 1185 by 2567 for this device, where the glass is 1080 by 2340.
	# That is where the layout lives, and the ratio between the two is the scale the block above reports; nothing
	# is resampled here, because a picture of the layout is worth more than a blurred copy of the screen.
	print(
		"PHONE SCREEN: wrote %s, %d by %d - the room's own canvas, the glass being %d by %d"
		% [shot, picture.get_width(), picture.get_height(), _glass.x, _glass.y]
	)
	# **The program is put away before this scene quits**, rather than left for the exit to free: a live game torn
	# down mid-frame answered a resize on a viewport it no longer had (`disable_3d` on a null) and placed a page
	# into a tree it had already left. The picture is written either way, but a run that prints errors has failed.
	await _leave_the_app_standing()
	_put_the_device_back()
	get_tree().quit()


## Put the program away in the order it would put itself away, giving a frame between the two so the notifications
## land on a tree that still holds them.
func _leave_the_app_standing() -> void:
	if _app != null:
		_app.queue_free()
		_app = null
	await get_tree().process_frame
	if _phone != null:
		_phone.queue_free()
		_phone = null


## State the A16W as this desk's display, so that every question the program asks about its device is answered
## with the phone's own numbers rather than this monitor's.
func _state_the_device() -> void:
	PhoneHudScript.force_density(PHONE_DPI)
	TouchInputScript.force(TouchInputScript.Answer.FINGER)
	PhoneHudScript.force_display(_glass, _usable)


## Hand the real display and the real device question back, so a run leaves this desk as it found it.
func _put_the_device_back() -> void:
	PhoneHudScript.force_density(0.0)
	PhoneHudScript.force_display(Vector2i.ZERO, Rect2i())
	TouchInputScript.force(TouchInputScript.Answer.AUTO)


## The program's own way out of the front door - and **through the program's own binding**: the ladder answers
## `draft_cancel` in `_unhandled_input`, so what is pushed is the event that action is bound to, not a key chosen
## here. That is the same reason a second door written in this file would be wrong. Two things had to be right and
## both were wrong at first (measured 2026-11-18): a key handed to `Input` goes to the *root* window and never
## reaches a program living in a `SubViewport`, and a focused control swallows the key before `_unhandled_input`
## sees it at all - so the focus is given up first, exactly as a finger on a phone never leaves one behind.
func _press_escape() -> void:
	var viewport: Viewport = _app.get_viewport()
	if viewport == null:
		return
	viewport.gui_release_focus()
	# **A page in front answers for itself, and the program says so in its own words**: "the pages that live in a
	# `Window` are deliberately not here: a focused window takes the keyboard into its own viewport, so this node
	# never sees an Escape meant for one". So the event goes to the page when there is one - the same page the
	# program's own Back key would hand it to, found through the HUD's own door - and to the program's viewport
	# when the board is what is up.
	var page: Viewport = _the_page_in_front()
	var handed_to: Viewport = page if page != null else viewport
	handed_to.gui_release_focus()
	var bound: Array[InputEvent] = InputMap.action_get_events(&"draft_cancel")
	if bound.is_empty():
		print("PHONE SCREEN: `draft_cancel` is bound to nothing, so this scene cannot reach the program's own way")
		return
	for event: InputEvent in bound:
		for held: bool in [true, false]:
			var out: InputEvent = event.duplicate()
			out.set("pressed", held)
			handed_to.push_input(out)


## Which way up the line asks the board to be: `--lying` is the phone on its side, and **silence means standing**,
## because standing is what every reading in this project was taken at until the lying one was written down.
##
## `--lying` wins if both are given, and neither is a *rotation*: a rotation is a number and the program's own word
## for a shape is what a person reads in the block (`shape=lying`), so the shapes are named and the rotations are
## not.
static func shape_from(asked: PackedStringArray) -> String:
	if "--lying" in asked:
		return "lying"
	return "standing"


## A `--word` this tool does not have, as a sentence ready to print - or nothing when every one of them is known.
##
## A typo is **refused rather than ignored**: `--lynig` would otherwise state the standing glass and say nothing
## about having done it, and the sibling tool's own words for exactly this apply here - a typo that holds somebody's
## phone at random is worse than a line saying what it wanted. The value after a verb is a path or a word and never
## begins with `--`, so every `--` word here is a verb.
static func unknown_verb(asked: PackedStringArray) -> String:
	for word: String in asked:
		if word.begins_with("--") and not VERBS.has(word):
			return "%s is not one of this tool's verbs: --shot, --door, --standing, --lying" % word
	return ""


## The path after `--shot`, or nothing when none was asked for. A bare `--shot` writes to `TO_SCREEN`, and the two
## are told apart by what follows it rather than by counting, so `--shot` last is the same as `--shot` bare.
static func shot_path(asked: PackedStringArray) -> String:
	var at: int = asked.find("--shot")
	if at < 0:
		return ""
	if at + 1 >= asked.size() or asked[at + 1].begins_with("--"):
		return TO_SCREEN
	return asked[at + 1]


## The node running a given script, found by walking down from the program - the same search `phone_hud_demo`
## makes, because where the HUD lives inside `main.tscn` is that scene's business and not this tool's.
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


## The page the program itself would reach first, through the HUD's own door rather than a search for windows
## made here - or nothing when the board is what is up. A `Window` is a `Viewport`, which is why a page can be
## handed an event the same way the program's own root window can.
func _the_page_in_front() -> Viewport:
	var hud: Node = _find_scripted(_app, "hud.gd")
	if hud == null:
		return null
	var page: Window = hud.page_in_front()
	if page == null:
		return null
	return page as Viewport


func _exit_tree() -> void:
	_put_the_device_back()
