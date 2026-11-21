extends Node

## The rule for a thing cut to a box smaller than the room around it had to give: the shortfall, the slack, the
## search outwards for a box that could have grown, and the two ways it is *not* a fault.
##
## Every item here is built by hand rather than measured, because the rule is arithmetic about two numbers and
## a list of boxes, and a test that had to bring up a scene to state them would be testing the scene.

const RoomToSpareScript := preload("res://scripts/room_to_spare.gd")


## An item as the walk hands one in: a thing cut, and the boxes outwards from it, nearest first.
func _an_item(name: String, given: Vector2, wanted: Vector2, around: Array) -> Dictionary:
	return { "name": name, "given": given, "wanted": wanted, "around": around }


## One box outwards: how big it is, and how much of it is in use. The difference is what it could give away.
func _a_box(name: String, size: Vector2, used: Vector2) -> Dictionary:
	return { "name": name, "size": size, "used": used }


func test_a_thing_given_less_than_it_wants_says_by_how_much() -> void:
	var short: Vector2 = RoomToSpareScript.shortfall(Vector2(300, 80), Vector2(500, 80))
	assert(short.x == 200.0, "two hundred pixels of width are missing")
	assert(short.y == 0.0, "and nothing is missing in height")


func test_a_thing_given_more_than_it_wants_is_short_of_nothing() -> void:
	var short: Vector2 = RoomToSpareScript.shortfall(Vector2(600, 400), Vector2(500, 80))
	assert(short == Vector2.ZERO, "a box bigger than it needs to be is not cut by a negative amount")


func test_a_box_with_room_standing_empty_knows_what_it_could_give_away() -> void:
	var room: Vector2 = RoomToSpareScript.slack(Vector2(500, 700), Vector2(300, 400))
	assert(room == Vector2(200, 300), "the difference is the room it had to give")
	assert(
		RoomToSpareScript.slack(Vector2(100, 100), Vector2(300, 400)) == Vector2.ZERO,
		"and a box with more in it than it holds has nothing to give",
	)


func test_the_first_box_outwards_with_room_is_the_one_that_could_have_given_it() -> void:
	var around: Array = [
		_a_box("the box right around it", Vector2(300, 90), Vector2(300, 90)),
		_a_box("the column above that", Vector2(400, 500), Vector2(400, 100)),
		_a_box("the panel above that", Vector2(900, 900), Vector2(500, 500)),
	]
	var giver: Dictionary = RoomToSpareScript.first_with_room(around, 200.0, "down")
	assert(giver["name"] == "the column above that", "the nearest box with room is the one worth naming")


func test_a_box_with_room_across_when_the_cut_is_down_is_left_alone() -> void:
	var around: Array = [_a_box("a wide flat box", Vector2(900, 100), Vector2(300, 100))]
	assert(
		RoomToSpareScript.first_with_room(around, 200.0, "down").is_empty(),
		"room it has across is no use to a thing cut down",
	)


## The regression this rule was corrected for: a box accepted for room it had on *either* axis was then named
## for a cut running on the other one, which printed "cut across by 484 px, and Scroll had 0 px to give".
func test_a_box_is_never_named_for_room_it_has_on_the_other_axis() -> void:
	var item: Dictionary = _an_item(
		"a wide list",
		Vector2(300, 100),
		Vector2(784, 100),
		[_a_box("the scroll around it", Vector2(300, 900), Vector2(300, 0))],
	)
	assert(RoomToSpareScript.faults([item]).is_empty(), "nine hundred pixels to give down is no use to a thing cut across")


func test_a_thing_cut_while_a_box_around_it_had_room_is_a_fault() -> void:
	var item: Dictionary = _an_item(
		"a text box",
		Vector2(300, 80),
		Vector2(300, 400),
		[_a_box("the column around it", Vector2(300, 500), Vector2(300, 100))],
	)
	var found: Array[Dictionary] = RoomToSpareScript.faults([item])
	assert(found.size() == 1, "a box made too small while the room was there is a fault")
	assert(
		RoomToSpareScript.sentence(found[0])
		== "a text box is cut down by 320 px, and the column around it had 400 px to give",
		"and it reads as what was cut and which box had room",
	)


func test_a_thing_cut_in_a_window_with_no_room_anywhere_is_not_a_fault() -> void:
	var item: Dictionary = _an_item(
		"a text box",
		Vector2(300, 80),
		Vector2(300, 400),
		[_a_box("the column around it", Vector2(300, 100), Vector2(300, 100))],
	)
	assert(
		RoomToSpareScript.faults([item]).is_empty(),
		"a thing in a window that is genuinely too small is not a box made too small",
	)


func test_a_thing_that_is_not_cut_is_not_a_fault_however_much_room_there_is() -> void:
	var item: Dictionary = _an_item(
		"a text box",
		Vector2(600, 400),
		Vector2(300, 200),
		[_a_box("the column around it", Vector2(900, 900), Vector2(300, 200))],
	)
	assert(RoomToSpareScript.faults([item]).is_empty(), "room to give is only a fault if something was cut")


func test_a_thing_cut_both_ways_is_named_by_the_worse_of_them() -> void:
	var item: Dictionary = _an_item(
		"a caption",
		Vector2(200, 20),
		Vector2(260, 90),
		[_a_box("the panel around it", Vector2(600, 600), Vector2(200, 40))],
	)
	var found: Array[Dictionary] = RoomToSpareScript.faults([item])
	assert(found.size() == 1, "cut both ways is still one fault, not two")
	assert(RoomToSpareScript.axis(found[0]) == "down", "the worse of the two directions names it")
	assert(RoomToSpareScript.cut_by(found[0]) == 70.0, "and the amount is the worse of the two")
	assert(RoomToSpareScript.had_to_give(found[0]) == 560.0, "with the room the box had along that direction")
