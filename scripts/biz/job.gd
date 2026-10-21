class_name Job
extends RefCounted
## A contracted job: what was agreed, how it is billed, and the budget per phase (spec §4.10).
##
## A **phase** is a cost code with a budget taken from the estimate's lines for that code, and it is
## stated *which* the budget is: the **price** the customer pays for that code, or the **cost** the
## business pays for it. Two people can compute "the budget" and get different numbers honestly, so
## the basis travels with the number (§2.9's spirit).
##
## The billing method is a property of the **contract** (§9.1) - it is what the customer agreed to -
## so it is here on the job and not on any invoice, and billing cannot change it.

const MoneyScript := preload("res://scripts/biz/money.gd")

const FIXED := 0
const MILESTONE := 1
const PERCENTAGE_COMPLETE := 2
const TIME_AND_MATERIALS := 3
const COST_PLUS := 4

## String keys: a StringName literal as a const Dictionary key fails the constant-expression check.
const BILLING_NAMES := {
	"FIXED": "fixed price",
	"MILESTONE": "milestones",
	"PERCENTAGE_COMPLETE": "percentage complete",
	"TIME_AND_MATERIALS": "time and materials",
	"COST_PLUS": "cost plus",
}

## What a phase's budget is measured against. PRICE is what the customer pays for the code; COST is
## what the business pays for it.
const PRICE := 0
const COST := 1
const BASIS_NAMES := {PRICE: "price", COST: "cost"}
const BASIS_IDS := {"PRICE": PRICE, "COST": COST}

var id: String = ""
var number: String = ""
var name: String = ""
var customer: Dictionary = {}
## The estimate revision this job was contracted from, so the budget has a lineage (§4.10).
var estimate_revision: int = 0
## What the customer agreed to pay, before tax.
var contract_sum: Money = null
var billing_method: int = FIXED
## `{cost_code, budget, basis}` - one per cost code the estimate priced.
var phases: Array[Dictionary] = []
## Blocks of this job's own schedule, as the schedule board holds them (§7.4).
var schedule: Array[Dictionary] = []
var crew: Array[StringName] = []
var documents: Array[String] = []


func _init(job_id: String = "") -> void:
	id = job_id
	contract_sum = MoneyScript.zero()


static func is_billing_method(candidate: int) -> bool:
	# By number, not by the name `_billing_key` would fall back to: a method nobody has must be
	# refused, and a fallback key would have made every unknown number read as FIXED.
	return candidate >= FIXED and candidate <= COST_PLUS


static func billing_name(method: int) -> String:
	return String(BILLING_NAMES.get(_billing_key(method), "fixed price"))


## Set how the job is billed. Refused for a method nobody has: billing is what the customer agreed to,
## and a job billed by a method the program does not understand cannot be billed at all.
func set_billing_method(method: int) -> bool:
	if not is_billing_method(method):
		return false
	billing_method = method
	return true


func set_contract_sum(amount: Money) -> bool:
	if amount == null or not amount.is_valid():
		return false
	contract_sum = amount
	return true


# --- phases, taken from the estimate -----------------------------------------------------


## Build a job's phases from an estimate, grouping the lines by cost code and summing each code's
## price (BASIS `PRICE`) or cost (BASIS `COST`). The contract sum is the estimate's price before tax,
## because tax is the customer's to remit and not the contract's value.
##
## A line with no cost code is grouped under `UNASSIGNED` rather than dropped: an estimate line that
## costs nothing to any phase is a line nobody will be paid for, and hiding it is how a job comes in
## under budget by accident.
static func from_estimate(estimate: Estimate, basis: int = PRICE) -> Job:
	var job: Job = JobScript.new(Estimate.new_id() if estimate == null else estimate.id)
	if estimate == null:
		return job
	job.customer = estimate.customer.duplicate(true)
	job.estimate_revision = estimate.revision
	job.contract_sum = estimate.price_before_tax()
	job.phases = phase_budgets(estimate, basis)
	return job


## One row per cost code the estimate prices, in code order: `{cost_code, budget, basis}`.
static func phase_budgets(estimate: Estimate, basis: int = PRICE) -> Array[Dictionary]:
	var running: Dictionary = {}
	var order: Array[String] = []
	if estimate != null:
		for line in estimate.lines:
			var code := String(line.cost_code)
			if code.is_empty():
				code = "UNASSIGNED"
			if not running.has(code):
				running[code] = MoneyScript.zero(estimate.currency)
				order.append(code)
			var amount: Money = line.cost() if basis == COST else line.extension()
			running[code] = running[code].add(amount)
	order.sort()
	var out: Array[Dictionary] = []
	for code in order:
		out.append({"cost_code": code, "budget": running[code], "basis": basis})
	return out


func phase(cost_code: String) -> Dictionary:
	for held in phases:
		if String(held["cost_code"]) == cost_code:
			return held
	return {}


func phase_codes() -> Array[String]:
	var out: Array[String] = []
	for held in phases:
		out.append(String(held["cost_code"]))
	return out


func phase_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for held in phases:
		out.append({
			"cost_code": String(held["cost_code"]),
			"budget": held["budget"],
			"basis": int(held["basis"]),
		})
	return out


## What every phase's budget comes to, in the job's contract currency.
func budget_total() -> Money:
	var amounts: Array = []
	for held in phases:
		amounts.append(held["budget"])
	return MoneyScript.sum(amounts, contract_sum.currency if contract_sum != null else &"CAD")


func basis_name(basis: int) -> String:
	return String(BASIS_NAMES.get(basis, "price"))


func assign_crew(member: StringName) -> bool:
	if String(member).strip_edges().is_empty() or crew.has(member):
		return false
	crew.append(member)
	return true


func to_dict() -> Dictionary:
	var phase_list: Array = []
	for held in phases:
		phase_list.append({
			"cost_code": String(held["cost_code"]),
			"budget": held["budget"].to_dict(),
			"basis": int(held["basis"]),
		})
	var crew_list: Array = []
	for member in crew:
		crew_list.append(String(member))
	var schedule_list: Array = []
	for block in schedule:
		schedule_list.append(block.duplicate(true))
	return {
		"id": id,
		"number": number,
		"name": name,
		"customer": customer.duplicate(true),
		"estimate_revision": estimate_revision,
		"contract_sum": (contract_sum if contract_sum != null else MoneyScript.zero()).to_dict(),
		"billing_method": _billing_key(billing_method),
		"phases": phase_list,
		"schedule": schedule_list,
		"crew": crew_list,
		"documents": documents.duplicate(),
	}


## A record with no id is **dropped rather than invented**. A billing method nobody has becomes FIXED,
## and a phase whose budget cannot be read is kept but unreadable, so the job refuses to foot rather
## than quietly costing a phase at nothing.
static func from_dict(data: Dictionary) -> Job:
	var job: Job = JobScript.new(String(data.get("id", "")))
	if job.id.is_empty():
		return null
	job.number = String(data.get("number", ""))
	job.name = String(data.get("name", ""))
	var customer_in = data.get("customer", {})
	job.customer = (customer_in as Dictionary).duplicate(true) if customer_in is Dictionary else {}
	job.estimate_revision = int(data.get("estimate_revision", 0))
	job.contract_sum = MoneyScript.from_dict(data.get("contract_sum", {}))
	job.billing_method = _method_from(String(data.get("billing_method", "FIXED")))
	var phases_in = data.get("phases", [])
	if phases_in is Array:
		for entry in (phases_in as Array):
			if entry is Dictionary:
				job.phases.append({
					"cost_code": String(entry.get("cost_code", "")),
					"budget": MoneyScript.from_dict(entry.get("budget", {})),
					"basis": int(entry.get("basis", PRICE)),
				})
	var schedule_in = data.get("schedule", [])
	if schedule_in is Array:
		for entry in (schedule_in as Array):
			if entry is Dictionary:
				job.schedule.append((entry as Dictionary).duplicate(true))
	var crew_in = data.get("crew", [])
	if crew_in is Array:
		for entry in (crew_in as Array):
			job.crew.append(StringName(entry))
	var docs_in = data.get("documents", [])
	if docs_in is Array:
		for entry in (docs_in as Array):
			job.documents.append(String(entry))
	return job


static func _billing_key(method: int) -> String:
	match method:
		FIXED: return "FIXED"
		MILESTONE: return "MILESTONE"
		PERCENTAGE_COMPLETE: return "PERCENTAGE_COMPLETE"
		TIME_AND_MATERIALS: return "TIME_AND_MATERIALS"
		COST_PLUS: return "COST_PLUS"
	return "FIXED"


static func _method_from(key: String) -> int:
	match key:
		"MILESTONE": return MILESTONE
		"PERCENTAGE_COMPLETE": return PERCENTAGE_COMPLETE
		"TIME_AND_MATERIALS": return TIME_AND_MATERIALS
		"COST_PLUS": return COST_PLUS
	return FIXED


const JobScript := preload("res://scripts/biz/job.gd")