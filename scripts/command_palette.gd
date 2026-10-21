class_name CommandPalette
extends Window
## Every command this program has, in one box with a field to type a word into.
##
## A `Window`, like the manual and the plant library, and for the one reason a window exists in this
## HUD: it has a field to type into, and a text field is the one thing the HUD may not own outside a
## window.
##
## ## What it does not know
##
## Nothing about any one command. It is handed rows - a label, the key that also does it, the menu it
## came from, whether it can run here, and the method that runs it - and shows them. Which commands
## exist is the bar's business, so the rows are built from the bar rather than written out again
## here: a palette with its own list of commands is a second menu bar, and the two would drift the
## first time one of them gained an entry. The palette does not even run them itself; it says which
## row was chosen and the HUD runs it through the one door the bar uses.
##
## ## Why a command that cannot run is shown rather than dropped
##
## The bar greys out what the scene cannot do rather than hiding it, so that a menu still says what
## the program does in a scene that cannot do it. The palette keeps the same rule and takes it one
## step further: choosing a command that cannot run here does not do nothing, it says what is missing
## by name. An entry that vanishes cannot teach anybody anything - and a command that is there in one
## drawing and gone in the next is worse than one that explains itself.

## The palette was closed, by Escape, by its own button, or by its own frame.
signal closed()
## A row was chosen. The row is carried whole, because the method it names and the entry that
## describes it are what runs it: the palette knows nothing about what any command does.
signal chosen(row: Dictionary)

## Big enough for a command and the reason it cannot run, and a list long enough to be worth
## searching. The minimum rather than the size: `popup_centered` fits the window to its contents, so
## this is what stops the box being squeezed smaller than a row can be read at.
const SIZE := Vector2i(640, 480)

## Every command handed over, in the order the bar holds them.
var _rows: Array[Dictionary] = []
## Which of `_rows` the list is showing, in list order. A search narrows this rather than the rows, so
## emptying the box is the way back to the whole bar without rebuilding anything.
var _shown: Array[int] = []

var _search: LineEdit = null
var _list: ItemList = null
var _status: Label = null


func _init() -> void:
	title = "Commands"
	min_size = SIZE
	# Not exclusive: the palette is a box over the drawing, not a decision that has to be answered
	# before anything else can happen.
	exclusive = false
	close_requested.connect(_on_close_requested)


func _ready() -> void:
	if _list == null:
		build()


# --- building ----------------------------------------------------------------------------------


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

	# The field goes above everything, and it is the only control here that may hold the keyboard:
	# the palette is typed into, and every key it wants - the arrows, Enter, Escape - is answered for
	# on this one control rather than scattered over four.
	var find_row := HBoxContainer.new()
	find_row.name = "FindRow"
	find_row.add_theme_constant_override("separation", 6)
	column.add_child(find_row)
	var find_label := Label.new()
	find_label.name = "FindLabel"
	find_label.text = "Command"
	find_row.add_child(find_label)
	_search = LineEdit.new()
	_search.name = "Search"
	_search.placeholder_text = "a command - undo, plot, mulch, invoice, transformer"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(_on_search_changed)
	_search.text_submitted.connect(_on_search_submitted)
	_search.gui_input.connect(_on_search_gui_input)
	find_row.add_child(_search)

	_list = ItemList.new()
	_list.name = "Commands"
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.select_mode = ItemList.SELECT_SINGLE
	# A list is picked from, not typed into: it must not take a key from the field above it.
	_list.focus_mode = Control.FOCUS_NONE
	_list.item_selected.connect(_on_row_selected)
	_list.item_activated.connect(_on_row_activated)
	column.add_child(_list)

	_status = Label.new()
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)

	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", 6)
	column.add_child(actions)
	var run_button := Button.new()
	run_button.name = "RunCommand"
	run_button.text = "Run"
	run_button.focus_mode = Control.FOCUS_NONE
	run_button.pressed.connect(run_selected)
	actions.add_child(run_button)
	var close_button := Button.new()
	close_button.name = "ClosePalette"
	close_button.text = "Close"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close_palette)
	actions.add_child(close_button)

	# A box that has been built and handed nothing says that rather than showing a blank frame: one
	# built by hand and never filled has no bar behind it, and two empty labels would look like a
	# palette that had failed.
	_apply_filter()


# --- what it is showing ------------------------------------------------------------------------


## Show a set of commands. The window is built if it has not been built yet, so a palette handed its
## commands before it has ever been on the screen still fills in. The search is cleared with them,
## because a palette that opened on somebody else's last search would look as though most of the
## program had gone.
func set_commands(rows: Array[Dictionary]) -> void:
	_rows = rows
	build()
	_search.text = ""
	_apply_filter()


## Show whatever the search box is asking for.
func filter() -> void:
	_apply_filter()


## Choose a row of the list, the way a click does. The index is into the list as it is shown now,
## which is what a click gives and what the rows are numbered by.
func select(row: int) -> bool:
	if _list == null or row < 0 or row >= _list.item_count:
		return false
	_list.select(row)
	_show_row(row)
	return true


## Choose a command by its id, wherever it is in the list.
func select_command(id: String) -> bool:
	for row in shown_count():
		if shown_id(row) == id:
			return select(row)
	return false


## Put a word in the search box and look, the way typing it would. `LineEdit.text` does not emit
## `text_changed`, so the search is asked for here rather than left to the signal.
func type_search(words: String) -> void:
	if _search == null:
		return
	_search.text = words
	_apply_filter()


## Run the row the list is on, the way Enter does. Returns whether anything was run: a row that
## cannot run here is refused by name rather than silently passed over, and the box stays open so
## that the next command is one keystroke away.
func run_selected() -> bool:
	if _list == null:
		say("no command is chosen")
		return false
	var picked: PackedInt32Array = _list.get_selected_items()
	if picked.is_empty():
		say("no command is chosen")
		return false
	_choose(picked[0])
	return true


## Run a command by its id, the way choosing its row does.
func run_command(id: String) -> bool:
	if not select_command(id):
		say("there is no command called %s" % _quoted(id))
		return false
	return run_selected()


## Every command handed over, however few the search is showing.
func command_count() -> int:
	return _rows.size()


## How many the search is showing.
func shown_count() -> int:
	return _shown.size()


## The commands as a person reads them, one row each.
func list_texts() -> Array[String]:
	var out: Array[String] = []
	if _list == null:
		return out
	for index in _list.item_count:
		out.append(_list.get_item_text(index))
	return out


## The id of a shown row, read off the row's metadata. The list is filtered, so a row's number is
## not a command's number.
func shown_id(row: int) -> String:
	if _list == null or row < 0 or row >= _list.item_count:
		return ""
	return String(_rows[int(_list.get_item_metadata(row))].get("id", ""))


## The whole row a shown row stands for.
func shown_row(row: int) -> Dictionary:
	if _list == null or row < 0 or row >= _list.item_count:
		return {}
	return _rows[int(_list.get_item_metadata(row))]


## Whether the row the list is on is one that can run in this scene.
func shown_is_available(row: int) -> bool:
	return bool(shown_row(row).get("available", false))


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


## The command list. Exposed so a test can check that picking from it does not take the keyboard.
func commands_list() -> ItemList:
	return _list


## The field: the one control in here that *is* allowed to hold the keyboard.
func search_field() -> LineEdit:
	return _search


# --- showing it --------------------------------------------------------------------------------


## Put the palette on the screen, with the keyboard already in the field - the whole point of the box
## is that a word can be typed into it without reaching for it first.
func open() -> void:
	build()
	popup_centered()
	if _search != null:
		_search.grab_focus()


## Take it off the screen. Says so once, however it was closed.
func close_palette() -> void:
	if not visible:
		return
	hide()
	closed.emit()


# --- the work ----------------------------------------------------------------------------------


## Narrow the list to what the search box asks for, and put the first of them under the cursor.
func _apply_filter() -> void:
	if _list == null:
		return
	var query := search_text()
	_shown = find_in(_rows, query)
	_list.clear()
	for absolute: int in _shown:
		_list.add_item(_row_text(_rows[absolute]))
		_list.set_item_metadata(_list.item_count - 1, absolute)
	if _shown.is_empty():
		_list.deselect_all()
		if _rows.is_empty():
			# Not the same thing as a search that found nothing: there is no bar to search, and a
			# palette that blamed the search box for that would be telling a person the wrong reason.
			say("there are no commands here")
			return
		say("%s: no command is called that. Clear the box for the whole bar." % _quoted(query))
		return
	select(0)
	say(_describe_shown(query))


## What one row says: what it is called, the key that also does it, and the menu it lives under. A
## command that cannot run here says what is missing in place of the menu, because that is the fact
## worth having in front of you before you press it.
func _row_text(row: Dictionary) -> String:
	var label := String(row.get("label", ""))
	if not bool(row.get("available", false)):
		return "%s    -    %s" % [label, String(row.get("why", "it cannot be done here"))]
	var key := String(row.get("key", ""))
	var menu := String(row.get("menu", ""))
	var parts: Array[String] = [label]
	if key != "":
		parts.append(key)
	parts.append(menu)
	return "    ".join(parts)


## Put the row's own state on the status line.
func _show_row(row: int) -> void:
	var picked: Dictionary = shown_row(row)
	if picked.is_empty():
		return
	if not bool(picked.get("available", false)):
		say(
			"%s cannot be used here: %s"
			% [String(picked.get("label", "")), String(picked.get("why", "it cannot be done here"))]
		)
		return
	say("Enter runs %s." % String(picked.get("label", "")))


## What the status line says about the search: how much of the bar is on the list, and why.
func _describe_shown(query: String) -> String:
	if query.strip_edges() == "":
		return "%d commands. Type to narrow them, Enter to run the chosen one." % _shown.size()
	return "%d of %d commands mention %s." % [_shown.size(), _rows.size(), _quoted(query)]


## Run a shown row: the command's own method, through the HUD, or the reason it cannot run.
func _choose(row: int) -> void:
	var picked: Dictionary = shown_row(row)
	if picked.is_empty():
		say("no command is chosen")
		return
	if not bool(picked.get("available", false)):
		# Refused by name rather than ignored. The box stays open: the command next to this one is
		# probably the one that was wanted.
		say(
			"%s cannot be used here: %s"
			% [String(picked.get("label", "")), String(picked.get("why", "it cannot be done here"))]
		)
		return
	chosen.emit(picked)
	close_palette()


# --- the search -------------------------------------------------------------------------------


## The rows whose label or menu mentions what is asked for, best first.
##
## Best first, because a palette is used a hundred times a day and the order it puts things in is
## the difference between a shortcut and a longer way round: a command whose *name* starts with the
## word beats one that merely contains it, and either beats one that is only in that menu. Ties keep
## the bar's own order, so the same search gives the same list every time.
##
## Static and pure, like the manual's: which of these matches is the half that is easy to get wrong
## and impossible to see.
static func find_in(among: Array[Dictionary], query: String) -> Array[int]:
	var wanted := query.strip_edges().to_lower()
	if wanted == "":
		var everything: Array[int] = []
		for index in among.size():
			everything.append(index)
		return everything
	var starting: Array[int] = []
	var containing: Array[int] = []
	var in_menu: Array[int] = []
	for index in among.size():
		var row: Dictionary = among[index]
		var label := String(row.get("label", "")).to_lower()
		var menu := String(row.get("menu", "")).to_lower()
		if label.begins_with(wanted):
			starting.append(index)
		elif label.contains(wanted):
			containing.append(index)
		elif menu.contains(wanted):
			in_menu.append(index)
	var out: Array[int] = []
	out.append_array(starting)
	out.append_array(containing)
	out.append_array(in_menu)
	return out


static func _quoted(words: String) -> String:
	return "\"%s\"" % words.strip_edges()


# --- what it does -----------------------------------------------------------------------------


## Move the cursor up or down the list, wrapping round, so the arrows are a way through the list
## without reaching for the mouse.
func _move_selection(step: int) -> void:
	var count := _list.item_count if _list != null else 0
	if count == 0:
		return
	var picked: PackedInt32Array = _list.get_selected_items()
	var current: int = picked[0] if not picked.is_empty() else -1
	var next: int = 0 if current < 0 else posmod(current + step, count)
	select(next)


func _on_row_selected(index: int) -> void:
	_show_row(index)


func _on_row_activated(index: int) -> void:
	# A double-click, or Enter while the list itself holds the keyboard, which it never does.
	_choose(index)


func _on_search_changed(_words: String) -> void:
	_apply_filter()


func _on_search_submitted(_words: String) -> void:
	run_selected()


## The keys a box like this is driven by, answered for on the one control that holds the keyboard.
##
## Escape, Enter and the arrows are read here rather than in the HUD, because while this window is up
## it is the window that has the keyboard and the HUD never sees them - which is the same reason the
## field exists at all. The code is taken from whichever of the two the event carries, because a key
## arrives with one or the other depending on how it was pressed.
func _on_search_gui_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var code := key.keycode if key.keycode != 0 else key.physical_keycode
	match code:
		KEY_ESCAPE:
			close_palette()
			_search.accept_event()
		KEY_ENTER, KEY_KP_ENTER:
			run_selected()
			_search.accept_event()
		KEY_DOWN:
			_move_selection(1)
			_search.accept_event()
		KEY_UP:
			_move_selection(-1)
			_search.accept_event()


func _on_close_requested() -> void:
	close_palette()