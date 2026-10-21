extends Node2D
## A live pass over the volume dimension: a patio on a real drawing, taken off as an area, then bought
## by the cubic metre once a depth is stated for its layer.
##
## This is a development tool, not part of the game. It exists because the feature is a *measurement*
## and the only honest evidence for one is the number a running program prints: that the takeoff really
## turns 24 m2 into 1.8 m3, that the suggested item really changes to a per-m3 rate, and that the line
## the panel shows says so in the word "volume" rather than only in a unit symbol.
##
## So it instances the **real main scene**, draws through the **real document**, opens the **real
## window** through the HUD the way the menu entry does, and states the depth through the window's own
## controls - the same calls a click makes - awaiting real frames so what it prints is what the running
## program would be showing. The window is left open on the takeoff tab, with the volume line in it.
##
## Run `res://scenes/volume_demo.tscn`.

const MAIN := preload("res://scenes/main.tscn")
const Entity := preload("res://scripts/draft/draft_entity.gd")

const HARDSCAPE := &"300-NEW-HARD"
const PATIO := Vector2(6.0, 4.0)


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	await _settle()
	var hud: Node = main.get_node_or_null(^"Hud")
	if hud == null:
		print("no HUD in the main scene")
		return
	var draft: Node = hud.get(&"_draft")
	if draft == null or draft.document == null:
		print("no drawing in the main scene")
		return

	# A patio, drawn on the layer a paving plan uses: 6 x 4 m, which is 24 m2.
	draft.document.add(Entity.make_rectangle(Vector2(0, 0), PATIO), HARDSCAPE)
	print("the drawing holds ", draft.document.count(), " entities")

	print("--- taking it off as an area, the way the menu does ---")
	hud._menu_take_off({})
	await _settle()
	var window: EstimateWindow = hud.get(&"_estimate_window")
	print("the window is up: ", hud.is_estimate_window_open())
	print("it is showing the tab: \"", window.tab_titles()[0], "\"")
	for line in window.takeoff_texts():
		print("    ", line)
	print("the depth row is usable: ", window.depth_row_enabled())
	print("the layers it offers: ", window.depth_choices())

	print("--- stating a depth, through the row's own controls ---")
	var chosen: bool = window.choose_depth(HARDSCAPE)
	window.set_depth_mm(75)
	window._on_depth_stated()
	await _settle()
	print("the hardscape layer was chosen from the row: ", chosen)
	print("the row now reads: \"", _words_for(window, HARDSCAPE), "\"")
	print("the status line: \"", window.status_text(), "\"")
	print("and the takeoff is now:")
	for line in window.takeoff_texts():
		print("    ", line)
	print("and on the proposal tab:")
	for line in window.line_texts():
		print("    ", line)

	print("--- the same layer taken the other way ---")
	print("forgetting the depth: ", window.desk.clear_layer_depth(HARDSCAPE))
	# The desk measured the drawing again, but a panel is only as fresh as the last thing that filled
	# it: the row's own button refreshes it, and this call is what that button does.
	window.refresh()
	await _settle()
	for line in window.takeoff_texts():
		print("    ", line)

	print("--- and stated once more, so the captured frame is the volume ---")
	window.choose_depth(HARDSCAPE)
	window.set_depth_mm(75)
	window._on_depth_stated()
	await _settle()
	print("the window is up, on the takeoff tab, with:")
	for line in window.takeoff_texts():
		print("    ", line)


## Let the running scene take a couple of frames, which is where the HUD settles.
func _settle() -> void:
	for _frame in 3:
		await get_tree().process_frame


## The depth row's own words for a layer, rather than an index: the order of the chooser is its own
## business and this tool is reporting what a person would read off the row.
static func _words_for(window: EstimateWindow, layer_name: StringName) -> String:
	var choices: Array[StringName] = window.depth_choices()
	var words: Array[String] = window.depth_texts()
	for index in choices.size():
		if choices[index] == layer_name:
			return words[index]
	return "(not offered)"