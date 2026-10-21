class_name PlantOrderWindow
extends Window
## The page that turns a planting list into a nursery order.
##
## ## What it is handed and what it does not own
##
## It is handed **the plan** - the dictionaries `PlantOrder.plan()` returns - and it holds nothing else
## about the planting. It reads no yard, no catalogue and no book: the HUD has all three and computes
## the plan, and a page that recomputed it would be a second answer to one question. What the page owns
## is the two things only a person knows: **which job** the plants are for, and **which nursery** they
## come from.
##
## ## Why it writes nothing itself
##
## Pressing the button announces `order_requested(job_id, supplier)` and nothing else. Writing a
## purchase order is the job desk's act, reached through the one door orders are written through - the
## same arrangement the plant library and the grading page keep - which is also what lets the whole page
## be tested with no desk, no drawing and no screen.

const OrderScript := preload("res://scripts/biz/plant_order.gd")

const SIZE := Vector2i(1080, 780)

## What the page is for, on the page, because a list of plant kinds does not explain itself.
const EXPLANATION := "What is standing in the drawing, one line per kind of plant, priced from the cost " \
	+ "book. Say which job it is for and which nursery the plants come from, and the page writes one " \
	+ "draft order per grower. Nothing is ordered until it is issued from Jobs > What the job has cost."

const NOTHING_PLANTED := "nothing is planted on this drawing yet"
const NO_JOB := "there is no job to order the plants for: an agreed estimate becomes a job"
const NO_SUPPLIER := "say which nursery these plants come from"
const NOT_ORDERABLE := "part of this cannot be priced, so no order can be written"

signal order_requested(job_id: String, supplier: String)
signal closed()

var desk: DeskScript = null

var _column: VBoxContainer = null
var _heading: Label = null
var _explanation: Label = null
var _job_option: OptionButton = null
var _supplier_field: LineEdit = null
var _lines: ItemList = null
var _summary: Label = null
var _problems: ItemList = null
var _hint: Label = null
var _order_button: Button = null
var _close_button: Button = null
var _status: Label = null

## The job ids behind the picker, in the order the option button shows them.
var _job_ids: Array[String] = []
## The plan handed in, and the signature of the rows actually on the list, so writing the same list
## again is not writing it again.
var _planned: Dictionary = {}
var _rows_signature: String = "<never written>"


func _init() -> void:
	title = "Order the plants"
	size = SIZE


# --- building it -------------------------------------------------------------------------------


func build() -> void:
	if _column != null:
		return
	_column = VBoxContainer.new()
	_column.name = "Column"
	_column.set_anchors_preset(Control.PRESET_FULL_RECT)
	_column.add_theme_constant_override("separation", 6)
	add_child(_column)

	_heading = Label.new()
	_heading.name = "Heading"
	_heading.text = "what the drawing plants, and what it costs"
	_column.add_child(_heading)

	_explanation = Label.new()
	_explanation.name = "Explanation"
	_explanation.text = EXPLANATION
	_explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_explanation.custom_minimum_size = Vector2(0, 56)
	_column.add_child(_explanation)

	_column.add_child(_build_who_row())

	var lines_heading := Label.new()
	lines_heading.name = "LinesHeading"
	lines_heading.text = "one line per kind of plant"
	_column.add_child(lines_heading)
	_lines = ItemList.new()
	_lines.name = "Lines"
	_lines.custom_minimum_size = Vector2(0, 200)
	_lines.select_mode = ItemList.SELECT_SINGLE
	_lines.focus_mode = Control.FOCUS_NONE
	_column.add_child(_lines)

	var problems_heading := Label.new()
	problems_heading.name = "ProblemsHeading"
	problems_heading.text = "what the book cannot price"
	_column.add_child(problems_heading)
	_problems = ItemList.new()
	_problems.name = "Problems"
	_problems.custom_minimum_size = Vector2(0, 70)
	_problems.select_mode = ItemList.SELECT_SINGLE
	_problems.focus_mode = Control.FOCUS_NONE
	_column.add_child(_problems)

	_summary = Label.new()
	_summary.name = "Summary"
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.custom_minimum_size = Vector2(0, 24)
	_column.add_child(_summary)

	_column.add_child(_build_action_row())

	_status = Label.new()
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 44)
	_column.add_child(_status)

	if not close_requested.is_connected(_on_close_requested):
		close_requested.connect(_on_close_requested)
	# A window holds the keyboard while it is up, which is what a window is for - but this one has one
	# field to type into and the rest of it must not take a key away from the drawing.
	rows_are_keyboard_free()
	set_plan({})
	hide()


## Who it is for and where it comes from: the one job and the one nursery, which are the two facts a
## cost book cannot carry.
func _build_who_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "WhoRow"
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
	var nursery_label := Label.new()
	nursery_label.name = "NurseryLabel"
	nursery_label.text = "the nursery"
	row.add_child(nursery_label)
	_supplier_field = LineEdit.new()
	_supplier_field.name = "Supplier"
	_supplier_field.placeholder_text = "who the plants are bought from"
	_supplier_field.custom_minimum_size = Vector2(280, 0)
	_supplier_field.text_changed.connect(_on_supplier_typed)
	row.add_child(_supplier_field)
	return row


## The button and the line saying what pressing it would write, before it is pressed.
func _build_action_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "ActionRow"
	row.add_theme_constant_override("separation", 6)
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(700, 0)
	row.add_child(_hint)
	_order_button = Button.new()
	_order_button.name = "OrderButton"
	_order_button.text = "Write the order"
	_order_button.focus_mode = Control.FOCUS_NONE
	_order_button.pressed.connect(_on_order)
	row.add_child(_order_button)
	_close_button = Button.new()
	_close_button.name = "CloseButton"
	_close_button.text = "Close"
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.pressed.connect(request_close)
	row.add_child(_close_button)
	return row


# --- what it was handed ------------------------------------------------------------------------


## Point the page at a job desk. A null desk becomes an empty one rather than a page with nothing to
## show, and the line about the old desk is about the old desk.
func bind(job_desk: DeskScript) -> void:
	if _column == null:
		build()
	desk = job_desk if job_desk != null else DeskScript.new()
	if _status != null:
		_status.text = ""
	_refresh_jobs()
	_refresh()
	say(opening_words())


## Hand the page the plan: the dictionaries `PlantOrder.plan()` returns. It reads them and keeps no
## second answer of its own.
func set_plan(planned: Dictionary) -> void:
	if _column == null:
		build()
	_planned = planned if planned != null else {}
	_rows_signature = "<never written>"
	_refresh()


func plan() -> Dictionary:
	return _planned


func line_count() -> int:
	return 0 if _lines == null else _lines.item_count


## Write the rows, unless they are the rows already there. Returns whether it wrote them, so a caller
## can prove a refresh that changed nothing changed nothing.
func show_lines(rows: Array) -> bool:
	if _lines == null:
		return false
	var signature := "|".join(PackedStringArray(rows))
	if signature == _rows_signature:
		return false
	_rows_signature = signature
	_lines.clear()
	for words: String in rows:
		_lines.add_item(words)
	return true


func line_texts() -> Array[String]:
	var out: Array[String] = []
	if _lines == null:
		return out
	for index in _lines.item_count:
		out.append(_lines.get_item_text(index))
	return out


## What the book could not price, said out loud and greyed rather than left out.
func show_problems(problems: Array) -> void:
	if _problems == null:
		return
	_problems.clear()
	for words: String in problems:
		var index: int = _problems.add_item(words)
		_problems.set_item_disabled(index, true)


func problem_texts() -> Array[String]:
	return _texts(_problems)


func problem_count() -> int:
	return 0 if _problems == null else _problems.item_count


func set_summary(words: String) -> void:
	if _summary != null:
		_summary.text = words


func summary_text() -> String:
	return "" if _summary == null else _summary.text


# --- the two facts a person knows -------------------------------------------------------------


func _refresh_jobs() -> void:
	var keep := selected_job()
	_job_ids.clear()
	if _job_option == null:
		return
	_job_option.clear()
	if desk != null:
		for held in desk.jobs:
			_job_ids.append(held.id)
			_job_option.add_item(desk.job_label(held.id))
	if not keep.is_empty():
		choose_job(keep)


func job_ids() -> Array[String]:
	return _job_ids.duplicate()


func selected_job() -> String:
	if _job_option == null or _job_option.selected < 0 or _job_option.selected >= _job_ids.size():
		return ""
	return _job_ids[_job_option.selected]


func choose_job(job_id: String) -> bool:
	if _job_option == null:
		return false
	var at: int = _job_ids.find(job_id)
	if at < 0:
		return false
	_job_option.select(at)
	_refresh()
	return true


func set_supplier(words: String) -> void:
	if _supplier_field != null:
		_supplier_field.text = words
	_refresh()


func supplier() -> String:
	return "" if _supplier_field == null else _supplier_field.text.strip_edges()


func set_supplier_silently(words: String) -> void:
	if _supplier_field != null:
		_supplier_field.text = words


func _on_supplier_typed(_typed: String) -> void:
	_refresh()


# --- what it says about itself ------------------------------------------------------------------


## The line before the button: what pressing it would write, or what is missing first.
##
## It counts the groups the same way `PlantOrder.write_orders` does, so the page cannot promise one
## order and the desk write two.
func order_hint() -> String:
	var lines: Array = _planned.get("lines", [])
	if lines.is_empty():
		return NOTHING_PLANTED
	if desk == null or desk.jobs.is_empty():
		return NO_JOB
	if int(_planned.get("unpriced", 0)) > 0:
		return NOT_ORDERABLE
	if selected_job().is_empty():
		return "pick which job the plants are for"
	var groups: Array[Dictionary] = OrderScript.by_supplier(
		lines, supplier(), _planned.get("currency", &"CAD")
	)
	if groups.size() == 1 and String(groups[0]["supplier"]).is_empty():
		return NO_SUPPLIER
	var parts: PackedStringArray = PackedStringArray()
	for group: Dictionary in groups:
		parts.append("%s (%d kind%s)" % [
			String(group["supplier"]), (group["lines"] as Array).size(),
			"" if (group["lines"] as Array).size() == 1 else "s",
		])
	return "%d draft order%s: %s" % [groups.size(), "" if groups.size() == 1 else "s", ", ".join(parts)]


func order_words() -> String:
	return "" if _order_button == null else _order_button.text


func order_enabled() -> bool:
	if _order_button == null:
		return false
	var lines: Array = _planned.get("lines", [])
	if lines.is_empty() or int(_planned.get("unpriced", 0)) > 0:
		return false
	if desk == null or desk.jobs.is_empty() or selected_job().is_empty():
		return false
	return not supplier().is_empty()


## The line the page opens with: what to do, or why there is nothing to do yet.
func opening_words() -> String:
	return order_hint()


## What the page says it last did. Readable without looking at a label.
func say(words: String) -> void:
	if _status != null:
		_status.text = words


func said() -> String:
	return status_text()


func status_text() -> String:
	return "" if _status == null else _status.text


func request_close() -> void:
	hide()
	closed.emit()


func _on_close_requested() -> void:
	request_close()


func _on_order() -> void:
	if not order_enabled():
		say(order_hint())
		return
	order_requested.emit(selected_job(), supplier())


## Re-read what the page is showing. **The status line is not touched here**: it is the line saying what
## the page last did, and a refresh that overwrote it would erase the answer to the question somebody
## just asked. The guidance line is `order_hint()`, and it is refreshed on every change.
func _refresh() -> void:
	show_lines(OrderScript.plan_rows(_planned))
	set_summary(OrderScript.summary(_planned) if not _planned.is_empty() else "")
	show_problems(_planned.get("problems", []))
	if _hint != null:
		_hint.text = order_hint()
	if _order_button != null:
		_order_button.disabled = not order_enabled()


# --- the keyboard -----------------------------------------------------------------------------


## Nothing on the page holds a key except the one field somebody types into.
func rows_are_keyboard_free() -> bool:
	var held: Array[Control] = [_job_option, _lines, _problems, _order_button, _close_button]
	for control: Control in held:
		if control != null and control.focus_mode != Control.FOCUS_NONE:
			return false
	return true


func list_is_keyboard_free() -> bool:
	return _lines == null or _lines.focus_mode == Control.FOCUS_NONE


func _texts(list: ItemList) -> Array[String]:
	var out: Array[String] = []
	if list == null:
		return out
	for index in list.item_count:
		out.append(list.get_item_text(index))
	return out


const DeskScript := preload("res://scripts/biz/job_desk.gd")