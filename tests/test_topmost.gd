extends Node

## What a tap would reach: the last rectangle in drawing order that holds the point, the two ways a tap fails -
## reaching nothing, and reaching something switched off - and the boundary of a rectangle.

const TopmostScript := preload("res://scripts/topmost.gd")

const BACK := { "name": "the palette", "rect": Rect2i(0, 600, 1600, 300) }
const FRONT := { "name": "the figures page", "rect": Rect2i(210, 98, 1180, 802) }


func test_nothing_at_all_is_reached_when_no_box_holds_the_point() -> void:
	var boxes: Array = [BACK]
	assert(TopmostScript.at(Vector2i(100, 100), boxes).is_empty(), "a point above the palette is on nothing")


func test_the_only_box_holding_the_point_is_the_one_reached() -> void:
	var boxes: Array = [BACK, FRONT]
	assert(
		TopmostScript.at(Vector2i(100, 700), boxes)["name"] == "the palette",
		"a point on the palette alone reaches the palette",
	)


func test_a_box_drawn_later_wins_the_point_they_share() -> void:
	var boxes: Array = [BACK, FRONT]
	assert(
		TopmostScript.at(Vector2i(300, 700), boxes)["name"] == "the figures page",
		"where a page over the board holds the point, the page is what a tap meets",
	)


func test_the_order_given_is_the_order_drawn() -> void:
	var boxes: Array = [FRONT, BACK]
	assert(
		TopmostScript.at(Vector2i(300, 700), boxes)["name"] == "the palette",
		"the walk decides which of two is in front, and this reads the order it gives",
	)


func test_a_rectangle_holds_its_far_edge_only_where_it_starts() -> void:
	var boxes: Array = [{ "name": "a button", "rect": Rect2i(100, 200, 200, 50) }]
	assert(not TopmostScript.at(Vector2i(100, 200), boxes).is_empty(), "the corner it starts at is on it")
	assert(not TopmostScript.at(Vector2i(299, 249), boxes).is_empty(), "and so is the last pixel inside it")
	assert(TopmostScript.at(Vector2i(300, 200), boxes).is_empty(), "while the pixel past its width is not")


func test_a_tap_meant_for_a_button_and_reaching_another_is_a_mistake() -> void:
	var boxes: Array = [BACK, FRONT]
	var mistake: Dictionary = TopmostScript.mistake(Vector2i(300, 700), boxes, "the row list")
	assert(not mistake.is_empty(), "a driver aiming at a control under a page is not reaching it")
	assert(
		TopmostScript.sentence(mistake)
		== "a tap at (300, 700) meant for the row list would reach the figures page instead",
		"and the answer names what it would reach instead, which is the answer being looked for",
	)


func test_a_tap_that_reaches_nothing_is_a_mistake_too() -> void:
	var boxes: Array = [BACK]
	var mistake: Dictionary = TopmostScript.mistake(Vector2i(100, 100), boxes, "the Line 1 button")
	assert(not mistake.is_empty(), "a point on nothing is nothing being pressed")
	assert(
		TopmostScript.sentence(mistake) == "a tap at (100, 100) meant for the Line 1 button would reach nothing there",
		"and it reads as nothing being there rather than as something else being there",
	)


func test_a_tap_on_what_it_meant_is_no_mistake() -> void:
	var boxes: Array = [BACK]
	assert(
		TopmostScript.mistake(Vector2i(100, 700), boxes, "the palette").is_empty(),
		"reaching the control meant is nothing to report",
	)


func test_a_switched_off_button_is_reached_and_says_so() -> void:
	var boxes: Array = [{ "name": "Finish", "rect": Rect2i(100, 100, 80, 30), "enabled": false }]
	var mistake: Dictionary = TopmostScript.mistake(Vector2i(140, 115), boxes, "Finish")
	assert(not mistake.is_empty(), "a button that is there but switched off does not answer")
	assert(bool(mistake["switched_off"]), "and the answer says the tap did reach it")
	assert(
		TopmostScript.sentence(mistake)
		== "a tap at (140, 115) does reach Finish, and it is switched off, so nothing happens",
		"which is the answer a person looking for a silent button wants",
	)


func test_a_box_that_answers_is_no_mistake_even_under_others() -> void:
	var boxes: Array = [BACK, { "name": "Finish", "rect": Rect2i(100, 600, 80, 30) }, FRONT]
	assert(
		TopmostScript.mistake(Vector2i(140, 615), boxes, "Finish").is_empty(),
		"a switched-on button of its own is reached like any other",
	)


func test_the_middle_of_a_control_is_where_it_is_pressed() -> void:
	assert(
		TopmostScript.middle(Rect2i(100, 200, 200, 50)) == Vector2i(200, 225),
		"the middle is half of each side along, and is on the control",
	)
