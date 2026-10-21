class_name Payment
extends RefCounted
## Money received against an invoice (spec §4.12, §9.4).
##
## A payment is its own record rather than a number on the invoice, because the two questions a
## business asks are different questions: "has the customer been invoiced" is a fact about the
## invoice, and "has the money arrived" is a fact about the bank. An invoice with a `paid_amount`
## field cannot say *when* anything arrived, or by what route, which is the first thing a bookkeeper
## asks when a balance does not match.
##
## **A refund is a credit note, not a negative payment.** An amount below zero is refused rather than
## accepted, so `applied()` can only grow and no "payment" can quietly write off a balance without
## anything having been said about why. A payment larger than the balance is refused by the invoice
## rather than clamped - clamping one hides a duplicate remittance, which is the error that costs the
## customer money and the business the trust.

const MoneyScript := preload("res://scripts/biz/money.gd")

## How the money arrived. `other` is a real answer - a trade, a barter, a rounding cheque - and a
## method nobody has is refused, so a typo cannot become a seventh method.
const METHODS := [&"cheque", &"e-transfer", &"cash", &"card", &"transfer", &"other"]

## String keys: a StringName literal as a const Dictionary key fails the constant-expression check.
const METHOD_NAMES := {
	"cheque": "cheque",
	"e-transfer": "e-transfer",
	"cash": "cash",
	"card": "card",
	"transfer": "bank transfer",
	"other": "other",
}

var id: String = ""
## The invoice this is applied to, by id.
var invoice: String = ""
var received_at: String = ""
var amount: Money = null
var method: StringName = &"cheque"
## A cheque number, a transfer reference, a receipt number: whatever the bank will show. Named
## `bank_reference` and not `reference`, because `Object.reference` is a method of every script here.
var bank_reference: String = ""
var note: String = ""


func _init(payment_id: String = "") -> void:
	id = payment_id
	amount = MoneyScript.zero()


static func is_method(candidate: StringName) -> bool:
	return METHODS.has(candidate)


static func method_name(candidate: StringName) -> String:
	return String(METHOD_NAMES.get(String(candidate), "other"))


## The one thing wrong with this record, or "" when there is nothing wrong with it. One problem
## reported rather than all of them, so a list of payments reads as a list of complaints.
func problem() -> String:
	if id.strip_edges().is_empty():
		return "a payment with no id"
	if invoice.strip_edges().is_empty():
		return "a payment that names no invoice"
	if received_at.strip_edges().is_empty():
		return "a payment with no date"
	if amount == null or not amount.is_valid():
		return "an amount that is not a readable number"
	if amount.is_negative():
		return "a negative payment, which is a credit note and not a payment"
	if amount.is_zero():
		return "a payment of nothing"
	if not is_method(method):
		return "a method nobody has: '%s'" % String(method)
	return ""


func is_sound() -> bool:
	return problem().is_empty()


func describe() -> String:
	if not is_sound():
		return problem()
	var parts := PackedStringArray()
	parts.append("%s by %s" % [amount.format_with_currency(), method_name(method)])
	if not received_at.strip_edges().is_empty():
		parts.append("on %s" % received_at)
	if not bank_reference.strip_edges().is_empty():
		parts.append("reference %s" % bank_reference)
	return ", ".join(parts)


func to_dict() -> Dictionary:
	return {
		"id": id,
		"invoice": invoice,
		"received_at": received_at,
		"amount": (amount if amount != null else MoneyScript.zero()).to_dict(),
		"method": String(method),
		"reference": bank_reference,
		"note": note,
	}


## A record with no id is **dropped rather than invented**: a payment that cannot be named cannot be
## un-applied either, and a balance nobody can explain is worse than a payment that is missing.
static func from_dict(data: Dictionary) -> Payment:
	var payment: Payment = PaymentScript.new(String(data.get("id", "")))
	if payment.id.is_empty():
		return null
	payment.invoice = String(data.get("invoice", ""))
	payment.received_at = String(data.get("received_at", ""))
	payment.amount = MoneyScript.from_dict(data.get("amount", {}))
	payment.method = StringName(data.get("method", "cheque"))
	payment.bank_reference = String(data.get("reference", ""))
	payment.note = String(data.get("note", ""))
	return payment


const PaymentScript := preload("res://scripts/biz/payment.gd")