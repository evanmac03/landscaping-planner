extends Node
## Job costing through the desk: the orders a job places, the changes a customer agrees to, and the
## report they add up to (spec §8.3, §8.2, §8.4).
##
## The desk holds no arithmetic here either. What is under test is the join: that the desk hands the
## numbers out, that the budget question is asked **before** an order goes out, that a receipt moves
## money from committed to actual, and that a change order only joins the contract sum once somebody
## has recorded the customer agreeing to it.

const DeskScript := preload("res://scripts/biz/job_desk.gd")
const JobScript := preload("res://scripts/biz/job.gd")
const CostScript := preload("res://scripts/biz/job_cost.gd")
const ChangeScript := preload("res://scripts/biz/change_order.gd")
const OrderScript := preload("res://scripts/biz/purchase_order.gd")
const EstimateScript := preload("res://scripts/biz/estimate.gd")
const LineScript := preload("res://scripts/biz/estimate_line.gd")
const ItemScript := preload("res://scripts/biz/cost_item.gd")
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


## PLANTING 150.00 sold for 100.00 of cost, HARDSCAPE 400.00 for 240.00.
func _estimate() -> EstimateScript:
	var estimate: EstimateScript = EstimateScript.new("E1")
	estimate.customer = {"name": "Smith, back garden"}
	estimate.lines.append(_line(&"PLANTING", 10000, 1000, 1500))
	estimate.lines.append(_line(&"HARDSCAPE", 20000, 1200, 2000))
	return estimate


## A desk with the job on it, made the way the interface makes one.
func _desk() -> DeskScript:
	var desk: DeskScript = DeskScript.new()
	assert(desk.make_job_from(_estimate()) != null, "the job is on the desk")
	return desk


func _entry(entry_id: String = "T1", code: StringName = &"PLANTING", minutes: int = 60,
		rate_cents: int = 3000) -> EntryScript:
	var entry: EntryScript = EntryScript.new(entry_id)
	entry.job = "E1"
	entry.cost_code = code
	entry.crew_member = &"C1"
	var start := Time.get_unix_time_from_datetime_string("2026-06-10T08:00:00")
	entry.started_at = "2026-06-10T08:00:00"
	entry.ended_at = Time.get_datetime_string_from_unix_time(start + minutes * 60)
	entry.loaded_rate = MoneyScript.of(rate_cents)
	entry.approve("Dana")
	return entry


# --- ordering ----------------------------------------------------------------------------------


func test_an_order_is_numbered_by_the_desk_and_is_not_issued_by_being_made() -> void:
	var desk := _desk()
	var order = desk.make_purchase_order("E1", &"PLANTING", "Buxus, 2 gal", 10000,
		MoneyScript.of(1000), "Greenline Nursery")
	assert(order != null, "the order was made")
	assert(order.number == "PO-001", order.number)
	assert(order.id == order.number, "a number is what everybody calls the paper")
	assert(order.state() == OrderScript.DRAFT)
	assert(desk.purchase_order("PO-001") == order)
	assert((desk.cost_report("E1").totals()["committed"] as MoneyScript).format() == "0.00",
		"a draft commits nothing")


func test_the_next_number_is_the_highest_taken_and_not_the_count() -> void:
	assert(DeskScript.next_number("PO-", []) == "PO-001")
	assert(DeskScript.next_number("PO-", ["PO-001"]) == "PO-002")
	assert(DeskScript.next_number("PO-", ["PO-001", "PO-007", "CO-009"]) == "PO-008",
		"a number that has been used is used")


func test_an_order_is_refused_for_a_job_the_desk_does_not_have() -> void:
	var desk := _desk()
	assert(desk.make_purchase_order("NOPE", &"PLANTING", "Buxus", 1000, MoneyScript.of(100),
		"Greenline") == null)
	assert(desk.purchase_orders_for("E1").is_empty())


func test_an_order_with_nothing_on_it_or_no_rate_is_not_made() -> void:
	var desk := _desk()
	assert(desk.make_purchase_order("E1", &"PLANTING", "", 1000, MoneyScript.of(100),
		"Greenline") == null, "a line with no description is not a line")
	assert(desk.make_purchase_order("E1", &"PLANTING", "Buxus", 0, MoneyScript.of(100),
		"Greenline") == null, "nor a quantity of nothing")
	assert(desk.make_purchase_order("E1", &"PLANTING", "Buxus", 1000, MoneyScript.invalid(),
		"Greenline") == null, "nor an unreadable rate")
	assert(desk.purchase_orders.is_empty())


func test_issuing_says_what_it_would_commit_the_job_to() -> void:
	var desk := _desk()
	# 20 units at 10.00 is 200.00 against a PLANTING budget of 150.00.
	var order = desk.make_purchase_order("E1", &"PLANTING", "Buxus, 2 gal", 20000,
		MoneyScript.of(1000), "Greenline Nursery")
	assert(order != null)
	var issued: Dictionary = desk.issue_purchase_order("PO-001", "2026-06-01")
	assert(bool(issued["ok"]), String(issued["reason"]))
	assert(String(issued["warning"]) == "PLANTING would be committed $200.00 against a budget of "
		+ "$150.00", String(issued["warning"]))
	assert(order.state() == OrderScript.ISSUED)
	assert((desk.cost_report("E1").row_for("PLANTING")["committed"] as MoneyScript).format() == "200.00")


func test_issuing_into_a_code_the_job_was_never_sold_is_refused_by_name() -> void:
	var desk := _desk()
	var order = desk.make_purchase_order("E1", &"EXTRAS", "A thing nobody sold", 1000,
		MoneyScript.of(500), "Greenline Nursery")
	assert(order != null, "the order can be written")
	var issued: Dictionary = desk.issue_purchase_order("PO-001", "2026-06-01")
	assert(not bool(issued["ok"]), "but it cannot be charged to nothing")
	assert(String(issued["reason"]).contains("has no EXTRAS in it"), String(issued["reason"]))
	assert(order.state() == OrderScript.DRAFT, "and nothing was committed")


func test_issuing_an_order_that_is_not_there_says_so() -> void:
	var desk := _desk()
	var issued: Dictionary = desk.issue_purchase_order("PO-009", "2026-06-01")
	assert(not bool(issued["ok"]))
	assert(String(issued["reason"]).contains("no order PO-009"), String(issued["reason"]))


func test_the_budget_question_asked_before_the_order_is_placed() -> void:
	var desk := _desk()
	assert(desk.make_purchase_order("E1", &"PLANTING", "Buxus", 10000, MoneyScript.of(1000),
		"Greenline") != null)
	desk.issue_purchase_order("PO-001", "2026-06-01")
	var fits: Dictionary = desk.order_would_commit("E1", &"PLANTING", 4000, MoneyScript.of(1000))
	assert(not bool(fits["over"]), "40.00 more fits")
	assert((fits["remaining"] as MoneyScript).format() == "50.00")
	var too_much: Dictionary = desk.order_would_commit("E1", &"PLANTING", 6000, MoneyScript.of(1000))
	assert(bool(too_much["over"]))
	assert(String(too_much["reason"]).contains("committed $160.00 against a budget of $150.00"),
		String(too_much["reason"]))


# --- what arrived ------------------------------------------------------------------------------


func test_what_arrived_moves_the_money_from_committed_to_actual() -> void:
	var desk := _desk()
	desk.make_purchase_order("E1", &"PLANTING", "Buxus", 10000, MoneyScript.of(1000), "Greenline")
	desk.issue_purchase_order("PO-001", "2026-06-01")
	var taken: Dictionary = desk.receive_what_was_ordered("PO-001", "2026-06-05")
	assert(bool(taken["ok"]), String(taken["reason"]))
	var row: Dictionary = desk.cost_report("E1").row_for("PLANTING")
	assert((row["committed"] as MoneyScript).format() == "0.00")
	assert((row["actual"] as MoneyScript).format() == "100.00")
	assert(desk.purchase_order("PO-001").state() == OrderScript.RECEIVED)


func test_a_short_delivery_is_recorded_line_by_line() -> void:
	var desk := _desk()
	desk.make_purchase_order("E1", &"HARDSCAPE", "Paving stones", 20000, MoneyScript.of(1000),
		"Stone Yard")
	desk.issue_purchase_order("PO-001", "2026-06-01")
	assert(desk.receive_order_line("PO-001", 0, 6000, "2026-06-05", "half the pallets")["ok"])
	var row: Dictionary = desk.cost_report("E1").row_for("HARDSCAPE")
	assert((row["committed"] as MoneyScript).format() == "140.00", "200.00 ordered less 60.00 arrived")
	assert((row["actual"] as MoneyScript).format() == "60.00")
	assert(desk.purchase_order("PO-001").state() == OrderScript.PARTIAL)
	var again: Dictionary = desk.receive_what_was_ordered("PO-001", "2026-06-12")
	assert(bool(again["ok"]), "and the rest arrives when it arrives")
	assert((desk.cost_report("E1").row_for("HARDSCAPE")["actual"] as MoneyScript).format() == "200.00")
	assert(not bool(desk.receive_what_was_ordered("PO-001", "2026-06-19")["ok"]),
		"with nothing outstanding there is nothing to receive")


func test_receiving_against_an_order_that_is_not_there_says_so() -> void:
	var desk := _desk()
	var taken: Dictionary = desk.receive_what_was_ordered("PO-009", "2026-06-05")
	assert(not bool(taken["ok"]))
	assert(String(taken["reason"]).contains("no order PO-009"), String(taken["reason"]))
	assert(not bool(desk.receive_order_line("PO-009", 0, 1000, "2026-06-05")["ok"]))


func test_closing_an_order_takes_it_out_of_the_commitment_and_leaves_the_cost() -> void:
	var desk := _desk()
	desk.make_purchase_order("E1", &"PLANTING", "Buxus", 10000, MoneyScript.of(1000), "Greenline")
	desk.issue_purchase_order("PO-001", "2026-06-01")
	assert(not desk.close_order("PO-001", "2026-07-01"), "nothing has arrived yet")
	desk.receive_order_line("PO-001", 0, 8000, "2026-06-05")
	assert(desk.close_order("PO-001", "2026-07-01", "invoiced and reconciled"))
	var row: Dictionary = desk.cost_report("E1").row_for("PLANTING")
	assert((row["committed"] as MoneyScript).format() == "0.00")
	assert((row["actual"] as MoneyScript).format() == "80.00")
	assert(desk.purchase_order("PO-001").state() == OrderScript.CLOSED)


func test_order_rows_read_the_way_the_office_reads_them() -> void:
	var desk := _desk()
	desk.make_purchase_order("E1", &"PLANTING", "Buxus", 10000, MoneyScript.of(1000), "Greenline")
	desk.issue_purchase_order("PO-001", "2026-06-01")
	desk.receive_order_line("PO-001", 0, 4000, "2026-06-05")
	var row: Dictionary = desk.order_rows("E1")[0]
	assert(String(row["number"]) == "PO-001")
	assert(String(row["cost_code"]) == "PLANTING")
	assert(String(row["supplier"]) == "Greenline")
	assert(String(row["state_name"]) == "partly received")
	assert((row["ordered"] as MoneyScript).format() == "100.00")
	assert((row["received"] as MoneyScript).format() == "40.00")
	assert((row["committed"] as MoneyScript).format() == "60.00")
	assert((row["actual"] as MoneyScript).format() == "40.00")
	assert((row["problems"] as Array).is_empty(), str(row["problems"]))
	assert(desk.order_rows("NOPE").is_empty())


# --- change orders -----------------------------------------------------------------------------


func test_a_change_order_made_at_the_desk_is_priced_numbered_and_proposed() -> void:
	var desk := _desk()
	var change = desk.make_change_order("E1", &"SITE_CONDITION", "Remove a buried wall",
		MoneyScript.of(50000), &"HARDSCAPE")
	assert(change != null)
	assert(change.number == "CO-001", change.number)
	assert(change.state() == ChangeScript.PROPOSED)
	assert(change.amount().format() == "500.00", change.amount().format())
	assert(change.line_count() == 1)
	assert(ChangeScript.reason_name(change.reason) == "site condition")
	assert(desk.change_order("CO-001") == change)


func test_a_change_order_needs_a_reason_that_exists_an_amount_and_a_job() -> void:
	var desk := _desk()
	assert(desk.make_change_order("E1", &"BECAUSE", "A thing", MoneyScript.of(100), &"PLANTING")
		== null, "a reason nobody has is not a reason")
	assert(desk.make_change_order("E1", &"OTHER", "A thing", MoneyScript.of(0), &"PLANTING")
		== null, "and nothing is not a change")
	assert(desk.make_change_order("NOPE", &"OTHER", "A thing", MoneyScript.of(100), &"PLANTING")
		== null)
	assert(desk.change_orders.is_empty())


func test_a_change_order_raised_from_an_estimate_copies_its_lines() -> void:
	var desk := _desk()
	var estimate := _estimate()
	var change = desk.change_order_from(estimate, "E1", &"DESIGN_CHANGE")
	assert(change != null)
	assert(change.line_count() == 2, "the change is the estimate it came from")
	assert(change.amount().format() == "550.00", change.amount().format())
	assert(change.cost().format() == "340.00")
	# A copy, and not a second reference to the estimate's lines.
	estimate.lines[0].quantity_milli = 20000
	assert(change.line_count() == 2)
	assert(change.amount().format() == "550.00", "the change order did not move with the estimate")


func test_a_change_order_with_nothing_on_it_or_a_job_that_is_not_there_is_not_raised() -> void:
	var desk := _desk()
	var empty: EstimateScript = EstimateScript.new("E9")
	assert(desk.change_order_from(empty, "E1", &"OTHER") == null)
	assert(desk.change_order_from(_estimate(), "NOPE", &"OTHER") == null)
	assert(desk.change_order_from(null, "E1", &"OTHER") == null)
	assert(desk.change_orders.is_empty())


func test_a_change_order_only_joins_the_contract_sum_once_it_is_approved() -> void:
	var desk := _desk()
	desk.make_change_order("E1", &"SITE_CONDITION", "Remove a buried wall", MoneyScript.of(50000),
		&"HARDSCAPE")
	assert((desk.cost_report("E1").totals()["agreed_sum"] as MoneyScript).format() == "550.00")
	assert(desk.propose_change("CO-001", "2026-06-20"))
	assert(desk.send_change("CO-001", "2026-06-21"))
	assert((desk.cost_report("E1").totals()["changes_pending"] as MoneyScript).format() == "500.00",
		"pending is shown beside the sum and not in it")
	var agreed: Dictionary = desk.approve_change("CO-001", "Dana", "2026-07-01", "in-app")
	assert(bool(agreed["ok"]), String(agreed["reason"]))
	var figures: Dictionary = desk.cost_report("E1").totals()
	assert((figures["agreed_sum"] as MoneyScript).format() == "1,050.00")
	assert((figures["changes_pending"] as MoneyScript).format() == "0.00")
	assert(int(figures["pending_count"]) == 0)


func test_an_approval_without_who_when_or_how_is_refused_by_the_desk_too() -> void:
	var desk := _desk()
	desk.make_change_order("E1", &"OTHER", "A thing", MoneyScript.of(10000), &"PLANTING")
	assert(String(desk.approve_change("CO-001", "", "2026-07-01", "in-app")["reason"])
		.contains("who agreed"))
	assert(String(desk.approve_change("CO-001", "Dana", "2026-07-01", "a handshake")["reason"])
		.contains("says how"))
	assert((desk.cost_report("E1").totals()["agreed_sum"] as MoneyScript).format() == "550.00")


func test_declining_and_voiding_through_the_desk() -> void:
	var desk := _desk()
	desk.make_change_order("E1", &"CUSTOMER_REQUEST", "Add a path", MoneyScript.of(20000),
		&"HARDSCAPE")
	assert(not bool(desk.decline_change("CO-001", "Dana", "2026-07-02", "")["ok"]),
		"a decline says why")
	assert(bool(desk.decline_change("CO-001", "Dana", "2026-07-02", "too expensive")["ok"]))
	assert(desk.change_order("CO-001").state() == ChangeScript.DECLINED)
	desk.make_change_order("E1", &"OTHER", "And another", MoneyScript.of(5000), &"PLANTING")
	assert(String(desk.void_change("CO-002", "2026-07-02", "")["reason"]).contains("says why"))
	assert(bool(desk.void_change("CO-002", "2026-07-02", "the customer withdrew it")["ok"]))
	assert(desk.change_order("CO-002").state() == ChangeScript.VOID)


func test_a_change_order_that_is_not_there_is_refused_by_the_desk() -> void:
	var desk := _desk()
	assert(not desk.propose_change("CO-009", "2026-06-20"))
	assert(not desk.send_change("CO-009", "2026-06-21"))
	assert(String(desk.approve_change("CO-009", "Dana", "2026-07-01", "in-app")["reason"])
		.contains("no change order CO-009"))


func test_change_rows_carry_the_state_the_amount_and_the_approval() -> void:
	var desk := _desk()
	desk.make_change_order("E1", &"CODE_OR_PERMIT", "A permit nobody expected", MoneyScript.of(8500),
		&"HARDSCAPE")
	desk.propose_change("CO-001", "2026-06-20")
	desk.approve_change("CO-001", "Dana", "2026-07-01", "signed paper photo")
	var row: Dictionary = desk.change_rows("E1")[0]
	assert(String(row["number"]) == "CO-001")
	assert(String(row["reason_name"]) == "code or permit")
	assert(String(row["state_name"]) == "approved")
	assert((row["amount"] as MoneyScript).format() == "85.00")
	assert(String(row["amount_text"]) == "+$85.00")
	assert(not bool(row["pending"]))
	assert(bool(row["enters_contract_sum"]))
	assert(String(row["approval_text"]) == "approved by Dana on 2026-07-01 (signed paper photo)",
		String(row["approval_text"]))
	assert(desk.change_rows("NOPE").is_empty())


# --- the report --------------------------------------------------------------------------------


func test_the_report_is_the_jobs_own_records_and_reads_the_way_a_report_does() -> void:
	var desk := _desk()
	desk.make_purchase_order("E1", &"PLANTING", "Buxus", 10000, MoneyScript.of(1000), "Greenline")
	desk.issue_purchase_order("PO-001", "2026-06-01")
	desk.receive_order_line("PO-001", 0, 6000, "2026-06-05")
	assert(desk.log_time(_entry()), "the hour reads")
	desk.make_change_order("E1", &"SITE_CONDITION", "A wall", MoneyScript.of(50000), &"HARDSCAPE")
	desk.propose_change("CO-001", "2026-06-20")
	var report = desk.cost_report("E1")
	assert(report != null)
	assert(report.codes() == ["HARDSCAPE", "PLANTING"], str(report.codes()))
	assert((report.row_for("PLANTING")["actual"] as MoneyScript).format() == "90.00",
		"60.00 arrived and 30.00 of approved time")
	var text: String = desk.cost_totals_text("E1")
	assert(text.contains("cost incurred"), text)
	assert(text.contains("change orders agreed"), text)
	assert(desk.cost_problems("E1").has("1 change order pending, $500.00 not yet agreed"),
		str(desk.cost_problems("E1")))


func test_a_receipt_entered_a_moment_ago_is_in_the_report() -> void:
	var desk := _desk()
	desk.make_purchase_order("E1", &"PLANTING", "Buxus", 10000, MoneyScript.of(1000), "Greenline")
	desk.issue_purchase_order("PO-001", "2026-06-01")
	var before: String = desk.cost_totals_text("E1")
	desk.receive_order_line("PO-001", 0, 4000, "2026-06-05")
	var after: String = desk.cost_totals_text("E1")
	assert(not before == after, "nothing is cached between two readings")


func test_a_job_the_desk_does_not_have_has_no_report() -> void:
	var desk := _desk()
	assert(desk.cost_report("NOPE") == null)
	assert(desk.cost_rows("NOPE").is_empty())
	assert(desk.cost_totals_text("NOPE").is_empty())
	assert(desk.cost_problems("NOPE").is_empty())


func test_what_has_been_billed_is_unknown_until_somebody_says() -> void:
	var desk := _desk()
	var report = desk.cost_report("E1")
	assert(not bool(report.totals()["billed_known"]), "nobody has invoiced this job")
	assert(not desk.set_invoiced("E1", MoneyScript.invalid()), "an unreadable figure is not a figure")
	assert(desk.set_invoiced("E1", MoneyScript.of(40000)))
	assert(desk.set_collected("E1", MoneyScript.of(15000)))
	var figures: Dictionary = desk.cost_report("E1").totals()
	assert(bool(figures["billed_known"]))
	assert((figures["uncollected"] as MoneyScript).format() == "250.00")
	assert(not desk.set_invoiced("NOPE", MoneyScript.of(100)),
		"a billed figure for a job nobody has is not a record")


func test_the_menu_line_counts_the_orders_the_commitment_and_the_changes() -> void:
	var desk := _desk()
	var plain: String = desk.describe()
	assert(plain == "1 job, 0 blocks on the board", plain)
	desk.make_purchase_order("E1", &"PLANTING", "Buxus", 10000, MoneyScript.of(1000), "Greenline")
	desk.issue_purchase_order("PO-001", "2026-06-01")
	desk.make_change_order("E1", &"SITE_CONDITION", "A wall", MoneyScript.of(50000), &"HARDSCAPE")
	desk.propose_change("CO-001", "2026-06-20")
	var line: String = desk.describe()
	assert(line == "1 job, 0 blocks on the board, 1 purchase order ($100.00 committed), "
		+ "1 change order ($0.00 agreed, 1 pending)", line)
	desk.approve_change("CO-001", "Dana", "2026-07-01", "in-app")
	assert(desk.describe().contains("1 change order ($500.00 agreed)"), desk.describe())
	assert(not desk.describe().contains("pending"), "nothing is waiting for an answer any more")


# --- the file -----------------------------------------------------------------------------------


func test_the_desk_survives_the_file_with_its_orders_and_its_changes() -> void:
	var desk := _desk()
	desk.make_purchase_order("E1", &"PLANTING", "Buxus", 10000, MoneyScript.of(1000), "Greenline")
	desk.issue_purchase_order("PO-001", "2026-06-01")
	desk.receive_order_line("PO-001", 0, 4000, "2026-06-05", "half the pallets")
	desk.make_change_order("E1", &"SITE_CONDITION", "A wall", MoneyScript.of(50000), &"HARDSCAPE")
	desk.propose_change("CO-001", "2026-06-20")
	desk.approve_change("CO-001", "Dana", "2026-07-01", "in-app")
	desk.set_invoiced("E1", MoneyScript.of(40000))
	desk.set_collected("E1", MoneyScript.of(10000))
	var text := JSON.stringify(desk.to_dict())
	var read: DeskScript = DeskScript.from_dict(JSON.parse_string(text))
	assert(read.purchase_orders.size() == 1)
	assert(read.purchase_order("PO-001").received_milli(0) == 4000, "the deliveries travelled")
	assert((read.purchase_order("PO-001").committed() as MoneyScript).format() == "60.00")
	assert(read.change_orders.size() == 1)
	assert(read.change_order("CO-001").is_approved(), "the approval travelled")
	assert((read.cost_report("E1").totals()["agreed_sum"] as MoneyScript).format() == "1,050.00")
	assert((read.cost_report("E1").totals()["billed"] as MoneyScript).format() == "400.00")
	assert((read.cost_report("E1").totals()["uncollected"] as MoneyScript).format() == "300.00")
	assert(read.describe() == desk.describe(), read.describe())


func test_an_order_or_a_change_order_for_a_job_nobody_has_is_dropped() -> void:
	var desk := _desk()
	desk.make_purchase_order("E1", &"PLANTING", "Buxus", 10000, MoneyScript.of(1000), "Greenline")
	desk.make_change_order("E1", &"OTHER", "A thing", MoneyScript.of(10000), &"PLANTING")
	var data: Dictionary = desk.to_dict()
	var orphans: Array = data["purchase_orders"]
	var stray: Dictionary = (orphans[0] as Dictionary).duplicate(true)
	stray["id"] = "PO-404"
	stray["number"] = "PO-404"
	stray["job"] = "GONE"
	orphans.append(stray)
	var loose: Array = data["change_orders"]
	var lost: Dictionary = (loose[0] as Dictionary).duplicate(true)
	lost["id"] = "CO-404"
	lost["number"] = "CO-404"
	lost["job"] = "GONE"
	loose.append(lost)
	var read: DeskScript = DeskScript.from_dict(data)
	assert(read.purchase_orders.size() == 1, "an order for no job is money nothing can explain")
	assert(read.change_orders.size() == 1)
	assert(read.purchase_order("PO-404") == null)
	assert(read.change_order("CO-404") == null)


func test_the_billed_figures_of_a_job_nobody_has_are_dropped_too() -> void:
	var desk := _desk()
	var data: Dictionary = desk.to_dict()
	(data["invoiced"] as Dictionary)["GONE"] = MoneyScript.of(100).to_dict()
	(data["collected"] as Dictionary)["GONE"] = MoneyScript.of(50).to_dict()
	(data["invoiced"] as Dictionary)["E1"] = MoneyScript.of(40000).to_dict()
	var read: DeskScript = DeskScript.from_dict(data)
	assert(not read.invoiced.has("GONE"))
	assert((read.cost_report("E1").totals()["billed"] as MoneyScript).format() == "400.00")
	assert(not bool(read.cost_report("E1").totals()["uncollected_known"]),
		"nothing was collected, and nobody said so")