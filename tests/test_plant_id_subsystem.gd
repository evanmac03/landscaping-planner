extends Node
## Tests for the field plant-ID and site-survey subsystem.
##
## Three pieces, all of them pure enough to test without a scene: the bit-mask
## conversions, the name resolver, and the survey manifest's write-then-read round trip.
## The last one writes a real file under user:// and removes it again.
##
## The resolver's tests pin the one behaviour that is easy to get wrong: a name it does
## not know must come back "not_in_catalogue" rather than the nearest plant, because a
## survey that files a weed as an ornamental is worse than one that files nothing.

const BitMaskScript := preload("res://scripts/utils/bitmask_utils.gd")
const ResolverScript := preload("res://scripts/plant_id_resolver.gd")
const ExporterScript := preload("res://scripts/io/field_manifest_exporter.gd")


## A species with just enough filled in to be resolved and filed.
func _species(id: StringName, botanical: String, common: String) -> PlantSpecies:
	var plant := PlantSpecies.new()
	plant.id = id
	plant.botanical_name = botanical
	plant.common_name = common
	plant.height_cm = 100
	plant.spread_cm = 100
	return plant


## A catalogue holding the given species, keyed by id.
func _catalogue_with(plants: Array[PlantSpecies]) -> PlantCatalogue:
	var catalogue := PlantCatalogue.new()
	for plant: PlantSpecies in plants:
		catalogue.species[plant.id] = plant
	return catalogue


func test_sun_hours_become_the_right_mask() -> void:
	assert(BitMaskScript.sun_hours_to_bitmask(7.0) & BitMaskScript.SUN_FULL_SUN != 0,
		"seven hours of sun must ask for full sun")
	assert(BitMaskScript.sun_hours_to_bitmask(4.5) & BitMaskScript.SUN_PART_SHADE != 0,
		"four and a half hours must ask for part shade")
	assert(BitMaskScript.sun_hours_to_bitmask(0.0) == 0,
		"nothing stated is no mask at all")


func test_edible_parts_become_the_right_mask() -> void:
	var mask: int = BitMaskScript.parse_edible_parts(["leaf", "fruit"])
	assert(mask == (BitMaskScript.EAT_LEAF | BitMaskScript.EAT_FRUIT),
		"leaf and fruit are both eaten")


## Nothing named is zero, and zero is not a value. A plant whose edible parts nobody wrote down is not
## known to be edible: answering `EDIBLE_ANY` would claim every part of it from root to seed, and a
## capture carrying that answer would reach the checks as though a person had listed them all.
func test_a_plant_whose_parts_nobody_listed_is_not_edible_by_default() -> void:
	assert(BitMaskScript.parse_edible_parts([]) == 0, "an empty list states nothing")
	assert(
		BitMaskScript.parse_edible_parts(["bark"]) == 0,
		"and neither does a part this program does not know"
	)
	assert(
		BitMaskScript.parse_edible_parts(["leaf"]) != BitMaskScript.EDIBLE_ANY,
		"one part named is one part eaten, never all of them"
	)
	assert(
		BitMaskScript.parse_edible_parts(["fruits"]) & BitMaskScript.EAT_FRUIT != 0,
		"a typist's plural is still the part"
	)


## One door per conversion. `bitmask_from_sun_hours` duplicated `sun_tenths_to_bitmask`, and two text
## parsers answered a guess (`FULL_SUN`, `DRAINS_ANY`) for words they could not read - both were removed
## rather than left beside the honest converters, because two doors where one of them invents a fact is
## a door somebody will use.
func test_only_one_converter_answers_sun_hours_and_edible_parts() -> void:
	var converter: RefCounted = BitMaskScript.new()
	assert(converter.has_method("sun_hours_to_bitmask"), "the hours converter is the door for figures")
	assert(converter.has_method("parse_edible_parts"), "and the parts parser is the door for words")
	for gone: String in [
		"bitmask_from_sun_hours",
		"bitmask_from_sun_text",
		"bitmask_from_drainage_text",
		"bitmask_from_edible_parts",
		"edible_parts_text",
	]:
		assert(
			not converter.has_method(gone),
			"%s is gone rather than left beside the one that answers honestly" % gone
		)


func test_the_resolver_matches_an_id_a_name_and_refuses_a_stranger() -> void:
	var catalogue := _catalogue_with([_species(&"acer_rubrum", "Acer rubrum", "Red Maple")])
	var resolver = ResolverScript.new(catalogue)

	var by_id: Dictionary = resolver.resolve_identification("acer rubrum", 0.95)
	assert(String(by_id["status"]) == "exact_match", "a spaced name reaches the id")
	assert(by_id["species"] != null and by_id["species"].id == &"acer_rubrum",
		"and it is the right plant")

	var by_common: Dictionary = resolver.resolve_identification("Red Maple", 0.88)
	assert(String(by_common["status"]) == "exact_match", "the common name matches")
	assert(String(by_common["match_type"]) == "common_exact", "and it matched as the common name")

	var stranger: Dictionary = resolver.resolve_identification("Unknown Weed", 0.50)
	assert(String(stranger["status"]) == "not_in_catalogue", "a plant not in the list is not a match")
	assert(stranger["species"] == null, "and nothing is handed back for it")


func test_a_manifest_written_is_a_manifest_read_back() -> void:
	var species := _species(&"quercus_alba", "Quercus alba", "White Oak")
	var feature: Dictionary = {
		"instance_id": "feature_001",
		"species": species,
		"confidence": 0.92,
		"position": Vector3(10.5, 0.0, -5.2),
		"sun_mask": BitMaskScript.SUN_FULL_SUN,
		"drainage_mask": BitMaskScript.DRAIN_FAST,
	}
	var path: String = "user://test_site_manifest.json"
	var error: Error = ExporterScript.export_manifest("Test Site", [feature], path)
	assert(error == OK, "writing the manifest failed with %d" % error)

	var read: Dictionary = ExporterScript.read_manifest(path)
	assert(bool(read["ok"]), String(read["reason"]))
	var data: Dictionary = read["data"]
	assert(String(data["site_name"]) == "Test Site", "the site name is kept")
	var features: Array = data["features"]
	assert(features.size() == 1, "one feature went in and one came out")
	assert(String(features[0]["species_id"]) == "quercus_alba", "the species id is kept")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## The same filing ViewController.process_field_identification does, without a scene:
## an identified plant lands in the "Field Survey Captures" collection.
func test_an_identified_plant_is_filed_in_the_survey_collection() -> void:
	var catalogue := _catalogue_with([_species(&"quercus_alba", "Quercus alba", "White Oak")])
	var resolver = ResolverScript.new(catalogue)
	var found: PlantSpecies = resolver.resolve("White Oak")
	assert(found != null, "the common name resolves")
	var name := "Field Survey Captures"
	if not catalogue.has_collection(name):
		catalogue.create_collection(name)
	catalogue.add_to_collection(name, found.id)
	assert(catalogue.collections_of(found.id).has(name), "the plant is in the survey collection")
	assert(catalogue.collection(name).size() == 1, "and the collection holds it")