class_name LedgerDesk
extends RefCounted
## The outbox: the documents this office has handed to a ledger, and what each ledger said about them
## (REQ-B14, AC-B15, spec §9.6-§9.7).
##
## `LedgerAdapter` knows how to write one document in one backend's language. `LedgerPush` is one
## attempt at handing it over and what came of it. **This is the thing that joins them to the office's
## own records**: it knows which documents exist (from the billing desk), which backend each one is
## going to, and which of them still has to go.
##
## Five things here are decisions rather than plumbing.
##
## **One push per document per backend, and the key is the identity.** Queueing the same invoice twice
## is one push, so a retry is a retry and never a second posting - AC-B15, and the reason
## `queue_invoice` is safe to call from anywhere a document is raised.
##
## **The request is built once, when the document is queued, and never rebuilt** (REQ-B14). A retry
## sends what the first attempt sent, and nothing here re-derives the document from the invoice - which
## is the guarantee that matters, because an invoice edited after issue would otherwise let a retry send
## a different document under the same key. Read back from the file, whole numbers arrive as floats
## (that is what a JSON round trip does to them) and every backend reads `60512.0` and `60512` as the
## same number.
##
## **The desk never writes a document.** An invoice belongs to the billing desk, a credit note to
## whoever issued it; the outbox only carries a copy of the request. Nothing here can move money.
##
## **What the queue will try again and what wants a person are two different lists.** `pending()` is
## what the queue still owns; `stranded()` is what it has given up on. A page showing one list would
## hide the document that is never going to arrive, which is exactly the silence REQ-B14 forbids.
##
## **The outbox is written down, because an outbox that forgets is not one.** A failed push that
## vanished when the program closed would be the same silent non-delivery by another route. `write`
## and `read` keep it in `user://biz/outbox.json` through a temporary file and a rename, the way a
## drawing is saved. **Adapters are not written down**, and neither is a credential: `settings()` says
## which of a backend's fields is a secret, and a file sitting behind a drawing is not where a token
## belongs. A stored request keeps its document byte for byte and has its authentication header
## blanked; `LedgerAdapter.authorise` puts it back at the moment of sending. The application registers
## its backends, and a push whose backend is not registered here says so instead of being posted
## somewhere else.

const AdapterScript := preload("res://scripts/biz/ledger_adapter.gd")
const FileLedgerScript := preload("res://scripts/biz/file_ledger.gd")
const PushScript := preload("res://scripts/biz/ledger_push.gd")
const BillingDeskScript := preload("res://scripts/biz/billing_desk.gd")
const InvoiceScript := preload("res://scripts/biz/invoice.gd")
const PaymentScript := preload("res://scripts/biz/payment.gd")
const CreditScript := preload("res://scripts/biz/credit_note.gd")

const OUTBOX_PATH := "user://biz/outbox.json"
const TEMP_SUFFIX := ".part"
const VERSION := 1
## The backend a desk starts with, and the name a page falls back to.
const DEFAULT_ADAPTER := "file"

## A cap, like the revision log's: an outbox nobody has opened in a year is not a queue, and an
## unbounded one grows a file that is read on every start. **Only delivered entries are dropped** -
## see `_trim`.
const MAX_PUSHES := 500

## What a reconciliation can find. String keys, because a StringName literal as a const Dictionary key
## fails the constant-expression check.
const NOT_HANDED_OVER := "not_handed_over"
const VOID_BUT_POSTED := "void_but_posted"
const RENUMBERED := "renumbered"

## What has been billed, so the desk can say which documents exist and whether each has been handed
## over. Null is allowed: an outbox that is only ever posted to by hand is still a valid one.
var billing: BillingDesk = null
## Every attempt this session has queued, oldest first.
var pushes: Array[LedgerPush] = []
## The backend a page posts to when it does not say.
var chosen: String = ""

## What could not be handed over the last time the desk was asked to. A refusal is a thing a person has
## to read - an invoice whose customer has no id in the ledger - and a queue that swallowed it would be
## the silence REQ-B14 forbids, so it is kept until the next attempt and shown wherever the outbox is.
var refusals: Array[String] = []

## The same documents, as `adapter:document`. Kept so that reconciliation does not say the same thing
## twice in two different words: an invoice that could not be built is already named, and named more
## precisely, by its refusal - so it is not also reported as "not handed over".
var refused_ids: Array[String] = []

var _adapters: Array[LedgerAdapter] = []


## A new desk holds the file backend, because it needs nothing configured and always works. An office
## that has not set up a hosted ledger still has a ledger, and documents do not pile up unsent behind
## a settings page nobody has visited.
func _init() -> void:
	_adapters = [FileLedgerScript.new()]
	chosen = DEFAULT_ADAPTER


func bind(billing_desk: BillingDesk) -> void:
	billing = billing_desk


# --- the backends this desk can post to ---------------------------------------------------------


## Register a backend. Refuses one with no name - it could not be chosen, and a push to it could not be
## read back - and one whose name is taken, because two backends called "file" would make the push's
## own record ambiguous about where the document went.
func add_adapter(candidate: LedgerAdapter) -> bool:
	if candidate == null or String(candidate.name()).strip_edges().is_empty():
		return false
	if has_adapter(String(candidate.name())):
		return false
	_adapters.append(candidate)
	return true


func adapters() -> Array[LedgerAdapter]:
	return _adapters.duplicate()


func adapter_names() -> Array[String]:
	var out: Array[String] = []
	for held in _adapters:
		out.append(String(held.name()))
	return out


func has_adapter(adapter_name: String) -> bool:
	return adapter(adapter_name) != null


func adapter(adapter_name: String) -> LedgerAdapter:
	for held in _adapters:
		if String(held.name()) == adapter_name:
			return held
	return null


## Which backend the desk posts to when nobody says. A name it does not have is **refused rather than
## kept**, so a page cannot believe it is posting to the office's accounting system while writing
## files into a folder.
func choose(adapter_name: String) -> bool:
	if not has_adapter(adapter_name):
		return false
	chosen = adapter_name
	return true


func chosen_adapter() -> LedgerAdapter:
	return adapter(chosen)


# --- the documents that are waiting --------------------------------------------------------------


## Queue an invoice for a backend, build the request now, and hold it. `{ok, reason, push, already}`.
##
## A document that cannot be built for this backend - a capability it does not have, a customer with
## no id there, a tax the invoice could not charge - is **refused in words** rather than queued and
## forgotten (AC-B14). The invoice itself is untouched either way: it has gone out and it has been
## printed whether or not a ledger is configured (REQ-B14).
func queue_invoice(invoice: Invoice, adapter_name: String = "", at: String = "") -> Dictionary:
	var backend: LedgerAdapter = _pick(adapter_name)
	if backend == null:
		return _refused(_no_ledger_text(adapter_name))
	if invoice == null:
		return _refused("there is no invoice to hand over")
	var key: String = backend.key_for_invoice(invoice)
	var built: Dictionary = backend.build_invoice_push(invoice, key)
	return _take(built, backend, AdapterScript.INVOICE_KIND, _identity(invoice.id, invoice.number),
		invoice.number, key, at)


## Queue a payment against the invoice it settles. `{ok, reason, push, already}`.
##
## A payment needs the invoice's id **in that ledger**, which is assigned when the invoice is first
## posted - so it is read off the invoice's own push, and an office that has recorded one by hand can
## state it instead. Without either, the backend refuses and names what is missing.
func queue_payment(payment: Payment, invoice: Invoice, adapter_name: String = "",
		at: String = "", external_invoice_id: String = "") -> Dictionary:
	var backend: LedgerAdapter = _pick(adapter_name)
	if backend == null:
		return _refused(_no_ledger_text(adapter_name))
	if payment == null or invoice == null:
		return _refused("there is no payment to hand over")
	var id_there: String = external_invoice_id.strip_edges()
	if id_there.is_empty():
		var posted: LedgerPush = push_for(backend.key_for_invoice(invoice))
		if posted != null:
			id_there = posted.external_id
	var key: String = backend.key_for_payment(payment, invoice)
	var built: Dictionary = backend.build_payment_push(payment, invoice, key, id_there)
	return _take(built, backend, AdapterScript.PAYMENT_KIND, payment.id, payment.id, key, at)


## Queue a credit note. `{ok, reason, push, already}`. A backend that cannot post credit notes refuses
## here, by name, which is the whole point of a capability being a property rather than a hope.
func queue_credit(credit: CreditNote, adapter_name: String = "", at: String = "") -> Dictionary:
	var backend: LedgerAdapter = _pick(adapter_name)
	if backend == null:
		return _refused(_no_ledger_text(adapter_name))
	if credit == null:
		return _refused("there is no credit note to hand over")
	var key: String = backend.key_for_credit(credit)
	var built: Dictionary = backend.build_credit_push(credit, key)
	return _take(built, backend, AdapterScript.CREDIT_KIND, _identity(credit.id, credit.number),
		credit.number, key, at)


## Take a built request into the outbox. A refusal is returned as it stands; a document already queued
## for this backend is handed back as the push it already has, because the key is the identity.
func _take(built: Dictionary, backend: LedgerAdapter, kind: StringName, doc_id: String,
		doc_number: String, idempotency_key: String, at: String) -> Dictionary:
	if not bool(built.get("ok", false)):
		return _refused(String(built.get("reason", "the ledger would not take it")))
	var held: LedgerPush = push_for(idempotency_key)
	if held != null:
		return {"ok": true, "reason": "", "push": held, "already": true}
	var request_in: Variant = built.get("request", {})
	var request: Dictionary = request_in if request_in is Dictionary else {}
	var push: LedgerPush = PushScript.for_document(
		String(backend.name()), kind, doc_id, doc_number, idempotency_key, request, _stamp(at)
	)
	var broken: Array[String] = push.problems()
	if not broken.is_empty():
		return _refused(broken[0])
	pushes.append(push)
	_trim()
	return {"ok": true, "reason": "", "push": push, "already": false}


# --- everything the office has issued and not yet handed over -----------------------------------


## Hand over every invoice this office has issued and is not already in the outbox for this backend.
## `{ok, queued, refused, reason}`.
##
## **Idempotent**, because the key is the identity: called on every billing change it queues a new
## invoice exactly once, and never re-queues one that is already here. That is what makes it safe to run
## as part of issuing - REQ-B14 wants the push queued when the document issues, not remembered about
## later.
##
## An invoice that cannot be built for this backend at all - a customer with no id there, a tax the
## invoice could not charge - is **refused by name and kept in `refusals`**, and does not stop the ones
## after it. A queue that swallowed that would be the silence REQ-B14 forbids.
func queue_unhanded(adapter_name: String = "", at: String = "") -> Dictionary:
	refusals.clear()
	refused_ids.clear()
	var backend: LedgerAdapter = _pick(adapter_name)
	if backend == null:
		return {"ok": false, "queued": 0, "refused": 0, "reason": _no_ledger_text(adapter_name)}
	if billing == null:
		return {"ok": true, "queued": 0, "refused": 0, "reason": ""}
	var queued: int = 0
	var refused: int = 0
	var reasons: Array[String] = []
	for invoice in billing.invoices:
		# An invoice that was never issued has no number to post, and one that was called back is not
		# supposed to go at all: only what has been issued and still stands is handed over.
		if not invoice.is_issued() or invoice.is_void():
			continue
		# A document already in the outbox is one push already, so it is not built again - which is what
		# makes this cheap enough to call on every change to what has been billed.
		if push_for(backend.key_for_invoice(invoice)) != null:
			continue
		var taken: Dictionary = queue_invoice(invoice, String(backend.name()), at)
		if bool(taken["ok"]):
			if not bool(taken["already"]):
				queued += 1
			continue
		refused += 1
		refused_ids.append(_refusal_tag(String(backend.name()), invoice))
		var said: String = "%s could not be handed over: %s" % [
			_invoice_name(invoice), String(taken["reason"]),
		]
		if not reasons.has(said):
			reasons.append(said)
	refusals = reasons.duplicate()
	return {"ok": refused == 0, "queued": queued, "refused": refused, "reason": ", ".join(reasons)}


# --- posting ------------------------------------------------------------------------------------


## Post one push: send what it holds and record what came back. `{ok, reason, status, push}`.
##
## **This is the only place a request is sent and the only place a transport is used.** A push already
## taken is not sent again - that is what `is_pushed` is for - so calling this twice is safe.
func post(key: String, at: String = "") -> Dictionary:
	var push: LedgerPush = push_for(key)
	if push == null:
		return {"ok": false, "reason": "nothing in the outbox is under that key", "status": 0, "push": null}
	if push.is_pushed():
		return {"ok": true, "reason": "", "status": push.last_status, "push": push}
	var backend: LedgerAdapter = adapter(push.adapter)
	if backend == null:
		# The backend this push was built for is not registered this session. The request is kept as it
		# stands and the attempt is recorded, because sending it to whichever backend happens to be
		# first would post the document to the wrong place - or, worse, to the right place twice.
		#
		# It records as **never arrived** (status 0), which is what happened: the queue keeps it and the
		# day the backend is registered the document goes. Five runs of that and it stops being the
		# queue's and becomes a person's, which is the right moment to say so.
		var missing: String = "no ledger called '%s' is registered here" % push.adapter
		var nowhere: Dictionary = {"status": 0, "error": missing}
		push.record_response(nowhere, AdapterScript.new().parse_common(nowhere), _stamp(at))
		return {"ok": false, "reason": missing, "status": 0, "push": push}
	var response: Dictionary = backend.send(backend.authorise(push.request))
	var parsed: Dictionary = _read(backend, push, response)
	var took_it: bool = push.record_response(response, parsed, _stamp(at))
	return {
		"ok": took_it,
		"reason": "" if took_it else push.failure,
		"status": int(response.get("status", 0)),
		"push": push,
	}


## Post everything the queue still owns, once each. **This is the retry loop**: what `can_retry()` is
## false for is left alone, so a refusal is not sent again and a backend that has been down five times
## stops being tried. Returns `{ok, tried, taken, failed, waiting, stranded, reason}`.
func post_due(at: String = "") -> Dictionary:
	var tried: int = 0
	var taken: int = 0
	var failed: int = 0
	var reasons: Array[String] = []
	for push in pending():
		if not push.can_retry():
			continue
		var posted: Dictionary = post(push.key, at)
		tried += 1
		if bool(posted["ok"]):
			taken += 1
		else:
			failed += 1
			var words: String = String(posted["reason"])
			if not words.strip_edges().is_empty() and not reasons.has(words):
				reasons.append(words)
	return {
		"ok": failed == 0,
		"tried": tried,
		"taken": taken,
		"failed": failed,
		"waiting": pending().size(),
		"stranded": stranded().size(),
		"reason": ", ".join(reasons),
	}


## The adapter's own reading of its own answer, chosen by what the document is - an invoice's answer
## and a payment's answer are read differently by every backend.
func _read(backend: LedgerAdapter, push: LedgerPush, response: Dictionary) -> Dictionary:
	match push.kind:
		AdapterScript.PAYMENT_KIND:
			return backend.parse_payment_response(response)
		AdapterScript.CREDIT_KIND:
			return backend.parse_credit_response(response)
	return backend.parse_invoice_response(response)


# --- reading the outbox -------------------------------------------------------------------------


func push_for(key: String) -> LedgerPush:
	for push in pushes:
		if push.key == key:
			return push
	return null


func has_push(key: String) -> bool:
	return push_for(key) != null


## What the queue still owns: not delivered, and still worth trying.
func pending() -> Array[LedgerPush]:
	var out: Array[LedgerPush] = []
	for push in pushes:
		if not push.is_pushed() and push.can_retry():
			out.append(push)
	return out


## What the queue has given up on. A person has to look at these, which is why they are their own list
## and why the desk says how many there are wherever it is summarised.
func stranded() -> Array[LedgerPush]:
	var out: Array[LedgerPush] = []
	for push in pushes:
		if push.needs_a_person():
			out.append(push)
	return out


func delivered() -> Array[LedgerPush]:
	var out: Array[LedgerPush] = []
	for push in pushes:
		if push.is_pushed():
			out.append(push)
	return out


func count() -> int:
	return pushes.size()


func count_for(adapter_name: String) -> int:
	var how_many: int = 0
	for push in pushes:
		if push.adapter == adapter_name:
			how_many += 1
	return how_many


## One row per push as a page shows them, newest first: the record's own answers, in named fields, so
## the page composes a line rather than parsing one.
func rows(adapter_name: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for at in range(pushes.size() - 1, -1, -1):
		var push: LedgerPush = pushes[at]
		if not adapter_name.strip_edges().is_empty() and push.adapter != adapter_name:
			continue
		out.append({
			"key": push.key,
			"state": push.state_name(),
			"kind": String(push.kind),
			"kind_name": String(AdapterScript.KIND_NAMES.get(String(push.kind), "a document")),
			"adapter": push.adapter,
			"number": push.document_number,
			"attempts": push.attempt_count(),
			"queued_at": push.queued_at,
			"pushed_at": push.pushed_at,
			"external_number": push.external_number,
			"why": push.failure,
			"retryable": push.can_retry(),
			"wants_a_person": push.needs_a_person(),
			"words": push.describe(),
		})
	return out


func row_texts(adapter_name: String = "") -> Array[String]:
	var out: Array[String] = []
	for held in rows(adapter_name):
		out.append(String(held["words"]))
	return out


## What the outbox says in one line. An outbox with nothing in it says so plainly rather than
## reporting three zeros: a menu line should not read "0 waiting, 0 delivered".
##
## A document that could not even be queued is counted here and not only in `problems()`, because this
## is the line somebody reads from across the room: "nothing has been handed to a ledger" while an
## invoice sits there unable to go would be the silence REQ-B14 forbids.
func summary_text() -> String:
	var sent: int = delivered().size()
	var waiting: int = pending().size()
	var stuck: int = stranded().size()
	var parts := PackedStringArray()
	if sent > 0:
		parts.append("%d handed over" % sent)
	if waiting > 0:
		parts.append("%d waiting" % waiting)
	if stuck > 0:
		parts.append("%d wanting a person" % stuck)
	if not refusals.is_empty():
		parts.append("%d could not be handed over" % refusals.size())
	if parts.is_empty():
		return "nothing has been handed to a ledger"
	return ", ".join(parts)


# --- what does not agree ------------------------------------------------------------------------


## What does not agree between this office's own records and the outbox, in words. **Nothing is
## changed.** A reconciliation that quietly fixed what it found would be a program editing an
## accounting record on a guess, so this only says what it sees and the page shows it.
##
## Three things it can find, each a real state of the outbox rather than a hypothetical:
##
## - an invoice that has been issued here and handed to nobody;
## - an invoice that was **posted and has since been called back**, which the ledger still believes in
##   and which only a credit note against it can undo;
## - a document the ledger numbered differently from the office, which is worth knowing before the two
##   numbers are quoted at each other.
##
## Each entry is `{kind, key, number, words}`.
func reconcile(adapter_name: String = "") -> Array[Dictionary]:
	var backend: LedgerAdapter = _pick(adapter_name)
	var out: Array[Dictionary] = []
	if backend == null:
		return out
	if billing != null:
		for invoice in billing.invoices:
			var key: String = backend.key_for_invoice(invoice)
			var held: LedgerPush = push_for(key)
			if invoice.is_void():
				if held != null and held.is_pushed():
					out.append(_note(VOID_BUT_POSTED, key, invoice.number,
						"%s was called back here and is still in %s: only a credit note against it reverses it"
						% [_invoice_name(invoice), String(backend.name())]))
				continue
			if held == null and invoice.is_issued() \
					and not refused_ids.has(_refusal_tag(String(backend.name()), invoice)):
				out.append(_note(NOT_HANDED_OVER, key, invoice.number,
					"%s has been issued and not handed to %s" % [_invoice_name(invoice), String(backend.name())]))
	for push in pushes:
		if push.adapter != String(backend.name()) or not push.is_pushed():
			continue
		if push.external_number.strip_edges().is_empty():
			continue
		if push.external_number == push.document_number:
			continue
		out.append(_note(RENUMBERED, push.key, push.document_number,
			"%s is %s here and %s in %s" % [
				push.document_number, push.document_number, push.external_number, String(backend.name())
			]))
	return out


func reconcile_words(adapter_name: String = "") -> Array[String]:
	var out: Array[String] = []
	for found in reconcile(adapter_name):
		out.append(String(found["words"]))
	return out


# --- soundness ----------------------------------------------------------------------------------


## Everything wrong with the outbox, in words: the records that are not sound, the documents the queue
## has given up on, and the backend as it stands. Empty is the good answer.
func problems() -> Array[String]:
	var out: Array[String] = []
	for push in pushes:
		for words: String in push.problems():
			out.append("%s: %s" % [_push_name(push), words])
	for push in stranded():
		out.append("%s will not be retried: %s" % [_push_name(push), push.failure])
	# A document the office has issued that could not even be queued is a person's to fix, and it is
	# named here so that handing over never fails quietly.
	for said in refusals:
		out.append(said)
	for found in reconcile():
		out.append(String(found["words"]))
	var backend: LedgerAdapter = chosen_adapter()
	if backend == null:
		out.append("no ledger is chosen")
	elif not backend.is_configured():
		out.append("%s needs %s" % [backend.describe(), ", ".join(backend.problems())])
	return out


func is_sound() -> bool:
	return problems().is_empty()


## How many things want a person: a document the queue has given up on, a document that could not even
## be queued, and a disagreement between the office's records and the ledger's. This is the number a menu
## line shows, because it is the one that means somebody has to do something.
func issues() -> int:
	return stranded().size() + refusals.size() + reconcile().size()


func describe() -> String:
	var backend: LedgerAdapter = chosen_adapter()
	var where: String = "no ledger" if backend == null else String(backend.name())
	return "the %s ledger: %s" % [where, summary_text()]


# --- the outbox on disk -------------------------------------------------------------------------


func to_dict() -> Dictionary:
	var rows_out: Array = []
	for push in pushes:
		var row: Dictionary = push.to_dict()
		# The document is written down as it was built - its URL and its body, byte for byte, which is
		# what AC-B15 rests on - and the credential is not. See `_written`.
		row["request"] = _written(push)
		rows_out.append(row)
	return {
		"version": VERSION,
		"chosen": chosen,
		"pushes": rows_out,
	}


## A push's request as it is **written down**: what was built, with any header this backend
## authenticates with blanked out.
##
## An outbox is a file that sits beside the drawings, and a file like that is not where a token
## belongs - the same rule `settings()` already applies by marking which of a backend's fields is a
## secret. What is *not* touched is the document: the method, the URL and the body are stored exactly
## as built, so a retry after a restart still sends the same document, and `LedgerAdapter.authorise`
## puts the credential back at the moment of sending.
func _written(push: LedgerPush) -> Dictionary:
	var request: Dictionary = push.request.duplicate(true)
	var backend: LedgerAdapter = adapter(push.adapter)
	if backend == null:
		return request
	var headers_in: Variant = request.get("headers", {})
	if not headers_in is Dictionary:
		return request
	var headers: Dictionary = headers_in
	for header_name: String in backend.secret_headers():
		if headers.has(header_name):
			headers[header_name] = ""
	request["headers"] = headers
	return request


## Read an outbox back into a desk. A damaged row is dropped and counted rather than invented, the way
## every other record in this project is read.
static func from_dict(data: Dictionary, billing_desk: BillingDesk = null) -> LedgerDesk:
	var desk: LedgerDesk = LedgerDeskScript.new()
	desk.bind(billing_desk)
	var rows_in: Variant = data.get("pushes", [])
	if rows_in is Array:
		for entry in (rows_in as Array):
			if not entry is Dictionary:
				continue
			var push: LedgerPush = PushScript.from_dict(entry)
			if push == null or not push.is_sound():
				continue
			desk.pushes.append(push)
	var chosen_in: String = String(data.get("chosen", ""))
	if desk.has_adapter(chosen_in):
		desk.chosen = chosen_in
	return desk


## Write the outbox down, through a temporary file and a rename, like a drawing: a save that fails
## halfway must not leave an outbox shorter than the one it replaced, because the entries it lost are
## documents nobody has been told about. Returns `{ok, reason, path}`.
func write(path: String = OUTBOX_PATH) -> Dictionary:
	if path.strip_edges().is_empty():
		return {"ok": false, "reason": "this outbox has no file name", "path": path}
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


## Read the outbox back. A missing file is an empty outbox rather than a fault - the first run has no
## outbox - and a file that will not read is refused with the reason and **leaves the desk alone**,
## because half-loading an outbox is worse than not loading one.
func read(path: String = OUTBOX_PATH) -> Dictionary:
	var empty := {"ok": true, "reason": "", "loaded": 0, "dropped": 0}
	if path.strip_edges().is_empty():
		return {"ok": false, "reason": "no outbox was named", "loaded": 0, "dropped": 0}
	if not FileAccess.file_exists(path):
		return empty
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "reason": "cannot read %s" % path.get_file(), "loaded": 0, "dropped": 0}
	var text: String = file.get_as_text()
	file.close()
	# Parsed with a reader rather than `JSON.parse_string`, which logs an engine error to the console
	# when it fails: the person is being told in a sentence what is wrong, and an error line nobody can
	# act on is noise in a console that should carry only real faults.
	var reader := JSON.new()
	if reader.parse(text) != OK:
		return {
			"ok": false,
			"reason": "%s is not readable as an outbox: %s (line %d)" % [
				path.get_file(), reader.get_error_message(), reader.get_error_line()
			],
			"loaded": 0,
			"dropped": 0,
		}
	var data: Variant = reader.data
	if not data is Dictionary:
		return {"ok": false, "reason": "%s is not an outbox" % path.get_file(), "loaded": 0, "dropped": 0}
	var read_back: Dictionary = data
	pushes.clear()
	var dropped: int = 0
	var rows_in: Variant = read_back.get("pushes", [])
	if rows_in is Array:
		for entry in (rows_in as Array):
			if not entry is Dictionary:
				dropped += 1
				continue
			var push: LedgerPush = PushScript.from_dict(entry)
			if push == null or not push.is_sound():
				dropped += 1
				continue
			pushes.append(push)
	var chosen_in: String = String(read_back.get("chosen", ""))
	if has_adapter(chosen_in):
		chosen = chosen_in
	elif not has_adapter(chosen):
		chosen = adapter_names()[0] if not _adapters.is_empty() else ""
	return {"ok": true, "reason": "", "loaded": pushes.size(), "dropped": dropped}


# --- help ---------------------------------------------------------------------------------------


func _pick(adapter_name: String) -> LedgerAdapter:
	if adapter_name.strip_edges().is_empty():
		return chosen_adapter()
	return adapter(adapter_name)


func _no_ledger_text(adapter_name: String) -> String:
	if adapter_name.strip_edges().is_empty():
		return "no ledger is chosen to hand documents to"
	return "no ledger called '%s' is registered here" % adapter_name


static func _refused(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "push": null, "already": false}


static func _note(kind: String, key: String, number: String, words: String) -> Dictionary:
	return {"kind": kind, "key": key, "number": number, "words": words}


## A document's identity in the outbox. An id is what a desk here assigns, but a record from somewhere
## else may carry only its number - and a push whose document id is empty is refused as unsound, so the
## number stands in rather than the document being unsendable.
static func _identity(id: String, number: String) -> String:
	if not id.strip_edges().is_empty():
		return id
	return number


## A refused document, tagged with the backend it was refused by: a document that could not be built for
## one backend is still perfectly handable to another, so the two questions are not the same question.
static func _refusal_tag(adapter_name: String, invoice: Invoice) -> String:
	return "%s:%s" % [adapter_name, _identity(invoice.id, invoice.number)]


static func _stamp(at: String) -> String:
	if at.strip_edges().is_empty():
		return Time.get_date_string_from_system()
	return at


static func _invoice_name(invoice: Invoice) -> String:
	if not invoice.number.strip_edges().is_empty():
		return invoice.number
	return invoice.id


static func _push_name(push: LedgerPush) -> String:
	if not push.document_number.strip_edges().is_empty():
		return push.document_number
	return push.key


## Keep the outbox to a size. **The oldest delivered entries go first**, so a document that has not
## been delivered is never dropped to make room for one that has - and if nothing in here has been
## delivered, nothing is dropped at all, because an outbox of undelivered documents is exactly the
## thing that must not be trimmed away.
func _trim() -> void:
	while pushes.size() > MAX_PUSHES:
		var oldest: int = -1
		for at in pushes.size():
			if pushes[at].is_pushed():
				oldest = at
				break
		if oldest < 0:
			return
		pushes.remove_at(oldest)


const LedgerDeskScript := preload("res://scripts/biz/ledger_desk.gd")