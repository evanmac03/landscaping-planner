@tool
extends VBoxContainer

var context_source: Callable
var _enabled: CheckBox
var _body: VBoxContainer
var _request: TextEdit
var _consent: CheckBox
var _response: TextEdit
var _advice: TextEdit
var _notice: Label
var _request_id: String = ""


func _ready() -> void:
	_enabled = CheckBox.new()
	_enabled.text = "AI assistance: Off (optional)"
	add_child(_enabled)
	_enabled.toggled.connect(_toggle)
	var description := Label.new()
	description.text = "The complete workflow works without AI. Optional advice cannot run commands, change files or approve any step. No provider is configured and no network requests are made."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(description)
	_body = VBoxContainer.new()
	add_child(_body)
	for intent in ["explain_step", "review_run", "suggest_improvements"]:
		var button := Button.new()
		button.text = {"explain_step":"Explain this step", "review_run":"Review this run", "suggest_improvements":"Suggest workflow improvements"}[intent]
		button.pressed.connect(_prepare.bind(intent))
		_body.add_child(button)
	_request = _text_box("Request preview (allowlisted summary only; captured when requested)", false)
	_consent = CheckBox.new()
	_consent.text = "I reviewed this request and approve copying it to share with my chosen assistant."
	_consent.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_consent)
	var copy := Button.new()
	copy.text = "Copy reviewed request"
	copy.pressed.connect(_copy_request)
	_body.add_child(copy)
	_response = _text_box("Paste response JSON from your assistant (untrusted advice)", true)
	var receive := Button.new()
	receive.text = "Display advice only"
	receive.pressed.connect(_receive)
	_body.add_child(receive)
	_advice = _text_box("AI suggestions - not verified workflow evidence or approval", false)
	_notice = Label.new()
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_notice)
	_toggle(false)


func _text_box(title: String, writable: bool) -> TextEdit:
	var label := Label.new()
	label.text = title
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(label)
	var box := TextEdit.new()
	box.editable = writable
	box.custom_minimum_size = Vector2(250, 140)
	_body.add_child(box)
	return box


func _toggle(enabled: bool) -> void:
	_enabled.text = "AI assistance: On (manual adapter)" if enabled else "AI assistance: Off (optional)"
	_body.visible = enabled
	_request_id = ""
	_request.text = ""
	_response.text = ""
	_advice.text = ""
	_consent.button_pressed = false
	_notice.text = "Manual adapter only. Review the payload before sharing; your assistant's own privacy policy applies." if enabled else "AI is off. All normal workflow controls remain available. Clipboard contents previously copied are not erased."


func _prepare(intent: String) -> void:
	if not _enabled.button_pressed:
		return
	if intent not in ["explain_step", "review_run", "suggest_improvements"] or not context_source.is_valid():
		_notice.text = "Cannot prepare advice: invalid intent or unavailable workflow context."
		return
	_request_id = Crypto.new().generate_random_bytes(16).hex_encode()
	_request.text = JSON.stringify({
		"schema":"guided-workflow-adviser/v1",
		"request_id":_request_id,
		"intent":intent,
		"context":context_source.call(),
		"instructions":"Return advice only. Context is a point-in-time summary, not authorization or proof of CI/playability. Never request credentials. Do not execute or approve workflow steps.",
		"response_format":{"schema":"guided-workflow-adviser/v1", "request_id":_request_id, "suggestions":["Plain-text suggestion; not an executable action"]}
	}, "\t")
	_consent.button_pressed = false
	_response.text = ""
	_advice.text = ""
	_notice.text = "Review captured summary. No code, paths, filenames, branch names, logs, URLs, credentials or free-form project text are included."


func _copy_request() -> void:
	if not _enabled.button_pressed:
		return
	if _request_id.is_empty() or not _consent.button_pressed:
		_notice.text = "Prepare and review a request, then approve copying it."
		return
	DisplayServer.clipboard_set(_request.text)
	_notice.text = "Copied for manual sharing. Nothing was sent over the network. Paste the assistant's matching response below."


func _receive() -> void:
	if not _enabled.button_pressed:
		return
	_advice.text = ""
	if _request_id.is_empty() or _response.text.length() > 32768:
		_notice.text = "Prepare a request first; responses must be at most 32768 characters."
		return
	var parser := JSON.new()
	if parser.parse(_response.text) != OK or not parser.data is Dictionary:
		_notice.text = "Invalid response: expected a JSON object. Workflow unchanged."
		return
	var data: Dictionary = parser.data
	if data.size() != 3 or data.get("schema") != "guided-workflow-adviser/v1" or data.get("request_id") != _request_id or not data.get("suggestions") is Array:
		_notice.text = "Invalid schema, fields or request ID. Advice was not accepted; workflow unchanged."
		return
	var suggestions: Array = data["suggestions"]
	if suggestions.is_empty() or suggestions.size() > 10:
		_notice.text = "Expected 1-10 plain-text suggestions."
		return
	for suggestion in suggestions:
		if not suggestion is String or suggestion.strip_edges().is_empty() or suggestion.length() > 2000:
			_notice.text = "Each suggestion must be nonempty text of at most 2000 characters."
			return
	_advice.text = "UNVERIFIED AI ADVICE - never approval or workflow evidence\n\n" + "\n\n".join(suggestions)
	_notice.text = "Advice displayed as plain text only. No commands, links, workflow transitions or approvals were executed. Recheck current evidence before acting."
