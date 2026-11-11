extends Node
## One request in flight, advanced a frame at a time.
##
## Nothing here opens a socket: `next_move` is the whole state machine as arithmetic over a status and
## two clocks, so a dead port, a model thinking for three minutes and a download that has gone quiet are
## all just numbers. `split_lines` is asked the same way. The two halves that *do* touch the world - the
## `step` that looks at a client, and the driver that runs it in a loop - are asked only what they answer
## when they were never given a request to wait on.
##
## The measurement the connecting rules rest on, taken on this project's own Windows machine: a live
## socket reaches `STATUS_CONNECTED` in about thirteen milliseconds, while a port nobody is listening on
## **never leaves `STATUS_CONNECTING`** - `poll()` keeps answering OK and the status never becomes
## `STATUS_CANT_CONNECT`. So a dead address cannot be told from a slow server by the status alone.

const Exchange := preload("res://scripts/http_exchange.gd")

const ANSWER_SECONDS := 180.0
const CONNECT_SECONDS := 1.5


## What the machine says about a request in this state.
func _move(
	stage: StringName, status: int, since_stage_ms: int = 0, since_bytes_ms: int = 0
) -> Dictionary:
	return Exchange.next_move(
		stage, status, since_stage_ms, since_bytes_ms, ANSWER_SECONDS, CONNECT_SECONDS
	)


# --- connecting -------------------------------------------------------------------------------------


func test_a_connection_that_is_not_up_yet_is_waited_for_rather_than_given_up_on() -> void:
	var move: Dictionary = _move(Exchange.CONNECTING, HTTPClient.STATUS_CONNECTING)
	assert(StringName(move["move"]) == Exchange.WAIT, "a socket still opening is waited for: %s" % str(move))
	assert(StringName(move["stage"]) == Exchange.CONNECTING, "and the stage has not moved on")


func test_a_connection_that_is_up_asks_for_the_request_to_be_sent() -> void:
	var move: Dictionary = _move(Exchange.CONNECTING, HTTPClient.STATUS_CONNECTED)
	assert(StringName(move["move"]) == Exchange.SEND, "the socket is open, so the request goes: %s" % str(move))
	assert(StringName(move["stage"]) == Exchange.REQUESTING, "and the exchange is now waiting to be answered")


func test_a_socket_that_never_connected_is_given_up_on_at_its_own_short_budget() -> void:
	# The measurement, as a rule: nothing listening leaves a socket in `STATUS_CONNECTING` forever, so the
	# clock is the only thing that can tell a dead address from a slow server - and it must be the
	# connecting clock, not the one a model is allowed to think for.
	var almost: Dictionary = _move(Exchange.CONNECTING, HTTPClient.STATUS_CONNECTING, 1499)
	assert(StringName(almost["move"]) == Exchange.WAIT, "one millisecond short is still within the budget")
	var done: Dictionary = _move(Exchange.CONNECTING, HTTPClient.STATUS_CONNECTING, 1500)
	assert(StringName(done["move"]) == Exchange.REFUSE, "and at the budget it is given up on: %s" % str(done))
	assert(
		StringName(done["because"]) == Exchange.LOST_CONNECTION,
		"and what it gives up on is the connection: %s" % done["because"]
	)


func test_a_name_that_does_not_resolve_is_refused_before_its_budget_is_spent() -> void:
	# A DNS failure is knowable at once, so making somebody wait even a second and a half to be told their
	# address is misspelled would be waiting for nothing.
	var move: Dictionary = _move(Exchange.CONNECTING, HTTPClient.STATUS_CANT_RESOLVE)
	assert(StringName(move["move"]) == Exchange.REFUSE, "it is a refusal immediately: %s" % str(move))
	assert(StringName(move["because"]) == Exchange.LOST_CONNECTION, "and about the connection")


# --- waiting to be answered -------------------------------------------------------------------------


func test_a_model_that_is_still_thinking_is_waited_for_within_its_budget_and_not_after_it() -> void:
	var thinking: Dictionary = _move(Exchange.REQUESTING, HTTPClient.STATUS_REQUESTING, 179000)
	assert(StringName(thinking["move"]) == Exchange.WAIT, "a model may think for its full three minutes")
	var gone: Dictionary = _move(Exchange.REQUESTING, HTTPClient.STATUS_REQUESTING, 180000)
	assert(StringName(gone["move"]) == Exchange.REFUSE, "and no longer: %s" % str(gone))
	assert(
		StringName(gone["because"]) == Exchange.LOST_ANSWER,
		"the refusal is about the answer, not about the connection: %s" % gone["because"]
	)


func test_the_patience_is_the_callers_and_not_a_constant_hidden_in_the_wire() -> void:
	# The whole reason `answer_seconds` is an argument: asking a machine what models it has deserves a
	# second, and asking a vision model to read a photograph deserves minutes. One number in the wire
	# would be a third opinion about both.
	var impatient: Dictionary = Exchange.next_move(
		Exchange.REQUESTING, HTTPClient.STATUS_REQUESTING, 10000, 0, 10.0, CONNECT_SECONDS
	)
	assert(StringName(impatient["move"]) == Exchange.REFUSE, "ten seconds of patience gives up at ten seconds")
	var patient: Dictionary = Exchange.next_move(
		Exchange.REQUESTING, HTTPClient.STATUS_REQUESTING, 10000, 0, ANSWER_SECONDS, CONNECT_SECONDS
	)
	assert(StringName(patient["move"]) == Exchange.WAIT, "and three minutes of it is still waiting")


func test_an_answer_that_has_started_arriving_is_read() -> void:
	var move: Dictionary = _move(Exchange.REQUESTING, HTTPClient.STATUS_BODY)
	assert(StringName(move["move"]) == Exchange.READ, "there are bytes to take: %s" % str(move))
	assert(StringName(move["stage"]) == Exchange.READING, "and the request has become a body")


# --- reading a body ---------------------------------------------------------------------------------


func test_a_body_that_keeps_arriving_is_never_a_stall_however_long_the_whole_of_it_takes() -> void:
	# A three-gigabyte fetch takes ten minutes and is not a stall. The clock that matters is the one since
	# the last byte, and the machine has to be told which of the two it is being given - hence the rule.
	var early: Dictionary = _move(Exchange.READING, HTTPClient.STATUS_BODY, 600000, 0)
	assert(StringName(early["move"]) == Exchange.READ, "ten minutes into a download, bytes are still read")
	var nearly: Dictionary = _move(Exchange.READING, HTTPClient.STATUS_BODY, 600000, 179999)
	assert(StringName(nearly["move"]) == Exchange.READ, "and so are bytes that came a moment ago")


func test_a_body_that_has_gone_quiet_is_a_stall_and_is_refused_as_one() -> void:
	var stalled: Dictionary = _move(Exchange.READING, HTTPClient.STATUS_BODY, 600000, 180000)
	assert(StringName(stalled["move"]) == Exchange.REFUSE, "a silent body is given up on: %s" % str(stalled))
	assert(
		StringName(stalled["because"]) == Exchange.LOST_STALLED,
		"and the refusal says it stopped rather than that it was never sent: %s" % stalled["because"]
	)


func test_the_end_of_a_body_is_the_end_of_the_request() -> void:
	# Both endings are normal: a keep-alive socket goes back to connected, and a server that closes after
	# answering leaves the socket disconnected. What arrived is what there is, and whether it can be read
	# is the reader's business rather than the wire's.
	var kept_alive: Dictionary = _move(Exchange.READING, HTTPClient.STATUS_CONNECTED)
	assert(StringName(kept_alive["move"]) == Exchange.FINISH, "a keep-alive socket has finished answering")
	var closed: Dictionary = _move(Exchange.READING, HTTPClient.STATUS_DISCONNECTED)
	assert(StringName(closed["move"]) == Exchange.FINISH, "and so has one that was closed underneath us")


func test_a_connection_that_breaks_while_the_body_is_arriving_says_that_rather_than_a_stall() -> void:
	var broke: Dictionary = _move(Exchange.READING, HTTPClient.STATUS_CONNECTION_ERROR)
	assert(StringName(broke["move"]) == Exchange.REFUSE, "a broken connection is a refusal: %s" % str(broke))
	assert(
		StringName(broke["because"]) == Exchange.LOST_BODY,
		"and it is worded as the body breaking, not as the body going quiet: %s" % broke["because"]
	)


# --- what a refusal says ----------------------------------------------------------------------------


func test_connect_refusal_names_where_and_what_rather_than_the_feature() -> void:
	var unresolved: String = Exchange.connect_refusal(HTTPClient.STATUS_CANT_RESOLVE, "nope.invalid", 11434)
	assert(unresolved.contains("does not resolve"), "a name that cannot be resolved says so: %s" % unresolved)
	var nothing: String = Exchange.connect_refusal(HTTPClient.STATUS_CANT_CONNECT, "127.0.0.1", 8080)
	assert(nothing.contains("nothing is listening"), "a refused socket is a server that is not up: %s" % nothing)
	var broke: String = Exchange.connect_refusal(HTTPClient.STATUS_CONNECTION_ERROR, "example.invalid", 443)
	assert(broke.contains("broke"), "a connection that broke says so: %s" % broke)
	var refused_tls: String = Exchange.connect_refusal(
		HTTPClient.STATUS_TLS_HANDSHAKE_ERROR, "example.invalid", 443
	)
	assert(refused_tls.contains("secure"), "and a refused handshake says that: %s" % refused_tls)
	var stuck: String = Exchange.connect_refusal(HTTPClient.STATUS_CONNECTING, "127.0.0.1", 8080)
	assert(stuck.contains("nothing is listening"), "a socket stuck connecting is read as nothing there")
	assert(stuck.contains("127.0.0.1:8080"), "and it names where: %s" % stuck)
	assert(
		not stuck.contains("seconds"),
		"and does not blame the clock, which is what the first version of this said: %s" % stuck
	)


func test_every_way_a_request_can_fail_is_worded_differently() -> void:
	# Five different things with five different fixes, and a program that said one sentence for all of
	# them would leave somebody trying the wrong one.
	var said: Array[String] = []
	for because: StringName in [
		Exchange.LOST_CONNECTION, Exchange.LOST_SEND, Exchange.LOST_ANSWER, Exchange.LOST_BODY,
		Exchange.LOST_STALLED,
	]:
		var words: String = Exchange.refusal_words(because, HTTPClient.STATUS_CONNECTING, "127.0.0.1", 11434, ANSWER_SECONDS)
		assert(not words.is_empty(), "%s is worded rather than silent" % because)
		assert(words.contains("127.0.0.1"), "%s names where it happened: %s" % [because, words])
		assert(not said.has(words), "%s is not the same sentence as another: %s" % [because, words])
		said.append(words)


func test_a_budget_of_three_minutes_is_said_in_seconds_rather_than_as_a_count() -> void:
	var answer: String = Exchange.refusal_words(
		Exchange.LOST_ANSWER, HTTPClient.STATUS_REQUESTING, "127.0.0.1", 11434, ANSWER_SECONDS
	)
	assert(answer.contains("180 seconds"), "how long was given is the useful half of it: %s" % answer)
	var stopped: String = Exchange.refusal_words(
		Exchange.LOST_STALLED, HTTPClient.STATUS_BODY, "127.0.0.1", 11434, 30.0
	)
	assert(stopped.contains("30 seconds"), "and the same number said the same way: %s" % stopped)


# --- lines out of a streamed body -------------------------------------------------------------------


func test_complete_lines_are_split_off_a_streamed_body_and_the_rest_is_held() -> void:
	var split: Dictionary = Exchange.split_lines(PackedByteArray(), "pulling manifest\ndownloading\npar".to_utf8_buffer())
	var lines: Array = split["lines"]
	assert(lines.size() == 2, "the two complete lines: %s" % str(lines))
	assert(String(lines[0]) == "pulling manifest", "the first one as it was written: %s" % lines[0])
	assert(String(lines[1]) == "downloading", "and the second")
	assert(
		(split["pending"] as PackedByteArray) == "par".to_utf8_buffer(),
		"and the start of a third is held rather than reported half-read"
	)


func test_the_rest_of_a_line_is_held_until_the_rest_of_it_arrives() -> void:
	var split: Dictionary = Exchange.split_lines("par".to_utf8_buffer(), "tial\n".to_utf8_buffer())
	var lines: Array = split["lines"]
	assert(lines.size() == 1, "the line arrived in two pieces and is one line: %s" % str(lines))
	assert(String(lines[0]) == "partial", "put back together rather than read as two: %s" % lines[0])
	assert((split["pending"] as PackedByteArray).is_empty(), "and nothing is left over")


func test_a_character_cut_in_half_by_two_chunks_is_put_back_together() -> void:
	# Lines are split over **bytes**, not over a string: a body with anything but plain ASCII in it can
	# have a character's bytes divided between two chunks, and decoding each half alone would give two
	# wrong characters where the server sent one right one.
	var first: Dictionary = Exchange.split_lines(PackedByteArray(), PackedByteArray([0xC3]))
	assert((first["lines"] as Array).is_empty(), "half a character is not a line")
	assert((first["pending"] as PackedByteArray).size() == 1, "it is held until the rest of it arrives")
	var second: Dictionary = Exchange.split_lines(first["pending"], PackedByteArray([0xA9, 10]))
	var lines: Array = second["lines"]
	assert(lines.size() == 1, "and then it is one line: %s" % str(lines))
	assert(String(lines[0]) == "é", "with the character the server actually sent: %s" % lines[0])


# --- the two halves that do touch the world ---------------------------------------------------------


func test_a_request_that_was_never_begun_is_refused_rather_than_waited_on_forever() -> void:
	var exchange: HttpExchange = Exchange.new()
	assert(
		exchange.step() == Exchange.REFUSED,
		"an exchange nothing was begun on has nothing to wait for"
	)
	assert(not String(exchange.result()["why"]).is_empty(), "and the refusal says so: %s" % exchange.result()["why"])


func test_a_request_that_could_not_be_built_is_refused_before_any_socket_is_opened() -> void:
	# The refusal the builder already wrote is the one that survives, rather than being replaced by
	# something about a connection that was never attempted.
	var exchange: HttpExchange = Exchange.new()
	var verdict: StringName = exchange.begin(
		{"ok": false, "reason": "the address of a model has to begin http:// or https://"}, ANSWER_SECONDS,
		CONNECT_SECONDS
	)
	assert(verdict == Exchange.REFUSED, "there is nothing to send")
	var sent: Dictionary = exchange.result()
	assert(String(sent["why"]).contains("begin http://"), "and the builder's own words are kept: %s" % sent["why"])
	assert(int(sent["status"]) == 0, "nothing came back, because nothing went out")
	assert(not bool(sent["reached"]), "and no machine was ever reached")


func test_the_result_reads_the_way_the_sender_that_wraps_it_does() -> void:
	# `PlantIdentifier.send_http` is this machine driven in a loop, and a caller reading one reads the
	# other - so the shape has to be the one that pipeline has always understood.
	var exchange: HttpExchange = Exchange.new()
	exchange.begin({"ok": false, "reason": "nothing to send"}, ANSWER_SECONDS, CONNECT_SECONDS)
	var sent: Dictionary = exchange.result()
	for key: String in ["status", "body", "why", "reached"]:
		assert(sent.has(key), "the result carries %s, which is what a reader of an answer reads" % key)
	assert(typeof(sent["status"]) == TYPE_INT, "a status is a number")
	assert(typeof(sent["body"]) == TYPE_STRING, "and a body is the words that came back")