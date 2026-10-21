extends Node
## The change order: a small estimate attached to a job, and the record of the customer agreeing to it
## (spec §8.2).
##
## Two properties carry the weight here. **Only an approved change order enters the contract sum**
## (REQ-B18), with the pending ones shown separately - a business that bills against a change the
## customer has not agreed to is a business in a dispute. And **an approval records who, when and how**
## (REQ-B13): "the customer said yes" is a claim that has to be supportable.

const ChangeScript := preload("res://scripts/biz/change_order.gd")
const EstimateScript := preload("res://scripts/biz/estimate.gd")
const LineScript := preload("res://scripts/biz/estimate_line.gd")
const ItemScript := preload("res://scripts/biz/cost_item.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")


func _line(code: StringName, units_milli: int, cost_cents: int, price_cents: int) -> LineScript:
	var line: LineScript = LineScript.new()
	line.description = "something the customer asked for"
	line.cost_code = code
	line.kind = ItemScript.MATERIAL
	line.quantity_milli = units_milli
	line.unit = &"EACH"
	line.unit_cost = MoneyScript.of(cost_cents)
	line.unit_price = MoneyScript.of(price_cents)
	return line


## A change order for job E1: 10 units at 150.00, costing 100.00.
func _change(order_id: String = "CO1") -> ChangeScript:
	var change: ChangeScript = ChangeScript.new(order_id)
	change.number = "CO-1"
	change.job = "E1"
	change.reason = &"SITE_CONDITION"
	change.add_line(_line(&"PLANTING", 10000, 1000, 1500))
	return change


func _approved() -> ChangeScript:
	var change := _change()
	change.propose("2026-06-20")
	change.send("2026-06-21")
	change.approve("Dana", "2026-07-01", "in-app")
	return change


# --- what it is worth ------------------------------------------------------------------------


func test_a_change_order_carries_an_estimate_and_the_estimate_prices_it() -> void:
	var change := _change()
	assert(change.line_count() == 1, "the lines are an estimate")
	assert(change.amount().format() == "150.00", change.amount().format())
	assert(change.cost().format() == "100.00", "and what the change costs is carried too")


func test_the_lines_go_in_through_the_estimates_own_engine_and_its_refusals() -> void:
	var change := _change()
	var blank: LineScript = LineScript.new()
	blank.quantity_milli = 1000
	blank.unit = &"EACH"
	blank.unit_cost = MoneyScript.of(100)
	blank.unit_price = MoneyScript.of(150)
	assert(not change.add_line(blank), "a line with no description is refused by the estimate")
	assert(change.line_count() == 1)
	assert(change.add_line(_line(&"HARDSCAPE", 1000, 500, 900)))
	assert(change.line_count() == 2)
	assert(change.amount().format() == "159.00", change.amount().format())


func test_the_change_is_worth_so_much_per_cost_code() -> void:
	var change := _change()
	change.add_line(_line(&"HARDSCAPE", 1000, 500, 900))
	var amounts: Dictionary = change.code_amounts()
	assert((amounts["PLANTING"] as MoneyScript).format() == "150.00")
	assert((amounts["HARDSCAPE"] as MoneyScript).format() == "9.00")
	assert((amounts as Dictionary).size() == 2)


func test_the_amount_is_signed_because_a_credit_is_a_change_too() -> void:
	var change := _change()
	assert(change.amount_text() == "+$150.00", change.amount_text())
	var credit: ChangeScript = ChangeScript.new("CO2")
	credit.add_line(_line(&"PLANTING", 2000, 100, -410))
	assert(credit.amount_text() == "-$8.20", credit.amount_text())
	assert(credit.cost().format() == "2.00", "a credit that costs money is a credit worth knowing about")


# --- the reason, the state, the approval -------------------------------------------------------


func test_the_reason_comes_from_the_short_list() -> void:
	assert(ChangeScript.is_reason(&"SITE_CONDITION"))
	assert(ChangeScript.is_reason(&"ERROR_AND_OMISSION"))
	assert(not ChangeScript.is_reason(&"BECAUSE_IT_IS_FRIDAY"))
	assert(ChangeScript.reason_name(&"SITE_CONDITION") == "site condition")
	assert(ChangeScript.reason_name(&"CODE_OR_PERMIT") == "code or permit")
	assert(ChangeScript.reason_name(&"SOMETHING_ELSE") == "other")


func test_it_starts_proposed_and_needs_a_moment_to_be_proposed() -> void:
	var change := _change()
	assert(change.state() == ChangeScript.PROPOSED)
	assert(change.state_name() == "proposed")
	assert(change.is_pending(), "it is waiting for an answer from the moment it exists")
	assert(not change.propose(""), "a proposed change order says when")
	assert(change.propose("2026-06-20"))
	assert(change.proposed_at == "2026-06-20")
	assert(not change.propose("2026-06-22"), "and it is proposed once")


func test_only_a_proposed_one_can_go_out() -> void:
	var change := _change()
	assert(not change.send("2026-06-21"), "not before it is proposed")
	assert(change.propose("2026-06-20"))
	assert(not change.send(""))
	assert(change.send("2026-06-21"))
	assert(change.state() == ChangeScript.SENT)
	assert(change.state_name() == "sent, not yet answered")
	assert(not change.send("2026-06-22"), "it is out already")


func test_an_approval_records_who_when_and_how() -> void:
	var change := _change()
	change.propose("2026-06-20")
	change.send("2026-06-21")
	assert(String(change.approve("", "2026-07-01", "in-app")["reason"]).contains("who agreed"))
	assert(String(change.approve("Dana", "", "in-app")["reason"]).contains("says when"))
	assert(String(change.approve("Dana", "2026-07-01", "")["reason"]).contains("says how"))
	assert(String(change.approve("Dana", "2026-07-01", "a handshake")["reason"]).contains("says how"))
	assert(change.state() == ChangeScript.SENT, "and none of that agreed anything")
	var done: Dictionary = change.approve("Dana", "2026-07-01", "signed paper photo", "user://sig.png")
	assert(bool(done["ok"]), String(done["reason"]))
	assert(change.state() == ChangeScript.APPROVED)
	assert(change.state_name() == "approved")
	assert(change.is_approved())
	assert(change.approved_signature == "user://sig.png")
	assert(change.approval_text() == "approved by Dana on 2026-07-01 (signed paper photo)",
		change.approval_text())


func test_nothing_to_approve_is_refused() -> void:
	var change: ChangeScript = ChangeScript.new("CO9")
	var empty: Dictionary = change.approve("Dana", "2026-07-01", "in-app")
	assert(not bool(empty["ok"]), "there is nothing on it")
	assert(String(empty["reason"]).contains("nothing on it"))


func test_an_answered_change_order_is_not_a_question_any_more() -> void:
	var change := _approved()
	assert(String(change.approve("Dana", "2026-07-02", "in-app")["reason"]).contains("not a question"))
	assert(not bool(change.decline("Dana", "2026-07-02", "changed their mind")["ok"]))
	assert(change.state() == ChangeScript.APPROVED, "and it is still approved")


func test_a_decline_says_why() -> void:
	var change := _change()
	change.propose("2026-06-20")
	assert(not bool(change.decline("Dana", "2026-06-25", "")["ok"]), "a decline says why")
	assert(change.state() == ChangeScript.PROPOSED)
	assert(bool(change.decline("Dana", "2026-06-25", "too expensive")["ok"]))
	assert(change.state() == ChangeScript.DECLINED)
	assert(change.declined_by == "Dana")
	assert(change.declined_why == "too expensive")
	assert(not change.is_pending())


func test_an_approved_change_order_is_a_contract_document_and_cannot_be_voided() -> void:
	var approved := _approved()
	var refused: Dictionary = approved.mark_void("2026-07-02", "wrong price")
	assert(not bool(refused["ok"]))
	assert(String(refused["reason"]).contains("contract document"), String(refused["reason"]))
	assert(approved.state() == ChangeScript.APPROVED)
	var waiting := _change("CO2")
	waiting.propose("2026-06-20")
	assert(not bool(waiting.mark_void("2026-06-22", "")["ok"]), "a void says why")
	assert(bool(waiting.mark_void("2026-06-22", "the customer withdrew it")["ok"]))
	assert(waiting.state() == ChangeScript.VOID)
	assert(waiting.state_name() == "void")
	assert(not bool(waiting.mark_void("2026-06-23", "again")["ok"]), "it is already void")


# --- REQ-B18: only an approved one is money ---------------------------------------------------


func test_only_an_approved_change_order_enters_the_contract_sum() -> void:
	var waiting := _change()
	assert(not waiting.enters_contract_sum(), "proposed is not agreed")
	waiting.propose("2026-06-20")
	assert(not waiting.enters_contract_sum(), "sent is still not agreed")
	var approved := _approved()
	assert(approved.enters_contract_sum())


func test_an_approved_change_that_says_it_does_not_affect_the_sum_does_not() -> void:
	var change := _approved()
	change.affects_contract_sum = false
	assert(change.is_approved())
	assert(not change.enters_contract_sum(), "agreed, and worth nothing to the contract")
	assert(change.describe().contains("does not change the contract sum"), change.describe())


func test_what_is_pending_is_a_proposed_or_a_sent_change_and_nothing_else() -> void:
	var proposed := _change("CO1")
	assert(proposed.is_pending())
	var sent := _change("CO2")
	sent.propose("2026-06-20")
	sent.send("2026-06-21")
	assert(sent.is_pending())
	assert(not _approved().is_pending(), "approved has been answered")
	var declined := _change("CO3")
	declined.propose("2026-06-20")
	declined.decline("Dana", "2026-06-25", "no")
	assert(not declined.is_pending())
	var voided := _change("CO4")
	voided.propose("2026-06-20")
	voided.mark_void("2026-06-22", "withdrawn")
	assert(not voided.is_pending())


# --- what is wrong with it ------------------------------------------------------------------


func test_a_record_that_says_approved_with_no_approval_is_not_approved() -> void:
	var hand_made: ChangeScript = ChangeScript.from_dict({
		"id": "CO7", "reason": "SITE_CONDITION", "state": "APPROVED",
		"estimate": _change().estimate.to_dict(),
	})
	assert(not hand_made.is_approved(), "an approval is the record of it, not a word in the file")
	assert(not hand_made.enters_contract_sum(), "and it adds nothing to the contract sum")
	assert(hand_made.is_pending(), "it is still waiting for an answer")


func test_an_approval_with_no_record_of_who_agreed_is_a_fault() -> void:
	var hand_made: ChangeScript = ChangeScript.from_dict({
		"id": "CO7", "reason": "SITE_CONDITION", "approved_at": "2026-07-01",
		"estimate": _change().estimate.to_dict(),
	})
	assert(hand_made.is_approved(), "the date of an agreement is an agreement")
	assert(hand_made.problems()[0].contains("no record of who agreed"), str(hand_made.problems()))


func test_a_reason_nobody_has_is_a_fault_on_a_record_that_did_not_come_from_here() -> void:
	var change := _change()
	change.reason = &"BECAUSE"
	assert(change.problems()[0].contains("not one of the six"), str(change.problems()))
	assert(not change.is_sound())


func test_a_change_order_with_no_id_is_a_fault() -> void:
	var bare: ChangeScript = ChangeScript.new("")
	assert(bare.problems()[0].contains("needs an id"), str(bare.problems()))


func test_describe_reads_as_a_change_order() -> void:
	var change := _approved()
	assert(change.describe() == "CO-1 site condition, +$150.00, approved by Dana on 2026-07-01 "
		+ "(in-app) (E1)", change.describe())
	var waiting := _change("CO2")
	assert(waiting.describe().contains(", proposed (E1)"), waiting.describe())


# --- the file -----------------------------------------------------------------------------------


func test_it_survives_the_file() -> void:
	var change := _approved()
	var text := JSON.stringify(change.to_dict())
	var restored: ChangeScript = ChangeScript.from_dict(JSON.parse_string(text))
	assert(restored.id == "CO1")
	assert(restored.number == "CO-1")
	assert(restored.job == "E1")
	assert(String(restored.reason) == "SITE_CONDITION")
	assert(restored.state() == ChangeScript.APPROVED)
	assert(restored.approved_by == "Dana")
	assert(restored.approved_at == "2026-07-01")
	assert(restored.approved_how == "in-app")
	assert(restored.proposed_at == "2026-06-20")
	assert(restored.sent_at == "2026-06-21")
	assert(restored.line_count() == 1, "the lines travelled")
	assert(restored.amount().format() == "150.00", restored.amount().format())
	assert(restored.enters_contract_sum())
	assert(restored.describe() == change.describe(), restored.describe())


func test_a_damaged_record_never_invents_an_agreement() -> void:
	assert(ChangeScript.from_dict({}) == null, "a record with no id is dropped")
	var read: ChangeScript = ChangeScript.from_dict({
		"id": "CO8", "reason": "MAYBE", "state": "SIGNED_OFF", "affects_contract_sum": false,
	})
	assert(String(read.reason) == "OTHER", "a reason nobody has becomes other")
	assert(read.state() == ChangeScript.PROPOSED, "a state nobody has is not an agreement")
	assert(not read.affects_contract_sum)
	assert(not read.enters_contract_sum())