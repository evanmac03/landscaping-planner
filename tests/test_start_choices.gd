extends Node
## The front door: the two things the program is opened to do, and when the door is shown at all.
##
## The rule held here is the one a person would notice immediately if it were wrong either way: a door that
## appeared in front of work somebody had already done, or a door that failed to appear on a launch with
## nothing behind it.

const StartScript := preload("res://scripts/start_choices.gd")


## The state every launch starts in: no file, nothing done. This is the only state the door is for.
func test_a_drawing_nobody_has_touched_and_never_saved_is_nothing_to_open() -> void:
	assert(
		StartScript.should_show("", false),
		"the door is shown when there is nothing behind it"
	)


## A drawing that came from a file is something to come back to, and the door does not stand in front of it.
func test_a_drawing_that_came_from_a_file_is_something_to_open() -> void:
	assert(
		not StartScript.should_show("user://drawings/Backyard Design.json", false),
		"a drawing with a file is already open"
	)


## An untitled drawing somebody has drawn in is work, which is the distinction the whole rule turns on:
## nothing stated is not the same as nothing open.
func test_work_in_an_untitled_drawing_is_something_to_open() -> void:
	assert(not StartScript.should_show("", true), "unsaved work is work")


## Exactly two choices, in the order they are shown: the drawing board first, because the drawing is what
## this program is for, and the camera beside it rather than buried under it.
func test_the_front_door_offers_the_two_things_this_program_is_for() -> void:
	var ids: Array[StringName] = StartScript.ids()
	assert(ids.size() == 2, "two choices: %s" % str(ids))
	assert(ids[0] == StartScript.DESIGN, "the drawing board is the first: %s" % ids[0])
	assert(ids[1] == StartScript.CAMERA, "and the camera the second: %s" % ids[1])


## Every choice is a button with words that say where it leads, and no two of them say the same thing - a
## door with two identical buttons is not a choice.
func test_every_choice_says_where_it_leads() -> void:
	var buttons: Array[String] = []
	for choice: Dictionary in StartScript.CHOICES:
		var label: String = String(choice.get("label", ""))
		var line: String = String(choice.get("line", ""))
		assert(not label.is_empty(), "a choice has a button: %s" % str(choice))
		assert(not line.is_empty(), "and a sentence under it: %s" % label)
		assert(not buttons.has(label), "two buttons must not read the same: %s" % label)
		buttons.append(label)
	assert(buttons.size() == StartScript.CHOICES.size(), "every choice was read")


## The screen behind the door is a sheet and not a window: nothing of the drawing board shows through it.
##
## This is the rule the program got wrong first. The door stood as it should have - and so did a fully
## furnished yard, the palette of tools and three panels of readings, all of them the design suite's room. A
## person arriving to take a photograph was shown a garden and a set of drawing tools instead of a choice.
## The sheet is opaque, and this is where that is held.
func test_the_screen_behind_the_door_shows_nothing_through_it() -> void:
	assert(
		StartScript.SCREEN.a >= 1.0,
		"the door's screen must be opaque, or the garden shows through it: %s" % StartScript.SCREEN
	)


## Closing the door lands in the drawing board rather than on a dark screen. The answer is the model's, so
## the page cannot invent a different one.
func test_closing_the_door_means_the_drawing_board() -> void:
	assert(
		StartScript.dismissed() == StartScript.DESIGN,
		"a dismissed front door is the drawing, not nothing: %s" % StartScript.dismissed()
	)