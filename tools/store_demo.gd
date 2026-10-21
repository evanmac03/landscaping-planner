extends Node2D
## A live pass over the **record store**: a job filed, an invoice filed under it, a price changed, a
## stale writer refused, and the journal read back to show what changed and when (spec §11.1, §11.6,
## §2.12).
##
## This is a development tool, not part of the game. It drives the real `BizStore` and prints what it
## found, so a person can see the layout on disk and the audit trail rather than take either on trust.
##
## It writes to `user://demo_store` and nothing in the game reads it; the folder is wiped first so the
## run reads the same every time. Run `res://scenes/store_demo.tscn`.

const StoreScript := preload("res://scripts/biz/store.gd")

const ROOT := "user://demo_store"

## A moment stated rather than read off the clock, the way every figure in this module is (see the
## store's own note on why). A June morning and a July morning.
const FIRST_MOMENT := 1780000000
const LATER_MOMENT := 1782600000

var _store: StoreScript


func _ready() -> void:
	_wipe(ROOT)
	_store = StoreScript.new(ROOT)

	print("--- the store ---")
	print(_store.describe())
	print("a job lives at ", _store.record_path(StoreScript.JOB_KIND, "J-1001"))
	print("an invoice lives at ", _store.record_path("invoice", "INV-77", "J-1001"))

	print("")
	print("--- the office files a job and an invoice ---")
	var job := {"number": "J-1001", "label": "Smith, back garden", "contract_sum": {"cents": 428400, "currency": "CAD"}}
	var filed_job: Dictionary = _store.put(StoreScript.JOB_KIND, "J-1001", job, "", -1, "evan", FIRST_MOMENT, "the job was opened")
	print("the job was filed: ", filed_job["ok"], " at revision ", filed_job["rev"])

	var invoice := {
		"number": "INV-2026-0001",
		"job": "J-1001",
		"amount": {"cents": 128500, "currency": "CAD"},
		"notes": "first draw on the patio",
	}
	var filed_invoice: Dictionary = _store.put("invoice", "INV-77", invoice, "J-1001", -1, "evan", FIRST_MOMENT, "raised")
	print("the invoice was filed: ", filed_invoice["ok"], " at revision ", filed_invoice["rev"])

	print("")
	print("--- a price is changed, and the journal records the before and the after ---")
	var repriced: Dictionary = invoice.duplicate(true)
	repriced["amount"] = {"cents": 135000, "currency": "CAD"}
	repriced["notes"] = "first draw on the patio and the walk"
	var changed_back: Dictionary = _store.put("invoice", "INV-77", repriced, "J-1001", int(filed_invoice["rev"]), "evan", LATER_MOMENT, "the walk joined the first draw")
	print("the change was taken: ", changed_back["ok"], " at revision ", changed_back["rev"])
	for entry in _store.history("invoice", "INV-77"):
		print("  ", _entry_text(entry))

	print("")
	print("--- a writer that has been offline is refused rather than allowed to clobber ---")
	var stale: Dictionary = _store.put("invoice", "INV-77", invoice, "J-1001", 1, "sam", LATER_MOMENT, "a stale edit")
	print("the stale write was refused: ", not stale["ok"], " - ", stale["reason"])
	print("and the record is still at revision ", _store.fetch("invoice", "INV-77", "J-1001")["rev"])

	print("")
	print("--- the invoice read back, and the folder it now sits in ---")
	var read: Dictionary = _store.fetch("invoice", "INV-77", "J-1001")
	print("read back at revision ", read["rev"], ", schema ", read["schema_version"])
	print("its amount is ", read["body"]["amount"]["cents"], " cents and its note is \"", read["body"]["notes"], "\"")
	print("the jobs the store holds: ", _record_ids(_store.records(StoreScript.JOB_KIND)))
	print("the invoices filed under J-1001: ", _record_ids(_store.records("invoice", "J-1001")))

	print("")
	print("--- what the schema guards refuse ---")
	print(
		"registering a step to the current schema is refused: ",
		not _store.register_upcaster(StoreScript.SCHEMA_VERSION, func(body: Dictionary) -> Dictionary: return body)
	)
	var from_a_newer: Dictionary = _store.upcast(StoreScript.SCHEMA_VERSION + 1, {})
	print("a record from a newer schema is refused: ", not from_a_newer["ok"], " - ", from_a_newer["reason"])

	print("")
	print("--- the store reads ---")
	print("problems: ", _store.problems())
	print(_store.describe())


func _record_ids(rows: Array[Dictionary]) -> Array:
	var out: Array = []
	for row in rows:
		out.append(row["id"])
	return out


func _entry_text(entry: Dictionary) -> String:
	var out: String = "%s %s by %s" % [entry["action"], entry["id"], entry["who"]]
	var changed: Variant = entry.get("changed", [])
	if changed is Array and not (changed as Array).is_empty():
		var pairs: Array = []
		for field in (changed as Array):
			pairs.append("%s %s -> %s" % [field["field"], _word(field["before"]), _word(field["after"])])
		out += " (" + ", ".join(PackedStringArray(pairs)) + ")"
	if not String(entry.get("note", "")).is_empty():
		out += ": " + String(entry["note"])
	return out


func _word(value: Variant) -> String:
	if value == null:
		return "nothing"
	return str(value)


## Take the demo folder away so each run reads the same. A tool's own scratch space, so a blunt wipe
## is right here; nothing in the game is under this path.
func _wipe(folder: String) -> void:
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		return
	for file_name in dir.get_files():
		DirAccess.remove_absolute(folder.path_join(String(file_name)))
	for subfolder in dir.get_directories():
		_wipe(folder.path_join(String(subfolder)))
	DirAccess.remove_absolute(folder)