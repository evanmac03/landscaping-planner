extends Node
## Whether a food crop gets the sun it needs where it is going (idea D).
##
## Three facts are joined here and these tests hold each of them down: the hours a stated light level
## stands for, the crop's own requirement, and the site's own longest day - which is the ceiling no
## spot can beat. The rule that decides the verdict is the suitability check's rule, in the suitability
## check's four words, and these tests read it the same way.

const CropSunScript := preload("res://scripts/crop_sun.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")
const ProfileScript := preload("res://scripts/terrain_profile.gd")
const CatalogueScript := preload("res://scripts/plant_catalogue.gd")
const SunStudyScript := preload("res://scripts/vis/sun_study.gd")
const SuitabilityScript := preload("res://scripts/plant_suitability.gd")


## A crop wanting some number of hours of sun.
func _crop(hours_tenths: int) -> PlantSpecies:
	var plant: PlantSpecies = SpeciesScript.make(
		&"crop", "Solanum lycopersicum", "Tomato", 150, 60, SpeciesScript.ANNUAL
	)
	plant.edible_parts = SpeciesScript.EAT_FRUIT
	plant.family = SpeciesScript.NIGHTSHADE
	plant.sun_hours_tenths = hours_tenths
	return plant


func _place(level: int) -> TerrainProfile:
	return ProfileScript.of("sun", level)


## A garden well north, so its midsummer day is long: the site the whole feature is about.
func _site() -> Dictionary:
	return SunStudyScript.site(45.4, -75.7, -5.0)


# --- the hours a stated level stands for ----------------------------------------------------


func test_each_stated_light_level_stands_for_a_span_of_hours() -> void:
	assert(CropSunScript.band(SpeciesScript.FULL_SUN) == Vector2(6.0, 24.0))
	assert(CropSunScript.band(SpeciesScript.PART_SHADE) == Vector2(3.0, 6.0))
	assert(CropSunScript.band(SpeciesScript.FULL_SHADE) == Vector2(0.0, 3.0))
	assert(CropSunScript.band(0) == Vector2.ZERO, "a level nobody has spans nothing")
	assert(CropSunScript.band_text(SpeciesScript.FULL_SUN) == "6 hours or more")
	assert(CropSunScript.band_text(SpeciesScript.PART_SHADE) == "3 to 6 hours")
	assert(CropSunScript.band_text(SpeciesScript.FULL_SHADE) == "under 3 hours")
	assert(CropSunScript.band_text(0) == "", "and nobody's level has no words")


# --- the check ------------------------------------------------------------------------------


func test_a_six_hour_crop_is_right_in_full_sun_and_thin_in_part_shade() -> void:
	var crop: PlantSpecies = _crop(60)
	var sunlit: Dictionary = CropSunScript.check(crop, _place(SpeciesScript.FULL_SUN))
	assert(int(sunlit["verdict"]) == CropSunScript.GOOD, CropSunScript.summary_of(sunlit))
	assert(sunlit["label"] == "enough sun", String(sunlit["label"]))
	var shaded: Dictionary = CropSunScript.check(crop, _place(SpeciesScript.PART_SHADE))
	assert(int(shaded["verdict"]) == CropSunScript.TOLERATED, CropSunScript.summary_of(shaded))
	assert(shaded["label"].contains("wants"), String(shaded["label"]))
	var dark: Dictionary = CropSunScript.check(crop, _place(SpeciesScript.FULL_SHADE))
	assert(int(dark["verdict"]) == CropSunScript.UNSUITABLE, CropSunScript.summary_of(dark))
	assert(String(dark["summary"]).contains("6 hours"), String(dark["summary"]))


func test_a_place_that_says_nothing_about_the_sun_is_unknown_not_green() -> void:
	var crop: PlantSpecies = _crop(60)
	var verdict: Dictionary = CropSunScript.check(crop, ProfileScript.make(), _site())
	assert(int(verdict["verdict"]) == CropSunScript.UNKNOWN, CropSunScript.summary_of(verdict))
	assert(verdict["label"] == "the plan doesn't say the sun", String(verdict["label"]))
	assert(CropSunScript.colour_from(verdict) != SuitabilityScript.GOOD_COLOUR, "and it is drawn grey, not green")


func test_a_crop_that_states_no_requirement_has_nothing_to_check() -> void:
	var crop: PlantSpecies = _crop(0)
	var verdict: Dictionary = CropSunScript.check(crop, _place(SpeciesScript.FULL_SUN), _site())
	assert(int(verdict["verdict"]) == CropSunScript.UNKNOWN, "not checked, so not green")
	assert(verdict["findings"].is_empty(), "and there is no finding to show")
	assert(String(verdict["summary"]).contains("does not say how much sun"), String(verdict["summary"]))
	assert(verdict["label"] == "no sun stated", String(verdict["label"]))


# --- the site's own ceiling -----------------------------------------------------------------


func test_the_longest_day_is_the_ceiling_and_it_grows_with_latitude() -> void:
	var tropics: Dictionary = CropSunScript.longest_day(SunStudyScript.site(0.0, 0.0, 0.0))
	assert(float(tropics["hours"]) > 11.9 and float(tropics["hours"]) < 12.2,
		"on the equator the longest day is a little over twelve hours: %.2f" % float(tropics["hours"]))
	var north: Dictionary = CropSunScript.longest_day(_site())
	assert(float(north["hours"]) > 14.0, "and at 45 north it is long: %.2f" % float(north["hours"]))
	assert(CropSunScript.season_line(_site()).contains("15"), CropSunScript.season_line(_site()))
	assert(CropSunScript.longest_day({}).get("hours", -1.0) == 0.0, "no site, no ceiling")


func test_a_crop_the_site_could_never_give_is_refused_outright() -> void:
	var longest: Dictionary = CropSunScript.longest_day(_site())
	var hours: float = float(longest["hours"])
	# One hour less than the site's own longest day is achievable in principle; one hour more is not,
	# however sunny the bed, because no bed is outdoors after the sun has set.
	var reachable: Dictionary = CropSunScript.check(
		_crop(int((hours - 1.0) * 10.0)), _place(SpeciesScript.FULL_SUN), _site()
	)
	assert(int(reachable["verdict"]) != CropSunScript.UNSUITABLE,
		"one hour short of the longest day is at least possible: %s" % CropSunScript.summary_of(reachable))
	var impossible: Dictionary = CropSunScript.check(
		_crop(int((hours + 1.0) * 10.0)), _place(SpeciesScript.FULL_SUN), _site()
	)
	assert(int(impossible["verdict"]) == CropSunScript.UNSUITABLE, CropSunScript.summary_of(impossible))
	assert(
		String(impossible["summary"]).contains("even at midsummer"),
		String(impossible["summary"])
	)


func test_something_against_the_crop_outranks_a_gap_the_way_suitability_orders_them() -> void:
	# A spot that cannot be checked on the season (no site) but is stated full shade for a sun-lover:
	# the shade is the verdict, not the gap.
	var crop: PlantSpecies = _crop(60)
	var verdict: Dictionary = CropSunScript.check(crop, _place(SpeciesScript.FULL_SHADE), {})
	assert(int(verdict["verdict"]) == CropSunScript.UNSUITABLE, CropSunScript.summary_of(verdict))


# --- what will crop in a place --------------------------------------------------------------


func _catalogue() -> PlantCatalogue:
	var catalogue: PlantCatalogue = CatalogueScript.make()
	var boxwood: PlantSpecies = SpeciesScript.make(&"buxus", "Buxus sempervirens", "Boxwood", 200, 150)
	catalogue.add(boxwood)
	catalogue.add(_crop(60))       # tomato: wants 6
	var lettuce: PlantSpecies = _crop(40)
	lettuce.id = &"lettuce"
	lettuce.botanical_name = "Lactuca sativa"
	lettuce.common_name = "Lettuce"
	catalogue.add(lettuce)
	return catalogue


func test_only_the_food_is_listed_and_the_best_comes_first() -> void:
	var rows: Array = CropSunScript.rows(_catalogue(), _place(SpeciesScript.FULL_SUN), _site())
	assert(rows.size() == 2, "the boxwood is not a crop: %d" % rows.size())
	assert(String(rows[0]["title"]).contains("Lettuce"), "the four-hour crop suits full sun best: %s" % String(rows[0]["title"]))
	var texts: Array[String] = CropSunScript.row_texts(_catalogue(), _place(SpeciesScript.FULL_SHADE), _site())
	assert(texts.size() == 2, "and in shade both are listed, refused: %d" % texts.size())
	assert(texts[0].contains("under 3 hours"), str(texts))


func test_the_rows_come_to_a_sentence_and_an_empty_list_says_so() -> void:
	var rows: Array = CropSunScript.rows(_catalogue(), _place(SpeciesScript.PART_SHADE), {})
	var line: String = CropSunScript.describe_rows(rows)
	assert(line.begins_with("2 crops:"), line)
	assert(CropSunScript.describe_rows([]) == "no crops are recorded in this plant list")


func test_a_null_catalogue_is_no_rows_rather_than_a_crash() -> void:
	assert(CropSunScript.rows(null, _place(SpeciesScript.FULL_SUN)).is_empty())
	assert(CropSunScript.describe_rows([]).contains("no crops"))