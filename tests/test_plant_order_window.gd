extends Node
## The nursery-order page: what it is handed, what it says, and the one thing pressing it announces.
##
## The page owns no plan of its own and writes nothing itself, so every one of these is a bare `.new()`
## with no window server, no drawing and no scene - which is the point of the arrangement.

const WindowScript := preload("res://scripts/plant_order_window.gd")
const OrderScript := preload("res://scripts/biz/plant_order.gd")
const BookScript := preload("res://scripts/biz/cost_book.gd")
const ItemScript := preload("res://scripts/biz/cost_item.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")
const DeskScript := preload("res://scripts/biz/job_desk.gd")
const EstimateScript := preload("res://scripts/biz/estimate.gd")
const LineScript := preload("res://scripts/biz/estimate_line.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")

const SEED := "res://data/biz/costbook.json"
const TREE_ITEM := &"plant-tree-50mm"
const PERENNIAL_ITEM := &"plant-perennial-1g"


func _book() -> CostBook:
	var read: Dictionary = BookScript.load_from(SEED)
	assert(bool(read["ok"]), "the starter book loads: %s" % String(read["reason"]))
	return read["book"]


func _two_nursery_book() -> CostBook:
	var book: CostBook = BookScript.make(1, "2026-01-01")
	var tree: CostItem = ItemScript.make(TREE_ITEM, "Tree, 50 mm caliper, installed", &"EACH", 14500)
	tree.supplier = &"Greenwood Nursery"
	book.add_item(tree)
	var perennial: CostItem = ItemScript.make(
		PERENNIAL_ITEM, "Perennial, 1 gallon, installed", &"EACH", 1200
	)
	perennial.supplier = &"Valley Perennials"
	book.add_item(perennial)
	return book


func _row(species: String, count: int, botanical: String, category: int, cultivar: String = "",
		common: String = "", spread_cm: int = 0) -> Dictionary:
	return {
		"id": StringName(species), "count": count, "botanical_name": botanical,
		"common_name": common, "cultivar": cultivar, "category": category,
		"category_name": String(SpeciesScript.CATEGORY_NAMES.get(category, "")),
		"spread_cm": spread_cm, "height_cm": 0,
	}


func _maple(count: int = 3) -> Dictionary:
	return _row("acer-rubrum-autumn-blaze", count, "Acer rubrum", SpeciesScript.TREE,
		"Autumn Blaze", "Red maple", 900)


func _hosta(count: int = 12) -> Dictionary:
	return _row("hosta-plantaginea", count, "Hosta plantaginea", SpeciesScript.PERENNIAL, "", "", 60)


func _plan(rows: Array = [], book: CostBook = null) -> Dictionary:
	return OrderScript.plan(
		rows if not rows.is_empty() else [_maple(), _hosta()],
		book if book != null else _book()
	)


func _desk() -> DeskScript:
	var desk: DeskScript = DeskScript.new()
	desk.make_job_from(_estimate())
	return desk


func _estimate(estimate_id: String = "E1") -> EstimateScript:
	var estimate: EstimateScript = EstimateScript.new(estimate_id)
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


## A page built and pointed at a desk, with a plan on it and a nursery named: the state every test
## below is a variation on.
func _page(with_desk: bool = true) -> WindowScript:
	var page: WindowScript = WindowScript.new()
	page.build()
	page.bind(_desk() if with_desk else null)
	page.set_plan(_plan())
	page.set_supplier("Greenwood Nursery")
	return page


# --- building the page -------------------------------------------------------------------------


func test_building_the_page_takes_it_off_the_screen() -> void:
	var page: WindowScript = WindowScript.new()
	page.build()
	assert(not page.visible, "a window defaults to visible; building ends in hide()")
	page.free()


func test_building_the_page_twice_builds_it_once() -> void:
	var page: WindowScript = WindowScript.new()
	page.build()
	var first: Control = page.get_node("Scroll/Column") as Control
	page.build()
	assert(page.get_node("Scroll/Column") == first, "the same column, not a second one")
	assert(page.get_child_count() == 1, "and one child: %d" % page.get_child_count())
	page.free()


func test_the_page_has_the_controls_a_page_like_this_has() -> void:
	var page: WindowScript = WindowScript.new()
	page.build()
	for wanted: String in ["Column", "Heading", "Explanation", "WhoRow", "JobOption", "Supplier",
			"Lines", "Problems", "Summary", "Hint", "OrderButton", "CloseButton", "Status"]:
		assert(page.find_child(wanted, true, false) != null, "%s is on the page" % wanted)
	page.free()


func test_only_the_nursery_field_is_built_with_a_keyboard_of_its_own() -> void:
	var page: WindowScript = WindowScript.new()
	page.build()
	assert(page.rows_are_keyboard_free(), "the buttons and the lists take no key")
	assert(page.list_is_keyboard_free(), "the plant list is not a keyboard surface")
	var field: LineEdit = page.find_child("Supplier", true, false) as LineEdit
	assert(field != null and field.focus_mode != Control.FOCUS_NONE, "the one field is typeable")
	page.free()


# --- what it is handed -------------------------------------------------------------------------


func test_an_empty_plan_says_nothing_is_planted_rather_than_nothing_to_pay() -> void:
	var page: WindowScript = WindowScript.new()
	page.build()
	assert(page.line_count() == 0, "no rows")
	assert(page.order_hint() == WindowScript.NOTHING_PLANTED, page.order_hint())
	page.free()


func test_the_rows_are_the_plans_own_rows() -> void:
	var page: WindowScript = _page()
	var planned: Dictionary = _plan()
	assert(page.line_count() == (planned["lines"] as Array).size(), "one row per kind")
	assert(page.line_texts() == OrderScript.plan_rows(planned), "and they are the plan's own sentences")
	page.free()


func test_the_list_is_only_written_when_it_changes() -> void:
	var page: WindowScript = _page()
	assert(not page.show_lines(page.line_texts()), "writing the same list again writes nothing")
	assert(page.show_lines(["1 x something else"]), "a different list is written")
	assert(page.line_count() == 1, "and it replaced what was there")
	page.free()


func test_a_kind_the_book_cannot_price_is_on_the_page_and_says_why() -> void:
	var page: WindowScript = WindowScript.new()
	page.build()
	page.bind(_desk())
	page.set_plan(OrderScript.plan([_maple()], BookScript.make(1, "2026-01-01")))
	assert(page.line_count() == 1, "the kind is still listed")
	assert(page.problem_count() == 1, "and the reason is beside it")
	assert(page.problem_texts()[0].contains("Acer rubrum"), page.problem_texts()[0])
	page.free()


func test_the_summary_is_the_plans_own_sentence() -> void:
	var page: WindowScript = _page()
	assert(page.summary_text() == OrderScript.summary(_plan()), page.summary_text())
	page.free()


func test_being_handed_a_plan_announces_nothing() -> void:
	var page: WindowScript = WindowScript.new()
	page.build()
	var heard: Array = []
	page.order_requested.connect(func(_job: String, _who: String) -> void:
		heard.append("ordered"))
	page.set_plan(_plan())
	page.set_supplier("Greenwood Nursery")
	assert(heard.is_empty(), "reading a plan is not ordering one")
	page.free()


# --- the job and the nursery -------------------------------------------------------------------


func test_the_picker_lists_the_jobs_the_desk_has() -> void:
	var page: WindowScript = _page()
	assert(page.job_ids().size() == 1, "the desk's one job")
	assert(page.selected_job() == page.job_ids()[0], "and it is the one chosen")
	page.free()


func test_a_job_the_page_does_not_have_cannot_be_chosen() -> void:
	var page: WindowScript = _page()
	assert(not page.choose_job("NOPE"), "and it is refused rather than silently ignored")
	page.free()


func test_a_page_with_no_desk_says_which_job_is_missing() -> void:
	var page: WindowScript = _page(false)
	assert(page.job_ids().is_empty(), "no jobs to pick")
	assert(page.order_hint() == WindowScript.NO_JOB, page.order_hint())
	assert(not page.order_enabled(), "and nothing can be written")
	page.free()


func test_typing_a_nursery_moves_the_line_before_the_button() -> void:
	var page: WindowScript = _page()
	page.set_supplier("")
	assert(page.order_hint() == WindowScript.NO_SUPPLIER, page.order_hint())
	page.set_supplier("Valley Perennials")
	assert(page.order_hint().contains("Valley Perennials"), page.order_hint())
	page.free()


func test_the_hint_counts_the_orders_the_writing_would_make() -> void:
	var page: WindowScript = WindowScript.new()
	page.build()
	page.bind(_desk())
	page.set_plan(_plan([_maple(), _hosta()], _two_nursery_book()))
	page.set_supplier("")
	var hint: String = page.order_hint()
	assert(hint.begins_with("2 draft orders: "), hint)
	assert(hint.contains("Greenwood Nursery (1 kind)"), hint)
	assert(hint.contains("Valley Perennials (1 kind)"), hint)
	page.free()


func test_the_order_button_is_dead_until_there_is_a_job_a_nursery_and_something_to_price() -> void:
	var page: WindowScript = WindowScript.new()
	page.build()
	page.bind(_desk())
	page.set_plan({})
	assert(not page.order_enabled(), "nothing planted, nothing to order")
	page.set_plan(_plan())
	assert(not page.order_enabled(), "no nursery named")
	page.set_supplier("Greenwood Nursery")
	assert(page.order_enabled(), "now there is something to write")
	page.free()


func test_a_plan_the_book_cannot_price_cannot_be_ordered() -> void:
	var page: WindowScript = WindowScript.new()
	page.build()
	page.bind(_desk())
	page.set_plan(OrderScript.plan([_maple()], BookScript.make(1, "2026-01-01")))
	page.set_supplier("Greenwood Nursery")
	assert(not page.order_enabled(), "a half-priced order is not written")
	assert(page.order_hint() == WindowScript.NOT_ORDERABLE, page.order_hint())
	page.free()


# --- what pressing it announces -----------------------------------------------------------------


func test_pressing_the_button_announces_the_job_and_the_nursery() -> void:
	var page: WindowScript = _page()
	var heard: Array = []
	page.order_requested.connect(func(job_id: String, who: String) -> void:
		heard.append([job_id, who]))
	page._on_order()
	assert(heard.size() == 1, "one announcement")
	assert(heard[0] == [page.selected_job(), "Greenwood Nursery"], str(heard[0]))
	page.free()


func test_pressing_it_when_it_cannot_order_announces_nothing_and_says_why() -> void:
	var page: WindowScript = WindowScript.new()
	page.build()
	page.bind(_desk())
	page.set_plan(_plan())
	var heard: Array = []
	page.order_requested.connect(func(_job: String, _who: String) -> void:
		heard.append("ordered"))
	page._on_order()
	assert(heard.is_empty(), "nothing was announced")
	assert(not page.status_text().is_empty(), "and the page says what is missing: %s" % page.status_text())
	page.free()


func test_closing_the_page_by_the_button_or_by_the_x_announces_the_same_thing() -> void:
	var page: WindowScript = _page()
	var heard: Array = []
	page.closed.connect(func() -> void:
		heard.append("closed"))
	page.request_close()
	page._on_close_requested()
	assert(heard.size() == 2, "both ways announce it: %d" % heard.size())
	assert(not page.visible, "and the page is off the screen")
	page.free()


func test_pointing_the_page_at_another_desk_reads_its_jobs_again() -> void:
	var page: WindowScript = _page()
	page.bind(DeskScript.new())
	assert(page.job_ids().is_empty(), "the new desk has nothing on it")
	assert(page.status_text() == WindowScript.NO_JOB, page.status_text())
	page.free()


func test_a_page_with_no_desk_at_all_is_still_a_page() -> void:
	var page: WindowScript = WindowScript.new()
	page.build()
	page.bind(null)
	assert(page.job_ids().is_empty(), "nothing to pick")
	assert(page.line_count() == 0, "and with no plan, nothing to show")
	page.free()