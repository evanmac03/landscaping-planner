extends Node
## The HUD's side of irrigation: the Water menu's way in, and what the panel's own signals do to the
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
const Irrigation := preload("res://scripts/draft/irrigation.gd")

## A nine metre square: two spray throws each way, so a zone comes out the textbook nine heads, which
## draw 81 of the 120 litres a minute the drawing is watered by.
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
	hud._build_irrigation_panel()
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


func test_the_water_menu_offers_watering_an_area() -> void:
	var entry: Dictionary = _entry(&"water.panel")
	assert(String(entry["label"]) == "Water an area...", String(entry["label"]))
	assert(StringName(entry["method"]) == &"_menu_water_panel", String(entry["method"]))
	assert(entry["needs"] == HudScript.NEEDS_DRAFT, "and it needs a drawing to water")
	# It is in the Water menu, with the line that reports what this drawing is watered by.
	var ids: Array[String] = []
	for listed: Dictionary in HudScript.items_for("Water"):
		ids.append(String(listed.get("id", "")))
	assert(ids.has("water.info"), "the menu says what the drawing is watered by")
	assert(ids.has("water.panel"), "and offers the page that waters an area")
	# And it is an entry the bar can actually run.
	var hud := HudScript.new()
	assert(hud.has_method(String(entry["method"])), "the method the entry names exists")
	_done(hud)


func test_a_page_with_no_drawing_opens_nothing() -> void:
	var hud := HudScript.new()
	assert(not hud.is_water_panel_open())
	hud.open_water_panel()
	assert(not hud.is_water_panel_open(), "there is no drawing for a page to be about")
	_done(hud)


# --- what the panel's signals do ------------------------------------------------------


func test_stating_the_supply_through_the_page_states_it_on_the_drawing() -> void:
	var hud = _hud()
	assert(hud._draft.irrigation_supply().is_empty(), "nothing is stated to begin with")
	hud._on_water_supply(120.0, 350.0)
	assert(absf(float(hud._draft.irrigation_supply()["flow"]) - 120.0) < 0.001, "it is stated")
	assert(hud.water_status_text().contains("120 L/min"), hud.water_status_text())
	assert(hud.water_status_text().contains("13"), "and the budget is thirteen spray heads: %s"
		% hud.water_status_text())
	_done(hud)


func test_watering_through_the_page_puts_the_heads_on_the_plan() -> void:
	var hud = _hud()
	hud._on_water_supply(120.0, 350.0)
	var before: int = hud._draft.document.count()
	var row: Dictionary = hud._draft.waterable_areas()[0]
	hud._on_water_area(String(row["key"]), Irrigation.SPRAY, Irrigation.throw_of_kind(Irrigation.SPRAY), false)
	assert(hud._draft.document.count() == before + 9, "nine heads on the plan: %d"
		% (hud._draft.document.count() - before))
	assert(hud._draft.irrigation_zones().size() == 1, "and one zone kept with the drawing")
	# The page reports what it just did: the verdict the controller handed back.
	assert(hud.water_status_text().contains("Zone 1 will run"), hud.water_status_text())
	assert(hud._water_panel._zone_list.item_count == 1, "the page lists it")
	# Clearing the reported line leaves the page saying what the drawing holds.
	hud._water_panel.say("")
	assert(hud.water_status_text().contains("1 zone"), hud.water_status_text())
	_done(hud)


func test_watering_an_area_the_page_has_that_is_gone_says_so_rather_than_failing() -> void:
	var hud = _hud()
	hud._on_water_supply(120.0, 350.0)
	hud._on_water_area("bed#9999", Irrigation.SPRAY, 4.5, false)
	assert(hud.water_status_text().contains("not there any more"), hud.water_status_text())
	assert(hud._draft.irrigation_zones().is_empty(), "and nothing was laid out")
	_done(hud)


func test_watering_with_no_supply_stated_is_refused_and_says_so() -> void:
	var hud = _hud()
	var row: Dictionary = hud._draft.waterable_areas()[0]
	hud._on_water_area(String(row["key"]), Irrigation.SPRAY, 4.5, false)
	assert(hud.water_status_text().contains("supply has not been stated"), hud.water_status_text())
	assert(hud._draft.document.count() == 1, "and the bed is alone on the drawing")
	_done(hud)


func test_taking_the_zone_off_through_the_page_takes_its_heads_with_it() -> void:
	var hud = _hud()
	hud._on_water_supply(120.0, 350.0)
	var row: Dictionary = hud._draft.waterable_areas()[0]
	hud._on_water_area(String(row["key"]), Irrigation.SPRAY, 4.5, false)
	var before: int = hud._draft.document.count()
	hud._on_water_remove(1)
	assert(hud._draft.irrigation_zones().is_empty(), "the zone is gone")
	assert(hud._draft.document.count() == before - 9, "and its nine heads with it: %d"
		% (before - hud._draft.document.count()))
	assert(hud.water_status_text().contains("off the drawing"), hud.water_status_text())
	_done(hud)


func test_the_menu_line_reports_the_supply_and_the_zones() -> void:
	var hud = _hud()
	assert(hud._water_text().contains("nothing on this drawing is watered yet"),
		hud._water_text())
	assert(hud._water_text().contains("no supply stated"), hud._water_text())
	hud._on_water_supply(120.0, 350.0)
	var row: Dictionary = hud._draft.waterable_areas()[0]
	hud._on_water_area(String(row["key"]), Irrigation.SPRAY, 4.5, false)
	assert(hud._water_text().contains("supply: 120 L/min at 350 kPa"), hud._water_text())
	assert(hud._water_text().contains("every zone runs off the supply"), hud._water_text())
	_done(hud)