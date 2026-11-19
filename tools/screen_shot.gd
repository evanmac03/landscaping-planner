extends Node
## A dev tool: **a picture of the screen, and the moment it is a picture of** - for a person, and for an
## agent, which cannot look at the glass at all.
##
## The pieces all exist. `ScreenshotReader` reads a picture's colours and cuts a region out of it, the colour
## walk down one column of the glass is `page_chrome_probe`'s, and the rectangles two surfaces share are drawn
## onto a picture by `gui_overlap_show`. But each one answers one question about one screen, and none of them
## answers the plainest question of the lot - **what is on the screen, hand it to me, and say which moment it
## is.** That is the gap this covers, and it is the gap that costs an agent most: an agent reads a prompt and a
## log and never the glass, so a fault a person settles in one look has to be argued about in sentences.
##
## Three questions, and the third is the one that is easy to skip.
##
## **1. What is on the screen.** The real `main.tscn` is put up, whatever is in front is put away, and the
## framebuffer is read after a frame has been drawn - the same three steps, in the same order, that
## `gui_overlap_show` takes, and for the same reasons: a picture of the launch shows the front door, whose own
## backdrop is drawn over everything beneath it, and a picture taken before the frame is drawn is a frame
## behind the rectangles that were measured on it.
##
## **2. Which moment it is.** Beside the picture goes how it was taken, how big it is, the room it counts in
## (`HudProbe.screen_room` - the screen's own rectangle, since a page is a viewport of its own and asking one
## for its visible rectangle answers with the page's size while every control inside it is in screen pixels),
## and every page that is up, filtered through `PageIndex.scripts()`: the same reading, of the same two
## owners, that the console's `:pages` makes. A picture already on disk is answered differently and more
## sharply - its size, **when it was written, and how long ago**. That line is as much why this file exists as
## the picture is. A stale picture answers the question it was taken for and says nothing about the question
## being asked now, and a hardcoded name in a script - a phone held upright while it lay on its side - cost a
## whole session exactly that way.
##
## **3. Let me look closer.** A whole phone screen handed over at once is a smear, and a rule one pixel wide is
## not a line in it. So a region can be cut out, doubled with every pixel kept square, and written where it can
## be looked at, and the colours down that region's own column are printed as rows - a hairline is a
## measurement before it is a sight. A rectangle can also be drawn onto a picture, for the question this
## project asks more than any other: is the rectangle the program *states* where the thing is *drawn*?
##
## **Nothing here decides anything, and nothing here is a second engine.** The colour runs are
## `ScreenshotReader`'s, the room and a page's own line are `HudProbe`'s, which scripts are pages is
## `PageIndex`'s, and the picture is written through `ScreenshotReader.write`, which goes through a temporary
## file and a rename so a write that fails never leaves a half-written picture where a good one was. This file
## phrases the answers and chooses the moment.
##
## Run it:
##
##     run_scene res://tools/screen_shot.tscn                        the desk, now, into res://build/the_screen.png
##     godot --path . res://tools/screen_shot.tscn -- --page open_analytics_window
##     ... -- --from res://build/board.png                          a picture already on disk, and its age
##     ... -- --from <picture> --zoom x y w h                       one region of it, twice as big, and read
##     ... -- --from <picture> --mark x y w h                       one rectangle drawn onto it, to be looked at
##     ... -- --named                                               the screen now, with every control numbered at it
##     ... -- --from <picture> --against <picture>                 what moved between two pictures, and when each
##     ... -- --against <picture>                                  the screen now, against the picture that run left
##
## **A screen is needed to take a picture, and none is needed to read one.** `HudProbe._a_real_screen()` is
## asked before a framebuffer is read - a headless run's display is a dummy and a picture of it is a picture of
## nothing - and that question is asked of the module that owns it rather than spelled out here. Reading a
## picture off the disk needs no screen at all, which is the whole point of `--from`: a picture pulled off a
## phone stays answerable after the phone is gone, and a device that will not stay on a USB cable has ended
## more than one session in this project.
##
## Not part of the game. The export excludes `tools/*`, so nothing here ships.

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const ScreenshotReaderScript := preload("res://scripts/screenshot_reader.gd")
const HudProbeScript := preload("res://scripts/hud_probe.gd")
const PageIndexScript := preload("res://scripts/page_index.gd")
const PageLayoutScript := preload("res://scripts/page_layout.gd")
const StillnessScript := preload("res://scripts/stillness.gd")

## Where a picture lands when no `--to` names another place.
const TO_SCREEN := "res://build/the_screen.png"
const TO_ZOOM := "res://build/the_zoom.png"
const TO_MARK := "res://build/the_marked.png"

## Where a numbered picture lands. A place of its own rather than over `the_screen.png`, because the two answer
## different questions - one is what the screen looks like, the other is which control is which - and overwriting
## the first with the second would cost a person a picture they were looking at.
const TO_NAMED := "res://build/the_screen_named.png"

## The plate a number sits on and the ink it is drawn in. The plate is not decoration: a number drawn straight onto
## a caption is a number nobody can read, which is the same lesson the `overlap` lines were built on.
const NUMBER_PLATE := Color(0.0, 0.0, 0.0, 0.62)
const NUMBER_INK := Color(1.0, 1.0, 1.0, 1.0)
const NUMBER_SCALE := 2

## How many colour runs down one column are worth printing before the column is called shaded and the picture
## is handed over instead. A shaded surface - the plan canvas, a panel lit from one side - is hundreds of runs,
## and a list that long is not read by anybody; the number left out is printed, so the list never pretends to
## be the whole of it.
const MOST_BANDS := 24

## The rectangle this tool draws, and what it means. It means **nothing but "this is the rectangle that was
## asked about"**: the colour carries no verdict, unlike the two `gui_overlap_show` paints with, because
## whether the rectangle is where the thing is drawn is the judgement the person looking at the picture makes.
## Blended, so what is underneath is still read through the mark.
const MARK := Color(1.0, 0.16, 0.16, 0.45)
const MARK_WIDTH := 3

## How long the program and a page are given to settle before the framebuffer is read. The same counts the two
## other tools that photograph this program wait, and for the same reason: the launch shows the front door and
## a page is not where it will be on the frame it is put up.
const FRAMES_FOR_THE_PROGRAM := 40
const FRAMES_FOR_A_PAGE := 20


func _ready() -> void:
	var asked: Dictionary = asked_for(OS.get_cmdline_user_args())
	if not String(asked["complaint"]).is_empty():
		print("SCREEN SHOT ", asked["complaint"])
		get_tree().quit()
		return
	var handed_in := String(asked["from"])
	var against := String(asked["against"])
	if not handed_in.is_empty():
		_say_a_picture_on_disk(handed_in, asked)
		if not against.is_empty():
			_say_what_moved_between(against, handed_in)
		# A run with no window has nothing left to draw, so it ends here rather than waiting to be killed.
		get_tree().quit()
		return
	await _take_the_screen(asked)


## A picture already on disk: its own facts, and then whatever was asked about one region of it.
func _say_a_picture_on_disk(path: String, asked: Dictionary) -> void:
	for line: String in file_lines(path):
		print(line)
	var picture: Image = ScreenshotReaderScript.read(path)
	if picture == null:
		return
	var to: String = String(asked["to"])
	if bool(asked["zoom_asked"]):
		for line: String in doubled_lines(picture, asked["zoom"], to if not to.is_empty() else TO_ZOOM):
			print(line)
	elif bool(asked["mark_asked"]):
		for line: String in mark_lines(picture, asked["mark"], to if not to.is_empty() else TO_MARK):
			print(line)
	elif not to.is_empty():
		print(
			(
				"SCREEN SHOT --to names the picture a region or a rectangle makes, and neither was asked for:"
				+ " add --zoom x y w h or --mark x y w h"
			)
		)
	else:
		print("  next        one region of it, twice as big, or one rectangle drawn onto it:")
		print("              --from %s --zoom x y w h" % path)
		print("              --from %s --mark x y w h" % path)


## What moved between two pictures **already on disk**, each read and the pair put in the order they were written.
##
## A pair named by hand - "the capture off the phone, and the picture of the desk" - is the case this exists for,
## and **neither order of naming is a mistake**: whichever was written first is the earlier one, and the answer
## says which was which. The ordering is `FileAccess.get_modified_time`'s, and a pair written within the same
## second keeps the order it was named in.
func _say_what_moved_between(one: String, other: String) -> void:
	var a: Image = ScreenshotReaderScript.read(one)
	var b: Image = ScreenshotReaderScript.read(other)
	if a == null or b == null:
		var missing: String = one if a == null else other
		print("SCREEN SHOT there is no readable picture at %s, so there is nothing to compare with" % missing)
		return
	var a_when: int = FileAccess.get_modified_time(one)
	var b_when: int = FileAccess.get_modified_time(other)
	var b_is_earlier: bool = b_when < a_when
	var earlier_path: String = other if b_is_earlier else one
	var later_path: String = one if b_is_earlier else other
	for line: String in compared_lines(
		b if b_is_earlier else a,
		a if b_is_earlier else b,
		"the earlier  %s   written %s" % [earlier_path, _written_when(earlier_path)],
		"the later    %s   written %s" % [later_path, _written_when(later_path)],
		a_when != b_when,
	):
		print(line)


## The picture just taken, against one already on disk: **the reading loop**, where the earlier picture is the
## one the last run left and this run's is the screen as it is now.
##
## The order is **known** here rather than worked out - the picture just taken is the later one whatever the
## clock says - which is why this does not go through the by-writing rule above.
func _say_what_moved_since(earlier: String, now_picture: Image) -> void:
	var before: Image = ScreenshotReaderScript.read(earlier)
	if before == null:
		print("SCREEN SHOT there is no readable picture at %s to compare this screen with" % earlier)
		return
	for line: String in compared_lines(
		before,
		now_picture,
		"the earlier  %s   written %s" % [earlier, _written_when(earlier)],
		"the later    the screen just photographed, in this run",
		false,
	):
		print(line)


## A file's writing time as a person reads it, the same two ways `file_lines` gives it - so the two pictures of a
## pair are told apart even when both were written a minute ago.
static func _written_when(path: String) -> String:
	var written: int = FileAccess.get_modified_time(path)
	return "%s, %s" % [Time.get_datetime_string_from_unix_time(written, true), _ago_from_now(written)]


## Two pictures of one screen, and what moved between them - **the whole of the arithmetic is `Stillness`'s**,
## and what this adds is the pair's two moments, because a difference is only meaningful with when each was
## taken. That is the same rule `--from` follows with a single picture, and the reason this verb exists at all: a
## picture answers the question it was taken for, and a *pair* is the only thing that can answer "did what I just
## changed move anything".
##
## Nothing here is decided: a band is named and not judged, exactly as `Stillness` names it - a caret blinking is
## an animation doing its job, a progress line moving is a screen working, and a caption that moved while the
## screen around it held still is the one a person wants to look at. **Every band is printed**, however many
## there are, because a list that stopped early would be a list pretending to be the whole of the difference.
static func compared_lines(
	before: Image,
	after: Image,
	before_when: String,
	after_when: String,
	ordered_by_writing: bool,
) -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("=== what moved between two pictures ===")
	lines.append("  %s" % before_when)
	lines.append("  %s" % after_when)
	if before == null or after == null:
		lines.append("  one of the two is not a picture this could read, so there is nothing to compare.")
		return lines
	if not StillnessScript.same_shape(before, after):
		lines.append(
			(
				"  these are not one screen: %d x %d against %d x %d. Subtracting two shapes would invent a"
				% [before.get_width(), before.get_height(), after.get_width(), after.get_height()]
			)
		)
		lines.append("  change along the whole of the shorter one, so this pair answers with nothing at all.")
		return lines
	if ordered_by_writing:
		lines.append("  ordered      by when each was written, not by the order they were named")
	var bands: Array[Dictionary] = StillnessScript.bands(before, after)
	if bands.is_empty():
		lines.append("  nothing moved: the two pictures are the same screen, row for row.")
		return lines
	lines.append(
		(
			"  moved        %d band(s) of rows, %.1f%% of the picture's height:"
			% [bands.size(), StillnessScript.moved_share(bands, after.get_height()) * 100.0]
		)
	)
	for band: Dictionary in bands:
		lines.append("              " + StillnessScript.sentence(band))
	return lines


## The desk's own screen, now.
##
## It leaves the program standing rather than quitting, because the picture and the screen it was taken from
## are meant to be the same thing: `run_scene` photographs the running scene when its window ends, so a tool
## that has already torn the tree down answers with nothing.
func _take_the_screen(asked: Dictionary) -> void:
	var main: Node = MainScene.instantiate()
	add_child(main)
	for _i: int in FRAMES_FOR_THE_PROGRAM:
		await get_tree().process_frame
	var hud: Node = main.get_node_or_null("Hud")
	if hud == null:
		print("SCREEN SHOT there is no Hud in the program, so there is nothing to look at")
		return
	var page: String = String(asked["page"])
	if not page.is_empty():
		if not hud.has_method(page):
			print(
				(
					"SCREEN SHOT the HUD has no method %s to open a page with: res://tools/page_index.gd lists"
					+ " every page this project has, with the method that opens it"
				)
				% page
			)
			return
		hud.call(page)
		for _i: int in FRAMES_FOR_A_PAGE:
			await get_tree().process_frame
	elif hud.has_method("back_puts_away"):
		hud.call("back_puts_away")
		for _i: int in FRAMES_FOR_A_PAGE:
			await get_tree().process_frame
	if not HudProbeScript._a_real_screen():
		print("SCREEN SHOT there is no screen to photograph: a headless run's display is a dummy, and a picture")
		print("            of it would be a picture of nothing. Run this where a window is open.")
		return
	await RenderingServer.frame_post_draw
	var picture: Image = get_viewport().get_texture().get_image()
	var wrote: Error = ScreenshotReaderScript.write(picture, TO_SCREEN)
	for line: String in live_lines(picture, HudProbeScript.screen_room(self), _the_pages_up(main), TO_SCREEN, wrote):
		print(line)
	if not String(asked["against"]).is_empty():
		_say_what_moved_since(String(asked["against"]), picture)
	var to: String = String(asked["to"])
	if bool(asked["zoom_asked"]):
		for line: String in doubled_lines(picture, asked["zoom"], to if not to.is_empty() else TO_ZOOM):
			print(line)
	elif bool(asked["mark_asked"]):
		for line: String in mark_lines(picture, asked["mark"], to if not to.is_empty() else TO_MARK):
			print(line)
	elif bool(asked["named"]):
		for line: String in named_lines(picture, hud, TO_NAMED):
			print(line)


## **Every control on the screen, its number drawn at it, with the block's own lines as the legend.**
##
## The numbers and the rectangles come from `HudProbe.tap_controls` - the very walk the block's `tap` lines are
## written from - numbered from one and carried across the parts in the block's own order, so the picture and the
## legend cannot name two different controls. Nothing here decides what a control is called, how big it is, or
## which one it is; this tool phrases an answer and draws it.
##
## A number goes **above** the control's top-left corner where there is room for one, and on the corner itself when
## the control stands in the screen's own top rows - the corner being the one place a number is always on the screen.
## A number laid over a caption would cover the words a person is matching it to, which is the fault the `overlap`
## lines exist for and the one the first version of this picture showed on every button.
func named_lines(picture: Image, hud: Node, to: String) -> PackedStringArray:
	var lines := PackedStringArray()
	var board: Node = hud.get_node_or_null(^"Root")
	var parts: Array = [{ "root": board, "scope": "the board" }]
	for node: Node in hud.get_viewport().get_embedded_subwindows():
		var page: Window = node as Window
		if page != null and page.visible:
			parts.append({ "root": page, "scope": PageLayoutScript.page_name(page) })
	var legend := PackedStringArray()
	var number: int = 1
	for part: Dictionary in parts:
		var root: Node = part["root"]
		var scope: String = String(part["scope"])
		var controls: Array[Dictionary] = HudProbeScript.tap_controls(root, scope, number)
		for one: Dictionary in controls:
			_draw_one_number(picture, Rect2i(one["rect"] as Rect2), int(one["n"]))
		legend.append_array(HudProbeScript.tap_lines(root, scope, number))
		number += controls.size()
	lines.append("=== the screen, with every control numbered ===")
	var wrote: Error = ScreenshotReaderScript.write(picture, to)
	if wrote != OK:
		lines.append("  the picture could not be written: %s refused with %s" % [to, error_string(wrote)])
		return lines
	lines.append("  wrote       %s" % to)
	if legend.is_empty():
		lines.append("  nothing a finger can tap is on the screen, so no number was drawn on it.")
		return lines
	lines.append(
		(
			"  numbered    %d control(s), #1 to #%d, each just above its own control or on its corner where"
			+ " there is no room above it"
		)
		% [legend.size(), legend.size()]
	)
	lines.append("  the legend  is the block's own lines, in the order the numbers run:")
	lines.append_array(legend)
	return lines


## One control's number, on a plate of its own, **above** the control's top-left corner where there is room for it
## and on the corner itself where there is not.
##
## Above rather than on the corner because a number laid over a caption covers the very words a person is matching
## it to - the fault the `overlap` lines exist for, and the one the picture of the first version showed on every
## button of the palette. A control standing in the screen's own top rows has nothing above it, and then the corner
## is the only place the number can be.
##
## The plate is laid by `ScreenshotReader.outline` **with a thickness as tall as the box**, which is that
## function's own documented way of filling a rectangle: a second painter with a fill of its own is exactly how two
## pictures of one screen come to disagree about what is on it.
static func _draw_one_number(picture: Image, rect: Rect2i, number: int) -> void:
	if picture == null:
		return
	var text: String = str(number)
	var plate := Rect2i(
		rect.position,
		Vector2i(
			ScreenshotReaderScript.label_width(text, NUMBER_SCALE) + 2,
			ScreenshotReaderScript.GLYPH_DOWN * NUMBER_SCALE + 2,
		),
	)
	if plate.position.y - plate.size.y >= 0:
		plate.position.y -= plate.size.y
	ScreenshotReaderScript.outline(picture, plate, NUMBER_PLATE, plate.size.y)
	ScreenshotReaderScript.label(picture, plate.position + Vector2i(1, 1), text, NUMBER_INK, NUMBER_SCALE)


## Every page that is up, each as the line `HudProbe` writes for it.
##
## Which scripts are pages is `PageIndex`'s answer, read rather than written down here, so a page added
## tomorrow is a page on this line tomorrow. Which of them are **up** is the running tree's answer, filtered
## through that list rather than being every `Window` in the program: a `PopupMenu` is a `Window` too, and a
## menu is not a page. That filter is the same one the console's `:pages` reads, made of the same two owners.
func _the_pages_up(app: Node) -> PackedStringArray:
	var up := PackedStringArray()
	var known: Array[String] = PageIndexScript.scripts()
	for node: Node in app.find_children("*", "Window", true, false):
		var page: Window = node as Window
		if page == null or not page.visible:
			continue
		var script: Script = page.get_script() as Script
		if script == null or not known.has(script.resource_path):
			continue
		var probe: PackedStringArray = HudProbeScript.page_lines(page)
		up.append(probe[0])
	return up


## The verbs this tool takes, read off the command line, or the complaint that says why they cannot be.
##
## Every verb is `--name`, and the two that carry a rectangle carry **four numbers** - x, y, a width and a
## height - rather than a string to be split: a rectangle read out of a string is one more syntax for a caller
## to get wrong and one more place for a comma to mean something. A short list of numbers is refused by name,
## and so is a verb this tool does not have. Nothing is guessed at.
static func asked_for(args: PackedStringArray) -> Dictionary:
	var asked: Dictionary = {
		"complaint": "",
		"from": "",
		"against": "",
		"page": "",
		"to": "",
		"zoom": Rect2i(),
		"zoom_asked": false,
		"mark": Rect2i(),
		"mark_asked": false,
		"named": false,
	}
	var at: int = 0
	while at < args.size():
		var verb: String = args[at]
		match verb:
			"--from", "--page", "--to", "--against":
				if at + 1 >= args.size():
					asked["complaint"] = "%s wants a value after it and the line ended with it" % verb
					return asked
				asked[verb.substr(2)] = args[at + 1]
				at += 2
			"--named":
				asked["named"] = true
				at += 1
			"--zoom", "--mark":
				var numbers: Array[int] = _numbers_from(args, at + 1)
				if numbers.size() < 4:
					asked["complaint"] = (
						"a rectangle is four numbers - x y w h - and %d could be read after %s" % [numbers.size(), verb]
					)
					return asked
				asked[verb.substr(2)] = Rect2i(numbers[0], numbers[1], numbers[2], numbers[3])
				asked[verb.substr(2) + "_asked"] = true
				at += 5
			_:
				asked["complaint"] = (
					(
						"%s is not one of this tool's verbs: --from, --against, --page, --to, --zoom, --mark,"
						+ " --named"
					)
					% verb
				)
				return asked
	if bool(asked["zoom_asked"]) and bool(asked["mark_asked"]):
		asked["complaint"] = (
			"a region can be zoomed or a rectangle marked, not both in one run: they are two different"
			+ " pictures, and one --to cannot name two"
		)
	if bool(asked["named"]) and (bool(asked["zoom_asked"]) or bool(asked["mark_asked"])):
		asked["complaint"] = (
			"a numbered screen is a picture of its own: --named cannot share a run with --zoom or --mark,"
			+ " which each name a picture of their own"
		)
	if bool(asked["named"]) and not String(asked["from"]).is_empty():
		asked["complaint"] = (
			"--named numbers the controls of the program that is running now, and a picture on disk is not that"
			+ " program: there is nothing left to ask what each control is called. Photograph the screen, or"
			+ " pull the numbers off the picture with --mark"
		)
	return asked


## The numbers at the front of `args`, from `at`: as many as can be read and not one more. A word that is not
## a number ends the run rather than being skipped, because `--zoom 10 20 30 --mark 4 5 6 7` is two rectangles
## and reading across the second verb would silently invent the first one a fourth number.
static func _numbers_from(args: PackedStringArray, at: int) -> Array[int]:
	var numbers: Array[int] = []
	var here: int = at
	while here < args.size() and numbers.size() < 4:
		if not args[here].is_valid_int():
			break
		numbers.append(args[here].to_int())
		here += 1
	return numbers


## A picture of a moment, and the moment: how it was taken, how big it is, the room it counts in, and every
## page that is up - then where the picture was written, or what refused to write it.
##
## Everything it needs is handed in, which is what makes the wording itself testable with no scene, no window
## and no file: a picture of a known size, a room, a list of the probe's own page lines, and a path.
static func live_lines(
	picture: Image,
	room: Vector2i,
	up: PackedStringArray,
	to: String,
	wrote: Error,
) -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("=== a picture of the screen, taken now ===")
	lines.append(
		"  picture     %d x %d, read from the framebuffer of this process's res://scenes/main.tscn"
		% [picture.get_width(), picture.get_height()]
	)
	lines.append("  room        %d x %d screen pixels   (HudProbe's own reading of the screen)" % [room.x, room.y])
	if up.is_empty():
		lines.append("  pages       none is up: this is the board, or a page that has not settled yet")
	else:
		lines.append("  pages       %d up" % up.size())
		for page: String in up:
			lines.append("              " + page)
	if wrote == OK:
		lines.append("  wrote       %s" % to)
	else:
		lines.append("  the picture could not be written: %s refused with %s" % [to, error_string(wrote)])
	lines.append("  look at it  the program is still up, so the screen is still there; the picture is the file")
	lines.append("              above, and one region of it can be had twice as big:")
	lines.append("              --from %s --zoom x y w h" % to)
	return lines


## A picture that is already on disk: what it is, and **when it was made**, which is the line that keeps it
## from being mistaken for the screen now.
##
## A file the tool cannot find, or one that is there and is not a PNG it can read, is refused in a sentence
## that names the file and what was wrong with it - never with a picture of nonsense.
static func file_lines(path: String) -> PackedStringArray:
	var lines := PackedStringArray()
	if not FileAccess.file_exists(path):
		lines.append("SCREEN SHOT there is no picture at %s" % path)
		return lines
	var picture: Image = ScreenshotReaderScript.read(path)
	if picture == null:
		lines.append("SCREEN SHOT %s is there and is not a PNG this can read" % path)
		return lines
	lines.append("=== a picture that is already on disk ===")
	lines.append("  file        %s" % path)
	lines.append("  picture     %d x %d" % [picture.get_width(), picture.get_height()])
	var written: int = FileAccess.get_modified_time(path)
	lines.append(
		"  written     %s, %s" % [Time.get_datetime_string_from_unix_time(written, true), _ago_from_now(written)]
	)
	lines.append("  note        the time above is the whole reason this line is here: a picture on disk answers")
	lines.append("              the question it was taken for, and says nothing about the one being asked now.")
	return lines


## How long ago something was written, said the way a person says it. Kept short and coarse on purpose: the
## question this answers is "is this picture from now, or from another session" and a second's precision would
## not answer it any better.
static func _ago_from_now(when: int) -> String:
	var away: int = int(Time.get_unix_time_from_system()) - when
	if away < 0:
		return "which is after now, so this machine's clock and that file disagree"
	if away < 60:
		return "under a minute ago"
	if away < 3600:
		# Whole minutes and whole hours: the truncation is the point here, because the question this answers
		# is only whether the picture came from this session or from another one.
		@warning_ignore("integer_division")
		return "%d minute(s) ago" % (away / 60)
	if away < 86400:
		@warning_ignore("integer_division")
		return "%d hour(s) ago" % (away / 3600)
	@warning_ignore("integer_division")
	return "%d day(s) ago" % (away / 86400)


## One region of the picture, cut out and doubled, written where it can be looked at - and the colours down
## that region's own column printed as rows, from the top.
##
## The column is the region's **middle** one in the picture's own coordinates and the rows are the picture's
## own row numbers, not the crop's, because those are the numbers a rectangle a module states is measured in
## and the two can be compared without arithmetic.
##
## A region with no pixels in it - wholly off the picture, or empty - is refused in a sentence that says which
## rectangle against which picture, rather than writing an empty file.
static func doubled_lines(picture: Image, region: Rect2i, at: String) -> PackedStringArray:
	var lines := PackedStringArray()
	if picture == null:
		return PackedStringArray(["SCREEN SHOT there is no picture to cut a region out of"])
	var cut: Image = ScreenshotReaderScript.doubled(picture, region)
	if cut == null:
		return PackedStringArray(
			[
				(
					"SCREEN SHOT that region has no pixels in it: %s against a %d x %d picture"
					% [rect_words(region), picture.get_width(), picture.get_height()]
				)
			]
		)
	var wrote: Error = ScreenshotReaderScript.write(cut, at)
	lines.append("=== one region of the picture, twice as big ===")
	lines.append("  region      %s" % rect_words(region))
	if wrote == OK:
		lines.append("  wrote       %s   %d x %d, every pixel kept square" % [at, cut.get_width(), cut.get_height()])
	else:
		lines.append("  the region could not be written: %s refused with %s" % [at, error_string(wrote)])
	# The middle column of a region of even width is either of the two middle ones, and either is the middle.
	@warning_ignore("integer_division")
	var middle: int = region.position.x + region.size.x / 2
	lines.append_array(band_lines(picture, middle, region))
	return lines


## The rectangle drawn onto the picture, and written, for the question of whether the place the program
## *states* is the place the thing is *drawn*.
##
## The rectangle is clamped to the picture once, here, and handed on already inside it, so there is one clamp
## in this file rather than one here and another inside `ScreenshotReader.outline`. A rectangle the picture
## cannot hold at all is refused by name: a mark drawn nowhere is not a fresh picture, and a picture silently
## written unchanged would be read as "the rectangle is where you said".
static func mark_lines(picture: Image, rect: Rect2i, at: String) -> PackedStringArray:
	var lines := PackedStringArray()
	if picture == null:
		return PackedStringArray(["SCREEN SHOT there is no picture to draw a rectangle on"])
	var inside: Rect2i = rect.intersection(Rect2i(0, 0, picture.get_width(), picture.get_height()))
	if inside.size.x <= 0 or inside.size.y <= 0:
		return PackedStringArray(
			[
				(
					"SCREEN SHOT that rectangle is not on the picture: %s against a %d x %d picture"
					% [rect_words(rect), picture.get_width(), picture.get_height()]
				)
			]
		)
	ScreenshotReaderScript.outline(picture, inside, MARK, MARK_WIDTH)
	var wrote: Error = ScreenshotReaderScript.write(picture, at)
	lines.append("=== a rectangle marked on the picture ===")
	lines.append("  rectangle   %s" % rect_words(rect))
	lines.append("  note        the mark means nothing but 'this is the rectangle that was asked about': it is")
	lines.append("              drawn over whatever is there, blended, so what is underneath is read through it.")
	if wrote == OK:
		lines.append("  wrote       %s" % at)
	else:
		lines.append("  the picture could not be written: %s refused with %s" % [at, error_string(wrote)])
	return lines


## The colours down one column, as rows and sizes, for the rows of the region in hand - capped, and **saying
## that it is capped**. A shaded column is a real answer and the picture is where to look; a list that stopped
## at the cap without saying so would be a list pretending to be the whole of the column.
static func band_lines(picture: Image, x: int, within: Rect2i) -> PackedStringArray:
	var lines := PackedStringArray()
	if picture == null:
		return PackedStringArray(["SCREEN SHOT there is no picture to read a column of"])
	var all: Array[Dictionary] = ScreenshotReaderScript.bands_down(picture, x)
	if all.is_empty():
		return PackedStringArray(["SCREEN SHOT column x=%d is not in a %d-wide picture" % [x, picture.get_width()]])
	var first: int = within.position.y
	var last: int = within.position.y + within.size.y - 1
	var crossing: Array[Dictionary] = []
	for band: Dictionary in all:
		if int(band["to"]) < first or int(band["from"]) > last:
			continue
		crossing.append(band)
	lines.append("  bands       down column x=%d, for that region's rows, from the top:" % x)
	var showing: int = mini(crossing.size(), MOST_BANDS)
	for which: int in showing:
		lines.append("              " + ScreenshotReaderScript.sentence(crossing[which]))
	if crossing.size() > showing:
		lines.append(
			"              %d further run(s), left out: a column with this many colours is a shaded"
			% (crossing.size() - showing)
		)
		lines.append("              surface, and the answer there is the picture rather than a list of rows.")
	return lines


## A rectangle as a person reads it, in both words a person uses: where it starts and what it covers, and the
## **inclusive** range of rows and columns it occupies. The second is the off-by-one every reader of a region
## gets wrong once - a rectangle 200 wide at x=16 covers x=16 to x=215, and 215 is the number that has to be
## compared against the edge it may be past.
static func rect_words(rect: Rect2i) -> String:
	return "x %d y %d, %d x %d   (x %d..%d, y %d..%d)" % [
		rect.position.x,
		rect.position.y,
		rect.size.x,
		rect.size.y,
		rect.position.x,
		rect.position.x + rect.size.x - 1,
		rect.position.y,
		rect.position.y + rect.size.y - 1,
	]
