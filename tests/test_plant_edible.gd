extends Node
## Food, on the species: what of a plant is eaten, when it is harvested, the family it rotates with,
## how long it takes and how much sun it needs (spec §3, extended).
##
## Every one of these fields is **optional and defaults to "not stated"**, which is the whole design:
## a catalogue of four thousand ornamental species must not become invalid the moment a food field is
## added, and a plant that says nothing about being edible is not claiming to be inedible. These tests
## hold the two halves of that - the field round-trips and refuses what is wrong, and silence is a
## real answer.

const SpeciesScript := preload("res://scripts/plant_species.gd")
const CatalogueScript := preload("res://scripts/plant_catalogue.gd")
const BrowserScript := preload("res://scripts/plant_browser.gd")


## A shrub with nothing said about food: the ordinary entry in the catalogue.
func _plain() -> PlantSpecies:
	return SpeciesScript.make(&"plain", "Buxus sempervirens", "Boxwood", 200, 150, SpeciesScript.SHRUB)


## A crop with every food field stated: tomatoes.
func _tomato() -> PlantSpecies:
	var plant: PlantSpecies = SpeciesScript.make(
		&"tomato", "Solanum lycopersicum", "Tomato", 150, 60, SpeciesScript.ANNUAL
	)
	plant.edible_parts = SpeciesScript.EAT_FRUIT
	plant.family = SpeciesScript.NIGHTSHADE
	plant.maturity_days = 75
	plant.sun_hours_tenths = 60
	for month: int in range(7, 10):
		plant.set_harvests_in(month, true)
	return plant


# --- silence is a real answer ---------------------------------------------------------------


func test_a_plant_that_says_nothing_about_food_is_still_a_valid_plant() -> void:
	var plant: PlantSpecies = _plain()
	assert(plant.is_valid(), "an ornamental is still valid: %s" % plant.problem())
	assert(not plant.is_edible(), "and it is not claiming to be food")
	assert(plant.edible_parts_text() == "", "with no parts named")
	assert(plant.harvest_text() == "", "no harvest window")
	assert(plant.family_name() == "", "no rotation family")
	assert(plant.sun_hours_text() == "", "no sun requirement")
	assert(plant.maturity_text() == "", "no time to maturity")
	assert(plant.crop_text() == "", "and nothing to say about it as food")


# --- what is eaten --------------------------------------------------------------------------


func test_the_parts_eaten_read_the_way_a_person_says_them() -> void:
	var chives: PlantSpecies = _plain()
	chives.edible_parts = SpeciesScript.EAT_LEAF | SpeciesScript.EAT_FLOWER
	assert(chives.is_edible())
	assert(chives.edible_parts_text() == "leaf, flower", chives.edible_parts_text())
	# The order is the table's own, not the order the bits were set in: a plant whose leaf is eaten
	# and whose fruit is not reads "leaf, fruit" the same way however the bits arrived.
	var both: PlantSpecies = _plain()
	both.edible_parts = SpeciesScript.EAT_FRUIT | SpeciesScript.EAT_LEAF
	assert(both.edible_parts_text() == "leaf, fruit", both.edible_parts_text())


# --- the harvest window, and the new year ---------------------------------------------------


func test_a_harvest_window_that_crosses_the_new_year_is_one_run() -> void:
	var leek: PlantSpecies = _plain()
	for month: int in [11, 12, 1, 2, 3]:
		leek.set_harvests_in(month, true)
	assert(leek.harvest_text() == "November-March", leek.harvest_text())
	assert(leek.harvests_in(1), "and January is in it")
	assert(not leek.harvests_in(6), "and June is not")
	leek.set_harvests_in(6, true)
	assert(leek.harvest_text() == "June, November-March", leek.harvest_text())
	leek.set_harvests_in(6, false)
	assert(leek.harvest_text() == "November-March", "and it comes back out")


func test_the_whole_year_is_all_year_and_a_month_out_of_range_is_ignored() -> void:
	var kale: PlantSpecies = _plain()
	for month: int in range(1, 13):
		kale.set_harvests_in(month, true)
	assert(kale.harvest_text() == "all year", kale.harvest_text())
	# A month that is not a month changes nothing, rather than setting a bit past December.
	var before: int = kale.harvest_months
	kale.set_harvests_in(13, true)
	kale.set_harvests_in(0, true)
	assert(kale.harvest_months == before, "a month nobody has is not a month")


# --- the sun it needs, and how long it takes ------------------------------------------------


func test_hours_and_days_read_as_a_person_writes_them() -> void:
	var tomato: PlantSpecies = _tomato()
	assert(tomato.sun_hours_text() == "6 hours", tomato.sun_hours_text())
	assert(is_equal_approx(tomato.sun_hours(), 6.0))
	assert(tomato.maturity_text() == "75 days", tomato.maturity_text())
	tomato.sun_hours_tenths = 65
	assert(tomato.sun_hours_text() == "6.5 hours", tomato.sun_hours_text())
	tomato.sun_hours_tenths = 10
	assert(tomato.sun_hours_text() == "1 hour", "one hour is singular: %s" % tomato.sun_hours_text())
	tomato.maturity_days = 1
	assert(tomato.maturity_text() == "1 day", tomato.maturity_text())


func test_the_crop_line_gathers_what_the_catalogue_says() -> void:
	var tomato: PlantSpecies = _tomato()
	assert(
		tomato.crop_text() == "fruit; harvested July-September; nightshade; 6 hours of sun; 75 days to maturity",
		tomato.crop_text()
	)


# --- what is refused ------------------------------------------------------------------------


func test_a_fault_is_named_rather_than_stored() -> void:
	var plant: PlantSpecies = _plain()
	plant.edible_parts = 1024
	assert(plant.problem().contains("edible parts"), plant.problem())
	plant.edible_parts = 0

	plant.harvest_months = 0x1000
	assert(plant.problem().contains("harvested"), plant.problem())
	plant.harvest_months = 0

	plant.family = &"PUMPKIN"
	assert(plant.problem().contains("crop family"), plant.problem())
	plant.family = SpeciesScript.FAMILY_NONE

	plant.maturity_days = -1
	assert(plant.problem().contains("time to maturity"), plant.problem())
	plant.maturity_days = 0

	plant.sun_hours_tenths = 250
	assert(plant.problem().contains("sun"), plant.problem())
	plant.sun_hours_tenths = 0

	assert(plant.is_valid(), "and it is sound once each fault is taken back: %s" % plant.problem())


# --- surviving the file ---------------------------------------------------------------------


func test_a_crop_survives_the_file_as_the_crop_it_was() -> void:
	var tomato: PlantSpecies = _tomato()
	var back: PlantSpecies = SpeciesScript.from_dict(tomato.to_dict())
	assert(back.edible_parts == tomato.edible_parts)
	assert(back.harvest_months == tomato.harvest_months)
	assert(back.family == tomato.family)
	assert(back.maturity_days == tomato.maturity_days)
	assert(back.sun_hours_tenths == tomato.sun_hours_tenths)
	assert(back.is_valid(), "and it is still valid: %s" % back.problem())
	# Through a real JSON round trip, where every number comes back a float.
	var text: String = JSON.stringify(tomato.to_dict())
	var parsed: Variant = JSON.parse_string(text)
	assert(parsed is Dictionary)
	var json_back: PlantSpecies = SpeciesScript.from_dict(parsed)
	assert(json_back.sun_hours_tenths == 60, "the sun need is still an integer: %d" % json_back.sun_hours_tenths)
	assert(json_back.harvest_months == tomato.harvest_months, "and the window is the same bits")
	assert(json_back.family == SpeciesScript.NIGHTSHADE)


func test_an_older_file_with_no_food_fields_reads_as_an_ordinary_plant() -> void:
	# The whole catalogue that shipped before this feature: a row with none of the new keys.
	var row: Dictionary = {
		"id": "buxus", "botanical_name": "Buxus sempervirens", "common_name": "Boxwood",
		"category": SpeciesScript.SHRUB, "height_cm": 200, "spread_cm": 150,
		"sun": SpeciesScript.FULL_SUN, "water": SpeciesScript.WATER_MEDIUM,
	}
	var plant: PlantSpecies = SpeciesScript.from_dict(row)
	assert(plant.is_valid(), "an old row is still valid: %s" % plant.problem())
	assert(not plant.is_edible())
	assert(plant.sun_hours_tenths == 0)


# --- finding food in the catalogue ----------------------------------------------------------


func _food_catalogue() -> PlantCatalogue:
	var catalogue: PlantCatalogue = CatalogueScript.make()
	catalogue.add(_plain())
	catalogue.add(_tomato())
	return catalogue


func test_the_catalogue_can_be_asked_for_food() -> void:
	var catalogue: PlantCatalogue = _food_catalogue()
	assert(catalogue.unknown_criterion({"edible": true}) == "", "edible is a criterion the filter knows")
	var found: Array[PlantSpecies] = catalogue.filter({"edible": true})
	assert(found.size() == 1, "only the tomato is food: %d" % found.size())
	assert(found[0].id == &"tomato")
	# And off, the filter is not applied at all.
	assert(catalogue.filter({}).size() == 2, "with no filter both are there")


func test_the_browser_narrows_to_food_and_says_so() -> void:
	var browser := BrowserScript.new()
	browser.bind(_food_catalogue())
	assert(browser.row_titles().size() == 2, "both plants to start")
	assert(browser.set_edible_filter(true), "the chip is set")
	assert(browser.edible_filter_on())
	assert(browser.row_titles().size() == 1, "and the grid is the one edible plant")
	assert(browser.criteria().has("edible"), "the filter it drives says so")
	browser.set_edible_filter(false)
	assert(browser.row_titles().size() == 2, "and off, both come back")
	browser.free()


func test_the_detail_pane_names_what_is_edible_about_a_plant() -> void:
	var browser := BrowserScript.new()
	browser.bind(_food_catalogue())
	browser.select(&"tomato")
	assert(browser.detail_text().contains("Food:"), browser.detail_text())
	assert(browser.detail_text().contains("nightshade"), browser.detail_text())
	browser.select(&"plain")
	assert(not browser.detail_text().contains("Food:"), "a plant with nothing to say gets no line")
	browser.free()


func test_the_detail_pane_names_what_a_plant_gives_and_what_a_person_eats() -> void:
	# The two figures a plan is worked out from. They are shown where every other species fact is
	# shown, because the yield page reads the catalogue rather than stating them itself.
	var tomato: PlantSpecies = _tomato()
	tomato.yield_per_plant_g = 2000
	tomato.need_per_person_g = 5000
	var catalogue: PlantCatalogue = CatalogueScript.make()
	catalogue.add(_plain())
	catalogue.add(tomato)
	var browser := BrowserScript.new()
	browser.bind(catalogue)
	browser.select(&"tomato")
	assert(browser.detail_text().contains("Gives:     2 kg a plant"), browser.detail_text())
	assert(browser.detail_text().contains("Eats:      5 kg a person"), browser.detail_text())
	browser.select(&"plain")
	assert(not browser.detail_text().contains("Gives:"), "a plant that states no yield gets no line")
	assert(not browser.detail_text().contains("Eats:"), "and none for what one person eats")
	browser.free()


# --- the shipped list carries a kitchen garden ----------------------------------------------


func test_the_shipped_list_carries_its_kitchen_garden() -> void:
	# The feature is only worth having if the list a person actually searches has food in it. This is
	# the one test that reads the real catalogue rather than one built here.
	var read: Dictionary = CatalogueScript.load_from("res://data/plants/nursery_list.json")
	assert(bool(read["ok"]), "the shipped list loads: %s" % String(read["reason"]))
	var catalogue: PlantCatalogue = read["catalogue"]
	var food: Array[PlantSpecies] = catalogue.filter({"edible": true})
	assert(food.size() >= 10, "there is food in the list: %d" % food.size())
	var chives: PlantSpecies = catalogue.get_species(&"allium-schoenoprasum")
	assert(chives != null and chives.is_edible(), "chives are food")
	assert(chives.edible_parts_text() == "leaf, flower", chives.edible_parts_text())
	assert(chives.family == SpeciesScript.ALLIUM, "and they rotate as an allium")
	assert(chives.harvest_text() == "April-October", chives.harvest_text())
	assert(chives.sun_hours_text() == "6 hours", chives.sun_hours_text())
	# Every one of them is a whole species the model still accepts: adding food to the list must not
	# have made one of them unsound.
	assert(catalogue.is_sound(), "the list is sound: %s" % " | ".join(catalogue.problems()))