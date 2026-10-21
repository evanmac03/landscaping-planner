extends Node2D
## A live pass over watering an area: a bed on the drawing, the supply stated, the page that lays a
## zone out, and the heads it leaves on the plan.
##
## This is a development tool, not part of the game. It instances the **real main scene** and drives the
## **real page** through the methods its controls call, so the module, the HUD, the controller and the
## plan canvas are all the shipped ones, and it prints every step. The screenshot at the end is the page
## over a drawing it has just watered.
##
## Run `res://scenes/irrigation_demo.tscn`.

const MAIN := preload("res://scenes/main.tscn")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const IrrigationScript := preload("res://scripts/draft/irrigation.gd")

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
	hud.open_water_panel()
	print("the page is up: ", hud.is_water_panel_open())
	print("the page opens saying: ", hud._water_panel.status_text())
	print("and its budget line reads: ", hud._water_panel.budget_text())

	print("--- the areas the drawing encloses ---")
	for row: Dictionary in controller.waterable_areas():
		print("  ", row["name"], "  ", snappedf(float(row["area_m2"]), 0.01), " m2  key ", row["key"])

	print("--- stating the supply, as the button does ---")
	print("before: ", IrrigationScript.supply_words(controller.irrigation_supply()))
	hud._on_water_supply(250.0, 350.0)
	print("after:  ", IrrigationScript.supply_words(controller.irrigation_supply()))
	print("the page says: ", hud.water_status_text())

	print("--- watering the bed, as the button does ---")
	var row: Dictionary = controller.waterable_areas()[0]
	hud._on_water_area(String(row["key"]), IrrigationScript.SPRAY,
		IrrigationScript.throw_of_kind(IrrigationScript.SPRAY), false)
	print("the page says: ", hud.water_status_text())
	print("the drawing holds ", controller.document.count(), " shapes")
	var heads := 0
	var radius := 0.0
	for entity in controller.document.entities():
		if not IrrigationScript.is_head_entity(entity):
			continue
		heads += 1
		radius = float(entity.params[2])
		print("  ", entity.layer, "  head for Zone ", IrrigationScript.zone_of_entity(entity),
			"  kind ", entity.meta[IrrigationScript.META_KIND],
			"  nozzle ", entity.meta[IrrigationScript.META_ARC], " deg")
	print(heads, " heads on the plan, each drawn at ", snappedf(radius, 0.001),
		" m of ground (3 mm on paper at 1:100)")
	print("the zone list on the page holds ", hud._water_panel._zone_list.item_count, " row(s):")
	for index in hud._water_panel._zone_list.item_count:
		print("  ", hud._water_panel._zone_list.get_item_text(index))

	print("--- what the Water menu now says ---")
	print("  ", hud._water_text())

	print("--- what is left on screen ---")
	print("the page is up: ", hud.is_water_panel_open(),
		", the drawing holds ", controller.document.count(), " shapes")


## An eighteen metre square: four spray throws each way, so a zone comes out five grid lines each way -
## the textbook twenty-five heads - and the whole zone draws 225 litres a minute.
func _bed_ring() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(BED, 0.0), Vector2(BED, BED), Vector2(0.0, BED),
	])