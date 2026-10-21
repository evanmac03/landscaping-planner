extends Node
## The transport interface and the rule every status is read by (spec §11.2).
##
## The base does nothing, and what is under test is that it **says so** rather than reporting an empty
## success: a sync that answers "nothing to do" when it has nowhere to talk is worse than one that
## refuses, because the office believes it. The retry rule is shared with the ledger adapters - status
## 0 and a momentary inability are worth another try, a service that said no is not.

const TransportScript := preload("res://scripts/biz/sync_transport.gd")


# --- the base that does nothing -----------------------------------------------------------------


func test_a_base_transport_has_no_name_and_nothing_configured() -> void:
	var base: BizSyncTransport = TransportScript.new()
	assert(String(base.name()).is_empty())
	assert(not base.is_configured())
	assert(not base.is_ready())
	assert(base.capabilities().is_empty())
	assert(base.settings().is_empty())


func test_every_call_the_base_cannot_make_says_which_one() -> void:
	var base: BizSyncTransport = TransportScript.new()
	assert(base.changes()["reason"].contains("changes"))
	assert(base.push("invoice", "INV-1", "J-1", {}, 0)["reason"].contains("push"))
	assert(base.attachment("a.jpg", PackedByteArray())["reason"].contains("attachments"))
	assert(base.health()["reason"].contains("health"))
	assert(base.whoami()["reason"].contains("whoami"))


func test_each_refusal_the_base_gives_is_not_a_retry() -> void:
	var base: BizSyncTransport = TransportScript.new()
	for answer in [base.changes(), base.push("invoice", "INV-1", "J-1", {}, 0), base.health()]:
		assert(not bool(answer["ok"]))
		assert(int(answer["status"]) == 0)
		assert(not bool(answer["retry"]))


func test_configuring_a_base_transport_is_refused_in_words() -> void:
	var base: BizSyncTransport = TransportScript.new()
	assert(not base.configure({"anything": "at all"})["ok"])
	assert(base.describe().contains("no transport"))


func test_a_capability_nobody_has_is_not_had() -> void:
	var base: BizSyncTransport = TransportScript.new()
	assert(not base.has_capability(TransportScript.PUSH))
	assert(not base.has_capability("teleport"))


# --- the one retry rule -------------------------------------------------------------------------


func test_the_service_never_reached_is_worth_trying_again() -> void:
	assert(BizSyncTransport.is_retryable(0))


func test_a_momentary_inability_is_worth_trying_again_and_a_refusal_is_not() -> void:
	for status in [408, 425, 429, 500, 502, 503, 504, 599]:
		assert(BizSyncTransport.is_retryable(status))
	for status in [400, 401, 403, 404, 409, 422]:
		assert(not BizSyncTransport.is_retryable(status))


func test_a_refusal_is_only_a_retry_when_it_says_so() -> void:
	assert(not bool(BizSyncTransport.refused("no")["retry"]))
	assert(bool(BizSyncTransport.refused("busy", true)["retry"]))
	assert(not bool(BizSyncTransport.refused("no")["ok"]))


# --- why a status was not a success -------------------------------------------------------------


func test_a_status_reads_as_words_an_office_can_act_on() -> void:
	assert(BizSyncTransport.status_reason(401, "the service", "") == "401 the token was refused")
	assert(BizSyncTransport.status_reason(403, "the service", "").contains("may not do that"))
	assert(BizSyncTransport.status_reason(404, "the service", "").contains("no such record"))
	assert(BizSyncTransport.status_reason(409, "the service", "").contains("someone else changed it first"))
	assert(BizSyncTransport.status_reason(422, "the service", "").contains("would not take the record"))


func test_a_server_error_reads_as_try_again_and_another_as_a_refusal() -> void:
	assert(BizSyncTransport.status_reason(503, "the service", "").contains("try again"))
	assert(BizSyncTransport.status_reason(418, "the service", "").contains("refused the request"))


func test_what_the_service_said_is_carried_into_the_reason() -> void:
	assert(BizSyncTransport.status_reason(422, "the service", "the field 'amount' is not a number")
		.contains("the field 'amount' is not a number"))


# --- the two tables the module agrees on --------------------------------------------------------


func test_the_four_calls_are_the_ones_the_service_has() -> void:
	assert(TransportScript.CAPABILITIES == ["changes", "push", "attachments", "health"])


func test_the_four_roles_are_the_ones_the_service_holds() -> void:
	assert(TransportScript.ROLES == ["OWNER", "OFFICE", "FIELD", "VIEWER"])