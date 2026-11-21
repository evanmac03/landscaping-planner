extends Node
## The bar's own table, held to the rules that make it a table rather than a list of menus: every menu it
## declares can be asked for by name and answers with its own items, the flattener reaches what is inside a
## submenu, and the plan is the same plan every time it is asked for.
##
## The deeper rules - that no two entries share an id, that every entry names a method that really exists,
## that the Draft menu holds every tool the legend holds - are held by the tests for the parts of the
## program those entries open, because that is where a menu entry can actually be wrong. Nothing here needs
## a scene: the table is static data, which is the whole reason it could leave the HUD.

const PlanScript := preload("res://scripts/menu_bar_plan.gd")


func test_every_menu_it_declares_can_be_asked_for_by_name() -> void:
	var plan: Array[Dictionary] = PlanScript.menu_plan()
	assert(plan.size() > 0, "the bar has menus")
	for menu: Dictionary in plan:
		var title: String = String(menu["title"])
		var own: Array = menu["items"]
		var asked: Array[Dictionary] = PlanScript.items_for(title)
		assert(not asked.is_empty(), "%s answers with its items" % title)
		assert(asked.size() == own.size(), "%s answers with its own items, not another menu's" % title)


func test_a_title_the_bar_does_not_have_is_answered_with_nothing() -> void:
	# Not with the first menu, and not with an error: the palette asks this by name for every row it is
	# about to run, so a wrong answer here would run a command the person did not pick.
	assert(PlanScript.items_for("Nothing of the kind").is_empty(), "an unknown title is not the first menu")
	assert(PlanScript.items_for("").is_empty(), "and neither is no title at all")


## **The bar's line about its own fold, round-tripped.** `Hud` writes it and `tools/phone_touch_pass.gd` reads it
## back, and both go through this file, so the writer and the reader cannot come apart: what is written here is
## what is read here, and a change to either is a change to both.
##
## It is the reading a fold is judged by, and the only one that is. Both numbers in it are the bar's own - the room
## it was given and what it needs - where the probe's `row` line puts the room the *menus* were given beside the
## whole *row*'s minimum. That mismatch was read as a bar overflowing its room twice.
func test_the_bar_s_line_about_its_fold_is_read_back_as_it_was_written() -> void:
	# The A16W held upright, at the moment the fold had finished: two titles, 272 px of bar, a 349 px room.
	var said: String = PlanScript.menubar_line(349.0, 272.0, 1129.0, 1185.0, 2)
	assert(said.begins_with(PlanScript.MENUBAR_MARK), "it begins with the bar's own word: %s" % said)
	var read: Dictionary = PlanScript.read_menubar_line(said)
	assert(not read.is_empty(), "and reads back as a reading rather than as nothing")
	assert(read["room"] == 349.0, "the room it was given: %s" % str(read["room"]))
	assert(read["bar_min"] == 272.0, "what it needed: %s" % str(read["bar_min"]))
	# The line carries whole pixels, which is all a fold is decided in.
	assert(read["row"] == 1129.0, "the row it sits in: %s" % str(read["row"]))
	assert(read["shown"] == 1185.0, "the screen it is on: %s" % str(read["shown"]))
	assert(read["titles"] == 2, "and the titles it is drawing: %s" % str(read["titles"]))
	assert(read["line"] == said, "and it hands the bar's own words straight back")
	# A logcat line carries that behind the time, the pid and the tag, which is how the tool meets it.
	var from_logcat: String = "11-13 17:08:32.906 26110 26217 I godot   : " + said
	assert(PlanScript.read_menubar_line(from_logcat)["bar_min"] == 272.0, "a logcat line is a reading too")
	# A bar that said nothing, and a line that is not whole, are both answered with nothing - rather than with a
	# zero a caller could read as a bar that needs no room at all.
	assert(PlanScript.read_menubar_line("").is_empty(), "no line, no reading")
	assert(PlanScript.read_menubar_line("MENUBAR room=1 bar_min=2").is_empty(), "half a line is not a reading")
	assert(PlanScript.read_menubar_line("nothing of the kind").is_empty(), "and neither is another line")


## Whether the bar had finished folding is its own two numbers against each other: what it needs against what it
## was given. A bar still folding is worth naming as such, because a reading taken mid-fold is not a fault in the
## bar - measured, one caught the bar asking for 1052 px of a 349 px room while the fold went on to 272 px and fitted.
func test_a_bar_that_needs_more_than_it_was_given_had_not_finished_folding() -> void:
	var settled: Dictionary = PlanScript.read_menubar_line(PlanScript.menubar_line(349.0, 272.0, 1129.0, 1185.0, 2))
	var folding: Dictionary = PlanScript.read_menubar_line(PlanScript.menubar_line(349.0, 1052.0, 1129.0, 1185.0, 10))
	assert(PlanScript.bar_had_finished(settled), "272 px of bar in a 349 px room is a bar that fits")
	assert(not PlanScript.bar_had_finished(folding), "1052 px of bar in a 349 px room is one still folding")
	# Nothing said is neither a bar that fits nor a bar that does not: it is a thing said in words, because a
	# caller reading it has no numbers to weigh and must not be handed a zero that looks like one.
	assert(not PlanScript.bar_had_finished({ }), "a bar that said nothing has not been shown to fit")
	assert(
		PlanScript.bar_words({ }).contains("said nothing"),
		"and it is told that, rather than shown a zero: %s" % PlanScript.bar_words({ }),
	)
	assert(
		PlanScript.bar_words(settled).contains("had finished folding"),
		"a fitting bar is said to have finished: %s" % PlanScript.bar_words(settled),
	)
	assert(
		PlanScript.bar_words(folding).contains("still folding"),
		"and one that does not fit is named as still folding: %s" % PlanScript.bar_words(folding),
	)


func test_the_flattener_reaches_what_is_inside_a_submenu() -> void:
	# A submenu is a heading rather than a command, so the entries underneath it are commands a palette
	# could not reach any other way: the plot scales, the reading sizes, the example garden.
	var flat: Array[Dictionary] = PlanScript.menu_entries()
	var top: Array[Dictionary] = PlanScript.file_items()
	assert(flat.size() > top.size(), "the whole bar is more than one menu's own list")
	assert(flat.size() > top.size(), "and it is the submenus that make the difference")


func test_the_plan_is_the_same_plan_every_time_it_is_asked_for() -> void:
	# Read fresh on every ask rather than kept, so a plan that drifted between two calls would be a plan
	# with state behind it. Nothing in this table holds any.
	assert(str(PlanScript.menu_plan()) == str(PlanScript.menu_plan()), "two asks are one plan")


func test_every_kind_of_entry_the_bar_can_hold_is_one_the_table_builds() -> void:
	# The vocabulary is the table's own, and a reader of the plan asks an entry what kind it is before
	# asking what it stands for, so every kind here has to be one the drawing code knows how to draw.
	var known: Array[StringName] = [&"command", &"radio", &"check", &"submenu", &"separator", &"info"]
	for entry: Dictionary in PlanScript.menu_entries():
		var kind: StringName = StringName(entry.get("kind", &"command"))
		assert(known.has(kind), "every entry is a kind the bar draws: %s" % str(kind))
