extends Node
## The cost book: items, kits, versions, and the file it lives in.
##
## The arithmetic is proved in `test_biz_money.gd`, `test_biz_tax.gd` and `test_biz_units.gd`. What
## is tested here is the catalogue itself - that a price survives the file, that a recipe expands to
## what it says it does, and that every way a book can be wrong is *named* rather than priced from.

const BookScript := preload("res://scripts/biz/cost_book.gd")
const ItemScript := preload("res://scripts/biz/cost_item.gd")
const KitScript := preload("res://scripts/biz/cost_kit.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")
const UnitScript := preload("res://scripts/biz/work_unit.gd")

const SCRATCH := "user://biz/test-costbook.json"


## One item, with everything set: the ordinary case a test wants to vary one field of.
func _item(id: StringName, unit: StringName, cents: int) -> CostItem:
	var item: CostItem = ItemScript.make(id, String(id), unit, cents)
	item.cost_code = &"300-NEW-HARD"
	item.tax_code = &"HST-ON"
	item.waste_ppm = 80000
	return item


## A book with one material, one labour item and one kit that uses both - the smallest book that is
## worth loading.
func _book() -> CostBook:
	var book: CostBook = BookScript.make(3, "2026-01-01")
	book.source = "test"
	book.put_item(_item(&"PAVER-GRANITE", &"SQ_M", 4200))
	# A labour item is labour, not a material: `_item` defaults to MATERIAL, and a fixture that
	# quietly made an hour of work a material would let a wrong kind pass for a right one.
	var labour: CostItem = _item(&"LABOUR-LANDSCAPE", &"HOUR", 4500)
	labour.kind = CostItem.LABOR
	book.put_item(labour)
	var kit: CostKit = KitScript.make(&"PATIO", "Patio, granite", &"SQ_M")
	kit.add_line(&"PAVER-GRANITE", 1000)
	kit.add_line(&"LABOUR-LANDSCAPE", 350)
	kit.labour_hours_milli = 350
	book.put_kit(kit)
	return book


func _clean() -> void:
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(SCRATCH)
	if FileAccess.file_exists(SCRATCH + BookScript.TEMP_SUFFIX):
		DirAccess.remove_absolute(SCRATCH + BookScript.TEMP_SUFFIX)


func _any_contains(lines: Array, text: String) -> bool:
	for line: Variant in lines:
		if String(line).contains(text):
			return true
	return false


func _lines_text(lines: Array) -> String:
	return JSON.stringify(lines)


func test_an_item_round_trips_through_the_file_format() -> void:
	# Through the *text*, not just through the dictionary: JSON has one number type, so a reader
	# that trusted what it got would store a waste factor as 80000.0 and a kind as 0.0.
	var item := _item(&"MULCH-BARK-BULK", &"CU_YD", 3150)
	var text: String = JSON.stringify(item.to_dict())
	var reader := JSON.new()
	assert(reader.parse(text) == OK, reader.get_error_message())
	var back: CostItem = ItemScript.from_dict(reader.data)
	assert(back.id == item.id)
	assert(back.name == item.name)
	assert(back.unit == item.unit, "the unit came back as %s" % back.unit)
	assert(back.kind == CostItem.MATERIAL)
	assert(back.waste_ppm == 80000, "waste came back as %d" % back.waste_ppm)
	assert(back.cost_code == item.cost_code)
	assert(back.tax_code == item.tax_code)
	assert(back.rate.equals(item.rate), "the rate came back as %s" % back.rate.format_iso())
	assert(back.is_valid(), back.problem())
	# And a copy is independent: a book's prices are replaced, never reached into.
	var other: CostItem = item.copy()
	other.rate = MoneyScript.of(9999)
	assert(item.rate.cents == 3150, "the original price is untouched")


func test_a_book_survives_the_file_and_comes_back_sound() -> void:
	_clean()
	var book := _book()
	var written: Dictionary = book.save_to(SCRATCH)
	assert(bool(written["ok"]), String(written["reason"]))
	var read: Dictionary = BookScript.load_from(SCRATCH)
	assert(bool(read["ok"]), String(read["reason"]))
	var back: CostBook = read["book"]
	assert(back.version == 3, "the version is what an estimate records, so it has to survive")
	assert(back.effective_from == "2026-01-01")
	assert(back.currency == &"CAD")
	assert(back.source == "test")
	assert(back.item_count() == 2)
	assert(back.kit_count() == 1)
	assert(back.item(&"PAVER-GRANITE").rate.cents == 4200, "the price survived")
	assert(back.item(&"PAVER-GRANITE").waste_ppm == 80000, "and so did the waste factor")
	assert(back.kit(&"PATIO").line_at(1)["quantity_milli"] == 350)
	assert(back.problems().is_empty(), " and a book written and read back is a sound book")
	assert(not FileAccess.file_exists(SCRATCH + BookScript.TEMP_SUFFIX), "no half file is left behind")
	_clean()


func test_the_file_is_json_a_bookkeeper_can_read() -> void:
	# REQ-B7's other half: loadable **without Godot**. So the text may not name a script path or a
	# class, which is what a `.tres` does and why the book is not one.
	var text: String = _book().to_json()
	assert(text.contains("\"version\": 3"), "the version is legible")
	assert(text.contains("\"PAVER-GRANITE\""))
	assert(text.contains("\"effective_from\": \"2026-01-01\""))
	assert(not text.contains("res://"), "nothing in the file points at this project")
	assert(not text.contains("Object("), "and nothing in it needs a Godot reader")


func test_a_book_with_no_version_is_refused() -> void:
	# Everything downstream records the version it priced from. A book that cannot say is a book
	# whose estimates cannot explain themselves, so it is refused rather than defaulted.
	_clean()
	var file := FileAccess.open(SCRATCH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"effective_from": "2026-01-01", "items": {}}))
	file.close()
	var read: Dictionary = BookScript.load_from(SCRATCH)
	assert(not bool(read["ok"]), "a book with no version is not usable")
	assert(String(read["reason"]).contains("version"), String(read["reason"]))
	_clean()


func test_a_missing_or_unreadable_book_is_refused_with_a_reason() -> void:
	_clean()
	var missing: Dictionary = BookScript.load_from(SCRATCH)
	assert(not bool(missing["ok"]))
	assert(String(missing["reason"]).contains("no cost book"), String(missing["reason"]))

	var file := FileAccess.open(SCRATCH, FileAccess.WRITE)
	file.store_string("this is not json at all")
	file.close()
	var rubbish: Dictionary = BookScript.load_from(SCRATCH)
	assert(not bool(rubbish["ok"]))
	# The line it gave up on, because "not readable JSON" alone sends nobody to the right place.
	assert(String(rubbish["reason"]).contains("line"), String(rubbish["reason"]))

	file = FileAccess.open(SCRATCH, FileAccess.WRITE)
	file.store_string("[\"a list\", \"of things\"]")
	file.close()
	var wrong_shape: Dictionary = BookScript.load_from(SCRATCH)
	assert(not bool(wrong_shape["ok"]))
	assert(String(wrong_shape["reason"]).contains("not a JSON object"), String(wrong_shape["reason"]))
	_clean()


func test_an_item_that_cannot_be_priced_is_refused_rather_than_stored() -> void:
	# Each of these is a line that would price something at nothing, so none of them may be stored.
	var unknown_unit: CostItem = _item(&"ODD", &"FURLONG", 100)
	assert(not unknown_unit.is_valid())
	assert(unknown_unit.problem().contains("FURLONG"), unknown_unit.problem())

	var unreadable: CostItem = _item(&"ODD", &"EACH", 100)
	unreadable.rate = MoneyScript.invalid()
	assert(not unreadable.is_valid())
	assert(unreadable.problem().contains("rate"), unreadable.problem())

	var absurd: CostItem = _item(&"ODD", &"EACH", 100)
	absurd.waste_ppm = CostItem.MAX_WASTE_PPM + 1
	assert(not absurd.is_valid())
	assert(absurd.problem().contains("waste"), absurd.problem())

	var no_name: CostItem = _item(&"ODD", &"EACH", 100)
	no_name.name = "   "
	assert(not no_name.is_valid())

	var book := _book()
	assert(not book.add_item(unknown_unit), "and the book will not take them")
	assert(book.item_count() == 2, "so its count did not move")


func test_a_duplicate_id_is_refused_rather_than_replaced() -> void:
	# Changing what a price *is* is a new version of the book. A silent replace is how a catalogue
	# loses a price nobody meant to lose.
	var book := _book()
	var dearer: CostItem = _item(&"PAVER-GRANITE", &"SQ_M", 4800)
	assert(not book.add_item(dearer), "the id is taken")
	assert(book.item(&"PAVER-GRANITE").rate.cents == 4200, "and the price did not move")
	# The importer's door is separate, and it says what it is for.
	assert(book.put_item(dearer))
	assert(book.item(&"PAVER-GRANITE").rate.cents == 4800)
	assert(book.item_count() == 2, "a replace is not a second item")


func test_a_kit_expands_to_its_items_and_scales_by_what_is_being_made() -> void:
	# The recipe is per unit of output, so a 45 m² patio is 45 x kit and the kit's lines scale. The
	# expanded lines carry **the item's own** unit, cost code and tax code, because a kit that spans
	# materials and labour must still cost to the right phases.
	var book := _book()
	var expanded: Dictionary = book.expand_kit(&"PATIO", 45000)
	assert(bool(expanded["ok"]), String(expanded["reason"]))
	var lines: Array = expanded["lines"]
	assert(lines.size() == 2, "two lines came out, %d did" % lines.size())

	var pavers: Dictionary = lines[0]
	assert(pavers["item_id"] == &"PAVER-GRANITE")
	assert(pavers["quantity_milli"] == 45000, "45 m² of pavers, got %d" % pavers["quantity_milli"])
	assert(pavers["unit"] == &"SQ_M")
	assert(pavers["cost_code"] == &"300-NEW-HARD", "the item's cost code, not the kit's")
	assert(pavers["tax_code"] == &"HST-ON", "and the item's tax code")

	var labour: Dictionary = lines[1]
	assert(labour["item_id"] == &"LABOUR-LANDSCAPE")
	assert(labour["quantity_milli"] == 15750, "0.35 h/m² over 45 m² is 15.75 h, got %d" % labour["quantity_milli"])
	assert(labour["unit"] == &"HOUR")
	assert(labour["kind"] == CostItem.LABOR)

	# A kit's output is priced per m² while its lines are in yd³ and hours: the dimensions are
	# deliberately different, which is why a kit is a recipe and not a unit conversion.
	var per_unit: Dictionary = book.expand_kit(&"PATIO", 1000)
	assert(per_unit["lines"][1]["quantity_milli"] == 350, "one square metre takes 0.35 hours")


func test_a_nested_kit_expands_to_the_same_lines_as_writing_it_out() -> void:
	# AC-B9. The base recipe is a kit of its own, because the same base is used under four different
	# surfaces - and expanding the nested version has to produce what a person would have written.
	var nested := _book()
	var base: CostKit = KitScript.make(&"BASE-COMPACTED", "Compacted base", &"SQ_M")
	base.add_line(&"PAVER-GRANITE", 0)
	base.lines.clear()
	base.add_line(&"LABOUR-LANDSCAPE", 100)
	nested.put_item(_item(&"BASE-GRAVEL", &"CU_YD", 2800))
	base.add_line(&"BASE-GRAVEL", 120)
	nested.put_kit(base)
	var patio: CostKit = KitScript.make(&"PATIO", "Patio, granite", &"SQ_M")
	patio.add_line(&"PAVER-GRANITE", 1000)
	patio.add_line(&"BASE-COMPACTED", 1000)
	patio.add_line(&"LABOUR-LANDSCAPE", 350)
	nested.put_kit(patio)

	# The same thing written out flat, in the order the nested one expands: the base's lines where
	# the base's line was.
	var flat := _book()
	flat.put_item(_item(&"BASE-GRAVEL", &"CU_YD", 2800))
	var written: CostKit = KitScript.make(&"PATIO", "Patio, granite", &"SQ_M")
	written.add_line(&"PAVER-GRANITE", 1000)
	written.add_line(&"LABOUR-LANDSCAPE", 100)
	written.add_line(&"BASE-GRAVEL", 120)
	written.add_line(&"LABOUR-LANDSCAPE", 350)
	flat.put_kit(written)

	var from_nested: Dictionary = nested.expand_kit(&"PATIO", 1000)
	var from_flat: Dictionary = flat.expand_kit(&"PATIO", 1000)
	assert(bool(from_nested["ok"]), String(from_nested["reason"]))
	assert(bool(from_flat["ok"]), String(from_flat["reason"]))
	assert(from_nested["lines"].size() == 4, "the base's two lines replaced its one line")
	assert(
		_lines_text(from_nested["lines"]) == _lines_text(from_flat["lines"]),
		"nested:\n%s\nwritten out:\n%s" % [
			_lines_text(from_nested["lines"]), _lines_text(from_flat["lines"])
		]
	)


func test_a_kit_cycle_is_refused_naming_the_chain() -> void:
	# AC-B8, and the reason a cycle is refused outright rather than caught by the depth cap: a
	# message that says "too deep" sends a reader looking for a long chain, not a loop.
	var book := _book()
	var first: CostKit = KitScript.make(&"TURF", "Turf", &"SQ_M")
	first.add_line(&"TOPSOIL", 1000)
	var second: CostKit = KitScript.make(&"TOPSOIL", "Topsoil", &"SQ_M")
	second.add_line(&"TURF", 1000)
	book.put_kit(first)
	book.put_kit(second)

	var expanded: Dictionary = book.expand_kit(&"TURF", 1000)
	assert(not bool(expanded["ok"]), "a cycle is not an expansion")
	assert(expanded["lines"].is_empty(), "and nothing is priced from it")
	assert(
		String(expanded["reason"]).contains("TURF -> TOPSOIL -> TURF"),
		"the chain is named: %s" % expanded["reason"]
	)
	# And the book says so before an estimate is priced from it, not while a customer waits.
	var problems: Array[String] = book.problems()
	assert(_any_contains(problems, "circular"), " | ".join(problems))


func test_a_kit_that_nests_deeper_than_the_cap_is_refused() -> void:
	# A generated book can be deep without being circular, and an expansion that runs away is a hang
	# rather than an answer.
	var book := _book()
	for level in CostBook.MAX_DEPTH + 2:
		var kit: CostKit = KitScript.make(StringName("LEVEL-%d" % level), "Level %d" % level, &"SQ_M")
		kit.add_line(StringName("LEVEL-%d" % (level + 1)), 1000)
		book.put_kit(kit)
	book.put_kit(KitScript.make(StringName("LEVEL-%d" % (CostBook.MAX_DEPTH + 2)), "Last", &"SQ_M"))

	var expanded: Dictionary = book.expand_kit(&"LEVEL-0", 1000)
	assert(not bool(expanded["ok"]), "the depth cap refuses rather than recursing")
	assert(String(expanded["reason"]).contains("deeper"), String(expanded["reason"]))
	assert(String(expanded["reason"]).contains("LEVEL-0"), "and names the chain from the top")


func test_a_kit_naming_something_that_is_not_there_is_refused_naming_both() -> void:
	var book := _book()
	var kit: CostKit = book.kit(&"PATIO")
	kit.add_line(&"GHOST-ITEM", 1000)
	var expanded: Dictionary = book.expand_kit(&"PATIO", 1000)
	assert(not bool(expanded["ok"]))
	assert(String(expanded["reason"]).contains("GHOST-ITEM"), String(expanded["reason"]))
	assert(String(expanded["reason"]).contains("PATIO"), "and says which recipe asked for it")

	# An id nobody has heard of is refused the same way, and says who wanted it.
	var unknown: Dictionary = book.expand_kit(&"NOSUCH-KIT", 1000)
	assert(not bool(unknown["ok"]))
	assert(String(unknown["reason"]).contains("NOSUCH-KIT"), String(unknown["reason"]))


func test_a_loaded_book_names_everything_wrong_with_it() -> void:
	# The load path is where a bad book arrives from outside, so this is where every kind of wrong
	# has to be caught - and it is caught by *naming* it, because a book that quietly dropped a
	# recipe is a book that will price the work wrongly, silently.
	var good: Dictionary = _item(&"PAVER-GRANITE", &"SQ_M", 4200).to_dict()
	var bad_unit: Dictionary = _item(&"ODD", &"FURLONG", 100).to_dict()
	var data := {
		"version": 1,
		"effective_from": "2026-01-01",
		"currency": "CAD",
		"items": {"PAVER-GRANITE": good, "ODD": bad_unit},
		"kits": {
			"BROKEN": {
				"id": "BROKEN", "name": "Broken", "output_unit": "SQ_M", "yield_milli": 1000,
				"lines": [{"item_id": "GHOST", "quantity_milli": 1000}],
			},
			"LOOP-A": {
				"id": "LOOP-A", "name": "Loop A", "output_unit": "SQ_M", "yield_milli": 1000,
				"lines": [{"item_id": "LOOP-B", "quantity_milli": 1000}],
			},
			"LOOP-B": {
				"id": "LOOP-B", "name": "Loop B", "output_unit": "SQ_M", "yield_milli": 1000,
				"lines": [{"item_id": "LOOP-A", "quantity_milli": 1000}],
			},
		},
	}
	var book := BookScript.from_dict(data)
	var problems: Array[String] = book.problems()
	assert(problems.size() >= 4, "everything wrong is reported: %s" % " | ".join(problems))
	assert(
		_any_contains(problems, "FURLONG"),
		"the unit that is not a unit: %s" % " | ".join(problems)
	)
	assert(_any_contains(problems, "GHOST"), "the item that is not there")
	assert(_any_contains(problems, "circular"), "the loop")
	assert(not book.is_sound())
	# The good item is still usable, so a book with one bad row is not a book with none.
	assert(book.item(&"PAVER-GRANITE") != null)
	assert(book.item(&"ODD") == null, "and the unusable one is not stored")


func test_a_new_version_is_a_new_book_and_the_old_one_does_not_move() -> void:
	# AC-B7's premise, tested on this side of it: the book an estimate was priced from cannot be
	# changed by publishing the next one. Prices are replaced, never reached into.
	var current := _book()
	var next: CostBook = current.bump_version("2027-04-01")
	assert(next.version == 4, "the next version is one past this one")
	assert(next.effective_from == "2027-04-01")
	assert(current.version == 3, "and the book in force did not move")
	assert(current.effective_from == "2026-01-01")

	assert(next.put_item(_item(&"PAVER-GRANITE", &"SQ_M", 5900)), "the new book takes a new price")
	assert(next.item(&"PAVER-GRANITE").rate.cents == 5900)
	assert(
		current.item(&"PAVER-GRANITE").rate.cents == 4200,
		"and the old book still costs what it cost"
	)
	assert(current.problems().is_empty(), "the book in force is still sound")


func test_a_recipe_line_too_small_to_survive_the_rounding_is_not_a_priced_line() -> void:
	# A throwaway amount of work needs no material, and saying so is the arithmetic rather than an
	# error. The recipe line has to be a trace for this to happen at all: one *thousandth* of a
	# square metre of work per square metre (a wipe or a bead of sealant), asked for as a tenth of a
	# square metre, is a ten-thousandth of a unit - which rounds to nothing and must not be rounded
	# up into a line nobody asked for.
	var book := _book()
	var trace: CostKit = KitScript.make(&"DETAIL", "Detail", &"SQ_M")
	trace.add_line(&"PAVER-GRANITE", 1)
	book.put_kit(trace)
	var tiny: Dictionary = book.expand_kit(&"DETAIL", 100)
	assert(bool(tiny["ok"]), "a small quantity is not an error: %s" % tiny["reason"])
	assert(tiny["lines"].is_empty(), "and it prices no line rather than a made-up one")

	# The same kit at a real size does price a line. The other reading of "too small" - a tenth of an
	# item - is a quantity, not a rounding: 0.1 of a square metre of pavers is 100 thousandths of one.
	var priced: Dictionary = book.expand_kit(&"DETAIL", 1000)
	assert(priced["lines"].size() == 1, "a whole unit of output prices the line")
	assert(priced["lines"][0]["quantity_milli"] == 1, "and it is a thousandth of the item")
	var round_size: CostKit = KitScript.make(&"PAVING", "Paving", &"SQ_M")
	round_size.add_line(&"PAVER-GRANITE", 1000)
	book.put_kit(round_size)
	var small: Dictionary = book.expand_kit(&"PAVING", 100)
	assert(small["lines"][0]["quantity_milli"] == 100, "0.1 m² of paving is 0.1 m² of pavers")


func test_a_quantity_scales_by_the_one_rounding_rule() -> void:
	# The rule is `Money.rounded_div` rather than a second one written here: a quantity and an amount
	# that rounded differently would be two rules to keep in step.
	assert(KitScript.scaled_quantity(350, 45000, 1000) == 15750)
	assert(KitScript.scaled_quantity(1, 500, 1000) == 1, "a half rounds away from zero, not to even")
	assert(KitScript.scaled_quantity(1, 499, 1000) == 0)
	assert(KitScript.scaled_quantity(1000, 1000, 1000) == 1000)
	assert(KitScript.scaled_quantity(1000, 1000, 0) == 0, "a yield of nothing is not a division")
	assert(KitScript.scaled_quantity(1000, 0, 1000) == 0, "and neither is being asked for nothing")