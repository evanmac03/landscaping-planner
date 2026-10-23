extends Node2D
## A live pass over what is ready when: the calendar page opened on a real running program, a month at a
## time, and what it says read off the real controls.
##
## This is a development tool, not part of the game. A page that answers "what is ready when" is one
## reading of the plant list, and reading the script that writes it cannot show whether the words come
## out right together, or whether the shipped catalogue really fills the year the way the arithmetic
## says it should.
##
## So it instances the **real main scene**, opens the window through the **real HUD** the way the menu
## entry does, walks a few months, and reads the lines off the **real controls**, awaiting real frames
## so what it prints is what a running editor would be showing. It needs no drawing: a harvest time is a
## fact about the crop, not about the ground.
##
## Run `res://scenes/harvest_demo.tscn`.

const MAIN := preload("res://scenes/main.tscn")


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	await _settle()
	var hud: Node = main.get_node_or_null(^"Hud")
	if hud == null:
		print("no HUD in the main scene")
		return

	print("--- the Plant menu ---")
	print("what is ready when is offered as: ", _entry_wording(hud))

	print("--- opening it, the way the menu entry does ---")
	hud.open_harvest_window()
	await _settle()
	var page: HarvestWindow = hud.get(&"_harvest_window")
	print("the window is up: ", hud.is_harvest_window_open())
	print("it is titled: \"", page.title, "\"")
	print("it opened on: ", page.month_name(), " (the fullest month)")
	print("the month line: \"", page.month_line(), "\"")
	print("the shape of the year: \"", page.year_line(), "\"")
	print("what the list says nothing about: \"", page.unstated_line(), "\"")
	print("the hint: \"", page.hint(), "\"")
	print("what is ready in ", page.month_name(), ":")
	for line: String in page.row_texts():
		print("    ", line)

	print("--- walking a few months ---")
	for which: int in [1, 4, 6, 9, 11]:
		page.choose_month(which)
		await _settle()
		print("  ", page.month_name(), " (", page.row_count(), "): \"", page.month_line(), "\"")

	print("--- closing it takes it off the screen ---")
	hud.close_harvest_window()
	await _settle()
	print("the window is up: ", hud.is_harvest_window_open())

	print("--- opened once more, so the captured frame is the page itself ---")
	hud.open_harvest_window()
	await _settle()
	print("the window is up: ", hud.is_harvest_window_open(), ", ", page.row_count(), " crops ready in ",
		page.month_name())


## Let the running scene take a couple of frames, which is where the HUD settles.
func _settle() -> void:
	for _frame in 3:
		await get_tree().process_frame


## The wording the Plant menu gives the harvest entry, read off the menu plan the same way the bar is
## built from it.
static func _entry_wording(hud: Node) -> String:
	for entry: Dictionary in hud.plant_items():
		if String(entry.get("id", "")) == "plant.harvest":
			return "\"%s\" (needs %s)" % [
				String(entry.get("label", "")), String(entry.get("needs", ""))
			]
	return "(no harvest entry in the Plant menu)"