class_name PlantPlacement
extends RefCounted
## Putting a catalogue species into the design.
##
## A species is not a thing on the plan; it is a *description* of one. What stands on the plan is a
## prop node under the yard's `Plants` subtree, and both views already agree about those: the plan
## draws whatever is in that subtree as its prop's symbol, and the 3D view draws the prop itself.
## So planting a species is one operation - instance its scene, size it the way the catalogue says,
## and put it in the subtree both views read - and no view needs to learn about species at all.
##
## The size is the whole point of the link. The tree scene is 3.7 m across because a generic tree is
## 3.7 m across; a red maple spreads 9 m. A species is planted at `spread / base`, so a red maple
## instance is 2.43x the generic tree, and its plan symbol, its footprint, its 3D model and the
## number in the planting schedule are all the same plant at the same size. The base size comes from
## `PlanStyle`, because "how big is this prop scene" is a plan-style question and not a plant one.

const PlanStyleScript := preload("res://scripts/plan_style.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")

## The subtree of the yard whose children are the planted objects. The same name `PlanCanvas` reads.
const PLANTS := "Plants"

## Node metadata: which species a planted node is, and the height the catalogue gave it. Stored on
## the node rather than in a side table, so moving or copying a plant node in the editor carries its
## species with it and nothing can fall out of step with what is on screen.
const SPECIES_META := &"species"
const HEIGHT_META := &"height_cm"
const SPREAD_META := &"spread_cm"


## The yard's `Plants` node, made if the yard does not have one yet. Returns null only when given
## something that is not a node.
static func plants_node(yard: Node) -> Node3D:
	if yard == null:
		return null
	var found: Node = yard.get_node_or_null(PLANTS)
	if found is Node3D:
		return found
	var made := Node3D.new()
	made.name = PLANTS
	yard.add_child(made)
	return made


## Plant one species at a world point.
##
## Returns `{ok, reason, node, scale, species}`. Refusals name what is missing rather than planting
## nothing and saying nothing: a species whose scene is not on disk would otherwise be a click that
## does nothing at all.
static func place(
	catalogue: PlantCatalogue, species_id: StringName, yard: Node, at: Vector3
) -> Dictionary:
	if catalogue == null:
		return _refuse("there is no plant list open")
	var species: PlantSpecies = catalogue.get_species(species_id)
	if species == null:
		return _refuse("the plant list has no species %s" % species_id)
	var path: String = species.model_scene if not species.model_scene.is_empty() else species.form
	var scene: PackedScene = catalogue.scene_for(species_id)
	if scene == null:
		return _refuse("%s is not a scene that can be planted" % path)
	var parent: Node3D = plants_node(yard)
	if parent == null:
		return _refuse("there is no yard to plant into")

	var node: Node3D = scene.instantiate() as Node3D
	if node == null:
		return _refuse("%s does not instantiate as a 3D object" % path)

	# The symbol the plan will draw comes from the instanced scene's own path, so the base size is
	# looked up from that and not from the species' `form`: a species with a model of its own is
	# drawn as *that* model, and sizing it against a different prop's footprint would be sizing it
	# against a symbol nobody ever sees.
	# The scene path is what `PlanStyle` keys the symbol on, so it is written down rather than
	# assumed to have been set by the instantiate: a prop node with an empty `scene_file_path`
	# would be drawn as the placeholder marker, which is a plant the plan cannot identify.
	if node.scene_file_path.is_empty():
		node.scene_file_path = path
	var instanced_path: String = node.scene_file_path
	var base_size: float = float((PlanStyleScript.spec_for(instanced_path)["size"] as Vector2).x)
	var planting_scale: float = species.planting_scale(base_size)

	# Out of the tree while it is being set up: an instance is not a design object until it is in
	# the yard, and adding it first would let the group and the transform arrive in either order.
	node.name = unique_name(parent, String(species_id))
	node.position = Vector3(at.x, at.y, at.z)
	node.scale = Vector3.ONE * planting_scale
	node.set_meta(SPECIES_META, String(species_id))
	node.set_meta(HEIGHT_META, species.height_cm)
	node.set_meta(SPREAD_META, species.spread_cm)
	# The group `ViewController` and the plan view both read to decide what is selectable, so a
	# planted species is draggable the moment it lands and needs no second registration.
	node.add_to_group(Yard.PLACEABLE_GROUP)
	parent.add_child(node)
	return {
		"ok": true, "reason": "", "node": node, "scale": planting_scale, "species": species,
	}


static func _refuse(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "node": null, "scale": 1.0, "species": null}


## A name that is not already taken under `parent`. Godot renames a duplicate by itself, but it
## numbers from the *second* one and the first keeps the bare name, which makes a planting list read
## as "shrub, shrub2, shrub3" in an order nobody chose. Numbering from the first keeps it in step.
static func unique_name(parent: Node, base: String) -> String:
	var clean: String = base.strip_edges()
	if clean.is_empty():
		clean = "plant"
	var taken: Array[String] = []
	for child in parent.get_children():
		taken.append(String(child.name))
	if not taken.has(clean):
		return clean
	var index: int = 1
	while taken.has("%s-%d" % [clean, index]):
		index += 1
	return "%s-%d" % [clean, index]


## Which species a planted node is, or empty when it was placed before there was a catalogue.
static func species_of(node: Node) -> StringName:
	if node == null or not node.has_meta(SPECIES_META):
		return &""
	return StringName(node.get_meta(SPECIES_META))


# --- the planting list ------------------------------------------------------------------


## Every plant standing in the yard, counted by species, as the schedule a planting plan carries:
## one row per species with its size and how many of it there are. Rows are sorted by botanical name
## so the list is the same list on every run, and a node with no species on it is **counted and
## named separately** rather than dropped - a plant on the plan that the catalogue cannot name is
## the one thing a planting list must not hide.
static func schedule(catalogue: PlantCatalogue, yard: Node) -> Array[Dictionary]:
	var counts: Dictionary = {}
	var unknown: int = 0
	for node: Node3D in planted(yard):
		var id: StringName = species_of(node)
		if id.is_empty() or catalogue == null or not catalogue.has(id):
			unknown += 1
			continue
		counts[id] = int(counts.get(id, 0)) + 1
	var rows: Array[Dictionary] = []
	for id: StringName in counts.keys():
		var species: PlantSpecies = catalogue.get_species(id)
		rows.append({
			"id": id,
			"count": int(counts[id]),
			"botanical_name": species.botanical_name,
			"common_name": species.common_name,
			"cultivar": species.cultivar,
			"category_name": species.category_name(),
			"spread_cm": species.spread_cm,
			"height_cm": species.height_cm,
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var order: int = String(a["botanical_name"]).naturalnocasecmp_to(String(b["botanical_name"]))
		if order != 0:
			return order < 0
		return String(a["cultivar"]).naturalnocasecmp_to(String(b["cultivar"])) < 0)
	if unknown > 0:
		# Named as the thing to go and fix rather than as a fact about the plant: these are the props
		# that were placed before there was a catalogue to say what they are, and a schedule that
		# called them "unidentified" would read as though the *plant* were the problem.
		rows.append({
			"id": &"", "count": unknown, "botanical_name": "no species recorded", "common_name": "",
			"cultivar": "", "category_name": "", "spread_cm": 0, "height_cm": 0,
		})
	return rows


## The planted nodes in the yard, as 3D nodes. Reads the `Plants` subtree rather than the
## `placeable` group, because a plant that has been dropped in by hand in the editor is still a
## plant and belongs on the list even if nobody tagged it.
static func planted(yard: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if yard == null:
		return out
	var parent: Node = yard.get_node_or_null(PLANTS)
	if parent == null:
		return out
	for child in parent.get_children():
		if child is Node3D:
			out.append(child)
	return out


## The planting list as a person reads it, one line per species, the way a schedule on a sheet is
## written. Empty when nothing is planted.
static func schedule_text(catalogue: PlantCatalogue, yard: Node) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for row: Dictionary in schedule(catalogue, yard):
		var words: String = String(row["botanical_name"])
		if not String(row["cultivar"]).is_empty():
			words = "%s '%s'" % [words, String(row["cultivar"])]
		lines.append("%d x %s" % [int(row["count"]), words])
	return "\n".join(lines)