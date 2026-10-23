extends Node
## How long the season is: the frost-date pair, and the crops measured against it.
##
## The arithmetic is the module's alone, so this drives the module directly - no window, no drawing and
## no screen. A species is made through `PlantSpecies.make`, the way the catalogue makes one.

const SeasonScript := preload("res://scripts/growing_season.gd")
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
	catalogue.add(_crop(&"quick", "Quick", 60))        # 80 days to spare
	catalogue.add(_crop(&"thin", "Thin", 130))         # 10 days to spare -> tolerated
	catalogue.add(_crop(&"slow", "Slow", 200))         # too slow for the season
	catalogue.add(_crop(&"unstated", "Unstated", 0))   # no time to maturity recorded
	catalogue.add(SpeciesScript.make(&"boxwood", "Buxus sempervirens", "Box", 60, 60, SpeciesScript.SHRUB))
	return catalogue


# --- the pair -------------------------------------------------------------------------------


func test_a_season_is_two_days_the_right_way_round() -> void:
	assert(SeasonScript.is_stated(LAST, FIRST), "a last frost before a first frost is a season")
	assert(not SeasonScript.is_stated(0, FIRST), "a last frost nobody stated is not a season")
	assert(not SeasonScript.is_stated(LAST, 0), "nor is a first frost nobody stated")
	assert(not SeasonScript.is_stated(FIRST, LAST), "nor is a season that ends before it begins")
	assert(not SeasonScript.is_stated(LAST, LAST), "nor is a season of no days")
	assert(not SeasonScript.is_stated(LAST, 500), "and a day outside the year is not a day of it")


func test_two_dates_are_a_number_of_days_to_finish_in() -> void:
	assert(SeasonScript.length_days(LAST, FIRST) == 140, "20 May to 7 October is 140 days")
	assert(SeasonScript.length_days(FIRST, LAST) == 0, "a pair the wrong way round is no days, not negative")
	assert(SeasonScript.length_days(0, 0) == 0, "and a season nobody stated is no days either")


func test_a_day_reads_as_a_date_and_one_that_is_not_a_day_reads_as_nothing() -> void:
	assert(SeasonScript.day_words(LAST) == "20 May", SeasonScript.day_words(LAST))
	assert(SeasonScript.day_words(FIRST) == "7 October", SeasonScript.day_words(FIRST))
	assert(SeasonScript.day_words(0) == "", "not stated is not a date")
	assert(SeasonScript.day_words(400) == "", "and neither is a day the year does not have")


func test_the_season_reads_as_one_sentence() -> void:
	var words: String = SeasonScript.season_text(LAST, FIRST)
	assert(words.contains("140 days"), words)
	assert(words.contains("20 May") and words.contains("7 October"), words)
	assert(SeasonScript.season_text(0, 0) == SeasonScript.NO_SEASON, SeasonScript.season_text(0, 0))
	assert(
		SeasonScript.season_text(FIRST, LAST) == SeasonScript.NO_SEASON,
		"a pair the wrong way round is not a season either"
	)


# --- a crop against the season -------------------------------------------------------------


func test_a_crop_with_time_to_spare_fits() -> void:
	var verdict: Dictionary = SeasonScript.check(_crop(&"quick", "Quick", 60), LAST, FIRST)
	assert(int(verdict["verdict"]) == SeasonScript.GOOD, SeasonScript.summary_of(verdict))
	assert(String(verdict["label"]) == "fits the season", String(verdict["label"]))
	assert(int(verdict["days"]) == 140, "and it reports the season's own length")
	assert(bool(verdict["stated"]), "and that the season is stated")


func test_a_crop_that_only_just_finishes_is_tolerated() -> void:
	# Ten days of a 140-day season to spare: it finishes, but a cold year would take it.
	var verdict: Dictionary = SeasonScript.check(_crop(&"thin", "Thin", 130), LAST, FIRST)
	assert(int(verdict["verdict"]) == SeasonScript.TOLERATED, SeasonScript.summary_of(verdict))
	assert(String(verdict["label"]).contains("to spare"), String(verdict["label"]))


func test_the_margin_is_a_fortnight() -> void:
	# Exactly a fortnight to spare is the last day that is still tolerated; one day more is comfortable.
	var exact: Dictionary = SeasonScript.check(
		_crop(&"a", "A", 140 - SeasonScript.TIGHT_DAYS), LAST, FIRST
	)
	assert(int(exact["verdict"]) == SeasonScript.TOLERATED, SeasonScript.summary_of(exact))
	var roomier: Dictionary = SeasonScript.check(
		_crop(&"b", "B", 140 - SeasonScript.TIGHT_DAYS - 1), LAST, FIRST
	)
	assert(int(roomier["verdict"]) == SeasonScript.GOOD, SeasonScript.summary_of(roomier))


func test_a_crop_too_slow_for_the_season_will_not_finish() -> void:
	var verdict: Dictionary = SeasonScript.check(_crop(&"slow", "Slow", 200), LAST, FIRST)
	assert(int(verdict["verdict"]) == SeasonScript.UNSUITABLE, SeasonScript.summary_of(verdict))
	assert(SeasonScript.summary_of(verdict).contains("will not finish"), SeasonScript.summary_of(verdict))
	assert(not bool(verdict["ok"]))


func test_a_crop_that_states_no_time_to_maturity_is_unknown_never_green() -> void:
	var verdict: Dictionary = SeasonScript.check(_crop(&"unstated", "Unstated", 0), LAST, FIRST)
	assert(int(verdict["verdict"]) == SeasonScript.UNKNOWN, SeasonScript.summary_of(verdict))
	assert(verdict["findings"].is_empty(), "nothing was asked, so there is no finding to show")
	assert(String(verdict["label"]) == "no time to maturity stated", String(verdict["label"]))


func test_a_season_nobody_stated_checks_nothing() -> void:
	var verdict: Dictionary = SeasonScript.check(_crop(&"quick", "Quick", 60), 0, 0)
	assert(int(verdict["verdict"]) == SeasonScript.UNKNOWN, "not stated, so not checked")
	assert(verdict["findings"].is_empty(), "and there is no finding")
	assert(String(verdict["label"]) == SeasonScript.NO_SEASON, String(verdict["label"]))
	assert(not bool(verdict["stated"]))
	var backwards: Dictionary = SeasonScript.check(_crop(&"quick", "Quick", 60), FIRST, LAST)
	assert(int(backwards["verdict"]) == SeasonScript.UNKNOWN, "a pair the wrong way round is no season either")


func test_a_null_crop_is_unknown_rather_than_a_crash() -> void:
	var verdict: Dictionary = SeasonScript.check(null, LAST, FIRST)
	assert(int(verdict["verdict"]) == SeasonScript.UNKNOWN)
	assert(verdict["findings"].is_empty())


# --- the crops of a season --------------------------------------------------------------------


func test_only_the_food_is_listed_and_the_best_comes_first() -> void:
	var rows: Array = SeasonScript.rows(_catalogue(), LAST, FIRST)
	assert(rows.size() == 4, "the boxwood is not a crop: %d" % rows.size())
	assert(String(rows[0]["title"]) == "Quick", "the comfortable fit leads: %s" % String(rows[0]["title"]))
	assert(String(rows[0]["label"]) == "fits the season", String(rows[0]["label"]))


func test_the_rows_come_to_a_sentence_and_an_empty_list_says_so() -> void:
	var words: String = SeasonScript.describe_rows(SeasonScript.rows(_catalogue(), LAST, FIRST))
	assert(words.begins_with("4 crops:"), words)
	assert(words.contains("1 have time to finish"), words)
	assert(words.contains("1 only just fit"), words)
	assert(words.contains("1 will not finish"), words)
	assert(words.contains("1 cannot be checked"), words)
	assert(
		SeasonScript.describe_rows([]) == "no crops are recorded in this plant list",
		SeasonScript.describe_rows([])
	)


func test_a_null_catalogue_is_no_rows_rather_than_a_crash() -> void:
	assert(SeasonScript.rows(null, LAST, FIRST).is_empty())
	assert(SeasonScript.row_texts(null, LAST, FIRST).is_empty())
	assert(int(SeasonScript.counts([]).get(SeasonScript.GOOD, -1)) == 0)


func test_the_check_borrows_the_suitability_words_and_colours() -> void:
	var verdict: Dictionary = SeasonScript.check(_crop(&"slow", "Slow", 200), LAST, FIRST)
	assert(
		SeasonScript.verdict_name(int(verdict["verdict"])) == "wrong",
		SeasonScript.verdict_name(int(verdict["verdict"]))
	)
	assert(SeasonScript.colour_from(verdict) != Color(0, 0, 0, 0), "and it carries a colour")


# --- the drawing keeps it ----------------------------------------------------------------------


func test_the_drawing_keeps_the_season_and_it_survives_the_file() -> void:
	var document: DraftDocument = DocumentScript.new()
	assert(document.season_last_frost == 0 and document.season_first_frost == 0, "a new drawing states none")
	assert(document.set_season(LAST, FIRST), "stating it is a change")
	assert(not document.set_season(LAST, FIRST), "stating it again is not")
	assert(document.season_last_frost == LAST and document.season_first_frost == FIRST)
	var read: DraftDocument = DocumentScript.from_dict(document.to_dict())
	assert(read.season_last_frost == LAST and read.season_first_frost == FIRST, "and it comes back out")


func test_a_day_the_year_does_not_have_is_stored_as_not_stated() -> void:
	var document: DraftDocument = DocumentScript.new()
	assert(document.set_season(400, FIRST))
	assert(document.season_last_frost == 0, "a day outside the year is not a date")
	assert(document.season_first_frost == FIRST, "and the date that was a day is kept")
	assert(not document.set_season(400, FIRST), "stating the same not-a-day twice is not a change")


func test_an_undo_step_puts_the_season_back() -> void:
	var document: DraftDocument = DocumentScript.new()
	document.set_season(LAST, FIRST)
	var snapshot: Dictionary = document.snapshot()
	document.set_season(100, 200)
	document.restore(snapshot)
	assert(document.season_last_frost == LAST and document.season_first_frost == FIRST, "the season came back")
	# And a file written before the season existed gets "not stated" rather than a made-up one.
	var older: Dictionary = document.to_dict()
	older.erase("season")
	var legacy: DraftDocument = DocumentScript.from_dict(older)
	assert(legacy.season_last_frost == 0 and legacy.season_first_frost == 0, "no season in the file, none stated")
	assert(not legacy.set_season(0, 0), "and a drawing that states none cannot restate it as none")