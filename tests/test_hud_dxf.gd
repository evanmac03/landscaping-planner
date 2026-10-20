extends Node
## The HUD's side of the DXF import: the File menu's way in, the page that says what was read, and the
## question a file that does not state its units has to be asked.
##
## The panel is a `Control` under `Root`, which a `Hud` built off-tree does not have - so what is under
## test here are the methods the panel's controls call, which is the same arrangement the sheet window
## and the hatch panel are tested with.

const HudScript := preload("res://scripts/hud.gd")
const ControllerScript := preload("res://scripts/draft/draft_controller.gd")
const DocumentScript := preload("res://scripts/draft/draft_document.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const DxfScript := preload("res://scripts/draft/dxf_file.gd")


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


## A DXF in the shape the reader reads, with a unitless header when `insunits` is 0.
func _dxf(insunits: int = 6) -> String:
	return "\n".join(PackedStringArray([
		"0", "SECTION", "2", "HEADER", "9", "$INSUNITS", "70", str(insunits),
		"0", "ENDSEC", "0", "SECTION", "2", "ENTITIES",
		"0", "LINE", "8", "PROPERTY", "10", "0.0", "20", "0.0", "11", "10.0", "21", "10.0",
		"0", "ENDSEC", "0", "EOF", "",
	]))


# --- the way in -----------------------------------------------------------------------


func test_the_file_menu_offers_importing_a_dxf() -> void:
	var entry: Dictionary = _entry(&"file.dxf")
	assert(String(entry["label"]) == "Import a DXF underlay...", String(entry["label"]))
	assert(StringName(entry["method"]) == &"_menu_import_dxf", String(entry["method"]))
	var in_file := false
	for listed: Dictionary in HudScript.items_for("File"):
		if StringName(listed.get("id", &"")) == &"file.dxf":
			in_file = true
	assert(in_file, "it is in the File menu, with the other things that come from somebody else")
	var hud := HudScript.new()
	assert(hud.has_method("_menu_import_dxf"), "and the method the entry names exists")
	assert(hud.has_method("open_dxf_panel"))
	assert(hud.has_method("dxf_report_text"))
	assert(not hud.is_dxf_panel_open(), "nothing is open until it is asked for")
	hud.free()


# --- what the page says ---------------------------------------------------------------


func test_a_reader_file_is_described_and_ready_to_place() -> void:
	var hud = _hud()
	hud._dxf_name = "site-plan.dxf"
	hud._dxf_text = _dxf()
	hud.open_dxf_panel()
	assert(bool(hud._pending_dxf["ok"]), String(hud._pending_dxf["reason"]))
	assert(hud.dxf_import_enabled(), "it holds a line and says it is in metres")
	var page: String = hud.dxf_report_text()
	assert(page.begins_with("site-plan.dxf"), page)
	assert(page.contains("1 shape in metres"), page)
	assert(page.contains("PROPERTY"), "and where its layer's geometry will go: %s" % page)
	_done(hud)


func test_a_file_that_is_not_a_dxf_says_so_and_cannot_be_placed() -> void:
	var hud = _hud()
	hud._dxf_name = "notes.txt"
	hud._dxf_text = "these are not\ncode pairs at all"
	hud.open_dxf_panel()
	assert(not bool(hud._pending_dxf["ok"]))
	assert(not hud.dxf_import_enabled())
	assert(hud.dxf_report_text().contains("DXF"), hud.dxf_report_text())
	# And confirming it does nothing rather than importing an empty drawing.
	var before: int = hud._draft.document.count()
	hud.confirm_dxf_import()
	assert(hud._draft.document.count() == before)
	_done(hud)


func test_nothing_read_yet_says_so_rather_than_failing() -> void:
	var hud = _hud()
	hud._pending_dxf = {}
	assert(hud.dxf_report_text() == "no DXF has been read", hud.dxf_report_text())
	assert(not hud.dxf_import_enabled())
	hud.confirm_dxf_import()
	assert(hud._draft.document.count() == 0)
	_done(hud)


# --- the question a unitless file asks -------------------------------------------------


func test_a_file_that_does_not_say_its_units_is_asked_about_and_then_read() -> void:
	var hud = _hud()
	hud._dxf_name = "plat.dxf"
	hud._dxf_text = _dxf(0)
	hud.open_dxf_panel()
	# Refused, with the sentence that asks - and not placeable until it is answered.
	assert(not bool(hud._pending_dxf["ok"]))
	assert(not hud.dxf_import_enabled())
	assert(int(hud._pending_dxf["insunits"]) == 0, "which the page uses to turn the units row on")
	assert(String(hud._pending_dxf["reason"]).contains("does not say"), String(hud._pending_dxf["reason"]))
	# Answered as feet: the same text read again, and now it reads - ten feet is 3.048 m.
	hud.choose_dxf_units("feet")
	assert(bool(hud._pending_dxf["ok"]), String(hud._pending_dxf["reason"]))
	assert(hud.dxf_import_enabled())
	assert(hud.dxf_report_text().contains("1 shape in feet"), hud.dxf_report_text())
	# And an answer the reader does not know is not an answer.
	hud.choose_dxf_units("furlongs")
	assert(not bool(hud._pending_dxf["ok"]))
	hud.choose_dxf_units("feet")
	assert(bool(hud._pending_dxf["ok"]))
	_done(hud)


func test_a_file_that_states_its_units_ignores_what_a_person_says() -> void:
	var hud = _hud()
	hud._dxf_text = _dxf(6)
	hud.open_dxf_panel()
	assert(hud._pending_dxf["units"] == "metres")
	# The file's own answer stands: answering for it would let a person halve a drawing by accident.
	hud.choose_dxf_units("feet")
	assert(String(hud._pending_dxf["units"]) == "metres", String(hud._pending_dxf["units"]))
	_done(hud)


# --- what confirming does --------------------------------------------------------------


func test_confirming_puts_the_underlay_on_the_drawing_and_closes_the_page() -> void:
	var hud = _hud()
	hud._dxf_text = _dxf()
	hud.open_dxf_panel()
	hud.confirm_dxf_import()
	assert(hud._draft.document.count() == 1, "the line is on the drawing")
	assert(hud._draft.document.entities()[0].layer == LayerSet.UNDERLAY, "on the layer that does not plot")
	assert(not hud.dxf_import_enabled(), "and the page has taken it")
	assert(String(hud._dxf_text).is_empty(), "and forgotten the file")
	_done(hud)


func test_a_drawing_that_is_not_there_yet_cannot_take_an_import() -> void:
	var hud = HudScript.new()
	hud._dxf_text = _dxf()
	hud.open_dxf_panel()
	# The reader is happy; the *drawing* is what is missing, and the page says so by refusing.
	assert(not hud.dxf_import_enabled())
	hud.confirm_dxf_import()
	assert(true, "and nothing raised")
	hud.free()