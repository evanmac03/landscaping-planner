extends Node
## The HUD's side of billing: the Jobs menu's third way in, and what the ledger's own words make that
## menu say (spec §9).
##
## The ledger and the page are built by hand here and never shown: what is under test is the wiring, and
## the page is never popped up, because a `Window` popped up with no tree to hang it on hangs the
## process.

const HudScript := preload("res://scripts/hud.gd")
const JobScript := preload("res://scripts/biz/job.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")
const EstimateScript := preload("res://scripts/biz/estimate.gd")
const LineScript := preload("res://scripts/biz/estimate_line.gd")
const ItemScript := preload("res://scripts/biz/cost_item.gd")

const JOBS_LINE := "0 crews, 1 job, 0 blocks on the board"


func _done(hud) -> void:
	hud.free()


func _entry(id: StringName) -> Dictionary:
	for entry: Dictionary in HudScript.menu_entries():
		if StringName(entry.get("id", &"")) == id:
			return entry
	assert(false, "no menu entry with id %s" % String(id))
	return {}


## An estimate with one priced line, so a job can be made of it: 10 x $15.00 of PLANTING, a contract of
## $150.00, so a fixed-price job bills one round invoice.
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


func test_the_jobs_menu_offers_what_has_been_billed() -> void:
	var entry: Dictionary = _entry(&"jobs.billing")
	assert(String(entry["label"]) == "What has been billed...", String(entry["label"]))
	assert(StringName(entry["method"]) == &"_menu_billing_window", String(entry["method"]))
	assert(entry["needs"] == HudScript.NEEDS_NOTHING, "what has been billed is not on the plan")
	var ids: Array[String] = []
	for listed: Dictionary in HudScript.items_for("Jobs"):
		ids.append(String(listed.get("id", "")))
	assert(ids.has("jobs.info"), "the menu reports the desk")
	assert(ids.has("jobs.board"), "and offers the board")
	assert(ids.has("jobs.cost"), "and the cost report")
	assert(ids.has("jobs.billing"), "and what has been billed")
	var hud := HudScript.new()
	assert(hud.has_method(String(entry["method"])), "the method the entry names exists")
	_done(hud)


func test_a_hud_with_no_page_reports_nothing_open() -> void:
	var hud := HudScript.new()
	assert(not hud.is_billing_window_open(), "and nothing is open")
	hud.close_billing_window()
	assert(not hud.is_billing_window_open())
	_done(hud)


func test_building_the_page_gives_the_menu_something_to_open() -> void:
	var hud := HudScript.new()
	hud._build_billing_window()
	assert(hud._billing_ledger != null, "the ledger was built")
	assert(hud._billing_window != null, "and so was the page")
	assert(hud._billing_window.get_parent() == hud, "it is the HUD's own child")
	assert(hud._billing_ledger.desk == hud._job_desk, "pointed at this desk")
	assert(not hud.is_billing_window_open(), "built is not shown")
	_done(hud)


func test_the_billing_ledger_and_the_board_are_both_pointed_at_the_one_desk() -> void:
	var hud := HudScript.new()
	hud._build_schedule_board()
	hud._build_billing_window()
	assert(hud._billing_ledger.desk == hud._job_desk, "one desk, read by both")
	assert(hud._schedule_board.desk == hud._job_desk, "and it is the HUD's own")
	_done(hud)


# --- what the ledger's words make the menu say -------------------------------------------------


func test_a_schedule_that_has_billed_nothing_says_nothing_on_the_menu_line() -> void:
	var hud := HudScript.new()
	hud._build_billing_window()
	hud._on_job_started(_estimate())
	assert(hud._jobs_text() == JOBS_LINE, hud._jobs_text())
	hud._job_desk.job("E1").set_billing_method(JobScript.FIXED)
	assert(hud._billing_ledger.start_billing("E1") != null, "the schedule was started")
	hud._billing_window.refresh()
	assert(hud._jobs_text() == JOBS_LINE,
		"a schedule with nothing on it is not news: " + hud._jobs_text())
	_done(hud)


func test_an_invoice_raised_through_the_page_is_in_the_menu_line() -> void:
	var hud := HudScript.new()
	hud._build_billing_window()
	hud._on_job_started(_estimate())
	hud._job_desk.job("E1").set_billing_method(JobScript.FIXED)
	hud._billing_ledger.start_billing("E1")
	hud._billing_window.refresh()
	var raised: Dictionary = hud._billing_window.raise_invoice()
	assert(raised["ok"] == true, String(raised["reason"]))
	assert(hud._jobs_text().contains("1 schedule, 1 invoice"), hud._jobs_text())
	assert(hud._jobs_text().contains("$150.00 billed"), hud._jobs_text())
	assert(hud._jobs_text().contains("$150.00 outstanding"), hud._jobs_text())
	_done(hud)


func test_money_arriving_through_the_page_moves_the_menu_line() -> void:
	var hud := HudScript.new()
	hud._build_billing_window()
	hud._on_job_started(_estimate())
	hud._job_desk.job("E1").set_billing_method(JobScript.FIXED)
	hud._billing_ledger.start_billing("E1")
	hud._billing_window.refresh()
	hud._billing_window.raise_invoice()
	hud._billing_window.set_payment("$50.00", "chq 1041")
	var taken: Dictionary = hud._billing_window.record_payment()
	assert(taken["ok"] == true, String(taken["reason"]))
	assert(hud._jobs_text().contains("$100.00 outstanding"), hud._jobs_text())
	_done(hud)


func test_a_ledger_with_something_wrong_with_it_says_so_on_the_menu_line() -> void:
	var hud := HudScript.new()
	hud._build_billing_window()
	hud._on_job_started(_estimate())
	hud._job_desk.job("E1").set_billing_method(JobScript.FIXED)
	hud._billing_ledger.start_billing("E1")
	assert(hud._jobs_text() == JOBS_LINE, "nothing has been billed, so nothing is said")
	# What a file could hold and the setters refuse: a retainage of 120%.
	hud._billing_ledger.billing_for("E1").retainage_ppm = 1200000
	hud._billing_window.refresh()
	assert(hud._jobs_text().contains("1 thing to look at"), hud._jobs_text())
	_done(hud)


func test_a_job_arriving_with_no_ledger_leaves_the_menu_line_alone() -> void:
	var hud := HudScript.new()
	hud._on_job_started(_estimate())
	assert(hud._billing_ledger == null, "nothing built the ledger")
	assert(hud._jobs_text() == JOBS_LINE, hud._jobs_text())
	hud._build_billing_ledger()
	assert(hud._billing_ledger != null, "and it is built when it is asked for")
	assert(hud._jobs_text() == JOBS_LINE, "a ledger with nothing in it says nothing")
	_done(hud)