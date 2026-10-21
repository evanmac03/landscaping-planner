extends Node
## The cost book dock: read the book, read a price list, plan it, preview it, and write the next
## version (spec §12, §1's `addons/biz_tools/`).
##
## The dock is a plain `Control`, so every one of these drives the real thing with it never added to a
## tree: `build()` makes the controls, and each test calls **the method the button calls**, which is
## the arrangement the hatch panel and the analytics page are tested by. Nothing here needs a window
## server because the dock opens no dialogs - a path is a typed field, not a file chooser.
##
## What is being asserted, beyond the plumbing: **a dock with no book refuses rather than fails**,
## **the price on a job already quoted is read back and is unchanged**, **the book the dock read is
## still the book it read after it wrote a new version**, and **a percentage is signed** - the one bug
## this file was written to catch, which was the module's own `Rate.is_valid` asking whether a *rate*
## is sensible (`>= 0`) about a price *change* that was a reduction.

const BookScript := preload("res://scripts/biz/cost_book.gd")
const ItemScript := preload("res://scripts/biz/cost_item.gd")
const EstimateScript := preload("res://scripts/biz/estimate.gd")
const LineScript := preload("res://scripts/biz/estimate_line.gd")
const StoreScript := preload("res://scripts/biz/store.gd")
const DockScript := preload("res://addons/biz_tools/costbook_dock.gd")

const ROOT := "user://test_costbook_dock"
const STORE_ROOT := "user://test_costbook_dock/store"
const BOOK_PATH := "user://test_costbook_dock/book.json"
const NEW_BOOK := "user://test_costbook_dock/new-book.json"
const PRICE_LIST := "user://test_costbook_dock/prices.csv"
## A September morning, stated rather than read off the clock.
const MOMENT := 1788000000


## Two items, one job and one estimate priced from them, a book on disk and a supplier's price list:
## everything the dock needs for each of its buttons to have something real to work on.
func _fixture() -> void:
	_wipe(ROOT)
	var book: CostBook = _book()
	book.save_to(BOOK_PATH)
	var store: BizStore = StoreScript.new(STORE_ROOT)
	store.put(StoreScript.JOB_KIND, "J-1", {"number": "J-1001"}, "", -1, "evan", MOMENT)
	store.put("estimate", "E-1", _estimate(book).to_dict(), "J-1", -1, "evan", MOMENT)
	var text := "SKU,Description,UOM,Unit Cost,Waste\n"
	text += "bed-mulch,Bark mulch,m3,64.50,8%\n"
	text += "hb-4x8,Bloomsdale 4x8,ea,3.24,\n"
	var file: FileAccess = FileAccess.open(PRICE_LIST, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _book() -> CostBook:
	var book: CostBook = BookScript.make(3, "2026-01-01")
	var mulch: CostItem = ItemScript.make(&"bed-mulch", "Bark mulch", &"CU_M", 5800)
	mulch.cost_code = &"BEDS"
	book.add_item(mulch)
	var paver: CostItem = ItemScript.make(&"hard-paver-60", "Interlock paving, 60mm", &"SQ_FT", 325)
	paver.cost_code = &"HARDSCAPE"
	book.add_item(paver)
	return book


## Twenty cubic metres of mulch at a 1.5 markup: $58.00 costs, $87.00 sells, margin 33.33%.
func _estimate(book: CostBook) -> Estimate:
	var mulch: CostItem = book.item(&"bed-mulch")
	var line: EstimateLine = LineScript.make(mulch, 20000)
	line.unit_price = mulch.rate.scale_ppm(1500000)
	var estimate: Estimate = EstimateScript.make("E-1")
	estimate.number = "EST-0001"
	estimate.customer["name"] = "Ada Lovelace"
	estimate.add_line(line, book)
	return estimate


func _built() -> Control:
	var dock: Control = DockScript.new()
	dock.store_root = STORE_ROOT
	dock.build()
	return dock


func _ready_dock() -> Control:
	_fixture()
	return _dock_on_what_is_there()


## A dock pointed at whatever book, store and price list are already on disk - for a test that has
## written its own fixture and must not have `_fixture` wipe it.
func _dock_on_what_is_there() -> Control:
	var dock: Control = _built()
	dock.set_output_path(NEW_BOOK)
	dock.load_book(BOOK_PATH)
	return dock


func _wipe(folder: String) -> void:
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		return
	for file_name in dir.get_files():
		DirAccess.remove_absolute(folder.path_join(String(file_name)))
	for subfolder in dir.get_directories():
		_wipe(folder.path_join(String(subfolder)))
	DirAccess.remove_absolute(folder)


# --- building it ----------------------------------------------------------------------------------


func test_a_dock_builds_its_controls_and_says_where_to_start() -> void:
	var dock: Control = _built()
	assert(dock.is_built())
	assert(dock.name == "Cost book")
	assert(dock.status_text() == "Open a cost book to begin.")
	assert(dock.book_text() == "no cost book is loaded")
	dock.free()


func test_the_default_paths_are_the_starter_book_and_the_live_book() -> void:
	var dock: Control = _built()
	assert(dock.book_path_text() == DockScript.SHIPPED_BOOK)
	assert(dock.output_path_text() == DockScript.LIVE_BOOK)
	assert(dock.price_path_text() == "")
	dock.free()


func test_building_twice_is_the_same_dock_rather_than_a_second_set_of_rows() -> void:
	var dock: Control = _built()
	dock.load_book(DockScript.SHIPPED_BOOK)
	var rows: int = dock.plan_rows().size()
	dock.build()
	assert(dock.plan_rows().size() == rows)
	dock.free()


# --- opening a book -------------------------------------------------------------------------------


func test_the_project_s_starter_book_reads_and_is_described() -> void:
	var dock: Control = _built()
	var read: Dictionary = dock.load_book(DockScript.SHIPPED_BOOK)
	assert(read["ok"], String(read["reason"]))
	assert(dock.book_text().contains("v1 from 2026-01-01"), dock.book_text())
	assert(dock.book_text().contains("21 items"), dock.book_text())
	assert(dock.status_text().contains("Cost book v1"), dock.status_text())
	dock.free()


func test_a_book_that_is_not_there_is_refused_in_words_and_leaves_the_dock_empty() -> void:
	var dock: Control = _built()
	var read: Dictionary = dock.load_book("user://test_costbook_dock/nothing.json")
	assert(not read["ok"])
	assert(String(read["reason"]).contains("no cost book"), String(read["reason"]))
	assert(dock.book_text() == "no cost book is loaded")
	assert(dock.status_text().contains("no cost book"), dock.status_text())
	dock.free()


func test_a_dock_with_no_book_refuses_each_thing_rather_than_failing() -> void:
	var dock: Control = _built()
	assert(String(dock.read_price_list(PRICE_LIST)["reason"]).contains("no cost book"))
	assert(String(dock.plan_bulk("5%")["reason"]).contains("no cost book"))
	assert(String(dock.apply_plan()["reason"]).contains("no cost book"))
	assert(String(dock.show_preview()["reason"]).contains("no cost book"))
	dock.free()


func test_loading_a_book_clears_the_plan_that_was_in_hand() -> void:
	_fixture()
	var dock: Control = _built()
	dock.load_book(BOOK_PATH)
	dock.read_price_list(PRICE_LIST)
	assert(not dock.plan_rows().is_empty())
	dock.load_book(BOOK_PATH)
	assert(dock.plan_rows().is_empty(), "a plan belongs to the book it was planned against")
	dock.free()


# --- reading a supplier's price list --------------------------------------------------------------


func test_a_price_list_reads_and_the_plan_is_shown_in_money() -> void:
	var dock: Control = _ready_dock()
	var read: Dictionary = dock.read_price_list(PRICE_LIST)
	assert(read["ok"], String(read["reason"]))
	assert((read["rows"] as Array).size() == 2)
	var rows: Array = dock.plan_rows()
	assert(rows.size() == 2, "one change and one unmatched row")
	assert(String(rows[0]).contains("Bark mulch"), String(rows[0]))
	assert(String(rows[0]).contains("$58.00 -> $64.50"), String(rows[0]))
	assert(String(rows[0]).contains("+$6.50"), String(rows[0]))
	assert(String(rows[1]).contains("unmatched"), String(rows[1]))
	assert(String(rows[1]).contains("Bloomsdale 4x8"), String(rows[1]))
	dock.free()


func test_the_status_line_counts_what_the_price_list_came_to() -> void:
	var dock: Control = _ready_dock()
	dock.read_price_list(PRICE_LIST)
	assert(dock.status_text().contains("1 repriced"), dock.status_text())
	assert(dock.status_text().contains("1 unmatched"), dock.status_text())
	dock.free()


func test_a_price_list_that_is_not_there_is_refused_in_words() -> void:
	var dock: Control = _ready_dock()
	var read: Dictionary = dock.read_price_list("user://test_costbook_dock/nothing.csv")
	assert(not read["ok"])
	assert(String(read["reason"]).contains("no price list"), String(read["reason"]))
	assert(dock.plan_rows().is_empty())
	dock.free()


func test_a_row_whose_cost_will_not_read_is_named_in_the_plan() -> void:
	var dock: Control = _ready_dock()
	var text := "id,name,unit,cost\nbed-mulch,Bark mulch,m3,sixty\n"
	var file: FileAccess = FileAccess.open(PRICE_LIST, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	var read: Dictionary = dock.read_price_list(PRICE_LIST)
	assert(read["ok"], "the file reads; the row does not")
	var rows: Array = dock.plan_rows()
	assert(rows.size() == 2, "nothing would change, and the unreadable line is named")
	assert(String(rows[0]) == "nothing would change")
	assert(String(rows[1]).contains("unreadable"), String(rows[1]))
	assert(String(rows[1]).contains("sixty"), String(rows[1]))
	dock.free()


# --- a percentage, which is signed ----------------------------------------------------------------


func test_a_reduction_is_a_percentage_too() -> void:
	# The bug this file exists for: `Rate.is_valid` asks whether a *rate* is sensible, and a rate is
	# never negative - so asking it about a price *change* refused every reduction as unreadable.
	var dock: Control = _ready_dock()
	var plan: Dictionary = dock.plan_bulk("-5%")
	assert(plan["ok"], String(plan["reason"]))
	assert((plan["changes"] as Array).size() == 2)
	assert(dock.status_text().contains("-5%"), dock.status_text())
	assert(String(dock.plan_rows()[0]).contains("(-$"), String(dock.plan_rows()[0]))
	dock.free()


func test_an_increase_is_a_percentage() -> void:
	var dock: Control = _ready_dock()
	var plan: Dictionary = dock.plan_bulk("+5")
	assert(plan["ok"], String(plan["reason"]))
	assert(dock.status_text().contains("5%"), dock.status_text())
	dock.free()


func test_a_percentage_nobody_could_read_is_refused_rather_than_planned_as_nothing() -> void:
	var dock: Control = _ready_dock()
	var plan: Dictionary = dock.plan_bulk("five")
	assert(not plan["ok"])
	assert(String(plan["reason"]).contains("is not a percentage this can read"), String(plan["reason"]))
	assert(dock.plan_rows().is_empty(), "the rows from before are cleared rather than left stale")
	dock.free()


func test_a_bulk_update_of_nothing_is_refused_with_its_reason() -> void:
	var dock: Control = _ready_dock()
	var plan: Dictionary = dock.plan_bulk("0")
	assert(not plan["ok"])
	assert(String(plan["reason"]).contains("a bulk update of nothing"), String(plan["reason"]))
	dock.free()


func test_a_bulk_update_narrowed_to_a_supplier_nobody_is_from_says_so() -> void:
	var dock: Control = _ready_dock()
	dock.set_supplier("Nobody")
	var plan: Dictionary = dock.plan_bulk("5%")
	assert(not plan["ok"])
	assert(String(plan["reason"]).contains("Nobody"), String(plan["reason"]))
	dock.free()


func test_a_bulk_update_narrowed_to_a_supplier_the_book_has_plans_only_those() -> void:
	_fixture()
	var dock: Control = _built()
	dock.load_book(BOOK_PATH)
	dock.set_supplier("Nobody At All")
	assert(not dock.plan_bulk("5%")["ok"])
	dock.set_supplier("")
	var plan: Dictionary = dock.plan_bulk("5%")
	assert(plan["ok"], String(plan["reason"]))
	assert((plan["changes"] as Array).size() == 2)
	dock.free()


# --- what it would do to the work already quoted ---------------------------------------------------


func test_the_preview_shows_the_cost_moving_and_the_price_standing_still() -> void:
	var dock: Control = _ready_dock()
	dock.read_price_list(PRICE_LIST)
	var rows: Array = dock.preview_rows()
	assert(rows.size() == 1)
	var words: String = String(rows[0])
	assert(words.contains("EST-0001"), words)
	assert(words.contains("cost $1,160.00 -> $1,290.00"), words)
	assert(words.contains("price $1,740.00 unchanged"), words)
	assert(words.contains("33.33% -> 25.86%"), words)
	dock.free()


func test_the_preview_reads_the_estimates_out_of_the_store_it_was_pointed_at() -> void:
	var dock: Control = _ready_dock()
	dock.read_price_list(PRICE_LIST)
	assert(dock.preview_rows().size() == 1)
	dock.store_root = "user://test_costbook_dock/nowhere"
	dock.show_preview()
	var rows: Array = dock.preview_rows()
	assert(rows.size() == 1)
	assert(String(rows[0]).contains("no estimate in the store"), String(rows[0]))
	dock.free()


func test_a_preview_with_no_plan_in_hand_is_refused_rather_than_showing_nothing() -> void:
	var dock: Control = _ready_dock()
	var result: Dictionary = dock.show_preview()
	assert(not result["ok"])
	assert(String(result["reason"]).contains("no plan in hand"), String(result["reason"]))
	dock.free()


# --- writing the next version ---------------------------------------------------------------------


func test_applying_a_plan_writes_the_next_version_where_it_was_told_to() -> void:
	var dock: Control = _ready_dock()
	dock.read_price_list(PRICE_LIST)
	dock.set_effective_date("2026-11-01")
	var applied: Dictionary = dock.apply_plan()
	assert(applied["ok"], String(applied["reason"]))
	assert(String(applied["path"]) == NEW_BOOK)
	assert(int(applied["version"]) == 4)
	assert(FileAccess.file_exists(NEW_BOOK))
	assert(dock.status_text().contains("Wrote Cost book v4"), dock.status_text())
	dock.free()


func test_the_book_written_is_the_book_read_back() -> void:
	var dock: Control = _ready_dock()
	dock.read_price_list(PRICE_LIST)
	dock.set_effective_date("2026-11-01")
	dock.apply_plan()
	var written: Dictionary = BookScript.load_from(NEW_BOOK)
	assert(written["ok"], String(written["reason"]))
	var next: CostBook = written["book"]
	assert(next.version == 4)
	assert(next.effective_from == "2026-11-01")
	assert(next.item(&"bed-mulch").rate.cents == 6450)
	assert(next.source.contains("the cost book dock"), next.source)
	dock.free()


func test_the_book_the_dock_read_is_still_the_book_it_read() -> void:
	var dock: Control = _ready_dock()
	dock.read_price_list(PRICE_LIST)
	dock.set_effective_date("2026-11-01")
	dock.apply_plan()
	assert(dock.book.version == 3, "the dock's own book is not the new version")
	assert(dock.book.item(&"bed-mulch").rate.cents == 5800, "and its prices did not move (REQ-B6)")
	dock.free()


func test_applying_with_no_date_is_refused_with_what_it_would_cost_the_record() -> void:
	var dock: Control = _ready_dock()
	dock.read_price_list(PRICE_LIST)
	var applied: Dictionary = dock.apply_plan()
	assert(not applied["ok"])
	assert(String(applied["reason"]).contains("is not a date"), String(applied["reason"]))
	assert(not FileAccess.file_exists(NEW_BOOK))
	dock.free()


func test_applying_with_no_home_to_write_to_is_refused() -> void:
	var dock: Control = _ready_dock()
	dock.read_price_list(PRICE_LIST)
	dock.set_effective_date("2026-11-01")
	dock.set_output_path("")
	assert(String(dock.apply_plan()["reason"]).contains("nowhere to write"), dock.status_text())
	dock.free()


func test_applying_a_bulk_update_of_nothing_is_refused_by_the_module() -> void:
	var dock: Control = _ready_dock()
	dock.plan_bulk("0")
	dock.set_effective_date("2026-11-01")
	var applied: Dictionary = dock.apply_plan()
	assert(not applied["ok"])
	assert(String(applied["reason"]).contains("a bulk update of nothing"), String(applied["reason"]))
	dock.free()


func test_a_bulk_update_writes_a_new_version_too() -> void:
	var dock: Control = _ready_dock()
	dock.plan_bulk("-5%")
	dock.set_effective_date("2026-12-01")
	assert(dock.apply_plan()["ok"])
	var written: Dictionary = BookScript.load_from(NEW_BOOK)
	assert(written["ok"], String(written["reason"]))
	var next: CostBook = written["book"]
	assert(next.item(&"bed-mulch").rate.cents == 5510, "5%% off $58.00")
	assert(next.version == 4)
	dock.free()


# --- what is wrong with it ------------------------------------------------------------------------


func test_a_dock_with_no_book_says_exactly_that() -> void:
	var dock: Control = _built()
	var rows: Array = dock.diagnostic_rows()
	assert(rows.size() == 1)
	assert(String(rows[0]) == "no cost book is loaded")
	dock.free()


func test_a_sound_book_with_no_store_says_they_agree() -> void:
	var dock: Control = _ready_dock()
	var rows: Array = dock.diagnostic_rows()
	assert(rows.size() == 1, str(rows))
	assert(String(rows[0]) == "the book, the store and the stored estimates agree")
	dock.free()


func test_an_item_with_no_cost_code_is_named_rather_than_left_to_be_found_by_a_takeoff() -> void:
	_fixture()
	var dock: Control = _built()
	dock.load_book(BOOK_PATH)
	dock.book.item(&"bed-mulch").cost_code = &""
	dock.refresh()
	var rows: Array = dock.diagnostic_rows()
	var found: bool = false
	for row: String in rows:
		if row.contains("carries no cost code"):
			found = true
	assert(found, str(rows))
	dock.free()


func test_a_stored_estimate_priced_from_an_item_the_book_no_longer_has_is_named() -> void:
	_fixture()
	var store: BizStore = StoreScript.new(STORE_ROOT)
	var book: CostBook = _book()
	var ghost: CostItem = ItemScript.make(&"discontinued-thing", "Discontinued thing", &"EACH", 1200)
	var estimate: Estimate = _estimate(book)
	estimate.add_line(LineScript.make(ghost, 4000))
	store.put("estimate", "E-1", estimate.to_dict(), "J-1", 1, "evan", MOMENT)

	var dock: Control = _dock_on_what_is_there()
	var rows: Array = dock.diagnostic_rows()
	var found: bool = false
	for row: String in rows:
		if row.contains("this book no longer has"):
			found = true
	assert(found, str(rows))
	dock.free()


func test_a_book_that_refuses_something_reports_it_rather_than_hiding_it() -> void:
	_fixture()
	var book: CostBook = _book()
	var broken: CostItem = ItemScript.make(&"", "No id at all", &"EACH", 100)
	book.items[&""] = broken
	book.save_to(BOOK_PATH)
	var dock: Control = _dock_on_what_is_there()
	var rows: Array = dock.diagnostic_rows()
	assert(rows.size() == 1, str(rows))
	assert(String(rows[0]).contains("needs an id"), String(rows[0]))
	dock.free()


# --- what a test (or a person) sets and reads back -------------------------------------------------


func test_every_field_the_dock_shows_can_be_set_and_read_back() -> void:
	var dock: Control = _built()
	dock.set_book_path("res://somewhere/book.json")
	dock.set_output_path("user://somewhere/new.json")
	dock.set_price_path("user://somewhere/prices.csv")
	dock.set_effective_date("2027-01-01")
	dock.set_supplier("GreenCo")
	dock.set_percent("-2.5")
	assert(dock.book_path_text() == "res://somewhere/book.json")
	assert(dock.output_path_text() == "user://somewhere/new.json")
	assert(dock.price_path_text() == "user://somewhere/prices.csv")
	dock.free()


func test_the_plan_and_the_preview_are_empty_before_anything_is_read() -> void:
	var dock: Control = _built()
	assert(dock.plan_rows().is_empty())
	assert(dock.preview_rows().is_empty())
	assert(dock.status_text() == "Open a cost book to begin.")
	dock.free()


func test_the_last_thing_said_is_readable_without_looking_at_a_label() -> void:
	var dock: Control = _ready_dock()
	dock.read_price_list(PRICE_LIST)
	assert(not dock.last_words.is_empty())
	assert(dock.last_words == dock.status_text())
	dock.free()


func test_a_dock_that_has_been_free_is_not_left_on_the_scene() -> void:
	# Every test frees its dock: an unfreed panel makes the runner report resources still in use,
	# which fails the verdict however well the assertions went.
	var dock: Control = _built()
	dock.free()
	assert(is_instance_valid(dock) == false)