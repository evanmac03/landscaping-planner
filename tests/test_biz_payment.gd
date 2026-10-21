extends Node
## A payment: money that arrived, against one invoice (spec §4.12, §9.4).
##
## The property under test is the one §9.4 states as a refusal: **a refund is a credit note, not a
## negative payment**. A record that can hold a minus amount can write off a balance without anything
## having been said about why, which is the shape of every small-business fraud story.

const PaymentScript := preload("res://scripts/biz/payment.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")


func _payment(amount_cents: int = 50000) -> PaymentScript:
	var payment: PaymentScript = PaymentScript.new("PAY1")
	payment.invoice = "INV1"
	payment.received_at = "2026-06-01"
	payment.amount = MoneyScript.of(amount_cents)
	return payment


func test_a_stated_payment_is_sound_and_reads_as_one_line() -> void:
	var payment := _payment()
	payment.reference = "chq 1041"
	assert(payment.is_sound())
	assert(payment.describe() == "$500.00 by cheque, on 2026-06-01, reference chq 1041", payment.describe())


func test_the_money_has_to_have_come_by_a_way_a_business_has() -> void:
	assert(PaymentScript.METHODS.size() == 6)
	assert(PaymentScript.is_method(&"e-transfer"))
	assert(not PaymentScript.is_method(&"bitcoin"))
	assert(PaymentScript.method_name(&"transfer") == "bank transfer")
	assert(PaymentScript.method_name(&"bitcoin") == "other")
	var payment := _payment()
	payment.method = &"bitcoin"
	assert(not payment.is_sound())
	assert(payment.problem() == "a method nobody has: 'bitcoin'", payment.problem())


func test_a_refund_is_a_credit_note_and_not_a_negative_payment() -> void:
	var payment := _payment(-50000)
	assert(not payment.is_sound())
	assert(payment.problem() == "a negative payment, which is a credit note and not a payment",
		payment.problem())


func test_a_payment_of_nothing_is_not_a_payment() -> void:
	var payment := _payment(0)
	assert(not payment.is_sound())
	assert(payment.problem() == "a payment of nothing", payment.problem())


func test_a_payment_that_cannot_be_named_or_dated_is_not_a_record() -> void:
	var payment := _payment()
	payment.id = ""
	assert(payment.problem() == "a payment with no id", payment.problem())
	payment = _payment()
	payment.invoice = ""
	assert(payment.problem() == "a payment that names no invoice", payment.problem())
	payment = _payment()
	payment.received_at = ""
	assert(payment.problem() == "a payment with no date", payment.problem())
	payment = _payment()
	payment.amount = MoneyScript.invalid()
	assert(payment.problem() == "an amount that is not a readable number", payment.problem())


func test_a_damaged_describe_is_the_reason_rather_than_a_line_a_person_reads_as_fine() -> void:
	var payment := _payment(-1)
	assert(payment.describe() == "a negative payment, which is a credit note and not a payment",
		payment.describe())


func test_a_payment_survives_the_file() -> void:
	var payment := _payment(123456)
	payment.method = &"card"
	payment.note = "deposit"
	var back: PaymentScript = PaymentScript.from_dict(payment.to_dict())
	assert(back.id == payment.id)
	assert(back.invoice == "INV1")
	assert(back.received_at == "2026-06-01")
	assert(back.amount.cents == 123456)
	assert(back.method == &"card")
	assert(back.note == "deposit")
	assert(back.is_sound())


func test_a_record_with_no_id_is_dropped_rather_than_invented() -> void:
	assert(PaymentScript.from_dict({"invoice": "INV1", "amount": {"cents": 100, "currency": "CAD"}}) == null)