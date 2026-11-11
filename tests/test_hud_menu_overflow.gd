extends Node
## The menu bar's overflow rule.
##
## The bar holds fourteen menus and has a measured headroom of a few tens of pixels - the audit's layout
## check prints "TopBar row wants 1540.0 px, panel is 1576.0 px" - so the day one more menu is added, the
## bar has to have an answer rather than a menu hanging off the right-hand edge.
##
## Two things are tested, and they are separate on purpose. The **rule** is `menu_fold_point`, pure
## arithmetic with no scene in it. The **measurement** is the part that has to be true for the rule to
## matter at all: if the titles cannot be measured, every one of them is nothing wide, and a rule applied
## to that would fold the whole bar into one menu. So the measurement is tested for being real - a longer
## title measures wider than a shorter one - and a bar it cannot measure is tested for staying whole.

const Hud := preload("res://scripts/hud.gd")

var _hud: PlannerHud = null
var _bar: MenuBar = null
var _row: HBoxContainer = null


func _free_all() -> void:
	if _row != null:
		_row.free()
		_row = null
		_bar = null
	elif _bar != null:
		_bar.free()
		_bar = null
	if _hud != null:
		_hud.free()
		_hud = null


## A HUD and a bar, with the bar in the tree so it draws its titles on a real font.
func _hud_with_a_bar() -> PlannerHud:
	_hud = Hud.new()
	_bar = MenuBar.new()
	_bar.name = "MenuBar"
	add_child(_bar)
	_hud.menu_bar = _bar
	return _hud


## The same, with the bar inside a row the way the game has it - a container, because the room the bar has
## is worked out from what is left of its row once the row's other children have taken their minimum.
func _hud_with_a_bar_in_a_row() -> PlannerHud:
	_hud = Hud.new()
	_row = HBoxContainer.new()
	_row.name = "Row"
	add_child(_row)
	_bar = MenuBar.new()
	_bar.name = "MenuBar"
	_row.add_child(_bar)
	_hud.menu_bar = _bar
	return _hud


func test_the_bar_can_be_rebuilt_with_its_tail_folded() -> void:
	# The path a person meets by dragging the window smaller, and the one worth testing by hand: it frees
	# the popups and builds new ones, which is where a hanging reference to the recent-drawings menu would
	# live. It is driven directly rather than by shrinking a row, because how a Control resizes in a test
	# is the engine's business and not this rule's.
	var hud: PlannerHud = _hud_with_a_bar_in_a_row()
	hud._build_menu_bar()
	assert(_bar.get_menu_count() == hud.menu_plan().size(),
		"the whole bar to begin with: %d menus" % _bar.get_menu_count())
	hud._rebuild_menu_bar(hud.menu_bar_plan(1.0))
	assert(_bar.get_menu_count() == 1, "one menu after the fold: %d" % _bar.get_menu_count())
	assert(_bar.get_menu_title(0) == Hud.MORE_TITLE, _bar.get_menu_title(0))
	# The entries are keyed per popup, and a folded menu brings its own submenus inside the More menu, so
	# what matters is not how many entries there are but that the popup the bar is now showing has them -
	# a press has to find the entry it names, and a stale key would be a press with nothing behind it.
	assert(hud._menu_items.has(_bar.get_menu_popup(0)),
		"the HUD holds the entries for the popup the bar is showing")
	_free_all()


func test_the_bar_is_not_rebuilt_again_once_the_room_is_recorded() -> void:
	# `_refresh_menus` runs on every frame, and a fold that forgot to record the room it folded for would
	# rebuild the bar on every one of them.
	var hud: PlannerHud = _hud_with_a_bar_in_a_row()
	hud._build_menu_bar()
	hud._rebuild_menu_bar(hud.menu_bar_plan(1.0))
	var folded: PopupMenu = _bar.get_menu_popup(0)
	hud._menu_room = hud.menu_bar_room()
	hud._refresh_menus()
	hud._refresh_menus()
	assert(_bar.get_menu_count() == 1, "still one menu: %d" % _bar.get_menu_count())
	assert(_bar.get_menu_popup(0) == folded, "and the same popup, not one rebuilt on every frame")
	_free_all()


func test_a_bar_with_room_to_spare_is_left_whole() -> void:
	var widths: Array[float] = [100.0, 100.0, 100.0, 100.0]
	assert(Hud.menu_fold_point(widths, 1000.0, 80.0) == 4, "room for all four menus and the More menu")


func test_the_tail_folds_when_the_room_runs_out() -> void:
	# 380 px, a 80 px More title and 100 px a menu: three menus and the More title come to 380.
	var widths: Array[float] = [100.0, 100.0, 100.0, 100.0, 100.0, 100.0]
	assert(Hud.menu_fold_point(widths, 380.0, 80.0) == 3, "three keep their place and three fold away")
	assert(Hud.menu_fold_point(widths, 380.0, 80.0) < widths.size(), "and folding is what happened")


func test_a_fold_that_would_keep_all_but_two_is_not_made() -> void:
	# Five menus in the same room would leave two behind the More menu, which saves 200 px and costs a
	# person the two places they knew. A tight bar is the better answer.
	var widths: Array[float] = [100.0, 100.0, 100.0, 100.0, 100.0]
	assert(Hud.menu_fold_point(widths, 380.0, 80.0) == 5, "no fold: too little would be folded to be worth it")


func test_a_bar_with_no_room_worked_out_is_not_folded() -> void:
	# Zero is "nobody has worked the room out yet", which is the state the bar is built in before the row
	# it sits in has been laid out. That is not the same as a room of no pixels.
	var widths: Array[float] = [100.0, 100.0, 100.0, 100.0, 100.0, 100.0]
	assert(Hud.menu_fold_point(widths, 0.0, 80.0) == 6, "an unknown room leaves the bar as it is")
	assert(Hud.menu_fold_point(widths, -5.0, 80.0) == 6, "and so does a nonsense one")


func test_a_title_is_measured_on_the_bar_font_and_a_longer_one_is_wider() -> void:
	# This is the test that says the fold can work at all. If the bar's theme type or its font item were
	# named wrongly, every title would measure nothing and the rule above would fold every menu.
	var hud: PlannerHud = _hud_with_a_bar()
	var widths: Array[float] = hud.menu_title_widths(["File", "Pipeline"])
	assert(widths.size() == 2, "both titles were measured")
	assert(widths[0] > 0.0, "a title has a width: %s" % str(widths))
	assert(widths[1] > widths[0],
		"a longer title is wider than a shorter one, so this is the real font: %s" % str(widths))
	_free_all()


func test_the_bar_plan_is_the_whole_plan_when_the_room_takes_it() -> void:
	var hud: PlannerHud = _hud_with_a_bar()
	var plan: Array[Dictionary] = hud.menu_bar_plan(100000.0)
	assert(plan.size() == hud.menu_plan().size(), "every menu is in the bar")
	assert(String(plan[0]["title"]) == String(hud.menu_plan()[0]["title"]), "and in the order they are in")
	_free_all()


func test_the_tail_gathers_under_one_more_menu_when_the_room_runs_out() -> void:
	var hud: PlannerHud = _hud_with_a_bar()
	var plan: Array[Dictionary] = hud.menu_bar_plan(1.0)
	assert(plan.size() == 1, "one menu is left: %d" % plan.size())
	assert(String(plan[0]["title"]) == Hud.MORE_TITLE, String(plan[0]["title"]))
	var more: Array = Array(plan[0]["items"])
	# A menu brings its own separators with it, and those carry no words; the named ones are the groups.
	var named: Array[String] = []
	for item: Dictionary in more:
		if StringName(item.get("kind", &"")) != &"separator":
			continue
		var label: String = String(item.get("label", ""))
		if not label.is_empty():
			named.append(label)
	var titles: Array[String] = []
	for menu: Dictionary in hud.menu_plan():
		titles.append(String(menu["title"]))
	assert(named == titles,
		"every folded menu is named, in the order it left the bar: %s" % str(named))
	assert(more.size() > named.size(),
		"and the commands themselves came with them rather than the names alone")
	_free_all()


func test_the_plan_itself_is_left_alone_by_a_folded_bar() -> void:
	# The palette lists the plan and the tests hold the Help menu's order to it, so the fold has to be a
	# view of the bar rather than an edit to the plan.
	var hud: PlannerHud = _hud_with_a_bar()
	var before: int = hud.menu_plan().size()
	var folded: Array[Dictionary] = hud.menu_bar_plan(1.0)
	assert(folded.size() == 1, "the bar is folded")
	assert(hud.menu_plan().size() == before, "the plan is not")
	_free_all()


## A phone's own finding, and the reason this arithmetic is a function of its own: the row's minimum came
## out *smaller* than the bar's, the subtraction went negative, and the bar was handed more room than the
## screen had - so nothing folded and all fourteen menus were drawn clipped at both ends.
func test_a_row_that_measures_smaller_than_its_bar_does_not_hand_the_bar_spare_room() -> void:
	assert(Hud.bar_room(1420.0, -120.0, 1444.0) == 1420.0,
		"a negative remainder is no remainder at all")
	assert(Hud.bar_room(1576.0, 36.0, 1600.0) == 1540.0,
		"and the desk's own numbers come out exactly as they always did")


## A row can be laid out wider than the canvas it is drawn in; the room the bar has is what a person can
## actually see, and before the first layout the screen is the only thing that knows.
func test_a_row_wider_than_the_screen_is_only_the_screen() -> void:
	assert(Hud.bar_room(1800.0, 0.0, 1444.0) == 1444.0, "clamped to the screen")
	assert(Hud.bar_room(0.0, 0.0, 1444.0) == 1444.0, "and before the first layout the screen answers")
	assert(Hud.bar_room(0.0, 0.0, 0.0) == 0.0,
		"a bar with nothing known is not told it has room, because no room worked out is not no room")