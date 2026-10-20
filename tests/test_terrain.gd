extends Node
## The ground: what a plan states about growing conditions, and how it states it.
##
## Three claims are under test here, and they are the ones the whole suitability feature rests on:
##
## * **A profile says only what it was told.** There is no default "medium" for a property nobody
##   set, because a check that read silence as an average would hand out confident verdicts about a
##   garden it knows nothing about.
## * **A zone states only what it changes**, and a later zone wins over an earlier one, because that
##   is the order a designer draws in.
## * **A drawing is evidence about two things and no more** - a building is shade, a hard surface is
##   hot and dry - so a plan that has been drawn on gives real answers, and a bed outline does not
##   get to describe the design back to itself and call it the environment.

const Profile := preload("res://scripts/terrain_profile.gd")
const ZoneMapScript := preload("res://scripts/zone_map.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const Document := preload("res://scripts/draft/draft_document.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")


func _square(centre: Vector2, half: float) -> PackedVector2Array:
	return PackedVector2Array([
		centre + Vector2(-half, -half),
		centre + Vector2(half, -half),
		centre + Vector2(half, half),
		centre + Vector2(-half, half),
	])


# --- a profile says what it was told ------------------------------------------------------


func test_a_new_profile_states_nothing_at_all() -> void:
	var profile: TerrainProfile = Profile.make()
	assert(profile.is_empty(), "an empty profile is empty")
	assert(not profile.has("moisture"), "and it has not claimed a moisture level")
	assert(profile.moisture_level() == Profile.NO_LEVEL, "reading it back says so")
	assert(profile.describe() == "nothing stated about this spot", "and it says so in words")
	assert(profile.is_valid(), "nothing stated is a valid state, not an error")


func test_a_profile_states_one_thing_and_says_only_that() -> void:
	var profile: TerrainProfile = Profile.of("sun", SpeciesScript.FULL_SHADE)
	assert(profile.stated_keys() == ["sun"], "one key is stated")
	assert(not profile.has("soil"), "and the soil is not one of them")
	assert(profile.text_of("sun") == "full shade")
	assert(profile.text_of("soil") == "", "an unstated attribute has no words")
	assert(profile.describe() == "full shade")


func test_a_zone_lays_only_its_own_statements_over_the_site() -> void:
	# The site is part shade on loam. The bed by the wall is dry - and says nothing about light, so
	# it inherits the site's, rather than claiming the sun for itself.
	var site: TerrainProfile = Profile.make({
		"sun": SpeciesScript.PART_SHADE,
		"soil": Profile.LOAM,
	})
	var zone: TerrainProfile = Profile.of("moisture", SpeciesScript.WATER_LOW)
	var together: TerrainProfile = zone.merged_over(site)
	assert(together.sun_level() == SpeciesScript.PART_SHADE, "the site's light survives")
	assert(together.soil_name() == Profile.LOAM, "and so does its soil")
	assert(together.moisture_level() == SpeciesScript.WATER_LOW, "and the zone adds the dryness")
	assert(together.stated_keys() == ["sun", "moisture", "soil"], "keys come back in reading order")


func test_a_zone_s_statement_beats_the_site_s() -> void:
	var site: TerrainProfile = Profile.of("sun", SpeciesScript.PART_SHADE)
	var zone: TerrainProfile = Profile.of("sun", SpeciesScript.FULL_SHADE)
	assert(zone.merged_over(site).sun_level() == SpeciesScript.FULL_SHADE)


func test_a_profile_refuses_a_value_that_is_not_a_value() -> void:
	# A light level is one of three bits, and 3 is two of them at once: a place is not "full sun and
	# part shade", and a profile that kept it would match no plant and look like horticulture.
	var both: TerrainProfile = Profile.of("sun", SpeciesScript.FULL_SUN | SpeciesScript.PART_SHADE)
	assert(not both.is_valid())
	assert(both.problem().contains("light level 3"), "and it says which: %s" % both.problem())
	var wrong_soil: TerrainProfile = Profile.of("soil", &"SANDY LOAM")
	assert(wrong_soil.problem().contains("SANDY LOAM"), "a soil nobody has heard of is named")
	var set_drainage: TerrainProfile = Profile.of("drainage", SpeciesScript.DRAINS_ANY)
	assert(not set_drainage.is_valid(), "a place drains one way, not a set of ways")
	var zone_thirteen: TerrainProfile = Profile.of("zone", 14)
	assert(not zone_thirteen.is_valid(), "and zone 14 is not a zone")
	var nonsense: TerrainProfile = Profile.make({"ph": 7})
	assert(nonsense.is_empty(), "an attribute that is not a thing a place can state is dropped")


# --- zones --------------------------------------------------------------------------------


func test_a_later_zone_wins_over_an_earlier_one() -> void:
	# The whole garden is part shade; a bed inside it is in full sun. Drawn in that order, the bed is
	# what answers for the middle.
	var map: ZoneMapScript = ZoneMapScript.make({"sun": SpeciesScript.PART_SHADE})
	map.add_zone("the garden", _square(Vector2.ZERO, 10.0), Profile.of("sun", SpeciesScript.PART_SHADE))
	map.add_zone("the sunny bed", _square(Vector2.ZERO, 3.0), Profile.of("sun", SpeciesScript.FULL_SUN))
	var middle: Dictionary = map.profile_at(Vector2(1.0, 1.0))
	assert(String(middle["place"]) == "the sunny bed", "the last zone drawn answers")
	assert(int((middle["profile"] as TerrainProfile).sun_level()) == SpeciesScript.FULL_SUN)
	var edge: Dictionary = map.profile_at(Vector2(8.0, 0.0))
	assert(String(edge["place"]) == "the garden", "and outside it the wider zone does")
	assert(int((edge["profile"] as TerrainProfile).sun_level()) == SpeciesScript.PART_SHADE)


func test_a_point_outside_every_zone_gets_the_site_itself() -> void:
	var map: ZoneMapScript = ZoneMapScript.make({"soil": Profile.CLAY})
	map.add_zone("the bed", _square(Vector2.ZERO, 2.0), Profile.of("moisture", SpeciesScript.WATER_HIGH))
	var away: Dictionary = map.profile_at(Vector2(20.0, 20.0))
	assert(away["zone"] == null, "no zone contains it")
	assert(String(away["place"]) == "the rest of the site")
	assert((away["profile"] as TerrainProfile).soil_name() == Profile.CLAY)
	assert(not (away["profile"] as TerrainProfile).has("moisture"), "and the bed's wetness is not its")


func test_a_zone_with_no_area_is_refused_and_named() -> void:
	var map: ZoneMapScript = ZoneMapScript.make()
	# Two points are a line, not an area: nothing can ever be inside it, so a zone that kept it would
	# silently never apply.
	map.add_zone("a line", PackedVector2Array([Vector2.ZERO, Vector2(3.0, 0.0)]), Profile.of("sun", 1))
	map.add_zone("empty", _square(Vector2(5.0, 5.0), 2.0), Profile.make())
	var problems: Array[String] = map.problems()
	assert(problems.size() == 2, "both are named: %s" % " | ".join(problems))
	assert(problems[0].contains("a line") and problems[0].contains("no area"), problems[0])
	assert(problems[1].contains("empty") and problems[1].contains("states nothing"), problems[1])
	assert(not map.is_sound())
	# And a zone that is fine does not make a noise about itself.
	var good: ZoneMapScript = ZoneMapScript.make()
	good.add_zone("the bed", _square(Vector2.ZERO, 2.0), Profile.of("sun", SpeciesScript.FULL_SUN))
	assert(good.is_sound(), "a stated zone with an area is sound: %s" % " | ".join(good.problems()))


func test_the_map_survives_a_json_round_trip() -> void:
	var map: ZoneMapScript = ZoneMapScript.make({"sun": SpeciesScript.FULL_SHADE, "soil": Profile.CLAY})
	map.add_zone(
		"the bed", _square(Vector2(1.5, -2.5), 2.0),
		Profile.of("moisture", SpeciesScript.WATER_HIGH), "layer:400-NEW-BED#7"
	)
	var text: String = JSON.stringify(map.to_dict())
	# `parse()` answers with an error code and keeps the data: the parsed value is `get_data()`.
	var reader := JSON.new()
	assert(reader.parse(text) == OK, "the map writes valid JSON: %s" % reader.get_error_message())
	var parsed: Variant = reader.get_data()
	assert(parsed is Dictionary, "the map writes JSON")
	var back: ZoneMapScript = ZoneMapScript.from_dict(parsed)
	assert(back.base.equals(map.base), "the site's conditions come back the same")
	assert(back.zone_count() == 1)
	assert(back.zones[0].name == "the bed")
	assert(back.zones[0].source == "layer:400-NEW-BED#7")
	assert(back.zones[0].profile.moisture_level() == SpeciesScript.WATER_HIGH, "as levels, not as 2.0")
	assert(back.zones[0].contains(Vector2(1.5, -2.5)), "and the outline still contains its middle")
	assert(back.profile_at(Vector2(1.5, -2.5))["profile"].soil_name() == Profile.CLAY)


# --- the drawing as evidence --------------------------------------------------------------


func test_the_drawing_states_what_a_building_and_a_hard_surface_mean() -> void:
	var document: DraftDocument = Document.new()
	document.add(Entity.make_rectangle(Vector2.ZERO, Vector2(8.0, 6.0)), LayerSet.EXISTING_STRUCTURE)
	document.add(Entity.make_rectangle(Vector2(12.0, 0.0), Vector2(4.0, 4.0)), LayerSet.NEW_HARDSCAPE)
	# A bed and a lawn are the *design*, not the site: they say nothing about the ground.
	document.add(Entity.make_rectangle(Vector2(0.0, 12.0), Vector2(6.0, 3.0)), LayerSet.NEW_BED)
	document.add(Entity.make_rectangle(Vector2(12.0, 12.0), Vector2(6.0, 3.0)), LayerSet.NEW_TURF)
	# A line on a derived layer has no area to be inside.
	document.add(Entity.make_line(Vector2(-20.0, 0.0), Vector2(-16.0, 0.0)), LayerSet.NEW_HARDSCAPE)

	var count: int = document.read_environment_from_drawing()
	assert(count == 2, "two areas of ground are read, not four: %d" % count)
	var under_house: Dictionary = document.environment.profile_at(Vector2.ZERO)
	assert(String(under_house["place"]) == "under the building")
	var ground: TerrainProfile = under_house["profile"]
	assert(ground.sun_level() == SpeciesScript.FULL_SHADE, "a building is shade")
	assert(ground.moisture_level() == SpeciesScript.WATER_LOW, "and its eaves are dry")
	assert(not ground.has("soil"), "and it does not claim to know the soil")
	var on_paving: Dictionary = document.environment.profile_at(Vector2(12.0, 0.0))
	assert(String(on_paving["place"]) == "hard surface")
	assert((on_paving["profile"] as TerrainProfile).sun_level() == SpeciesScript.FULL_SUN)
	assert((on_paving["profile"] as TerrainProfile).drainage_level() == Profile.DRAINAGE_FAST)
	var in_the_bed: Dictionary = document.environment.profile_at(Vector2(0.0, 12.0))
	assert(String(in_the_bed["place"]) == "the rest of the site", "a bed says nothing about the ground")
	assert((in_the_bed["profile"] as TerrainProfile).is_empty(), "and nothing is what it says")
	assert(String(in_the_bed["source"]) == "the site")


func test_reading_the_drawing_again_does_not_double_the_zones() -> void:
	var document: DraftDocument = Document.new()
	document.add(Entity.make_rectangle(Vector2.ZERO, Vector2(8.0, 6.0)), LayerSet.EXISTING_STRUCTURE)
	assert(document.read_environment_from_drawing() == 1)
	assert(document.read_environment_from_drawing() == 1, "asking twice gives one zone, not two")
	assert(document.environment.zone_count() == 1)


func test_a_drawing_with_nothing_on_it_says_nothing() -> void:
	var document: DraftDocument = Document.new()
	assert(document.read_environment_from_drawing() == 0)
	assert(document.environment.zone_count() == 0)
	assert(document.environment.base.is_empty())


# --- the map belongs to the drawing -------------------------------------------------------


func test_the_ground_travels_in_the_file_and_moves_with_undo() -> void:
	var document: DraftDocument = Document.new()
	var stated: ZoneMapScript = ZoneMapScript.make({"soil": Profile.SAND})
	assert(document.set_environment(stated), "stating the ground is a change")
	assert(not document.set_environment(stated.copy()), "and stating the same thing again is not")
	# A version 5 file carries it.
	var saved: Dictionary = document.to_dict()
	assert(int(saved["version"]) == 5, "the file states what the ground is like: version %d" % int(saved["version"]))
	assert(saved.has("environment"), "and it is written out")
	var loaded: DraftDocument = Document.from_dict(saved)
	assert(loaded.environment.base.soil_name() == Profile.SAND, "and read back")
	# A version 4 file has no ground in it, and gets "nothing stated" rather than an invented garden.
	var old: Dictionary = document.to_dict()
	old.erase("environment")
	old["version"] = 4
	var legacy: DraftDocument = Document.from_dict(old)
	assert(legacy.environment.base.is_empty(), "a file from before the ground existed states nothing")
	assert(legacy.environment.zone_count() == 0)
	# And the ground is on the undo stack, because the stack stores the whole document.
	var changed: ZoneMapScript = document.environment.copy()
	changed.base.with("moisture", SpeciesScript.WATER_HIGH)
	assert(document.set_environment(changed))
	assert(document.environment.base.moisture_level() == SpeciesScript.WATER_HIGH)
	assert(document.undo_last(), "the change can be undone")
	assert(document.environment.base.soil_name() == Profile.SAND, "and the soil is back")
	assert(not document.environment.base.has("moisture"), "and the moisture is unstated again")