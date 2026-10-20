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

@export var plan_canvas_path: NodePath = ^"../PlanLayer/PlanCanvas"
## The 3D linework overlay, when the scene has one. Optional: drawing works
## without it, the linework is simply not visible in the 3D views.
@export var overlay_path: NodePath = ^"../DraftOverlay"

## True while the tools own the left mouse button.
var drawing: bool = false

var document
var snap
var tool
var canvas: Node2D = null
var overlay: Node = null

var cursor_point: Vector2 = Vector2.ZERO
var cursor_snapped: bool = false
var last_message: String = ""

var _last_snap: Dictionary = {}

signal changed()


func _ready() -> void:
	document = DocumentScript.new()
	snap = SnapScript.new()
	tool = ToolScript.new()
	tool.begin(ToolScript.Kind.LINE, LayerSetScript.NEW_HARDSCAPE)
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
	tool.begin(kind, tool.layer)
	snap.clear_lock()
	_last_snap = {}
	last_message = ""
	_refresh_canvas()


func set_layer(layer_name: StringName) -> void:
	if not document.layers.has(layer_name):
		return
	tool.layer = layer_name
	last_message = "drawing on %s" % String(layer_name)
	_refresh_canvas()


func toggle_drawing() -> void:
	drawing = not drawing
	if not drawing:
		cancel()
	last_message = "drawing on" if drawing else ""
	_refresh_canvas()


func entity_count() -> int:
	return document.count()


func status() -> String:
	if not drawing:
		return ""
	var text := "%s  ·  %s  ·  %s" % [
		ToolScript.label_for(tool.kind), String(tool.layer), tool.status()
	]
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


# --- plumbing -----------------------------------------------------------------------


func _on_document_changed() -> void:
	# The index has to follow the drawing or snapping goes stale after an edit.
	snap.bind(document.entities())
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
	canvas.status_text = status()
	canvas.queue_redraw()