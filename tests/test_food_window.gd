extends Node
## The food-garden page: what will crop in a bed.
##
## The page is built and driven with no drawing and no screen, so every assertion here is about the
## text a designer would read: the bed's stated light, the crop's own facts, the verdict, and the list
## of what the bed would carry. The one thing checked over and over is that a question nobody answered
## comes back grey rather than green.

const FoodWindowScript := preload("res://scripts/food_window.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")
const ProfileScript := preload("res://scripts/terrain_profile.gd")
const CatalogueScript := preload("res://scripts/plant_catalogue.gd")
const CropSunScript := preload("res://scripts/crop_sun.gd")
const SunStudyScript := preload("res://scripts/vis/sun_study.gd")


func _crop(id: StringName, title: String, hours_tenths: int) -> PlantSpecies:
	var plant: PlantSpecies = SpeciesScript.make(id, "%s sp." % title, title, 150, 60, SpeciesScript.ANNUAL)
	plant.edible_parts = SpeciesScript.EAT_LEAF
	plant.family = SpeciesScript.BRASSICA
	plant.harvest_months = 0
	for month: int in [5, 6, 7, 8]:
		plant.set_harvests_in(month, true)
	plant.maturity_days = 55
	plant.sun_hours_tenths = hours_tenths
	return plant


func _catalogue() -> PlantCatalogue:
	var catalogue: PlantCatalogue = CatalogueScript.make()
	catalogue.add(_crop(&"kale", "Kale", 60))
	catalogue.add(_crop(&"lettuce", "Lettuce", 40))
	var boxwood: PlantSpecies = SpeciesScript.make(&"buxus", "Buxus sempervirens", "Boxwood", 200, 150)
	catalogue.add(boxwood)
	return catalogue


func _places() -> Array:
	return [
		{"name": "South bed", "profile": ProfileScript.of("sun", SpeciesScript.FULL_SUN)},
		{"name": "North bed", "profile": ProfileScript.of("sun", SpeciesScript.FULL_SHADE)},
		{"name": "the rest of the site", "profile": ProfileScript.make()},
	]


func _site() -> Dictionary:
	return SunStudyScript.site(45.4, -75.7, -5.0)


## A page, built, with a plant list, three beds and a site - and freed by the caller.
func _page() -> FoodWindow:
	var page: FoodWindow = FoodWindowScript.new()
	page.build()
	page.bind(_catalogue(), _places(), _site())
	return page


# --- building -------------------------------------------------------------------------------


func test_the_page_builds_its_controls_and_takes_no_keyboard() -> void:
	var page: FoodWindow = FoodWindowScript.new()
	page.build()
	assert(page.get_node_or_null("Column/PlaceRow/Place") is OptionButton, "a bed to choose")
	assert(page.get_node_or_null("Column/CropRow/Crop") is OptionButton, "a crop to choose")
	assert(page.get_node_or_null("Column/Crops") is ItemList, "and the list of what would crop")
	assert(page.lists_are_keyboard_free(), "a list a person reads is no place to type")
	assert(page.get_node_or_null("Column/Buttons/CloseButton") is Button, "and a way out")
	page.free()


func test_a_page_with_nothing_bound_reports_what_it_is_missing() -> void:
	var page: FoodWindow = FoodWindowScript.new()
	page.bind(null, [], {})
	assert(page.hint() == FoodWindowScript.NO_CROPS, page.hint())
	assert(page.place_line() == FoodWindowScript.NO_PLACES, page.place_line())
	assert(page.season_line() == FoodWindowScript.NO_SITE, page.season_line())
	assert(page.row_count() == 0, "and there is nothing to list")
	page.free()


# --- the check, as the page shows it ---------------------------------------------------------


func test_the_page_checks_the_chosen_crop_in_the_chosen_bed() -> void:
	var page: FoodWindow = _page()
	assert(page.place_count() == 3, "three beds came in: %d" % page.place_count())
	assert(page.selected_crop() != null, "and a crop is in hand without anyone choosing one")
	assert(page.choose_crop(&"kale"), "kale is in the list")
	assert(page.selected_crop().id == &"kale")
	assert(page.choose_place(0), "the south bed")
	assert(String(page.selected_place()["name"]) == "South bed")
	# Six hours wanted, full sun: it crops, and the verdict is the check's own words.
	assert(int(page.verdict()["verdict"]) == CropSunScript.GOOD, page.verdict_line())
	assert(page.verdict_line().contains("Kale"), page.verdict_line())
	assert(page.crop_line().contains("harvest"), page.crop_line())
	assert(page.place_line().begins_with("South bed:"), page.place_line())
	assert(page.season_line().contains("longest day"), page.season_line())
	page.free()


func test_the_same_crop_in_a_shaded_bed_is_refused_and_the_words_say_why() -> void:
	var page: FoodWindow = _page()
	page.choose_crop(&"kale")
	page.choose_place(1)
	assert(String(page.selected_place()["name"]) == "North bed")
	assert(int(page.verdict()["verdict"]) == CropSunScript.UNSUITABLE, page.verdict_line())
	assert(page.verdict_line().contains("will not crop"), page.verdict_line())
	page.free()


func test_a_bed_nobody_described_is_unknown_never_green() -> void:
	var page: FoodWindow = _page()
	page.choose_crop(&"kale")
	page.choose_place(2)
	assert(int(page.verdict()["verdict"]) == CropSunScript.UNKNOWN, page.verdict_line())
	assert(page.verdict_line().contains("cannot be checked"), page.verdict_line())
	assert(page.get_node("Column/Verdict").text == page.verdict_line(), "and the page shows it")
	page.free()


func test_the_list_is_food_only_best_first() -> void:
	var page: FoodWindow = _page()
	page.choose_place(0)
	var texts: Array[String] = page.row_texts()
	assert(texts.size() == 2, "the boxwood is not a crop: %d" % texts.size())
	assert(not str(texts).contains("Boxwood"), str(texts))
	assert(page.row_count() == 2, "and the count matches the lines")
	assert(page.get_node("Column/Crops").item_count == 2, "the list shows them too")
	page.free()


func test_the_page_says_what_the_bed_would_carry() -> void:
	var page: FoodWindow = _page()
	page.choose_place(0)
	assert(page.summary_text().begins_with("2 crops:"), page.summary_text())
	# In full shade both are refused, and the sentence says so.
	page.choose_place(1)
	assert(page.summary_text().contains("will not"), page.summary_text())
	page.free()


# --- what it does ------------------------------------------------------------------------------


func test_choosing_a_crop_says_so_and_closing_emits() -> void:
	var page: FoodWindow = _page()
	var closed: Array = []
	page.closed.connect(func() -> void: closed.append(true))
	assert(page.choose_crop(&"lettuce"))
	page._on_crop_selected(page.get_node("Column/CropRow/Crop").selected)
	assert(page.said().contains("Lettuce"), page.said())
	page.request_close()
	assert(closed.size() == 1, "the page announced its own closing")
	assert(not page.visible, "and it put itself away")
	page.free()


func test_choosing_a_crop_that_is_not_there_is_refused_rather_than_guessed() -> void:
	var page: FoodWindow = _page()
	assert(not page.choose_crop(&"parsnip"), "a crop the list does not have")
	assert(not page.choose_place(9), "and a bed that is not there")
	page.free()


func test_the_hint_is_guidance_rather_than_the_verdict_said_twice() -> void:
	var page: FoodWindow = _page()
	page.choose_crop(&"kale")
	page.choose_place(0)
	assert(page.hint() != page.verdict_line(), "the page does not say one sentence on two lines")
	assert(page.hint().contains("ask again"), page.hint())
	page.choose_place(1)
	assert(page.hint().contains("another bed"), page.hint())
	page.choose_place(2)
	assert(page.hint().contains("state this bed"), page.hint())
	page.free()