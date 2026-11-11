class_name YieldWindow
extends Window
## How much to plant: how many plants it takes to feed a household through a season.
##
## `PlantYield` is the arithmetic - how much a person eats, over how much a plant gives, plus a spare.
## This is the screen: the number of people, the spare, and the plants it comes to for every food crop
## in the list.
##
## A `Window`, like the season page and for the same reason: it holds number fields, and a window is the
## one boundary at which controls are allowed to hold the keyboard. Everything else in this HUD is built
## focus-free, and the spin boxes here are the one kind of control that may take a key.
##
## ## What it reads
##
## It reads the plant list and nothing else - no drawing, like the harvest calendar and for the same
## reason: how much a plant gives is a fact about the plant, and how many people are eating is a fact
## about a household, and neither was ever told to a drawing. So it needs no `document` and holds no
## state but the two numbers a person is choosing.
##
## ## Why it has no verdicts
##
## It gives a **count**, and a count is not a judgement - the reason the harvest calendar keeps no
## verdict vocabulary either. A crop that cannot be worked out is **reported apart**, naming which of the
## two facts is missing, rather than called good or wrong.

const YieldScript := preload("res://scripts/plant_yield.gd")

## The page was closed by its own close button.
signal closed

## The household's count is to be turned into a nursery order. It carries the rows `PlantYield.order_rows`
## writes - the shape the ordering side already prices - so the page never learns what an order is.
signal order_requested(rows: Array)

## Big enough for the two fields, the list and the sentence underneath without anything falling off the
## bottom edge: measured, they want 696 px, so 700.
const SIZE := Vector2i(920, 700)

const EXPLANATION := ("Work out how much to plant from how many you are feeding. A crop that records "
	+ "both how much one plant gives in a season and how much of it one person eats can be turned into "
	+ "a number of plants; a spare is added on top, because no garden brings every plant in whole. A "
	+ "crop the list says nothing about is counted apart rather than given a number nobody stated.")

const NO_CROPS := "this plant list has no food in it yet"
const NO_FACTS := ("none of these crops records both how much one plant gives and how much a person "
	+ "eats, so there is no number to work out")
const ANSWER_HINT := ("set how many you are feeding and how much spare to allow; every crop below is "
	+ "then worked out into a number of plants, and the button turns them into a nursery order")
const ORDER_BUTTON := "Order these plants..."
const NO_ORDER := "nothing on this list can be worked out into a count, so there is no order to write"

var catalogue: PlantCatalogue = null

var _built: bool = false
var _status: String = ""

var _heading: Label = null
var _explanation: Label = null
var _people_box: SpinBox = null
var _spare_box: SpinBox = null
var _list_label: Label = null
var _crops_list: ItemList = null
var _feed_line: Label = null
var _summary_label: Label = null
var _hint_label: Label = null
var _close_button: Button = null
var _order_button: Button = null
var _status_label: Label = null


# --- building -----------------------------------------------------------------------------


## Build the controls, once. Idempotent, and callable off-tree, so a test drives the same controls the
## program shows.
func build() -> void:
	if _built:
		return
	_built = true
	title = "How much to plant"
	# A window that has never been shown still defaults to visible, and a page that is up before anybody
	# asked for it is the one thing every page in this HUD has to avoid.
	hide()
	size = SIZE
	close_requested.connect(_on_close_requested)

	var column := PageChrome.column(self, 6, Vector2(16.0, 12.0))

	_heading = Label.new()
	_heading.name = "Heading"
	_heading.text = "How much to plant"
	column.add_child(_heading)

	_explanation = Label.new()
	_explanation.name = "Explanation"
	_explanation.text = EXPLANATION
	_explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_explanation)

	var people_row := HBoxContainer.new()
	people_row.name = "PeopleRow"
	var people_caption := Label.new()
	people_caption.name = "PeopleCaption"
	people_caption.text = "Feeding"
	people_caption.custom_minimum_size = Vector2(120.0, 0.0)
	people_row.add_child(people_caption)
	_people_box = _number_box("PeopleBox", YieldScript.DEFAULT_PEOPLE, YieldScript.MIN_PEOPLE,
		YieldScript.MAX_PEOPLE, "How many people the garden is feeding.")
	people_row.add_child(_people_box)
	var people_units := Label.new()
	people_units.name = "PeopleUnits"
	people_units.text = "people"
	people_row.add_child(people_units)
	column.add_child(people_row)

	var spare_row := HBoxContainer.new()
	spare_row.name = "SpareRow"
	var spare_caption := Label.new()
	spare_caption.name = "SpareCaption"
	spare_caption.text = "More for losses"
	spare_caption.custom_minimum_size = Vector2(120.0, 0.0)
	spare_row.add_child(spare_caption)
	_spare_box = _number_box("SpareBox", YieldScript.DEFAULT_SPARE, YieldScript.MIN_SPARE,
		YieldScript.MAX_SPARE, "A percentage more than the bare number, for the plants that do not come in.")
	spare_row.add_child(_spare_box)
	var spare_units := Label.new()
	spare_units.name = "SpareUnits"
	spare_units.text = "%"
	spare_row.add_child(spare_units)
	column.add_child(spare_row)

	_list_label = Label.new()
	_list_label.name = "ListLabel"
	column.add_child(_list_label)
	_crops_list = ItemList.new()
	_crops_list.name = "Crops"
	_crops_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_crops_list.custom_minimum_size = Vector2(0.0, 280.0)
	# A list a person reads is not a list a person types into: the keyboard belongs to the fields.
	_crops_list.focus_mode = Control.FOCUS_NONE
	_crops_list.select_mode = ItemList.SELECT_SINGLE
	column.add_child(_crops_list)

	_feed_line = Label.new()
	_feed_line.name = "FeedLine"
	_feed_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_feed_line)

	_summary_label = Label.new()
	_summary_label.name = "Summary"
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_summary_label)

	_hint_label = Label.new()
	_hint_label.name = "Hint"
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_hint_label)

	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	# The hand-off: the count this page works out, turned into a nursery order. It is dead while nothing on
	# the list can be worked out, because a count nobody stated must not become a line on an order.
	_order_button = Button.new()
	_order_button.name = "OrderButton"
	_order_button.text = ORDER_BUTTON
	_order_button.focus_mode = Control.FOCUS_NONE
	_order_button.pressed.connect(_on_order)
	buttons.add_child(_order_button)
	_close_button = Button.new()
	_close_button.name = "CloseButton"
	_close_button.text = "Close"
	# The HUD's own rule: a control in the HUD never takes the keyboard from the drawing.
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.pressed.connect(request_close)
	buttons.add_child(_close_button)
	column.add_child(buttons)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status_label)

	_refresh()


func _number_box(node_name: String, start: int, low: int, high: int, tip: String) -> SpinBox:
	var box := SpinBox.new()
	box.name = node_name
	box.min_value = float(low)
	box.max_value = float(high)
	box.step = 1.0
	box.value = clampi(start, low, high)
	box.custom_minimum_size = Vector2(96.0, 0.0)
	box.tooltip_text = tip
	box.value_changed.connect(_on_field_changed)
	return box


# --- binding ------------------------------------------------------------------------------


## Point the page at the plant list it works from. Absent is a state the page reports rather than fails
## on.
func bind(new_catalogue: PlantCatalogue) -> void:
	build()
	catalogue = new_catalogue
	_refresh()


func set_catalogue(new_catalogue: PlantCatalogue) -> void:
	catalogue = new_catalogue
	_refresh()


# --- the two numbers -----------------------------------------------------------------------


## How many people the garden is feeding.
func people() -> int:
	return int(_people_box.value) if _people_box != null else YieldScript.DEFAULT_PEOPLE


func set_people(count: int) -> void:
	if _people_box != null:
		_people_box.set_value_no_signal(
			clampi(count, YieldScript.MIN_PEOPLE, YieldScript.MAX_PEOPLE)
		)
	_refresh()


## The spare added on top, as a percentage.
func spare() -> int:
	return int(_spare_box.value) if _spare_box != null else YieldScript.DEFAULT_SPARE


func set_spare(percent: int) -> void:
	if _spare_box != null:
		_spare_box.set_value_no_signal(
			clampi(percent, YieldScript.MIN_SPARE, YieldScript.MAX_SPARE)
		)
	_refresh()


# --- the hand-off to a nursery order -------------------------------------------------------


## The rows the household's count would order: one per crop that worked out, in the shape the nursery
## order prices. A crop that could not be worked out has no row at all - a count nobody stated must never
## become a line on an order.
func order_rows() -> Array[Dictionary]:
	if catalogue == null:
		return [] as Array[Dictionary]
	return YieldScript.order_rows(YieldScript.plan(catalogue, people(), spare()), catalogue)


## Whether pressing the order button would hand anything over. False while nothing on the list can be
## worked out into a count.
func order_enabled() -> bool:
	return not order_rows().is_empty()


func order_words() -> String:
	return "" if _order_button == null else _order_button.text


func _on_order() -> void:
	if not order_enabled():
		say(NO_ORDER)
		return
	order_requested.emit(order_rows())


# --- what the plan comes to ----------------------------------------------------------------


## The lines the crop list shows: one per food crop, the plants it takes or the fact that is missing.
func row_texts() -> Array[String]:
	if catalogue == null:
		return [] as Array[String]
	return YieldScript.row_texts(catalogue, people(), spare())


func row_count() -> int:
	return row_texts().size()


## The whole plan in one sentence: how many plants to feed the household.
func feed_line() -> String:
	if catalogue == null:
		return NO_CROPS
	return YieldScript.feed_text(
		YieldScript.plan(catalogue, people(), spare()), people(), spare()
	)


## How much of the list could and could not be worked out.
func summary_text() -> String:
	if catalogue == null:
		return NO_CROPS
	return YieldScript.describe_rows(YieldScript.plan(catalogue, people(), spare()))


## The guidance: what the page is waiting for, or what it is doing. Kept apart from the feed line above,
## so nothing is said twice.
func hint() -> String:
	if catalogue == null or row_count() == 0:
		return NO_CROPS
	if int(YieldScript.counts(YieldScript.plan(catalogue, people(), spare()))["worked"]) == 0:
		return NO_FACTS
	return ANSWER_HINT


# --- what it says -------------------------------------------------------------------------


func say(text: String) -> void:
	_status = text
	if _status_label != null:
		_status_label.text = text


func said() -> String:
	return _status


func status_text() -> String:
	return _status


## True when nothing on the page can take the drawing's keyboard except the two number fields, which are
## the one kind of control that may hold it.
func lists_are_keyboard_free() -> bool:
	return _crops_list != null and _crops_list.focus_mode == Control.FOCUS_NONE


func request_close() -> void:
	hide()
	closed.emit()


func _on_close_requested() -> void:
	request_close()


# --- the refresh --------------------------------------------------------------------------


func _refresh() -> void:
	if not _built:
		return
	_list_label.text = "Plants to feed %s \u2014 %d" % [YieldScript.people_text(people()), row_count()]
	var texts: Array[String] = row_texts()
	_crops_list.clear()
	for text: String in texts:
		_crops_list.add_item(text)
	_feed_line.text = feed_line()
	_summary_label.text = summary_text()
	_hint_label.text = hint()
	if _order_button != null:
		_order_button.disabled = not order_enabled()


func _on_field_changed(_value: float) -> void:
	_refresh()