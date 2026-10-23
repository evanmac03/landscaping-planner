extends Node2D
## A live pass over the food garden: the page opened on a real running program, a bed chosen, a crop
## chosen, and what the ground would carry read off the real controls.
##
## This is a development tool, not part of the game. A page that answers "will this crop crop here" is
## four things stacked - the bed, the crop, the site's day length and the list - and reading the script
## that writes it cannot show whether the words come out right together, or whether the list is the list
## the catalogue would give.
##
## So it instances the **real main scene**, states a ground through the **real drawing**, opens the window
## through the **real HUD** the way the menu entry does, and reads the lines off the **real controls**,
## awaiting real frames so what it prints is what a running editor would be showing.
##
## Run `res://scenes/food_demo.tscn`.

const MAIN := preload("res://scenes/main.tscn")
const ProfileScript := preload("res://scripts/terrain_profile.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	await _settle()
	var hud: Node = main.get_node_or_null(^"Hud")
	if hud == null:
		print("no HUD in the main scene")
		return

	print("--- the Plant menu ---")
	print("the food garden is offered as: ", _entry_wording(hud))

	print("--- stating a ground, the way the ground window does ---")
	var map: ZoneMap = hud._ground_map()
	map.base = ProfileScript.of("sun", SpeciesScript.FULL_SUN)
	map.add_zone(
		"the north bed",
		PackedVector2Array([
			Vector2(0.0, 0.0), Vector2(4.0, 0.0), Vector2(4.0, 4.0), Vector2(0.0, 4.0)
		]),
		ProfileScript.of("sun", SpeciesScript.FULL_SHADE)
	)
	print("the ground now reads: ", map.describe())

	print("--- opening it, the way the menu entry does ---")
	hud.open_food_window()
	await _settle()
	var page: FoodWindow = hud.get(&"_food_window")
	print("the window is up: ", hud.is_food_window_open())
	print("it is titled: \"", page.title, "\"")
	print("the beds it was handed: ", page.place_count())
	print("the crops in the list: ", page.row_count())
	print("the site's own ceiling: \"", page.season_line(), "\"")
	print("the bed in hand: \"", page.place_line(), "\"")
	print("the crop in hand: \"", page.crop_line(), "\"")
	print("the verdict: \"", page.verdict_line(), "\"")
	print("what the bed would carry: \"", page.summary_text(), "\"")
	print("the rows read as:")
	for line: String in page.row_texts():
		print("    ", line)

	print("--- the same crop in a bed the plan says is shaded ---")
	page.choose_place(1)
	await _settle()
	print("the bed in hand: \"", page.place_line(), "\"")
	print("the verdict: \"", page.verdict_line(), "\"")
	print("the status line: \"", page.said(), "\"")

	print("--- back to the sunny bed, where the list reads best ---")
	page.choose_place(0)
	page.choose_crop(&"thymus-vulgaris")
	await _settle()
	print("the crop in hand: \"", page.crop_line(), "\"")
	print("the verdict: \"", page.verdict_line(), "\"")

	print("--- closing it takes it off the screen ---")
	hud.close_food_window()
	await _settle()
	print("the window is up: ", hud.is_food_window_open())

	print("--- opened once more, so the captured frame is the page itself ---")
	hud.open_food_window()
	await _settle()
	print("the window is up: ", hud.is_food_window_open(), ", ", page.place_count(), " beds, ",
		page.row_count(), " crops")


## Let the running scene take a couple of frames, which is where the HUD settles.
func _settle() -> void:
	for _frame in 3:
		await get_tree().process_frame


## The wording the Plant menu gives the food entry, read off the menu plan the same way the bar is
## built from it.
static func _entry_wording(hud: Node) -> String:
	for entry: Dictionary in hud.plant_items():
		if String(entry.get("id", "")) == "plant.food":
			return "\"%s\" (needs %s)" % [String(entry.get("label", "")), String(entry.get("needs", ""))]
	return "(no food entry in the Plant menu)"