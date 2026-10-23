extends Node2D
## A live pass over how much to plant: the page opened on a real running program, a household at a time,
## and what it says read off the real controls.
##
## This is a development tool, not part of the game. A page that answers "how many plants feed these
## people" is one arithmetic over the plant list, and reading the script that writes it cannot show
## whether the words come out right together, or whether the shipped catalogue really carries the two
## facts the sum needs.
##
## So it instances the **real main scene**, opens the window through the **real HUD** the way the menu
## entry does, changes the household, and reads the lines off the **real controls**, awaiting real frames
## so what it prints is what a running editor would be showing. It needs no drawing: how much a plant
## gives is a fact about the plant, and how many people are eating is a fact about a household.
##
## Run `res://scenes/yield_demo.tscn`.

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
	print("how much to plant is offered as: ", _entry_wording(hud))

	print("--- opening it, the way the menu entry does ---")
	hud.open_yield_window()
	await _settle()
	var page: YieldWindow = hud.get(&"_yield_window")
	print("the window is up: ", hud.is_yield_window_open())
	print("it is titled: \"", page.title, "\"")
	print("feeding: ", page.people(), ", with a spare of ", page.spare(), "%")
	print("the whole plan: \"", page.feed_line(), "\"")
	print("how much of the list it could tell: \"", page.summary_text(), "\"")
	print("the hint: \"", page.hint(), "\"")
	print("every crop it works out:")
	for line: String in page.row_texts():
		print("    ", line)

	print("--- a bigger household, and a bigger spare ---")
	page.set_people(6)
	await _settle()
	print("  ", page.people(), " people: \"", page.feed_line(), "\"")
	page.set_spare(25)
	await _settle()
	print("  and 25% spare: \"", page.feed_line(), "\"")

	print("--- closing it takes it off the screen ---")
	hud.close_yield_window()
	await _settle()
	print("the window is up: ", hud.is_yield_window_open())

	print("--- opened once more, so the captured frame is the page itself ---")
	page.bind(hud.plant_list())
	hud.open_yield_window()
	await _settle()
	print("the window is up: ", hud.is_yield_window_open(), ", ", page.row_count(), " crops, ",
		page.feed_line())

	print("--- handing the count over to a nursery order ---")
	var order_button: Button = page.get_node_or_null(^"Column/Buttons/OrderButton")
	print("the page offers a button: \"", page.order_words(), "\" (live: ", page.order_enabled(), ")")
	if order_button != null:
		order_button.pressed.emit()
	await _settle()
	print("the nursery order is up: ", hud.is_plant_order_window_open())
	var order: PlantOrderWindow = hud.get(&"_plant_order_window")
	if order != null:
		print("it is showing: \"", order.summary_text(), "\"")
		print("its line before the button: \"", order.order_hint(), "\"")
		for line: String in order.line_texts():
			print("    ", line)


## Let the running scene take a couple of frames, which is where the HUD settles.
func _settle() -> void:
	for _frame in 3:
		await get_tree().process_frame


## The wording the Plant menu gives the yield entry, read off the menu plan the same way the bar is built
## from it.
static func _entry_wording(hud: Node) -> String:
	for entry: Dictionary in hud.plant_items():
		if String(entry.get("id", "")) == "plant.yield":
			return "\"%s\" (needs %s)" % [
				String(entry.get("label", "")), String(entry.get("needs", ""))
			]
	return "(no yield entry in the Plant menu)"