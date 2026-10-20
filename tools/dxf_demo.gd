extends Node2D
## A live pass over the DXF import: a surveyor's file read into an underlay, the page that says what
## was read, and the one question a unitless file has to be asked.
##
## This is a development tool, not part of the game. It instances the **real main scene** and drives the
## **real page** through the methods its controls call, so the reader, the HUD, the controller and the
## plan canvas are all the shipped ones, and it prints every step. The screenshot at the end is the page
## with a file that does not say its units in it, over a drawing that already carries the first one.
##
## Run `res://scenes/dxf_demo.tscn`.

const MAIN := preload("res://scenes/main.tscn")
const LayerSet := preload("res://scripts/draft/layer_set.gd")

const UNDERLAY_FILE := "user://dxf-underlay-demo.dxf"
const UNITS_FILE := "user://dxf-units-demo.dxf"


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	var hud: Node = main.get_node_or_null(^"Hud")
	var controller: Node = main.get_node_or_null(^"DraftController")
	if hud == null or controller == null:
		print("no HUD or no drafting controller in the main scene")
		return

	print("--- a surveyor's file, in feet, with three layers ---")
	_write(UNDERLAY_FILE, _survey_dxf())
	print("written to ", ProjectSettings.globalize_path(UNDERLAY_FILE))
	hud._on_dxf_chosen(UNDERLAY_FILE)
	print("what the page says:")
	for line: String in hud.dxf_report_text().split("\n"):
		print("  ", line)
	print("the page will let it on the drawing: ", hud.dxf_import_enabled())

	print("--- confirming it, as the button does ---")
	hud.confirm_dxf_import()
	print("status: ", controller.last_message)
	print("the drawing holds ", controller.document.count(), " shapes")
	print("and ", controller.document.plotting_entities().size(), " of them plot")
	for entity in controller.document.entities():
		print("  ", entity.layer, "  ", _kind_name(entity.kind))
	# The whole point of the mirror, read off the geometry itself rather than off the drawing's box: the
	# file's northernmost vertex is the arc's crown at 114 feet, and 114 feet is 34.75 m - so the model
	# must hold it 34.75 m *south* of the origin, and it does.
	var north := 0.0
	var south := 0.0
	var count := 0
	for entity in controller.document.entities():
		if entity.layer != LayerSet.UNDERLAY:
			continue
		for point: Vector2 in entity.outline():
			north = minf(north, point.y)
			south = maxf(south, point.y)
			count += 1
	print("the imported geometry spans y ", snappedf(north, 0.01), " to ", snappedf(south, 0.01),
		" over ", count, " points")
	print("the file's northernmost vertex was 114 ft = ",
		snappedf(114.0 * 0.3048, 0.01), " m, and it landed south of the origin: ",
		is_equal_approx(north, -114.0 * 0.3048))

	print("--- a file that does not say what its units are ---")
	_write(UNITS_FILE, _survey_dxf(0))
	hud._on_dxf_chosen(UNITS_FILE)
	print("what the page says:")
	for line: String in hud.dxf_report_text().split("\n"):
		print("  ", line)
	print("the page will let it on the drawing: ", hud.dxf_import_enabled())
	print("--- answering the question, as the drop-down does ---")
	for answer: String in ["metres", "feet"]:
		hud.choose_dxf_units(answer)
		print("told it is ", answer, ": placeable = ", hud.dxf_import_enabled(),
			", the drop-down reads \"", hud.dxf_units_text(), "\"",
			", and the page says: ", hud.dxf_report_text().split("\n")[1])
	print("--- what is left on screen ---")
	print("the page is up: ", hud.is_dxf_panel_open(),
		", the drawing holds ", controller.document.count(), " shapes")


## A surveyor's DXF: a closed property boundary, an easement across it, a building footprint, a tree
## and a label - on three layers, one of which this reader has never seen.
func _survey_dxf(insunits: int = 2) -> String:
	var lines: Array[String] = [
		"0", "SECTION", "2", "HEADER", "9", "$INSUNITS", "70", str(insunits), "0", "ENDSEC",
		"0", "SECTION", "2", "TABLES", "0", "TABLE", "2", "LAYER",
		"0", "LAYER", "2", "PROPERTY", "70", "0",
		"0", "LAYER", "2", "EASEMENT", "70", "0",
		"0", "LAYER", "2", "MYSTERY-37", "70", "0",
		"0", "ENDTAB", "0", "ENDSEC",
		"0", "SECTION", "2", "ENTITIES",
		# A 60 x 100 foot lot, drawn north of the origin as a plat is.
		"0", "LWPOLYLINE", "8", "PROPERTY", "90", "4", "70", "1",
		"10", "0.0", "20", "0.0", "10", "60.0", "20", "0.0",
		"10", "60.0", "20", "100.0", "10", "0.0", "20", "100.0",
		# A ten-foot easement along the south edge, and a curved one across the lot.
		"0", "LWPOLYLINE", "8", "EASEMENT", "90", "2", "70", "0",
		"10", "0.0", "20", "10.0", "42", "0.5", "10", "60.0", "20", "10.0",
		# A house, a driveway and a tree.
		"0", "LWPOLYLINE", "8", "MYSTERY-37", "90", "4", "70", "1",
		"10", "10.0", "20", "30.0", "10", "34.0", "20", "30.0",
		"10", "34.0", "20", "58.0", "10", "10.0", "20", "58.0",
		"0", "CIRCLE", "8", "MYSTERY-37", "10", "46.0", "20", "70.0", "40", "9.0",
		"0", "ARC", "8", "PROPERTY", "10", "30.0", "20", "100.0", "40", "14.0", "50", "0.0", "51", "180.0",
		# A label, at the height the surveyor drew it.
		"0", "TEXT", "8", "EASEMENT", "10", "2.0", "20", "4.0", "40", "0.8", "1", "10 FT EASEMENT",
		"0", "ENDSEC", "0", "EOF", "",
	]
	return "\n".join(PackedStringArray(lines))


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