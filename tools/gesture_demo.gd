extends Node2D
## A live pass over the drawing's gesture history: the undo and redo buttons named, a drawn shape
## recorded under the words a person would use for it, and the join to the revision history - how many
## gestures have happened since a revision was sent.
##
## This is a development tool, not part of the game, and it exists because two things cannot be settled
## by reading. The first is that a tooltip is only true if the running HUD actually puts it on the button:
## the palette decides what to write from a state signature, and a signature that forgot the gesture
## label would leave the tooltip naming whatever was in hand when the palette last redrew. The second is
## that "two gestures since" is a claim about a live drawing's own count, and the line is kept current by
## the HUD's own per-frame poll rather than by the act of recording anything.
##
## So this instances the **real main scene**, draws through the **real controller** (arming a tool and
## clicking, exactly as a mouse does), and reads the tooltips off the **real buttons** - and it awaits
## real frames between the steps, so what it prints is what a running editor would be showing rather
## than numbers this tool poked in itself.
##
## Run `res://scenes/gesture_demo.tscn`.

const MAIN := preload("res://scenes/main.tscn")
const ToolScript := preload("res://scripts/draft/draft_tool.gd")


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	var hud: Node = main.get_node_or_null(^"Hud")
	var controller: Node = main.get_node_or_null(^"DraftController")
	if hud == null or controller == null:
		print("no HUD or no drafting controller in the main scene")
		return
	var window: RevisionWindow = hud.get(&"_revision_window")

	print("--- the buttons before anything has been done ---")
	print("undo says: ", _tooltip(hud, &"_undo_button"))
	print("redo says: ", _tooltip(hud, &"_redo_button"))

	print("--- drawing a line the ordinary way: arm the tool, then click twice ---")
	controller.arm(ToolScript.Kind.LINE)
	print("the tool in hand is: ", ToolScript.label_for(controller.current_tool()))
	controller.click(Vector2(700.0, 420.0))
	controller.click(Vector2(950.0, 520.0))
	await _settle()
	print("the drawing has ", controller.document.count(), " shapes")
	print("the gesture it recorded: \"", controller.document.undo_label(), "\"")
	print("undo now says: ", _tooltip(hud, &"_undo_button"))
	print("and redo still says: ", _tooltip(hud, &"_redo_button"))

	print("--- a revision goes out at that point ---")
	hud.open_revision_window()
	print("the history window is up: ", hud.is_revision_window_open())
	window.type_message("sent to the client")
	window.record()
	await _settle()
	print("the history: ", window.list_texts())
	window.select(0)
	print("the revision's own line: ", window.description_text())
	print("and what it says about the drawing since: \"", window.since_text(), "\"")

	print("--- two more gestures after the client saw it ---")
	controller.arm(ToolScript.Kind.LINE)
	controller.click(Vector2(600.0, 640.0))
	controller.click(Vector2(860.0, 700.0))
	hud.set_layer_locked(true)
	print("the drawing has ", controller.document.count(), " shapes and the layer in hand is locked")
	print("the last gesture recorded: \"", controller.document.undo_label(), "\"")
	# Nothing was pushed into the window here: the HUD's own poll saw the count move and refreshed the
	# rows, which is why the line is right rather than still saying nobody had touched the drawing.
	await _settle()
	print("what the revision window says has happened since it was sent: \"", window.since_text(), "\"")
	print("undo now says: ", _tooltip(hud, &"_undo_button"))
	print("and the redo side is empty: ", _tooltip(hud, &"_redo_button"))

	print("--- undoing the lock: the redo side names it in turn ---")
	print("undoing: ", controller.undo())
	print("the drawing still has ", controller.document.count(), " shapes")
	print("and the status line said: ", controller.last_message)
	await _settle()
	print("undo now says: ", _tooltip(hud, &"_undo_button"))
	print("redo now says: ", _tooltip(hud, &"_redo_button"))
	print("the count since the revision stands, because a count does not go backwards: \"",
		window.since_text(), "\"")

	print("--- a revision recorded before gestures were counted admits it does not know ---")
	# Written straight onto the log the way a file from an older version would arrive: no `serial` field,
	# so it reads as 0 and the difference it would report is unknowable rather than great. The HUD's own
	# signature is cleared so its poll sees a change, exactly as a drawing opened from an older file does.
	controller.revisions.capture(controller.document.to_dict(), "imported from an older version")
	hud.set(&"_revision_state", "")
	await _settle()
	print("the history now: ", window.list_texts())
	window.select(1)
	print("the older revision's line: ", window.description_text())
	print("and what it says about the drawing since: \"", window.since_text(), "\"")
	window.select(0)
	print("back on the current revision: \"", window.since_text(), "\"")


## Let the running scene take a couple of frames, which is where the HUD refreshes what is on screen.
func _settle() -> void:
	for _frame in 3:
		await get_tree().process_frame


static func _tooltip(hud: Node, field: StringName) -> String:
	var button: Button = hud.get(field) as Button
	if button == null:
		return "(no such button)"
	return "\"%s\"" % button.tooltip_text