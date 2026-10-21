extends Node
## The purchase order: what was ordered, what arrived, and which of the two the money is (spec §8.3).
##
## The property under test throughout is the one §8.3 spends a paragraph on: **committed is issued and
## not received, and actual is what arrived** - because a job that looks profitable for the three weeks
## between the mulch arriving and the invoice being entered is the report every landscape business has
## been burned by.

const OrderScript := preload("res://scripts/biz/purchase_order.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")


## An order of 10 units at $12.50: $125.00 ordered.
func _order(order_id: String = "PO1") -> OrderScript:
	var order: OrderScript = OrderScript.new(order_id)
	order.number = "PO-2026-001"
	order.job = "E1"
	order.cost_code = &"PLANTING"
	order.supplier = "Greenline Nursery"
	order.add_line("Buxus, 2 gal", &"EACH", 10000, MoneyScript.of(1250))
	return order


func _issued() -> OrderScript:
	var order := _order()
	order.issue("2026-06-01")
	return order


# --- ordering --------------------------------------------------------------------------------


func test_a_line_needs_something_to_order_a_quantity_and_a_rate() -> void:
	var order: OrderScript = OrderScript.new("PO1")
	assert(not order.add_line("", &"EACH", 1000, MoneyScript.of(100)))
	assert(not order.add_line("Mulch", &"YARD", 0, MoneyScript.of(100)))
	assert(not order.add_line("Mulch", &"YARD", 1000, MoneyScript.invalid()))
	assert(not order.add_line("Mulch", &"YARD", 1000, null))
	assert(order.line_count() == 0)
	assert(order.add_line("Mulch", &"YARD", 3000, MoneyScript.of(4800)))


func test_a_draft_commits_nothing_and_costs_nothing() -> void:
	var order := _order()
	assert(order.state() == OrderScript.DRAFT)
	assert(order.state_name() == "draft, not ordered")
	assert(not order.is_issued())
	assert(order.ordered_total().format() == "125.00", order.ordered_total().format())
	assert(order.committed().format() == "0.00", "nobody has ordered it")
	assert(order.actual().format() == "0.00")


func test_issuing_needs_a_supplier_something_on_it_and_a_moment() -> void:
	var bare: OrderScript = OrderScript.new("PO0")
	assert(not bare.issue("2026-06-01")["ok"], "no supplier")
	bare.supplier = "Greenline Nursery"
	assert(not bare.issue("2026-06-01")["ok"], "nothing on it")
	bare.add_line("Mulch", &"YARD", 3000, MoneyScript.of(4800))
	assert(not bare.issue("")["ok"], "an issued order says when")
	var done: Dictionary = bare.issue("2026-06-01")
	assert(bool(done["ok"]), String(done["reason"]))
	assert(not bare.issue("2026-06-02")["ok"], "it has already been issued")


func test_an_issued_order_commits_what_was_ordered_and_costs_nothing_yet() -> void:
	var order := _issued()
	assert(order.state() == OrderScript.ISSUED)
	assert(order.state_name() == "issued, nothing has arrived")
	assert(order.committed().format() == "125.00", order.committed().format())
	assert(order.actual().format() == "0.00", "nothing has arrived")


# --- receiving ---------------------------------------------------------------------------------


func test_a_receipt_turns_commitment_into_actual() -> void:
	var order := _issued()
	assert(order.receive("2026-06-05", 0, 4000)["ok"])
	assert(order.state() == OrderScript.PARTIAL)
	assert(order.received_milli(0) == 4000)
	assert(order.actual().format() == "50.00", order.actual().format())
	assert(order.committed().format() == "75.00", "what is still owed is what has not arrived")


func test_a_full_delivery_is_received_and_commits_nothing() -> void:
	var order := _issued()
	order.receive("2026-06-05", 0, 6000)
	order.receive("2026-06-09", 0, 4000)
	assert(order.state() == OrderScript.RECEIVED)
	assert(order.actual().format() == "125.00")
	assert(order.committed().format() == "0.00")


func test_a_receipt_is_a_quantity_and_the_orders_own_rate_prices_it() -> void:
	# Two lines at different rates: a receipt is a quantity, and nothing else, because §8.3 says a
	# receipt is not an invoice.
	var order := _issued()
	order.add_line("Compost, bulk", &"YARD", 2000, MoneyScript.of(3150))
	order.receive("2026-06-05", 1, 2000)
	assert(order.actual().format() == "63.00", order.actual().format())
	assert(order.line_received_cost(1).format() == "63.00")
	assert(order.actual().format() == order.received_total().format())


func test_receiving_more_than_ordered_is_not_an_error() -> void:
	var order := _issued()
	var taken: Dictionary = order.receive("2026-06-05", 0, 12000)
	assert(bool(taken["ok"]), "the receipt says what arrived")
	assert(order.state() == OrderScript.RECEIVED, "more than ordered is still received")
	assert(order.actual().format() == "150.00", order.actual().format())
	assert(order.committed().format() == "0.00", "an over-delivery does not make the money owed negative")
	assert(order.variance_milli(0) == 2000, "and the variance is reported")
	assert(order.line_variance(0).format() == "25.00", order.line_variance(0).format())


func test_receiving_needs_an_issued_order_a_line_and_a_quantity() -> void:
	var draft := _order()
	assert(not draft.receive("2026-06-05", 0, 1000)["ok"], "nobody has ordered it")
	var order := _issued()
	assert(String(order.receive("2026-06-05", 5, 1000)["reason"]).contains("no line 5"))
	assert(not order.receive("2026-06-05", 0, 0)["ok"], "a receipt is a quantity that arrived")
	assert(not order.receive("", 0, 1000)["ok"], "a receipt says when it arrived")
	assert(order.receipts.is_empty(), "and nothing was recorded")


func test_the_state_is_a_function_of_the_records_and_not_a_field() -> void:
	var order := _issued()
	assert(order.state() == OrderScript.ISSUED)
	order.receive("2026-06-05", 0, 10000)
	assert(order.state() == OrderScript.RECEIVED)
	# A record edited by hand - the receipts are the truth, so the state follows them.
	order.receipts.clear()
	assert(order.state() == OrderScript.ISSUED, "nothing has arrived because nothing is recorded")
	assert(order.committed().format() == "125.00")


func test_a_delivery_is_recorded_once_so_the_line_and_the_receipts_cannot_disagree() -> void:
	var order := _issued()
	order.receive("2026-06-05", 0, 3000)
	order.receive("2026-06-06", 0, 3000)
	assert(order.received_milli(0) == 6000)
	assert(order.received_milli_total() == 6000, "the line and the receipts are one number")
	assert(order.received_total().format() == "75.00")


# --- closing ----------------------------------------------------------------------------------


func test_closing_needs_something_to_have_arrived_and_takes_it_out_of_the_report() -> void:
	var order := _issued()
	assert(not order.mark_closed("2026-07-01"), "nothing has arrived")
	order.receive("2026-06-05", 0, 8000)
	assert(not order.mark_closed(""), "and it says when")
	assert(order.mark_closed("2026-07-01", "invoiced and reconciled"))
	assert(order.state() == OrderScript.CLOSED)
	assert(order.is_closed())
	assert(not order.is_issued())
	assert(order.committed().format() == "0.00", "closed is neither committed nor")
	assert(order.actual().format() == "100.00", "and the cost stays where it is")
	assert(not order.mark_closed("2026-07-02"), "and it cannot be closed twice")
	assert(not order.receive("2026-07-02", 0, 1000)["ok"], "a closed order takes no receipts")


func test_closing_an_order_that_never_was_issued_is_refused() -> void:
	var draft := _order()
	assert(not draft.mark_closed("2026-07-01"))


# --- what is wrong with it ------------------------------------------------------------------


func test_a_receipt_dated_before_the_order_is_a_fault() -> void:
	var order := _order()
	order.issue("2026-06-10")
	order.receive("2026-06-01", 0, 1000)
	assert(order.problems()[0].contains("before it was issued"), str(order.problems()))
	assert(not order.is_sound())


func test_an_order_with_a_receipt_and_no_issue_date_is_a_fault() -> void:
	var order := _order()
	order.receipts.append({"at": "2026-06-05", "line": 0, "quantity_milli": 1000})
	assert(order.problems()[0].contains("was never issued"), str(order.problems()))


func test_a_closed_order_short_of_what_was_ordered_says_so() -> void:
	var order := _issued()
	order.receive("2026-06-05", 0, 6000)
	order.mark_closed("2026-07-01")
	assert(order.problems()[0].contains("closed with 6000 of 10000"), str(order.problems()))


func test_an_order_with_no_id_is_a_fault() -> void:
	var bare: OrderScript = OrderScript.new("")
	assert(bare.problems()[0].contains("needs an id"), str(bare.problems()))


func test_describe_reads_as_a_purchase_order() -> void:
	var order := _issued()
	assert(order.describe() == "PO-2026-001 to Greenline Nursery, issued, nothing has arrived, "
		+ "ordered $125.00, committed $125.00 (PLANTING)", order.describe())
	order.receive("2026-06-05", 0, 4000)
	assert(order.describe().contains("arrived $50.00"), order.describe())
	assert(order.describe().contains("committed $75.00"), order.describe())


func test_line_rows_read_the_way_a_receiver_reads_them() -> void:
	var order := _issued()
	order.receive("2026-06-05", 0, 4000)
	var row: Dictionary = order.line_rows()[0]
	assert(int(row["index"]) == 0)
	assert(String(row["description"]) == "Buxus, 2 gal")
	assert(int(row["ordered_milli"]) == 10000)
	assert(int(row["received_milli"]) == 4000)
	assert(int(row["variance_milli"]) == -6000)
	assert((row["ordered"] as MoneyScript).format() == "125.00")
	assert((row["received"] as MoneyScript).format() == "50.00")


# --- the file -----------------------------------------------------------------------------------


func test_an_order_survives_the_file() -> void:
	var order := _issued()
	order.expected_at = "2026-06-04"
	order.receive("2026-06-05", 0, 4000, "half the pallets", "user://photo.png")
	var text := JSON.stringify(order.to_dict())
	var restored: OrderScript = OrderScript.from_dict(JSON.parse_string(text))
	assert(restored.id == "PO1")
	assert(restored.number == "PO-2026-001")
	assert(String(restored.cost_code) == "PLANTING")
	assert(restored.supplier == "Greenline Nursery")
	assert(restored.line_count() == 1)
	assert(restored.received_milli(0) == 4000, "the deliveries travelled")
	assert(restored.actual().format() == "50.00", restored.actual().format())
	assert(restored.committed().format() == "75.00")
	assert(restored.state() == OrderScript.PARTIAL)
	assert(restored.expected_at == "2026-06-04")
	assert(String(restored.receipts[0]["note"]) == "half the pallets")
	assert(restored.describe() == order.describe(), restored.describe())


func test_a_record_with_no_id_and_a_receipt_for_no_line_are_dropped() -> void:
	assert(OrderScript.from_dict({}) == null)
	var read: OrderScript = OrderScript.from_dict({
		"id": "PO9",
		"lines": [{"description": "Mulch", "ordered_milli": 3000, "unit_cost": MoneyScript.of(4800).to_dict()}],
		"receipts": [
			{"at": "2026-06-05", "line": 4, "quantity_milli": 1000},
			{"at": "2026-06-06", "line": 0, "quantity_milli": 1000},
			{"at": "2026-06-07", "line": 0, "quantity_milli": 0},
		],
	})
	assert(read.line_count() == 1)
	assert(read.receipts.size() == 1, "a receipt that names no line is not a receipt")
	assert(read.received_milli(0) == 1000)


func test_an_unreadable_rate_poisons_the_totals_rather_than_reading_as_free() -> void:
	var order: OrderScript = OrderScript.from_dict({
		"id": "PO9",
		"lines": [{"description": "Mulch", "ordered_milli": 3000}],
	})
	assert(not order.ordered_total().is_valid(), "a line with no rate is not a line at nothing")
	assert(not order.is_sound())