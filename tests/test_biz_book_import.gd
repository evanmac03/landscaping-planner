extends Node
## The supplier price list: read it, plan it against a book, and put the plan into a **new version**
## (spec §12, the cost book panel's "bulk import and price preview").
##
## Three properties are under test. **A row that will not read is refused and named**, with its line
## number and the text, because a price list with one unreadable cost is a list to fix rather than one
## to lose. **A row is never matched by guesswork**: an id the book has, or a name exactly one item
## carries, or nothing - and "nothing" is reported rather than invented. And **applying a plan makes a
## new version and leaves the old book alone**, which is the whole reason a stored estimate's prices
## stay frozen (REQ-B6, AC-B7).

const BookScript := preload("res://scripts/biz/cost_book.gd")
const ItemScript := preload("res://scripts/biz/cost_item.gd")
const ImportScript := preload("res://scripts/biz/book_import.gd")

## Three items: a material bought by volume with waste, one priced in square feet, and labour.
func _book() -> CostBook:
	var book: CostBook = BookScript.make(3, "2026-01-01")
	var mulch: CostItem = ItemScript.make(&"bed-mulch", "Bark mulch", &"CU_M", 5800)
	mulch.waste_ppm = 80000
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


func _rows(text: String, currency: StringName = &"CAD") -> Array:
	var read: Dictionary = ImportScript.read_csv(text, currency)
	return read["rows"]


func _ids(entries: Array) -> Array:
	var out: Array = []
	for entry: Dictionary in entries:
		out.append(String(entry["id"]))
	return out


# --- reading a supplier's file -------------------------------------------------------------------


func test_a_price_list_reads_its_columns_by_any_of_their_names() -> void:
	var read: Dictionary = ImportScript.read_csv(
		"SKU,Description,UOM,Unit Cost\nbed-mulch,\"Bark mulch, bulk\",m3,64.50\n"
	)
	assert(read["ok"], String(read["reason"]))
	var rows: Array = read["rows"]
	assert(rows.size() == 1)
	var row: Dictionary = rows[0]
	assert(row["id"] == &"bed-mulch")
	assert(row["name"] == "Bark mulch, bulk", "a quoted comma is one field")
	assert(row["unit"] == &"CU_M")
	assert((row["cost"] as Money).cents == 6450)


func test_a_heading_written_with_spaces_or_dashes_is_the_same_heading() -> void:
	var read: Dictionary = ImportScript.read_csv("Item-Code,Name,Units,Price\nbed-mulch,Bark mulch,cu yd,58.00\n")
	assert(read["ok"], String(read["reason"]))
	var rows: Array = read["rows"]
	var row: Dictionary = rows[0]
	assert(row["id"] == &"bed-mulch")
	assert(row["unit"] == &"CU_YD")


func test_a_doubled_quote_inside_a_quoted_field_survives() -> void:
	var rows: Array = _rows("id,name,unit,cost\nx,\"3\"\" drain pipe\",m,4.00\n")
	var row: Dictionary = rows[0]
	assert(row["name"] == "3\" drain pipe")


func test_carriage_returns_and_blank_lines_are_not_rows() -> void:
	var read: Dictionary = ImportScript.read_csv("id,name,unit,cost\r\n\r\nbed-mulch,Bark mulch,m3,64.50\r\n\r\n")
	assert(read["ok"], String(read["reason"]))
	assert((read["rows"] as Array).size() == 1)


func test_a_file_with_no_cost_column_is_refused_rather_than_read_as_nothing() -> void:
	var read: Dictionary = ImportScript.read_csv("id,name,unit\nbed-mulch,Bark mulch,m3\n")
	assert(not read["ok"])
	assert(String(read["reason"]).contains("names no cost column"), String(read["reason"]))


func test_a_file_that_names_neither_an_id_nor_a_name_is_refused() -> void:
	var read: Dictionary = ImportScript.read_csv("unit,cost\nm3,64.50\n")
	assert(not read["ok"])
	assert(String(read["reason"]).contains("no id and no name"), String(read["reason"]))


func test_an_empty_file_is_refused_rather_than_read_as_no_prices() -> void:
	var read: Dictionary = ImportScript.read_csv("")
	assert(not read["ok"])


func test_a_file_longer_than_the_cap_is_a_wrong_file_not_a_long_one() -> void:
	var text: String = "id,name,unit,cost\n"
	for index in ImportScript.MAX_ROWS + 1:
		text += "item-%d,Thing %d,each,1.00\n" % [index, index]
	var read: Dictionary = ImportScript.read_csv(text)
	assert(not read["ok"])
	assert(String(read["reason"]).contains(str(ImportScript.MAX_ROWS)), String(read["reason"]))


# --- a row that will not read is named, not dropped ----------------------------------------------


func test_an_unreadable_cost_is_named_with_its_line_and_its_text() -> void:
	var read: Dictionary = ImportScript.read_csv("id,name,unit,cost\nbed-mulch,Bark mulch,m3,sixty\n")
	assert(read["ok"], "the file reads, the row does not")
	var problems: Array = read["problems"]
	assert(problems.size() == 1)
	assert(String(problems[0]).contains("line 2"), String(problems[0]))
	assert(String(problems[0]).contains("sixty"), String(problems[0]))


func test_a_unit_nobody_knows_is_refused_by_name() -> void:
	var read: Dictionary = ImportScript.read_csv("id,name,unit,cost\nbed-mulch,Bark mulch,bushels,64.50\n")
	var problems: Array = read["problems"]
	assert(problems.size() == 1)
	assert(String(problems[0]).contains("bushels"), String(problems[0]))


func test_a_kind_nobody_has_is_refused_rather_than_read_as_a_material() -> void:
	var read: Dictionary = ImportScript.read_csv("id,name,unit,cost,kind\nbed-mulch,Bark mulch,m3,64.50,Unobtainium\n")
	var problems: Array = read["problems"]
	assert(problems.size() == 1)
	assert(String(problems[0]).contains("Unobtainium"), String(problems[0]))


func test_a_row_naming_neither_an_id_nor_a_name_is_named() -> void:
	var read: Dictionary = ImportScript.read_csv("id,name,unit,cost\n,,m3,64.50\n")
	var problems: Array = read["problems"]
	assert(problems.size() == 1)
	assert(String(problems[0]).contains("line 2"), String(problems[0]))


func test_a_row_that_cannot_be_read_is_still_counted_as_a_line_rather_than_lost() -> void:
	var read: Dictionary = ImportScript.read_csv("id,name,unit,cost\nbed-mulch,Bark mulch,m3,sixty\npaver,Paving,each,4.00\n")
	assert((read["rows"] as Array).size() == 2, "every line is kept so the line numbers keep their meaning")
	var good: Array = read["rows"]
	assert((good[1]["cost"] as Money).cents == 400)


# --- waste, as a supplier states it ---------------------------------------------------------------


func test_a_percentage_of_waste_is_read_as_parts_per_million() -> void:
	var rows: Array = _rows("id,name,unit,cost,waste\nbed-mulch,Bark mulch,m3,64.50,8%\n")
	assert(int(rows[0]["waste_ppm"]) == 80000)


func test_a_bare_number_in_the_waste_column_is_a_percentage() -> void:
	var rows: Array = _rows("id,name,unit,cost,waste\nbed-mulch,Bark mulch,m3,64.50,8\n")
	assert(int(rows[0]["waste_ppm"]) == 80000)
	assert(int(_rows("id,name,unit,cost,waste\nx,T,m3,1.00,7.5\n")[0]["waste_ppm"]) == 75000)


func test_a_waste_finer_than_a_hundredth_of_a_percent_is_refused() -> void:
	var read: Dictionary = ImportScript.read_csv("id,name,unit,cost,waste\nx,Thing,m3,1.00,8.00005\n")
	assert((read["problems"] as Array).size() == 1)
	assert(String((read["problems"] as Array)[0]).contains("finer than a hundredth"), String((read["problems"] as Array)[0]))


func test_a_waste_past_the_caps_the_item_allows_is_refused_with_the_cap_named() -> void:
	var read: Dictionary = ImportScript.read_csv("id,name,unit,cost,waste\nx,Thing,m3,1.00,300\n")
	assert((read["problems"] as Array).size() == 1)
	assert(String((read["problems"] as Array)[0]).contains("50.00%"), String((read["problems"] as Array)[0]))


func test_no_waste_column_at_all_is_no_waste() -> void:
	var rows: Array = _rows("id,name,unit,cost\nbed-mulch,Bark mulch,m3,64.50\n")
	assert(int(rows[0]["waste_ppm"]) == 0)


# --- matching a row to an item -------------------------------------------------------------------


func test_a_row_naming_an_id_the_book_has_is_that_item() -> void:
	var plan: Dictionary = ImportScript.plan(_book(), _rows("id,name,unit,cost\nbed-mulch,Anything,m3,64.50\n"))
	var changes: Array = plan["changes"]
	assert(changes.size() == 1)
	assert(String(changes[0]["id"]) == "bed-mulch")
	assert(String(changes[0]["name"]) == "Bark mulch", "the book's own name is kept, not the list's")


func test_a_row_naming_an_id_the_book_does_not_have_matches_on_the_name_instead() -> void:
	var plan: Dictionary = ImportScript.plan(_book(), _rows("id,name,unit,cost\nXX-9,Bark mulch,m3,64.50\n"))
	var changes: Array = plan["changes"]
	assert(changes.size() == 1)
	assert(String(changes[0]["id"]) == "bed-mulch")


func test_a_name_two_items_share_matches_neither_rather_than_guessing() -> void:
	var book: CostBook = _book()
	book.add_item(ItemScript.make(&"mulch-two", "Bark mulch", &"CU_M", 6000))
	var plan: Dictionary = ImportScript.plan(book, _rows("id,name,unit,cost\n,Bark mulch,m3,64.50\n"))
	assert((plan["changes"] as Array).is_empty())
	assert((plan["unmatched"] as Array).size() == 1)


func test_an_item_the_book_does_not_have_is_unmatched_and_named() -> void:
	var plan: Dictionary = ImportScript.plan(_book(), _rows("id,name,unit,cost\nastroturf,Roll-out turf,each,199.00\n"))
	var unmatched: Array = plan["unmatched"]
	assert(unmatched.size() == 1)
	assert(String(unmatched[0]["name"]) == "Roll-out turf")
	assert(String(unmatched[0]["reason"]).contains("not the authority"), String(unmatched[0]["reason"]))


func test_an_item_the_book_does_not_have_is_created_only_when_that_is_asked_for() -> void:
	var plan: Dictionary = ImportScript.plan(
		_book(), _rows("id,name,unit,cost\nastroturf,Roll-out turf,SQ_FT,199.00\n"), true
	)
	assert((plan["unmatched"] as Array).is_empty())
	var created: Array = plan["created"]
	assert(created.size() == 1)
	assert(String(created[0]["id"]) == "astroturf")
	assert(int(created[0]["after_cents"]) == 19900)
	assert(int(created[0]["before_cents"]) == 0)


func test_an_item_created_from_a_name_alone_is_filed_under_a_slug_of_it() -> void:
	var plan: Dictionary = ImportScript.plan(
		_book(), _rows("id,name,unit,cost\n,Roll-out turf,SQ_FT,199.00\n"), true
	)
	var created: Array = plan["created"]
	assert(created.size() == 1)
	assert(String(created[0]["id"]) == "roll-out-turf")


func test_two_rows_about_one_item_are_refused_rather_than_one_of_them_winning() -> void:
	var plan: Dictionary = ImportScript.plan(
		_book(), _rows("id,name,unit,cost\nbed-mulch,Bark mulch,m3,64.50\nbed-mulch,Bark mulch,m3,70.00\n")
	)
	var problems: Array = plan["problems"]
	assert(problems.size() == 1)
	assert(String(problems[0]).contains("line 2 and line 3"), String(problems[0]))


func test_a_row_that_agrees_with_the_book_is_unchanged_rather_than_a_change_of_nothing() -> void:
	var plan: Dictionary = ImportScript.plan(_book(), _rows(
		"id,name,unit,cost,waste\nbed-mulch,Bark mulch,m3,58.00,8%\n"
	))
	assert((plan["changes"] as Array).is_empty())
	assert((plan["unchanged"] as Array).size() == 1)


func test_a_row_costing_the_same_but_priced_in_another_unit_is_a_change() -> void:
	var plan: Dictionary = ImportScript.plan(_book(), _rows("id,name,unit,cost\nhard-paver-60,Paving,SQ_M,3.25\n"))
	var changes: Array = plan["changes"]
	assert(changes.size() == 1)
	assert(int(changes[0]["delta_cents"]) == 0)
	assert(bool(changes[0]["unit_changed"]), "a unit is a price's meaning, not a label")
	assert(String(changes[0]["unit"]) == "SQ_M")


func test_a_row_that_changes_only_the_waste_is_a_change() -> void:
	var plan: Dictionary = ImportScript.plan(_book(), _rows(
		"id,name,unit,cost,waste\nbed-mulch,Bark mulch,m3,58.00,12%\n"
	))
	assert((plan["changes"] as Array).size() == 1)
	assert(bool((plan["changes"] as Array)[0]["waste_changed"]))


func test_the_plan_counts_what_it_found_in_one_line() -> void:
	var plan: Dictionary = ImportScript.plan(_book(), _rows(
		"id,name,unit,cost,waste\nbed-mulch,Bark mulch,m3,64.50,8%\nhard-paver-60,Paving,SQ_FT,3.25,\nastroturf,Turf,each,199.00,\n"
	))
	assert(ImportScript.describe(plan) == "1 repriced, 1 unchanged, 0 new, 1 unmatched, 0 unreadable",
		ImportScript.describe(plan))


# --- putting a plan into a new book --------------------------------------------------------------


func test_applying_a_plan_makes_the_next_version_and_dates_it() -> void:
	var book: CostBook = _book()
	var plan: Dictionary = ImportScript.plan(book, _rows("id,name,unit,cost\nbed-mulch,Bark mulch,m3,64.50\n"))
	var applied: Dictionary = ImportScript.apply(book, plan, "2026-11-01")
	assert(applied["ok"], String(applied["reason"]))
	var next: CostBook = applied["book"]
	assert(next.version == 4, "v3's next version is v4")
	assert(next.effective_from == "2026-11-01")
	assert(next.item(&"bed-mulch").rate.cents == 6450)
	assert(int(applied["changed"]) == 1)


func test_applying_a_plan_leaves_the_book_it_was_read_from_alone() -> void:
	var book: CostBook = _book()
	var plan: Dictionary = ImportScript.plan(book, _rows("id,name,unit,cost\nbed-mulch,Bark mulch,m3,64.50\n"))
	ImportScript.apply(book, plan, "2026-11-01")
	assert(book.version == 3)
	assert(book.item(&"bed-mulch").rate.cents == 5800, "an estimate priced from v3 keeps its prices")


func test_the_new_book_says_where_its_prices_came_from() -> void:
	var book: CostBook = _book()
	var plan: Dictionary = ImportScript.plan(book, _rows("id,name,unit,cost\nbed-mulch,Bark mulch,m3,64.50\n"))
	var applied: Dictionary = ImportScript.apply(book, plan, "2026-11-01", "evan", 1780000000)
	var next: CostBook = applied["book"]
	assert(next.source.contains("imported price list"), next.source)
	assert(next.source.contains("by evan"), next.source)
	assert(next.source.contains("1 repriced"), next.source)


func test_a_plan_that_changes_nothing_is_refused_rather_than_made_a_new_version() -> void:
	var book: CostBook = _book()
	var plan: Dictionary = ImportScript.plan(book, _rows("id,name,unit,cost,waste\nbed-mulch,Bark mulch,m3,58.00,8%\n"))
	var applied: Dictionary = ImportScript.apply(book, plan, "2026-11-01")
	assert(not applied["ok"])
	assert(String(applied["reason"]).contains("changes no price"), String(applied["reason"]))


func test_a_price_change_without_a_date_is_refused_with_what_it_would_cost_the_record() -> void:
	var book: CostBook = _book()
	var plan: Dictionary = ImportScript.plan(book, _rows("id,name,unit,cost\nbed-mulch,Bark mulch,m3,64.50\n"))
	var applied: Dictionary = ImportScript.apply(book, plan, "next Tuesday")
	assert(not applied["ok"])
	assert(String(applied["reason"]).contains("is not a date"), String(applied["reason"]))


func test_a_plan_priced_in_another_currency_is_refused_naming_both() -> void:
	var book: CostBook = _book()
	var plan: Dictionary = ImportScript.plan(book, _rows("id,name,unit,cost\nbed-mulch,Bark mulch,m3,64.50\n", &"USD"))
	var applied: Dictionary = ImportScript.apply(book, plan, "2026-11-01")
	assert(not applied["ok"])
	assert(String(applied["reason"]).contains("priced in USD"), String(applied["reason"]))
	assert(String(applied["reason"]).contains("the book is in CAD"), String(applied["reason"]))


func test_a_created_item_arrives_priced_measured_and_kinded() -> void:
	var book: CostBook = _book()
	var plan: Dictionary = ImportScript.plan(
		book, _rows("id,name,unit,cost,waste,kind,supplier,cost code\nastroturf,Turf,SQ_FT,199.00,5%,Equipment,GreenCo,HARDSCAPE\n"), true
	)
	var applied: Dictionary = ImportScript.apply(book, plan, "2026-11-01")
	assert(applied["ok"], String(applied["reason"]))
	var next: CostBook = applied["book"]
	var fresh: CostItem = next.item(&"astroturf")
	assert(fresh != null)
	assert(fresh.rate.cents == 19900)
	assert(fresh.unit == &"SQ_FT")
	assert(fresh.kind == ItemScript.EQUIPMENT)
	assert(fresh.waste_ppm == 50000)
	assert(fresh.supplier == &"GreenCo")
	assert(fresh.cost_code == &"HARDSCAPE")
	assert(next.version == 4)


func test_a_plan_whose_ok_is_false_is_refused_rather_than_half_applied() -> void:
	var applied: Dictionary = ImportScript.apply(_book(), {"ok": false, "reason": "nothing read"}, "2026-11-01")
	assert(not applied["ok"])
	assert(String(applied["reason"]).contains("nothing read"), String(applied["reason"]))


func test_applying_a_plan_to_no_book_is_refused_rather_than_crashing() -> void:
	var applied: Dictionary = ImportScript.apply(null, ImportScript.plan(null, []), "2026-11-01")
	assert(not applied["ok"])
	assert(String(applied["reason"]).contains("no cost book"), String(applied["reason"]))


func test_planning_with_no_book_is_refused_rather_than_read_as_no_changes() -> void:
	var plan: Dictionary = ImportScript.plan(null, _rows("id,name,unit,cost\nbed-mulch,Bark mulch,m3,64.50\n"))
	assert(not plan["ok"])
	assert(String(plan["reason"]).contains("no cost book"), String(plan["reason"]))


func test_a_plan_reads_the_things_it_could_not_take_into_its_problems() -> void:
	var plan: Dictionary = ImportScript.plan(_book(), _rows(
		"id,name,unit,cost\nbed-mulch,Bark mulch,bushels,64.50\nhard-paver-60,Paving,SQ_FT,3.50\n"
	))
	var problems: Array = plan["problems"]
	assert(problems.size() == 1)
	assert(String(problems[0]).contains("bushels"), String(problems[0]))
	assert((plan["changes"] as Array).size() == 1, "one bad row does not stop the rest")
	assert(String((plan["changes"] as Array)[0]["id"]) == "hard-paver-60")


func test_the_supplier_and_the_cost_code_a_list_carries_reach_the_new_book() -> void:
	var book: CostBook = _book()
	var plan: Dictionary = ImportScript.plan(book, _rows(
		"id,name,unit,cost,supplier,cost code\nbed-mulch,Bark mulch,m3,64.50,NewCo,SOFT\n"
	))
	var applied: Dictionary = ImportScript.apply(book, plan, "2026-11-01")
	var next: CostBook = applied["book"]
	assert(next.item(&"bed-mulch").supplier == &"NewCo")
	assert(next.item(&"bed-mulch").cost_code == &"SOFT")


func test_a_list_with_no_supplier_column_leaves_the_supplier_the_book_had() -> void:
	var book: CostBook = _book()
	var plan: Dictionary = ImportScript.plan(book, _rows("id,name,unit,cost\nbed-mulch,Bark mulch,m3,64.50\n"))
	var applied: Dictionary = ImportScript.apply(book, plan, "2026-11-01")
	assert(applied["book"].item(&"bed-mulch").supplier == &"GreenCo")