extends Node
## The board: columns per stage, a card per lead, and a drop into LOST that asks why (spec §9).
##
## The board owns no arithmetic - the funnel and the summary are the pipeline's own words - so these
## tests hold two things: that a card lands in the right column, and that the one interaction with
## weight on it (closing a lead as lost) cannot happen without the reason that report is made of.
##
## Each test frees the window it built, which is what the other window tests do: a `Window` is a tree
## with a viewport, and letting one live to engine exit is a leaked resource.

const BoardScript := preload("res://scripts/pipeline_board.gd")
const PipelineScript := preload("res://scripts/biz/pipeline.gd")
const LeadScript := preload("res://scripts/biz/lead.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")


func _board() -> BoardScript:
	var board: BoardScript = BoardScript.new()
	board.build()
	return board


func _card_node(board: BoardScript, stage: int, lead_id: String) -> Node:
	return board.get_node_or_null(NodePath("Column/Scroll/Board/Column%d/Card%s" % [stage, lead_id]))


# --- building --------------------------------------------------------------------------------


func test_the_board_builds_one_beside_the_other_for_every_stage() -> void:
	var board := _board()
	assert(board.column_titles() == ["Lead", "Qualified", "Site visit", "Estimating", "Proposed",
		"Won", "Lost", "Withdrawn", "Dormant"])
	# Terminal states keep a column of their own, which is what makes the win/loss visible.
	assert(board.card_count(LeadScript.WON) == 0)
	board.free()


func test_building_twice_is_the_same_board() -> void:
	var board := _board()
	board.add_lead("Smith", 100000)
	board.build()
	assert(board.card_count(LeadScript.LEAD) == 1, "a second build did not wipe the board")
	board.free()


func test_a_board_with_no_pipeline_is_empty_rather_than_broken() -> void:
	var board := _board()
	board.bind(null)
	assert(board.card_count(LeadScript.LEAD) == 0)
	assert(board.summary_text() == "no open leads")
	board.free()


# --- a card ----------------------------------------------------------------------------------


func test_adding_a_lead_puts_a_card_in_the_first_column() -> void:
	var board := _board()
	var added := board.add_lead("Smith, patio", 500000, &"referral")
	assert(added["ok"])
	assert(board.card_count(LeadScript.LEAD) == 1)
	assert(board.card_texts(LeadScript.LEAD) == ["Smith, patio\n5,000.00"])
	board.free()


func test_a_lead_with_no_name_is_refused() -> void:
	var board := _board()
	assert(not board.add_lead("   ", 100000)["ok"])
	assert(board.card_count(LeadScript.LEAD) == 0)
	board.free()


func test_a_card_carries_the_lead_it_stands_for() -> void:
	var board := _board()
	var id: String = board.add_lead("Nguyen", 250000)["id"]
	var card := _card_node(board, LeadScript.LEAD, id)
	assert(card != null, "the card is in the Lead column")
	var data = card._get_drag_data(Vector2.ZERO)
	assert(data is Dictionary and String(data["lead"]) == id, "a card drags its lead's id")
	board.free()


# --- moving ----------------------------------------------------------------------------------


func test_dropping_a_card_in_another_column_moves_the_lead() -> void:
	var board := _board()
	var id: String = board.add_lead("Smith", 100000)["id"]
	assert(board.move_lead(id, LeadScript.QUALIFIED)["ok"])
	assert(board.card_count(LeadScript.LEAD) == 0)
	assert(board.card_count(LeadScript.QUALIFIED) == 1)
	board.free()


func test_a_drop_into_lost_asks_for_the_reason_and_holds_the_card() -> void:
	var board := _board()
	var id: String = board.add_lead("Smith", 100000)["id"]
	var column := board.get_node_or_null(^"Column/Scroll/Board/Column6")
	assert(column._can_drop_data(Vector2.ZERO, {"lead": id}), "the Lost column accepts the card")
	column._drop_data(Vector2.ZERO, {"lead": id})
	# Held, not made: the lead is still where it was, and the board is asking.
	assert(board.card_count(LeadScript.QUALIFIED) == 0 and board.card_count(LeadScript.LOST) == 0)
	assert(board.is_asking_for_a_reason(), "the board is asking why")
	assert(board.pending_lead() == id and board.pending_stage() == LeadScript.LOST)
	assert(board.is_reason_row_visible(), "the reason field is shown")
	board.free()


func test_confirming_the_reason_closes_the_lead_as_lost() -> void:
	var board := _board()
	var id: String = board.add_lead("Smith", 100000)["id"]
	board.move_lead(id, LeadScript.LOST)
	board.confirm_move("price")
	assert(board.card_count(LeadScript.LOST) == 1)
	assert(not board.is_asking_for_a_reason())
	assert(board.pipeline.find(id).lost_reason == &"price")
	board.free()


func test_cancelling_puts_the_card_back_by_never_having_moved_it() -> void:
	var board := _board()
	var id: String = board.add_lead("Smith", 100000)["id"]
	board.move_lead(id, LeadScript.QUALIFIED)
	board.move_lead(id, LeadScript.LOST)  # held
	board.cancel_move()
	assert(board.card_count(LeadScript.QUALIFIED) == 1, "the lead is where it was")
	assert(board.card_count(LeadScript.LOST) == 0)
	assert(not board.is_asking_for_a_reason())
	board.free()


func test_confirming_with_nothing_pending_is_refused() -> void:
	var board := _board()
	board.add_lead("Smith", 100000)
	assert(not board.confirm_move("price")["ok"])
	board.free()


func test_moving_a_lead_that_is_not_on_the_board_is_refused() -> void:
	var board := _board()
	assert(not board.move_lead("nobody", LeadScript.QUALIFIED)["ok"])
	board.free()


func test_a_move_to_where_a_lead_already_is_is_refused() -> void:
	var board := _board()
	var id: String = board.add_lead("Smith", 100000)["id"]
	assert(not board.move_lead(id, LeadScript.LEAD)["ok"])
	board.free()


# --- what the board says ---------------------------------------------------------------------


func test_the_funnel_is_the_pipelines_own_numbers() -> void:
	var board := _board()
	board.add_lead("A", 100000)
	board.add_lead("B", 200000)
	board.add_lead("C", 300000)
	var texts := board.funnel_texts()
	assert(texts.size() == LeadScript.FUNNEL_ORDER.size())
	assert(texts[0] == "Lead 3 - 6,000.00", "the board showed a number it did not compute")
	board.free()


func test_the_summary_reports_the_open_pipeline_raw_and_weighted() -> void:
	var board := _board()
	var id: String = board.add_lead("Smith", 1000000)["id"]
	board.move_lead(id, LeadScript.PROPOSED)
	assert(board.summary_text() == "open: 1 leads worth 10,000.00, weighted 8,000.00")
	assert(board.status_text() == board.summary_text())
	board.free()


func test_the_board_formats_in_the_currency_it_was_given() -> void:
	var board: BoardScript = BoardScript.new()
	board.currency = &"JPY"
	board.build()
	board.add_lead("Yen", 150000)
	assert(board.card_texts(LeadScript.LEAD) == ["Yen\n150,000"], "yen has no minor unit")
	assert(board.pipeline.currency == &"JPY")
	board.free()


func test_every_button_on_the_board_is_focus_free() -> void:
	# The typed fields are the only things allowed the keyboard (spec §9).
	var board := _board()
	board.add_lead("Smith", 100000)
	assert(board.buttons_are_focus_free())
	board.free()


func test_a_moved_card_emits_the_change_so_the_menu_line_is_not_stale() -> void:
	var board := _board()
	var id: String = board.add_lead("Smith", 100000)["id"]
	var seen := [0]
	board.pipeline_changed.connect(func() -> void: seen[0] += 1)
	board.move_lead(id, LeadScript.QUALIFIED)
	assert(seen[0] == 1)
	board.move_lead(id, LeadScript.PROPOSED)
	assert(seen[0] == 2)
	board.free()
