extends Node2D
## A live pass over the sheet setup: the window the HUD opens, the sheets a person adds and edits, and
## the files a whole set plots to.
##
## This is a development tool, not part of the game, and it exists because of two things that reading
## cannot settle. The first is that a `Window`'s controls cannot be clicked by an injected mouse event:
## the click arrives in the main viewport and the window never sees it (see the run-scene notes), so a
## button inside a window is proved by calling the method its press is connected to. The second is that
## "it plots the set" is only true if two files are on disk afterwards with the right words in them.
##
## So this instances the **real main scene** and drives the **real window** through the same methods its
## controls call - `sheet_added`, `type_field`, `choose_scale`, `tick_flag`, `plot_set_requested` - so
## the signals, the HUD's handlers, the controller and the plotter are all the shipped ones. It prints
## every step, and the screenshot at the end is the window with the set in it.
##
## Run `res://scenes/sheet_set_demo.tscn`.

const MAIN := preload("res://scenes/main.tscn")
const EntityScript := preload("res://scripts/draft/draft_entity.gd")
const LayerSetScript := preload("res://scripts/draft/layer_set.gd")

## Where a plot is written, which is what this tool then reads back.
const SHEETS := "user://sheets"


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	var hud: Node = main.get_node_or_null(^"Hud")
	var controller: Node = main.get_node_or_null(^"DraftController")
	if hud == null or controller == null:
		print("no HUD or no drafting controller in the main scene")
		return

	# Something on the drawing: a plot of an empty drawing is refused, and refusing is not what this
	# tool is here to prove.
	controller.document.add(
		EntityScript.make_rectangle(Vector2(0.0, 0.0), Vector2(12.0, 8.0)), LayerSetScript.NEW_BED
	)

	print("--- opening the sheet setup from the File menu ---")
	hud.open_sheet_window()
	var window: SheetWindow = hud.get(&"_sheet_window")
	print("the window is up: ", hud.is_sheet_window_open())
	print("the set as the window found it: ", window.list_texts())
	print("which the set itself agrees with: ", controller.sheet_set().titles())
	print("and the drawing is set up as sheet ", controller.sheet_set().current_index() + 1)
	print("status: ", hud.sheet_status_text())

	print("--- a second sheet, as the Add button asks for it ---")
	window.sheet_added.emit()
	print("the list now: ", window.list_texts())
	print("numbers: ", controller.sheet_set().numbers())
	# The form has to end up on the sheet that was just added, or the designer types into the sheet they
	# were already on and the new one stays empty.
	print("the form is on sheet ", window.selected_index() + 1,
		", the set's current sheet is ", controller.sheet_set().current_index() + 1,
		", they agree: ", window.selected_index() == controller.sheet_set().current_index())

	print("--- typing into the sheet in hand, as the form does ---")
	print("typed: ", window.type_field("title", "Planting plan"))
	print("chose 1:200: ", window.choose_scale(200.0))
	print("turned it portrait: ", window.tick_flag("portrait", true))
	print("and the drawing followed the sheet: ", controller.sheet == "A3", " at 1:%d" % int(controller.plot_scale))
	print("project and date: ", window.type_identity("project", "Riverbend"), window.type_identity("date", "2026-05-04"))
	print("the row says: ", window.selected_row().get("description", ""))

	print("--- choosing the first sheet back ---")
	window.select(0)
	window.sheet_selected.emit(0)
	print("the drawing is set up as sheet ", controller.sheet_set().current_index() + 1,
		" on ", controller.sheet, " at 1:%d" % int(controller.plot_scale))

	print("--- plotting the set ---")
	window.plot_set_requested.emit()
	print("status: ", hud.sheet_status_text())
	var written: PackedStringArray = DirAccess.get_files_at(SHEETS)
	print("files in ", ProjectSettings.globalize_path(SHEETS), ": ", written.size())
	for file_name: String in written:
		var text := _read("user://sheets/%s" % file_name)
		print("  ", file_name, ": L1.1 on it? ", text.contains("L1.1"), ", L1.2? ", text.contains("L1.2"),
			", Planting plan? ", text.contains("Planting plan"), ", Riverbend? ", text.contains("Riverbend"))
	print("--- what the set holds now ---")
	for row: Dictionary in controller.sheet_rows():
		print("  ", row["number"], "  ", row["title"], "  ", row["sheet"], "  1:%d" % int(row["scale"]),
			"  portrait: ", row["portrait"], "  current: ", row["current"])
	# The HUD keeps the drawing's live paper fields in step with the current sheet, which is the one
	# thing a person would notice if it drifted.
	print("the drawing's own paper: ", controller.sheet, " 1:%d" % int(controller.plot_scale),
		" title: ", controller.drawing_title, " project: ", controller.project_name)


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_buffer(file.get_length()).get_string_from_utf8()
	file.close()
	return text