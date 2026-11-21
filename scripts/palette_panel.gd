class_name PalettePanel
extends VBoxContainer
## The left-hand palette: the drawing tools, the editing commands, the layer and its lock, and the handful of
## ways a drawing leaves the application - all of it within reach beside the plan rather than behind a menu.
##
## It is the same kind of thing as `PlantPanel` and the menu bar, and for the same reason: **built in code
## from tables that already exist** (`DraftTool.DRAFTING_TOOLS`, `DraftController.EDIT_TOOLS`, the layers the
## drawing has), so there is no second list of tools to keep in step with the first. A scene file holding
## nine near-identical buttons would be a third copy of that list.
##
## **It owns no design state.** It says what was chosen - `armed`, `tool_chosen`, `edit_chosen`,
## `command_chosen`, `layer_chosen`, `lock_chosen` - and the HUD does the work, exactly as `PlantPanel` says
## what was chosen and the HUD does the planting. Everything it draws is read back from the controller it is
## handed, and it decides what to redraw from a **signature rather than a signal**: the controller is changed
## from several places - a key, a click, a button here - and a signature cannot miss one the way a forgotten
## connection would.
##
## Two things it deliberately does not know. The **words** this program writes for a key ("Ctrl+Z") are handed
## in with the build, because the input map is the HUD's to read and a palette that guessed them would be a
## second answer to what a key does. And whether the layer is **locked** arrives with each refresh, because
## "not locked when there is nothing to draw on" is one rule and it is the HUD's.
##
## Nothing here holds the keyboard. Godot hands Tab to focus navigation the moment a Control holds it, and a
## focused Button swallows the keys the drawing tools are driven by - which is why the HUD sweeps the focus
## off every button it draws, this panel's included, and must do it after this panel is built.

## The tools armed, or put away again.
signal armed(on: bool)
## One of the drawing tools, by `DraftTool.Kind`.
signal tool_chosen(kind: int)
## One of the editing commands, by `DraftController.EditKind`.
signal edit_chosen(kind: int)
## One of the commands under the rows of tools, by the action name the menu bar gives it too.
signal command_chosen(action: StringName)
## The layer the next shape is drawn on.
signal layer_chosen(layer_name: StringName)
## The lock on the layer in hand, as the button now reads.
signal lock_chosen(locked: bool)

const DraftToolScript := preload("res://scripts/draft/draft_tool.gd")
const DraftControllerScript := preload("res://scripts/draft/draft_controller.gd")
## The palette's layout - how many tools across, how wide a cell - which lives beside the fitting that reads
## the same numbers: `ToolPalette` re-flows these rows around the words a phone draws, and it measures them
## against these widths.
const ToolPaletteScript := preload("res://scripts/tool_palette.gd")

## The rows of tools, in the order a person reaches for them.
const DRAFTING_TOOLS: Array = DraftToolScript.DRAFTING_TOOLS
const EDIT_TOOLS: Array = DraftControllerScript.EDIT_TOOLS

## The commands under the tools, in the rows this palette has always drawn them in: what to do with the shape
## in hand, then with the drawing, then the two ways it leaves the application, then the dimension standard.
## The grouping is a layout and belongs here; **every action named is an action the menu bar holds too**, so
## pressing one runs the same door the menu runs rather than a second implementation of the same command.
const COMMAND_ROWS: Array = [
	["ShapeRow", [[&"draft_finish", "Finish"], [&"draft_close", "Close"], [&"draft_cancel", "Cancel"]]],
	["EditRow", [[&"draft_undo", "Undo"], [&"draft_redo", "Redo"], [&"draft_undo_point", "Drop"]]],
	["SheetRow", [[&"draft_plot", "Plot a sheet"], [&"vis_painted", "Painted plan"]]],
	["StyleRow", [[&"draft_dimension_style", "Standard"]]],
]

## The controller this palette reports on and sends choices to. Null until `build`, and null is survivable:
## a HUD with no drawing still gets a palette, drawn and dead, rather than nothing at all.
var _draft: DraftControllerScript = null
## The words for each action's key, handed in by the HUD. An action that is not here has no key, which is the
## honest answer for a command nobody bound and exactly what the label then draws.
var _keys: Dictionary = { }

var _arm_button: CheckButton = null
var _layer_option: OptionButton = null
var _lock_button: CheckButton = null
var _style_button: Button = null
var _undo_button: Button = null
var _redo_button: Button = null
var _tool_buttons: Array[Button] = []
var _edit_buttons: Array[Button] = []
## The layer names the drop-down holds, in the order it holds them. Taken from the drawing when the palette is
## built: a layer added while the palette stands is a change to the drawing, and the palette is rebuilt where
## a drawing is opened rather than being asked to grow.
var _layer_names: Array[StringName] = []
## What the controls were last set to, so a check every frame does not touch a button that is already right.
var _state: String = ""
var _built: bool = false


## Build the controls. Called once by the HUD, and callable directly so that a test can build a palette with no
## scene tree - a bare `PalettePanel.new()` never gets `_ready`, which is why there is no `_ready` here.
##
## `draft` may be null: the rows are then drawn from the tables alone and every button does nothing, which is
## what a scene with no drawing gets.
func build(draft: DraftControllerScript, keys: Dictionary) -> void:
	if _built:
		return
	_built = true
	_draft = draft
	_keys = keys

	_arm_button = CheckButton.new()
	_arm_button.name = "ArmButton"
	_arm_button.text = "Drawing (%s)" % key_words(&"draft_mode")
	_arm_button.tooltip_text = "Arm the drawing tools, and put them away again"
	_arm_button.toggled.connect(_on_armed)
	add_child(_arm_button)

	var grid := GridContainer.new()
	grid.name = "Tools"
	grid.columns = ToolPaletteScript.PALETTE_COLUMNS
	add_child(grid)
	for pair: Array in DRAFTING_TOOLS:
		var kind: int = pair[2]
		var button := Button.new()
		# Named after the action it stands for, so the node tree says what each button does rather than
		# "Button17".
		button.name = String(pair[0])
		button.text = label(pair, key_words(pair[0]))
		button.tooltip_text = "Draw a %s" % String(pair[1])
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(ToolPaletteScript.PALETTE_CELL_WIDTH, 0.0)
		button.pressed.connect(_on_tool_pressed.bind(kind))
		grid.add_child(button)
		_tool_buttons.append(button)

	var edit_grid := GridContainer.new()
	edit_grid.name = "EditTools"
	edit_grid.columns = ToolPaletteScript.PALETTE_EDIT_COLUMNS
	add_child(edit_grid)
	for pair: Array in EDIT_TOOLS:
		var edit_button := Button.new()
		edit_button.name = String(pair[0])
		edit_button.text = label(pair, key_words(pair[0]))
		edit_button.tooltip_text = String(pair[3])
		edit_button.toggle_mode = true
		edit_button.custom_minimum_size = Vector2(ToolPaletteScript.PALETTE_EDIT_CELL_WIDTH, 0.0)
		edit_button.pressed.connect(_on_edit_pressed.bind(int(pair[2])))
		edit_grid.add_child(edit_button)
		_edit_buttons.append(edit_button)

	add_child(HSeparator.new())
	_build_layer_row()
	_build_command_rows()


## The layer the next shape goes on, and the lock that stops it being picked.
##
## The lock sits on the layer's own row because it is a property of that layer rather than a tool. It is
## `FOCUS_NONE` like `PlantPanel`'s controls, so a check box here cannot swallow Tab or Enter on its way to
## the drawing; the rest of the palette's buttons are taken out of the focus chain in one sweep by the HUD,
## which runs after this panel is built.
func _build_layer_row() -> void:
	# A flow container rather than a box: its minimum width is its **widest single child**, not the sum of
	# them all, so a row whose words do not fit the panel wraps onto a second line instead of widening the
	# panel out from under the drawing. A desk's sums already fit, so it draws exactly what it drew before.
	var layer_row := HFlowContainer.new()
	layer_row.name = "LayerRow"
	var layer_caption := Label.new()
	layer_caption.text = "Layer"
	layer_row.add_child(layer_caption)
	_layer_option = OptionButton.new()
	_layer_option.name = "LayerOption"
	_layer_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layer_option.tooltip_text = "The layer the next shape is drawn on"
	_layer_names.clear()
	if _draft != null:
		for choice: Dictionary in _draft.layer_choices():
			_layer_names.append(StringName(choice["name"]))
			_layer_option.add_item(String(choice["name"]))
			_layer_option.set_item_tooltip(_layer_option.item_count - 1, String(choice["purpose"]))
	_layer_option.item_selected.connect(_on_layer_selected)
	layer_row.add_child(_layer_option)
	_lock_button = CheckButton.new()
	_lock_button.name = "LockButton"
	_lock_button.text = "Lock"
	_lock_button.focus_mode = Control.FOCUS_NONE
	_lock_button.tooltip_text = "Lock this layer: its shapes stay on the sheet but cannot be picked, selected or drawn on"
	_lock_button.pressed.connect(_on_lock_pressed)
	layer_row.add_child(_lock_button)
	add_child(layer_row)


## One row per group of commands, each a flow container for the reason the layer row is.
func _build_command_rows() -> void:
	for row: Array in COMMAND_ROWS:
		var made := HFlowContainer.new()
		made.name = String(row[0])
		add_child(made)
		for command: Array in row[1]:
			var button := _command_button(made, StringName(command[0]), String(command[1]))
			match StringName(command[0]):
				&"draft_undo":
					_undo_button = button
				&"draft_redo":
					_redo_button = button
				&"draft_dimension_style":
					_style_button = button


## A command button: it says what it does, says the key that also does it, and reports which command it stood
## for rather than holding a copy of the act itself. That is the whole difference between this and a button
## wired to a `Callable`: a command cannot be run twice over, and the menu bar and this palette cannot come to
## mean two different things by one name.
func _command_button(row: Container, action: StringName, wording: String) -> Button:
	var button := Button.new()
	button.name = String(action)
	button.text = wording
	var key := key_words(action)
	if key != "":
		button.tooltip_text = "%s (%s)" % [wording, key]
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_on_command_pressed.bind(action))
	row.add_child(button)
	return button


## Set the controls to the drawing's own state, and do nothing at all when that state has not moved.
##
## The signature holds the two tooltips as well as the drawing's own facts, because a gesture label that was
## not in it would leave a tooltip naming whatever was in hand when the palette last redrew - which is exactly
## the confusion those labels exist to remove.
##
## The tooltips arrive already worded. What an undo *would* undo is a question about the drawing, and "nothing
## to undo" is the HUD's sentence rather than this panel's; the lock arrives for the same reason.
func refresh(locked: bool, undo_tooltip: String, redo_tooltip: String) -> void:
	if not _built or _arm_button == null:
		return
	var is_armed: bool = _draft != null and _draft.drawing
	var kind: int = 0 if _draft == null else int(_draft.current_tool())
	var edit: int = 0 if _draft == null else int(_draft.current_edit())
	var layer: StringName = &"" if _draft == null else _draft.current_layer()
	var style: String = "" if _draft == null else String(_draft.dimension_style_name)
	var state := "%s|%d|%s|%s|%d|%s|%s|%s" % [
		str(is_armed),
		kind,
		layer,
		style,
		edit,
		str(locked),
		undo_tooltip,
		redo_tooltip,
	]
	if state == _state:
		return
	_state = state
	# By the silent setter, because setting a button the ordinary way fires the handler: the palette would
	# then be driving the controller it is reporting on.
	_arm_button.set_pressed_no_signal(is_armed)
	for index in _tool_buttons.size():
		var button: Button = _tool_buttons[index]
		# Only a tool actually in your hand is shown as chosen. A palette highlighting a tool while the tools
		# are put away would be describing a mode that is not on, and an editing command in hand is not a
		# drawing tool.
		button.button_pressed = is_armed and edit == 0 and int(DRAFTING_TOOLS[index][2]) == kind
	for index in _edit_buttons.size():
		var edit_button: Button = _edit_buttons[index]
		edit_button.button_pressed = armed and int(EDIT_TOOLS[index][2]) == edit
	var selected: int = _layer_names.find(layer)
	if selected >= 0:
		_layer_option.selected = selected
	# By the silent setter for the same reason the arm button uses it: setting a toggle the ordinary way
	# fires its handler, and the refresh would then be driving the layer it reports on.
	_lock_button.set_pressed_no_signal(locked)
	if _style_button != null:
		_style_button.text = "Standard: %s" % style
		_style_button.tooltip_text = "%s (%s)" % [style_words(), key_words(&"draft_dimension_style")]
	# What the two buttons would act on, by name. A button that says only "Undo" leaves a person to guess
	# whether it will put back the line they have just trimmed or a survey overlaid two hours ago.
	if _undo_button != null:
		_undo_button.tooltip_text = undo_tooltip
	if _redo_button != null:
		_redo_button.tooltip_text = redo_tooltip


## What one tool or editing button says: the words on the first line, the key that does the same thing on the
## second, so the palette teaches the shortcut while it is being used.
##
## A pure function of the row and the key rather than of the input map: the key is handed in, so this can be
## held by a test without a project, an action or a device.
static func label(pair: Array, key: String) -> String:
	var words := String(pair[1])
	var capitalised := words.substr(0, 1).to_upper() + words.substr(1)
	return capitalised if key.is_empty() else "%s\n%s" % [capitalised, key]


## The words for one action's key, or "" when nothing is bound to it.
func key_words(action: StringName) -> String:
	return String(_keys.get(action, ""))


## What the dimension standard is, in the drawing's own words. Empty with no drawing, which the style button
## then shows as no standard rather than as a standard nobody has.
func style_words() -> String:
	if _draft == null or _draft.document == null:
		return ""
	return _draft.document.dimension_style.describe()


## The controls the fitting pass measures: it re-flows the two grids around the words these buttons draw, so
## it needs them in the order they are laid out.
func tool_buttons() -> Array[Button]:
	return _tool_buttons


func edit_buttons() -> Array[Button]:
	return _edit_buttons


## The two buttons the gesture demo reads by name off the HUD. Doors rather than copies: there is one undo
## button on the screen and this is it.
func undo_button() -> Button:
	return _undo_button


func redo_button() -> Button:
	return _redo_button


func arm_button() -> CheckButton:
	return _arm_button


func layer_button() -> OptionButton:
	return _layer_option


func lock_button() -> CheckButton:
	return _lock_button


func style_button() -> Button:
	return _style_button


## The layer names the drop-down holds, in its order. The HUD needs them to turn the chosen row back into a
## name; the names come from the drawing and are asked for once, when the palette is built.
func layer_names() -> Array[StringName]:
	return _layer_names


func built() -> bool:
	return _built

# --- what a person does ---------------------------------------------------------------------


## The arm toggle. It is read rather than taken from the signal's argument for the same reason the lock is:
## the refresh writes these buttons, and a refresh arriving mid-click would otherwise report the state it had
## just drawn as though it were the state a person had asked for.
func _on_armed(_pressed: bool) -> void:
	armed.emit(_arm_button.button_pressed)


func _on_tool_pressed(kind: int) -> void:
	tool_chosen.emit(kind)


func _on_edit_pressed(kind: int) -> void:
	edit_chosen.emit(kind)


func _on_command_pressed(action: StringName) -> void:
	command_chosen.emit(action)


func _on_layer_selected(index: int) -> void:
	if index < 0 or index >= _layer_names.size():
		return
	layer_chosen.emit(_layer_names[index])


func _on_lock_pressed() -> void:
	lock_chosen.emit(_lock_button.button_pressed)
