class_name HttpExchange
extends RefCounted
## One request in flight, advanced a frame at a time.
##
## ## Why this exists
##
## `HTTPClient.poll()` does not block: a request is a socket that has to be looked at repeatedly until it
## answers. `PlantIdentifier.send_http` used to do that looking **inside a single call**, which meant
## that while a vision model thought about a photograph the whole program drew no frame at all - a page
## frozen for as long as the model took. The same act done the other way round is this object: one
## request held, stepped once per frame by whoever is waiting on it.
##
## ## One machine, one driver
##
## `send_http` is still how a request is sent and waited for inside a call, and it is now **nothing but
## this machine driven to completion**. So the rules about clocks, stages and refusals live here once:
## a second loop elsewhere would be a second place the faults this file already documents could come
## back, and those faults have cost this project two whole readings.
##
## ## The decision is pure; the looking is not
##
## `next_move` is the whole state machine as arithmetic over a status and two clocks - no socket, no
## `HTTPClient`, nothing to be. `step` is the one method that touches the world: it looks at the client
## and does what `next_move` said. That split is what lets every rule below be held down by a test with
## no server, no network and no frame.
##
## ## Three clocks, and why connecting gets its own
##
## A socket gets the caller's `connect_seconds` to connect, the answer gets `answer_seconds` to start
## arriving, and a body gets `answer_seconds` **between bytes**. The middle one is where a model is
## allowed to think. The last one is what makes a long download safe, because bytes arriving reset it: a
## three-gigabyte fetch taking ten minutes is not a stall, and only a body that has gone quiet for
## `answer_seconds` is.
##
## **Measured, and the reason connecting is separate**: a port nobody is listening on never leaves
## `STATUS_CONNECTING` on this project's machine - `poll()` keeps answering OK and the status never
## becomes `STATUS_CANT_CONNECT` - so a dead address cannot be told from a slow server by the status
## alone. Only a short budget for connecting distinguishes them, and without it a mistyped address costs
## the whole time a model is allowed.

## How the exchange is getting on.
const WORKING := &"working"
const DONE := &"done"
const REFUSED := &"refused"

## Where in the act it is.
const CONNECTING := &"connecting"
const REQUESTING := &"requesting"
const READING := &"reading"

## What should happen next.
const WAIT := &"wait"
const SEND := &"send"
const READ := &"read"
const FINISH := &"finish"
const REFUSE := &"refuse"

## Why it gave up, as a **word** rather than a sentence. The sentence is `refusal_words`'s business,
## because wording a refusal needs a host and a port and the machine deliberately has neither.
const LOST_CONNECTION := &"connect"
const LOST_SEND := &"send"
const LOST_ANSWER := &"answer"
const LOST_BODY := &"body"
const LOST_STALLED := &"stalled"

## How long a **blocking** driver pauses between looks. A caller stepping this once per frame passes
## nothing: the frame is already the pause, and sleeping inside a frame is how a program comes to feel
## sluggish for no reason.
const PAUSE_MS := 5

## How many chunks are taken out of a body in one step.
##
## One per step would spread a many-chunk body over a frame per chunk for no reason, and taking them all
## unboundedly would let a server hold a frame open by never stopping. This is between the two.
const DRAIN_PER_STEP := 256

## The most of a body that is kept in memory.
##
## A body is read for its words - a model's answer, a list of models, a download's progress lines - and
## none of those is large. But a server that answered a request for a models list with something enormous
## should not be able to fill this program's memory, so past this the bytes are counted and dropped and
## `result` says the body was cut.
const BODY_CAP_BYTES := 2000000

var _client: HTTPClient = null
var _request: Dictionary = {}
var _stage: StringName = CONNECTING
var _verdict: StringName = WORKING
var _why: String = ""
var _status: int = 0
var _body: PackedByteArray = PackedByteArray()
var _pending: PackedByteArray = PackedByteArray()
var _lines: Array[String] = []
var _body_cut: bool = false
var _received: int = 0
var _reached: bool = false
var _answer_seconds: float = 0.0
var _connect_seconds: float = 0.0
var _stage_at_ms: int = 0
var _bytes_at_ms: int = 0


## Start one request, and say whether there is anything to wait for.
##
## The patience is the **caller's**, stated rather than defaulted: two callers want very different
## answers, and a constant hidden in here would be a third opinion about how long a model may think. The
## request is the shape `PlantIdLlm.build_request` and `LocalModelProbe` build - `{ok, reason, tls, host,
## port, path, method, headers, body}`.
func begin(
	request: Dictionary, answer_seconds: float, connect_seconds: float
) -> StringName:
	_request = request
	_answer_seconds = answer_seconds
	_connect_seconds = connect_seconds
	_client = null
	_body = PackedByteArray()
	_pending = PackedByteArray()
	_lines.clear()
	_body_cut = false
	_received = 0
	_reached = false
	_why = ""
	_status = 0
	_verdict = WORKING
	_stage = CONNECTING
	var now: int = Time.get_ticks_msec()
	_stage_at_ms = now
	_bytes_at_ms = now
	if not bool(request.get("ok", true)):
		_refuse(String(request.get("reason", "the request could not be built")))
		return _verdict
	_client = HTTPClient.new()
	var error: int = OK
	if bool(request.get("tls", false)):
		error = _client.connect_to_host(_host(), _port(), TLSOptions.client())
	else:
		error = _client.connect_to_host(_host(), _port())
	if error != OK:
		_refuse("cannot reach %s" % _host())
	return _verdict


## Look at the socket once and do what the machine says, answering `WORKING` until it is not.
##
## `pause_ms` is for a driver with nothing else to do between looks. A caller stepping this from a frame
## leaves it at zero.
func step(pause_ms: int = 0) -> StringName:
	if _verdict != WORKING:
		return _verdict
	if _client == null:
		_refuse("no request was ever begun, so there is nothing to wait for")
		return _verdict
	var now: int = Time.get_ticks_msec()
	var move: Dictionary = next_move(
		_stage,
		_client.get_status(),
		now - _stage_at_ms,
		now - _bytes_at_ms,
		_answer_seconds,
		_connect_seconds
	)
	match StringName(move["move"]):
		WAIT:
			_client.poll()
			if pause_ms > 0:
				OS.delay_msec(pause_ms)
		SEND:
			_stage = REQUESTING
			_stage_at_ms = now
			_bytes_at_ms = now
			_send_now()
		READ:
			if _stage != READING:
				_stage = READING
				_stage_at_ms = now
				_bytes_at_ms = now
			# Read what is already there **before** looking again: the engine refuses to hand over a
			# chunk once it considers the body finished, so a read after a look that ended the body is an
			# error rather than an empty answer.
			_drain_the_body(now)
			_client.poll()
		FINISH:
			_drain_the_body(now)
			_status = _client.get_response_code()
			_client.close()
			_verdict = DONE
		REFUSE:
			var state: int = _client.get_status()
			_client.close()
			_refuse(refusal_words(StringName(move["because"]), state, _host(), _port(), _answer_seconds))
	return _verdict


## Which stage the exchange gave up in, or is in: `WORKING`, `DONE` or `REFUSED`.
func verdict() -> StringName:
	return _verdict


## Where in the act it is: connecting, waiting to be answered, or reading.
func stage() -> StringName:
	return _stage


## What came back, in the same shape `PlantIdentifier.send_http` has always answered with, so that a
## caller reading one reads the other.
func result() -> Dictionary:
	return {
		"status": _status,
		"body": _body.get_string_from_utf8(),
		"why": _why,
		"reached": _reached,
		"body_cut": _body_cut,
		"received_bytes": _received,
	}


## The complete lines that have arrived since this was last asked, and forget them.
##
## A streamed answer - Ollama fetching a model sends one line per step - is read a line at a time rather
## than as one body, because a page showing how far along a download is wants the newest line and not the
## whole of what has arrived. A caller that never asks loses nothing: the body is kept as well.
func take_lines() -> Array[String]:
	var taken: Array[String] = _lines
	_lines = [] as Array[String]
	return taken


## How many bytes of body have arrived, whether or not they were all kept.
func received_bytes() -> int:
	return _received


# --- the machine, with the world taken out of it ----------------------------------------------------


## What should happen to a request in this state, as pure arithmetic over a status and two clocks.
##
## Every rule of the exchange is here and nowhere else, which is why all of them can be tested without a
## socket: `since_stage_ms` is how long the current stage has been going on, and `since_bytes_ms` is how
## long since any byte of the body arrived - the one that makes a long download safe.
##
## The parameter is `at_stage` and not `stage`, because a class may not name a parameter after one of its
## own methods: `stage()` is the accessor a caller reads, and the engine reports that shadowing as an
## **error** rather than as a warning.
static func next_move(
	at_stage: StringName,
	status: int,
	since_stage_ms: int,
	since_bytes_ms: int,
	answer_seconds: float,
	connect_seconds: float
) -> Dictionary:
	var connect_ms: int = int(connect_seconds * 1000.0)
	var answer_ms: int = int(answer_seconds * 1000.0)
	match at_stage:
		CONNECTING:
			if status == HTTPClient.STATUS_CONNECTED:
				return _a_move(REQUESTING, SEND)
			if _lost(status) or since_stage_ms >= connect_ms:
				return _a_move(CONNECTING, REFUSE, LOST_CONNECTION)
			return _a_move(CONNECTING, WAIT)
		REQUESTING:
			if status == HTTPClient.STATUS_BODY or status == HTTPClient.STATUS_CONNECTED:
				return _a_move(READING, READ)
			if _lost(status) or since_stage_ms >= answer_ms:
				return _a_move(REQUESTING, REFUSE, LOST_ANSWER)
			return _a_move(REQUESTING, WAIT)
		READING:
			# A body that is still arriving is read, however long the whole of it takes: the clock that
			# matters is the one since the last byte, not the one since the request went out.
			if status == HTTPClient.STATUS_BODY:
				if since_bytes_ms >= answer_ms:
					return _a_move(READING, REFUSE, LOST_STALLED)
				return _a_move(READING, READ)
			# The body has ended: a keep-alive socket goes back to connected, and one that was closed
			# underneath us is still the end of what was sent. Either way what arrived is what there is,
			# and whether it can be read is the reader's business.
			if status == HTTPClient.STATUS_CONNECTED or status == HTTPClient.STATUS_DISCONNECTED:
				return _a_move(READING, FINISH)
			if _lost(status) or since_bytes_ms >= answer_ms:
				return _a_move(READING, REFUSE, LOST_BODY)
			return _a_move(READING, WAIT)
	return _a_move(at_stage, REFUSE, LOST_ANSWER)


## Whether a socket is in a state it will never come back from.
static func _lost(status: int) -> bool:
	match status:
		HTTPClient.STATUS_DISCONNECTED, HTTPClient.STATUS_CANT_RESOLVE, \
		HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CONNECTION_ERROR, \
		HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			return true
	return false


static func _a_move(
	at_stage: StringName, move: StringName, because: StringName = &""
) -> Dictionary:
	return {"stage": at_stage, "move": move, "because": because}


## A complete line is one that ends in a newline; anything after the last newline is held until the rest
## of it arrives.
##
## Split over **bytes** and not over a string, so that a character whose bytes are cut in half by two
## chunks - which happens whenever a body carries anything but plain ASCII - is put back together rather
## than decoded as two wrong characters. `{lines, pending}`.
static func split_lines(pending: PackedByteArray, chunk: PackedByteArray) -> Dictionary:
	var held: PackedByteArray = pending
	held.append_array(chunk)
	var lines: Array[String] = []
	var start: int = 0
	for i: int in held.size():
		if held[i] != 10:
			continue
		var line: String = held.slice(start, i).get_string_from_utf8().strip_edges()
		if not line.is_empty():
			lines.append(line)
		start = i + 1
	return {"lines": lines, "pending": held.slice(start)}


## Why the exchange gave up, in the words of whatever stage it gave up in.
##
## A refusal names what stopped rather than the feature: an address nothing is listening at, a request
## that could not be sent, a model that never began answering, a connection that broke mid-answer, and a
## body that went quiet are five different things and five different fixes.
static func refusal_words(
	because: StringName, status: int, host: String, port: int, seconds: float
) -> String:
	match because:
		LOST_SEND:
			return "the request could not be sent to %s:%d" % [host, port]
		LOST_ANSWER:
			return "%s did not answer within %d seconds" % [host, int(seconds)]
		LOST_BODY:
			return "the connection to %s:%d broke while its answer was arriving" % [host, port]
		LOST_STALLED:
			return "the answer from %s stopped arriving: nothing came for %d seconds" % [
				host, int(seconds),
			]
	return connect_refusal(status, host, port)


## Why a connection was never made, in the words of whatever stopped it.
##
## The three answers are different things and want different things done: a name that does not resolve is
## a typo in the address, nothing listening is a server that is not running, and a connection that broke
## or a handshake that failed is something in between this program and the machine. `STATUS_CONNECTING`
## is the fourth case, and the one measurement bought: it is what a socket says forever when nobody
## accepts it, so a connection still in it after its budget is reported as nothing listening rather than
## as a server that was slow.
static func connect_refusal(state: int, host: String, port: int) -> String:
	match state:
		HTTPClient.STATUS_CANT_RESOLVE:
			return "no connection could be made to %s: that name does not resolve to a machine" % host
		HTTPClient.STATUS_CANT_CONNECT:
			return "no connection could be made to %s:%d: nothing is listening there" % [host, port]
		HTTPClient.STATUS_CONNECTION_ERROR:
			return "the connection to %s:%d broke before it was made" % [host, port]
		HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			return "the secure connection to %s:%d was refused" % [host, port]
	return "no connection could be made to %s:%d, which usually means nothing is listening there" % [
		host, port,
	]


# --- the parts that touch the socket -----------------------------------------------------------------


func _send_now() -> void:
	var headers: PackedStringArray = []
	for header: Variant in Array(_request.get("headers", [])):
		headers.append(String(header))
	var error: int = _client.request(
		int(_request.get("method", HTTPClient.METHOD_GET)),
		String(_request.get("path", "/")),
		headers,
		String(_request.get("body", ""))
	)
	if error != OK:
		_client.close()
		_refuse(refusal_words(LOST_SEND, 0, _host(), _port(), _answer_seconds))
		return
	_reached = true


## Take everything the client has of the body, keeping the bytes, counting them, and splitting off
## complete lines.
##
## The body is read **while it arrives** rather than waited for first: a socket that fills up while nobody
## is reading it stops the answer arriving at all.
##
## **The status is checked before every read**, and that is not a precaution but what the engine requires:
## `read_response_body_chunk` refuses and logs a runtime error once the client considers the body
## finished, which a read after a look that ended it is exactly. This was found by a live run against a
## real server - no unit test can see it, because no unit test has a socket.
func _drain_the_body(now: int) -> void:
	var looks: int = 0
	while looks < DRAIN_PER_STEP and _client.get_status() == HTTPClient.STATUS_BODY:
		var chunk: PackedByteArray = _client.read_response_body_chunk()
		if chunk.is_empty():
			return
		_keep(chunk, now)
		looks += 1


func _keep(chunk: PackedByteArray, now: int) -> void:
	_bytes_at_ms = now
	_received += chunk.size()
	var room: int = BODY_CAP_BYTES - _body.size()
	if room <= 0:
		_body_cut = true
	elif chunk.size() > room:
		_body.append_array(chunk.slice(0, room))
		_body_cut = true
	else:
		_body.append_array(chunk)
	var split: Dictionary = split_lines(_pending, chunk)
	for line: String in Array(split["lines"]):
		_lines.append(line)
	_pending = split["pending"]


func _refuse(why: String) -> void:
	_why = why
	_verdict = REFUSED
	_status = 0


func _host() -> String:
	return String(_request.get("host", ""))


func _port() -> int:
	return int(_request.get("port", 0))