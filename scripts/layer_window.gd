class_name LayerWindow
extends Window
## The drawing's layers on a page: every layer, what it is for, and the two things done to one here -
## lock it against editing, or make it the layer new shapes are drawn on.
##
## A `Window` like the library and the ground window, for the same reason they are: it has a field to
## type into (the search box), and a `Window` owns its own input, so nothing here can take the
## drawing's keys. It *builds* every control but the search field without a keyboard of its own, which is
## this project's rule for a control; what a page that is **open** does with the keyboard is decided once,
## in `PageChrome.takes_the_keyboard`, which the shared show calls - so a person can walk this page with
## Tab and press its buttons with Enter all the same.
##
## It shows what `LayerDialog` says and decides nothing itself. The dialog reads the drawing and makes
## every change through the document, so a lock taken here is one undo step like any other, and the
## page holds no opinion about layers the drawing does not already hold.

const DialogScript := preload("res://scripts/draft/layer_dialog.gd")
const ControllerScript := preload("res://scripts/draft/draft_controller.gd")

## The window was closed by its own close button.
signal closed()
## A layer was locked, unlocked or made current. The drawing may want to redraw, and whatever says
## which layer is current is now stale.
signal layers_changed()

## Wide enough for a layer's name and what it is for beside its own facts.
const SIZE := Vector2i(720, 640)

## The layer data and every change, backed by the drawing's controller.
var dialog: DialogScript = null

var _column: VBoxContainer = null
var _search: LineEdit = null
var _list: ItemList = null
var _status: Label = null
var _lock_button: Button = null
var _current_button: Button = null
## The layer names the list is showing, in order: a list row's index is a position, and these are what
## the positions mean.
var _shown_names: Array[StringName] = []


func _init() -> void:
	title = "Layers"
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
	_ensure_dialog()
	_column = PageChrome.column(self)

	# The search box is the one control here that may hold the keyboard, and the only one a person
	# types into.
	_search = LineEdit.new()
	_search.name = "Search"
	_search.placeholder_text = "a word in a layer's name"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(_on_search_changed)
	# A caption and the box it names, in one row: the crib the page has a row for is the page's own
	# name for it rather than the shared builder's, which is set here after it.
	var find_row: HBoxContainer = PageChrome.labelled("Find", _search)
	find_row.name = "FindRow"
	_column.add_child(find_row)

	_list = ItemList.new()
	_list.name = "Layers"
	_list.focus_mode = Control.FOCUS_NONE
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(0, 240)
	_list.item_selected.connect(_on_layer_selected)
	_column.add_child(_list)

	# The line the page says what just happened on. It reserves no room of its own, which is the shared
	# rule: a status line holding space for a sentence it may not have is a page asking for room it is
	# not using.
	_status = PageChrome.status()
	_column.add_child(_status)

	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", 6)
	_column.add_child(actions)
	_lock_button = PageChrome.button("Lock")
	_lock_button.pressed.connect(_on_lock_pressed)
	actions.add_child(_lock_button)
	_current_button = PageChrome.button("Make current")
	_current_button.name = "CurrentButton"
	_current_button.pressed.connect(_on_current_pressed)
	actions.add_child(_current_button)

	var close_row := HBoxContainer.new()
	close_row.name = "CloseRow"
	_column.add_child(close_row)
	# The shared builder names a button from its caption, which would make this `CloseButton`: the name
	# this row is read by is a fact the page already holds, so it sets it rather than the builder.
	var close_button: Button = PageChrome.button("Close")
	close_button.name = "Close"
	close_button.pressed.connect(_on_close_requested)
	close_row.add_child(close_button)

	refresh()


## Make the dialog once, and make it a child so the page owns it: freeing the window frees the layer
## data with it, rather than leaving a Node behind for a test runner to report.
func _ensure_dialog() -> void:
	if dialog != null:
		return
	dialog = DialogScript.new()
	add_child(dialog)


## Point the page at the drawing's controller. Everything the page shows is read from it.
func bind(controller: ControllerScript) -> void:
	_ensure_dialog()
	dialog.controller = controller
	if _column != null:
		refresh()


# --- what it shows ------------------------------------------------------------------------------


## Read the drawing again and rebuild the list. The search box's own word is kept, so a refresh after
## a change shows the same narrowed list.
func refresh() -> void:
	if dialog == null:
		return
	dialog.refresh_layers()
	_rebuild_list()


## Put a word in the box and filter by it. `LineEdit.text` does not emit `text_changed`, so the filter
## is asked for here rather than left to the signal.
func type_search(words: String) -> void:
	if _search == null:
		return
	_search.text = words
	_on_search_changed(words)


func list_rows() -> Array[String]:
	var out: Array[String] = []
	if _list == null:
		return out
	for index in _list.item_count:
		out.append(_list.get_item_text(index))
	return out


func shown_count() -> int:
	return _shown_names.size()


func search_field() -> LineEdit:
	return _search


func layers_list() -> ItemList:
	return _list


func status_text() -> String:
	return _status.text if _status != null else ""


## The layer the list has under the cursor, or an empty name when there is none.
func selected_layer() -> StringName:
	if _list == null:
		return &""
	var picked: PackedInt32Array = _list.get_selected_items()
	if picked.is_empty():
		return &""
	var row: int = picked[0]
	if row < 0 or row >= _shown_names.size():
		return &""
	return _shown_names[row]


## Choose a layer by name, wherever the search has left it.
func select_layer(layer_name: StringName) -> bool:
	var row: int = _shown_names.find(layer_name)
	if row < 0:
		return false
	_list.select(row)
	_on_layer_selected(row)
	return true


# --- what it does -------------------------------------------------------------------------------


## Lock or unlock the chosen layer. Returns whether it is locked now.
func toggle_lock() -> bool:
	var layer_name := selected_layer()
	if layer_name == &"":
		return false
	var locked: bool = dialog.toggle_layer_lock(layer_name)
	_rebuild_list()
	select_layer(layer_name)
	say("Locked %s." % layer_name if locked else "Unlocked %s." % layer_name)
	layers_changed.emit()
	return locked


## Make the chosen layer the one new shapes are drawn on.
func make_current() -> bool:
	var layer_name := selected_layer()
	if layer_name == &"":
		return false
	dialog.set_layer_current(layer_name)
	_rebuild_list()
	select_layer(layer_name)
	say("%s is now the layer new shapes are drawn on." % layer_name)
	layers_changed.emit()
	return true


func say(words: String) -> void:
	if _status != null:
		_status.text = words


func _on_search_changed(words: String) -> void:
	if dialog != null:
		dialog.set_search_text(words)
	_rebuild_list()


func _on_layer_selected(index: int) -> void:
	if index < 0 or index >= _shown_names.size():
		return
	var layer := _layer_record(_shown_names[index])
	if layer.is_empty():
		say("")
		return
	_lock_button.text = "Unlock" if bool(layer["is_locked"]) else "Lock"
	say(_describe(layer))


func _on_lock_pressed() -> void:
	toggle_lock()


func _on_current_pressed() -> void:
	make_current()


func _on_close_requested() -> void:
	hide()
	closed.emit()


# --- reading the drawing ------------------------------------------------------------------------


func _rebuild_list() -> void:
	if _list == null or dialog == null:
		return
	var keep: StringName = selected_layer()
	_list.clear()
	_shown_names.clear()
	for layer: Dictionary in dialog._filtered_layers:
		_shown_names.append(StringName(layer["name"]))
		_list.add_item(_row_text(layer))
		_list.set_item_custom_fg_color(_list.item_count - 1, layer["colour"])
	if _shown_names.is_empty():
		_lock_button.text = "Lock"
		say(
			"No layer matches that. Clear the box for every layer."
			if String(dialog._search_text) != ""
			else "There are no layers here."
		)
		return
	var row: int = _shown_names.find(keep) if keep != &"" else -1
	if row < 0:
		row = 0
	_list.select(row)
	_on_layer_selected(row)


func _layer_record(layer_name: StringName) -> Dictionary:
	for layer: Dictionary in dialog._filtered_layers:
		if StringName(layer["name"]) == layer_name:
			return layer
	return {}


func _row_text(layer: Dictionary) -> String:
	var marks := ""
	if bool(layer["is_locked"]):
		marks += "  [locked]"
	if bool(layer["is_frozen"]):
		marks += "  [frozen]"
	return "%s%s  -  %s" % [String(layer["name"]), marks, String(layer["purpose"])]


func _describe(layer: Dictionary) -> String:
	var flags: Array[String] = []
	flags.append("locked" if bool(layer["is_locked"]) else "unlocked")
	flags.append("frozen" if bool(layer["is_frozen"]) else "visible")
	var plots := "plots" if bool(layer["plots"]) else "does not plot"
	var colour: Color = layer["colour"]
	return "%s - %s; %s mm, %s, %s, %s, %s" % [
		String(layer["name"]),
		String(layer["purpose"]),
		String.num(float(layer["weight"]), 2),
		String(layer["linetype"]),
		colour.to_html(false),
		", ".join(flags),
		plots,
	]