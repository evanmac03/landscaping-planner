extends Node2D
## A live pass over the copy kept in case the program stops: a copy really written by a running
## program, a copy really left behind by a session that ended without saving, the question really put
## on the screen, and the two answers really doing what they say to the drawing behind it.
##
## This is a development tool, not part of the game. It exists because a feature whose whole subject is
## what happens when the program *stops* cannot be settled by reading the script that runs it: what a
## crash leaves on disk is a file, and the only honest way to check the file is to let the real program
## write one. Three things only a running window can show: that the copy comes out of the real drawing
## the real controller holds; that the File menu's line and the entry move together when work is
## waiting, and go back when somebody answers the question; and that answering it really changes the
## drawing - with an undo step, because recovering the wrong copy has to be one Ctrl+Z away.
##
## So it instances the **real main scene** and drives the **real HUD**. Run
## `res://scenes/autosave_demo.tscn`.
##
## It clears the recovery folder before it starts and again when it is done: the copies it makes are of
## test shapes, and leaving one behind would offer the next person who opens the app a "rescue" of work
## nobody lost.

const MAIN := preload("res://scenes/main.tscn")
const AutosaveScript := preload("res://scripts/draft/autosave.gd")
const EntityScript := preload("res://scripts/draft/draft_entity.gd")
const LayerSetScript := preload("res://scripts/draft/layer_set.gd")


func _ready() -> void:
	AutosaveScript.clear_all()
	var main: Node = MAIN.instantiate()
	add_child(main)
	await _settle()
	var hud: Node = main.get_node_or_null(^"Hud")
	if hud == null:
		print("no HUD in the main scene")
		return
	var draft: DraftController = hud.get(&"_draft")
	if draft == null:
		print("no drafting controller in the main scene")
		return
	var dialog: ConfirmationDialog = hud.get(&"_recovery_dialog")
	if dialog == null:
		print("the HUD built no recovery question")
		return

	print("--- the File menu before anything has happened ---")
	print("the entry: ", _entry_wording(hud))
	print("the line above it: \"", _info_line(hud), "\"")
	print("the entry is switched off: ", _entry_disabled(hud, &"file.recover"))
	print("the question is built and hidden: ", not dialog.visible)
	print("the folder of copies is empty: ", AutosaveScript.list())

	print("--- a copy written by the running program ---")
	for index in 3:
		draft.document.add(
			EntityScript.make_line(Vector2(index, 0), Vector2(index + 4, 2 + index)),
			LayerSetScript.NEW_HARDSCAPE
		)
	await _settle()
	print("the drawing is unsaved: ", draft.dirty, " with ", draft.document.count(), " shapes on it")
	print("nothing has been kept yet: ", AutosaveScript.list())
	# The frame's own clock, asked the way `_process` asks it - a little under the interval first, so
	# that what the interval does is visible rather than assumed.
	hud._tick_autosave(10.0)
	print("ten seconds in, still nothing: ", AutosaveScript.list())
	hud._tick_autosave(AutosaveScript.INTERVAL)
	var kept: Dictionary = AutosaveScript.read(AutosaveScript.path_for(""))
	print("half a minute in, a copy is on disk: ", bool(kept["ok"]), " -> ", kept["path"])
	print("it holds: ", AutosaveScript.describe(kept))
	print("and it is the drawing that is on the screen, never offered back: ", hud.get(&"_pending_recovery").is_empty())

	print("--- a copy a session that ended without saving left behind ---")
	_leave_work_behind(draft, 9)
	hud._refresh_pending_recovery()
	await _settle()
	print("what is waiting: ", AutosaveScript.describe(hud.get(&"_pending_recovery")))
	print("the line above the entry now reads: \"", _info_line(hud), "\"")
	print("and the entry is switched on: ", not _entry_disabled(hud, &"file.recover"))
	print("the palette knows the command too: ", _in_the_palette(hud, "Recover unsaved work..."))

	print("--- the question, opened the way the entry opens it ---")
	hud.run_entry(_entry(hud, &"file.recover"))
	await _settle()
	print("the question is on the screen: ", dialog.visible)
	print("and it says: \"", String(dialog.dialog_text).replace("\n", " / "), "\"")

	print("--- recovering ---")
	var before: int = draft.document.count()
	# The button is pressed rather than the handler called: a handler called directly would prove
	# nothing about the label on the button, and the label is what a person acts on.
	await _press(dialog, "Recover")
	print("the question is off the screen: ", not dialog.visible)
	print("the drawing went from ", before, " to ", draft.document.count(), " shapes")
	print("it is unsaved, because the file it belongs to does not hold it: ", draft.dirty)
	print("it says what it did: \"", draft.last_message, "\"")
	print("recovering is one undoable step: ", draft.document.gestures.can_undo())
	print("the offer is gone: ", hud.get(&"_pending_recovery").is_empty())
	print("and a fresh copy of what came back is down already: ", AutosaveScript.list())
	draft.undo()
	await _settle()
	print("Ctrl+Z puts the drawing back to ", draft.document.count(), " shapes")

	print("--- saying no ---")
	_leave_work_behind(draft, 12)
	hud._refresh_pending_recovery()
	await _settle()
	print("work is waiting again: ", not hud.get(&"_pending_recovery").is_empty())
	hud.run_entry(_entry(hud, &"file.recover"))
	await _settle()
	await _press(dialog, "Not now")
	print("closing the question decides nothing - still waiting: ", not hud.get(&"_pending_recovery").is_empty())
	print("and the copy is still on disk: ", AutosaveScript.list())
	hud.run_entry(_entry(hud, &"file.recover"))
	await _settle()
	await _press(dialog, "Discard it")
	print("discarding takes the offer away: ", hud.get(&"_pending_recovery").is_empty())
	print("and removes the copy, so it is never asked again: ", AutosaveScript.list())

	print("--- left on the screen: the question, as a person would first meet it ---")
	_leave_work_behind(draft, 14)
	hud._refresh_pending_recovery()
	await _settle()
	hud.run_entry(_entry(hud, &"file.recover"))
	await _settle()
	print("the question is up: ", dialog.visible)
	print("the File menu says: \"", _info_line(hud), "\"")

	# Left clean: the demo's own answers are given before it goes, so nothing of this run can be
	# offered to the next person who opens the program.
	hud._discard_the_recovery()
	draft.document.clear()
	draft.dirty = false
	AutosaveScript.clear_all()


## Write a copy of a drawing this one has never been, under the identity the drawing in hand uses: the
## file a session that ended without saving leaves behind. The gesture serial is what tells the two
## apart - a copy of the drawing in hand carries the serial it is at, and this one carries one the
## drawing has not reached.
##
## The entities are built here rather than drawn, so they are given a layer by hand: a document assigns
## the layer when an entity is added to it, and a drawing whose shapes belong to no layer is not a
## drawing the program can read.
func _leave_work_behind(draft: DraftController, shapes: int) -> void:
	var state: Dictionary = draft.document.to_dict()
	var built: Dictionary = {}
	for index in shapes:
		var line: EntityScript = EntityScript.make_line(
			Vector2(index, 0), Vector2(index + 2, 1.5 + index)
		)
		var row: Dictionary = line.to_dict()
		row["id"] = 1000 + index
		row["layer"] = String(LayerSetScript.NEW_HARDSCAPE)
		built[1000 + index] = row
	state["entities"] = built
	state["order"] = built.keys()
	AutosaveScript.write(state, "", draft.project_name, draft.document.gesture_serial() + 5)


## The File menu entry that offers the recovery, or an empty dictionary when the bar has none - which
## is itself the thing worth checking first.
static func _entry(hud: Node, id: StringName) -> Dictionary:
	for entry: Dictionary in hud.file_items():
		if StringName(entry.get("id", &"")) == id:
			return entry
	return {}


static func _entry_wording(hud: Node) -> String:
	var entry: Dictionary = _entry(hud, &"file.recover")
	if entry.is_empty():
		return "(the File menu offers no recovery)"
	return "\"%s\", running \"%s\", available when \"%s\"" % [
		String(entry.get("label", "")), String(entry.get("method", "")), String(entry.get("enabled_when", "")),
	]


## Whether the bar is really showing the entry switched off, read off the popup rather than off the
## plan: a menu item that is greyed is a fact about the screen.
static func _entry_disabled(hud: Node, id: StringName) -> bool:
	var found: Array = hud._find_item(id)
	if found.is_empty():
		return true
	var popup: PopupMenu = found[0]
	return popup.is_item_disabled(int(found[1]))


static func _info_line(hud: Node) -> String:
	var found: Array = hud._find_item(&"file.info")
	if found.is_empty():
		return ""
	var popup: PopupMenu = found[0]
	return popup.get_item_text(int(found[1]))


static func _in_the_palette(hud: Node, label: String) -> bool:
	for row: Dictionary in hud.command_rows():
		if String(row.get("label", "")) == label:
			return true
	return false


## Let the running scene take a couple of frames, which is where the HUD settles.
func _settle() -> void:
	for _frame in 3:
		await get_tree().process_frame


## Press one of the question's own buttons.
func _press(dialog: ConfirmationDialog, text: String) -> void:
	var button: Button = _button_named(dialog, text)
	if button == null:
		print("the question has no button called \"%s\"" % text)
		return
	button.pressed.emit()
	await _settle()


## A button under a node, by the words on it. The dialog's own buttons are built by the engine and are
## not named, so the label is the only handle there is - which is also why pressing them matters: the
## label is what a person reads before deciding.
##
## `get_children(true)` and not `get_children()`: a dialog's buttons are *internal* nodes, and the
## plain call hides them, so a search over the default list finds nothing at all and looks as though the
## dialog had no buttons.
static func _button_named(under: Node, text: String) -> Button:
	for child in under.get_children(true):
		if child is Button and (child as Button).text == text:
			return child
		var deeper: Button = _button_named(child, text)
		if deeper != null:
			return deeper
	return null