extends Node
## Billing through the desk: the schedule a job is billed by, the invoices it raises, and the money
## that arrives against them (spec §9).
##
## The desk holds no arithmetic here either. What is under test is the join: that a schedule takes the
## method the contract agreed to and never changes it, that the amount due is the schedule's own answer
## with its own reason, that an invoice is written and issued from the job's contract sum, that a
## payment is applied through the invoice's door rather than clamped, and that a void puts the schedule
## back where it was so the step can be billed again.

const DeskScript := preload("res://scripts/biz/job_desk.gd")
const LedgerScript := preload("res://scripts/biz/billing_desk.gd")
const JobScript := preload("res://scripts/biz/job.gd")
const BillingScript := preload("res://scripts/biz/billing.gd")
const MilestoneScript := preload("res://scripts/biz/milestone.gd")
const InvoiceScript := preload("res://scripts/biz/invoice.gd")
const PaymentScript := preload("res://scripts/biz/payment.gd")
const EstimateScript := preload("res://scripts/biz/estimate.gd")
const LineScript := preload("res://scripts/biz/estimate_line.gd")
const ItemScript := preload("res://scripts/biz/cost_item.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")

## The one job every test bills, and the moment every invoice in these tests goes out.
const JOB := "E1"
const AT := "2026-06-20"
const DUE := "2026-07-20"


func _line(code: StringName, units_milli: int, cost_cents: int, price_cents: int) -> LineScript:
	var line: LineScript = LineScript.new()
	line.description = "something"
	line.cost_code = code
	line.kind = ItemScript.MATERIAL
	line.quantity_milli = units_milli
	line.unit = &"EACH"
	line.unit_cost = MoneyScript.of(cost_cents)
	line.unit_price = MoneyScript.of(price_cents)
	return line


## HARDSCAPE sold for $10,000.00 and PLANTING for $2,000.00, so the contract is $12,000.00 and a
## quarter of it is a round $3,000.00.
func _estimate() -> EstimateScript:
	var estimate: EstimateScript = EstimateScript.new(JOB)
	estimate.customer = {"name": "Smith, back garden"}
	estimate.lines.append(_line(&"HARDSCAPE", 10000, 70000, 100000))
	estimate.lines.append(_line(&"PLANTING", 10000, 15000, 20000))
	return estimate


func _jobs() -> DeskScript:
	var desk: DeskScript = DeskScript.new()
	assert(desk.make_job_from(_estimate()) != null, "the job is on the desk")
	return desk


func _ledger_on(jobs: DeskScript, method: int = JobScript.MILESTONE) -> LedgerScript:
	jobs.job(JOB).set_billing_method(method)
	var ledger: LedgerScript = LedgerScript.new()
	ledger.bind(jobs)
	ledger.start_billing(JOB)
	return ledger


func _ledger(method: int = JobScript.MILESTONE) -> LedgerScript:
	return _ledger_on(_jobs(), method)


## A schedule that claims the whole contract, so the desk has nothing to complain about except what a
## test is asking about.
func _full_schedule(ledger: LedgerScript) -> void:
	ledger.add_milestone(JOB, "Deposit", 250000)
	ledger.add_milestone(JOB, "Balance", 750000)


# --- starting to bill ---------------------------------------------------------------------------


func test_a_job_nobody_has_started_billing_has_no_schedule() -> void:
	var jobs := _jobs()
	var ledger: LedgerScript = LedgerScript.new()
	ledger.bind(jobs)
	assert(ledger.billing_for(JOB) == null, "no schedule is invented by being read")
	assert(ledger.has_billing(JOB) == false)
	assert(ledger.amount_due(JOB)["ok"] == false)
	assert(String(ledger.amount_due(JOB)["reason"]) == "this job is not being billed yet",
		String(ledger.amount_due(JOB)["reason"]))
	assert(ledger.amount_due(JOB)["amount"].is_valid() == false,
		"an amount nobody can work out is not a zero")


func test_starting_billing_takes_the_method_the_contract_agreed_to() -> void:
	var ledger := _ledger(JobScript.PERCENTAGE_COMPLETE)
	var schedule: BillingScript = ledger.billing_for(JOB)
	assert(schedule != null, "the schedule was started")
	assert(schedule.method == JobScript.PERCENTAGE_COMPLETE, schedule.method_name())
	assert(schedule.method_name() == "percentage complete")
	assert(schedule.job == JOB)
	assert(ledger.billing_count() == 1)


func test_one_job_has_one_schedule() -> void:
	var ledger := _ledger()
	assert(ledger.start_billing(JOB) == null, "a second schedule is two answers to what is owed")
	assert(ledger.billing_count() == 1)


func test_a_job_the_desk_does_not_have_cannot_be_billed() -> void:
	var ledger := _ledger()
	assert(ledger.start_billing("NOPE") == null)
	assert(ledger.contract_sum_of("NOPE").is_valid() == false,
		"a contract sum invented for a job nobody has would be an invoice out of nothing")
	var refused: Dictionary = ledger.raise_invoice("NOPE", AT)
	assert(refused["ok"] == false)
	assert(String(refused["reason"]) == "there is no job NOPE on the desk", String(refused["reason"]))


func test_a_job_with_no_schedule_is_refused_and_says_so() -> void:
	var jobs := _jobs()
	var ledger: LedgerScript = LedgerScript.new()
	ledger.bind(jobs)
	var refused: Dictionary = ledger.raise_invoice(JOB, AT)
	assert(refused["ok"] == false)
	assert(String(refused["reason"]).contains("nothing to bill it by"), String(refused["reason"]))


func test_the_contract_sum_is_the_jobs_own_and_not_an_invoices() -> void:
	var ledger := _ledger()
	assert(ledger.contract_sum_of(JOB).format_with_currency() == "$12,000.00",
		ledger.contract_sum_of(JOB).format_with_currency())
	assert(ledger.currency_of(JOB) == &"CAD")


func test_the_desk_says_nothing_has_been_billed_until_something_has() -> void:
	var ledger: LedgerScript = LedgerScript.new()
	assert(ledger.describe() == "nothing has been billed yet", ledger.describe())
	assert(ledger.billing_count() == 0)
	assert(ledger.invoices.is_empty())


# --- the schedule of steps ----------------------------------------------------------------------


func test_a_share_of_the_contract_is_a_step_and_the_schedule_bills_the_next_one() -> void:
	var ledger := _ledger()
	_full_schedule(ledger)
	var asked: Dictionary = ledger.amount_due(JOB)
	assert(asked["ok"] == true, String(asked["reason"]))
	assert((asked["amount"] as MoneyScript).format_with_currency() == "$3,000.00",
		(asked["amount"] as MoneyScript).format_with_currency())
	assert(String(asked["milestone"]) == "Deposit")
	assert(ledger.billable_step(JOB) == "Deposit")
	assert(ledger.amount_due_text(JOB).contains("$3,000.00"), ledger.amount_due_text(JOB))
	assert(ledger.amount_due_text(JOB).contains("Deposit"), ledger.amount_due_text(JOB))


func test_a_steps_row_reads_as_the_row_a_schedule_shows() -> void:
	var ledger := _ledger()
	ledger.add_milestone(JOB, "Deposit", 250000, MilestoneScript.DATE, "2026-06-01", 100000)
	var rows: Array[Dictionary] = ledger.milestone_rows(JOB)
	assert(rows.size() == 1, str(rows.size()))
	assert(String(rows[0]["name"]) == "Deposit")
	assert(String(rows[0]["amount_text"]) == "$3,000.00", String(rows[0]["amount_text"]))
	assert(String(rows[0]["state"]) == "pending")
	assert(String(rows[0]["trigger_name"]) == "on a date")
	assert((rows[0]["retainage"] as MoneyScript).format_with_currency() == "$300.00",
		"the retainage is a share of the step")
	assert(String(rows[0]["describe"]).contains("25% of the contract"), String(rows[0]["describe"]))


func test_a_second_step_with_one_name_is_two_answers_to_one_question() -> void:
	var ledger := _ledger()
	assert(ledger.add_milestone(JOB, "Deposit", 250000)["ok"] == true)
	var refused: Dictionary = ledger.add_milestone(JOB, "Deposit", 100000)
	assert(refused["ok"] == false)
	assert(String(refused["reason"]).contains("already a step called"), String(refused["reason"]))
	assert(ledger.milestone_rows(JOB).size() == 1)


func test_a_share_of_nothing_or_of_more_than_the_whole_is_not_a_step() -> void:
	var ledger := _ledger()
	assert(ledger.add_milestone(JOB, "Free", 0)["ok"] == false, "a step of 0% bills nothing")
	assert(ledger.add_milestone(JOB, "Everything and more", 1200000)["ok"] == false,
		"a step of 120% is a contract mis-written")
	assert(ledger.milestone_rows(JOB).is_empty())


func test_a_step_priced_as_a_flat_amount_ignores_the_contract() -> void:
	var ledger := _ledger()
	assert(ledger.add_fixed_milestone(JOB, "Permit", MoneyScript.of(25000))["ok"] == true)
	var rows: Array[Dictionary] = ledger.milestone_rows(JOB)
	assert(String(rows[0]["amount_text"]) == "$250.00", String(rows[0]["amount_text"]))
	assert(String(rows[0]["describe"]).contains("a fixed amount"), String(rows[0]["describe"]))


func test_a_flat_step_of_nothing_is_not_a_price() -> void:
	var ledger := _ledger()
	assert(ledger.add_fixed_milestone(JOB, "Free", MoneyScript.zero())["ok"] == false)
	assert(ledger.add_fixed_milestone(JOB, "Nothing", null)["ok"] == false)


func test_a_step_on_a_job_with_no_schedule_is_refused() -> void:
	var jobs := _jobs()
	var ledger: LedgerScript = LedgerScript.new()
	ledger.bind(jobs)
	assert(ledger.add_milestone(JOB, "Deposit", 250000)["ok"] == false)
	assert(ledger.set_retainage_rate(JOB, 100000) == false)
	assert(ledger.set_percent_complete(JOB, 500000, BillingScript.BY_COST_INCURRED) == false)


# --- raising an invoice -------------------------------------------------------------------------


func test_an_invoice_is_written_numbered_issued_and_points_at_the_job() -> void:
	var ledger := _ledger()
	_full_schedule(ledger)
	var raised: Dictionary = ledger.raise_invoice(JOB, AT)
	assert(raised["ok"] == true, String(raised["reason"]))
	var invoice: InvoiceScript = raised["invoice"]
	assert(invoice.number == "INV-2026-0001", invoice.number)
	assert(invoice.is_issued(), "an invoice raised here is issued, not left as a draft")
	assert(invoice.issued_at == AT)
	assert(invoice.due_at == DUE, invoice.due_at)
	assert(invoice.state() == InvoiceScript.ISSUED)
	assert(invoice.subtotal().format_with_currency() == "$3,000.00",
		invoice.subtotal().format_with_currency())
	assert(invoice.job == "Smith, back garden", "a document names the job a person knows: " + invoice.job)
	assert(ledger.job_id_of_invoice(invoice) == JOB, "and the desk still finds it by that name")
	assert(String(invoice.customer.get("name", "")) == "Smith, back garden")
	assert(String(invoice.site.get("name", "")).is_empty(),
		"the name is not said twice: the document's own reference already reads as it")
	assert(ledger.invoices.size() == 1)
	assert(ledger.invoice_for(invoice.id) == invoice)
	assert(ledger.invoice_by_number("INV-2026-0001") == invoice)


func test_the_line_says_what_the_document_is_for() -> void:
	var ledger := _ledger()
	_full_schedule(ledger)
	var invoice: InvoiceScript = ledger.raise_invoice(JOB, AT)["invoice"]
	assert(invoice.line_count() == 1)
	assert(int(invoice.line(0)["kind"]) == InvoiceScript.MILESTONE_LINE)
	assert(String(invoice.line(0)["description"]) == "'Deposit'", String(invoice.line(0)["description"]))


func test_a_fixed_job_bills_the_contract_and_the_line_says_so() -> void:
	var ledger := _ledger(JobScript.FIXED)
	var invoice: InvoiceScript = ledger.raise_invoice(JOB, AT)["invoice"]
	assert(invoice.subtotal().format_with_currency() == "$12,000.00",
		invoice.subtotal().format_with_currency())
	assert(int(invoice.line(0)["kind"]) == InvoiceScript.FIXED_LINE)
	assert(String(invoice.line(0)["description"]) == "the contract")
	var after: Dictionary = ledger.amount_due(JOB)
	assert(after["ok"] == true && (after["amount"] as MoneyScript).is_zero(),
		"the whole of the contract has been billed")


func test_a_period_job_bills_the_period_it_worked() -> void:
	var ledger := _ledger(JobScript.TIME_AND_MATERIALS)
	ledger.set_markup(JOB, 150000)
	var raised: Dictionary = ledger.raise_invoice(JOB, AT, "", "2026-06-01", "2026-06-15", &"NONE", &"",
		MoneyScript.of(100000), MoneyScript.of(50000))
	assert(raised["ok"] == true, String(raised["reason"]))
	var invoice: InvoiceScript = raised["invoice"]
	assert(invoice.subtotal().format_with_currency() == "$1,575.00",
		invoice.subtotal().format_with_currency())
	assert(int(invoice.line(0)["kind"]) == InvoiceScript.PERIOD_LINE)
	assert(String(invoice.line(0)["description"]) == "work from 2026-06-01 to 2026-06-15",
		String(invoice.line(0)["description"]))


func test_a_cost_plus_job_bills_the_cost_and_the_fee() -> void:
	var ledger := _ledger(JobScript.COST_PLUS)
	ledger.set_fee(JOB, 150000)
	var raised: Dictionary = ledger.raise_invoice(JOB, AT, "", "", "", &"NONE", &"",
		MoneyScript.of(100000))
	assert(raised["ok"] == true, String(raised["reason"]))
	assert((raised["invoice"] as InvoiceScript).subtotal().format_with_currency() == "$1,150.00",
		(raised["invoice"] as InvoiceScript).subtotal().format_with_currency())


func test_the_tax_a_page_charges_is_the_code_own() -> void:
	var ledger := _ledger()
	_full_schedule(ledger)
	var invoice: InvoiceScript = ledger.raise_invoice(JOB, AT, "", "", "", &"HST-ON")["invoice"]
	assert(invoice.subtotal().format_with_currency() == "$3,000.00")
	assert(invoice.tax().format_with_currency() == "$390.00", invoice.tax().format_with_currency())
	assert(invoice.total().format_with_currency() == "$3,390.00", invoice.total().format_with_currency())


func test_an_invoice_goes_out_on_a_date_and_not_on_a_word() -> void:
	var ledger := _ledger()
	_full_schedule(ledger)
	var refused: Dictionary = ledger.raise_invoice(JOB, "next Tuesday")
	assert(refused["ok"] == false)
	assert(String(refused["reason"]).contains("is not one"), String(refused["reason"]))
	assert(ledger.invoices.is_empty(), "nothing was written")


func test_nothing_left_to_bill_is_refused_with_the_schedules_own_reason() -> void:
	var ledger := _ledger()
	ledger.add_milestone(JOB, "Everything", 1000000)
	assert(ledger.raise_invoice(JOB, AT)["ok"] == true)
	var refused: Dictionary = ledger.raise_invoice(JOB, AT)
	assert(refused["ok"] == false)
	assert(String(refused["reason"]).contains("nothing to bill"), String(refused["reason"]))
	assert(String(refused["reason"]).contains("every step of this schedule has been billed"),
		String(refused["reason"]))
	assert(ledger.invoices.size() == 1)


func test_a_step_that_has_already_gone_out_is_refused_by_name() -> void:
	var ledger := _ledger()
	_full_schedule(ledger)
	assert(ledger.raise_invoice(JOB, AT)["ok"] == true)
	var refused: Dictionary = ledger.raise_invoice(JOB, AT, "Deposit")
	assert(refused["ok"] == false)
	assert(String(refused["reason"]).contains("'Deposit' was billed on") ||
		String(refused["reason"]).contains("nothing to bill"), String(refused["reason"]))


func test_a_step_the_schedule_does_not_have_is_refused_by_name() -> void:
	var ledger := _ledger()
	_full_schedule(ledger)
	var refused: Dictionary = ledger.raise_invoice(JOB, AT, "Final")
	assert(refused["ok"] == false)
	assert(String(refused["reason"]).contains("no step called 'Final'"), String(refused["reason"]))


# --- the percentage the whole module exists for -------------------------------------------------


func test_two_billings_at_thirty_and_sixty_percent_bill_the_thirty_once() -> void:
	var ledger := _ledger(JobScript.PERCENTAGE_COMPLETE)
	assert(ledger.set_percent_complete(JOB, 300000, BillingScript.BY_COST_INCURRED))
	var first: InvoiceScript = ledger.raise_invoice(JOB, AT)["invoice"]
	assert(first.subtotal().format_with_currency() == "$3,600.00",
		first.subtotal().format_with_currency())
	assert(ledger.set_percent_complete(JOB, 600000, BillingScript.BY_COST_INCURRED))
	var second: InvoiceScript = ledger.raise_invoice(JOB, AT)["invoice"]
	assert(second.subtotal().format_with_currency() == "$3,600.00",
		"60% of $12,000.00 less the $3,600.00 already billed")
	assert(int(second.line(0)["kind"]) == InvoiceScript.PERCENTAGE_LINE)
	assert(ledger.invoiced_total(JOB).format_with_currency() == "$7,200.00",
		ledger.invoiced_total(JOB).format_with_currency())


func test_a_percent_with_no_measurement_is_refused_and_says_so() -> void:
	var ledger := _ledger(JobScript.PERCENTAGE_COMPLETE)
	var refused: Dictionary = ledger.raise_invoice(JOB, AT)
	assert(refused["ok"] == false)
	assert(String(refused["reason"]).contains("nobody has measured"), String(refused["reason"]))


func test_a_percent_nobody_could_have_measured_is_refused() -> void:
	var ledger := _ledger(JobScript.PERCENTAGE_COMPLETE)
	assert(ledger.set_percent_complete(JOB, 0, BillingScript.BY_COST_INCURRED) == false)
	assert(ledger.set_percent_complete(JOB, 1100000, BillingScript.BY_COST_INCURRED) == false)
	assert(ledger.set_percent_complete(JOB, 500000, 7) == false, "a percent with no basis is half a claim")


func test_the_basis_travels_with_the_number() -> void:
	var ledger := _ledger(JobScript.PERCENTAGE_COMPLETE)
	assert(ledger.set_percent_complete(JOB, 500000, BillingScript.BY_PHASE_COMPLETION))
	var schedule: BillingScript = ledger.billing_for(JOB)
	assert(schedule.basis_name() == "by phase completion")
	assert(ledger.amount_due_text(JOB).contains("by phase completion"), ledger.amount_due_text(JOB))
	assert(schedule.describe().contains("50% complete by phase completion"), schedule.describe())


# --- retainage ----------------------------------------------------------------------------------


func test_retainage_is_withheld_per_step_and_ridden_on_the_invoice() -> void:
	var ledger := _ledger()
	ledger.add_milestone(JOB, "Deposit", 250000, MilestoneScript.DATE, "", 100000)
	var invoice: InvoiceScript = ledger.raise_invoice(JOB, AT)["invoice"]
	assert(invoice.retainage.format_with_currency() == "$300.00", invoice.retainage.format_with_currency())
	assert(invoice.total().format_with_currency() == "$2,700.00", invoice.total().format_with_currency())
	assert(invoice.balance().format_with_currency() == "$2,700.00")
	assert(ledger.retained_total(JOB).format_with_currency() == "$300.00",
		ledger.retained_total(JOB).format_with_currency())


func test_retainage_is_released_only_by_an_explicit_act_at_closeout() -> void:
	var ledger := _ledger()
	ledger.add_milestone(JOB, "Deposit", 250000, MilestoneScript.DATE, "", 100000)
	ledger.add_milestone(JOB, "Balance", 750000)
	ledger.raise_invoice(JOB, AT)
	assert(ledger.retained_total(JOB).format_with_currency() == "$300.00")
	assert(ledger.release_retainage(JOB, "2026-08-01").format_with_currency() == "$300.00",
		"the release hands back what was held")
	assert(ledger.retained_total(JOB).is_zero(), "and nothing is held any more")
	assert(ledger.release_retainage(JOB, "2026-08-02").is_zero(),
		"a second release releases nothing and does not restamp the date")
	var schedule: BillingScript = ledger.billing_for(JOB)
	assert(schedule.retainage_released_at == "2026-08-01", schedule.retainage_released_at)


func test_a_rate_nobody_has_is_refused_by_the_desk_too() -> void:
	var ledger := _ledger()
	assert(ledger.set_retainage_rate(JOB, 1200000) == false)
	assert(ledger.set_retainage_rate(JOB, 100000) == true)
	assert(ledger.set_markup(JOB, -1) == false)
	assert(ledger.set_fee(JOB, -1) == false)


# --- the money arriving -------------------------------------------------------------------------


func test_money_arrives_against_an_invoice_by_the_way_it_came() -> void:
	var ledger := _ledger()
	_full_schedule(ledger)
	var invoice: InvoiceScript = ledger.raise_invoice(JOB, AT)["invoice"]
	var taken: Dictionary = ledger.record_payment(invoice.id, "2026-07-01", MoneyScript.of(100000),
		&"cheque", "chq 1041")
	assert(taken["ok"] == true, String(taken["reason"]))
	var payment: PaymentScript = taken["payment"]
	assert(payment.id == "PMT-001", payment.id)
	assert(payment.invoice == invoice.id)
	assert(invoice.payment_count() == 1)
	assert(invoice.balance().format_with_currency() == "$2,000.00", invoice.balance().format_with_currency())
	assert(invoice.state() == InvoiceScript.PART_PAID)
	assert(payment.describe().contains("by cheque"), payment.describe())
	assert(ledger.payment_for(payment.id) == payment)
	assert(ledger.payment_texts(invoice.id).size() == 1)
	assert(ledger.outstanding_total(JOB).format_with_currency() == "$2,000.00")


func test_a_second_payment_settles_it() -> void:
	var ledger := _ledger()
	_full_schedule(ledger)
	var invoice: InvoiceScript = ledger.raise_invoice(JOB, AT)["invoice"]
	ledger.record_payment(invoice.id, "2026-07-01", MoneyScript.of(100000))
	var taken: Dictionary = ledger.record_payment(invoice.id, "2026-07-10", MoneyScript.of(200000), &"e-transfer")
	assert(taken["ok"] == true, String(taken["reason"]))
	assert(invoice.state() == InvoiceScript.PAID)
	assert(invoice.balance().is_zero())
	assert(ledger.collected_total(JOB).format_with_currency() == "$3,000.00",
		ledger.collected_total(JOB).format_with_currency())
	assert(ledger.outstanding_total(JOB).is_zero())


func test_a_payment_larger_than_the_balance_is_refused_rather_than_clamped() -> void:
	var ledger := _ledger()
	_full_schedule(ledger)
	var invoice: InvoiceScript = ledger.raise_invoice(JOB, AT)["invoice"]
	var refused: Dictionary = ledger.record_payment(invoice.id, "2026-07-01", MoneyScript.of(400000))
	assert(refused["ok"] == false)
	assert(String(refused["reason"]).contains("more than the"), String(refused["reason"]))
	assert(invoice.payment_count() == 0, "nothing was clamped")


func test_a_refund_is_a_credit_note_and_not_a_negative_payment() -> void:
	var ledger := _ledger()
	_full_schedule(ledger)
	var invoice: InvoiceScript = ledger.raise_invoice(JOB, AT)["invoice"]
	var refused: Dictionary = ledger.record_payment(invoice.id, "2026-07-01", MoneyScript.of(-100000))
	assert(refused["ok"] == false)
	assert(String(refused["reason"]).contains("credit note"), String(refused["reason"]))


func test_a_payment_of_nothing_or_by_no_method_is_refused() -> void:
	var ledger := _ledger()
	_full_schedule(ledger)
	var invoice: InvoiceScript = ledger.raise_invoice(JOB, AT)["invoice"]
	assert(ledger.record_payment(invoice.id, "2026-07-01", MoneyScript.zero())["ok"] == false)
	assert(ledger.record_payment(invoice.id, "2026-07-01", MoneyScript.of(10000), &"bitcoin")["ok"] == false)
	assert(ledger.record_payment(invoice.id, "", MoneyScript.of(10000))["ok"] == false,
		"a payment with no date is not a record")


func test_the_same_payment_cannot_be_applied_twice() -> void:
	var ledger := _ledger()
	_full_schedule(ledger)
	var invoice: InvoiceScript = ledger.raise_invoice(JOB, AT)["invoice"]
	var taken: Dictionary = ledger.record_payment(invoice.id, "2026-07-01", MoneyScript.of(100000))
	var again: PaymentScript = PaymentScript.new("PMT-001")
	again.invoice = invoice.id
	again.received_at = "2026-07-01"
	again.amount = MoneyScript.of(100000)
	var refused: Dictionary = ledger.apply_payment(again)
	assert(refused["ok"] == false, "a payment is already against this invoice")
	assert(invoice.payment_count() == 1)


func test_a_payment_must_name_an_invoice_the_desk_has() -> void:
	var ledger := _ledger()
	var stray: PaymentScript = PaymentScript.new("P9")
	stray.invoice = "no such invoice"
	stray.received_at = "2026-07-01"
	stray.amount = MoneyScript.of(10000)
	var refused: Dictionary = ledger.apply_payment(stray)
	assert(refused["ok"] == false)
	assert(String(refused["reason"]).contains("this desk does not have"), String(refused["reason"]))
	assert(ledger.record_payment("no such invoice", "2026-07-01", MoneyScript.of(100))["ok"] == false)


# --- calling one back ---------------------------------------------------------------------------


func test_voiding_keeps_the_number_and_takes_the_billing_off_the_schedule() -> void:
	var ledger := _ledger()
	_full_schedule(ledger)
	var invoice: InvoiceScript = ledger.raise_invoice(JOB, AT)["invoice"]
	var schedule: BillingScript = ledger.billing_for(JOB)
	assert(schedule.billed_to_date.format_with_currency() == "$3,000.00",
		schedule.billed_to_date.format_with_currency())
	var called: Dictionary = ledger.void_invoice(invoice.id, AT, "the address was wrong")
	assert(called["ok"] == true, String(called["reason"]))
	assert(invoice.is_void())
	assert(invoice.number == "INV-2026-0001", "a void keeps its number so the year stays gapless")
	assert(invoice.voided_text().contains("the address was wrong"), invoice.voided_text())
	assert(schedule.billed_to_date.is_zero(), "the billing came back off the schedule")
	assert(schedule.milestone("Deposit").is_billed() == false)
	assert(ledger.billable_step(JOB) == "Deposit", "so the step can be billed again")
	assert(ledger.next_invoice_number(AT) == "INV-2026-0002",
		"the voided number is taken and is never handed out again")
	assert(ledger.retained_total(JOB).is_zero())


func test_the_step_can_be_billed_again_after_the_document_was_called_back() -> void:
	var ledger := _ledger()
	_full_schedule(ledger)
	var first: InvoiceScript = ledger.raise_invoice(JOB, AT)["invoice"]
	ledger.void_invoice(first.id, AT, "wrong address")
	var again: Dictionary = ledger.raise_invoice(JOB, AT)
	assert(again["ok"] == true, String(again["reason"]))
	var second: InvoiceScript = again["invoice"]
	assert(second.number == "INV-2026-0002", second.number)
	assert(second.subtotal().format_with_currency() == "$3,000.00")
	assert(ledger.billing_for(JOB).billed_to_date.format_with_currency() == "$3,000.00")
	assert(ledger.problems(JOB).is_empty(), str(ledger.problems(JOB)))


func test_a_void_says_when_and_why() -> void:
	var ledger := _ledger()
	_full_schedule(ledger)
	var invoice: InvoiceScript = ledger.raise_invoice(JOB, AT)["invoice"]
	assert(ledger.void_invoice(invoice.id, AT, "")["ok"] == false, "a void with no reason says nothing")
	assert(ledger.void_invoice(invoice.id, "yesterday", "a reason")["ok"] == false,
		"and a void on a day that is not a day says nothing either")
	assert(invoice.is_void() == false, "neither of them went through")


func test_a_draft_is_not_voided_and_a_void_is_not_voided_twice() -> void:
	var ledger := _ledger()
	_full_schedule(ledger)
	var invoice: InvoiceScript = ledger.raise_invoice(JOB, AT)["invoice"]
	assert(ledger.void_invoice(invoice.id, AT, "wrong")["ok"] == true)
	var again: Dictionary = ledger.void_invoice(invoice.id, AT, "wrong again")
	assert(again["ok"] == false)
	assert(String(again["reason"]).contains("already called back"), String(again["reason"]))
	assert(ledger.void_invoice("no such invoice", AT, "wrong")["ok"] == false)


func test_a_voided_invoice_takes_no_payment() -> void:
	var ledger := _ledger()
	_full_schedule(ledger)
	var invoice: InvoiceScript = ledger.raise_invoice(JOB, AT)["invoice"]
	ledger.void_invoice(invoice.id, AT, "wrong address")
	var refused: Dictionary = ledger.record_payment(invoice.id, "2026-07-01", MoneyScript.of(100000))
	assert(refused["ok"] == false)
	assert(String(refused["reason"]).contains("was voided"), String(refused["reason"]))


func test_a_call_back_that_would_empty_the_schedule_is_refused() -> void:
	var ledger := _ledger()
	_full_schedule(ledger)
	var invoice: InvoiceScript = ledger.raise_invoice(JOB, AT)["invoice"]
	# A hand-edited schedule that has already recorded less than the document comes to: un-billing it
	# would take the record below nothing, which means the two had already disagreed.
	ledger.billing_for(JOB).billed_to_date = MoneyScript.of(100000)
	var refused: Dictionary = ledger.void_invoice(invoice.id, AT, "wrong address")
	assert(refused["ok"] == false)
	assert(String(refused["reason"]).contains("cannot be called back"), String(refused["reason"]))
	assert(invoice.is_void() == false, "and nothing was changed")


# --- numbering ----------------------------------------------------------------------------------


func test_a_number_is_a_fiscal_year_and_a_sequence_and_the_year_is_the_businesss_own() -> void:
	var ledger := _ledger()
	assert(ledger.next_invoice_number(AT) == "INV-2026-0001", ledger.next_invoice_number(AT))
	ledger.fiscal_start_month = 4
	assert(ledger.next_invoice_number("2026-03-15") == "INV-2025-0001",
		"a fiscal year that starts in April puts March in the year before")
	assert(ledger.next_invoice_number("2026-04-15") == "INV-2026-0001")


func test_terms_are_the_desks_own_and_the_due_date_comes_out_of_them() -> void:
	var ledger := _ledger(JobScript.FIXED)
	ledger.terms_days = 15
	var invoice: InvoiceScript = ledger.raise_invoice(JOB, AT)["invoice"]
	assert(invoice.terms_days == 15)
	assert(invoice.due_at == "2026-07-05", invoice.due_at)
	assert(LedgerScript.new().terms_days == LedgerScript.DEFAULT_TERMS_DAYS,
		"a desk states net 30 until somebody says otherwise")


func test_two_invoices_are_numbered_apart() -> void:
	var ledger := _ledger()
	_full_schedule(ledger)
	var first: InvoiceScript = ledger.raise_invoice(JOB, AT)["invoice"]
	var second: InvoiceScript = ledger.raise_invoice(JOB, AT)["invoice"]
	assert(first.number == "INV-2026-0001")
	assert(second.number == "INV-2026-0002", second.number)
	assert(second.subtotal().format_with_currency() == "$9,000.00",
		"the balance step is three quarters of the contract")


# --- what the desk says -------------------------------------------------------------------------


func test_the_desk_says_what_has_been_billed_and_what_is_still_owed() -> void:
	var ledger := _ledger()
	_full_schedule(ledger)
	var invoice: InvoiceScript = ledger.raise_invoice(JOB, AT)["invoice"]
	ledger.record_payment(invoice.id, "2026-07-01", MoneyScript.of(100000))
	var line: String = ledger.describe()
	assert(line.contains("1 schedule"), line)
	assert(line.contains("1 invoice"), line)
	assert(line.contains("$3,000.00 billed"), line)
	assert(line.contains("$2,000.00 outstanding"), line)


func test_the_schedule_and_the_documents_are_compared_and_a_disagreement_is_named() -> void:
	var ledger := _ledger()
	_full_schedule(ledger)
	ledger.raise_invoice(JOB, AT)
	assert(ledger.problems(JOB).is_empty(), str(ledger.problems(JOB)))
	assert(ledger.is_sound())
	ledger.billing_for(JOB).billed_to_date = MoneyScript.of(999900)
	var found: Array[String] = ledger.problems(JOB)
	assert(found.size() == 1, str(found))
	assert(found[0].contains("has been billed and its invoices come to"), found[0])
	assert(ledger.describe().contains("1 thing to look at"), ledger.describe())


func test_a_schedule_that_covers_part_of_the_contract_is_a_problem_the_desk_reports() -> void:
	var ledger := _ledger()
	ledger.add_milestone(JOB, "Deposit", 250000)
	var found: Array[String] = ledger.problems(JOB)
	assert(found.size() == 1, str(found))
	assert(found[0].contains("claimed by no step"), found[0])


func test_an_invoice_naming_a_job_the_desk_does_not_have_is_named_rather_than_dropped() -> void:
	var ledger := _ledger()
	var stray: InvoiceScript = InvoiceScript.new("i9")
	stray.job = "GONE"
	stray.currency = &"CAD"
	stray.add_amount(InvoiceScript.FIXED_LINE, "the contract", MoneyScript.of(100000))
	stray.issue(AT, 30, "INV-2026-0009")
	ledger.invoices.append(stray)
	var found: Array[String] = ledger.problems()
	assert(found.size() >= 1, str(found))
	var named := false
	for words in found:
		if words.contains("names a job this desk does not have"):
			named = true
	assert(named, str(found))
	assert(ledger.job_id_of_invoice(stray) == "")


func test_a_job_with_invoices_and_no_schedule_is_named() -> void:
	var jobs := _jobs()
	var ledger: LedgerScript = LedgerScript.new()
	ledger.bind(jobs)
	var invoice: InvoiceScript = InvoiceScript.new("i1")
	invoice.job = JOB
	invoice.currency = &"CAD"
	invoice.add_amount(InvoiceScript.FIXED_LINE, "the contract", MoneyScript.of(100000))
	invoice.issue(AT, 30, "INV-2026-0001")
	ledger.invoices.append(invoice)
	var found: Array[String] = ledger.problems(JOB)
	assert(found.size() == 1, str(found))
	assert(found[0].contains("has invoices but no billing schedule"), found[0])


func test_the_desk_summary_reads_the_schedule_and_the_contract() -> void:
	var ledger := _ledger()
	_full_schedule(ledger)
	var line: String = ledger.summary_text(JOB)
	assert(line.contains("Smith, back garden"), line)
	assert(line.contains("milestones"), line)
	assert(line.contains("100% of the contract in all"), line)
	assert(line.contains("$12,000.00"), line)
	assert(ledger.summary_text("NOPE") == "no job chosen")


# --- the page -----------------------------------------------------------------------------------


func test_the_letterhead_is_the_one_the_business_holds() -> void:
	var ledger := _ledger()
	_full_schedule(ledger)
	var invoice: InvoiceScript = ledger.raise_invoice(JOB, AT)["invoice"]
	ledger.company.append("Greenline Landscapes")
	ledger.company.append("12 Mill Road")
	ledger.contact.append("HST 12345 6789")
	var written: Dictionary = ledger.write_invoice(invoice.id)
	assert(written["ok"] == true, String(written["reason"]))
	var path: String = String(written["path"])
	assert(path.begins_with("user://biz/invoices/"), path)
	assert(path.contains("INV-2026-0001"), path)
	assert(FileAccess.file_exists(path), path)
	var bytes := FileAccess.get_file_as_bytes(path)
	assert(bytes.size() > 400, str(bytes.size()))
	assert(bytes.slice(0, 4).get_string_from_ascii() == "%PDF", "a customer can open it")
	assert(ledger.invoice_pdf(invoice.id).size() == bytes.size(), "and it is drawn once")
	assert(ledger.write_invoice("no such invoice")["ok"] == false)


func test_the_page_holds_the_invoices_own_figures() -> void:
	var ledger := _ledger()
	_full_schedule(ledger)
	var invoice: InvoiceScript = ledger.raise_invoice(JOB, AT, "", "", "", &"HST-ON")["invoice"]
	var page: Dictionary = SheetScript.plan_page(invoice)
	var rows: Array = (page["totals"] as Dictionary)["rows"]
	var captions := PackedStringArray()
	for row in rows:
		captions.append(String((row as Dictionary)["caption"]))
	assert(captions.has("Subtotal"), str(captions))
	assert(captions.has("Total"), str(captions))
	assert(captions.has("Balance due"), str(captions))
	var header: Dictionary = page["header"]
	assert(String(header["name"]) == "", "no letterhead was stated")
	assert(String(header["number_text"]) == "INV-2026-0001", String(header["number_text"]))


# --- the file -----------------------------------------------------------------------------------


func test_the_ledger_survives_the_file() -> void:
	var jobs := _jobs()
	var ledger := _ledger_on(jobs)
	_full_schedule(ledger)
	ledger.terms_days = 45
	ledger.fiscal_start_month = 4
	ledger.company.append("Greenline Landscapes")
	ledger.contact.append("HST 12345 6789")
	var invoice: InvoiceScript = ledger.raise_invoice(JOB, AT)["invoice"]
	ledger.record_payment(invoice.id, "2026-07-01", MoneyScript.of(100000), &"e-transfer", "tr 88")
	var read: LedgerScript = LedgerScript.from_dict(ledger.to_dict(), jobs)
	assert(read.terms_days == 45)
	assert(read.fiscal_start_month == 4)
	assert(read.company.size() == 1)
	assert(read.contact.size() == 1)
	assert(read.billing_count() == 1)
	assert(read.invoices.size() == 1)
	var back: InvoiceScript = read.invoices[0]
	assert(back.number == "INV-2026-0001")
	assert(back.subtotal().format_with_currency() == "$3,000.00")
	assert(back.payment_count() == 1)
	assert(back.state() == InvoiceScript.PART_PAID, "the state is a function of the records")
	assert(read.billing_for(JOB).billed_to_date.format_with_currency() == "$3,000.00")
	assert(read.billing_for(JOB).milestone("Deposit").is_billed())
	assert(read.problems().is_empty(), str(read.problems()))


func test_a_damaged_document_is_dropped_and_the_rest_of_the_ledger_reads() -> void:
	var ledger := _ledger()
	_full_schedule(ledger)
	ledger.raise_invoice(JOB, AT)
	var data: Dictionary = ledger.to_dict()
	(data["invoices"] as Array).append({"number": "INV-2026-0009"})
	(data["invoices"] as Array).append("not a document at all")
	var read: LedgerScript = LedgerScript.from_dict(data)
	assert(read.invoices.size() == 1, "a record with no id is dropped rather than invented")
	var empty: LedgerScript = LedgerScript.from_dict({})
	assert(empty.invoices.is_empty())
	assert(empty.billing_count() == 0)
	assert(empty.terms_days == LedgerScript.DEFAULT_TERMS_DAYS)


func test_a_schedule_read_back_is_the_schedule_that_went_in() -> void:
	var jobs := _jobs()
	var ledger := _ledger_on(jobs)
	ledger.add_milestone(JOB, "Deposit", 250000, MilestoneScript.APPROVED, "2026-06-01", 100000)
	ledger.set_percent_complete(JOB, 400000, BillingScript.BY_COST_INCURRED)
	var read: LedgerScript = LedgerScript.from_dict(ledger.to_dict(), jobs)
	var schedule: BillingScript = read.billing_for(JOB)
	assert(schedule.method == JobScript.MILESTONE)
	assert(schedule.step_count() == 1)
	assert(schedule.milestone("Deposit").percent_ppm == 250000)
	assert(schedule.milestone("Deposit").retainage_ppm == 100000)
	assert(schedule.milestone("Deposit").trigger == MilestoneScript.APPROVED)
	assert(schedule.milestone("Deposit").due_date == "2026-06-01")
	assert(read.milestone_rows(JOB)[0]["amount_text"] == "$3,000.00")


func test_a_schedule_for_a_job_the_desk_does_not_have_is_dropped() -> void:
	var ledger := _ledger()
	var stray: BillingScript = BillingScript.for_method("GONE", JobScript.FIXED)
	assert(ledger.add_billing(stray) == false)
	assert(ledger.add_billing(null) == false)
	assert(ledger.billing_count() == 1, "the desk still holds only the one it started")


func test_a_ledger_read_without_its_jobs_says_what_it_cannot_find() -> void:
	var ledger := _ledger()
	_full_schedule(ledger)
	ledger.raise_invoice(JOB, AT)
	var read: LedgerScript = LedgerScript.from_dict(ledger.to_dict())
	assert(read.invoices.size() == 1, "the document is kept: dropping it would lose a number")
	assert(read.billing_count() == 1, "and so is the schedule")
	var found: Array[String] = read.problems()
	assert(found.size() == 2, str(found))
	assert(found[0].contains("names a job this desk does not have"), found[0])
	assert(found[1].contains("schedule for a job this desk does not have"), found[1])


const SheetScript := preload("res://scripts/invoice_sheet.gd")
const UnderlayScript := preload("res://scripts/draft/raster_underlay.gd")

## Everything a logo test writes goes under this name, swept away first and last, so a test that
## throws half-way leaves nothing behind and a leftover cannot be the reason a later one passes.
const LOGO_PREFIX := "test-ledger-logo-"


func _logo_file(name: String) -> String:
	UnderlayScript.ensure_dir()
	var path: String = UnderlayScript.DIR.path_join(LOGO_PREFIX + name + ".png")
	var image := Image.create_empty(48, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.1, 0.3, 0.5, 1.0))
	image.save_png(path)
	return path


func _forget_logos() -> void:
	for path: String in UnderlayScript.list():
		if path.get_file().begins_with(LOGO_PREFIX):
			DirAccess.remove_absolute(path)


# --- the letterhead's picture --------------------------------------------------------------------


func test_the_company_logo_is_taken_and_kept_where_the_app_keeps_pictures() -> void:
	_forget_logos()
	var ledger := _ledger()
	var source := _logo_file("brand")
	var taken: Dictionary = ledger.keep_logo(source)
	assert(taken["ok"] == true, String(taken["reason"]))
	assert(ledger.logo.begins_with(UnderlayScript.DIR), ledger.logo)
	assert(FileAccess.file_exists(ledger.logo), "a copy is kept")
	assert(ledger.logo != source, "and it is the app's own copy rather than the file somebody found")
	_forget_logos()


func test_a_file_that_is_not_a_picture_is_refused_as_a_logo() -> void:
	_forget_logos()
	var ledger := _ledger()
	UnderlayScript.ensure_dir()
	var path: String = UnderlayScript.DIR.path_join(LOGO_PREFIX + "notes.png")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("an address book")
	file.close()
	var taken: Dictionary = ledger.keep_logo(path)
	assert(taken["ok"] == false, "a text file renamed .png is not a logo")
	assert(not String(taken["reason"]).is_empty(), "and it says why")
	assert(ledger.logo.is_empty(), "and nothing was taken")
	_forget_logos()


func test_the_logo_survives_the_file() -> void:
	_forget_logos()
	var jobs := _jobs()
	var ledger := _ledger_on(jobs)
	ledger.keep_logo(_logo_file("brand"))
	assert(not ledger.logo.is_empty())
	var read: LedgerScript = LedgerScript.from_dict(ledger.to_dict(), jobs)
	assert(read.logo == ledger.logo, read.logo)
	assert(LedgerScript.from_dict({}).logo == "", "a ledger from before logos has none")
	_forget_logos()


func test_the_invoice_carries_the_companys_logo_when_it_has_one() -> void:
	_forget_logos()
	var ledger := _ledger()
	_full_schedule(ledger)
	var invoice: InvoiceScript = ledger.raise_invoice(JOB, AT)["invoice"]
	ledger.company.append("Greenline Landscapes")
	var plain: PackedByteArray = ledger.invoice_pdf(invoice.id)
	assert(not plain.get_string_from_utf8().contains("/Subtype /Image"), "no logo, no picture")
	ledger.keep_logo(_logo_file("brand"))
	var with_logo: PackedByteArray = ledger.invoice_pdf(invoice.id)
	var text := with_logo.get_string_from_utf8()
	assert(text.contains("/Subtype /Image"), "the desk's logo reaches the page")
	assert(text.contains("/XObject"), "and the page's resources name it")
	assert(with_logo.size() > plain.size(), "the page is bigger for carrying it")
	_forget_logos()