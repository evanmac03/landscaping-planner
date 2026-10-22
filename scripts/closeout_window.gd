class_name CloseoutWindow
extends Window
## The end of a job: the punch list, the hand-over date and the warranty (phase 12).
##
## A `Window` like the other pages, for their two reasons: it has fields to type into, and a `Window`
## owns its own input, so nothing here can take the drawing's keys. Every button is `FOCUS_NONE`; the
## typed fields are the only things allowed the keyboard.
##
## It shows what the desk says and works out nothing. Every count on the page is a count the report
## did, every line of an item is the item's own `describe()`, and the desk is read again on every
## refresh - so an item raised a moment ago is on the next list the page draws.
##
## ## The one thing this page is for
##
## A punch list is worked through in three steps, and the step an office forgets is the **check**: an
## item that has been put right and never looked at sits at the top of the list looking finished. So
## the item rows put the three acts beside each item as its own buttons, and the line above them says
## how many are waiting to be checked rather than how many are left. The warranty is the same idea one
## year later: a claim has to be **answered** before it can be done, and the answer has to give its
## reason whether it is covered or not.

const DeskScript := preload("res://scripts/biz/closeout_desk.gd")
const ItemScript := preload("res://scripts/biz/punch_item.gd")
const WarrantyScript := preload("res://scripts/biz/warranty.gd")

## Something was raised, fixed, checked, taken off, stated or answered. The HUD's menu line about the
## desk is stale.
signal closeout_changed()
## The window was closed by its own close button.
signal closed()

## Wide enough for an item row and its four buttons, and no taller than the screen.
const SIZE := Vector2i(1180, 780)

var desk: DeskScript = null

var _column: VBoxContainer = null
var _summary: Label = null
var _hint: Label = null
var _status: Label = null
var _punch_heading: Label = null
var _warranty_heading: Label = null
var _job_option: OptionButton = null
var _completed_field: LineEdit = null
var _completed_by_field: LineEdit = null
var _where_field: LineEdit = null
var _what_field: LineEdit = null
var _who_field: LineEdit = null
var _raised_by_field: LineEdit = null
var _by_field: LineEdit = null
var _why_field: LineEdit = null
var _months_field: LineEdit = null
var _starts_field: LineEdit = null
var _excludes_field: LineEdit = null
var _claim_field: LineEdit = null
var _claim_by_field: LineEdit = null
var _parts_row: HBoxContainer = null
var _items: VBoxContainer = null
var _claims: VBoxContainer = null
## The coverage boxes, keyed by the part they stand for, so what they say can be read back.
var _part_boxes: Dictionary = {}
## The jobs the picker is showing, in order: a dropdown's index is a position.
var _job_ids: Array[String] = []


func _init() -> void:
	title = "Finishing the job: the punch list and the warranty"
	min_size = SIZE
	exclusive = false
	close_requested.connect(_on_close_requested)


func _ready() -> void:
	if _column == null:
		build()


# --- building ----------------------------------------------------------------------------------


## Build the whole window by hand. Idempotent, and callable off-tree so a test can drive the same
## controls the program shows.
func build() -> void:
	if _column != null:
		return
	if desk == null:
		desk = DeskScript.new()
	_column = VBoxContainer.new()
	_column.name = "Column"
	_column.set_anchors_preset(Control.PRESET_FULL_RECT)
	_column.add_theme_constant_override("separation", 6)
	add_child(_column)

	_summary = Label.new()
	_summary.name = "Summary"
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.custom_minimum_size = Vector2(0, 22)
	_column.add_child(_summary)
	_column.add_child(_build_job_row())
	_column.add_child(_build_completion_row())
	_column.add_child(_build_check_row())
	_column.add_child(_build_item_row())

	var punch_heading := Label.new()
	punch_heading.name = "PunchHeading"
	_punch_heading = punch_heading
	_column.add_child(punch_heading)

	_items = VBoxContainer.new()
	_items.name = "Items"
	_items.add_theme_constant_override("separation", 2)
	_column.add_child(_items)

	_column.add_child(_build_terms_row())

	var warranty_heading := Label.new()
	warranty_heading.name = "WarrantyHeading"
	_warranty_heading = warranty_heading
	_column.add_child(warranty_heading)

	_column.add_child(_build_claim_row())

	_claims = VBoxContainer.new()
	_claims.name = "Claims"
	_claims.add_theme_constant_override("separation", 2)
	_column.add_child(_claims)

	_hint = Label.new()
	_hint.name = "Hint"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(0, 22)
	_column.add_child(_hint)

	_status = Label.new()
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 40)
	_column.add_child(_status)
	refresh()


## Which job the page is about. Everything below is a fact about one job.
func _build_job_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "JobRow"
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.name = "JobLabel"
	label.text = "the job"
	row.add_child(label)
	_job_option = OptionButton.new()
	_job_option.name = "JobOption"
	_job_option.custom_minimum_size = Vector2(320, 0)
	_job_option.focus_mode = Control.FOCUS_NONE
	row.add_child(_job_option)
	_why_field = _field("WhyField", "why: needed to reject or take an item off, or to move the date", 420)
	row.add_child(_why_field)
	return row


## The day the client was given the garden, and who says so. The warranty runs from it, which is why
## it is the first thing on the page after the job.
func _build_completion_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "CompletionRow"
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.name = "CompletionLabel"
	label.text = "handed over on"
	row.add_child(label)
	_completed_field = _field("CompletedField", "YYYY-MM-DD", 110)
	row.add_child(_completed_field)
	_completed_by_field = _field("CompletedByField", "who states it", 140)
	row.add_child(_completed_by_field)
	row.add_child(_act_button("State it", _on_state_completion))
	return row


## Raising an item: where it is, what is wrong, who it is with, and who says so.
func _build_item_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "NewItemRow"
	row.add_theme_constant_override("separation", 6)
	_where_field = _field("WhereField", "where: back patio, north edge", 240)
	row.add_child(_where_field)
	_what_field = _field("WhatField", "what is wrong", 280)
	row.add_child(_what_field)
	_who_field = _field("WhoField", "with (a trade, or blank for ours)", 200)
	row.add_child(_who_field)
	_raised_by_field = _field("RaisedByField", "raised by", 130)
	row.add_child(_raised_by_field)
	row.add_child(_act_button("Raise it", _on_raise))
	return row


## Stating the warranty: what it covers, how long, and from when.
func _build_terms_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "TermsRow"
	row.add_theme_constant_override("separation", 6)
	_parts_row = HBoxContainer.new()
	_parts_row.name = "PartsRow"
	_parts_row.add_theme_constant_override("separation", 4)
	for part: String in WarrantyScript.PARTS:
		var box := CheckBox.new()
		box.name = "Part" + part.replace(" ", "")
		box.text = part
		box.focus_mode = Control.FOCUS_NONE
		_parts_row.add_child(box)
		_part_boxes[part] = box
	row.add_child(_parts_row)
	_months_field = _field("MonthsField", "months", 70)
	row.add_child(_months_field)
	_starts_field = _field("StartsField", "from YYYY-MM-DD", 130)
	row.add_child(_starts_field)
	_excludes_field = _field("ExcludesField", "not covering (one sentence per ';')", 260)
	row.add_child(_excludes_field)
	row.add_child(_act_button("State the warranty", _on_state_warranty))
	return row


## Filing a claim against the warranty.
func _build_claim_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "NewClaimRow"
	row.add_theme_constant_override("separation", 6)
	_claim_field = _field("ClaimField", "what failed", 420)
	row.add_child(_claim_field)
	_claim_by_field = _field("ClaimByField", "reported by", 150)
	row.add_child(_claim_by_field)
	row.add_child(_act_button("File the claim", _on_file_claim))
	return row


func _field(field_name: String, placeholder: String, width: int) -> LineEdit:
	var edit := LineEdit.new()
	edit.name = field_name
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(width, 0)
	return edit


func _act_button(words: String, handler: Callable) -> Button:
	var button := Button.new()
	button.name = words.replace(" ", "")
	button.text = words
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(handler)
	return button


## Who is doing the checking, the rejecting, or taking an item off. It is its own field because the
## person who walks a list and the person who puts it right are usually not the same person, and a
## punch list's whole value is that both names are on it.
func _build_check_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "CheckRow"
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.name = "CheckLabel"
	label.text = "checked by"
	row.add_child(label)
	_by_field = _field("ByField", "who checks it, rejects it, or takes it off", 300)
	row.add_child(_by_field)
	return row


# --- showing what is there ---------------------------------------------------------------------


## Point the page at a desk and read it again. A null desk becomes an empty one rather than a page
## with nothing to show.
func bind(closeout_desk: DeskScript) -> void:
	if _column == null:
		build()
	desk = closeout_desk if closeout_desk != null else DeskScript.new()
	# The line about the old desk is about the old desk: pointing the page at another one starts its
	# own line again.
	if _status != null:
		_status.text = ""
	refresh()


func refresh() -> void:
	_fill_pickers()
	_fill_items()
	_fill_claims()
	_fill_part_boxes()
	if _summary != null:
		_summary.text = summary_text()
	if _punch_heading != null:
		_punch_heading.text = "one row per item, with what is waiting on it:  " + punch_text()
	if _warranty_heading != null:
		_warranty_heading.text = warranty_text()
	if _hint != null:
		_hint.text = hint_text()
	if _status != null and _status.text.is_empty():
		_set_status(opening_words())


## The line the page opens with: what to do, or why there is nothing to do yet.
func opening_words() -> String:
	if desk == null or selected_job().is_empty():
		return "No job has been started yet: an estimate that is agreed becomes a job."
	var report: Closeout = _report()
	if report != null and report.count() == 0 and report.completed_on.strip_edges().is_empty():
		return "Walk the job and put what is wrong on the list, then the desk hands each item to " \
			+ "whoever is to put it right."
	return "Put a date and a name in to say when the garden was handed over - the warranty runs from it."


## What to do next about this job, in one line: the first thing standing in the way, or the fact that
## nothing is.
func hint_text() -> String:
	if desk == null or selected_job().is_empty():
		return "Pick a job to see what is left to finish."
	var report: Closeout = _report()
	if report == null:
		return "That job is not on the desk any more."
	var problems: Array[String] = report.problems()
	if problems.is_empty():
		return "Nothing is left: the punch list is done and the garden has been handed over."
	return problems[0]


func summary_text() -> String:
	if desk == null or selected_job().is_empty():
		return "No job is picked."
	var report: Closeout = _report()
	if report == null:
		return "That job is not on the desk any more."
	return report.describe()


func punch_text() -> String:
	var report: Closeout = _report()
	return report.punch_text() if report != null else "nothing to show"


func warranty_text() -> String:
	var report: Closeout = _report()
	return report.warranty_text() if report != null else "nothing to show"


## The report for the job in hand, or null when there is no job the desk has. Everything on the page
## goes through here, so nothing on it can disagree with what the desk would answer.
func _report() -> Closeout:
	if desk == null:
		return null
	var job_id := selected_job()
	if job_id.is_empty():
		return null
	return desk.report(job_id, today())


func _fill_pickers() -> void:
	var keep := selected_job()
	_job_ids.clear()
	if _job_option != null:
		_job_option.clear()
		if desk != null and desk.job_desk != null:
			for held: Job in desk.job_desk.jobs:
				_job_ids.append(held.id)
				_job_option.add_item(desk.job_desk.job_label(held.id))
		if not keep.is_empty():
			choose_job(keep)


## The punch list: one row per item, with the acts it is ready for live and the rest dead. A dead
## button is how this program says "not from here, not yet" - the record's own state decides.
func _fill_items() -> void:
	if _items == null:
		return
	for child in _items.get_children():
		# Freed now, not queue_free'd: a deferred free leaves the old row in the tree, and anything
		# that looked one up by name would find the stale one with the same name.
		_items.remove_child(child)
		child.free()
	var report: Closeout = _report()
	if report == null:
		return
	for held: Dictionary in report.rows:
		var id := String(held.get("id", ""))
		var state := StringName(held.get("state", &""))
		var row := HBoxContainer.new()
		row.name = "Item" + id
		row.add_theme_constant_override("separation", 6)
		var words := Label.new()
		words.name = "ItemText"
		words.text = String(held.get("text", ""))
		words.custom_minimum_size = Vector2(760, 0)
		row.add_child(words)
		row.add_child(_row_button("Fix", _on_fix.bind(id), state == ItemScript.OPEN))
		row.add_child(_row_button("Accept", _on_accept.bind(id), state == ItemScript.FIXED))
		row.add_child(_row_button("Reject", _on_reject.bind(id), state == ItemScript.FIXED))
		row.add_child(
			_row_button("Takeoff", _on_withdraw.bind(id),
				state == ItemScript.OPEN or state == ItemScript.FIXED)
		)
		_items.add_child(row)


func _row_button(words: String, handler: Callable, live: bool) -> Button:
	var button := _act_button(words, handler)
	button.disabled = not live
	return button


func _fill_claims() -> void:
	if _claims == null:
		return
	for child in _claims.get_children():
		_claims.remove_child(child)
		child.free()
	var report: Closeout = _report()
	if report == null or report.warranty == null:
		return
	for held: Dictionary in report.warranty.claim_rows():
		var id := String(held.get("id", ""))
		var answered := String(held.get("state", "")) != "OPEN"
		var covered := bool(held.get("covered", false))
		var done := String(held.get("state", "")) == "DONE"
		var row := HBoxContainer.new()
		row.name = "Claim" + id
		row.add_theme_constant_override("separation", 6)
		var words := Label.new()
		words.name = "ClaimText"
		words.text = String(held.get("text", ""))
		words.custom_minimum_size = Vector2(700, 0)
		row.add_child(words)
		row.add_child(_row_button("Covered", _on_cover.bind(id), not answered))
		row.add_child(_row_button("Notcovered", _on_refuse.bind(id), not answered))
		row.add_child(_row_button("Done", _on_done.bind(id), covered and answered and not done))
		_claims.add_child(row)


## The coverage boxes show whatever term is stated, so a person correcting one can see what they are
## correcting rather than guessing at four unchecked boxes.
func _fill_part_boxes() -> void:
	var report: Closeout = _report()
	var held: Warranty = null if report == null else report.warranty
	for part: String in _part_boxes:
		var box: CheckBox = _part_boxes[part]
		box.button_pressed = held != null and held.covers(part)
	if held != null and _months_field != null:
		_months_field.text = str(held.months)
		_starts_field.text = held.starts_on
		_excludes_field.text = "; ".join(PackedStringArray(held.excludes))


# --- the fields, for a page or a test to fill --------------------------------------------------


func set_item_fields(place: String, wrong: String, trade: String, raiser: String) -> void:
	_where_field.text = place
	_what_field.text = wrong
	_who_field.text = trade
	_raised_by_field.text = raiser


func set_check_by(who: String) -> void:
	_by_field.text = who


func set_completion_fields(at: String, by: String) -> void:
	_completed_field.text = at
	_completed_by_field.text = by


func set_terms_fields(covered: Array, months: String, from: String, excludes: String) -> void:
	for part: String in _part_boxes:
		var box: CheckBox = _part_boxes[part]
		box.button_pressed = covered.has(part)
	_months_field.text = months
	_starts_field.text = from
	_excludes_field.text = excludes


func set_claim_fields(what: String, by: String) -> void:
	_claim_field.text = what
	_claim_by_field.text = by


func set_why(why: String) -> void:
	_why_field.text = why


## Today, as a date this program writes. Public so a test can say what the page is reading rather
## than reach for a clock of its own.
func today() -> String:
	return Time.get_date_string_from_system()


func selected_job() -> String:
	if _job_option == null or _job_ids.is_empty():
		return ""
	var index := _job_option.selected
	if index < 0 or index >= _job_ids.size():
		return ""
	return _job_ids[index]


func choose_job(job_id: String) -> bool:
	var index := _job_ids.find(job_id)
	if index < 0 or _job_option == null:
		return false
	_job_option.select(index)
	refresh()
	return true


func item_texts() -> Array[String]:
	return _texts_of(_items)


func claim_texts() -> Array[String]:
	return _texts_of(_claims)


func row_count() -> int:
	return 0 if _items == null else _items.get_child_count()


func claim_row_count() -> int:
	return 0 if _claims == null else _claims.get_child_count()


func status_text() -> String:
	return "" if _status == null else _status.text


## The row a record stands in, so a person - or a test - presses the act beside an item rather than
## the first act on the page. Each row is named for the record it stands for.
func row_for(record_id: String) -> Node:
	return _named_row(_items, "Item", record_id)


func claim_row_for(claim_id: String) -> Node:
	return _named_row(_claims, "Claim", claim_id)


func _named_row(box: VBoxContainer, prefix: String, record_id: String) -> Node:
	if box == null:
		return null
	for child in box.get_children():
		if String(child.name) == prefix + record_id:
			return child
	return null


func button_in(row: Node, words: String) -> Button:
	if row == null:
		return null
	for child in row.get_children():
		if child is Button and String(child.name) == words.replace(" ", ""):
			return child
	return null


func _texts_of(box: VBoxContainer) -> Array[String]:
	var out: Array[String] = []
	if box == null:
		return out
	for child in box.get_children():
		for grandchild in child.get_children():
			if grandchild is Label:
				out.append((grandchild as Label).text)
				break
	return out


func buttons_are_focus_free() -> bool:
	for button: Button in _all_buttons(self):
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


# --- the acts ----------------------------------------------------------------------------------


func _on_raise() -> void:
	if desk == null:
		return
	var raised: Dictionary = desk.raise_item(
		selected_job(), _where_field.text, _what_field.text, _raised_by_field.text, today(),
		_who_field.text
	)
	if not bool(raised["ok"]):
		_set_status(String(raised["reason"]))
		refresh()
		return
	_where_field.text = ""
	_what_field.text = ""
	_report_act(raised, "%s is on the list." % String(raised["id"]))


func _on_fix(item_id: String) -> void:
	if desk == null:
		return
	_report_act(desk.fix_item(item_id, today()), "%s is fixed and waiting to be checked." % item_id)


func _on_accept(item_id: String) -> void:
	if desk == null:
		return
	_report_act(
		desk.accept_item(item_id, _by_field.text, today()),
		"%s is closed: the check passed." % item_id
	)


func _on_reject(item_id: String) -> void:
	if desk == null:
		return
	_report_act(
		desk.reject_item(item_id, _by_field.text, today(), _why_field.text),
		"%s is back on the list." % item_id
	)


func _on_withdraw(item_id: String) -> void:
	if desk == null:
		return
	_report_act(
		desk.withdraw_item(item_id, _by_field.text, today(), _why_field.text),
		"%s is off the list, and the list still says so." % item_id
	)


func _on_state_completion() -> void:
	if desk == null:
		return
	var result: Dictionary = desk.state_completion(
		selected_job(), _completed_field.text, _completed_by_field.text, _why_field.text
	)
	_report_act(result, "The garden was handed over on %s." % _completed_field.text.strip_edges())


func _on_state_warranty() -> void:
	if desk == null:
		return
	var result: Dictionary = desk.state_warranty(
		selected_job(), covered_parts(), _months_field.text.to_int(), _starts_field.text,
		excluded_lines()
	)
	_report_act(result, "The warranty says: %s." % warranty_text())


func _on_file_claim() -> void:
	if desk == null:
		return
	var filed: Dictionary = desk.file_claim(
		selected_job(), today(), _claim_field.text, _claim_by_field.text
	)
	if not bool(filed["ok"]):
		_set_status(String(filed["reason"]))
		refresh()
		return
	_claim_field.text = ""
	_report_act(filed, "%s is filed against the warranty." % String(filed["id"]))


func _on_cover(claim_id: String) -> void:
	_answer(claim_id, true, "claim %s is covered." % claim_id)


func _on_refuse(claim_id: String) -> void:
	_answer(claim_id, false, "claim %s is not covered." % claim_id)


func _answer(claim_id: String, is_covered: bool, said: String) -> void:
	if desk == null:
		return
	_report_act(
		desk.answer_claim(selected_job(), claim_id, _by_field.text, today(), is_covered, _why_field.text),
		said
	)


func _on_done(claim_id: String) -> void:
	if desk == null:
		return
	_report_act(
		desk.finish_claim(selected_job(), claim_id, today(), ""),
		"claim %s has been put right." % claim_id
	)


## What the coverage boxes say, in the table's own order.
func covered_parts() -> Array[String]:
	var out: Array[String] = []
	for part: String in WarrantyScript.PARTS:
		var box: CheckBox = _part_boxes[part]
		if box.button_pressed:
			out.append(part)
	return out


## The exclusion sentences: one per ';', and the blank ones dropped, because a field a person typed
## into and changed their mind about is not a sentence.
func excluded_lines() -> Array[String]:
	var out: Array[String] = []
	for line: String in _excludes_field.text.split(";"):
		var body := line.strip_edges()
		if not body.is_empty():
			out.append(body)
	return out


## What happened, on the status line, or why it did not. A refusal is said here rather than thrown:
## it is a sentence a person acts on, and the page has nothing else to do with it.
func _report_act(result: Dictionary, said: String) -> void:
	if not bool(result.get("ok", false)):
		_set_status(String(result.get("reason", "that did not work")))
		refresh()
		return
	_set_status(said)
	refresh()
	closeout_changed.emit()


func _set_status(words: String) -> void:
	if _status != null:
		_status.text = words


func _on_close_requested() -> void:
	hide()
	closed.emit()