extends Node
## A dev tool: the phone's own touch report, in one command, so that reading a real device's answer is not a six
## step adb dance remembered from a memory.
##
## The four questions that only a device can answer - is a target big enough for the density it is drawn at, are
## two targets closer than a thumb can tell apart, is a target standing in a band the system keeps, and is the
## words too small for the screen - are asked by the probe inside the running program, and land in `probe.log` on
## the phone. Nothing here decides any of it: this pulls that log and prints what it says, grouped by the block it
## was published in, so the newest reading is the one in front of a person.
##
## **The log is the phone's, and so is the reading.** A desk cannot be told to lay out like a phone - Godot's
## embedded game refuses a window size change - which is why this drives the installed program rather than
## pretending to be one. It touches nothing on this computer but adb - and, when `--build` is asked, the engine's
## own export, which is the one step that makes a build to install.
##
## **A phone in reach is the first thing it asks about, and the refusal names it.** An instrument that has
## nothing to say and one that cannot ask are different readings: with no device in reach, the log's absence is
## not the program's silence. Measured 2026-11-14 with the A16W's wireless debugging off - the tool used to go on
## to "the log holds no block - has the program run since it was installed?", which points a person at the
## program. `a_device_is_here` is that question's pure half, held by a test.
##
## **A bare run is the whole question** - the one this is driven for most of the time - and it is a *look* rather
## than a reading: the device in reach, the hold the board obeys, whether the build on disk is still the work in
## hand, a picture of the screen, and the newest block beside it.
##
##     res://tools/phone_touch_pass.tscn                        what is on the screen now
##     ... -- --fresh                                           the same, having thrown the old log away first
##     ... -- --fresh --back                                    ... and one BACK, waited for rather than guessed at
##     ... -- --taps Cancel                                     the centres to aim at, for words holding `Cancel`
##     ... -- --press Begin                                     press that control, at the centre the block published
##     ... -- --swipe 540 1800 540 1200                         drag, to bring a control below a scroller into view
##     ... -- --crop 0 1700 1080 500                            that band of the picture, twice as big
##     ... -- --install --launch --wait 3                       make the phone run the build on disk
##     ... -- --build --launch --wait 25                        make a build first if anything reaching the phone has moved
##     ... -- --turn landscape --build --launch --wait 25        ...holding the device on its side, put back after
##     ... -- --tap 540 552                                     press at a place of your own choosing
##     ... -- --key tab                                         press a key the device's own input can send
##     ... -- --clear-pages                                     BACK until nothing is in front of the board
##     ... -- --block                                           the newest block whole, every line of it
##     ... -- --blocks                                          every block the log holds, by age, and what it named
##     ... -- --overlay                                         the block's own rectangles marked on the picture
##     ... -- --installed                                       what the phone is running, by the hash of its own copy
##     ... -- --numbers                                         the numbers this project states for a phone, against the phone
##     ... -- --band                                            the band the program reports for this device, beside the
##                                                       band the phone's own `dumpsys` reports
##     ... -- --capture                                         the board upright, a line, then the question - it
##                                                       turns the device and holds the board upright itself,
##                                                       and hands both back when it is done
##     ... -- --keep widened_bar                                ...and keep this run's picture under a name; a
##                                                       capture prefixes its three pictures with it, since
##                                                       their own names are the same every time
##
## **From a shell, with no display**: the tool touches nothing on this computer but adb, so nothing here wants the
## editor or a window open.
##
## **Run it bare, or into a file - not into a pipe.** Measured 2026-11-17: the same pass written to a file returned
## `exit=0` with the whole report printed, while the same run through `| tail` never came back at all. The tool had
## finished; something it starts through adb outlived it and held the pipe open, so nothing downstream ever saw the
## end of the output. `> build/phone_pass.txt` is how to keep a copy of a run and still get the prompt back.
##
##     GODOT_MCP_RUNTIME=0 <godot> --headless --path . res://tools/phone_touch_pass.tscn -- --fresh
##     GODOT_MCP_RUNTIME=0 <godot> --headless --path . res://tools/phone_touch_pass.tscn -- --turn landscape --build --launch
##
## **The picture is the arbiter and the block is not.** A block is published when the pages up change, so a
## rectangle in the newest one can be older than what is on the glass - measured 2026-11-14, a whole diagnosis was
## built on a block written at launch, before the foot line had wrapped, while the screen it was about had long
## moved on. Three things answer that. `--fresh` gives up the old log before anything is asked of the device, so
## what is read was published after this run started; **`--blocks` says how old the newest block is**, which no
## line inside a block can; and `--overlay` puts the rectangles onto the picture, so a claim and the pixels it is a
## claim about are looked at together.
##
## ## `--blocks`: the log as a list of moments, which is the question every stale reading turns on
##
## A block's text has no clock in it and `probe.log` is nothing but that text. logcat carries one, so the list is
## read from there - in `-v epoch`, so the age of a block is the difference between two absolute numbers rather
## than a subtraction across two clocks' opinions of what "14:44" means. That is why the age is printed and the
## time of day is not, exactly as the build's age is. It reads:
##
##     4 s ago        no page
##     9 s ago        1 page: start_window
##     12 s ago       2 pages: start_window, start_drawing_window
##
## **The last line is the newest block, and its age is the answer.** A block older than the moment a person acted
## means the program published nothing about that act - which is the whole story of a scroll, and of the palette's
## own re-place, neither of which is a page changing.
##
## **And the picture can be looked at closely.** `--crop x y width height` writes that band of it **twice as big**
## to `build/the_crop.png`, nearest-neighbour so that no colour is invented between two pixels. The picture is the
## screen's own pixels, which is the same space a block's rectangles are in, so a rectangle read off a block can be
## handed straight to `--crop` - which is how a 20 px overlap stops being something a person squints at.
##
## **The log is the program's own account of the screen, and it is as fresh as the last thing the screen did.** A
## page arriving and a page being put away both publish a block, so `--press`, `--swipe` and `--back` learn from the
## log whether what they did changed anything. That holds because of a fix made the same day the fault was found:
## until 2026-11-14 the block came from signals connected to the pages that existed when the program *started*, so
## a page built later - the begin-a-drawing page, the camera's - was never watched and **its leaving was
## invisible**. A BACK that the glass plainly showed had landed printed nothing at all, and the newest block went
## on naming the page it had put away. `Hud` asks the screen now.
##
## **The count either side of a press is what `--blocks` replaced**, and how the fault above was settled before it
## existed as a command:
##
##     adb logcat -d -s godot:I | grep -c "PROBE --- what is on the screen ---"
##
## A count that grew is a screen that changed; a count that held still, with a page named in the newest block, was
## the old fault rather than a BACK that failed. A build older than that fix still answers the old way - which is
## why the branch that finds nothing published says so rather than calling the press a failure - and `--blocks`
## reads the same count off any build.
##
## ## What a block's numbers are in, and how a page is read in landscape
##
## A block's `tap` lines are the **screen's own pixels** - the figure beside `native=` on its `room` line - while
## its `page` lines carry both: the page's own rectangle in logical room units, and, after `->`, the same
## rectangle in screen pixels. So `--tap X Y`, `--crop x y w h` and `--swipe` all want screen pixels, and a
## centre copied from a block taken the other way up reaches nothing. Since 2026-11-17 the tool measures a tap it
## sent against the screen rather than against the room, because a press that had plainly landed was being called
## a miss - `--press "Design the garden"` put (1213, 753) into a 2340 x 1080 screen and the sentence said
## "outside the room ... (1444, 666)", which is the logical room and not the space a centre is in at all.
##
## **The menu bar's titles are not targets the probe can publish, and that is correct.** A `MenuBar` handles the
## mouse itself, so its own buttons pass input through, and `Topmost`'s rule leaves a control the mouse passes
## through out of the tap list. To open a menu on a device, `--key tab` and then `--key enter` are the route; a
## page, once it is up, is reached by tapping a centre the block published for it.
##
## **A page in landscape is read by launching into it.** The doorway is laid out from the hold the device reports,
## so `--launch --wait N` with the hold landscape brings it up `shape=lying` - no `--back` needed, and a `--back`
## would put the door away instead of measuring it. Measured that way 2026-11-17: with the door up the strip read
## **91** px of the room against the bar's own 61 px row, the door's chrome sat well below it (its plate at screen
## rows 297..347 of a 1080-tall screen), and no `overlap` line named the top bar - the structural prevention the
## fixing pass could only infer. The board, with no page up, reads `strip` **247** and `nothing meets anything it
## may not`.
##
## **A control is pressed by its words rather than by a copied centre.** `--press Begin` finds the newest block's
## own line for that control and taps the middle of it, which removes the transposition between reading a centre
## out of a block and typing it again.
##
## `--tap` is how a page is reached on the device: the probe reports every control it could be tapped at, with the
## centre to aim at, and a real OS tap does reach a control inside a page's `Window` - measured, and the opposite
## of what the injection in `run_scene` can do. Those centres are what `--taps` prints.
##
## **The build is not run here, only asked about.** An export is a three-minute process with its own environment
## and this is a reader; what it does instead is say whether what is on disk still matches `res://scripts` and
## `res://scenes`, and hand over the line when it does not. **`--installed` goes the step further and asks the
## phone itself what it is running**, by the hash of its own copy of the program, so "the same build" stops being an
## inference from a timestamp and becomes a fact.
##
##     GODOT_MCP_RUNTIME=0 <godot> --headless --path . --export-debug "Android (phone)" build/phone-adapt.apk
##
## **It quits when the pass is done**, so putting a `timeout` around it is not needed - the address of the old
## hang was two exits from `_ready` with no `quit()` after either of them.
##
## **The two captures that still owe a phone.** Both are readings of the **board**, and both were attempted and
## lost to the link, so the sequence is written down here rather than remembered. Recorded 2026-11-14, when the
## A16W's wireless debugging was off and `adb mdns services` found nothing at all: no substitute exists for it,
## because a desk cannot be told to lay out like a phone.
##
##     adb shell run-as <pkg> cat files/orientation.json      # the hold; must read {"orientation": "portrait"}
##     adb shell run-as <pkg> rm -f files/probe.log
##     adb shell am force-stop <pkg>
##     adb shell am start -n <pkg>/com.godot.game.GodotAppLauncher
##     sleep 8
##     adb shell input keyevent 4                # BACK: the doorway away, so the BOARD is what is on screen
##     sleep 4
##     adb exec-out screencap -p > build/gap_board_portrait.png
##     adb shell input keyevent 8                # the `1` key is draft_line, so the palette needs no tapping
##     adb shell input tap 520 1150 ; sleep 2 ; adb shell input tap 880 1550      # a line: work to lose
##     adb shell input keyevent 4                # BACK: with unsaved work this IS the question (see below)
##     sleep 4
##     adb exec-out screencap -p > build/gap_question_portrait.png
##     adb exec-out run-as <pkg> cat files/probe.log > build/gap_probe.log
##
## The two tap points are clear of the palette (x < 0.4 of 1080 px) and mid-screen, so they land on the board
## whatever else is about. `--tap X Y` above is for a centre the probe itself printed; these two are not that -
## they are a place on the plan, and any place will do, because the line exists only to make work unsaved. The
## hold has to be the **valid** json written with `dd`, not the `{orientation:portrait}` the device was found
## holding: that is not JSON and is refused by design, so the board falls back to the wide default.
##
## **Taken, 2026-11-14, on the A16W held upright**, and two things the first attempt got wrong and this does not:
##
## - **The palette cell is tapped at the centre the probe itself printed** - `Line / 1` at (150, 404) upright -
##   because `input keyevent 8`, which is the `1` key `draft_line` is bound to, **did nothing at all**: two
##   screenshots a minute apart came back byte-identical. A tap the program's own report named is the one that
##   landed.
## - **No Escape, and one BACK.** `input keyevent 111` never reached the program at all: it left the phone's own
##   *USB settings* panel on the screen and the tool went on drawing into that. The tool box's foot line says
##   "Esc: cancel", but that is the app's Escape, not the key `input` sends. Nothing needs it either - a
##   completed line leaves a tool in hand, and BACK's ladder puts the tool away *and* asks, so one BACK is the
##   whole of it. That BACK is what put `DiscardChanges "Unsaved changes" ... 951x354 px` up inside the
##   1080 x 2340 room, with the program still alive.

const ADB := "C:/Users/storm/AppData/Local/Android/Sdk/platform-tools/adb.exe"
const PACKAGE := "ca.storm.landscapingplanner"
const ACTIVITY := "ca.storm.landscapingplanner/com.godot.game.GodotAppLauncher"
const APK := "res://build/phone-adapt.apk"

## The preset `--build` makes, and the file that decides what a build *contains* - permissions among them.
##
## A preset edit changes the APK without touching a single script: Android's INTERNET permission was added to one
## on 2026-11-10 and took a fresh export before the phone had it. So the preset's own time is part of the question
## "is the build still the work in hand", rather than a thing a person has to remember.
const PRESET := "res://export_presets.cfg"
const PRESET_NAME := "Android (phone)"

## The words `--turn` takes, and the rotation each means to Android: 0 upright, 1 on its side. `auto` is the third
## word and is deliberately not in here, because it names the device's own answer rather than a rotation of ours.
const TURNS: Dictionary = { "portrait": "0", "landscape": "1" }

## How long `--build` waits for the engine's own export before it stops waiting and says so. A ceiling rather than
## nothing: without one an export that wedged would leave a tool that looks frozen, which is what a person reaches
## for Ctrl-C about.
const EXPORT_CEILING := 900.0

## How near two numbers must be to be the same one. A block writes its density to one decimal and its scale to two
## (`%.1f` and `%.2f` in `HudProbe.device_lines`), so a fixture carrying `1.622` where the block says `1.62` is the
## same reading and not a fault.
const NEAR_ENOUGH := 0.01

## The trees a stated phone-number may hide in: the program, and the two dev trees. `addons/` is third-party and
## is never walked. **The program is included on purpose** - it is not supposed to state a phone's density at all,
## since it reads one, so a script under `res://scripts` that did would be the first thing worth knowing.
const STATED_ROOTS: Array[String] = ["res://scripts", "res://tools", "res://tests"]

## What the program is showing, in the order a person wants it: the device it is answering as, the room it was
## taken in, the strip at the top of it that no page may be placed in, **the band the device keeps for itself** -
## which is what the top bar is lifted by and was the one figure missing while the bar was being read on the phone,
## because the block named every control that had strayed *into* that band and never how big it was - the line at
## the foot and the box beside the plan, the page in front of all of it, the colour drawn above that page's top
## edge, and every meeting the drawn-surfaces rule named.
const SCREEN_LINES: Array[String] = [
	"device", "room", "strip", "insets", "foot", "tool", "page", "drawn", "overlap"
]

## The lines that name trouble a finger would have, printed after the screen so the news is never buried: a target
## under the floor, two a thumb cannot tell apart, one standing in a band the device keeps (or with its middle in
## one), words too small for the screen, words wanting more room than they are drawn in, and a control the room
## cannot hold.
const TOUCH_LINES: Array[String] = ["small", "close", "unsafe", "middle", "tiny", "clipped", "offscreen"]

## The four ways up a phone's own report lists its kept bands in, and the two bands it gives per way up. Read by name
## rather than by position, so a report that lists them in another order is still read the same way.
const ROTATIONS: PackedStringArray = ["ROTATION_0", "ROTATION_90", "ROTATION_180", "ROTATION_270"]

## What each of the eight bands `kept_bands_from` answers is, in the order it answers them: for each way up, the band
## that is the system bars alone, and the band that is those and the display's own configuration besides. The names
## are the phone's own words for them (`overrideNonDecorInsets`, `overrideConfigInsets`).
const BAND_ROWS: PackedStringArray = [
	"ROTATION_0   system bars",
	"ROTATION_0   system bars and config",
	"ROTATION_90  system bars",
	"ROTATION_90  system bars and config",
	"ROTATION_180 system bars",
	"ROTATION_180 system bars and config",
	"ROTATION_270 system bars",
	"ROTATION_270 system bars and config",
]

## Where the phone's own report states its camera cutout, in the display's natural pixels: `initCutout` is the cutout
## the panel was made with, where `baseCutout` is the one a rotation is worked out from - the two agree on the A16W,
## and this reads the first because it is the number a person compares with the panel's specification.
const CUTOUT_MARK := "initCutout=DisplayCutout{insets=Rect("


## The band a phone's own report says it keeps, as (left, top, right, bottom), for the reading in `text`. This is the
## **phone's** answer and not the program's: what it is for is being set beside what the program reports, so that a
## disagreement between Godot's safe area and the phone's own insets can be seen rather than guessed at.
static func cutout_insets_from(text: String) -> Vector4i:
	var at: int = text.find(CUTOUT_MARK)
	if at < 0:
		return Vector4i.ZERO
	var tail: String = text.substr(at + CUTOUT_MARK.length())
	var shut: int = tail.find(")")
	if shut < 0:
		return Vector4i.ZERO
	# The phone writes a rectangle as `Rect(left, top - right, bottom)`, the middle pair joined by a dash rather than a
	# comma, so the dash is turned into a separator before the four are read. Written any other way this read three
	# numbers out of four and called every cutout zero.
	var parts: PackedStringArray = tail.substr(0, shut).replace(" - ", ",").split(",")
	if parts.size() < 4:
		return Vector4i.ZERO
	return Vector4i(
		parts[0].strip_edges().to_int(),
		parts[1].strip_edges().to_int(),
		parts[2].strip_edges().to_int(),
		parts[3].strip_edges().to_int(),
	)


## Every band the phone's own report names: for each of the four ways up, the band that is the system bars and the
## band that is those and the display's configuration besides - always eight, in the order `BAND_ROWS` names them.
##
## **The eight are answered together or not at all.** A report naming only some of the four ways up would leave every
## name after the gap against the wrong band, and a name read off one list by an index into another is the
## second-engine mistake this project works hardest to avoid. So an empty list is a report this reader does not know,
## which is a different answer from a phone that keeps nothing - the caller says which of the two it found.
static func kept_bands_from(text: String) -> Array[Vector4i]:
	var none: Array[Vector4i] = []
	var bands: Array[Vector4i] = []
	for rotation: String in ROTATIONS:
		var row: String = _the_line_naming(text, rotation + "={")
		if row.is_empty():
			return none
		bands.append(_a_rectangle_after(row, "overrideNonDecorInsets="))
		bands.append(_a_rectangle_after(row, "overrideConfigInsets="))
	return bands


## A band as a person reads it.
static func band_words(band: Vector4i) -> String:
	return "left=%d top=%d right=%d bottom=%d" % [band.x, band.y, band.z, band.w]


## The one line that says what the two readings mean together: whether the band the program reports **is** the phone's
## camera cutout, **is** one of the bands the phone keeps for its own furniture, or is neither. The last is the answer
## worth having - it is what says Godot's safe area and this phone's insets disagree about this device.
static func band_verdict(program: Vector4i, cutout: Vector4i, kept: Array[Vector4i]) -> String:
	if program == Vector4i.ZERO:
		return "the program reported no band at all, which is what a desk answers and not what a phone does."
	if program == cutout:
		return "the program's reading IS the phone's own camera cutout."
	for i: int in kept.size():
		if program == kept[i]:
			return "the program's reading IS the band the phone keeps: %s." % BAND_ROWS[i]
	return (
		"the program's reading matches none of the bands the phone names, so Godot's safe area and the phone's own"
		+ " report disagree about this device."
	)


## The line of `text` that carries `mark`, or nothing when no line does.
static func _the_line_naming(text: String, mark: String) -> String:
	for raw: String in text.split("\n"):
		var line: String = raw.strip_edges()
		if line.contains(mark):
			return line
	return ""


## The band the phone writes as two pairs of numbers - `[100,84][0,42]` - as (left, top, right, bottom). Zero when the
## mark is not there, so a report naming no such band is no reading rather than a band of nothing.
static func _a_rectangle_after(text: String, mark: String) -> Vector4i:
	var at: int = text.find(mark)
	if at < 0:
		return Vector4i.ZERO
	var tail: String = text.substr(at + mark.length())
	var first: int = tail.find("]")
	if first < 0:
		return Vector4i.ZERO
	var second: int = tail.find("]", first + 1)
	if second < 0:
		return Vector4i.ZERO
	var parts: PackedStringArray = (
		tail.substr(0, second + 1).replace("][", ",").replace("[", "").replace("]", "").split(",")
	)
	if parts.size() < 4:
		return Vector4i.ZERO
	return Vector4i(
		parts[0].strip_edges().to_int(),
		parts[1].strip_edges().to_int(),
		parts[2].strip_edges().to_int(),
		parts[3].strip_edges().to_int(),
	)

## The files a build is made from: what reaches the phone's program, and nothing else. A test, a doc or a dev tool
## is nothing to export for, so a tree full of yesterday's tests is not a reason to install again.
const REBUILD_ROOTS: Array[String] = ["res://scripts", "res://scenes"]
const REBUILD_SUFFIXES: Array[String] = [".gd", ".tscn"]

## What the bare run's picture is called, in the capture directory, and what `--crop` writes beside it.
const THE_SCREEN_NOW := "the_screen_now.png"
const THE_CROP := "the_crop.png"

## And what `--overlay` writes: the pulled picture with the block's own rectangles marked on it.
const THE_BOXES := "the_boxes.png"

## The two colours `--overlay` marks with - a control a finger can aim at, and the page standing in front of the
## board - both translucent, so the pixels a mark is about are still read through it.
const TAP_BOX := Color(0.1, 1.0, 0.9, 0.7)
const PAGE_BOX := Color(1.0, 0.72, 0.1, 0.7)
const BOX_THICKNESS := 3

## How many BACKs `--clear-pages` will send before it stops and says what is still up. A page that will not go away
## is something to read, not a reason to keep pressing.
const MAX_PAGES_TO_CLEAR := 4

## The keys a phone's own `input` can send, by name: **Android keycodes, not Godot's**, because `input keyevent`
## speaks the device's alphabet. BACK and the two that drive a dialog are the three measured to reach this program;
## the arrows are here because a walk of focus is what they are for. `the_key_number` reads this table and
## `key_words` is where the two keys that must not be sent say why.
const KEYS: Dictionary = {
	"back": 4,
	"tab": 61,
	"enter": 66,
	"space": 62,
	"up": 19,
	"down": 20,
	"left": 21,
	"right": 22,
}

## The words a block begins with, in the probe's own report.
const BLOCK_HEAD := "--- what is on the screen ---"

## The probe, for the one thing only a block can say: the room it was taken in. This tool sends a tap in screen
## pixels, and whether those pixels are on the screen the program is drawing on is the block's answer.
const HudProbeScript := preload("res://scripts/hud_probe.gd")

## The picture read as numbers, for the one question no rectangle can answer: what is actually on the glass. The
## crop `--crop` writes is this module's own `doubled`, so the enlargement a person reads a letter off and the one
## this tool makes cannot be two different enlargements.
const ScreenshotReaderScript := preload("res://scripts/screenshot_reader.gd")

## Where `--capture` puts its screenshots, and the three places it presses on the way.
##
## The two line points are in the screen's own pixels on the A16W held upright: clear of the palette (x is under
## 0.4 of the 1080 it is drawn on) and mid-screen, so they land on the plan whatever else is about. Any place
## would do - the line exists only to make work unsaved. `LINE_CELL` is the palette's own first tool cell, which
## is pressed **at the centre the probe itself printed** for it.
const CAPTURE_DIR := "res://build/"
const LINE_CELL := Vector2i(150, 404)
const LINE_TAPS: Array[Vector2i] = [Vector2i(620, 1150), Vector2i(800, 1450)]

## The one upright hold this tool writes for the board. The board reads it when it starts, and `hold_words` is the
## reader that says whether it took - so what this writes and what a person is told cannot drift apart.
const UPRIGHT_HOLD := "{\"orientation\": \"portrait\"}"

## Where a file made on this computer is put on the device before it is moved into the program's own storage.
## **`dd` with an `if=` is how a file gets there**: `run-as <pkg> sh -c "cat > files/x"` fails because the device's
## outer shell eats the redirect, and a pipe cannot be sent through `OS.execute` at all.
##
## **`/data/local/tmp`, and never `/sdcard`.** Measured 2026-11-17: a hold staged on `/sdcard` left the board
## reading `{"orientation": "landscape"}` after the write - the program's own uid cannot read an arbitrary public
## file under scoped storage, so `dd` had nothing to copy. `/data/local/tmp` is the device's own scratch space,
## readable by `run-as` and writable by `adb push`.
const STAGING := "/data/local/tmp/"
const STAGED_HOLD := "phone_hold.json"

## How long a run waits for a phone that has left the link before it gives up and says so.
const DEVICE_WAIT := 60.0

## What a `--keep` name may be made of, so that a name a person types can never point this tool's writing at a place
## outside the capture directory.
const LETTERS_IN_A_NAME := "abcdefghijklmnopqrstuvwxyz0123456789_"

## Where adb was found, once, at the start: the SDK copy, or a bare one on the path.
var _adb_path: String = ""

## The tap this run sent, and whether there was one - a tap at (0, 0) is a real place on a screen, so the point
## alone cannot say whether anything was sent.
var _tapped: Vector2i = Vector2i.ZERO
var _sent_a_tap: bool = false

## What the device's own rotation was before `--turn` set it: read before it is touched, so the run can hand back
## exactly what it found rather than a guess about what a person had chosen.
var _was_auto: String = ""
var _was_rotation: String = ""
var _turned: bool = false


func _ready() -> void:
	# One exit for the whole tool: a pass that returns early - no adb on this machine - ends the same way a
	# finished one does. Before this line, both exits simply fell off the end of `_ready`, so the tree never
	# quit and the tool sat open for ever unless it was run under a `timeout`. Every future exit is a `return`
	# inside `_one_pass`, and this line covers it too.
	await _one_pass()
	get_tree().quit()


## Everything the tool does, in one pass. It is a coroutine because waiting for a phone is what it spends its
## time doing, and a dev tool has the frames to spare; it ends wherever it has nothing left to say, and `_ready`
## is what turns that ending into the program stopping.
func _one_pass() -> void:
	_adb_path = _find_adb()
	if _adb_path.is_empty():
		print("PHONE no adb at %s, and none on the path - is the SDK still where it was?" % ADB)
		return
	var asked: PackedStringArray = OS.get_cmdline_user_args()
	var devices: String = _line(["devices", "-l"])
	if not a_device_is_here(devices):
		print("PHONE no phone is in reach, so there is nothing to read. adb said:")
		print("      %s" % devices.strip_edges().replace("\n", " | "))
		print("      Turn wireless debugging back on - a *fresh* adb server discovers it with `adb mdns services`")
		print("      - or put a cable in. Nothing here stands in for a device: a desk cannot be told to lay out")
		print("      like a phone.")
		return
	print("PHONE %s" % _first_line(_line(["version"])))
	print("PHONE %s" % devices.strip_edges().replace("\n", " | "))

	# **Which way up the device is, asked for by name.** This is the *device's* own rotation, and it is a different
	# thing from the board's hold in `user://orientation.json` that `hold_words` reads below: a capture wants both,
	# and `--capture` says so when its own half is missing. A word this does not know is refused rather than
	# guessed at, because a typo that holds somebody's phone at random is worse than a line saying what it wanted.
	if "--turn" in asked:
		if turn_of(asked).is_empty():
			print("PHONE `--turn` wants `portrait`, `landscape` or `auto` - `--turn landscape` - and the device's")
			print("      rotation was left alone. This is the device's rotation, not the board's hold.")
		else:
			_turn_the_device(turn_of(asked))

	if "--capture" in asked:
		await _capture_the_two_gaps()
		_put_the_screen_back()
		return

	# **A reading needs no build, so it happens before anything is made or put on the device.** `--band` is the one
	# question this tool asks that a desk cannot answer at all - a computer has no cutout - and the one the menu bar's
	# lift turned on: the block named every control that had strayed *into* the band the device keeps and never how big
	# the band was, so the size of the lift could only be guessed at from a picture and arithmetic.
	if "--band" in asked:
		await _read_the_band()
		_put_the_screen_back()
		return

	# **Giving up the old log is what makes a reading fresh**, and it happens before anything is asked of the
	# device, because a block is a moment and the file does not stamp it. **One call site**: `--fresh`, `--install`,
	# `--build` and `--launch` all want the same thing, and the first version had two of them clearing it, so the
	# line saying so was printed twice.
	var building: bool = "--build" in asked
	var putting_it_on: bool = building or "--install" in asked
	# **A launch gives up the log itself, and closer to the act.** A build takes minutes and the program already on the
	# phone publishes blocks all the while, so a log cleared before the build is full of the *old* build's moments by
	# the time the install lands - and the wait below then finds one of them in half a second and calls the program up.
	# Measured 2026-11-17: the reading that followed was the previous build's, down to a field that no longer exists in
	# the tree. What a reading must be newer than is the **launch**, so that is where the log is given up when there is
	# one; every other run gives it up here, before anything is asked of the device.
	var launching: bool = putting_it_on or "--launch" in asked
	var cleared: bool = "--fresh" in asked or putting_it_on
	if cleared and not launching:
		_clear_the_log()
	# **A build that would not be made stops the run**, rather than installing the last one: nothing below would be
	# a reading of the change that was asked for, and a screen read from the wrong build is the mistake this whole
	# tool is about.
	if building:
		var made_now: bool = await _make_the_build()
		if not made_now:
			_put_the_screen_back()
			return
	if putting_it_on:
		# **A ten-minute export is long enough for a phone to leave the USB link.** Measured 2026-11-17: the install
		# that followed read `adb: no devices/emulators found` and nothing said what to do about it, while the build
		# had already been made and the answer was one more command. The wait is bounded and the refusal names that.
		if not await _wait_for_the_device(DEVICE_WAIT):
			_put_the_screen_back()
			return
		print("PHONE installing %s" % APK)
		print("PHONE %s" % _line(["install", "-r", ProjectSettings.globalize_path(APK)]).strip_edges())
	if putting_it_on or "--launch" in asked:
		# The other half of the rule above: the log is given up **here**, after the build and the install, so that it
		# holds nothing but what the program that is about to start publishes.
		_clear_the_log()
		_line(["shell", "am", "force-stop", PACKAGE])
		print("PHONE launching %s" % ACTIVITY)
		_line(["shell", "am", "start", "-n", ACTIVITY])
		# **Waiting for the block rather than for a number of seconds.** A debug build publishes one at launch, so
		# the program itself says when it is up - and eight seconds was measured *not* to be enough on the A16W
		# (2026-11-14: the log was still empty, so a `--press` in the same command found nothing to press at).
		# `--wait N` is the ceiling now rather than the wait.
		var allowed: float = float(_wait_seconds(asked))
		var waited: float = 0.0
		var up: bool = false
		while waited < allowed and not up:
			await get_tree().create_timer(0.5).timeout
			waited += 0.5
			up = not blocks_in(_line(["exec-out", "run-as", PACKAGE, "cat", "files/probe.log"])).is_empty()
		if up:
			print(
				"PHONE the program is up: it published a block after %.1f s, of the %d s allowed"
				% [waited, int(allowed)]
			)
		else:
			print(
				"PHONE no block in %d s: the program had not published when this looked, and nothing below is a"
				% int(allowed)
			)
			print("      reading of a blank screen. A slower device wants a bigger `--wait N`.")
	if "--tap" in asked:
		var at: Vector2i = _the_tap(asked)
		_tapped = at
		_sent_a_tap = at != Vector2i.ZERO
		print("PHONE tapping (%d, %d)" % [at.x, at.y])
		_line(["shell", "input", "tap", str(at.x), str(at.y)])
		await get_tree().create_timer(3.0).timeout
	if "--swipe" in asked:
		var drag: Array[Vector2i] = the_swipe(asked)
		if drag.size() != 2:
			print("PHONE `--swipe` wants four numbers - x1 y1 x2 y2, and an optional duration in ms - so nothing")
			print("      was dragged.")
		else:
			await _drag(drag[0], drag[1], the_drag_ms(asked))
	if "--press" in asked:
		var words: String = the_word_after(asked, "--press")
		if words.is_empty():
			print(
				"PHONE `--press` wants the words of the control to press - `--press Begin` - and nothing was pressed."
			)
		else:
			await _press_a_control(words)
	if "--key" in asked:
		var key: String = the_word_after(asked, "--key")
		if key.is_empty():
			print(
				"PHONE `--key` wants a key's name - `--key tab` - and nothing was sent. It sends: %s"
				% ", ".join(PackedStringArray(KEYS.keys()))
			)
		else:
			await _send_a_key(key)
	if "--back" in asked:
		await _go_back()
	if "--clear-pages" in asked:
		await _clear_the_pages()

	print("PHONE the hold: %s" % hold_words(_line(["shell", "run-as", PACKAGE, "cat", "files/orientation.json"])))
	_report_the_build()
	_photograph_the_screen()
	if "--keep" in asked:
		_keep_the_picture(asked)
	if "--crop" in asked:
		_crop_the_picture(asked)
	# Named for what it is rather than `log`: `log` is a built-in function, and a local that shadows one is a
	# thing this project's warnings are set to fail on.
	var probe_log: String = _line(["exec-out", "run-as", PACKAGE, "cat", "files/probe.log"])
	# Read *before* the block is reported, because the age it carries is the one thing a block cannot say about
	# itself and it is what tells a reader whether the geometry below is about the screen in front of them.
	var logcat: String = _line(["logcat", "-d", "-s", "godot:I", "-v", "epoch"])
	_report(probe_log, cleared, logcat)
	if "--block" in asked:
		_report_the_whole_block(probe_log)
	if "--taps" in asked:
		_report_the_taps(probe_log, asked)
	if "--overlay" in asked:
		_draw_the_boxes(newest_block(probe_log))
	# The bar's own line and the blocks themselves are both stamped by the device and not by the file, so both are
	# read from logcat - **once**, in the one format that carries a clock - and that one read is above the block
	# report, which wants the age it carries.
	# `--build` asks it too, because the whole point of making a build and putting it on is that the phone is now
	# running the work in hand - and the hash of the phone's own installed copy is the only reading that can say so.
	if building or "--installed" in asked:
		_report_what_the_phone_runs()
	if "--blocks" in asked:
		_report_the_blocks(logcat)
	if "--numbers" in asked:
		_report_the_stated_numbers(probe_log)
	_report_the_fold(logcat)
	# **The screen is put back last**, after `_photograph_the_screen` has taken its picture: the picture is of the
	# device as it is held, and that picture is the whole reason holding it is worth doing.
	_put_the_screen_back()


## The top bar's own numbers, out of logcat: the durable evidence for the one thing a single block cannot show -
## whether the fold had **finished** when the block was taken.
##
## A block is published the moment a page appears, and the fold goes on running after that: measured on the A16W,
## a launch block still carried the bar at ten titles needing 1052 px of a 349 px room, while the bar's own line
## went on to two titles and 272 px and fitted. Reading that block as a defect in the bar is the mistake this
## exists to prevent, and the line it reads is the bar's own - its reader and its writer are one thing, in
## `menu_bar_plan.gd`, round-tripped by a test.
func _report_the_fold(logcat: String) -> void:
	var folded: Dictionary = MenuBarPlan.read_menubar_line(logcat)
	if folded.is_empty():
		print("PHONE the top bar printed nothing: a release build does not say what it folded, and neither does a")
		print("      run that never laid the bar out. Nothing here is a reading of the bar.")
		return
	print("PHONE the top bar, last word: %s" % folded["line"])
	print("      %s" % MenuBarPlan.bar_words(folded))
	print("      That is the bar's own word, taken after the block above was printed: the block is what the screen")
	print("      looked like when it was taken, and a launch block is taken before the fold has finished.")


## The two captures that owe a phone, in one command rather than a remembered dance.
##
## **Both are readings of the board, and both are the way up it is held.** The hold is checked and stated first,
## and a board that is not held upright **stops the capture** rather than producing two handsome screenshots of
## the wrong thing.
##
## Then: launch, BACK to put the doorway away so the board is what is on the screen, and photograph it. Then a
## line - the palette's own tool cell at the centre the probe reported, then two points on the plan - and one
## BACK, which with unsaved work *is* the unsaved-changes question rather than a way out of the program. That
## question is the second capture, and it is the one that pays: taken upright on 2026-11-14 it showed its own two
## buttons 33 px short of the device's floor, a fault that had been cured in landscape and never seen in portrait.
##
## Neither capture presses Escape: `input keyevent 111` does not reach this program at all - it left the phone's
## own USB settings panel on the screen - and nothing here needs it, because a completed line leaves a tool in
## hand and BACK's ladder puts that tool away and then asks.
func _capture_the_two_gaps() -> void:
	# **Both halves of a capture belong to this verb.** The board's hold lives in `user://orientation.json` and the
	# way up the *device* is lives in its own settings: two owners, which is why this used to stop and print the
	# `dd` line for a person to run by hand - measured 2026-11-17, that refusal fired on every capture and the
	# hand-written file was one more thing to remember between two runs. It writes both halves now, reads the hold
	# back in the board's own words to prove it took, and hands both back on every way out.
	_turn_the_device("portrait")
	_hold_the_board_as_found()
	# The view the block already in the log names, before anything relaunches the program: a program that has just
	# started is in 3D overhead whatever view a person was using, and nothing else remembers it.
	_view_as_found = HudProbeScript.read_view_line(
		"\n".join(newest_block(_line(["shell", "run-as", PACKAGE, "cat", "files/probe.log"])))
	)
	_write_the_board_hold(UPRIGHT_HOLD)
	var hold: String = hold_words(_line(["shell", "run-as", PACKAGE, "cat", "files/orientation.json"]))
	print("PHONE the hold: %s" % hold)
	if not hold.begins_with("the board is held upright"):
		print("PHONE the board would not take the upright hold - %s - so nothing was photographed." % hold)
		print("      The hold and the device's own rotation are handed back as they were found.")
		_hand_the_board_back()
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIR))

	_line(["shell", "run-as", PACKAGE, "rm", "-f", "files/probe.log"])
	_line(["shell", "am", "force-stop", PACKAGE])
	print("PHONE launching %s" % ACTIVITY)
	_line(["shell", "am", "start", "-n", ACTIVITY])
	await get_tree().create_timer(10.0).timeout

	_line(["shell", "input", "keyevent", "4"])
	await get_tree().create_timer(4.0).timeout
	# **A BACK can be swallowed, and the picture would then be of the doorway rather than the board.** Measured
	# 2026-11-14: on the *first* launch after an install the front door was still up when the board was
	# photographed, because that press went to Android's own first-run furniture. So the door is asked about
	# rather than assumed - the probe writes a block whenever a page is shown, and the newest block names the
	# page it is for. One more BACK is safe *here* and only here: a BACK with nothing on the screen is the
	# quit guard, which is why this asks the log instead of pressing again regardless.
	if _a_page_is_still_up():
		print("PHONE a page is still up after BACK - pressing once more so the picture is the board")
		_line(["shell", "input", "keyevent", "4"])
		await get_tree().create_timer(4.0).timeout
	_save_a_screenshot(_a_capture_picture("board_upright.png"))

	_line(["shell", "input", "tap", str(LINE_CELL.x), str(LINE_CELL.y)])
	await get_tree().create_timer(3.0).timeout
	for point: Vector2i in LINE_TAPS:
		_line(["shell", "input", "tap", str(point.x), str(point.y)])
		await get_tree().create_timer(2.0).timeout
	_save_a_screenshot(_a_capture_picture("a_line_drawn.png"))

	_line(["shell", "input", "keyevent", "4"])
	await get_tree().create_timer(6.0).timeout
	_save_a_screenshot(_a_capture_picture("the_unsaved_question.png"))
	print("PHONE the program is still alive as pid %s" % _first_line(_line(["shell", "pidof", PACKAGE])))
	print("PHONE three pictures in %s - and what the probe says about each is in the log beside them" % CAPTURE_DIR)
	# And the phone is handed back the way it was found, in the other direction: the hold it started with, and the
	# program on the board with nothing in front of it - a step a person used to do by hand, twice, with a
	# force-stop and a BACK.
	_hand_the_board_back()
	await _put_the_program_back()
	# **The view is the one thing this run cannot hand back, and the reason is measured.** A view change publishes
	# no block - what a block follows is the pages up - so the newest block's own view can be several turns old:
	# measured 2026-11-17, the log's newest block said `3D OVERHEAD` while the glass plainly showed the 2D plan, and
	# a first version of this *pressed* the toggle on that reading and turned the board to 3D the wrong way. So the
	# view is named and left to the person, whose own button says which way it goes - `2D plan  (Q)` from the 3D
	# view - which is better than a run guessing and being wrong with confidence.
	print("PHONE the view: a launch starts in the 3D overhead view whatever was in use, and a view change publishes")
	var named: String = "no view at all" if _view_as_found.is_empty() else _view_as_found
	print("      no block, so the block above knows no better than this (%s) - press the view button" % named)
	print("      yourself if you were not in the 3D overhead view.")


## **The band the program reports, beside the band the phone reports.** Two owners, neither restated: the program's
## half comes out of the newest block, where `PhoneHud.band_as_reported` wrote it, and the phone's half comes out of
## the phone's own `dumpsys`. The verdict compares them, because a pile of numbers with no answer is what this whole
## exercise was: on the A16W the bar was found 212 px down a screen the phone keeps only 84 px of, and no line said so.
func _read_the_band() -> void:
	var block: String = "\n".join(
		newest_block(_line(["shell", "run-as", PACKAGE, "cat", "files/probe.log"]))
	)
	if block.is_empty():
		print("PHONE the log holds no block, so there is no program reading to set beside the phone's. Launch it")
		print("      once - `--launch --wait 20` - and ask again.")
		return
	if not block.contains(HudProbeScript.BAND_MARK):
		# **A block that names no band line is a different answer from a program that reported no band**, and once
		# both are read as four zeros they look identical. Measured 2026-11-17, the first live run answered
		# `left=0 top=0 right=0 bottom=0` for exactly this reason - the build on the device predated the line - and
		# the verdict below then blamed Godot's safe area for a reading that had never been made.
		print(
			"PHONE the block the phone published names no band line at all (%s), so the build on the device predates"
			% HudProbeScript.BAND_MARK
		)
		print("      it. One export makes this half real: `--build --launch`, then ask again.")
	var program: Vector4i = HudProbeScript.read_display_band_line(block)
	print("PHONE the band the program reports: %s" % band_words(program))
	var report: String = _line(["shell", "dumpsys", "window", "displays"])
	var cutout: Vector4i = cutout_insets_from(report)
	print("PHONE the phone's own report:       %s  (its camera cutout)" % band_words(cutout))
	print("PHONE and what it keeps, by the way up the device is held:")
	var kept: Array[Vector4i] = kept_bands_from(report)
	if kept.is_empty():
		print("      nothing - this report names no kept bands at all, so which of the two answers is missing is")
		print("      the report rather than the device.")
		return
	for i: int in mini(kept.size(), BAND_ROWS.size()):
		print("      %s  %s" % [BAND_ROWS[i], band_words(kept[i])])
	print("PHONE %s" % band_verdict(program, cutout, kept))


## The board's hold in `user://orientation.json`, kept **verbatim** so it can be handed back exactly as it was
## found: `{"orientation": "portrait"}` and a file that is not JSON at all are both things this device has held,
## and a reader that re-serialised one would be handing back something the board never had.
var _hold_as_found: String = ""
var _held_the_board: bool = false

## The view the block already in the log was taken in, in the program's own words, read before the capture
## relaunches the program - the copy of it that a relaunch destroys.
var _view_as_found: String = ""


## Read the hold the board is obeying now, before anything changes it.
func _hold_the_board_as_found() -> void:
	_hold_as_found = _line(["shell", "run-as", PACKAGE, "cat", "files/orientation.json"])
	_held_the_board = true


## Write the hold the board takes at its launch, staged on the device and moved in with `dd`.
func _write_the_board_hold(wanted: String) -> void:
	var here: String = ProjectSettings.globalize_path(CAPTURE_DIR.path_join(STAGED_HOLD))
	var file := FileAccess.open(here, FileAccess.WRITE)
	if file == null:
		print("PHONE the hold could not be written here (%s), so the board's own was left alone" % here)
		return
	file.store_string(wanted)
	file.close()
	_line(["push", here, STAGING + STAGED_HOLD])
	_line(["shell", "run-as", PACKAGE, "dd", "if=%s" % (STAGING + STAGED_HOLD), "of=files/orientation.json"])


## Hand the board's hold back exactly as it was found - or take the file away again if the device had none, which
## is a hold of its own: `hold_words` reads that as the wide default.
func _hand_the_board_back() -> void:
	if not _held_the_board:
		return
	_held_the_board = false
	if _hold_as_found.strip_edges().is_empty():
		_line(["shell", "run-as", PACKAGE, "rm", "-f", "files/orientation.json"])
	else:
		_write_the_board_hold(_hold_as_found)
	print(
		"PHONE the board's own hold is handed back: %s"
		% hold_words(_line(["shell", "run-as", PACKAGE, "cat", "files/orientation.json"]))
	)


## Put the program back on the board with nothing in front of it - the way a run finds it, and the step a person
## used to do by hand after every capture.
func _put_the_program_back() -> void:
	_line(["shell", "am", "force-stop", PACKAGE])
	_line(["shell", "am", "start", "-n", ACTIVITY])
	await get_tree().create_timer(10.0).timeout
	_line(["shell", "input", "keyevent", "4"])
	await get_tree().create_timer(4.0).timeout
	print("PHONE the program is back on the board with nothing in front of it")


## Wait, two seconds at a time, for a phone that has left the link to come back - and where it does not, name it in
## terms of what the run had already done, rather than letting a wall of `adb ... ended with -1` be the last word.
func _wait_for_the_device(seconds: float) -> bool:
	var waited: float = 0.0
	while waited < seconds:
		_line(["start-server"])
		if a_device_is_here(_line(["devices", "-l"])):
			if waited > 0.0:
				print("PHONE the phone is back in the link after %.1f s" % waited)
			return true
		await get_tree().create_timer(2.0).timeout
		waited += 2.0
	print("PHONE the phone is not in the link, and has not come back in %d s." % int(seconds))
	print("      %s" % the_device_left_words(true))
	return false


## Keep this run's picture under a name of your own, so the next run does not overwrite this one's evidence.
##
## The picture is always pulled as `the_screen_now.png` - the name a person goes looking for - which is why three
## runs in a row on 2026-11-17 each had to be copied aside by hand, and the first one's picture was lost before
## anybody noticed.
func _keep_the_picture(asked: PackedStringArray) -> void:
	var words: String = the_word_after(asked, "--keep")
	if words.is_empty():
		print("PHONE `--keep` wants a name - `--keep widened_bar` - and nothing was kept.")
		return
	var name: String = kept_picture_name(words)
	var from: String = ProjectSettings.globalize_path(CAPTURE_DIR.path_join(THE_SCREEN_NOW))
	var to: String = ProjectSettings.globalize_path(CAPTURE_DIR.path_join(name))
	if DirAccess.copy_absolute(from, to) != OK:
		print("PHONE there was no picture to keep as %s" % name)
		return
	print("PHONE the picture is kept as %s%s" % [CAPTURE_DIR, name])


## The file a `--keep` name is written as: made of letters, digits and underscores, ending `.png`, and inside the
## capture directory whatever was typed. A name is a person's own words; a path is not somewhere a name should be
## able to point a tool that writes files.
static func kept_picture_name(words: String) -> String:
	var said: String = words.strip_edges().to_lower()
	var safe: String = ""
	for index: int in said.length():
		var letter: String = said.substr(index, 1)
		if LETTERS_IN_A_NAME.contains(letter):
			safe += letter
		elif letter == " " or letter == "-":
			safe += "_"
	if safe.replace("_", "").is_empty():
		safe = "kept"
	return "%s.png" % safe


## The name a capture's picture is written under: its own, or the `--keep` name in front of it, so that a second
## capture does not overwrite the first one's evidence.
##
## **A gap documented is not a gap fixed.** These three - `board_upright.png`, `a_line_drawn.png`,
## `the_unsaved_question.png` - were the names they carried on 2026-11-17, so every capture after the first wrote
## over the pictures a person was still looking at, and the note that `--keep` did not apply to a capture was the
## whole of what was done about it. Pure, and with the `--keep` words handed in rather than read, so a test can
## hold what a run would be told without being one.
static func capture_picture_name(kept_words: String, own: String) -> String:
	if kept_words.strip_edges().is_empty():
		return own
	return "%s_%s" % [kept_picture_name(kept_words).trim_suffix(".png"), own]


## What to say when the phone is not in reach for the step that needed it. Named rather than generic, because
## what a person does next depends on how far the run had got: a build already made is not one to make again.
static func the_device_left_words(a_build_was_made: bool) -> String:
	if a_build_was_made:
		return (
			"The build is already made, so put the phone back in reach and run `--install --launch` -"
			+ " there is nothing left to export."
		)
	return "Put the phone back in reach - a cable is the reliable route - and run the same command again."


## Whether the newest block in the probe's log names a page.
##
## It reads the device's own log rather than a picture, for the reason the whole tool exists: a rectangle is a
## statement by the program about itself, and the log is the program making it. **It answers about the block and not
## about the screen**: a block is only as fresh as the last thing the screen did, which is why `--capture` asks this
## rather than trusting it, and why every run takes a picture.
func _a_page_is_still_up() -> bool:
	return a_block_names_a_page(newest_block(_line(["shell", "run-as", PACKAGE, "cat", "files/probe.log"])))


## The name this capture's picture goes under, from the `--keep` this run was given - the one place the run's own
## arguments are read, so a picture's name is decided by `capture_picture_name` and nothing else.
func _a_capture_picture(own: String) -> String:
	return capture_picture_name(the_word_after(OS.get_cmdline_user_args(), "--keep"), own)


## One screenshot, taken on the device and pulled back as a file.
##
## **`exec-out screencap -p` cannot be used from here.** `OS.execute` hands back *text*, and a PNG read through it
## is a length of mangled characters - so the picture is written on the device and `pull` copies the bytes.
func _save_a_screenshot(file_name: String) -> void:
	var far: String = "/sdcard/%s" % file_name
	_line(["shell", "screencap", "-p", far])
	var here: String = ProjectSettings.globalize_path(CAPTURE_DIR.path_join(file_name))
	print("PHONE %s" % _line(["pull", far, here]).strip_edges().replace("\n", " | "))


## Throw the device's log away, so that whatever is read next was published after this moment.
func _clear_the_log() -> void:
	_line(["shell", "run-as", PACKAGE, "rm", "-f", "files/probe.log"])
	print("PHONE the log is cleared: what is printed below was published after this moment")


## The screen as it is now, pulled back as a file - the reading the block above cannot give, because a block is
## published at a moment and the glass has no history at all.
func _photograph_the_screen() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIR))
	_save_a_screenshot(THE_SCREEN_NOW)


## A region of the picture just pulled, written out **twice as big**, so that what a person has to judge - two sets
## of words in one band, a bar's height as it was drawn, a letter - can be looked at instead of guessed at.
##
## The path is the picture's own pixels, which is the space a block's rectangles are also in, so a region read off a
## `page`, `drawn` or `overlap` line can be handed straight over. Both paths are globalised because this is the
## filesystem's business and not the engine's: a `res://` path reaches the file manager of an editor but not a
## `save_png`.
func _crop_the_picture(asked: PackedStringArray) -> void:
	var region: Rect2i = the_region(asked)
	if region.size.x <= 0 or region.size.y <= 0:
		print("PHONE `--crop` wants four numbers - x y width height, in the picture's own pixels - and no crop was")
		print("      written.")
		return
	var shot: String = ProjectSettings.globalize_path(CAPTURE_DIR.path_join(THE_SCREEN_NOW))
	var picture: Image = ScreenshotReaderScript.read(shot)
	if picture == null:
		print("PHONE there is no picture at %s to crop: the pull above did not land." % shot)
		return
	var cut: Image = ScreenshotReaderScript.doubled(picture, region)
	if cut == null:
		print(
			"PHONE the region %s does not meet the picture, which is %d x %d - so there is nothing there to show."
			% [str(region), picture.get_width(), picture.get_height()]
		)
		return
	var to: String = ProjectSettings.globalize_path(CAPTURE_DIR.path_join(THE_CROP))
	if ScreenshotReaderScript.write(cut, to) != OK:
		print("PHONE the crop could not be written to %s" % to)
		return
	print("PHONE the crop of %s, doubled, is %s (%d x %d)" % [str(region), to, cut.get_width(), cut.get_height()])
	print("      That is the screen's own pixels, the same space a block's rectangles are in.")


## Press the control whose words hold `words`, at the centre the program itself published for it.
##
## The block is read **first and once**: what is pressed and what the reading afterwards is about are then the same
## moment, rather than two trips to the device that a passing second can come between.
func _press_a_control(words: String) -> void:
	var before: String = _line(["exec-out", "run-as", PACKAGE, "cat", "files/probe.log"])
	var block: PackedStringArray = newest_block(before)
	if block.is_empty():
		print("PHONE the device holds no block to read a centre from, so nothing was pressed")
		return
	var found: Dictionary = press_words(block, words)
	if not bool(found["found"]):
		print("PHONE %s" % found["said"])
		return
	var at: Vector2i = found["at"]
	_tapped = at
	_sent_a_tap = true
	print("PHONE pressing \"%s\" at (%d, %d), the centre the block published:" % [words, at.x, at.y])
	print("      %s" % String(found["line"]))
	_line(["shell", "input", "tap", str(at.x), str(at.y)])
	await _says_a_press_landed(before, "the press", 5.0)


## One drag, and then the honest question about it.
##
## A drag exists here for one reason: a control below a scroller is not drawn, so it is not in the block, so
## `--press` cannot find it. Whether the drag makes that control *readable* is the program's business rather than
## this tool's - a block is published when a page is shown, moved or resized, or when the bar is rebuilt - so this
## asks whether the log grew a block and says which answer it got, rather than letting a stale block be read as the
## screen the drag made.
func _drag(from: Vector2i, to: Vector2i, milliseconds: int) -> void:
	var before: String = _line(["exec-out", "run-as", PACKAGE, "cat", "files/probe.log"])
	print("PHONE dragging (%d, %d) to (%d, %d) over %d ms" % [from.x, from.y, to.x, to.y, milliseconds])
	_line(["shell", "input", "swipe", str(from.x), str(from.y), str(to.x), str(to.y), str(milliseconds)])
	if await _says_a_press_landed(before, "the drag", 3.0):
		print("      so anything read below is the screen after it")
	else:
		print("      so what is below is the screen **before** the drag. A scrolled control is brought into view")
		print("      but not yet readable here: a block is published when the pages up change, and a scroll changes")
		print("      neither which pages are up nor where they stand.")


## Whether the device published a block other than the one it held - asked of the log rather than waited out with
## a stopwatch, because a block is published when the screen actually changes and a pause says nothing at all.
##
## It answers with the wait it took, so a caller can say how long a thing took rather than only that it happened.
func _says_a_press_landed(before: String, what: String, seconds: float) -> bool:
	var held: int = blocks_in(before).size()
	var waited: float = 0.0
	while waited < seconds:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
		if blocks_in(_line(["exec-out", "run-as", PACKAGE, "cat", "files/probe.log"])).size() != held:
			print("PHONE %s landed: the log gained a block after %.1f s" % [what, waited])
			return true
	print("PHONE %s published no fresh block in %.0f s" % [what, seconds])
	return false


## Send one BACK and let the device say when the screen changed, rather than waiting out a stopwatch.
##
## It gathers everything a caller needs to word the answer and decides nothing: the log it held, the log it has
## afterwards, what the newest block before the press named, whether a block arrived, and how long that took.
##
## **One press.** Android 36 reports a single BACK **twice**, 354 ms apart (measured, and filed upstream), so
## pressing again to make sure would send a second BACK the board reads as the quit guard.
func _send_a_back() -> Dictionary:
	var before: String = _line(["exec-out", "run-as", PACKAGE, "cat", "files/probe.log"])
	var had_a_page: bool = a_block_names_a_page(newest_block(before))
	var held: int = blocks_in(before).size()
	print("PHONE one BACK")
	_line(["shell", "input", "keyevent", "4"])
	var after: String = before
	var gained: bool = false
	var waited: float = 0.0
	while waited < 8.0 and not gained:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
		after = _line(["exec-out", "run-as", PACKAGE, "cat", "files/probe.log"])
		gained = blocks_in(after).size() != held
	return { "before": before, "after": after, "had_a_page": had_a_page, "gained": gained, "waited": waited }


## One BACK, and then what the log says about it.
##
## **The program says a block for a page being put away as readily as for one arriving** - but it did not until
## 2026-11-14, and the way that was found is worth keeping. A BACK that the picture proved had landed left the
## newest block still naming the page it had put away, because the block came from signals connected to the pages
## that existed when the program started and a page built later was never watched. `Hud` asks the *screen* now (see
## its `_notice_the_pages_changing`), so a page leaving is a block like any other change. A build on the device that
## is older than that fix answers the old way, which is why the branch that finds nothing published says so and
## points at the picture rather than calling the press a failure. `--blocks` reads the same list out of logcat.
func _go_back() -> void:
	var back: Dictionary = await _send_a_back()
	var had_a_page: bool = bool(back["had_a_page"])
	var gained: bool = bool(back["gained"])
	var waited: float = float(back["waited"])
	if gained:
		print(
			"PHONE the screen changed: the log gained a block after %.1f s, and its newest names %s"
			% [waited, "a page" if _a_page_is_still_up() else "no page"]
		)
	elif had_a_page:
		# Until 2026-11-14 this was the ordinary answer, because a page built after the program started was never
		# watched and its leaving published nothing at all. The program asks the screen now, so reaching here means
		# either a build older than that fix or a BACK the program did not take, and the picture tells them apart.
		print(
			"PHONE nothing was published in %.0f s, with a page named before the press - so either this build is"
			% waited
		)
		print("      older than the fix that made a page **leaving** say a block like any other change, or a BACK")
		print("      that did not land. The picture this run took tells the two apart, and for an older build the")
		print("      recipe is to count the program's own block headings in logcat either side of the press.")
	else:
		print("PHONE the newest block named no page before the press either, so nothing was standing for BACK to")
		print("      put away. What is below is the screen as it already was.")


## Put everything standing in front of the board away: BACK until the newest block names no page.
##
## **The state a driver wants before reading the board**, and the one `--overlay` most wants to be looking at. Every
## BACK here is the press `--back` sends, waited for rather than guessed at, so the loop can end. It stops after
## `MAX_PAGES_TO_CLEAR` and says which page is still up rather than pressing on: a page that will not go away is
## something to read, not something to insist on.
func _clear_the_pages() -> void:
	var step: int = 0
	var block: PackedStringArray = newest_block(_line(["exec-out", "run-as", PACKAGE, "cat", "files/probe.log"]))
	while a_block_names_a_page(block) and step < MAX_PAGES_TO_CLEAR:
		step += 1
		var back: Dictionary = await _send_a_back()
		block = newest_block(String(back["after"]))
		print("PHONE BACK %d: the newest block names %s" % [step, page_names_in(block)])
	if a_block_names_a_page(block):
		print("PHONE %d BACK(s) and %s is still up. Nothing here presses on:" % [step, page_names_in(block)])
		print("      a page that will not go away is something to read, and the picture is where to read it.")
	else:
		print("PHONE the board is clear after %d BACK(s): the newest block names no page" % step)


## The pages one block named, in the words a driver reads: `no page`, or a count and the names.
static func page_names_in(block: PackedStringArray) -> String:
	var names: PackedStringArray = PackedStringArray()
	for line: String in block:
		if not line.begins_with("page "):
			continue
		var rest: String = line.substr(5).strip_edges()
		if not rest.is_empty():
			names.append(rest.split(" ", false)[0])
	if names.is_empty():
		return "no page"
	return "%d page(s): %s" % [names.size(), ", ".join(names)]


## Press one key the device's own input can send. **What the key did is asked of the log**, not waited out: a key
## that changes the pages says so with a block, and a key that does not is answered by the absence - the honest
## reading for a key that moved nothing and for one the program never received, which are two faults a person wants
## to tell apart and a pass cannot yet.
func _send_a_key(key_name: String) -> void:
	var code: int = the_key_number(key_name)
	if code < 0:
		print("PHONE %s" % key_words(key_name))
		print("      so nothing was sent.")
		return
	var before: String = _line(["exec-out", "run-as", PACKAGE, "cat", "files/probe.log"])
	print("PHONE pressing %s (keyevent %d)" % [key_name.to_lower(), code])
	_line(["shell", "input", "keyevent", str(code)])
	if not await _says_a_press_landed(before, "the key", 3.0):
		print("      so it changed nothing the program publishes: a page would have published a block, while a tool")
		print("      in hand and a scroll publish none - and so does a key the program never received.")


## The number a key's name stands for, or -1 for one this tool will not send. A name nobody has is answered the
## same way, so a caller has one thing to test rather than two.
static func the_key_number(key_name: String) -> int:
	return int(KEYS.get(key_name.to_lower(), -1))


## Why a key this tool will not send is not sent. **Two of these are measurements and not policy.**
##
## `escape` (`input keyevent 111`) never reached this program at all: it left the phone's own *USB settings* panel
## on the screen while the tool went on drawing into that. The cancel this program has is `draft_cancel`, a button
## in the palette - and BACK reaches it too, because the ladder puts a tool in hand away first. **A single
## character** is the other: `input keyevent 8`, the `1` key `draft_line` is bound to, did nothing at all, two
## screenshots a minute apart byte-identical. No tool is put in hand by a key; the palette's own cell is tapped, at
## the centre `--taps` prints.
static func key_words(key_name: String) -> String:
	var lower: String = key_name.to_lower()
	if lower == "escape" or lower == "esc" or lower == "111":
		return (
			"`escape` is not sent: measured on the A16W, `input keyevent 111` never reached this program - it left"
			+ " the phone's own USB settings panel on the screen. The cancel this program has is `draft_cancel`, a"
			+ " button in the palette, and BACK reaches it as well."
		)
	if lower.length() == 1:
		return (
			"a single character is not sent: measured on the A16W, `input keyevent 8` - the `1` key `draft_line` is"
			+ " bound to - did nothing at all, two screenshots a minute apart byte-identical. No tool is put in hand"
			+ " by a key: `--taps` prints the palette cell's own centre, and tapping that is what works."
		)
	return "`%s` is not a key this tool knows: it sends %s." % [key_name, ", ".join(PackedStringArray(KEYS.keys()))]


## What the phone's own glass says, out of the blocks the text handed over holds: the newest for the density, and
## **all of them together for the scale** - through `HudProbe`'s own two readers, so that the line's writer and its
## reader stay one thing.
##
## **A phone answers its scale differently in each orientation** - 0.91 upright and 1.62 on its side, on the A16W -
## and a rotation publishes a block, so a log that has seen both is a log that knows both. Reading every block is
## what lets a scale a file states be *judged* rather than only named as one this block cannot judge, and it costs
## nothing: the log has already been pulled off the phone. The density comes from the newest block alone, since one
## glass has one.
##
## A text with no block heading in it is read as one block rather than refused, so a caller holding a fragment gets
## the same answer. Nothing at all is **no reading**, never a zero to compare a file's number against.
static func the_phones_numbers(kept: String) -> Dictionary:
	var blocks: Array[String] = blocks_in(kept)
	if blocks.is_empty():
		blocks.append(kept)
	var scales: Array[float] = []
	for one: String in blocks:
		var got: float = HudProbeScript.read_device_scale(one)
		if got <= 0.0:
			continue
		var known: bool = false
		for had: float in scales:
			if absf(got - had) <= NEAR_ENOUGH:
				known = true
		if not known:
			scales.append(got)
	scales.sort()
	var newest: String = blocks[blocks.size() - 1]
	return {
		"dpi": HudProbeScript.read_device_density(newest),
		"scale": HudProbeScript.read_device_scale(newest),
		"scales": scales,
		"blocks": blocks.size(),
	}


## The scales a phone's blocks state, as a person reads them - `0.91 and 1.62` - to two places, because that is
## how the block itself writes them. One place words this, for the greeting line and for a fault alike.
static func _scales_text(scales: Array) -> String:
	var shown: PackedStringArray = PackedStringArray()
	for one: Variant in scales:
		shown.append("%.2f" % float(one))
	return " and ".join(shown)


## The numbers **one file** states for a phone, sorted against what the phone itself says:
## `{ "disagrees": [...], "not_this_way_up": [...], "agreed": n }`, each entry the path, the line and the words.
##
## **The fault this exists for.** A device's numbers get written down - a fixture in a tool, a constant in a test -
## and they go stale the moment the device does. Three test fixtures carried `PHONE_DPI := 384.6` while the A16W
## reports 450.0, which is a fixture pinning a phone nobody has - and no desk test can say so, because a desk has
## no phone to disagree with. The check found them on its first live run, 2026-11-17, and they were corrected; it
## stays because the next fixture will be written by somebody who has not measured the device.
##
## **What it looks for, and what it cannot.** A `const <NAME> := <number>` whose name **names the phone** - it
## carries `PHONE` - and ends in `_DPI`/`_DENSITY` (a density) or carries `_SCALE` (a scale, `PHONE_SCALE_UPRIGHT`
## included). Everything else is **not seen**: a number inside a `Vector2i`, a number under another name, a number
## that belongs to another device. That last one is not hypothetical: **the first live run, 2026-11-17, named
## `touch_input.gd`'s `HELD_DPI := 200.0` - the floor below which a device is not one held in a hand - and
## `tablet_demo.gd`'s `TABLET_DPI := 300.0`, a tablet's density, as faults against this phone.** Both are `_DPI`
## constants the phone has every right to disagree with and neither is a number *for this phone*, which is the
## false positive this project's doctrine is written against. The name is the whole basis of the rule, it is said
## here rather than left to be discovered, and the report says how many numbers it found so that a thin look
## cannot pass for a clean one. Every instrument here is a floor, named as a floor.
##
## **The scale is judged against every scale the phone's blocks have stated**, because a phone answers differently
## in each orientation and a rotation publishes a block: a log that has seen both knows both, and a scale matching
## neither is then a **genuine fault**, named with the scales the phone does state. A log holding only one block
## can judge only that one, and a scale matching neither is then named as **one this block cannot judge** rather
## than condemned - a fixture holding the other orientation's 0.91 against a landscape block's 1.62 is right, and
## calling it a fault would be the false positive this project warns about.
##
## **A density is a density whichever way the phone is lying**, so a density that disagrees is always a fault: one
## glass has one.
static func stated_numbers_in(path: String, text: String, said: Dictionary) -> Dictionary:
	var disagreeing: Array[String] = []
	var not_this_way_up: Array[String] = []
	var agreed: int = 0
	var lines := text.split("\n")
	for i in lines.size():
		var line: String = String(lines[i]).strip_edges()
		if not line.begins_with("const "):
			continue
		var told: Dictionary = a_stated_number(line)
		if told.is_empty():
			continue
		var named: String = String(told.get("name", ""))
		var value: float = float(told.get("value", 0.0))
		var where: String = "%s:%d: %s" % [path, i + 1, line]
		if _is_a_density_name(named):
			var density: float = float(said.get("dpi", 0.0))
			if density <= 0.0:
				continue
			if absf(value - density) <= NEAR_ENOUGH:
				agreed += 1
			else:
				disagreeing.append(
					"%s - states %.1f, and the phone's own glass says %.1f" % [where, value, density]
				)
		elif _is_a_scale_name(named):
			var scales: Array = said.get("scales", [])
			if scales.is_empty():
				continue
			var matched: bool = false
			for one: Variant in scales:
				if absf(value - float(one)) <= NEAR_ENOUGH:
					matched = true
			if matched:
				agreed += 1
			elif scales.size() == 1:
				not_this_way_up.append(
					(
						"%s - states %.2f, and the block's glass is %.2f this way up: not this orientation's,"
						% [where, value, float(scales[0])]
					)
					+ " and one run's log cannot say whether it is the other's or has gone stale"
				)
			else:
				disagreeing.append(
					(
						"%s - states %.2f, and this phone's own blocks state %s"
						% [where, value, _scales_text(scales)]
					)
				)
	return {
		"disagrees": disagreeing,
		"not_this_way_up": not_this_way_up,
		"agreed": agreed,
	}


## One line read as a stated number: `{ "name": "PHONE_DPI", "value": 450.0 }`, or nothing at all when the line is
## not a `const` naming a plain number.
##
## A `Vector2i` or a quoted string is deliberately **nothing** rather than a zero: `String.to_float` reads a number
## only where one begins, and a zero would then be compared with a phone's own answer and reported as a fault the
## file never stated. The one shape a name may take is `NAME` or `NAME: Type`, so `:=` and `=` read alike.
static func a_stated_number(line: String) -> Dictionary:
	if not line.begins_with("const "):
		return {}
	var rest: String = line.trim_prefix("const ").strip_edges()
	var shut: int = rest.find("=")
	if shut < 0:
		return {}
	var left: String = rest.substr(0, shut).strip_edges()
	var named: String = left
	var colon: int = left.find(":")
	if colon >= 0:
		named = left.substr(0, colon).strip_edges()
	var value: String = rest.substr(shut + 1).strip_edges()
	if value.is_empty() or not "0123456789+-".contains(value.substr(0, 1)):
		return {}
	return { "name": named, "value": value.to_float() }


## Whether a constant's name claims to be **this phone's** density, or its scale - the reason `HELD_DPI` and
## `TABLET_DPI` are left alone, which the doc above records the live run saying.
static func _is_a_density_name(named: String) -> bool:
	return named.contains("PHONE") and (named.ends_with("_DPI") or named.ends_with("_DENSITY"))


static func _is_a_scale_name(named: String) -> bool:
	return named.contains("PHONE") and (named.ends_with("_SCALE") or named.contains("_SCALE_"))


## Every `.gd` in the three trees that hold this project's own code, sorted so a report names the same files in the
## same order every time - the walk `files_since` already makes for its own question, asked for this one.
static func _files_that_state_a_number() -> Array[String]:
	var found: Array[Dictionary] = []
	for root: String in STATED_ROOTS:
		_gather(root, [".gd"], found)
	var out: Array[String] = []
	for one: Dictionary in found:
		out.append(String(one.get("path", "")))
	out.sort()
	return out


## Whether the build on disk is still the work in hand, and the line to make a new one when it is not.
##
## The mistake this exists to prevent is the one a phone makes easy: reading a screen that the program in hand has
## never been given. Age says how long ago the disk was written and nothing about the device - and the other half
## of that question, what the phone is *actually* running, is `--installed`'s, which hashes the copy installed on it
## rather than inferring anything from a clock.
func _report_the_build() -> void:
	var made: int = FileAccess.get_modified_time(APK)
	var since: Dictionary = files_since(REBUILD_ROOTS, REBUILD_SUFFIXES, made)
	print("PHONE %s" % build_words(made, since, int(Time.get_unix_time_from_system())))
	if int(since.get("count", 0)) > 0:
		print("      %s" % export_words())


## The numbers this project states for a phone, against the phone's own answer - **the one check a desk cannot
## make**, and the reason this is asked of a device rather than of the tree.
##
## It names every file and line that disagrees, says how much it read so that a clean pass cannot be mistaken for a
## check with nothing in front of it, and names separately the numbers a single block cannot judge.
func _report_the_stated_numbers(kept: String) -> void:
	var said: Dictionary = the_phones_numbers(kept)
	print("")
	print("--- the numbers this project states for a phone ---")
	var density: float = float(said.get("dpi", 0.0))
	if density <= 0.0:
		print("  the blocks in the log state no density, so there is nothing to check a file's numbers against.")
		print("  A device in reach with `--launch` publishes one; without a phone this cannot be asked at all.")
		return
	print(
		"  the phone's own glass, out of the %d block(s) in the log: dpi=%.1f, and the scale(s) %s"
		% [int(said.get("blocks", 0)), density, _scales_text(said.get("scales", []))]
	)
	var paths: Array[String] = _files_that_state_a_number()
	var agreed: int = 0
	var disagreeing: Array[String] = []
	var not_this_way_up: Array[String] = []
	for path: String in paths:
		var here: Dictionary = stated_numbers_in(path, FileAccess.get_file_as_string(path), said)
		agreed += int(here.get("agreed", 0))
		var against: Array = here.get("disagrees", [])
		for one: Variant in against:
			disagreeing.append(str(one))
		var unjudged: Array = here.get("not_this_way_up", [])
		for one: Variant in unjudged:
			not_this_way_up.append(str(one))
	var stated: int = agreed + disagreeing.size() + not_this_way_up.size()
	print("  read %d file(s) and found %d number(s) stated for a phone" % [paths.size(), stated])
	if disagreeing.is_empty():
		print("  none of them disagrees with this phone.")
	else:
		print("  ** these disagree with this phone:")
		for one: String in disagreeing:
			print("     %s" % one)
	if not not_this_way_up.is_empty():
		print("  and these no single run's block can judge: **a phone states one scale per orientation**, and this")
		print("  log holds one run's blocks - measured 2026-11-17, a landing run clears the device's log and a")
		print("  rotation publishes no block at all. Run this again held the other way up and read both reports:")
		for one: String in not_this_way_up:
			print("     %s" % one)
	if stated == 0:
		print("  ** nothing at all was looked at, so this proves nothing: a number under another name, or inside")
		print("     a Vector, is not seen by this check.")


## Whether the phone is running the build on disk, by the only reading that can say so: the hash of the copy it has
## installed against the hash of the file here.
##
## **This closes the one thing the tool used to have to disclaim.** Age says how long ago the disk was written and
## nothing at all about the device; only an install could say what the phone held, and an install is a step this
## tool *takes* rather than a reading it makes. A hash is the reading: two files with one MD5 are one file, so "the
## same build" becomes a fact. The path is the phone's own answer (`pm path`), read past the word `package:` it
## carries, and the hash is its own `md5sum` of that file - so nothing here assumes where a program is installed.
func _report_what_the_phone_runs() -> void:
	var here: String = FileAccess.get_md5(ProjectSettings.globalize_path(APK))
	var named: String = apk_path_from(_line(["shell", "pm", "path", PACKAGE]))
	print("")
	print("--- what the phone is running ---")
	if named.is_empty():
		print("  the phone would not name its own copy (`pm path %s`), so nothing is claimed about it" % PACKAGE)
		return
	var there: String = hash_of(_line(["shell", "md5sum", named]))
	if there.is_empty():
		print("  the phone has %s but would not read it, so nothing is claimed about it" % named)
		return
	print("  the copy installed on it  %s" % there)
	print("  the build on this disk    %s" % here)
	if here == there:
		print("  the phone is running exactly this build")
	else:
		print("  ** they are not the same build: the phone is running something else. `--install` is what puts this")
		print("     one on it, and the age above says how old the one on the disk is.")


## The path `pm path` named for this program: the file the phone has installed. An app installed as split APKs
## answers with several lines and the base one is the file an install replaces, so the first `.apk` is taken.
static func apk_path_from(pm_path: String) -> String:
	for raw: String in pm_path.split("\n"):
		var line: String = raw.strip_edges()
		if not line.begins_with("package:"):
			continue
		var path: String = line.substr(8).strip_edges()
		if path.ends_with(".apk"):
			return path
	return ""


## The hash out of an `md5sum` line, which carries the hash first and the file it read second - or nothing when the
## phone refused to read the file at all, which is an answer and not a hash of nothing.
static func hash_of(md5sum: String) -> String:
	for raw: String in md5sum.split("\n"):
		var line: String = raw.strip_edges()
		if line.is_empty():
			continue
		var first: String = line.split(" ", false)[0]
		if first.length() == 32:
			return first
	return ""


## The line that makes a new build, written the way this tool's own header and the manual write it.
##
## `APK` wears a project path because that is how a file is opened and timed from here, and the engine is not told
## where to put a file that way: printing the constant straight out handed a person `res://build/phone-adapt.apk`,
## which is neither the line in the two other places nor how the engine is asked.
static func export_words() -> String:
	return (
		"GODOT_MCP_RUNTIME=0 <godot> --headless --path . --export-debug \"Android (phone)\" %s"
		% APK.trim_prefix("res://")
	)


## Why the build on disk has to be made again, or **nothing at all** when it is still the work in hand.
##
## This is the rule `--build` runs on, and it is the same one `_report_the_build` states a person's evidence with -
## so the tool cannot call a build stale in one line and current in the next. Three things make a build stale: a
## script or a scene written after it, the preset written after it (a preset decides what a build *contains*), and
## a tree that cannot be walked at all - which is answered by making a build rather than by trusting an age.
##
## **An empty answer is the answer** - the shape `hash_of`, `apk_path_from` and `the_word_after` already have - and
## it is what says no export is worth spending a minute on.
static func rebuild_reason(made: int, since: Dictionary, preset: int, now: int) -> String:
	if made <= 0:
		return "there is no build at %s yet" % APK
	if not bool(since.get("readable", false)):
		return "the tree could not be walked from here, so this makes a build rather than trusting an age"
	if preset > made:
		return (
			"%s has been written since the build, and a preset decides what a build contains"
			% PRESET.trim_prefix("res://")
		)
	if int(since.get("count", 0)) == 0:
		return ""
	return build_words(made, since, now)


## The engine's own argv for making that build. `export_words` is the same command written out for a person to
## copy, and the two are kept beside each other so a change to one is a change to the other.
##
## **Both paths are absolute**, and that is the one thing here that must not depend on where a person stood: the
## project is named with `--path` and the file to write is named in full, so a tool started from another directory
## builds this project rather than whatever is beside the shell.
static func export_argv() -> Array[String]:
	var argv: Array[String] = [
		"--headless",
		"--path",
		ProjectSettings.globalize_path("res://"),
		"--export-debug",
		PRESET_NAME,
		ProjectSettings.globalize_path(APK),
	]
	return argv


## Make the build, or say plainly that the one on disk is still the work in hand. False when the export refused,
## and the caller stops on a false: nothing below it would be a reading of the change that was asked for.
##
## **The engine is run with `GODOT_MCP_RUNTIME=0` in its environment**, which is not a detail of taste: without it
## the export's own process binds this project's runtime port and claims the entry a real game session uses. It is
## set around the one call that starts the process and put straight back, because the child reads it as it is
## spawned and nothing after that asks for it.
##
## **It is started and then polled rather than waited on** (`create_process`, not `execute`), so the engine's own
## words reach the terminal while it works. `OS.execute` captures them, and a two-minute export that says nothing
## at all is a tool somebody interrupts. The ceiling is what stops a wedged export being waited on for ever.
func _make_the_build() -> bool:
	var made: int = FileAccess.get_modified_time(APK)
	var since: Dictionary = files_since(REBUILD_ROOTS, REBUILD_SUFFIXES, made)
	var preset: int = FileAccess.get_modified_time(PRESET)
	var now: int = int(Time.get_unix_time_from_system())
	var why: String = rebuild_reason(made, since, preset, now)
	if why.is_empty():
		print(
			"PHONE nothing was exported: the build on disk is %s old, and nothing that reaches the phone - and"
			% age_words(maxi(now - made, 0))
			+ " no preset - has been written since"
		)
		return true
	print("PHONE making a build, because %s" % why)
	print("PHONE %s %s" % [OS.get_executable_path(), " ".join(PackedStringArray(export_argv()))])
	var was_the_bridge: String = OS.get_environment("GODOT_MCP_RUNTIME")
	OS.set_environment("GODOT_MCP_RUNTIME", "0")
	var pid: int = OS.create_process(OS.get_executable_path(), PackedStringArray(export_argv()))
	OS.set_environment("GODOT_MCP_RUNTIME", was_the_bridge)
	if pid <= 0:
		print("PHONE the engine would not start at all, so there is no build to put on the phone.")
		return false
	var waited: float = 0.0
	while OS.is_process_running(pid) and waited < EXPORT_CEILING:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	if OS.is_process_running(pid):
		print(
			"PHONE the export is still running after %d s, and this stops waiting for it: the engine's process is"
			% int(EXPORT_CEILING)
		)
		print("      still going (pid %d) and %s may be half written. Nothing was put on the phone." % [pid, APK])
		return false
	var code: int = OS.get_process_exit_code(pid)
	if code != 0:
		print(
			"PHONE the export ended with %d, so what would go on the phone is the last build, and it was not sent."
			% code
		)
		print("      The engine's own words are above this line.")
		return false
	print("PHONE the build is made: %s" % APK)
	return true


## Every file under these roots, and the newest of them, measured against the moment a build was made.
##
## `readable` is the honest half: an exported program cannot list `res://` at all, so a walk that found nothing
## says nothing about the build and must not be read as a tree that has held still.
static func files_since(roots: Array[String], suffixes: Array[String], when: int) -> Dictionary:
	var found: Array[Dictionary] = []
	var read_any: bool = false
	for root: String in roots:
		if DirAccess.open(root) == null:
			continue
		read_any = true
		_gather(root, suffixes, found)
	if not read_any:
		return { "count": 0, "newest": 0, "path": "", "readable": false }
	var newer: Array[Dictionary] = []
	for one: Dictionary in found:
		if int(one["when"]) > when:
			newer.append(one)
	if newer.is_empty():
		return { "count": 0, "newest": 0, "path": "", "paths": PackedStringArray(), "readable": true }
	# **Newest first**, so the few a person is shown are the ones most likely to matter, while the count still
	# carries the whole of it.
	newer.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["when"]) > int(b["when"]))
	var paths: PackedStringArray = PackedStringArray()
	for one: Dictionary in newer:
		paths.append(String(one["path"]))
	return {
		"count": newer.size(),
		"newest": int(newer[0]["when"]),
		"path": String(newer[0]["path"]),
		"paths": paths,
		"readable": true,
	}


## One directory's files, and its subdirectories', gathered into `into` - so that a walk is a walk and the suffix
## test lives in one place. A directory that cannot be opened is skipped rather than raised.
static func _gather(dir_path: String, suffixes: Array[String], into: Array[Dictionary]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	for file_name: String in dir.get_files():
		var wanted: bool = false
		for suffix: String in suffixes:
			if file_name.ends_with(suffix):
				wanted = true
		if not wanted:
			continue
		var full: String = dir_path.path_join(file_name)
		into.append({ "path": full, "when": FileAccess.get_modified_time(full) })
	for sub: String in dir.get_directories():
		if sub.begins_with("."):
			continue
		_gather(dir_path.path_join(sub), suffixes, into)


## How many of the changed files are named before the rest are counted.
##
## **Naming the newest few is what turns a count into a judgement.** "3 script(s) or scene(s) have changed since"
## says a build may be stale; which three says whether it matters - measured 2026-11-17, a build 66 minutes old
## had three changed files that were a comment correction and the moved demo scenes, so it *was* the work in hand
## in everything but its comments, and the behavioural proof was the new line the block published besides.
const FILES_NAMED := 3


## What the build on disk is, in words, against the tree.
##
## The build is stamped by **how long ago it was made** rather than by a clock time: a unix time printed back is
## in UTC, and this desk is not, so "14:44" would be four or five hours from what a person sees in their file
## manager. An age cannot be wrong about that.
static func build_words(made: int, since: Dictionary, now: int) -> String:
	if made <= 0:
		return "there is no build at %s yet, so nothing here is running the work in hand: make one" % APK
	if not bool(since.get("readable", false)):
		return (
			"the build on disk is %s old, and the tree could not be walked from here - an exported program cannot"
			% age_words(maxi(now - made, 0))
			+ " list res:// - so this says nothing about whether it is still the work in hand"
		)
	var count: int = int(since.get("count", 0))
	if count == 0:
		return (
			"the build on disk is %s old, and no script or scene in the tree has changed since, so it is the work"
			% age_words(maxi(now - made, 0))
			+ " in hand"
		)
	var named: String = String(since.get("path", ""))
	var paths: PackedStringArray = since.get("paths", PackedStringArray())
	if paths.size() > 0:
		var shown: PackedStringArray = paths.slice(0, mini(FILES_NAMED, paths.size()))
		named = ", ".join(shown)
		if paths.size() > shown.size():
			named += " and %d more" % (paths.size() - shown.size())
	return (
		"the build on disk is %s old, and %d script(s) or scene(s) have changed since - %s, so this"
		% [age_words(maxi(now - made, 0)), count, named]
		+ " is not what the phone would be running"
	)


## A count with the unit a person would say after it - singular when the count is one, so that an age reads
## "1 hour" rather than "1 hours". One plural rule for all three units, in the one place that words an age.
static func _counted(count: int, unit: String) -> String:
	return "%d %s" % [count, unit if count == 1 else unit + "s"]


## A length of time as a person says it.
##
## **The singular is a reading somebody can be shown, not a nicety.** This words the age of a block as well as of a
## build, and a block is published the moment a screen changes: without this, a build an hour and a half old read
## "1 hours old" and a block one second old would read "1 seconds ago". Found by running the tool on 2026-11-17.
static func age_words(seconds: int) -> String:
	if seconds < 90:
		return _counted(seconds, "second")
	# Whole minutes and whole hours, and `floori` rather than a bare `/`: an integer division warns, and this
	# project's warnings are errors. The same sum `Analytics._hours_text` works out for a sentence about time.
	if seconds < 5400:
		return _counted(floori(float(seconds) / 60.0), "minute")
	return _counted(floori(float(seconds) / 3600.0), "hour")


## What the hold on the device says, in words - and the trap this exists to catch.
##
## The board obeys `OrientationChoice`'s own hold in `user://orientation.json`, and `stored()` parses it with
## `JSON.new().parse` and refuses anything unreadable **by design**: never having chosen and having chosen the
## default are the same answer. The file the A16W was found holding read `{orientation:portrait}` - the key
## unquoted, which is not JSON - so the hold fell back to the wide default and the board reported `shape=lying`.
## That is why portrait looked impossible to force for a whole session, and why this is asked **before** anything
## is launched rather than afterwards, off a screenshot nobody has looked at yet.
static func hold_words(text: String) -> String:
	var said: String = text.strip_edges()
	if said.is_empty():
		return "the device has no orientation.json at all, so the board takes the wide default"
	# The **same reader the hold itself uses**, so that a file this reads as upright is one `OrientationChoice.
	# stored()` reads as upright too. It is not `JSON.parse_string`: that one writes an engine error for text it
	# cannot read, and an instrument that puts an error into an otherwise clean run is a fault of its own.
	var reader: JSON = JSON.new()
	if reader.parse(said) != OK:
		return (
			"the device's orientation.json is not readable JSON (%s), and an unreadable hold is refused by design,"
			% said
			+ " so the board takes the wide default"
		)
	var held: Variant = reader.data
	if held is Dictionary:
		var chosen: Variant = (held as Dictionary).get("orientation", "")
		if String(chosen) == "portrait":
			return "the board is held upright (%s)" % said
	return "the board is not held upright (%s), so a capture would be the other way up" % said


## Which way up `--turn` was asked to hold the device: one of `TURNS`' words, or `auto`, or nothing at all when it
## was not asked for. A word this does not know reads as **not asked**, so a typo never holds a phone at random.
static func turn_of(asked: PackedStringArray) -> String:
	var wanted: String = the_word_after(asked, "--turn")
	if wanted == "auto" or TURNS.has(wanted):
		return wanted
	return ""


## A word for which way up a phone is, in the program's own vocabulary: the board reports `shape=lying` of a room
## wider than it is tall, and `hold_words` says "held upright" of the other.
static func the_way_up(wanted: String) -> String:
	if wanted == "portrait":
		return "upright"
	return "lying"


## What the device says about which way up it is, in words.
##
## **Read back off the device rather than assumed from the command**, which is the whole point of it: a
## `settings put` that was refused looks exactly like one that was obeyed until something is read, and a report
## that states the command is a report of an intention. So this says what was asked for, what the device actually
## reports, and refuses to call it held when it is not.
static func turn_words(wanted: String, rotation: String, auto: String) -> String:
	if wanted.is_empty():
		return ""
	var rotation_said: String = rotation.strip_edges()
	var auto_said: String = auto.strip_edges()
	if wanted == "auto":
		if auto_said == "1":
			return "the device is taking its own answer again (accelerometer_rotation=1)"
		return (
			"the device would not go back to its own answer: it reports accelerometer_rotation=%s" % auto_said
		)
	if auto_said == "0" and rotation_said == String(TURNS.get(wanted, "")):
		return (
			"the device is held %s: it reports user_rotation=%s with auto-rotate off"
			% [the_way_up(wanted), rotation_said]
		)
	return (
		"the device would NOT take the hold: `--turn %s` asks for user_rotation=%s with auto-rotate off, and it"
		% [wanted, String(TURNS.get(wanted, ""))]
		+ " reports user_rotation=%s, accelerometer_rotation=%s" % [rotation_said, auto_said]
	)


## Hold the device the way `--turn` asked, remembering what it held before so the run can hand it back.
##
## **The program reads this when it starts**, which is why the useful form of it is `--turn landscape --launch`:
## whatever is already on the screen keeps the shape it was given. `_photograph_the_screen` then photographs it as
## held, and the picture is the reason to hold it at all.
func _turn_the_device(wanted: String) -> void:
	_was_auto = _line(["shell", "settings", "get", "system", "accelerometer_rotation"])
	_was_rotation = _line(["shell", "settings", "get", "system", "user_rotation"])
	_turned = true
	if wanted == "auto":
		_line(["shell", "settings", "put", "system", "accelerometer_rotation", "1"])
	else:
		_line(["shell", "settings", "put", "system", "accelerometer_rotation", "0"])
		_line(["shell", "settings", "put", "system", "user_rotation", String(TURNS.get(wanted, "0"))])
	var rotation: String = _line(["shell", "settings", "get", "system", "user_rotation"])
	var auto: String = _line(["shell", "settings", "get", "system", "accelerometer_rotation"])
	print("PHONE %s" % turn_words(wanted, rotation, auto))


## Hand the device's own rotation back, exactly as it was found, and only if this run changed it.
##
## **Called on every way out that could have got past the turn** - the capture's own return, a build that would not
## be made, and the end of the pass - which is the discipline the phone demos already keep. A phone left locked in
## a landscape nobody chose is a phone its owner has to go and fix by hand, and this tool has no business doing
## that to somebody's handset. A value the device would not give is left alone rather than written as empty.
func _put_the_screen_back() -> void:
	if not _turned:
		return
	_turned = false
	if not _was_auto.strip_edges().is_empty():
		_line(["shell", "settings", "put", "system", "accelerometer_rotation", _was_auto.strip_edges()])
	if not _was_rotation.strip_edges().is_empty():
		_line(["shell", "settings", "put", "system", "user_rotation", _was_rotation.strip_edges()])
	print(
		"PHONE the device's own rotation is put back: accelerometer_rotation=%s, user_rotation=%s"
		% [_was_auto.strip_edges(), _was_rotation.strip_edges()]
	)


## Where adb is: the SDK copy this project was driven from, or a bare one on the path.
func _find_adb() -> String:
	if FileAccess.file_exists(ADB):
		return ADB
	var check: Array = []
	if OS.execute("adb", PackedStringArray(["version"]), check) == 0:
		return "adb"
	return ""


## One adb command, its text handed back - this call's output and not a word of anything earlier.
func _line(arguments: Array[String]) -> String:
	var output: Array = []
	var code: int = OS.execute(_adb_path, PackedStringArray(arguments), output, true)
	if code != 0:
		print("PHONE adb %s ended with %d" % [arguments[0], code])
	var text: String = ""
	for part: Variant in output:
		text += str(part)
	return text


## The first line of something, for a one-line summary of a command that answers in several.
func _first_line(text: String) -> String:
	var lines: PackedStringArray = text.strip_edges().split("\n")
	return lines[0] if lines.size() > 0 else ""


## How long the program is given to publish its first block, from `--wait N` - the **ceiling** on that wait rather
## than the wait itself, since the block arriving is what ends it. It is the one number here a slow phone may want
## more of: measured on the A16W, 2026-11-14, a cold start had published nothing eight seconds after the launch,
## and a `--press` in the same command then found no centre to press at.
func _wait_seconds(asked: PackedStringArray) -> int:
	var at: int = asked.find("--wait")
	if at < 0 or at + 1 >= asked.size():
		return 14
	return maxi(int(asked[at + 1]), 2)


## Whether a phone is actually in reach, read off `adb devices -l`'s own table.
##
## The header is always `List of devices attached`, so the word `device` on its own proves nothing and is found
## inside `devices` besides. What is tested is the **state column** - the second field of a device's own row,
## which is `device` for one that is reachable, and `unauthorized` or `offline` for one that is not yet a device
## this tool can ask anything of. The tab between the serial and the state is why the row is unsplit by a single
## space before it is looked at.
static func a_device_is_here(devices_text: String) -> bool:
	for raw: String in devices_text.split("\n"):
		var fields: PackedStringArray = raw.strip_edges().replace("\t", " ").split(" ", false)
		if fields.size() >= 2 and fields[1] == "device":
			return true
	return false


## What to say about a tap and the **screen** the block it produced was taken on.
##
## **A block publishes its `tap` centres in the screen's own pixels, not the room's.** A centre reads
## `screen (951, 212) .. (1375, 385) centre (1163, 299)` - pixels of the display - while the `room` line's
## `viewport=` figure is the logical room a page is laid out in, 1.62 times smaller on the A16W. Measuring one
## against the other called a press that had plainly landed a miss: measured 2026-11-17, `--press "Design the
## garden"` put (1213, 753) into a 2340 x 1080 screen and this sentence said it was "outside the room ... (1444,
## 666)". The `native=` figure is the space the centres are in, so that is the one it is measured against now -
## `HudProbe.read_screen_line`.
##
## The question the check exists for is unchanged and still answered: a centre copied from a block taken the other
## way up is past the far edge of this screen - measured, a centre at y 1654 against a 1080-tall screen, where the
## viewport figure of 666 would have let it pass as well as calling real presses misses.
##
## `Rect2i` is the engine's own answer to this and it is **exclusive of the far edge** - a point exactly on the
## right or the foot of the screen counts as outside it - which is the honest reading: a tap on the last row of
## pixels is not one the program can be depended on to have received.
##
## A block that names no screen has no answer, and saying so is the point. It is not a tap inside a screen of no
## size, which would read as a clean run.
static func tap_words(tap: Vector2i, screen: Vector2i) -> String:
	if screen.x <= 0 or screen.y <= 0:
		return "the block names no screen to measure the tap at (%d, %d) against" % [tap.x, tap.y]
	if Rect2i(Vector2i.ZERO, screen).has_point(tap):
		return "the tap at (%d, %d) is inside the screen the block was taken on, %s" % [tap.x, tap.y, str(screen)]
	return (
		"the tap at (%d, %d) is outside the screen the block was taken on, %s" % [tap.x, tap.y, str(screen)]
		+ " - nothing on the screen received it. A centre from a block taken the other way up is the usual cause;"
		+ " the block above is not about this tap either way."
	)


## Where to tap, from `--tap X Y`, which is the centre the probe itself printed for the control in hand.
func _the_tap(asked: PackedStringArray) -> Vector2i:
	var at: int = asked.find("--tap")
	if at < 0 or at + 2 >= asked.size():
		return Vector2i.ZERO
	return Vector2i(int(asked[at + 1]), int(asked[at + 2]))


## What the phone last said, in the probe's own words: the newest block's screen lines, then the troubles a finger
## would have, then the verdict on those troubles, and the tap this run sent against the room it was taken in.
##
## `cleared` is what a block cannot say about itself: a block is a moment with no stamp on it, so a log that holds
## nothing means something different when this run has just emptied it.
func _report(kept: String, cleared: bool, logcat: String) -> void:
	var blocks: Array[String] = blocks_in(kept)
	if blocks.is_empty():
		if cleared:
			print("PHONE the log holds no block, and this run cleared it. The program publishes one when a page is")
			print("      shown, moved or resized, or when the top bar is rebuilt - so do something on the device")
			print("      (a `--back`, a `--tap`) and ask again.")
		else:
			print("PHONE the log holds no block - has the program run since it was installed?")
		return
	var lines: PackedStringArray = newest_block(kept)
	print("")
	var heading: String = (
		"--- what the phone last said (%d block(s) in the log, %d line(s) in the newest)"
		% [blocks.size(), lines.size()]
	)
	var aged: String = _age_of_the_newest_block(logcat)
	if not aged.is_empty():
		heading += ", published %s ago" % aged
	print(heading)
	var shown: int = 0
	for kind: String in SCREEN_LINES:
		shown += _print_the(lines, kind)
	var troubles: int = 0
	for kind: String in TOUCH_LINES:
		troubles += _print_the(lines, kind)
	shown += troubles
	_print_the_touch_verdict(lines, troubles)
	var centres: int = _count_of(lines, "tap")
	print(
		"  (%d line(s) it published that this tool does not list%s)"
		% [maxi(lines.size() - shown, 0), " - `--taps` prints their centres" if centres > 0 else ""]
	)
	# The tap this run sent, against the **screen** the block it produced was taken on. A centre is only where a
	# finger should land in the space it was measured in, and the device turns under the program: measured on the
	# A16W, a centre at y 1654 aimed at a 1080-tall landscape screen reached nothing, and nothing said so. The
	# space is the screen and not the room, because the block's own `tap` lines are the screen's pixels - see
	# `tap_words`.
	# **The screen is read off the newest block, not off the log.** `read_screen_line` takes the first `native=`
	# it finds, and the first block in a log is not always about the screen in front of a person - measured on the
	# A16W 2026-11-17: a launch block on a phone lying on a desk is an **upright** block (`scale=0.91
	# shape=standing`, `native=(1080, 2340)`), because the program's window is portrait for its first moment and
	# re-lays out. Measuring a lying block's centre against that called a press that had plainly landed a miss:
	# `--press "2D plan"` moved the button's own label and still printed "outside the screen the block was taken
	# on, (1080, 2340)". The newest block is the one the tap was sent against, so it is the one to measure in.
	if _sent_a_tap:
		print("  %s" % tap_words(_tapped, HudProbeScript.read_screen_line("\n".join(lines))))


## How long ago the newest block in the log was published, in a person's words - or nothing when the device's clock
## did not stamp it.
##
## **A block cannot say how old it is.** Its text carries no clock and `probe.log` is that text and nothing else, so
## the age comes from logcat's own `-v epoch` stamp, exactly as `--blocks` reads it. It is worth a line of its own
## because a block is only as fresh as the last thing the screen did: read without its age, a block taken at launch
## reads as though it were about the screen now in front of a person - which is the mistake this tool exists to
## prevent, and which it very nearly made again on 2026-11-17, when the block that placed the front door in
## landscape was also the one taken before the top bar had finished folding.
func _age_of_the_newest_block(logcat: String) -> String:
	var now: float = float(Time.get_unix_time_from_system())
	var headings: Array[Dictionary] = block_headings(logcat, now)
	if headings.is_empty():
		return ""
	var when: float = float(headings[headings.size() - 1].get("when", 0.0))
	if when <= 0.0:
		return ""
	return age_words(maxi(int(now - when), 0))


## Every block the program has published, oldest first, with the moment the **device's own clock** stamped it and
## the pages it named.
##
## Read from `logcat -v epoch`, because that is the only place a block is stamped at all: `probe.log` is the block
## text and nothing else. An epoch is one number in every time zone, so the age of a block is the difference between
## two of them rather than a subtraction across two clocks' opinions of what "14:44" means - which is why an *age*
## is reported and a time of day is not, exactly as with the build. A line with no readable stamp carries
## `when = 0.0`, and its age comes back `-1.0`: not a block that is no seconds old, but one whose moment is unknown.
static func block_headings(logcat: String, now: float) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	# The names are gathered in a local and stored whole when a block ends, never appended to through the dictionary:
	# **a `PackedStringArray` is a value, not a reference**, so `(block["names"] as PackedStringArray).append(...)`
	# appends to a copy and the block silently keeps none of them - which is what this tool did until the test below
	# was written, and is why the test walks the names rather than only counting the blocks.
	var names: PackedStringArray = PackedStringArray()
	var when: float = 0.0
	var started: bool = false
	for raw: String in logcat.split("\n"):
		var line: String = raw.strip_edges()
		var at: int = line.find("PROBE " + BLOCK_HEAD)
		if at >= 0:
			if started:
				found.append({ "when": when, "names": names })
			started = true
			when = _stamp_before(line, at)
			names = PackedStringArray()
			continue
		if not started:
			continue
		var named: String = _page_name_in_logcat(line)
		if not named.is_empty():
			names.append(named)
	if started:
		found.append({ "when": when, "names": names })
	for block: Dictionary in found:
		var stamp: float = float(block["when"])
		block["age"] = (now - stamp) if stamp > 0.0 else -1.0
	return found


## The moment a logcat line was stamped with: the first word before the message, when that word is a number. In
## `-v epoch` it is seconds since 1970; in any other format it is a date, which is not read here and gives 0.0.
static func _stamp_before(line: String, at: int) -> float:
	var head: String = line.substr(0, at).strip_edges()
	if head.is_empty():
		return 0.0
	var first: String = head.split(" ", false)[0]
	return float(first) if first.is_valid_float() else 0.0


## The page a logcat line names, or nothing. The probe's own `page` line carries the page's name first:
## `page     start_window  "Landscaping Planner"  at ...`.
static func _page_name_in_logcat(line: String) -> String:
	var at: int = line.find("PROBE page")
	if at < 0:
		return ""
	var rest: String = line.substr(at + 10).strip_edges()
	if rest.is_empty():
		return ""
	return rest.split(" ", false)[0]


## The log as a list of moments: every block, by how long ago the device stamped it, and what it named.
##
## **This is the question every stale reading turns on, and no line inside a block answers it.** The last line is
## the newest block, and its age says whether the thing a person just did is in the reading at all.
func _report_the_blocks(logcat: String) -> void:
	# **The device's own clock, not this machine's.** A block is stamped by the phone and an epoch is absolute, so
	# the age of a block is the difference between two numbers - but only while both come from one clock. Two
	# machines keep their own time, and a difference between them would show up here as every age being wrong
	# together, in a list whose spacing still looked right: read against this desk, three blocks came out twenty
	# seconds old and the same three came out three minutes old a few minutes later, because three minutes had in
	# fact passed. Nothing is *known* to be wrong without that - the phone's own answer costs one `date`, and it is
	# the only clock a block's own stamp means anything against.
	var on_the_device: float = _the_devices_clock()
	var here: float = Time.get_unix_time_from_system()
	print("")
	if on_the_device <= 0.0:
		print("--- the device would not say what time it is, so these ages are read against this machine ---")
	if absf(on_the_device - here) > 5.0:
		print(
			"--- and its clock is %s this machine's by %d s, which is why an age is read from it and not from here ---"
			% ["ahead of" if on_the_device > here else "behind", int(absf(on_the_device - here))]
		)
	var blocks: Array[Dictionary] = block_headings(logcat, on_the_device if on_the_device > 0.0 else here)
	if blocks.is_empty():
		print("--- the log holds no block ---")
		print("  The program publishes one when the pages up change, and this read found none: nothing has been")
		print("  published since the log was last cleared.")
		return
	print("--- the blocks the log holds (%d), newest last ---" % blocks.size())
	for block: Dictionary in blocks:
		var age: float = float(block["age"])
		var names: PackedStringArray = block["names"]
		print(
			"  %-18s %s"
			% [
				"no clock" if age < 0.0 else "%s ago" % age_words(int(age)),
				"no page" if names.is_empty() else "%d page(s): %s" % [names.size(), ", ".join(names)],
			]
		)
	var newest: float = float(blocks[blocks.size() - 1]["age"])
	if newest > 2.0:
		print(
			"  The newest was published %s ago. Anything done to the screen since then published nothing - which"
			% age_words(int(newest))
		)
		print("  is the answer for a scroll, and for a re-place that is not a page changing.")


## What the phone says the time is, in seconds since 1970, or 0.0 when it will not say.
##
## `date +%s` is the device's own answer, and the device's own answer is the only one a block's stamp can be
## compared with: a block is stamped by that clock.
func _the_devices_clock() -> float:
	var said: String = _line(["shell", "date", "+%s"]).strip_edges()
	return float(said) if said.is_valid_float() else 0.0


## The newest block printed whole, in the program's own words rather than the subset the report above chooses.
##
## The report is the shape most questions want: the screen lines and the touch lines, named and counted. **A
## question the subset does not cover is otherwise a grep** - a `page` line's own place, the rows in a `drawn` or
## `overlap` line, the exact numbers behind a `small` line - and grepping a log is the step this tool exists to
## remove.
func _report_the_whole_block(kept: String) -> void:
	var lines: PackedStringArray = newest_block(kept)
	print("")
	if lines.is_empty():
		print("--- there is no block to print in full ---")
		return
	print("--- the newest block, whole (%d line(s)) ---" % lines.size())
	for line: String in lines:
		print("  %s" % line)


## The block's own rectangles, marked on the picture this run pulled, so that a claim and the pixels it is a claim
## about are looked at in one place.
##
## **This is the doctrine's own step turned into a file**: a rectangle is a statement by the program about itself,
## the glass is what a person sees, and the only way to know the two agree is to put one on the other. A control a
## finger can aim at is marked in one colour with a dot at the centre the block published; the page standing in
## front of the board in the other, because a page's rectangle is a different question from a button's.
func _draw_the_boxes(lines: PackedStringArray) -> void:
	var from: String = CAPTURE_DIR + THE_SCREEN_NOW
	var picture: Image = ScreenshotReaderScript.read(from)
	print("")
	if picture == null:
		print("--- there is no picture to mark on ---")
		print("  %s was not there. The bare run pulls it, so it is there unless the pull itself failed." % from)
		return
	var taps: Array[Rect2i] = boxes_of(lines, "tap")
	var pages: Array[Rect2i] = boxes_of(lines, "page")
	for rect: Rect2i in taps:
		ScreenshotReaderScript.outline(picture, rect, TAP_BOX, BOX_THICKNESS)
		# The centre the block published, as a filled 3 by 3: an outline as thick as a 3 px box is wide fills it.
		var at: Vector2i = rect.get_center()
		ScreenshotReaderScript.outline(picture, Rect2i(at.x - 1, at.y - 1, 3, 3), TAP_BOX, 3)
	for rect: Rect2i in pages:
		ScreenshotReaderScript.outline(picture, rect, PAGE_BOX, BOX_THICKNESS)
	var to: String = CAPTURE_DIR + THE_BOXES
	var wrote: Error = ScreenshotReaderScript.write(picture, to)
	if wrote != OK:
		print("  the picture could not be written: %s refused with %s" % [to, error_string(wrote)])
		return
	print("--- the block's own rectangles, marked on %s ---" % from)
	print("  %d control(s) a finger can aim at, in cyan, with a dot at the centre the block published" % taps.size())
	print("  %d page(s) standing in front of the board, in amber" % pages.size())
	print("  wrote %s - hold it beside the block: a rectangle not on the control it names is a fault" % to)


## The rectangles the lines of one kind published - every `tap` line, or every `page` line - and nothing for a line
## whose rectangle cannot be read.
static func boxes_of(lines: PackedStringArray, kind: String) -> Array[Rect2i]:
	var found: Array[Rect2i] = []
	for line: String in lines:
		if not line.begins_with(kind + " "):
			continue
		var rect: Rect2i = rect_of(line)
		if rect.size.x > 0 and rect.size.y > 0:
			found.append(rect)
	return found


## The screen rectangle a line published, in the probe's own words for one: `(x, y) .. (x, y) WxH px`.
##
## The **last** `screen (` in a line is the one taken, because that is the rectangle the line is about rather than
## anything a control's caption might happen to say. A line with none, or with words that are not numbers, is an
## empty rectangle - not a place on any picture, and so not one that can be mistaken for one.
static func rect_of(line: String) -> Rect2i:
	var at: int = line.rfind("screen (")
	if at < 0:
		return Rect2i()
	var halves: PackedStringArray = line.substr(at).split("..")
	if halves.size() < 2:
		return Rect2i()
	var first: Vector2i = _point_in(halves[0])
	var second: Vector2i = _point_in(halves[1])
	if first.x < 0 or second.x < 0:
		return Rect2i()
	return Rect2i(first, second - first)


## The first pair of whole numbers in parentheses in a piece of text, or `(-1, -1)` for one that has none.
static func _point_in(text: String) -> Vector2i:
	var open: int = text.find("(")
	if open < 0:
		return Vector2i(-1, -1)
	var close: int = text.find(")", open + 1)
	if close < 0:
		return Vector2i(-1, -1)
	var parts: PackedStringArray = text.substr(open + 1, close - open - 1).split(",")
	if parts.size() != 2:
		return Vector2i(-1, -1)
	var across: String = parts[0].strip_edges()
	var down: String = parts[1].strip_edges()
	if not across.is_valid_int() or not down.is_valid_int():
		return Vector2i(-1, -1)
	return Vector2i(int(across), int(down))


## The blocks in the log's text, oldest first.
##
## A block begins at the probe's own heading and carries one line per `PROBE` prefix; the text arrives from adb,
## so every line is stripped of the carriage return a shell adds before it is looked at.
static func blocks_in(kept: String) -> Array[String]:
	var blocks: Array[String] = []
	var current: PackedStringArray = PackedStringArray()
	for raw: String in kept.split("\n"):
		var line: String = raw.strip_edges()
		if not line.begins_with("PROBE "):
			continue
		var said: String = line.substr(6)
		if said == BLOCK_HEAD:
			if current.size() > 0:
				blocks.append("\n".join(current))
			current = PackedStringArray()
			continue
		current.append(said)
	if current.size() > 0:
		blocks.append("\n".join(current))
	return blocks


## Every line of one kind, as the probe worded it, and how many there were.
func _print_the(lines: PackedStringArray, kind: String) -> int:
	var printed: int = 0
	for line: String in lines:
		if line.begins_with(kind + " "):
			print("  %s" % line)
			printed += 1
	return printed


## How many lines of one kind a block holds, without printing them - so a count can be offered without spending
## the screen on the thing being counted.
static func _count_of(lines: PackedStringArray, kind: String) -> int:
	var found: int = 0
	for line: String in lines:
		if line.begins_with(kind + " "):
			found += 1
	return found


## **A phone nothing is wrong with still gets its sentence, and that is not the same as silence.** The touch lines
## are troubles and nothing else, so a block holding none of them is good news. The first version asked this only
## when *nothing at all* had been printed, and `device` was one of the kinds it printed - so the sentence could
## never be reached, and a clean phone read exactly like one that had not been asked. Measured 2026-11-14.
func _print_the_touch_verdict(lines: PackedStringArray, troubles: int) -> void:
	if troubles > 0:
		return
	if says_a_finger(lines):
		print("  nothing a touch rule can name: every target clears the floor, none is too close to its")
		print("  neighbour, none stands in a band the device keeps and the words are legible")
	else:
		print("  the program is not serving a finger, so it asks none of these questions")


## Whether the block's own device line says this program is serving a finger, which is the condition every touch
## rule is asked under at all.
static func says_a_finger(lines: PackedStringArray) -> bool:
	for line: String in lines:
		if line.begins_with("device ") and line.contains("finger=true"):
			return true
	return false


## The centres a driver aims at, in the newest block's own words: every control it listed as reachable, or only
## those whose words hold a piece of text that was asked for.
##
## This is the half of the tool a driver needs and the report above hides. A tap is only as good as the centre it
## is aimed at, and these centres are what the program itself published rather than a guess made from a picture.
func _report_the_taps(kept: String, asked: PackedStringArray) -> void:
	var lines: PackedStringArray = newest_block(kept)
	if lines.is_empty():
		return
	var filter: String = tap_filter(asked)
	var held: Array[String] = []
	for line: String in lines:
		if not line.begins_with("tap "):
			continue
		if filter.is_empty() or line.to_lower().contains(filter.to_lower()):
			held.append(line)
	print("")
	if filter.is_empty():
		print("--- every centre the newest block published (%d) ---" % held.size())
	else:
		print("--- the centres whose words hold \"%s\" (%d) ---" % [filter, held.size()])
	for line: String in held:
		print("  %s" % line)
	if held.is_empty():
		print("  nothing: no control the block names has words holding that, so nothing can be aimed at it")


## The one word a driver may narrow the centres by, from `--taps [words]` - the same rule `--press` reads its words
## by, kept in one place so the two verbs cannot come to disagree about what a word after a flag is.
static func tap_filter(asked: PackedStringArray) -> String:
	return the_word_after(asked, "--taps")


## The one word a driver may name after a flag - `--taps Cancel`, `--press Begin`: everything after it that is not
## another flag. Empty means none was named, which is a different answer from a word that is not in the block.
static func the_word_after(asked: PackedStringArray, flag: String) -> String:
	var at: int = asked.find(flag)
	if at < 0:
		return ""
	for i: int in range(at + 1, asked.size()):
		if not asked[i].begins_with("--"):
			return asked[i]
	return ""


## Whether a block's own lines name a page - the one thing the newest block is asked before `--capture` presses BACK
## a second time, since a picture of the doorway is not the picture it came for.
##
## It answers about the block, and a block is only as fresh as the last thing the screen did: until 2026-11-14 a
## page *leaving* published no block at all, so this could go on naming a page that was no longer on the screen
## (measured on the A16W, and cured the same day - see `_go_back`).
static func a_block_names_a_page(block: PackedStringArray) -> bool:
	for line: String in block:
		if line.begins_with("page "):
			return true
	return false


## The newest block in the log's text, as lines - or nothing when the log holds none. **One place finds it**, so
## that a reading and a driver cannot end up looking at two different blocks.
static func newest_block(kept: String) -> PackedStringArray:
	var blocks: Array[String] = blocks_in(kept)
	if blocks.is_empty():
		return PackedStringArray()
	return blocks[blocks.size() - 1].split("\n", false)


## The centre a tap line published, read off its own last words - `... centre (320, 526)`.
##
## A line that says no centre, or one whose two numbers are not numbers, gives `(-1, -1)`: not a place on any
## screen, and so not a place that can be mistaken for one.
static func centre_of(line: String) -> Vector2i:
	var at: int = line.rfind("centre (")
	if at < 0:
		return Vector2i(-1, -1)
	var rest: String = line.substr(at + 8)
	var close: int = rest.find(")")
	if close < 0:
		return Vector2i(-1, -1)
	var parts: PackedStringArray = rest.substr(0, close).split(",")
	if parts.size() != 2:
		return Vector2i(-1, -1)
	var across: String = parts[0].strip_edges()
	var down: String = parts[1].strip_edges()
	if not across.is_valid_int() or not down.is_valid_int():
		return Vector2i(-1, -1)
	return Vector2i(int(across), int(down))


## What the block says about pressing the control whose words hold `words`: the centre to aim at, or - in words -
## why nothing can be pressed at it.
##
## **Only a `tap` line is a control that can be pressed.** The foot line says `Esc: cancel` and the box beside the
## plan says the words of the tool in hand, so searching the whole block would find something no finger can reach -
## which is why the kind is asked for first and the search second.
##
## **A control the block does not name cannot be pressed, and naming that is the honest answer.** A control below a
## scroller is not drawn, so it is not in the block: measured on the A16W held upright, the palette's own `Cancel`
## is under its column's fold. `--swipe` is how it is brought into view - and whether the program then publishes a
## block about it is the program's business, which `--swipe` asks about rather than assumes.
static func press_words(block: PackedStringArray, words: String) -> Dictionary:
	var wanted: String = words.to_lower()
	for line: String in block:
		if not line.begins_with("tap "):
			continue
		if not line.to_lower().contains(wanted):
			continue
		var at: Vector2i = centre_of(line)
		if at.x < 0:
			continue
		return { "found": true, "at": at, "line": line }
	return {
		"found": false,
		"at": Vector2i.ZERO,
		"said": (
			"no control the newest block names has words holding \"%s\", so nothing here can be pressed at it. A"
			% words
			+ " control below a scroller is not drawn and so is not in the block: `--swipe` brings it into view."
		),
	}


## The drag `--swipe` was given: a start and an end, from `--swipe x1 y1 x2 y2 [ms]`. Four numbers or none - a drag
## missing its end is not a drag, and reading one as a press would be a guess.
static func the_swipe(asked: PackedStringArray) -> Array[Vector2i]:
	var none: Array[Vector2i] = []
	var at: int = asked.find("--swipe")
	if at < 0 or at + 4 >= asked.size():
		return none
	for i: int in range(at + 1, at + 5):
		if not asked[i].is_valid_int():
			return none
	return [Vector2i(int(asked[at + 1]), int(asked[at + 2])), Vector2i(int(asked[at + 3]), int(asked[at + 4]))]


## How long a drag takes, from the optional fifth number: slow enough that a list follows the finger rather than
## flinging past what was wanted. Bounded at both ends, so a mistyped duration is a slow drag and not a hang.
static func the_drag_ms(asked: PackedStringArray) -> int:
	var at: int = asked.find("--swipe")
	if at < 0 or at + 5 >= asked.size() or not asked[at + 5].is_valid_int():
		return 300
	return clampi(int(asked[at + 5]), 50, 5000)


## The region `--crop` was given, in the picture's own pixels: `--crop x y width height`. **Nothing rather than a
## whole-screen consolation** when the numbers are missing or are not numbers: a crop nobody asked for is a file
## that lies about what it is.
static func the_region(asked: PackedStringArray) -> Rect2i:
	var at: int = asked.find("--crop")
	if at < 0 or at + 4 >= asked.size():
		return Rect2i()
	for i: int in range(at + 1, at + 5):
		if not asked[i].is_valid_int():
			return Rect2i()
	return Rect2i(int(asked[at + 1]), int(asked[at + 2]), int(asked[at + 3]), int(asked[at + 4]))
