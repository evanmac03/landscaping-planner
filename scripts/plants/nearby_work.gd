## What the drawing puts around a place: the work nearest where a person stands, so that somebody holding the plan
## on site can see what goes in next to them.
##
## **The build step was the one step of a job with no page of its own.** A survey has one, a drawing, an estimate,
## a presentation and an invoice each have one - and the person standing in the garden with the plan in hand had
## nothing that answered "what goes in around here?". This module is that page's arithmetic: given a place and what
## the drawing places, it answers the nearest few, in the order they would walk to them.
##
## **Metres, and the drawing's own axis.** A place is a `Vector2` in plan metres, which is the model's own space,
## and the axis is `Survey.traverse`'s, read from there rather than restated: **east is +X and north is -Z**. A
## distance is worded by `UnitsScript.length_words`, the one place a length becomes words in this program, and a
## direction is that same azimuth said as a compass point - because "N 45°30'15\" E" is a surveyor's line on a
## plat, and a person standing in a garden can point at north-east and cannot point at 45°30'15".
##
## Everything here is static and pure: no scene, no node and no file. `planted_things` is the one reader that turns
## a yard into this module's own input, and it is a separate function because reading a scene is not arithmetic.
class_name NearbyWork
extends RefCounted

const PlantPlacementScript := preload("res://scripts/plants/plant_placement.gd")
const UnitsScript := preload("res://scripts/draft/units.gd")

## How many the page lists. **A handful is what a person carries to the next spot**; a list of thirty is a
## schedule, and a schedule is a page this program already has (`PlantPlacement.schedule`).
const NEAREST := 5

## The eight points of the compass, clockwise from north, in the words each is said as.
const COMPASS: Array[String] = [
	"north",
	"north-east",
	"east",
	"south-east",
	"south",
	"south-west",
	"west",
	"north-west",
]

## What a drawing with nothing planted on it says. A refusal names what is missing, so this is the sentence a
## person reads in place of an empty list.
const NOTHING_PLANTED := "nothing is planted on the drawing yet"


## The things around a place, nearest first.
##
## `things` is one dictionary per thing - `{name: String, at: Vector2}` - and an **empty name is a plant the
## catalogue cannot name**, which is counted and said rather than dropped: the shipped yard has thirty of them, and
## a page that quietly left them out would be describing a third of the planting.
##
## The order is **distance, then name**, so two things equally far away come out in the same order every time
## rather than in whatever order the yard happened to list them.
##
## Returns `{rows, found, unnamed, nearest, text}`. `rows` is the nearest `most` of them, and each row carries
## `{name, at, metres, words, direction, sentence}` - the sentence being the line a person reads.
static func around(things: Array, at: Vector2, most: int = NEAREST) -> Dictionary:
	var all: Array[Dictionary] = []
	var unnamed: int = 0
	for thing: Variant in things:
		if not (thing is Dictionary):
			continue
		var entry: Dictionary = thing
		var where: Variant = entry.get("at", null)
		if not (where is Vector2):
			continue
		var name: String = String(entry.get("name", "")).strip_edges()
		if name.is_empty():
			unnamed += 1
			continue
		var point: Vector2 = where
		all.append({ "name": name, "at": point, "metres": at.distance_to(point) })
	all.sort_custom(
		func(first: Dictionary, second: Dictionary) -> bool:
			var gap: float = float(first["metres"]) - float(second["metres"])
			if not is_equal_approx(gap, 0.0):
				return gap < 0.0
			return String(first["name"]) < String(second["name"]),
	)
	var rows: Array[Dictionary] = []
	for index in mini(maxi(most, 0), all.size()):
		var row: Dictionary = all[index]
		var words: String = UnitsScript.length_words(float(row["metres"]))
		var direction: String = direction_words(at, row["at"])
		row["words"] = words
		row["direction"] = direction
		row["sentence"] = "%s, %s to the %s." % [row["name"], words, direction]
		rows.append(row)
	return {
		"rows": rows,
		"found": all.size(),
		"unnamed": unnamed,
		"nearest": rows[0] if not rows.is_empty() else { },
		"text": summary_words(all.size(), unnamed),
	}


## The direction from one place to another, as one of the eight points of the compass.
##
## The azimuth is measured off the drawing's own axis - east +X, north -Y, the convention `Survey.traverse` states
## - and rounded to the nearest of the eight. A thing standing in the very spot says "here", which is a real answer
## rather than a slip: it is exactly what a person holding the plan would say about it.
static func direction_words(from: Vector2, to: Vector2) -> String:
	var across: Vector2 = to - from
	if across.is_zero_approx():
		return "here"
	var azimuth: float = rad_to_deg(atan2(across.x, -across.y))
	var index: int = int(round(fposmod(azimuth, 360.0) / 45.0)) % COMPASS.size()
	return COMPASS[index]


## The line under the list: what the drawing holds, and what it could not name.
##
## **The words for the plants with no species are the audit's own** - "with no species recorded" - because a person
## who has run "Check the planting" and then opened this page is reading about the same thirty plants in both, and
## two ways of saying it would read as two different problems.
static func summary_words(found: int, unnamed: int) -> String:
	if found == 0 and unnamed == 0:
		return NOTHING_PLANTED
	var parts: PackedStringArray = PackedStringArray()
	parts.append("%d planted thing%s, nearest first" % [found, "" if found == 1 else "s"])
	if unnamed > 0:
		parts.append("%d with no species recorded" % unnamed)
	return "%s." % ", ".join(parts)


## The things a yard holds, in this module's own input: one `{name, at}` per planted thing, with an empty name for
## one no species is recorded for.
##
## **The plan's metres are the yard's own** - a planted prop hangs straight off `Yard/Plants` - so a position is
## read exactly as `PlantSuitability.audit` reads it, and through the same two owners: `PlantPlacement.planted` for
## the walk and `PlantPlacement.species_of` for which species it is. A node that is not in the scene yet is read
## from its own position, because asking a detached node for a global transform is an engine error and answers
## zero.
##
## The name is the **common** one, because that is what somebody standing in the garden says, with the botanical
## name where the catalogue carries no common one - so a plant is never nameless for want of a nickname.
static func planted_things(catalogue: PlantCatalogue, yard: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if yard == null:
		return out
	for node: Node3D in PlantPlacementScript.planted(yard):
		var where: Vector3 = node.global_position if node.is_inside_tree() else node.position
		var named: String = species_words(catalogue, PlantPlacementScript.species_of(node))
		out.append({ "name": named, "at": Vector2(where.x, where.z) })
	return out


## How a species is named on this page, or empty when nothing can name it.
static func species_words(catalogue: PlantCatalogue, species_id: StringName) -> String:
	if catalogue == null or species_id.is_empty():
		return ""
	var species: PlantSpecies = catalogue.get_species(species_id)
	if species == null:
		return ""
	var common: String = species.common_name.strip_edges()
	if not common.is_empty():
		return common
	return species.botanical_name.strip_edges()
