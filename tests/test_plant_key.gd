extends Node
## The plant key (`res://scripts/plant_key.gd`): naming a plant by answering questions about it.
##
## What is held here is the arithmetic and the wording rather than a page: which question the key asks
## next, which plants an answer leaves, and what it says when one plant is left, when several cannot be
## told apart, and when an answer fits nothing at all. The kinds, the light levels and the conifer rule
## are `PlantSpecies`' own and are held by `test_plants.gd`; this file only asks that the key hands them
## to the one filter rather than reading the same fields a second time.
##
## The fixture is a small garden built here rather than the shipped list, so the questions have one right
## answer: how much a question tells depends on which plants there are, and a key measured against four
## thousand nursery entries would be measured against a number nobody can check. The two files are
## preloaded by path, because a `class_name` is only visible once the editor has picked the file up.

const SpeciesScript := preload("res://scripts/plant_species.gd")
const CatalogueScript := preload("res://scripts/plant_catalogue.gd")
const KeyScript := preload("res://scripts/plant_key.gd")


# --- the fixture -------------------------------------------------------------------------


## One plant, with the size it grows to. A spread equal to the height is fine: nothing here asks about
## the spread, and a plant with no size at all is one the catalogue refuses.
func _plant(species_id: String, botanical: String, common: String, kind: int, height_cm: int) -> SpeciesScript:
	return SpeciesScript.make(StringName(species_id), botanical, common, height_cm, height_cm, kind)


func _add(catalogue: CatalogueScript, plant: SpeciesScript) -> SpeciesScript:
	assert(catalogue.add(plant), "the fixture's %s is a plant the catalogue takes" % plant.id)
	return plant


## A garden of eight: both sides of every question, and the conifer the kind question cannot reach on its
## own - a spruce is a tree and so is a maple.
##
## The three edibles are herbs, an annual and a shrub, so the food question cuts across the kind question
## rather than repeating it, and the two shrubs are told apart by their light.
func _catalogue() -> CatalogueScript:
	var catalogue: CatalogueScript = CatalogueScript.make()

	var maple: SpeciesScript = _plant("ACER-RUBRUM", "Acer rubrum", "Red maple", SpeciesScript.TREE, 1500)
	maple.sun = SpeciesScript.FULL_SUN | SpeciesScript.PART_SHADE
	maple.water = SpeciesScript.WATER_MEDIUM
	_add(catalogue, maple)

	var spruce: SpeciesScript = _plant("PICEA-ABIES", "Picea abies", "Norway spruce", SpeciesScript.TREE, 1500)
	spruce.sun = SpeciesScript.FULL_SUN | SpeciesScript.PART_SHADE
	spruce.water = SpeciesScript.WATER_MEDIUM
	_add(catalogue, spruce)

	# Tagged "evergreen", which is a nursery's word and not a botanical one: a boxwood is a broadleaf,
	# so the conifer question must not sweep it in with the spruce.
	var boxwood: SpeciesScript = _plant(
		"BUXUS-SEMPERVIRENS",
		"Buxus sempervirens",
		"Common box",
		SpeciesScript.SHRUB,
		120,
	)
	boxwood.sun = SpeciesScript.PART_SHADE | SpeciesScript.FULL_SHADE
	boxwood.water = SpeciesScript.WATER_MEDIUM
	boxwood.tags = ["evergreen"]
	_add(catalogue, boxwood)

	var hosta: SpeciesScript = _plant("HOSTA", "Hosta", "Plantain lily", SpeciesScript.PERENNIAL, 60)
	hosta.sun = SpeciesScript.PART_SHADE | SpeciesScript.FULL_SHADE
	hosta.water = SpeciesScript.WATER_MEDIUM
	_add(catalogue, hosta)

	var thyme: SpeciesScript = _plant(
		"THYMUS-SERPYLLUM",
		"Thymus serpyllum",
		"Creeping thyme",
		SpeciesScript.HERB,
		30,
	)
	thyme.sun = SpeciesScript.FULL_SUN
	thyme.water = SpeciesScript.WATER_LOW
	thyme.edible_parts = SpeciesScript.EAT_LEAF
	_add(catalogue, thyme)

	var basil: SpeciesScript = _plant("OCIMUM-BASILICUM", "Ocimum basilicum", "Sweet basil", SpeciesScript.ANNUAL, 60)
	basil.sun = SpeciesScript.FULL_SUN
	basil.water = SpeciesScript.WATER_MEDIUM
	basil.edible_parts = SpeciesScript.EAT_LEAF
	_add(catalogue, basil)

	var fescue: SpeciesScript = _plant("FESTUCA-GLAUCA", "Festuca glauca", "Blue fescue", SpeciesScript.GRASS, 40)
	fescue.sun = SpeciesScript.FULL_SUN
	fescue.water = SpeciesScript.WATER_LOW
	_add(catalogue, fescue)

	var rosemary: SpeciesScript = _plant(
		"SALVIA-ROSMARINUS",
		"Salvia rosmarinus",
		"Rosemary",
		SpeciesScript.SHRUB,
		120,
	)
	rosemary.sun = SpeciesScript.FULL_SUN
	rosemary.water = SpeciesScript.WATER_LOW
	rosemary.edible_parts = SpeciesScript.EAT_LEAF
	_add(catalogue, rosemary)

	return catalogue


## Two plants the list cannot tell apart: every question this program asks has the same answer for both.
func _twins() -> CatalogueScript:
	var catalogue: CatalogueScript = CatalogueScript.make()
	var sage: SpeciesScript = _plant("SALVIA-OFFICINALIS", "Salvia officinalis", "Common sage", SpeciesScript.SHRUB, 120)
	sage.sun = SpeciesScript.FULL_SUN
	sage.water = SpeciesScript.WATER_LOW
	_add(catalogue, sage)
	var rosemary: SpeciesScript = _plant(
		"SALVIA-ROSMARINUS",
		"Salvia rosmarinus",
		"Rosemary",
		SpeciesScript.SHRUB,
		120,
	)
	rosemary.sun = SpeciesScript.FULL_SUN
	rosemary.water = SpeciesScript.WATER_LOW
	_add(catalogue, rosemary)
	return catalogue


## Four trees where the light question is worth more than the conifer question - so the key asks the
## light, which is **later** in the authored order. This is the fixture that holds the arithmetic down:
## an order written by hand would ask the conifer question first, and be right to, and be less useful.
func _four_trees() -> CatalogueScript:
	var catalogue: CatalogueScript = CatalogueScript.make()
	var spruce: SpeciesScript = _plant("PICEA-ABIES", "Picea abies", "Norway spruce", SpeciesScript.TREE, 1500)
	spruce.sun = SpeciesScript.FULL_SUN
	_add(catalogue, spruce)
	var maple: SpeciesScript = _plant("ACER-RUBRUM", "Acer rubrum", "Red maple", SpeciesScript.TREE, 1500)
	maple.sun = SpeciesScript.FULL_SUN
	_add(catalogue, maple)
	var oak: SpeciesScript = _plant("QUERCUS-RUBRA", "Quercus rubra", "Red oak", SpeciesScript.TREE, 1500)
	oak.sun = SpeciesScript.PART_SHADE
	_add(catalogue, oak)
	var beech: SpeciesScript = _plant("FAGUS-SYLVATICA", "Fagus sylvatica", "European beech", SpeciesScript.TREE, 1500)
	beech.sun = SpeciesScript.FULL_SHADE
	_add(catalogue, beech)
	return catalogue


func _ids(plants: Array) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for plant: SpeciesScript in plants:
		out.append(String(plant.id))
	return out


# --- the join with the one filter ---------------------------------------------------------


func test_the_answers_become_the_one_filters_own_criteria() -> void:
	var criteria: Dictionary = KeyScript.criteria_for({ KeyScript.KIND: &"tree" })
	assert(criteria.size() == 1, "one answer, one criterion")
	assert(int(criteria["category"]) == SpeciesScript.TREE, "the kind becomes the filter's category")


func test_the_criteria_of_two_answers_are_both_kept() -> void:
	var criteria: Dictionary = KeyScript.criteria_for({
		KeyScript.KIND: &"tree",
		KeyScript.CONIFER: &"yes",
	})
	assert(int(criteria["category"]) == SpeciesScript.TREE)
	assert(bool(criteria["conifer"]), "whether it is a conifer is the filter's own answer")


func test_answers_that_came_back_from_a_file_hold_strings_and_still_work() -> void:
	# A round trip through JSON gives a String back where this program writes a StringName, so a key
	# that only took one of the two would stop narrowing the moment its answers were saved.
	var criteria: Dictionary = KeyScript.criteria_for({ "kind": "tree", "conifer": "yes" })
	assert(int(criteria["category"]) == SpeciesScript.TREE)
	assert(bool(criteria["conifer"]))


func test_a_question_the_program_does_not_have_narrows_nothing() -> void:
	# A record with a question this program has since dropped narrows by what the rest of it says
	# rather than refusing the whole thing - and an unknown criteria key would make the filter refuse.
	var catalogue: CatalogueScript = _catalogue()
	var answers: Dictionary = { &"weather": &"rainy", KeyScript.KIND: &"tree" }
	var criteria: Dictionary = KeyScript.criteria_for(answers)
	assert(criteria.size() == 1, "the question nobody has contributes nothing")
	assert(int(criteria["category"]) == SpeciesScript.TREE)
	assert(KeyScript.remaining(catalogue, { &"weather": &"rainy" }).size() == catalogue.count())


func test_a_kind_answer_keeps_only_that_kind() -> void:
	var catalogue: CatalogueScript = _catalogue()
	var answers: Dictionary = { KeyScript.KIND: &"shrub" }
	assert(
		_ids(KeyScript.remaining(catalogue, answers)) == PackedStringArray(["BUXUS-SEMPERVIRENS", "SALVIA-ROSMARINUS"]),
	)


# --- which question is asked next ---------------------------------------------------------


func test_the_question_asked_is_the_one_that_splits_the_field_most_evenly() -> void:
	# The light question is worth more than the conifer question here, and it is authored *after* it:
	# so this holds the arithmetic down rather than an order somebody wrote out.
	var catalogue: CatalogueScript = _four_trees()
	var all: Array[SpeciesScript] = catalogue.all()
	assert(KeyScript.split_score(all, KeyScript.LIGHT) > KeyScript.split_score(all, KeyScript.CONIFER))
	assert(KeyScript.next_question(catalogue, { }) == KeyScript.LIGHT, "the light tells the most")


func test_a_question_already_answered_is_never_asked_again() -> void:
	var catalogue: CatalogueScript = _catalogue()
	var answers: Dictionary = { KeyScript.CONIFER: &"no" }
	assert(KeyScript.next_question(catalogue, answers) != KeyScript.CONIFER)
	assert(KeyScript.next_question(catalogue, answers) != &"", "there is still more to ask of seven plants")


func test_the_kind_is_asked_before_anything_else() -> void:
	# Eight plants of six kinds: nothing cuts the field like asking what kind of plant it is.
	var catalogue: CatalogueScript = _catalogue()
	assert(KeyScript.next_question(catalogue, { }) == KeyScript.KIND)


func test_a_question_that_cannot_narrow_the_field_is_not_asked() -> void:
	# Every plant left takes full sun and part shade and neither takes full shade, so the light question
	# has nothing to say about the two trees and must give way to one that has.
	var catalogue: CatalogueScript = _catalogue()
	var answers: Dictionary = { KeyScript.KIND: &"tree" }
	assert(KeyScript.split_score(KeyScript.remaining(catalogue, answers), KeyScript.LIGHT) == 0.0)
	assert(KeyScript.next_question(catalogue, answers) == KeyScript.CONIFER)


# --- answers that are offered -----------------------------------------------------------------


func test_only_answers_that_would_still_leave_a_plant_are_offered() -> void:
	# Neither tree takes full shade, so offering it would offer a way to eliminate the right plant by
	# mistake.
	var catalogue: CatalogueScript = _catalogue()
	var answers: Dictionary = { KeyScript.KIND: &"tree" }
	var offered: PackedStringArray = PackedStringArray()
	for option: StringName in KeyScript.live_options(catalogue, KeyScript.LIGHT, answers):
		offered.append(String(option))
	assert(offered == PackedStringArray(["full_sun", "part_shade"]))


func test_every_kind_the_species_table_knows_is_offered() -> void:
	# The kinds are read off `PlantSpecies.CATEGORY_NAMES` rather than written again, so a kind added
	# there is offered by the key the day it is added.
	assert(KeyScript.option_keys(KeyScript.KIND).size() == SpeciesScript.CATEGORY_NAMES.size())


func test_the_height_bands_leave_every_plant_in_exactly_one() -> void:
	# A band's upper bound is one centimetre below the next band's lower bound, so no plant falls
	# between two bands or into both.
	var catalogue: CatalogueScript = _catalogue()
	var bands: Array = KeyScript.options_of(KeyScript.HEIGHT)
	assert(bands.size() > 1, "the height question offers a choice")
	for plant: SpeciesScript in catalogue.all():
		var in_a_band: int = 0
		for band: Dictionary in bands:
			if CatalogueScript.matches(plant, band["criteria"]):
				in_a_band += 1
		assert(in_a_band == 1, "%s stands in exactly one band, not %d" % [plant.id, in_a_band])


func test_the_two_food_answers_between_them_are_every_plant() -> void:
	var catalogue: CatalogueScript = _catalogue()
	var answers: Array = KeyScript.options_of(KeyScript.FOOD)
	for plant: SpeciesScript in catalogue.all():
		var eaten: int = 0
		for answer: Dictionary in answers:
			if CatalogueScript.matches(plant, answer["criteria"]):
				eaten += 1
		assert(eaten == 1, "%s is on exactly one side of the food question" % plant.id)


func test_a_conifer_is_a_question_about_the_genus_and_not_about_a_tag() -> void:
	# The boxwood is a nursery's "evergreen" and a botanical broadleaf, so it answers "not a conifer"
	# while the spruce answers the other way.
	var catalogue: CatalogueScript = _catalogue()
	var conifers: Dictionary = { KeyScript.CONIFER: &"yes" }
	assert(_ids(KeyScript.remaining(catalogue, conifers)) == PackedStringArray(["PICEA-ABIES"]))
	var broadleaves: Dictionary = { KeyScript.CONIFER: &"no" }
	assert(_ids(KeyScript.remaining(catalogue, broadleaves)).has("BUXUS-SEMPERVIRENS"))


# --- what the key says -------------------------------------------------------------------------


func test_every_question_has_a_prompt_and_every_answer_has_words() -> void:
	# A refusal or a prompt a compiler could have written is the one thing this program does not do,
	# so nothing here may be empty.
	for question: StringName in KeyScript.QUESTIONS:
		assert(not KeyScript.question_text(question).is_empty(), "the question %s has a prompt" % question)
		var options: Array = KeyScript.options_of(question)
		assert(options.size() >= 2, "the question %s offers a choice" % question)
		for option: Dictionary in options:
			assert(not String(option["label"]).is_empty(), "%s.%s has words" % [question, option["key"]])
			assert(not (option["criteria"] as Dictionary).is_empty(), "%s.%s filters something" % [question, option["key"]])


func test_a_fresh_key_asks_what_kind_of_plant_it_is() -> void:
	var catalogue: CatalogueScript = _catalogue()
	var state: Dictionary = KeyScript.state(catalogue, { })
	assert(StringName(state["verdict"]) == KeyScript.ASKING)
	assert(int(state["count"]) == catalogue.count(), "nothing has been ruled out yet")
	assert(StringName(state["question"]) == KeyScript.KIND)
	assert(not String(state["words"]).is_empty(), "the state says something in words")
	assert((state["options"] as Array).size() >= 2, "and offers the answers")
	for option: Dictionary in state["options"]:
		assert(int(option["leaves"]) > 0, "an answer offered leaves something")


func test_the_kind_then_the_conifer_names_the_spruce() -> void:
	var catalogue: CatalogueScript = _catalogue()
	var answers: Dictionary = { }
	answers = KeyScript.with_answer(answers, KeyScript.KIND, &"tree")
	assert(KeyScript.remaining(catalogue, answers).size() == 2, "a maple and a spruce are both trees")
	answers = KeyScript.with_answer(answers, KeyScript.CONIFER, &"yes")
	var state: Dictionary = KeyScript.state(catalogue, answers)
	assert(StringName(state["verdict"]) == KeyScript.IDENTIFIED)
	assert(int(state["count"]) == 1)
	assert(String(state["words"]).contains("Norway spruce"), "it says which plant it is: %s" % state["words"])


func test_a_plant_the_list_cannot_separate_is_reported_rather_than_guessed_at() -> void:
	# A key that chose between two plants the list cannot tell apart would be inventing a fact.
	var catalogue: CatalogueScript = _twins()
	var state: Dictionary = KeyScript.state(catalogue, { })
	assert(StringName(state["verdict"]) == KeyScript.SEVERAL)
	assert(KeyScript.next_question(catalogue, { }) == &"", "nothing can split them")
	assert(int(state["count"]) == 2, "both are still in the running")
	var words: String = String(state["words"])
	assert(words.contains("cannot tell"), "it says so: %s" % words)
	assert(words.contains("Common sage") and words.contains("Rosemary"), "and names them")


func test_an_answer_that_fits_nothing_says_so_rather_than_showing_nothing() -> void:
	var catalogue: CatalogueScript = _twins()
	var state: Dictionary = KeyScript.state(catalogue, { KeyScript.CONIFER: &"yes" })
	assert(StringName(state["verdict"]) == KeyScript.NONE)
	assert(int(state["count"]) == 0)
	assert((state["matches"] as Array).is_empty())
	var words: String = String(state["words"])
	assert(words.contains("Nothing in the plant list matches"), "it says so: %s" % words)
	assert(words.contains("Take the last answer back"), "and offers the way out")


func test_taking_the_last_answer_back_leaves_the_answers_before_it() -> void:
	var answers: Dictionary = { KeyScript.KIND: &"tree", KeyScript.LIGHT: &"full_sun" }
	var back: Dictionary = KeyScript.without_last(answers)
	assert(back.has(KeyScript.KIND), "the first answer stays")
	assert(not back.has(KeyScript.LIGHT), "the last one goes")
	assert(answers.size() == 2, "and the answers it was handed are not changed")
	assert(KeyScript.without_last({ }).is_empty(), "there is nothing to take back from nothing")


func test_changing_an_answer_does_not_move_it_to_the_end() -> void:
	# Changing one's mind about the light is not answering the light last, and an undo that took back
	# the wrong answer would be worse than no undo.
	var answers: Dictionary = { KeyScript.KIND: &"shrub", KeyScript.LIGHT: &"full_sun" }
	var again: Dictionary = KeyScript.with_answer(answers, KeyScript.KIND, &"tree")
	assert(KeyScript.asked(again) == KeyScript.asked(answers), "the order is unchanged")
	assert(StringName(again[KeyScript.KIND]) == &"tree", "and the answer is the new one")


# --- the leaves ---------------------------------------------------------------------------


## A garden whose leaves are stated: two trees that come off opposite and two that come off alternate,
## and one **nobody has read a leaf of** - whose water is different, so the only way to reach the leaf
## questions is to answer the habit question that takes the undescribed plant out of the running.
func _leaf_garden() -> CatalogueScript:
	var catalogue: CatalogueScript = CatalogueScript.make()
	_add(catalogue, _leaf_tree("ACER-RUBRUM", "Acer rubrum", "Red maple", SpeciesScript.ARR_OPPOSITE))
	_add(catalogue, _leaf_tree("ACER-SACCHARUM", "Acer saccharum", "Sugar maple", SpeciesScript.ARR_OPPOSITE))
	_add(catalogue, _leaf_tree("BETULA-PENDULA", "Betula pendula", "Silver birch", SpeciesScript.ARR_ALTERNATE))
	_add(catalogue, _leaf_tree("QUERCUS-RUBRA", "Quercus rubra", "Red oak", SpeciesScript.ARR_ALTERNATE))
	_add(catalogue, _leaf_tree("SALIX-BABYLONICA", "Salix babylonica", "Weeping willow", 0, SpeciesScript.WATER_LOW))
	return catalogue


func _leaf_tree(
	species_id: String,
	botanical: String,
	common: String,
	arrangement: int,
	water: int = SpeciesScript.WATER_MEDIUM,
) -> SpeciesScript:
	var plant: SpeciesScript = _plant(species_id, botanical, common, SpeciesScript.TREE, 1500)
	plant.sun = SpeciesScript.FULL_SUN
	plant.water = water
	plant.leaf_arrangement = arrangement
	return plant


func test_a_leaf_question_is_not_asked_while_a_plant_nobody_described_is_left() -> void:
	# The rule that makes a partly-described catalogue safe. A plant that states nothing about a leaf
	# fails every answer to a question about that leaf, so asking one would eliminate it by a description
	# nobody gave - and the key would settle confidently on the wrong plant.
	var catalogue: CatalogueScript = _leaf_garden()
	var all: Array[SpeciesScript] = catalogue.all()
	assert(not KeyScript.askable(all, KeyScript.LEAF_ARRANGEMENT), "the willow has no leaf stated")
	assert(KeyScript.split_score(all, KeyScript.LEAF_ARRANGEMENT) == 0.0, "so the question says nothing")
	assert(KeyScript.next_question(catalogue, { }) != KeyScript.LEAF_ARRANGEMENT, "and is not asked")
	assert(
		KeyScript.live_options(catalogue, KeyScript.LEAF_ARRANGEMENT, { }).is_empty(),
		"nor does it offer answers that would drop the willow",
	)


func test_the_leaf_question_comes_back_once_the_undescribed_plant_is_gone() -> void:
	var catalogue: CatalogueScript = _leaf_garden()
	# Only the willow grows in low water, so this is the habit question that takes it out of the running.
	assert(KeyScript.next_question(catalogue, { }) == KeyScript.WATER, "the water separates them first")
	var answers: Dictionary = KeyScript.with_answer({ }, KeyScript.WATER, &"medium_water")
	assert(KeyScript.remaining(catalogue, answers).size() == 4, "the willow is gone")
	assert(KeyScript.next_question(catalogue, answers) == KeyScript.LEAF_ARRANGEMENT, "and now the leaves can be asked")


func test_a_leaf_answer_narrows_the_field_to_that_leaf() -> void:
	var catalogue: CatalogueScript = _leaf_garden()
	var answers: Dictionary = KeyScript.with_answer({ }, KeyScript.WATER, &"medium_water")
	var opposite: Dictionary = KeyScript.with_answer(answers, KeyScript.LEAF_ARRANGEMENT, &"opposite")
	assert(_ids(KeyScript.remaining(catalogue, opposite)) == PackedStringArray(["ACER-RUBRUM", "ACER-SACCHARUM"]))
	var alternate: Dictionary = KeyScript.with_answer(answers, KeyScript.LEAF_ARRANGEMENT, &"alternate")
	assert(_ids(KeyScript.remaining(catalogue, alternate)) == PackedStringArray(["BETULA-PENDULA", "QUERCUS-RUBRA"]))


func test_a_leaf_question_offers_only_the_answers_that_would_leave_something() -> void:
	var catalogue: CatalogueScript = _leaf_garden()
	var answers: Dictionary = KeyScript.with_answer({ }, KeyScript.WATER, &"medium_water")
	var offered: Array[StringName] = KeyScript.live_options(catalogue, KeyScript.LEAF_ARRANGEMENT, answers)
	assert(offered.size() == 2, "two answers, not four: whorled and a rosette leave nothing")


func test_the_leaf_questions_are_the_species_own_vocabulary() -> void:
	# One table per trait, and the key offers exactly it - so a value added to a leaf's vocabulary is
	# offered by the key the day it is added, and a mistyped name cannot invent a leaf nobody has.
	assert(KeyScript.LEAF_QUESTIONS.size() == SpeciesScript.LEAF_TRAITS.size())
	for question: StringName in KeyScript.LEAF_QUESTIONS:
		assert(SpeciesScript.LEAF_TRAITS.has(question), "a leaf question is a leaf trait: %s" % question)
		var names: Dictionary = SpeciesScript.names_for(question)
		assert(names.size() >= 2, "the trait %s has a vocabulary" % question)
		assert(KeyScript.option_keys(question).size() == names.size(), "%s offers every value and no more" % question)
		for option: Dictionary in KeyScript.options_of(question):
			assert(
				(option["criteria"] as Dictionary).has(question),
				"an answer to %s is a criterion in its own trait's words" % question,
			)
		assert(KeyScript.LEAF_QUESTIONS.count(question) == 1, "and it is asked once")


func test_every_leaf_trait_is_a_criterion_the_filter_understands() -> void:
	# The key and the filter have to agree about the words, or the filter refuses the criteria the key
	# hands it and every leaf answer finds nothing at all.
	for question: StringName in KeyScript.LEAF_QUESTIONS:
		assert(
			CatalogueScript.unknown_criterion({ question: 1 }) == "",
			"the filter knows %s" % question,
		)


# --- the flower questions -----------------------------------------------------------------


## Two trees that agree about everything this key could ask before the flowers, and a fern: it flowers
## never, so it states no colour and no season.
func _two_flowers_and_a_fern() -> CatalogueScript:
	var catalogue: CatalogueScript = CatalogueScript.make()

	var serviceberry: SpeciesScript = _plant(
		"AMELANCHIER",
		"Amelanchier canadensis",
		"Serviceberry",
		SpeciesScript.TREE,
		600,
	)
	serviceberry.sun = SpeciesScript.FULL_SUN
	serviceberry.water = SpeciesScript.WATER_MEDIUM
	serviceberry.bloom_colour = Color(0.96, 0.94, 0.88)
	serviceberry.set_blooms_in(4, true)
	serviceberry.set_blooms_in(5, true)
	_add(catalogue, serviceberry)

	var crabapple: SpeciesScript = _plant(
		"MALUS-ROYALTY",
		"Malus 'Royalty'",
		"Purple crabapple",
		SpeciesScript.TREE,
		600,
	)
	crabapple.sun = SpeciesScript.FULL_SUN
	crabapple.water = SpeciesScript.WATER_MEDIUM
	crabapple.bloom_colour = Color(0.78, 0.47, 0.60)
	crabapple.set_blooms_in(5, true)
	_add(catalogue, crabapple)

	var fern: SpeciesScript = _plant("DRYOPTERIS", "Dryopteris filix-mas", "Male fern", SpeciesScript.FERN, 90)
	fern.sun = SpeciesScript.PART_SHADE
	fern.water = SpeciesScript.WATER_MEDIUM
	_add(catalogue, fern)

	return catalogue


func test_a_flower_question_is_asked_only_while_every_candidate_flowers() -> void:
	# The rule the leaves keep, for the same reason: a fern states no flower colour because it has no
	# flower, and the colour it does hold is the class's default, which nobody chose.
	var catalogue: CatalogueScript = _two_flowers_and_a_fern()
	assert(not KeyScript.askable(catalogue.all(), KeyScript.FLOWER), "a fern in the running means no colour question")
	assert(not KeyScript.askable(catalogue.all(), KeyScript.BLOOM), "and no season question either")
	assert(KeyScript.askable(catalogue.all(), KeyScript.KIND), "the kind is always askable")
	assert(
		KeyScript.askable(catalogue.filter({ "category": SpeciesScript.TREE }), KeyScript.FLOWER),
		"two flowering trees can be asked about colour",
	)
	assert(
		KeyScript.split_score(catalogue.filter({ "category": SpeciesScript.TREE }), KeyScript.FLOWER) > 0.0,
		"and the colour tells something",
	)


func test_two_plants_told_apart_by_nothing_but_the_flower_are_named_by_it() -> void:
	# The case that motivated the question: two trees that agree about everything this key could ask
	# before. Without the flower questions this was honestly "the list cannot tell them apart" with nothing
	# left to ask; the colour settles it in one more answer.
	var catalogue: CatalogueScript = _two_flowers_and_a_fern()
	var answers: Dictionary = { KeyScript.KIND: &"tree" }
	assert(
		KeyScript.next_question(catalogue, answers) == KeyScript.FLOWER,
		"the flower is what is worth asking about two trees alike in everything else",
	)
	answers = KeyScript.with_answer(answers, KeyScript.FLOWER, &"cream")
	assert(KeyScript.remaining(catalogue, answers).size() == 1, "one plant here flowers cream")
	assert(String(KeyScript.remaining(catalogue, answers)[0].id) == "AMELANCHIER", "the serviceberry")
	assert(
		KeyScript.verdict_of(KeyScript.remaining(catalogue, answers), KeyScript.next_question(catalogue, answers))
		== KeyScript.IDENTIFIED,
		"and the key names it rather than leaving two it cannot separate",
	)


func test_a_plant_that_never_flowers_is_not_a_colour_nobody_chose() -> void:
	# The trap this criterion closes. A fern's stored colour is `PlantSpecies`' default, which happens to be
	# a pink - so a criterion reading the colour and nothing else would keep a plant with no flower at all,
	# and keep it under an answer nobody gave it.
	var catalogue: CatalogueScript = _two_flowers_and_a_fern()
	var pink_criteria: Dictionary = KeyScript.criteria_for({ KeyScript.FLOWER: &"pink" })
	assert(catalogue.filter(pink_criteria).size() == 1, "exactly one plant here flowers pink")
	assert(String(catalogue.filter(pink_criteria)[0].id) == "MALUS-ROYALTY", "and it is the crabapple")
	# The fern is offered no colour at all, whichever one is asked for.
	for colour: StringName in SpeciesScript.FLOWER_COLOURS:
		var found: Array = catalogue.filter(KeyScript.criteria_for({ KeyScript.FLOWER: colour }))
		for plant: SpeciesScript in found:
			assert(String(plant.id) != "DRYOPTERIS", "a fern is not a %s flower" % colour)


func test_the_season_answer_is_the_seasons_own_months() -> void:
	# The answer is a season, because that is what a person knows; the filter is what turns it into months.
	# Both trees flower in May, so spring keeps both and summer keeps neither.
	var catalogue: CatalogueScript = _two_flowers_and_a_fern()
	assert(
		catalogue.filter(KeyScript.criteria_for({ KeyScript.BLOOM: &"spring" })).size() == 2,
		"both trees flower in spring",
	)
	assert(
		catalogue.filter(KeyScript.criteria_for({ KeyScript.BLOOM: &"summer" })).is_empty(),
		"neither flowers in summer, and the fern states no month at all",
	)
	var criteria: Dictionary = KeyScript.criteria_for({ KeyScript.BLOOM: &"spring" })
	assert(criteria.keys() == ["bloom_season"], "the answer is the filter's own season criterion")
	assert(CatalogueScript.unknown_criterion(criteria) == "", "which the filter understands")


func test_the_flower_vocabulary_is_the_species_own() -> void:
	# Both tables live on `PlantSpecies`, so a colour or a season added there is offered by the key the day
	# it is added, and the key can never offer an answer the filter cannot come back with.
	assert(KeyScript.option_keys(KeyScript.FLOWER) == SpeciesScript.FLOWER_COLOURS, "the colours are the species' own")
	assert(KeyScript.option_keys(KeyScript.BLOOM).size() == SpeciesScript.SEASONS.size(), "one answer per season")
	for question: StringName in [KeyScript.FLOWER, KeyScript.BLOOM]:
		assert(KeyScript.question_text(question) != "", "%s has a prompt" % question)
		for option: Dictionary in KeyScript.options_of(question):
			assert(
				CatalogueScript.unknown_criterion(option["criteria"]) == "",
				"the filter knows the criterion behind %s" % option["label"],
			)


func test_an_i_am_not_sure_answer_narrows_nothing_and_is_not_asked_again() -> void:
	# The way past a question somebody cannot answer. It is kept as an answer so the key moves on rather than
	# asking the same thing forever, and it carries no criterion - so the field is not narrowed by a guess
	# nobody made, which is the one thing a key may not do.
	var catalogue: CatalogueScript = _catalogue()
	var nothing_said: int = KeyScript.remaining(catalogue, { }).size()
	var answers: Dictionary = KeyScript.with_unsure({ }, KeyScript.KIND)
	assert(KeyScript.criteria_for(answers).is_empty(), "not sure is no criterion at all")
	assert(KeyScript.remaining(catalogue, answers).size() == nothing_said, "so it narrows nothing")
	assert(KeyScript.asked(answers) == [KeyScript.KIND], "and the question counts as answered")
	assert(KeyScript.next_question(catalogue, answers) != KeyScript.KIND, "so it is not asked again")
	assert(KeyScript.option_text(KeyScript.KIND, KeyScript.UNSURE) == KeyScript.UNSURE_WORDS, "and it has words")
	# It is never one of a question's own answers: it is a way past a question, not a way to name a plant.
	for question: StringName in KeyScript.QUESTIONS:
		assert(not KeyScript.option_keys(question).has(KeyScript.UNSURE), "%s does not offer not sure" % question)
	# And it is taken back like any other answer, which is what somebody who pressed it by mistake needs.
	assert(KeyScript.without_last(answers).is_empty(), "taking it back leaves nothing answered")