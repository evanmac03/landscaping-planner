class_name PlantIDResolver
extends RefCounted
## Resolves a raw taxon string - what a phone capture or a spoken name gives you - against a
## `PlantCatalogue`: a direct `StringName` id lookup first, `search()` ranking second.
##
##     var resolver := PlantIDResolver.new()
##     var species: PlantSpecies = resolver.resolve(raw_name, catalogue)
##
## An exact id match returns that species at once; otherwise the best ranked search result is
## returned, and `null` when nothing matches or the best match is below the confidence floor.

## Below this confidence a resolved name is not called a match.
const CONFIDENCE_EXACT := 0.75
const CONFIDENCE_FUZZY := 0.4

## The catalogue this resolver was made with, or null when it was made with none and
## every call passes one.
var _catalogue: PlantCatalogue = null


func _init(catalogue: PlantCatalogue = null) -> void:
	_catalogue = catalogue

# --- internal helpers --------------------------------------------------------

## A name as an id: lowercased, with runs of whitespace, `_` and `-` as single
## underscores, so "Acer rubrum" and "acer-rubrum" both reach the id "acer_rubrum".
static func as_id(text: String) -> StringName:
	var lowered: String = text.strip_edges().to_lower()
	var out: String = ""
	var last_was_sep: bool = false
	for i in lowered.length():
		var c: String = lowered.substr(i, 1)
		var is_sep: bool = c == " " or c == "_" or c == "-" or c == "\t"
		if is_sep:
			if not last_was_sep and not out.is_empty():
				out += "_"
			last_was_sep = true
		else:
			out += c
			last_was_sep = false
	return StringName(out)


## The species whose id is this name written as an id, or null.
static func best_id_match(source: PlantCatalogue, raw_name: String) -> PlantSpecies:
	if source == null:
		return null
	var id: StringName = as_id(raw_name)
	if source.has(id):
		return source.get_species(id)
	# A catalogue keyed by a plain String is still found: Godot treats the two as the
	# same key, but a name that only differs by a space would not have matched above.
	var direct: StringName = StringName(raw_name.strip_edges().to_lower())
	if source.has(direct):
		return source.get_species(direct)
	return null


## How well one plant matches, or -1 for no match. Lower is better; the same order
## PlantCatalogue.rank_of uses.
static func rank_of(plant: PlantSpecies, needle: String) -> int:
	if plant == null:
		return -1
	if String(plant.id).to_lower() == needle:
		return 0
	var botanical: String = plant.botanical_name.to_lower()
	var common: String = plant.common_name.to_lower()
	var cultivar: String = plant.cultivar.to_lower()
	if botanical.begins_with(needle):
		return 1
	if cultivar.begins_with(needle) or common.begins_with(needle):
		return 2
	if botanical.contains(needle):
		return 3
	if common.contains(needle) or cultivar.contains(needle):
		return 4
	for tag: String in plant.tags:
		if tag.to_lower().contains(needle):
			return 5
	if plant.search_text().contains(needle):
		return 6
	return -1


# --- public API ------------------------------------------------------------

## The best match for a name, or null. The catalogue is the one passed in, or the one
## this resolver was made with.
func resolve(raw_name: String, catalogue: PlantCatalogue = null) -> PlantSpecies:
	var source: PlantCatalogue = catalogue if catalogue != null else _catalogue
	if source == null or raw_name.strip_edges().is_empty():
		return null
	var needle: String = raw_name.strip_edges().to_lower()

	# An exact id wins outright.
	var by_id: PlantSpecies = best_id_match(source, raw_name)
	if by_id != null:
		return by_id

	var best_rank: int = 999
	var best: PlantSpecies = null
	for id: StringName in source.ids():
		var plant: PlantSpecies = source.get_species(id)
		var rank: int = rank_of(plant, needle)
		if rank >= 0 and rank < best_rank:
			best_rank = rank
			best = plant
	return best


## Identify a name from a field capture, with the confidence the capture reported.
##
## Returns a Dictionary: `status` is "exact_match", "fuzzy_match" or
## "not_in_catalogue"; `match_type` names how it matched; `species` is the match or
## null; `confidence` is echoed back. A capture the surveyor is unsure of is not filed
## as a plant it probably is not.
func resolve_identification(text: String, confidence: float = 1.0) -> Dictionary:
	var result: Dictionary = {
		"status": "not_in_catalogue",
		"match_type": "none",
		"species": null,
		"confidence": confidence,
	}
	if _catalogue == null or text.strip_edges().is_empty():
		return result

	var exact: PlantSpecies = best_id_match(_catalogue, text)
	if exact != null:
		result["status"] = "exact_match"
		result["match_type"] = "id_exact"
		result["species"] = exact
		return result

	var needle: String = text.strip_edges().to_lower()
	var best_rank: int = 999
	var best: PlantSpecies = null
	for id: StringName in _catalogue.ids():
		var plant: PlantSpecies = _catalogue.get_species(id)
		var rank: int = rank_of(plant, needle)
		if rank >= 0 and rank < best_rank:
			best_rank = rank
			best = plant
	if best == null:
		return result

	if best_rank <= 2 and confidence >= CONFIDENCE_EXACT:
		result["status"] = "exact_match"
		result["match_type"] = "botanical_exact" if best_rank == 1 else "common_exact"
		result["species"] = best
	elif best_rank <= 6 and confidence >= CONFIDENCE_FUZZY:
		result["status"] = "fuzzy_match"
		result["match_type"] = "fuzzy"
		result["species"] = best
	return result
