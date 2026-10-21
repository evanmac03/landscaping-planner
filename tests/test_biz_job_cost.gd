extends Node
## The job cost report: budget, committed and actual per cost code, and what they come to (spec §8.4).
##
## What is under test is REQ-B17 - the three numbers shown **separately**, with committed derived from
## issued-not-received purchase orders - and REQ-B18 - a change order is revenue and only an approved
## one joins the contract sum. The subtle claim the whole report rests on is that it is a function of
## the records: change a receipt and the report changes, with nothing else to keep in step.

const JobCostScript := preload("res://scripts/biz/job_cost.gd")
const JobScript := preload("res://scripts/biz/job.gd")
const EstimateScript := preload("res://scripts/biz/estimate.gd")
const LineScript := preload("res://scripts/biz/estimate_line.gd")
const ItemScript := preload("res://scripts/biz/cost_item.gd")
const OrderScript := preload("res://scripts/biz/purchase_order.gd")
const ChangeScript := preload("res://scripts/biz/change_order.gd")
const EntryScript := preload("res://scripts/biz/time_entry.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")


func _line(code: StringName, units_milli: int, cost_cents: int, price_cents: int) -> LineScript:
	var line: LineScript = LineScript.new()
	line.description = "something"
	line.cost_code = code
	line.kind = ItemScript.MATERIAL
	line.quantity_milli = units_milli
	line.unit = &"EACH"
	line.unit_cost = MoneyScript.of(cost_cents)
	line.unit_price = MoneyScript.of(price_cents)
	return line


## PLANTING 10 x 15.00 = 150.00 price, 100.00 cost; HARDSCAPE 20 x 20.00 = 400.00 price, 240.00 cost.
## So the contract sum is 550.00 and the cost budget is 340.00.
func _estimate() -> EstimateScript:
	var estimate: EstimateScript = EstimateScript.new("E1")
	estimate.lines.append(_line(&"PLANTING", 10000, 1000, 1500))
	estimate.lines.append(_line(&"HARDSCAPE", 20000, 1200, 2000))
	return estimate


func _job(basis: int = JobScript.PRICE) -> JobScript:
	return JobScript.from_estimate(_estimate(), basis)


## A purchase order for PLANTING: 10 units at 10.00, of which 6 have arrived. So 40.00 is committed
## and 60.00 has been incurred.
func _po_planting(order_id: String = "PO1", ordered_milli: int = 10000, receipt: int = 6000) -> OrderScript:
	var order: OrderScript = OrderScript.new(order_id)
	order.number = "PO-2026-001"
	order.job = "E1"
	order.cost_code = &"PLANTING"
	order.supplier = "Greenline Nursery"
	order.add_line("Buxus, 2 gal", &"EACH", ordered_milli, MoneyScript.of(1000))
	order.issue("2026-06-01")
	if receipt > 0:
		order.receive("2026-06-05", 0, receipt)
	return order


## An hour of PLANTING labour at 30.00 an hour: 30.00.
func _entry(code: StringName = &"PLANTING", minutes: int = 60, rate_cents: int = 3000,
		approved: bool = true) -> EntryScript:
	var entry: EntryScript = EntryScript.new("T1")
	entry.job = "E1"
	entry.cost_code = code
	entry.crew_member = &"D1"
	var start := Time.get_unix_time_from_datetime_string("2026-06-08T12:00:00")
	entry.started_at = "2026-06-08T12:00:00"
	entry.ended_at = Time.get_datetime_string_from_unix_time(start + minutes * 60)
	entry.loaded_rate = MoneyScript.of(rate_cents)
	if approved:
		assert(entry.approve("Dana"), "the entry reads and somebody signed it")
	return entry


## An approved change order for HARDSCAPE worth 500.00: 25 units at 20.00.
func _approved_change(order_id: String = "CO1") -> ChangeScript:
	var change: ChangeScript = ChangeScript.new(order_id)
	change.job = "E1"
	change.reason = &"SITE_CONDITION"
	change.estimate.add_line(_line(&"HARDSCAPE", 25000, 1200, 2000))
	change.propose("2026-06-20")
	change.send("2026-06-21")
	change.approve("Dana", "2026-07-01", "in-app")
	return change


func _pending_change(order_id: String = "CO2") -> ChangeScript:
	var change: ChangeScript = ChangeScript.new(order_id)
	change.job = "E1"
	change.reason = &"CUSTOMER_REQUEST"
	change.estimate.add_line(_line(&"HARDSCAPE", 5000, 1200, 2000))  # 100.00
	change.propose("2026-07-01")
	return change


func _with_costs(basis: int = JobScript.PRICE) -> JobCostScript:
	return JobCostScript.of(_job(basis), [_po_planting()], [], [_entry()])


# --- the rows -----------------------------------------------------------------------------------


func test_a_job_with_nothing_against_it_has_one_row_per_phase_and_nothing_in_them() -> void:
	var report := JobCostScript.of(_job(), [], [], [])
	assert(report.codes() == ["HARDSCAPE", "PLANTING"], str(report.codes()))
	var row: Dictionary = report.row_for("PLANTING")
	assert((row["budget"] as MoneyScript).format() == "150.00", (row["budget"] as MoneyScript).format())
	assert((row["committed"] as MoneyScript).format() == "0.00")
	assert((row["actual"] as MoneyScript).format() == "0.00")
	assert(int(row["percent_ppm"]) == 0)
	assert(not bool(row["over_committed"]))
	assert(report.problems().is_empty(), str(report.problems()))


func test_the_three_numbers_are_shown_separately() -> void:
	# REQ-B17. A job with 40.00 committed, 60.00 of material arrived and an hour of labour approved.
	var report := _with_costs()
	var row: Dictionary = report.row_for("PLANTING")
	assert((row["budget"] as MoneyScript).format() == "150.00")
	assert((row["committed"] as MoneyScript).format() == "40.00", "ordered and not arrived")
	assert((row["actual"] as MoneyScript).format() == "90.00", "60.00 arrived plus 30.00 of labour")
	var figures: Dictionary = report.totals()
	assert((figures["budget"] as MoneyScript).format() == "550.00")
	assert((figures["committed"] as MoneyScript).format() == "40.00")
	assert((figures["actual"] as MoneyScript).format() == "90.00")
	assert((figures["cost"] as MoneyScript).format() == "90.00", "cost incurred is the actual")


func test_committed_comes_from_the_orders_and_a_closed_one_drops_out_of_it() -> void:
	var order := _po_planting()
	var report := JobCostScript.of(_job(), [order], [], [])
	assert((report.row_for("PLANTING")["committed"] as MoneyScript).format() == "40.00")
	order.receive("2026-06-09", 0, 4000)
	var arrived := JobCostScript.of(_job(), [order], [], [])
	assert((arrived.row_for("PLANTING")["committed"] as MoneyScript).format() == "0.00")
	assert((arrived.row_for("PLANTING")["actual"] as MoneyScript).format() == "100.00")
	assert(order.mark_closed("2026-07-01", "invoiced"), "the whole order arrived")
	var closed := JobCostScript.of(_job(), [order], [], [])
	assert((closed.row_for("PLANTING")["committed"] as MoneyScript).format() == "0.00")
	assert((closed.row_for("PLANTING")["actual"] as MoneyScript).format() == "100.00",
		"closing an order does not un-spend the money")


func test_a_pending_time_entry_is_not_cost() -> void:
	var waiting := _entry(&"PLANTING", 480, 3000, false)
	var report := JobCostScript.of(_job(), [], [], [waiting])
	assert((report.row_for("PLANTING")["actual"] as MoneyScript).format() == "0.00",
		"hour nobody has approved")
	assert(not waiting.is_approved())


func test_a_code_nobody_budgeted_but_somebody_worked_on_gets_an_honest_row() -> void:
	var report := JobCostScript.of(_job(), [], [], [_entry(&"EXTRAS")])
	assert(report.codes() == ["EXTRAS", "HARDSCAPE", "PLANTING"], str(report.codes()))
	var row: Dictionary = report.row_for("EXTRAS")
	assert(not bool(row["has_budget"]), "there is no budget for it")
	assert((row["budget"] as MoneyScript).format() == "0.00")
	assert((row["actual"] as MoneyScript).format() == "30.00")
	assert(not bool(row["percent_known"]), "an unbudgeted code is unmeasured, not complete")
	assert(report.problems().has("EXTRAS has cost $30.00 and has no budget at all"), str(report.problems()))


func test_the_variance_and_the_projection_are_what_is_left() -> void:
	var row: Dictionary = _with_costs().row_for("PLANTING")
	assert((row["variance"] as MoneyScript).format() == "60.00", "150.00 less 90.00 of cost")
	assert((row["projection"] as MoneyScript).format() == "20.00",
		"150.00 less 90.00 of cost less 40.00 committed")


func test_percent_complete_is_by_cost_incurred_and_the_report_says_so() -> void:
	var report := _with_costs()
	assert(report.percent_basis == JobCostScript.BY_COST_INCURRED)
	assert(report.percent_basis == "by cost incurred")
	var row: Dictionary = report.row_for("PLANTING")
	assert(int(row["percent_ppm"]) == 600000, "90.00 of 150.00 is 60%%")
	assert(bool(row["percent_known"]))
	assert((report.totals()["percent_basis"] as String) == "by cost incurred")


func test_a_code_with_no_budget_is_unmeasured_and_not_called_complete() -> void:
	var report := JobCostScript.of(_job(), [], [], [])
	var bare: Dictionary = JobCostScript.of(null, [], [], []).totals()
	assert(not bool(bare["percent_known"]))
	assert(int(bare["percent_ppm"]) == 0)
	assert(report.row_for("NOTHING").is_empty(), "and a code nobody mentions is not a row")


# --- the flag that matters before the money is spent ------------------------------------------


func test_more_committed_than_budgeted_is_a_problem_at_the_moment_it_happens() -> void:
	var order := _po_planting("PO1", 20000, 0)  # 20 x 10.00 = 200.00 against a budget of 150.00
	var report := JobCostScript.of(_job(), [order], [], [])
	assert(bool(report.row_for("PLANTING")["over_committed"]))
	assert(report.over_committed_codes() == ["PLANTING"], str(report.over_committed_codes()))
	assert(report.problems().has("PLANTING is committed $200.00 against a budget of $150.00"),
		str(report.problems()))


func test_over_commitment_asked_before_the_order_goes_out() -> void:
	var order := _po_planting("PO1", 10000, 0)  # 100.00 committed of a 150.00 budget
	var fits: Dictionary = JobCostScript.over_commitment(
		_job(), [order], &"PLANTING", MoneyScript.of(4000))
	assert(not bool(fits["over"]), "40.00 more fits in the 50.00 that is left")
	assert((fits["remaining"] as MoneyScript).format() == "50.00")
	assert(String(fits["reason"]).is_empty())
	var too_much: Dictionary = JobCostScript.over_commitment(
		_job(), [order], &"PLANTING", MoneyScript.of(6000))
	assert(bool(too_much["over"]), "60.00 more does not")
	assert(String(too_much["reason"]).contains("committed $160.00 against a budget of $150.00"),
		String(too_much["reason"]))
	# And a budget nobody has touched has all of itself left.
	var fresh: Dictionary = JobCostScript.over_commitment(
		_job(), [], &"HARDSCAPE", MoneyScript.of(40000))
	assert(not bool(fresh["over"]))
	assert((fresh["remaining"] as MoneyScript).format() == "400.00")


# --- REQ-B18: change orders --------------------------------------------------------------------


func test_an_approved_change_order_raises_the_contract_sum_and_a_pending_one_is_shown_separately() -> void:
	var report := JobCostScript.of(_job(), [], [_approved_change(), _pending_change()], [])
	var figures: Dictionary = report.totals()
	assert((figures["contract_sum"] as MoneyScript).format() == "550.00")
	assert((figures["changes_approved"] as MoneyScript).format() == "500.00")
	assert((figures["agreed_sum"] as MoneyScript).format() == "1,050.00")
	assert((figures["changes_pending"] as MoneyScript).format() == "100.00")
	assert(int(figures["pending_count"]) == 1)
	assert(report.problems().has("1 change order pending, $100.00 not yet agreed"),
		str(report.problems()))
	var row: Dictionary = report.row_for("HARDSCAPE")
	assert((row["changes_approved"] as MoneyScript).format() == "500.00")
	assert((row["revised_budget"] as MoneyScript).format() == "900.00", "400.00 of budget plus 500.00")


func test_a_declined_or_void_change_order_is_neither_agreed_nor_pending() -> void:
	var declined := _pending_change("CO2")
	declined.decline("Dana", "2026-07-02", "too expensive")
	var voided := _pending_change("CO3")
	voided.mark_void("2026-07-02", "the customer withdrew it")
	var report := JobCostScript.of(_job(), [], [declined, voided], [])
	var figures: Dictionary = report.totals()
	assert((figures["changes_approved"] as MoneyScript).format() == "0.00")
	assert((figures["changes_pending"] as MoneyScript).format() == "0.00")
	assert(int(figures["pending_count"]) == 0)
	assert((figures["agreed_sum"] as MoneyScript).format() == "550.00")
	assert(report.problems().is_empty(), str(report.problems()))


func test_an_approved_change_order_only_joins_the_sum_when_it_says_it_does() -> void:
	var change := _approved_change()
	change.affects_contract_sum = false
	var figures: Dictionary = JobCostScript.of(_job(), [], [change], []).totals()
	assert((figures["changes_approved"] as MoneyScript).format() == "0.00")
	assert((figures["agreed_sum"] as MoneyScript).format() == "550.00")


func test_a_change_order_is_revenue_and_its_cost_is_wherever_it_was_spent() -> void:
	# The change raises what the code was sold for and nothing else: its material arrives through a
	# purchase order like any other material, which is why the report needs no rule about changes.
	var report := JobCostScript.of(_job(), [], [_approved_change()], [])
	var row: Dictionary = report.row_for("HARDSCAPE")
	assert((row["changes_approved"] as MoneyScript).format() == "500.00")
	assert((row["actual"] as MoneyScript).format() == "0.00", "and nothing has been spent yet")
	assert((row["variance"] as MoneyScript).format() == "400.00", "against the original budget")
	assert((row["variance_after_changes"] as MoneyScript).format() == "900.00",
		"and against what the code is now sold for")


# --- billed, and the margin ---------------------------------------------------------------------


func test_what_has_been_billed_is_not_known_rather_than_nothing() -> void:
	var report := _with_costs()
	var figures: Dictionary = report.totals()
	assert(not bool(figures["billed_known"]))
	assert(not (figures["billed"] as MoneyScript).is_valid(), "not known is not zero")
	assert(not bool(figures["uncollected_known"]))
	assert(report.notes.has("nothing has been invoiced, so what has been billed and what is "
		+ "uncollected are not known rather than nothing"), str(report.notes))
	assert(report.totals_text().contains("not known: nothing has been invoiced"),
		report.totals_text())


func test_what_has_been_billed_when_somebody_says() -> void:
	var report := JobCostScript.of(_job(), [], [], [], MoneyScript.of(40000), MoneyScript.of(15000))
	var figures: Dictionary = report.totals()
	assert(bool(figures["billed_known"]))
	assert((figures["billed"] as MoneyScript).format() == "400.00")
	assert((figures["uncollected"] as MoneyScript).format() == "250.00", "400.00 billed, 150.00 paid")
	assert(bool(figures["uncollected_known"]))
	assert(not report.notes.has("nothing has been invoiced, so what has been billed and what is "
		+ "uncollected are not known rather than nothing"))


func test_the_margin_is_what_has_been_earned_less_what_it_has_cost() -> void:
	# On a **cost** budget, so the contract sum is not the budget and the margin is a real number:
	# 340.00 of cost budget, 550.00 agreed, 90.00 spent is 264706 ppm earned, so 145.59 earned and
	# 55.59 of margin.
	var report := _with_costs(JobScript.COST)
	var figures: Dictionary = report.totals()
	assert(int(figures["percent_ppm"]) == 264706, str(figures["percent_ppm"]))
	assert((figures["earned"] as MoneyScript).format() == "145.59",
		(figures["earned"] as MoneyScript).format())
	assert((figures["margin_to_date"] as MoneyScript).format() == "55.59",
		(figures["margin_to_date"] as MoneyScript).format())
	assert(bool(figures["margin_known"]))
	assert((report.row_for("PLANTING")["budget"] as MoneyScript).format() == "100.00",
		"the budget is what the work costs the business")


func test_the_basis_travels_with_every_budget() -> void:
	var priced := _with_costs()
	assert(String(priced.row_for("PLANTING")["basis_name"]) == "price")
	assert(priced.notes.has("the budget is the price the customer pays for each code, so a variance "
		+ "against it is a margin to date and not a cost overrun"), str(priced.notes))
	var costed := _with_costs(JobScript.COST)
	assert(String(costed.row_for("PLANTING")["basis_name"]) == "cost")
	assert(costed.notes.has("the budget is the cost the business pays for each code"),
		str(costed.notes))


# --- what it says ---------------------------------------------------------------------------------


func test_describe_reads_as_one_line() -> void:
	var report := _with_costs()
	assert(report.describe() == "budget $550.00, committed $40.00, actual $90.00, "
		+ "projection $420.00, 16.4% complete by cost incurred", report.describe())
	assert(JobCostScript.of(null, [], [], []).describe()
		== "nothing has been costed to this job yet")


func test_totals_text_names_every_figure_and_its_basis() -> void:
	var report := _with_costs()
	var text := report.totals_text()
	assert(text.contains("contract sum"), text)
	assert(text.contains("cost incurred"), text)
	assert(text.contains("gross margin to date"), text)
	assert(text.contains("billed"), text)
	assert(text.contains("margin to date and not a cost overrun"), text)
	var costed := _with_costs(JobScript.COST).totals_text()
	assert(costed.contains("the budget is the cost the business pays"), costed)


func test_a_row_reads_as_the_four_numbers_side_by_side() -> void:
	var report := _with_costs()
	assert(report.row_text("PLANTING") == "PLANTING  budget $150.00  committed $40.00  "
		+ "actual $90.00  variance $60.00", report.row_text("PLANTING"))
	assert(report.row_text("SOMETHING") == "SOMETHING is not on this report")


func test_the_report_is_a_function_of_the_records_and_nothing_is_cached() -> void:
	var order := _po_planting()
	var orders: Array = [order]
	var first: JobCostScript = JobCostScript.of(_job(), orders, [], [_entry()])
	var again: JobCostScript = JobCostScript.of(_job(), orders, [], [_entry()])
	assert(first.describe() == again.describe(), "the same records say the same thing")
	order.receive("2026-06-09", 0, 4000)
	var after: JobCostScript = JobCostScript.of(_job(), orders, [], [_entry()])
	assert(not after.describe() == first.describe(), "and a delivery changes it")
	assert((after.row_for("PLANTING")["actual"] as MoneyScript).format() == "130.00",
		(after.row_for("PLANTING")["actual"] as MoneyScript).format())


func test_an_unreadable_rate_poisons_the_report_rather_than_reading_as_free() -> void:
	var broken: OrderScript = OrderScript.from_dict({
		"id": "PO9", "job": "E1", "cost_code": "PLANTING", "supplier": "Greenline",
		"issued_at": "2026-06-01",
		"lines": [{"description": "Buxus", "ordered_milli": 10000}],
	})
	assert(not broken.is_sound(), "and the order itself says what is wrong with it")
	var report := JobCostScript.of(_job(), [broken], [], [])
	assert(not (report.row_for("PLANTING")["committed"] as MoneyScript).is_valid())
	assert(not (report.totals()["committed"] as MoneyScript).is_valid(),
		"one unreadable rate does not quietly read as nothing committed")