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
const PenStyleScript := preload("res://scripts/draft/plot_style_table.gd")
const DimensionStyleScript := preload("res://scripts/draft/dimension_style.gd")

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

## Which layer ordinary geometry is drawn on. Held apart from the tool's own
## layer because annotating is not drawing: a dimension always goes on the
## dimension layer, and that choice must not leave the next line stranded there.
var drawing_layer: StringName = LayerSetScript.NEW_HARDSCAPE

## The sheet the drawing plots to: a property of the drawing rather than of a
## tool, so it lives here beside the document.
var sheet: String = "A3"
var plot_scale: float = 100.0
var pen_table = null
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

var cursor_point: Vector2 = Vector2.ZERO
var cursor_snapped: bool = false
var last_message: String = ""

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
	drawing = not drawing
	if not drawing:
		cancel()
	last_message = "drawing on" if drawing else ""
	_refresh_canvas()


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
func plot() -> String:
	if document.count() == 0:
		last_message = "nothing to plot"
		_refresh_canvas()
		return ""
	var options := {
		"sheet": sheet,
		"scale": plot_scale,
		"pen_table": pen_table,
		"project": project_name,
		"drawing": drawing_title,
		"legend": show_legend,
	}
	var bytes: PackedByteArray = SheetExporterScript.export_pdf(document, options)
	# A timestamped name, so plotting twice does not silently replace the first
	# sheet a client has already been sent.
	var path := "user://sheets/plot-%s.pdf" % Time.get_datetime_string_from_system(
		false, true
	).replace(":", "-")
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