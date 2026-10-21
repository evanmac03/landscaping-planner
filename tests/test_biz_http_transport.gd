extends Node
## The HTTP sync transport (spec §11.2).
##
## **What is under test is what this build would send**, because that is the part a person can get
## wrong: the path, the `If-Match` header, the `Authorization` header, and whether an id with a slash in
## it stays one id. Sending it needs a deployment (§15), and the one thing that *is* testable without
## one is that a service which cannot be reached is **a refusal that says so** rather than a silence or
## a crash - which is the whole difference between a sync an office can act on and one it cannot.

const TransportScript := preload("res://scripts/biz/sync_transport.gd")
const HttpScript := preload("res://scripts/biz/http_transport.gd")

## An address that resolves instantly and refuses instantly, so the unreachable path is tested without
## a timeout and without a network.
const NOWHERE := "http://127.0.0.1:1"


func _ready_transport() -> BizHttpTransport:
	return HttpScript.new("https://sync.example.com", "a-token")


# --- what it is configured with -----------------------------------------------------------------


func test_a_transport_with_no_address_is_not_configured() -> void:
	var transport: BizHttpTransport = HttpScript.new()
	assert(not transport.is_configured())
	assert(not transport.is_ready())
	assert(transport.describe().contains("no address yet"))


func test_an_address_with_no_token_is_configured_but_not_ready() -> void:
	var transport: BizHttpTransport = HttpScript.new("https://sync.example.com")
	assert(transport.is_configured())
	assert(not transport.is_ready())
	assert(transport.describe().contains("no token"))


func test_an_address_and_a_token_is_ready() -> void:
	var transport: BizHttpTransport = _ready_transport()
	assert(transport.is_ready())
	assert(transport.describe().contains("sync.example.com"))


func test_an_address_that_is_not_an_address_is_not_configured() -> void:
	assert(not HttpScript.new("sync.example.com").is_configured())
	assert(not HttpScript.new("file:///tmp/sync").is_configured())


func test_it_can_do_the_four_things() -> void:
	var transport: BizHttpTransport = _ready_transport()
	assert(transport.capabilities() == TransportScript.CAPABILITIES)
	assert(transport.has_capability(TransportScript.PUSH))


func test_it_has_two_settings_and_the_token_is_the_secret_one() -> void:
	var transport: BizHttpTransport = _ready_transport()
	var held: Array[Dictionary] = transport.settings()
	assert(held.size() == 2)
	assert(String(held[0]["key"]) == HttpScript.BASE_URL)
	assert(not bool(held[0]["secret"]))
	assert(String(held[1]["key"]) == HttpScript.TOKEN)
	assert(bool(held[1]["secret"]))


func test_the_settings_it_takes_are_taken_and_the_others_are_named() -> void:
	var transport: BizHttpTransport = HttpScript.new()
	assert(transport.configure({HttpScript.BASE_URL: "https://sync.example.com", HttpScript.TOKEN: "t"})["ok"])
	assert(transport.is_ready())
	var refused: Dictionary = transport.configure({HttpScript.BASE_URL: "x", "password": "hunter2"})
	assert(not refused["ok"])
	assert(refused["reason"].contains("password"))
	# Nothing was half-saved.
	assert(String(transport.base_url) == "https://sync.example.com")


# --- what would be sent -------------------------------------------------------------------------


func test_a_pull_is_a_get_of_the_change_log_since_the_cursor() -> void:
	var request: Dictionary = _ready_transport().request_for(TransportScript.CHANGES, {"since": 12, "limit": 25})
	assert(int(request["method"]) == HTTPClient.METHOD_GET)
	assert(String(request["path"]) == "/changes?since=12&limit=25")
	assert(String(request["body"]).is_empty())


func test_a_pull_that_does_not_name_a_limit_asks_for_the_default() -> void:
	var request: Dictionary = _ready_transport().request_for(TransportScript.CHANGES, {"since": 0})
	assert(String(request["path"]).contains("limit=%d" % HttpScript.DEFAULT_LIMIT))


func test_every_call_carries_the_token() -> void:
	var request: Dictionary = _ready_transport().request_for(TransportScript.HEALTH, {})
	assert((request["headers"] as Array).has("Authorization: Bearer a-token"))


func test_a_transport_with_no_token_sends_no_authorisation() -> void:
	var request: Dictionary = HttpScript.new("https://sync.example.com").request_for(TransportScript.HEALTH, {})
	for header in (request["headers"] as Array):
		assert(not String(header).begins_with("Authorization"))


func test_a_push_is_a_put_of_the_record_with_if_match() -> void:
	var args: Dictionary = {
		"kind": "invoice", "id": "INV-7", "job": "J-1", "rev": 3,
		"body": {"amount": {"cents": 10000, "currency": "CAD"}}, "who": "evan",
	}
	var request: Dictionary = _ready_transport().request_for(TransportScript.PUSH, args)
	assert(int(request["method"]) == HTTPClient.METHOD_PUT)
	assert(String(request["path"]) == "/records/invoice/INV-7")
	assert((request["headers"] as Array).has("If-Match: 3"))
	assert((request["headers"] as Array).has("Content-Type: application/json"))


func test_a_pushed_body_carries_the_record_and_who_changed_it() -> void:
	var args: Dictionary = {"kind": "invoice", "id": "INV-7", "job": "J-1", "rev": 0, "body": {"a": 1}, "who": "evan"}
	var request: Dictionary = _ready_transport().request_for(TransportScript.PUSH, args)
	var reader := JSON.new()
	assert(reader.parse(String(request["body"])) == OK)
	var body: Dictionary = reader.data
	assert(String(body["kind"]) == "invoice")
	assert(String(body["id"]) == "INV-7")
	assert(String(body["job"]) == "J-1")
	assert(String(body["who"]) == "evan")
	assert(int(body["body"]["a"]) == 1)


func test_an_id_with_a_slash_in_it_stays_one_id() -> void:
	var request: Dictionary = _ready_transport().request_for(
		TransportScript.PUSH, {"kind": "invoice", "id": "a/b", "job": "", "rev": 0, "body": {}, "who": ""}
	)
	assert(String(request["path"]) == "/records/invoice/a%2Fb")


func test_the_deployment_checks_are_where_the_service_puts_them() -> void:
	assert(String(_ready_transport().request_for(TransportScript.HEALTH, {})["path"]) == "/health")
	assert(String(_ready_transport().request_for("whoami", {})["path"]) == "/whoami")


func test_an_attachment_is_posted_apart_from_the_records() -> void:
	var request: Dictionary = _ready_transport().request_for(TransportScript.ATTACHMENTS, {"name": "receipt.jpg"})
	assert(int(request["method"]) == HTTPClient.METHOD_POST)
	assert(String(request["path"]) == "/attachments")
	assert((request["headers"] as Array).has("X-Attachment-Name: receipt.jpg"))


# --- the address, split -------------------------------------------------------------------------


func test_an_https_address_is_read_with_its_port() -> void:
	var parts: Dictionary = _ready_transport()._split_base()
	assert(bool(parts["tls"]))
	assert(String(parts["host"]) == "sync.example.com")
	assert(int(parts["port"]) == 443)
	assert(String(parts["prefix"]).is_empty())


func test_an_http_address_defaults_to_port_eighty() -> void:
	var parts: Dictionary = HttpScript.new("http://localhost")._split_base()
	assert(not bool(parts["tls"]))
	assert(int(parts["port"]) == 80)


func test_a_port_stated_in_the_address_is_the_one_used() -> void:
	var parts: Dictionary = HttpScript.new("http://localhost:9000")._split_base()
	assert(String(parts["host"]) == "localhost")
	assert(int(parts["port"]) == 9000)


func test_a_path_prefix_is_kept_and_used_in_front_of_every_call() -> void:
	var transport: BizHttpTransport = HttpScript.new("https://example.com/api/sync/", "t")
	assert(String(transport._split_base()["prefix"]) == "/api/sync")
	assert(String(transport.request_for(TransportScript.HEALTH, {})["path"]) == "/api/sync/health")


# --- nowhere to send it to ----------------------------------------------------------------------


func test_a_call_with_no_address_refuses_rather_than_sending_an_anonymous_request() -> void:
	var transport: BizHttpTransport = HttpScript.new()
	var answer: Dictionary = transport.changes()
	assert(not answer["ok"])
	assert(answer["reason"].contains("token"))
	assert(int(answer["status"]) == 0)


func test_an_address_nobody_answers_is_a_refusal_that_says_so() -> void:
	var transport: BizHttpTransport = HttpScript.new(NOWHERE, "t")
	var answer: Dictionary = transport.changes()
	assert(not answer["ok"])
	assert(int(answer["status"]) == 0)
	assert(bool(answer["retry"]))
	assert(answer["reason"].contains("127.0.0.1"))


func test_a_push_to_nowhere_is_not_recorded_as_a_conflict() -> void:
	var transport: BizHttpTransport = HttpScript.new(NOWHERE, "t")
	var answer: Dictionary = transport.push("invoice", "INV-1", "J-1", {}, 0, "evan")
	assert(not answer["ok"])
	assert(not bool(answer["conflict"]))
	assert(bool(answer["retry"]))


func test_the_health_check_against_nowhere_says_it_could_not_reach_it() -> void:
	var transport: BizHttpTransport = HttpScript.new(NOWHERE, "t")
	var answer: Dictionary = transport.health()
	assert(not answer["ok"])
	assert(String(answer["service"]).is_empty())