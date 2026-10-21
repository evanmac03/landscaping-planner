extends Node
## The record store: one file per record, revisions, and the append-only journal (spec §11.1, §11.6,
## §2.12).
##
## Four properties are under test. **A record lands where §11.1 says it does**, because the folder
## layout is the thing that makes git the version-control strategy rather than a wish. **A write names
## the revision it expected and a stale one is refused**, which is what stops a client that has been
## offline clobbering the office. **The journal records the before and the after of a money field**,
## because a price change is the change somebody gets asked about, and it is never rewritten. And **the
## schema guards refuse rather than half-read**, because a record that only its own build can read is a
## data loss with a delay on it.

const StoreScript := preload("res://scripts/biz/store.gd")

const ROOT := "user://test_store"
## A May morning and a June one, stated rather than read off the clock.
const MAY := 1780000000
const JUNE := 1782600000


func _fresh() -> StoreScript:
	_wipe(ROOT)
	return StoreScript.new(ROOT)


func _wipe(folder: String) -> void:
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		return
	for file_name in dir.get_files():
		DirAccess.remove_absolute(folder.path_join(String(file_name)))
	for subfolder in dir.get_directories():
		_wipe(folder.path_join(String(subfolder)))
	DirAccess.remove_absolute(folder)


func _job() -> Dictionary:
	return {
		"number": "J-1001",
		"label": "Smith, back garden",
		"contract_sum": {"cents": 428400, "currency": "CAD"},
	}


func _invoice(cents: int) -> Dictionary:
	return {
		"number": "INV-2026-0001",
		"job": "J-1001",
		"amount": {"cents": cents, "currency": "CAD"},
		"notes": "first draw",
	}


func _ids(rows: Array[Dictionary]) -> Array:
	var out: Array = []
	for row in rows:
		out.append(String(row["id"]))
	return out


# --- where a record lands -----------------------------------------------------------------------


func test_a_job_is_filed_where_the_folder_layout_says() -> void:
	var store := _fresh()
	assert(store.record_path(StoreScript.JOB_KIND, "J-1001") == ROOT.path_join("jobs/J-1001/job.json"))


func test_a_job_level_record_is_filed_under_its_job() -> void:
	var store := _fresh()
	assert(store.record_path("invoice", "INV-77", "J-1001") == ROOT.path_join("jobs/J-1001/invoice/INV-77.json"))
	assert(store.record_path("estimate", "E-3", "J-1001") == ROOT.path_join("jobs/J-1001/estimate/E-3.json"))
	assert(store.record_path("time_entry", "T-9", "J-1001") == ROOT.path_join("jobs/J-1001/time_entry/T-9.json"))


func test_a_flat_record_is_filed_in_its_own_folder() -> void:
	var store := _fresh()
	assert(store.record_path("lead", "L-4") == ROOT.path_join("leads/L-4.json"))
	assert(store.record_path("crew", "C-2") == ROOT.path_join("crew/C-2.json"))


func test_the_file_is_written_where_the_path_says() -> void:
	var store := _fresh()
	assert(store.put(StoreScript.JOB_KIND, "J-1001", _job(), "", -1, "evan", MAY)["ok"])
	assert(FileAccess.file_exists(ROOT.path_join("jobs/J-1001/job.json")))
	assert(store.holds(StoreScript.JOB_KIND, "J-1001"))
	assert(not store.holds("invoice", "INV-77", "J-1001"))


# --- reading it back ----------------------------------------------------------------------------


func test_a_record_read_back_is_the_record_that_went_in() -> void:
	var store := _fresh()
	store.put(StoreScript.JOB_KIND, "J-1001", _job(), "", -1, "evan", MAY)
	var read: Dictionary = store.fetch(StoreScript.JOB_KIND, "J-1001")
	assert(read["ok"])
	assert(read["found"])
	assert(String(read["body"]["number"]) == "J-1001")
	assert(String(read["body"]["label"]) == "Smith, back garden")
	assert(int(read["body"]["contract_sum"]["cents"]) == 428400)


func test_a_missing_record_is_not_found_rather_than_an_error() -> void:
	var store := _fresh()
	var read: Dictionary = store.fetch(StoreScript.JOB_KIND, "J-9999")
	assert(not read["ok"])
	assert(not read["found"])
	assert(read["reason"].contains("there is no job"))


# --- revisions ----------------------------------------------------------------------------------


func test_a_revision_counts_up_from_one() -> void:
	var store := _fresh()
	assert(int(store.put(StoreScript.JOB_KIND, "J-1001", _job(), "", -1, "evan", MAY)["rev"]) == 1)
	assert(int(store.put(StoreScript.JOB_KIND, "J-1001", _job(), "", -1, "evan", MAY)["rev"]) == 2)
	assert(int(store.fetch(StoreScript.JOB_KIND, "J-1001")["rev"]) == 2)


func test_a_write_naming_the_revision_it_expected_is_taken() -> void:
	var store := _fresh()
	var first: Dictionary = store.put("invoice", "INV-77", _invoice(128500), "J-1001", -1, "evan", MAY)
	var second: Dictionary = store.put("invoice", "INV-77", _invoice(135000), "J-1001", int(first["rev"]), "evan", JUNE)
	assert(second["ok"])
	assert(int(second["rev"]) == 2)


func test_a_write_naming_a_revision_it_is_not_at_is_refused_and_says_both_numbers() -> void:
	var store := _fresh()
	store.put("invoice", "INV-77", _invoice(128500), "J-1001", -1, "evan", MAY)
	store.put("invoice", "INV-77", _invoice(135000), "J-1001", 1, "evan", JUNE)
	var stale: Dictionary = store.put("invoice", "INV-77", _invoice(1), "J-1001", 1, "sam", JUNE)
	assert(not stale["ok"])
	assert(stale["conflict"])
	assert(stale["reason"].contains("expected at revision 1"))
	assert(stale["reason"].contains("moved to 2"))
	assert(int(stale["rev"]) == 2)


func test_a_refused_stale_write_leaves_the_record_alone() -> void:
	var store := _fresh()
	store.put("invoice", "INV-77", _invoice(128500), "J-1001", -1, "evan", MAY)
	store.put("invoice", "INV-77", _invoice(135000), "J-1001", 1, "evan", JUNE)
	assert(not store.put("invoice", "INV-77", _invoice(1), "J-1001", 1, "sam", JUNE)["ok"])
	var read: Dictionary = store.fetch("invoice", "INV-77", "J-1001")
	assert(int(read["body"]["amount"]["cents"]) == 135000)
	assert(int(read["rev"]) == 2)


func test_a_first_write_naming_revision_zero_is_taken() -> void:
	var store := _fresh()
	assert(store.put("lead", "L-4", {"name": "the Hendersons"}, "", 0, "evan", MAY)["ok"])


func test_naming_a_revision_when_nothing_is_there_is_a_conflict() -> void:
	var store := _fresh()
	var stale: Dictionary = store.put("lead", "L-4", {"name": "x"}, "", 3, "evan", MAY)
	assert(not stale["ok"])
	assert(stale["conflict"])
	assert(stale["reason"].contains("there is nothing here"))


# --- the journal --------------------------------------------------------------------------------


func test_the_journal_records_a_money_fields_before_and_after_as_cents() -> void:
	var store := _fresh()
	store.put("invoice", "INV-77", _invoice(128500), "J-1001", -1, "evan", MAY)
	store.put("invoice", "INV-77", _invoice(135000), "J-1001", 1, "evan", JUNE)
	var entries: Array[Dictionary] = store.history("invoice", "INV-77")
	var changed: Array = entries[entries.size() - 1]["changed"]
	var money: Dictionary = {}
	for field in changed:
		if String(field["field"]) == "amount":
			money = field
	assert(not money.is_empty())
	assert(int(money["before"]) == 128500)
	assert(int(money["after"]) == 135000)


func test_the_journal_records_the_changed_fields_in_name_order() -> void:
	var store := _fresh()
	store.put("lead", "L-4", {"zone": "front", "amount": {"cents": 1, "currency": "CAD"}, "notes": "x"}, "", -1, "evan", MAY)
	var entries: Array[Dictionary] = store.history("lead", "L-4")
	var changed: Array = entries[0]["changed"]
	var names: Array = []
	for field in changed:
		names.append(String(field["field"]))
	assert(names == ["amount", "notes", "zone"])


func test_an_addition_is_recorded_with_nothing_before_it() -> void:
	var store := _fresh()
	store.put("lead", "L-4", {"name": "the Hendersons"}, "", -1, "evan", MAY)
	var changed: Array = store.history("lead", "L-4")[0]["changed"]
	assert(changed.size() == 1)
	assert(String(changed[0]["field"]) == "name")
	assert(changed[0]["before"] == null)
	assert(String(changed[0]["after"]) == "the Hendersons")


func test_the_journal_names_who_changed_what_and_when() -> void:
	var store := _fresh()
	store.put("lead", "L-4", {"name": "x"}, "", -1, "evan", MAY, "the enquiry came in")
	var entry: Dictionary = store.history("lead", "L-4")[0]
	assert(String(entry["who"]) == "evan")
	assert(int(entry["at"]) == MAY)
	assert(String(entry["action"]) == "put")
	assert(int(entry["rev"]) == 1)
	assert(int(entry["before_rev"]) == 0)
	assert(String(entry["note"]) == "the enquiry came in")


func test_the_journal_is_append_only_so_two_writes_are_two_entries() -> void:
	var store := _fresh()
	store.put("lead", "L-4", {"name": "x"}, "", -1, "evan", MAY)
	store.put("lead", "L-4", {"name": "y"}, "", 1, "evan", MAY)
	var entries: Array[Dictionary] = store.journal()
	assert(entries.size() == 2)
	assert(String(entries[0]["id"]) == "L-4")
	assert(int(entries[0]["rev"]) == 1)
	assert(int(entries[1]["rev"]) == 2)


func test_a_deletion_is_journaled() -> void:
	var store := _fresh()
	store.put("lead", "L-4", {"name": "x"}, "", -1, "evan", MAY)
	assert(store.discard("lead", "L-4", "", "evan", MAY, "the enquiry went cold")["ok"])
	assert(not store.holds("lead", "L-4"))
	var last: Dictionary = store.history("lead", "L-4")[1]
	assert(String(last["action"]) == StoreScript.REMOVE_ACTION)
	assert(int(last["before_rev"]) == 1)
	assert(String(last["note"]) == "the enquiry went cold")


func test_the_journal_file_is_named_for_the_month_of_the_moment() -> void:
	var store := _fresh()
	assert(store.journal_path(MAY).get_file() == "events-2026-05.jsonl")
	assert(store.journal_path(JUNE).get_file() == "events-2026-06.jsonl")


func test_a_time_nobody_stated_is_filed_as_undated() -> void:
	var store := _fresh()
	assert(store.journal_path(0).get_file() == "events-undated.jsonl")
	store.put("lead", "L-4", {"name": "x"}, "", -1, "evan", 0)
	assert(FileAccess.file_exists(ROOT.path_join("journals/events-undated.jsonl")))


func test_a_month_apart_is_two_journal_files() -> void:
	var store := _fresh()
	store.put("lead", "L-4", {"name": "x"}, "", -1, "evan", MAY)
	store.put("lead", "L-5", {"name": "y"}, "", -1, "evan", JUNE)
	assert(FileAccess.file_exists(ROOT.path_join("journals/events-2026-05.jsonl")))
	assert(FileAccess.file_exists(ROOT.path_join("journals/events-2026-06.jsonl")))
	assert(store.journal().size() == 2)


func test_history_is_one_records_entries_in_order() -> void:
	var store := _fresh()
	store.put("lead", "L-4", {"name": "x"}, "", -1, "evan", MAY)
	store.put("lead", "L-5", {"name": "y"}, "", -1, "evan", MAY)
	store.put("lead", "L-4", {"name": "z"}, "", 1, "evan", MAY)
	var entries: Array[Dictionary] = store.history("lead", "L-4")
	assert(entries.size() == 2)
	assert(int(entries[0]["rev"]) == 1)
	assert(int(entries[1]["rev"]) == 2)


func test_history_can_be_narrowed_to_a_job() -> void:
	var store := _fresh()
	store.put("invoice", "INV-77", _invoice(1), "J-1001", -1, "evan", MAY)
	store.put("invoice", "INV-77", _invoice(2), "J-1002", -1, "evan", MAY)
	assert(store.history("invoice", "INV-77", "J-1001").size() == 1)
	assert(store.history("invoice", "INV-77").size() == 2)


# --- the things it refuses ----------------------------------------------------------------------


func test_a_record_id_that_is_a_path_separator_is_refused() -> void:
	var store := _fresh()
	assert(not store.put("lead", "a/b", {"name": "x"}, "", -1, "evan", MAY)["ok"])
	assert(not store.put("lead", "a\\b", {"name": "x"}, "", -1, "evan", MAY)["ok"])
	assert(store.record_path("lead", "a/b") == "")


func test_a_record_id_of_two_dots_is_refused() -> void:
	var store := _fresh()
	assert(not store.put("lead", "..", {"name": "x"}, "", -1, "evan", MAY)["ok"])
	assert(not store.put("lead", ".hidden", {"name": "x"}, "", -1, "evan", MAY)["ok"])


func test_a_job_level_record_with_no_job_named_is_refused() -> void:
	var store := _fresh()
	var refused: Dictionary = store.put("invoice", "INV-77", _invoice(1), "", -1, "evan", MAY)
	assert(not refused["ok"])
	assert(refused["reason"].contains("belongs to a job"))


func test_a_kind_the_store_does_not_keep_is_refused() -> void:
	var store := _fresh()
	var refused: Dictionary = store.put("sandwich", "S-1", {}, "", -1, "evan", MAY)
	assert(not refused["ok"])
	assert(refused["reason"].contains("not a kind of record"))


func test_a_record_on_disk_that_will_not_read_is_not_written_over() -> void:
	var store := _fresh()
	var path: String = store.record_path("invoice", "INV-77", "J-1001")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{ this is not json")
	file.close()
	var refused: Dictionary = store.put("invoice", "INV-77", _invoice(1), "J-1001", -1, "evan", MAY)
	assert(not refused["ok"])
	assert(refused["reason"].contains("cannot be read"))
	var kept: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert(kept.get_as_text() == "{ this is not json")
	kept.close()


# --- health -------------------------------------------------------------------------------------


func test_a_store_that_reads_has_no_problems() -> void:
	var store := _fresh()
	store.put(StoreScript.JOB_KIND, "J-1001", _job(), "", -1, "evan", MAY)
	store.put("invoice", "INV-77", _invoice(1), "J-1001", -1, "evan", MAY)
	assert(store.problems().is_empty())


func test_a_record_file_with_no_schema_is_named() -> void:
	var store := _fresh()
	var path: String = store.record_path("lead", "L-4")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"kind": "lead", "id": "L-4", "rev": 1, "body": {}}))
	file.close()
	var problems: Array[String] = store.problems()
	assert(problems.size() == 1)
	assert(problems[0].contains("does not say which schema"))


func test_a_damaged_journal_line_is_skipped_and_named() -> void:
	var store := _fresh()
	store.put("lead", "L-4", {"name": "x"}, "", -1, "evan", MAY)
	var path: String = ROOT.path_join("journals/events-2026-05.jsonl")
	var file: FileAccess = FileAccess.open(path, FileAccess.READ_WRITE)
	file.seek_end()
	file.store_line("{ not a journal entry")
	file.close()
	assert(store.journal().size() == 1)
	assert(store.problems().size() == 1)
	assert(store.problems()[0].contains("will not read as a journal entry"))


func test_describe_counts_what_is_kept() -> void:
	var store := _fresh()
	store.put(StoreScript.JOB_KIND, "J-1001", _job(), "", -1, "evan", MAY)
	store.put("lead", "L-4", {"name": "x"}, "", -1, "evan", MAY)
	var words: String = store.describe()
	assert(words.contains("2 kept"))
	assert(words.contains("2 journal entries"))


# --- schema versioning --------------------------------------------------------------------------


func test_upcast_passes_a_current_record_through() -> void:
	var store := _fresh()
	var got: Dictionary = store.upcast(StoreScript.SCHEMA_VERSION, {"a": 1})
	assert(got["ok"])
	assert(int(got["body"]["a"]) == 1)
	assert(int(got["from"]) == StoreScript.SCHEMA_VERSION)
	assert(int(got["to"]) == StoreScript.SCHEMA_VERSION)


func test_upcast_refuses_a_newer_record_naming_both_numbers() -> void:
	var store := _fresh()
	var got: Dictionary = store.upcast(StoreScript.SCHEMA_VERSION + 1, {"a": 1})
	assert(not got["ok"])
	assert(got["reason"].contains("newer version"))
	assert(got["reason"].contains("schema 2"))
	assert(got["reason"].contains("understands 1"))


func test_upcast_refuses_an_old_record_with_no_step() -> void:
	var store := _fresh()
	var got: Dictionary = store.upcast(StoreScript.SCHEMA_VERSION - 1, {"a": 1})
	assert(not got["ok"])
	assert(got["reason"].contains("no way here"))
	assert(int(got["body"].size()) == 0)


func test_a_step_registered_for_an_older_version_migrates_a_body() -> void:
	# This build sits at schema 1, so it ships no step; the step is injected so that the machinery is
	# proved now rather than trusted until the first time it matters.
	var store := _fresh()
	var step := func(body: Dictionary) -> Dictionary:
		var moved: Dictionary = body.duplicate(true)
		moved["unit"] = "m2"
		return moved
	store._upcasters = {1: step}
	var got: Dictionary = store.upcast(1, {"area": 3}, 2)
	assert(got["ok"])
	assert(String(got["body"]["unit"]) == "m2")
	assert(int(got["body"]["area"]) == 3)
	assert(int(got["from"]) == 1)
	assert(int(got["to"]) == 2)


func test_register_upcaster_refuses_what_it_cannot_take() -> void:
	# A build sitting at schema 1 has nothing to register: a step is only meaningful below the current
	# schema, and there is no version between 1 and 1. The table exists for the day there is.
	var store := _fresh()
	var step := func(body: Dictionary) -> Dictionary: return body
	assert(not store.register_upcaster(StoreScript.SCHEMA_VERSION, step))
	assert(not store.register_upcaster(StoreScript.SCHEMA_VERSION + 1, step))
	assert(not store.register_upcaster(0, step))
	assert(not store.register_upcaster(StoreScript.SCHEMA_VERSION, Callable()))


# --- listing and the wire form ------------------------------------------------------------------


func test_records_lists_the_ids_in_name_order() -> void:
	var store := _fresh()
	store.put("crew", "C-10", {"name": "ten"}, "", -1, "evan", MAY)
	store.put("crew", "C-2", {"name": "two"}, "", -1, "evan", MAY)
	var rows: Array[Dictionary] = store.records("crew")
	assert(_ids(rows) == ["C-10", "C-2"])
	assert(int(rows[0]["rev"]) == 1)


func test_records_of_a_job_level_kind_are_filed_under_that_job() -> void:
	var store := _fresh()
	store.put("invoice", "INV-77", _invoice(1), "J-1001", -1, "evan", MAY)
	store.put("invoice", "INV-78", _invoice(2), "J-1001", -1, "evan", MAY)
	assert(_ids(store.records("invoice", "J-1001")) == ["INV-77", "INV-78"])
	assert(store.records("invoice", "J-2002").is_empty())


func test_records_of_jobs_reads_the_folders() -> void:
	var store := _fresh()
	store.put(StoreScript.JOB_KIND, "J-1001", _job(), "", -1, "evan", MAY)
	store.put(StoreScript.JOB_KIND, "J-1002", _job(), "", -1, "evan", MAY)
	assert(_ids(store.records(StoreScript.JOB_KIND)) == ["J-1001", "J-1002"])


func test_the_envelope_carries_the_revision_and_the_schema() -> void:
	var store := _fresh()
	store.put("invoice", "INV-77", _invoice(128500), "J-1001", -1, "evan", MAY)
	var got: Dictionary = store.envelope("invoice", "INV-77", "J-1001")
	assert(got["ok"])
	var env: Dictionary = got["envelope"]
	assert(String(env["kind"]) == "invoice")
	assert(String(env["id"]) == "INV-77")
	assert(String(env["job"]) == "J-1001")
	assert(int(env["rev"]) == 1)
	assert(int(env["schema_version"]) == StoreScript.SCHEMA_VERSION)
	assert(int(env["body"]["amount"]["cents"]) == 128500)
	assert(not env["deleted"])


func test_an_applied_envelope_is_written_at_the_revision_it_carries() -> void:
	var store := _fresh()
	var pulled: Dictionary = store.apply({
		"kind": "invoice",
		"id": "INV-77",
		"job": "J-1001",
		"rev": 7,
		"schema_version": StoreScript.SCHEMA_VERSION,
		"body": _invoice(128500),
		"deleted": false,
	}, "the service", JUNE)
	assert(pulled["ok"])
	var read: Dictionary = store.fetch("invoice", "INV-77", "J-1001")
	assert(int(read["rev"]) == 7)
	assert(String(store.history("invoice", "INV-77", "J-1001")[0]["action"]) == StoreScript.PULL_ACTION)