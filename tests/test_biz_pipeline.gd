extends Node
## The pipeline: stages as events, and every figure a pure function of the history (spec §4.7, §10).
##
## These tests hold the two properties the module is written for. The first is REQ-B4: nothing here is
## a live accumulator, so a figure for a past window is computed from the events and reads the same
## next year. The second is REQ-B16: a figure that cannot be computed is refused, naming what is
## missing, rather than shown as a zero that looks like an answer.

const LeadScript := preload("res://scripts/biz/lead.gd")
const PipelineScript := preload("res://scripts/biz/pipeline.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")


## A lead with an opening event, so it exists in the event history the funnel reads.
func _lead(id: String, cents: int, source: StringName, at: String) -> LeadScript:
	var lead: LeadScript = LeadScript.new(id, "Lead " + id)
	lead.value_estimate = MoneyScript.of(cents)
	lead.source = source
	lead.open(at, "evan")
	return lead


func _marched() -> PipelineScript:
	## Three March leads: one won, one lost for price, one withdrawn. Returns the pipeline.
	var pipe: PipelineScript = PipelineScript.new()
	pipe.add(_lead("L1", 500000, &"referral", "2026-03-01T09:00:00Z"))
	pipe.add(_lead("L2", 300000, &"web", "2026-03-02T09:00:00Z"))
	pipe.add(_lead("L3", 200000, &"repeat", "2026-03-03T09:00:00Z"))
	pipe.find("L2").move_to(LeadScript.QUALIFIED, "2026-03-05T09:00:00Z", "evan")
	pipe.find("L2").move_to(LeadScript.PROPOSED, "2026-03-10T09:00:00Z", "evan")
	pipe.find("L2").set_lost_reason(&"price")
	pipe.find("L2").move_to(LeadScript.LOST, "2026-03-20T09:00:00Z", "evan")
	pipe.find("L1").move_to(LeadScript.WON, "2026-03-12T09:00:00Z", "evan")
	pipe.find("L3").move_to(LeadScript.WITHDRAWN, "2026-03-14T09:00:00Z", "evan")
	return pipe


# --- a stage is a field plus a history -------------------------------------------------------


func test_opening_a_lead_records_an_arrival_event() -> void:
	var lead: LeadScript = LeadScript.new("L1", "Smith, patio")
	var result := lead.open("2026-03-01T09:00:00Z", "evan")
	assert(result["ok"])
	assert(lead.event_count() == 1, "an arrival is an event like any other")
	assert(int(lead.events[0]["to"]) == LeadScript.LEAD)
	assert(int(lead.events[0]["from"]) == -1, "nothing comes before an arrival")


func test_a_lead_cannot_be_opened_twice() -> void:
	var lead := _lead("L1", 100000, &"referral", "2026-03-01T09:00:00Z")
	var again := lead.open("2026-03-02T09:00:00Z", "evan")
	assert(not again["ok"], "opening is not a way to fake a second arrival")
	assert(lead.event_count() == 1)


func test_moving_a_lead_appends_an_event_and_never_just_sets_a_field() -> void:
	var lead := _lead("L1", 100000, &"referral", "2026-03-01T09:00:00Z")
	assert(lead.move_to(LeadScript.QUALIFIED, "2026-03-02T09:00:00Z", "evan")["ok"])
	assert(lead.stage == LeadScript.QUALIFIED)
	assert(lead.event_count() == 2)
	var event: Dictionary = lead.events[1]
	assert(int(event["from"]) == LeadScript.LEAD and int(event["to"]) == LeadScript.QUALIFIED)
	assert(event["at"] == "2026-03-02T09:00:00Z" and event["by"] == "evan")


func test_a_move_is_refused_for_a_stage_nobody_has_or_a_place_it_already_is() -> void:
	var lead := _lead("L1", 100000, &"referral", "2026-03-01T09:00:00Z")
	assert(not lead.move_to(99, "2026-03-02T09:00:00Z", "evan")["ok"], "99 is not a stage")
	assert(not lead.move_to(LeadScript.LEAD, "2026-03-02T09:00:00Z", "evan")["ok"],
		"a transition that changes nothing is not a transition")
	assert(lead.event_count() == 1, "a refused move left no event behind")


func test_a_lead_cannot_be_lost_without_saying_why() -> void:
	var lead := _lead("L1", 100000, &"referral", "2026-03-01T09:00:00Z")
	var refused := lead.move_to(LeadScript.LOST, "2026-03-05T09:00:00Z", "evan")
	assert(not refused["ok"], "the loss reason is the whole win/loss report")
	assert("lost reason" in String(refused["reason"]))
	lead.set_lost_reason(&"price")
	assert(lead.move_to(LeadScript.LOST, "2026-03-05T09:00:00Z", "evan")["ok"])


func test_closing_sets_the_decision_date_and_reopening_clears_it() -> void:
	var lead := _lead("L1", 100000, &"referral", "2026-03-01T09:00:00Z")
	lead.move_to(LeadScript.WON, "2026-03-12T09:00:00Z", "evan")
	assert(lead.closed_at == "2026-03-12T09:00:00Z")
	assert(not lead.is_open())
	# A reopened lead is open again - and a stale decision date would put it in a past period.
	lead.move_to(LeadScript.ESTIMATING, "2026-04-01T09:00:00Z", "evan")
	assert(lead.closed_at.is_empty(), "a reopened lead has no decision date")
	assert(lead.is_open())


# --- the funnel reads events, not the present -----------------------------------------------


func test_the_funnel_places_a_lead_by_where_it_arrived_not_where_it_is() -> void:
	var pipe := _marched()
	var rows := pipe.funnel("2026-03-01", "2026-03-31T23:59:59Z")
	var by_stage: Dictionary = {}
	for row in rows:
		by_stage[int(row["stage"])] = row
	# All three arrived in March, though only one is still at the top of the funnel.
	assert(int(by_stage[LeadScript.LEAD]["count"]) == 3)
	assert(int(by_stage[LeadScript.LEAD]["value_cents"]) == 1000000)
	assert(int(by_stage[LeadScript.PROPOSED]["count"]) == 1, "L2 was proposed in March")
	assert(int(by_stage[LeadScript.WON]["count"]) == 1, "L1 was won in March")


func test_a_funnel_window_excludes_arrivals_outside_it() -> void:
	var pipe := _marched()
	var april := pipe.funnel("2026-04-01", "2026-04-30")
	var lead_bar: Dictionary = april[0]
	assert(int(lead_bar["count"]) == 0, "no lead arrived in April")
	assert(pipe.funnel("2026-03-01", "2026-03-31").size() == LeadScript.FUNNEL_ORDER.size())


func test_a_figure_for_a_past_window_is_recomputed_from_the_events() -> void:
	# REQ-B4/B15: the March figure is a pure function of the history, so it reads the same whenever
	# it is asked. There is no accumulator to drift.
	var pipe := _marched()
	var first := pipe.funnel("2026-03-01", "2026-03-31T23:59:59Z")
	var second := pipe.funnel("2026-03-01", "2026-03-31T23:59:59Z")
	assert(first == second, "the same window yields the same funnel")
	assert(int(first[0]["count"]) == 3)


func test_conversion_counts_the_leads_that_reached_one_bar_and_went_on_to_the_next() -> void:
	var pipe := _marched()
	var lead_to_proposed := pipe.conversion(LeadScript.LEAD, LeadScript.PROPOSED,
		"2026-03-01", "2026-03-31")
	assert(lead_to_proposed["ok"])
	assert(int(lead_to_proposed["reached"]) == 3)
	assert(int(lead_to_proposed["converted"]) == 1)
	assert(int(lead_to_proposed["ppm"]) == 333333)


func test_a_conversion_out_of_no_leads_is_unknown_not_zero() -> void:
	var pipe := _marched()
	var visit_to_won := pipe.conversion(LeadScript.VISIT, LeadScript.WON, "2026-03-01", "2026-03-31")
	assert(not visit_to_won["ok"], "a conversion from nothing is not zero per cent")
	assert("no leads reached" in String(visit_to_won["reason"]))


# --- win, loss, and why ----------------------------------------------------------------------


func test_win_rate_is_measured_on_the_decision_date_and_counted_apart_from_withdrawals() -> void:
	var pipe := _marched()
	var rate := pipe.win_rate("2026-03-01", "2026-03-31")
	assert(rate["ok"])
	assert(int(rate["won"]) == 1 and int(rate["lost"]) == 1)
	assert(int(rate["withdrawn"]) == 1, "a withdrawal is counted, not decided")
	assert(int(rate["ppm"]) == 500000, "one of one won and one lost is a half")


func test_win_rate_is_refused_when_a_closed_lead_has_no_reason() -> void:
	# A record that arrived from elsewhere: closed as lost, with the reason never filled in.
	var pipe: PipelineScript = PipelineScript.new()
	pipe.leads.append(LeadScript.from_dict({
		"id": "IMPORT-1", "name": "Imported", "stage": LeadScript.LOST,
		"closed_at": "2026-03-20T09:00:00Z", "value_estimate": MoneyScript.of(100000).to_dict(),
	}))
	var rate := pipe.win_rate("2026-03-01", "2026-03-31")
	assert(not rate["ok"], "a win rate that ignored the blanks is a number nobody should trust")
	assert(rate["reason"] == "win rate unavailable: 1 of 1 closed leads have no lost reason")


func test_win_rate_with_nothing_decided_is_refused() -> void:
	var pipe: PipelineScript = PipelineScript.new()
	pipe.add(_lead("L1", 100000, &"web", "2026-03-01T09:00:00Z"))
	var rate := pipe.win_rate("2026-03-01", "2026-03-31")
	assert(not rate["ok"])
	assert("no won or lost leads" in String(rate["reason"]))


func test_lost_reasons_tally_count_and_value_most_frequent_first() -> void:
	var pipe := _marched()
	pipe.add(_lead("L4", 400000, &"web", "2026-03-04T09:00:00Z"))
	pipe.find("L4").set_lost_reason(&"price")
	pipe.find("L4").move_to(LeadScript.LOST, "2026-03-21T09:00:00Z", "evan")
	var rows := pipe.lost_reasons("2026-03-01", "2026-03-31")
	assert(rows.size() == 1)
	assert(rows[0]["reason"] == "price")
	assert(int(rows[0]["count"]) == 2, "two leads lost for price")
	assert(int(rows[0]["value_cents"]) == 700000)


func test_a_lost_lead_with_no_reason_is_tallied_under_a_named_blank() -> void:
	var pipe: PipelineScript = PipelineScript.new()
	pipe.leads.append(LeadScript.from_dict({
		"id": "L9", "stage": LeadScript.LOST, "closed_at": "2026-03-09T09:00:00Z",
		"value_estimate": MoneyScript.of(1000).to_dict(),
	}))
	var rows := pipe.lost_reasons("2026-03-01", "2026-03-31")
	assert(rows.size() == 1 and rows[0]["name"] == "No reason given")


func test_source_performance_is_sorted_by_name_and_reports_a_win_rate_by_source() -> void:
	var pipe := _marched()
	var rows := pipe.source_performance("2026-03-01", "2026-03-31")
	var names: Array[String] = []
	for row in rows:
		names.append(String(row["name"]))
	# StringName keys sort as pointers, not lexicographically, so the sort is on the String form -
	# this is the assertion that would fail if the keys were handed straight to `sort()`.
	var sorted_names := names.duplicate()
	sorted_names.sort()
	assert(names == sorted_names, "sources come out in name order")
	var by_source: Dictionary = {}
	for row in rows:
		by_source[String(row["source"])] = row
	assert(int(by_source["referral"]["ppm"]) == 1000000, "referral won its one decided lead")
	assert(int(by_source["repeat"]["closed"]) == 0, "a withdrawal is not a decided lead")
	assert("no decided leads" in String(by_source["repeat"]["reason"]))


# --- the present -----------------------------------------------------------------------------


func test_pipeline_value_reports_raw_and_a_stated_weighted_figure() -> void:
	var pipe: PipelineScript = PipelineScript.new()
	pipe.add(_lead("L1", 1000000, &"web", "2026-03-01T09:00:00Z"))
	pipe.find("L1").move_to(LeadScript.PROPOSED, "2026-03-05T09:00:00Z", "evan")
	var value := pipe.pipeline_value()
	assert(int(value["raw_cents"]) == 1000000)
	assert(int(value["weighted_cents"]) == 800000, "PROPOSED weighs 800000 ppm in the stated table")
	assert((value["stages_missing_odds"] as Array).is_empty())


func test_every_open_stage_has_stated_odds_so_the_missing_list_is_empty() -> void:
	# `pipeline_value` reports the open stages it could not weight rather than quietly counting them
	# at zero. That guard is only ever exercised if somebody adds an open stage and forgets the odds,
	# so the invariant it depends on is asserted here directly.
	var open_stages: Array[int] = []
	for stage_value in LeadScript.STAGES.keys():
		var stage_int := int(stage_value)
		if not LeadScript.is_closed(stage_int):
			open_stages.append(stage_int)
			assert(PipelineScript.ODDS_PPM.has(stage_int),
				"%s is an open stage with no stated odds" % LeadScript.stage_name(stage_int))
	var pipe: PipelineScript = PipelineScript.new()
	for stage_int in open_stages:
		var lead := _lead("L%d" % stage_int, 100000, &"web", "2026-03-01T09:00:00Z")
		lead.stage = stage_int
		pipe.add(lead)
	assert((pipe.pipeline_value()["stages_missing_odds"] as Array).is_empty())


func test_slipped_lists_open_leads_past_their_expected_close_most_late_first() -> void:
	var pipe: PipelineScript = PipelineScript.new()
	var a := _lead("L1", 100000, &"web", "2026-01-01T09:00:00Z")
	a.expected_close_at = "2026-03-01T00:00:00Z"
	var b := _lead("L2", 100000, &"web", "2026-01-01T09:00:00Z")
	b.expected_close_at = "2026-03-20T00:00:00Z"
	var c := _lead("L3", 100000, &"web", "2026-01-01T09:00:00Z")
	c.expected_close_at = ""  # unscheduled, not late
	var d := _lead("L4", 100000, &"web", "2026-01-01T09:00:00Z")
	d.expected_close_at = "2026-05-01T00:00:00Z"  # not yet due
	pipe.add(a)
	pipe.add(b)
	pipe.add(c)
	pipe.add(d)
	var rows := pipe.slipped("2026-04-01T00:00:00Z")
	assert(rows.size() == 2)
	assert(rows[0]["id"] == "L1", "the most late lead comes first")
	assert(int(rows[0]["days_late"]) == 31)
	assert(int(rows[1]["days_late"]) == 12)


func test_columns_are_one_per_stage_in_funnel_order() -> void:
	var pipe := _marched()
	var columns := pipe.columns()
	assert(columns.size() == 9)
	assert(int(columns[0]["stage"]) == LeadScript.LEAD)
	assert((columns[0]["leads"] as Array).size() == 0, "all three have moved on")


# --- the file --------------------------------------------------------------------------------


func test_a_pipeline_round_trips_through_its_dict_with_its_events() -> void:
	var pipe := _marched()
	var restored := PipelineScript.from_dict(pipe.to_dict())
	assert(restored.lead_count() == 3)
	var l2: LeadScript = restored.find("L2")
	assert(l2.stage == LeadScript.LOST)
	assert(l2.closed_at == "2026-03-20T09:00:00Z")
	assert(l2.lost_reason == &"price")
	assert(l2.event_count() == 4, "the whole history survives the file, not just the stage")
	assert(restored.find("L1").source == &"referral")


func test_a_record_that_is_not_a_lead_is_dropped_and_a_damaged_stage_is_led() -> void:
	var pipe := PipelineScript.from_dict({
		"leads": [
			{"name": "no id here"},
			{"id": "L1", "name": "ok", "stage": 99},
		],
	})
	assert(pipe.lead_count() == 1, "a record with no id is not a lead with a blank id")
	assert(pipe.find("L1").stage == LeadScript.LEAD, "a lead has to be somewhere, so it starts")


func test_a_lead_with_no_estimate_is_worth_nothing_not_unreadable() -> void:
	var lead: LeadScript = LeadScript.new("L1", "x")
	assert(lead.value().is_zero())
	assert(lead.value().is_valid())