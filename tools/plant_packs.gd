class_name PlantPacks
extends RefCounted
## The plant models pulled in from outside packs, and the shape each one stands for.
##
## ## Why the models come from a pack at all
##
## This project draws a plant twice: the plan draws it as its **symbol** and the 3D view draws it as
## its **model**, and until now most models were one of three primitive props (`tree.tscn`,
## `shrub.tscn`, `flower_bed.tscn`) standing in for every plant in the catalogue. `tools/plant_models.gd`
## builds a model for each of the six shapes nobody sells, but a **tree** or a **shrub** is a shape
## every low-poly kit in the world has, drawn better than a cylinder with spheres on it.
##
## So the tree, shrub, grass and groundcover shapes are **pulled from a pack** - one folder of `.glb`
## files under `DIR`, one model per file - and the model a species is planted as is **the model of the
## shape the plan already draws it as**. That is the whole rule (`SHAPE_MODELS`, keyed by symbol), and
## it means the two views cannot drift: whatever the plan calls a spruce, the garden plants as.
##
## ## The pack this is
##
## **Kenney's Nature Kit**, CC0, 330 models, nothing to sign up for: `SOURCE` is the page and
## `ARCHIVE` the zip it hands out, whose models live under `ARCHIVE_PATH`. Thirteen of its plant
## models are pulled in - the ones whose names are *shapes* (`tree_oak`, `plant_bush`, `grass`) rather
## than some other species' name, so pointing a maple at one is not a claim about the maple. Each is a
## few hundred triangles, so a bed of fifty is nothing.
##
## The pack's material is `KHR_materials_unlit`: the models arrive flat-shaded and keep the kit's own
## palette. The plan is unaffected - it takes its colour from `PlanStyle.COLOURS` and its shape from
## the symbol - so a garden and its drawing still agree about what is planted where.
##
## ## What is measured rather than typed
##
## A model is planted at `spread / footprint` (`PlantPlacement.place`), so the footprint recorded in
## `PlanStyle.SYMBOLS` has to be the model's **real** one: a number typed in by hand that is 30% out
## puts every plant of that shape at the wrong size while every view still looks plausible. `measure()`
## walks the model's meshes and `run()` prints what it found, and `tests/test_plant_packs.gd` measures
## the files on disk against the table every time the suite runs.

const SpeciesScript := preload("res://scripts/plant_species.gd")
const CatalogueScript := preload("res://scripts/plant_catalogue.gd")
const SymbolsScript := preload("res://scripts/plant_symbols.gd")
const PlanStyleScript := preload("res://scripts/plan_style.gd")
const ModelsScript := preload("res://tools/plant_models.gd")
const ExpansionScript := preload("res://tools/plant_expansion.gd")

## The plant list this writes models onto: the same file the expansion tool builds.
const SHIPPED := ExpansionScript.SHIPPED_PATH

## Where the pack's models live: one `<id>.glb` per model, beside this table.
const DIR := "res://assets/plants/kenney"
const SUFFIX := ".glb"

## The pack, its licence, and where a copy comes from.
const PACK := "Kenney Nature Kit"
const LICENCE := "CC0-1.0"
const SOURCE := "https://kenney.nl/assets/nature-kit"
const ARCHIVE := "https://kenney.nl/media/pages/assets/nature-kit/37ac38a37b-1677698939/kenney_nature-kit.zip"
const ARCHIVE_PATH := "Models/GLTF format"

## The shapes the pack draws, and the models that stand for each. **The shape is the plan symbol**
## (`PlantSymbols`), so a species is planted as the model of the shape its own drawing uses.
##
## Several models to a shape on purpose: the shapes are shared out between the species of that shape
## by **genus** (`assignment`), so a border of nine grasses does not stand in the garden as nine
## copies of one tuft. Cultivars of one genus share a model, which is right - they are the same plant.
const SHAPE_MODELS := {
	&"canopy": ["tree_oak", "tree_detailed", "tree_default", "tree_fat"],
	&"shrub": ["plant_bushDetailed", "plant_bushLarge", "plant_bush", "plant_bushTriangle"],
	&"grass": ["grass", "grass_large", "grass_leafsLarge"],
	&"groundcover": ["plant_flatTall", "plant_bushSmall"],
}

## The shapes no kit sells as a single plant, and the model this project **built** for each, by its id
## in `tools/plant_models.gd`. A bed is an oblong planting, a fern a rosette of fronds, and a vine
## climbs: none of them is a shape a low-poly kit has, so these are modelled here rather than pulled.
const SHAPE_BUILT := {
	&"conifer": "conifer",
	&"fern": "fern",
	&"vine": "vine",
	&"bed": "perennial",
}


# --- the models -------------------------------------------------------------------------------


## Every model pulled in, alphabetical.
static func ids() -> Array[String]:
	var out: Array[String] = []
	for shape: StringName in SHAPE_MODELS:
		for id: String in SHAPE_MODELS[shape]:
			out.append(id)
	out.sort()
	return out


## Where a pulled model's file is.
static func path_for(id: String) -> String:
	return "%s/%s%s" % [DIR, id, SUFFIX]


## The shape a pulled model stands for, or empty when this is not one of ours.
static func shape_of(id: String) -> StringName:
	for shape: StringName in SHAPE_MODELS:
		if (SHAPE_MODELS[shape] as Array).has(id):
			return shape
	return &""


## The plan symbol a pulled model is drawn as. The shape *is* the symbol, which is what makes the two
## views agree; the built models are keyed the same way in `PlanStyle.SYMBOLS` by hand.
static func symbol_of(id: String) -> StringName:
	return shape_of(id)


## The symbol the plan draws a species as. Worked out exactly the way `PlantPlacement.place` works it
## out - what the plant *is* where the catalogue says (a spruce is a conifer), and what its prop draws
## as where it does not (a perennial is drawn as the bed it is planted as). Asking the same question
## the planting asks is what makes the two answers the same; asking a different one had every
## perennial answer "no model" and left fifty-seven plants standing in the garden as a raised bed.
static func symbol_of_species(species: SpeciesScript) -> StringName:
	return SymbolsScript.of(species, PlanStyleScript.spec_for(species.form)["symbol"])


## The pulled model paths that stand for a shape, in the order species are given them.
static func paths_for(shape: StringName) -> Array[String]:
	var out: Array[String] = []
	for id: String in SHAPE_MODELS.get(shape, []):
		out.append(path_for(id))
	return out


## The path of the model a species is planted as: the model of the **shape its plan symbol is**, a
## pulled one where the pack draws that shape and a built one where it does not.
##
## Empty for a species whose shape has no model at all, which is the honest answer - the plant is then
## planted as its `form`, the generic prop, exactly as every plant was before any of this.
static func model_for(species: SpeciesScript, index: int) -> String:
	var shape: StringName = symbol_of_species(species)
	if SHAPE_BUILT.has(shape):
		return ModelsScript.path_for(SHAPE_BUILT[shape])
	var paths: Array[String] = paths_for(shape)
	if paths.is_empty():
		return ""
	return paths[index % paths.size()]


# --- measuring a model ------------------------------------------------------------------------


## A model's real size, in metres, and the triangle count that says whether a garden of them can be
## drawn. Also the two things a planted model needs and a bounding box alone does not give: how far
## below the origin its lowest vertex sits, and how far its centre is off the origin sideways.
##
## Returns `{ok, reason, width_m, depth_m, height_m, footprint_m, base_y, offset_x, offset_z, tris}`.
static func measure(path: String) -> Dictionary:
	if not ResourceLoader.exists(path):
		return _failed("there is no model at %s" % path)
	var packed: PackedScene = ResourceLoader.load(path, "PackedScene") as PackedScene
	if packed == null:
		return _failed("%s does not load as a scene" % path)
	var model: Node = packed.instantiate()
	if model == null:
		return _failed("%s does not instantiate" % path)
	var acc: Array = [null, 0]
	_measure_node(model, Transform3D(), acc)
	model.free()
	var box: AABB = acc[0]
	if box == null:
		return _failed("%s has no meshes in it" % path)
	return {
		"ok": true,
		"reason": "",
		"width_m": box.size.x,
		"depth_m": box.size.z,
		"height_m": box.size.y,
		"footprint_m": maxf(box.size.x, box.size.z),
		"base_y": box.position.y,
		"offset_x": box.position.x + box.size.x * 0.5,
		"offset_z": box.position.z + box.size.z * 0.5,
		"tris": int(acc[1]),
	}


static func _measure_node(node: Node, xf: Transform3D, acc: Array) -> void:
	var here: Transform3D = xf
	if node is Node3D:
		here = xf * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		var box: AABB = here * mesh.get_aabb()
		acc[0] = box if acc[0] == null else (acc[0] as AABB).merge(box)
		acc[1] += int(float(mesh.get_faces().size()) / 3.0)
	for child: Node in node.get_children():
		_measure_node(child, here, acc)


## The same, for a model named by its id in this pack.
static func measurement_of(id: String) -> Dictionary:
	return measure(path_for(id))


static func _failed(reason: String) -> Dictionary:
	return {
		"ok": false, "reason": reason, "width_m": 0.0, "depth_m": 0.0, "height_m": 0.0,
		"footprint_m": 0.0, "base_y": 0.0, "offset_x": 0.0, "offset_z": 0.0, "tris": 0,
	}


# --- which species gets which model ------------------------------------------------------------


## The genus of a species, which is what shares a model out. Taken from the botanical name, so
## "Acer rubrum 'Autumn Blaze'" is an Acer.
static func genus_of(species: SpeciesScript) -> String:
	var words: PackedStringArray = species.botanical_name.strip_edges().split(" ", false)
	if words.size() == 0:
		return species.botanical_name.strip_edges()
	return words[0]


## Every species of the list, with the model it is planted as, as `{id: path}`.
##
## A species' place among the models of its shape is its **genus'** place among the genera of that
## shape, taken in alphabetical order, so the whole assignment is a function of the list: adding a
## plant changes one plant's model and nothing else's.
static func assignment(catalogue: CatalogueScript) -> Dictionary:
	var ids: Array[StringName] = catalogue.ids()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		return String(a) < String(b))
	var genera: Dictionary = {}
	for id: StringName in ids:
		var shape: StringName = symbol_of_species(catalogue.get_species(id))
		var genus: String = genus_of(catalogue.get_species(id))
		genera["%s|%s" % [shape, genus]] = true
	var ranked: Dictionary = {}
	for shape: StringName in SHAPE_MODELS:
		var mine: Array[String] = []
		for key: String in genera:
			var parts: PackedStringArray = key.split("|")
			if parts.size() == 2 and parts[0] == String(shape):
				mine.append(parts[1])
		mine.sort()
		for i: int in range(mine.size()):
			ranked["%s|%s" % [shape, mine[i]]] = i
	var out: Dictionary = {}
	for id: StringName in ids:
		var species: SpeciesScript = catalogue.get_species(id)
		var shape: StringName = symbol_of_species(species)
		var index: int = int(ranked.get("%s|%s" % [shape, genus_of(species)], 0))
		out[id] = model_for(species, index)
	return out


## Write the assignment onto the shipped plant list.
##
## Through `PlantCatalogue.save_to`, which is the same writer the list was built with, so the file is
## not reformatted by having its models filled in: the diff is one line per plant whose model changed.
## Returns `{ok, reason, shaped, built, formed, total}`.
static func apply() -> Dictionary:
	var read: Dictionary = CatalogueScript.load_from(SHIPPED)
	if not bool(read["ok"]):
		return _apply_failed("the shipped list would not load: %s" % String(read["reason"]))
	var catalogue: CatalogueScript = read["catalogue"]
	var chosen: Dictionary = assignment(catalogue)
	var shaped: int = 0
	var built: int = 0
	var formed: int = 0
	for id: StringName in catalogue.ids():
		var path: String = String(chosen[id])
		catalogue.get_species(id).model_scene = path
		if path.is_empty():
			formed += 1
		elif path.begins_with(DIR):
			shaped += 1
		else:
			built += 1
	var saved: Dictionary = catalogue.save_to(SHIPPED)
	if not bool(saved["ok"]):
		return _apply_failed("the list was not written: %s" % String(saved["reason"]))
	return {
		"ok": true, "reason": "", "shaped": shaped, "built": built, "formed": formed,
		"total": catalogue.count(),
	}


static func _apply_failed(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "shaped": 0, "built": 0, "formed": 0, "total": 0}


# --- the report ----------------------------------------------------------------------------------


## What is in the pack, measured: one row per model with the numbers the style table wants.
##
## This is the tool's output rather than its input. Run it with `execute_script` and print it: the
## sizes are what `PlanStyle.SYMBOLS` has to say, and `symbol_source()` writes them out as the table
## itself rather than as a list to retype.
static func run() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in ids():
		var path: String = path_for(id)
		var found: Dictionary = measure(path)
		out.append({
			"id": id,
			"path": path,
			"shape": String(shape_of(id)),
			"symbol": String(symbol_of(id)),
			"size": Vector2(found["footprint_m"], found["footprint_m"]),
			"measured": found,
		})
	return out


## The `PlanStyle.SYMBOLS` entries for the pack, as the source text of the table.
##
## Written out rather than retyped, because a footprint is the one number in this program that a
## person cannot check by looking: the plant would simply be planted at the wrong size, everywhere,
## for ever.
static func symbol_source() -> String:
	var lines: PackedStringArray = PackedStringArray()
	for row: Dictionary in run():
		var found: Dictionary = row["measured"]
		if not bool(found["ok"]):
			lines.append("\t# %s: %s" % [row["id"], String(found["reason"])])
			continue
		lines.append("\t\"%s\": {" % row["path"])
		lines.append("\t\t\"symbol\": &\"%s\", \"size\": Vector2(%.2f, %.2f), \"wash\": FOLIAGE_WASH," % [
			row["symbol"], found["footprint_m"], found["footprint_m"]])
		lines.append("\t},")
	return "\n".join(lines)