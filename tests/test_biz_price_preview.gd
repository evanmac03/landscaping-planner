extends Node
## The price preview: what a cost book change would do to the work already quoted (§12, the cost
## book panel's "preview of what it changes").
##
## The property this file exists for is the one the module is built around: **a cost book change does
## not move a quoted price** (REQ-B6, AC-B7). A preview recomputes what the work would *cost* and
## leaves the price that went to the customer exactly where it was, so what falls is the margin. The
## other two: **the preview's cost is the arithmetic the estimate would actually be priced at**, which
## a test checks by pricing a second estimate from the new book and comparing, and **nothing is
## written**, so an estimate can be looked at against a dozen price lists without moving.

const BookScript := preload("res://scripts/biz/cost_book.gd")
const ItemScript := preload("res://scripts/biz/cost_item.gd")
const EstimateScript := preload("res://scripts/biz/estimate.gd")
const LineScript := preload("res://scripts/biz/estimate_line.gd")
const ImportScript := preload("res://scripts/biz/book_import.gd")
const PreviewScript := preload("res://scripts/biz/price_preview.gd")
const StoreScript := preload("res://scripts/biz/store.gd")

const ROOT := "user://test_price_preview"
## A stated moment, so nothing in the test reads the clock.
const MAY := 1780000000


func _book() -> CostBook:
	var book: CostBook = BookScript.make(3, "2026-01-01")
	var mulch: CostItem = ItemScript.make(&"bed-mulch", "Bark mulch", &"CU_M", 5800)
	mulch.waste_ppm = 0
	mulch.cost_code = &"BEDS"
	mulch.supplier = &"GreenCo"
	book.add_item(mulch)
	var paver: CostItem = ItemScript.make(&"hard-paver-60", "Interlock paving, 60mm", &"SQ_FT", 325)
	paver.cost_code = &"HARDSCAPE"
	paver.supplier = &"StoneYard"
	book.add_item(paver)
	var labour: CostItem = ItemScript.make(&"crew-hour", "Landscape crew", &"HOUR", 4500, ItemScript.LABOR)
	labour.supplier = &"GreenCo"
	book.add_item(labour)
	return book


## An estimate of one mulch line, priced at a markup over the book's cost. Twenty cubic metres at
## $58.00 costs $1,160.00; at a 1.5 markup the price is $1,740.00 and the margin is 33.33%.
func _estimate(book: CostBook, estimate_id: String, number: String, units_milli: int, markup_ppm: int) -> Estimate:
	var mulch: CostItem = book.item(&"bed-mulch")
	var line: EstimateLine = LineScript.make(mulch, units_milli)
	line.unit_price = mulch.rate.scale_ppm(markup_ppm)
	var estimate: Estimate = EstimateScript.make(estimate_id)
	estimate.number = number
	estimate.customer["name"] = "Ada Lovelace"
	estimate.add_line(line, book)
	return estimate


func _ten_percent(book: CostBook) -> Dictionary:
	return PreviewScript.bulk_plan(book, 100000)


func _wipe(folder: String) -> void:
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		return
	for file_name in dir.get_files():
		DirAccess.remove_absolute(folder.path_join(String(file_name)))
	for subfolder in dir.get_directories():
		_wipe(folder.path_join(String(subfolder)))
	DirAccess.remove_absolute(folder)


# --- pointing it at a book and some estimates ----------------------------------------------------


func test_binding_keeps_the_estimates_and_drops_anything_else() -> void:
	var book: CostBook = _book()
	var preview: BizPricePreview = PreviewScript.new()
	preview.bind(book, [_estimate(book, "E-1", "EST-0001", 20000, 1500000), "not an estimate", 17])
	assert(preview.estimates.size() == 1)
	assert(preview.estimates[0].id == "E-1")
	assert(preview.book == book)


func test_binding_twice_does_not_keep_the_first_list_as_well() -> void:
	var book: CostBook = _book()
	var preview: BizPricePreview = PreviewScript.new()
	preview.bind(book, [_estimate(book, "E-1", "EST-0001", 20000, 1500000)])
	preview.bind(book, [])
	assert(preview.estimates.is_empty())


# --- a bulk update, as a plan --------------------------------------------------------------------


func test_a_bulk_plan_reprices_every_item_by_the_percentage() -> void:
	var book: CostBook = _book()
	var plan: Dictionary = _ten_percent(book)
	assert(plan["ok"], String(plan["reason"]))
	var changes: Array = plan["changes"]
	assert(changes.size() == 3)
	assert(String(changes[0]["id"]) == "bed-mulch", "items are planned in name order")
	assert(int(changes[0]["before_cents"]) == 5800)
	assert(int(changes[0]["after_cents"]) == 6380, "10% of 5800 cents")
	assert(int(changes[0]["delta_cents"]) == 580)


func test_a_bulk_plan_is_in_the_same_shape_an_imported_list_makes() -> void:
	var book: CostBook = _book()
	var plan: Dictionary = _ten_percent(book)
	for key: String in ["ok", "reason", "changes", "unchanged", "unmatched", "created", "problems", "currency"]:
		assert(plan.has(key), "a plan has a %s" % key)
	var entry: Dictionary = (plan["changes"] as Array)[0]
	for key: String in ["id", "before_cents", "after_cents", "delta_cents", "row_currency", "unit", "is_new"]:
		assert(entry.has(key), "a change has a %s" % key)


func test_a_bulk_plan_narrowed_to_one_supplier_leaves_the_others_out() -> void:
	var book: CostBook = _book()
	var plan: Dictionary = PreviewScript.bulk_plan(book, 100000, &"GreenCo")
	assert(plan["ok"], String(plan["reason"]))
	assert((plan["changes"] as Array).size() == 2, "mulch and labour are GreenCo's")
	var unchanged: Array = plan["unchanged"]
	assert(unchanged.size() == 1)
	assert(String(unchanged[0]["id"]) == "hard-paver-60")
	assert(String(unchanged[0]["reason"]).contains("StoneYard"), String(unchanged[0]["reason"]))


func test_a_bulk_update_of_nothing_is_refused_rather_than_made_a_version_of() -> void:
	var plan: Dictionary = PreviewScript.bulk_plan(_book(), 0)
	assert(not plan["ok"])
	assert(String(plan["reason"]).contains("a bulk update of nothing"), String(plan["reason"]))


func test_a_bulk_update_for_a_supplier_nobody_is_from_says_so() -> void:
	var plan: Dictionary = PreviewScript.bulk_plan(_book(), 50000, &"Nobody")
	assert(not plan["ok"])
	assert(String(plan["reason"]).contains("Nobody"), String(plan["reason"]))


func test_a_bulk_plan_with_no_book_is_refused_rather_than_read_as_no_changes() -> void:
	var plan: Dictionary = PreviewScript.bulk_plan(null, 100000)
	assert(not plan["ok"])
	assert(String(plan["reason"]).contains("no cost book"), String(plan["reason"]))


# --- the preview: the cost moves, the price does not ---------------------------------------------


func test_the_price_does_not_move_and_the_cost_does() -> void:
	var book: CostBook = _book()
	var estimate: Estimate = _estimate(book, "E-1", "EST-0001", 20000, 1500000)
	var preview: BizPricePreview = PreviewScript.new()
	preview.bind(book, [estimate])
	var result: Dictionary = preview.preview(_ten_percent(book))
	assert(result["ok"], String(result["reason"]))
	var rows: Array = result["rows"]
	assert(rows.size() == 1)
	var row: Dictionary = rows[0]
	assert(int(row["cost_before_cents"]) == 116000)
	assert(int(row["cost_after_cents"]) == 127600, "20 m3 at 10% more")
	assert(int(row["delta_cents"]) == 11600)
	assert(int(row["price_cents"]) == 174000, "the price the customer was quoted")
	assert(int(result["price_before_cents"]) == 174000)
	assert(int(result["price_after_cents"]) == 174000)


func test_the_margin_falls_by_what_the_cost_rose() -> void:
	var book: CostBook = _book()
	var estimate: Estimate = _estimate(book, "E-1", "EST-0001", 20000, 1500000)
	var preview: BizPricePreview = PreviewScript.new()
	preview.bind(book, [estimate])
	var row: Dictionary = (preview.preview(_ten_percent(book))["rows"] as Array)[0]
	assert(int(row["margin_before_ppm"]) == 333333)
	assert(int(row["margin_after_ppm"]) == 266667)


func test_reading_a_preview_moves_nothing_on_the_estimate() -> void:
	var book: CostBook = _book()
	var estimate: Estimate = _estimate(book, "E-1", "EST-0001", 20000, 1500000)
	var price: int = estimate.price_before_tax().cents
	var cost: int = estimate.direct_cost().cents
	var margin: int = estimate.margin_ppm()
	var frozen: int = estimate.lines[0].unit_cost.cents
	var preview: BizPricePreview = PreviewScript.new()
	preview.bind(book, [estimate])
	preview.preview(_ten_percent(book))
	assert(estimate.price_before_tax().cents == price)
	assert(estimate.direct_cost().cents == cost)
	assert(estimate.margin_ppm() == margin)
	assert(estimate.lines[0].unit_cost.cents == frozen, "the line keeps the cost it was priced with")


func test_a_preview_reads_the_estimates_it_was_pointed_at_not_the_ones_it_had_before() -> void:
	var book: CostBook = _book()
	var preview: BizPricePreview = PreviewScript.new()
	preview.bind(book, [_estimate(book, "E-1", "EST-0001", 20000, 1500000)])
	assert((preview.preview(_ten_percent(book))["rows"] as Array).size() == 1)
	preview.bind(book, [])
	assert((preview.preview(_ten_percent(book))["rows"] as Array).is_empty())


func test_the_preview_counts_the_estimates_whose_cost_would_move() -> void:
	var book: CostBook = _book()
	var preview: BizPricePreview = PreviewScript.new()
	preview.bind(book, [
		_estimate(book, "E-1", "EST-0001", 20000, 1500000),
		_estimate(book, "E-2", "EST-0002", 8000, 1500000),
	])
	var result: Dictionary = preview.preview(_ten_percent(book))
	assert(int(result["moved"]) == 2)
	assert(int(result["cost_before_cents"]) == 116000 + 46400)
	assert(int(result["cost_after_cents"]) == 127600 + 51040)


func test_a_plan_touching_none_of_an_estimates_items_leaves_it_where_it_is() -> void:
	var book: CostBook = _book()
	var estimate: Estimate = _estimate(book, "E-1", "EST-0001", 20000, 1500000)
	var preview: BizPricePreview = PreviewScript.new()
	preview.bind(book, [estimate])
	var result: Dictionary = preview.preview(PreviewScript.bulk_plan(book, 100000, &"StoneYard"))
	assert(int(result["moved"]) == 0)
	var row: Dictionary = (result["rows"] as Array)[0]
	assert(int(row["delta_cents"]) == 0)
	assert(int(row["lines_touched"]) == 0)


func test_a_line_an_imported_list_reprices_is_counted_as_touched() -> void:
	var book: CostBook = _book()
	var estimate: Estimate = _estimate(book, "E-1", "EST-0001", 20000, 1500000)
	var preview: BizPricePreview = PreviewScript.new()
	preview.bind(book, [estimate])
	var rows: Array = ImportScript.read_csv("id,name,unit,cost\nbed-mulch,Bark mulch,m3,64.50\n")["rows"]
	var row: Dictionary = (preview.preview(ImportScript.plan(book, rows))["rows"] as Array)[0]
	assert(int(row["lines_touched"]) == 1)
	assert(int(row["cost_before_cents"]) == 116000)


func test_the_preview_names_the_estimate_by_its_number_and_its_customer() -> void:
	var book: CostBook = _book()
	var estimate: Estimate = _estimate(book, "E-1", "EST-0001", 20000, 1500000)
	var preview: BizPricePreview = PreviewScript.new()
	preview.bind(book, [estimate])
	var row: Dictionary = (preview.preview(_ten_percent(book))["rows"] as Array)[0]
	assert(String(row["number"]) == "EST-0001")
	assert(String(row["client"]) == "Ada Lovelace")


func test_an_estimate_with_no_number_reads_by_its_id() -> void:
	var book: CostBook = _book()
	var estimate: Estimate = _estimate(book, "E-1", "", 20000, 1500000)
	var preview: BizPricePreview = PreviewScript.new()
	preview.bind(book, [estimate])
	var row: Dictionary = (preview.preview(_ten_percent(book))["rows"] as Array)[0]
	assert(String(row["number"]) == "E-1")


func test_a_preview_matches_what_the_new_book_would_actually_price() -> void:
	var book: CostBook = _book()
	var old_estimate: Estimate = _estimate(book, "E-1", "EST-0001", 20000, 1500000)
	var plan: Dictionary = _ten_percent(book)
	var applied: Dictionary = ImportScript.apply(book, plan, "2026-11-01")
	assert(applied["ok"], String(applied["reason"]))
	var new_book: CostBook = applied["book"]
	# The same work, priced from the new book: its cost is what the preview promised.
	var repriced: Estimate = _estimate(new_book, "E-2", "EST-0002", 20000, 1500000)
	var preview: BizPricePreview = PreviewScript.new()
	preview.bind(book, [old_estimate])
	var row: Dictionary = (preview.preview(plan)["rows"] as Array)[0]
	assert(int(row["cost_after_cents"]) == repriced.direct_cost().cents)
	assert(int(row["cost_before_cents"]) == old_estimate.direct_cost().cents)


func test_a_preview_of_a_plan_that_did_not_read_says_so() -> void:
	var book: CostBook = _book()
	var preview: BizPricePreview = PreviewScript.new()
	preview.bind(book, [_estimate(book, "E-1", "EST-0001", 20000, 1500000)])
	var result: Dictionary = preview.preview({"ok": false, "reason": "nothing read"})
	assert(not result["ok"])
	assert(String(result["reason"]).contains("nothing read"), String(result["reason"]))
	assert((result["rows"] as Array).is_empty())


func test_a_preview_with_no_book_is_refused_rather_than_reported_as_no_change() -> void:
	var preview: BizPricePreview = PreviewScript.new()
	var result: Dictionary = preview.preview({"ok": true, "changes": []})
	assert(not result["ok"])
	assert(String(result["reason"]).contains("no cost book"), String(result["reason"]))


func test_a_preview_with_no_estimates_is_an_empty_preview_not_a_failure() -> void:
	var book: CostBook = _book()
	var preview: BizPricePreview = PreviewScript.new()
	preview.bind(book, [])
	var result: Dictionary = preview.preview(_ten_percent(book))
	assert(result["ok"], String(result["reason"]))
	assert((result["rows"] as Array).is_empty())
	assert(int(result["moved"]) == 0)


# --- the margin, by the estimate's own rule ------------------------------------------------------


func test_margin_is_the_same_figure_the_estimate_computes() -> void:
	var book: CostBook = _book()
	var estimate: Estimate = _estimate(book, "E-1", "EST-0001", 20000, 1500000)
	var preview: BizPricePreview = PreviewScript.new()
	preview.bind(book, [estimate])
	var row: Dictionary = (preview.preview(_ten_percent(book))["rows"] as Array)[0]
	assert(int(row["margin_before_ppm"]) == estimate.margin_ppm())


func test_a_price_of_nothing_has_no_margin_rather_than_a_divide_by_zero() -> void:
	assert(BizPricePreview.margin_ppm(0, 1000) == 0)


func test_a_job_that_costs_more_than_it_sells_for_has_a_negative_margin() -> void:
	assert(BizPricePreview.margin_ppm(100000, 120000) == -200000)


# --- where the estimates come from ---------------------------------------------------------------


func test_the_estimates_are_read_out_of_the_store_a_job_at_a_time() -> void:
	_wipe(ROOT)
	var store: BizStore = StoreScript.new(ROOT)
	store.put(StoreScript.JOB_KIND, "J-1", {"number": "J-1001"}, "", -1, "evan", MAY)
	store.put(StoreScript.JOB_KIND, "J-2", {"number": "J-1002"}, "", -1, "evan", MAY)
	var book: CostBook = _book()
	store.put("estimate", "E-1", _estimate(book, "E-1", "EST-0001", 20000, 1500000).to_dict(), "J-1", -1, "evan", MAY)
	store.put("estimate", "E-2", _estimate(book, "E-2", "EST-0002", 8000, 1500000).to_dict(), "J-2", -1, "evan", MAY)
	var found: Array[Estimate] = BizPricePreview.read_estimates(store)
	assert(found.size() == 2)
	assert(found[0].number == "EST-0001")
	assert(found[1].number == "EST-0002")
	assert(found[0].direct_cost().cents == 116000, "a record read back is the estimate that went in")


func test_reading_estimates_out_of_a_store_with_none_is_an_empty_list() -> void:
	_wipe(ROOT)
	var store: BizStore = StoreScript.new(ROOT)
	assert(BizPricePreview.read_estimates(store).is_empty())
	assert(BizPricePreview.read_estimates(null).is_empty())


func test_an_estimate_read_out_of_the_store_previews_like_one_in_hand() -> void:
	_wipe(ROOT)
	var store: BizStore = StoreScript.new(ROOT)
	store.put(StoreScript.JOB_KIND, "J-1", {"number": "J-1001"}, "", -1, "evan", MAY)
	var book: CostBook = _book()
	store.put("estimate", "E-1", _estimate(book, "E-1", "EST-0001", 20000, 1500000).to_dict(), "J-1", -1, "evan", MAY)
	var preview: BizPricePreview = PreviewScript.new()
	preview.bind(book, BizPricePreview.read_estimates(store))
	var row: Dictionary = (preview.preview(_ten_percent(book))["rows"] as Array)[0]
	assert(int(row["cost_before_cents"]) == 116000)
	assert(int(row["cost_after_cents"]) == 127600)


# --- what a person reads -------------------------------------------------------------------------


func test_the_preview_reads_as_sentences_carrying_both_figures_and_the_margin() -> void:
	var book: CostBook = _book()
	var estimate: Estimate = _estimate(book, "E-1", "EST-0001", 20000, 1500000)
	var preview: BizPricePreview = PreviewScript.new()
	preview.bind(book, [estimate])
	var words: String = preview.describe(_ten_percent(book))
	assert(words.contains("1 estimate in hand, 1 whose cost would move"), words)
	assert(words.contains("EST-0001"), words)
	assert(words.contains("$1,160.00"), words)
	assert(words.contains("$1,276.00"), words)
	assert(words.contains("price $1,740.00 unchanged"), words)
	assert(words.contains("33.33% -> 26.67%"), words)


func test_a_preview_that_could_not_be_read_describes_the_reason() -> void:
	var book: CostBook = _book()
	var preview: BizPricePreview = PreviewScript.new()
	preview.bind(book, [_estimate(book, "E-1", "EST-0001", 20000, 1500000)])
	var words: String = preview.describe({"ok": false, "reason": "nothing read"})
	assert(words.contains("nothing read"), words)
	var empty: BizPricePreview = PreviewScript.new()
	assert(empty.describe({"ok": true, "changes": []}).contains("no cost book"))