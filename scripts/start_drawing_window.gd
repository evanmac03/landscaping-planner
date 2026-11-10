class_name StartDrawingWindow
extends Window
## The begin-a-drawing page: the four ways to start a drawing, offered once the drawing board is chosen.
##
## A `Window` like the other pages, for the same reasons they are: it holds buttons a person presses, and a
## `Window` owns its own input, so nothing here can take the drawing's keys. The four ways, the words on
## their buttons and every sentence come from `StartDrawing`, so the page cannot offer a fifth thing or word
## one differently from the model the tests hold.
##
## What this page deliberately does **not** do is decide anything. Taking a way answers with its id and puts
## the page away, and the HUD runs the same handler the File menu's entry runs - so New here and File > New
## drawing are one action, not two that can drift apart. The recent drawings are shown inside the page
## rather than handed off, and a recent drawing answers with the path it opens.
##
## The page stands where the front door stood, over the same opaque sheet: the drawing board is behind it,
## already here, and this is the last question before a person is looking at it.

const StartDrawingScript := preload("res://scripts/start_drawing.gd")

## A way was taken. The id is one of `StartDrawing`'s - `new`, `open`, `recent` or `example`.
signal chosen(id: StringName)
## A remembered drawing was chosen to open, by its path.
signal recent_chosen(path: String)
## The page was put away, however it was asked for - the Close button, Escape, or the title bar's cross.
signal closed()

## Room for the page, and the room is mostly slack on purpose: on a phone the shared chrome makes every
## button big enough for a thumb, and a page with four ways and a recent list needs the room. The column
## scrolls (`PageChrome.scrolling_column`), so a page that grows taller than this on a smaller screen reaches
## its own bottom rather than cutting it off.
const SIZE := Vector2i(540, 560)
## Where the way buttons are told apart by a test, and by anything that ever needs to press one.
const BUTTON_PREFIX := "Choose"

var _column: VBoxContainer = null
var _opening: Label = null
var _status: Label = null
var _buttons: Dictionary = {}
var _recent_section: VBoxContainer = null
var _recent_list: VBoxContainer = null
var _recent_paths: Array[String] = []


func _init() -> void:
	title = StartDrawingScript.TITLE
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
	# A scrolling column, because the recent list appears on demand and pushes the Close row down: on a
	# smaller screen the rest of the page scrolls into view rather than being cut off.
	_column = PageChrome.scrolling_column(self, 10)

	_opening = PageChrome.note(StartDrawingScript.OPENING)
	_opening.name = "Opening"
	_column.add_child(_opening)

	_column.add_child(PageChrome.separator())

	for entry: Dictionary in StartDrawingScript.WAYS:
		var id := StringName(entry.get("id", ""))
		var made: Button = PageChrome.button(String(entry.get("label", "")))
		made.name = BUTTON_PREFIX + String(id).capitalize()
		made.pressed.connect(choose.bind(id))
		_column.add_child(made)
		_buttons[id] = made
		var line: Label = PageChrome.note(String(entry.get("line", "")))
		line.name = made.name + "Line"
		_column.add_child(line)

	# The recent drawings, under the "Open recent" button and hidden until it is pressed. Made here so a
	# page that binds nothing still shows a page rather than a hole.
	_recent_section = VBoxContainer.new()
	_recent_section.name = "RecentSection"
	_recent_section.add_theme_constant_override("separation", 6)
	_recent_section.visible = false
	_column.add_child(_recent_section)

	var heading: Label = PageChrome.subheading(StartDrawingScript.RECENT_HEADING)
	heading.name = "RecentHeading"
	_recent_section.add_child(heading)

	_recent_list = VBoxContainer.new()
	_recent_list.name = "RecentList"
	_recent_list.add_theme_constant_override("separation", 4)
	_recent_section.add_child(_recent_list)

	var row := PageChrome.button_row()
	_column.add_child(row)
	var close_button := PageChrome.button("Close")
	close_button.name = "CloseButton"
	close_button.pressed.connect(_on_close_requested)
	row.add_child(close_button)

	# No height is reserved for the status line: it carries nothing until there is something to say.
	_status = PageChrome.status("")
	_column.add_child(_status)

	_fill_recent()


# --- what it offers -----------------------------------------------------------------------------


## Take a way. The three that leave the page answer with their id and put the page away; the recent one
## shows the drawings to come back to instead of leaving, because there is still a choice to make.
func choose(id: StringName) -> void:
	if not _buttons.has(id):
		say("There is nothing here called %s." % String(id))
		return
	if id == StartDrawingScript.RECENT:
		_reveal_recent()
		return
	chosen.emit(id)
	# Every other way leaves the page: the drawing board stands behind it, so taking a way and closing the
	# page are the same act.
	request_close()


## Show the drawings that were opened recently, or say there are none. Taking nothing yet.
func _reveal_recent() -> void:
	if _recent_paths.is_empty():
		say(StartDrawingScript.NOTHING_RECENT)
		return
	if _recent_section != null:
		_recent_section.visible = true
	say(StartDrawingScript.RECENT_HINT)


## Hand the page the drawings to come back to, newest first, as the store gives them. Callable before or
## after `build()`: the rows are rebuilt either way.
func bind_recent(paths: Array[String]) -> void:
	_recent_paths = paths.duplicate()
	_fill_recent()


## The ids on offer, in the order the buttons stand.
func choice_buttons() -> Array[StringName]:
	var ordered: Array[StringName] = []
	for id: StringName in StartDrawingScript.ids():
		if _buttons.has(id):
			ordered.append(id)
	return ordered


func button_of(id: StringName) -> Button:
	var found: Object = _buttons.get(id)
	return found as Button


## The buttons for the remembered drawings, in the order they are shown, for a test or a press.
func recent_buttons() -> Array[Button]:
	var out: Array[Button] = []
	if _recent_list == null:
		return out
	for child: Node in _recent_list.get_children():
		var made: Button = child as Button
		if made != null:
			out.append(made)
	return out


## The path a recent button opens, or "" when this node is not one of them.
func recent_path_of(button: Button) -> String:
	if button == null:
		return ""
	return str(button.get_meta("path", ""))


func opening_text() -> String:
	return _opening.text if _opening != null else ""


func status_text() -> String:
	return _status.text if _status != null else ""


func say(words: String) -> void:
	if _status != null:
		_status.text = words


# --- the recent rows ----------------------------------------------------------------------------


func _fill_recent() -> void:
	if _recent_list == null:
		return
	for child: Node in _recent_list.get_children():
		_recent_list.remove_child(child)
		child.queue_free()
	for row: Dictionary in StartDrawingScript.recent_rows(_recent_paths):
		var path := String(row["path"])
		var made: Button = PageChrome.button(String(row["label"]))
		made.set_meta("path", path)
		made.pressed.connect(_on_recent_pressed.bind(path))
		_recent_list.add_child(made)


func _on_recent_pressed(path: String) -> void:
	recent_chosen.emit(path)
	request_close()


# --- the way out --------------------------------------------------------------------------------


## Put the page away. The one place this page hides itself, so that every way out of it - the Close button,
## Escape, the title bar's cross, or a way that has been taken - leaves exactly the same state: the page
## gone, and the drawing standing behind it where it always was.
func request_close() -> void:
	hide()
	closed.emit()


func _on_close_requested() -> void:
	request_close()