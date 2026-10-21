class_name BillingDesk
extends RefCounted
## What a job has been billed and what the customer has paid: phase 7's engines, joined to a screen
## (spec §9).
##
## Phase 7's five models are pure. `Billing` knows how a job is billed and what it can bill right now,
## `Milestone` is one step of a schedule, `Invoice` is one document, `Payment` is money received, and
## `Rate` is the one place a percentage is read and printed. None of them knows that a screen exists.
## This class is the join, and like `JobDesk` and `EstimateDesk` it is deliberately thin: it holds
## them, runs the hand-offs they already define, and answers the questions a page asks in words.
##
## It is **not** a sixth engine and it holds no arithmetic of its own. What a job can bill is
## `Billing.amount_due`; what is withheld is `Billing.retainage_due`; what is outstanding is
## `Invoice.balance`. A desk that recomputed any one of them would be a second place the rule lives,
## and the two would drift.
##
## ## The three things it does decide
##
## * **The contract sum comes from the job and never from an invoice.** An invoice is a document drawn
##   out of the contract, and a document that carried its own idea of what the job is worth would be a
##   second contract.
## * **An invoice is written and issued in one act.** A page with two buttons for one intention is a
##   page that gets one of them wrong, which is the rule §8.3 already gives about purchase orders. The
##   model keeps drafts available; this desk does not need the intermediate state.
## * **A voided invoice takes its billing off the schedule with it.** A schedule that still says a step
##   went out when the document was called back will never offer it again, so the reissue a void exists
##   to make possible could not happen. `Billing.record_billed` is the only place `billed_to_date` goes
##   up, and this file is the only place it comes back down.

const JobDeskScript := preload("res://scripts/biz/job_desk.gd")
const JobScript := preload("res://scripts/biz/job.gd")
const BillingScript := preload("res://scripts/biz/billing.gd")
const MilestoneScript := preload("res://scripts/biz/milestone.gd")
const InvoiceScript := preload("res://scripts/biz/invoice.gd")
const PaymentScript := preload("res://scripts/biz/payment.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")
const RateScript := preload("res://scripts/biz/rate.gd")
const SheetScript := preload("res://scripts/invoice_sheet.gd")

## Net 30: what a landscape contract usually says when nobody says otherwise. A term is a property of
## the agreement, so the desk states one and every invoice the desk raises uses it.
const DEFAULT_TERMS_DAYS := 30
const DEFAULT_SHEET := "LETTER"
## Where a written invoice lands, beside the proposals a business already sends from here.
const INVOICE_FOLDER := "user://biz/invoices"
## The series a payment is numbered under. A payment is not numbered paper the way an invoice is, but a
## payment that cannot be named cannot be un-applied either, so it needs one.
const PAYMENT_PREFIX := "PMT-"

## The business's own letterhead, as lines: the name first, then its address and whatever else goes
## above the rule. Held here rather than typed on the page for the reason a letterhead is printed once.
var company: Array[String] = []
var contact: Array[String] = []
## The paper an invoice is printed on, by `InvoiceSheet`'s own name for it.
var sheet: String = DEFAULT_SHEET

## The jobs. A desk that billed a job it did not have would be billing nothing.
var desk: JobDesk = null
## One billing schedule per job, keyed by job id. A job with no entry here has **not started being
## billed**, which is a different thing from a job that cannot bill anything yet.
var billings: Dictionary = {}
var invoices: Array[Invoice] = []
## Terms in days, and the month a fiscal year starts in. Both are properties of the business.
var terms_days: int = DEFAULT_TERMS_DAYS
var fiscal_start_month: int = 1


func _init() -> void:
	desk = JobDeskScript.new()


# --- the jobs -----------------------------------------------------------------------------------


## Point the desk at the jobs. A null desk becomes an empty one rather than a desk with nothing.
func bind(job_desk: JobDesk) -> void:
	desk = job_desk if job_desk != null else JobDeskScript.new()


func job_ids() -> Array[String]:
	if desk == null:
		return []
	return desk.job_ids()


func job_of(job_id: String) -> Job:
	if desk == null:
		return null
	return desk.job(job_id)


func has_job(job_id: String) -> bool:
	return job_of(job_id) != null


## What a job is called, by the job desk's own rule.
func job_label(job_id: String) -> String:
	if desk == null:
		return job_id
	return desk.job_label(job_id)


func currency_of(job_id: String = "") -> StringName:
	var held: Job = job_of(job_id)
	if held != null and held.contract_sum != null and held.contract_sum.is_valid():
		return held.contract_sum.currency
	return desk.currency if desk != null else &"CAD"


## What the contract is worth. The job's own figure, and **invalid** for a job this desk does not have:
## a contract sum invented here would be an invoice drawn out of nothing.
func contract_sum_of(job_id: String) -> Money:
	var held: Job = job_of(job_id)
	if held == null or held.contract_sum == null or not held.contract_sum.is_valid():
		return MoneyScript.invalid(currency_of(job_id))
	return held.contract_sum


# --- the billing schedule -----------------------------------------------------------------------


## The schedule a job is billed by, or **null** when nobody has started billing it. Null rather than a
## fresh schedule, because a schedule that materialized when it was read would look like a decision
## the office had made.
func billing_for(job_id: String) -> Billing:
	var held = billings.get(job_id, null)
	return held if held is Billing else null


func has_billing(job_id: String) -> bool:
	return billing_for(job_id) != null


func billing_count() -> int:
	return billings.size()


## Start billing a job, by the method the **contract** agreed to. Refused for a job this desk does not
## have and for one that is already being billed: a second schedule for one job is two answers to what
## the customer owes.
func start_billing(job_id: String) -> Billing:
	var held: Job = job_of(job_id)
	if held == null or billing_for(job_id) != null:
		return null
	var schedule: Billing = BillingScript.for_method(job_id, held.billing_method)
	billings[job_id] = schedule
	return schedule


## Take a schedule as it was read from a file. Refused for a schedule that names no job, or one for a
## job this desk does not have: it would be money against nothing.
func add_billing(schedule: Billing) -> bool:
	if schedule == null or schedule.job.strip_edges().is_empty():
		return false
	if job_of(schedule.job) == null or billing_for(schedule.job) != null:
		return false
	billings[schedule.job] = schedule
	return true


## Add a step priced as a share of the contract. Refused for everything `Milestone.set_percent`
## refuses, and for a job with no schedule.
## Returns `{ok, reason}`.
func add_milestone(job_id: String, step_name: String, ppm: int,
		trigger: int = MilestoneScript.DATE, due_date: String = "",
		retainage_ppm: int = 0) -> Dictionary:
	var schedule: Billing = billing_for(job_id)
	if schedule == null:
		return {"ok": false, "reason": "this job is not being billed yet"}
	var step: Milestone = MilestoneScript.new(step_name)
	if not step.set_percent(ppm):
		return {"ok": false, "reason": "a step is a share of the contract between 0 and 100 per cent"}
	step.trigger = trigger if MilestoneScript.is_trigger(trigger) else MilestoneScript.DATE
	step.due_date = due_date
	step.retainage_ppm = maxi(0, retainage_ppm)
	if not schedule.add_milestone(step):
		return {"ok": false, "reason": "there is already a step called '%s', or it has no name" % step_name}
	return {"ok": true, "reason": ""}


## Add a step priced as a flat amount - a permit fee, a deposit. A step is priced **one of two ways
## and never both**, which is why this is a door of its own rather than a flag.
## Returns `{ok, reason}`.
func add_fixed_milestone(job_id: String, step_name: String, amount: Money,
		trigger: int = MilestoneScript.DATE, due_date: String = "",
		retainage_ppm: int = 0) -> Dictionary:
	var schedule: Billing = billing_for(job_id)
	if schedule == null:
		return {"ok": false, "reason": "this job is not being billed yet"}
	var step: Milestone = MilestoneScript.new(step_name)
	if not step.set_fixed_amount(amount):
		return {"ok": false, "reason": "a flat step is an amount of money and not nothing"}
	step.trigger = trigger if MilestoneScript.is_trigger(trigger) else MilestoneScript.DATE
	step.due_date = due_date
	step.retainage_ppm = maxi(0, retainage_ppm)
	if not schedule.add_milestone(step):
		return {"ok": false, "reason": "there is already a step called '%s', or it has no name" % step_name}
	return {"ok": true, "reason": ""}


## The rate withheld from an invoice on a method that has no steps of its own.
func set_retainage_rate(job_id: String, ppm: int) -> bool:
	var schedule: Billing = billing_for(job_id)
	if schedule == null or ppm < 0 or ppm > RateScript.WHOLE:
		return false
	schedule.retainage_ppm = ppm
	return true


## What materials are marked up by on a time-and-materials job, and what the fee is on a cost-plus one.
func set_markup(job_id: String, ppm: int) -> bool:
	var schedule: Billing = billing_for(job_id)
	if schedule == null or ppm < 0:
		return false
	schedule.markup_ppm = ppm
	return true


func set_fee(job_id: String, ppm: int) -> bool:
	var schedule: Billing = billing_for(job_id)
	if schedule == null or ppm < 0:
		return false
	schedule.fee_ppm = ppm
	return true


func set_percent_complete(job_id: String, ppm: int, basis: int) -> bool:
	var schedule: Billing = billing_for(job_id)
	if schedule == null:
		return false
	return schedule.set_percent_complete(ppm, basis)


## Withhold the retainage the whole job has been holding, at closeout. An explicit act: nothing here
## releases it by itself (§9.2).
func release_retainage(job_id: String, at: String) -> Money:
	var schedule: Billing = billing_for(job_id)
	if schedule == null:
		return MoneyScript.invalid(currency_of(job_id))
	return schedule.release_retainage(at)


## One row per step of the schedule, as a page draws it. Nothing is recomputed: every figure is the
## step's own.
func milestone_rows(job_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var schedule: Billing = billing_for(job_id)
	if schedule == null:
		return out
	var contract: Money = contract_sum_of(job_id)
	for step in schedule.milestones:
		out.append({
			"name": step.name,
			"state": step.state_name(),
			"billed": step.is_billed(),
			"amount": step.amount_for(contract),
			"amount_text": step.amount_for(contract).format_with_currency(),
			"trigger_name": MilestoneScript.trigger_name(step.trigger),
			"retainage": step.retainage_for(contract),
			"invoice_number": step.invoice_number,
			"describe": step.describe(contract),
			"problem": step.problem(),
		})
	return out


## The name of the step a milestone schedule bills next, or "" when there is none or the method is not
## one with steps. This is what a "bill it" button on a row is for.
func billable_step(job_id: String) -> String:
	var schedule: Billing = billing_for(job_id)
	if schedule == null or schedule.method != JobScript.MILESTONE:
		return ""
	var step: Milestone = schedule.next_pending()
	return "" if step == null else step.name


# --- what can be billed now ---------------------------------------------------------------------


## What the job can bill right now, by its own method, as `Billing.amount_due` answers.
## Returns `{ok, reason, amount, milestone}`.
func amount_due(job_id: String, milestone_name: String = "", period_amount: Money = null,
		materials: Money = null) -> Dictionary:
	var schedule: Billing = billing_for(job_id)
	if schedule == null:
		return {
			"ok": false,
			"reason": "this job is not being billed yet",
			"amount": MoneyScript.invalid(currency_of(job_id)),
			"milestone": "",
		}
	return schedule.amount_due(contract_sum_of(job_id), period_amount, materials, milestone_name)


## The amount due in words, with its reason: what a page prints above the button that raises an
## invoice. A reason is always given, including for the zero that means there is nothing left to bill.
func amount_due_text(job_id: String, milestone_name: String = "") -> String:
	var asked: Dictionary = amount_due(job_id, milestone_name)
	var amount: Money = asked["amount"]
	if not bool(asked["ok"]):
		return String(asked["reason"])
	if amount == null or not amount.is_valid():
		return String(asked["reason"])
	return "%s: %s" % [amount.format_with_currency(), String(asked["reason"])]


# --- raising an invoice -------------------------------------------------------------------------


## The numbers already taken in the series, in every fiscal year. A voided invoice keeps its number,
## so it is still taken: this is what makes the year stay gapless (§9.4).
func taken_numbers() -> Array[String]:
	var out: Array[String] = []
	for held in invoices:
		if not held.number.strip_edges().is_empty():
			out.append(held.number)
	return out


## The next number in the series for the fiscal year a moment falls in. **The highest taken plus one,
## never the count**, which `Invoice.next_number` owns.
func next_invoice_number(at: String) -> String:
	return InvoiceScript.next_number(
		InvoiceScript.fiscal_year_of(at, fiscal_start_month), taken_numbers()
	)


## Write an invoice for what the job can bill right now, and issue it. One act, because the model's
## separate draft exists for a page that shows a draft and this page does not.
##
## Refused for a job with no schedule, for a moment that is not a date, and for everything the
## schedule refuses: nothing left to bill, a step that has already gone out, a job with no measurement
## to bill against. A billing that comes to nothing is refused **with the schedule's own reason**,
## because a zero invoice is not a document.
##
## If the schedule will not record the billing the number has already been taken, so the invoice is
## voided in place and the reason returned: a number that vanishes and a document that never existed
## are both worse than a visible void.
## Returns `{ok, reason, invoice}`.
func raise_invoice(job_id: String, at: String, milestone_name: String = "",
		period_start: String = "", period_end: String = "", tax_code: StringName = &"NONE",
		cost_code: StringName = &"", period_amount: Money = null,
		materials: Money = null) -> Dictionary:
	var refused := {"ok": false, "reason": "", "invoice": null}
	var held: Job = job_of(job_id)
	if held == null:
		refused["reason"] = "there is no job %s on the desk" % job_id
		return refused
	var schedule: Billing = billing_for(job_id)
	if schedule == null:
		refused["reason"] = "no schedule has been started for %s, so there is nothing to bill it by" % job_label(job_id)
		return refused
	if not RateScript.is_date(at):
		refused["reason"] = "an invoice goes out on a date, and '%s' is not one" % at
		return refused
	var contract: Money = contract_sum_of(job_id)
	var asked: Dictionary = schedule.amount_due(contract, period_amount, materials, milestone_name)
	if not bool(asked["ok"]):
		refused["reason"] = String(asked["reason"])
		return refused
	var amount: Money = asked["amount"]
	if amount == null or not amount.is_valid():
		refused["reason"] = String(asked["reason"])
		return refused
	if amount.is_zero():
		refused["reason"] = "nothing to bill: %s" % String(asked["reason"])
		return refused
	if amount.is_negative():
		refused["reason"] = "a negative billing is a credit note and not an invoice"
		return refused

	var number := next_invoice_number(at)
	var label := job_label(job_id)
	var invoice: Invoice = InvoiceScript.new(_next_invoice_id())
	invoice.job = _job_reference(held, label)
	invoice.customer = held.customer.duplicate(true)
	invoice.site = _site_of(held, label, invoice.job)
	invoice.currency = contract.currency
	invoice.period_start = period_start
	invoice.period_end = period_end
	var withheld: Money = schedule.retainage_due(contract, amount, String(asked["milestone"]))
	if withheld != null and withheld.is_valid() and withheld.cents > 0:
		invoice.set_retainage(withheld)
	var step: String = String(asked["milestone"])
	if not invoice.add_amount(_kind_for(schedule), _description_for(schedule, step, period_start, period_end),
			amount, cost_code, tax_code):
		refused["reason"] = "the invoice line could not be written"
		return refused
	var issued: Dictionary = invoice.issue(at, terms_days, number)
	if not bool(issued["ok"]):
		refused["reason"] = String(issued["reason"])
		return refused
	invoices.append(invoice)
	var recorded: Dictionary = schedule.record_billed(contract, amount, at, number, step)
	if not bool(recorded["ok"]):
		invoice.mark_void(at, "the billing schedule refused it: %s" % String(recorded["reason"]))
		refused["reason"] = String(recorded["reason"])
		return refused
	return {"ok": true, "reason": "", "invoice": invoice}


## Which document a line is: the shape the invoice's own kinds describe, and each is a different
## document to a bookkeeper even when the money is the same.
static func _kind_for(schedule: Billing) -> int:
	match schedule.method:
		JobScript.MILESTONE: return InvoiceScript.MILESTONE_LINE
		JobScript.PERCENTAGE_COMPLETE: return InvoiceScript.PERCENTAGE_LINE
		JobScript.TIME_AND_MATERIALS: return InvoiceScript.PERIOD_LINE
		JobScript.COST_PLUS: return InvoiceScript.PERIOD_LINE
	return InvoiceScript.FIXED_LINE


## What the line says. A document describes itself: "the contract" and "progress claim at 40% by cost
## incurred" are the two lines a customer reads most often.
static func _description_for(schedule: Billing, step: String, period_start: String,
		period_end: String) -> String:
	if schedule.method == JobScript.MILESTONE:
		if step.strip_edges().is_empty():
			return "a milestone of the schedule"
		return "'%s'" % step
	if schedule.method == JobScript.PERCENTAGE_COMPLETE:
		return "Progress claim at %s %s" % [
			RateScript.percent_text(schedule.complete_ppm), schedule.basis_name(),
		]
	if schedule.method == JobScript.TIME_AND_MATERIALS or schedule.method == JobScript.COST_PLUS:
		if period_start.strip_edges().is_empty() and period_end.strip_edges().is_empty():
			return "work done this period"
		return "work from %s to %s" % [period_start, period_end]
	return "the contract"


## What a job is called on a document: its number, or the name a person knows it by. **Not its id**,
## which is the machine's own label: a customer handed "for job 72db2450-ff39-40a2-b24c-5fa6835bd9d0"
## has been given a database key instead of an address. The id is the last resort, for a job nobody has
## named or numbered at all.
static func _job_reference(record: Job, label: String) -> String:
	if not record.number.strip_edges().is_empty():
		return record.number
	if not label.strip_edges().is_empty():
		return label
	return record.id


## What goes under JOB AND SITE on the page. The name is not said twice: when the document's own
## reference already reads as the job's name, the block carries the address and nothing else.
static func _site_of(record: Job, label: String, job_reference: String) -> Dictionary:
	var where: Dictionary = {}
	if not label.strip_edges().is_empty() and label != job_reference:
		where["name"] = label
	var address: String = String(record.customer.get("address", "")).strip_edges()
	if not address.is_empty():
		where["address"] = address
	return where


func _next_invoice_id() -> String:
	var n: int = invoices.size() + 1
	while _has_invoice_id("invoice-%d" % n):
		n += 1
	return "invoice-%d" % n


func _has_invoice_id(candidate: String) -> bool:
	for held in invoices:
		if held.id == candidate:
			return true
	return false


# --- the documents ------------------------------------------------------------------------------


func invoice_for(invoice_id: String) -> Invoice:
	for held in invoices:
		if held.id == invoice_id:
			return held
	return null


func invoice_by_number(number: String) -> Invoice:
	for held in invoices:
		if not number.strip_edges().is_empty() and held.number == number:
			return held
	return null


func invoices_for(job_id: String) -> Array[Invoice]:
	var out: Array[Invoice] = []
	for held in invoices:
		if held.job.strip_edges().is_empty():
			continue
		if job_id_of_invoice(held) == job_id:
			out.append(held)
	return out


## Which job an invoice belongs to, by whatever the document says it is: its number, its id, or the
## name a person calls it. Three because a document carries whichever the job had when it went out,
## and a job is recognised by any of them - a lookup that knew only one would lose a document.
func job_id_of_invoice(invoice: Invoice) -> String:
	if invoice == null or desk == null:
		return ""
	for held_id in desk.job_ids():
		var held: Job = desk.job(held_id)
		if held == null:
			continue
		if held.id == invoice.job:
			return held_id
		if not held.number.strip_edges().is_empty() and held.number == invoice.job:
			return held_id
		if desk.job_label(held_id) == invoice.job:
			return held_id
	return ""


## One row per invoice on a job, as a list draws it. Every figure is the document's own.
func invoice_rows(job_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for held in invoices_for(job_id):
		out.append({
			"id": held.id,
			"number": held.number,
			"state": held.state(),
			"state_name": held.state_name(),
			"issued_at": held.issued_at,
			"due_at": held.due_at,
			"total": held.total(),
			"applied": held.applied(),
			"balance": held.balance(),
			"retainage": held.retainage,
			"payment_count": held.payment_count(),
			"void": held.is_void(),
			"describe": held.describe(),
		})
	return out


func invoice_texts(job_id: String) -> Array[String]:
	var out: Array[String] = []
	for held in invoice_rows(job_id):
		out.append(String(held["describe"]))
	return out


## What has been invoiced on a job, from the documents: the sum of the subtotals of the invoices that
## went out and were not called back.
##
## The **subtotal**, not the total: what a schedule records as billed is the amount of work, before
## tax, and before the retainage that is withheld from it. Comparing the schedule against anything
## else here would read as a disagreement every time a job charged tax.
func invoiced_total(job_id: String = "") -> Money:
	var amounts: Array = []
	for held in _in_scope(job_id):
		if held.is_issued() and not held.is_void():
			amounts.append(held.subtotal())
	return MoneyScript.sum(amounts, currency_of(job_id))


func collected_total(job_id: String = "") -> Money:
	var amounts: Array = []
	for held in _in_scope(job_id):
		if not held.is_void():
			amounts.append(held.applied())
	return MoneyScript.sum(amounts, currency_of(job_id))


## What is still owed on everything that went out, and nothing for a document that was called back.
func outstanding_total(job_id: String = "") -> Money:
	var amounts: Array = []
	for held in _in_scope(job_id):
		if held.is_issued() and not held.is_void():
			amounts.append(held.balance())
	return MoneyScript.sum(amounts, currency_of(job_id))


## What is being held back as retainage, from the **schedules**: it is the schedule that accumulates it
## per step, and an invoice only ever shows its own deduction.
func retained_total(job_id: String = "") -> Money:
	var amounts: Array = []
	for held_id in _scope_ids(job_id):
		var schedule: Billing = billing_for(held_id)
		if schedule != null and schedule.retainage_held != null and schedule.retainage_held.is_valid():
			amounts.append(schedule.retainage_held)
	return MoneyScript.sum(amounts, currency_of(job_id))


func _in_scope(job_id: String) -> Array[Invoice]:
	if job_id.strip_edges().is_empty():
		return invoices
	return invoices_for(job_id)


func _scope_ids(job_id: String) -> Array[String]:
	if not job_id.strip_edges().is_empty():
		var one: Array[String] = [job_id]
		return one
	return job_ids()


# --- money arriving -----------------------------------------------------------------------------


## Record money the customer sent, against an invoice. The payment is built here and applied through
## the invoice's own door, so a payment larger than the balance is refused rather than clamped (§9.4).
## Returns `{ok, reason, payment}`.
func record_payment(invoice_id: String, at: String, amount: Money, method: StringName = &"cheque",
		bank_reference: String = "", note: String = "") -> Dictionary:
	var invoice: Invoice = invoice_for(invoice_id)
	if invoice == null:
		return {"ok": false, "reason": "there is no invoice %s on the desk" % invoice_id, "payment": null}
	var payment: Payment = PaymentScript.new(_next_payment_id())
	payment.invoice = invoice.id
	payment.received_at = at
	payment.amount = amount
	payment.method = method
	payment.bank_reference = bank_reference
	payment.note = note
	var applied: Dictionary = invoice.apply_payment(payment)
	if not bool(applied["ok"]):
		return {"ok": false, "reason": String(applied["reason"]), "payment": null}
	return {"ok": true, "reason": "", "payment": payment}


## Apply a payment that was read from a file, through the invoice it names.
func apply_payment(payment: Payment) -> Dictionary:
	if payment == null:
		return {"ok": false, "reason": "there is no payment to apply"}
	var invoice: Invoice = invoice_for(payment.invoice)
	if invoice == null:
		return {"ok": false, "reason": "that payment names an invoice this desk does not have"}
	return invoice.apply_payment(payment)


func payment_for(payment_id: String) -> Payment:
	for held in invoices:
		var found: Payment = held.payment_by_id(payment_id)
		if found != null:
			return found
	return null


func payment_rows(invoice_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var invoice: Invoice = invoice_for(invoice_id)
	if invoice == null:
		return out
	for held in invoice.payments:
		out.append({
			"id": held.id,
			"received_at": held.received_at,
			"amount": held.amount,
			"method": String(held.method),
			"method_name": PaymentScript.method_name(held.method),
			"reference": held.bank_reference,
			"describe": held.describe(),
			"problem": held.problem(),
		})
	return out


## One line per payment against an invoice, in the payment's own words.
func payment_texts(invoice_id: String) -> Array[String]:
	var out: Array[String] = []
	var invoice: Invoice = invoice_for(invoice_id)
	if invoice == null:
		return out
	for held in invoice.payments:
		out.append(held.describe())
	return out


func _next_payment_id() -> String:
	var taken: Array[String] = []
	for held in invoices:
		for payment in held.payments:
			taken.append(payment.id)
	return JobDeskScript.next_number(PAYMENT_PREFIX, taken)


# --- calling one back ---------------------------------------------------------------------------


## Void an invoice: keep its number, say when and why, and name what replaces it. A draft is not
## voided - it has no number to keep - and a document that never went out cannot be called back.
##
## **The void takes the billing off the schedule with it**, so a step that was billed can be billed
## again. Refused, and nothing changed, when un-billing would take the schedule below what it has
## already recorded: that would mean the schedule and the invoices had already disagreed.
## Returns `{ok, reason}`.
func void_invoice(invoice_id: String, at: String, why: String = "",
		replacement: String = "") -> Dictionary:
	var invoice: Invoice = invoice_for(invoice_id)
	if invoice == null:
		return {"ok": false, "reason": "there is no invoice %s on the desk" % invoice_id}
	if invoice.is_void():
		return {"ok": false, "reason": "%s was already called back" % _number_label(invoice)}
	if not invoice.is_issued():
		return {"ok": false, "reason": "a draft is not voided: it has no number to keep"}
	var job_id := job_id_of_invoice(invoice)
	var schedule: Billing = billing_for(job_id)
	if schedule != null and schedule.billed_to_date != null and schedule.billed_to_date.is_valid():
		var left: Money = schedule.billed_to_date.sub(invoice.subtotal())
		if not left.is_valid() or left.is_negative():
			return {
				"ok": false,
				"reason": "%s cannot be called back: the schedule has recorded less billed than it comes to" % _number_label(invoice),
			}
	if not invoice.mark_void(at, why, replacement):
		return {"ok": false, "reason": "a void says when and why, and '%s' is not a date" % at}
	_unwind_billed(job_id, invoice)
	return {"ok": true, "reason": ""}


## Take a document's billing back off the schedule. `Billing.record_billed` is the only place
## `billed_to_date` goes up; this is the mirror, and it is here rather than in `Billing` because it is
## a consequence of a decision about a document, which is what this desk is for.
func _unwind_billed(job_id: String, invoice: Invoice) -> void:
	var schedule: Billing = billing_for(job_id)
	if schedule == null:
		return
	var contract: Money = contract_sum_of(job_id)
	for step in schedule.milestones:
		if not step.is_billed() or step.invoice_number != invoice.number:
			continue
		step.billed_at = ""
		step.invoice_number = ""
		if schedule.retainage_held != null and schedule.retainage_held.is_valid():
			var held: Money = schedule.retainage_held.sub(step.retainage_for(contract))
			if held.is_valid() and not held.is_negative():
				schedule.retainage_held = held
		break
	if schedule.billed_to_date != null and schedule.billed_to_date.is_valid():
		schedule.billed_to_date = schedule.billed_to_date.sub(invoice.subtotal())


# --- the page -----------------------------------------------------------------------------------


## The invoice page, as bytes. `InvoiceSheet` draws it and this desk only says where it goes.
func invoice_pdf(invoice_id: String, options: Dictionary = {}) -> PackedByteArray:
	var invoice: Invoice = invoice_for(invoice_id)
	if invoice == null:
		return PackedByteArray()
	return SheetScript.export_pdf(invoice, _page_options(options))


## Write the page where the drawings and the proposals already go, and say where.
## Returns `{ok, path, reason}`.
func write_invoice(invoice_id: String, options: Dictionary = {}) -> Dictionary:
	var invoice: Invoice = invoice_for(invoice_id)
	if invoice == null:
		return {"ok": false, "path": "", "reason": "there is no invoice %s on the desk" % invoice_id}
	var bytes: PackedByteArray = SheetScript.export_pdf(invoice, _page_options(options))
	if bytes.is_empty():
		return {"ok": false, "path": "", "reason": "the page came out empty"}
	DirAccess.make_dir_recursive_absolute(INVOICE_FOLDER)
	var path := "%s/%s.pdf" % [INVOICE_FOLDER, _safe_name(_number_label(invoice))]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "path": "", "reason": "the file could not be opened: %s" % str(FileAccess.get_open_error())}
	file.store_buffer(bytes)
	file.close()
	return {"ok": true, "path": path, "reason": ""}


## The letterhead the desk holds, unless a caller brought its own.
func _page_options(options: Dictionary) -> Dictionary:
	var asked: Dictionary = options.duplicate(true)
	if not asked.has("sheet"):
		asked["sheet"] = sheet
	if not asked.has("company"):
		asked["company"] = company.duplicate()
	if not asked.has("contact"):
		asked["contact"] = contact.duplicate()
	return asked


static func _safe_name(text: String) -> String:
	var out := text.strip_edges()
	for bad in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		out = out.replace(bad, "-")
	return out if not out.is_empty() else "invoice"


# --- what it says -------------------------------------------------------------------------------


func summary_text(job_id: String) -> String:
	if job_of(job_id) == null:
		return "no job chosen"
	var schedule: Billing = billing_for(job_id)
	if schedule == null:
		return "%s is not being billed yet." % job_label(job_id)
	return "%s: %s of %s, %s" % [
		job_label(job_id),
		schedule.describe(),
		contract_sum_of(job_id).format_with_currency(),
		schedule.method_name(),
	]


## Everything the schedules and the documents disagree about, or are wrong about, in words. This is
## the one place the two records are compared, and it is a comparison rather than a computation: both
## figures are the models' own.
func problems(job_id: String = "") -> Array[String]:
	var out: Array[String] = []
	for held_id in _scope_ids(job_id):
		var label := job_label(held_id)
		var documents: Array = []
		for invoice in invoices_for(held_id):
			if invoice.is_void():
				continue
			if not invoice.is_sound():
				for words in invoice.problems():
					out.append("%s: %s" % [_number_label(invoice), words])
			if invoice.is_issued():
				documents.append(invoice.subtotal())
		var schedule: Billing = billing_for(held_id)
		if schedule == null:
			if not documents.is_empty():
				out.append("%s has invoices but no billing schedule" % label)
			continue
		for words in schedule.problems():
			out.append("%s: %s" % [label, words])
		var billed: Money = MoneyScript.sum(documents, currency_of(held_id))
		var recorded: Money = schedule.billed_to_date
		if billed.is_valid() and recorded != null and recorded.is_valid() and not billed.equals(recorded):
			out.append("the schedule of %s says %s has been billed and its invoices come to %s" % [
				label, recorded.format_with_currency(), billed.format_with_currency(),
			])
	for invoice in invoices:
		if invoice.job.strip_edges().is_empty():
			continue
		if job_id_of_invoice(invoice).is_empty():
			out.append("%s names a job this desk does not have: %s" % [_number_label(invoice), invoice.job])
	for key in billings.keys():
		if job_of(String(key)) == null:
			out.append("a billing schedule for a job this desk does not have: %s" % String(key))
	return out


func is_sound() -> bool:
	return problems().is_empty()


## One line for the menu: what has been billed and what is still owed. A desk that has neither says
## so rather than reading as a row of zeroes.
func describe() -> String:
	if billings.is_empty() and invoices.is_empty():
		return "nothing has been billed yet"
	var line := "%d schedule%s, %d invoice%s" % [
		billings.size(), _plural(billings.size()),
		invoices.size(), _plural(invoices.size()),
	]
	var billed: Money = invoiced_total()
	var owed: Money = outstanding_total()
	line += " (%s billed" % billed.format_with_currency()
	if owed.is_valid() and not owed.is_zero():
		line += ", %s outstanding" % owed.format_with_currency()
	line += ")"
	var held: Money = retained_total()
	if held.is_valid() and not held.is_zero():
		line += ", %s retained" % held.format_with_currency()
	var counted := issues()
	if counted > 0:
		line += ", %d thing%s to look at" % [counted, _plural(counted)]
	return line


func issues() -> int:
	return problems().size()


static func _plural(how_many: int) -> String:
	return "" if how_many == 1 else "s"


static func _number_label(invoice: Invoice) -> String:
	if invoice == null:
		return "an invoice"
	if not invoice.number.strip_edges().is_empty():
		return invoice.number
	return invoice.id


# --- the file -----------------------------------------------------------------------------------


func to_dict() -> Dictionary:
	var schedules: Dictionary = {}
	for key in billings.keys():
		var held: Billing = billing_for(String(key))
		if held != null:
			schedules[String(key)] = held.to_dict()
	var papers: Array = []
	for held in invoices:
		papers.append(held.to_dict())
	return {
		"terms_days": terms_days,
		"fiscal_start_month": fiscal_start_month,
		"sheet": sheet,
		"company": company.duplicate(),
		"contact": contact.duplicate(),
		"billings": schedules,
		"invoices": papers,
	}


## A schedule or an invoice that is not a dictionary is dropped and the rest of the ledger reads. An
## invoice whose job is not on the desk at all is **kept**: the desk can say which job it names, and
## dropping it would silently lose a numbered document.
##
## The jobs are handed in rather than read from the file. An invoice is a document drawn out of a
## contract, and a ledger read without the jobs still reads back whole - every document then says
## which job it cannot find - but nothing on it can be billed or reported against.
static func from_dict(data: Dictionary, job_desk: JobDesk = null) -> BillingDesk:
	var ledger: BillingDesk = LedgerScript.new()
	if job_desk != null:
		ledger.bind(job_desk)
	ledger.terms_days = int(data.get("terms_days", DEFAULT_TERMS_DAYS))
	ledger.fiscal_start_month = int(data.get("fiscal_start_month", 1))
	ledger.sheet = String(data.get("sheet", DEFAULT_SHEET))
	for entry in _texts(data.get("company", [])):
		ledger.company.append(entry)
	for entry in _texts(data.get("contact", [])):
		ledger.contact.append(entry)
	var schedules = data.get("billings", {})
	if schedules is Dictionary:
		for key in (schedules as Dictionary).keys():
			var read = (schedules as Dictionary)[key]
			if read is Dictionary:
				ledger.billings[String(key)] = BillingScript.from_dict(read)
	var papers = data.get("invoices", [])
	if papers is Array:
		for entry in (papers as Array):
			if entry is Dictionary:
				var paper: Invoice = InvoiceScript.from_dict(entry)
				if paper != null and ledger.invoice_for(paper.id) == null:
					ledger.invoices.append(paper)
	return ledger


static func _texts(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for entry in (value as Array):
			var text: String = String(entry).strip_edges()
			if not text.is_empty():
				out.append(text)
	elif value is String and not (value as String).strip_edges().is_empty():
		out.append((value as String).strip_edges())
	return out


const LedgerScript := preload("res://scripts/biz/billing_desk.gd")