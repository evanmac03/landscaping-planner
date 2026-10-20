extends Node
## Tests for window and crossing selection: which shapes a rubber band catches,
## and why the two modes are not the same question.

const Select := preload("res://scripts/draft/draft_select.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")

## The band every test sweeps, 10 m square from the origin.
const BAND_A := Vector2(0.0, 0.0)
const BAND_B := Vector2(10.0, 10.0)


func _line(x0: float, y0: float, x1: float, y1: float):
	return Entity.make_line(Vector2(x0, y0), Vector2(x1, y1))


func _caught(entity, mode: StringName) -> bool:
	return Select.catches(entity, Select.band(BAND_A, BAND_B), mode)


# --- window: only what is wholly inside ----------------------------------------------


func test_a_window_catches_a_shape_wholly_inside_it() -> void:
	assert(_caught(_line(2.0, 2.0, 8.0, 8.0), Select.MODE_WINDOW), "a line inside the band")


func test_a_window_misses_a_shape_that_pokes_out() -> void:
	assert(not _caught(_line(2.0, 2.0, 12.0, 8.0), Select.MODE_WINDOW),
		"one end outside the band is outside the band")


func test_a_window_misses_a_shape_wholly_outside_it() -> void:
	assert(not _caught(_line(20.0, 20.0, 30.0, 30.0), Select.MODE_WINDOW))


func test_a_shape_on_the_bands_own_edge_is_inside_it() -> void:
	assert(_caught(_line(0.0, 0.0, 10.0, 10.0), Select.MODE_WINDOW),
		"a shape that stops exactly on the edge has not left the band")


# --- crossing: anything the band touches ---------------------------------------------


func test_a_crossing_catches_a_shape_that_pokes_out() -> void:
	assert(_caught(_line(2.0, 2.0, 12.0, 8.0), Select.MODE_CROSSING),
		"the band has met this line, so it is caught")


func test_a_crossing_catches_a_shape_wholly_inside_it() -> void:
	assert(_caught(_line(2.0, 2.0, 8.0, 8.0), Select.MODE_CROSSING),
		"anything inside the band has certainly met it")


func test_a_crossing_misses_a_shape_wholly_outside_it() -> void:
	assert(not _caught(_line(20.0, 20.0, 30.0, 30.0), Select.MODE_CROSSING))


func test_a_crossing_catches_a_shape_that_only_crosses_an_edge() -> void:
	# A long line straight through the band: neither end is inside it.
	assert(not _caught(_line(-40.0, 5.0, 40.0, 5.0), Select.MODE_WINDOW),
		"a window does not catch it")
	assert(_caught(_line(-40.0, 5.0, 40.0, 5.0), Select.MODE_CROSSING),
		"but the band is across it, which is exactly what a crossing sweep is for")


func test_a_shape_that_encloses_the_band_is_caught_by_neither() -> void:
	# A ring of radius 50 around the band's middle: the band never meets the ring.
	var big = Entity.make_circle(Vector2(5.0, 5.0), 50.0)
	assert(not _caught(big, Select.MODE_WINDOW), "it is not inside the band")
	assert(not _caught(big, Select.MODE_CROSSING),
		"and the band has not met it: a sweep over the middle of a circle must not take the circle")


# --- curves are sampled, not guessed -------------------------------------------------


func test_a_curve_is_judged_on_its_own_linework() -> void:
	var circle = Entity.make_circle(Vector2(4.5, 4.5), 3.0)
	assert(_caught(circle, Select.MODE_WINDOW), "a circle of radius 3 at 4.5,4.5 is inside a 10 m band")
	var edge = Entity.make_circle(Vector2(9.0, 9.0), 4.0)
	assert(not _caught(edge, Select.MODE_WINDOW), "one that runs over the edge is not")
	assert(_caught(edge, Select.MODE_CROSSING), "but a crossing catches it")


func test_an_arc_is_caught_where_its_sweep_is() -> void:
	# A quarter arc of radius 20 centred at the origin sweeps from (20,0) to (0,20):
	# nowhere near the band, so neither mode takes it.
	var far = Entity.make_arc(Vector2(0.0, 0.0), 20.0, 0.0, PI * 0.5)
	assert(not _caught(far, Select.MODE_CROSSING), "the sweep never comes near the band")


# --- what a band hands back -----------------------------------------------------------


func test_a_band_hands_back_the_ids_it_caught_in_document_order() -> void:
	var inside = _line(2.0, 2.0, 8.0, 8.0)
	inside.id = 7
	var outside = _line(20.0, 20.0, 30.0, 30.0)
	outside.id = 9
	var also_inside = _line(3.0, 3.0, 4.0, 4.0)
	also_inside.id = 11
	var caught := Select.pick([inside, outside, also_inside], Select.band(BAND_A, BAND_B), Select.MODE_WINDOW)
	assert(bool(caught["ok"]))
	assert(caught["ids"] == [7, 11], "in the order they were handed over: %s" % str(caught["ids"]))
	assert(StringName(caught["mode"]) == Select.MODE_WINDOW)


func test_the_corners_may_be_picked_either_way_round() -> void:
	var inside = _line(2.0, 2.0, 8.0, 8.0)
	inside.id = 1
	var forwards := Select.pick_between([inside], BAND_A, BAND_B, Select.MODE_WINDOW)
	var backwards := Select.pick_between([inside], BAND_B, BAND_A, Select.MODE_WINDOW)
	assert(forwards["ids"] == backwards["ids"], "a band dragged the other way is the same band")


func test_a_label_is_caught_by_where_it_stands() -> void:
	# A text entity has a place but no linework: without a fallback it could never be
	# selected by anything.
	var label := Entity.make_text(Vector2(5.0, 5.0), "Acer rubrum (3)")
	label.id = 3
	var caught := Select.pick_between([label], BAND_A, BAND_B, Select.MODE_WINDOW)
	assert(caught["ids"] == [3], "a label inside the band is caught")
	var away := Entity.make_text(Vector2(50.0, 50.0), "far away")
	away.id = 4
	assert(Select.pick_between([away], BAND_A, BAND_B, Select.MODE_WINDOW)["ids"].is_empty())


func test_a_band_with_no_area_is_refused_rather_than_swept() -> void:
	var caught := Select.pick_between([], Vector2(4.0, 4.0), Vector2(4.0, 4.0), Select.MODE_WINDOW)
	assert(not bool(caught["ok"]), "a double click is not a window")
	assert(String(caught["reason"]) == "a selection band with no area")
	var flat := Select.pick_between([], Vector2(0.0, 4.0), Vector2(10.0, 4.0), Select.MODE_CROSSING)
	assert(not bool(flat["ok"]), "and a band of no height is no band either")


# --- the words ------------------------------------------------------------------------


func test_the_modes_are_two_and_they_are_named() -> void:
	assert(Select.is_mode(Select.MODE_WINDOW))
	assert(Select.is_mode(Select.MODE_CROSSING))
	assert(not Select.is_mode(&"lasso"), "there is no third mode yet, and it does not exist by accident")
	assert(Select.mode_name(Select.MODE_WINDOW) == "Window")
	assert(Select.mode_name(Select.MODE_CROSSING) == "Crossing")


func test_a_selection_reads_as_one_line() -> void:
	assert(Select.describe(1, Select.MODE_CROSSING) == "1 shape selected (crossing)")
	assert(Select.describe(3, Select.MODE_WINDOW) == "3 shapes selected (window)")