extends Node
## The claim three readers exist to make, as a test: **there is one shape table**, a fourth format
## would fill it too, and there is exactly one place a shape becomes a drawing entity.
##
## The DXF reader fills it from a stream of code-and-value pairs, the OpenStreetMap reader from a JSON
## tree, and the LandXML reader from an XML tree. Their coordinate conventions are all different - a
## DXF is drawn north-up in the file's own units, an OSM way is degrees on a sphere, a LandXML point is
## northing first in words - and their units are each a fact about their own format. What they agree on
## is this table, and what this file pins down is that they really do: the same keys, the same
## invariants, one builder, and geometry that is in metres by the time a shape exists.

const Dxf := preload("res://scripts/draft/dxf_file.gd")
const Osm := preload("res://scripts/draft/osm_file.gd")
const LandXml := preload("res://scripts/draft/landxml_file.gd")
const ControllerScript := preload("res://scripts/draft/draft_controller.gd")
const DocumentScript := preload("res://scripts/draft/draft_document.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")

## The keys a shape has whichever reader made it: the ones `_entity_from_shape` reads. A reader may
## add words of its own beside them - and both the OSM reader and the LandXML reader do, naming the
## feature a shape came from, as the DXF reader names the layer the file had - but these are what makes
## a shape a shape.
const SHARED: Array[String] = [
	"kind", "layer", "points", "bulges", "closed", "words", "height", "arc",
]

## The kinds a shape may be: what the builder knows how to draw. A reader that invents a kind has
## invented a shape nothing draws.
const KINDS: Array[String] = ["LINE", "LWPOLYLINE", "POLYLINE", "CIRCLE", "ARC", "TEXT"]


## A DXF holding a ten-foot line and a circle, in feet.
func _dxf() -> Dictionary:
	return Dxf.read_text("\n".join(PackedStringArray([
		"0", "SECTION", "2", "HEADER", "9", "$INSUNITS", "70", "2", "0", "ENDSEC",
		"0", "SECTION", "2", "ENTITIES",
		"0", "LINE", "8", "PROPERTY", "10", "0.0", "20", "0.0", "11", "10.0", "21", "0.0",
		"0", "CIRCLE", "8", "PROPERTY", "10", "5.0", "20", "5.0", "40", "2.0",
		"0", "ENDSEC", "0", "EOF", "",
	])))


## An Overpass response holding a building and a tree, a hundredth of a degree east of the centre.
func _osm() -> Dictionary:
	return Osm.read_text(
		"{\"generator\": \"test\", \"elements\": ["
		+ "{\"type\": \"node\", \"id\": 1, \"lat\": 43.0, \"lon\": -79.0,"
		+ " \"tags\": {\"natural\": \"tree\", \"name\": \"A maple\"}},"
		+ "{\"type\": \"way\", \"id\": 2, \"geometry\": ["
		+ "{\"lat\": 43.0, \"lon\": -79.0}, {\"lat\": 43.0, \"lon\": -78.9999},"
		+ "{\"lat\": 43.0001, \"lon\": -78.9999}],"
		+ " \"tags\": {\"building\": \"house\"}}]}",
		{"centre": {"latitude": 43.0, "longitude": -79.0}}
	)


## A LandXML plat holding a parcel with a curved side, in US survey feet.
func _landxml() -> Dictionary:
	return LandXml.read_text("\n".join(PackedStringArray([
		"<LandXML xmlns=\"http://www.landxml.org/schema/LandXML-1.2\" version=\"1.2\">",
		"  <Units><Imperial linearUnit=\"USSurveyFoot\"/></Units>",
		"  <Parcels><Parcel name=\"LOT 12\"><CoordGeom>",
		"    <Line><Start>1000.0 3000.0</Start><End>1000.0 3010.0</End></Line>",
		"    <Curve rot=\"ccw\"><Start>1000.0 3010.0</Start><Center>1010.0 3010.0</Center>"
		+ "<End>1010.0 3000.0</End></Curve>",
		"    <Line><Start>1010.0 3000.0</Start><End>1000.0 3000.0</End></Line>",
		"  </CoordGeom></Parcel></Parcels>",
		"</LandXML>",
		"",
	])))


## One shape from each reader, each with the name of the reader that made it, so a failure says which
## one broke the table rather than only that something did.
func _one_from_each() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for pair: Array in [
		["the DXF reader", _dxf()], ["the OSM reader", _osm()], ["the LandXML reader", _landxml()],
	]:
		var plan: Dictionary = pair[1]
		assert(bool(plan["ok"]), "%s refused its own sample: %s" % [String(pair[0]), String(plan["reason"])])
		var shapes: Array = plan["shapes"]
		assert(not shapes.is_empty(), "%s drew nothing" % String(pair[0]))
		found.append({"reader": String(pair[0]), "shape": shapes[0]})
	return found


func _hud_less_controller():
	var controller = ControllerScript.new()
	controller.document = DocumentScript.new()
	return controller


# --- one table --------------------------------------------------------------------------


func test_every_reader_fills_the_same_keys_with_the_same_kinds_of_value() -> void:
	for entry: Dictionary in _one_from_each():
		var shape: Dictionary = entry["shape"]
		var reader := String(entry["reader"])
		for key: String in SHARED:
			assert(shape.has(key), "%s does not fill %s" % [reader, key])
		assert(KINDS.has(String(shape["kind"])), "%s made a %s" % [reader, String(shape["kind"])])
		assert(shape["points"] is PackedVector2Array, "%s's points are a vector array" % reader)
		assert(shape["bulges"] is PackedFloat64Array, "%s's bulges are a float array" % reader)
		assert(shape["layer"] is StringName and not String(shape["layer"]).is_empty(),
			"%s decides the layer itself" % reader)
		assert(shape["closed"] is bool, "%s says whether a line closes" % reader)


func test_the_bulge_list_is_one_per_point_which_is_what_the_builder_relies_on() -> void:
	# `_entity_from_shape` applies bulges only when the two arrays line up, so a reader that filled one
	# per *segment* rather than one per point would silently draw a shape with no curves at all. The
	# invariant is a polyline's: a line, a circle, an arc and a text are not strings of segments, and
	# the DXF reader gives them an empty bulge list, which is exactly what the builder expects of them.
	var lines := 0
	for entry: Dictionary in _one_from_each():
		var shape: Dictionary = entry["shape"]
		if not (String(shape["kind"]) == "LWPOLYLINE" or String(shape["kind"]) == "POLYLINE"):
			lines += 1
			continue
		var points: PackedVector2Array = shape["points"]
		var bulges: PackedFloat64Array = shape["bulges"]
		assert(bulges.size() == points.size(),
			"%s: %d points and %d bulges" % [String(entry["reader"]), points.size(), bulges.size()])
	assert(lines == 2, "the DXF line and the map's tree ring are not strings of segments, so the rule is "
		+ "tested exactly where it applies: %d were" % lines)


func test_a_reader_may_add_words_of_its_own_and_none_of_them_is_required() -> void:
	var dxf: Dictionary = (_dxf()["shapes"] as Array)[0]
	var osm: Dictionary = (_osm()["shapes"] as Array)[0]
	var landxml: Dictionary = (_landxml()["shapes"] as Array)[0]
	assert(dxf.has("dxf_layer"), "the DXF reader names the layer the file had")
	assert(osm.has("feature"), "the OSM reader names the feature a way was")
	assert(landxml.has("feature"), "and so does this one")
	for extra: Dictionary in [dxf, osm, landxml]:
		for key: String in extra.keys():
			assert(SHARED.has(String(key)) or ["dxf_layer", "feature", "name"].has(String(key)),
				"a shape carries nothing beyond the table and its reader's own words: %s" % String(key))


# --- one builder ------------------------------------------------------------------------


func test_one_builder_draws_a_shape_from_any_of_the_three_readers() -> void:
	var controller = _hud_less_controller()
	for entry: Dictionary in _one_from_each():
		var shape: Dictionary = entry["shape"]
		var entity = controller._entity_from_shape(shape)
		assert(entity != null, "%s's shape became no entity at all" % String(entry["reader"]))
		assert(entity.layer == String(shape["layer"]) or entity.layer == &"",
			"the entity arrives on the layer the shape named")
	controller.free()


func test_a_curve_put_into_the_table_by_a_plat_survives_into_the_drawing() -> void:
	var controller = _hud_less_controller()
	var parcel: Dictionary = (_landxml()["shapes"] as Array)[0]
	var entity = controller._entity_from_shape(parcel)
	assert(entity != null)
	assert(entity.point_count() == 3, "the three corners the file stated: %d" % entity.point_count())
	var bulges: PackedFloat64Array = entity.bulges
	assert(bulges.size() == 3, "one per point")
	assert(absf(bulges[1] + tan(PI / 8.0)) < 1.0e-5,
		"the quarter turn survived the trip: %.6f" % bulges[1])
	# And the outline is a curve rather than a corner: sampled, its midpoint is off the chord.
	var outline: PackedVector2Array = entity.outline(0.05)
	assert(outline.size() > 4, "a curve is sampled, not a straight line: %d points" % outline.size())
	controller.free()


func test_a_circle_of_no_radius_is_refused_by_the_one_builder_whichever_reader_made_it() -> void:
	# The builder's refusals are the reason there is one of it: a reader cannot be a new chance to
	# forget them. This is the shape a tree with a radius of nothing would be.
	var controller = _hud_less_controller()
	var degenerate := {
		"kind": "CIRCLE", "layer": LayerSet.UNDERLAY,
		"points": PackedVector2Array([Vector2.ZERO, Vector2(0.0, 0.0)]),
		"bulges": PackedFloat64Array([0.0, 0.0]), "closed": false,
		"words": "", "height": 0.0, "arc": Vector2.ZERO,
	}
	assert(controller._entity_from_shape(degenerate) == null, "a circle of no radius is nothing")
	controller.free()


# --- one unit: metres -------------------------------------------------------------------


func test_whatever_the_file_was_in_the_table_is_in_metres() -> void:
	# Ten international feet in a DXF and ten US survey feet in a plat, side by side. The two lengths
	# differ by two parts per million - which is immaterial for a planting layout and material for a
	# legal boundary - and both are metres, not the units the files were written in.
	var from_dxf: Dictionary = (_dxf()["shapes"] as Array)[0]
	var dxf_points: PackedVector2Array = from_dxf["points"]
	assert(absf(dxf_points[0].distance_to(dxf_points[1]) - 3.048) < 1.0e-3,
		"ten feet is 3.048 m: %.6f" % dxf_points[0].distance_to(dxf_points[1]))
	var from_plat: Dictionary = (_landxml()["shapes"] as Array)[0]
	var plat_points: PackedVector2Array = from_plat["points"]
	assert(absf(plat_points[0].distance_to(plat_points[1]) - 10.0 * 1200.0 / 3937.0) < 1.0e-3,
		"ten survey feet is 3.048006 m: %.6f" % plat_points[0].distance_to(plat_points[1]))
	# And the OSM reader's degrees became metres too: a tree is a ring of the model's own radius.
	var tree := {}
	for shape: Dictionary in (_osm()["shapes"] as Array):
		if String(shape["kind"]) == "CIRCLE":
			tree = shape
	assert(not tree.is_empty(), "the tree came in as a circle")
	var ring: PackedVector2Array = tree["points"]
	assert(absf(ring[1].x - Osm.TREE_RING_M) < 1.0e-6,
		"a from-nothing-a-tree-is becomes a 1.5 m ring in metres, not in degrees: %.6f" % ring[1].x)


# --- one gesture per import -------------------------------------------------------------


func test_each_reader_puts_its_whole_file_on_the_drawing_in_one_undo_step() -> void:
	var controller = _hud_less_controller()
	var document = controller.document
	var dxf: Dictionary = _dxf()
	var osm: Dictionary = _osm()
	var landxml: Dictionary = _landxml()
	assert(bool(controller.import_dxf(dxf).get("ok", false)), controller.last_message)
	assert(document.count() == 2, "a line and a circle: %d" % document.count())
	assert(document.gestures.depth() == 1, "one undo step for the whole file")
	assert(bool(controller.import_osm(osm).get("ok", false)), controller.last_message)
	assert(document.count() == 4, "two features came in: %d" % document.count())
	assert(document.gestures.depth() == 2, "and one step for those two as well")
	assert(bool(controller.import_landxml(landxml).get("ok", false)), controller.last_message)
	assert(document.count() == 5, "the parcel is the fifth shape: %d" % document.count())
	assert(document.gestures.depth() == 3)
	# Undoing once takes the whole plat off again and leaves the other two imports alone - which is the
	# promise every one of them makes to somebody who read the wrong file.
	assert(document.undo_last())
	assert(document.count() == 4, "the plat is gone: %d" % document.count())
	assert(document.undo_last())
	assert(document.count() == 2, "and the map with it: %d" % document.count())
	# A reader that read nothing refuses rather than opening a gesture: an undo step that changes
	# nothing is a step a person walks into and finds no change at the end of.
	assert(not bool(controller.import_landxml(LandXml.refused("none"))["ok"]))
	assert(document.gestures.depth() == 1, "and no empty step was left behind: %d" % document.gestures.depth())
	controller.free()