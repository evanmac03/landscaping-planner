class_name PunchItem
extends RefCounted
## One thing on a punch list: what is not right, and what happened about it (phase 12).
##
## A punch list is the walk at the end of a job. Somebody - the designer, the client, the general
## contractor - walks the garden with the plans in hand and writes down what is not finished or not
## right: a paver out of level, a shrub planted crooked, a gate that does not latch, a line of
## edging missing. Each one is handed to whoever is to put it right, then looked at again, and the
## job is not finished until the list is empty. Everything about a punch list is in four facts per
## item, and this record is those four facts.
##
## ## The state is a function of the records, not a field
##
## `state()` is **worked out** from the timestamps - withdrawn, accepted, fixed, or open - and there
## is no stored state field, for the reason phase 6 gives about purchase orders: a stored enum is a
## second place the truth lives, and the two disagree the first time a record is edited by hand. The
## same rule gives a punch list its next question for free: an item with a `fixed_at` and no
## `accepted_at` is one waiting to be **checked**, which is the step an office most often forgets.
##
## ## A rejection puts the item back
##
## Checking an item can fail, and a rejection **returns the item to the list** rather than leaving it
## in a fifth state: that is what a punch walk does - it is looked at again after it is put right
## again. The rejection is not a loss, either: it is appended to `rejections` with the moment, who
## rejected it, the reason they gave, and the fix it was rejecting, so a list that has been round
## twice says so. Clearing `fixed_at` is what makes the state derivable, and the entry in
## `rejections` is what stops that from being a deleted fact.
##
## ## What this record does not carry: money
##
## There is no cost or credit field. Putting a deficiency right costs labour and material, and those
## are already records of their own - a time entry against a cost code, a purchase order - so a
## money field here would be a **second total for the same money**, and the job cost report would be
## summing one of them. A punch list is about work, not about money.

const RateScript := preload("res://scripts/biz/rate.gd")

## The states an item can be in, in the order a list is worked through.
const OPEN := &"OPEN"
const FIXED := &"FIXED"
const CLOSED := &"CLOSED"
const WITHDRAWN := &"WITHDRAWN"

## What each state is called in words a person reads.
const STATE_NAMES := {
	"OPEN": "open",
	"FIXED": "fixed, waiting to be checked",
	"CLOSED": "closed",
	"WITHDRAWN": "withdrawn",
}

## What an item in each state is *waiting for*, which is the question a punch list answers. A closed
## or withdrawn item is waiting for nothing, and says so by having nothing to say.
const WAITING_NAMES := {
	"OPEN": "waiting to be put right",
	"FIXED": "waiting to be checked",
	"CLOSED": "",
	"WITHDRAWN": "",
}

var id: String = ""
## The job this belongs to. A punch item with no job is not a punch item: it is somebody's note.
var job_id: String = ""
## **Where** it is, in words a person can find: "back patio, north edge". Required. A deficiency
## nobody can locate is a deficiency nobody can put right, and drawing coordinates would not help
## the person holding a trowel.
var where: String = ""
## **What** is wrong. Required.
var what: String = ""
## Who said so, and when. Both required: a list nobody signed is a list nobody owns.
var raised_by: String = ""
var raised_at: String = ""
## Who is to put it right - a trade, a crew's label, or "" for our own crew.
var who: String = ""
var fixed_at: String = ""
var fixed_note: String = ""
## The check that passed. An acceptance needs a person: "it was looked at" has to name who looked.
var accepted_by: String = ""
var accepted_at: String = ""
## Withdrawn items: raised in error, or agreed to be left as they are. A withdrawn item stops
## counting against the job, and it is kept rather than deleted so the list still says it happened.
var withdrawn_by: String = ""
var withdrawn_at: String = ""
var withdrawn_why: String = ""
## Every rejection, oldest first: `{at, by, why, was_fixed_at}`. Append-only.
var rejections: Array[Dictionary] = []
var note: String = ""


func _init(item_id: String = "") -> void:
	id = item_id


## A new item, refused rather than stored when it cannot be read. The moment has to be a date this
## program writes and the place and the description have to say something, because an item with
## either missing is an item that will sit on the list for the rest of the job.
static func make(item_id: String, job: String, at: String, place: String, description: String,
		by: String) -> PunchItem:
	if item_id.strip_edges().is_empty() or job.strip_edges().is_empty():
		return null
	if place.strip_edges().is_empty() or description.strip_edges().is_empty():
		return null
	if by.strip_edges().is_empty() or not RateScript.is_date(at):
		return null
	var item := PunchItemScript.new(item_id)
	item.job_id = job
	item.where = place.strip_edges()
	item.what = description.strip_edges()
	item.raised_by = by.strip_edges()
	item.raised_at = at
	return item


# --- the state, worked out ------------------------------------------------------------------


## Which state this item is in. Withdrawn outranks everything - an item taken off the list is off it
## however far round it had got - and a passing check outranks a fix.
func state() -> StringName:
	if not withdrawn_at.strip_edges().is_empty():
		return WITHDRAWN
	if not accepted_at.strip_edges().is_empty():
		return CLOSED
	if not fixed_at.strip_edges().is_empty():
		return FIXED
	return OPEN


func state_name() -> String:
	return String(STATE_NAMES.get(String(state()), String(state())))


## What this item is waiting for, or "" when it is waiting for nothing.
func waiting_name() -> String:
	return String(WAITING_NAMES.get(String(state()), ""))


## Whether this item still counts against the job.
func is_outstanding() -> bool:
	var held: StringName = state()
	return held == OPEN or held == FIXED


func is_open() -> bool:
	return state() == OPEN


func is_fixed() -> bool:
	return state() == FIXED


func is_closed() -> bool:
	return state() == CLOSED


func is_withdrawn() -> bool:
	return state() == WITHDRAWN


func rejection_count() -> int:
	return rejections.size()


# --- the acts --------------------------------------------------------------------------------


## It has been put right. Refused for an item that is closed or withdrawn, and for a moment that is
## not a date: "when it was done" is a fact somebody has to state.
func mark_fixed(at: String, what_was_done: String = "") -> bool:
	if not is_open():
		return false
	if not RateScript.is_date(at):
		return false
	fixed_at = at
	fixed_note = what_was_done.strip_edges()
	return true


## The check passed. Refused unless there is a fix to check, and refused without a person: an
## acceptance nobody signed is not an acceptance.
func mark_accepted(by: String, at: String) -> bool:
	if not is_fixed():
		return false
	if by.strip_edges().is_empty() or not RateScript.is_date(at):
		return false
	accepted_by = by.strip_edges()
	accepted_at = at
	return true


## The check failed. The item goes back on the list, and the rejection is recorded with the fix it
## was rejecting. Refused without a reason: a rejection nobody explained is one the crew cannot act
## on, and the second time round the same mistake is made.
func mark_rejected(by: String, at: String, why: String) -> bool:
	if not is_fixed():
		return false
	if by.strip_edges().is_empty() or why.strip_edges().is_empty() or not RateScript.is_date(at):
		return false
	rejections.append({"at": at, "by": by.strip_edges(), "why": why.strip_edges(), "was_fixed_at": fixed_at})
	fixed_at = ""
	fixed_note = ""
	return true


## Taken off the list: raised in error, or agreed with the client to be left as it is. Refused once
## the item is closed, and refused without a reason - the same rule as a rejection, because "why is
## this not being done" is the first thing anybody asks about a line that vanished.
func mark_withdrawn(by: String, at: String, why: String) -> bool:
	if is_closed() or is_withdrawn():
		return false
	if by.strip_edges().is_empty() or why.strip_edges().is_empty() or not RateScript.is_date(at):
		return false
	withdrawn_by = by.strip_edges()
	withdrawn_at = at
	withdrawn_why = why.strip_edges()
	return true


# --- describing it ---------------------------------------------------------------------------


## The one line a list shows: where it is, what is wrong, and where it has got to.
func describe() -> String:
	if not is_sound():
		return problem()
	var parts := PackedStringArray()
	parts.append("%s: %s" % [where, what])
	if not who.strip_edges().is_empty():
		parts.append("with %s" % who)
	parts.append("raised %s by %s" % [raised_at, raised_by])
	var waiting: String = waiting_name()
	if not waiting.is_empty():
		parts.append(waiting)
	else:
		parts.append(state_name())
	if is_closed():
		parts.append("checked by %s on %s" % [accepted_by, accepted_at])
	if is_withdrawn():
		parts.append("on %s by %s: %s" % [withdrawn_at, withdrawn_by, withdrawn_why])
	if rejection_count() > 0:
		parts.append("put right and rejected %d time%s" % [
			rejection_count(), "" if rejection_count() == 1 else "s",
		])
	if not fixed_note.strip_edges().is_empty() and is_fixed():
		parts.append("done: %s" % fixed_note)
	return "%s (%s)" % [parts[0], ", ".join(parts.slice(1))]


## The rows a list is drawn from. Written here rather than in the page for the reason every other
## row in this module is: the page shows what a record says, and a second place to word a row is a
## second place for it to drift.
func row() -> Dictionary:
	return {
		"id": id,
		"job_id": job_id,
		"where": where,
		"what": what,
		"who": who,
		"state": String(state()),
		"state_name": state_name(),
		"waiting": waiting_name(),
		"raised_by": raised_by,
		"raised_at": raised_at,
		"fixed_at": fixed_at,
		"accepted_by": accepted_by,
		"accepted_at": accepted_at,
		"withdrawn_at": withdrawn_at,
		"rejections": rejection_count(),
		"text": describe(),
	}


# --- soundness -------------------------------------------------------------------------------


## The one thing wrong with this item, or "". A loaded record can be wrong in ways `make` and the
## acts refuse, which is the whole reason this exists: the file is not the editor.
func problem() -> String:
	if id.strip_edges().is_empty():
		return "an item with no id"
	if job_id.strip_edges().is_empty():
		return "'%s' belongs to no job" % id
	if where.strip_edges().is_empty():
		return "'%s' does not say where it is" % id
	if what.strip_edges().is_empty():
		return "'%s' does not say what is wrong" % id
	if raised_by.strip_edges().is_empty():
		return "'%s' does not say who raised it" % id
	if not RateScript.is_date(raised_at):
		return "'%s' was raised on a date that is not a date: '%s'" % [id, raised_at]
	if not fixed_at.strip_edges().is_empty() and not RateScript.is_date(fixed_at):
		return "'%s' was fixed on a date that is not a date: '%s'" % [id, fixed_at]
	if not accepted_at.strip_edges().is_empty():
		if not RateScript.is_date(accepted_at):
			return "'%s' was checked on a date that is not a date: '%s'" % [id, accepted_at]
		if accepted_by.strip_edges().is_empty():
			return "'%s' was accepted and does not say by whom" % id
	if not accepted_at.strip_edges().is_empty() and fixed_at.strip_edges().is_empty():
		return "'%s' was accepted with nothing recorded as fixed" % id
	if not withdrawn_at.strip_edges().is_empty():
		if not RateScript.is_date(withdrawn_at):
			return "'%s' was withdrawn on a date that is not a date: '%s'" % [id, withdrawn_at]
		if withdrawn_by.strip_edges().is_empty() or withdrawn_why.strip_edges().is_empty():
			return "'%s' was withdrawn with no reason or nobody to ask" % id
	for entry: Dictionary in rejections:
		if not RateScript.is_date(String(entry.get("at", ""))):
			return "'%s' has a rejection with no date on it" % id
		if String(entry.get("why", "")).strip_edges().is_empty():
			return "'%s' has a rejection nobody explained" % id
	return ""


func is_sound() -> bool:
	return problem().is_empty()


# --- persistence -----------------------------------------------------------------------------


func copy() -> PunchItem:
	return from_dict(to_dict())


func to_dict() -> Dictionary:
	return {
		"id": id,
		"job_id": job_id,
		"where": where,
		"what": what,
		"raised_by": raised_by,
		"raised_at": raised_at,
		"who": who,
		"fixed_at": fixed_at,
		"fixed_note": fixed_note,
		"accepted_by": accepted_by,
		"accepted_at": accepted_at,
		"withdrawn_by": withdrawn_by,
		"withdrawn_at": withdrawn_at,
		"withdrawn_why": withdrawn_why,
		"rejections": rejections.duplicate(true),
		"note": note,
	}


## An item that is not a dictionary is dropped by the caller. An item with no id is kept: it is
## wrong and it says so, and dropping it would silently shorten a punch list.
static func from_dict(data: Dictionary) -> PunchItem:
	var item: PunchItem = PunchItemScript.new(String(data.get("id", "")))
	item.job_id = String(data.get("job_id", ""))
	item.where = String(data.get("where", ""))
	item.what = String(data.get("what", ""))
	item.raised_by = String(data.get("raised_by", ""))
	item.raised_at = String(data.get("raised_at", ""))
	item.who = String(data.get("who", ""))
	item.fixed_at = String(data.get("fixed_at", ""))
	item.fixed_note = String(data.get("fixed_note", ""))
	item.accepted_by = String(data.get("accepted_by", ""))
	item.accepted_at = String(data.get("accepted_at", ""))
	item.withdrawn_by = String(data.get("withdrawn_by", ""))
	item.withdrawn_at = String(data.get("withdrawn_at", ""))
	item.withdrawn_why = String(data.get("withdrawn_why", ""))
	var held: Variant = data.get("rejections", [])
	if held is Array:
		for entry: Variant in held:
			if entry is Dictionary:
				item.rejections.append(entry)
	item.note = String(data.get("note", ""))
	return item


const PunchItemScript := preload("res://scripts/biz/punch_item.gd")