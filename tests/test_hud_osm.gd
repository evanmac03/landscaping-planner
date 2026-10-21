extends Node
## The HUD's side of the OpenStreetMap import: the File menu's way in, the window pointed at the
## drawing's own site, and the join between a map being read and the drawing taking it.
##
## The window is a `Window` and is never shown here - it is built and filled, which is what the
## methods the controls call do, and the same arrangement the sheet window is tested with.

const HudScript := preload("res://scripts/hud.gd")
const ControllerScript := preload("res://scripts/draft/draft_controller.gd")
const DocumentScript := preload("res://scripts/draft/draft_document.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const OsmFile := preload("res://scripts/draft/osm_file.gd")

const CENTRE := {"latitude": 43.7, "longitude": -79.4}
const SAVED := "user://osm-hud-test.json"


func _hud():
	var hud = HudScript.new()
	var controller = ControllerScript.new()
	controller.document = DocumentScript.new()
	hud._draft = controller
	return hud


func _done(hud) -> void:
	var controller: Node = hud._draft
	if hud._osm_window != null:
		hud._osm_window.free()
	if hud._osm_fetch != null:
		hud._osm_fetch.free()
	hud.free()
	if controller != null:
		controller.free()


func _entry(id: StringName) -> Dictionary:
	for entry: Dictionary in HudScript.menu_entries():
		if StringName(entry.get("id", &"")) == id:
			return entry
	assert(false, "no menu entry with id %s" % String(id))
	return {}


func _write_map() -> void:
	var file := FileAccess.open(SAVED, FileAccess.WRITE)
	file.store_string(JSON.stringify({"elements": [
		{
			"type": "way", "id": 1, "tags": {"building": "house"},
			"geometry": [
				{"lat": 43.7002, "lon": -79.3997}, {"lat": 43.7002, "lon": -79.3994},
				{"lat": 43.7, "lon": -79.3994}, {"lat": 43.7002, "lon": -79.3997},
			],
		},
		{"type": "node", "id": 2, "lat": 43.7001, "lon": -79.3999, "tags": {"natural": "tree"}},
	]}))
	file.close()


# --- the way in -----------------------------------------------------------------------


func test_the_file_menu_offers_importing_a_site_map() -> void:
	var entry: Dictionary = _entry(&"file.osm")
	assert(
		String(entry["label"]) == "Import a site map (OpenStreetMap)...", String(entry["label"])
	)
	assert(StringName(entry["method"]) == &"_menu_import_osm", String(entry["method"]))
	assert(StringName(entry["needs"]) == &"draft", "a map needs a drawing to land on")
	var in_file := false
	for listed: Dictionary in HudScript.items_for("File"):
		if StringName(listed.get("id", &"")) == &"file.osm":
			in_file = true
	assert(in_file, "it is in the File menu, with the other things that come from somebody else")
	var hud := HudScript.new()
	assert(hud.has_method("_menu_import_osm"), "and the method the entry names exists")
	assert(hud.has_method("open_osm_window"))
	assert(hud.has_method("osm_report_text"))
	assert(hud.has_method("osm_import_enabled"))
	assert(not hud.is_osm_window_open(), "nothing is open until it is asked for")
	hud.free()


func test_the_map_window_is_pointed_at_the_drawings_own_site() -> void:
	# A site is already a fact about the drawing - the sun study reads the same two numbers - so the
	# window opens on it rather than on a placeholder, and the common case needs no typing.
	var hud = _hud()
	hud._draft.document.set_site(51.5, -0.12, 0.0)
	hud._build_osm_window()
	hud._fill_osm_window()
	var centre: Dictionary = hud._osm_window.centre()
	assert(is_equal_approx(float(centre["latitude"]), 51.5), str(centre))
	assert(is_equal_approx(float(centre["longitude"]), -0.12), str(centre))
	assert(hud._osm_window.fetch_enabled(), "and a place can be asked about")
	assert(hud.osm_report_text() == "no map has been read", hud.osm_report_text())
	_done(hud)


# --- what the window says --------------------------------------------------------------


func test_nothing_read_yet_says_so_and_cannot_be_placed() -> void:
	var hud = _hud()
	assert(hud.osm_report_text() == "no map has been read", hud.osm_report_text())
	assert(not hud.osm_import_enabled())
	hud.confirm_osm_import()
	assert(hud._draft.document.count() == 0)
	_done(hud)


func test_a_saved_map_is_read_at_the_drawings_site_and_says_what_came_in() -> void:
	var hud = _hud()
	hud._draft.document.set_site(float(CENTRE["latitude"]), float(CENTRE["longitude"]), -5.0)
	_write_map()
	hud._on_osm_chosen(SAVED)
	assert(bool(hud._pending_osm.get("ok", false)), String(hud._pending_osm.get("reason", "")))
	assert(hud.osm_import_enabled(), "it holds a house and a tree")
	var page: String = hud.osm_report_text()
	assert(page.begins_with("osm-hud-test.json"), page)
	assert(page.contains("2 features from OpenStreetMap"), page)
	assert(page.contains("what came in: building x1, tree x1"), page)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVED))
	_done(hud)


func test_a_file_that_is_not_a_map_says_so_and_cannot_be_placed() -> void:
	var hud = _hud()
	_write_map()
	hud._on_osm_chosen("user://no-such-map.json")
	assert(not bool(hud._pending_osm.get("ok", false)))
	assert(not hud.osm_import_enabled())
	assert(hud.osm_report_text().contains("no file called"), hud.osm_report_text())
	var before: int = hud._draft.document.count()
	hud.confirm_osm_import()
	assert(hud._draft.document.count() == before, "and confirming it does nothing")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVED))
	_done(hud)


# --- what confirming does --------------------------------------------------------------


func test_confirming_puts_the_map_on_the_underlay_and_closes_the_window() -> void:
	var hud = _hud()
	hud._draft.document.set_site(float(CENTRE["latitude"]), float(CENTRE["longitude"]), -5.0)
	_write_map()
	hud._on_osm_chosen(SAVED)
	hud.confirm_osm_import()
	assert(hud._draft.document.count() == 2, "the house and the tree are on the drawing")
	for entity: DraftEntity in hud._draft.document.entities():
		assert(entity.layer == LayerSet.UNDERLAY, "on the layer that does not plot")
	assert(hud._pending_osm.is_empty(), "and the window has taken it")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVED))
	_done(hud)


func test_a_drawing_that_is_not_there_yet_cannot_take_an_import() -> void:
	var hud = HudScript.new()
	hud._pending_osm = OsmFile.read_text(
		JSON.stringify({"elements": [
			{"type": "node", "id": 1, "lat": 43.7001, "lon": -79.4, "tags": {"natural": "tree"}},
		]}),
		{"centre": CENTRE}
	)
	# The reader is happy; the *drawing* is what is missing, and the page says so by refusing.
	assert(not hud.osm_import_enabled())
	hud.confirm_osm_import()
	assert(true, "and nothing raised")
	hud.free()