class_name ChangeOrder
extends RefCounted
## A small estimate attached to a job, and the record of the customer agreeing to it (spec §8.2).
##
## It **reuses §5's engine**: the lines are an `Estimate`, so waste, kits, the tax handling, the
## freezing and every refusal come from the engine the proposal already uses, and a change order
## cannot price something a proposal could not. What it adds is a **reason**, a **state**, and an
## **approval record**.
##
## ## The reason is the point
##
## `reason` is required and comes from a short list. It is the data that later says whether the
## business is losing money to *unforeseen* conditions or to its own estimating (§8.2), which is the
## only question a change-order log is worth keeping to answer.
##
## ## Only an approved one enters the contract sum
##
## REQ-B18. A pending one is shown separately wherever the contract sum is shown, and the billing
## screens say so: "contract sum $84,300 (2 change orders pending, $4,150 not yet agreed)".
##
## ## The approval records who, when and how
##
## REQ-B13: "the customer agreed" is a claim a business has to be able to support, so an approval
## without an approver, a moment and a *how* (in-app, a signed paper photo, an e-mail reference) is
## refused rather than stored as a date.

const EstimateScript := preload("res://scripts/biz/estimate.gd")
const LineScript := preload("res://scripts/biz/estimate_line.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")
const BookScript := preload("res://scripts/biz/cost_book.gd")

const PROPOSED := &"PROPOSED"
const SENT := &"SENT"
const APPROVED := &"APPROVED"
const DECLINED := &"DECLINED"
const VOID := &"VOID"

const STATE_NAMES := {
	"PROPOSED": "proposed",
	"SENT": "sent, not yet answered",
	"APPROVED": "approved",
	"DECLINED": "declined",
	"VOID": "void",
}

## The short list a reason comes from. String keys: a StringName literal as a const Dictionary key
## fails the constant-expression check in this build.
const REASONS := {
	"CUSTOMER_REQUEST": "customer request",
	"SITE_CONDITION": "site condition",
	"DESIGN_CHANGE": "design change",
	"CODE_OR_PERMIT": "code or permit",
	"ERROR_AND_OMISSION": "error and omission",
	"OTHER": "other",
}

## How the agreement was recorded (REQ-B13). An approval in the app, a photograph of signed paper, or
## the reference of an e-mail that says yes are three different weights of evidence.
const APPROVAL_HOWS: Array[String] = [
	"in-app", "signed paper photo", "e-mail reference",
]

var id: String = ""
var number: String = ""
var job: String = ""
## From REASONS. Required: a change order nobody can explain is a change order nobody can learn from.
var reason: StringName = &"OTHER"
## The priced lines, as an estimate: §5's engine, its refusals and its rounding.
var estimate: Estimate = null
## Whether an approved change joins the contract sum. A schedule-only change is agreed and worth
## nothing, and a credit is agreed and worth less - both are real.
var affects_contract_sum: bool = true
var proposed_at: String = ""
var sent_at: String = ""
var approved_by: String = ""
var approved_at: String = ""
var approved_how: String = ""
## A path to the photograph of the signed paper, when that is how it was agreed.
var approved_signature: String = ""
var declined_by: String = ""
var declined_at: String = ""
var declined_why: String = ""
var voided_at: String = ""
var voided_why: String = ""
var note: String = ""


func _init(order_id: String = "") -> void:
	id = order_id
	estimate = EstimateScript.new(EstimateScript.new_id() if id.is_empty() else id)


static func is_reason(candidate: StringName) -> bool:
	return REASONS.has(String(candidate))


static func reason_name(candidate: StringName) -> String:
	return String(REASONS.get(String(candidate), "other"))


## The state, **derived from the records** exactly as the purchase order's is (§8.3): proposed once
## somebody proposed it, sent once it went out, and answered once an approval or a decline was
## recorded. It is deliberately not a stored field - a second place the truth lives is a state that
## can drift, and this one drifting means an agreement nobody ever made.
func state() -> StringName:
	if not approved_at.is_empty():
		return APPROVED
	if not voided_at.is_empty():
		return VOID
	if not declined_at.is_empty():
		return DECLINED
	if not sent_at.is_empty():
		return SENT
	return PROPOSED


func state_name() -> String:
	return String(STATE_NAMES.get(String(state()), String(state())))


## Whether it is still waiting for an answer: what "2 change orders pending, $4,150 not yet agreed"
## counts.
func is_pending() -> bool:
	var now := state()
	return now == PROPOSED or now == SENT


func is_approved() -> bool:
	return state() == APPROVED


## Whether the money on it has joined the contract sum: approved **and** stated to affect it (REQ-B18).
func enters_contract_sum() -> bool:
	return state() == APPROVED and affects_contract_sum


# --- what it is worth ------------------------------------------------------------------------


func line_count() -> int:
	return estimate.line_count() if estimate != null else 0


## What it adds to the job, before tax: what the customer agreed to pay for the change.
func amount() -> Money:
	if estimate == null:
		return MoneyScript.invalid()
	return estimate.price_before_tax()


## What the change costs the business. Carried here so a cost report can see what a change is worth
## against what it costs, without re-pricing anything.
func cost() -> Money:
	if estimate == null:
		return MoneyScript.invalid()
	return estimate.direct_cost()


func add_line(line: EstimateLine, book: CostBook = null) -> bool:
	if estimate == null:
		return false
	return estimate.add_line(line, book)


## What the change is worth per cost code, from its own lines - so a cost report can show what was
## approved for a code beside what the code has cost.
## Returns `{code: Money}`.
func code_amounts() -> Dictionary:
	var out: Dictionary = {}
	if estimate == null:
		return out
	for line in estimate.lines:
		var code := String(line.cost_code)
		if code.is_empty():
			code = "UNASSIGNED"
		var running: Money = out.get(code, MoneyScript.zero(estimate.currency))
		out[code] = running.add(line.extension())
	return out


# --- the workflow ---------------------------------------------------------------------------


func propose(at: String) -> bool:
	if at.strip_edges().is_empty():
		return false
	if not proposed_at.is_empty() or state() != PROPOSED:
		return false
	proposed_at = at
	return true


## Send it for an answer. Only a proposed change order can go out, and only once.
func send(at: String) -> bool:
	if proposed_at.is_empty() or not sent_at.is_empty() or at.strip_edges().is_empty():
		return false
	sent_at = at
	return true


## Record the customer's agreement. Refused without **who, when and how** (REQ-B13), for a change
## order that was never proposed, and for one already answered.
## Returns `{ok, reason}`.
func approve(by: String, at: String, how: String, signature: String = "") -> Dictionary:
	if not is_pending():
		return {"ok": false, "reason": "it is %s, and that is not a question any more" % state_name()}
	if by.strip_edges().is_empty():
		return {"ok": false, "reason": "an approval says who agreed"}
	if at.strip_edges().is_empty():
		return {"ok": false, "reason": "an approval says when"}
	if how.strip_edges().is_empty() or not APPROVAL_HOWS.has(how):
		return {"ok": false,
			"reason": "an approval says how it was recorded: %s" % ", ".join(APPROVAL_HOWS)}
	if estimate != null and estimate.line_count() == 0:
		return {"ok": false, "reason": "there is nothing on it to approve"}
	approved_by = by
	approved_at = at
	approved_how = how
	approved_signature = signature
	return {"ok": true, "reason": ""}


func decline(by: String, at: String, why: String) -> Dictionary:
	if not is_pending():
		return {"ok": false, "reason": "it is %s, and that is not a question any more" % state_name()}
	if why.strip_edges().is_empty():
		return {"ok": false, "reason": "a declined change order says why"}
	declined_by = by
	declined_at = at
	declined_why = why
	return {"ok": true, "reason": ""}


## Void one that was never answered. **An approved change order is a contract document** and cannot be
## voided: the way to undo agreement is a second change order, which is what a paper trail is for.
## Not named `void`, which is a keyword in this language.
func mark_void(at: String, why: String) -> Dictionary:
	if is_approved():
		return {"ok": false,
			"reason": "an approved change order is a contract document: agree a second one instead"}
	if not voided_at.is_empty():
		return {"ok": false, "reason": "it is already void"}
	if why.strip_edges().is_empty():
		return {"ok": false, "reason": "a void change order says why"}
	voided_at = at
	voided_why = why
	return {"ok": true, "reason": ""}


# --- what it says --------------------------------------------------------------------------


func approval_text() -> String:
	if not is_approved():
		return ""
	return "approved by %s on %s (%s)" % [approved_by, approved_at, approved_how]


## What is wrong with it, in sentences. A proposed change order with no lines is a form somebody
## started; an approved one with no approver could not happen through `approve`, so it is a record
## somebody edited by hand.
func problems(book: CostBook = null) -> Array[String]:
	var out: Array[String] = []
	if id.strip_edges().is_empty():
		out.append("a change order needs an id")
	if not is_reason(reason):
		out.append("%s has reason \"%s\", which is not one of the six" % [_label(), String(reason)])
	if estimate != null:
		for held in estimate.problems(book):
			out.append("%s: %s" % [_label(), String(held)])
	if is_approved() and (approved_by.strip_edges().is_empty() or approved_at.is_empty()
			or approved_how.strip_edges().is_empty()):
		out.append("%s is approved with no record of who agreed, when or how" % _label())
	return out


func is_sound(book: CostBook = null) -> bool:
	return problems(book).is_empty()


## "+$4,150.00" or "-$820.00": a change is signed, because a credit is a change too.
func amount_text() -> String:
	var money := amount()
	if not money.is_valid():
		return "unpriced"
	var sign_text := "-" if money.cents < 0 else "+"
	return "%s%s" % [sign_text, money.abs().format_with_currency()]


func describe() -> String:
	var parts := PackedStringArray()
	parts.append("%s %s" % [_label(), reason_name(reason)])
	parts.append(amount_text())
	if is_approved():
		parts.append(approval_text())
	else:
		parts.append(state_name())
	if not affects_contract_sum:
		parts.append("does not change the contract sum")
	return "%s (%s)" % [", ".join(parts), job if not job.is_empty() else "no job"]


func _label() -> String:
	if not number.is_empty():
		return number
	if not id.is_empty():
		return id
	return "this change order"


# --- the file ---------------------------------------------------------------------------------


func to_dict() -> Dictionary:
	return {
		"id": id,
		"number": number,
		"job": job,
		"reason": String(reason),
		"state": String(state()),
		"estimate": estimate.to_dict() if estimate != null else {},
		"affects_contract_sum": affects_contract_sum,
		"proposed_at": proposed_at,
		"sent_at": sent_at,
		"approved_by": approved_by,
		"approved_at": approved_at,
		"approved_how": approved_how,
		"approved_signature": approved_signature,
		"declined_by": declined_by,
		"declined_at": declined_at,
		"declined_why": declined_why,
		"voided_at": voided_at,
		"voided_why": voided_why,
		"note": note,
	}


## Read one back. A record with no id is **dropped**, not invented. A reason nobody has becomes OTHER;
## a state nobody has is not read at all, because the state is the records - which is the direction that
## must not invent an agreement, so a damaged record never quietly adds money to a contract sum.
static func from_dict(data: Dictionary) -> ChangeOrder:
	var order: ChangeOrder = OrderScript.new(String(data.get("id", "")))
	if order.id.is_empty():
		return null
	order.number = String(data.get("number", ""))
	order.job = String(data.get("job", ""))
	var reason_in := StringName(data.get("reason", "OTHER"))
	order.reason = reason_in if is_reason(reason_in) else &"OTHER"
	# The stored "state" is written for whoever reads the JSON and deliberately **not** read back here:
	# the state is derived from the dates below, so a record that says APPROVED with no approver is a
	# proposed change order rather than an agreement nobody made.
	var held = data.get("estimate", {})
	if held is Dictionary and not (held as Dictionary).is_empty():
		var read: Estimate = EstimateScript.from_dict(held)
		if read != null:
			order.estimate = read
	order.affects_contract_sum = bool(data.get("affects_contract_sum", true))
	order.proposed_at = String(data.get("proposed_at", ""))
	order.sent_at = String(data.get("sent_at", ""))
	order.approved_by = String(data.get("approved_by", ""))
	order.approved_at = String(data.get("approved_at", ""))
	order.approved_how = String(data.get("approved_how", ""))
	order.approved_signature = String(data.get("approved_signature", ""))
	order.declined_by = String(data.get("declined_by", ""))
	order.declined_at = String(data.get("declined_at", ""))
	order.declined_why = String(data.get("declined_why", ""))
	order.voided_at = String(data.get("voided_at", ""))
	order.voided_why = String(data.get("voided_why", ""))
	order.note = String(data.get("note", ""))
	return order


const OrderScript := preload("res://scripts/biz/change_order.gd")