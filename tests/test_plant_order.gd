extends Node
## The nursery order: the drawing's planting list and the cost book turned into what to buy, from whom.
##
## These tests hold down the two decisions the module is made of - **the book prices the plant and a
## person names the nursery**, and **a plant the book cannot price is refused by name rather than
## ordered at nothing** - and the one thing the order is allowed to be: a **draft** that commits a job
## to nothing until somebody issues it.

const PlantOrderScript := preload("res://scripts/biz/plant_order.gd")
const BookScript := preload("res://scripts/biz/cost_book.gd")
const ItemScript := preload("res://scripts/biz/cost_item.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")
const OrderScript := preload("res://scripts/biz/purchase_order.gd")
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


## A book with two nurseries on it, because the starter book names nobody: a business states who it buys
## from, and that is the fact this module exists to honour.
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


## A planting-list row, in the shape `PlantPlacement.schedule` hands over - the machine-readable
## category beside the printed one, so an order never has to match on a display string.
func _row(species: String, count: int, botanical: String, category: int, cultivar: String = "",
		common: String = "", spread_cm: int = 0) -> Dictionary:
	return {
		"id": StringName(species),
		"count": count,
		"botanical_name": botanical,
		"common_name": common,
		"cultivar": cultivar,
		"category": category,
		"category_name": String(SpeciesScript.CATEGORY_NAMES.get(category, "")),
		"spread_cm": spread_cm,
		"height_cm": 0,
	}


func _maple(count: int = 3) -> Dictionary:
	return _row("acer-rubrum-autumn-blaze", count, "Acer rubrum", SpeciesScript.TREE,
		"Autumn Blaze", "Red maple", 900)


func _hosta(count: int = 12) -> Dictionary:
	return _row("hosta-plantaginea", count, "Hosta plantaginea", SpeciesScript.PERENNIAL,
		"", "Plantain lily", 60)


func _nameless(count: int = 2) -> Dictionary:
	return {
		"id": &"", "count": count, "botanical_name": "no species recorded", "common_name": "",
		"cultivar": "", "category": -1, "category_name": "", "spread_cm": 0, "height_cm": 0,
	}


func _job_desk() -> DeskScript:
	var desk: DeskScript = DeskScript.new()
	desk.make_job_from(_estimate())
	return desk


func _estimate(estimate_id: String = "E1") -> EstimateScript:
	var estimate: EstimateScript = EstimateScript.new(estimate_id)
	estimate.customer = {"name": "Smith, back garden"}
	var line: LineScript = LineScript.new()
	line.cost_code = PlantOrderScript.PLANTING_CODE
	line.kind = ItemScript.MATERIAL
	line.quantity_milli = 10000
	line.unit = &"EACH"
	line.unit_cost = MoneyScript.of(750)
	line.unit_price = MoneyScript.of(1500)
	estimate.lines.append(line)
	return estimate


func _job_id(desk: DeskScript) -> String:
	assert(desk.jobs.size() == 1, "the desk has the one job")
	return desk.jobs[0].id


# --- what prices a plant ------------------------------------------------------------------------


func test_a_tree_and_a_fern_are_priced_by_their_own_items() -> void:
	assert(PlantOrderScript.category_item(SpeciesScript.TREE) == TREE_ITEM, "a tree")
	assert(PlantOrderScript.category_item(SpeciesScript.FERN) == PERENNIAL_ITEM, "and a fern")
	assert(PlantOrderScript.category_item(SpeciesScript.TREE) != PERENNIAL_ITEM,
		"a tree and a fern are not the same money")


func test_a_kind_of_plant_nobody_has_an_opinion_about_is_answered_with_nothing() -> void:
	assert(PlantOrderScript.category_item(-1).is_empty(), "no category, no suggestion")
	assert(PlantOrderScript.category_item(999).is_empty(), "and a category that is not one")


func test_every_category_a_plant_can_be_is_priced_by_the_starter_book() -> void:
	var book: CostBook = _book()
	for category: int in SpeciesScript.CATEGORY_NAMES.keys():
		var item_id: StringName = PlantOrderScript.category_item(int(category))
		assert(not item_id.is_empty(),
			"%s has a suggestion" % String(SpeciesScript.CATEGORY_NAMES[category]))
		assert(book.has_item(item_id), "and %s is in the starter book" % String(item_id))


func test_the_office_own_item_beats_the_programs_suggestion() -> void:
	var book: CostBook = _book()
	var chosen: Dictionary = {&"acer-rubrum-autumn-blaze": PERENNIAL_ITEM}
	var planned: Dictionary = PlantOrderScript.plan([_maple()], book, chosen)
	assert((planned["lines"][0] as Dictionary)["item_id"] == PERENNIAL_ITEM,
		"the office's answer is the one used")


# --- the plan ----------------------------------------------------------------------------------


func test_a_line_is_the_count_at_the_items_rate() -> void:
	var book: CostBook = _book()
	var rate: Money = book.item(TREE_ITEM).rate
	var planned: Dictionary = PlantOrderScript.plan([_maple(3)], book)
	assert(planned["lines"].size() == 1, "one kind, one line")
	var held: Dictionary = planned["lines"][0]
	assert(int(held["count"]) == 3, "three maples")
	assert((held["amount"] as MoneyScript).cents == rate.cents * 3, "at the book's rate, three times")
	assert((planned["total"] as MoneyScript).cents == rate.cents * 3, "and that is the total")


func test_a_count_travels_as_thousandths_so_it_is_not_converted_twice() -> void:
	var planned: Dictionary = PlantOrderScript.plan([_maple(7)], _book())
	assert(int((planned["lines"][0] as Dictionary)["quantity_milli"]) == 7000,
		"seven plants is seven thousand of the unit")


func test_a_line_carries_the_item_the_nursery_and_the_words_a_person_reads() -> void:
	var book: CostBook = _two_nursery_book()
	var held: Dictionary = PlantOrderScript.plan([_maple(2)], book)["lines"][0]
	assert(held["item_id"] == TREE_ITEM, "the item that prices it")
	assert(String(held["item_name"]) == "Tree, 50 mm caliper, installed", "its name")
	assert(String(held["supplier"]) == "Greenwood Nursery", "and the nursery the book states")
	assert(String(held["unit"]) == "EACH", "the unit it is bought in")
	var words: String = PlantOrderScript.row_words(held)
	assert(words == "2 x %s - %s" % [String(held["words"]), String(held["price_words"])], words)
	assert(String(held["price_words"]).begins_with("2 at "), String(held["price_words"]))
	assert(String(held["price_words"]).ends_with("(Tree, 50 mm caliper, installed)"),
		String(held["price_words"]))


func test_the_plant_is_named_the_way_a_planting_plan_names_it() -> void:
	var held: Dictionary = PlantOrderScript.plan([_maple()], _book())["lines"][0]
	assert(String(held["words"]) == "Acer rubrum 'Autumn Blaze' (Red maple), 9.0 m",
		String(held["words"]))


func test_a_plant_the_book_cannot_price_is_named_and_kept_on_the_list() -> void:
	var book: CostBook = BookScript.make(1, "2026-01-01")
	var planned: Dictionary = PlantOrderScript.plan([_maple()], book)
	assert(planned["lines"].size() == 1, "the kind is still on the plan")
	assert(not bool((planned["lines"][0] as Dictionary)["priced"]), "and it is not priced")
	assert(int(planned["unpriced"]) == 1, "one kind nothing can price")
	assert(planned["problems"].size() == 1, "said out loud once")
	assert(String(planned["problems"][0]).contains(String((planned["lines"][0] as Dictionary)["words"])),
		String(planned["problems"][0]))


func test_a_kind_the_program_has_no_item_for_says_which_kind_is_missing() -> void:
	var book: CostBook = _book()
	var row: Dictionary = _row("unknown-thing", 1, "Mysteria", 999)
	var planned: Dictionary = PlantOrderScript.plan([row], book)
	assert(int(planned["unpriced"]) == 1, "nothing prices it")
	assert(String(planned["problems"][0]).contains("999") == false, "and the message is not a number")
	assert(String((planned["lines"][0] as Dictionary)["price_words"]).contains("plant of that kind"),
		String((planned["lines"][0] as Dictionary)["price_words"]))


func test_a_plant_with_no_species_cannot_be_priced_and_says_so_that_way() -> void:
	var planned: Dictionary = PlantOrderScript.plan([_nameless(4)], _book())
	assert(int(planned["plants"]) == 4, "the four are counted")
	assert(int(planned["unpriced"]) == 1, "and none of them can be priced")
	assert(String((planned["lines"][0] as Dictionary)["price_words"]) ==
		"no species recorded, so there is nothing to price it with",
		String((planned["lines"][0] as Dictionary)["price_words"]))


func test_a_total_that_leaves_a_kind_out_is_not_a_total() -> void:
	var book: CostBook = _book()
	var planned: Dictionary = PlantOrderScript.plan([_maple(3), _nameless(1)], book)
	assert((planned["total"] as MoneyScript).is_valid() == false,
		"a total with a hole in it is not a total")
	assert((planned["priced_total"] as MoneyScript).is_valid(), "but what was priced is known")
	assert((planned["priced_total"] as MoneyScript).cents == book.item(TREE_ITEM).rate.cents * 3,
		"and it is the priced lines")


func test_the_summary_says_how_much_is_priced_and_what_is_not() -> void:
	var book: CostBook = _book()
	var whole: Dictionary = PlantOrderScript.plan([_maple(3), _hosta(12)], book)
	var line: String = PlantOrderScript.summary(whole)
	assert(int(whole["unpriced"]) == 0, "everything is priced")
	assert(line.contains("2 plants in 2 kinds") == false, "the count of plants is not the count of kinds")
	assert(line.begins_with("%d plants in %d kinds: " % [int(whole["plants"]), 2]), line)
	assert(line.contains((whole["total"] as MoneyScript).format_with_currency()), line)
	var holed: Dictionary = PlantOrderScript.plan([_maple(3), _nameless(1)], book)
	assert(PlantOrderScript.summary(holed).contains("not the whole order"),
		PlantOrderScript.summary(holed))
	assert(PlantOrderScript.summary(holed).contains("1 kind the book cannot price"),
		PlantOrderScript.summary(holed))


func test_an_empty_planting_says_nothing_is_planted_rather_than_nothing_costs() -> void:
	var planned: Dictionary = PlantOrderScript.plan([], _book())
	assert(PlantOrderScript.summary(planned) == "nothing is planted on this drawing",
		PlantOrderScript.summary(planned))
	assert(planned["lines"].is_empty(), "and there are no lines")
	assert(plan_rows_are_empty(planned), "nor rows")


func plan_rows_are_empty(planned: Dictionary) -> bool:
	return PlantOrderScript.plan_rows(planned).is_empty()


func test_a_row_with_nothing_on_it_is_not_a_line() -> void:
	var planned: Dictionary = PlantOrderScript.plan([_maple(0), _hosta(-2)], _book())
	assert(planned["lines"].is_empty(), "a count of nothing is not something to buy")
	assert(int(planned["plants"]) == 0, "and it stands for no plants")


func test_the_plan_is_in_botanical_name_order_however_it_arrives() -> void:
	var planned: Dictionary = PlantOrderScript.plan([_hosta(1), _maple(1), _nameless(1)], _book())
	var named: Array[String] = []
	for held: Dictionary in planned["lines"]:
		named.append(String(held["words"]))
	assert(named.size() == 3, "three rows")
	assert(named[0].begins_with("Acer rubrum"), named[0])
	assert(named[1].begins_with("Hosta plantaginea"), named[1])
	assert(named[2].begins_with("no species recorded"), named[2])


func test_the_plan_says_how_many_plants_and_how_many_kinds() -> void:
	var planned: Dictionary = PlantOrderScript.plan([_maple(3), _hosta(12)], _book())
	assert(int(planned["plants"]) == 15, "fifteen plants")
	assert((planned["lines"] as Array).size() == 2, "in two kinds")
	assert(int(planned["priced"]) == 2, "both priced")


func test_the_describe_line_names_the_book_it_was_priced_from() -> void:
	var book: CostBook = _book()
	var planned: Dictionary = PlantOrderScript.plan([_maple(3)], book)
	var line: String = PlantOrderScript.describe(planned, book)
	assert(line.contains(book.describe()), line)
	assert(line.begins_with(PlantOrderScript.summary(planned)), line)


# --- what to buy, from whom ---------------------------------------------------------------------


func test_the_lines_group_by_the_nursery_they_come_from() -> void:
	var book: CostBook = _two_nursery_book()
	var planned: Dictionary = PlantOrderScript.plan([_maple(2), _hosta(12)], book)
	var groups: Array[Dictionary] = PlantOrderScript.by_supplier(planned["lines"])
	assert(groups.size() == 2, "two nurseries, two orders")
	assert(String(groups[0]["supplier"]) == "Greenwood Nursery", String(groups[0]["supplier"]))
	assert((groups[0]["lines"] as Array).size() == 1, "the trees")
	assert(String(groups[1]["supplier"]) == "Valley Perennials", String(groups[1]["supplier"]))
	assert((groups[1]["lines"] as Array).size() == 1, "and the perennials")


func test_a_line_the_book_names_no_nursery_for_takes_the_one_the_person_stated() -> void:
	var planned: Dictionary = PlantOrderScript.plan([_maple(2)], _book())
	var groups: Array[Dictionary] = PlantOrderScript.by_supplier(planned["lines"], "One Big Grower")
	assert(groups.size() == 1, "one order")
	assert(String(groups[0]["supplier"]) == "One Big Grower", String(groups[0]["supplier"]))


func test_a_line_with_no_nursery_at_all_lands_in_the_group_nobody_is_addressed_to() -> void:
	var planned: Dictionary = PlantOrderScript.plan([_maple(2)], _book())
	var groups: Array[Dictionary] = PlantOrderScript.by_supplier(planned["lines"])
	assert(groups.size() == 1, "one group")
	assert(String(groups[0]["supplier"]).is_empty(), "and it has nobody to go to")


func _plan_two_nurseries() -> Dictionary:
	return PlantOrderScript.plan([_maple(2), _hosta(12)], _two_nursery_book())


func test_writing_the_order_makes_a_draft_and_commits_the_job_to_nothing() -> void:
	var desk: DeskScript = _job_desk()
	var written: Dictionary = PlantOrderScript.write_orders(
		desk, _job_id(desk), _plan_two_nurseries(), ""
	)
	assert(bool(written["ok"]), String(written["reason"]))
	var orders: Array = written["orders"]
	assert(orders.size() == 2, "one order per nursery: %d" % orders.size())
	for held: PurchaseOrder in orders:
		assert(held.state() == OrderScript.DRAFT, "a draft, not an order")
		assert(held.committed().cents == 0, "and nothing committed")
		assert(held.issued_at.is_empty(), "nobody has issued it")


func test_the_order_is_written_to_the_planting_phase() -> void:
	var desk: DeskScript = _job_desk()
	var written: Dictionary = PlantOrderScript.write_orders(
		desk, _job_id(desk), _plan_two_nurseries(), ""
	)
	for held: PurchaseOrder in written["orders"]:
		assert(held.cost_code == PlantOrderScript.PLANTING_CODE, String(held.cost_code))
		assert(held.job == _job_id(desk), "and against the job")


func test_the_order_carries_every_kind_on_its_own_line() -> void:
	var desk: DeskScript = _job_desk()
	var written: Dictionary = PlantOrderScript.write_orders(
		desk, _job_id(desk), _plan_two_nurseries(), ""
	)
	var written_lines := 0
	for held: PurchaseOrder in written["orders"]:
		written_lines += held.line_count()
	assert(written_lines == 2, "two kinds, two lines: %d" % written_lines)
	var order: PurchaseOrder = written["orders"][0]
	assert(order.ordered_milli(0) == 2000, "the count of the trees, in thousandths")


func test_nothing_is_issued_so_the_planting_phase_is_not_committed_yet() -> void:
	var desk: DeskScript = _job_desk()
	var job_id: String = _job_id(desk)
	PlantOrderScript.write_orders(desk, job_id, _plan_two_nurseries(), "")
	var report: JobCost = desk.cost_report(job_id)
	assert((report.totals()["committed"] as MoneyScript).cents == 0, "a draft commits nothing")
	var row: Dictionary = report.row_for(String(PlantOrderScript.PLANTING_CODE))
	assert((row["committed"] as MoneyScript).cents == 0, "and the planting phase is untouched")


func test_a_plan_with_a_kind_the_book_cannot_price_writes_nothing_at_all() -> void:
	var desk: DeskScript = _job_desk()
	var planned: Dictionary = PlantOrderScript.plan([_maple(2), _nameless(1)], _book())
	var written: Dictionary = PlantOrderScript.write_orders(desk, _job_id(desk), planned, "Grower")
	assert(not bool(written["ok"]), "a half-written order looks finished, so none is written")
	assert((written["orders"] as Array).is_empty(), "and nothing is on the desk")
	assert(desk.purchase_orders.is_empty(), "nothing at all")
	assert(String(written["reason"]).contains("cannot be ordered"), String(written["reason"]))


func test_a_job_the_desk_does_not_have_cannot_be_ordered_for() -> void:
	var desk: DeskScript = _job_desk()
	var written: Dictionary = PlantOrderScript.write_orders(desk, "NOPE", _plan_two_nurseries(), "")
	assert(not bool(written["ok"]), "there is no such job")
	assert(String(written["reason"]).contains("NOPE"), String(written["reason"]))


func test_a_plan_with_nothing_planted_writes_nothing() -> void:
	var desk: DeskScript = _job_desk()
	var written: Dictionary = PlantOrderScript.write_orders(
		desk, _job_id(desk), PlantOrderScript.plan([], _book()), ""
	)
	assert(not bool(written["ok"]), "there is nothing to order")
	assert(desk.purchase_orders.is_empty(), "and nothing is on the desk")


func test_a_nursery_nobody_named_is_refused_by_name() -> void:
	var desk: DeskScript = _job_desk()
	var written: Dictionary = PlantOrderScript.write_orders(
		desk, _job_id(desk), PlantOrderScript.plan([_maple(2)], _book()), ""
	)
	assert(not bool(written["ok"]), "an order addressed to nobody is not written")
	assert(String(written["reason"]).contains("which nursery"), String(written["reason"]))
	assert(desk.purchase_orders.is_empty(), "and nothing is on the desk")


func test_two_nurseries_are_two_orders_with_their_own_totals() -> void:
	var desk: DeskScript = _job_desk()
	var written: Dictionary = PlantOrderScript.write_orders(
		desk, _job_id(desk), _plan_two_nurseries(), ""
	)
	var book: CostBook = _two_nursery_book()
	var trees: PurchaseOrder = null
	var perennials: PurchaseOrder = null
	for held: PurchaseOrder in written["orders"]:
		if held.supplier == "Greenwood Nursery":
			trees = held
		elif held.supplier == "Valley Perennials":
			perennials = held
	assert(trees != null and perennials != null, "one each")
	assert(trees.ordered_total().cents == book.item(TREE_ITEM).rate.cents * 2, "the trees")
	assert(perennials.ordered_total().cents == book.item(PERENNIAL_ITEM).rate.cents * 12, "the ferns")


func test_what_was_written_is_said_in_one_line_naming_each_order() -> void:
	var desk: DeskScript = _job_desk()
	var written: Dictionary = PlantOrderScript.write_orders(
		desk, _job_id(desk), _plan_two_nurseries(), ""
	)
	var line: String = PlantOrderScript.orders_words(written["orders"])
	for held: PurchaseOrder in written["orders"]:
		assert(line.contains(held.number), line)
		assert(line.contains(held.supplier), line)
	assert(PlantOrderScript.orders_words([]) == "no order was written", "and nothing says so")


func test_a_written_order_survives_a_round_trip_through_the_desk() -> void:
	var desk: DeskScript = _job_desk()
	var job_id: String = _job_id(desk)
	PlantOrderScript.write_orders(desk, job_id, _plan_two_nurseries(), "")
	var data: Dictionary = desk.to_dict()
	var read: DeskScript = DeskScript.from_dict(data)
	assert(read.purchase_orders.size() == 2, "both orders come back")
	assert(read.purchase_orders_for(job_id).size() == 2, "and they are still the job's")
	assert(read.purchase_order(desk.purchase_orders[0].id) != null, "found by their own id")


func test_the_plan_is_a_function_of_its_input_and_nothing_is_cached() -> void:
	var book: CostBook = _book()
	var first: Dictionary = PlantOrderScript.plan([_maple(3)], book)
	var second: Dictionary = PlantOrderScript.plan([_maple(3)], book)
	assert((first["total"] as MoneyScript).cents == (second["total"] as MoneyScript).cents,
		"the same planting is the same money")
	book.erase_item(TREE_ITEM)
	var third: Dictionary = PlantOrderScript.plan([_maple(3)], book)
	assert(int(third["unpriced"]) == 1, "and a book that loses the item prices nothing")