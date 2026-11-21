extends Node

## A target against what the device promised to leave alone: the four insets, the bands they are worded as, and
## the device that has promised nothing.

const SafeAreaScript := preload("res://scripts/safe_area.gd")

## What a phone held upright leaves for the program: the notch's band at the top and the navigation bar's at the
## foot, in screen pixels. The numbers are this instrument's own example, not a reading of any device.
const SAFE := Rect2i(0, 96, 1080, 2100)


func test_a_target_inside_the_promised_area_is_left_alone() -> void:
	assert(SafeAreaScript.inside(Rect2i(100, 200, 200, 80), SAFE), "nowhere near an edge")
	assert(SafeAreaScript.faults([{ "name": "Design the garden", "rect": Rect2i(100, 200, 200, 80), "safe": SAFE }]).is_empty())


func test_a_button_under_the_navigation_bar_is_named_by_how_far_it_reaches() -> void:
	var found := SafeAreaScript.faults([{ "name": "the foot button", "rect": Rect2i(40, 2170, 400, 60), "safe": SAFE }])
	assert(found.size() == 1, "the bar starts where the promise ends, and this reaches 34 px into it")
	assert((found[0]["insets"] as Vector4i).w == 34, "34 px past the foot")
	assert(
		SafeAreaScript.sentence(found[0])
		== "the foot button stands 34 px into the foot, which the device keeps for itself",
		SafeAreaScript.sentence(found[0]),
	)


func test_a_target_reaching_into_two_bands_names_both_of_them() -> void:
	var found := SafeAreaScript.faults([{ "name": "a wide button", "rect": Rect2i(-20, 80, 1140, 60), "safe": SAFE }])
	assert(found.size() == 1)
	var words: String = SafeAreaScript.words(found[0]["insets"] as Vector4i)
	assert(words.contains("20 px into the left band"), words)
	assert(words.contains("16 px into the top band"), words)
	assert(words.contains("40 px into the right band"), words)


func test_the_four_insets_are_left_top_right_and_foot_in_that_order() -> void:
	var reaches: Vector4i = SafeAreaScript.insets(Rect2i(8, 90, 60, 20), Rect2i(20, 100, 40, 40))
	assert(reaches.x == 12, "left")
	assert(reaches.y == 10, "top")
	assert(reaches.z == 8, "right")
	assert(reaches.w == 0, "and nothing past the foot")


func test_a_device_that_has_promised_nothing_names_nothing() -> void:
	assert(SafeAreaScript.faults([{ "name": "anything", "rect": Rect2i(-500, -500, 40, 40), "safe": Rect2i() }]).is_empty(), "every control in the program is outside a place that is not there")


func test_the_deepest_reach_is_the_one_named_first() -> void:
	var found := SafeAreaScript.faults(
		[
			{ "name": "a little over", "rect": Rect2i(40, 2160, 40, 40), "safe": SAFE },
			{ "name": "well under", "rect": Rect2i(40, 2190, 40, 40), "safe": SAFE },
		]
	)
	assert(found.size() == 2)
	assert(SafeAreaScript.worst(found)["name"] == "well under", "it reaches 54 px into the band")


func test_an_item_without_a_rectangle_or_a_promise_is_left_out() -> void:
	assert(SafeAreaScript.faults([{ "name": "no rectangle", "safe": SAFE }]).is_empty())
	assert(SafeAreaScript.faults([{ "name": "no promise", "rect": Rect2i(0, 0, 10, 10) }]).is_empty())


## Where a finger actually lands: the middle of what it was aimed at. This is the question the phone's own
## reading was really about - its three view buttons each reached 81 px into the top band, and their middles at
## y=68 are what put the press in the system's hands.
func test_a_large_button_whose_middle_is_clear_is_not_named() -> void:
	# It overlaps the top band by 16 px, and a thumb aiming at it lands 30 px below the band's edge.
	var big := Rect2i(400, 80, 300, 100)
	assert(not SafeAreaScript.inside(big, SAFE), "it does reach the band the device keeps")
	assert(not SafeAreaScript.covers_centre(big, SAFE), "but its middle at y=130 is well clear of it")
	assert(SafeAreaScript.centre_faults([{ "name": "a big button", "rect": big, "safe": SAFE }]).is_empty())


func test_a_button_whose_middle_is_in_the_top_band_is_named() -> void:
	# The phone's own case: a button at screen y 19..117, whose middle at y=68 is above the 96 the device starts
	# leaving alone at.
	var found := SafeAreaScript.centre_faults(
		[{ "name": "the board  \"Fit\"", "rect": Rect2i(649, 19, 57, 98), "safe": SAFE }]
	)
	assert(found.size() == 1, "a finger aiming at its middle aims into the band")
	assert(found[0]["centre"] == Vector2i(677, 68), "the middle it was aimed at: %s" % str(found[0]["centre"]))
	assert(
		SafeAreaScript.centre_sentence(found[0])
		== "the board  \"Fit\" takes a finger at its middle, (677, 68), which is inside the band the device keeps for itself",
		SafeAreaScript.centre_sentence(found[0]),
	)


func test_a_device_that_has_promised_nothing_names_nothing_by_the_middle_either() -> void:
	var item := { "name": "anything", "rect": Rect2i(0, 0, 40, 40), "safe": Rect2i() }
	assert(
		not SafeAreaScript.covers_centre(item["rect"], item["safe"]),
		"every middle is outside a place that is not there",
	)
	assert(SafeAreaScript.centre_faults([item]).is_empty())


func test_the_middle_deepest_in_a_band_is_the_one_named_first() -> void:
	var found := SafeAreaScript.centre_faults(
		[
			{ "name": "just over the edge", "rect": Rect2i(40, 40, 40, 40), "safe": SAFE },
			{ "name": "deep in it", "rect": Rect2i(40, 0, 40, 40), "safe": SAFE },
		]
	)
	assert(found.size() == 2)
	assert(SafeAreaScript.deepest_centre(found)["name"] == "deep in it", "its middle at y=20 is 76 px above the edge")
