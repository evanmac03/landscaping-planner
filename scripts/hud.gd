class_name PlannerHud
extends CanvasLayer
## The planner's heads-up display: which view you are in, what the controls do,
## and the drafting aids on the overlay layer.

const EDIT_HINTS := "Left-drag: move a plant     "
const HINTS_2D := EDIT_HINTS + "Right-drag: pan     Wheel: zoom     W A S D: pan     F: fit     Tab: 3D view     G: ground"
const HINTS_3D := EDIT_HINTS + "Right-drag: pan     Wheel: zoom     W A S D: pan     F: fit     Tab: 2D plan     G: ground"
const HINTS_GROUND := "W A S D: walk     Shift: run     Mouse: look     Arrows: look     Esc: free cursor     G: back to overhead"

## The drawing tools, in the order the number keys select them, with the wording
## the legend introduces each by.
##
## The list is here rather than in the input map because "1" is a key and "line"
## is a word, and nothing can derive one from the other. The *key* is read from
## the input map, which is the half that can be derived - and a legend naming a
## key that is not bound sends the reader to a key that does nothing, so that half
## is the half worth deriving.
const DRAFTING_TOOLS: Array = [
	[&"draft_line", "line"],
	[&"draft_polyline", "polyline"],
	[&"draft_rect", "rectangle"],
	[&"draft_circle", "circle"],
	[&"draft_arc", "arc"],
	[&"draft_measure", "measure"],
	[&"draft_dimension", "aligned dim"],
	[&"draft_dimension_linear", "linear dim"],
	[&"draft_dimension_radius", "radial dim"],
]

## The keys that are not a tool, in the order a hand meets them: what to do when
## the shape is right, and what to do when it is not.
const DRAFTING_COMMANDS: Array = [
	[&"draft_finish", "finish"],
	[&"draft_close", "close"],
	[&"draft_undo_point", "drop a point"],
	[&"draft_cancel", "cancel"],
	[&"draft_undo", "undo"],
	[&"draft_plot", "plot"],
	[&"draft_dimension_style", "dimension standard"],
]

## Key names worth shortening so a legend line stays a line.
const SHORT_KEY_NAMES := {"Escape": "Esc", "Return": "Enter"}

## How many entries share a line before the legend wraps.
const DRAFTING_TOOLS_PER_ROW := 5
const DRAFTING_COMMANDS_PER_ROW := 4
const DRAFTING_ROW_GAP := "    "

@export var view_controller: ViewController

@onready var mode_label: Label = %ModeLabel
@onready var toggle_button: Button = %ToggleButton
@onready var ground_button: Button = %GroundButton
@onready var fit_button: Button = %FitButton
@onready var hints_label: Label = %HintsLabel
@onready var overlay: HudOverlay = %Overlay
@onready var draft_hints: PanelContainer = %DraftHints
@onready var draft_hints_label: Label = %DraftHintsLabel


func _ready() -> void:
	if view_controller == null:
		push_error("PlannerHud: view_controller must be assigned.")
		return
	view_controller.view_mode_changed.connect(_on_view_mode_changed)
	view_controller.transition_started.connect(_on_transition_started)
	view_controller.transition_finished.connect(_on_transition_finished)
	toggle_button.pressed.connect(view_controller.toggle_overhead)
	ground_button.pressed.connect(view_controller.toggle_ground)
	fit_button.pressed.connect(view_controller.fit_plan_to_yard)
	draft_hints_label.text = drafting_hints()
	_on_view_mode_changed(view_controller.mode)


func _process(_delta: float) -> void:
	if view_controller == null:
		return
	var viewport_height: float = get_viewport().get_visible_rect().size.y
	# Both overhead views share one zoom, so one conversion serves them both.
	overlay.set_pixels_per_metre(
		ViewMath.pixels_per_metre(viewport_height, view_controller.plan_size)
	)
	# Arming the tools happens on a key press inside the view controller, which has
	# no signal for it, and it is one bool: reading it is cheaper than routing it.
	# The legend goes away on the ground, where the tools do nothing.
	draft_hints.visible = view_controller.is_drafting() \
		and view_controller.mode != ViewController.ViewMode.GROUND


func _on_view_mode_changed(new_mode: ViewController.ViewMode) -> void:
	var overhead: bool = new_mode != ViewController.ViewMode.GROUND
	var flat: bool = new_mode == ViewController.ViewMode.PLAN_2D
	if flat:
		mode_label.text = "2D PLAN"
		mode_label.add_theme_color_override("font_color", Color(0.6, 0.85, 0.52))
	elif overhead:
		mode_label.text = "3D OVERHEAD"
		mode_label.add_theme_color_override("font_color", Color(0.62, 0.78, 0.95))
	else:
		mode_label.text = "GROUND VIEW"
		mode_label.add_theme_color_override("font_color", Color(0.85, 0.78, 0.5))
	toggle_button.text = "3D view  (Tab)" if flat else "2D plan  (Tab)"
	toggle_button.visible = overhead
	fit_button.visible = overhead
	ground_button.text = "Ground view  (G)" if overhead else "Back to overhead  (G)"
	hints_label.text = HINTS_2D if flat else (HINTS_3D if overhead else HINTS_GROUND)
	overlay.set_mode(new_mode)


func _on_transition_started(_to_ground: bool) -> void:
	overlay.set_transitioning(true)


func _on_transition_finished(_to_ground: bool) -> void:
	overlay.set_transitioning(false)


# --- the drafting legend --------------------------------------------------------------


## The legend, line by line. Kept as lines rather than as one string so that a test
## can check every entry against the binding it claims, which is the only way a
## legend stays true.
static func drafting_rows() -> Array[String]:
	var rows: Array[String] = []
	rows.append("%s leaves the drawing tools" % _key_label(&"draft_mode"))
	rows.append_array(_wrap(_entries(DRAFTING_TOOLS), DRAFTING_TOOLS_PER_ROW))
	rows.append_array(_wrap(_entries(DRAFTING_COMMANDS), DRAFTING_COMMANDS_PER_ROW))
	return rows


## The same, as one block of text for a label.
static func drafting_hints() -> String:
	return "\n".join(PackedStringArray(drafting_rows()))


## Action-and-wording pairs as the legend prints them. An action bound to nothing
## is left out rather than printed with a blank key, so an unbound tool is a
## missing line instead of a line saying nothing.
static func _entries(pairs: Array) -> Array[String]:
	var out: Array[String] = []
	for pair: Array in pairs:
		var key := _key_label(pair[0])
		if key == "":
			continue
		out.append("%s %s" % [key, pair[1]])
	return out


static func _wrap(entries: Array[String], per_row: int) -> Array[String]:
	var rows: Array[String] = []
	for start in range(0, entries.size(), per_row):
		rows.append(DRAFTING_ROW_GAP.join(PackedStringArray(
			entries.slice(start, start + per_row)
		)))
	return rows


## The key an action is bound to, or "" when it is bound to nothing.
##
## Modifiers are included, so Ctrl+Z does not print as a bare Z, which would be a
## different command. The name comes from the event rather than from a table here,
## so the legend follows a rebinding.
static func _key_label(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""
	for event: InputEvent in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key == null:
			continue
		# An action binds by physical keycode or by keycode depending on how it was
		# authored, and which one is set differs between the number keys and the
		# named ones, so both have to be looked at.
		var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
		if code == 0:
			continue
		var rendered := OS.get_keycode_string(code)
		var shortened: String = SHORT_KEY_NAMES.get(rendered, rendered)
		return ("Ctrl+" + shortened) if key.ctrl_pressed else shortened
	return ""
