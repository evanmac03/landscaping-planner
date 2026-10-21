class_name BizStore
extends RefCounted
## The record store: one file per record, an append-only journal, and per-record revisions
## (spec §11.1, §11.6, §2.12).
##
## A job's month of edits should diff as a handful of small files rather than a rewritten megabyte:
## that is what makes **git a usable version-control strategy for the whole business** (§11.6) and
## makes a merge conflict something a human can read. So a record is one JSON file, laid out the way
## §11.1 lays it out, and the folder as a whole is the thing a person commits.
##
## Five things here are decisions rather than plumbing.
##
## **A write names the revision it expected, and a mismatch is refused rather than written over.**
## That is the same `If-Match` the service arbitrates with (§11.2); enforcing it here as well means a
## client that has been offline for a week cannot quietly clobber the office's edit - it is told, and
## the sync layer turns that into a conflict a person resolves. `expected_rev` of `-1` means "I am not
## claiming to know", which is what a first write and a deliberate overwrite both are.
##
## **The journal is append-only and is never rewritten.** It is the audit trail §2.12 asks for ("who
## changed the price, and when") and, because business state has no per-edit snapshot, it is the only
## tractable undo for it. One file a month - `events-YYYY-MM.jsonl` - so an append is an append and the
## file for a past month never moves. **A money field's before and after are recorded**: a value shaped
## like `{cents, currency}` is written into the journal as its integer `cents`, because a price change
## is the change somebody will be asked about.
##
## **A record says what schema wrote it, and an upcaster table carries it forward** (§11.6.3). A
## business's records outlive several generations of this software, and a document that can only be
## read by the version that wrote it is a data loss with a delay on it. A record from a *newer* schema
## is refused, naming both numbers, rather than half-read.
##
## **Nothing here reads the clock.** `at` is an argument (seconds since the epoch), the way every other
## figure in this module is - so a journal entry can be written for a moment that is stated, not
## stumbled into. `at` of `0` means none was stated and the entry lands in `events-undated.jsonl`
## rather than being dated 1970.
##
## **A file is written through a temporary file and a rename**, exactly as a drawing is: a save that
## fails halfway must not leave a record shorter than the one it replaced. And a record that is already
## on disk and **cannot be read** is never written over - a damaged record is a fault to name, not a
## thing to lose.


## Every kind of record this store keeps.
const JOB_KIND := "job"
const JOB_KINDS := ["estimate", "change_order", "purchase_order", "time_entry", "invoice"]
## Kinds that are filed flat, and the folder each lives in (§11.1).
const FLAT_FOLDERS := {"lead": "leads", "crew": "crew"}

const ROOT := "user://biz"
const JOURNAL_FOLDER := "journals"
const TEMP_SUFFIX := ".part"
## What this build writes, and the version its upcaster table brings other versions up to.
const SCHEMA_VERSION := 1

const PUT_ACTION := "put"
const PULL_ACTION := "pull"
const REMOVE_ACTION := "remove"

## Where the store lives. `user://biz` in use; a test points it somewhere of its own.
var root: String
## from_version -> Callable(body: Dictionary) -> Dictionary. Empty until a schema changes, at which
## point a `1 -> 2` step is registered here and old records start reading again.
var _upcasters: Dictionary = {}


func _init(root_path: String = ROOT) -> void:
	root = root_path


# --- what is a kind, and where does a record of it live ------------------------------------------


static func is_known_kind(kind: String) -> bool:
	if kind == JOB_KIND:
		return true
	return JOB_KINDS.has(kind) or FLAT_FOLDERS.has(kind)


## The folder a record of this kind lives in. A job-level kind with no job named has no folder, which
## is a refusal the caller turns into a sentence rather than an empty string it writes to.
func folder_for(kind: String, job_id: String = "") -> String:
	if kind == JOB_KIND:
		return root.path_join("jobs")
	if JOB_KINDS.has(kind):
		if _safe_id(job_id).is_empty():
			return ""
		return root.path_join("jobs").path_join(_safe_id(job_id)).path_join(kind)
	if FLAT_FOLDERS.has(kind):
		return root.path_join(FLAT_FOLDERS[kind])
	return ""


## The file one record lives in (§11.1): a job is `jobs/<id>/job.json`, a job-level record is
## `jobs/<job>/<kind>/<id>.json`, a flat one is `leads/<id>.json` or `crew/<id>.json`.
func record_path(kind: String, id: String, job_id: String = "") -> String:
	if kind == JOB_KIND:
		if _safe_id(id).is_empty():
			return ""
		return root.path_join("jobs").path_join(_safe_id(id)).path_join("job.json")
	var folder: String = folder_for(kind, job_id)
	if folder.is_empty():
		return ""
	var safe_id: String = _safe_id(id)
	if safe_id.is_empty():
		return ""
	return folder.path_join(safe_id + ".json")


## A record id is a file name, so it has to be one a person could type and a filesystem would take: a
## separator, a `..` or a leading dot is refused rather than silently mangled, because an id that is
## quietly a different id is the failure §15.7 records in another guise.
static func _safe_id(id: String) -> String:
	var trimmed: String = id.strip_edges()
	if trimmed.is_empty():
		return ""
	if trimmed.contains("/") or trimmed.contains("\\"):
		return ""
	if trimmed.contains("..") or trimmed.begins_with("."):
		return ""
	return trimmed


## The reason a record cannot be filed where it was asked to be, or `""` if it can. Kept in one place
## so every door refuses in the same words.
func _place_problem(kind: String, id: String, job_id: String) -> String:
	if not is_known_kind(kind):
		return "'%s' is not a kind of record this store keeps" % kind
	if _safe_id(id).is_empty():
		return "'%s' is not a name a record can be filed under" % id
	if JOB_KINDS.has(kind) and _safe_id(job_id).is_empty():
		return "a %s belongs to a job, and no job was named" % kind
	return ""


# --- writing ------------------------------------------------------------------------------------


## Write a record, naming the revision it was expected to be at. Returns
## `{ok, reason, rev, conflict}`.
##
## `expected_rev` of `-1` means the caller is not claiming a revision; any other value is a claim, and
## a record that is not at that revision is refused with `conflict` set, which is what a sync layer
## looks for. `who`, `at` and `note` are for the journal, so an edit is attributable without the store
## reading anything it was not told.
func put(
	kind: String,
	id: String,
	body: Dictionary,
	job_id: String = "",
	expected_rev: int = -1,
	who: String = "",
	at: int = 0,
	note: String = ""
) -> Dictionary:
	var problem: String = _place_problem(kind, id, job_id)
	if not problem.is_empty():
		return _refused(problem)
	var path: String = record_path(kind, id, job_id)
	var existing_rev: int = 0
	var before: Dictionary = {}
	if FileAccess.file_exists(path):
		var read: Dictionary = _read_envelope(path)
		if not bool(read["ok"]):
			return _refused(
				"the record already at %s cannot be read, so it will not be written over: %s"
				% [path.get_file(), String(read["reason"])]
			)
		var held: Dictionary = read["envelope"]
		existing_rev = int(held.get("rev", 0))
		var held_body: Variant = held.get("body", {})
		if held_body is Dictionary:
			before = held_body
	if expected_rev >= 0 and expected_rev != existing_rev:
		return {
			"ok": false,
			"reason": _conflict_words(kind, id, expected_rev, existing_rev),
			"rev": existing_rev,
			"conflict": true,
		}
	var new_rev: int = existing_rev + 1
	var wire: Dictionary = {
		"kind": kind,
		"id": id,
		"job": job_id,
		"rev": new_rev,
		"schema_version": SCHEMA_VERSION,
		"body": body,
	}
	var wrote: Dictionary = _write_envelope(path, wire)
	if not bool(wrote["ok"]):
		return _refused(String(wrote["reason"]))
	_append_journal({
		"at": at,
		"who": who,
		"kind": kind,
		"id": id,
		"job": job_id,
		"action": PUT_ACTION,
		"rev": new_rev,
		"before_rev": existing_rev,
		"changed": _changed(before, body),
		"note": note,
	})
	return {"ok": true, "reason": "", "rev": new_rev, "conflict": false}


## Write a record exactly as the service handed it over, at the revision the service gave it - the
## write half of the pull in §11.2. No revision is bumped and no claim is checked, because on a pull
## the server's revision *is* the truth; the journal records that it arrived rather than that somebody
## made it.
func apply(record_env: Dictionary, who: String = "", at: int = 0) -> Dictionary:
	var kind: String = String(record_env.get("kind", ""))
	var id: String = String(record_env.get("id", ""))
	var job_id: String = String(record_env.get("job", ""))
	var problem: String = _place_problem(kind, id, job_id)
	if not problem.is_empty():
		return _refused(problem)
	var path: String = record_path(kind, id, job_id)
	var wrote: Dictionary = _write_envelope(path, record_env)
	if not bool(wrote["ok"]):
		return _refused(String(wrote["reason"]))
	_append_journal({
		"at": at,
		"who": who,
		"kind": kind,
		"id": id,
		"job": job_id,
		"action": PULL_ACTION,
		"rev": int(record_env.get("rev", 0)),
		"before_rev": 0,
		"changed": [],
		"note": "applied from the service",
	})
	return {"ok": true, "reason": "", "rev": int(record_env.get("rev", 0))}


## Take a record away. The journal keeps the fact, because a deletion is a change like any other and a
## sync queue has to be able to hand it on.
func discard(
	kind: String,
	id: String,
	job_id: String = "",
	who: String = "",
	at: int = 0,
	note: String = ""
) -> Dictionary:
	var problem: String = _place_problem(kind, id, job_id)
	if not problem.is_empty():
		return _refused(problem)
	var path: String = record_path(kind, id, job_id)
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "there is no %s filed as '%s'" % [kind, id], "rev": 0}
	var last_rev: int = 0
	var read: Dictionary = _read_envelope(path)
	if bool(read["ok"]):
		last_rev = int((read["envelope"] as Dictionary).get("rev", 0))
	var error: int = DirAccess.remove_absolute(path)
	if error != OK:
		return _refused("cannot take %s away: %s" % [path.get_file(), error_string(error)])
	_append_journal({
		"at": at,
		"who": who,
		"kind": kind,
		"id": id,
		"job": job_id,
		"action": REMOVE_ACTION,
		"rev": last_rev + 1,
		"before_rev": last_rev,
		"changed": [],
		"note": note,
	})
	return {"ok": true, "reason": "", "rev": last_rev + 1}


# --- reading ------------------------------------------------------------------------------------


## Read one record back, upcast to this build's schema. A missing record is `found: false` so a caller
## can tell "there is none" from "it will not read".
func fetch(kind: String, id: String, job_id: String = "") -> Dictionary:
	var problem: String = _place_problem(kind, id, job_id)
	if not problem.is_empty():
		return _missing(problem)
	var path: String = record_path(kind, id, job_id)
	if not FileAccess.file_exists(path):
		return _missing("there is no %s filed as '%s'" % [kind, id])
	var read: Dictionary = _read_envelope(path)
	if not bool(read["ok"]):
		return {
			"ok": false,
			"reason": String(read["reason"]),
			"found": true,
			"rev": 0,
			"schema_version": 0,
			"body": {},
		}
	var held: Dictionary = read["envelope"]
	var stored: int = int(held.get("schema_version", SCHEMA_VERSION))
	var body: Dictionary = {}
	var held_body: Variant = held.get("body", {})
	if held_body is Dictionary:
		body = held_body
	var migrated: Dictionary = upcast(stored, body)
	if not bool(migrated["ok"]):
		return {
			"ok": false,
			"reason": String(migrated["reason"]),
			"found": true,
			"rev": int(held.get("rev", 0)),
			"schema_version": stored,
			"body": {},
		}
	return {
		"ok": true,
		"reason": "",
		"found": true,
		"rev": int(held.get("rev", 0)),
		"schema_version": SCHEMA_VERSION,
		"body": migrated["body"],
	}


func holds(kind: String, id: String, job_id: String = "") -> bool:
	if not _place_problem(kind, id, job_id).is_empty():
		return false
	return FileAccess.file_exists(record_path(kind, id, job_id))


## Every readable record of one kind, by id in name order - a job listing and a lead listing alike. A
## record that will not read is left out rather than half-handed to a caller; `problems()` is what
## names it.
func records(kind: String, job_id: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var folder: String = folder_for(kind, job_id)
	if folder.is_empty():
		return out
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		return out
	var ids: Array[String] = []
	if kind == JOB_KIND:
		# A job's own file lives in its own folder, so the folders are the ids here.
		for subfolder in dir.get_directories():
			ids.append(String(subfolder))
	else:
		for file_name in dir.get_files():
			var held: String = String(file_name)
			if not held.ends_with(".json"):
				continue
			ids.append(held.substr(0, held.length() - 5))
	ids.sort()
	for id in ids:
		var read: Dictionary = fetch(kind, id, job_id)
		if not bool(read["ok"]):
			continue
		out.append({
			"id": id,
			"rev": int(read["rev"]),
			"schema_version": int(read["schema_version"]),
			"body": read["body"],
		})
	return out


## One record as the wire form §11.2 sends and receives: the body, the revision, the schema, and
## whether it is a tombstone.
func envelope(kind: String, id: String, job_id: String = "") -> Dictionary:
	var read: Dictionary = fetch(kind, id, job_id)
	if not bool(read["ok"]):
		return {"ok": false, "reason": String(read["reason"]), "envelope": {}}
	return {
		"ok": true,
		"reason": "",
		"envelope": {
			"kind": kind,
			"id": id,
			"job": job_id,
			"rev": int(read["rev"]),
			"schema_version": SCHEMA_VERSION,
			"body": read["body"],
			"deleted": false,
		},
	}


# --- the journal --------------------------------------------------------------------------------


## Where an entry written for this moment goes: one file a month, so an append to a past month never
## happens. A moment nobody stated is filed as undated rather than dated to the epoch.
func journal_path(at: int) -> String:
	var suffix: String = "undated"
	if at > 0:
		var parts: Dictionary = Time.get_datetime_dict_from_unix_time(at)
		suffix = "%04d-%02d" % [int(parts["year"]), int(parts["month"])]
	return root.path_join(JOURNAL_FOLDER).path_join("events-%s.jsonl" % suffix)


## Every journal entry, oldest file first and in the order written. A line that will not parse is left
## out; `problems()` names it.
func journal() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var folder: String = root.path_join(JOURNAL_FOLDER)
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		return out
	var names: Array[String] = []
	for file_name in dir.get_files():
		var held: String = String(file_name)
		if held.ends_with(".jsonl"):
			names.append(held)
	names.sort()
	for held in names:
		_read_journal_file(folder.path_join(held), out)
	return out


## What the journal says about one record - the audit trail §2.12 asks for, in the order it happened.
func history(kind: String, id: String, job_id: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in journal():
		if String(entry.get("kind", "")) != kind:
			continue
		if String(entry.get("id", "")) != id:
			continue
		if not job_id.is_empty() and String(entry.get("job", "")) != job_id:
			continue
		out.append(entry)
	return out


# --- schema versioning --------------------------------------------------------------------------


## Register the step that brings a `from_version` record up to `from_version + 1`. Refused for a
## version at or above this build's schema (there is nothing to step to) and for a step that is not
## callable, because a half-registered upcaster is a record that migrates to nothing.
func register_upcaster(from_version: int, step: Callable) -> bool:
	if from_version < 1 or from_version >= SCHEMA_VERSION:
		return false
	if not step.is_valid():
		return false
	if _upcasters.has(from_version):
		return false
	_upcasters[from_version] = step
	return true


## Bring a stored body up to this build's schema. A newer record is refused naming both numbers - it
## is not half-read - and an old one with no step to carry it forward is refused naming the missing
## step, rather than being handed to a caller as if it were current.
##
## `target` is the version to bring it up to, and defaults to this build's. It exists for the test that
## proves a step actually migrates a body: a build sitting at schema 1 has no step it could ship, and a
## step that is never exercised is a step that will be wrong the first time it matters.
func upcast(stored_version: int, body: Dictionary, target: int = SCHEMA_VERSION) -> Dictionary:
	if stored_version > target:
		return {
			"ok": false,
			"reason": "this record was written by a newer version of the program (schema %d; this build understands %d)"
				% [stored_version, SCHEMA_VERSION],
			"body": {},
			"from": stored_version,
			"to": stored_version,
		}
	var version: int = stored_version
	var work: Dictionary = body
	while version < target:
		if not _upcasters.has(version):
			return {
				"ok": false,
				"reason": "there is no way here to bring a schema %d record up to %d" % [version, version + 1],
				"body": {},
				"from": version,
				"to": version,
			}
		var step: Callable = _upcasters[version]
		var result: Variant = step.call(work)
		if result is Dictionary:
			work = result
		version += 1
	return {"ok": true, "reason": "", "body": work, "from": stored_version, "to": version}


# --- health -------------------------------------------------------------------------------------


## Everything wrong with the files themselves: a journal line that will not parse, a record that will
## not read, a record with no revision or no schema. Empty means the store reads.
func problems() -> Array[String]:
	var out: Array[String] = []
	var folder: String = root.path_join(JOURNAL_FOLDER)
	var dir: DirAccess = DirAccess.open(folder)
	if dir != null:
		for file_name in dir.get_files():
			var held: String = String(file_name)
			if not held.ends_with(".jsonl"):
				continue
			_check_journal_file(folder.path_join(held), out)
	for path in _all_record_paths():
		var read: Dictionary = _read_envelope(path)
		if not bool(read["ok"]):
			out.append(String(read["reason"]))
			continue
		var held_env: Dictionary = read["envelope"]
		if int(held_env.get("rev", 0)) < 1:
			out.append("%s carries no revision" % path.get_file())
		if not held_env.has("schema_version"):
			out.append("%s does not say which schema wrote it" % path.get_file())
	return out


func describe() -> String:
	return "the records under %s: %d kept, %d journal entries" % [
		root, _all_record_paths().size(), journal().size()
	]


# --- files --------------------------------------------------------------------------------------


func _write_envelope(path: String, record_env: Dictionary) -> Dictionary:
	var folder: String = path.get_base_dir()
	if not _ensure_folder(folder):
		return {"ok": false, "reason": "cannot open %s" % folder}
	var temp: String = path + TEMP_SUFFIX
	var file: FileAccess = FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "reason": "cannot write %s" % temp.get_file()}
	file.store_string(JSON.stringify(record_env, "  "))
	file.close()
	var error: int = DirAccess.rename_absolute(temp, path)
	if error != OK:
		DirAccess.remove_absolute(temp)
		return {"ok": false, "reason": "cannot put %s in place: %s" % [path.get_file(), error_string(error)]}
	return {"ok": true, "reason": ""}


func _read_envelope(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "there is no record at %s" % path, "envelope": {}}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "reason": "cannot read %s" % path.get_file(), "envelope": {}}
	var text: String = file.get_as_text()
	file.close()
	# Parsed with a reader rather than `JSON.parse_string`, which logs an engine error to the console
	# when it fails: a person is being told in a sentence what is wrong.
	var reader := JSON.new()
	if reader.parse(text) != OK:
		return {
			"ok": false,
			"reason": "%s is not readable: %s (line %d)" % [
				path.get_file(), reader.get_error_message(), reader.get_error_line()
			],
			"envelope": {},
		}
	var data: Variant = reader.data
	if not data is Dictionary:
		return {"ok": false, "reason": "%s is not a record" % path.get_file(), "envelope": {}}
	return {"ok": true, "reason": "", "envelope": (data as Dictionary)}


func _append_journal(entry: Dictionary) -> bool:
	var path: String = journal_path(int(entry.get("at", 0)))
	var folder: String = path.get_base_dir()
	if not _ensure_folder(folder):
		return false
	var file: FileAccess = null
	if FileAccess.file_exists(path):
		file = FileAccess.open(path, FileAccess.READ_WRITE)
		if file == null:
			return false
		file.seek_end()
	else:
		file = FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return false
	file.store_line(JSON.stringify(entry))
	file.close()
	return true


func _read_journal_file(path: String, out: Array[Dictionary]) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var text: String = file.get_as_text()
	file.close()
	for line in text.split("\n"):
		var trimmed: String = String(line).strip_edges()
		if trimmed.is_empty():
			continue
		var reader := JSON.new()
		if reader.parse(trimmed) != OK:
			continue
		var data: Variant = reader.data
		if data is Dictionary:
			out.append(data)


func _check_journal_file(path: String, out: Array[String]) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		out.append("cannot read %s" % path.get_file())
		return
	var text: String = file.get_as_text()
	file.close()
	var number: int = 0
	for line in text.split("\n"):
		number += 1
		var trimmed: String = String(line).strip_edges()
		if trimmed.is_empty():
			continue
		var reader := JSON.new()
		if reader.parse(trimmed) != OK:
			out.append("%s line %d will not read as a journal entry" % [path.get_file(), number])


func _all_record_paths() -> Array[String]:
	var out: Array[String] = []
	var jobs_dir: String = root.path_join("jobs")
	var dir: DirAccess = DirAccess.open(jobs_dir)
	if dir != null:
		for subfolder in dir.get_directories():
			var id: String = String(subfolder)
			var job_file: String = jobs_dir.path_join(id).path_join("job.json")
			if FileAccess.file_exists(job_file):
				out.append(job_file)
			for kind in JOB_KINDS:
				_collect_json(jobs_dir.path_join(id).path_join(kind), out)
	for kind in FLAT_FOLDERS:
		_collect_json(root.path_join(FLAT_FOLDERS[kind]), out)
	return out


static func _collect_json(folder: String, out: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		return
	for file_name in dir.get_files():
		var held: String = String(file_name)
		if held.ends_with(".json"):
			out.append(folder.path_join(held))


static func _ensure_folder(folder: String) -> bool:
	if DirAccess.open(folder) != null:
		return true
	return DirAccess.make_dir_recursive_absolute(folder) == OK


# --- the journal's diff -------------------------------------------------------------------------


## What changed between two bodies, one entry per field, in name order - a deterministic diff so the
## journal of a given edit is the same list every run. A value shaped like money is written as its
## integer `cents`, because a price change is the change somebody will be asked about.
static func _changed(before: Dictionary, after: Dictionary) -> Array[Dictionary]:
	var fields: Array[String] = []
	for key in before:
		var held: String = String(key)
		if not fields.has(held):
			fields.append(held)
	for key in after:
		var held: String = String(key)
		if not fields.has(held):
			fields.append(held)
	fields.sort()
	var out: Array[Dictionary] = []
	for field in fields:
		var was: Variant = before.get(field)
		var now: Variant = after.get(field)
		if was == now:
			continue
		out.append({"field": field, "before": _flatten(was), "after": _flatten(now)})
	return out


static func _flatten(value: Variant) -> Variant:
	if value is Dictionary:
		var held: Dictionary = value
		if held.has("cents") and held.has("currency"):
			return int(held["cents"])
	return value


static func _conflict_words(kind: String, id: String, expected: int, actual: int) -> String:
	if actual == 0:
		return "this %s '%s' was expected at revision %d, but there is nothing here" % [kind, id, expected]
	return "this %s '%s' was expected at revision %d, but it has moved to %d" % [kind, id, expected, actual]


static func _refused(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "rev": 0, "conflict": false}


static func _missing(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "found": false, "rev": 0, "schema_version": 0, "body": {}}