class_name Schedule
extends RefCounted
## The schedule board: crews down the side, days across the top, jobs as blocks (spec §7.4).
##
## It **places** and it **reports conflicts**; it never rearranges anything. "A scheduler that
## rearranges a crew's day without being asked is a scheduler nobody trusts twice", so every conflict
## is a row in a list and a highlight on a block, and the office is the one who moves things.
##
## A block is `{job, crew, date, start_minute, end_minute, note}` - minutes from midnight, so a block
## needs no date arithmetic to compare, and two blocks overlap iff their windows do.

## A crew member's record, when the board has it: needed to say a person is booked onto a day they
## are not available for. Availability is the crew member's, never the schedule's (§7.1).
const CrewScript := preload("res://scripts/biz/crew.gd")

const CREW_DOUBLE_BOOKED := &"CREW_DOUBLE_BOOKED"
const JOB_TWO_CREWS := &"JOB_TWO_CREWS"
const OUTSIDE_WINDOW := &"OUTSIDE_WINDOW"
const UNAVAILABLE := &"UNAVAILABLE"

const CONFLICT_NAMES := {
	"CREW_DOUBLE_BOOKED": "the same crew in two windows at once",
	"JOB_TWO_CREWS": "the same job with two crews on one day",
	"OUTSIDE_WINDOW": "a block outside the day",
	"UNAVAILABLE": "a crew member on a day they are not available",
}

## The blocks, in the order they were placed. A block's index is its identity until somebody is given
## a real one - the board only ever moves a thing it can point at.
var entries: Array[Dictionary] = []
## Crew member id (String) to `CrewMember`, or empty. Used for the availability conflict only.
var crews: Dictionary = {}

const MINUTES_PER_DAY := 1440


# --- placing ---------------------------------------------------------------------------------


## Place a block. Refused when it ends before it starts, or sits outside the day: a block nobody can
## point at is not a block, and an end equal to a start is zero work, not a booking.
##
## Returns `{ok, reason, index}`.
func place(job: String, crew: StringName, date: String, start_minute: int, end_minute: int,
		note: String = "") -> Dictionary:
	if date.strip_edges().is_empty():
		return {"ok": false, "reason": "a block needs a date", "index": -1}
	if end_minute <= start_minute:
		return {"ok": false, "reason": "a block that ends before it starts is no block", "index": -1}
	if start_minute < 0 or end_minute > MINUTES_PER_DAY:
		return {"ok": false, "reason": "a block outside the day is not a booking", "index": -1}
	entries.append({
		"job": job, "crew": String(crew), "date": date,
		"start_minute": start_minute, "end_minute": end_minute, "note": note,
	})
	return {"ok": true, "reason": "", "index": entries.size() - 1}


## Move a block to a new window on the same day. Refused for the same reasons a placement is.
func move(index: int, start_minute: int, end_minute: int) -> bool:
	if index < 0 or index >= entries.size():
		return false
	if end_minute <= start_minute or start_minute < 0 or end_minute > MINUTES_PER_DAY:
		return false
	entries[index]["start_minute"] = start_minute
	entries[index]["end_minute"] = end_minute
	return true


## Move a block to a different day as well. Refused for the same reasons, plus a day with no date.
func move_to(index: int, date: String, start_minute: int, end_minute: int) -> bool:
	if date.strip_edges().is_empty() or index < 0 or index >= entries.size():
		return false
	if end_minute <= start_minute or start_minute < 0 or end_minute > MINUTES_PER_DAY:
		return false
	entries[index]["date"] = date
	entries[index]["start_minute"] = start_minute
	entries[index]["end_minute"] = end_minute
	return true


func remove(index: int) -> bool:
	if index < 0 or index >= entries.size():
		return false
	entries.remove_at(index)
	return true


func count() -> int:
	return entries.size()


func on_date(date: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in entries:
		if String(entry["date"]) == date:
			out.append(entry)
	return out


func for_crew(crew: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in entries:
		if String(entry["crew"]) == String(crew):
			out.append(entry)
	return out


func dates() -> Array[String]:
	var out: Array[String] = []
	for entry in entries:
		var date := String(entry["date"])
		if not out.has(date):
			out.append(date)
	out.sort()
	return out


func crew_ids() -> Array[String]:
	var out: Array[String] = []
	for entry in entries:
		var crew := String(entry["crew"])
		if not out.has(crew):
			out.append(crew)
	out.sort()
	return out


## Add a crew member's record so availability can be checked. Optional: without it, the schedule
## simply has no availability to report against.
func know_crew(member: CrewScript) -> void:
	if member != null and not String(member.id).is_empty():
		crews[String(member.id)] = member


# --- the conflicts, as a list and never an automatic move --------------------------------------


## Every conflict on the board, as rows `{kind, name, date, crew, job, detail}`. Sorted date, then
## kind, then crew, so the same board always reads the same way.
func conflicts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for date in dates():
		var day := on_date(date)
		out.append_array(_double_bookings(date, day))
		out.append_array(_two_crews_on_one_job(date, day))
		out.append_array(_unavailable_crews(date, day))
	out.sort_custom(_by_date_kind_crew)
	return out


func conflict_count() -> int:
	return conflicts().size()


func is_clear() -> bool:
	return conflicts().is_empty()


func _double_bookings(date: String, day: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var crews_seen: Array[String] = []
	for entry in day:
		var crew := String(entry["crew"])
		if not crews_seen.has(crew):
			crews_seen.append(crew)
	for crew in crews_seen:
		var blocks: Array[Dictionary] = []
		for entry in day:
			if String(entry["crew"]) == crew:
				blocks.append(entry)
		for i in blocks.size():
			for j in range(i + 1, blocks.size()):
				if _overlap(blocks[i], blocks[j]):
					out.append(_row(CREW_DOUBLE_BOOKED, date, crew,
						"%s is booked in two windows at once (%s and %s)"
						% [crew, _window(blocks[i]), _window(blocks[j])]))
	return out


func _two_crews_on_one_job(date: String, day: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var jobs_seen: Array[String] = []
	for entry in day:
		var job := String(entry["job"])
		if not jobs_seen.has(job):
			jobs_seen.append(job)
	for job in jobs_seen:
		var crews: Array[String] = []
		for entry in day:
			if String(entry["job"]) == job:
				var crew := String(entry["crew"])
				if not crews.has(crew):
					crews.append(crew)
		if crews.size() > 1:
			out.append(_row(JOB_TWO_CREWS, date, crews[0],
				"%s has two crews on it (%s)" % [job, ", ".join(crews)]))
	return out


func _unavailable_crews(date: String, day: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in day:
		var crew := String(entry["crew"])
		if not crews.has(crew):
			continue
		var member: CrewScript = crews[crew]
		var why := member.unavailability(date)
		if not why.is_empty():
			out.append(_row(UNAVAILABLE, date, crew, why))
	return out


static func _overlap(a: Dictionary, b: Dictionary) -> bool:
	return int(a["start_minute"]) < int(b["end_minute"]) \
		and int(b["start_minute"]) < int(a["end_minute"])


static func _window(entry: Dictionary) -> String:
	return "%d-%d" % [int(entry["start_minute"]), int(entry["end_minute"])]


static func _row(kind: StringName, date: String, crew: String, detail: String) -> Dictionary:
	return {
		"kind": String(kind),
		"name": String(CONFLICT_NAMES.get(String(kind), String(kind))),
		"date": date,
		"crew": crew,
		"detail": detail,
	}


static func _by_date_kind_crew(a: Dictionary, b: Dictionary) -> bool:
	if String(a["date"]) != String(b["date"]):
		return String(a["date"]) < String(b["date"])
	if String(a["kind"]) != String(b["kind"]):
		return String(a["kind"]) < String(b["kind"])
	return String(a["crew"]) < String(b["crew"])


# --- the file ---------------------------------------------------------------------------------


func to_dict() -> Dictionary:
	var list: Array = []
	for entry in entries:
		list.append({
			"job": String(entry["job"]),
			"crew": String(entry["crew"]),
			"date": String(entry["date"]),
			"start_minute": int(entry["start_minute"]),
			"end_minute": int(entry["end_minute"]),
			"note": String(entry.get("note", "")),
		})
	return {"entries": list}


static func from_dict(data: Dictionary) -> Schedule:
	var schedule: Schedule = ScheduleScript.new()
	var list = data.get("entries", [])
	if list is Array:
		for entry in (list as Array):
			if entry is Dictionary:
				var placed: Dictionary = schedule.place(
					String(entry.get("job", "")), StringName(entry.get("crew", "")),
					String(entry.get("date", "")), int(entry.get("start_minute", 0)),
					int(entry.get("end_minute", 0)), String(entry.get("note", "")))
				# A block that will not place is a damaged record, and it is dropped rather than
				# stored as something the board cannot point at.
				if not placed["ok"]:
					continue
	return schedule


const ScheduleScript := preload("res://scripts/biz/schedule.gd")