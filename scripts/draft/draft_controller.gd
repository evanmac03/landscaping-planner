class_name DraftController
extends Node
## Owns the drafting document, the snap engine and the active tool, and turns
## screen-space picks into committed entities.
##
## Input stays in the ViewController, because it already owns the overhead mouse
## handling and knows which view you are in. This node holds the state and the
## decisions, and knows nothing about events.
##
## Drawing is deliberately armed rather than always on: while it is off the plan
## behaves exactly as it did before, so the plant drag-and-move in either view is
## untouched.

const DocumentScript := preload("res://scripts/draft/draft_document.gd")
const SnapScript := preload("res://scripts/draft/snap_engine.gd")
const ToolScript := preload("res://scripts/draft/draft_tool.gd")
const LayerSetScript := preload("res://scripts/draft/layer_set.gd")
const SheetExporterScript := preload("res://scripts/draft/sheet_exporter.gd")
const StoreScript := preload("res://scripts/draft/drawing_store.gd")
const PenStyleScript := preload("res://scripts/draft/plot_style_table.gd")
const DimensionStyleScript := preload("res://scripts/draft/dimension_style.gd")
const EditScript := preload("res://scripts/draft/draft_edit.gd")
const GeomScript := preload("res://scripts/draft/geom2d.gd")
const SurveyFileScript := preload("res://scripts/draft/survey_file.gd")
const EntityScript := preload("res://scripts/draft/draft_entity.gd")
const PlantLabelsScript := preload("res://scripts/plant_labels.gd")
const SelectScript := preload("res://scripts/draft/draft_select.gd")
const HatchFillScript := preload("res://scripts/draft/hatch_fill.gd")
const ZoneMapScript := preload("res://scripts/zone_map.gd")
const SheetSetScript := preload("res://scripts/draft/sheet_set.gd")
const PlotScaleScript := preload("res://scripts/draft/plot_scale.gd")
const RevisionLogScript := preload("res://scripts/draft/revision_log.gd")

## The smallest area a fill will offer a region at, in square metres: a sliver nobody
## meant to draw is not a region.
const HATCH_MIN_AREA := 0.1

## The "layer" a hand-drawn ground zone is keyed under: `by hand:zone#<n>`. `zone` is not
## a layer, which is exactly what tells a hand zone apart from an area of the plan.
const HAND_ZONE_TAG := "zone#"

## The editing commands: what can be done to geometry that is already on the
## drawing. Held apart from the drawing tools because a tool answers "make me a new
## shape" and an edit answers "change the shape I already have", and because a tool
## is one gesture while a trim is one gesture measured against everything else on
## the sheet.
enum EditKind {
	NONE,
	OFFSET,
	TRIM,
	EXTEND,
	FILLET,
	ERASE,
}

## The words each edit command is introduced by, so the status line, the menu and
## the palette cannot call the same command three different things.
const EDIT_LABELS: Dictionary = {
	EditKind.OFFSET: "Offset",
	EditKind.TRIM: "Trim",
	EditKind.EXTEND: "Extend",
	EditKind.FILLET: "Fillet",
	EditKind.ERASE: "Erase",
}

## How near the cursor has to come to a shape, in screen pixels, before a pick
## finds it. An aperture rather than exact contact, because picking linework by
## exact contact is a game of pixel hunting.
const PICK_PIXELS := 8.0

## A pick aperture in model metres for the case where there is no canvas to read a
## scale off - only reachable off-scene, in a test.
const DEFAULT_PICK_METRES := 0.2

## The first fillet a drawing gets, in model metres. A property of the command in
## hand rather than of any one corner, exactly as it is in a CAD package.
const DEFAULT_FILLET_RADIUS := 1.0

## Whether a layer holds annotations rather than site features. An edit neither
## picks an annotation nor measures against one: trimming a line against the
## dimension that describes it would be a drawing editing itself.
static func is_annotation_layer(layer_name: StringName) -> bool:
	return layer_name == LayerSetScript.DIMENSION \
		or layer_name == LayerSetScript.TEXT \
		or layer_name == LayerSetScript.CALLOUT

@export var plan_canvas_path: NodePath = ^"../PlanLayer/PlanCanvas"
## The 3D linework overlay, when the scene has one. Optional: drawing works
## without it, the linework is simply not visible in the 3D views.
@export var overlay_path: NodePath = ^"../DraftOverlay"

## True while the tools own the left mouse button.
var drawing: bool = false

var document: DraftDocument = null:
	set(value):
		document = value
		# The paper fields - the sheet, the scale, the drawing number, the revision, the title - belong to
		# the sheet in hand, so binding a document adopts its current sheet right here. Adopting later,
		# the first time something reaches for the set, would mean a caller that set a field *first* had it
		# silently overwritten by the adoption it did not know was coming.
		_adopt_current_sheet()
var snap
var tool
var canvas: Node2D = null
var overlay: Node = null

## Which layer ordinary geometry is drawn on. Held apart from the tool's own
## layer because annotating is not drawing: a dimension always goes on the
## dimension layer, and that choice must not leave the next line stranded there.
var drawing_layer: StringName = LayerSetScript.NEW_HARDSCAPE

## The sheet the drawing plots to: a property of the drawing rather than of a
## tool, so it lives here beside the document.
var sheet: String = "A3"
var plot_scale: float = 100.0
var pen_table = null
## The current sheet's *drawing number*, revision and whether it is portrait. Beside the sheet and the
## scale because they are the same kind of thing: the current sheet of the set, as the rest of the app
## reads it. The set itself (every sheet, in order) is on the document, because it travels in the file
## with the drawing.
var sheet_number: String = ""
var revision: String = ""
var portrait: bool = false
## The date the set is drawn with, as it goes on every title block. Empty means "today", which is what
## the plotter writes when a drawing has never been dated - a date is a fact somebody types once for a
## whole set, not once per sheet.
var sheet_date: String = ""
## What goes in the title block, and whether the layer key is drawn with it. The
## sheet is a deliverable, so its wording is a property of the drawing too.
var project_name: String = "Backyard Design"
var drawing_title: String = "Landscaping Plan"
var show_legend: bool = true
## Which shipped dimension standard the drawing is using, so a key can step to the
## next one.
var dimension_style_name: StringName = &"architectural"
## Where the last plot was written, so the result can be reported.
var plot_path: String = ""
## Where this drawing lives on disk, or "" when it has never been saved. Held here rather than
## in the HUD because it is a property of the drawing and not of the furniture: a drawing that
## has a file knows where its next Save goes.
var drawing_path: String = ""
## The named revisions of this drawing: a history you keep, kept beside the drawing rather than in it.
##
## Not in the document, because a revision *is* the document: a log stored inside the drawing would be
## a snapshot of a state that contains the snapshot of the state before it, growing without bound. It
## lives in `user://revisions/<name>.json`, and it is loaded when a drawing is opened and written when
## a revision is recorded.
var revisions: DraftRevisionLog = RevisionLogScript.new()
## Whether the drawing has changed since it was last written or read. What decides whether Save
## has anything to do, and whether New or Open would throw work away.
var dirty: bool = false

var cursor_point: Vector2 = Vector2.ZERO
var cursor_snapped: bool = false
var last_message: String = ""

## The editing command in hand, if any. Held apart from the drawing tool because
## an edit picks whole entities rather than points.
var edit_kind: EditKind = EditKind.NONE
## The radius a fillet rounds a corner with, in model metres.
var fillet_radius: float = DEFAULT_FILLET_RADIUS

var _edit_picked: Array = []
var _edit_points: Array[Vector2] = []

## Whether a selection band catches only what is wholly inside it (window) or
## anything it touches (crossing).
var select_mode: StringName = SelectScript.MODE_WINDOW
## The corners of the band being dragged out. Held here rather than in the drawing
## tool because a selection is measured against the *document* rather than being a
## shape in it: the tool that owns it, `Tool.Kind.SELECT`, takes no points at all.
var _select_points: Array[Vector2] = []
## The ids of the shapes a band last caught, in document order.
var _selected: Array[int] = []
## Whether the next closed shape drawn becomes a **ground zone** rather than geometry: a zone whose
## outline is drawn by hand has no entity behind it, so the outline *is* the zone and nothing is added
## to the drawing.
var zone_hand: bool = false

var _last_snap: Dictionary = {}

signal changed()


func _ready() -> void:
	document = DocumentScript.new()
	snap = SnapScript.new()
	tool = ToolScript.new()
	tool.begin(ToolScript.Kind.LINE, drawing_layer)
	pen_table = PenStyleScript.default_table()
	snap.bind(document.entities())
	document.changed.connect(_on_document_changed)
	var node := get_node_or_null(plan_canvas_path)
	if node is Node2D:
		canvas = node
		canvas.bind_document(document)
	var overlay_node := get_node_or_null(overlay_path)
	if overlay_node != null:
		overlay = overlay_node
		overlay.bind_document(document)
	_refresh_canvas()


# --- tool and layer ------------------------------------------------------------------


func set_tool(kind: ToolScript.Kind) -> void:
	# Keep whatever is on the drawing surface: switching tools mid-shape throws
	# away half a shape, which is never what was meant.
	clear_edit()
	# A selection belongs to the tool that made it, so putting the select tool away
	# puts the selection away too: a highlight on the screen that no command can act
	# on is a lie about what is in hand.
	clear_selection()
	# A ground zone is drawn with the polygon tool for one purpose; choosing another tool, or putting
	# the tools away, drops the purpose with the tool rather than leaving a click meaning two things.
	zone_hand = false
	tool.begin(kind, _layer_for(kind))
	snap.clear_lock()
	_last_snap = {}
	last_message = ""
	_refresh_canvas()


## Which layer a tool draws on.
##
## A dimension is an annotation rather than a site feature, so it goes on the
## dimension layer whatever was being drawn. Burying measurements among the
## hardscape is the exact mistake that layer exists to prevent, and it would
## plot them at the hardscape's weight as well as counting them in its row of
## the key.
func _layer_for(kind: ToolScript.Kind) -> StringName:
	if ToolScript.is_dimension(kind):
		return LayerSetScript.DIMENSION
	return drawing_layer


func set_layer(layer_name: StringName) -> void:
	if not document.layers.has(layer_name):
		return
	drawing_layer = layer_name
	# Reported from the tool rather than from the argument, so the line says what
	# will actually happen: selecting a layer while annotating cannot move the
	# dimension off the dimension layer.
	tool.layer = _layer_for(tool.kind)
	last_message = "drawing on %s" % String(tool.layer)
	_refresh_canvas()


func toggle_drawing() -> void:
	set_drawing(not drawing)


## Arm the tools, or put them away.
##
## Explicit rather than only a toggle, so that a button which says what it does and
## a key which toggles can both be truthful about the same state.
func set_drawing(on: bool) -> void:
	if drawing == on:
		return
	drawing = on
	if not drawing:
		clear_edit()
		cancel()
		clear_selection()
		# Putting the tools away drops the zone purpose with them, like another tool.
		zone_hand = false
	last_message = "drawing on" if drawing else ""
	_refresh_canvas()


## Pick a tool and start drawing with it, which is what one press of a palette
## button should do: choosing a tool and arming the tools separately is two presses
## for one intention.
func arm(kind: ToolScript.Kind) -> void:
	set_tool(kind)
	set_drawing(true)


# --- editing what is already drawn ----------------------------------------------------


## Take an editing command. Armed like a tool: it puts the drawing tools away so a
## click cannot mean two things, and it stays in hand until another command is
## chosen, so a run of trims is a run of clicks rather than a run of key presses.
func arm_edit(kind: EditKind) -> void:
	edit_kind = kind
	_edit_picked = []
	_edit_points = []
	tool.cancel()
	snap.clear_lock()
	_last_snap = {}
	last_message = ""
	drawing = kind != EditKind.NONE
	_refresh_canvas()


## Put the editing command away without disturbing what is being drawn.
func clear_edit() -> void:
	edit_kind = EditKind.NONE
	_edit_picked = []
	_edit_points = []


func current_edit() -> EditKind:
	return edit_kind


func is_editing() -> bool:
	return edit_kind != EditKind.NONE


## The radius a fillet will round the next corner with, in model metres. Refused
## rather than clamped for a value that is not a radius.
func set_fillet_radius(metres: float) -> bool:
	if metres <= 0.0 or is_nan(metres):
		last_message = "a fillet radius has to be a positive length"
		_refresh_canvas()
		return false
	fillet_radius = metres
	_refresh_canvas()
	return true


## The wording one edit command is introduced by.
static func edit_label(kind: EditKind) -> String:
	return String(EDIT_LABELS.get(kind, "Edit"))


# --- what a palette needs to know -----------------------------------------------------


func current_tool() -> ToolScript.Kind:
	return tool.kind


func current_layer() -> StringName:
	return tool.layer


## Every layer the document offers, in draw order, as name-and-purpose pairs.
##
## Both halves are needed: "300-NEW-HARD" is a code, "New paving, walls, steps" is
## a choice somebody can make. The list comes from the document rather than from the
## preset table, so a document that has added or removed a layer is described as it
## actually is.
func layer_choices() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for layer in document.layers.layers():
		out.append({"name": layer.name, "purpose": layer.purpose})
	return out


func entity_count() -> int:
	return document.count()


func status() -> String:
	if not drawing:
		# Plotting works whether or not a tool is armed, so its result - and the
		# key that triggers it - belong on screen outside drawing mode too.
		# The key that arms the tools is advertised here because this is where every
		# other key the drawing needs is advertised, and it is the one key a user
		# cannot discover by accident. The rest of the legend appears once armed.
		var idle := "P plots a sheet at 1:%d on %s   D: drawing tools" % [
			int(plot_scale), sheet
		]
		return "%s   %s" % [idle, last_message] if last_message != "" else idle
	if is_editing():
		return _edit_status()
	if tool.kind == ToolScript.Kind.SELECT:
		return _select_status()
	var text := "%s  ·  %s  ·  %s" % [
		ToolScript.label_for(tool.kind), String(tool.layer), tool.status()
	]
	if last_message != "":
		text += "  ·  " + last_message
	return text


## What an editing command says while it is in hand. Its own prompt is the half
## that changes as picks land, so an edit cannot be left half-made without the line
## saying which pick it is waiting for.
func _edit_status() -> String:
	var hint := ""
	match edit_kind:
		EditKind.OFFSET:
			hint = "pick the shape to offset" if _edit_picked.is_empty() \
				else "click the side and distance to offset to"
		EditKind.TRIM:
			hint = "pick the piece to cut away"
		EditKind.EXTEND:
			hint = "pick the end to grow"
		EditKind.FILLET:
			hint = "pick the first line" if _edit_picked.is_empty() else "pick the second line"
		EditKind.ERASE:
			hint = "pick what to erase"
	var text := "%s  ·  %s" % [edit_label(edit_kind), hint]
	if edit_kind == EditKind.FILLET:
		text += "  ·  radius %s" % document.units.format_length(fillet_radius)
	if last_message != "":
		text += "  ·  " + last_message
	return text


# --- picks --------------------------------------------------------------------------


## Follow the cursor: snap it, and refresh the ghost of the shape in progress.
func hover(screen: Vector2) -> Dictionary:
	if canvas == null:
		return {}
	var previous := Vector2.ZERO
	var has_previous: bool = tool.point_count() > 0
	if has_previous:
		# The last picked point, which is what perpendicular and tangent are
		# measured from, and what ortho and polar track from.
		previous = Vector2(tool.points()[tool.point_count() - 1])
	var result: Dictionary = snap.resolve(
		canvas.screen_to_world(screen), canvas.pixels_per_metre, previous, has_previous
	)
	cursor_point = result["point"]
	cursor_snapped = result["snapped"]
	_refresh_canvas()
	return result


func click(screen: Vector2) -> Dictionary:
	if canvas == null:
		return {}
	if is_editing():
		return _edit_click(screen)
	if tool.kind == ToolScript.Kind.SELECT:
		return _select_click(screen)
	# Snap first, so the point that is committed is the one the marker showed.
	hover(screen)
	var pick: Dictionary = tool.click(cursor_point)
	if pick.get("committed", false):
		_commit(pick)
	_refresh_canvas()
	return pick


func finish() -> Dictionary:
	var pick: Dictionary = tool.finish()
	if pick.get("committed", false):
		_commit(pick)
	_refresh_canvas()
	return pick


func finish_closed() -> Dictionary:
	var pick: Dictionary = tool.finish_closed()
	if pick.get("committed", false):
		_commit(pick)
	_refresh_canvas()
	return pick


func undo_point() -> bool:
	var dropped: bool = tool.undo_point()
	_refresh_canvas()
	return dropped


func cancel() -> void:
	tool.cancel()
	# Escape backs out of a half-made edit - the first line of a fillet, the shape
	# picked to offset - without putting the command itself away.
	_edit_picked = []
	_edit_points = []
	# Escape also drops a half-made selection band, for the same reason: it is half
	# of a gesture nobody has finished.
	_select_points = []
	snap.clear_lock()
	_last_snap = {}
	_refresh_canvas()


func undo() -> bool:
	var done: bool = document.undo_last()
	last_message = "undo" if done else "nothing to undo"
	return done


func redo() -> bool:
	var done: bool = document.redo_last()
	last_message = "redo" if done else "nothing to redo"
	return done


func _commit(pick: Dictionary) -> void:
	var entity = pick["entity"]
	if entity != null:
		# A ring drawn to state a ground zone is not geometry: nothing goes on the drawing, and the
		# map takes the outline itself.
		if zone_hand and entity.kind == EntityScript.Kind.POLYGON:
			state_ground_zone(entity.outline())
			return
		# One snapshot per committed shape, so a single undo removes a whole
		# entity rather than un-picking a point.
		document.begin_gesture()
		document.add(entity, tool.layer)
		last_message = "%s added" % ToolScript.label_for(tool.kind)
		return
	var measure: Dictionary = pick["measure"]
	if measure != null:
		last_message = "%s at %s" % [
			document.units.format_length(measure["distance"]),
			document.units.format_length(measure["delta"].length()),
		]


# --- selecting what is already drawn --------------------------------------------------


## Take a selection mode, arming the select tool with it.
##
## A mode is not a command that does something and ends; it is a standing
## preference, like the drawing layer, so choosing one leaves the band in hand and
## a designer can sweep twice in a row without re-choosing.
func set_select_mode(mode: StringName) -> bool:
	if not SelectScript.is_mode(mode):
		return false
	select_mode = mode
	return true


func selection_mode() -> StringName:
	return select_mode


## Take the select tool in a mode, which is what choosing a mode means: the mode is
## not worth setting if the band is not in hand, and the band is not in hand if a
## trim is still waiting for a pick.
func arm_select(mode: StringName) -> bool:
	if not set_select_mode(mode):
		return false
	clear_edit()
	arm(ToolScript.Kind.SELECT)
	return true


func selection_mode_name() -> String:
	return SelectScript.mode_name(select_mode)


## The ids a band last caught. A copy, so a caller cannot edit the selection behind
## the controller's back.
func selection() -> Array[int]:
	return _selected.duplicate()


func selected_count() -> int:
	return _selected.size()


func is_selected(id: int) -> bool:
	return _selected.has(id)


## The selected shapes themselves, skipping any that have since been taken off the
## drawing - a selection outlives the geometry it named.
func selected_entities() -> Array[EntityScript]:
	var out: Array[EntityScript] = []
	if document == null:
		return out
	for id: int in _selected:
		var entity: EntityScript = document.get_entity(id)
		if entity != null:
			out.append(entity)
	return out


func selection_bounds() -> Rect2:
	var chosen := selected_entities()
	if chosen.is_empty():
		return Rect2()
	var rect := Rect2(chosen[0].point(0), Vector2.ZERO)
	for entity: EntityScript in chosen:
		for point: Vector2 in entity.outline(SelectScript.TOLERANCE):
			rect = rect.expand(point)
	return rect


func clear_selection() -> void:
	_select_points = []
	_selected = []
	_refresh_canvas()


## Take everything on a visible layer. The nearest thing to "select all" that means
## anything on a drawing with hidden layers: what is hidden is not on the sheet.
func select_all() -> int:
	_selected = []
	if document != null:
		for entity: EntityScript in document.visible_entities():
			_selected.append(int(entity.id))
	_select_points = []
	last_message = SelectScript.describe(_selected.size(), select_mode)
	_refresh_canvas()
	return _selected.size()


## A click while the select tool is out. The first pick anchors the band, the
## second completes it - the same two-pick gesture the rectangle tool uses, so there
## is nothing new to learn and no new key to bind.
func _select_click(screen: Vector2) -> Dictionary:
	if canvas == null:
		return {}
	select_at(canvas.screen_to_world(screen))
	_refresh_canvas()
	return {}


## The same, in model coordinates: the canvas-free entry point, so the whole rule is
## testable without a scale to read.
func select_at(world: Vector2) -> Dictionary:
	if _select_points.is_empty():
		_select_points.append(world)
		last_message = ""
		return {"ok": false, "progress": 1, "reason": ""}
	var first: Vector2 = _select_points[0]
	var reason := SelectScript.band_reason(first, world)
	if reason != "":
		# The bad corner is given back, so the band stays where the person thinks it
		# is and the next click can still finish it - the same courtesy the drawing
		# tools extend to a degenerate pick.
		last_message = reason
		return {"ok": false, "progress": 1, "reason": reason}
	var caught: Dictionary = SelectScript.pick_between(
		document.visible_entities() if document != null else [], first, world, select_mode
	)
	_selected = []
	for id in caught["ids"]:
		_selected.append(int(id))
	_select_points = []
	last_message = SelectScript.describe(_selected.size(), select_mode)
	return {"ok": true, "progress": 0, "ids": selection(), "reason": ""}


## What the select tool says while it is out: which way round the band catches
## things, what the next pick is for, and what is selected.
func _select_status() -> String:
	var hint := "pick the first corner" if _select_points.is_empty() else "pick the opposite corner"
	var text := "%s selection  ·  %s" % [SelectScript.mode_name(select_mode), hint]
	if not _selected.is_empty():
		text += "  ·  %d selected" % _selected.size()
	if last_message != "":
		text += "  ·  " + last_message
	return text


# --- drawing a ground zone by hand ----------------------------------------------------


## Take the polygon tool, meaning the next closed shape drawn will be a **ground zone**.
##
## A hand zone is for ground nothing on the plan outlines: a wet corner, a frost pocket, a strip of
## shade. There is therefore no entity to key it to - the outline the designer draws *is* the zone -
## so nothing is added to the drawing and the map holds the ring itself. The polygon tool is the
## gesture because closing a ring is what it already does, so there is nothing new to learn.
func begin_ground_zone() -> void:
	arm(ToolScript.Kind.POLYLINE)
	zone_hand = true
	last_message = ""


func ground_zone_pending() -> bool:
	return zone_hand


## The number the next hand zone takes, from the zones already in the map.
func _next_hand_zone_number() -> int:
	var most := 0
	if document != null and document.environment != null:
		var prefix := ZoneMapScript.HAND_PREFIX + HAND_ZONE_TAG
		for zone in document.environment.zones:
			var source := String(zone.source)
			if source.begins_with(prefix):
				most = maxi(most, String(source.get_slice("#", 1)).to_int())
	return most + 1


## State a ground zone over a ring the designer drew. One gesture, so Ctrl+Z takes the zone off the
## map (the map travels in the document - docs/plant-database-spec.md §7a).
func state_ground_zone(outline: PackedVector2Array) -> Dictionary:
	if document == null or document.environment == null:
		last_message = "there is no ground to state a zone on"
		_refresh_canvas()
		return {"ok": false, "reason": last_message}
	if outline.size() < 3:
		last_message = "a ground zone needs an outline that encloses something"
		_refresh_canvas()
		return {"ok": false, "reason": last_message}
	var number := _next_hand_zone_number()
	document.begin_gesture()
	document.environment.add_zone(
		"ground zone %d" % number, outline, null,
		"%s%d" % [ZoneMapScript.HAND_PREFIX + HAND_ZONE_TAG, number]
	)
	zone_hand = false
	dirty = true
	last_message = "stated ground zone %d where you drew it" % number
	_refresh_canvas()
	return {"ok": true, "reason": "", "number": number, "message": last_message}


# --- filling a region with a pattern --------------------------------------------------


## The closed regions of the drawing a fill can cover, in draw order.
##
## The list is `ZoneMap.areas_of`'s - the same areas the ground window states conditions for and a
## bed is filled with plants in - so a bed is named the same way wherever it is offered. The caller
## re-reads it before filling, because a bed is drawn, moved and deleted while the plan is made.
func hatch_regions() -> Array[Dictionary]:
	if document == null:
		return []
	return ZoneMapScript.areas_of(document, HATCH_MIN_AREA)


## Fill one closed region with a pattern, writing the pattern's linework as lines on the hatch
## layer.
##
## `options` carries `pattern`, `spacing_mm`, `angle_deg` and `symbol`, the same four things the
## panel offers. The paper spacing is turned into a model one here, because the drawing is in metres
## and the person chose millimetres (see `HatchFill`). The whole fill is one gesture: hatching a bed
## is one act, and Ctrl+Z takes the whole pattern back off rather than one line of it.
func fill_region(rings: Array, options: Dictionary) -> Dictionary:
	if document == null:
		return {"ok": false, "reason": "there is no drawing to fill"}
	var pattern := StringName(options.get("pattern", HatchFillScript.HATCH))
	var symbol := StringName(options.get("symbol", HatchFillScript.SYMBOL_DOT))
	if not HatchFillScript.is_pattern(pattern):
		last_message = "there is no such fill pattern"
		_refresh_canvas()
		return {"ok": false, "reason": last_message}
	if not HatchFillScript.is_symbol(symbol):
		symbol = HatchFillScript.SYMBOL_DOT
	# A solid fill has no spacing of its own to choose: its density is fixed on paper.
	var spacing_m: float = HatchFillScript.solid_spacing_m(plot_scale) \
		if pattern == HatchFillScript.SOLID \
		else HatchFillScript.model_spacing_m(float(options.get("spacing_mm", 2.0)), plot_scale)
	var angle := deg_to_rad(float(options.get("angle_deg", 45.0)))
	var worked: Dictionary = HatchFillScript.fill(rings, pattern, spacing_m, angle, symbol)
	if not bool(worked.get("ok", false)):
		last_message = String(worked.get("reason", "the fill could not be made"))
		_refresh_canvas()
		return {"ok": false, "reason": last_message}
	var lines: Array = worked.get("lines", [])
	document.begin_gesture()
	var added := 0
	for stroke: PackedVector2Array in lines:
		if stroke.size() < 2:
			continue
		document.add(
			EntityScript.make_line(stroke[0], stroke[stroke.size() - 1]), LayerSetScript.HATCH
		)
		added += 1
	snap.bind(document.entities())
	dirty = true
	last_message = "filled the region: %s" % HatchFillScript.describe(worked)
	_refresh_canvas()
	return {"ok": true, "reason": "", "count": added, "message": last_message}


## Fill a region named by the id of the closed shape that encloses it. The outline is read from the
## drawing again here, so a bed moved since the list was built fills where it is now.
func fill_entity(entity_id: int, options: Dictionary) -> Dictionary:
	if document == null:
		return {"ok": false, "reason": "there is no drawing to fill"}
	var entity: EntityScript = document.get_entity(entity_id)
	if entity == null:
		last_message = "that region is not on the drawing any more"
		_refresh_canvas()
		return {"ok": false, "reason": last_message}
	var ring: PackedVector2Array = entity.outline()
	if ring.size() < 3:
		last_message = "that shape does not enclose an area"
		_refresh_canvas()
		return {"ok": false, "reason": last_message}
	return fill_region([ring], options)


# --- the editing commands -------------------------------------------------------------


## A click while an editing command is in hand. The command is a small state
## machine of its own - some take one pick, some take two - so its picks live here
## rather than in the drawing tool, which is a machine over points.
func _edit_click(screen: Vector2) -> Dictionary:
	edit_at(canvas.screen_to_world(screen))
	_refresh_canvas()
	return {}


## The same, in model coordinates. Split out so an editing command can be driven
## without a canvas to read a scale off - which is how it is tested, and how a
## script or a future command line could reach it.
func edit_at(world: Vector2) -> void:
	match edit_kind:
		EditKind.OFFSET:
			_edit_offset(world)
		EditKind.TRIM:
			_edit_trim(world)
		EditKind.EXTEND:
			_edit_extend(world)
		EditKind.FILLET:
			_edit_fillet(world)
		EditKind.ERASE:
			_edit_erase(world)


## Trim: cut the picked piece of a line out against every other editable shape.
func _edit_trim(world: Vector2) -> void:
	var target = _pick_world(world)
	if target == null:
		last_message = "nothing there to trim"
		return
	var result: Dictionary = EditScript.trim(target, world, _others(target))
	if not bool(result["ok"]):
		last_message = String(result["reason"])
		return
	var layer: StringName = target.layer
	var pieces: Array = result["entities"]
	document.begin_gesture()
	document.remove(target.id)
	for piece in pieces:
		document.add(piece, layer)
	var count := pieces.size()
	last_message = "trimmed to %d line%s" % [count, "" if count == 1 else "s"]


## Extend: grow the picked end of a line out to the nearest shape beyond it.
func _edit_extend(world: Vector2) -> void:
	var target = _pick_world(world)
	if target == null:
		last_message = "nothing there to extend"
		return
	var result: Dictionary = EditScript.extend(target, world, _others(target))
	if not bool(result["ok"]):
		last_message = String(result["reason"])
		return
	var layer: StringName = target.layer
	document.begin_gesture()
	document.remove(target.id)
	for piece in result["entities"]:
		document.add(piece, layer)
	last_message = "extended"


## Erase: take the picked shape off the drawing.
func _edit_erase(world: Vector2) -> void:
	var target = _pick_world(world)
	if target == null:
		last_message = "nothing there to erase"
		return
	document.begin_gesture()
	document.remove(target.id)
	last_message = "erased"


## Offset: pick a shape, then the side and distance. The offset is a new shape; the
## one it came from stays, which is what makes offset a drawing aid rather than an
## edit to one outline.
func _edit_offset(world: Vector2) -> void:
	if _edit_picked.is_empty():
		var target = _pick_world(world)
		if target == null:
			last_message = "nothing there to offset"
			return
		_edit_picked = [target]
		last_message = "click the side and distance to offset to"
		return
	var source = _edit_picked[0]
	var distance: float = EditScript.offset_sign(source, world) * _distance_to(source, world)
	var result: Dictionary = EditScript.offset(source, distance)
	_edit_picked = []
	if not bool(result["ok"]):
		last_message = String(result["reason"])
		return
	var produced: Array = result["entities"]
	if produced.is_empty():
		last_message = "that offset leaves nothing"
		return
	document.begin_gesture()
	for piece in produced:
		document.add(piece, source.layer)
	last_message = "offset by %s" % document.units.format_length(absf(distance))


## Fillet: pick two lines, round the corner between the halves that were picked.
func _edit_fillet(world: Vector2) -> void:
	if _edit_picked.is_empty():
		var chosen = _pick_world(world)
		if chosen == null:
			last_message = "nothing there to round"
			return
		_edit_picked = [chosen]
		_edit_points = [world]
		last_message = "pick the second line"
		return
	var first = _edit_picked[0]
	var pick_a: Vector2 = _edit_points[0]
	_edit_picked = []
	_edit_points = []
	var second = _pick_world(world)
	if second == null:
		last_message = "nothing there to round"
		return
	if second.id == first.id:
		last_message = "pick a second, different line"
		return
	var result: Dictionary = EditScript.fillet(first, second, fillet_radius, pick_a, world)
	if not bool(result["ok"]):
		last_message = String(result["reason"])
		return
	var layer: StringName = first.layer
	document.begin_gesture()
	document.remove(first.id)
	document.remove(second.id)
	for piece in result["lines"]:
		document.add(piece, layer)
	document.add(result["arc"], layer)
	last_message = "rounded the corner at %s" % document.units.format_length(fillet_radius)


## The shape under a model point, or null. Only editable, visible geometry is
## considered, so a pick cannot find an annotation or something switched off.
func _pick_world(world: Vector2):
	var aperture := DEFAULT_PICK_METRES
	if canvas != null:
		aperture = PICK_PIXELS / maxf(canvas.pixels_per_metre, 1e-9)
	var best = null
	var best_distance := aperture
	for entity in document.visible_entities():
		if is_annotation_layer(entity.layer):
			continue
		var distance := _distance_to(entity, world)
		if distance <= best_distance:
			best_distance = distance
			best = entity
	return best


## Every editable shape other than the one being edited, which is what a trim cuts
## against and an extend runs into.
func _others(target) -> Array:
	var out: Array = []
	for entity in document.visible_entities():
		if entity.id == target.id or is_annotation_layer(entity.layer):
			continue
		out.append(entity)
	return out


## How far a model point is from an entity's linework. Its outline sampled to
## segments, so a curve is measured against chords fine enough to be exact.
func _distance_to(entity, world: Vector2) -> float:
	var outline: PackedVector2Array = entity.outline()
	var count := outline.size()
	if count == 0:
		return INF
	if count == 1:
		return world.distance_to(outline[0])
	var best := INF
	var segments := count if entity.is_closed() else count - 1
	for index in segments:
		var distance := GeomScript.distance_to_segment(world, outline[index], outline[(index + 1) % count])
		if distance < best:
			best = distance
	return best


# --- the drawing's standards --------------------------------------------------------


## The shipped dimension standards, in the order a key or a button steps through
## them.
const DIMENSION_STYLES: Array[StringName] = [&"architectural", &"engineering", &"minimal"]


## Set the document's dimension standard by name, so a caller or a panel can
## switch between the shipped ones without knowing their shape. Returns false, and
## says so in the status line, for a name that is not one of them.
func set_dimension_style(preset: StringName) -> bool:
	match preset:
		&"architectural":
			document.dimension_style = DimensionStyleScript.architectural()
		&"engineering":
			document.dimension_style = DimensionStyleScript.engineering()
		&"minimal":
			document.dimension_style = DimensionStyleScript.minimal()
		_:
			last_message = "no dimension style called %s" % preset
			_refresh_canvas()
			return false
	dimension_style_name = preset
	last_message = document.dimension_style.describe()
	# The plan and the overlay both listen to the document, so telling them once
	# is enough.
	document.changed.emit()
	_refresh_canvas()
	return true


## Step to the next shipped dimension standard, which is what a key or a button
## does.
func cycle_dimension_style() -> StringName:
	var index := DIMENSION_STYLES.find(dimension_style_name)
	var next: StringName = DIMENSION_STYLES[(index + 1) % DIMENSION_STYLES.size()]
	set_dimension_style(next)
	return next


# --- plotting -----------------------------------------------------------------------


## Plot the drawing to a PDF sheet at its exact scale. Returns the absolute path,
## or an empty string when there was nothing to plot or the file could not be
## written.
##
## `schedule` is the planting list the sheet carries, in the rows `PlantPlacement.schedule()`
## returns. It is handed in rather than read off here, because the drafting controller has no
## yard and no catalogue: the planting schedule is the one part of a sheet that comes from the
## garden rather than from the drawing, and it is passed the way the pen table is.
##
## `options_override` is the sheet of the *set* being plotted, when a caller has one: its paper, scale,
## number, title and revision lay over this drawing's own. It is an argument rather than a state change
## because plotting the set must not leave the drawing set up as whatever sheet happened to be last.
func plot(schedule: Array = [], options_override: Dictionary = {}) -> String:
	if document.count() == 0:
		last_message = "nothing to plot"
		_refresh_canvas()
		return ""
	# The set is the truth for a sheet's own fields, so the live ones are written back before they are
	# used: a size chosen from the File menu and a size typed in the sheet window then end up in one
	# place rather than in whichever of the two the last code path happened to consult.
	save_sheet()
	var options := {
		"sheet": sheet,
		"scale": plot_scale,
		"pen_table": pen_table,
		"project": project_name,
		"drawing": drawing_title,
		"legend": show_legend,
		"schedule": schedule,
		"number": sheet_number,
		"revision": revision,
		"portrait": portrait,
	}
	# The date is only passed when it has been stated: an empty one is the absence of an instruction, and
	# the plotter's own default - today - is what should stand.
	if not sheet_date.strip_edges().is_empty():
		options["date"] = sheet_date
	options.merge(options_override, true)
	var bytes: PackedByteArray = SheetExporterScript.export_pdf(document, options)
	# A timestamped name, so plotting twice does not silently replace the first
	# sheet a client has already been sent. A sheet of a set also carries its own
	# number, which is the name a person looks for: two sheets of one set plotted in
	# one minute are otherwise the same file name to the second.
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-")
	var tag: String = StoreScript.sanitise(String(options.get("number", "")).strip_edges())
	var stem := "plot-%s-%s" % [tag, stamp] if not tag.is_empty() else "plot-%s" % stamp
	var path := "user://sheets/%s.pdf" % stem
	var directory := DirAccess.open("user://")
	if directory == null or (not directory.dir_exists("sheets") and directory.make_dir("sheets") != OK):
		last_message = "could not create the sheets folder"
		_refresh_canvas()
		return ""
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		last_message = "could not write the sheet"
		_refresh_canvas()
		return ""
	file.store_buffer(bytes)
	file.close()
	plot_path = ProjectSettings.globalize_path(path)
	last_message = "plotted %d entities, %d bytes" % [document.count(), bytes.size()]
	_refresh_canvas()
	return plot_path


# --- the sheet set -------------------------------------------------------------------


## The sheets this drawing is plotted as. On the document, because a set is a property of the drawing
## and travels in the file with it; this is only how the rest of the app reaches it.
##
## The paper fields are adopted from the current sheet the moment a document is bound (see `document`),
## so by the time anything asks for the set the two already agree.
func sheet_set() -> DraftSheetSet:
	return document.sheets if document != null else null


## Make one sheet of the set the current one: the drawing's paper fields take its values. That is what
## choosing a sheet means - the sheet is what is plotted next, and the drawing is set up as it.
func load_sheet(index: int) -> bool:
	var sheet_book := sheet_set()
	if sheet_book == null or not sheet_book.select(index):
		return false
	return _adopt_current_sheet()


func _adopt_current_sheet() -> bool:
	var sheet_book := sheet_set()
	if sheet_book == null:
		return false
	var row: Dictionary = sheet_book.current()
	if row.is_empty():
		return false
	sheet = String(row["sheet"])
	plot_scale = float(row["scale"])
	show_legend = bool(row["legend"])
	portrait = bool(row["portrait"])
	sheet_number = String(row["number"])
	revision = String(row["revision"])
	# The sheet titles the drawing, which is what the DRAWING row of a title block says: a set's sheets
	# are several drawings of one job, and "Planting plan" belongs to the sheet rather than to the site.
	drawing_title = String(row["title"])
	project_name = sheet_book.project if not sheet_book.project.strip_edges().is_empty() else project_name
	sheet_date = sheet_book.date
	return true


## Write the live paper fields back into the current sheet. Called on every plot as well as on every
## edit, so the set cannot fall out of step with what is on screen.
func save_sheet() -> bool:
	var sheet_book := sheet_set()
	if sheet_book == null:
		return false
	var index := sheet_book.current_index()
	sheet_book.set_field(index, "title", drawing_title)
	sheet_book.set_field(index, "number", sheet_number)
	sheet_book.set_field(index, "revision", revision)
	sheet_book.set_field(index, "sheet", sheet)
	sheet_book.set_field(index, "scale", plot_scale)
	sheet_book.set_field(index, "legend", show_legend)
	sheet_book.set_field(index, "portrait", portrait)
	sheet_book.project = project_name
	sheet_book.date = sheet_date
	return true


## Choose the paper size, from the File menu or from the sheet window. One door, so the size and the
## current sheet cannot disagree.
func set_sheet_size(sheet_name: String) -> bool:
	if not PlotScaleScript.sheet_names().has(sheet_name):
		return false
	sheet = sheet_name
	save_sheet()
	return true


func set_plot_scale(ratio: float) -> bool:
	if ratio <= 0.0:
		return false
	plot_scale = ratio
	save_sheet()
	return true


## One row per sheet of the set, as anything drawing a list of them needs it: the set's own fields,
## plus whether this is the current sheet. Saying it in one place keeps the window, a menu and a test
## from each deciding what a sheet is.
func sheet_rows() -> Array[Dictionary]:
	var sheet_book := sheet_set()
	var out: Array[Dictionary] = []
	if sheet_book == null:
		return out
	for index in sheet_book.count():
		var row: Dictionary = sheet_book.sheet(index)
		out.append({
			"index": index,
			"title": String(row["title"]),
			"number": String(row["number"]),
			"revision": String(row["revision"]),
			"sheet": String(row["sheet"]),
			"scale": float(row["scale"]),
			"legend": bool(row["legend"]),
			"portrait": bool(row["portrait"]),
			"current": index == sheet_book.current_index(),
			"description": sheet_book.describe(index),
		})
	return out


## Add a sheet to the set, titled and papered like the current one: a second sheet of a set is
## usually the same job on the same paper, and the designer edits what differs. One undo step, because
## adding a sheet is a change to the drawing like any other.
func add_sheet(title: String = "") -> int:
	var sheet_book := sheet_set()
	if sheet_book == null:
		return -1
	var current: Dictionary = sheet_book.current()
	var wanted := title if not title.strip_edges().is_empty() else String(current.get("title", drawing_title))
	# The paper is copied and the *identity* is not: the new sheet takes the current one's size, scale and
	# flags, but gets its own number from the set and starts with no revision, because a second sheet of a
	# set is the same job on the same paper and not a copy of the sheet it came from.
	var paper := {
		"sheet": current.get("sheet", SheetSetScript.DEFAULT_SHEET),
		"scale": current.get("scale", SheetSetScript.DEFAULT_SCALE),
		"legend": current.get("legend", true),
		"portrait": current.get("portrait", false),
	}
	document.begin_gesture()
	var index: int = sheet_book.add(wanted, paper)
	_adopt_current_sheet()
	last_message = "sheet %s added" % String(sheet_book.current()["number"])
	_refresh_canvas()
	return index


func remove_sheet(index: int) -> bool:
	var sheet_book := sheet_set()
	if sheet_book == null:
		return false
	if not sheet_book.is_valid(index):
		return false
	document.begin_gesture()
	if not sheet_book.remove(index):
		last_message = "a drawing always plots as at least one sheet"
		_refresh_canvas()
		return false
	_adopt_current_sheet()
	last_message = "sheet removed"
	_refresh_canvas()
	return true


## Change one field of one sheet of the set. Routed through here rather than through the set directly,
## so that editing the *current* sheet also moves the live fields the rest of the app reads.
func set_sheet_field(index: int, field: String, value: Variant) -> bool:
	var sheet_book := sheet_set()
	if sheet_book == null or not sheet_book.is_valid(index):
		return false
	if not sheet_book.set_field(index, field, value):
		return false
	if index == sheet_book.current_index():
		_adopt_current_sheet()
	return true


## Plot one sheet of the set.
func plot_sheet(index: int, schedule: Array = []) -> String:
	var sheet_book := sheet_set()
	if sheet_book == null or not sheet_book.is_valid(index):
		last_message = "there is no such sheet"
		_refresh_canvas()
		return ""
	save_sheet()
	var options: Dictionary = sheet_book.options_for(index, {"pen_table": pen_table, "project": project_name})
	return plot(schedule, options)


## Plot every sheet of the set, in order, and report how many were written. The set is left as the
## designer set it up - nothing is switched by hand in between, which is the whole reason a set exists
## - and one sheet that fails does not stop the rest.
func plot_set(schedule: Array = []) -> Array[String]:
	var written: Array[String] = []
	var sheet_book := sheet_set()
	if sheet_book == null:
		return written
	if document.count() == 0:
		# One reason for the whole set rather than one per sheet: an empty drawing has nothing to plot on
		# any of them, and "plotted 0 of 3 sheets" would bury the reason.
		last_message = "nothing to plot"
		_refresh_canvas()
		return written
	save_sheet()
	for index in sheet_book.count():
		var path: String = plot_sheet(index, schedule)
		if not path.is_empty():
			written.append(path)
	last_message = "plotted %d of %d sheets" % [written.size(), sheet_book.count()]
	_refresh_canvas()
	return written


## Put an imported survey on the drawing.
##
## The property outline lands on the property layer as one closed shape, and the
## whole import is one undo step: importing is one act, and a designer who read the
## wrong lot wants one Ctrl+Z to take it back off rather than a walk back through it
## line by line.
##
## The survey engine's own report decides. A failing check refuses the import -
## a parcel that crosses itself is a tracing error, and putting it on the drawing
## would make the plan the place the mistake is discovered, months later. A warning
## does not refuse: a loose closure is a fact about the survey rather than a reason
## to keep it off the plan, and it is reported instead.
func import_survey(parsed: Dictionary) -> Dictionary:
	if document == null:
		return {"ok": false, "reason": "there is no drawing to import it into"}
	if not bool(parsed.get("ok", false)):
		last_message = String(parsed.get("reason", "the survey could not be read"))
		_refresh_canvas()
		return {"ok": false, "reason": last_message}
	if not SurveyFileScript.is_sound(parsed):
		last_message = "the survey did not pass its own checks"
		_refresh_canvas()
		return {"ok": false, "reason": last_message}
	var outline: PackedVector2Array = parsed.get("outline", PackedVector2Array())
	if outline.size() < 3:
		last_message = "the survey has no outline to put on the drawing"
		_refresh_canvas()
		return {"ok": false, "reason": last_message}
	document.begin_gesture()
	var entity := EntityScript.make_polyline(outline, true)
	if entity == null:
		last_message = "the survey outline could not be drawn"
		_refresh_canvas()
		return {"ok": false, "reason": last_message}
	document.add(entity, LayerSetScript.SURVEY_PROPERTY)
	snap.bind(document.entities())
	dirty = true
	last_message = "imported %s" % SurveyFileScript.describe(parsed)
	_refresh_canvas()
	return {"ok": true, "reason": "", "id": entity.id, "message": last_message}


## Write the planting's own labels onto the drawing.
##
## A label is an annotation, so it lands on the text layer whatever was being drawn,
## for the same reason a dimension lands on the dimension layer: a planting label
## buried among the bed outlines would plot at the beds' weight and count in their
## row of the key.
##
## The whole run of labels is one undo step, because a plan is labelled in one act -
## and a designer who labels a planting twice wants one Ctrl+Z, not one per plant.
## A label with nothing to say, or with nowhere to stand, is passed over.
func label_planting(labels: Array) -> Dictionary:
	if document == null:
		return {"ok": false, "reason": "there is no drawing to label"}
	var wanted: Array = []
	for entry in labels:
		var label: Dictionary = entry
		var text := String(label.get("text", "")).strip_edges()
		if text.is_empty():
			continue
		if not (label.get("at") is Vector2):
			continue
		wanted.append({"at": label["at"], "text": text})
	if wanted.is_empty():
		last_message = "there is nothing to label"
		_refresh_canvas()
		return {"ok": false, "reason": last_message}
	document.begin_gesture()
	for label: Dictionary in wanted:
		var entity := EntityScript.make_text(label["at"], String(label["text"]))
		if entity == null:
			continue
		entity.meta["height"] = PlantLabelsScript.LABEL_HEIGHT_MM
		document.add(entity, LayerSetScript.TEXT)
	dirty = true
	last_message = "labelled %s" % PlantLabelsScript.summary(labels)
	_refresh_canvas()
	return {"ok": true, "reason": "", "count": wanted.size(), "message": last_message}


## Put a sentence on the drawing's own status line, for a caller that never reached the
## controller. An import that failed to be read still has to be answered for, and the status line
## is where every other answer about the drawing appears.
func note(message: String) -> void:
	last_message = message
	_refresh_canvas()


# --- the drawing on disk --------------------------------------------------------------


## Start an empty drawing.


## Start an empty drawing.
##
## The layers, the units, the site and the dimension standard stay: they are the drawing's
## *setup* rather than its contents, and a new drawing in a named project is still drawn to
## that project's standards. The undo history goes, because the history of the drawing that
## was on the screen is not the history of this one.
func new_drawing() -> void:
	document.clear()
	document.undo.clear()
	# A new drawing starts from one sheet. The set is not carried over from the drawing that was in hand:
	# a new drawing is a new job on a new title block, and inheriting the last job's drawing numbers and
	# revisions is how a set of sheets ends up describing somebody else's garden.
	document.sheets = SheetSetScript.new()
	# The set's own first sheet is taken as it is - A3 at 1:100, numbered under the drawing number - and
	# the two things a new job must not inherit are cleared with it: the last revision, and its date.
	_adopt_current_sheet()
	revision = ""
	sheet_date = ""
	save_sheet()
	# A new drawing has no history: the revisions belong to the design that was sent, and a new drawing
	# is a new job rather than a continuation of the one in hand.
	revisions = RevisionLogScript.new()
	drawing_path = ""
	dirty = false
	last_message = "new drawing"
	_refresh_canvas()


## Write the drawing to disk. With no path, it goes back where it came from.
##
## A drawing that has never been saved has no name, and this refuses rather than inventing one:
## a file called "untitled-3.json" is a file nobody will find again, which is what Save As is
## for. Returns `{"ok", "reason", "path"}`, and says what happened in `last_message` either way.
func save_drawing(path: String = "") -> Dictionary:
	var target := path if not path.is_empty() else drawing_path
	var written: Dictionary = StoreScript.write(document, target)
	if bool(written["ok"]):
		drawing_path = String(written["path"])
		dirty = false
		StoreScript.remember(drawing_path)
		# The history follows the drawing to its file. A revision recorded before the drawing had a name
		# was kept in memory - the designer had done their part and the file name is a separate errand -
		# and this is the moment it has somewhere to go.
		StoreScript.write_revisions(revisions, drawing_path)
		last_message = "saved %s" % StoreScript.display_name(drawing_path)
	else:
		last_message = String(written["reason"])
	_refresh_canvas()
	return written


## Open a drawing over the one in hand.
##
## A file that cannot be read leaves the drawing in hand alone: a failed Open must not be a way
## to lose what you had. The whole chain is re-bound, because the snaps, the canvas and the
## overlay each hold the document they were given.
func open_drawing(path: String) -> bool:
	var read: Dictionary = StoreScript.read(path)
	if not bool(read["ok"]):
		last_message = String(read["reason"])
		_refresh_canvas()
		return false
	var opened := DocumentScript.from_dict(read["data"])
	_bind_document(opened)
	drawing_path = path
	dirty = false
	StoreScript.remember(path)
	# The history that belongs to this drawing comes with it. A drawing nothing has been recorded
	# against has no history file, which is not a failure: it is a history with nothing in it yet.
	revisions = StoreScript.read_revisions(path)
	last_message = "opened %s" % StoreScript.display_name(path)
	_refresh_canvas()
	return true


## Put a document in place of the one in hand and re-bind everything that holds it - the snaps, the
## canvas and the overlay each keep the document they were given.
##
## One door, because *two* things now do this: opening a drawing, and restoring a revision of the one
## that is open. The document's own `changed` signal is connected by `_ready` when the controller is in
## a scene, and guarded here because a controller that never entered a tree never ran it.
func _bind_document(opened) -> void:
	if document != null and document.changed.is_connected(_on_document_changed):
		document.changed.disconnect(_on_document_changed)
	# Setting `document` adopts the current sheet of whatever set the new drawing carries, so the paper
	# the drawing is set up at is the paper it was saved at.
	document = opened
	document.changed.connect(_on_document_changed)
	# The history goes with the drawing it belonged to: an undo that reached across a file
	# boundary would resurrect a drawing the file no longer holds.
	document.undo.clear()
	snap.bind(document.entities())
	if canvas != null:
		canvas.bind_document(document)
	if overlay != null:
		overlay.bind_document(document)


# --- the named revisions of the drawing -----------------------------------------------


## Record the drawing as it stands, under a message. The one act a revision log needs, and the only
## thing a designer has to do: everything else - the time, the author, the size of the drawing, the
## difference from the revision before - is read off what it keeps.
##
## A drawing that has never been saved has nowhere to keep its history, so the revision is held in
## memory until the drawing is saved; the message says so rather than failing, because the designer has
## done their part and the file name is a separate errand.
func capture_revision(message: String = "", author: String = "") -> Dictionary:
	var record: Dictionary = revisions.capture(document.to_dict(), message, author)
	var written: Dictionary = StoreScript.write_revisions(revisions, drawing_path)
	if bool(written["ok"]):
		last_message = "recorded %s" % revisions.describe(revisions.count() - 1)
	else:
		last_message = "recorded in memory only: %s" % String(written["reason"])
	_refresh_canvas()
	return record


## One row per revision, as anything listing them needs it, plus the difference from the revision
## before it - which is the question a history exists to answer, and which is cheap here because a
## snapshot is five lines' work to compare.
func revision_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for index in revisions.count():
		var row: Dictionary = revisions.record_at(index)
		var changes: Dictionary = revisions.diff(index - 1, index) if index > 0 else {}
		row["description"] = revisions.describe(index)
		row["change"] = DraftRevisionLog.describe_diff(changes) if not changes.is_empty() else ""
		rows.append(row)
	return rows


## Put an earlier revision back on the drawing. It is a change to the drawing like any other, so the
## state it replaces is pushed onto the undo stack: a designer who restores the wrong revision must be
## able to get back the drawing they had a moment before.
func restore_revision(index: int) -> bool:
	if not revisions.is_valid(index):
		last_message = "there is no such revision"
		_refresh_canvas()
		return false
	var state: Dictionary = revisions.snapshot(index)
	var restored := DocumentScript.from_dict(state)
	if restored == null:
		last_message = "that revision cannot be put back"
		_refresh_canvas()
		return false
	var before: Dictionary = document.snapshot()
	_bind_document(restored)
	if not before.is_empty():
		document.undo.push(before)
	# The drawing no longer matches the file it came from: what is on screen is an earlier revision of
	# it, and nothing has been written since.
	dirty = true
	last_message = "restored %s" % revisions.describe(index)
	_refresh_canvas()
	return true


## The drawings opened recently, newest first, as paths.
func recent_drawings() -> Array[String]:
	return StoreScript.read_recent()


## What the drawing is, for a menu line or a window title: its file name, and whether what is on
## the screen is what the file holds.
func drawing_state_text() -> String:
	# Not `name`: this is a Node, and `name` is the node's own.
	var file_name := StoreScript.display_name(drawing_path)
	if file_name.is_empty():
		file_name = "untitled drawing"
	return "%s - unsaved changes" % file_name if dirty else file_name


func _on_document_changed() -> void:
	# The index has to follow the drawing or snapping goes stale after an edit.
	snap.bind(document.entities())
	dirty = true
	_refresh_canvas()
	changed.emit()


func _refresh_canvas() -> void:
	if canvas == null:
		return
	canvas.snap = {
		"snapped": cursor_snapped,
		"point": cursor_point,
		"label": String(_last_snap.get("label", "")),
	}
	var preview = tool.preview(cursor_point)
	canvas.ghost = {"entity": preview, "layer": document.layers.get_layer(tool.layer)} \
		if preview != null else {}
	if overlay != null:
		overlay.set_ghost(preview, document.layers.get_layer(tool.layer))
	# The selection is the canvas's to draw and the controller's to decide, so it is
	# handed over as ids: a highlight that outlived the geometry it named would be a
	# highlight of nothing.
	canvas.set_selection(_selected)
	canvas.status_text = status()
	canvas.queue_redraw()