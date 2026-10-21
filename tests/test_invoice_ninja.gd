extends Node
## Invoice Ninja v5: the request it builds, what it refuses, and what it will not claim (spec §9.6).
##
## Four properties are under test. **The push carries the headers the service requires** and a body of
## the shape it documents. **A line is posted at the invoice's own amount** rather than as a quantity at
## a rate, because the service would multiply and round it its own way. **A customer with no id in the
## service is refused rather than invented**, and a damaged invoice is refused in its own words. And
## **nothing is claimed that is not done**: no credits, no customers, no idempotency, and a test button
## that says it cannot test.

const NinjaScript := preload("res://scripts/biz/invoice_ninja.gd")
const LedgerScript := preload("res://scripts/biz/ledger_adapter.gd")
const InvoiceScript := preload("res://scripts/biz/invoice.gd")
const PaymentScript := preload("res://scripts/biz/payment.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")

const CLIENT := "Wpmbk5ezJn"


func _configured() -> NinjaScript:
	return NinjaScript.new("https://ninja.example.test", "token-abc")


func _invoice(tax_code: StringName = &"HST-ON", client: String = CLIENT,
		quantity_milli: int = 1000, rate_cents: int = 53550) -> InvoiceScript:
	var invoice: InvoiceScript = InvoiceScript.new("INV1")
	invoice.job = "J1"
	invoice.customer = {"name": "Smith", "external_id": client}
	invoice.add_line(InvoiceScript.MILESTONE_LINE, "Deposit", quantity_milli, &"SQ_FT",
		MoneyScript.of(rate_cents), &"HARDSCAPE", tax_code)
	assert(bool(invoice.issue("2026-06-10", 30, "INV-2026-0001")["ok"]))
	return invoice


func _built(ledger: NinjaScript, invoice: InvoiceScript) -> Dictionary:
	return ledger.build_invoice_push(invoice, ledger.key_for_invoice(invoice))


# --- what it is and what it will not claim -------------------------------------------------------


func test_it_reports_only_the_capabilities_it_actually_has() -> void:
	var ledger := _configured()
	var caps: Dictionary = ledger.capabilities()
	assert(bool(caps["invoices"]))
	assert(bool(caps["payments"]))
	# A capability says what this adapter does, not what the service might be able to do. Nothing here
	# posts a credit, creates a client, attaches a document, or can promise a single posting on a retry.
	for what: String in ["credits", "customers", "idempotency", "attachments"]:
		assert(not bool(caps[what]), "%s should not be claimed" % what)
	assert(not ledger.can(LedgerScript.CREDITS))
	assert(ledger.cannot_text(LedgerScript.CREDITS).contains("cannot post credit notes"),
		ledger.cannot_text(LedgerScript.CREDITS))
	assert(ledger.name() == &"invoice_ninja")
	assert(ledger.describe() == "Invoice Ninja at https://ninja.example.test")


func test_it_is_not_configured_until_its_settings_are_stated() -> void:
	var fresh: NinjaScript = NinjaScript.new()
	# The address has a default; the token is what a fresh one is missing.
	assert(fresh.problems().size() == 1, str(fresh.problems()))
	assert(fresh.problems()[0].contains("API token"), fresh.problems()[0])
	assert(not fresh.is_configured())
	assert(fresh.settings().size() == 2)
	assert(fresh.set_setting(&"token", "  token-abc  "))
	assert(fresh.setting(&"token") == "token-abc")
	assert(fresh.is_configured())
	assert(fresh.problems().is_empty())
	assert(fresh.set_setting(&"url", "https://ninja.example.test"))
	assert(fresh.setting(&"url") == "https://ninja.example.test")
	# A field it does not have is refused, so a settings page cannot store a value nothing reads.
	assert(not fresh.set_setting(&"secret_sauce", "x"))
	assert(fresh.setting(&"secret_sauce") == "")
	# A setting with nothing in it is refused rather than stored empty.
	assert(not fresh.set_setting(&"url", "   "))


func test_a_stated_address_with_no_token_is_still_not_configured() -> void:
	var ledger: NinjaScript = NinjaScript.new("https://ninja.example.test")
	assert(not ledger.is_configured())
	assert(ledger.describe() == "Invoice Ninja at https://ninja.example.test")
	var nowhere: NinjaScript = NinjaScript.new("")
	assert(nowhere.describe() == "Invoice Ninja (no address)")
	assert(nowhere.problems().size() == 2, str(nowhere.problems()))


# --- the request -------------------------------------------------------------------------------


func test_the_push_carries_the_headers_the_service_requires() -> void:
	var ledger := _configured()
	var invoice := _invoice()
	var built: Dictionary = _built(ledger, invoice)
	assert(bool(built["ok"]), String(built["reason"]))
	var request: Dictionary = built["request"]
	assert(String(request["method"]) == "POST")
	assert(String(request["url"]) == "https://ninja.example.test/api/v1/invoices")
	var headers: Dictionary = request["headers"]
	# The three headers the service requires on every request, plus the key.
	assert(String(headers[NinjaScript.TOKEN_HEADER]) == "token-abc")
	assert(String(headers[NinjaScript.REQUESTED_WITH_HEADER]) == "XMLHttpRequest")
	assert(String(headers["Content-Type"]) == "application/json")
	assert(String(headers[LedgerScript.KEY_HEADER]) == ledger.key_for_invoice(invoice))


func test_the_body_is_the_shape_the_service_documents() -> void:
	var ledger := _configured()
	var invoice := _invoice()
	var built: Dictionary = _built(ledger, invoice)
	var body: Dictionary = built["request"]["body"]
	assert(String(body["client_id"]) == CLIENT)
	assert(String(body["date"]) == "2026-06-10")
	assert(String(body["due_date"]) == "2026-07-10")
	assert(String(body["number"]) == "INV-2026-0001")
	# The key is in the body as well as the header, so a backend that reads it there has it.
	assert(String(body[NinjaScript.KEY_FIELD]) == ledger.key_for_invoice(invoice))
	var items: Array = body["line_items"]
	assert(items.size() == 1)
	var item: Dictionary = items[0]
	assert(float(item["cost"]) == 535.5, str(item["cost"]))
	assert(String(item["tax_name1"]) == "HST-ON")
	# The rate is read off the published table: 13% for HST-ON, not a number this adapter derived.
	assert(float(item["tax_rate1"]) == 13.0, str(item["tax_rate1"]))
	assert(String(item["product_key"]) == "HARDSCAPE")


func test_a_line_is_posted_at_the_invoices_own_amount_rather_than_a_quantity_at_a_rate() -> void:
	var ledger := _configured()
	# 3.5 square feet at 2.50 is 8.75, and the invoice rounded that once. The service would multiply and
	# round it itself, so the quantity travels in the words instead and the money travels as the amount.
	var invoice := _invoice(&"NONE", CLIENT, 3500, 250)
	assert(invoice.subtotal().cents == 875)
	var built: Dictionary = _built(ledger, invoice)
	assert(bool(built["ok"]), String(built["reason"]))
	var item: Dictionary = built["request"]["body"]["line_items"][0]
	assert(int(item["quantity"]) == 1)
	assert(float(item["cost"]) == 8.75, str(item["cost"]))
	assert(String(item["notes"]) == "Deposit, 3.5 SQ_FT", String(item["notes"]))
	# A code that charges nothing gets no tax on the line at all, which is not the same as a rate of 0.
	assert(not item.has("tax_name1"))
	assert(not item.has("tax_rate1"))


func test_a_zero_rated_code_and_a_missing_one_are_neither_of_them_a_tax_rate() -> void:
	var ledger := _configured()
	for code: StringName in [&"NONE", &"EXEMPT"]:
		var built: Dictionary = _built(ledger, _invoice(code))
		assert(bool(built["ok"]), String(built["reason"]))
		var item: Dictionary = built["request"]["body"]["line_items"][0]
		assert(not item.has("tax_rate1"), "a %s line carries no rate" % String(code))


# --- what it refuses ----------------------------------------------------------------------------


func test_a_customer_with_no_id_in_the_service_is_refused_rather_than_invented() -> void:
	var ledger := _configured()
	var refused: Dictionary = _built(ledger, _invoice(&"HST-ON", ""))
	assert(not bool(refused["ok"]))
	assert(String(refused["reason"]).contains("no id in Invoice Ninja"), String(refused["reason"]))
	assert(String(refused["reason"]).contains("external_id"), String(refused["reason"]))
	assert((refused["request"] as Dictionary).is_empty())


func test_a_damaged_invoice_is_refused_in_its_own_words() -> void:
	var ledger := _configured()
	# A file can carry an issued invoice whose line amount cannot be read, because `from_dict` keeps a
	# damaged line rather than dropping it. The invoice is the authority on whether it can be posted, so
	# its own reason is the one that comes back.
	var damaged: InvoiceScript = InvoiceScript.from_dict({
		"id": "INV9",
		"job": "J1",
		"customer": {"name": "Smith", "external_id": CLIENT},
		"issued_at": "2026-06-10",
		"due_at": "2026-07-10",
		"number": "INV-2026-0009",
		"lines": [{
			"kind": "MILESTONE",
			"description": "Deposit",
			"quantity_milli": 1000,
			"unit": "EACH",
			"rate": MoneyScript.invalid().to_dict(),
			"amount": MoneyScript.invalid().to_dict(),
			"tax_code": "NONE",
		}],
	})
	assert(damaged != null)
	assert(damaged.is_issued())
	var refused: Dictionary = ledger.build_invoice_push(damaged, "key")
	assert(not bool(refused["ok"]))
	assert(String(refused["reason"]).contains("readable"), String(refused["reason"]))


func test_a_payment_needs_the_invoices_id_in_the_service() -> void:
	var ledger := _configured()
	var invoice := _invoice()
	var payment: PaymentScript = PaymentScript.new("PMT-0001")
	payment.invoice = "INV1"
	payment.received_at = "2026-06-20"
	payment.amount = MoneyScript.of(53550)
	payment.bank_reference = "chq 1041"
	var refused: Dictionary = ledger.build_payment_push(
		payment, invoice, ledger.key_for_payment(payment, invoice)
	)
	assert(not bool(refused["ok"]))
	assert(String(refused["reason"]).contains("the invoice's id in Invoice Ninja"),
		String(refused["reason"]))
	assert(String(refused["reason"]).contains("when the invoice is first posted"),
		String(refused["reason"]))
	var built: Dictionary = ledger.build_payment_push(
		payment, invoice, ledger.key_for_payment(payment, invoice), "abc123"
	)
	assert(bool(built["ok"]), String(built["reason"]))
	var body: Dictionary = built["request"]["body"]
	assert(float(body["amount"]) == 535.5)
	assert(String(body["date"]) == "2026-06-20")
	assert(String(body["transaction_reference"]) == "chq 1041")
	var applied: Array = body["invoices"]
	assert(applied.size() == 1)
	assert(String(applied[0]["invoice_id"]) == "abc123")
	assert(float(applied[0]["amount"]) == 535.5)
	assert(String(built["request"]["url"]) == "https://ninja.example.test/api/v1/payments")


# --- reading the answer -------------------------------------------------------------------------


func test_it_reads_the_document_out_of_the_data_the_service_wraps_it_in() -> void:
	var ledger := _configured()
	var read: Dictionary = ledger.parse_invoice_response({
		"status": 200,
		"body": {"data": {"id": "xYRdG7dDzO", "number": "0019"}},
	})
	assert(bool(read["ok"]))
	assert(String(read["external_id"]) == "xYRdG7dDzO")
	assert(String(read["external_number"]) == "0019")
	# An answer with nothing in it is still a success: the request was taken.
	var quiet: Dictionary = ledger.parse_invoice_response({"status": 200, "body": {}})
	assert(bool(quiet["ok"]))
	assert(String(quiet["external_id"]) == "")
	# A refusal is read the way every backend's is, with the message the service sent.
	var refused: Dictionary = ledger.parse_invoice_response({
		"status": 422,
		"body": {"message": "The number has already been taken"},
	})
	assert(not bool(refused["ok"]))
	assert(not bool(refused["retry"]))
	assert(String(refused["reason"]).contains("already been taken"), String(refused["reason"]))


func test_it_cannot_be_tested_or_sent_until_the_transport_exists() -> void:
	var ledger := _configured()
	var tested: Dictionary = ledger.self_test()
	# A green light that verified nothing would be worse than no button: this says what it cannot do.
	assert(not bool(tested["ok"]))
	assert(String(tested["reason"]).contains("no transport yet"), String(tested["reason"]))
	var sent: Dictionary = ledger.send({"method": "POST", "url": "https://ninja.example.test"})
	assert(int(sent["status"]) == 0)
	assert(String(sent["error"]).contains("HTTP transport"), String(sent["error"]))
	var unconfigured: NinjaScript = NinjaScript.new()
	assert(String(unconfigured.self_test()["reason"]).contains("API token"),
		String(unconfigured.self_test()["reason"]))