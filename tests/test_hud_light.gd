extends Node
## The HUD's side of lighting: the Light menu's way in, and what the panel's own signals do to the
## drawing.
##
## The page is built by hand here and never shown: what is under test is the wiring, and every handler
## below is reached by the same method the signal is connected to.

const HudScript := preload("res://scripts/hud.gd")
const ControllerScript := preload("res://scripts/draft/draft_controller.gd")
const DocumentScript := preload("res://scripts/draft/draft_document.gd")
const ToolScript := preload("res://scripts/draft/draft_tool.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const Lighting := preload("res://scripts/draft/lighting.gd")

## A nine metre square: three well-light throws each way, so a circuit comes out sixteen fixtures,
## which draw 80 of the 100 volt-amperes the drawing is lit by.
const BED := 9.0


func _hud():
	var hud := HudScript.new()
	# The page is a `Control` in the HUD's own "Root", so the HUD needs one to hang it on: without it
	# there is nowhere for the page to be built and every handler below would find no panel.
	var root := Node.new()
	root.name = "Root"
	hud.add_child(root)
	var controller = ControllerScript.new()
	controller.document = DocumentScript.new()
	controller.tool = ToolScript.new()
	hud._draft = controller
	hud._build_lighting_panel()
	controller.document.add(
		Entity.make_polyline(PackedVector2Array([
			Vector2(0.0, 0.0), Vector2(BED, 0.0), Vector2(BED, BED), Vector2(0.0, BED),
		]), true),
		LayerSet.NEW_BED
	)
	return hud


## Free the Hud and the controller holding the drawing it was given. A Node is not reference counted,
## and a leaked one is reported as a resource still in use at exit - which the runner counts as a
## failing test.
func _done(hud) -> void:
	var controller: Node = hud._draft
	hud.free()
	if controller != null:
		controller.free()


func _entry(id: StringName) -> Dictionary:
	for entry: Dictionary in HudScript.menu_entries():
		if StringName(entry.get("id", &"")) == id:
			return entry
	assert(false, "no menu entry with id %s" % String(id))
	return {}


# --- the way in -----------------------------------------------------------------------


func test_the_light_menu_offers_lighting_an_area() -> void:
	var entry: Dictionary = _entry(&"light.panel")
	assert(String(entry["label"]) == "Light an area...", String(entry["label"]))
	assert(StringName(entry["method"]) == &"_menu_light_panel", String(entry["method"]))
	assert(entry["needs"] == HudScript.NEEDS_DRAFT, "and it needs a drawing to light")
	# It is in the Light menu, with the line that reports what this drawing is lit by.
	var ids: Array[String] = []
	for listed: Dictionary in HudScript.items_for("Light"):
		ids.append(String(listed.get("id", "")))
	assert(ids.has("light.info"), "the menu says what the drawing is lit by")
	assert(ids.has("light.panel"), "and offers the page that lights an area")
	# And it is an entry the bar can actually run.
	var hud := HudScript.new()
	assert(hud.has_method(String(entry["method"])), "the method the entry names exists")
	_done(hud)


func test_a_page_with_no_drawing_opens_nothing() -> void:
	var hud := HudScript.new()
	assert(not hud.is_light_panel_open())
	hud.open_light_panel()
	assert(not hud.is_light_panel_open(), "there is no drawing for a page to be about")
	_done(hud)


# --- what the panel's signals do ------------------------------------------------------


func test_stating_the_transformer_through_the_page_states_it_on_the_drawing() -> void:
	var hud = _hud()
	assert(hud._draft.lighting_transformer().is_empty(), "nothing is stated to begin with")
	hud._on_light_transformer(100.0, 12.0)
	assert(absf(float(hud._draft.lighting_transformer()["va"]) - 100.0) < 0.001, "it is stated")
	assert(hud.light_status_text().contains("100 VA at 12 V"), hud.light_status_text())
	assert(hud.light_status_text().contains("25"), "and the budget is twenty-five path lights: %s"
		% hud.light_status_text())
	_done(hud)


func test_lighting_through_the_page_puts_the_fixtures_on_the_plan() -> void:
	var hud = _hud()
	hud._on_light_transformer(100.0, 12.0)
	var before: int = hud._draft.document.count()
	var row: Dictionary = hud._draft.lightable_areas()[0]
	hud._on_light_area(String(row["key"]), Lighting.WELL, Lighting.throw_of_kind(Lighting.WELL), false)
	assert(hud._draft.document.count() == before + 16, "sixteen fixtures on the plan: %d"
		% (hud._draft.document.count() - before))
	assert(hud._draft.lighting_circuits().size() == 1, "and one circuit kept with the drawing")
	# The page reports what it just did: the verdict the controller handed back.
	assert(hud.light_status_text().contains("Circuit 1 will run"), hud.light_status_text())
	assert(hud._light_panel._circuit_list.item_count == 1, "the page lists it")
	# Clearing the reported line leaves the page saying what the drawing holds.
	hud._light_panel.say("")
	assert(hud.light_status_text().contains("1 circuit"), hud.light_status_text())
	_done(hud)


func test_lighting_an_area_the_page_has_that_is_gone_says_so_rather_than_failing() -> void:
	var hud = _hud()
	hud._on_light_transformer(100.0, 12.0)
	hud._on_light_area("bed#9999", Lighting.WELL, 3.0, false)
	assert(hud.light_status_text().contains("not there any more"), hud.light_status_text())
	assert(hud._draft.lighting_circuits().is_empty(), "and nothing was laid out")
	_done(hud)


func test_lighting_with_no_transformer_stated_is_refused_and_says_so() -> void:
	var hud = _hud()
	var row: Dictionary = hud._draft.lightable_areas()[0]
	hud._on_light_area(String(row["key"]), Lighting.WELL, 3.0, false)
	assert(hud.light_status_text().contains("transformer has not been stated"), hud.light_status_text())
	assert(hud._draft.document.count() == 1, "and the bed is alone on the drawing")
	_done(hud)


func test_taking_the_circuit_off_through_the_page_takes_its_fixtures_with_it() -> void:
	var hud = _hud()
	hud._on_light_transformer(100.0, 12.0)
	var row: Dictionary = hud._draft.lightable_areas()[0]
	hud._on_light_area(String(row["key"]), Lighting.WELL, 3.0, false)
	var before: int = hud._draft.document.count()
	hud._on_light_remove(1)
	assert(hud._draft.lighting_circuits().is_empty(), "the circuit is gone")
	assert(hud._draft.document.count() == before - 16, "and its sixteen fixtures with it: %d"
		% (before - hud._draft.document.count()))
	assert(hud.light_status_text().contains("off the drawing"), hud.light_status_text())
	_done(hud)


func test_the_menu_line_reports_the_transformer_and_the_circuits() -> void:
	var hud = _hud()
	assert(hud._light_text().contains("nothing on this drawing is lit yet"),
		hud._light_text())
	assert(hud._light_text().contains("no transformer stated"), hud._light_text())
	hud._on_light_transformer(100.0, 12.0)
	var row: Dictionary = hud._draft.lightable_areas()[0]
	hud._on_light_area(String(row["key"]), Lighting.WELL, 3.0, false)
	assert(hud._light_text().contains("transformer: 100 VA at 12 V"), hud._light_text())
	assert(hud._light_text().contains("every circuit runs off the transformer"), hud._light_text())
	_done(hud)