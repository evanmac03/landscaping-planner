extends Node
## The HUD's side of the LandXML import: the File menu's way in, the page that says what was read, the
## question a plat that does not state its units has to be asked, and what confirming does.
##
## The panel is a `Control` under `Root`, which a `Hud` built off-tree does not have - so what is under
## test here are the methods the panel's controls call, which is the arrangement the DXF page and the
## hatch panel are tested with.

const HudScript := preload("res://scripts/hud.gd")
const ControllerScript := preload("res://scripts/draft/draft_controller.gd")
const DocumentScript := preload("res://scripts/draft/draft_document.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")


func _hud():
	var hud := HudScript.new()
	var controller = ControllerScript.new()
	controller.document = DocumentScript.new()
	hud._draft = controller
	return hud


func _done(hud) -> void:
	var controller: Node = hud._draft
	hud.free()
	if controller != null:
		controller.free()


func _entry(id: StringName) -> Dictionary:
	for entry: Dictionary in HudScript.menu_entries():
		if StringName(entry.get("id", &"")) == id:
			return entry
	assert(false, "no menu entry with id %s" % String(id))
	return {}


## A plat with a parcel of four corners and an alignment with a curve in it, in the units the
## `<Units>` element names - or in no units at all when `units` is empty.
func _plat(units: String = "<Metric linearUnit=\"meter\"/>") -> String:
	return "\n".join(PackedStringArray([
		"<?xml version=\"1.0\"?>",
		"<LandXML xmlns=\"http://www.landxml.org/schema/LandXML-1.2\" version=\"1.2\">",
		"  <Units>" + units + "</Units>",
		"  <Parcels>",
		"    <Parcel name=\"LOT 12\">",
		"      <CoordGeom>",
		"        <Line><Start>1000.0 3000.0</Start><End>1000.0 3060.0</End></Line>",
		"        <Line><Start>1000.0 3060.0</Start><End>1060.0 3060.0</End></Line>",
		"        <Line><Start>1060.0 3060.0</Start><End>1060.0 3000.0</End></Line>",
		"        <Line><Start>1060.0 3000.0</Start><End>1000.0 3000.0</End></Line>",
		"      </CoordGeom>",
		"    </Parcel>",
		"  </Parcels>",
		"</LandXML>",
		"",
	]))


# --- the way in -----------------------------------------------------------------------


func test_the_file_menu_offers_importing_a_landxml_plat() -> void:
	var entry: Dictionary = _entry(&"file.landxml")
	assert(String(entry["label"]) == "Import a LandXML plat...", String(entry["label"]))
	assert(StringName(entry["method"]) == &"_menu_import_landxml", String(entry["method"]))
	var in_file := false
	for listed: Dictionary in HudScript.items_for("File"):
		if StringName(listed.get("id", &"")) == &"file.landxml":
			in_file = true
	assert(in_file, "it is in the File menu, with the other things that come from somebody else")
	var hud := HudScript.new()
	assert(hud.has_method("_menu_import_landxml"), "and the method the entry names exists")
	assert(hud.has_method("open_landxml_panel"))
	assert(hud.has_method("landxml_report_text"))
	assert(not hud.is_landxml_panel_open(), "nothing is open until it is asked for")
	hud.free()


# --- what the page says ---------------------------------------------------------------


func test_a_plat_is_described_and_ready_to_place() -> void:
	var hud = _hud()
	hud._landxml_name = "lot-12.xml"
	hud._landxml_text = _plat()
	hud.open_landxml_panel()
	assert(bool(hud._pending_landxml["ok"]), String(hud._pending_landxml["reason"]))
	assert(hud.landxml_import_enabled(), "it holds a parcel and says it is in metres")
	var page: String = hud.landxml_report_text()
	assert(page.begins_with("lot-12.xml"), page)
	assert(page.contains("1 shape in metres"), page)
	assert(page.contains("parcel -> 950-UNDERLAY"), "and where its geometry will go: %s" % page)
	_done(hud)


func test_a_file_that_is_not_a_plat_says_so_and_cannot_be_placed() -> void:
	var hud = _hud()
	hud._landxml_name = "notes.xml"
	hud._landxml_text = "<notes><line>these are not a plat</line></notes>"
	hud.open_landxml_panel()
	assert(not bool(hud._pending_landxml["ok"]))
	assert(not hud.landxml_import_enabled())
	assert(hud.landxml_report_text().contains("LandXML"), hud.landxml_report_text())
	# And confirming it does nothing rather than importing an empty drawing.
	var before: int = hud._draft.document.count()
	hud.confirm_landxml_import()
	assert(hud._draft.document.count() == before)
	_done(hud)


func test_nothing_read_yet_says_so_rather_than_failing() -> void:
	var hud = _hud()
	hud._pending_landxml = {}
	assert(hud.landxml_report_text() == "no LandXML plat has been read", hud.landxml_report_text())
	assert(not hud.landxml_import_enabled())
	hud.confirm_landxml_import()
	assert(hud._draft.document.count() == 0)
	_done(hud)


# --- the question a unitless plat asks --------------------------------------------------


func test_a_plat_that_does_not_say_its_units_is_asked_about_and_then_read() -> void:
	var hud = _hud()
	hud._landxml_name = "plat.xml"
	hud._landxml_text = _plat("")
	hud.open_landxml_panel()
	# Refused, with the sentence that asks - and not placeable until it is answered.
	assert(not bool(hud._pending_landxml["ok"]))
	assert(not hud.landxml_import_enabled())
	assert(String(hud._pending_landxml["declared_unit"]).is_empty(),
		"which the page uses to turn the units row on")
	assert(String(hud._pending_landxml["reason"]).contains("does not say"),
		String(hud._pending_landxml["reason"]))
	# Answered as feet: the same text read again, and now it reads - sixty feet is 18.288 m.
	hud.choose_landxml_units("feet")
	assert(bool(hud._pending_landxml["ok"]), String(hud._pending_landxml["reason"]))
	assert(hud.landxml_import_enabled())
	assert(hud.landxml_report_text().contains("1 shape in feet"), hud.landxml_report_text())
	var parcel: Dictionary = (hud._pending_landxml["shapes"] as Array)[0]
	var corners: PackedVector2Array = parcel["points"]
	assert(corners.size() == 4, "four corners")
	# Read as feet, the lot's own 60-foot side is 18.288 m of easting in the model.
	assert(absf(corners[0].distance_to(corners[1]) - 18.288) < 1.0e-3,
		"sixty feet of easting is 18.288 m: %.4f" % corners[0].distance_to(corners[1]))
	# And an answer the reader does not know is not an answer.
	hud.choose_landxml_units("furlongs")
	assert(not bool(hud._pending_landxml["ok"]))
	hud.choose_landxml_units("feet")
	assert(bool(hud._pending_landxml["ok"]))
	_done(hud)


func test_a_plat_that_states_its_units_ignores_what_a_person_says() -> void:
	var hud = _hud()
	hud._landxml_text = _plat("<Imperial linearUnit=\"USSurveyFoot\"/>")
	hud.open_landxml_panel()
	assert(String(hud._pending_landxml["units"]) == "US survey feet", String(hud._pending_landxml["units"]))
	# The file's own answer stands: answering for it would let a person halve a drawing by accident.
	hud.choose_landxml_units("metres")
	assert(String(hud._pending_landxml["units"]) == "US survey feet",
		String(hud._pending_landxml["units"]))
	_done(hud)


# --- what confirming does --------------------------------------------------------------


func test_confirming_puts_the_plat_on_the_drawing_and_closes_the_page() -> void:
	var hud = _hud()
	hud._landxml_text = _plat()
	hud.open_landxml_panel()
	hud.confirm_landxml_import()
	assert(hud._draft.document.count() == 1, "the parcel is on the drawing")
	assert(hud._draft.document.entities()[0].layer == LayerSet.UNDERLAY, "on the layer that does not plot")
	assert(not hud.landxml_import_enabled(), "and the page has taken it")
	assert(String(hud._landxml_text).is_empty(), "and forgotten the file")
	_done(hud)


func test_a_drawing_that_is_not_there_yet_cannot_take_an_import() -> void:
	var hud := HudScript.new()
	hud._landxml_text = _plat()
	hud.open_landxml_panel()
	# The reader is happy; the *drawing* is what is missing, and the page says so by refusing.
	assert(not hud.landxml_import_enabled())
	hud.confirm_landxml_import()
	assert(true, "and nothing raised")
	hud.free()