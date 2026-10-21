extends Node2D
## A live pass over the command palette: the box opened on a real running program, the bar's own
## commands listed in it, a word typed to narrow them, a command actually run through it, and a
## command that cannot run here refused by name.
##
## This is a development tool, not part of the game, and it exists because a box that is all keyboard
## cannot be settled by reading the script that builds it. Three things only a running window can show:
## the rows really come out of the real menu bar (so the box cannot list a command the menu has not
## got); a command chosen in the box really runs, and runs the *same* thing its menu entry runs; and a
## command whose subject is missing really says so rather than doing nothing.
##
## So it instances the **real main scene**, opens the box through the **real HUD** the way the key
## does, and reads the rows off the **real controls**, awaiting real frames so what it prints is what a
## running editor would be showing.
##
## Run `res://scenes/palette_demo.tscn`.

const MAIN := preload("res://scenes/main.tscn")


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	await _settle()
	var hud: Node = main.get_node_or_null(^"Hud")
	if hud == null:
		print("no HUD in the main scene")
		return
	var box: CommandPalette = hud.get(&"_command_palette")

	print("--- the way in ---")
	print("the Help menu offers: ", _palette_wording(hud))
	print("the box is up before anything is opened: ", hud.is_command_palette_open())

	print("--- opening it, the way the key does ---")
	hud.open_command_palette()
	await _settle()
	print("the box is up: ", hud.is_command_palette_open())
	print("it holds ", box.command_count(), " commands of the whole bar")
	print("the status line: \"", box.said(), "\"")
	print("the first rows read as:")
	for index in mini(6, box.shown_count()):
		print("    ", box.list_texts()[index])

	print("--- it reaches inside the submenus too ---")
	box.type_search("A2")
	await _settle()
	print("a search for \"A2\" leaves ", box.shown_count(), " rows: ", box.list_texts())

	print("--- searching by name, best first ---")
	box.type_search("undo")
	await _settle()
	print("a search for \"undo\" leaves ", box.shown_count(), " rows: ", box.list_texts())
	print("and it is turned to: ", box.shown_id(0))

	print("--- a command run from the box really runs ---")
	print("the key reference is up before: ", hud.is_keys_open())
	box.type_search("keys")
	await _settle()
	print("a search for \"keys\" leaves ", box.shown_count(), " rows: ", box.list_texts())
	box.run_command("help.keys")
	await _settle()
	print("the key reference is up after running it from the box: ", hud.is_keys_open())
	print("and the box took itself off the screen: ", not hud.is_command_palette_open())
	# Put it back, so the drawing is left as the demo found it apart from what it is showing.
	hud.open_command_palette()
	await _settle()
	box.run_command("help.keys")
	await _settle()
	print("and running the same command again takes it away: ", not hud.is_keys_open())

	print("--- a command whose subject is missing says so rather than doing nothing ---")
	hud.open_command_palette()
	await _settle()
	box.type_search("save")
	await _settle()
	print("a search for \"save\" leaves ", box.shown_count(), " rows: ", box.list_texts())
	print("running it: ", box.run_command("file.save"))
	print("the box is still up: ", hud.is_command_palette_open())
	print("and it says: \"", box.said(), "\"")

	print("--- clearing the box is the way back to the whole bar ---")
	box.type_search("")
	await _settle()
	print("the list is showing ", box.shown_count(), " rows again")
	print("the status line: \"", box.said(), "\"")

	print("--- the real keyboard: Ctrl+P, typed letters, Enter and Escape ---")
	hud.close_command_palette()
	await _settle()
	print("the box is up before any key is pressed: ", hud.is_command_palette_open())
	await _press_key(KEY_P, true)
	print("after Ctrl+P the box is up: ", hud.is_command_palette_open())
	print("and the field already has the keyboard: ", box.search_field().has_focus())
	for letter in ["k", "e", "y", "s"]:
		await _type_letter(letter)
	print(
		"after typing \"keys\" the field holds \"%s\" and the list shows %d row(s): %s"
		% [box.search_text(), box.shown_count(), box.list_texts()]
	)
	await _press_key(KEY_ENTER, false)
	print("after Enter the box is up: ", hud.is_command_palette_open())
	print("and the key reference is up: ", hud.is_keys_open())
	# Put the drawing back the way the demo found it before the next act.
	hud._menu_keys({})
	await _settle()
	hud.open_command_palette()
	await _settle()
	print("opened again for Escape: ", hud.is_command_palette_open())
	await _press_key(KEY_ESCAPE, false)
	print("after Escape the box is up: ", hud.is_command_palette_open())

	print("--- closed, and opened once more for the captured frame ---")
	hud.close_command_palette()
	await _settle()
	print("the box is up: ", hud.is_command_palette_open())
	hud.open_command_palette()
	box.type_search("plot")
	await _settle()
	print("the box is up: ", hud.is_command_palette_open())
	print("showing ", box.shown_count(), " of ", box.command_count(), " commands: ", box.list_texts())


## Let the running scene take a couple of frames, which is where the HUD settles.
func _settle() -> void:
	for _frame in 3:
		await get_tree().process_frame


## Press and release a key through the real input pipeline, which is the only way the handler that
## reads it ever sees it.
##
## `Input.action_press` will not do: it sets an action's state and sends no event at all, so a key that
## is checked for in `_unhandled_input` - which is where Ctrl+P is answered - could never be exercised
## that way, and a live check that used it would be checking nothing. Both codes are set, because that
## is what the operating system sends and what the binding is matched against.
func _press_key(code: Key, ctrl: bool) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.ctrl_pressed = ctrl
		event.pressed = down
		Input.parse_input_event(event)
	await _settle()


## Type a letter the way a keyboard sends one: the keycode of the key, and the character the focused
## field inserts.
func _type_letter(letter: String) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = letter.to_upper().unicode_at(0) as Key
		event.unicode = letter.unicode_at(0)
		event.pressed = down
		Input.parse_input_event(event)
	await _settle()


## The wording and the key the Help menu gives the palette entry, read off the menu plan the same way
## the bar is built from it.
static func _palette_wording(hud: Node) -> String:
	for entry: Dictionary in hud.help_items():
		if String(entry.get("id", "")) == "help.palette":
			var key := String(entry.get("action", ""))
			return "\"%s\" on the key \"%s\"" % [String(entry.get("label", "")), key]
	return "(no palette entry in the Help menu)"