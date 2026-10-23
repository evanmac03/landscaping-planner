class_name Warranty
extends RefCounted
## What a job's work is guaranteed for, and every claim made against it (phase 12).
##
## A landscape warranty is two promises and a calendar. The promises are **plant material** - a shrub
## that dies in its first season is replaced - and **workmanship** - a wall that settles, a patio that
## drains the wrong way, a joint that opens. The calendar starts at **substantial completion**, which
## is the moment the client is given the garden, and it is the same moment the punch list ends at. So
## a warranty is a set of covered parts, a number of months, and a start date.
##
## ## Two decisions that are worth stating
##
## * **The term ends on its anniversary.** A warranty of twelve months from 2026-06-30 covers up to
##   and including 2027-06-30, and a claim reported that day is the last one it covers. The
##   alternative - the term runs out the day before the anniversary - is defensible and it was not
##   chosen, because "covered until June 30th next year" is the sentence a contract writes. Which one
##   this program means is written down here rather than left to be re-derived from a comparison.
## * **A month that has no such day clamps.** Six months after 2026-08-31 is 2027-02-28: February has
##   no 31st, and the term ends on the month's last day rather than being refused or running a day
##   into March. A warranty that expired a day early would refuse a claim it should have paid, which
##   is the failure a client remembers.
##
## ## Exclusions are stated, not inferred
##
## `excludes` is a list of sentences - "damage by others", "the client's own watering during
## establishment" - and it is deliberately free text. It is the part of a warranty that a claim is
## argued about, and a fixed list of codes would be a lie about the variety of the arguing.
##
## ## The claims live here
##
## A warranty owns its claims, the way a billing schedule owns its steps: a claim has no meaning
## apart from the term it is made against. `answer_claim` and `finish_claim` are the two acts, and
## both go through the claim's own records rather than setting a state here.

const RateScript := preload("res://scripts/biz/rate.gd")
const ClaimScript := preload("res://scripts/biz/warranty_claim.gd")

## What a warranty can cover. Plain words rather than codes, for the reason the wash table and the
## solid table are keyed by the project's own layer names: the words in the file are the words on the
## contract.
const PARTS: Array[String] = ["plant material", "workmanship", "irrigation", "lighting"]

## What an exclusion or a part is called when it is empty, so a page has something to show.
const NOTHING_STATED := "nothing stated"

## The longest term this accepts, in months. Ten years is longer than any landscape warranty and
## longer than a mis-typed number should be taken for: a term of 1200 months is a typo, not a promise.
const MAX_MONTHS := 120

## The year a claim's number is a run of, so the ids in a file are readable next to each other.
const CLAIM_PREFIX := "WC-"

var job_id: String = ""
## The parts covered. At least one, and only from `PARTS`.
var parts: Array[String] = []
## How long the term runs, in months. Required, and inside `MAX_MONTHS`.
var months: int = 0
## Where it starts: the date of substantial completion, as a date this program writes.
var starts_on: String = ""
## What it does not cover, one sentence each.
var excludes: Array[String] = []
## Every claim against it, oldest first.
var claims: Array[WarrantyClaim] = []
var note: String = ""


func _init(held_job: String = "") -> void:
	job_id = held_job


## A warranty stated in one call, refused when it cannot be read. The parts are cleaned through
## `set_term`, so a page can hand over what its checkboxes say and be told no by name.
static func make(held_job: String, covered: Array, how_many_months: int, from: String) -> Warranty:
	var record := WarrantyScript.new(held_job)
	if not record.set_term(covered, how_many_months, from):
		return null
	return record


# --- the terms -------------------------------------------------------------------------------


## Whether a word is a part this program covers. Case and spacing do not matter: a page may hand over
## what it typed.
static func is_part(candidate: String) -> bool:
	return PARTS.has(candidate.strip_edges().to_lower())


## The parts, in the table's own order whatever order they were stated in, so two warranties that
## cover the same things say so the same way.
static func canonical_parts(covered: Array) -> Array[String]:
	var out: Array[String] = []
	for part: String in PARTS:
		for wanted: Variant in covered:
			if String(wanted).strip_edges().to_lower() == part and not out.has(part):
				out.append(part)
	return out


## State the term. Refused for no parts, for a part nobody covers, for a term outside `MAX_MONTHS`,
## and for a start that is not a date: each of the four would make the warranty unreadable, and an
## unreadable warranty refuses good claims.
func set_term(covered: Array, how_many_months: int, from: String) -> bool:
	var wanted: Array[String] = canonical_parts(covered)
	if wanted.is_empty() or wanted.size() != covered.size():
		return false
	if how_many_months < 1 or how_many_months > MAX_MONTHS:
		return false
	if not RateScript.is_date(from):
		return false
	parts = wanted
	months = how_many_months
	starts_on = from
	return true


func covers(part: String) -> bool:
	return parts.has(part.strip_edges().to_lower())


## The day the term runs out: the anniversary of the start, with the day clamped when the target
## month has no such day. "" when either the start or the term is not stated.
func ends_on() -> String:
	return months_after(starts_on, months)


## Whether a date is inside the term. Dates this program writes are `YYYY-MM-DD`, so comparing them
## as strings is comparing them as dates - which is why `Rate.is_date` insists on the shape and on
## the zero padding, and why nothing here parses a date to compare it.
func covers_on(date: String) -> bool:
	if not RateScript.is_date(date) or not RateScript.is_date(starts_on) or months < 1:
		return false
	var last: String = ends_on()
	if last.is_empty():
		return false
	return date >= starts_on and date <= last


## A stated number of months after a date, with the day clamped to the month's last day. Refused for
## a date that is not a date or a term that is not a term; "" then.
##
## The calendar lives in one place: the day is clamped by **asking the one validator** whether the
## candidate exists, so the month lengths are not written down a second time here.
static func months_after(date: String, how_many_months: int) -> String:
	if not RateScript.is_date(date) or how_many_months < 1:
		return ""
	var year: int = date.substr(0, 4).to_int()
	var month: int = date.substr(5, 2).to_int()
	var day: int = date.substr(8, 2).to_int()
	var counted: int = year * 12 + (month - 1) + how_many_months
	# Whole years and the leftover month are exact here: counted is never negative (year and
	# how_many_months are both >= 1), so the truncating division is the intended one.
	@warning_ignore("integer_division")
	var target_year: int = counted / 12
	var target_month: int = counted % 12 + 1
	while day > 0:
		var candidate := "%04d-%02d-%02d" % [target_year, target_month, day]
		if RateScript.is_date(candidate):
			return candidate
		day -= 1
	return ""


# --- claiming --------------------------------------------------------------------------------


## A claim reported against this warranty. Refused for a report that is not readable, and refused
## when the term is not sound: a claim against a warranty nobody can read is a claim that cannot be
## judged, and storing it would hide that behind a row on a page.
func file_claim(at: String, about: String, by: String) -> WarrantyClaim:
	if not is_sound():
		return null
	var filed: WarrantyClaim = ClaimScript.make(next_claim_id(), job_id, at, about, by)
	if filed == null:
		return null
	claims.append(filed)
	return filed


func claim(claim_id: String) -> WarrantyClaim:
	for held: WarrantyClaim in claims:
		if held.id == claim_id:
			return held
	return null


## The number the next claim gets: one past the highest ever handed out, never the count, so a claim
## that was dropped by hand cannot cause a second claim to share its number.
func next_claim_id() -> String:
	var highest := 0
	for held: WarrantyClaim in claims:
		var body: String = held.id
		if body.begins_with(CLAIM_PREFIX):
			var tail: String = body.substr(CLAIM_PREFIX.length())
			if tail.is_valid_int():
				highest = maxi(highest, tail.to_int())
	return "%s%d" % [CLAIM_PREFIX, highest + 1]


## Answer a claim: covered, or not covered, with the reason either way.
func answer_claim(claim_id: String, by: String, at: String, is_covered: bool, why: String) -> bool:
	var held: WarrantyClaim = claim(claim_id)
	if held == null:
		return false
	return held.mark_answered(by, at, is_covered, why)


## The work, on a claim that is covered.
func finish_claim(claim_id: String, at: String, what_was_done: String = "") -> bool:
	var held: WarrantyClaim = claim(claim_id)
	if held == null:
		return false
	return held.mark_done(at, what_was_done)


func claim_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for held: WarrantyClaim in claims:
		out.append(held.row())
	return out


## Claims nobody has answered, or has answered and not put right.
func claims_needing_attention() -> Array[WarrantyClaim]:
	var out: Array[WarrantyClaim] = []
	for held: WarrantyClaim in claims:
		if held.needs_attention():
			out.append(held)
	return out


# --- describing it ---------------------------------------------------------------------------


## The parts and the term, as the sentence a contract writes.
func terms_text() -> String:
	if parts.is_empty() or months < 1 or not RateScript.is_date(starts_on):
		return NOTHING_STATED
	return "%s for %d month%s from %s, so until %s" % [
		and_join(parts), months, "" if months == 1 else "s", starts_on, ends_on(),
	]


## The exclusions, or the fact that none are stated. A warranty with no exclusions is a warranty
## that covers everything it names, and saying so is more use than an empty list.
##
## An exclusion that says nothing - a stray blank line in a file - is not shown, and is not a fault:
## it is noise in a list of sentences, and a line reading "not covering damage by others; " would be
## the fault. Everything else on this record is reported as it was read, because a file is not an
## editor; this one line is worded, so it skips what a person would not write.
func excludes_text() -> String:
	var stated: Array[String] = []
	for line: String in excludes:
		var body := line.strip_edges()
		if not body.is_empty():
			stated.append(body)
	if stated.is_empty():
		return NOTHING_STATED
	return "; ".join(PackedStringArray(stated))


func describe() -> String:
	if not is_sound():
		return problem()
	var words := terms_text()
	if not excludes.is_empty():
		words = "%s, not covering %s" % [words, excludes_text()]
	if claims.is_empty():
		return "%s, with no claims against it" % words
	var want: int = claims_needing_attention().size()
	if want == 0:
		return "%s, with %d claim%s settled" % [words, claims.size(), "" if claims.size() == 1 else "s"]
	return "%s, with %d of %d claim%s still wanting somebody" % [
		words, want, claims.size(), "" if claims.size() == 1 else "s",
	]


## A list in words: "a", "a and b", "a, b and c". One place, so a terms line and an exclusions line
## read the same way.
static func and_join(items: Array) -> String:
	var words: Array[String] = []
	for item: Variant in items:
		var body := String(item).strip_edges()
		if not body.is_empty():
			words.append(body)
	if words.size() <= 1:
		return words[0] if words.size() == 1 else ""
	return "%s and %s" % [", ".join(PackedStringArray(words.slice(0, words.size() - 1))), words[-1]]


# --- soundness -------------------------------------------------------------------------------


func problem() -> String:
	if job_id.strip_edges().is_empty():
		return "a warranty that belongs to no job"
	if parts.is_empty():
		return "the warranty for '%s' covers nothing" % job_id
	for part: String in parts:
		if not PARTS.has(part):
			return "the warranty for '%s' covers '%s', which is not a thing it can cover" % [job_id, part]
	if months < 1 or months > MAX_MONTHS:
		return "the warranty for '%s' runs for %d month(s)" % [job_id, months]
	if not RateScript.is_date(starts_on):
		return "the warranty for '%s' starts on a date that is not a date: '%s'" % [job_id, starts_on]
	for held: WarrantyClaim in claims:
		var wrong: String = held.problem()
		if not wrong.is_empty():
			return wrong
	return ""


func is_sound() -> bool:
	return problem().is_empty()


# --- persistence -----------------------------------------------------------------------------


func copy() -> Warranty:
	return from_dict(to_dict())


func to_dict() -> Dictionary:
	var held: Array[Dictionary] = []
	for claim_record: WarrantyClaim in claims:
		held.append(claim_record.to_dict())
	return {
		"job_id": job_id,
		"parts": parts.duplicate(),
		"months": months,
		"starts_on": starts_on,
		"excludes": excludes.duplicate(),
		"claims": held,
		"note": note,
	}


static func from_dict(data: Dictionary) -> Warranty:
	var record: Warranty = WarrantyScript.new(String(data.get("job_id", "")))
	var held: Variant = data.get("parts", [])
	if held is Array:
		for part: Variant in held:
			record.parts.append(String(part))
	record.months = int(data.get("months", 0))
	record.starts_on = String(data.get("starts_on", ""))
	var left_out: Variant = data.get("excludes", [])
	if left_out is Array:
		for line: Variant in left_out:
			record.excludes.append(String(line))
	var claimed: Variant = data.get("claims", [])
	if claimed is Array:
		for entry: Variant in claimed:
			if entry is Dictionary:
				record.claims.append(ClaimScript.from_dict(entry))
	record.note = String(data.get("note", ""))
	return record


const WarrantyScript := preload("res://scripts/biz/warranty.gd")