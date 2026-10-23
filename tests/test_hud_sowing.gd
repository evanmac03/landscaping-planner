extends Node
## When to sow, joined to the Plant menu.
##
## The arithmetic is tested in `test_sowing_planner.gd` and the page in `test_sowing_window.gd`; this is
## the part that only exists when they are put together - that the Plant menu offers the page and hands
## it the drawing and the list, that the page is built hidden inside the HUD and put in the Escape
## pass's list, and that a season stated behind an open page reaches it.
##
## The HUD and the page enter no tree, so no `_ready` runs and no window is ever shown: `popup_centered`
## needs a screen and a test does not have one, which is why filling the page is its own function and
## `open_sowing_window()` is only called where it is expected to do nothing.

const HudScript := preload("res://scripts/hud.gd")
const ControllerScript := preload("res://scripts/draft/draft_controller.gd")
const DocumentScript := preload("res://scripts/draft/draft_document.gd")

const LAST := 140
const FIRST := 280


## A HUD with a drawing in the scene, so the page has a season to read.
func _hud_with_a_drawing() -> Array:
	var controller: DraftController = ControllerScript.new()
	controller.document = DocumentScript.new()
	var hud: HudScript = HudScript.new()
	hud._draft = controller
	return [hud, controller]


func _done(parts: Array) -> void:
	var hud: HudScript = parts[0]
	var controller: Node = parts[1]
	hud.free()
	if controller != null:
		controller.free()


# --- the menu ---------------------------------------------------------------------------------


func test_the_plant_menu_offers_it_needing_a_drawing() -> void:
	var entry: Dictionary = {}
	for candidate: Dictionary in HudScript.plant_items():
		if StringName(candidate.get("id", &"")) == &"plant.sow":
			entry = candidate
	assert(not entry.is_empty(), "the Plant menu has no entry for sowing")
	assert(String(entry["label"]) == "When to sow...", String(entry["label"]))
	assert(StringName(entry["method"]) == &"_menu_sowing_window", String(entry["method"]))
	assert(StringName(entry.get("action", &"")) == &"", "it takes no key")
	assert(entry["kind"] == "command", "and it is a command like the ones beside it")
	assert(
		StringName(entry["needs"]) == HudScript.NEEDS_DRAFT,
		"the season it sows into is a fact about the site, which lives on the drawing"
	)


func test_every_menu_entry_still_names_a_method_this_hud_has() -> void:
	var hud: HudScript = HudScript.new()
	assert(hud.has_method(&"_menu_sowing_window"), "the menu's door is a real one")
	assert(hud.has_method(&"_tick_sowing_window"), "and so is the door the tick calls")
	hud.free()


# --- the page ---------------------------------------------------------------------------------


func test_the_page_is_built_hidden_inside_the_hud() -> void:
	var hud: HudScript = HudScript.new()
	hud._build_sowing_window()
	assert(hud._sowing_window != null, "the page was built")
	assert(hud._sowing_window.get_parent() == hud, "it belongs to the HUD")
	assert(hud._sowing_window.name == StringName("SowingWindow"), str(hud._sowing_window.name))
	assert(not hud._sowing_window.visible, "and it is not on screen")
	assert(not hud.is_sowing_window_open(), "so nothing is open")
	hud.free()


func test_it_is_a_page_the_escape_pass_has_to_reach() -> void:
	# A page in a `Window` takes the keyboard into its own viewport, so it is only closable by Escape if
	# it is on the list the pass walks.
	var hud: HudScript = HudScript.new()
	hud._build_sowing_window()
	assert(hud.pages_in_windows().has(hud._sowing_window), "the page is on the list")
	hud._let_escape_close_pages()
	assert(hud._sowing_window.get_node_or_null(^"PageEscape") != null, "and it can be escaped from")
	hud.free()


func test_a_hud_with_no_drawing_reports_nothing_open() -> void:
	var hud: HudScript = HudScript.new()
	assert(not hud.is_sowing_window_open())
	hud.close_sowing_window()
	assert(not hud.is_sowing_window_open(), "and closing a page that is not open is harmless")
	hud.free()


func test_opening_it_with_no_drawing_builds_the_page_without_showing_it() -> void:
	var hud: HudScript = HudScript.new()
	assert(hud._draft == null, "there is no drawing at all")
	hud.open_sowing_window()
	assert(hud._sowing_window != null, "the page is built")
	assert(not hud.is_sowing_window_open(), "but it is not shown - there is no season to sow into")
	hud.free()


# --- the join ---------------------------------------------------------------------------------


func test_filling_it_hands_over_the_drawing_and_the_list() -> void:
	var parts: Array = _hud_with_a_drawing()
	var hud: HudScript = parts[0]
	parts[1].document.set_season(LAST, FIRST)
	hud._fill_sowing_window()
	assert(hud._sowing_window.season_stated(), "the drawing's season reaches the page")
	assert(hud._sowing_window.season_line().contains("140 days"), hud._sowing_window.season_line())
	assert(hud._sowing_window.sow() == LAST, "and the day in hand is the drawing's last frost")
	assert(hud._sowing_window.row_count() > 0, "and the shipped list is the crops it sows")
	_done(parts)


func test_the_page_keeps_up_with_the_drawing_while_it_is_up() -> void:
	var parts: Array = _hud_with_a_drawing()
	var hud: HudScript = parts[0]
	parts[1].document.set_season(LAST, FIRST)
	hud._fill_sowing_window()
	hud._sowing_window.visible = true
	# A different season stated behind the open page - an undo, or another window - has to reach it.
	parts[1].document.set_season(166, 250)
	hud._tick_sowing_window()
	assert(
		hud._sowing_window.season_line().contains("84 days"),
		"the season stated behind the page reaches it: %s" % hud._sowing_window.season_line()
	)
	hud._sowing_window.visible = false
	_done(parts)


func test_the_tick_is_harmless_while_the_page_is_away() -> void:
	var parts: Array = _hud_with_a_drawing()
	var hud: HudScript = parts[0]
	hud._build_sowing_window()
	hud._tick_sowing_window()
	assert(not hud._sowing_window.visible, "a page that is not up was not shown by the tick")
	_done(parts)