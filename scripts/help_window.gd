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
## Nothing about any one subject. It is handed topics - a title and a body of text, and what the topic
## says about its own place in the manual: the section it is filed under and the subjects it points at.
## Which subjects exist, what they say, how they are grouped and what points at what is `HelpDoc`'s
## business, and the key reference is the HUD's, because only the HUD has the tables the keys come from.
## A page that knew its own contents would be a second copy of them.
##
## ## Finding your way
##
## Four ways to move about, in the order a person reaches for them: typing in the box, walking the
## contents with the up and down arrows while the box holds the keyboard, pressing a cross-reference
## under a body, and going back along what has already been read.

const HelpDocScript := preload("res://scripts/help_doc.gd")

## The window was closed by its own close button.
signal closed()

## Big enough for a page of prose and a list of twenty subjects. The minimum rather than the size:
## the page is shown fitted to its contents, so this is what stops it being squeezed smaller than it
## can be read at. It is a floor that comes down to fit a screen smaller than the page - a floor taller
## than the display would push the page's own buttons off the bottom - which `clamped_minimum` works out
## and `open` applies.
const SIZE := Vector2i(960, 720)
## The contents column: wide enough for the longest subject in the manual on one line.
const LIST_WIDTH := 300.0
## What the row of cross-reference buttons is introduced by. A person who has finished a subject needs
## to be told that the buttons under it are other subjects rather than something about this one.
const SEE_CAPTION := "Read next:"
## How a section heading in the contents is written: dimmed, so a row that cannot be chosen does not
## look like one that can.
const SECTION_COLOUR := Color(0.55, 0.61, 0.7)

## Every topic, in the order they are read.
var _topics: Array[Dictionary] = []
## Which of `_topics` the list is showing, in list order. A search narrows this rather than the
## topics, so emptying the search box is the way back to the whole manual without re-reading anything.
var _shown: Array[int] = []
## Which topic is on the page, as an index into `_topics` - not into the list, which moves as the
## search changes. -1 when nothing is shown.
var _shown_topic: int = -1
## Where a person has been, newest last, and where back has put them, so the page can be *walked*
## rather than only jumped from. Topic indices, because that is what the page is showing.
var _back: Array[int] = []
var _forward: Array[int] = []

var _list: ItemList = null
var _search: LineEdit = null
var _title_label: Label = null
var _body: RichTextLabel = null
var _status: Label = null
## The cross-reference buttons under the body: one per subject the shown one points at, rebuilt
## whenever the page turns. Every one of them is `FOCUS_NONE` like the rest of the page.
var _see_row: HBoxContainer = null
var _see_buttons: Array[Button] = []


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
	# The arrow keys walk the contents while the box holds the keyboard. A single-line box has no use
	# for up and down itself, so taking them costs a typist nothing - and the box is the one control in
	# here that may hold the keyboard at all.
	_search.gui_input.connect(_on_search_input)
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

	# The subjects this one points at, under the prose. A row of buttons rather than a sentence of
	# names, because a name in a sentence is a thing to read and a button is a thing to press - and the
	# whole reason for a cross-reference is that a person wants to *go* there. Hidden until a subject
	# with links is on the page, so a manual whose subjects point at nothing is not a blank strip.
	_see_row = HBoxContainer.new()
	_see_row.name = "SeeAlso"
	_see_row.add_theme_constant_override("separation", 6)
	_see_row.visible = false
	page.add_child(_see_row)

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


# --- putting it on the screen -------------------------------------------------------------------

## The floor the window opens at, brought down to what a screen actually has room for. A window is
## shown fitted to its contents and clamped to the screen it lands on, but a `min_size` larger than
## that screen would fight the clamp and push the page's own controls off the edge - so the floor comes
## down to fit as well, and is never wider or taller than the page asked for in the first place.
##
## A screen nothing can be learned about - a headless run reports a nought by nought screen - leaves
## the floor at its full size: the page is made smaller for want of room, never for want of knowing.
static func clamped_minimum(available: Vector2i) -> Vector2i:
	if available.x <= 0 or available.y <= 0:
		return SIZE
	return Vector2i(mini(SIZE.x, available.x), mini(SIZE.y, available.y))


## Bring the window's floor down to what the screen it will land on can hold, and hand it back. Kept
## apart from showing the window so a test can read it without a window server.
func clamp_to_screen() -> Vector2i:
	var screen := DisplayServer.window_get_current_screen()
	var available := DisplayServer.screen_get_usable_rect(screen).size
	min_size = clamped_minimum(available)
	return min_size


## Put the page on the screen: built, its floor fitted to the screen, sized to its contents and
## centred - and the keyboard put in the search box, because looking a word up is what a manual this
## long is for. The parts a test can drive without a window server are `build`, `clamp_to_screen` and
## `move_selection`.
func open() -> void:
	build()
	clamp_to_screen()
	popup_centered_clamped()
	if _search != null:
		_search.grab_focus()


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
##
## A section heading is a row of the list too, and it is not a subject: choosing one is refused rather
## than silently opening whatever happens to be filed under it.
func select(row: int) -> bool:
	if _list == null or row < 0 or row >= _list.item_count:
		return false
	if not _list.is_item_selectable(row):
		return false
	var index := int(_list.get_item_metadata(row))
	if index < 0 or index >= _topics.size():
		return false
	_list.select(row)
	_go(index)
	return true


## Choose a topic by its title, wherever it is in the list.
func select_topic(wanted: String) -> bool:
	var row := row_of(wanted)
	if row < 0:
		return false
	return select(row)


## The row a subject is listed at, or -1 when the list is not showing it. Section headings are skipped,
## so this is a row a person can actually choose.
func row_of(wanted: String) -> int:
	if _list == null:
		return -1
	for row in _list.item_count:
		if not _list.is_item_selectable(row):
			continue
		if _topic_title(int(_list.get_item_metadata(row))) == wanted:
			return row
	return -1


## Walk the contents with the keyboard: one subject on, or one back. Section headings are skipped -
## they are furniture and cannot be chosen - and either end stops rather than wrapping, because a
## manual has a first subject and a last one and a person who walks off the end wants to know it. The
## page moves only if it can; `false` means it is already at the end it was walking towards.
func move_selection(step: int) -> bool:
	if _list == null or step == 0:
		return false
	var from := _selected_row()
	if from < 0:
		return select(_first_topic_row())
	var row := _next_topic_row(from, step)
	if row < 0:
		return false
	return select(row)


## Every row of the list, headings and all - what the contents *looks* like rather than what it holds.
func list_rows() -> Array[String]:
	var out: Array[String] = []
	if _list == null:
		return out
	for row in _list.item_count:
		out.append(_list.get_item_text(row))
	return out


## The subjects the page is offering to read next, in the order the buttons are laid out.
func see_links() -> Array[String]:
	var out: Array[String] = []
	for button: Button in _see_buttons:
		if is_instance_valid(button):
			out.append(button.text)
	return out


## Go to a subject by name, the way one of the cross-reference buttons does.
##
## A link points at a subject, not at a row, so it works even while a search is hiding that subject:
## the box is cleared first, because a link that appears to do nothing is worse than one that widens
## the contents. A name the manual does not have is said rather than silently ignored.
##
## The parameter is not called `title`: a `Window` has a `title` property, and a parameter of that name
## shadows the window's own.
func follow(subject: String) -> bool:
	if _index_of(subject) < 0:
		say("there is no subject called \"%s\" to read" % subject)
		return false
	if row_of(subject) < 0 and not search_text().strip_edges().is_empty():
		_search.text = ""
		_apply_filter()
	return select_topic(subject)


## Walk back to the subject the page was showing before this one, or refuse when there is none.
func back() -> bool:
	if _back.is_empty():
		return false
	var to: int = _back.pop_back()
	if _shown_topic >= 0:
		_forward.append(_shown_topic)
	_show_topic(to)
	return true


## And forward again, along the way back was walked.
func forward() -> bool:
	if _forward.is_empty():
		return false
	var to: int = _forward.pop_back()
	if _shown_topic >= 0:
		_back.append(_shown_topic)
	_show_topic(to)
	return true


func can_go_back() -> bool:
	return not _back.is_empty()


func can_go_forward() -> bool:
	return not _forward.is_empty()


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


## The contents as a person reads it: the subjects, in order.
##
## The section headings the list is drawn with are left out. They are furniture - the same subjects
## under a heading are the same subjects - so what the manual is offering to read is this and nothing
## more. `list_rows` is what the control itself is showing, headings and all.
func list_texts() -> Array[String]:
	var out: Array[String] = []
	if _list == null:
		return out
	for index in _list.item_count:
		if not _list.is_item_selectable(index):
			continue
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


## The row the "read next" buttons are laid out in. Exposed for the same reason as the list: a
## cross-reference is pressed with the mouse, like everything else on the page, and that is checked
## against the buttons themselves rather than against what the page meant to do.
func see_view() -> HBoxContainer:
	return _see_row


## The search box: the one control in here that *is* allowed to hold the keyboard.
func search_field() -> LineEdit:
	return _search


# --- the work ---------------------------------------------------------------------------------


## Narrow the contents to what the search box asks for, and show the first of them.
func _apply_filter() -> void:
	if _list == null:
		return
	# A search starts a fresh walk. The subjects back and forward would go to are the ones the contents
	# was showing a moment ago, and a Back that landed on a subject the list no longer holds would be a
	# page out of step with its own contents - so the search clears the trail rather than keeping it.
	_back.clear()
	_forward.clear()
	var query := search_text()
	_shown = HelpDocScript.find_in(_topics, query)
	_list.clear()
	# The section headings are rows of the list that cannot be chosen. One is written when the section
	# the subject is filed under changes, so a run of subjects sharing a section gets one heading and a
	# search that finds one subject from each of three sections still reads under its own headings.
	var section := ""
	for absolute: int in _shown:
		var here := _topic_section(absolute)
		if here != section:
			section = here
			if here != "":
				_list.add_item(here)
				_list.set_item_selectable(_list.item_count - 1, false)
				_list.set_item_metadata(_list.item_count - 1, -1)
				_list.set_item_custom_fg_color(_list.item_count - 1, SECTION_COLOUR)
		_list.add_item(_topic_title(absolute))
		_list.set_item_metadata(_list.item_count - 1, absolute)
	if _shown.is_empty():
		_shown_topic = -1
		_list.deselect_all()
		_show_see(-1)
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
			("Nothing in the manual matches %s.\n\n"
			+ "Try a shorter word, or clear the box to read the contents again.") % _quoted(query)
		)
		say("%s: no topic matches it. Clear the box for the whole manual." % _quoted(query))
		return
	_show_first()
	say(_describe_shown(query))


## Put the first subject the contents is holding on the page. Not `select(0)`: with headings in the
## list the first row may be one of them, and a page that opened on a heading would be showing nothing.
func _show_first() -> void:
	var row := _first_topic_row()
	if row < 0:
		_shown_topic = -1
		_show_see(-1)
		return
	_list.select(row)
	_show_topic(int(_list.get_item_metadata(row)))


## The first row a person can choose, or -1 when there is none.
func _first_topic_row() -> int:
	for row in _list.item_count:
		if _list.is_item_selectable(row) and int(_list.get_item_metadata(row)) >= 0:
			return row
	return -1


## The row the contents has chosen, or -1 when it has chosen nothing.
func _selected_row() -> int:
	var chosen := _list.get_selected_items()
	if chosen.is_empty():
		return -1
	return chosen[0]


## The next row a person can choose in `step` direction from `row`, or -1 when the contents runs out
## that way: headings (selectable=false, metadata=-1) and any other furniture are stepped over rather
## than landed on, so the walk visits only content rows.
func _next_topic_row(row: int, step: int) -> int:
	var at := row + step
	while at >= 0 and at < _list.item_count:
		if _list.is_item_selectable(at) and int(_list.get_item_metadata(at)) >= 0:
			return at
		at += step
	return -1


## Put one topic on the page. The row is a row of the list, and the topic it stands for is carried
## on the row as its metadata - the list is filtered, so a row's number is not a topic's number.
func _show_row(row: int) -> void:
	if _list == null or row < 0 or row >= _list.item_count:
		return
	var index := int(_list.get_item_metadata(row))
	if index >= 0 and index < _topics.size():
		_go(index)


## Turn to a subject, and remember where the page was so it can be walked back.
func _go(index: int) -> void:
	if index < 0 or index >= _topics.size():
		return
	if index != _shown_topic:
		if _shown_topic >= 0:
			_back.append(_shown_topic)
		# Turning to a new subject is where the walk goes next; never mind the way forward from wherever
		# the page happened to be before it.
		_forward.clear()
	_show_topic(index)


## Put a subject on the page without touching the trail: what back, forward and opening all use.
func _show_topic(index: int) -> void:
	_shown_topic = index
	_title_label.text = _topic_title(index)
	_body.text = _topic_body(index)
	_body.scroll_to_line(0)
	_show_see(index)


## Rebuild the cross-reference buttons for the subject on the page, hiding the row when it points at
## nothing.
func _show_see(index: int) -> void:
	if _see_row == null:
		return
	for child: Node in _see_row.get_children():
		# Freed rather than queued: the row is read back the moment it is written, and a node waiting to
		# be freed at the end of the frame would still be counted among the buttons.
		_see_row.remove_child(child)
		child.free()
	_see_buttons = []
	var links := _topic_see(index)
	if links.is_empty():
		_see_row.visible = false
		return
	var caption := Label.new()
	caption.name = "SeeCaption"
	caption.text = SEE_CAPTION
	_see_row.add_child(caption)
	for target: String in links:
		var button := Button.new()
		# Not named after the subject: a title carries a colon, and a colon is not a character a node
		# name may hold.
		button.text = target
		button.tooltip_text = "Read \"%s\"" % target
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_see_pressed.bind(target))
		_see_row.add_child(button)
		_see_buttons.append(button)
	_see_row.visible = true


func _on_see_pressed(target: String) -> void:
	follow(target)


## The subjects the shown topic points at, empty when it has an index that is not a topic.
func _topic_see(index: int) -> Array[String]:
	var out: Array[String] = []
	if index < 0 or index >= _topics.size():
		return out
	for target: Variant in _topics[index].get("see", []):
		out.append(String(target))
	return out


## The section a topic is filed under, or "" when no section names it.
func _topic_section(index: int) -> String:
	if index < 0 or index >= _topics.size():
		return ""
	return String(_topics[index].get("section", ""))


## Where a subject sits in the topics that were handed over, or -1 when there is no such subject.
func _index_of(wanted: String) -> int:
	for index in _topics.size():
		if _topic_title(index) == wanted:
			return index
	return -1


func _topic_title(index: int) -> String:
	if index < 0 or index >= _topics.size():
		return ""
	return String(_topics[index].get("title", ""))


func _topic_body(index: int) -> String:
	if index < 0 or index >= _topics.size():
		return ""
	return String(_topics[index].get("body", ""))


## What the status line says about the search: how much of the manual is on the list, and why.
##
## "Match" rather than "mention", because the search has a last tier that finds a subject by the part of
## the manual it is filed under - a subject that need not contain the word itself. And "the best first",
## because the order is a rule rather than the contents order, and a reader who cannot see the rule can
## at least see that there is one.
func _describe_shown(query: String) -> String:
	if query.strip_edges() == "":
		return "%d topics. Pick one from the contents to read it." % _shown.size()
	return "%d of %d topics match %s, the best first." % [_shown.size(), _topics.size(), _quoted(query)]


static func _quoted(words: String) -> String:
	return "\"%s\"" % words.strip_edges()


# --- what it does -----------------------------------------------------------------------------


func _on_topic_selected(index: int) -> void:
	_show_row(index)


func _on_search_changed(_words: String) -> void:
	_apply_filter()


## The arrow keys, pressed while the search box holds the keyboard, walk the contents rather than
## moving a caret. Nothing is marked handled: up and down are not keys a single-line box uses, so there
## is nothing of the box's to take - and the box is the only control that can have been focused.
func _on_search_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_down"):
		move_selection(1)
	elif event.is_action_pressed("ui_up"):
		move_selection(-1)


func _on_close_requested() -> void:
	hide()
	closed.emit()