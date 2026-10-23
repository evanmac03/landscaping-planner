extends Node
## When to sow, when it is ready, and how to keep it coming: the sowing calendar's arithmetic.
##
## The arithmetic is the module's alone, so this drives the module directly - no window, no drawing and
## no screen. A species is made through `PlantSpecies.make`, the way the catalogue makes one.

const PlannerScript := preload("res://scripts/sowing_planner.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")
const CatalogueScript := preload("res://scripts/plant_catalogue.gd")

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
	catalogue.add(_crop(&"slow", "Slow", 200))         # too slow to sow anywhere in the season
	catalogue.add(_crop(&"unstated", "Unstated", 0))   # no time to maturity recorded
	catalogue.add(SpeciesScript.make(&"boxwood", "Buxus sempervirens", "Box", 60, 60, SpeciesScript.SHRUB))
	return catalogue


# --- days and dates -------------------------------------------------------------------------


func test_a_day_is_a_day_of_the_year() -> void:
	assert(PlannerScript.is_day(140), "140 is a day")
	assert(PlannerScript.is_day(1) and PlannerScript.is_day(366), "the ends of the year are days")
	assert(not PlannerScript.is_day(0), "zero is not a day: it is not stated")
	assert(not PlannerScript.is_day(367), "and neither is a day the year does not have")


func test_a_day_reads_as_a_date() -> void:
	assert(PlannerScript.day_words(LAST) == "20 May", PlannerScript.day_words(LAST))
	assert(PlannerScript.day_words(FIRST) == "7 October", PlannerScript.day_words(FIRST))
	assert(PlannerScript.day_words(0) == "", "not stated is not a date")
	assert(PlannerScript.day_words(400) == "", "and neither is a day the year does not have")


# --- the sowing window ----------------------------------------------------------------------


func test_the_last_day_to_sow_is_the_frost_less_the_time_to_maturity() -> void:
	assert(PlannerScript.last_sow_day(FIRST, 60) == 220, "7 October less 60 days is 8 August")
	assert(PlannerScript.last_sow_day(FIRST, 0) == 0, "no time to maturity is no last day")
	assert(PlannerScript.last_sow_day(0, 60) == 0, "and no frost is no last day either")


func test_the_window_is_the_last_frost_through_the_last_safe_day() -> void:
	var window: Dictionary = PlannerScript.sow_window(LAST, FIRST, 60)
	assert(bool(window["stated"]), "a crop that fits has a window")
	assert(int(window["first"]) == LAST, "the earliest safe sowing is the last frost")
	assert(int(window["last"]) == 220, "and the last is 8 August")
	assert(int(window["days"]) == 81, "which is 81 days to choose from: %d" % int(window["days"]))


func test_a_crop_too_slow_to_sow_has_no_window_and_says_so() -> void:
	var window: Dictionary = PlannerScript.sow_window(LAST, FIRST, 200)
	assert(not bool(window["stated"]), "a crop that takes longer than the season has nowhere to be sown")
	assert(String(window["reason"]) == PlannerScript.NO_WINDOW, String(window["reason"]))


func test_no_season_or_no_maturity_is_no_window() -> void:
	assert(
		String(PlannerScript.sow_window(0, 0, 60)["reason"]) == PlannerScript.NO_SEASON,
		"a drawing with no season has no window"
	)
	assert(
		String(PlannerScript.sow_window(LAST, FIRST, 0)["reason"]) == PlannerScript.NO_MATURITY,
		"and a crop with no time to maturity has none either"
	)


func test_the_window_reads_as_a_phrase() -> void:
	var words: String = PlannerScript.window_text(LAST, FIRST, 60)
	assert(words.contains("20 May") and words.contains("August"), words)
	assert(
		PlannerScript.window_text(LAST, FIRST, 200) == PlannerScript.NO_WINDOW,
		"a crop with no window says why rather than showing a date"
	)


func test_a_harvest_with_no_room_to_move_is_a_window_of_one_day() -> void:
	# A crop whose last safe day lands exactly on the last frost has a single sowing day.
	var words: String = PlannerScript.window_text(LAST, FIRST, FIRST - LAST)
	assert(words.begins_with("sow on"), words)
	assert(not words.contains(" to "), "a one-day window is not a span: %s" % words)


func test_a_sowing_plus_its_days_is_the_harvest() -> void:
	assert(PlannerScript.ready_day(LAST, 60) == 200, "20 May plus 60 days is 19 July")
	assert(PlannerScript.ready_day(0, 60) == 0, "no sowing day is no harvest day")
	assert(PlannerScript.ready_day(LAST, 0) == 0, "and no time to maturity is no harvest day")


# --- one crop against one sowing day --------------------------------------------------------


func test_a_quick_crop_sown_after_the_frost_ripens_in_time() -> void:
	var answer: Dictionary = PlannerScript.check(_crop(&"quick", "Quick", 60), LAST, FIRST, LAST)
	assert(int(answer["verdict"]) == PlannerScript.GOOD, PlannerScript.verdict_name(int(answer["verdict"])))
	assert(String(answer["label"]) == "ripens in time", String(answer["label"]))
	assert(int(answer["ready"]) == 200, "ready on 19 July")
	assert(String(answer["summary"]).contains("ready about 19 July"), String(answer["summary"]))


func test_a_crop_that_finishes_only_just_is_tolerated() -> void:
	var answer: Dictionary = PlannerScript.check(_crop(&"thin", "Thin", 130), LAST, FIRST, LAST)
	assert(int(answer["verdict"]) == PlannerScript.TOLERATED, PlannerScript.verdict_name(int(answer["verdict"])))
	assert(String(answer["label"]) == "only just ripens", String(answer["label"]))


func test_a_crop_that_ripens_after_the_frost_is_refused() -> void:
	var answer: Dictionary = PlannerScript.check(_crop(&"slow", "Slow", 200), LAST, FIRST, LAST)
	assert(int(answer["verdict"]) == PlannerScript.UNSUITABLE, PlannerScript.verdict_name(int(answer["verdict"])))
	assert(String(answer["label"]) == "ripens too late", String(answer["label"]))


func test_a_sowing_before_the_last_frost_is_a_gamble_not_a_failure() -> void:
	var answer: Dictionary = PlannerScript.check(_crop(&"quick", "Quick", 60), LAST, FIRST, 100)
	assert(int(answer["verdict"]) == PlannerScript.TOLERATED, "a crop sown early is a gamble")
	assert(String(answer["label"]) == "sown before the last frost", String(answer["label"]))


func test_questions_nobody_answered_are_skipped_rather_than_green() -> void:
	var unstated: Dictionary = PlannerScript.check(_crop(&"unstated", "Unstated", 0), LAST, FIRST, LAST)
	assert(int(unstated["verdict"]) == PlannerScript.UNKNOWN, "no time to maturity is nothing to work out")
	assert(String(unstated["label"]) == PlannerScript.NO_MATURITY, String(unstated["label"]))
	assert((unstated["findings"] as Array).is_empty(), "and no finding at all")

	var no_season: Dictionary = PlannerScript.check(_crop(&"quick", "Quick", 60), 0, 0, LAST)
	assert(int(no_season["verdict"]) == PlannerScript.UNKNOWN, "a drawing with no season checks nothing")
	assert(String(no_season["label"]) == PlannerScript.NO_SEASON, String(no_season["label"]))

	var no_day: Dictionary = PlannerScript.check(_crop(&"quick", "Quick", 60), LAST, FIRST, 0)
	assert(int(no_day["verdict"]) == PlannerScript.UNKNOWN, "a sowing date that is not a day asks nothing")


# --- succession -----------------------------------------------------------------------------


func test_a_succession_is_sowings_that_still_have_time_to_ripen() -> void:
	var days: Array[int] = PlannerScript.sowings(LAST, LAST, FIRST, 60, 21)
	assert(days.size() == 4, "four sowings: %s" % str(days))
	assert(days[0] == 140 and days[1] == 161 and days[2] == 182 and days[3] == 203, str(days))


func test_a_succession_never_sows_later_than_a_crop_can_ripen() -> void:
	var days: Array[int] = PlannerScript.sowings(LAST, LAST, FIRST, 60, 21)
	assert(days[days.size() - 1] <= 220, "the last sowing still ripens before the frost")
	assert(PlannerScript.sowings(LAST, LAST, FIRST, 200, 21).is_empty(), "a crop too slow has no succession")
	assert(PlannerScript.sowings(LAST, 0, 0, 60, 21).is_empty(), "and no season is no succession")


func test_a_succession_is_a_fact_a_page_can_read() -> void:
	var plan: Dictionary = PlannerScript.succession(_crop(&"quick", "Quick", 60), LAST, FIRST, LAST, 21)
	assert(int(plan["count"]) == 4, "four sowings: %d" % int(plan["count"]))
	assert(int(plan["first_sow"]) == LAST and int(plan["last_ready"]) == 203 + 60, "the span is the whole run")
	assert(
		int(PlannerScript.succession(_crop(&"slow", "Slow", 200), LAST, FIRST, LAST, 21)["count"]) == 0,
		"a crop with no window has no sowings"
	)


func test_a_succession_reads_as_a_sentence() -> void:
	var words: String = PlannerScript.succession_text(_crop(&"quick", "Quick", 60), LAST, FIRST, LAST, 21)
	assert(words.contains("every 21 days"), words)
	assert(words.contains("4 sowings"), words)
	assert(words.contains("20 May") and words.contains("July"), words)


func test_a_single_sowing_is_said_as_one() -> void:
	var words: String = PlannerScript.succession_text(_crop(&"quick", "Quick", 60), LAST, FIRST, LAST, 120)
	assert(words.contains("one sowing"), words)
	assert(not words.contains("every"), "one sowing is not a rhythm: %s" % words)


# --- the crops of a sowing day --------------------------------------------------------------


func test_the_rows_are_food_only_best_first() -> void:
	var rows: Array[Dictionary] = PlannerScript.rows(_catalogue(), LAST, FIRST, LAST)
	assert(rows.size() == 4, "the boxwood is not a crop: %d" % rows.size())
	assert(String(rows[0]["title"]) == "Quick", "the best answer leads: %s" % String(rows[0]["title"]))
	for row: Dictionary in rows:
		assert(String(row["title"]) != "Buxus sempervirens - Box", "no shrub among the sowings")


func test_the_rows_read_as_lines_and_summarise() -> void:
	var texts: Array[String] = PlannerScript.row_texts(_catalogue(), LAST, FIRST, LAST)
	assert(texts.size() == 4)
	assert(texts[0].begins_with("Quick:"), texts[0])
	var summary: String = PlannerScript.describe_rows(PlannerScript.rows(_catalogue(), LAST, FIRST, LAST))
	assert(summary.contains("ripen in time"), summary)
	assert(summary.contains("too late"), "the slow crop is named as too late: %s" % summary)
	assert(summary.contains("cannot be checked"), summary)


func test_a_list_with_no_food_says_so() -> void:
	assert(
		PlannerScript.describe_rows([] as Array[Dictionary]) == "no crops are recorded in this plant list",
		"an empty list is said plainly"
	)