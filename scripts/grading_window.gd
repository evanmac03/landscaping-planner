class_name GradingWindow
extends Window
## The page for the ground's own heights: the level in hand, the three tools, the check, and what is
## already on the drawing.
##
## ## Why this is a window and not a panel
##
## The one rule the HUD's panels keep is that nothing on them holds the keyboard, because a control
## that holds it swallows the keys the *drawing* needs - and a level and a fall have to be typed. So
## this is a `Window`, like the sheet page, the ground page and the picture page, and it is the same
## reason in each case: a field to type into.
##
## ## What it knows
##
## Nothing about a drawing. It is handed the level, the fall, the rows and the report, and it announces
## what a person did; the HUD answers with the controller. A page that read the drawing itself would be
## a second place that knows how a level is worded.
##
## ## Arming a tool
##
## Pressing one of the three tool buttons *arms a tool and closes this page*, because the next thing a
## person does is click on the plan - and a window left standing over it would be a page between the
## person and the thing they are drawing on. The button says so; the level and the fall in hand are
## already on the controller by then, so nothing is lost by the page going away.

signal level_requested(level: float)
signal fall_requested(percent: float)
signal tool_requested(kind: String)
signal change_requested(kind: String, id: int, level: float)
signal remove_requested(kind: String, id: int)
signal closed()

const GradingScript := preload("res://scripts/draft/grading.gd")

## Big enough for the two fields, the three buttons, the report and the list at once, measured the way
## the picture page's was: a button that exists and cannot be pressed is not a button.
const SIZE := Vector2i(880, 720)

const EXPLANATION := (
	"Spot levels, contours and slope arrows - the ground's own heights, not the shapes on it. A level "
	+ "is a number at a place, a contour is a line at one level, and a slope arrow states the fall of "
	+ "something that is to be built. Put the level in hand, press one of the three tools, and click on "
	+ "the plan: the page steps out of the way while you do."
)

const NOTHING_YET := "nothing on this drawing is graded yet"
const NO_RECORD := "nothing chosen"
const AGREES := "the grading agrees with itself"

var _level_spin: SpinBox = null
var _fall_spin: SpinBox = null
var _level_button: Button = null
var _fall_button: Button = null
var _spot_button: Button = null
var _contour_button: Button = null
var _slope_button: Button = null
var _report: Label = null
var _list: ItemList = null
var _change_button: Button = null
var _remove_button: Button = null
var _status: Label = null

var _records: Array[Dictionary] = []
## The rows as they were last written. Deliberately not empty to start with: an empty signature would
## make the first `show_records([])` a no-op and leave a freshly built page with a blank list where the
## placeholder belongs.
var _signature: String = "<never written>"
var _said: String = ""


func _init() -> void:
	title = "Grading"
	min_size = SIZE
	exclusive = false
	close_requested.connect(_on_close_requested)


func _ready() -> void:
	if _list == null:
		build()


# --- building -------------------------------------------------------------------------


## Build the whole page by hand, idempotent, and callable off-tree so a test can drive the same
## controls the program shows.
func build() -> void:
	if _list != null:
		return
	var column := PageChrome.column(self, 8)

	column.add_child(PageChrome.heading("Grading"))

	# The page's own name for this sentence, kept: an explanation of what a page is for is what the
	# shared note is worded as, and `tests/test_grading_window.gd` and the HUD both leave it alone.
	var explanation := PageChrome.note(EXPLANATION)
	explanation.name = "Explanation"
	column.add_child(explanation)

	# The two numbers in hand. A step of five centimetres on the level and half a percent on the fall,
	# because those are the intervals a plan is set out to - and both can be typed past, which is what
	# the field is for.
	_level_spin = _spin(column, "Level (m)", "LevelSpin", -1000.0, 1000.0, 0.05, " m",
		"Metres above whatever benchmark the drawing is levelled to. The level the next spot level, "
		+ "contour or fall is stated at.")
	_level_button = _button(column, "LevelButton", "Set the level")
	_level_button.tooltip_text = "The level in hand. A spot level and a contour are stamped with it."
	_level_button.pressed.connect(state_level)

	_fall_spin = _spin(column, "Fall (%)", "FallSpin", -100.0, 100.0, 0.5, " %",
		"A slope arrow states the fall of what is built along it, downhill from its first pick. "
		+ "The levels at its ends are checked against it.")
	_fall_button = _button(column, "FallButton", "Set the fall")
	_fall_button.tooltip_text = "The fall in hand, downhill along the arrow."
	_fall_button.pressed.connect(state_fall)

	var tools := HBoxContainer.new()
	tools.name = "ToolsRow"
	tools.add_theme_constant_override("separation", 6)
	column.add_child(tools)
	_spot_button = _button(tools, "SpotButton", "Spot level here")
	_spot_button.tooltip_text = ("Click one place on the plan. The level in hand is written there "
		+ "beside a mark.")
	_spot_button.pressed.connect(arm_spot)
	_contour_button = _button(tools, "ContourButton", "Draw a contour")
	_contour_button.tooltip_text = ("Click the line of one level. Enter finishes it, C closes it into "
		+ "a ring.")
	_contour_button.pressed.connect(arm_contour)
	_slope_button = _button(tools, "SlopeButton", "Draw a slope arrow")
	_slope_button.tooltip_text = ("Click the top of the fall and then the bottom of it: the arrow runs "
		+ "downhill and the fall in hand is written beside it.")
	_slope_button.pressed.connect(arm_slope)

	# The check. Findings first because they are the things that are wrong, then what is worth knowing.
	# No height reserved: the report always has something to say - that the grading agrees with itself,
	# if nothing else - so its own line is the room it needs.
	_report = PageChrome.text()
	_report.name = "Report"
	column.add_child(_report)

	_list = ItemList.new()
	_list.name = "RecordList"
	_list.custom_minimum_size = Vector2(0.0, 150.0)
	_list.focus_mode = Control.FOCUS_NONE
	_list.item_selected.connect(func(_index: int) -> void: _refresh())
	column.add_child(_list)

	var buttons := HBoxContainer.new()
	buttons.name = "ButtonsRow"
	buttons.add_theme_constant_override("separation", 6)
	column.add_child(buttons)
	_change_button = _button(buttons, "ChangeButton", "Change the level")
	_change_button.tooltip_text = ("Change the level the chosen record states. Its marks and its "
		+ "label are written again, as one undoable step.")
	_change_button.pressed.connect(change_chosen)
	_remove_button = _button(buttons, "RemoveButton", "Take it off the drawing")
	_remove_button.pressed.connect(remove_chosen)
	_button(buttons, "CloseButton", "Close").pressed.connect(_on_close_requested)

	_status = PageChrome.status()
	column.add_child(_status)

	show_records([])
	set_report({})
	hide()


# --- state in -------------------------------------------------------------------------


## The level in hand, without announcing it: this page is being *told* what the drawing holds, and a
## page that announced the state it was handed would drive the controller in a circle.
##
## The parameter is not called `level`: this page has a `level()` of its own, and one name cannot be two
## things.
func set_level(metres: float) -> void:
	build()
	_level_spin.set_value_no_signal(metres)


func level() -> float:
	build()
	return _level_spin.value


func set_fall(percent: float) -> void:
	build()
	_fall_spin.set_value_no_signal(percent)


func fall() -> float:
	build()
	return _fall_spin.value


## The level in hand as the page shows it, which is also what a test can read without reaching into a
## control.
func level_text() -> String:
	build()
	return "%.2f m" % _level_spin.value


func fall_text() -> String:
	build()
	return "%.1f %%" % _fall_spin.value


## Hand over the records to list. Returns false when nothing changed, so the HUD can call it every
## frame without rebuilding a list under somebody's cursor.
func show_records(rows: Array[Dictionary]) -> bool:
	build()
	var signature := _signature_of(rows)
	if signature == _signature:
		return false
	_signature = signature
	var wanted := _chosen_key()
	_records = rows.duplicate(true)
	_list.clear()
	if _records.is_empty():
		_list.add_item(NOTHING_YET)
		_list.set_item_disabled(0, true)
	else:
		for index in _records.size():
			var row: Dictionary = _records[index]
			_list.add_item(String(row.get("text", "")))
			_list.set_item_metadata(index, {
				"kind": String(row.get("kind", "")), "id": int(row.get("id", 0)),
			})
	# The choice survives the list being written again, and only while the record it names is still on
	# the drawing: a level that has gone cannot stay chosen.
	for index in _records.size():
		if _key_of(_records[index]) == wanted:
			_list.select(index)
			break
	_refresh()
	return true


func record_texts() -> Array[String]:
	build()
	var out: Array[String] = []
	if _records.is_empty():
		out.append(NOTHING_YET)
		return out
	for row in _records:
		out.append(String(row.get("text", "")))
	return out


## The check, as the page shows it: what is wrong, and then what is worth knowing.
func set_report(report: Dictionary) -> void:
	build()
	_report.text = _report_words(report)
	_refresh()


func report_text() -> String:
	build()
	return _report.text


func say(text: String) -> void:
	_said = text
	if _status != null:
		_refresh()


func said() -> String:
	return _said


func status_text() -> String:
	build()
	if not _said.is_empty():
		return _said
	if _records.is_empty():
		return NOTHING_YET
	return "%d record%s on this drawing" % [_records.size(), "" if _records.size() == 1 else "s"]


# --- what a person did -----------------------------------------------------------------


func state_level() -> bool:
	build()
	level_requested.emit(_level_spin.value)
	return true


func state_fall() -> bool:
	build()
	fall_requested.emit(_fall_spin.value)
	return true


func arm_spot() -> bool:
	return _arm(GradingScript.SPOT)


func arm_contour() -> bool:
	return _arm(GradingScript.CONTOUR)


func arm_slope() -> bool:
	return _arm(GradingScript.SLOPE)


## Change the level of whatever is chosen, to whatever the level field now holds. Two presses and no
## ambiguity: the field is the level, the list is the record, and this is the act that joins them.
func change_chosen() -> bool:
	build()
	var kind := chosen_kind()
	if kind == "":
		return false
	change_requested.emit(kind, chosen_id(), _level_spin.value)
	return true


func remove_chosen() -> bool:
	build()
	var kind := chosen_kind()
	if kind == "":
		return false
	remove_requested.emit(kind, chosen_id())
	return true


func chosen_kind() -> String:
	var index := _selected_index()
	if index < 0 or index >= _records.size():
		return ""
	return String((_records[index] as Dictionary).get("kind", ""))


func chosen_id() -> int:
	var index := _selected_index()
	if index < 0 or index >= _records.size():
		return 0
	return int((_records[index] as Dictionary).get("id", 0))


## Choose a row the way a click does, so a test drives the same selection the screen does.
func choose_record(index: int) -> bool:
	build()
	if index < 0 or index >= _records.size():
		return false
	_list.select(index)
	_refresh()
	return true


## Ask for a tool by name, the way the button does.
func arm(kind: String) -> bool:
	if kind == GradingScript.CONTOUR:
		return arm_contour()
	if kind == GradingScript.SLOPE:
		return arm_slope()
	return arm_spot()


# --- what the buttons say -----------------------------------------------------------------


func change_enabled() -> bool:
	build()
	return not chosen_kind().is_empty()


func remove_enabled() -> bool:
	build()
	return not chosen_kind().is_empty()


func button_texts() -> Array[String]:
	build()
	var out: Array[String] = []
	out.append(_level_button.text)
	out.append(_fall_button.text)
	out.append(_spot_button.text)
	out.append(_contour_button.text)
	out.append(_slope_button.text)
	out.append(_change_button.text)
	out.append(_remove_button.text)
	return out


## Every control that is *not* a field is built without a keyboard of its own. The two number fields are
## the exception at build time, and they are the reason this page is a `Window` at all: a level has to be
## typed. A control that holds the keyboard *inside the HUD* takes the drawing's keys with it - which is
## exactly why a page is a `Window`: it holds the keyboard while it is up, so its own switches and buttons
## may take it too (`PageChrome.takes_the_keyboard`, called by the shared show).
func list_is_keyboard_free() -> bool:
	build()
	return _list.focus_mode == Control.FOCUS_NONE \
		and _level_button.focus_mode == Control.FOCUS_NONE \
		and _fall_button.focus_mode == Control.FOCUS_NONE \
		and _spot_button.focus_mode == Control.FOCUS_NONE \
		and _contour_button.focus_mode == Control.FOCUS_NONE \
		and _slope_button.focus_mode == Control.FOCUS_NONE \
		and _change_button.focus_mode == Control.FOCUS_NONE \
		and _remove_button.focus_mode == Control.FOCUS_NONE


# --- private --------------------------------------------------------------------------


func _arm(kind: String) -> bool:
	build()
	tool_requested.emit(kind)
	return true


func _on_close_requested() -> void:
	closed.emit()


func _selected_index() -> int:
	var chosen := _list.get_selected_items()
	return int(chosen[0]) if not chosen.is_empty() else -1


func _key_of(row: Dictionary) -> String:
	return "%s#%d" % [String(row.get("kind", "")), int(row.get("id", 0))]


func _chosen_key() -> String:
	var kind := chosen_kind()
	if kind == "":
		return ""
	return "%s#%d" % [kind, chosen_id()]


## A signature of the rows, so the list is only written when it has actually changed. The words are in
## it rather than only the ids, because a level that has been changed is a row that has changed.
func _signature_of(rows: Array[Dictionary]) -> String:
	var parts := PackedStringArray()
	for row: Dictionary in rows:
		parts.append("%s#%d %s" % [String(row.get("kind", "")), int(row.get("id", 0)),
			String(row.get("text", ""))])
	return "|".join(parts)


func _report_words(report: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	var findings: Array = report.get("findings", [])
	var notes: Array = report.get("notes", [])
	if findings.is_empty():
		lines.append(AGREES)
	else:
		for one in findings:
			lines.append("- " + String(one))
	for note in notes:
		lines.append(String(note))
	return "\n".join(lines)


## Word a button that cannot do anything with what is missing, rather than leaving it dead and silent.
func _refresh() -> void:
	if _list == null:
		return
	_status.text = status_text()
	_change_button.disabled = not change_enabled()
	_remove_button.disabled = not remove_enabled()
	_remove_button.text = "Take it off the drawing" if remove_enabled() else "Nothing chosen to take off"


## A button on this page, from the shared chrome and named by the page: the names are what the HUD's
## wiring and this page's tests hold it by, so they are set after the builder rather than left to the
## chrome's naming of a caption.
func _button(parent: Node, node_name: String, text: String) -> Button:
	var button := PageChrome.button(text)
	button.name = node_name
	parent.add_child(button)
	return button


## A caption and the number it names, in the shared kind of row, plus the range, the step, the suffix
## and the tooltip a `SpinBox` has to be told. The row goes back to this page's own name for itself, and
## the two captions are given the same width so the numbers line up under each other rather than the
## second row beginning where the first caption ends.
func _spin(parent: Node, caption_text: String, node_name: String, low: float, high: float,
		step: float, suffix: String, tip: String) -> SpinBox:
	var spin := SpinBox.new()
	spin.name = node_name
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.suffix = suffix
	spin.tooltip_text = tip
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := PageChrome.labelled(caption_text, spin)
	row.name = node_name + "Row"
	var caption: Label = row.get_node(^"Caption")
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	caption.custom_minimum_size = Vector2(90.0, 0.0)
	parent.add_child(row)
	return spin