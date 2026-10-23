extends Node2D
## A live pass over what to grow here next: the page opened on a real running program, a bed's history
## stated, a crop chosen, and what the ground would carry read off the real controls.
##
## This is a development tool, not part of the game. A page that answers "what should follow what" is
## three things stacked - the bed, the family that grew there last, and the crop - and reading the
## script that writes it cannot show whether the words come out right together, or whether the list is
## the list the catalogue would give.
##
## So it instances the **real main scene**, states a ground through the **real drawing**, opens the
## window through the **real HUD** the way the menu entry does, and reads the lines off the **real
## controls**, awaiting real frames so what it prints is what a running editor would be showing.
##
## Run `res://scenes/rotation_demo.tscn`.

const MAIN := preload("res://scenes/main.tscn")
const ProfileScript := preload("res://scripts/terrain_profile.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")
const CropRotationScript := preload("res://scripts/crop_rotation.gd")


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	await _settle()
	var hud: Node = main.get_node_or_null(^"Hud")
	if hud == null:
		print("no HUD in the main scene")
		return

	print("--- the Plant menu ---")
	print("what to grow here next is offered as: ", _entry_wording(hud))

	print("--- stating a ground, the way the ground window does ---")
	var map: ZoneMap = hud._ground_map()
	map.base = ProfileScript.of("sun", SpeciesScript.FULL_SUN)
	map.add_zone(
		"the kitchen bed",
		PackedVector2Array([
			Vector2(0.0, 0.0), Vector2(4.0, 0.0), Vector2(4.0, 4.0), Vector2(0.0, 4.0)
		]),
		ProfileScript.of("sun", SpeciesScript.FULL_SUN)
	)
	print("the ground now reads: ", map.describe())

	print("--- opening it, the way the menu entry does ---")
	hud.open_rotation_window()
	await _settle()
	var page: RotationWindow = hud.get(&"_rotation_window")
	print("the window is up: ", hud.is_rotation_window_open())
	print("it is titled: \"", page.title, "\"")
	print("the beds it was handed: ", page.place_count())
	print("the crops in the list: ", page.row_count())
	print("the bed in hand: \"", page.place_line(), "\"")
	print("the crop in hand: \"", page.crop_line(), "\"")
	print("what it grows beside: \"", page.company_line(), "\"")
	print("the verdict: \"", page.turn_line(), "\"")
	print("what the bed would carry: \"", page.summary_text(), "\"")
	print("the rows read as:")
	for line: String in page.row_texts():
		print("    ", line)

	print("--- saying an allium grew in this bed last, then putting chives back in it ---")
	if not page.choose_previous_family(CropRotationScript.ALLIUM):
		print("(the bed did not take a history)")
	page.choose_crop(&"allium-schoenoprasum")
	await _settle()
	print("the bed in hand: \"", page.place_line(), "\"")
	print("the crop in hand: \"", page.crop_line(), "\"")
	print("the verdict: \"", page.turn_line(), "\"")
	print("the hint: \"", page.hint(), "\"")
	print("the status line: \"", page.said(), "\"")

	print("--- a dill where the chives were: a different family, so it follows on ---")
	page.choose_crop(&"anethum-graveolens")
	await _settle()
	print("the crop in hand: \"", page.crop_line(), "\"")
	print("the verdict: \"", page.turn_line(), "\"")
	print("what it grows beside: \"", page.company_line(), "\"")

	print("--- closing it takes it off the screen ---")
	hud.close_rotation_window()
	await _settle()
	print("the window is up: ", hud.is_rotation_window_open())

	print("--- opened once more, so the captured frame is the page itself ---")
	hud.open_rotation_window()
	await _settle()
	print("the window is up: ", hud.is_rotation_window_open(), ", ", page.place_count(), " beds, ",
		page.row_count(), " crops")


## Let the running scene take a couple of frames, which is where the HUD settles.
func _settle() -> void:
	for _frame in 3:
		await get_tree().process_frame


## The wording the Plant menu gives the rotation entry, read off the menu plan the same way the bar is
## built from it.
static func _entry_wording(hud: Node) -> String:
	for entry: Dictionary in hud.plant_items():
		if String(entry.get("id", "")) == "plant.rotation":
			return "\"%s\" (needs %s)" % [
				String(entry.get("label", "")), String(entry.get("needs", ""))
			]
	return "(no rotation entry in the Plant menu)"