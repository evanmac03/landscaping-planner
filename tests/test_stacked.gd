extends Node

## Two things of one kind in one rectangle, and the pairs that are deliberately not findings.

const StackedScript := preload("res://scripts/stacked.gd")


func test_two_buttons_in_one_rectangle_are_named_as_one_finding() -> void:
	var found := StackedScript.faults(
		[
			{ "name": "the water panel's head", "kind": "Button", "rect": Rect2i(1292, 107, 280, 31) },
			{ "name": "the light panel's head", "kind": "Button", "rect": Rect2i(1292, 107, 280, 31) },
		]
	)
	assert(found.size() == 1, "one pair, one finding")
	assert(found[0]["a"] == "the water panel's head", "named in the order they are drawn")
	assert(found[0]["b"] == "the light panel's head")


func test_a_label_standing_on_a_panel_is_not_a_finding() -> void:
	var found := StackedScript.faults(
		[
			{ "name": "the plate", "kind": "Panel", "rect": Rect2i(0, 0, 200, 100) },
			{ "name": "the caption", "kind": "Label", "rect": Rect2i(0, 0, 200, 100) },
		]
	)
	assert(found.is_empty(), "a control standing on a panel is the design, and they are different kinds")


func test_two_controls_that_only_overlap_are_left_alone() -> void:
	var found := StackedScript.faults(
		[
			{ "name": "one", "kind": "Button", "rect": Rect2i(0, 0, 100, 40) },
			{ "name": "the other", "kind": "Button", "rect": Rect2i(1, 0, 100, 40) },
		]
	)
	assert(found.is_empty(), "a pixel apart is two buttons a person can tell apart")


func test_three_in_one_rectangle_are_three_pairs() -> void:
	var found := StackedScript.faults(
		[
			{ "name": "one", "kind": "Button", "rect": Rect2i(0, 0, 50, 50) },
			{ "name": "two", "kind": "Button", "rect": Rect2i(0, 0, 50, 50) },
			{ "name": "three", "kind": "Button", "rect": Rect2i(0, 0, 50, 50) },
		]
	)
	assert(found.size() == 3, "each of the three has a twin, and there are three ways to be a pair")


func test_a_finding_names_the_kind_and_both_controls() -> void:
	var found := StackedScript.faults(
		[
			{ "name": "head", "kind": "Button", "rect": Rect2i(10, 20, 30, 40) },
			{ "name": "hatch", "kind": "Button", "rect": Rect2i(10, 20, 30, 40) },
		]
	)
	assert(
		StackedScript.sentence(found[0])
		== "head and hatch are both Button at (10, 20) sized 30 x 40, so only the later one is ever seen",
		StackedScript.sentence(found[0]),
	)


func test_an_item_with_no_kind_or_no_rectangle_is_left_out() -> void:
	var found := StackedScript.faults(
		[
			{ "name": "a control with no rectangle", "kind": "Button" },
			{ "name": "a control with no kind", "rect": Rect2i(0, 0, 10, 10) },
		]
	)
	assert(found.is_empty(), "a pair cannot be found in a control that is not fully stated")
