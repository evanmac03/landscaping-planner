extends Node
## The job: phases taken from the estimate, the basis stated, and the billing method of the contract
## (spec §4.10, §9.1).

const JobScript := preload("res://scripts/biz/job.gd")
const EstimateScript := preload("res://scripts/biz/estimate.gd")
const LineScript := preload("res://scripts/biz/estimate_line.gd")
const ItemScript := preload("res://scripts/biz/cost_item.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")


func _line(code: StringName, units_milli: int, cost_cents: int, price_cents: int) -> LineScript:
	var line: LineScript = LineScript.new()
	line.cost_code = code
	line.kind = ItemScript.MATERIAL
	line.quantity_milli = units_milli
	line.unit = &"EACH"
	line.unit_cost = MoneyScript.of(cost_cents)
	line.unit_price = MoneyScript.of(price_cents)
	return line


## An estimate over two phases, price 150.00 + 400.00 + 75.00 = 625.00 and cost 100.00 + 240.00 +
## 50.00 = 390.00.
func _estimate() -> EstimateScript:
	var estimate: EstimateScript = EstimateScript.new("E1")
	estimate.lines.append(_line(&"PLANTING", 10000, 1000, 1500))     # 10 x 15.00
	estimate.lines.append(_line(&"HARDSCAPE", 20000, 1200, 2000))    # 20 x 20.00
	estimate.lines.append(_line(&"PLANTING", 5000, 1000, 1500))      # 5 x 15.00
	return estimate


func test_phases_group_the_estimate_by_cost_code_in_code_order() -> void:
	var job: JobScript = JobScript.from_estimate(_estimate())
	assert(job.phase_codes() == ["HARDSCAPE", "PLANTING"], str(job.phase_codes()))
	assert(job.phase("PLANTING")["budget"].format() == "225.00", "15.00 of two lines added")
	assert(job.phase("HARDSCAPE")["budget"].format() == "400.00")


func test_the_basis_is_stated_and_cost_is_a_different_budget() -> void:
	var job: JobScript = JobScript.from_estimate(_estimate(), JobScript.COST)
	assert(int(job.phase("PLANTING")["basis"]) == JobScript.COST)
	assert(job.phase("PLANTING")["budget"].format() == "150.00", "10.00 an hour of cost, not price")
	assert(job.phase("HARDSCAPE")["budget"].format() == "240.00")
	assert(job.basis_name(JobScript.COST) == "cost")


func test_a_line_with_no_cost_code_is_unassigned_rather_than_dropped() -> void:
	var estimate := _estimate()
	estimate.lines.append(_line(&"", 1000, 1000, 1500))  # 1 x 15.00, nobody's code
	var job: JobScript = JobScript.from_estimate(estimate)
	assert(job.phase_codes().has("UNASSIGNED"), "a line nobody is paid for is still counted")
	assert(job.phase("UNASSIGNED")["budget"].format() == "15.00")


func test_the_contract_sum_is_the_price_before_tax_and_the_revision_travels() -> void:
	var estimate := _estimate()
	estimate.revision = 3
	var job: JobScript = JobScript.from_estimate(estimate)
	assert(job.contract_sum.format() == "625.00", job.contract_sum.format())
	assert(job.estimate_revision == 3)
	assert(job.id == "E1", "the job is built from the estimate it came from")


func test_the_budget_total_is_every_phase() -> void:
	var job: JobScript = JobScript.from_estimate(_estimate())
	assert(job.budget_total().format() == "625.00", job.budget_total().format())


func test_billing_methods_are_names_the_contract_agreed_to() -> void:
	assert(JobScript.billing_name(JobScript.FIXED) == "fixed price")
	assert(JobScript.billing_name(JobScript.PERCENTAGE_COMPLETE) == "percentage complete")
	assert(JobScript.billing_name(JobScript.TIME_AND_MATERIALS) == "time and materials")
	assert(JobScript.billing_name(JobScript.COST_PLUS) == "cost plus")
	var job: JobScript = JobScript.new("J1")
	assert(job.set_billing_method(JobScript.MILESTONE))
	assert(job.billing_method == JobScript.MILESTONE)
	assert(not job.set_billing_method(99), "a method nobody has cannot be billed")


func test_a_job_round_trips_through_the_file() -> void:
	var job: JobScript = JobScript.from_estimate(_estimate())
	job.number = "JOB-2026-0007"
	job.name = "Smith backyard"
	job.set_billing_method(JobScript.MILESTONE)
	job.assign_crew(&"C1")
	job.documents.append("proposal.pdf")
	job.schedule.append({"date": "2026-06-01", "start_minute": 480, "end_minute": 600})
	var restored: JobScript = JobScript.from_dict(job.to_dict())
	assert(restored.id == "E1" and restored.number == "JOB-2026-0007")
	assert(restored.billing_method == JobScript.MILESTONE)
	assert(restored.contract_sum.format() == "625.00")
	assert(restored.phase_codes() == ["HARDSCAPE", "PLANTING"])
	assert(restored.phase("PLANTING")["budget"].format() == "225.00")
	assert(restored.crew.size() == 1 and String(restored.crew[0]) == "C1")
	assert(restored.documents.size() == 1 and restored.documents[0] == "proposal.pdf")
	assert(restored.schedule.size() == 1)


func test_a_billing_method_nobody_has_becomes_the_common_one_through_a_file() -> void:
	var made: JobScript = JobScript.from_dict({"id": "J1", "billing_method": "MAGIC"})
	assert(made.billing_method == JobScript.FIXED)


func test_a_record_with_no_id_is_dropped() -> void:
	assert(JobScript.from_dict({"name": "nobody"}) == null)


func test_a_crew_member_is_assigned_once() -> void:
	var job: JobScript = JobScript.new("J1")
	assert(job.assign_crew(&"C1"))
	assert(not job.assign_crew(&"C1"), "the same person twice is one crew")
	assert(not job.assign_crew(&""), "and nobody is not a crew member")
	assert(job.crew.size() == 1)