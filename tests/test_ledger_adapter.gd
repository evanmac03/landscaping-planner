extends Node
## The ledger adapter interface: capabilities, the idempotency key, and reading a response (spec §9.6).
##
## Three properties are under test. **A path a backend cannot do refuses rather than drops** (AC-B14):
## the credit path comes back with a refusal naming the backend, never with a silent nothing. **Every
## push carries a key derived from the document and never from the clock** (REQ-B14, AC-B15), so a
## retry collapses onto the first attempt. And **a response is read into a reason a person can act on**
## - a transport failure is a retry, a 401 is not, and the distinction is the difference between an
## office that waits and one that fixes a token.

const LedgerScript := preload("res://scripts/biz/ledger_adapter.gd")
const InvoiceScript := preload("res://scripts/biz/invoice.gd")
const PaymentScript := preload("res://scripts/biz/payment.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")


## A backend that posts invoices and nothing else. The base reports no capabilities at all; this one
## reports exactly one, which is the case AC-B14 is about.
class NoCreditLedger extends LedgerAdapter:
	func name() -> StringName:
		return &"nocredit"

	func describe() -> String:
		return "a backend that posts invoices and nothing else"

	func capabilities() -> Dictionary:
		var out: Dictionary = super()
		out["invoices"] = true
		return out

	func invoice_request(invoice: Invoice, idempotency_key: String) -> Dictionary:
		var headers: Dictionary = {KEY_HEADER: idempotency_key}
		var body: Dictionary = invoice_body(invoice, idempotency_key)
		return asked(INVOICE_KIND, make_request(&"POST", "https://example.test/invoices", headers, body))


func _invoice() -> InvoiceScript:
	var invoice: InvoiceScript = InvoiceScript.new("INV1")
	invoice.job = "J1"
	invoice.customer = {"name": "Smith"}
	invoice.add_amount(InvoiceScript.MILESTONE_LINE, "Deposit", MoneyScript.of(50000), &"HARDSCAPE", &"NONE")
	assert(bool(invoice.issue("2026-06-01", 30, "INV-2026-0001")["ok"]))
	return invoice


func _credit() -> CreditNote:
	var note: CreditNote = CreditNote.new("CN1")
	note.job = "J1"
	note.set_amount(MoneyScript.of(50000))
	note.set_against("INV-2026-0001", "overbilled")
	assert(bool(note.issue("2026-06-20", "CN-2026-0001")["ok"]))
	return note


# --- what a backend declares ---------------------------------------------------------------------


func test_the_capability_table_is_the_six_things_a_backend_can_do() -> void:
	var declared: Array = [
		LedgerScript.INVOICES, LedgerScript.PAYMENTS, LedgerScript.CREDITS,
		LedgerScript.CUSTOMERS, LedgerScript.IDEMPOTENCY, LedgerScript.ATTACHMENTS,
	]
	assert(LedgerScript.CAPABILITY_NAMES.size() == declared.size(), "the table and the names are one list")
	for what: StringName in declared:
		assert(LedgerScript.CAPABILITY_NAMES.has(String(what)), "the table names %s" % String(what))
	var kinds: Array = [LedgerScript.INVOICE_KIND, LedgerScript.PAYMENT_KIND, LedgerScript.CREDIT_KIND]
	assert(LedgerScript.KIND_NAMES.size() == kinds.size())
	for kind: StringName in kinds:
		assert(LedgerScript.KIND_NAMES.has(String(kind)), String(kind))


func test_a_base_adapter_can_do_nothing_and_says_so_in_words() -> void:
	var adapter: LedgerScript = LedgerScript.new()
	var caps: Dictionary = adapter.capabilities()
	# Every key is present, so a caller never has to work out whether a missing key means "no" or
	# "nobody asked".
	assert(caps.size() == 6)
	for key: String in caps.keys():
		assert(not bool(caps[key]), "%s should default to no" % key)
	assert(not adapter.can(LedgerScript.INVOICES))
	assert(adapter.name() == &"")
	assert(adapter.describe() == "no ledger")
	assert(adapter.cannot_text(LedgerScript.CREDITS) == "no ledger cannot post credit notes")
	assert(adapter.is_configured())
	assert(adapter.problems().is_empty())
	# The names are empty rather than absent: a base that named itself would let a subclass forget to.
	assert(adapter.settings().is_empty())
	assert(adapter.setting(&"anything") == "")
	assert(not adapter.set_setting(&"anything", "value"))


func test_a_credit_path_on_a_backend_with_no_credit_capability_refuses_rather_than_dropping() -> void:
	var adapter: NoCreditLedger = NoCreditLedger.new()
	assert(adapter.can(LedgerScript.INVOICES))
	assert(not adapter.can(LedgerScript.CREDITS))
	var refused: Dictionary = adapter.build_credit_push(_credit(), "key-1")
	assert(not bool(refused["ok"]))
	assert(String(refused["reason"]).contains("cannot post credit notes"), String(refused["reason"]))
	assert(String(refused["reason"]).contains("posts invoices and nothing else"), String(refused["reason"]))
	# The refusal is a refusal: there is no request to send, so nothing can be sent by mistake.
	assert((refused["request"] as Dictionary).is_empty())
	# And a thing it *can* do is not refused with it.
	assert(bool(adapter.build_invoice_push(_invoice(), "key-1")["ok"]))


func test_a_backend_that_cannot_post_payments_refuses_them_too() -> void:
	var adapter: LedgerScript = LedgerScript.new()
	var payment: PaymentScript = PaymentScript.new("P1")
	payment.invoice = "INV1"
	payment.received_at = "2026-06-10"
	payment.amount = MoneyScript.of(10000)
	var refused: Dictionary = adapter.build_payment_push(payment, _invoice(), "key-2")
	assert(not bool(refused["ok"]))
	assert(String(refused["reason"]).contains("cannot post payments"), String(refused["reason"]))


# --- building a push ----------------------------------------------------------------------------


func test_a_push_that_could_not_be_built_carries_the_same_shape_as_one_that_could() -> void:
	var adapter: NoCreditLedger = NoCreditLedger.new()
	for built: Dictionary in [
		adapter.build_invoice_push(null, "key"),
		adapter.build_invoice_push(_invoice(), ""),
		adapter.build_credit_push(null, "key"),
	]:
		assert(built.has("ok") and built.has("reason") and built.has("request"), str(built))
		assert(not bool(built["ok"]))


func test_a_draft_is_not_posted_because_it_has_no_number_to_post() -> void:
	var adapter: NoCreditLedger = NoCreditLedger.new()
	var draft: InvoiceScript = InvoiceScript.new("INV2")
	draft.job = "J1"
	draft.add_amount(InvoiceScript.MILESTONE_LINE, "Deposit", MoneyScript.of(100), &"", &"NONE")
	var refused: Dictionary = adapter.build_invoice_push(draft, "key")
	assert(not bool(refused["ok"]))
	assert(String(refused["reason"]).contains("a draft has no number"), String(refused["reason"]))


func test_a_push_with_no_idempotency_key_is_refused_rather_than_built() -> void:
	var adapter: NoCreditLedger = NoCreditLedger.new()
	var refused: Dictionary = adapter.build_invoice_push(_invoice(), "   ")
	assert(not bool(refused["ok"]))
	assert(String(refused["reason"]).contains("no idempotency key"), String(refused["reason"]))


func test_the_request_is_the_shape_every_backend_is_read_by() -> void:
	var adapter: NoCreditLedger = NoCreditLedger.new()
	var invoice := _invoice()
	var built: Dictionary = adapter.build_invoice_push(invoice, "key-7")
	assert(bool(built["ok"]))
	assert(built["kind"] == LedgerScript.INVOICE_KIND)
	var request: Dictionary = built["request"]
	assert(String(request["method"]) == "POST")
	assert(String(request["url"]) == "https://example.test/invoices")
	var headers: Dictionary = request["headers"]
	assert(String(headers[LedgerScript.KEY_HEADER]) == "key-7")
	var body: Dictionary = request["body"]
	assert(String(body["kind"]) == "invoice")
	assert(String(body["client_key"]) == "key-7")
	assert(String(body["number"]) == "INV-2026-0001")


func test_the_body_carries_the_invoices_own_figures_so_nothing_downstream_recomputes_money() -> void:
	var adapter: NoCreditLedger = NoCreditLedger.new()
	var issued := _invoice()
	var body: Dictionary = adapter.invoice_body(issued, "key")
	# The invoice worked these out; the adapter read them. A ledger that re-derived a subtotal would be
	# a second place for the rounding rule to live (§9.5).
	assert(MoneyScript.from_dict(body["subtotal"]).cents == issued.subtotal().cents)
	assert(MoneyScript.from_dict(body["total"]).cents == issued.total().cents)
	assert(MoneyScript.from_dict(body["balance"]).cents == issued.balance().cents)
	assert(String(body["state"]) == issued.state_name())
	assert(String(body["currency_iso"]) == "CAD")
	# Tax is per code with the share it was charged on, which is what a bookkeeper reconciles.
	var tax_rows: Array = body["tax_lines"]
	assert(tax_rows.size() == 1)
	assert(String(tax_rows[0]["tax_code"]) == "NONE")
	assert(MoneyScript.from_dict(tax_rows[0]["taxable"]).cents == 50000)


# --- the idempotency key -------------------------------------------------------------------------


func test_the_idempotency_key_is_derived_from_the_document_and_reads_no_clock() -> void:
	var adapter: NoCreditLedger = NoCreditLedger.new()
	var invoice := _invoice()
	var first: String = adapter.key_for_invoice(invoice)
	# Asked twice, the same answer: nothing in it is a moment.
	assert(adapter.key_for_invoice(invoice) == first)
	assert(first.contains("nocredit:invoice:INV1"), first)
	assert(first.contains("INV-2026-0001"), first)
	assert(first.contains("CAD 500.00"), first)
	# A second invoice is a different document and a different key.
	var other := _invoice()
	other.id = "INV9"
	assert(adapter.key_for_invoice(other) != first)
	# A document with nothing to identify it has no key at all, rather than a shared one.
	assert(adapter.key_for_invoice(null) == "")


func test_a_credit_note_and_an_invoice_never_share_a_key() -> void:
	var adapter: NoCreditLedger = NoCreditLedger.new()
	var invoice := _invoice()
	var note: CreditNote = CreditNote.new("INV1")
	# Even given the same id and the same amount, the kind is part of the key.
	assert(adapter.key_for_credit(note) != adapter.key_for_invoice(invoice))
	assert(adapter.key_for_credit(note).contains(":credit:"), adapter.key_for_credit(note))


# --- reading what came back ---------------------------------------------------------------------


func test_a_request_that_never_reached_the_server_is_a_retry() -> void:
	var adapter: LedgerScript = LedgerScript.new()
	var read: Dictionary = adapter.parse_common({"status": 0, "error": "connection reset"})
	assert(not bool(read["ok"]))
	assert(bool(read["retry"]), "a transport failure is worth trying again")
	assert(String(read["reason"]).contains("connection reset"), String(read["reason"]))


func test_a_refusal_names_the_status_and_the_message_and_is_not_a_retry() -> void:
	var adapter: LedgerScript = LedgerScript.new()
	var bad_token: Dictionary = adapter.parse_common({"status": 401, "body": {}})
	assert(not bool(bad_token["ok"]))
	assert(not bool(bad_token["retry"]))
	assert(String(bad_token["reason"]).contains("401 unauthorized"), String(bad_token["reason"]))
	assert(String(bad_token["reason"]).contains("check the API token"), String(bad_token["reason"]))
	var validation: Dictionary = adapter.parse_common({"status": 422, "body": {"message": "amount is required"}})
	assert(String(validation["reason"]).contains("422"), String(validation["reason"]))
	assert(String(validation["reason"]).contains("amount is required"), String(validation["reason"]))
	var missing: Dictionary = adapter.parse_common({"status": 404, "body": "no such endpoint"})
	assert(String(missing["reason"]).contains("check the ledger's address"), String(missing["reason"]))
	assert(String(missing["reason"]).contains("no such endpoint"), String(missing["reason"]))


func test_a_rate_limit_is_worth_trying_again_and_a_validation_error_is_not() -> void:
	var adapter: LedgerScript = LedgerScript.new()
	assert(bool(adapter.parse_common({"status": 429})["retry"]))
	assert(bool(adapter.parse_common({"status": 503})["retry"]))
	assert(not bool(adapter.parse_common({"status": 400})["retry"]))
	assert(not bool(adapter.parse_common({"status": 409})["retry"]))
	# The message survives whatever shape it arrived in.
	var errors: Dictionary = adapter.parse_common({"status": 422, "body": {"errors": ["a", "b"]}})
	assert(String(errors["reason"]).contains("[\"a\",\"b\"]"), String(errors["reason"]))


func test_a_successful_response_names_the_document_the_ledger_made() -> void:
	var adapter: LedgerScript = LedgerScript.new()
	var read: Dictionary = adapter.parse_invoice_response({
		"status": 201,
		"body": {"id": "42", "number": "INV-2026-0001"},
	})
	assert(bool(read["ok"]))
	assert(not bool(read["retry"]))
	assert(String(read["external_id"]) == "42")
	assert(String(read["external_number"]) == "INV-2026-0001")
	# A 200 with nothing in the body is still a success: not every backend answers with the document.
	var quiet: Dictionary = adapter.parse_invoice_response({"status": 204, "body": {}})
	assert(bool(quiet["ok"]))
	assert(String(quiet["external_id"]) == "")


func test_a_base_adapter_has_no_transport_and_says_so_rather_than_pretending() -> void:
	var adapter: LedgerScript = LedgerScript.new()
	var sent: Dictionary = adapter.send({"method": "POST", "url": "https://example.test"})
	assert(int(sent["status"]) == 0)
	assert(String(sent["error"]).contains("no transport of its own"), String(sent["error"]))
	var tested: Dictionary = adapter.self_test()
	assert(not bool(tested["ok"]))
	assert(String(tested["reason"]).contains("cannot test itself"), String(tested["reason"]))


# --- reading the document every backend is built from -------------------------------------------


func test_a_document_is_read_the_same_way_by_every_backend() -> void:
	var document: Dictionary = {
		"customer": {"name": "Smith", "external_id": "  42  "},
		"lines": [{"amount": {"cents": 100, "currency": "CAD"}}, "not a line", 7],
	}
	# A line that is not a line is left out rather than crashing a builder three call frames down.
	assert(LedgerScript.lines_of(document).size() == 1)
	assert(LedgerScript.lines_of({}).is_empty())
	assert(LedgerScript.customer_name_of(document) == "Smith")
	assert(LedgerScript.customer_name_of({"customer": {"company": "Smith Landscaping"}}) == "Smith Landscaping")
	assert(LedgerScript.customer_name_of({}) == "")
	# The id in the backend being posted to is trimmed: an id with a space in it is an id nobody pasted
	# on purpose.
	assert(LedgerScript.party_id_of(document) == "42")
	assert(LedgerScript.party_id_of({"customer": {}}) == "")
	assert(LedgerScript.party_id_of({}) == "")


func test_a_line_states_its_quantity_when_there_is_more_than_one_of_them() -> void:
	var one: Dictionary = {"description": "Deposit", "quantity_milli": 1000, "unit": "EACH"}
	var many: Dictionary = {"description": "Sod", "quantity_milli": 3500, "unit": "SQ_FT"}
	assert(LedgerScript.line_notes(one) == "Deposit")
	assert(LedgerScript.line_notes(many) == "Sod, 3.5 SQ_FT")
	# A line with no quantity at all still reads as its description rather than as a stray comma.
	assert(LedgerScript.line_notes({"description": "Deposit"}) == "Deposit")


func test_a_machines_amount_is_a_number_and_not_a_persons_amount() -> void:
	assert(absf(LedgerScript.major_units(MoneyScript.of(53550)) - 535.5) < 0.000001)
	assert(absf(LedgerScript.major_units(MoneyScript.of(-53550)) + 535.5) < 0.000001)
	assert(absf(LedgerScript.major_units(MoneyScript.of(0)) - 0.0) < 0.000001)
	# An amount that cannot be read is not a number either, and zero is the only thing a float can
	# honestly say - which is why every builder reads `is_valid` before it reads the figures.
	assert(absf(LedgerScript.major_units(MoneyScript.invalid())) < 0.000001)
	# A currency with no decimals has no decimal point to lose.
	assert(absf(LedgerScript.major_units(MoneyScript.of(535, &"JPY")) - 535.0) < 0.000001)
	assert(LedgerScript.plain_quantity(3500) == "3.5")
	assert(LedgerScript.plain_quantity(0) == "")


func test_the_tax_rate_told_to_an_api_is_read_off_the_published_table() -> void:
	# Not worked out here: 13% is the table's own figure for HST-ON, and 12% is GST and PST added up.
	assert(absf(LedgerScript.tax_percent(&"HST-ON") - 13.0) < 0.000001)
	assert(absf(LedgerScript.tax_percent(&"GST-PST-BC") - 12.0) < 0.000001)
	assert(absf(LedgerScript.tax_percent(&"NONE")) < 0.000001)
	# A code the table does not have comes back as zero, and the invoice's own `tax_lines` are what say
	# whether it could be charged at all - which is what `document_refusal` reads.
	assert(absf(LedgerScript.tax_percent(&"NO-SUCH-CODE")) < 0.000001)


func test_a_document_that_says_what_is_wrong_with_it_is_refused_in_those_words() -> void:
	var clean: Dictionary = {
		"total": {"cents": 100, "currency": "CAD"},
		"tax_lines": [{"tax_code": "NONE", "ok": true, "reason": ""}],
	}
	assert(LedgerScript.document_refusal(clean) == "")
	var taxed: Dictionary = {
		"total": {"cents": 100, "currency": "CAD"},
		"tax_lines": [{"tax_code": "GONE", "ok": false, "reason": "unknown tax code 'GONE'"}],
	}
	assert(LedgerScript.document_refusal(taxed) == "unknown tax code 'GONE'",
		LedgerScript.document_refusal(taxed))
	var unreadable: Dictionary = {
		"total": MoneyScript.invalid().to_dict(),
		"tax_lines": [],
	}
	assert(LedgerScript.document_refusal(unreadable) == "the invoice's total cannot be read",
		LedgerScript.document_refusal(unreadable))