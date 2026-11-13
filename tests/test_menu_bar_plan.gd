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
