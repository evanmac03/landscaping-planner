class_name StartWindow
extends Window
## The front door: the two things this program is opened to do (specification §2).
##
## A `Window` like the other pages, for the same reasons they are: it holds buttons a person presses, and a
## `Window` owns its own input, so nothing here can take the drawing's keys. Both buttons and the words on
## them come from `StartChoices`, so the door cannot offer a third thing or word one differently from the
## model the tests hold.
##
## What this page deliberately does **not** do is hide itself. The drawing board is already behind it, so
## closing the door - by its Close button, or by Escape - is nothing more than putting the page away, and the
## person is where they wanted to be. The camera is different: it is a page that stands *over* the door
## rather than replacing it, so a photograph taken from here can be closed and another taken, and the door is
## still there to lead into the drawing when the photographing is done.

const StartScript := preload("res://scripts/start_choices.gd")

## A choice was taken. The id is one of `StartChoices`' - `design` or `camera`.
signal chosen(id: StringName)
## The door was put away, however it was asked for - the Close button, Escape, or the title bar's cross.
signal closed()

## Room for the door, and the room is mostly slack on purpose.
##
## On a computer the contents want 201 by 293 px. The page is declared at nearly twice that because on a
## phone the shared chrome makes every button big enough for a thumb, and a door with four of them needs the
## room - the first version of this page declared 520 by 320 and, on the SM-A166W, its Close button fell off
## the bottom edge. The page layout check cannot catch that: it measures at a desk, deliberately, which is
## what keeps it measuring the pages this project designed rather than a phone's version of them.
##
## So the slack is the phone's room, exactly as it is on the other tall-and-spare pages here.
const SIZE := Vector2i(520, 540)
## Where the buttons are told apart by a test, and by anything that ever needs to press one.
const BUTTON_PREFIX := "Choose"

var _column: VBoxContainer = null
var _opening: Label = null
var _status: Label = null
var _buttons: Dictionary = {}


func _init() -> void:
	title = StartScript.TITLE
	min_size = SIZE
	exclusive = false
	close_requested.connect(_on_close_requested)


func _ready() -> void:
	if _column == null:
		build()


# --- building -----------------------------------------------------------------------------------


## Build the whole window by hand. Idempotent, and callable off-tree so a test can press the same buttons
## the program shows.
func build() -> void:
	if _column != null:
		return
	_column = PageChrome.column(self, 10)

	# No heading in the page: its own title bar already carries the program's name, and saying it twice only
	# takes room away from the two things this page is here to offer.
	_opening = PageChrome.text(StartScript.OPENING)
	_opening.name = "Opening"
	_column.add_child(_opening)

	_column.add_child(PageChrome.separator())

	for choice: Dictionary in StartScript.CHOICES:
		var id := StringName(choice.get("id", ""))
		var made: Button = PageChrome.button(String(choice.get("label", "")))
		made.name = BUTTON_PREFIX + String(id).capitalize()
		made.pressed.connect(choose.bind(id))
		_column.add_child(made)
		_buttons[id] = made
		var line: Label = PageChrome.note(String(choice.get("line", "")))
		line.name = made.name + "Line"
		_column.add_child(line)

	var row := PageChrome.button_row()
	# The shared button row puts a page's buttons at its foot, right-aligned, because there they are nearly
	# always an OK-and-Cancel pair read from the right. This door has one button at its foot and everything
	# above it is centred - the title is, and both choices run the width of the column - so a lone Close
	# pushed to the right edge reads as a stray rather than as the door's own way out. The row is still the
	# shared one; only this page's use of it is turned to the middle.
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_column.add_child(row)
	var close_button := PageChrome.button("Close")
	close_button.name = "CloseButton"
	close_button.pressed.connect(_on_close_requested)
	row.add_child(close_button)

	# No height is reserved for the status line: the shared status line carries no minimum, and a page that
	# reserves room whether or not it has anything to say is a page asking for space it is not using.
	_status = PageChrome.status("")
	_column.add_child(_status)


# --- what it offers -----------------------------------------------------------------------------


## Take a choice. Every button here answers with this, so a test presses exactly what a person presses.
func choose(id: StringName) -> void:
	if not _buttons.has(id):
		say("There is nothing here called %s." % String(id))
		return
	chosen.emit(id)
	# A choice that means "you are already there" puts the door away, because the drawing board stands behind
	# this page: taking it and closing the page are the same act. Which choice that is comes from the model,
	# so the page cannot decide for itself that the design button happens to be the one.
	if id == StartScript.dismissed():
		request_close()


## The ids on offer, in the order the buttons stand.
func choice_buttons() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _buttons:
		out.append(id)
	# Dictionary order is insertion order in this language, and the buttons were inserted as they were
	# offered - but the model is what decides the order, so it is the model the answer is sorted by.
	var ordered: Array[StringName] = []
	for id: StringName in StartScript.ids():
		if _buttons.has(id):
			ordered.append(id)
	return ordered if not ordered.is_empty() else out


func button_of(id: StringName) -> Button:
	var found: Object = _buttons.get(id)
	return found as Button


func opening_text() -> String:
	return _opening.text if _opening != null else ""


func status_text() -> String:
	return _status.text if _status != null else ""


func say(words: String) -> void:
	if _status != null:
		_status.text = words


# --- the two ways out ---------------------------------------------------------------------------


## Put the door away. The one place this page hides itself, so that every way out of it - the Close button,
## Escape, the title bar's cross, or the choice that means the drawing board - leaves exactly the same state:
## the door gone, and the drawing standing behind it where it always was.
func request_close() -> void:
	hide()
	closed.emit()


func _on_close_requested() -> void:
	request_close()