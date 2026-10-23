extends Node2D
## A live pass over how long the season is: the site's frost dates, and the food list measured against
## them, on a real running program.
##
## This is a development tool, not part of the game. A page that answers "what will finish in the
## season" is one reading of two facts that are easy to get wrong together - a pair of dates the
## drawing holds, and a catalogue of crops that may or may not record a time to maturity - and reading
## the script that writes it cannot show whether the words come out right or whether the shipped list
## really answers the way the arithmetic says it should.
##
## So it instances the **real main scene**, opens the window through the **real HUD** the way the menu
## entry does, states a season through the page's own button, and reads the lines off the **real
## controls**, awaiting real frames so what it prints is what a running editor would be showing.
##
## Run `res://scenes/season_demo.tscn`.

const MAIN := preload("res://scenes/main.tscn")


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	await _settle()
	var hud: Node = main.get_node_or_null(^"Hud")
	if hud == null:
		print("no HUD in the main scene")
		return

	print("--- the Site menu ---")
	print("the growing season is offered as: ", _entry_wording(hud))

	print("--- opening it, the way the menu entry does ---")
	hud.open_season_window()
	await _settle()
	var page: SeasonWindow = hud.get(&"_season_window")
	print("the window is up: ", hud.is_season_window_open())
	print("it is titled: \"", page.title, "\"")
	print("the drawing states: \"", page.season_line(), "\"")

	print("--- stating a temperate season: 20 May to 7 October ---")
	page.set_fields(140, 280)
	print("the button is live: ", page.state_enabled())
	print("stating it: ", page.state_season())
	await _settle()
	print("the Site menu now says: \"", hud._season_text(), "\"")
	print("the season line: \"", page.season_line(), "\"")
	print("the hint: \"", page.hint(), "\"")
	print("the crops, measured against the season:")
	for line: String in page.row_texts():
		print("    ", line)
	print("the summary: \"", page.summary_text(), "\"")

	print("--- a short season: 15 June to 7 September ---")
	page.set_fields(166, 250)
	print("stating it: ", page.state_season())
	await _settle()
	print("the season line: \"", page.season_line(), "\"")
	print("the summary: \"", page.summary_text(), "\"")
	for line: String in page.row_texts():
		print("    ", line)

	print("--- taking it back ---")
	print("taking it back: ", page.clear_season())
	await _settle()
	print("the drawing now says: \"", page.season_line(), "\"")
	print("and the hint: \"", page.hint(), "\"")

	print("--- leaving a temperate season stated, so the captured frame is the page ---")
	page.set_fields(140, 280)
	page.state_season()
	await _settle()
	print("the window is up: ", hud.is_season_window_open(), ", ", page.row_count(), " crops checked")


## Let the running scene take a couple of frames, which is where the HUD settles.
func _settle() -> void:
	for _frame in 3:
		await get_tree().process_frame


## The wording the Site menu gives the season entry, read off the menu plan the same way the bar is
## built from it.
static func _entry_wording(hud: Node) -> String:
	for entry: Dictionary in hud.site_items():
		if String(entry.get("id", "")) == "site.season.window":
			return "\"%s\" (needs %s)" % [
				String(entry.get("label", "")), String(entry.get("needs", ""))
			]
	return "(no season entry in the Site menu)"