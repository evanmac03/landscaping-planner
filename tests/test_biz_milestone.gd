extends Node
## A milestone: one step of a billing schedule (spec §9.2).
##
## Two properties are under test. The first is that a step is priced **one of two ways and never
## both**, because a step that is a percent and a flat amount at once cannot be read - which of the
## two does it come to? The second is that **whether it has been billed is a record, not a state
## field**, so the schedule and the invoices cannot disagree about what has gone out.

const MilestoneScript := preload("res://scripts/biz/milestone.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")
const RateScript := preload("res://scripts/biz/rate.gd")

const CONTRACT_CENTS := 1000000


func _contract() -> MoneyScript:
	return MoneyScript.of(CONTRACT_CENTS)


func _step(step_name: String = "Deposit") -> MilestoneScript:
	return MilestoneScript.new(step_name)


func test_pricing_is_one_of_two_ways_and_the_second_replaces_the_first() -> void:
	var step := _step()
	assert(not step.is_priced())
	assert(step.set_percent(250000))
	assert(step.is_percentage())
	assert(not step.is_fixed())
	assert(step.set_fixed_amount(MoneyScript.of(50000)))
	assert(step.is_fixed())
	assert(not step.is_percentage())
	assert(step.percent_ppm == RateScript.INVALID)


func test_a_share_of_nothing_or_of_more_than_the_whole_is_not_a_step() -> void:
	var step := _step()
	assert(not step.set_percent(0))
	assert(not step.set_percent(-1000))
	assert(not step.set_percent(RateScript.WHOLE + 1))
	assert(step.set_percent(RateScript.WHOLE))
	assert(step.is_percentage())


func test_a_fixed_amount_of_nothing_is_not_a_price() -> void:
	var step := _step()
	assert(not step.set_fixed_amount(MoneyScript.zero()))
	assert(not step.set_fixed_amount(MoneyScript.of(-1)))
	assert(not step.set_fixed_amount(MoneyScript.invalid()))
	assert(not step.set_fixed_amount(null))
	assert(not step.is_priced())


func test_a_share_of_the_contract_is_scaled_by_it() -> void:
	var step := _step()
	assert(step.set_percent(250000))
	assert(step.amount_for(_contract()).cents == 250000)
	assert(step.amount_for(MoneyScript.of(200000)).cents == 50000)


func test_a_flat_step_ignores_the_contract() -> void:
	var step := _step()
	assert(step.set_fixed_amount(MoneyScript.of(45000)))
	assert(step.amount_for(_contract()).cents == 45000)
	assert(step.amount_for(MoneyScript.of(200000)).cents == 45000)


func test_an_unpriced_step_answers_with_the_invalid_amount_rather_than_nothing() -> void:
	var step := _step()
	assert(not step.amount_for(_contract()).is_valid())


func test_retainage_is_a_share_of_the_step_and_not_of_the_contract() -> void:
	var step := _step()
	assert(step.set_percent(250000))
	step.retainage_ppm = 100000
	assert(step.amount_for(_contract()).cents == 250000)
	assert(step.retainage_for(_contract()).cents == 25000)
	var clean := _step("Final")
	assert(clean.set_percent(500000))
	assert(clean.retainage_for(_contract()).is_zero())


func test_retainage_can_withhold_the_whole_step_and_then_nothing_is_paid_on_it() -> void:
	var step := _step()
	assert(step.set_percent(250000))
	step.retainage_ppm = RateScript.WHOLE
	assert(step.retainage_for(_contract()).cents == 250000)


func test_a_step_is_billed_once_and_the_moment_and_the_invoice_are_both_required() -> void:
	var step := _step()
	assert(step.set_percent(250000))
	assert(not step.is_billed())
	assert(step.state_name() == "pending")
	assert(not step.mark_billed("", "INV-2026-0001"))
	assert(not step.mark_billed("2026-06-01", ""))
	assert(step.mark_billed("2026-06-01", "INV-2026-0001"))
	assert(step.is_billed())
	assert(step.state_name() == "billed")
	assert(not step.mark_billed("2026-06-02", "INV-2026-0002"))
	assert(step.billed_at == "2026-06-01")


func test_a_record_can_be_wrong_in_ways_the_setters_refuse() -> void:
	var step: MilestoneScript = MilestoneScript.from_dict({"name": "Deposit", "percent_ppm": 1200000})
	assert(not step.is_sound())
	assert(step.problem() == "'Deposit' claims 120% of the contract", step.problem())


func test_the_things_a_step_can_be_wrong_about_are_named() -> void:
	var nameless := _step("")
	assert(nameless.problem() == "a step with no name", nameless.problem())
	var unpriced := _step("Deposit")
	assert(unpriced.problem() == "'Deposit' is priced as neither a share of the contract nor a fixed amount",
		unpriced.problem())
	var undated := _step("Deposit")
	undated.set_percent(250000)
	undated.due_date = "June"
	assert(undated.problem() == "'Deposit' is due on a date that is not a date: 'June'", undated.problem())
	var both: MilestoneScript = MilestoneScript.from_dict({
		"name": "Deposit",
		"percent_ppm": 250000,
		"fixed_amount": {"cents": 50000, "currency": "CAD"},
	})
	assert(both.problem() == "'Deposit' is priced as a share of the contract and as a fixed amount",
		both.problem())
	var triggerless := _step("Deposit")
	triggerless.set_percent(250000)
	triggerless.trigger = 9
	assert(triggerless.problem() == "'Deposit' fires on a trigger nobody has", triggerless.problem())


func test_a_step_that_says_it_was_billed_must_say_on_what() -> void:
	var step: MilestoneScript = MilestoneScript.from_dict({
		"name": "Deposit",
		"percent_ppm": 250000,
		"billed_at": "2026-06-01",
		"invoice_number": "",
	})
	assert(step.problem() == "'Deposit' says it was billed and cannot say on which invoice", step.problem())


func test_the_triggers_are_three_and_they_are_named() -> void:
	assert(MilestoneScript.is_trigger(MilestoneScript.DATE))
	assert(MilestoneScript.is_trigger(MilestoneScript.PHASE_COMPLETE))
	assert(MilestoneScript.is_trigger(MilestoneScript.APPROVED))
	assert(not MilestoneScript.is_trigger(7))
	assert(MilestoneScript.trigger_name(MilestoneScript.PHASE_COMPLETE) == "when a phase is complete")
	assert(MilestoneScript.trigger_name(7) == "on a date")


func test_a_step_survives_the_file_with_its_price_and_its_trigger() -> void:
	var step := _step("Rough grade")
	assert(step.set_percent(300000))
	step.trigger = MilestoneScript.PHASE_COMPLETE
	step.due_date = "2026-07-01"
	step.retainage_ppm = 50000
	step.note = "after the sub is off site"
	assert(step.mark_billed("2026-07-02", "INV-2026-0011"))
	var back: MilestoneScript = MilestoneScript.from_dict(step.to_dict())
	assert(back.name == "Rough grade")
	assert(back.percent_ppm == 300000)
	assert(back.trigger == MilestoneScript.PHASE_COMPLETE)
	assert(back.due_date == "2026-07-01")
	assert(back.retainage_ppm == 50000)
	assert(back.billed_at == "2026-07-02")
	assert(back.invoice_number == "INV-2026-0011")
	assert(back.is_sound())
	assert(back.note == "after the sub is off site")


func test_a_step_reads_as_the_row_a_schedule_shows() -> void:
	var step := _step("Deposit")
	assert(step.set_percent(250000))
	step.retainage_ppm = 100000
	assert(step.describe(_contract()) == "Deposit (25% of the contract, $2,500.00, on a date, 10% withheld, pending)",
		step.describe(_contract()))