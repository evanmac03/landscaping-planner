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
const OrderScript := preload("res://scripts/biz/purchase_order.gd")
const ChangeScript := preload("res://scripts/biz/change_order.gd")
const CostScript := preload("res://scripts/biz/job_cost.gd")
const LineScript := preload("res://scripts/biz/estimate_line.gd")
const ItemScript := preload("res://scripts/biz/cost_item.gd")

const DEFAULT_CURRENCY := &"CAD"
## The hour a crew's day begins when nobody has said otherwise: 8:00, as minutes from midnight.
const DEFAULT_DAY_START := 480
## The prefixes the desk hands numbers out under. A number is a thing an office keeps a register of,
## and two purchase orders with one number is the failure numbering exists to prevent (§8.3).
const PO_PREFIX := "PO-"
const CO_PREFIX := "CO-"

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
## What has been ordered for a job, and what has arrived against it (phase 6, §8.3).
var purchase_orders: Array[PurchaseOrder] = []
## What a customer has been asked to agree to on top of the contract, and whether they have (phase 6,
## §8.2).
var change_orders: Array[ChangeOrder] = []
## What has been invoiced and what has been collected, keyed by job id. **Said, never assumed**: a job
## with no entry here reports billed as unknown rather than as nothing (§8.4).
var invoiced: Dictionary = {}
var collected: Dictionary = {}


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


# --- what was ordered, and what was agreed to on top ------------------------------------------


## The next number in a series the desk hands out, so that two orders cannot be given the same one.
## The highest number already taken wins rather than the count: an order that was voided leaves its
## number taken, which is what a register of numbered paper does.
static func next_number(prefix: String, taken: Array[String]) -> String:
	var highest := 0
	for text in taken:
		if not text.begins_with(prefix):
			continue
		var tail := text.substr(prefix.length())
		if tail.is_valid_int() and int(tail) > highest:
			highest = int(tail)
	return "%s%03d" % [prefix, highest + 1]


## An order for one thing, ready to be issued. Refused for a job this desk does not have, and for a
## line `PurchaseOrder.add_line` refuses - nothing to order, no quantity, no readable rate.
##
## The order is **not** issued here: ordering and issuing are two acts, and §8.4 wants the office to
## see what an order would commit it to before it goes out.
func make_purchase_order(job_id: String, cost_code: StringName, description: String,
		quantity_milli: int, unit_cost: Money, supplier: String,
		unit: StringName = &"EACH") -> PurchaseOrder:
	if job(job_id) == null:
		return null
	var taken: Array[String] = []
	for held in purchase_orders:
		taken.append(held.number)
	var number := next_number(PO_PREFIX, taken)
	var order: PurchaseOrder = OrderScript.new(number)
	order.number = number
	order.job = job_id
	order.cost_code = cost_code
	order.supplier = supplier
	order.currency = currency
	if not order.add_line(description, unit, quantity_milli, unit_cost):
		return null
	if not add_purchase_order(order):
		return null
	return order


func add_purchase_order(order: PurchaseOrder) -> bool:
	if order == null or order.id.strip_edges().is_empty():
		return false
	if purchase_order(order.id) != null:
		return false
	purchase_orders.append(order)
	return true


func purchase_order(order_id: String) -> PurchaseOrder:
	for held in purchase_orders:
		if held.id == order_id:
			return held
	return null


func purchase_orders_for(job_id: String) -> Array[PurchaseOrder]:
	var out: Array[PurchaseOrder] = []
	for held in purchase_orders:
		if held.job == job_id:
			out.append(held)
	return out


## What an order of `quantity_milli` at `unit_cost` for a cost code would do to that code's budget,
## asked **before** the order is issued. This is the flag §8.4 wants raised at the moment the
## commitment is made: the one moment the office can still change its mind.
## Returns `{over, remaining, reason}`.
func order_would_commit(job_id: String, cost_code: StringName, quantity_milli: int,
		unit_cost: Money) -> Dictionary:
	var held: Job = job(job_id)
	if held == null:
		return {"over": false, "remaining": MoneyScript.zero(currency),
			"reason": "there is no job %s on the desk" % job_id}
	var amount: Money = MoneyScript.round_div(
		unit_cost.cents * quantity_milli, OrderScript.QUANTITY_MILLI, currency
	) if unit_cost != null and unit_cost.is_valid() else MoneyScript.invalid(currency)
	return CostScript.over_commitment(held, purchase_orders_for(job_id), cost_code, amount)


## Order it. Refused for everything `PurchaseOrder.issue` refuses, and refused for an order whose
## cost code **this job has no budget for at all**: a commitment against a code the contract never
## sold is how a job is committed past its own agreement without anybody noticing. The warning is
## returned either way, so a caller can show it.
## Returns `{ok, reason, warning}`.
func issue_purchase_order(order_id: String, at: String) -> Dictionary:
	var order: PurchaseOrder = purchase_order(order_id)
	if order == null:
		return {"ok": false, "reason": "there is no order %s on the desk" % order_id, "warning": ""}
	var held: Job = job(order.job)
	if held == null:
		return {"ok": false, "reason": "the order is for a job this desk does not have",
			"warning": ""}
	if held.phase(String(order.cost_code)).is_empty():
		return {"ok": false, "reason": "the job %s has no %s in it to charge this to" % [
			job_label(order.job), String(order.cost_code),
		], "warning": ""}
	var issued: Dictionary = order.issue(at)
	if not bool(issued["ok"]):
		return {"ok": false, "reason": String(issued["reason"]), "warning": ""}
	# The warning is computed **after** the order has gone out, from the orders that are now live -
	# which is the commitment the office can still act on. The order's own figure is one of the live
	# ones being summed, so nothing is counted twice.
	var warning := ""
	if order.committed().cents > 0:
		var asked: Dictionary = CostScript.over_commitment(
			held, purchase_orders_for(order.job), order.cost_code, MoneyScript.zero(currency)
		)
		if bool(asked["over"]):
			warning = String(asked["reason"])
	return {"ok": true, "reason": "", "warning": warning}


## Record a delivery against a line of an order.
func receive_order_line(order_id: String, line_index: int, quantity_milli: int, at: String,
		note: String = "") -> Dictionary:
	var order: PurchaseOrder = purchase_order(order_id)
	if order == null:
		return {"ok": false, "reason": "there is no order %s on the desk" % order_id}
	return order.receive(at, line_index, quantity_milli, note)


## What arrived, recorded as what is still outstanding: the ordinary case where the truck brings what
## was ordered. A short or long delivery is recorded line by line instead.
## Returns `{ok, reason}`.
func receive_what_was_ordered(order_id: String, at: String) -> Dictionary:
	var order: PurchaseOrder = purchase_order(order_id)
	if order == null:
		return {"ok": false, "reason": "there is no order %s on the desk" % order_id}
	var anything := false
	for index in order.line_count():
		var outstanding := order.ordered_milli(index) - order.received_milli(index)
		if outstanding <= 0:
			continue
		var taken: Dictionary = order.receive(at, index, outstanding)
		if bool(taken["ok"]):
			anything = true
	return {"ok": anything,
		"reason": "" if anything else "there is nothing outstanding on it"}


## Close an order once it has been invoiced and reconciled.
func close_order(order_id: String, at: String, why: String = "") -> bool:
	var order: PurchaseOrder = purchase_order(order_id)
	if order == null:
		return false
	return order.mark_closed(at, why)


## One row per order on a job, as a list draws it. `committed` is the order's own figure - the desk
## recomputes nothing (§8.3).
func order_rows(job_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for held in purchase_orders_for(job_id):
		out.append({
			"id": held.id,
			"number": held.number,
			"cost_code": String(held.cost_code),
			"supplier": held.supplier,
			"state": String(held.state()),
			"state_name": held.state_name(),
			"ordered": held.ordered_total(),
			"received": held.received_total(),
			"committed": held.committed(),
			"actual": held.actual(),
			"issued_at": held.issued_at,
			"problems": held.problems(),
			"describe": held.describe(),
		})
	return out


# --- change orders -----------------------------------------------------------------------------


## A change order for a job, priced as one line: what the extra work is sold for. The reason is
## required and comes from §8.2's short list.
##
## One line is a deliberate limit of this door, not of the model: `ChangeOrder` holds a whole
## `Estimate`, so a change with twenty lines is made from an estimate (`change_order_from`), and this
## is the case where somebody at a desk knows the number.
func make_change_order(job_id: String, reason_key: StringName, description: String,
		amount: Money, cost_code: StringName, unit_cost: Money = null) -> ChangeOrder:
	if job(job_id) == null or not ChangeScript.is_reason(reason_key):
		return null
	if amount == null or not amount.is_valid() or amount.cents == 0:
		return null
	var taken: Array[String] = []
	for held in change_orders:
		taken.append(held.number)
	var number := next_number(CO_PREFIX, taken)
	var change: ChangeOrder = ChangeScript.new(number)
	change.number = number
	change.job = job_id
	change.reason = reason_key
	var line: EstimateLine = LineScript.new()
	line.description = description if not description.strip_edges().is_empty() \
		else "change: %s" % ChangeScript.reason_name(reason_key)
	line.cost_code = cost_code
	line.kind = ItemScript.MATERIAL
	line.quantity_milli = 1000
	line.unit = &"EACH"
	line.unit_cost = unit_cost if unit_cost != null and unit_cost.is_valid() \
		else MoneyScript.zero(currency)
	line.unit_price = amount
	if not change.add_line(line):
		return null
	if not add_change_order(change):
		return null
	return change


## A change order from the estimate it was priced as: §8.2's own shape, where the change is a small
## estimate and reuses §5's engine. The lines are **copied** line by line, so the change order and the
## estimate it came from cannot move each other.
func change_order_from(estimate: Estimate, job_id: String, reason_key: StringName) -> ChangeOrder:
	if estimate == null or job(job_id) == null or not ChangeScript.is_reason(reason_key):
		return null
	if estimate.line_count() == 0:
		return null
	var taken: Array[String] = []
	for held in change_orders:
		taken.append(held.number)
	var number := next_number(CO_PREFIX, taken)
	var change: ChangeOrder = ChangeScript.new(number)
	change.number = number
	change.job = job_id
	change.reason = reason_key
	for each: EstimateLine in estimate.lines:
		change.estimate.lines.append(each.copy())
	return change if add_change_order(change) else null


func add_change_order(change: ChangeOrder) -> bool:
	if change == null or change.id.strip_edges().is_empty():
		return false
	if change_order(change.id) != null:
		return false
	change_orders.append(change)
	return true


func change_order(order_id: String) -> ChangeOrder:
	for held in change_orders:
		if held.id == order_id:
			return held
	return null


func change_orders_for(job_id: String) -> Array[ChangeOrder]:
	var out: Array[ChangeOrder] = []
	for held in change_orders:
		if held.job == job_id:
			out.append(held)
	return out


func propose_change(order_id: String, at: String) -> bool:
	var held: ChangeOrder = change_order(order_id)
	return false if held == null else held.propose(at)


func send_change(order_id: String, at: String) -> bool:
	var held: ChangeOrder = change_order(order_id)
	return false if held == null else held.send(at)


func approve_change(order_id: String, by: String, at: String, how: String,
		signature: String = "") -> Dictionary:
	var held: ChangeOrder = change_order(order_id)
	if held == null:
		return {"ok": false, "reason": "there is no change order %s on the desk" % order_id}
	return held.approve(by, at, how, signature)


func decline_change(order_id: String, by: String, at: String, why: String) -> Dictionary:
	var held: ChangeOrder = change_order(order_id)
	if held == null:
		return {"ok": false, "reason": "there is no change order %s on the desk" % order_id}
	return held.decline(by, at, why)


func void_change(order_id: String, at: String, why: String) -> Dictionary:
	var held: ChangeOrder = change_order(order_id)
	if held == null:
		return {"ok": false, "reason": "there is no change order %s on the desk" % order_id}
	return held.mark_void(at, why)


func change_rows(job_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for held in change_orders_for(job_id):
		out.append({
			"id": held.id,
			"number": held.number,
			"reason": String(held.reason),
			"reason_name": ChangeScript.reason_name(held.reason),
			"state": String(held.state()),
			"state_name": held.state_name(),
			"amount": held.amount(),
			"amount_text": held.amount_text(),
			"pending": held.is_pending(),
			"enters_contract_sum": held.enters_contract_sum(),
			"line_count": held.line_count(),
			"approval_text": held.approval_text(),
			"describe": held.describe(),
		})
	return out


# --- what it has cost, and what it has been billed ---------------------------------------------


## Say what a job has been invoiced, and what has been collected against it. Both are **stated**:
## phase 6 has no invoicing of its own, and a report that showed nothing billed because nobody had
## told it would be a report that lies quietly (§8.4).
func set_invoiced(job_id: String, amount: Money) -> bool:
	if job(job_id) == null or amount == null or not amount.is_valid():
		return false
	invoiced[job_id] = amount
	return true


func set_collected(job_id: String, amount: Money) -> bool:
	if job(job_id) == null or amount == null or not amount.is_valid():
		return false
	collected[job_id] = amount
	return true


## What a job has been invoiced, or **null** when nobody has said - which is not the same as nothing.
func invoiced_for(job_id: String) -> Money:
	var held = invoiced.get(job_id, null)
	return held if held is Money else null


func collected_for(job_id: String) -> Money:
	var held = collected.get(job_id, null)
	return held if held is Money else null


## The report, built from the records every time it is asked for. Nothing is cached, so a receipt
## entered a second ago is in it. Null for a job this desk does not have.
func cost_report(job_id: String) -> JobCost:
	var held: Job = job(job_id)
	if held == null:
		return null
	return CostScript.of(held, purchase_orders_for(job_id), change_orders_for(job_id),
		entries_for(job_id), invoiced_for(job_id), collected_for(job_id))


func cost_rows(job_id: String) -> Array[Dictionary]:
	var report: JobCost = cost_report(job_id)
	return [] if report == null else report.rows


func cost_totals_text(job_id: String) -> String:
	var report: JobCost = cost_report(job_id)
	return "" if report == null else report.totals_text()


func cost_problems(job_id: String) -> Array[String]:
	var report: JobCost = cost_report(job_id)
	return [] if report == null else report.problems()


# --- what it says ------------------------------------------------------------------------------


## One line for the menu: what the desk holds, and whether the board is clear. A board with something
## wrong on it says so here rather than only inside the window.
func describe() -> String:
	var money := _money_lines()
	if jobs.is_empty() and crews.is_empty() and schedule.count() == 0 and money.is_empty():
		return "no crews and no jobs yet"
	var parts := PackedStringArray()
	if not crews.is_empty():
		parts.append("%d crew%s" % [crews.size(), _plural(crews.size())])
	if not jobs.is_empty():
		parts.append("%d job%s" % [jobs.size(), _plural(jobs.size())])
	parts.append("%d block%s on the board" % [schedule.count(), _plural(schedule.count())])
	var problems := conflict_count()
	if problems > 0:
		parts.append("%d conflict%s" % [problems, _plural(problems)])
	for line in money:
		parts.append(line)
	return ", ".join(parts)


## What the orders and the agreed change orders come to, in words, for the one line the menu shows.
## Nothing is said about a desk that has neither.
func _money_lines() -> Array[String]:
	var out: Array[String] = []
	if not purchase_orders.is_empty():
		var committed: Array = []
		for held in purchase_orders:
			committed.append(held.committed())
		out.append("%d purchase order%s (%s committed)" % [
			purchase_orders.size(), _plural(purchase_orders.size()),
			MoneyScript.sum(committed, currency).format_with_currency(),
		])
	var agreed: Array = []
	var waiting := 0
	for held in change_orders:
		if held.enters_contract_sum():
			agreed.append(held.amount())
		elif held.is_pending():
			waiting += 1
	if not change_orders.is_empty():
		var line := "%d change order%s (%s agreed" % [
			change_orders.size(), _plural(change_orders.size()),
			MoneyScript.sum(agreed, currency).format_with_currency(),
		]
		# Written as a statement and not as `line += ... if ... else ...`: a ternary swallows the
		# `+=` into its condition arm, so the assignment simply never happens on the false branch.
		if waiting > 0:
			line += ", %d pending)" % waiting
		else:
			line += ")"
		out.append(line)
	return out


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
	var orders: Array = []
	for held in purchase_orders:
		orders.append(held.to_dict())
	var changes: Array = []
	for held in change_orders:
		changes.append(held.to_dict())
	var billed: Dictionary = {}
	for key in invoiced.keys():
		var said: Money = invoiced_for(String(key))
		if said != null and said.is_valid():
			billed[String(key)] = said.to_dict()
	var paid: Dictionary = {}
	for key in collected.keys():
		var said: Money = collected_for(String(key))
		if said != null and said.is_valid():
			paid[String(key)] = said.to_dict()
	return {
		"currency": String(currency),
		"crews": crew_list,
		"jobs": job_list,
		"schedule": schedule.to_dict(),
		"time_entries": entry_list,
		"job_places": places,
		"purchase_orders": orders,
		"change_orders": changes,
		"invoiced": billed,
		"collected": paid,
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
	# An order or a change order whose job is not on the desk is dropped for the same reason a block
	# is: it would be a cost against nothing, and the report would carry money no job can explain.
	var order_list = data.get("purchase_orders", [])
	if order_list is Array:
		for entry in (order_list as Array):
			if entry is Dictionary:
				var read: PurchaseOrder = OrderScript.from_dict(entry)
				if read != null and desk.job(read.job) != null:
					desk.add_purchase_order(read)
	var change_list = data.get("change_orders", [])
	if change_list is Array:
		for entry in (change_list as Array):
			if entry is Dictionary:
				var raised: ChangeOrder = ChangeScript.from_dict(entry)
				if raised != null and desk.job(raised.job) != null:
					desk.add_change_order(raised)
	for key in _billed_keys(data):
		var job_id := String(key)
		if desk.job(job_id) == null:
			continue
		var paid: Money = MoneyScript.from_dict((data["invoiced"] as Dictionary)[key])
		if paid.is_valid():
			desk.invoiced[job_id] = paid
		var got = (data["collected"] as Dictionary).get(key, null)
		if got is Dictionary:
			var received: Money = MoneyScript.from_dict(got)
			if received.is_valid():
				desk.collected[job_id] = received
	return desk


## The job ids that have a billed figure recorded. Kept apart so that a file with one and not the other
## is read as what it says rather than as a fault.
static func _billed_keys(data: Dictionary) -> Array:
	var held = data.get("invoiced", null)
	if held is Dictionary:
		return (held as Dictionary).keys()
	return []


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