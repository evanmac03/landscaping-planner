class_name HarvestWindow
extends Window
## What is ready when: the year as twelve lists of crops, one month at a time.
##
## `HarvestCalendar` is the arithmetic - which crops the catalogue records as ready in a month, and what
## the whole year comes to. This is the screen: a month to choose, the crops ready in it, and the shape
## of the year underneath.
##
## Four things are true of this page, and each is a decision:
##
## * **It holds no arithmetic and no records.** Every list comes from `HarvestCalendar` and every line
##   from a species' own `edible_parts_text`, so the page cannot disagree with the calendar.
##
## * **It opens on the fullest month, not on January.** A calendar is most useful where there is
##   something to read, and the busiest month is the one the catalogue actually has content for. A list
##   with nothing ready opens on January and says so.
##
## * **An empty month is a real answer.** January with nothing ready is a fact about the plant list, not
##   a fault: the page says "nothing is recorded as ready in January" and keeps going.
##
## * **Nothing here writes anything**, and everything it builds is built without a keyboard of its own:
##   it is a page you read, choose on and close. What the page does with the keyboard while it is *open*
##   is decided once, by `PageChrome.takes_the_keyboard`.

## A page wide enough for the month's list and a couple of sentences about the year, and as tall as all
## of it comes to: measured, that is 682 px, so 690 with the buttons on the end.
const SIZE := Vector2i(940, 690)

const HarvestCalendarScript := preload("res://scripts/harvest_calendar.gd")

const EXPLANATION := ("Pick a month and read what is ready then. A crop's harvest window is the span "
	+ "of months the plant list records for it - some are cut for a single month, some stand through "
	+ "the winter - and a crop the list says nothing about is counted apart rather than shown on a "
	+ "month it was never given.")

const NO_CROPS := "this plant list has no food in it yet"

signal closed

var catalogue: PlantCatalogue = null
var _built: bool = false
var _status: String = ""

var _heading: Label = null
var _explanation: Label = null
var _month_option: OptionButton = null
var _month_line: Label = null
var _list_label: Label = null
var _crops_list: ItemList = null
var _year_line: Label = null
var _unstated_line: Label = null
var _hint_label: Label = null
var _close_button: Button = null
var _status_label: Label = null


# --- building -----------------------------------------------------------------------------


## Build the controls, once. Idempotent, and callable off-tree, so a test drives the same controls the
## program shows.
func build() -> void:
	if _built:
		return
	_built = true
	title = "What's ready when"
	hide()
	size = SIZE
	close_requested.connect(_on_close_requested)

	var column := PageChrome.column(self, 6, Vector2(16.0, 12.0))

	_heading = PageChrome.subheading("What's ready when")
	column.add_child(_heading)

	_explanation = PageChrome.note(EXPLANATION)
	column.add_child(_explanation)

	_month_option = OptionButton.new()
	_month_option.name = "Month"
	# Built without a keyboard of its own, like everything a page makes; the shared show is what gives it
	# one while the page is open.
	_month_option.focus_mode = Control.FOCUS_NONE
	_month_option.tooltip_text = "The month to read"
	_month_option.custom_minimum_size = Vector2(300.0, 0.0)
	_month_option.item_selected.connect(func(index: int) -> void: _on_month_selected(index))
	# The shared chrome names the row after the control it carries, which is the `MonthRow` this page's own
	# tests have always read the dropdown under.
	column.add_child(PageChrome.labelled("Month", _month_option))

	_month_line = PageChrome.text()
	_month_line.name = "MonthLine"
	column.add_child(_month_line)

	_list_label = PageChrome.text()
	_list_label.name = "ListLabel"
	column.add_child(_list_label)
	_crops_list = ItemList.new()
	_crops_list.name = "Crops"
	_crops_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_crops_list.custom_minimum_size = Vector2(0.0, 300.0)
	# A list a person reads rather than types into, built without a keyboard of its own like the rest.
	_crops_list.focus_mode = Control.FOCUS_NONE
	_crops_list.select_mode = ItemList.SELECT_SINGLE
	column.add_child(_crops_list)

	_year_line = PageChrome.text()
	_year_line.name = "Year"
	column.add_child(_year_line)

	_unstated_line = PageChrome.text()
	_unstated_line.name = "Unstated"
	column.add_child(_unstated_line)

	_hint_label = PageChrome.hint()
	column.add_child(_hint_label)

	var buttons := PageChrome.button_row()
	column.add_child(buttons)
	_close_button = PageChrome.button("Close")
	_close_button.pressed.connect(request_close)
	buttons.add_child(_close_button)

	_status_label = PageChrome.status()
	column.add_child(_status_label)

	_rebuild_month_choices()
	_refresh()


# --- binding ------------------------------------------------------------------------------


## Point the page at the plant list it reads. Absent is a state the page reports rather than fails on,
## and the month in hand is the fullest one so the page opens where there is something to read.
func bind(new_catalogue: PlantCatalogue) -> void:
	build()
	catalogue = new_catalogue
	choose_month(_default_month())
	_refresh()


func month() -> int:
	if _month_option == null or _month_option.selected < 0:
		return 1
	return int(_month_option.get_item_metadata(_month_option.selected))


func month_name() -> String:
	return HarvestCalendarScript.month_name(month())


## Choose the month to read. Refused for a number that is not a month; selecting does not emit
## `item_selected`, which is right: choosing what to look at is not a request to do anything.
func choose_month(which: int) -> bool:
	if _month_option == null or not HarvestCalendarScript.is_month(which):
		return false
	_month_option.select(which - 1)
	_refresh()
	return true


func row_texts() -> Array[String]:
	if catalogue == null:
		return [] as Array[String]
	return HarvestCalendarScript.row_texts(catalogue, month())


func row_count() -> int:
	return row_texts().size()


## The month's own headline: how many crops are ready in it, or that nothing is.
func month_line() -> String:
	if catalogue == null:
		return NO_CROPS
	return HarvestCalendarScript.describe_rows(
		HarvestCalendarScript.rows(catalogue, month()), month()
	)


## The shape of the whole year, in one sentence.
func year_line() -> String:
	if catalogue == null:
		return NO_CROPS
	return HarvestCalendarScript.year_text(catalogue)


## What the list says nothing about, or empty when it says something about every crop.
func unstated_line() -> String:
	if catalogue == null:
		return ""
	return HarvestCalendarScript.unstated_line(catalogue)


## What the page is waiting for, or - once it can answer - what to try next. Deliberately not the
## headline again: a page that says the same sentence twice reads as a page that has lost track of
## which line is which.
func hint() -> String:
	if catalogue == null or HarvestCalendarScript.year_text(catalogue) == HarvestCalendarScript.NO_FOOD:
		return NO_CROPS
	if row_count() == 0:
		return "nothing is ready this month; choose another"
	return "choose another month to see what else is ready"


# --- what it says -------------------------------------------------------------------------


func say(text: String) -> void:
	_status = text
	if _status_label != null:
		_status_label.text = text


func said() -> String:
	return _status


func status_text() -> String:
	return _status


## True when the page is *built* with nothing that takes a keyboard of its own: there is no text field
## here, and the list is built focus-free like every other control a page makes. Whether the page holds
## the keyboard once it is open is the shared show's decision, and is measured live rather than here.
func lists_are_keyboard_free() -> bool:
	return _crops_list != null and _crops_list.focus_mode == Control.FOCUS_NONE


func request_close() -> void:
	hide()
	closed.emit()


# --- the refresh --------------------------------------------------------------------------


## The month the page opens on: the one the catalogue has the most ready in, or January when it has
## nothing ready at all - so an empty list still opens somewhere it can say so.
func _default_month() -> int:
	if catalogue == null:
		return 1
	var fullest: Dictionary = HarvestCalendarScript.busiest(catalogue)
	if int(fullest["month"]) <= 0:
		return 1
	return int(fullest["month"])


func _rebuild_month_choices() -> void:
	if _month_option == null:
		return
	_month_option.clear()
	for which in range(1, HarvestCalendarScript.MONTHS + 1):
		_month_option.add_item(HarvestCalendarScript.month_name(which))
		_month_option.set_item_metadata(which - 1, which)
	_month_option.selected = 0


func _refresh() -> void:
	if not _built:
		return
	_month_line.text = month_line()
	_list_label.text = "Ready in %s \u2014 %d" % [month_name(), row_count()]
	var texts: Array[String] = row_texts()
	_crops_list.clear()
	for text: String in texts:
		_crops_list.add_item(text)
	_year_line.text = year_line()
	_unstated_line.text = unstated_line()
	_hint_label.text = hint()


func _on_month_selected(index: int) -> void:
	if not choose_month(int(_month_option.get_item_metadata(index))):
		return
	say("%s: %s" % [month_name(), month_line()])


func _on_close_requested() -> void:
	request_close()