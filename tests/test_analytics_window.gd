extends Node
## The figures on a page: what it shows, what its one act does, and what it refuses (spec §10, §14f).
##
## The properties under test. **The page holds no figures of its own** - every line is recomputed from
## the records when an argument changes, so a figure is never a moment out of date. **A figure that
## cannot be worked out still gets its row**, greyed, saying what it is waiting for: a page that omitted
## it would read as a figure the report does not have. **The page may know today and the report may
## not**: the as-of field is filled in with today when it is empty, while the report itself never reads
## a clock. And **nothing on the page takes the keyboard** beyond the typed fields.

const WindowScript := preload("res://scripts/analytics_window.gd")
const AnalyticsScript := preload("res://scripts/biz/analytics.gd")
const PipelineScript := preload("res://scripts/biz/pipeline.gd")
const LeadScript := preload("res://scripts/biz/lead.gd")
const JobDeskScript := preload("res://scripts/biz/job_desk.gd")
const JobScript := preload("res://scripts/biz/job.gd")
const CrewScript := preload("res://scripts/biz/crew.gd")
const EntryScript := preload("res://scripts/biz/time_entry.gd")
const BillingDeskScript := preload("res://scripts/biz/billing_desk.gd")
const InvoiceScript := preload("res://scripts/biz/invoice.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")

const FROM := "2026-01-01"
const TO := "2026-03-31"
const NOW := "2026-04-01"


# --- fixtures -----------------------------------------------------------------------------------


func _lead(lead_id: String, cents: int, arrived: String, stage: int, decided: String = "",
		proposed: String = "", reason: StringName = &"", expected: String = "") -> LeadScript:
	var lead: LeadScript = LeadScript.new(lead_id, "Lead %s" % lead_id)
	lead.source = &"web"
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
	return lead


func _pipeline() -> PipelineScript:
	var pipe: PipelineScript = PipelineScript.new()
	pipe.add(_lead("A", 2000000, "2025-11-02", LeadScript.WON, "2026-02-10", "2026-01-05"))
	pipe.add(_lead("B", 3000000, "2026-01-05", LeadScript.PROPOSED, "", "2026-01-20",
		&"", "2026-03-20"))
	return pipe


func _job_desk() -> JobDeskScript:
	var desk: JobDeskScript = JobDeskScript.new()
	var job: JobScript = JobScript.new("J1")
	job.name = "Smith"
	job.contract_sum = MoneyScript.of(2000000)
	job.phases = [{"cost_code": "HARDSCAPE", "budget": MoneyScript.of(800000), "basis": JobScript.PRICE}]
	desk.add_job(job)
	var peter: CrewScript = CrewScript.new(&"P1", "Peter")
	peter.add_availability({"kind": CrewScript.DAY_OFF, "weekday": 0})
	desk.add_crew(peter)
	var entry: EntryScript = EntryScript.new("T1")
	entry.job = "J1"
	entry.cost_code = &"HARDSCAPE"
	entry.crew_member = &"P1"
	entry.loaded_rate = MoneyScript.of(4500)
	entry.started_at = "2026-03-03T08:00:00"
	entry.ended_at = "2026-03-03T16:00:00"
	entry.approve("office")
	desk.log_time(entry)
	return desk


func _billing(desk: JobDeskScript) -> BillingDeskScript:
	var ledger: BillingDeskScript = BillingDeskScript.new()
	ledger.bind(desk)
	var invoice: InvoiceScript = InvoiceScript.new("I-INV-1")
	invoice.job = "J1"
	invoice.customer = {"name": "Smith"}
	invoice.add_line(InvoiceScript.MILESTONE_LINE, "Deposit", 1000, &"EACH",
		MoneyScript.of(20000), &"HARDSCAPE", &"EXEMPT")
	invoice.issue("2026-01-10", 30, "INV-1")
	ledger.invoices.append(invoice)
	return ledger


## A report over the pipeline, the job desk and the ledger - with a working day stated, so the figures
## about hours are readable too.
func _report(with_billing: bool = true) -> AnalyticsScript:
	var desk: JobDeskScript = _job_desk()
	var made: AnalyticsScript = AnalyticsScript.new(_pipeline(), desk)
	if with_billing:
		made.bind(_pipeline(), desk, _billing(desk))
	made.set_working_day(480)
	return made


## A report over the same three desks with **no working day stated**, which is how the office's records
## start: no hours-per-day is recorded anywhere, so the figures about hours refuse until somebody says.
func _report_without_a_day() -> AnalyticsScript:
	var made: AnalyticsScript = _report()
	made.working_day_minutes = 0
	return made


## A page built off-tree, pointed at a report and reading a window with both ends and an as-of date, so
## every figure that can be worked out over them is worked out.
func _page(made: AnalyticsScript = null) -> WindowScript:
	var page: WindowScript = WindowScript.new()
	page.build()
	page.bind(made if made != null else _report())
	page.set_window_fields(FROM, TO)
	page.set_as_of(NOW)
	return page


## One figure's own sentence, in table order.
func _row(page: WindowScript, key: String) -> String:
	var at: int = AnalyticsScript.KEYS.find(key)
	assert(at >= 0, "the table has a figure called %s" % key)
	var texts: Array[String] = page.figure_texts()
	assert(texts.size() == AnalyticsScript.KEYS.size(), "one row per figure: %d" % texts.size())
	return texts[at]


# --- what the page shows ------------------------------------------------------------------------


func test_a_page_with_no_report_shows_every_figure_refused_rather_than_broken() -> void:
	var page := WindowScript.new()
	page.build()
	assert(page.row_count() == 14, str(page.row_count()))
	assert(page.available_count() == 0, "nothing can be worked out with nothing loaded")
	for words: String in page.figure_texts():
		assert(words.contains("unavailable"), words)
	assert(page.opening_words().contains("Nothing to report on yet"), page.opening_words())
	page.free()


func test_the_page_shows_one_row_per_figure_in_the_tables_own_order() -> void:
	var page := _page()
	assert(page.figure_keys() == AnalyticsScript.KEYS, str(page.figure_keys()))
	page.free()


func test_a_row_is_the_reports_own_sentence_and_nothing_the_page_added() -> void:
	var page := _page()
	var rows: Array[Dictionary] = page.figure_rows()
	var at: int = AnalyticsScript.KEYS.find("win_rate")
	assert(String(rows[at]["label"]) == "Win rate", String(rows[at]["label"]))
	assert(String(rows[at]["text"]) == _report().figure("win_rate", FROM, TO, NOW).text(),
		String(rows[at]["text"]))
	assert(bool(rows[at]["ok"]), str(rows[at]))
	# The sentence opens by naming the figure, so the page shows it once: a label column would be the
	# page agreeing with itself.
	assert(_row(page, "win_rate") == String(rows[at]["text"]), _row(page, "win_rate"))
	assert(_row(page, "win_rate").begins_with("Win rate: "), _row(page, "win_rate"))
	page.free()


func test_a_figure_that_cannot_be_worked_out_still_gets_its_row_and_says_what_it_is_waiting_for() -> void:
	var page := _page(_report_without_a_day())
	var rows: Array[Dictionary] = page.figure_rows()
	var at: int = AnalyticsScript.KEYS.find("crew_utilisation")
	assert(not bool(rows[at]["ok"]), str(rows[at]))
	assert(String(rows[at]["text"]).contains("no working day is stated"), String(rows[at]["text"]))
	assert(page.row_count() == 14, "the row is there, greyed rather than left out")
	page.free()


func test_the_working_day_field_offers_a_day_as_a_placeholder_and_not_as_a_value() -> void:
	var page := _page(_report_without_a_day())
	assert(page.working_day_text().contains("not stated"), page.working_day_text())
	assert(page.status_text().is_empty() == false, "the page opens saying something")
	var field: LineEdit = page.find_child("DayMinutes", true, false)
	assert(field != null, "the page has a field for the day")
	assert(field.text.is_empty(), "a placeholder is not a value: '%s'" % field.text)
	assert(field.placeholder_text == "480", field.placeholder_text)
	page.free()


func test_a_report_with_nothing_stated_reads_as_the_figures_about_hours_waiting() -> void:
	var page := _page(_report_without_a_day())
	assert(page.unavailable_texts().size() == 1, str(page.unavailable_texts()))
	assert(_row(page, "crew_utilisation").contains("no working day is stated"),
		_row(page, "crew_utilisation"))
	# One lead was won and nothing was lost, so the rate is the whole of what was decided.
	assert(_row(page, "win_rate").contains("100.0% (1 won, 0 lost"), _row(page, "win_rate"))
	assert(page.opening_words().contains("State how long a working day is"), page.opening_words())
	page.free()


func test_nothing_on_the_page_takes_the_keyboard() -> void:
	var page := _page()
	assert(page.buttons_are_focus_free())
	var bare := WindowScript.new()
	bare.build()
	assert(bare.buttons_are_focus_free())
	page.free()
	bare.free()


func test_the_summary_is_the_reports_own_summary_of_this_window() -> void:
	var page := _page()
	assert(page.summary_text() == "14 figures for 2026-01-01 to 2026-03-31, all of them available",
		page.summary_text())
	page.free()


func test_the_page_says_which_window_and_which_moment_it_is_reading() -> void:
	var page := _page()
	assert(page.window_text() == "2026-01-01 to 2026-03-31", page.window_text())
	assert(page.as_of_text() == "as at 2026-04-01", page.as_of_text())
	page.set_window_fields("", "")
	assert(page.window_text() == "every date", page.window_text())
	page.set_as_of("")
	assert(page.as_of_text() == "no as-of date", page.as_of_text())
	page.free()


# --- today, and the report's own refusal to read a clock ----------------------------------------


func test_the_as_of_field_is_filled_in_with_today_when_it_is_empty() -> void:
	var page := WindowScript.new()
	page.build()
	page.bind(_report())
	assert(page.as_of() == Time.get_date_string_from_system(), page.as_of())
	page.free()


func test_the_as_of_field_is_left_alone_once_a_person_has_stated_one() -> void:
	var page := _page()
	page.bind(_report())
	assert(page.as_of() == NOW, page.as_of())
	page.free()


func test_the_page_may_know_today_while_the_report_still_will_not_be_told_a_clock() -> void:
	var page := _page()
	page.set_window_fields("", "")
	assert(_row(page, "pipeline_value").contains("$30,000.00 raw"), _row(page, "pipeline_value"))
	page.set_as_of("")
	assert(_row(page, "pipeline_value") ==
		"Pipeline value unavailable: an as-of date is needed, because what is open is open now",
		_row(page, "pipeline_value"))
	page.free()


# --- changing an argument reads the figures again ------------------------------------------------


func test_changing_the_window_reads_the_figures_again() -> void:
	var page := _page()
	var before := _row(page, "funnel")
	page.set_window_fields("2026-01-01", "2026-01-31")
	assert(_row(page, "funnel") != before, _row(page, "funnel"))
	assert(_row(page, "funnel").contains("2026-01-01 to 2026-01-31"), _row(page, "funnel"))
	page.free()


func test_a_window_with_nothing_in_it_says_so_in_the_figures_and_in_the_summary() -> void:
	var page := _page()
	page.set_window_fields("2026-06-01", "2026-06-30")
	assert(_row(page, "funnel").contains("nothing entered the funnel in this window"),
		_row(page, "funnel"))
	assert(page.status_text().is_empty() == false, "the page always has a line")
	page.free()


func test_the_page_reads_the_records_it_was_pointed_at_and_keeps_no_copies() -> void:
	var made: AnalyticsScript = _report()
	var page := _page(made)
	var before := _row(page, "win_rate")
	# A lead is won, in the window, with no proposal recorded: the rate moves because the records moved.
	made.pipeline.add(_lead("C", 1000000, "2026-01-10", LeadScript.WON, "2026-02-01"))
	page.refresh()
	assert(_row(page, "win_rate") != before, _row(page, "win_rate"))
	assert(_row(page, "win_rate").contains("2 won, 0 lost"), _row(page, "win_rate"))
	page.free()


func test_reading_the_figures_twice_gives_the_same_page() -> void:
	var page := _page()
	var first: Array[String] = page.figure_texts()
	page.refresh()
	assert(page.figure_texts() == first, "nothing is cached, so nothing drifts")
	page.free()


# --- what could not be worked out ---------------------------------------------------------------


func test_what_could_not_be_worked_out_is_listed_on_the_page() -> void:
	var page := _page()
	var missing: ItemList = page.find_child("Missing", true, false)
	assert(missing != null, "the page lists what it could not work out")
	assert(missing.item_count == page.unavailable_texts().size(),
		"%d listed, %d said" % [missing.item_count, page.unavailable_texts().size()])
	page.free()


func test_a_report_with_figures_it_cannot_work_out_lists_them_all() -> void:
	var page := _page(AnalyticsScript.new())
	assert(page.unavailable_texts().size() == 14, str(page.unavailable_texts().size()))
	var missing: ItemList = page.find_child("Missing", true, false)
	assert(missing.item_count == 14, str(missing.item_count))
	assert(page.status_text().contains("Nothing to report on yet"), page.status_text())
	page.free()


func test_a_window_with_no_ends_refuses_the_hours_figure_by_name() -> void:
	var page := _page()
	page.set_window_fields("2026-03-01", "")
	assert(_row(page, "crew_utilisation").contains("both ends readable"), _row(page, "crew_utilisation"))
	assert(page.unavailable_texts().has(
		"Crew utilisation unavailable: crew utilisation needs a window with both ends readable"
	), str(page.unavailable_texts()))
	page.free()


# --- the one act --------------------------------------------------------------------------------


func test_the_state_button_is_dead_until_the_field_holds_a_number() -> void:
	var page := _page()
	# The placeholder is a hint, not a value, so there is nothing to state yet.
	assert(page.state_button_disabled(), "an empty field is not a day")
	page.set_working_day_field(0)
	assert(not page.state_button_disabled(), "zero is a number, and the report is what refuses it")
	# Typing is what makes a field change, and a field that changed says so: the button follows the
	# page's own reading of the field rather than being set by whoever typed.
	var field: LineEdit = page.find_child("DayMinutes", true, false)
	field.text = "eight hours"
	field.text_changed.emit("eight hours")
	assert(page.state_button_disabled(), "words are not minutes")
	page.free()


func test_stating_a_working_day_states_it_on_the_report_and_says_so() -> void:
	var made: AnalyticsScript = _report_without_a_day()
	var page := _page(made)
	var before := _row(page, "crew_utilisation")
	assert(page.working_day_text().contains("not stated"), page.working_day_text())
	page.set_working_day_field(420)
	var stated: Dictionary = page.state_working_day()
	assert(bool(stated["ok"]), str(stated))
	assert(int(stated["minutes"]) == 420, str(stated))
	assert(made.working_day_stated(), "the report is what holds the day")
	assert(page.working_day_text() == "stated as 7 hours 0 minutes", page.working_day_text())
	assert(page.status_text().contains("7 hours 0 minutes"), page.status_text())
	# The figures about hours are read off the day that was stated: 77 available days in the first
	# quarter of 2026, one Sunday a week off, at seven hours each.
	assert(_row(page, "crew_utilisation") != before, _row(page, "crew_utilisation"))
	assert(_row(page, "crew_utilisation").contains("539 hour(s) 0 minute(s) available"),
		_row(page, "crew_utilisation"))
	assert(page.unavailable_texts().is_empty(), str(page.unavailable_texts()))
	page.free()


func test_stating_a_day_that_is_not_a_number_is_refused_and_nothing_is_stated() -> void:
	var made: AnalyticsScript = _report_without_a_day()
	var page := _page(made)
	page.find_child("DayMinutes", true, false).text = "eight hours"
	var refused: Dictionary = page.state_working_day()
	assert(not bool(refused["ok"]), str(refused))
	assert(not made.working_day_stated(), "nothing was stated")
	assert(page.status_text().contains("'eight hours' is not one"), page.status_text())
	page.free()


func test_a_day_of_no_minutes_is_refused_by_the_reports_own_rule() -> void:
	var made: AnalyticsScript = _report_without_a_day()
	var page := _page(made)
	page.set_working_day_field(0)
	var refused: Dictionary = page.state_working_day()
	assert(not bool(refused["ok"]), str(refused))
	assert(not made.working_day_stated(), "a day of no minutes is not a day")
	assert(page.status_text().contains("is not a day the figures can use"), page.status_text())
	page.free()


func test_stating_a_working_day_announces_itself() -> void:
	var made: AnalyticsScript = _report_without_a_day()
	var page := _page(made)
	var heard: Array = []
	page.report_changed.connect(func() -> void: heard.append(true))
	page.set_working_day_field(480)
	assert(bool(page.state_working_day()["ok"]))
	assert(heard.size() == 1, str(heard))
	# A refusal changes nothing, so nothing is announced.
	page.set_working_day_field(0)
	assert(not bool(page.state_working_day()["ok"]))
	assert(heard.size() == 1, str(heard))
	page.free()


func test_a_page_with_no_report_refuses_to_state_a_day_rather_than_failing() -> void:
	# Nothing built and nothing bound: there is no report to state anything on.
	var page := WindowScript.new()
	var refused: Dictionary = page.state_working_day()
	assert(not bool(refused["ok"]), str(refused))
	assert(String(refused["reason"]) == "there is no report on this page", String(refused["reason"]))
	# And a page with a report on it but nothing typed says what a day is rather than reading the blank.
	var built := WindowScript.new()
	built.build()
	assert(not bool(built.state_working_day()["ok"]))
	assert(built.status_text().contains("is not one"), built.status_text())
	page.free()
	built.free()


# --- the page as the program builds it ----------------------------------------------------------


func test_building_twice_is_the_same_page() -> void:
	var page := _page()
	var keys: Array[String] = page.figure_keys()
	page.build()
	assert(page.figure_keys() == keys, "build is idempotent")
	page.free()


func test_pointing_the_page_at_another_report_reads_it_again() -> void:
	var page := _page()
	assert(_row(page, "win_rate").contains("100.0%"), _row(page, "win_rate"))
	# A report with nothing in it: every figure refuses.
	page.bind(AnalyticsScript.new())
	assert(page.available_count() == 0, "the new report is the one being read")
	assert(_row(page, "win_rate").contains("unavailable"), _row(page, "win_rate"))
	assert(page.status_text().contains("Nothing to report on yet"), page.status_text())
	page.free()


func test_closing_the_page_says_so() -> void:
	var page := _page()
	var heard: Array = []
	page.closed.connect(func() -> void: heard.append(true))
	page._on_close_requested()
	assert(heard.size() == 1, str(heard))
	assert(not page.visible, "closing hides the page")
	page.free()


func test_the_page_is_titled_and_sized_like_the_other_pages() -> void:
	var page := WindowScript.new()
	assert(page.title == "The figures", page.title)
	assert(page.min_size == WindowScript.SIZE, str(page.min_size))
	assert(page.min_size.x <= 1200 and page.min_size.y <= 900, str(page.min_size))
	assert(page.exclusive == false, "a page is not a modal: the drawing keeps working behind it")
	page.free()