extends Node
## The figures in §10: what each one is a function of, what it says when it cannot be worked out, and
## the three decisions the build made that the table did not settle (REQ-B15, REQ-B16, REQ-B20, AC-B17,
## AC-B18).
##
## The properties under test, in the order this file takes them. **Every figure the specification lists
## is here, once, in order, and names its basis.** **A report is a pure function of the records**: the
## same window computed twice is the same answer, and a past window does not move when new leads
## arrive. **A figure with nothing to read, or no as-of date, or no stated working day, is refused with
## the missing thing named** - never zero. **A figure about invoices is read off the invoices.**

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
## A week that begins on a Sunday, which is the day one of the crew is off.
const WEEK_FROM := "2026-03-01"
const WEEK_TO := "2026-03-07"


# --- fixtures -----------------------------------------------------------------------------------


## A lead with a history: it arrived, it was proposed on a date if one is given, and it ended where it
## ended. Every date is an argument, because every figure here is measured on one.
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


## Two wins (one proposed in January, one in February), a loss to price in January, a withdrawal in
## March that never said why, one lead still proposed and overdue, and one still early. Enough that
## every one of §10's lead figures has something to say about it.
func _pipeline() -> PipelineScript:
	var pipe: PipelineScript = PipelineScript.new()
	pipe.add(_lead("A", &"web", 1000000, "2025-11-02", LeadScript.WON, "2026-02-10", "2026-01-05"))
	pipe.add(_lead("B", &"web", 3000000, "2025-12-01", LeadScript.WON, "2026-03-05", "2026-02-01"))
	pipe.add(_lead("C", &"referral", 2000000, "2025-10-01", LeadScript.LOST, "2026-01-20",
		"2025-11-15", &"price"))
	pipe.add(_lead("D", &"sign", 500000, "2026-02-01", LeadScript.WITHDRAWN, "2026-03-02"))
	pipe.add(_lead("E", &"web", 4000000, "2026-01-05", LeadScript.PROPOSED, "", "2026-01-20",
		&"", "2026-03-20"))
	pipe.add(_lead("F", &"repeat", 1500000, "2026-02-20", LeadScript.VISIT))
	return pipe


## A job with two budgeted codes, a contract of $20,000, and two people - one of whom is off on
## Sundays.
func _job_desk() -> JobDeskScript:
	var desk: JobDeskScript = JobDeskScript.new()
	var job: JobScript = JobScript.new("J1")
	job.name = "Smith"
	job.number = "J-1"
	job.contract_sum = MoneyScript.of(2000000)
	job.phases = [
		{"cost_code": "HARDSCAPE", "budget": MoneyScript.of(800000), "basis": JobScript.PRICE},
		{"cost_code": "PLANTING", "budget": MoneyScript.of(400000), "basis": JobScript.PRICE},
	]
	desk.add_job(job)
	var peter: CrewScript = CrewScript.new(&"P1", "Peter")
	peter.add_availability({"kind": "DAY_OFF", "weekday": 0})
	desk.add_crew(peter)
	desk.add_crew(CrewScript.new(&"P2", "Paul"))
	return desk


## An entry that really lasts `minutes`, starting at eight in the morning on a given day, approved or
## not. The end time is worked out from the duration rather than typed, so `minutes()` is what the test
## asked for and not what a mistyped clock happens to give.
func _entry(entry_id: String, member: StringName, day: String, minutes: int,
		approved: bool = true) -> EntryScript:
	var entry: EntryScript = EntryScript.new(entry_id)
	entry.job = "J1"
	entry.cost_code = &"HARDSCAPE"
	entry.crew_member = member
	entry.loaded_rate = MoneyScript.of(4500)
	var end := 8 * 60 + minutes
	entry.started_at = "%sT08:00:00" % day
	entry.ended_at = "%sT%02d:%02d:00" % [day, floori(float(end) / 60.0), end % 60]
	if approved:
		entry.approve("office")
	return entry


## A loss that never said why. `move_to` refuses to close a lead as lost without a reason, so this is
## built the way a file hands one back: the stage and the decision date set with no reason beside them,
## which is the state the win/loss report has to cope with.
func _unreasoned_loss(lead_id: String, cents: int, decided: String) -> LeadScript:
	var lead: LeadScript = _lead(lead_id, &"sign", cents, "2025-09-01", LeadScript.PROPOSED, "",
		"2025-10-01")
	lead.stage = LeadScript.LOST
	lead.closed_at = decided
	return lead


func _billing(job_records: JobDeskScript) -> BillingDeskScript:
	var ledger: BillingDeskScript = BillingDeskScript.new()
	ledger.bind(job_records)
	return ledger


## An issued invoice for a job, worth `cents` before tax, due `terms` days after it went out. The tax
## code is EXEMPT so the balance is the amount and nothing else - an ageing test should not be arithmetic
## about tax.
func _invoice(number: String, job_label: String, cents: int, issued_at: String,
		terms: int = 30) -> InvoiceScript:
	var invoice: InvoiceScript = InvoiceScript.new("I-%s" % number)
	invoice.job = job_label
	invoice.customer = {"name": "Smith"}
	invoice.add_line(InvoiceScript.MILESTONE_LINE, "Deposit", 1000, &"EACH",
		MoneyScript.of(cents), &"HARDSCAPE", &"EXEMPT")
	assert(bool(invoice.issue(issued_at, terms, number)["ok"]), "the fixture invoice should issue")
	return invoice


## An analytics over a whole office: the pipeline, a job with two codes and two people, and a billing
## ledger - with the crew's day stated, so the utilisation figure can be worked out at all.
func _analytics(with_billing: bool = true) -> AnalyticsScript:
	var desk: JobDeskScript = _job_desk()
	desk.log_time(_entry("T1", &"P1", "2026-03-03", 480))
	desk.log_time(_entry("T2", &"P2", "2026-03-02", 240))
	desk.log_time(_entry("T3", &"P1", "2026-03-04", 300, false))
	var made: AnalyticsScript = AnalyticsScript.new(_pipeline(), desk)
	if with_billing:
		var ledger: BillingDeskScript = _billing(desk)
		ledger.invoices.append(_invoice("INV-1", "J-1", 20000, "2026-01-10"))
		made.bind(_pipeline(), desk, ledger)
	made.set_working_day(480)
	return made


func _text_of(made: AnalyticsScript, key: String, from: String = FROM, to: String = TO,
		now: String = NOW) -> String:
	return made.figure(key, from, to, now).text()


# --- the table ----------------------------------------------------------------------------------


func test_every_figure_the_specification_lists_is_here_once_and_in_order() -> void:
	var expected: Array[String] = [
		"funnel", "win_rate", "lost_reasons", "average_sale", "average_cycle", "source_performance",
		"pipeline_value", "slipped", "job_profitability", "cost_tracking", "backlog", "wip",
		"ar_aging", "crew_utilisation",
	]
	assert(AnalyticsScript.KEYS == expected,
		"the keys are the table's own figures: %s" % str(AnalyticsScript.KEYS))


func test_every_figure_names_its_basis_and_its_label() -> void:
	for key: String in AnalyticsScript.KEYS:
		assert(not AnalyticsScript.LABELS.get(key, "").is_empty(), "%s has a label" % key)
		assert(not AnalyticsScript.BASES.get(key, "").is_empty(), "%s has a basis" % key)


func test_a_figure_the_table_does_not_have_is_refused_rather_than_answered_with_another() -> void:
	var figure: AnalyticsScript.Figure = _analytics().figure("profit_per_crew")
	assert(not figure.ok, "an unknown figure is not available")
	assert(figure.missing.contains("no figure called 'profit_per_crew'"), figure.missing)


func test_a_report_over_nothing_refuses_the_figures_that_need_records() -> void:
	var made: AnalyticsScript = AnalyticsScript.new()
	var missing := made.unavailable()
	assert(missing.size() >= 12, "almost every figure has nothing to read: %d" % missing.size())
	assert(made.figure("funnel").missing.contains("no pipeline is loaded"),
		made.figure("funnel").missing)
	assert(made.figure("ar_aging").missing.contains("no billing ledger is loaded"),
		made.figure("ar_aging").missing)


func test_describe_says_what_the_report_can_read() -> void:
	assert(AnalyticsScript.new().describe() == "analytics with nothing to read",
		AnalyticsScript.new().describe())
	assert(_analytics().describe() == "analytics over the pipeline, the job desk, the billing ledger",
		_analytics().describe())


func test_a_basis_is_printed_with_every_line() -> void:
	var line := _text_of(_analytics(), "win_rate")
	assert(line.contains("won over won plus lost, by decision date"), line)
	assert(line.contains("2026-01-01 to 2026-03-31"), line)


func test_a_window_with_no_ends_is_every_date_and_one_sided_windows_read_as_they_are() -> void:
	assert(AnalyticsScript.window_text("", "") == "every date", AnalyticsScript.window_text("", ""))
	assert(AnalyticsScript.window_text(FROM, "") == "everything from %s" % FROM,
		AnalyticsScript.window_text(FROM, ""))
	assert(AnalyticsScript.window_text("", TO) == "everything up to %s" % TO,
		AnalyticsScript.window_text("", TO))


# --- the pipeline figures -----------------------------------------------------------------------


func test_the_funnel_counts_where_a_lead_entered_a_stage_not_where_it_is_now() -> void:
	var rows: Array = _analytics().figure("funnel", FROM, TO, NOW).value
	var counts: Dictionary = {}
	for held in rows:
		counts[int(held["stage"])] = int(held["count"])
	# A and B arrived in November and December, which is outside this window, but both were proposed
	# inside it - and A was won inside it too. A bar for March counts March's arrivals.
	assert(counts[LeadScript.PROPOSED] == 3, "three proposals arrived: %s" % str(counts))
	assert(counts[LeadScript.WON] == 2, "two wins arrived: %s" % str(counts))
	assert(counts[LeadScript.LEAD] == 3, "three leads arrived: %s" % str(counts))


func test_a_funnel_reads_the_way_a_person_says_a_count_and_a_name() -> void:
	var line := _text_of(_analytics(), "funnel")
	assert(line.contains("3 leads"), line)
	# One, and it is a site visit: the count and the name agree.
	assert(line.contains("1 site visit,"), line)
	assert(line.contains("0 qualified"), line)
	assert(line.contains("3 proposed"), line)
	assert(line.contains("2 won."), line)


func test_a_funnel_with_nothing_in_it_says_so_rather_than_showing_zeroes() -> void:
	var line := _text_of(_analytics(), "funnel", "2026-05-01", "2026-05-31")
	assert(line.contains("nothing entered the funnel in this window"), line)


func test_win_rate_is_measured_on_the_decision_date_and_withdrawn_is_counted_apart() -> void:
	var figure: AnalyticsScript.Figure = _analytics().figure("win_rate", FROM, TO, NOW)
	assert(figure.ok, figure.missing)
	assert(int(figure.value["won"]) == 2, str(figure.value))
	assert(int(figure.value["lost"]) == 1, str(figure.value))
	assert(int(figure.value["withdrawn"]) == 1, str(figure.value))
	assert(int(figure.value["ppm"]) == 666667, str(figure.value))
	assert(figure.words.contains("2 won, 1 lost, 1 withdrawn, 4 closed"), figure.words)


func test_a_win_rate_with_nothing_decided_is_refused_rather_than_zero() -> void:
	var figure: AnalyticsScript.Figure = _analytics().figure("win_rate", "2026-06-01", "2026-06-30")
	assert(not figure.ok, "nothing was decided, so the rate is unknown")
	assert(figure.missing == "no won or lost leads in this window", figure.missing)


func test_a_win_rate_over_a_loss_that_said_no_reason_is_refused_naming_how_many() -> void:
	var pipe: PipelineScript = _pipeline()
	pipe.add(_unreasoned_loss("G", 700000, "2026-02-14"))
	var made: AnalyticsScript = AnalyticsScript.new(pipe)
	var figure: AnalyticsScript.Figure = made.figure("win_rate", FROM, TO, NOW)
	assert(not figure.ok, "a blank reason is what the report is made of and it is missing")
	assert(figure.missing == "win rate unavailable: 1 of 5 closed leads have no lost reason",
		figure.missing)


func test_lost_reasons_are_tallied_by_reason_with_what_they_were_worth() -> void:
	var rows: Array = _analytics().figure("lost_reasons", FROM, TO, NOW).value
	assert(rows.size() == 1, str(rows))
	assert(String(rows[0]["reason"]) == "price", str(rows[0]))
	assert(int(rows[0]["count"]) == 1, str(rows[0]))
	assert(int(rows[0]["value_cents"]) == 2000000, str(rows[0]))


func test_a_window_that_lost_nothing_says_nothing_was_lost() -> void:
	var line := _text_of(_analytics(), "lost_reasons", "2026-03-01", "2026-03-31")
	assert(line.contains("nothing was lost in this window"), line)


func test_average_sale_is_the_mean_over_the_leads_won_in_the_window() -> void:
	var figure: AnalyticsScript.Figure = _analytics().figure("average_sale", FROM, TO, NOW)
	assert(figure.ok, figure.missing)
	assert(int(figure.value["mean_cents"]) == 2000000, str(figure.value))
	assert(int(figure.value["won"]) == 2, str(figure.value))
	assert(figure.words.contains("$20,000.00 over 2 won lead(s)"), figure.words)


func test_average_sale_names_the_won_leads_that_recorded_no_value() -> void:
	var pipe: PipelineScript = _pipeline()
	pipe.add(_lead("H", &"other", 0, "2025-12-20", LeadScript.WON, "2026-02-20"))
	var figure: AnalyticsScript.Figure = AnalyticsScript.new(pipe).figure("average_sale", FROM, TO, NOW)
	assert(int(figure.value["valued"]) == 2, str(figure.value))
	assert(int(figure.value["unvalued"]) == 1, str(figure.value))
	assert(figure.words.contains("1 had no estimate and count as nothing"), figure.words)


func test_average_sale_with_nothing_won_is_refused_rather_than_zero() -> void:
	var figure: AnalyticsScript.Figure = _analytics().figure("average_sale", "2026-06-01", "2026-06-30")
	assert(not figure.ok, "no lead was won, so there is no average")
	assert(figure.missing == "no lead was won in this window", figure.missing)


func test_average_cycle_measures_lead_to_close_and_estimate_to_decision() -> void:
	var figure: AnalyticsScript.Figure = _analytics().figure("average_cycle", FROM, TO, NOW)
	assert(figure.ok, figure.missing)
	assert(int(figure.value["open_to_close_days"]) == 97, str(figure.value))
	assert(int(figure.value["open_count"]) == 2, str(figure.value))
	assert(int(figure.value["proposed_to_close_days"]) == 34, str(figure.value))
	assert(int(figure.value["proposed_count"]) == 2, str(figure.value))
	assert(figure.words.contains("lead to close 97 day(s) over 2 of 2 won leads"), figure.words)


func test_a_cycle_whose_wins_recorded_no_proposal_says_that_half_is_unknown() -> void:
	var pipe: PipelineScript = PipelineScript.new()
	pipe.add(_lead("A", &"web", 1000000, "2026-01-02", LeadScript.WON, "2026-02-10"))
	var figure: AnalyticsScript.Figure = AnalyticsScript.new(pipe).figure(
		"average_cycle", FROM, TO, NOW
	)
	assert(figure.ok, figure.missing)
	assert(int(figure.value["proposed_count"]) == 0, str(figure.value))
	assert(figure.words.contains("no won lead recorded a proposal date"), figure.words)


func test_average_cycle_with_nothing_won_is_refused() -> void:
	var figure: AnalyticsScript.Figure = _analytics().figure("average_cycle", "2026-06-01", "2026-06-30")
	assert(not figure.ok, "no lead was won, so there is no cycle")
	assert(figure.missing == "no lead was won in this window", figure.missing)


func test_source_performance_reports_a_rate_per_source_and_none_for_a_source_with_nothing_decided() -> void:
	var figure: AnalyticsScript.Figure = _analytics().figure("source_performance", FROM, TO, NOW)
	assert(figure.ok, figure.missing)
	assert(figure.words.contains("Web: 100.0% of 2, average $20,000.00"), figure.words)
	assert(figure.words.contains("Referral: 0.0% of 1"), figure.words)
	assert(figure.words.contains("Yard sign: nothing decided"), figure.words)


func test_pipeline_value_needs_an_as_of_date_and_says_what_is_open() -> void:
	var made: AnalyticsScript = _analytics()
	var refused: AnalyticsScript.Figure = made.figure("pipeline_value", FROM, TO, "")
	assert(not refused.ok, "an as-of date is an input and not a clock this file reads")
	assert(refused.missing.contains("an as-of date is needed"), refused.missing)
	var figure: AnalyticsScript.Figure = made.figure("pipeline_value", FROM, TO, NOW)
	assert(int(figure.value["raw_cents"]) == 5500000, str(figure.value))
	assert(int(figure.value["count"]) == 2, str(figure.value))
	assert(figure.words.contains("over 2 open lead(s)"), figure.words)
	assert(figure.window == "as at 2026-04-01", figure.window)


func test_slipped_names_the_leads_past_their_expected_close_and_nothing_when_there_are_none() -> void:
	var made: AnalyticsScript = _analytics()
	var figure: AnalyticsScript.Figure = made.figure("slipped", FROM, TO, NOW)
	assert(figure.ok, figure.missing)
	assert(figure.value.size() == 1, str(figure.value))
	assert(int(figure.value[0]["days_late"]) == 12, str(figure.value))
	var early: AnalyticsScript.Figure = made.figure("slipped", FROM, TO, "2026-03-01")
	assert(early.value.is_empty(), str(early.value))
	assert(early.words == "nothing open is past its expected close", early.words)


func test_slipped_needs_an_as_of_date_too() -> void:
	var figure: AnalyticsScript.Figure = _analytics().figure("slipped", FROM, TO, "")
	assert(not figure.ok, "nothing is late without a moment to be late at")
	assert(figure.missing.contains("an as-of date is needed"), figure.missing)


# --- the job figures ----------------------------------------------------------------------------


func test_job_profitability_is_agreed_less_cost_per_job_with_the_margin_named() -> void:
	var figure: AnalyticsScript.Figure = _analytics().figure("job_profitability", FROM, TO, NOW)
	assert(figure.ok, figure.missing)
	assert(figure.value.size() == 1, str(figure.value))
	var row: Dictionary = figure.value[0]
	assert(String(row["job"]) == "Smith", str(row))
	assert((row["agreed"] as Money).cents == 2000000, str(row))
	assert((row["cost"] as Money).cents == 54000, str(row))
	assert(bool(row["margin_known"]), str(row))
	assert((row["margin"] as Money).cents == 36000, str(row))
	assert(int(row["percent_ppm"]) == 45000, str(row))
	assert(figure.words.contains("cost $540.00"), figure.words)


func test_a_job_with_no_budget_says_its_margin_is_not_known_rather_than_zero() -> void:
	var desk: JobDeskScript = _job_desk()
	desk.jobs[0].phases = []
	desk.log_time(_entry("T1", &"P1", "2026-03-03", 480))
	var figure: AnalyticsScript.Figure = AnalyticsScript.new(null, desk).figure(
		"job_profitability", FROM, TO, NOW
	)
	assert(figure.ok, figure.missing)
	assert(not bool(figure.value[0]["margin_known"]), str(figure.value[0]))
	assert(figure.words.contains("1 job(s) have no margin"), figure.words)


func test_job_profitability_with_no_job_desk_is_refused() -> void:
	var figure: AnalyticsScript.Figure = AnalyticsScript.new(_pipeline()).figure(
		"job_profitability", FROM, TO, NOW
	)
	assert(not figure.ok, "there is no job desk to report on")
	assert(figure.missing.contains("no job desk is loaded"), figure.missing)


func test_cost_tracking_is_one_row_per_code_and_counts_what_is_committed_past_budget() -> void:
	var figure: AnalyticsScript.Figure = _analytics().figure("cost_tracking", FROM, TO, NOW)
	assert(figure.ok, figure.missing)
	assert(figure.value.size() == 2, "two codes were budgeted: %d" % figure.value.size())
	assert(figure.words.contains("1 job(s), 2 cost code(s)"), figure.words)
	var codes: Array[String] = []
	for held in figure.value:
		codes.append(String(held["cost_code"]))
	assert(codes.has("HARDSCAPE") and codes.has("PLANTING"), str(codes))


func test_backlog_is_the_agreed_sum_less_what_the_invoices_say() -> void:
	var figure: AnalyticsScript.Figure = _analytics().figure("backlog", FROM, TO, NOW)
	assert(figure.ok, figure.missing)
	assert(int(figure.value["cents"]) == 1980000, str(figure.value))
	assert(figure.words.contains("$19,800.00 of approved work not yet billed"), figure.words)


func test_backlog_reads_the_invoices_and_not_the_desk_dictionary() -> void:
	var desk: JobDeskScript = _job_desk()
	# The desk's own memory of what has been billed disagrees with the invoice that went out. A
	# document and a number somebody typed are not the same kind of evidence.
	desk.invoiced["J1"] = MoneyScript.of(0)
	var ledger: BillingDeskScript = _billing(desk)
	ledger.invoices.append(_invoice("INV-1", "J-1", 20000, "2026-01-10"))
	var made: AnalyticsScript = AnalyticsScript.new(null, desk, ledger)
	var figure: AnalyticsScript.Figure = made.figure("backlog", FROM, TO, NOW)
	assert(int(figure.value["cents"]) == 1980000, "the invoice is what counts: %s" % str(figure.value))


func test_backlog_falls_back_to_the_desks_own_figure_and_says_that_it_has() -> void:
	var desk: JobDeskScript = _job_desk()
	desk.invoiced["J1"] = MoneyScript.of(500000)
	var figure: AnalyticsScript.Figure = AnalyticsScript.new(null, desk).figure(
		"backlog", FROM, TO, NOW
	)
	assert(figure.ok, figure.missing)
	assert(int(figure.value["cents"]) == 1500000, str(figure.value))
	assert(figure.words.contains("no ledger is loaded"), figure.words)


func test_backlog_with_nothing_recorded_as_billed_is_refused_naming_the_job() -> void:
	var figure: AnalyticsScript.Figure = AnalyticsScript.new(null, _job_desk()).figure(
		"backlog", FROM, TO, NOW
	)
	assert(not figure.ok, "nothing says what has been billed, so what is left cannot be worked out")
	assert(figure.missing.contains("nothing is recorded as billed against Smith"), figure.missing)


func test_a_job_billed_past_its_agreement_is_named_rather_than_hidden() -> void:
	var desk: JobDeskScript = _job_desk()
	desk.invoiced["J1"] = MoneyScript.of(2500000)
	var figure: AnalyticsScript.Figure = AnalyticsScript.new(null, desk).figure(
		"backlog", FROM, TO, NOW
	)
	assert(figure.ok, figure.missing)
	assert(int(figure.value["cents"]) == -500000, str(figure.value))
	assert(figure.words.contains("Smith has been billed past what was agreed"), figure.words)


func test_work_in_progress_is_cost_incurred_against_billed_to_date() -> void:
	var figure: AnalyticsScript.Figure = _analytics().figure("wip", FROM, TO, NOW)
	assert(figure.ok, figure.missing)
	assert(int(figure.value["cents"]) == 34000, str(figure.value))
	assert(figure.words.contains("$340.00 worked ahead of billing"), figure.words)


func test_work_in_progress_with_nothing_billed_is_refused_rather_than_read_as_nothing() -> void:
	var figure: AnalyticsScript.Figure = AnalyticsScript.new(null, _job_desk()).figure(
		"wip", FROM, TO, NOW
	)
	assert(not figure.ok, "cost against billing needs a billed figure")
	assert(figure.missing.contains("cost against billing cannot be worked out"), figure.missing)


# --- money owed ---------------------------------------------------------------------------------


func test_ageing_buckets_an_invoice_by_how_late_it_is_and_puts_one_not_yet_due_first() -> void:
	var desk: JobDeskScript = _job_desk()
	var ledger: BillingDeskScript = _billing(desk)
	ledger.invoices.append(_invoice("INV-1", "J-1", 100000, "2026-01-01"))
	ledger.invoices.append(_invoice("INV-2", "J-1", 200000, "2026-03-20"))
	ledger.invoices.append(_invoice("INV-3", "J-1", 300000, "2025-12-01"))
	var made: AnalyticsScript = AnalyticsScript.new(null, desk, ledger)
	var figure: AnalyticsScript.Figure = made.figure("ar_aging", FROM, TO, NOW)
	assert(figure.ok, figure.missing)
	assert(int(figure.value["count"]) == 3, str(figure.value))
	assert(int(figure.value["cents"]) == 600000, str(figure.value))
	var buckets: Array = figure.value["buckets"]
	assert(int(buckets[0]["count"]) == 1, "not yet due sits in the first bucket: %s" % str(buckets))
	assert(int(buckets[1]["count"]) == 1, "sixty days late is 31-60: %s" % str(buckets))
	assert(int(buckets[2]["count"]) == 0, str(buckets))
	assert(int(buckets[3]["count"]) == 1, "ninety-one days late is 90+: %s" % str(buckets))


func test_ageing_leaves_out_a_void_invoice_and_one_that_never_went_out() -> void:
	var desk: JobDeskScript = _job_desk()
	var ledger: BillingDeskScript = _billing(desk)
	ledger.invoices.append(_invoice("INV-1", "J-1", 100000, "2026-01-01"))
	var voided: InvoiceScript = _invoice("INV-2", "J-1", 50000, "2026-01-05")
	voided.mark_void("2026-02-01", "raised twice")
	ledger.invoices.append(voided)
	var draft: InvoiceScript = InvoiceScript.new("I-DRAFT")
	draft.job = "J-1"
	draft.add_line(InvoiceScript.MILESTONE_LINE, "Deposit", 1000, &"EACH",
		MoneyScript.of(70000), &"HARDSCAPE", &"EXEMPT")
	ledger.invoices.append(draft)
	var figure: AnalyticsScript.Figure = AnalyticsScript.new(null, desk, ledger).figure(
		"ar_aging", FROM, TO, NOW
	)
	assert(int(figure.value["count"]) == 1, str(figure.value))
	assert(int(figure.value["cents"]) == 100000, str(figure.value))


func test_ageing_says_nothing_is_unpaid_rather_than_showing_four_zeroes() -> void:
	var desk: JobDeskScript = _job_desk()
	var figure: AnalyticsScript.Figure = AnalyticsScript.new(
		null, desk, _billing(desk)
	).figure("ar_aging", FROM, TO, NOW)
	assert(figure.ok, figure.missing)
	assert(int(figure.value["count"]) == 0, str(figure.value))
	assert(figure.words == "nothing is unpaid", figure.words)


func test_ageing_needs_an_as_of_date_because_an_age_is_an_age_today() -> void:
	var figure: AnalyticsScript.Figure = _analytics().figure("ar_aging", FROM, TO, "")
	assert(not figure.ok, "there is no age without a moment to age against")
	assert(figure.missing.contains("an as-of date is needed"), figure.missing)


# --- hours --------------------------------------------------------------------------------------


func test_crew_utilisation_refuses_until_a_working_day_is_stated() -> void:
	var made: AnalyticsScript = _analytics()
	made.working_day_minutes = 0
	var figure: AnalyticsScript.Figure = made.figure("crew_utilisation", WEEK_FROM, WEEK_TO)
	assert(not figure.ok, "available hours need a day length, and this file will not invent one")
	assert(figure.missing.contains("no working day is stated"), figure.missing)
	assert(made.set_working_day(0) == false, "a day of no hours is not a day")
	assert(made.set_working_day(-60) == false, "a day of minus hours is not a day")
	assert(made.set_working_day(480), "eight hours is a day")
	assert(made.working_day_text() == "8 hours 0 minutes", made.working_day_text())
	assert(made.working_day_stated(), "the day is stated")


func test_crew_utilisation_is_approved_hours_over_the_days_a_person_is_available() -> void:
	var figure: AnalyticsScript.Figure = _analytics().figure("crew_utilisation", WEEK_FROM, WEEK_TO)
	assert(figure.ok, figure.missing)
	var rows: Array = figure.value["rows"]
	assert(rows.size() == 2, str(rows))
	assert(String(rows[0]["crew"]) == "P1", str(rows))
	assert(int(rows[0]["approved_minutes"]) == 480, str(rows[0]))
	assert(int(rows[0]["available_minutes"]) == 2880, "six days, the Sunday off: %s" % str(rows[0]))
	assert(int(rows[0]["ppm"]) == 166667, str(rows[0]))
	assert(int(rows[1]["available_minutes"]) == 3360, "seven days: %s" % str(rows[1]))
	assert(int(figure.value["approved_minutes"]) == 720, str(figure.value))
	assert(int(figure.value["available_minutes"]) == 6240, str(figure.value))
	assert(figure.words.contains("worked"), figure.words)


func test_an_unapproved_entry_is_not_an_hour_worked() -> void:
	var figure: AnalyticsScript.Figure = _analytics().figure("crew_utilisation", WEEK_FROM, WEEK_TO)
	for held in figure.value["rows"]:
		if String(held["crew"]) == "P1":
			assert(int(held["approved_minutes"]) == 480,
				"the 300 minute entry nobody approved is not hours: %s" % str(held))


func test_a_day_of_its_own_gives_a_whole_day_of_utilisation() -> void:
	var figure: AnalyticsScript.Figure = _analytics().figure("crew_utilisation", "2026-03-03", "2026-03-03")
	var rows: Array = figure.value["rows"]
	assert(int(rows[0]["available_minutes"]) == 480, str(rows[0]))
	assert(int(rows[0]["ppm"]) == 1000000, str(rows[0]))


func test_utilisation_needs_both_ends_of_the_window_and_a_window_a_report_could_be_for() -> void:
	var made: AnalyticsScript = _analytics()
	var half: AnalyticsScript.Figure = made.figure("crew_utilisation", WEEK_FROM, "")
	assert(not half.ok, "one end is not a period")
	assert(half.missing.contains("both ends readable"), half.missing)
	var years: AnalyticsScript.Figure = made.figure("crew_utilisation", "2020-01-01", "2026-03-31")
	assert(not years.ok, "a window of years is a mistyped year")
	assert(years.missing.contains("longer than 400 days"), years.missing)


func test_a_crew_member_nobody_scheduled_shows_no_hours_but_is_still_listed() -> void:
	var desk: JobDeskScript = _job_desk()
	desk.add_crew(CrewScript.new(&"P3", "Mary"))
	var made: AnalyticsScript = AnalyticsScript.new(_pipeline(), desk)
	made.set_working_day(480)
	var figure: AnalyticsScript.Figure = made.figure("crew_utilisation", WEEK_FROM, WEEK_TO)
	var rows: Array = figure.value["rows"]
	assert(rows.size() == 3, str(rows))
	assert(int(rows[2]["approved_minutes"]) == 0, str(rows[2]))
	assert(int(rows[2]["ppm"]) == 0, str(rows[2]))


# --- recomputable, and nothing cached -----------------------------------------------------------


func test_a_past_window_is_the_same_answer_when_it_is_asked_again_later() -> void:
	var made: AnalyticsScript = _analytics()
	var past_from := "2025-11-01"
	var past_to := "2025-12-31"
	var before := made.figure("funnel", past_from, past_to, NOW).text()
	var whole_before := made.figure("funnel", FROM, TO, NOW).text()
	# February and March get busier, and a report for a window that has already closed must not move
	# because of it (REQ-B15, AC-B17).
	made.pipeline.add(_lead("Z", &"web", 9000000, "2026-02-25", LeadScript.WON, "2026-03-20"))
	made.pipeline.add(_lead("Y", &"web", 9000000, "2026-03-01", LeadScript.LOST, "2026-03-25",
		"", &"timing"))
	assert(made.figure("funnel", past_from, past_to, NOW).text() == before,
		"a window that closed before either arrival cannot have changed")
	assert(made.figure("funnel", FROM, TO, NOW).text() != whole_before,
		"and the window they did arrive in must have changed")


func test_the_same_report_asked_twice_is_the_same_report() -> void:
	var made: AnalyticsScript = _analytics()
	var first: Array[String] = []
	for held in made.figures(FROM, TO, NOW):
		first.append(held.text())
	var second: Array[String] = []
	for held in made.figures(FROM, TO, NOW):
		second.append(held.text())
	assert(first == second, "nothing here is accumulated, so nothing here drifts")


func test_reading_the_figures_does_not_change_the_records() -> void:
	var made: AnalyticsScript = _analytics()
	var leads_before := made.pipeline.leads.size()
	var entries_before := made.jobs.time_entries.size()
	var invoices_before := made.billing.invoices.size()
	made.figures(FROM, TO, NOW)
	assert(made.pipeline.leads.size() == leads_before, "no lead was added")
	assert(made.jobs.time_entries.size() == entries_before, "no entry was added")
	assert(made.billing.invoices.size() == invoices_before, "no invoice was added")


func test_the_summary_counts_the_figures_and_what_could_not_be_worked_out() -> void:
	var made: AnalyticsScript = AnalyticsScript.new()
	var line := made.summary_text(FROM, TO, "")
	assert(line == "14 figures for 2026-01-01 to 2026-03-31, 14 unavailable", line)
	var whole := _analytics().summary_text(FROM, TO, NOW)
	assert(whole == "14 figures for 2026-01-01 to 2026-03-31, all of them available", whole)


func test_what_could_not_be_worked_out_names_its_own_missing_input() -> void:
	var made: AnalyticsScript = AnalyticsScript.new(_pipeline())
	made.set_working_day(480)
	var missing := made.unavailable(FROM, TO, "")
	assert(missing.has("Pipeline value unavailable: an as-of date is needed, because what is open is open now"),
		str(missing))
	assert(missing.has("Crew utilisation unavailable: no job desk is loaded, so there are no crews or timesheets"),
		str(missing))
	for line: String in missing:
		assert(line.contains("unavailable"), line)