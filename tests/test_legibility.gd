extends Node

## Words against the screen they land on: the floor taken from `PhoneHud` rather than restated, the desk left
## unjudged, and the device that has not said what it is.

const LegibilityScript := preload("res://scripts/legibility.gd")
const PhoneHudScript := preload("res://scripts/phone_hud.gd")
const ReadingSizeScript := preload("res://scripts/reading_size.gd")

## The phone this program is aimed at: the same two numbers `tools/phone_gui_probe.gd` states a device with.
const SCALE := 1.62
const DENSITY := 384.6


func test_the_body_text_this_program_lays_out_is_too_small_for_a_phone() -> void:
	# The one reading that says why any of this exists: 12 px is correct on a desk and unreadable at arm's
	# length on a phone, which is what `PhoneHud.text_size_for_a_finger` is for.
	assert(
		LegibilityScript.shortfall(PhoneHudScript.DESK_TEXT, SCALE, DENSITY) > 0,
		"the desk's own body size falls short on a phone",
	)


func test_the_floor_the_program_states_is_big_enough_by_definition() -> void:
	var least: int = PhoneHudScript.font_size(SCALE, DENSITY)
	assert(least > 0, "a density this program can read has a floor")
	assert(LegibilityScript.fits(least, SCALE, DENSITY), "and the floor fits the floor")
	assert(LegibilityScript.shortfall(least - 1, SCALE, DENSITY) == 1, "one pixel under it is one pixel short")


func test_a_desk_is_not_judged_at_all() -> void:
	assert(
		LegibilityScript.shortfall(6, 0.0, 0.0) == 0,
		"a machine that has not said what it is has no floor, and nothing is named against nothing",
	)


func test_a_control_with_no_size_of_its_own_is_left_out() -> void:
	assert(LegibilityScript.shortfall(0, SCALE, DENSITY) == 0, "there is no size to judge")


func test_the_readers_choice_only_ever_raises_the_floor() -> void:
	# `ReadingSize` is what a person asked for and `PhoneHud` is where it is applied, so the two are checked
	# together: a choice on its own moves no size at all. Restored afterwards, because both are statics and the
	# next test measures whatever this one leaves behind.
	var floor_size: int = PhoneHudScript.font_size(SCALE, DENSITY)
	PhoneHudScript.use_reading_scale(ReadingSizeScript.factor_for(ReadingSizeScript.LARGEST))
	var raised: int = PhoneHudScript.font_size(SCALE, DENSITY)
	PhoneHudScript.use_reading_scale(0.0)
	assert(raised > floor_size, "the largest reading asks for more than the standard one")
	assert(
		PhoneHudScript.font_size(SCALE, DENSITY) == floor_size,
		"and 0 puts the stated sizes back, which is what the rest of the run measures at",
	)


func test_words_too_small_are_named_with_both_numbers() -> void:
	var least: int = PhoneHudScript.font_size(SCALE, DENSITY)
	var found := LegibilityScript.faults(
		[
			{ "name": "the status line", "font": 10, "scale": SCALE, "density": DENSITY },
			{ "name": "a page's body", "font": least, "scale": SCALE, "density": DENSITY },
		]
	)
	assert(found.size() == 1, "only the one that is too small")
	assert(found[0]["least"] == least, "with the floor the program itself states")
	assert(
		LegibilityScript.sentence(found[0]) == "the status line is drawn at 10 px where this screen needs %d" % least,
		LegibilityScript.sentence(found[0]),
	)


func test_the_smallest_words_are_the_ones_named_first() -> void:
	var found := LegibilityScript.faults(
		[
			{ "name": "nearly there", "font": 11, "scale": SCALE, "density": DENSITY },
			{ "name": "hopeless", "font": 7, "scale": SCALE, "density": DENSITY },
		]
	)
	assert(found.size() == 2)
	assert(LegibilityScript.worst(found)["name"] == "hopeless")


func test_an_item_that_states_no_font_is_left_out() -> void:
	assert(LegibilityScript.faults([{ "name": "a control with no font", "scale": SCALE, "density": DENSITY }]).is_empty())
