extends Node
## The food garden, joined to the Plant menu and to the drawing.
##
## The arithmetic is tested in `test_crop_sun.gd` and the page in `test_food_window.gd`; this is the part
## that only exists when they are put together - that the menu offers the page and gives it no key, that
## the page is built hidden inside the HUD and put in the Escape pass's list, that the beds it checks
## are the *drawing's* own ground merged over the site, and that the page keeps up with the ground while
## it is up.
##
## The HUD and the page enter no tree, so no `_ready` runs and no window is ever shown:
## `popup_centered` needs a screen and a test does not have one, which is why filling the page is its
## own function and `open_food_window()` is never called here.

const HudScript := preload("res://scripts/hud.gd")
const ControllerScript := preload("res://scripts/draft/draft_controller.gd")
const DocumentScript := preload("res://scripts/draft/draft_document.gd")
const ProfileScript := preload("res://scripts/terrain_profile.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")


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
		if StringName(candidate.get("id", &"")) == &"plant.food":
			entry = candidate
	assert(not entry.is_empty(), "the Plant menu has no entry for the food garden")
	assert(String(entry["label"]) == "What will crop here...", String(entry["label"]))
	assert(StringName(entry["method"]) == &"_menu_food_window", String(entry["method"]))
	assert(StringName(entry.get("action", &"")) == &"", "it takes no key")
	assert(entry["kind"] == "command", "and it is a command like the ones beside it")
	assert(
		StringName(entry["needs"]) == HudScript.NEEDS_DRAFT,
		"it needs the drawing, because a bed's light is stated on the plan"
	)


# --- the page -----------------------------------------------------------------------------


func test_the_page_is_built_hidden_inside_the_hud() -> void:
	var hud: HudScript = HudScript.new()
	hud._build_food_window()
	assert(hud._food_window != null, "the page was built")
	assert(hud._food_window.get_parent() == hud, "it belongs to the HUD")
	assert(hud._food_window.name == StringName("FoodWindow"), str(hud._food_window.name))
	assert(not hud._food_window.visible, "and it is not on screen")
	assert(not hud.is_food_window_open(), "so nothing is open")
	hud.close_food_window()
	assert(not hud.is_food_window_open(), "and closing a page that is not open is harmless")
	hud.free()


func test_it_is_a_page_the_escape_pass_has_to_reach() -> void:
	# A page in a `Window` takes the keyboard into its own viewport, so it is only closable by Escape if
	# it is on the list the pass walks.
	var hud: HudScript = HudScript.new()
	hud._build_food_window()
	assert(hud.pages_in_windows().has(hud._food_window), "the page is on the list")
	hud._let_escape_close_pages()
	assert(hud._food_window.get_node_or_null(^"PageEscape") != null, "and it can be escaped from")
	hud.free()


# --- the beds are the drawing's -----------------------------------------------------------------


func test_a_scene_with_no_drawing_has_no_beds() -> void:
	var hud: HudScript = HudScript.new()
	assert(hud.food_places().is_empty(), "no drawing, no ground, no bed")
	hud.free()


func test_the_beds_are_the_ground_maps_own_merged_over_the_site() -> void:
	var controller: DraftController = _drawing()
	var map: ZoneMap = controller.document.environment
	map.base = ProfileScript.of("sun", SpeciesScript.FULL_SUN)
	map.add_zone("the north bed", _bed(), ProfileScript.of("sun", SpeciesScript.FULL_SHADE))
	var hud: HudScript = _hud_with_drawing(controller)
	var places: Array = hud.food_places()
	assert(places.size() == 2, "the site and the one bed: %d" % places.size())
	assert(String(places[0]["name"]) == "the whole site", String(places[0]["name"]))
	assert(
		int((places[0]["profile"] as TerrainProfile).sun_level()) == SpeciesScript.FULL_SUN,
		"the site's own light is the base"
	)
	assert(String(places[1]["name"]) == "the north bed", String(places[1]["name"]))
	assert(
		int((places[1]["profile"] as TerrainProfile).sun_level()) == SpeciesScript.FULL_SHADE,
		"and the bed's own light is the bed's"
	)
	hud.free()
	controller.free()


# --- the join -----------------------------------------------------------------------------


func test_filling_it_hands_over_the_plant_list_the_beds_and_the_site() -> void:
	var controller: DraftController = _drawing()
	var map: ZoneMap = controller.document.environment
	map.base = ProfileScript.of("sun", SpeciesScript.FULL_SUN)
	map.add_zone("the north bed", _bed(), ProfileScript.of("sun", SpeciesScript.FULL_SHADE))
	var hud: HudScript = _hud_with_drawing(controller)
	hud._fill_food_window()
	assert(hud._food_window != null, "the page is built by filling it")
	assert(hud._food_window.place_count() == 2, "both beds were handed over")
	assert(hud._food_window.row_count() > 0, "and the shipped list has food in it to check")
	assert(not hud._food_window.verdict_line().is_empty(), hud._food_window.verdict_line())
	hud.free()
	controller.free()


func test_the_page_keeps_up_with_the_ground_while_it_is_up() -> void:
	var controller: DraftController = _drawing()
	var hud: HudScript = _hud_with_drawing(controller)
	hud._fill_food_window()
	assert(hud._food_window.place_count() == 1, "with no zones there is only the site")
	hud._food_window.visible = true
	controller.document.environment.add_zone(
		"a bed", _bed(), ProfileScript.of("sun", SpeciesScript.FULL_SHADE)
	)
	hud._tick_food_window()
	assert(hud._food_window.place_count() == 2, "the bed stated while the page was up was picked up")
	hud._food_window.visible = false
	hud.free()
	controller.free()


func test_the_refresh_is_harmless_while_the_page_is_away() -> void:
	# The tick runs every frame; a page that is not on screen must not be rewritten under it.
	var controller: DraftController = _drawing()
	var hud: HudScript = _hud_with_drawing(controller)
	hud._build_food_window()
	controller.document.environment.add_zone(
		"a bed", _bed(), ProfileScript.of("sun", SpeciesScript.FULL_SHADE)
	)
	hud._tick_food_window()
	assert(hud._food_window.place_count() == 0, "a page that is not up was not written")
	hud.free()
	controller.free()