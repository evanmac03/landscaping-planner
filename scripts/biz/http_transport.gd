class_name BizHttpTransport
extends BizSyncTransport
## The sync service over HTTP (§11.2): the change log, a push with `If-Match`, attachments, and the two
## deployment checks.
##
## **Everything is stated as a request before it is sent.** `request_for` builds the method, the path,
## the headers and the body, and is pure - so the shape of what this build would PUT is testable
## without a server, which is the part a person can get wrong. `_exchange` is the part that needs a
## deployment: it connects, sends, and reads the answer, and it is written so that **failing to reach
## the service is a refusal that says so**, not an exception and not a silence.
##
## **A push carries `If-Match` with the revision the change was based on.** That is what makes a push
## idempotent and interruptible: the service answers 200 (taken, at rev+1) or 409 (someone else changed
## it first), and a 409 is a conflict rather than a failure - the sync layer has a policy for it (§11.3)
## and it is the reason the office cannot clobber a colleague by working offline.
##
## **No token, no service.** The address says where the service is; the token says the device may talk
## to it, and §11.6.4 wants a token on the device rather than a password. A transport with an address
## and no token is configured but not ready, and every call refuses rather than sending an anonymous
## request the service would reject anyway.


const BASE_URL := "base_url"
const TOKEN := "token"
## How many records one pull asks for. A cursor advances by what was applied, so a page of 500 is 500
## small files rather than a request that never returns.
const DEFAULT_LIMIT := 500
## How many times a poll loop turns before it gives up. A bounded loop is the difference between "the
## service is slow" and "this program is not coming back".
const MAX_POLLS := 4000

var base_url: String = ""
var token: String = ""


func _init(address: String = "", bearer: String = "") -> void:
	base_url = address.strip_edges()
	token = bearer


func name() -> String:
	return "http"


func is_configured() -> bool:
	var raw: String = base_url.strip_edges()
	return raw.begins_with("http://") or raw.begins_with("https://")


func is_ready() -> bool:
	return is_configured() and not token.strip_edges().is_empty()


func capabilities() -> Array[String]:
	return [CHANGES, PUSH, ATTACHMENTS, HEALTH]


## The two settings, and which one is a secret - so a page can mask the token and a file can keep it
## out (the same rule the ledger adapters follow).
func settings() -> Array[Dictionary]:
	return [
		{"key": BASE_URL, "label": "the address of the sync service", "secret": false},
		{"key": TOKEN, "label": "the token this device signs in with", "secret": true},
	]


## Take the settings it knows and refuse the ones it does not, naming them: a page that silently kept
## half of what a person typed is a page that lied about saving.
func configure(values: Dictionary) -> Dictionary:
	var known: Array[String] = [BASE_URL, TOKEN]
	for key in values:
		var held: String = String(key)
		if not known.has(held):
			return refused("this service has no setting called '%s'" % held)
	if values.has(BASE_URL):
		base_url = String(values[BASE_URL]).strip_edges()
	if values.has(TOKEN):
		token = String(values[TOKEN])
	return {"ok": true, "status": 0, "retry": false, "reason": ""}


func describe() -> String:
	if is_ready():
		return "the sync service at %s" % base_url
	if is_configured():
		return "the sync service at %s, which this device has no token for" % base_url
	return "a sync service with no address yet"


# --- what would be sent -------------------------------------------------------------------------


## The request a call would make: `{method, path, headers, body}`. Pure, so the shape of a push can be
## read without a service to send it to.
func request_for(which: String, args: Dictionary) -> Dictionary:
	var parts: Dictionary = _split_base()
	var prefix: String = String(parts["prefix"])
	var headers: Array[String] = ["Accept: application/json"]
	if not token.strip_edges().is_empty():
		headers.append("Authorization: Bearer " + token.strip_edges())
	match which:
		CHANGES:
			var since: int = int(args.get("since", 0))
			var limit: int = int(args.get("limit", 0))
			if limit <= 0:
				limit = DEFAULT_LIMIT
			return {
				"method": HTTPClient.METHOD_GET,
				"path": "%s/changes?since=%d&limit=%d" % [prefix, since, limit],
				"headers": headers,
				"body": "",
			}
		PUSH:
			headers.append("Content-Type: application/json")
			headers.append("If-Match: %d" % int(args.get("rev", 0)))
			var payload: Dictionary = {
				"kind": String(args.get("kind", "")),
				"id": String(args.get("id", "")),
				"job": String(args.get("job", "")),
				"body": args.get("body", {}),
				"who": String(args.get("who", "")),
			}
			return {
				"method": HTTPClient.METHOD_PUT,
				"path": "%s/records/%s/%s" % [
					prefix, String(args.get("kind", "")).uri_encode(), String(args.get("id", "")).uri_encode()
				],
				"headers": headers,
				"body": JSON.stringify(payload),
			}
		ATTACHMENTS:
			headers.append("Content-Type: application/octet-stream")
			headers.append("X-Attachment-Name: " + String(args.get("name", "")).uri_encode())
			return {
				"method": HTTPClient.METHOD_POST,
				"path": "%s/attachments" % prefix,
				"headers": headers,
				"body": "",
			}
		HEALTH:
			return {"method": HTTPClient.METHOD_GET, "path": "%s/health" % prefix, "headers": headers, "body": ""}
		_:
			return {
				"method": HTTPClient.METHOD_GET,
				"path": "%s/whoami" % prefix,
				"headers": headers,
				"body": "",
			}


# --- the four calls -----------------------------------------------------------------------------


func changes(since: int = 0, limit: int = 0) -> Dictionary:
	var guard: Dictionary = _readiness()
	if not bool(guard["ok"]):
		return guard
	var answer: Dictionary = _exchange(request_for(CHANGES, {"since": since, "limit": limit}))
	if not bool(answer["ok"]):
		return {
			"ok": false,
			"status": int(answer["status"]),
			"retry": bool(answer["retry"]),
			"reason": String(answer["reason"]),
			"cursor": since,
			"records": [],
		}
	var body: Dictionary = answer["body"]
	var records: Array = []
	var held: Variant = body.get("records", [])
	if held is Array:
		records = held
	return {
		"ok": true,
		"status": int(answer["status"]),
		"retry": false,
		"reason": "",
		"cursor": int(body.get("cursor", since)),
		"records": records,
	}


func push(kind: String, id: String, job: String, body: Dictionary, rev: int, who: String = "") -> Dictionary:
	var guard: Dictionary = _readiness()
	if not bool(guard["ok"]):
		return guard
	var args: Dictionary = {"kind": kind, "id": id, "job": job, "body": body, "rev": rev, "who": who}
	var answer: Dictionary = _exchange(request_for(PUSH, args))
	if not bool(answer["ok"]):
		var status: int = int(answer["status"])
		return {
			"ok": false,
			"status": status,
			"retry": bool(answer["retry"]),
			"conflict": status == HTTPClient.RESPONSE_CONFLICT,
			"reason": String(answer["reason"]),
			"rev": rev,
		}
	var answer_body: Dictionary = answer["body"]
	var new_rev: int = int(answer_body.get("rev", rev + 1))
	return {
		"ok": true,
		"status": int(answer["status"]),
		"retry": false,
		"conflict": false,
		"reason": "",
		"rev": new_rev,
	}


func attachment(attachment_name: String, bytes: PackedByteArray) -> Dictionary:
	var guard: Dictionary = _readiness()
	if not bool(guard["ok"]):
		return guard
	var args: Dictionary = {"name": attachment_name}
	var request: Dictionary = request_for(ATTACHMENTS, args)
	request["body"] = bytes.get_string_from_utf8()
	var answer: Dictionary = _exchange(request)
	if not bool(answer["ok"]):
		return {
			"ok": false,
			"status": int(answer["status"]),
			"retry": bool(answer["retry"]),
			"reason": String(answer["reason"]),
			"id": "",
		}
	return {
		"ok": true,
		"status": int(answer["status"]),
		"retry": false,
		"reason": "",
		"id": String((answer["body"] as Dictionary).get("id", "")),
	}


func health() -> Dictionary:
	var guard: Dictionary = _readiness()
	if not bool(guard["ok"]):
		return guard
	var answer: Dictionary = _exchange(request_for(HEALTH, {}))
	if not bool(answer["ok"]):
		return {
			"ok": false,
			"status": int(answer["status"]),
			"retry": bool(answer["retry"]),
			"reason": String(answer["reason"]),
			"service": "",
			"version": "",
		}
	var body: Dictionary = answer["body"]
	return {
		"ok": true,
		"status": int(answer["status"]),
		"retry": false,
		"reason": "",
		"service": String(body.get("service", "")),
		"version": String(body.get("version", "")),
	}


func whoami() -> Dictionary:
	var guard: Dictionary = _readiness()
	if not bool(guard["ok"]):
		return guard
	var answer: Dictionary = _exchange(request_for("whoami", {}))
	if not bool(answer["ok"]):
		return {
			"ok": false,
			"status": int(answer["status"]),
			"retry": bool(answer["retry"]),
			"reason": String(answer["reason"]),
			"user": "",
			"role": "",
		}
	var body: Dictionary = answer["body"]
	var role: String = String(body.get("role", ""))
	if not ROLES.has(role):
		role = ""
	return {
		"ok": true,
		"status": int(answer["status"]),
		"retry": false,
		"reason": "",
		"user": String(body.get("user", "")),
		"role": role,
	}


# --- the wire -----------------------------------------------------------------------------------


## The address split into what a client needs: scheme, host, port and any path prefix. Pure, so the
## awkward addresses (a port, a prefix, no scheme) are settled by a test rather than by a deployment.
func _split_base() -> Dictionary:
	var raw: String = base_url.strip_edges().trim_suffix("/")
	var tls: bool = raw.begins_with("https://")
	var rest: String = raw
	if rest.begins_with("https://"):
		rest = rest.substr(8)
	elif rest.begins_with("http://"):
		rest = rest.substr(7)
	var slash: int = rest.find("/")
	var authority: String = rest if slash < 0 else rest.substr(0, slash)
	var prefix: String = "" if slash < 0 else rest.substr(slash)
	var host: String = authority
	var port: int = 443 if tls else 80
	var colon: int = authority.rfind(":")
	if colon > 0:
		host = authority.substr(0, colon)
		port = int(authority.substr(colon + 1))
	return {"tls": tls, "host": host, "port": port, "prefix": prefix}


## Send one request and read the answer. **Failing to reach the service is a refusal that says so** -
## `status` 0 and retryable - because the alternative is a sync that reports nothing the matter when
## nothing was ever sent.
func _exchange(request: Dictionary) -> Dictionary:
	var parts: Dictionary = _split_base()
	var host: String = String(parts["host"])
	if host.is_empty():
		return _unreachable("the sync address does not name a host")
	var client := HTTPClient.new()
	var error: int = OK
	if bool(parts["tls"]):
		error = client.connect_to_host(host, int(parts["port"]), TLSOptions.client())
	else:
		error = client.connect_to_host(host, int(parts["port"]))
	if error != OK:
		return _unreachable("cannot reach %s: %s" % [host, error_string(error)])
	var turns: int = 0
	while turns < MAX_POLLS and (
		client.get_status() == HTTPClient.STATUS_RESOLVING
		or client.get_status() == HTTPClient.STATUS_CONNECTING
	):
		client.poll()
		turns += 1
	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		return _unreachable("%s did not answer (%s)" % [host, _status_word(client.get_status())])
	var headers: PackedStringArray = []
	for header in (request["headers"] as Array):
		headers.append(String(header))
	error = client.request(int(request["method"]), String(request["path"]), headers, String(request["body"]))
	if error != OK:
		return _unreachable("cannot send the request to %s: %s" % [host, error_string(error)])
	turns = 0
	while turns < MAX_POLLS and client.get_status() == HTTPClient.STATUS_REQUESTING:
		client.poll()
		turns += 1
	if not client.has_response():
		return _unreachable("%s did not answer the request" % host)
	var status: int = client.get_response_code()
	var bytes := PackedByteArray()
	turns = 0
	while turns < MAX_POLLS and client.get_status() == HTTPClient.STATUS_BODY:
		client.poll()
		bytes.append_array(client.read_response_body_chunk())
		turns += 1
	client.close()
	var text: String = bytes.get_string_from_utf8()
	if status < FIRST_SUCCESS or status > LAST_SUCCESS:
		return {
			"ok": false,
			"status": status,
			"retry": is_retryable(status),
			"reason": status_reason(status, name(), text),
			"body": _read_json(text),
			"text": text,
		}
	return {"ok": true, "status": status, "retry": false, "reason": "", "body": _read_json(text), "text": text}


# --- help ---------------------------------------------------------------------------------------


## The guard every call starts with: `ok` true when the service can be used, and the refusal to return
## when it cannot. Every call answers with this rather than sending an anonymous request the service
## would reject anyway.
func _readiness() -> Dictionary:
	if is_ready():
		return {"ok": true, "status": 0, "retry": false, "reason": ""}
	return refused("the sync address and a token have to both be set before this service can be used")


static func _unreachable(why: String) -> Dictionary:
	return {"ok": false, "status": 0, "retry": true, "reason": why, "body": {}}


## Parse an answer body, tolerating one that is not JSON (a service that answers a sentence). A reader
## rather than `JSON.parse_string`, which logs an engine error to the console on a body that is not JSON.
static func _read_json(text: String) -> Dictionary:
	var trimmed: String = text.strip_edges()
	if trimmed.is_empty():
		return {}
	var reader := JSON.new()
	if reader.parse(trimmed) != OK:
		return {}
	var data: Variant = reader.data
	if data is Dictionary:
		return data
	return {}


static func _status_word(status: int) -> String:
	match status:
		HTTPClient.STATUS_RESOLVING:
			return "the address did not resolve"
		HTTPClient.STATUS_CANT_RESOLVE:
			return "the address did not resolve"
		HTTPClient.STATUS_CONNECTING:
			return "the connection did not finish"
		HTTPClient.STATUS_CANT_CONNECT:
			return "the connection was refused"
		HTTPClient.STATUS_CONNECTION_ERROR:
			return "the connection failed"
		HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			return "the secure handshake failed"
		HTTPClient.STATUS_DISCONNECTED:
			return "the connection was lost"
	return "the reason was not stated"