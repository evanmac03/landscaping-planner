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
## Run it with `execute_script`/`run_scene`, and pass its own words through the command line:
##
##     res://tools/phone_touch_pass.tscn                              what the phone last said
##     res://tools/phone_touch_pass.tscn -- && --install --launch --wait 3
##     res://tools/phone_touch_pass.tscn -- && --tap 540 552          press at the probe's own centre
##
## `--tap` is how a page is reached on the device: the probe reports every control it could be tapped at, with
## the centre to aim at, and a real OS tap does reach a control inside a page's `Window` - measured, and the
## opposite of what the injection in `run_scene` can do.

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

## Where adb was found, once, at the start: the SDK copy, or a bare one on the path.
var _adb_path: String = ""

## The tap this run sent, and whether there was one - a tap at (0, 0) is a real place on a screen, so the point
## alone cannot say whether anything was sent.
var _tapped: Vector2i = Vector2i.ZERO
var _sent_a_tap: bool = false


func _ready() -> void:
	_adb_path = _find_adb()
	if _adb_path.is_empty():
		print("PHONE no adb at %s, and none on the path - is the SDK still where it was?" % ADB)
		return
	var asked: PackedStringArray = OS.get_cmdline_user_args()
	print("PHONE %s" % _first_line(_line(["version"])))
	print("PHONE %s" % _line(["devices", "-l"]).strip_edges().replace("\n", " | "))

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
