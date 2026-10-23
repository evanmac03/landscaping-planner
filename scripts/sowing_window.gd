class_name SowingWindow
extends Window
## When to sow, and how to keep it coming: the growing season read as a sowing calendar.
##
## `SowingPlanner` is the arithmetic - the days a crop may be sown on and still ripen, the day it is
## ready, and the succession of sowings that keeps it coming. This is the screen: a day to sow on, a
## crop to sow, an interval to repeat it by, and the sentences those three produce.
##
## A `Window`, like the season page and for the same reason: it holds number fields, and a window is the
## one boundary at which controls are allowed to hold the keyboard. Everything else in this HUD is built
## focus-free, and the spin boxes here are the one kind of control that may take a key.
##
## ## What it reads and what it does not
##
## It reads the drawing for the one thing it cannot work out for itself - the site's frost dates, which
## live on the drawing (see `SeasonWindow`) - and the plant list for the crops' times to maturity. It
## writes nothing: a sowing date is a question a person asks, not a fact about the plan, so changing it
## changes only what the page says and never the drawing. It owns the day in hand and the interval in
## the same way `RotationWindow` owns a bed's history - the drawing was never told either.
##
## The rule it keeps, as every food page does: a question nobody answered is skipped, not green. A crop
## that records no time to maturity, or a drawing that states no season, comes back unknown rather than
## a comfortable fit that was never checked.

const PlannerScript := preload("res://scripts/sowing_planner.gd")

## The page was closed by its own close button.
signal closed

## Big enough for the fields, the crop's sentences, the list and the words underneath without anything
## falling off the bottom edge.
const SIZE := Vector2i(940, 700)

const EXPLANATION := ("Say when you mean to sow, and the season works out the rest. A crop takes a "
	+ "stated number of days from sowing to its first harvest, so sown on a given day it is ready on a "
	+ "day you can count, and that day either comes before the first frost or it does not. Sow the same "
	+ "crop again every few weeks and its harvest moves on rather than ripening all at once - that is a "
	+ "succession, and its last sowing is the last one with time to finish.")

const NO_DOCUMENT := "there is no drawing open, so there is no season to sow into"
const NOT_STATED_HINT := ("the drawing does not state a growing season yet: open Site > How long the "
	+ "season is and set the frost dates, and every sowing date is then measured against them")
const NO_CROPS := "this plant list has no food in it yet"
const NO_CROP_CHOSEN := "choose a crop to work out when to sow it"
const ANSWER_HINT := ("move the sowing date to see when a crop would ripen, and the interval to see how "
	+ "long you can keep it coming")

## The day the sowing field starts on when the drawing states no season. A temperate garden's last
## frost - the middle of May - offered as a starting point rather than as a claim.
const DEFAULT_SOW := 140

## The drawing whose season the sowings are measured against. Null means there is none, which the page
## reports rather than fails on.
var document: DraftDocument = null
var catalogue: PlantCatalogue = null

var _built: bool = false
var _status: String = ""
var _rows_signature_seen: String = "<never written>"

var _season_line: Label = null
var _sow_box: SpinBox = null
var _every_box: SpinBox = null
var _crop_option: OptionButton = null
var _crop_line: Label = null
var _verdict_line: Label = null
var _window_line: Label = null
var _succession_line: Label = null
var _list_label: Label = null
var _crops_list: ItemList = null
var _summary_label: Label = null
var _hint_label: Label = null
var _status_label: Label = null


# --- building -----------------------------------------------------------------------------


## Build the controls, once. Idempotent, and callable off-tree, so a test drives the same controls the
## program shows.
func build() -> void:
	if _built:
		return
	_built = true
	title = "When to sow"
	# A window that has never been shown still defaults to visible, and a page that is up before anybody
	# asked for it is the one thing every page in this HUD has to avoid.
	hide()
	size = SIZE
	close_requested.connect(_on_close_requested)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 16.0
	column.offset_top = 12.0
	column.offset_right = -16.0
	column.offset_bottom = -12.0
	column.add_theme_constant_override("separation", 6)
	add_child(column)

	var heading := Label.new()
	heading.name = "Heading"
	heading.text = "When to sow"
	column.add_child(heading)

	var explanation := Label.new()
	explanation.name = "Explanation"
	explanation.text = EXPLANATION
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(explanation)

	_season_line = Label.new()
	_season_line.name = "SeasonLine"
	_season_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_season_line)

	var sow_row := HBoxContainer.new()
	sow_row.name = "SowRow"
	var sow_caption := Label.new()
	sow_caption.name = "SowCaption"
	sow_caption.text = "Sow on"
	sow_caption.custom_minimum_size = Vector2(120.0, 0.0)
	sow_row.add_child(sow_caption)
	_sow_box = _day_box("SowBox", DEFAULT_SOW, "Day of the year. 140 is 20 May and 280 is 7 October.")
	sow_row.add_child(_sow_box)
	column.add_child(sow_row)

	var every_row := HBoxContainer.new()
	every_row.name = "EveryRow"
	var every_caption := Label.new()
	every_caption.name = "EveryCaption"
	every_caption.text = "Sow again every"
	every_caption.custom_minimum_size = Vector2(120.0, 0.0)
	every_row.add_child(every_caption)
	_every_box = _day_box(
		"EveryBox", PlannerScript.DEFAULT_INTERVAL, "Days between one sowing of the crop and the next."
	)
	_every_box.min_value = float(PlannerScript.MIN_INTERVAL)
	_every_box.max_value = float(PlannerScript.MAX_INTERVAL)
	every_row.add_child(_every_box)
	var every_units := Label.new()
	every_units.name = "EveryUnits"
	every_units.text = "days"
	every_row.add_child(every_units)
	column.add_child(every_row)

	var crop_row := HBoxContainer.new()
	crop_row.name = "CropRow"
	var crop_caption := Label.new()
	crop_caption.name = "CropCaption"
	crop_caption.text = "Crop"
	crop_caption.custom_minimum_size = Vector2(120.0, 0.0)
	crop_row.add_child(crop_caption)
	_crop_option = OptionButton.new()
	_crop_option.name = "Crop"
	# The HUD's own rule: a control in the HUD never takes the keyboard from the drawing.
	_crop_option.focus_mode = Control.FOCUS_NONE
	_crop_option.tooltip_text = "The crop to sow"
	_crop_option.custom_minimum_size = Vector2(320.0, 0.0)
	_crop_option.item_selected.connect(_on_crop_selected)
	crop_row.add_child(_crop_option)
	column.add_child(crop_row)

	_crop_line = Label.new()
	_crop_line.name = "CropLine"
	_crop_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_crop_line)

	_verdict_line = Label.new()
	_verdict_line.name = "VerdictLine"
	_verdict_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_verdict_line)

	_window_line = Label.new()
	_window_line.name = "WindowLine"
	_window_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_window_line)

	_succession_line = Label.new()
	_succession_line.name = "SuccessionLine"
	_succession_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_succession_line)

	_list_label = Label.new()
	_list_label.name = "ListLabel"
	column.add_child(_list_label)
	_crops_list = ItemList.new()
	_crops_list.name = "Crops"
	_crops_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_crops_list.custom_minimum_size = Vector2(0.0, 180.0)
	# A list a person reads is not a list a person types into: the keyboard belongs to the fields.
	_crops_list.focus_mode = Control.FOCUS_NONE
	_crops_list.select_mode = ItemList.SELECT_SINGLE
	column.add_child(_crops_list)

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
	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "Close"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(request_close)
	buttons.add_child(close_button)
	column.add_child(buttons)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status_label)

	# A page with nothing in it yet is still a page: it says what it is waiting for rather than showing
	# an empty list that reads as a garden nothing is sown in.
	refresh()


func _day_box(node_name: String, start: int, tip: String) -> SpinBox:
	var box := SpinBox.new()
	box.name = node_name
	box.min_value = 1.0
	box.max_value = float(PlannerScript.MAX_DAY)
	box.step = 1.0
	box.value = clampi(start, 1, PlannerScript.MAX_DAY)
	box.custom_minimum_size = Vector2(96.0, 0.0)
	box.tooltip_text = tip
	box.value_changed.connect(_on_field_changed)
	return box


# --- binding ------------------------------------------------------------------------------


## Point the page at the plant list and the drawing whose season it sows into. Absent is a state the
## page reports rather than fails on.
##
## The sowing field is put back on the drawing's last frost whenever the page is bound - the day a
## gardener opens the page on, before moving it - while a re-bind behind an open page (the tick) leaves
## the day in hand alone.
func bind(new_catalogue: PlantCatalogue, new_document: DraftDocument) -> void:
	build()
	catalogue = new_catalogue
	document = new_document
	_rebuild_crop_choices()
	if season_stated():
		_set_sow_field(last_frost())
	else:
		_set_sow_field(DEFAULT_SOW)
	if _every_box != null:
		_every_box.set_value_no_signal(float(PlannerScript.DEFAULT_INTERVAL))
	refresh()


## Point the page at a drawing whose season may have moved. The day in hand is left where it is: what a
## person is about to sow is theirs, and the tick must not throw it away.
func set_document(new_document: DraftDocument) -> void:
	document = new_document
	refresh()


func set_catalogue(new_catalogue: PlantCatalogue) -> void:
	catalogue = new_catalogue
	_rebuild_crop_choices()
	refresh()


# --- the drawing --------------------------------------------------------------------------


## The stated season: the last frost of spring, or 0 when the drawing states none.
func last_frost() -> int:
	return document.season_last_frost if document != null else 0


## The stated season: the first frost of autumn, or 0 when the drawing states none.
func first_frost() -> int:
	return document.season_first_frost if document != null else 0


## Whether the drawing states a season at all.
func season_stated() -> bool:
	return document != null and PlannerScript.GrowingSeasonScript.is_stated(last_frost(), first_frost())


## The stated season in words, or the reason there is none.
func season_line() -> String:
	if document == null:
		return NO_DOCUMENT
	return PlannerScript.GrowingSeasonScript.season_text(last_frost(), first_frost())


# --- the fields ---------------------------------------------------------------------------


## The day in hand to sow on, whether or not it is in the season.
func sow() -> int:
	return int(_sow_box.value) if _sow_box != null else DEFAULT_SOW


## Put a sowing day in the field, the way a person editing it would, and put the answers in step with it.
func set_sow(day: int) -> void:
	_set_sow_field(day)
	_refresh_answers()


func _set_sow_field(day: int) -> void:
	if _sow_box != null:
		_sow_box.set_value_no_signal(clampi(day, 1, PlannerScript.MAX_DAY))


## The days between one sowing and the next.
func interval() -> int:
	return int(_every_box.value) if _every_box != null else PlannerScript.DEFAULT_INTERVAL


func set_interval(days: int) -> void:
	if _every_box != null:
		_every_box.set_value_no_signal(
			clampi(days, PlannerScript.MIN_INTERVAL, PlannerScript.MAX_INTERVAL)
		)
	_refresh_answers()


# --- the crop -----------------------------------------------------------------------------


## The ids of the crops the picker offers, in the order it offers them.
func crop_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	if _crop_option == null:
		return out
	for index in _crop_option.item_count:
		out.append(StringName(_crop_option.get_item_metadata(index)))
	return out


func selected_crop_id() -> StringName:
	if _crop_option == null or _crop_option.selected < 0:
		return &""
	return StringName(_crop_option.get_item_metadata(_crop_option.selected))


## The crop in hand, or null when the list has none or none is chosen.
func selected_crop() -> PlantSpecies:
	var crop_id: StringName = selected_crop_id()
	if catalogue == null or crop_id == &"":
		return null
	return catalogue.get_species(crop_id)


## Choose the crop to sow. Refused for an id the list does not hold; selecting does not emit
## `item_selected`, which is right: choosing what to sow is not a request to do anything.
func choose_crop(crop_id: StringName) -> bool:
	if _crop_option == null:
		return false
	var index: int = _option_index_of(crop_id)
	if index < 0:
		return false
	_crop_option.select(index)
	_refresh_answers()
	return true


func _option_index_of(crop_id: StringName) -> int:
	if _crop_option == null:
		return -1
	for index in _crop_option.item_count:
		if StringName(_crop_option.get_item_metadata(index)) == crop_id:
			return index
	return -1


func _rebuild_crop_choices() -> void:
	if _crop_option == null:
		return
	var keep: StringName = selected_crop_id()
	_crop_option.clear()
	var crops: Array[PlantSpecies] = []
	if catalogue != null:
		for plant: PlantSpecies in catalogue.all():
			if plant.is_edible():
				crops.append(plant)
	crops.sort_custom(func(a: PlantSpecies, b: PlantSpecies) -> bool:
		return a.display_name() < b.display_name())
	for crop: PlantSpecies in crops:
		_crop_option.add_item(crop.display_name())
		_crop_option.set_item_metadata(_crop_option.item_count - 1, crop.id)
	if _crop_option.item_count == 0:
		return
	var index: int = 0
	var found: int = _option_index_of(keep)
	if found >= 0:
		index = found
	_crop_option.select(index)


# --- what the crop comes to -----------------------------------------------------------------


## The crop's own line: its name and its time to maturity.
func crop_line() -> String:
	var crop: PlantSpecies = selected_crop()
	if crop == null:
		return NO_CROPS
	var days: String = crop.maturity_text()
	return "%s \u2014 %s" % [crop.display_name(), days if not days.is_empty() else "no time to maturity stated"]


## The sowing check for the crop in hand: the judgement line from `SowingPlanner`.
func verdict_line() -> String:
	var crop: PlantSpecies = selected_crop()
	if crop == null:
		return NO_CROPS
	return String(PlannerScript.check(crop, last_frost(), first_frost(), sow())["summary"])


## The days the crop may be sown on, or the reason there are none.
func window_line() -> String:
	var crop: PlantSpecies = selected_crop()
	if document == null:
		return NO_DOCUMENT
	if crop == null:
		return NO_CROPS
	var words: String = PlannerScript.window_text(last_frost(), first_frost(), crop.maturity_days)
	if not season_stated() and words == PlannerScript.NO_SEASON:
		return NOT_STATED_HINT
	return words


## The succession of sowings of the crop in hand, or the reason there is none.
func succession_line() -> String:
	var crop: PlantSpecies = selected_crop()
	if document == null:
		return NO_DOCUMENT
	if crop == null:
		return NO_CROPS
	return PlannerScript.succession_text(crop, last_frost(), first_frost(), sow(), interval())


## The lines the crop list shows: every food crop, best first, checked against the day in hand.
func row_texts() -> Array[String]:
	if catalogue == null:
		return [] as Array[String]
	return PlannerScript.row_texts(catalogue, last_frost(), first_frost(), sow())


func row_count() -> int:
	return row_texts().size()


## Crop list in one sentence, or what the list itself is missing.
func summary_text() -> String:
	if catalogue == null:
		return NO_CROPS
	return PlannerScript.describe_rows(PlannerScript.rows(catalogue, last_frost(), first_frost(), sow()))


## The guidance: what the page is waiting for, or what it is doing. Kept apart from the verdict line and
## from the season line above, so nothing is said twice.
func hint() -> String:
	if document == null:
		return NO_DOCUMENT
	if not season_stated():
		return NOT_STATED_HINT
	if catalogue == null or row_count() == 0:
		return NO_CROPS
	if selected_crop() == null:
		return NO_CROP_CHOSEN
	return ANSWER_HINT


# --- what the page says --------------------------------------------------------------------


func say(text: String) -> void:
	_status = text
	if _status_label != null:
		_status_label.text = text


func said() -> String:
	return _status


func status_text() -> String:
	return _status


## True when nothing on the page can take the drawing's keyboard except the two number fields, which
## are the one kind of control that may hold it.
func lists_are_keyboard_free() -> bool:
	return _crops_list != null and _crops_list.focus_mode == Control.FOCUS_NONE


func request_close() -> void:
	hide()
	closed.emit()


func _on_close_requested() -> void:
	request_close()


# --- the refresh -------------------------------------------------------------------------


## Read the drawing again and put its season and the answers on the page. Touches the guidance and never
## the status.
func refresh() -> void:
	if not _built:
		return
	_season_line.text = season_line()
	_refresh_answers()


## The answers themselves: every line that depends on the day in hand, the interval or the crop.
func _refresh_answers() -> void:
	if not _built:
		return
	_crop_line.text = crop_line()
	_verdict_line.text = verdict_line()
	_window_line.text = window_line()
	_succession_line.text = succession_line()
	_list_label.text = "The food list, sown on %s \u2014 %d" % [_sow_words(), row_count()]
	_write_rows()
	_summary_label.text = summary_text()
	_hint_label.text = hint()


func _sow_words() -> String:
	var words: String = PlannerScript.day_words(sow())
	return words if not words.is_empty() else "no day"


## Write the rows, once per sowing day. Signature-guarded, so a page left open does not rebuild a
## hundred strings a frame.
func _write_rows() -> void:
	var texts: Array[String] = row_texts()
	var signature: String = "%d|%d|%d|%s" % [
		last_frost(), first_frost(), sow(), "+".join(PackedStringArray(texts))
	]
	if signature == _rows_signature_seen:
		return
	_rows_signature_seen = signature
	_crops_list.clear()
	for text: String in texts:
		_crops_list.add_item(text)


func _on_field_changed(_value: float) -> void:
	_refresh_answers()


func _on_crop_selected(index: int) -> void:
	var crop_id: StringName = StringName(_crop_option.get_item_metadata(index))
	choose_crop(crop_id)
	say(verdict_line())