extends Node
## The cost report page: the three figures per cost code, and the two things a person does about them
## (spec §8.4).
##
## The page owns no arithmetic - every figure is a field of a row the report produced - so these tests
## hold three things: that what is shown is what the report says, that the budget question is asked
## **before** an order goes out, and that agreeing to a change order needs somebody's name.
##
## Each test frees the window it built, which is what the other window tests do: a `Window` is a tree
## with a viewport, and letting one live to engine exit is a leaked resource.

const WindowScript := preload("res://scripts/job_cost_window.gd")
const DeskScript := preload("res://scripts/biz/job_desk.gd")
const ChangeScript := preload("res://scripts/biz/change_order.gd")
const EstimateScript := preload("res://scripts/biz/estimate.gd")
const LineScript := preload("res://scripts/biz/estimate_line.gd")
const ItemScript := preload("res://scripts/biz/cost_item.gd")
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
func _desk() -> DeskScript:
	var desk: DeskScript = DeskScript.new()
	var estimate: EstimateScript = EstimateScript.new("E1")
	estimate.customer = {"name": "Smith, back garden"}
	estimate.lines.append(_line(&"PLANTING", 10000, 1000, 1500))
	estimate.lines.append(_line(&"HARDSCAPE", 20000, 1200, 2000))
	desk.make_job_from(estimate)
	return desk


func _page(desk: DeskScript) -> WindowScript:
	var page: WindowScript = WindowScript.new()
	page.build()
	page.bind(desk)
	return page


# --- building ----------------------------------------------------------------------------------


func test_a_page_with_no_desk_is_empty_rather_than_broken() -> void:
	var page: WindowScript = WindowScript.new()
	page.build()
	page.bind(null)
	assert(page.summary_text() == "no job chosen", page.summary_text())
	assert(page.row_count() == 0)
	assert(page.total_text() == "")
	assert(page.problem_texts().is_empty())
	assert(page.order_texts().is_empty())
	assert(page.change_texts().is_empty())
	assert(page.order_button_disabled())
	assert(page.row_text("PLANTING") == "PLANTING is not on this report")
	page.free()


func test_the_page_has_the_controls_a_program_of_this_kind_has() -> void:
	var page := _page(_desk())
	assert(page.get_node_or_null(NodePath("Column/Summary")) != null)
	assert(page.get_node_or_null(NodePath("Column/JobRow/JobOption")) != null)
	assert(page.get_node_or_null(NodePath("Column/Rows")) != null)
	assert(page.get_node_or_null(NodePath("Column/Totals")) != null)
	assert(page.get_node_or_null(NodePath("Column/Problems")) != null)
	assert(page.get_node_or_null(NodePath("Column/Orders")) != null)
	assert(page.get_node_or_null(NodePath("Column/Changes")) != null)
	assert(page.get_node_or_null(NodePath("Column/OrderRow/CodeOption")) != null)
	assert(page.get_node_or_null(NodePath("Column/OrderRow/Supplier")) != null)
	assert(page.get_node_or_null(NodePath("Column/OrderRow/Description")) != null)
	assert(page.get_node_or_null(NodePath("Column/OrderRow/Quantity")) != null)
	assert(page.get_node_or_null(NodePath("Column/OrderRow/Rate")) != null)
	assert(page.get_node_or_null(NodePath("Column/OrderRow/Hint")) != null)
	assert(page.get_node_or_null(NodePath("Column/OrderRow/Orderit")) != null)
	assert(page.get_node_or_null(NodePath("Column/ChangeRow/AgreedBy")) != null)
	assert(page.get_node_or_null(NodePath("Column/ChangeRow/HowOption")) != null)
	assert(page.get_node_or_null(NodePath("Column/ChangeRow/Why")) != null)
	assert(page.get_node_or_null(NodePath("Column/Status")) != null)
	page.free()


func test_nothing_on_the_page_takes_the_keyboard() -> void:
	var page := _page(_desk())
	assert(page.buttons_are_focus_free(), "a button that took focus would swallow the drawing's keys")
	page.free()


func test_a_page_that_has_opened_says_what_to_do_with_it() -> void:
	var page := _page(_desk())
	assert(page.status_text() == page.opening_words(), page.status_text())
	assert(page.status_text().contains("what the order would commit the job to"), page.status_text())
	var bare: WindowScript = WindowScript.new()
	bare.build()
	bare.bind(DeskScript.new())
	assert(bare.status_text() == "No job has been started yet: an estimate that is agreed becomes a job.",
		bare.status_text())
	bare.free()
	page.free()


# --- the table ---------------------------------------------------------------------------------


func test_the_table_is_one_row_per_cost_code_and_the_reports_own_figures() -> void:
	var page := _page(_desk())
	assert(page.row_count() == 2, str(page.row_count()))
	assert(page.row_text("PLANTING") == "PLANTING  $150.00  $0.00  $0.00  $150.00  0.0%",
		page.row_text("PLANTING"))
	var grid: GridContainer = page.get_node(NodePath("Column/Rows"))
	assert(grid.columns == 6)
	assert(grid.get_child_count() == 18, "a header and two rows of six: %d" % grid.get_child_count())
	page.free()


func test_the_totals_are_the_reports_own_words() -> void:
	var page := _page(_desk())
	var text: String = page.total_text()
	assert(text.contains("contract sum"), text)
	assert(text.contains("cost incurred"), text)
	assert(text.contains("not known: nothing has been invoiced"), text)
	page.free()


func test_a_cost_entered_through_the_page_is_in_the_next_line_it_draws() -> void:
	var desk := _desk()
	var page := _page(desk)
	assert(page.row_text("PLANTING").contains("$0.00  $0.00"), page.row_text("PLANTING"))
	desk.make_purchase_order("E1", &"PLANTING", "Buxus", 10000, MoneyScript.of(1000), "Greenline")
	desk.issue_purchase_order("PO-001", "2026-06-01")
	page.refresh()
	assert(page.row_text("PLANTING").contains("$100.00  $0.00"), "committed, and nothing arrived yet")
	assert(page.row_text("PLANTING").contains("0.0%"), "none of it has been spent yet")
	assert(page.order_texts().size() == 1)
	assert(page.order_texts()[0].contains("issued, nothing has arrived"), page.order_texts()[0])
	desk.receive_what_was_ordered("PO-001", "2026-06-05")
	page.refresh()
	assert(page.row_text("PLANTING").contains("$0.00  $100.00"), "and now it has been costed")
	assert(page.row_text("PLANTING").contains("66.7%"), page.row_text("PLANTING"))
	assert(page.order_texts()[0].contains("received"), page.order_texts()[0])
	page.free()


# --- ordering ----------------------------------------------------------------------------------


func test_the_order_button_is_dead_until_the_fields_describe_an_order() -> void:
	var page := _page(_desk())
	assert(page.order_button_disabled(), "nothing is filled in")
	page.set_order_fields("Greenline Nursery", "Buxus, 2 gal", "10", "10.00")
	assert(not page.order_button_disabled(), "and now it is an order")
	page.set_order_fields("", "Buxus, 2 gal", "10", "10.00")
	assert(page.order_button_disabled(), "a purchase order needs a supplier")
	page.set_order_fields("Greenline Nursery", "", "10", "10.00")
	assert(page.order_button_disabled(), "and something on it")
	page.set_order_fields("Greenline Nursery", "Buxus, 2 gal", "0", "10.00")
	assert(page.order_button_disabled(), "a quantity of nothing is not a quantity")
	page.set_order_fields("Greenline Nursery", "Buxus, 2 gal", "10", "ten dollars")
	assert(page.order_button_disabled(), "and a rate nobody can read is not a rate")
	page.free()


func test_the_page_says_what_the_order_would_commit_before_it_goes_out() -> void:
	var page := _page(_desk())
	assert(page.selected_code() == "HARDSCAPE", "the job's phases are in code order, so this is first")
	assert(page.order_hint() == "A quantity of what is being ordered.", page.order_hint())
	assert(page.choose_code("PLANTING"))
	page.set_order_fields("Greenline Nursery", "Buxus", "10", "10.00")
	assert(page.order_hint() == "PLANTING has $150.00 of its budget left.", page.order_hint())
	page.set_order_fields("Greenline Nursery", "Buxus", "20", "10.00")
	assert(page.order_hint() == "PLANTING would be committed $200.00 against a budget of $150.00",
		page.order_hint())
	page.set_order_fields("Greenline Nursery", "Buxus", "", "10.00")
	assert(page.order_hint() == "A quantity of what is being ordered.", page.order_hint())
	page.set_order_fields("Greenline Nursery", "Buxus", "10", "")
	assert(page.order_hint().contains("A rate for it"), page.order_hint())
	page.free()


func test_ordering_from_the_page_writes_it_issues_it_and_says_what_it_did() -> void:
	var desk := _desk()
	var page := _page(desk)
	assert(page.choose_code("PLANTING"))
	page.set_order_fields("Greenline Nursery", "Buxus, 2 gal", "20", "10.00")
	var done: Dictionary = page.order_material()
	assert(bool(done["ok"]), String(done["reason"]))
	assert(String(done["warning"]).contains("$200.00 against a budget of $150.00"),
		String(done["warning"]))
	assert(page.status_text() == "PO-001 ordered: Buxus, 2 gal of PLANTING - PLANTING would be "
		+ "committed $200.00 against a budget of $150.00", page.status_text())
	assert(page.order_texts().size() == 1)
	assert(page.order_texts()[0].contains("committed $200.00"), page.order_texts()[0])
	assert(page.problem_texts().has("PLANTING is committed $200.00 against a budget of $150.00"),
		str(page.problem_texts()))
	var listed: ItemList = page.get_node(NodePath("Column/Problems"))
	assert(listed.item_count == 1)
	page.free()


func test_ordering_with_a_field_missing_says_which_and_writes_nothing() -> void:
	var desk := _desk()
	var page := _page(desk)
	assert(page.choose_code("HARDSCAPE"))
	page.set_order_fields("", "Paving stones", "20", "10.00")
	var refused: Dictionary = page.order_material()
	assert(not bool(refused["ok"]))
	assert(String(refused["reason"]) == "a purchase order needs a supplier", String(refused["reason"]))
	assert(desk.purchase_orders.is_empty(), "nothing was written")
	page.free()


func test_a_draft_row_can_be_issued_from_the_page() -> void:
	# An order for a phase the job was never sold is written and left as a draft: the page offers
	# issuing it, and issuing is refused by name.
	var desk := _desk()
	desk.make_purchase_order("E1", &"EXTRAS", "A thing nobody sold", 1000, MoneyScript.of(500),
		"Greenline Nursery")
	var page := _page(desk)
	assert(page.order_texts()[0].contains("draft, not ordered"), page.order_texts()[0])
	var row: Node = page.get_node(NodePath("Column/Orders/OrderPO-001"))
	assert(row != null, "the order has a row")
	assert(row.get_node_or_null(NodePath("Issueit")) != null, "and a button to issue it")
	var issued: Dictionary = page.issue_order("PO-001")
	assert(not bool(issued["ok"]))
	assert(page.status_text() == "PO-001 was not ordered: the job Smith, back garden has no EXTRAS "
		+ "in it to charge this to", page.status_text())
	assert(desk.purchase_order("PO-001").state() == &"DRAFT", "and it is still a draft")
	page.free()


func test_receiving_from_the_page_moves_the_money_from_committed_to_cost() -> void:
	var desk := _desk()
	var page := _page(desk)
	desk.make_purchase_order("E1", &"PLANTING", "Buxus", 10000, MoneyScript.of(1000), "Greenline")
	desk.issue_purchase_order("PO-001", "2026-06-01")
	page.refresh()
	var row: Node = page.get_node(NodePath("Column/Orders/OrderPO-001"))
	assert(row.get_node_or_null(NodePath("Receiveit")) != null)
	assert(row.get_node_or_null(NodePath("Closeit")) == null, "nothing has arrived to reconcile")
	var taken: Dictionary = page.receive_order("PO-001")
	assert(bool(taken["ok"]), String(taken["reason"]))
	assert(page.status_text() == "PO-001: what was ordered has arrived.", page.status_text())
	assert(page.order_texts()[0].contains("arrived $100.00"), page.order_texts()[0])
	assert(page.row_text("PLANTING").contains("$0.00  $100.00"), page.row_text("PLANTING"))
	var after: Node = page.get_node(NodePath("Column/Orders/OrderPO-001"))
	assert(after.get_node_or_null(NodePath("Closeit")) != null, "and now it can be reconciled")
	assert(bool(page.close_order("PO-001")))
	assert(page.status_text() == "PO-001 is closed and reconciled.", page.status_text())
	var closed: Node = page.get_node(NodePath("Column/Orders/OrderPO-001"))
	assert(closed.get_node_or_null(NodePath("Receiveit")) == null,
		"a closed order takes no receipts, so the page offers none")
	assert(page.order_texts()[0].contains("closed and reconciled"), page.order_texts()[0])
	page.free()


# --- change orders -----------------------------------------------------------------------------


func test_a_change_order_is_shown_and_agreed_from_the_page() -> void:
	var desk := _desk()
	desk.make_change_order("E1", &"SITE_CONDITION", "Remove a buried wall", MoneyScript.of(50000),
		&"HARDSCAPE")
	desk.propose_change("CO-001", "2026-06-20")
	var page := _page(desk)
	assert(page.change_texts().size() == 1)
	assert(page.change_texts()[0].contains("proposed"), page.change_texts()[0])
	assert(page.problem_texts().has("1 change order pending, $500.00 not yet agreed"),
		str(page.problem_texts()))
	assert(not page.total_text().contains("$1,050.00"), "it is not agreed yet")
	page.set_approver("Dana", "signed paper photo")
	var agreed: Dictionary = page.agree_change("CO-001")
	assert(bool(agreed["ok"]), String(agreed["reason"]))
	assert(page.status_text() == "CO-001 is agreed, and the contract sum has moved.", page.status_text())
	assert(page.total_text().contains("change orders agreed"), page.total_text())
	assert(page.total_text().contains("$500.00"), "the agreed change is in the breakdown")
	assert(page.change_texts()[0].contains("signed paper photo"), page.change_texts()[0])
	page.free()


func test_agreeing_needs_somebody_who_agreed() -> void:
	var desk := _desk()
	desk.make_change_order("E1", &"OTHER", "A thing", MoneyScript.of(10000), &"PLANTING")
	var page := _page(desk)
	page.set_approver("")
	var refused: Dictionary = page.agree_change("CO-001")
	assert(not bool(refused["ok"]))
	assert(String(refused["reason"]).contains("who agreed"), String(refused["reason"]))
	assert(page.status_text() == "CO-001 was not agreed: an approval says who agreed",
		page.status_text())
	assert(desk.change_order("CO-001").is_pending())
	page.free()


func test_declining_and_withdrawing_take_their_reason_from_the_why_field() -> void:
	var desk := _desk()
	desk.make_change_order("E1", &"CUSTOMER_REQUEST", "Add a path", MoneyScript.of(20000),
		&"HARDSCAPE")
	desk.make_change_order("E1", &"OTHER", "And another", MoneyScript.of(5000), &"PLANTING")
	var page := _page(desk)
	var no_why: Dictionary = page.void_change("CO-002")
	assert(not bool(no_why["ok"]), "a withdrawal says why")
	assert(String(no_why["reason"]).contains("says why"), String(no_why["reason"]))
	assert(not bool(page.decline_change("CO-001")["ok"]), "and so does a decline")
	assert(page.status_text().contains("a declined change order says why"), page.status_text())
	page.set_why("too expensive")
	assert(bool(page.decline_change("CO-001")["ok"]))
	assert(page.status_text() == "CO-001 was declined, and the reason is kept.", page.status_text())
	assert(page.change_texts()[0].contains("declined"), page.change_texts()[0])
	assert(bool(page.void_change("CO-002")["ok"]), "the why field is read by both")
	assert(page.status_text() == "CO-002 was withdrawn.", page.status_text())
	# A row with an answer behind it offers no more answers.
	var row: Node = page.get_node(NodePath("Column/Changes/ChangeCO-001"))
	assert(row.get_node_or_null(NodePath("Declineit")) == null)
	page.free()


func test_a_damaged_request_says_so_rather_than_failing() -> void:
	var desk := _desk()
	var page := _page(desk)
	var refused: Dictionary = page.agree_change("CO-404")
	assert(not bool(refused["ok"]))
	assert(page.status_text().contains("no change order CO-404"), page.status_text())
	assert(not bool(page.issue_order("PO-404")["ok"]))
	assert(not page.close_order("PO-404"))
	assert(not bool(page.receive_order("PO-404")["ok"]))
	assert(desk.purchase_orders.is_empty(), "and nothing was written by any of it")
	page.free()


# --- the small ones ----------------------------------------------------------------------------


func test_a_quantity_is_read_the_way_a_person_types_it() -> void:
	assert(WindowScript.parse_quantity("20") == 20000)
	assert(WindowScript.parse_quantity(" 2.5 ") == 2500)
	assert(WindowScript.parse_quantity("3,000") == 3000000)
	assert(WindowScript.parse_quantity("") == 0)
	assert(WindowScript.parse_quantity("twenty") == 0)
	assert(WindowScript.parse_quantity("2.5.5") == 0)