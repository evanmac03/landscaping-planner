extends Node
## The rotation page: what should follow in a bed, and what grows well beside.
##
## The page is built and driven with no drawing and no screen, so every assertion here is about the
## text a designer would read: the bed's stated history, the crop's own family, the verdict, and the
## list of what would follow. The two things checked over and over are that a bed whose history nobody
## has stated comes back grey rather than green, and that the history is kept per bed.

const RotationWindowScript := preload("res://scripts/rotation_window.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")
const CatalogueScript := preload("res://scripts/plant_catalogue.gd")
const CropRotationScript := preload("res://scripts/crop_rotation.gd")


func _crop(id: StringName, title: String, family: StringName) -> PlantSpecies:
	var plant: PlantSpecies = SpeciesScript.make(id, "%s sp." % title, title, 150, 60, SpeciesScript.ANNUAL)
	plant.edible_parts = SpeciesScript.EAT_LEAF
	plant.family = family
	return plant


func _catalogue() -> PlantCatalogue:
	var catalogue: PlantCatalogue = CatalogueScript.make()
	catalogue.add(_crop(&"kale", "Kale", CropRotationScript.BRASSICA))
	catalogue.add(_crop(&"bean", "Bean", CropRotationScript.LEGUME))
	catalogue.add(_crop(&"mystery", "Mystery green", CropRotationScript.FAMILY_NONE))
	var boxwood: PlantSpecies = SpeciesScript.make(&"buxus", "Buxus sempervirens", "Boxwood", 200, 150)
	catalogue.add(boxwood)
	return catalogue


func _places() -> Array:
	return [{"name": "South bed"}, {"name": "North bed"}]


## A page, built, with a plant list and two beds - and freed by the caller.
func _page() -> RotationWindow:
	var page: RotationWindow = RotationWindowScript.new()
	page.build()
	page.bind(_catalogue(), _places())
	return page


# --- building -------------------------------------------------------------------------------


func test_the_page_builds_its_controls_and_takes_no_keyboard() -> void:
	var page: RotationWindow = RotationWindowScript.new()
	page.build()
	assert(page.get_node_or_null("Column/PlaceRow/Place") is OptionButton, "a bed to choose")
	assert(page.get_node_or_null("Column/TurnRow/Turn") is OptionButton, "what grew here last")
	assert(page.get_node_or_null("Column/CropRow/Crop") is OptionButton, "a crop to try")
	assert(page.get_node_or_null("Column/Crops") is ItemList, "and the list of what would follow")
	assert(page.lists_are_keyboard_free(), "a list a person reads is no place to type")
	assert(page.get_node_or_null("Column/Buttons/CloseButton") is Button, "and a way out")
	page.free()


func test_the_history_dropdown_offers_nine_families_and_not_stated() -> void:
	var page: RotationWindow = _page()
	var turn: OptionButton = page.get_node("Column/TurnRow/Turn")
	assert(turn.item_count == 10, "not stated, then the nine families: %d" % turn.item_count)
	assert(turn.get_item_text(0) == RotationWindowScript.NOT_STATED, turn.get_item_text(0))
	assert(StringName(turn.get_item_metadata(0)) == &"", "and it stands for no family")
	assert(StringName(turn.get_item_metadata(turn.item_count - 1)) == CropRotationScript.HERB_FAMILY)
	page.free()


func test_a_page_with_nothing_bound_reports_what_it_is_missing() -> void:
	var page: RotationWindow = RotationWindowScript.new()
	page.bind(null, [])
	assert(page.hint() == RotationWindowScript.NO_CROPS, page.hint())
	assert(page.place_line() == RotationWindowScript.NO_PLACES, page.place_line())
	assert(page.row_count() == 0, "and there is nothing to list")
	page.free()


# --- the check, as the page shows it ---------------------------------------------------------


func test_the_page_checks_the_chosen_crop_against_the_beds_history() -> void:
	var page: RotationWindow = _page()
	assert(page.place_count() == 2, "two beds came in: %d" % page.place_count())
	assert(page.selected_crop() != null, "and a crop is in hand without anyone choosing one")
	assert(page.previous_family() == CropRotationScript.FAMILY_NONE, "with no history stated yet")
	assert(page.choose_previous_family(CropRotationScript.BRASSICA), "a brassica grew here last")
	assert(StringName(page.previous_family()) == CropRotationScript.BRASSICA)
	assert(page.place_line().contains("brassica"), page.place_line())
	assert(page.choose_crop(&"kale"), "kale is a brassica, so it will not follow itself")
	assert(int(page.verdict()["verdict"]) == CropRotationScript.UNSUITABLE, page.turn_line())
	assert(page.turn_line().contains("should not go"), page.turn_line())
	assert(page.choose_crop(&"bean"), "a bean after a brassica is a fresh start")
	assert(int(page.verdict()["verdict"]) == CropRotationScript.GOOD, page.turn_line())
	assert(page.turn_line().contains("follows on well"), page.turn_line())
	page.free()


func test_a_bed_whose_history_is_unstated_is_unknown_never_green() -> void:
	var page: RotationWindow = _page()
	page.choose_place(1)
	page.choose_crop(&"kale")
	assert(int(page.verdict()["verdict"]) == CropRotationScript.UNKNOWN, page.turn_line())
	assert(page.turn_line().contains("cannot be rotated"), page.turn_line())
	assert(page.get_node("Column/Verdict").text == page.turn_line(), "and the page shows it")
	page.free()


func test_the_list_is_food_only_best_first() -> void:
	var page: RotationWindow = _page()
	page.choose_previous_family(CropRotationScript.BRASSICA)
	var texts: Array[String] = page.row_texts()
	assert(texts.size() == 3, "the boxwood is not a crop: %d" % texts.size())
	assert(not str(texts).contains("Boxwood"), str(texts))
	assert(texts[0].contains("follows on well") or texts[0].contains("fresh family"), texts[0])
	assert(page.row_count() == 3, "and the count matches the lines")
	assert(page.get_node("Column/Crops").item_count == 3, "the list shows them too")
	page.free()


func test_the_page_says_what_the_bed_would_carry() -> void:
	var page: RotationWindow = _page()
	page.choose_previous_family(CropRotationScript.BRASSICA)
	assert(page.summary_text().begins_with("3 crops:"), page.summary_text())
	assert(page.summary_text().contains("should not"), page.summary_text())
	page.free()


# --- the history is per bed ------------------------------------------------------------------


func test_the_history_is_kept_for_the_bed_it_was_stated_for() -> void:
	var page: RotationWindow = _page()
	assert(page.choose_place(0))
	assert(page.choose_previous_family(CropRotationScript.LEGUME))
	assert(page.choose_place(1), "the other bed has its own history")
	assert(page.previous_family() == CropRotationScript.FAMILY_NONE, "which is not the first bed's")
	assert(page.choose_place(0))
	assert(StringName(page.previous_family()) == CropRotationScript.LEGUME, "and the first bed remembers")
	# The dropdown follows the bed, so showing a stored history is not a request to change it.
	var turn: OptionButton = page.get_node("Column/TurnRow/Turn")
	assert(StringName(turn.get_item_metadata(turn.selected)) == CropRotationScript.LEGUME)
	page.free()


# --- what it does ------------------------------------------------------------------------------


func test_the_companion_line_is_the_crops_own_knowledge() -> void:
	var page: RotationWindow = _page()
	assert(page.choose_crop(&"bean"))
	assert(page.company_line().contains("grows well beside"), page.company_line())
	assert(page.company_line().contains("kept from allium"), page.company_line())
	assert(page.choose_crop(&"mystery"))
	assert(
		page.company_line().contains("nothing is stated"),
		"a plant with no family has no companions: %s" % page.company_line()
	)
	page.free()


func test_choosing_a_crop_says_so_and_closing_emits() -> void:
	var page: RotationWindow = _page()
	var closed: Array = []
	page.closed.connect(func() -> void: closed.append(true))
	assert(page.choose_crop(&"bean"))
	page._on_crop_selected(page.get_node("Column/CropRow/Crop").selected)
	assert(page.said().contains("Bean"), page.said())
	page.request_close()
	assert(closed.size() == 1, "the page announced its own closing")
	assert(not page.visible, "and it put itself away")
	page.free()


func test_choosing_what_is_not_there_is_refused_rather_than_guessed() -> void:
	var page: RotationWindow = _page()
	assert(not page.choose_crop(&"parsnip"), "a crop the list does not have")
	assert(not page.choose_place(9), "a bed that is not there")
	assert(not page.choose_previous_family(&"PUMPKIN"), "and a word that is not a family")
	assert(page.previous_family() == CropRotationScript.FAMILY_NONE, "so nothing was stated")
	page.free()


func test_stating_the_history_through_the_dropdown_announces_it() -> void:
	var page: RotationWindow = _page()
	var turn: OptionButton = page.get_node("Column/TurnRow/Turn")
	var index: int = 0
	for candidate in turn.item_count:
		if StringName(turn.get_item_metadata(candidate)) == CropRotationScript.BRASSICA:
			index = candidate
	page._on_turn_selected(index)
	assert(StringName(page.previous_family()) == CropRotationScript.BRASSICA, "the choice was taken")
	assert(page.said().contains("brassica"), page.said())
	assert(page.said().contains("South bed"), page.said())
	page.free()


func test_the_hint_is_guidance_rather_than_the_verdict_said_twice() -> void:
	var page: RotationWindow = _page()
	page.choose_previous_family(CropRotationScript.BRASSICA)
	page.choose_crop(&"kale")
	assert(page.hint() != page.turn_line(), "the page does not say one sentence on two lines")
	assert(page.hint().contains("another crop"), page.hint())
	page.choose_crop(&"bean")
	assert(page.hint().contains("compare"), page.hint())
	page.choose_place(1)
	assert(page.hint().contains("state what grew"), page.hint())
	page.free()