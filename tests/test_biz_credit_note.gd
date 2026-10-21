extends Node
## Credit notes: the document a refund is, and the exact mirror of the charge it reverses (spec §9.4).
##
## Three properties are under test. **A refund is a credit note, not a negative payment** - the amount
## is a positive document, and the setters refuse anything else. **A credit note that reverses a charge
## is that charge to the cent**, which `Money`'s single rounding rule makes a fact. And **it is never
## edited after issue, and a void keeps its number**, exactly as an invoice is not.

const CreditScript := preload("res://scripts/biz/credit_note.gd")
const InvoiceScript := preload("res://scripts/biz/invoice.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")


func _invoice() -> InvoiceScript:
	var invoice: InvoiceScript = InvoiceScript.new("INV1")
	invoice.job = "J1"
	invoice.customer = {"name": "Smith", "city": "Ottawa"}
	invoice.add_amount(InvoiceScript.MILESTONE_LINE, "Deposit", MoneyScript.of(50000), &"HARDSCAPE", &"NONE")
	invoice.set_retainage(MoneyScript.of(5000))
	assert(bool(invoice.issue("2026-06-01", 30, "INV-2026-0001")["ok"]))
	return invoice


func _note() -> CreditScript:
	var note: CreditScript = CreditScript.new("CN1")
	note.job = "J1"
	note.customer = {"name": "Smith"}
	assert(note.set_amount(MoneyScript.of(45000)))
	assert(note.set_against("INV-2026-0001", "the paving was overbilled"))
	return note


func _issued() -> CreditScript:
	var note := _note()
	assert(bool(note.issue("2026-06-20", "CN-2026-0001")["ok"]))
	return note


# --- what a credit note is ----------------------------------------------------------------------


func test_a_credit_note_is_the_exact_mirror_of_the_invoice_it_reverses() -> void:
	var invoice := _invoice()
	var note: CreditScript = CreditScript.mirror_of(invoice, "2026-06-20", "CN-2026-0001", "customer cancelled the second phase")
	assert(note != null)
	# The invoice total is 500.00 + no tax - 50.00 retained = 450.00, and the mirror is that to the cent.
	assert(note.amount.cents == invoice.total().cents, str(note.amount.cents))
	assert(note.amount.cents == 45000)
	assert(note.against == "INV-2026-0001")
	assert(note.job == "J1")
	assert(note.customer["name"] == "Smith")
	assert(note.issued_at == "2026-06-20")
	assert(note.number == "CN-2026-0001")
	assert(note.is_issued())
	assert(note.reason.contains("second phase"))


func test_a_note_is_issued_by_its_mirror_and_an_unnumbered_one_is_not_a_mirror_at_all() -> void:
	var invoice := _invoice()
	assert(CreditScript.mirror_of(invoice, "2026-06-20", "") == null)
	# An invoice that never went out has nothing to reverse, and an unreadable total is not a mirror.
	var draft: InvoiceScript = InvoiceScript.new("INV2")
	draft.job = "J1"
	draft.add_amount(InvoiceScript.MILESTONE_LINE, "Deposit", MoneyScript.of(100), &"", &"NONE")
	assert(CreditScript.mirror_of(draft, "2026-06-20", "CN-2026-0001") == null)


func test_mirroring_a_voided_invoice_gives_nothing_because_there_is_nothing_to_reverse() -> void:
	var invoice := _invoice()
	assert(invoice.mark_void("2026-06-15", "the address was wrong"))
	assert(CreditScript.mirror_of(invoice, "2026-06-20", "CN-2026-0001") == null)


# --- stating it: the amount is positive and the invoice is named ---------------------------------


func test_a_credit_note_cannot_be_a_negative_or_a_zero_amount() -> void:
	var note: CreditScript = CreditScript.new("CN1")
	# A negative amount here would be writing the refund as a payment again under another name, which
	# is the whole reason this document exists.
	assert(not note.set_amount(MoneyScript.of(-45000)))
	assert(not note.set_amount(MoneyScript.zero()))
	assert(not note.set_amount(MoneyScript.invalid()))
	assert(not note.set_amount(MoneyScript.of(45000, &"USD")))
	assert(note.amount.cents == 0)


func test_a_credit_note_that_credits_no_invoice_is_not_sound() -> void:
	var note: CreditScript = CreditScript.new("CN1")
	note.job = "J1"
	assert(note.set_amount(MoneyScript.of(45000)))
	note.reason = "a reason"
	var problems: Array[String] = note.problems()
	assert(problems.size() == 1, str(problems))
	assert(problems[0].contains("credits no invoice"), problems[0])
	assert(not note.is_sound())
	assert(not bool(note.issue("2026-06-20", "CN-2026-0001")["ok"]))


func test_a_credit_note_nobody_explained_cannot_be_issued() -> void:
	var note: CreditScript = CreditScript.new("CN1")
	note.job = "J1"
	assert(note.set_amount(MoneyScript.of(45000)))
	assert(not note.set_against("", "why"))
	assert(not note.set_against("INV-2026-0001", ""))
	note.against = "INV-2026-0001"
	var issued: Dictionary = note.issue("2026-06-20", "CN-2026-0001")
	assert(not bool(issued["ok"]))
	assert(String(issued["reason"]).contains("explained"), String(issued["reason"]))
	# A record can be wrong in ways its own setters refuse, which is what `problems` is for.
	note.reason = ""
	assert(note.problems().size() == 1)


func test_an_empty_note_cannot_be_issued_and_a_row_that_is_not_a_note_is_dropped() -> void:
	var note: CreditScript = CreditScript.new("CN1")
	assert(not bool(note.issue("2026-06-20", "CN-2026-0001")["ok"]))
	assert(CreditScript.from_dict({}) == null)
	assert(CreditScript.from_dict({"id": ""}) == null)
	var back: CreditScript = CreditScript.from_dict({"id": "CN1", "amount": {"cents": 45000, "currency": "CAD"}})
	assert(back != null)
	assert(back.amount.cents == 45000)


# --- issuing, editing, voiding ------------------------------------------------------------------


func test_an_issued_note_is_never_edited_and_a_void_keeps_its_number() -> void:
	var note := _issued()
	assert(not note.is_editable())
	assert(not note.set_amount(MoneyScript.of(1)))
	var again: Dictionary = note.issue("2026-07-01", "CN-2026-0002")
	assert(not again["ok"])
	assert(String(again["reason"]).contains("never edited"), String(again["reason"]))
	assert(note.mark_void("2026-06-25", "issued to the wrong customer"))
	assert(note.number == "CN-2026-0001")
	assert(note.voided_text().contains("wrong customer"), note.voided_text())
	assert(note.state() == CreditScript.VOID)
	# A voided note is not issued again under the same number.
	assert(not bool(note.issue("2026-07-01", "CN-2026-0002")["ok"]))
	# A draft is not voided - it has no number to keep.
	var draft: CreditScript = _note()
	assert(not draft.mark_void("2026-06-25", "never mind"))


func test_issuing_needs_a_date_and_a_number_that_read() -> void:
	var note := _note()
	assert(not bool(note.issue("not a date", "CN-2026-0001")["ok"]))
	assert(not bool(note.issue("2026-06-20", "")["ok"]))
	assert(not note.is_issued())


func test_the_state_is_a_function_of_the_records_and_not_a_field() -> void:
	var note := _issued()
	var row: Dictionary = note.to_dict()
	assert(String(row["state"]) == "issued")
	# A file that claims a state the records do not support does not make it so.
	row["state"] = "void"
	var back: CreditScript = CreditScript.from_dict(row)
	assert(back != null)
	assert(back.state() == CreditScript.ISSUED)
	assert(back.state_name() == "issued")


func test_a_note_survives_the_file_with_its_number_and_its_reason() -> void:
	var note := _issued()
	var back: CreditScript = CreditScript.from_dict(note.to_dict())
	assert(back != null)
	assert(back.id == "CN1")
	assert(back.number == "CN-2026-0001")
	assert(back.against == "INV-2026-0001")
	assert(back.amount.cents == 45000)
	assert(back.issued_at == "2026-06-20")
	assert(back.reason == note.reason)
	assert(back.is_sound())


# --- numbering, by the same rule an invoice uses ------------------------------------------------


func test_the_number_is_the_highest_taken_and_never_the_count() -> void:
	# Three taken with a gap where the second was: a count would hand out CN-2026-0003 twice.
	assert(CreditScript.next_number(2026, ["CN-2026-0001", "CN-2026-0003"]) == "CN-2026-0004")
	assert(CreditScript.next_number(2026, []) == "CN-2026-0001")
	assert(CreditScript.next_number(2026, ["INV-2026-0009"]) == "CN-2026-0001")
	assert(CreditScript.next_number(2025, ["CN-2026-0003"]) == "CN-2025-0001")
	assert(CreditScript.sequence_of("CN-2026-0003") == 3)
	assert(CreditScript.sequence_of("INV-2026-0003") == -1)
	assert(CreditScript.sequence_of("rubbish") == -1)
	assert(CreditScript.year_of("CN-2026-0003") == 2026)
	assert(CreditScript.year_of("rubbish") == 0)


func test_describe_reads_as_a_credit_note() -> void:
	var note := _issued()
	var text: String = note.describe()
	assert(text == "CN-2026-0001, $450.00, against INV-2026-0001, the paving was overbilled, issued, 2026-06-20", text)
	var draft: CreditScript = CreditScript.new("CN2")
	draft.amount = MoneyScript.invalid()
	assert(draft.describe().contains("unnumbered draft"), draft.describe())