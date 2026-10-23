extends Node
## What to grow here next, joined to the Plant menu and to the drawing.
##
## The arithmetic is tested in `test_crop_rotation.gd` and the page in `test_rotation_window.gd`; this
## is the part that only exists when they are put together - that the menu offers the page and gives it
## no key, that the page is built hidden inside the HUD and put in the Escape pass's list, that the
## beds it offers are the *drawing's* own ground, and that the page keeps up with the ground while
## keeping the history a person has stated.
##
## The HUD and the page enter no tree, so no `_ready` runs and no window is ever shown:
## `popup_centered` needs a screen and a test does not have one, which is why filling the page is its
## own function and `open_rotation_window()` is never called here.

const HudScript := preload("res://scripts/hud.gd")
const ControllerScript := preload("res://scripts/draft/draft_controller.gd")
const DocumentScript := preload("res://scripts/draft/draft_document.gd")
const ProfileScript := preload("res://scripts/terrain_profile.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")
const CropRotationScript := preload("res://scripts/crop_rotation.gd")


func _drawing() -> DraftController:
	var controller: DraftController = ControllerScript.new()
	controller._bind_document(DocumentScript.new())
	return controller


func _hud_with_drawing(controller: DraftController) -> Node:
	var hud: HudScript = HudScript.new()
	hud._draft = controller
	return hud


## A four-metre square bed, which is all a zone needs to be a place.
func _bed() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(4.0, 0.0), Vector2(4.0, 4.0), Vector2(0.0, 4.0)
	])


# --- the menu -----------------------------------------------------------------------------


func test_the_plant_menu_offers_it_with_no_key_and_needs_a_drawing() -> void:
	var entry: Dictionary = {}
	for candidate: Dictionary in HudScript.plant_items():
		if StringName(candidate.get("id", &"")) == &"plant.rotation":
			entry = candidate
	assert(not entry.is_empty(), "the Plant menu has no entry for what to grow here next")
	assert(String(entry["label"]) == "What to grow here next...", String(entry["label"]))
	assert(StringName(entry["method"]) == &"_menu_rotation_window", String(entry["method"]))
	assert(StringName(entry.get("action", &"")) == &"", "it takes no key")
	assert(entry["kind"] == "command", "and it is a command like the ones beside it")
	assert(
		StringName(entry["needs"]) == HudScript.NEEDS_DRAFT,
		"it needs the drawing, because the beds are the plan's ground"
	)


func test_every_menu_entry_still_names_a_method_this_hud_has() -> void:
	# The new entry sits in the same bar as the rest, so the door it names has to exist.
	var hud: HudScript = HudScript.new()
	assert(hud.has_method(&"_menu_rotation_window"), "the menu's door is a real one")
	hud.free()


# --- the page -----------------------------------------------------------------------------


func test_the_page_is_built_hidden_inside_the_hud() -> void:
	var hud: HudScript = HudScript.new()
	hud._build_rotation_window()
	assert(hud._rotation_window != null, "the page was built")
	assert(hud._rotation_window.get_parent() == hud, "it belongs to the HUD")
	assert(hud._rotation_window.name == StringName("RotationWindow"), str(hud._rotation_window.name))
	assert(not hud._rotation_window.visible, "and it is not on screen")
	assert(not hud.is_rotation_window_open(), "so nothing is open")
	hud.close_rotation_window()
	assert(not hud.is_rotation_window_open(), "and closing a page that is not open is harmless")
	hud.free()


func test_it_is_a_page_the_escape_pass_has_to_reach() -> void:
	# A page in a `Window` takes the keyboard into its own viewport, so it is only closable by Escape if
	# it is on the list the pass walks.
	var hud: HudScript = HudScript.new()
	hud._build_rotation_window()
	assert(hud.pages_in_windows().has(hud._rotation_window), "the page is on the list")
	hud._let_escape_close_pages()
	assert(hud._rotation_window.get_node_or_null(^"PageEscape") != null, "and it can be escaped from")
	hud.free()


# --- the beds are the drawing's -----------------------------------------------------------------


func test_a_scene_with_no_drawing_has_no_beds() -> void:
	var hud: HudScript = HudScript.new()
	assert(hud.rotation_places().is_empty(), "no drawing, no ground, no bed")
	hud.free()


func test_the_beds_are_the_ground_maps_own() -> void:
	var controller: DraftController = _drawing()
	var map: ZoneMap = controller.document.environment
	map.base = ProfileScript.of("sun", SpeciesScript.FULL_SUN)
	map.add_zone("the north bed", _bed(), ProfileScript.of("sun", SpeciesScript.FULL_SHADE))
	var hud: HudScript = _hud_with_drawing(controller)
	var places: Array = hud.rotation_places()
	assert(places.size() == 2, "the site and the one bed: %d" % places.size())
	assert(String(places[0]["name"]) == "the whole site", String(places[0]["name"]))
	assert(String(places[1]["name"]) == "the north bed", String(places[1]["name"]))
	hud.free()
	controller.free()


# --- the join -----------------------------------------------------------------------------


func test_filling_it_hands_over_the_plant_list_and_the_beds() -> void:
	var controller: DraftController = _drawing()
	var map: ZoneMap = controller.document.environment
	map.add_zone("the north bed", _bed(), ProfileScript.of("sun", SpeciesScript.FULL_SHADE))
	var hud: HudScript = _hud_with_drawing(controller)
	hud._fill_rotation_window()
	assert(hud._rotation_window != null, "the page is built by filling it")
	assert(hud._rotation_window.place_count() == 2, "both beds were handed over")
	assert(hud._rotation_window.row_count() > 0, "and the shipped list has food in it to rotate")
	assert(not hud._rotation_window.turn_line().is_empty(), hud._rotation_window.turn_line())
	hud.free()
	controller.free()


func test_the_page_keeps_up_with_the_ground_and_keeps_what_was_stated() -> void:
	var controller: DraftController = _drawing()
	var hud: HudScript = _hud_with_drawing(controller)
	hud._fill_rotation_window()
	assert(hud._rotation_window.place_count() == 1, "with no zones there is only the site")
	assert(hud._rotation_window.choose_previous_family(CropRotationScript.BRASSICA), "state a history")
	hud._rotation_window.visible = true
	controller.document.environment.add_zone(
		"a bed", _bed(), ProfileScript.of("sun", SpeciesScript.FULL_SHADE)
	)
	hud._tick_rotation_window()
	assert(hud._rotation_window.place_count() == 2, "the bed stated while the page was up was picked up")
	assert(
		StringName(hud._rotation_window.previous_family()) == CropRotationScript.BRASSICA,
		"and the history a person stated was not thrown away"
	)
	hud._rotation_window.visible = false
	hud.free()
	controller.free()


func test_the_refresh_is_harmless_while_the_page_is_away() -> void:
	# The tick runs every frame; a page that is not on screen must not be rewritten under it.
	var controller: DraftController = _drawing()
	var hud: HudScript = _hud_with_drawing(controller)
	hud._build_rotation_window()
	controller.document.environment.add_zone(
		"a bed", _bed(), ProfileScript.of("sun", SpeciesScript.FULL_SHADE)
	)
	hud._tick_rotation_window()
	assert(hud._rotation_window.place_count() == 0, "a page that is not up was not written")
	hud.free()
	controller.free()