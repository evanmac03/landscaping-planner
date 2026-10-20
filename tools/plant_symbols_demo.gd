extends Node2D
## A sheet of the plant symbols, one of each, drawn by the real plan.
##
## This is a development tool, not part of the game. It instances the *actual* `PlanCanvas` and plants
## into a *real* yard through `PlantPlacement`, so what it shows is what a designer would see: the
## same figures, the same footprint, the same `PlanStyle` inks. Reading the script tells you the
## symbols differ; only looking at it tells you whether they *read* as a spruce, a grass and a bed.
##
## Run `res://scenes/plant_symbols_demo.tscn`. It prints the symbol each plant was given, which is the
## half a picture cannot state.

const CatalogueScript := preload("res://scripts/plant_catalogue.gd")
const PlaceScript := preload("res://scripts/plant_placement.gd")
const PlanCanvasScript := preload("res://scripts/plan_canvas.gd")
const PlanStyleScript := preload("res://scripts/plan_style.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")
const SymbolsScript := preload("res://scripts/plant_symbols.gd")

const SEED := "res://data/plants/nursery_list.json"
const VIEWPORT := Vector2(1600.0, 900.0)
const SPACING := 2.6


func _ready() -> void:
	var read: Dictionary = CatalogueScript.load_from(SEED)
	if not bool(read["ok"]):
		print("no plant list to draw: %s" % String(read["reason"]))
		return
	var catalogue: PlantCatalogue = read["catalogue"]
	var picked: Array[PlantSpecies] = _picked(catalogue)
	print("--- what each plant is drawn as ---")
	var yard := Node3D.new()
	yard.name = "Yard"
	add_child(yard)
	for index in picked.size():
		var species: PlantSpecies = picked[index]
		var row: float = float(index) - float(picked.size() - 1) * 0.5
		var planted: Dictionary = PlaceScript.place(
			catalogue, species.id, yard, Vector3(row * SPACING, 0.0, 0.0)
		)
		if not bool(planted["ok"]):
			print("%s was refused: %s" % [species.id, String(planted["reason"])])
			continue
		var node: Node3D = planted["node"]
		var symbol: StringName = PlanStyleScript.symbol_of(node)
		var size: Vector2 = PlanStyleScript.footprint_size(node)
		print("%-12s %-14s %-5.2f x %-5.2f  %s" % [
			String(symbol), species.category_name(), size.x, size.y, species.display_name()
		])
	var canvas: PlanCanvas = PlanCanvasScript.new()
	canvas.name = "Plan"
	add_child(canvas)
	canvas.rebind(yard)
	canvas.apply_view(Vector2.ZERO, 14.0, VIEWPORT)


## One plant for every symbol a species can be: a conifer and a broadleaf tree, a conifer and a
## broadleaf shrub, a grass, a groundcover, a vine, a fern and the planted bed the perennials use. The
## catalogue is asked for them rather than naming them, so this keeps working when the list changes.
func _picked(catalogue: PlantCatalogue) -> Array[PlantSpecies]:
	var out: Array[PlantSpecies] = []
	_take(out, catalogue, SpeciesScript.TREE, true)
	_take(out, catalogue, SpeciesScript.TREE, false)
	_take(out, catalogue, SpeciesScript.SHRUB, true)
	_take(out, catalogue, SpeciesScript.SHRUB, false)
	_take(out, catalogue, SpeciesScript.GRASS, false)
	_take(out, catalogue, SpeciesScript.GROUNDCOVER, false)
	_take(out, catalogue, SpeciesScript.VINE, false)
	_take(out, catalogue, SpeciesScript.FERN, false)
	_take(out, catalogue, SpeciesScript.PERENNIAL, false)
	return out


func _take(
	into: Array[PlantSpecies], catalogue: PlantCatalogue, category: int, conifer: bool
) -> void:
	for species: PlantSpecies in catalogue.all():
		if species.category != category:
			continue
		if category == SpeciesScript.TREE or category == SpeciesScript.SHRUB:
			if species.is_conifer() != conifer:
				continue
		into.append(species)
		return
	print("the list has no %s plant for %s" % [
		String(SpeciesScript.CATEGORY_NAMES.get(category, "?")), "a conifer" if conifer else "not a conifer"
	])