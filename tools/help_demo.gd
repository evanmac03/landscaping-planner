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
const HelpDocScript := preload("res://scripts/help_doc.gd")


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
	# The row, not the position in the list of subjects: the contents is drawn with section headings,
	# which are rows a person cannot choose, so a topic's place in `list_texts()` is not its row.
	var keys_at := window.row_of("Keys")
	print("the key reference is listed at row ", keys_at)
	window.select(keys_at)
	await _settle()
	print("reading it: \"", window.shown_title(), "\"")
	# The one claim worth checking: the subject in the manual is the HUD's own key reference, character
	# for character, so a key cannot be named in the manual that the key panel does not also show.
	print("it is the key reference itself, character for character: ", window.shown_body() == hud.keys_text())
	print("it quotes the undo key: ", window.shown_body().contains("Ctrl+Z"))

	print("--- the contents is grouped under headings ---")
	for row in window.list_rows():
		if row in HelpDocScript.section_titles():
			print("  [", row, "]")

	print("--- the subjects that point at others ---")
	window.select_topic("Plants")
	await _settle()
	print("\"Plants\" points at: ", window.see_links())
	print("pressing the first one: ", window.follow(window.see_links()[0]))
	await _settle()
	print("and the page is now on: \"", window.shown_title(), "\"")
	print("walking back: ", window.back(), " -> \"", window.shown_title(), "\"")
	print("and forward again: ", window.forward(), " -> \"", window.shown_title(), "\"")

	print("--- searching the whole manual ---")
	window.type_search("mulch")
	await _settle()
	print("a search for \"mulch\" leaves ", window.shown_count(), " of ", window.topic_count(), " topics")
	print("the rows it found: ", window.list_texts())
	print("and it turned to: \"", window.shown_title(), "\"")
	print("the status line: \"", window.said(), "\"")

	# The same rule the command palette searches its rows by, with the section in the menu's place: a
	# subject named for the word, then one whose prose discusses it, then one only filed where the word
	# is written. "water" used to come back in reading order, with the subject called Water: irrigation
	# last of the four.
	print("--- a subject is read by the word it is named for first ---")
	for ranked: String in ["water", "food", "business"]:
		window.type_search(ranked)
		await _settle()
		print("  \"%s\" -> %s" % [ranked, window.list_texts()])
		print("      opens on \"%s\"" % window.shown_title())
		print("      the status line: \"", window.said(), "\"")

	# The word the food pages are actually about. It used to find nothing at all: the sowing, the
	# rotation and the yield were all prose inside one subject, so a person searching for the thing
	# they wanted was told the manual does not mention it.
	print("--- a word that has to find something ---")
	for word: String in ["yield", "succession", "companion"]:
		window.type_search(word)
		await _settle()
		print("  \"%s\" -> %s" % [word, window.list_texts()])

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

	print("--- the arrow keys walk the contents, stepping over the headings ---")
	window.select_topic("Plants")
	await _settle()
	print("on \"", window.shown_title(), "\"")
	for _step in 2:
		window.move_selection(1)
		print("  down -> \"", window.shown_title(), "\"")
	window.move_selection(-1)
	print("  up   -> \"", window.shown_title(), "\"")
	var walked := 0
	while window.move_selection(1):
		walked += 1
	print("  walking to the foot visits ", walked, " more subjects, stopping on \"", window.shown_title(), "\"")

	print("--- closing it takes it off the screen ---")
	hud.close_help_window()
	await _settle()
	print("the window is up: ", hud.is_help_window_open())

	print("--- opened once more, so the captured frame is the page itself ---")
	hud.open_help_window()
	# Left on a subject that points at others, so the captured frame carries the "Read next:" row as
	# well as the grouped contents. A subject with no links is the exception, not the picture.
	window.select_topic("Plants")
	await _settle()
	print("the window is up: ", hud.is_help_window_open())
	print("showing \"", window.shown_title(), "\", ", window.shown_count(), " topics in the contents")
	print("offering to read next: ", window.see_links())


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