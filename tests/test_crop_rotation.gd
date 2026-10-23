extends Node
## What a food crop should follow and what it should stand beside (idea #3).
##
## The `family` field a crop carries is read here for the first time. Two questions are held down:
## the **turn** - the same family shall not follow itself, and a legume before it is a good thing -
## and the **company** - what grows well beside what. The rule that decides the verdict is the
## suitability check's rule in the suitability check's four words, and these tests read it the same
## way, grey for a question that could not be asked and never green.

const CropRotationScript := preload("res://scripts/crop_rotation.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")
const CatalogueScript := preload("res://scripts/plant_catalogue.gd")
const SuitabilityScript := preload("res://scripts/plant_suitability.gd")


## An edible crop of a stated family.
func _crop(id: StringName, family: StringName) -> PlantSpecies:
	var plant: PlantSpecies = SpeciesScript.make(
		id, "%s sp." % String(id), String(id), 150, 60, SpeciesScript.ANNUAL
	)
	plant.edible_parts = SpeciesScript.EAT_LEAF
	plant.family = family
	return plant


# --- the families ---------------------------------------------------------------------------


func test_a_family_reads_as_words_and_there_are_nine_of_them() -> void:
	assert(CropRotationScript.family_words(CropRotationScript.BRASSICA) == "brassica")
	assert(CropRotationScript.family_words(CropRotationScript.HERB_FAMILY) == "herb")
	assert(CropRotationScript.family_words(CropRotationScript.FAMILY_NONE) == "", "nobody rotates nothing")
	assert(CropRotationScript.family_words(&"PUMPKIN") == "", "and a word that is not a family has none")
	assert(CropRotationScript.families().size() == 9, "nine families rotate")
	assert(CropRotationScript.families()[0] == CropRotationScript.BRASSICA, "in the catalogue's order")


func test_a_family_reads_with_the_article_it_wants() -> void:
	assert(CropRotationScript.article("allium") == "an")
	assert(CropRotationScript.article("brassica") == "a")
	assert(CropRotationScript.article("") == "")
	var chives: PlantSpecies = _crop(&"chives", CropRotationScript.ALLIUM)
	var verdict: Dictionary = CropRotationScript.check(chives, CropRotationScript.ALLIUM)
	assert(
		String(verdict["summary"]).contains("an allium after an allium"),
		String(verdict["summary"])
	)


# --- companion planting ---------------------------------------------------------------------


func test_the_companion_table_reads_the_same_either_way_round() -> void:
	# A pairing is declared once and read as a symmetry, so the table cannot disagree with itself.
	assert(CropRotationScript.good_neighbours(CropRotationScript.LEGUME).has(CropRotationScript.LEAFY))
	assert(CropRotationScript.good_neighbours(CropRotationScript.LEAFY).has(CropRotationScript.LEGUME))
	assert(CropRotationScript.bad_neighbours(CropRotationScript.LEGUME).has(CropRotationScript.ALLIUM))
	assert(CropRotationScript.bad_neighbours(CropRotationScript.ALLIUM).has(CropRotationScript.LEGUME))
	assert(CropRotationScript.good_neighbours(CropRotationScript.FAMILY_NONE).is_empty())
	assert(CropRotationScript.bad_neighbours(CropRotationScript.FAMILY_NONE).is_empty())


func test_a_crops_companions_read_as_a_line() -> void:
	var line: String = CropRotationScript.companion_line(CropRotationScript.LEGUME)
	assert(line.contains("grows well beside"), line)
	assert(line.contains("leafy"), line)
	assert(line.contains("kept from allium"), line)
	var herb: String = CropRotationScript.companion_line(CropRotationScript.HERB_FAMILY)
	assert(not herb.contains("kept from"), "a herb is kept from nothing in this table: %s" % herb)
	assert(CropRotationScript.companion_line(CropRotationScript.FAMILY_NONE) == "")


func test_a_companion_is_reported_only_where_there_is_a_stated_pairing() -> void:
	var apart: Dictionary = CropRotationScript.companion_finding(
		CropRotationScript.ALLIUM, CropRotationScript.LEGUME
	)
	assert(not apart.is_empty(), "an allium beside a legume is worth reporting")
	assert(int(apart["outcome"]) == CropRotationScript.UNSUITABLE, String(apart["because"]))
	var together: Dictionary = CropRotationScript.companion_finding(
		CropRotationScript.LEAFY, CropRotationScript.LEGUME
	)
	assert(int(together["outcome"]) == CropRotationScript.GOOD, String(together["because"]))
	# A herb beside a root crop is not a pairing anybody stated, so nothing is claimed about it.
	assert(
		CropRotationScript.companion_finding(
			CropRotationScript.HERB_FAMILY, CropRotationScript.ROOT_CROP
		).is_empty(),
		"a pairing nobody stated is passed over rather than invented"
	)
	assert(
		CropRotationScript.companion_finding(
			CropRotationScript.LEGUME, CropRotationScript.LEGUME
		).is_empty(),
		"and the same family beside itself is not a companion question"
	)


# --- the turn -------------------------------------------------------------------------------


func test_the_same_family_shall_not_follow_itself() -> void:
	var kale: PlantSpecies = _crop(&"kale", CropRotationScript.BRASSICA)
	var verdict: Dictionary = CropRotationScript.check(kale, CropRotationScript.BRASSICA)
	assert(int(verdict["verdict"]) == CropRotationScript.UNSUITABLE, CropRotationScript.summary_of(verdict))
	assert(verdict["label"] == "same family twice", String(verdict["label"]))
	assert(String(verdict["summary"]).contains("shares the same pests"), String(verdict["summary"]))


func test_a_different_family_is_a_fresh_start_and_a_legume_is_a_gift() -> void:
	var kale: PlantSpecies = _crop(&"kale", CropRotationScript.BRASSICA)
	var fresh: Dictionary = CropRotationScript.check(kale, CropRotationScript.ROOT_CROP)
	assert(int(fresh["verdict"]) == CropRotationScript.GOOD, CropRotationScript.summary_of(fresh))
	assert(fresh["label"] == "a fresh family", String(fresh["label"]))
	var after_beans: Dictionary = CropRotationScript.check(kale, CropRotationScript.LEGUME)
	assert(after_beans["label"] == "after a legume", String(after_beans["label"]))
	var reason: String = String((after_beans["findings"] as Array)[0].get("because", ""))
	assert(reason.contains("richer"), reason)


func test_something_against_the_crop_outranks_a_gap_the_way_suitability_orders_them() -> void:
	# A bed nobody has stated the history of, with an allium already beside the beans: the companion
	# wrong is the verdict, not the gap the unstated history left.
	var bean: PlantSpecies = _crop(&"bean", CropRotationScript.LEGUME)
	var verdict: Dictionary = CropRotationScript.check(
		bean, CropRotationScript.FAMILY_NONE, [CropRotationScript.ALLIUM]
	)
	assert(int(verdict["verdict"]) == CropRotationScript.UNSUITABLE, CropRotationScript.summary_of(verdict))
	assert(verdict["findings"].size() == 1, "only the company question could be asked")


# --- a question nobody answered -------------------------------------------------------------


func test_a_bed_whose_history_is_unstated_leaves_the_turn_unknown_never_green() -> void:
	var kale: PlantSpecies = _crop(&"kale", CropRotationScript.BRASSICA)
	var verdict: Dictionary = CropRotationScript.check(kale, CropRotationScript.FAMILY_NONE)
	assert(int(verdict["verdict"]) == CropRotationScript.UNKNOWN, CropRotationScript.summary_of(verdict))
	assert(verdict["findings"].is_empty(), "nothing was asked, so there is no finding")
	assert(
		String(verdict["summary"]).contains("nothing says what grew there before"),
		String(verdict["summary"])
	)
	assert(
		CropRotationScript.colour_from(verdict) != SuitabilityScript.GOOD_COLOUR,
		"and it is drawn grey, not green"
	)


func test_a_crop_that_names_no_family_cannot_be_rotated() -> void:
	var mystery: PlantSpecies = _crop(&"mystery", CropRotationScript.FAMILY_NONE)
	assert(CropRotationScript.turn_finding(mystery, CropRotationScript.BRASSICA).is_empty())
	var verdict: Dictionary = CropRotationScript.check(mystery, CropRotationScript.BRASSICA)
	assert(int(verdict["verdict"]) == CropRotationScript.UNKNOWN, CropRotationScript.summary_of(verdict))
	assert(String(verdict["summary"]).contains("does not say which family"), String(verdict["summary"]))


func test_a_null_crop_is_unknown_rather_than_a_crash() -> void:
	var verdict: Dictionary = CropRotationScript.check(null, CropRotationScript.BRASSICA)
	assert(int(verdict["verdict"]) == CropRotationScript.UNKNOWN)


# --- what would follow in a bed -------------------------------------------------------------


func _catalogue() -> PlantCatalogue:
	var catalogue: PlantCatalogue = CatalogueScript.make()
	var boxwood: PlantSpecies = SpeciesScript.make(&"buxus", "Buxus sempervirens", "Boxwood", 200, 150)
	catalogue.add(boxwood)
	catalogue.add(_crop(&"kale", CropRotationScript.BRASSICA))
	var bean: PlantSpecies = _crop(&"bean", CropRotationScript.LEGUME)
	bean.botanical_name = "Phaseolus vulgaris"
	catalogue.add(bean)
	return catalogue


func test_only_the_food_is_listed_and_the_best_comes_first() -> void:
	var rows: Array = CropRotationScript.rows(_catalogue(), CropRotationScript.BRASSICA)
	assert(rows.size() == 2, "the boxwood is not a crop: %d" % rows.size())
	assert(StringName(rows[0]["id"]) == &"bean", "the legume follows the brassica best: %s" % String(rows[0]["title"]))
	var texts: Array[String] = CropRotationScript.row_texts(_catalogue(), CropRotationScript.BRASSICA)
	assert(texts.size() == 2, "and in the same bed the brassica is listed, refused")
	assert(texts[1].contains("same family twice"), str(texts))


func test_the_rows_come_to_a_sentence_and_an_empty_list_says_so() -> void:
	var rows: Array = CropRotationScript.rows(_catalogue(), CropRotationScript.LEGUME)
	var line: String = CropRotationScript.describe_rows(rows)
	assert(line.begins_with("2 crops:"), line)
	assert(line.contains("follow on well"), line)
	assert(CropRotationScript.describe_rows([]) == "no crops are recorded in this plant list")


func test_a_null_catalogue_is_no_rows_rather_than_a_crash() -> void:
	assert(CropRotationScript.rows(null, CropRotationScript.BRASSICA).is_empty())
	assert(CropRotationScript.describe_rows([]).contains("no crops"))