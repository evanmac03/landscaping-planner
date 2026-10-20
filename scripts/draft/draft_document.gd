class_name DraftDocument
extends RefCounted
## The drafting document: the one home for drafted linework.
##
## Placed assets keep their home in the scene graph; drafted geometry lives here.
## Nothing is duplicated, so the flat plan and the 3D view cannot disagree — both
## are projections of this store (docs/drafting-subsystem-spec.md §1, D1).
##
## Sibling modules are reached by preload and instances are made by path: the
## global class registry is rewritten by the editor's scan, so a class_name that
## has not been registered yet is not resolvable as a value, and .godot/ is
## gitignored so a fresh clone hits the same wall.

const EntityScript := preload("res://scripts/draft/draft_entity.gd")
const LayerSetScript := preload("res://scripts/draft/layer_set.gd")
const UnitsScript := preload("res://scripts/draft/units.gd")
const UndoScript := preload("res://scripts/draft/undo_stack.gd")
const DimensionStyleScript := preload("res://scripts/draft/dimension_style.gd")

signal changed()
signal entity_added(id: int)
signal entity_removed(id: int)

var layers: LayerSetScript
var units: UnitsScript
var undo: UndoScript
## The drawing's standard for how a dimension is drawn. A single dimension may
## override it, and the same rule covers the plan and the plotted sheet, so a
## practice's standard only has to be set once.
var dimension_style: DimensionStyleScript

## Where the site is, in degrees north. A latitude is a fact about the *site*, like the
## units are a fact about the practice, so it lives on the drawing rather than on the sun
## study or on the scene: a designer who works at one latitude sets it once and every
## shadow in every presentation agrees with the survey.
##
## The default is 45°N, the middle of the band these plans are drawn in — close enough to
## read as a northern hemisphere garden, far enough from any single city to be obviously
## a placeholder. A sun study is only worth anything once this number is the site's own
## (visualization spec §16).
const DEFAULT_SITE_LATITUDE := 45.0

var site_latitude: float = DEFAULT_SITE_LATITUDE

var _entities: Dictionary = {}
## Insertion order, which is the tie-break inside a layer's plotting band.
var _order: PackedInt32Array = PackedInt32Array()
var _next_id: int = 1


static func _new() -> DraftDocument:
	return (load("res://scripts/draft/draft_document.gd") as GDScript).new()


func _init() -> void:
	layers = LayerSetScript.default_set()
	units = UnitsScript.new()
	undo = UndoScript.new()
	dimension_style = DimensionStyleScript.architectural()


# --- entities -----------------------------------------------------------------------


## Add an entity, assigning it an id. An entity with no layer, or with a layer
## outside the preset set, lands on the default drafting layer rather than
## becoming invisible (REQ 5.1.1).
func add(entity: EntityScript, layer_name: StringName = &"") -> int:
	if layer_name != &"":
		entity.layer = layer_name
	if entity.layer == &"" or not layers.has(entity.layer):
		entity.layer = LayerSetScript.NEW_BED
	entity.id = _next_id
	_next_id += 1
	_entities[entity.id] = entity
	_order.append(entity.id)
	entity_added.emit(entity.id)
	changed.emit()
	return entity.id


func remove(id: int) -> bool:
	if not _entities.has(id):
		return false
	_entities.erase(id)
	var position := _order.find(id)
	if position >= 0:
		_order.remove_at(position)
	entity_removed.emit(id)
	changed.emit()
	return true


## Swap an entity's geometry, keeping its id and place in draw order.
func replace(id: int, entity: EntityScript) -> bool:
	if not _entities.has(id):
		return false
	entity.id = id
	_entities[id] = entity
	changed.emit()
	return true


func get_entity(id: int) -> EntityScript:
	return _entities.get(id, null)


func has(id: int) -> bool:
	return _entities.has(id)


func count() -> int:
	return _order.size()


func ids() -> PackedInt32Array:
	return _order.duplicate()


## Entities in draw order: by the layer's plotting band, then by insertion, so
## bigger things sit underneath (REQ 5.1.2).
func entities() -> Array[EntityScript]:
	var out: Array[EntityScript] = []
	if _order.is_empty():
		return out
	var rank: Dictionary = {}
	var index := 0
	for id in _order:
		var entity: EntityScript = _entities[id]
		rank[id] = layers.get_layer(entity.layer).sort_key() * 100000 + index
		index += 1
	for id in _order:
		out.append(_entities[id])
	var by_rank := func(a: EntityScript, b: EntityScript) -> bool: return rank[a.id] < rank[b.id]
	out.sort_custom(by_rank)
	return out


## Only what is on a visible layer. Drives every view at once, so a hidden layer
## is hidden in the plan, the 3D overhead and the ground view alike (REQ 5.2.3).
func visible_entities() -> Array[EntityScript]:
	var out: Array[EntityScript] = []
	for entity: EntityScript in entities():
		var layer: DraftLayer = layers.get_layer(entity.layer)
		if layer != null and layer.visible:
			out.append(entity)
	return out


## Only what is on a visible, plotting layer, in draw order. This is the plot set.
func plotting_entities() -> Array[EntityScript]:
	var out: Array[EntityScript] = []
	for entity: EntityScript in entities():
		var layer: DraftLayer = layers.get_layer(entity.layer)
		if layer != null and layer.visible and layer.plots:
			out.append(entity)
	return out


func entities_on_layer(layer_name: StringName) -> Array[EntityScript]:
	var out: Array[EntityScript] = []
	for entity: EntityScript in entities():
		if entity.layer == layer_name:
			out.append(entity)
	return out


func entities_of_kind(kind: int) -> Array[EntityScript]:
	var out: Array[EntityScript] = []
	for entity: EntityScript in entities():
		if entity.kind == kind:
			out.append(entity)
	return out


## Bounding box of all geometry, for fitting a view or a sheet.
func bounds() -> Rect2:
	var box := Rect2()
	var first := true
	for entity: EntityScript in _entities.values():
		var entity_box: Rect2 = entity.aabb()
		if entity_box.size == Vector2.ZERO:
			continue
		if first:
			box = entity_box
			first = false
		else:
			box = box.merge(entity_box)
	return box


## Clear the whole document, for loading over the top of one.
func clear() -> void:
	_entities.clear()
	_order = PackedInt32Array()
	_next_id = 1
	changed.emit()


# --- undo ---------------------------------------------------------------------------


## Record the state before a gesture. Call once per gesture, never per motion
## event, or the stack fills with intermediate states.
func begin_gesture() -> void:
	undo.push(snapshot())


func undo_last() -> bool:
	var previous := undo.undo(snapshot())
	if previous.is_empty():
		return false
	restore(previous)
	return true


func redo_last() -> bool:
	var following := undo.redo(snapshot())
	if following.is_empty():
		return false
	restore(following)
	return true


## A complete, independent copy of the document's state.
func snapshot() -> Dictionary:
	var saved: Dictionary = {}
	for id in _entities:
		saved[id] = (_entities[id] as EntityScript).to_dict()
	var order: Array = []
	for id in _order:
		order.append(id)
	return {
		"next_id": _next_id,
		"order": order,
		"entities": saved,
		"layers": layers.copy(),
		"units": units_snapshot(),
		"site_latitude": site_latitude,
		"dimension_style": dimension_style.to_dict(),
	}


func restore(state: Dictionary) -> void:
	_entities.clear()
	_order = PackedInt32Array()
	var saved: Dictionary = state.get("entities", {})
	for id in saved:
		_entities[int(id)] = EntityScript.from_dict(saved[id])
	for value in state.get("order", []):
		_order.append(int(value))
	_next_id = int(state.get("next_id", 1))

	var saved_layers = state.get("layers", null)
	# snapshot() stores a ready LayerSet; to_dict() stores plain layer records for
	# persistence, and from_dict() has already applied those. Only a LayerSet is
	# restored here, or a saved file would overwrite the set with an Array.
	if saved_layers is RefCounted:
		# Copy on restore, so later edits cannot reach into the stored snapshot.
		layers = saved_layers.copy()
	var units_state: Dictionary = state.get("units", {})
	@warning_ignore("int_as_enum_without_cast")
	units.system = int(units_state.get("system", UnitsScript.System.METRIC))
	@warning_ignore("int_as_enum_without_cast")
	units.length_style = int(units_state.get("length_style", UnitsScript.LengthStyle.DECIMAL))
	units.display_precision = int(units_state.get("display_precision", 3))
	units.inch_denominator = int(units_state.get("inch_denominator", 16))
	units.use_us_survey_foot = bool(units_state.get("use_us_survey_foot", false))
	# A latitude is a recent arrival, so a file written before it existed gets the default
	# rather than zero: zero is the equator, which is a site, and a wrong one.
	site_latitude = float(state.get("site_latitude", DEFAULT_SITE_LATITUDE))
	var style_state = state.get("dimension_style", null)
	# A file written before dimensions had styles carries none, and falls back to
	# the shipped standard rather than to something empty.
	if style_state is Dictionary:
		dimension_style = DimensionStyleScript.from_dict(style_state)
	changed.emit()


func units_snapshot() -> Dictionary:
	return {
		"system": units.system,
		"length_style": units.length_style,
		"display_precision": units.display_precision,
		"inch_denominator": units.inch_denominator,
		"use_us_survey_foot": units.use_us_survey_foot,
	}


# --- persistence --------------------------------------------------------------------


func to_dict() -> Dictionary:
	var saved: Dictionary = {}
	for id in _entities:
		saved[id] = (_entities[id] as EntityScript).to_dict()
	var layer_list: Array = []
	for layer in layers.layers():
		layer_list.append({
			"name": String(layer.name),
			"purpose": layer.purpose,
			"screen_colour": layer.screen_colour.to_html(),
			"plot_colour": layer.plot_colour.to_html(),
			"plot_weight_mm": layer.plot_weight_mm,
			"linetype": String(layer.linetype),
			"plots": layer.plots,
			"visible": layer.visible,
			"locked": layer.locked,
		})
	var order: Array = []
	for id in _order:
		order.append(id)
	return {
		"version": 3,
		"units": units_snapshot(),
		"site_latitude": site_latitude,
		"dimension_style": dimension_style.to_dict(),
		"layers": layer_list,
		"order": order,
		"entities": saved,
		"next_id": _next_id,
	}


static func from_dict(data: Dictionary) -> DraftDocument:
	var document := _new()
	for entry: Dictionary in data.get("layers", []):
		var layer_name := StringName(entry.get("name", ""))
		var layer: DraftLayer = document.layers.get_layer(layer_name)
		if layer == null:
			continue
		layer.purpose = String(entry.get("purpose", layer.purpose))
		layer.screen_colour = Color.html(String(entry.get("screen_colour", layer.screen_colour.to_html())))
		layer.plot_colour = Color.html(String(entry.get("plot_colour", layer.plot_colour.to_html())))
		layer.plot_weight_mm = float(entry.get("plot_weight_mm", layer.plot_weight_mm))
		layer.linetype = StringName(entry.get("linetype", String(layer.linetype)))
		layer.plots = bool(entry.get("plots", layer.plots))
		layer.visible = bool(entry.get("visible", layer.visible))
		layer.locked = bool(entry.get("locked", layer.locked))
	document.restore(data)
	return document