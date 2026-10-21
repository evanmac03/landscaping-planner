extends Node
## A dev tool: plant one species of every category in the *real* game scene, and report the model each
## one actually got.
##
## The asset tools check the files on disk and the test suite checks the catalogue's mapping, and
## neither of them drives the scene: a list can point every species at the right file and the game can
## still put something else on the ground, because the planted object is whatever the *scene's own*
## controller instanced. So this does what a designer does - it arms a species through the `Hud` and
## plants it through the `ViewController` - and then reads the node that landed.
##
## It is a check and not a printout: each row is compared against the species' own `model_scene`, the
## `PlanStyle` footprint its scale is worked out from, the symbol the plan will draw, and the group the
## view controller reads. One bad row is one wrong plant in every garden.
##
## Run it with `run_scene` and read the console:
##     res://tools/plant_scene_check.tscn

const MAIN := preload("res://scenes/main.tscn")
const PlanStyleScript := preload("res://scripts/plan_style.gd")
const PlantSymbolsScript := preload("res://scripts/plant_symbols.gd")
const YardScript := preload("res://scripts/yard.gd")

## One species for each of these, taken from the list rather than named, so this keeps working when
## the list changes. The order is `PlantSpecies.category`.
const CATEGORY_WORDS: Array[String] = [
	"tree", "shrub", "perennial", "annual", "grass",
	"groundcover", "vine", "fern", "bulb", "herb",
]

## Where the plants go, in screen pixels: one row across the plan, so the photograph a run leaves
## behind shows every one of them side by side.
const FIRST_X := 120.0
const STEP_X := 140.0
const PLAN_Y := 430.0

## How far a scale may sit from `spread / declared footprint` before it is called wrong. The arithmetic
## is the same two numbers, so this only absorbs float32.
const SCALE_SLACK := 0.001


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	# The Hud lays itself out and reads the yard on the first few frames; planting before that would
	# be measuring a scene that has not finished coming up.
	for i: int in 5:
		await get_tree().process_frame

	var hud: Node = main.get_node_or_null(^"Hud")
	var controller: Node = main.get_node_or_null(^"ViewController")
	if hud == null or controller == null:
		print("PLANT SCENE: no Hud (%s) or ViewController (%s) - is this the real main scene?" % [hud, controller])
		return
	var catalogue: PlantCatalogue = hud.plant_list()
	if catalogue == null:
		print("PLANT SCENE: the scene has no plant list")
		return

	print("=== WHAT THE SCENE PLANTS (%d species from %s, view mode %d) ===" % [
		catalogue.count(), catalogue.source, int(controller.mode),
	])
	print("standing before: %d" % controller.planted_count())

	var picked: Dictionary = {}
	for species: PlantSpecies in catalogue.all():
		if not picked.has(species.category):
			picked[species.category] = species

	var planted: int = 0
	var wrong: int = 0
	for index: int in range(CATEGORY_WORDS.size()):
		var outcome: Dictionary = _plant_one(hud, controller, picked, index, planted)
		planted += 1 if bool(outcome["planted"]) else 0
		wrong += int(outcome["wrong"])

	print("standing after: %d" % controller.planted_count())
	var total: int = picked.size()
	if wrong == 0 and planted == total and total == CATEGORY_WORDS.size():
		print("PLANT SCENE: every category planted a model of its own shape, at its own size")
	else:
		print("PLANT SCENE: %d of %d categories planted, %d wrong" % [planted, total, wrong])


## Arm one species and plant it where the next click would go, then hold the node that landed up
## against the four things the rest of the program will read off it.
func _plant_one(
	hud: Node, controller: Node, picked: Dictionary, index: int, slot: int
) -> Dictionary:
	var words: String = CATEGORY_WORDS[index]
	if not picked.has(index):
		print("  %-11s the list has none" % words)
		return {"planted": false, "wrong": 0}

	var species: PlantSpecies = picked[index]
	if not hud._arm_planting(species.id):
		print("  %-11s %s would not arm" % [words, species.id])
		return {"planted": false, "wrong": 1}

	var result: Dictionary = controller.plant_at(Vector2(FIRST_X + STEP_X * float(slot), PLAN_Y))
	# Put it away between species, so the next arm is the only plant in hand.
	controller.stop_planting()
	if not bool(result["ok"]):
		print("  %-11s %-30s REFUSED: %s" % [words, species.id, String(result["reason"])])
		return {"planted": false, "wrong": 1}

	var node: Node3D = result["node"]
	var path: String = node.scene_file_path
	var wanted: String = species.model_scene if not species.model_scene.is_empty() else species.form
	var spec: Dictionary = PlanStyleScript.spec_for(path)
	var base: float = float((spec["size"] as Vector2).x)
	var wanted_scale: float = species.spread_m() / base
	var symbol: StringName = PlanStyleScript.symbol_of(node)
	var size: Vector2 = PlanStyleScript.footprint_size(node)

	var faults: Array[String] = []
	if path != wanted:
		faults.append("planted %s, not its model %s" % [path, wanted])
	if absf(node.scale.x - wanted_scale) > SCALE_SLACK:
		faults.append("scale %.4f, wanted %.4f" % [node.scale.x, wanted_scale])
	if not PlantSymbolsScript.is_symbol(symbol):
		faults.append("drawn as %s, which is not a symbol" % symbol)
	if not node.is_in_group(YardScript.PLACEABLE_GROUP):
		faults.append("not in the group the views read")

	print("  %-11s %-30s %-48s scale %6.3f = %5.2f/%-5.2f  %-11s %5.2f x %-5.2f  %s" % [
		words, species.id, path, node.scale.x, species.spread_m(), base, symbol,
		size.x, size.y,
		"OK" if faults.is_empty() else "WRONG: " + "; ".join(faults),
	])
	return {"planted": true, "wrong": faults.size()}