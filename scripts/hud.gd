class_name PlannerHud
extends CanvasLayer
## The planner's heads-up display: which view you are in, what the controls do,
## the drawing palette, and the drafting aids on the overlay layer.

const DraftToolScript := preload("res://scripts/draft/draft_tool.gd")
const DraftControllerScript := preload("res://scripts/draft/draft_controller.gd")

const EDIT_HINTS := "Left-drag: move a plant     "
## The key that swaps the two overhead views is written as a token and filled in
## from the input map: it is the one key in these lines that gets rebound, and a
## hint naming a key that no longer switches anything is the same class of lie as a
## legend entry that does nothing.
const VIEW_KEY_TOKEN := "%VIEW%"
const HINTS_2D := EDIT_HINTS + "Right-drag: pan     Wheel: zoom     W A S D: pan     F: fit     %VIEW%: 3D view     G: ground"
const HINTS_3D := EDIT_HINTS + "Right-drag: pan     Wheel: zoom     W A S D: pan     F: fit     %VIEW%: 2D plan     G: ground"
const HINTS_GROUND := "W A S D: walk     Shift: run     Mouse: look     Arrows: look     Esc: free cursor     G: back to overhead"

## The drawing tools, in the order the number keys select them: the action that
## selects one, the wording it is introduced by, and the tool it puts in your hand.
##
## One table serves both the key legend and the palette, so a tool cannot appear in
## one and be missing from the other, and neither can describe a different tool from
## the one the key selects.
##
## The *key* is read from the input map rather than written here, which is the half
## that can be derived - and a legend naming a key that is not bound sends the reader
## to a key that does nothing, so that half is the half worth deriving.
const DRAFTING_TOOLS: Array = [
	[&"draft_line", "line", DraftToolScript.Kind.LINE],
	[&"draft_polyline", "polyline", DraftToolScript.Kind.POLYLINE],
	[&"draft_rect", "rectangle", DraftToolScript.Kind.RECTANGLE],
	[&"draft_circle", "circle", DraftToolScript.Kind.CIRCLE],
	[&"draft_arc", "arc", DraftToolScript.Kind.ARC],
	[&"draft_measure", "measure", DraftToolScript.Kind.MEASURE],
	[&"draft_dimension", "aligned dim", DraftToolScript.Kind.DIMENSION],
	[&"draft_dimension_linear", "linear dim", DraftToolScript.Kind.DIMENSION_LINEAR],
	[&"draft_dimension_radius", "radial dim", DraftToolScript.Kind.DIMENSION_RADIUS],
]

## The keys that are not a tool, in the order a hand meets them: what to do when
## the shape is right, and what to do when it is not.
const DRAFTING_COMMANDS: Array = [
	[&"draft_finish", "finish"],
	[&"draft_close", "close"],
	[&"draft_undo_point", "drop a point"],
	[&"draft_cancel", "cancel"],
	[&"draft_undo", "undo"],
	[&"draft_redo", "redo"],
	[&"draft_plot", "plot"],
	[&"draft_dimension_style", "dimension standard"],
]

## Key names worth shortening so a legend line stays a line.
const SHORT_KEY_NAMES := {"Escape": "Esc", "Return": "Enter"}

## How many entries share a line before the legend wraps.
const DRAFTING_TOOLS_PER_ROW := 5
const DRAFTING_COMMANDS_PER_ROW := 4
const DRAFTING_ROW_GAP := "    "

## The palette: three tools across, which is what makes it a palette rather than a
## list of nine, and a cell wide enough for the longest tool name on one line with
## its key underneath.
const PALETTE_COLUMNS := 3
const PALETTE_CELL_WIDTH := 86.0

@export var view_controller: ViewController

@onready var mode_label: Label = %ModeLabel
@onready var toggle_button: Button = %ToggleButton
@onready var ground_button: Button = %GroundButton
@onready var fit_button: Button = %FitButton
@onready var hints_label: Label = %HintsLabel
@onready var overlay: HudOverlay = %Overlay
@onready var draft_hints: PanelContainer = %DraftHints
@onready var draft_hints_label: Label = %DraftHintsLabel
@onready var palette: PanelContainer = %Palette
@onready var palette_column: VBoxContainer = %PaletteColumn

## The drafting controller, when the scene has one. Held because the palette drives
## it and the legend reports on it.
var _draft: DraftControllerScript = null
## The controls built by _build_palette, kept so the refresh can set them.
var _arm_button: CheckButton = null
var _tool_buttons: Array[Button] = []
var _layer_option: OptionButton = null
var _layer_names: Array[StringName] = []
var _style_button: Button = null
## What the palette was last drawn to match, so a check every frame does not
## restate state that has not moved.
var _palette_state: String = ""


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
	_build_palette()
	_on_view_mode_changed(view_controller.mode)
	# Last, so it covers the buttons the palette just built as well as the ones in
	# the scene: a button that holds the keyboard takes the drawing keys with it.
	release_keyboard_focus(self)


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
	# The legend and the palette both go away on the ground, where the tools do
	# nothing at all.
	var overhead: bool = view_controller.mode != ViewController.ViewMode.GROUND
	draft_hints.visible = overhead and view_controller.is_drafting()
	if palette.get_child_count() > 0:
		palette.visible = overhead
		_refresh_palette()


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
	var switch_key := _key_label(&"toggle_view")
	toggle_button.text = "3D view  (%s)" % switch_key if flat else "2D plan  (%s)" % switch_key
	toggle_button.visible = overhead
	fit_button.visible = overhead
	ground_button.text = "Ground view  (G)" if overhead else "Back to overhead  (G)"
	hints_label.text = _hints_for(new_mode)
	overlay.set_mode(new_mode)


## The control hints for a view, with the key that swaps the overhead views filled
## in from the input map.
static func _hints_for(view_mode: int) -> String:
	if view_mode == ViewController.ViewMode.GROUND:
		return HINTS_GROUND
	var template := HINTS_2D \
		if view_mode == ViewController.ViewMode.PLAN_2D else HINTS_3D
	return template.replace(VIEW_KEY_TOKEN, _key_label(&"toggle_view"))


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
## The *first* event an action lists is the one it is introduced by, so the order of
## an action's events is what decides which key gets advertised.
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


# --- the drawing palette --------------------------------------------------------------


## Build the palette's controls in code rather than in the scene.
##
## They are nine near-identical buttons and a handful of rows, every one of them
## derived from the tables the legend already uses, so a scene file would be a third
## copy of that list to keep in step. Built here, the palette is described once and
## its buttons exist because the tools do.
func _build_palette() -> void:
	_draft = view_controller.draft_controller()
	if _draft == null or palette_column == null:
		return

	_arm_button = CheckButton.new()
	_arm_button.name = "ArmButton"
	_arm_button.text = "Drawing (%s)" % _key_label(&"draft_mode")
	_arm_button.tooltip_text = "Arm the drawing tools, and put them away again"
	_arm_button.toggled.connect(_on_arm_toggled)
	palette_column.add_child(_arm_button)

	var grid := GridContainer.new()
	grid.name = "Tools"
	grid.columns = PALETTE_COLUMNS
	palette_column.add_child(grid)
	for pair: Array in DRAFTING_TOOLS:
		var kind: int = pair[2]
		var button := Button.new()
		# Named after the action it stands for, so the node tree says what each
		# button does rather than "Button17".
		button.name = String(pair[0])
		button.text = palette_label(pair)
		button.tooltip_text = "Draw a %s" % String(pair[1])
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(PALETTE_CELL_WIDTH, 0.0)
		button.pressed.connect(_on_tool_pressed.bind(kind))
		grid.add_child(button)
		_tool_buttons.append(button)

	palette_column.add_child(HSeparator.new())

	var layer_row := HBoxContainer.new()
	layer_row.name = "LayerRow"
	var layer_caption := Label.new()
	layer_caption.text = "Layer"
	layer_row.add_child(layer_caption)
	_layer_option = OptionButton.new()
	_layer_option.name = "LayerOption"
	_layer_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layer_option.tooltip_text = "The layer the next shape is drawn on"
	for choice: Dictionary in _draft.layer_choices():
		_layer_names.append(choice["name"])
		_layer_option.add_item(String(choice["name"]))
		_layer_option.set_item_tooltip(
			_layer_option.item_count - 1, String(choice["purpose"])
		)
	_layer_option.item_selected.connect(_on_layer_selected)
	layer_row.add_child(_layer_option)
	palette_column.add_child(layer_row)

	# What to do with the shape in hand, then what to do with the drawing.
	var shape_row := HBoxContainer.new()
	shape_row.name = "ShapeRow"
	palette_column.add_child(shape_row)
	_command_button(shape_row, &"draft_finish", "Finish", _draft.finish)
	_command_button(shape_row, &"draft_close", "Close", _draft.finish_closed)
	_command_button(shape_row, &"draft_cancel", "Cancel", _draft.cancel)

	var edit_row := HBoxContainer.new()
	edit_row.name = "EditRow"
	palette_column.add_child(edit_row)
	_command_button(edit_row, &"draft_undo", "Undo", _draft.undo)
	_command_button(edit_row, &"draft_redo", "Redo", _draft.redo)
	_command_button(edit_row, &"draft_undo_point", "Drop", _draft.undo_point)

	var plot_row := HBoxContainer.new()
	plot_row.name = "SheetRow"
	palette_column.add_child(plot_row)
	_command_button(plot_row, &"draft_plot", "Plot a sheet", _draft.plot)

	var style_row := HBoxContainer.new()
	style_row.name = "StyleRow"
	palette_column.add_child(style_row)
	_style_button = _command_button(
		style_row, &"draft_dimension_style", "Standard", _draft.cycle_dimension_style
	)

	_refresh_palette()


## A palette button for one of the drafting commands. The key goes in the tooltip
## rather than on the button: the nine tools are worth learning by number, and the
## row of small buttons would be a wall of brackets if every one carried its key.
func _command_button(
	row: HBoxContainer, action: StringName, wording: String, handler: Callable
) -> Button:
	var button := Button.new()
	button.name = String(action)
	button.text = wording
	var key := _key_label(action)
	if key != "":
		button.tooltip_text = "%s (%s)" % [wording, key]
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(handler)
	row.add_child(button)
	return button


## Match the palette to the controller.
##
## Driven by state rather than by signals because the controller is changed from
## several places - a key, a click, a palette button - and a signature cannot miss
## one the way a forgotten connection would.
func _refresh_palette() -> void:
	if _draft == null or _arm_button == null:
		return
	var state := "%s|%d|%s|%s" % [
		_draft.drawing, int(_draft.current_tool()), String(_draft.current_layer()),
		String(_draft.dimension_style_name),
	]
	if state == _palette_state:
		return
	_palette_state = state
	# By the silent setter, because setting a button the ordinary way fires the
	# handler: the palette would then be driving the controller it is reporting on.
	_arm_button.set_pressed_no_signal(_draft.drawing)
	var armed: bool = _draft.drawing
	var kind: int = int(_draft.current_tool())
	for index in _tool_buttons.size():
		var button: Button = _tool_buttons[index]
		# Only a tool actually in your hand is shown as chosen. A palette
		# highlighting a tool while the tools are put away would be describing a
		# mode that is not on.
		button.button_pressed = armed and int(DRAFTING_TOOLS[index][2]) == kind
	var selected := _layer_names.find(_draft.current_layer())
	if selected >= 0:
		_layer_option.selected = selected
	_style_button.text = "Standard: %s" % String(_draft.dimension_style_name)
	_style_button.tooltip_text = "%s (%s)" % [
		_draft.document.dimension_style.describe(), _key_label(&"draft_dimension_style"),
	]


func _on_arm_toggled(pressed: bool) -> void:
	if _draft != null:
		_draft.set_drawing(pressed)


func _on_tool_pressed(kind: int) -> void:
	if _draft != null:
		_draft.arm(kind)


func _on_layer_selected(index: int) -> void:
	if _draft == null or index < 0 or index >= _layer_names.size():
		return
	_draft.set_layer(_layer_names[index])


## What one tool button says: the tool on the first line, the key that does the same
## thing on the second, so the palette teaches the shortcut while it is being used.
static func palette_label(pair: Array) -> String:
	var words := String(pair[1])
	var capitalised := words.substr(0, 1).to_upper() + words.substr(1)
	var key := _key_label(pair[0])
	return capitalised if key == "" else "%s\n%s" % [capitalised, key]


## Keep the HUD out of the keyboard focus chain.
##
## Godot hands Tab to focus navigation as soon as a Control holds it, and a focused
## Button swallows the keys the drawing tools are driven by: the moment the palette was
## clicked, Tab stopped reaching the view switch and Enter started pressing the button
## that had focus rather than finishing the shape. Nothing in the HUD is typed into, so
## nothing in it should hold the keyboard, and every key belongs to the drawing.
static func release_keyboard_focus(root: Node) -> void:
	for found: Node in root.find_children("*", "Button", true, false):
		(found as Button).focus_mode = Control.FOCUS_NONE
