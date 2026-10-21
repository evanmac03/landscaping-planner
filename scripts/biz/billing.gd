class_name Billing
extends RefCounted
## How a job is billed, and what it can bill right now (spec §9.1-§9.3).
##
## The **method is a property of the contract**, so it is copied here from the job and this module
## never changes it: billing is what the customer agreed to, and an invoice that could change it is
## an invoice that decides how the job is priced.
##
## The three figures that matter, and each is a function of the records rather than a running total
## kept in step by hand:
##
## * `billed_to_date` - what has actually gone out. It moves in exactly one place (`record_billed`).
## * `retainage_held` - what has been withheld, accumulated per step, released only by an explicit
##   act at closeout. Nothing releases it by itself.
## * `complete_ppm` - the measured percent complete, **stored with its basis**, because "60% complete"
##   from a cost report and from a walk around the garden are different claims (spec §9.3).
##
## The percentage-completion arithmetic is the one this whole module exists for:
## `target = contract x percent`, `due = target - billed_to_date`, never below zero. Billing 30% and
## then 60% bills 30% twice only in software that computes the *percentage* as the amount (spec §9.3,
## AC-B11). The floor at zero is deliberate and is **not** an error: billing 60% twice is refused by
## arithmetic rather than by a guard, and the refusal says why.

const MoneyScript := preload("res://scripts/biz/money.gd")
const RateScript := preload("res://scripts/biz/rate.gd")
const JobScript := preload("res://scripts/biz/job.gd")
const MilestoneScript := preload("res://scripts/biz/milestone.gd")

## What a measured percent complete is measured against. The numbers line up with the cost report's
## own bases on purpose, so the desk can pass one straight through to the other; they are repeated
## here rather than reached for across scripts, because a report's basis and a billing's basis are
## two different claims that happen to have the same two answers.
const BY_COST_INCURRED := 0
const BY_PHASE_COMPLETION := 1
const BASIS_NAMES := {
	BY_COST_INCURRED: "by cost incurred",
	BY_PHASE_COMPLETION: "by phase completion",
}

var job: String = ""
var method: int = JobScript.FIXED
## The steps of a MILESTONE schedule, in the order they fire.
var milestones: Array[Milestone] = []
var billed_to_date: Money = null
var retainage_held: Money = null
var retainage_released_at: String = ""
## The measured percent complete and the basis it was measured on. `Rate.INVALID` is "nobody has
## measured it", which is a different thing from "it is nothing per cent complete".
var complete_ppm: int = RateScript.INVALID
var percent_basis: int = RateScript.INVALID
## Retainage withheld on a method that has no steps of its own, in parts per million.
var retainage_ppm: int = 0
## What TIME_AND_MATERIALS marks materials up by, and what COST_PLUS charges as its fee.
var markup_ppm: int = 0
var fee_ppm: int = 0
var note: String = ""


func _init(job_id: String = "") -> void:
	job = job_id
	billed_to_date = MoneyScript.zero()
	retainage_held = MoneyScript.zero()


## The schedule for a job billed this way. A method nobody has falls back to the contract's own
## default rather than inventing one, and the schedule then reads as a fixed-price one.
static func for_method(job_id: String, method_key: int) -> Billing:
	var schedule: Billing = BillingScript.new(job_id)
	if JobScript.is_billing_method(method_key):
		schedule.method = method_key
	return schedule


func method_name() -> String:
	return JobScript.billing_name(method)


func currency() -> StringName:
	return billed_to_date.currency if billed_to_date != null else &"CAD"


# --- the schedule of steps ----------------------------------------------------------------------


## Add a step. Refused for a step with no name or no price, and for a second step with the same name:
## a schedule with two steps called "Deposit" is two answers to one question.
func add_milestone(step: Milestone) -> bool:
	if step == null or not step.is_sound():
		return false
	if milestone(step.name) != null:
		return false
	milestones.append(step)
	return true


func milestone(step_name: String) -> Milestone:
	for held in milestones:
		if held.name == step_name:
			return held
	return null


func milestone_names() -> Array[String]:
	var out: Array[String] = []
	for held in milestones:
		out.append(held.name)
	return out


func step_count() -> int:
	return milestones.size()


## What the schedule's percentages add up to, or `Rate.INVALID` when any step is a fixed amount and
## the schedule therefore cannot be added up as a share of the contract at all.
func claimed_ppm() -> int:
	var total: int = 0
	for held in milestones:
		if not held.is_percentage():
			return RateScript.INVALID
		total += held.percent_ppm
	return total


## What share of the contract no step claims, or `Rate.INVALID` when the schedule is in fixed amounts.
## Reported rather than refused, so a schedule that covers 87% of a job says so instead of billing
## 87% and reading as complete (spec §9.2).
func unbilled_ppm() -> int:
	var claimed: int = claimed_ppm()
	if claimed == RateScript.INVALID:
		return RateScript.INVALID
	return maxi(0, RateScript.WHOLE - claimed)


func next_pending() -> Milestone:
	for held in milestones:
		if not held.is_billed():
			return held
	return null


# --- what can be billed now ---------------------------------------------------------------------


## State the measured percent complete **and the basis it was measured on**. Refused for a percent
## nobody could have measured and for a basis nobody has: a percent with no basis is half a claim.
func set_percent_complete(ppm: int, basis: int) -> bool:
	if ppm <= 0 or ppm > RateScript.WHOLE:
		return false
	if not BASIS_NAMES.has(basis):
		return false
	complete_ppm = ppm
	percent_basis = basis
	return true


func basis_name() -> String:
	return String(BASIS_NAMES.get(percent_basis, "no basis stated"))


## What should have been billed by now at `complete_ppm`, or `Rate.INVALID` when nobody has measured.
func target_billed(contract_sum: Money) -> Money:
	if not RateScript.is_valid(complete_ppm) or contract_sum == null:
		return MoneyScript.invalid(currency())
	return contract_sum.scale_ppm(complete_ppm)


## What a job can bill right now, by its own method.
##
## Returns `{ok, reason, amount, milestone}`. `ok` with an amount of nothing is a **real answer** -
## there is nothing left to bill - and comes with the reason in words, because a zero that explains
## itself is worth more than a refusal that makes the office wonder.
func amount_due(contract_sum: Money, period_amount: Money = null, materials: Money = null,
		milestone_name: String = "") -> Dictionary:
	var refused := {
		"ok": false,
		"reason": "",
		"amount": MoneyScript.invalid(currency()),
		"milestone": "",
	}
	if contract_sum == null or not contract_sum.is_valid():
		refused["reason"] = "the contract sum is not a readable number"
		return refused
	match method:
		JobScript.FIXED:
			return _fixed_due(contract_sum)
		JobScript.MILESTONE:
			return _milestone_due(contract_sum, milestone_name)
		JobScript.PERCENTAGE_COMPLETE:
			return _percentage_due(contract_sum)
		JobScript.TIME_AND_MATERIALS:
			return _time_and_materials_due(period_amount, materials)
		JobScript.COST_PLUS:
			return _cost_plus_due(period_amount)
	refused["reason"] = "a billing method nobody has: %s" % method_name()
	return refused


func _fixed_due(contract_sum: Money) -> Dictionary:
	var left: Money = contract_sum.sub(billed_to_date)
	if not left.is_valid():
		return {"ok": false, "reason": "what has been billed is not a readable number", "amount": left, "milestone": ""}
	if left.is_negative() or left.is_zero():
		return {
			"ok": true,
			"reason": "the whole of %s has been billed" % contract_sum.format_with_currency(),
			"amount": MoneyScript.zero(contract_sum.currency),
			"milestone": "",
		}
	return {"ok": true, "reason": "the rest of the contract", "amount": left, "milestone": ""}


func _milestone_due(contract_sum: Money, milestone_name: String) -> Dictionary:
	var step: Milestone = next_pending()
	if not milestone_name.strip_edges().is_empty():
		step = milestone(milestone_name)
		if step == null:
			return {
				"ok": false,
				"reason": "this schedule has no step called '%s'" % milestone_name,
				"amount": MoneyScript.invalid(contract_sum.currency),
				"milestone": "",
			}
		if step.is_billed():
			return {
				"ok": false,
				"reason": "'%s' was billed on %s" % [step.name, step.invoice_number],
				"amount": MoneyScript.invalid(contract_sum.currency),
				"milestone": step.name,
			}
	if step == null:
		return {
			"ok": true,
			"reason": "every step of this schedule has been billed",
			"amount": MoneyScript.zero(contract_sum.currency),
			"milestone": "",
		}
	return {
		"ok": true,
		"reason": "'%s' (%s)" % [step.name, MilestoneScript.trigger_name(step.trigger)],
		"amount": step.amount_for(contract_sum),
		"milestone": step.name,
	}


func _percentage_due(contract_sum: Money) -> Dictionary:
	if not RateScript.is_valid(complete_ppm):
		return {
			"ok": false,
			"reason": "nobody has measured the percent complete of this job",
			"amount": MoneyScript.invalid(contract_sum.currency),
			"milestone": "",
		}
	var target: Money = target_billed(contract_sum)
	if not target.is_valid():
		return {
			"ok": false,
			"reason": "the measured percent complete cannot be applied to this contract",
			"amount": target,
			"milestone": "",
		}
	var left: Money = target.sub(billed_to_date)
	if not left.is_valid():
		return {
			"ok": false,
			"reason": "what has been billed is not a readable number",
			"amount": left,
			"milestone": "",
		}
	var claim: String = "%s %s" % [RateScript.percent_text(complete_ppm), basis_name()]
	if left.is_negative() or left.is_zero():
		return {
			"ok": true,
			"reason": "%s is already billed: %s of a target of %s" % [
				claim,
				billed_to_date.format_with_currency(),
				target.format_with_currency(),
			],
			"amount": MoneyScript.zero(contract_sum.currency),
			"milestone": "",
		}
	return {
		"ok": true,
		"reason": "%s of %s, less %s already billed" % [
			claim,
			target.format_with_currency(),
			billed_to_date.format_with_currency(),
		],
		"amount": left,
		"milestone": "",
	}


## TIME_AND_MATERIALS for a period: the labour the period is billed at, and the materials at their
## markup. Two figures rather than one, because the markup applies to the materials alone (spec §9.1)
## and a single number would have to have the markup baked into it by whoever typed it.
func _time_and_materials_due(labour: Money, materials: Money) -> Dictionary:
	var nothing: Money = MoneyScript.zero(currency())
	var stated_materials: Money = materials if materials != null else nothing
	if labour == null or not labour.is_valid() or not stated_materials.is_valid():
		return {
			"ok": false,
			"reason": "the period's figures are not readable numbers",
			"amount": MoneyScript.invalid(currency()),
			"milestone": "",
		}
	var amount: Money = time_and_materials_amount(labour, stated_materials, markup_ppm)
	if amount.is_negative():
		return {"ok": true, "reason": "the period comes to a credit", "amount": amount, "milestone": ""}
	return {
		"ok": true,
		"reason": "the period's labour of %s and materials of %s at %s" % [
			labour.format_with_currency(),
			stated_materials.format_with_currency(),
			RateScript.percent_text(markup_ppm),
		],
		"amount": amount,
		"milestone": "",
	}


## COST_PLUS for a period: the cost incurred, plus the fee.
func _cost_plus_due(cost: Money) -> Dictionary:
	if cost == null or not cost.is_valid():
		return {
			"ok": false,
			"reason": "the period's cost is not a readable number",
			"amount": MoneyScript.invalid(currency()),
			"milestone": "",
		}
	var amount: Money = cost_plus_amount(cost, fee_ppm)
	if amount.is_negative():
		return {"ok": true, "reason": "the period comes to a credit", "amount": amount, "milestone": ""}
	return {
		"ok": true,
		"reason": "the period's cost of %s plus a fee of %s" % [
			cost.format_with_currency(),
			RateScript.percent_text(fee_ppm),
		],
		"amount": amount,
		"milestone": "",
	}


## What is withheld from an amount: a named step's own rate, or the schedule's own default for a
## method that has no steps. Zero is the common answer.
func retainage_due(contract_sum: Money, amount: Money, milestone_name: String = "") -> Money:
	var code: StringName = amount.currency if amount != null else currency()
	if amount == null or not amount.is_valid():
		return MoneyScript.invalid(code)
	var step: Milestone = milestone(milestone_name) if not milestone_name.strip_edges().is_empty() else null
	if step != null:
		return step.retainage_for(contract_sum)
	return amount.scale_ppm(retainage_ppm) if retainage_ppm > 0 else MoneyScript.zero(code)


# --- recording what happened --------------------------------------------------------------------


## Record that an invoice for `amount` went out. **The only place `billed_to_date` moves**, so what
## has been billed cannot drift from the invoices that were issued.
##
## Naming a step bills it, and withholds its own retainage. A naming that cannot be billed - a step
## that is already billed, or one the schedule does not have - is refused rather than quietly treated
## as a step-less billing, because a schedule and a set of invoices that disagree about what has been
## billed is the one thing this module is here to prevent.
func record_billed(contract_sum: Money, amount: Money, at: String, invoice_number: String,
		milestone_name: String = "") -> Dictionary:
	if amount == null or not amount.is_valid():
		return {"ok": false, "reason": "the amount is not a readable number"}
	if amount.is_negative():
		return {"ok": false, "reason": "a negative invoice is a credit note and not a billing"}
	if at.strip_edges().is_empty() or invoice_number.strip_edges().is_empty():
		return {"ok": false, "reason": "a billing with no moment or no invoice number"}
	var step: Milestone = null
	if not milestone_name.strip_edges().is_empty():
		step = milestone(milestone_name)
		if step == null:
			return {"ok": false, "reason": "this schedule has no step called '%s'" % milestone_name}
		if not step.mark_billed(at, invoice_number):
			return {"ok": false, "reason": "'%s' was already billed on %s" % [step.name, step.invoice_number]}
	var moved: Money = billed_to_date.add(amount)
	if not moved.is_valid():
		return {"ok": false, "reason": "what has been billed is in another currency"}
	billed_to_date = moved
	if step != null:
		var held: Money = retainage_held.add(step.retainage_for(contract_sum))
		if not held.is_valid():
			return {"ok": false, "reason": "the retainage held is in another currency"}
		retainage_held = held
	return {"ok": true, "reason": ""}


## Release everything withheld, at closeout. An explicit act: nothing here releases it by itself.
##
## A release with nothing held is **a zero and not a second release**: it must not restamp the date,
## because "retainage was released on the 2nd" written over "released on the 1st" is a record that no
## longer says when the money moved.
func release_retainage(at: String) -> Money:
	if at.strip_edges().is_empty():
		return MoneyScript.invalid(currency())
	var released: Money = retainage_held if retainage_held != null else MoneyScript.zero(currency())
	if not released.is_valid():
		return released
	if released.is_zero():
		return released
	retainage_held = MoneyScript.zero(released.currency)
	retainage_released_at = at
	return released


# --- the arithmetic of the two methods with no schedule -----------------------------------------


## TIME_AND_MATERIALS for a period: hours x the billing rate, plus materials at their markup.
## Labour is billed at what it is worth, not at what it cost, which is why the markup is applied to
## the materials alone (spec §9.1).
static func time_and_materials_amount(labour: Money, materials: Money, markup_ppm: int) -> Money:
	if labour == null or materials == null:
		return MoneyScript.invalid(&"CAD")
	var materials_billed: Money = materials.add(materials.scale_ppm(markup_ppm))
	if not materials_billed.is_valid():
		return materials_billed
	return labour.add(materials_billed)


## COST_PLUS for a period: the cost incurred, plus the fee.
static func cost_plus_amount(cost: Money, fee_ppm: int) -> Money:
	if cost == null or not cost.is_valid():
		return MoneyScript.invalid(&"CAD")
	return cost.add(cost.scale_ppm(fee_ppm))


# --- soundness ----------------------------------------------------------------------------------


func problems() -> Array[String]:
	var out: Array[String] = []
	if not JobScript.is_billing_method(method):
		out.append("a billing method nobody has: %s" % method_name())
	if billed_to_date == null or not billed_to_date.is_valid():
		out.append("what has been billed is not a readable number")
	if retainage_held == null or not retainage_held.is_valid():
		out.append("the retainage held is not a readable number")
	if retainage_ppm < 0 or retainage_ppm > RateScript.WHOLE:
		out.append("a retainage of %s" % RateScript.percent_text(retainage_ppm))
	if RateScript.is_valid(complete_ppm) and not BASIS_NAMES.has(percent_basis):
		out.append("a measured percent complete with no basis stated")
	for index in milestones.size():
		var held: Milestone = milestones[index]
		if held == null:
			out.append("step %d is not a step" % (index + 1))
		elif not held.is_sound():
			out.append(held.problem())
	if method == JobScript.MILESTONE and milestones.is_empty():
		out.append("a job billed by milestones with no milestones")
	var claimed: int = claimed_ppm()
	if claimed != RateScript.INVALID:
		if claimed > RateScript.WHOLE:
			out.append("the steps claim %s of the contract" % RateScript.percent_text(claimed))
		elif claimed < RateScript.WHOLE and milestones.size() > 0:
			out.append("%s of the contract is claimed by no step" % RateScript.percent_text(RateScript.WHOLE - claimed))
	return out


func is_sound() -> bool:
	return problems().is_empty()


func describe() -> String:
	var parts := PackedStringArray()
	parts.append(method_name())
	if method == JobScript.MILESTONE:
		parts.append("%d step(s)" % milestones.size())
		if claimed_ppm() == RateScript.INVALID:
			parts.append("in fixed amounts")
		else:
			parts.append("%s of the contract in all" % RateScript.percent_text(claimed_ppm()))
	elif method == JobScript.PERCENTAGE_COMPLETE:
		if RateScript.is_valid(complete_ppm):
			parts.append("%s complete %s" % [RateScript.percent_text(complete_ppm), basis_name()])
		else:
			parts.append("nobody has measured the percent complete")
	parts.append("%s billed" % billed_to_date.format_with_currency())
	if retainage_held != null and not retainage_held.is_zero():
		parts.append("%s retained" % retainage_held.format_with_currency())
	elif not retainage_released_at.strip_edges().is_empty():
		parts.append("retainage released %s" % retainage_released_at)
	return ", ".join(parts)


# --- persistence --------------------------------------------------------------------------------


func to_dict() -> Dictionary:
	var steps: Array = []
	for held in milestones:
		steps.append(held.to_dict())
	return {
		"job": job,
		"method": _method_key(method),
		"milestones": steps,
		"billed_to_date": (billed_to_date if billed_to_date != null else MoneyScript.zero()).to_dict(),
		"retainage_held": (retainage_held if retainage_held != null else MoneyScript.zero()).to_dict(),
		"retainage_released_at": retainage_released_at,
		"complete_ppm": complete_ppm,
		"percent_basis": percent_basis,
		"retainage_ppm": retainage_ppm,
		"markup_ppm": markup_ppm,
		"fee_ppm": fee_ppm,
		"note": note,
	}


## A step that is not a dictionary is dropped and the rest of the schedule reads. A percent complete
## whose basis did not survive becomes a percent with no basis, which `problems()` names rather than
## guessing at - the reader must not invent the claim the office made.
static func from_dict(data: Dictionary) -> Billing:
	var schedule: Billing = BillingScript.new(String(data.get("job", "")))
	schedule.method = JobScript._method_from(String(data.get("method", "FIXED")))
	var steps_in = data.get("milestones", [])
	if steps_in is Array:
		for entry in (steps_in as Array):
			if entry is Dictionary:
				schedule.milestones.append(MilestoneScript.from_dict(entry))
	schedule.billed_to_date = MoneyScript.from_dict(data.get("billed_to_date", {}))
	schedule.retainage_held = MoneyScript.from_dict(data.get("retainage_held", {}))
	schedule.retainage_released_at = String(data.get("retainage_released_at", ""))
	schedule.complete_ppm = int(data.get("complete_ppm", RateScript.INVALID))
	schedule.percent_basis = int(data.get("percent_basis", RateScript.INVALID))
	schedule.retainage_ppm = int(data.get("retainage_ppm", 0))
	schedule.markup_ppm = int(data.get("markup_ppm", 0))
	schedule.fee_ppm = int(data.get("fee_ppm", 0))
	schedule.note = String(data.get("note", ""))
	return schedule


static func _method_key(method_key: int) -> String:
	match method_key:
		JobScript.MILESTONE: return "MILESTONE"
		JobScript.PERCENTAGE_COMPLETE: return "PERCENTAGE_COMPLETE"
		JobScript.TIME_AND_MATERIALS: return "TIME_AND_MATERIALS"
		JobScript.COST_PLUS: return "COST_PLUS"
	return "FIXED"


const BillingScript := preload("res://scripts/biz/billing.gd")