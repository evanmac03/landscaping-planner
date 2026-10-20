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

## The client presentation: the budgets it can be shown at, and the sizes a proposal
## still is rendered at. Both are read from the tables that act on them rather than
## written here, so the picker cannot offer a tier or a size that does not exist.
const TierScript := preload("res://scripts/vis/presentation_tier.gd")
const DirectorScript := preload("res://scripts/vis/presentation_director.gd")
const PaintedPlanScript := preload("res://scripts/vis/painted_plan.gd")
const SunStudyScript := preload("res://scripts/vis/sun_study.gd")

## The sizes a still can be asked for. Not every size for every job: these are the
## four a proposal actually wants, and each is a name a person recognises.
const STILL_SIZES: Array = [
	["Web 1920 x 1080", Vector2i(1920, 1080)],
	["QHD 2560 x 1440", Vector2i(2560, 1440)],
	["4K 3840 x 2160", Vector2i(3840, 2160)],
]

@export var view_controller: ViewController
## The presentation director. Absent in a scene that has no presentation, in which
## case the panel is not built at all rather than built full of dead buttons.
@export var presentation: DirectorScript
## The painted plan. Absent in a scene that cannot paint one, in which case the key
## does nothing rather than reporting a failure for a feature that is not there.
@export var painted_plan: PaintedPlanScript

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
@onready var presentation_panel: PanelContainer = %Presentation
@onready var presentation_column: VBoxContainer = %PresentationColumn
@onready var painted_sheet: Control = %PaintedSheet
@onready var painted_picture: TextureRect = %Sheet
@onready var painted_caption: Label = %Caption
@onready var painted_actions: HBoxContainer = %PaintedActions
## The working furniture, found by path rather than by name: these two are old
## enough that giving them unique names would be a scene change for no reason.
@onready var top_bar: PanelContainer = get_node_or_null(^"Root/TopBar")
@onready var hints: PanelContainer = get_node_or_null(^"Root/Hints")

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

## The controls built by _build_presentation_panel, kept so the refresh can set them.
var _present_toggle: CheckButton = null
var _tier_option: OptionButton = null
var _sun_hour: SpinBox = null
var _sun_day: SpinBox = null
var _sun_latitude: SpinBox = null
var _sun_longitude: SpinBox = null
var _sun_utc_offset: SpinBox = null
var _still_size_option: OptionButton = null
var _still_status: Label = null
## What the presentation panel was last drawn to match.
var _presentation_state: String = ""
## Whether a client presentation is running. Held here because the HUD is what
## decides which of its own furniture belongs in a presentation.
var _presenting: bool = false

## The painted plan on screen, held rather than rendered again when it is saved:
## looking at the picture and filing it are two decisions, and the second one should
## file the picture that was looked at.
var _painted_image: Image = null
## The button that files it, kept so it can be switched off while there is nothing
## to file.
var _painted_save: Button = null


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
	_build_presentation_panel()
	_build_painted_actions()
	# The painted plan reports by signal, so the panel is a caption rather than a
	# function that blocks the frame the key was pressed in.
	if painted_plan != null:
		painted_plan.painted.connect(_on_painted)
		painted_plan.paint_failed.connect(_on_paint_failed)
	_on_view_mode_changed(view_controller.mode)
	# Last, so it covers the buttons the palette and the presentation panel just
	# built as well as the ones in the scene: a button that holds the keyboard takes
	# the drawing keys with it.
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
	# A presentation is not a working view, so none of the working furniture is in
	# it: the panel that ends the presentation is the one thing that stays.
	draft_hints.visible = overhead and view_controller.is_drafting() and not _presenting
	if palette.get_child_count() > 0:
		palette.visible = overhead and not _presenting
		_refresh_palette()
	# A presentation is a view of the garden rather than of the drawing, so the
	# painted sheet goes away with the rest of the drawing's furniture.
	if _presenting and painted_sheet.visible:
		close_painted()
	_refresh_presentation()


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
	# Next to plotting, because it is the other way the drawing leaves the application:
	# the sheet is the drawing, the painted plan is the drawing coloured.
	_command_button(plot_row, &"vis_painted", "Painted plan", open_painted)

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


# --- the client presentation ----------------------------------------------------------


## The presentation panel: start a client presentation, choose what it is rendered at,
## aim the sun, and render a proposal still.
##
## Built in code rather than in the scene, for the same reason the palette's buttons
## are: every control here is derived from a table (`PresentationTier.LOOKS` and
## `STILL_SIZES`), so a scene file would be a second copy of those tables to keep in
## step with the first.
##
## A scene with no director gets no panel at all, rather than a panel full of dead
## buttons: this is the one GUI in the project that may legitimately not exist.
func _build_presentation_panel() -> void:
	if presentation == null or presentation_column == null:
		if presentation_panel != null:
			presentation_panel.visible = false
		return

	var heading := Label.new()
	heading.text = "Presentation"
	presentation_column.add_child(heading)

	_present_toggle = CheckButton.new()
	_present_toggle.name = "PresentationToggle"
	_present_toggle.text = "Client presentation"
	_present_toggle.tooltip_text = (
		"Walk a client through the garden: right-drag to orbit, wheel to dolly, "
		+ "middle-drag to pan. The working tools are put away."
	)
	_present_toggle.toggled.connect(_on_presentation_toggled)
	presentation_column.add_child(_present_toggle)

	var tier_row := HBoxContainer.new()
	tier_row.name = "TierRow"
	var tier_caption := Label.new()
	tier_caption.text = "Quality"
	tier_row.add_child(tier_caption)
	_tier_option = OptionButton.new()
	_tier_option.name = "TierOption"
	_tier_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tier_option.tooltip_text = "What the renderer is allowed to spend"
	for tier in TierScript.CHOICES:
		_tier_option.add_item(TierScript.name_of(tier))
	_tier_option.item_selected.connect(_on_tier_selected)
	tier_row.add_child(_tier_option)
	presentation_column.add_child(tier_row)

	presentation_column.add_child(HSeparator.new())

	var sun_caption := Label.new()
	sun_caption.text = "Sun"
	presentation_column.add_child(sun_caption)
	# The site and the moment, one field to a row. Labelled rather than suffix-only, because
	# two of these five numbers are degrees, two are hours and the latitude and the longitude
	# would otherwise be told apart by position alone.
	var sun_grid := GridContainer.new()
	sun_grid.name = "SunGrid"
	sun_grid.columns = 2
	# A tenth of a degree of latitude, so the site's own latitude survives being put in
	# the box: at half a degree the panel would silently move the garden 5 km north. Half a
	# degree of longitude is two minutes of solar time, which is fine for a longitude.
	_sun_hour = _spin("SunHour", 0.0, 24.0, 0.5, " h", 16.0,
		"Clock time at the site. The sun's own noon is up to sixteen minutes off the clock's.")
	_sun_day = _spin("SunDay", 1.0, 366.0, 1.0, " d", 172.0,
		"Day of the year. 172 is the solstice.")
	_sun_latitude = _spin("SunLatitude", -90.0, 90.0, 0.1, "°", 45.0,
		"Degrees north, so negative is south. The number that makes a shadow study mean anything.")
	_sun_longitude = _spin("SunLongitude", -180.0, 180.0, 0.5, "°", -75.0,
		"Degrees east, so negative is west. Four minutes of solar time to a degree: this is what makes a clock time the site's sky rather than the sky at Greenwich.")
	# A quarter hour, because the world's zones are not all whole hours apart.
	_sun_utc_offset = _spin("SunUtcOffset", -12.0, 14.0, 0.25, " h", -5.0,
		"Hours from UTC in force at the site. Daylight saving belongs here rather than in a rule, since a rule is right in one country and wrong in the next: in summer this is an hour ahead of standard time, which is why every sunrise reads an hour later.")
	_add_sun_field(sun_grid, "Hour", _sun_hour)
	_add_sun_field(sun_grid, "Day", _sun_day)
	_add_sun_field(sun_grid, "Latitude", _sun_latitude)
	_add_sun_field(sun_grid, "Longitude", _sun_longitude)
	_add_sun_field(sun_grid, "UTC offset", _sun_utc_offset)
	presentation_column.add_child(sun_grid)

	var sun_buttons := HBoxContainer.new()
	sun_buttons.name = "SunButtons"
	var apply_button := Button.new()
	apply_button.name = "ApplySun"
	apply_button.text = "Apply the sun"
	apply_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply_button.pressed.connect(_on_apply_sun)
	sun_buttons.add_child(apply_button)
	var frame_button := Button.new()
	frame_button.name = "FrameYard"
	frame_button.text = "Frame the garden"
	frame_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame_button.tooltip_text = "Pull the camera back until the whole garden fits"
	frame_button.pressed.connect(_on_frame_yard)
	sun_buttons.add_child(frame_button)
	presentation_column.add_child(sun_buttons)

	# The site is a fact about the drawing, so the panel offers to make it one. Without
	# this the five fields would be a study of somewhere else that is thrown away the
	# moment the drawing is reloaded.
	var save_site_button := Button.new()
	save_site_button.name = "SaveSite"
	save_site_button.text = "Save the site to the drawing"
	save_site_button.tooltip_text = "Keep this latitude, longitude and offset with the plan"
	save_site_button.pressed.connect(_on_save_site)
	presentation_column.add_child(save_site_button)

	presentation_column.add_child(HSeparator.new())

	var still_row := HBoxContainer.new()
	still_row.name = "StillRow"
	var still_caption := Label.new()
	still_caption.text = "Still"
	still_row.add_child(still_caption)
	_still_size_option = OptionButton.new()
	_still_size_option.name = "StillSize"
	_still_size_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_still_size_option.tooltip_text = "The size of the image a proposal gets"
	for choice: Array in STILL_SIZES:
		_still_size_option.add_item(String(choice[0]))
	still_row.add_child(_still_size_option)
	var render_button := Button.new()
	render_button.name = "RenderStill"
	render_button.text = "Render"
	render_button.tooltip_text = "Render the current view at that size and write it out"
	render_button.pressed.connect(_on_render_still)
	still_row.add_child(render_button)
	presentation_column.add_child(still_row)

	_still_status = Label.new()
	_still_status.name = "StillStatus"
	_still_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_still_status.custom_minimum_size = Vector2(280.0, 0.0)
	presentation_column.add_child(_still_status)

	# The director reports what it did; the HUD is what takes its own furniture out of
	# the picture, because the furniture is the HUD's.
	presentation.presentation_changed.connect(_on_presentation_changed)
	presentation.note.connect(_on_presentation_note)
	presentation.still_beginning.connect(_on_still_beginning)
	presentation.still_written.connect(_on_still_written)
	presentation.still_failed.connect(_on_still_failed)

	# Start from what the scene actually holds, so the form describes the garden rather
	# than a default. The sun's own values are set by `_refresh_presentation()`, which is
	# the one place that reads the presenter: the site's latitude arrives from the drawing
	# when the *presenter* is ready, and the presenter is later in the scene than this
	# panel is.
	_refresh_presentation()


## One labelled spin box for the sun row. Returns the box; the caller puts it in the row,
## because a helper that both made a control and parented it would have two owners for
## one child.
func _spin(
	node_name: String, low: float, high: float, step: float,
	suffix: String, initial: float, tip: String
) -> SpinBox:
	var box := SpinBox.new()
	box.name = node_name
	box.min_value = low
	box.max_value = high
	box.step = step
	box.value = initial
	box.suffix = suffix
	box.tooltip_text = tip
	# A spin box is typed into, so it is the one control in the HUD that has to be able
	# to hold the keyboard; `release_keyboard_focus` only touches buttons.
	box.custom_minimum_size = Vector2(64.0, 0.0)
	return box


## One labelled field of the sun grid. The label is the control that keeps five numbers
## legible: a suffix carries units but not meaning, and two of these boxes hold degrees.
func _add_sun_field(grid: GridContainer, text: String, box: SpinBox) -> void:
	var label := Label.new()
	label.name = text.replace(" ", "") + "Label"
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(label)
	grid.add_child(box)


## Match the panel to the director, when something other than this panel changed it.
##
## Driven by a signature rather than by a signal, like the palette: the director is
## changed from a key, a click and a script, and a signature cannot miss one of them
## the way a forgotten connection would.
func _refresh_presentation() -> void:
	if _present_toggle == null or presentation == null:
		return
	# The sun's settings are part of the state this panel describes, and not only the
	# tier. The site reaches the presenter from the drawing when the presenter is ready —
	# later than this panel — so a signature that ignored the sun would leave the form
	# showing a default the scene does not use, and *Apply* would then push that default
	# back over the site's own latitude, longitude and offset.
	var state := "%s|%d|%.2f|%.2f|%.2f|%d|%.2f" % [
		str(presentation.is_active()), presentation.tier,
		presentation.latitude, presentation.longitude, presentation.utc_offset_hours,
		presentation.day_of_year, presentation.hour,
	]
	if state == _presentation_state:
		return
	_presentation_state = state
	_sun_hour.value = presentation.hour
	_sun_day.value = float(presentation.day_of_year)
	_sun_latitude.value = presentation.latitude
	_sun_longitude.value = presentation.longitude
	_sun_utc_offset.value = presentation.utc_offset_hours
	# By the silent setters: setting a button the ordinary way fires the handler, which
	# would then call `begin()` on a presentation that is already running.
	_present_toggle.set_pressed_no_signal(presentation.is_active())
	var selected: int = TierScript.CHOICES.find(presentation.tier)
	if selected >= 0:
		_tier_option.selected = selected


## Put the working furniture away for a presentation, or bring it back.
##
## This is the HUD's own business: the director says when a presentation begins, and
## what is working furniture is decided here, by the code that made it.
func set_presenting(on: bool) -> void:
	_presenting = on
	if top_bar != null:
		top_bar.visible = not on
	if hints != null:
		hints.visible = not on
	# The scale bar and the north point are sheet furniture, and a client is being
	# shown the garden rather than the drawing.
	if overlay != null:
		overlay.visible = not on
	# The palette and the key legend read `_presenting` every frame, so they put
	# themselves away rather than being set here: one place per control decides whether
	# it is visible.


func _on_presentation_toggled(pressed: bool) -> void:
	if presentation == null:
		return
	if not pressed:
		presentation.end()
		return
	# It could not start: put the switch back rather than leave it claiming something is
	# running that is not.
	if not presentation.begin(presentation.tier):
		_present_toggle.set_pressed_no_signal(false)


func _on_presentation_changed(active: bool) -> void:
	set_presenting(active)
	if active:
		_still_status.text = "presentation running"
	else:
		_still_status.text = ""


func _on_presentation_note(text: String) -> void:
	if _still_status != null:
		_still_status.text = text


func _on_tier_selected(index: int) -> void:
	if presentation == null or index < 0 or index >= TierScript.CHOICES.size():
		return
	presentation.set_tier(TierScript.CHOICES[index])


func _on_apply_sun() -> void:
	if presentation == null:
		return
	# The site and the moment, together: the presenter turns the clock time into the
	# site's own sky, which is where the longitude and the offset earn their place.
	presentation.apply_sun(
		SunStudyScript.site(
			float(_sun_latitude.value),
			float(_sun_longitude.value),
			float(_sun_utc_offset.value)
		),
		SunStudyScript.moment(int(_sun_day.value), float(_sun_hour.value))
	)


## Keep the site with the drawing rather than only in this presentation. A drawing fact, so
## it is undoable like any other, and the presenter says what happened either way.
func _on_save_site() -> void:
	if presentation != null:
		presentation.save_site()


func _on_frame_yard() -> void:
	if presentation != null:
		presentation.frame_yard()


func _on_render_still() -> void:
	if presentation == null:
		return
	var size: Vector2i = selected_still_size()
	_still_status.text = "rendering %d x %d..." % [size.x, size.y]
	# Not awaited. The render waits for real frames and answers by signal, so this
	# panel stays a status line instead of blocking the frame it was pressed in.
	presentation.render_still(size)


## The size the still picker is on, as a pixel pair.
func selected_still_size() -> Vector2i:
	var index: int = _still_size_option.selected if _still_size_option != null else 0
	if index < 0 or index >= STILL_SIZES.size():
		index = 0
	return STILL_SIZES[index][1]


func _on_still_beginning() -> void:
	# The whole HUD, not just the working parts: a proposal image is of the garden, and
	# the panel holding the Render button would be in the corner of it.
	visible = false


func _on_still_written(path: String) -> void:
	visible = true
	if _still_status != null:
		_still_status.text = "wrote %s" % path.get_file()


func _on_still_failed(reason: String) -> void:
	visible = true
	if _still_status != null:
		_still_status.text = "no still: %s" % reason


# --- the painted plan -----------------------------------------------------------------


## The two buttons under a painted plan: file it, or put it away.
##
## Built in code for the same reason the palette's buttons are: they are two
## decisions about one picture, and a scene file holding them would be a second place
## to change when there is only ever one.
func _build_painted_actions() -> void:
	if painted_actions == null:
		return
	_painted_save = Button.new()
	_painted_save.name = "SavePaintedStill"
	_painted_save.text = "Save a still"
	_painted_save.tooltip_text = "Write this picture into the proposals folder, with its record"
	_painted_save.disabled = true
	_painted_save.pressed.connect(_on_save_painted)
	painted_actions.add_child(_painted_save)
	var close_button := Button.new()
	close_button.name = "ClosePaintedSheet"
	close_button.text = "Close"
	close_button.pressed.connect(close_painted)
	painted_actions.add_child(close_button)


## Show the painted plan, painting it first if there is nothing to show.
##
## Painting again on every key press rather than caching: a designer presses this
## after changing the drawing, and a cached picture would be a picture of the plan as
## it used to be.
func open_painted() -> void:
	if painted_plan == null or painted_sheet == null:
		return
	if painted_sheet.visible:
		close_painted()
		return
	# A presentation is a view of the garden rather than of the drawing, so the
	# drawing does not open over it.
	if _presenting:
		return
	_painted_image = null
	if _painted_save != null:
		_painted_save.disabled = true
	painted_picture.texture = null
	var reason: String = painted_plan.refusal()
	if reason != "":
		# The answer to "show me the painted plan" is a sentence when there is no
		# plan to paint, and the sheet is where the answer is read.
		painted_caption.text = reason
		painted_sheet.visible = true
		return
	painted_caption.text = "painting..."
	painted_sheet.visible = true
	# Not awaited: the render waits for real frames, and the result arrives by
	# signal. The status line is this label, which is already saying so.
	painted_plan.render()


func close_painted() -> void:
	if painted_sheet != null:
		painted_sheet.visible = false


func _on_painted(image: Image, report: Dictionary) -> void:
	_painted_image = image
	if painted_picture != null:
		painted_picture.texture = ImageTexture.create_from_image(image)
	if painted_caption != null:
		painted_caption.text = painted_caption_text(report)
	if _painted_save != null:
		_painted_save.disabled = false


func _on_paint_failed(reason: String) -> void:
	_painted_image = null
	if painted_picture != null:
		painted_picture.texture = null
	if painted_caption != null:
		painted_caption.text = reason
	if _painted_save != null:
		_painted_save.disabled = true


func _on_save_painted() -> void:
	if painted_plan == null or _painted_image == null:
		return
	# The button is switched off while there is nothing to file, so an empty save here
	# is a state that cannot be reached - but the file is written by a function that
	# can fail, and a failure has somewhere to be read.
	var path: String = painted_plan.save(_painted_image)
	if path != "" and painted_caption != null:
		painted_caption.text = "wrote %s" % path.get_file()


## What a painted plan says about itself: the sheet, the scale, the pixels, and how
## much of the drawing reached the paper. Static so a test can hold the promise that
## the caption names the scale the drawing was painted at.
static func painted_caption_text(report: Dictionary) -> String:
	var pixels: Array = report.get("pixels", [0, 0])
	var mm: Array = report.get("mm", [0.0, 0.0])
	return "Painted plan   %.0f x %.0f mm at 1:%s   %d x %d px   %d washed areas, %d planted" % [
		float(mm[0]), float(mm[1]), String.num(float(report.get("plot_scale", 100.0)), 4),
		int(pixels[0]), int(pixels[1]),
		int(report.get("regions", 0)), int(report.get("props", 0)),
	]


## The painted plan's key, and the way out of it.
##
## Handled here rather than in the view controller because the sheet is the HUD's own
## surface: the key that opens it, the escape that closes it, and the picture it shows
## are one feature in one place.
func _unhandled_input(event: InputEvent) -> void:
	if painted_plan == null:
		return
	if event.is_action_pressed(&"vis_painted"):
		open_painted()
		get_viewport().set_input_as_handled()
		return
	# Escape closes the sheet before anything else gets a turn: while it is up, the
	# drawing behind it is not what the person is looking at. Cancelling a shape still
	# works when the sheet is not up, which is the only time it means anything.
	if painted_sheet.visible and event.is_action_pressed(&"draft_cancel"):
		close_painted()
		get_viewport().set_input_as_handled()
