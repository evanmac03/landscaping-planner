extends Node
## How much to plant: how many plants feed a given number of people, and the hand-off to a nursery order.
##
## The arithmetic is the module's alone, so this drives the module directly - no window, no drawing and
## no screen. A species is made through `PlantSpecies.make`, the way the catalogue makes one.

const YieldScript := preload("res://scripts/plant_yield.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")
const CatalogueScript := preload("res://scripts/plant_catalogue.gd")
const OrderScript := preload("res://scripts/biz/plant_order.gd")
const BookScript := preload("res://scripts/biz/cost_book.gd")

const SEED := "res://data/biz/costbook.json"


func _crop(species_id: StringName, name: String, gives: int, eats: int) -> PlantSpecies:
	var crop: PlantSpecies = SpeciesScript.make(species_id, name, "", 40, 30, SpeciesScript.ANNUAL)
	crop.edible_parts = SpeciesScript.EAT_LEAF
	crop.yield_per_plant_g = gives
	crop.need_per_person_g = eats
	return crop


func _catalogue() -> PlantCatalogue:
	var catalogue: PlantCatalogue = CatalogueScript.make()
	catalogue.add(_crop(&"tomato", "Tomato", 2000, 5000))
	catalogue.add(_crop(&"herb", "Herb", 100, 100))
	catalogue.add(_crop(&"thyme", "Thyme", 0, 300))       # no yield stated
	catalogue.add(_crop(&"sorrel", "Sorrel", 3000, 0))    # no amount per person stated
	catalogue.add(SpeciesScript.make(&"boxwood", "Buxus sempervirens", "Box", 60, 60, SpeciesScript.SHRUB))
	return catalogue


func _book() -> CostBook:
	var read: Dictionary = BookScript.load_from(SEED)
	assert(bool(read["ok"]), "the starter book loads: %s" % String(read["reason"]))
	return read["book"]


# --- weights -------------------------------------------------------------------------------


func test_a_weight_reads_the_way_a_person_writes_it() -> void:
	assert(SpeciesScript.weight_text(450) == "450 g", SpeciesScript.weight_text(450))
	assert(SpeciesScript.weight_text(1000) == "1 kg", SpeciesScript.weight_text(1000))
	assert(SpeciesScript.weight_text(1500) == "1.5 kg", SpeciesScript.weight_text(1500))
	assert(SpeciesScript.weight_text(2000) == "2 kg", SpeciesScript.weight_text(2000))
	assert(SpeciesScript.weight_text(0) == "", "not stated is not a weight")


func test_an_amount_is_more_than_nothing_and_no_more_than_a_tonne() -> void:
	assert(YieldScript.is_grams(1), "a gram is an amount")
	assert(YieldScript.is_grams(1000000), "a tonne is the heaviest that makes sense")
	assert(not YieldScript.is_grams(0), "nothing is not an amount")
	assert(not YieldScript.is_grams(1000001), "and neither is more than a tonne")


func test_a_fact_missing_is_named_rather_than_guessed() -> void:
	var no_yield: PlantSpecies = _crop(&"thyme", "Thyme", 0, 300)
	assert(not YieldScript.can_answer(no_yield), "a crop with no stated yield cannot be worked out")
	assert(YieldScript.reason(no_yield) == YieldScript.NO_YIELD, YieldScript.reason(no_yield))
	var no_need: PlantSpecies = _crop(&"sorrel", "Sorrel", 3000, 0)
	assert(YieldScript.reason(no_need) == YieldScript.NO_NEED, YieldScript.reason(no_need))
	assert(YieldScript.reason(_crop(&"tomato", "Tomato", 2000, 5000)) == "", "a crop with both is fine")


# --- how many plants -----------------------------------------------------------------------


func test_plants_are_the_need_divided_by_the_yield() -> void:
	var tomato: PlantSpecies = _crop(&"tomato", "Tomato", 2000, 5000)
	assert(YieldScript.plants_for(tomato, 4, 0) == 10, "4 x 5000 g over 2000 g a plant is 10")


func test_the_count_is_rounded_up_because_half_a_plant_is_not_a_plant() -> void:
	var tight: PlantSpecies = _crop(&"tight", "Tight", 3000, 5000)
	# 4 x 5000 / 3000 = 6.67 -> 7
	assert(YieldScript.plants_for(tight, 4, 0) == 7, str(YieldScript.plants_for(tight, 4, 0)))


func test_the_spare_is_added_on_top_and_rounded_up_too() -> void:
	var tomato: PlantSpecies = _crop(&"tomato", "Tomato", 2000, 5000)
	assert(YieldScript.plants_for(tomato, 4, 0) == 10, "no spare is the bare number")
	assert(YieldScript.plants_for(tomato, 4, 10) == 11, "a tenth more is 11")
	assert(YieldScript.plants_for(tomato, 4, 100) == 20, "a spare of the whole again doubles it")


func test_nobody_to_feed_or_a_fact_missing_is_no_plants() -> void:
	assert(YieldScript.plants_for(_crop(&"thyme", "Thyme", 0, 300), 4) == 0, "nothing to divide")
	assert(YieldScript.plants_for(_crop(&"tomato", "Tomato", 2000, 5000), 0) == 0, "nobody to feed")


func test_the_need_is_the_share_of_one_person_times_the_household() -> void:
	var tomato: PlantSpecies = _crop(&"tomato", "Tomato", 2000, 5000)
	assert(YieldScript.need_grams(tomato, 4) == 20000, "%d" % YieldScript.need_grams(tomato, 4))
	assert(YieldScript.need_grams(_crop(&"sorrel", "Sorrel", 3000, 0), 4) == 0, "an unstated share is nothing")


# --- the plan ------------------------------------------------------------------------------


func test_the_plan_is_food_only_and_sorted() -> void:
	var rows: Array[Dictionary] = YieldScript.plan(_catalogue(), 4, 0)
	assert(rows.size() == 4, "the boxwood is not a crop: %d" % rows.size())
	assert(String(rows[0]["title"]) == "Herb", "the plan is in title order: %s" % String(rows[0]["title"]))
	for row: Dictionary in rows:
		assert(String(row["title"]) != "Buxus sempervirens - Box", "no shrub in a food plan")


func test_a_crop_that_cannot_be_worked_out_is_a_row_naming_what_is_missing() -> void:
	var rows: Array[Dictionary] = YieldScript.plan(_catalogue(), 4, 0)
	var thyme: Dictionary = {}
	for row: Dictionary in rows:
		if String(row["id"]) == "thyme":
			thyme = row
	assert(not thyme.is_empty(), "the crop is still listed")
	assert(int(thyme["plants"]) == 0, "with no number")
	assert(not bool(thyme["stated"]), "and marked as not worked out")
	assert(String(thyme["note"]) == YieldScript.NO_YIELD, String(thyme["note"]))


func test_the_rows_read_as_lines_and_summarise() -> void:
	var catalogue: PlantCatalogue = _catalogue()
	var texts: Array[String] = YieldScript.row_texts(catalogue, 4, 0)
	assert(texts.size() == 4)
	assert(texts[0] == "Herb: plant 4", texts[0])
	var summary: String = YieldScript.describe_rows(YieldScript.plan(catalogue, 4, 0))
	assert(summary == "4 crops: 2 can be worked out, 2 cannot be told.", summary)


func test_the_counts_and_the_total_add_up() -> void:
	var rows: Array[Dictionary] = YieldScript.plan(_catalogue(), 4, 0)
	var count: Dictionary = YieldScript.counts(rows)
	assert(int(count["worked"]) == 2, str(count))
	assert(int(count["unstated"]) == 2, str(count))
	# Herb 4 plants + Tomato 10 plants
	assert(YieldScript.total_plants(rows) == 14, str(YieldScript.total_plants(rows)))


func test_the_household_reads_as_a_number_of_people() -> void:
	assert(YieldScript.people_text(1) == "1 person", YieldScript.people_text(1))
	assert(YieldScript.people_text(4) == "4 people", YieldScript.people_text(4))


func test_the_feed_line_says_what_the_plan_comes_to() -> void:
	var rows: Array[Dictionary] = YieldScript.plan(_catalogue(), 4, 10)
	var words: String = YieldScript.feed_text(rows, 4, 10)
	assert(words.begins_with("To feed 4 people"), words)
	assert(words.contains("plants across 2 kinds"), words)
	assert(words.contains("10% spare"), words)


func test_a_plan_that_works_nothing_out_says_so() -> void:
	var only_thyme: PlantCatalogue = CatalogueScript.make()
	only_thyme.add(_crop(&"thyme", "Thyme", 0, 300))
	var rows: Array[Dictionary] = YieldScript.plan(only_thyme, 4, 0)
	assert(
		YieldScript.feed_text(rows, 4, 0) == "nothing on this list can be worked out into a number of plants",
		YieldScript.feed_text(rows, 4, 0)
	)


# --- the hand-off to a nursery order ---------------------------------------------------------


func test_the_hand_off_is_the_shape_a_planting_schedule_writes() -> void:
	var catalogue: PlantCatalogue = _catalogue()
	var orders: Array[Dictionary] = YieldScript.order_rows(YieldScript.plan(catalogue, 4, 0), catalogue)
	assert(orders.size() == 2, "only what worked out is ordered: %d" % orders.size())
	for row: Dictionary in orders:
		for key: String in [
			"id", "count", "botanical_name", "common_name", "cultivar", "category", "category_name",
			"spread_cm", "height_cm",
		]:
			assert(row.has(key), "the row is missing %s" % key)


func test_what_could_not_be_worked_out_is_left_off_the_order() -> void:
	var catalogue: PlantCatalogue = _catalogue()
	var orders: Array[Dictionary] = YieldScript.order_rows(YieldScript.plan(catalogue, 4, 0), catalogue)
	for row: Dictionary in orders:
		assert(String(row["id"]) != "thyme", "a crop with no number is not an order line")
		assert(String(row["id"]) != "sorrel", "and nor is one with no share stated")


func test_the_hand_off_prices_through_the_nursery_order() -> void:
	var catalogue: PlantCatalogue = _catalogue()
	var rows: Array[Dictionary] = YieldScript.plan(catalogue, 4, 0)
	var orders: Array[Dictionary] = YieldScript.order_rows(rows, catalogue)
	var priced: Dictionary = OrderScript.plan(orders, _book())
	assert(int(priced["plants"]) == YieldScript.total_plants(rows), "every plant reaches the order")
	assert(int(priced["lines"].size()) == int(YieldScript.counts(rows)["worked"]), "one line per kind")
	assert(int(priced["unpriced"]) == 0, "the starter book prices a seed crop: %s" % str(priced["problems"]))
	assert((priced["total"] as Money).is_valid(), "and the order comes to a real total")