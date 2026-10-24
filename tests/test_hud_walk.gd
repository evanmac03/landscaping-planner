extends Node
## The walk-through page as the program reaches it: the Present menu's entry, the page the HUD builds,
## and the Escape pass that has to be able to close it.
##
## The page itself - the stops, the clock, the camera - is driven in `tests/test_walk_window.gd`; this
## is the join, which is where an omission (a page built but never added to `pages_in_windows()`, a menu
## entry pointing at no method) actually shows.
##
## A HUD is built off-tree - no `_ready`, so nothing is painted and no window pops up - and freed by
## hand: a leaked Node is a resource still in use at the end of the run.

const HudScript := preload("res://scripts/hud.gd")


func _present_entry(id: String) -> Dictionary:
	for entry: Dictionary in HudScript.items_for("Present"):
		if String(entry.get("id", "")) == id:
			return entry
	return {}


func test_the_present_menu_offers_a_walk_through() -> void:
	var entry: Dictionary = _present_entry("present.walk")
	assert(not entry.is_empty(), "the Present menu can walk the garden")
	assert(String(entry["method"]) == "_menu_walk_window")
	assert(StringName(entry["kind"]) == &"command")
	# A walk moves the presentation camera, so it needs of the scene what the sun study needs.
	var study: Dictionary = _present_entry("present.sun_study")
	assert(not study.is_empty(), "the sun study is still there beside it")
	assert(StringName(entry["needs"]) == StringName(study["needs"]), "it needs a presentation")


func test_the_menu_has_the_methods_the_page_needs() -> void:
	var hud := HudScript.new()
	assert(hud.has_method("open_walk_window"))
	assert(hud.has_method("close_walk_window"))
	assert(hud.has_method("is_walk_window_open"))
	assert(hud.has_method("_menu_walk_window"))
	assert(not hud.is_walk_window_open(), "and it is not open until it is asked for")
	hud.free()


func test_the_hud_builds_the_page_and_it_can_be_escaped_from() -> void:
	var hud := HudScript.new()
	assert(hud._walk_window == null, "no page until the HUD builds one")
	hud._build_walk_window()
	assert(hud._walk_window != null)
	assert(hud.pages_in_windows().has(hud._walk_window), "the page is on the escape list")
	hud._let_escape_close_pages()
	assert(hud._walk_window.get_node_or_null(^"PageEscape") != null, "and it can be escaped from")
	assert(not hud.is_walk_window_open(), "built but not shown is not open")
	hud.free()


func test_the_page_has_no_walk_until_a_presentation_is_bound() -> void:
	var hud := HudScript.new()
	hud._build_walk_window()
	hud._fill_walk_window()
	# The HUD built off-tree holds no presentation node, so the page honestly has no garden to walk.
	assert(hud._walk_window.stop_rows().is_empty(), "no presenter, no route")
	assert(hud._walk_window.summary_text().contains("no walk-through"),
		"and it says so: %s" % hud._walk_window.summary_text())
	assert(hud._walk_window.play_button().disabled, "with nothing to walk")
	hud.free()