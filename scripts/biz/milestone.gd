class_name Milestone
extends RefCounted
## One step of a billing schedule (spec §9.2).
##
## A milestone is priced **one of two ways and never both**: a percent of the contract, or a fixed
## amount. Both is a step nobody can read - which of the two does it come to? - and neither is a step
## that bills nothing while looking like a step. `percent_ppm` is `Rate.INVALID` when it is not
## stated, so "unpriced" is a value and not a zero that would bill nothing quietly.
##
## Whether a step has been billed is a **record** (`billed_at` and the invoice number it went out on)
## rather than a state field, for the reason phase 6 gives about purchase orders: a stored enum is a
## second place the truth lives, and the two disagree the first time a record is edited by hand.

const MoneyScript := preload("res://scripts/biz/money.gd")
const RateScript := preload("res://scripts/biz/rate.gd")

## What fires the step. DATE is the due date; PHASE_COMPLETE is a phase of the job being finished;
## APPROVED is somebody agreeing. All three are things a person states, because none of them is
## something this program can work out on its own.
const DATE := 0
const PHASE_COMPLETE := 1
const APPROVED := 2
const TRIGGER_NAMES := {
	"DATE": "on a date",
	"PHASE_COMPLETE": "when a phase is complete",
	"APPROVED": "on approval",
}

const NAME := "pending"
const BILLED := "billed"

var name: String = ""
## The share of the contract this step bills, in parts per million, or `Rate.INVALID`.
var percent_ppm: int = RateScript.INVALID
## A flat amount, for a step that is not a share of anything (a permit fee, a deposit).
var fixed_amount: Money = null
var trigger: int = DATE
var due_date: String = ""
## Retainage withheld on this step's own amount, in parts per million. Zero is "nothing withheld
## here", which is a real answer and the common one.
var retainage_ppm: int = 0
var billed_at: String = ""
var invoice_number: String = ""
var note: String = ""


func _init(milestone_name: String = "") -> void:
	name = milestone_name


static func is_trigger(candidate: int) -> bool:
	return candidate >= DATE and candidate <= APPROVED


static func trigger_name(candidate: int) -> String:
	return String(TRIGGER_NAMES.get(_trigger_key(candidate), "on a date"))


# --- pricing -----------------------------------------------------------------------------------


## Price this step as a share of the contract. Refused for nothing and for more than the whole: a
## step of 0% bills nothing while reading as a step, and a step of 120% is a contract that was
## mis-written rather than one to bill.
func set_percent(ppm: int) -> bool:
	if ppm <= 0 or ppm > RateScript.WHOLE:
		return false
	percent_ppm = ppm
	fixed_amount = null
	return true


## Price this step as a flat amount.
func set_fixed_amount(amount: Money) -> bool:
	if amount == null or not amount.is_valid() or amount.is_negative() or amount.is_zero():
		return false
	fixed_amount = amount.copy()
	percent_ppm = RateScript.INVALID
	return true


func is_percentage() -> bool:
	return RateScript.is_valid(percent_ppm)


func is_fixed() -> bool:
	return fixed_amount != null and fixed_amount.is_valid()


func is_priced() -> bool:
	return is_percentage() or is_fixed()


## What this step bills on a contract of `contract_sum`. A fixed step ignores the contract; a
## percentage one is scaled by it. An unpriced step answers with the invalid amount, which poisons
## whatever total it feeds rather than disappearing into it.
func amount_for(contract_sum: Money) -> Money:
	if is_fixed():
		return fixed_amount.copy()
	if is_percentage() and contract_sum != null:
		return contract_sum.scale_ppm(percent_ppm)
	return MoneyScript.invalid(contract_sum.currency if contract_sum != null else &"CAD")


## What is withheld from this step: a share of the step's own amount, not of the contract, because
## the sentence a contract writes is "10% of each progress payment".
func retainage_for(contract_sum: Money) -> Money:
	if retainage_ppm <= 0:
		return MoneyScript.zero(contract_sum.currency if contract_sum != null else &"CAD")
	return amount_for(contract_sum).scale_ppm(retainage_ppm)


# --- being billed ------------------------------------------------------------------------------


func is_billed() -> bool:
	return not billed_at.strip_edges().is_empty()


func state_name() -> String:
	return BILLED if is_billed() else NAME


## Record that this step went out on an invoice. The moment and the number are both required: a step
## that says it was billed and cannot say when, or on what, is a step nobody can check.
func mark_billed(at: String, number: String) -> bool:
	if is_billed():
		return false
	if at.strip_edges().is_empty() or number.strip_edges().is_empty():
		return false
	billed_at = at
	invoice_number = number
	return true


## What a schedule row says. The step's name leads, because that is what a person looks for, and the
## state closes the parenthesis, because it is the first thing an office asks.
func describe(contract_sum: Money) -> String:
	if not is_sound():
		return problem()
	var parts := PackedStringArray()
	if is_percentage():
		parts.append(RateScript.percent_text(percent_ppm) + " of the contract")
	else:
		parts.append("a fixed amount")
	parts.append(amount_for(contract_sum).format_with_currency())
	parts.append(trigger_name(trigger))
	if retainage_ppm > 0:
		parts.append("%s withheld" % RateScript.percent_text(retainage_ppm))
	if is_billed():
		parts.append("billed %s on %s" % [billed_at, invoice_number])
	parts.append(state_name())
	return "%s (%s)" % [name, ", ".join(parts)]


# --- soundness ---------------------------------------------------------------------------------


## The one thing wrong with this step, or "". A loaded record can be wrong in ways the setters
## refuse, which is the whole reason this exists: the file is not the editor.
func problem() -> String:
	if name.strip_edges().is_empty():
		return "a step with no name"
	if is_percentage() and is_fixed():
		return "'%s' is priced as a share of the contract and as a fixed amount" % name
	if not is_priced():
		return "'%s' is priced as neither a share of the contract nor a fixed amount" % name
	if percent_ppm != RateScript.INVALID and (percent_ppm <= 0 or percent_ppm > RateScript.WHOLE):
		return "'%s' claims %s of the contract" % [name, RateScript.percent_text(percent_ppm)]
	if fixed_amount != null and fixed_amount.is_valid() and (fixed_amount.is_zero() or fixed_amount.is_negative()):
		return "'%s' is a fixed amount of %s" % [name, fixed_amount.format_with_currency()]
	if retainage_ppm < 0 or retainage_ppm > RateScript.WHOLE:
		return "'%s' withholds %s" % [name, RateScript.percent_text(retainage_ppm)]
	if not is_trigger(trigger):
		return "'%s' fires on a trigger nobody has" % name
	if not due_date.strip_edges().is_empty() and not RateScript.is_date(due_date):
		return "'%s' is due on a date that is not a date: '%s'" % [name, due_date]
	if is_billed() and invoice_number.strip_edges().is_empty():
		return "'%s' says it was billed and cannot say on which invoice" % name
	return ""


func is_sound() -> bool:
	return problem().is_empty()


# --- persistence -------------------------------------------------------------------------------


func copy() -> Milestone:
	return from_dict(to_dict())


func to_dict() -> Dictionary:
	return {
		"name": name,
		"percent_ppm": percent_ppm,
		"fixed_amount": null if fixed_amount == null else fixed_amount.to_dict(),
		"trigger": _trigger_key(trigger),
		"due_date": due_date,
		"retainage_ppm": retainage_ppm,
		"billed_at": billed_at,
		"invoice_number": invoice_number,
		"note": note,
	}


## A step that is not a dictionary is dropped by the caller. A step with no name is kept: it is
## wrong and it says so, and dropping it would silently change what the schedule bills.
static func from_dict(data: Dictionary) -> Milestone:
	var step: Milestone = MilestoneScript.new(String(data.get("name", "")))
	step.percent_ppm = int(data.get("percent_ppm", RateScript.INVALID))
	var fixed_in = data.get("fixed_amount", null)
	if fixed_in is Dictionary:
		step.fixed_amount = MoneyScript.from_dict(fixed_in)
	step.trigger = _trigger_from(String(data.get("trigger", "DATE")))
	step.due_date = String(data.get("due_date", ""))
	step.retainage_ppm = int(data.get("retainage_ppm", 0))
	step.billed_at = String(data.get("billed_at", ""))
	step.invoice_number = String(data.get("invoice_number", ""))
	step.note = String(data.get("note", ""))
	return step


static func _trigger_key(trigger: int) -> String:
	match trigger:
		PHASE_COMPLETE: return "PHASE_COMPLETE"
		APPROVED: return "APPROVED"
	return "DATE"


static func _trigger_from(key: String) -> int:
	match key:
		"PHASE_COMPLETE": return PHASE_COMPLETE
		"APPROVED": return APPROVED
	return DATE


const MilestoneScript := preload("res://scripts/biz/milestone.gd")