class_name BillingWindow
extends Window
## What a job has been billed: the schedule it is billed by, the invoices that went out, and the money
## that came in (spec §9).
##
## A `Window` like the five other pages, for the two reasons they are: it has fields to type into, and
## a `Window` owns its own input, so nothing here can take the drawing's keys (spec §9's rule). Every
## button is `FOCUS_NONE`; the typed fields are the only things allowed the keyboard.
##
## It shows what `BillingDesk` says and recomputes nothing. Every figure on the page is a field of a row
## the desk produced, and the desk builds those from the records every time it is asked, so an invoice
## raised a moment ago is in the next line the page draws.
##
## ## What this page is for
##
## §9.3 says the whole point of the percentage arithmetic is that billing 30% and then 60% bills the
## 30% **once**. So the amount the page shows is the schedule's own answer, with the schedule's own
## reason beside it, and it is shown **before** the invoice button is pressed. The schedule rows carry a
## button only on the step a milestone schedule would bill next, because that is the only step the
## schedule can bill.

const LedgerScript := preload("res://scripts/biz/billing_desk.gd")
const JobScript := preload("res://scripts/biz/job.gd")
const BillingScript := preload("res://scripts/biz/billing.gd")
const MilestoneScript := preload("res://scripts/biz/milestone.gd")
const InvoiceScript := preload("res://scripts/biz/invoice.gd")
const PaymentScript := preload("res://scripts/biz/payment.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")
const RateScript := preload("res://scripts/biz/rate.gd")
const TaxScript := preload("res://scripts/biz/tax.gd")

## An invoice was raised or called back, a step was added or billed, or money arrived. The HUD's menu
## line about the job is stale.
signal billing_changed()
## The window was closed by its own close button.
signal closed()

## Wide enough for the schedule rows and the invoice rows, and shorter than the 900-pixel screen the
## other pages are sized for once the window's own title bar is counted.
const SIZE := Vector2i(1180, 850)
## The two bases a percent complete can be measured on, in the order the desk's own table has them.
const BASES := [BillingScript.BY_COST_INCURRED, BillingScript.BY_PHASE_COMPLETION]

var ledger: LedgerScript = null

var _column: VBoxContainer = null
var _summary: Label = null
var _schedule: VBoxContainer = null
var _amount: Label = null
var _invoices: VBoxContainer = null
var _payments: Label = null
var _problems: ItemList = null
var _status: Label = null
var _job_option: OptionButton = null
var _invoice_option: OptionButton = null
var _tax_option: OptionButton = null
var _basis_option: OptionButton = null
var _method_option: OptionButton = null
var _step_field: LineEdit = null
var _share_field: LineEdit = null
var _retainage_field: LineEdit = null
var _percent_field: LineEdit = null
var _terms_field: LineEdit = null
var _amount_field: LineEdit = null
var _reference_field: LineEdit = null
var _why_field: LineEdit = null
var _start_button: Button = null
var _raise_button: Button = null
var _payment_button: Button = null
## The ids the two pickers are showing, in order: a dropdown's index is a position, and these are what
## the positions mean.
var _job_ids: Array[String] = []
var _invoice_ids: Array[String] = []
var _tax_codes: Array[StringName] = []


func _init() -> void:
	title = "What has been billed"
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
	if ledger == null:
		ledger = LedgerScript.new()
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
	_column.add_child(_build_job_row())
	_column.add_child(_build_step_row())
	_column.add_child(_heading("the schedule, and what it bills next"))
	_schedule = VBoxContainer.new()
	_schedule.name = "Schedule"
	_schedule.add_theme_constant_override("separation", 2)
	_column.add_child(_schedule)

	_column.add_child(_build_measure_row())
	_column.add_child(_build_terms_row())

	_amount = Label.new()
	_amount.name = "AmountDue"
	_amount.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_amount.custom_minimum_size = Vector2(0, 22)
	_column.add_child(_amount)
	_column.add_child(_build_raise_row())

	_column.add_child(_heading("what has been invoiced"))
	_column.add_child(_build_invoice_row())
	_invoices = VBoxContainer.new()
	_invoices.name = "Invoices"
	_invoices.add_theme_constant_override("separation", 2)
	_column.add_child(_invoices)
	_column.add_child(_build_payment_row())

	_column.add_child(_heading("what has come in"))
	# A label and not a list: there are three payments at most on an invoice, and a scrolled list would
	# claim height on every page whether or not there is anything in it.
	_payments = Label.new()
	_payments.name = "Payments"
	_payments.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_payments.custom_minimum_size = Vector2(0, 20)
	_column.add_child(_payments)
	_column.add_child(_build_void_row())

	_column.add_child(_heading("what wants looking at"))
	_problems = ItemList.new()
	_problems.name = "Problems"
	_problems.custom_minimum_size = Vector2(0, 46)
	_problems.select_mode = ItemList.SELECT_SINGLE
	_column.add_child(_problems)

	_status = Label.new()
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 36)
	_column.add_child(_status)
	refresh()


func _heading(words: String) -> Label:
	var label := Label.new()
	label.name = "Heading%s" % str(words.hash())
	label.text = words
	return label


## Which job the page is about, and the one act that begins billing it by the method the contract
## agreed to. Everything below is a fact about one job, so this is the first thing on the page.
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
	_start_button = _act_button("Start billing it", _on_start)
	row.add_child(_start_button)
	return row


## Adding a step: what it is called and what share of the contract it bills.
func _build_step_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "StepRow"
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.name = "StepLabel"
	label.text = "a step of the schedule"
	row.add_child(label)
	_step_field = _field("StepName", "Deposit", 200)
	row.add_child(_step_field)
	_share_field = _field("StepShare", "25", 70)
	row.add_child(_share_field)
	var share_label := Label.new()
	share_label.name = "ShareLabel"
	share_label.text = "% of the contract"
	row.add_child(share_label)
	_retainage_field = _field("StepRetainage", "10", 60)
	row.add_child(_retainage_field)
	var retain_label := Label.new()
	retain_label.name = "RetainLabel"
	retain_label.text = "% withheld"
	row.add_child(retain_label)
	row.add_child(_act_button("Add the step", _on_add_step))
	return row


## The measured percent complete. Separate from the share a step is priced at, because one is what the
## office has measured and the other is what the contract says a step bills: two different claims that
## happen to both be percentages.
func _build_measure_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "MeasureRow"
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.name = "PercentLabel"
	label.text = "percent complete"
	row.add_child(label)
	_percent_field = _field("Percent", "40", 70)
	row.add_child(_percent_field)
	_basis_option = OptionButton.new()
	_basis_option.name = "BasisOption"
	_basis_option.custom_minimum_size = Vector2(220, 0)
	_basis_option.focus_mode = Control.FOCUS_NONE
	for basis in BASES:
		_basis_option.add_item(String(BillingScript.BASIS_NAMES[basis]))
	row.add_child(_basis_option)
	row.add_child(_act_button("Save the measurement", _on_measure))
	return row


## Which tax is charged on this invoice, and how long the customer has to pay it.
func _build_terms_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "TermsRow"
	row.add_theme_constant_override("separation", 6)
	var tax_label := Label.new()
	tax_label.name = "TaxLabel"
	tax_label.text = "tax"
	row.add_child(tax_label)
	_tax_option = OptionButton.new()
	_tax_option.name = "TaxOption"
	_tax_option.custom_minimum_size = Vector2(300, 0)
	_tax_option.focus_mode = Control.FOCUS_NONE
	row.add_child(_tax_option)
	var terms_label := Label.new()
	terms_label.name = "TermsLabel"
	terms_label.text = "terms, in days"
	row.add_child(terms_label)
	_terms_field = _field("Terms", "30", 70)
	row.add_child(_terms_field)
	return row


func _build_raise_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "RaiseRow"
	row.add_theme_constant_override("separation", 6)
	_raise_button = _act_button("Raise the invoice", _on_raise)
	row.add_child(_raise_button)
	var note := Label.new()
	note.name = "RaiseNote"
	note.text = "written and issued in one act, numbered above everything already taken"
	row.add_child(note)
	return row


func _build_invoice_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "InvoiceRow"
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.name = "InvoiceLabel"
	label.text = "the invoice"
	row.add_child(label)
	_invoice_option = OptionButton.new()
	_invoice_option.name = "InvoiceOption"
	_invoice_option.custom_minimum_size = Vector2(620, 0)
	_invoice_option.focus_mode = Control.FOCUS_NONE
	row.add_child(_invoice_option)
	return row


## Money arriving: how much, by what route, and whatever the bank will show.
func _build_payment_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "PaymentRow"
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.name = "PaymentLabel"
	label.text = "money received"
	row.add_child(label)
	_amount_field = _field("Payment", "$1,000.00", 130)
	row.add_child(_amount_field)
	_method_option = OptionButton.new()
	_method_option.name = "MethodOption"
	_method_option.custom_minimum_size = Vector2(170, 0)
	_method_option.focus_mode = Control.FOCUS_NONE
	for method in PaymentScript.METHODS:
		_method_option.add_item(PaymentScript.method_name(method))
	row.add_child(_method_option)
	_reference_field = _field("Reference", "chq 1041", 180)
	row.add_child(_reference_field)
	_payment_button = _act_button("Record it", _on_payment)
	row.add_child(_payment_button)
	return row


func _build_void_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "VoidRow"
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.name = "WhyLabel"
	label.text = "why (a void says why)"
	row.add_child(label)
	_why_field = _field("Why", "the address was wrong", 300)
	row.add_child(_why_field)
	row.add_child(_act_button("Print the invoice", _on_print))
	row.add_child(_act_button("Call it back", _on_void))
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


# --- showing what is there ---------------------------------------------------------------------


## Point the page at a ledger and read it again. A null ledger becomes an empty one rather than a page
## with nothing to show.
func bind(billing_ledger: LedgerScript) -> void:
	if _column == null:
		build()
	ledger = billing_ledger if billing_ledger != null else LedgerScript.new()
	# The line about the old ledger is about the old ledger: pointing the page at another one starts its
	# own line again.
	if _status != null:
		_status.text = ""
	if _terms_field != null:
		_terms_field.text = str(ledger.terms_days)
	refresh()


func refresh() -> void:
	_fill_pickers()
	_fill_tax_codes()
	_fill_schedule()
	_fill_invoices()
	_fill_payments()
	_fill_buttons()
	if _summary != null:
		_summary.text = summary_text()
	if _amount != null:
		_amount.text = amount_text()
	if _problems != null:
		_problems.clear()
		for words: String in problem_texts():
			var index: int = _problems.add_item(words)
			_problems.set_item_disabled(index, true)
	if _status != null and _status.text.is_empty():
		_set_status(opening_words())


## The line the page opens with: what to do, or why there is nothing to do yet.
func opening_words() -> String:
	if ledger == null or ledger.job_ids().is_empty():
		return "No job has been started yet: an estimate that is agreed becomes a job."
	var job_id := selected_job()
	if job_id.is_empty():
		return "Pick a job to see what it has been billed."
	if not ledger.has_billing(job_id):
		return "Start billing this job by the method the contract agreed to: " + \
			JobScript.billing_name(ledger.job_of(job_id).billing_method) + "."
	return "The page says what the job can bill before the invoice goes out."


func _fill_pickers() -> void:
	var keep_job := selected_job()
	var keep_invoice := selected_invoice()
	_job_ids.clear()
	_invoice_ids.clear()
	if _job_option != null:
		_job_option.clear()
		if ledger != null:
			for held_id in ledger.job_ids():
				_job_ids.append(held_id)
				_job_option.add_item(ledger.job_label(held_id))
		if not keep_job.is_empty():
			choose_job(keep_job)
	_fill_invoice_picker(keep_invoice)
	if _terms_field != null and ledger != null:
		_terms_field.text = str(ledger.terms_days)


func _fill_invoice_picker(keep: String) -> void:
	if _invoice_option == null:
		return
	_invoice_option.clear()
	if ledger == null:
		return
	for held in ledger.invoice_rows(selected_job()):
		_invoice_ids.append(String(held["id"]))
		_invoice_option.add_item(_invoice_label(held))
	if not keep.is_empty():
		choose_invoice(keep)


## What an invoice is called in a dropdown: its number (or its id, while it has no number), what it
## comes to and where it stands.
func _invoice_label(held: Dictionary) -> String:
	var number := String(held["number"])
	if number.strip_edges().is_empty():
		number = String(held["id"])
	return "%s  %s  %s" % [
		number,
		(held["total"] as MoneyScript).format_with_currency(),
		String(held["state_name"]),
	]


func _fill_tax_codes() -> void:
	if _tax_option == null:
		return
	var keep := selected_tax_code()
	_tax_option.clear()
	_tax_codes.clear()
	var names: Array[String] = []
	for code in TaxScript.CODES.keys():
		names.append(String(code))
	names.sort()
	var at: int = 0
	for index in names.size():
		var code := StringName(names[index])
		_tax_codes.append(code)
		_tax_option.add_item("%s    %s" % [TaxScript.describe(code), String(code)])
		if code == keep:
			at = index
	_tax_option.select(at)


## The schedule: one row per step of the job's billing schedule, with the button that bills it on the
## one step the schedule would bill next.
func _fill_schedule() -> void:
	if _schedule == null:
		return
	for child in _schedule.get_children():
		# Freed now, not queue_free'd: a deferred free leaves the old label in the tree, and anything
		# that looked one up by name would find the stale one with the same name.
		_schedule.remove_child(child)
		child.free()
	var rows: Array[Dictionary] = [] if ledger == null else ledger.milestone_rows(selected_job())
	if rows.is_empty():
		var empty := Label.new()
		empty.name = "NoSteps"
		empty.text = _no_steps_words()
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_schedule.add_child(empty)
		return
	var next_step := "" if ledger == null else ledger.billable_step(selected_job())
	for index in rows.size():
		var held: Dictionary = rows[index]
		var row := HBoxContainer.new()
		row.name = "Step%d" % index
		row.add_theme_constant_override("separation", 6)
		var label := Label.new()
		label.name = "Label"
		label.text = String(held["describe"])
		label.custom_minimum_size = Vector2(920, 0)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		var step_name := String(held["name"])
		if not next_step.is_empty() and step_name == next_step:
			row.add_child(_act_button("Bill it", _on_bill_step.bind(step_name)))
		_schedule.add_child(row)


func _no_steps_words() -> String:
	if ledger == null or selected_job().is_empty():
		return "Pick a job and the page will show the schedule it is billed by."
	var schedule: BillingScript = ledger.billing_for(selected_job())
	if schedule == null:
		return "This job is not being billed yet. Start it, and the schedule below is the method the " \
			+ "contract agreed to."
	if schedule.method != JobScript.MILESTONE:
		return "This job is billed by %s, which has no steps of its own." % schedule.method_name()
	return "A job billed by milestones with no milestones can bill nothing. Add the first step above."


## One row per invoice: what it is worth, where it stands, and the two things that happen to one.
func _fill_invoices() -> void:
	if _invoices == null:
		return
	for child in _invoices.get_children():
		_invoices.remove_child(child)
		child.free()
	var rows: Array[Dictionary] = [] if ledger == null else ledger.invoice_rows(selected_job())
	if rows.is_empty():
		var empty := Label.new()
		empty.name = "NoInvoices"
		empty.text = "Nothing has gone out for this job yet."
		_invoices.add_child(empty)
		return
	for index in rows.size():
		var held: Dictionary = rows[index]
		var row := HBoxContainer.new()
		row.name = "Invoice%d" % index
		row.add_theme_constant_override("separation", 6)
		var label := Label.new()
		label.name = "Label"
		label.text = String(held["describe"])
		label.custom_minimum_size = Vector2(920, 0)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		var invoice_id := String(held["id"])
		if not bool(held["void"]):
			row.add_child(_act_button("Print it", _on_print_this.bind(invoice_id)))
		_invoices.add_child(row)


func _fill_payments() -> void:
	if _payments == null:
		return
	var lines: Array[String] = payment_texts()
	if lines.is_empty():
		_payments.text = "no money has come in against this invoice yet"
		return
	_payments.text = "\n".join(lines)


func _fill_buttons() -> void:
	if _start_button != null:
		_start_button.disabled = start_button_disabled()
	if _raise_button != null:
		_raise_button.disabled = raise_button_disabled()
	if _payment_button != null:
		_payment_button.disabled = payment_button_disabled()


# --- what the fields say -----------------------------------------------------------------------


func selected_job() -> String:
	if _job_option == null or _job_ids.is_empty():
		return ""
	var at := _job_option.selected
	if at < 0 or at >= _job_ids.size():
		return ""
	return _job_ids[at]


func selected_invoice() -> String:
	if _invoice_option == null or _invoice_ids.is_empty():
		return ""
	var at := _invoice_option.selected
	if at < 0 or at >= _invoice_ids.size():
		return ""
	return _invoice_ids[at]


func selected_tax_code() -> StringName:
	if _tax_option == null or _tax_codes.is_empty():
		return &"NONE"
	var at := _tax_option.selected
	if at < 0 or at >= _tax_codes.size():
		return &"NONE"
	return _tax_codes[at]


func selected_basis() -> int:
	if _basis_option == null or _basis_option.selected < 0:
		return BillingScript.BY_COST_INCURRED
	return int(BASES[_basis_option.selected])


func selected_method() -> StringName:
	if _method_option == null or _method_option.selected < 0:
		return &"cheque"
	return PaymentScript.METHODS[_method_option.selected]


func choose_job(job_id: String) -> bool:
	for at in _job_ids.size():
		if _job_ids[at] == job_id:
			_job_option.selected = at
			return true
	return false


func choose_invoice(invoice_id: String) -> bool:
	for at in _invoice_ids.size():
		if _invoice_ids[at] == invoice_id:
			_invoice_option.selected = at
			return true
	return false


func choose_tax_code(code: StringName) -> bool:
	for at in _tax_codes.size():
		if _tax_codes[at] == code:
			_tax_option.selected = at
			return true
	return false


func choose_basis(basis: int) -> bool:
	for at in BASES.size():
		if int(BASES[at]) == basis:
			_basis_option.selected = at
			return true
	return false


func _currency() -> StringName:
	if ledger == null:
		return &"CAD"
	var invoice: InvoiceScript = ledger.invoice_for(selected_invoice())
	if invoice != null:
		return invoice.currency
	return ledger.currency_of(selected_job())


func start_button_disabled() -> bool:
	if ledger == null or selected_job().is_empty():
		return true
	return ledger.has_billing(selected_job())


func raise_button_disabled() -> bool:
	if ledger == null or selected_job().is_empty():
		return true
	if not ledger.has_billing(selected_job()):
		return true
	return _tax_codes.is_empty()


func payment_button_disabled() -> bool:
	if ledger == null or selected_invoice().is_empty():
		return true
	var amount: MoneyScript = MoneyScript.parse(_amount_field.text, _currency())
	return not amount.is_valid()


# --- the things a person does ------------------------------------------------------------------


## Start billing this job by the method the contract agreed to. The method is the contract's and is
## never chosen here: billing is what the customer agreed to (§9.1).
func begin_billing() -> bool:
	if ledger == null or selected_job().is_empty():
		_set_status("pick a job first")
		return false
	var schedule: BillingScript = ledger.start_billing(selected_job())
	if schedule == null:
		_set_status("%s is already being billed." % ledger.job_label(selected_job()))
		_after_change()
		return false
	_set_status("%s is billed by %s." % [ledger.job_label(selected_job()), schedule.method_name()])
	_after_change()
	return true


## Add a step priced as a share of the contract.
## Returns `{ok, reason}`.
func add_step() -> Dictionary:
	if ledger == null or selected_job().is_empty():
		return {"ok": false, "reason": "pick a job first"}
	var step_name := _step_field.text.strip_edges() if _step_field != null else ""
	var share := RateScript.parse_percent(_share_field.text if _share_field != null else "")
	if not RateScript.is_valid(share):
		var refused := {"ok": false, "reason": "a step is a share of the contract, as \"25\" or \"25%\""}
		_set_status(String(refused["reason"]))
		return refused
	# An empty retainage field is no retainage, which is the common answer; a written one that cannot
	# be read is refused rather than taken as nothing, because 1% and 100% are one keystroke apart.
	var withheld := 0
	var written := _retainage_field.text.strip_edges() if _retainage_field != null else ""
	if not written.is_empty():
		withheld = RateScript.parse_percent(written)
		if not RateScript.is_valid(withheld):
			var bad := {"ok": false, "reason": "a retainage is a percent of the step, as \"10\" or \"10%\""}
			_set_status(String(bad["reason"]))
			return bad
	var added: Dictionary = ledger.add_milestone(
		selected_job(), step_name, share, MilestoneScript.DATE, "", withheld
	)
	if bool(added["ok"]):
		var words := "'%s' is %s of the contract" % [step_name, RateScript.percent_text(share)]
		if withheld > 0:
			words += ", with %s withheld from it" % RateScript.percent_text(withheld)
		_set_status(words + ".")
	else:
		_set_status("'%s' was not added: %s" % [step_name, String(added["reason"])])
	_after_change()
	return added


## Save the measured percent complete, with the basis it was measured on.
## Returns `{ok, reason}`.
func measure() -> Dictionary:
	if ledger == null or selected_job().is_empty():
		return {"ok": false, "reason": "pick a job first"}
	var ppm := RateScript.parse_percent(_percent_field.text if _percent_field != null else "")
	var basis := selected_basis()
	if not ledger.set_percent_complete(selected_job(), ppm, basis):
		var refused := {"ok": false, "reason": "a percent somebody could have measured, and a basis to measure it on"}
		_set_status(String(refused["reason"]))
		return refused
	var schedule: BillingScript = ledger.billing_for(selected_job())
	_set_status("%s complete %s." % [RateScript.percent_text(ppm), schedule.basis_name()])
	_after_change()
	return {"ok": true, "reason": ""}


## Write what the schedule says the job can bill now, number it, and issue it. One act, because the
## model's separate draft exists for a page that shows a draft and this page does not.
## Returns `{ok, reason, invoice}`.
func raise_invoice() -> Dictionary:
	if ledger == null or selected_job().is_empty():
		return {"ok": false, "reason": "pick a job first", "invoice": null}
	_remember_terms()
	var raised: Dictionary = ledger.raise_invoice(
		selected_job(), _today(), "", "", "", selected_tax_code()
	)
	_said_raise(raised)
	_after_change()
	return raised


## Bill one named step of a milestone schedule. The step is named rather than assumed, so a step that
## has gone out is refused by name rather than quietly billing the next one.
func bill_step(step_name: String) -> Dictionary:
	if ledger == null or selected_job().is_empty():
		return {"ok": false, "reason": "pick a job first", "invoice": null}
	_remember_terms()
	var raised: Dictionary = ledger.raise_invoice(
		selected_job(), _today(), step_name, "", "", selected_tax_code()
	)
	_said_raise(raised)
	_after_change()
	return raised


func _said_raise(raised: Dictionary) -> void:
	if bool(raised["ok"]):
		var invoice: InvoiceScript = raised["invoice"]
		_set_status("%s written: %s due %s." % [
			invoice.number,
			invoice.total().format_with_currency(),
			invoice.due_at,
		])
	else:
		_set_status("nothing went out: %s" % String(raised["reason"]))


## Record money the customer sent, against the invoice the picker is showing. Applied through the
## invoice's own door, so a payment larger than the balance is refused rather than clamped (§9.4).
## Returns `{ok, reason, payment}`.
func record_payment() -> Dictionary:
	if ledger == null or selected_invoice().is_empty():
		return {"ok": false, "reason": "pick the invoice it is against", "payment": null}
	var amount: MoneyScript = MoneyScript.parse(_amount_field.text, _currency())
	var bank_reference := _reference_field.text.strip_edges() if _reference_field != null else ""
	var taken: Dictionary = ledger.record_payment(
		selected_invoice(), _today(), amount, selected_method(), bank_reference
	)
	if bool(taken["ok"]):
		_set_status("%s received." % (taken["payment"] as PaymentScript).describe())
	else:
		_set_status("nothing was recorded: %s" % String(taken["reason"]))
	_after_change()
	return taken


## Call the chosen invoice back: keep its number, say when and why, and put the billing back on the
## schedule so the step can go out again (§9.4).
## Returns `{ok, reason}`.
func void_invoice() -> Dictionary:
	if ledger == null or selected_invoice().is_empty():
		return {"ok": false, "reason": "pick the invoice to call back"}
	var why := _why_field.text.strip_edges() if _why_field != null else ""
	var called: Dictionary = ledger.void_invoice(selected_invoice(), _today(), why)
	if bool(called["ok"]):
		_set_status("%s was called back and the schedule is where it was: %s" % [
			_invoice_number_of(selected_invoice()), why,
		])
	else:
		_set_status("nothing was called back: %s" % String(called["reason"]))
	_after_change()
	return called


## Write the chosen invoice as a PDF, where the drawings and the proposals already go.
## Returns `{ok, path, reason}`.
func print_invoice() -> Dictionary:
	if ledger == null or selected_invoice().is_empty():
		return {"ok": false, "path": "", "reason": "pick the invoice to print"}
	var written: Dictionary = ledger.write_invoice(selected_invoice())
	if bool(written["ok"]):
		_set_status("%s is written to %s" % [
			_invoice_number_of(selected_invoice()), String(written["path"]),
		])
	else:
		_set_status("nothing was written: %s" % String(written["reason"]))
	return written


func _invoice_number_of(invoice_id: String) -> String:
	var invoice: InvoiceScript = ledger.invoice_for(invoice_id)
	if invoice == null:
		return invoice_id
	return invoice.number if not invoice.number.strip_edges().is_empty() else invoice.id


## Terms are a property of the business, so the field writes back to the ledger and every invoice the
## page raises uses what it says.
func _remember_terms() -> void:
	if ledger == null or _terms_field == null:
		return
	var days := _terms_field.text.strip_edges().to_int()
	if _terms_field.text.strip_edges().is_valid_int():
		ledger.terms_days = days


## Read the page again after something was done to it, and say that the money has moved: the HUD's
## line about the desk is stale from this moment.
##
## A **button's own callback defers the action** (`_on_raise` and its neighbours), and this is why:
## refreshing rebuilds the schedule and invoice rows, which frees the very button that was pressed, and
## a `free` inside its own signal handler is "Object is locked and can't be freed". Deferring the entry
## point rather than the rebuild keeps the action itself synchronous, so what a caller reads straight
## after `raise_invoice` is what the action did.
func _after_change() -> void:
	refresh()
	billing_changed.emit()


# --- what it says ------------------------------------------------------------------------------


func summary_text() -> String:
	if ledger == null or selected_job().is_empty():
		return "no job chosen"
	return ledger.summary_text(selected_job())


## What the job can bill right now, in the schedule's own words. Shown **before** the invoice button is
## pressed, which is the whole reason it is on the page (§9.3).
func amount_text() -> String:
	if ledger == null or selected_job().is_empty():
		return ""
	return ledger.amount_due_text(selected_job())


func schedule_texts() -> Array[String]:
	var out: Array[String] = []
	if ledger == null:
		return out
	for held in ledger.milestone_rows(selected_job()):
		out.append(String(held["describe"]))
	return out


func invoice_texts() -> Array[String]:
	if ledger == null:
		return []
	return ledger.invoice_texts(selected_job())


func payment_texts() -> Array[String]:
	if ledger == null:
		return []
	return ledger.payment_texts(selected_invoice())


func problem_texts() -> Array[String]:
	return [] if ledger == null else ledger.problems(selected_job())


func status_text() -> String:
	return "" if _status == null else _status.text


func set_step_fields(step_name: String, share: String, retainage: String = "") -> void:
	if _step_field != null:
		_step_field.text = step_name
	if _share_field != null:
		_share_field.text = share
	if _retainage_field != null:
		_retainage_field.text = retainage


func set_percent(percent: String, basis: int = BillingScript.BY_COST_INCURRED) -> void:
	if _percent_field != null:
		_percent_field.text = percent
	choose_basis(basis)


func set_payment(amount: String, bank_reference: String = "", method: String = "") -> void:
	if _amount_field != null:
		_amount_field.text = amount
	if _reference_field != null:
		_reference_field.text = bank_reference
	if _method_option != null and not method.is_empty():
		for at in PaymentScript.METHODS.size():
			if PaymentScript.method_name(PaymentScript.METHODS[at]) == method:
				_method_option.selected = at


func set_why(why: String) -> void:
	if _why_field != null:
		_why_field.text = why


func set_terms(days: int) -> void:
	if _terms_field != null:
		_terms_field.text = str(days)


## Whether every button on the page is focus-free. The typed fields are the only things allowed the
## keyboard (spec §9's rule), and this is what proves it.
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


func _today() -> String:
	return Time.get_date_string_from_system()


func _set_status(words: String) -> void:
	if _status != null:
		_status.text = words


func _on_start() -> void:
	begin_billing.call_deferred()


func _on_add_step() -> void:
	add_step.call_deferred()


func _on_measure() -> void:
	measure.call_deferred()


func _on_raise() -> void:
	# Deferred for the same reason the rows are: raising writes the row that is about to be rebuilt.
	raise_invoice.call_deferred()


func _on_bill_step(step_name: String) -> void:
	bill_step.call_deferred(step_name)


func _on_payment() -> void:
	record_payment.call_deferred()


func _on_void() -> void:
	void_invoice.call_deferred()


func _on_print() -> void:
	print_invoice.call_deferred()


func _on_print_this(invoice_id: String) -> void:
	choose_invoice(invoice_id)
	print_invoice.call_deferred()


func _on_close_requested() -> void:
	hide()
	closed.emit()