class_name SeasonWindow
extends Window
## How long the season is: the site's frost dates, and which food crops have time to finish in the
## window they bound.
##
## A `Window`, like the ground page and for the same reason: it holds number fields, and a window is
## the one boundary at which controls are allowed to hold the keyboard. Everything here is built through
## the shared chrome, which makes a control without a keyboard of its own - except the two number fields,
## which keep theirs, because a field is where somebody types. What the *open* page does with the
## keyboard is decided once, by `PageChrome.takes_the_keyboard`.
##
## ## Why it writes to the drawing
##
## Every other page in the food garden - what will crop, what to grow next, what is ready when -
## reads the drawing and writes nothing. This one is the exception, and it has to be: a frost date is
## the one input the drawing cannot supply, the way a casting height is the one input the sun study
## cannot supply. It is stated **once for the site** and kept with the drawing beside the latitude,
## because it is the same kind of fact, and every food question that needs a season then reads it.
##
## ## What it does not do
##
## It does not say when to sow: that needs a start date and a succession of them, and it belongs to
## the planner that asks it. This page measures the season and checks the crops against its length,
## so whatever asks about sowing has a season to sow into.

const GrowingSeasonScript := preload("res://scripts/growing_season.gd")

## The season changed on the drawing: the Site menu's line about it is stale.
signal season_changed()
## The page was closed by its own close button.
signal closed

## Big enough for the two fields, the list and the words underneath without anything falling off the
## bottom edge.
const SIZE := Vector2i(880, 640)

const EXPLANATION := ("A growing season is two dates: the last frost of spring and the first frost "
	+ "of autumn. State them here and they are kept with the drawing, and every food crop in the "
	+ "list is then measured against the season they bound - a crop that takes longer to ripen than "
	+ "the season lasts will not finish before the frost comes back.")

const NO_DOCUMENT := "there is no drawing open, so there is no season to state"
const NOT_STATED_HINT := ("the drawing does not state a growing season yet: set the frost dates and "
	+ "press State the season to keep them with the drawing")
const NO_FOOD := "no food crops are recorded in the plant list, so there is nothing to check against the season"
const BAD_DATES := "those dates are not a season: the last frost has to come before the first"

## The dates the fields start on when the drawing states none. A temperate garden's - the middle of
## May to the first week of October - offered as a starting point rather than as a claim: nothing is
## stated until the button is pressed, and the fields say what filling them comes to.
const DEFAULT_LAST_FROST := 140
const DEFAULT_FIRST_FROST := 280

## The drawing whose season this page states. Null means there is none, which the page reports rather
## than fails on.
var document: DraftDocument = null

var _catalogue: PlantCatalogue = null
var _built: bool = false
var _status: String = ""
var _rows_signature_seen: String = "<never written>"

var _season_line: Label = null
var _last_box: SpinBox = null
var _first_box: SpinBox = null
var _field_line: Label = null
var _state_button: Button = null
var _clear_button: Button = null
var _crops_label: Label = null
var _crops_list: ItemList = null
var _summary_label: Label = null
var _hint_label: Label = null
var _status_label: Label = null


# --- building -----------------------------------------------------------------------------


## Build the controls, once. Idempotent, and callable off-tree, so a test drives the same controls
## the program shows.
func build() -> void:
	if _built:
		return
	_built = true
	title = "How long the season is"
	# A window that has never been shown still defaults to visible, and a page that is up before
	# anybody asked for it is the one thing every page in this HUD has to avoid.
	hide()
	size = SIZE
	close_requested.connect(_on_close_requested)

	var column := PageChrome.column(self, 6, Vector2(16.0, 12.0))

	column.add_child(PageChrome.subheading("How long the season is"))
	column.add_child(PageChrome.note(EXPLANATION))

	_season_line = PageChrome.text()
	_season_line.name = "SeasonLine"
	column.add_child(_season_line)

	_last_box = _day_box("LastFrostBox", DEFAULT_LAST_FROST)
	column.add_child(_field_row("Last frost of spring", "LastFrostRow", _last_box))

	_first_box = _day_box("FirstFrostBox", DEFAULT_FIRST_FROST)
	column.add_child(_field_row("First frost of autumn", "FirstFrostRow", _first_box))

	_field_line = PageChrome.text()
	_field_line.name = "FieldLine"
	column.add_child(_field_line)

	var buttons := PageChrome.button_row()
	_state_button = _button(buttons, "StateButton", "State the season")
	_state_button.tooltip_text = "Keep these frost dates with the drawing, as one undoable step"
	_state_button.pressed.connect(_on_state_pressed)
	_clear_button = _button(buttons, "ClearButton", "Take it back")
	_clear_button.tooltip_text = "Unstate the season, so the drawing says nothing about the frosts"
	_clear_button.pressed.connect(_on_clear_pressed)
	var close_button := _button(buttons, "CloseButton", "Close")
	close_button.pressed.connect(request_close)
	column.add_child(buttons)

	_crops_label = PageChrome.text()
	_crops_label.name = "CropsLabel"
	column.add_child(_crops_label)
	_crops_list = ItemList.new()
	_crops_list.name = "Crops"
	_crops_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_crops_list.custom_minimum_size = Vector2(0.0, 200.0)
	# A list a person reads rather than types into, built without a keyboard of its own like the rest.
	_crops_list.focus_mode = Control.FOCUS_NONE
	_crops_list.select_mode = ItemList.SELECT_SINGLE
	column.add_child(_crops_list)

	_summary_label = PageChrome.text()
	_summary_label.name = "Summary"
	column.add_child(_summary_label)

	_hint_label = PageChrome.hint()
	column.add_child(_hint_label)

	_status_label = PageChrome.status()
	column.add_child(_status_label)

	# A page with nothing in it yet is still a page: it says what it is waiting for rather than
	# showing an empty table that reads as a season nothing grows in.
	refresh()


func _day_box(node_name: String, start: int) -> SpinBox:
	var box := SpinBox.new()
	box.name = node_name
	box.min_value = 1.0
	box.max_value = float(GrowingSeasonScript.MAX_DAY)
	box.step = 1.0
	box.value = clampi(start, 1, GrowingSeasonScript.MAX_DAY)
	box.custom_minimum_size = Vector2(96.0, 0.0)
	box.tooltip_text = "Day of the year. 140 is 20 May and 280 is 7 October."
	box.value_changed.connect(_on_field_changed)
	return box


## A caption and the field it names, in one row. Both rows give their caption the same width so the two
## number fields line up whichever words stand in front of them. The caption itself is the shared
## chrome's, which is why it is found by the name the chrome gives it rather than by the page naming it.
func _field_row(caption: String, row_name: String, box: SpinBox) -> HBoxContainer:
	var row := PageChrome.labelled(caption, box)
	row.name = row_name
	var words: Label = row.get_node(^"Caption")
	words.custom_minimum_size = Vector2(150.0, 0.0)
	return row


## A button in the page's own row, made by the shared chrome so that its caption and what it does with
## the keyboard are the project's rather than this page's. The node name is the page's, because its own
## tests read `StateButton` and `ClearButton`.
func _button(row: Node, node_name: String, caption: String) -> Button:
	var made := PageChrome.button(caption)
	made.name = node_name
	row.add_child(made)
	return made


# --- the drawing --------------------------------------------------------------------------


## Point the page at the drawing whose season it states.
func set_document(doc: DraftDocument) -> void:
	document = doc
	_sync_fields_from_document()
	refresh()


## Point the page at the plant list it checks against the season.
func set_catalogue(cat: PlantCatalogue) -> void:
	_catalogue = cat
	refresh()


## The stated season: the last frost of spring, or 0 when the drawing states none.
func last_frost() -> int:
	return document.season_last_frost if document != null else 0


## The stated season: the first frost of autumn, or 0 when the drawing states none.
func first_frost() -> int:
	return document.season_first_frost if document != null else 0


## Whether the drawing states a season at all.
func season_stated() -> bool:
	return document != null and GrowingSeasonScript.is_stated(last_frost(), first_frost())


## The stated season in words, or the reason there is none. Read off the drawing, never off the
## fields: the fields are what a person is *about* to state.
func season_line() -> String:
	if document == null:
		return NO_DOCUMENT
	return GrowingSeasonScript.season_text(last_frost(), first_frost())


# --- the fields ---------------------------------------------------------------------------


## The last frost the fields describe, whether or not it has been stated.
func field_last_frost() -> int:
	return int(_last_box.value) if _last_box != null else DEFAULT_LAST_FROST


func field_first_frost() -> int:
	return int(_first_box.value) if _first_box != null else DEFAULT_FIRST_FROST


## Put a pair of dates in the fields, the way a person editing them would.
func set_fields(last: int, first: int) -> void:
	if _last_box != null:
		_last_box.set_value_no_signal(clampi(last, 1, GrowingSeasonScript.MAX_DAY))
	if _first_box != null:
		_first_box.set_value_no_signal(clampi(first, 1, GrowingSeasonScript.MAX_DAY))
	_refresh_field_line()
	_refresh_buttons()
	_hint_label.text = hint()


# --- what the buttons do -------------------------------------------------------------------


## State the season the fields describe, and keep it with the drawing. One undo step, through the
## document, like every other act on the drawing.
##
## A pair the fields describe that is not a season - the first frost on or before the last - is
## **refused with its reason** rather than stored: the drawing would hold two dates that answer no
## question, and a page that stored them would be claiming a season where there is none.
func state_season() -> bool:
	if document == null:
		say(NO_DOCUMENT)
		return false
	var last: int = field_last_frost()
	var first: int = field_first_frost()
	if not GrowingSeasonScript.is_stated(last, first):
		say(BAD_DATES)
		return false
	if not document.set_season(last, first):
		say("the season is already stated as those dates")
		return false
	refresh()
	say(GrowingSeasonScript.season_text(last, first))
	season_changed.emit()
	return true


## Unstate the season, so the drawing says nothing about the frosts again. The way back to "not
## stated" has to exist, the same way it does for every other statement about the site.
func clear_season() -> bool:
	if document == null:
		say(NO_DOCUMENT)
		return false
	if not season_stated():
		say("there is no season stated to take back")
		return false
	document.set_season(0, 0)
	refresh()
	say("the growing season is not stated again")
	season_changed.emit()
	return true


# --- what the season comes to --------------------------------------------------------------


## The lines the crop list shows: one per food crop, best first, each carrying its verdict.
func row_texts() -> Array[String]:
	if _catalogue == null:
		return [] as Array[String]
	return GrowingSeasonScript.row_texts(_catalogue, last_frost(), first_frost())


func row_count() -> int:
	return row_texts().size()


## The season's crop list in one sentence, or what the list itself is missing.
func summary_text() -> String:
	if _catalogue == null:
		return "there is no plant list to check"
	return GrowingSeasonScript.describe_rows(
		GrowingSeasonScript.rows(_catalogue, last_frost(), first_frost())
	)


## The guidance: what the page is waiting for, or what it is doing. Kept apart from the status line,
## which is what the page last *did*, and from the season line above, so nothing is said twice.
func hint() -> String:
	if document == null:
		return NO_DOCUMENT
	if not season_stated():
		return NOT_STATED_HINT
	if _catalogue == null or row_count() == 0:
		return NO_FOOD
	return "each crop below is measured against this season: one that ripens later than the first frost will not finish"


# --- what the page says ----------------------------------------------------------------------


func say(text: String) -> void:
	_status = text
	if _status_label != null:
		_status_label.text = text


func said() -> String:
	return _status


func status_text() -> String:
	return _status


func state_enabled() -> bool:
	return _state_button != null and not _state_button.disabled


func clear_enabled() -> bool:
	return _clear_button != null and not _clear_button.disabled


## True when the page is *built* with nothing that takes a keyboard of its own except the two number
## fields, which keep theirs because a field is where somebody types. Whether the page holds the keyboard
## once it is open is the shared show's decision, and is measured live rather than here.
func lists_are_keyboard_free() -> bool:
	return _crops_list != null and _crops_list.focus_mode == Control.FOCUS_NONE


func request_close() -> void:
	hide()
	closed.emit()


func _on_close_requested() -> void:
	request_close()


# --- the refresh -------------------------------------------------------------------------


## Read the drawing again and put the season and the crop list on the page. Touches the guidance and
## never the status.
func refresh() -> void:
	if not _built:
		return
	_season_line.text = season_line()
	_refresh_field_line()
	_crops_label.text = "The food list, checked against the season \u2014 %d" % row_count()
	_write_rows()
	_summary_label.text = summary_text()
	# The buttons first, because the guidance is written from whether they are live - and a hint
	# computed from the previous refresh's button states is a hint that is one edit behind.
	_refresh_buttons()
	_hint_label.text = hint()


## Put the stated season in the fields, when there is one. A drawing that states none leaves the
## fields where they are: what a person is about to fill in is not thrown away by a refresh.
func _sync_fields_from_document() -> void:
	if _last_box == null or _first_box == null:
		return
	if season_stated():
		_last_box.set_value_no_signal(last_frost())
		_first_box.set_value_no_signal(first_frost())


func _refresh_field_line() -> void:
	if _field_line == null:
		return
	var last: int = field_last_frost()
	var first: int = field_first_frost()
	if not GrowingSeasonScript.is_stated(last, first):
		_field_line.text = ("These dates are not a season. " + BAD_DATES.capitalize() + ".")
		return
	# The line is only written when the fields say something the drawing does not: when they agree, the
	# season line above has already said it, and saying one thing twice is how a page stops being read.
	if season_stated() and last == last_frost() and first == first_frost():
		_field_line.text = ""
		return
	_field_line.text = "With these dates the season is about %d days, from %s to %s." % [
		GrowingSeasonScript.length_days(last, first),
		GrowingSeasonScript.day_words(last),
		GrowingSeasonScript.day_words(first),
	]


## Write the rows, once per season. Signature-guarded, so a page left open does not rebuild a
## hundred strings a frame.
func _write_rows() -> void:
	var texts: Array[String] = row_texts()
	var signature: String = "%d|%d|%s" % [
		last_frost(), first_frost(), "+".join(PackedStringArray(texts))
	]
	if signature == _rows_signature_seen:
		return
	_rows_signature_seen = signature
	_crops_list.clear()
	for text: String in texts:
		_crops_list.add_item(text)


func _refresh_buttons() -> void:
	if _state_button == null or _clear_button == null:
		return
	# The same question asked twice: the button is dead when the page cannot do it, and the hint above
	# says which fact is missing - which a disabled button cannot say for itself.
	_state_button.disabled = document == null or not GrowingSeasonScript.is_stated(
		field_last_frost(), field_first_frost()
	)
	_clear_button.disabled = not season_stated()


func _on_field_changed(_value: float) -> void:
	_refresh_field_line()
	_refresh_buttons()
	if _hint_label != null:
		_hint_label.text = hint()


func _on_state_pressed() -> void:
	state_season()


func _on_clear_pressed() -> void:
	clear_season()