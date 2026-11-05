extends Node
## Tests for PlantIDResolver: turning a name from the field into a species in the list.
##
## Three behaviours, in the order a name is tried: an **exact id** first, then the
## **ranked** search over botanical and common names, and finally what happens when the
## plant is not in the catalogue at all. The last is the one worth pinning hardest - a
## resolver that answers every name with the nearest plant is worse than one that refuses,
## because a survey would file a weed as an ornamental and nobody would know.

const ResolverScript := preload("res://scripts/plant_id_resolver.gd")


## A species with just enough filled in to be resolved.
func _species(id: StringName, botanical: String, common: String) -> PlantSpecies:
	var plant := PlantSpecies.new()
	plant.id = id
	plant.botanical_name = botanical
	plant.common_name = common
	plant.height_cm = 100
	plant.spread_cm = 100
	return plant


## A catalogue of three plants, keyed by id the way PlantCatalogue stores them.
func _catalogue() -> PlantCatalogue:
	var catalogue := PlantCatalogue.new()
	for plant: PlantSpecies in [
		_species(&"acer_rubrum", "Acer rubrum", "Red Maple"),
		_species(&"acer_saccharum", "Acer saccharum", "Sugar Maple"),
		_species(&"quercus_alba", "Quercus alba", "White Oak"),
	]:
		catalogue.species[plant.id] = plant
	return catalogue


## 1. An exact id is found as itself, whether written as the id or as a label.
func test_an_exact_id_is_found_as_itself() -> void:
	var resolver = ResolverScript.new(_catalogue())

	var by_id: Dictionary = resolver.resolve_identification("quercus_alba")
	assert(String(by_id["status"]) == "exact_match", "the id is an exact match")
	assert(String(by_id["match_type"]) == "id_exact", "and it matched on the id")
	assert(by_id["species"] != null and by_id["species"].id == &"quercus_alba",
		"and it is the plant that id names")

	# The same id written the way a nursery label writes it - a space, a capital - still
	# reaches the id, because a name and an id differ only by how they are spelled.
	var spaced: Dictionary = resolver.resolve_identification("Quercus alba")
	assert(String(spaced["match_type"]) == "id_exact", "a spaced name still reaches the id")

	# `resolve` hands back the species itself for an exact id.
	var species: PlantSpecies = resolver.resolve("quercus_alba")
	assert(species != null and species.id == &"quercus_alba", "resolve returns the species")


## 2a. A botanical name prefix is an exact match, and outranks a weaker one.
func test_a_botanical_prefix_matches() -> void:
	var resolver = ResolverScript.new(_catalogue())
	var found: Dictionary = resolver.resolve_identification("acer")
	assert(String(found["status"]) == "exact_match", "a genus prefix is an exact match")
	assert(String(found["match_type"]) == "botanical_exact", "and it matched the botanical name")
	assert(found["species"] != null and String(found["species"].botanical_name).begins_with("Acer"),
		"and it is an Acer")


## 2b. A common name matches too, and says that is how it matched.
func test_a_common_name_matches() -> void:
	var resolver = ResolverScript.new(_catalogue())
	var found: Dictionary = resolver.resolve_identification("Red Maple")
	assert(String(found["status"]) == "exact_match", "the common name is an exact match")
	assert(String(found["match_type"]) == "common_exact", "and it says it matched the common name")
	assert(found["species"] != null and found["species"].id == &"acer_rubrum",
		"and it is the Red Maple")


## 2c. `rank_of` orders the ways of matching, lower being better: an id, then a botanical
## prefix, then a common prefix, then a mere containment.
func test_the_ranking_orders_the_ways_of_matching() -> void:
	var rubrum: PlantSpecies = _species(&"acer_rubrum", "Acer rubrum", "Red Maple")
	assert(ResolverScript.rank_of(rubrum, "acer_rubrum") == 0, "an id scores best")
	assert(ResolverScript.rank_of(rubrum, "acer") == 1, "a botanical prefix is next")
	assert(ResolverScript.rank_of(rubrum, "red maple") == 2, "a common prefix follows")
	assert(ResolverScript.rank_of(rubrum, "rubrum") == 3, "a botanical containment is weaker still")
	assert(ResolverScript.rank_of(rubrum, "maple") == 4, "a common containment is weaker again")
	assert(ResolverScript.rank_of(rubrum, "no such thing") == -1, "and nothing at all scores nothing")

	# With only a containment to go on, the resolver still picks the right plant - as a
	# fuzzy match rather than an exact one.
	var resolver = ResolverScript.new(_catalogue())
	var picked: PlantSpecies = resolver.resolve("sugar maple")
	assert(picked != null and picked.id == &"acer_saccharum", "a full common name picks the plant")
	var fuzzy: Dictionary = resolver.resolve_identification("rubrum")
	assert(String(fuzzy["status"]) == "fuzzy_match", "a containment is only a fuzzy match")
	assert(fuzzy["species"] != null and fuzzy["species"].id == &"acer_rubrum",
		"and it still names the right plant")


## 3a. A plant the catalogue does not have is refused, not guessed at.
func test_a_missing_species_is_refused() -> void:
	var resolver = ResolverScript.new(_catalogue())
	var missing: Dictionary = resolver.resolve_identification("Unknown Weed")
	assert(String(missing["status"]) == "not_in_catalogue", "a plant not in the list is not a match")
	assert(missing["species"] == null, "and nothing is handed back for it")
	assert(String(missing["match_type"]) == "none", "and it matched nothing")
	assert(resolver.resolve("Unknown Weed") == null, "resolve agrees and returns nothing")
	assert(resolver.resolve("") == null, "and an empty name is nothing to resolve")


## 3b. A name the surveyor is unsure of is refused even though it matches, because a low
## confidence must not be filed as a plant it probably is not.
func test_a_match_below_the_confidence_floor_is_refused() -> void:
	var resolver = ResolverScript.new(_catalogue())
	var unsure: Dictionary = resolver.resolve_identification("Red Maple", 0.1)
	assert(String(unsure["status"]) == "not_in_catalogue", "a low confidence is not a match")
	assert(unsure["species"] == null, "and nothing is filed for it")
	assert(abs(float(unsure["confidence"]) - 0.1) < 0.0001, "the confidence is echoed back")

	# The same name at a confidence worth trusting is accepted, so it is the floor doing
	# the refusing and not the name.
	var sure: Dictionary = resolver.resolve_identification("Red Maple", 0.9)
	assert(String(sure["status"]) == "exact_match", "the same name is accepted when trusted")