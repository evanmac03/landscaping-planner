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
const ZoneMapScript := preload("res://scripts/zone_map.gd")
const SheetSetScript := preload("res://scripts/draft/sheet_set.gd")

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

## What the ground is like where the design is going: light, moisture, soil, drainage, hardiness,
## as a base for the whole site plus any number of areas laid over it.
##
## It lives on the drawing because it is a fact about *this site*, the same way the latitude and the
## units are: a designer describes the ground once and every plant they place is checked against it,
## and it travels in the file with the design it belongs to. A separate environment document would
## be a second thing to keep in step with the plan.
##
## It also gives the undo stack the environment for free, because the stack stores whole snapshots of
## the document - so stating a zone is undoable exactly like moving a wall is.
var environment: ZoneMapScript

## The sheets this drawing is plotted as: the set of paper sizes, scales, drawing numbers, titles and
## revisions the drawing goes out on (see `DraftSheetSet`).
##
## It lives on the drawing for the same reason the ground and the dimension standard do: it is a fact
## about *this drawing* rather than about the application or the session, so it travels in the file
## with the design it belongs to and it comes back when the file is opened. It is also, as those are,
## part of the undo snapshot - setting up a sheet is a change to the drawing like any other.
##
## It is paper and not geometry: a sheet carries no entities, so nothing here can become a second copy
## of the linework.
var sheets: DraftSheetSet = SheetSetScript.new()

## What the drawing is watered by, as the irrigation module writes it: `{"zones": [...], "supply":
## {...}}`, with each zone's own record shape owned by `Irrigation`.
##
## It is held as the plain body rather than as a class of its own because a zone is arithmetic rather
## than an object with behaviour: `Irrigation` is static and does the sums, and the drawing only has
## to keep the records. It lives on the drawing for the reason the ground and the sheets do - a zone
## is a fact about *this* garden - and it is part of the undo snapshot, so watering a bed and taking
## it back is one step.
##
## An empty body is not "a supply of nothing": it is *nothing stated*, which is what the flow check
## refuses on, and what a file written before any of this existed gets.
var irrigation: Dictionary = {}

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

## The default longitude and zone offset, chosen to *agree* with the default latitude rather
## than to be neutral: 45°N 75°W on standard time is roughly Ottawa, so the defaults are a
## place somebody could stand rather than a coordinate in the Atlantic, and a sun study run
## on a new drawing is wrong only by its placeholder-ness and not by being nonsense.
const DEFAULT_SITE_LONGITUDE := -75.0

## Hours from UTC in force at the site. Daylight saving is folded into this number rather
## than inferred from a rule, because every rule is wrong somewhere: what a site's clock
## reads is a fact about the site, and the person who lives there knows it.
const DEFAULT_SITE_UTC_OFFSET_HOURS := -5.0

## Where the garden is. A latitude, a longitude and a zone offset travel together, because a
## sun study is a question about a place and any two of the three is not an answer to it
## (visualization spec §16). The same keys as `SunStudy.site()`, so this dictionary can be
## handed straight to the sun study - which a test does.
var site_latitude: float = DEFAULT_SITE_LATITUDE
var site_longitude: float = DEFAULT_SITE_LONGITUDE
var site_utc_offset_hours: float = DEFAULT_SITE_UTC_OFFSET_HOURS

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
	environment = ZoneMapScript.make()


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


# --- the ground ---------------------------------------------------------------------


## State what the ground is like, or replace what is stated.
##
## One act and one undo step, like `set_site`: describing the site is a change to the drawing, and a
## designer who states the wrong zone wants Ctrl+Z to put it back. Answers false when nothing
## changed, so a caller can tell "saved" from "already so".
func set_environment(map: ZoneMapScript) -> bool:
	if map == null or map.to_dict() == environment.to_dict():
		return false
	begin_gesture()
	environment = map
	changed.emit()
	return true


## Copy the site's conditions out from the entities already drawn: a building is shade, a hard
## surface is full sun and dry. See `ZoneMap.from_document`.
##
## The base survives - what somebody has stated about the whole site is not thrown away by asking the
## drawing what it knows - and the drawing's own zones are replaced, so a designer who edits a patio
## and asks again gets the new patio rather than two of them.
##
## **A zone stated by hand survives too**, and it is put *after* the ones read from the drawing, so it
## goes on answering for its area: a re-read is the software looking at the plan again, and the plan
## looking again must never overrule what a person said about the ground. See `ZoneMap.HAND_PREFIX`.
##
## Answers the number of zones read from the drawing, which is 0 for a drawing with no structure and
## no paving on it.
func read_environment_from_drawing() -> int:
	var derived: ZoneMapScript = ZoneMapScript.from_document(self, environment.base.to_dict())
	var read: int = derived.zones.size()
	for zone in environment.zones:
		if String(zone.source).begins_with(ZoneMapScript.HAND_PREFIX):
			derived.zones.append(zone)
	if read == 0 and environment.zones.is_empty():
		return 0
	set_environment(derived)
	return read


# --- the site -----------------------------------------------------------------------


## Where the garden is, in the shape the sun study takes.
func site() -> Dictionary:
	return {
		"latitude": site_latitude,
		"longitude": site_longitude,
		"utc_offset_hours": site_utc_offset_hours,
	}


## Move the site. One act and one undo step, the same promise a gesture makes: a site moved
## by a panel button is a change to the drawing like any other, and it reaches the screen
## through the ordinary `changed`.
##
## Returns false when the site is already there, so a caller can tell "saved" from "nothing
## to save" without comparing floats itself.
func set_site(new_latitude: float, new_longitude: float, new_utc_offset_hours: float) -> bool:
	if (
		is_equal_approx(new_latitude, site_latitude)
		and is_equal_approx(new_longitude, site_longitude)
		and is_equal_approx(new_utc_offset_hours, site_utc_offset_hours)
	):
		return false
	begin_gesture()
	site_latitude = new_latitude
	site_longitude = new_longitude
	site_utc_offset_hours = new_utc_offset_hours
	changed.emit()
	return true


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
		"site": site(),
		"dimension_style": dimension_style.to_dict(),
		"environment": environment.to_dict(),
		"sheets": sheets.to_dict(),
		"irrigation": irrigation.duplicate(true),
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
	# The site is a recent arrival, so a file written before it existed gets the defaults
	# rather than zeroes: zero latitude is the equator and zero longitude is Greenwich,
	# which are two sites, and both of them wrong. A version 3 file has the latitude but
	# not the rest, which is why the flat key is still read.
	var site_state: Dictionary = state.get("site", {})
	site_latitude = float(site_state.get("latitude", state.get("site_latitude", DEFAULT_SITE_LATITUDE)))
	site_longitude = float(site_state.get("longitude", DEFAULT_SITE_LONGITUDE))
	site_utc_offset_hours = float(site_state.get("utc_offset_hours", DEFAULT_SITE_UTC_OFFSET_HOURS))
	# What the ground is like is a recent arrival too, so a file written before it existed gets an
	# empty map - which is not "average ground" but "nothing stated", and a suitability check on it
	# says so rather than handing out verdicts about a garden it knows nothing about.
	var env_state: Variant = state.get("environment", null)
	environment = ZoneMapScript.from_dict(env_state if env_state is Dictionary else {})
	# The sheet set is the newest arrival: a file written before it existed gets one sheet at the
	# drawing's own size and scale, which is the sheet this app plotted before sets existed.
	sheets = SheetSetScript.from_dict(state.get("sheets", null))
	# What the drawing is watered by is the newest arrival, and a file written before it existed gets
	# no zones and no supply stated - which is a drawing nobody has worked the irrigation out for, and
	# not a garden with mysterious forty-litres-a-minute water in it.
	var irrigation_state: Variant = state.get("irrigation", null)
	irrigation = irrigation_state.duplicate(true) if irrigation_state is Dictionary else {}
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
	# Version 5 is the version that states what the ground is like. The number is written out rather
	# than inferred because a reader has to be able to tell "this file has no environment in it" from
	# "this file's environment is empty" - and 4 and 5 are the same drawing with a different answer to
	# that question.
	#
	# Version 6 states which sheets the drawing is plotted as, for the same reason: one sheet at the
	# drawing's own size is not the same answer as "this file was written before sets existed".
	#
	# Version 7 states what the drawing is watered by. A file with no irrigation in it is not a garden
	# with no water in it: it is a drawing nobody has worked the irrigation out for, and the flow
	# check says so rather than blessing a zone against a supply nobody stated.
	return {
		"version": 7,
		"units": units_snapshot(),
		"site": site(),
		"dimension_style": dimension_style.to_dict(),
		"environment": environment.to_dict(),
		"sheets": sheets.to_dict(),
		"irrigation": irrigation.duplicate(true),
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