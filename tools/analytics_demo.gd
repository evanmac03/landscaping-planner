extends Node2D
## A live pass over the **figures** in §10: an office does an afternoon's work - a plan drawn, taken
## off, handed to a job, billed, a crew booked and a timesheet logged, a few leads worked - and then the
## report over everything it has is printed, figure by figure, with each one's basis beside it.
##
## This is a development tool, not part of the game. The first pass instances the **real main scene** and
## drives the **real pages** (the estimate window, the billing window, the schedule board, the pipeline
## board), so the records the report reads are the shipped ones. The second pass is a **written-out book**
## with its dates spread over the last few months, because a report run on one afternoon's records has
## every cycle at zero days and every invoice not yet due; the arithmetic is better seen on a book with a
## history behind it.
##
## Nothing of its own is added to disk: the pages it drives write their proposals and their invoices
## where they always do, and the book in the second pass is built in memory. Run
## `res://scenes/analytics_demo.tscn`.

const MAIN := preload("res://scenes/main.tscn")
const HudScript := preload("res://scripts/hud.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const JobScript := preload("res://scripts/biz/job.gd")
const JobDeskScript := preload("res://scripts/biz/job_desk.gd")
const CrewScript := preload("res://scripts/biz/crew.gd")
const EntryScript := preload("res://scripts/biz/time_entry.gd")
const PipelineScript := preload("res://scripts/biz/pipeline.gd")
const LeadScript := preload("res://scripts/biz/lead.gd")
const BillingDeskScript := preload("res://scripts/biz/billing_desk.gd")
const InvoiceScript := preload("res://scripts/biz/invoice.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")
const AnalyticsScript := preload("res://scripts/biz/analytics.gd")


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	var hud: Node = main.get_node_or_null(^"Hud")
	var controller: Node = main.get_node_or_null(^"DraftController")
	if hud == null or controller == null:
		print("no HUD or no drafting controller in the main scene")
		return
	var today: String = Time.get_date_string_from_system()

	print("--- an afternoon's work, on the real pages ---")
	controller.document.add(
		Entity.make_rectangle(Vector2(0, 0), Vector2(6, 4)), LayerSet.NEW_HARDSCAPE
	)
	controller.document.add(Entity.make_circle(Vector2(20, 0), 1.5), LayerSet.NEW_PLANTING)
	hud.open_estimate_window()
	hud._estimate_window.take_off()
	hud._estimate_window.set_recipient("Smith, back garden")
	hud._estimate_window.send_it()
	var started: Dictionary = hud._estimate_window.start_job()
	print("the hand-off was accepted: ", started["ok"])
	var job_id: String = hud._job_desk.job_ids()[0]
	var job: JobScript = hud._job_desk.job(job_id)
	var codes: Array = job.phase_codes()
	print("the job it made carries these cost codes: ", codes)
	var code: StringName = &"LABOUR"
	if not codes.is_empty():
		code = codes[0]
	job.set_billing_method(JobScript.MILESTONE)
	hud.open_billing_window()
	hud._billing_window.choose_tax_code(&"HST-ON")
	hud._billing_window.begin_billing()
	hud._billing_window.set_step_fields("Deposit", "25", "10")
	hud._billing_window.add_step()
	hud._billing_window.set_step_fields("Balance", "75")
	hud._billing_window.add_step()
	var raised: Dictionary = hud._billing_window.raise_invoice()
	print("the billing page raised ", raised["ok"], " - ", hud._billing_window.status_text())
	hud.close_billing_window()

	print("--- a crew, a booking, and a timesheet ---")
	hud.open_schedule_board()
	hud._schedule_board.set_crew_fields("Peter", &"LABOURER")
	print("the board took the crew: ", hud._schedule_board.add_crew_from_fields())
	hud._schedule_board.set_crew_fields("Paul", &"LABOURER")
	hud._schedule_board.add_crew_from_fields()
	var crew: Array[StringName] = hud._job_desk.crew_ids()
	print("the desk now holds: ", crew)
	hud._schedule_board.set_window("8:00", "16:00")
	hud._schedule_board.choose_job(job_id)
	hud._schedule_board.choose_crew(crew[0])
	hud._schedule_board.set_date(today)
	print("booking the day: ", hud._schedule_board.book_selected())
	print("the week reads: ", hud._schedule_board.summary_text())
	hud.close_schedule_board()
	for entry: EntryScript in [
		_entry("E-1", crew[0], job_id, code, today, 480, true),
		_entry("E-2", crew[0], job_id, code, today, 90, false),
	]:
		print("the desk took a timesheet line of ", entry.minutes(), " minute(s), approved ",
			entry.is_approved(), ": ", hud._job_desk.log_time(entry))

	print("--- some leads, worked as far as they got ---")
	hud.open_pipeline_board()
	var board: PipelineBoard = hud._pipeline_board
	var won: Dictionary = board.add_lead("Halstead, front yard", 2450000, &"referral",
		_days_from_today(10))
	board.move_lead(String(won["id"]), LeadScript.PROPOSED)
	board.move_lead(String(won["id"]), LeadScript.WON)
	var lost: Dictionary = board.add_lead("Nguyen, side path", 780000, &"web", _days_from_today(5))
	board.move_lead(String(lost["id"]), LeadScript.PROPOSED)
	print("a drop into lost with no reason is held: ", board.move_lead(
		String(lost["id"]), LeadScript.LOST
	))
	print("and a reason finishes it: ", board.confirm_move("price"))
	var late: Dictionary = board.add_lead("Okafor, back garden", 1900000, &"web", _days_ago(20))
	board.move_lead(String(late["id"]), LeadScript.PROPOSED)
	print("the board reads: ", board.summary_text())
	hud._pipeline_board.hide()

	print("--- the report over everything the office has, as at ", today, " ---")
	var report: AnalyticsScript = AnalyticsScript.new(
		board.pipeline, hud._job_desk, hud._billing_ledger
	)
	print("there is no working day stated yet: ", not report.working_day_stated(),
		", so utilisation says: ", report.figure("crew_utilisation", _days_ago(7), today).missing)
	print("stating one is taken: ", report.set_working_day(480), " - ", report.working_day_text())
	print(report.describe())
	print(report.summary_text("", "", today))
	for figure: AnalyticsScript.Figure in report.figures("", "", today):
		print("  ", figure.text())

	print("--- the same report, on the page the Jobs menu opens ---")
	hud.open_analytics_window()
	var page: AnalyticsWindow = hud._analytics_window
	print("the Jobs menu offers: ", _menu_line())
	print("the page opens saying: ", page.opening_words())
	print("reading ", page.window_text(), ", ", page.as_of_text())
	print(page.summary_text())
	for row: Dictionary in page.figure_rows():
		if bool(row["ok"]):
			print("  ", row["text"])
	print("with ", page.row_count(), " row(s), ", page.available_count(), " of them readable, ",
		page.unavailable_texts().size(), " waiting on something")
	print("nothing on the page takes the keyboard: ", page.buttons_are_focus_free())
	print("and it offers no working day until one is stated: ", page.working_day_text(), " (",
		page.state_button_disabled(), " with the field left empty)")
	page.set_working_day_field(480)
	print("stating eight hours: ", page.state_working_day())
	print("so the hours figure is readable: ", _figure_line(page, "crew_utilisation"))
	print("and the status line reads: ", page.status_text())
	hud.close_analytics_window()
	print("closing it: ", hud.is_analytics_window_open(), " (false is closed)")

	print("--- a book with a history behind it ---")
	var book: Dictionary = _book(today)
	var pipe: PipelineScript = book["pipeline"]
	var desk: JobDeskScript = book["jobs"]
	var ledger: BillingDeskScript = book["billing"]
	var book_report: AnalyticsScript = AnalyticsScript.new(pipe, desk, ledger)
	book_report.set_working_day(480)
	print(book_report.describe())
	print(book_report.summary_text(_days_ago(100), today, today))
	for figure: AnalyticsScript.Figure in book_report.figures(_days_ago(100), today, today):
		print("  ", figure.text())

	print("--- what the report will not answer, and why ---")
	var narrow: AnalyticsScript = AnalyticsScript.new(pipe, desk)
	narrow.set_working_day(480)
	print("  ", narrow.figure("crew_utilisation", _days_ago(7), "").text())
	print("  ", narrow.figure("crew_utilisation", _days_ago(2000), today).text())
	print("  ", narrow.figure("backlog", _days_ago(100), today).text())
	print("  ", narrow.figure("ar_aging", _days_ago(100), today).text())
	print("  ", narrow.figure("total_profit", _days_ago(100), today).text())
	print("  ", narrow.figure("win_rate", _days_ago(400), _days_ago(200)).text())
	print("  ", narrow.figure("slipped", _days_ago(100), today, "").missing)
	print("  ", report.figure("pipeline_value", "", today, "").missing)

	print("--- two things the report says out loud rather than hiding ---")
	desk.invoiced["J1"] = MoneyScript.of(0)
	print("the desk's own memory of what has been billed says ", desk.invoiced["J1"].format(),
		" and the invoices still win: ",
		book_report.figure("backlog", "", today, today).words)
	var without: AnalyticsScript = AnalyticsScript.new(pipe, desk)
	print("with no ledger loaded it falls back, and says so: ",
		without.figure("backlog", "", today, today).words)
	var bare: JobDeskScript = JobDeskScript.new()
	var alone: JobScript = JobScript.new("J9")
	alone.name = "Nobody ever billed this one"
	alone.contract_sum = MoneyScript.of(100000)
	bare.add_job(alone)
	print("and a job no invoice ever went out against has no backlog to report: ",
		AnalyticsScript.new(null, bare).figure("backlog", "", today, today).text())

	print("--- reading the figures changes nothing ---")
	var leads_before: int = pipe.leads.size()
	var entries_before: int = desk.time_entries.size()
	var invoices_before: int = ledger.invoices.size()
	book_report.figures("", "", today)
	print("leads ", pipe.leads.size() == leads_before, ", timesheet lines ",
		desk.time_entries.size() == entries_before, ", invoices ",
		ledger.invoices.size() == invoices_before, " - nothing was accumulated")
	print("and asking for the same window twice gives the same answer: ",
		book_report.figures("", today, today)[0].text()
			== book_report.figures("", today, today)[0].text())


# --- a book with a history ----------------------------------------------------------------------


## The whole book as one dictionary, so the three desks the report reads travel together: a pipeline
## with a history, a job with two budgeted codes and three people, and a billing ledger with invoices
## at three different ages - one of them called back.
func _book(today: String) -> Dictionary:
	var pipe: PipelineScript = PipelineScript.new()
	pipe.add(_lead("A", &"web", 1850000, _days_ago(70), LeadScript.WON, _days_ago(12),
		_days_ago(45)))
	pipe.add(_lead("B", &"referral", 3200000, _days_ago(95), LeadScript.WON, _days_ago(5),
		_days_ago(50)))
	pipe.add(_lead("C", &"web", 900000, _days_ago(60), LeadScript.LOST, _days_ago(8),
		_days_ago(40), &"price"))
	pipe.add(_lead("D", &"sign", 1250000, _days_ago(40), LeadScript.WITHDRAWN, _days_ago(20)))
	pipe.add(_lead("E", &"repeat", 2700000, _days_ago(25), LeadScript.PROPOSED, "",
		_days_ago(10), &"", _days_ago(3)))
	pipe.add(_lead("F", &"web", 640000, _days_ago(6), LeadScript.VISIT))

	var desk: JobDeskScript = JobDeskScript.new()
	var job: JobScript = JobScript.new("J1")
	job.name = "Halstead"
	job.number = "J-1042"
	job.contract_sum = MoneyScript.of(4800000)
	job.phases = [
		{"cost_code": "HARDSCAPE", "budget": MoneyScript.of(1800000), "basis": JobScript.PRICE},
		{"cost_code": "PLANTING", "budget": MoneyScript.of(900000), "basis": JobScript.PRICE},
	]
	desk.add_job(job)
	var peter: CrewScript = CrewScript.new(&"P1", "Peter")
	peter.add_availability({"kind": CrewScript.DAY_OFF, "weekday": 0})
	desk.add_crew(peter)
	var paul: CrewScript = CrewScript.new(&"P2", "Paul")
	desk.add_crew(paul)
	desk.add_crew(CrewScript.new(&"P3", "Mary"))
	desk.log_time(_entry("E-1", &"P1", "J1", &"HARDSCAPE", _days_ago(3), 480, true))
	desk.log_time(_entry("E-2", &"P2", "J1", &"PLANTING", _days_ago(2), 240, true))
	desk.log_time(_entry("E-3", &"P1", "J1", &"HARDSCAPE", _days_ago(1), 300, false))

	var ledger: BillingDeskScript = BillingDeskScript.new()
	ledger.bind(desk)
	ledger.invoices.append(_invoice("INV-1041", "J-1042", 1200000, _days_ago(120)))
	ledger.invoices.append(_invoice("INV-1044", "J-1042", 600000, _days_ago(45)))
	ledger.invoices.append(_invoice("INV-1046", "J-1042", 900000, _days_ago(10)))
	var called_back: InvoiceScript = _invoice("INV-1047", "J-1042", 50000, _days_ago(30))
	called_back.mark_void(_days_ago(25), "raised twice")
	ledger.invoices.append(called_back)
	# The one date that is not on a document anywhere: what the office says a holiday cottage week
	# costs. A crew member's own availability is the record; this is what the report reads for a day.
	print("the book reads as at ", today, ": ", pipe.leads.size(), " leads, ", desk.time_entries.size(),
		" timesheet line(s), ", ledger.invoices.size(), " invoice(s)")
	return {"pipeline": pipe, "jobs": desk, "billing": ledger}


## A lead with a history: it arrived, it was proposed if a date is given, and it ended where it ended.
func _lead(lead_id: String, source: StringName, cents: int, arrived: String, stage: int,
		decided: String = "", proposed: String = "", reason: StringName = &"",
		expected: String = "") -> LeadScript:
	var lead: LeadScript = LeadScript.new(lead_id, "Lead %s" % lead_id)
	lead.source = source
	lead.value_estimate = MoneyScript.of(cents)
	lead.opened_at = arrived
	lead.expected_close_at = expected
	lead.open(arrived, "office")
	if not proposed.is_empty():
		lead.move_to(LeadScript.PROPOSED, proposed, "office")
	if stage == LeadScript.WON or stage == LeadScript.LOST or stage == LeadScript.WITHDRAWN:
		if reason != &"":
			lead.set_lost_reason(reason)
		lead.move_to(stage, decided, "office")
	elif stage == LeadScript.QUALIFIED or stage == LeadScript.VISIT or stage == LeadScript.ESTIMATING:
		lead.move_to(stage, arrived, "office")
	return lead


## An entry that really lasts `minutes`, starting at eight in the morning on a given day, approved or
## not.
func _entry(entry_id: String, member: StringName, job_id: String, code: StringName, day: String,
		minutes: int, approved: bool) -> EntryScript:
	var entry: EntryScript = EntryScript.new(entry_id)
	entry.job = job_id
	entry.cost_code = code
	entry.crew_member = member
	entry.loaded_rate = MoneyScript.of(4500)
	var end := 8 * 60 + minutes
	entry.started_at = "%sT08:00:00" % day
	entry.ended_at = "%sT%02d:%02d:00" % [day, floori(float(end) / 60.0), end % 60]
	if approved:
		entry.approve("office")
	return entry


## An issued invoice for a job, worth `cents` before tax, due thirty days after it went out. The tax
## code is EXEMPT so an ageing test is not arithmetic about tax.
func _invoice(number: String, job_label: String, cents: int, issued_at: String) -> InvoiceScript:
	var invoice: InvoiceScript = InvoiceScript.new("I-%s" % number)
	invoice.job = job_label
	invoice.customer = {"name": "Halstead"}
	invoice.add_line(InvoiceScript.MILESTONE_LINE, "Deposit", 1000, &"EACH",
		MoneyScript.of(cents), &"HARDSCAPE", &"EXEMPT")
	var issued: Dictionary = invoice.issue(issued_at, 30, number)
	if not bool(issued["ok"]):
		print("the fixture invoice would not issue: ", issued["reason"])
	return invoice


## A date `offset` days from today, counted on the same calendar the rest of the app uses. Every date
## in this file is relative to today, so the demo reads the same whenever it is run.
func _days_from_today(offset: int) -> String:
	var today: String = Time.get_date_string_from_system()
	var unix: int = int(Time.get_unix_time_from_datetime_string(today))
	return Time.get_date_string_from_unix_time(unix + offset * 86400)


func _days_ago(days: int) -> String:
	return _days_from_today(-days)


## The Jobs menu entry about the figures, as the bar would read it.
func _menu_line() -> String:
	for entry in HudScript.jobs_items():
		if String(entry.get("id", "")) == "jobs.analytics":
			return String(entry["label"])
	return "the Jobs menu offers nothing about the figures"


## One figure's own sentence, by key, read off the page the same way the page builds its rows.
func _figure_line(page: AnalyticsWindow, key: String) -> String:
	for row: Dictionary in page.figure_rows():
		if String(row["key"]) == key:
			return String(row["text"])
	return "the page has no figure called %s" % key