class_name JobDesk
extends RefCounted
## The jobs and the crews and their days, gathered into one thing the interface can hold (spec §7).
##
## Phase 5's five models - the job, the crew member, the schedule board, the route and the time entry -
## are pure: a job is produced *from* an estimate, a route is produced *from* a home and a list of
## stops, and none of them knows that a screen exists. This class is the join, and like `EstimateDesk`
## it is deliberately thin: it holds them, runs the hand-offs they already define, and answers the
## questions a panel asks in words.
##
## It is **not** a sixth engine and it holds no arithmetic of its own. What a job's labour comes to is
## `TimeEntry.labour` summed by `Money`; where a crew drives is `Route.plan`; what clashes is
## `Schedule.conflicts`. A desk that recomputed any of those would be a second place for the rule to
## live, and the two would drift.
##
## ## Two things it does decide
##
## * **A block goes in two places at once.** Booking a crew onto a job puts the block on the schedule
##   board *and* on the job's own `schedule`, because the job file has to say when it is being built
##   even when the board is not open. They are written from one call, so they cannot disagree.
## * **A place is stated, never guessed.** A route is computed from where a job is, and a job whose
##   place nobody has stated is **refused by name** rather than run from the drawing's origin: a crew
##   sent to (0, 0) is exactly the failure routing exists to prevent.

const JobScript := preload("res://scripts/biz/job.gd")
const CrewScript := preload("res://scripts/biz/crew.gd")
const ScheduleScript := preload("res://scripts/biz/schedule.gd")
const RouteScript := preload("res://scripts/biz/route.gd")
const EntryScript := preload("res://scripts/biz/time_entry.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")

const DEFAULT_CURRENCY := &"CAD"
## The hour a crew's day begins when nobody has said otherwise: 8:00, as minutes from midnight.
const DEFAULT_DAY_START := 480

var currency: StringName = DEFAULT_CURRENCY
## The people who do the work. A crew member is not a user account (§7.1).
var crews: Array[CrewMember] = []
var jobs: Array[Job] = []
## The board: crews down the side, days across the top, jobs as blocks.
var schedule: Schedule = null
## What has been logged, approved or not. Only an approved entry becomes cost (§7.3).
var time_entries: Array[TimeEntry] = []
## Where each job is, in the drawing's model metres, keyed by job id. Stated, not guessed.
var job_places: Dictionary = {}


func _init() -> void:
	schedule = ScheduleScript.new()


# --- the people ------------------------------------------------------------------------------


## Take a person onto the crew. Refused for nobody, for a record with no id (a person nobody can
## name is a damaged record, not a person) and for an id already on the crew.
func add_crew(member: CrewMember) -> bool:
	if member == null or String(member.id).is_empty():
		return false
	if crew(member.id) != null:
		return false
	crews.append(member)
	# The board needs the person's record and not only their id: a block on a day somebody is on
	# vacation is a conflict, and availability belongs to the crew member (§7.1).
	schedule.know_crew(member)
	return true


func crew(member_id: StringName) -> CrewMember:
	for held in crews:
		if held.id == member_id:
			return held
	return null


func crew_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for held in crews:
		out.append(held.id)
	return out


## "Ada Lovelace (Foreman)" - what a dropdown and a block both call a person.
func crew_names() -> Array[String]:
	var out: Array[String] = []
	for held in crews:
		out.append(crew_label(held.id))
	return out


## One person's name and role, or their id when the desk has never heard of them: a label that
## vanished would be a row a person cannot find.
func crew_label(member_id: StringName) -> String:
	var held: CrewMember = crew(member_id)
	if held == null:
		return String(member_id)
	return "%s (%s)" % [held.name, CrewScript.role_name(held.role)]


## One row per person, with what they cost **on a date** and whether they can work it. The date is
## asked for rather than assumed: a rate and an availability are both facts about a day (§7.1).
func crew_rows(on_date: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for held in crews:
		out.append({
			"id": String(held.id),
			"name": held.name,
			"role": String(held.role),
			"role_name": CrewScript.role_name(held.role),
			"loaded_rate": held.rate_on(on_date),
			"available": held.available_on(on_date),
		})
	return out


# --- the jobs --------------------------------------------------------------------------------


## A job from the estimate it was agreed from: the phases are the estimate's own cost codes, the
## contract sum is its price before tax, and the revision it was contracted from is recorded, so the
## budget has a lineage (§4.10).
func make_job_from(estimate: Estimate, basis: int = JobScript.PRICE) -> Job:
	if estimate == null:
		return null
	var made: Job = JobScript.from_estimate(estimate, basis)
	made.name = String(estimate.customer.get("name", ""))
	if not add_job(made):
		return null
	return made


func add_job(record: Job) -> bool:
	if record == null or record.id.is_empty():
		return false
	if job(record.id) != null:
		return false
	jobs.append(record)
	return true


func job(job_id: String) -> Job:
	for held in jobs:
		if held.id == job_id:
			return held
	return null


## What a job is called on a board or in a route: its name, its number, or its id, whichever it has.
func job_label(job_id: String) -> String:
	var held: Job = job(job_id)
	if held == null:
		return job_id
	if not held.name.is_empty():
		return held.name
	if not held.number.is_empty():
		return held.number
	return job_id


func job_ids() -> Array[String]:
	var out: Array[String] = []
	for held in jobs:
		out.append(held.id)
	return out


## One row per job: what it is worth, how it is billed and how many phases it carries. The budget
## total is the job's own sum of its own phase budgets.
func job_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for held in jobs:
		out.append({
			"id": held.id,
			"name": job_label(held.id),
			"number": held.number,
			"contract_sum": held.contract_sum,
			"budget_total": held.budget_total(),
			"billing_method": held.billing_method,
			"billing_name": JobScript.billing_name(held.billing_method),
			"phase_count": held.phases.size(),
			"estimate_revision": held.estimate_revision,
		})
	return out


# --- where a job is ----------------------------------------------------------------------------


## State where a job is on the drawing. Refused for a job this desk does not have: a place is a
## property of a job, and a place for nobody is a place nothing can be sent to.
func set_job_place(job_id: String, at: Vector2) -> bool:
	if job(job_id) == null:
		return false
	job_places[job_id] = at
	return true


func has_job_place(job_id: String) -> bool:
	return job_places.has(job_id)


func job_place(job_id: String) -> Vector2:
	var at = job_places.get(job_id, null)
	if at is Vector2:
		return at
	return Vector2.ZERO


# --- the board ---------------------------------------------------------------------------------


## Book a crew onto a job for a window on a day. The block goes on the board **and** on the job's own
## schedule, from one call, because a job that has been scheduled is a job that says when.
##
## Refused for a job or a person this desk does not have, and then for everything `Schedule.place`
## refuses - a window that ends before it starts, or one outside the day.
## Returns `{ok, reason, index}`.
func book(job_id: String, member_id: StringName, date: String, start_minute: int, end_minute: int,
		note: String = "") -> Dictionary:
	if job(job_id) == null:
		return {"ok": false, "reason": "there is no job %s to book" % job_id, "index": -1}
	if crew(member_id) == null:
		return {"ok": false,
			"reason": "there is nobody called %s on the crew" % String(member_id), "index": -1}
	var placed: Dictionary = schedule.place(job_id, member_id, date, start_minute, end_minute, note)
	if not bool(placed["ok"]):
		return placed
	var index := int(placed["index"])
	var held: Job = job(job_id)
	held.schedule.append(_block_copy(schedule.entries[index]))
	return {"ok": true, "reason": "", "index": index}


## Take a block off the board, and off the job's own schedule with it.
func unbook(index: int) -> bool:
	if index < 0 or index >= schedule.count():
		return false
	var before: Dictionary = _block_copy(schedule.entries[index])
	var held: Job = job(String(before["job"]))
	if not schedule.remove(index):
		return false
	if held != null:
		var at: int = _index_of_block(held, before)
		if at >= 0:
			held.schedule.remove_at(at)
	return true


## Move a block to another day, or to another window on the same day. The job's own copy follows, so
## the board and the job file still say the same thing.
##
## A copy of the block is taken **before** the move, because a `Dictionary` in the board is a
## reference: after `move_to` the board's own entry reads the new window, and matching on it would
## find nothing on the job.
func move_block(index: int, date: String, start_minute: int, end_minute: int) -> bool:
	if index < 0 or index >= schedule.count():
		return false
	var before: Dictionary = _block_copy(schedule.entries[index])
	var held: Job = job(String(before["job"]))
	if not schedule.move_to(index, date, start_minute, end_minute):
		return false
	if held != null:
		var at: int = _index_of_block(held, before)
		if at >= 0:
			held.schedule[at] = _block_copy(schedule.entries[index])
	return true


func blocks_on(date: String) -> Array[Dictionary]:
	return schedule.on_date(date)


## Every block on a day as a row a board can draw: `{index, job, job_label, crew, crew_label, date,
## start_minute, end_minute, note}`. The index is the block's identity until somebody is given a real
## one - a board only ever moves a thing it can point at (§7.4).
func day_rows(date: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for index in schedule.entries.size():
		var entry: Dictionary = schedule.entries[index]
		if String(entry["date"]) != date:
			continue
		out.append({
			"index": index,
			"job": String(entry["job"]),
			"job_label": job_label(String(entry["job"])),
			"crew": String(entry["crew"]),
			"crew_label": crew_label(StringName(entry["crew"])),
			"date": date,
			"start_minute": int(entry["start_minute"]),
			"end_minute": int(entry["end_minute"]),
			"note": String(entry.get("note", "")),
		})
	return out


## One block by its index, as plain data, or `{}`. A **copy**: a board reads a block, it does not hold
## the desk's own, and reading start and end out of the desk's entry after moving it would read the
## new window rather than the one the move started from.
func block_at(index: int) -> Dictionary:
	if index < 0 or index >= schedule.count():
		return {}
	return _block_copy(schedule.entries[index])


func dates() -> Array[String]:
	return schedule.dates()


func block_count() -> int:
	return schedule.count()


## Everything wrong with the board, as the board's own rows. Never moved, only reported: "a scheduler
## that rearranges a crew's day without being asked is a scheduler nobody trusts twice" (§7.4).
func conflict_rows() -> Array[Dictionary]:
	return schedule.conflicts()


func conflict_count() -> int:
	return schedule.conflict_count()


func is_clear() -> bool:
	return schedule.is_clear()


# --- a crew's day, as a route ------------------------------------------------------------------


## A crew's day as a proposed order of stops, with the assumption stated in the route's own note.
##
## Every job the person is booked on that day must have a place: a stop with no place is refused by
## name rather than driven from the origin.
## Returns `{ok, reason, route}`.
func route_for(member_id: StringName, date: String, start_minute: int = DEFAULT_DAY_START) -> Dictionary:
	var member: CrewMember = crew(member_id)
	if member == null:
		return {"ok": false,
			"reason": "there is nobody called %s on the crew" % String(member_id), "route": {}}
	var stops: Array = []
	for entry in schedule.on_date(date):
		if String(entry["crew"]) != String(member_id):
			continue
		var job_id := String(entry["job"])
		if not job_places.has(job_id):
			return {"ok": false,
				"reason": "the job %s has no place on the drawing, so there is nowhere to drive to"
					% job_label(job_id),
				"route": {}}
		stops.append({
			"id": job_id,
			"at": job_place(job_id),
			"service_minutes": int(entry["end_minute"]) - int(entry["start_minute"]),
		})
	# The crew starts from their own home base, which is stated on the person (§7.2).
	var planned: Dictionary = RouteScript.plan(
		member.home_base, stops, RouteScript.DEFAULT_SPEED_KMH, {}, start_minute
	)
	return {"ok": true, "reason": "", "route": planned}


# --- the time ----------------------------------------------------------------------------------


## Log what somebody worked. Refused for nobody, for a record with no id, for an id already logged,
## and for an entry that does not read - an entry that ends before it starts is not a record of work
## and is never averaged away (§7.3).
func log_time(entry: TimeEntry) -> bool:
	if entry == null or entry.id.is_empty():
		return false
	if time_entry(entry.id) != null:
		return false
	if not entry.is_valid():
		return false
	time_entries.append(entry)
	return true


func time_entry(entry_id: String) -> TimeEntry:
	for held in time_entries:
		if held.id == entry_id:
			return held
	return null


## Approve an entry, so it may become cost. Only an entry that reads can be approved.
func approve_time(entry_id: String, by: String) -> bool:
	var entry: TimeEntry = time_entry(entry_id)
	if entry == null:
		return false
	return entry.approve(by)


func entries_for(job_id: String) -> Array[TimeEntry]:
	var out: Array[TimeEntry] = []
	for held in time_entries:
		if held.job == job_id:
			out.append(held)
	return out


## What a job's approved time cost, in the job's own currency. An entry whose rate cannot be read
## poisons the total rather than reading as free labour - Money's own contagion, not a rule here.
func labour_on(job_id: String) -> Money:
	var amounts: Array = []
	for entry in entries_for(job_id):
		if entry.is_approved():
			amounts.append(entry.labour())
	return MoneyScript.sum(amounts, currency)


## What has been logged and not approved, and how many entries that is: excluded from cost and
## reported beside it, so a job never reads low without saying why (§7.3).
func pending_on(job_id: String) -> Dictionary:
	var amounts: Array = []
	var waiting := 0
	for entry in entries_for(job_id):
		if not entry.is_approved():
			waiting += 1
			amounts.append(entry.labour())
	return {"total": MoneyScript.sum(amounts, currency), "count": waiting}


func time_rows(job_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in entries_for(job_id):
		out.append({
			"id": entry.id,
			"crew": entry.crew_member,
			"crew_label": crew_label(entry.crew_member),
			"cost_code": String(entry.cost_code),
			"minutes": entry.minutes(),
			"amount": entry.labour(),
			"approved": entry.is_approved(),
			"problem": entry.problem(),
			"source_name": EntryScript.source_name(entry.source),
		})
	return out


# --- what it says ------------------------------------------------------------------------------


## One line for the menu: what the desk holds, and whether the board is clear. A board with something
## wrong on it says so here rather than only inside the window.
func describe() -> String:
	if jobs.is_empty() and crews.is_empty() and schedule.count() == 0:
		return "no crews and no jobs yet"
	var line := "%d crew%s, %d job%s, %d block%s on the board" % [
		crews.size(), _plural(crews.size()),
		jobs.size(), _plural(jobs.size()),
		schedule.count(), _plural(schedule.count()),
	]
	var problems := conflict_count()
	if problems > 0:
		line += ", %d conflict%s" % [problems, _plural(problems)]
	return line


## Everything the board's own rows say, in words.
func conflict_lines() -> Array[String]:
	var out: Array[String] = []
	for row in conflict_rows():
		out.append("%s on %s: %s" % [String(row["name"]), String(row["date"]), String(row["detail"])])
	return out


# --- the file ----------------------------------------------------------------------------------


func to_dict() -> Dictionary:
	var crew_list: Array = []
	for held in crews:
		crew_list.append(held.to_dict())
	var job_list: Array = []
	for held in jobs:
		job_list.append(held.to_dict())
	var entry_list: Array = []
	for held in time_entries:
		entry_list.append(held.to_dict())
	var places: Dictionary = {}
	for key in job_places.keys():
		var at: Vector2 = job_place(String(key))
		places[String(key)] = [at.x, at.y]
	return {
		"currency": String(currency),
		"crews": crew_list,
		"jobs": job_list,
		"schedule": schedule.to_dict(),
		"time_entries": entry_list,
		"job_places": places,
	}


## A damaged record is **dropped, not invented**: a crew member with no id, a job with no id, a block
## that will not place. The desk comes back with what it could read.
static func from_dict(data: Dictionary) -> JobDesk:
	var desk: JobDesk = DeskScript.new()
	desk.currency = StringName(data.get("currency", "CAD"))
	var crew_list = data.get("crews", [])
	if crew_list is Array:
		for entry in (crew_list as Array):
			if entry is Dictionary:
				desk.add_crew(CrewScript.from_dict(entry))
	var job_list = data.get("jobs", [])
	if job_list is Array:
		for entry in (job_list as Array):
			if entry is Dictionary:
				desk.add_job(JobScript.from_dict(entry))
	var board = data.get("schedule", {})
	if board is Dictionary:
		desk.schedule = ScheduleScript.from_dict(board)
		# A block whose job is not on the desk is dropped: the board can name a job or it can show a
		# block nothing can be said about, and the second is a row the office cannot act on.
		var at: int = desk.schedule.count() - 1
		while at >= 0:
			if desk.job(String(desk.schedule.entries[at].get("job", ""))) == null:
				desk.schedule.remove(at)
			at -= 1
		for held in desk.crews:
			desk.schedule.know_crew(held)
	var entry_list = data.get("time_entries", [])
	if entry_list is Array:
		for entry in (entry_list as Array):
			if entry is Dictionary:
				desk.log_time(EntryScript.from_dict(entry))
	var places = data.get("job_places", {})
	if places is Dictionary:
		for key in (places as Dictionary).keys():
			var at = (places as Dictionary)[key]
			if at is Array and (at as Array).size() == 2:
				var job_id := String(key)
				if desk.job(job_id) != null:
					desk.job_places[job_id] = Vector2(float(at[0]), float(at[1]))
	return desk


# --- the small joins --------------------------------------------------------------------------


## A block as plain data: the board's entry copied field by field, so the job's copy is the job's own
## and not a second reference to the board's.
static func _block_copy(entry: Dictionary) -> Dictionary:
	return {
		"job": String(entry.get("job", "")),
		"crew": String(entry.get("crew", "")),
		"date": String(entry.get("date", "")),
		"start_minute": int(entry.get("start_minute", 0)),
		"end_minute": int(entry.get("end_minute", 0)),
		"note": String(entry.get("note", "")),
	}


## Where a block sits on a job's own schedule, by what it says. -1 when the job does not hold it.
static func _index_of_block(record: Job, block: Dictionary) -> int:
	for index in record.schedule.size():
		var held: Dictionary = record.schedule[index]
		if String(held.get("job", "")) != String(block["job"]):
			continue
		if String(held.get("crew", "")) != String(block["crew"]):
			continue
		if String(held.get("date", "")) != String(block["date"]):
			continue
		if int(held.get("start_minute", 0)) != int(block["start_minute"]):
			continue
		if int(held.get("end_minute", 0)) != int(block["end_minute"]):
			continue
		return index
	return -1


static func _plural(how_many: int) -> String:
	return "" if how_many == 1 else "s"


const DeskScript := preload("res://scripts/biz/job_desk.gd")