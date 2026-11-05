class_name RevisionWindow
extends Window
## The history of the drawing: what was sent, what changed after it, and how to get an earlier one back.
##
## A `Window`, for the same reason the sheet setup is one: a revision needs a *message*, and a message is
## typed text, which only a window may take away from the drawing's keys.
##
## ## It owns no drawing
##
## Every line it shows is handed to it as a row, and every act is an intent it announces -
## `revision_recorded`, `restore_requested`. The HUD answers with the controller, which owns the drawing
## and the history. That is the hatch panel's arrangement, and it is what lets the whole window be
## driven by a test with no drawing and no screen.
##
## ## What it shows
##
## One row per revision, newest last, each reading the way a history is read: its message, who made it,
## when, and how many shapes the drawing had. Under the list, what the *selected* revision changed from
## the one before it - which is the question the log exists to answer, and the one thing a list of
## timestamps cannot tell you.

signal revision_recorded(message: String)
signal restore_requested(index: int)
signal closed()

## Wide enough for a revision line and the message box beside it, tall enough for a history of a
## reasonable job. Measured as the sheet window's was: a button that exists and cannot be pressed is not
## a button.
const SIZE := Vector2i(780, 560)

var _rows: Array[Dictionary] = []
var _index: int = 0
## How many revisions fell off the oldest end of the log, so the window can say that what it lists is the
## last of it rather than all of it.
var _dropped: int = 0
var _identity: Dictionary = {}
## True while the list is being filled, so a selection made in code does not echo back as a click - which
## would rebuild the pane under the cursor.
var _filling: bool = false
var _said: String = ""

var _list: ItemList = null
var _description: Label = null
var _change: Label = null
## What has happened to the drawing since the selected revision was taken: the one line that joins this
## history to the undo history (`DraftGestureHistory`).
var _since: Label = null
var _message: LineEdit = null
var _status: Label = null
var _restore_button: Button = null


func _init() -> void:
	title = "Revisions"
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

	column.add_child(PageChrome.subheading("The history of this drawing"))

	var body := HBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	var left := VBoxContainer.new()
	left.name = "Revisions"
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(left)
	left.add_child(PageChrome.text("Revision"))
	_list = ItemList.new()
	_list.name = "List"
	_list.custom_minimum_size = Vector2(300.0, 0.0)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_revision_selected)
	left.add_child(_list)

	# What the selected revision is, and what it changed. The change line is the point of the window:
	# a list of dates tells a person nothing about whether the drawing moved, and this tells them
	# without opening it.
	var right := VBoxContainer.new()
	right.name = "Changes"
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 4)
	body.add_child(right)
	right.add_child(PageChrome.text("This revision"))
	_description = _wrapped(right, "Description")
	right.add_child(PageChrome.text("Since the one before it"))
	_change = _wrapped(right, "Change")
	right.add_child(PageChrome.text("Done since"))
	_since = _wrapped(right, "DoneSince")

	right.add_child(PageChrome.text("Record a revision"))
	var row := HBoxContainer.new()
	row.name = "MessageRow"
	row.add_theme_constant_override("separation", 6)
	right.add_child(row)
	_message = LineEdit.new()
	_message.name = "MessageText"
	_message.placeholder_text = "what this drawing is now"
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_message)
	var record_button := _button(row, "Record this revision")
	record_button.pressed.connect(func() -> void: revision_recorded.emit(_message.text))

	_status = PageChrome.status()
	column.add_child(_status)

	var buttons := PageChrome.button_row()
	column.add_child(buttons)
	_restore_button = _button(buttons, "Put this revision back")
	_restore_button.pressed.connect(func() -> void: restore_requested.emit(_index))
	var close_button := _button(buttons, "Close")
	close_button.pressed.connect(func() -> void: closed.emit())


## A label that wraps, because a change line naming eight shapes is longer than the pane. Its size and
## its wrapping come from the shared chrome; what this page decides is the pane it fills and the name its
## own tests read.
func _wrapped(parent: Node, node_name: String) -> Label:
	var label := PageChrome.text()
	label.name = node_name
	label.custom_minimum_size = Vector2(300.0, 0.0)
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


## A button filling the row it sits in, made by the shared chrome so that its name, its caption and what
## it does with the keyboard are the project's rather than this page's. The one thing this adds is the
## equal share of the button strip the revisions page has always given its buttons.
func _button(parent: Node, words: String) -> Button:
	var made := PageChrome.button(words)
	made.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(made)
	return made


func _on_close_requested() -> void:
	closed.emit()


# --- what it shows ------------------------------------------------------------------


## What the history belongs to: the drawing, and the size of the history itself. The dropped count is
## said out loud, because "these are all the revisions" and "these are the last of them" are different
## claims and only one of them is true.
func set_identity(drawing: String, dropped: int) -> void:
	build()
	_identity = {"drawing": drawing, "dropped": dropped}
	_dropped = dropped


func identity() -> Dictionary:
	return _identity


## The revisions, as the controller describes them: one row per revision, oldest first. The selection is
## kept where it was if the row is still there, so recording a revision does not move the person off
## what they were reading.
func set_revisions(rows: Array[Dictionary]) -> void:
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


## What one revision is called in the list: which one it is and what it was called.
##
## Not the whole description - who made it, when, how many shapes - because a row long enough for all of
## that is a row nobody can scan, and it is all in the pane beside the list anyway. The list answers "which
## one", and the pane answers "what was it".
func _row_words(row: Dictionary) -> String:
	var message := String(row.get("message", ""))
	if message.is_empty():
		return "rev %d" % (int(row.get("index", 0)) + 1)
	return "rev %d  %s" % [int(row.get("index", 0)) + 1, message]


func row_count() -> int:
	return _rows.size()


func list_texts() -> Array[String]:
	var out: Array[String] = []
	for row: Dictionary in _rows:
		out.append(_row_words(row))
	return out


func selected_index() -> int:
	return _index


func selected_row() -> Dictionary:
	if _index < 0 or _index >= _rows.size():
		return {}
	return _rows[_index]


## What the selected revision changed from the one before it. Empty for the first revision, which has
## nothing before it to differ from - which is not the same as saying nothing changed.
func change_text() -> String:
	return String(selected_row().get("change", ""))


## What has been done to the drawing since the selected revision was taken. Empty when there is nothing
## to say, which is different from saying nothing happened - see `DraftController.gestures_since_text`.
func since_text() -> String:
	return String(selected_row().get("since", ""))


func description_text() -> String:
	return String(selected_row().get("description", ""))


func message_text() -> String:
	return _message.text if _message != null else ""


func status_text() -> String:
	if not _said.is_empty():
		return _said
	var kept: int = _rows.size()
	if kept == 0:
		return "nothing has been recorded against this drawing yet"
	var words := "%d revision" % kept
	if kept != 1:
		words += "s"
	words += " kept"
	if _dropped > 0:
		words += ", and %d older one" % _dropped
		if _dropped != 1:
			words += "s"
		words += " let go"
	return words


## Select a revision by index, as a click in the list does.
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


func _show_row() -> void:
	var row: Dictionary = selected_row()
	_description.text = String(row.get("description", ""))
	_change.text = change_text()
	_since.text = since_text()
	_restore_button.disabled = row.is_empty()
	_status.text = status_text()


func _on_revision_selected(index: int) -> void:
	if _filling:
		return
	_index = index
	_show_row()


func say(words: String) -> void:
	build()
	_said = words
	_status.text = status_text()


func said() -> String:
	return _said


# --- the same acts, scriptable ---------------------------------------------------------
#
# Each does exactly what the control above it does, so a test drives the window through the same path a
# person does rather than through a second one that exists only for tests.


## Type a message into the box.
func type_message(words: String) -> bool:
	build()
	_message.text = words
	return true


## Record the drawing as it stands, under the message in the box. The box is emptied here rather than by
## the HUD, because the next revision is a new message and a stale one is a lie about it.
func record() -> bool:
	build()
	var words := _message.text
	_message.text = ""
	revision_recorded.emit(words)
	return true


## Put the selected revision back. A window with no revisions recorded takes no intent: there is nothing
## a restore could be about.
func restore() -> bool:
	build()
	if _rows.is_empty():
		return false
	restore_requested.emit(_index)
	return true