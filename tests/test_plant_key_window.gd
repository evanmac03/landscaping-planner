extends Node
## The plant key's page (`res://scripts/plant_key_window.gd`), driven off-tree.
##
## The rules held here are the ones a page can get wrong by itself: which controls a person answers with,
## that the answers offered change with the answers given, that a button which cannot act is disabled
## rather than hidden and says on its tooltip what it is waiting for, and that a page with no plant list
## says so rather than showing nothing. Which question follows which answer is `test_plant_key.gd`'s
## arithmetic; this file only asks that the page shows what the key says and hands back what was pressed.
##
## The fixture is built here rather than loaded from the nursery list, so the key has one right answer to
## walk through. The page is built and shown off-tree - no `popup_centered`, which needs a screen - and
## every test frees the page it made, or the runner reports resources still in use.

const PageScript := preload("res://scripts/plant_key_window.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")
const CatalogueScript := preload("res://scripts/plant_catalogue.gd")
const ProfileScript := preload("res://scripts/terrain_profile.gd")

const SPRUCE := &"PICEA-ABIES"
const TREE_WORDS := "Tree"
## Enough of the conifer answer to find its button. Not "a conifer", which the other answer - "not a
## conifer - ordinary leaves" - also contains.
const NEEDLES := "needles"
const HERB_WORDS := "Herb"


func _plant(species_id: String, botanical: String, common: String, kind: int, height_cm: int) -> SpeciesScript:
	return SpeciesScript.make(StringName(species_id), botanical, common, height_cm, height_cm, kind)


## Five plants: two trees that only the conifer question separates, two herbs that nothing separates, and
## a grass. Enough for a question, an answer, a narrowing, and a pair the list cannot tell apart.
func _catalogue() -> CatalogueScript:
	var catalogue: CatalogueScript = CatalogueScript.make()
	var spruce: SpeciesScript = _plant("PICEA-ABIES", "Picea abies", "Norway spruce", SpeciesScript.TREE, 1500)
	spruce.sun = SpeciesScript.FULL_SUN
	spruce.water = SpeciesScript.WATER_MEDIUM
	assert(catalogue.add(spruce), "the spruce is a plant the catalogue takes")
	var maple: SpeciesScript = _plant("ACER-RUBRUM", "Acer rubrum", "Red maple", SpeciesScript.TREE, 1500)
	maple.sun = SpeciesScript.FULL_SUN | SpeciesScript.PART_SHADE
	maple.water = SpeciesScript.WATER_MEDIUM
	assert(catalogue.add(maple), "the maple is a plant the catalogue takes")
	var thyme: SpeciesScript = _plant("THYMUS-SERPYLLUM", "Thymus serpyllum", "Creeping thyme", SpeciesScript.HERB, 30)
	thyme.sun = SpeciesScript.FULL_SUN
	thyme.water = SpeciesScript.WATER_LOW
	thyme.edible_parts = SpeciesScript.EAT_LEAF
	assert(catalogue.add(thyme), "the thyme is a plant the catalogue takes")
	var marjoram: SpeciesScript = _plant("ORIGANUM-VULGARE", "Origanum vulgare", "Wild marjoram", SpeciesScript.HERB, 30)
	marjoram.sun = SpeciesScript.FULL_SUN
	marjoram.water = SpeciesScript.WATER_LOW
	marjoram.edible_parts = SpeciesScript.EAT_LEAF
	assert(catalogue.add(marjoram), "the marjoram is a plant the catalogue takes")
	var fescue: SpeciesScript = _plant("FESTUCA-GLAUCA", "Festuca glauca", "Blue fescue", SpeciesScript.GRASS, 40)
	fescue.sun = SpeciesScript.FULL_SUN
	fescue.water = SpeciesScript.WATER_LOW
	assert(catalogue.add(fescue), "the fescue is a plant the catalogue takes")
	return catalogue


## A page built, bound and shown, with nothing of the program's own touched.
func _page() -> PageScript:
	var page: PageScript = PageScript.new()
	page.build()
	page.visible = true
	page.bind(_catalogue())
	return page


## The index of the answer whose button says these words, so a test presses what a person reads rather
## than what happens to be first in the row.
func _answer_for(page: PageScript, words: String) -> int:
	for index: int in page.option_count():
		if page.option_words(index).contains(words):
			return index
	return -1


# --- leaving a question out ---------------------------------------------------------------


func test_not_sure_leaves_the_question_out_without_answering_it() -> void:
	# The button that is not one of the answers. Pressing it says nothing about the plant, so nothing is
	# narrowed; what changes is that the question is not asked again.
	var page: PageScript = _page()
	var before: int = int(page.the_state()["count"])
	var question: StringName = StringName(page.the_state()["question"])
	assert(question != &"", "the key opens with a question to leave out")
	assert(page.skip(), "leaving it out is offered while there is a question")
	assert(int(page.the_state()["count"]) == before, "and the field is not narrowed by a guess nobody made")
	assert(StringName(page.the_state()["question"]) != question, "the question left out is not asked again")
	assert(page.answers().has(question), "though it counts as answered")
	assert(page.status_text() != "", "and the page says what it did")
	page.free()


func test_not_sure_is_not_counted_as_one_of_the_answers() -> void:
	# Otherwise a person reading the row - or a test walking it - would find among the answers something that
	# identifies nothing, and the count on the last real answer would be off by one.
	var page: PageScript = _page()
	assert(page.option_count() > 0, "the page opens with a question's answers")
	for index: int in page.option_count():
		assert(
			page.option_words(index) != PageScript.NOT_SURE,
			"not sure is not one of the %d answers" % page.option_count(),
		)
	assert(page.the_button("NotSure") != null, "and it is there all the same")
	page.free()


func test_the_not_sure_button_is_gone_once_there_is_no_question_left() -> void:
	var page: PageScript = _page()
	while page.option_count() > 0:
		assert(page.choose(0), "an answer the page is offering can be taken")
	assert(page.option_count() == 0, "the key has stopped asking")
	assert(page.the_button("NotSure") == null, "so there is nothing left to leave out")
	page.free()


func test_saying_not_sure_with_nothing_to_leave_out_says_so() -> void:
	var page: PageScript = _page()
	while page.option_count() > 0:
		page.choose(0)
	assert(not page.skip(), "there is no question to leave out")
	assert(page.status_text() == PageScript.NOTHING_TO_LEAVE_OUT, "and the page says why rather than doing nothing")
	page.free()


# --- the drawings beside the answers ------------------------------------------------------


## Two trees that differ in nothing at all except how their veins run, so "how do the veins run?" is the one
## question worth asking - and it is the one leaf question that has been drawn.
func _two_veined() -> CatalogueScript:
	var catalogue: CatalogueScript = CatalogueScript.make()
	var beech: SpeciesScript = _plant("FAGUS-SYLVATICA", "Fagus sylvatica", "Beech", SpeciesScript.TREE, 1500)
	beech.sun = SpeciesScript.FULL_SUN
	beech.water = SpeciesScript.WATER_MEDIUM
	beech.leaf_venation = SpeciesScript.VEN_PINNATE
	assert(catalogue.add(beech), "the beech is a plant the catalogue takes")
	var maple: SpeciesScript = _plant("ACER-RUBRUM", "Acer rubrum", "Red maple", SpeciesScript.TREE, 1500)
	maple.sun = SpeciesScript.FULL_SUN
	maple.water = SpeciesScript.WATER_MEDIUM
	maple.leaf_venation = SpeciesScript.VEN_PALMATE
	assert(catalogue.add(maple), "the maple is a plant the catalogue takes")
	return catalogue


func test_an_answer_that_has_been_drawn_shows_the_drawing() -> void:
	# The two plants differ only in their veins, so the veins are what the key asks about - and its answers
	# are the ones that have pictures.
	var page: PageScript = PageScript.new()
	page.build()
	page.visible = true
	page.bind(_two_veined())
	assert(StringName(page.the_state()["question"]) == &"leaf_venation", "the key has come to the veins")
	assert(page.option_count() == 2, "and offers the two answers that are left")
	for index: int in page.option_count():
		assert(
			page.option_picture(index) != null,
			"the answer '%s' shows its drawing" % page.option_words(index),
		)
	page.free()


func test_an_answer_nobody_has_drawn_is_offered_with_its_words_alone() -> void:
	# The other half of the same rule, and the reason the key could be built before any drawing existed: a
	# button with no picture is built exactly like one with, and nothing is claimed for it.
	var page: PageScript = _page()
	assert(page.option_count() > 0, "the page opens with answers")
	for index: int in page.option_count():
		assert(page.option_picture(index) == null, "no drawing is shown where none has been made")
	page.free()


func test_the_page_builds_the_controls_a_person_answers_with() -> void:
	var page: PageScript = _page()
	for control_name: String in [
		"Heading",
		"Explanation",
		"Words",
		"Prompt",
		"Answers",
		"Matches",
		"TakeBack",
		"StartAgain",
		"UsePlant",
		"CloseButton",
	]:
		assert(page.find_child(control_name, true, false) != null, "the page has a %s" % control_name)
	page.free()


func test_the_first_question_is_what_kind_of_plant_it_is() -> void:
	var page: PageScript = _page()
	assert(
		page.prompt_text().contains("What kind of plant is it?"),
		"the prompt is the key's own question: %s" % page.prompt_text(),
	)
	assert(page.option_count() == 3, "three kinds are still possible here, not %d" % page.option_count())
	page.free()


func test_an_answer_button_says_how_many_plants_it_would_leave() -> void:
	var page: PageScript = _page()
	var trees: int = _answer_for(page, TREE_WORDS)
	assert(trees >= 0, "the kind question offers a tree")
	assert(
		page.option_words(trees).contains("2 plants"),
		"and the button says what it leaves: %s" % page.option_words(trees),
	)
	page.free()


func test_answering_moves_the_page_on_to_the_next_question() -> void:
	var page: PageScript = _page()
	assert(page.choose(_answer_for(page, TREE_WORDS)), "choosing one of the offered answers works")
	assert(page.answer_count() == 1, "one answer has been given")
	assert(page.prompt_text().contains("conifer"), "the conifer question is next: %s" % page.prompt_text())
	assert(page.option_count() == 2, "two answers, not the three kinds that are now gone")
	page.free()


func test_answering_the_kind_then_the_conifer_names_the_spruce() -> void:
	var page: PageScript = _page()
	page.choose(_answer_for(page, TREE_WORDS))
	page.choose(_answer_for(page, NEEDLES))
	assert(StringName(page.identified_id()) == SPRUCE, "the key has narrowed to the spruce")
	assert(page.words_text().contains("Norway spruce"), "and it says so: %s" % page.words_text())
	assert(page.option_count() == 0, "there is nothing left to ask about one plant")
	page.free()


func test_taking_the_last_answer_back_undoes_exactly_one_answer() -> void:
	var page: PageScript = _page()
	page.choose(_answer_for(page, TREE_WORDS))
	assert(page.answer_count() == 1)
	assert(page.take_back(), "there is an answer to take back")
	assert(page.answer_count() == 0, "and it is gone")
	assert(page.prompt_text().contains("What kind of plant is it?"), "the first question is back")
	assert(page.status_text().contains("Took back"), "and the page says which one went: %s" % page.status_text())
	assert(not page.take_back(), "there is nothing left to take back")
	assert(page.status_text().contains("nothing to take back"), "which the page says plainly")
	page.free()


func test_start_again_empties_the_key() -> void:
	var page: PageScript = _page()
	page.choose(_answer_for(page, TREE_WORDS))
	page.choose(_answer_for(page, NEEDLES))
	page.start_again()
	assert(page.answer_count() == 0, "every answer is gone, not just the last one")
	assert(page.prompt_text().contains("What kind of plant is it?"))
	assert(page.status_text().contains("Starting again"))
	page.free()


func test_binding_again_does_not_throw_the_answers_away() -> void:
	# A person who closed the key to go and look at the plant again carries on where they were, so
	# binding a list to a page that already has answers must not clear them.
	var page: PageScript = _page()
	page.choose(_answer_for(page, TREE_WORDS))
	page.bind(_catalogue())
	assert(page.answer_count() == 1, "the answer is still there")
	page.free()


func test_a_button_that_cannot_act_is_disabled_rather_than_hidden() -> void:
	var page: PageScript = _page()
	assert(page.the_button("TakeBack").disabled, "nothing has been answered, so nothing can be taken back")
	assert(page.the_button("StartAgain").disabled)
	assert(page.the_button("UsePlant").disabled, "no plant has been named yet")
	assert(page.the_button("TakeBack").tooltip_text.contains("nothing to take back"))
	page.choose(_answer_for(page, TREE_WORDS))
	assert(not page.the_button("TakeBack").disabled, "now there is something to take back")
	assert(page.the_button("UsePlant").disabled, "but two trees are still possible")
	page.free()


func test_use_this_plant_names_the_plant_and_puts_the_page_away() -> void:
	var page: PageScript = _page()
	var heard: Array[StringName] = []
	page.species_chosen.connect(
		func(species_id: StringName) -> void:
			heard.append(species_id),
	)
	var closed: Array[int] = [0]
	page.closed.connect(
		func() -> void:
			closed[0] += 1,
	)
	assert(not page.use_this_plant(), "nothing is named yet, so there is nothing to use")
	assert(
		page.status_text().contains("once the answers"),
		"and the page says why: %s" % page.status_text(),
	)
	page.choose(_answer_for(page, TREE_WORDS))
	page.choose(_answer_for(page, NEEDLES))
	assert(page.use_this_plant(), "one plant is left, so it can be used")
	assert(heard.size() == 1 and heard[0] == SPRUCE, "the page said which plant it is")
	assert(closed[0] == 1, "and it put itself away")
	assert(not page.visible, "the page is hidden")
	assert(page.answer_count() == 2, "and the answers are still there for the next opening")
	page.free()


func test_the_plants_the_list_cannot_separate_are_shown() -> void:
	var page: PageScript = _page()
	page.choose(_answer_for(page, HERB_WORDS))
	assert(page.words_text().contains("cannot tell"), "the key says so: %s" % page.words_text())
	assert(page.match_count() == 2, "and the page shows both plants")
	assert(page.option_count() == 0, "with nothing left to ask")
	page.free()


func test_a_page_with_no_list_says_so_rather_than_showing_nothing() -> void:
	var page: PageScript = PageScript.new()
	page.build()
	page.visible = true
	page.bind(null)
	assert(page.words_text().contains("no plant list"), "the page says what is missing: %s" % page.words_text())
	assert(page.option_count() == 0, "and offers nothing to answer")
	assert(page.prompt_text().is_empty(), "and asks nothing")
	page.free()


# --- the bed the plant is going in --------------------------------------------------------


## A bed in part shade, which of the fixture's five plants exactly one will take - the maple. The other four
## are all full-sun herbs and a grass, so the count and the narrowing have one right answer.
func _part_shade_bed() -> ProfileScript:
	return ProfileScript.make({ "sun": SpeciesScript.PART_SHADE, "moisture": SpeciesScript.WATER_MEDIUM })


func test_the_page_says_what_the_ground_is_like_where_the_plant_is_going() -> void:
	var page: PageScript = _page()
	page.suit_to({ "profile": _part_shade_bed(), "place": "the front bed" })
	assert(
		page.site_text().contains("1 of 5 plants suit the front bed"),
		"the page says what the bed leaves of the list: %s" % page.site_text(),
	)
	assert(not page.is_narrowed(), "and the key is not narrowed by itself")
	assert(page.field_count() == 5, "so every plant is still in it")
	assert(page.only_the_ones_that_suit(), "narrowing to the bed is offered")
	assert(page.is_narrowed(), "and the key is narrowed to it")
	assert(page.field_count() == 1, "to the one plant that suits it")
	assert(int(page.the_state()["count"]) == 1, "which is what the answers are narrowing now")
	assert(page.show_every_plant(), "and the way back is there")
	assert(not page.is_narrowed(), "which widens the key again")
	assert(page.field_count() == 5, "to the whole list")
	page.free()


func test_a_spot_nobody_has_described_offers_no_narrowing_and_says_where_to_state_it() -> void:
	var page: PageScript = _page()
	page.suit_to({ "profile": ProfileScript.make(), "place": "the bed" })
	assert(
		page.site_text().contains("Nothing says what the ground is like the bed"),
		"the page says what is missing: %s" % page.site_text(),
	)
	var button: Button = page.the_button("SuitHere")
	assert(button != null and button.disabled, "the narrowing is off rather than hidden")
	assert(button.tooltip_text.contains("Site menu"), "and says where the ground is stated: %s" % button.tooltip_text)
	assert(not page.only_the_ones_that_suit(), "pressing it anyway narrows nothing")
	assert(page.status_text().contains("Nothing says what the ground is like"), "and says so: %s" % page.status_text())
	assert(page.field_count() == 5, "with the whole list still in the key")
	page.free()


func test_the_way_back_is_off_until_the_key_has_been_narrowed() -> void:
	# A button that cannot act is disabled and says what it is waiting for, the same rule the three buttons
	# of state below follow - so nobody is left wondering whether the control they remember has gone.
	var page: PageScript = _page()
	page.suit_to({ "profile": _part_shade_bed(), "place": "the bed" })
	var back: Button = page.the_button("EveryPlant")
	assert(back != null and back.disabled, "there is nothing to widen back from yet")
	assert(not page.show_every_plant(), "and pressing it does nothing")
	assert(page.status_text() == PageScript.NOT_NARROWED, "and it says why: %s" % page.status_text())
	page.free()


func test_a_spot_nothing_suits_does_not_leave_an_empty_key() -> void:
	# The failure this holds off: narrowing a key to a spot nothing in the list suits would be a page with no
	# plants on it, which somebody would have to work out how to get out of.
	var page: PageScript = _page()
	page.suit_to({
		"profile": ProfileScript.make({ "sun": SpeciesScript.FULL_SHADE, "moisture": SpeciesScript.WATER_LOW }),
		"place": "the bed",
	})
	assert(not page.can_narrow(), "nothing in this list suits a dark, dry bed")
	assert(page.the_button("SuitHere").disabled, "so the narrowing is off rather than empty")
	assert(
		page.the_button("SuitHere").tooltip_text.contains("Nothing in the list suits this spot"),
		"and it says which fact stopped it: %s" % page.the_button("SuitHere").tooltip_text,
	)
	assert(page.field_count() == 5, "with the whole list still in the key")
	assert(not page.is_narrowed(), "and the key is not narrowed by a press that could not work")
	page.free()


# --- a shortlist somebody else made -------------------------------------------------------


func test_a_shortlist_narrows_the_key_and_says_where_it_came_from() -> void:
	# The photograph's half: a reading offers several plants and the key asks only the question that tells
	# them apart. The page takes **ids**, because what a model said into a species is `PlantIDResolver`'s
	# join and the page that holds the reading is where it is asked.
	var page: PageScript = _page()
	page.from_a_shortlist([SPRUCE, &"ACER-RUBRUM"], "photograph")
	assert(page.is_from_a_shortlist(), "the key is narrowing the shortlist")
	assert(page.field_count() == 2, "to the two plants the reading offered: %d" % page.field_count())
	assert(
		page.shortlist_text().contains("offered 2 plants"),
		"and the page says where they came from: %s" % page.shortlist_text(),
	)
	assert(not page.the_button("EveryPlant").disabled, "the way back is offered while a shortlist stands")
	assert(page.show_every_plant(), "and it widens the key")
	assert(page.field_count() == 5, "to every plant in the list")
	assert(not page.is_from_a_shortlist(), "with no shortlist left")
	page.free()


func test_a_shortlist_the_list_cannot_place_leaves_the_whole_key_usable() -> void:
	# A model naming something this catalogue does not stock is an ordinary thing to happen, and the answer
	# is a usable key plus a line saying so - never a key of no plants.
	var page: PageScript = _page()
	page.from_a_shortlist([&"NOT-IN-THE-LIST"], "photograph")
	assert(page.field_count() == 5, "every plant is still in the key: %d" % page.field_count())
	assert(
		page.shortlist_text().contains("Nothing the photograph offered is in the plant list"),
		"and the page says why: %s" % page.shortlist_text(),
	)
	assert(not page.is_from_a_shortlist(), "so there is no shortlist to widen back from")
	assert(page.the_button("EveryPlant").disabled, "and the way back is off rather than a button that does nothing")
	assert(not page.show_every_plant(), "pressing it anyway does nothing")
	page.free()