extends Node
## Proof that the plant key is reachable and that it narrows the **real** catalogue: stand the game up,
## open the page through the very handler the Plant menu names, and answer it until it settles.
##
## The modules cannot make this check for themselves. `test_plant_key.gd` measures the arithmetic against
## a garden of five, and `test_plant_key_window.gd` drives the page off-tree; neither can answer "does the
## menu entry open this page, and does it narrow the shipped nursery list". That is what this prints.
##
##     run_scene res://tools/plant_key_demo.tscn
##
## It writes nothing at all - the key reads the catalogue and keeps its answers in memory - so there is
## nothing to clean up afterwards.

const MainScene := preload("res://scenes/main.tscn")
const PageScript := preload("res://scripts/plant_key_window.gd")
## Which page a script is, and which subject of the manual describes it. Both are the project's own single
## sources for those two questions, so neither is worked out a second time here.
const IndexScript := preload("res://scripts/page_index.gd")
const PageHelpScript := preload("res://scripts/page_help.gd")
const HelpDocScript := preload("res://scripts/help_doc.gd")

## The two nodes this needs: the HUD owns the door and the one plant list.
const HUD_SCRIPT := "res://scripts/hud.gd"
const PAGE_NAME := "PlantKeyWindow"
## The handler the menu entry calls, named here so the demo can prove the menu names the same one.
const OPEN_HANDLER := &"_menu_plant_key"
## Long enough for the front door and the rest of the scene to settle before anything is driven.
const SETTLE_SECONDS := 0.5
## A key has six questions, so more answers than this means something is wrong rather than long.
const MOST_STEPS := 12

var _game: Node = null
var _hud: PlannerHud = null


func _ready() -> void:
	_game = MainScene.instantiate()
	add_child(_game)
	var timer := Timer.new()
	timer.name = "SettleTimer"
	timer.wait_time = SETTLE_SECONDS
	timer.one_shot = true
	timer.timeout.connect(_prove)
	add_child(timer)
	timer.start()


func _prove() -> void:
	_hud = _first_with_script(_game, HUD_SCRIPT) as PlannerHud
	if _hud == null:
		print("DEMO FAILED the game has no HUD, so there is nothing to prove")
		get_tree().quit(1)
		return

	var catalogue: PlantCatalogue = _hud.plant_list()
	print("DEMO the game's list holds %d species" % catalogue.count())

	# The door: the Plant menu has to offer this handler by name, or there is a page nobody can open.
	print("DEMO the Plant menu offers %s: %s" % [OPEN_HANDLER, str(_menu_offers(OPEN_HANDLER))])

	# Opened through the handler the menu holds, which is what a person's click runs.
	_hud.call(OPEN_HANDLER, { })
	var page: PageScript = _hud.find_child(PAGE_NAME, true, false) as PageScript
	if page == null:
		print("DEMO FAILED the handler did not build the page")
		get_tree().quit(1)
		return
	print("DEMO the page is open: %s" % str(_hud.is_plant_key_window_open()))

	# Answered until it settles, always taking the first answer offered: the biggest group, so this walks
	# the whole list down rather than taking a shortcut through one plant's own answers.
	var steps: int = 0
	while page.option_count() > 0 and steps < MOST_STEPS:
		print("DEMO %s  (%d offered)" % [page.prompt_text(), page.option_count()])
		for index: int in page.option_count():
			print("DEMO     %s" % page.option_words(index))
		page.choose(0)
		steps += 1
	print("DEMO after %d answer(s): %s" % [page.answer_count(), page.words_text()])
	print("DEMO the key names: %s" % String(page.identified_id()))

	# The manual join: a page with no subject would send a person who pressed Help from it nowhere, and a
	# subject the manual does not have would send them to a heading that is not there.
	var page_name: String = IndexScript.page_name((page.get_script() as Script).resource_path)
	var subject: String = PageHelpScript.subject_for(page_name)
	print("DEMO the page %s is described by \"%s\"" % [page_name, subject])
	print("DEMO the manual has that subject: %s" % str(HelpDocScript.SUBJECTS.has(subject)))

	_hud.close_plant_key_window()
	print("DEMO the page is open after closing: %s" % str(_hud.is_plant_key_window_open()))
	get_tree().quit(0)


## Whether the Plant menu has an entry carrying this handler - searched by value rather than by the key the
## entry keeps it under, so this does not depend on the menu table's own shape.
func _menu_offers(handler: StringName) -> bool:
	for item: Dictionary in PlannerHud.plant_items():
		for value: Variant in item.values():
			if value is StringName and StringName(value) == handler:
				return true
	return false


func _first_with_script(node: Node, path: String) -> Node:
	for child: Node in node.get_children(true):
		var script: Script = child.get_script() as Script
		if script != null and script.resource_path == path:
			return child
		var found: Node = _first_with_script(child, path)
		if found != null:
			return found
	return null