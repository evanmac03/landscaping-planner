extends Node
## Tests for an OpenStreetMap extract arriving on the drawing: the entities the controller makes of
## it, the layer they land on, and the fact that the whole import is one undo step.
##
## The controller is built with its parts but no scene tree, as the DXF-import tests are, and the map
## is read by the real reader, so what is under test is the join between the two rather than either on
## its own.

const Ctrl := preload("res://scripts/draft/draft_controller.gd")
const Tool := preload("res://scripts/draft/draft_tool.gd")
const Document := preload("res://scripts/draft/draft_document.gd")
const SnapScript := preload("res://scripts/draft/snap_engine.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const OsmFile := preload("res://scripts/draft/osm_file.gd")

const CENTRE := {"latitude": 43.7, "longitude": -79.4}


func _controller():
	var controller = Ctrl.new()
	controller.document = Document.new()
	controller.snap = SnapScript.new()
	controller.tool = Tool.new()
	return controller


## A map with a house, a street, a tree and a named cafe - one of each kind of thing this draws.
func _map() -> Dictionary:
	var source := JSON.stringify({"elements": [
		{
			"type": "way", "id": 1, "tags": {"building": "house"},
			"geometry": [
				{"lat": 43.70020, "lon": -79.39970}, {"lat": 43.70020, "lon": -79.39940},
				{"lat": 43.70000, "lon": -79.39940}, {"lat": 43.70000, "lon": -79.39970},
				{"lat": 43.70020, "lon": -79.39970},
			],
		},
		{
			"type": "way", "id": 2, "tags": {"highway": "residential"},
			"geometry": [
				{"lat": 43.69980, "lon": -79.40030}, {"lat": 43.70020, "lon": -79.39980},
			],
		},
		{"type": "node", "id": 3, "lat": 43.70010, "lon": -79.39990, "tags": {"natural": "tree"}},
		{
			"type": "node", "id": 4, "lat": 43.70005, "lon": -79.39995,
			"tags": {"amenity": "cafe", "name": "The Cafe"},
		},
	]})
	return OsmFile.read_text(source, {"centre": CENTRE, "radius": 120.0})


func _on_layer(controller, layer_name: StringName) -> Array:
	var out: Array = []
	for entity: DraftEntity in controller.document.entities():
		if entity.layer == layer_name:
			out.append(entity)
	return out


# --- what arrives ---------------------------------------------------------------------


func test_a_map_lands_as_geometry_on_the_layer_that_does_not_plot() -> void:
	var controller = _controller()
	var taken: Dictionary = controller.import_osm(_map())
	assert(bool(taken["ok"]), String(taken["reason"]))
	assert(int(taken["added"]) == 4, str(taken))
	assert(controller.document.count() == 4)
	assert(controller.last_message.begins_with("placed 4 features from the underlay"), controller.last_message)
	# On the underlay, which is the whole point: map context is something to draw over, and a
	# neighbour's house must not reach the client's sheet.
	assert(_on_layer(controller, LayerSet.UNDERLAY).size() == 4)
	assert(not LayerSet.default_set().plotting_names().has(LayerSet.UNDERLAY), "and that layer does not plot")
	controller.free()


func test_a_house_becomes_a_closed_outline_and_a_street_a_line() -> void:
	var controller = _controller()
	assert(bool(controller.import_osm(_map())["ok"]))
	var closed := 0
	var open := 0
	for entity: DraftEntity in controller.document.entities():
		if entity.kind == Entity.Kind.POLYGON:
			closed += 1
		elif entity.kind == Entity.Kind.POLYLINE:
			open += 1
	assert(closed == 1, "the house")
	assert(open == 1, "the street")
	controller.free()


func test_a_tree_arrives_as_a_disc_on_the_plan() -> void:
	var controller = _controller()
	assert(bool(controller.import_osm(_map())["ok"]))
	var circles := 0
	for entity: DraftEntity in controller.document.entities():
		if entity.kind == Entity.Kind.CIRCLE:
			circles += 1
	assert(circles == 1, "one tree")
	controller.free()


func test_a_named_place_is_written_on_the_drawing() -> void:
	var controller = _controller()
	assert(bool(controller.import_osm(_map())["ok"]))
	var labels: Array[String] = []
	for entity: DraftEntity in controller.document.entities():
		if entity.kind == Entity.Kind.TEXT:
			labels.append(String(entity.meta.get("text", "")))
	assert(labels == ["The Cafe"], str(labels))
	controller.free()


func test_the_geometry_keeps_the_drawings_own_handedness() -> void:
	var controller = _controller()
	assert(bool(controller.import_osm(_map())["ok"]))
	# The house stands east of the site and on the north side of it, and the drawing's own convention is
	# east +X and north -Y - the same one the survey reader keeps. (The street crosses the centre, so it
	# is the house that proves the sign.) Its south edge lies on the site's own parallel, so it reaches
	# the origin rather than passing it: never south of the origin, and part of it strictly above it.
	var houses := 0
	var above := 0
	for entity: DraftEntity in controller.document.entities():
		if entity.kind != Entity.Kind.POLYGON:
			continue
		houses += 1
		for point: Vector2 in entity.outline():
			assert(point.x > 0.0, "east of the site: %s" % str(point))
			assert(point.y <= 0.0, "and never south of it: %s" % str(point))
			if point.y < 0.0:
				above += 1
	assert(houses == 1, "the one house")
	assert(above > 0, "and north is up the page, so a corner above the origin")
	controller.free()


func test_keeping_the_map_puts_it_on_the_existing_conditions_layers() -> void:
	var controller = _controller()
	var kept := OsmFile.read_text(
		JSON.stringify({"elements": [
			{
				"type": "way", "id": 1, "tags": {"building": "house"},
				"geometry": [
					{"lat": 43.7002, "lon": -79.3997}, {"lat": 43.7002, "lon": -79.3994},
					{"lat": 43.7, "lon": -79.3994}, {"lat": 43.7002, "lon": -79.3997},
				],
			},
		]}),
		{"centre": CENTRE, "radius": 120.0, "underlay": false}
	)
	assert(bool(controller.import_osm(kept)["ok"]))
	assert(_on_layer(controller, LayerSet.EXISTING_STRUCTURE).size() == 1, "a house is existing structure")
	assert(controller.last_message.contains("existing conditions layers"), controller.last_message)
	controller.free()


# --- the rules around it ---------------------------------------------------------------


func test_an_import_is_one_undo_step_however_many_features_it_holds() -> void:
	var controller = _controller()
	assert(bool(controller.import_osm(_map())["ok"]))
	assert(controller.document.count() == 4)
	assert(controller.dirty, "an import leaves the drawing unsaved")
	assert(controller.document.undo_last(), "one undo puts the drawing back")
	assert(controller.document.count() == 0, "all of it, not one feature")
	controller.free()


func test_a_map_with_nothing_it_can_draw_is_refused_in_words() -> void:
	var controller = _controller()
	var nothing := OsmFile.read_text(
		JSON.stringify({"elements": [{"type": "node", "id": 1, "lat": 43.7, "lon": -79.4}]}),
		{"centre": CENTRE}
	)
	var taken: Dictionary = controller.import_osm(nothing)
	assert(not bool(taken["ok"]))
	assert(controller.last_message.contains("nothing in it"), controller.last_message)
	assert(controller.document.count() == 0, "and nothing was placed")
	controller.free()


func test_a_map_that_could_not_be_read_is_refused_in_its_own_words() -> void:
	var controller = _controller()
	var taken: Dictionary = controller.import_osm(OsmFile.refused("the map is empty"))
	assert(not bool(taken["ok"]))
	assert(controller.last_message == "the map is empty", controller.last_message)
	controller.free()


func test_a_drawing_that_is_not_there_cannot_take_an_import() -> void:
	var controller = Ctrl.new()
	var taken: Dictionary = controller.import_osm(_map())
	assert(not bool(taken["ok"]))
	assert(controller.last_message == "there is no drawing to import it into", controller.last_message)
	controller.free()