extends Node
## The schedule board: a column per day, a block per crew day, and every clash listed (spec §7.4).
##
## The board owns no arithmetic - the blocks, the clashes and the route are the desk's - so these tests
## hold three things: that a block lands in the right day's column, that a time a person cannot have
## meant is refused rather than booked, and that nothing here ever moves a block to avoid a clash.
##
## Each test frees the window it built, which is what the other window tests do: a `Window` is a tree
## with a viewport, and letting one live to engine exit is a leaked resource.

const BoardScript := preload("res://scripts/schedule_board.gd")
const DeskScript := preload("res://scripts/biz/job_desk.gd")
const JobScript := preload("res://scripts/biz/job.gd")
const CrewScript := preload("res://scripts/biz/crew.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")

const WEDNESDAY := "2026-06-10"
const THURSDAY := "2026-06-11"


func _desk(with_job: bool = true, with_crew: bool = true) -> DeskScript:
	var desk: DeskScript = DeskScript.new()
	if with_crew:
		var member: CrewScript = CrewScript.new(&"C1", "Dana")
		member.add_rate("2026-01-01", MoneyScript.of(4500))
		desk.add_crew(member)
	if with_job:
		var job: JobScript = JobScript.new("E1")
		job.name = "Smith"
		desk.add_job(job)
	return desk


func _board(desk: DeskScript) -> BoardScript:
	var board: BoardScript = BoardScript.new()
	board.build()
	board.bind(desk)
	return board


func _day_node(board: BoardScript, date: String) -> Node:
	return board.get_node_or_null(NodePath("Column/Scroll/Board/Day%s" % date))


# --- the clock ---------------------------------------------------------------------------------


func test_the_clock_is_read_and_written_one_way() -> void:
	assert(BoardScript.parse_clock("8:00") == 480)
	assert(BoardScript.parse_clock("16:30") == 990)
	assert(BoardScript.parse_clock(" 6:05 ") == 365)
	assert(BoardScript.parse_clock("24:00") == 1440, "the end of a block that runs to midnight")
	assert(BoardScript.parse_clock("") == -1)
	assert(BoardScript.parse_clock("8") == -1)
	assert(BoardScript.parse_clock("eight") == -1)
	assert(BoardScript.parse_clock("8:xy") == -1)
	assert(BoardScript.parse_clock("25:00") == -1)
	assert(BoardScript.parse_clock("8:60") == -1)
	assert(BoardScript.clock_words(480) == "8:00")
	assert(BoardScript.clock_words(990) == "16:30")
	assert(BoardScript.clock_words(1440) == "24:00")
	assert(BoardScript.clock_words(-1) == "?")
	assert(BoardScript.clock_words(2000) == "?")


# --- building ----------------------------------------------------------------------------------


func test_a_board_with_no_desk_is_empty_rather_than_broken() -> void:
	var board: BoardScript = BoardScript.new()
	board.build()
	board.bind(null)
	# The week is still drawn, from today: a board with no columns is a board nothing can be put on.
	assert(board.day_titles().size() == BoardScript.DAYS_SHOWN)
	assert(board.day_titles()[0] == Time.get_date_string_from_system(true))
	assert(board.summary_text() == "no crews and no jobs yet", board.summary_text())
	assert(board.block_texts(WEDNESDAY).is_empty())
	assert(board.conflict_texts().is_empty())
	board.free()


func test_building_twice_is_the_same_board() -> void:
	var desk := _desk()
	desk.book("E1", &"C1", WEDNESDAY, 480, 960)
	var board := _board(desk)
	board.build()
	assert(board.block_count(WEDNESDAY) == 1, "a second build did not wipe the board")
	board.free()


func test_the_board_is_a_week_starting_at_the_first_day_with_work_on_it() -> void:
	var desk := _desk()
	desk.book("E1", &"C1", THURSDAY, 480, 960)
	desk.book("E1", &"C1", WEDNESDAY, 480, 960)
	var board := _board(desk)
	assert(board.day_titles().size() == BoardScript.DAYS_SHOWN, "a week, not only the days worked")
	assert(board.day_titles()[0] == WEDNESDAY, "the earliest day with work on it comes first")
	assert(board.day_titles()[1] == THURSDAY)
	assert(_day_node(board, WEDNESDAY) != null, "each day is a node a block can be dropped on")
	assert(_day_node(board, THURSDAY) != null)
	assert(board.day_texts()[0] == "%s (1)" % WEDNESDAY)
	assert(board.day_texts()[2].ends_with(" (0)"), "a day with nothing on it still has a column")
	board.free()


func test_a_block_carries_the_job_the_hours_and_the_person() -> void:
	var desk := _desk()
	desk.book("E1", &"C1", WEDNESDAY, 480, 960)
	var board := _board(desk)
	assert(board.block_texts(WEDNESDAY) == ["Smith  8:00-16:00\nDana (Labourer)"],
		str(board.block_texts(WEDNESDAY)))
	assert(board.block_count(WEDNESDAY) == 1)
	assert(board.block_count(THURSDAY) == 0)
	board.free()


# --- the pickers -------------------------------------------------------------------------------


func test_the_two_pickers_list_what_the_desk_has() -> void:
	var desk := _desk()
	var board := _board(desk)
	assert(board.selected_job() == "E1", "the only job is the one chosen")
	assert(board.selected_crew() == "C1")
	assert(not board.choose_job("gone"), "a job the desk does not have cannot be chosen")
	assert(not board.choose_crew("gone"))
	assert(board.choose_job("E1"))
	assert(board.choose_crew("C1"))
	board.free()


func test_the_book_button_is_dead_until_there_is_a_job_and_a_crew() -> void:
	var empty := _desk(false, false)
	var board := _board(empty)
	assert(board.book_button_disabled())
	assert(board.book_hint() == "no job yet: a job is made from an estimate", board.book_hint())
	board.bind(_desk(true, false))
	assert(board.book_button_disabled())
	assert(board.book_hint() == "nobody is on the crew yet", board.book_hint())
	board.bind(_desk())
	assert(not board.book_button_disabled(), "with a job and a person it can be pressed")
	assert(board.book_hint().is_empty())
	board.free()


func test_putting_somebody_on_the_crew_from_the_fields() -> void:
	var desk := _desk(true, false)
	var board := _board(desk)
	assert(not board.add_crew_from_fields(), "a name is what makes a person a person")
	assert(board.status_text() == "A crew member needs a name.", board.status_text())
	board.set_crew_fields("Sam", &"FOREMAN")
	assert(board.add_crew_from_fields())
	assert(desk.crew_ids().size() == 1)
	var taken: Array = desk.crew_rows(WEDNESDAY)
	assert(taken[0]["name"] == "Sam")
	assert(taken[0]["role_name"] == "Foreman")
	assert(board.status_text() == "Sam is on the crew, as Foreman.", board.status_text())
	board.free()


# --- booking -----------------------------------------------------------------------------------


func test_booking_reads_the_row_and_books_it() -> void:
	var desk := _desk()
	var board := _board(desk)
	board.set_date(WEDNESDAY)
	board.set_window("8:00", "16:00")
	board.set_note("first day")
	var booked: Dictionary = board.book_selected()
	assert(bool(booked["ok"]), String(booked["reason"]))
	assert(desk.block_count() == 1)
	assert(board.block_count(WEDNESDAY) == 1)
	assert(board.status_text() == "Booked Smith on 2026-06-10, 8:00 to 16:00.", board.status_text())
	assert(desk.blocks_on(WEDNESDAY)[0]["note"] == "first day", "the note travels")
	board.free()


func test_a_time_that_cannot_be_read_is_refused_in_words() -> void:
	var desk := _desk()
	var board := _board(desk)
	board.set_date(WEDNESDAY)
	board.set_window("eight", "16:00")
	var refused: Dictionary = board.book_selected()
	assert(not bool(refused["ok"]))
	assert(String(refused["reason"]) == "the times read like 8:00 and 16:00", String(refused["reason"]))
	assert(desk.block_count() == 0, "and nothing was booked at midnight")
	assert(board.status_text() == "Not booked: the times read like 8:00 and 16:00.", board.status_text())
	board.free()


func test_booking_with_no_job_or_no_crew_says_which() -> void:
	var board := _board(_desk(false, true))
	assert(not bool(board.book_selected()["ok"]))
	assert(board.status_text() == "There is no job to book: a job is made from an estimate.",
		board.status_text())
	board.bind(_desk(true, false))
	assert(not bool(board.book_selected()["ok"]))
	assert(board.status_text() == "There is nobody on the crew yet: put somebody on it below.",
		board.status_text())
	board.free()


func test_a_clash_is_listed_and_nothing_is_moved_to_avoid_it() -> void:
	var desk := _desk()
	desk.add_job(JobScript.new("E2"))
	desk.book("E1", &"C1", WEDNESDAY, 480, 960)
	desk.book("E2", &"C1", WEDNESDAY, 900, 1020)
	var board := _board(desk)
	assert(board.conflict_texts().size() == 1, str(board.conflict_texts()))
	assert(board.conflict_texts()[0].contains("two windows at once"), board.conflict_texts()[0])
	assert(board.block_count(WEDNESDAY) == 2, "both blocks stand where they were put")
	board.free()


func test_a_board_opens_saying_what_to_do_with_it() -> void:
	var empty := _desk()
	var board := _board(empty)
	assert(board.status_text() == "Nothing is booked yet: put somebody on the crew, then book a day.",
		board.status_text())
	var working := _desk()
	working.book("E1", &"C1", WEDNESDAY, 480, 960)
	board.bind(working)
	assert(board.status_text() == "Click a block to pick it up; drag it to another day's column to move it.",
		board.status_text())
	board.free()


func test_the_summary_counts_the_days_the_board_is_spread_over() -> void:
	var desk := _desk()
	desk.book("E1", &"C1", WEDNESDAY, 480, 960)
	var board := _board(desk)
	assert(board.summary_text() == "1 crew, 1 job, 1 block on the board, over 1 day",
		board.summary_text())
	board.free()


# --- moving and taking off ---------------------------------------------------------------------


func test_moving_a_block_to_another_day_keeps_its_window() -> void:
	var desk := _desk()
	desk.book("E1", &"C1", WEDNESDAY, 480, 960)
	var board := _board(desk)
	assert(board.move_block(0, THURSDAY))
	assert(board.block_count(WEDNESDAY) == 0)
	assert(board.block_count(THURSDAY) == 1)
	assert(board.block_texts(THURSDAY) == ["Smith  8:00-16:00\nDana (Labourer)"],
		"the hours travelled with it")
	assert(String(desk.job("E1").schedule[0]["date"]) == THURSDAY, "and so did the job's own copy")
	assert(not board.move_block(9, THURSDAY), "a block that is not there cannot move")
	board.free()


func test_a_drop_on_a_day_moves_the_block_to_that_day() -> void:
	var desk := _desk()
	desk.book("E1", &"C1", WEDNESDAY, 480, 960)
	var board := _board(desk)
	var target: Node = _day_node(board, THURSDAY)
	assert(target != null)
	assert(target._can_drop_data(Vector2.ZERO, {"block": 0}), "a day takes a block")
	assert(not target._can_drop_data(Vector2.ZERO, {"job": "E1"}), "and nothing else")
	target._drop_data(Vector2.ZERO, {"block": 0})
	assert(board.block_count(THURSDAY) == 1)
	assert(board.block_count(WEDNESDAY) == 0)
	# The drop's own callback cannot rebuild the columns - it would free the column that is running -
	# so the picture is rebuilt on the next frame. Here, now, so the column can be read.
	board.refresh()
	var landed: Node = _day_node(board, THURSDAY)
	assert(landed != null)
	assert(landed.get_node_or_null(^"Header").text == "%s (1)" % THURSDAY,
		landed.get_node_or_null(^"Header").text)
	# The week follows the work: with nothing left on Wednesday the board starts at Thursday.
	assert(board.day_titles()[0] == THURSDAY)
	assert(_day_node(board, WEDNESDAY) == null)
	board.free()


func test_clicking_a_block_selects_it_and_taking_it_off_removes_it() -> void:
	var desk := _desk()
	desk.book("E1", &"C1", WEDNESDAY, 480, 960)
	var board := _board(desk)
	assert(board.selected_block() == -1, "nothing is selected to start with")
	board._on_remove()
	assert(board.status_text() == "Click a block first, then take it off.", board.status_text())
	board._on_block_pressed(0)
	assert(board.selected_block() == 0)
	assert(board.status_text() == "Smith on 2026-06-10, 8:00 to 16:00, Dana (Labourer).",
		board.status_text())
	board._on_remove()
	assert(desk.block_count() == 0)
	assert(board.selected_block() == -1, "and nothing is selected once it is gone")
	assert(board.status_text() == "Taken off the board.", board.status_text())
	board.free()


# --- the keyboard ------------------------------------------------------------------------------


func test_every_button_on_the_board_is_focus_free() -> void:
	var board := _board(_desk())
	assert(board.buttons_are_focus_free(), "nothing here may take the drawing's keys")
	board.free()