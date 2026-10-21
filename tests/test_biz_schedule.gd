extends Node
## The schedule board: blocks placed and moved, and conflicts **reported** and never auto-resolved
## (spec §7.4).

const ScheduleScript := preload("res://scripts/biz/schedule.gd")
const CrewScript := preload("res://scripts/biz/crew.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")


func test_a_block_that_ends_before_it_starts_is_not_a_block() -> void:
	var board: ScheduleScript = ScheduleScript.new()
	assert(not board.place("J1", &"C1", "2026-06-01", 600, 600)["ok"], "zero work is not a booking")
	assert(not board.place("J1", &"C1", "2026-06-01", 600, 500)["ok"])
	assert(not board.place("J1", &"C1", "", 480, 600)["ok"], "a block needs a date")
	assert(not board.place("J1", &"C1", "2026-06-01", -30, 600)["ok"], "and sits inside the day")
	assert(not board.place("J1", &"C1", "2026-06-01", 480, 2000)["ok"])
	assert(board.count() == 0)


func test_place_move_and_remove() -> void:
	var board: ScheduleScript = ScheduleScript.new()
	var placed := board.place("J1", &"C1", "2026-06-01", 480, 660)
	assert(placed["ok"] and int(placed["index"]) == 0)
	assert(board.count() == 1)
	assert(board.move(0, 600, 780))
	assert(int(board.on_date("2026-06-01")[0]["start_minute"]) == 600)
	assert(board.move_to(0, "2026-06-02", 480, 600), "and moved to another day")
	assert(board.on_date("2026-06-01").is_empty())
	var dates := board.dates()
	assert(dates == ["2026-06-02"], str(dates))
	assert(board.remove(0))
	assert(board.count() == 0)


func test_a_crew_double_booking_is_reported_naming_the_windows() -> void:
	var board: ScheduleScript = ScheduleScript.new()
	board.place("J1", &"C1", "2026-06-01", 480, 600)
	board.place("J2", &"C1", "2026-06-01", 540, 660)
	var conflicts := board.conflicts()
	assert(conflicts.size() == 1, str(conflicts.size()))
	assert(String(conflicts[0]["kind"]) == "CREW_DOUBLE_BOOKED")
	assert(String(conflicts[0]["detail"]).contains("480-600"), String(conflicts[0]["detail"]))
	assert(String(conflicts[0]["detail"]).contains("540-660"))


func test_the_same_job_with_two_crews_on_one_day_is_reported() -> void:
	var board: ScheduleScript = ScheduleScript.new()
	board.place("J1", &"C1", "2026-06-01", 480, 600)
	board.place("J1", &"C2", "2026-06-01", 600, 720)
	var conflicts := board.conflicts()
	assert(conflicts.size() == 1)
	assert(String(conflicts[0]["kind"]) == "JOB_TWO_CREWS")
	assert(String(conflicts[0]["detail"]).contains("C1") and String(conflicts[0]["detail"]).contains("C2"))


func test_a_crew_member_scheduled_on_a_day_off_is_reported() -> void:
	var board: ScheduleScript = ScheduleScript.new()
	var dana: CrewScript = CrewScript.new(&"C1", "Dana")
	dana.add_availability({"kind": "VACATION", "from": "2026-06-15", "to": "2026-06-22"})
	board.know_crew(dana)
	board.place("J1", &"C1", "2026-06-18", 480, 600)
	var conflicts := board.conflicts()
	assert(conflicts.size() == 1 and String(conflicts[0]["kind"]) == "UNAVAILABLE")
	assert(String(conflicts[0]["detail"]).contains("vacation"))
	# A board with no crew records simply has no availability to report against.
	var blind: ScheduleScript = ScheduleScript.new()
	blind.place("J1", &"C1", "2026-06-18", 480, 600)
	assert(blind.is_clear())


func test_a_clean_board_has_no_conflicts() -> void:
	var board: ScheduleScript = ScheduleScript.new()
	board.place("J1", &"C1", "2026-06-01", 480, 600)
	board.place("J2", &"C2", "2026-06-01", 480, 600)
	board.place("J1", &"C1", "2026-06-02", 480, 600)
	assert(board.is_clear(), str(board.conflicts()))
	assert(board.conflict_count() == 0)


func test_conflicts_are_listed_in_the_same_order_every_time() -> void:
	var board: ScheduleScript = ScheduleScript.new()
	board.place("J1", &"C2", "2026-06-02", 480, 600)
	board.place("J2", &"C2", "2026-06-02", 540, 660)
	board.place("J1", &"C1", "2026-06-01", 480, 600)
	board.place("J2", &"C1", "2026-06-01", 540, 660)
	var conflicts := board.conflicts()
	assert(conflicts.size() == 2)
	assert(String(conflicts[0]["date"]) == "2026-06-01", "the earlier day first")
	assert(String(conflicts[1]["date"]) == "2026-06-02")


func test_the_board_round_trips_and_drops_a_block_that_will_not_place() -> void:
	var board: ScheduleScript = ScheduleScript.new()
	board.place("J1", &"C1", "2026-06-01", 480, 600)
	board.place("J2", &"C2", "2026-06-02", 600, 720)
	var restored: ScheduleScript = ScheduleScript.from_dict(board.to_dict())
	assert(restored.count() == 2)
	assert(String(restored.on_date("2026-06-01")[0]["job"]) == "J1")
	# A block whose window is nonsense is a damaged record, not a block the board cannot point at.
	var damaged: ScheduleScript = ScheduleScript.from_dict(
		{"entries": [{"job": "J1", "crew": "C1", "date": "d", "start_minute": 600, "end_minute": 600}]})
	assert(damaged.count() == 0)