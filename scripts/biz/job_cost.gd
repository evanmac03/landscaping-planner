class_name JobCost
extends RefCounted
## The job cost report: budget, committed and actual per cost code, and the numbers they come to
## (spec §8.4, REQ-B17).
##
## It is a **report of records and not a store of them**. `JobCost.of(job, orders, changes, entries)`
## reads the job, its purchase orders, its change orders and its time entries and computes every figure
## from them, so a report opened twice says the same thing twice, and a report opened after a receipt
## was entered says the new thing. Nothing here is written down.
##
## ## The three numbers, and why committed is separate
##
## * **budget** - the estimate's own figures for that cost code, with the **basis** it was taken on:
##   the price the customer pays, or the cost the business pays. Two people can compute "the budget"
##   and honestly get different numbers, so the basis travels with the number (§2.9).
## * **committed** - issued and not yet arrived. REQ-B17: derived from issued-not-received purchase
##   orders, **never** from an in-memory flag.
## * **actual** - what has arrived (priced at the order's own line rates) plus approved time.
##
## A pending time entry is **not** cost: it is counted and shown beside it, so a report never reads low
## without saying why (§7.3).
##
## ## A change order is revenue, not cost
##
## An approved change order raises the contract sum. Its **cost** appears here the same way any other
## cost does - through the purchase orders and the hours that carry that cost code - so the report does
## not need a rule about change orders to be right, and a change whose work costs more than it was sold
## for shows up as a variance instead of hiding inside an adjusted budget.
##
## ## Earned, and the margin on it
##
## `gross margin to date` is what has been **earned** at the percent complete, less what the job has
## cost; the earned figure is the agreed sum scaled by that percent, which is the ordinary
## percentage-of-completion reading. It is deliberately **not capped at the contract sum**: a job that
## has spent more than its budget then shows a percent above 100 and a margin that has to be explained,
## rather than a cap quietly making a loss look like a job on plan (§8.4, REQ-B20).

const MoneyScript := preload("res://scripts/biz/money.gd")
const JobScript := preload("res://scripts/biz/job.gd")
const OrderScript := preload("res://scripts/biz/purchase_order.gd")
const ChangeScript := preload("res://scripts/biz/change_order.gd")
const EntryScript := preload("res://scripts/biz/time_entry.gd")

## The basis the cost incurred is measured on. Stated on every report, because §8.4 says the report
## says which: cost incurred now, a milestone in phase 7.
const BY_COST_INCURRED := "by cost incurred"
const BY_MILESTONE := "by milestone"

const BASIS_NAMES := {"cost": "by cost incurred", "milestone": "by milestone"}

## Parts per million, the module's one rate unit (§2.1).
const PPM := 1000000

var job_reference: Job = null
var currency: StringName = &"CAD"
## One row per cost code the job has a budget for **or** a record against, in code order.
var rows: Array[Dictionary] = []
## Invoiced to date, or invalid when nobody has said - never zero, which would read as "nothing has
## been billed" when the truth is "this report was not told".
var billed: Money = null
var paid: Money = null
var percent_basis: String = BY_COST_INCURRED
## What a person should know about the figures but which is not a fault: which basis the budget is on,
## and which figures nobody has supplied.
var notes: Array[String] = []
## The change orders this report was built with, so what is pending is counted once and always from
## the same records the rows were built from.
var _pending: Array = []


# --- building the report --------------------------------------------------------------------


## Read a job and its records into a report. Every argument is a list of records and nothing else: the
## orders, the changes and the entries can come from anywhere, which is what makes this testable
## without a database.
static func of(contracted: Job, orders: Array, changes: Array, entries: Array,
		invoiced: Money = null, received: Money = null) -> JobCost:
	var report: JobCost = ReportScript.new()
	report.job_reference = contracted
	report.currency = _currency_of(contracted)
	report.billed = invoiced if invoiced != null else MoneyScript.invalid(report.currency)
	report.paid = received if received != null else MoneyScript.invalid(report.currency)
	for change in changes:
		if change is ChangeScript and (change as ChangeScript).is_pending():
			report._pending.append(change)
	for code in _codes(contracted, orders, changes, entries):
		report.rows.append(_row_for(contracted, orders, changes, entries, code, report.currency))
	report.notes = _notes(contracted, report.billed)
	return report


## Every cost code this report has something to say about: the job's own phases, and any code a
## record carries. A code nobody budgeted but somebody spent against is the honest overrun, so it gets
## a row with a budget of nothing rather than being left out of the report.
static func _codes(contracted: Job, orders: Array, changes: Array, entries: Array) -> Array[String]:
	var found: Array[String] = []
	if contracted != null:
		for held in contracted.phases:
			var code := String(held.get("cost_code", ""))
			if not code.is_empty() and not found.has(code):
				found.append(code)
	for order in orders:
		if order is OrderScript:
			var held: OrderScript = order
			_collect(found, String(held.cost_code))
	for change in changes:
		if change is ChangeScript:
			var raised: ChangeScript = change
			if raised.enters_contract_sum():
				for code in raised.code_amounts().keys():
					_collect(found, String(code))
	for entry in entries:
		if entry is EntryScript:
			var spent: EntryScript = entry
			_collect(found, String(spent.cost_code))
	found.sort()
	return found


## The currency a job's money is in. `Job` has no currency field of its own - a job's money comes from
## the estimate it was made from, so it is read off the contract sum when there is one and off the
## first budget otherwise. A job with no money at all is in the module's default.
static func _currency_of(contracted: Job) -> StringName:
	if contracted == null:
		return &"CAD"
	if contracted.contract_sum != null and contracted.contract_sum.is_valid():
		return contracted.contract_sum.currency
	for held in contracted.phases:
		var money: Money = held.get("budget", null)
		if money != null and money.is_valid():
			return money.currency
	return &"CAD"


static func _collect(into: Array[String], code: String) -> void:
	var clean := code if not code.is_empty() else "UNASSIGNED"
	if not into.has(clean):
		into.append(clean)


static func _row_for(contracted: Job, orders: Array, changes: Array, entries: Array, code: String,
		code_currency: StringName) -> Dictionary:
	var basis := _basis_for(contracted, code)
	var budget := MoneyScript.zero(code_currency)
	var has_budget := false
	if contracted != null:
		var phase: Dictionary = contracted.phase(code)
		if not phase.is_empty():
			budget = phase["budget"]
			has_budget = true
	var approved := MoneyScript.sum(_change_amounts(changes, code), code_currency)
	var revised := budget.add(approved)
	var committed := MoneyScript.sum(_order_field(orders, code, "committed"), code_currency)
	var actual := MoneyScript.sum(
		_order_field(orders, code, "actual") + _entry_amounts(entries, code), code_currency
	)
	var variance := budget.sub(actual)
	var projection := budget.sub(actual).sub(committed)
	var row := {
		"cost_code": code,
		"basis": basis,
		"basis_name": contracted.basis_name(basis) if contracted != null else "price",
		"budget": budget,
		"has_budget": has_budget,
		"changes_approved": approved,
		"revised_budget": revised,
		"committed": committed,
		"actual": actual,
		"variance": variance,
		"variance_after_changes": revised.sub(actual),
		"projection": projection,
		"projection_after_changes": revised.sub(actual).sub(committed),
		"percent_ppm": _percent(actual, budget),
		"percent_known": budget.cents > 0 and actual.is_valid() and budget.is_valid(),
		"over_committed": committed.is_valid() and budget.is_valid() and committed.cents > budget.cents,
	}
	return row


static func _basis_for(contracted: Job, code: String) -> int:
	if contracted != null:
		var phase: Dictionary = contracted.phase(code)
		if not phase.is_empty():
			return int(phase.get("basis", JobScript.PRICE))
	return _dominant_basis(contracted)


## The approved change order money for one cost code.
static func _change_amounts(changes: Array, code: String) -> Array:
	var out: Array = []
	for change in changes:
		if change is ChangeScript:
			var raised: ChangeScript = change
			if not raised.enters_contract_sum():
				continue
			var amounts: Dictionary = raised.code_amounts()
			if amounts.has(code):
				out.append(amounts[code])
	return out


## One field of every order on a code, as the list the sums are built from.
static func _order_field(orders: Array, code: String, field: String) -> Array:
	var out: Array = []
	for order in orders:
		if not (order is OrderScript):
			continue
		var held: OrderScript = order
		if String(held.cost_code) != code:
			continue
		out.append(held.committed() if field == "committed" else held.actual())
	return out


## The money on the **approved** time entries for one cost code. A pending entry is not cost.
static func _entry_amounts(entries: Array, code: String) -> Array:
	var out: Array = []
	for entry in entries:
		if entry is EntryScript:
			var held: EntryScript = entry
			if String(held.cost_code) == code and held.is_approved():
				out.append(held.labour())
	return out


## Cost incurred against budget, in parts per million. Nothing when there is no budget: a code with no
## budget is not 100% complete, it is unmeasured.
static func _percent(spent: Money, budget: Money) -> int:
	if budget == null or not budget.is_valid() or budget.cents <= 0:
		return 0
	if spent == null or not spent.is_valid():
		return 0
	return MoneyScript.rounded_div(spent.cents * PPM, budget.cents)


static func _notes(contracted: Job, already_billed: Money) -> Array[String]:
	var out: Array[String] = []
	if contracted != null:
		if _dominant_basis(contracted) == JobScript.PRICE:
			out.append("the budget is the price the customer pays for each code, so a variance "
				+ "against it is a margin to date and not a cost overrun")
		else:
			out.append("the budget is the cost the business pays for each code")
	if not already_billed.is_valid():
		out.append("nothing has been invoiced, so what has been billed and what is uncollected "
			+ "are not known rather than nothing")
	return out


## The basis a job's phases are on, for the sentence the report says about its own figures. A job with
## no phases has none, and the shipped default is the price.
static func _dominant_basis(contracted: Job) -> int:
	if contracted == null or contracted.phases.is_empty():
		return JobScript.PRICE
	return int(contracted.phases[0].get("basis", JobScript.PRICE))


# --- reading it -------------------------------------------------------------------------------


func row_for(code: String) -> Dictionary:
	for held in rows:
		if String(held["cost_code"]) == code:
			return held
	return {}


func codes() -> Array[String]:
	var out: Array[String] = []
	for held in rows:
		out.append(String(held["cost_code"]))
	return out


## Whether a code has more committed against it than its budget: the flag §8.4 wants raised **at the
## moment the order is issued**, not three weeks later at the WIP review.
func over_committed_codes() -> Array[String]:
	var out: Array[String] = []
	for held in rows:
		if bool(held["over_committed"]):
			out.append(String(held["cost_code"]))
	return out


## Every figure added up, each with the basis it is on (§8.4's breakdown).
func totals() -> Dictionary:
	var budgets: Array = []
	var committeds: Array = []
	var actuals: Array = []
	for held in rows:
		budgets.append(held["budget"])
		committeds.append(held["committed"])
		actuals.append(held["actual"])
	var budget := MoneyScript.sum(budgets, currency)
	var committed := MoneyScript.sum(committeds, currency)
	var actual := MoneyScript.sum(actuals, currency)
	var approved := MoneyScript.sum(_approved_change_amounts(), currency)
	var pending := _pending_changes()
	var contract_sum := MoneyScript.zero(currency)
	if job_reference != null and job_reference.contract_sum != null:
		contract_sum = job_reference.contract_sum
	var agreed := contract_sum.add(approved)
	var percent := _percent(actual, budget)
	# What has been earned at that percent complete, and the margin on it. Both are refused rather
	# than guessed when the percent is not known.
	var earned := MoneyScript.invalid(currency)
	var margin := MoneyScript.invalid(currency)
	if budget.cents > 0 and percent > 0 and agreed.is_valid():
		earned = MoneyScript.round_div(agreed.cents * percent, PPM, currency)
		margin = earned.sub(actual)
	var billed_known := billed != null and billed.is_valid()
	var uncollected := MoneyScript.invalid(currency)
	if billed_known and paid != null and paid.is_valid():
		uncollected = billed.sub(paid)
	return {
		"contract_sum": contract_sum,
		"changes_approved": approved,
		"changes_pending": pending["total"],
		"pending_count": int(pending["count"]),
		"agreed_sum": agreed,
		"budget": budget,
		"committed": committed,
		"actual": actual,
		"cost": actual,
		"variance": budget.sub(actual),
		"projection": budget.sub(actual).sub(committed),
		"percent_ppm": percent,
		"percent_known": budget.cents > 0,
		"percent_basis": percent_basis,
		"earned": earned,
		"margin_to_date": margin,
		"margin_known": margin.is_valid(),
		"billed": billed,
		"billed_known": billed_known,
		"paid": paid if paid != null else MoneyScript.invalid(currency),
		"uncollected": uncollected,
		"uncollected_known": uncollected.is_valid(),
	}


func _approved_change_amounts() -> Array:
	var out: Array = []
	for held in rows:
		out.append(held["changes_approved"])
	return out


## Pending change orders: what is not agreed yet, with its count, which is what REQ-B18 says is shown
## beside the contract sum.
func _pending_changes() -> Dictionary:
	var amounts: Array = []
	var waiting := 0
	for change in _pending:
		waiting += 1
		amounts.append((change as ChangeScript).amount())
	return {"total": MoneyScript.sum(amounts, currency), "count": waiting}


# --- what is wrong with it --------------------------------------------------------------------


## What is wrong with the job as it stands, in sentences. REQ-B17's flag lives here: a code with more
## committed than budget is a problem **now**, while the order can still be changed.
func problems() -> Array[String]:
	var out: Array[String] = []
	for held in rows:
		var code := String(held["cost_code"])
		var budget: Money = held["budget"]
		if bool(held["over_committed"]):
			out.append("%s is committed %s against a budget of %s" % [
				code, (held["committed"] as Money).format_with_currency(),
				budget.format_with_currency(),
			])
		elif not bool(held["has_budget"]) and (held["actual"] as Money).cents > 0:
			out.append("%s has cost %s and has no budget at all" % [
				code, (held["actual"] as Money).format_with_currency(),
			])
	if not _pending.is_empty():
		var pending := _pending_changes()
		out.append("%d change order%s pending, %s not yet agreed" % [
			int(pending["count"]), "" if int(pending["count"]) == 1 else "s",
			(pending["total"] as Money).format_with_currency(),
		])
	return out


## The one line the HUD's menu and the window's heading say.
func describe() -> String:
	var figures := totals()
	if rows.is_empty():
		return "nothing has been costed to this job yet"
	var parts := PackedStringArray()
	parts.append("budget %s" % (figures["budget"] as Money).format_with_currency())
	parts.append("committed %s" % (figures["committed"] as Money).format_with_currency())
	parts.append("actual %s" % (figures["actual"] as Money).format_with_currency())
	parts.append("projection %s" % (figures["projection"] as Money).format_with_currency())
	if bool(figures["percent_known"]):
		parts.append("%.1f%% complete %s" % [
			float(int(figures["percent_ppm"])) / 10000.0, percent_basis,
		])
	else:
		parts.append("no budget to measure completion against")
	return ", ".join(parts)


## The breakdown §8.4 calls the one nobody can avoid agreeing with, one line per figure, each with its
## basis said out loud.
func totals_text() -> String:
	var figures := totals()
	var lines := PackedStringArray()
	lines.append("%-22s %s" % ["contract sum", (figures["contract_sum"] as Money).format_with_currency()])
	if (figures["changes_approved"] as Money).cents != 0 \
			or (figures["changes_pending"] as Money).cents != 0:
		lines.append("%-22s %s" % [
			"change orders agreed", (figures["changes_approved"] as Money).format_with_currency(),
		])
		if int(figures["pending_count"]) > 0:
			lines.append("%-22s %s  (%d pending, not agreed)" % [
				"change orders pending", (figures["changes_pending"] as Money).format_with_currency(),
				int(figures["pending_count"]),
			])
	lines.append("%-22s %s" % ["cost incurred", (figures["cost"] as Money).format_with_currency()])
	if bool(figures["margin_known"]):
		lines.append("%-22s %s  (earned %s at percent complete, %s)" % [
			"gross margin to date", (figures["margin_to_date"] as Money).format_with_currency(),
			(figures["earned"] as Money).format_with_currency(), percent_basis,
		])
	else:
		lines.append("%-22s not known: %s" % ["gross margin", "no budget to measure it against"])
	if bool(figures["billed_known"]):
		lines.append("%-22s %s" % ["billed", (figures["billed"] as Money).format_with_currency()])
		if bool(figures["uncollected_known"]):
			lines.append("%-22s %s" % [
				"uncollected", (figures["uncollected"] as Money).format_with_currency(),
			])
	else:
		lines.append("%-22s not known: nothing has been invoiced" % "billed")
	for note in notes:
		lines.append(note)
	return "\n".join(lines)


func row_text(code: String) -> String:
	var held := row_for(code)
	if held.is_empty():
		return "%s is not on this report" % code
	return "%s  budget %s  committed %s  actual %s  variance %s" % [
		code,
		(held["budget"] as Money).format_with_currency(),
		(held["committed"] as Money).format_with_currency(),
		(held["actual"] as Money).format_with_currency(),
		(held["variance"] as Money).format_with_currency(),
	]


# --- the question that matters before an order goes out -----------------------------------------


## Whether issuing an order of `amount` for `cost_code` would commit the job past what is left of that
## code's budget. Asked **before** the order is sent: §8.4 says the flag is raised at the moment the PO
## is issued, because that is the only moment the office can still do something about it.
##
## Returns `{over, remaining, reason}`, where the reason is a sentence naming both numbers.
static func over_commitment(contracted: Job, orders: Array, cost_code: StringName, amount: Money) -> Dictionary:
	var code := String(cost_code)
	var currency_code: StringName = _currency_of(contracted)
	var budget := MoneyScript.zero(currency_code)
	if contracted != null:
		var phase: Dictionary = contracted.phase(code)
		if not phase.is_empty():
			budget = phase["budget"]
	var committed := MoneyScript.sum(_order_field(orders, code, "committed"), currency_code)
	var remaining := budget.sub(committed)
	if amount == null or not amount.is_valid():
		return {"over": false, "remaining": remaining,
			"reason": ""}
	var after := committed.add(amount)
	var over := after.cents > budget.cents
	return {
		"over": over,
		"remaining": remaining,
		"reason": "%s would be committed %s against a budget of %s" % [
			code, after.format_with_currency(), budget.format_with_currency(),
		] if over else "",
	}


const ReportScript := preload("res://scripts/biz/job_cost.gd")