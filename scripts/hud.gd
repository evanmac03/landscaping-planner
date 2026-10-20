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
const PlotScaleScript := preload("res://scripts/draft/plot_scale.gd")
const StoreScript := preload("res://scripts/draft/drawing_store.gd")

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
## The menu bar. In the scene, because where it sits among the top bar's controls is a layout
## decision; its menus are built in code from `menu_plan()`, because what is in them is derived
## from the tables that already describe those commands.
@onready var menu_bar: MenuBar = %MenuBar

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

## The menu bar's entries, per popup, in the order they were added. A PopupMenu item's id is its
## index, so this is the way back from a press to the entry that describes it.
var _menu_items: Dictionary = {}
## What the menu was last drawn to match, so a check every frame does not restate state that has
## not moved.
var _menu_state: String = ""
## The key reference, built by `_build_keys_panel`: the wrapper that centres the page, held so the
## one place that decides whether it is up is the panel's own `visible`.
var _keys_panel: Control = null
## Whether the line of control hints is wanted at the bottom of the screen. Held here rather than
## read from the node, because a presentation takes the hints away and has to give them back the
## way the person left them.
var _show_hints: bool = true

## The file dialogs, and the question asked before work is thrown away.
var _open_dialog: FileDialog = null
var _save_dialog: FileDialog = null
var _discard_dialog: ConfirmationDialog = null
## What to do once the unsaved-changes question has been answered. Held as an id rather than as a
## Callable so that a dialog left open while something else happens cannot run a stale action out
## of a captured closure.
var _pending_action: StringName = &""
## The file an action is about, when it is about one: opening a drawing from the recent list.
var _pending_path: String = ""
## The submenu of recently opened drawings, and what it was last filled with: it is the one part
## of the bar whose *entries* change rather than only their ticks.
var _recent_popup: PopupMenu = null
var _recent_filled: String = ""

## The plant list: JSON under `user://plants`, seeded on the first run from the list the project
## ships with, for the same reason the cost book is JSON - a catalogue is four thousand entries a
## nursery mails you as a spreadsheet, not four thousand `.tres` files (spec §2.3).
const PlantCatalogueScript := preload("res://scripts/plant_catalogue.gd")
const PlantBrowserScript := preload("res://scripts/plant_browser.gd")
const PlantPanelScript := preload("res://scripts/plant_panel.gd")
const PlantSuitabilityScript := preload("res://scripts/plant_suitability.gd")
const TerrainProfileScript := preload("res://scripts/terrain_profile.gd")
const ZoneMapScript := preload("res://scripts/zone_map.gd")
const GroundWindowScript := preload("res://scripts/ground_window.gd")
const STARTER_PLANT_LIST := "res://data/plants/nursery_list.json"

## The plant list once it has been read, held because it is a file: a menu that read four thousand
## species in order to write one line on itself would be a menu nobody could use.
var _plants: PlantCatalogue = null
## The library: the window, the browser inside it, and the two dialogs a plant list arrives and
## leaves by. The window is a `Window` rather than a panel in `Root` on purpose - it is the one
## boundary at which something in this HUD is allowed to hold the keyboard, which is what makes the
## search box typeable without taking W A S D away from the design.
var _plant_window: Window = null
var _plant_browser: PlantBrowser = null
var _plant_import_dialog: FileDialog = null
var _plant_export_dialog: FileDialog = null
## The ground: one window, because the site's conditions and the conditions of every area of the plan
## are one subject, and a menu cannot hold an area.
var _ground_window: GroundWindow = null
## The species the last choice armed, so "place it again" has something to place.
var _plant_chosen: StringName = &""
## The plants section of the palette, thrown in under the drawing tools. The library is where a
## catalogue of four thousand is searched; this is where the one plant you already know you want is
## reached, one click, without a window, a menu or a key in the way.
var _plant_panel: PlantPanel = null


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
	_build_plant_panel()
	_build_presentation_panel()
	_build_painted_actions()
	_build_menu_bar()
	_build_keys_panel()
	_build_file_dialogs()
	_build_plant_library()
	_build_ground_window()
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
		_refresh_plant_panel()
	# A presentation is a view of the garden rather than of the drawing, so the
	# painted sheet goes away with the rest of the drawing's furniture.
	if _presenting and painted_sheet.visible:
		close_painted()
	_refresh_presentation()
	_refresh_menus()


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
		# A Button inside a Window is a *dialog's* own - Save, Cancel, Keep editing - and a modal
		# dialog is meant to hold the keyboard while it is up. Taking its buttons out of the focus
		# chain too left the dialog unable to focus the one it opens on: it appeared, and the
		# engine logged "This control can't grab focus" at the moment of popping up.
		if _inside_window(found):
			continue
		(found as Button).focus_mode = Control.FOCUS_NONE


## Whether a node lives inside a Window - a dialog rather than the HUD's own furniture.
static func _inside_window(node: Node) -> bool:
	var walk: Node = node
	while walk != null:
		if walk is Window:
			return true
		walk = walk.get_parent()
	return false


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
	if on:
		# The key reference is working furniture: a client is being shown the garden, not the
		# shortcut list.
		close_keys()
	if top_bar != null:
		top_bar.visible = not on
	# The hints come back the way they were left, which is why their visibility is decided in one
	# place from a flag rather than set directly here and in the menu.
	_apply_hints_visibility()
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
	# The key reference is answered for first, because it is the one thing here that can be up in
	# a scene that has no painted plan at all.
	if is_keys_open() and event.is_action_pressed(&"draft_cancel"):
		close_keys()
		get_viewport().set_input_as_handled()
		return
	# The file commands, while none of our dialogs is up: a dialog has its own keys, and a second
	# Ctrl+S behind an open Save dialog would open another one.
	if not _file_dialog_open():
		if event.is_action_pressed(&"file_new"):
			_menu_new_drawing({})
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"file_open"):
			_menu_open_drawing({})
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"file_save"):
			_menu_save_drawing({})
			get_viewport().set_input_as_handled()
			return
		# The plant library, on the same footing: a plant browser is reached for constantly while
		# planting a bed, and a menu is a slow way to get to something you use every minute.
		if event.is_action_pressed(&"plant_library"):
			if _plant_window != null and _plant_window.visible:
				close_plant_browser()
			else:
				open_plant_browser()
			get_viewport().set_input_as_handled()
			return
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


# --- the menu bar ---------------------------------------------------------------------
#
# A menu across the top of the window: the things a program of this kind always offers, plus the
# two things this one is actually made of - the drawing tools and the client presentation.
#
# Every entry does something, and the ones that stand for a key say which key. The keys come from
# the input map rather than from a table here, so a rebinding moves the menu with the legend.


## What an entry needs from the scene before it means anything. `NEEDS_NOTHING` is the common
## case: the command works in any scene this HUD is in.
const NEEDS_NOTHING := &""
const NEEDS_DRAFT := &"draft"
const NEEDS_PRESENTATION := &"presentation"
const KNOWN_NEEDS: Array[StringName] = [NEEDS_NOTHING, NEEDS_DRAFT, NEEDS_PRESENTATION]


## One entry that runs a command.
static func _command(
	id: String, label: String, action: StringName, method: StringName,
	needs: StringName = NEEDS_NOTHING, enabled_when: StringName = &""
) -> Dictionary:
	return {
		"kind": &"command", "id": id, "label": label, "action": action,
		"method": method, "needs": needs, "enabled_when": enabled_when, "value": null,
	}


## One entry of a set: choosing it chooses that value, and exactly one of the set is shown as on.
## `state` names what it is checked against, and `value` is the value it stands for.
static func _radio(
	id: String, label: String, action: StringName, method: StringName,
	state: StringName, value: Variant, needs: StringName = NEEDS_NOTHING
) -> Dictionary:
	return {
		"kind": &"radio", "id": id, "label": label, "action": action, "method": method,
		"state": state, "value": value, "needs": needs,
	}


## One entry that is on or off, and means the state it names. It carries a null value so that
## every checkable entry has the same shape, and a reader of the plan does not have to know which
## kind it is before asking what it stands for.
static func _check(
	id: String, label: String, action: StringName, method: StringName, state: StringName
) -> Dictionary:
	return {
		"kind": &"check", "id": id, "label": label, "action": action, "method": method,
		"state": state, "value": null, "needs": NEEDS_NOTHING,
	}


## A menu inside a menu, for the sets that would otherwise be ten entries long.
static func _submenu(id: String, label: String, items: Array[Dictionary]) -> Dictionary:
	return {"kind": &"submenu", "id": id, "label": label, "items": items, "action": &"", "needs": NEEDS_NOTHING}


static func _separator() -> Dictionary:
	return {"kind": &"separator", "id": "", "action": &"", "needs": NEEDS_NOTHING}


## A line that says something rather than doing something: shown switched off, because a menu
## entry that looks pressable and is not is the thing this whole file is trying not to build.
static func _info(id: String, label: String) -> Dictionary:
	return {
		"kind": &"info", "id": id, "label": label, "action": &"", "needs": NEEDS_NOTHING,
		"value": null,
	}


## The whole bar, menu by menu.
static func menu_plan() -> Array[Dictionary]:
	var menus: Array[Dictionary] = []
	menus.append({"title": "File", "items": file_items()})
	menus.append({"title": "Edit", "items": edit_items()})
	menus.append({"title": "View", "items": view_items()})
	menus.append({"title": "Draft", "items": draft_items()})
	menus.append({"title": "Site", "items": site_items()})
	menus.append({"title": "Plant", "items": plant_items()})
	menus.append({"title": "Present", "items": present_items()})
	menus.append({"title": "Help", "items": help_items()})
	return menus


## Everything the drawing can be sent to: the sheet it is plotted on, the picture of it at the
## chosen size, and how the sheet itself is set up.
static func file_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	# The drawing is named at the top of the menu, where a person looks to find out what is open.
	# A menu is also the last place something silent should live, so whether the screen and the
	# file agree is stated rather than implied by a greyed-out Save.
	items.append(_info(&"file.info", "no drawing"))
	items.append(_separator())
	items.append(_command(&"file.new", "New drawing", &"file_new", &"_menu_new_drawing", NEEDS_DRAFT))
	items.append(_command(&"file.open", "Open drawing...", &"file_open", &"_menu_open_drawing", NEEDS_DRAFT))
	items.append(_submenu(&"file.recent", "Open recent", []))
	items.append(_separator())
	items.append(_command(
		&"file.save", "Save", &"file_save", &"_menu_save_drawing", NEEDS_DRAFT, &"dirty"
	))
	items.append(_command(&"file.save_as", "Save as...", &"", &"_menu_save_drawing_as", NEEDS_DRAFT))
	items.append(_separator())
	items.append(_command(&"file.plot", "Plot a sheet...", &"draft_plot", &"_menu_plot", NEEDS_DRAFT))
	items.append(_command(&"file.still", "Render a proposal still", &"", &"_menu_render_still", NEEDS_PRESENTATION))
	items.append(_separator())
	items.append(_submenu(&"file.sheet", "Sheet size", sheet_items()))
	items.append(_submenu(&"file.scale", "Plot scale", scale_items()))
	items.append(_separator())
	items.append(_command(&"file.quit", "Quit", &"", &"_menu_quit"))
	return items


## Every sheet the plotter knows, from the table that measures them.
static func sheet_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	# Not `name`: this is a CanvasLayer, and `name` is the node's own.
	for sheet_name in PlotScaleScript.sheet_names():
		items.append(_radio(
			"file.sheet." + String(sheet_name), String(sheet_name), &"", &"_menu_set_sheet",
			&"sheet", sheet_name, NEEDS_DRAFT
		))
	return items


## Every scale on the metric ladder. Ten entries, which is why they are behind a submenu: a menu
## that is a list of numbers reads as a table rather than as commands.
static func scale_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	# Not `scale`: this is a CanvasLayer, and `scale` is a property of it.
	for ratio: float in PlotScaleScript.METRIC_LADDER:
		items.append(_radio(
			"file.scale.%d" % int(ratio), PlotScaleScript.metric_label(ratio), &"",
			&"_menu_set_scale", &"scale", ratio, NEEDS_DRAFT
		))
	return items


## What can be done to the drawing: its history, the shape in hand, and how it is measured.
static func edit_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	items.append(_command(&"edit.undo", "Undo", &"draft_undo", &"_menu_undo"))
	items.append(_command(&"edit.redo", "Redo", &"draft_redo", &"_menu_redo"))
	items.append(_separator())
	items.append(_command(&"edit.drop_point", "Drop the last point", &"draft_undo_point", &"_menu_drop_point"))
	items.append(_command(&"edit.cancel", "Cancel the shape", &"draft_cancel", &"_menu_cancel_shape"))
	items.append(_separator())
	items.append(_submenu(&"edit.dimension_style", "Dimension standard", dimension_style_items()))
	return items


## The dimension standards the controller offers, from its own table.
static func dimension_style_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for style: StringName in DraftControllerScript.DIMENSION_STYLES:
		var words := String(style)
		items.append(_radio(
			"edit.dimension_style." + words, words.substr(0, 1).to_upper() + words.substr(1),
			&"draft_dimension_style", &"_menu_set_dimension_style", &"dimension_style", style
		))
	return items


## Where you can be and what you can look at.
##
## The three views are a set rather than a toggle: the key swaps two of them because that is what
## one key can do, and a menu lists all three because that is what a menu is for.
static func view_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	items.append(_radio(
		&"view.plan", "2D plan", &"toggle_view", &"_menu_show_mode",
		&"mode", ViewController.ViewMode.PLAN_2D
	))
	items.append(_radio(
		&"view.overhead", "3D overhead", &"toggle_view", &"_menu_show_mode",
		&"mode", ViewController.ViewMode.OVERHEAD_3D
	))
	items.append(_radio(
		&"view.ground", "Ground view", &"toggle_ground", &"_menu_show_mode",
		&"mode", ViewController.ViewMode.GROUND
	))
	items.append(_separator())
	items.append(_command(&"view.fit", "Fit the design to the screen", &"fit_view", &"_menu_fit"))
	items.append(_separator())
	items.append(_command(&"view.painted", "Painted plan", &"vis_painted", &"_menu_painted"))
	items.append(_check(&"view.hints", "Control hints", &"", &"_menu_toggle_hints", &"hints"))
	return items


## The drawing tools, and what is done with the shape in hand.
##
## The tools come from `DRAFTING_TOOLS` - the same table the legend and the palette are built
## from - so a tool cannot be in the legend and missing from the menu, or in the menu and
## pointing at a different tool from the one the key arms.
static func draft_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	items.append(_check(&"draft.armed", "Drawing tools", &"draft_mode", &"_menu_toggle_drawing", &"drawing"))
	items.append(_separator())
	for pair: Array in DRAFTING_TOOLS:
		items.append(_radio(
			"draft.tool." + String(pair[0]), tool_label(pair), pair[0], &"_menu_arm_tool",
			&"tool", pair[2]
		))
	items.append(_separator())
	items.append(_command(&"draft.finish", "Finish the shape", &"draft_finish", &"_menu_finish"))
	items.append(_command(&"draft.close", "Close the shape", &"draft_close", &"_menu_close_shape"))
	items.append(_command(&"draft.drop_point", "Drop the last point", &"draft_undo_point", &"_menu_drop_point"))
	items.append(_command(&"draft.cancel", "Cancel the shape", &"draft_cancel", &"_menu_cancel_shape"))
	items.append(_separator())
	items.append(_command(&"draft.plot", "Plot a sheet...", &"draft_plot", &"_menu_plot"))
	items.append(_command(
		&"draft.style", "Next dimension standard", &"draft_dimension_style", &"_menu_cycle_dimension_style"
	))
	return items


## A tool as one line of a menu: the word the palette uses, on one line rather than two, because a
## menu row has the key beside the name rather than under it.
static func tool_label(pair: Array) -> String:
	var words := String(pair[1])
	return words.substr(0, 1).to_upper() + words.substr(1)


## The client presentation: what it is rendered at, how the garden is framed, and the sun.
static func present_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	items.append(_check(&"present.running", "Client presentation", &"", &"_menu_toggle_presentation", &"presenting"))
	items.append(_separator())
	items.append(_submenu(&"present.quality", "Quality", tier_items()))
	items.append(_command(&"present.frame", "Frame the garden", &"", &"_menu_frame_yard"))
	items.append(_separator())
	items.append(_submenu(&"present.still_size", "Still size", still_size_items()))
	items.append(_command(&"present.still", "Render a still", &"", &"_menu_render_still"))
	items.append(_separator())
	items.append(_command(&"present.save_site", "Save the site to the drawing", &"", &"_menu_save_site"))
	return items


## The rendering budgets, from the table that acts on them.
static func tier_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for tier: int in TierScript.CHOICES:
		items.append(_radio(
			"present.quality.%d" % tier, TierScript.name_of(tier), &"", &"_menu_set_tier",
			&"tier", tier
		))
	return items


## The sizes a proposal still can be, from the table the render button is built from.
static func still_size_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for index in STILL_SIZES.size():
		items.append(_radio(
			"present.still_size.%d" % index, String(STILL_SIZES[index][0]), &"",
			&"_menu_set_still_size", &"still_size", index
		))
	return items


## What the ground is like here: the facts about the place rather than the things drawn on it.
##
## This menu is where the green and red rings around a plant being placed come from. The ring is the
## answer; these entries are the question - the site's light, moisture, soil and hardiness - plus the
## report on the planting that is already in the ground.
##
## Half of it is a set of radios rather than a dialog, because that is what these are: four facts with
## a handful of values each, stated once for the site. A dialog would be a window with a dropdown in
## it to choose between "full sun" and "part shade", and a window is the one thing this HUD may not
## open casually. Each set starts with "not stated", because the truth about a plan nobody has
## described is that nobody has described it, and the way back to that has to exist.
static func site_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	items.append(_info(&"site.ground", "the plan does not say what the ground is like"))
	items.append(_separator())
	items.append(_command(&"site.window", "What the ground is like...", &"", &"_menu_ground_window"))
	items.append(_command(&"site.read", "Read the ground from the drawing", &"", &"_menu_read_ground"))
	items.append(_separator())
	items.append(_command(&"site.check", "Check the planting", &"", &"_menu_check_planting"))
	return items


## The plant list, and the one thing a plant list is for.
##
## Every entry here reaches the catalogue rather than the scene, so this is the same menu in a scene
## with no yard: a plant list is data, and where a plant goes is the plan's business. None of them
## advertises a key, because none of them is done often enough to deserve one.
static func plant_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	items.append(_info(&"plant.info", "no plant list"))
	items.append(_separator())
	items.append(_command(&"plant.library", "Plant library...", &"plant_library", &"_menu_plant_library"))
	items.append(_command(&"plant.place", "Place the chosen plant", &"", &"_menu_plant_place"))
	items.append(_command(&"plant.stop", "Stop planting", &"", &"_menu_stop_planting"))
	items.append(_separator())
	items.append(_command(&"plant.import", "Import a plant list...", &"", &"_menu_plant_import"))
	items.append(_command(&"plant.export", "Export the plant list...", &"", &"_menu_plant_export"))
	return items


## The reference: every key in one place, which is the one thing a menu can offer that the
## on-screen hints cannot, because they are three lines in three corners.
static func help_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	items.append(_check(&"help.keys", "Drawing keys", &"", &"_menu_keys", &"keys_panel"))
	return items


## Every entry in the bar, flattened, each with the menu it sits under. What a test reads.
static func menu_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for menu: Dictionary in menu_plan():
		_collect_entries(String(menu["title"]), menu["items"], out)
	return out


static func _collect_entries(path: String, items: Array, out: Array[Dictionary]) -> void:
	for item: Dictionary in items:
		var entry: Dictionary = item
		entry["menu"] = path
		out.append(entry)
		if StringName(entry.get("kind", &"")) == &"submenu":
			_collect_entries(path + " > " + String(entry["label"]), entry["items"], out)


## The entries of one menu, for a test that wants to talk about the Draft menu.
static func items_for(title: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for menu: Dictionary in menu_plan():
		if String(menu["title"]) == title:
			var items: Array[Dictionary] = menu["items"]
			out = items
	return out


## What an entry says: its label, and the key that does the same thing when there is one.
##
## The key is written into the text rather than set as the item's accelerator. An accelerator is a
## second binding, and it fires *as well as* the input action: pressing P would plot the sheet
## twice, which is the kind of bug a menu makes easy and a legend cannot.
static func menu_label(entry: Dictionary) -> String:
	var label := String(entry.get("label", ""))
	var key := _key_label(StringName(entry.get("action", &"")))
	return label if key == "" else "%s    %s" % [label, key]


## Whether a checkable entry is on, decided from a snapshot of everything the bar reports on.
##
## Static and pure so the rule can be read and tested without a scene: which of these is on is the
## half of a menu that is easy to get wrong and impossible to see.
static func is_checked(state: StringName, value: Variant, world: Dictionary) -> bool:
	match state:
		&"mode":
			return int(world.get("mode", -1)) == int(value)
		&"drawing":
			return bool(world.get("drawing", false))
		&"tool":
			# A tool is shown as chosen only while the tools are out, which is the same rule the
			# palette follows: a menu highlighting a tool while the tools are put away would be
			# describing a mode that is not on.
			return bool(world.get("drawing", false)) and int(world.get("tool", -1)) == int(value)
		&"dimension_style":
			return StringName(world.get("dimension_style", &"")) == StringName(value)
		&"sheet":
			return String(world.get("sheet", "")) == String(value)
		&"scale":
			return is_equal_approx(float(world.get("plot_scale", 0.0)), float(value))
		&"presenting":
			return bool(world.get("presenting", false))
		&"tier":
			return int(world.get("tier", -1)) == int(value)
		&"still_size":
			return int(world.get("still_size", -1)) == int(value)
		&"keys_panel":
			return bool(world.get("keys_panel", false))
		&"hints":
			return bool(world.get("hints", true))
	return false


## Everything the bar reports on, as one snapshot. The checks are drawn from this rather than from
## the controls, so the menu describes the state rather than a button that happens to agree with it.
func menu_world() -> Dictionary:
	var world: Dictionary = {
		"mode": int(view_controller.mode) if view_controller != null else -1,
		"drawing": _draft != null and _draft.drawing,
		"tool": int(_draft.current_tool()) if _draft != null else -1,
		"dimension_style": StringName(_draft.dimension_style_name) if _draft != null else &"",
		"sheet": String(_draft.sheet) if _draft != null else "",
		"plot_scale": float(_draft.plot_scale) if _draft != null else 0.0,
		"presenting": presentation != null and presentation.is_active(),
		"tier": int(presentation.tier) if presentation != null else -1,
		"still_size": int(_still_size_option.selected) if _still_size_option != null else -1,
		"keys_panel": is_keys_open(),
		"hints": _show_hints,
		# What the File menu reports on: which drawing is open, whether it has been saved, and
		# what was open before. The recent list is in here so that the signature notices when it
		# changes - the one thing about the bar that is entries rather than ticks.
		"dirty": _draft != null and _draft.dirty,
		"drawing_path": String(_draft.drawing_path) if _draft != null else "",
		"drawing_state": _draft.drawing_state_text() if _draft != null else "",
		"recent": ", ".join(PackedStringArray(_draft.recent_drawings())) if _draft != null else "",
		# The plant list is in the signature only once it has been read - this snapshot is taken on
		# every state change, and it must not be the thing that reads four thousand species. What a
		# click would plant and how many are planted are cheap, and they are what moves.
		"plants": _plants.describe() if _plants != null else "",
		"planting": String(view_controller.planting_species) if view_controller != null else "",
		"planted": view_controller.planted_count() if view_controller != null else 0,
		# What the ground is stated to be, which is what every plant verdict is judged against: the
		# whole point of a ring that changes when a plant is dropped two metres to the left. One line
		# now rather than a radio state per attribute: the ground is edited in its own window, and the
		# menu reports what came of it.
		"ground": _ground_text(),
	}
	return world


## The drawing's own record of what the ground is like, or null in a scene with no drawing. The
## ground belongs to the document, so it travels in the file with the design it describes and moves
## with the undo stack like everything else on it.
func _ground_map() -> ZoneMapScript:
	if _draft == null:
		return null
	var document: DraftDocument = _draft.document
	if document == null:
		return null
	return document.environment


## What the ground is stated to be, in one line, for the Site menu to say rather than to imply.
func _ground_text() -> String:
	var map: ZoneMapScript = _ground_map()
	if map == null:
		return "there is no drawing to say what the ground is like"
	return map.describe()




## Build the menus from the plan.
##
## In code rather than in the scene for the same reason the palette is: the entries are derived
## from tables that already exist, and a scene file holding forty copies of them would be forty
## places to keep in step.
func _build_menu_bar() -> void:
	if menu_bar == null:
		return
	# A menu bar holds the keyboard like any other Control, and the keys belong to the drawing.
	menu_bar.focus_mode = Control.FOCUS_NONE
	for menu: Dictionary in menu_plan():
		var popup := PopupMenu.new()
		popup.name = String(menu["title"])
		popup.title = String(menu["title"])
		menu_bar.add_child(popup)
		_build_menu(popup, menu["items"])
	_hide_unavailable_menus()
	_refresh_menus()


## One menu's items, including any submenus, filling `_menu_items` as it goes: an item's id is its
## index, so the index of the entry in this array is the id the popup will report.
func _build_menu(popup: PopupMenu, items: Array) -> void:
	var entries: Array[Dictionary] = []
	for raw: Dictionary in items:
		var entry: Dictionary = raw
		var kind: StringName = entry.get("kind", &"command")
		if kind == &"separator":
			popup.add_separator()
		elif kind == &"submenu":
			var child := PopupMenu.new()
			child.name = String(entry["id"]).replace(".", "_") + "Menu"
			child.title = String(entry["label"])
			popup.add_child(child)
			_build_menu(child, entry["items"])
			popup.add_submenu_item(String(entry["label"]), child.name)
			# The recent drawings are the one set whose *entries* grow and shrink, so the menu
			# that holds them is kept rather than found again every time it changes.
			if String(entry["id"]) == "file.recent":
				_recent_popup = child
		else:
			var label := menu_label(entry)
			var wanted: bool = _menu_needs_met(StringName(entry.get("needs", NEEDS_NOTHING)))
			if kind == &"radio":
				popup.add_radio_check_item(label)
			elif kind == &"check":
				popup.add_check_item(label)
			else:
				popup.add_item(label)
			if kind == &"info":
				# A line that says something: never pressable, and never a method.
				popup.set_item_disabled(entries.size(), true)
			if not wanted:
				# Visible but switched off, so the menu still says what the program does in a
				# scene that cannot do it.
				popup.set_item_disabled(entries.size(), true)
		entries.append(entry)
	_menu_items[popup] = entries
	popup.id_pressed.connect(_on_menu_item_pressed.bind(popup))


## Whether what an entry needs is in this scene.
func _menu_needs_met(needs: StringName) -> bool:
	match needs:
		NEEDS_DRAFT:
			return _draft != null
		NEEDS_PRESENTATION:
			return presentation != null
	return true


## A menu whose whole subject is absent is not shown at all: a list of ten drawing tools in a
## scene with no drawing is not a menu, and every entry in it would be dead. The same rule the
## palette and the presentation panel are built by.
func _hide_unavailable_menus() -> void:
	if menu_bar == null:
		return
	for index in menu_bar.get_menu_count():
		var title: String = menu_bar.get_menu_title(index)
		if title == "Draft":
			menu_bar.set_menu_hidden(index, _draft == null)
		elif title == "Site":
			# The ground lives on the drawing, so a scene with no drawing has no ground to state.
			menu_bar.set_menu_hidden(index, _ground_map() == null)
		elif title == "Present":
			menu_bar.set_menu_hidden(index, presentation == null)


## Match the checks to the state, from the snapshot.
##
## Driven by a signature rather than by signals, like the palette and the presentation panel: the
## state a menu shows is changed from a key, a click, a menu entry and a script, and a signature
## cannot miss one of them the way a forgotten connection would.
func _refresh_menus() -> void:
	if menu_bar == null or _menu_items.is_empty():
		return
	var world: Dictionary = menu_world()
	var state: String = str(world)
	if state == _menu_state:
		return
	_menu_state = state
	for popup: PopupMenu in _menu_items.keys():
		var entries: Array = _menu_items[popup]
		for index in entries.size():
			var entry: Dictionary = entries[index]
			var kind: StringName = entry.get("kind", &"command")
			if kind == &"radio" or kind == &"check":
				popup.set_item_checked(
					index,
					is_checked(StringName(entry.get("state", &"")), entry.get("value", null), world)
				)
			# An entry that only means something in some states says which, and is shown switched
			# off rather than doing nothing when the state is not on: Save with nothing to save.
			var available := StringName(entry.get("enabled_when", &""))
			if available != &"" and kind != &"info":
				popup.set_item_disabled(index, not is_enabled(available, world))
	_refresh_file_menu()
	_refresh_plant_menu()
	_refresh_site_menu()


## An entry was chosen. The entry knows which method runs it, so there is no second list of ids
## here to fall out of step with the first.
func _on_menu_item_pressed(id: int, popup: PopupMenu) -> void:
	var entries: Array = _menu_items.get(popup, [])
	if id < 0 or id >= entries.size():
		return
	var entry: Dictionary = entries[id]
	var method := StringName(entry.get("method", &""))
	if method == &"" or not has_method(String(method)):
		return
	call(String(method), entry)
	# A menu is a Control, and choosing from one can leave it holding the keyboard that the
	# drawing keys belong to. This is the same release the HUD does at startup.
	release_keyboard_focus(self)


# --- what each entry does -------------------------------------------------------------


func _menu_plot(_entry: Dictionary) -> void:
	if _draft != null:
		_draft.plot()


func _menu_quit(_entry: Dictionary) -> void:
	# Quitting with unsaved work asks first. The drawing lives in memory until it is written, so
	# this is the last moment at which anybody could be warned.
	_guard_unsaved(&"quit")


# --- the drawing on disk --------------------------------------------------------------


## Whether an entry is available in this state, for the entries that come and go with the state
## rather than with the scene. Save is the only one: there is nothing to save until something has
## changed.
static func is_enabled(state: StringName, world: Dictionary) -> bool:
	match state:
		&"dirty":
			return bool(world.get("dirty", false))
	return true


## The file dialogs: where a drawing comes from and where it goes.
##
## Built in code, like the rest of this file's furniture, and pointed at the drawings folder
## rather than at the filesystem at large: a drawing lives in `user://drawings`, and a dialog that
## opens anywhere invites somebody to file their drawing where the recent list cannot follow.
func _build_file_dialogs() -> void:
	# Parented to the HUD - the CanvasLayer - and not to `Root`, which is a Control with
	# `focus_mode` off so that nothing in the HUD can take the keyboard away from the drawing.
	# Godot 4.7 inherits focus behaviour down the tree, so a dialog under `Root` could not focus
	# its own file-name field: it opened, and could not be typed into. A CanvasLayer passes no
	# focus behaviour on, and the dialog's field gets the keyboard for as long as it is up.
	_open_dialog = FileDialog.new()
	_open_dialog.name = "OpenDrawing"
	_open_dialog.title = "Open a drawing"
	_open_dialog.access = FileDialog.ACCESS_USERDATA
	_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.current_dir = StoreScript.DIR
	_open_dialog.filters = PackedStringArray(["*.json ; Drawings"])
	_open_dialog.file_selected.connect(_on_open_chosen)
	add_child(_open_dialog)

	_save_dialog = FileDialog.new()
	_save_dialog.name = "SaveDrawing"
	_save_dialog.title = "Save the drawing"
	_save_dialog.access = FileDialog.ACCESS_USERDATA
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.current_dir = StoreScript.DIR
	_save_dialog.filters = PackedStringArray(["*.json ; Drawings"])
	_save_dialog.file_selected.connect(_on_save_as_chosen)
	add_child(_save_dialog)

	_discard_dialog = ConfirmationDialog.new()
	_discard_dialog.name = "DiscardChanges"
	_discard_dialog.title = "Unsaved changes"
	# Two buttons, and neither of them is "save": the way to save is one click away in the menu
	# that raised this, and a dialog that can write files is a dialog that can write the wrong
	# one. What it asks is only whether the changes may be let go.
	_discard_dialog.ok_button_text = "Discard"
	_discard_dialog.cancel_button_text = "Keep editing"
	_discard_dialog.confirmed.connect(_on_discard_confirmed)
	_discard_dialog.canceled.connect(_on_discard_cancelled)
	add_child(_discard_dialog)


func _file_dialog_open() -> bool:
	return (_open_dialog != null and _open_dialog.visible) \
		or (_save_dialog != null and _save_dialog.visible) \
		or (_discard_dialog != null and _discard_dialog.visible)


## Ask before throwing work away, then do what was asked for.
##
## The action is held as an id rather than as a Callable: a question can sit open while the scene
## moves on, and a captured closure would then run against a world that is no longer there.
func _guard_unsaved(next: StringName) -> void:
	if _draft == null or not _draft.dirty or _discard_dialog == null:
		_run_pending(next)
		return
	_pending_action = next
	_discard_dialog.dialog_text = "%s\n\nDiscard the changes?" % _draft.drawing_state_text()
	_discard_dialog.popup_centered()


func _on_discard_confirmed() -> void:
	var next := _pending_action
	_pending_action = &""
	_run_pending(next)


func _on_discard_cancelled() -> void:
	# Closing the question decides nothing, so the action is dropped rather than left armed for
	# whatever the next click happens to be.
	_pending_action = &""
	_pending_path = ""


func _run_pending(next: StringName) -> void:
	match next:
		&"new":
			if _draft != null:
				_draft.new_drawing()
		&"open":
			if _pending_path.is_empty():
				open_drawing_dialog()
			else:
				var path: String = _pending_path
				_pending_path = ""
				if _draft != null:
					_draft.open_drawing(path)
		&"quit":
			get_tree().quit()


func open_drawing_dialog() -> void:
	if _open_dialog == null:
		return
	_open_dialog.current_dir = StoreScript.DIR
	_open_dialog.popup_centered_ratio(0.7)


## The Save As dialog, offered a name. The project's own name to begin with, because a drawing of
## a garden is much more often called what the garden is called than it is called "untitled".
func save_drawing_dialog() -> void:
	if _save_dialog == null or _draft == null:
		return
	_save_dialog.current_dir = StoreScript.DIR
	# Not `name`: this is a CanvasLayer, and `name` is the node's own.
	var file_name := StoreScript.display_name(_draft.drawing_path)
	if file_name.is_empty():
		file_name = StoreScript.sanitise(_draft.project_name)
	_save_dialog.current_file = file_name + StoreScript.EXTENSION
	_save_dialog.popup_centered_ratio(0.7)


func _on_open_chosen(path: String) -> void:
	_pending_path = ""
	if _draft != null:
		_draft.open_drawing(path)
	release_keyboard_focus(self)


func _on_save_as_chosen(path: String) -> void:
	if _draft == null:
		return
	# A name typed without the extension is given one rather than trusted: a drawing the Open
	# dialog cannot see is a drawing that cannot be opened again.
	var target := path if path.ends_with(StoreScript.EXTENSION) else path + StoreScript.EXTENSION
	_draft.save_drawing(target)
	release_keyboard_focus(self)


func _menu_new_drawing(_entry: Dictionary) -> void:
	_guard_unsaved(&"new")


func _menu_open_drawing(_entry: Dictionary) -> void:
	_pending_path = ""
	_guard_unsaved(&"open")


func _menu_open_recent(entry: Dictionary) -> void:
	_pending_path = str(entry.get("value", ""))
	_guard_unsaved(&"open")


func _menu_save_drawing(_entry: Dictionary) -> void:
	if _draft == null:
		return
	# A drawing with no name yet is what Save As is for, and Save standing in for it is what a
	# person expects: the alternative is being told the drawing has no name on the one command
	# that exists to give it one.
	if _draft.drawing_path.is_empty():
		save_drawing_dialog()
		return
	_draft.save_drawing()


func _menu_save_drawing_as(_entry: Dictionary) -> void:
	save_drawing_dialog()


## The two parts of the File menu that are live: the line naming the drawing, and the list of what
## was opened recently. Everything else in the bar is a fixed set of entries whose ticks move.
func _refresh_file_menu() -> void:
	if _draft == null:
		return
	var named := _find_item(&"file.info")
	if not named.is_empty():
		var popup: PopupMenu = named[0]
		popup.set_item_text(int(named[1]), _draft.drawing_state_text())
	var recent := ", ".join(PackedStringArray(_draft.recent_drawings()))
	if recent != _recent_filled:
		_recent_filled = recent
		_fill_recent_menu()


## One item of the bar, by id, as `[popup, index, entry]`, or nothing when it is not there.
func _find_item(id: StringName) -> Array:
	for popup: PopupMenu in _menu_items.keys():
		var entries: Array = _menu_items[popup]
		for index in entries.size():
			if StringName(entries[index].get("id", &"")) == id:
				return [popup, index, entries[index]]
	return []


## Refill the list of recently opened drawings.
##
## The one part of the bar whose *entries* are not fixed: a recent list built once at startup
## would never show a drawing that has just been saved, and one that was never pruned would offer
## files that are no longer there. The drawings themselves come from the store, which drops a
## remembered drawing the moment it stops existing.
func _fill_recent_menu() -> void:
	if _recent_popup == null or _draft == null:
		return
	_recent_popup.clear()
	var entries: Array[Dictionary] = []
	var paths: Array[String] = _draft.recent_drawings()
	if paths.is_empty():
		_recent_popup.add_item("nothing yet")
		_recent_popup.set_item_disabled(0, true)
		entries.append({
			"kind": &"info", "id": &"file.recent.none", "label": "nothing yet",
			"action": &"", "needs": NEEDS_NOTHING, "value": null,
		})
	else:
		for path in paths:
			# Not `name`: this is a CanvasLayer, and `name` is the node's own.
			var file_name := StoreScript.display_name(path)
			_recent_popup.add_item(file_name)
			entries.append({
				"kind": &"command", "id": StringName("file.recent." + file_name),
				"label": file_name, "action": &"", "method": &"_menu_open_recent",
				"needs": NEEDS_DRAFT, "value": path,
			})
	_menu_items[_recent_popup] = entries


func _menu_set_sheet(entry: Dictionary) -> void:
	if _draft != null:
		_draft.sheet = String(entry["value"])


func _menu_set_scale(entry: Dictionary) -> void:
	if _draft != null:
		_draft.plot_scale = float(entry["value"])


func _menu_undo(_entry: Dictionary) -> void:
	if _draft != null:
		_draft.undo()


func _menu_redo(_entry: Dictionary) -> void:
	if _draft != null:
		_draft.redo()


func _menu_drop_point(_entry: Dictionary) -> void:
	if _draft != null:
		_draft.undo_point()


func _menu_cancel_shape(_entry: Dictionary) -> void:
	if _draft != null:
		_draft.cancel()


func _menu_finish(_entry: Dictionary) -> void:
	if _draft != null:
		_draft.finish()


func _menu_close_shape(_entry: Dictionary) -> void:
	if _draft != null:
		_draft.finish_closed()


func _menu_set_dimension_style(entry: Dictionary) -> void:
	if _draft != null:
		_draft.set_dimension_style(StringName(entry["value"]))


func _menu_cycle_dimension_style(_entry: Dictionary) -> void:
	if _draft != null:
		_draft.cycle_dimension_style()


func _menu_toggle_drawing(_entry: Dictionary) -> void:
	if _draft != null:
		_draft.set_drawing(not _draft.drawing)


func _menu_arm_tool(entry: Dictionary) -> void:
	if _draft != null:
		@warning_ignore("int_as_enum_without_cast")
		_draft.arm(int(entry["value"]))


func _menu_show_mode(entry: Dictionary) -> void:
	if view_controller != null:
		@warning_ignore("int_as_enum_without_cast")
		view_controller.show_mode(int(entry["value"]))


func _menu_fit(_entry: Dictionary) -> void:
	if view_controller != null:
		view_controller.fit_plan_to_yard()


func _menu_painted(_entry: Dictionary) -> void:
	open_painted()


func _menu_toggle_hints(_entry: Dictionary) -> void:
	_show_hints = not _show_hints
	_apply_hints_visibility()


func _menu_toggle_presentation(_entry: Dictionary) -> void:
	if presentation == null:
		return
	if presentation.is_active():
		presentation.end()
		return
	presentation.begin(presentation.tier)


func _menu_set_tier(entry: Dictionary) -> void:
	if presentation != null:
		presentation.set_tier(int(entry["value"]))


func _menu_frame_yard(_entry: Dictionary) -> void:
	if presentation != null:
		presentation.frame_yard()


func _menu_set_still_size(entry: Dictionary) -> void:
	if _still_size_option != null:
		_still_size_option.selected = int(entry["value"])


func _menu_render_still(_entry: Dictionary) -> void:
	_on_render_still()


func _menu_save_site(_entry: Dictionary) -> void:
	if presentation != null:
		presentation.save_site()


func _menu_keys(_entry: Dictionary) -> void:
	if is_keys_open():
		close_keys()
	else:
		open_keys()


# --- the key reference ----------------------------------------------------------------


## The keys, in one place.
##
## Every line is a string that already exists - the hint lines the HUD shows, and the drafting
## legend built from the tool tables - so this panel cannot disagree with the corner of the screen
## it is quoting. It is built in code for that reason: it is a view of three tables, not a fourth
## copy of them.
func _build_keys_panel() -> void:
	var root := get_node_or_null(^"Root")
	if root == null:
		return
	var wrapper := CenterContainer.new()
	wrapper.name = "KeysPanel"
	wrapper.set_anchors_preset(Control.PRESET_FULL_RECT)
	# The wrapper is only a placement; the panel inside it takes the clicks, so the drawing
	# underneath is not blocked by an invisible full-screen control.
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.visible = false

	var panel := PanelContainer.new()
	panel.name = "Page"
	panel.custom_minimum_size = Vector2(700.0, 0.0)
	if top_bar != null:
		# The same furniture as every other box on the screen, borrowed rather than copied: one
		# panel style, so a change to it changes all of them.
		panel.add_theme_stylebox_override("panel", top_bar.get_theme_stylebox("panel"))
	var column := VBoxContainer.new()
	column.name = "Column"
	panel.add_child(column)

	var heading := Label.new()
	heading.name = "Heading"
	heading.text = "Keys"
	column.add_child(heading)

	var body := Label.new()
	body.name = "KeysText"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = keys_text()
	column.add_child(body)

	var footer := Label.new()
	footer.name = "Footer"
	footer.add_theme_font_size_override("font_size", 12)
	footer.text = keys_footer()
	column.add_child(footer)

	var close_button := Button.new()
	close_button.name = "CloseKeys"
	close_button.text = "Close"
	close_button.pressed.connect(close_keys)
	column.add_child(close_button)

	wrapper.add_child(panel)
	_keys_panel = wrapper
	root.add_child(wrapper)


## The pages of the reference, from the strings the HUD already shows.
func keys_text() -> String:
	var rows: Array[String] = []
	rows.append("Top-down and overhead")
	rows.append("    " + _hints_for(ViewController.ViewMode.PLAN_2D))
	rows.append("Ground view")
	rows.append("    " + HINTS_GROUND)
	rows.append("Drawing")
	rows.append_array(drafting_rows())
	return "\n".join(PackedStringArray(rows))


## What the reference says about the program itself.
func keys_footer() -> String:
	return "landscaping planner    Godot %s    sheets are written to user://sheets, stills to user://proposals" % String(
		Engine.get_version_info()["string"]
	)


func is_keys_open() -> bool:
	return _keys_panel != null and _keys_panel.visible


func open_keys() -> void:
	if _keys_panel != null:
		_keys_panel.visible = true


func close_keys() -> void:
	if _keys_panel != null:
		_keys_panel.visible = false


## Show the line of hints or not, remembering that a presentation takes them away as well.
func _apply_hints_visibility() -> void:
	if hints != null:
		hints.visible = _show_hints and not _presenting


# --- the plant list -----------------------------------------------------------------------


## The library: a window, the browser in it, and the two dialogs a plant list arrives and leaves by.
##
## A `Window` rather than a panel in `Root`, and that is the whole reason it can have a search box:
## `Root` is built focus-free so that nothing in this HUD can take the drawing keys away, and the one
## exception this project allows is a modal window (spec REQ 8.7). Inside this window the controls
## own the keyboard; outside it, nothing has changed.
func _build_plant_library() -> void:
	_plant_window = Window.new()
	_plant_window.name = "PlantLibrary"
	_plant_window.title = "Plant library"
	_plant_window.exclusive = false
	_plant_window.min_size = Vector2i(760, 460)
	_plant_window.close_requested.connect(close_plant_browser)
	add_child(_plant_window)

	_plant_browser = PlantBrowserScript.new()
	_plant_browser.name = "Browser"
	_plant_browser.set_anchors_preset(Control.PRESET_FULL_RECT)
	_plant_browser.plant_chosen.connect(_on_plant_chosen)
	_plant_browser.import_requested.connect(_on_plant_import_requested)
	_plant_browser.export_requested.connect(_on_plant_export_requested)
	_plant_window.add_child(_plant_browser)

	# Imported from wherever the file is - a nursery's list arrives as a download, not as something
	# already filed in this program's folder - and exported into `user://plants`, where the list the
	# program reads lives.
	_plant_import_dialog = FileDialog.new()
	_plant_import_dialog.name = "ImportPlantList"
	_plant_import_dialog.title = "Import a plant list"
	_plant_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_plant_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_plant_import_dialog.filters = PackedStringArray(["*.json ; Plant lists"])
	_plant_import_dialog.file_selected.connect(_on_plant_import_chosen)
	add_child(_plant_import_dialog)

	_plant_export_dialog = FileDialog.new()
	_plant_export_dialog.name = "ExportPlantList"
	_plant_export_dialog.title = "Export the plant list"
	_plant_export_dialog.access = FileDialog.ACCESS_USERDATA
	_plant_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_plant_export_dialog.current_dir = PlantCatalogueScript.DEFAULT_PATH.get_base_dir()
	_plant_export_dialog.current_file = "plant-list.json"
	_plant_export_dialog.filters = PackedStringArray(["*.json ; Plant lists"])
	_plant_export_dialog.file_selected.connect(_on_plant_export_chosen)
	add_child(_plant_export_dialog)

	# Not shown until it is asked for. A window is shown by showing it, and a library that appeared
	# the moment the program started would be a program that opens with somebody else's plant list
	# over the drawing.
	_plant_window.hide()


## The plants section of the palette: the catalogue as a list under the drawing tools.
##
## The library answers "which plant is right for this spot" - four thousand species, filters, a search
## box, a detail pane. It is a window, and it has to be, because it has a text field in it and a text
## field is the one thing this HUD may not own outside a modal window. This answers the other
## question, which is "put that one down again", and it answers it where the designer is already
## looking. Between them a bed is a dozen clicks rather than a dozen trips through a window.
func _build_plant_panel() -> void:
	if palette_column == null or _plant_panel != null:
		return
	var panel: PlantPanel = PlantPanelScript.new()
	panel.name = "Plants"
	# Built before it is added, and built by hand: the panel's `_ready` would build it with a default
	# label, and the key this project writes into every label comes from the input map.
	panel.build("Library...  (%s)" % _key_label(&"plant_library"))
	panel.bind(plant_list())
	panel.plant_chosen.connect(_on_plant_panel_chosen)
	panel.library_requested.connect(open_plant_browser)
	panel.stop_requested.connect(_on_plant_panel_stop)
	palette_column.add_child(panel)
	_plant_panel = panel


## Choosing from the palette arms the plant and changes nothing else: the library closes on a choice
## because the choice was made to get back to the plan, and here there is nothing to close.
func _on_plant_panel_chosen(species_id: StringName) -> void:
	_arm_planting(species_id)


func _on_plant_panel_stop() -> void:
	if view_controller != null:
		view_controller.stop_planting()


## Match the plants section to the controller. Bound to whatever the list is now, because an import
## replaces the catalogue itself and a panel still listing the plants from this morning would look
## like an import that failed. The expensive part - the rows - is only rebuilt when the catalogue or
## the tag changes; a plant count is a label.
func _refresh_plant_panel() -> void:
	if _plant_panel == null:
		return
	var catalogue: PlantCatalogue = plant_list()
	if _plant_panel.catalogue != catalogue:
		_plant_panel.bind(catalogue)
	var in_hand: StringName = &""
	var standing: int = 0
	if view_controller != null:
		in_hand = view_controller.planting_species
		standing = view_controller.planted_count()
	_plant_panel.refresh(in_hand, standing)


## The plant list, read once and kept.
##
## The first run has no catalogue of its own, so the list the project ships with is the list - read
## from `res://` and held in memory until something changes it, at which point it is written to
## `user://`. A shipped list stays a shipped list, and a catalogue somebody has edited is theirs.
func plant_list() -> PlantCatalogue:
	if _plants != null:
		return _plants
	var read: Dictionary = PlantCatalogueScript.load_from(PlantCatalogueScript.DEFAULT_PATH)
	if bool(read["ok"]):
		_plants = read["catalogue"]
	else:
		var seeded: Dictionary = PlantCatalogueScript.load_from(STARTER_PLANT_LIST)
		_plants = seeded["catalogue"] if bool(seeded["ok"]) else PlantCatalogueScript.make()
	# A person's own collections live in their own file and are read on top of the catalogue, which
	# is what keeps them out of the way of an import that replaces the catalogue wholesale.
	_plants.load_collections()
	return _plants


## What the Plant menu says on itself: what the list is, and what a click would put down.
func plant_state_text() -> String:
	var catalogue: PlantCatalogue = plant_list()
	if view_controller != null and view_controller.is_planting():
		var species: PlantSpecies = catalogue.get_species(view_controller.planting_species)
		if species != null:
			return "planting %s" % species.display_name()
	var planted: int = view_controller.planted_count() if view_controller != null else 0
	var words: String = "%d species, %d planted" % [catalogue.count(), planted]
	var problems: Array[String] = catalogue.problems()
	if not problems.is_empty():
		words += "  -  %d entries need attention" % problems.size()
	return words


func open_plant_browser() -> void:
	if _plant_window == null:
		return
	_refresh_plant_browser()
	_plant_window.popup_centered(Vector2i(1080, 680))
	if _plant_browser != null:
		_plant_browser.focus_search()


func close_plant_browser() -> void:
	if _plant_window != null:
		_plant_window.hide()


## The ground: the site's conditions and one statement per area of the plan.
##
## A `Window` like the library, and for the same reason - it has dropdowns in it, and `Root` is built
## focus-free so that nothing in the HUD can take the drawing keys. Built by hand rather than left to
## its own `_ready`, so that the window the designer opens is the window this file has already wired
## to the menu, the drawing and the planting check.
func _build_ground_window() -> void:
	if _ground_window != null:
		return
	_ground_window = GroundWindowScript.new()
	_ground_window.name = "GroundWindow"
	add_child(_ground_window)
	_ground_window.ground_changed.connect(_on_ground_changed)
	_ground_window.check_requested.connect(_on_ground_check_requested)
	_ground_window.hide()


## Open it, pointed at the drawing that is open now.
func open_ground_window() -> void:
	if _ground_window == null:
		return
	if _draft == null or _draft.document == null:
		return
	_ground_window.document = _draft.document
	_ground_window.refresh()
	_ground_window.popup_centered()
	# A window holds the keyboard while it is up, which is exactly what a window is for; the moment
	# it closes the drawing keys belong to the drawing again.
	release_keyboard_focus(self)


func close_ground_window() -> void:
	if _ground_window != null:
		_ground_window.hide()


func is_ground_window_open() -> bool:
	return _ground_window != null and _ground_window.visible


## The ground changed in the window: the Site menu's line about it is now stale, and so is the ring
## around whatever plant is in hand.
func _on_ground_changed() -> void:
	_refresh_menus()


func _on_ground_check_requested() -> void:
	_menu_check_planting({})


## Point the browser at the catalogue, reading it only if it has never been read.
##
## `refresh` rather than `bind` once it is bound, because `bind` rebuilds the tag chips: what is
## ticked is a person's filter, and reopening the library must not throw it away.
func _refresh_plant_browser() -> void:
	if _plant_browser == null:
		return
	if _plant_browser.catalogue == null:
		_plant_browser.bind(plant_list())
	else:
		_plant_browser.refresh()


func _menu_plant_library(_entry: Dictionary) -> void:
	open_plant_browser()


## Put the last chosen plant back in hand. With nothing chosen yet, the library is what is wanted,
## which is a better answer than a command that does nothing.
func _menu_plant_place(_entry: Dictionary) -> void:
	if _plant_chosen.is_empty():
		open_plant_browser()
		return
	_arm_planting(_plant_chosen)


func _menu_stop_planting(_entry: Dictionary) -> void:
	if view_controller != null:
		view_controller.stop_planting()


# --- what the ground is like, and what that means for the planting -----------------------


## Open the ground window: the site's conditions and one statement per area of the plan.
func _menu_ground_window(_entry: Dictionary) -> void:
	open_ground_window()


## Ask the drawing what it already knows about the ground: a building is shade, a hard surface is hot
## and dry. Nothing else is read, because nothing else on a plan is a fact about the ground rather
## than an intention about the design - and what is not read is named in the menu, so a grey ring
## everywhere has an answer.
func _menu_read_ground(_entry: Dictionary) -> void:
	var map: ZoneMapScript = _ground_map()
	if map == null:
		return
	var document: DraftDocument = _draft.document
	var count: int = document.read_environment_from_drawing()
	if count <= 0:
		_plant_say(
			"the drawing has no buildings or hard surfaces on it, so it says nothing about the ground"
		)
		return
	_plant_say("read %d area%s of ground from the drawing" % [count, "" if count == 1 else "s"])
	_refresh_menus()


## Report on the planting that is already in the ground: which plants the plan's own conditions say
## are in the wrong place.
##
## The answer arrives in the library's status line because it is a list, and because the library is
## where a designer goes to do something about it. The window is opened: a report nobody can see is
## not a report, and the ring at the cursor only ever tells you about the plant in your hand.
func _menu_check_planting(_entry: Dictionary) -> void:
	var yard: Node3D = view_controller.yard if view_controller != null else null
	var report: Dictionary = PlantSuitabilityScript.audit(plant_list(), yard, _ground_map())
	var lines: Array[String] = PlantSuitabilityScript.audit_lines(report)
	var text: String = String(report["text"])
	if not lines.is_empty():
		text = "%s   %s" % [text, " | ".join(lines)]
	open_plant_browser()
	_plant_say(text)


func _menu_plant_import(_entry: Dictionary) -> void:
	if _plant_import_dialog != null:
		_plant_import_dialog.popup_centered_ratio(0.7)


func _menu_plant_export(_entry: Dictionary) -> void:
	if _plant_export_dialog != null:
		_plant_export_dialog.current_dir = PlantCatalogueScript.DEFAULT_PATH.get_base_dir()
		_plant_export_dialog.popup_centered_ratio(0.7)


## The browser's two buttons reach the same commands the menu does, through these: a menu entry
## takes the entry that was pressed and a button has no such thing to pass, so the two doors are
## kept and the work stays in one place.
func _on_plant_import_requested() -> void:
	_menu_plant_import({})


func _on_plant_export_requested() -> void:
	_menu_plant_export({})


## Choosing a plant arms it and closes the library: the very next click is on the plan, which is
## where the plant was going. It stays armed afterwards, so a bed is a dozen clicks rather than a
## dozen trips back here.
func _on_plant_chosen(species_id: StringName) -> void:
	if not _arm_planting(species_id):
		return
	close_plant_browser()


func _arm_planting(species_id: StringName) -> bool:
	if view_controller == null or not view_controller.arm_planting(plant_list(), species_id):
		return false
	_plant_chosen = species_id
	# Planting happens on the plan, and a click in the ground view is not a click on the plan.
	if view_controller.mode == ViewController.ViewMode.GROUND:
		view_controller.show_mode(ViewController.ViewMode.PLAN_2D)
	return true


func _on_plant_import_chosen(path: String) -> void:
	var catalogue: PlantCatalogue = plant_list()
	var report: Dictionary = catalogue.import_json(path, false)
	if not bool(report["ok"]):
		_plant_say(String(report["reason"]))
		return
	# The catalogue a person has just added to is the catalogue from now on, so it is written: an
	# import that lived only in memory would be gone the next time the program opened.
	var written: Dictionary = catalogue.save_to()
	if not bool(written["ok"]):
		_plant_say(String(written["reason"]))
		return
	var refused: Array = report["refused"]
	var words: String = "imported %d new, %d replaced" % [int(report["added"]), int(report["replaced"])]
	if not refused.is_empty():
		words += ", %d refused" % refused.size()
	_refresh_plant_browser()
	open_plant_browser()
	_plant_say(words)
	release_keyboard_focus(self)


func _on_plant_export_chosen(path: String) -> void:
	var target: String = path if path.ends_with(".json") else path + ".json"
	var written: Dictionary = plant_list().export_json(target)
	if not bool(written["ok"]):
		_plant_say(String(written["reason"]))
		return
	# The species only: a collection is one person's list of plants, and a list sent to a nursery is
	# the plants themselves.
	open_plant_browser()
	_plant_say("wrote %d species to %s" % [int(written["count"]), target])
	release_keyboard_focus(self)


func _plant_say(text: String) -> void:
	if _plant_browser != null:
		_plant_browser.set_status(text)


## The live part of the Site menu: the line describing what the ground is stated to be. The radios
## need nothing here - the snapshot drives those - but a sentence derived from a map has to be
## written out, in the same way the File menu writes out which drawing is open.
func _refresh_site_menu() -> void:
	var named := _find_item(&"site.ground")
	if not named.is_empty():
		var popup: PopupMenu = named[0]
		popup.set_item_text(int(named[1]), _ground_text())


## The two live parts of the Plant menu: the line describing the list, and the one entry that only
## means something while a plant is in hand.
func _refresh_plant_menu() -> void:
	var named := _find_item(&"plant.info")
	if not named.is_empty():
		var popup: PopupMenu = named[0]
		popup.set_item_text(int(named[1]), plant_state_text())
	var stop := _find_item(&"plant.stop")
	if not stop.is_empty():
		var stop_popup: PopupMenu = stop[0]
		stop_popup.set_item_disabled(
			int(stop[1]), view_controller == null or not view_controller.is_planting()
		)
