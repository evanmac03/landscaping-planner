extends Node
## The sowing page: a day to sow, a crop to sow, an interval to repeat it by, and what the season says.
##
## The page is built and driven off-tree, so no `_ready` runs and no window is ever shown:
## `popup_centered` needs a screen and a test does not have one.

const PageScript := preload("res://scripts/sowing_window.gd")
const PlannerScript := preload("res://scripts/sowing_planner.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")
const CatalogueScript := preload("res://scripts/plant_catalogue.gd")
const DocumentScript := preload("res://scripts/draft/draft_document.gd")

## A temperate garden: last frost 20 May, first frost 7 October, so 140 days.
const LAST := 140
const FIRST := 280


func _crop(species_id: StringName, name: String, days: int) -> PlantSpecies:
	var crop: PlantSpecies = SpeciesScript.make(species_id, name, "", 40, 30, SpeciesScript.ANNUAL)
	crop.edible_parts = SpeciesScript.EAT_LEAF
	crop.maturity_days = days
	return crop


func _catalogue() -> PlantCatalogue:
	var catalogue: PlantCatalogue = CatalogueScript.make()
	catalogue.add(_crop(&"quick", "Quick", 60))
	catalogue.add(_crop(&"slow", "Slow", 200))
	catalogue.add(_crop(&"unstated", "Unstated", 0))
	catalogue.add(SpeciesScript.make(&"boxwood", "Buxus sempervirens", "Box", 60, 60, SpeciesScript.SHRUB))
	return catalogue


func _season_document() -> DraftDocument:
	var document: DraftDocument = DocumentScript.new()
	document.set_season(LAST, FIRST)
	return document


func _page() -> SowingWindow:
	var page: SowingWindow = PageScript.new()
	page.build()
	return page


# --- the controls ---------------------------------------------------------------------------


func test_the_page_builds_its_controls_and_takes_no_keyboard() -> void:
	var page: SowingWindow = _page()
	assert(page.get_node_or_null(^"Column/SowRow/SowBox") != null, "there is a field for the sowing day")
	assert(page.get_node_or_null(^"Column/EveryRow/EveryBox") != null, "and one for the interval")
	assert(page.get_node_or_null(^"Column/CropRow/Crop") != null, "and a picker for the crop")
	assert(page.get_node_or_null(^"Column/Crops") != null, "and a list for the food")
	assert(page.lists_are_keyboard_free(), "the crop list does not take the keyboard from the drawing")
	assert(not page.visible, "and a page nobody asked for is not on screen")
	page.free()


func test_a_page_with_no_drawing_says_so_rather_than_failing() -> void:
	var page: SowingWindow = _page()
	assert(page.season_line() == PageScript.NO_DOCUMENT, page.season_line())
	assert(page.hint() == PageScript.NO_DOCUMENT, page.hint())
	assert(not page.season_stated(), "nothing is stated with no drawing")
	assert(page.verdict_line() == PageScript.NO_CROPS, "and there is no crop to work out")
	assert(page.sow() == PageScript.DEFAULT_SOW, "the day in hand starts on the temperate last frost")
	page.free()


# --- binding ------------------------------------------------------------------------------


func test_binding_hands_over_the_list_and_sows_from_the_drawings_last_frost() -> void:
	var page: SowingWindow = _page()
	page.bind(_catalogue(), _season_document())
	assert(page.season_stated(), "the drawing's season reaches the page")
	assert(page.season_line().contains("140 days"), page.season_line())
	assert(page.sow() == LAST, "the day in hand is the drawing's last frost: %d" % page.sow())
	assert(page.crop_ids().size() == 3, "the boxwood is not a crop: %d" % page.crop_ids().size())
	assert(page.sow() != page.interval(), "the interval starts somewhere of its own")
	assert(page.interval() == PlannerScript.DEFAULT_INTERVAL, "%d" % page.interval())
	page.free()


func test_a_drawing_that_states_no_season_still_opens_on_a_starting_day() -> void:
	var page: SowingWindow = _page()
	page.bind(_catalogue(), DocumentScript.new())
	assert(not page.season_stated(), "nothing is stated")
	assert(page.sow() == PageScript.DEFAULT_SOW, "so the field starts where it always starts")
	assert(page.hint() == PageScript.NOT_STATED_HINT, page.hint())
	page.free()


# --- what the crop comes to ------------------------------------------------------------------


func test_the_crop_lines_say_the_crop_its_verdict_its_window_and_its_succession() -> void:
	var page: SowingWindow = _page()
	page.bind(_catalogue(), _season_document())
	page.choose_crop(&"quick")
	assert(page.crop_line().contains("Quick") and page.crop_line().contains("60 days"), page.crop_line())
	assert(page.verdict_line().contains("ready about 19 July"), page.verdict_line())
	assert(page.window_line().contains("20 May"), page.window_line())
	assert(page.succession_line().contains("21 days"), page.succession_line())
	assert(page.succession_line().contains("sowings"), page.succession_line())
	page.free()


func test_moving_the_sowing_day_moves_the_verdict() -> void:
	var page: SowingWindow = _page()
	page.bind(_catalogue(), _season_document())
	page.choose_crop(&"quick")
	page.set_sow(LAST)
	assert(page.verdict_line().contains("ready about"), page.verdict_line())
	page.set_sow(260)   # too late for a 60-day crop
	assert(page.verdict_line().contains("would not finish"), page.verdict_line())
	assert(not page.window_line().is_empty(), "and the window line still says something")
	page.free()


func test_a_crop_with_no_time_to_maturity_is_told_apart() -> void:
	var page: SowingWindow = _page()
	page.bind(_catalogue(), _season_document())
	page.choose_crop(&"unstated")
	assert(page.verdict_line().contains("does not record a time to maturity"), page.verdict_line())
	assert(page.crop_line().contains("no time to maturity stated"), page.crop_line())
	page.free()


func test_a_drawing_with_no_season_checks_nothing_but_still_lists_the_food() -> void:
	var page: SowingWindow = _page()
	page.bind(_catalogue(), DocumentScript.new())
	page.choose_crop(&"quick")
	assert(page.verdict_line().contains("not stated"), page.verdict_line())
	assert(page.window_line() == PageScript.NOT_STATED_HINT, page.window_line())
	assert(page.row_count() == 3, "every food crop is still listed")
	assert(page.summary_text().contains("cannot be checked"), page.summary_text())
	page.free()


func test_choosing_a_crop_the_list_does_not_hold_is_refused() -> void:
	var page: SowingWindow = _page()
	page.bind(_catalogue(), _season_document())
	page.choose_crop(&"quick")
	assert(not page.choose_crop(&"boxwood"), "the shrub is not among the crops")
	assert(page.selected_crop_id() == &"quick", "and the choice is unmoved")
	page.free()


# --- the list ------------------------------------------------------------------------------


func test_the_list_is_food_only_and_reads_as_lines() -> void:
	var page: SowingWindow = _page()
	page.bind(_catalogue(), _season_document())
	assert(page.row_count() == 3, "the boxwood is not a crop: %d" % page.row_count())
	var texts: Array[String] = page.row_texts()
	assert(texts[0].begins_with("Quick:"), texts[0])
	for text: String in texts:
		assert(not text.contains("Box"), "no shrub among the sowings: %s" % text)
	assert(page.summary_text().contains("ripen in time"), page.summary_text())
	page.free()


func test_the_hint_is_guidance_rather_than_a_line_said_twice() -> void:
	var page: SowingWindow = _page()
	page.bind(_catalogue(), _season_document())
	assert(page.hint() != page.season_line(), "the guidance is not the season line again")
	assert(not page.hint().contains("140 days"), page.hint())
	page.free()


# --- closing -------------------------------------------------------------------------------


func test_closing_the_page_says_so_once() -> void:
	var page: SowingWindow = _page()
	var closed: Array = []
	page.closed.connect(func() -> void: closed.append(1))
	page.request_close()
	assert(closed.size() == 1)
	assert(not page.visible)
	page.free()