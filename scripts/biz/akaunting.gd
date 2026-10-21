class_name AkauntingLedger
extends LedgerAdapter
## Akaunting (spec §9.6): HTTP Basic, self-hosted or cloud, an accounting system with ACL permissions.
##
## `POST /api/invoices` with HTTP Basic, a body carrying `contact_id` and `items`, and an answer wrapped
## in `data`. Akaunting gives the invoice API to any user with `read-api`, and every write is checked
## against that user's permissions - which is why a 403 here is a thing to fix in Akaunting and not a
## thing to retry.
##
## **A date is a date *and a time*.** Akaunting validates `invoiced_at` and `due_at` as datetimes -
## `2026-06-10 00:00:00`, not `2026-06-10` - and its refusal is otherwise a generic "the given data
## failed to pass validation" that names no field at all. That is a long afternoon to find by hand, so
## it is a function with a test: `datetime_of`.
##
## **A tax is attached by its id inside Akaunting, which this program cannot know.** So no `tax_ids`
## are sent, and the invoice's own `amount`, `tax_amount` and `total` travel as stated figures beside
## the lines instead. The alternative - sending the lines and hoping Akaunting's own tax setup agrees -
## would post an invoice whose total disagrees with the page the customer was sent.
##
## The rest of the decisions are Invoice Ninja's, for the same reasons: a line is posted as one of one
## at the invoice's own amount, the customer's id in this service is stated rather than invented, a
## payment names the invoice's id here, and no idempotency capability is claimed - nor can this backend
## be tested from here, because a probe has to be sent and the transport that sends is phase 10's.

const INVOICE_PATH := "/api/invoices"
const PAYMENT_PATH := "/api/payments"

const AUTH_HEADER := "Authorization"
const BASIC_PREFIX := "Basic "
const ACCEPT_HEADER := "Accept"
const CONTENT_TYPE_HEADER := "Content-Type"
const JSON_TYPE := "application/json"
## For an installation holding more than one company, which this service needs told.
const COMPANY_HEADER := "X-Company-Id"

## Akaunting calls a customer a **contact**, and the document's customer block carries the id this
## service gave them.
const CONTACT_ID_KEY := "external_id"

var url: String = ""
var email: String = ""
var password: String = ""
var company: String = ""


func _init(base_url: String = "", user_email: String = "", user_password: String = "",
		company_id: String = "") -> void:
	url = base_url
	email = user_email
	password = user_password
	company = company_id


# --- what this backend is -----------------------------------------------------------------------


func name() -> StringName:
	return &"akaunting"


func describe() -> String:
	if url.strip_edges().is_empty():
		return "Akaunting (no address)"
	return "Akaunting at %s" % url.strip_edges()


func settings() -> Array[Dictionary]:
	return [
		{"key": "url", "name": "Address", "secret": false},
		{"key": "email", "name": "Email", "secret": false},
		{"key": "password", "name": "Password", "secret": true},
		{"key": "company", "name": "Company id", "secret": false},
	]


func setting(key: StringName) -> String:
	match key:
		&"url":
			return url
		&"email":
			return email
		&"password":
			return password
		&"company":
			return company
	return ""


func set_setting(key: StringName, value: String) -> bool:
	match key:
		&"url":
			url = value.strip_edges()
			return not url.is_empty()
		&"email":
			email = value.strip_edges()
			return not email.is_empty()
		&"password":
			password = value
			return true
		&"company":
			# Optional: only an installation holding more than one company has one to state.
			company = value.strip_edges()
			return true
	return false


func capabilities() -> Dictionary:
	var out: Dictionary = super()
	out["invoices"] = true
	out["payments"] = true
	out["credits"] = false
	out["customers"] = false
	out["idempotency"] = false
	out["attachments"] = false
	return out


func problems() -> Array[String]:
	var out: Array[String] = []
	if url.strip_edges().is_empty():
		out.append("an Akaunting address")
	if email.strip_edges().is_empty():
		out.append("the email Akaunting reads the API as")
	if password.is_empty():
		out.append("that user's password")
	return out


# --- building a push (pure) ---------------------------------------------------------------------


func invoice_request(invoice: Invoice, idempotency_key: String) -> Dictionary:
	var document: Dictionary = invoice_body(invoice, idempotency_key)
	var unreadable: String = document_refusal(document)
	if not unreadable.is_empty():
		return refused(unreadable)
	var contact: String = party_id_of(document, CONTACT_ID_KEY)
	if contact.is_empty():
		return refused(missing_contact_text())
	var body: Dictionary = {
		"contact_id": contact,
		"customer_name": customer_name_of(document),
		"currency_code": String(document.get("currency_iso", "CAD")),
		"currency_rate": 1,
		"invoiced_at": datetime_of(String(document.get("issued_at", ""))),
		"due_at": datetime_of(String(document.get("due_at", ""))),
		"invoice_number": String(document.get("number", "")),
		"amount": major_units(MoneyScript.from_dict(document.get("subtotal", {}))),
		"tax_amount": major_units(MoneyScript.from_dict(document.get("tax", {}))),
		"total": major_units(MoneyScript.from_dict(document.get("total", {}))),
		"notes": String(document.get("note", "")),
		"items": line_items(document),
	}
	return asked(INVOICE_KIND, make_request(
		&"POST", url.strip_edges() + INVOICE_PATH, headers(idempotency_key), body
	))


func payment_request(payment: Payment, invoice: Invoice, idempotency_key: String,
		external_invoice_id: String = "") -> Dictionary:
	var document: Dictionary = payment_body(payment, invoice, idempotency_key)
	if external_invoice_id.strip_edges().is_empty():
		return refused("a payment needs the invoice's id in %s, which the ledger assigns when the invoice is first posted" % describe())
	var body: Dictionary = {
		"invoice_id": external_invoice_id.strip_edges(),
		"amount": major_units(payment.amount),
		"paid_at": datetime_of(payment.received_at),
		"payment_method": String(payment.method),
		"reference": payment.bank_reference,
		"description": String(document.get("note", "")),
	}
	return asked(PAYMENT_KIND, make_request(
		&"POST", url.strip_edges() + PAYMENT_PATH, headers(idempotency_key), body
	))


## How this service spells a line: one of one at the invoice's own amount, with the quantity and unit
## in the description. See `LedgerAdapter.line_notes` for why the quantity does not travel as one.
func line_items(document: Dictionary) -> Array:
	var items: Array = []
	for entry: Dictionary in lines_of(document):
		items.append({
			"name": String(entry.get("description", "")),
			"quantity": 1,
			"price": major_units(MoneyScript.from_dict(entry.get("amount", {}))),
			"description": line_notes(entry),
		})
	return items


## HTTP Basic, and the company when an installation holds more than one.
func headers(idempotency_key: String) -> Dictionary:
	var out: Dictionary = {
		CONTENT_TYPE_HEADER: JSON_TYPE,
		ACCEPT_HEADER: JSON_TYPE,
		AUTH_HEADER: BASIC_PREFIX + Marshalls.utf8_to_base64("%s:%s" % [email, password]),
	}
	if not company.strip_edges().is_empty():
		out[COMPANY_HEADER] = company.strip_edges()
	if not idempotency_key.strip_edges().is_empty():
		out[KEY_HEADER] = idempotency_key
	return out


func missing_contact_text() -> String:
	return "a customer with no id in %s: create them there and record the id as '%s' on the customer" % [
		describe(), CONTACT_ID_KEY,
	]


# --- a date, the way this service reads one ------------------------------------------------------


## A date as this service's validator wants it: a datetime. `2026-06-10` alone is refused with a
## message that names no field, which is why this is one function with its own test rather than a
## concatenation in two places. A value that already carries a time is left exactly as it is.
static func datetime_of(date: String) -> String:
	var trimmed: String = date.strip_edges()
	if trimmed.is_empty():
		return ""
	if trimmed.length() > 10:
		return trimmed
	return trimmed + " 00:00:00"


# --- reading what came back ---------------------------------------------------------------------


func parse_invoice_response(response: Dictionary) -> Dictionary:
	return _parse_data(response, "id", "invoice_number")


func parse_payment_response(response: Dictionary) -> Dictionary:
	return _parse_data(response, "id", "number")


func self_test() -> Dictionary:
	var missing: Array[String] = problems()
	if not missing.is_empty():
		return {"ok": false, "reason": "%s needs %s" % [describe(), ", ".join(missing)]}
	return {
		"ok": false,
		"reason": "%s is configured, but a probe has to be sent and this build has no transport yet (phase 10)" % describe(),
	}


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