class_name WalkWindow
extends Window
## A walk-through of the garden, on a page: the places a client is shown, and a button that walks
## them (specification §9.2).
##
## A `Window` like the other pages, for the same two reasons they are: it has a list a person reads
## and buttons they press, and a `Window` owns its own input, so nothing here can take the drawing's
## keys. Every button is `FOCUS_NONE`.
##
## The page holds no arithmetic. The route - its stops, its dwells, its duration - is `WalkRoute`'s,
## and the clock and the one camera transform are `VisWalkDirector`'s. What this page is, is the
## button, the list, and the frame that steps the clock.

const RouteScript := preload("res://scripts/vis/walk_route.gd")
const DirectorScript := preload("res://scripts/vis/walk_director.gd")

## The window was closed by its own close button.
signal closed()
## The walk started, stopped, or reached its end, so anything reporting on it is now stale.
signal walk_changed()

## Wide enough for a stop's row and its words, shorter than the 900-pixel screen the other pages
## are sized for once the window's own title bar is counted.
const SIZE := Vector2i(780, 620)
## What the stops list is introduced by.
const CAPTION := "the places this walk-through visits"

## The route being walked, and the clock that walks it. Made here rather than passed in, so a page
## with no presenter still holds a walk and can say why it cannot be walked.
var route: WalkRoute = null
var walk: DirectorScript = null
## The presentation director the walk takes its camera from, when there is one. Null is allowed.
var presenter: Node3D = null
## The camera the walk moves, read from the presenter or stated outright.
var camera: Camera3D = null

var _column: VBoxContainer = null
var _summary: Label = null
var _stops: ItemList = null
var _play: Button = null
var _stop_button: Button = null
var _status: Label = null


func _init() -> void:
	title = "Walk-through"
	min_size = SIZE
	exclusive = false
	close_requested.connect(_on_close_requested)


func _ready() -> void:
	if _column == null:
		build()


# --- building -----------------------------------------------------------------------------------


## Build the whole window by hand. Idempotent, and callable off-tree so a test can drive the same
## controls the program shows.
func build() -> void:
	if _column != null:
		return
	_column = VBoxContainer.new()
	_column.name = "Column"
	_column.set_anchors_preset(Control.PRESET_FULL_RECT)
	_column.add_theme_constant_override("separation", 6)
	add_child(_column)

	_summary = Label.new()
	_summary.name = "Summary"
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.custom_minimum_size = Vector2(0, 20)
	_column.add_child(_summary)

	_column.add_child(_heading(CAPTION))
	_stops = ItemList.new()
	_stops.name = "Stops"
	_stops.focus_mode = Control.FOCUS_NONE
	_stops.custom_minimum_size = Vector2(0, 160)
	_column.add_child(_stops)

	var run_row := HBoxContainer.new()
	run_row.name = "RunRow"
	run_row.add_theme_constant_override("separation", 6)
	_column.add_child(run_row)
	_play = Button.new()
	_play.name = "Play"
	_play.focus_mode = Control.FOCUS_NONE
	_play.text = "Walk it"
	_play.pressed.connect(_on_play_pressed)
	run_row.add_child(_play)
	_stop_button = Button.new()
	_stop_button.name = "Stop"
	_stop_button.focus_mode = Control.FOCUS_NONE
	_stop_button.text = "Stop"
	_stop_button.pressed.connect(_on_stop_pressed)
	run_row.add_child(_stop_button)
	var restart_button := Button.new()
	restart_button.name = "Restart"
	restart_button.focus_mode = Control.FOCUS_NONE
	restart_button.text = "From the top"
	restart_button.pressed.connect(_on_restart_pressed)
	run_row.add_child(restart_button)
	var close_button := Button.new()
	close_button.name = "Close"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.text = "Close"
	close_button.pressed.connect(_on_close_requested)
	run_row.add_child(close_button)

	_status = Label.new()
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 44)
	_column.add_child(_status)

	refresh()


## Point the page at the presentation director: the walk takes that director's camera and builds a
## route of whatever garden its yard holds. A presenter with no yard keeps whatever route it had.
func bind(new_presenter: Node3D) -> void:
	presenter = new_presenter
	camera = _camera_of(new_presenter)
	var bounds: Rect2 = _yard_bounds(new_presenter)
	if bounds.size.x > 0.0 and bounds.size.y > 0.0:
		set_route(RouteScript.for_yard(bounds), camera)
	else:
		refresh()


## Walk a particular route with a particular camera. The route is the page's own to hold, which is
## what lets a walk be proved with no presenter - and no window - at all.
func set_route(new_route: WalkRoute, new_camera: Camera3D = null) -> void:
	route = new_route
	camera = new_camera
	walk = DirectorScript.new()
	walk.bind(route)
	refresh()


# --- what it shows ------------------------------------------------------------------------------


## Read the walk again and put what it says on the page: the stops, the state, the buttons.
func refresh() -> void:
	if _stops == null:
		return
	_fill_stops()
	_update_summary()
	_update_buttons()


func summary_text() -> String:
	return _summary.text if _summary != null else ""


func status_text() -> String:
	return _status.text if _status != null else ""


## The stop rows as the list shows them, for a test.
func stop_rows() -> Array[String]:
	var out: Array[String] = []
	if _stops == null:
		return out
	for index in _stops.item_count:
		out.append(_stops.get_item_text(index))
	return out


func play_button() -> Button:
	return _play


func stop_button() -> Button:
	return _stop_button


# --- what it does -------------------------------------------------------------------------------


## Start the walk. False - and the route's own reason said on the page - when there is nothing to
## walk: no route, or a route of fewer than two stops (REQ-V9.5).
func play() -> bool:
	if walk == null:
		say("there is no walk-through here")
		return false
	if not walk.play():
		say(route.refusal() if route != null and route.refusal() != "" else "this walk cannot be started")
		refresh()
		return false
	say("walking: %s" % route.describe())
	walk_changed.emit()
	refresh()
	return true


## Stand still, where the walk has got to.
func stop() -> void:
	if walk == null:
		return
	walk.stop()
	say("stopped %.0f%% of the way in" % (walk.progress() * 100.0))
	walk_changed.emit()
	refresh()


## Back to the first stop. Keeps playing when it was playing.
func restart() -> void:
	if walk == null:
		return
	walk.restart()
	say("from the top again")
	walk_changed.emit()
	refresh()


## Whether the walk is running right now.
func is_playing() -> bool:
	return walk != null and walk.playing


## The walk in one line, for a status bar or a test.
func describe() -> String:
	if walk == null:
		return "no walk-through is loaded"
	return walk.describe()


func say(words: String) -> void:
	if _status != null:
		_status.text = words


# --- stepping the clock -------------------------------------------------------------------------


func _process(delta: float) -> void:
	if walk == null or not walk.playing:
		return
	var running: bool = walk.advance(delta)
	if camera != null:
		walk.apply_to(camera)
	# Only the state line moves while the clock runs: the stops cannot have changed mid-walk.
	_update_summary()
	if not running:
		say("the walk is finished: %s" % route.describe())
		_update_buttons()
		walk_changed.emit()


func _on_play_pressed() -> void:
	play()


func _on_stop_pressed() -> void:
	stop()


func _on_restart_pressed() -> void:
	restart()


func _on_close_requested() -> void:
	stop()
	hide()
	closed.emit()


# --- reading the presenter ----------------------------------------------------------------------


func _camera_of(node: Node3D) -> Camera3D:
	if node == null:
		return null
	var orbit: Object = node.get("orbit")
	if orbit == null:
		return null
	return orbit.get("camera") as Camera3D


func _yard_bounds(node: Node3D) -> Rect2:
	if node == null:
		return Rect2()
	var yard: Object = node.get("yard")
	if yard == null or not yard.has_method("get_bounds"):
		return Rect2()
	return yard.get_bounds()


# --- the small jobs -----------------------------------------------------------------------------


func _fill_stops() -> void:
	_stops.clear()
	if route == null:
		return
	for place: Dictionary in route.stops():
		var at: Vector3 = place["at"]
		_stops.add_item("%s · (%.1f, %.1f, %.1f) · %s s" % [
			String(place["name"]), at.x, at.y, at.z, String.num(float(place["dwell"]), 1),
		])


func _update_summary() -> void:
	if _summary == null:
		return
	if route == null:
		_summary.text = "There is no walk-through here."
		return
	if route.refusal() != "":
		_summary.text = route.refusal()
		return
	_summary.text = "%s - %s" % [route.describe(), describe()]


func _update_buttons() -> void:
	if _play == null or _stop_button == null:
		return
	var walkable: bool = route != null and route.refusal() == ""
	_play.disabled = not walkable or is_playing()
	_stop_button.disabled = not is_playing()


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label