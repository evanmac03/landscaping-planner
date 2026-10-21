class_name CreditNote
extends RefCounted
## A credit note: the document a refund is, and the exact mirror of the charge it reverses (spec
## §9.4).
##
## **A refund is a credit note, not a negative payment.** `Payment` refuses an amount below zero and
## names this document instead, because a payment that went backwards leaves a bookkeeper subtracting
## to find out what actually happened, and an invoice whose own total can move is an invoice whose
## total nobody can trust. A credit note is a document in its own right: it has **its own number and
## its own date**, it says which invoice it credits, and it is what a ledger is asked to post.
##
## Like an invoice it is **never edited after issue** and a **void keeps its number**. The state is a
## function of the records and `from_dict` ignores any state a file happens to carry, exactly as
## `Invoice` does: a stored state would be a second place the truth lives, and a damaged file could
## make a draft look issued.
##
## `mirror_of` is the one thing that needs the invoice: a credit that reverses a charge is the same
## amount to the cent, and `Money`'s single rounding rule is what makes "exact mirror" a fact rather
## than an intention (AC-B4).

const MoneyScript := preload("res://scripts/biz/money.gd")
const RateScript := preload("res://scripts/biz/rate.gd")
const InvoiceScript := preload("res://scripts/biz/invoice.gd")

const DRAFT := 0
const ISSUED := 1
const VOID := 2

## String keys: a StringName literal as a const Dictionary key fails the constant-expression check.
const STATE_NAMES := {
	"DRAFT": "draft",
	"ISSUED": "issued",
	"VOID": "void",
}

## Its own prefix, so a credit note can never be mistaken in a ledger for an invoice.
const NUMBER_PREFIX := "CN"

var id: String = ""
## Empty until it is issued, because a draft has no number (§9.4).
var number: String = ""
var job: String = ""
var customer: Dictionary = {}
var currency: StringName = &"CAD"
var issued_at: String = ""
var amount: Money = null
## The invoice this credits, by its number. A credit note that names nothing is a credit nobody can
## reconcile against anything, so `problems()` counts it.
var against: String = ""
var reason: String = ""
var note: String = ""
var voided_at: String = ""
var voided_why: String = ""


func _init(note_id: String = "") -> void:
	id = note_id
	amount = MoneyScript.zero()


func state_name() -> String:
	return String(STATE_NAMES.get(_state_key(state()), "draft"))


func is_issued() -> bool:
	return not issued_at.strip_edges().is_empty()


func is_void() -> bool:
	return not voided_at.strip_edges().is_empty()


func is_editable() -> bool:
	return not is_issued() and not is_void()


# --- stating it, before it goes out --------------------------------------------------------------


## State the amount. Refused for an unreadable, zero or negative amount: a credit note is a **positive
## document that reverses a charge**, and storing a negative number here would be writing the refund as
## a payment again under another name.
func set_amount(value: Money) -> bool:
	if not is_editable():
		return false
	if value == null or not value.is_valid() or value.cents <= 0:
		return false
	if value.currency != currency:
		return false
	amount = value.copy()
	return true


## State which invoice it credits, and why, in words. Both are required before it can be issued: an
## unexplained credit is a number an office cannot defend at year end.
func set_against(invoice_number: String, why: String) -> bool:
	if not is_editable():
		return false
	if invoice_number.strip_edges().is_empty() or why.strip_edges().is_empty():
		return false
	against = invoice_number.strip_edges()
	reason = why.strip_edges()
	return true


## The credit that exactly mirrors an invoice: the same amount, the same customer, the same job, naming
## the invoice it reverses - and issued, because a mirror of a document that has gone out has gone out
## too. Returns **null** for an invoice that was never issued or whose total cannot be read: there is
## nothing to mirror, and a credit of an unreadable amount is the worst kind of quiet wrong.
static func mirror_of(invoice: Invoice, at: String, note_number: String, why: String = "") -> CreditNote:
	if invoice == null or not invoice.is_issued() or invoice.is_void():
		return null
	var total: Money = invoice.total()
	if not total.is_valid() or total.cents <= 0:
		return null
	var credit: CreditNote = CreditNoteScript.new("")
	credit.job = invoice.job
	credit.customer = invoice.customer.duplicate(true)
	credit.currency = invoice.currency
	credit.amount = total.copy()
	credit.against = invoice.number
	credit.reason = why if not why.strip_edges().is_empty() else "reversing %s" % invoice.number
	var issued: Dictionary = credit.issue(at, note_number)
	if not bool(issued["ok"]):
		return null
	return credit


# --- what it comes to ---------------------------------------------------------------------------


## The state, read off the records: nothing issued is a draft, issued on a date is issued, and a void
## is a void whatever else is true.
func state() -> int:
	if is_void():
		return VOID
	if not is_issued():
		return DRAFT
	return ISSUED


## Everything the page and the window print, named once.
func totals() -> Dictionary:
	return {"amount": amount if amount != null else MoneyScript.zero(currency)}


# --- issuing and voiding ------------------------------------------------------------------------


## Issue it: assign the number and stamp the moment. Refused for a note with nothing stated - no
## amount, no invoice it credits - and for a number or a date nobody could have written.
func issue(at: String, note_number: String) -> Dictionary:
	if is_void():
		return {"ok": false, "reason": "a voided credit note is never reissued - a fresh one is"}
	if is_issued():
		return {"ok": false, "reason": "a credit note is never edited after issue: %s went out on %s" % [number, issued_at]}
	if amount == null or not amount.is_valid() or amount.cents <= 0:
		return {"ok": false, "reason": "a credit note with no amount on it"}
	if against.strip_edges().is_empty():
		return {"ok": false, "reason": "a credit note that credits no invoice"}
	if reason.strip_edges().is_empty():
		return {"ok": false, "reason": "a credit note nobody explained"}
	if note_number.strip_edges().is_empty():
		return {"ok": false, "reason": "a credit note with no number"}
	if not RateScript.is_date(at):
		return {"ok": false, "reason": "an issue date that is not a date: '%s'" % at}
	issued_at = at
	number = note_number.strip_edges()
	return {"ok": true, "reason": ""}


## Void it: keep the number, say when and why. A **draft is not voided** - it has no number to keep
## and is simply deleted.
func mark_void(at: String, why: String) -> bool:
	if not is_issued() or is_void():
		return false
	if why.strip_edges().is_empty():
		return false
	if not RateScript.is_date(at):
		return false
	voided_at = at
	voided_why = why
	return true


func voided_text() -> String:
	if not is_void():
		return ""
	return "voided on %s: %s" % [voided_at, voided_why]


# --- numbering, by the same rule an invoice uses -------------------------------------------------


## A number for a note that has not been issued yet: `CN-2026-0003`.
##
## The highest number already taken in that fiscal year, plus one - **never the count** - for the same
## reason an invoice's is: a count hands the same number out twice the moment anything is voided, and a
## reused number is the one error an auditor does not forgive.
static func next_number(fiscal_year: int, taken: Array) -> String:
	var highest: int = 0
	for entry in taken:
		var text: String = String(entry)
		if year_of(text) != fiscal_year:
			continue
		var sequence: int = sequence_of(text)
		if sequence > highest:
			highest = sequence
	return number_for(fiscal_year, highest + 1)


static func number_for(fiscal_year: int, sequence: int) -> String:
	if fiscal_year <= 0 or sequence <= 0:
		return ""
	return "%s-%04d-%04d" % [NUMBER_PREFIX, fiscal_year, sequence]


## The number part of a credit note number, or -1 when the text is not one of ours.
static func sequence_of(text: String) -> int:
	var parts: PackedStringArray = text.strip_edges().split("-")
	if parts.size() != 3 or parts[0] != NUMBER_PREFIX:
		return -1
	if not parts[2].is_valid_int():
		return -1
	return parts[2].to_int()


static func year_of(text: String) -> int:
	var parts: PackedStringArray = text.strip_edges().split("-")
	if parts.size() != 3 or parts[0] != NUMBER_PREFIX:
		return 0
	if not parts[1].is_valid_int():
		return 0
	return parts[1].to_int()


# --- soundness ----------------------------------------------------------------------------------


func problems() -> Array[String]:
	var out: Array[String] = []
	if id.strip_edges().is_empty():
		out.append("a credit note with no id")
	if job.strip_edges().is_empty():
		out.append("a credit note that belongs to no job")
	if amount == null or not amount.is_valid() or amount.cents <= 0:
		out.append("a credit note whose amount cannot be read")
	if against.strip_edges().is_empty():
		out.append("a credit note that credits no invoice")
	if reason.strip_edges().is_empty():
		out.append("a credit note nobody explained")
	if is_issued() and number.strip_edges().is_empty():
		out.append("an issued credit note with no number")
	if is_void() and voided_why.strip_edges().is_empty():
		out.append("a void with no reason")
	return out


func is_sound() -> bool:
	return problems().is_empty()


func describe() -> String:
	var parts := PackedStringArray()
	parts.append(number if not number.strip_edges().is_empty() else "an unnumbered draft")
	var money: Money = amount if amount != null else MoneyScript.zero(currency)
	parts.append(money.format_with_currency())
	if not against.strip_edges().is_empty():
		parts.append("against %s" % against)
	if not reason.strip_edges().is_empty():
		parts.append(reason)
	parts.append(state_name())
	if is_issued():
		parts.append(issued_at)
	return ", ".join(parts)


# --- persistence --------------------------------------------------------------------------------


func to_dict() -> Dictionary:
	return {
		"id": id,
		"number": number,
		"job": job,
		"customer": customer.duplicate(true),
		"currency": String(currency),
		"issued_at": issued_at,
		"amount": (amount if amount != null else MoneyScript.zero(currency)).to_dict(),
		"against": against,
		"reason": reason,
		"note": note,
		"voided_at": voided_at,
		"voided_why": voided_why,
		# Written for whoever reads the file. `from_dict` ignores it: the state is a function of the
		# records, and a stored one would be a second place the truth lives.
		"state": state_name(),
	}


## A record with no id is **dropped rather than invented**, like every other record here. An amount
## that cannot be read is kept as the invalid amount, so the note refuses to be posted rather than
## quietly crediting nothing.
static func from_dict(data: Dictionary) -> CreditNote:
	var credit: CreditNote = CreditNoteScript.new(String(data.get("id", "")))
	if credit.id.is_empty():
		return null
	credit.number = String(data.get("number", ""))
	credit.job = String(data.get("job", ""))
	var customer_in: Variant = data.get("customer", {})
	credit.customer = (customer_in as Dictionary).duplicate(true) if customer_in is Dictionary else {}
	credit.currency = StringName(data.get("currency", "CAD"))
	credit.issued_at = String(data.get("issued_at", ""))
	credit.amount = MoneyScript.from_dict(data.get("amount", {}))
	credit.against = String(data.get("against", ""))
	credit.reason = String(data.get("reason", ""))
	credit.note = String(data.get("note", ""))
	credit.voided_at = String(data.get("voided_at", ""))
	credit.voided_why = String(data.get("voided_why", ""))
	return credit


static func _state_key(state_key: int) -> String:
	match state_key:
		ISSUED:
			return "ISSUED"
		VOID:
			return "VOID"
	return "DRAFT"


const CreditNoteScript := preload("res://scripts/biz/credit_note.gd")