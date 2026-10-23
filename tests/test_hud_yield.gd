extends Node
## How much to plant, joined to the Plant menu.
##
## The arithmetic is tested in `test_plant_yield.gd` and the page in `test_yield_window.gd`; this is the
## part that only exists when they are put together - that the Plant menu offers the page and hands it the
## list, that the page is built hidden inside the HUD and put in the Escape pass's list, and that an
## imported list reaches it while it is up.
##
## The HUD and the page enter no tree, so no `_ready` runs and no window is ever shown: `popup_centered`
## needs a screen and a test does not have one, which is why filling the page is its own function and
## `open_yield_window()` is only called where it is expected to do nothing.

const HudScript := preload("res://scripts/hud.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")
const CatalogueScript := preload("res://scripts/plant_catalogue.gd")


func _crop(species_id: StringName, name: String, gives: int, eats: int) -> PlantSpecies:
	var crop: PlantSpecies = SpeciesScript.make(species_id, name, "", 40, 30, SpeciesScript.ANNUAL)
	crop.edible_parts = SpeciesScript.EAT_LEAF
	crop.yield_per_plant_g = gives
	crop.need_per_person_g = eats
	return crop


func _catalogue(gives_a: int) -> PlantCatalogue:
	var catalogue: PlantCatalogue = CatalogueScript.make()
	catalogue.add(_crop(&"a", "First crop", gives_a, 5000))
	catalogue.add(_crop(&"b", "Second", 100, 100))
	return catalogue


# --- the menu ---------------------------------------------------------------------------------


func test_the_plant_menu_offers_it_with_no_key_and_needs_nothing() -> void:
	var entry: Dictionary = {}
	for candidate: Dictionary in HudScript.plant_items():
		if StringName(candidate.get("id", &"")) == &"plant.yield":
			entry = candidate
	assert(not entry.is_empty(), "the Plant menu has no entry for how much to plant")
	assert(String(entry["label"]) == "How much to plant...", String(entry["label"]))
	assert(StringName(entry["method"]) == &"_menu_yield_window", String(entry["method"]))
	assert(StringName(entry.get("action", &"")) == &"", "it takes no key")
	assert(entry["kind"] == "command", "and it is a command like the ones beside it")
	assert(
		StringName(entry["needs"]) == HudScript.NEEDS_NOTHING,
		"it reads the list and a household, neither of which is on a drawing"
	)


func test_every_menu_entry_still_names_a_method_this_hud_has() -> void:
	var hud: HudScript = HudScript.new()
	assert(hud.has_method(&"_menu_yield_window"), "the menu's door is a real one")
	assert(hud.has_method(&"_tick_yield_window"), "and so is the door the tick calls")
	assert(hud.has_method(&"open_yield_window"), "and the one the menu entry runs")
	hud.free()


# --- the page ---------------------------------------------------------------------------------


func test_the_page_is_built_hidden_inside_the_hud() -> void:
	var hud: HudScript = HudScript.new()
	hud._build_yield_window()
	assert(hud._yield_window != null, "the page was built")
	assert(hud._yield_window.get_parent() == hud, "it belongs to the HUD")
	assert(hud._yield_window.name == StringName("YieldWindow"), str(hud._yield_window.name))
	assert(not hud._yield_window.visible, "and it is not on screen")
	assert(not hud.is_yield_window_open(), "so nothing is open")
	hud.free()


func test_it_is_a_page_the_escape_pass_has_to_reach() -> void:
	# A page in a `Window` takes the keyboard into its own viewport, so it is only closable by Escape if
	# it is on the list the pass walks.
	var hud: HudScript = HudScript.new()
	hud._build_yield_window()
	assert(hud.pages_in_windows().has(hud._yield_window), "the page is on the list")
	hud._let_escape_close_pages()
	assert(hud._yield_window.get_node_or_null(^"PageEscape") != null, "and it can be escaped from")
	hud.free()


func test_a_hud_with_no_page_reports_nothing_open() -> void:
	var hud: HudScript = HudScript.new()
	assert(not hud.is_yield_window_open())
	hud.close_yield_window()
	assert(not hud.is_yield_window_open(), "and closing a page that is not open is harmless")
	hud.free()


func test_it_needs_no_drawing_to_be_filled() -> void:
	var hud: HudScript = HudScript.new()
	assert(hud._draft == null, "there is no drawing at all")
	hud._fill_yield_window()
	assert(hud._yield_window != null, "the page is built")
	assert(hud._yield_window.row_count() > 0, "and the shipped list is the food it works from")
	assert(not hud.is_yield_window_open(), "but nothing was shown - the page is only filled")
	hud.free()


func test_opening_it_is_not_done_off_tree() -> void:
	# `open_yield_window` shows the page, and `popup_centered` needs a window server a test has not got.
	# So this checks the door exists and does nothing here, rather than calling it.
	var hud: HudScript = HudScript.new()
	assert(hud.has_method(&"open_yield_window"), "the door is there")
	hud.free()


# --- the join ---------------------------------------------------------------------------------


func test_filling_it_hands_over_the_list() -> void:
	var hud: HudScript = HudScript.new()
	hud._plants = _catalogue(2000)
	hud._fill_yield_window()
	assert(hud._yield_window.row_count() == 2, "the list reaches the page: %d" % hud._yield_window.row_count())
	assert(hud._yield_window.feed_line().contains("To feed"), hud._yield_window.feed_line())
	hud.free()


func test_the_page_keeps_up_with_the_list_while_it_is_up() -> void:
	var hud: HudScript = HudScript.new()
	hud._plants = _catalogue(2000)
	hud._fill_yield_window()
	hud._yield_window.visible = true
	# A different yield has to reach the open page: the plan is a different number.
	hud._plants = _catalogue(4000)
	hud._tick_yield_window()
	assert(
		hud._yield_window.row_texts()[0] == "First crop: plant 6",
		"the changed list reaches the page: %s" % hud._yield_window.row_texts()[0]
	)
	hud._yield_window.visible = false
	hud.free()


func test_the_tick_is_harmless_while_the_page_is_away() -> void:
	var hud: HudScript = HudScript.new()
	hud._plants = _catalogue(2000)
	hud._build_yield_window()
	hud._tick_yield_window()
	assert(not hud._yield_window.visible, "a page that is not up was not shown by the tick")
	hud.free()


# --- the hand-off to the nursery order -------------------------------------------------------


func test_the_count_hands_over_to_the_nursery_order() -> void:
	var hud: HudScript = HudScript.new()
	hud._plants = _catalogue(2000)
	hud._fill_yield_window()
	var rows: Array = hud._yield_window.order_rows()
	assert(rows.size() == 2, "both crops worked out: %d" % rows.size())
	var planned: Dictionary = hud._show_yield_order(rows)
	assert(hud._plant_order_window != null, "the order page was built")
	assert(hud._plant_order_window.plan() == planned, "and it is showing the household's count")
	var total := 0
	for row: Dictionary in rows:
		total += int(row["count"])
	assert(int(planned.get("plants", 0)) == total, "the order's plants are the household's count: %d vs %d"
		% [int(planned.get("plants", 0)), total])
	hud.free()


func test_the_menu_door_is_the_drawings_planting_again() -> void:
	var hud: HudScript = HudScript.new()
	hud._plants = _catalogue(2000)
	hud._fill_yield_window()
	hud._show_yield_order(hud._yield_window.order_rows())
	assert(hud.plant_order_plan() == hud._plant_order_plan_override,
		"the handed plan is what the page is about")
	hud._forget_handed_plan()
	assert(hud._plant_order_plan_override.is_empty(), "and the menu door forgets it")
	assert(int(hud.plant_order_plan().get("plants", 0)) == 0,
		"so the page is about the drawing's planting, and this drawing has none")
	hud.free()


func test_the_page_is_wired_to_hand_its_count_over() -> void:
	var hud: HudScript = HudScript.new()
	hud._build_yield_window()
	assert(
		hud._yield_window.order_requested.is_connected(Callable(hud, &"_on_yield_order_requested")),
		"pressing the order button reaches this file"
	)
	hud.free()