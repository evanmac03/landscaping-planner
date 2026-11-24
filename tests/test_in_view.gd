extends Node

## The rule for a control the room cannot hold: how far past each edge it goes, whether any of it is left, and
## the two cases that are deliberately not faults - a control flush with the edge, and a room that is not there.

const InViewScript := preload("res://scripts/in_view.gd")

const ROOM := Vector2i(1600, 900)


func test_a_control_inside_the_room_fits() -> void:
	assert(InViewScript.fits(Rect2i(210, 98, 1180, 802), ROOM), "a page inside the screen is inside it")


func test_a_control_flush_with_the_edge_fits() -> void:
	assert(
		InViewScript.fits(Rect2i(0, 0, 1600, 900), ROOM),
		"a control the size of the room fits it exactly, and touching an edge is being inside",
	)


func test_a_control_past_the_right_edge_says_how_far() -> void:
	assert(
		InViewScript.off_the_edge(Rect2i(1400, 40, 190, 31), ROOM) == Vector4i.ZERO,
		"a control ending at 1590 is inside a 1600 room, and being short of the edge is not being past it",
	)
	var off: Vector4i = InViewScript.off_the_edge(Rect2i(1450, 40, 190, 31), ROOM)
	assert(off.z == 40, "a control ending at 1640 hangs 40 px past the right edge")
	assert(off.x == 0 and off.y == 0 and off.w == 0, "and past no other edge")


func test_a_control_hanging_off_two_edges_names_both() -> void:
	var over: Vector4i = InViewScript.off_the_edge(Rect2i(-12, 870, 400, 60), ROOM)
	assert(over.x == 12, "twelve px past the left edge")
	assert(over.w == 30, "and thirty past the foot")
	assert(over.y == 0 and over.z == 0, "while the other two sides are inside")


func test_a_control_off_the_screen_altogether_is_named_as_gone() -> void:
	assert(
		InViewScript.wholly_outside(Rect2i(1700, 40, 190, 31), ROOM),
		"a control starting past the right edge has none of itself left",
	)
	assert(
		not InViewScript.wholly_outside(Rect2i(1500, 40, 190, 31), ROOM),
		"while one that only hangs over the edge is still mostly there",
	)


func test_a_control_wholly_above_the_room_is_gone_too() -> void:
	assert(InViewScript.wholly_outside(Rect2i(100, -80, 200, 60), ROOM), "a control above the screen is gone")


func test_a_room_that_is_not_there_cannot_hold_anything() -> void:
	assert(
		InViewScript.fits(Rect2i(0, 0, 10, 10), Vector2i.ZERO),
		"a viewport of no size, which is what a headless run has, has no outside to be on",
	)
	assert(InViewScript.faults([{ "name": "a button", "rect": Rect2i(0, 0, 10, 10), "room": Vector2i.ZERO }]).is_empty(), "so nothing is reported against it")


func test_a_control_a_little_past_the_edge_reads_as_tight_not_as_gone() -> void:
	var found: Array[Dictionary] = InViewScript.faults(
		[{ "name": "the ground view button", "rect": Rect2i(1450, 40, 190, 31), "room": ROOM }]
	)
	assert(found.size() == 1, "one control past the edge is one fault")
	assert(
		InViewScript.sentence(found[0])
		== "the ground view button is 40 px past the right edge of a 1600 x 900 room, and part of it can never be seen",
		"and it reads as what it is and how far",
	)
	assert(InViewScript.worst(found[0]) == 40, "with the worst side named as the number worth reading")


func test_a_control_wholly_off_the_screen_reads_as_gone() -> void:
	var found: Array[Dictionary] = InViewScript.faults(
		[{ "name": "the ground view button", "rect": Rect2i(1700, 40, 190, 31), "room": ROOM }]
	)
	assert(
		InViewScript.sentence(found[0])
		== "the ground view button is off the screen altogether - 290 px past the right edge of a 1600 x 900 room",
		"a control nobody can reach reads as gone rather than as tight",
	)


func test_only_what_leaves_the_room_is_a_fault() -> void:
	var found: Array[Dictionary] = InViewScript.faults(
		[
			{ "name": "inside", "rect": Rect2i(100, 100, 200, 100), "room": ROOM },
			{ "name": "outside", "rect": Rect2i(-40, 100, 200, 100), "room": ROOM },
		]
	)
	assert(found.size() == 1, "a screen is not a problem to be found everywhere on")
	assert(found[0]["name"] == "outside", "and the one named is the one past the edge")
