class_name SunWindow
extends Window
## The sun and shadow study, as a page: the site the presentation is showing, the moments to study
## at, and what a stated height casts at each of them.
##
## Four things are true of this page, and each of them is a decision:
##
## - **It holds a list of moments, not a moment.** `SunStudy` is a place and a time; what a client
##   asks is a *season* of them - "will it be in shade by four" and "will it be in shade in June" -
##   so the page's own subject is the list, and the presets are the four lists gardens get asked
##   about.
## - **The site is not stated here.** Latitude, longitude and zone offset are a fact about the
##   drawing, and the presentation panel is where they are edited. This page reads them, shows them
##   in words, and says so when there are none - a second copy of the site form would be a second
##   answer to one question.
## - **The height is stated here**, because it is the one input the drawing cannot supply: an entity
##   is a shape on the ground and carries no height. The study reports what *that* casts, and never
##   claims to know what is in the shade.
## - **Nothing is written by this page.** The sun is aimed by the presentation, the stills are
##   rendered by the presentation's own exporter, and this page asks for both by signal - which is
##   what lets it be built, filled and driven with no director, no drawing and no screen.

## A page wide enough for a row of the report, which is the longest line here - a day, a time, the
## sun's own numbers and what the height casts - and tall enough for the whole of it: measured, the
## report, the fields and the buttons want 811 px, so 820.
const SIZE := Vector2i(1020, 820)

const SunReportScript := preload("res://scripts/vis/sun_report.gd")
const SunStudyScript := preload("res://scripts/vis/sun_study.gd")
const UnitsScript := preload("res://scripts/draft/units.gd")

const EXPLANATION := ("The place is the presentation's own site, kept with the drawing. Choose the "
	+ "moments a client will ask about, and say how tall the thing casting the shadow is: each row "
	+ "is the sun at that moment and what that height throws there. A shadow is arithmetic on a sun "
	+ "and a height, so nothing here reads the yard.")

### What the page says when it cannot study anything yet. Each names what is missing rather than
### showing an empty table, because an empty table reads as a study that found nothing.
const NO_SITE := "there is no site to study yet: the presentation panel holds the latitude, the longitude and the zone offset"
const NO_MOMENTS := "no moments have been chosen, so there is nothing to study"
const NO_CHOICE := "choose a moment to aim the sun at, or render the whole study"
const NO_SUN := "the sun is below the horizon then, so there is no sun to aim"

## Asked for when the page wants the presentation aimed at a moment.
signal apply_requested(moment: Dictionary)
## Asked for when the page wants one still per moment. Only the moments with the sun up are
## handed over: a still of a garden after dark is a still of nothing, and a caller that had to
## sort them out itself would be a second answer to which moments are worth rendering.
signal render_requested(moments: Array)
signal closed

## The site in hand. Empty until it is told one, which is a real state: the presentation may not
## be ready, or the drawing may have no site.
var _site: Dictionary = {}
## The drawing's units, defaulted to metric rather than left null: the height in hand is in
## metres whatever the drawing is, and the words on the page have to be able to be printed before
## anybody has told the page what the drawing is drawn in.
var _units: DraftUnits = UnitsScript.or_default(null)
## The height in hand, in **metres**, which is what `SunReport` works in whatever the drawing's
## own units are. The field shows it in the drawing's unit and this is converted at the edge.
var _height_m: float = SunReportScript.DEFAULT_HEIGHT_M
var _moments: Array[Dictionary] = []
var _summary: String = ""
var _status: String = ""
var _built: bool = false
var _rows_signature_seen: String = "<never written>"

var _heading: Label = null
var _explanation: Label = null
var _site_line: Label = null
var _height_label: Label = null
var _height_box: SpinBox = null
var _day_box: SpinBox = null
var _hour_box: SpinBox = null
var _moments_label: Label = null
var _moments_list: ItemList = null
var _days_label: Label = null
var _rows_label: Label = null
var _rows_list: ItemList = null
var _summary_label: Label = null
var _hint_label: Label = null
var _apply_button: Button = null
var _render_button: Button = null
var _close_button: Button = null
var _status_label: Label = null


# --- building -------------------------------------------------------------------------


## Build the controls, once. Idempotent, and callable off-tree, so a test drives the same
## controls the program shows.
func build() -> void:
	if _built:
		return
	_built = true
	title = "Sun and shadow study"
	# A window that has never been shown still defaults to visible, and a page that is up before
	# anybody asked for it is the one thing every page in this HUD has to avoid.
	hide()
	size = SIZE
	close_requested.connect(_on_close_requested)

	# Longer than the screen this page is sized for: what does not fit scrolls into view rather than
	# being cut off at the foot of the page.
	var column: VBoxContainer = PageChrome.scrolling_column(self, 6, Vector2(16.0, 12.0))

	_heading = Label.new()
	_heading.name = "Heading"
	_heading.text = "Sun and shadow study"
	column.add_child(_heading)

	_explanation = Label.new()
	_explanation.name = "Explanation"
	_explanation.text = EXPLANATION
	_explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_explanation)

	_site_line = Label.new()
	_site_line.name = "SiteLine"
	column.add_child(_site_line)

	var height_row := HBoxContainer.new()
	height_row.name = "HeightRow"
	_height_label = Label.new()
	_height_label.name = "HeightLabel"
	height_row.add_child(_height_label)
	_height_box = SpinBox.new()
	_height_box.name = "HeightBox"
	_height_box.min_value = 0.1
	_height_box.max_value = 40.0
	# Five centimetres: finer than anyone measures a fence, and fine enough that a height stated in
	# the drawing's own unit survives being put in the box and read back out of it.
	_height_box.step = 0.05
	_height_box.value = _height_m
	_height_box.custom_minimum_size = Vector2(96.0, 0.0)
	_height_box.tooltip_text = "How tall the thing casting the shadow is. A 1.8 m fence is the usual answer."
	_height_box.value_changed.connect(_on_height_changed)
	height_row.add_child(_height_box)
	column.add_child(height_row)

	var moment_row := HBoxContainer.new()
	moment_row.name = "MomentRow"
	var day_caption := Label.new()
	day_caption.text = "Day"
	moment_row.add_child(day_caption)
	_day_box = SpinBox.new()
	_day_box.name = "DayBox"
	_day_box.min_value = 1.0
	_day_box.max_value = 366.0
	_day_box.step = 1.0
	_day_box.value = SunReportScript.JUNE_SOLSTICE
	_day_box.custom_minimum_size = Vector2(72.0, 0.0)
	_day_box.tooltip_text = "Day of the year. 172 is 21 June and 355 is 21 December."
	moment_row.add_child(_day_box)
	var hour_caption := Label.new()
	hour_caption.text = "at"
	moment_row.add_child(hour_caption)
	_hour_box = SpinBox.new()
	_hour_box.name = "HourBox"
	_hour_box.min_value = 0.0
	_hour_box.max_value = 24.0
	_hour_box.step = 0.5
	_hour_box.value = 16.0
	_hour_box.suffix = " h"
	_hour_box.custom_minimum_size = Vector2(88.0, 0.0)
	_hour_box.tooltip_text = "The site's own clock, so four in the afternoon means what the client's watch says."
	moment_row.add_child(_hour_box)
	var add_button := _button(moment_row, "AddButton", "Add the moment")
	add_button.pressed.connect(_on_add_pressed)
	var remove_button := _button(moment_row, "RemoveButton", "Remove the moment")
	remove_button.pressed.connect(_on_remove_pressed)
	column.add_child(moment_row)

	var preset_row := HBoxContainer.new()
	preset_row.name = "PresetRow"
	for preset_name: StringName in SunReportScript.preset_names():
		var caption: String = "Study %s" % SunReportScript.preset_name(preset_name)
		var preset_button := _button(preset_row, "Preset_%s" % String(preset_name), caption)
		preset_button.tooltip_text = "Replace the list with %s" % SunReportScript.preset_name(preset_name)
		preset_button.pressed.connect(_on_preset_pressed.bind(preset_name))
	column.add_child(preset_row)

	_moments_label = Label.new()
	_moments_label.name = "MomentsLabel"
	column.add_child(_moments_label)
	_moments_list = ItemList.new()
	_moments_list.name = "Moments"
	_moments_list.custom_minimum_size = Vector2(0.0, 120.0)
	# A list a person reads is not a list a person types into: the keyboard belongs to the fields,
	# and nothing here takes a key from the drawing.
	_moments_list.focus_mode = Control.FOCUS_NONE
	_moments_list.select_mode = ItemList.SELECT_SINGLE
	_moments_list.item_selected.connect(_on_moment_selected)
	column.add_child(_moments_list)

	_days_label = Label.new()
	_days_label.name = "Days"
	_days_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_days_label)

	_rows_label = Label.new()
	_rows_label.name = "RowsLabel"
	column.add_child(_rows_label)
	_rows_list = ItemList.new()
	_rows_list.name = "Rows"
	_rows_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rows_list.custom_minimum_size = Vector2(0.0, 200.0)
	_rows_list.focus_mode = Control.FOCUS_NONE
	_rows_list.select_mode = ItemList.SELECT_SINGLE
	column.add_child(_rows_list)

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
	_apply_button = _button(buttons, "ApplyButton", "Aim the sun at it")
	_apply_button.pressed.connect(_on_apply_pressed)
	_render_button = _button(buttons, "RenderButton", "Render the stills")
	_render_button.tooltip_text = "One still per moment, named for the moment it shows"
	_render_button.pressed.connect(_on_render_pressed)
	_close_button = _button(buttons, "CloseButton", "Close")
	_close_button.pressed.connect(request_close)
	column.add_child(buttons)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status_label)

	# A page with nothing in it yet is still a page: it says what it is waiting for rather than
	# showing an empty table that reads as a study which found nothing.
	_refresh()


func _button(row: Node, node_name: String, caption: String) -> Button:
	var made_button := Button.new()
	made_button.name = node_name
	made_button.text = caption
	# The HUD's own rule: a control in the HUD never takes the keyboard from the drawing.
	made_button.focus_mode = Control.FOCUS_NONE
	row.add_child(made_button)
	return made_button


# --- the site, and the height ---------------------------------------------------------


## Point the page at a site. Empty means there is none, which is a state the page reports rather
## than fails on.
func bind(site_dict: Dictionary) -> void:
	_site = site_dict.duplicate()
	say("")
	_refresh()
	say(opening_words())


## The site in hand, as a copy, so a caller cannot edit the page's own copy by accident.
func site() -> Dictionary:
	return _site.duplicate()


func has_site() -> bool:
	return not _site.is_empty()


## Set the drawing's units, so the height the person types and the length the report prints are in
## the unit the drawing is drawn in. A drawing in feet gets a field in feet.
func set_units(units: DraftUnits) -> void:
	_units = UnitsScript.or_default(units)
	if _height_box != null:
		_height_box.suffix = _unit_suffix()
		_height_box.set_value_no_signal(_shown_height())
	_refresh()


## The height in hand, in the drawing's own unit, as the field reads.
func height_in_hand() -> float:
	if _height_box == null:
		return _shown_height()
	return _height_box.value


## The height in hand, in metres, which is what the study works in.
func height_m() -> float:
	return _metres_from(float(height_in_hand()))


func set_height(metres: float) -> void:
	_height_m = metres
	if _height_box != null:
		# `set_value_no_signal` because a page filling its own field is not a person editing it,
		# and the refresh below does the work either way.
		_height_box.set_value_no_signal(_shown_height())
	_refresh()


func height_words() -> String:
	return SunReportScript.height_words(_height_m, _units)


## The drawing's units this page is stating its height in.
func units_in_hand() -> DraftUnits:
	return _units


## The day and the hour the two fields describe. Setting them is not an edit anybody has to be
## told about - nothing is connected to either field, and Add is what acts on them - which is why
## these are plain assignments rather than signals.
func day_in_field() -> int:
	if _day_box == null:
		return SunReportScript.JUNE_SOLSTICE
	return int(_day_box.value)


func hour_in_field() -> float:
	if _hour_box == null:
		return 12.0
	return _hour_box.value


func set_day(day_of_year: int) -> void:
	if _day_box != null:
		_day_box.value = clampi(day_of_year, 1, 366)


func set_hour(hours: float) -> void:
	if _hour_box != null:
		_hour_box.value = clampf(hours, 0.0, 24.0)


func _unit_suffix() -> String:
	return " ft" if _units.system == UnitsScript.System.IMPERIAL else " m"


func _shown_height() -> float:
	return _display_from(_height_m)


func _display_from(metres: float) -> float:
	if _units.system == UnitsScript.System.IMPERIAL:
		return metres / UnitsScript.FOOT
	return metres


func _metres_from(shown: float) -> float:
	if _units.system == UnitsScript.System.IMPERIAL:
		return shown * UnitsScript.FOOT
	return shown


# --- the moments ----------------------------------------------------------------------


## The moments in hand, in the order they were chosen: a study's reading order is the order it was
## asked for, and sorting them would hide a moment somebody added twice.
func moments() -> Array[Dictionary]:
	return _moments.duplicate()


func moment_count() -> int:
	return _moments.size()


## Replace the whole list, as a preset does. Duplicates are dropped, because two identical rows
## are one moment studied twice and the second would be a still of the first.
func set_moments(list: Array) -> void:
	_moments.clear()
	for moment_dict: Dictionary in list:
		_add_one(moment_dict)
	_refresh()


func clear_moments() -> void:
	set_moments([])


## Add the moment the two fields describe.
func add_moment_from_fields() -> bool:
	if _day_box == null or _hour_box == null:
		return false
	var before: int = _moments.size()
	_add_one(SunStudyScript.moment(day_in_field(), hour_in_field()))
	_refresh()
	return _moments.size() > before


## Take the chosen moment off the list.
func remove_selected() -> bool:
	var at: int = selected_index()
	if at < 0 or at >= _moments.size():
		return false
	_moments.remove_at(at)
	_refresh()
	return true


## Replace the list with a ready-made study. False for a name nobody has, so the page says so
## rather than quietly emptying itself.
##
## Nothing is said here: installing a study is a *change* to the page, and the status is what the
## page last did - which is the button's own sentence, not this one. Writing the guidance into the
## status on every change is how a status line stops being about anything.
func use_preset(preset_name: StringName) -> bool:
	var preset_moments: Array = SunReportScript.preset(preset_name)
	if preset_moments.is_empty():
		say("there is no study called \"%s\"" % String(preset_name))
		return false
	set_moments(preset_moments)
	return true


func _add_one(moment_dict: Dictionary) -> void:
	for held: Dictionary in _moments:
		if SunReportScript.day_of(held) == SunReportScript.day_of(moment_dict) \
				and is_equal_approx(
					float(held.get("clock_hour", 0.0)),
					float(moment_dict.get("clock_hour", 0.0))
				):
			return
	_moments.append(moment_dict)


## The moments a still can be rendered at: the ones with the sun up. A still of a garden after
## dark is a still of nothing, and the rest of the page says which ones those are.
func renderable_moments() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for moment_dict: Dictionary in _moments:
		if bool(SunStudyScript.position_for(_site, moment_dict)["is_up"]):
			out.append(moment_dict)
	return out


## The moments with the sun below the horizon: studied, and not rendered.
func dark_moments() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for moment_dict: Dictionary in _moments:
		if not bool(SunStudyScript.position_for(_site, moment_dict)["is_up"]):
			out.append(moment_dict)
	return out


## The names the study's stills will be filed under, in the study's own order.
func still_names() -> Array[String]:
	return SunReportScript.still_names(renderable_moments())


## A moment as a person reads it, for the list.
func moment_texts() -> Array[String]:
	var out: Array[String] = []
	for moment_dict: Dictionary in _moments:
		out.append(SunReportScript.moment_words(moment_dict))
	return out


func choose_moment(index: int) -> bool:
	if _moments_list == null or index < 0 or index >= _moments.size():
		return false
	# Selecting does not emit `item_selected` in Godot, which is exactly right here: choosing
	# what the buttons act on is not a request to act.
	_moments_list.select(index)
	_refresh()
	return true


func selected_index() -> int:
	if _moments_list == null:
		return -1
	var chosen: PackedInt32Array = _moments_list.get_selected_items()
	if chosen.is_empty():
		return -1
	return int(chosen[0])


## The moment the buttons act on, or an empty dictionary when none is chosen.
func selected_moment() -> Dictionary:
	var at: int = selected_index()
	if at < 0 or at >= _moments.size():
		return {}
	return _moments[at]


# --- the study, as rows -----------------------------------------------------------------


## The study's own rows, one per moment, refusals included: a moment with the sun below the
## horizon is a row that says so rather than a hole in the table.
func study_rows() -> Array[Dictionary]:
	if not has_site():
		return [] as Array[Dictionary]
	return SunReportScript.rows(_site, _moments, _height_m, _units)


func row_count() -> int:
	return _moments.size()


func row_texts() -> Array[String]:
	var out: Array[String] = []
	for row: Dictionary in study_rows():
		out.append(String(row["text"]))
	return out


## Write the rows, once per study. Signature-guarded, so a page left open does not rebuild three
## hundred strings a frame.
func show_rows(built: Array) -> bool:
	var signature: String = _rows_signature(built)
	if signature == _rows_signature_seen:
		return false
	_rows_signature_seen = signature
	_rows_list.clear()
	for row: Dictionary in built:
		_rows_list.add_item(String(row["text"]))
	return true


func _rows_signature(built: Array) -> String:
	var texts: Array[String] = []
	for row: Dictionary in built:
		texts.append(String(row["text"]))
	return "%s|%d|%s" % [SunReportScript.site_words(_site), _moments.size(), "+".join(texts)]


## One line per day the study covers: the day's sunrise, sunset and length of light.
func day_lines() -> Array[String]:
	if not has_site():
		return [] as Array[String]
	return SunReportScript.day_texts(_site, _moments)


# --- what the page says ----------------------------------------------------------------


func report_summary() -> String:
	return _summary


## The guidance: what the page is waiting for, or what the study in hand is.
##
## The status line is a different thing and is written only by `say`: the status is what the page
## last *did*, and this is what it is asking for. Conflating them makes the status go stale the
## moment the study changes.
func hint() -> String:
	if not has_site():
		return NO_SITE
	if _moments.is_empty():
		return NO_MOMENTS
	if not apply_enabled():
		return NO_CHOICE if selected_index() < 0 else NO_SUN
	return SunReportScript.describe(_site, _moments, _height_m, _units)


## What the page says about itself when it opens: the study in hand, or what is missing.
func opening_words() -> String:
	return hint()


func say(text: String) -> void:
	_status = text
	if _status_label != null:
		_status_label.text = text


func said() -> String:
	return _status


func status_text() -> String:
	return _status


func apply_enabled() -> bool:
	return _apply_button != null and not _apply_button.disabled


func render_enabled() -> bool:
	return _render_button != null and not _render_button.disabled


## True when nothing in the page can take the drawing's keyboard except the number fields, which
## are the one kind of control that may hold it.
func rows_are_keyboard_free() -> bool:
	return _rows_list != null and _rows_list.focus_mode == Control.FOCUS_NONE


func lists_are_keyboard_free() -> bool:
	return (
		rows_are_keyboard_free()
		and _moments_list != null
		and _moments_list.focus_mode == Control.FOCUS_NONE
	)


func request_close() -> void:
	hide()
	closed.emit()


# --- the refresh, and what the buttons ask for -----------------------------------------


## Re-read the study in hand and put it on the page. Touches the guidance and never the status.
func _refresh() -> void:
	if not _built:
		return
	_site_line.text = (
		"Site: %s" % SunReportScript.site_words(_site) if has_site() else "Site: none yet"
	)
	_height_label.text = "Casting height"
	if _height_box != null:
		_height_box.suffix = _unit_suffix()
	_moments_label.text = "The moments to study \u2014 %d" % _moments.size()
	var texts: Array[String] = moment_texts()
	var chosen: int = selected_index()
	_moments_list.clear()
	for text: String in texts:
		_moments_list.add_item(text)
	if chosen >= 0 and chosen < texts.size():
		_moments_list.select(chosen)
	var built: Array = study_rows()
	show_rows(built)
	var lines: Array[String] = day_lines()
	_days_label.text = "\n".join(PackedStringArray(lines))
	_rows_label.text = "What the study says \u2014 %d rows" % built.size()
	_summary = (
		SunReportScript.summary(_site, _moments, _height_m, _units) if has_site() else ""
	)
	_summary_label.text = _summary
	# The buttons first, because the guidance is written from whether they are live - and a hint
	# computed from the previous refresh's button states is a hint that is one edit behind.
	_refresh_buttons()
	_hint_label.text = hint()


func _refresh_buttons() -> void:
	if _apply_button == null or _render_button == null:
		return
	# The same question asked twice: the button is dead when the page cannot do it, and the hint
	# above says which fact is missing - which a disabled button cannot say for itself.
	var chosen: Dictionary = selected_moment()
	var sun_up: bool = (
		not chosen.is_empty()
		and bool(SunStudyScript.position_for(_site, chosen)["is_up"])
	)
	_apply_button.disabled = not sun_up
	_render_button.disabled = _moments.is_empty()


func _on_height_changed(shown: float) -> void:
	_height_m = _metres_from(shown)
	_refresh()


func _on_add_pressed() -> void:
	if add_moment_from_fields():
		say("added %s" % SunReportScript.moment_words(_moments[_moments.size() - 1]))
		return
	say("that moment is already on the list")


func _on_remove_pressed() -> void:
	var at: int = selected_index()
	if not remove_selected():
		say("choose a moment to take off the list")
		return
	say("took moment %d off the list" % (at + 1))


func _on_preset_pressed(preset_name: StringName) -> void:
	if use_preset(preset_name):
		say("the study is %s" % SunReportScript.preset_name(preset_name))


func _on_moment_selected(index: int) -> void:
	if not choose_moment(index):
		return
	say("moment %d: %s" % [index + 1, SunReportScript.moment_words(_moments[index])])


func _on_apply_pressed() -> void:
	var chosen: Dictionary = selected_moment()
	if chosen.is_empty() or not apply_enabled():
		say(hint())
		return
	apply_requested.emit(chosen)


func _on_render_pressed() -> void:
	if not render_enabled():
		say(hint())
		return
	render_requested.emit(renderable_moments())


func _on_close_requested() -> void:
	request_close()