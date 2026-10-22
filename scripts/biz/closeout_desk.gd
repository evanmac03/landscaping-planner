class_name CloseoutDesk
extends RefCounted
## The end of the jobs: the punch lists, the hand-over dates and the warranties, in one place
## (phase 12).
##
## Phase 5 to 8 stop at hand-over. A job is made from an estimate, priced, built, costed, billed and
## handed to a ledger - and then the garden is finished, the client walks it, and somebody writes a
## list. This desk holds that list, the day the garden was handed over, and the promise that starts
## on that day.
##
## ## What it decides, and what it does not
##
## It holds the records (`PunchItem`, `Warranty` and its claims) and runs the acts, and it holds **no
## arithmetic and no state**: an item's state is worked out from its own timestamps, a warranty's end
## date from its own term, and a job's answer is `Closeout.of(...)`. That is the same division
## `JobDesk` keeps, and for the same reason: a rule in two places drifts.
##
## Three things here are decisions rather than plumbing.
##
## * **A punch item belongs to a job the desk actually has.** A job we cannot find is refused by
##   name, the way a crew member who is not on the crew is: a list against a job nobody has is a list
##   nobody will ever walk.
## * **A date of substantial completion is stated again rather than edited.** A wrong date has to be
##   correctable, and moving it is not nothing - the warranty hangs off it - so a *change* needs a
##   reason and is kept in a history beside the date it replaced. The first statement needs no reason:
##   there is nothing to explain about saying when something happened.
## * **Stating the warranty again keeps its claims.** An office that mistyped the term fixes it by
##   stating it again, and the claims already answered against it are untouched: correcting a term is
##   not a new warranty, and a second record would make every claim ambiguous.
##
## ## What it does not hold: money
##
## Nothing here has an amount on it. Putting a deficiency right costs labour and material, and those
## are already recorded as labour and material against the job's cost codes; a total for rework kept
## here would be a second total for the same money, and the job cost report would be summing one of
## them. The retainage that a contract holds back is released from the billing page, on the day this
## desk records.

const ItemScript := preload("res://scripts/biz/punch_item.gd")
const WarrantyScript := preload("res://scripts/biz/warranty.gd")
const CloseoutScript := preload("res://scripts/biz/closeout.gd")

## The prefix a punch item's number is handed out under, beside PO- and CO-. A number is a thing an
## office keeps a register of, and two items sharing one is the failure numbering prevents.
const ITEM_PREFIX := "PL-"

## The desk the jobs come from. Set by `bind`, and a desk with none can state nothing: a punch item
## against a job nobody can look up is a punch item nobody will walk.
var job_desk: JobDesk = null
## Every punch item, every job's, oldest first.
var items: Array[PunchItem] = []
## One warranty per job, keyed by job id.
var warranties: Dictionary = {}
## The history of hand-over dates, keyed by job id: one entry per statement, oldest first, each
## `{at, by, why}`. The **current** date is the last of them, and the earlier ones are what says a
## date was moved and why.
var completions: Dictionary = {}


func bind(jobs: JobDesk) -> void:
	job_desk = jobs


# --- the punch list --------------------------------------------------------------------------


## Raise an item against a job. Refused for a job this desk does not have, and refused for an item
## that cannot be read - the place and the description are what the crew works from.
##
## The trade is the last argument because it is the only one that can be blank: an item with nobody
## named to put it right is our own crew's, which is a real answer, while an item with no place, no
## description, no date or nobody to ask is not an item at all.
func raise_item(job_id: String, where: String, what: String, by: String, at: String,
		who: String = "") -> Dictionary:
	var no_job: String = _job_problem(job_id)
	if not no_job.is_empty():
		return {"ok": false, "reason": no_job, "id": ""}
	var item: PunchItem = ItemScript.make(next_item_id(), job_id, at, where, what, by)
	if item == null:
		return {"ok": false, "reason": _item_refusal(where, what, by, at), "id": ""}
	item.who = who.strip_edges()
	items.append(item)
	return {"ok": true, "reason": "", "id": item.id}


func fix_item(item_id: String, at: String, note: String = "") -> Dictionary:
	var item: PunchItem = item(item_id)
	if item == null:
		return {"ok": false, "reason": "there is no item %s" % item_id}
	if not item.mark_fixed(at, note):
		return {"ok": false, "reason": _act_refusal(item, "fixed", at)}
	return {"ok": true, "reason": ""}


func accept_item(item_id: String, by: String, at: String) -> Dictionary:
	var item: PunchItem = item(item_id)
	if item == null:
		return {"ok": false, "reason": "there is no item %s" % item_id}
	if not item.mark_accepted(by, at):
		if item.is_fixed():
			return {"ok": false, "reason": _nobody_or_moment("checking", by, at)}
		return {"ok": false, "reason": "'%s' is %s, so there is nothing to check" % [item_id, item.state_name()]}
	return {"ok": true, "reason": ""}


func reject_item(item_id: String, by: String, at: String, why: String) -> Dictionary:
	var item: PunchItem = item(item_id)
	if item == null:
		return {"ok": false, "reason": "there is no item %s" % item_id}
	if not item.mark_rejected(by, at, why):
		if item.is_fixed():
			return {"ok": false, "reason": _nobody_or_reason("rejecting", by, why, at)}
		return {"ok": false, "reason": "'%s' is %s, so there is nothing to reject" % [item_id, item.state_name()]}
	return {"ok": true, "reason": ""}


## Take an item off the list: raised in error, or agreed with the client to be left as it is. It
## keeps its record, so the list still says it was there.
func withdraw_item(item_id: String, by: String, at: String, why: String) -> Dictionary:
	var item: PunchItem = item(item_id)
	if item == null:
		return {"ok": false, "reason": "there is no item %s" % item_id}
	if not item.mark_withdrawn(by, at, why):
		if item.is_closed() or item.is_withdrawn():
			return {"ok": false, "reason": "'%s' is %s, and it cannot be taken off again" % [item_id, item.state_name()]}
		return {"ok": false, "reason": _nobody_or_reason("withdrawing", by, why, at)}
	return {"ok": true, "reason": ""}


func item(item_id: String) -> PunchItem:
	for held: PunchItem in items:
		if held.id == item_id:
			return held
	return null


func items_for(job_id: String) -> Array[PunchItem]:
	var out: Array[PunchItem] = []
	for held: PunchItem in items:
		if held.job_id == job_id:
			out.append(held)
	return out


func item_rows(job_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for held: PunchItem in items_for(job_id):
		out.append(held.row())
	return out


## The number the next item gets: one past the highest ever handed out, never the count, so an item
## removed by hand cannot cause a second item to share its number.
func next_item_id() -> String:
	var highest := 0
	for held: PunchItem in items:
		var body: String = held.id
		if body.begins_with(ITEM_PREFIX):
			var tail: String = body.substr(ITEM_PREFIX.length())
			if tail.is_valid_int():
				highest = maxi(highest, tail.to_int())
	return "%s%d" % [ITEM_PREFIX, highest + 1]


# --- the hand-over date ----------------------------------------------------------------------


## State the day the garden was given to the client. The first statement needs no reason; a change of
## date does, because the warranty runs from it.
func state_completion(job_id: String, at: String, by: String, why: String = "") -> Dictionary:
	var no_job: String = _job_problem(job_id)
	if not no_job.is_empty():
		return {"ok": false, "reason": no_job}
	if by.strip_edges().is_empty():
		return {"ok": false, "reason": "a date of substantial completion needs somebody to state it"}
	if not RateScript.is_date(at):
		return {"ok": false, "reason": "'%s' is not a date this program writes" % at}
	var history: Array = completions.get(job_id, [])
	if not history.is_empty() and why.strip_edges().is_empty():
		return {"ok": false, "reason": "the date is already stated; moving it needs a reason"}
	var entry := {"at": at, "by": by.strip_edges(), "why": why.strip_edges()}
	var kept: Array = history.duplicate()
	kept.append(entry)
	completions[job_id] = kept
	return {"ok": true, "reason": ""}


## The date now in force, or "".
func completed_on(job_id: String) -> String:
	var history: Array = completions.get(job_id, [])
	if history.is_empty():
		return ""
	return String((history[history.size() - 1] as Dictionary).get("at", ""))


func completed_by(job_id: String) -> String:
	var history: Array = completions.get(job_id, [])
	if history.is_empty():
		return ""
	return String((history[history.size() - 1] as Dictionary).get("by", ""))


## Every statement of the date, oldest first: what says the date was moved, and why.
func completion_history(job_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Variant in completions.get(job_id, []):
		if entry is Dictionary:
			out.append(entry)
	return out


# --- the warranty -----------------------------------------------------------------------------


## State, or correct, a job's warranty. Refused for a job this desk does not have, for a term nobody
## can read, and for a job whose garden has not been handed over - a warranty starts at completion,
## so there is no such thing as one before it.
func state_warranty(job_id: String, parts: Array, months: int, starts_on: String,
		excludes: Array = []) -> Dictionary:
	var no_job: String = _job_problem(job_id)
	if not no_job.is_empty():
		return {"ok": false, "reason": no_job}
	if completed_on(job_id).strip_edges().is_empty():
		return {"ok": false, "reason": "the garden has not been handed over yet, so nothing has started"}
	var record: Warranty = warranty_for(job_id)
	if record == null:
		record = WarrantyScript.new(job_id)
		if not record.set_term(parts, months, starts_on):
			return {"ok": false, "reason": _term_refusal(parts, months, starts_on)}
		record.excludes = _lines(excludes)
		warranties[job_id] = record
		return {"ok": true, "reason": ""}
	if not record.set_term(parts, months, starts_on):
		return {"ok": false, "reason": _term_refusal(parts, months, starts_on)}
	record.excludes = _lines(excludes)
	return {"ok": true, "reason": ""}


func warranty_for(job_id: String) -> Warranty:
	var held: Variant = warranties.get(job_id, null)
	if held is Warranty:
		return held
	return null


func has_warranty(job_id: String) -> bool:
	return warranty_for(job_id) != null


## Report a claim against a job's warranty. Refused when there is no warranty to claim against: a
## claim nobody can judge is worse stored than refused.
func file_claim(job_id: String, at: String, what: String, by: String) -> Dictionary:
	var record: Warranty = warranty_for(job_id)
	if record == null:
		return {"ok": false, "reason": "%s has no warranty yet, so there is nothing to claim against" % _job_words(job_id), "id": ""}
	if not RateScript.is_date(at) or what.strip_edges().is_empty() or by.strip_edges().is_empty():
		return {"ok": false, "reason": _claim_refusal(at, what, by), "id": ""}
	var claim: WarrantyClaim = record.file_claim(at, what, by)
	if claim == null:
		return {"ok": false, "reason": "%s's warranty cannot be read, so a claim cannot be judged against it" % _job_words(job_id), "id": ""}
	return {"ok": true, "reason": "", "id": claim.id}


## Answer a claim: covered or not, with the reason either way.
func answer_claim(job_id: String, claim_id: String, by: String, at: String, covered: bool,
		why: String) -> Dictionary:
	var record: Warranty = warranty_for(job_id)
	if record == null or record.claim(claim_id) == null:
		return {"ok": false, "reason": "there is no claim %s against %s" % [claim_id, _job_words(job_id)]}
	if not record.answer_claim(claim_id, by, at, covered, why):
		if record.claim(claim_id).is_answered():
			return {"ok": false, "reason": "claim %s is already answered" % claim_id}
		return {"ok": false, "reason": _nobody_or_reason("answering", by, why, at)}
	return {"ok": true, "reason": ""}


## The work, on a claim that is covered.
func finish_claim(job_id: String, claim_id: String, at: String, note: String = "") -> Dictionary:
	var record: Warranty = warranty_for(job_id)
	if record == null or record.claim(claim_id) == null:
		return {"ok": false, "reason": "there is no claim %s against %s" % [claim_id, _job_words(job_id)]}
	if not record.finish_claim(claim_id, at, note):
		var claim: WarrantyClaim = record.claim(claim_id)
		if not claim.is_answered():
			return {"ok": false, "reason": "claim %s has not been answered yet" % claim_id}
		if not claim.covered:
			return {"ok": false, "reason": "claim %s is not covered, so there is nothing to do" % claim_id}
		return {"ok": false, "reason": "claim %s wants a date it was done on" % claim_id}
	return {"ok": true, "reason": ""}


func claim_rows(job_id: String) -> Array[Dictionary]:
	var record: Warranty = warranty_for(job_id)
	return [] as Array[Dictionary] if record == null else record.claim_rows()


# --- the answer a page asks for ---------------------------------------------------------------


## What one job's closeout is: the punch list, the hand-over date and the warranty, in one report.
## Null for a job this desk does not have - the page says which rather than showing an empty list.
func report(job_id: String, as_of: String = "") -> Closeout:
	var contracted: Job = _job(job_id)
	if contracted == null:
		return null
	return CloseoutScript.of(
		contracted, items, warranty_for(job_id), completed_on(job_id), as_of
	)


## The jobs this desk has anything to say about: a punch item, a hand-over date or a warranty.
func jobs_in_closeout() -> Array[String]:
	var out: Array[String] = []
	for held: PunchItem in items:
		if not out.has(held.job_id):
			out.append(held.job_id)
	for key: Variant in completions:
		if not out.has(String(key)):
			out.append(String(key))
	for key: Variant in warranties:
		if not out.has(String(key)):
			out.append(String(key))
	out.sort()
	return out


func outstanding_count() -> int:
	var total := 0
	for held: PunchItem in items:
		if held.is_outstanding():
			total += 1
	return total


func claims_needing_attention() -> int:
	var total := 0
	for key: Variant in warranties:
		var record: Warranty = warranty_for(String(key))
		if record != null:
			total += record.claims_needing_attention().size()
	return total


## The line the Jobs menu shows. Only what a person must not have to open a window to find: how many
## jobs are being closed out, how many items are outstanding, and whether a claim is waiting on
## somebody.
func describe() -> String:
	if items.is_empty() and warranties.is_empty() and completions.is_empty():
		return "nothing is being closed out"
	var jobs := jobs_in_closeout().size()
	var parts := PackedStringArray()
	parts.append("%d job%s in closeout" % [jobs, "" if jobs == 1 else "s"])
	if not items.is_empty():
		parts.append("%d item%s" % [items.size(), "" if items.size() == 1 else "s"])
	var outstanding := outstanding_count()
	if outstanding > 0:
		parts.append("%d outstanding" % outstanding)
	var claimed := claims_needing_attention()
	if claimed > 0:
		parts.append("%d claim%s wanting somebody" % [claimed, "" if claimed == 1 else "s"])
	return ", ".join(parts)


## Everything wrong with what the desk is holding, counted and named: a record that does not read,
## and an item or a warranty against a job this desk does not have.
func problems() -> Array[String]:
	var out: Array[String] = []
	for held: PunchItem in items:
		var wrong: String = held.problem()
		if not wrong.is_empty():
			out.append(wrong)
		elif _job(held.job_id) == null:
			out.append("item %s belongs to a job this desk does not have: %s" % [held.id, held.job_id])
	for id: String in jobs_in_closeout():
		var record: Warranty = warranty_for(id)
		if record == null:
			continue
		var bad: String = record.problem()
		if not bad.is_empty():
			out.append(bad)
	return out


# --- what the desk is, in a file ---------------------------------------------------------------


func to_dict() -> Dictionary:
	var held: Array[Dictionary] = []
	for record: PunchItem in items:
		held.append(record.to_dict())
	var stated := {}
	for key: Variant in warranties:
		var record: Warranty = warranty_for(String(key))
		if record != null:
			stated[String(key)] = record.to_dict()
	var dates := {}
	for key: Variant in completions:
		dates[String(key)] = completion_history(String(key))
	return {"items": held, "warranties": stated, "completions": dates}


static func from_dict(data: Dictionary) -> CloseoutDesk:
	var desk := CloseoutDeskScript.new()
	var held: Variant = data.get("items", [])
	if held is Array:
		for entry: Variant in held:
			if entry is Dictionary:
				desk.items.append(ItemScript.from_dict(entry))
	var stated: Variant = data.get("warranties", {})
	if stated is Dictionary:
		for key: Variant in stated:
			var body: Variant = stated[key]
			if body is Dictionary:
				desk.warranties[String(key)] = WarrantyScript.from_dict(body)
	var dates: Variant = data.get("completions", {})
	if dates is Dictionary:
		for key: Variant in dates:
			var body: Variant = dates[key]
			if body is Array:
				var history: Array = []
				for entry: Variant in body:
					if entry is Dictionary:
						history.append(entry)
				desk.completions[String(key)] = history
	return desk


# --- the words a refusal uses ------------------------------------------------------------------


func _job(job_id: String) -> Job:
	if job_desk == null:
		return null
	return job_desk.job(job_id)


## Why a job cannot be used, or "". A desk with no jobs at all says which, rather than accepting an
## item against anything.
func _job_problem(job_id: String) -> String:
	if job_id.strip_edges().is_empty():
		return "a punch item needs a job"
	if job_desk == null:
		return "there is no desk of jobs to put that against"
	if _job(job_id) == null:
		return "there is no job %s" % job_id
	return ""


## The job in words, for a refusal that has to name it: its label when there is one, its id when
## there is not, and - for a desk that has no jobs at all - the id it was given.
func _job_words(job_id: String) -> String:
	var contracted: Job = _job(job_id)
	if contracted != null:
		return job_desk.job_label(job_id)
	return "job %s" % job_id if not job_id.strip_edges().is_empty() else "that job"


func _item_refusal(where: String, what: String, by: String, at: String) -> String:
	if where.strip_edges().is_empty():
		return "an item has to say where it is; nobody can find a deficiency with no place"
	if what.strip_edges().is_empty():
		return "an item has to say what is wrong"
	if by.strip_edges().is_empty():
		return "an item has to say who raised it"
	return "'%s' is not a date this program writes" % at


func _claim_refusal(at: String, what: String, by: String) -> String:
	if what.strip_edges().is_empty():
		return "a claim has to say what failed"
	if by.strip_edges().is_empty():
		return "a claim has to say who reported it"
	return "'%s' is not a date this program writes" % at


func _term_refusal(parts: Array, months: int, starts_on: String) -> String:
	var wanted: Array[String] = WarrantyScript.canonical_parts(parts)
	if parts.is_empty():
		return "a warranty has to cover something"
	# A request with a part nobody covers in it names the four that can be covered, because a page
	# handing over a checkbox it built from somewhere else has to be told what the choice was.
	if wanted.size() != parts.size():
		return "a warranty can cover %s, and something else was asked for" % WarrantyScript.and_join(
			WarrantyScript.PARTS
		)
	if months < 1 or months > WarrantyScript.MAX_MONTHS:
		return "a warranty runs for between 1 and %d months, and %d was asked for" % [
			WarrantyScript.MAX_MONTHS, months,
		]
	return "'%s' is not a date this program writes" % starts_on


## The one thing wrong with an act that a record has already refused, in the record's own terms: the
## state it is in, or the person or the moment it is missing.
func _act_refusal(item: PunchItem, doing: String, at: String) -> String:
	if not item.is_open():
		return "'%s' is %s, so it cannot be %s" % [item.id, item.state_name(), doing]
	return "'%s' is not a date this program writes" % at


func _nobody_or_moment(doing: String, by: String, at: String) -> String:
	if by.strip_edges().is_empty():
		return "%s an item takes somebody's name" % doing
	return "'%s' is not a date this program writes" % at


func _nobody_or_reason(doing: String, by: String, why: String, at: String) -> String:
	if by.strip_edges().is_empty():
		return "%s takes somebody's name" % doing
	if why.strip_edges().is_empty():
		return "%s takes a reason" % doing
	return "'%s' is not a date this program writes" % at


## A list of sentences with the blank ones dropped: a page may hand over a field somebody left empty.
static func _lines(values: Array) -> Array[String]:
	var out: Array[String] = []
	for value: Variant in values:
		var body := String(value).strip_edges()
		if not body.is_empty():
			out.append(body)
	return out


const RateScript := preload("res://scripts/biz/rate.gd")
const CloseoutDeskScript := preload("res://scripts/biz/closeout_desk.gd")