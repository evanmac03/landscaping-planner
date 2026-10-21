extends Node2D
## A live pass over the manual: the Help menu opened on a real running program, the contents listed, a
## subject read, and the search used to find one.
##
## This is a development tool, not part of the game, and it exists because a page of prose cannot be
## settled by reading the script that writes it. Three things only a running window can show:
## the page really opens when the menu entry is taken; the key reference is the HUD's own (so it cannot
## drift from the key panel - it is generated from the same tables the panel is); and the search really
## narrows the contents and shows the topic it found rather than the one that was there before.
##
## So it instances the **real main scene**, opens the window through the **real HUD** the way a menu
## click does, and reads the titles and bodies off the **real controls**, awaiting real frames so what it
## prints is what a running editor would be showing.
##
## Run `res://scenes/help_demo.tscn`.

const MAIN := preload("res://scenes/main.tscn")


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	await _settle()
	var hud: Node = main.get_node_or_null(^"Hud")
	if hud == null:
		print("no HUD in the main scene")
		return
	var window: HelpWindow = hud.get(&"_help_window")

	print("--- the Help menu ---")
	print("the manual is offered as: ", _entry_wording(hud))
	print("the window is up before anything is opened: ", hud.is_help_window_open())

	print("--- opening it, the way the menu entry does ---")
	hud.open_help_window()
	await _settle()
	print("the window is up: ", hud.is_help_window_open())
	print("it is titled: \"", window.title, "\"")
	print("the page has ", window.topic_count(), " topics, and the list is showing ", window.shown_count())
	print("the contents read as:")
	for line in window.list_texts():
		print("    ", line)
	print("the opened topic: \"", window.shown_title(), "\"")
	print("the first line of it: \"", window.shown_body().split("\n")[0], "\"")
	print("the status line: \"", window.said(), "\"")

	print("--- the key reference is the HUD's own, not a second copy ---")
	var keys_at := window.list_texts().find("Keys")
	print("the key reference is listed at row ", keys_at)
	window.select(keys_at)
	await _settle()
	print("reading it: \"", window.shown_title(), "\"")
	# The one claim worth checking: the subject in the manual is the HUD's own key reference, character
	# for character, so a key cannot be named in the manual that the key panel does not also show.
	print("it is the key reference itself, character for character: ", window.shown_body() == hud.keys_text())
	print("it quotes the undo key: ", window.shown_body().contains("Ctrl+Z"))

	print("--- searching the whole manual ---")
	window.type_search("mulch")
	await _settle()
	print("a search for \"mulch\" leaves ", window.shown_count(), " of ", window.topic_count(), " topics")
	print("the rows it found: ", window.list_texts())
	print("and it turned to: \"", window.shown_title(), "\"")
	print("the status line: \"", window.said(), "\"")

	print("--- searching for nothing real says so rather than showing a near miss ---")
	window.type_search("zzzznothing")
	await _settle()
	print("the list is showing ", window.shown_count(), " rows")
	print("the page says: \"", window.shown_title(), "\"")
	print("the status line: \"", window.said(), "\"")

	print("--- clearing the box brings the whole manual back ---")
	window.type_search("")
	await _settle()
	print("the list is showing ", window.shown_count(), " rows again")
	print("back on: \"", window.shown_title(), "\"")

	print("--- closing it takes it off the screen ---")
	hud.close_help_window()
	await _settle()
	print("the window is up: ", hud.is_help_window_open())

	print("--- opened once more, so the captured frame is the page itself ---")
	hud.open_help_window()
	window.select_topic("What this program is")
	await _settle()
	print("the window is up: ", hud.is_help_window_open())
	print("showing \"", window.shown_title(), "\", ", window.shown_count(), " topics in the contents")


## Let the running scene take a couple of frames, which is where the HUD settles.
func _settle() -> void:
	for _frame in 3:
		await get_tree().process_frame


## The wording the Help menu gives the manual entry, read off the menu plan the same way the bar is
## built from it.
static func _entry_wording(hud: Node) -> String:
	for entry: Dictionary in hud.help_items():
		if String(entry.get("id", "")) == "help.manual":
			return "\"%s\"" % String(entry.get("label", ""))
	return "(no manual entry in the Help menu)"