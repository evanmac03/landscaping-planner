class_name HudProbe
extends RefCounted
## What is on the screen, printed where a person driving this program from another computer can read it.
##
## A page is a rectangle on a screen, and anything driving one from outside has only pixels to go by: it can
## take a screenshot, but it cannot ask the program where a button is, what the foot of the screen says, or
## whether this machine was answered as a device with a finger. So time is spent tapping at coordinates read
## off an old screenshot which a scrollbar has since moved. That is the *program's* fault rather than the
## driver's: every one of those figures is known here already, and none of them was being said.
##
## ## What it says, and when
##
## One block, whenever a page is put on the screen - and that includes the first frame of a session, because
## the front door is a page and its own pop is the first thing here that publishes. So a driver that has
## driven nothing at all still finds one block, and it says where this device was answered from, the room
## everything lands in, the two lines at the foot of the screen with the words they are showing, and then the
## board's own controls and the page itself - its title, its rectangle in the pixels a screenshot is taken in,
## and one line for each control a finger could hit, with the centre of it, so that a fixture can be tapped
## without measuring anything at all.
##
## ## A release build says nothing
##
## `on()` is `OS.is_debug_build()`, so a build exported for release carries this code and never runs it, and
## writes no file either. That is also why it lives here rather than in `tools/`: the export excludes that
## folder on purpose, and anything that drives a phone has to be *in* the phone.
##
## ## It reports; it never decides
##
## Every figure is read off the object it belongs to - `Control.get_global_rect()`, the window's own
## `position`, `Viewport.get_screen_transform()` - and nothing is worked out a second time here. A reading
## that could disagree with the program would be worse than no reading at all.
##
## ## Where the pixels come from
##
## A control's rectangle is in the coordinates of the viewport it lives in, which for a control on a page is
## the page's *own* window rather than the screen. `Viewport.get_screen_transform()` is the engine's own
## answer for turning one into the other - this project's stretched canvas included - so a rectangle is
## composed through it and the numbers printed are the numbers `adb shell input tap` wants.

## The word every line starts with, so that one command finds them all:
## `adb logcat -d | grep PROBE`.
const PREFIX := "PROBE"

## Where the same block is kept on the machine, because a log is a ring and a session is not.
##
## `adb logcat` holds a rolling buffer: on a phone, a session long enough to be worth reading has usually
## scrolled past the block that mattered, and once it has gone it has gone. So every block is written here
## as well as printed, and the file is pulled off the device rather than watched live:
##
##     adb exec-out run-as ca.storm.landscapingplanner cat files/probe.log
##
## A debug build is the only one that may be read out of this way, which is the same condition as `on()`.
const LOG_PATH := "user://probe.log"

## What a rewrite of the log goes through on its way to the real file - the same litter every other writer
## here leaves (`autosave.gd`, `cost_book.gd`, the field photos), so a person looking in the folder sees one
## shape of it rather than two.
const TEMP_SUFFIX := ".writing"

## How large the log may grow before it gives up its oldest lines, and how much of the end it keeps when it
## does. A log nobody trims is a file that fills a phone, and the newest blocks are the ones a person came
## for, so the old end is what goes.
const LOG_LIMIT := 1_000_000
const LOG_KEEP := 500_000

## A control a finger can hit.
##
## Deliberately not `PageChrome.ACTED_WITH`, which answers a different question - what takes the *keyboard* -
## and leaves out the things a finger presses without ever tabbing to them: a field, a spinner, a slider, a
## list. A `ScrollBar` is in here on purpose and is not an oversight: a page whose last row is below the fold
## is scrolled by dragging its bar, and the bar's rectangle is exactly the thing a driver cannot otherwise
## find.
const TAPPABLE: Array[String] = ["BaseButton", "LineEdit", "SpinBox", "Range", "ItemList"]

## The controls that *show* something - words, or a list of them - where `TAPPABLE` is the ones a finger can
## press. A container is deliberately not here: it is cut only because something inside it was, and that
## something is reported as itself. Without the list a crowded screen would name every ancestor of every fault
## and the one line that mattered would be lost in the noise.
const SHOWING: Array[String] = [
	"Label",
	"Button",
	"TextEdit",
	"RichTextLabel",
	"ItemList",
	"Tree",
	"LineEdit",
	"OptionButton",
	"ScrollContainer",
]

const PageLayoutScript := preload("res://scripts/page_layout.gd")
const PageChromeScript := preload("res://scripts/page_chrome.gd")
const DrawnSurfacesScript := preload("res://scripts/drawn_surfaces.gd")
const ScreenshotReaderScript := preload("res://scripts/screenshot_reader.gd")
const RoomToSpareScript := preload("res://scripts/room_to_spare.gd")
const GuiWordsScript := preload("res://scripts/gui_words.gd")
const InViewScript := preload("res://scripts/in_view.gd")
const TopmostScript := preload("res://scripts/topmost.gd")
const ContrastScript := preload("res://scripts/contrast.gd")
const TouchTargetScript := preload("res://scripts/touch_target.gd")
const StackedScript := preload("res://scripts/stacked.gd")
const BlankPictureScript := preload("res://scripts/blank_picture.gd")
const SpacingScript := preload("res://scripts/spacing.gd")
const SafeAreaScript := preload("res://scripts/safe_area.gd")
const LegibilityScript := preload("res://scripts/legibility.gd")
const PhoneHudScript := preload("res://scripts/phone_hud.gd")
const ClippedWordsScript := preload("res://scripts/clipped_words.gd")


## Whether this build says anything at all. A release export carries every line below and runs none of it.
static func on() -> bool:
	return OS.is_debug_build()


## What a line of two lines is printed as. Several captions here are genuinely two rows - a tool button is
## `"Line"` over its shortcut letter, and a hint can be two rows of words - and the report is read back out
## of a logcat line, which is cut off rather than wrapped. A newline left in would throw away everything after
## it, and what comes after it is the part a driver came for: the centre of the button. The first report this
## ever printed lost a whole column of the tool grid that way.
const LINE_BREAK := " / "


## One line, fit to be read back from logcat.
static func line_for_printing(text: String) -> String:
	return text.replace("\r\n", LINE_BREAK).replace("\n", LINE_BREAK).replace("\r", LINE_BREAK)


## Print a block, one line at a time: a logcat line is cut off rather than wrapped, so a whole report on one
## `print` would lose its end - and so would any one line holding a newline of its own, which is why every
## line goes through `line_for_printing` rather than being trusted to be one line already.
static func publish(lines: PackedStringArray) -> void:
	if not on():
		return
	for line: String in lines:
		print("%s %s" % [PREFIX, line_for_printing(line)])
	record(lines)


## Keep the block as well as say it, in the very words it was said in: what is written is what was printed,
## so a line read back off the device and a line read out of the log are the same line and cannot come to
## disagree about a number.
##
## Deliberately not gated on `on()`. This is the half a test drives, and a release build reaches neither
## anyway because nothing calls `publish`; gating here would only mean a rule that two places have to keep.
##
## A file that cannot be opened is left unwritten rather than raised, and the same for a rewrite that cannot
## be made: a probe able to stop the program it was measuring would be worse than no probe at all.
static func record(
	lines: PackedStringArray,
	to: String = LOG_PATH,
	limit: int = LOG_LIMIT,
	keep: int = LOG_KEEP,
) -> void:
	# `READ_WRITE` will not bring the file into being, so the first block of a session makes it with `WRITE`
	# and every block after that appends to what is already there. A file made `WRITE` and never truncated
	# again is the same file, and the blocks in it are the ones written before.
	var mode: FileAccess.ModeFlags = FileAccess.READ_WRITE if FileAccess.file_exists(to) else FileAccess.WRITE
	var file: FileAccess = FileAccess.open(to, mode)
	if file == null:
		return
	file.seek_end()
	for line: String in lines:
		file.store_line("%s %s" % [PREFIX, line_for_printing(line)])
	file.flush()
	var written: int = file.get_length()
	file.close()
	if written > limit:
		_keep_the_newest(to, keep)


## Give up the oldest lines once the log has grown past its limit, keeping the end of it whole: the rewrite
## goes through a temporary name and is moved into place, which is the rule every written file here follows,
## so a rewrite that is interrupted leaves the log it had rather than half of the one it was making.
##
## The cut is made at a line break and never inside a line. A block is read back by a person looking for a
## control's rectangle, and a block starting halfway through one is worse than no block at all.
static func _keep_the_newest(to: String, keep: int) -> void:
	var reading: FileAccess = FileAccess.open(to, FileAccess.READ)
	if reading == null:
		return
	var whole: PackedByteArray = reading.get_buffer(reading.get_length())
	reading.close()
	if whole.size() <= keep:
		return
	var window: PackedByteArray = whole.slice(whole.size() - keep)
	# 10 is the line break every line here ends with, so the first one in the window is where whole lines
	# start again.
	var first_whole: int = window.find(10)
	if first_whole < 0:
		return
	var kept: PackedByteArray = window.slice(first_whole + 1)
	var temp: String = to + TEMP_SUFFIX
	var writing: FileAccess = FileAccess.open(temp, FileAccess.WRITE)
	if writing == null:
		return
	writing.store_buffer(kept)
	writing.close()
	if DirAccess.rename_absolute(temp, to) != OK:
		DirAccess.remove_absolute(temp)


## Where this device was answered from, the room everything lands in, the strip at the top of it that no page
## may be placed in, and the two lines a person reads at the foot of the screen. The words are handed in rather
## than read here: what is printed is what the label is actually showing, which is the only reading that can
## settle a question about what a phone was told.
##
## The strip is here because it is the one figure that cannot be read off a picture of a page. A page is placed
## below the bar, so a page standing correctly has a rectangle whose top edge is a title bar below the bar's foot
## - and whether that foot is the number this window's shape asks for is invisible in the page's own rectangle,
## which is placed from it either way. On the SM-A166W it reads **357** on the block taken while this HUD is
## still building its bar and **247** on every block taken afterwards, and 357 is the number the front door was
## placed by - which is what put that page's title bar over the menu titles. A `strip` line beside the `room`
## line is what names which foot a page was placed by.
static func device_lines(
	finger: bool,
	zooming: bool,
	dpi: float,
	scale: float,
	room: Vector2i,
	strip: int,
	native: Vector2i,
	touchscreen: bool,
	shape: StringName,
	foot: String,
	tool: String,
) -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("--- what is on the screen ---")
	lines.append(
		"device   finger=%s zooming=%s touchscreen=%s dpi=%.1f scale=%.2f shape=%s"
		% [str(finger), str(zooming), str(touchscreen), dpi, scale, str(shape)]
	)
	lines.append("room     viewport=%s native=%s" % [str(room), str(native)])
	lines.append("strip    the top %d px of the room is the bar's, and no page may be placed in it" % strip)
	# **The band the device keeps, in this room's own pixels and in the display's.** The room half is the figure
	# `Hud` lifts the top bar by, so the line says what the bar was moved by rather than leaving it to be worked out
	# from a picture; the display half is the reading a person compares with what the phone itself reports. Measured
	# 2026-11-17, this line was missing: the bar's first button stood 212 px down and the block named every control
	# that had strayed *into* the band (`unsafe`) while never saying how large the band was, so the size of the lift
	# could only be guessed at.
	var kept: Vector4i = PhoneHudScript.cutout_here(room)
	var shown: Vector4i = PhoneHudScript.band_as_reported()
	lines.append(
		"insets   room l=%d t=%d r=%d b=%d   display l=%d t=%d r=%d b=%d"
		% [kept.x, kept.y, kept.z, kept.w, shown.x, shown.y, shown.z, shown.w]
	)
	# **The one band the program is *told* rather than reads**, and printed for the same reason the `insets` line
	# is: the `insets` reading above is the display cutout alone, so a program that gives the foot its own ground
	# as well would otherwise read as a program that gives it none. Both figures are here - the display's, which is
	# what a person compares with the phone's own report, and the room's, which is what the plates were moved by -
	# and where nothing is stated the line says so rather than printing a zero nobody could tell from a zero band.
	var kept_foot: int = PhoneHudScript.kept_foot(room)
	if kept_foot > 0:
		lines.append(
			"kept     the foot: %d px of the display, %d of the room (stated, not read)"
			% [PhoneHudScript.stated_foot(), kept_foot]
		)
	else:
		lines.append(
			"kept     the foot: nothing stated for a %d by %d screen, so the scene's own clearance stands"
			% [PhoneHudScript.screen_here().x, PhoneHudScript.screen_here().y]
		)
	lines.append("foot     \"%s\"" % foot)
	lines.append("tool     \"%s\"" % tool)
	return lines


## A row of controls as it came out: the room it was given, what the row itself asks for, and one line per
## child with where it stands and how much room it wants.
##
## The top bar is why this exists. An `HBoxContainer` lays its children out at their own minimum widths and
## lets the row run past the edge of the screen rather than shrink one of them, so the controls at its end are
## drawn where no finger can reach them - measured on a phone, the view buttons at x=1860 on a 1080-wide
## screen, entirely off it. Which child it is that will not fit cannot be read off a screenshot, and it is not
## worked out a second time here either: the row is asked what it holds, and each child what it needs.
static func row_lines(row: Control, what: String, room: float) -> PackedStringArray:
	var lines := PackedStringArray()
	if row == null:
		return lines
	# **A room and a minimum that belong to different things are not a comparison.** The room is what the caller
	# handed the *menus* - the space left for them once the row's other controls had theirs - while the minimum
	# is what the whole *row* asks for. Printed as `room=` and `min=` beside each other they read as one object
	# measured against itself, and on the A16W in portrait they read as a bar overflowing a room: `room=349
	# min=(1052.0, 107.0)` is a row wanting 1052 px in which the menus' 272 px sat comfortably inside their 349.
	# Each number now says whose it is. Measured, and misread twice before it was named.
	lines.append(
		"row      %s  menus_room=%.0f  row_min=%s  row_size=%s  at=%s"
		% [what, room, str(row.get_combined_minimum_size()), str(row.size), _point_words(row.position)]
	)
	for child: Node in row.get_children():
		var control: Control = child as Control
		if control == null:
			continue
		var words: String = ""
		if control is Button:
			words = (control as Button).text
		elif control is Label:
			words = (control as Label).text
		lines.append(
			"row      %s  %-14s  min=%s  size=%s  at=%s  font=%d  shown=%s  \"%s\""
			% [
				what,
				control.name,
				str(control.get_combined_minimum_size()),
				str(control.size),
				_point_words(control.position),
				control.get_theme_font_size(&"font_size"),
				str(control.is_visible_in_tree()),
				words,
			]
		)
	return lines


## Everything a finger could hit in a tree, with the centre of each: what to tap and where.
##
## The walk **stops at a `Window`**: a page answers for its own controls, and this is asked once for the
## board's own chrome and once inside each page that is up, so the two lists never overlap.
##
## **The rectangle published is the part that is *drawn*, and the centre is that part's.** A control a box above
## it is clipping - on a phone, the palette's cells inside its scroller - is half in the picture and half below
## the fold, and the whole of it is not a place anything can be pressed. Published as its layout rectangle, its
## centre could stand on whatever is drawn below the fold. Measured on the A16W lying down: `Line / 1` was given
## as `screen (45, 609) .. (488, 826)` with its centre at (266, 718) while the palette's box - the clip - ended at
## 673, so the centre the block handed a driver was a place on the plate under the palette and a tap there pressed
## nothing. `drawn_rect` is the reader the `overlap` lines already use for exactly this reason.
##
## **Each line ends with the control's own number in the block**, which is what lets a picture carry that number at
## the control while the block's own lines are read as its legend - the same list, so nothing has to be matched up
## by eye. `first` is where the count starts, so that a page's controls carry on from the board's. The number is
## deliberately the **last** thing on the line: every reader of a block finds the rectangle by the last `screen (`
## and the name by the words before it, and both of the phone's own readers (`PhoneTouchPass.rect_of` and
## `named_boxes_of`) are written that way.
## Every control of one part that a finger could hit, **as data rather than as a line**: the number it carries in
## the block, what it is called, and the rectangle that is *drawn* - which is the part of it a picture shows.
##
## This is the one walk. A `tap` line is a rendering of it and a number drawn at a control on a picture is another,
## so the legend, the block and the picture cannot come to name two different controls - and there is no second
## pass of the tree for a caller that wants rectangles rather than words.
static func tap_controls(root: Node, scope: String, first: int = 1) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var number: int = first
	for control: Control in _controls_under(root):
		if not _tappable(control):
			continue
		var rect: Rect2 = drawn_rect(control)
		if rect.size.x < 1.0 or rect.size.y < 1.0:
			continue
		# **The control itself travels with the number**, so that one walk answers both "where can a finger tap" and
		# "what does a plate cover": a control numbered here and unknown to `targets_in` would be a control that can
		# be pressed and cannot be reported on.
		found.append({ "n": number, "scope": scope, "name": _caption(control), "rect": rect, "control": control })
		number += 1
	return found


static func tap_lines(root: Node, scope: String, first: int = 1) -> PackedStringArray:
	var lines := PackedStringArray()
	for one: Dictionary in tap_controls(root, scope, first):
		var rect: Rect2 = one["rect"]
		lines.append(
			(
				"tap      %-28s %-34s screen %s  centre %s  #%d"
				% [
					scope,
					"\"%s\"" % String(one["name"]),
					_rect_words(rect),
					_point_words(rect.get_center()),
					int(one["n"]),
				]
			)
		)
	return lines


## Every surface one tree draws that can meet another: the words, the plates, and the controls a finger
## presses. **The one place the three are gathered**, so the HUD and a workspace asking the same question of
## their own trees cannot come to two different answers about what a surface is.
##
## **A page is not here, and that is deliberate rather than an omission**: a page is a `Window` beside the
## board rather than a control under it, so whoever knows the pages hands them in through `page_surfaces` -
## exactly as `hud.gd` does. This gathers what one walk of one tree can find.
static func all_in(root: Node, scope: String = "the board") -> Array[Dictionary]:
	var surfaces: Array[Dictionary] = words_in(root)
	surfaces.append_array(plates_in(root))
	surfaces.append_array(targets_in(root, scope))
	return surfaces


## Every control that draws a plate of its own and says nothing, with the rectangle it is drawn in.
##
## **A plate and not a page.** A page over the furniture it covers is what a page is, and pages are handed in by
## `page_surfaces`; what this catches is the other thing - a plate drawn across a control a finger must press, which
## takes the press away, or across words, which takes half a sentence away, and neither can be read.
##
## **Named by its node name, and that is the scheme rather than an inconsistency**: a surface that says something is
## named by the words it says, and one that says nothing has only the tree's name to be known by. The ancestry a
## target carries holds both, so either will match.
##
## **A plate that covers the whole room is not in anybody's way**, which is `Topmost`'s own rule and now this one:
## the screen's own backdrop stands under everything by design, and the front door's is drawn across the entire board.
## **This paragraph used to reason instead**, and the reasoning was wrong: it said a sheet that is up has the furniture
## under it switched off, so a covering plate would never become a pair - measured on `hud_layout_check`,
## `StartBackdrop` was paired with every button on the screen, because the front door's board is very much still
## drawn underneath. The room is the *root viewport's* rectangle, never the plate's own viewport, for the reason
## `in_view.gd` states: a page is a viewport of its own and would answer with itself.
##
## **By the engine's own panel kinds, a limit worth stating rather than hiding**: a bare `Control` with a `StyleBox`
## override of its own covers its children too and this does not name it. What it does name is the fault this exists
## for - `Presentation` is a `PanelContainer`, and it was drawn across two of the bar's buttons.
static func plates_in(root: Node) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if root == null:
		return found
	# **The room, in the space a plate is measured in.** `screen_room` is the screen's own pixels rather than a
	# viewport's, which is the whole of the fault `_covers_the_room` records: a plate's rectangle comes from
	# `drawn_rect` and so does this, and the two must be read in one space.
	var room: Vector2i = screen_room(root)
	for control: Control in _controls_under(root):
		if not drawn(control) or _the_engines_own(control):
			continue
		if not (control is PanelContainer or control is Panel or control is ColorRect or control is TextureRect):
			continue
		var said: String = _caption(control)
		if not said.is_empty() and said != control.get_class():
			continue
		var rect: Rect2 = drawn_rect(control)
		if rect.size.x < 1.0 or rect.size.y < 1.0:
			continue
		if _covers_the_room(rect, room):
			continue
		found.append(DrawnSurfacesScript.plate(String(control.name), Rect2i(rect)))
	return found


## Whether a control is drawn across the whole room, which is the one thing a plate may cover and be nothing.
##
## **It is the screen's own pixels that are compared, and a device is what found that this function was not.** It
## read the control's *own* viewport rectangle, which is the logical room a page is laid out in: on the A16W that
## is 1185 x 2567 while the screen is 1080 x 2340. So the front door's backdrop - a full-rect `ColorRect` across
## the whole of the glass - came back as *not* covering the room, and the block named it as drawn over all twelve
## controls beneath it. On a desk the two numbers are equal and no run here could ever have shown it, which is why
## `hud_layout_check` had called this clean since the rule was written.
##
## `screen_room` is that figure, from the same place `screen_rect` measures a control and the block's `tap`
## centres are published: the two sides of this comparison cannot come from two spaces again, because there is now
## one source for the room and the same call answers `tap_boxes`.
##
## A room of nothing - a headless run, whose dummy display has no screen to speak of - is the rule's own case:
## nothing is outside a room that is not there, so no plate is taken for a backdrop and nothing is hidden by this.
static func _covers_the_room(rect: Rect2, room: Vector2i) -> bool:
	if room.x <= 0 or room.y <= 0:
		return false
	return Rect2i(rect).encloses(Rect2i(0, 0, room.x, room.y))


## Every control a finger must press, as `DrawnSurfaces` wants it: its rectangle, and **the names of the panels it
## stands inside**.
##
## **The names are the whole rule.** A panel meets its own children's rectangles by definition, so a list that did not
## say what each control stands inside would report every button in the program as covered by the panel it is in. That
## is why the parent chain is walked here, where the tree is, rather than in a module that measures nothing of its own.
##
## It goes through `tap_controls`, so "where can a finger tap" and "what does a plate cover" are answered by one walk
## of the board and cannot disagree about which controls exist.
static func targets_in(root: Node, scope: String = "the board") -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for one: Dictionary in tap_controls(root, scope):
		var control: Control = one.get("control") as Control
		var where: Rect2 = one["rect"]
		found.append(DrawnSurfacesScript.target(String(one["name"]), Rect2i(where), _surfaces_above(control)))
	return found


## The names of the controls a control stands inside, outermost first - **both names it can be known by**.
##
## **The naming scheme, decided once.** A surface handed to `DrawnSurfaces` is named by what a person *reads* - the
## caption a control draws, so that a report is a sentence and not a tree - while a plate that says nothing is named
## by its node name, because that is the only name it has. So the ancestry carries **both**: a control is its caption
## to a reader and its node name to the tree, and a rule that asked after one of the two was measured naming five
## `SpinBox` fields against their own text, because the walk wrote `"SpinBox"` where the surface said `"16.0  h"`.
##
## Every ancestor is named, and not only the panels: a `SpinBox` is a thing a finger presses and the `LineEdit` inside
## it is what says the number, so neither's rectangle contains the other and only the names can say they are one thing.
## An ancestor that is no surface at all costs nothing by being named - these names are only ever asked whether one
## control is another's.
static func _surfaces_above(control: Control) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if control == null:
		return out
	var parent: Node = control.get_parent()
	while parent != null:
		var box: Control = parent as Control
		if box != null:
			out.append(String(box.name))
			var said: String = _caption(box)
			if not said.is_empty() and said != box.get_class():
				out.append(said)
		parent = parent.get_parent()
	return out


## One page as it stands: what it is, the rectangle it was given, and every control a finger could hit.
##
## `first` is where this page's controls are numbered from, so a page's taps carry on from the board's rather than
## every part numbering from one: a picture with the numbers drawn at the controls needs one count and not a count
## per part, and the block states the parts in the order a person reads them.
static func page_lines(page: Window, first: int = 1) -> PackedStringArray:
	var lines := PackedStringArray()
	if page == null:
		return lines
	lines.append(
		"page     %s  \"%s\"  at %s size %s  ->  screen %s"
		% [
			PageLayoutScript.page_name(page),
			page.title,
			str(page.position),
			str(page.size),
			_rect_words(window_rect(page)),
		]
	)
	lines.append_array(tap_lines(page, PageLayoutScript.page_name(page), first))
	return lines


## How many `tap` lines a run of block lines holds - so that whoever is numbering the block's controls can carry the
## count on from one part to the next.
##
## It counts **lines**, and the lines are the authority on that: a second walk of the controls to count them would
## be the very thing this project spends most of its effort avoiding, a second answer to a question that already has
## one. A numbered line still begins with `tap `, so the count is unaffected by the numbering itself.
static func taps_in(lines: PackedStringArray) -> int:
	var found: int = 0
	for line: String in lines:
		if line.begins_with("tap "):
			found += 1
	return found


## Every control under a root, **stopping at a `Window`**: a page answers for its own controls, and this is
## asked once for the board's own chrome and once inside each page that is up, so the two lists never overlap
## and a page under another page is still listed as itself.
##
## `PageChrome.every_node_under` walks the whole tree instead, and deliberately: it is looking *for* the
## windows - a picker's menu is one - where this is walking round them. Internal children are read in both,
## because a `ScrollContainer`'s bars are internal and a bar is exactly what a driver needs the rectangle of.
static func _controls_under(root: Node) -> Array[Control]:
	var found: Array[Control] = []
	for child: Node in root.get_children(true):
		if child is Window:
			continue
		var control: Control = child as Control
		if control != null:
			found.append(control)
		found.append_array(_controls_under(child))
	return found


## Where a control stands in the pixels a screenshot is taken in.
static func screen_rect(control: Control) -> Rect2:
	var where: Viewport = control.get_viewport()
	if where == null:
		return Rect2()
	return _compose(where.get_screen_transform(), control.get_global_rect())


## Where a *page* stands in those same pixels.
##
## A `Window` is placed in its **parent viewport's** coordinates and not in its own, so its own transform
## would say where it is not: the rectangle is composed through the parent's transform instead. A page with
## no parent at all - one a test built and never added - is reported in its own coordinates, which is the
## only thing that is true about it.
static func window_rect(page: Window) -> Rect2:
	var rect := Rect2(page.position, page.size)
	var parent: Node = page.get_parent()
	var where: Viewport = parent.get_viewport() if parent != null else null
	if where == null:
		return rect
	return _compose(where.get_screen_transform(), rect)


## A rectangle and a point, in the words a screenshot's pixels are counted in: whole numbers, because a tap
## wants one, and `(x, y)` so that a line can be read straight off.
static func _rect_words(rect: Rect2) -> String:
	return "(%.0f, %.0f) .. (%.0f, %.0f) %0.fx%0.f px" % [
		rect.position.x,
		rect.position.y,
		rect.end.x,
		rect.end.y,
		rect.size.x,
		rect.size.y,
	]


static func _point_words(point: Vector2) -> String:
	return "(%.0f, %.0f)" % [point.x, point.y]


## A rectangle taken through a transform, both corners moved and the box that holds them handed back: a
## transform that scales may also mirror, so the two corners are put in order rather than assumed.
static func _compose(xform: Transform2D, rect: Rect2) -> Rect2:
	var corner: Vector2 = xform * (rect.position + rect.size)
	var origin: Vector2 = xform * rect.position
	return Rect2(origin.min(corner), (corner - origin).abs())


## Whether a control is one a finger could hit rather than something to read or lay out.
static func _tappable(control: Control) -> bool:
	if not drawn(control):
		return false
	for kind: String in TAPPABLE:
		if control.is_class(kind):
			return true
	return false


## What a control is called on the screen, in the words a person looking at the phone would use: a button
## says its caption, a field what it holds, a bar what it is.
static func _caption(control: Control) -> String:
	if control is Button:
		return (control as Button).text
	if control is LineEdit:
		return (control as LineEdit).text
	if control is SpinBox:
		return str((control as SpinBox).value)
	if control is OptionButton:
		return (control as OptionButton).text
	if control is ItemList:
		return "%d rows" % (control as ItemList).item_count
	if control is Label:
		return (control as Label).text
	return control.get_class()


## Whether a control's words were written by nobody here: an engine-built child is named `@SpinBoxLineEdit@133`
## and the like, and says what its parent composes - a `SpinBox` makes its field out of the value and the suffix,
## two spaces between them, so the field says `172  d` where the program wrote `172` and `d`.
##
## Its words are real on the glass and are **not** a second thing saying something: the `SpinBox` is the one
## control and the field is a part of it. So both walks that look for words leave it out - the one that reports
## what is drawn over what, where two surfaces must be two things, and the one that reports words that are
## wrong, where the text is not this program's to police. Reading it in one place is what keeps the two agreeing.
##
## **The name is the only tell, and it is a narrow one, so it is applied narrowly.** A control the program built
## for a test is named `@Button@1` by the engine too, and `get_children` deliberately reads internal children
## because a `ScrollContainer`'s bars are internal and a driver needs their rectangles - so the walk cannot use
## this, only the readings whose question is *what a control says*.
static func _the_engines_own(control: Control) -> bool:
	return String(control.name).begins_with("@")


## Every control under a node that says something a person *reads*, at the rectangle it is drawn in - in the
## pixels a screenshot is taken in, which is the space every other rectangle here is reported in too.
##
## A control whose caption is its own class name is a container, a panel or a picture: it is drawn, but there
## are no words in it for anything to be drawn over, so it is left out. This is the half of the overlap
## measurement that knows about the HUD's own furniture - a panel's caption, a button, a page's own sentence.
##
## A part the engine built is left out too: a `SpinBox`'s own field says the same number the `SpinBox` says, and
## two surfaces that share rows have to be two things. Measured on the desk, `16.0` and `16.0  h` were reported
## as sharing exactly one cell - one control, drawn once, named twice.
static func words_in(root: Node) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if root == null:
		return found
	for control: Control in _controls_under(root):
		if not drawn(control):
			continue
		if _the_engines_own(control):
			continue
		var said: String = _caption(control)
		if said.is_empty() or said == control.get_class():
			continue
		var rect: Rect2 = drawn_rect(control)
		if rect.size.x < 1.0 or rect.size.y < 1.0:
			continue
		found.append(DrawnSurfacesScript.words(said, Rect2i(rect), _surfaces_above(control)))
	return found


## A page as the two surfaces it really draws: the rectangle it occupies, and the title bar Godot draws
## **above** it, which no node owns and no layout counts.
##
## The bar's height starts as `PageChrome.chrome_above` - the theme's answer - and is converted into the same
## pixels the rectangle was composed into, because a phone draws this canvas 1.62 times as large and a 36 px
## bar is 58 px of screenshot. **That conversion is the honest part and the fragile one**: a phone's drawn
## title bar is about 71 px where the theme says 36, which is the gap `page_chrome_probe` measures on the glass
## - so this reports the bar's rectangle *beside* the theme's claim rather than trusting it to be the whole
## story. A page the theme is wrong about is still caught when its bar reaches the words it must not.
static func page_surfaces(page: Window) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if page == null:
		return found
	var placed: Rect2 = window_rect(page)
	if placed.size.x < 1.0 or placed.size.y < 1.0 or page.size.y <= 0:
		return found
	var named: String = PageLayoutScript.page_name(page)
	var above: int = roundi(float(PageChromeScript.chrome_above(page)) * (placed.size.y / float(page.size.y)))
	found.append(DrawnSurfacesScript.page(named, Rect2i(placed)))
	found.append(DrawnSurfacesScript.bar_of(named, Rect2i(placed), above))
	return found


## What is drawn and what may not share rows, said in this probe's own voice: one row when nothing meets
## anything it may not, and one row per meeting when something does. The rule and the wording of a meeting both
## belong to `DrawnSurfaces`; this only reports them.
static func meeting_lines(surfaces: Array) -> PackedStringArray:
	var lines := PackedStringArray()
	var found: Array[Dictionary] = DrawnSurfacesScript.meetings(surfaces)
	if found.is_empty():
		lines.append("overlap  %d surface(s) drawn, and nothing meets anything it may not" % surfaces.size())
		return lines
	for meeting: Dictionary in found:
		lines.append("overlap  %s" % DrawnSurfacesScript.sentence(meeting))
	return lines


## Everything under a root that is being **cut**: words scrolling inside a box, or a caption clipped by one,
## while a box around it had room to give. The rule and the wording both belong to `RoomToSpare`; this only
## walks, measures, and hands it the numbers.
##
## The measurement that matters is `_wants`. A list or a text document does not grow - it scrolls - so its own
## minimum size says nothing about what it holds; the engine keeps the honest numbers on its scroll bar, where
## `max_value` is the whole content and `page` is what is on show. The difference between them is exactly the
## amount a person is scrolling by, which is the fault, where the rectangle is merely the symptom. Everything
## else is asked what it wants with `get_minimum_size` - which for a wrapped caption is the height it needs at
## the width it was given.
##
## That is also the one thing a picture cannot settle: a box scrolled and a box clipped look the same in a
## screenshot, and only the bar knows which of the two it is.
static func crowded_lines(root: Node, scope: String) -> PackedStringArray:
	var lines := PackedStringArray()
	if root == null:
		return lines
	var items: Array = []
	for control: Control in _controls_under(root):
		if not _shows(control):
			continue
		items.append(
			{
				"name": "%s  %s  at %s"
				% [scope, _a_showing_thing(control), _point_words(screen_rect(control).position)],
				"given": control.size,
				"wanted": _wants(control),
				"around": _boxes_around(control),
			}
		)
	for fault: Dictionary in RoomToSpareScript.faults(items):
		lines.append("crowded  %s" % RoomToSpareScript.sentence(fault))
	return lines


## What a control wants to be, in the one sense that is honest for it: what it is showing plus what it is
## scrolling by, or - for something that does not scroll - the least it can be, asked of the control itself.
static func _wants(control: Control) -> Vector2:
	var over: Vector2 = _scrolling_by(control)
	if over.x > 0.0 or over.y > 0.0:
		return control.size + over
	return control.get_minimum_size()


## How much a control is scrolling by, in each direction, read off its own bars: zero for anything that has
## none, and the difference between the whole content and the visible part for anything that has them.
##
## `has_method` rather than a list of classes, because the five controls that scroll do not share a base class
## that says so, and a list here would be a second answer to a question the engine already answers.
static func _scrolling_by(control: Control) -> Vector2:
	var over := Vector2.ZERO
	if control.has_method(&"get_v_scroll_bar"):
		var down: VScrollBar = control.call(&"get_v_scroll_bar") as VScrollBar
		if down != null and down.max_value > down.page:
			over.y = down.max_value - down.page
	if control.has_method(&"get_h_scroll_bar"):
		var across: HScrollBar = control.call(&"get_h_scroll_bar") as HScrollBar
		if across != null and across.max_value > across.page:
			over.x = across.max_value - across.page
	return over


## The boxes outwards from a thing that was cut, nearest first, each with the room standing empty in it. A page
## is a box like any other and is added last: a `Window` is not a `Control` and is never reached by walking up,
## and the room a page has is much of what this question is about - "cut 200 px, and the page had 306 to give".
static func _boxes_around(control: Control) -> Array:
	var boxes: Array = []
	var parent: Node = control.get_parent()
	while parent != null:
		var box: Control = parent as Control
		if box != null and box.is_visible_in_tree():
			boxes.append({ "name": "%s (%s)" % [box.name, box.get_class()], "size": box.size, "used": _used_room(box) })
		parent = parent.get_parent()
	var page: Window = control.get_window()
	if page != null and page != control.get_viewport():
		boxes.append(
			{
				"name": "the page (%s)" % PageLayoutScript.page_name(page),
				"size": Vector2(page.size),
				"used": _used_room(page),
			}
		)
	return boxes


## How much of a box is in use: the extent of the visible controls it holds, from its own corner. Used for a
## control and for a page, which are the same question - how much of this is anything actually occupying.
##
## A box filled by a child that fills it is using all of itself, which is the answer that matters: the panel
## around the palette's own tool scroll has nothing to give, whatever its minimum size says it needs.
static func _used_room(box: Node) -> Vector2:
	var used := Vector2.ZERO
	for child: Node in box.get_children():
		var control: Control = child as Control
		if control == null or not control.is_visible_in_tree():
			continue
		used = used.max(control.position + control.size)
	return used


## Whether a control is one that shows something rather than one that lays something out.
static func _shows(control: Control) -> bool:
	if not control.is_visible_in_tree():
		return false
	for kind: String in SHOWING:
		if control.is_class(kind):
			return true
	return false


## What a thing that shows words is called on one line: a caption, a field's text, or - for something holding a
## document - how much of it there is, because a page of prose on a probe line helps nobody.
static func _a_showing_thing(control: Control) -> String:
	var named: String = "%s %s" % [control.name, control.get_class()]
	if control is TextEdit:
		return "%s (%d lines)" % [named, (control as TextEdit).get_line_count()]
	if control is RichTextLabel:
		return "%s (%d lines)" % [named, (control as RichTextLabel).get_line_count()]
	var said: String = _caption(control)
	if said.is_empty() or said == control.get_class():
		return named
	if said.length() > 60:
		return "%s \"%s...\"" % [named, said.substr(0, 60)]
	return "%s \"%s\"" % [named, said]


## Every control whose **words** are wrong in a way no rectangle can show: a note to the author left in place,
## a message a compiler would have written, a sentence where a name belongs, a caption padded by a space. The
## rules and the wording of a fault both belong to `GuiWords`; this only finds which controls are showing what
## and hands the strings over.
##
## It reads the same `_caption` the tap walk does, so a control is called what a person would call it, and it
## skips a control whose caption is its own class name - a container, a panel, a picture - because there are no
## words in one to be wrong.
static func words_lines(root: Node, scope: String) -> PackedStringArray:
	var lines := PackedStringArray()
	if root == null:
		return lines
	for control: Control in _controls_under(root):
		if not drawn(control):
			continue
		if _the_engines_own(control):
			continue
		var said: String = _caption(control)
		if said.is_empty() or said == control.get_class():
			continue
		var where: String = "%s  %s" % [scope, control.name]
		for fault: Dictionary in GuiWordsScript.faults(said, GuiWordsScript.kind_of(control), where):
			lines.append("words    %s" % GuiWordsScript.sentence(fault))
	return lines


## Where the bar above a page is **drawn**, read off the framebuffer rather than asked of the theme.
##
## Godot draws a `Window`'s title bar itself: no node carries it and nothing reports its height, so
## `PageChrome.chrome_above` answers with the theme's number - and a phone draws that bar taller than the theme
## says it is. The two are allowed to disagree, and the only thing that knows which is true is the glass, so
## this reads the column at the page's own centre, one row above its top edge, and hands back the run of colour
## found there. That run **is** the bar when nothing else of the same colour stands above the page, and is
## deliberately reported as a run rather than as a height: the front door's own body is the same theme colour
## as its title bar, so the run above it measured 78 px against a theme answer of 36, and neither number is a
## lie - they are answers to different questions. It is printed *beside* the theme's own answer, so that a
## disagreement is visible as a number rather than discovered as a fault later.
static func drawn_bar_lines(page: Window, image: Image) -> PackedStringArray:
	var lines := PackedStringArray()
	if page == null or image == null:
		return lines
	var placed: Rect2 = window_rect(page)
	var at: Dictionary = ScreenshotReaderScript.band_containing(
		image,
		int(placed.position.x + placed.size.x * 0.5),
		int(placed.position.y) - 1,
	)
	if at.is_empty():
		return lines
	lines.append(
		"drawn    %s  the run of colour above its top edge is %s, the theme says %d px"
		% [PageLayoutScript.page_name(page), ScreenshotReaderScript.sentence(at), PageChromeScript.chrome_above(page)]
	)
	return lines


## The room, counted the way every rectangle here is counted: the **screen** put through the transform of the
## top-level viewport, so that a room and a control can be put side by side on a phone, where this canvas is
## drawn 1.62 times as large.
##
## It is deliberately the *root* viewport's rectangle and not whichever viewport is handed in. A page is a
## `Window` and a viewport of its own, so asking a page for its visible rectangle answers with the page's own
## size and its own transform is the identity - and a control inside that page is reported in screen pixels, so
## the two numbers come from different spaces and every control in every page reads as off the screen. That was
## measured: the front door's own scroll container was reported 540 px past the right edge of a 520 x 540 room,
## which is its position on the screen against the page's width. The rectangle every control is measured in is
## the screen's, so the room that holds them is the screen's too.
##
## A headless run has a viewport and no screen; its own transform still answers, and a room that comes back empty
## is the rule's own case - nothing is outside a room that is not there.
static func screen_room(anywhere: Node) -> Vector2i:
	var tree: SceneTree = anywhere.get_tree() if anywhere != null else null
	var where: Viewport = tree.root if tree != null else null
	if where == null:
		return Vector2i.ZERO
	return Vector2i(_compose(where.get_screen_transform(), Rect2(Vector2.ZERO, where.get_visible_rect().size)).size)


## Controls the room cannot hold: something drawn past the edge of the screen, which is the one fault a person
## can do nothing about, and the one comparison no instrument here had made - every other measurement is a
## control against another control, never against the room the two of them are standing in.
##
## The phone's own view buttons were drawn at x=1860 on a 1080-wide screen, entirely off it, and that was found
## by eye. The walk behind `row_lines` had the numbers all along - it printed each child's position - and
## nothing ever said the answer out loud.
##
## A control something is **clipping** is left alone, because for one of those being past the edge is the design:
## a tool in the palette's scroll stands above the visible part of the scroller on purpose, and so does a page's
## contents in the scroller `PageChrome` gives an over-tall page. What is left is a control nothing is clipping
## and the room cannot hold.
static func offscreen_lines(root: Node, scope: String) -> PackedStringArray:
	var lines := PackedStringArray()
	var room: Vector2i = screen_room(root)
	if root == null or room.x <= 0 or room.y <= 0:
		return lines
	var items: Array = []
	for control: Control in _controls_under(root):
		if not _showing_at_all(control):
			continue
		var rect: Rect2 = screen_rect(control)
		if rect.size.x < 1.0 or rect.size.y < 1.0:
			continue
		items.append({ "name": "%s  %s" % [scope, _a_showing_thing(control)], "rect": Rect2i(rect), "room": room })
	for fault: Dictionary in InViewScript.faults(items):
		lines.append("offscreen  %s" % InViewScript.sentence(fault))
	return lines


## Every box a tap could stop at inside **one part** of the screen - the board, or one page - in the order they
## are drawn, which is the whole of what `Topmost` needs to answer with.
##
## This is the walk the block's own `reach` lines have always made, given a name so that asking about **one
## point** and reporting every button cannot come to disagree about what is at a place: a control the mouse
## passes through is not handed over at all, a control covering the whole room is the screen's own backdrop
## rather than a thing in the way, and the name on each box is the one the block prints.
static func tap_boxes(root: Node, scope: String, room: Vector2i) -> Array:
	var boxes: Array = []
	for control: Control in _controls_under(root):
		if not _a_tap_stops_here(control):
			continue
		var rect: Rect2 = screen_rect(control)
		if rect.size.x < 1.0 or rect.size.y < 1.0:
			continue
		# A control covering the whole room is the screen's own backdrop, stopping the mouse on purpose
		# while a person is being asked something. It is not a thing that got in the way. **The same call
		# `plates_in` makes**, so the two answers about what the backdrop is cannot drift apart - which they
		# had, because this one was given the room and that one read a viewport.
		if _covers_the_room(rect, room):
			continue
		boxes.append({ "name": _press_name(scope, control), "rect": Rect2i(rect), "enabled": _answers_a_tap(control) })
	return boxes


## **What a tap at a point would reach, and the program's own name for it** - the question a person asks when
## they mean "that one, there" and the answer they can then say out loud.
##
## The parts are asked **each against its own furniture**, exactly as the `reach` lines are: the board is what a
## tap standing on the board meets, and a page over it is what a tap on the page meets. A point that reaches
## something in both is answered by the page, because the page is drawn later - and the answer says which part it
## was on, so the board's palette and a page's own list cannot be confused for one another.
##
## Nothing is measured a second time: the boxes, their names and their rectangles are `tap_boxes`', and the rule
## that picks the winner out of them is `Topmost`'s. A point where nothing takes the mouse says so rather than
## answering with an empty line.
static func what_is_at(board: Node, pages: Array, board_scope: String, point: Vector2i) -> String:
	var parts: Array = []
	if board != null:
		parts.append({ "root": board, "scope": board_scope })
	for node: Node in pages:
		var page: Window = node as Window
		if page != null and page.visible:
			parts.append({ "root": page, "scope": PageLayoutScript.page_name(page) })
	if parts.is_empty():
		return "there is nothing on the screen to ask about"
	var room: Vector2i = screen_room(board if board != null else parts[0]["root"])
	var reached: Dictionary = { }
	# Named `standing_on` and not `on`: this class already has an `on()` - the gate that says whether a build
	# speaks at all - and a local shadowing it is a reload error the engine reports on every run.
	var standing_on: String = ""
	for part: Dictionary in parts:
		var top: Dictionary = TopmostScript.at(point, tap_boxes(part["root"], part["scope"], room))
		if top.is_empty():
			continue
		reached = top
		standing_on = String(part["scope"])
	if reached.is_empty():
		return (
			"nothing takes a tap at (%d, %d): the control there passes the mouse through, or nothing is there"
			% [point.x, point.y]
		)
	var rect: Rect2i = reached["rect"]
	var said: String = "%s  on %s  screen (%d, %d) .. (%d, %d)  %d x %d px" % [
		String(reached["name"]),
		standing_on,
		rect.position.x,
		rect.position.y,
		rect.end.x,
		rect.end.y,
		rect.size.x,
		rect.size.y,
	]
	if not bool(reached["enabled"]):
		return said + "  - and it is switched off, so a tap there does nothing"
	return said


## Every button the GUI is showing and whether a tap on it would reach it: the one question a driver asks when a
## click does nothing at all, and the one nothing here could answer. A button drawn under a page is perfectly
## sized, perfectly worded, and unreachable.
##
## Two things are left out of that, and the first version got both wrong, in opposite directions, on the very
## first run. Each part is asked about **its own furniture** - the board's buttons against what the board draws
## over them, a page's against what that page draws over them - because a page standing over the board is what a
## page *is*, so the board being unreachable behind one is the design rather than a fault. And a control that
## covers the **whole room** is the screen's own backdrop rather than a thing in the way: `Hud` draws a full-rect
## `ColorRect` that stops the mouse while a person has not yet said what they came here for, which is precisely
## its job. Handing every rectangle of every part over together reported ten lines about that backdrop.
##
## What is left is what is worth reporting: a control only another control of the same screen's making could have
## got in the way of, and a button that is drawn where it can be seen and still would not be reached.
##
## A control the mouse passes through - a plain panel, a spacer - is not handed over at all, because a tap never
## stops there; a button switched off *is* handed over, so that the answer can say the tap did reach it and then
## nothing happened.
##
## The strip above a page is deliberately not asked about: Godot draws that as the page's own title bar, which is
## a bar rather than a control, and `DrawnSurfaces` already reports it against the words it must not cover.
##
## **The findings are data and the lines are a rendering of it**, because a caller has to be able to weigh the
## two kinds apart. A button something else stands over cannot be pressed by anybody; a button that is there and
## switched off is the design - a state button is dead until its field holds something - so a caller that counts
## faults counts the first and names the second. Both are the same walk, so neither reader can come to a
## different answer about what is at a place.
static func reach_findings(board: Node, pages: Array, board_scope: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var parts: Array = []
	if board != null:
		parts.append({ "root": board, "scope": board_scope })
	for node: Node in pages:
		var page: Window = node as Window
		if page != null and page.visible:
			parts.append({ "root": page, "scope": PageLayoutScript.page_name(page) })
	if parts.is_empty():
		return found
	var first: Node = parts[0]["root"]
	var room: Vector2i = screen_room(board if board != null else first)
	for part: Dictionary in parts:
		var root: Node = part["root"]
		var scope: String = part["scope"]
		var boxes: Array = tap_boxes(root, scope, room)
		for control: Control in _controls_under(root):
			if not _a_tap_stops_here(control) or not (control is BaseButton):
				continue
			var rect: Rect2 = screen_rect(control)
			if rect.size.x < 1.0 or rect.size.y < 1.0:
				continue
			# A button the room cannot hold belongs to `offscreen` and would only be named a second time here: a
			# tap cannot be aimed at a control nobody can see, and the aiming is what this asks about.
			if not InViewScript.fits(Rect2i(rect), room):
				continue
			var wanted: String = _press_name(scope, control)
			var gap: Dictionary = TopmostScript.mistake(TopmostScript.middle(Rect2i(rect)), boxes, wanted)
			if gap.is_empty():
				continue
			found.append(
				{ "line": "reach    %s" % TopmostScript.sentence(gap), "switched_off": bool(gap["switched_off"]) }
			)
	return found


## The same findings as the block's own `reach` lines, in the order the parts are asked.
static func reach_lines(board: Node, pages: Array, board_scope: String) -> PackedStringArray:
	var lines := PackedStringArray()
	for one: Dictionary in reach_findings(board, pages, board_scope):
		lines.append(String(one["line"]))
	return lines


## Words a person cannot read against the colour behind them.
##
## Nothing else here asks about colour at all: a rectangle knows its size and a caption knows its words, and the
## two together can be perfectly right while the words are the same shade as the plate they sit on. Only a pair
## where a program can *know* both colours is judged - a button's own plate fills itself, and a word-bearing
## control standing on a panel or a plain filled rectangle has a paper that can be read. A caption drawn straight
## onto the plan has no paper a program can find, and is left alone rather than judged against a guess.
static func contrast_lines(root: Node, scope: String) -> PackedStringArray:
	var lines := PackedStringArray()
	if root == null:
		return lines
	var items: Array = []
	for control: Control in _controls_under(root):
		if not _showing_at_all(control):
			continue
		if _caption(control).is_empty():
			continue
		var ink: Variant = _ink_of(control)
		var paper: Variant = _paper_behind(control)
		if ink == null or paper == null:
			continue
		items.append({ "name": "%s  %s" % [scope, _a_showing_thing(control)], "ink": ink, "paper": paper })
	for fault: Dictionary in ContrastScript.faults(items):
		lines.append("contrast  %s" % ContrastScript.sentence(fault))
	return lines


## Words needing more room than the box they are drawn in, which is the one thing about a caption a rectangle
## cannot say: a box 523 px wide holding words that want 754 px looks exactly like a box that fits them, and the
## phone's own foot line read "Pinch: zoo" where the program had written "Pinch: zoom".
##
## Two kinds of control are left out. One that **wraps** its words has cut nothing: the words are all there, on
## another line, and whether there is room for that line is `RoomToSpare`'s question rather than this one. A
## `LineEdit` scrolls its own text, which is an editor doing its job.
##
## **Both widths are in the control's own pixels.** The room the words want is measured here, with the font the
## control draws at and at its own size, because that is a question about the theme and no rectangle can answer
## it - `get_minimum_size()` cannot either, since a `Label` set to clip reports the room it was *given*. Reading
## the box in the same units as the words keeps the two from being compared across a scale, which is the mistake
## the phone's own band cost once already.
static func clipped_lines(root: Node, scope: String) -> PackedStringArray:
	var lines := PackedStringArray()
	if root == null:
		return lines
	var items: Array = []
	for control: Control in _controls_under(root):
		if not (control is Label or control is BaseButton):
			continue
		if not _showing_at_all(control):
			continue
		if _wraps_its_words(control):
			continue
		var said: String = _caption(control)
		if said.is_empty():
			continue
		var wanted: float = _words_width(control, said)
		if wanted <= 0.0 or control.size.x < 1.0:
			continue
		items.append(
			{
				"name": "%s  %s" % [scope, _a_showing_thing(control)],
				"said": said,
				"wanted": wanted,
				"given": control.size.x,
			}
		)
	for fault: Dictionary in ClippedWordsScript.faults(items):
		lines.append("clipped   %s" % ClippedWordsScript.sentence(fault))
	return lines


## How wide the longest of a control's lines of words is, at the font and size that control draws them with. A
## button's caption is deliberately two rows - the tool over its shortcut key - so the widest row is the one that
## has to fit, and the whole caption measured as one line would name every two-line button in the program.
static func _words_width(control: Control, said: String) -> float:
	var font: Font = control.get_theme_font(&"font")
	if font == null:
		return 0.0
	var size: int = control.get_theme_font_size(&"font_size")
	var widest: float = 0.0
	for line: String in said.split("\n"):
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x)
	return widest


## Whether a control puts its words on another line rather than cutting them off, which is the difference between
## a caption that is short of room and a caption that has lost a word.
static func _wraps_its_words(control: Control) -> bool:
	var label := control as Label
	if label != null:
		return label.autowrap_mode != TextServer.AUTOWRAP_OFF
	var button := control as Button
	if button != null:
		return button.autowrap_mode != TextServer.AUTOWRAP_OFF
	return false


## Targets a finger would be asked to hit and could not, which is a question only while a finger is the thing
## being served - so the caller asks it only then, and the measurement is in screen pixels, so the phone's own
## scaling is already in the number.
##
## A control the room cannot hold at all is left out: nobody can press what nobody can see, and `offscreen` has
## already named it. This asks only about what a person can see and still could not hit.
##
## `least` is the shorter side a target should have, in screen pixels, and 0 uses this project's own floor. A
## caller measuring a window that is not a phone's shape - `tools/phone_gui_probe` - states the floor the device
## it is standing in for would have, so that the answer is that device's rather than this window's.
static func small_lines(root: Node, scope: String, least: int = 0) -> PackedStringArray:
	var lines := PackedStringArray()
	if not _a_real_screen():
		return lines
	var room: Vector2i = screen_room(root)
	if root == null or room.x <= 0 or room.y <= 0:
		return lines
	var items: Array = []
	for item: Dictionary in _targets_under(root, scope):
		if not InViewScript.fits(item["rect"] as Rect2i, room):
			continue
		items.append(item)
	var floor_size: int = TouchTargetScript.LEAST if least <= 0 else least
	for fault: Dictionary in TouchTargetScript.faults(items, floor_size):
		lines.append("small     %s" % TouchTargetScript.sentence(fault))
	return lines


## Two things of one kind drawing in exactly one rectangle, so that only the one drawn later is ever seen.
static func twin_lines(root: Node, scope: String) -> PackedStringArray:
	var lines := PackedStringArray()
	if root == null:
		return lines
	var items: Array = []
	for control: Control in _controls_under(root):
		if not _showing_at_all(control):
			continue
		var rect: Rect2 = screen_rect(control)
		if rect.size.x < 1.0 or rect.size.y < 1.0:
			continue
		items.append(
			{ "name": "%s  %s" % [scope, _a_showing_thing(control)], "kind": control.get_class(), "rect": Rect2i(rect) }
		)
	for fault: Dictionary in StackedScript.faults(items):
		lines.append("twins     %s" % StackedScript.sentence(fault))
	return lines


## Pictures being shown with nothing in them: no texture at all, or a texture that is one colour from corner to
## corner. A texture whose picture cannot be read - one held in an atlas has none of its own - is passed over
## rather than called empty, because not being able to read a thing is not the same as the thing being blank.
static func blank_lines(root: Node, scope: String) -> PackedStringArray:
	var lines := PackedStringArray()
	if root == null:
		return lines
	var items: Array = []
	for control: Control in _controls_under(root):
		var shown := control as TextureRect
		if shown == null or not _showing_at_all(shown):
			continue
		if shown.size.x < 1.0 or shown.size.y < 1.0:
			continue
		if shown.texture == null:
			items.append({ "name": "%s  %s" % [scope, shown.name], "image": null })
			continue
		var image: Image = shown.texture.get_image()
		if image == null:
			continue
		items.append({ "name": "%s  %s" % [scope, shown.name], "image": image })
	for fault: Dictionary in BlankPictureScript.faults(items):
		lines.append("blank     %s" % BlankPictureScript.sentence(fault))
	return lines


## Whole pages the room cannot hold - the class the phone's camera page belonged to, and the one no check on
## the controls inside a page can reach, because every control in it may be perfectly placed in a page that has
## itself been put past the edge of the screen.
static func page_edge_lines(pages: Array) -> PackedStringArray:
	var lines := PackedStringArray()
	var up: Array[Window] = []
	for node: Node in pages:
		var page := node as Window
		if page != null and page.visible:
			up.append(page)
	if up.is_empty():
		return lines
	var room: Vector2i = screen_room(up[0])
	if room.x <= 0 or room.y <= 0:
		return lines
	var items: Array = []
	for page: Window in up:
		var rect: Rect2 = window_rect(page)
		if rect.size.x < 1.0 or rect.size.y < 1.0:
			continue
		items.append({ "name": "the page (%s)" % PageLayoutScript.page_name(page), "rect": Rect2i(rect), "room": room })
	for fault: Dictionary in InViewScript.faults(items):
		lines.append("page-edge %s" % InViewScript.sentence(fault))
	return lines


## What every caption the GUI is showing says, keyed by where it stands - one reading of the screen's words, to
## be taken a second time after an action and compared by `CaptionLedger`. This is the half of a stale caption
## that can be had without knowing what a page promised: the taking of the reading, not the judging of it.
static func captions(root: Node) -> Dictionary:
	var said: Dictionary = { }
	if root == null:
		return said
	for control: Control in _controls_under(root):
		if not _showing_at_all(control):
			continue
		var words: String = _caption(control)
		if words.is_empty():
			continue
		said[String(control.get_path())] = words
	return said


## The colour a control's own words are drawn in, or null where the control has no words of its own to colour.
## Only the kinds that certainly have that theme item are asked: asking a control for a theme colour it does not
## have is an engine error rather than an empty answer.
static func _ink_of(control: Control) -> Variant:
	if control is Label or control is BaseButton or control is LineEdit:
		return control.get_theme_color(&"font_color")
	return null


## The colour behind a control's words, where a program can know it: a button fills its own plate, and otherwise
## it is the nearest ancestor that fills a rectangle with a colour - a panel, or a plain `ColorRect`. Where there
## is none, nothing is said: the paper is whatever the drawing under it happens to be.
static func _paper_behind(control: Control) -> Variant:
	var button := control as BaseButton
	if button != null:
		var own := button.get_theme_stylebox(&"normal") as StyleBoxFlat
		if own != null:
			return own.bg_color
	var parent: Node = control.get_parent()
	while parent != null:
		if parent is Panel or parent is PanelContainer:
			var style := (parent as Control).get_theme_stylebox(&"panel") as StyleBoxFlat
			if style != null:
				return style.bg_color
		var plate := parent as ColorRect
		if plate != null:
			return plate.color
		parent = parent.get_parent()
	return null


## Targets a finger could not tell apart from their neighbours, which is a question about the pairs a person has
## to choose between rather than about any one target's size.
static func close_lines(root: Node, scope: String, least: int = SpacingScript.LEAST) -> PackedStringArray:
	var lines := PackedStringArray()
	if root == null or not _a_real_screen():
		return lines
	for fault: Dictionary in SpacingScript.faults(_targets_under(root, scope), least):
		lines.append("close     %s" % SpacingScript.sentence(fault))
	return lines


## Targets standing in a band the device keeps for itself: the swipe up from the bottom, the swipe in from the
## side, the notification shade at the top. This reads the platform itself, and only where the program has said
## the room really is a phone's - `PhoneHud.zooming_here` is a finger *and* a small screen, so a monitor's promise
## is never applied to a window standing on it. The room handed to `PhoneHud.cutout_here` is the one *this*
## measures in, because the insets come back in the units of the room they are asked about and two spaces
## compared against each other is how the phone read 91 px where the truth was 83.
static func unsafe_lines(root: Node, scope: String) -> PackedStringArray:
	var lines := PackedStringArray()
	var safe: Rect2i = _the_bands_kept(root)
	if root == null or safe.size.x <= 0 or safe.size.y <= 0:
		return lines
	var items: Array = []
	for item: Dictionary in _targets_under(root, scope):
		items.append({ "name": item["name"], "rect": item["rect"], "safe": safe })
	for fault: Dictionary in SafeAreaScript.faults(items):
		lines.append("unsafe    %s" % SafeAreaScript.sentence(fault))
	return lines


## Targets whose **middle** is in a band the device keeps, which is the sharper of the two questions about a
## band: a finger does not land where a control reaches, it lands where it was aimed. The phone's own reading is
## what taught it - the board's three view buttons each reach 81 px into the top band, and it is their middles at
## y=68 being inside that band which hands the press to the system. A large button merely overlapping an edge,
## whose middle and most of its area are perfectly reachable, is left alone by this and named by `unsafe`.
static func middle_lines(root: Node, scope: String) -> PackedStringArray:
	var lines := PackedStringArray()
	var safe: Rect2i = _the_bands_kept(root)
	if root == null or safe.size.x <= 0 or safe.size.y <= 0:
		return lines
	var items: Array = []
	for item: Dictionary in _targets_under(root, scope):
		items.append({ "name": item["name"], "rect": item["rect"], "safe": safe })
	for fault: Dictionary in SafeAreaScript.centre_faults(items):
		lines.append("middle    %s" % SafeAreaScript.centre_sentence(fault))
	return lines


## The area the device has promised to leave alone, in the screen pixels every rectangle here is counted in - or
## an empty rectangle where there is no such promise, which is a desk or a device that has said nothing. It reads
## the platform itself and only where `PhoneHud.zooming_here` says the room really is a phone's, so a monitor's
## promise is never applied to a window standing on it. One reading serves both questions about a band, so that
## the two cannot end up being asked about two different areas.
static func _the_bands_kept(root: Node) -> Rect2i:
	if root == null:
		return Rect2i()
	var room: Vector2i = screen_room(root)
	if room.x <= 0 or room.y <= 0:
		return Rect2i()
	# **The device is asked in the space this measures in.** `PhoneHud.cutout_here` answers in the units of the
	# room it is handed, and everything here is in the screen pixels `screen_rect` produced. Handing it the
	# viewport's own logical size instead, which is what the HUD has to hand, compares a phone's band with a
	# rectangle drawn in another space, and the phone read "91 px into the top band" where the truth was 81.
	if not PhoneHudScript.zooming_here():
		return Rect2i()
	var insets: Vector4i = PhoneHudScript.cutout_here(room)
	if insets == Vector4i.ZERO:
		return Rect2i()
	return Rect2i(insets.x, insets.y, room.x - insets.x - insets.z, room.y - insets.y - insets.w)


## A row stated in the layout's pixels, brought into the screen's - or 0 where either is unknown.
##
## This is the arithmetic and nothing else, so it can be held down without a phone: the A16W held upright states
## a 107 px row, a 1185 px room and a 1080 px screen, and 107 x 1080 / 1185 is 97 - which is exactly the width
## the `Fit` button came back with once `PhoneHud` gave it the row, and exactly the width the floor must not
## exceed or it calls a target that meets the row short.
##
## Truncated, not rounded: the row is a "no less than", so rounding it up would invent a one-pixel shortfall for
## a target that meets it, while a real shortfall of tens of pixels is untouched either way.
static func floor_in_screen_px(row: float, room: Vector2i, laid: Vector2) -> int:
	if row <= 0.0 or laid.x <= 0.0 or room.x <= 0:
		return 0
	return int(row * (float(room.x) / laid.x))


## The row a finger needs, **in the pixels the rectangles here are measured in**.
##
## **The floor and the rectangle must be in one space**, which is the lesson this project keeps paying for. The
## rectangles come from `screen_rect`, which composes the layout through the viewport's screen transform, so a
## phone draws them at `canvas_scale` of their layout size - 0.91 of it on the A16W held upright, where a 107 px
## layout row arrives as 97 px of screen. `PhoneHud.row_height` answers in the layout's own pixels, so handing it
## over unchanged compares a floor of 107 with a target of 97 and **calls every button on the screen ten pixels
## short**. Measured: the very build that fixed the `Fit` button's width read all three view buttons as 10 px
## short of a floor they now meet exactly.
##
## The ratio is the room's, not a number anybody states: the screen the probe measures in over the room the layout
## was given. It is truncated rather than rounded, because the floor is a "no less than" - rounding it *up* would
## invent a one-pixel shortfall for a target that meets the row - and a real shortfall of tens of pixels is not
## touched by that at all.
static func finger_floor(root: Node) -> int:
	if root == null or not PhoneHudScript.on_a_finger_here():
		return 0
	var viewport: Viewport = root.get_viewport()
	if viewport == null:
		return 0
	var laid: Vector2 = Vector2(viewport.get_visible_rect().size)
	var room: Vector2i = screen_room(root)
	if laid.x <= 0.0 or room.x <= 0:
		return 0
	var window: Window = root.get_window()
	var scale: float = PhoneHudScript.canvas_scale(window) if window != null else 0.0
	var row: float = PhoneHudScript.row_height(scale, PhoneHudScript.dpi())
	if row <= 0.0:
		return 0
	return int(row * (float(room.x) / laid.x))


## The words a block uses for the room it was taken in, in the one place that also writes them.
const ROOM_MARK := "room     viewport=("

## Where the `room` line's **screen** figure begins: the display's own pixels, which is the space a block's `tap`
## centres are published in and so the space a tap is a place in. See `read_screen_line`.
const SCREEN_MARK := "native=("

## Where the `device` line's **density** begins: the glass's own answer in pixels per logical inch, which is the
## number a phone build is developed against and the one that goes stale in a fixture. See `read_device_density`.
const DENSITY_MARK := "dpi="

## Where that same line's **scale** begins: the screen's pixels per logical one, this way up. The leading space is
## part of the mark because `scale=` on its own could be a word in another line's prose.
const SCALE_MARK := " scale="

## The room a block was taken in, read back out of the block's own line - or a room of no size where the line is
## not there.
##
## **Why this exists:** a centre is only where a finger should land *in the room it was measured in*, and the
## device turns under the program. A tap aimed from a portrait block at a landscape screen reaches nothing at all
## - measured, a centre at y 1654 on a 1080-tall screen, and the run that sent it had to be wondered about. The
## format is the probe's own, and it is read here rather than somewhere else so that the reader and the writer
## cannot come apart.
##
## The marker is searched for rather than anchored to, because the same block arrives both as the probe wrote it
## and behind the `PROBE ` a log line carries.


## **The screen's own pixels, which is the space a block's `tap` centres are published in.** The `room` line
## carries both figures - `room     viewport=(1444, 666) native=(2340, 1080)` - and they are not the same space:
## the viewport is the logical room a page is laid out in, and on the A16W the screen is 1.62 times larger. A tap
## is a place on the glass, so it is measured against this one. A centre read against the viewport instead called
## a press that had plainly landed a miss (2026-11-17).
##
## Read here, beside the writer and beside its sibling above, for the reason that comment gives.
static func read_screen_line(text: String) -> Vector2i:
	return _a_pair_after(text, SCREEN_MARK)


## The **room** a block was taken in - the viewport a page is laid out in, and the one thing a turn changes on a screen
## that publishes nothing else. Read here beside the writer, for the same reason as its siblings.
static func read_room_line(text: String) -> Vector2i:
	return _a_pair_after(text, ROOM_MARK)


## Where the `row` line that says which view is up names itself: the top bar's own mode label, whose words are the
## program's own name for the view - `2D PLAN` in the plan, `3D OVERHEAD` from above.
const VIEW_MARK := "ModeLabel"


## The view a block was taken in, in the program's own words, read off the `row` line that publishes it - or nothing
## when the block names none.
##
## Read beside the writer, for the reason the reader above is: `row_lines` writes the line and the words are the
## label's own text, so a second way of naming a view cannot appear here. A controller that relaunches the program
## changes the view under a person's hands - a program that has just started is in 3D overhead whatever view was in
## use - and this is the only copy of what was there before.
static func read_view_line(text: String) -> String:
	for line: String in text.split("\n"):
		if not line.contains(VIEW_MARK):
			continue
		var last: int = line.rfind("\"")
		if last < 0:
			continue
		var first: int = line.rfind("\"", last - 1)
		if first < 0:
			continue
		return line.substr(first + 1, last - first - 1)
	return ""


## Where the `insets` line's **display** half begins: the band the display itself reports, in the display's own pixels.
## The line carries two bands and this is only one of them - the `room` half is that band's share of the room the bar
## is laid out in, which is a different number in a different space.
const BAND_MARK := "display l="


## The band the block's `insets` line says **the display** reports, as (left, top, right, bottom) - all zeros when the
## block names none, so a missing line is no reading rather than a reading of nothing.
##
## What is read back is the program's own answer (`PhoneHud.band_as_reported`), and that is the whole point: a tool
## setting this beside what the phone says about itself has to start from what the program actually answered, not from
## what the tool thinks it ought to have answered.
##
## Read here, beside the marker that writes it, for the same reason as its siblings above.
static func read_display_band_line(text: String) -> Vector4i:
	for raw: String in text.split("\n"):
		var line: String = raw.strip_edges()
		# **The line is read field by field.** It carries more than one band - the room's share, the display's whole
		# band, and what the system bars alone take - and each is its own run of `name l=0 t=0 r=0 b=0` after three
		# spaces. Reading to the end of the line instead puts the *next* field's numbers in this one's fourth place.
		for field: String in line.split("   "):
			var at: int = field.find(BAND_MARK)
			if at < 0:
				continue
			# `display l=0 t=0 r=0 b=0`: the four letters are the field's own separators, so the shape is read back
			# with one replacement rather than a second walk over the numbers.
			var tail: String = field.substr(at + BAND_MARK.length())
			tail = tail.replace(" t=", ",").replace(" r=", ",").replace(" b=", ",")
			var parts: PackedStringArray = tail.split(",")
			if parts.size() < 4:
				continue
			return Vector4i(
				parts[0].strip_edges().to_int(),
				parts[1].strip_edges().to_int(),
				parts[2].strip_edges().to_int(),
				parts[3].strip_edges().to_int(),
			)
	return Vector4i.ZERO


## The **density** the block's `device` line states for the glass this program is running on: the device's own
## answer, in pixels per logical inch.
##
## **Why this exists.** The numbers a phone is developed against get written down - a fixture in a tool, a constant
## in a test - and a written number goes stale the moment the device does. Three test fixtures carried
## `PHONE_DPI := 384.6`, an estimate from the first draft, while the A16W's own glass reports **450.0** - which is
## a fixture pinning a phone nobody has, and no desk test can say so, because a desk has no phone to disagree with.
##
## Read here beside the writer (`device_lines`) and beside its siblings either side, for the reason those comments
## give: the reader and the writer of one line are one thing, and a second reader is the defect this project works
## hardest to avoid. A line that is not there answers `0.0` - **no reading rather than a reading of nothing**,
## which is what lets a caller say it has nothing to check against instead of comparing with zero.
static func read_device_density(text: String) -> float:
	return _a_number_after(text, DENSITY_MARK)


## The **scale** that same line states - the screen's own pixels per logical one, this way up. Portrait and
## landscape answer differently on a phone (0.91 and 1.62 on the A16W), which is why a block, taken one way up,
## can only ever judge one of the two: `tools/phone_touch_pass.gd` says so where it makes that judgement.
static func read_device_scale(text: String) -> float:
	return _a_number_after(text, SCALE_MARK)


## The number a marker is followed by, or `0.0` when no line carries one - the same shape as `_a_pair_after` one
## figure down, and the same rule about a miss.
##
## The rest of the line is handed to `String.to_float`, which reads a number only where one begins and stops at the
## first character that is not part of it: `450.0 scale=1.62 shape=lying` reads 450.0, so no bracket is needed to
## end the figure, and `Vector2i(1080, 2340)` reads nothing rather than a 0 that could be compared with a phone's.
static func _a_number_after(text: String, mark: String) -> float:
	for raw: String in text.split("\n"):
		var line: String = raw.strip_edges()
		var at: int = line.find(mark)
		if at < 0:
			continue
		return line.substr(at + mark.length()).to_float()
	return 0.0


## The two numbers inside the brackets a marker is followed by, or `Vector2i.ZERO` when no line carries them.
##
## **One walk for both figures on the `room` line**, since the pair after a marker is the same shape whichever
## figure it is; a second copy of this loop is the kind of thing this project spends the most effort avoiding. An
## unreadable line is no reading rather than a reading of nothing, which is why every miss returns the zero.
static func _a_pair_after(text: String, mark: String) -> Vector2i:
	for raw: String in text.split("\n"):
		var line: String = raw.strip_edges()
		var at: int = line.find(mark)
		if at < 0:
			continue
		var from: int = at + mark.length()
		var shut: int = line.find(")", from)
		if shut < 0:
			continue
		var parts: PackedStringArray = line.substr(from, shut - from).split(",")
		if parts.size() != 2:
			continue
		return Vector2i(int(parts[0].strip_edges()), int(parts[1].strip_edges()))
	return Vector2i.ZERO


## Whether there is a screen to measure in at all.
##
## **A floor counted in pixels needs a screen that has pixels.** Two kinds of question are asked of a rectangle
## here and only one of them survives the screen being absent. "Do these two rectangles overlap", "does this page
## hang off the room" - those compare a shape with a shape, so an engine that scales both by the same amount
## changes neither answer, and they may be asked anywhere. "Is this target 44 px across" is an *absolute* number:
## measured in a headless run, whose dummy display reports a 64 x 64 window with the canvas drawn at 0.04, a
## 109 x 50 button measures 4 x 2 px and every control in the program is named for a fault nobody could have.
## That is exactly what this guard was written for: it was found by a test asserting a button's own width and
## reading back two pixels of it.
##
## The same two questions the framebuffer needs the same answer to - a headless run has no picture either - and
## this is the guard `DisplayServer` agrees with on both.
static func _a_real_screen() -> bool:
	return DisplayServer.get_name() != "headless"


## Words the screen is not big enough to read, judged against the floor the program itself states for the device
## the caller names - and nothing at all for a device that has not said what it is, which is every desk.
static func tiny_lines(root: Node, scope: String, scale: float, density: float) -> PackedStringArray:
	var lines := PackedStringArray()
	if root == null or PhoneHudScript.font_size(scale, density) <= 0:
		return lines
	var items: Array = []
	for control: Control in _controls_under(root):
		if not _showing_at_all(control):
			continue
		if _caption(control).is_empty():
			continue
		if not (control is Label or control is BaseButton or control is LineEdit):
			continue
		items.append(
			{
				"name": "%s  %s" % [scope, _a_showing_thing(control)],
				"font": control.get_theme_font_size(&"font_size"),
				"scale": scale,
				"density": density,
			}
		)
	for fault: Dictionary in LegibilityScript.faults(items):
		lines.append("tiny      %s" % LegibilityScript.sentence(fault))
	return lines


## The controls a finger is meant to press and nowhere else: a plate a button stands on is not a target, and a
## control switched off still is one, because the answer a person gets from it - nothing - is worth knowing was
## reached. The words are carried on every one for the same reason `small` carries them: a reader has to know
## which control a line is about.
static func _targets_under(root: Node, scope: String) -> Array:
	var items: Array = []
	for control: Control in _controls_under(root):
		if not _a_tap_stops_here(control):
			continue
		# **A part the engine built is not a target of its own.** A `SpinBox`'s field is a `LineEdit`, so it
		# would be reported beside the `SpinBox` as a second target in the same place: 68 px wide where the
		# `SpinBox` is 87, four pixels from the next row where the `SpinBox` is four from it, and one control's
		# size counted twice over. The `SpinBox` is what a finger presses; the field is its face. Measured on the
		# desk's finger pass: `small` named 15 things and `close` 10 pairs before this, and 10 and 5 after, with
		# every `@SpinBoxLineEdit@…` gone from both - and the real four-pixel pair of `StillSize` and
		# `RenderStill`, which are two different controls, still named.
		if _the_engines_own(control):
			continue
		if not (control is BaseButton or control is LineEdit):
			continue
		var rect: Rect2 = screen_rect(control)
		if rect.size.x < 1.0 or rect.size.y < 1.0:
			continue
		items.append({ "name": _press_name(scope, control), "rect": Rect2i(rect) })
	return items


## Whether a thing is on the screen at all rather than scrolled above the visible part of a box: visible in the
## tree, and nothing above it clipping it.
static func _showing_at_all(control: Control) -> bool:
	return control.is_visible_in_tree() and not _clipped(control)


## Whether something above a control is clipping it, which makes where it stands the design's choice rather than
## a fault. Only a `Control` ancestor counts: a `Window` clips its own children by its nature, and that is not
## this question - a page's control can still be drawn past the edge of the screen.
static func _clipped(control: Control) -> bool:
	var parent: Node = control.get_parent()
	while parent != null:
		var box: Control = parent as Control
		if box != null and box.clip_contents:
			return true
		parent = parent.get_parent()
	return false


## Whether a box above a control clips it **out of the picture**, and the part that is left showing.
##
## This is the sharper half of `_clipped`, and the two answer different questions on purpose. `_clipped` asks
## whether anything above a control clips at all - which is what `InView` needs, because for a control in a
## scroller being past the edge is the design and the question there is whether the room can hold it. This asks
## whether the control is outside what the clipping box actually shows, which is what anything about what is
## *drawn* needs: a `ScrollContainer` draws the part of its child standing inside it and clips the rest away, so
## a control below a scroller's foot is **not on the glass at all** - it is reached by scrolling.
##
## Measured on the desk: the palette's own column is 924 px tall inside a 768 px box, so `Place`, `Stop` and the
## plant list's caption `130 species.` stand below the scroller's foot. They are drawn nowhere, and were reported
## as sharing rows with the foot line - a fault nobody could see, in the probe's own `overlap` lines and in the
## tap list a driver follows. The rectangle handed back is the part that *is* drawn, so a control half in and
## half out is compared as the half a person can see.
static func drawn_rect(control: Control) -> Rect2:
	var inside: Rect2 = screen_rect(control)
	var parent: Node = control.get_parent()
	while parent != null:
		var box: Control = parent as Control
		if box != null and box.clip_contents:
			var shown: Rect2 = screen_rect(box)
			inside = inside.intersection(shown)
			# **Empty, and not "smaller than a pixel".** A floor counted in pixels needs a screen to count it on,
			# and this is asked by a headless runner too, whose dummy display scales every rectangle by 0.04: two
			# thirds of a control showing was 0.8 "pixels" there and read as nothing at all. Whether anything of a
			# control is in the picture is a question of two shapes, which survives any scale.
			if inside.size.x <= 0.0 or inside.size.y <= 0.0:
				return Rect2()
		parent = parent.get_parent()
	return inside


## Whether a control is drawn at all: visible in the tree, and not clipped out of the picture by a box above it.
static func drawn(control: Control) -> bool:
	if not control.is_visible_in_tree():
		return false
	var inside: Rect2 = drawn_rect(control)
	return inside.size.x > 0.0 and inside.size.y > 0.0


## Whether a tap stops at a control at all: something on the screen that takes the mouse. The engine's own
## `mouse_filter` answers it - a plain panel under a button passes the click through to the button - so a control
## that ignores the mouse is not a thing a tap can reach.
static func _a_tap_stops_here(control: Control) -> bool:
	if not _showing_at_all(control):
		return false
	return control.mouse_filter != Control.MOUSE_FILTER_IGNORE


## Whether a tap on a control is answered: a button switched off takes the click and then does nothing at all,
## which is exactly the answer somebody hunting a button that does nothing is looking for. Everything else here
## answers when it is reached.
static func _answers_a_tap(control: Control) -> bool:
	if control is BaseButton:
		return not (control as BaseButton).disabled
	return true


## What a control is called in a sentence about a tap, unique enough to be argued about: the part it is in, the
## node's own name, and the words showing on it.
static func _press_name(scope: String, control: Control) -> String:
	return "%s  %s  %s" % [scope, control.name, _a_showing_thing(control)]
