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
const DxfFileScript := preload("res://scripts/draft/dxf_file.gd")
const DxfWriterScript := preload("res://scripts/draft/dxf_writer.gd")
const UnitsScript := preload("res://scripts/draft/units.gd")
const OsmFileScript := preload("res://scripts/draft/osm_file.gd")
const LandXmlFileScript := preload("res://scripts/draft/landxml_file.gd")
const IrrigationScript := preload("res://scripts/draft/irrigation.gd")
const LightingScript := preload("res://scripts/draft/lighting.gd")
const EntityScript := preload("res://scripts/draft/draft_entity.gd")
const PlantLabelsScript := preload("res://scripts/plant_labels.gd")
const SelectScript := preload("res://scripts/draft/draft_select.gd")
const HatchFillScript := preload("res://scripts/draft/hatch_fill.gd")
const ZoneMapScript := preload("res://scripts/zone_map.gd")
const SheetSetScript := preload("res://scripts/draft/sheet_set.gd")
const PlotScaleScript := preload("res://scripts/draft/plot_scale.gd")
const RevisionLogScript := preload("res://scripts/draft/revision_log.gd")
const DraftSimplifyScript := preload("res://scripts/draft/draft_simplify.gd")
const SimplifyReportScript := preload("res://scripts/draft/simplify_report.gd")
const AutosaveScript := preload("res://scripts/draft/autosave.gd")
const RasterUnderlayScript := preload("res://scripts/draft/raster_underlay.gd")
const GradingScript := preload("res://scripts/draft/grading.gd")
const StatusHistoryScript := preload("res://scripts/draft/status_history.gd")

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
	ROTATE,
	MOVE,
	COPY,
}

## The words each edit command is introduced by, so the status line, the menu and
## the palette cannot call the same command three different things.
const EDIT_LABELS: Dictionary = {
	EditKind.OFFSET: "Offset",
	EditKind.TRIM: "Trim",
	EditKind.EXTEND: "Extend",
	EditKind.FILLET: "Fillet",
	EditKind.ERASE: "Erase",
	EditKind.ROTATE: "Rotate",
	EditKind.MOVE: "Move",
	EditKind.COPY: "Copy",
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
## The last thing the drawing said about itself: what the status line under the plan is made of.
##
## Every message the drawing says is kept as it is said - see `said` - so a status line that has already
## moved on can still be read back. The setter is what feeds it rather than a call at each of the twenty
## places a message is set: a message is a message wherever it comes from, and this is the one place all
## of them pass through.
var last_message: String = "":
	set(value):
		last_message = value
		said.note(value)
## What the drawing has said, newest first, capped. Read by the HUD's "What just happened" page.
var said: StatusHistory = StatusHistoryScript.new()

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

## The level a grading tool is stating, in metres above whatever benchmark the drawing uses. The level
## *in hand*, like the layer in hand: it is what the next spot level gets, it is not a fact about the
## drawing, and it is therefore not written into the file. What the drawing keeps is the levels that
## were stamped with it.
## The fall a slope arrow states, in percent, downhill along the arrow. The *intention* rather than a
## measurement, which is why it is a number in hand rather than something worked out: the levels say
## what the ground does, the arrow says what the paving is to do, and the check exists to catch the two
## disagreeing. An arrow whose ends have no levels on them is not wrong, it is unchecked, and the
## report says which of the two it is.
var grading_fall_percent: float = 2.0

## The level a grading tool is stating, in metres above whatever benchmark the drawing uses. The level
## *in hand*, like the layer in hand: it is what the next spot level gets, it is not a fact about the
## drawing, and it is therefore not written into the file. What the drawing keeps is the levels that
## were stamped with it.
var grading_level: float = 0.0

var _last_snap: Dictionary = {}

signal changed()

## The document in hand was *replaced* rather than edited: a drawing was opened, a revision of it was
## restored, or a copy of it was recovered. Every holder of a document watches this, because a
## replacement leaves each of them pointing at a drawing that is no longer on the screen. The snaps,
## the canvas and the overlay are re-bound by `_bind_document` itself; anything else that keeps a
## document - the 3D derivation is the one in the scene - re-binds on the signal.
signal document_replaced(opened: DraftDocument)


func _ready() -> void:
	document = DocumentScript.new()
	snap = SnapScript.new()
	tool = ToolScript.new()
	tool.begin(ToolScript.Kind.LINE, drawing_layer)
	pen_table = PenStyleScript.default_table()
	_rebind_snap()
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
	if ToolScript.is_grading(kind):
		# A grading mark goes on its own grading layer whatever was last drawn on, for the reason a
		# dimension goes on the dimension layer: a level buried among the paving plots at the paving's
		# weight and counts in the paving's row of the key.
		return GradingScript.layer_for(ToolScript.grading_kind(kind))
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


## A key as a person reads it: the first event an action lists, with its modifier.
##
## The idle status advertises the two keys a person needs before any tool is armed - the one that arms
## the tools and the one that plots a sheet. A letter written into the string goes stale the moment a
## binding moves, and it did: `draft_mode` was moved from D to 0 and this line went on telling people
## to press D, which now pans the camera - a legend that sends somebody to the wrong key is worse than
## no legend at all. So the keys are read from the bindings, the way the HUD's legend labels its own
## rows; `test_hud_hints` holds the two to the same answer so they cannot drift apart.
static func action_key_label(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""
	for event: InputEvent in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key == null:
			continue
		# An action binds by physical keycode or by keycode depending on how it was authored, and
		# which one is set differs between the number keys and the named ones, so both are looked at.
		var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
		if code == 0:
			continue
		var rendered := OS.get_keycode_string(code)
		return ("Ctrl+" + rendered) if key.ctrl_pressed else rendered
	return ""


func status() -> String:
	if not drawing:
		# Plotting works whether or not a tool is armed, so its result - and the
		# key that triggers it - belong on screen outside drawing mode too.
		# The key that arms the tools is advertised here because this is where every
		# other key the drawing needs is advertised, and it is the one key a user
		# cannot discover by accident. The rest of the legend appears once armed.
		var idle := "%s plots a sheet at 1:%d on %s   %s: drawing tools" % [
			action_key_label(&"draft_plot"), int(plot_scale), sheet,
			action_key_label(&"draft_mode"),
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
		EditKind.ROTATE:
			if _edit_picked.is_empty():
				hint = "pick the shape to turn"
			elif _edit_points.is_empty():
				hint = "pick the point to turn it about"
			else:
				hint = "click the direction to turn it to"
		EditKind.MOVE:
			if _edit_picked.is_empty():
				hint = "pick the shape to move"
			elif _edit_points.is_empty():
				hint = "pick the point to move it from"
			else:
				hint = "click where it should go"
		EditKind.COPY:
			if _edit_picked.is_empty():
				hint = "pick the shape to copy"
			elif _edit_points.is_empty():
				hint = "pick the point to copy from"
			else:
				hint = "click where the copy should go"
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
	_last_snap = result
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


## Undo the last gesture, and say which one it was. The label is read *before* the undo, because after it
## the gesture is on the redo side of the history - and "undo" alone leaves a person guessing whether it
## will put back the line they just trimmed or the survey they overlaid two hours ago.
func undo() -> bool:
	var words: String = document.undo_label() if document != null else ""
	var done: bool = document.undo_last()
	last_message = "undid %s" % words if done else "nothing to undo"
	return done


func redo() -> bool:
	var words: String = document.redo_label() if document != null else ""
	var done: bool = document.redo_last()
	last_message = "redid %s" % words if done else "nothing to redo"
	return done


func _commit(pick: Dictionary) -> void:
	# A grading tool hands back picks rather than a shape - a spot level is a mark *and* a label, and
	# only the module knows how big either is on paper - so it is stamped and the commit is over. The
	# picks come through the measure channel because that is the channel a tool has for "here is what
	# I picked, and no entity came of it".
	if ToolScript.is_grading(tool.kind):
		_commit_grading(pick.get("measure", null))
		return
	var entity = pick["entity"]
	if entity != null:
		# A ring drawn to state a ground zone is not geometry: nothing goes on the drawing, and the
		# map takes the outline itself.
		if zone_hand and entity.kind == EntityScript.Kind.POLYGON:
			state_ground_zone(entity.outline())
			return
		# A locked layer is not one you can add to either, or locking the survey and then finding a
		# line you drew on it would be the worst of both. The check is here rather than in
		# `document.add` because a command has a status line to say *why* nothing happened.
		if document != null and document.is_layer_locked(tool.layer):
			last_message = "%s is locked" % String(tool.layer)
			return
		# One gesture per committed shape, so a single undo removes a whole
		# entity rather than un-picking a point - and it is named, so the undo
		# button says which shape it would take back.
		document.begin_gesture("drawing a new %s" % ToolScript.label_for(tool.kind).to_lower())
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
		for entity: EntityScript in document.editable_entities():
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
		document.editable_entities() if document != null else [], first, world, select_mode
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


# --- simplifying what is already drawn ------------------------------------------------


## Work out a simplification of the selection, or of the whole visible drawing when nothing is
## selected, and change nothing. The plan is read back before it is applied, so the refusal
## rule - a shape that would detach from another is left alone - can be shown first.
func plan_simplify() -> SimplifyReportScript:
	var chosen: Array[EntityScript] = selected_entities()
	if chosen.is_empty() and document != null:
		chosen = document.editable_entities()
	return DraftSimplifyScript.plan(chosen, DraftSimplifyScript.default_tolerance(plot_scale))


## Carry a plan out as one undo step, and say in the status line what happened. A plan that
## changes nothing leaves the drawing and the undo stack untouched.
func apply_simplify(report: SimplifyReportScript) -> int:
	var written := DraftSimplifyScript.apply(document, report)
	if written > 0:
		last_message = report.describe()
		_refresh_canvas()
	else:
		last_message = "nothing to simplify"
	return written


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
	document.begin_gesture("stating the ground")
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
	document.begin_gesture("hatching a region")
	var added := 0
	for stroke: PackedVector2Array in lines:
		if stroke.size() < 2:
			continue
		document.add(
			EntityScript.make_line(stroke[0], stroke[stroke.size() - 1]), LayerSetScript.HATCH
		)
		added += 1
	_rebind_snap()
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
		EditKind.ROTATE:
			_edit_rotate(world)
		EditKind.MOVE:
			_edit_move(world)
		EditKind.COPY:
			_edit_copy(world)


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
	document.begin_gesture("trimming")
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
	document.begin_gesture("extending")
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
	document.begin_gesture("erasing")
	document.remove(target.id)
	last_message = "erased"


## Rotate: pick a shape, pick the point to turn it about, then click the direction to turn it to.
##
## The angle is read off the third pick the way `Vector2.angle()` reads one - from +X toward +Y - so
## clicking due east is a turn of nothing and clicking due north is a quarter turn. That is the CAD
## convention for "specify the rotation angle", and it is the one that lets a designer aim a shape at
## something on the plan rather than work out a number: the direction clicked *is* the answer.
##
## The shape is replaced rather than duplicated. Offsetting makes a second shape and leaves the first,
## which is why offset is a drawing aid; turning changes the shape that is already there, which is why
## this keeps the original's id and its place in the draw order.
##
## The key is U because every letter that spells the command is spoken for - R toggles the painted
## plan, O is offset, T trim, A walks the camera, E erases - and U was the free key nearest the
## drafting run.
func _edit_rotate(world: Vector2) -> void:
	if _edit_picked.is_empty():
		var target = _pick_world(world)
		if target == null:
			last_message = "nothing there to turn"
			return
		_edit_picked = [target]
		last_message = "pick the point to turn it about"
		return
	if _edit_points.is_empty():
		_edit_points = [world]
		last_message = "click the direction to turn it to"
		return
	var source = _edit_picked[0]
	var pivot: Vector2 = _edit_points[0]
	var angle: float = (world - pivot).angle()
	_edit_picked = []
	_edit_points = []
	var result: Dictionary = EditScript.rotate(source, pivot, angle)
	if not bool(result["ok"]):
		last_message = String(result["reason"])
		return
	var turned = result["entities"][0]
	document.begin_gesture("turning a shape")
	document.replace(source.id, turned)
	last_message = "turned by %s" % _turn_words(angle)


## An angle in words, for the line the command reports itself on.
static func _turn_words(angle: float) -> String:
	return String.num(rad_to_deg(angle), 1) + "°"


## Move: pick a shape, pick the point to move it from, then click where it should go.
##
## The displacement is the difference between the two picks, which is the CAD convention for
## "specify a base point and a destination" and the reason a move can be aimed at something
## already on the plan rather than worked out as a distance and a bearing: the point clicked *is*
## the destination, and a snap makes it an exact one.
##
## The shape is **replaced**, not duplicated - it keeps its id and its place in the draw order.
## Copying is the separate command, and offset is the third of the three that makes a new shape
## and leaves the old one, which is why each is its own word rather than a setting on one.
##
## The key is J because every letter that spells the command is spoken for - M draws a slope
## arrow, O is offset - and J and Y were the only letters left free; of the two, J is the one
## nearer the drafting run. Copy takes Y.
func _edit_move(world: Vector2) -> void:
	if _edit_picked.is_empty():
		var target = _pick_world(world)
		if target == null:
			last_message = "nothing there to move"
			return
		_edit_picked = [target]
		last_message = "pick the point to move it from"
		return
	if _edit_points.is_empty():
		_edit_points = [world]
		last_message = "click where it should go"
		return
	var source = _edit_picked[0]
	var offset: Vector2 = world - Vector2(_edit_points[0])
	_edit_picked = []
	_edit_points = []
	var result: Dictionary = EditScript.move(source, offset)
	if not bool(result["ok"]):
		last_message = String(result["reason"])
		return
	document.begin_gesture("moving a shape")
	document.replace(source.id, result["entities"][0])
	last_message = "moved by %s" % document.units.format_length(offset.length())


## Copy: the same three picks as a move, and the one difference that matters - the shape that was
## picked stays where it was and the copy lands at the destination.
##
## The copy is added rather than replacing anything, so it is a new shape with a new id and it
## goes to the end of its layer's draw order. That is the whole of what tells a copy from a move:
## one shape afterwards or two.
func _edit_copy(world: Vector2) -> void:
	if _edit_picked.is_empty():
		var target = _pick_world(world)
		if target == null:
			last_message = "nothing there to copy"
			return
		_edit_picked = [target]
		last_message = "pick the point to copy from"
		return
	if _edit_points.is_empty():
		_edit_points = [world]
		last_message = "click where the copy should go"
		return
	var source = _edit_picked[0]
	var offset: Vector2 = world - Vector2(_edit_points[0])
	_edit_picked = []
	_edit_points = []
	var result: Dictionary = EditScript.copy(source, offset)
	if not bool(result["ok"]):
		last_message = String(result["reason"])
		return
	document.begin_gesture("copying a shape")
	document.add(result["entities"][0], source.layer)
	last_message = "copied %s away" % document.units.format_length(offset.length())


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
	document.begin_gesture("offsetting")
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
	document.begin_gesture("filleting a corner")
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
	# `editable_entities` is what leaves a locked layer out: its shapes stay on the sheet and
	# still plot, they simply cannot be picked (REQ 5.2.2). Every editing command reaches its
	# shape through here, so one filter covers offset, trim, extend, fillet, erase, rotate, move
	# and copy.
	for entity in document.editable_entities():
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
## garden rather than from the drawing, and it is passed the way the pen table is. The irrigation
## schedule is the other way round - a zone is stored with the drawing - so that table is filled in
## here and needs no argument.
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
	# The irrigation schedule is the one table the sheet reads off the drawing itself: a zone is stored
	# with the drawing, so nobody has to hand it in the way the planting list is handed in. An unwatered
	# drawing gets no table rather than an empty one.
	var zones := irrigation_rows()
	if not zones.is_empty():
		options["irrigation"] = zones
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


## Writing the drawing out as a DXF for somebody else to open.
##
## The mirror of the DXF import and deliberately not the same command: an import *places* geometry that
## came from somewhere else, while this sends the drawing out as it stands. So it touches the drawing
## not at all - no undo step, no selection, no layer - and the only things it decides are what the file
## says its numbers mean and how big its text is.
##
## The unit is the drawing's own, because that is what its numbers already are: a drawing set up in
## feet is one whose dimensions read in feet, and a file that went out in metres would contradict the
## sheet plotted from it.
##
## The plot scale is passed because **text height is a paper property**. A `TEXT` entity carries a
## position and some words and nothing that says how tall it is - the height comes from the drawing's
## standard at a scale - so the file is written at the size this drawing would go out at, and the
## report says which scale that was.
##
## Returns the writer's own report, so a caller can show the lines
## (`DxfWriter.report_lines`) rather than a summary of them.
func export_dxf(path: String) -> Dictionary:
	var unit_name := "metres" if document.units.system == UnitsScript.System.METRIC else "feet"
	var made := DxfWriterScript.shapes_from_document(document, {"scale": plot_scale})
	if not bool(made["ok"]):
		last_message = String(made["reason"])
		_refresh_canvas()
		return made
	if (made["shapes"] as Array).is_empty():
		# Said rather than written: a file with no records in it is not an export, and a person who
		# asked for one and got an empty file would think it had failed silently.
		last_message = "nothing on this drawing plots, so there is nothing to export"
		_refresh_canvas()
		return {"ok": false, "reason": String(last_message)}
	var written := DxfWriterScript.write_file(
		path, made["shapes"], {"units": unit_name, "scale": plot_scale}
	)
	if not bool(written["ok"]):
		last_message = String(written["reason"])
		_refresh_canvas()
		return written
	written["not_written"] = made["not_written"]
	last_message = "exported %s" % DxfWriterScript.describe(written)
	_refresh_canvas()
	return written


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
	document.begin_gesture("adding a sheet")
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
	document.begin_gesture("taking a sheet away")
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
	document.begin_gesture("importing a survey")
	var entity := EntityScript.make_polyline(outline, true)
	if entity == null:
		last_message = "the survey outline could not be drawn"
		_refresh_canvas()
		return {"ok": false, "reason": last_message}
	document.add(entity, LayerSetScript.SURVEY_PROPERTY)
	_rebind_snap()
	dirty = true
	last_message = "imported %s" % SurveyFileScript.describe(parsed)
	_refresh_canvas()
	return {"ok": true, "reason": "", "id": entity.id, "message": last_message}


## Put a surveyor's DXF on the drawing: as an underlay to trace over, or - when the file is being
## kept rather than traced over - on the layers its own layer names map to. Which one happened is the
## plan's own decision, made when it was read (`DxfFile`, REQ 6.7.4).
##
## One undo step whatever the file holds. A plan traced over a surveyor's drawing is one act, and
## somebody who reads the wrong file wants one Ctrl+Z rather than three hundred.
##
## Text keeps the surveyor's own size: a DXF height is a *model* length and this drawing states text
## sizes on paper, so the two are reconciled by the plot scale - exactly as the drawing's own
## dimensions are (a text size is a paper property, not a model one).
func import_dxf(plan: Dictionary, _options: Dictionary = {}) -> Dictionary:
	if document == null:
		last_message = "there is no drawing to import it into"
		_refresh_canvas()
		return {"ok": false, "reason": last_message, "added": 0, "refused": 0}
	if not DxfFileScript.is_usable(plan):
		# A refused plan says why it was refused; a plan that read but holds nothing this can draw
		# has to say that instead, because "the file could not be read" would be false.
		last_message = (String(plan.get("reason", "")) if not bool(plan.get("ok", false))
			else "the file has nothing in it that this can draw")
		_refresh_canvas()
		return {"ok": false, "reason": last_message, "added": 0, "refused": 0}
	var placed := _place_shapes(plan["shapes"], "importing a DXF underlay")
	last_message = "placed %d shape%s%s on the %s" % [
		int(placed["added"]), "" if int(placed["added"]) == 1 else "s",
		"" if int(placed["refused"]) == 0 else " and left out %d" % int(placed["refused"]),
		"underlay" if bool(plan["underlay"]) else "layers it maps to",
	]
	_refresh_canvas()
	return {
		"ok": true, "reason": "", "added": int(placed["added"]),
		"refused": int(placed["refused"]), "message": last_message,
	}


## Put an OpenStreetMap extract on the drawing: the existing conditions around the site, to trace
## over. The same shape table the DXF reader produces and the same one undo step, and the same
## default of the layer that does not plot, because map context is context rather than survey
## (see `OsmFile`).
##
## The message says *feature* rather than *shape* because that is what an OSM element is: a house, a
## street, a row of trees. Saying "shape" would read as though the reader had failed to understand
## its own file.
func import_osm(plan: Dictionary, _options: Dictionary = {}) -> Dictionary:
	if document == null:
		last_message = "there is no drawing to import it into"
		_refresh_canvas()
		return {"ok": false, "reason": last_message, "added": 0, "refused": 0}
	if not OsmFileScript.is_usable(plan):
		last_message = (String(plan.get("reason", "")) if not bool(plan.get("ok", false))
			else "the map has nothing in it that this can draw")
		_refresh_canvas()
		return {"ok": false, "reason": last_message, "added": 0, "refused": 0}
	var placed := _place_shapes(plan["shapes"], "importing a site map")
	last_message = "placed %d feature%s%s from %s" % [
		int(placed["added"]), "" if int(placed["added"]) == 1 else "s",
		"" if int(placed["refused"]) == 0 else " and left out %d" % int(placed["refused"]),
		"the underlay" if bool(plan["underlay"]) else "the existing conditions layers",
	]
	_refresh_canvas()
	return {
		"ok": true, "reason": "", "added": int(placed["added"]),
		"refused": int(placed["refused"]), "message": last_message,
	}


## Put a LandXML plat on the drawing: a surveyor's or a civil engineer's own file, read into
## something to draw over. The same shape table, the same one undo step and the same default of the
## layer that does not plot that the DXF and OpenStreetMap readers have (see `LandXmlFile`).
##
## The message says *shape* rather than *parcel* because one file may hold parcels, alignments and plan
## features at once, and naming one of them would be a lie about the other two.
func import_landxml(plan: Dictionary, _options: Dictionary = {}) -> Dictionary:
	if document == null:
		last_message = "there is no drawing to import it into"
		_refresh_canvas()
		return {"ok": false, "reason": last_message, "added": 0, "refused": 0}
	if not LandXmlFileScript.is_usable(plan):
		last_message = (String(plan.get("reason", "")) if not bool(plan.get("ok", false))
			else "the plat has nothing in it that this can draw")
		_refresh_canvas()
		return {"ok": false, "reason": last_message, "added": 0, "refused": 0}
	var placed := _place_shapes(plan["shapes"], "importing a LandXML plat")
	last_message = "placed %d shape%s%s from %s" % [
		int(placed["added"]), "" if int(placed["added"]) == 1 else "s",
		"" if int(placed["refused"]) == 0 else " and left out %d" % int(placed["refused"]),
		"the underlay" if bool(plan["underlay"]) else "the layers the file's features map to",
	]
	_refresh_canvas()
	return {
		"ok": true, "reason": "", "added": int(placed["added"]),
		"refused": int(placed["refused"]), "message": last_message,
	}


## Put a table of shape dictionaries on the drawing as **one** undo step, whatever it holds and
## whoever read it.
##
## **The shape table is the interface between a reader and the drawing, and it is three readers old.**
## A shape is a dictionary with these keys, and nothing else is asked of it:
##
## * `kind` - `LINE`, `LWPOLYLINE`, `POLYLINE`, `CIRCLE`, `ARC` or `TEXT`
## * `layer` - which drawing layer it belongs on, decided by the reader that read it
## * `points` - the geometry, in model metres: two points for a line, a centre and a `(radius, 0)` for a
##   circle or an arc, one point for a text, and the vertices of a polyline
## * `bulges` - one per polyline point: the turn from that point to the next, 0 for a straight run
## * `closed` - whether a polyline's last point joins its first
## * `words` - what a text says; `height` - how tall it is, as a model length, reconciled with the
##   drawing's paper scale here; `arc` - a start angle and a sweep, for an arc
##
## `DxfFile`, `OsmFile` and `LandXmlFile` fill that table from a pair stream, a JSON tree and an XML
## tree respectively, and each adds its own words *beside* those keys - the DXF reader the layer name
## the file used, the other two the feature a shape came from - because those are facts about a file
## format rather than about a shape. What is not shared is the units: each reader answers that question
## itself, and the table is geometry in model metres by the time it is written. That is why a third
## format with another coordinate convention, another closure rule and another way of stating a curve
## needed no new key: there is exactly one place where a shape becomes a drawing entity, so a reader
## cannot be a new chance to forget the circle of no radius or the text with nothing written in it.
##
## One gesture because an import is one act: somebody who read the wrong file wants one Ctrl+Z
## rather than three hundred. The gesture is *named* by the reader that read the file - "importing a
## DXF underlay", "importing a site map" - because that is the one thing about the import a person
## looking at the undo button needs to know, and it is the reader that knows it.
func _place_shapes(shapes: Array, label: String = "") -> Dictionary:
	document.begin_gesture(label)
	var added := 0
	var refused := 0
	for shape: Dictionary in shapes:
		var entity := _entity_from_shape(shape)
		if entity == null:
			refused += 1
			continue
		document.add(entity, shape["layer"])
		added += 1
	_rebind_snap()
	dirty = true
	return {"added": added, "refused": refused}


## One shape as a drawing entity, or null when it cannot be one - a shape with too few points, a
## circle of no radius, a text with nothing written in it. Refusing here rather than placing a
## degenerate entity is what keeps a bad record from becoming a shape nobody can select or delete.
func _entity_from_shape(shape: Dictionary) -> DraftEntity:
	var points: PackedVector2Array = shape["points"]
	var kind := String(shape["kind"])
	if kind == "LINE":
		if points.size() < 2:
			return null
		return EntityScript.make_line(points[0], points[1])
	if kind == "CIRCLE":
		if points.size() < 2 or points[1].x <= 0.0:
			return null
		return EntityScript.make_circle(points[0], points[1].x)
	if kind == "ARC":
		if points.size() < 2 or points[1].x <= 0.0:
			return null
		var sweep: Vector2 = shape["arc"]
		return EntityScript.make_arc(points[0], points[1].x, sweep.x, sweep.y)
	if kind == "TEXT":
		if points.is_empty() or String(shape["words"]).is_empty():
			return null
		var label := EntityScript.make_text(points[0], String(shape["words"]))
		var height := float(shape.get("height", 0.0))
		if height > 0.0 and plot_scale > 0.0:
			label.meta["height"] = height * 1000.0 / plot_scale
		return label
	if kind == "LWPOLYLINE" or kind == "POLYLINE":
		if points.size() < 2:
			return null
		var line := EntityScript.make_polyline(points, bool(shape["closed"]))
		var bulges: PackedFloat64Array = shape["bulges"]
		if bulges.size() == points.size():
			line.bulges = bulges
		return line
	return null


## The zones this drawing is watered by, as the irrigation module's own records. Reading is
## defensive in one place and one place only: `Irrigation.from_dict` drops a record that is not a
## zone, so a damaged file gives fewer zones rather than an error nobody can act on.
func irrigation_zones() -> Array[Dictionary]:
	if document == null:
		return []
	return IrrigationScript.from_dict(document.irrigation)


## The water supply, as somebody stated it. A drawing with nothing stated gives an empty body, and
## the flow check refuses on it - which is the point: the app never assumes forty litres a minute.
func irrigation_supply() -> Dictionary:
	if document == null:
		return {}
	var stated = document.irrigation.get("supply", null)
	return stated if stated is Dictionary else {}


## State the supply: a flow in litres per minute at a pressure in kilopascals. One undo step,
## because it is a change to the drawing like any other.
func set_irrigation_supply(flow: float, pressure: float) -> Dictionary:
	if document == null:
		return {"ok": false, "reason": "there is no drawing to state a supply for"}
	if flow <= 0.0 or pressure <= 0.0:
		return {"ok": false, "reason": "a supply is a flow at a pressure, and neither can be nothing"}
	document.begin_gesture("stating the water supply")
	document.irrigation["supply"] = IrrigationScript.make_supply(flow, pressure)
	dirty = true
	last_message = "the supply is %s" % IrrigationScript.supply_words(irrigation_supply())
	_refresh_canvas()
	return {"ok": true, "reason": "", "message": last_message, "supply": irrigation_supply()}


## How many heads of a kind the stated supply can run, or 0 when nothing is stated. The panel shows
## this beside the supply, so a designer sees the budget before laying anything out.
func irrigation_head_budget(kind: String) -> int:
	return IrrigationScript.head_budget(irrigation_supply(), kind)


## The areas of the plan that can be watered. `hatch_regions`' own list, for the reason that list
## gives: a bed has to be named the same way wherever a designer is offered one.
func waterable_areas() -> Array[Dictionary]:
	return hatch_regions()


## Water an area: make a zone, lay its heads out, keep the zone with the drawing and put the heads
## on the plan. **One undo step**, because watering a bed is one act.
##
## Refuses before it touches anything - an area the grid cannot be laid out in, or a zone that would
## not run off the stated supply - and that is deliberate: laying out a valve that cannot be opened
## and leaving it on the drawing for the next person to find is worse than saying so.
##
## Returns `{ok, reason, message, zone, number, placed, verdict, rows}`.
func water_area(ring: PackedVector2Array, kind: String, spacing: float = 0.0,
		staggered: bool = false) -> Dictionary:
	if document == null:
		return {"ok": false, "reason": "there is no drawing to water", "placed": 0}
	if not IrrigationScript.is_kind(kind):
		last_message = "that is not a kind of head"
		_refresh_canvas()
		return {"ok": false, "reason": last_message, "placed": 0}
	var zones := irrigation_zones()
	var zone := IrrigationScript.make_zone(IrrigationScript.next_number(zones), kind)
	zone["valve"] = IrrigationScript.next_valve(zones)
	IrrigationScript.set_area(zone, ring)
	var report := IrrigationScript.lay_out(zone, kind, spacing, staggered)
	if not bool(report["ok"]):
		last_message = String(report["reason"])
		_refresh_canvas()
		return {"ok": false, "reason": last_message, "placed": 0}
	var supply := irrigation_supply()
	var verdict := IrrigationScript.check(zone, supply)
	if not bool(verdict["ok"]):
		last_message = IrrigationScript.verdict_words(zone, supply, document.units)
		_refresh_canvas()
		return {"ok": false, "reason": last_message, "placed": 0}
	document.begin_gesture("watering an area")
	zones.append(zone)
	document.irrigation["zones"] = IrrigationScript.to_dict(zones)["zones"]
	var placed := _stamp_heads(zone)
	_rebind_snap()
	dirty = true
	last_message = "%s, and %s" % [IrrigationScript.verdict_words(zone, supply, document.units),
		"1 head is on the plan" if placed == 1 else "%d heads are on the plan" % placed]
	_refresh_canvas()
	return {
		"ok": true, "reason": "", "message": last_message, "zone": zone,
		"number": int(zone["number"]), "placed": placed,
		"verdict": IrrigationScript.verdict_words(zone, supply, document.units), "rows": irrigation_rows(),
	}


## Put a zone's heads on the drawing, one entity each, and say how many.
func _stamp_heads(zone: Dictionary) -> int:
	var placed := 0
	for entry in IrrigationScript.heads_of(zone):
		var head: Dictionary = entry
		var entity := IrrigationScript.head_entity(head, int(zone.get("number", 0)), plot_scale)
		if entity == null:
			continue
		document.add(entity, IrrigationScript.layer())
		placed += 1
	return placed


## Take a zone off the drawing: its record with it, and the heads that belong to it, in one step. A
## zone whose heads stayed behind would be a plan with unwatered circles on it and nothing to say
## what they were for.
func remove_zone(number: int) -> Dictionary:
	if document == null:
		return {"ok": false, "reason": "there is no drawing to change"}
	var zones := irrigation_zones()
	var kept: Array[Dictionary] = []
	var found := false
	for zone in zones:
		if int(zone.get("number", 0)) == number:
			found = true
			continue
		kept.append(zone)
	if not found:
		last_message = "there is no Zone %d" % number
		_refresh_canvas()
		return {"ok": false, "reason": last_message, "removed": 0}
	document.begin_gesture("taking the water off an area")
	var removed := 0
	for entity in document.entities():
		if IrrigationScript.zone_of_entity(entity) == number and document.remove(entity.id):
			removed += 1
	document.irrigation["zones"] = IrrigationScript.to_dict(kept)["zones"]
	_rebind_snap()
	dirty = true
	last_message = "Zone %d is off the drawing, with %s" % [number,
		"1 head" if removed == 1 else "%d heads" % removed]
	_refresh_canvas()
	return {"ok": true, "reason": "", "message": last_message, "removed": removed,
		"rows": irrigation_rows()}


## The zones as a schedule reads them, one row each, checked against the stated supply.
func irrigation_rows() -> Array[Dictionary]:
	return IrrigationScript.schedule(irrigation_zones(), irrigation_supply(), document.units)


## The schedule as the lines a sheet or a status bar carries.
func irrigation_lines() -> Array[String]:
	return IrrigationScript.schedule_lines(irrigation_zones(), irrigation_supply(), document.units)


## One line saying what the drawing is watered by, for a panel to lead with.
func irrigation_summary() -> String:
	var zones := irrigation_zones()
	if zones.is_empty():
		return "nothing on this drawing is watered yet"
	var heads := 0
	var flow := 0.0
	var area := 0.0
	var wrong := ""
	for zone in zones:
		heads += IrrigationScript.head_count(zone)
		flow += IrrigationScript.demand_of(zone)
		area += IrrigationScript.area_m2(zone)
		if wrong.is_empty():
			var verdict := IrrigationScript.check(zone, irrigation_supply())
			if not bool(verdict["ok"]):
				wrong = IrrigationScript.verdict_words(zone, irrigation_supply(), document.units)
	if wrong.is_empty():
		wrong = "every zone runs off the supply"
	return "%s over %s, %s" % [_zone_count_words(zones.size(), heads, _quantity_words(flow)),
		document.units.format_area(area), wrong]


## A measurement as one line writes it: whole where it is whole, one decimal otherwise.
static func _quantity_words(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return "%d" % int(round(value))
	return "%.1f" % value


static func _zone_count_words(zones: int, heads: int, flow: String) -> String:
	var zone_part := "1 zone" if zones == 1 else "%d zones" % zones
	var head_part := "1 head" if heads == 1 else "%d heads" % heads
	return "%s, %s drawing %s L/min" % [zone_part, head_part, flow]


# --- lighting a circuit --------------------------------------------------------------------


## The circuits this drawing is lit by, as the lighting module's own records. Reading is defensive
## in one place and one place only: `Lighting.from_dict` drops a record that is not a circuit, so a
## damaged file gives fewer circuits rather than an error nobody can act on.
func lighting_circuits() -> Array[Dictionary]:
	if document == null:
		return []
	return LightingScript.from_dict(document.lighting)


## The transformer, as somebody stated it. A drawing with nothing stated gives an empty body, and the
## load check refuses on it - which is the point: the app never assumes a hundred volt-amperes.
func lighting_transformer() -> Dictionary:
	if document == null:
		return {}
	var stated = document.lighting.get("transformer", null)
	return stated if stated is Dictionary else {}


## State the transformer: a capacity in volt-amperes at a voltage. One undo step, because it is a
## change to the drawing like any other.
func set_lighting_transformer(va: float, volts: float) -> Dictionary:
	if document == null:
		return {"ok": false, "reason": "there is no drawing to state a transformer for"}
	if va <= 0.0 or volts <= 0.0:
		return {"ok": false, "reason": "a transformer is a capacity at a voltage, and neither can be nothing"}
	document.begin_gesture("stating the transformer")
	document.lighting["transformer"] = LightingScript.make_transformer(va, volts)
	dirty = true
	last_message = "the transformer is %s" % LightingScript.transformer_words(lighting_transformer())
	_refresh_canvas()
	return {"ok": true, "reason": "", "message": last_message, "transformer": lighting_transformer()}


## How many fixtures of a kind the stated transformer can carry, or 0 when nothing is stated.
func lighting_fixture_budget(kind: String) -> int:
	return LightingScript.power_budget(lighting_transformer(), kind)


## The areas of the plan that can be lit. `hatch_regions`' own list, for the reason that list gives:
## a bed has to be named the same way wherever a designer is offered one.
func lightable_areas() -> Array[Dictionary]:
	return hatch_regions()


## Light an area: make a circuit, lay its fixtures out, keep the circuit with the drawing and put the
## fixtures on the plan. **One undo step**, because lighting a bed is one act.
##
## Refuses before it touches anything - an area the grid cannot be laid out in, or a circuit that
## would not run off the stated transformer - and that is deliberate: laying out a circuit that cannot
## be opened and leaving it on the drawing for the next person to find is worse than saying so.
##
## Returns `{ok, reason, message, circuit, number, placed, verdict, rows}`.
func light_area(ring: PackedVector2Array, kind: String, spacing: float = 0.0,
		staggered: bool = false) -> Dictionary:
	if document == null:
		return {"ok": false, "reason": "there is no drawing to light", "placed": 0}
	if not LightingScript.is_kind(kind):
		last_message = "that is not a kind of fixture"
		_refresh_canvas()
		return {"ok": false, "reason": last_message, "placed": 0}
	var circuits := lighting_circuits()
	var circuit := LightingScript.make_circuit(LightingScript.next_number(circuits), kind)
	circuit["tap"] = LightingScript.next_tap(circuits)
	LightingScript.set_area(circuit, ring)
	var report := LightingScript.lay_out(circuit, kind, spacing, staggered)
	if not bool(report["ok"]):
		last_message = String(report["reason"])
		_refresh_canvas()
		return {"ok": false, "reason": last_message, "placed": 0}
	var transformer := lighting_transformer()
	var verdict := LightingScript.check(circuit, transformer)
	if not bool(verdict["ok"]):
		last_message = LightingScript.verdict_words(circuit, transformer, document.units)
		_refresh_canvas()
		return {"ok": false, "reason": last_message, "placed": 0}
	document.begin_gesture("lighting an area")
	circuits.append(circuit)
	document.lighting["circuits"] = LightingScript.to_dict(circuits)["circuits"]
	var placed := _stamp_fixtures(circuit)
	_rebind_snap()
	dirty = true
	last_message = "%s, and %s" % [LightingScript.verdict_words(circuit, transformer, document.units),
		"1 fixture is on the plan" if placed == 1 else "%d fixtures are on the plan" % placed]
	_refresh_canvas()
	return {
		"ok": true, "reason": "", "message": last_message, "circuit": circuit,
		"number": int(circuit["number"]), "placed": placed,
		"verdict": LightingScript.verdict_words(circuit, transformer, document.units), "rows": lighting_rows(),
	}


## Put a circuit's fixtures on the drawing, one entity each, and say how many.
func _stamp_fixtures(circuit: Dictionary) -> int:
	var placed := 0
	for entry in LightingScript.fixtures_of(circuit):
		var fixture: Dictionary = entry
		var entity := LightingScript.fixture_entity(fixture, int(circuit.get("number", 0)), plot_scale)
		if entity == null:
			continue
		document.add(entity, LightingScript.layer())
		placed += 1
	return placed


## Take a circuit off the drawing: its record with it, and the fixtures that belong to it, in one
## step. A circuit whose fixtures stayed behind would be a plan with unexplained circles on it.
func remove_circuit(number: int) -> Dictionary:
	if document == null:
		return {"ok": false, "reason": "there is no drawing to change"}
	var circuits := lighting_circuits()
	var kept: Array[Dictionary] = []
	var found := false
	for circuit in circuits:
		if int(circuit.get("number", 0)) == number:
			found = true
			continue
		kept.append(circuit)
	if not found:
		last_message = "there is no Circuit %d" % number
		_refresh_canvas()
		return {"ok": false, "reason": last_message, "removed": 0}
	document.begin_gesture("taking the lighting off an area")
	var removed := 0
	for entity in document.entities():
		if LightingScript.circuit_of_entity(entity) == number and document.remove(entity.id):
			removed += 1
	document.lighting["circuits"] = LightingScript.to_dict(kept)["circuits"]
	_rebind_snap()
	dirty = true
	last_message = "Circuit %d is off the drawing, with %s" % [number,
		"1 fixture" if removed == 1 else "%d fixtures" % removed]
	_refresh_canvas()
	return {"ok": true, "reason": "", "message": last_message, "removed": removed,
		"rows": lighting_rows()}


## The circuits as a schedule reads them, one row each, checked against the stated transformer.
func lighting_rows() -> Array[Dictionary]:
	return LightingScript.schedule(lighting_circuits(), lighting_transformer(), document.units)


## The schedule as the lines a sheet or a status bar carries.
func lighting_lines() -> Array[String]:
	return LightingScript.schedule_lines(lighting_circuits(), lighting_transformer(), document.units)


## One line saying what the drawing is lit by, for a panel to lead with.
func lighting_summary() -> String:
	var circuits := lighting_circuits()
	if circuits.is_empty():
		return "nothing on this drawing is lit yet"
	var fixtures := 0
	var demand := 0.0
	var area := 0.0
	var wrong := ""
	for circuit in circuits:
		fixtures += LightingScript.fixture_count(circuit)
		demand += LightingScript.demand_of(circuit)
		area += LightingScript.area_m2(circuit)
		if wrong.is_empty():
			var verdict := LightingScript.check(circuit, lighting_transformer())
			if not bool(verdict["ok"]):
				wrong = LightingScript.verdict_words(circuit, lighting_transformer(), document.units)
	if wrong.is_empty():
		wrong = "every circuit runs off the transformer"
	return "%s over %s, %s" % [_circuit_count_words(circuits.size(), fixtures,
		_quantity_words(demand)), document.units.format_area(area), wrong]


static func _circuit_count_words(circuits: int, fixtures: int, watts: String) -> String:
	var circuit_part := "1 circuit" if circuits == 1 else "%d circuits" % circuits
	var fixture_part := "1 fixture" if fixtures == 1 else "%d fixtures" % fixtures
	return "%s, %s drawing %s W" % [circuit_part, fixture_part, watts]


# --- the ground's own heights -----------------------------------------------------------
#
# Spot levels, contours and slope arrows. The records live on the drawing (`document.grading`) and the
# marks live on the drawing as entities, which is the split irrigation and lighting use: the module
# does the arithmetic, the drawing keeps what was stated, and the entities are what a plan and a plot
# are made of.
#
# A grading entity carries its own record's kind and id in `meta`, so taking a level off the drawing
# finds every mark and every label that level put there and nothing else.


## Every grading record the drawing holds, as the module's own set.
func grading() -> Dictionary:
	if document == null:
		return GradingScript.empty_set()
	return GradingScript.from_dict(document.grading)


func grading_spots() -> Array:
	return GradingScript.spots_of(grading())


func grading_contours() -> Array:
	return GradingScript.contours_of(grading())


func grading_slopes() -> Array:
	return GradingScript.slopes_of(grading())


## The level the next grading tool stamps, in words, so a page and a status line cannot word it twice.
func grading_level_words() -> String:
	return GradingScript.level_words(grading_level, document.units if document != null else null)


## State the level in hand. A level is a number: anything that is not one is refused rather than read
## as zero, because zero is a real elevation above a real benchmark.
func set_grading_level(level: float) -> Dictionary:
	if is_nan(level) or not is_finite(level):
		last_message = "a level is a number"
		_refresh_canvas()
		return {"ok": false, "reason": last_message, "level": grading_level}
	grading_level = level
	last_message = "a level of %s" % grading_level_words()
	_refresh_canvas()
	return {"ok": true, "reason": "", "level": grading_level, "message": last_message}


## State the fall in hand, in percent downhill. Refused rather than clamped for anything that is not a
## percentage, and refused beyond a fall that is not a fall: 100% is one in one, and a garden path at
## more than that is a wall.
func set_grading_fall(percent: float) -> Dictionary:
	if is_nan(percent) or not is_finite(percent) or absf(percent) > GradingScript.MAX_PERCENT:
		last_message = "a fall is a percentage below %s" % GradingScript.MAX_PERCENT
		_refresh_canvas()
		return {"ok": false, "reason": last_message, "percent": grading_fall_percent}
	grading_fall_percent = percent
	last_message = "slope arrows are drawn %s" % GradingScript.percent_words(percent)
	_refresh_canvas()
	return {"ok": true, "reason": "", "percent": percent, "message": last_message}


## Arm a grading tool with the level in hand. What a menu entry and a button both call, so the level
## cannot be in hand in one place and not the other.
func begin_grading(kind: String) -> Dictionary:
	if document == null:
		return {"ok": false, "reason": "there is no drawing to grade"}
	if not GradingScript.is_kind(kind):
		return {"ok": false, "reason": "that is not a kind of grading"}
	var tool_kind := ToolScript.Kind.GRADE_SPOT
	if kind == GradingScript.CONTOUR:
		tool_kind = ToolScript.Kind.GRADE_CONTOUR
	elif kind == GradingScript.SLOPE:
		tool_kind = ToolScript.Kind.GRADE_SLOPE
	arm(tool_kind)
	last_message = _grading_arm_words(kind)
	_refresh_canvas()
	return {"ok": true, "reason": "", "message": last_message, "tool": tool_kind}


## What arming a grading tool says, in the words of the kind: a level in the drawing's own units for
## the two kinds that state one, and a fall in percent for the arrow that states one instead.
func _grading_arm_words(kind: String) -> String:
	if kind == GradingScript.SLOPE:
		return "a slope arrow %s" % GradingScript.percent_words(grading_fall_percent)
	return "a %s at %s" % [GradingScript.kind_name(kind), grading_level_words()]


## Stamp what a grading tool just picked.
##
## The whole act is one gesture, named, and it refuses before it touches the drawing: a spot with no
## pick, a contour with one point and an arrow with no length are all things that would put a record
## on the drawing with no mark behind it, which is the state that makes a drawing lie about itself.
func stamp_grading(picks: Dictionary) -> Dictionary:
	if document == null:
		return {"ok": false, "reason": "there is no drawing to grade", "added": 0}
	var kind := String(picks.get("grading", ""))
	if not GradingScript.is_kind(kind):
		return {"ok": false, "reason": "that is not a kind of grading", "added": 0}
	if document.is_layer_locked(GradingScript.layer_for(kind)):
		last_message = "%s is locked" % String(GradingScript.layer_for(kind))
		_refresh_canvas()
		return {"ok": false, "reason": last_message, "added": 0}
	if is_nan(grading_level) or not is_finite(grading_level):
		last_message = "a level is a number"
		_refresh_canvas()
		return {"ok": false, "reason": last_message, "added": 0}

	var points: PackedVector2Array = picks.get("points", PackedVector2Array())
	var records := grading()
	var id := GradingScript.next_id(records, kind)
	var record: Dictionary = {}
	var label := ""
	if kind == GradingScript.SPOT:
		if points.is_empty():
			return _grading_refused("a spot level is a place, and nothing was picked")
		record = GradingScript.make_spot(id, points[0], grading_level)
		label = "stating a spot level"
	elif kind == GradingScript.CONTOUR:
		if points.size() < GradingScript.MIN_CONTOUR_POINTS:
			return _grading_refused("a contour needs at least two points to be a line")
		record = GradingScript.make_contour(id, grading_level, points, bool(picks.get("closed", false)))
		label = "drawing a %s contour" % GradingScript.level_words(grading_level, document.units)
	else:
		if points.size() < 2 or points[0].distance_to(points[1]) < GradingScript.MIN_RUN_M:
			return _grading_refused("a slope arrow needs two points with a fall between them")
		if is_nan(grading_fall_percent) or not is_finite(grading_fall_percent):
			return _grading_refused("a slope arrow states a fall, and a fall is a percentage")
		record = GradingScript.make_slope(id, points[0], points[1], grading_fall_percent)
		label = "drawing a slope arrow"

	document.begin_gesture(label)
	GradingScript.add_record(records, kind, record)
	document.grading = GradingScript.to_dict(records)
	var added := _stamp_grading(kind, record)
	_rebind_snap()
	dirty = true
	last_message = "%s is on the drawing, with %s" % [GradingScript.record_words(kind, record,
		document.units), "1 mark" if added == 1 else "%d marks" % added]
	_refresh_canvas()
	return {
		"ok": true, "reason": "", "message": last_message, "kind": kind, "id": id,
		"record": record, "added": added, "rows": grading_rows(),
	}


## Change the level a record states. One named gesture, worked out and compared before anything moves,
## so asking for the level it already has records nothing.
func set_grading_level_of(kind: String, id: int, level: float) -> Dictionary:
	if document == null:
		return {"ok": false, "reason": "there is no drawing to change"}
	if not GradingScript.is_kind(kind):
		return {"ok": false, "reason": "that is not a kind of grading"}
	if is_nan(level) or not is_finite(level):
		return _grading_refused("a level is a number")
	var records := grading()
	var record := GradingScript.record_for(records, kind, id)
	if record.is_empty():
		return _grading_refused("there is no %s %d on this drawing" % [GradingScript.kind_name(kind), id])
	if absf(float(record.get("level", NAN)) - level) <= GradingScript.LEVEL_TOLERANCE:
		last_message = "%s is already at %s" % [GradingScript.kind_name(kind),
			GradingScript.level_words(level, document.units)]
		_refresh_canvas()
		return {"ok": false, "reason": last_message, "changed": false}
	document.begin_gesture("changing the level of a %s" % GradingScript.kind_name(kind))
	record["level"] = level
	document.grading = GradingScript.to_dict(records)
	_clear_grading_entities(kind, id)
	var added := _stamp_grading(kind, record)
	_rebind_snap()
	dirty = true
	last_message = "%s is %s" % [GradingScript.kind_name(kind),
		GradingScript.level_words(level, document.units)]
	_refresh_canvas()
	return {"ok": true, "reason": "", "changed": true, "message": last_message, "added": added}


## Take a record off the drawing, with every mark and every label it put there.
func remove_grading(kind: String, id: int) -> Dictionary:
	if document == null:
		return {"ok": false, "reason": "there is no drawing to change"}
	if not GradingScript.is_kind(kind):
		return {"ok": false, "reason": "that is not a kind of grading"}
	var records := grading()
	if GradingScript.record_for(records, kind, id).is_empty():
		return _grading_refused("there is no %s %d on this drawing" % [GradingScript.kind_name(kind), id])
	document.begin_gesture("taking a %s off the drawing" % GradingScript.kind_name(kind))
	GradingScript.remove_record(records, kind, id)
	document.grading = GradingScript.to_dict(records)
	var removed := _clear_grading_entities(kind, id)
	_rebind_snap()
	dirty = true
	last_message = "%s off the drawing, with %s" % [GradingScript.kind_name(kind),
		"1 mark" if removed == 1 else "%d marks" % removed]
	_refresh_canvas()
	return {"ok": true, "reason": "", "message": last_message, "removed": removed,
		"rows": grading_rows()}


## The drawing's grading, checked against itself: the crossed contours, the two of one level, the spot
## that disagrees with the line it stands on and the arrow that contradicts its own ends.
func grading_report() -> Dictionary:
	return GradingScript.check(grading(), document.units if document != null else null)


## Whether the check has anything wrong to say. A drawing with no grading has nothing wrong with it.
func grading_reports_findings() -> bool:
	return not bool(grading_report()["ok"])


func grading_rows() -> Array[Dictionary]:
	return GradingScript.schedule(grading(), document.units if document != null else null)


func grading_lines() -> Array[String]:
	return GradingScript.schedule_lines(grading(), document.units if document != null else null)


func grading_summary() -> String:
	return GradingScript.summary(grading(), document.units if document != null else null)


## Put a record's marks and labels on the drawing. Returns how many entities were added.
func _stamp_grading(kind: String, record: Dictionary) -> int:
	var added := 0
	for entity in GradingScript.entities_for(kind, record, plot_scale, document.units):
		if entity == null:
			continue
		document.add(entity, GradingScript.layer_for(kind))
		added += 1
	return added


## Take a record's own entities off the drawing, and nothing else: the kind and the id in the entity's
## metadata are what say an entity belongs to this record rather than to the drawing.
func _clear_grading_entities(kind: String, id: int) -> int:
	var removed := 0
	for entry in document.entities():
		var entity: DraftEntity = entry
		if GradingScript.kind_of_entity(entity) != kind:
			continue
		if GradingScript.id_of_entity(entity) != id:
			continue
		if document.remove(entity.id):
			removed += 1
	return removed


## The commit a grading tool lands on. Named here rather than in `_commit` so the commit stays a
## dispatcher and the wording stays in one place.
func _commit_grading(picks) -> void:
	if not (picks is Dictionary):
		return
	var stamped := stamp_grading(picks)
	last_message = String(stamped.get("message", stamped.get("reason", "")))


func _grading_refused(reason: String) -> Dictionary:
	last_message = reason
	_refresh_canvas()
	return {"ok": false, "reason": reason, "added": 0, "removed": 0}


# --- the pictures under the drawing ----------------------------------------------------


## The pictures lying under the drawing, in draw order. Read straight from the drawing, because a
## picture is a record the drawing keeps rather than geometry it holds: nothing here has an id in the
## entity sequence, nothing here snaps, and nothing here plots.
func underlays() -> Array:
	if document == null:
		return []
	return document.underlays


## Take a picture on: copy it beside the drawing, lay it under everything and put the record on the
## drawing. **One undo step**, because putting a tracing aid under the plan is one act.
##
## `options` may carry `at` (the centre on the ground, in world XZ metres), `name` (what to call the
## copy), `rotation_deg` and `opacity`. Returns `{ok, reason, message, id, picture}`.
##
## It lands on the middle of the drawing's own extent unless it is told otherwise, so the common case
## - a scan of the site, and a design drawn on that site - puts the two on top of each other with
## nothing to type and nothing to drag.
func place_underlay(source: String, width_m: float, options: Dictionary = {}) -> Dictionary:
	if document == null:
		return {"ok": false, "reason": "there is no drawing to put a picture under", "id": 0, "picture": {}}
	var at: Vector2 = _underlay_landing()
	var stated: Variant = options.get("at", null)
	if stated is Vector2:
		at = stated
	var taken: Dictionary = RasterUnderlayScript.place(source, width_m, at, String(options.get("name", "")))
	if not bool(taken.get("ok", false)):
		last_message = String(taken.get("reason", "the picture could not be taken on"))
		_refresh_canvas()
		return {"ok": false, "reason": last_message, "id": 0, "picture": {}}
	return take_on_picture(taken["record"], options)


## Put a picture that has already been read **and kept** under the drawing, with the numbers a form is
## showing. Returns `{ok, reason, message, id, picture}`.
##
## This is the half that touches the drawing; `place_underlay` is this half plus the copy. The two are
## apart because a page that reads a file and then says how it lies has already kept its copy, and
## copying it a second time would leave a duplicate in the drawing's folder for every press of a
## button.
##
## The record is validated by the module that owns what a picture is worth, so a width that says
## nothing, a file that has gone and a size that was never read are all refused in one place, and the
## refusal names which of them it was.
func take_on_picture(record: Dictionary, options: Dictionary = {}) -> Dictionary:
	if document == null:
		return {"ok": false, "reason": "there is no drawing to put a picture under", "id": 0, "picture": {}}
	var wanted: Dictionary = record.duplicate(true)
	# A number a form sent that cannot be read is **refused by name** rather than ignored: a page that
	# says "left blank" and a page that silently keeps the old width are two different pages, and only
	# one of them is telling the person what happened.
	if options.has("width_m"):
		var width := float(options["width_m"])
		if is_nan(width):
			return _picture_refused("the width across the ground is not a number")
		if width <= 0.0:
			return _picture_refused("a picture has to be more than nothing across")
		RasterUnderlayScript.set_width(wanted, width)
	if options.has("rotation_deg"):
		if not RasterUnderlayScript.set_rotation(wanted, float(options["rotation_deg"])):
			return _picture_refused("a picture's turn has to be a number of degrees")
	if options.has("opacity"):
		if not RasterUnderlayScript.set_opacity(wanted, float(options["opacity"])):
			return _picture_refused("how see-through a picture is has to be a number")
	var problem := RasterUnderlayScript.describe_problem(wanted)
	if not problem.is_empty():
		return _picture_refused(problem)
	var stated: Variant = options.get("at", null)
	if stated is Vector2:
		RasterUnderlayScript.move_to(wanted, (stated as Vector2).x, (stated as Vector2).y)
	document.begin_gesture("putting a picture under the drawing")
	var id := document.add_underlay(wanted)
	dirty = true
	var picture := document.underlay(id)
	last_message = "put %s under the drawing, %s across" % [
		String(picture.get("name", "a picture")),
		document.units.format_length(float(picture.get("width_m", 0.0))),
	]
	_refresh_canvas()
	return {"ok": true, "reason": "", "id": id, "picture": picture, "message": last_message}


## Nothing reached the drawing, and the reason is what the drawing's own status line says.
func _picture_refused(reason: String) -> Dictionary:
	last_message = reason
	_refresh_canvas()
	return {"ok": false, "reason": reason, "id": 0, "picture": {}}


## Change a picture already under the drawing: how wide it lies, which way round it is, how
## see-through it is, whether it is shown, or where it lies. One undo step, like any other change to a
## drawing.
##
## The change is worked out on a **copy** and only written across once there is something to record.
## That is not tidiness: `begin_gesture` records the state there and then, so a gesture opened before
## a change that turns out to change nothing would leave an undo step that puts back what is already
## there - worse than no step at all.
func change_underlay(id: int, changes: Dictionary) -> Dictionary:
	if document == null:
		return {"ok": false, "reason": "there is no drawing here", "changed": false, "picture": {}}
	var record := document.underlay(id)
	if record.is_empty():
		return {
			"ok": false, "reason": "there is no picture %d under this drawing" % id,
			"changed": false, "picture": {},
		}
	var wanted: Dictionary = record.duplicate(true)
	if changes.has("width_m"):
		RasterUnderlayScript.set_width(wanted, float(changes["width_m"]))
	if changes.has("rotation_deg"):
		RasterUnderlayScript.set_rotation(wanted, float(changes["rotation_deg"]))
	if changes.has("opacity"):
		RasterUnderlayScript.set_opacity(wanted, float(changes["opacity"]))
	if changes.has("visible"):
		RasterUnderlayScript.set_visible(wanted, bool(changes["visible"]))
	var stated: Variant = changes.get("at", null)
	if stated is Vector2:
		RasterUnderlayScript.move_to(wanted, (stated as Vector2).x, (stated as Vector2).y)
	if wanted == record:
		return {"ok": true, "reason": "", "changed": false, "picture": record}
	document.begin_gesture("moving the picture under the drawing")
	for key: String in wanted:
		record[key] = wanted[key]
	dirty = true
	last_message = RasterUnderlayScript.describe(record, document.units)
	_refresh_canvas()
	return {"ok": true, "reason": "", "changed": true, "picture": record, "message": last_message}


## Take a picture out from under the drawing. Its copy stays in the app's own folder, because an undo
## has to be able to put the picture back and a file thrown away cannot be.
func remove_underlay(id: int) -> bool:
	if document == null:
		return false
	var record := document.underlay(id)
	if record.is_empty():
		return false
	document.begin_gesture("taking the picture out from under the drawing")
	if not document.remove_underlay(id):
		return false
	dirty = true
	last_message = "took %s out from under the drawing" % String(record.get("name", "the picture"))
	_refresh_canvas()
	return true


## What is under the drawing, one row each: the id a button acts on, the words a list shows, the three
## numbers a form edits, and whether the picture can actually be drawn. The words are built here so
## that nothing reading a row has to know the shape of a picture's record.
func underlay_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if document == null:
		return rows
	for record: Dictionary in document.underlays:
		var words := RasterUnderlayScript.describe(record, document.units)
		# A picture whose file has been moved is still on the drawing and cannot be drawn, and the row
		# says so rather than reading as though everything were well.
		var problem := RasterUnderlayScript.describe_problem(record)
		rows.append({
			"id": int(record.get("id", 0)),
			"name": String(record.get("name", "picture")),
			"text": words if problem.is_empty() else "%s - %s" % [words, problem],
			"width_m": float(record.get("width_m", 0.0)),
			"rotation_deg": float(record.get("rotation_deg", 0.0)),
			"opacity": float(record.get("opacity", 1.0)),
			"visible": bool(record.get("visible", true)),
			"usable": problem.is_empty(),
		})
	return rows


## One line saying what is under the drawing, for a panel to lead with.
func underlay_summary() -> String:
	var rows := underlay_rows()
	if rows.is_empty():
		return "nothing is under this drawing"
	return "%d picture%s under the drawing" % [rows.size(), "" if rows.size() == 1 else "s"]


## Where a picture lands when nobody says otherwise: the middle of the drawing's own extent. A scan of
## a site and a design drawn on that site belong on top of each other, and the origin is the middle of
## the site only when somebody has drawn it there.
func _underlay_landing() -> Vector2:
	if document == null:
		return Vector2.ZERO
	var box: Rect2 = document.bounds()
	if box.size == Vector2.ZERO:
		return Vector2.ZERO
	return box.get_center()


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
	document.begin_gesture("labelling the planting")
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
	document.gestures.clear()
	# Nothing was said about this drawing yet either, so the answers the last one gave go with its
	# history. Without this the page would show the two drawings' answers as one run of events.
	said.clear()
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
	# The drawing being left behind is being left behind on purpose - the question was asked and
	# answered - so the copy that was kept of it goes too, rather than being offered on the next launch
	# as work nobody lost.
	AutosaveScript.clear(drawing_path)
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
		# The copy was of work that is now on disk, so it is not a rescue any more. Both identities are
		# cleared: a drawing that was called `untitled` when the copy was taken is filed under
		# `untitled`, and a save is exactly the errand that gives it another name.
		var was := drawing_path
		drawing_path = String(written["path"])
		AutosaveScript.clear(was)
		AutosaveScript.clear(drawing_path)
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
	# The drawing in hand was let go on purpose - the question was asked before this ran - so the copy
	# that was kept of it goes too. The copy of the drawing being *opened* is deliberately left alone:
	# it is a version of that file which is newer than the file, and opening the file is not a decision
	# about the copy. Recovering it is what the File menu is for.
	AutosaveScript.clear(drawing_path)
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
	# boundary would resurrect a drawing the file no longer holds. What the drawing *said* goes with it
	# for the same reason: "shape added" is no longer something this drawing did.
	document.gestures.clear()
	said.clear()
	_rebind_snap()
	if canvas != null:
		canvas.bind_document(document)
	if overlay != null:
		overlay.bind_document(document)
	# Announced last, once the document is fully in place: a listener that re-binds here must find
	# the new drawing rather than a half-installed one.
	document_replaced.emit(document)


# --- a copy kept in case the program stops --------------------------------------------


## Where a copy of the drawing in hand would go, or "" when there is nothing to say - a drawing with no
## name has one identity, `untitled`, and one slot to go with it.
func recovery_path() -> String:
	return AutosaveScript.path_for(drawing_path)


## Keep a copy of the drawing in case the program stops without being asked.
##
## Refuses a drawing that has been saved - there is nothing to recover - and, inside the store, a
## drawing with nothing drawn on it. Says nothing to anybody: nobody asked for this, and a status line
## that announced a write every half minute would be a status line that says nothing.
func keep_a_copy() -> Dictionary:
	if not dirty:
		return {"ok": false, "reason": "the drawing has been saved, so there is nothing to keep", "path": ""}
	return AutosaveScript.write(
		document.to_dict(), drawing_path, project_name, document.gesture_serial()
	)


## The work a session that ended without saving left behind, or an empty dictionary when there is none.
##
## The newest copy that is not of the drawing already on the screen. Two things say "this is the
## drawing in hand": the file it belongs to, and how many gestures it had been through - which is the
## number a copy records so that a live backup is never mistaken for a rescue. Everything else is
## filtered by the store, which passes over a copy whose drawing has since been saved.
func pending_recovery() -> Dictionary:
	var found: Dictionary = AutosaveScript.newest_wanted()
	if found.is_empty():
		return {}
	if String(found.get("drawing_path", "")) == drawing_path \
			and int(found.get("serial", -1)) == document.gesture_serial():
		return {}
	return found


func has_pending_recovery() -> bool:
	return not pending_recovery().is_empty()


## Put the work a session that ended without saving left behind back on the drawing.
##
## An ordinary edit: the drawing it replaces goes onto the undo history under a name that says what
## happened, so recovering the wrong copy is one Ctrl+Z away. The file the copy belonged to is restored
## with it and the drawing is left *unsaved* - what came back is a version of that file which the file
## does not hold, which is the whole reason it was worth keeping.
func recover_pending() -> bool:
	var found: Dictionary = pending_recovery()
	if found.is_empty():
		last_message = "there is no unsaved work to put back"
		_refresh_canvas()
		return false
	var state: Variant = found.get("state", {})
	if not (state is Dictionary):
		last_message = "that copy cannot be put back"
		_refresh_canvas()
		return false
	var recovered := DocumentScript.from_dict(state)
	if recovered == null:
		last_message = "that copy cannot be put back"
		_refresh_canvas()
		return false
	var before: Dictionary = document.snapshot()
	_bind_document(recovered)
	if not before.is_empty():
		# Onto the *restored* drawing's history, which is empty because it is a different document:
		# what comes back on undo is the drawing that was on the screen a moment ago, and the gesture
		# says what that act was.
		document.record_gesture(before, "recovering unsaved work")
	drawing_path = String(found.get("drawing_path", ""))
	# The history belongs to the drawing, so it comes with it - a named revision recorded before the
	# copy was taken is a revision of the file this drawing belongs to.
	revisions = StoreScript.read_revisions(drawing_path)
	dirty = true
	# The copy has been taken up, so it is no longer waiting - and the drawing is unsaved from this
	# moment. A fresh copy of exactly what came back goes down at once rather than half a minute later,
	# because the stretch between recovering and the next copy is the one moment when a second crash
	# would be worst. Same identity, so it replaces the copy that was just read.
	keep_a_copy()
	last_message = "recovered %s" % AutosaveScript.describe(found)
	_refresh_canvas()
	return true


## Say no to the work a session that ended without saving left behind. The copy is removed rather than
## merely passed over, because a question a person has answered must not be asked again.
func discard_pending() -> bool:
	var found: Dictionary = pending_recovery()
	if found.is_empty():
		return false
	var removed: bool = AutosaveScript.clear(String(found.get("drawing_path", "")))
	if removed:
		last_message = "threw the recovered copy away"
	return removed


# --- the named revisions of the drawing -----------------------------------------------


## Record the drawing as it stands, under a message. The one act a revision log needs, and the only
## thing a designer has to do: everything else - the time, the author, the size of the drawing, the
## difference from the revision before - is read off what it keeps.
##
## A drawing that has never been saved has nowhere to keep its history, so the revision is held in
## memory until the drawing is saved; the message says so rather than failing, because the designer has
## done their part and the file name is a separate errand.
func capture_revision(message: String = "", author: String = "") -> Dictionary:
	# The gesture the drawing has been through is read *here*, because it is the one thing about a
	# revision its own snapshot cannot tell anyone: the history that knows it is the drawing's.
	var record: Dictionary = revisions.capture(
		document.to_dict(), message, author, document.gesture_serial()
	)
	var written: Dictionary = StoreScript.write_revisions(revisions, drawing_path)
	if bool(written["ok"]):
		last_message = "recorded %s" % revisions.describe(revisions.count() - 1)
	else:
		last_message = "recorded in memory only: %s" % String(written["reason"])
	_refresh_canvas()
	return record


## One row per revision, as anything listing them needs it, plus the difference from the revision
## before it - which is the question a history exists to answer, and which is cheap here because a
## snapshot is five lines' work to compare - and how much has happened *since* it, which is the one
## thing that joins the named history to the undo history.
func revision_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for index in revisions.count():
		var row: Dictionary = revisions.record_at(index)
		var changes: Dictionary = revisions.diff(index - 1, index) if index > 0 else {}
		row["description"] = revisions.describe(index)
		row["change"] = DraftRevisionLog.describe_diff(changes) if not changes.is_empty() else ""
		row["since"] = gestures_since_text(index)
		rows.append(row)
	return rows


## How much has been done to the drawing since a revision was taken, in words. The revision kept the
## gesture it was taken at and the drawing knows how many it has been through, so this is a difference
## of two numbers rather than a guess.
##
## "Nothing has been done" and "not known" are different claims, and a revision recorded before gestures
## were counted says which one it is rather than reading as a drawing nobody has touched.
func gestures_since_text(index: int) -> String:
	if document == null or not revisions.is_valid(index):
		return ""
	if int(revisions.record_at(index).get("serial", 0)) <= 0:
		return "recorded before gestures were counted"
	var count: int = revisions.gestures_since(index, document.gesture_serial())
	if count == 0:
		return "nothing has been done to the drawing since"
	return "%d gesture%s since" % [count, "" if count == 1 else "s"]


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
		# Onto the *restored* drawing's history, which is empty because it is a different document:
		# what comes back on undo is the drawing that was on screen a moment ago, and the gesture says
		# what that act was.
		document.record_gesture(before, "putting a revision back")
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
	_rebind_snap()
	dirty = true
	_refresh_canvas()
	changed.emit()


## Tell the snap engine what the drawing holds, if there is one.
##
## A controller can be built without a snap engine - a test, or a headless run that only measures -
## and everything else in this file tolerates that. One door, so the tolerance is not remembered at
## six call sites and forgotten at the seventh: `restore_revision` and `import_dxf` both crashed on
## exactly that before they called this.
func _rebind_snap() -> void:
	if snap != null:
		snap.bind(document.entities())

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