extends Node
## The plant models, and the shape each one is.
##
## A model asset is a file nothing in the program compiles: a model rebuilt at the wrong size, or a
## species pointed at another species' model, looks exactly like a model that is right. So the two
## things tested here are measured rather than read - the size of the asset against the footprint its
## `PlanStyle` entry declares, and the fact that the catalogue points each plant at the model for the
## shape the drawing already draws it as.

const ModelsScript := preload("res://tools/plant_models.gd")
const PlanStyleScript := preload("res://scripts/plan_style.gd")
const SymbolsScript := preload("res://scripts/plant_symbols.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")
const CatalogueScript := preload("res://scripts/plant_catalogue.gd")
const PlacementScript := preload("res://scripts/plant_placement.gd")

const LIST := "res://data/plants/nursery_list.json"

## The shape each model is, and the symbol the plan draws a plant of that shape as.
const SHAPES := {
	"conifer": SymbolsScript.CONIFER,
	"grass": SymbolsScript.GRASS,
	"groundcover": SymbolsScript.GROUNDCOVER,
	"vine": SymbolsScript.VINE,
	"fern": SymbolsScript.FERN,
	"perennial": SymbolsScript.BED,
}


# --- helpers ------------------------------------------------------------------------------------


## One model file, loaded and instanced. The caller frees it.
func _instance(id: String) -> Node3D:
	var path: String = ModelsScript.path_for(id)
	assert(ResourceLoader.exists(path, "PackedScene"), "%s is on disk" % path)
	var packed: PackedScene = ResourceLoader.load(path, "PackedScene") as PackedScene
	assert(packed != null, "%s loads as a scene" % path)
	var node: Node3D = packed.instantiate() as Node3D
	assert(node != null, "%s instantiates as a 3D object" % path)
	return node


## The bounding box of a model as the engine reads it, measured from its meshes: what is on disk,
## not what the builder meant to write.
func _bounds(node: Node3D) -> AABB:
	var box := AABB()
	var found := false
	for part: Node in node.get_children():
		var mesh_part := part as MeshInstance3D
		if mesh_part == null or mesh_part.mesh == null:
			continue
		var local: AABB = mesh_part.mesh.get_aabb()
		for corner: int in range(8):
			var point: Vector3 = mesh_part.transform * local.get_endpoint(corner)
			if not found:
				box = AABB(point, Vector3.ZERO)
				found = true
			else:
				box = box.expand(point)
	return box


func _catalogue() -> PlantCatalogue:
	var read: Dictionary = CatalogueScript.load_from(LIST)
	assert(bool(read["ok"]), "the shipped list loads: %s" % String(read["reason"]))
	return read["catalogue"]


## Every species in the list pointed at a given model.
func _pointed_at(catalogue: PlantCatalogue, path: String) -> Array[String]:
	var out: Array[String] = []
	for id: StringName in catalogue.ids():
		if catalogue.get_species(id).model_scene == path:
			out.append(String(id))
	return out


# --- the assets ---------------------------------------------------------------------------------


func test_every_model_the_builder_names_is_on_disk_as_a_loadable_scene() -> void:
	for id: String in ModelsScript.IDS:
		var node: Node3D = _instance(id)
		assert(node.get_child_count() >= 3, "%s is made of parts, not one shape: %d" % [id, node.get_child_count()])
		node.free()


func test_every_model_stands_on_the_ground() -> void:
	# A model whose lowest point is below its own origin is planted that far into the lawn, and
	# nothing in the program would ever say so - it would just look slightly wrong, forever.
	for id: String in ModelsScript.IDS:
		var node: Node3D = _instance(id)
		var box: AABB = _bounds(node)
		assert(
			absf(box.position.y) < 0.02,
			"%s stands on y = 0, not %.3f m below it" % [id, box.position.y]
		)
		assert(box.end.y > 0.1, "%s has a height to it: %.3f m" % [id, box.end.y])
		node.free()


func test_every_model_is_the_size_its_plan_style_entry_declares() -> void:
	# This is the test worth having. `PlantPlacement` plants an instance at `spread / size.x`, so the
	# declared footprint is the number every plant's real size comes from: a model rebuilt 20% wider
	# without its declaration moving would plant every one of its species at 20% under size, and every
	# view would still look plausible.
	for id: String in ModelsScript.IDS:
		var path: String = ModelsScript.path_for(id)
		var spec: Dictionary = PlanStyleScript.spec_for(path)
		assert(spec["symbol"] == SHAPES[id], "%s draws as %s" % [id, SHAPES[id]])
		var declared: Vector2 = spec["size"]
		var node: Node3D = _instance(id)
		var measured: float = maxf(_bounds(node).size.x, _bounds(node).size.z)
		var slack: float = declared.x * 0.05 + 0.01
		assert(
			absf(declared.x - measured) <= slack,
			"%s is %.2f m across and its entry says %.2f m" % [id, measured, declared.x]
		)
		node.free()


func test_every_model_is_a_shape_the_drawing_can_speak() -> void:
	for id: String in ModelsScript.IDS:
		var symbol: StringName = PlanStyleScript.spec_for(ModelsScript.path_for(id))["symbol"]
		assert(SymbolsScript.is_symbol(symbol), "%s is a symbol the plan knows: %s" % [id, symbol])


func test_the_models_are_the_shapes_they_say_they_are() -> void:
	# A model swapped for another one would be caught here rather than in a garden: a conifer is
	# taller than it is wide, a groundcover mat, a fern, a grass tuft and a planted bed are all wider
	# than they are tall, and a climber stands up rather than spreading.
	var conifer: Node3D = _instance("conifer")
	assert(_bounds(conifer).size.y > _bounds(conifer).size.x * 2.0, "a spruce is a spire")
	conifer.free()
	var vine: Node3D = _instance("vine")
	assert(_bounds(vine).size.y > _bounds(vine).size.x, "a climber climbs")
	vine.free()
	for id: String in ["groundcover", "perennial", "fern", "grass"]:
		var node: Node3D = _instance(id)
		assert(_bounds(node).size.y < _bounds(node).size.x, "%s is a low clump" % id)
		node.free()


func test_the_builder_and_the_assets_agree_about_what_is_built() -> void:
	# The builder is the record of how each asset was made. A model it names but never wrote, or a
	# file on disk it does not know how to rebuild, is an asset nobody can regenerate.
	for id: String in ModelsScript.IDS:
		assert(ResourceLoader.exists(ModelsScript.path_for(id)), "%s was written" % id)
	var folder := DirAccess.open(ModelsScript.OUT_DIR)
	assert(folder != null, "the model folder is there")
	for file: String in folder.get_files():
		if file.ends_with(".gltf"):
			var id: String = file.get_basename()
			assert(ModelsScript.IDS.has(id), "%s is a model this builder makes" % file)


# --- the catalogue points at them ---------------------------------------------------------------


func test_a_species_is_planted_as_the_shape_it_is_drawn_as() -> void:
	# The plan has drawn a spruce as a conifer since `PlantSymbols` was written, while the garden had
	# one tree model for every tree. These are the six that were furthest apart.
	var catalogue: PlantCatalogue = _catalogue()
	var expected := {
		"picea-pungens-hoopsii": "conifer",
		"calamagrostis-acutiflora-karl-foerster": "grass",
		"adiantum-pedatum": "fern",
		"hosta-patriot": "perennial",
		"clematis-jackmanii": "vine",
		"ajuga-reptans": "groundcover",
	}
	for id: String in expected:
		var species: PlantSpecies = catalogue.get_species(StringName(id))
		assert(species != null, "%s is in the list" % id)
		assert(species.model_scene == ModelsScript.path_for(expected[id]),
			"%s is planted as its %s: %s" % [id, expected[id], species.model_scene])


func test_every_species_of_a_shape_that_has_a_model_is_pointed_at_it() -> void:
	# The rule rather than the samples: a species added later with no model of its own is a species
	# that stands in the garden as a shrub, and the drawing will still call it a grass.
	var catalogue: PlantCatalogue = _catalogue()
	for id: StringName in catalogue.ids():
		var plant: PlantSpecies = catalogue.get_species(id)
		var wanted := ""
		if plant.is_conifer():
			wanted = ModelsScript.path_for("conifer")
		elif plant.category in [SpeciesScript.PERENNIAL, SpeciesScript.ANNUAL, SpeciesScript.BULB, SpeciesScript.HERB]:
			wanted = ModelsScript.path_for("perennial")
		elif plant.category == SpeciesScript.GRASS:
			wanted = ModelsScript.path_for("grass")
		elif plant.category == SpeciesScript.GROUNDCOVER:
			wanted = ModelsScript.path_for("groundcover")
		elif plant.category == SpeciesScript.VINE:
			wanted = ModelsScript.path_for("vine")
		elif plant.category == SpeciesScript.FERN:
			wanted = ModelsScript.path_for("fern")
		if wanted.is_empty():
			continue
		assert(
			plant.model_scene == wanted,
			"%s is planted as %s, not %s" % [id, wanted.get_file(), plant.model_scene if not plant.model_scene.is_empty() else "its form"]
		)


func test_a_tree_and_a_shrub_still_stand_on_the_generic_forms() -> void:
	# The two shapes where one prop for every species is right: a red maple is a broadleaf tree and
	# there is no separate model to give it. This holds the line against the wiring above growing
	# until every species carries a model of its own.
	var catalogue: PlantCatalogue = _catalogue()
	var maple: PlantSpecies = catalogue.get_species(&"acer-rubrum-autumn-blaze")
	assert(maple.model_scene.is_empty(), "a broadleaf tree is still its form")
	assert(maple.form == "res://scenes/props/tree.tscn", "and its form is the tree")
	var box: PlantSpecies = catalogue.get_species(&"buxus-sempervirens")
	assert(box.model_scene.is_empty(), "so is a shrub")
	assert(catalogue.missing_files().is_empty(), "and every path in the list is on disk")


func test_most_of_the_list_has_a_model_of_its_own_and_not_the_generic_three() -> void:
	var catalogue: PlantCatalogue = _catalogue()
	var with_model: int = 0
	for id: StringName in catalogue.ids():
		if not catalogue.get_species(id).model_scene.is_empty():
			with_model += 1
	assert(with_model >= 80, "four species in five are planted as what they are: %d" % with_model)
	assert(with_model < catalogue.count(), "and the generic forms are still doing the rest")


# --- planting through the real pipeline ---------------------------------------------------------


func test_planting_a_spruce_puts_the_conifer_in_the_yard_at_the_catalogue_size() -> void:
	# End to end, through the code the tool calls: the model, the scale the catalogue says, and the
	# symbol the plan will draw, all from one plant.
	var catalogue: PlantCatalogue = _catalogue()
	var yard := Node3D.new()
	var placed: Dictionary = PlacementScript.place(catalogue, &"picea-pungens-hoopsii", yard, Vector3(2.0, 0.0, -3.0))
	assert(bool(placed["ok"]), "the spruce was planted: %s" % String(placed["reason"]))
	var node: Node3D = placed["node"] as Node3D
	assert(node != null, "and there is a node")
	assert(node.scene_file_path == "res://assets/plants/conifer.gltf", "it is the conifer model: %s" % node.scene_file_path)
	# The catalogue's own spread rather than a number typed here: Hoopsii spreads 5 m, and what stands
	# in the yard is that 5 m across however wide the model itself was built.
	var spruce: PlantSpecies = catalogue.get_species(&"picea-pungens-hoopsii")
	assert(
		is_equal_approx(node.scale.x, spruce.spread_m() / 2.6),
		"scaled by the catalogue's spread over the model's own footprint: %.3f" % node.scale.x
	)
	assert(node.position.is_equal_approx(Vector3(2.0, 0.0, -3.0)), "standing where it was asked to stand")
	assert(PlanStyleScript.symbol_of(node) == SymbolsScript.CONIFER, "and the plan draws it as a conifer")
	assert(
		is_equal_approx(PlanStyleScript.footprint_size(node).x, spruce.spread_m()),
		"at its own %.2f m across, not the model's: %.2f" % [
			spruce.spread_m(), PlanStyleScript.footprint_size(node).x
		]
	)
	yard.free()