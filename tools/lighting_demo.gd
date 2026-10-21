extends Node2D
## A live pass over lighting an area: a bed on the drawing, the transformer stated, the page that lays
## a circuit out, and the fixtures it leaves on the plan.
##
## This is a development tool, not part of the game. It instances the **real main scene** and drives the
## **real page** through the methods its controls call, so the module, the HUD, the controller and the
## plan canvas are all the shipped ones, and it prints every step. The screenshot at the end is the page
## over a drawing it has just lit.
##
## Run `res://scenes/lighting_demo.tscn`.

const MAIN := preload("res://scenes/main.tscn")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const LightingScript := preload("res://scripts/draft/lighting.gd")

const BED := 18.0


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	var hud: Node = main.get_node_or_null(^"Hud")
	var controller: Node = main.get_node_or_null(^"DraftController")
	if hud == null or controller == null:
		print("no HUD or no drafting controller in the main scene")
		return

	print("--- a bed on the drawing, and the page opened over it ---")
	controller.document.add(Entity.make_polyline(_bed_ring(), true), LayerSet.NEW_BED)
	hud.open_light_panel()
	print("the page is up: ", hud.is_light_panel_open())
	print("the page opens saying: ", hud._light_panel.status_text())
	print("and its budget line reads: ", hud._light_panel.budget_text())

	print("--- the areas the drawing encloses ---")
	for row: Dictionary in controller.lightable_areas():
		print("  ", row["name"], "  ", row["area_text"], "  key ", row["key"])

	print("--- stating the transformer, as the button does ---")
	print("before: ", LightingScript.transformer_words(controller.lighting_transformer()))
	hud._on_light_transformer(300.0, 12.0)
	print("after:  ", LightingScript.transformer_words(controller.lighting_transformer()))
	print("the page says: ", hud.light_status_text())

	print("--- lighting the bed, as the button does ---")
	var row: Dictionary = controller.lightable_areas()[0]
	hud._on_light_area(String(row["key"]), LightingScript.WELL,
		LightingScript.throw_of_kind(LightingScript.WELL), false)
	print("the page says: ", hud.light_status_text())
	print("the drawing holds ", controller.document.count(), " shapes")
	var fixtures := 0
	var radius := 0.0
	for entity in controller.document.entities():
		if not LightingScript.is_fixture_entity(entity):
			continue
		fixtures += 1
		radius = float(entity.params[2])
		print("  ", entity.layer, "  fixture for Circuit ", LightingScript.circuit_of_entity(entity),
			"  kind ", entity.meta[LightingScript.META_KIND],
			"  beam ", entity.meta[LightingScript.META_SPREAD], " deg")
	print(fixtures, " fixtures on the plan, each drawn at ", snappedf(radius, 0.001),
		" m of ground (3 mm on paper at 1:100)")
	print("the circuit list on the page holds ", hud._light_panel._circuit_list.item_count, " row(s):")
	for index in hud._light_panel._circuit_list.item_count:
		print("  ", hud._light_panel._circuit_list.get_item_text(index))

	print("--- what the Light menu now says ---")
	print("  ", hud._light_text())

	print("--- what is left on screen ---")
	print("the page is up: ", hud.is_light_panel_open(),
		", the drawing holds ", controller.document.count(), " shapes")


## An eighteen metre square: six well-light throws each way, so a circuit comes out seven grid lines
## each way - forty-nine fixtures - and the whole circuit draws 245 watts of the 300 volt-amperes the
## drawing is lit by.
func _bed_ring() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(BED, 0.0), Vector2(BED, BED), Vector2(0.0, BED),
	])