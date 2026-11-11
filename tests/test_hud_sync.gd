extends Node
## The sync page as the program reaches it: the Jobs menu's entry, the page the HUD builds, the engine
## and service behind it, and the Escape pass that has to be able to close it.
##
## The page itself is driven in `tests/test_sync_window.gd`; this is the join.
##
## A HUD is built off-tree - no `_ready`, so nothing is painted and no window pops up - and freed by
## hand: a leaked Node is a resource still in use at the end of the run.

const HudScript := preload("res://scripts/hud.gd")


func _jobs_entry(id: String) -> Dictionary:
	for entry: Dictionary in HudScript.items_for("Jobs"):
		if String(entry.get("id", "")) == id:
			return entry
	return {}


func test_the_jobs_menu_offers_syncing_with_the_office() -> void:
	var entry: Dictionary = _jobs_entry("jobs.sync")
	assert(not entry.is_empty(), "the Jobs menu can sync the records")
	assert(String(entry["method"]) == "_menu_sync_window")
	assert(StringName(entry["kind"]) == &"command")
	# A sync is business data, so it needs of the scene exactly what the rest of this menu needs.
	var outbox: Dictionary = _jobs_entry("jobs.outbox")
	assert(StringName(entry["needs"]) == StringName(outbox["needs"]), "it needs no drawing")


func test_the_menu_has_the_methods_the_page_needs() -> void:
	var hud := HudScript.new()
	assert(hud.has_method("open_sync_window"))
	assert(hud.has_method("close_sync_window"))
	assert(hud.has_method("is_sync_window_open"))
	assert(hud.has_method("_menu_sync_window"))
	assert(not hud.is_sync_window_open(), "and it is not open until it is asked for")
	hud.free()


func test_the_hud_builds_the_page_the_engine_and_the_service() -> void:
	var hud := HudScript.new()
	assert(hud._sync_window == null, "no page until the HUD builds one")
	hud._build_sync_window()
	assert(hud._sync_window != null)
	assert(hud._sync_engine != null, "the page has an engine to show")
	assert(hud._sync_engine.store != null, "and a store for the records to live in")
	assert(hud._sync_engine.transport != null, "and the one service this build offers")
	assert(hud._sync_engine.transport.name() == "http")
	assert(hud.pages_in_windows().has(hud._sync_window), "the page is on the escape list")
	hud._let_escape_close_pages()
	assert(hud._sync_window.get_node_or_null(^"PageEscape") != null, "and it can be escaped from")
	assert(not hud.is_sync_window_open(), "built but not shown is not open")
	hud.free()


func test_the_page_shows_the_engines_own_state() -> void:
	var hud := HudScript.new()
	hud._build_sync_window()
	# A fresh engine with nowhere configured: the page is honest about both, and its settings are the
	# service's own two.
	assert(hud._sync_window.queue_rows().is_empty(), "nothing is waiting yet")
	assert(hud._sync_window.service_text().contains("no address yet"), hud._sync_window.service_text())
	assert(hud._sync_window.setting_field(&"base_url") != null, "the address can be set here")
	assert(hud._sync_window.setting_field(&"token") != null, "and the token")
	hud.free()