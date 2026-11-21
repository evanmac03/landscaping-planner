extends Node
## A guard on the one question "which device is this", and on where the program is allowed to ask it.
##
## **The rule.** A difference between a desk and a phone is a *question with one owner*, never a second
## implementation of the same answer. So the platform may be asked who it is - its name, its model, whether it
## has a touchscreen, how dense its screen is, what band it keeps for itself - **in the files listed here
## only**, each because the question is what that file is for. A file that asks and is not listed is the fault
## this holds: two answers to one question drift apart, and the one that drifts is the phone's, because the
## desk is where the suite runs.
##
## **Why it is worth a guard.** This project already has the receipt: the phone's fixes were once wiped by a
## `git checkout -- .`, had to be restored in six parts, and a memory was left claiming the work was done.
## Nothing pinned the reading itself, and a new device branch in a new file is exactly how a fork creeps in -
## it reads as one line, and it is a second answer that nobody diffs.
##
## **What it is not.** Not every reading of the glass. `DisplayServer.screen_get_size()` - how big the room is
## - is deliberately not a shape: it is a reading of the machine that nothing can answer two ways, so two
## copies of it cannot disagree. What is held is the questions the *program answers*, each of which can. The
## other question of this kind, "is there a screen to measure on", has its own doctrine and its own one owner
## in `tests/test_screen_doctrine.gd`, and is not restated here.
##
## **Why a list may exist at all.** Each of these owners offers two doors where it matters: one that reads the
## machine (`PhoneHud.on_a_finger_here`, `TouchInput.has_a_touchscreen`, `OrientationChoice.can_turn_here`),
## and one that is *told* the answer (`PhoneHud.force_density`, `TouchInput.answered_by_a_thumb`,
## `PhoneFiles.force`, `Hud.force_touch_controls`). That is what lets the suite hold the phone's behaviour on
## a desk, and it is why an owner may ask while a caller must be handed the answer.
##
## **Three of those files stopped asking.** `PhoneFiles`, `OrientationChoice` and `CameraWindow` each read the
## platform feature for themselves once - `android`, `mobile`, and `android` again - which is four readings of
## one fact, and the way to have four answers that agree is to have one. They are handed it by
## `DevicePlatform` now. The list is what holds that: those three ask nothing, so they are not on it, and the
## day one of them reads a feature again this guard names it.
##
## **Out of scope on purpose.** `addons/` is third-party and is never walked; `tests/` is left out because
## quoting a spelling is how a test checks it - the controls below are the case in point.

const Scan := preload("res://tests/support/source_scan.gd")

## The shapes a device decision is written in.
##
## `OS.has_feature(` is the one shape with an exception, in `LEFT_ALONE` below.
const SHAPES: Array[String] = [
	"OS.get_name()",
	"OS.get_model_name()",
	"OS.has_feature(",
	"DisplayServer.is_touchscreen_available()",
	"DisplayServer.screen_get_dpi()",
	"DisplayServer.get_display_safe_area()",
]

## The call a line may name and be cleared of, because `("editor")` is not the device question but the editor
## question - which this program is entitled to ask, AGENTS.md naming it for its one autoload. What is cleared
## is the call itself, so a device question beside it on the same line is still caught.
const LEFT_ALONE: Array[String] = ["OS.has_feature(\"editor\")"]

## The files allowed to ask, and what each one owns. An entry is a question rather than a permission: a file
## here that asks something else, or asks a question it does not own, is still a second answer, and this list
## is not a place to hide one.
const ASKED_HERE: Dictionary = {
	"res://scripts/touch_input.gd": "owns whether a finger is being served",
	"res://scripts/phone_hud.gd": "owns the device's own numbers: the density, the glass, the system band",
	"res://scripts/device_platform.gd": "owns which platform this is: the one place the machine is asked",
	"res://scripts/hud.gd": "hands the facts to the one decision; nothing is decided here",
	"res://scripts/device_model_fit.gd": "is the feature that describes the machine",
	"res://tools/debug_toolbox.gd": "is the tool that reports the machine it is running on",
}

## The three files this consolidation is about: each read the platform for itself once, and each is handed it
## by `DevicePlatform` now. Held apart from the list so that a file that goes back to asking is caught twice -
## once by the list, and once by the test below, which says which of the two happened.
const NOW_HANDED_THE_PLATFORM: Array[String] = [
	"res://scripts/phone_files.gd",
	"res://scripts/orientation_choice.gd",
	"res://scripts/camera_window.gd",
]


## The rule itself.
func test_the_device_is_asked_only_where_the_question_is_owned() -> void:
	var caught := PackedStringArray()
	for path: String in Scan.files():
		if not _offences_on(path).is_empty():
			caught.append(path)
	var allowed := PackedStringArray()
	for path: String in ASKED_HERE:
		allowed.append(path)
	allowed.sort()
	var new_ones := PackedStringArray()
	for path: String in caught:
		if not ASKED_HERE.has(path):
			new_ones.append(path)
	var gone := PackedStringArray()
	for path: String in allowed:
		if not caught.has(path):
			gone.append(path)
	assert(
		new_ones.is_empty(),
		(
			"the device is asked in a file that does not own the question - hand the answer in, or say "
			+ "what the file owns and add it to ASKED_HERE: " + ", ".join(new_ones)
		),
	)
	assert(
		gone.is_empty(),
		(
			"a file listed as asking the device asks nothing of the sort any more, so the list is out "
			+ "of date: " + ", ".join(gone)
		),
	)


## A guard that reads nothing passes everything. This is the assertion that the walk is a walk.
func test_the_guard_reads_the_program_and_the_tools() -> void:
	var paths := Scan.files()
	assert(paths.size() > 100, "the walk found the project's own scripts: %d" % paths.size())
	assert(paths.has("res://scripts/hud.gd"), "including the HUD that hands the facts to the one decision")
	assert(paths.has("res://scripts/phone_hud.gd"), "and the module that owns the device's numbers")
	assert(paths.has("res://tools/debug_toolbox.gd"), "and the tool that reports the machine")
	assert(not paths.has("res://tests/test_device_doctrine.gd"), "and nothing outside the two trees")
	for path: String in paths:
		assert(not Scan.read(path).is_empty(), path + " could be read")


## A guard that cannot fail is not a guard. The matcher is run against the shapes it exists to catch, written
## here by hand rather than found in the tree, so it is still a guard on the day the tree is clean - and
## against the shapes it must **not** catch, which are the ones it would be useless for catching falsely.
func test_the_guard_catches_a_second_answer_and_leaves_writing_about_it_alone() -> void:
	assert(_offences("if OS.has_feature(\"android\"):", "sample.gd").size() == 1, "a device branch is caught")
	assert(_offences("if OS.get_name() == \"Android\":", "sample.gd").size() == 1, "and one by name")
	assert(
		_offences("if DisplayServer.is_touchscreen_available():", "sample.gd").size() == 1,
		"and one that asks whether a finger is being served",
	)
	assert(
		_offences("var density := DisplayServer.screen_get_dpi()", "sample.gd").size() == 1,
		"and one that reads the density for itself",
	)
	assert(
		_offences("var band := DisplayServer.get_display_safe_area()", "sample.gd").size() == 1,
		"and one that reads the band the system keeps",
	)
	assert(
		_offences("if not OS.has_feature(\"editor\"):", "sample.gd").is_empty(),
		"while the editor question, which this program is entitled to ask, is left alone",
	)
	assert(
		(_offences("if OS.has_feature(\"android\") and not OS.has_feature(\"editor\"):", "sample.gd").size() == 1),
		"and the exception clears the call it names, not the device question beside it on the same line",
	)
	assert(
		_offences("## Asking OS.get_name() here would be a second answer.", "sample.gd").is_empty(),
		"while a comment naming the call is writing about the rule rather than keeping a copy of it",
	)
	assert(
		_offences("printerr(\"the android picker is missing\")", "sample.gd").is_empty(),
		"and a device's name inside a message is a person being told something",
	)
	assert(
		_offences("var names := [\"windows\", \"android\"]", "sample.gd").is_empty(),
		"and a list of platform names as data is not a question asked of the machine",
	)
	assert(
		_offences("var room := DisplayServer.screen_get_size()", "sample.gd").is_empty(),
		"and a reading of the glass that nothing can answer two ways is deliberately not held",
	)


## The three files whose four readings this consolidation removed read the platform through the one owner and
## ask the machine nothing themselves. This is the guard on the change rather than on the list: reverting one
## of them puts a feature back in the file, and this says which file and what is now wrong with it.
func test_the_files_that_used_to_ask_now_read_the_one_owner() -> void:
	for path: String in NOW_HANDED_THE_PLATFORM:
		var text: String = Scan.read(path)
		assert(text.contains("device_platform.gd"), path + " reads the platform through DevicePlatform")
		var offences := _offences(text, path)
		assert(offences.is_empty(), path + " asks the machine nothing itself any more: " + ", ".join(offences))
		assert(not ASKED_HERE.has(path), path + " is not a file the device is allowed to be asked in")


## A list a reader is meant to trust names files that are there, and says what each one owns.
func test_every_file_the_device_is_asked_in_says_what_it_owns() -> void:
	for path: String in ASKED_HERE:
		assert(not Scan.read(path).is_empty(), path + " is a file, and can be read")
		var why := String(ASKED_HERE[path])
		assert(why.length() > 20, path + " says what it owns: " + why)


## The offences on one script, under this doctrine's shapes and its one exception.
func _offences_on(path: String) -> Array[String]:
	return _offences(Scan.read(path), path)


## The same reading of a line written out by hand, which is how the controls above state their case.
func _offences(text: String, path: String) -> Array[String]:
	return Scan.offences(text, path, SHAPES, LEFT_ALONE)
