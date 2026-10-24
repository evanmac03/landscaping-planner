class_name SyncWindow
extends Window
## The sync of the local records with the office's service, on a page: what is waiting to be pushed,
## what the queue has given up on, where this device and the office disagree, and what the last run said
## (spec §11.2-§11.5).
##
## A `Window` like the other pages, for the two reasons they are: it has fields to type into (the
## service's address and token), and a `Window` owns its own input, so nothing here can take the
## drawing's keys. Every button is `FOCUS_NONE`; the settings are the only controls allowed the keyboard.
##
## It shows what `BizSync` says and decides nothing itself. A conflict is shown and never repaired on a
## guess: the two buttons settle it with the copy a person names, which is the module's own `resolve`.

const SyncScript := preload("res://scripts/biz/sync.gd")
const TransportScript := preload("res://scripts/biz/sync_transport.gd")

## The window was closed by its own close button.
signal closed()
## Something moved - a run, a settled conflict, or the service configured - so whatever reports on the
## queue is now stale.
signal sync_changed()

## Wide enough for a row of the queue and its words, and shorter than the 900-pixel screen the other
## pages are sized for once the window's own title bar is counted.
const SIZE := Vector2i(1000, 780)
## What the settings row is introduced by. A page that keeps two fields has to say what they are for.
const SETTINGS_CAPTION := "where the office's service is"

## The sync engine, the same object the store writes through. Null is allowed - a page with no engine
## says so rather than failing.
var sync: SyncScript = null

var _column: VBoxContainer = null
var _summary: Label = null
var _service_line: Label = null
var _settings_row: VBoxContainer = null
var _queue: ItemList = null
var _stranded: Label = null
var _conflicts: ItemList = null
var _our_button: Button = null
var _their_button: Button = null
var _last_run: Label = null
var _sync_button: Button = null
var _save_button: Button = null
var _status: Label = null
## The setting each field belongs to, in the order the fields were built.
var _setting_keys: Array[StringName] = []
var _setting_fields: Array[LineEdit] = []


func _init() -> void:
	title = "Sync"
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

	_service_line = Label.new()
	_service_line.name = "ServiceLine"
	_service_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_service_line.custom_minimum_size = Vector2(0, 20)
	_column.add_child(_service_line)

	_column.add_child(_heading(SETTINGS_CAPTION))
	_settings_row = VBoxContainer.new()
	_settings_row.name = "Settings"
	_settings_row.add_theme_constant_override("separation", 2)
	_column.add_child(_settings_row)

	_column.add_child(_heading("what is waiting to go out"))
	_queue = ItemList.new()
	_queue.name = "Queue"
	_queue.focus_mode = Control.FOCUS_NONE
	_queue.custom_minimum_size = Vector2(0, 120)
	_column.add_child(_queue)

	_stranded = Label.new()
	_stranded.name = "Stranded"
	_stranded.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stranded.custom_minimum_size = Vector2(0, 20)
	_column.add_child(_stranded)

	_column.add_child(_heading("where it does not agree"))
	_conflicts = ItemList.new()
	_conflicts.name = "Conflicts"
	_conflicts.focus_mode = Control.FOCUS_NONE
	_conflicts.custom_minimum_size = Vector2(0, 100)
	_conflicts.item_selected.connect(_on_conflict_selected)
	_column.add_child(_conflicts)

	var settle_row := HBoxContainer.new()
	settle_row.name = "SettleRow"
	settle_row.add_theme_constant_override("separation", 6)
	_column.add_child(settle_row)
	_our_button = Button.new()
	_our_button.name = "OurCopyButton"
	_our_button.focus_mode = Control.FOCUS_NONE
	_our_button.text = "Keep this device's copy"
	_our_button.pressed.connect(_on_our_copy)
	settle_row.add_child(_our_button)
	_their_button = Button.new()
	_their_button.name = "TheirCopyButton"
	_their_button.focus_mode = Control.FOCUS_NONE
	_their_button.text = "Keep the office's copy"
	_their_button.pressed.connect(_on_their_copy)
	settle_row.add_child(_their_button)

	_last_run = Label.new()
	_last_run.name = "LastRun"
	_last_run.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_last_run.custom_minimum_size = Vector2(0, 20)
	_column.add_child(_last_run)

	var run_row := HBoxContainer.new()
	run_row.name = "RunRow"
	run_row.add_theme_constant_override("separation", 6)
	_column.add_child(run_row)
	_sync_button = Button.new()
	_sync_button.name = "SyncButton"
	_sync_button.focus_mode = Control.FOCUS_NONE
	_sync_button.text = "Sync now"
	_sync_button.pressed.connect(_on_sync_pressed)
	run_row.add_child(_sync_button)
	_save_button = Button.new()
	_save_button.name = "SaveButton"
	_save_button.focus_mode = Control.FOCUS_NONE
	_save_button.text = "Save the service"
	_save_button.pressed.connect(_on_save_pressed)
	run_row.add_child(_save_button)
	var close_button := Button.new()
	close_button.name = "Close"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.text = "Close"
	close_button.pressed.connect(_on_close_requested)
	run_row.add_child(close_button)

	_status = Label.new()
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 44)
	_column.add_child(_status)

	refresh()


## Point the page at the sync engine, and build the settings fields for whatever service it holds.
func bind(engine: SyncScript) -> void:
	sync = engine
	if _column == null:
		return
	_build_settings()
	refresh()


# --- what it shows ------------------------------------------------------------------------------


## Read the engine again and put what it says on the page.
func refresh() -> void:
	if _summary == null:
		return
	if sync == null:
		_summary.text = "There is no sync here."
		_service_line.text = "nowhere to sync to"
		_queue.clear()
		_conflicts.clear()
		_stranded.text = ""
		_last_run.text = ""
		_update_buttons()
		return
	_summary.text = sync.summary_text()
	_service_line.text = _service_words()
	_fill_list(_queue, sync.pending_row_texts())
	_fill_list(_conflicts, sync.conflict_texts())
	var stranded_rows: Array[String] = sync.stranded_texts()
	_stranded.text = (
		"nothing has been given up on"
		if stranded_rows.is_empty()
		else "%d change(s) want a person: %s" % [stranded_rows.size(), "; ".join(stranded_rows)]
	)
	_last_run.text = sync.last_words if not sync.last_words.is_empty() else "no run yet"
	_update_buttons()


func summary_text() -> String:
	return _summary.text if _summary != null else ""


func service_text() -> String:
	return _service_line.text if _service_line != null else ""


func queue_rows() -> Array[String]:
	return _list_rows(_queue)


func conflict_rows() -> Array[String]:
	return _list_rows(_conflicts)


func stranded_text() -> String:
	return _stranded.text if _stranded != null else ""


func last_run_text() -> String:
	return _last_run.text if _last_run != null else ""


func status_text() -> String:
	return _status.text if _status != null else ""


func sync_button() -> Button:
	return _sync_button


func save_button() -> Button:
	return _save_button


## The field a setting is typed into, by the setting's own key - so a test types into the same box a
## person does.
func setting_field(key: StringName) -> LineEdit:
	var at: int = _setting_keys.find(key)
	if at < 0:
		return null
	return _setting_fields[at]


## Which conflict the list has under the cursor, or -1 when none.
func selected_conflict() -> int:
	if _conflicts == null:
		return -1
	var picked: PackedInt32Array = _conflicts.get_selected_items()
	return picked[0] if not picked.is_empty() else -1


# --- what it does -------------------------------------------------------------------------------


## Run a sync now and say what it did. `{ok, reason, ...}` is the engine's own answer.
func run_now() -> Dictionary:
	if sync == null:
		return {"ok": false, "reason": "there is no sync here"}
	var out: Dictionary = sync.run()
	refresh()
	say(_run_words(out))
	sync_changed.emit()
	return out


## Save what the settings fields hold onto the service, refusing a setting it does not have by name.
func save_settings() -> Dictionary:
	if sync == null or sync.transport == null:
		return {"ok": false, "reason": "there is no sync service here to configure"}
	var values: Dictionary = {}
	for at in _setting_keys.size():
		values[_setting_keys[at]] = _setting_fields[at].text
	var out: Dictionary = sync.transport.configure(values)
	refresh()
	say(
		"the service is saved." if bool(out.get("ok", false))
		else String(out.get("reason", "the service would not take that"))
	)
	sync_changed.emit()
	return out


## Settle the chosen conflict with the copy a person names - `BizSync.OUR_COPY` or `THEIR_COPY`.
func settle(choice: String) -> bool:
	var index: int = selected_conflict()
	if sync == null or index < 0:
		return false
	var out: Dictionary = sync.resolve(index, choice)
	refresh()
	var ok: bool = bool(out.get("ok", false))
	say(
		"the conflict is settled." if ok
		else String(out.get("reason", "that conflict could not be settled"))
	)
	sync_changed.emit()
	return ok


func say(words: String) -> void:
	if _status != null:
		_status.text = words


func _on_sync_pressed() -> void:
	run_now()


func _on_save_pressed() -> void:
	save_settings()


func _on_our_copy() -> void:
	settle(SyncScript.OUR_COPY)


func _on_their_copy() -> void:
	settle(SyncScript.THEIR_COPY)


func _on_conflict_selected(_index: int) -> void:
	_update_buttons()


func _on_close_requested() -> void:
	hide()
	closed.emit()


# --- reading the engine -------------------------------------------------------------------------


func _service_words() -> String:
	if sync == null:
		return "nowhere to sync to"
	if sync.transport == null:
		return "nowhere to sync to"
	return sync.transport.describe()


func _build_settings() -> void:
	if _settings_row == null:
		return
	for child in _settings_row.get_children():
		child.queue_free()
	_setting_keys.clear()
	_setting_fields.clear()
	if sync == null or sync.transport == null:
		return
	for setting: Dictionary in sync.transport.settings():
		var key := StringName(setting.get("key", ""))
		if key == &"":
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_settings_row.add_child(row)
		var label := Label.new()
		label.text = String(setting.get("label", String(key)))
		row.add_child(label)
		var field := LineEdit.new()
		field.name = String(key)
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.secret = bool(setting.get("secret", false))
		row.add_child(field)
		_setting_keys.append(key)
		_setting_fields.append(field)


func _update_buttons() -> void:
	if _save_button != null:
		_save_button.disabled = _setting_fields.is_empty()
	if _our_button != null:
		_our_button.disabled = selected_conflict() < 0
	if _their_button != null:
		_their_button.disabled = selected_conflict() < 0


func _fill_list(list: ItemList, rows: Array[String]) -> void:
	if list == null:
		return
	list.clear()
	for row: String in rows:
		list.add_item(row)


func _list_rows(list: ItemList) -> Array[String]:
	var out: Array[String] = []
	if list == null:
		return out
	for index in list.item_count:
		out.append(list.get_item_text(index))
	return out


func _run_words(out: Dictionary) -> String:
	if bool(out.get("ok", false)):
		return "the run finished: %s" % String(out.get("reason", "done"))
	return String(out.get("reason", "the run did not go"))


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label