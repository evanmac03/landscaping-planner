extends Node2D
## A live pass over the LandXML import: a surveyor's plat read into an underlay, the page that says
## what was read, and the one question a plat with no units has to be asked.
##
## This is a development tool, not part of the game. It instances the **real main scene** and drives
## the **real page** through the methods its controls call, so the reader, the HUD, the controller and
## the plan canvas are all the shipped ones, and it prints every step. The three claims it measures
## rather than asserts are the ones a third reader is *for*: the northing-first pair, the parcel that
## closes because a parcel is a ring, and the curve that arrives as a bulge.
##
## Run `res://scenes/landxml_demo.tscn`.

const MAIN := preload("res://scenes/main.tscn")
const LayerSet := preload("res://scripts/draft/layer_set.gd")

const PLAT_FILE := "user://landxml-plat-demo.xml"
const UNITS_FILE := "user://landxml-units-demo.xml"


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	var hud: Node = main.get_node_or_null(^"Hud")
	var controller: Node = main.get_node_or_null(^"DraftController")
	if hud == null or controller == null:
		print("no HUD or no drafting controller in the main scene")
		return

	print("--- a surveyor's plat, in US survey feet, with a curved lot line ---")
	_write(PLAT_FILE, _plat())
	print("written to ", ProjectSettings.globalize_path(PLAT_FILE))
	hud._on_landxml_chosen(PLAT_FILE)
	print("what the page says:")
	for line: String in hud.landxml_report_text().split("\n"):
		print("  ", line)
	print("the page will let it on the drawing: ", hud.landxml_import_enabled())
	print("and it is not asked about units, because the file says: ", hud.landxml_units_text())

	print("--- confirming it, as the button does ---")
	hud.confirm_landxml_import()
	print("status: ", controller.last_message)
	print("the drawing holds ", controller.document.count(), " shapes")
	for entity in controller.document.entities():
		print("  ", entity.layer, "  ", _kind_name(entity.kind), "  ", entity.point_count(), " points")
	# The pair is written northing first, and the model is east +X and north -Y, so a point at
	# "N 5250  E 3010" is 3010 m east and 5250 m *south* of the origin. Measured off the geometry
	# rather than off the drawing's box: a swap and a reflection look alike in a bounding box.
	var furthest_east := -1.0e12
	var furthest_south := -1.0e12
	for entity in controller.document.entities():
		if entity.layer != LayerSet.UNDERLAY:
			continue
		for point: Vector2 in entity.outline():
			furthest_east = maxf(furthest_east, point.x)
			furthest_south = maxf(furthest_south, point.y)
	var survey_foot := 1200.0 / 3937.0
	print("the furthest east vertex is at x = ", snappedf(furthest_east, 0.01),
		" m; the file's largest easting was 3060 survey feet = ",
		snappedf(3060.0 * survey_foot, 0.01), " m")
	print("the furthest south vertex is at y = ", snappedf(furthest_south, 0.01),
		" m, a northing of ", snappedf(-furthest_south / survey_foot, 0.1),
		" survey feet - the file's own lowest northing is 5250. Read as a plain (x, y) pair the plat",
		" would stand its northings on the southings and stand 1.6 km the wrong way up, and would",
		" still look like a lot")
	# And the curve: the lot's south-east side is a quarter turn, and it arrives as the bulge of the
	# polyline rather than as a fan of arcs.
	for entity in controller.document.entities():
		if entity.layer != LayerSet.UNDERLAY:
			continue
		var bulges: PackedFloat64Array = entity.bulges
		if bulges.size() == 0:
			continue
		var turned := 0
		for bulge: float in bulges:
			if not is_zero_approx(bulge):
				turned += 1
		print("  a shape with ", entity.point_count(), " points carries ", turned,
			" turning segment(s): bulges = ", bulges)
		print("  and its outline is sampled into ", entity.outline(0.05).size(),
			" points, because a bulge is a curve and not a corner")

	print("--- a plat that does not say what its units are ---")
	_write(UNITS_FILE, _plat(""))
	hud._on_landxml_chosen(UNITS_FILE)
	print("what the page says:")
	for line: String in hud.landxml_report_text().split("\n"):
		print("  ", line)
	print("the page will let it on the drawing: ", hud.landxml_import_enabled())
	print("--- answering the question, as the drop-down does ---")
	for answer: String in ["metres", "feet"]:
		hud.choose_landxml_units(answer)
		print("told it is ", answer, ": placeable = ", hud.landxml_import_enabled(),
			", the drop-down reads \"", hud.landxml_units_text(), "\"",
			", and the page says: ", hud.landxml_report_text().split("\n")[1])
	print("--- what is left on screen ---")
	print("the page is up: ", hud.is_landxml_panel_open(),
		", the drawing holds ", controller.document.count(), " shapes")


## A plat of one lot: three straight lines and a quarter-turn curve between two of them, with the
## corners named in a point database and the lines pointing at those names.
func _plat(units: String = "<Imperial linearUnit=\"USSurveyFoot\"/>") -> String:
	return "\n".join(PackedStringArray([
		"<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
		"<LandXML xmlns=\"http://www.landxml.org/schema/LandXML-1.2\" version=\"1.2\">",
		"  <Units>" + units + "</Units>",
		"  <CgPoints>",
		"    <CgPoint name=\"1\" code=\"BND\">5250.0 3000.0</CgPoint>",
		"    <CgPoint name=\"2\" code=\"BND\">5250.0 3060.0</CgPoint>",
		"    <CgPoint name=\"3\" code=\"BND\">5280.0 3060.0</CgPoint>",
		"  </CgPoints>",
		"  <Parcels>",
		"    <Parcel name=\"LOT 12\" area=\"2700.0\">",
		"      <CoordGeom>",
		"        <Line><Start pntRef=\"1\"/><End pntRef=\"2\"/></Line>",
		"        <Line><Start pntRef=\"2\"/><End pntRef=\"3\"/></Line>",
		"        <Curve rot=\"ccw\"><Start>5280.0 3060.0</Start><Center>5280.0 3050.0</Center>"
			+ "<End>5270.0 3050.0</End></Curve>",
		"        <Line><Start>5270.0 3050.0</Start><End>5250.0 3000.0</End></Line>",
		"      </CoordGeom>",
		"    </Parcel>",
		"  </Parcels>",
		"</LandXML>",
		"",
	]))


func _kind_name(kind: int) -> String:
	match kind:
		DraftEntity.Kind.LINE:
			return "line"
		DraftEntity.Kind.CIRCLE:
			return "circle"
		DraftEntity.Kind.ARC:
			return "arc"
		DraftEntity.Kind.POLYLINE:
			return "polyline"
		DraftEntity.Kind.POLYGON:
			return "polygon"
		DraftEntity.Kind.TEXT:
			return "text"
	return "kind %d" % kind


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		print("cannot write ", path)
		return
	file.store_string(text)
	file.close()