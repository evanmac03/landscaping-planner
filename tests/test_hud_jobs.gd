extends Node
## The HUD's side of the jobs: the Jobs menu's way in, and what the desk's own words make it say.
##
## The desk and the board are built by hand here and never shown: what is under test is the wiring, and
## the board is never popped up, because a `Window` popped up with no tree to hang it on hangs the
## process.

const HudScript := preload("res://scripts/hud.gd")
const JobScript := preload("res://scripts/biz/job.gd")
const CrewScript := preload("res://scripts/biz/crew.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")
const EstimateScript := preload("res://scripts/biz/estimate.gd")
const LineScript := preload("res://scripts/biz/estimate_line.gd")
const ItemScript := preload("res://scripts/biz/cost_item.gd")


func _done(hud) -> void:
	hud.free()


func _entry(id: StringName) -> Dictionary:
	for entry: Dictionary in HudScript.menu_entries():
		if StringName(entry.get("id", &"")) == id:
			return entry
	assert(false, "no menu entry with id %s" % String(id))
	return {}


## An estimate with one priced line, so a job can be made of it.
func _estimate() -> EstimateScript:
	var estimate: EstimateScript = EstimateScript.new("E1")
	estimate.customer = {"name": "Smith"}
	var line: LineScript = LineScript.new()
	line.cost_code = &"PLANTING"
	line.kind = ItemScript.MATERIAL
	line.quantity_milli = 10000
	line.unit = &"EACH"
	line.unit_cost = MoneyScript.of(500)
	line.unit_price = MoneyScript.of(1500)
	estimate.lines.append(line)
	return estimate


# --- the way in ------------------------------------------------------------------------------


func test_the_jobs_menu_offers_the_board() -> void:
	var entry: Dictionary = _entry(&"jobs.board")
	assert(String(entry["label"]) == "Open the schedule board...", String(entry["label"]))
	assert(StringName(entry["method"]) == &"_menu_schedule_board", String(entry["method"]))
	# A crew and a job are business data, not drawing data, so the entry needs nothing open.
	assert(entry["needs"] == HudScript.NEEDS_NOTHING, "the board needs no drawing")
	var ids: Array[String] = []
	for listed: Dictionary in HudScript.items_for("Jobs"):
		ids.append(String(listed.get("id", "")))
	assert(ids.has("jobs.info"), "the menu reports the desk")
	assert(ids.has("jobs.board"), "and offers the board")
	var hud := HudScript.new()
	assert(hud.has_method(String(entry["method"])), "the method the entry names exists")
	_done(hud)


func test_a_hud_with_no_desk_reports_no_crews() -> void:
	var hud := HudScript.new()
	assert(hud._jobs_text() == "no crews and no jobs yet", hud._jobs_text())
	assert(not hud.is_schedule_board_open(), "and nothing is open")
	_done(hud)


func test_building_the_desk_gives_the_menu_a_line_to_read() -> void:
	var hud := HudScript.new()
	hud._build_job_desk()
	assert(hud._job_desk != null, "the desk was built")
	hud._build_schedule_board()
	assert(hud._schedule_board != null, "the board was built")
	assert(hud._schedule_board.get_parent() == hud, "and it is the HUD's own child")
	assert(hud._schedule_board.desk == hud._job_desk, "pointed at this desk")
	assert(hud._jobs_text() == "no crews and no jobs yet", hud._jobs_text())
	_done(hud)


func test_a_board_built_but_not_shown_is_not_open() -> void:
	var hud := HudScript.new()
	hud._build_schedule_board()
	assert(not hud.is_schedule_board_open(), "built is not shown")
	hud.close_schedule_board()
	assert(not hud.is_schedule_board_open())
	_done(hud)


# --- what the desk's words make the menu say --------------------------------------------------


func test_a_job_started_from_the_estimate_lands_on_the_desk() -> void:
	var hud := HudScript.new()
	hud._build_job_desk()
	# The estimate window hands the estimate over; this is where it arrives.
	hud._on_job_started(_estimate())
	assert(hud._job_desk.job_ids() == ["E1"], str(hud._job_desk.job_ids()))
	assert(hud._job_desk.job_label("E1") == "Smith")
	assert(hud._jobs_text() == "0 crews, 1 job, 0 blocks on the board", hud._jobs_text())
	assert(hud.is_schedule_board_open() == false, "and nothing was opened by it")
	_done(hud)


func test_a_job_arriving_with_no_desk_builds_it() -> void:
	# A HUD whose `_ready` never ran still keeps the job: the hand-off must not need the menu bar.
	var hud := HudScript.new()
	hud._on_job_started(_estimate())
	assert(hud._job_desk != null, "the desk was built on the spot")
	assert(hud._job_desk.job_ids() == ["E1"])
	_done(hud)


func test_the_menu_line_counts_the_blocks_and_the_clashes() -> void:
	var hud := HudScript.new()
	hud._build_job_desk()
	var member: CrewScript = CrewScript.new(&"C1", "Dana")
	member.add_rate("2026-01-01", MoneyScript.of(4500))
	hud._job_desk.add_crew(member)
	hud._on_job_started(_estimate())
	hud._job_desk.add_job(JobScript.new("E2"))
	hud._job_desk.book("E1", &"C1", "2026-06-10", 480, 960)
	assert(hud._jobs_text() == "1 crew, 2 jobs, 1 block on the board", hud._jobs_text())
	hud._job_desk.book("E2", &"C1", "2026-06-10", 900, 1020)
	assert(hud._jobs_text() == "1 crew, 2 jobs, 2 blocks on the board, 1 conflict",
		hud._jobs_text())
	_done(hud)