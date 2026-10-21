class_name BizSync
extends RefCounted
## The sync of the local store with a service, and the conflict policy (spec §11.2-§11.5).
##
## The service is small and boring on purpose (§11.2) and the client around it is the same shape: **pull
## then push**, idempotent, and safe to interrupt. The cursor only advances once the pull has been
## applied, so a device that has been offline for a week pulls the week and pushes its queue, and a
## device that is interrupted half way does the same thing again with the same answers.
##
## Four things here are decisions rather than plumbing.
##
## **A failed pull does not push.** If the change log cannot be read, the client does not know what the
## service holds, and pushing blind is how a device that has been offline clobbers the office. It says
## what went wrong and leaves the queue alone.
##
## **Offline first is not optional, so the queue is local and the queue is visible** (§11.5). A field
## action - a time entry, a delivery receipt, a change order - is written to the store and queued here
## whether or not there is a service to talk to, and `queue_text()` always says how many changes are
## waiting. A sync failure never blocks the next entry.
##
## **Conflicts have three policies, because money is not text** (§11.3). A changed field is classified
## by *what it holds*: a value shaped like money, or a name this module treats as money whatever it
## holds, is **never auto-merged**; a value that is a structure - lines, schedule stops - is
## record-level last-writer-wins with the other copy kept for a person to see; a descriptive field is
## last-writer-wins, because losing a note's wording is not a business event.
##
## **A money conflict stops the document being issued.** `refuses_to_issue` is the guard the billing
## and proposal doors ask before a document goes out, and it is the feature rather than a limitation: a
## silently merged price is a wrong invoice, and a wrong invoice is a legal problem, not a UI problem.
##
## A pending change is **one entry per record**, like a push per document in the outbox: two local edits
## before a sync are one change carrying the latest body and every field either edit touched. That is
## what makes `enqueue` safe to call from anywhere a record is written, and a retry a retry.

const StoreScript := preload("res://scripts/biz/store.gd")
const TransportScript := preload("res://scripts/biz/sync_transport.gd")

const STATE_PATH := "user://biz/sync/state.json"
const TEMP_SUFFIX := ".part"
const VERSION := 1
## How many times a change is tried before it wants a person rather than the queue.
const MAX_TRIES := 5

## The three policies, by what a field holds.
const TEXT := "text"
const STRUCTURE := "structure"
const MONEY := "money"
## The field names this module treats as money whatever they hold, because a rate, a quantity and an
## approval are money by another name and a silently merged one of those is the failure §11.3 is about.
const MONEY_NAMES := [
	"quantity", "quantity_milli", "rate", "loaded_rate", "markup_ppm", "tax_code", "tax",
	"contract_sum", "approval", "approved", "approved_by", "approved_at",
	"amount", "price", "unit_cost", "unit_price", "cost", "fee", "retainage",
	"total", "subtotal", "balance",
]
## What a person may choose when settling a conflict.
const OUR_COPY := "ours"
const THEIR_COPY := "theirs"

## The local records. Null is allowed - a queue with no store is still readable.
var store: BizStore = null
## Where the service is. Null means there is nowhere to sync to, which is a state and not an error.
var transport: BizSyncTransport = null
## How far the change log has been read, in the service's own numbering.
var cursor: int = 0
## What is waiting to be pushed, one entry per record.
var pending: Array[Dictionary] = []
## What could not be merged, waiting for a person.
var conflicts: Array[Dictionary] = []
## What the last run said, and whether it worked, so a page is never stale about the last answer.
var last_words: String = ""
var last_ok: bool = true
var last_run_at: int = 0
## Where the queue and the cursor are kept. `user://biz/sync/state.json` in use; a test points it
## somewhere of its own so a test never writes over the office's real queue.
var state_path: String = STATE_PATH


func _init(record_store: BizStore = null, service: BizSyncTransport = null) -> void:
	store = record_store
	transport = service


func bind(target: BizStore) -> void:
	store = target


func use_transport(candidate: BizSyncTransport) -> void:
	transport = candidate


func has_transport() -> bool:
	return transport != null and transport.is_ready()


# --- queueing a local change --------------------------------------------------------------------


## Queue a record for the service. The body is read **from the store**, so the queue holds the document
## and never a copy that could drift, and the field list is read from the journal, so the merge knows
## exactly what this device changed. Returns `{ok, reason, queued, waiting, base_rev, saved}`.
##
## Two local edits to one record before a sync are one entry: the latest body, and every field either
## edit touched, with the earliest value it was before.
func enqueue(
	kind: String,
	id: String,
	job: String = "",
	why: String = "",
	who: String = "",
	at: int = 0,
	base_rev: int = -1
) -> Dictionary:
	if store == null:
		return _refused("there is no store here to queue a change from")
	var held: Dictionary = store.fetch(kind, id, job)
	if not bool(held["ok"]):
		return _refused("cannot queue %s '%s': %s" % [kind, id, String(held["reason"])])
	var body: Dictionary = held["body"]
	var rev: int = int(held["rev"])
	var at_index: int = _pending_index(kind, id, job)
	var base: int = base_rev if base_rev >= 0 else rev - 1
	if at_index >= 0 and base_rev < 0:
		# A second local edit to one record is still one change against what the service last held, not
		# against the first edit: the base stays where the queue already had it.
		base = int(pending[at_index].get("base_rev", base))
	var changed: Array = _changed_at(kind, id, job, rev)
	if at_index >= 0:
		changed = _merge_changed(pending[at_index].get("changed", []), changed)
	var entry: Dictionary = {
		"kind": kind,
		"id": id,
		"job": job,
		"base_rev": base,
		"body": body.duplicate(true),
		"changed": changed,
		"why": why,
		"who": who,
		"at": at,
		"tries": 0,
		"last": "",
	}
	if at_index < 0:
		pending.append(entry)
	else:
		pending[at_index] = entry
	var saved: Dictionary = _persist()
	return {
		"ok": true,
		"reason": "",
		"queued": true,
		"waiting": pending.size(),
		"base_rev": base,
		"saved": bool(saved["ok"]),
	}


func waiting() -> int:
	return pending.size()


## What is waiting, in one line, so a page or a menu is never quiet about an unsent change (§11.5).
func queue_text() -> String:
	var words: String = ""
	if pending.is_empty():
		words = "nothing is waiting to sync"
	elif pending.size() == 1:
		words = "1 record change waiting to sync"
	else:
		words = "%d record changes waiting to sync" % pending.size()
	if not conflicts.is_empty():
		words += " and %d conflict%s to settle" % [conflicts.size(), "" if conflicts.size() == 1 else "s"]
	return words


func summary_text() -> String:
	if store == null:
		return "no records are bound to this sync"
	var stranded_count: int = stranded().size()
	if pending.is_empty() and conflicts.is_empty() and stranded_count == 0:
		return "nothing has changed here since the last sync"
	var parts: Array[String] = ["%d waiting" % pending.size()]
	if stranded_count > 0:
		parts.append("%d given up on" % stranded_count)
	if not conflicts.is_empty():
		parts.append("%d to settle" % conflicts.size())
	if cursor > 0:
		parts.append("read to %d" % cursor)
	return ", ".join(PackedStringArray(parts))


func pending_rows() -> Array[Dictionary]:
	return pending.duplicate(true)


func pending_row_texts() -> Array[String]:
	var out: Array[String] = []
	for entry in pending:
		var words: String = "%s '%s'" % [String(entry["kind"]), String(entry["id"])]
		if not String(entry.get("why", "")).is_empty():
			words += ": " + String(entry["why"])
		if int(entry.get("tries", 0)) > 0:
			words += " (%d tries: %s)" % [int(entry["tries"]), String(entry.get("last", ""))]
		out.append(words)
	return out


## The changes the queue has stopped trying, because five attempts is a person's problem and not the
## loop's. Kept apart from what is still being tried, the way the outbox keeps them apart.
func stranded() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in pending:
		if int(entry.get("tries", 0)) >= MAX_TRIES:
			out.append(entry)
	return out


func stranded_texts() -> Array[String]:
	var out: Array[String] = []
	for entry in stranded():
		out.append("%s '%s': %s" % [String(entry["kind"]), String(entry["id"]), String(entry.get("last", ""))])
	return out


# --- the run ------------------------------------------------------------------------------------


## Pull the change log, then push the queue. Returns a dictionary of what happened, and never changes
## the local records except to apply what the service holds.
func run(limit: int = 0, at: int = 0) -> Dictionary:
	if transport == null:
		return _stopped("there is no sync service here to talk to")
	if not transport.is_ready():
		return _stopped("the sync service is not ready: %s" % transport.describe())
	if store == null:
		return _stopped("there is no store here to sync")
	var answer: Dictionary = transport.changes(cursor, limit)
	if not bool(answer["ok"]):
		# A pull that could not be read means this device does not know what the service holds, and
		# pushing blind is exactly how an offline week clobbers the office. The queue is left alone.
		last_ok = false
		last_words = String(answer["reason"])
		last_run_at = at
		_persist()
		return {
			"ok": false,
			"reason": last_words,
			"pulled": 0,
			"applied": 0,
			"merged": 0,
			"conflicts": 0,
			"pushed": 0,
			"held": 0,
			"waiting": pending.size(),
			"stranded": stranded().size(),
			"notes": [],
		}
	var pulled: int = 0
	var applied: int = 0
	var merged: int = 0
	var made: int = 0
	var notes: Array[String] = []
	var records: Array = answer["records"]
	for held in records:
		if not held is Dictionary:
			continue
		pulled += 1
		var record: Dictionary = held
		var record_kind: String = String(record.get("kind", ""))
		var record_id: String = String(record.get("id", ""))
		var record_job: String = String(record.get("job", ""))
		var at_index: int = _pending_index(record_kind, record_id, record_job)
		if bool(record.get("deleted", false)):
			if at_index >= 0:
				# A record this device has changed and the service has taken away is a conflict, not a
				# deletion: two people disagree, and one of them gets to say so.
				conflicts.append(_disagreement(record_kind, record_id, record_job, "(the whole record)", MONEY,
					pending[at_index].get("body", {}), {}, String(pending[at_index].get("who", "")),
					int(pending[at_index].get("at", 0)), "the service", at, int(record.get("rev", 0))))
				made += 1
			elif bool(store.discard(record_kind, record_id, record_job, "the service", at)["ok"]):
				applied += 1
			continue
		if at_index < 0:
			if bool(store.apply(record, "the service", at)["ok"]):
				applied += 1
			continue
		var outcome: Dictionary = _merge_pulled(at_index, record, at)
		merged += 1
		made += int(outcome["conflicts"])
		var note: String = String(outcome["note"])
		if not note.is_empty():
			notes.append(note)
	# The cursor advances only now: everything above has been applied to the store (or folded into the
	# queue), and the state file is written after this line. A run interrupted before it repeats the
	# same pull and the same answers, because applying a record twice is applying it once.
	cursor = int(answer.get("cursor", cursor))
	var pushed: int = 0
	var held_back: int = 0
	var kept: Array[Dictionary] = []
	for entry in pending:
		var entry_kind: String = String(entry["kind"])
		var entry_id: String = String(entry["id"])
		var entry_job: String = String(entry.get("job", ""))
		if not open_conflicts(entry_kind, entry_id, entry_job).is_empty():
			# A change with an unsettled conflict does not go out: pushing ours over theirs is exactly
			# the silent merge §11.3 forbids, so it waits for a person to choose.
			kept.append(entry)
			held_back += 1
			continue
		var sent: Dictionary = transport.push(
			entry_kind, entry_id, entry_job, entry["body"], int(entry["base_rev"]), String(entry.get("who", ""))
		)
		if bool(sent["ok"]):
			# The service's revision becomes the local one, so the next change is based on it.
			store.apply({
				"kind": String(entry["kind"]),
				"id": String(entry["id"]),
				"job": String(entry.get("job", "")),
				"rev": int(sent["rev"]),
				"schema_version": StoreScript.SCHEMA_VERSION,
				"body": entry["body"],
				"deleted": false,
			}, "this device", int(entry.get("at", 0)))
			pushed += 1
			continue
		var failing: Dictionary = entry.duplicate(true)
		failing["tries"] = int(entry.get("tries", 0)) + 1
		failing["last"] = String(sent["reason"])
		if bool(sent.get("conflict", false)):
			# The service moved under this change. It cannot be merged from here - the copy it holds is
			# not in the answer - so it is a disagreement for a person, and the change stays queued.
			conflicts.append(_disagreement(
				String(failing["kind"]), String(failing["id"]), String(failing.get("job", "")),
				"(the whole record)", MONEY, failing.get("body", {}), {},
				String(failing.get("who", "")), int(failing.get("at", 0)), "the service", at,
				int(sent.get("rev", failing["base_rev"]))
			))
			made += 1
		kept.append(failing)
	pending = kept
	last_ok = true
	last_words = "%d applied, %d merged, %d pushed%s" % [
		applied, merged, pushed, "" if made == 0 else ", %d to settle" % made
	]
	last_run_at = at
	_persist()
	return {
		"ok": true,
		"reason": "",
		"pulled": pulled,
		"applied": applied,
		"merged": merged,
		"conflicts": made,
		"pushed": pushed,
		"held": held_back,
		"waiting": pending.size(),
		"stranded": stranded().size(),
		"notes": notes,
	}


# --- the conflicts ------------------------------------------------------------------------------


func conflict_texts() -> Array[String]:
	var out: Array[String] = []
	for row in conflicts:
		out.append(_conflict_words(row))
	return out


## The conflicts still open for one record - what a page about that record has to show.
func open_conflicts(kind: String, id: String, job: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in conflicts:
		if String(row["kind"]) != kind or String(row["id"]) != id:
			continue
		if not job.is_empty() and String(row.get("job", "")) != job:
			continue
		out.append(row)
	return out


## Whether a document may go out. **This is the guard, and it is the feature** (§11.3): a record with an
## unresolved money conflict refuses to issue until somebody says which value is right.
func refuses_to_issue(kind: String, id: String, job: String = "") -> bool:
	for row in open_conflicts(kind, id, job):
		if String(row["class"]) == MONEY:
			return true
	return false


## Why, in words a page can print beside the disabled button.
func refusal_words(kind: String, id: String, job: String = "") -> String:
	var open: Array[Dictionary] = open_conflicts(kind, id, job)
	if open.is_empty():
		return ""
	var money: Array[String] = []
	for row in open:
		if String(row["class"]) == MONEY:
			money.append(String(row["field"]))
	if money.is_empty():
		return ""
	return "this %s cannot go out until somebody settles %s, which two people changed" % [
		kind, ", ".join(PackedStringArray(money))
	]


## Settle a conflict by choosing a copy. The chosen value is written to the record and queued for the
## service against the revision the service holds, and the conflict is closed. **A person's choice is
## the only thing that resolves a money conflict** - nothing here guesses.
func resolve(index: int, choice: String, who: String = "", at: int = 0) -> Dictionary:
	if index < 0 or index >= conflicts.size():
		return _refused("there is no conflict here to settle")
	if choice != OUR_COPY and choice != THEIR_COPY:
		return _refused("a conflict is settled by choosing 'ours' or 'theirs'")
	if store == null:
		return _refused("there is no store here to write the settled value to")
	var row: Dictionary = conflicts[index]
	var kind: String = String(row["kind"])
	var id: String = String(row["id"])
	var job: String = String(row.get("job", ""))
	var field: String = String(row["field"])
	var chosen: Variant = row["ours"] if choice == OUR_COPY else row["theirs"]
	var held: Dictionary = store.fetch(kind, id, job)
	if not bool(held["ok"]):
		return _refused("cannot settle %s '%s': %s" % [kind, id, String(held["reason"])])
	var body: Dictionary = held["body"]
	body[field] = chosen
	var written: Dictionary = store.put(kind, id, body, job, int(held["rev"]), who, at, "settled a conflict")
	if not bool(written["ok"]):
		return _refused(String(written["reason"]))
	conflicts.remove_at(index)
	var queued: Dictionary = enqueue(kind, id, job, "settled a conflict", who, at, int(row.get("theirs_rev", -1)))
	return {
		"ok": true,
		"reason": "",
		"rev": int(written["rev"]),
		"queued": bool(queued["ok"]),
	}


# --- the state file -----------------------------------------------------------------------------


func to_dict() -> Dictionary:
	return {
		"version": VERSION,
		"cursor": cursor,
		"pending": pending.duplicate(true),
		"conflicts": conflicts.duplicate(true),
		"last_words": last_words,
		"last_ok": last_ok,
		"last_run_at": last_run_at,
	}


## Read a sync state back. A damaged row is dropped and counted rather than invented, the way every
## other record in this project is read.
static func from_dict(data: Dictionary, record_store: BizStore = null, service: BizSyncTransport = null) -> BizSync:
	var sync: BizSync = BizSync.new(record_store, service)
	sync.cursor = int(data.get("cursor", 0))
	var pending_in: Variant = data.get("pending", [])
	if pending_in is Array:
		for entry in (pending_in as Array):
			if entry is Dictionary:
				sync.pending.append(entry)
	var conflicts_in: Variant = data.get("conflicts", [])
	if conflicts_in is Array:
		for entry in (conflicts_in as Array):
			if entry is Dictionary:
				sync.conflicts.append(entry)
	sync.last_words = String(data.get("last_words", ""))
	sync.last_ok = bool(data.get("last_ok", true))
	sync.last_run_at = int(data.get("last_run_at", 0))
	return sync


## Write the state down, through a temporary file and a rename, like every other file here: a queue
## that loses its entries on a half-written save is a change nobody will ever send.
func write(path: String = STATE_PATH) -> Dictionary:
	if path.strip_edges().is_empty():
		return {"ok": false, "reason": "this sync has no file name", "path": path}
	var folder: String = path.get_base_dir()
	if DirAccess.open(folder) == null and DirAccess.make_dir_recursive_absolute(folder) != OK:
		return {"ok": false, "reason": "cannot open %s" % folder, "path": path}
	var temp: String = path + TEMP_SUFFIX
	var file: FileAccess = FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "reason": "cannot write %s" % temp.get_file(), "path": path}
	file.store_string(JSON.stringify(to_dict(), "  "))
	file.close()
	var error: int = DirAccess.rename_absolute(temp, path)
	if error != OK:
		DirAccess.remove_absolute(temp)
		return {
			"ok": false,
			"reason": "cannot put %s in place: %s" % [path.get_file(), error_string(error)],
			"path": path,
		}
	return {"ok": true, "reason": "", "path": path}


## Read the state back. A missing file is a fresh sync rather than a fault - the first run has none -
## and a file that will not read is refused with the reason and **leaves the sync alone**, because
## half-loading a queue is worse than not loading one.
func read(path: String = STATE_PATH) -> Dictionary:
	var empty := {"ok": true, "reason": "", "loaded": 0, "dropped": 0}
	if path.strip_edges().is_empty():
		return {"ok": false, "reason": "no sync state was named", "loaded": 0, "dropped": 0}
	if not FileAccess.file_exists(path):
		return empty
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "reason": "cannot read %s" % path.get_file(), "loaded": 0, "dropped": 0}
	var text: String = file.get_as_text()
	file.close()
	var reader := JSON.new()
	if reader.parse(text) != OK:
		return {
			"ok": false,
			"reason": "%s is not readable as a sync state: %s (line %d)" % [
				path.get_file(), reader.get_error_message(), reader.get_error_line()
			],
			"loaded": 0,
			"dropped": 0,
		}
	var data: Variant = reader.data
	if not data is Dictionary:
		return {"ok": false, "reason": "%s is not a sync state" % path.get_file(), "loaded": 0, "dropped": 0}
	var loaded: BizSync = BizSync.from_dict(data, store, transport)
	cursor = loaded.cursor
	pending = loaded.pending
	conflicts = loaded.conflicts
	last_words = loaded.last_words
	last_ok = loaded.last_ok
	last_run_at = loaded.last_run_at
	return {"ok": true, "reason": "", "loaded": pending.size(), "dropped": 0}


func describe() -> String:
	var where: String = "nowhere"
	if transport != null:
		where = transport.describe()
	return "the sync of %s with %s, read to %d" % [store.describe() if store != null else "nothing", where, cursor]


# --- what a field holds -------------------------------------------------------------------------


## Whether a value is money: a cents-and-currency pair, whatever it is called.
static func is_money_shape(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var held: Dictionary = value
	return held.has("cents") and held.has("currency")


## Whether two values are the same value **for the purpose of deciding a conflict** - which is not
## quite `==`, because a record read back from a file has its whole numbers as floats and its keys
## still interchangeable, and a 10000 that came out of a file is the same price as a 10000 written in
## code. Numbers are compared as numbers and structures are walked; anything else is `==`.
static func same_value(left: Variant, right: Variant) -> bool:
	if left is Dictionary and right is Dictionary:
		var ours: Dictionary = left
		var theirs: Dictionary = right
		if ours.size() != theirs.size():
			return false
		for key in ours:
			if not theirs.has(key):
				return false
			if not same_value(ours[key], theirs[key]):
				return false
		return true
	if left is Array and right is Array:
		var mine: Array = left
		var other: Array = right
		if mine.size() != other.size():
			return false
		for index in mine.size():
			if not same_value(mine[index], other[index]):
				return false
		return true
	var left_number: bool = left is int or left is float
	var right_number: bool = right is int or right is float
	if left_number and right_number:
		return float(left) == float(right)
	return left == right


## Which policy a changed field falls under, from **what it holds** first and its name second (§11.3).
## A value shaped like money, or one of the names this module treats as money, is money; a value that
## is a structure - lines, schedule stops - is structure; anything else is text.
static func class_of(field: String, before: Variant, after: Variant) -> String:
	if is_money_shape(before) or is_money_shape(after):
		return MONEY
	if MONEY_NAMES.has(field):
		return MONEY
	if before is Array or after is Array:
		return STRUCTURE
	if before is Dictionary or after is Dictionary:
		return STRUCTURE
	return TEXT


# --- the merge ----------------------------------------------------------------------------------


## Fold a pulled record into the queued change for it. Ours wins for what we changed (a text change is
## not a business event, and a structure change keeps the other copy for a person to see), a money
## change becomes a conflict that stops the document going out, and the queue is rebased onto the
## service's revision so the next push is against what the service actually holds.
func _merge_pulled(index: int, record: Dictionary, at: int) -> Dictionary:
	var entry: Dictionary = pending[index]
	var ours: Dictionary = entry.get("body", {})
	var theirs: Dictionary = {}
	var held: Variant = record.get("body", {})
	if held is Dictionary:
		theirs = held
	var theirs_rev: int = int(record.get("rev", 0))
	var theirs_who: String = String(record.get("who", "the service"))
	var theirs_at: int = int(record.get("at", at))
	var merged: Dictionary = theirs.duplicate(true)
	var notes: Array[String] = []
	var made: int = 0
	var changed: Array = entry.get("changed", [])
	for field in changed:
		if not field is Dictionary:
			continue
		var field_record: Dictionary = field
		var field_name: String = String(field_record.get("field", ""))
		var mine: Variant = ours.get(field_name)
		var other: Variant = theirs.get(field_name)
		if same_value(mine, other):
			continue
		var policy: String = class_of(field_name, field_record.get("before"), mine)
		merged[field_name] = mine
		if policy == TEXT:
			notes.append("the newer wording of '%s' was kept" % field_name)
			continue
		conflicts.append(_disagreement(
			String(entry["kind"]), String(entry["id"]), String(entry.get("job", "")), field_name, policy,
			mine, other, String(entry.get("who", "")), int(entry.get("at", 0)),
			theirs_who, theirs_at, theirs_rev
		))
		made += 1
	entry["body"] = merged
	entry["base_rev"] = theirs_rev
	if not notes.is_empty():
		return {"note": notes[0], "conflicts": made}
	return {"note": "", "conflicts": made}


## One record of two people changing one thing. It names **both values, both authors and both
## timestamps**, because that is what a person needs to choose, and the revision the service holds,
## because that is what a settled value has to be pushed against.
static func _disagreement(
	kind: String,
	id: String,
	job: String,
	field: String,
	policy: String,
	ours: Variant,
	theirs: Variant,
	ours_who: String,
	ours_at: int,
	theirs_who: String,
	theirs_at: int,
	theirs_rev: int
) -> Dictionary:
	return {
		"kind": kind,
		"id": id,
		"job": job,
		"field": field,
		"class": policy,
		"ours": ours,
		"theirs": theirs,
		"ours_who": ours_who,
		"ours_at": ours_at,
		"theirs_who": theirs_who,
		"theirs_at": theirs_at,
		"theirs_rev": theirs_rev,
	}


static func _conflict_words(row: Dictionary) -> String:
	var kind: String = String(row.get("kind", ""))
	var id: String = String(row.get("id", ""))
	var field: String = String(row.get("field", ""))
	if String(row.get("class", "")) == MONEY:
		return "this %s ('%s') has %s changed by two people - yours %s, theirs %s - and will not go out until somebody settles it" % [
			kind, id, field, _value_words(row.get("ours")), _value_words(row.get("theirs"))
		]
	return "this %s ('%s') has %s changed by two people; your copy was kept and theirs is beside it" % [
		kind, id, field
	]


static func _value_words(value: Variant) -> String:
	if is_money_shape(value):
		var held: Dictionary = value
		return "%d %s" % [int(held["cents"]), String(held["currency"])]
	return str(value)


# --- help ---------------------------------------------------------------------------------------


func _pending_index(kind: String, id: String, job: String) -> int:
	for index in pending.size():
		var entry: Dictionary = pending[index]
		if String(entry.get("kind", "")) == kind and String(entry.get("id", "")) == id and String(entry.get("job", "")) == job:
			return index
	return -1


## What this device changed in a record, read from the journal so the merge works from the same field
## list the audit trail was built from - including a money value written as its integer cents.
func _changed_at(kind: String, id: String, job: String, rev: int) -> Array:
	for entry in store.history(kind, id, job):
		if int(entry.get("rev", 0)) != rev:
			continue
		if String(entry.get("action", "")) != StoreScript.PUT_ACTION:
			continue
		var held: Variant = entry.get("changed", [])
		if held is Array:
			return held
	return []


## Fold a second local edit of one record into the first: the same field keeps the value it had before
## the *first* edit, because that is what the service is being compared against, and takes the value
## after the *last*.
static func _merge_changed(older: Array, newer: Array) -> Array:
	var out: Array = []
	for item in older:
		out.append((item as Dictionary).duplicate(true))
	for item in newer:
		if not item is Dictionary:
			continue
		var field_name: String = String((item as Dictionary).get("field", ""))
		var found: bool = false
		for existing in out:
			if String((existing as Dictionary).get("field", "")) == field_name:
				(existing as Dictionary)["after"] = (item as Dictionary).get("after")
				found = true
				break
		if not found:
			out.append((item as Dictionary).duplicate(true))
	return out


func _persist() -> Dictionary:
	return write(state_path)


func _stopped(reason: String) -> Dictionary:
	last_ok = false
	last_words = reason
	return {
		"ok": false,
		"reason": reason,
		"pulled": 0,
		"applied": 0,
		"merged": 0,
		"conflicts": 0,
		"pushed": 0,
		"held": 0,
		"waiting": pending.size(),
		"stranded": stranded().size(),
		"notes": [],
	}


static func _refused(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}