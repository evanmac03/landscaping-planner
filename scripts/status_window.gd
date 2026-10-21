class_name StatusWindow
extends Window
## What the drawing has said, kept: the last few answers the status line gave, newest first.
##
## A `Window`, like every other page here, and for the plainest reason of all: it is a list of sentences
## someone reads at length, not a status bar they glance at. It is opened for the question the status
## line cannot answer - "what was it it said when I did that" - and then closed again.
##
## ## It owns nothing
##
## The answers are handed over as a `StatusHistory` the drawing keeps; this page reads it and writes
## nothing back. That is the arrangement the plant order page and the sheet list use, and it is what lets
## the whole page be driven by a test with no drawing, no document and no screen.
##
## ## It is a page, not a log file
##
## The history itself is capped (the drawing decides where - `StatusHistory.CAP`), so this lists the
## newest handful and says so. Nothing here promises a lifetime of everything ever said.

signal closed()

## Wide enough for a refusal to be read whole - the sentences this page exists for are the long ones -
## and tall enough for a screenful.
const SIZE := Vector2i(820, 560)

const EXPLANATION := (
	"The status line under the plan says what the drawing just did, and then it moves on. This is the "
	+ "same thing, kept: the newest answer at the top, and the ones before it under it."
)
const NOTHING_YET := "nothing has been done to this drawing yet, so there is nothing it has said."
const NO_DRAWING := "there is no drawing here, so nothing has been said."

var _history: StatusHistory = null
var _said: String = ""
## Rewriting the rows is not free, so it is done when the count or the newest answer changes rather than
## every frame the page is up.
var _lines_signature_seen: String = "<never written>"

var _list: ItemList = null
var _count: Label = null
var _hint: Label = null
var _status: Label = null


func _init() -> void:
	title = "What just happened"
	min_size = SIZE
	exclusive = false
	close_requested.connect(_on_close_requested)


func _ready() -> void:
	if _list == null:
		build()


# --- building -----------------------------------------------------------------------


## Build the whole page by hand, idempotent, and callable off-tree so a test can drive the same controls
## the program shows.
func build() -> void:
	if _list != null:
		return
	var column := VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 8)
	add_child(column)

	column.add_child(_heading("What just happened"))

	var explanation := _label(column, "Explanation", EXPLANATION)
	explanation.add_theme_color_override("font_color", Color(0.78, 0.8, 0.72))

	_count = _label(column, "Count", "")

	var list := ItemList.new()
	list.name = "Lines"
	# Sentences to read, not a list to drive: single selection so nothing is highlighted as a choice, and
	# no focus so the arrow keys stay with the drawing.
	list.select_mode = ItemList.SELECT_SINGLE
	list.focus_mode = Control.FOCUS_NONE
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(list)
	_list = list

	_hint = _label(column, "Hint", "")
	_hint.add_theme_color_override("font_color", Color(0.68, 0.72, 0.62))

	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(buttons)
	var close_button := _button(buttons, "Close")
	close_button.pressed.connect(_on_close_pressed)

	_status = _label(column, "Status", "")
	_status.add_theme_color_override("font_color", Color(0.72, 0.76, 0.68))


func _heading(words: String) -> Label:
	var label := Label.new()
	label.name = "Heading"
	label.text = words
	label.add_theme_font_size_override("font_size", 20)
	return label


func _label(parent: Node, node_name: String, words: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = words
	label.add_theme_font_size_override("font_size", 12)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(300.0, 0.0)
	parent.add_child(label)
	return label


func _button(parent: Node, words: String) -> Button:
	var button := Button.new()
	button.name = words.replace(" ", "") + "Button"
	button.text = words
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(button)
	return button


func _on_close_pressed() -> void:
	request_close()


func _on_close_requested() -> void:
	request_close()


## Put the page away and say so once, however it was asked for - the window's own close button, the
## Close button, or Escape (which `PageEscape` turns into `close_requested`).
func request_close() -> void:
	hide()
	closed.emit()


# --- what it shows ------------------------------------------------------------------


## Point the page at the drawing's history and write the rows. Writes nothing back, and says nothing:
## nothing has been done yet, the page has only been told what to show.
##
## The parameter is not called `history`: the page has a `history()` of its own, and a parameter may not
## share a name with a method of its own class.
func set_history(what_it_said: StatusHistory) -> void:
	build()
	_history = what_it_said
	_lines_signature_seen = "<never written>"
	show_lines()


func history() -> StatusHistory:
	return _history


## Write the rows from the history, if there is anything new to write. Returns whether they were
## rewritten, so the page can be refreshed on a tick without rebuilding the list per frame.
func show_lines() -> bool:
	build()
	var signature := _signature()
	if signature == _lines_signature_seen:
		_refresh_hint()
		return false
	_lines_signature_seen = signature
	_list.clear()
	var lines: Array[String] = []
	if _history != null:
		lines = _history.lines()
	for index in lines.size():
		_list.add_item(lines[index])
	if not lines.is_empty():
		# The row the status line under the plan is showing right now, called out because the whole point
		# of the page is knowing which of these is the one you just missed.
		_list.set_item_custom_fg_color(0, Color(1.0, 0.96, 0.8))
	_count.text = _count_words()
	_refresh_hint()
	return true


func _signature() -> String:
	if _history == null:
		return "none"
	return "%d|%s" % [_history.count(), _history.latest()]


func _count_words() -> String:
	if _history == null:
		return ""
	if _history.is_empty():
		return "no answers yet"
	if _history.count() >= StatusHistory.CAP:
		return "the last %d answers (older ones are not kept)" % _history.count()
	return "%d answer%s" % [_history.count(), "" if _history.count() == 1 else "s"]


func _refresh_hint() -> void:
	_hint.text = hint()


func line_count() -> int:
	return _list.item_count if _list != null else 0


## One sentence per row, newest first, exactly as the drawing said them.
func line_texts() -> Array[String]:
	var out: Array[String] = []
	if _list != null:
		for index in _list.item_count:
			out.append(_list.get_item_text(index))
	return out


## The last thing said, which is the top row - the answer that is still under the plan.
func newest() -> String:
	return _history.latest() if _history != null else ""


func hint() -> String:
	if _history == null:
		return NO_DRAWING
	if _history.is_empty():
		return NOTHING_YET
	return "the top row is what the plan is saying now, and it changes as you work."


## The guidance the page gives when it is opened, which is not the same claim as what it last did.
func opening_words() -> String:
	if _history == null:
		return NO_DRAWING
	if _history.is_empty():
		return NOTHING_YET
	return "the drawing last said: %s" % newest()


# --- what it says about itself -------------------------------------------------------


func say(words: String) -> void:
	build()
	_said = words
	if _status != null:
		_status.text = words


func said() -> String:
	return _said


func status_text() -> String:
	return _status.text if _status != null else ""


func count_text() -> String:
	return _count.text if _count != null else ""


## Nothing inside the rows takes the keyboard: they are sentences to read, not a list to drive. Whether
## the page keeps the reader's keys to itself is what decides whether Escape reaches it at all.
func rows_are_keyboard_free() -> bool:
	build()
	return _list.focus_mode == Control.FOCUS_NONE