extends Node
## The plant models pulled in from the outside pack, and the shape each one stands for.
##
## A downloaded model is the one asset in this project that nothing else can vouch for: it was made
## elsewhere, nobody here measured it, and a model whose footprint is wrong puts every plant of its
## shape at the wrong size while both views still look plausible. So the tests here **measure the
## files on disk** - the size against the style table's declaration, the height against its own
## origin, the triangle count against what a garden can draw - and hold the catalogue to the one rule
## the whole pack rests on: **a species is planted as the model of the shape the plan draws it as**.

const Packs := preload("res://tools/plant_packs.gd")
const PlanStyleScript := preload("res://scripts/plan_style.gd")
const SymbolsScript := preload("res://scripts/plant_symbols.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")
const CatalogueScript := preload("res://scripts/plant_catalogue.gd")
const PlacementScript := preload("res://scripts/plant_placement.gd")

## The shapes the pack draws, as the plan symbol each is drawn as.
const PULLED: Array[StringName] = [
	SymbolsScript.CANOPY, SymbolsScript.SHRUB, SymbolsScript.GRASS, SymbolsScript.GROUNDCOVER,
]

## A model's triangle ceiling. A planting bed of fifty plants at this is a hundred thousand
## triangles, which is what the compatibility renderer draws a garden of; a model over it is a model
## that cannot be planted thirty of, however good it looks on its own.
const TRI_CEILING := 2000

## How far below its own origin a model's lowest vertex may sit. The pack's models all dip five
## centimetres, which is on purpose - it is what makes a plant look planted - so the ceiling is a
## hand's width and the floor is nothing above the ground at all: a model whose base is *above* its
## origin floats over the lawn for ever, and no view would call it a fault.
const BASE_FLOOR := -0.10
const BASE_CEILING := 0.02

## How far off its own origin a model's centre may sit, as a fraction of its width. Not zero: a plant
## is not symmetrical, and the pack's grass tuft leans four centimetres off centre on a thirty-nine
## centimetre clump, which is the model being a plant rather than a fault. A model authored in a
## corner of its own space is out by half its width and is what this catches.
const CENTRE_SLACK := 0.15


# --- helpers ------------------------------------------------------------------------------------


func _catalogue() -> PlantCatalogue:
	var read: Dictionary = CatalogueScript.load_from(Packs.SHIPPED)
	assert(bool(read["ok"]), "the shipped list loads: %s" % String(read["reason"]))
	return read["catalogue"]


## A pulled model, instanced. The caller frees it.
func _instance(id: String) -> Node3D:
	var path: String = Packs.path_for(id)
	assert(ResourceLoader.exists(path, "PackedScene"), "%s is on disk" % path)
	var packed: PackedScene = ResourceLoader.load(path, "PackedScene") as PackedScene
	assert(packed != null, "%s loads as a scene" % path)
	var node: Node3D = packed.instantiate() as Node3D
	assert(node != null, "%s instantiates as a 3D object" % path)
	return node


## The model a species is planted as, as its id in this pack.
func _model_of(catalogue: PlantCatalogue, id: String) -> String:
	var species: PlantSpecies = catalogue.get_species(StringName(id))
	assert(species != null, "%s is in the list" % id)
	return species.model_scene.get_file().get_basename()


# --- the files ----------------------------------------------------------------------------------


func test_every_model_the_pack_names_is_on_disk_as_a_loadable_scene() -> void:
	for id: String in Packs.ids():
		var node: Node3D = _instance(id)
		# The plan keys its style table on the path an instanced scene reports, so a model whose
		# node does not know where it came from would be drawn at the placeholder size by both views.
		assert(
			node.scene_file_path == Packs.path_for(id),
			"%s knows the file it came from: %s" % [id, node.scene_file_path]
		)
		node.free()


func test_no_model_in_the_folder_is_one_the_table_does_not_name() -> void:
	# A model dropped into the folder but not into the table is a file nothing measures and nobody
	# can plant, and it would sit there looking like part of the pack for ever.
	var folder := DirAccess.open(Packs.DIR)
	assert(folder != null, "the pack folder is there: %s" % Packs.DIR)
	for file: String in folder.get_files():
		if not file.ends_with(Packs.SUFFIX):
			continue
		assert(
			Packs.ids().has(file.get_basename()),
			"%s is a model this table names" % file
		)
	assert(Packs.ids().size() >= 4, "and the table is not empty: %d models" % Packs.ids().size())


func test_every_model_is_the_size_its_plan_style_entry_declares() -> void:
	# The test worth having: a plant is planted at `spread / size.x`, so a declared footprint that is
	# 30% out puts every plant of that shape at the wrong size for ever, and every view still looks
	# plausible. The number in the table is the number measured here.
	for id: String in Packs.ids():
		var path: String = Packs.path_for(id)
		var spec: Dictionary = PlanStyleScript.spec_for(path)
		var shape: StringName = Packs.shape_of(id)
		assert(not shape.is_empty(), "%s stands for a shape" % id)
		assert(spec["symbol"] == shape, "%s draws as %s, not %s" % [id, shape, spec["symbol"]])
		assert(SymbolsScript.is_symbol(shape), "%s is a symbol the plan can draw: %s" % [id, shape])
		assert(SymbolsScript.is_round(shape), "%s is drawn as a round footprint" % shape)
		var found: Dictionary = Packs.measurement_of(id)
		assert(bool(found["ok"]), "%s could be measured: %s" % [id, String(found["reason"])])
		var declared: Vector2 = spec["size"]
		var measured: float = found["footprint_m"]
		assert(
			absf(declared.x - measured) <= declared.x * 0.05 + 0.01,
			"%s is %.3f m across and its entry says %.2f m" % [id, measured, declared.x]
		)
		assert(
			is_equal_approx(declared.x, declared.y),
			"%s is declared square, which is what a round symbol is drawn from" % id
		)


func test_every_model_stands_on_its_own_origin_and_is_centred_on_it() -> void:
	# A plant is put where the drawing says, at the scale the catalogue says, and it stands or falls
	# by where its own origin is: a model floating above the ground hangs in the air for ever, and one
	# whose trunk is a third of a metre to one side misses the spot the plan drew.
	for id: String in Packs.ids():
		var found: Dictionary = Packs.measurement_of(id)
		assert(bool(found["ok"]), "%s could be measured" % id)
		var base: float = found["base_y"]
		assert(
			base >= BASE_FLOOR and base <= BASE_CEILING,
			"%s stands on its origin: its lowest point is %.3f m off it" % [id, base]
		)
		assert(float(found["height_m"]) > 0.1, "%s has a height to it: %.3f m" % [id, found["height_m"]])
		var across: float = found["footprint_m"]
		assert(
			absf(found["offset_x"]) <= across * CENTRE_SLACK and absf(found["offset_z"]) <= across * CENTRE_SLACK,
			"%s is centred: (%.3f, %.3f) of %.2f m" % [id, found["offset_x"], found["offset_z"], across]
		)


func test_every_model_is_light_enough_to_plant_a_bed_of() -> void:
	var total: int = 0
	for id: String in Packs.ids():
		var found: Dictionary = Packs.measurement_of(id)
		assert(
			int(found["tris"]) <= TRI_CEILING,
			"%s is %d triangles, under the %d a garden can draw" % [id, found["tris"], TRI_CEILING]
		)
		total += int(found["tris"])
	assert(total <= 5000, "and the whole pack is %d triangles" % total)


func test_the_pack_is_one_licence_and_one_source() -> void:
	# Nothing here is inferred from the folder name: if a pack cannot say where it came from and what
	# it may be used for, it is a stack of files somebody will have to trace one day.
	assert(Packs.LICENCE == "CC0-1.0", "the pack is public domain: %s" % Packs.LICENCE)
	assert(Packs.SOURCE.begins_with("https://"), "the pack says where it came from: %s" % Packs.SOURCE)
	assert(Packs.ARCHIVE.begins_with("https://"), "and where a copy is: %s" % Packs.ARCHIVE)
	assert(not Packs.ARCHIVE_PATH.is_empty(), "and where the models are in it: %s" % Packs.ARCHIVE_PATH)
	assert(Packs.DIR.begins_with("res://assets/plants/"), "and they live with the other plant assets")


# --- the catalogue points at them ---------------------------------------------------------------


func test_a_tree_shrub_grass_or_mat_is_planted_as_one_of_the_packs_models() -> void:
	var catalogue: PlantCatalogue = _catalogue()
	var shaped: int = 0
	for id: StringName in catalogue.ids():
		var plant: PlantSpecies = catalogue.get_species(id)
		var drawn: StringName = Packs.symbol_of_species(plant)
		if not PULLED.has(drawn):
			continue
		shaped += 1
		assert(
			plant.model_scene.begins_with(Packs.DIR + "/"),
			"%s is drawn as %s and planted as %s" % [id, drawn, plant.model_scene]
		)
	assert(shaped >= 40, "and the pack's shapes are the ones the list is full of: %d" % shaped)


func test_the_shipped_list_is_the_assignment_this_tool_builds() -> void:
	# The list is data and this tool is its writer, exactly as the expansion tool owns which plants are
	# in it. A list hand-edited out of step with the table is a plant whose model nobody chose.
	var catalogue: PlantCatalogue = _catalogue()
	var chosen: Dictionary = Packs.assignment(catalogue)
	for id: StringName in catalogue.ids():
		assert(
			catalogue.get_species(id).model_scene == String(chosen[id]),
			"%s is planted as %s in the list" % [id, String(chosen[id])]
		)


func test_the_shapes_are_shared_out_between_the_genera_that_use_them() -> void:
	# One model for every shrub would be one shrub forty times over, which is what the three generic
	# props already were. So the genera of a shape are spread across its models - in order, from the
	# list, so the assignment is a function of the catalogue rather than of when it was run.
	var catalogue: PlantCatalogue = _catalogue()
	var used: Dictionary = {}
	var by_genus: Dictionary = {}
	for id: StringName in catalogue.ids():
		var plant: PlantSpecies = catalogue.get_species(id)
		if not PULLED.has(Packs.symbol_of_species(plant)):
			continue
		used[plant.model_scene] = true
		var key: String = "%s|%s" % [Packs.symbol_of_species(plant), Packs.genus_of(plant)]
		if by_genus.has(key):
			assert(
				by_genus[key] == plant.model_scene,
				"two %s share one model: %s and %s" % [Packs.genus_of(plant), by_genus[key], plant.model_scene]
			)
		by_genus[key] = plant.model_scene
	assert(used.size() >= 8, "the shapes use %d models between them" % used.size())
	var again: Dictionary = Packs.assignment(catalogue)
	var chosen: Dictionary = Packs.assignment(catalogue)
	assert(JSON.stringify(again) == JSON.stringify(chosen), "and the assignment is the same every time")


# --- planting through the real pipeline ---------------------------------------------------------


func test_planting_a_maple_puts_a_tree_model_in_the_yard_at_the_catalogue_size() -> void:
	# End to end, through the code the tool calls: the model, the scale the catalogue says, and the
	# symbol the plan will draw, all from one plant. The scale is checked against the model's *measured*
	# footprint rather than a number typed here, so a model replaced by a wider one is caught.
	var catalogue: PlantCatalogue = _catalogue()
	var maple: PlantSpecies = catalogue.get_species(&"acer-rubrum-autumn-blaze")
	var model: String = Packs.path_for(_model_of(catalogue, "acer-rubrum-autumn-blaze"))
	assert(ResourceLoader.exists(model), "the maple's model is on disk: %s" % model)
	var footprint: float = PlanStyleScript.spec_for(model)["size"].x
	var measured: float = Packs.measure(model)["footprint_m"]

	var yard := Node3D.new()
	var placed: Dictionary = PlacementScript.place(catalogue, &"acer-rubrum-autumn-blaze", yard, Vector3(4.0, 0.0, 1.5))
	assert(bool(placed["ok"]), "the maple was planted: %s" % String(placed["reason"]))
	var node: Node3D = placed["node"] as Node3D
	assert(node != null, "and there is a node")
	assert(node.scene_file_path == model, "it is the pack's tree: %s" % node.scene_file_path)
	assert(
		is_equal_approx(node.scale.x, maple.spread_m() / footprint),
		"scaled by the catalogue's spread over the model's own footprint: %.3f of %.3f" % [
			node.scale.x, maple.spread_m() / footprint]
	)
	assert(
		absf(footprint - measured) <= footprint * 0.05 + 0.01,
		"and that footprint is the model's real one: %.3f against %.3f" % [footprint, measured]
	)
	assert(node.position.is_equal_approx(Vector3(4.0, 0.0, 1.5)), "standing where it was asked to stand")
	assert(PlanStyleScript.symbol_of(node) == SymbolsScript.CANOPY, "and the plan draws it as a canopy")
	assert(
		is_equal_approx(PlanStyleScript.footprint_size(node).x, maple.spread_m()),
		"at its own %.2f m across, not the model's: %.2f" % [
			maple.spread_m(), PlanStyleScript.footprint_size(node).x]
	)
	yard.free()