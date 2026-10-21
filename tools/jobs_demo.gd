extends Node2D
## A live pass over the jobs and the crews: an estimate taken off the plan, a job made from it, a crew
## put on, days booked, the clashes the board reports, and a crew's day as a route.
##
## This is a development tool, not part of the game. It instances the **real main scene** and drives the
## **real window and board** through the methods their controls call, so the desk, the board, the
## estimate window and the HUD's menu line are all the shipped ones, and it prints every step. The
## screenshot at the end is the schedule board over the drawing the job was priced from.
##
## Run `res://scenes/jobs_demo.tscn`.

const MAIN := preload("res://scenes/main.tscn")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")

const MONDAY := "2026-06-08"
const TUESDAY := "2026-06-09"


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	var hud: Node = main.get_node_or_null(^"Hud")
	var controller: Node = main.get_node_or_null(^"DraftController")
	if hud == null or controller == null:
		print("no HUD or no drafting controller in the main scene")
		return

	print("--- a plan worth pricing: a patio and a bed ---")
	controller.document.add(
		Entity.make_rectangle(Vector2(0, 0), Vector2(6, 4)), LayerSet.NEW_HARDSCAPE
	)
	controller.document.add(Entity.make_circle(Vector2(20, 0), 1.5), LayerSet.NEW_PLANTING)
	print("the drawing holds ", controller.document.count(), " shapes")

	print("--- the estimate, taken off the plan as the button does ---")
	hud.open_estimate_window()
	print("before: ", hud._estimate_text())
	hud._estimate_window.take_off()
	print("after:  ", hud._estimate_text())
	print("the window says: ", hud._estimate_window.status_text())
	print("the job button is dead: ", hud._estimate_window.start_job_button_disabled())

	print("--- sent to the customer, because a job is a proposal that came back won ---")
	hud._estimate_window.set_recipient("Smith, back garden")
	hud._estimate_window.send_it()
	print("the window says: ", hud._estimate_window.status_text())

	print("--- a job made from the estimate, which is the hand-off ---")
	print("the Jobs menu said: ", hud._jobs_text())
	var started: Dictionary = hud._estimate_window.start_job()
	print("the hand-off was accepted: ", started["ok"])
	print("the window says: ", hud._estimate_window.status_text())
	print("the Jobs menu says: ", hud._jobs_text())
	var job_id: String = hud._job_desk.job_ids()[0]
	var job: Job = hud._job_desk.job(job_id)
	print("the job carries ", job.phases.size(), " phases and is contracted at ",
		job.contract_sum.format_with_currency())
	for row: Dictionary in hud._job_desk.job_rows():
		print("  ", row["name"], "  ", (row["contract_sum"] as MoneyScript).format(),
			"  billed ", row["billing_name"], "  revision ", row["estimate_revision"])

	print("--- the board, and a crew on it ---")
	hud.open_schedule_board()
	print("the board is up: ", hud.is_schedule_board_open())
	var board: Node = hud._schedule_board
	print("it opens saying: ", board.status_text())
	board.set_crew_fields("Dana", &"FOREMAN")
	board.add_crew_from_fields()
	board.set_crew_fields("Sam", &"LABOURER")
	board.add_crew_from_fields()
	print("the crew is: ", hud._job_desk.crew_names())

	print("--- booking three days of work ---")
	board.choose_job(job_id)
	board.choose_crew(String(hud._job_desk.crew_ids()[0]))
	board.set_date(MONDAY)
	board.set_window("8:00", "16:00")
	board.set_note("set out and plant")
	print("Dana, Monday: ", board.book_selected())
	board.choose_crew(String(hud._job_desk.crew_ids()[1]))
	print("Sam, the same Monday: ", board.book_selected())
	board.choose_crew(String(hud._job_desk.crew_ids()[0]))
	board.set_window("15:00", "17:00")
	print("Dana again, overlapping: ", board.book_selected())
	print("the board says: ", board.status_text())
	print("the desk says: ", hud._jobs_text())

	print("--- what the board reports, and only reports ---")
	for line: String in board.conflict_texts():
		print("  ", line)
	print("there are ", hud._job_desk.conflict_count(), " clashes and ",
		hud._job_desk.block_count(), " blocks: nothing was rearranged to avoid one")

	print("--- moving Dana's second block to Tuesday ---")
	var moved: bool = board.move_block(2, TUESDAY)
	print("moved: ", moved, "  the board says: ", board.status_text())
	for line: String in board.conflict_texts():
		print("  ", line)

	print("--- the days on the board ---")
	for date: String in board.day_titles():
		print("  ", date, " (", board.block_count(date), ")")
	for text: String in board.block_texts(MONDAY):
		print("  ", text.replace("\n", "  "))

	print("--- Dana's Monday, as a route ---")
	var planned: Dictionary = hud._job_desk.route_for(
		StringName(hud._job_desk.crew_ids()[0]), MONDAY
	)
	if not bool(planned["ok"]):
		print("no route: ", planned["reason"], " - so the job gets a place on the drawing")
		hud._job_desk.set_job_place(job_id, Vector2(10.0, 10.0))
		planned = hud._job_desk.route_for(StringName(hud._job_desk.crew_ids()[0]), MONDAY)
	print("planned: ", planned["ok"], "  ", str((planned["route"] as Dictionary).get("note", "")))
	print("the stops come in this order: ", (planned["route"] as Dictionary).get("order", []))
	print("the day finishes at minute ",
		int((planned["route"] as Dictionary).get("finish_minute", 0)),
		" of which ", snappedf(float((planned["route"] as Dictionary).get("total_drive_minutes", 0.0)), 0.1),
		" are driving")

	print("--- taking a block off ---")
	board._on_block_pressed(0)
	board._on_remove()
	print("the board says: ", board.status_text())
	print("and the desk now says: ", hud._jobs_text())

	print("--- what is left on screen ---")
	print("the board is up: ", hud.is_schedule_board_open(), ", the Jobs menu reads: ", hud._jobs_text())