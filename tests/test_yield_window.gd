extends Node
## The yield page: how many plants feed a household, read off the plant list.
##
## The page is built and driven off-tree, so no `_ready` runs and no window is ever shown:
## `popup_centered` needs a screen and a test does not have one.

const PageScript := preload("res://scripts/yield_window.gd")
const YieldScript := preload("res://scripts/plant_yield.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")
const CatalogueScript := preload("res://scripts/plant_catalogue.gd")


func _crop(species_id: StringName, name: String, gives: int, eats: int) -> PlantSpecies:
	var crop: PlantSpecies = SpeciesScript.make(species_id, name, "", 40, 30, SpeciesScript.ANNUAL)
	crop.edible_parts = SpeciesScript.EAT_LEAF
	crop.yield_per_plant_g = gives
	crop.need_per_person_g = eats
	return crop


func _catalogue() -> PlantCatalogue:
	var catalogue: PlantCatalogue = CatalogueScript.make()
	catalogue.add(_crop(&"tomato", "Tomato", 2000, 5000))
	catalogue.add(_crop(&"herb", "Herb", 100, 100))
	catalogue.add(_crop(&"thyme", "Thyme", 0, 300))
	catalogue.add(_crop(&"sorrel", "Sorrel", 3000, 0))
	catalogue.add(SpeciesScript.make(&"boxwood", "Buxus sempervirens", "Box", 60, 60, SpeciesScript.SHRUB))
	return catalogue


func _page() -> YieldWindow:
	var page: YieldWindow = PageScript.new()
	page.build()
	return page


# --- the controls ---------------------------------------------------------------------------


func test_the_page_builds_its_controls_and_takes_no_keyboard() -> void:
	var page: YieldWindow = _page()
	assert(page.get_node_or_null(^"Column/PeopleRow/PeopleBox") != null, "there is a field for the people")
	assert(page.get_node_or_null(^"Column/SpareRow/SpareBox") != null, "and one for the spare")
	assert(page.get_node_or_null(^"Column/Crops") != null, "and a list for the crops")
	assert(page.lists_are_keyboard_free(), "the crop list does not take the keyboard from the drawing")
	assert(not page.visible, "and a page nobody asked for is not on screen")
	page.free()


func test_a_page_with_no_list_says_so_rather_than_failing() -> void:
	var page: YieldWindow = _page()
	assert(page.row_count() == 0)
	assert(page.feed_line() == PageScript.NO_CROPS, page.feed_line())
	assert(page.hint() == PageScript.NO_CROPS, page.hint())
	page.free()


# --- binding ------------------------------------------------------------------------------


func test_binding_hands_over_the_list_and_opens_on_a_household() -> void:
	var page: YieldWindow = _page()
	page.bind(_catalogue())
	assert(page.people() == YieldScript.DEFAULT_PEOPLE, "%d" % page.people())
	assert(page.spare() == YieldScript.DEFAULT_SPARE, "%d" % page.spare())
	assert(page.row_count() == 4, "the boxwood is not a crop: %d" % page.row_count())
	page.free()


# --- what the plan comes to ------------------------------------------------------------------


func test_the_lines_say_the_plants_or_the_fact_that_is_missing() -> void:
	var page: YieldWindow = _page()
	page.bind(_catalogue())
	page.set_spare(0)
	var texts: Array[String] = page.row_texts()
	assert(texts.size() == 4)
	assert(texts[0] == "Herb: plant 4", texts[0])
	var sandy := false
	for text: String in texts:
		if text.begins_with("Thyme:"):
			sandy = text == "Thyme: %s" % YieldScript.NO_YIELD
	assert(sandy, "a crop with no yield says which fact is missing: %s" % str(texts))
	page.free()


func test_moving_the_people_moves_the_number() -> void:
	var page: YieldWindow = _page()
	page.bind(_catalogue())
	page.set_spare(0)
	assert(page.feed_line().contains("about 14 plants"), page.feed_line())
	page.set_people(2)
	assert(page.feed_line().contains("To feed 2 people"), page.feed_line())
	assert(page.feed_line().contains("about 7 plants"), page.feed_line())
	page.free()


func test_the_spare_moves_the_number_too() -> void:
	var page: YieldWindow = _page()
	page.bind(_catalogue())
	page.set_spare(0)
	assert(page.feed_line().contains("with no spare"), page.feed_line())
	page.set_spare(100)
	assert(page.feed_line().contains("about 28 plants"), page.feed_line())
	assert(page.feed_line().contains("100% spare"), page.feed_line())
	page.free()


func test_the_feed_line_reads_as_a_sentence_and_the_summary_counts_the_list() -> void:
	var page: YieldWindow = _page()
	page.bind(_catalogue())
	assert(page.feed_line().begins_with("To feed"), page.feed_line())
	assert(page.summary_text() == "4 crops: 2 can be worked out, 2 cannot be told.", page.summary_text())
	page.free()


func test_a_list_where_nothing_can_be_worked_out_says_so() -> void:
	var page: YieldWindow = _page()
	var only_thyme: PlantCatalogue = CatalogueScript.make()
	only_thyme.add(_crop(&"thyme", "Thyme", 0, 300))
	page.bind(only_thyme)
	assert(page.hint() == PageScript.NO_FACTS, page.hint())
	assert(
		page.feed_line() == "nothing on this list can be worked out into a number of plants",
		page.feed_line()
	)
	page.free()


func test_the_hint_is_guidance_rather_than_the_feed_line_said_twice() -> void:
	var page: YieldWindow = _page()
	page.bind(_catalogue())
	assert(page.hint() != page.feed_line(), "the guidance is not the headline again")
	assert(not page.hint().contains("To feed"), page.hint())
	page.free()


# --- the hand-off to a nursery order --------------------------------------------------------


func test_the_page_builds_an_order_button_that_takes_no_keyboard() -> void:
	var page: YieldWindow = _page()
	var button: Button = page.get_node_or_null(^"Column/Buttons/OrderButton")
	assert(button != null, "there is a button to hand the count to a nursery order")
	assert(button.focus_mode == Control.FOCUS_NONE, "and it does not take the drawing's keyboard")
	assert(page.order_words() == PageScript.ORDER_BUTTON, page.order_words())
	page.free()


func test_the_order_button_is_dead_while_nothing_can_be_worked_out() -> void:
	var page: YieldWindow = _page()
	var only_thyme: PlantCatalogue = CatalogueScript.make()
	only_thyme.add(_crop(&"thyme", "Thyme", 0, 300))
	page.bind(only_thyme)
	assert(not page.order_enabled(), "nothing can be worked out, so there is nothing to order")
	assert(page.order_rows().is_empty(), "and no rows to hand over")
	page.free()


func test_pressing_it_hands_over_a_row_per_crop_that_worked_out() -> void:
	var page: YieldWindow = _page()
	page.bind(_catalogue())
	var handed: Array = []
	page.order_requested.connect(func(rows: Array) -> void: handed.append(rows))
	assert(page.order_enabled(), "some crops worked out, so there is an order to write")
	page._on_order()
	assert(handed.size() == 1, "it handed the rows over once")
	var rows: Array = handed[0]
	assert(rows.size() == 2, "one row per crop that worked out: %d" % rows.size())
	assert(rows[0].has("count") and rows[0].has("botanical_name"),
		"in the shape the nursery order prices")
	page.free()


# --- closing -------------------------------------------------------------------------------


func test_closing_the_page_says_so_once() -> void:
	var page: YieldWindow = _page()
	var closed: Array = []
	page.closed.connect(func() -> void: closed.append(1))
	page.request_close()
	assert(closed.size() == 1)
	assert(not page.visible)
	page.free()