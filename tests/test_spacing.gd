extends Node

## Two targets a finger has to choose between: the gap, the pairs that are deliberately not findings, and the
## overlap worded as what it is.

const SpacingScript := preload("res://scripts/spacing.gd")


func test_a_gap_the_width_a_finger_wants_is_left_alone() -> void:
	var found := SpacingScript.faults(
		[{ "name": "one", "rect": Rect2i(0, 0, 40, 40) }, { "name": "two", "rect": Rect2i(48, 0, 40, 40) }]
	)
	assert(found.is_empty(), "8 px of clear space is the floor, and 8 is not below it")


func test_a_gap_one_pixel_under_the_floor_is_named() -> void:
	var found := SpacingScript.faults(
		[{ "name": "Trim", "rect": Rect2i(88, 348, 50, 54) }, { "name": "Extend", "rect": Rect2i(145, 348, 62, 54) }]
	)
	assert(found.size() == 1, "7 px between two tool buttons")
	assert(found[0]["gap"] == 7, "and the gap is the number a reader gets")
	assert(
		SpacingScript.sentence(found[0]) == "Trim and Extend are 7 px apart where a finger wants 8",
		SpacingScript.sentence(found[0]),
	)


func test_two_buttons_touching_are_named_as_an_overlap() -> void:
	var found := SpacingScript.faults(
		[{ "name": "one", "rect": Rect2i(0, 0, 40, 40) }, { "name": "two", "rect": Rect2i(36, 0, 40, 40) }]
	)
	assert(found.size() == 1, "an overlap is the worst gap there is")
	assert(found[0]["gap"] == 0, "and it has no distance to quote")
	assert(
		SpacingScript.sentence(found[0])
		== "one and two overlap, so a tap at the seam reaches whichever the engine draws later",
		SpacingScript.sentence(found[0]),
	)


func test_two_controls_in_one_rectangle_are_left_to_stacked() -> void:
	var found := SpacingScript.faults(
		[
			{ "name": "the water head", "rect": Rect2i(10, 20, 30, 40) },
			{ "name": "the light head", "rect": Rect2i(10, 20, 30, 40) },
		]
	)
	assert(found.is_empty(), "one defect is named by one instrument, and that one is Stacked's")


func test_a_button_standing_on_a_plate_is_not_a_pair() -> void:
	var found := SpacingScript.faults(
		[
			{ "name": "the plate", "rect": Rect2i(0, 0, 200, 100) },
			{ "name": "the button", "rect": Rect2i(10, 10, 40, 30) },
		]
	)
	assert(found.is_empty(), "a control inside another is not a target beside a target")


func test_a_neighbour_further_up_the_screen_is_apart_by_its_nearer_axis() -> void:
	var found := SpacingScript.faults(
		[{ "name": "one", "rect": Rect2i(0, 0, 40, 40) }, { "name": "two", "rect": Rect2i(42, 100, 40, 40) }]
	)
	assert(found.is_empty(), "two across and sixty down is sixty apart to a finger at the corner")


func test_a_corner_near_miss_is_as_close_as_the_corner() -> void:
	assert(SpacingScript.gap_between(Rect2i(0, 0, 40, 40), Rect2i(43, 43, 40, 40)) == 3, "3 across, 3 down")


func test_the_tightest_pair_is_the_one_named_first() -> void:
	var found := SpacingScript.faults(
		[
			{ "name": "nearly", "rect": Rect2i(0, 0, 40, 40) },
			{ "name": "nearly's neighbour", "rect": Rect2i(47, 0, 40, 40) },
			{ "name": "hopeless", "rect": Rect2i(46, 60, 40, 40) },
			{ "name": "hopeless's neighbour", "rect": Rect2i(47, 60, 40, 40) },
		]
	)
	assert(found.size() == 2, "two pairs are too close")
	assert(SpacingScript.closest(found)["a"] == "hopeless", "and one of them is much closer than the other")


func test_an_item_with_no_rectangle_is_left_out() -> void:
	assert(SpacingScript.faults([{ "name": "a control with no rectangle" }]).is_empty())
