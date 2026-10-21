class_name AnalyticsWindow
extends Window
## The report on a page: every figure in §10, each with its basis beside it, over a window and as at a
## moment the page lets a person choose (spec §10, §14f).
##
## A `Window` like the other pages, for the two reasons they are: it has fields to type into, and a
## `Window` owns its own input, so nothing here can take the drawing's keys (spec §9's rule). Every
## button is `FOCUS_NONE`; the typed fields are the only things allowed the keyboard.
##
## ## What this page is for
##
## It shows what `Analytics` says and decides nothing itself. **It holds no figures of its own**: every
## line is recomputed from the records the moment a field changes, because the report is a function of
## the records and a page that cached one would be a second answer to the same question (REQ-B15). So
## the window's fields are arguments, not settings.
##
## Two things the page does on the reader's behalf, and both of them are the sort of thing a page may
## know and a report may not:
##
## - **It fills the as-of date in with today.** A report will not read a clock (that is what makes an
##   ageing figure reproducible), but a page is a place where today is the sensible starting point.
## - **It offers the eight-hour day as a placeholder rather than a value.** No hours-per-day is recorded
##   anywhere in the office's records, and the utilisation figure refuses to invent one - so the hint
##   sits in grey in the field, and the figure stays refused until somebody states a day by pressing the
##   button.
##
## A figure that cannot be worked out still gets its row, greyed, saying what it is waiting for: a page
## that omitted it would read as a figure the report does not have.

const AnalyticsScript := preload("res://scripts/biz/analytics.gd")

## The window, the as-of moment, or the working day changed. The line the HUD shows is stale.
signal report_changed()
## The window was closed by its own close button.
signal closed()

## Wide enough for a figure's own sentence beside its label.
const SIZE := Vector2i(1180, 850)
## How many minutes the placeholder in the working-day field suggests, and nothing more than a hint.
const SUGGESTED_DAY_MINUTES := 480

var report: AnalyticsScript = null

var _column: VBoxContainer = null
var _summary: Label = null
var _from_field: LineEdit = null
var _to_field: LineEdit = null
var _as_of_field: LineEdit = null
var _day_field: LineEdit = null
var _day_line: Label = null
var _day_button: Button = null
var _rows: VBoxContainer = null
var _missing: ItemList = null
var _status: Label = null
## The keys of the figures the rows are showing, in the order they are shown: a row's position is a
## reading order and these are what the positions mean.
var _row_keys: Array[String] = []


func _init() -> void:
	title = "The figures"
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
	if report == null:
		report = AnalyticsScript.new()
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

	_column.add_child(_build_window_row())
	_column.add_child(_build_day_row())

	_column.add_child(_heading("the figures"))
	# The rows are rebuilt from the report on every refresh, so a figure is never a moment out of date.
	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.add_theme_constant_override("separation", 2)
	_column.add_child(_rows)

	_column.add_child(_heading("what could not be worked out"))
	_missing = ItemList.new()
	_missing.name = "Missing"
	_missing.custom_minimum_size = Vector2(0, 96)
	_missing.select_mode = ItemList.SELECT_SINGLE
	_column.add_child(_missing)

	_status = Label.new()
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 36)
	_column.add_child(_status)
	refresh()


func _heading(words: String) -> Label:
	var label := Label.new()
	label.name = "Heading%s" % str(words.hash())
	label.text = words
	return label


## What window the report is over, and as at what moment. Three arguments, three fields: they are not
## settings, and changing one reads the figures again.
func _build_window_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "WindowRow"
	row.add_theme_constant_override("separation", 6)
	_from_field = _field("WindowFrom", "2026-01-01", 140)
	_to_field = _field("WindowTo", "2026-03-31", 140)
	_as_of_field = _field("AsAt", "2026-04-01", 140)
	row.add_child(_labelled("from", _from_field))
	row.add_child(_labelled("to", _to_field))
	row.add_child(_labelled("as at", _as_of_field))
	var again := _act_button("Read it again", _on_read_again)
	row.add_child(again)
	return row


## The one thing on this page that a person states rather than reads: how long a working day is. The
## figure about hours refuses until it is stated, so the page says what it is waiting for and offers the
## button that answers it.
func _build_day_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "DayRow"
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.name = "DayLabel"
	label.text = "a working day"
	label.custom_minimum_size = Vector2(160, 0)
	row.add_child(label)
	_day_field = _field("DayMinutes", str(SUGGESTED_DAY_MINUTES), 90)
	row.add_child(_day_field)
	var unit := Label.new()
	unit.name = "DayUnit"
	unit.text = "minutes"
	row.add_child(unit)
	_day_button = _act_button("State the working day", _on_state_day)
	row.add_child(_day_button)
	_day_line = Label.new()
	_day_line.name = "DayLine"
	_day_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_day_line.custom_minimum_size = Vector2(360, 0)
	row.add_child(_day_line)
	return row


func _labelled(words: String, field: LineEdit) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.name = "Box%s" % field.name
	box.add_theme_constant_override("separation", 4)
	var label := Label.new()
	label.name = "Label%s" % field.name
	label.text = words
	box.add_child(label)
	box.add_child(field)
	return box


## A typed field: the only kind of control on any of these pages that is allowed the keyboard.
func _field(shown_name: String, placeholder: String, width: int) -> LineEdit:
	var edit := LineEdit.new()
	edit.name = shown_name
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(width, 0)
	edit.text_changed.connect(_on_field_changed)
	return edit


func _act_button(words: String, handler: Callable) -> Button:
	var button := Button.new()
	button.name = words.replace(" ", "")
	button.text = words
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(handler)
	return button


# --- showing what is there ----------------------------------------------------------------------


## Point the page at a report and read it again. A null report becomes one over nothing rather than a
## page with nothing to show. **The as-of field is filled in with today when it is empty**, because a
## page is where today is a reasonable default and a report is where reading a clock is not.
func bind(analytics: AnalyticsScript) -> void:
	if _column == null:
		build()
	report = analytics if analytics != null else AnalyticsScript.new()
	if _status != null:
		_status.text = ""
	_fill_window_fields()
	refresh()


func _fill_window_fields() -> void:
	if _as_of_field != null and _as_of_field.text.strip_edges().is_empty():
		_as_of_field.text = Time.get_date_string_from_system()


func refresh() -> void:
	if _rows != null:
		_fill_rows()
	if _missing != null:
		_missing.clear()
		for words: String in unavailable_texts():
			var index: int = _missing.add_item(words)
			_missing.set_item_disabled(index, true)
	if _summary != null:
		_summary.text = summary_text()
	if _day_line != null:
		_day_line.text = working_day_text()
	if _day_button != null:
		_day_button.disabled = _day_field == null or not _day_field.text.strip_edges().is_valid_int()
	if _status != null and _status.text.is_empty():
		_set_status(opening_words())


## One row per figure in the table's own order: the report's own sentence, which opens by naming the
## figure. A figure that cannot be worked out is greyed rather than left out, so the page shows every
## figure the report has. No label column: the sentence already opens with the name, and a page that
## wrote the name twice would be a page agreeing with itself.
func _fill_rows() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.free()
	_row_keys.clear()
	if report == null:
		return
	for held in figure_rows():
		var row := HBoxContainer.new()
		row.name = "Row%s" % String(held["key"]).hash()
		row.add_theme_constant_override("separation", 6)
		var words := Label.new()
		words.name = "Words"
		words.text = String(held["text"])
		words.custom_minimum_size = Vector2(1100, 0)
		words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if not bool(held["ok"]):
			# Greyed, not hidden: the figure is on the page and the page says what it is waiting for.
			words.modulate = Color(0.62, 0.62, 0.62)
		row.add_child(words)
		_rows.add_child(row)
		_row_keys.append(String(held["key"]))


## The line the page opens with: what to do, or why there is nothing to read yet.
func opening_words() -> String:
	if report == null or report.pipeline == null and report.jobs == null and report.billing == null:
		return "Nothing to report on yet: the figures read the pipeline, the job desk and the billing ledger."
	if not report.working_day_stated():
		return "State how long a working day is and the figures about hours can be read; the rest are already here."
	if unavailable_texts().is_empty():
		return "Every figure can be worked out over this window. Change the window to read another."
	return "Change the window or the as-of date, and read the figures again."


# --- reading back what the page is showing ------------------------------------------------------


func window_from() -> String:
	return "" if _from_field == null else _from_field.text.strip_edges()


func window_to() -> String:
	return "" if _to_field == null else _to_field.text.strip_edges()


func as_of() -> String:
	return "" if _as_of_field == null else _as_of_field.text.strip_edges()


func set_window_fields(from_date: String, to_date: String) -> void:
	if _from_field != null:
		_from_field.text = from_date
	if _to_field != null:
		_to_field.text = to_date
	# A field typed into emits its own change; a field set by a program is set silently, so re-reading
	# the figures is this method's job. Nothing is cached, and a page that showed a figure for the
	# window before last would be showing an answer to a question nobody is asking.
	refresh()


func set_as_of(now: String) -> void:
	if _as_of_field != null:
		_as_of_field.text = now
	refresh()


func set_working_day_field(minutes: int) -> void:
	if _day_field != null:
		_day_field.text = str(minutes)
	refresh()


func window_text() -> String:
	return AnalyticsScript.window_text(window_from(), window_to())


func as_of_text() -> String:
	var moment: String = as_of()
	return "no as-of date" if moment.is_empty() else "as at %s" % moment


func working_day_text() -> String:
	if report == null:
		return "there is no report on this page"
	if not report.working_day_stated():
		return "not stated, so the figures about hours refuse"
	return "stated as %s" % report.working_day_text()


func summary_text() -> String:
	if report == null:
		return "no report is loaded"
	return report.summary_text(window_from(), window_to(), as_of())


## Every figure in the table's order, as `{key, label, ok, text, missing, basis}`. The page draws these
## and nothing else, so what the page shows is what the report says.
func figure_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if report == null:
		return out
	for figure: AnalyticsScript.Figure in report.figures(window_from(), window_to(), as_of()):
		out.append({
			"key": figure.key,
			"label": figure.label,
			"ok": figure.ok,
			"text": figure.text(),
			"missing": figure.missing,
			"basis": figure.basis,
		})
	return out


func figure_keys() -> Array[String]:
	return _row_keys.duplicate()


func figure_texts() -> Array[String]:
	var out: Array[String] = []
	if _rows == null:
		return out
	for row in _rows.get_children():
		for child in row.get_children():
			if child is Label and String(child.name) == "Words":
				out.append((child as Label).text)
	return out


func row_count() -> int:
	return _row_keys.size()


func available_count() -> int:
	var how_many: int = 0
	for held in figure_rows():
		if bool(held["ok"]):
			how_many += 1
	return how_many


func unavailable_texts() -> Array[String]:
	return [] if report == null else report.unavailable(window_from(), window_to(), as_of())


func status_text() -> String:
	return "" if _status == null else _status.text


func state_button_disabled() -> bool:
	return _day_button == null or _day_button.disabled


## Whether every button on the page is focus-free. The typed fields are the only things allowed the
## keyboard (spec §9's rule), and this is what proves it.
func buttons_are_focus_free() -> bool:
	for button in _all_buttons(self):
		if button.focus_mode != Control.FOCUS_NONE:
			return false
	return true


func _all_buttons(node: Node) -> Array[Button]:
	var out: Array[Button] = []
	for child in node.get_children():
		if child is Button:
			out.append(child)
		out.append_array(_all_buttons(child))
	return out


# --- the one act --------------------------------------------------------------------------------


## State how long a working day is, which is the one thing on this page that is a decision rather than a
## reading. A day that does not read as a positive number of minutes is refused rather than taken as
## nothing, and the figures about hours say so.
func state_working_day() -> Dictionary:
	if report == null:
		return {"ok": false, "reason": "there is no report on this page", "minutes": 0}
	var typed: String = "" if _day_field == null else _day_field.text.strip_edges()
	if not typed.is_valid_int():
		_set_status("A working day is a number of minutes, like 480, and '%s' is not one." % typed)
		return {"ok": false, "reason": "a working day is a number of minutes", "minutes": 0}
	var minutes: int = typed.to_int()
	if not report.set_working_day(minutes):
		_set_status("A working day of %d minutes is not a day the figures can use." % minutes)
		return {"ok": false, "reason": "a working day is more than no minutes", "minutes": minutes}
	_after_change()
	_set_status("A working day is stated as %s." % report.working_day_text())
	return {"ok": true, "reason": "", "minutes": minutes}


func _after_change() -> void:
	var spoken: Array[String] = unavailable_texts()
	refresh()
	_set_status("A working day is stated as %s; %d figure(s) still cannot be worked out." % [
		report.working_day_text(), spoken.size(),
	])
	report_changed.emit()


func _set_status(words: String) -> void:
	if _status != null:
		_status.text = words


# --- the controls' own entry points -------------------------------------------------------------


func _on_field_changed(_words: String) -> void:
	# Reading the figures again is what a changed argument means, and it is cheap: the report is a walk
	# over the records the desks already hold and it keeps nothing.
	refresh()


func _on_read_again() -> void:
	refresh.call_deferred()


func _on_state_day() -> void:
	state_working_day.call_deferred()


func _on_close_requested() -> void:
	hide()
	closed.emit()