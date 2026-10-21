class_name BizSyncTransport
extends RefCounted
## What a sync service has to be able to do, and the honest answer when nothing can (§11.2).
##
## The service is small and boring on purpose, and it is four calls:
##
##     GET  /changes?since=<cursor>&limit=<n>        the append-only change log
##     PUT  /records/<kind>/<id>   If-Match: <rev>   a push; 200 accepted at rev+1, 409 someone else
##     POST /attachments                             photos: large and immutable, kept apart from records
##     GET  /health, /whoami                         deployment checks
##
## The base does **nothing and says so**. Every call answers with a sentence naming what is missing
## rather than an empty success, because a backend that silently does nothing is exactly the failure
## the ledger adapter layer was built to avoid (REQ-B14) - and a sync that reports "nothing to do" when
## it has nowhere to talk is worse than one that refuses, because the office believes it.
##
## A result is `{ok, status, retry, reason, ...}`. **`status` 0 means the service was never reached**,
## which is the retryable case, and any HTTP status the service did answer with is carried through so a
## caller can tell 409 (someone else changed it) from 401 (the token is wrong). That is the same shape
## the ledger adapters answer with, deliberately: one result convention for the whole module.


const CHANGES := "changes"
const PUSH := "push"
const ATTACHMENTS := "attachments"
const HEALTH := "health"
## The four things a service can be able to do, so a picker can say which before it is chosen.
const CAPABILITIES := [CHANGES, PUSH, ATTACHMENTS, HEALTH]

## The roles the service holds, and what a role decides (§11.6.4).
const OWNER := "OWNER"
const OFFICE := "OFFICE"
const FIELD := "FIELD"
const VIEWER := "VIEWER"
const ROLES := [OWNER, OFFICE, FIELD, VIEWER]

## The codes that mean the service took it.
const FIRST_SUCCESS := 200
const LAST_SUCCESS := 299
## The statuses worth trying again: **status 0 is the service never reached** and the rest are a
## momentary inability. A service that said no (400/401/403/404/409/422) will say no again, and a queue
## that retries it forever never asks a person. Deliberately the same list the ledger adapters use -
## one result convention for the whole module.
const RETRYABLE := [408, 425, 429, 500, 502, 503, 504]


## The backend's name, for a picker and for a file. Empty names nothing.
func name() -> String:
	return ""


## Whether this transport has somewhere to point at. A transport that does not is not offered.
func is_configured() -> bool:
	return false


## Whether it is configured and can actually be used - a token is present, a folder exists.
func is_ready() -> bool:
	return false


func capabilities() -> Array[String]:
	return []


func has_capability(cap: String) -> bool:
	return capabilities().has(cap)


## `{key, label, secret}` for every setting this transport has, so a page can build its fields and mask
## the ones that are secret.
func settings() -> Array[Dictionary]:
	return []


func configure(values: Dictionary) -> Dictionary:
	for key in values:
		return refused("there is no sync service here to set '%s' on" % String(key))
	return refused("there is no sync service here to configure")


func describe() -> String:
	return "a sync service this build has no transport for"


# --- the four calls -----------------------------------------------------------------------------


func changes(since: int = 0, limit: int = 0) -> Dictionary:
	return _nothing("read changes", "since %d, %d at a time" % [since, limit])


func push(kind: String, id: String, job: String, body: Dictionary, rev: int, who: String = "") -> Dictionary:
	var what: String = "%s '%s'" % [kind, id]
	if not job.is_empty():
		what += " on %s" % job
	if not who.is_empty():
		what += " (by %s)" % who
	if not body.is_empty():
		what += " carrying %d field(s)" % body.size()
	return _nothing("push", "%s at revision %d" % [what, rev])


func attachment(attachment_name: String, bytes: PackedByteArray) -> Dictionary:
	return _nothing("take attachments", "'%s' of %d byte(s)" % [attachment_name, bytes.size()])


func health() -> Dictionary:
	return _nothing("answer a health check", "nothing was asked of it")


func whoami() -> Dictionary:
	return _nothing("answer whoami", "nothing was asked of it")


## The words every unimplemented call answers with, **naming what was asked for**, so a refusal says
## which call and which record rather than six copies of one sentence.
static func _nothing(what: String, detail: String) -> Dictionary:
	return refused("no sync service is configured to %s: %s was asked for" % [what, detail])


## A refusal is not a retry unless the caller says it is: a service that was reached and said no will
## say no again, and a queue that retries a refusal forever is a queue that never asks a person.
static func refused(reason: String, retry: bool = false) -> Dictionary:
	return {"ok": false, "status": 0, "retry": retry, "reason": reason}


## Whether a status is worth trying again, by the one rule both transports and the sync run share.
static func is_retryable(status: int) -> bool:
	if status == 0:
		return true
	if status in RETRYABLE:
		return true
	return status >= 500 and status <= 599


## Why a status was not a success, in words an office can act on rather than a number on its own.
static func status_reason(status: int, service: String, detail: String) -> String:
	var because: String = ""
	if not detail.strip_edges().is_empty():
		because = ": " + detail.strip_edges()
	match status:
		401:
			return "401 the token was refused%s" % because
		403:
			return "403 the account may not do that%s" % because
		404:
			return "404 %s has no such record%s" % [service, because]
		409:
			return "409 someone else changed it first%s" % because
		422:
			return "422 %s would not take the record%s" % [service, because]
	if is_retryable(status):
		return "%d %s was momentarily unable; try again%s" % [status, service, because]
	return "%d %s refused the request%s" % [status, service, because]