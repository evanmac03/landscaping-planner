extends Node
## The snapping page as the program reaches it: the Draft menu's entry, the page the HUD builds, and
## the Escape pass that has to be able to close it.
##
## The page's own switches are driven in `tests/test_snap_window.gd`; this is the join, which is where
## an omission - a page built but never added to `pages_in_windows()`, a menu entry pointing at no
## method - actually shows.
##
## A HUD is built off-tree - no `_ready`, so nothing is painted and no window pops up - and freed by
## hand: a leaked Node is a resource still in use at the end of the run.

const HudScript := preload("res://scripts/hud.gd")


func _draft_entry(id: String) -> Dictionary:
	for entry: Dictionary in HudScript.items_for("Draft"):
		if String(entry.get("id", "")) == id:
			return entry
	return {}


func test_the_draft_menu_offers_the_snapping_settings() -> void:
	var entry: Dictionary = _draft_entry("draft.snapping")
	assert(not entry.is_empty(), "the Draft menu can reach the snapping settings")
	assert(String(entry["method"]) == "_menu_snap_window")
	assert(StringName(entry["kind"]) == &"command")


func test_the_menu_has_the_methods_the_page_needs() -> void:
	var hud := HudScript.new()
	assert(hud.has_method("open_snap_window"))
	assert(hud.has_method("close_snap_window"))
	assert(hud.has_method("is_snap_window_open"))
	assert(hud.has_method("_menu_snap_window"))
	assert(not hud.is_snap_window_open(), "and it is not open until it is asked for")
	hud.free()


func test_the_hud_builds_the_page_and_it_can_be_escaped_from() -> void:
	var hud := HudScript.new()
	assert(hud._snap_window == null, "no page until the HUD builds one")
	hud._build_snap_window()
	assert(hud._snap_window != null)
	assert(hud.pages_in_windows().has(hud._snap_window), "the page is on the escape list")
	hud._let_escape_close_pages()
	assert(hud._snap_window.get_node_or_null(^"PageEscape") != null, "and it can be escaped from")
	assert(not hud.is_snap_window_open(), "built but not shown is not open")
	hud.free()


func test_a_hud_with_no_drawing_offers_a_page_that_says_so() -> void:
	var hud := HudScript.new()
	hud._build_snap_window()
	hud._fill_snap_window()
	# The HUD built off-tree holds no drafting controller, so the page honestly has nothing to snap.
	assert(hud._snap_window.status_text().contains("nothing here to snap"),
		"it says so: %s" % hud._snap_window.status_text())
	assert(hud._snap_window.master_button().disabled, "and there is nothing it could switch")
	hud.free()