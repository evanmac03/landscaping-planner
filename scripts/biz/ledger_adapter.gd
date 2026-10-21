class_name LedgerAdapter
extends RefCounted
## What the business module needs from whatever keeps the books (spec §9.6).
##
## A ledger adapter is the one place that knows how somebody else's system spells an invoice. It is
## **pure on the way out** - `build_invoice_push` returns a request and does not send it - so a push
## can be built, checked, queued, retried and compared without a network or a server. That is also the
## only half of this a test can honestly cover: a live server is a deployment, a recorded fixture is
## the other half (§9.6).
##
## Two rules the base class enforces, so that a backend cannot get them wrong by forgetting:
##
## **A capability is a property, and a path a backend cannot do refuses rather than drops.**
## `capabilities()` answers what this backend can do, every `build_*_push` asks it first, and a path
## that is not supported comes back as `{ok: false, reason: ...}` naming the backend and the thing it
## cannot do. A credit note quietly turned into nothing is a customer who was never credited, and the
## office would go on believing the books agreed with the program (AC-B14).
##
## **Every push carries an idempotency key derived from the document, never from the clock.** A retry
## after a timeout has to collapse onto the first attempt; a key built from the moment would post the
## invoice a second time, which is the one error a bookkeeper will not forgive (REQ-B14, AC-B15).
## `idempotency_key_for` and the `key_for_*` helpers are the one place a key is made, and none of them
## reads a clock.
##
## The **file backend is the default** and needs no service at all: an invoice issues and prints
## whether or not a ledger is configured, and the push is a queued, retryable, idempotent action with a
## visible state (REQ-B14).

const InvoiceScript := preload("res://scripts/biz/invoice.gd")
const PaymentScript := preload("res://scripts/biz/payment.gd")
const CreditScript := preload("res://scripts/biz/credit_note.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")

## The six things a backend either can or cannot do. Every key of `CAPABILITY_NAMES` is always present
## in `capabilities()`, so a caller never has to work out whether a missing key means "no" or "not
## asked" - which is the difference between a backend that cannot post credits and one nobody asked.
const INVOICES := &"invoices"
const PAYMENTS := &"payments"
const CREDITS := &"credits"
const CUSTOMERS := &"customers"
const IDEMPOTENCY := &"idempotency"
const ATTACHMENTS := &"attachments"

## String keys: a StringName literal as a const Dictionary key fails the constant-expression check.
## A test holds this table and the six names above to be the same six things.
const CAPABILITY_NAMES := {
	"invoices": "post invoices",
	"payments": "post payments",
	"credits": "post credit notes",
	"customers": "create customers",
	"idempotency": "de-duplicate a retry",
	"attachments": "attach a document",
}

## The kinds of document a push can be for.
const INVOICE_KIND := &"invoice"
const PAYMENT_KIND := &"payment"
const CREDIT_KIND := &"credit"
const KIND_NAMES := {
	"invoice": "invoice",
	"payment": "payment",
	"credit": "credit note",
}

## The header a backend that de-duplicates reads. Carried on every request whether or not the backend
## reads it: a header nobody reads costs nothing, and a missing one costs a duplicate posting.
const KEY_HEADER := "Idempotency-Key"

## The codes that mean the backend took it. Anything else is read by `_status_reason`.
const FIRST_SUCCESS := 200
const LAST_SUCCESS := 299

## The codes worth trying again - the server was busy, or the request timed out. Everything else is
## something a person has to fix, and retrying it only sends the same mistake again.
const RETRYABLE := [408, 425, 429, 500, 502, 503, 504]

## The fields a response message is usually under, in the order they are looked for.
const MESSAGE_FIELDS := ["message", "error", "detail", "errors"]


# --- what this backend is -----------------------------------------------------------------------


## This backend's own name, for a menu line and for a push record. Empty in the base: a base that named
## itself would let a subclass forget to.
func name() -> StringName:
	return &""


## One line for a person: what this backend is, and where it keeps things.
func describe() -> String:
	return "no ledger"


## The fields this backend needs, in the order a settings page shows them: `{key, name, secret}`.
## The file backend needs none, which is part of why it is the default.
func settings() -> Array[Dictionary]:
	return []


func setting(_key: StringName) -> String:
	return ""


## Refused for a field this backend does not have, so a settings page cannot store a value that will
## never be read into a backend that will go on behaving as if it were unconfigured.
func set_setting(_key: StringName, _value: String) -> bool:
	return false


## What this backend can do (§9.6). Every capability is present and defaults to false.
func capabilities() -> Dictionary:
	var out: Dictionary = {}
	for key: String in CAPABILITY_NAMES.keys():
		out[key] = false
	return out


func can(what: StringName) -> bool:
	return bool(capabilities().get(String(what), false))


## The refusal a path this backend cannot do gives, naming both the backend and the thing (AC-B14).
func cannot_text(what: StringName) -> String:
	return "%s cannot %s" % [describe(), String(CAPABILITY_NAMES.get(String(what), "do that"))]


## Whether it has everything it needs to be used at all, which is exactly "there is nothing wrong with
## its settings". A hosted backend with no credential is not configured; the file backend is configured
## out of the box, which is why it is the default.
func is_configured() -> bool:
	return problems().is_empty()


func problems() -> Array[String]:
	return []


# --- the idempotency key (one place, and it reads no clock) --------------------------------------


## The key for a document: **derived from the document, never from the moment.** A retry after a
## timeout must produce the same key, so the backend can collapse it onto the first attempt. `marker`
## is whatever identifies the *version* being posted - a number and a total - so a void and reissue is
## a different push rather than a duplicate of the first (REQ-B14, AC-B15).
static func idempotency_key_for(adapter: StringName, kind: StringName, document_id: String,
		marker: String) -> String:
	return "%s:%s:%s:%s" % [String(adapter), String(kind), document_id, marker]


func key_for_invoice(invoice: Invoice) -> String:
	if invoice == null:
		return ""
	return idempotency_key_for(name(), INVOICE_KIND, invoice.id,
		"%s@%s" % [invoice.number, invoice.total().format_iso()])


func key_for_payment(payment: Payment, invoice: Invoice) -> String:
	if payment == null or invoice == null:
		return ""
	return idempotency_key_for(name(), PAYMENT_KIND, payment.id,
		"%s@%s" % [payment.amount.format_iso(), payment.received_at])


func key_for_credit(credit: CreditNote) -> String:
	if credit == null:
		return ""
	return idempotency_key_for(name(), CREDIT_KIND, credit.id,
		"%s@%s" % [credit.number, credit.amount.format_iso()])


# --- building a push (pure: it builds, it does not send) ------------------------------------------


## The request that posts an invoice, or a refusal saying why this backend cannot. **Pure.**
func build_invoice_push(invoice: Invoice, idempotency_key: String) -> Dictionary:
	if not can(INVOICES):
		return refused(cannot_text(INVOICES))
	if invoice == null:
		return refused("there is no invoice to post")
	if not invoice.is_issued():
		return refused("a draft has no number, so there is nothing to post: issue it first")
	if idempotency_key.strip_edges().is_empty():
		return refused("a push with no idempotency key")
	return invoice_request(invoice, idempotency_key)


## The request that posts a payment against an invoice, or a refusal. **Pure.**
func build_payment_push(payment: Payment, invoice: Invoice, idempotency_key: String) -> Dictionary:
	if not can(PAYMENTS):
		return refused(cannot_text(PAYMENTS))
	if payment == null or invoice == null:
		return refused("there is no payment to post")
	if idempotency_key.strip_edges().is_empty():
		return refused("a push with no idempotency key")
	return payment_request(payment, invoice, idempotency_key)


## The request that posts a credit note, or a refusal. **Pure.** This is the path AC-B14 is about: a
## backend that declares no credit capability refuses here, in words, rather than posting nothing.
func build_credit_push(credit: CreditNote, idempotency_key: String) -> Dictionary:
	if not can(CREDITS):
		return refused(cannot_text(CREDITS))
	if credit == null:
		return refused("there is no credit note to post")
	if not credit.is_issued():
		return refused("a draft has no number, so there is nothing to post: issue it first")
	if idempotency_key.strip_edges().is_empty():
		return refused("a push with no idempotency key")
	return credit_request(credit, idempotency_key)


## A backend's own invoice request. The base has none: a backend that says it can post invoices and
## then does not is a bug, and saying so is better than posting nothing at all.
func invoice_request(_invoice: Invoice, _idempotency_key: String) -> Dictionary:
	return refused("%s has no invoice path" % describe())


func payment_request(_payment: Payment, _invoice: Invoice, _idempotency_key: String) -> Dictionary:
	return refused("%s has no payment path" % describe())


func credit_request(_credit: CreditNote, _idempotency_key: String) -> Dictionary:
	return refused("%s has no credit path" % describe())


# --- the API-neutral document the body is made of -------------------------------------------------


## The document a ledger is asked to keep, from the invoice's own `to_dict()`. One shape, so the file
## backend writes it and a hosted backend reshapes it from the same source: two builders would be two
## places for the figures to be worked out, and the invoice already owns that (spec §9.5).
func invoice_body(invoice: Invoice, idempotency_key: String) -> Dictionary:
	var body: Dictionary = invoice.to_dict()
	body["kind"] = String(INVOICE_KIND)
	body["client_key"] = idempotency_key
	body["currency_iso"] = String(invoice.currency)
	body.merge(totals_body(invoice))
	return body


## The invoice's own figures, in a JSON-safe form, so that **nothing downstream recomputes money**. A
## ledger that re-derived a subtotal would be a second place for the rounding rule to live, and the day
## the two disagreed the printed page and the posted document would be different documents (§9.5).
## Tax is per code with the share it was charged on, because that is what a bookkeeper reconciles.
func totals_body(invoice: Invoice) -> Dictionary:
	var tax_rows: Array = []
	for entry in invoice.tax_lines():
		tax_rows.append({
			"tax_code": String(entry["tax_code"]),
			"taxable": (entry["taxable"] as Money).to_dict(),
			"tax": (entry["tax"] as Money).to_dict(),
			"ok": bool(entry["ok"]),
			"reason": String(entry["reason"]),
		})
	return {
		"subtotal": invoice.subtotal().to_dict(),
		"tax": invoice.tax().to_dict(),
		"retainage_total": (invoice.retainage if invoice.retainage != null else MoneyScript.zero(invoice.currency)).to_dict(),
		"total": invoice.total().to_dict(),
		"applied": invoice.applied().to_dict(),
		"balance": invoice.balance().to_dict(),
		"state": invoice.state_name(),
		"tax_lines": tax_rows,
	}


func payment_body(payment: Payment, invoice: Invoice, idempotency_key: String) -> Dictionary:
	var body: Dictionary = payment.to_dict()
	body["kind"] = String(PAYMENT_KIND)
	body["client_key"] = idempotency_key
	body["invoice_number"] = invoice.number
	body["currency_iso"] = String(invoice.currency)
	return body


func credit_body(credit: CreditNote, idempotency_key: String) -> Dictionary:
	var body: Dictionary = credit.to_dict()
	body["kind"] = String(CREDIT_KIND)
	body["client_key"] = idempotency_key
	body["currency_iso"] = String(credit.currency)
	return body


# --- reading what came back ---------------------------------------------------------------------


func parse_invoice_response(response: Dictionary) -> Dictionary:
	return _parse_document(response, "id", "number")


func parse_payment_response(response: Dictionary) -> Dictionary:
	return _parse_document(response, "id", "number")


func parse_credit_response(response: Dictionary) -> Dictionary:
	return _parse_document(response, "id", "number")


## Read a response that is not about one of our documents at all - a capability probe, a settings
## test. Returns the same shape, with no external id.
func parse_common(response: Dictionary) -> Dictionary:
	var status: int = int(response.get("status", 0))
	var error_text: String = String(response.get("error", ""))
	var raw: Variant = response.get("body", {})
	var body: Dictionary = {}
	if raw is Dictionary:
		body = raw
	if status == 0:
		var why: String = error_text if not error_text.strip_edges().is_empty() else "it returned nothing"
		return _result(false, true, "the request did not reach %s: %s" % [describe(), why], status, body)
	if status < FIRST_SUCCESS or status > LAST_SUCCESS:
		return _result(false, _is_retryable(status), _status_reason(status, body, raw), status, body)
	return _result(true, false, "", status, body)


# --- the pieces every adapter needs -------------------------------------------------------------


## The request that posts a document. `make_request` is the one place a request is shaped, and `url`
## is a URL for an HTTP backend and a path for the file backend - because what `send` understands is
## the backend's own business, which is why `send` is overridden rather than assumed.
static func make_request(method: StringName, url: String, headers: Dictionary,
		body: Dictionary) -> Dictionary:
	return {
		"method": String(method),
		"url": url,
		"headers": headers.duplicate(true),
		"body": body,
	}


## Actually send a request. **The base has no transport of its own**: phase 10's sync does HTTP, and
## the file backend writes its own files. A backend that cannot send says so rather than pretending, so
## a push against it fails visibly instead of quietly doing nothing.
func send(_request: Dictionary) -> Dictionary:
	return {"status": 0, "error": "%s has no transport of its own" % describe(), "body": {}}


## The adapter's "test" button: prove this backend is reachable and will take a document, without
## posting anything that matters. The base cannot, and says so.
func self_test() -> Dictionary:
	return {"ok": false, "reason": "%s cannot test itself" % describe()}


## A refusal, in the shape every `build_*_push` returns.
static func refused(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "kind": &"", "request": {}}


## An accepted build, in the same shape.
static func asked(kind: StringName, request: Dictionary) -> Dictionary:
	return {"ok": true, "reason": "", "kind": kind, "request": request}


func _parse_document(response: Dictionary, id_field: String, number_field: String) -> Dictionary:
	var common: Dictionary = parse_common(response)
	if bool(common["ok"]):
		var body: Dictionary = common["body"]
		common["external_id"] = String(body.get(id_field, ""))
		common["external_number"] = String(body.get(number_field, ""))
	return common


static func _result(ok: bool, retry: bool, reason: String, status: int, body: Dictionary,
		external_id: String = "", external_number: String = "") -> Dictionary:
	return {
		"ok": ok,
		"retry": retry,
		"reason": reason,
		"status": status,
		"body": body,
		"external_id": external_id,
		"external_number": external_number,
	}


static func _is_retryable(status: int) -> bool:
	if status in RETRYABLE:
		return true
	return status >= 500 and status <= 599


## Why a status was not a success, in words an office can act on: "401 unauthorized: check the API
## token" is a thing somebody can fix, and "request failed" is not.
static func _status_reason(status: int, body: Dictionary, raw: Variant) -> String:
	var because: String = _because(_message_of(body, raw))
	match status:
		400:
			return "400 the ledger refused the request%s" % because
		401:
			return "401 unauthorized: check the API token%s" % because
		403:
			return "403 forbidden: this credential may not post%s" % because
		404:
			return "404 not found: check the ledger's address%s" % because
		409:
			return "409 the ledger already has a document under that key%s" % because
		422:
			return "422 the ledger would not accept the document%s" % because
		429:
			return "429 the ledger is rate limiting; try again shortly%s" % because
	if _is_retryable(status):
		return "%d the ledger had a server error; try again%s" % [status, because]
	return "%d the ledger refused the request%s" % [status, because]


static func _because(detail: String) -> String:
	return "" if detail.strip_edges().is_empty() else ": " + detail.strip_edges()


## The message a server sent with its refusal, from wherever it usually hides one. A JSON body with a
## `message` is read; so is a plain string; an array or an object of validation errors is serialised
## rather than dropped, because "422" alone tells nobody which field was wrong.
static func _message_of(body: Dictionary, raw: Variant) -> String:
	for field: String in MESSAGE_FIELDS:
		if not body.has(field):
			continue
		var value: Variant = body[field]
		if value is String:
			return String(value)
		if value is Array or value is Dictionary:
			return JSON.stringify(value)
	if raw is String:
		return String(raw)
	return ""