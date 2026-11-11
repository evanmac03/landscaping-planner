class_name SnapWindow
extends Window
## The snapping settings, on a page: what the cursor is allowed to snap to, and the constraints that
## hold it straight (specification REQ 2.3).
##
## A `Window` like the other pages, for the two reasons they are: it holds switches a person works,
## and a `Window` owns its own input, so nothing here can take the drawing's keys.
##
## The page holds no state and no arithmetic. Every switch writes through the controller's own
## setters, and every control is then set again from `snap_state()`, so the page and a keyboard
## toggle can never drift apart: this is a view of the settings, not a copy of them. The controls are
## set with `set_pressed_no_signal`, which is what stops a refresh from looking like a person
## pressing eight checkboxes and writing the same settings straight back.

const SnapScript := preload("res://scripts/draft/snap_engine.gd")

## The window was closed by its own close button.
signal closed()

## Wide enough for a snap's name and its checkbox in one column, and shorter than the 900-pixel screen
## the other pages are sized for once the window's own title bar is counted. 600 is this page's own
## number and the one it goes back to: the switches and their captions came to 627 while every line here
## was hand-built, which is why it spent a while at 640, and they come to 596 now that the captions, the
## headings and the status line are the shared chrome's.
const SIZE := Vector2i(560, 600)
const CAPTION_MODES := "what the cursor will snap to"
const CAPTION_HOLD := "how it is held straight"

## The polar increments the page offers, in degrees. Fifteen is the fine one a person uses to keep a
## run just off the axes; ninety makes polar behave like ortho with a label on it.
const POLAR_STEPS: Array[float] = [15.0, 30.0, 45.0, 90.0]

## The drafting controller whose settings this page shows and sets. Null is allowed: a page with
## nothing bound says so and switches nothing.
var controller: Variant = null

var _column: VBoxContainer = null
var _master: CheckButton = null
var _modes: Dictionary = {}
var _ortho: CheckBox = null
var _polar: CheckBox = null
var _polar_step: OptionButton = null
var _grid: CheckBox = null
var _grid_step: SpinBox = null
var _status: Label = null


func _init() -> void:
	title = "Snapping"
	min_size = SIZE
	exclusive = false
	close_requested.connect(_on_close_requested)


func _ready() -> void:
	if _column == null:
		build()


# --- building -----------------------------------------------------------------------------------


## Build the whole window by hand. Idempotent, and callable off-tree so a test can drive the same
## switches the program shows.
func build() -> void:
	if _column != null:
		return
	_column = PageChrome.column(self, 4)

	_master = CheckButton.new()
	_master.name = "SnapToggle"
	_master.text = "Snap to what is already drawn"
	_master.focus_mode = Control.FOCUS_NONE
	_master.toggled.connect(_on_master_toggled)
	_column.add_child(_master)

	_column.add_child(PageChrome.subheading(CAPTION_MODES))
	for snap_mode: int in mode_order():
		var box := CheckBox.new()
		box.name = "Mode%s" % String(mode_label(snap_mode)).capitalize()
		box.text = mode_label(snap_mode)
		box.focus_mode = Control.FOCUS_NONE
		box.toggled.connect(_on_mode_toggled.bind(snap_mode))
		_column.add_child(box)
		_modes[snap_mode] = box

	_column.add_child(PageChrome.subheading(CAPTION_HOLD))
	_ortho = CheckBox.new()
	_ortho.name = "Ortho"
	_ortho.text = "Ortho: hold to the axes from the last point"
	_ortho.focus_mode = Control.FOCUS_NONE
	_ortho.toggled.connect(_on_ortho_toggled)
	_column.add_child(_ortho)

	_polar = CheckBox.new()
	_polar.name = "Polar"
	_polar.text = "Polar tracking"
	_polar.focus_mode = Control.FOCUS_NONE
	_polar.toggled.connect(_on_polar_toggled)
	_column.add_child(_polar)
	_polar_step = OptionButton.new()
	_polar_step.name = "PolarStep"
	_polar_step.focus_mode = Control.FOCUS_NONE
	for degrees: float in POLAR_STEPS:
		_polar_step.add_item("%d°" % int(degrees))
	_polar_step.item_selected.connect(_on_polar_step_selected)
	_column.add_child(PageChrome.labelled("every", _polar_step))

	_grid = CheckBox.new()
	_grid.name = "GridSnap"
	_grid.text = "Snap to a grid"
	_grid.focus_mode = Control.FOCUS_NONE
	_grid.toggled.connect(_on_grid_toggled)
	_column.add_child(_grid)
	_grid_step = SpinBox.new()
	_grid_step.name = "GridStep"
	# The pitch is offered on a 5 cm step, and the minimum is that same step so the values a person
	# gets are whole steps of it. A minimum that is *off* the step - 0.01 against a 0.05 step - makes
	# Godot round every value onto min + n*step, and a 0.5 m grid silently becomes 0.51.
	_grid_step.min_value = 0.05
	_grid_step.max_value = 100.0
	_grid_step.step = 0.05
	_grid_step.suffix = " m"
	_grid_step.value_changed.connect(_on_grid_step_changed)
	_column.add_child(PageChrome.labelled("grid pitch", _grid_step))

	var run_row := HBoxContainer.new()
	run_row.name = "RunRow"
	run_row.add_theme_constant_override("separation", 6)
	_column.add_child(run_row)
	var close_button := PageChrome.button("Close")
	close_button.name = "Close"
	close_button.pressed.connect(_on_close_requested)
	run_row.add_child(close_button)

	_status = PageChrome.status()
	_column.add_child(_status)

	refresh()


## Point the page at a controller and follow its settings from now on. Called again with a different
## controller, the old one is let go of rather than left connected to a page it no longer owns.
func bind(draft: Variant) -> void:
	if controller != null and controller.snap_changed.is_connected(refresh):
		controller.snap_changed.disconnect(refresh)
	controller = draft
	if controller != null:
		controller.snap_changed.connect(refresh)
	refresh()


# --- what it shows ------------------------------------------------------------------------------


## Read the settings and set every control to match.
func refresh() -> void:
	if _column == null:
		return
	var state: Dictionary = controller.snap_state() if controller != null else {}
	var master_on: bool = bool(state.get("snapping", false))
	_master.set_pressed_no_signal(master_on)
	_master.disabled = controller == null
	var modes: Dictionary = state.get("modes", {})
	for snap_mode: int in _modes:
		var box: CheckBox = _modes[snap_mode]
		box.set_pressed_no_signal(bool(modes.get(snap_mode, false)))
		# With the master switch off every mode is dormant, and a page that let them look live would
		# be describing a snap that is not happening.
		box.disabled = controller == null or not master_on
	_ortho.set_pressed_no_signal(bool(state.get("ortho", false)))
	_polar.set_pressed_no_signal(bool(state.get("polar", false)))
	_grid.set_pressed_no_signal(bool(state.get("grid", false)))
	_select_polar_step(float(state.get("polar_step", 45.0)))
	_grid_step.set_value_no_signal(float(state.get("grid_step", 0.5)))
	_status.text = _state_words(state)


func status_text() -> String:
	return _status.text if _status != null else ""


func master_button() -> CheckButton:
	return _master


func mode_button(snap_mode: int) -> CheckBox:
	return _modes.get(snap_mode)


func ortho_button() -> CheckBox:
	return _ortho


func polar_button() -> CheckBox:
	return _polar


func polar_step_field() -> OptionButton:
	return _polar_step


func grid_button() -> CheckBox:
	return _grid


func grid_step_field() -> SpinBox:
	return _grid_step


## The object snaps the page offers, in the engine's own priority order. Read from `PRIORITY` rather
## than restated, so a mode added to the engine appears here without this file being touched; grid is
## left out because it has a switch of its own below.
static func mode_order() -> Array:
	var out: Array = []
	for snap_mode: int in SnapScript.PRIORITY:
		if snap_mode != SnapScript.Mode.GRID:
			out.append(snap_mode)
	return out


## A mode's own name, from the engine's table, so the page never invents a second vocabulary.
static func mode_label(snap_mode: int) -> String:
	return String(SnapScript.LABELS.get(snap_mode, str(snap_mode)))


# --- what it does -------------------------------------------------------------------------------


func _on_master_toggled(on: bool) -> void:
	if controller == null:
		return
	controller.set_snapping(on)


func _on_mode_toggled(on: bool, snap_mode: int) -> void:
	if controller == null:
		return
	controller.set_snap_mode(snap_mode, on)


func _on_ortho_toggled(on: bool) -> void:
	if controller == null:
		return
	controller.set_ortho(on)


func _on_polar_toggled(on: bool) -> void:
	if controller == null:
		return
	controller.set_polar(on)


func _on_grid_toggled(on: bool) -> void:
	if controller == null:
		return
	controller.set_grid_snap(on)


func _on_grid_step_changed(metres: float) -> void:
	if controller == null:
		return
	controller.set_grid_step(metres)


func _on_polar_step_selected(index: int) -> void:
	if controller == null or index < 0 or index >= POLAR_STEPS.size():
		return
	controller.set_polar_step_degrees(POLAR_STEPS[index])


func _on_close_requested() -> void:
	hide()
	closed.emit()


# --- the small jobs -----------------------------------------------------------------------------


## One line saying what the cursor is actually allowed to do, which is the question the page exists
## to answer: how many object snaps are live, and which constraints are holding the point.
func _state_words(state: Dictionary) -> String:
	if controller == null:
		return "There is nothing here to snap."
	if not bool(state.get("snapping", false)):
		return "Snapping is off: a pick lands exactly where the pointer is."
	var live := 0
	var modes: Dictionary = state.get("modes", {})
	for snap_mode: int in modes:
		if snap_mode != SnapScript.Mode.GRID and bool(modes[snap_mode]):
			live += 1
	var parts: Array[String] = ["%d object snap%s live" % [live, "" if live == 1 else "s"]]
	if bool(state.get("ortho", false)):
		parts.append("ortho")
	if bool(state.get("polar", false)):
		parts.append("polar every %d°" % int(round(float(state.get("polar_step", 0.0)))))
	if bool(state.get("grid", false)):
		parts.append("grid at %s m" % String.num(float(state.get("grid_step", 0.0)), 2))
	return "  ·  ".join(parts)


func _select_polar_step(degrees: float) -> void:
	var index: int = POLAR_STEPS.find(degrees)
	if index >= 0:
		_polar_step.select(index)


