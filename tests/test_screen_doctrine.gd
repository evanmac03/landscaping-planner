extends Node
## A guard on the one question "is there a screen to measure on".
##
## Five things in this project need the same answer, each for a different reason: the probe, before its
## absolute-pixel lines (`small` and `close`) turn a headless 64 x 64 dummy display into a fault nobody has;
## the HUD, before it copies the framebuffer to read a page's title bar off; `tools/gui_stillness.gd`, before it
## reads two frames of the glass; `tools/check_github_dock.gd`, before it saves a preview; and
## `tools/hud_layout_check.gd`, before it compares two heights in the room it is measuring. The answer is
## **`HudProbe._a_real_screen()`**, and this asserts there is one of it.
##
## **Why it is worth a guard.** Every copy of it was written `DisplayServer.get_name() != "headless"`, and the
## line a person is tempted to write instead is `OS.has_feature("headless")` - which is false on a machine
## running the editor and **false in a debug export too**, so it asks a different question while looking like the
## same one. The cost of a copy drifting is already on the record: the layout check's finger pass compared two
## heights in a headless 64 x 64 room, the finger-typed foot line's top came back as `-69443`, and
## `tools/audit.tscn` reported `FAIL HUD layout` on a fault nobody had.
##
## **What it looks for, and why it is that narrow.** Two shapes, and only one of them is code: the API call
## `DisplayServer.get_name()`, and the literal `"headless"` **on its own** - which is the only way any code can
## ask the platform about the dummy display, and so catches `OS.has_feature("headless")` beside the comparison
## every copy used to be. The word inside a longer message (`"cannot draw on a headless machine"`) is a person
## being told something and is deliberately left alone. A comment is not a copy either, so a line is read only up
## to a `#` that is not inside a literal: three of the files that call the owner name the call in their own
## prose, and that is writing about the rule rather than keeping a second copy of it.
##
## **Out of scope on purpose.** `addons/` is third-party and is not walked, and nothing here may police it - its
## `headless` words are button labels and library internals. `tests/` is out of scope for the reason
## `test_area_units_doctrine` gives about its own rule: quoting the call is how a test checks it.

## The one file allowed to ask the question.
const OWNER := "res://scripts/hud_probe.gd"

## The walk itself, shared with `test_device_doctrine.gd`: the files, the code on a line with its comments
## cut off, and the places a shape is found. One reader of the source, so two doctrines cannot come to
## disagree about what it says.
const Scan := preload("res://tests/support/source_scan.gd")

## The shapes a second copy takes: the call itself, and the word a program can only ask the platform with.
const SHAPES: Array[String] = ["DisplayServer.get_name()", "\"headless\""]

# --- the guard ---------------------------------------------------------------------------------


func test_the_one_place_that_asks_for_a_screen_is_the_probe() -> void:
	var caught := PackedStringArray()
	for path: String in Scan.files():
		if not offences_in(Scan.read(path), path).is_empty():
			caught.append(path)
	assert(
		caught == PackedStringArray([OWNER]),
		"exactly one file asks whether there is a screen; these do: " + ", ".join(caught),
	)


## A guard that reads nothing passes everything. This is the assertion that the walk is a walk.
func test_the_guard_reads_the_scripts_and_the_tools() -> void:
	var paths := Scan.files()
	assert(paths.size() > 100, "the walk found the project's own scripts: %d" % paths.size())
	assert(paths.has(OWNER), "including the one that answers the question")
	assert(paths.has("res://scripts/hud.gd"), "and the HUD that copies the framebuffer through it")
	assert(paths.has("res://tools/gui_stillness.gd"), "and the tool that reads two frames of the glass")
	assert(paths.has("res://tools/hud_layout_check.gd"), "and the check whose finger pass states a device")
	assert(not paths.has("res://tests/test_screen_doctrine.gd"), "and nothing outside those two trees")
	for path: String in paths:
		assert(not Scan.read(path).is_empty(), path + " could be read")


## A guard that cannot fail is not a guard. The matcher is run against the shapes it exists to catch, written
## out by hand here rather than found in the tree, so it is still a guard on the day the tree is clean - and
## against the shapes it must **not** catch, which are the ones it would be useless for catching falsely.
func test_the_guard_catches_the_shapes_a_second_copy_takes() -> void:
	assert(
		offences_in("if DisplayServer.get_name() != \"headless\":", "sample.gd").size() == 1,
		"the rule as every copy of it was written, and both shapes on the one line, are caught",
	)
	assert(
		offences_in("if not OS.has_feature(\"headless\"):", "sample.gd").size() == 1,
		"and the line that looks like the rule and is worse, being true of a debug export as well",
	)
	assert(
		offences_in("printerr(\"cannot draw on a headless machine\")", "sample.gd").is_empty(),
		"while the word inside a longer message is a person being told something, not a second copy of the rule",
	)
	assert(
		offences_in("## The guard the framebuffer needs is DisplayServer.get_name().", "sample.gd").is_empty(),
		"while a comment that names the call is writing about the rule, not keeping a copy of it",
	)
	assert(
		offences_in("## A headless run has no framebuffer.", "sample.gd").is_empty(),
		"and a comment that says headless is the same kind of writing",
	)
	assert(
		offences_in("if not OS.has_feature(\"editor\"):", "sample.gd").is_empty(),
		"and the editor test, which this program uses for reasons of its own, is left alone",
	)
	assert(
		offences_in("var words := \"#\" + DisplayServer.get_name()", "sample.gd").size() == 1,
		"and a `#` inside a literal does not cut the line short, hiding a copy after it",
	)

# --- the matcher -------------------------------------------------------------------------------


## Every offence on one script, as `path:line: "the line as code"`. Public so that a reader of this file can see
## the whole rule in one place.
static func offences_in(text: String, path: String) -> Array[String]:
	return Scan.offences(text, path, SHAPES)
