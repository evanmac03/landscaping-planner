extends Node2D
## A live pass over when to sow: a day to sow, a crop to sow, and the succession that keeps it coming,
## on a real running program.
##
## This is a development tool, not part of the game. A page that answers "when will this ripen" is one
## reading of three facts that are easy to get wrong together - a pair of frost dates the drawing holds,
## a catalogue of crops that may or may not record a time to maturity, and the planting day a person
## chooses - and reading the script that writes the arithmetic cannot show whether the words come out
## right or whether the shipped list really answers the way the sums say it should.
##
## So it instances the **real main scene**, states a season through the **real season page**, opens the
## sowing window through the **real HUD** the way the menu entry does, and reads the lines off the
## **real controls**, awaiting real frames so what it prints is what a running editor would be showing.
##
## Run `res://scenes/sowing_demo.tscn`.

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
	print("the sowing page is offered as: ", _entry_wording(hud))

	print("--- stating a season the real way, through the season page ---")
	hud.open_season_window()
	await _settle()
	var season: SeasonWindow = hud.get(&"_season_window")
	season.set_fields(140, 280)
	print("stating a temperate season: ", season.state_season())
	season.request_close()
	await _settle()

	print("--- opening the sowing page, the way the menu entry does ---")
	hud.open_sowing_window()
	await _settle()
	var page: SowingWindow = hud.get(&"_sowing_window")
	print("the window is up: ", hud.is_sowing_window_open())
	print("it is titled: \"", page.title, "\"")
	print("the season it sows into: \"", page.season_line(), "\"")
	print("the day in hand is the last frost: ", page.sow())
	print("the crops it offers: ", page.crop_ids().size())

	print("--- a crop that fits the season ---")
	var chosen: StringName = _first_crop_with_a_maturity(page)
	print("choosing: ", chosen)
	page.choose_crop(chosen)
	print("the crop: \"", page.crop_line(), "\"")
	print("the verdict: \"", page.verdict_line(), "\"")
	print("the sowing window: \"", page.window_line(), "\"")
	print("the succession: \"", page.succession_line(), "\"")

	print("--- the whole food list, sown on the last frost ---")
	for line: String in page.row_texts():
		print("    ", line)
	print("the summary: \"", page.summary_text(), "\"")

	print("--- sowing late: two months on ---")
	page.set_sow(220)
	print("the sow date is now: ", page.sow())
	print("the verdict: \"", page.verdict_line(), "\"")
	print("the succession: \"", page.succession_line(), "\"")
	print("the summary: \"", page.summary_text(), "\"")

	print("--- back to the last frost, so the captured frame is the page ---")
	page.set_sow(140)
	page.choose_crop(chosen)
	await _settle()
	print("the window is up: ", hud.is_sowing_window_open(), ", ", page.row_count(), " crops checked")


## The first crop in the picker the catalogue gives a time to maturity, so the demo shows a real answer
## rather than an unknown.
func _first_crop_with_a_maturity(page: SowingWindow) -> StringName:
	for crop_id: StringName in page.crop_ids():
		var crop: PlantSpecies = page.catalogue.get_species(crop_id)
		if crop != null and crop.maturity_days > 0:
			return crop_id
	return page.selected_crop_id()


## Let the running scene take a couple of frames, which is where the HUD settles.
func _settle() -> void:
	for _frame in 3:
		await get_tree().process_frame


## The wording the Plant menu gives the sowing entry, read off the menu plan the same way the bar is
## built from it.
static func _entry_wording(hud: Node) -> String:
	for entry: Dictionary in hud.plant_items():
		if String(entry.get("id", "")) == "plant.sow":
			return "\"%s\" (needs %s)" % [
				String(entry.get("label", "")), String(entry.get("needs", ""))
			]
	return "(no sowing entry in the Plant menu)"