class_name InvoiceNinjaLedger
extends LedgerAdapter
## Invoice Ninja v5 (spec §9.6): REST with an API token, self-hosted or in the cloud.
##
## The shape of a push here is the shape the service documents: `POST /api/v1/invoices` carrying
## `X-API-TOKEN` and `X-Requested-With: XMLHttpRequest`, a body with `client_id` and `line_items`, and
## an answer wrapped in `data`. The headers are the ones the service requires on **every** request; the
## idempotency key rides beside them and in the body as `custom_value1`, so a backend that wants to
## de-duplicate has something to de-duplicate on.
##
## Four things about this adapter are decisions rather than transcription:
##
## **A line is posted as one of one, at the amount the invoice worked out.** Invoice Ninja multiplies a
## line's quantity by its cost itself, and a fractional quantity that rounds a cent differently there
## would make the ledger and the printed page two different documents. `quantity: 1` with
## `cost: <the line's own amount>` means the money on the ledger is the money on the page; the quantity
## and its unit are stated in the line's notes, where a person reads them.
##
## **The customer's id in this service is stated, not invented.** A push whose customer carries no
## `external_id` is refused and named: the office creates the client in Invoice Ninja once and records
## the id, because an invoice posted against a client this program believed in is a document nobody can
## reconcile.
##
## **No idempotency capability is claimed.** This service has no de-duplication this program can rely
## on, so a retry that arrives twice is caught by the invoice number already being taken - a visible
## failure rather than a silent duplicate. That is why the capability is reported rather than assumed:
## a caller that needs a guaranteed single posting has to know it is not getting one here.
##
## **It cannot be tested from here.** A probe would have to be sent, and the transport that sends is
## phase 10's; the test button says so rather than pretending, and so does `send`.

## The cloud address. A business running its own instance sets this to its own address.
const DEFAULT_URL := "https://invoicing.co"
const INVOICE_PATH := "/api/v1/invoices"
const PAYMENT_PATH := "/api/v1/payments"

const TOKEN_HEADER := "X-API-TOKEN"
const REQUESTED_WITH_HEADER := "X-Requested-With"
const XML_HTTP_REQUEST := "XMLHttpRequest"
const CONTENT_TYPE_HEADER := "Content-Type"
const JSON_TYPE := "application/json"

## The field the office records this service's client id under, on the document's customer block.
const CLIENT_ID_KEY := "external_id"
## Where the key rides in the body, for a backend that reads it there rather than out of the header.
const KEY_FIELD := "custom_value1"

var url: String = DEFAULT_URL
var token: String = ""


func _init(base_url: String = DEFAULT_URL, api_token: String = "") -> void:
	url = base_url
	token = api_token


# --- what this backend is -----------------------------------------------------------------------


func name() -> StringName:
	return &"invoice_ninja"


func describe() -> String:
	if url.strip_edges().is_empty():
		return "Invoice Ninja (no address)"
	return "Invoice Ninja at %s" % url.strip_edges()


func settings() -> Array[Dictionary]:
	return [
		{"key": "url", "name": "Address", "secret": false},
		{"key": "token", "name": "API token", "secret": true},
	]


func setting(key: StringName) -> String:
	if key == &"url":
		return url
	if key == &"token":
		return token
	return ""


func set_setting(key: StringName, value: String) -> bool:
	if key == &"url":
		url = value.strip_edges()
		return not url.is_empty()
	if key == &"token":
		token = value.strip_edges()
		return true
	return false


func capabilities() -> Dictionary:
	var out: Dictionary = super()
	out["invoices"] = true
	out["payments"] = true
	# It declares what this adapter does, not what the service might be able to do: nothing here posts
	# a credit note, creates a client, or attaches a document, so none of those is claimed.
	out["credits"] = false
	out["customers"] = false
	out["idempotency"] = false
	out["attachments"] = false
	return out


func problems() -> Array[String]:
	var out: Array[String] = []
	if url.strip_edges().is_empty():
		out.append("an Invoice Ninja address")
	if token.strip_edges().is_empty():
		out.append("an Invoice Ninja API token")
	return out


## The one header this service authenticates with. It is what keeps the token out of the outbox file
## and what lets a rotated token be the one that goes out.
func secret_headers() -> Array[String]:
	return [TOKEN_HEADER]


func authorise(request: Dictionary) -> Dictionary:
	var ready: Dictionary = request.duplicate(true)
	var headers_in: Variant = ready.get("headers", {})
	var sent: Dictionary = headers_in if headers_in is Dictionary else {}
	sent[TOKEN_HEADER] = token
	ready["headers"] = sent
	return ready


# --- building a push (pure) ---------------------------------------------------------------------


func invoice_request(invoice: Invoice, idempotency_key: String) -> Dictionary:
	var document: Dictionary = invoice_body(invoice, idempotency_key)
	var unreadable: String = document_refusal(document)
	if not unreadable.is_empty():
		return refused(unreadable)
	var client: String = party_id_of(document, CLIENT_ID_KEY)
	if client.is_empty():
		return refused(missing_client_text())
	var body: Dictionary = {
		"client_id": client,
		"date": String(document.get("issued_at", "")),
		"due_date": String(document.get("due_at", "")),
		"number": String(document.get("number", "")),
		"public_notes": String(document.get("note", "")),
		"discount": 0,
		"line_items": line_items(document),
		KEY_FIELD: idempotency_key,
	}
	return asked(INVOICE_KIND, make_request(
		&"POST", url.strip_edges() + INVOICE_PATH, headers(idempotency_key), body
	))


func payment_request(payment: Payment, invoice: Invoice, idempotency_key: String,
		external_invoice_id: String = "") -> Dictionary:
	var document: Dictionary = payment_body(payment, invoice, idempotency_key)
	var client: String = party_id_of(document, CLIENT_ID_KEY)
	if client.is_empty():
		return refused(missing_client_text())
	if external_invoice_id.strip_edges().is_empty():
		return refused("a payment needs the invoice's id in %s, which the ledger assigns when the invoice is first posted" % describe())
	var amount: float = major_units(payment.amount)
	var body: Dictionary = {
		"client_id": client,
		"amount": amount,
		"date": payment.received_at,
		"transaction_reference": payment.bank_reference,
		"invoices": [{"invoice_id": external_invoice_id.strip_edges(), "amount": amount}],
		KEY_FIELD: idempotency_key,
	}
	return asked(PAYMENT_KIND, make_request(
		&"POST", url.strip_edges() + PAYMENT_PATH, headers(idempotency_key), body
	))


## How this service spells a line: one of one at the invoice's own amount. See the class note for why.
func line_items(document: Dictionary) -> Array:
	var items: Array = []
	for entry: Dictionary in lines_of(document):
		var item: Dictionary = {
			"quantity": 1,
			"cost": major_units(MoneyScript.from_dict(entry.get("amount", {}))),
			"product_key": String(entry.get("cost_code", "")),
			"notes": line_notes(entry),
		}
		var code: String = String(entry.get("tax_code", "NONE")).strip_edges()
		if not code.is_empty() and code != "NONE" and code != "EXEMPT":
			item["tax_name1"] = code
			item["tax_rate1"] = tax_percent(StringName(code))
		items.append(item)
	return items


func headers(idempotency_key: String) -> Dictionary:
	var out: Dictionary = {
		CONTENT_TYPE_HEADER: JSON_TYPE,
		TOKEN_HEADER: token,
		REQUESTED_WITH_HEADER: XML_HTTP_REQUEST,
	}
	if not idempotency_key.strip_edges().is_empty():
		out[KEY_HEADER] = idempotency_key
	return out


func missing_client_text() -> String:
	return "a customer with no id in %s: create them there and record the id as '%s' on the customer" % [
		describe(), CLIENT_ID_KEY,
	]


# --- reading what came back ---------------------------------------------------------------------


## This service answers with the document inside `data`. An answer that carries none is still a
## success: the request was taken, and not every backend echoes the document back.
func parse_invoice_response(response: Dictionary) -> Dictionary:
	return _parse_data(response, "id", "number")


func parse_payment_response(response: Dictionary) -> Dictionary:
	return _parse_data(response, "id", "number")


## The adapter's "test" button: **it cannot test itself yet**, and it says so. A probe would have to be
## sent, and the transport that sends arrives with sync (phase 10). A green light that verified nothing
## would be worse than no button.
func self_test() -> Dictionary:
	var missing: Array[String] = problems()
	if not missing.is_empty():
		return {"ok": false, "reason": "%s needs %s" % [describe(), ", ".join(missing)]}
	return {
		"ok": false,
		"reason": "%s is configured, but a probe has to be sent and this build has no transport yet (phase 10)" % describe(),
	}


## Seeing this backend needs HTTP. A push against it fails visibly until sync arrives rather than
## pretending to have posted, which REQ-B14 asks for in the other direction: the workflow never blocks.
func send(_request: Dictionary) -> Dictionary:
	return {
		"status": 0,
		"error": "posting to %s needs the HTTP transport, which arrives with sync (phase 10)" % describe(),
		"body": {},
	}


func _parse_data(response: Dictionary, id_field: String, number_field: String) -> Dictionary:
	var read: Dictionary = parse_common(response)
	if bool(read["ok"]):
		var made: Dictionary = {}
		var body: Dictionary = read["body"]
		var data_in: Variant = body.get("data", {})
		if data_in is Dictionary:
			made = data_in
		read["external_id"] = String(made.get(id_field, ""))
		read["external_number"] = String(made.get(number_field, ""))
	return read