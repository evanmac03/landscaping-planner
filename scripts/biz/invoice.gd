class_name Invoice
extends RefCounted
## An invoice: what was billed, on what it was charged, and what has been paid (spec §4.12, §9.4).
##
## **An invoice is never edited after issue.** `add_line`, `erase_line` and `set_retainage` all refuse
## once `issued_at` is set; a wrong invoice is voided and reissued, and the void **keeps its number**
## and names its replacement. Gap-free numbering with a visible void is what an auditor wants, which
## is why the number is assigned at *issue* and not at draft: a draft has no number, so deleting one
## leaves no hole (§9.4).
##
## The **state is a function of the records** - `issued_at`, `voided_at` and the payments applied -
## exactly as phase 6's purchase order and change order are. `to_dict` writes the state for a reader
## and `from_dict` **ignores it**, so a damaged file cannot make a draft look issued or an unpaid
## invoice look paid.
##
## Tax is charged per code on that code's share of the invoice, through the same `Tax` engine the
## estimate uses: one tax table, one rounding rule, one answer.

const MoneyScript := preload("res://scripts/biz/money.gd")
const TaxScript := preload("res://scripts/biz/tax.gd")
const RateScript := preload("res://scripts/biz/rate.gd")
const PaymentScript := preload("res://scripts/biz/payment.gd")

const DRAFT := 0
const ISSUED := 1
const PART_PAID := 2
const PAID := 3
const VOID := 4

## String keys: a StringName literal as a const Dictionary key fails the constant-expression check.
const STATE_NAMES := {
	"DRAFT": "draft",
	"ISSUED": "issued",
	"PART_PAID": "part paid",
	"PAID": "paid",
	"VOID": "void",
}

## What a line is. The kind is not decoration: it is what the desk and the page say a line came from,
## and a percentage-completion invoice's single line is a different document from a milestone one.
const MILESTONE_LINE := 0
const PERCENTAGE_LINE := 1
const PERIOD_LINE := 2
const CHANGE_LINE := 3
const FIXED_LINE := 4
const KIND_NAMES := {
	"MILESTONE": "a milestone",
	"PERCENTAGE": "a progress claim",
	"PERIOD": "a period of work",
	"CHANGE": "a change order",
	"FIXED": "the contract",
}

const NUMBER_PREFIX := "INV"
const QUANTITY_MILLI := 1000
const SECONDS_PER_DAY := 86400
## Ten years of terms: longer is a date somebody mistyped, and a due date beyond it is not a term.
const MAX_TERMS_DAYS := 3650

var id: String = ""
## Empty until the invoice is issued, because a draft has no number (§9.4).
var number: String = ""
var job: String = ""
## The customer and the site, copied from the job: the invoice has to print them whether or not the
## job is open, and a document that reaches for its customer is a document that changes when a job is
## edited.
var customer: Dictionary = {}
var site: Dictionary = {}
var currency: StringName = &"CAD"
var issued_at: String = ""
var due_at: String = ""
var terms_days: int = 0
## A period invoice's own window: TIME_AND_MATERIALS and COST_PLUS bill a period, not a position.
var period_start: String = ""
var period_end: String = ""
## `{kind, description, quantity_milli, unit, rate, amount, cost_code, tax_code}`.
var lines: Array[Dictionary] = []
## What is withheld from this invoice. A deduction on the totals, and its own row on the page,
## because a customer's bookkeeper looks for it (§9.2).
var retainage: Money = null
var payments: Array[Payment] = []
var voided_at: String = ""
var voided_why: String = ""
## The number of the invoice that replaces this one, when it was voided and reissued.
var replaces: String = ""
var note: String = ""


func _init(invoice_id: String = "") -> void:
	id = invoice_id
	retainage = MoneyScript.zero()


static func kind_name(kind: int) -> String:
	return String(KIND_NAMES.get(_kind_key(kind), "a line"))


static func is_kind(candidate: int) -> bool:
	return candidate >= MILESTONE_LINE and candidate <= FIXED_LINE


func state_name() -> String:
	return String(STATE_NAMES.get(_state_key(state()), "draft"))


# --- building it, before it goes out ------------------------------------------------------------


func is_issued() -> bool:
	return not issued_at.strip_edges().is_empty()


func is_void() -> bool:
	return not voided_at.strip_edges().is_empty()


## Whether anything about the money on this invoice can still be changed.
func is_editable() -> bool:
	return not is_issued() and not is_void()


## Add a line: a quantity of a unit at a rate, priced by the one rounding rule Money has.
## Refused for a kind nobody has, for nothing to say, and for an amount that cannot be read - a line
## the totals cannot include is a line that disappears from the invoice.
func add_line(kind: int, description: String, quantity_milli: int, unit: StringName, rate: Money,
		cost_code: StringName = &"", tax_code: StringName = &"NONE") -> bool:
	if not is_editable():
		return false
	if not is_kind(kind):
		return false
	if description.strip_edges().is_empty():
		return false
	if quantity_milli <= 0:
		return false
	if rate == null or not rate.is_valid():
		return false
	if rate.currency != currency:
		return false
	var amount: Money = MoneyScript.round_div(rate.cents * quantity_milli, QUANTITY_MILLI, currency)
	if not amount.is_valid() or amount.is_zero():
		return false
	lines.append({
		"kind": kind,
		"description": description,
		"quantity_milli": quantity_milli,
		"unit": String(unit),
		"rate": rate.copy(),
		"amount": amount,
		"cost_code": String(cost_code),
		"tax_code": String(tax_code),
	})
	return true


## Add a line that is simply an amount - a milestone, a progress claim, a change order. One each of
## one unit at that rate, which is how a document that bills a sum writes it.
func add_amount(kind: int, description: String, amount: Money, cost_code: StringName = &"",
		tax_code: StringName = &"NONE") -> bool:
	return add_line(kind, description, QUANTITY_MILLI, &"EACH", amount, cost_code, tax_code)


func erase_line(index: int) -> bool:
	if not is_editable():
		return false
	if index < 0 or index >= lines.size():
		return false
	lines.remove_at(index)
	return true


func line_count() -> int:
	return lines.size()


func line(index: int) -> Dictionary:
	if index < 0 or index >= lines.size():
		return {}
	return lines[index]


## State what is withheld from this invoice. Refused for an unreadable or negative amount, and once
## the invoice has gone out: a retainage corrected after issue is a second invoice, not an edit.
func set_retainage(amount: Money) -> bool:
	if not is_editable():
		return false
	if amount == null or not amount.is_valid() or amount.is_negative():
		return false
	if amount.currency != currency:
		return false
	retainage = amount.copy()
	return true


# --- what it comes to ---------------------------------------------------------------------------


func subtotal() -> Money:
	var amounts: Array = []
	for entry in lines:
		amounts.append(entry.get("amount", null))
	return MoneyScript.sum(amounts, currency)


## One entry per tax code, each with the share it was charged on and the components it added. Tax is
## charged on a code's **own share** and rounded once per component, so a mixed invoice charges each
## code exactly what the published table says.
func tax_lines() -> Array[Dictionary]:
	var order: Array[StringName] = []
	var buckets: Dictionary = {}
	for entry in lines:
		var code: StringName = StringName(entry.get("tax_code", "NONE"))
		if not buckets.has(code):
			buckets[code] = []
			order.append(code)
		var bucket: Array = buckets[code]
		bucket.append(entry.get("amount", null))
	var out: Array[Dictionary] = []
	for code in order:
		var taxable: Money = MoneyScript.sum(buckets[code], currency)
		var grossed: Dictionary = TaxScript.gross(taxable, code)
		out.append({
			"tax_code": code,
			"taxable": taxable,
			"tax": grossed["tax"],
			"components": grossed["components"],
			"ok": bool(grossed["ok"]),
			"reason": String(grossed["reason"]),
		})
	return out


func tax() -> Money:
	var amounts: Array = []
	for entry in tax_lines():
		if not bool(entry["ok"]):
			return MoneyScript.invalid(currency)
		amounts.append(entry["tax"])
	return MoneyScript.sum(amounts, currency)


## Why the tax could not be worked out, or "" when it could.
func tax_problem() -> String:
	for entry in tax_lines():
		if not bool(entry["ok"]):
			return String(entry["reason"])
	return ""


func total() -> Money:
	var gross: Money = subtotal().add(tax())
	if not gross.is_valid():
		return gross
	return gross.sub(retainage if retainage != null else MoneyScript.zero(currency))


func applied() -> Money:
	var amounts: Array = []
	for entry in payments:
		amounts.append(entry.amount)
	return MoneyScript.sum(amounts, currency)


func balance() -> Money:
	return total().sub(applied())


func payment_count() -> int:
	return payments.size()


func payment_by_id(payment_id: String) -> Payment:
	for entry in payments:
		if entry.id == payment_id:
			return entry
	return null


## The state, read off the records: nothing issued is a draft, something issued with money against it
## is part paid, and a settled one is paid.
func state() -> int:
	if is_void():
		return VOID
	if not is_issued():
		return DRAFT
	var paid: Money = applied()
	var owed: Money = total()
	if not paid.is_valid() or not owed.is_valid() or paid.is_zero():
		return ISSUED
	if paid.cents >= owed.cents:
		return PAID
	return PART_PAID


## Every figure the page and the window print, named once.
func totals() -> Dictionary:
	return {
		"subtotal": subtotal(),
		"tax": tax(),
		"retainage": retainage if retainage != null else MoneyScript.zero(currency),
		"total": total(),
		"applied": applied(),
		"balance": balance(),
	}


# --- issuing, paying, voiding -------------------------------------------------------------------


## Issue it: assign the number, stamp the moment and work out the due date.
## Refused for an invoice with nothing on it, with no number, with terms nobody could have agreed to,
## and for one whose totals do not read - an invoice that cannot add up must not go out.
func issue(at: String, net_days: int, invoice_number: String) -> Dictionary:
	if is_void():
		return {"ok": false, "reason": "a voided invoice is never reissued - a fresh one is"}
	if is_issued():
		return {"ok": false, "reason": "an invoice is never edited after issue: %s went out on %s" % [number, issued_at]}
	if lines.is_empty():
		return {"ok": false, "reason": "an invoice with nothing on it"}
	if invoice_number.strip_edges().is_empty():
		return {"ok": false, "reason": "an invoice with no number"}
	if not RateScript.is_date(at):
		return {"ok": false, "reason": "an issue date that is not a date: '%s'" % at}
	if net_days < 0 or net_days > MAX_TERMS_DAYS:
		return {"ok": false, "reason": "terms of %d days, which nobody agreed to" % net_days}
	var due: String = add_days(at, net_days)
	if due.is_empty():
		return {"ok": false, "reason": "the terms could not be turned into a due date"}
	if not total().is_valid():
		return {"ok": false, "reason": "the totals do not read, so this cannot go out"}
	issued_at = at
	terms_days = net_days
	number = invoice_number
	due_at = due
	return {"ok": true, "reason": ""}


## Apply a payment. Refused for a payment that is not sound, for one that names another invoice, for
## one against an invoice that has not gone out, and for **more than the balance outstanding**.
##
## Not clamped. A payment larger than the balance is either a duplicate remittance or a number typed
## wrong, and clamping it hides both until the customer's bookkeeper finds it (spec §9.4).
func apply_payment(payment: Payment) -> Dictionary:
	if payment == null:
		return {"ok": false, "reason": "there is no payment to apply"}
	if not payment.is_sound():
		return {"ok": false, "reason": payment.problem()}
	if payment.invoice != id:
		return {"ok": false, "reason": "that payment names another invoice"}
	if is_void():
		return {"ok": false, "reason": "this invoice was voided and takes no payment"}
	if not is_issued():
		return {"ok": false, "reason": "this invoice has not been issued yet"}
	if payment_by_id(payment.id) != null:
		return {"ok": false, "reason": "that payment is already against this invoice"}
	if payment.amount.currency != currency:
		return {"ok": false, "reason": "that payment is in another currency"}
	var owed: Money = balance()
	if not owed.is_valid():
		return {"ok": false, "reason": "the balance is not a readable number"}
	if payment.amount.cents > owed.cents:
		return {
			"ok": false,
			"reason": "a payment of %s is more than the %s outstanding, which is a duplicate or a typo rather than an overpayment" % [
				payment.amount.format_with_currency(),
				owed.format_with_currency(),
			],
		}
	payments.append(payment)
	return {"ok": true, "reason": ""}


## Void it: keep the number, say when and why, and name what replaces it.
## A **draft is not voided** - it has no number to keep and is simply deleted.
func mark_void(at: String, why: String, replacement: String = "") -> bool:
	if not is_issued() or is_void():
		return false
	if why.strip_edges().is_empty():
		return false
	if not RateScript.is_date(at):
		return false
	voided_at = at
	voided_why = why
	replaces = replacement
	return true


func voided_text() -> String:
	if not is_void():
		return ""
	var text: String = "voided on %s: %s" % [voided_at, voided_why]
	if not replaces.strip_edges().is_empty():
		text += " (reissued as %s)" % replaces
	return text


# --- numbering ----------------------------------------------------------------------------------


## A number for an invoice that has not been issued yet: `INV-2026-0184`.
##
## The highest number already taken in that fiscal year, plus one - **never the count**. A count
## hands the same number out twice the moment anything is voided or deleted, and a reused invoice
## number is the single error an auditor does not forgive. Assigned at issue, so a draft has none and
## deleting a draft leaves no hole.
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


## The number part of an invoice number, or -1 when the text is not one of ours.
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


## Which fiscal year a moment falls in. A year that starts in April puts March in the year before,
## which is the whole reason this is a function rather than `date.substr(0, 4)`.
static func fiscal_year_of(date: String, start_month: int = 1) -> int:
	if not RateScript.is_date(date):
		return 0
	var year: int = date.substr(0, 4).to_int()
	if start_month <= 1 or start_month > 12:
		return year
	if date.substr(5, 2).to_int() < start_month:
		return year - 1
	return year


## A moment a stated number of days later. Empty when the date is not a date.
static func add_days(date: String, days: int) -> String:
	if not RateScript.is_date(date):
		return ""
	var start: int = Time.get_unix_time_from_datetime_string(date)
	return Time.get_date_string_from_unix_time(start + days * SECONDS_PER_DAY)


# --- soundness ----------------------------------------------------------------------------------


func problems() -> Array[String]:
	var out: Array[String] = []
	if id.strip_edges().is_empty():
		out.append("an invoice with no id")
	if job.strip_edges().is_empty():
		out.append("an invoice that belongs to no job")
	if lines.is_empty():
		out.append("an invoice with nothing on it")
	var tax_reason: String = tax_problem()
	if not tax_reason.is_empty():
		out.append(tax_reason)
	if not subtotal().is_valid():
		out.append("a line whose amount cannot be read")
	if retainage == null or not retainage.is_valid() or retainage.is_negative():
		out.append("a retainage that cannot be read")
	if is_issued():
		if number.strip_edges().is_empty():
			out.append("an issued invoice with no number")
		if not RateScript.is_date(due_at):
			out.append("an issued invoice due on a date that is not a date: '%s'" % due_at)
		if RateScript.is_date(due_at) and due_at < issued_at:
			out.append("an invoice due before it was issued")
	if is_void() and voided_why.strip_edges().is_empty():
		out.append("a void with no reason")
	for entry in payments:
		if not entry.is_sound():
			out.append(entry.problem())
	var paid: Money = applied()
	var owed: Money = total()
	if paid.is_valid() and owed.is_valid() and paid.cents > owed.cents:
		out.append("%s has been paid against a total of %s" % [
			paid.format_with_currency(),
			owed.format_with_currency(),
		])
	return out


func is_sound() -> bool:
	return problems().is_empty()


func describe() -> String:
	var parts := PackedStringArray()
	parts.append(number if not number.strip_edges().is_empty() else "an unnumbered draft")
	if not job.strip_edges().is_empty():
		parts.append("for job %s" % job)
	parts.append("%d line(s)" % lines.size())
	parts.append(subtotal().format_with_currency())
	if not tax().is_zero():
		parts.append("+ %s tax" % tax().format_with_currency())
	if retainage != null and not retainage.is_zero():
		parts.append("less %s retained" % retainage.format_with_currency())
	parts.append("%s due" % total().format_with_currency())
	if not applied().is_zero():
		parts.append("%s paid" % applied().format_with_currency())
	parts.append(state_name())
	if is_issued():
		parts.append("%s to %s" % [issued_at, due_at])
	return ", ".join(parts)


# --- persistence --------------------------------------------------------------------------------


func to_dict() -> Dictionary:
	var rows: Array = []
	for entry in lines:
		rows.append({
			"kind": _kind_key(int(entry.get("kind", MILESTONE_LINE))),
			"description": String(entry.get("description", "")),
			"quantity_milli": int(entry.get("quantity_milli", QUANTITY_MILLI)),
			"unit": String(entry.get("unit", "EACH")),
			"rate": (entry.get("rate", MoneyScript.zero(currency)) as Money).to_dict(),
			"amount": (entry.get("amount", MoneyScript.zero(currency)) as Money).to_dict(),
			"cost_code": String(entry.get("cost_code", "")),
			"tax_code": String(entry.get("tax_code", "NONE")),
		})
	var paid: Array = []
	for entry in payments:
		paid.append(entry.to_dict())
	return {
		"id": id,
		"number": number,
		"job": job,
		"customer": customer.duplicate(true),
		"site": site.duplicate(true),
		"currency": String(currency),
		"issued_at": issued_at,
		"due_at": due_at,
		"terms_days": terms_days,
		"period_start": period_start,
		"period_end": period_end,
		"lines": rows,
		"retainage": (retainage if retainage != null else MoneyScript.zero(currency)).to_dict(),
		"payments": paid,
		"voided_at": voided_at,
		"voided_why": voided_why,
		"replaces": replaces,
		"note": note,
		# Written for whoever reads the file. `from_dict` ignores it: the state is a function of the
		# records, and a stored one would be a second place the truth lives.
		"state": state_name(),
	}


## A record with no id is **dropped rather than invented**, like every other record here. A line
## whose rate cannot be read is kept with the invalid amount, so the invoice refuses to foot rather
## than quietly pricing a line at nothing.
static func from_dict(data: Dictionary) -> Invoice:
	var invoice: Invoice = InvoiceScript.new(String(data.get("id", "")))
	if invoice.id.is_empty():
		return null
	invoice.number = String(data.get("number", ""))
	invoice.job = String(data.get("job", ""))
	var customer_in = data.get("customer", {})
	invoice.customer = (customer_in as Dictionary).duplicate(true) if customer_in is Dictionary else {}
	var site_in = data.get("site", {})
	invoice.site = (site_in as Dictionary).duplicate(true) if site_in is Dictionary else {}
	invoice.currency = StringName(data.get("currency", "CAD"))
	invoice.issued_at = String(data.get("issued_at", ""))
	invoice.due_at = String(data.get("due_at", ""))
	invoice.terms_days = int(data.get("terms_days", 0))
	invoice.period_start = String(data.get("period_start", ""))
	invoice.period_end = String(data.get("period_end", ""))
	var lines_in = data.get("lines", [])
	if lines_in is Array:
		for entry in (lines_in as Array):
			if entry is Dictionary:
				invoice.lines.append({
					"kind": _kind_from(String(entry.get("kind", "MILESTONE"))),
					"description": String(entry.get("description", "")),
					"quantity_milli": int(entry.get("quantity_milli", QUANTITY_MILLI)),
					"unit": String(entry.get("unit", "EACH")),
					"rate": MoneyScript.from_dict(entry.get("rate", {})),
					"amount": MoneyScript.from_dict(entry.get("amount", {})),
					"cost_code": String(entry.get("cost_code", "")),
					"tax_code": String(entry.get("tax_code", "NONE")),
				})
	invoice.retainage = MoneyScript.from_dict(data.get("retainage", {}))
	var paid_in = data.get("payments", [])
	if paid_in is Array:
		for entry in (paid_in as Array):
			if entry is Dictionary:
				var payment: Payment = PaymentScript.from_dict(entry)
				if payment != null:
					invoice.payments.append(payment)
	invoice.voided_at = String(data.get("voided_at", ""))
	invoice.voided_why = String(data.get("voided_why", ""))
	invoice.replaces = String(data.get("replaces", ""))
	invoice.note = String(data.get("note", ""))
	return invoice


static func _state_key(state_key: int) -> String:
	match state_key:
		ISSUED: return "ISSUED"
		PART_PAID: return "PART_PAID"
		PAID: return "PAID"
		VOID: return "VOID"
	return "DRAFT"


static func _kind_key(kind: int) -> String:
	match kind:
		PERCENTAGE_LINE: return "PERCENTAGE"
		PERIOD_LINE: return "PERIOD"
		CHANGE_LINE: return "CHANGE"
		FIXED_LINE: return "FIXED"
	return "MILESTONE"


static func _kind_from(key: String) -> int:
	match key:
		"PERCENTAGE": return PERCENTAGE_LINE
		"PERIOD": return PERIOD_LINE
		"CHANGE": return CHANGE_LINE
		"FIXED": return FIXED_LINE
	return MILESTONE_LINE


const InvoiceScript := preload("res://scripts/biz/invoice.gd")