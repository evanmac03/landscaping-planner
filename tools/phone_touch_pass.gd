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
## pretending to be one. It touches nothing on this computer but adb.
##
## **A phone in reach is the first thing it asks about, and the refusal names it.** An instrument that has
## nothing to say and one that cannot ask are different readings: with no device in reach, the log's absence is
## not the program's silence. Measured 2026-11-14 with the A16W's wireless debugging off - the tool used to go on
## to "the log holds no block - has the program run since it was installed?", which points a person at the
## program. `a_device_is_here` is that question's pure half, held by a test.
##
## Run it with `execute_script`/`run_scene`, and pass its own words through the command line:
##
##     res://tools/phone_touch_pass.tscn                              what the phone last said
##     res://tools/phone_touch_pass.tscn -- && --install --launch --wait 3
##     res://tools/phone_touch_pass.tscn -- && --tap 540 552          press at the probe's own centre
##     res://tools/phone_touch_pass.tscn -- && --capture              the board upright, a line, then the question
##
## `--tap` is how a page is reached on the device: the probe reports every control it could be tapped at, with
## the centre to aim at, and a real OS tap does reach a control inside a page's `Window` - measured, and the
## opposite of what the injection in `run_scene` can do.
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

## The lines the touch rules publish, and what each one asks. Printed in this order, and anything else in a block
## is summarised rather than buried.
const TOUCH_LINES: Array[String] = [
	"device",
	"room",
	"small",
	"close",
	"unsafe",
	"middle",
	"tiny",
	"clipped",
	"offscreen",
]

## The words a block begins with, in the probe's own report.
const BLOCK_HEAD := "--- what is on the screen ---"

## The probe, for the one thing only a block can say: the room it was taken in. This tool sends a tap in screen
## pixels, and whether those pixels are on the screen the program is drawing on is the block's answer.
const HudProbeScript := preload("res://scripts/hud_probe.gd")

## Where `--capture` puts its screenshots, and the three places it presses on the way.
##
## The two line points are in the screen's own pixels on the A16W held upright: clear of the palette (x is under
## 0.4 of the 1080 it is drawn on) and mid-screen, so they land on the plan whatever else is about. Any place
## would do - the line exists only to make work unsaved. `LINE_CELL` is the palette's own first tool cell, which
## is pressed **at the centre the probe itself printed** for it.
const CAPTURE_DIR := "res://build/"
const LINE_CELL := Vector2i(150, 404)
const LINE_TAPS: Array[Vector2i] = [Vector2i(620, 1150), Vector2i(800, 1450)]

## Where adb was found, once, at the start: the SDK copy, or a bare one on the path.
var _adb_path: String = ""

## The tap this run sent, and whether there was one - a tap at (0, 0) is a real place on a screen, so the point
## alone cannot say whether anything was sent.
var _tapped: Vector2i = Vector2i.ZERO
var _sent_a_tap: bool = false


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

	if "--capture" in asked:
		await _capture_the_two_gaps()
		return
	if "--install" in asked:
		print("PHONE installing %s" % APK)
		print("PHONE %s" % _line(["install", "-r", ProjectSettings.globalize_path(APK)]).strip_edges())
	if "--install" in asked or "--launch" in asked:
		_line(["shell", "run-as", PACKAGE, "rm", "-f", "files/probe.log"])
		_line(["shell", "am", "force-stop", PACKAGE])
		print("PHONE launching %s" % ACTIVITY)
		_line(["shell", "am", "start", "-n", ACTIVITY])
		var seconds: int = _wait_seconds(asked)
		print("PHONE waiting %d s for the front door" % seconds)
		await get_tree().create_timer(float(seconds)).timeout
	if "--tap" in asked:
		var at: Vector2i = _the_tap(asked)
		_tapped = at
		_sent_a_tap = at != Vector2i.ZERO
		print("PHONE tapping (%d, %d)" % [at.x, at.y])
		_line(["shell", "input", "tap", str(at.x), str(at.y)])
		await get_tree().create_timer(3.0).timeout

	_report(_line(["exec-out", "run-as", PACKAGE, "cat", "files/probe.log"]))
	_report_the_fold()


## The top bar's own numbers, out of logcat: the durable evidence for the one thing a single block cannot show -
## whether the fold had **finished** when the block was taken.
##
## A block is published the moment a page appears, and the fold goes on running after that: measured on the A16W,
## a launch block still carried the bar at ten titles needing 1052 px of a 349 px room, while the bar's own line
## went on to two titles and 272 px and fitted. Reading that block as a defect in the bar is the mistake this
## exists to prevent, and the line it reads is the bar's own - its reader and its writer are one thing, in
## `menu_bar_plan.gd`, round-tripped by a test.
func _report_the_fold() -> void:
	var folded: Dictionary = MenuBarPlan.read_menubar_line(_line(["logcat", "-d", "-s", "godot:I"]))
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
	var hold: String = hold_words(_line(["shell", "run-as", PACKAGE, "cat", "files/orientation.json"]))
	print("PHONE the hold: %s" % hold)
	if not hold.begins_with("the board is held upright"):
		print("PHONE so this is NOT the capture the two gaps ask for. Hold the board upright first, on the device:")
		print("      echo '{\"orientation\": \"portrait\"}' | adb shell run-as %s dd of=files/orientation.json" % PACKAGE)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIR))

	_line(["shell", "run-as", PACKAGE, "rm", "-f", "files/probe.log"])
	_line(["shell", "am", "force-stop", PACKAGE])
	print("PHONE launching %s" % ACTIVITY)
	_line(["shell", "am", "start", "-n", ACTIVITY])
	await get_tree().create_timer(10.0).timeout

	_line(["shell", "input", "keyevent", "4"])
	await get_tree().create_timer(4.0).timeout
	_save_a_screenshot("board_upright.png")

	_line(["shell", "input", "tap", str(LINE_CELL.x), str(LINE_CELL.y)])
	await get_tree().create_timer(3.0).timeout
	for point: Vector2i in LINE_TAPS:
		_line(["shell", "input", "tap", str(point.x), str(point.y)])
		await get_tree().create_timer(2.0).timeout
	_save_a_screenshot("a_line_drawn.png")

	_line(["shell", "input", "keyevent", "4"])
	await get_tree().create_timer(6.0).timeout
	_save_a_screenshot("the_unsaved_question.png")
	print("PHONE the program is still alive as pid %s" % _first_line(_line(["shell", "pidof", PACKAGE])))
	print("PHONE three pictures in %s - and what the probe says about each is in the log beside them" % CAPTURE_DIR)


## One screenshot, taken on the device and pulled back as a file.
##
## **`exec-out screencap -p` cannot be used from here.** `OS.execute` hands back *text*, and a PNG read through it
## is a length of mangled characters - so the picture is written on the device and `pull` copies the bytes.
func _save_a_screenshot(name: String) -> void:
	var far: String = "/sdcard/%s" % name
	_line(["shell", "screencap", "-p", far])
	var here: String = ProjectSettings.globalize_path(CAPTURE_DIR.path_join(name))
	print("PHONE %s" % _line(["pull", far, here]).strip_edges().replace("\n", " | "))


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


## How long to wait for the program to come up, from `--wait N`, which is the one number here a slow phone may
## want more of.
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


## What to say about a tap and the room the block it produced was taken in.
##
## `Rect2i` is the engine's own answer to this and it is **exclusive of the far edge** - a point exactly on the
## right or the foot of the room counts as outside it - which is the honest reading: a tap on the last row of
## pixels is not one the program can be depended on to have received.
##
## A block that names no room has no answer, and saying so is the point. It is not a tap inside a room of no size,
## which would read as a clean run.
static func tap_words(tap: Vector2i, room: Vector2i) -> String:
	if room.x <= 0 or room.y <= 0:
		return "the block names no room to measure the tap at (%d, %d) against" % [tap.x, tap.y]
	if Rect2i(Vector2i.ZERO, room).has_point(tap):
		return "the tap at (%d, %d) is inside the room the block was taken in, %s" % [tap.x, tap.y, str(room)]
	return (
		"the tap at (%d, %d) is outside the room the block was taken in, %s" % [tap.x, tap.y, str(room)]
		+ " - a centre from a block taken the other way up reaches nothing, so the block above is not about it"
	)


## Where to tap, from `--tap X Y`, which is the centre the probe itself printed for the control in hand.
func _the_tap(asked: PackedStringArray) -> Vector2i:
	var at: int = asked.find("--tap")
	if at < 0 or at + 2 >= asked.size():
		return Vector2i.ZERO
	return Vector2i(int(asked[at + 1]), int(asked[at + 2]))


## What the phone last said, in the probe's own words: the newest block's touch lines, and a count of what else
## was in it, so that a report nobody has read yet is still visible as a size.
func _report(kept: String) -> void:
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

	if blocks.is_empty():
		print("PHONE the log holds no block - has the program run since it was installed?")
		return
	var newest: String = blocks[blocks.size() - 1]
	var lines: PackedStringArray = newest.split("\n", false)
	print("")
	print(
		"--- what the phone last said (%d block(s) in the log, %d line(s) in the newest) ---"
		% [blocks.size(), lines.size()]
	)
	var printed: int = 0
	for kind: String in TOUCH_LINES:
		for line: String in lines:
			if not line.begins_with(kind + " "):
				continue
			print("  %s" % line)
			printed += 1
	for line: String in lines:
		if printed > 0:
			break
		# A block with a device line saying a finger and no touch line after it is a phone with **nothing wrong
		# to name** - every target over the floor, no two too close, nothing in a kept band, the words legible.
		# That is the honest reading, and it is not the same as a program that never published: the first is
		# good news and the second is a reason to look at the build.
		if line.begins_with("device ") and line.contains("finger=true"):
			print("  nothing a touch rule can name: every target clears the floor, none is too close to its")
			print("  neighbour, none stands in a band the device keeps and the words are legible")
		elif line.begins_with("device ") and line.contains("finger=false"):
			print("  the program is not serving a finger, so it asks none of these questions")
	print("  (%d line(s) it published that this tool does not list)" % maxi(lines.size() - printed, 0))
	# The tap this run sent, against the room the block it produced was taken in. A centre is only where a finger
	# should land **in the room it was measured in**, and the device turns under the program: measured on the A16W,
	# a centre at y 1654 aimed at a 1080-tall landscape screen reached nothing, and nothing said so.
	if _sent_a_tap:
		print("  %s" % tap_words(_tapped, HudProbeScript.read_room_line(kept)))
