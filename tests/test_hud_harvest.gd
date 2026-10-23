extends Node
## What is ready when, joined to the Plant menu.
##
## The arithmetic is tested in `test_harvest_calendar.gd` and the page in `test_harvest_window.gd`; this
## is the part that only exists when they are put together - that the menu offers the page and gives it
## no key, that the page is built hidden inside the HUD and put in the Escape pass's list, and that it
## reads the *plant list* and nothing else, so it needs no drawing and keeps up with a list that changes
## while it is up.
##
## The HUD and the page enter no tree, so no `_ready` runs and no window is ever shown: `popup_centered`
## needs a screen and a test does not have one, which is why filling the page is its own function and
## `open_harvest_window()` is never called here.

const HudScript := preload("res://scripts/hud.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")
const CatalogueScript := preload("res://scripts/plant_catalogue.gd")


# --- the menu -----------------------------------------------------------------------------


func test_the_plant_menu_offers_it_with_no_key_and_needs_nothing() -> void:
	var entry: Dictionary = {}
	for candidate: Dictionary in HudScript.plant_items():
		if StringName(candidate.get("id", &"")) == &"plant.harvest":
			entry = candidate
	assert(not entry.is_empty(), "the Plant menu has no entry for what is ready when")
	assert(String(entry["label"]) == "What's ready when...", String(entry["label"]))
	assert(StringName(entry["method"]) == &"_menu_harvest_window", String(entry["method"]))
	assert(StringName(entry.get("action", &"")) == &"", "it takes no key")
	assert(entry["kind"] == "command", "and it is a command like the ones beside it")
	assert(
		StringName(entry["needs"]) == HudScript.NEEDS_NOTHING,
		"a harvest time is a fact about the crop, not about the ground, so it needs no drawing"
	)


func test_every_menu_entry_still_names_a_method_this_hud_has() -> void:
	# The new entry sits in the same bar as the rest, so the door it names has to exist.
	var hud: HudScript = HudScript.new()
	assert(hud.has_method(&"_menu_harvest_window"), "the menu's door is a real one")
	hud.free()


# --- the page -----------------------------------------------------------------------------


func test_the_page_is_built_hidden_inside_the_hud() -> void:
	var hud: HudScript = HudScript.new()
	hud._build_harvest_window()
	assert(hud._harvest_window != null, "the page was built")
	assert(hud._harvest_window.get_parent() == hud, "it belongs to the HUD")
	assert(hud._harvest_window.name == StringName("HarvestWindow"), str(hud._harvest_window.name))
	assert(not hud._harvest_window.visible, "and it is not on screen")
	assert(not hud.is_harvest_window_open(), "so nothing is open")
	hud.close_harvest_window()
	assert(not hud.is_harvest_window_open(), "and closing a page that is not open is harmless")
	hud.free()


func test_it_is_a_page_the_escape_pass_has_to_reach() -> void:
	# A page in a `Window` takes the keyboard into its own viewport, so it is only closable by Escape if
	# it is on the list the pass walks.
	var hud: HudScript = HudScript.new()
	hud._build_harvest_window()
	assert(hud.pages_in_windows().has(hud._harvest_window), "the page is on the list")
	hud._let_escape_close_pages()
	assert(hud._harvest_window.get_node_or_null(^"PageEscape") != null, "and it can be escaped from")
	hud.free()


# --- the join -----------------------------------------------------------------------------


func test_it_needs_no_drawing_to_be_filled() -> void:
	# Unlike the food and rotation pages, this one reads the plant list alone: a scene with no drawing
	# can still fill it.
	var hud: HudScript = HudScript.new()
	assert(hud._draft == null, "there is no drawing at all")
	hud._fill_harvest_window()
	assert(hud._harvest_window != null, "the page is built by filling it")
	assert(hud._harvest_window.row_count() > 0, "and the shipped list has crops with harvest windows")
	assert(not hud._harvest_window.month_line().is_empty(), hud._harvest_window.month_line())
	hud.free()


# --- the list is the only thing it reads ----------------------------------------------------


func test_the_refresh_is_harmless_while_the_page_is_away() -> void:
	# The tick runs every frame; a page that is not on screen must not be rewritten under it.
	var hud: HudScript = HudScript.new()
	hud._build_harvest_window()
	hud._tick_harvest_window()
	assert(not hud._harvest_window.visible, "a page that is not up was not shown by the tick")
	hud.free()


func test_the_page_keeps_up_with_the_list_while_it_is_up() -> void:
	# The one thing that can change under this page is the plant list itself - an import. When it does,
	# the page follows it.
	var hud: HudScript = HudScript.new()
	hud._fill_harvest_window()
	assert(hud._harvest_window.row_count() > 0, "the shipped list fills the page first")
	var small: PlantCatalogue = CatalogueScript.make()
	var crop: PlantSpecies = SpeciesScript.make(&"parsnip", "Parsnip", "", 60, 40, SpeciesScript.ANNUAL)
	crop.edible_parts = SpeciesScript.EAT_ROOT
	crop.set_harvests_in(3, true)   # March only
	small.add(crop)
	hud._plants = small
	hud._harvest_window.visible = true
	hud._tick_harvest_window()
	assert(hud._harvest_window.month() == 3, "the page moved to the new list's fullest month")
	assert(hud._harvest_window.row_count() == 1, "and shows the one crop the new list has")
	hud._harvest_window.visible = false
	hud.free()