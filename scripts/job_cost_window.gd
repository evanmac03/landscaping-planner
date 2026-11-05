class_name JobCostWindow
extends Window
## What a job has cost: budget, committed and actual per cost code, what has been billed, and the two
## things a person does about it here (spec §8.4, REQ-B17).
##
## A `Window` like the four other pages, for the two reasons they are: it has fields to type into, and
## a `Window` owns its own input, so nothing here can take the drawing's keys (spec §9's rule). Every
## button is `FOCUS_NONE`; the typed fields are the only things allowed the keyboard.
##
## It shows what `JobDesk` says and recomputes nothing. Every figure on the page is a field of a row the
## report produced, and the report is built fresh from the records on every refresh, so a receipt
## entered a moment ago is in the next line the page draws.
##
## ## The one thing this page is for
##
## §8.4 says the flag "more committed than budget" is worth raising at the moment the purchase order is
## issued, because that is the only moment the office can still change its answer. So the ordering
## fields say **what the order would commit the job to before the button is pressed**, and what actually
## happened afterwards.

const DeskScript := preload("res://scripts/biz/job_desk.gd")
const ChangeScript := preload("res://scripts/biz/change_order.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")

## An order was issued, received, closed, or a change order was answered. The HUD's menu line about
## the desk is stale.
signal cost_changed()
## The window was closed by its own close button.
signal closed()

## Wide enough for the six columns and the order rows - measured, the six of them want 1205 px, and the
## first 1180 cut the last column off the page's own side - and no taller than the screen.
const SIZE := Vector2i(1210, 760)
## Thousandths of a unit per unit, the module's one quantity unit (§2.1).
const QUANTITY_MILLI := 1000

var desk: DeskScript = null

var _column: VBoxContainer = null
var _summary: Label = null
var _grid: GridContainer = null
var _totals: Label = null
var _problems: ItemList = null
var _orders: VBoxContainer = null
var _changes: VBoxContainer = null
var _hint: Label = null
var _status: Label = null
var _job_option: OptionButton = null
var _code_option: OptionButton = null
var _supplier_field: LineEdit = null
var _description_field: LineEdit = null
var _quantity_field: LineEdit = null
var _rate_field: LineEdit = null
var _by_field: LineEdit = null
var _how_option: OptionButton = null
var _why_field: LineEdit = null
var _order_button: Button = null
## The ids the two pickers are showing, in order: a dropdown's index is a position, and these are what
## the positions mean.
var _job_ids: Array[String] = []
var _code_ids: Array[String] = []


func _init() -> void:
	title = "What the job has cost"
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
	_column = PageChrome.column(self, 6)

	_summary = Label.new()
	_summary.name = "Summary"
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.custom_minimum_size = Vector2(0, 22)
	_column.add_child(_summary)
	_column.add_child(_build_job_row())

	var heading := Label.new()
	heading.name = "RowHeading"
	heading.text = "one row per cost code: what it was sold for, what is committed, what it has cost"
	_column.add_child(heading)

	_grid = GridContainer.new()
	_grid.name = "Rows"
	_grid.columns = 6
	_column.add_child(_grid)

	var totals_heading := Label.new()
	totals_heading.name = "TotalsHeading"
	totals_heading.text = "the breakdown, with the basis of each figure"
	_column.add_child(totals_heading)
	_totals = Label.new()
	_totals.name = "Totals"
	_totals.custom_minimum_size = Vector2(0, 150)
	_column.add_child(_totals)

	var problems_heading := Label.new()
	problems_heading.name = "ProblemsHeading"
	problems_heading.text = "what wants looking at"
	_column.add_child(problems_heading)
	_problems = ItemList.new()
	_problems.name = "Problems"
	_problems.custom_minimum_size = Vector2(0, 60)
	_problems.select_mode = ItemList.SELECT_SINGLE
	_column.add_child(_problems)

	_column.add_child(_build_order_row())
	_column.add_child(_build_change_row())

	var order_heading := Label.new()
	order_heading.name = "OrdersHeading"
	order_heading.text = "what has been ordered"
	_column.add_child(order_heading)
	_orders = VBoxContainer.new()
	_orders.name = "Orders"
	_orders.add_theme_constant_override("separation", 2)
	_column.add_child(_orders)

	var change_heading := Label.new()
	change_heading.name = "ChangesHeading"
	change_heading.text = "what the customer has been asked to agree to"
	_column.add_child(change_heading)
	_changes = VBoxContainer.new()
	_changes.name = "Changes"
	_changes.add_theme_constant_override("separation", 2)
	_column.add_child(_changes)

	_status = Label.new()
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 40)
	_column.add_child(_status)
	refresh()


## Which job the page is about. Everything below is a fact about one job - its budget, its orders, its
## changes - so this is the first thing on the page.
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
	return row


## Ordering something: which cost code, from whom, what, how many, at what rate.
func _build_order_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "OrderRow"
	row.add_theme_constant_override("separation", 6)
	_code_option = OptionButton.new()
	_code_option.name = "CodeOption"
	_code_option.custom_minimum_size = Vector2(180, 0)
	_code_option.focus_mode = Control.FOCUS_NONE
	row.add_child(_code_option)
	_supplier_field = _field("Supplier", "who it is ordered from", 200)
	row.add_child(_supplier_field)
	_description_field = _field("Description", "what it is", 220)
	row.add_child(_description_field)
	_quantity_field = _field("Quantity", "20", 70)
	row.add_child(_quantity_field)
	_rate_field = _field("Rate", "$10.00", 90)
	row.add_child(_rate_field)
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.custom_minimum_size = Vector2(340, 0)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_hint)
	_order_button = _act_button("Order it", _on_order)
	row.add_child(_order_button)
	return row


## Answering a change order: who agreed, and how it was recorded (REQ-B13), and why anything was
## declined or withdrawn - a decline without a reason is the entry the win/loss report cannot use.
func _build_change_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "ChangeRow"
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.name = "AgreedByLabel"
	label.text = "agreed by"
	row.add_child(label)
	_by_field = _field("AgreedBy", "who agreed", 160)
	row.add_child(_by_field)
	_how_option = OptionButton.new()
	_how_option.name = "HowOption"
	_how_option.custom_minimum_size = Vector2(200, 0)
	_how_option.focus_mode = Control.FOCUS_NONE
	for how in ChangeScript.APPROVAL_HOWS:
		_how_option.add_item(how)
	row.add_child(_how_option)
	var why_label := Label.new()
	why_label.name = "WhyLabel"
	why_label.text = "why (a decline or a withdrawal says why)"
	row.add_child(why_label)
	_why_field = _field("Why", "why", 220)
	row.add_child(_why_field)
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


func _plain_button(words: String, handler: Callable) -> Button:
	return _act_button(words, handler)


# --- showing what is there ---------------------------------------------------------------------


## Point the page at a desk and read it again. A null desk becomes an empty one rather than a page
## with nothing to show.
func bind(job_desk: DeskScript) -> void:
	if _column == null:
		build()
	desk = job_desk if job_desk != null else DeskScript.new()
	# The line about the old desk is about the old desk: pointing the page at another one starts its
	# own line again.
	if _status != null:
		_status.text = ""
	refresh()


func refresh() -> void:
	_fill_pickers()
	_fill_rows()
	_fill_orders()
	_fill_changes()
	_fill_buttons()
	if _summary != null:
		_summary.text = summary_text()
	if _totals != null:
		_totals.text = total_text()
	if _problems != null:
		_problems.clear()
		for words: String in problem_texts():
			var index: int = _problems.add_item(words)
			_problems.set_item_disabled(index, true)
	if _hint != null:
		_hint.text = order_hint()
	if _status != null and _status.text.is_empty():
		_set_status(opening_words())


## The line the page opens with: what to do, or why there is nothing to do yet.
func opening_words() -> String:
	if desk == null or desk.jobs.is_empty():
		return "No job has been started yet: an estimate that is agreed becomes a job."
	if selected_job().is_empty():
		return "Pick a job to see what it has cost."
	return "Put a quantity and a rate in and the page says what the order would commit the job to " \
		+ "before it goes out."


func _fill_pickers() -> void:
	var keep_job := selected_job()
	var keep_code := selected_code()
	_job_ids.clear()
	_code_ids.clear()
	if _job_option != null:
		_job_option.clear()
		if desk != null:
			for held in desk.jobs:
				_job_ids.append(held.id)
				_job_option.add_item(desk.job_label(held.id))
		if not keep_job.is_empty():
			choose_job(keep_job)
	if _code_option != null:
		_code_option.clear()
		var held_job: Job = desk.job(selected_job()) if desk != null else null
		if held_job != null:
			for code in held_job.phase_codes():
				_code_ids.append(code)
				_code_option.add_item(code)
		if not keep_code.is_empty():
			choose_code(keep_code)


## The table: one header row and one row per cost code the report has something to say about.
func _fill_rows() -> void:
	if _grid == null:
		return
	for child in _grid.get_children():
		# Freed now, not queue_free'd: a deferred free leaves the old label in the tree, and anything
		# that looked one up by name would find the stale one with the same name.
		_grid.remove_child(child)
		child.free()
	for words in _header_cells():
		_grid.add_child(_cell(words, true))
	for held in _row_data():
		for words in _row_cells(held):
			_grid.add_child(_cell(words, false))


func _cell(words: String, bold: bool) -> Label:
	var label := Label.new()
	label.text = words
	label.custom_minimum_size = Vector2(150, 0)
	if bold:
		label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	return label


func _header_cells() -> PackedStringArray:
	return PackedStringArray(["cost code", "budget", "committed", "actual", "variance", "% complete"])


## One row of the table as the five figures and the percent, from the report's own row.
func _row_cells(held: Dictionary) -> PackedStringArray:
	var percent := "not known"
	if bool(held["percent_known"]):
		percent = "%.1f%%" % (float(int(held["percent_ppm"])) / 10000.0)
	return PackedStringArray([
		String(held["cost_code"]),
		(held["budget"] as MoneyScript).format_with_currency(),
		(held["committed"] as MoneyScript).format_with_currency(),
		(held["actual"] as MoneyScript).format_with_currency(),
		(held["variance"] as MoneyScript).format_with_currency(),
		percent,
	])


## What the report says about one cost code, as one line. The same words the table draws, so what is
## tested is what is shown.
func row_text(code: String) -> String:
	for held in _row_data():
		if String(held["cost_code"]) == code:
			return "  ".join(_row_cells(held))
	return "%s is not on this report" % code


func row_count() -> int:
	return _row_data().size()


func _row_data() -> Array[Dictionary]:
	if desk == null:
		return []
	return desk.cost_rows(selected_job())


## One order row: what it is, and the two things that happen to an order. A draft can be issued; what
## has arrived can be closed.
func _fill_orders() -> void:
	if _orders == null:
		return
	for child in _orders.get_children():
		_orders.remove_child(child)
		child.free()
	var rows: Array[Dictionary] = [] if desk == null else desk.order_rows(selected_job())
	for held in rows:
		var row := HBoxContainer.new()
		row.name = "Order%s" % String(held["number"])
		row.add_theme_constant_override("separation", 6)
		var label := Label.new()
		label.name = "Label"
		label.text = String(held["describe"])
		label.custom_minimum_size = Vector2(820, 0)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		var order_id := String(held["id"])
		var state := String(held["state"])
		if state == "DRAFT":
			row.add_child(_plain_button("Issue it", _on_issue.bind(order_id)))
		if state != "CLOSED":
			# A closed order takes no receipts and is not a commitment: the only thing left to do with
			# it is read it.
			row.add_child(_plain_button("Receive it", _on_receive.bind(order_id)))
			if (held["received"] as MoneyScript).cents > 0:
				row.add_child(_plain_button("Close it", _on_close_order.bind(order_id)))
		_orders.add_child(row)


## One change order row: what it is worth, what state it is in, and the three answers a customer can
## give.
func _fill_changes() -> void:
	if _changes == null:
		return
	for child in _changes.get_children():
		_changes.remove_child(child)
		child.free()
	var rows: Array[Dictionary] = [] if desk == null else desk.change_rows(selected_job())
	for held in rows:
		var row := HBoxContainer.new()
		row.name = "Change%s" % String(held["number"])
		row.add_theme_constant_override("separation", 6)
		var label := Label.new()
		label.name = "Label"
		label.text = String(held["describe"])
		label.custom_minimum_size = Vector2(820, 0)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		var change_id := String(held["id"])
		if bool(held["pending"]):
			row.add_child(_plain_button("Agree to it", _on_agree.bind(change_id)))
			row.add_child(_plain_button("Decline it", _on_decline.bind(change_id)))
			row.add_child(_plain_button("Withdraw it", _on_void.bind(change_id)))
		_changes.add_child(row)


func _fill_buttons() -> void:
	if _order_button != null:
		_order_button.disabled = order_button_disabled()


# --- what the fields say -----------------------------------------------------------------------


## The order the fields describe, as the figures the desk would use.
func _order_amount() -> Dictionary:
	var quantity := parse_quantity(_quantity_field.text if _quantity_field != null else "")
	var rate: Money = MoneyScript.parse(_rate_field.text if _rate_field != null else "", _currency())
	return {"quantity_milli": quantity, "rate": rate}


func _currency() -> StringName:
	return desk.currency if desk != null else DeskScript.DEFAULT_CURRENCY


## What the order the fields describe **would** commit the job to, said before the button is pressed.
## This is the whole reason the fields are on the page at all (§8.4).
func order_hint() -> String:
	if desk == null or desk.jobs.is_empty():
		return ""
	var job_id := selected_job()
	var code := selected_code()
	if job_id.is_empty() or code.is_empty():
		return "Pick a cost code, and the page will say what the order commits the job to."
	var asked_fields := _order_amount()
	var quantity := int(asked_fields["quantity_milli"])
	var rate: Money = asked_fields["rate"]
	if quantity <= 0:
		return "A quantity of what is being ordered."
	if not rate.is_valid():
		return "A rate for it, as a price: \"1000.00\" or \"$1,000.00\"."
	var asked: Dictionary = desk.order_would_commit(job_id, StringName(code), quantity, rate)
	if bool(asked["over"]):
		return String(asked["reason"])
	return "%s has %s of its budget left." % [
		code, (asked["remaining"] as MoneyScript).format_with_currency(),
	]


func order_button_disabled() -> bool:
	if desk == null or desk.jobs.is_empty():
		return true
	if selected_job().is_empty() or selected_code().is_empty():
		return true
	if _supplier_field == null or _supplier_field.text.strip_edges().is_empty():
		return true
	if _description_field == null or _description_field.text.strip_edges().is_empty():
		return true
	var asked_fields := _order_amount()
	return int(asked_fields["quantity_milli"]) <= 0 or not (asked_fields["rate"] as Money).is_valid()


# --- the things a person does ------------------------------------------------------------------


## Order what the fields describe: the order is written and issued in one act here, because a page
## with two buttons for one intention is a page that gets one of them wrong.
##
## An order for a code the job was never sold is **left on the desk as a draft** and the reason said
## out loud: the order exists, and nothing has been charged to a phase the contract does not have.
## Returns `{ok, reason, warning}`.
func order_material() -> Dictionary:
	if desk == null or desk.jobs.is_empty():
		return {"ok": false, "reason": "there is no job to order for", "warning": ""}
	var job_id := selected_job()
	var code := selected_code()
	var supplier := _supplier_field.text.strip_edges() if _supplier_field != null else ""
	var description := _description_field.text.strip_edges() if _description_field != null else ""
	var asked_fields := _order_amount()
	var quantity := int(asked_fields["quantity_milli"])
	var rate: Money = asked_fields["rate"]
	if job_id.is_empty() or code.is_empty():
		return {"ok": false, "reason": "pick a job and a cost code first", "warning": ""}
	if supplier.is_empty():
		return {"ok": false, "reason": "a purchase order needs a supplier", "warning": ""}
	if description.is_empty():
		return {"ok": false, "reason": "there is nothing on it to order", "warning": ""}
	if quantity <= 0 or not rate.is_valid():
		return {"ok": false, "reason": "a quantity and a readable rate", "warning": ""}
	var made = desk.make_purchase_order(job_id, StringName(code), description, quantity, rate,
		supplier)
	if made == null:
		return {"ok": false, "reason": "the order could not be written", "warning": ""}
	var issued: Dictionary = desk.issue_purchase_order(made.id, _today())
	var warning := String(issued.get("warning", ""))
	if not bool(issued["ok"]):
		_set_status("%s is written but not ordered: %s" % [made.number, String(issued["reason"])])
	else:
		var words := "%s ordered: %s of %s" % [made.number, description, code]
		if not warning.is_empty():
			words += " - %s" % warning
		_set_status(words)
	_after_change()
	return {"ok": bool(issued["ok"]), "reason": String(issued["reason"]), "warning": warning}


## Issue an order that was written but not sent.
func issue_order(order_id: String) -> Dictionary:
	if desk == null:
		return {"ok": false, "reason": "there is no desk", "warning": ""}
	var issued: Dictionary = desk.issue_purchase_order(order_id, _today())
	if bool(issued["ok"]):
		var words := "%s is ordered." % order_id
		if not String(issued.get("warning", "")).is_empty():
			words += " %s" % String(issued["warning"])
		_set_status(words)
	else:
		_set_status("%s was not ordered: %s" % [order_id, String(issued["reason"])])
	_after_change()
	return issued


## What arrived, recorded as what was still outstanding.
func receive_order(order_id: String) -> Dictionary:
	if desk == null:
		return {"ok": false, "reason": "there is no desk"}
	var taken: Dictionary = desk.receive_what_was_ordered(order_id, _today())
	if bool(taken["ok"]):
		_set_status("%s: what was ordered has arrived." % order_id)
	else:
		_set_status("%s: %s" % [order_id, String(taken["reason"])])
	_after_change()
	return taken


func close_order(order_id: String) -> bool:
	if desk == null:
		return false
	var done := desk.close_order(order_id, _today(), "invoiced and reconciled")
	_set_status("%s is closed and reconciled." % order_id if done
		else "%s could not be closed: nothing has arrived on it." % order_id)
	_after_change()
	return done


## Record the customer agreeing to a change order: who agreed, when, and how it was recorded.
## Returns `{ok, reason}`.
func agree_change(change_id: String) -> Dictionary:
	if desk == null:
		return {"ok": false, "reason": "there is no desk"}
	var by := _by_field.text.strip_edges() if _by_field != null else ""
	var how := _how_option.get_item_text(_how_option.selected) if _how_option != null else "in-app"
	var agreed: Dictionary = desk.approve_change(change_id, by, _today(), how)
	if bool(agreed["ok"]):
		_set_status("%s is agreed, and the contract sum has moved." % change_id)
	else:
		_set_status("%s was not agreed: %s" % [change_id, String(agreed["reason"])])
	_after_change()
	return agreed


func decline_change(change_id: String) -> Dictionary:
	if desk == null:
		return {"ok": false, "reason": "there is no desk"}
	var by := _by_field.text.strip_edges() if _by_field != null else ""
	var why := _why_field.text.strip_edges() if _why_field != null else ""
	var refused: Dictionary = desk.decline_change(change_id, by, _today(), why)
	if bool(refused["ok"]):
		_set_status("%s was declined, and the reason is kept." % change_id)
	else:
		_set_status("%s was not declined: %s" % [change_id, String(refused["reason"])])
	_after_change()
	return refused


func void_change(change_id: String) -> Dictionary:
	if desk == null:
		return {"ok": false, "reason": "there is no desk"}
	var why := _why_field.text.strip_edges() if _why_field != null else ""
	var withdrawn: Dictionary = desk.void_change(change_id, _today(), why)
	if bool(withdrawn["ok"]):
		_set_status("%s was withdrawn." % change_id)
	else:
		_set_status("%s was not withdrawn: %s" % [change_id, String(withdrawn["reason"])])
	_after_change()
	return withdrawn


## Read the page again after something was done to it, and say that the desk's money has moved: the
## HUD's line about the desk is stale from this moment.
##
## A **button's own callback defers the action** (`_on_receive` and its neighbours), and this is why:
## refreshing rebuilds the order and change lists, which frees the very button that was pressed, and a
## `free` inside its own signal handler is "Object is locked and can't be freed". Deferring the entry
## point rather than the rebuild keeps the action itself synchronous, so what a caller reads straight
## after `receive_order` is what the action did.
func _after_change() -> void:
	refresh()
	cost_changed.emit()


# --- what it says ------------------------------------------------------------------------------


## The line the menu and the top of the page read: the job, its three figures and how far along it is.
func summary_text() -> String:
	if desk == null or selected_job().is_empty():
		return "no job chosen"
	var report = desk.cost_report(selected_job())
	if report == null:
		return "no job chosen"
	return "%s: %s" % [desk.job_label(selected_job()), report.describe()]


func total_text() -> String:
	if desk == null:
		return ""
	return desk.cost_totals_text(selected_job())


func problem_texts() -> Array[String]:
	return [] if desk == null else desk.cost_problems(selected_job())


## One line per order on the job, as the list draws them.
func order_texts() -> Array[String]:
	var out: Array[String] = []
	if desk == null:
		return out
	for held in desk.order_rows(selected_job()):
		out.append(String(held["describe"]))
	return out


func change_texts() -> Array[String]:
	var out: Array[String] = []
	if desk == null:
		return out
	for held in desk.change_rows(selected_job()):
		out.append(String(held["describe"]))
	return out


func status_text() -> String:
	return "" if _status == null else _status.text


func selected_job() -> String:
	if _job_option == null or _job_ids.is_empty():
		return ""
	var at := _job_option.selected
	if at < 0 or at >= _job_ids.size():
		return ""
	return _job_ids[at]


func selected_code() -> String:
	if _code_option == null or _code_ids.is_empty():
		return ""
	var at := _code_option.selected
	if at < 0 or at >= _code_ids.size():
		return ""
	return _code_ids[at]


func choose_job(job_id: String) -> bool:
	for at in _job_ids.size():
		if _job_ids[at] == job_id:
			_job_option.selected = at
			return true
	return false


func choose_code(code: String) -> bool:
	for at in _code_ids.size():
		if _code_ids[at] == code:
			_code_option.selected = at
			return true
	return false


func set_order_fields(supplier: String, description: String, quantity: String, rate: String) -> void:
	if _supplier_field != null:
		_supplier_field.text = supplier
	if _description_field != null:
		_description_field.text = description
	if _quantity_field != null:
		_quantity_field.text = quantity
	if _rate_field != null:
		_rate_field.text = rate
	if _hint != null:
		_hint.text = order_hint()


func set_why(why: String) -> void:
	if _why_field != null:
		_why_field.text = why


func set_approver(who: String, how: String = "") -> void:
	if _by_field != null:
		_by_field.text = who
	if _how_option != null and not how.is_empty():
		for at in _how_option.item_count:
			if _how_option.get_item_text(at) == how:
				_how_option.selected = at


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


## A quantity in thousandths of a unit from what somebody typed. Not money, so not `Money.parse`: a
## quantity may be fractional in a way a price may not.
static func parse_quantity(text: String) -> int:
	var body := text.strip_edges().replace(",", "").replace("$", "")
	if body.is_empty() or not body.is_valid_float():
		return 0
	return roundi(body.to_float() * float(QUANTITY_MILLI))


func _today() -> String:
	return Time.get_date_string_from_system()


func _set_status(words: String) -> void:
	if _status != null:
		_status.text = words


func _on_order() -> void:
	# Deferred for the same reason the lists are: ordering writes the order and issues it, and the
	# refresh that follows frees the button that was pressed.
	order_material.call_deferred()


func _on_issue(order_id: String) -> void:
	issue_order.call_deferred(order_id)


func _on_receive(order_id: String) -> void:
	receive_order.call_deferred(order_id)


func _on_close_order(order_id: String) -> void:
	close_order.call_deferred(order_id)


func _on_agree(change_id: String) -> void:
	agree_change.call_deferred(change_id)


func _on_decline(change_id: String) -> void:
	decline_change.call_deferred(change_id)


func _on_void(change_id: String) -> void:
	void_change.call_deferred(change_id)


func _on_close_requested() -> void:
	hide()
	closed.emit()