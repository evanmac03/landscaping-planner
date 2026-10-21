extends Node
## Akaunting: HTTP Basic, contacts, datetimes, and the tax id this program cannot know (spec §9.6).
##
## Five properties are under test. **A date is posted as a datetime**, because Akaunting refuses a bare
## date with a message that names no field at all. **The invoice's own figures travel** as stated
## amounts, because a tax has to be attached by its id inside Akaunting and this program has no way to
## know it. **The credential is HTTP Basic** over the user and password, with the company header only
## when one is stated. **A customer with no id in the service is refused rather than invented.** And
## **nothing is claimed that is not done**: no credits, no customers, no idempotency, and a test button
## that says it cannot test.

const AkauntingScript := preload("res://scripts/biz/akaunting.gd")
const LedgerScript := preload("res://scripts/biz/ledger_adapter.gd")
const InvoiceScript := preload("res://scripts/biz/invoice.gd")
const PaymentScript := preload("res://scripts/biz/payment.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")

const CONTACT := "7"


func _configured() -> AkauntingScript:
	return AkauntingScript.new("https://books.example.test", "office@example.test", "hunter2")


func _invoice(tax_code: StringName = &"HST-ON", contact: String = CONTACT) -> InvoiceScript:
	var invoice: InvoiceScript = InvoiceScript.new("INV1")
	invoice.job = "J1"
	invoice.customer = {"name": "Smith", "external_id": contact}
	invoice.note = "Back garden, phase one"
	invoice.add_line(InvoiceScript.MILESTONE_LINE, "Deposit", 1000, &"EACH",
		MoneyScript.of(53550), &"HARDSCAPE", tax_code)
	assert(bool(invoice.issue("2026-06-10", 30, "INV-2026-0001")["ok"]))
	return invoice


func _built(ledger: AkauntingScript, invoice: InvoiceScript) -> Dictionary:
	return ledger.build_invoice_push(invoice, ledger.key_for_invoice(invoice))


# --- what it is and what it will not claim -------------------------------------------------------


func test_it_reports_only_the_capabilities_it_actually_has() -> void:
	var ledger := _configured()
	var caps: Dictionary = ledger.capabilities()
	assert(bool(caps["invoices"]))
	assert(bool(caps["payments"]))
	for what: String in ["credits", "customers", "idempotency", "attachments"]:
		assert(not bool(caps[what]), "%s should not be claimed" % what)
	assert(not ledger.can(LedgerScript.CREDITS))
	assert(ledger.name() == &"akaunting")
	assert(ledger.describe() == "Akaunting at https://books.example.test")


func test_it_is_not_configured_until_the_user_and_the_password_are_stated() -> void:
	var fresh: AkauntingScript = AkauntingScript.new()
	assert(fresh.problems().size() == 3, str(fresh.problems()))
	assert(not fresh.is_configured())
	assert(fresh.describe() == "Akaunting (no address)")
	assert(fresh.settings().size() == 4)
	# Each field it names is a field it accepts, and storing them is what makes it configured. The
	# password is the one setting with no trimming: a password may legitimately begin or end in a space.
	assert(not fresh.set_setting(&"url", "   "))
	assert(fresh.set_setting(&"url", "https://books.example.test"))
	# A field refused for being blank leaves nothing behind, so a blank does not count as configured.
	assert(not fresh.set_setting(&"email", "  "))
	assert(fresh.setting(&"email") == "")
	assert(not fresh.is_configured())
	assert(fresh.set_setting(&"email", "office@example.test"))
	assert(fresh.set_setting(&"password", " hunter2 "))
	assert(fresh.setting(&"password") == " hunter2 ")
	assert(fresh.is_configured())
	assert(fresh.set_setting(&"company", "3"))
	assert(fresh.setting(&"company") == "3")
	assert(not fresh.set_setting(&"token", "x"))


# --- the request -------------------------------------------------------------------------------


func test_a_bare_date_becomes_the_datetime_the_service_validates_against() -> void:
	# Akaunting refuses `2026-06-10` with "the given data failed to pass validation", naming no field.
	assert(AkauntingScript.datetime_of("2026-06-10") == "2026-06-10 00:00:00")
	assert(AkauntingScript.datetime_of("") == "")
	assert(AkauntingScript.datetime_of("  2026-06-10  ") == "2026-06-10 00:00:00")
	# A value that already carries a time is left exactly as it is.
	assert(AkauntingScript.datetime_of("2026-06-10 12:30:00") == "2026-06-10 12:30:00")
	var ledger := _configured()
	var built: Dictionary = _built(ledger, _invoice())
	assert(bool(built["ok"]), String(built["reason"]))
	var body: Dictionary = built["request"]["body"]
	assert(String(body["invoiced_at"]) == "2026-06-10 00:00:00", String(body["invoiced_at"]))
	assert(String(body["due_at"]) == "2026-07-10 00:00:00", String(body["due_at"]))


func test_the_push_carries_http_basic_and_the_headers_the_service_wants() -> void:
	var ledger := _configured()
	var invoice := _invoice()
	var built: Dictionary = _built(ledger, invoice)
	assert(String(built["request"]["method"]) == "POST")
	assert(String(built["request"]["url"]) == "https://books.example.test/api/invoices")
	var headers: Dictionary = built["request"]["headers"]
	assert(String(headers[AkauntingScript.AUTH_HEADER]).begins_with("Basic "),
		String(headers[AkauntingScript.AUTH_HEADER]))
	var encoded: String = String(headers[AkauntingScript.AUTH_HEADER]).substr(6)
	assert(Marshalls.base64_to_utf8(encoded) == "office@example.test:hunter2",
		Marshalls.base64_to_utf8(encoded))
	assert(String(headers["Accept"]) == "application/json")
	assert(String(headers[LedgerScript.KEY_HEADER]) == ledger.key_for_invoice(invoice))
	# No company stated, so no company header: a header nobody asked for is a header a service may act on.
	assert(not headers.has(AkauntingScript.COMPANY_HEADER))
	var many: AkauntingScript = AkauntingScript.new(
		"https://books.example.test", "office@example.test", "hunter2", "3"
	)
	assert(String(many.headers("k")[AkauntingScript.COMPANY_HEADER]) == "3")


func test_the_invoice_figures_travel_because_a_tax_id_here_cannot_be_known() -> void:
	var ledger := _configured()
	var invoice := _invoice()
	var built: Dictionary = _built(ledger, invoice)
	var body: Dictionary = built["request"]["body"]
	assert(String(body["contact_id"]) == CONTACT)
	assert(String(body["customer_name"]) == "Smith")
	assert(String(body["currency_code"]) == "CAD")
	assert(int(body["currency_rate"]) == 1)
	assert(String(body["invoice_number"]) == "INV-2026-0001")
	assert(String(body["notes"]) == "Back garden, phase one")
	# The figures are the invoice's own: 535.50 at 13% is 69.62 of tax and 605.12 in all.
	assert(absf(float(body["amount"]) - 535.5) < 0.001, str(body["amount"]))
	assert(absf(float(body["tax_amount"]) - 69.62) < 0.001, str(body["tax_amount"]))
	assert(absf(float(body["total"]) - 605.12) < 0.001, str(body["total"]))
	var items: Array = body["items"]
	assert(items.size() == 1)
	var item: Dictionary = items[0]
	assert(String(item["name"]) == "Deposit")
	assert(int(item["quantity"]) == 1)
	assert(absf(float(item["price"]) - 535.5) < 0.001, str(item["price"]))
	# No tax ids: the id a tax has inside Akaunting is not a thing this program can know, so it is not
	# guessed at. The amount, the tax and the total are stated instead.
	assert(not item.has("tax_ids"))
	assert(not item.has("taxes"))


# --- what it refuses ----------------------------------------------------------------------------


func test_a_customer_with_no_id_in_the_service_is_refused_rather_than_invented() -> void:
	var ledger := _configured()
	var refused: Dictionary = _built(ledger, _invoice(&"HST-ON", ""))
	assert(not bool(refused["ok"]))
	# Akaunting calls a customer a contact, and the refusal says so in its own vocabulary.
	assert(String(refused["reason"]).contains("no id in Akaunting"), String(refused["reason"]))
	assert(String(refused["reason"]).contains("external_id"), String(refused["reason"]))
	assert((refused["request"] as Dictionary).is_empty())


func test_a_payment_needs_the_invoices_id_here_and_is_dated_the_way_a_date_is() -> void:
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
	assert(String(refused["reason"]).contains("the invoice's id in Akaunting"),
		String(refused["reason"]))
	assert(String(refused["reason"]).contains("when the invoice is first posted"),
		String(refused["reason"]))
	var built: Dictionary = ledger.build_payment_push(
		payment, invoice, ledger.key_for_payment(payment, invoice), "9"
	)
	assert(bool(built["ok"]), String(built["reason"]))
	var body: Dictionary = built["request"]["body"]
	assert(String(body["invoice_id"]) == "9")
	assert(absf(float(body["amount"]) - 535.5) < 0.001, str(body["amount"]))
	assert(String(body["paid_at"]) == "2026-06-20 00:00:00", String(body["paid_at"]))
	assert(String(body["reference"]) == "chq 1041")
	assert(String(built["request"]["url"]) == "https://books.example.test/api/payments")


# --- reading the answer -------------------------------------------------------------------------


func test_it_reads_the_invoice_number_the_service_answers_with() -> void:
	var ledger := _configured()
	var read: Dictionary = ledger.parse_invoice_response({
		"status": 201,
		"body": {"data": {"id": "12", "invoice_number": "INV-2026-0001"}},
	})
	assert(bool(read["ok"]))
	assert(String(read["external_id"]) == "12")
	assert(String(read["external_number"]) == "INV-2026-0001")
	# A 403 is a permission to fix in Akaunting, not a request to try again.
	var forbidden: Dictionary = ledger.parse_invoice_response({
		"status": 403,
		"body": {"message": "Forbidden"},
	})
	assert(not bool(forbidden["ok"]))
	assert(not bool(forbidden["retry"]))
	assert(String(forbidden["reason"]).contains("this credential may not post"),
		String(forbidden["reason"]))
	assert(String(forbidden["reason"]).contains("Forbidden"), String(forbidden["reason"]))


func test_it_cannot_be_tested_or_sent_until_the_transport_exists() -> void:
	var ledger := _configured()
	var tested: Dictionary = ledger.self_test()
	assert(not bool(tested["ok"]))
	assert(String(tested["reason"]).contains("no transport yet"), String(tested["reason"]))
	var sent: Dictionary = ledger.send({"method": "POST", "url": "https://books.example.test"})
	assert(int(sent["status"]) == 0)
	assert(String(sent["error"]).contains("HTTP transport"), String(sent["error"]))
	var unconfigured: AkauntingScript = AkauntingScript.new()
	assert(String(unconfigured.self_test()["reason"]).contains("Akaunting address"),
		String(unconfigured.self_test()["reason"]))