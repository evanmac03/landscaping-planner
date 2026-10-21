extends Node
## The job desk: the crews, the jobs, their days, their routes and their time (spec §7).
##
## The desk owns no arithmetic, so what is under test is the **join**: that a block booked through it
## lands on the board and on the job at once, that a route refuses a job with no place rather than
## driving to the origin, and that only approved time becomes cost.

const DeskScript := preload("res://scripts/biz/job_desk.gd")
const JobScript := preload("res://scripts/biz/job.gd")
const CrewScript := preload("res://scripts/biz/crew.gd")
const EntryScript := preload("res://scripts/biz/time_entry.gd")
const EstimateScript := preload("res://scripts/biz/estimate.gd")
const LineScript := preload("res://scripts/biz/estimate_line.gd")
const ItemScript := preload("res://scripts/biz/cost_item.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")

## A Wednesday, and a Sunday, both used below.
const WEDNESDAY := "2026-06-10"
const SUNDAY := "2026-06-07"


func _desk() -> DeskScript:
	return DeskScript.new()


func _person(member_id: StringName = &"C1", person_name: String = "Dana") -> CrewScript:
	var member: CrewScript = CrewScript.new(member_id, person_name)
	member.add_rate("2026-01-01", MoneyScript.of(4500))
	member.home_base = Vector2.ZERO
	return member


## An estimate over two cost codes: 10 x 15.00 of planting and 20 x 20.00 of hardscape.
func _estimate(estimate_id: String = "E1") -> EstimateScript:
	var estimate: EstimateScript = EstimateScript.new(estimate_id)
	estimate.customer = {"name": "Smith, back garden"}
	estimate.lines.append(_line(&"PLANTING", 10000, 1500))
	estimate.lines.append(_line(&"HARDSCAPE", 20000, 2000))
	return estimate


func _line(code: StringName, units_milli: int, price_cents: int) -> LineScript:
	var line: LineScript = LineScript.new()
	line.cost_code = code
	line.kind = ItemScript.MATERIAL
	line.quantity_milli = units_milli
	line.unit = &"EACH"
	line.unit_cost = MoneyScript.of(price_cents / 2)
	line.unit_price = MoneyScript.of(price_cents)
	return line


## An entry: 8:00 to 16:30 with half an hour for lunch, which is 480 minutes.
func _entry(entry_id: String = "T1", member_id: StringName = &"C1", rate_cents: int = 5000) -> EntryScript:
	var entry: EntryScript = EntryScript.new(entry_id)
	entry.job = "E1"
	entry.cost_code = &"PLANTING"
	entry.crew_member = member_id
	entry.started_at = "2026-06-10T08:00:00"
	entry.ended_at = "2026-06-10T16:30:00"
	entry.break_minutes = 30
	entry.loaded_rate = MoneyScript.of(rate_cents)
	return entry


# --- the people ------------------------------------------------------------------------------


func test_a_desk_with_nothing_on_it_says_so() -> void:
	var desk := _desk()
	assert(desk.describe() == "no crews and no jobs yet", desk.describe())
	assert(desk.conflict_lines().is_empty())
	assert(desk.dates().is_empty())


func test_a_person_is_taken_onto_the_crew_once() -> void:
	var desk := _desk()
	assert(desk.add_crew(_person()))
	assert(not desk.add_crew(_person()), "the same id twice is one person")
	assert(desk.crew(&"C1") != null)
	assert(desk.crew_ids() == [&"C1"], str(desk.crew_ids()))


func test_a_record_with_no_id_is_not_a_person() -> void:
	var desk := _desk()
	assert(not desk.add_crew(null))
	assert(not desk.add_crew(CrewScript.new(&"", "nobody")))
	assert(desk.crew_ids().is_empty())


func test_a_label_is_the_name_and_the_role_or_the_id() -> void:
	var desk := _desk()
	var member := _person()
	member.role = &"FOREMAN"
	desk.add_crew(member)
	assert(desk.crew_label(&"C1") == "Dana (Foreman)", desk.crew_label(&"C1"))
	assert(desk.crew_names() == ["Dana (Foreman)"])
	assert(desk.crew_label(&"nobody") == "nobody", "a label that vanished is a row nobody can find")


func test_crew_rows_read_a_person_on_a_date() -> void:
	var desk := _desk()
	var member := _person(&"C2", "Sam")
	member.add_availability({"kind": "DAY_OFF", "weekday": 0})
	desk.add_crew(member)
	var row: Dictionary = desk.crew_rows(WEDNESDAY)[0]
	assert(row["id"] == "C2")
	assert(row["role_name"] == "Labourer")
	assert((row["loaded_rate"] as MoneyScript).format() == "45.00")
	assert(bool(row["available"]), "a Wednesday is a working day")
	assert(not bool(desk.crew_rows(SUNDAY)[0]["available"]), "a Sunday is not")


# --- the jobs --------------------------------------------------------------------------------


func test_a_job_is_made_from_an_estimate_with_the_estimates_own_codes() -> void:
	var desk := _desk()
	var made: JobScript = desk.make_job_from(_estimate())
	assert(made != null)
	assert(desk.job("E1") == made)
	assert(made.name == "Smith, back garden", "the job is named for the customer")
	assert(made.phase_codes() == ["HARDSCAPE", "PLANTING"])
	assert(made.contract_sum.format() == "550.00", made.contract_sum.format())


func test_making_a_job_from_nothing_is_refused() -> void:
	var desk := _desk()
	assert(desk.make_job_from(null) == null)
	assert(desk.jobs.is_empty())


func test_a_job_is_added_once() -> void:
	var desk := _desk()
	var made: JobScript = desk.make_job_from(_estimate())
	assert(not desk.add_job(made), "the same job twice is one job")
	assert(not desk.add_job(null))
	assert(desk.job_ids() == ["E1"])


func test_a_label_falls_back_to_the_number_then_the_id() -> void:
	var desk := _desk()
	var named: JobScript = JobScript.new("J1")
	named.name = "the Nguyen job"
	desk.add_job(named)
	var numbered: JobScript = JobScript.new("J2")
	numbered.number = "2026-014"
	desk.add_job(numbered)
	var bare: JobScript = JobScript.new("J3")
	desk.add_job(bare)
	assert(desk.job_label("J1") == "the Nguyen job")
	assert(desk.job_label("J2") == "2026-014")
	assert(desk.job_label("J3") == "J3")
	assert(desk.job_label("gone") == "gone", "a job the desk never had is still named by its id")


func test_job_rows_carry_the_budget_the_revision_and_how_it_is_billed() -> void:
	var desk := _desk()
	var estimate := _estimate()
	estimate.revision = 2
	desk.make_job_from(estimate)
	var row: Dictionary = desk.job_rows()[0]
	assert(row["id"] == "E1")
	assert(row["name"] == "Smith, back garden")
	assert((row["contract_sum"] as MoneyScript).format() == "550.00")
	assert((row["budget_total"] as MoneyScript).format() == "550.00")
	assert(row["billing_name"] == "fixed price")
	assert(int(row["estimate_revision"]) == 2)
	assert(int(row["phase_count"]) == 2)


# --- where a job is ----------------------------------------------------------------------------


func test_a_place_is_stated_and_a_place_for_nobody_is_refused() -> void:
	var desk := _desk()
	desk.make_job_from(_estimate())
	assert(not desk.has_job_place("E1"), "nothing has been stated yet")
	assert(not desk.set_job_place("gone", Vector2(3.0, 4.0)))
	assert(desk.set_job_place("E1", Vector2(3.0, 4.0)))
	assert(desk.has_job_place("E1"))
	assert(desk.job_place("E1") == Vector2(3.0, 4.0))


# --- the board ---------------------------------------------------------------------------------


func test_booking_a_crew_puts_the_block_on_the_board_and_on_the_job() -> void:
	var desk := _desk()
	desk.add_crew(_person())
	desk.make_job_from(_estimate())
	var booked := desk.book("E1", &"C1", WEDNESDAY, 480, 960, "first day")
	assert(bool(booked["ok"]), String(booked["reason"]))
	assert(int(booked["index"]) == 0)
	assert(desk.block_count() == 1)
	assert(desk.blocks_on(WEDNESDAY).size() == 1)
	var held: JobScript = desk.job("E1")
	assert(held.schedule.size() == 1, "the job says when it is being built too")
	assert(int(held.schedule[0]["start_minute"]) == 480)
	assert(String(held.schedule[0]["note"]) == "first day")


func test_booking_a_job_the_desk_does_not_have_says_which() -> void:
	var desk := _desk()
	desk.add_crew(_person())
	var booked := desk.book("E9", &"C1", WEDNESDAY, 480, 960)
	assert(not bool(booked["ok"]))
	assert(String(booked["reason"]).contains("E9"), String(booked["reason"]))
	assert(desk.block_count() == 0)


func test_booking_somebody_who_is_not_on_the_crew_says_so() -> void:
	var desk := _desk()
	desk.make_job_from(_estimate())
	var booked := desk.book("E1", &"C9", WEDNESDAY, 480, 960)
	assert(not bool(booked["ok"]))
	assert(String(booked["reason"]).contains("C9"), String(booked["reason"]))


func test_a_window_that_ends_before_it_starts_is_refused_and_nothing_is_stored() -> void:
	var desk := _desk()
	desk.add_crew(_person())
	desk.make_job_from(_estimate())
	var refused := desk.book("E1", &"C1", WEDNESDAY, 960, 480)
	assert(not bool(refused["ok"]))
	assert(desk.block_count() == 0)
	assert(desk.job("E1").schedule.is_empty(), "and the job holds nothing either")


func test_taking_a_block_off_takes_it_off_the_job_too() -> void:
	var desk := _desk()
	desk.add_crew(_person())
	desk.make_job_from(_estimate())
	desk.book("E1", &"C1", WEDNESDAY, 480, 960)
	assert(desk.unbook(0))
	assert(desk.block_count() == 0)
	assert(desk.job("E1").schedule.is_empty())
	assert(not desk.unbook(0), "and there is nothing left to take off")


func test_moving_a_block_moves_the_jobs_own_copy_with_it() -> void:
	var desk := _desk()
	desk.add_crew(_person())
	desk.make_job_from(_estimate())
	desk.book("E1", &"C1", WEDNESDAY, 480, 960)
	assert(desk.move_block(0, "2026-06-11", 600, 1080))
	assert(desk.blocks_on(WEDNESDAY).is_empty())
	assert(desk.blocks_on("2026-06-11").size() == 1)
	var held: Dictionary = desk.job("E1").schedule[0]
	assert(String(held["date"]) == "2026-06-11")
	assert(int(held["start_minute"]) == 600)
	assert(int(held["end_minute"]) == 1080)
	assert(not desk.move_block(9, "2026-06-11", 600, 1080), "a block that is not there cannot move")


func test_the_board_reports_a_clash_and_moves_nothing() -> void:
	var desk := _desk()
	desk.add_crew(_person())
	desk.make_job_from(_estimate())
	desk.add_job(JobScript.new("E2"))
	desk.book("E1", &"C1", WEDNESDAY, 480, 960)
	desk.book("E2", &"C1", WEDNESDAY, 900, 1020)
	assert(desk.conflict_count() == 1, str(desk.conflict_lines()))
	assert(not desk.is_clear())
	assert(String(desk.conflict_rows()[0]["kind"]) == "CREW_DOUBLE_BOOKED")
	assert(desk.conflict_lines()[0].contains("C1"))
	assert(desk.block_count() == 2, "nothing was rearranged to avoid it")
	assert(int(desk.blocks_on(WEDNESDAY)[1]["start_minute"]) == 900)


func test_a_crew_on_a_day_off_is_a_clash() -> void:
	var desk := _desk()
	var member := _person()
	member.add_availability({"kind": "DAY_OFF", "weekday": 0})
	desk.add_crew(member)
	desk.make_job_from(_estimate())
	desk.book("E1", &"C1", SUNDAY, 480, 960)
	assert(desk.conflict_count() == 1, str(desk.conflict_lines()))
	assert(String(desk.conflict_rows()[0]["kind"]) == "UNAVAILABLE")
	assert(desk.conflict_lines()[0].contains("off on"), desk.conflict_lines()[0])


func test_the_summary_counts_the_crew_the_jobs_the_blocks_and_the_clashes() -> void:
	var desk := _desk()
	desk.add_crew(_person())
	desk.make_job_from(_estimate())
	desk.book("E1", &"C1", WEDNESDAY, 480, 960)
	assert(desk.describe() == "1 crew, 1 job, 1 block on the board", desk.describe())
	desk.add_job(JobScript.new("E2"))
	desk.book("E2", &"C1", WEDNESDAY, 900, 1020)
	assert(desk.describe() == "1 crew, 2 jobs, 2 blocks on the board, 1 conflict", desk.describe())


# --- a crew's day ------------------------------------------------------------------------------


func test_a_route_is_proposed_from_where_the_crew_starts_and_says_its_assumption() -> void:
	var desk := _desk()
	var member := _person(&"C1", "Dana")
	member.home_base = Vector2.ZERO
	desk.add_crew(member)
	desk.make_job_from(_estimate("E1"))
	desk.add_job(JobScript.new("E2"))
	desk.set_job_place("E1", Vector2(100.0, 0.0))
	desk.set_job_place("E2", Vector2(10.0, 0.0))
	desk.book("E1", &"C1", WEDNESDAY, 780, 900)   # placed first, furthest away
	desk.book("E2", &"C1", WEDNESDAY, 480, 600)
	var planned: Dictionary = desk.route_for(&"C1", WEDNESDAY)
	assert(bool(planned["ok"]), String(planned["reason"]))
	var route: Dictionary = planned["route"]
	assert(route["order"] == [1, 0], str(route["order"]))
	assert((route["late"] as Array).is_empty())
	assert(String(route["note"]).contains("nearest-neighbour"), String(route["note"]))
	assert(float(route["total_drive_minutes"]) > 0.0)
	assert(int(route["finish_minute"]) > 480)


func test_a_route_refuses_a_job_with_no_place_by_name() -> void:
	var desk := _desk()
	desk.add_crew(_person())
	desk.make_job_from(_estimate())
	desk.book("E1", &"C1", WEDNESDAY, 480, 960)
	var planned: Dictionary = desk.route_for(&"C1", WEDNESDAY)
	assert(not bool(planned["ok"]))
	assert(String(planned["reason"]).contains("Smith, back garden"), String(planned["reason"]))
	assert((planned["route"] as Dictionary).is_empty())


func test_a_route_for_nobody_on_the_crew_says_so() -> void:
	var desk := _desk()
	var planned: Dictionary = desk.route_for(&"C9", WEDNESDAY)
	assert(not bool(planned["ok"]))
	assert(String(planned["reason"]).contains("C9"))


func test_a_route_over_a_day_with_nothing_on_it_is_the_day_it_started() -> void:
	var desk := _desk()
	desk.add_crew(_person())
	var planned: Dictionary = desk.route_for(&"C1", WEDNESDAY, 420)
	assert(bool(planned["ok"]))
	assert(int((planned["route"] as Dictionary)["finish_minute"]) == 420)
	assert((planned["route"] as Dictionary)["order"].is_empty())


# --- the time ----------------------------------------------------------------------------------


func test_time_is_logged_once_and_only_if_it_reads() -> void:
	var desk := _desk()
	assert(not desk.log_time(null))
	assert(not desk.log_time(EntryScript.new("")))
	assert(desk.log_time(_entry()))
	assert(not desk.log_time(_entry()), "the same entry twice is one entry")
	var broken := _entry("T2")
	broken.ended_at = "2026-06-10T07:00:00"
	assert(not desk.log_time(broken), "an entry that ends before it starts is not work")
	assert(desk.time_entry("T1") != null)
	assert(desk.time_entry("T9") == null)


func test_only_an_approved_entry_becomes_cost_and_the_rest_is_reported_beside_it() -> void:
	var desk := _desk()
	desk.log_time(_entry())
	assert(desk.labour_on("E1").format() == "0.00", "nothing approved yet")
	var waiting: Dictionary = desk.pending_on("E1")
	assert(int(waiting["count"]) == 1)
	assert((waiting["total"] as MoneyScript).format() == "400.00", "8 hours at 50.00")
	assert(desk.approve_time("T1", "office"))
	assert(desk.labour_on("E1").format() == "400.00")
	assert(int(desk.pending_on("E1")["count"]) == 0)
	assert(desk.labour_on("E9").format() == "0.00", "a job with no time cost nothing")


func test_approving_needs_an_entry_that_reads_and_somebody_to_approve_it() -> void:
	var desk := _desk()
	desk.log_time(_entry())
	assert(not desk.approve_time("T1", "   "), "nobody approved it")
	assert(not desk.approve_time("T9", "office"), "and there is no such entry")
	assert(not desk.time_entry("T1").is_approved())
	assert(desk.approve_time("T1", "office"))


func test_an_unreadable_rate_poisons_the_labour_rather_than_reading_as_free() -> void:
	var desk := _desk()
	desk.log_time(_entry("T1", &"C1", 0))
	desk.time_entry("T1").loaded_rate = MoneyScript.invalid()
	desk.approve_time("T1", "office")
	assert(not desk.labour_on("E1").is_valid(), "a bad rate is not a rate of nothing")


func test_time_rows_read_the_way_a_timesheet_does() -> void:
	var desk := _desk()
	desk.add_crew(_person())
	desk.log_time(_entry())
	var row: Dictionary = desk.time_rows("E1")[0]
	assert(row["id"] == "T1")
	assert(row["crew_label"] == "Dana (Labourer)")
	assert(row["cost_code"] == "PLANTING")
	assert(int(row["minutes"]) == 480)
	assert((row["amount"] as MoneyScript).format() == "400.00")
	assert(not bool(row["approved"]))
	assert(String(row["problem"]).is_empty())
	assert(row["source_name"] == "typed in")


# --- the file ----------------------------------------------------------------------------------


## A desk through the file format, by the JSON text a file really holds: every number comes back a
## float, so the test that reads it back is the test that catches a cast that only worked in memory.
func test_the_desk_survives_the_file() -> void:
	var desk := _desk()
	desk.add_crew(_person())
	desk.make_job_from(_estimate())
	desk.set_job_place("E1", Vector2(3.5, -4.25))
	desk.book("E1", &"C1", WEDNESDAY, 480, 960)
	desk.log_time(_entry())
	desk.approve_time("T1", "office")
	var text := JSON.stringify(desk.to_dict())
	var restored: DeskScript = DeskScript.from_dict(JSON.parse_string(text))
	assert(restored.crew_ids() == desk.crew_ids(), str(restored.crew_ids()))
	assert(restored.job_ids() == ["E1"])
	assert(restored.job_label("E1") == "Smith, back garden")
	assert(restored.job_place("E1") == Vector2(3.5, -4.25), str(restored.job_place("E1")))
	assert(restored.block_count() == 1)
	assert(int(restored.blocks_on(WEDNESDAY)[0]["start_minute"]) == 480)
	assert(restored.time_entry("T1").is_approved(), "an approval is a record, not a session")
	assert(restored.labour_on("E1").format() == "400.00")
	assert(restored.describe() == desk.describe(), restored.describe())
	assert(restored.is_clear())


func test_a_damaged_record_is_dropped_and_the_rest_of_the_desk_reads() -> void:
	var good := {
		"job": "E1", "crew": "C1", "date": WEDNESDAY,
		"start_minute": 480, "end_minute": 960, "note": "",
	}
	var desk: DeskScript = DeskScript.from_dict({
		"crews": [{"id": "C1", "name": "Dana"}, {}, {"name": "nobody"}],
		"jobs": [{"id": "E1"}, {}],
		"schedule": {"entries": [good, {
			"job": "E1", "crew": "C1", "date": WEDNESDAY,
			"start_minute": 960, "end_minute": 480,
		}, {
			"job": "gone", "crew": "C1", "date": WEDNESDAY,
			"start_minute": 480, "end_minute": 960,
		}]},
		"time_entries": [{
			"id": "T1", "job": "E1", "crew_member": "C1",
			"started_at": "2026-06-10T08:00:00", "ended_at": "2026-06-10T16:00:00",
		}, {}, {"id": "T2"}],
		"job_places": {"E1": [1.0, 2.0], "gone": [5.0, 6.0]},
	})
	assert(desk.crew_ids() == [&"C1"], str(desk.crew_ids()))
	assert(desk.job_ids() == ["E1"])
	assert(desk.block_count() == 1, "a block that cannot place is not a block")
	assert(desk.time_entry("T1") != null)
	assert(desk.time_entry("") == null)
	assert(desk.time_entry("T2") == null, "an entry that does not read is not a record of work")
	assert(desk.job_place("E1") == Vector2(1.0, 2.0))
	assert(not desk.has_job_place("gone"), "a place for a job nobody has is not a place")