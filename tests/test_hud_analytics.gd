extends Node
## The figures as the program reaches them: the Jobs menu entry, the page, and what happens to the page
## when a record moves under it (spec §10, §14f).
##
## The properties under test. **The report is pointed at the three desks the HUD already holds** rather
## than at copies of them, so a lead added on the board is a lead the figures about leads read. **An
## open page is read again when a record moves**, and a page that is closed is not read at all, because
## there is nobody looking. And **the Jobs menu line says nothing about the figures**: a report is not
## something an office can act on from across the room, and the one line there is for what it can.
##
## A page is never opened here with `popup_centered`, because that needs a window server and a test
## process has not got one. Being shown is what the page's own `visible` flag means, and that is what
## these tests set - which is exactly what the change handlers below look at.

const HudScript := preload("res://scripts/hud.gd")
const AnalyticsScript := preload("res://scripts/biz/analytics.gd")
const PipelineScript := preload("res://scripts/biz/pipeline.gd")
const LeadScript := preload("res://scripts/biz/lead.gd")
const JobDeskScript := preload("res://scripts/biz/job_desk.gd")
const JobScript := preload("res://scripts/biz/job.gd")
const BillingDeskScript := preload("res://scripts/biz/billing_desk.gd")
const InvoiceScript := preload("res://scripts/biz/invoice.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")

const TODAY := "2026-06-15"


## A HUD built off-tree with the desks it would have built itself. No `_ready`, so no windows are
## painted: the methods a control calls are driven directly, which is what the menu handlers call.
func _hud() -> HudScript:
	var hud: HudScript = HudScript.new()
	hud._job_desk = JobDeskScript.new()
	var job: JobScript = JobScript.new("J1")
	job.name = "Smith"
	job.contract_sum = MoneyScript.of(2000000)
	job.phases = [{"cost_code": "HARDSCAPE", "budget": MoneyScript.of(800000), "basis": JobScript.PRICE}]
	hud._job_desk.add_job(job)
	hud._billing_ledger = BillingDeskScript.new()
	hud._billing_ledger.bind(hud._job_desk)
	hud._build_pipeline_board()
	return hud


## The page as it stands when it is on the screen.
func _open(hud: HudScript) -> void:
	hud._build_analytics_window()
	hud._analytics_window.visible = true


func _invoice(cents: int, issued_at: String) -> InvoiceScript:
	var invoice: InvoiceScript = InvoiceScript.new("I-INV-1")
	invoice.job = "J1"
	invoice.customer = {"name": "Smith"}
	invoice.add_line(InvoiceScript.MILESTONE_LINE, "Deposit", 1000, &"EACH",
		MoneyScript.of(cents), &"HARDSCAPE", &"EXEMPT")
	invoice.issue(issued_at, 30, "INV-1")
	return invoice


## One figure's sentence off the open page, by key.
func _row(hud: HudScript, key: String) -> String:
	var texts: Array[String] = hud._analytics_window.figure_texts()
	return texts[AnalyticsScript.KEYS.find(key)]


# --- the menu -----------------------------------------------------------------------------------


func test_the_jobs_menu_offers_the_figures() -> void:
	var offered: Array[Dictionary] = HudScript.jobs_items()
	var found: Dictionary = {}
	for entry in offered:
		if String(entry.get("id", "")) == "jobs.analytics":
			found = entry
	assert(not found.is_empty(), "the Jobs menu has an entry for the figures")
	assert(String(found["label"]).contains("figures"), String(found["label"]))
	assert(String(found["method"]) == "_menu_analytics_window", String(found["method"]))


func test_the_jobs_line_says_nothing_about_the_figures() -> void:
	var hud: HudScript = _hud()
	var line: String = hud._jobs_text()
	assert(not line.contains("figure"), line)
	assert(not line.contains("%"), "a report is not a menu line: %s" % line)
	hud.free()


# --- the page as the HUD builds it ---------------------------------------------------------------


func test_a_hud_with_no_page_reports_nothing_open() -> void:
	var hud: HudScript = HudScript.new()
	assert(not hud.is_analytics_window_open(), "no page is open")
	assert(hud._analytics_window == null, "and there is none built yet")
	hud.free()


func test_the_report_is_pointed_at_the_three_desks_the_hud_holds() -> void:
	var hud: HudScript = _hud()
	hud._build_analytics_report()
	var made: AnalyticsScript = hud._analytics_report
	assert(made != null, "the report is built")
	assert(made.pipeline == hud._pipeline_board.pipeline, "the pipeline is the board's own")
	assert(made.jobs == hud._job_desk, "the desk is the HUD's own")
	assert(made.billing == hud._billing_ledger, "the ledger is the HUD's own")
	assert(not made.working_day_stated(), "nobody has stated a working day yet")
	hud.free()


func test_building_the_page_gives_the_menu_something_to_open() -> void:
	var hud: HudScript = _hud()
	assert(hud._analytics_window == null, "nothing is built yet")
	hud._build_analytics_window()
	assert(hud._analytics_window != null, "the page is built")
	assert(hud._analytics_window.report == hud._analytics_report, "and pointed at this report")
	# Built but not shown is not open: a page nobody has opened is not on the screen.
	assert(not hud.is_analytics_window_open(), "built is not shown")
	assert(hud._analytics_window.get_node_or_null(^"Column/Rows") != null, "with the figures on it")
	assert(hud._analytics_window.get_node_or_null(^"Column/DayRow/DayMinutes") != null,
		"and the field a working day is stated in")
	hud.free()


func test_the_page_is_shown_when_it_is_made_visible_and_hidden_when_it_is_closed() -> void:
	var hud: HudScript = _hud()
	hud._build_analytics_window()
	hud._analytics_window.visible = true
	assert(hud.is_analytics_window_open(), "a page on the screen is open")
	hud.close_analytics_window()
	assert(not hud.is_analytics_window_open(), "and closing it hides it")
	hud.free()


func test_the_page_reads_a_window_and_the_figures_can_be_read_off_it() -> void:
	var hud: HudScript = _hud()
	_open(hud)
	assert(hud._analytics_window.as_of() == Time.get_date_string_from_system(),
		hud._analytics_window.as_of())
	assert(hud._analytics_window.window_text() == "every date", hud._analytics_window.window_text())
	assert(hud._analytics_window.row_count() == 14, str(hud._analytics_window.row_count()))
	hud.free()


func test_stating_a_working_day_on_the_page_reaches_the_huds_report() -> void:
	var hud: HudScript = _hud()
	_open(hud)
	hud._analytics_window.set_working_day_field(480)
	assert(bool(hud._analytics_window.state_working_day()["ok"]))
	assert(hud._analytics_report.working_day_stated(), "the day is the report's own")
	assert(hud._analytics_window.working_day_text() == "stated as 8 hours 0 minutes",
		hud._analytics_window.working_day_text())
	hud.free()


# --- a record moving under an open page ----------------------------------------------------------


func test_a_lead_added_on_the_board_moves_the_open_pages_figures() -> void:
	var hud: HudScript = _hud()
	_open(hud)
	var before := _row(hud, "pipeline_value")
	var added: Dictionary = hud._pipeline_board.add_lead("Halstead", 2450000, &"web", TODAY)
	assert(bool(added["ok"]), str(added))
	hud._on_pipeline_changed()
	assert(_row(hud, "pipeline_value") != before, _row(hud, "pipeline_value"))
	assert(_row(hud, "pipeline_value").contains("$24,500.00 raw"), _row(hud, "pipeline_value"))
	hud.free()


func test_an_invoice_going_out_moves_the_open_pages_figures() -> void:
	var hud: HudScript = _hud()
	_open(hud)
	hud._analytics_window.set_as_of(TODAY)
	var before := _row(hud, "ar_aging")
	assert(before.contains("nothing is unpaid"), before)
	hud._billing_ledger.invoices.append(_invoice(500000, "2026-06-01"))
	hud._on_billing_changed()
	assert(_row(hud, "ar_aging") != before, _row(hud, "ar_aging"))
	assert(_row(hud, "ar_aging").contains("$5,000.00"), _row(hud, "ar_aging"))
	hud.free()


func test_a_closed_page_is_not_read_again() -> void:
	var hud: HudScript = _hud()
	_open(hud)
	var before := _row(hud, "pipeline_value")
	hud.close_analytics_window()
	hud._pipeline_board.add_lead("Halstead", 2450000, &"web", TODAY)
	hud._on_pipeline_changed()
	assert(_row(hud, "pipeline_value") == before,
		"nobody is looking at a closed page: %s" % _row(hud, "pipeline_value"))
	hud.free()


func test_a_change_with_no_page_at_all_is_no_trouble() -> void:
	var hud: HudScript = _hud()
	hud._on_pipeline_changed()
	hud._on_billing_changed()
	assert(hud._analytics_window == null, "no page was built by a change to the records")
	hud.free()