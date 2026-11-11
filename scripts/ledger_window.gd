class_name LedgerWindow
extends Window
## The outbox on a page: what has been handed to a ledger, what is still waiting, what the queue has
## given up on, and where the office's own records and the ledger's disagree (spec §9.6-§9.7).
##
## A `Window` like the six other pages, for the two reasons they are: it has fields to type into, and a
## `Window` owns its own input, so nothing here can take the drawing's keys (spec §9's rule). Every
## button is built without a keyboard of its own, like every control the shared chrome makes; the typed
## fields - and a backend's settings are typed fields - are the only things that keep one, because a
## field is where somebody types. What the *open* page does with the keyboard is decided once, by
## `PageChrome.takes_the_keyboard`.
##
## It shows what `LedgerDesk` says and decides nothing itself. Every line on the page is a field of a row
## the desk produced, and the desk builds those from the records every time it is asked, so a document
## posted a moment ago is in the next line the page draws.
##
## ## What this page is for
##
## §9.7 says the push is a **queued, retryable, idempotent action with a visible state**, and this is
## where it is visible. Three things follow from that and shape the page:
##
## - **A row carries a Post button only while the queue can still send it.** A delivered document has no
##   button because posting it again is not an action; a stranded one has no button because the queue has
##   already decided that pressing it is not what will fix it, and the page says what is wrong instead.
## - **The waiting documents are posted in one act**, which is the loop, and the page reports what it did
##   rather than only that it did something.
## - **What does not agree is shown and not fixed.** A page that repaired a disagreement would be a
##   program editing an accounting record on a guess.

const DeskScript := preload("res://scripts/biz/ledger_desk.gd")
const AdapterScript := preload("res://scripts/biz/ledger_adapter.gd")

## A document was queued, posted, or a backend was chosen or configured. The HUD's menu line is stale.
signal ledger_changed()
## The window was closed by its own close button.
signal closed()

## Wide enough for a row's own words beside its button, and shorter than the 900-pixel screen the other
## pages are sized for once the window's own title bar is counted.
const SIZE := Vector2i(1180, 850)

var desk: DeskScript = null

var _column: VBoxContainer = null
var _summary: Label = null
var _backend_option: OptionButton = null
var _backend_line: Label = null
var _settings_row: VBoxContainer = null
var _rows: VBoxContainer = null
var _disagreements: Label = null
var _problems: ItemList = null
var _status: Label = null
var _run_button: Button = null
var _save_button: Button = null
var _test_button: Button = null
## The backend names the picker is showing, in order: a dropdown's index is a position, and these are
## what the positions mean.
var _backend_names: Array[String] = []
## The setting each field belongs to, in the order the fields were built.
var _setting_keys: Array[StringName] = []
var _setting_fields: Array[LineEdit] = []


func _init() -> void:
	title = "What has been handed to a ledger"
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
	if desk == null:
		desk = DeskScript.new()
	# Longer than the screen this page is sized for: what does not fit scrolls into view rather than
	# being cut off at the foot of the page.
	_column = PageChrome.scrolling_column(self, 6)

	_summary = PageChrome.text()
	_summary.name = "Summary"
	_column.add_child(_summary)

	_column.add_child(_build_backend_row())
	_backend_line = PageChrome.text()
	_backend_line.name = "BackendLine"
	_column.add_child(_backend_line)

	_column.add_child(PageChrome.subheading("what this ledger needs told"))
	_settings_row = VBoxContainer.new()
	_settings_row.name = "Settings"
	_settings_row.add_theme_constant_override("separation", 2)
	_column.add_child(_settings_row)

	_column.add_child(_build_run_row())
	_column.add_child(PageChrome.subheading("what is in the outbox"))
	# The rows are built from the desk's own rows and rebuilt on every refresh, so a document posted a
	# moment ago is in the next line the page draws.
	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.add_theme_constant_override("separation", 2)
	_column.add_child(_rows)

	_column.add_child(PageChrome.subheading("where it does not agree"))
	_disagreements = PageChrome.text()
	_disagreements.name = "Disagreements"
	_column.add_child(_disagreements)

	_column.add_child(PageChrome.subheading("what wants looking at"))
	_problems = ItemList.new()
	_problems.name = "Problems"
	_problems.custom_minimum_size = Vector2(0, 46)
	_problems.select_mode = ItemList.SELECT_SINGLE
	_column.add_child(_problems)

	_status = PageChrome.status()
	_column.add_child(_status)
	refresh()


## Which ledger the page is about, whether it is configured, and the two acts that belong to the
## backend rather than to any one document: test it, and save its settings.
func _build_backend_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "BackendRow"
	row.add_theme_constant_override("separation", 6)
	var label := PageChrome.text("the ledger")
	label.name = "BackendLabel"
	row.add_child(label)
	_backend_option = OptionButton.new()
	_backend_option.name = "BackendOption"
	_backend_option.custom_minimum_size = Vector2(300, 0)
	_backend_option.focus_mode = Control.FOCUS_NONE
	row.add_child(_backend_option)
	_save_button = _act_button("Save its settings", _on_save_settings)
	row.add_child(_save_button)
	_test_button = _act_button("Test it", _on_test_backend)
	row.add_child(_test_button)
	return row


## The one act that belongs to the queue as a whole: send everything it still owns.
func _build_run_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "RunRow"
	row.add_theme_constant_override("separation", 6)
	_run_button = _act_button("Hand over everything waiting", _on_run)
	row.add_child(_run_button)
	return row


## A button on this page, from the shared chrome and named by the page's own rule: a caption with its
## spaces taken out, which is the name `tests/test_ledger_window.gd` holds these rows by. The chrome does
## name a button from its caption too, but it ends the name in `Button`, and these rows came first.
func _act_button(words: String, handler: Callable) -> Button:
	var button := PageChrome.button(words)
	button.name = words.replace(" ", "")
	button.pressed.connect(handler)
	return button


# --- showing what is there ----------------------------------------------------------------------


## Point the page at an outbox and read it again. A null desk becomes an empty one rather than a page
## with nothing to show.
func bind(outbox: DeskScript) -> void:
	if _column == null:
		build()
	desk = outbox if outbox != null else DeskScript.new()
	# The line about the old outbox is about the old outbox: pointing the page at another starts its own
	# line again.
	if _status != null:
		_status.text = ""
	refresh()


func refresh() -> void:
	_fill_backend_picker()
	_fill_settings()
	_fill_rows()
	_fill_buttons()
	if _summary != null:
		_summary.text = summary_text()
	if _backend_line != null:
		_backend_line.text = backend_text()
	if _disagreements != null:
		_disagreements.text = disagreement_text()
	if _problems != null:
		_problems.clear()
		for words: String in problem_texts():
			var index: int = _problems.add_item(words)
			_problems.set_item_disabled(index, true)
	if _status != null and _status.text.is_empty():
		_set_status(opening_words())
	# The rows just built carry a Post button each, and the shared show that gave this page its keyboard
	# ran when the page was *opened*, before any of them existed. So a page that is up gives the new ones
	# theirs here. Nothing is done while it is down: the show decides it then, and it decides it once.
	PageChrome.takes_the_keyboard_if_up(self)


## The line the page opens with: what to do, or why there is nothing to do yet.
func opening_words() -> String:
	if desk == null or desk.adapter_names().is_empty():
		return "No ledger is registered, so nothing can be handed to one."
	if desk.chosen_adapter() == null:
		return "Pick the ledger documents should be handed to."
	if not desk.chosen_adapter().is_configured():
		return "This ledger still needs told where it is: %s." % ", ".join(desk.chosen_adapter().problems())
	if desk.count() == 0:
		return "Nothing has been handed to a ledger yet: an invoice raised on the billing page can be."
	return "Post what is waiting, or read what the ledger made of what has gone."


func _fill_backend_picker() -> void:
	if _backend_option == null:
		return
	var keep: String = selected_backend()
	_backend_option.clear()
	_backend_names.clear()
	if desk == null:
		return
	for adapter_name: String in desk.adapter_names():
		_backend_names.append(adapter_name)
		var backend: AdapterScript = desk.adapter(adapter_name)
		var words: String = adapter_name
		if backend != null and not backend.is_configured():
			words += "  (needs configuring)"
		_backend_option.add_item(words)
	if not keep.is_empty():
		choose_backend(keep)


## One labelled field per setting the backend declares, in the order it declares them. A setting the
## backend marks secret is masked on the page - the page is a screen somebody walks past.
func _fill_settings() -> void:
	if _settings_row == null:
		return
	for child in _settings_row.get_children():
		_settings_row.remove_child(child)
		child.free()
	_setting_keys.clear()
	_setting_fields.clear()
	var backend: AdapterScript = desk.chosen_adapter() if desk != null else null
	if backend == null:
		return
	for held in backend.settings():
		var entry: Dictionary = held
		var row := HBoxContainer.new()
		row.name = "Setting%s" % String(entry["key"])
		row.add_theme_constant_override("separation", 6)
		var label := Label.new()
		label.name = "Label%s" % String(entry["key"])
		label.text = String(entry["name"])
		label.custom_minimum_size = Vector2(140, 0)
		row.add_child(label)
		var field := LineEdit.new()
		field.name = "Field%s" % String(entry["key"])
		field.custom_minimum_size = Vector2(360, 0)
		field.text = backend.setting(StringName(String(entry["key"])))
		if bool(entry.get("secret", false)):
			field.secret = true
		row.add_child(field)
		_settings_row.add_child(row)
		_setting_keys.append(StringName(String(entry["key"])))
		_setting_fields.append(field)


## One row per document in the outbox: the record's own words, and a Post button **only while the queue
## can still send it**.
func _fill_rows() -> void:
	if _rows == null:
		return
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.free()
	if desk == null:
		return
	var held: Array[Dictionary] = desk.rows()
	if held.is_empty():
		var quiet := Label.new()
		quiet.name = "NoRows"
		quiet.text = "the outbox is empty"
		_rows.add_child(quiet)
		return
	for row in held:
		var line := HBoxContainer.new()
		line.name = "Row%s" % str(String(row["key"]).hash())
		line.add_theme_constant_override("separation", 6)
		var words := Label.new()
		words.name = "Words"
		words.text = String(row["words"])
		words.custom_minimum_size = Vector2(880, 0)
		words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_child(words)
		if bool(row["retryable"]):
			var key: String = String(row["key"])
			var button := _act_button("Post", _on_post_one.bind(key))
			# Which document a row's button is about, for a page that wants to say so and for a test that
			# wants to press the right one.
			button.set_meta("key", key)
			line.add_child(button)
		_rows.add_child(line)


func _fill_buttons() -> void:
	if _run_button != null:
		_run_button.disabled = desk == null or desk.pending().is_empty()
	if _save_button != null:
		_save_button.disabled = desk == null or desk.chosen_adapter() == null \
			or desk.chosen_adapter().settings().is_empty()
	if _test_button != null:
		_test_button.disabled = desk == null or desk.chosen_adapter() == null


# --- reading back what the page is showing ------------------------------------------------------


func selected_backend() -> String:
	if _backend_option == null or _backend_option.selected < 0 \
			or _backend_option.selected >= _backend_names.size():
		return ""
	return _backend_names[_backend_option.selected]


func choose_backend(adapter_name: String) -> bool:
	if _backend_option == null:
		return false
	for at in _backend_names.size():
		if _backend_names[at] != adapter_name:
			continue
		_backend_option.selected = at
		return true
	return false


## Choose a backend on the page and on the desk at once, and read the page again. **The desk is what it
## means**; the dropdown only shows it. Everything on the page follows the backend - its settings, the
## documents queued for it - so choosing one is a change worth announcing.
func select_backend(adapter_name: String) -> bool:
	if desk == null or not desk.choose(adapter_name):
		return false
	choose_backend(adapter_name)
	_after_change()
	return true


func summary_text() -> String:
	return "" if desk == null else desk.summary_text()


func backend_text() -> String:
	if desk == null or desk.chosen_adapter() == null:
		return "no ledger is chosen"
	var backend: AdapterScript = desk.chosen_adapter()
	var parts := PackedStringArray()
	parts.append(backend.describe())
	parts.append("configured" if backend.is_configured() else "needs " + ", ".join(backend.problems()))
	var caps := PackedStringArray()
	for what in [AdapterScript.INVOICES, AdapterScript.PAYMENTS, AdapterScript.CREDITS,
			AdapterScript.IDEMPOTENCY]:
		if backend.can(what):
			caps.append(String(AdapterScript.CAPABILITY_NAMES[String(what)]))
	parts.append("can " + (", ".join(caps) if not caps.is_empty() else "nothing"))
	return "%s - %s" % ["; ".join(parts), "%d document(s) for it in the outbox" % desk.count_for(String(backend.name()))]


func row_texts() -> Array[String]:
	return [] if desk == null else desk.row_texts()


func disagreement_text() -> String:
	if desk == null:
		return ""
	var words: Array[String] = desk.reconcile_words()
	if words.is_empty():
		return "the outbox and the office's own records agree"
	return "\n".join(words)


func disagreement_texts() -> Array[String]:
	return [] if desk == null else desk.reconcile_words()


func problem_texts() -> Array[String]:
	return [] if desk == null else desk.problems()


func status_text() -> String:
	return "" if _status == null else _status.text


## Whether every button on the page is built without a keyboard of its own - which is what "the typed
## fields are the only things allowed the keyboard" meant when the HUD was the only surface here, and
## what it still means about the *building* of a page. What a page that is **shown** does with the
## keyboard is decided once, in `PageChrome.takes_the_keyboard`, so a button here is reachable with Tab
## all the same.
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


func run_button_disabled() -> bool:
	return _run_button == null or _run_button.disabled


func post_count() -> int:
	var how_many: int = 0
	if _rows == null:
		return how_many
	for row in _rows.get_children():
		for child in row.get_children():
			if child is Button:
				how_many += 1
	return how_many


func setting_keys() -> Array[StringName]:
	return _setting_keys.duplicate()


func setting_fields() -> Array[LineEdit]:
	return _setting_fields.duplicate()


## Whether the field for a setting is masked, which is what a secret gets.
func setting_is_masked(key: StringName) -> bool:
	for at in _setting_keys.size():
		if _setting_keys[at] == key:
			return _setting_fields[at].secret
	return false


func set_setting_field(key: StringName, value: String) -> void:
	for at in _setting_keys.size():
		if _setting_keys[at] == key:
			_setting_fields[at].text = value


# --- the acts -----------------------------------------------------------------------------------


## Post one document from its row. `{ok, reason, status, push}` as the desk's own.
func post_one(key: String) -> Dictionary:
	if desk == null:
		return {"ok": false, "reason": "there is no outbox on this page", "status": 0, "push": null}
	var posted: Dictionary = desk.post(key)
	_said_a_post(posted, 1)
	_after_change()
	return posted


## Hand over everything the queue still owns and say what it did. A run that sent none of them still
## says how many it tried and what stood in the way, because "the button did nothing" is not a report.
func post_all() -> Dictionary:
	if desk == null:
		return {"ok": false, "reason": "there is no outbox on this page", "tried": 0, "taken": 0}
	var run: Dictionary = desk.post_due()
	var words: String = ""
	if int(run["tried"]) == 0:
		words = "nothing was waiting to be handed over."
	elif bool(run["ok"]):
		words = "handed over %s." % _document_count(int(run["taken"]))
	else:
		words = "handed over %s, and %s did not go: %s" % [
			_document_count(int(run["taken"])), _document_count(int(run["failed"])), String(run["reason"]),
		]
	var waiting: int = int(run["waiting"])
	if waiting > 0:
		words += " %s still waiting." % _document_count(waiting)
	_set_status(words)
	_after_change()
	return run


## The backend's own test button, on the page.
func test_backend() -> Dictionary:
	if desk == null or desk.chosen_adapter() == null:
		return {"ok": false, "reason": "no ledger is chosen"}
	var tested: Dictionary = desk.chosen_adapter().self_test()
	# The backend's own words, whatever they are: a success that names what it did ("wrote and read back
	# ...") says more than "all well", and a refusal already says what is wrong.
	var words: String = String(tested["reason"]).strip_edges()
	if words.is_empty():
		words = "all well" if bool(tested["ok"]) else "it did not say why"
	_set_status("%s: %s" % [desk.chosen_adapter().describe(), words])
	return tested


## Save every setting the page is showing into the backend. A backend that refuses one - an empty
## address, a field it does not have - is reported by name rather than silently half-saved.
func save_settings() -> Dictionary:
	var backend: AdapterScript = desk.chosen_adapter() if desk != null else null
	if backend == null:
		return {"ok": false, "reason": "no ledger is chosen", "saved": 0}
	var saved: int = 0
	var refused: Array[String] = []
	for at in _setting_keys.size():
		var key: StringName = _setting_keys[at]
		var value: String = _setting_fields[at].text
		if value == backend.setting(key):
			continue
		if backend.set_setting(key, value):
			saved += 1
		else:
			# A secret is never named by its value, and a blank address is refused by the backend.
			refused.append(String(key))
	if saved > 0:
		_after_change()
	if not refused.is_empty():
		_set_status("%s would not take %s." % [backend.describe(), ", ".join(refused)])
		return {"ok": false, "reason": "refused: " + ", ".join(refused), "saved": saved}
	_set_status("%s is saved: %s" % [
		backend.describe(), "configured" if backend.is_configured() else "needs " + ", ".join(backend.problems()),
	])
	return {"ok": true, "reason": "", "saved": saved}


func _said_a_post(posted: Dictionary, how_many: int) -> void:
	if bool(posted["ok"]):
		_set_status("handed over %s." % _document_count(how_many))
		return
	_set_status("%s did not go: %s" % [_document_count(how_many), String(posted["reason"])])


static func _document_count(how_many: int) -> String:
	return "1 document" if how_many == 1 else "%d documents" % how_many


func _after_change() -> void:
	refresh()
	ledger_changed.emit()


func _set_status(words: String) -> void:
	if _status != null:
		_status.text = words


# --- the controls' own entry points -------------------------------------------------------------


func _on_post_one(key: String) -> void:
	# Deferred, because the button doing the calling is inside the row the post rebuilds, and a callback
	# that frees the node it is running on is an error.
	post_one.call_deferred(key)


func _on_run() -> void:
	post_all.call_deferred()


func _on_save_settings() -> void:
	save_settings.call_deferred()


func _on_test_backend() -> void:
	test_backend.call_deferred()


func _on_close_requested() -> void:
	hide()
	closed.emit()