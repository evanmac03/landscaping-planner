extends Node
## How the phone is being held, and what a camera has to do about it.
##
## The rule worth holding down is the one nobody can see from a desk: the window follows the device and the
## camera does not, so a picture taken with the phone on its side arrives on its side and the page has to turn
## it back.
##
## What the turn is worked out *from* is the whole of this file's reason to exist, and it is the shape of the
## room the page is drawn in - taller than it is wide, or not. It is deliberately *not* the orientation the
## program asked the phone for: that call answers with a **request** (six, follow the device, or a pinned
## landscape) rather than with a fact, so on the phone this was built for a window told to follow the device
## the reading was neither portrait nor reverse-portrait, every branch fell through, and a picture taken with
## the phone held upright was left in the sensor's landscape frame. A request cannot answer a question about a
## fact, and how big the room is is a fact.

const HeldOrientationScript := preload("res://scripts/held_orientation.gd")

## The phone this was built for, both ways round, and the two rooms nothing can be said about.
const HELD_UPRIGHT := Vector2i(1080, 2340)
const ON_ITS_SIDE := Vector2i(2340, 1080)
const SQUARE := Vector2i(1200, 1200)
const NOTHING_MEASURED := Vector2i.ZERO


## A phone held upright is a quarter turn away from the sensor; a phone held on its side is already where the
## sensor is, which is why the camera on a phone used in landscape needs nothing done to it.
func test_a_room_that_stands_up_turns_the_picture_a_quarter_and_one_on_its_side_turns_it_none() -> void:
	assert(
		HeldOrientationScript.turns_for_a_room(HELD_UPRIGHT) == 1,
		"held upright against a landscape sensor is one quarter turn"
	)
	assert(
		HeldOrientationScript.turns_for_a_room(ON_ITS_SIDE) == 0,
		"the frame a phone's sensor makes is a landscape one, so a landscape room needs no turning"
	)


## A room nobody could measure leaves the picture alone, and so does one with no long side: a turn invented
## here would put a plant on its side in the one case where nothing at all is known.
func test_a_room_nothing_can_be_said_about_leaves_the_picture_alone() -> void:
	assert(
		HeldOrientationScript.turns_for_a_room(NOTHING_MEASURED) == 0,
		"a room nobody measured is not turned"
	)
	assert(
		HeldOrientationScript.turns_for_a_room(SQUARE) == 0,
		"and a square has no long side to stand up by"
	)


## Taller than wide is the question a page that has to fit asks, and the camera's turn asks the same one of
## the same room - which is what keeps there being one answer rather than two that can disagree.
func test_a_room_taller_than_it_is_wide_stands_up() -> void:
	assert(HeldOrientationScript.stands_up(HELD_UPRIGHT), "a phone held upright stands up")
	assert(not HeldOrientationScript.stands_up(ON_ITS_SIDE), "a phone on its side does not")
	assert(
		not HeldOrientationScript.stands_up(NOTHING_MEASURED),
		"and neither does a room nobody measured, rather than half of one"
	)


## The words say how the room stands, and no more than that: a shape can tell standing up from on its side
## and *cannot* tell which end is up, so a line claiming an upside-down phone would be invention. The line
## this replaced said "held on its side" over a portrait window, which is exactly how the fault in the camera
## page was found.
func test_the_words_say_how_the_room_stands_and_never_guess_at_which_end_is_up() -> void:
	assert(
		HeldOrientationScript.words_for_a_room(HELD_UPRIGHT) == "held upright",
		"a room taller than it is wide is held upright"
	)
	assert(
		HeldOrientationScript.words_for_a_room(ON_ITS_SIDE) == "held on its side",
		"and one wider than it is tall is on its side"
	)
	assert(
		not HeldOrientationScript.words_for_a_room(HELD_UPRIGHT).contains("upside"),
		"a shape cannot see which end is up, so the words never claim it"
	)
	assert(
		not HeldOrientationScript.words_for_a_room(ON_ITS_SIDE).contains("upside"),
		"either way round"
	)
