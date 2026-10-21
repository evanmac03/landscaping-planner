class_name HelpWindow
extends Window
## The manual on the screen: the contents of `HelpDoc` in a list, the chosen subject beside it, and a
## box to search the whole thing with.
##
## A `Window`, like the plant library and the ground window, and for the one reason a window exists in
## this HUD: it has a field to type into, and a text field is the one thing the HUD may not own
## outside a window. `Root` is built focus-free so that no key of the drawing can be taken from it,
## and everything inside this window is behind that boundary.
##
## ## What it does not know
##
## Nothing about any one subject. It is handed topics - a title and a body of text - and shows them;
## which subjects exist and what they say is `HelpDoc`'s business, and the key reference is the HUD's,
## because only the HUD has the tables the keys come from. A page that knew its own contents would be
## a second copy of them.

const HelpDocScript := preload("res://scripts/help_doc.gd")

## The window was closed by its own close button.
signal closed()

## Big enough for a page of prose and a list of twenty subjects. The minimum rather than the size:
## `popup_centered` fits the window to its contents, so this is what stops the page being squeezed
## smaller than it can be read at.
const SIZE := Vector2i(960, 720)
## The contents column: wide enough for the longest subject in the manual on one line.
const LIST_WIDTH := 300.0

## Every topic, in the order they are read.
var _topics: Array[Dictionary] = []
## Which of `_topics` the list is showing, in list order. A search narrows this rather than the
## topics, so emptying the search box is the way back to the whole manual without re-reading anything.
var _shown: Array[int] = []
## Which topic is on the page, as an index into `_topics` - not into the list, which moves as the
## search changes. -1 when nothing is shown.
var _shown_topic: int = -1

var _list: ItemList = null
var _search: LineEdit = null
var _title_label: Label = null
var _body: RichTextLabel = null
var _status: Label = null


func _init() -> void:
	title = "Landscaping Planner help"
	min_size = SIZE
	exclusive = false
	close_requested.connect(_on_close_requested)


func _ready() -> void:
	if _list == null:
		build()


# --- building --------------------------------------------------------------------------------


## Build the whole window by hand. Idempotent, and callable off-tree so a test can drive the same
## controls the program shows.
func build() -> void:
	if _list != null:
		return
	var column := VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 8)
	add_child(column)

	# The search goes above everything, because the first thing somebody does with a manual this long
	# is look for a word in it. It is the only control here that may hold the keyboard.
	var find_row := HBoxContainer.new()
	find_row.name = "FindRow"
	find_row.add_theme_constant_override("separation", 6)
	column.add_child(find_row)
	var find_label := Label.new()
	find_label.name = "FindLabel"
	find_label.text = "Find"
	find_row.add_child(find_label)
	_search = LineEdit.new()
	_search.name = "Search"
	_search.placeholder_text = "a word to look for - mulch, invoice, snap, transformer"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(_on_search_changed)
	find_row.add_child(_search)

	var body_row := HBoxContainer.new()
	body_row.name = "BodyRow"
	body_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_row.add_theme_constant_override("separation", 10)
	column.add_child(body_row)

	var contents := VBoxContainer.new()
	contents.name = "Contents"
	contents.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	body_row.add_child(contents)
	var contents_label := Label.new()
	contents_label.name = "ContentsLabel"
	contents_label.text = "Contents"
	contents.add_child(contents_label)
	_list = ItemList.new()
	_list.name = "Topics"
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.select_mode = ItemList.SELECT_SINGLE
	# A list is picked from, not typewritten into: it must not take a key from the search box beside it
	# or from the window's own close button.
	_list.focus_mode = Control.FOCUS_NONE
	_list.item_selected.connect(_on_topic_selected)
	contents.add_child(_list)

	var page := VBoxContainer.new()
	page.name = "Page"
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_row.add_child(page)
	_title_label = Label.new()
	_title_label.name = "TopicTitle"
	_title_label.add_theme_font_size_override("font_size", 18)
	page.add_child(_title_label)
	_body = RichTextLabel.new()
	_body.name = "Body"
	# Plain text rather than markup: the manual is written as sentences, and a stray bracket in a
	# sentence would otherwise become a tag nobody could see.
	_body.bbcode_enabled = false
	_body.scroll_active = true
	# Readable and copyable, but never focused: selecting a sentence must not take the keys.
	_body.selection_enabled = true
	_body.focus_mode = Control.FOCUS_NONE
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(_body)

	_status = Label.new()
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)

	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", 6)
	column.add_child(actions)
	var close_button := Button.new()
	close_button.name = "CloseHelp"
	close_button.text = "Close"
	close_button.pressed.connect(_on_close_requested)
	actions.add_child(close_button)
	# A page that has been built and handed nothing shows that rather than a blank frame: one built by
	# hand and never filled is a page with no manual behind it, and the two labels saying nothing at all
	# would look like a page that had failed.
	_apply_filter()


# --- what it is showing -----------------------------------------------------------------------


## Show a set of topics. The window is built if it has not been built yet, so a page handed its
## subjects before it has ever been on the screen still fills in. The search is cleared with them,
## because a manual that opened on somebody else's last search would look as though it had lost most
## of itself.
func set_topics(topics: Array[Dictionary]) -> void:
	_topics = topics
	build()
	_search.text = ""
	_apply_filter()


## Show whatever the search box is asking for.
func filter() -> void:
	_apply_filter()


## Choose a row of the contents, the way a click does. The index is into the list as it is shown
## now, which is what a click gives and what the rows are numbered by.
func select(index: int) -> bool:
	if _list == null or index < 0 or index >= _list.item_count:
		return false
	_list.select(index)
	_show_row(index)
	return true


## Choose a topic by its title, wherever it is in the list.
func select_topic(wanted: String) -> bool:
	if _list == null:
		return false
	for row in _list.item_count:
		if _topic_title(int(_list.get_item_metadata(row))) == wanted:
			return select(row)
	return false


## Put a word in the search box and look, the way typing it would. `LineEdit.text` does not emit
## `text_changed`, so the search is asked for here rather than left to the signal.
func type_search(words: String) -> void:
	if _search == null:
		return
	_search.text = words
	_apply_filter()


## The title on the page.
func shown_title() -> String:
	return _title_label.text if _title_label != null else ""


## The body on the page, as the page has it.
func shown_body() -> String:
	return _body.text if _body != null else ""


## Which topic the page is showing, as an index into the topics that were handed over. -1 when the
## page is showing nothing, which is what a search that finds nothing leaves it showing.
func shown_topic_index() -> int:
	return _shown_topic


## Every topic handed over, however few the search is showing.
func topic_count() -> int:
	return _topics.size()


## How many the search is showing.
func shown_count() -> int:
	return _shown.size()


## The contents as a person reads it.
func list_texts() -> Array[String]:
	var out: Array[String] = []
	if _list == null:
		return out
	for index in _list.item_count:
		out.append(_list.get_item_text(index))
	return out


func search_text() -> String:
	return _search.text if _search != null else ""


func say(words: String) -> void:
	if _status != null:
		_status.text = words


func said() -> String:
	return _status.text if _status != null else ""


func status_text() -> String:
	return said()


# --- the controls themselves, for a test that has to read them ---------------------------------


## The contents list. Exposed so a test can check that picking from it does not take the keyboard.
func topics_list() -> ItemList:
	return _list


## The prose. Exposed for the same reason as the list.
func body_view() -> RichTextLabel:
	return _body


## The search box: the one control in here that *is* allowed to hold the keyboard.
func search_field() -> LineEdit:
	return _search


# --- the work ---------------------------------------------------------------------------------


## Narrow the contents to what the search box asks for, and show the first of them.
func _apply_filter() -> void:
	if _list == null:
		return
	var query := search_text()
	_shown = HelpDocScript.find_in(_topics, query)
	_list.clear()
	for absolute: int in _shown:
		_list.add_item(_topic_title(absolute))
		_list.set_item_metadata(_list.item_count - 1, absolute)
	if _shown.is_empty():
		_shown_topic = -1
		_list.deselect_all()
		if _topics.is_empty():
			# Not the same thing as a search that found nothing: there is no manual to search, and a
			# page that blamed the search box for that would be telling a person the wrong reason.
			_title_label.text = "The manual is empty"
			_body.text = "There is nothing in the manual to read."
			say("the manual has no topics in it")
			return
		_title_label.text = "Nothing found"
		# The whole concatenation is bracketed before the `%`: `%` binds tighter than `+`, so the
		# unbracketed form is a format applied to the last fragment alone - and a fragment with no
		# placeholder in it is a formatting error rather than a sentence.
		_body.text = (
			("Nothing in the manual mentions %s.\n\n"
			+ "Try a shorter word, or clear the box to read the contents again.") % _quoted(query)
		)
		say("%s: no topic mentions it. Clear the box for the whole manual." % _quoted(query))
		return
	select(0)
	say(_describe_shown(query))


## Put one topic on the page. The row is a row of the list, and the topic it stands for is carried
## on the row as its metadata - the list is filtered, so a row's number is not a topic's number.
func _show_row(row: int) -> void:
	_shown_topic = int(_list.get_item_metadata(row))
	_title_label.text = _topic_title(_shown_topic)
	_body.text = _topic_body(_shown_topic)
	_body.scroll_to_line(0)


func _topic_title(index: int) -> String:
	if index < 0 or index >= _topics.size():
		return ""
	return String(_topics[index].get("title", ""))


func _topic_body(index: int) -> String:
	if index < 0 or index >= _topics.size():
		return ""
	return String(_topics[index].get("body", ""))


## What the status line says about the search: how much of the manual is on the list, and why.
func _describe_shown(query: String) -> String:
	if query.strip_edges() == "":
		return "%d topics. Pick one from the contents to read it." % _shown.size()
	return "%d of %d topics mention %s." % [_shown.size(), _topics.size(), _quoted(query)]


static func _quoted(words: String) -> String:
	return "\"%s\"" % words.strip_edges()


# --- what it does -----------------------------------------------------------------------------


func _on_topic_selected(index: int) -> void:
	_show_row(index)


func _on_search_changed(_words: String) -> void:
	_apply_filter()


func _on_close_requested() -> void:
	hide()
	closed.emit()