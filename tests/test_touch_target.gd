extends Node

## A target a finger is meant to press: the shorter side that counts, who decides whether a finger is being
## served, and the sentence a reader gets.

const TouchTargetScript := preload("res://scripts/touch_target.gd")


func test_a_target_the_size_a_finger_wants_fits() -> void:
	assert(TouchTargetScript.fits(Rect2i(0, 0, 44, 44)), "44 on the shorter side is the guidance")


func test_a_target_one_pixel_short_is_named_one_pixel_short() -> void:
	assert(TouchTargetScript.shortfall(Rect2i(0, 0, 80, 43)) == 1, "one pixel")


func test_a_wide_but_short_button_is_short_by_its_shorter_side() -> void:
	# The desk's own button: 200 across and 31 down. Its width is generous and its height is what a thumb needs.
	assert(
		TouchTargetScript.shortfall(Rect2i(28, 79, 352, 31)) == 13,
		"the longer side cannot make up for the shorter one",
	)


func test_whether_a_finger_is_being_served_is_the_callers_to_say() -> void:
	var button := [
		{ "name": "Line", "rect": Rect2i(28, 115, 103, 54) },
		{ "name": "Fit", "rect": Rect2i(1336, 21, 28, 31) },
	]
	assert(TouchTargetScript.faults(button).size() == 1, "on a finger, the 28 x 31 Fit button is too small")
	assert(TouchTargetScript.faults(button, 28).is_empty(), "and a mouse needs nothing more than what the mouse has")


func test_a_target_with_no_rectangle_is_left_out() -> void:
	assert(TouchTargetScript.faults([{ "name": "a control with no rectangle" }]).is_empty())


func test_the_target_furthest_short_is_the_one_named_first() -> void:
	var found := TouchTargetScript.faults(
		[
			{ "name": "nearly there", "rect": Rect2i(0, 0, 100, 43) },
			{ "name": "hopeless", "rect": Rect2i(0, 0, 100, 12) },
		]
	)
	var worst: Dictionary = TouchTargetScript.worst(found)
	assert(worst["name"] == "hopeless", "the furthest short of what a finger wants")


func test_a_target_reads_as_its_size_and_how_short_it_is() -> void:
	var found := TouchTargetScript.faults([{ "name": "the Fit button", "rect": Rect2i(1336, 21, 28, 31) }])
	assert(
		TouchTargetScript.sentence(found[0]) == "the Fit button is 28 x 31, 16 px short of the 44 a finger wants",
		TouchTargetScript.sentence(found[0]),
	)


func test_nothing_is_short_of_nothing() -> void:
	assert(TouchTargetScript.shortfall(Rect2i(0, 0, 4, 4), 0) == 0, "a caller asking for no least gets no finding")
