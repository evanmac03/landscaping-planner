extends Node2D
## A live pass over the drawing's history: the window the HUD opens, a revision recorded, a drawing
## changed, and an earlier revision put back on the canvas.
##
## This is a development tool, not part of the game, and it exists because two things cannot be settled by
## reading. The first is that a `Window`'s controls cannot be clicked by an injected mouse event - the
## click arrives in the main viewport and the window never sees it (see the run-scene notes) - so a button
## inside a window is proved by emitting the signal its press is connected to. The second is that "the
## drawing came back" is only true if the drawing on screen has the shapes it had, which is a thing to
## look at rather than to reason about.
##
## So this instances the **real main scene** and drives the **real window** through the same methods its
## controls call, so the signals, the HUD's handlers, the controller and the plan canvas are all the
## shipped ones. It prints every step, and the screenshot at the end is the window with the history in it
## and the drawing put back.
##
## Run `res://scenes/revision_demo.tscn`.

const MAIN := preload("res://scenes/main.tscn")
const HudScript := preload("res://scripts/hud.gd")
const StoreScript := preload("res://scripts/draft/drawing_store.gd")
const EntityScript := preload("res://scripts/draft/draft_entity.gd")
const LayerSetScript := preload("res://scripts/draft/layer_set.gd")


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	var hud: Node = main.get_node_or_null(^"Hud")
	var controller: Node = main.get_node_or_null(^"DraftController")
	if hud == null or controller == null:
		print("no HUD or no drafting controller in the main scene")
		return

	print("--- a drawing, as a designer would have it before sending it ---")
	var bed := EntityScript.make_rectangle(Vector2(0.0, 0.0), Vector2(12.0, 8.0))
	controller.document.add(bed, LayerSetScript.NEW_BED)
	controller.document.add(
		EntityScript.make_line(Vector2(0.0, 8.0), Vector2(12.0, 8.0)), LayerSetScript.NEW_HARDSCAPE
	)
	var seen: int = controller.document.count()
	print("the drawing has ", seen, " shapes in it")

	print("--- the Edit menu's way in ---")
	print("the entry is there: ", not _entry("edit.revisions").is_empty(),
		" and it is called ", _entry("edit.revisions").get("label", ""))
	hud.open_revision_window()
	var window: RevisionWindow = hud.get(&"_revision_window")
	print("the window is up: ", hud.is_revision_window_open())
	print("with nothing recorded against the drawing yet: ", window.list_texts())
	print("status: ", hud.revision_status_text())

	print("--- recording the revision that goes to the client ---")
	window.type_message("sent to the client")
	print("typed: ", window.message_text())
	# `record()` is what the button's press is connected to, so the box is emptied by the same code a
	# person's click runs. Emitting the signal straight would leave the text sitting there.
	print("recording it: ", window.record())
	print("the message box was emptied by the window: ", window.message_text() == "")
	print("the history now: ", window.list_texts())
	print("status: ", hud.revision_status_text())
	var first: Dictionary = controller.revision_rows()[0]
	print("kept for the file: message ", first["message"], ", by ", first["author"],
		", when ", first["when"], ", ", first["shapes"], " shapes")
	print("and it is on disk beside the drawings: ", _history_exists(controller))

	print("--- what happened after the client saw it ---")
	controller.document.add(
		EntityScript.make_circle(Vector2(3.0, 5.0), 2.0), LayerSetScript.NEW_PLANTING
	)
	controller.document.add(
		EntityScript.make_polyline(PackedVector2Array([
			Vector2(14.0, 0.0), Vector2(20.0, 0.0), Vector2(17.0, 5.0),
		]), true), LayerSetScript.NEW_TURF
	)
	print("the drawing has ", controller.document.count(), " shapes now")
	window.type_message("client asked for more lawn")
	window.record()
	print("the history: ", window.list_texts())
	print("the difference the second revision records: ", window.change_text())
	print("status: ", hud.revision_status_text())

	print("--- putting the first one back ---")
	window.select(0)
	print("the selected revision: ", window.description_text())
	print("which has nothing before it to differ from: '", window.change_text(), "'")
	# What the "Put this revision back" button's press is connected to.
	print("putting it back: ", window.restore())
	print("the drawing has ", controller.document.count(), " shapes, as revision 1 had: ",
		controller.document.count() == seen)
	print("status: ", hud.revision_status_text())
	print("and it is a change like any other, so it can be undone: ", controller.document.undo_last())
	print("after the undo the drawing has ", controller.document.count(), " shapes again")
	# The window lists the history, not the drawing: recording after a restore is a third revision, and the
	# drawing it holds is the one on screen.
	print("the history still reads: ", window.list_texts())


static func _entry(id: StringName) -> Dictionary:
	for entry: Dictionary in HudScript.menu_entries():
		if StringName(entry.get("id", &"")) == id:
			return entry
	return {}


func _history_exists(controller: Node) -> bool:
	var path: String = StoreScript.revisions_path(controller.drawing_path)
	if path.is_empty():
		return false
	return FileAccess.file_exists(path)