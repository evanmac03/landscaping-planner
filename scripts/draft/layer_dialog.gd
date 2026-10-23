# Layer Dialog - searchable, filterable layer management UI
# Provides UI for managing the 15+ layers in the drawing

extends Node
## Shows when the user opens the layer management dialog from the HUD or palette.

# The layer presets from LayerSetScript.PRESETS define the full layer list.
# Each layer has: name, purpose, colour, weight, linetype, plots

# Search/filter state
var _search_text: String = ""
var _filtered_layers: Array[Dictionary] = []

# UI state
var _is_dirty: bool = false  # Layer changes need to be committed

func _ready() -> void:
	refresh_layers()

func refresh_layers() -> void:
	var all_layers: Array[Dictionary] = []
	
	# Get all layers from the document
	if document != null:
		for layer in document.layers.layers():
			all_layers.append({
				"name": layer.name,
				"purpose": layer.purpose,
				"colour": layer.screen_colour,
				"weight": layer.weight,
				"linetype": layer.linetype,
				"plots": layer.plots,
				"is_locked": document.is_layer_locked(layer.name),
				"is_frozen": false,  # Would need additional state
			})
	
	# Initial filter: show all layers
	_filtered_layers = all_layers
	_update_search_highlights()

func _update_search_highlights() -> void:
	# Could highlight matching parts of layer names
	pass

func set_search_text(text: String) -> void:
	_search_text = text
	_filter_layers()

func _filter_layers() -> void:
	if _search_text == "":
		_filtered_layers = []
	else:
		_filtered_layers = []
		for layer in _get_all_layers():
			if layer["name"].to_lower().contains(_search_text.to_lower()):
				_filtered_layers.append(layer)

func _get_all_layers() -> Array[Dictionary]:
	# This would typically query the document layers
	# For now, return empty - the dialog would be populated from the document
	return []

func toggle_layer_lock(layer_name: StringName) -> bool:
	if document != null:
		current_state = document.is_layer_locked(layer_name)
		document.set_layer_locked(layer_name, !current_state)
		return !current_state
	return false

func set_layer_current(layer_name: StringName) -> void:
	if document != null:
		document.drawing_layer = layer_name
		_refresh_canvas()

func get_layer_colour(layer_name: StringName) -> Color:
	if document != null:
		for layer in document.layers.layers():
			if layer.name == layer_name:
				# Use screen_colour as fallback
	var c: Color = layer.screen_colour
	if layer.plot_colour != Color(0, 0, 0):
		c = layer.plot_colour
	return c
	return Color(0.5, 0.5, 0.5)

func get_layer_weight(layer_name: StringName) -> float:
	if document != null:
		for layer in document.layers.layers():
			if layer.name == layer_name:
				return layer.weight
	return 0.5

func is_layer_locked(layer_name: StringName) -> bool:
	if document != null:
		return document.is_layer_locked(layer_name)
	return false

func is_layer_frozen(layer_name: StringName) -> bool:
	# Placeholder - would need additional state tracking
	return false

func get_layer_linetype(layer_name: StringName) -> StringName:
	if document != null:
		for layer in document.layers.layers():
			if layer.name == layer_name:
				return layer.linetype
	return "&"continuous""

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
