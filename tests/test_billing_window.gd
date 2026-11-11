extends Node
## The billing page: the schedule, the invoices and the money that came in (spec §9).
##
## The page owns no arithmetic - every figure is a field of a row the desk produced - so these tests
## hold four things: that what is shown is what the desk says, that the amount due is on the page
## **before** the invoice button is pressed, that a step can be billed from its own row, and that calling
## an invoice back puts the step back on the schedule.
##
## Each test frees the window it built, which is what the other window tests do: a `Window` is a tree
## with a viewport, and letting one live to engine exit is a leaked resource.

const WindowScript := preload("res://scripts/billing_window.gd")
const DeskScript := preload("res://scripts/biz/job_desk.gd")
const LedgerScript := preload("res://scripts/biz/billing_desk.gd")
const JobScript := preload("res://scripts/biz/job.gd")
const BillingScript := preload("res://scripts/biz/billing.gd")
const InvoiceScript := preload("res://scripts/biz/invoice.gd")
const EstimateScript := preload("res://scripts/biz/estimate.gd")
const LineScript := preload("res://scripts/biz/estimate_line.gd")
const ItemScript := preload("res://scripts/biz/cost_item.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")

const JOB := "E1"


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


## HARDSCAPE sold for $10,000.00 and PLANTING for $2,000.00: a contract of $12,000.00, of which a
## quarter is a round $3,000.00.
func _desk(method: int = JobScript.MILESTONE) -> DeskScript:
	var jobs: DeskScript = DeskScript.new()
	var estimate: EstimateScript = EstimateScript.new(JOB)
	estimate.customer = {"name": "Smith, back garden"}
	estimate.lines.append(_line(&"HARDSCAPE", 10000, 70000, 100000))
	estimate.lines.append(_line(&"PLANTING", 10000, 15000, 20000))
	jobs.make_job_from(estimate)
	jobs.job(JOB).set_billing_method(method)
	return jobs


func _ledger(method: int = JobScript.MILESTONE, start := true) -> LedgerScript:
	var ledger: LedgerScript = LedgerScript.new()
	ledger.bind(_desk(method))
	if start:
		ledger.start_billing(JOB)
	return ledger


func _page(method: int = JobScript.MILESTONE, start := true) -> WindowScript:
	var page: WindowScript = WindowScript.new()
	page.build()
	page.bind(_ledger(method, start))
	return page


## A schedule that claims the whole contract, so the only thing the desk complains about is what a test
## is asking about.
func _full_schedule(page: WindowScript) -> void:
	page.ledger.add_milestone(JOB, "Deposit", 250000)
	page.ledger.add_milestone(JOB, "Balance", 750000)
	page.refresh()


# --- building ----------------------------------------------------------------------------------


func test_a_page_with_no_ledger_is_empty_rather_than_broken() -> void:
	var page: WindowScript = WindowScript.new()
	page.build()
	page.bind(null)
	assert(page.summary_text() == "no job chosen", page.summary_text())
	assert(page.amount_text() == "")
	assert(page.schedule_texts().is_empty())
	assert(page.invoice_texts().is_empty())
	assert(page.payment_texts().is_empty())
	assert(page.problem_texts().is_empty())
	assert(page.status_text() == "No job has been started yet: an estimate that is agreed becomes a job.",
		page.status_text())
	assert(page.start_button_disabled())
	assert(page.raise_button_disabled())
	assert(page.payment_button_disabled())
	page.free()


func test_the_page_has_the_controls_a_program_of_this_kind_has() -> void:
	var page := _page()
	assert(page.get_node_or_null(NodePath("Scroll/Column/Summary")) != null)
	assert(page.get_node_or_null(NodePath("Scroll/Column/JobRow/JobOption")) != null)
	assert(page.get_node_or_null(NodePath("Scroll/Column/JobRow/Startbillingit")) != null)
	assert(page.get_node_or_null(NodePath("Scroll/Column/StepRow/StepName")) != null)
	assert(page.get_node_or_null(NodePath("Scroll/Column/StepRow/StepShare")) != null)
	assert(page.get_node_or_null(NodePath("Scroll/Column/StepRow/StepRetainage")) != null)
	assert(page.get_node_or_null(NodePath("Scroll/Column/StepRow/Addthestep")) != null)
	assert(page.get_node_or_null(NodePath("Scroll/Column/Schedule")) != null)
	assert(page.get_node_or_null(NodePath("Scroll/Column/MeasureRow/Percent")) != null)
	assert(page.get_node_or_null(NodePath("Scroll/Column/MeasureRow/BasisOption")) != null)
	assert(page.get_node_or_null(NodePath("Scroll/Column/TermsRow/TaxOption")) != null)
	assert(page.get_node_or_null(NodePath("Scroll/Column/TermsRow/Terms")) != null)
	assert(page.get_node_or_null(NodePath("Scroll/Column/AmountDue")) != null)
	assert(page.get_node_or_null(NodePath("Scroll/Column/RaiseRow/Raisetheinvoice")) != null)
	assert(page.get_node_or_null(NodePath("Scroll/Column/InvoiceRow/InvoiceOption")) != null)
	assert(page.get_node_or_null(NodePath("Scroll/Column/Invoices")) != null)
	assert(page.get_node_or_null(NodePath("Scroll/Column/PaymentRow/Payment")) != null)
	assert(page.get_node_or_null(NodePath("Scroll/Column/PaymentRow/MethodOption")) != null)
	assert(page.get_node_or_null(NodePath("Scroll/Column/PaymentRow/Recordit")) != null)
	assert(page.get_node_or_null(NodePath("Scroll/Column/Payments")) != null)
	assert(page.get_node_or_null(NodePath("Scroll/Column/VoidRow/Why")) != null)
	assert(page.get_node_or_null(NodePath("Scroll/Column/VoidRow/Printtheinvoice")) != null)
	assert(page.get_node_or_null(NodePath("Scroll/Column/VoidRow/Callitback")) != null)
	assert(page.get_node_or_null(NodePath("Scroll/Column/Problems")) != null)
	assert(page.get_node_or_null(NodePath("Scroll/Column/Status")) != null)
	page.free()


func test_the_job_picker_lists_what_the_job_desk_has() -> void:
	var page := _page()
	assert(page.selected_job() == JOB, page.selected_job())
	assert(page.summary_text().contains("Smith, back garden"), page.summary_text())
	assert(page.choose_job(JOB))
	assert(page.choose_job("NOPE") == false)
	page.free()


func test_the_page_opens_saying_what_to_do_with_it() -> void:
	var page := _page(JobScript.MILESTONE, false)
	assert(page.opening_words().contains("Start billing this job"), page.opening_words())
	assert(page.opening_words().contains("milestones"), page.opening_words())
	assert(page.status_text() == page.opening_words(), page.status_text())
	assert(page.start_button_disabled() == false)
	assert(page.raise_button_disabled(), "there is nothing to bill by yet")
	page.free()


func test_a_page_builds_its_buttons_without_a_keyboard_of_their_own() -> void:
	var page := _page()
	# At build time the typed fields are the only things that hold one; when the page is *shown* the
	# shared show gives its controls the keyboard too, because the page holds it while it is up.
	assert(page.buttons_are_focus_free(), "at build time, before anything shows the page")
	page.free()


# --- starting to bill, and the schedule ---------------------------------------------------------


func test_starting_billing_through_the_page_says_which_method_the_contract_agreed_to() -> void:
	var page := _page(JobScript.PERCENTAGE_COMPLETE, false)
	assert(page.begin_billing(), page.status_text())
	assert(page.status_text().contains("percentage complete"), page.status_text())
	assert(page.start_button_disabled(), "a job is billed one way")
	assert(page.begin_billing() == false, "and starting it again is refused")
	assert(page.raise_button_disabled() == false, "now there is a method to bill by")
	page.free()


func test_a_step_is_added_through_the_page() -> void:
	var page := _page()
	page.set_step_fields("Deposit", "25")
	var added: Dictionary = page.add_step()
	assert(added["ok"] == true, String(added["reason"]))
	assert(page.status_text().contains("25% of the contract"), page.status_text())
	assert(page.schedule_texts().size() == 1, str(page.schedule_texts()))
	assert(page.schedule_texts()[0].contains("Deposit"), page.schedule_texts()[0])
	assert(page.schedule_texts()[0].contains("$3,000.00"), page.schedule_texts()[0])
	assert(page.get_node_or_null(NodePath("Scroll/Column/Schedule/Step0")) != null)
	page.free()


## A row the page builds **while it is open** is reachable too. The shared show gave the page its
## keyboard when it was opened, before this row existed, so the rebuild is what gives the new controls
## theirs - and the page does that only while it is up, because for a page that is down the show is the
## one place that decides it.
func test_a_row_built_while_the_page_is_open_is_reachable() -> void:
	var page := _page()
	add_child(page)
	page.show()
	page.set_step_fields("Deposit", "25")
	var added: Dictionary = page.add_step()
	assert(added["ok"] == true, String(added["reason"]))
	var step: Node = page.get_node_or_null(NodePath("Scroll/Column/Schedule/Step0"))
	assert(step != null, "the row was built")
	var buttons: Array[Node] = step.find_children("*", "Button", true, false)
	assert(buttons.size() >= 1, "with the button that bills it")
	for found: Node in buttons:
		assert((found as Control).focus_mode == Control.FOCUS_ALL, "and it can be reached with Tab")
	page.free()


func test_a_step_that_is_not_a_share_of_the_contract_is_refused_by_the_page() -> void:
	var page := _page()
	page.set_step_fields("Deposit", "a quarter")
	var refused: Dictionary = page.add_step()
	assert(refused["ok"] == false)
	assert(page.status_text().contains("share of the contract"), page.status_text())
	assert(page.schedule_texts().is_empty(), "and nothing was added")
	page.set_step_fields("Deposit", "25", "one tenth")
	assert(page.add_step()["ok"] == false,
		"a retainage nobody can read is refused rather than taken as lots")
	assert(page.schedule_texts().is_empty())
	page.free()


func test_a_retainage_on_a_step_reaches_the_invoice_through_the_page() -> void:
	var page := _page()
	page.set_step_fields("Deposit", "25", "10")
	var added: Dictionary = page.add_step()
	assert(added["ok"] == true, String(added["reason"]))
	assert(page.status_text().contains("10% withheld from it"), page.status_text())
	assert(page.schedule_texts()[0].contains("10% withheld"), page.schedule_texts()[0])
	var raised: Dictionary = page.raise_invoice()
	assert(raised["ok"] == true, String(raised["reason"]))
	var invoice: InvoiceScript = raised["invoice"]
	assert(invoice.retainage.format_with_currency() == "$300.00", invoice.retainage.format_with_currency())
	assert(invoice.total().format_with_currency() == "$2,700.00", invoice.total().format_with_currency())
	assert(page.ledger.retained_total(JOB).format_with_currency() == "$300.00")
	page.free()


func test_the_schedule_says_what_a_job_that_cannot_bill_anything_is_missing() -> void:
	var page := _page()
	assert(page.get_node_or_null(NodePath("Scroll/Column/Schedule/NoSteps")) != null)
	var blank := _page()
	blank.bind(_ledger(JobScript.MILESTONE, false))
	blank.refresh()
	var page_text: String = (blank.get_node(NodePath("Scroll/Column/Schedule/NoSteps")) as Label).text
	assert(page_text.contains("not being billed yet"), page_text)
	page.free()
	blank.free()


func test_the_schedule_bills_the_step_the_schedule_would_bill_next() -> void:
	var page := _page()
	_full_schedule(page)
	assert(page.get_node_or_null(NodePath("Scroll/Column/Schedule/Step0/Billit")) != null,
		"the next step carries the button")
	assert(page.get_node_or_null(NodePath("Scroll/Column/Schedule/Step1/Billit")) == null,
		"and the one after it does not")
	page.free()


func test_the_rows_on_the_page_are_the_desks_own_rows() -> void:
	var page := _page()
	_full_schedule(page)
	var from_the_desk: Array[String] = []
	for held in page.ledger.milestone_rows(JOB):
		from_the_desk.append(String(held["describe"]))
	assert(page.schedule_texts() == from_the_desk, "what is shown is what the desk says")
	assert(page.invoice_texts() == page.ledger.invoice_texts(JOB))
	page.free()


func test_the_measurement_is_saved_with_the_basis_the_dropdown_shows() -> void:
	var page := _page(JobScript.PERCENTAGE_COMPLETE)
	page.set_percent("40", BillingScript.BY_PHASE_COMPLETION)
	var saved: Dictionary = page.measure()
	assert(saved["ok"] == true, String(saved["reason"]))
	assert(page.status_text().contains("by phase completion"), page.status_text())
	page.ledger.billing_for(JOB)
	assert(page.ledger.billing_for(JOB).percent_basis == BillingScript.BY_PHASE_COMPLETION)
	assert(page.ledger.billing_for(JOB).complete_ppm == 400000)
	page.free()


func test_a_percent_nobody_could_have_measured_is_refused_by_the_page() -> void:
	var page := _page(JobScript.PERCENTAGE_COMPLETE)
	page.set_percent("most of it")
	var refused: Dictionary = page.measure()
	assert(refused["ok"] == false)
	assert(page.status_text().contains("a percent somebody could have measured"), page.status_text())
	page.free()


# --- raising an invoice -------------------------------------------------------------------------


func test_the_page_says_what_the_job_can_bill_before_the_button_is_pressed() -> void:
	var page := _page()
	_full_schedule(page)
	assert(page.amount_text().contains("$3,000.00"), page.amount_text())
	assert(page.amount_text().contains("Deposit"), page.amount_text())
	assert(page.raise_button_disabled() == false)
	page.free()


func test_raising_an_invoice_from_the_page_writes_it_and_says_where_it_stands() -> void:
	var page := _page()
	_full_schedule(page)
	var raised: Dictionary = page.raise_invoice()
	assert(raised["ok"] == true, String(raised["reason"]))
	assert(page.status_text().contains("INV-2026-"), page.status_text())
	assert(page.status_text().contains("$3,000.00"), page.status_text())
	assert(page.invoice_texts().size() == 1, str(page.invoice_texts()))
	assert(page.selected_invoice() == (raised["invoice"] as InvoiceScript).id)
	assert(page.amount_text().contains("$9,000.00"), "the page now offers the balance")
	page.free()


func test_a_step_is_billed_from_its_own_row() -> void:
	var page := _page()
	_full_schedule(page)
	var raised: Dictionary = page.bill_step("Balance")
	assert(raised["ok"] == true, String(raised["reason"]))
	assert((raised["invoice"] as InvoiceScript).subtotal().format_with_currency() == "$9,000.00",
		(raised["invoice"] as InvoiceScript).subtotal().format_with_currency())
	assert(page.status_text().contains("$9,000.00"), page.status_text())
	page.free()


func test_a_step_that_has_gone_out_is_refused_from_its_row_by_name() -> void:
	var page := _page()
	_full_schedule(page)
	page.raise_invoice()
	var refused: Dictionary = page.bill_step("Deposit")
	assert(refused["ok"] == false)
	assert(page.status_text().contains("nothing went out"), page.status_text())
	assert(page.invoice_texts().size() == 1, "and no second document was written")
	page.free()


func test_the_tax_dropdown_charges_the_code_it_shows() -> void:
	var page := _page()
	_full_schedule(page)
	assert(page.choose_tax_code(&"HST-ON"))
	assert(page.selected_tax_code() == &"HST-ON")
	page.raise_invoice()
	var invoice: InvoiceScript = page.ledger.invoices[0]
	assert(invoice.total().format_with_currency() == "$3,390.00", invoice.total().format_with_currency())
	page.free()


func test_the_terms_field_is_the_businesss_own() -> void:
	var page := _page(JobScript.FIXED)
	page.set_terms(15)
	var raised: Dictionary = page.raise_invoice()
	assert(raised["ok"] == true, String(raised["reason"]))
	assert((raised["invoice"] as InvoiceScript).terms_days == 15)
	assert(page.ledger.terms_days == 15, "the field writes back to the business")
	page.free()


func test_an_invoice_that_could_not_go_out_says_why_on_the_status_line() -> void:
	var page := _page()
	var raised: Dictionary = page.raise_invoice()
	assert(raised["ok"] == false)
	assert(page.status_text().contains("nothing went out"), page.status_text())
	assert(page.invoice_texts().is_empty())
	page.free()


# --- the money ----------------------------------------------------------------------------------


func test_money_is_recorded_through_the_page_against_the_invoice_the_picker_shows() -> void:
	var page := _page()
	_full_schedule(page)
	page.raise_invoice()
	page.set_payment("$1,000.00", "chq 1041", "cheque")
	assert(page.payment_button_disabled() == false)
	var taken: Dictionary = page.record_payment()
	assert(taken["ok"] == true, String(taken["reason"]))
	assert(page.payment_texts().size() == 1, str(page.payment_texts()))
	assert(page.payment_texts()[0].contains("by cheque"), page.payment_texts()[0])
	assert(page.payment_texts()[0].contains("chq 1041"), page.payment_texts()[0])
	assert(page.status_text().contains("$1,000.00"), page.status_text())
	assert(page.invoice_texts()[0].contains("part paid"), page.invoice_texts()[0])
	page.free()


func test_a_payment_with_no_amount_is_not_recorded() -> void:
	var page := _page()
	_full_schedule(page)
	page.raise_invoice()
	page.set_payment("")
	assert(page.payment_button_disabled(), "a page does not offer a button that cannot work")
	var refused: Dictionary = page.record_payment()
	assert(refused["ok"] == false)
	assert(page.payment_texts().is_empty())
	page.free()


func test_the_page_refuses_more_than_the_balance() -> void:
	var page := _page()
	_full_schedule(page)
	page.raise_invoice()
	page.set_payment("$99,000.00", "tr 12", "bank transfer")
	var refused: Dictionary = page.record_payment()
	assert(refused["ok"] == false)
	assert(page.status_text().contains("nothing was recorded"), page.status_text())
	assert(page.payment_texts().is_empty())
	page.free()


func test_the_payments_the_page_lists_are_the_ones_the_desk_holds() -> void:
	var page := _page()
	_full_schedule(page)
	page.raise_invoice()
	page.set_payment("$1,000.00", "chq 1041")
	page.record_payment()
	assert(page.payment_texts() == page.ledger.payment_texts(page.selected_invoice()))
	page.free()


# --- calling one back ---------------------------------------------------------------------------


func test_calling_an_invoice_back_through_the_page_needs_a_reason() -> void:
	var page := _page()
	_full_schedule(page)
	page.raise_invoice()
	page.set_why("")
	var refused: Dictionary = page.void_invoice()
	assert(refused["ok"] == false)
	assert(page.status_text().contains("nothing was called back"), page.status_text())
	page.free()


func test_calling_an_invoice_back_puts_the_step_on_the_schedule_again() -> void:
	var page := _page()
	_full_schedule(page)
	page.raise_invoice()
	page.set_why("the address was wrong")
	var called: Dictionary = page.void_invoice()
	assert(called["ok"] == true, String(called["reason"]))
	assert(page.status_text().contains("called back"), page.status_text())
	assert(page.amount_text().contains("$3,000.00"), "the step can be billed again")
	assert(page.ledger.billable_step(JOB) == "Deposit")
	assert(page.invoice_texts()[0].contains("void"), page.invoice_texts()[0])
	assert(page.ledger.problems(JOB).is_empty(), str(page.ledger.problems(JOB)))
	page.free()


func test_printing_the_invoice_writes_the_page_and_says_where() -> void:
	var page := _page()
	_full_schedule(page)
	page.raise_invoice()
	var written: Dictionary = page.print_invoice()
	assert(written["ok"] == true, String(written["reason"]))
	assert(String(written["path"]).contains("INV-"), String(written["path"]))
	assert(FileAccess.file_exists(String(written["path"])), String(written["path"]))
	assert(page.status_text().contains("is written to"), page.status_text())
	page.free()


func test_the_problems_the_page_shows_are_the_desks_own() -> void:
	var page := _page()
	page.ledger.add_milestone(JOB, "Deposit", 250000)
	page.refresh()
	assert(page.problem_texts().size() == 1, str(page.problem_texts()))
	assert(page.problem_texts()[0].contains("claimed by no step"), page.problem_texts()[0])
	var listed: ItemList = page.get_node(NodePath("Scroll/Column/Problems"))
	assert(listed.item_count == 1, str(listed.item_count))
	assert(listed.is_item_disabled(0), "a problem is a thing to read, not a thing to choose")
	page.free()


func test_an_empty_schedule_says_what_is_missing_rather_than_reading_as_nothing_to_bill() -> void:
	var page := _page()
	var empty: Label = page.get_node(NodePath("Scroll/Column/Schedule/NoSteps"))
	assert(empty.text.contains("with no milestones"), empty.text)
	page.free()