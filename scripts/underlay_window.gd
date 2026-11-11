class_name UnderlayWindow
extends Window
## A picture under the drawing: choosing the file, saying how it lies, and what is already there.
##
## A `Window` rather than a HUD panel, for the reason every page in this app that has a field to type
## into is one: a HUD control that holds the keyboard swallows the drawing's own keys, so the
## keyboard is only ever somewhere else - in a window - and the drawing keeps `L`, `Q` and `Ctrl+Z`
## while this is open. The DXF page can be a panel because it has nothing to type into.
##
## ## What it does and what it does not
##
## It reads nothing from the disk, copies nothing and puts nothing on the drawing. Every action is an
## intent it announces - `choose_file_requested`, `place_requested`, `apply_requested`,
## `remove_requested`, `closed` - and the HUD answers with the module that reads the file and the
## controller that owns the drawing. That is the arrangement `OsmWindow` and the sheet window have,
## and it is what lets this whole page be driven by a test with no drawing, no file dialog and no
## screen.
##
## ## Why it asks for a width and not a scale
##
## A raster picture has no scale in it: a scan of a plot plan is at whatever the photocopier felt
## like, an aerial photograph at whatever the tile server served. So what the page asks for is how
## far the picture lies **across the ground**, which is the one number a person can measure on their
## own site - and the picture's own pixel proportion supplies the other one, so a picture cannot be
## stretched out of shape by mistake.
##
## ## Why the list of what is underneath lives here
##
## Because that is where a person already is when they wonder it. Changing a picture is the same
## three numbers as placing one, so the two belong on one page: pick the picture that is already
## there and the same fields become the way to move it.

signal choose_file_requested()
signal place_requested()
signal apply_requested()
signal remove_requested()
signal closed()

const UnitsScript := preload("res://scripts/draft/units.gd")
const RasterUnderlayScript := preload("res://scripts/draft/raster_underlay.gd")

## Big enough for the form, the report, the list and the four buttons at once, measured the way the
## map window's was: a button that exists and cannot be pressed is not a button.
const SIZE := Vector2i(760, 660)

## What the page says it is for. A page whose subject is "put a picture under the drawing" has to say
## what a picture is *for* here, because the answer is not obvious: it is something to trace over, not
## something that becomes part of the design.
const EXPLANATION := (
	"A scan of a surveyor's plan, an aerial photograph, a consultant's drawing - kept beside this "
	+ "drawing and laid under everything on the plan. It never plots, never snaps and is never "
	+ "measured: it is a tracing aid. Say how far it lies across the ground, and the other direction "
	+ "follows from the picture's own shape."
)

const NO_PICTURE := "no picture chosen"
const NOTHING_UNDER := "nothing is under this drawing"
const NOTHING_CHOSEN := "no picture chosen to change"

var _file_label: Label = null
var _choose_button: Button = null
var _across: LineEdit = null
var _across_caption: Label = null
var _turn: SpinBox = null
var _see_through: SpinBox = null
var _report: Label = null
var _status: Label = null
var _underlays: OptionButton = null
var _place_button: Button = null
var _apply_button: Button = null
var _remove_button: Button = null
var _close_button: Button = null

## The drawing's own units, so the width is typed in metres or feet and never in the other one.
var _units: UnitsScript = null
## The pictures already under the drawing, as the HUD describes them: `{id, name, text, width_m,
## rotation_deg, opacity}`.
var _rows: Array[Dictionary] = []
var _a_file_is_chosen: bool = false
var _said: String = ""


func _init() -> void:
	title = "Put a picture under the drawing"
	min_size = SIZE
	exclusive = false
	close_requested.connect(_on_close_requested)


func _ready() -> void:
	if _file_label == null:
		build()


# --- building -------------------------------------------------------------------------


## Build the whole page by hand, idempotent, and callable off-tree so a test can drive the same
## controls the program shows.
func build() -> void:
	if _file_label != null:
		return
	var column := PageChrome.column(self)

	column.add_child(PageChrome.subheading("Put a picture under the drawing"))
	column.add_child(PageChrome.note(EXPLANATION))

	# The file. Chosen through the HUD's own file dialog, and named here so that the page, the report
	# and the status line all say which picture they are talking about.
	var file_row := HBoxContainer.new()
	file_row.name = "FileRow"
	file_row.add_theme_constant_override("separation", 6)
	column.add_child(file_row)
	_choose_button = _button(file_row, "ChooseButton", "Choose a picture...")
	_choose_button.pressed.connect(func() -> void: choose_file_requested.emit())
	_file_label = PageChrome.text(NO_PICTURE)
	_file_label.name = "FileLabel"
	_file_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	file_row.add_child(_file_label)

	var report_box := ScrollContainer.new()
	report_box.name = "ReportBox"
	report_box.custom_minimum_size = Vector2(0.0, 96.0)
	report_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(report_box)
	_report = PageChrome.text()
	_report.name = "Report"
	_report.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	report_box.add_child(_report)

	# How it lies. Three numbers, and the first is the only one that has to be measured.
	var lie_row := HBoxContainer.new()
	lie_row.name = "LieRow"
	lie_row.add_theme_constant_override("separation", 10)
	column.add_child(lie_row)
	var across_holder := VBoxContainer.new()
	across_holder.name = "Across"
	lie_row.add_child(across_holder)
	_across_caption = PageChrome.text("Across the ground (m)")
	_across_caption.name = "AcrossCaption"
	across_holder.add_child(_across_caption)
	_across = LineEdit.new()
	_across.name = "AcrossField"
	_across.custom_minimum_size = Vector2(140.0, 0.0)
	_across.placeholder_text = "how far it lies across"
	across_holder.add_child(_across)
	_turn = _spin(lie_row, "Turn", "Turn", -180.0, 180.0, 1.0, " degrees")
	_see_through = _spin(lie_row, "See through", "SeeThrough", 0.0, 100.0, 5.0, " %")
	# A tracing aid is for tracing over, so it starts part-transparent - and the number comes from the
	# module that owns it rather than being written down twice.
	_see_through.value = roundf(RasterUnderlayScript.DEFAULT_OPACITY * 100.0)

	# What is already underneath, and what can be done to it.
	var list_row := HBoxContainer.new()
	list_row.name = "ListRow"
	list_row.add_theme_constant_override("separation", 6)
	column.add_child(list_row)
	var list_holder := VBoxContainer.new()
	list_holder.name = "UnderlayHolder"
	list_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_row.add_child(list_holder)
	var list_caption := PageChrome.text("Under the drawing")
	list_caption.name = "UnderlayCaption"
	list_holder.add_child(list_caption)
	_underlays = OptionButton.new()
	_underlays.name = "UnderlayOption"
	_underlays.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_underlays.item_selected.connect(_on_underlay_chosen)
	list_holder.add_child(_underlays)
	_apply_button = _button(list_row, "ApplyButton", "Apply these numbers")
	_apply_button.pressed.connect(func() -> void: apply_requested.emit())
	_remove_button = _button(list_row, "RemoveButton", "Take it off")
	_remove_button.pressed.connect(func() -> void: remove_requested.emit())

	_status = PageChrome.status()
	column.add_child(_status)

	var buttons := PageChrome.button_row()
	column.add_child(buttons)
	_place_button = _button(buttons, "PlaceButton", "Put it under the drawing")
	_place_button.pressed.connect(func() -> void: place_requested.emit())
	_close_button = _button(buttons, "CloseButton", "Close")
	_close_button.pressed.connect(_on_close_requested)

	_across.text_changed.connect(func(_text: String) -> void: _refresh())
	_turn.value_changed.connect(func(_value: float) -> void: _refresh())
	_see_through.value_changed.connect(func(_value: float) -> void: _refresh())
	show_underlays([])
	_refresh()


# --- what the page knows ---------------------------------------------------------------


## Which picture was chosen, or nothing when none was. An empty name is how the HUD says that a file
## was picked and *refused*: the report says why, and the button stays off until something readable
## is chosen.
##
## The parameter is not called `name`: this page is a `Node`, and `name` is the node's own.
func show_file(file_name: String) -> void:
	_a_file_is_chosen = not file_name.strip_edges().is_empty()
	if _file_label != null:
		_file_label.text = file_name if _a_file_is_chosen else NO_PICTURE
	_refresh()


func file_text() -> String:
	return _file_label.text if _file_label != null else ""


## The drawing's units, so the width field is metres or feet and the caption says which.
func set_units(units: UnitsScript) -> void:
	_units = units
	if _across_caption != null:
		_across_caption.text = "Across the ground (%s)" % _unit_name()


## The width to start from: the drawing's own extent, so the common case - a scan of this site and a
## design drawn on it - lands at about the size it already is.
func set_suggested_width(metres: float) -> void:
	if _across == null or not is_finite(metres) or metres <= 0.0:
		return
	_across.text = _number_in_units(metres)
	_refresh()


## What is under the drawing, one row each, and the choice kept if the picture chosen is still there -
## a list refreshing itself under somebody's hand must not put their choice back to nothing.
func show_underlays(rows: Array) -> void:
	if _underlays == null:
		return
	var chosen := chosen_id()
	_rows = []
	for entry: Dictionary in rows:
		_rows.append(entry)
	_underlays.clear()
	if _rows.is_empty():
		_underlays.add_item(NOTHING_UNDER)
		_underlays.set_item_disabled(0, true)
	else:
		_underlays.add_item(NOTHING_CHOSEN)
		_underlays.set_item_disabled(0, true)
		for index in _rows.size():
			_underlays.add_item("%s - %s" % [
				String(_rows[index].get("name", "picture")), String(_rows[index].get("text", "")),
			])
	var wanted := 0
	for index in _rows.size():
		if int(_rows[index].get("id", 0)) == chosen:
			wanted = index + 1
			break
	_underlays.select(wanted)
	_fill_from_row(wanted)


## The id of the picture chosen to change, or 0 when none is.
func chosen_id() -> int:
	var index := _underlays.selected - 1 if _underlays != null else -1
	if index < 0 or index >= _rows.size():
		return 0
	return int(_rows[index].get("id", 0))


## How far the picture lies across the ground, in metres, or NAN when what is typed is not a length.
## NAN rather than a guessed zero, so the button that cannot act is the thing that says so.
func width_m() -> float:
	if _across == null:
		return NAN
	var system := UnitsScript.System.METRIC
	var survey := false
	if _units != null:
		system = _units.system
		survey = _units.use_us_survey_foot
	return UnitsScript.parse_length(_across.text, system, survey)


func rotation_deg() -> float:
	return float(_turn.value) if _turn != null else 0.0


func opacity() -> float:
	return (float(_see_through.value) / 100.0) if _see_through != null else 1.0


## Show a report - what was read, or why it was not.
func show_report(text: String) -> void:
	if _report != null:
		_report.text = text


func report_text() -> String:
	return _report.text if _report != null else ""


func say(text: String) -> void:
	_said = text
	if _status != null:
		_status.text = text


func said_text() -> String:
	return _said


# --- the controls a test drives ----------------------------------------------------------


func place_enabled() -> bool:
	return _place_button != null and not _place_button.disabled


func apply_enabled() -> bool:
	return _apply_button != null and not _apply_button.disabled


func remove_enabled() -> bool:
	return _remove_button != null and not _remove_button.disabled


func across_text() -> String:
	return _across.text if _across != null else ""


## Type a width the way a person would. A programmatic `text =` does not emit `text_changed`, so the
## buttons are told by hand - the same trap `OsmWindow.type_...` has and the same answer.
func set_across_text(text: String) -> void:
	if _across == null:
		return
	_across.text = text
	_refresh()


func set_turn(degrees: float) -> void:
	if _turn != null:
		_turn.value = degrees


func set_see_through(percent: float) -> void:
	if _see_through != null:
		_see_through.value = percent


func underlay_texts() -> Array[String]:
	var out: Array[String] = []
	if _underlays == null:
		return out
	for index in _underlays.item_count:
		out.append(_underlays.get_item_text(index))
	return out


## Choose one of the pictures already under the drawing, the way a click on the list does. It calls
## the handler the signal calls, because `select()` does not emit `item_selected` - an `ItemList`'s
## rule, and an `OptionButton`'s.
func choose_underlay(index: int) -> void:
	if _underlays == null or index < 0 or index >= _underlays.item_count:
		return
	_underlays.select(index)
	_on_underlay_chosen(index)


## The words a button carries, for a test or a demonstration that has to press the real one.
func button_texts() -> Array[String]:
	var out: Array[String] = []
	for button: Button in [_choose_button, _apply_button, _remove_button, _place_button, _close_button]:
		if button != null:
			out.append(button.text)
	return out


# --- the page's own behaviour ------------------------------------------------------------


func _on_underlay_chosen(selected: int) -> void:
	_fill_from_row(selected)


## Put the chosen picture's own numbers in the fields. A picture chosen from the list means "change
## this one", so the fields become its numbers rather than whatever was typed for a new file.
func _fill_from_row(selected: int) -> void:
	var index := selected - 1
	if _across == null:
		return
	if index >= 0 and index < _rows.size():
		var row: Dictionary = _rows[index]
		_across.text = _number_in_units(float(row.get("width_m", 0.0)))
		_turn.value = float(row.get("rotation_deg", 0.0))
		_see_through.value = roundf(float(row.get("opacity", 1.0)) * 100.0)
	_refresh()


func _on_close_requested() -> void:
	closed.emit()


## The two buttons that act are live only when there is something for them to act on, and each says
## what is missing when it is not - a button that is there and cannot be pressed is a button that
## explains itself.
func _refresh() -> void:
	if _place_button == null:
		return
	var width := width_m()
	# Not `ready`: this page is a `Node`, and `ready` is a signal of its own.
	var can_place := _a_file_is_chosen and not is_nan(width) and width > 0.0
	_place_button.disabled = not can_place
	_place_button.tooltip_text = (
		"lay the picture under everything on the plan" if can_place
		else "choose a picture and say how far it lies across the ground"
	)
	var chosen := chosen_id() != 0
	_apply_button.disabled = not chosen
	_remove_button.disabled = not chosen
	var why := "" if chosen else "no picture is chosen from the list"
	_apply_button.tooltip_text = "put these numbers on the picture chosen" if chosen else why
	_remove_button.tooltip_text = "take the picture chosen off the drawing" if chosen else why


func _unit_name() -> String:
	if _units == null:
		return "m"
	return "m" if _units.system == UnitsScript.System.METRIC else "ft"


## A bare number in the drawing's own unit: the field holds what a person measures, and the unit is
## in the caption above it. A metre drawing and a feet drawing therefore type the same kind of number.
func _number_in_units(metres: float) -> String:
	var factor := 1.0 if _unit_name() == "m" else UnitsScript.FOOT
	return String.num(metres / factor, 2)


# --- furniture -------------------------------------------------------------------------


func _spin(parent: HBoxContainer, caption: String, node_name: String, minimum: float,
		maximum: float, step: float, suffix: String) -> SpinBox:
	var holder := VBoxContainer.new()
	holder.name = node_name
	parent.add_child(holder)
	var label := PageChrome.text(caption)
	label.name = node_name + "Caption"
	holder.add_child(label)
	var spin := SpinBox.new()
	spin.name = node_name + "Spin"
	spin.custom_minimum_size = Vector2(120.0, 0.0)
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.suffix = suffix
	holder.add_child(spin)
	return spin


## A button in the page's own row, made by the shared chrome so that its caption and what it does with
## the keyboard are the project's rather than this page's. The node name is given explicitly rather than
## taken from the caption, because these captions are written for a person - two end in an ellipsis or a
## full stop - and are not what this page's own reading of itself is keyed by.
func _button(parent: HBoxContainer, node_name: String, text: String) -> Button:
	var made := PageChrome.button(text)
	made.name = node_name
	parent.add_child(made)
	return made