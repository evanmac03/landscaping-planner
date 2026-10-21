class_name LedgerPush
extends RefCounted
## One attempt to hand a document to a ledger, and what came of it (REQ-B14, spec §9.7).
##
## REQ-B14 says an invoice issues and prints whether or not a ledger is configured, and that the push
## is a **queued, retryable, idempotent action with a visible state**. This record is that state: it
## holds the request that was built, how many times it has been tried, and what the last attempt said.
##
## **The state is a function of what happened, not a field somebody set.** Nothing tried is queued; a
## try the ledger did not take is failed once it is no longer worth retrying; something accepted has a
## `pushed_at`. `to_dict` writes the state for whoever reads the file and `from_dict` ignores it,
## exactly as `Invoice` does: a stored state would be a second place the truth lives.
##
## **The request is stored, not rebuilt.** A retry sends byte-for-byte what the first attempt sent,
## which is the whole basis of AC-B15 - a retry that rebuilt its body could send a different document
## if the invoice moved under it, and the key would de-duplicate the wrong things.
##
## A retryable failure (the server was busy, the request timed out) stays **queued** and will go again;
## a refusal, or too many attempts, becomes **failed**, which is a thing a person is told about. The
## office is never the silent recipient of a document that did not arrive.

const QUEUED := 0
const PUSHED := 1
const FAILED := 2

## String keys: a StringName literal as a const Dictionary key fails the constant-expression check.
const STATE_NAMES := {
	"QUEUED": "queued",
	"PUSHED": "pushed",
	"FAILED": "failed",
}

## How many times a push may be tried before it stops being an automatic retry and becomes something
## the office has to look at. A backend that has refused the same document five times will refuse it
## the sixth, and a queue that retries forever is a queue nobody notices is stuck.
const MAX_ATTEMPTS := 5

const AdapterScript := preload("res://scripts/biz/ledger_adapter.gd")

var adapter: String = ""
var kind: StringName = &""
var document_id: String = ""
var document_number: String = ""
## The idempotency key. It is also this record's identity: one push per document per backend, so the
## same invoice cannot be queued twice and a retry is a retry rather than a second posting.
var key: String = ""
var request: Dictionary = {}
var attempts: int = 0
var queued_at: String = ""
var pushed_at: String = ""
var failure: String = ""
var last_status: int = 0
## Whether the last failure was worth retrying. Not derivable from the status alone by a reader, and
## the difference between a push that waits and one that asks for a person.
var last_retryable: bool = false
var last_response: Dictionary = {}
var external_id: String = ""
var external_number: String = ""


## A push for a document that was just built. Refuses nothing: `problems()` is how a caller asks
## whether it is worth queueing, so a build that leaves something out is visible rather than thrown.
static func for_document(adapter_name: String, document_kind: StringName, doc_id: String,
		doc_number: String, idempotency_key: String, built_request: Dictionary,
		at: String) -> LedgerPush:
	var push: LedgerPush = PushScript.new()
	push.adapter = adapter_name
	push.kind = document_kind
	push.document_id = doc_id
	push.document_number = doc_number
	push.key = idempotency_key
	push.request = built_request.duplicate(true)
	push.queued_at = at
	return push


func state_name() -> String:
	return String(STATE_NAMES.get(_state_key(state()), "queued"))


func is_pushed() -> bool:
	return not pushed_at.strip_edges().is_empty()


## Whether this push will go again on its own: it has not been taken, it has not been tried too often,
## and the last failure was the kind that a retry actually helps with.
func can_retry() -> bool:
	if is_pushed() or attempts >= MAX_ATTEMPTS:
		return false
	if attempts == 0:
		return true
	return last_retryable


## Whether somebody has to look at this. A refusal is now; a busy server is only once "try again" has
## stopped being advice, which is what `can_retry` already answers.
func needs_a_person() -> bool:
	if is_pushed() or attempts == 0:
		return false
	return not can_retry()


## The state, read off the records.
func state() -> int:
	if is_pushed():
		return PUSHED
	if needs_a_person():
		return FAILED
	return QUEUED


func attempt_count() -> int:
	return attempts


## Record the outcome of one attempt. `parsed` is the adapter's own reading of the response. Returns
## whether the ledger took it.
func record_response(response: Dictionary, parsed: Dictionary, at: String) -> bool:
	attempts += 1
	last_status = int(response.get("status", 0))
	last_response = response.duplicate(true)
	last_retryable = bool(parsed.get("retry", false))
	var took_it: bool = bool(parsed.get("ok", false))
	if took_it:
		pushed_at = at
		failure = ""
		external_id = String(parsed.get("external_id", ""))
		external_number = String(parsed.get("external_number", ""))
		return true
	failure = String(parsed.get("reason", "the ledger did not say why"))
	return false


# --- soundness ----------------------------------------------------------------------------------


func problems() -> Array[String]:
	var out: Array[String] = []
	if adapter.strip_edges().is_empty():
		out.append("a push that names no ledger")
	if kind == &"":
		out.append("a push with no document kind")
	if document_id.strip_edges().is_empty():
		out.append("a push for no document")
	if key.strip_edges().is_empty():
		out.append("a push with no idempotency key, so a retry would post the document twice")
	if request.is_empty():
		out.append("a push with nothing to send")
	elif String(request.get("url", "")).strip_edges().is_empty():
		out.append("a push whose request goes nowhere")
	return out


func is_sound() -> bool:
	return problems().is_empty()


func describe() -> String:
	var parts := PackedStringArray()
	parts.append(state_name())
	parts.append("%s to %s" % [String(AdapterScript.KIND_NAMES.get(String(kind), "a document")), adapter])
	if not document_number.strip_edges().is_empty():
		parts.append(document_number)
	if attempts > 0:
		parts.append("try %d of %d" % [attempts, MAX_ATTEMPTS])
	if is_pushed():
		parts.append("as %s" % external_number if not external_number.strip_edges().is_empty() else "accepted")
	if not failure.strip_edges().is_empty():
		parts.append(failure)
	return ", ".join(parts)


# --- persistence --------------------------------------------------------------------------------


func to_dict() -> Dictionary:
	return {
		"adapter": adapter,
		"kind": String(kind),
		"document_id": document_id,
		"document_number": document_number,
		"key": key,
		"request": request.duplicate(true),
		"attempts": attempts,
		"queued_at": queued_at,
		"pushed_at": pushed_at,
		"failure": failure,
		"last_status": last_status,
		"last_retryable": last_retryable,
		"last_response": last_response.duplicate(true),
		"external_id": external_id,
		"external_number": external_number,
		# Written for whoever reads the file. `from_dict` ignores it: the state is a function of the
		# records, and a stored one would be a second place the truth lives.
		"state": state_name(),
	}


## A record with no key is **dropped rather than invented**: the key is this record's identity, so a
## push without one cannot be de-duplicated and must not be queued.
static func from_dict(data: Dictionary) -> LedgerPush:
	var push: LedgerPush = PushScript.new()
	push.key = String(data.get("key", ""))
	if push.key.strip_edges().is_empty():
		return null
	push.adapter = String(data.get("adapter", ""))
	push.kind = StringName(data.get("kind", ""))
	push.document_id = String(data.get("document_id", ""))
	push.document_number = String(data.get("document_number", ""))
	var request_in: Variant = data.get("request", {})
	push.request = (request_in as Dictionary).duplicate(true) if request_in is Dictionary else {}
	push.attempts = int(data.get("attempts", 0))
	push.queued_at = String(data.get("queued_at", ""))
	push.pushed_at = String(data.get("pushed_at", ""))
	push.failure = String(data.get("failure", ""))
	push.last_status = int(data.get("last_status", 0))
	push.last_retryable = bool(data.get("last_retryable", false))
	var response_in: Variant = data.get("last_response", {})
	push.last_response = (response_in as Dictionary).duplicate(true) if response_in is Dictionary else {}
	push.external_id = String(data.get("external_id", ""))
	push.external_number = String(data.get("external_number", ""))
	return push


static func _state_key(state_key: int) -> String:
	match state_key:
		PUSHED:
			return "PUSHED"
		FAILED:
			return "FAILED"
	return "QUEUED"


const PushScript := preload("res://scripts/biz/ledger_push.gd")