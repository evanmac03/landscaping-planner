extends Node2D
## A live pass over the **store and sync**: a change made offline and queued, a service that has moved
## under it, a money conflict that stops a document going out, the choice that settles it, and the push
## that follows (spec §11.1-§11.6).
##
## This is a development tool, not part of the game. It drives the real `BizStore`, the real `BizSync`
## and the real transport, against a **service written into this file** so the demo needs no deployment:
## what a live service does with a socket is a deployment question the specification names (§15), and
## what this shows is what the client does with the answers.
##
## It writes to `user://demo_sync_store` and `user://demo_sync`; nothing in the game reads either, and
## both are wiped first so the run reads the same every time. Run `res://scenes/sync_demo.tscn`.

const StoreScript := preload("res://scripts/biz/store.gd")
const SyncScript := preload("res://scripts/biz/sync.gd")
const TransportScript := preload("res://scripts/biz/sync_transport.gd")
const HttpScript := preload("res://scripts/biz/http_transport.gd")

const ROOT := "user://demo_sync_store"
const STATE_DIR := "user://demo_sync"
const STATE := "user://demo_sync/state.json"

## Two stated moments: a May morning, and an afternoon a colleague was also working.
const MAY := 1780000000
const LATER := 1782600000
const CAD := "CAD"


## The service, written into the demo: it holds a change log a test or a person sets by hand.
class Service extends BizSyncTransport:
	var log_to_serve: Array = []
	var cursor_to_report: int = 0
	var received: Array = []
	var answer: Dictionary = {}

	func name() -> String:
		return "the demo service"

	func is_configured() -> bool:
		return true

	func is_ready() -> bool:
		return true

	func describe() -> String:
		return "the demo service"

	func changes(_since: int = 0, _limit: int = 0) -> Dictionary:
		return {
			"ok": true,
			"status": 200,
			"retry": false,
			"reason": "",
			"cursor": cursor_to_report,
			"records": log_to_serve,
		}

	func push(kind: String, id: String, _job: String, _body: Dictionary, rev: int, who: String = "") -> Dictionary:
		received.append({"kind": kind, "id": id, "rev": rev, "who": who})
		if not answer.is_empty():
			return answer
		return {"ok": true, "status": 200, "retry": false, "conflict": false, "reason": "", "rev": rev + 1}


var _store: StoreScript
var _sync: SyncScript
var _service: Service


func _ready() -> void:
	_wipe(ROOT)
	_wipe(STATE_DIR)
	_store = StoreScript.new(ROOT)
	_service = Service.new()
	_sync = SyncScript.new(_store, _service)
	_sync.state_path = STATE

	print("--- the store and the sync ---")
	print(_store.describe())
	print(_sync.describe())
	print("the service it talks to: ", _service.describe())

	print("")
	print("--- a morning's work done offline ---")
	var invoice := {"number": "INV-2026-0001", "amount": {"cents": 128500, "currency": CAD}, "notes": "first draw"}
	print("the invoice is written locally: ", _store.put("invoice", "INV-1", invoice, "J-1", -1, "evan", MAY, "raised")["ok"])
	_sync.use_transport(null)
	print("queued with nowhere to send it: ", _sync.enqueue("invoice", "INV-1", "J-1", "raised the first draw", "evan", MAY)["ok"])
	print(_sync.queue_text())
	print("and a field change never blocks the next one: ", _store.put("time_entry", "T-1", {"minutes": 480}, "J-1", -1, "sam", MAY, "on the patio")["ok"])
	_sync.enqueue("time_entry", "T-1", "J-1", "the day on the patio", "sam", MAY)
	print(_sync.queue_text())

	print("")
	print("--- the service now has the invoice, changed by somebody else ---")
	_sync.use_transport(_service)
	_service.log_to_serve = [{
		"kind": "invoice", "id": "INV-1", "job": "J-1", "rev": 1,
		"schema_version": StoreScript.SCHEMA_VERSION, "deleted": false,
		"who": "sam", "at": LATER,
		"body": {"number": "INV-2026-0001", "amount": {"cents": 145000, "currency": CAD}, "notes": "first draw"},
	}]
	_service.cursor_to_report = 41
	var first: Dictionary = _sync.run(0, LATER)
	print("the run read ", first["pulled"], " record(s), merged ", first["merged"], ", and settled on ", first["conflicts"], " conflict(s)")
	for note in (first["notes"] as Array):
		print("  note: ", note)
	print("the cursor is now ", _sync.cursor)
	print(_sync.queue_text())

	print("")
	print("--- the document will not go out ---")
	for words in _sync.conflict_texts():
		print("  ", words)
	print("the invoice refuses to issue: ", _sync.refuses_to_issue("invoice", "INV-1", "J-1"))
	print("  ", _sync.refusal_words("invoice", "INV-1", "J-1"))
	print("the amount on disk is still ours: ", _store.fetch("invoice", "INV-1", "J-1")["body"]["amount"]["cents"])

	print("")
	print("--- a person settles it by taking the office's figure, and it goes out ---")
	var settled: Dictionary = _sync.resolve(0, SyncScript.THEIR_COPY, "evan", LATER)
	print("settled: ", settled["ok"], ", written at revision ", settled["rev"])
	print("the invoice goes out now: ", not _sync.refuses_to_issue("invoice", "INV-1", "J-1"))
	print("the amount on disk is the office's: ", _store.fetch("invoice", "INV-1", "J-1")["body"]["amount"]["cents"])
	_service.log_to_serve = []
	_service.cursor_to_report = 42
	var second: Dictionary = _sync.run(0, LATER)
	print("the second run pushed ", second["pushed"], " change(s) against ", _service.received.size(), " the service received")
	for entry in _service.received:
		print("  ", entry)

	print("")
	print("--- the state is written down, so a restart does not lose the queue ---")
	var again := SyncScript.new(_store, _service)
	again.state_path = STATE
	print("read back: ", again.read(STATE)["ok"])
	print(again.summary_text())
	print("cursor read back: ", again.cursor)

	print("")
	print("--- the real transport, and what it would send ---")
	var http: BizHttpTransport = HttpScript.new("https://sync.example.com/api/sync", "a-token")
	print(http.describe())
	print("a pull would be ", http.request_for(TransportScript.CHANGES, {"since": 0})["method"], " ", http.request_for(TransportScript.CHANGES, {"since": 0})["path"])
	print("a push would be ", http.request_for(TransportScript.PUSH, {"kind": "invoice", "id": "INV-1", "rev": 3, "body": {}})["path"])
	print("with nowhere to reach, it answers: ", HttpScript.new("http://127.0.0.1:1", "t").health()["reason"])

	print("")
	print("--- the store reads ---")
	print("problems: ", _store.problems())
	print(_store.describe())


## A tool's own scratch space, so a blunt wipe is right here; nothing in the game is under these paths.
func _wipe(folder: String) -> void:
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		return
	for file_name in dir.get_files():
		DirAccess.remove_absolute(folder.path_join(String(file_name)))
	for subfolder in dir.get_directories():
		_wipe(folder.path_join(String(subfolder)))
	DirAccess.remove_absolute(folder)