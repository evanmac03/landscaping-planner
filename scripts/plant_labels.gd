class_name PlantLabels
extends RefCounted
## Where a planting plan says what is standing there: one label per species,
## standing at the middle of the group it names.
##
## The label is *derived* from the plants rather than typed, so it cannot disagree
## with the plan it sits on: move a plant and the middle moves with it, plant
## another and the count changes. This file owns no yard and no catalogue - it is
## handed positions and the name to print for each of them - so the whole decision
## is testable with three points and no scene.
##
## A plant standing under no name is labelled as such rather than dropped. A plan
## that quietly omits the plant nobody can name is the one mistake a planting plan
## must not make.

## What a plant the list cannot name is called on the drawing.
const UNKNOWN_NAME := "no species"
## The height a plan label is written at, in paper millimetres. A planting label is
## read on a sheet at the sheet's own scale, so it is a paper property and not a
## model one - the same reason a dimension's text height is in millimetres.
const LABEL_HEIGHT_MM := 2.5


## The middle of a group: the mean of its plants.
##
## A mean rather than a bounding box's centre, because one plant set a long way out
## should drag its group's label towards itself, and a mean is also what a person
## means by "where the group is".
static func centroid(points: PackedVector2Array) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var total := Vector2.ZERO
	for point: Vector2 in points:
		total += point
	return total / float(points.size())


## What one label says.
##
## `keyed` is for the day a plan carries a key lettered A, B, C: then the label is
## the key alone and the key says the name. Until then the name is on the label,
## because a plan that does not key its plants has to name them.
static func label_text(name: String, count: int, keyed: bool = false) -> String:
	if keyed:
		return "%d" % count
	return "%s (%d)" % [name, count]


## One label per species, from a list of plants.
##
## Each plant is a dictionary of "species" (a `StringName` id), "name" (what to
## print for it) and "position" (a model `Vector2`). A plant with no position
## cannot be labelled and is passed over rather than guessed at.
##
## Returns `{"labels": [...], "skipped": n, "reason": ""}`. A label is
## `{"species": id, "text": String, "at": Vector2, "count": n}`. `skipped` counts
## the plants standing under no name, so a caller can say so out loud.
static func labels_for(plants: Array, keyed: bool = false) -> Dictionary:
	var groups: Dictionary = {}
	for entry in plants:
		var plant: Dictionary = entry
		if not (plant.get("position") is Vector2):
			continue
		var species: StringName = StringName(plant.get("species", ""))
		var name := String(plant.get("name", "")).strip_edges()
		if name.is_empty():
			name = UNKNOWN_NAME
		# Grouped by the species id where there is one, and by the name where there
		# is not: two plants the catalogue cannot name are still two plants of a kind.
		var key := String(species) if not String(species).is_empty() else UNKNOWN_NAME
		# A plain `Array` for the positions, because a packed array is a value: append
		# to one taken back out of a dictionary and the append is lost.
		var group: Dictionary = groups.get(key, {"name": name, "points": []})
		(group["points"] as Array).append(plant["position"])
		groups[key] = group

	var labels: Array[Dictionary] = []
	var skipped := 0
	for key: String in groups:
		var group: Dictionary = groups[key]
		var points: Array = group["points"]
		labels.append({
			"species": StringName(key),
			"text": label_text(String(group["name"]), points.size(), keyed),
			"at": centroid(PackedVector2Array(points)),
			"count": points.size(),
		})
		if key == UNKNOWN_NAME:
			skipped += points.size()
	# Sorted by what they say, so the same drawing always writes the same list.
	labels.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return String(first["text"]) < String(second["text"]))

	var reason := "nothing is planted" if labels.is_empty() else ""
	return {"labels": labels, "skipped": skipped, "reason": reason}


## How many plants the labels account for.
static func planted_count(labels: Array) -> int:
	var total := 0
	for entry: Dictionary in labels:
		total += int(entry.get("count", 0))
	return total


## The labels in one line, which is what goes on a status line.
static func summary(labels: Array) -> String:
	var wanted := planted_count(labels)
	if wanted == 0:
		return "nothing to label"
	return "%d label%s for %d plant%s" % [
		labels.size(), "" if labels.size() == 1 else "s",
		wanted, "" if wanted == 1 else "s",
	]