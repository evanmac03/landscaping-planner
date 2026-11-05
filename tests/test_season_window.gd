extends Node
## The season page: the site's frost dates, and the food list measured against the season they bound.
##
## The page is built and driven off-tree, so no `_ready` runs and no window is ever shown:
## `popup_centered` needs a screen and a test does not have one.

const PageScript := preload("res://scripts/season_window.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")
const CatalogueScript := preload("res://scripts/plant_catalogue.gd")
const DocumentScript := preload("res://scripts/draft/draft_document.gd")

## A temperate garden: 20 May to 7 October, 140 days.
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


func _page() -> SeasonWindow:
	var page: SeasonWindow = PageScript.new()
	page.build()
	return page


# --- the controls -----------------------------------------------------------------------------


func test_the_page_builds_its_controls_without_a_keyboard_of_their_own() -> void:
	var page: SeasonWindow = _page()
	assert(
		page.get_node_or_null(^"Column/LastFrostRow/LastFrostBox") != null,
		"there is a field for the last frost"
	)
	assert(
		page.get_node_or_null(^"Column/FirstFrostRow/FirstFrostBox") != null,
		"and one for the first frost"
	)
	assert(page.get_node_or_null(^"Column/Crops") != null, "and a list for the crops")
	assert(page.lists_are_keyboard_free(), "the crop list does not take the keyboard from the drawing")
	assert(not page.visible, "and a page nobody asked for is not on screen")
	page.free()


func test_a_page_with_no_drawing_says_so_rather_than_failing() -> void:
	var page: SeasonWindow = _page()
	assert(page.season_line() == PageScript.NO_DOCUMENT, page.season_line())
	assert(page.hint() == PageScript.NO_DOCUMENT, page.hint())
	assert(not page.season_stated(), "nothing is stated with no drawing")
	assert(not page.state_enabled(), "so the button is dead")
	assert(not page.state_season(), "and pressing it says why rather than failing")
	assert(page.said() == PageScript.NO_DOCUMENT, page.said())
	page.free()


# --- stating the season -----------------------------------------------------------------------


func test_stating_the_season_writes_it_to_the_drawing_and_announces_it() -> void:
	var page: SeasonWindow = _page()
	var document: DraftDocument = DocumentScript.new()
	page.set_document(document)
	page.set_catalogue(_catalogue())
	var announced: Array = []
	page.season_changed.connect(func() -> void: announced.append(1))
	page.set_fields(LAST, FIRST)
	assert(page.state_enabled(), "the button is live with a season in the fields")
	assert(page.state_season(), "and it states it")
	assert(document.season_last_frost == LAST and document.season_first_frost == FIRST, "on the drawing")
	assert(announced.size() == 1, "and it announces itself")
	assert(page.said().contains("140 days"), page.said())
	page.free()


func test_dates_that_are_not_a_season_are_refused_rather_than_stored() -> void:
	var page: SeasonWindow = _page()
	var document: DraftDocument = DocumentScript.new()
	page.set_document(document)
	page.set_fields(FIRST, LAST)   # the first frost before the last
	assert(not page.state_enabled(), "the button is dead for dates that are not a season")
	assert(not page.state_season())
	assert(page.said() == PageScript.BAD_DATES, page.said())
	assert(document.season_last_frost == 0 and document.season_first_frost == 0, "and nothing is stored")
	page.free()


func test_stating_the_same_season_twice_is_not_a_change() -> void:
	var page: SeasonWindow = _page()
	var document: DraftDocument = DocumentScript.new()
	page.set_document(document)
	page.set_fields(LAST, FIRST)
	assert(page.state_season())
	assert(not page.state_season(), "the same season again is nothing to state")
	assert(page.said().contains("already"), page.said())
	page.free()


func test_taking_the_season_back_unstates_it() -> void:
	var page: SeasonWindow = _page()
	var document: DraftDocument = DocumentScript.new()
	document.set_season(LAST, FIRST)
	page.set_document(document)
	assert(page.season_stated(), "the drawing states a season")
	assert(page.clear_enabled(), "so it can be taken back")
	var announced: Array = []
	page.season_changed.connect(func() -> void: announced.append(1))
	assert(page.clear_season())
	assert(document.season_last_frost == 0 and document.season_first_frost == 0, "the drawing states none again")
	assert(announced.size() == 1, "and it announces itself")
	assert(not page.clear_enabled(), "and there is nothing left to take back")
	assert(not page.clear_season(), "pressing it again does nothing")
	page.free()


# --- reading the drawing ----------------------------------------------------------------------


func test_the_page_reads_the_drawings_season_and_shows_it() -> void:
	var page: SeasonWindow = _page()
	var document: DraftDocument = DocumentScript.new()
	document.set_season(LAST, FIRST)
	page.set_document(document)
	assert(page.season_stated())
	assert(page.season_line().contains("140 days"), page.season_line())
	assert(page.last_frost() == LAST and page.first_frost() == FIRST)
	assert(page.field_last_frost() == LAST, "and the fields show it")
	assert(page.field_first_frost() == FIRST)
	page.free()


func test_a_drawing_that_states_nothing_leaves_the_fields_alone() -> void:
	var page: SeasonWindow = _page()
	page.set_document(DocumentScript.new())
	page.set_fields(150, 300)
	page.set_document(DocumentScript.new())   # a drawing that states no season either
	assert(
		page.field_last_frost() == 150 and page.field_first_frost() == 300,
		"what a person is about to fill in is not thrown away by a refresh"
	)
	page.free()


# --- the crop list ----------------------------------------------------------------------------


func test_the_list_is_food_only_and_measured_against_the_stated_season() -> void:
	var page: SeasonWindow = _page()
	var document: DraftDocument = DocumentScript.new()
	document.set_season(LAST, FIRST)
	page.set_document(document)
	page.set_catalogue(_catalogue())
	assert(page.row_count() == 3, "the boxwood is not a crop: %d" % page.row_count())
	var texts: Array[String] = page.row_texts()
	assert(texts[0].begins_with("Quick:"), texts[0])
	assert(page.summary_text().contains("have time to finish"), page.summary_text())
	page.free()


func test_a_drawing_whose_season_is_unstated_checks_nothing() -> void:
	var page: SeasonWindow = _page()
	page.set_document(DocumentScript.new())
	page.set_catalogue(_catalogue())
	assert(page.row_count() == 3, "every food crop is still listed")
	assert(page.summary_text().contains("3 cannot be checked"), page.summary_text())
	assert(page.hint() == PageScript.NOT_STATED_HINT, page.hint())
	page.free()


func test_a_list_with_no_food_says_so_rather_than_showing_an_empty_season() -> void:
	var page: SeasonWindow = _page()
	var document: DraftDocument = DocumentScript.new()
	document.set_season(LAST, FIRST)
	page.set_document(document)
	var shrubs_only: PlantCatalogue = CatalogueScript.make()
	shrubs_only.add(SpeciesScript.make(&"boxwood", "Buxus sempervirens", "Box", 60, 60, SpeciesScript.SHRUB))
	page.set_catalogue(shrubs_only)
	assert(page.row_count() == 0)
	assert(page.hint() == PageScript.NO_FOOD, page.hint())
	page.free()


func test_the_hint_is_guidance_rather_than_the_season_line_said_twice() -> void:
	var page: SeasonWindow = _page()
	var document: DraftDocument = DocumentScript.new()
	document.set_season(LAST, FIRST)
	page.set_document(document)
	page.set_catalogue(_catalogue())
	assert(page.hint() != page.season_line(), "the guidance is not the headline again")
	assert(not page.hint().contains("140 days"), page.hint())
	page.free()


# --- closing -----------------------------------------------------------------------------------


func test_closing_the_page_says_so_once() -> void:
	var page: SeasonWindow = _page()
	var closed: Array = []
	page.closed.connect(func() -> void: closed.append(1))
	page.request_close()
	assert(closed.size() == 1)
	assert(not page.visible)
	page.free()