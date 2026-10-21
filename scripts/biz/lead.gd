class_name Lead
extends RefCounted
## A sales lead: somebody who might buy, and the history of what happened to them.
##
## A stage is a field **plus a history** (spec section 4.7). The field is what the board shows now;
## the history is the events that moved it, and the history is what a funnel is computed from -
## because "how many of March's leads became proposals" cannot be answered by a field that only
## holds this month's value (section 2.7, REQ-B4). So a transition is never just an assignment: it
## appends an event, and everything downstream reads the events rather than the field.

const MoneyScript := preload("res://scripts/biz/money.gd")

## The stages, in funnel order, with the three terminal ones last. The order is the order a funnel
## draws its bars in, which is why it is a list and not just an enum.
const LEAD := 0
const QUALIFIED := 1
const VISIT := 2
const ESTIMATING := 3
const PROPOSED := 4
const WON := 5
const LOST := 6
const WITHDRAWN := 7
const DORMANT := 8

const STAGES := {
	LEAD: "Lead",
	QUALIFIED: "Qualified",
	VISIT: "Site visit",
	ESTIMATING: "Estimating",
	PROPOSED: "Proposed",
	WON: "Won",
	LOST: "Lost",
	WITHDRAWN: "Withdrawn",
	DORMANT: "Dormant",
}

## The order a funnel draws, open stages first and terminal states after them.
const FUNNEL_ORDER: Array[int] = [LEAD, QUALIFIED, VISIT, ESTIMATING, PROPOSED, WON]

## The stages from which there is no further pipeline: the decision has been made, or the lead has
## left. A funnel's win/loss figures are measured on the *decision date* (section 10), which is why
## a lead remembers when it closed.
const CLOSED: Array[int] = [WON, LOST, WITHDRAWN]

## Where leads come from. A source is data rather than a free note because "which source wins most"
## is a question a business asks (section 10), and a note cannot answer it.
const SOURCES := {
	&"referral": "Referral",
	&"repeat": "Repeat business",
	&"web": "Web",
	&"sign": "Yard sign",
	&"other": "Other",
}

var id: String = ""
var name: String = ""
var customer: String = ""
var address: String = ""
var source: StringName = &"other"
## What the office thinks the work is worth, in the lead's currency. It is the number a funnel sums.
var value_estimate: Money = null
var stage: int = LEAD
## ISO-8601 UTC strings. They compare as text, which is why a window is a pair of them (section 10).
var opened_at: String = ""
var expected_close_at: String = ""
var closed_at: String = ""
## Required to close a lead as LOST: the loss reason is the whole win/loss report (section 9).
var lost_reason: StringName = &""
## `{at, from, to, by, note}` - one entry per transition, in the order they happened.
var events: Array[Dictionary] = []


func _init(lead_id: String = "", lead_name: String = "") -> void:
	id = lead_id
	name = lead_name
	value_estimate = MoneyScript.zero()


# --- what a stage is ------------------------------------------------------------------


static func is_stage(candidate: int) -> bool:
	return STAGES.has(candidate)


## "Proposed", for a card or a table cell.
static func stage_name(stage_value: int) -> String:
	return String(STAGES.get(stage_value, "Unknown stage"))


static func is_closed(stage_value: int) -> bool:
	return CLOSED.has(stage_value)


static func source_name(code: StringName) -> String:
	return String(SOURCES.get(code, "Other"))


# --- what a lead holds ------------------------------------------------------------------


func value() -> Money:
	return value_estimate if value_estimate != null else MoneyScript.zero()


func is_open() -> bool:
	return not is_closed(stage)


func event_count() -> int:
	return events.size()


## The event that put this lead into `target`, or an empty dictionary when it never reached it.
## A funnel reads these rather than the `stage` field, so a lead's whole history is answerable.
func event_into(target: int) -> Dictionary:
	for entry in events:
		if int(entry.get("to", -1)) == target:
			return entry
	return {}


# --- moving a lead ----------------------------------------------------------------------


## Record that a lead came into being. A lead's *arrival* in the pipeline is an event like any other
## - without it, a lead created and still in LEAD would have no history to place in the month it
## arrived, and the funnel's first bar would read zero (REQ-B4: nothing is a field that only knows
## the present).
##
## Refuses a lead that already has a history, so opening is not a way to fake an arrival.
func open(at: String = "", by: String = "", note: String = "Opened") -> Dictionary:
	if not events.is_empty():
		return {"ok": false, "reason": "this lead already has a history", "event": {}}
	var event := {"at": at, "from": -1, "to": stage, "by": by, "note": note}
	events.append(event)
	return {"ok": true, "reason": "", "event": event, "from": -1, "to": stage}


## Move a lead to another stage. This is the only way the stage changes, and it always appends an
## event: setting the field alone would leave a lead that says where it is and not how it got there.
##
## Refuses a stage nobody has; refuses a move to where the lead already is, because a transition that
## changes nothing is not a transition; and **refuses to close a lead as LOST without a loss reason**,
## because the reason is what the win/loss report is made of (section 4.7).
##
## Returns `{ok, reason, event, from, to}`.
func move_to(to_stage: int, at: String = "", by: String = "", note: String = "") -> Dictionary:
	if not is_stage(to_stage):
		return {"ok": false, "reason": "that is not a stage a lead can be in", "event": {}}
	if to_stage == stage:
		return {"ok": false, "reason": "%s is already where this lead is" % stage_name(to_stage),
			"event": {}}
	if to_stage == LOST and lost_reason == &"":
		return {"ok": false, "reason": "a lead closed as lost says why, and this one has no lost reason",
			"event": {}}
	var moved_from := stage
	stage = to_stage
	if is_closed(to_stage):
		if closed_at.is_empty():
			closed_at = at
	else:
		# A reopened lead is open again, and a decision date on an open lead would put it in a past
		# period's win/loss figure that it never belonged to.
		closed_at = ""
	var event := {"at": at, "from": moved_from, "to": to_stage, "by": by, "note": note}
	events.append(event)
	return {"ok": true, "reason": "", "event": event, "from": moved_from, "to": to_stage}


## Name the reason a lead might be lost, before it is. Kept separate from `move_to` because a reason
## recorded *before* the decision is a note, and one recorded *with* the decision is the decision.
func set_lost_reason(reason: StringName) -> void:
	lost_reason = reason


# --- the file -------------------------------------------------------------------------


func to_dict() -> Dictionary:
	var events_out: Array = []
	for entry in events:
		events_out.append({
			"at": String(entry.get("at", "")),
			"from": int(entry.get("from", -1)),
			"to": int(entry.get("to", -1)),
			"by": String(entry.get("by", "")),
			"note": String(entry.get("note", "")),
		})
	return {
		"id": id,
		"name": name,
		"customer": customer,
		"address": address,
		"source": String(source),
		"value_estimate": value().to_dict(),
		"stage": stage,
		"opened_at": opened_at,
		"expected_close_at": expected_close_at,
		"closed_at": closed_at,
		"lost_reason": String(lost_reason),
		"events": events_out,
	}


## A record that is not a lead is **dropped rather than invented**: no id and no name is not a lead
## with a blank name, it is a damaged record. A stage nobody has becomes LEAD, because a lead has to
## be somewhere and the start of the pipeline is the only honest default.
static func from_dict(data: Dictionary) -> Lead:
	var lead: Lead = LeadScript.new(String(data.get("id", "")), String(data.get("name", "")))
	if lead.id.is_empty():
		return null
	lead.customer = String(data.get("customer", ""))
	lead.address = String(data.get("address", ""))
	lead.source = StringName(data.get("source", "other"))
	lead.value_estimate = MoneyScript.from_dict(data.get("value_estimate", {}))
	var held := int(data.get("stage", LEAD))
	lead.stage = held if is_stage(held) else LEAD
	lead.opened_at = String(data.get("opened_at", ""))
	lead.expected_close_at = String(data.get("expected_close_at", ""))
	lead.closed_at = String(data.get("closed_at", ""))
	lead.lost_reason = StringName(data.get("lost_reason", ""))
	var events_in = data.get("events", [])
	if events_in is Array:
		for entry in (events_in as Array):
			if entry is Dictionary:
				lead.events.append(_event_from(entry))
	return lead


static func _event_from(entry: Dictionary) -> Dictionary:
	return {
		"at": String(entry.get("at", "")),
		"from": int(entry.get("from", -1)),
		"to": int(entry.get("to", -1)),
		"by": String(entry.get("by", "")),
		"note": String(entry.get("note", "")),
	}


const LeadScript := preload("res://scripts/biz/lead.gd")