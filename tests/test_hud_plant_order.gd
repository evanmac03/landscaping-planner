extends Node
## The nursery order, joined to the Plant menu, to the page, to the job desk and to the price list.
##
## The module is tested in `test_plant_order.gd` and the page in `test_plant_order_window.gd`; this is
## the part that only exists when they are put together - that the Plant menu offers the order, that the
## page is filled from **the yard** rather than from itself, that the write lands on the job desk as
## drafts, and that a page left open keeps up with plants being put down behind it.
##
## No node enters a tree, so no `_ready` runs, no dialog is built and no window is ever shown:
## `popup_centered` needs a screen and a test does not have one, which is why filling the page is its
## own function.

const HudScript := preload("res://scripts/hud.gd")
const ViewControllerScript := preload("res://scripts/view_controller.gd")
const PlacementScript := preload("res://scripts/plant_placement.gd")
const CatalogueScript := preload("res://scripts/plant_catalogue.gd")
const OrderScript := preload("res://scripts/biz/plant_order.gd")
const OrderWindowScript := preload("res://scripts/plant_order_window.gd")
const EstimateWindowScript := preload("res://scripts/estimate_window.gd")
const DeskScript := preload("res://scripts/biz/job_desk.gd")
const EstimateScript := preload("res://scripts/biz/estimate.gd")
const LineScript := preload("res://scripts/biz/estimate_line.gd")
const ItemScript := preload("res://scripts/biz/cost_item.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")
const PurchaseScript := preload("res://scripts/biz/purchase_order.gd")

const SEED := "res://data/plants/nursery_list.json"
## A tree and a perennial, because a nursery order prices the two differently.
const MAPLE := &"acer-rubrum-autumn-blaze"
const RUDBECKIA := &"rudbeckia-fulgida-goldsturm"
const NURSERY := "Greenwood Nursery"


# --- helpers ---------------------------------------------------------------------------------


func _catalogue() -> PlantCatalogue:
	var read: Dictionary = CatalogueScript.load_from(SEED)
	assert(bool(read["ok"]), "the shipped list loads: %s" % String(read["reason"]))
	return read["catalogue"]


func _yard() -> Node3D:
	var yard := Node3D.new()
	yard.name = "Yard"
	return yard


## A yard with one tree and one perennial standing in it.
func _stocked_yard() -> Node3D:
	var yard: Node3D = _yard()
	var catalogue: PlantCatalogue = _catalogue()
	PlacementScript.place(catalogue, MAPLE, yard, Vector3.ZERO)
	PlacementScript.place(catalogue, RUDBECKIA, yard, Vector3(3.0, 0.0, 0.0))
	return yard


func _hud(yard: Node3D = null, with_book: bool = true) -> Node:
	var hud: Node = HudScript.new()
	hud._plants = _catalogue()
	if yard != null:
		var view: ViewController = ViewControllerScript.new()
		view.yard = yard
		# Added as a child so freeing the HUD frees the view with it.
		hud.add_child(view)
		hud.view_controller = view
	if with_book:
		# The price list the plants are bought at is the estimator's, so the page is given the
		# estimator. It is added as a child so freeing the HUD frees it too.
		var estimate: EstimateWindow = EstimateWindowScript.new()
		hud.add_child(estimate)
		estimate.build()
		hud._estimate_window = estimate
	return hud


func _desk() -> DeskScript:
	var desk: DeskScript = DeskScript.new()
	desk.make_job_from(_estimate())
	return desk


func _estimate() -> EstimateScript:
	var estimate: EstimateScript = EstimateScript.new("E1")
	estimate.customer = {"name": "Smith, back garden"}
	var line: LineScript = LineScript.new()
	line.cost_code = OrderScript.PLANTING_CODE
	line.kind = ItemScript.MATERIAL
	line.quantity_milli = 10000
	line.unit = &"EACH"
	line.unit_cost = MoneyScript.of(750)
	line.unit_price = MoneyScript.of(1500)
	estimate.lines.append(line)
	return estimate


# --- the menu --------------------------------------------------------------------------------


func test_the_plant_menu_offers_the_nursery_order() -> void:
	var entries: Array[Dictionary] = HudScript.plant_items()
	var order: Dictionary = {}
	for entry: Dictionary in entries:
		if String(entry.get("id", "")) == "plant.order":
			order = entry
	assert(not order.is_empty(), "the Plant menu offers the order")
	assert(String(order["label"]) == "Order the plants for this drawing...", String(order["label"]))
	assert(String(order["method"]) == "_menu_plant_order_window", String(order["method"]))
	assert(StringName(order["needs"]) == HudScript.NEEDS_DRAFT, "which needs a drawing to plant")
	var hud := HudScript.new()
	assert(hud.has_method("_menu_plant_order_window"), "and the method it names is there")
	assert(hud.has_method("open_plant_order_window") and hud.has_method("is_plant_order_window_open"),
		"beside the pair that opens and reports on the page")
	assert(hud.has_method("write_plant_order"), "and the write, reachable without a page")
	hud.free()


# --- what the drawing plants -----------------------------------------------------------------


func test_a_scene_with_no_yard_has_nothing_to_order() -> void:
	var hud := _hud()
	var planned: Dictionary = hud.plant_order_plan()
	assert((planned["lines"] as Array).is_empty(), "no yard, nothing planted")
	hud._build_plant_order_window()
	assert(hud._plant_order_window != null, "the page is built")
	assert(not hud.is_plant_order_window_open(), "and not shown: a form nobody opened is not over the plan")
	hud._fill_plant_order_window()
	assert(hud._plant_order_window.line_count() == 0, "with nothing on it")
	assert(hud._plant_order_window.order_hint() == OrderWindowScript.NOTHING_PLANTED,
		hud._plant_order_window.order_hint())
	hud.free()


func test_the_plan_is_the_yard_s_planting_priced_from_the_price_list() -> void:
	var yard: Node3D = _stocked_yard()
	var hud := _hud(yard)
	var planned: Dictionary = hud.plant_order_plan()
	assert((planned["lines"] as Array).size() == 2, "two kinds standing: %d" % (planned["lines"] as Array).size())
	assert(int(planned["plants"]) == 2, "two plants")
	assert(int(planned["unpriced"]) == 0, "and the price list prices both: %s" % str(planned["problems"]))
	assert(String((planned["lines"][0] as Dictionary)["words"]).begins_with("Acer rubrum"),
		String((planned["lines"][0] as Dictionary)["words"]))
	assert(String((planned["lines"][1] as Dictionary)["words"]).begins_with("Rudbeckia"),
		String((planned["lines"][1] as Dictionary)["words"]))
	hud.free()
	yard.free()


func test_the_page_is_filled_from_the_yard_rather_than_from_itself() -> void:
	var yard: Node3D = _stocked_yard()
	var hud := _hud(yard)
	hud._fill_plant_order_window()
	var planned: Dictionary = hud.plant_order_plan()
	assert(hud._plant_order_window.line_texts() == OrderScript.plan_rows(planned),
		str(hud._plant_order_window.line_texts()))
	assert(hud._plant_order_window.summary_text() == OrderScript.summary(planned),
		hud._plant_order_window.summary_text())
	assert(hud._plant_order_window.line_count() == 2, "two rows")
	hud.free()
	yard.free()


func test_building_the_page_twice_builds_it_once() -> void:
	var hud := _hud()
	hud._build_plant_order_window()
	var first: Node = hud._plant_order_window
	hud._build_plant_order_window()
	assert(hud._plant_order_window == first, "the same page, not a second one")
	hud.free()


# --- the write -------------------------------------------------------------------------------


func test_writing_the_order_puts_drafts_on_the_job_desk() -> void:
	var yard: Node3D = _stocked_yard()
	var hud := _hud(yard)
	var desk: DeskScript = _desk()
	hud._job_desk = desk
	var written: Dictionary = hud.write_plant_order(desk.jobs[0].id, NURSERY)
	assert(bool(written["ok"]), String(written["reason"]))
	assert(desk.purchase_orders.size() == 1, "one order: %d" % desk.purchase_orders.size())
	var order: PurchaseOrder = desk.purchase_orders[0]
	assert(order.state() == PurchaseScript.DRAFT, "a draft, not an order")
	assert(order.issued_at.is_empty(), "and nobody has issued it")
	assert(order.supplier == NURSERY, order.supplier)
	assert(order.line_count() == 2, "with both kinds on it: %d" % order.line_count())
	assert(order.cost_code == OrderScript.PLANTING_CODE, String(order.cost_code))
	# The desk is RefCounted and lets go of itself; the HUD did not adopt it.
	hud.free()
	yard.free()


func test_a_draft_moves_nothing_of_what_the_job_has_committed() -> void:
	var yard: Node3D = _stocked_yard()
	var hud := _hud(yard)
	var desk: DeskScript = _desk()
	hud._job_desk = desk
	var job_id: String = desk.jobs[0].id
	assert((desk.cost_report(job_id).totals()["committed"] as MoneyScript).cents == 0, "nothing yet")
	hud.write_plant_order(job_id, NURSERY)
	assert((desk.cost_report(job_id).totals()["committed"] as MoneyScript).cents == 0,
		"and a draft still commits nothing")
	hud.free()
	yard.free()


func test_the_page_asks_for_the_order_and_the_hud_writes_it() -> void:
	var yard: Node3D = _stocked_yard()
	var hud := _hud(yard)
	var desk: DeskScript = _desk()
	hud._job_desk = desk
	hud._fill_plant_order_window()
	assert(not hud._plant_order_window.order_enabled(), "no nursery named yet")
	hud._on_plant_order_requested(desk.jobs[0].id, NURSERY)
	assert(desk.purchase_orders.size() == 1, "the order is on the desk")
	assert(String(hud._plant_order_window.said()).begins_with("written, and waiting to be issued: "),
		hud._plant_order_window.said())
	assert(String(hud._plant_order_window.said()).contains(NURSERY), hud._plant_order_window.said())
	hud.free()
	yard.free()


func test_a_refusal_is_said_on_the_page_rather_than_thrown() -> void:
	var yard: Node3D = _stocked_yard()
	var hud := _hud(yard)
	hud._build_plant_order_window()
	hud._on_plant_order_requested("", NURSERY)
	assert(String(hud._plant_order_window.said()).contains("no job"), hud._plant_order_window.said())
	var desk: DeskScript = _desk()
	hud._job_desk = desk
	hud._on_plant_order_requested(desk.jobs[0].id, "")
	assert(String(hud._plant_order_window.said()).contains("which nursery"),
		hud._plant_order_window.said())
	assert(desk.purchase_orders.is_empty(), "and nothing reached the desk")
	hud.free()
	yard.free()


# --- the page while it is up -------------------------------------------------------------------


func test_a_page_left_open_keeps_up_with_plants_put_down_behind_it() -> void:
	var yard: Node3D = _stocked_yard()
	var hud := _hud(yard)
	hud._build_plant_order_window()
	hud._fill_plant_order_window()
	assert(hud._plant_order_window.line_count() == 2, "two kinds to begin with")
	PlacementScript.place(_catalogue(), MAPLE, yard, Vector3(6.0, 0.0, 0.0))
	hud._tick_plant_order_window()
	assert(hud._plant_order_window.line_count() == 2, "a page that is not up is not read again")
	hud._plant_order_window.visible = true
	hud._tick_plant_order_window()
	assert(String(hud._plant_order_window.line_texts()[0]).begins_with("2 x Acer rubrum"),
		String(hud._plant_order_window.line_texts()[0]))
	assert(hud._plant_order_window.line_count() == 2, "and still one row per kind: %d"
		% hud._plant_order_window.line_count())
	hud._plant_order_window.visible = false
	hud.free()
	yard.free()


func test_the_write_is_in_the_snapshot_the_page_is_read_from() -> void:
	# Writing an order moves what the desk holds, so the next refresh is drawn from something else.
	var yard: Node3D = _stocked_yard()
	var hud := _hud(yard)
	var desk: DeskScript = _desk()
	hud._job_desk = desk
	hud._build_plant_order_window()
	hud._fill_plant_order_window()
	var before: String = hud._plant_order_state
	hud.write_plant_order(desk.jobs[0].id, NURSERY)
	assert(hud._plant_order_state != before, "the page's own state has moved with the desk")
	hud.free()
	yard.free()