extends Node
## The asking half of the OpenStreetMap import: the query it builds, the refusals it makes, and the
## fact that a reader that is not in a scene says so rather than reaching for a network it does not
## have.
##
## The request itself is deliberately not made here. A test that needs the internet is a test that
## fails on a train, and the honest thing to test is everything up to the socket.

const OsmFetch := preload("res://scripts/draft/osm_fetch.gd")
const OsmFile := preload("res://scripts/draft/osm_file.gd")

const CENTRE := {"latitude": 43.7, "longitude": -79.4}
const TEMP := "user://osm-fetch-test.json"


func _free(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.free()


# --- what it asks for -----------------------------------------------------------------


func test_the_query_is_an_overpass_query_for_everything_this_draws() -> void:
	var query := OsmFetch.build_query(CENTRE, 120.0)
	assert(query.contains("[out:json]"), query)
	assert(query.contains("out geom;"), "without this there are no points to draw: %s" % query)
	for tag: String in ["building", "highway", "waterway", "natural", "barrier"]:
		assert(query.contains('way["%s"]' % tag), "it asks for %s: %s" % [tag, query])
	assert(query.contains('node["natural"="tree"]'), "a tree is a node, not a way: %s" % query)
	assert(query.contains('node["name"]'), "and a named place has no shape of its own: %s" % query)


func test_the_query_is_centred_on_the_site_and_asks_around_a_distance() -> void:
	var query := OsmFetch.build_query(CENTRE, 250.0)
	assert(query.contains("around:"), query)
	assert(query.contains("43.7"), "the site's latitude is in it: %s" % query)
	assert(query.contains("-79.4"), "and its longitude: %s" % query)
	assert(query.contains("250"), "and the distance: %s" % query)


func test_the_bound_of_a_radius_is_a_rectangle_around_the_centre() -> void:
	var box := OsmFetch.bounds_of(CENTRE, 100.0)
	assert(float(box["south"]) < 43.7 and float(box["north"]) > 43.7, str(box))
	assert(float(box["west"]) < -79.4 and float(box["east"]) > -79.4, str(box))
	# A metre is a smaller share of a degree of longitude than of latitude away from the equator, so
	# the box is wider than it is tall.
	assert(
		(float(box["east"]) - float(box["west"])) > (float(box["north"]) - float(box["south"])),
		str(box)
	)
	assert(absf(float(box["north"]) - 43.7 - 100.0 / OsmFile.metres_per_degree_latitude(43.7)) < 1.0e-9)


func test_what_would_be_asked_for_is_refused_when_it_is_not_a_place() -> void:
	assert(not bool(OsmFetch.can_fetch({}, 120.0)["ok"]), "no centre at all")
	assert(not bool(OsmFetch.can_fetch({"latitude": 91.0, "longitude": 0.0}, 120.0)["ok"]), "off the earth")
	assert(not bool(OsmFetch.can_fetch(CENTRE, 0.0)["ok"]), "a radius of nothing")
	assert(not bool(OsmFetch.can_fetch(CENTRE, NAN)["ok"]), "and a radius that is not a number")
	assert(not bool(OsmFetch.can_fetch(CENTRE, OsmFetch.MAX_RADIUS_M + 1.0)["ok"]), "more map than this draws")
	assert(bool(OsmFetch.can_fetch(CENTRE, OsmFetch.DEFAULT_RADIUS_M)["ok"]), "the default is a place and a distance")


func test_a_refusal_says_what_is_wrong_rather_than_only_that_something_is() -> void:
	assert(String(OsmFetch.can_fetch({}, 120.0)["reason"]).contains("centre"))
	assert(String(OsmFetch.can_fetch(CENTRE, 0.0)["reason"]).contains("distance"))
	assert(String(OsmFetch.can_fetch(CENTRE, 1.0e9)["reason"]).contains("%.0f m" % OsmFetch.MAX_RADIUS_M))


# --- the network it does not have -----------------------------------------------------


func test_a_reader_that_is_not_in_a_scene_cannot_reach_the_network_and_says_so() -> void:
	var reader: Node = OsmFetch.new()
	var reach: Dictionary = reader.can_reach_network()
	assert(not bool(reach["ok"]), "a HTTPRequest has to be in the scene to make a request")
	assert(String(reach["reason"]).contains("network"), String(reach["reason"]))
	_free(reader)


func test_the_endpoint_is_the_public_overpass_interpreter() -> void:
	assert(OsmFetch.ENDPOINT.begins_with("https://"), OsmFetch.ENDPOINT)
	assert(OsmFetch.ENDPOINT.contains("overpass"), OsmFetch.ENDPOINT)


# --- the offline half -----------------------------------------------------------------


func test_a_saved_map_is_read_at_the_centre_it_is_given() -> void:
	var file := FileAccess.open(TEMP, FileAccess.WRITE)
	file.store_string(JSON.stringify({"elements": [
		{
			"type": "node", "id": 1, "lat": 43.7001, "lon": -79.4001,
			"tags": {"natural": "tree"},
		},
	]}))
	file.close()
	var plan: Dictionary = OsmFetch.read_saved(TEMP, CENTRE, 120.0)
	assert(bool(plan["ok"]), String(plan["reason"]))
	assert((plan["shapes"] as Array).size() == 1, "the tree came in")
	assert(String(plan["source"]) == "osm-fetch-test.json", "and the file it came from is named")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP))


func test_a_saved_map_that_is_not_there_is_refused_rather_than_raising() -> void:
	var plan: Dictionary = OsmFetch.read_saved("user://no-such-saved-map.json", CENTRE, 120.0)
	assert(not bool(plan["ok"]))
	assert(String(plan["reason"]).contains("no file called"), String(plan["reason"]))