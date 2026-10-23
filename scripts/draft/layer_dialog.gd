extends Node
## Layer-management data for a dialog backed by the drawing's controller.

const ControllerScript := preload("res://scripts/draft/draft_controller.gd")
const DocumentScript := preload("res://scripts/draft/draft_document.gd")

var controller: ControllerScript
var document: DocumentScript:
	get:
		return controller.document if controller != null else null

var _search_text: String = ""
var _filtered_layers: Array[Dictionary] = []


func _ready() -> void:
	refresh_layers()


func refresh_layers() -> void:
	_filter_layers()


func set_search_text(text: String) -> void:
	_search_text = text
	_filter_layers()


func _filter_layers() -> void:
	_filtered_layers.clear()
	for layer in _get_all_layers():
		if _search_text.is_empty() or String(layer["name"]).to_lower().contains(_search_text.to_lower()):
			_filtered_layers.append(layer)


func _get_all_layers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if document == null:
		return result
	for layer in document.layers.layers():
		result.append({
			"name": layer.name,
			"purpose": layer.purpose,
			"colour": layer.screen_colour,
			"weight": layer.plot_weight_mm,
			"linetype": layer.linetype,
			"plots": layer.plots,
			"is_locked": layer.locked,
			"is_frozen": not layer.visible,
		})
	return result


func toggle_layer_lock(layer_name: StringName) -> bool:
	if document == null or not document.layers.has(layer_name):
		push_error("Cannot lock a layer without a drawing containing that layer.")
		return false
	var locked := not document.is_layer_locked(layer_name)
	var words := "locking %s" % layer_name if locked else "unlocking %s" % layer_name
	document.begin_gesture(words)
	document.layers.set_locked(layer_name, locked)
	document.changed.emit()
	refresh_layers()
	return locked


func set_layer_current(layer_name: StringName) -> void:
	if document == null or not document.layers.has(layer_name):
		push_error("Cannot select a layer without a drawing containing that layer.")
		return
	controller.set_layer(layer_name)


func get_layer_colour(layer_name: StringName) -> Color:
	if document != null:
		for layer in document.layers.layers():
			if layer.name == layer_name:
				return layer.screen_colour if layer.plot_colour == Color.BLACK else layer.plot_colour
	return Color(0.5, 0.5, 0.5)


func get_layer_weight(layer_name: StringName) -> float:
	if document != null:
		for layer in document.layers.layers():
			if layer.name == layer_name:
				return layer.plot_weight_mm
	return 0.5


func is_layer_locked(layer_name: StringName) -> bool:
	return document != null and document.is_layer_locked(layer_name)


func is_layer_frozen(layer_name: StringName) -> bool:
	if document != null:
		for layer in document.layers.layers():
			if layer.name == layer_name:
				return not layer.visible
	return false


func get_layer_linetype(layer_name: StringName) -> StringName:
	if document != null:
		for layer in document.layers.layers():
			if layer.name == layer_name:
				return layer.linetype
	return &"continuous"


func layer_has_plots(layer_name: StringName) -> bool:
	if document != null:
		for layer in document.layers.layers():
			if layer.name == layer_name:
				return layer.plots
	return false


func get_layer_purpose(layer_name: StringName) -> String:
	if document != null:
		for layer in document.layers.layers():
			if layer.name == layer_name:
				return layer.purpose
	return ""
