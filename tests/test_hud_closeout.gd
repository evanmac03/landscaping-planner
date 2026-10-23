extends Node
## The HUD's side of finishing a job: the Jobs menu's way into the punch list and the warranty, and
## what the closeout desk's own words make that menu say (phase 12).
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


func test_the_jobs_menu_offers_finishing_the_job() -> void:
	var entry: Dictionary = _entry(&"jobs.closeout")
	assert(String(entry["label"]) == "Finishing the job...", String(entry["label"]))
	assert(StringName(entry["method"]) == &"_menu_closeout_window", String(entry["method"]))
	assert(entry["needs"] == HudScript.NEEDS_NOTHING, "a punch list is not on the plan")
	var ids: Array[String] = []
	for listed: Dictionary in HudScript.items_for("Jobs"):
		ids.append(String(listed.get("id", "")))
	assert(ids.has("jobs.closeout"), "the menu offers finishing the job")
	var hud := HudScript.new()
	assert(hud.has_method(String(entry["method"])), "the method the entry names exists")
	_done(hud)


func test_a_hud_with_no_page_reports_nothing_open() -> void:
	var hud := HudScript.new()
	assert(not hud.is_closeout_window_open(), "and nothing is open")
	hud.close_closeout_window()
	assert(not hud.is_closeout_window_open())
	_done(hud)


func test_building_the_page_gives_the_menu_something_to_open() -> void:
	var hud := HudScript.new()
	hud._build_closeout_window()
	assert(hud._closeout_window != null, "the page was built")
	assert(hud._closeout_window.get_parent() == hud, "and it is the HUD's own child")
	assert(hud._closeout_window.desk == hud._closeout_desk, "pointed at this desk")
	assert(not hud.is_closeout_window_open(), "built is not shown")
	_done(hud)


func test_the_page_and_the_jobs_are_wired_to_one_desk() -> void:
	var hud := HudScript.new()
	hud._build_closeout_window()
	assert(hud._closeout_desk.job_desk == hud._job_desk, "the closeout desk reads the HUD's jobs")
	_done(hud)


func test_it_is_a_page_the_escape_pass_has_to_reach() -> void:
	var hud := HudScript.new()
	hud._build_closeout_window()
	assert(hud.pages_in_windows().has(hud._closeout_window), "the escape pass must be able to close it")
	_done(hud)


# --- what the desk's words make the menu say --------------------------------------------------


func test_the_menu_line_says_nothing_until_something_is_being_closed_out() -> void:
	var hud := HudScript.new()
	hud._build_closeout_window()
	hud._on_job_started(_estimate())
	assert(not hud._jobs_text().contains("closeout"), hud._jobs_text())
	_done(hud)


func test_an_item_raised_through_the_page_is_in_the_menu_line() -> void:
	var hud := HudScript.new()
	hud._build_closeout_window()
	hud._on_job_started(_estimate())
	# What the page does to the desk, the menu line reads back at once: the signal is the wiring.
	hud._closeout_desk.raise_item("E1", "patio", "paver out of level", "Dana", "2026-07-10")
	hud._on_closeout_changed()
	assert(hud._jobs_text().contains("1 item"), hud._jobs_text())
	assert(hud._jobs_text().contains("1 outstanding"), hud._jobs_text())
	hud._closeout_window.closeout_changed.emit()
	assert(hud._jobs_text().contains("1 item"), hud._jobs_text())
	_done(hud)


func test_a_warranty_stated_on_the_page_is_in_the_menu_line() -> void:
	var hud := HudScript.new()
	hud._build_closeout_window()
	hud._on_job_started(_estimate())
	hud._closeout_desk.state_completion("E1", "2026-07-01", "Dana")
	hud._closeout_desk.state_warranty("E1", ["plant material"], 12, "2026-07-01")
	hud._closeout_desk.file_claim("E1", "2026-08-01", "the maple died", "the client")
	hud._on_closeout_changed()
	assert(hud._jobs_text().contains("1 claim wanting somebody"), hud._jobs_text())
	_done(hud)