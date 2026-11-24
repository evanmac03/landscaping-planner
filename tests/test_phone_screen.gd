extends Node
## The phone-shaped desk scene's own rules, held down where no window can be opened.
##
## The scene's job is to make a window the size of a phone's glass and put the program in it, which a test runner
## has no display for - so what is held here is everything that decides **which phone a run states**: the way up the
## line asks for, and the verb a typo is refused by. A run that quietly states the wrong shape answers every question
## with the wrong device and looks perfectly healthy doing it, which is the whole reason they are here rather than
## left to a person's eye.
##
## **The glass and the usable rectangle are not held here, because they were a table here and are not any more.** The
## A16W both ways up lives in `PhoneHud.MEASURED_SCREENS`, beside the two other things a device is told about itself,
## and is held by that module's own tests; what is left for this file is the half that belongs to this tool - reading
## a line and answering a stranger. Two copies of one device are the fault the move was made to end.

## A line that names neither way up is the standing glass, which is what every reading in this project was taken at
## until the lying one was written down.
const Screen := preload("res://tools/phone_screen.gd")


func test_a_line_that_names_no_shape_is_standing_and_lying_is_what_the_verb_says() -> void:
	assert(Screen.shape_from(PackedStringArray(["--shot"])) == "standing", "no shape named is standing")
	assert(Screen.shape_from(PackedStringArray(["--door"])) == "standing", "nothing here names a shape")
	assert(Screen.shape_from(PackedStringArray(["--lying"])) == "lying", "--lying is lying")
	assert(
		Screen.shape_from(PackedStringArray(["--lying", "--standing"])) == "lying",
		"--lying wins when both are given",
	)


## A `--word` this tool does not have is refused and the words it does have are named, because a typo would
## otherwise state the standing glass, answer every question with it, and say nothing about having done it.
func test_a_verb_this_tool_does_not_have_is_refused_and_the_known_ones_named() -> void:
	var said: String = Screen.unknown_verb(PackedStringArray(["--lynig"]))
	assert(not said.is_empty(), "--lynig is not a verb here")
	assert(said.contains("--lynig"), said)
	assert(said.contains("--lying"), said)
	var all_of_them: PackedStringArray = PackedStringArray(
		["--shot", "res://build/x.png", "--lying", "--door", "--standing"]
	)
	assert(Screen.unknown_verb(all_of_them).is_empty(), "every word on that line is one of this tool's")


## The path after `--shot`, read the same way the tool reads it: bare means the tool's own place, a following word
## means that place, and no `--shot` at all means no picture is asked for.
func test_the_shot_path_is_read_off_the_line_or_says_no_picture_was_asked_for() -> void:
	assert(Screen.shot_path(PackedStringArray([])) == "", "no --shot is no picture")
	assert(Screen.shot_path(PackedStringArray(["--shot"])) == Screen.TO_SCREEN, "a bare --shot is the tool's own place")
	assert(
		Screen.shot_path(PackedStringArray(["--shot", "res://build/x.png"])) == "res://build/x.png",
		"a word after --shot is where it goes",
	)
	assert(
		Screen.shot_path(PackedStringArray(["--lying", "--shot"])) == Screen.TO_SCREEN,
		"a bare --shot last is the same as a bare --shot",
	)
