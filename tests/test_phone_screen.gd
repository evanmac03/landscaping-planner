extends Node
## The phone-shaped desk scene's own rules, held down where no window can be opened.
##
## The scene's job is to make a window the size of a phone's glass and put the program in it, which a test runner
## has no display for - so what is held here is everything that decides **which phone a run states**: the way up the
## line asks for, the glass and the usable rectangle each way up is stated with, and the verb a typo is refused by.
## A run that quietly states the wrong shape answers every question with the wrong device and looks perfectly
## healthy doing it, which is the whole reason these three are here rather than left to a person's eye.


## A line that names neither way up is the standing glass, which is what every reading in this project was taken at
## until the lying one was written down.
const Screen := preload("res://tools/phone_screen.gd")


func test_a_line_that_names_no_shape_is_standing_and_lying_is_what_the_verb_says() -> void:
	assert(Screen.shape_from(PackedStringArray(["--shot"])) == "standing", "no shape named is standing")
	assert(Screen.shape_from(PackedStringArray(["--door"])) == "standing", "nothing here names a shape")
	assert(Screen.shape_from(PackedStringArray(["--lying"])) == "lying", "--lying is lying")
	assert(
		Screen.shape_from(PackedStringArray(["--lying", "--standing"])) == "lying",
		"--lying wins when both are given"
	)


## Both ways up are the A16W's own numbers, read off its own block: standing is 1080 by 2340 with the cutout at the
## top, lying is 2340 by 1080 with the same 100 px turned to the **left**. The usable rectangle is the whole glass
## less that inset and is a rectangle rather than an inset, because a rectangle is what the door takes.
func test_each_way_up_states_the_glass_and_the_usable_rectangle_the_device_itself_reports() -> void:
	var standing: Dictionary = Screen.SHAPES["standing"]
	assert(standing["glass"] == Vector2i(1080, 2340), str(standing["glass"]))
	assert(standing["usable"] == Rect2i(0, 100, 1080, 2240), str(standing["usable"]))
	var lying: Dictionary = Screen.SHAPES["lying"]
	assert(lying["glass"] == Vector2i(2340, 1080), str(lying["glass"]))
	assert(lying["usable"] == Rect2i(100, 0, 2240, 1080), str(lying["usable"]))


## The two ways up are the same glass turned, which is the one thing that has to be true of them: the usable
## rectangle's shorter side is the inset itself, and neither states a glass the other could be mistaken for.
func test_the_two_ways_up_are_the_same_glass_turned() -> void:
	var standing: Dictionary = Screen.SHAPES["standing"]
	var lying: Dictionary = Screen.SHAPES["lying"]
	var upright: Vector2i = standing["glass"]
	var sideways: Vector2i = lying["glass"]
	assert(sideways == Vector2i(upright.y, upright.x), "%s is not %s turned" % [sideways, upright])
	assert(sideways != upright, "one glass, two ways up - and the two are not the same rectangle")


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
		"a word after --shot is where it goes"
	)
	assert(
		Screen.shot_path(PackedStringArray(["--lying", "--shot"])) == Screen.TO_SCREEN,
		"a bare --shot last is the same as a bare --shot"
	)
