extends Node
## Recording what is on site, joined to the Site menu.
##
## The identity rules are `test_field_capture.gd`'s, the survey's are `test_field_manifest_exporter.gd`'s
## and the page's own are `test_field_window.gd`'s; this is the part that only exists when they are put
## together - that the Site menu offers the page, that it is built hidden inside the HUD and put in the
## Escape pass's list, and that opening it hands over the one plant list.
##
## The HUD and the page enter no tree, so no `_ready` runs and no window is ever shown: `popup_centered`
## needs a screen and a test does not have one, which is why filling the page is its own function and
## `open_capture_window()` is only called where it is expected to do nothing.

const HudScript := preload("res://scripts/hud.gd")
const ControllerScript := preload("res://scripts/draft/draft_controller.gd")
const DocumentScript := preload("res://scripts/draft/draft_document.gd")


func _hud_with_a_drawing() -> Array:
	var controller: DraftController = ControllerScript.new()
	controller.document = DocumentScript.new()
	var hud: HudScript = HudScript.new()
	hud._draft = controller
	return [hud, controller]


func _done(parts: Array) -> void:
	var hud: HudScript = parts[0]
	var controller: Node = parts[1]
	hud.free()
	if controller != null:
		controller.free()


func test_the_site_menu_offers_it_needing_a_drawing() -> void:
	var entry: Dictionary = {}
	for candidate: Dictionary in HudScript.site_items():
		if StringName(candidate.get("id", &"")) == &"site.capture":
			entry = candidate
	assert(not entry.is_empty(), "the Site menu has no entry for recording what is on site")
	assert(String(entry["label"]) == "Record what is on site...", String(entry["label"]))
	assert(StringName(entry["method"]) == &"_menu_capture_window", String(entry["method"]))
	assert(StringName(entry.get("action", &"")) == &"", "it takes no key")
	assert(entry["kind"] == "command", "and it is a command like the ones beside it")
	assert(
		StringName(entry["needs"]) == HudScript.NEEDS_DRAFT,
		"a capture is a plant at a place on this site, and the site is the drawing"
	)


func test_the_menu_door_and_the_doors_behind_it_are_methods_this_hud_has() -> void:
	var hud: HudScript = HudScript.new()
	assert(hud.has_method(&"_menu_capture_window"), "the menu's door is a real one")
	assert(hud.has_method(&"_fill_capture_window"), "and so is the one that fills the page")
	assert(hud.has_method(&"open_capture_window"), "and the one the door calls")
	assert(hud.has_method(&"is_capture_window_open"), "and the one that answers whether it is up")
	hud.free()


func test_the_page_is_built_hidden_inside_the_hud() -> void:
	var hud: HudScript = HudScript.new()
	hud._build_capture_window()
	assert(hud._capture_window != null, "the page was built")
	assert(hud._capture_window.get_parent() == hud, "it belongs to the HUD")
	assert(hud._capture_window.name == StringName("CaptureWindow"), str(hud._capture_window.name))
	assert(not hud._capture_window.visible, "and it is not on screen")
	assert(not hud.is_capture_window_open(), "so nothing is open")
	hud.free()


func test_it_is_a_page_the_escape_pass_has_to_reach() -> void:
	# A page in a `Window` takes the keyboard into its own viewport, so it is only closable by Escape if
	# it is on the list the pass walks.
	var hud: HudScript = HudScript.new()
	hud._build_capture_window()
	assert(hud.pages_in_windows().has(hud._capture_window), "the page is on the list")
	hud._let_escape_close_pages()
	assert(hud._capture_window.get_node_or_null(^"PageEscape") != null, "and it can be escaped from")
	hud.free()


func test_a_hud_with_no_drawing_reports_nothing_open() -> void:
	var hud: HudScript = HudScript.new()
	assert(not hud.is_capture_window_open())
	hud.close_capture_window()
	assert(not hud.is_capture_window_open(), "and closing a page that is not open is harmless")
	hud.free()


func test_opening_it_with_no_drawing_builds_the_page_without_showing_it() -> void:
	var hud: HudScript = HudScript.new()
	assert(hud._draft == null, "there is no drawing at all")
	hud.open_capture_window()
	assert(hud._capture_window != null, "the page is built")
	assert(
		not hud.is_capture_window_open(),
		"but it is not shown - there is no drawing to put a plant on"
	)
	hud.free()


func test_filling_it_hands_over_the_list_the_browser_shows() -> void:
	var parts: Array = _hud_with_a_drawing()
	var hud: HudScript = parts[0]
	hud._fill_capture_window()
	assert(hud._capture_window != null, "the page was built")
	hud._capture_window.set_name_text("Thymus serpyllum")
	assert(
		hud._capture_window.species_line().contains("Thymus serpyllum"),
		"the shipped list reaches the page: %s" % hud._capture_window.species_line()
	)
	assert(
		String(hud._capture_window.capture()["species_id"]) == "thymus-serpyllum",
		"and a name typed on the page resolves against it"
	)
	_done(parts)