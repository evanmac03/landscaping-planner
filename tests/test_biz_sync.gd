extends Node
## The sync run and the conflict policy (spec §11.2-§11.5).
##
## What is under test is the part of collaboration that is a *decision*: a pull that could not be read
## does not push, a money change is never merged, a text change is not a business event, and a money
## conflict stops the document going out. The transport is a fake, so every answer - a change log, a
## 409, a 503 - can be made to happen on purpose; what a real service does with a live socket is a
## deployment question (§15), and the shape of the request it would receive is tested in
## `test_biz_http_transport.gd`.

const StoreScript := preload("res://scripts/biz/store.gd")
const SyncScript := preload("res://scripts/biz/sync.gd")
const TransportScript := preload("res://scripts/biz/sync_transport.gd")

const ROOT := "user://test_sync_store"
const STATE := "user://test_sync/state.json"
const AT := 1780000000
## A money value, so a test says "money" by shape rather than by name.
const CAD := "CAD"

## A service that answers whatever a test tells it to and remembers what it was asked.
class Fake extends BizSyncTransport:
	var pull: Dictionary = {"ok": true, "status": 200, "retry": false, "reason": "", "cursor": 0, "records": []}
	var answers: Array = []
	var sent: Array = []
	var asked_since: int = -1
	var asked_limit: int = 0

	func name() -> String:
		return "fake"

	func is_configured() -> bool:
		return true

	func is_ready() -> bool:
		return true

	func describe() -> String:
		return "the fake service"

	func changes(since: int = 0, limit: int = 0) -> Dictionary:
		asked_since = since
		asked_limit = limit
		return pull

	func push(kind: String, id: String, job: String, body: Dictionary, rev: int, who: String = "") -> Dictionary:
		sent.append({"kind": kind, "id": id, "job": job, "rev": rev, "body": body, "who": who})
		if answers.is_empty():
			return {"ok": true, "status": 200, "retry": false, "conflict": false, "reason": "", "rev": rev + 1}
		return answers.pop_front()


class Offline extends BizSyncTransport:
	func name() -> String:
		return "offline"


func _wipe(folder: String) -> void:
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		return
	for file_name in dir.get_files():
		DirAccess.remove_absolute(folder.path_join(String(file_name)))
	for subfolder in dir.get_directories():
		_wipe(folder.path_join(String(subfolder)))
	DirAccess.remove_absolute(folder)


func _fresh() -> StoreScript:
	_wipe(ROOT)
	_wipe("user://test_sync")
	return StoreScript.new(ROOT)


func _money(cents: int) -> Dictionary:
	return {"cents": cents, "currency": CAD}


func _sync(store: StoreScript, service: BizSyncTransport) -> SyncScript:
	var sync: SyncScript = SyncScript.new(store, service)
	sync.state_path = STATE
	return sync


## A service that hands back one record and nothing else.
func _serving(kind: String, id: String, job: String, rev: int, body: Dictionary, cursor: int = 1) -> Fake:
	var service := Fake.new()
	service.pull = {
		"ok": true,
		"status": 200,
		"retry": false,
		"reason": "",
		"cursor": cursor,
		"records": [{
			"kind": kind, "id": id, "job": job, "rev": rev,
			"schema_version": StoreScript.SCHEMA_VERSION, "body": body, "deleted": false,
		}],
	}
	return service


# --- what a field holds -------------------------------------------------------------------------


func test_a_money_shaped_value_is_money_whatever_it_is_called() -> void:
	assert(BizSync.class_of("total", null, {"cents": 1, "currency": CAD}) == BizSync.MONEY)
	assert(BizSync.class_of("whatever", {"cents": 1, "currency": CAD}, null) == BizSync.MONEY)


func test_a_quantity_a_rate_and_an_approval_are_money_by_name() -> void:
	assert(BizSync.class_of("quantity_milli", 100, 200) == BizSync.MONEY)
	assert(BizSync.class_of("rate", 1, 2) == BizSync.MONEY)
	assert(BizSync.class_of("approved_by", "evan", "sam") == BizSync.MONEY)


func test_a_list_of_lines_or_a_schedule_is_a_structure() -> void:
	assert(BizSync.class_of("lines", [1], [1, 2]) == BizSync.STRUCTURE)
	assert(BizSync.class_of("stops", {"a": 1}, {"a": 2}) == BizSync.STRUCTURE)


func test_a_note_a_name_or_a_description_is_text() -> void:
	assert(BizSync.class_of("notes", "first", "second") == BizSync.TEXT)
	assert(BizSync.class_of("label", "Smith", "Jones") == BizSync.TEXT)


func test_money_is_a_cents_and_currency_pair_and_nothing_else() -> void:
	assert(BizSync.is_money_shape({"cents": 1, "currency": CAD}))
	assert(not BizSync.is_money_shape({"cents": 1}))
	assert(not BizSync.is_money_shape("CAD"))
	assert(not BizSync.is_money_shape([1, 2]))


# --- the queue ----------------------------------------------------------------------------------


func test_a_change_queues_the_body_from_the_store_and_the_fields_from_the_journal() -> void:
	var store := _fresh()
	store.put("invoice", "INV-1", {"number": "INV-1", "amount": _money(10000)}, "J-1", -1, "evan", AT)
	var sync := _sync(store, Fake.new())
	var queued: Dictionary = sync.enqueue("invoice", "INV-1", "J-1", "raised it", "evan", AT)
	assert(queued["ok"])
	assert(int(queued["base_rev"]) == 0)
	var rows: Array[Dictionary] = sync.pending_rows()
	assert(rows.size() == 1)
	assert(int(rows[0]["body"]["amount"]["cents"]) == 10000)
	var changed: Array = rows[0]["changed"]
	assert(changed.size() == 2)


func test_queueing_one_record_twice_is_one_entry_with_the_latest_body() -> void:
	var store := _fresh()
	store.put("invoice", "INV-1", {"amount": _money(10000)}, "J-1", -1, "evan", AT)
	var sync := _sync(store, Fake.new())
	sync.enqueue("invoice", "INV-1", "J-1", "raised", "evan", AT)
	store.put("invoice", "INV-1", {"amount": _money(20000)}, "J-1", 1, "evan", AT)
	sync.enqueue("invoice", "INV-1", "J-1", "raised it higher", "evan", AT)
	assert(sync.waiting() == 1)
	var rows: Array[Dictionary] = sync.pending_rows()
	assert(int(rows[0]["body"]["amount"]["cents"]) == 20000)
	assert(int(rows[0]["base_rev"]) == 0)
	var changed: Array = rows[0]["changed"]
	# The record was created by the first edit, so what it was before is nothing, and what it is after
	# is the latest value - not the value the second edit started from.
	assert(changed[0]["before"] == null)
	assert(int(changed[0]["after"]) == 20000)


func test_queueing_works_with_nowhere_to_sync_to() -> void:
	var store := _fresh()
	store.put("time_entry", "T-1", {"minutes": 480}, "J-1", -1, "sam", AT)
	var sync := _sync(store, Offline.new())
	assert(sync.enqueue("time_entry", "T-1", "J-1", "the day on the patio", "sam", AT)["ok"])
	assert(sync.waiting() == 1)
	assert(sync.queue_text().contains("waiting to sync"))


func test_queueing_a_record_the_store_does_not_have_is_refused() -> void:
	var store := _fresh()
	var sync := _sync(store, Fake.new())
	var refused: Dictionary = sync.enqueue("invoice", "INV-9", "J-1")
	assert(not refused["ok"])
	assert(refused["reason"].contains("cannot queue"))


func test_the_queue_says_how_much_is_waiting() -> void:
	var store := _fresh()
	var sync := _sync(store, Fake.new())
	assert(sync.queue_text() == "nothing is waiting to sync")
	store.put("lead", "L-1", {"name": "a"}, "", -1, "evan", AT)
	sync.enqueue("lead", "L-1")
	assert(sync.queue_text() == "1 record change waiting to sync")
	store.put("lead", "L-2", {"name": "b"}, "", -1, "evan", AT)
	sync.enqueue("lead", "L-2")
	assert(sync.queue_text() == "2 record changes waiting to sync")


func test_a_pending_row_carries_what_the_person_was_doing() -> void:
	var store := _fresh()
	store.put("lead", "L-1", {"name": "a"}, "", -1, "evan", AT)
	var sync := _sync(store, Fake.new())
	sync.enqueue("lead", "L-1", "", "the enquiry came in", "evan", AT)
	assert(sync.pending_row_texts()[0].contains("the enquiry came in"))


# --- the run: what it will not do ---------------------------------------------------------------


func test_a_run_with_nowhere_to_sync_to_refuses_and_keeps_the_queue() -> void:
	var store := _fresh()
	store.put("lead", "L-1", {"name": "a"}, "", -1, "evan", AT)
	var sync := _sync(store, Offline.new())
	sync.enqueue("lead", "L-1")
	var run: Dictionary = sync.run(0, AT)
	assert(not run["ok"])
	assert(run["reason"].contains("not ready"))
	assert(sync.waiting() == 1)


func test_a_pull_that_could_not_be_read_does_not_push() -> void:
	var store := _fresh()
	store.put("lead", "L-1", {"name": "a"}, "", -1, "evan", AT)
	var service := Fake.new()
	service.pull = {"ok": false, "status": 0, "retry": true, "reason": "503 the service was momentarily unable", "cursor": 0, "records": []}
	var sync := _sync(store, service)
	sync.enqueue("lead", "L-1")
	var run: Dictionary = sync.run(0, AT)
	assert(not run["ok"])
	assert(run["reason"].contains("503"))
	assert(sync.waiting() == 1)
	assert(service.sent.is_empty())


func test_a_run_with_no_store_refuses() -> void:
	var sync: SyncScript = SyncScript.new(null, Fake.new())
	sync.state_path = STATE
	assert(not sync.run(0, AT)["ok"])


# --- the run: pulling ---------------------------------------------------------------------------


func test_a_record_the_service_has_and_this_device_has_not_is_applied_and_the_cursor_moves() -> void:
	var store := _fresh()
	var sync := _sync(store, _serving("lead", "L-1", "", 4, {"name": "the Hendersons"}, 7))
	var run: Dictionary = sync.run(0, AT)
	assert(run["ok"])
	assert(int(run["pulled"]) == 1)
	assert(int(run["applied"]) == 1)
	assert(sync.cursor == 7)
	assert(String(store.fetch("lead", "L-1")["body"]["name"]) == "the Hendersons")
	assert(int(store.fetch("lead", "L-1")["rev"]) == 4)


func test_a_pull_asks_the_service_for_changes_since_the_cursor() -> void:
	var store := _fresh()
	var service := _serving("lead", "L-1", "", 1, {"name": "a"})
	var sync := _sync(store, service)
	sync.cursor = 12
	sync.run(25, AT)
	assert(service.asked_since == 12)
	assert(service.asked_limit == 25)


func test_a_pulled_tombstone_takes_the_record_away() -> void:
	var store := _fresh()
	store.put("lead", "L-1", {"name": "a"}, "", -1, "evan", AT)
	var service := Fake.new()
	service.pull = {
		"ok": true, "status": 200, "retry": false, "reason": "", "cursor": 3,
		"records": [{"kind": "lead", "id": "L-1", "job": "", "rev": 2, "schema_version": 1, "body": {}, "deleted": true}],
	}
	var sync := _sync(store, service)
	sync.run(0, AT)
	assert(not store.holds("lead", "L-1"))


func test_a_tombstone_for_a_record_this_device_changed_is_a_disagreement_not_a_deletion() -> void:
	var store := _fresh()
	store.put("lead", "L-1", {"name": "a"}, "", -1, "evan", AT)
	var service := Fake.new()
	service.pull = {
		"ok": true, "status": 200, "retry": false, "reason": "", "cursor": 3,
		"records": [{"kind": "lead", "id": "L-1", "job": "", "rev": 2, "schema_version": 1, "body": {}, "deleted": true}],
	}
	var sync := _sync(store, service)
	sync.enqueue("lead", "L-1")
	sync.run(0, AT)
	assert(store.holds("lead", "L-1"))
	assert(sync.conflicts.size() == 1)
	assert(sync.refuses_to_issue("lead", "L-1"))


# --- the run: merging ---------------------------------------------------------------------------


func test_a_text_change_by_two_people_is_not_a_conflict_and_ours_is_kept() -> void:
	var store := _fresh()
	store.put("invoice", "INV-1", {"notes": "first draw"}, "J-1", -1, "evan", AT)
	var service := _serving("invoice", "INV-1", "J-1", 1, {"notes": "first draw and the walk"})
	var sync := _sync(store, service)
	sync.enqueue("invoice", "INV-1", "J-1", "raised", "evan", AT)
	var run: Dictionary = sync.run(0, AT)
	assert(int(run["merged"]) == 1)
	assert(sync.conflicts.is_empty())
	assert(not (run["notes"] as Array).is_empty())
	# The change is still pushed - ours wins a wording - and it is pushed against the revision the
	# service actually holds.
	assert(String(service.sent[0]["body"]["notes"]) == "first draw")
	assert(int(service.sent[0]["rev"]) == 1)


func test_a_money_change_by_two_people_is_a_conflict_and_stops_the_document_going_out() -> void:
	var store := _fresh()
	store.put("invoice", "INV-1", {"amount": _money(10000)}, "J-1", -1, "evan", AT)
	var service := _serving("invoice", "INV-1", "J-1", 1, {"amount": _money(20000)})
	var sync := _sync(store, service)
	sync.enqueue("invoice", "INV-1", "J-1", "raised", "evan", AT)
	var run: Dictionary = sync.run(0, AT)
	assert(int(run["conflicts"]) == 1)
	var row: Dictionary = sync.open_conflicts("invoice", "INV-1", "J-1")[0]
	assert(String(row["class"]) == BizSync.MONEY)
	assert(int(row["ours"]["cents"]) == 10000)
	assert(int(row["theirs"]["cents"]) == 20000)
	assert(sync.refuses_to_issue("invoice", "INV-1", "J-1"))
	assert(sync.refusal_words("invoice", "INV-1", "J-1").contains("amount"))
	# And the change does not go out over theirs: pushing ours would be the silent merge §11.3 forbids.
	assert(int(run["held"]) == 1)
	assert(service.sent.is_empty())
	assert(sync.waiting() == 1)
	# And the change does not go out over theirs: pushing ours would be the silent merge §11.3 forbids.
	assert(int(run["held"]) == 1)
	assert(service.sent.is_empty())
	assert(sync.waiting() == 1)


func test_a_structure_change_by_two_people_is_a_conflict() -> void:
	var store := _fresh()
	store.put("estimate", "E-1", {"lines": [1, 2]}, "J-1", -1, "evan", AT)
	var service := _serving("estimate", "E-1", "J-1", 1, {"lines": [1, 3]})
	var sync := _sync(store, service)
	sync.enqueue("estimate", "E-1", "J-1", "priced it", "evan", AT)
	sync.run(0, AT)
	assert(sync.conflicts.size() == 1)
	assert(String(sync.conflicts[0]["class"]) == BizSync.STRUCTURE)


func test_a_disagreement_names_both_values_both_authors_and_both_timestamps() -> void:
	var store := _fresh()
	store.put("invoice", "INV-1", {"amount": _money(10000)}, "J-1", -1, "evan", AT)
	var service := _serving("invoice", "INV-1", "J-1", 1, {"amount": _money(20000)})
	var sync := _sync(store, service)
	sync.enqueue("invoice", "INV-1", "J-1", "raised", "evan", AT)
	sync.run(0, AT + 60)
	var row: Dictionary = sync.conflicts[0]
	assert(String(row["ours_who"]) == "evan")
	assert(int(row["ours_at"]) == AT)
	assert(String(row["theirs_who"]) == "the service")
	assert(int(row["theirs_at"]) == AT + 60)
	assert(int(row["theirs_rev"]) == 1)


func test_a_change_the_service_agrees_with_is_not_a_conflict() -> void:
	var store := _fresh()
	store.put("invoice", "INV-1", {"amount": _money(10000)}, "J-1", -1, "evan", AT)
	var service := _serving("invoice", "INV-1", "J-1", 1, {"amount": _money(10000)})
	var sync := _sync(store, service)
	sync.enqueue("invoice", "INV-1", "J-1", "raised", "evan", AT)
	sync.run(0, AT)
	assert(sync.conflicts.is_empty())


# --- the run: pushing ---------------------------------------------------------------------------


func test_a_pushed_change_is_cleared_and_the_local_revision_becomes_the_services() -> void:
	var store := _fresh()
	store.put("lead", "L-1", {"name": "a"}, "", -1, "evan", AT)
	var service := Fake.new()
	var sync := _sync(store, service)
	sync.enqueue("lead", "L-1", "", "the enquiry", "evan", AT)
	var run: Dictionary = sync.run(0, AT)
	assert(int(run["pushed"]) == 1)
	assert(sync.waiting() == 0)
	assert(int(service.sent[0]["rev"]) == 0)
	assert(String(service.sent[0]["who"]) == "evan")
	assert(int(store.fetch("lead", "L-1")["rev"]) == 1)


func test_a_change_the_service_refused_stays_queued_with_the_words() -> void:
	var store := _fresh()
	store.put("lead", "L-1", {"name": "a"}, "", -1, "evan", AT)
	var service := Fake.new()
	service.answers = [{"ok": false, "status": 401, "retry": false, "conflict": false, "reason": "401 the token was refused", "rev": 0}]
	var sync := _sync(store, service)
	sync.enqueue("lead", "L-1")
	sync.run(0, AT)
	assert(sync.waiting() == 1)
	var rows: Array[Dictionary] = sync.pending_rows()
	assert(int(rows[0]["tries"]) == 1)
	assert(String(rows[0]["last"]).contains("401"))


func test_a_change_tried_to_the_limit_is_given_up_on() -> void:
	var store := _fresh()
	store.put("lead", "L-1", {"name": "a"}, "", -1, "evan", AT)
	var service := Fake.new()
	for _try in SyncScript.MAX_TRIES:
		service.answers.append({"ok": false, "status": 503, "retry": true, "conflict": false, "reason": "503 try again", "rev": 0})
	var sync := _sync(store, service)
	sync.enqueue("lead", "L-1")
	for _run in SyncScript.MAX_TRIES:
		sync.run(0, AT)
	assert(sync.stranded().size() == 1)
	assert(sync.stranded_texts()[0].contains("503"))
	assert(sync.summary_text().contains("given up on"))


func test_a_push_the_service_says_conflicts_records_a_disagreement_and_keeps_the_change() -> void:
	var store := _fresh()
	store.put("lead", "L-1", {"name": "a"}, "", -1, "evan", AT)
	var service := Fake.new()
	service.answers = [{"ok": false, "status": 409, "retry": false, "conflict": true, "reason": "409 someone else changed it first", "rev": 5}]
	var sync := _sync(store, service)
	sync.enqueue("lead", "L-1")
	var run: Dictionary = sync.run(0, AT)
	assert(int(run["conflicts"]) == 1)
	assert(sync.waiting() == 1)
	assert(int(sync.conflicts[0]["theirs_rev"]) == 5)


func test_the_run_counts_what_it_did() -> void:
	var store := _fresh()
	store.put("lead", "L-1", {"name": "a"}, "", -1, "evan", AT)
	var service := _serving("lead", "L-2", "", 1, {"name": "theirs"})
	var sync := _sync(store, service)
	sync.enqueue("lead", "L-1")
	var run: Dictionary = sync.run(0, AT)
	assert(int(run["pulled"]) == 1)
	assert(int(run["applied"]) == 1)
	assert(int(run["pushed"]) == 1)
	assert(int(run["waiting"]) == 0)


# --- settling a conflict ------------------------------------------------------------------------


func _conflicted() -> SyncScript:
	var store := _fresh()
	store.put("invoice", "INV-1", {"amount": _money(10000)}, "J-1", -1, "evan", AT)
	var service := _serving("invoice", "INV-1", "J-1", 1, {"amount": _money(20000)})
	var sync := _sync(store, service)
	sync.enqueue("invoice", "INV-1", "J-1", "raised", "evan", AT)
	sync.run(0, AT)
	return sync


func test_settling_a_conflict_by_our_copy_writes_it_and_closes_the_conflict() -> void:
	var sync: SyncScript = _conflicted()
	var settled: Dictionary = sync.resolve(0, SyncScript.OUR_COPY, "evan", AT + 120)
	assert(settled["ok"])
	assert(sync.conflicts.is_empty())
	assert(not sync.refuses_to_issue("invoice", "INV-1", "J-1"))
	assert(int(sync.store.fetch("invoice", "INV-1", "J-1")["body"]["amount"]["cents"]) == 10000)


func test_settling_a_conflict_by_their_copy_takes_their_value() -> void:
	var sync: SyncScript = _conflicted()
	sync.resolve(0, SyncScript.THEIR_COPY, "evan", AT + 120)
	assert(int(sync.store.fetch("invoice", "INV-1", "J-1")["body"]["amount"]["cents"]) == 20000)


func test_settling_a_conflict_queues_the_settled_value_against_the_services_revision() -> void:
	var sync: SyncScript = _conflicted()
	sync.resolve(0, SyncScript.THEIR_COPY, "evan", AT + 120)
	assert(sync.waiting() == 1)
	assert(int(sync.pending_rows()[0]["base_rev"]) == 1)


func test_a_conflict_is_settled_by_choosing_a_copy_or_not_at_all() -> void:
	var sync: SyncScript = _conflicted()
	assert(not sync.resolve(0, "maybe")["ok"])
	assert(sync.conflicts.size() == 1)


func test_settling_a_conflict_that_is_not_there_is_refused() -> void:
	var store := _fresh()
	var sync := _sync(store, Fake.new())
	assert(not sync.resolve(0, SyncScript.OUR_COPY)["ok"])


func test_a_record_with_no_conflict_goes_out_and_its_refusal_is_silent() -> void:
	var store := _fresh()
	var sync := _sync(store, Fake.new())
	assert(not sync.refuses_to_issue("invoice", "INV-1", "J-1"))
	assert(sync.refusal_words("invoice", "INV-1", "J-1") == "")


# --- the state file -----------------------------------------------------------------------------


func test_the_state_survives_the_file() -> void:
	var store := _fresh()
	store.put("lead", "L-1", {"name": "a"}, "", -1, "evan", AT)
	var sync := _sync(store, Fake.new())
	sync.cursor = 4
	sync.enqueue("lead", "L-1", "", "the enquiry", "evan", AT)
	var again := _sync(store, Fake.new())
	assert(again.read(STATE)["ok"])
	assert(again.cursor == 4)
	assert(again.waiting() == 1)
	assert(again.pending_rows()[0]["why"] == "the enquiry")


func test_a_missing_state_file_is_a_fresh_sync() -> void:
	var store := _fresh()
	var sync := _sync(store, Fake.new())
	assert(sync.read(STATE)["ok"])
	assert(sync.waiting() == 0)
	assert(sync.cursor == 0)


func test_a_state_file_that_will_not_read_is_refused_and_leaves_the_sync_alone() -> void:
	var store := _fresh()
	store.put("lead", "L-1", {"name": "a"}, "", -1, "evan", AT)
	var sync := _sync(store, Fake.new())
	sync.enqueue("lead", "L-1")
	DirAccess.make_dir_recursive_absolute(STATE.get_base_dir())
	var file: FileAccess = FileAccess.open(STATE, FileAccess.WRITE)
	file.store_string("{ not a sync state")
	file.close()
	var read: Dictionary = sync.read(STATE)
	assert(not read["ok"])
	assert(read["reason"].contains("not readable"))
	assert(sync.waiting() == 1)


func test_a_state_file_with_a_row_that_is_not_an_entry_is_dropped() -> void:
	var store := _fresh()
	var sync := _sync(store, Fake.new())
	sync.pending = [{"kind": "lead", "id": "L-1", "job": "", "body": {}, "changed": [], "base_rev": 0, "tries": 0}]
	sync.write(STATE)
	var again := _sync(store, Fake.new())
	assert(again.read(STATE)["ok"])
	assert(again.waiting() == 1)


func test_describe_names_the_store_the_service_and_the_cursor() -> void:
	var store := _fresh()
	var sync := _sync(store, Fake.new())
	sync.cursor = 9
	var words: String = sync.describe()
	assert(words.contains("the fake service"))
	assert(words.contains("read to 9"))
	assert(words.contains(ROOT))


func test_a_sync_with_no_store_says_so() -> void:
	var sync: SyncScript = SyncScript.new(null, null)
	sync.state_path = STATE
	assert(sync.summary_text().contains("no records"))