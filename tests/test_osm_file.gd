extends Node
## The OpenStreetMap reader: the projection, the tag table, and what a small extract of a real place
## becomes in the model.
##
## The fixture is a house, a street, a tree, a cafe, a relation and an untagged node - one of each
## thing a real extract holds - laid out a few tens of metres from the centre, so the arithmetic can be
## checked against numbers a person can work out.

const OsmFile := preload("res://scripts/draft/osm_file.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")

## The site: a real latitude and longitude, so the degree lengths are the ones a real site gets.
const CENTRE := {"latitude": 43.7, "longitude": -79.4}


func _map(elements: Array = []) -> String:
	var listed: Array = elements
	if listed.is_empty():
		listed = [
			# A house: a closed way, with the first point repeated at the end as Overpass writes it.
			{
				"type": "way", "id": 1, "tags": {"building": "house"},
				"geometry": [
					{"lat": 43.70020, "lon": -79.39970},
					{"lat": 43.70020, "lon": -79.39940},
					{"lat": 43.70000, "lon": -79.39940},
					{"lat": 43.70000, "lon": -79.39970},
					{"lat": 43.70020, "lon": -79.39970},
				],
			},
			# A street: an open way through the site.
			{
				"type": "way", "id": 2, "tags": {"highway": "residential"},
				"geometry": [
					{"lat": 43.69980, "lon": -79.40030},
					{"lat": 43.70000, "lon": -79.40000},
					{"lat": 43.70020, "lon": -79.39980},
				],
			},
			{"type": "node", "id": 3, "lat": 43.70010, "lon": -79.39990, "tags": {"natural": "tree"}},
			{
				"type": "node", "id": 4, "lat": 43.70005, "lon": -79.39995,
				"tags": {"amenity": "cafe", "name": "The Cafe"},
			},
			{"type": "relation", "id": 5, "tags": {"type": "multipolygon", "building": "yes"}, "members": []},
			{"type": "node", "id": 6, "lat": 43.70003, "lon": -79.39993},
		]
	return JSON.stringify({"version": 0.6, "generator": "Overpass API 0.7.62", "elements": listed})


func _read(options: Dictionary = {}) -> Dictionary:
	var merged := {"centre": CENTRE}
	merged.merge(options, true)
	return OsmFile.read_text(_map(), merged)


func _of(plan: Dictionary, feature: String) -> Array:
	var out: Array = []
	for shape: Dictionary in (plan["shapes"] as Array):
		if String(shape["feature"]) == feature:
			out.append(shape)
	return out


# --- the projection -------------------------------------------------------------------


func test_a_degree_of_latitude_is_the_length_the_ellipsoid_says() -> void:
	# The meridian degree is shortest at the equator and longest at the pole, which is the whole reason
	# a site's own latitude is part of the projection.
	assert(absf(OsmFile.metres_per_degree_latitude(0.0) - 110574.0) < 20.0, "at the equator")
	assert(absf(OsmFile.metres_per_degree_latitude(90.0) - 111694.0) < 20.0, "at the pole")
	assert(absf(OsmFile.metres_per_degree_latitude(43.7) - 111132.0) < 60.0, "and in between")


func test_a_degree_of_longitude_is_nothing_at_all_at_the_pole() -> void:
	assert(absf(OsmFile.metres_per_degree_longitude(0.0) - 111320.0) < 1.0, "at the equator")
	assert(absf(OsmFile.metres_per_degree_longitude(43.7) - 80500.0) < 200.0, "at this site")
	assert(absf(OsmFile.metres_per_degree_longitude(90.0)) < 250.0, "and nothing at the pole")


func test_a_place_north_of_the_site_lands_at_a_negative_y() -> void:
	# Model space is east +X and north -Y, the same convention the survey reader and the DXF reader use.
	var north := OsmFile.to_model(43.701, -79.4, CENTRE)
	assert(is_zero_approx(north.x), "a hundredth of a degree due north is due north")
	assert(north.y < 0.0, "and north is up the page, so -Y: %f" % north.y)
	assert(absf(absf(north.y) - OsmFile.metres_per_degree_latitude(43.7) * 0.001) < 0.01, "by one thousandth of a degree")


func test_a_place_east_of_the_site_lands_at_a_positive_x() -> void:
	var east := OsmFile.to_model(43.7, -79.399, CENTRE)
	assert(east.x > 0.0, "east is +X: %f" % east.x)
	assert(is_zero_approx(east.y), "and the same latitude is the same line across the page")


func test_the_centre_itself_is_the_origin_of_the_drawing() -> void:
	var here := OsmFile.to_model(43.7, -79.4, CENTRE)
	assert(here == Vector2.ZERO, "the site is the origin: %s" % str(here))


func test_a_place_is_worded_the_way_a_person_writes_one() -> void:
	assert(OsmFile.place_words(CENTRE) == "43.7000°N 79.4000°W", OsmFile.place_words(CENTRE))
	assert(OsmFile.place_words({"latitude": -33.5, "longitude": 151.2}) == "33.5000°S 151.2000°E")


# --- what the tags mean ---------------------------------------------------------------


func test_a_house_a_street_a_path_a_river_and_a_pond_are_told_apart_by_their_tags() -> void:
	var building := OsmFile.feature_for({"building": "house"})
	assert(String(building["kind"]) == "building")
	assert(bool(building["area"]), "a house is a footprint")
	var street := OsmFile.feature_for({"highway": "residential"})
	assert(String(street["kind"]) == "road")
	assert(not bool(street["area"]), "a street is a line")
	assert(String(OsmFile.feature_for({"highway": "footway"})["kind"]) == "path")
	assert(String(OsmFile.feature_for({"highway": "steps"})["kind"]) == "path")
	var stream := OsmFile.feature_for({"waterway": "stream"})
	assert(String(stream["kind"]) == "water")
	assert(not bool(stream["area"]), "a stream is a line")
	var pond := OsmFile.feature_for({"natural": "water"})
	assert(String(pond["kind"]) == "water")
	assert(bool(pond["area"]), "a pond is a ring")


func test_a_tree_and_a_wood_are_planting_and_a_fence_is_hardscape() -> void:
	assert(String(OsmFile.feature_for({"natural": "tree"})["kind"]) == "tree")
	assert(String(OsmFile.feature_for({"natural": "wood"})["kind"]) == "wood")
	assert(bool(OsmFile.feature_for({"landuse": "forest"})["area"]), "a forest is a region")
	assert(String(OsmFile.feature_for({"barrier": "fence"})["kind"]) == "wall")
	assert(String(OsmFile.feature_for({"wall": "no"})["kind"]) == "wall")


func test_the_thing_an_element_is_wins_over_what_else_it_is_called() -> void:
	# A building with a name is a building, not a label: the order of the table is the decision.
	var named_house := OsmFile.feature_for({"building": "yes", "amenity": "school", "name": "P.S. 1"})
	assert(String(named_house["kind"]) == "building", String(named_house["kind"]))


func test_tags_nothing_here_draws_are_not_a_feature() -> void:
	assert(String(OsmFile.feature_for({"name": "Somewhere"})["kind"]).is_empty())
	assert(String(OsmFile.feature_for({"type": "multipolygon"})["kind"]).is_empty())


# --- reading a real extract -----------------------------------------------------------


func test_a_house_comes_in_as_a_closed_footprint() -> void:
	var plan := _read()
	assert(bool(plan["ok"]), String(plan["reason"]))
	var house: Array = _of(plan, "building")
	assert(house.size() == 1, "one house")
	var shape: Dictionary = house[0]
	assert(String(shape["kind"]) == "LWPOLYLINE")
	assert(bool(shape["closed"]), "a house is a ring")
	# Four corners, not five: Overpass repeats the first point and the repeat is where it closes.
	assert((shape["points"] as PackedVector2Array).size() == 4, "four corners: %d" % (shape["points"] as PackedVector2Array).size())


func test_a_street_comes_in_as_a_line_that_does_not_close() -> void:
	var plan := _read()
	var street: Array = _of(plan, "road")
	assert(street.size() == 1, "one street")
	assert(not bool((street[0] as Dictionary)["closed"]), "a street is not a ring")
	assert((street[0] as Dictionary)["points"].size() == 3)


func test_a_tree_becomes_a_ring_of_the_stated_size() -> void:
	var plan := _read()
	var trees: Array = _of(plan, "tree")
	assert(trees.size() == 1)
	var shape: Dictionary = trees[0]
	assert(String(shape["kind"]) == "CIRCLE", "a tree is drawn as a disc")
	assert(is_equal_approx(((shape["points"] as PackedVector2Array)[1]).x, OsmFile.TREE_RING_M))


func test_a_named_place_is_written_on_the_drawing() -> void:
	var plan := _read()
	var labels: Array = _of(plan, "amenity")
	assert(labels.size() == 1, "the cafe")
	assert(String((labels[0] as Dictionary)["kind"]) == "TEXT")
	assert(String((labels[0] as Dictionary)["words"]) == "The Cafe")


func test_a_relation_and_an_untagged_node_are_counted_rather_than_drawn() -> void:
	var plan := _read()
	assert((plan["shapes"] as Array).size() == 4, "four things out of six elements")
	var skipped: Dictionary = plan["skipped"]
	assert(int(skipped.get("a relation, which this does not follow", 0)) == 1, str(skipped))
	assert(int(skipped.get("an element with no tags, so nothing says what it is", 0)) == 1, str(skipped))
	assert(int(plan["elements"]) == 6)


func test_what_came_in_is_counted_by_what_it_is() -> void:
	var plan := _read()
	var counts: Dictionary = plan["counts"]
	assert(int(counts.get("building", 0)) == 1)
	assert(int(counts.get("road", 0)) == 1)
	assert(int(counts.get("tree", 0)) == 1)
	assert(int(counts.get("amenity", 0)) == 1)


func test_the_extract_lands_on_the_layer_that_does_not_plot() -> void:
	var plan := _read()
	assert(bool(plan["underlay"]), "the underlay is the default, as it is for a DXF")
	var layer_set := LayerSet.default_set()
	assert(not layer_set.plotting_names().has(LayerSet.UNDERLAY), "and that layer does not plot")
	for shape: Dictionary in (plan["shapes"] as Array):
		assert(StringName(shape["layer"]) == LayerSet.UNDERLAY, String(shape["layer"]))


func test_nothing_reaches_the_sheet_even_when_the_map_is_kept() -> void:
	# The kept mode is the same data read as existing conditions. The layers it names are the
	# existing-conditions band, which *does* plot - that is the difference between the two modes.
	var plan := _read({"underlay": false})
	assert(not bool(plan["underlay"]))
	var house: Dictionary = _of(plan, "building")[0]
	assert(StringName(house["layer"]) == LayerSet.EXISTING_STRUCTURE, String(house["layer"]))
	var street: Dictionary = _of(plan, "road")[0]
	assert(StringName(street["layer"]) == LayerSet.EXISTING_HARDSCAPE, String(street["layer"]))
	var tree: Dictionary = _of(plan, "tree")[0]
	assert(StringName(tree["layer"]) == LayerSet.EXISTING_PLANTING, String(tree["layer"]))


func test_a_map_read_from_a_saved_file_says_which_file_it_was() -> void:
	var plan := _read()
	plan["source"] = "site.json"
	assert(String(plan["source"]) == "site.json")


# --- the size of the ask --------------------------------------------------------------


func test_a_feature_reaching_past_the_area_that_was_asked_for_is_left_out() -> void:
	# The house and the street reach about thirty metres from the centre, so they are inside a
	# hundred-metre extract and outside a ten-metre one. Overpass answers with a whole way if any part
	# of it is in range, so without this a park boundary comes in whole.
	var small := _read({"radius": 10.0})
	assert(int(small["outlying"]) == 2, "the house and the street: %d" % int(small["outlying"]))
	assert((small["shapes"] as Array).size() == 2, "the tree and the cafe are inside it")
	var large := _read({"radius": 120.0})
	assert(int(large["outlying"]) == 0, "nothing reaches past a hundred and twenty metres")
	assert((large["shapes"] as Array).size() == 4, "and everything comes in")


func test_a_way_the_response_was_not_asked_to_geometrise_is_named_rather_than_drawn() -> void:
	# `out` without `geom` answers a way with node ids and no points. That is a different file, and the
	# reader says so rather than silently placing nothing.
	var plan := OsmFile.read_text(
		JSON.stringify({"elements": [
			{"type": "way", "id": 9, "tags": {"building": "yes"}, "nodes": [1, 2, 3]},
		]}),
		{"centre": CENTRE}
	)
	assert(bool(plan["ok"]), String(plan["reason"]))
	assert((plan["shapes"] as Array).is_empty())
	assert(int((plan["skipped"] as Dictionary).get("a way with no geometry: the response was not asked for `out geom`", 0)) == 1)


# --- what is refused ------------------------------------------------------------------


func test_an_empty_map_is_refused() -> void:
	var plan := OsmFile.read_text("", {"centre": CENTRE})
	assert(not bool(plan["ok"]))
	assert(String(plan["reason"]) == "the map is empty")


func test_that_which_is_not_json_is_refused_in_words() -> void:
	var plan := OsmFile.read_text("<osm><node/></osm>", {"centre": CENTRE})
	assert(not bool(plan["ok"]))
	assert(String(plan["reason"]).contains("not JSON"), String(plan["reason"]))


func test_json_that_is_not_a_map_is_refused_in_words() -> void:
	var plan := OsmFile.read_text('{"hello": "world"}', {"centre": CENTRE})
	assert(not bool(plan["ok"]))
	assert(String(plan["reason"]).contains("no elements array"), String(plan["reason"]))


func test_a_map_with_no_centre_is_refused_rather_than_placed_at_a_guess() -> void:
	# The projection has no meaning without a centre, and a default latitude would be a confident map
	# of somewhere else. It is the one question this reader will not answer for itself.
	var plan := OsmFile.read_text(_map(), {})
	assert(not bool(plan["ok"]))
	assert(String(plan["reason"]).contains("where the drawing's origin is"), String(plan["reason"]))


func test_a_file_that_is_not_there_is_refused_rather_than_raising() -> void:
	var plan := OsmFile.of_file("user://no-such-map.json", {"centre": CENTRE})
	assert(not bool(plan["ok"]))
	assert(String(plan["reason"]).contains("no file called"), String(plan["reason"]))


# --- saying what was read -------------------------------------------------------------


func test_the_report_reads_the_way_a_person_accepts_an_import() -> void:
	var plan := _read()
	var lines: Array[String] = OsmFile.report_lines(plan)
	var text := "\n".join(PackedStringArray(lines))
	assert(text.contains("4 features from OpenStreetMap around 43.7000°N 79.4000°W"), text)
	assert(text.contains("6 elements read"), text)
	assert(text.contains("what came in: amenity x1, building x1, road x1, tree x1"), text)
	assert(text.contains("not drawn:"), text)
	assert(text.contains("relation"), text)
	assert(text.contains("building -> 950-UNDERLAY"), text)


func test_a_refused_map_reads_as_its_reason() -> void:
	var lines: Array[String] = OsmFile.report_lines(OsmFile.refused("the map is empty"))
	assert(lines.size() == 1)
	assert(lines[0] == "the map is empty", lines[0])


func test_is_usable_is_about_having_something_to_draw() -> void:
	assert(OsmFile.is_usable(_read()))
	assert(not OsmFile.is_usable(OsmFile.refused("no")))
	assert(not OsmFile.is_usable(_read({"radius": 1.0})), "a map with nothing in it is not usable")