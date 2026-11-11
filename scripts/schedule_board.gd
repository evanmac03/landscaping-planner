class_name ScheduleBoard
extends Window
## The week's work: a column per day, a block per crew day, and every clash listed rather than fixed
## (spec §7.4).
##
## The board is a `Window` like the pipeline board, the estimate and the ground window, for the same
## two reasons: it has fields to type into, and a `Window` owns its own input, so nothing here can take
## the drawing's keys (spec §9's rule). Buttons are built without a keyboard of their own, like every
## control the shared chrome makes; the typed fields are the only things that keep one, because a field
## is where somebody types. What the *open* board does with the keyboard is decided once, by
## `PageChrome.takes_the_keyboard`.
##
## It shows what `JobDesk` says and holds no arithmetic of its own. The conflicts below the days are
## the board's own rows, in the model's own order, and **nothing here ever moves a block to avoid
## one**: "a scheduler that rearranges a crew's day without being asked is a scheduler nobody trusts
## twice", so the office drags the block and the list changes to match.
##
## ## The one gesture
##
## A block is dragged from one day's column to another's, and the window it sits in travels with it.
## Moving a block's *hours* is done by taking it off and booking it again, because a typed window is
## two fields and a drag is one gesture and the two do not mix on one control.

const DeskScript := preload("res://scripts/biz/job_desk.gd")
const CrewScript := preload("res://scripts/biz/crew.gd")
const ScheduleScript := preload("res://scripts/biz/schedule.gd")

## A block was booked, moved or taken off. The HUD's menu line about the desk is stale.
signal schedule_changed()
## The window was closed by its own close button.
signal closed()

## Wide enough for seven day columns, and no taller than the screen.
const SIZE := Vector2i(1120, 700)
const DAY_WIDTH := 196
## How many blocks a day's column shows before the rest are counted instead. A column is a viewport,
## not a report: the summary line above counts every block, whatever the column is showing.
const DAY_BLOCKS := 8
## How many days across the top. A week, starting at the earliest day the desk has a block on, or at
## today when the board is empty.
const DAYS_SHOWN := 7
const SECONDS_PER_DAY := 86400

var desk: DeskScript = null

var _row: HBoxContainer = null
var _summary: Label = null
var _conflicts: ItemList = null
var _status: Label = null
var _job_option: OptionButton = null
var _crew_option: OptionButton = null
var _role_option: OptionButton = null
var _date_field: LineEdit = null
var _from_field: LineEdit = null
var _to_field: LineEdit = null
var _note_field: LineEdit = null
var _crew_name_field: LineEdit = null
var _book_button: Button = null
var _remove_button: Button = null
## The ids the two pickers are showing, in the order they are shown: a dropdown's index is a position
## and this is what that position means.
var _job_ids: Array[String] = []
var _crew_ids: Array[String] = []
## The block a click last landed on, or -1. What "take it off" acts on.
var _selected_index: int = -1


func _init() -> void:
	title = "The week's work"
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
	if desk == null:
		desk = DeskScript.new()
	var column := PageChrome.column(self, 8)

	_summary = PageChrome.text()
	_summary.name = "Summary"
	column.add_child(_summary)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)

	_row = HBoxContainer.new()
	_row.name = "Board"
	_row.add_theme_constant_override("separation", 6)
	scroll.add_child(_row)

	column.add_child(_build_book_row())
	column.add_child(_build_crew_row())

	var problems := PageChrome.subheading("clashes")
	problems.name = "ConflictsLabel"
	column.add_child(problems)
	_conflicts = ItemList.new()
	_conflicts.name = "Conflicts"
	_conflicts.custom_minimum_size = Vector2(0, 96)
	_conflicts.select_mode = ItemList.SELECT_SINGLE
	column.add_child(_conflicts)

	_status = PageChrome.status()
	column.add_child(_status)
	refresh()


## Booking a crew onto a job: which job, who, when, and for how long.
func _build_book_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "BookRow"
	row.add_theme_constant_override("separation", 6)
	_job_option = OptionButton.new()
	_job_option.name = "JobOption"
	_job_option.custom_minimum_size = Vector2(200, 0)
	_job_option.focus_mode = Control.FOCUS_NONE
	row.add_child(_job_option)
	_crew_option = OptionButton.new()
	_crew_option.name = "CrewOption"
	_crew_option.custom_minimum_size = Vector2(200, 0)
	_crew_option.focus_mode = Control.FOCUS_NONE
	row.add_child(_crew_option)
	_date_field = _field("Date", "2026-07-01", 120)
	row.add_child(_date_field)
	_from_field = _field("From", "8:00", 70)
	row.add_child(_from_field)
	_to_field = _field("To", "16:00", 70)
	row.add_child(_to_field)
	_note_field = _field("Note", "what it is for", 180)
	row.add_child(_note_field)
	_book_button = _button("Book it", "_on_book")
	row.add_child(_book_button)
	_remove_button = _button("Take it off", "_on_remove")
	row.add_child(_remove_button)
	return row


## Putting somebody on the crew in the first place. A crew member is not a user account (§7.1), so
## this is a name and a role and nothing else: nothing here is an account, and nothing here signs in.
func _build_crew_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "CrewRow"
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.name = "CrewLabel"
	label.text = "a person"
	row.add_child(label)
	_crew_name_field = _field("NewCrew", "a new crew member's name", 220)
	row.add_child(_crew_name_field)
	_role_option = OptionButton.new()
	_role_option.name = "RoleOption"
	_role_option.custom_minimum_size = Vector2(160, 0)
	_role_option.focus_mode = Control.FOCUS_NONE
	row.add_child(_role_option)
	var add_button := _button("Put them on the crew", "_on_add_crew")
	add_button.name = "AddCrew"
	row.add_child(add_button)
	return row


func _field(field_name: String, placeholder: String, width: int) -> LineEdit:
	var edit := LineEdit.new()
	edit.name = field_name
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(width, 0)
	return edit


## A button on this board, from the shared chrome and named by the board's own rule: a caption with its
## spaces taken out. `_build_crew_row` renames the one button whose name is not its caption.
func _button(words: String, method: String) -> Button:
	var button := PageChrome.button(words)
	button.name = words.replace(" ", "")
	button.pressed.connect(Callable(self, method))
	return button


# --- showing what is there ---------------------------------------------------------------------


## Point the board at a desk and read it again. A null desk becomes an empty one rather than a board
## with nothing to show.
func bind(job_desk: DeskScript) -> void:
	if _row == null:
		build()
	desk = job_desk if job_desk != null else DeskScript.new()
	_selected_index = -1
	# The line about the old desk is about the old desk: pointing the board at another one starts the
	# board's own line again.
	if _status != null:
		_status.text = ""
	refresh()


func refresh() -> void:
	_fill_pickers()
	_refresh_days()
	if _summary != null:
		_summary.text = summary_text()
	if _conflicts != null:
		_conflicts.clear()
		for words: String in conflict_texts():
			var index: int = _conflicts.add_item(words)
			_conflicts.set_item_disabled(index, true)
	_fill_buttons()
	# A board that opened with nothing to say would be a board a person has to guess at, so the first
	# line is what to do with it - and what to do first when there is nothing on it yet.
	if _status != null and _status.text.is_empty():
		_set_status(_opening_words())
	# The blocks just built are new controls, and the shared show that gave this board its keyboard ran
	# when the board was *opened* - before any of them existed. So a board that is up gives the new ones
	# theirs here. Nothing is done while it is down: the show decides it then, and it decides it once.
	PageChrome.takes_the_keyboard_if_up(self)


## The line the board opens with: what to do, or why there is nothing to do yet.
func _opening_words() -> String:
	if desk == null or desk.block_count() == 0:
		return "Nothing is booked yet: put somebody on the crew, then book a day."
	return "Click a block to pick it up; drag it to another day's column to move it."


## Rebuild every day's column from the desk. Cheap at this size - a column is a handful of buttons -
## and it means the board can never show a block the desk does not have.
func _refresh_days() -> void:
	if _row == null:
		return
	for child in _row.get_children():
		# Freed now, not queue_free'd: a deferred free leaves the old column in the tree, and a test
		# that looked a column up by name would find the stale one with the same name.
		_row.remove_child(child)
		child.free()
	for date in day_titles():
		var box := Day.new()
		box.name = "Day%s" % date
		box.day_date = date
		box.board = self
		box.custom_minimum_size = Vector2(DAY_WIDTH, 0)
		box.add_theme_constant_override("separation", 4)
		_row.add_child(box)
		var header := Label.new()
		header.name = "Header"
		header.text = "%s (%d)" % [date, block_count(date)]
		box.add_child(header)
		var rows: Array[Dictionary] = desk.day_rows(date) if desk != null else []
		var shown := 0
		for entry in rows:
			if shown >= DAY_BLOCKS:
				var more := Label.new()
				more.name = "More"
				more.text = "+%d more" % (rows.size() - shown)
				box.add_child(more)
				break
			box.add_child(_block(entry))
			shown += 1


func _block(entry: Dictionary) -> Block:
	var index := int(entry["index"])
	var button := Block.new()
	button.name = "Block%d" % index
	button.block_index = index
	button.board = self
	button.text = _block_words(entry)
	button.custom_minimum_size = Vector2(DAY_WIDTH - 12, 0)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_on_block_pressed.bind(index))
	return button


func _fill_pickers() -> void:
	var keep_job := selected_job()
	var keep_crew := selected_crew()
	_job_ids.clear()
	_crew_ids.clear()
	if _job_option != null:
		_job_option.clear()
		if desk != null:
			for held in desk.jobs:
				_job_ids.append(held.id)
				_job_option.add_item(desk.job_label(held.id))
		if not keep_job.is_empty():
			choose_job(keep_job)
	if _crew_option != null:
		_crew_option.clear()
		if desk != null:
			for held in desk.crews:
				_crew_ids.append(String(held.id))
				_crew_option.add_item(desk.crew_label(held.id))
		if not keep_crew.is_empty():
			choose_crew(keep_crew)
	if _role_option != null and _role_option.item_count == 0:
		for role in CrewScript.role_list():
			_role_option.add_item(CrewScript.role_name(role))


## A button that cannot do anything says why, which is the rule the plant panel's Place button and the
## estimate's Send button both follow.
func _fill_buttons() -> void:
	# Not `ready`: `ready` is a signal on Node, and a local of that name hides it.
	var can_book: bool = _job_ids.size() > 0 and _crew_ids.size() > 0
	if _book_button != null:
		_book_button.disabled = not can_book
		if _job_ids.is_empty():
			_book_button.tooltip_text = "no job yet: a job is made from an estimate"
		elif _crew_ids.is_empty():
			_book_button.tooltip_text = "nobody is on the crew yet"
		else:
			_book_button.tooltip_text = ""
	if _remove_button != null:
		_remove_button.disabled = _selected_index < 0
		_remove_button.tooltip_text = "click a block first" if _selected_index < 0 else ""


# --- booking, moving, taking off ---------------------------------------------------------------


## Book a crew onto a job. The times are read the way a person types them ("8:00", "16:00") and a time
## that cannot be read is **refused in words** rather than booked at midnight.
## Returns `{ok, reason, index}`.
func book(job_id: String, member_id: StringName, date: String, from_text: String, to_text: String,
		note: String = "") -> Dictionary:
	var starts := parse_clock(from_text)
	var ends := parse_clock(to_text)
	if starts < 0 or ends < 0:
		return {"ok": false, "reason": "the times read like 8:00 and 16:00", "index": -1}
	if desk == null:
		return {"ok": false, "reason": "the board has no desk", "index": -1}
	return desk.book(job_id, member_id, date, starts, ends, note)


## Book what the row is showing: what the button does, split out so a test can drive the same path.
## Returns `{ok, reason, index}`.
func book_selected() -> Dictionary:
	var job_id := selected_job()
	if job_id.is_empty():
		_set_status("There is no job to book: a job is made from an estimate.")
		return {"ok": false, "reason": "there is no job to book", "index": -1}
	var member := selected_crew()
	if member.is_empty():
		_set_status("There is nobody on the crew yet: put somebody on it below.")
		return {"ok": false, "reason": "there is nobody on the crew", "index": -1}
	var result := book(
		job_id, StringName(member),
		_date_field.text if _date_field != null else "",
		_from_field.text if _from_field != null else "",
		_to_field.text if _to_field != null else "",
		_note_field.text if _note_field != null else ""
	)
	if not bool(result["ok"]):
		_set_status("Not booked: %s." % String(result["reason"]))
		return result
	var booked := desk.block_at(int(result["index"]))
	refresh()
	_set_status("Booked %s on %s, %s to %s." % [
		desk.job_label(String(booked["job"])),
		String(booked["date"]),
		clock_words(int(booked["start_minute"])),
		clock_words(int(booked["end_minute"])),
	])
	schedule_changed.emit()
	return result


## Move a block to another day, keeping the window it sits in. This is what a drop calls.
##
## `rebuild` is false when the move is made **from a day column's own drop callback**: the data changes
## at once, but rebuilding the columns would free the column whose callback is running, which is an
## error and not only a puzzle. So the picture is rebuilt on the next frame instead, from the same
## desk - and the board's own reading methods ask the desk, so they answer correctly either way.
func move_block(index: int, date: String, rebuild: bool = true) -> bool:
	if desk == null:
		return false
	var block: Dictionary = desk.block_at(index)
	if block.is_empty():
		return false
	var starts := int(block["start_minute"])
	var ends := int(block["end_minute"])
	if not desk.move_block(index, date, starts, ends):
		return false
	if rebuild:
		refresh()
	else:
		call_deferred("refresh")
	_set_status("Moved to %s, still %s to %s." % [
		date, clock_words(starts), clock_words(ends),
	])
	schedule_changed.emit()
	return true


## Take a block off the board, and off the job's own schedule with it.
func remove_block(index: int) -> bool:
	if desk == null or not desk.unbook(index):
		return false
	_selected_index = -1
	refresh()
	_set_status("Taken off the board.")
	schedule_changed.emit()
	return true


## Put somebody on the crew from the fields, which is what the button does.
func add_crew_from_fields() -> bool:
	var person_name := _crew_name_field.text.strip_edges() if _crew_name_field != null else ""
	if person_name.is_empty():
		_set_status("A crew member needs a name.")
		return false
	var role := &"LABOURER"
	if _role_option != null and _role_option.selected >= 0:
		var roles: Array[StringName] = CrewScript.role_list()
		if _role_option.selected < roles.size():
			role = roles[_role_option.selected]
	var member := CrewScript.new(_new_crew_id(person_name), person_name)
	member.role = role
	if not desk.add_crew(member):
		_set_status("That person is already on the crew.")
		return false
	refresh()
	_set_status("%s is on the crew, as %s." % [person_name, CrewScript.role_name(role)])
	schedule_changed.emit()
	return true


# --- what the board says -------------------------------------------------------------------


## The days across the top: a week, starting at the earliest day the desk has a block on, or at today
## when the board is empty.
##
## A week rather than only the days that already have something on them, because a block can only be
## dragged onto a day that is *there*: a board that shows no column until something is booked on it is
## a board nothing can ever be moved onto.
func day_titles() -> Array[String]:
	var out: Array[String] = []
	var start := int(Time.get_unix_time_from_datetime_string(_week_start() + "T00:00:00"))
	for step in DAYS_SHOWN:
		out.append(Time.get_date_string_from_unix_time(start + step * SECONDS_PER_DAY))
	return out


## The first day of the week the board is showing.
func _week_start() -> String:
	var booked: Array[String] = desk.dates() if desk != null else []
	if not booked.is_empty():
		return booked[0]
	return Time.get_date_string_from_system(true)


## The blocks in one day's column, each as the two lines the button shows.
func block_texts(date: String) -> Array[String]:
	var out: Array[String] = []
	if desk == null:
		return out
	for entry in desk.day_rows(date):
		out.append(_block_words(entry))
	return out


func block_count(date: String) -> int:
	return desk.blocks_on(date).size() if desk != null else 0


## One line: what the desk holds, plus how many days the board is spread over.
func summary_text() -> String:
	if desk == null:
		return "no crews and no jobs yet"
	var days := desk.dates().size()
	if days == 0:
		return desk.describe()
	return "%s, over %d day%s" % [desk.describe(), days, "" if days == 1 else "s"]


## The clashes, in the schedule's own words and its own order.
func conflict_texts() -> Array[String]:
	return desk.conflict_lines() if desk != null else []


func status_text() -> String:
	return _status.text if _status != null else ""


func selected_job() -> String:
	if _job_option == null or _job_option.selected < 0 or _job_option.selected >= _job_ids.size():
		return ""
	return _job_ids[_job_option.selected]


func selected_crew() -> String:
	if _crew_option == null or _crew_option.selected < 0 or _crew_option.selected >= _crew_ids.size():
		return ""
	return _crew_ids[_crew_option.selected]


func selected_block() -> int:
	return _selected_index


func choose_job(job_id: String) -> bool:
	if _job_option == null:
		return false
	var at: int = _job_ids.find(job_id)
	if at < 0:
		return false
	_job_option.select(at)
	return true


func choose_crew(member_id: String) -> bool:
	if _crew_option == null:
		return false
	var at: int = _crew_ids.find(member_id)
	if at < 0:
		return false
	_crew_option.select(at)
	return true


func set_date(date: String) -> void:
	if _date_field != null:
		_date_field.text = date


func set_window(from_text: String, to_text: String) -> void:
	if _from_field != null:
		_from_field.text = from_text
	if _to_field != null:
		_to_field.text = to_text


func set_note(words: String) -> void:
	if _note_field != null:
		_note_field.text = words


func set_crew_fields(person_name: String, role: StringName) -> void:
	if _crew_name_field != null:
		_crew_name_field.text = person_name
	if _role_option != null:
		var roles: Array[StringName] = CrewScript.role_list()
		var at: int = roles.find(role)
		if at >= 0:
			_role_option.select(at)


func book_button_disabled() -> bool:
	return _book_button.disabled if _book_button != null else true


func book_hint() -> String:
	return _book_button.tooltip_text if _book_button != null else ""


func day_texts() -> Array[String]:
	var out: Array[String] = []
	if _row == null:
		return out
	for child in _row.get_children():
		var header := child.get_node_or_null(^"Header")
		if header is Label:
			out.append((header as Label).text)
	return out


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


# --- the small joins ---------------------------------------------------------------------------


## "8:00" as minutes from midnight, or -1 when it cannot be read. Parsed in one place: the block, the
## route and the job all count minutes, and only the board ever sees a colon.
static func parse_clock(text: String) -> int:
	var clean := text.strip_edges()
	var parts := clean.split(":")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return -1
	var hours := int(parts[0])
	var minutes := int(parts[1])
	if hours < 0 or hours > 24 or minutes < 0 or minutes > 59:
		return -1
	return hours * 60 + minutes


## Minutes from midnight as a clock time a person reads: "8:00", "16:30". A whole day is "24:00",
## which is the end of a block that runs to midnight and not a time of day.
static func clock_words(minute: int) -> String:
	if minute < 0 or minute > ScheduleScript.MINUTES_PER_DAY:
		return "?"
	return "%d:%02d" % [floori(float(minute) / 60.0), minute % 60]


func _block_words(entry: Dictionary) -> String:
	return "%s  %s-%s\n%s" % [
		String(entry.get("job_label", "")),
		clock_words(int(entry.get("start_minute", 0))),
		clock_words(int(entry.get("end_minute", 0))),
		String(entry.get("crew_label", "")),
	]


## A name nobody else has: the id a crew member is stored under. A person typed twice is two people
## here, because the board has no way to know they are one - and merging them would lose a day.
func _new_crew_id(person_name: String) -> StringName:
	var slug := person_name.to_lower().replace(" ", "-")
	return StringName("%s-%d" % [slug, int(Time.get_unix_time_from_system())])


func _set_status(words: String) -> void:
	if _status != null:
		_status.text = words


# --- the buttons -----------------------------------------------------------------------------


func _on_book() -> void:
	book_selected()


func _on_remove() -> void:
	if _selected_index < 0:
		_set_status("Click a block first, then take it off.")
		return
	remove_block(_selected_index)


func _on_add_crew() -> void:
	add_crew_from_fields()


func _on_block_pressed(index: int) -> void:
	_selected_index = index
	_fill_buttons()
	if desk == null:
		return
	var block := desk.block_at(index)
	if block.is_empty():
		return
	_set_status("%s on %s, %s to %s, %s." % [
		desk.job_label(String(block["job"])),
		String(block["date"]),
		clock_words(int(block["start_minute"])),
		clock_words(int(block["end_minute"])),
		desk.crew_label(StringName(block["crew"])),
	])


func _on_close_requested() -> void:
	hide()
	closed.emit()


# --- dragging a block to another day -----------------------------------------------------------


## A block: a button you can drag, carrying its index on the desk.
class Block extends Button:
	var block_index: int = -1
	var board: ScheduleBoard = null

	func _get_drag_data(_at: Vector2) -> Variant:
		if board == null or block_index < 0:
			return null
		# A drag preview is attached to the viewport, so it needs a tree; off-tree (a test) the
		# payload is still returned, which is the part the drop reads.
		if is_inside_tree():
			var preview := Label.new()
			preview.text = text
			set_drag_preview(preview)
		return {"block": block_index}


## A day's column: a drop target that knows which date it is.
class Day extends VBoxContainer:
	var day_date: String = ""
	var board: ScheduleBoard = null

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		if board == null or not (data is Dictionary):
			return false
		return (data as Dictionary).has("block")

	func _drop_data(_at: Vector2, data: Variant) -> void:
		if board == null or not (data is Dictionary):
			return
		board.move_block(int((data as Dictionary).get("block", -1)), day_date, false)