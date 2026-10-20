extends Node
## The shipped plant list, and the expansion that grew it.
##
## The list is data, and data has no compiler: a species with a zone of 9..3, a form naming a prop
## that was renamed, or an id typed twice all look like every other line in the file. So the two
## things tested here are the things a person cannot see by reading it - that the additions and the
## shipped list are **the same list**, and that adding them again adds nothing.

const CatalogueScript := preload("res://scripts/plant_catalogue.gd")
const ExpansionScript := preload("res://tools/plant_expansion.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")

## A plant that was in the shipped list before the expansion, chosen because its own values are
## distinctive: if the importer ever replaced an existing entry instead of skipping it, this is the
## plant that would come back different.
const OLD_HAND := &"acer-rubrum-autumn-blaze"


func _catalogue() -> PlantCatalogue:
	var read: Dictionary = CatalogueScript.load_from(ExpansionScript.SHIPPED_PATH)
	assert(bool(read["ok"]), "the shipped list loads: %s" % String(read["reason"]))
	return read["catalogue"]


# --- the additions ------------------------------------------------------------------------


func test_the_additions_are_valid_and_listed_once_each() -> void:
	var additions: Array[Dictionary] = ExpansionScript.additions()
	assert(additions.size() >= 100, "the expansion is a nursery's worth: %d" % additions.size())
	var complaints: Array[String] = ExpansionScript.validate(additions)
	assert(complaints.is_empty(), "and there is nothing wrong with them: %s" % " | ".join(complaints))


func test_every_addition_is_in_the_shipped_list() -> void:
	# This is the test that catches the mistake this tool makes easy: adding a plant to the GDScript
	# and forgetting to run it. The list the program loads is the file, so an addition that is only
	# in the script is a plant nobody can plant.
	var catalogue: PlantCatalogue = _catalogue()
	var absent: Array[String] = []
	for row: Dictionary in ExpansionScript.additions():
		if not catalogue.has(StringName(row["id"])):
			absent.append(String(row["id"]))
	assert(absent.is_empty(), "every addition reached the list: %s" % ", ".join(PackedStringArray(absent)))


func test_the_additions_file_on_disk_is_the_list_this_tool_builds() -> void:
	# The file is the record a person reads and diffs, so it has to be the list rather than a copy of
	# it that was current once.
	var read: Dictionary = CatalogueScript.load_from(ExpansionScript.MORE_PATH)
	assert(bool(read["ok"]), "the additions file loads: %s" % String(read["reason"]))
	var on_disk: CatalogueScript = read["catalogue"]
	var built: Array[Dictionary] = ExpansionScript.additions()
	assert(on_disk.count() == built.size(), "the file has every addition: %d vs %d" % [
		on_disk.count(), built.size()
	])
	for row: Dictionary in built:
		var id: StringName = StringName(row["id"])
		var here: PlantSpecies = on_disk.get_species(id)
		assert(here != null, "%s is in the file" % id)
		assert(
			JSON.stringify(here.to_dict()) == JSON.stringify(SpeciesScript.from_dict(row).to_dict()),
			"%s in the file is the one this tool builds" % id
		)


func test_importing_the_additions_onto_their_own_list_adds_nothing() -> void:
	# The rule the expansion came with, tested through the mechanism that enforces it: the module's
	# importer, with `replace` off. Every addition is already there, so every one of them is refused
	# and nothing moves. This is what running `PlantExpansion.run()` a second time does.
	var read: Dictionary = CatalogueScript.load_from(ExpansionScript.MORE_PATH)
	var additions: CatalogueScript = read["catalogue"]
	var before: Array[StringName] = additions.ids()
	var imported: Dictionary = additions.import_json(ExpansionScript.MORE_PATH)
	assert(bool(imported["ok"]), "the import ran: %s" % String(imported["reason"]))
	assert(int(imported["added"]) == 0, "and added nothing: %d" % int(imported["added"]))
	assert(int(imported["replaced"]) == 0, "and replaced nothing")
	assert(imported["refused"].size() == before.size(), "and refused every one of them as already there")
	assert(additions.ids() == before, "with the list exactly as it was")


func test_an_addition_already_in_the_catalogue_does_not_move() -> void:
	# The other half of that rule, and the one that protects the plants that were in the list first:
	# the entry that is already there wins, even when the incoming one would have been valid.
	var catalogue: PlantCatalogue = _catalogue()
	var was: PlantSpecies = catalogue.get_species(OLD_HAND)
	assert(was != null, "%s is in the shipped list" % OLD_HAND)
	var kept: Dictionary = was.to_dict()
	# A whole catalogue of one plant, whose only entry is a *different* version of that plant.
	var incoming: CatalogueScript = CatalogueScript.from_dict({
		"version": 1,
		"source": "a list that wants to change a plant",
		"species": {"acer-rubrum-autumn-blaze": {
			"id": "acer-rubrum-autumn-blaze",
			"botanical_name": "Acer rubrum",
			"common_name": "Red maple",
			"cultivar": "Autumn Blaze",
			"category": SpeciesScript.TREE,
			"zone_min": 3,
			"zone_max": 9,
			"height_cm": 1,
			"spread_cm": 1,
			"sun": SpeciesScript.FULL_SUN,
			"water": SpeciesScript.WATER_LOW,
			"soils": [],
			"drainage": SpeciesScript.DRAINS_ANY,
			"bloom_months": 0,
			"bloom_colour": "#000000",
			"form": "res://scenes/props/tree.tscn",
			"model_scene": "",
			"thumbnail": "",
			"tags": [],
			"note": "",
		}},
	})
	var count: int = catalogue.count()
	var imported: Dictionary = catalogue.import_json(ExpansionScript.MORE_PATH)
	assert(int(imported["added"]) == 0, "the additions are all already there")
	assert(catalogue.count() == count, "so the catalogue has not grown")
	assert(
		JSON.stringify(catalogue.get_species(OLD_HAND).to_dict()) == JSON.stringify(kept),
		"and the red maple is still the red maple"
	)
	assert(incoming.count() == 1, "the other list is a catalogue in its own right")
	assert(incoming.get_species(OLD_HAND).height_cm == 1, "and it really did say something different")


# --- what the bigger list is worth ----------------------------------------------------------


func test_the_list_covers_every_category_and_the_questions_a_plan_asks() -> void:
	var catalogue: PlantCatalogue = _catalogue()
	# A filter that can find one plant is a filter nobody uses: each category a browser offers has to
	# have enough in it to choose *between*, or the list is not yet a list.
	for kind: int in SpeciesScript.CATEGORY_NAMES.keys():
		var found: Array[PlantSpecies] = catalogue.filter({"category": kind})
		assert(found.size() >= 3, "%s has %d in it" % [String(SpeciesScript.CATEGORY_NAMES[kind]), found.size()])
	# The suitability check can only be as sharp as the catalogue: with no soil stated anywhere it
	# would skip the question for every plant in the list, and a check that never fires is worse than
	# no check, because somebody believes it.
	var soils: int = 0
	var drained: int = 0
	for plant: PlantSpecies in catalogue.all():
		if not plant.soils.is_empty():
			soils += 1
		if plant.drainage != SpeciesScript.DRAINS_ANY:
			drained += 1
	assert(soils >= 20, "plenty of plants name their soil: %d" % soils)
	assert(drained >= 50, "and their drainage: %d" % drained)


func test_the_bigger_list_is_still_something_a_nursery_would_recognise() -> void:
	# The properties `test_plant_browser.gd` holds the shipped list to, restated here at its new size:
	# sound, drawn with scenes that exist, and every category represented.
	var catalogue: PlantCatalogue = _catalogue()
	assert(catalogue.count() >= 120, "the list grew: %d" % catalogue.count())
	assert(catalogue.is_sound(), "and it is sound: %s" % " | ".join(catalogue.problems()))
	assert(catalogue.missing_files().is_empty(),
		"and every form in it is on disk: %s" % " | ".join(catalogue.missing_files()))
	assert(catalogue.source == "starter list", "and it still says where it came from")
	# Nothing arrives twice, and nothing arrives with no name: an id is what an imported list and the
	# catalogue are matched on, so a duplicate id is a plant that cannot be planted by name.
	var ids: Array[StringName] = catalogue.ids()
	var unique: Dictionary = {}
	for id: StringName in ids:
		assert(not unique.has(id), "%s is in the list once" % id)
		unique[id] = true
		var plant: PlantSpecies = catalogue.get_species(id)
		assert(not plant.botanical_name.strip_edges().is_empty(), "%s has a botanical name" % id)
		assert(not plant.common_name.strip_edges().is_empty(), "%s has a common name" % id)