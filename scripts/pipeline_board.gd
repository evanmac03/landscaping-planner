class_name PipelineBoard
extends Window
## The pipeline as a board: a column per stage, a card per lead, and a drop that asks why.
##
## The board is a `Window` like the estimate and the ground window, for the same two reasons: it has
## a field to type into, and a `Window` owns its own input, so nothing here can take the drawing's
## keys (spec §9's rule). It holds a `Pipeline` and shows what the pipeline's own words say - it does
## no arithmetic of its own, because the funnel and the win rate are the pipeline's, and a board that
## recomputed them would be a second answer to the same question.
##
## ## A drop into LOST asks the reason
##
## The one interaction with weight on it. A lead cannot be closed as lost without a loss reason
## (§4.7), and the reason is the whole win/loss report, so the drop is *held*: `move_lead` refuses,
## the board remembers which card was dropped where, and shows a field for the reason. Confirming
## finishes the move; cancelling puts the card back by never having moved it.

const PipelineScript := preload("res://scripts/biz/pipeline.gd")
const LeadScript := preload("res://scripts/biz/lead.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")

## A card was moved, a lead was added, or a drop is being asked about. The HUD's menu line is stale.
signal pipeline_changed()
## The window was closed by its own close button.
signal closed()

## Wide enough for nine columns of cards, and no taller than the screen.
const SIZE := Vector2i(1120, 700)
const COLUMN_WIDTH := 172
## The height one card needs to show a name and a value without clipping either.
const CARD_HEIGHT := 46
## How many cards a column scrolls before the rest are out of sight. A column is a viewport, not a
## report: the funnel above counts every lead, whatever the column is showing.
const COLUMN_CARDS := 8

## The columns, in the order a lead moves through them, with the three terminal states on the right.
const BOARD_STAGES: Array[int] = [
	LeadScript.LEAD, LeadScript.QUALIFIED, LeadScript.VISIT, LeadScript.ESTIMATING,
	LeadScript.PROPOSED, LeadScript.WON, LeadScript.LOST, LeadScript.WITHDRAWN, LeadScript.DORMANT,
]

var pipeline: PipelineScript = null
var currency: StringName = &"CAD"

var _row: HBoxContainer = null
var _funnel: Label = null
var _status: Label = null
var _reason_row: HBoxContainer = null
var _reason: LineEdit = null
var _reason_label: Label = null
## The card a drop is being asked about, and where it was dropped. Empty when nothing is pending.
var _pending_id: String = ""
var _pending_stage: int = -1
## A monotonic serial, so two leads added in the same second still have different ids.
var _serial: int = 0


func _init() -> void:
	title = "The pipeline"
	min_size = SIZE
	exclusive = false
	close_requested.connect(_on_close_requested)


func _ready() -> void:
	if _row == null:
		build()


# --- building ------------------------------------------------------------------------------


## Build the whole window by hand. Idempotent, and callable off-tree so a test can drive the same
## controls the program shows.
func build() -> void:
	if _row != null:
		return
	if pipeline == null:
		pipeline = PipelineScript.new()
		pipeline.currency = currency
	var column := PageChrome.column(self, 8)

	_funnel = PageChrome.text()
	_funnel.name = "Funnel"
	column.add_child(_funnel)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)

	_row = HBoxContainer.new()
	_row.name = "Board"
	_row.add_theme_constant_override("separation", 6)
	scroll.add_child(_row)
	for stage_value in BOARD_STAGES:
		var stage_int := int(stage_value)
		var box := Column.new()
		box.name = "Column%d" % stage_int
		box.stage = stage_int
		box.board = self
		box.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
		box.add_theme_constant_override("separation", 4)
		_row.add_child(box)

	_reason_row = HBoxContainer.new()
	_reason_row.name = "ReasonRow"
	_reason_row.add_theme_constant_override("separation", 6)
	_reason_row.visible = false
	column.add_child(_reason_row)
	_reason_label = PageChrome.text()
	_reason_label.name = "ReasonLabel"
	_reason_row.add_child(_reason_label)
	_reason = LineEdit.new()
	_reason.name = "Reason"
	_reason.placeholder_text = "why it was lost"
	_reason.custom_minimum_size = Vector2(300, 0)
	_reason_row.add_child(_reason)
	var confirm := _button("Close as lost", "_on_confirm_lost")
	confirm.name = "ConfirmLost"
	_reason_row.add_child(confirm)
	var cancel := _button("Keep it open", "_on_cancel_lost")
	cancel.name = "CancelLost"
	_reason_row.add_child(cancel)

	var add_row := HBoxContainer.new()
	add_row.name = "AddRow"
	add_row.add_theme_constant_override("separation", 6)
	column.add_child(add_row)
	var name_field := LineEdit.new()
	name_field.name = "NewName"
	name_field.placeholder_text = "a new lead's name"
	name_field.custom_minimum_size = Vector2(220, 0)
	add_row.add_child(name_field)
	var value_field := LineEdit.new()
	value_field.name = "NewValue"
	value_field.placeholder_text = "what it is worth"
	value_field.custom_minimum_size = Vector2(140, 0)
	add_row.add_child(value_field)
	var add_button := _button("Add the lead", "_on_add_lead")
	add_button.name = "AddLead"
	add_row.add_child(add_button)

	_status = PageChrome.status()
	column.add_child(_status)
	refresh()


## A button on this board, from the shared chrome and named by the board's own rule: a caption with its
## spaces taken out. The board's typed fields are the only controls it builds with a keyboard, because a
## field is where somebody types; what the *open* board does with the keyboard is decided once, by
## `PageChrome.takes_the_keyboard`.
func _button(words: String, method: String) -> Button:
	var button := PageChrome.button(words)
	button.name = words.replace(" ", "")
	button.pressed.connect(Callable(self, method))
	return button


# --- showing what is there ---------------------------------------------------------------------


## Point the board at a pipeline and read it again. A null pipeline becomes an empty one rather than
## a board with nothing to show.
func bind(lead_pipeline: PipelineScript) -> void:
	if _row == null:
		build()
	pipeline = lead_pipeline if lead_pipeline != null else PipelineScript.new()
	pipeline.currency = currency
	_refresh_columns()
	refresh()


func refresh() -> void:
	_refresh_columns()
	if _funnel != null:
		_funnel.text = _funnel_words()
	if _status != null:
		_status.text = summary_text()
	if _reason_row != null:
		_reason_row.visible = _pending_stage == LeadScript.LOST
		if is_asking_for_a_reason():
			_reason_label.text = "%s is being closed as lost. Why?" % _name_of(_pending_id)
	# The cards just built are new controls, and the shared show that gave this board its keyboard ran
	# when it was *opened* - before any of them existed. So a board that is up gives them the keyboard
	# here. Nothing is done while it is down: the show is what decides it then, and it decides it once.
	PageChrome.takes_the_keyboard_if_up(self)


## Rebuild every column's cards from the pipeline. Cheap at this size - a column is a handful of
## buttons - and it means the board can never show a card the pipeline does not have.
func _refresh_columns() -> void:
	if _row == null:
		return
	for stage_value in BOARD_STAGES:
		var stage_int := int(stage_value)
		var box := _row.get_node_or_null(NodePath("Column%d" % stage_int))
		if box == null:
			continue
		for child in box.get_children():
			# Freed now, not queue_free'd: a deferred free leaves the old card in the tree, and a
			# test that looked the card up by name would find the stale one with the same name.
			box.remove_child(child)
			child.free()
		var header := Label.new()
		header.name = "Header"
		header.text = "%s (%d)" % [LeadScript.stage_name(stage_int), _stage_count(stage_int)]
		box.add_child(header)
		var shown := 0
		for lead in _stage_leads(stage_int):
			if shown >= COLUMN_CARDS:
				var more := Label.new()
				more.name = "More"
				more.text = "+%d more" % (_stage_count(stage_int) - shown)
				box.add_child(more)
				break
			box.add_child(_card(lead))
			shown += 1


func _card(lead: LeadScript) -> Card:
	var card := Card.new()
	card.name = "Card" + lead.id
	card.lead_id = lead.id
	card.board = self
	card.text = "%s\n%s" % [lead.name, lead.value().format()]
	card.custom_minimum_size = Vector2(COLUMN_WIDTH - 12, CARD_HEIGHT)
	card.focus_mode = Control.FOCUS_NONE
	card.pressed.connect(_on_card_pressed.bind(lead.id))
	return card


# --- moving a lead -------------------------------------------------------------------------


## Move a lead to a stage. This is what a drop calls.
##
## A move into LOST with no reason is **held, not made**: the refusal is returned and the board
## remembers the drop so the reason row can finish it. Everything else goes straight through.
##
## Returns the move's own `{ok, reason, ...}`.
func move_lead(lead_id: String, to_stage: int) -> Dictionary:
	if pipeline == null:
		return {"ok": false, "reason": "the board has no pipeline", "event": {}}
	var lead: LeadScript = pipeline.find(lead_id)
	if lead == null:
		return {"ok": false, "reason": "that lead is not on the board", "event": {}}
	if to_stage == LeadScript.LOST and lead.lost_reason == &"":
		_pending_id = lead_id
		_pending_stage = to_stage
		refresh()
		return {"ok": false, "reason": "a lead closed as lost says why, and this one has no lost reason",
			"event": {}}
	var result := lead.move_to(to_stage, _now(), "office")
	if result["ok"]:
		_clear_pending()
		refresh()
		pipeline_changed.emit()
	return result


## The reason a held drop was waiting for. Sets it and finishes the move it was holding.
func confirm_move(reason: String) -> Dictionary:
	if not is_asking_for_a_reason():
		return {"ok": false, "reason": "nothing is being closed as lost", "event": {}}
	var lead: LeadScript = pipeline.find(_pending_id)
	if lead == null:
		_clear_pending()
		refresh()
		return {"ok": false, "reason": "that lead is not on the board", "event": {}}
	lead.set_lost_reason(StringName(reason.strip_edges()))
	var target := _pending_stage
	_clear_pending()
	var result := move_lead(lead.id, target)
	return result


## Put a held drop back, by never having moved it.
func cancel_move() -> void:
	_clear_pending()
	refresh()


## The card a drop is asking about, or empty.
func pending_lead() -> String:
	return _pending_id


## The stage a drop was going to, or -1.
func pending_stage() -> int:
	return _pending_stage


func is_asking_for_a_reason() -> bool:
	return not _pending_id.is_empty() and _pending_stage == LeadScript.LOST


## Add a lead, opened now at the first stage. The value is read the way a person types money; a value
## that cannot be read is refused rather than stored as nothing.
##
## Returns `{ok, reason, id}`.
func add_lead(lead_name: String, cents: int, source: StringName = &"other", expected_at: String = "") -> Dictionary:
	if _row == null:
		build()
	var clean := lead_name.strip_edges()
	if clean.is_empty():
		return {"ok": false, "reason": "a lead needs a name", "id": ""}
	var lead := LeadScript.new(_new_id(), clean)
	lead.value_estimate = MoneyScript.of(cents, currency)
	lead.source = source if LeadScript.SOURCES.has(source) else &"other"
	lead.expected_close_at = expected_at
	lead.opened_at = _now()
	lead.open(lead.opened_at, "office")
	if pipeline == null:
		pipeline = PipelineScript.new()
		pipeline.currency = currency
	pipeline.add(lead)
	refresh()
	pipeline_changed.emit()
	return {"ok": true, "reason": "", "id": lead.id}


# --- what the board says -------------------------------------------------------------------


## The stage names, one per column, in board order. What a test reads instead of pixels.
func column_titles() -> Array[String]:
	var out: Array[String] = []
	for stage_value in BOARD_STAGES:
		out.append(LeadScript.stage_name(int(stage_value)))
	return out


## The cards in one column, each as "name\nvalue", in pipeline order.
func card_texts(stage: int) -> Array[String]:
	var out: Array[String] = []
	for lead in _stage_leads(stage):
		out.append("%s\n%s" % [lead.name, lead.value().format()])
	return out


func card_count(stage: int) -> int:
	return _stage_count(stage)


## The lead ids in one column, in pipeline order.
func card_ids(stage: int) -> Array[String]:
	var out: Array[String] = []
	for lead in _stage_leads(stage):
		out.append(lead.id)
	return out


## The funnel as lines, straight from the pipeline: "Lead 3 - 10,000.00". The board shows the count
## and the value; the arithmetic is the pipeline's.
func funnel_texts() -> Array[String]:
	var out: Array[String] = []
	if pipeline == null:
		return out
	for row in pipeline.funnel():
		out.append("%s %d - %s" % [
			String(row["name"]), int(row["count"]),
			MoneyScript.of(int(row["value_cents"]), currency).format(),
		])
	return out


## One line: what the open pipeline is worth, raw and weighted, and how many leads are on it.
func summary_text() -> String:
	if pipeline == null:
		return "no pipeline"
	var value := pipeline.pipeline_value()
	if int(value["count"]) == 0:
		return "no open leads"
	return "open: %d leads worth %s, weighted %s" % [
		int(value["count"]),
		MoneyScript.of(int(value["raw_cents"]), currency).format(),
		MoneyScript.of(int(value["weighted_cents"]), currency).format(),
	]


func status_text() -> String:
	return _status.text if _status != null else ""


func reason_text() -> String:
	return _reason.text if _reason != null else ""


func set_reason(words: String) -> void:
	if _reason != null:
		_reason.text = words


func is_reason_row_visible() -> bool:
	return _reason_row != null and _reason_row.visible


## The controls that are *built* without a keyboard: every button on the board. The typed fields are the
## only things here allowed focus at build time, so this returns the buttons and nothing else - and what a
## board that is *shown* does with the keyboard is decided once, in `PageChrome.takes_the_keyboard`.
func buttons_are_focus_free() -> bool:
	if _row == null:
		return false
	for button in _all_buttons(self):
		if button.focus_mode != Control.FOCUS_NONE:
			return false
	return true


func _all_buttons(node: Node) -> Array[Button]:
	var out: Array[Button] = []
	for child in node.get_children():
		if child is Button:
			out.append(child)
		out.append_array(_all_buttons(child))
	return out


func _name_of(lead_id: String) -> String:
	if pipeline == null:
		return lead_id
	var lead: LeadScript = pipeline.find(lead_id)
	return lead.name if lead != null else lead_id


# --- the small arithmetic the board needs --------------------------------------------------


func _stage_leads(stage: int) -> Array[LeadScript]:
	var out: Array[LeadScript] = []
	if pipeline == null:
		return out
	for lead in pipeline.leads:
		if lead.stage == stage:
			out.append(lead)
	return out


func _stage_count(stage: int) -> int:
	return _stage_leads(stage).size()


func _funnel_words() -> String:
	var parts := funnel_texts()
	return "   ".join(parts) if not parts.is_empty() else "the funnel is empty"


func _clear_pending() -> void:
	_pending_id = ""
	_pending_stage = -1


func _new_id() -> String:
	_serial += 1
	return "lead-%d-%d" % [int(Time.get_unix_time_from_system()), _serial]


## Now, as the ISO-8601 UTC string the pipeline compares as text.
func _now() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"


# --- the buttons ----------------------------------------------------------------------------


func _on_card_pressed(lead_id: String) -> void:
	if _status != null:
		var lead: LeadScript = pipeline.find(lead_id) if pipeline != null else null
		if lead != null:
			_status.text = "%s: %s, %s" % [
				LeadScript.stage_name(lead.stage), lead.name, lead.value().format(),
			]


func _on_confirm_lost() -> void:
	if _reason == null:
		return
	confirm_move(_reason.text)
	_reason.text = ""


func _on_cancel_lost() -> void:
	cancel_move()


func _on_add_lead() -> void:
	var name_field := get_node_or_null(^"Column/AddRow/NewName") as LineEdit
	var value_field := get_node_or_null(^"Column/AddRow/NewValue") as LineEdit
	if name_field == null:
		return
	var parsed := MoneyScript.parse(value_field.text if value_field != null else "", currency)
	var cents := parsed.cents if parsed.is_valid() else 0
	var result := add_lead(name_field.text, cents)
	if result["ok"]:
		name_field.text = ""
		if value_field != null:
			value_field.text = ""
	elif _status != null:
		_status.text = "a lead needs a name"


func _on_close_requested() -> void:
	hide()
	closed.emit()


# --- dragging a card between columns ---------------------------------------------------------


## A card: a button you can drag, carrying the lead's id.
class Card extends Button:
	var lead_id: String = ""
	var board: PipelineBoard = null

	func _get_drag_data(_at: Vector2) -> Variant:
		if board == null or lead_id.is_empty():
			return null
		# A drag preview is attached to the viewport, so it needs a tree; off-tree (a test) the
		# payload is still returned, which is the part the drop reads.
		if is_inside_tree():
			var preview := Label.new()
			preview.text = text
			set_drag_preview(preview)
		return {"lead": lead_id}


## A column: a drop target that knows which stage it is.
class Column extends VBoxContainer:
	var stage: int = -1
	var board: PipelineBoard = null

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		if board == null or not (data is Dictionary):
			return false
		return (data as Dictionary).has("lead")

	func _drop_data(_at: Vector2, data: Variant) -> void:
		if board == null or not (data is Dictionary):
			return
		board.move_lead(String((data as Dictionary).get("lead", "")), stage)