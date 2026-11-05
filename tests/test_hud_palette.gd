extends Node
## The command palette as the program reaches it: the Help menu's way in, the rows the HUD builds out
## of the bar, and the one door a command runs through whether it was chosen from a menu or typed for
## in the box.
##
## The palette is never popped up here. `popup_centered` needs a window server and a test process has
## not got one, so the filling is driven separately from the showing - which is why the HUD keeps them
## apart in the first place. Being shown is the window's own `visible` flag, exactly as the other page
## tests have it.

const HudScript := preload("res://scripts/hud.gd")


## The kinds that are not commands: a separator does nothing, an "info" line is a sentence, and a
## submenu heading is the name of a set of commands rather than one of them.
const NOT_COMMANDS: Array[StringName] = [&"separator", &"info", &"submenu"]


func _hud() -> HudScript:
	var hud: HudScript = HudScript.new()
	hud._build_command_palette()
	return hud


## The bar's own entries that are commands, in the bar's own order. Worked out here rather than asked
## of the HUD, so that a HUD which dropped one of them would fail rather than agree with itself.
func _runnable() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in HudScript.menu_entries():
		if NOT_COMMANDS.has(StringName(entry.get("kind", &""))):
			continue
		out.append(entry)
	return out


func _row_for(hud: HudScript, id: String) -> Dictionary:
	for row: Dictionary in hud.command_rows():
		if String(row.get("id", "")) == id:
			return row
	assert(false, "the palette has no row for %s" % id)
	return {}


## The row for a command, read out of a HUD that is then freed. A row holds nothing but strings, the
## id, and the entry it stands for, so it outlives the HUD it was read from - and a HUD left unfreed
## is a resource still in use at the end of the run, which fails the verdict.
func _row_of(id: String) -> Dictionary:
	var hud: HudScript = _hud()
	var row: Dictionary = _row_for(hud, id)
	hud.free()
	return row


# --- the way in -------------------------------------------------------------------------------


func test_the_help_menu_offers_the_palette_above_the_manual_and_the_keys() -> void:
	var ids: Array[String] = []
	for entry: Dictionary in HudScript.items_for("Help"):
		ids.append(String(entry.get("id", "")))
	var expected: Array[String] = ["help.palette", "help.manual", "help.keys", "help.this_page"]
	assert(ids == expected, "the palette is the first thing the help menu offers")


func test_the_palette_reaches_nothing_in_the_scene_it_is_opened_from() -> void:
	var entry: Dictionary = _row_of("help.palette")["entry"]
	assert(StringName(entry.get("kind", &"")) == &"command", "it is a command rather than a toggle")
	assert(
		String(entry.get("method", "")) == "_menu_command_palette",
		"and it runs the handler that opens the box"
	)
	assert(
		StringName(entry.get("needs", &"")) == HudScript.NEEDS_NOTHING,
		"a box that lists the whole bar needs nothing of the scene it is opened in"
	)


func test_the_palette_advertises_the_key_that_opens_it() -> void:
	var entry: Dictionary = _row_of("help.palette")["entry"]
	assert(String(entry.get("action", "")) == "command_palette", "the entry stands for its own key")
	assert(
		HudScript._key_label(&"command_palette") == "Ctrl+P",
		"and the key it advertises is the one it is bound to"
	)
	assert(
		HudScript.menu_label(entry).contains("Ctrl+P"),
		"which is what the menu entry itself says"
	)


# --- the rows out of the bar ------------------------------------------------------------------


func test_every_command_the_bar_holds_is_a_row_the_palette_offers() -> void:
	var hud: HudScript = _hud()
	var rows: Array[Dictionary] = hud.command_rows()
	var wanted: Array[Dictionary] = _runnable()
	assert(
		rows.size() == wanted.size(),
		"the box offers %d rows for %d commands" % [rows.size(), wanted.size()]
	)
	for index in wanted.size():
		assert(
			String(rows[index].get("id", "")) == String(wanted[index].get("id", "")),
			"in the bar's own order, so the same search gives the same list"
		)
	hud.free()


func test_the_box_leaves_out_the_punctuation_and_the_submenu_headings() -> void:
	var hud: HudScript = _hud()
	var ids: Array[String] = []
	for row: Dictionary in hud.command_rows():
		ids.append(String(row.get("id", "")))
	assert(not ids.has(""), "a separator is not a command")
	assert(not ids.has("file.info"), "and a line that says something is not one either")
	assert(not ids.has("file.sheet"), "nor is the heading of a set")
	hud.free()


func test_the_commands_inside_a_submenu_are_offered_too() -> void:
	var hud: HudScript = _hud()
	var ids: Array[String] = []
	for row: Dictionary in hud.command_rows():
		ids.append(String(row.get("id", "")))
	assert(ids.has("file.sheet.A3"), "a command a submenu holds is a command")
	assert(ids.size() > HudScript.items_for("File").size(), "so the box reaches more than File's first level")
	hud.free()


func test_a_row_carries_the_entry_it_stands_for_so_it_runs_what_the_menu_runs() -> void:
	var hud: HudScript = _hud()
	for row: Dictionary in hud.command_rows():
		var entry: Dictionary = row["entry"]
		assert(String(row["id"]) == String(entry.get("id", "")), "the row is that entry")
		assert(
			StringName(row["method"]) == StringName(entry.get("method", &"")),
			"%s runs what its menu entry runs" % String(row["id"])
		)
	hud.free()


func test_every_row_names_a_method_this_hud_has() -> void:
	# A row naming a method that is not here is a command that looks like it works.
	var hud: HudScript = _hud()
	for row: Dictionary in hud.command_rows():
		assert(
			hud.has_method(String(row["method"])),
			"%s names %s, which is not a method of the HUD" % [String(row["id"]), String(row["method"])]
		)
	hud.free()


func test_a_row_says_the_label_the_key_and_the_menu_the_bar_shows() -> void:
	var hud: HudScript = _hud()
	var row: Dictionary = _row_for(hud, "edit.undo")
	assert(String(row["label"]) == "Undo", "the row is labelled the way the menu entry is")
	assert(String(row["key"]) == HudScript._key_label(&"draft_undo"), "and advertises the same key")
	assert(String(row["menu"]) == "Edit", "and says which menu it came from")
	hud.free()


# --- whether a row can run here ---------------------------------------------------------------


func test_a_command_that_needs_a_drawing_says_so_in_a_scene_with_none() -> void:
	var hud: HudScript = _hud()
	var row: Dictionary = _row_for(hud, "file.plot")
	assert(row["available"] == false, "there is nothing here to plot")
	assert(String(row["why"]) == "there is no drawing open", "and the row says what is missing by name")
	assert(String(row["why"]) == HudScript.needs_words(HudScript.NEEDS_DRAFT), "in the one set of words")
	hud.free()


func test_a_command_that_needs_a_session_says_that_instead_of_anything_else() -> void:
	var hud: HudScript = _hud()
	var row: Dictionary = _row_for(hud, "team.leave")
	assert(row["available"] == false, "there is no session to leave")
	assert(String(row["why"]) == "there is no shared session", "and it is the session that is missing")
	hud.free()


func test_a_command_that_is_only_sometimes_available_says_which_fact_is_missing() -> void:
	# Worked out from the row's own entry rather than from a scene, because this is the half that is
	# easy to get wrong: the need and the state are two different questions.
	var entry: Dictionary = _row_of("file.save")["entry"]
	var row: Dictionary = HudScript.command_row(entry, true, false)
	assert(row["available"] == false, "nothing has changed, so there is nothing to save")
	assert(String(row["why"]) == "nothing has changed since it was saved", "and the row says why")
	assert(row["available"] == (String(row["why"]) == ""), "a row's availability and its reason are one fact")


func test_an_available_row_gives_no_reason_at_all() -> void:
	var entry: Dictionary = _row_of("help.manual")["entry"]
	var row: Dictionary = HudScript.command_row(entry, true, true)
	assert(row["available"], "a command that can run here")
	assert(String(row["why"]) == "", "has nothing to explain")


# --- the one door -----------------------------------------------------------------------------


func test_running_an_entry_runs_the_method_it_names() -> void:
	var hud: HudScript = _hud()
	# A method this HUD really has, and an entry shaped the way the bar shapes them. Nothing is
	# observable about `_menu_undo` in a scene with no drawing, so what is being checked is the door
	# itself: it takes the method out of the entry and calls it.
	assert(hud.run_entry({"method": &"_menu_undo"}) == true, "an entry naming a method that is here runs")
	assert(hud.run_entry({"method": &"_menu_nope"}) == false, "and one naming nothing that is here does not")
	assert(hud.run_entry({}) == false, "an entry naming no method at all does not either")
	hud.free()


func test_choosing_a_row_from_the_box_runs_it_through_the_same_door() -> void:
	var hud: HudScript = _hud()
	hud._fill_command_palette()
	assert(
		hud._command_palette.chosen.is_connected(hud._on_command_chosen),
		"the box's own signal is what tells the HUD a command was chosen"
	)
	var ran: Array[String] = []
	hud._command_palette.chosen.connect(
		func(row: Dictionary) -> void: ran.append(String(row.get("id", "")))
	)
	assert(hud._command_palette.run_command("edit.undo"), "the row was chosen in the box")
	assert(ran.size() == 1, "and the box announced it once")
	assert(String(ran[0]) == "edit.undo", "carrying the row that was chosen")
	assert(not hud.is_command_palette_open(), "and the box took itself off the screen")
	hud.free()


# --- showing it -------------------------------------------------------------------------------


func test_the_box_the_hud_builds_is_built_hidden_and_inside_the_hud() -> void:
	var hud: HudScript = _hud()
	assert(hud._command_palette != null, "the HUD has a box")
	assert(hud._command_palette.get_parent() == hud, "parented to the HUD, not to the focus-free Root")
	assert(not hud.is_command_palette_open(), "and it is not on the screen until it is opened")
	hud.free()


func test_the_box_is_open_exactly_while_it_is_visible() -> void:
	var hud: HudScript = _hud()
	hud._command_palette.visible = true
	assert(hud.is_command_palette_open(), "a box on the screen is open")
	hud.close_command_palette()
	assert(not hud.is_command_palette_open(), "and closing it takes it off the screen")
	hud.free()


func test_filling_the_box_hands_over_the_bar_without_showing_it() -> void:
	var hud: HudScript = _hud()
	hud._fill_command_palette()
	assert(
		hud._command_palette.command_count() == _runnable().size(),
		"the box holds every command the bar does"
	)
	assert(not hud.is_command_palette_open(), "and filling it is not the same act as showing it")
	hud.free()


func test_a_hud_with_no_box_at_all_says_nothing_rather_than_failing() -> void:
	var hud: HudScript = HudScript.new()
	assert(not hud.is_command_palette_open(), "there is no box, so nothing is open")
	hud.close_command_palette()
	hud._fill_command_palette()
	# Opening with no box must refuse before it reaches `popup_centered`, which is what makes this safe
	# to call with no window server behind it.
	hud.open_command_palette()
	hud.toggle_command_palette()
	assert(not hud.is_command_palette_open(), "and nothing was opened")
	hud.free()


# --- what was run last ------------------------------------------------------------------------


func test_running_a_command_remembers_it() -> void:
	# `run_entry` is the one door a menu line and a palette row both go through, so this is the only
	# place the remembering could be wrong - and the only place it needs to be right.
	var hud := _hud()
	hud._recent_commands = []
	assert(hud.recent_commands().is_empty(), "nothing has been run yet")
	# Entries shaped the way the bar shapes them, naming methods this HUD has: what is being checked is
	# the door - a command that runs is a command that was remembered.
	assert(hud.run_entry({"id": "edit.undo", "method": &"_menu_undo"}), "a command that is there runs")
	var once: Array[String] = ["edit.undo"]
	assert(hud.recent_commands() == once, "and is remembered by id")
	assert(hud.run_entry({"id": "file.plot", "method": &"_menu_plot"}))
	var twice: Array[String] = ["file.plot", "edit.undo"]
	assert(hud.recent_commands() == twice, "newest first")
	hud.free()


func test_a_command_run_again_moves_to_the_front_rather_than_being_listed_twice() -> void:
	var hud := _hud()
	hud._recent_commands = []
	hud.run_entry({"id": "edit.undo", "method": &"_menu_undo"})
	hud.run_entry({"id": "file.plot", "method": &"_menu_plot"})
	hud.run_entry({"id": "edit.undo", "method": &"_menu_undo"})
	var wanted: Array[String] = ["edit.undo", "file.plot"]
	assert(hud.recent_commands() == wanted, str(hud.recent_commands()))
	hud.free()


func test_a_command_that_is_not_there_is_not_remembered() -> void:
	# A method the HUD has not got is not a command: remembering it would put a row in the box that
	# nothing can run.
	var hud := _hud()
	hud._recent_commands = []
	assert(not hud.run_entry({"id": "nothing.at.all", "method": &"_menu_nothing_at_all"}))
	assert(not hud.run_entry({"id": "nothing.at.all", "method": &""}))
	assert(hud.recent_commands().is_empty(), "nothing was run, so nothing was remembered")
	hud.free()


func test_only_the_last_few_are_kept() -> void:
	# It is a way back to what you just did, not a history: a list that grew would push the whole bar
	# down for the sake of commands nobody is coming back to.
	var hud := _hud()
	hud._recent_commands = []
	for index in HudScript.RECENT_COMMANDS + 4:
		hud._remember_command("command-%d" % index)
	assert(hud.recent_commands().size() == HudScript.RECENT_COMMANDS, str(hud.recent_commands().size()))
	assert(hud.recent_commands()[0] == "command-11", "the newest is at the front")
	assert(hud.recent_commands().has("command-4"), "and the last kept one is still there")
	assert(not hud.recent_commands().has("command-3"), "while the oldest have fallen off")
	hud.free()


func test_the_box_is_handed_them_when_it_is_filled() -> void:
	# The HUD keeps the order and the box is handed it, which is the whole of the join.
	var hud := _hud()
	hud.run_entry(_row_for(hud, "edit.undo"))
	hud._fill_command_palette()
	assert(hud._command_palette.shown_id(0) == "edit.undo", "the box offers it first")
	hud.free()