class_name Pipeline
extends RefCounted
## The leads, and the questions a salesperson asks about them (spec section 4.7, REQ-B4).
##
## Every figure here is a **pure function of the leads' event histories**, computable for any date
## range, so a report for last March is the same report next year (REQ-B4). Nothing accumulates: the
## funnel is computed from the `to` stage and `at` time of each event, the win rate from the decision
## date, and a figure that cannot be computed is **refused, naming what is missing**, rather than
## shown as zero (REQ-B16).
##
## Dates are **ISO-8601 UTC strings compared as text**. That is only sound because the form is fixed
## and zero-padded, which is exactly why the form is fixed and zero-padded - and why a window is a
## pair of strings rather than a pair of parsed times.

const LeadScript := preload("res://scripts/biz/lead.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")

## The odds an open deal closes, by stage, in parts per million. A **stated table** rather than a
## number buried in a formula, because probability weighting is an opinion and an opinion has to be
## visible to be argued with. An open stage with no entry here is not counted at all, not counted at
## zero - the figure says so.
const ODDS_PPM := {
	LeadScript.LEAD: 100000,
	LeadScript.QUALIFIED: 250000,
	LeadScript.VISIT: 400000,
	LeadScript.ESTIMATING: 600000,
	LeadScript.PROPOSED: 800000,
	LeadScript.DORMANT: 50000,
}

const SECONDS_PER_DAY := 86400

var leads: Array[Lead] = []
var currency: StringName = &"CAD"


# --- the list ------------------------------------------------------------------------------


func add(lead: Lead) -> bool:
	if lead == null or lead.id.is_empty():
		return false
	for held in leads:
		if held.id == lead.id:
			return false
	leads.append(lead)
	return true


func find(lead_id: String) -> Lead:
	for held in leads:
		if held.id == lead_id:
			return held
	return null


func lead_count() -> int:
	return leads.size()


func open_leads() -> Array[Lead]:
	var out: Array[Lead] = []
	for held in leads:
		if held.is_open():
			out.append(held)
	return out


## One column per stage, in funnel order, each already carrying its leads. The board draws these.
func columns() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for stage_value in LeadScript.STAGES.keys():
		var stage_int := int(stage_value)
		var column: Array[Lead] = []
		for held in leads:
			if held.stage == stage_int:
				column.append(held)
		out.append({
			"stage": stage_int,
			"name": LeadScript.stage_name(stage_int),
			"leads": column,
		})
	return out


# --- the funnel ----------------------------------------------------------------------------


## Count and value of the leads that **entered** each funnel stage within the window, and nobody
## else. A lead is placed by the event that moved it into the stage, not by where it is now, so the
## bar for March's proposals counts March's arrivals - even for a lead that has since been won.
##
## Returns one row per funnel stage in draw order: `{stage, name, count, value_cents, currency}`.
func funnel(from: String = "", to: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for stage_int in LeadScript.FUNNEL_ORDER:
		var count := 0
		var cents := 0
		for held in leads:
			var event := held.event_into(stage_int)
			if event.is_empty():
				continue
			if _in_window(String(event.get("at", "")), from, to):
				count += 1
				cents += held.value().cents
		out.append({
			"stage": stage_int,
			"name": LeadScript.stage_name(stage_int),
			"count": count,
			"value_cents": cents,
			"currency": String(currency),
		})
	return out


## How many of the leads that reached `from_stage` in the window went on to reach `to_stage`. This is
## the figure a salesperson checks on a Monday (section 2.7): the conversion between two bars.
##
## Returns `{ok, reached, converted, ppm, reason}`. Refused when nothing reached `from_stage` in the
## window - a conversion out of no leads is not zero per cent, it is unknown.
func conversion(from_stage: int, to_stage: int, from: String = "", to: String = "") -> Dictionary:
	if not LeadScript.is_stage(from_stage) or not LeadScript.is_stage(to_stage):
		return {"ok": false, "reached": 0, "converted": 0, "ppm": 0,
			"reason": "conversion needs two stages, and one of these is not a stage"}
	var reached := 0
	var converted := 0
	for held in leads:
		var source_event := held.event_into(from_stage)
		if source_event.is_empty() or not _in_window(String(source_event.get("at", "")), from, to):
			continue
		reached += 1
		var arrival := String(source_event.get("at", ""))
		var target_event := held.event_into(to_stage)
		if not target_event.is_empty() and String(target_event.get("at", "")) >= arrival:
			converted += 1
	if reached == 0:
		return {"ok": false, "reached": 0, "converted": 0, "ppm": 0,
			"reason": "no leads reached %s in this window" % LeadScript.stage_name(from_stage)}
	return {"ok": true, "reached": reached, "converted": converted,
		"ppm": MoneyScript.rounded_div(converted * 1000000, reached), "reason": ""}


# --- win, loss and why ---------------------------------------------------------------------


## Won over won-plus-lost, on the **decision date** (section 10). Withdrawn leads are excluded from
## the ratio and counted separately, because a customer who withdrew never decided.
##
## Refused when a lost lead in the window carries no loss reason: the reason is what the report is
## made of, and a win rate that quietly ignored the blanks would be a number nobody should trust.
##
## Returns `{ok, ppm, won, lost, withdrawn, closed, reason}`.
func win_rate(from: String = "", to: String = "") -> Dictionary:
	var won := 0
	var lost := 0
	var withdrawn := 0
	var missing := 0
	for held in leads:
		if not _in_window(held.closed_at, from, to) or held.closed_at.is_empty():
			continue
		match held.stage:
			LeadScript.WON:
				won += 1
			LeadScript.LOST:
				lost += 1
				if held.lost_reason == &"":
					missing += 1
			LeadScript.WITHDRAWN:
				withdrawn += 1
	var closed := won + lost + withdrawn
	if missing > 0:
		return {"ok": false, "ppm": 0, "won": won, "lost": lost, "withdrawn": withdrawn,
			"closed": closed,
			"reason": "win rate unavailable: %d of %d closed leads have no lost reason" % [missing, closed]}
	if won + lost == 0:
		return {"ok": false, "ppm": 0, "won": won, "lost": lost, "withdrawn": withdrawn,
			"closed": closed, "reason": "no won or lost leads in this window"}
	return {"ok": true, "ppm": MoneyScript.rounded_div(won * 1000000, won + lost), "won": won,
		"lost": lost, "withdrawn": withdrawn, "closed": closed, "reason": ""}


## What was lost and why, by reason code, worth more knowing than the count alone (section 10).
## Returns rows `{reason, name, count, value_cents, currency}`, most frequent first.
func lost_reasons(from: String = "", to: String = "") -> Array[Dictionary]:
	var tally: Dictionary = {}
	for held in leads:
		if held.stage != LeadScript.LOST or held.closed_at.is_empty():
			continue
		if not _in_window(held.closed_at, from, to):
			continue
		var key := String(held.lost_reason)
		if not tally.has(key):
			tally[key] = {"count": 0, "cents": 0}
		tally[key]["count"] += 1
		tally[key]["cents"] += held.value().cents
	var out: Array[Dictionary] = []
	for key in tally.keys():
		out.append({
			"reason": key,
			"name": key if not key.is_empty() else "No reason given",
			"count": int(tally[key]["count"]),
			"value_cents": int(tally[key]["cents"]),
			"currency": String(currency),
		})
	out.sort_custom(_by_count_then_name)
	return out


## Win rate and average value by lead source, on the decision date (section 10). A source that
## closed nothing reports a refused win rate rather than a zero.
func source_performance(from: String = "", to: String = "") -> Array[Dictionary]:
	var tokens: Array[StringName] = []
	for key in LeadScript.SOURCES.keys():
		tokens.append(StringName(key))
	# Sorted by the *name a table prints*, not the token: "Yard sign" belongs after "Web".
	tokens.sort_custom(func(a: StringName, b: StringName) -> bool:
		return LeadScript.source_name(a) < LeadScript.source_name(b))
	var out: Array[Dictionary] = []
	for token in tokens:
		var won := 0
		var closed := 0
		var cents := 0
		for held in leads:
			if held.source != token or held.closed_at.is_empty():
				continue
			if not _in_window(held.closed_at, from, to):
				continue
			if held.stage == LeadScript.WON:
				won += 1
				closed += 1
				cents += held.value().cents
			elif held.stage == LeadScript.LOST:
				closed += 1
			else:
				continue
		var ppm := 0
		var reason := ""
		if closed == 0:
			reason = "no decided leads from %s in this window" % LeadScript.source_name(token)
		elif won == 0:
			ppm = 0
		else:
			ppm = MoneyScript.rounded_div(won * 1000000, closed)
		out.append({
			"source": String(token),
			"name": LeadScript.source_name(token),
			"won": won,
			"closed": closed,
			"ppm": ppm,
			"average_cents": MoneyScript.rounded_div(cents, won) if won > 0 else 0,
			"currency": String(currency),
			"reason": reason,
		})
	return out


# --- the present --------------------------------------------------------------------------


## The open pipeline right now, raw and probability-weighted by stage. The weighted figure is an
## opinion, so it is labelled as one wherever it prints (section 2.9's spirit): the table of odds is
## named with it.
##
## Returns `{raw_cents, weighted_cents, count, currency, stages_missing_odds}`.
func pipeline_value() -> Dictionary:
	var raw := 0
	var weighted := 0
	var count := 0
	var missing: Array[int] = []
	for held in leads:
		if not held.is_open():
			continue
		count += 1
		raw += held.value().cents
		if not ODDS_PPM.has(held.stage):
			if not missing.has(held.stage):
				missing.append(held.stage)
			continue
		weighted += MoneyScript.rounded_div(held.value().cents * int(ODDS_PPM[held.stage]), 1000000)
	return {"raw_cents": raw, "weighted_cents": weighted, "count": count,
		"currency": String(currency), "stages_missing_odds": missing}


## Open leads whose expected close date has passed, with how many days late they are (section 10).
## Sorted most-late first. A lead with no expected date is not "on time", it is unscheduled, and is
## left out rather than counted as late.
func slipped(now: String = "") -> Array[Dictionary]:
	var now_unix := _unix(now)
	var out: Array[Dictionary] = []
	for held in leads:
		if not held.is_open() or held.expected_close_at.is_empty():
			continue
		var due_unix := _unix(held.expected_close_at)
		if due_unix == 0 or due_unix >= now_unix:
			continue
		out.append({
			"id": held.id,
			"name": held.name,
			"stage": held.stage,
			"stage_name": LeadScript.stage_name(held.stage),
			"due": held.expected_close_at,
			"days_late": int((now_unix - due_unix) / SECONDS_PER_DAY),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["days_late"]) > int(b["days_late"]))
	return out


# --- the file ------------------------------------------------------------------------------


func to_dict() -> Dictionary:
	var list: Array = []
	for held in leads:
		list.append(held.to_dict())
	return {"currency": String(currency), "leads": list}


static func from_dict(data: Dictionary) -> Pipeline:
	var pipe: Pipeline = PipelineScript.new()
	pipe.currency = StringName(data.get("currency", "CAD"))
	var list = data.get("leads", [])
	if list is Array:
		for entry in (list as Array):
			if entry is Dictionary:
				var lead := LeadScript.from_dict(entry)
				if lead != null:
					pipe.leads.append(lead)
	return pipe


# --- the arithmetic tail --------------------------------------------------------------------


## Is an ISO timestamp inside a window? An empty bound is open. An empty timestamp cannot be placed
## in a window at all, so it only counts when there is no window to place it in.
static func _in_window(at: String, from: String, to: String) -> bool:
	if from.is_empty() and to.is_empty():
		return true
	if at.is_empty():
		return false
	return (from.is_empty() or at >= from) and (to.is_empty() or at <= to)


## Seconds since the epoch from an ISO-8601 string. A bare date is read as midnight, and a trailing
## `Z` is dropped (Godot's parser wants the bare form). Unreadable text is 0, which callers treat as
## "no date" rather than as 1970.
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


static func _by_count_then_name(a: Dictionary, b: Dictionary) -> bool:
	if int(a["count"]) != int(b["count"]):
		return int(a["count"]) > int(b["count"])
	return String(a["name"]) < String(b["name"])


const PipelineScript := preload("res://scripts/biz/pipeline.gd")