extends Node
## The outbox record: one push, what it sent, and what came of it (REQ-B14, spec §9.7).
##
## Three properties are under test. **The state is a function of what happened** - nothing tried is
## queued, something accepted is pushed, a refusal is failed - and a file that claims otherwise on an
## untried push does not make it so. **A failure worth retrying stays queued and one that is not asks
## for a person**, which is the difference between an office that waits and one that is told. And **the
## request is stored, not rebuilt**, because that is the whole basis of AC-B15: a retry sends what the
## first attempt sent.

const PushScript := preload("res://scripts/biz/ledger_push.gd")
const LedgerScript := preload("res://scripts/biz/ledger_adapter.gd")

const KEY := "file:invoice:INV1:INV-2026-0001@CAD 500.00"


func _request() -> Dictionary:
	var headers: Dictionary = {LedgerScript.KEY_HEADER: KEY}
	return {
		"method": "POST",
		"url": "https://example.test/invoices",
		"headers": headers,
		"body": {"kind": "invoice", "number": "INV-2026-0001"},
	}


func _push() -> PushScript:
	return PushScript.for_document("file", LedgerScript.INVOICE_KIND, "INV1", "INV-2026-0001",
		KEY, _request(), "2026-06-01")


func _took_it() -> Dictionary:
	return {"ok": true, "retry": false, "reason": "", "external_id": "42", "external_number": "INV-2026-0001"}


func _refused() -> Dictionary:
	return {"ok": false, "retry": false, "reason": "401 unauthorized: check the API token"}


func _busy() -> Dictionary:
	return {"ok": false, "retry": true, "reason": "503 the ledger had a server error; try again"}


# --- queueing it --------------------------------------------------------------------------------


func test_a_queued_push_holds_what_it_was_built_with_and_has_not_been_tried_yet() -> void:
	var push := _push()
	assert(push.state() == PushScript.QUEUED)
	assert(push.state_name() == "queued")
	assert(push.attempt_count() == 0)
	assert(not push.is_pushed())
	assert(push.can_retry())
	assert(not push.needs_a_person())
	assert(push.is_sound())
	assert(push.problems().is_empty())
	assert(String(push.request["url"]) == "https://example.test/invoices")
	assert(String(push.request["headers"][LedgerScript.KEY_HEADER]) == KEY)
	assert(push.kind == LedgerScript.INVOICE_KIND)
	assert(push.queued_at == "2026-06-01")


func test_the_request_is_stored_rather_than_rebuilt() -> void:
	# A retry must send what the first attempt sent: a rebuilt body could carry a document that moved
	# under it, and the idempotency key would then de-duplicate the wrong thing (AC-B15).
	var source: Dictionary = _request()
	var push: PushScript = PushScript.for_document("file", LedgerScript.INVOICE_KIND, "INV1",
		"INV-2026-0001", KEY, source, "2026-06-01")
	source["url"] = "https://somewhere.else"
	source["body"]["number"] = "MOVED"
	assert(String(push.request["url"]) == "https://example.test/invoices")
	assert(String(push.request["body"]["number"]) == "INV-2026-0001")


# --- what came of it ----------------------------------------------------------------------------


func test_a_ledger_that_took_the_document_records_where_it_went() -> void:
	var push := _push()
	assert(push.record_response({"status": 201, "body": {"id": "42"}}, _took_it(), "2026-06-01"))
	assert(push.is_pushed())
	assert(push.state() == PushScript.PUSHED)
	assert(push.state_name() == "pushed")
	assert(push.pushed_at == "2026-06-01")
	assert(push.external_id == "42")
	assert(push.external_number == "INV-2026-0001")
	assert(push.attempt_count() == 1)
	assert(push.failure == "")
	assert(not push.can_retry(), "an accepted push is never sent again")
	assert(push.describe().contains("as INV-2026-0001"), push.describe())


func test_a_refusal_makes_it_failed_and_a_busy_server_leaves_it_queued() -> void:
	var refused := _push()
	assert(not refused.record_response({"status": 401, "body": {}}, _refused(), "2026-06-02"))
	assert(refused.state() == PushScript.FAILED)
	assert(refused.needs_a_person(), "a refused push is somebody's to fix, not the queue's to re-send")
	assert(not refused.can_retry())
	assert(refused.failure.contains("401 unauthorized"), refused.failure)
	var busy := _push()
	assert(not busy.record_response({"status": 503, "error": "connection reset", "body": {}}, _busy(), "2026-06-02"))
	# A server that was busy is not a document that is wrong: this one goes again by itself.
	assert(busy.state() == PushScript.QUEUED)
	assert(busy.can_retry())
	assert(not busy.needs_a_person())
	assert(int(busy.last_status) == 503)


func test_a_push_that_keeps_failing_stops_retrying_and_asks_for_a_person() -> void:
	var push := _push()
	for step in range(PushScript.MAX_ATTEMPTS - 1):
		push.record_response({"status": 503, "body": {}}, _busy(), "2026-06-0%d" % (step + 2))
	assert(push.state() == PushScript.QUEUED, "still worth one more try")
	assert(push.can_retry())
	push.record_response({"status": 503, "body": {}}, _busy(), "2026-06-09")
	assert(push.attempt_count() == PushScript.MAX_ATTEMPTS)
	# "Try again" has stopped being advice by now, so the office is told instead of re-sent.
	assert(push.state() == PushScript.FAILED)
	assert(push.needs_a_person())
	assert(not push.can_retry())


# --- soundness ----------------------------------------------------------------------------------


func test_a_push_with_nothing_to_send_is_not_sound() -> void:
	var empty: PushScript = PushScript.new()
	var problems: Array[String] = empty.problems()
	assert(problems.size() == 5, str(problems))
	assert(not empty.is_sound())
	var nowhere: PushScript = PushScript.for_document("file", LedgerScript.INVOICE_KIND, "INV1",
		"INV-2026-0001", KEY, {"method": "POST", "url": "", "headers": {}, "body": {}}, "2026-06-01")
	assert(nowhere.problems().size() == 1, str(nowhere.problems()))
	assert(nowhere.problems()[0].contains("goes nowhere"), nowhere.problems()[0])


func test_a_record_with_no_key_is_dropped_rather_than_invented() -> void:
	# The key is this record's identity, so a push without one cannot be de-duplicated and must not be
	# queued at all.
	assert(PushScript.from_dict({}) == null)
	assert(PushScript.from_dict({"key": "   "}) == null)
	assert(PushScript.from_dict({"adapter": "file", "document_id": "INV1"}) == null)


# --- the state is a function of the records ------------------------------------------------------


func test_the_state_is_a_function_of_the_records_and_not_a_field() -> void:
	var push := _push()
	var row: Dictionary = push.to_dict()
	assert(String(row["state"]) == "queued")
	# A file that claims a state the records do not support does not make it so.
	row["state"] = "pushed"
	var back: PushScript = PushScript.from_dict(row)
	assert(back != null)
	assert(back.state() == PushScript.QUEUED)
	assert(back.state_name() == "queued")
	assert(not back.is_pushed())


func test_a_push_survives_the_file_with_its_request_and_what_it_learned() -> void:
	var push := _push()
	push.record_response({"status": 503, "error": "connection reset", "body": {}}, _busy(), "2026-06-02")
	var back: PushScript = PushScript.from_dict(push.to_dict())
	assert(back != null)
	assert(back.key == KEY)
	assert(back.adapter == "file")
	assert(back.kind == LedgerScript.INVOICE_KIND)
	assert(back.document_id == "INV1")
	assert(back.document_number == "INV-2026-0001")
	assert(back.request == push.request)
	assert(back.attempt_count() == 1)
	assert(back.last_retryable)
	assert(int(back.last_status) == 503)
	assert(String(back.failure).contains("server error"))


func test_describe_reads_as_a_push() -> void:
	var push := _push()
	assert(push.describe() == "queued, invoice to file, INV-2026-0001", push.describe())
	push.record_response({"status": 401, "body": {}}, _refused(), "2026-06-02")
	assert(push.describe() == "failed, invoice to file, INV-2026-0001, try 1 of 5, 401 unauthorized: check the API token", push.describe())
	var credit: PushScript = PushScript.for_document("file", LedgerScript.CREDIT_KIND, "CN1",
		"CN-2026-0001", "k", _request(), "2026-06-01")
	assert(credit.describe() == "queued, credit note to file, CN-2026-0001", credit.describe())