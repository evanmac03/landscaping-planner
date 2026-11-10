extends Node
## How the phone is being held, and what a camera has to do about it.
##
## The rule worth holding down is the one nobody can see from a desk: the window follows the device and the
## camera does not, so a picture taken with the phone on its side arrives on its side and the page has to turn
## it back. Every way a phone can be held gets its own answer here, and a device that answers nothing gets the
## landscape one rather than a guess.

const LandscapeScript := preload("res://scripts/held_orientation.gd")

# The device's own enum, as the phone reports it: landscape is the default a phone's camera frame arrives in.
const LANDSCAPE := 0
const PORTRAIT := 1
const OTHER_LANDSCAPE := 2
const UPSIDE_DOWN := 3


## A phone held upright is a quarter turn away from the sensor; a phone held on its side is already where the
## sensor is, which is why the camera on a phone used in landscape needs nothing done to it.
func test_a_phone_held_upright_turns_the_picture_a_quarter_and_one_on_its_side_turns_it_none() -> void:
	assert(
		LandscapeScript.quarter_turns(LANDSCAPE, LANDSCAPE, PORTRAIT, OTHER_LANDSCAPE, UPSIDE_DOWN) == 0,
		"the frame a phone's sensor makes is a landscape one, so landscape needs no turning"
	)
	assert(
		LandscapeScript.quarter_turns(PORTRAIT, LANDSCAPE, PORTRAIT, OTHER_LANDSCAPE, UPSIDE_DOWN) == 1,
		"held upright against a landscape sensor is one quarter turn"
	)
	assert(
		LandscapeScript.quarter_turns(UPSIDE_DOWN, LANDSCAPE, PORTRAIT, OTHER_LANDSCAPE, UPSIDE_DOWN) == 3,
		"upside down against the sensor is three quarters, not a mirror"
	)


## Four ways to hold a phone and four different answers: a turn of one, two or three quarters, and the
## landscape case for a device that will not say.
func test_every_way_a_phone_can_be_held_gets_exact_quarter_turns_or_none() -> void:
	var landscape: int = LandscapeScript.quarter_turns(
		LANDSCAPE, LANDSCAPE, PORTRAIT, OTHER_LANDSCAPE, UPSIDE_DOWN
	)
	var other_landscape: int = LandscapeScript.quarter_turns(
		OTHER_LANDSCAPE, LANDSCAPE, PORTRAIT, OTHER_LANDSCAPE, UPSIDE_DOWN
	)
	var portrait: int = LandscapeScript.quarter_turns(PORTRAIT, LANDSCAPE, PORTRAIT, OTHER_LANDSCAPE, UPSIDE_DOWN)
	var upside_down: int = LandscapeScript.quarter_turns(
		UPSIDE_DOWN, LANDSCAPE, PORTRAIT, OTHER_LANDSCAPE, UPSIDE_DOWN
	)
	assert(
		[landscape, portrait, other_landscape, upside_down] == [0, 1, 2, 3],
		"the four holds are the four turns: %s" % str([landscape, portrait, other_landscape, upside_down])
	)
	assert(
		LandscapeScript.quarter_turns(99, LANDSCAPE, PORTRAIT, OTHER_LANDSCAPE, UPSIDE_DOWN) == 0,
		"and a device that says nothing readable leaves the picture alone rather than guessing at a turn"
	)


## Taller than wide is the question a page that has to fit asks, and it is asked of the two portrait answers
## together rather than of one of them.
func test_a_screen_taller_than_it_is_wide_stands_up() -> void:
	assert(
		LandscapeScript.stands_up(PORTRAIT, PORTRAIT, UPSIDE_DOWN),
		"a phone held upright stands up"
	)
	assert(
		LandscapeScript.stands_up(UPSIDE_DOWN, PORTRAIT, UPSIDE_DOWN),
		"and so does one held upside down - it is still taller than it is wide"
	)
	assert(
		not LandscapeScript.stands_up(LANDSCAPE, PORTRAIT, UPSIDE_DOWN),
		"a phone on its side does not"
	)
	assert(
		not LandscapeScript.stands_up(OTHER_LANDSCAPE, PORTRAIT, UPSIDE_DOWN),
		"whichever way round that side is"
	)


## Every hold reads as words a page can put in a sentence, and no two of them read the same - a line that
## said "held on its side" for an upside-down phone would be worse than saying nothing.
func test_every_hold_reads_as_words_and_no_two_of_them_the_same() -> void:
	var said: Array[String] = []
	for screen: int in [LANDSCAPE, PORTRAIT, OTHER_LANDSCAPE, UPSIDE_DOWN]:
		var words: String = LandscapeScript.words_for(
			screen, LANDSCAPE, PORTRAIT, OTHER_LANDSCAPE, UPSIDE_DOWN
		)
		assert(not words.is_empty(), "every hold gets words: %d" % screen)
		assert(not said.has(words), "two holds must not read the same: %s" % words)
		said.append(words)
	assert(said.size() == 4, "four holds, four lines: %s" % str(said))