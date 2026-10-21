extends Node
## An invoice: what was billed, what it comes to, and what has been paid (spec §4.12, §9.4).
##
## Three properties are under test. **An invoice is never edited after issue** - the setters refuse and
## a wrong one is voided and reissued, keeping its number. **The state is a function of the records**,
## so a file that claims "paid" on an unpaid draft does not make it paid. And **the numbering is
## gapless**, assigned at issue rather than at draft, which is why the next number is the highest
## taken plus one and never a count.

const InvoiceScript := preload("res://scripts/biz/invoice.gd")
const PaymentScript := preload("res://scripts/biz/payment.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")


func _invoice(invoice_id: String = "INV1") -> InvoiceScript:
	var invoice: InvoiceScript = InvoiceScript.new(invoice_id)
	invoice.job = "J1"
	invoice.add_amount(InvoiceScript.MILESTONE_LINE, "Deposit", MoneyScript.of(100000), &"HARDSCAPE", &"HST-ON")
	return invoice


func _issued() -> InvoiceScript:
	var invoice := _invoice()
	assert(bool(invoice.issue("2026-06-01", 30, "INV-2026-0001")["ok"]))
	return invoice


func _payment(payment_id: String, cents: int, invoice_id: String = "INV1") -> PaymentScript:
	var payment: PaymentScript = PaymentScript.new(payment_id)
	payment.invoice = invoice_id
	payment.received_at = "2026-06-10"
	payment.amount = MoneyScript.of(cents)
	return payment


# --- lines and what they come to ---------------------------------------------------------------


func test_a_line_is_a_quantity_at_a_rate_priced_by_the_one_rounding_rule() -> void:
	var invoice: InvoiceScript = InvoiceScript.new("INV1")
	assert(invoice.add_line(InvoiceScript.PERIOD_LINE, "Sod", 3500, &"SQ_FT", MoneyScript.of(250), &"PLANTING", &"NONE"))
	assert(invoice.subtotal().cents == 875, str(invoice.subtotal().cents))
	assert(invoice.line_count() == 1)
	assert(InvoiceScript.kind_name(InvoiceScript.PERIOD_LINE) == "a period of work")
	assert(invoice.line(0)["unit"] == "SQ_FT")


func test_a_line_the_totals_cannot_include_is_refused() -> void:
	var invoice: InvoiceScript = InvoiceScript.new("INV1")
	assert(not invoice.add_line(99, "Whatever", 1000, &"EACH", MoneyScript.of(100)))
	assert(not invoice.add_line(InvoiceScript.MILESTONE_LINE, "", 1000, &"EACH", MoneyScript.of(100)))
	assert(not invoice.add_line(InvoiceScript.MILESTONE_LINE, "Deposit", 0, &"EACH", MoneyScript.of(100)))
	assert(not invoice.add_line(InvoiceScript.MILESTONE_LINE, "Deposit", 1000, &"EACH", MoneyScript.invalid()))
	assert(not invoice.add_line(InvoiceScript.MILESTONE_LINE, "Deposit", 1000, &"EACH", MoneyScript.of(100, &"USD")))
	assert(not invoice.add_line(InvoiceScript.MILESTONE_LINE, "Deposit", 1000, &"EACH", MoneyScript.zero()))
	assert(invoice.line_count() == 0)


func test_the_subtotal_is_the_lines_and_the_totals_block_is_the_subtotals_own_figures() -> void:
	var invoice := _invoice()
	var figures: Dictionary = invoice.totals()
	assert((figures["subtotal"] as MoneyScript).cents == 100000)
	assert((figures["tax"] as MoneyScript).cents == 13000)
	assert((figures["retainage"] as MoneyScript).is_zero())
	assert((figures["total"] as MoneyScript).cents == 113000)
	assert((figures["balance"] as MoneyScript).cents == 113000)
	assert(invoice.tax_lines().size() == 1)
	assert(String(invoice.tax_lines()[0]["tax_code"]) == "HST-ON")


func test_each_tax_code_is_charged_on_its_own_share_of_the_invoice() -> void:
	var invoice := _invoice()
	invoice.add_amount(InvoiceScript.PERIOD_LINE, "Bark mulch", MoneyScript.of(50000), &"PLANTING", &"NONE")
	assert(invoice.subtotal().cents == 150000)
	assert(invoice.tax().cents == 13000, str(invoice.tax().cents))
	assert(invoice.tax_lines().size() == 2)


func test_a_tax_code_nobody_has_refuses_the_invoice_rather_than_charging_nothing() -> void:
	var invoice: InvoiceScript = InvoiceScript.new("INV1")
	invoice.job = "J1"
	assert(invoice.add_amount(InvoiceScript.MILESTONE_LINE, "Deposit", MoneyScript.of(100000), &"HARDSCAPE", &"VAT-99"))
	assert(invoice.tax_problem().contains("unknown tax code"), invoice.tax_problem())
	assert(not invoice.total().is_valid())
	assert(not invoice.is_sound())
	assert(invoice.problems().has("unknown tax code 'VAT-99'"), str(invoice.problems()))


func test_retainage_is_a_deduction_on_the_totals() -> void:
	var invoice := _invoice()
	assert(invoice.set_retainage(MoneyScript.of(10000)))
	assert(invoice.total().cents == 103000)
	assert(not invoice.set_retainage(MoneyScript.of(-1)))
	assert(not invoice.set_retainage(MoneyScript.invalid()))
	assert(not invoice.set_retainage(MoneyScript.of(100, &"USD")))
	assert(not invoice.set_retainage(null))
	assert(invoice.total().cents == 103000)


# --- issuing -----------------------------------------------------------------------------------


func test_an_invoice_with_nothing_on_it_does_not_go_out() -> void:
	var invoice: InvoiceScript = InvoiceScript.new("INV1")
	invoice.job = "J1"
	var refused: Dictionary = invoice.issue("2026-06-01", 30, "INV-2026-0001")
	assert(not bool(refused["ok"]))
	assert(String(refused["reason"]) == "an invoice with nothing on it", String(refused["reason"]))


func test_issuing_needs_a_number_a_moment_and_terms_nobody_mistyped() -> void:
	var invoice := _invoice()
	assert(not bool(invoice.issue("2026-06-01", 30, "")["ok"]))
	assert(not bool(invoice.issue("June", 30, "INV-2026-0001")["ok"]))
	assert(not bool(invoice.issue("2026-06-01", -1, "INV-2026-0001")["ok"]))
	assert(not bool(invoice.issue("2026-06-01", 99999, "INV-2026-0001")["ok"]))
	assert(not invoice.is_issued())


func test_issuing_stamps_the_moment_and_works_the_due_date_out_of_the_terms() -> void:
	var invoice := _issued()
	assert(invoice.number == "INV-2026-0001")
	assert(invoice.issued_at == "2026-06-01")
	assert(invoice.due_at == "2026-07-01")
	assert(invoice.state_name() == "issued")
	assert(invoice.is_issued())


func test_an_invoice_is_never_edited_after_issue() -> void:
	var invoice := _issued()
	assert(not invoice.add_amount(InvoiceScript.MILESTONE_LINE, "Something else", MoneyScript.of(100)))
	assert(not invoice.erase_line(0))
	assert(not invoice.set_retainage(MoneyScript.of(1000)))
	assert(invoice.line_count() == 1)
	assert(invoice.retainage.is_zero())
	var again: Dictionary = invoice.issue("2026-06-02", 30, "INV-2026-0002")
	assert(not bool(again["ok"]))
	assert(String(again["reason"]).contains("never edited after issue"), String(again["reason"]))
	assert(invoice.number == "INV-2026-0001")


func test_an_invoice_whose_totals_do_not_read_does_not_go_out() -> void:
	var invoice := _invoice()
	invoice.lines.append({
		"kind": InvoiceScript.MILESTONE_LINE,
		"description": "Damaged",
		"quantity_milli": 1000,
		"unit": "EACH",
		"rate": MoneyScript.invalid(),
		"amount": MoneyScript.invalid(),
		"cost_code": "",
		"tax_code": "NONE",
	})
	var refused: Dictionary = invoice.issue("2026-06-01", 30, "INV-2026-0001")
	assert(not bool(refused["ok"]))
	assert(not invoice.is_issued())


# --- numbering ---------------------------------------------------------------------------------


func test_a_number_is_a_fiscal_year_and_a_sequence() -> void:
	assert(InvoiceScript.number_for(2026, 184) == "INV-2026-0184")
	assert(InvoiceScript.number_for(2026, 0) == "")
	assert(InvoiceScript.number_for(0, 4) == "")
	assert(InvoiceScript.sequence_of("INV-2026-0184") == 184)
	assert(InvoiceScript.sequence_of("INV-2026-xxxx") == -1)
	assert(InvoiceScript.sequence_of("EST-2026-0004") == -1)
	assert(InvoiceScript.year_of("INV-2026-0184") == 2026)
	assert(InvoiceScript.year_of("nonsense") == 0)


func test_the_next_number_is_the_highest_taken_and_never_the_count() -> void:
	var taken: Array = ["INV-2026-0001", "INV-2026-0007", "INV-2025-0099"]
	assert(InvoiceScript.next_number(2026, taken) == "INV-2026-0008")
	assert(InvoiceScript.next_number(2025, taken) == "INV-2025-0100")
	assert(InvoiceScript.next_number(2027, taken) == "INV-2027-0001")
	var emptied: Array = ["INV-2026-0001", "INV-2026-0002"]
	assert(InvoiceScript.next_number(2026, emptied) == "INV-2026-0003",
		"a deleted draft leaves no hole but a voided invoice keeps its number")


func test_a_voided_invoice_keeps_its_number_so_the_year_stays_gapless() -> void:
	var invoice := _issued()
	assert(invoice.mark_void("2026-06-05", "the customer was changed", "INV-2026-0002"))
	assert(invoice.number == "INV-2026-0001")
	assert(invoice.state_name() == "void")
	var taken: Array = [invoice.number]
	assert(InvoiceScript.next_number(2026, taken) == "INV-2026-0002")


func test_a_fiscal_year_that_starts_before_january_puts_march_in_the_year_before() -> void:
	assert(InvoiceScript.fiscal_year_of("2026-06-01") == 2026)
	assert(InvoiceScript.fiscal_year_of("2026-03-15", 4) == 2025)
	assert(InvoiceScript.fiscal_year_of("2026-04-01", 4) == 2026)
	assert(InvoiceScript.fiscal_year_of("June", 4) == 0)


func test_terms_are_counted_in_days_from_the_moment_it_went_out() -> void:
	assert(InvoiceScript.add_days("2026-06-01", 30) == "2026-07-01")
	assert(InvoiceScript.add_days("2026-01-31", 30) == "2026-03-02")
	assert(InvoiceScript.add_days("June", 30) == "")


# --- payments and the state --------------------------------------------------------------------


func test_a_part_payment_leaves_a_balance_and_a_second_settles_it() -> void:
	var invoice := _issued()
	assert(bool(invoice.apply_payment(_payment("PAY1", 50000))["ok"]))
	assert(invoice.state_name() == "part paid")
	assert(invoice.balance().cents == 63000)
	assert(bool(invoice.apply_payment(_payment("PAY2", 63000))["ok"]))
	assert(invoice.state_name() == "paid")
	assert(invoice.balance().is_zero())
	assert(invoice.applied().cents == 113000)
	assert(invoice.payment_count() == 2)


func test_a_payment_larger_than_the_balance_is_refused_rather_than_clamped() -> void:
	var invoice := _issued()
	var refused: Dictionary = invoice.apply_payment(_payment("PAY1", 120000))
	assert(not bool(refused["ok"]))
	assert(String(refused["reason"]).contains("more than the"), String(refused["reason"]))
	assert(invoice.payment_count() == 0)
	assert(invoice.balance().cents == 113000)


func test_a_payment_against_a_draft_or_another_invoice_is_refused() -> void:
	var draft := _invoice()
	assert(not bool(draft.apply_payment(_payment("PAY1", 1000))["ok"]))
	var invoice := _issued()
	assert(not bool(invoice.apply_payment(_payment("PAY1", 1000, "OTHER"))["ok"]))
	assert(not bool(invoice.apply_payment(_payment("PAY1", -1000))["ok"]))
	assert(invoice.payment_count() == 0)


func test_the_same_payment_cannot_be_applied_twice() -> void:
	var invoice := _issued()
	assert(bool(invoice.apply_payment(_payment("PAY1", 1000))["ok"]))
	var again: Dictionary = invoice.apply_payment(_payment("PAY1", 1000))
	assert(not bool(again["ok"]))
	assert(String(again["reason"]).contains("already against this invoice"), String(again["reason"]))
	assert(invoice.applied().cents == 1000)


func test_a_voided_invoice_takes_no_payment_and_a_draft_is_not_voided() -> void:
	var draft := _invoice()
	assert(not draft.mark_void("2026-06-05", "wrong customer"))
	var invoice := _issued()
	assert(not invoice.mark_void("2026-06-05", ""))
	assert(not invoice.mark_void("June", "wrong customer"))
	assert(invoice.mark_void("2026-06-05", "the customer was changed", "INV-2026-0002"))
	assert(not invoice.mark_void("2026-06-06", "again"))
	assert(String(invoice.voided_text()) == "voided on 2026-06-05: the customer was changed (reissued as INV-2026-0002)",
		invoice.voided_text())
	assert(not bool(invoice.apply_payment(_payment("PAY1", 1000))["ok"]))


func test_the_state_is_a_function_of_the_records_and_not_a_field() -> void:
	var claimed: InvoiceScript = InvoiceScript.from_dict({
		"id": "INV1",
		"job": "J1",
		"state": "PAID",
		"lines": [{
			"kind": "MILESTONE",
			"description": "Deposit",
			"quantity_milli": 1000,
			"unit": "EACH",
			"rate": {"cents": 100000, "currency": "CAD"},
			"amount": {"cents": 100000, "currency": "CAD"},
			"tax_code": "NONE",
		}],
	})
	assert(claimed.state_name() == "draft", "a damaged file cannot make a draft look issued")
	var paid_claim: InvoiceScript = InvoiceScript.from_dict({
		"id": "INV2",
		"job": "J1",
		"issued_at": "2026-06-01",
		"number": "INV-2026-0001",
		"state": "PAID",
		"due_at": "2026-07-01",
		"lines": [{
			"kind": "MILESTONE",
			"description": "Deposit",
			"quantity_milli": 1000,
			"unit": "EACH",
			"rate": {"cents": 100000, "currency": "CAD"},
			"amount": {"cents": 100000, "currency": "CAD"},
			"tax_code": "NONE",
		}],
	})
	assert(paid_claim.state_name() == "issued", "an unpaid invoice is not paid because a file says so")


# --- soundness ----------------------------------------------------------------------------------


func test_an_issued_invoice_that_cannot_say_its_number_or_its_due_date_is_not_sound() -> void:
	var broken: InvoiceScript = InvoiceScript.from_dict({
		"id": "INV1",
		"job": "J1",
		"issued_at": "2026-06-01",
		"lines": [{
			"kind": "MILESTONE",
			"description": "Deposit",
			"quantity_milli": 1000,
			"unit": "EACH",
			"rate": {"cents": 100000, "currency": "CAD"},
			"amount": {"cents": 100000, "currency": "CAD"},
			"tax_code": "NONE",
		}],
	})
	assert(not broken.is_sound())
	assert(broken.problems().has("an issued invoice with no number"), str(broken.problems()))
	assert(broken.problems().has("an issued invoice due on a date that is not a date: ''"), str(broken.problems()))


func test_a_void_with_no_reason_and_an_overpaid_invoice_are_both_named() -> void:
	var invoice: InvoiceScript = InvoiceScript.from_dict({
		"id": "INV1",
		"job": "J1",
		"issued_at": "2026-06-01",
		"number": "INV-2026-0001",
		"due_at": "2026-07-01",
		"voided_at": "2026-06-05",
		"lines": [{
			"kind": "MILESTONE",
			"description": "Deposit",
			"quantity_milli": 1000,
			"unit": "EACH",
			"rate": {"cents": 100000, "currency": "CAD"},
			"amount": {"cents": 100000, "currency": "CAD"},
			"tax_code": "NONE",
		}],
		"payments": [{
			"id": "PAY1",
			"invoice": "INV1",
			"received_at": "2026-06-10",
			"amount": {"cents": 500000, "currency": "CAD"},
			"method": "cheque",
		}],
	})
	assert(invoice.problems().has("a void with no reason"), str(invoice.problems()))
	assert(invoice.problems().has("$5,000.00 has been paid against a total of $1,000.00"), str(invoice.problems()))


func test_an_invoice_reads_as_one_line() -> void:
	var invoice := _issued()
	assert(invoice.describe() == "INV-2026-0001, for job J1, 1 line(s), $1,000.00, + $130.00 tax, $1,130.00 due, issued, 2026-06-01 to 2026-07-01",
		invoice.describe())


# --- persistence --------------------------------------------------------------------------------


func test_an_invoice_survives_the_file_with_its_lines_its_tax_and_its_payments() -> void:
	var invoice := _issued()
	assert(bool(invoice.apply_payment(_payment("PAY1", 50000))["ok"]))
	invoice.note = "progress claim 1"
	invoice.period_start = "2026-05-01"
	invoice.period_end = "2026-05-31"
	invoice.customer = {"name": "Smith"}
	var back: InvoiceScript = InvoiceScript.from_dict(invoice.to_dict())
	assert(back.id == "INV1")
	assert(back.job == "J1")
	assert(back.number == "INV-2026-0001")
	assert(back.issued_at == "2026-06-01")
	assert(back.due_at == "2026-07-01")
	assert(back.terms_days == 30)
	assert(back.line_count() == 1)
	assert(back.line(0)["amount"].cents == 100000)
	assert(back.line(0)["tax_code"] == "HST-ON")
	assert(back.tax().cents == 13000)
	assert(back.total().cents == 113000)
	assert(back.payment_count() == 1)
	assert(back.applied().cents == 50000)
	assert(back.state_name() == "part paid")
	assert(String(back.customer["name"]) == "Smith")
	assert(back.note == "progress claim 1")
	assert(back.period_start == "2026-05-01")
	assert(back.is_sound())


func test_a_record_with_no_id_is_dropped_rather_than_invented() -> void:
	assert(InvoiceScript.from_dict({"job": "J1"}) == null)