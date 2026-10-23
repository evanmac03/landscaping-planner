extends Node
## What is ready when: the year as twelve lists of crops (the harvest calendar).
##
## The one fact under test is `PlantSpecies.harvest_months`, read through `harvests_in`. What these
## tests hold down is that the calendar is honest about what it does not know: a crop with no window is
## on no month and is counted apart, an empty month says so rather than reading as a fault, and a window
## that crosses the new year is ready on both sides of it.

const CalendarScript := preload("res://scripts/harvest_calendar.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")
const CatalogueScript := preload("res://scripts/plant_catalogue.gd")


## A crop cut in the months given (1..12).
func _crop(id: StringName, name: String, months: Array, parts: int = SpeciesScript.EAT_LEAF) -> PlantSpecies:
	# No common name, so `display_name` is the plain name rather than "Botanical - Common".
	var plant: PlantSpecies = SpeciesScript.make(id, name, "", 60, 40, SpeciesScript.ANNUAL)
	plant.edible_parts = parts
	for month: int in months:
		plant.set_harvests_in(month, true)
	return plant


## A plant nobody eats: on no month, however its bits read.
func _boxwood() -> PlantSpecies:
	return SpeciesScript.make(&"buxus", "Buxus sempervirens", "Boxwood", 200, 150)


func _catalogue() -> PlantCatalogue:
	var catalogue: PlantCatalogue = CatalogueScript.make()
	catalogue.add(_boxwood())
	catalogue.add(_crop(&"basil", "Basil", [6, 7], SpeciesScript.EAT_LEAF))       # June-July
	catalogue.add(_crop(&"kale", "Kale", [11, 12, 1, 2, 3], SpeciesScript.EAT_LEAF))  # Nov-March
	catalogue.add(_crop(&"beet", "Beetroot", [6], SpeciesScript.EAT_ROOT))        # June only
	return catalogue


# --- months -------------------------------------------------------------------------------


func test_a_month_reads_the_way_a_person_says_it() -> void:
	assert(CalendarScript.month_name(1) == "January")
	assert(CalendarScript.month_name(6) == "June")
	assert(CalendarScript.month_name(12) == "December")
	assert(CalendarScript.month_name(0) == "", "nought is not a month")
	assert(CalendarScript.month_name(13) == "", "nor is thirteen")
	assert(CalendarScript.is_month(1) and CalendarScript.is_month(12))
	assert(not CalendarScript.is_month(0) and not CalendarScript.is_month(13))


# --- what is ready ------------------------------------------------------------------------


func test_only_the_food_is_ready_and_only_in_its_own_months() -> void:
	var basil: PlantSpecies = _crop(&"basil", "Basil", [6, 7])
	assert(CalendarScript.ready(basil, 6), "basil is ready in June")
	assert(CalendarScript.ready(basil, 7), "and in July")
	assert(not CalendarScript.ready(basil, 5), "but not in May")
	assert(not CalendarScript.ready(_boxwood(), 6), "a boxwood is never a harvest")
	assert(not CalendarScript.ready(null, 6), "and nothing at all is nothing")


func test_a_window_that_crosses_the_new_year_is_ready_on_both_sides() -> void:
	var kale: PlantSpecies = _crop(&"kale", "Kale", [11, 12, 1, 2, 3])
	assert(CalendarScript.ready(kale, 12), "kale stands into December")
	assert(CalendarScript.ready(kale, 1), "and is cut again in the new year")
	assert(CalendarScript.ready(kale, 3))
	assert(not CalendarScript.ready(kale, 6), "and it is over by summer")
	assert(kale.harvest_text() == "November-March", kale.harvest_text())


func test_the_crops_of_a_month_come_in_botanical_order() -> void:
	var names: Array[String] = []
	for plant: PlantSpecies in CalendarScript.crops_in(_catalogue(), 6):
		names.append(plant.display_name())
	assert(names == ["Basil", "Beetroot"], str(names))
	var jan: Array[String] = []
	for plant: PlantSpecies in CalendarScript.crops_in(_catalogue(), 1):
		jan.append(plant.display_name())
	assert(jan == ["Kale"], "only the winter crop is ready in January: %s" % str(jan))


func test_the_row_line_is_the_rows_own_label() -> void:
	var lines: Array[String] = CalendarScript.row_texts(_catalogue(), 6)
	assert(lines.size() == 2, str(lines))
	assert(lines[0] == "Basil: leaf", lines[0])
	assert(lines[1] == "Beetroot: root", lines[1])
	var rows: Array[Dictionary] = CalendarScript.rows(_catalogue(), 6)
	assert(String(rows[0]["window"]) == "June-July", String(rows[0]["window"]))


# --- the year -----------------------------------------------------------------------------


func test_the_counts_are_twelve_numbers_one_a_month() -> void:
	var counts: Array[int] = CalendarScript.counts(_catalogue())
	assert(counts.size() == 12, "a year of months: %d" % counts.size())
	assert(counts[0] == 1, "January has the kale: %d" % counts[0])
	assert(counts[5] == 2, "June has basil and beetroot: %d" % counts[5])
	assert(counts[6] == 1, "July has basil: %d" % counts[6])
	assert(counts[3] == 0, "April has nothing: %d" % counts[3])
	assert(CalendarScript.month_count(_catalogue(), 6) == 2)
	assert(CalendarScript.month_count(_catalogue(), 0) == 0, "nought is not a month")


func test_the_busiest_month_is_the_fullest_and_ties_go_early() -> void:
	# January, March and June all hold one; June holds two. The busiest is June, and a tie would be the
	# earlier month, which is what stops the answer depending on how anything was walked.
	assert(int(CalendarScript.busiest(_catalogue())["month"]) == 6)
	assert(int(CalendarScript.busiest(_catalogue())["count"]) == 2)
	assert(int(CalendarScript.busiest(CatalogueScript.make())["month"]) == 0, "nothing ready, no month")


func test_the_ready_span_words_the_run_the_way_a_bloom_is_worded() -> void:
	# The whole catalogue is ready January-March and June-July, which is the one wording a run of months
	# uses everywhere it is said.
	var span: Dictionary = CalendarScript.ready_span(_catalogue())
	assert(int(span["first"]) == 1, "January is the first: %d" % int(span["first"]))
	assert(int(span["last"]) == 12, "the winter crop reaches December: %d" % int(span["last"]))
	assert(span["months"] == [1, 2, 3, 6, 7, 11, 12], str(span["months"]))
	assert(
		SpeciesScript.months_run_text(int(span["bits"])) == "June-July, November-March",
		SpeciesScript.months_run_text(int(span["bits"]))
	)
	assert(int(CalendarScript.ready_span(CatalogueScript.make())["first"]) == 0, "nothing ready, no span")


func test_a_crop_with_no_window_is_counted_apart_rather_than_unsuitable() -> void:
	var catalogue: PlantCatalogue = _catalogue()
	var mint: PlantSpecies = _crop(&"mint", "Mint", [])   # edible, but no months
	catalogue.add(mint)
	var missing: Array[PlantSpecies] = CalendarScript.unstated(catalogue)
	assert(missing.size() == 1, "one crop says nothing: %d" % missing.size())
	assert(missing[0].display_name() == "Mint")
	for month in range(1, 13):
		assert(not CalendarScript.ready(mint, month), "a crop with no window is on no month")
	var line: String = CalendarScript.unstated_line(catalogue)
	assert(line.begins_with("1 crop says nothing"), line)
	assert(line.contains("Mint"), line)
	assert(
		CalendarScript.unstated_line(_catalogue()) == "",
		"and a list where every crop has a window has nothing to admit"
	)


func test_the_year_reads_as_one_sentence_and_says_what_it_is_missing() -> void:
	var line: String = CalendarScript.year_text(_catalogue())
	assert(line.contains("3 crops"), line)
	assert(line.contains("ready"), line)
	assert(line.contains("June-July"), line)
	assert(line.contains("November-March"), line)
	var empty: PlantCatalogue = CatalogueScript.make()
	empty.add(_boxwood())
	assert(CalendarScript.year_text(empty) == CalendarScript.NO_FOOD, CalendarScript.year_text(empty))
	var undated: PlantCatalogue = CatalogueScript.make()
	undated.add(_crop(&"mint", "Mint", []))
	assert(CalendarScript.year_text(undated) == CalendarScript.NONE_RECORDED, CalendarScript.year_text(undated))
	assert(CalendarScript.year_text(null) == CalendarScript.NO_FOOD)


# --- saying it ----------------------------------------------------------------------------


func test_a_month_with_nothing_ready_says_so_rather_than_failing() -> void:
	var line: String = CalendarScript.describe_rows(CalendarScript.rows(_catalogue(), 4), 4)
	assert(line == "nothing is recorded as ready in April.", line)
	assert(
		CalendarScript.describe_rows(CalendarScript.rows(_catalogue(), 6), 6) == "2 crops ready in June.",
		CalendarScript.describe_rows(CalendarScript.rows(_catalogue(), 6), 6)
	)
	assert(CalendarScript.describe_rows([], 0) == "no month was chosen")


func test_a_null_catalogue_is_no_rows_rather_than_a_crash() -> void:
	assert(CalendarScript.rows(null, 6).is_empty())
	assert(CalendarScript.crops_in(null, 6).is_empty())
	assert(CalendarScript.unstated(null).is_empty())
	assert((CalendarScript.counts(null) as Array[int]).size() == 12)