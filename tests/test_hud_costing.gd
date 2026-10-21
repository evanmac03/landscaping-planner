extends Node
## The HUD's side of job costing: the Jobs menu's second way in, and what the desk's own words make
## that menu say (spec §8.4).
##
## The desk and the page are built by hand here and never shown: what is under test is the wiring, and
## the page is never popped up, because a `Window` popped up with no tree to hang it on hangs the
## process.

const HudScript := preload("res://scripts/hud.gd")
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


## An estimate with one priced line, so a job can be made of it: 10 x 15.00 of PLANTING.
func _estimate() -> EstimateScript:
	var estimate: EstimateScript = EstimateScript.new("E1")
	estimate.customer = {"name": "Smith"}
	var line: LineScript = LineScript.new()
	line.description = "Buxus, 2 gal"
	line.cost_code = &"PLANTING"
	line.kind = ItemScript.MATERIAL
	line.quantity_milli = 10000
	line.unit = &"EACH"
	line.unit_cost = MoneyScript.of(500)
	line.unit_price = MoneyScript.of(1500)
	estimate.lines.append(line)
	return estimate


# --- the way in ------------------------------------------------------------------------------


func test_the_jobs_menu_offers_what_a_job_has_cost() -> void:
	var entry: Dictionary = _entry(&"jobs.cost")
	assert(String(entry["label"]) == "What the job has cost...", String(entry["label"]))
	assert(StringName(entry["method"]) == &"_menu_cost_window", String(entry["method"]))
	assert(entry["needs"] == HudScript.NEEDS_NOTHING, "what a job has cost is not on the plan")
	var ids: Array[String] = []
	for listed: Dictionary in HudScript.items_for("Jobs"):
		ids.append(String(listed.get("id", "")))
	assert(ids.has("jobs.info"), "the menu reports the desk")
	assert(ids.has("jobs.board"), "and offers the board")
	assert(ids.has("jobs.cost"), "and the cost report")
	var hud := HudScript.new()
	assert(hud.has_method(String(entry["method"])), "the method the entry names exists")
	_done(hud)


func test_a_hud_with_no_page_reports_nothing_open() -> void:
	var hud := HudScript.new()
	assert(not hud.is_cost_window_open(), "and nothing is open")
	hud.close_cost_window()
	assert(not hud.is_cost_window_open())
	_done(hud)


func test_building_the_page_gives_the_menu_something_to_open() -> void:
	var hud := HudScript.new()
	hud._build_cost_window()
	assert(hud._cost_window != null, "the page was built")
	assert(hud._cost_window.get_parent() == hud, "and it is the HUD's own child")
	assert(hud._cost_window.desk == hud._job_desk, "pointed at this desk")
	assert(not hud.is_cost_window_open(), "built is not shown")
	_done(hud)


# --- what the desk's words make the menu say --------------------------------------------------


func test_an_order_placed_through_the_page_is_in_the_menu_line() -> void:
	var hud := HudScript.new()
	hud._build_cost_window()
	hud._on_job_started(_estimate())
	assert(hud._jobs_text() == "0 crews, 1 job, 0 blocks on the board", hud._jobs_text())
	# What the page does to the desk, the menu line reads back at once: the signal is the wiring.
	assert(hud._job_desk.make_purchase_order("E1", &"PLANTING", "Buxus", 10000,
		MoneyScript.of(1000), "Greenline Nursery") != null)
	hud._job_desk.issue_purchase_order("PO-001", "2026-06-01")
	hud._on_cost_changed()
	assert(hud._jobs_text() == "0 crews, 1 job, 0 blocks on the board, "
		+ "1 purchase order ($100.00 committed)", hud._jobs_text())
	hud._cost_window.cost_changed.emit()
	assert(hud._jobs_text().contains("$100.00 committed"), hud._jobs_text())
	_done(hud)


func test_agreeing_to_a_change_order_moves_the_menu_line() -> void:
	var hud := HudScript.new()
	hud._build_cost_window()
	hud._on_job_started(_estimate())
	hud._job_desk.make_change_order("E1", &"SITE_CONDITION", "A wall", MoneyScript.of(50000),
		&"PLANTING")
	hud._on_cost_changed()
	assert(hud._jobs_text().contains("1 change order ($0.00 agreed, 1 pending)"), hud._jobs_text())
	hud._job_desk.approve_change("CO-001", "Dana", "2026-07-01", "in-app")
	hud._on_cost_changed()
	assert(hud._jobs_text().contains("1 change order ($500.00 agreed)"), hud._jobs_text())
	_done(hud)


func test_the_page_and_the_board_are_both_pointed_at_the_one_desk() -> void:
	var hud := HudScript.new()
	hud._build_schedule_board()
	hud._build_cost_window()
	assert(hud._schedule_board.desk == hud._cost_window.desk, "one desk, read by both")
	assert(hud._cost_window.desk == hud._job_desk, "and it is the HUD's own")
	_done(hud)