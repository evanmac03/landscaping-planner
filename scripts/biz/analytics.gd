class_name Analytics
extends RefCounted
## The figures in §10, worked out from the records and the events, each naming its **basis** and its
## **window** (REQ-B15, REQ-B16, REQ-B20, AC-B17, AC-B18).
##
## Three rules this file exists to keep:
##
## * **Nothing is accumulated.** Every figure is a function of the records handed to `bind`, the window
##   and the as-of moment, so a report for last March is the same report next year (REQ-B15). There is no
##   running total and no cache anywhere here.
## * **A figure that cannot be worked out is refused, naming what is missing** (REQ-B16). It is never
##   zero: `pipeline_value` needs an as-of date, `crew_utilisation` needs a stated working day, `backlog`
##   needs something recorded as billed against every job. Each one says which.
## * **Every figure carries its basis in words.** "62.5% won" with no statement of whether withdrawn
##   leads were counted is a number two people can disagree about while both being right, so the basis
##   travels with the figure rather than living in a document nobody opens.
##
## Three decisions the build made that the specification's table did not settle, each recorded where it
## is applied:
##
## * **A figure about invoices is read off the invoices.** `_billed_for` reads the billing ledger when
##   there is one and only falls back to the job desk's own `invoiced` dictionary when there is not,
##   because a document and somebody's memory are not the same kind of evidence.
## * **Billable hours are approved hours.** Nothing in the records marks an hour as billable, so
##   `crew_utilisation` says out loud that it takes an approved timesheet as the definition, and refuses
##   outright until a working day is stated.
## * **An unpaid invoice that is not yet due sits in the 0-30 bucket**, which is where a bookkeeper reads
##   it, rather than in a bucket of its own that no ageing report has.

const MoneyScript := preload("res://scripts/biz/money.gd")
const JobCostScript := preload("res://scripts/biz/job_cost.gd")
const LeadScript := preload("res://scripts/biz/lead.gd")

const PPM := 1000000
const SECONDS_PER_DAY := 86400
const MINUTES_PER_HOUR := 60
## A window longer than this is refused rather than iterated: a report is a period, and a "window" of
## four years is somebody mistyping a year.
const MAX_WINDOW_DAYS := 400

## The ageing buckets, in the order a report reads them (§10).
const BUCKETS: Array[String] = ["0-30", "31-60", "61-90", "90+"]
## The last day of each bucket but the last. A day late is bucketed by `_bucket_of`.
const BUCKET_LAST_DAY: Array[int] = [30, 60, 90]

## The figures, in the order §10 lists them. `average sale, average cycle` is one row there and two
## figures here, because they are two numbers with two windows of their own.
const KEYS: Array[String] = [
	"funnel", "win_rate", "lost_reasons", "average_sale", "average_cycle", "source_performance",
	"pipeline_value", "slipped", "job_profitability", "cost_tracking", "backlog", "wip", "ar_aging",
	"crew_utilisation",
]

const LABELS := {
	"funnel": "Funnel by stage",
	"win_rate": "Win rate",
	"lost_reasons": "Lost reasons",
	"average_sale": "Average sale",
	"average_cycle": "Average cycle",
	"source_performance": "Source performance",
	"pipeline_value": "Pipeline value",
	"slipped": "Slipped",
	"job_profitability": "Job profitability",
	"cost_tracking": "Cost tracking",
	"backlog": "Backlog",
	"wip": "Work in progress",
	"ar_aging": "A/R ageing",
	"crew_utilisation": "Crew utilisation",
}

## What each figure is a function of. Every one of these is printed with the figure.
const BASES := {
	"funnel": "counted by the event that moved a lead into each stage",
	"win_rate": "won over won plus lost, by decision date, withdrawn counted apart",
	"lost_reasons": "by decision date, by reason code",
	"average_sale": "the value recorded on the lead, by decision date",
	"average_cycle": "the lead's own stage events, by decision date",
	"source_performance": "the lead's own source, by decision date",
	"pipeline_value": "the open leads and the table of odds, raw beside weighted",
	"slipped": "open leads past their expected close, most late first",
	"job_profitability": "accrual, per job: agreed sum, cost incurred and the margin between them",
	"cost_tracking": "budget, committed and actual, per cost code",
	"backlog": "approved contract value not yet billed",
	"wip": "cost incurred against billed to date, per job",
	"ar_aging": "unpaid invoices by due date; one not yet due is in the first bucket",
	"crew_utilisation": "hours on an approved timesheet over the days a person is available",
}


## One figure: what it is, whether it could be worked out, and on what.
class Figure extends RefCounted:
	var key: String = ""
	var label: String = ""
	var ok: bool = false
	var value: Variant = null
	var words: String = ""
	var basis: String = ""
	var window: String = ""
	var missing: String = ""

	## The line a report prints: the figure, its basis and its window, or what it is missing.
	func text() -> String:
		if ok:
			return "%s: %s. %s, %s." % [label, words, basis, window]
		return "%s unavailable: %s" % [label, missing]

	## The same line cut back to the figure, for a list of what is missing.
	func short_text() -> String:
		if ok:
			return "%s: %s" % [label, words]
		return "%s unavailable: %s" % [label, missing]


# --- what it reads ------------------------------------------------------------------------------

var pipeline: Pipeline = null
var jobs: JobDesk = null
var billing: BillingDesk = null
## The hours in a working day, in minutes. **Zero until somebody states one**, which is what makes
## `crew_utilisation` refuse rather than divide by a day length this file invented.
var working_day_minutes: int = 0


func _init(pipeline_desk: Pipeline = null, job_records: JobDesk = null,
		billing_ledger: BillingDesk = null) -> void:
	pipeline = pipeline_desk
	jobs = job_records
	billing = billing_ledger


func bind(pipeline_desk: Pipeline = null, job_records: JobDesk = null,
		billing_ledger: BillingDesk = null) -> void:
	pipeline = pipeline_desk
	jobs = job_records
	billing = billing_ledger


## State the working day. Refused for nothing or a negative, because a day of no hours would make
## every utilisation figure a division by zero and a day of minus hours is not a day.
func set_working_day(minutes: int) -> bool:
	if minutes <= 0:
		return false
	working_day_minutes = minutes
	return true


func working_day_stated() -> bool:
	return working_day_minutes > 0


func working_day_text() -> String:
	if working_day_minutes <= 0:
		return "no working day is stated"
	var hours := floori(float(working_day_minutes) / float(MINUTES_PER_HOUR))
	var rest := working_day_minutes - hours * MINUTES_PER_HOUR
	return "%d hours %d minutes" % [hours, rest]


# --- the figures --------------------------------------------------------------------------------


func keys() -> Array[String]:
	return KEYS.duplicate()


func label_for(key: String) -> String:
	return String(LABELS.get(key, key))


func basis_for(key: String) -> String:
	return String(BASES.get(key, ""))


## Every figure for a window, in the order §10 lists them. `now` is the as-of moment the "now" figures
## are worked out at, and one that is not stated makes exactly those five refuse.
func figures(from: String = "", to: String = "", now: String = "") -> Array[Figure]:
	var out: Array[Figure] = []
	for held in KEYS:
		out.append(figure(held, from, to, now))
	return out


## One figure, by name. A name nothing here computes is refused as such rather than answered with
## something else, because a report that quietly shows the wrong figure is worse than an empty one.
func figure(key: String, from: String = "", to: String = "", now: String = "") -> Figure:
	match key:
		"funnel":
			return _funnel(from, to)
		"win_rate":
			return _win_rate(from, to)
		"lost_reasons":
			return _lost_reasons(from, to)
		"average_sale":
			return _average_sale(from, to)
		"average_cycle":
			return _average_cycle(from, to)
		"source_performance":
			return _source_performance(from, to)
		"pipeline_value":
			return _pipeline_value(now)
		"slipped":
			return _slipped(now)
		"job_profitability":
			return _job_profitability(now)
		"cost_tracking":
			return _cost_tracking(now)
		"backlog":
			return _backlog(now)
		"wip":
			return _wip(now)
		"ar_aging":
			return _ar_aging(now)
		"crew_utilisation":
			return _crew_utilisation(from, to)
	return _blank(key, "there is no figure called '%s' here" % key)


## What could not be worked out, each naming its own missing input. Empty is the good answer.
func unavailable(from: String = "", to: String = "", now: String = "") -> Array[String]:
	var out: Array[String] = []
	for held in figures(from, to, now):
		if not held.ok:
			out.append(held.short_text())
	return out


func summary_text(from: String = "", to: String = "", now: String = "") -> String:
	var made: Array[Figure] = figures(from, to, now)
	var lacking := 0
	for held in made:
		if not held.ok:
			lacking += 1
	var words := "%d figures for %s" % [made.size(), window_text(from, to)]
	if lacking == 0:
		return "%s, all of them available" % words
	return "%s, %d unavailable" % [words, lacking]


func describe() -> String:
	var parts := PackedStringArray()
	if pipeline != null:
		parts.append("the pipeline")
	if jobs != null:
		parts.append("the job desk")
	if billing != null:
		parts.append("the billing ledger")
	if parts.is_empty():
		return "analytics with nothing to read"
	return "analytics over %s" % ", ".join(parts)


## The window in words. Both ends are inclusive, and an end nobody stated is not a bound.
static func window_text(from: String, to: String) -> String:
	var start := from.strip_edges()
	var finish := to.strip_edges()
	if start.is_empty() and finish.is_empty():
		return "every date"
	if start.is_empty():
		return "everything up to %s" % finish
	if finish.is_empty():
		return "everything from %s" % start
	return "%s to %s" % [start, finish]


# --- the pipeline figures -----------------------------------------------------------------------


func _funnel(from: String, to: String) -> Figure:
	if pipeline == null:
		return _blank("funnel", "no pipeline is loaded, so there are no stage events to count")
	var rows: Array[Dictionary] = pipeline.funnel(from, to)
	var parts := PackedStringArray()
	var entered := 0
	for held in rows:
		var count := int(held["count"])
		entered += count
		parts.append("%d %s" % [count, String(held["name"]).to_lower()])
	var words := "nothing entered the funnel in this window"
	if entered > 0:
		words = ", ".join(parts)
	return _found("funnel", rows, words, window_text(from, to))


func _win_rate(from: String, to: String) -> Figure:
	if pipeline == null:
		return _blank("win_rate", "no pipeline is loaded, so there are no decision dates to read")
	var rate: Dictionary = pipeline.win_rate(from, to)
	if not bool(rate["ok"]):
		return _blank("win_rate", String(rate["reason"]))
	var words := "%s (%d won, %d lost, %d withdrawn, %d closed)" % [
		_percent_text(int(rate["ppm"])), int(rate["won"]), int(rate["lost"]),
		int(rate["withdrawn"]), int(rate["closed"]),
	]
	return _found("win_rate", rate, words, window_text(from, to))


func _lost_reasons(from: String, to: String) -> Figure:
	if pipeline == null:
		return _blank("lost_reasons", "no pipeline is loaded, so there are no loss reasons to count")
	var rows: Array[Dictionary] = pipeline.lost_reasons(from, to)
	var parts := PackedStringArray()
	var lost := 0
	for held in rows:
		var count := int(held["count"])
		lost += count
		parts.append("%d %s (%s)" % [
			count, String(held["name"]),
			_money_text(int(held["value_cents"]), StringName(held["currency"])),
		])
	var words := "nothing was lost in this window"
	if lost > 0:
		words = ", ".join(parts)
	return _found("lost_reasons", rows, words, window_text(from, to))


func _average_sale(from: String, to: String) -> Figure:
	if pipeline == null:
		return _blank("average_sale", "no pipeline is loaded, so there is no decision date to read")
	var won := _won_in(from, to)
	if won.is_empty():
		return _blank("average_sale", "no lead was won in this window")
	var cents := 0
	var valued := 0
	for held in won:
		var amount: Money = held.value()
		cents += amount.cents
		if amount.cents != 0:
			valued += 1
	var unvalued := won.size() - valued
	var words := "%s over %d won lead(s)" % [
		_money_text(MoneyScript.rounded_div(cents, won.size()), pipeline.currency), won.size(),
	]
	if unvalued > 0:
		words += ", of which %d had no estimate and count as nothing" % unvalued
	return _found("average_sale", {
		"cents": cents,
		"mean_cents": MoneyScript.rounded_div(cents, won.size()),
		"won": won.size(),
		"valued": valued,
		"unvalued": unvalued,
		"currency": String(pipeline.currency),
	}, words, window_text(from, to))


func _average_cycle(from: String, to: String) -> Figure:
	if pipeline == null:
		return _blank("average_cycle", "no pipeline is loaded, so there are no dates to measure")
	var won := _won_in(from, to)
	if won.is_empty():
		return _blank("average_cycle", "no lead was won in this window")
	var open_seconds := 0
	var open_count := 0
	var proposed_seconds := 0
	var proposed_count := 0
	for held in won:
		var opened := _unix(held.opened_at)
		var closed := _unix(held.closed_at)
		if opened > 0 and closed >= opened:
			open_seconds += closed - opened
			open_count += 1
		var proposed := held.event_into(LeadScript.PROPOSED)
		if proposed.is_empty():
			continue
		var raised := _unix(String(proposed.get("at", "")))
		if raised > 0 and closed >= raised:
			proposed_seconds += closed - raised
			proposed_count += 1
	var words := "no won lead has both dates readable"
	if open_count > 0:
		words = "lead to close %d day(s) over %d of %d won leads" % [
			_mean_days(open_seconds, open_count), open_count, won.size(),
		]
	if proposed_count > 0:
		words += "; estimate to decision %d day(s) over %d" % [
			_mean_days(proposed_seconds, proposed_count), proposed_count,
		]
	else:
		words += "; no won lead recorded a proposal date, so estimate to decision is unknown"
	return _found("average_cycle", {
		"won": won.size(),
		"open_to_close_days": _mean_days(open_seconds, open_count),
		"open_count": open_count,
		"proposed_to_close_days": _mean_days(proposed_seconds, proposed_count),
		"proposed_count": proposed_count,
	}, words, window_text(from, to))


func _source_performance(from: String, to: String) -> Figure:
	if pipeline == null:
		return _blank("source_performance", "no pipeline is loaded, so there are no sources to compare")
	var rows: Array[Dictionary] = pipeline.source_performance(from, to)
	var parts := PackedStringArray()
	var decided := 0
	for held in rows:
		var closed := int(held["closed"])
		decided += closed
		if closed == 0:
			parts.append("%s: nothing decided" % String(held["name"]))
			continue
		parts.append("%s: %s of %d, average %s" % [
			String(held["name"]), _percent_text(int(held["ppm"])), closed,
			_money_text(int(held["average_cents"]), StringName(held["currency"])),
		])
	var words := "nothing was decided in this window"
	if decided > 0:
		words = ", ".join(parts)
	return _found("source_performance", rows, words, window_text(from, to))


# --- the "now" figures --------------------------------------------------------------------------


func _pipeline_value(now: String) -> Figure:
	if pipeline == null:
		return _blank("pipeline_value", "no pipeline is loaded, so there is nothing open to value")
	var moment := _moment(now)
	if moment.is_empty():
		return _blank("pipeline_value", "an as-of date is needed, because what is open is open now")
	var held: Dictionary = pipeline.pipeline_value()
	var words := "%s raw and %s weighted by the table of odds, over %d open lead(s)" % [
		_money_text(int(held["raw_cents"]), StringName(held["currency"])),
		_money_text(int(held["weighted_cents"]), StringName(held["currency"])),
		int(held["count"]),
	]
	var missing: Array = held["stages_missing_odds"]
	if not missing.is_empty():
		words += "; %d stage(s) have no stated odds and were left out of the weighted figure" % (
			missing.size()
		)
	return _found("pipeline_value", held, words, "as at %s" % moment)


func _slipped(now: String) -> Figure:
	if pipeline == null:
		return _blank("slipped", "no pipeline is loaded, so there is nothing open to check")
	var moment := _moment(now)
	if moment.is_empty():
		return _blank("slipped", "an as-of date is needed to say what is late")
	var rows: Array[Dictionary] = pipeline.slipped(moment)
	var words := "nothing open is past its expected close"
	if not rows.is_empty():
		words = "%d open lead(s) past their expected close, worst %d day(s) late" % [
			rows.size(), int(rows[0]["days_late"]),
		]
	return _found("slipped", rows, words, "as at %s" % moment)


func _job_profitability(now: String) -> Figure:
	var moment := _moment(now)
	if jobs == null:
		return _blank("job_profitability", "no job desk is loaded, so there are no jobs to report on")
	if moment.is_empty():
		return _blank("job_profitability", "an as-of date is needed, because a job's cost is as now")
	if jobs.jobs.is_empty():
		return _found("job_profitability", [], "no jobs are on the desk", "as at %s" % moment)
	var rows: Array[Dictionary] = []
	var agreed: Array = []
	var costs: Array = []
	var margins: Array = []
	var unknown_margin := 0
	for held in jobs.jobs:
		var report: JobCost = _report_for(held)
		var totals: Dictionary = report.totals()
		var job_agreed: Money = totals["agreed_sum"]
		var job_cost: Money = totals["cost"]
		var job_billed: Money = totals["billed"]
		var job_margin: Money = totals["margin_to_date"]
		var known: bool = bool(totals["margin_known"])
		agreed.append(job_agreed)
		costs.append(job_cost)
		if known:
			margins.append(job_margin)
		else:
			unknown_margin += 1
		rows.append({
			"job_id": held.id,
			"job": jobs.job_label(held.id),
			"agreed": job_agreed,
			"billed": job_billed,
			"billed_known": bool(totals["billed_known"]),
			"cost": job_cost,
			"margin": job_margin,
			"margin_known": known,
			"percent_ppm": int(totals["percent_ppm"]),
			"percent_known": bool(totals["percent_known"]),
		})
	var currency: StringName = jobs.currency
	var words := "%d job(s): agreed %s, cost %s, margin to date %s" % [
		rows.size(),
		MoneyScript.sum(agreed, currency).format_with_currency(),
		MoneyScript.sum(costs, currency).format_with_currency(),
		MoneyScript.sum(margins, currency).format_with_currency(),
	]
	if unknown_margin > 0:
		words += "; %d job(s) have no margin, having no budget or nothing measured" % unknown_margin
	return _found("job_profitability", rows, words, "as at %s" % moment)


func _cost_tracking(now: String) -> Figure:
	var moment := _moment(now)
	if jobs == null:
		return _blank("cost_tracking", "no job desk is loaded, so there are no cost codes to report on")
	if moment.is_empty():
		return _blank("cost_tracking", "an as-of date is needed, because committed and actual are as now")
	if jobs.jobs.is_empty():
		return _found("cost_tracking", [], "no jobs are on the desk", "as at %s" % moment)
	var rows: Array[Dictionary] = []
	var codes := 0
	var over := 0
	for held in jobs.jobs:
		var report: JobCost = _report_for(held)
		for line in report.rows:
			codes += 1
			var overspent: bool = bool(line["over_committed"])
			if overspent:
				over += 1
			rows.append({
				"job_id": held.id,
				"job": jobs.job_label(held.id),
				"cost_code": String(line["cost_code"]),
				"basis": String(line["basis_name"]),
				"budget": line["budget"],
				"revised_budget": line["revised_budget"],
				"committed": line["committed"],
				"actual": line["actual"],
				"projection": line["projection"],
				"over_committed": overspent,
			})
	var words := "%d job(s), %d cost code(s)" % [jobs.jobs.size(), codes]
	if over > 0:
		words += ", %d of them committed past budget" % over
	return _found("cost_tracking", rows, words, "as at %s" % moment)


func _backlog(now: String) -> Figure:
	var moment := _moment(now)
	if jobs == null:
		return _blank("backlog", "no job desk is loaded, so there are no contracts to read")
	if moment.is_empty():
		return _blank("backlog", "an as-of date is needed, because what is left is left now")
	if jobs.jobs.is_empty():
		return _found("backlog", {"cents": 0, "jobs": []}, "no jobs are on the desk", "as at %s" % moment)
	var unstated := PackedStringArray()
	var rows: Array[Dictionary] = []
	var cents := 0
	for held in jobs.jobs:
		var totals: Dictionary = _report_for(held).totals()
		if not bool(totals["billed_known"]):
			unstated.append(jobs.job_label(held.id))
			continue
		var left: Money = (totals["agreed_sum"] as Money).sub(totals["billed"] as Money)
		cents += left.cents
		rows.append({
			"job_id": held.id,
			"job": jobs.job_label(held.id),
			"agreed": totals["agreed_sum"],
			"billed": totals["billed"],
			"left": left,
		})
	if not unstated.is_empty():
		return _blank("backlog", "nothing is recorded as billed against %s, so what is left of those contracts cannot be worked out" % ", ".join(unstated))
	var words := "%s of approved work not yet billed over %d job(s)" % [
		_money_text(cents, jobs.currency), rows.size(),
	]
	words += _billed_from_the_desk()
	var behind := PackedStringArray()
	for held in rows:
		var left: Money = held["left"]
		if left.cents < 0:
			behind.append(String(held["job"]))
	if not behind.is_empty():
		words += "; %s has been billed past what was agreed" % ", ".join(behind)
	return _found("backlog", {"cents": cents, "jobs": rows}, words, "as at %s" % moment)


func _wip(now: String) -> Figure:
	var moment := _moment(now)
	if jobs == null:
		return _blank("wip", "no job desk is loaded, so there is no cost to set against billing")
	if moment.is_empty():
		return _blank("wip", "an as-of date is needed, because cost incurred is cost incurred now")
	var unstated := PackedStringArray()
	var rows: Array[Dictionary] = []
	var ahead := 0
	for held in jobs.jobs:
		var totals: Dictionary = _report_for(held).totals()
		if not bool(totals["billed_known"]):
			unstated.append(jobs.job_label(held.id))
			continue
		var cost: Money = totals["cost"]
		var billed: Money = totals["billed"]
		var over_under := cost.sub(billed)
		ahead += over_under.cents
		rows.append({
			"job_id": held.id,
			"job": jobs.job_label(held.id),
			"cost": cost,
			"billed": billed,
			"worked_ahead": over_under,
		})
	if not unstated.is_empty():
		return _blank("wip", "nothing is recorded as billed against %s, so cost against billing cannot be worked out" % ", ".join(unstated))
	var words := "no jobs are on the desk"
	if not rows.is_empty():
		words = "%s worked ahead of billing over %d job(s)" % [
			_money_text(ahead, jobs.currency), rows.size(),
		]
		words += _billed_from_the_desk()
	return _found("wip", {"cents": ahead, "jobs": rows}, words, "as at %s" % moment)


func _ar_aging(now: String) -> Figure:
	var moment := _moment(now)
	if billing == null:
		return _blank("ar_aging", "no billing ledger is loaded, so there are no invoices to age")
	if moment.is_empty():
		return _blank("ar_aging", "an as-of date is needed, because an age is an age today")
	var start := _unix(moment)
	if start <= 0:
		return _blank("ar_aging", "the as-of date cannot be read")
	var currency: StringName = billing.currency_of("")
	var counts: Array = [0, 0, 0, 0]
	var cents: Array = [0, 0, 0, 0]
	var total := 0
	for held in billing.invoices:
		if not held.is_issued() or held.is_void():
			continue
		var balance: Money = held.balance()
		if not balance.is_valid() or balance.cents <= 0:
			continue
		var late := 0
		var due := _unix(held.due_at)
		if due > 0 and due < start:
			late = floori(float(start - due) / float(SECONDS_PER_DAY))
		var at := _bucket_of(late)
		counts[at] = int(counts[at]) + 1
		cents[at] = int(cents[at]) + balance.cents
		total += balance.cents
	var rows: Array[Dictionary] = []
	var unpaid := 0
	for index in range(BUCKETS.size()):
		unpaid += int(counts[index])
		rows.append({
			"bucket": BUCKETS[index],
			"count": int(counts[index]),
			"cents": int(cents[index]),
		})
	var words := "nothing is unpaid"
	if unpaid > 0:
		var parts := PackedStringArray()
		for held in rows:
			if int(held["count"]) == 0:
				continue
			parts.append("%s: %s over %d invoice(s)" % [
				String(held["bucket"]), _money_text(int(held["cents"]), currency),
				int(held["count"]),
			])
		words = "%d invoice(s) unpaid, %s (%s)" % [
			unpaid, _money_text(total, currency), ", ".join(parts),
		]
	return _found("ar_aging", {
		"buckets": rows,
		"count": unpaid,
		"cents": total,
		"currency": String(currency),
	}, words, "as at %s" % moment)


func _crew_utilisation(from: String, to: String) -> Figure:
	if jobs == null:
		return _blank("crew_utilisation", "no job desk is loaded, so there are no crews or timesheets")
	if not working_day_stated():
		return _blank("crew_utilisation", "no working day is stated, so the hours anybody was available cannot be counted")
	var start := _unix(from)
	var finish := _unix(to)
	if start <= 0 or finish <= 0 or finish < start:
		return _blank("crew_utilisation", "crew utilisation needs a window with both ends readable")
	var span := _days_between(start, finish)
	if span > MAX_WINDOW_DAYS:
		return _blank("crew_utilisation", "a window longer than %d days is not worked out" % MAX_WINDOW_DAYS)
	if jobs.crews.is_empty():
		return _found("crew_utilisation", [], "no crew members are on the desk", window_text(from, to))
	var rows: Array[Dictionary] = []
	var worked := 0
	var available := 0
	for held in jobs.crews:
		var days := 0
		for index in range(span):
			if held.available_on(_date_at(start, index)):
				days += 1
		var theirs := days * working_day_minutes
		available += theirs
		var minutes := 0
		for entry in jobs.time_entries:
			if entry.crew_member != held.id or not entry.is_approved() or not entry.is_valid():
				continue
			if not _in_window(_day_of(entry.started_at), from, to):
				continue
			minutes += entry.minutes()
		worked += minutes
		rows.append({
			"crew": String(held.id),
			"name": held.name,
			"approved_minutes": minutes,
			"available_minutes": theirs,
			"ppm": MoneyScript.rounded_div(minutes * PPM, theirs) if theirs > 0 else 0,
		})
	var words := "%s of %s available on approved timesheets" % [
		_hours_text(worked), _hours_text(available),
	]
	if available > 0:
		words = "%s, %s worked" % [_percent_text(MoneyScript.rounded_div(worked * PPM, available)), words]
	return _found("crew_utilisation", {
		"approved_minutes": worked,
		"available_minutes": available,
		"working_day_minutes": working_day_minutes,
		"rows": rows,
	}, words, window_text(from, to))


# --- the records underneath ---------------------------------------------------------------------


## What has been billed against a job, **from the documents**. The billing ledger's invoices are what
## went out and were not called back, so they answer; the job desk's `invoiced` dictionary is somebody
## stating a figure, and is only reached when there is no ledger at all. Nothing either way gives
## `null`, which every caller reports as not known rather than as nothing (REQ-B30).
func _billed_for(job_id: String) -> Money:
	if billing != null:
		return billing.invoiced_total(job_id)
	if jobs != null:
		var held: Variant = jobs.invoiced.get(job_id, null)
		if held is Money:
			return held
	return null


## A job's cost report, built from the records this desk holds. The billing ledger supplies the billed
## figure when it is here, which is the one thing a cost report deliberately leaves alone (§8.4).
func _report_for(job: Job) -> JobCost:
	return JobCostScript.of(
		job, jobs.purchase_orders_for(job.id), jobs.change_orders_for(job.id),
		jobs.entries_for(job.id), _billed_for(job.id)
	)


## Said out loud when the billed figure came from the desk's own dictionary rather than from invoices,
## because a number somebody typed and a document are not the same kind of evidence and a figure that
## did not say which it used would let the reader assume the stronger one.
func _billed_from_the_desk() -> String:
	if billing != null:
		return ""
	return " (from the job desk's own billed figures, as no ledger is loaded)"


# --- making a figure ----------------------------------------------------------------------------


func _blank(key: String, missing: String = "") -> Figure:
	var made: Figure = Figure.new()
	made.key = key
	made.label = label_for(key)
	made.basis = basis_for(key)
	made.ok = false
	made.missing = missing
	return made


func _found(key: String, value: Variant, words: String, window: String) -> Figure:
	var made: Figure = Figure.new()
	made.key = key
	made.label = label_for(key)
	made.basis = basis_for(key)
	made.ok = true
	made.value = value
	made.words = words
	made.window = window
	return made


# --- reading dates ------------------------------------------------------------------------------


## The leads won in a window, by decision date. The decision is the lead's own `closed_at`, which is the
## date the last stage event carried (section 10's basis for win rate, average sale and cycle alike).
func _won_in(from: String, to: String) -> Array[Lead]:
	var out: Array[Lead] = []
	if pipeline == null:
		return out
	for held in pipeline.leads:
		if held.stage != LeadScript.WON or held.closed_at.is_empty():
			continue
		if not _in_window(held.closed_at, from, to):
			continue
		out.append(held)
	return out


## Is an ISO moment inside a window? An empty bound is open, and an empty moment cannot be placed in a
## window at all. The same rule `Pipeline` applies to its own figures, so a funnel and a win rate for
## one window cannot disagree about what the window is.
static func _in_window(at: String, from: String, to: String) -> bool:
	if from.strip_edges().is_empty() and to.strip_edges().is_empty():
		return true
	if at.strip_edges().is_empty():
		return false
	var start := from.strip_edges()
	var finish := to.strip_edges()
	return (start.is_empty() or at >= start) and (finish.is_empty() or at <= finish)


## An as-of moment as a bare date, or empty when nobody stated one this file can read. A "now" figure
## with no moment refuses rather than reading the clock, so a report is reproducible.
static func _moment(now: String) -> String:
	var text := now.strip_edges()
	if text.length() < 10 or not text.contains("-"):
		return ""
	return text.substr(0, 10)


## The day an ISO moment falls on. A timestamp and a bare date both give their date.
static func _day_of(at: String) -> String:
	var text := at.strip_edges()
	if text.length() >= 10:
		return text.substr(0, 10)
	return text


## Seconds since the epoch from an ISO-8601 string, 0 when it cannot be read. A bare date is midnight.
static func _unix(iso: String) -> int:
	var text := iso.strip_edges()
	if text.is_empty():
		return 0
	if text.ends_with("Z"):
		text = text.substr(0, text.length() - 1)
	if text.length() == 10:
		text += "T00:00:00"
	if not text.contains("T"):
		return 0
	return Time.get_unix_time_from_datetime_string(text)


## How many days a span of seconds covers, counting both ends.
static func _days_between(start: int, finish: int) -> int:
	return floori(float(finish - start) / float(SECONDS_PER_DAY)) + 1


static func _date_at(start: int, offset: int) -> String:
	return Time.get_date_string_from_unix_time(start + offset * SECONDS_PER_DAY)


static func _bucket_of(days_late: int) -> int:
	for index in range(BUCKET_LAST_DAY.size()):
		if days_late <= BUCKET_LAST_DAY[index]:
			return index
	return BUCKETS.size() - 1


# --- saying numbers -----------------------------------------------------------------------------


static func _money_text(cents: int, currency: StringName) -> String:
	return MoneyScript.of(cents, currency).format_with_currency()


## A rate in parts per million as a percentage. Two decimals at most, and never fewer than one - a
## whole rate reads 100.0% and a rate of two thirds reads 66.67%, which is String.num's own trimming
## rather than something this file does.
static func _percent_text(ppm: int) -> String:
	return "%s%%" % String.num(float(ppm) / 10000.0, 2)


## A mean over a number of things, in whole days. Rounded half away from zero, like every other mean
## here, so a cycle a person works out on paper comes out the same as this.
static func _mean_days(total_seconds: int, count: int) -> int:
	if count <= 0:
		return 0
	return MoneyScript.rounded_div(total_seconds, count * SECONDS_PER_DAY)


static func _hours_text(minutes: int) -> String:
	var hours := floori(float(minutes) / float(MINUTES_PER_HOUR))
	var rest := minutes - hours * MINUTES_PER_HOUR
	return "%d hour(s) %d minute(s)" % [hours, rest]