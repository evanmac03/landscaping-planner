extends Node

const Dialog := preload("res://scripts/draft/layer_dialog.gd")
const Controller := preload("res://scripts/draft/draft_controller.gd")
const Document := preload("res://scripts/draft/draft_document.gd")
const Tool := preload("res://scripts/draft/draft_tool.gd")
const Layers := preload("res://scripts/draft/layer_set.gd")


func _dialog():
	var dialog := Dialog.new()
	dialog.controller = Controller.new()
	dialog.controller.document = Document.new()
	dialog.controller.tool = Tool.new()
	return dialog


func test_filtering_and_clearing_search_preserve_layers() -> void:
	var dialog = _dialog()
	dialog.refresh_layers()
	var count: int = dialog.document.layers.layers().size()
	assert(dialog._filtered_layers.size() == count)
	dialog.set_search_text("new-bed")
	assert(dialog._filtered_layers.size() == 1)
	assert(dialog._filtered_layers[0]["name"] == Layers.NEW_BED)
	dialog.refresh_layers()
	assert(dialog._filtered_layers.size() == 1)
	dialog.set_search_text("")
	assert(dialog._filtered_layers.size() == count)
	dialog.controller.free()
	dialog.free()


func test_layer_properties_match_the_document() -> void:
	var dialog = _dialog()
	var layer = dialog.document.layers.get_layer(Layers.NEW_BED)
	layer.visible = false
	assert(dialog.get_layer_colour(layer.name) == layer.screen_colour)
	layer.plot_colour = Color.RED
	assert(dialog.get_layer_colour(layer.name) == Color.RED)
	assert(dialog.get_layer_weight(layer.name) == layer.plot_weight_mm)
	assert(dialog.get_layer_linetype(layer.name) == layer.linetype)
	assert(dialog.get_layer_purpose(layer.name) == layer.purpose)
	assert(dialog.layer_has_plots(layer.name) == layer.plots)
	assert(dialog.is_layer_frozen(layer.name))
	dialog.refresh_layers()
	for record in dialog._filtered_layers:
		if record["name"] == layer.name:
			assert(record["weight"] == layer.plot_weight_mm)
			assert(record["is_frozen"])
	dialog.controller.free()
	dialog.free()


func test_locking_is_undoable_and_selection_uses_controller() -> void:
	var dialog = _dialog()
	dialog.set_layer_current(Layers.NEW_BED)
	assert(dialog.controller.current_layer() == Layers.NEW_BED)
	assert(dialog.toggle_layer_lock(Layers.NEW_BED))
	assert(dialog.is_layer_locked(Layers.NEW_BED))
	assert(dialog.document.undo_last())
	assert(not dialog.is_layer_locked(Layers.NEW_BED))
	assert(dialog.toggle_layer_lock(Layers.NEW_BED))
	assert(not dialog.toggle_layer_lock(Layers.NEW_BED))
	dialog.controller.free()
	dialog.free()


func test_unattached_dialog_has_no_layers() -> void:
	var dialog := Dialog.new()
	dialog.refresh_layers()
	assert(dialog._filtered_layers.is_empty())
	assert(dialog.get_layer_linetype(&"missing") == &"continuous")
	assert(not dialog.is_layer_locked(&"missing"))
	dialog.free()
