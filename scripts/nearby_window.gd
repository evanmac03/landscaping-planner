class_name NearbyWindow
extends Window
## What the drawing puts around where a person stands: the page somebody opens on site with the plan in hand.
##
## **It is deliberately small, and that is the design rather than a smaller size.** The plan behind it *is* the
## drawing in hand - the whole point of the step - so the page keeps to one corner of the screen and leaves the
## board visible and usable around it. A person points at where they are standing on the plan, or taps it, and the
## list under the heading changes as they move: this is the one page in the program that is *meant* to be read with
## the drawing still in front of it.
##
## ## What it owns, and what it is handed
##
## It owns nothing. The place is handed over in plan metres and the things are handed over as `{name, at}`
## dictionaries, which is `NearbyWork.planted_things`'s own shape and `NearbyWork.around`'s own input - so a test
## drives the whole page with no drawing, no yard and no screen, and the page's words are the module's words rather
## than a second way of saying the same thing.
##
## ## It says what is missing
##
## Nothing planted, no drawing at all, plants the catalogue cannot name: each of those is a sentence rather than an
## empty list. A page that showed nothing would leave a person unable to tell "nothing goes here" from "the program
## could not read the drawing".

signal closed()

const NearbyWorkScript := preload("res://scripts/plants/nearby_work.gd")

## Wide enough for a row's sentence and tall enough for a handful, and **no wider**: the board is the other half of
## this page.
const SIZE := Vector2i(560, 620)

const EXPLANATION := (
	"The plan behind this page is the drawing in your hand. Point at where you are standing on it - or tap it - "
	+ "and this lists the things nearest that spot, closest first, with how far they are and which way to look."
)
const NO_DRAWING := "there is no drawing open, so there is nowhere to stand."
const AT_THE_SPOT := "standing at the spot the plan was last pointed at"

## The place the page last showed, in plan metres. Infinity until it is given one, which is a value no plan point
## can hold - the same device `Hud._bar_offsets_as_drawn` uses for "not stated yet".
const NOWHERE := Vector2(INF, INF)
## **How far the place must move before the rows are written again.** A person's hand resting on a mouse is not
## standing somewhere else, and a page that rewrote its list every frame the pointer jittered would flicker at a
## reader. A tenth of a metre is under a hand's width on the glass at any zoom a person works at.
const STILL_ENOUGH := 0.1

var _place: Vector2 = NOWHERE
var _planting: Array = []
var _last_seen: String = "<never written>"
var _said: String = ""

var _place_label: Label = null
var _rows: ItemList = null
var _summary: Label = null
var _hint: Label = null
var _status: Label = null


func _init() -> void:
	title = "What is around me"
	min_size = SIZE
	exclusive = false
	close_requested.connect(_on_close_requested)


func _ready() -> void:
	if _rows == null:
		build()

# --- building -----------------------------------------------------------------------


## Build the whole page by hand, idempotent, and callable off-tree so a test can drive the same controls the
## program shows.
func build() -> void:
	if _rows != null:
		return
	var column := PageChrome.column(self)

	column.add_child(PageChrome.heading("What is around me"))

	var explanation := PageChrome.note(EXPLANATION)
	explanation.name = "Explanation"
	column.add_child(explanation)

	_place_label = PageChrome.text()
	_place_label.name = "Place"
	column.add_child(_place_label)

	var rows := ItemList.new()
	rows.name = "Rows"
	# Sentences to read, not a list to drive: single selection so nothing is highlighted as a choice, and no
	# keyboard of its own, like every control on a page.
	rows.select_mode = ItemList.SELECT_SINGLE
	rows.focus_mode = Control.FOCUS_NONE
	rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(rows)
	_rows = rows

	_summary = PageChrome.text()
	_summary.name = "Summary"
	column.add_child(_summary)

	_hint = PageChrome.hint()
	column.add_child(_hint)

	var buttons := PageChrome.button_row()
	column.add_child(buttons)
	var close_button := PageChrome.button("Close")
	close_button.pressed.connect(_on_close_pressed)
	buttons.add_child(close_button)

	# No height is reserved for the status line: a page that reserves room whether or not it has anything to say
	# is a page asking for space it is not using.
	_status = PageChrome.status()
	column.add_child(_status)


func _on_close_pressed() -> void:
	request_close()


func _on_close_requested() -> void:
	request_close()


## Put the page away and say so once, however it was asked for - the window's own close button, the Close button,
## or Escape (which `PageEscape` turns into `close_requested`).
func request_close() -> void:
	hide()
	closed.emit()

# --- what it shows ------------------------------------------------------------------


## Where the person is standing, and what the drawing holds, both handed over by the HUD.
##
## The place is a point in plan metres - the drawing's own `cursor_point`, so it is the spot the pointer was over
## on its way to the menu rather than the menu it arrived at, which is the same reading `ground_at_cursor` makes.
## A drawing with nothing planted is still a place, and the page says what is missing rather than showing nothing.
func stand_at(point: Vector2, things: Array) -> void:
	build()
	_place = point
	_planting = things
	# **Deliberately no reset of what was last written.** The HUD hands the place over on every frame while this page
	# is up, so a reset here would rewrite the rows sixty times a second however still the person's hand was. The
	# signature decides, and only it: a place a hand's width away from the last one is the same place.
	show_around()


## Write the rows, if the place has moved or the planting has changed. Returns whether they were rewritten, so the
## page can be asked on a tick without re-listing a list that has not moved.
func show_around() -> bool:
	build()
	var signature := _signature()
	if signature == _last_seen:
		_refresh_hint()
		return false
	_last_seen = signature
	_rows.clear()
	var found: Dictionary = NearbyWorkScript.around(_planting, _place)
	for row: Dictionary in found["rows"]:
		_rows.add_item(String(row["sentence"]))
	if _rows.item_count > 0:
		# The nearest one is the one a person acts on, called out the way the status page calls out the answer the
		# plan is showing now.
		_rows.set_item_custom_fg_color(0, Color(1.0, 0.96, 0.8))
	_summary.text = String(found["text"])
	_place_label.text = place_words(found)
	_refresh_hint()
	return true


## The place, in the one line above the list. It names the nearest thing as the landmark the person is standing
## beside, because "3.4 m from the origin" tells somebody in a garden nothing at all.
func place_words(found: Dictionary) -> String:
	if _place == NOWHERE:
		return NO_DRAWING
	var nearest: Dictionary = found.get("nearest", { }) as Dictionary
	if nearest.is_empty():
		return AT_THE_SPOT
	return "%s - nearest is %s" % [AT_THE_SPOT, String(nearest["name"])]


## **A signature that rounds the place to a tenth of a metre**, for the reason `STILL_ENOUGH` gives: a resting hand
## must not rewrite the list sixty times a second, and a hand's width is not a move worth re-reading for.
func _signature() -> String:
	if _place == NOWHERE:
		return "nowhere"
	var rounded := Vector2(round(_place.x / STILL_ENOUGH) * STILL_ENOUGH, round(_place.y / STILL_ENOUGH) * STILL_ENOUGH)
	return "%s|%d" % [str(rounded), _planting.size()]


func _refresh_hint() -> void:
	_hint.text = hint()


func place() -> Vector2:
	return _place


func planting() -> Array:
	return _planting


func row_count() -> int:
	return _rows.item_count if _rows != null else 0


## One sentence per row, nearest first, exactly as `NearbyWork` worded them.
func row_texts() -> Array[String]:
	var out: Array[String] = []
	if _rows != null:
		for index in _rows.item_count:
			out.append(_rows.get_item_text(index))
	return out


## The nearest row's sentence, which is the one a person reads first.
func nearest_text() -> String:
	if _rows == null or _rows.item_count == 0:
		return ""
	return _rows.get_item_text(0)


func summary_text() -> String:
	return _summary.text if _summary != null else ""


func place_text() -> String:
	return _place_label.text if _place_label != null else ""


func hint() -> String:
	if _place == NOWHERE:
		return NO_DRAWING
	return "point at the plan behind this page - or tap it - to stand somewhere else."


## The guidance the page gives when it is opened, which is not the same claim as what it last showed.
func opening_words() -> String:
	if _place == NOWHERE:
		return NO_DRAWING
	if row_count() == 0:
		return NearbyWorkScript.NOTHING_PLANTED
	return "nearest first: %s" % nearest_text()

# --- what it says about itself -------------------------------------------------------


func say(words: String) -> void:
	build()
	_said = words
	if _status != null:
		_status.text = words


func said() -> String:
	return _said


func status_text() -> String:
	return _status.text if _status != null else ""


## The rows are built without a keyboard of their own, like every control on a page: they are sentences to read
## rather than a list to drive. What the *open* page does with the keyboard is decided once, by
## `PageChrome.takes_the_keyboard`, and not here.
func rows_are_keyboard_free() -> bool:
	build()
	return _rows.focus_mode == Control.FOCUS_NONE
