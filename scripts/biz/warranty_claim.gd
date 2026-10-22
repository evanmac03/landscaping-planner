class_name WarrantyClaim
extends RefCounted
## One claim against a warranty: what failed, whether it is covered, and what was done (phase 12).
##
## A claim is not a punch item with a different word on it. A punch item is work the contractor owes;
## a claim is a **question about who owes it** - the plant died in its first summer, so is that the
## nursery's material, the weather, or the watering the client did not do? - and the answer is a
## decision somebody makes, in writing, with a reason. That is why this record's middle state is not
## "fixed" but `answered`, and why an answer without a reason is refused: the reason is the whole
## value of a warranty log, because it is what the next claim is judged against.
##
## ## The state is a function of the records
##
## `open` is reported and not answered; `answered` has a verdict; `done` is a covered claim that has
## been put right. A claim that is **not** covered is finished when it is answered - there is nothing
## left to do - so `is_done()` says yes for both, and `state_name()` keeps the two apart in words:
## "answered, not covered" reads differently to a person than "answered, to be done".

const RateScript := preload("res://scripts/biz/rate.gd")

const OPEN := &"OPEN"
const ANSWERED := &"ANSWERED"
const DONE := &"DONE"

const STATE_NAMES := {
	"OPEN": "open, not yet answered",
	"ANSWERED": "answered",
	"DONE": "done",
}

var id: String = ""
var job_id: String = ""
## When it was reported, who reported it, and what is wrong. All three required: a claim nobody made
## is not a claim.
var reported_at: String = ""
var reported_by: String = ""
var what: String = ""
## The answer: whether the warranty covers it, why, and who decided. All three required, together.
var answered_at: String = ""
var answered_by: String = ""
var covered: bool = false
var answer_why: String = ""
## The work, once a covered claim has been put right.
var done_at: String = ""
var done_note: String = ""


func _init(claim_id: String = "") -> void:
	id = claim_id


static func make(claim_id: String, job: String, at: String, about: String, by: String) -> WarrantyClaim:
	if claim_id.strip_edges().is_empty() or job.strip_edges().is_empty():
		return null
	if about.strip_edges().is_empty() or by.strip_edges().is_empty() or not RateScript.is_date(at):
		return null
	var claim := WarrantyClaimScript.new(claim_id)
	claim.job_id = job
	claim.reported_at = at
	claim.reported_by = by.strip_edges()
	claim.what = about.strip_edges()
	return claim


# --- the state, worked out ------------------------------------------------------------------


func is_answered() -> bool:
	return not answered_at.strip_edges().is_empty()


func is_done() -> bool:
	if not is_answered():
		return false
	# Not covered is a complete answer: there is nothing to do about it.
	return not covered or not done_at.strip_edges().is_empty()


func is_open() -> bool:
	return not is_answered()


## Whether this claim still wants somebody: a claim nobody has answered, or a covered claim nobody
## has put right. What a warranty report counts.
func needs_attention() -> bool:
	return not is_done()


func state() -> StringName:
	if not is_answered():
		return OPEN
	return DONE if is_done() else ANSWERED


func state_name() -> String:
	return String(STATE_NAMES.get(String(state()), String(state())))


# --- the acts --------------------------------------------------------------------------------


## The answer. Refused without a reason and without a person, and refused twice: an answer that is
## overwritten is an answer nobody can rely on, and a second look at the same claim is a second
## claim about the same thing.
func mark_answered(by: String, at: String, is_covered: bool, why: String) -> bool:
	if is_answered():
		return false
	if by.strip_edges().is_empty() or why.strip_edges().is_empty() or not RateScript.is_date(at):
		return false
	answered_by = by.strip_edges()
	answered_at = at
	covered = is_covered
	answer_why = why.strip_edges()
	return true


## The work, once it has been done. Refused for a claim that is not covered - nothing is owed on it -
## and refused before it has been answered.
func mark_done(at: String, what_was_done: String = "") -> bool:
	if not is_answered() or not covered:
		return false
	if not done_at.strip_edges().is_empty() or not RateScript.is_date(at):
		return false
	done_at = at
	done_note = what_was_done.strip_edges()
	return true


# --- describing it ---------------------------------------------------------------------------


func describe() -> String:
	if not is_sound():
		return problem()
	var parts := PackedStringArray()
	parts.append("%s: %s" % [reported_at, what])
	parts.append("reported by %s" % reported_by)
	if is_answered():
		parts.append("covered" if covered else "not covered")
		parts.append("%s on %s: %s" % [answered_by, answered_at, answer_why])
	else:
		parts.append(state_name())
	if covered and not done_at.strip_edges().is_empty():
		parts.append("done %s%s" % [
			done_at, "" if done_note.strip_edges().is_empty() else " (%s)" % done_note,
		])
	return "%s (%s)" % [parts[0], ", ".join(parts.slice(1))]


func row() -> Dictionary:
	return {
		"id": id,
		"job_id": job_id,
		"reported_at": reported_at,
		"reported_by": reported_by,
		"what": what,
		"answered_at": answered_at,
		"answered_by": answered_by,
		"covered": covered,
		"answer_why": answer_why,
		"done_at": done_at,
		"state": String(state()),
		"state_name": state_name(),
		"text": describe(),
	}


# --- soundness -------------------------------------------------------------------------------


func problem() -> String:
	if id.strip_edges().is_empty():
		return "a claim with no id"
	if job_id.strip_edges().is_empty():
		return "claim '%s' belongs to no job" % id
	if what.strip_edges().is_empty():
		return "claim '%s' does not say what failed" % id
	if reported_by.strip_edges().is_empty():
		return "claim '%s' does not say who reported it" % id
	if not RateScript.is_date(reported_at):
		return "claim '%s' was reported on a date that is not a date: '%s'" % [id, reported_at]
	if is_answered():
		if not RateScript.is_date(answered_at):
			return "claim '%s' was answered on a date that is not a date: '%s'" % [id, answered_at]
		if answered_by.strip_edges().is_empty() or answer_why.strip_edges().is_empty():
			return "claim '%s' was answered with no reason or nobody to ask" % id
	if not done_at.strip_edges().is_empty():
		if not covered:
			return "claim '%s' was put right and is not covered" % id
		if not RateScript.is_date(done_at):
			return "claim '%s' was done on a date that is not a date: '%s'" % [id, done_at]
	return ""


func is_sound() -> bool:
	return problem().is_empty()


# --- persistence -----------------------------------------------------------------------------


func copy() -> WarrantyClaim:
	return from_dict(to_dict())


func to_dict() -> Dictionary:
	return {
		"id": id,
		"job_id": job_id,
		"reported_at": reported_at,
		"reported_by": reported_by,
		"what": what,
		"answered_at": answered_at,
		"answered_by": answered_by,
		"covered": covered,
		"answer_why": answer_why,
		"done_at": done_at,
		"done_note": done_note,
	}


## A claim that is not a dictionary is dropped by the caller. A claim with no id is kept: it is wrong
## and it says so, and a dropped claim is a claim the client made and the office cannot find.
static func from_dict(data: Dictionary) -> WarrantyClaim:
	var claim: WarrantyClaim = WarrantyClaimScript.new(String(data.get("id", "")))
	claim.job_id = String(data.get("job_id", ""))
	claim.reported_at = String(data.get("reported_at", ""))
	claim.reported_by = String(data.get("reported_by", ""))
	claim.what = String(data.get("what", ""))
	claim.answered_at = String(data.get("answered_at", ""))
	claim.answered_by = String(data.get("answered_by", ""))
	claim.covered = bool(data.get("covered", false))
	claim.answer_why = String(data.get("answer_why", ""))
	claim.done_at = String(data.get("done_at", ""))
	claim.done_note = String(data.get("done_note", ""))
	return claim


const WarrantyClaimScript := preload("res://scripts/biz/warranty_claim.gd")