class_name Closeout
extends RefCounted
## The end of a job: the punch list, the date of substantial completion, and the warranty (phase 12).
##
## Every phase before this one is about the job being *built*: what it was sold for, what it was
## ordered, what it has cost, what has been billed, what has been handed to the ledger. This is the
## job being **finished** - the walk at the end, the list it produces, the day the client is given
## the garden, and the promise that starts on that day.
##
## It is a report and not an engine, for the same reason `JobCost` is: the arithmetic is in the
## records (`PunchItem.state()`, `Warranty.ends_on()`, `WarrantyClaim.is_done()`) and this class only
## gathers them and answers in words. A report that recomputed a state would be a second place for
## the rule to live.
##
## ## What is outstanding, and what is only worth naming
##
## `problems()` lists both, because a page with a "what wants looking at" list is the page this
## project already has - and because the difference matters to a person. An **outstanding item**
## stands between the job and being finished; an **unanswered claim** does not, and can arrive a year
## after everybody has gone home. The wording says which is which.
##
## ## The date-dependent line
##
## Whether the warranty is still running is a question about **today**, so the moment is an argument
## and never read off a clock. A report asked for a date that is not a date answers with no
## date-dependent sentence at all rather than with a guess - the rule the analytics report follows.

const JobScript := preload("res://scripts/biz/job.gd")
const ItemScript := preload("res://scripts/biz/punch_item.gd")
const WarrantyScript := preload("res://scripts/biz/warranty.gd")
const ClaimScript := preload("res://scripts/biz/warranty_claim.gd")
const RateScript := preload("res://scripts/biz/rate.gd")

var job_reference: Job = null
var job_id: String = ""
var label: String = ""
## The date the client was given the garden, or "" while nobody has stated one. Everything about the
## warranty hangs off this, which is why the list reports its absence first.
var completed_on: String = ""
var completed_by: String = ""
## One row per punch item, in the order the list was made.
var rows: Array[Dictionary] = []
var warranty: Warranty = null
## The moment the report is being read at, for the one line that depends on it.
var as_of: String = ""


## The report for one job: its punch items, its warranty, and the day it was handed over.
##
## `items` is handed over rather than filtered here, so the desk's list stays the one place the
## records live; anything in it that belongs to another job is left out and **counted**, because a
## silently dropped punch item is exactly the failure this list exists to prevent.
static func of(contracted: Job, items: Array, terms: Warranty, handed_over_on: String = "",
		read_at: String = "") -> Closeout:
	var report := CloseoutScript.new()
	report.job_reference = contracted
	if contracted != null:
		report.job_id = contracted.id
		report.label = contracted.name if not contracted.name.strip_edges().is_empty() else contracted.id
	report.completed_on = handed_over_on
	report.warranty = terms
	report.as_of = read_at if RateScript.is_date(read_at) else ""
	for entry: Variant in items:
		if not entry is ItemScript:
			continue
		var item: PunchItem = entry
		if contracted != null and item.job_id != contracted.id:
			continue
		report.rows.append(item.row())
	return report


func count() -> int:
	return rows.size()


## How many items are in one state. Counted off the rows, which were counted off the records.
func count_in(held_state: StringName) -> int:
	var total := 0
	for held: Dictionary in rows:
		if StringName(held.get("state", &"")) == held_state:
			total += 1
	return total


func counts() -> Dictionary:
	return {
		"open": count_in(ItemScript.OPEN),
		"fixed": count_in(ItemScript.FIXED),
		"closed": count_in(ItemScript.CLOSED),
		"withdrawn": count_in(ItemScript.WITHDRAWN),
		"total": count(),
	}


## Items still standing between this job and being finished: open ones, and fixed ones nobody has
## checked. The second kind is the one an office forgets, which is why the two are counted apart.
func outstanding_count() -> int:
	return count_in(ItemScript.OPEN) + count_in(ItemScript.FIXED)


## Whether the job is finished: a date of substantial completion, and nothing outstanding. An empty
## punch list with no completion date is not a finished job - it is a job nobody has walked.
func is_finished() -> bool:
	return not completed_on.strip_edges().is_empty() and outstanding_count() == 0


## Whether the warranty is running at the moment the report is being read. False when there is no
## warranty, when nobody has stated the moment, or when the term is not sound.
func is_warranty_running() -> bool:
	if warranty == null or as_of.is_empty():
		return false
	return warranty.covers_on(as_of)


## The claims reported on a date the term does not cover. Naming these is worth the few lines: a
## claim out of term is a conversation with a client about money, and it is much easier to have early.
func claims_out_of_term() -> Array[WarrantyClaim]:
	var out: Array[WarrantyClaim] = []
	if warranty == null:
		return out
	for held: WarrantyClaim in warranty.claims:
		if not warranty.covers_on(held.reported_at):
			out.append(held)
	return out


# --- saying what is there --------------------------------------------------------------------


## The punch list in one line: how much of it is done, and what is still waiting.
func punch_text() -> String:
	var held: Dictionary = counts()
	if count() == 0:
		return "nothing on the punch list"
	if outstanding_count() == 0:
		return "the punch list is done: %d item%s closed%s" % [
			held["total"], "" if int(held["total"]) == 1 else "s",
			" (%d withdrawn)" % int(held["withdrawn"]) if int(held["withdrawn"]) > 0 else "",
		]
	var parts := PackedStringArray()
	parts.append("%d of %d item%s closed" % [
		int(held["closed"]) + int(held["withdrawn"]),
		int(held["total"]),
		"" if int(held["total"]) == 1 else "s",
	])
	if int(held["open"]) > 0:
		parts.append("%d still to be put right" % int(held["open"]))
	if int(held["fixed"]) > 0:
		parts.append("%d fixed and waiting to be checked" % int(held["fixed"]))
	return "the punch list: %s" % ", ".join(parts)


## The day the garden was handed over, or what is missing.
func completion_text() -> String:
	if completed_on.strip_edges().is_empty():
		return "the date of substantial completion has not been stated"
	if completed_by.strip_edges().is_empty():
		return "the garden was handed over on %s" % completed_on
	return "the garden was handed over on %s, stated by %s" % [completed_on, completed_by]


## The warranty in one line, including - when the report knows the moment - whether it is still
## running. That sentence is the answer to the question a claim starts with.
func warranty_text() -> String:
	if warranty == null:
		return "no warranty has been stated for this job"
	var words: String = warranty.describe()
	if as_of.is_empty():
		return words
	if is_warranty_running():
		return "%s, running on %s" % [words, as_of]
	return "%s, and it had run out by %s" % [words, as_of]


## One line for a menu or a status line. The punch list leads, because it is the thing that stands
## between the job and being finished, and the warranty closes it - when there is one.
func describe() -> String:
	var parts := PackedStringArray()
	parts.append(punch_text())
	if warranty != null:
		var want: int = warranty.claims_needing_attention().size()
		parts.append(
			"%d claim%s settled" % [warranty.claims.size(), "" if warranty.claims.size() == 1 else "s"]
			if want == 0
			else "%d claim%s wanting somebody" % [want, "" if want == 1 else "s"]
		)
	return "%s (%s)" % [parts[0], ", ".join(parts.slice(1))]


## Everything standing in the way of finishing the job, and everything worth naming that is not.
##
## A finished job with a claim against it is finished; the claim is still there to be answered. The
## two are on one list because they are both read by the same person on the same morning.
func problems() -> Array[String]:
	var out: Array[String] = []
	if completed_on.strip_edges().is_empty():
		out.append("the date of substantial completion has not been stated")
	var held: Dictionary = counts()
	if int(held["open"]) > 0:
		out.append("%d item%s still to be put right" % [
			int(held["open"]), "" if int(held["open"]) == 1 else "s",
		])
	if int(held["fixed"]) > 0:
		out.append("%d item%s fixed and waiting to be checked" % [
			int(held["fixed"]), "" if int(held["fixed"]) == 1 else "s",
		])
	if warranty == null:
		out.append("no warranty has been stated for this job")
		return out
	var late: Array[WarrantyClaim] = claims_out_of_term()
	if not late.is_empty():
		out.append("%d claim%s reported outside the term, which ended on %s" % [
			late.size(), "" if late.size() == 1 else "s", warranty.ends_on(),
		])
	for held_claim: WarrantyClaim in warranty.claims_needing_attention():
		out.append("claim %s: %s" % [held_claim.id, held_claim.state_name()])
	return out


## One line per punch item, then one per claim - the two lists a page draws, in the order they are
## worked through. Written here so the page holds no wording of its own.
func text_lines() -> Array[String]:
	var lines: Array[String] = []
	lines.append(completion_text())
	lines.append(punch_text())
	for held: Dictionary in rows:
		lines.append(String(held.get("text", "")))
	lines.append(warranty_text())
	if warranty != null:
		for claim_row: Dictionary in warranty.claim_rows():
			lines.append(String(claim_row.get("text", "")))
	for words: String in problems():
		lines.append("wants looking at: " + words)
	return lines


const CloseoutScript := preload("res://scripts/biz/closeout.gd")