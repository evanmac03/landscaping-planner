extends Node
## The command palette as the screen: a box with a field to type into, the rows it was handed in a
## list, and one rule that runs them.
##
## The box is built by hand here rather than popped up, because `popup_centered` needs a window server
## and a test process has not got one. Being shown is what the window's own `visible` flag means, and
## every test makes its own box and frees it - an unfreed Node is a resource still in use at the end
## of the run, which fails the verdict.
##
## The palette is handed its rows rather than reading them out of a menu bar, so these are the tests
## of the box itself: what it says about a row, what a search does to the order, and what choosing a
## command that cannot run here does. Whether the rows come from the bar is the HUD's test.

const PaletteScript := preload("res://scripts/command_palette.gd")


## One row in the shape the HUD hands them over. The method is not one this test has: the box never
## calls it, it only carries it, which is exactly the boundary these tests are about.
func _row(
	id: String, label: String, key: String, menu: String, available: bool, why: String
) -> Dictionary:
	return {
		"id": id,
		"label": label,
		"key": key,
		"menu": menu,
		"method": &"_menu_thing",
		"entry": {"id": id, "kind": &"command", "label": label, "method": &"_menu_thing"},
		"available": available,
		"why": why,
	}


func _rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	rows.append(_row("edit.undo", "Undo", "Ctrl+Z", "Edit", true, ""))
	rows.append(_row("edit.redo", "Redo", "Ctrl+Y", "Edit", true, ""))
	rows.append(_row("file.save", "Save", "Ctrl+S", "File", false, "nothing has changed since it was saved"))
	rows.append(_row("file.plot", "Plot a sheet...", "P", "File", false, "there is no drawing open"))
	rows.append(_row("file.sheet.A3", "A3", "", "File > Sheet size", true, ""))
	rows.append(_row("help.manual", "Landscaping Planner help...", "", "Help", true, ""))
	return rows


func _window(rows: Array[Dictionary]) -> PaletteScript:
	var box: PaletteScript = PaletteScript.new()
	box.build()
	box.set_commands(rows)
	return box


# --- building and the shape of the box ---------------------------------------------------------


func test_the_box_is_built_once_however_many_times_it_is_asked_for() -> void:
	var box: PaletteScript = _window(_rows())
	var controls: int = box.get_child_count()
	box.build()
	box.set_commands(_rows())
	assert(box.get_child_count() == controls, "building again is the same box, not a second set of rows")
	box.free()


func test_the_box_has_the_controls_a_box_like_this_has() -> void:
	var box: PaletteScript = _window(_rows())
	assert(box.commands_list() != null, "a list of commands")
	assert(box.search_field() != null, "a field to type into")
	assert(box.search_field().placeholder_text != "", "with something in it to say what it is for")
	assert(box.command_count() == 6, "and every row it was handed")
	assert(box.shown_count() == 6, "of which the empty search shows all of them")
	box.free()


func test_nothing_in_the_list_takes_the_keyboard_from_the_field() -> void:
	var box: PaletteScript = _window(_rows())
	assert(
		box.commands_list().focus_mode == Control.FOCUS_NONE,
		"the list is picked from, not typed into, so it never holds the keys"
	)
	# The field is the one control in here that is *meant* to hold them.
	assert(
		box.search_field().focus_mode != Control.FOCUS_NONE,
		"and the field is the one thing in the box that does"
	)
	box.free()


func test_a_box_handed_no_commands_says_so_rather_than_showing_a_blank_frame() -> void:
	var box: PaletteScript = _window([] as Array[Dictionary])
	assert(box.command_count() == 0, "it holds nothing")
	assert(box.shown_count() == 0, "and shows nothing")
	assert(box.said() != "", "but it says something rather than leaving two empty labels")
	assert(box.run_selected() == false, "and there is nothing for Enter to run")
	box.free()


# --- what a row says --------------------------------------------------------------------------


func test_a_row_says_what_the_command_is_called_the_key_and_the_menu_it_is_under() -> void:
	var box: PaletteScript = _window(_rows())
	var texts: Array[String] = box.list_texts()
	assert(texts[0] == "Undo    Ctrl+Z    Edit", "the label, the key that also does it, and its menu")
	assert(
		texts[4] == "A3    File > Sheet size",
		"a command with no key of its own leaves the key out rather than leaving a gap"
	)
	box.free()


func test_a_command_that_cannot_run_here_says_what_is_missing_in_place_of_its_menu() -> void:
	var box: PaletteScript = _window(_rows())
	var texts: Array[String] = box.list_texts()
	assert(
		texts[2] == "Save    -    nothing has changed since it was saved",
		"the reason is the fact worth having in front of you before you press it"
	)
	assert(texts[3] == "Plot a sheet...    -    there is no drawing open", "and it is the real reason")
	box.free()


func test_moving_the_cursor_puts_the_rows_own_state_on_the_status_line() -> void:
	var box: PaletteScript = _window(_rows())
	assert(box.shown_id(0) == "edit.undo", "the box opens on the first command")
	assert(box.said().contains("6 commands"), "and the line says how much of the bar is showing")
	assert(box.said().contains("Enter"), "and what the key that runs one does")
	box.select(1)
	assert(box.shown_id(1) == "edit.redo", "choosing a row says what Enter would run")
	assert(box.said().contains("Redo"), "naming the command itself")
	box.select(2)
	assert(box.shown_id(2) == "file.save", "and choosing the row that cannot run says which one it is")
	assert(box.said().contains("nothing has changed since it was saved"), "and why it cannot run")
	box.free()


# --- the search -------------------------------------------------------------------------------


func test_a_search_finds_a_command_by_a_word_in_its_name() -> void:
	var box: PaletteScript = _window(_rows())
	box.type_search("undo")
	var ids: Array[String] = []
	for index in box.shown_count():
		ids.append(box.shown_id(index))
	assert(ids == ["edit.undo"], "one command is called that")
	box.free()


func test_a_search_puts_the_command_whose_name_starts_with_the_word_first() -> void:
	var box: PaletteScript = _window(_rows())
	# "re" starts "Redo" and is inside nothing else's name, but it is inside two menu paths once the
	# rows whose names do not match are the only ones left.
	box.type_search("re")
	assert(box.shown_id(0) == "edit.redo", "a name that begins with the word outranks anything else")
	box.free()


func test_a_search_finds_a_command_by_the_menu_it_lives_under() -> void:
	var box: PaletteScript = _window(_rows())
	box.type_search("help")
	var ids: Array[String] = []
	for index in box.shown_count():
		ids.append(box.shown_id(index))
	assert(ids == ["help.manual"], "the command is found by the menu it is filed under")
	box.free()


func test_the_same_search_gives_the_same_list_every_time() -> void:
	var box: PaletteScript = _window(_rows())
	box.type_search("e")
	var first: Array[String] = box.list_texts()
	box.type_search("")
	box.type_search("e")
	assert(box.list_texts() == first, "ties keep the bar's own order, so the list does not shuffle")
	box.free()


func test_a_search_that_finds_nothing_says_so_rather_than_showing_a_near_miss() -> void:
	var box: PaletteScript = _window(_rows())
	box.type_search("zzz")
	assert(box.shown_count() == 0, "nothing matches")
	assert(box.said().contains("zzz"), "and the line names the word that found nothing")
	assert(
		box.said().contains("Clear the box"),
		"and says how to get back to the whole bar, because that is the way back"
	)
	box.free()


func test_clearing_the_box_brings_the_whole_bar_back() -> void:
	var box: PaletteScript = _window(_rows())
	box.type_search("undo")
	assert(box.shown_count() == 1, "the search narrowed it")
	box.type_search("")
	assert(box.shown_count() == 6, "and emptying the box is the way back without rebuilding anything")
	assert(box.said().contains("6 commands"), "and the line says how much of the bar is showing")
	box.free()


func test_moving_the_cursor_with_the_arrows_wraps_round_the_list() -> void:
	var box: PaletteScript = _window(_rows())
	box.commands_list().select(5)
	box._move_selection(1)
	assert(box.shown_id(box.commands_list().get_selected_items()[0]) == "edit.undo", "down from the last is the first")
	box._move_selection(-1)
	assert(
		box.shown_id(box.commands_list().get_selected_items()[0]) == "help.manual",
		"and up from the first is the last"
	)
	box.free()


# --- what it does -----------------------------------------------------------------------------


func test_choosing_a_command_carries_the_whole_row_out_and_closes_the_box() -> void:
	var box: PaletteScript = _window(_rows())
	var carried: Array[Dictionary] = []
	box.chosen.connect(func(row: Dictionary) -> void: carried.append(row))
	box.select_command("edit.redo")
	assert(box.run_selected(), "the row was chosen and run")
	assert(carried.size() == 1, "and the box announced it once")
	assert(String(carried[0]["id"]) == "edit.redo", "carrying the row rather than just its name")
	assert(
		StringName(carried[0]["method"]) == &"_menu_thing",
		"including the method that runs it, which is the box's whole contract with the HUD"
	)
	assert(not box.visible, "and the box is off the screen once a command has been run")
	box.free()


func test_a_command_that_cannot_run_here_is_refused_by_name_and_the_box_stays_open() -> void:
	var box: PaletteScript = _window(_rows())
	var carried: Array[Dictionary] = []
	box.chosen.connect(func(row: Dictionary) -> void: carried.append(row))
	box.select_command("file.save")
	assert(box.shown_is_available(box.commands_list().get_selected_items()[0]) == false, "it cannot run here")
	assert(box.run_selected(), "the row was chosen")
	assert(carried.is_empty(), "and nothing was run")
	assert(box.visible, "the box stays open: the command beside this one is probably the one wanted")
	assert(box.said().contains("nothing has changed since it was saved"), "and the line says why")
	box.free()


func test_a_command_nobody_has_is_refused_rather_than_run() -> void:
	var box: PaletteScript = _window(_rows())
	var carried: Array[Dictionary] = []
	box.chosen.connect(func(row: Dictionary) -> void: carried.append(row))
	assert(box.run_command("edit.nope") == false, "there is no such command")
	assert(carried.is_empty(), "so nothing ran")
	assert(box.said().contains("edit.nope"), "and the line names what was asked for")
	box.free()


func test_closing_the_box_says_so_once_however_it_was_closed() -> void:
	var box: PaletteScript = _window(_rows())
	var said: Array[bool] = []
	box.closed.connect(func() -> void: said.append(true))
	box.close_palette()
	assert(said.size() == 1, "closing it says so once")
	box.close_palette()
	assert(said.size() == 1, "and closing a box that is already closed does not say it again")
	box.free()


# --- the search rule on its own ---------------------------------------------------------------


func test_the_search_rule_reads_a_row_by_its_name_before_its_menu() -> void:
	var rows: Array[Dictionary] = [
		_row("a", "something else", "", "Undo", true, ""),
		_row("b", "Undo", "", "Edit", true, ""),
	]
	var found: Array[int] = PaletteScript.find_in(rows, "undo")
	assert(found == [1, 0], "the command named Undo comes before the one merely filed under it")
	assert(
		PaletteScript.find_in(rows, "  undo  ").size() == 2,
		"and the word is trimmed before it is looked for"
	)
	assert(PaletteScript.find_in(rows, "UNDO").size() == 2, "and the search is not case sensitive")
	assert(PaletteScript.find_in(rows, "").size() == 2, "an empty search is the whole list")
	assert(PaletteScript.find_in(rows, "zzz").is_empty(), "and a word nobody has finds nothing at all")


# --- what was run last ------------------------------------------------------------------------


func test_the_commands_run_last_come_first_when_nothing_is_being_searched() -> void:
	var box: PaletteScript = PaletteScript.new()
	box.set_commands(_rows())
	assert(box.shown_id(0) == "edit.undo", "the bar's own order to begin with")
	box.set_recents(["file.plot", "edit.redo"])
	assert(box.shown_id(0) == "file.plot", "then the one run most recently")
	assert(box.shown_id(1) == "edit.redo", "then the one before it")
	assert(box.shown_id(2) == "edit.undo", "and the rest keep the bar's order")
	# The bar is not reordered, only the list: a command that cannot run here still says so where it is.
	assert(box.list_texts()[0].contains("no drawing open") or box.list_texts()[0].contains("Plot"),
		box.list_texts()[0])
	box.free()


func test_a_word_puts_the_order_back() -> void:
	# A search is a question about names, and where a command was run last is not part of the answer.
	var box: PaletteScript = PaletteScript.new()
	box.set_commands(_rows())
	box.set_recents(["file.plot"])
	box.type_search("undo")
	assert(box.shown_count() == 1 and box.shown_id(0) == "edit.undo", "the search is what decides")
	box.type_search("")
	assert(box.shown_id(0) == "file.plot", "and clearing it brings the recents back")
	box.free()


func test_a_recent_command_that_nobody_has_is_not_a_row() -> void:
	# The HUD is the one that remembers, so the box must not invent a command out of an id it cannot
	# find: a stale id is not a row.
	var box: PaletteScript = PaletteScript.new()
	box.set_commands(_rows())
	box.set_recents(["edit.from-a-drawing-that-is-closed"])
	assert(box.shown_count() == box.command_count(), "every command is still shown")
	assert(box.shown_id(0) == "edit.undo", "in the bar's order")
	box.free()


func test_the_status_line_says_why_the_order_is_what_it_is() -> void:
	var box: PaletteScript = PaletteScript.new()
	box.set_commands(_rows())
	box.set_recents(["file.plot"])
	assert(box.status_text().contains("ran last first"), box.status_text())
	box.set_recents([])
	assert(not box.status_text().contains("ran last"), box.status_text())
	assert(box.status_text().contains("%d commands" % box.command_count()), box.status_text())
	box.free()