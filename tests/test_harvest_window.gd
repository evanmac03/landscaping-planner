extends Node
## The harvest calendar page: what is ready in a chosen month, and the shape of the year.
##
## The page is built and driven with no drawing and no screen, so every assertion here is about the text
## a person would read: the crops ready in a month, what of each crop is cut, and how the year reads.
## The two things checked over and over are that the page opens on the fullest month rather than on a
## blank January, and that an empty month says so rather than reading as a fault.

const HarvestWindowScript := preload("res://scripts/harvest_window.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")
const CatalogueScript := preload("res://scripts/plant_catalogue.gd")
const CalendarScript := preload("res://scripts/harvest_calendar.gd")


## A crop cut in the months given (1..12). No common name, so `display_name` is the plain name.
func _crop(id: StringName, title: String, months: Array, parts: int) -> PlantSpecies:
	var plant: PlantSpecies = SpeciesScript.make(id, title, "", 60, 40, SpeciesScript.ANNUAL)
	plant.edible_parts = parts
	for month: int in months:
		plant.set_harvests_in(month, true)
	return plant


func _catalogue() -> PlantCatalogue:
	var catalogue: PlantCatalogue = CatalogueScript.make()
	catalogue.add(_crop(&"basil", "Basil", [6, 7], SpeciesScript.EAT_LEAF))    # June-July
	catalogue.add(_crop(&"beet", "Beetroot", [6], SpeciesScript.EAT_ROOT))     # June only
	catalogue.add(_crop(&"kale", "Kale", [11, 12, 1, 2, 3], SpeciesScript.EAT_LEAF))  # Nov-March
	catalogue.add(_crop(&"mint", "Mint", [], SpeciesScript.EAT_LEAF))          # edible, no window
	var boxwood: PlantSpecies = SpeciesScript.make(&"buxus", "Buxus sempervirens", "Boxwood", 200, 150)
	catalogue.add(boxwood)
	return catalogue


## A page, built and bound to the test list - and freed by the caller.
func _page() -> HarvestWindow:
	var page: HarvestWindow = HarvestWindowScript.new()
	page.build()
	page.bind(_catalogue())
	return page


# --- building -------------------------------------------------------------------------------


func test_the_page_builds_its_controls_and_takes_no_keyboard() -> void:
	var page: HarvestWindow = HarvestWindowScript.new()
	page.build()
	assert(page.get_node_or_null("Column/MonthRow/Month") is OptionButton, "a month to choose")
	assert(page.get_node_or_null("Column/Crops") is ItemList, "and the list of what is ready")
	assert(page.lists_are_keyboard_free(), "a list a person reads is no place to type")
	assert(page.get_node_or_null("Column/Buttons/CloseButton") is Button, "and a way out")
	page.free()


func test_the_month_dropdown_offers_the_twelve_months() -> void:
	var page: HarvestWindow = _page()
	var option: OptionButton = page.get_node("Column/MonthRow/Month")
	assert(option.item_count == 12, "a year: %d" % option.item_count)
	assert(option.get_item_text(0) == "January", option.get_item_text(0))
	assert(option.get_item_text(11) == "December", option.get_item_text(11))
	assert(int(option.get_item_metadata(0)) == 1, "the metadata is the month number")
	assert(int(option.get_item_metadata(11)) == 12)
	page.free()


func test_a_page_with_nothing_bound_reports_what_it_is_missing() -> void:
	var page: HarvestWindow = HarvestWindowScript.new()
	page.bind(null)
	assert(page.hint() == HarvestWindowScript.NO_CROPS, page.hint())
	assert(page.month_line() == HarvestWindowScript.NO_CROPS, page.month_line())
	assert(page.row_count() == 0, "and there is nothing to list")
	page.free()


func test_the_page_opens_on_the_fullest_month() -> void:
	# June holds basil and beetroot, more than any other month, so the page opens there rather than on a
	# blank January.
	var page: HarvestWindow = _page()
	assert(page.month() == 6, "June is the fullest: %d" % page.month())
	assert(page.month_name() == "June", page.month_name())
	page.free()


# --- the month, as the page shows it ---------------------------------------------------------


func test_choosing_a_month_shows_what_is_ready_then() -> void:
	var page: HarvestWindow = _page()
	assert(page.choose_month(6))
	assert(page.row_count() == 2, "basil and beetroot: %d" % page.row_count())
	assert(page.month_line().contains("2 crops ready in June"), page.month_line())
	assert(page.choose_month(1), "and the winter crop is ready in the new year")
	assert(page.row_count() == 1, "just the kale: %d" % page.row_count())
	assert(page.row_texts()[0].begins_with("Kale"), page.row_texts()[0])
	page.free()


func test_an_empty_month_says_so_rather_than_failing() -> void:
	var page: HarvestWindow = _page()
	assert(page.choose_month(4))
	assert(page.row_count() == 0, "nothing is ready in April")
	assert(
		page.month_line() == "nothing is recorded as ready in April.",
		page.month_line()
	)
	assert(page.get_node("Column/MonthLine").text == page.month_line(), "and the page shows it")
	page.free()


func test_the_list_shows_what_of_the_crop_is_cut() -> void:
	var page: HarvestWindow = _page()
	page.choose_month(6)
	var texts: Array[String] = page.row_texts()
	assert(texts[0] == "Basil: leaf", texts[0])
	assert(texts[1] == "Beetroot: root", texts[1])
	assert(not str(texts).contains("Boxwood"), "a boxwood is never a harvest: %s" % str(texts))
	assert(page.get_node("Column/Crops").item_count == 2, "the list shows them too")
	page.free()


func test_the_year_line_and_the_unstated_line_say_the_shape_of_the_list() -> void:
	var page: HarvestWindow = _page()
	var year: String = page.year_line()
	assert(year.contains("3 crops"), year)
	assert(year.contains("June-July"), year)
	assert(year.contains("November-March"), year)
	var missing: String = page.unstated_line()
	assert(missing.begins_with("1 crop says nothing"), missing)
	assert(missing.contains("Mint"), missing)
	assert(page.get_node("Column/Year").text == year, "the page shows the year's shape")
	page.free()


func test_choosing_what_is_not_a_month_is_refused_rather_than_guessed() -> void:
	var page: HarvestWindow = _page()
	var before: int = page.month()
	assert(not page.choose_month(0), "nought is not a month")
	assert(not page.choose_month(13), "nor is thirteen")
	assert(page.month() == before, "so the month in hand did not move")
	page.free()


# --- what it does ------------------------------------------------------------------------------


func test_choosing_a_month_says_so_and_closing_emits() -> void:
	var page: HarvestWindow = _page()
	var closed: Array = []
	page.closed.connect(func() -> void: closed.append(true))
	var option: OptionButton = page.get_node("Column/MonthRow/Month")
	page._on_month_selected(0)
	assert(page.month() == 1, "the choice was taken")
	assert(page.said().contains("January"), page.said())
	assert(page.said().contains("ready"), page.said())
	page.request_close()
	assert(closed.size() == 1, "the page announced its own closing")
	assert(not page.visible, "and it put itself away")
	page.free()


func test_the_hint_is_guidance_rather_than_the_headline_said_twice() -> void:
	var page: HarvestWindow = _page()
	page.choose_month(6)
	assert(page.hint() != page.month_line(), "the page does not say one sentence on two lines")
	assert(page.hint().contains("another month"), page.hint())
	page.choose_month(4)
	assert(page.hint().contains("nothing is ready this month"), page.hint())
	page.free()