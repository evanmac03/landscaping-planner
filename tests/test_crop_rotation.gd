extends Node
## What a food crop should follow and what it should stand beside (idea #3).
##
## The `family` field a crop carries is read here for the first time. Two questions are held down:
## the **turn** - the same family shall not follow itself, and a legume before it is a good thing -
## and the **company** - what grows well beside what. The rule that decides the verdict is the
## suitability check's rule in the suitability check's four words, and these tests read it the same
## way, grey for a question that could not be asked and never green.
##
## The company knowledge is in two layers - the **families** a pairing groups and the **plants** a
## pairing names - and the rules held down below are that a named plant is read before its family, that
## a plant with no family at all can still be a companion, that a warning is read before an
## encouragement, and that every pairing in the file says where it came from and whether it is a
## mechanism or a tradition.

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


# --- the plants a pairing names -------------------------------------------------------------


## A species with a common name, a botanical name and a family. The two names matter: a pairing kept by
## name has to find a plant the way a person would write it.
func _plant(id: StringName, common: String, family: StringName, edible: bool = true) -> PlantSpecies:
	var plant: PlantSpecies = SpeciesScript.make(
		id, "Botanical %s" % common, common, 100, 60, SpeciesScript.ANNUAL
	)
	plant.family = family
	if edible:
		plant.edible_parts = SpeciesScript.EAT_LEAF
	return plant


## A list holding every plant the file's named pairings are about, under the id each pairing writes: the
## marigold, which has no family and is not a crop, the herbs, and a bed's worth of food.
func _companion_catalogue() -> PlantCatalogue:
	var catalogue: PlantCatalogue = CatalogueScript.make()
	catalogue.add(_plant(&"tagetes-patula", "Marigold", CropRotationScript.FAMILY_NONE, false))
	catalogue.add(_plant(&"bean", "Bean", CropRotationScript.LEGUME))
	catalogue.add(_plant(&"tomato", "Tomato", CropRotationScript.NIGHTSHADE))
	catalogue.add(_plant(&"ocimum-basilicum-genovese", "Basil", CropRotationScript.HERB_FAMILY))
	catalogue.add(_plant(&"fennel", "Fennel", CropRotationScript.HERB_FAMILY))
	catalogue.add(_plant(&"anethum-graveolens", "Dill", CropRotationScript.HERB_FAMILY))
	return catalogue


func _outcome_of(rows: Array[Dictionary], name: String) -> int:
	for row: Dictionary in rows:
		if String(row["name"]) == name:
			return int(row["outcome"])
	return CropRotationScript.UNKNOWN


func _pair_about(id: StringName) -> Dictionary:
	for pair: Dictionary in CropRotationScript.COMPANION_PLANTS:
		var a: Dictionary = pair["a"]
		var b: Dictionary = pair["b"]
		if StringName(a.get("id", &"")) == id or StringName(b.get("id", &"")) == id:
			return pair
	return {}


func test_a_pairing_that_names_a_plant_is_read_before_the_family_it_sits_in() -> void:
	# The tradition's chart gives fennel as compatible with nothing, and the family table says a herb
	# grows well beside a nightshade. Fennel is a herb: the named rule is the answer, not a second
	# opinion standing beside the family's.
	var catalogue: PlantCatalogue = _companion_catalogue()
	var fennel: Dictionary = CropRotationScript.subject_of(catalogue.get_species(&"fennel"))
	var tomato: Dictionary = CropRotationScript.subject_of(catalogue.get_species(&"tomato"))
	var apart: Dictionary = CropRotationScript.company_finding(fennel, tomato)
	assert(int(apart["outcome"]) == CropRotationScript.UNSUITABLE, String(apart.get("because", "")))
	assert(String(apart["because"]).contains("does not grow well"), String(apart["because"]))
	# And the herb row still speaks for a herb that is not excepted, so this is one plant and not the
	# family: basil beside the same tomato is the good pairing the row claims.
	var basil: Dictionary = CropRotationScript.subject_of(
		catalogue.get_species(&"ocimum-basilicum-genovese")
	)
	assert(
		int(CropRotationScript.company_finding(basil, tomato)["outcome"]) == CropRotationScript.GOOD,
		String(CropRotationScript.company_finding(basil, tomato).get("because", ""))
	)


func test_a_plant_with_no_family_can_still_be_a_companion() -> void:
	# Marigold rotates with nobody and is not a crop, so no family row can ever reach it. The named table
	# is the only way this plant is ever spoken of, and it is the best-stated companion in the file.
	var catalogue: PlantCatalogue = _companion_catalogue()
	var marigold: Dictionary = CropRotationScript.subject_of(catalogue.get_species(&"tagetes-patula"))
	assert(marigold["family"] == CropRotationScript.FAMILY_NONE, "it has no family to be grouped by")
	var line: String = CropRotationScript.company_line(
		catalogue, CropRotationScript.subject_of(catalogue.get_species(&"bean"))
	)
	assert(line.contains("Marigold"), line)
	assert(not line.contains("Botanical"), "named as a person says it, not by its whole label: %s" % line)
	assert(line.count("Marigold") == 1, "and named once, not once per pairing about it: %s" % line)


func test_a_warning_is_read_before_an_encouragement_when_both_are_stated() -> void:
	# A bean is told two things at once: marigold goes with it, and fennel should be kept from it. The
	# caution is the verdict's own rule - something against the crop outranks something for it - so the
	# answer does not depend on which entry was written first.
	var catalogue: PlantCatalogue = _companion_catalogue()
	var bean: Dictionary = CropRotationScript.subject_of(catalogue.get_species(&"bean"))
	var named: Array[Dictionary] = CropRotationScript.company_names(catalogue, bean)
	assert(_outcome_of(named, "Marigold") == CropRotationScript.GOOD, str(named))
	assert(_outcome_of(named, "Fennel") == CropRotationScript.UNSUITABLE, str(named))
	assert(
		int(CropRotationScript.company_finding(bean, CropRotationScript.subject_of(
			catalogue.get_species(&"fennel")
		))["outcome"]) == CropRotationScript.UNSUITABLE,
		"and asked the other way round it is the same answer"
	)


func test_a_pairing_nobody_stated_is_passed_over_rather_than_invented() -> void:
	var boxwood: PlantSpecies = SpeciesScript.make(&"buxus", "Buxus sempervirens", "Boxwood", 200, 150)
	assert(
		CropRotationScript.company_finding(
			CropRotationScript.subject_of(boxwood), CropRotationScript.subject_of(boxwood)
		).is_empty(),
		"nothing is stated about a boxwood beside a boxwood"
	)
	assert(CropRotationScript.company_names(_companion_catalogue(), {}).is_empty())
	assert(CropRotationScript.company_line(_companion_catalogue(), {}).is_empty())
	assert(CropRotationScript.company_names(null, CropRotationScript.subject_of(boxwood)).is_empty())


func test_the_family_table_is_still_the_whole_answer_for_a_caller_holding_only_families() -> void:
	# "Whatever is growing" answers a plant somebody has named, and only that, so a rule about one plant
	# can never become a rule about the family that plant happens to sit in.
	var herb: String = CropRotationScript.companion_line(CropRotationScript.HERB_FAMILY)
	assert(not herb.contains("Marigold"), herb)
	assert(not herb.contains("growing"), herb)
	assert(CropRotationScript.companion_line(CropRotationScript.FAMILY_NONE) == "")
	assert(
		CropRotationScript.universal_pair(
			CropRotationScript.family_subject(CropRotationScript.HERB_FAMILY)
		).is_empty()
	)


func test_a_line_with_no_list_is_the_family_answer_and_names_no_plant() -> void:
	var family: Dictionary = CropRotationScript.family_subject(CropRotationScript.LEGUME)
	var line: String = CropRotationScript.company_line(null, family)
	assert(line == CropRotationScript.companion_line(CropRotationScript.LEGUME), line)
	assert(not line.contains("Marigold"), "a plant outside this list cannot be named: %s" % line)
	assert(CropRotationScript.company_names(null, family).is_empty())
	assert(
		CropRotationScript.company_reason(null, family).is_empty(),
		"and no plant was named, so there is no reason to give"
	)


func test_a_plant_whose_rule_asks_nothing_of_the_other_plant_is_answered_by_that_rule_alone() -> void:
	# The family words cannot sit beside a rule that is about everything: they would say the opposite of
	# it. Fennel's own rule is "with nothing", the herb row's is "grows well beside a nightshade", and
	# the plant's own rule is what a person is told.
	var catalogue: PlantCatalogue = _companion_catalogue()
	var fennel: Dictionary = CropRotationScript.subject_of(catalogue.get_species(&"fennel"))
	assert(
		CropRotationScript.company_line(catalogue, fennel) == "should be kept from whatever is growing",
		CropRotationScript.company_line(catalogue, fennel)
	)
	var marigold: Dictionary = CropRotationScript.subject_of(catalogue.get_species(&"tagetes-patula"))
	assert(
		CropRotationScript.company_line(catalogue, marigold) == "grows well with whatever is growing",
		CropRotationScript.company_line(catalogue, marigold)
	)
	assert(
		CropRotationScript.universal_pair(
			CropRotationScript.subject_of(catalogue.get_species(&"bean"))
		).is_empty(),
		"the ordinary plant has no such rule, and the family table speaks for it"
	)


func test_a_rule_about_a_plant_this_list_has_not_got_is_carried_rather_than_lost() -> void:
	# Dill is kept from the carrot, and this list has never held a carrot. The rule is kept by the
	# plant's name, so the day one arrives the pairing is already right and nobody had to remember it.
	var catalogue: PlantCatalogue = _companion_catalogue()
	var dill: Dictionary = CropRotationScript.subject_of(catalogue.get_species(&"anethum-graveolens"))
	var carrot: PlantSpecies = _plant(&"carrot", "Carrot", CropRotationScript.ROOT_CROP)
	assert(
		int(CropRotationScript.company_finding(
			dill, CropRotationScript.subject_of(carrot)
		)["outcome"]) == CropRotationScript.UNSUITABLE,
		"a rule kept by name answers a carrot that was never in the file"
	)
	assert(
		CropRotationScript.company_finding(
			{}, CropRotationScript.subject_of(carrot)
		).is_empty(),
		"and there is nothing to match against a subject that is not a plant"
	)
	catalogue.add(carrot)
	assert(CropRotationScript.company_line(catalogue, dill).contains("Carrot"), "the day it arrives it is named")


func test_every_pairing_says_where_it_came_from_and_how_it_is_known() -> void:
	for pair: Dictionary in CropRotationScript.COMPANION_PLANTS:
		var outcome: int = int(pair.get("outcome", CropRotationScript.UNKNOWN))
		assert(
			outcome == CropRotationScript.GOOD or outcome == CropRotationScript.UNSUITABLE,
			"a pairing is a good one or a warning, and nothing else: %s" % str(pair)
		)
		var nature: String = String(pair.get("nature", ""))
		assert(
			nature == CropRotationScript.NATURE_KNOWN or nature == CropRotationScript.NATURE_TRADITION,
			"and it says whether it is a mechanism or a tradition: %s" % str(pair)
		)
		var ref: Variant = pair.get("source", "")
		var ids: Array = ref if ref is Array else [ref]
		for one: Variant in ids:
			assert(
				CropRotationScript.COMPANION_SOURCES.has(String(one)),
				"%s is named as a source and is not written down" % one
			)
		assert(
			not CropRotationScript.source_title(ref).is_empty(),
			"and the work has a title a page can print: %s" % str(pair)
		)
		assert(not String(pair.get("why", "")).is_empty(), "and every pairing can say why it is said")


func test_a_mechanism_is_given_as_a_mechanism_and_a_tradition_as_a_tradition() -> void:
	# Marigold is the pairing here with a mechanism somebody has looked into, and its entry carries the
	# mechanism itself - the chemical - rather than only the claim.
	var marigold: Dictionary = _pair_about(&"tagetes-patula")
	assert(not marigold.is_empty(), "the marigold pairing is in the file")
	assert(String(marigold["nature"]) == CropRotationScript.NATURE_KNOWN, str(marigold))
	assert(String(marigold["why"]).contains("alpha-terthienyl"), String(marigold["why"]))
	assert(
		CropRotationScript.source_title(marigold["source"]).contains("Wisconsin"),
		CropRotationScript.source_title(marigold["source"])
	)
	# And the dill beside the carrot is what the other kind looks like: repeated, unexplained, and
	# carried anyway, because saying so is the honest thing to do with it.
	var kept_from: Dictionary = {}
	for pair: Dictionary in CropRotationScript.COMPANION_PLANTS:
		if String((pair["b"] as Dictionary).get("name", "")) == "Carrot":
			kept_from = pair
	assert(not kept_from.is_empty(), "the carrot pairing is carried")
	assert(String(kept_from["nature"]) == CropRotationScript.NATURE_TRADITION, str(kept_from))
	assert(
		not String(kept_from["why"]).contains("alpha-terthienyl"),
		"and a tradition is not dressed up as a mechanism"
	)


func test_the_reason_says_why_and_names_the_work_it_came_from() -> void:
	var catalogue: PlantCatalogue = _companion_catalogue()
	var bean: Dictionary = CropRotationScript.subject_of(catalogue.get_species(&"bean"))
	var reason: String = CropRotationScript.company_reason(catalogue, bean)
	assert(reason.contains("alpha-terthienyl"), reason)
	assert(reason.contains("Wisconsin Horticulture"), reason)
	assert(reason.contains("Mississippi State"), "both works that say it are cited: %s" % reason)
	assert(
		reason.find("Marigold") < reason.find("Fennel"),
		"what goes with it is said before what it is kept from: %s" % reason
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