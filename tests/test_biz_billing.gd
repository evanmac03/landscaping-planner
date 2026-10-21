extends Node
## Billing: what a job can bill right now, by the method its contract agreed to (spec §9.1-§9.3).
##
## The arithmetic under test is §9.3's, and it is the one this module exists for: **billing 30% and
## then 60% bills 30% twice only in software that computes the percentage as the amount.** The target
## is `contract x percent`, the amount due is `target - billed_to_date`, and the floor at zero is a
## refusal done with arithmetic rather than a guard that could be forgotten.

const BillingScript := preload("res://scripts/biz/billing.gd")
const MilestoneScript := preload("res://scripts/biz/milestone.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")
const RateScript := preload("res://scripts/biz/rate.gd")
const JobScript := preload("res://scripts/biz/job.gd")

## $10,000.00, so every percentage below is a round number of cents and a wrong one is obvious.
const CONTRACT_CENTS := 1000000


func _contract() -> MoneyScript:
	return MoneyScript.of(CONTRACT_CENTS)


func _schedule(method_key: int = JobScript.PERCENTAGE_COMPLETE) -> BillingScript:
	return BillingScript.for_method("J1", method_key)


func _step(step_name: String, ppm: int) -> MilestoneScript:
	var step: MilestoneScript = MilestoneScript.new(step_name)
	assert(step.set_percent(ppm))
	return step


func _three_steps(schedule: BillingScript) -> void:
	assert(schedule.add_milestone(_step("Deposit", 300000)))
	assert(schedule.add_milestone(_step("Rough grade", 300000)))
	assert(schedule.add_milestone(_step("Final", 400000)))


# --- the method comes from the contract --------------------------------------------------------


func test_the_method_is_the_one_the_contract_agreed_to() -> void:
	assert(_schedule(JobScript.MILESTONE).method == JobScript.MILESTONE)
	assert(_schedule(JobScript.PERCENTAGE_COMPLETE).method_name() == "percentage complete")


func test_a_method_nobody_has_falls_back_to_the_contracts_default_and_says_so() -> void:
	var schedule := _schedule(99)
	assert(schedule.method == JobScript.FIXED)
	assert(schedule.method_name() == "fixed price")


# --- fixed price -------------------------------------------------------------------------------


func test_a_fixed_price_job_bills_the_whole_contract_once() -> void:
	var schedule := _schedule(JobScript.FIXED)
	var first: Dictionary = schedule.amount_due(_contract())
	assert(bool(first["ok"]))
	assert((first["amount"] as MoneyScript).cents == CONTRACT_CENTS)
	var recorded: Dictionary = schedule.record_billed(_contract(), first["amount"], "2026-06-01", "INV-2026-0001")
	assert(bool(recorded["ok"]))
	assert(schedule.billed_to_date.cents == CONTRACT_CENTS)
	var again: Dictionary = schedule.amount_due(_contract())
	assert(bool(again["ok"]))
	assert((again["amount"] as MoneyScript).is_zero())
	assert(String(again["reason"]).contains("has been billed"), String(again["reason"]))


func test_a_negative_billing_is_a_credit_note_and_not_a_billing() -> void:
	var schedule := _schedule(JobScript.FIXED)
	var recorded: Dictionary = schedule.record_billed(_contract(), MoneyScript.of(-50000), "2026-06-01", "INV-2026-0001")
	assert(not bool(recorded["ok"]))
	assert(schedule.billed_to_date.is_zero())


func test_a_billing_with_no_moment_or_no_number_is_not_recorded() -> void:
	var schedule := _schedule(JobScript.FIXED)
	assert(not bool(schedule.record_billed(_contract(), MoneyScript.of(100), "", "INV-2026-0001")["ok"]))
	assert(not bool(schedule.record_billed(_contract(), MoneyScript.of(100), "2026-06-01", "")["ok"]))
	assert(schedule.billed_to_date.is_zero())


# --- percentage complete: the double-billing guard ----------------------------------------------


func test_the_target_is_the_contract_times_the_percent_complete() -> void:
	var schedule := _schedule()
	assert(schedule.set_percent_complete(300000, BillingScript.BY_COST_INCURRED))
	assert(schedule.target_billed(_contract()).cents == 300000)


func test_two_billings_at_thirty_and_sixty_percent_are_equal_and_a_third_is_nothing() -> void:
	var schedule := _schedule()
	assert(schedule.set_percent_complete(300000, BillingScript.BY_COST_INCURRED))
	var first: Dictionary = schedule.amount_due(_contract())
	assert((first["amount"] as MoneyScript).cents == 300000)
	assert(bool(schedule.record_billed(_contract(), first["amount"], "2026-06-01", "INV-2026-0001")["ok"]))
	assert(schedule.set_percent_complete(600000, BillingScript.BY_COST_INCURRED))
	var second: Dictionary = schedule.amount_due(_contract())
	assert((second["amount"] as MoneyScript).cents == 300000, "the second billing is the difference, not 60%")
	assert(bool(schedule.record_billed(_contract(), second["amount"], "2026-07-01", "INV-2026-0002")["ok"]))
	assert(schedule.billed_to_date.cents == 600000)
	var third: Dictionary = schedule.amount_due(_contract())
	assert(bool(third["ok"]))
	assert((third["amount"] as MoneyScript).is_zero())
	assert((String(third["reason"])).contains("already billed"), String(third["reason"]))


func test_a_percent_nobody_measured_is_refused_rather_than_taken_as_nothing() -> void:
	var schedule := _schedule()
	var refused: Dictionary = schedule.amount_due(_contract())
	assert(not bool(refused["ok"]))
	assert(String(refused["reason"]) == "nobody has measured the percent complete of this job",
		String(refused["reason"]))


func test_a_percent_nobody_could_have_measured_is_refused_and_the_basis_is_required() -> void:
	var schedule := _schedule()
	assert(not schedule.set_percent_complete(0, BillingScript.BY_COST_INCURRED))
	assert(not schedule.set_percent_complete(RateScript.WHOLE + 1, BillingScript.BY_COST_INCURRED))
	assert(not schedule.set_percent_complete(500000, 7))
	assert(not RateScript.is_valid(schedule.complete_ppm))


func test_the_basis_travels_with_the_number() -> void:
	var schedule := _schedule()
	assert(schedule.set_percent_complete(500000, BillingScript.BY_PHASE_COMPLETION))
	assert(schedule.basis_name() == "by phase completion")
	assert(schedule.describe().contains("50% complete by phase completion"), schedule.describe())
	var back: BillingScript = BillingScript.from_dict(schedule.to_dict())
	assert(back.complete_ppm == 500000)
	assert(back.percent_basis == BillingScript.BY_PHASE_COMPLETION)
	assert(back.is_sound())


func test_a_measured_percent_whose_basis_did_not_survive_is_named_rather_than_guessed_at() -> void:
	var broken: BillingScript = BillingScript.from_dict({
		"job": "J1",
		"method": "PERCENTAGE_COMPLETE",
		"complete_ppm": 500000,
		"percent_basis": -1,
	})
	assert(not broken.is_sound())
	assert(broken.problems().has("a measured percent complete with no basis stated"), str(broken.problems()))


func test_the_contract_sum_being_unreadable_is_refused_rather_than_billed() -> void:
	var schedule := _schedule(JobScript.FIXED)
	assert(not bool(schedule.amount_due(MoneyScript.invalid())["ok"]))
	assert(not bool(schedule.amount_due(null)["ok"]))


# --- milestones --------------------------------------------------------------------------------


func test_a_milestone_schedule_bills_the_next_step_and_only_that_one() -> void:
	var schedule := _schedule(JobScript.MILESTONE)
	_three_steps(schedule)
	var first: Dictionary = schedule.amount_due(_contract())
	assert(String(first["milestone"]) == "Deposit")
	assert((first["amount"] as MoneyScript).cents == 300000)
	assert(bool(schedule.record_billed(_contract(), first["amount"], "2026-06-01", "INV-2026-0001", "Deposit")["ok"]))
	var second: Dictionary = schedule.amount_due(_contract())
	assert(String(second["milestone"]) == "Rough grade")
	assert((second["amount"] as MoneyScript).cents == 300000)


func test_a_step_can_be_billed_by_name_and_one_already_billed_is_refused() -> void:
	var schedule := _schedule(JobScript.MILESTONE)
	_three_steps(schedule)
	assert(bool(schedule.record_billed(_contract(), MoneyScript.of(300000), "2026-06-01", "INV-2026-0001", "Deposit")["ok"]))
	var again: Dictionary = schedule.amount_due(_contract(), null, null, "Deposit")
	assert(not bool(again["ok"]))
	assert(String(again["reason"]).contains("was billed on INV-2026-0001"), String(again["reason"]))


func test_a_step_the_schedule_does_not_have_is_refused_by_name() -> void:
	var schedule := _schedule(JobScript.MILESTONE)
	_three_steps(schedule)
	var refused: Dictionary = schedule.amount_due(_contract(), null, null, "Retention")
	assert(not bool(refused["ok"]))
	assert(String(refused["reason"]).contains("no step called 'Retention'"), String(refused["reason"]))


func test_a_step_cannot_be_billed_twice_through_the_records_either() -> void:
	var schedule := _schedule(JobScript.MILESTONE)
	_three_steps(schedule)
	assert(bool(schedule.record_billed(_contract(), MoneyScript.of(300000), "2026-06-01", "INV-2026-0001", "Deposit")["ok"]))
	var second: Dictionary = schedule.record_billed(_contract(), MoneyScript.of(300000), "2026-06-02", "INV-2026-0002", "Deposit")
	assert(not bool(second["ok"]))
	assert(schedule.billed_to_date.cents == 300000)


func test_the_part_of_the_contract_no_step_claims_is_named_rather_than_hidden() -> void:
	var schedule := _schedule(JobScript.MILESTONE)
	assert(schedule.add_milestone(_step("Deposit", 300000)))
	assert(schedule.add_milestone(_step("Final", 600000)))
	assert(schedule.claimed_ppm() == 900000)
	assert(schedule.unbilled_ppm() == 100000)
	assert(not schedule.is_sound())
	assert(schedule.problems().has("10% of the contract is claimed by no step"), str(schedule.problems()))


func test_more_than_the_whole_contract_in_steps_is_a_problem() -> void:
	var schedule := _schedule(JobScript.MILESTONE)
	assert(schedule.add_milestone(_step("Deposit", 600000)))
	assert(schedule.add_milestone(_step("Final", 600000)))
	assert(schedule.problems().has("the steps claim 120% of the contract"), str(schedule.problems()))


func test_a_schedule_in_fixed_amounts_cannot_be_summed_as_a_share_and_says_so() -> void:
	var schedule := _schedule(JobScript.MILESTONE)
	var step: MilestoneScript = MilestoneScript.new("Permit fee")
	assert(step.set_fixed_amount(MoneyScript.of(45000)))
	assert(schedule.add_milestone(step))
	assert(schedule.claimed_ppm() == RateScript.INVALID)
	assert(schedule.unbilled_ppm() == RateScript.INVALID)
	assert(schedule.is_sound(), str(schedule.problems()))
	assert(schedule.describe().contains("in fixed amounts"), schedule.describe())


func test_a_job_billed_by_milestones_with_no_milestones_says_so() -> void:
	var schedule := _schedule(JobScript.MILESTONE)
	assert(not schedule.is_sound())
	assert(schedule.problems().has("a job billed by milestones with no milestones"), str(schedule.problems()))


func test_two_steps_with_one_name_is_two_answers_to_one_question() -> void:
	var schedule := _schedule(JobScript.MILESTONE)
	assert(schedule.add_milestone(_step("Deposit", 300000)))
	assert(not schedule.add_milestone(_step("Deposit", 200000)))
	assert(schedule.step_count() == 1)
	assert(not schedule.add_milestone(null))
	var unpriced: MilestoneScript = MilestoneScript.new("Whatever")
	assert(not schedule.add_milestone(unpriced))


func test_a_schedule_with_every_step_billed_has_nothing_left_to_bill() -> void:
	var schedule := _schedule(JobScript.MILESTONE)
	assert(schedule.add_milestone(_step("Deposit", 1000000)))
	assert(bool(schedule.record_billed(_contract(), MoneyScript.of(1000000), "2026-06-01", "INV-2026-0001", "Deposit")["ok"]))
	var done: Dictionary = schedule.amount_due(_contract())
	assert(bool(done["ok"]))
	assert((done["amount"] as MoneyScript).is_zero())
	assert(String(done["reason"]).contains("every step"), String(done["reason"]))


# --- retainage --------------------------------------------------------------------------------


func test_a_steps_retainage_is_withheld_when_it_is_billed_and_accumulates() -> void:
	var schedule := _schedule(JobScript.MILESTONE)
	var step: MilestoneScript = MilestoneScript.new("Deposit")
	assert(step.set_percent(250000))
	step.retainage_ppm = 100000
	assert(schedule.add_milestone(step))
	assert(bool(schedule.record_billed(_contract(), MoneyScript.of(225000), "2026-06-01", "INV-2026-0001", "Deposit")["ok"]))
	assert(schedule.billed_to_date.cents == 225000)
	assert(schedule.retainage_held.cents == 25000)


func test_retainage_is_released_only_by_an_explicit_act_at_closeout() -> void:
	var schedule := _schedule(JobScript.MILESTONE)
	var step: MilestoneScript = MilestoneScript.new("Deposit")
	assert(step.set_percent(250000))
	step.retainage_ppm = 100000
	assert(schedule.add_milestone(step))
	assert(bool(schedule.record_billed(_contract(), MoneyScript.of(225000), "2026-06-01", "INV-2026-0001", "Deposit")["ok"]))
	assert(schedule.retainage_held.cents == 25000)
	assert(not schedule.release_retainage("").is_valid())
	assert(schedule.release_retainage("2026-09-01").cents == 25000)
	assert(schedule.retainage_held.is_zero())
	assert(schedule.retainage_released_at == "2026-09-01")
	assert(schedule.release_retainage("2026-09-02").is_zero())
	assert(schedule.retainage_released_at == "2026-09-01", "a release of nothing does not restamp the date")
	assert(schedule.describe().contains("retainage released 2026-09-01"), schedule.describe())


func test_a_schedule_that_has_no_steps_withholds_its_own_rate() -> void:
	var schedule := _schedule()
	schedule.retainage_ppm = 100000
	assert(schedule.retainage_due(_contract(), MoneyScript.of(300000)).cents == 30000)
	assert(schedule.retainage_due(_contract(), MoneyScript.invalid()).is_valid() == false)


# --- the two methods with no schedule ---------------------------------------------------------


func test_time_and_materials_bills_labour_and_materials_at_their_markup() -> void:
	var schedule := _schedule(JobScript.TIME_AND_MATERIALS)
	schedule.markup_ppm = 200000
	var due: Dictionary = schedule.amount_due(_contract(), MoneyScript.of(100000), MoneyScript.of(50000))
	assert(bool(due["ok"]))
	assert((due["amount"] as MoneyScript).cents == 160000, str((due["amount"] as MoneyScript).cents))
	assert(String(due["reason"]).contains("20%"), String(due["reason"]))


func test_cost_plus_is_the_cost_incurred_plus_the_fee() -> void:
	var schedule := _schedule(JobScript.COST_PLUS)
	schedule.fee_ppm = 150000
	var due: Dictionary = schedule.amount_due(_contract(), MoneyScript.of(200000))
	assert(bool(due["ok"]))
	assert((due["amount"] as MoneyScript).cents == 230000)
	assert(BillingScript.cost_plus_amount(MoneyScript.of(200000), 150000).cents == 230000)


func test_the_period_is_required_for_the_methods_that_have_no_schedule() -> void:
	var schedule := _schedule(JobScript.TIME_AND_MATERIALS)
	var refused: Dictionary = schedule.amount_due(_contract())
	assert(not bool(refused["ok"]))
	assert(String(refused["reason"]).contains("not readable"), String(refused["reason"]))


func test_an_unreadable_period_is_refused_rather_than_billed_as_nothing() -> void:
	var schedule := _schedule(JobScript.COST_PLUS)
	assert(not bool(schedule.amount_due(_contract(), MoneyScript.invalid())["ok"]))
	assert(BillingScript.time_and_materials_amount(null, null, 0).is_valid() == false)


# --- the record ---------------------------------------------------------------------------------


func test_the_schedule_survives_the_file_with_its_steps_and_its_money() -> void:
	var schedule := _schedule(JobScript.MILESTONE)
	_three_steps(schedule)
	assert(bool(schedule.record_billed(_contract(), MoneyScript.of(300000), "2026-06-01", "INV-2026-0001", "Deposit")["ok"]))
	schedule.markup_ppm = 200000
	schedule.fee_ppm = 150000
	schedule.retainage_ppm = 50000
	var back: BillingScript = BillingScript.from_dict(schedule.to_dict())
	assert(back.job == "J1")
	assert(back.method == JobScript.MILESTONE)
	assert(back.step_count() == 3)
	assert(back.milestone("Deposit").is_billed())
	assert(back.milestone("Deposit").invoice_number == "INV-2026-0001")
	assert(back.billed_to_date.cents == 300000)
	assert(back.retainage_ppm == 50000)
	assert(back.markup_ppm == 200000)
	assert(back.fee_ppm == 150000)
	assert(back.is_sound())


func test_a_damaged_step_is_kept_and_named_rather_than_dropped() -> void:
	var schedule: BillingScript = BillingScript.from_dict({
		"job": "J1",
		"method": "MILESTONE",
		"milestones": [{"name": "Deposit", "percent_ppm": 1200000}],
	})
	assert(schedule.step_count() == 1)
	assert(not schedule.is_sound())
	assert(schedule.problems().has("'Deposit' claims 120% of the contract"), str(schedule.problems()))


func test_a_record_that_is_not_a_step_is_dropped_and_the_rest_reads() -> void:
	var schedule: BillingScript = BillingScript.from_dict({
		"job": "J1",
		"method": "MILESTONE",
		"milestones": ["Deposit", {"name": "Final", "percent_ppm": 1000000}],
	})
	assert(schedule.step_count() == 1)
	var names: Array[String] = schedule.milestone_names()
	var expected: Array[String] = ["Final"]
	assert(names == expected)


func test_what_has_been_billed_moves_in_exactly_one_place() -> void:
	var schedule := _schedule(JobScript.PERCENTAGE_COMPLETE)
	assert(schedule.billed_to_date.is_zero())
	assert(not bool(schedule.record_billed(_contract(), MoneyScript.invalid(), "2026-06-01", "INV-2026-0001")["ok"]))
	assert(schedule.billed_to_date.is_zero())
	assert(not bool(schedule.record_billed(_contract(), MoneyScript.of(100), "2026-06-01", "INV-2026-0001", "Nope")["ok"]))
	assert(schedule.billed_to_date.is_zero())