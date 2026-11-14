extends Node
## A dev tool: **shows** where two things are drawn over each other when they may not be, on the picture.
##
## The rule and the rectangles both exist already. `Hud.drawn_surfaces()` gathers every surface on the screen,
## each measured by the module that owns it - the HUD's own bar and panels by the HUD, a page's window and the
## title bar Godot draws above it by `PageChrome`, every control that says something by `HudProbe` - and
## `DrawnSurfaces.meetings()` decides which of them share rows they may not. What **no instrument did** was show
## it: every reading until now was a line of text in a log, which a person reads one at a time and cannot see the
## shape of. Measured on the A16W held upright, that gap is exactly what let a real fault stand for a whole
## session - the palette's own group header `Layer` drawn across the foot line's words - because nobody had a
## picture of the rows two things were sharing.
##
## **Two colours, because there are two answers.** A meeting that reaches the HUD's own top bar is the fault
## `hud_layout_check` *fails a check on* - drawn **red**. Any other meeting is one that check *names and leaves to
## be judged*, because whether a page over the palette's first button is wrong is a judgement and not a
## measurement - drawn **amber**. Nothing here decides anything: both colourings come from the same meetings the
## rest of the program already reports, and the colour only says which of the two the program thinks it is.
##
## **A screen is needed, and it says so in words where there is none.** The rectangles are in the pixels a
## screenshot is counted in (`HudProbe` composes every one of them through the screen transform, so a picture and
## a rectangle are in one space), and a headless run has no framebuffer to draw them on. That question is
## `HudProbe._a_real_screen()`'s, asked here rather than spelled out.
##
## Run it in the editor with `run_scene` for the board, or **from a command line with an argument** for a page -
## `run_scene` takes a scene path and no arguments, so a page can only be asked for where a command line exists.
## The pages' own open methods are the HUD's, so `res://tools/page_index.gd` lists what can be asked for:
##
##     godot --path . res://tools/gui_overlap_show.tscn                              the board
##     godot --path . res://tools/gui_overlap_show.tscn -- open_analytics_window     and one page put up first
##
## Reading the board, it **first puts whatever is in front away**: the launch shows the front door, and a page
## draws its own backdrop over everything beneath it. The board's words are still there and still compared, so a
## picture taken through that would show patches over a dimmed screen. Putting what is in front away is the same
## door `Escape` uses, and it does nothing when nothing is up.
##
## It prints every meeting it drew and writes the picture to `res://build/overlap_board.png`, or
## `overlap_<page>.png` for a page.

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const DrawnSurfacesScript := preload("res://scripts/drawn_surfaces.gd")
const HudProbeScript := preload("res://scripts/hud_probe.gd")
const ScreenshotReaderScript := preload("res://scripts/screenshot_reader.gd")

## The colour a meeting that reaches the top bar of the screen is painted in: the one thing about overlap this
## program will call a fault without asking anybody.
const REACHES_THE_BAR := Color(1.0, 0.16, 0.16, 0.45)

## And the colour of every other meeting: named, and left to the person looking at the picture.
const LEFT_TO_BE_JUDGED := Color(1.0, 0.72, 0.1, 0.45)


func _ready() -> void:
	var main: Node = MainScene.instantiate()
	add_child(main)
	for _i: int in 40:
		await get_tree().process_frame
	var hud: Node = main.get_node_or_null("Hud")
	if hud == null:
		print("OVERLAP no Hud")
		return
	var asked: PackedStringArray = OS.get_cmdline_user_args()
	var opened: String = ""
	if asked.size() > 0 and hud.has_method(asked[0]):
		opened = asked[0]
		hud.call(opened)
		for _i: int in 20:
			await get_tree().process_frame
	if opened.is_empty() and hud.has_method("back_puts_away"):
		# The board means the board a person can see. The launch shows the front door, whose own backdrop is
		# drawn over everything beneath it, so its words would be patched onto a dimmed screen.
		hud.call("back_puts_away")
		for _i: int in 20:
			await get_tree().process_frame
	if not HudProbeScript._a_real_screen():
		print("OVERLAP there is no screen to draw on, so there is no picture to make: the rectangles are in the")
		print("        pixels a screenshot is counted in, and a headless run's framebuffer is a dummy display.")
		print("        Run this with a window open, or read the probe's own `overlap` lines instead.")
		return
	var where: String = "the board" if opened.is_empty() else opened
	var surfaces: Array = hud.call("drawn_surfaces")
	var found: Array[Dictionary] = DrawnSurfacesScript.meetings(surfaces)
	print("")
	print("=== %s: %d surface(s) drawn, %d meeting(s) ===" % [where, surfaces.size(), found.size()])
	if found.is_empty():
		print("  nothing meets anything it may not. That is the answer this program is meant to give, and it is")
		print("  the answer for almost every screen: %d rectangles were compared." % surfaces.size())
		return
	# The picture is taken **after** a frame is drawn, so what is painted onto it is the screen the rectangles
	# were measured on rather than one a frame behind it.
	await RenderingServer.frame_post_draw
	var picture: Image = get_viewport().get_texture().get_image()
	var reaching: int = 0
	var judged: int = 0
	for meeting: Dictionary in found:
		var reaches: bool = reaches_the_top_bar(meeting)
		if reaches:
			reaching += 1
		else:
			judged += 1
		paint(picture, meeting["covered"] as Rect2i, REACHES_THE_BAR if reaches else LEFT_TO_BE_JUDGED)
		print(
			"  %s   ->  %s"
			% [
				DrawnSurfacesScript.sentence(meeting),
				"over the bar at the top of the screen" if reaches else "named, left to be judged",
			]
		)
	var to: String = "res://build/overlap_%s.png" % ("board" if opened.is_empty() else opened)
	print("")
	print("  red   %d meeting(s) reaching the top bar - what a check fails on" % reaching)
	print("  amber %d meeting(s) left to be judged - a person reads the patch off the picture" % judged)
	var wrote: Error = ScreenshotReaderScript.write(picture, to)
	if wrote == OK:
		print("  wrote %s" % to)
	else:
		print("  the picture could not be written: %s refused with %s" % [to, error_string(wrote)])


## Whether a meeting is the one the layout check fails a check on: either side of it is the HUD's own top bar.
## Kept here rather than asked of `DrawnSurfaces`, which reports a meeting and does not rank it - the ranking is
## the *check*'s, and this is the same reading of the same two kinds that `hud_layout_check` makes.
static func reaches_the_top_bar(meeting: Dictionary) -> bool:
	for side: String in ["a", "b"]:
		if StringName((meeting[side] as Dictionary)["kind"]) == DrawnSurfacesScript.TOP_BAR:
			return true
	return false


## The rows two surfaces share, painted onto the picture.
##
## Clamped to the image on the way in: a rectangle that reaches past the edge of the screen is a rectangle the
## framebuffer has no pixel for, and asking an `Image` for one is an error rather than a drawing.
static func paint(picture: Image, covered: Rect2i, colour: Color) -> void:
	var first := Vector2i(maxi(covered.position.x, 0), maxi(covered.position.y, 0))
	var past := Vector2i(
		mini(covered.position.x + covered.size.x, picture.get_width()),
		mini(covered.position.y + covered.size.y, picture.get_height()),
	)
	for y: int in range(first.y, past.y):
		for x: int in range(first.x, past.x):
			picture.set_pixel(x, y, picture.get_pixel(x, y).blend(colour))
