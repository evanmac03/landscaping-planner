extends Node
## What the drawing has said, joined to the Edit menu and to the drawing.
##
## The history is tested in `test_status_history.gd` and the page in `test_status_window.gd`; this is the
## part that only exists when they are put together - that the menu offers the page and gives it no key,
## that the page is built hidden inside the HUD and put in the Escape pass's list, and that filling it
## hands it the *drawing's* own answers rather than a list the HUD keeps.
##
## The HUD and the page enter no tree, so no `_ready` runs and no window is ever shown:
## `popup_centered` needs a screen and a test does not have one, which is why filling the page is its own
## function and `open_status_window()` is never called here.

const HudScript := preload("res://scripts/hud.gd")
const WindowScript := preload("res://scripts/status_window.gd")
const ControllerScript := preload("res://scripts/draft/draft_controller.gd")
const DocumentScript := preload("res://scripts/draft/draft_document.gd")


# --- helpers --------------------------------------------------------------------------


## A controller with a document under it and nothing else: everything that reaches for a scene is
## avoided - the binding is done the way `open_drawing` does it.
func _drawing() -> DraftController:
	var controller: DraftController = ControllerScript.new()
	controller._bind_document(DocumentScript.new())
	return controller


func _hud_with_drawing(controller: DraftController) -> Node:
	var hud: HudScript = HudScript.new()
	hud._draft = controller
	return hud


# --- the menu -------------------------------------------------------------------------


func test_the_edit_menu_offers_it_at_the_foot_with_no_key() -> void:
	var entry: Dictionary = {}
	for candidate: Dictionary in HudScript.edit_items():
		if StringName(candidate.get("id", &"")) == &"edit.said":
			entry = candidate
	assert(not entry.is_empty(), "the Edit menu has no entry for what has been said")
	assert(String(entry["label"]) == "What just happened...", String(entry["label"]))
	assert(StringName(entry["method"]) == &"_menu_said", String(entry["method"]))
	assert(StringName(entry.get("action", &"")) == &"", "it takes no key")
	assert(entry["kind"] == "command", "and it is a command like the ones beside it")


# --- the page -------------------------------------------------------------------------


func test_the_page_is_built_hidden_inside_the_hud() -> void:
	var hud: HudScript = HudScript.new()
	hud._build_status_window()
	assert(hud._status_window != null, "the page was built")
	assert(hud._status_window.get_parent() == hud, "it belongs to the HUD")
	assert(hud._status_window.name == StringName("StatusWindow"), str(hud._status_window.name))
	assert(not hud._status_window.visible, "and it is not on screen")
	assert(not hud.is_status_window_open(), "so nothing is open")
	hud.close_status_window()
	assert(not hud.is_status_window_open(), "and closing a page that is not open is harmless")
	hud.free()


func test_it_is_a_page_the_escape_pass_has_to_reach() -> void:
	# A page in a `Window` takes the keyboard into its own viewport, so it is only closable by Escape if
	# it is on the list the pass walks.
	var hud: HudScript = HudScript.new()
	hud._build_status_window()
	assert(hud.pages_in_windows().has(hud._status_window), "the page is on the list")
	hud._let_escape_close_pages()
	assert(hud._status_window.get_node_or_null(^"PageEscape") != null, "and it can be escaped from")
	hud.free()


# --- the join -------------------------------------------------------------------------


func test_filling_it_hands_over_the_drawings_own_answers() -> void:
	var controller := _drawing()
	var hud: HudScript = _hud_with_drawing(controller)
	controller.last_message = "line added"
	controller.last_message = "1 entity erased"
	hud._fill_status_window()
	assert(hud._status_window.line_count() == 2, str(hud._status_window.line_count()))
	var wanted: Array[String] = ["1 entity erased", "line added"]
	assert(hud._status_window.line_texts() == wanted, str(hud._status_window.line_texts()))
	assert(hud._status_window.said() == "the drawing last said: 1 entity erased",
		hud._status_window.said())
	hud.free()
	controller.free()


func test_the_drawing_carries_on_and_the_page_is_the_same_page() -> void:
	# The page holds a handle on the drawing's history rather than a copy of it, so what is said after the
	# page was filled is what the page shows when it is next written.
	var controller := _drawing()
	var hud: HudScript = _hud_with_drawing(controller)
	controller.last_message = "line added"
	hud._fill_status_window()
	controller.last_message = "3 entities moved"
	assert(hud._status_window.show_lines(), "there is something new to write")
	assert(hud._status_window.newest() == "3 entities moved", hud._status_window.newest())
	hud.free()
	controller.free()


func test_a_scene_with_no_drawing_says_so_rather_than_listing_nothing() -> void:
	var hud: HudScript = HudScript.new()
	hud._fill_status_window()
	assert(hud._status_window != null, "the page is still built")
	assert(hud._status_window.line_count() == 0, "with no rows")
	assert(hud._status_window.hint() == WindowScript.NO_DRAWING, hud._status_window.hint())
	assert(hud._status_window.said() == WindowScript.NO_DRAWING, hud._status_window.said())
	hud.free()


func test_the_refresh_is_harmless_while_the_page_is_away() -> void:
	# The tick runs every frame; a page that is not on screen must not be rewritten under it.
	var controller := _drawing()
	var hud: HudScript = _hud_with_drawing(controller)
	hud._build_status_window()
	controller.last_message = "line added"
	hud._tick_status_window()
	assert(hud._status_window.line_count() == 0, "a page that is not up was not written")
	hud.free()
	controller.free()