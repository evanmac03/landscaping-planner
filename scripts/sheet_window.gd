class_name SheetWindow
extends Window
## The sheet setup: what this drawing goes out on, and the set of sheets it goes out as.
##
## A `Window`, like the ground window and the plant library, and it has to be: this is the one kind of
## surface in this app that takes typed text, and the drawing's keys belong to the drawing. A window is
## the boundary at which that is allowed.
##
## ## What it shows and what it does not
##
## It shows the *paper*: one row per sheet of the set - its drawing number, its title, its revision, and
## the sheet it is printed on - and, above them, the project and the date every sheet of the set shares.
## It draws nothing and plots nothing. Every edit is an intent it announces (`field_changed`,
## `sheet_added`, `plot_requested`, ...), and the HUD answers with the controller, which owns the
## drawing and the set. That is the same arrangement as the hatch panel, and it is what lets the whole
## window be driven by a test without a drawing, a plotter or a screen.
##
## ## The two things a person does here
##
## Set up the paper a drawing is plotted on - the size, the scale, whether the key is drawn, whether the
## sheet is portrait - and, when a job needs more than one sheet, add the second and third sheets with
## their own numbers, titles and revisions. Both are edits to the *drawing*: they are stored with it and
## they come back when it is opened.

signal field_changed(index: int, field: String, value: Variant)
signal identity_changed(field: String, value: String)
signal sheet_added()
signal sheet_removed(index: int)
signal sheet_selected(index: int)
signal plot_requested(index: int)
signal plot_set_requested()
signal closed()

const PlotScaleScript := preload("res://scripts/draft/plot_scale.gd")

## Big enough for the whole form, the list and the buttons at once. Measured the way the ground window's
## was: a button that exists and cannot be pressed is not a button.
const SIZE := Vector2i(780, 640)

## The fields of a sheet this window edits, in the order the form shows them. A sheet's *number* is
## derived - the set gives it one - but it is editable here, because a set is numbered to match the
## drawing it belongs to rather than to match this app.
const TEXT_FIELDS: Array[String] = ["title", "number", "revision"]

var _identity: Dictionary = {}
var _rows: Array[Dictionary] = []
var _index: int = 0
## True while the form is being filled from a row, so typing does not echo back as an edit - which would
## make the list rebuild under the cursor on every keystroke.
var _filling: bool = false
var _said: String = ""

var _project: LineEdit = null
var _date: LineEdit = null
var _list: ItemList = null
var _texts: Dictionary = {}
var _size_option: OptionButton = null
var _scale_option: OptionButton = null
var _legend: CheckBox = null
var _portrait: CheckBox = null
var _status: Label = null
var _plot_button: Button = null
var _remove_button: Button = null


func _init() -> void:
	title = "Sheet setup"
	min_size = SIZE
	exclusive = false
	close_requested.connect(_on_close_requested)


func _ready() -> void:
	if _list == null:
		build()


# --- building -----------------------------------------------------------------------


## Build the whole window by hand, idempotent, and callable off-tree so a test can drive the same
## controls the program shows.
func build() -> void:
	if _list != null:
		return
	var column := PageChrome.column(self)

	column.add_child(PageChrome.subheading("The sheets this drawing goes out as"))

	# What every sheet of a set shares. A set is one job: the project is the same on all of them, and so
	# is the date they were drawn.
	var shared := HBoxContainer.new()
	shared.name = "Shared"
	shared.add_theme_constant_override("separation", 6)
	column.add_child(shared)
	_project = _text_row(shared, "Project", 240.0)
	_project.text_changed.connect(func(text: String) -> void: identity_changed.emit("project", text))
	_date = _text_row(shared, "Date", 120.0)
	_date.text_changed.connect(func(text: String) -> void: identity_changed.emit("date", text))

	var body := HBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	var left := VBoxContainer.new()
	left.name = "SheetList"
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(left)
	left.add_child(PageChrome.text("Sheet"))
	_list = ItemList.new()
	_list.name = "Sheets"
	_list.custom_minimum_size = Vector2(300.0, 0.0)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_sheet_selected)
	left.add_child(_list)
	_remove_button = _button(left, "Remove the sheet")
	_remove_button.pressed.connect(func() -> void: sheet_removed.emit(_index))

	# The selected sheet's own fields.
	var right := VBoxContainer.new()
	right.name = "SheetFields"
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 4)
	body.add_child(right)
	right.add_child(PageChrome.text("This sheet"))
	for field: String in TEXT_FIELDS:
		var line := _text_row(right, _field_caption(field), 0.0)
		_texts[field] = line
		line.text_changed.connect(func(_text: String) -> void: _emit_text(field))

	right.add_child(PageChrome.text("On"))
	var paper := HBoxContainer.new()
	paper.name = "Paper"
	paper.add_theme_constant_override("separation", 6)
	right.add_child(paper)
	_size_option = _option(paper, "SheetOption", "Paper size")
	for sheet_name: String in PlotScaleScript.sheet_names():
		_size_option.add_item(sheet_label(sheet_name))
		_size_option.set_item_metadata(_size_option.item_count - 1, sheet_name)
	_size_option.item_selected.connect(func(_index_picked: int) -> void: _emit_option("sheet"))
	_scale_option = _option(paper, "ScaleOption", "Plot scale")
	for ratio: float in PlotScaleScript.METRIC_LADDER:
		_scale_option.add_item(PlotScaleScript.metric_label(ratio))
		_scale_option.set_item_metadata(_scale_option.item_count - 1, ratio)
	_scale_option.item_selected.connect(func(_index_picked: int) -> void: _emit_option("scale"))

	_legend = _flag(right, "Legend", "Carry the layer key")
	_legend.toggled.connect(func(on: bool) -> void: _emit_flag("legend", on))
	_portrait = _flag(right, "Portrait", "Turn the sheet a quarter turn")
	_portrait.toggled.connect(func(on: bool) -> void: _emit_flag("portrait", on))

	_status = PageChrome.status()
	column.add_child(_status)

	var buttons := PageChrome.button_row()
	column.add_child(buttons)
	var add_button := _button(buttons, "Add a sheet")
	add_button.pressed.connect(func() -> void: sheet_added.emit())
	_plot_button = _button(buttons, "Plot this sheet")
	_plot_button.pressed.connect(func() -> void: plot_requested.emit(_index))
	var plot_all := _button(buttons, "Plot the set")
	plot_all.pressed.connect(func() -> void: plot_set_requested.emit())
	var close_button := _button(buttons, "Close")
	close_button.pressed.connect(func() -> void: closed.emit())


static func _field_caption(field: String) -> String:
	match field:
		"title":
			return "What this sheet shows"
		"number":
			return "Drawing number"
		_:
			return "Revision"


## What a paper size is called in the list: the name a person asks for it by, and the sheet's size,
## because "A3" means nothing to somebody who has only ever bought paper in inches.
static func sheet_label(sheet_name: String) -> String:
	var paper: Vector2 = PlotScaleScript.sheet_size_mm(sheet_name)
	return "%s  (%.0f x %.0f mm)" % [sheet_name, paper.x, paper.y]


## A caption and the box it names, in one row. The caption and the row's two parts come from the shared
## chrome; the row's own name is the page's - it has always been `ProjectRow` here - so it is set after
## the chrome has named it from the field it carries.
func _text_row(parent: Node, caption: String, width: float) -> LineEdit:
	var line := LineEdit.new()
	line.name = caption.replace(" ", "") + "Text"
	if width > 0.0:
		line.custom_minimum_size = Vector2(width, 0.0)
	else:
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := PageChrome.labelled(caption, line)
	row.name = caption.replace(" ", "") + "Row"
	parent.add_child(row)
	return line


func _option(parent: Node, node_name: String, tip: String) -> OptionButton:
	var option := OptionButton.new()
	option.name = node_name
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.tooltip_text = tip
	parent.add_child(option)
	return option


func _flag(parent: Node, node_name: String, text: String) -> CheckBox:
	var box := CheckBox.new()
	box.name = node_name
	box.text = text
	parent.add_child(box)
	return box


## A button filling the row it sits in, made by the shared chrome so that its name, its caption and what
## it does with the keyboard are the project's rather than this page's. The one thing this adds is the
## equal share of the button strip the sheets page has always given its buttons.
func _button(parent: Node, text: String) -> Button:
	var made := PageChrome.button(text)
	made.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(made)
	return made


func _on_close_requested() -> void:
	closed.emit()


# --- what it shows ------------------------------------------------------------------


## Everything the window says about the drawing that is not a sheet: the two fields the whole set
## shares.
func set_identity(project: String, date: String) -> void:
	build()
	_identity = {"project": project, "date": date}
	_filling = true
	_project.text = project
	_date.text = date
	_filling = false


## The set, as the controller describes it: one row per sheet. The selected row is kept if it is still
## there, so a change made in the form does not move the selection out from under the person making it.
func set_sheets(rows: Array[Dictionary]) -> void:
	build()
	_rows = rows.duplicate(true)
	if _rows.is_empty():
		_index = 0
	else:
		_index = clampi(_index, 0, _rows.size() - 1)
	_filling = true
	_list.clear()
	for index in _rows.size():
		_list.add_item(_row_words(_rows[index]))
		if index == _index:
			_list.select(index)
	_filling = false
	_show_row()
	_remove_button.disabled = _rows.size() <= 1


func _row_words(row: Dictionary) -> String:
	var number := String(row.get("number", ""))
	var heading := String(row.get("title", ""))
	if number.is_empty():
		return heading
	return "%s  %s" % [number, heading]


## The two fields every sheet of the set shares, as the HUD last set them.
func identity() -> Dictionary:
	return _identity


func selected_index() -> int:
	return _index


func row_count() -> int:
	return _rows.size()


func list_texts() -> Array[String]:
	var out: Array[String] = []
	for row: Dictionary in _rows:
		out.append(_row_words(row))
	return out


func selected_row() -> Dictionary:
	if _index < 0 or _index >= _rows.size():
		return {}
	return _rows[_index]


## What the form is showing in one of the typed fields.
func field_text(field: String) -> String:
	var line: LineEdit = _texts.get(field, null)
	return line.text if line != null else ""


func sheet_choice() -> String:
	if _size_option == null or _size_option.item_count == 0:
		return ""
	return String(_size_option.get_item_metadata(maxi(_size_option.selected, 0)))


func scale_choice() -> float:
	if _scale_option == null or _scale_option.item_count == 0:
		return 0.0
	return float(_scale_option.get_item_metadata(maxi(_scale_option.selected, 0)))


func flag(field: String) -> bool:
	if field == "legend":
		return _legend != null and _legend.button_pressed
	if field == "portrait":
		return _portrait != null and _portrait.button_pressed
	return false


func status_text() -> String:
	if not _said.is_empty():
		return _said
	return selected_row().get("description", "")


## Select a sheet by index, as a click in the list does.
func select(index: int) -> bool:
	build()
	if index < 0 or index >= _rows.size():
		return false
	_index = index
	_filling = true
	_list.select(index)
	_filling = false
	_show_row()
	return true


## Fill the form from the selected row.
func _show_row() -> void:
	var row: Dictionary = selected_row()
	if row.is_empty():
		return
	_filling = true
	for field: String in TEXT_FIELDS:
		var line: LineEdit = _texts[field]
		line.text = String(row.get(field, ""))
	_select_metadata(_size_option, String(row.get("sheet", "")))
	_select_metadata(_scale_option, float(row.get("scale", 0.0)))
	_legend.button_pressed = bool(row.get("legend", true))
	_portrait.button_pressed = bool(row.get("portrait", false))
	_filling = false
	_plot_button.disabled = false
	_remove_button.disabled = _rows.size() <= 1
	_status.text = status_text()


## Pick the item whose metadata is this value, if it is in the list at all. A sheet quoting a size or a
## ratio that is not in the table leaves the drop-down where it was rather than clearing it.
static func _select_metadata(option: OptionButton, value: Variant) -> void:
	if option == null:
		return
	for index in option.item_count:
		var meta: Variant = option.get_item_metadata(index)
		if meta is float or meta is int:
			if is_equal_approx(float(meta), float(value)):
				option.selected = index
				return
		elif String(meta) == String(value):
			option.selected = index
			return


func _on_sheet_selected(index: int) -> void:
	if _filling:
		return
	_index = index
	_show_row()
	sheet_selected.emit(index)


func say(text: String) -> void:
	build()
	_said = text
	_status.text = status_text()


func said() -> String:
	return _said


# --- what a person did --------------------------------------------------------------


func _emit_text(field: String) -> void:
	if _filling:
		return
	var line: LineEdit = _texts.get(field, null)
	if line != null:
		field_changed.emit(_index, field, line.text)


func _emit_option(field: String) -> void:
	if _filling:
		return
	# Not a ternary: one arm is a String and the other a float, and GDScript wants the two compatible.
	if field == "sheet":
		field_changed.emit(_index, field, sheet_choice())
	else:
		field_changed.emit(_index, field, scale_choice())


func _emit_flag(field: String, on: bool) -> void:
	if _filling:
		return
	field_changed.emit(_index, field, on)


# --- the same acts, scriptable ---------------------------------------------------------
#
# Each of these does exactly what the control wired above it does - set the control, then announce the
# change - so a test drives the window through the same path a person does rather than through a second
# one that only exists for tests. The window still owns no drawing: all four announce and return.


## Whether there is a sheet in the form at all. A window that has been handed no rows - a HUD whose
## drawing has not arrived yet - takes no intent: there is no sheet any of it could be about.
func _has_row() -> bool:
	return not _rows.is_empty() and _index >= 0 and _index < _rows.size()


## Type into a field of the current sheet.
func type_field(field: String, text: String) -> bool:
	build()
	if not _has_row():
		return false
	var line: LineEdit = _texts.get(field, null)
	if line == null:
		return false
	_filling = true
	line.text = text
	_filling = false
	_emit_text(field)
	return true


## Choose the paper a sheet is on.
func choose_sheet(sheet_name: String) -> bool:
	build()
	if not _has_row():
		return false
	for index in _size_option.item_count:
		if String(_size_option.get_item_metadata(index)) == sheet_name:
			_size_option.selected = index
			_emit_option("sheet")
			return true
	return false


## Choose the scale a sheet is drawn at.
func choose_scale(ratio: float) -> bool:
	build()
	if not _has_row():
		return false
	for index in _scale_option.item_count:
		if is_equal_approx(float(_scale_option.get_item_metadata(index)), ratio):
			_scale_option.selected = index
			_emit_option("scale")
			return true
	return false


## Tick or untick one of the two flags. Not called `set_flag`: `Window` already has a `set_flag` of its
## own - its window flags - and a method that overrides a native one with a different signature is a
## warning, which in this project is a failure.
func tick_flag(field: String, on: bool) -> bool:
	build()
	if not _has_row():
		return false
	# A `CheckBox` announces its own `toggled` when `button_pressed` is set in code - unlike a
	# `LineEdit`, which says nothing when its `text` is assigned - so the boxes are set behind the
	# filling guard and the one announcement is made here. Without that the HUD hears the same edit
	# twice.
	_filling = true
	if field == "legend":
		_legend.button_pressed = on
	elif field == "portrait":
		_portrait.button_pressed = on
	else:
		_filling = false
		return false
	_filling = false
	_emit_flag(field, on)
	return true


## Type into one of the two fields the whole set shares.
func type_identity(field: String, text: String) -> bool:
	build()
	if field == "project":
		_project.text = text
	elif field == "date":
		_date.text = text
	else:
		return false
	identity_changed.emit(field, text)
	return true