extends Node
## The outbox: what is queued, what has gone, what the queue has given up on, and what does not agree
## (REQ-B14, AC-B15, spec §9.6-§9.7).
##
## The properties under test, in the order the file takes them. **A document is queued once however
## often it is offered** - the key is the identity, which is AC-B15. **A build that refuses is returned
## as it stands and nothing is queued**, because a document that could not be posted must not look
## queued. **The request is built at queue time and never rebuilt.** **Posting is one place, and posting
## twice is not posting twice.** **The loop sends what the queue still owns and leaves a refusal alone.**
## **A credential is not written into the outbox file.** And **reconciliation reports without changing
## anything**, which is the only way a program may touch an accounting record.

const LedgerDeskScript := preload("res://scripts/biz/ledger_desk.gd")
const AdapterScript := preload("res://scripts/biz/ledger_adapter.gd")
const FileLedgerScript := preload("res://scripts/biz/file_ledger.gd")
const NinjaScript := preload("res://scripts/biz/invoice_ninja.gd")
const AkauntingScript := preload("res://scripts/biz/akaunting.gd")
const BillingDeskScript := preload("res://scripts/biz/billing_desk.gd")
const PushScript := preload("res://scripts/biz/ledger_push.gd")
const InvoiceScript := preload("res://scripts/biz/invoice.gd")
const PaymentScript := preload("res://scripts/biz/payment.gd")
const CreditScript := preload("res://scripts/biz/credit_note.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")

const TEST_FOLDER := "user://test_ledger_desk"
const CLIENT := "Wpmbk5ezJn"


# --- fixtures -----------------------------------------------------------------------------------


## A desk pointed at a throwaway folder, emptied first so one test's files are never another's. The
## folder is made rather than merely emptied, because a test that writes its own file needs it to exist.
func _desk(adapter_name: String = "") -> LedgerDeskScript:
	DirAccess.make_dir_recursive_absolute(TEST_FOLDER)
	_wipe(TEST_FOLDER)
	var desk: LedgerDeskScript = LedgerDeskScript.new()
	desk.chosen_adapter().set_setting(&"folder", TEST_FOLDER)
	if not adapter_name.is_empty():
		desk.choose(adapter_name)
	return desk


func _wipe(folder: String) -> void:
	var at: DirAccess = DirAccess.open(folder)
	if at == null:
		return
	for file_name in at.get_files():
		at.remove(file_name)


func _invoice(number: String = "INV-2026-0001", client: String = CLIENT) -> InvoiceScript:
	var invoice: InvoiceScript = InvoiceScript.new("INV-%s" % number)
	invoice.job = "J1"
	invoice.customer = {"name": "Smith", "external_id": client}
	invoice.add_line(InvoiceScript.MILESTONE_LINE, "Deposit", 1000, &"EACH",
		MoneyScript.of(53550), &"HARDSCAPE", &"HST-ON")
	assert(bool(invoice.issue("2026-06-10", 30, number)["ok"]))
	return invoice


func _payment(invoice: InvoiceScript) -> PaymentScript:
	var payment: PaymentScript = PaymentScript.new("PMT-0001")
	payment.invoice = invoice.id
	payment.received_at = "2026-06-20"
	payment.amount = MoneyScript.of(53550)
	payment.bank_reference = "chq 1041"
	return payment


## Make a queued push look as though a ledger answered it, without a network: the real parser reads the
## real response shape, so what the push records is what it would record.
func _answered(push: PushScript, status: int, body: Dictionary, at: String = "2026-06-12") -> bool:
	var response: Dictionary = {"status": status, "body": body}
	return push.record_response(response, AdapterScript.new().parse_common(response), at)


func _key_for(desk: LedgerDeskScript, invoice: InvoiceScript, adapter_name: String = "") -> String:
	var backend: AdapterScript = desk.adapter(adapter_name) if not adapter_name.is_empty() \
		else desk.chosen_adapter()
	return backend.key_for_invoice(invoice)


# --- the backends this desk can post to ---------------------------------------------------------


func test_a_new_desk_holds_the_file_ledger_because_it_always_works() -> void:
	var desk: LedgerDeskScript = LedgerDeskScript.new()
	var only_file: Array[String] = ["file"]
	assert(desk.adapter_names() == only_file, str(desk.adapter_names()))
	assert(desk.chosen == LedgerDeskScript.DEFAULT_ADAPTER)
	assert(desk.chosen_adapter() != null)
	assert(desk.chosen_adapter().is_configured())
	assert(desk.count() == 0)
	assert(desk.describe() == "the file ledger: nothing has been handed to a ledger")


func test_a_backend_with_no_name_cannot_be_registered() -> void:
	var desk := _desk()
	# The base adapter names nothing, so it could not be chosen and a push to it could not be read back.
	assert(not desk.add_adapter(AdapterScript.new()))
	assert(not desk.has_adapter(""))
	assert(desk.adapter_names().size() == 1)


func test_a_backend_cannot_be_registered_twice() -> void:
	var desk := _desk()
	assert(not desk.add_adapter(FileLedgerScript.new("user://somewhere_else")))
	assert(desk.adapter_names().size() == 1)
	# Two of the same name would make a push's own record ambiguous about where the document went.
	assert(desk.add_adapter(NinjaScript.new("https://ninja.example.test", "token")))
	assert(not desk.add_adapter(NinjaScript.new("https://other.example.test", "token")))
	var both: Array[String] = ["file", "invoice_ninja"]
	assert(desk.adapter_names() == both, str(desk.adapter_names()))


func test_choosing_a_backend_the_desk_does_not_have_is_refused() -> void:
	var desk := _desk()
	assert(desk.choose("invoice_ninja") == false)
	# Refused rather than kept, so a page cannot believe it is posting to the office's accounting
	# system while writing files into a folder.
	assert(desk.chosen == "file")
	desk.add_adapter(NinjaScript.new("https://ninja.example.test", "token"))
	assert(desk.choose("invoice_ninja"))
	assert(desk.chosen_adapter().name() == &"invoice_ninja")
	assert(desk.adapter("file") != null)
	assert(desk.adapter("nothing") == null)


# --- what is queued -----------------------------------------------------------------------------


func test_an_invoice_is_built_once_and_held() -> void:
	var desk := _desk()
	var invoice := _invoice()
	var queued: Dictionary = desk.queue_invoice(invoice)
	assert(bool(queued["ok"]), String(queued["reason"]))
	assert(not bool(queued["already"]))
	var push: PushScript = queued["push"]
	assert(push.state_name() == "queued")
	assert(push.attempts == 0)
	assert(String(push.request["method"]) == "WRITE")
	assert(String(push.request["url"]).begins_with(TEST_FOLDER), String(push.request["url"]))
	# The body is the invoice's own document, figures and all, because the outbox never recomputes money.
	assert(int(push.request["body"]["total"]["cents"]) == invoice.total().cents)
	assert(desk.count() == 1)
	assert(desk.pending().size() == 1)
	assert(desk.push_for(push.key) == push)


func test_queueing_the_same_invoice_again_is_the_same_push() -> void:
	var desk := _desk()
	var invoice := _invoice()
	var first: Dictionary = desk.queue_invoice(invoice)
	var second: Dictionary = desk.queue_invoice(invoice)
	assert(bool(second["ok"]))
	# AC-B15: the key is the identity, so a second offer is a retry rather than a second posting.
	assert(bool(second["already"]))
	assert(second["push"] == first["push"])
	assert(desk.count() == 1)


func test_a_draft_invoice_with_no_number_is_refused_in_the_backends_words() -> void:
	var desk := _desk()
	var draft: InvoiceScript = InvoiceScript.new("INV-1")
	draft.job = "J1"
	draft.add_line(InvoiceScript.MILESTONE_LINE, "Deposit", 1000, &"EACH",
		MoneyScript.of(1000), &"HARDSCAPE", &"NONE")
	assert(not draft.is_issued())
	var queued: Dictionary = desk.queue_invoice(draft)
	assert(not bool(queued["ok"]))
	assert(String(queued["reason"]).contains("issue it first"), String(queued["reason"]))
	assert(desk.count() == 0)


func test_a_document_a_backend_cannot_post_is_refused_by_name_and_nothing_is_queued() -> void:
	var desk := _desk()
	desk.add_adapter(NinjaScript.new("https://ninja.example.test", "token"))
	var credit: CreditNote = CreditScript.mirror_of(_invoice(), "2026-07-01", "CN-2026-0001", "called back")
	assert(credit != null)
	var queued: Dictionary = desk.queue_credit(credit, "invoice_ninja")
	assert(not bool(queued["ok"]))
	# AC-B14: the capability is a property, and a path a backend cannot do refuses rather than dropping.
	assert(String(queued["reason"]).contains("cannot post credit notes"), String(queued["reason"]))
	assert(desk.count() == 0)


func test_a_document_the_backend_cannot_build_is_refused_and_nothing_is_queued() -> void:
	var desk := _desk()
	desk.add_adapter(NinjaScript.new("https://ninja.example.test", "token"))
	var queued: Dictionary = desk.queue_invoice(_invoice("INV-2026-0001", ""), "invoice_ninja")
	assert(not bool(queued["ok"]))
	assert(String(queued["reason"]).contains("no id in Invoice Ninja"), String(queued["reason"]))
	assert(desk.count() == 0)
	assert(desk.pending().is_empty())


func test_a_credit_note_is_queued_on_a_backend_that_has_a_credit_path() -> void:
	var desk := _desk()
	var credit: CreditNote = CreditScript.mirror_of(_invoice(), "2026-07-01", "CN-2026-0001", "called back")
	var queued: Dictionary = desk.queue_credit(credit)
	assert(bool(queued["ok"]), String(queued["reason"]))
	assert(String(queued["push"].kind) == "credit")
	assert(queued["push"].document_number == "CN-2026-0001")
	assert(desk.count() == 1)


func test_a_payment_reads_the_invoices_id_in_the_ledger_off_its_own_push() -> void:
	var desk := _desk()
	var ninja: NinjaScript = NinjaScript.new("https://ninja.example.test", "token")
	desk.add_adapter(ninja)
	var invoice := _invoice()
	var queued: Dictionary = desk.queue_invoice(invoice, "invoice_ninja")
	var push: PushScript = queued["push"]
	# The ledger takes it and hands back its own id for the invoice.
	var answered: Dictionary = {"status": 200, "body": {"data": {"id": "42", "number": "INV-2026-0001"}}}
	assert(push.record_response(answered, ninja.parse_invoice_response(answered), "2026-06-11"))
	assert(push.external_id == "42")
	var paid: Dictionary = desk.queue_payment(_payment(invoice), invoice, "invoice_ninja")
	assert(bool(paid["ok"]), String(paid["reason"]))
	# The payment names the id the ledger assigned, read from the push that got it - which is the whole
	# reason the outbox records it.
	assert(String(paid["push"].request["body"]["invoices"][0]["invoice_id"]) == "42")


func test_a_payment_names_an_id_the_office_states_when_the_invoice_has_not_been_posted() -> void:
	var desk := _desk()
	desk.add_adapter(NinjaScript.new("https://ninja.example.test", "token"))
	var invoice := _invoice()
	desk.queue_invoice(invoice, "invoice_ninja")
	var paid: Dictionary = desk.queue_payment(_payment(invoice), invoice, "invoice_ninja",
		"2026-06-20", "  the-id-the-office-wrote-down  ")
	assert(bool(paid["ok"]), String(paid["reason"]))
	assert(String(paid["push"].request["body"]["invoices"][0]["invoice_id"]) == "the-id-the-office-wrote-down")


func test_a_payment_with_no_id_anywhere_is_refused_and_named() -> void:
	var desk := _desk()
	desk.add_adapter(NinjaScript.new("https://ninja.example.test", "token"))
	var invoice := _invoice()
	var paid: Dictionary = desk.queue_payment(_payment(invoice), invoice, "invoice_ninja")
	assert(not bool(paid["ok"]))
	assert(String(paid["reason"]).contains("when the invoice is first posted"), String(paid["reason"]))
	assert(desk.count() == 0)


func test_queueing_against_a_ledger_that_is_not_there_says_which() -> void:
	var desk := _desk()
	var by_name: Dictionary = desk.queue_invoice(_invoice(), "invoice_ninja")
	assert(not bool(by_name["ok"]))
	assert(String(by_name["reason"]).contains("no ledger called 'invoice_ninja'"), String(by_name["reason"]))
	# A desk whose chosen backend has gone says so rather than posting to whichever is first.
	desk.chosen = ""
	var by_chosen: Dictionary = desk.queue_invoice(_invoice())
	assert(not bool(by_chosen["ok"]))
	assert(String(by_chosen["reason"]).contains("no ledger is chosen"), String(by_chosen["reason"]))
	assert(desk.count() == 0)


# --- posting ------------------------------------------------------------------------------------


func test_posting_a_push_sends_what_it_holds_and_records_the_answer() -> void:
	var desk := _desk()
	var invoice := _invoice()
	var queued: Dictionary = desk.queue_invoice(invoice)
	var posted: Dictionary = desk.post(queued["push"].key)
	assert(bool(posted["ok"]), String(posted["reason"]))
	assert(int(posted["status"]) == 200)
	var push: PushScript = posted["push"]
	assert(push.is_pushed())
	assert(push.state_name() == "pushed")
	assert(push.attempts == 1)
	assert(not push.failure.is_empty() == false)
	# The file backend's own id for the document is where it put it.
	assert(push.external_id == String(queued["push"].request["url"]))
	assert(desk.pending().is_empty())
	assert(desk.delivered().size() == 1)
	# And the file is really there, with the invoice's own figure in it.
	assert(FileAccess.file_exists("%s/%s.json" % [TEST_FOLDER, invoice.number]))


func test_posting_twice_does_not_post_twice() -> void:
	var desk := _desk()
	var invoice := _invoice()
	var queued: Dictionary = desk.queue_invoice(invoice)
	assert(bool(desk.post(queued["push"].key)["ok"]))
	var again: Dictionary = desk.post(queued["push"].key)
	assert(bool(again["ok"]))
	assert(int(again["push"].attempts) == 1)
	assert(desk.count_for("file") == 1)


func test_posting_a_key_that_is_not_there_says_so() -> void:
	var desk := _desk()
	var posted: Dictionary = desk.post("nothing-here")
	assert(not bool(posted["ok"]))
	assert(String(posted["reason"]).contains("nothing in the outbox"), String(posted["reason"]))
	assert(int(posted["status"]) == 0)


func test_a_push_whose_backend_is_not_registered_says_so_instead_of_posting_anywhere() -> void:
	var desk := _desk()
	# A push built for a backend this session does not have: the request is kept as it stands, and the
	# attempt is recorded, because sending it to whichever backend happens to be first would post the
	# document to the wrong place.
	var push: PushScript = PushScript.for_document("invoice_ninja", AdapterScript.INVOICE_KIND,
		"INV-1", "INV-2026-0001", "key-1",
		AdapterScript.make_request(&"POST", "https://ninja.example.test/api/v1/invoices", {}, {"number": "INV-2026-0001"}),
		"2026-06-12")
	desk.pushes.append(push)
	var posted: Dictionary = desk.post("key-1")
	assert(not bool(posted["ok"]))
	assert(String(posted["reason"]).contains("no ledger called 'invoice_ninja' is registered here"),
		String(posted["reason"]))
	assert(push.attempts == 1)
	# Nothing reached a server, so this records as never arrived: the queue keeps it and will try it
	# again, and five runs of that is what turns it into a person's job.
	assert(push.can_retry())
	assert(not push.needs_a_person())
	assert(desk.stranded().is_empty())
	assert(desk.pending().size() == 1)
	assert(push.request["url"] == "https://ninja.example.test/api/v1/invoices")


func test_the_loop_sends_what_the_queue_still_owns_and_leaves_the_rest() -> void:
	var desk := _desk()
	var one := _invoice("INV-2026-0001")
	var two := _invoice("INV-2026-0002")
	desk.queue_invoice(one)
	desk.queue_invoice(two)
	assert(bool(desk.post(_key_for(desk, one))["ok"]))
	var run: Dictionary = desk.post_due()
	assert(bool(run["ok"]), String(run["reason"]))
	assert(int(run["tried"]) == 1)
	assert(int(run["taken"]) == 1)
	assert(int(run["failed"]) == 0)
	assert(int(run["waiting"]) == 0)
	assert(desk.delivered().size() == 2)


func test_the_loop_does_not_send_a_refusal_again() -> void:
	var desk := _desk()
	var queued: Dictionary = desk.queue_invoice(_invoice())
	var push: PushScript = queued["push"]
	assert(not _answered(push, 401, {"message": "token expired"}))
	assert(not push.can_retry())
	assert(push.needs_a_person())
	var run: Dictionary = desk.post_due()
	assert(int(run["tried"]) == 0)
	assert(int(run["stranded"]) == 1)


func test_the_loop_tries_a_busy_server_again() -> void:
	var desk := _desk()
	var queued: Dictionary = desk.queue_invoice(_invoice())
	var push: PushScript = queued["push"]
	assert(not _answered(push, 503, {"error": "connection reset"}))
	assert(push.can_retry())
	assert(not push.needs_a_person())
	# The backup is the queue's to try again, so it does - and this time the disk takes it.
	var run: Dictionary = desk.post_due()
	assert(int(run["tried"]) == 1)
	assert(int(run["taken"]) == 1)
	assert(push.is_pushed())


func test_the_loop_stops_after_so_many_tries() -> void:
	var desk := _desk()
	var queued: Dictionary = desk.queue_invoice(_invoice())
	var push: PushScript = queued["push"]
	for _try in PushScript.MAX_ATTEMPTS:
		_answered(push, 503, {})
	assert(push.attempts == PushScript.MAX_ATTEMPTS)
	assert(not push.can_retry())
	assert(push.needs_a_person())
	# A backend that has been down five times gets asked no more: the document becomes a person's.
	assert(int(desk.post_due()["tried"]) == 0)
	assert(desk.stranded().size() == 1)


func test_a_delivered_document_is_never_sent_by_the_loop_again() -> void:
	var desk := _desk()
	desk.queue_invoice(_invoice())
	assert(int(desk.post_due()["taken"]) == 1)
	var again: Dictionary = desk.post_due()
	assert(int(again["tried"]) == 0)
	assert(int(again["taken"]) == 0)
	assert(desk.delivered().size() == 1)


func test_the_loop_says_what_stood_in_the_way() -> void:
	var desk := _desk()
	# One push this desk can deliver, and one built for a backend that is not registered here.
	desk.queue_invoice(_invoice())
	var orphan: PushScript = PushScript.for_document("invoice_ninja", AdapterScript.INVOICE_KIND,
		"INV-9", "INV-2026-0009", "key-9",
		AdapterScript.make_request(&"POST", "https://ninja.example.test/api/v1/invoices", {},
			{"number": "INV-2026-0009"}),
		"2026-06-12")
	desk.pushes.append(orphan)
	var run: Dictionary = desk.post_due()
	# The run is not a success and says which document stood in the way, in words a person can act on.
	assert(not bool(run["ok"]))
	assert(int(run["tried"]) == 2)
	assert(int(run["taken"]) == 1)
	assert(int(run["failed"]) == 1)
	assert(int(run["waiting"]) == 1)
	assert(String(run["reason"]).contains("no ledger called 'invoice_ninja' is registered here"),
		String(run["reason"]))
	assert(desk.delivered().size() == 1)


# --- reading the outbox -------------------------------------------------------------------------


func test_what_the_queue_owns_and_what_it_has_given_up_on_are_two_lists() -> void:
	var desk := _desk()
	var one: Dictionary = desk.queue_invoice(_invoice("INV-2026-0001"))
	var two: Dictionary = desk.queue_invoice(_invoice("INV-2026-0002"))
	_answered(two["push"], 422, {"message": "the ledger would not accept it"})
	assert(desk.pending().size() == 1)
	assert(desk.stranded().size() == 1)
	assert(desk.delivered().is_empty())
	assert(desk.pending()[0] == one["push"])
	assert(desk.stranded()[0] == two["push"])


func test_rows_are_newest_first_and_carry_the_records_own_words() -> void:
	var desk := _desk()
	desk.queue_invoice(_invoice("INV-2026-0001"))
	desk.queue_invoice(_invoice("INV-2026-0002"))
	var rows: Array[Dictionary] = desk.rows()
	assert(rows.size() == 2)
	assert(String(rows[0]["number"]) == "INV-2026-0002")
	assert(String(rows[1]["number"]) == "INV-2026-0001")
	assert(String(rows[0]["state"]) == "queued")
	assert(String(rows[0]["kind_name"]) == "invoice")
	assert(int(rows[0]["attempts"]) == 0)
	assert(bool(rows[0]["retryable"]))
	assert(not bool(rows[0]["wants_a_person"]))
	assert(String(rows[0]["words"]).contains("queued, invoice to file, INV-2026-0002"), String(rows[0]["words"]))
	assert(desk.row_texts().size() == 2)


func test_rows_can_be_narrowed_to_one_backend() -> void:
	var desk := _desk()
	desk.add_adapter(NinjaScript.new("https://ninja.example.test", "token"))
	desk.queue_invoice(_invoice("INV-2026-0001"))
	desk.queue_invoice(_invoice("INV-2026-0002"), "invoice_ninja")
	assert(desk.rows().size() == 2)
	assert(desk.rows("invoice_ninja").size() == 1)
	assert(String(desk.rows("invoice_ninja")[0]["number"]) == "INV-2026-0002")
	assert(desk.rows("nothing").is_empty())
	assert(desk.count_for("file") == 1)
	assert(desk.count_for("invoice_ninja") == 1)


func test_the_summary_says_nothing_when_nothing_has_been_handed_over() -> void:
	var desk := _desk()
	# "0 handed over, 0 waiting" is noise on the one line a person reads from across the room.
	assert(desk.summary_text() == "nothing has been handed to a ledger")
	assert(desk.describe() == "the file ledger: nothing has been handed to a ledger")


func test_the_summary_counts_what_was_sent_what_waits_and_what_wants_a_person() -> void:
	var desk := _desk()
	var sent: Dictionary = desk.queue_invoice(_invoice("INV-2026-0001"))
	desk.post(sent["push"].key)
	desk.queue_invoice(_invoice("INV-2026-0002"))
	var stuck: Dictionary = desk.queue_invoice(_invoice("INV-2026-0003"))
	_answered(stuck["push"], 403, {})
	assert(desk.summary_text() == "1 handed over, 1 waiting, 1 wanting a person",
		desk.summary_text())
	assert(desk.issues() == 1)


# --- what does not agree ------------------------------------------------------------------------


func test_an_issued_invoice_handed_to_nobody_is_found() -> void:
	var desk := _desk()
	# The billing desk's own list is what "a document exists" means; reconcile only reads it.
	var billing: BillingDeskScript = BillingDeskScript.new()
	billing.invoices.append(_invoice())
	desk.bind(billing)
	var found: Array[Dictionary] = desk.reconcile()
	assert(found.size() == 1, str(found))
	assert(String(found[0]["kind"]) == LedgerDeskScript.NOT_HANDED_OVER)
	assert(String(found[0]["number"]) == "INV-2026-0001")
	assert(String(found[0]["words"]).contains("has been issued and not handed to file"),
		String(found[0]["words"]))
	assert(desk.reconcile_words().size() == 1)
	# Queueing it settles the question without anything being sent.
	desk.queue_invoice(billing.invoices[0])
	assert(desk.reconcile().is_empty())


func test_an_invoice_that_was_posted_and_then_called_back_is_found() -> void:
	var desk := _desk()
	var billing: BillingDeskScript = BillingDeskScript.new()
	var invoice := _invoice()
	billing.invoices.append(invoice)
	desk.bind(billing)
	desk.queue_invoice(invoice)
	assert(bool(desk.post_due()["taken"]) == true)
	invoice.voided_at = "2026-07-01"
	invoice.voided_why = "the customer went elsewhere"
	assert(invoice.is_void())
	var found: Array[Dictionary] = desk.reconcile()
	assert(found.size() == 1, str(found))
	assert(String(found[0]["kind"]) == LedgerDeskScript.VOID_BUT_POSTED)
	assert(String(found[0]["words"]).contains("only a credit note against it reverses it"),
		String(found[0]["words"]))


func test_a_void_invoice_that_was_never_handed_over_is_not_a_disagreement() -> void:
	var desk := _desk()
	var billing: BillingDeskScript = BillingDeskScript.new()
	var invoice := _invoice()
	invoice.voided_at = "2026-07-01"
	invoice.voided_why = "the customer went elsewhere"
	billing.invoices.append(invoice)
	desk.bind(billing)
	# A void invoice is not supposed to be handed over, so there is nothing to report.
	assert(desk.reconcile().is_empty())


func test_a_document_the_ledger_numbered_differently_is_found() -> void:
	var desk := _desk()
	var queued: Dictionary = desk.queue_invoice(_invoice())
	var push: PushScript = queued["push"]
	# The file backend keeps the office's number, but a hosted one may assign its own - and the two
	# numbers must not be quoted at each other without somebody knowing.
	var answered: Dictionary = {"status": 200, "body": {"id": "xYRdG7dDzO", "number": "0019"}}
	assert(push.record_response(answered, desk.chosen_adapter().parse_invoice_response(answered), "2026-06-12"))
	var found: Array[Dictionary] = desk.reconcile()
	assert(found.size() == 1, str(found))
	assert(String(found[0]["kind"]) == LedgerDeskScript.RENUMBERED)
	assert(String(found[0]["words"]).contains("is INV-2026-0001 here and 0019 in file"),
		String(found[0]["words"]))


func test_a_push_still_waiting_is_not_a_renumbering() -> void:
	var desk := _desk()
	desk.queue_invoice(_invoice())
	# Nothing has answered, so nothing has been renumbered: only a delivered document can disagree.
	assert(desk.reconcile().is_empty())


func test_reconciliation_changes_nothing() -> void:
	var desk := _desk()
	var billing: BillingDeskScript = BillingDeskScript.new()
	var invoice := _invoice()
	billing.invoices.append(invoice)
	desk.bind(billing)
	assert(desk.reconcile().size() == 1)
	# Nothing was queued on the ledger's behalf, nothing was posted, and the invoice is where it was:
	# a reconciliation that quietly fixed what it found would be a program editing an accounting record
	# on a guess.
	assert(desk.count() == 0)
	assert(desk.pushes.is_empty())
	assert(desk.delivered().is_empty())
	assert(billing.invoices.size() == 1)
	assert(invoice.is_issued())


func test_problems_names_the_documents_the_queue_gave_up_on_and_the_disagreements() -> void:
	var desk := _desk()
	var billing: BillingDeskScript = BillingDeskScript.new()
	billing.invoices.append(_invoice("INV-2026-0009"))
	desk.bind(billing)
	var stuck: Dictionary = desk.queue_invoice(_invoice("INV-2026-0001"))
	_answered(stuck["push"], 401, {"message": "token expired"})
	var found: Array[String] = desk.problems()
	assert(found.size() == 2, str(found))
	assert(found[0].contains("INV-2026-0001 will not be retried: "), found[0])
	assert(found[0].contains("token expired"), found[0])
	assert(found[1].contains("INV-2026-0009 has been issued and not handed to"), found[1])
	assert(not desk.is_sound())


func test_a_desk_whose_chosen_ledger_is_not_configured_says_what_it_needs() -> void:
	var desk := _desk()
	desk.add_adapter(NinjaScript.new())
	# A registered backend nobody has chosen is not a problem for the desk: nothing is going to it.
	assert(desk.problems().is_empty())
	assert(desk.is_sound())
	assert(desk.choose("invoice_ninja"))
	assert(desk.problems().size() == 1, str(desk.problems()))
	assert(desk.problems()[0].contains("API token"), desk.problems()[0])
	assert(not desk.is_sound())
	# Configured, and with an empty outbox, there is nothing wrong with it.
	desk.adapter("invoice_ninja").set_setting(&"token", "a-token")
	assert(desk.problems().is_empty())
	assert(desk.is_sound())


func test_a_desk_with_the_file_ledger_and_an_empty_outbox_is_sound() -> void:
	var desk := _desk()
	assert(desk.problems().is_empty())
	assert(desk.is_sound())
	assert(desk.issues() == 0)


# --- the outbox on disk -------------------------------------------------------------------------


func test_the_outbox_has_a_home_of_its_own() -> void:
	# Beside the invoices and the ledger, not among the drawings.
	assert(LedgerDeskScript.OUTBOX_PATH == "user://biz/outbox.json", LedgerDeskScript.OUTBOX_PATH)
	assert(LedgerDeskScript.OUTBOX_PATH.begins_with("user://biz/"))


func test_the_outbox_survives_a_file() -> void:
	var desk := _desk()
	var invoice := _invoice()
	var queued: Dictionary = desk.queue_invoice(invoice)
	assert(bool(desk.post(queued["push"].key)["ok"]))
	desk.queue_invoice(_invoice("INV-2026-0002"))
	var path: String = "%s/outbox.json" % TEST_FOLDER
	var written: Dictionary = desk.write(path)
	assert(bool(written["ok"]), String(written["reason"]))
	var reopened: LedgerDeskScript = LedgerDeskScript.new()
	reopened.chosen_adapter().set_setting(&"folder", TEST_FOLDER)
	var read_back: Dictionary = reopened.read(path)
	assert(bool(read_back["ok"]), String(read_back["reason"]))
	assert(int(read_back["loaded"]) == 2)
	assert(int(read_back["dropped"]) == 0)
	assert(reopened.count() == 2)
	assert(reopened.delivered().size() == 1)
	assert(reopened.pending().size() == 1)
	assert(reopened.chosen == "file")
	# The request comes back as the document it was, so a retry sends the same document (AC-B15). Method,
	# URL and every field of the body are the ones that went in; whole numbers arrive as floats, which is
	# what a JSON round trip does to them and what every backend reads the same.
	var stored: Dictionary = reopened.pushes[0].request
	var built: Dictionary = desk.pushes[0].request
	assert(String(stored["method"]) == String(built["method"]))
	assert(stored["url"] == built["url"])
	assert(String(stored["headers"][AdapterScript.KEY_HEADER])
		== String(built["headers"][AdapterScript.KEY_HEADER]))
	assert(String(stored["body"]["number"]) == String(built["body"]["number"]))
	assert(String(stored["body"]["kind"]) == String(built["body"]["kind"]))
	assert(float(stored["body"]["total"]["cents"]) == float(built["body"]["total"]["cents"]))
	assert(float(stored["body"]["lines"][0]["amount"]["cents"])
		== float(built["body"]["lines"][0]["amount"]["cents"]))


func test_a_delivered_state_is_a_function_of_the_records_after_a_file_too() -> void:
	var desk := _desk()
	desk.queue_invoice(_invoice())
	assert(bool(desk.post_due()["taken"]) == true)
	var path: String = "%s/outbox.json" % TEST_FOLDER
	assert(bool(desk.write(path)["ok"]))
	var reopened: LedgerDeskScript = LedgerDeskScript.new()
	assert(bool(reopened.read(path)["ok"]))
	# Nothing stored the word "pushed": what was stored was the moment it was taken.
	assert(reopened.pushes[0].pushed_at == desk.pushes[0].pushed_at)
	assert(reopened.pushes[0].state_name() == "pushed")
	assert(reopened.delivered().size() == 1)


func test_a_missing_outbox_is_an_empty_one_rather_than_a_fault() -> void:
	var desk := _desk()
	var read_back: Dictionary = desk.read("%s/nothing-here.json" % TEST_FOLDER)
	assert(bool(read_back["ok"]))
	assert(int(read_back["loaded"]) == 0)
	assert(desk.count() == 0)


func test_an_outbox_with_no_name_is_refused() -> void:
	var desk := _desk()
	assert(not bool(desk.write("")["ok"]))
	assert(not bool(desk.read("  ")["ok"]))


func test_an_unreadable_outbox_is_refused_and_leaves_the_desk_alone() -> void:
	var desk := _desk()
	desk.queue_invoice(_invoice())
	var path: String = "%s/broken.json" % TEST_FOLDER
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{ this is not an outbox")
	file.close()
	var read_back: Dictionary = desk.read(path)
	assert(not bool(read_back["ok"]))
	assert(String(read_back["reason"]).contains("not readable"), String(read_back["reason"]))
	# Half-loading an outbox is worse than not loading one, so the desk is left as it was.
	assert(desk.count() == 1)


func test_an_outbox_that_is_not_an_object_is_refused() -> void:
	var desk := _desk()
	var path: String = "%s/list.json" % TEST_FOLDER
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("[1, 2, 3]")
	file.close()
	var read_back: Dictionary = desk.read(path)
	assert(not bool(read_back["ok"]))
	assert(String(read_back["reason"]).contains("is not an outbox"), String(read_back["reason"]))


func test_a_damaged_row_is_dropped_and_the_rest_reads() -> void:
	var desk := _desk()
	desk.queue_invoice(_invoice())
	var second: PushScript = PushScript.for_document("file", AdapterScript.INVOICE_KIND,
		"INV-2", "INV-2026-0004", "key-4",
		AdapterScript.make_request(&"WRITE", "%s/INV-2026-0004.json" % TEST_FOLDER, {}, {"kind": "invoice"}),
		"2026-06-12")
	var path: String = "%s/outbox.json" % TEST_FOLDER
	var rows: Array = [
		desk.pushes[0].to_dict(),
		7,
		{"no_key": true},
		# Sound JSON with a key, and still not a push: there is no document and nothing to send, so it is
		# dropped rather than kept as a hole in the outbox.
		{"key": "k2", "adapter": "file"},
		second.to_dict(),
	]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "chosen": "file", "pushes": rows}, "  "))
	file.close()
	var read_back: Dictionary = desk.read(path)
	assert(bool(read_back["ok"]), String(read_back["reason"]))
	assert(int(read_back["loaded"]) == 2, str(read_back))
	assert(int(read_back["dropped"]) == 3, str(read_back))
	assert(desk.count() == 2)
	assert(desk.has_push("key-4"))


func test_a_backend_that_is_gone_falls_back_rather_than_breaking_the_outbox() -> void:
	var desk := _desk()
	desk.queue_invoice(_invoice())
	var path: String = "%s/outbox.json" % TEST_FOLDER
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"version": 1, "chosen": "invoice_ninja", "pushes": [desk.pushes[0].to_dict()],
	}, "  "))
	file.close()
	var reopened: LedgerDeskScript = LedgerDeskScript.new()
	assert(bool(reopened.read(path)["ok"]))
	# The pushes are read; the backend they were built for is not registered this session, and the desk
	# still has one to work with rather than none.
	assert(reopened.count() == 1)
	assert(reopened.chosen == "file")
	assert(reopened.chosen_adapter() != null)


func test_the_outbox_file_is_json_a_person_can_read() -> void:
	var desk := _desk()
	var invoice := _invoice()
	desk.queue_invoice(invoice)
	var path: String = "%s/outbox.json" % TEST_FOLDER
	assert(bool(desk.write(path)["ok"]))
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var text: String = file.get_as_text()
	file.close()
	var reader := JSON.new()
	assert(reader.parse(text) == OK)
	var data: Dictionary = reader.data
	assert(int(data["version"]) == LedgerDeskScript.VERSION)
	assert(String(data["chosen"]) == "file")
	var rows: Array = data["pushes"]
	assert(rows.size() == 1)
	var row: Dictionary = rows[0]
	# The document, its key, and what happened to it - all of them named, none of them encoded.
	assert(String(row["key"]) == _key_for(desk, invoice))
	assert(String(row["document_number"]) == "INV-2026-0001")
	assert(String(row["adapter"]) == "file")
	assert(String(row["state"]) == "queued")
	assert(String(row["request"]["method"]) == "WRITE")


func test_a_credential_is_not_written_into_the_outbox() -> void:
	var desk := _desk()
	var ninja: NinjaScript = NinjaScript.new("https://ninja.example.test", "super-secret-token")
	desk.add_adapter(ninja)
	var invoice := _invoice()
	desk.queue_invoice(invoice, "invoice_ninja")
	# In memory the request is the real one, credential and all, because that is what will be sent.
	var in_memory: Dictionary = desk.pushes[0].request["headers"]
	assert(String(in_memory[NinjaScript.TOKEN_HEADER]) == "super-secret-token")
	var path: String = "%s/outbox.json" % TEST_FOLDER
	assert(bool(desk.write(path)["ok"]))
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var text: String = file.get_as_text()
	file.close()
	# A file sitting beside the drawings is not where a token belongs.
	assert(not text.contains("super-secret-token"), "the token reached the outbox file")
	var reader := JSON.new()
	assert(reader.parse(text) == OK)
	var written: Dictionary = (reader.data as Dictionary)["pushes"][0]["request"]["headers"]
	assert(written.has(NinjaScript.TOKEN_HEADER))
	assert(String(written[NinjaScript.TOKEN_HEADER]) == "")
	# And the other headers, which are not secret, are written down as they stand.
	assert(String(written["X-Requested-With"]) == "XMLHttpRequest")


func test_the_credential_is_put_back_at_the_moment_of_sending() -> void:
	var desk := _desk()
	var ninja: NinjaScript = NinjaScript.new("https://ninja.example.test", "first-token")
	desk.add_adapter(ninja)
	# The desk has to be pointed at it, because which backend a stored outbox belongs to is part of what
	# was written down.
	assert(desk.choose("invoice_ninja"))
	desk.queue_invoice(_invoice(), "invoice_ninja")
	var path: String = "%s/outbox.json" % TEST_FOLDER
	assert(bool(desk.write(path)["ok"]))
	var reopened: LedgerDeskScript = LedgerDeskScript.new()
	reopened.add_adapter(NinjaScript.new("https://ninja.example.test", "second-token"))
	assert(bool(reopened.read(path)["ok"]))
	# The stored request has no credential in it at all, so the one that goes out is the live one - which
	# is also the only way a token rotated between two sessions can be the right one.
	assert(String(reopened.pushes[0].request["headers"][NinjaScript.TOKEN_HEADER]) == "")
	var ready: Dictionary = reopened.chosen_adapter().authorise(reopened.pushes[0].request)
	assert(String(ready["headers"][NinjaScript.TOKEN_HEADER]) == "second-token")
	# Everything that is the document is untouched: only the credential is re-supplied.
	assert(ready["url"] == reopened.pushes[0].request["url"])
	assert(ready["body"] == reopened.pushes[0].request["body"])


func test_a_backend_that_authenticates_with_a_header_says_which_one() -> void:
	var ninja: NinjaScript = NinjaScript.new("https://ninja.example.test", "token")
	var token_only: Array[String] = [NinjaScript.TOKEN_HEADER]
	assert(ninja.secret_headers() == token_only, str(ninja.secret_headers()))
	var books: AkauntingScript = AkauntingScript.new("https://books.example.test", "someone", "hunter2")
	var basic_only: Array[String] = [AkauntingScript.AUTH_HEADER]
	assert(books.secret_headers() == basic_only, str(books.secret_headers()))
	# The file backend authenticates with nothing, which is why its requests go to disk as they stand.
	assert(FileLedgerScript.new().secret_headers().is_empty())
	# And a backend with nothing secret to put back hands the request straight back.
	var request: Dictionary = {"method": "WRITE", "url": "user://x.json", "headers": {}, "body": {}}
	assert(FileLedgerScript.new().authorise(request) == request)


func test_a_password_is_not_written_into_the_outbox_either() -> void:
	var desk := _desk()
	var books: AkauntingScript = AkauntingScript.new("https://books.example.test", "office@example.test", "hunter2")
	desk.add_adapter(books)
	desk.queue_invoice(_invoice(), "akaunting")
	var path: String = "%s/outbox.json" % TEST_FOLDER
	assert(bool(desk.write(path)["ok"]))
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var text: String = file.get_as_text()
	file.close()
	assert(not text.contains("hunter2"), "the password reached the outbox file")
	# Not even encoded: the whole Basic credential is blanked, not written out and hidden.
	assert(not text.contains(Marshalls.utf8_to_base64("office@example.test:hunter2")))


# --- keeping it to a size -----------------------------------------------------------------------


func test_a_full_outbox_drops_the_oldest_thing_it_has_already_delivered() -> void:
	var desk := _desk()
	for at in LedgerDeskScript.MAX_PUSHES + 1:
		var push: PushScript = PushScript.for_document(
			"file", AdapterScript.INVOICE_KIND, "INV-%d" % at, "INV-%04d" % at, "key-%d" % at,
			AdapterScript.make_request(&"WRITE", "user://x.json", {}, {}), "2026-06-12"
		)
		if at == 0:
			# The oldest is delivered, so it is the one that goes.
			push.record_response({"status": 200, "body": {}},
				AdapterScript.new().parse_common({"status": 200, "body": {}}), "2026-06-12")
		desk.pushes.append(push)
	desk._trim()
	assert(desk.count() == LedgerDeskScript.MAX_PUSHES)
	assert(desk.has_push("key-0") == false)
	assert(desk.has_push("key-1"))
	assert(desk.has_push("key-%d" % LedgerDeskScript.MAX_PUSHES))


func test_an_outbox_full_of_undelivered_documents_is_not_trimmed_at_all() -> void:
	var desk := _desk()
	for at in LedgerDeskScript.MAX_PUSHES + 5:
		desk.pushes.append(PushScript.for_document(
			"file", AdapterScript.INVOICE_KIND, "INV-%d" % at, "INV-%04d" % at, "key-%d" % at,
			AdapterScript.make_request(&"WRITE", "user://x.json", {}, {}), "2026-06-12"
		))
	desk._trim()
	# A document nobody has been told about is exactly the thing that must not be trimmed away, so the
	# outbox is allowed to be over its cap rather than lose one.
	assert(desk.count() == LedgerDeskScript.MAX_PUSHES + 5)


# --- everything the office has issued and not yet handed over -----------------------------------


func _billing(invoices: Array) -> BillingDeskScript:
	var billing: BillingDeskScript = BillingDeskScript.new()
	for invoice in invoices:
		billing.invoices.append(invoice)
	return billing


func test_handing_over_every_issued_invoice_queues_each_one_once() -> void:
	var desk := _desk()
	desk.bind(_billing([_invoice("INV-2026-0001"), _invoice("INV-2026-0002")]))
	var run: Dictionary = desk.queue_unhanded()
	assert(bool(run["ok"]), String(run["reason"]))
	assert(int(run["queued"]) == 2)
	assert(int(run["refused"]) == 0)
	assert(desk.count() == 2)
	# Idempotent: the key is the identity, so a second pass queues nothing and re-queues nothing.
	var again: Dictionary = desk.queue_unhanded()
	assert(bool(again["ok"]))
	assert(int(again["queued"]) == 0)
	assert(desk.count() == 2)
	assert(desk.refusals.is_empty())


func test_an_invoice_that_was_never_issued_is_not_handed_over() -> void:
	var desk := _desk()
	var draft: InvoiceScript = InvoiceScript.new("INV-1")
	draft.job = "J1"
	draft.customer = {"name": "Smith", "external_id": CLIENT}
	draft.add_line(InvoiceScript.MILESTONE_LINE, "Deposit", 1000, &"EACH",
		MoneyScript.of(1000), &"HARDSCAPE", &"NONE")
	desk.bind(_billing([draft, _invoice("INV-2026-0001")]))
	# A draft has no number to post, so there is nothing to hand over.
	assert(int(desk.queue_unhanded()["queued"]) == 1)
	assert(desk.count() == 1)
	assert(desk.refusals.is_empty())


func test_an_invoice_that_was_called_back_is_not_handed_over() -> void:
	var desk := _desk()
	var called_back := _invoice("INV-2026-0001")
	called_back.voided_at = "2026-07-01"
	called_back.voided_why = "the customer went elsewhere"
	desk.bind(_billing([called_back, _invoice("INV-2026-0002")]))
	assert(int(desk.queue_unhanded()["queued"]) == 1)
	assert(desk.count() == 1)


func test_an_invoice_that_cannot_be_built_is_refused_by_name_and_does_not_stop_the_rest() -> void:
	var desk := _desk()
	desk.add_adapter(NinjaScript.new("https://ninja.example.test", "token"))
	desk.choose("invoice_ninja")
	desk.bind(_billing([_invoice("INV-2026-0001", ""), _invoice("INV-2026-0002")]))
	var run: Dictionary = desk.queue_unhanded()
	assert(not bool(run["ok"]))
	assert(int(run["queued"]) == 1)
	assert(int(run["refused"]) == 1)
	assert(String(run["reason"]).contains("INV-2026-0001 could not be handed over"), String(run["reason"]))
	assert(String(run["reason"]).contains("no id in Invoice Ninja"), String(run["reason"]))
	# It is kept and shown, not swallowed: the desk's own problems name it.
	assert(desk.refusals.size() == 1)
	assert(desk.problems().size() == 1, str(desk.problems()))
	assert(desk.problems()[0].contains("INV-2026-0001 could not be handed over"), desk.problems()[0])
	assert(desk.issues() == 1)


func test_a_refusal_is_forgotten_when_it_is_fixed() -> void:
	var desk := _desk()
	desk.add_adapter(NinjaScript.new("https://ninja.example.test", "token"))
	desk.choose("invoice_ninja")
	var invoice := _invoice("INV-2026-0001", "")
	desk.bind(_billing([invoice]))
	assert(int(desk.queue_unhanded()["refused"]) == 1)
	assert(desk.problems().size() == 1)
	# The office records the id the ledger gave the customer, and hands it over again.
	invoice.customer = {"name": "Smith", "external_id": CLIENT}
	var again: Dictionary = desk.queue_unhanded()
	assert(bool(again["ok"]), String(again["reason"]))
	assert(int(again["queued"]) == 1)
	assert(desk.refusals.is_empty())
	assert(desk.problems().is_empty())


func test_handing_over_with_no_billing_desk_queues_nothing() -> void:
	var desk := _desk()
	var run: Dictionary = desk.queue_unhanded()
	assert(bool(run["ok"]))
	assert(int(run["queued"]) == 0)
	assert(desk.count() == 0)


func test_handing_over_with_no_ledger_says_which() -> void:
	var desk := _desk()
	desk.bind(_billing([_invoice()]))
	desk.chosen = ""
	var run: Dictionary = desk.queue_unhanded()
	assert(not bool(run["ok"]))
	assert(String(run["reason"]).contains("no ledger is chosen"), String(run["reason"]))
	assert(desk.count() == 0)