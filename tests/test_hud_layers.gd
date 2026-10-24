extends Node
## The layers page as the program reaches it: the Site menu's entry, the page the HUD builds and opens,
## and the Escape pass that has to be able to close it.
##
## The page itself is driven in `tests/test_layer_window.gd`; this is the join.

const HudScript := preload("res://scripts/hud.gd")


func _site_entry(id: String) -> Dictionary:
	for entry: Dictionary in HudScript.items_for("Site"):
		if String(entry.get("id", "")) == id:
			return entry
	return {}


func test_the_site_menu_offers_the_layers_page() -> void:
	var entry: Dictionary = _site_entry("site.layers")
	assert(not entry.is_empty(), "the Site menu can manage the drawing's layers")
	assert(String(entry["method"]) == "_menu_layer_window")
	assert(StringName(entry["needs"]) == HudScript.NEEDS_DRAFT, "and it needs a drawing to manage")


func test_the_menu_has_the_methods_the_page_needs() -> void:
	var hud := HudScript.new()
	assert(hud.has_method("open_layer_window"))
	assert(hud.has_method("close_layer_window"))
	assert(hud.has_method("is_layer_window_open"))
	assert(hud.has_method("_menu_layer_window"))
	assert(not hud.is_layer_window_open(), "and it is not open until it is asked for")
	hud.free()


func test_the_hud_builds_the_page_and_lets_escape_close_it() -> void:
	# A page in a `Window` takes the keyboard into its own viewport, so it is only closable by Escape if
	# it is on the list the pass walks.
	var hud: HudScript = HudScript.new()
	assert(hud._layer_window == null, "no page until the HUD builds one")
	hud._build_layer_window()
	assert(hud._layer_window != null)
	assert(hud._layer_window.dialog != null, "pointed at a layer dialog")
	assert(hud.pages_in_windows().has(hud._layer_window), "the page is on the list")
	hud._let_escape_close_pages()
	assert(hud._layer_window.get_node_or_null(^"PageEscape") != null, "and it can be escaped from")
	assert(not hud.is_layer_window_open(), "built but not shown is not open")
	hud.free()


func test_opening_the_page_with_no_drawing_does_nothing() -> void:
	# The entry needs a drawing, but the method is reachable anyway: with no controller there is nothing
	# to show, so it opens nothing rather than reaching through a null.
	var hud := HudScript.new()
	hud._build_layer_window()
	hud.open_layer_window()
	assert(not hud.is_layer_window_open())
	hud.free()