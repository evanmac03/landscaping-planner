## What the drawing puts around a place: the nearest few, named, with a distance and a direction - the arithmetic
## behind the page a person opens on site with the plan in hand.
##
## No scene and no node is needed for any of it except the reader, which is given a yard built in code and freed at
## the end: the model is static and pure, which is the whole reason it can be held this cheaply.
extends Node

const NearbyWorkScript := preload("res://scripts/plants/nearby_work.gd")
const NearbyWindowScript := preload("res://scripts/nearby_window.gd")
const PlantPlacementScript := preload("res://scripts/plants/plant_placement.gd")
const UnitsScript := preload("res://scripts/draft/units.gd")


## Three things east of the origin at 1, 2 and 3 metres, plus one north at 2 metres.
func _things() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({ "name": "holly", "at": Vector2(3.0, 0.0) })
	out.append({ "name": "boxwood", "at": Vector2(1.0, 0.0) })
	out.append({ "name": "olive", "at": Vector2(2.0, 0.0) })
	out.append({ "name": "cedar", "at": Vector2(0.0, -2.0) })
	return out


func test_the_nearest_few_come_out_nearest_first() -> void:
	var found: Dictionary = NearbyWorkScript.around(_things(), Vector2.ZERO)
	var rows: Array = found["rows"]
	assert(rows.size() == 4, "four things were placed, and a handful holds four: %d" % rows.size())
	assert(rows[0]["name"] == "boxwood", "the nearest is first: %s" % rows[0]["name"])
	assert(rows[1]["name"] == "cedar", "then the next: %s" % rows[1]["name"])
	assert(rows[2]["name"] == "olive", "and the two at two metres are level: %s" % rows[2]["name"])
	assert(rows[3]["name"] == "holly", "with the farthest last: %s" % rows[3]["name"])


func test_two_things_equally_far_come_out_in_the_same_order_every_time() -> void:
	# The tie is broken by name, so the list does not move between two runs on the same drawing - which is what a
	# person reads it against as they walk to the next spot.
	var found: Dictionary = NearbyWorkScript.around(_things(), Vector2.ZERO)
	var rows: Array = found["rows"]
	var level: Array[String] = []
	for row: Dictionary in rows:
		if is_equal_approx(float(row["metres"]), 2.0):
			level.append(String(row["name"]))
	assert(
		level.size() == 2 and level[0] == "cedar" and level[1] == "olive",
		"two at two metres read by name, 'cedar' before 'olive': %s" % str(level),
	)


func test_only_a_handful_is_listed_however_many_the_drawing_holds() -> void:
	var many: Array[Dictionary] = []
	for index in 8:
		many.append({ "name": "plant %d" % index, "at": Vector2(float(index) + 1.0, 0.0) })
	var found: Dictionary = NearbyWorkScript.around(many, Vector2.ZERO)
	assert(int(found["found"]) == 8, "the drawing holds eight: %d" % int(found["found"]))
	assert((found["rows"] as Array).size() == NearbyWorkScript.NEAREST, "and a handful is listed")
	assert(
		String(found["text"]).begins_with("8 planted things"),
		"the line says how many the drawing really holds: %s" % found["text"],
	)


func test_a_plant_with_no_species_is_counted_and_said_rather_than_dropped() -> void:
	var things: Array = _things()
	things.append({ "name": "", "at": Vector2(0.5, 0.0) })
	var found: Dictionary = NearbyWorkScript.around(things, Vector2.ZERO)
	assert((found["rows"] as Array).size() == 4, "an unnamed plant is not a row: %d" % (found["rows"] as Array).size())
	assert(int(found["unnamed"]) == 1, "but it is counted: %d" % int(found["unnamed"]))
	assert(
		String(found["text"]).contains("1 with no species recorded"),
		"and the page says so, in the audit's own words: %s" % found["text"],
	)


func test_a_drawing_with_nothing_planted_says_what_is_missing() -> void:
	var empty: Dictionary = NearbyWorkScript.around([], Vector2.ZERO)
	assert((empty["rows"] as Array).is_empty(), "nothing placed is nothing to list")
	assert(
		empty["text"] == NearbyWorkScript.NOTHING_PLANTED,
		"and the refusal names what is missing rather than showing a zero: %s" % empty["text"],
	)
	assert(
		(empty["nearest"] as Dictionary).is_empty(),
		"with no nearest thing to point at, which is an empty answer rather than a made-up one",
	)


func test_a_direction_reads_the_drawings_own_axis_east_right_and_north_up() -> void:
	# East is +X and north is -Y, which is `Survey.traverse`'s own convention: a survey's easting and northing
	# arrive in model space without a flip, and this page reads them the same way round.
	var here := Vector2(10.0, 10.0)
	assert(NearbyWorkScript.direction_words(here, here + Vector2(0.0, -1.0)) == "north", "up the plan is north")
	assert(NearbyWorkScript.direction_words(here, here + Vector2(1.0, 0.0)) == "east", "right is east")
	assert(NearbyWorkScript.direction_words(here, here + Vector2(0.0, 1.0)) == "south", "down is south")
	assert(NearbyWorkScript.direction_words(here, here + Vector2(-1.0, 0.0)) == "west", "left is west")
	assert(
		NearbyWorkScript.direction_words(here, here + Vector2(1.0, -1.0)) == "north-east",
		"and the diagonal between two of them reads as the point between two of them",
	)
	assert(NearbyWorkScript.direction_words(here, here) == "here", "a thing in the very spot says so")


func test_a_distance_is_worded_by_the_one_place_a_length_becomes_words() -> void:
	var found: Dictionary = NearbyWorkScript.around([{ "name": "olive", "at": Vector2(3.4, 0.0) }], Vector2.ZERO)
	var row: Dictionary = (found["rows"] as Array)[0]
	assert(
		String(row["words"]) == UnitsScript.length_words(3.4),
		"the page words no length of its own: %s" % row["words"],
	)
	assert(
		String(row["sentence"]) == "olive, %s to the east." % UnitsScript.length_words(3.4),
		"and the row is the sentence a person reads: %s" % row["sentence"],
	)


func test_the_reader_takes_the_plans_metres_straight_off_the_planted_nodes() -> void:
	# The plan's metres are the yard's own, so a prop at (2, 0, -3) in the yard stands at (2, -3) on the plan -
	# the same read `PlantSuitability.audit` makes, through the same two owners.
	var yard := Node3D.new()
	var plants: Node3D = PlantPlacementScript.plants_node(yard)
	var prop := Node3D.new()
	prop.position = Vector3(2.0, 0.0, -3.0)
	prop.add_to_group(&"placeable")
	plants.add_child(prop)
	var things: Array[Dictionary] = NearbyWorkScript.planted_things(null, yard)
	assert(things.size() == 1, "one prop was planted: %d" % things.size())
	assert(things[0]["at"] == Vector2(2.0, -3.0), "and it stands where the plan says: %s" % str(things[0]["at"]))
	assert(things[0]["name"] == "", "with no catalogue to name it, a plant is unnamed rather than invented")
	assert(NearbyWorkScript.planted_things(null, null).is_empty(), "and a scene with no yard has nothing to read")
	yard.free()

# --- the page -----------------------------------------------------------------------
#
# The page is built by hand and driven off-tree, with no drawing, no yard and no screen: it owns nothing, and the
# place and the things are handed to it, which is exactly why it can be held this cheaply.


func test_the_page_lists_the_nearest_few_as_the_sentences_a_person_reads() -> void:
	var page: Window = NearbyWindowScript.new()
	page.stand_at(Vector2.ZERO, _things())
	assert(page.row_count() == 4, "four things were placed, and all four are listed: %d" % page.row_count())
	assert(
		page.nearest_text() == "boxwood, %s to the east." % UnitsScript.length_words(1.0),
		"the nearest is the first row, as a sentence: %s" % page.nearest_text(),
	)
	assert(
		page.place_text().contains("boxwood"),
		"and the place names it as the landmark the person is standing beside: %s" % page.place_text(),
	)
	assert(page.summary_text().contains("4 planted things"), "with the count under the list: %s" % page.summary_text())
	assert(
		page.opening_words().begins_with("nearest first:"),
		"and the guidance says what the list is in the order of: %s" % page.opening_words(),
	)
	page.free()


func test_the_page_says_what_is_missing_rather_than_showing_nothing() -> void:
	var page: Window = NearbyWindowScript.new()
	page.stand_at(Vector2.ZERO, [])
	assert(page.row_count() == 0, "nothing is planted, so there is nothing to list")
	assert(
		page.summary_text() == NearbyWorkScript.NOTHING_PLANTED,
		"and the page says so rather than leaving a blank: %s" % page.summary_text(),
	)
	assert(
		page.opening_words() == NearbyWorkScript.NOTHING_PLANTED,
		"which is also what it says when it is opened: %s" % page.opening_words(),
	)
	page.free()


func test_a_page_with_no_place_yet_says_where_the_place_would_come_from() -> void:
	var page: Window = NearbyWindowScript.new()
	assert(page.place() == NearbyWindowScript.NOWHERE, "a page nobody has stood anywhere with has no place")
	assert(
		page.hint() == NearbyWindowScript.NO_DRAWING,
		"and it names what is missing rather than showing an empty list: %s" % page.hint(),
	)
	page.free()


func test_a_hand_resting_on_the_mouse_does_not_rewrite_the_rows() -> void:
	# The rows are written when the place moves a hand's width, so a person pointing at the plan and thinking does
	# not have the list flicker under their eyes.
	var page: Window = NearbyWindowScript.new()
	page.stand_at(Vector2(4.0, 4.0), _things())
	assert(page.show_around() == false, "the rows were just written, so asking again writes nothing")
	var written: Array[String] = page.row_texts()
	page.stand_at(Vector2(4.02, 4.0), _things())
	assert(page.show_around() == false, "and a hand's jitter is not a move worth re-reading for")
	assert(page.row_texts() == written, "so the list under the reader's eyes does not move")
	# A step to somewhere else is written as it arrives - `stand_at` is a statement of where the person is, not a
	# request to redraw - and asking straight after writes nothing, because it has already been written.
	page.stand_at(Vector2(5.0, 4.0), _things())
	assert(page.show_around() == false, "a step arrives written, so asking again writes nothing")
	assert(page.place() == Vector2(5.0, 4.0), "and the page stands where it was told")
	page.free()


func test_the_pages_rows_are_sentences_to_read_rather_than_controls_to_drive() -> void:
	var page: Window = NearbyWindowScript.new()
	page.stand_at(Vector2.ZERO, _things())
	assert(page.rows_are_keyboard_free(), "the rows take no keyboard of their own, like every control on a page")
	assert(page.row_texts().size() == page.row_count(), "and they read back as the sentences they are")
	page.free()
