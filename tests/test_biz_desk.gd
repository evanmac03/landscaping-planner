extends Node
## The estimate desk: the join between the drawing, the cost book and the two business engines.
##
## These tests are about the *join* - that a drawing becomes priced lines in one step, that what
## cannot be priced is named rather than dropped, that sending freezes what went out, and that the
## desk never recomputes a figure the estimate already owns.

const DeskScript := preload("res://scripts/biz/estimate_desk.gd")
const Document := preload("res://scripts/draft/draft_document.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")
const TakeoffScript := preload("res://scripts/biz/takeoff.gd")

const PROPOSAL_PATH := "user://biz/proposals"


func _drawing() -> DraftDocument:
	var document: DraftDocument = Document.new()
	document.add(Entity.make_rectangle(Vector2(0, 0), Vector2(6, 4)), LayerSet.NEW_HARDSCAPE)
	document.add(Entity.make_circle(Vector2(20, 0), 1.5), LayerSet.NEW_PLANTING)
	return document


func _desk(with_drawing: bool = true) -> DeskScript:
	var desk: DeskScript = DeskScript.new()
	if with_drawing:
		desk.bind(_drawing())
	assert(desk.load_book()["ok"], "the shipped book loads")
	return desk


func _clean_proposals() -> void:
	var dir: DirAccess = DirAccess.open(PROPOSAL_PATH)
	if dir == null:
		return
	for name: String in dir.get_files():
		dir.remove(name)


func test_the_starter_book_is_what_prices_a_plan_until_a_business_writes_its_own() -> void:
	var desk: DeskScript = _desk()
	assert(desk.book != null, "there is a book")
	assert(desk.book.item_count() > 10, "with the starter items in it: %d" % desk.book.item_count())
	assert(desk.book.kit_count() > 0, "and the starter kits")
	assert(desk.book_source == DeskScript.SHIPPED_BOOK, "read from the shipped file: %s" % desk.book_source)


func test_the_book_a_business_wrote_beats_the_one_that_shipped() -> void:
	# A book found at the office's own path is the one used: a business that has priced its own work
	# means those prices, and pricing from the starter list instead would be the worst kind of quiet
	# wrong. A path that is there and will not load is refused rather than fallen back from, because
	# the file that will not load is the file somebody meant to use.
	var desk: DeskScript = _desk(false)
	var own: String = "user://biz/test-costbook.json"
	var copied: Dictionary = (desk.book as CostBook).save_to(own)
	assert(bool(copied["ok"]), "a copy of the starter book was written")
	var read: Dictionary = desk.load_book(own)
	assert(bool(read["ok"]), "and read back: %s" % String(read["reason"]))
	assert(read["source"] == own, "from where it was told to look: %s" % String(read["source"]))
	assert((read["book"] as CostBook).item_count() > 10, "and it is a whole book")
	DirAccess.remove_absolute(own)
	var broken: String = "user://biz/broken-costbook.json"
	var file: FileAccess = FileAccess.open(broken, FileAccess.WRITE)
	file.store_string("{\"items\": {\"hard-paving-interlock\": {\"name\": \"Paving\"}}}")
	file.close()
	var failed: Dictionary = desk.load_book(broken)
	assert(not bool(failed["ok"]), "a book that will not load is refused")
	assert(String(failed["reason"]).contains(broken), "naming the file: %s" % String(failed["reason"]))
	DirAccess.remove_absolute(broken)
	# With no path named, the office's own book is looked for first and the shipped one is the answer
	# when there is none: this is the path the program takes when it opens the panel.
	var fell_back: Dictionary = desk.load_book()
	assert(bool(fell_back["ok"]), "the shipped book is found when nothing else is there")
	assert(fell_back["source"] == DeskScript.SHIPPED_BOOK, String(fell_back["source"]))


func test_a_plan_becomes_priced_lines_in_one_step() -> void:
	var desk: DeskScript = _desk()
	var result: Dictionary = desk.take_off()
	assert(bool(result["ok"]), "the takeoff ran: %s" % String(result["reason"]))
	assert(int(result["measured"]) == 2, "the paving and the plant symbol: %d" % int(result["measured"]))
	assert(int(result["priced"]) == 2, "both were priced: %d" % int(result["priced"]))
	assert(desk.estimate.line_count() == 2, "and both are lines of the estimate")
	assert(desk.estimate.total(desk.book).cents > 0, "the total is money")
	# The paving is 6 x 4 = 24 m2 and the item that prices it is the one the layer names.
	var paving: EstimateLine = desk.estimate.lines[0]
	assert(paving.quantity_milli == 24000, "24 m2, in thousandths: %d" % paving.quantity_milli)
	assert(paving.cost_item == &"hard-paving-interlock", "priced by the layer's own item")
	assert(paving.description.contains("Interlock"), "and the line says what it is: %s" % paving.description)


func test_a_line_the_book_cannot_price_is_named_rather_than_dropped() -> void:
	var desk: DeskScript = _desk()
	# A contour line is work the takeoff deliberately does not measure (grading is a volume), and a
	# note has to exist for it, because "why is nothing on my drawing in the proposal" is the question
	# every designer asks.
	desk.document.add(
		Entity.make_line(Vector2(0, 20), Vector2(30, 20)), LayerSet.GRADING_CONTOUR
	)
	desk.take_off()
	var notes: Array[String] = desk.notes()
	assert(notes.size() == 1, "one thing was left out: %s" % str(notes))
	assert(notes[0].contains("volume"), "and it says why: %s" % notes[0])
	# A layer the book does not price is refused by name and is *not* a line of the estimate: a
	# proposal that quietly omitted the irrigation is worse than one that says it has no price.
	desk.document.add(Entity.make_circle(Vector2(40, 0), 0.2), LayerSet.IRRIGATION)
	desk.take_off()
	assert(desk.refused.is_empty(), "an irrigation head is priced by the starter book")
	# Every item that costs to that code has to go, and then nothing prices it at all. One item is
	# not enough: the takeoff offers the *other* irrigation item, which is the behaviour that keeps a
	# plan priced when the office's first choice is out of stock.
	assert(desk.book.erase_item(&"irr-head-spray"), "the book can lose an item")
	desk.take_off()
	assert(desk.refused.is_empty(), "the other irrigation item still prices it")
	assert(desk.estimate.lines[2].cost_item == &"irr-zone-valve", "by the layer's code")
	assert(desk.book.erase_item(&"irr-zone-valve"), "and it can lose that one too")
	desk.take_off()
	assert(desk.refused.size() == 1, "with the item gone it is refused: %s" % str(desk.refused))
	assert(desk.refused[0].contains("nothing in the cost book is priced by"), "in the takeoff's words: %s" % desk.refused[0])
	assert(not desk.check()["ok"], "and the check is not clean")
	assert(desk.check()["problems"].size() == 1, "one thing to fix, said once")
	assert(
		desk.estimate_lines().has(desk.refused[0]) == false,
		"nothing in the proposal is the refusal itself"
	)


func test_a_planting_list_with_no_species_is_refused_by_name_and_counted_once() -> void:
	var desk: DeskScript = _desk()
	desk.plant_rows = [{
		"id": &"",
		"count": 30,
		"botanical_name": "no species recorded",
		"common_name": "",
		"cultivar": "",
		"spread_cm": 0,
		"height_cm": 0,
	}]
	var result: Dictionary = desk.take_off()
	assert(int(result["priced"]) == 1, "the paving is priced and the thirty are not")
	# One fault, one sentence: the takeoff's fuller explanation is the one that is printed, not it and
	# the estimate's shorter refusal together.
	assert(desk.refused.size() == 1, "the plants are refused once: %s" % str(desk.refused))
	assert(desk.refused[0].contains("30 plants have no species recorded"), "fully: %s" % desk.refused[0])
	# The plant symbol drawn on the drawing is not a second plant: with a planting list the layer's
	# own geometry is left out, which is the double-count rule.
	assert(desk.notes().size() == 1, "and the symbol left out is noted: %s" % str(desk.notes()))
	assert(desk.notes()[0].contains("props"), "for the reason the takeoff gives: %s" % desk.notes()[0])


func test_the_tax_is_the_estimate_s_own_and_re_prices_every_line() -> void:
	var desk: DeskScript = _desk()
	desk.take_off()
	var before: int = desk.estimate.total(desk.book).cents
	assert(desk.estimate.tax(desk.book).cents == 0, "no tax code means no tax charged")
	assert(desk.set_tax_code(&"HST-ON"), "the code is one the table has")
	assert(desk.estimate.tax_code == &"HST-ON", "and the estimate now carries it")
	assert(desk.estimate.lines[0].tax_code == &"HST-ON", "as do its lines")
	assert(desk.estimate.tax(desk.book).cents > 0, "so tax is charged")
	assert(desk.estimate.total(desk.book).cents > before, "and the total rose by it")
	# A line that was already added keeps the code it was added with, which is why choosing a code
	# re-prices rather than editing the estimate's default in place.
	assert(
		desk.estimate.total(desk.book).cents
			== desk.estimate.price_before_tax().cents + desk.estimate.tax(desk.book).cents,
		"and the total is the price plus the tax"
	)
	assert(not desk.set_tax_code(&"NOT-A-CODE"), "a code that is not a code is refused")
	assert(desk.tax_code == &"HST-ON", "and the choice is unchanged")


func test_sending_needs_somebody_and_holds_what_went_out() -> void:
	var desk: DeskScript = _desk()
	desk.take_off()
	var nobody: Dictionary = desk.send("")
	assert(not bool(nobody["ok"]), "a proposal with no recipient is refused")
	assert(String(nobody["reason"]).contains("somebody"), "and says so: %s" % String(nobody["reason"]))
	var sent: Dictionary = desk.send("Jane Doe")
	assert(bool(sent["ok"]), "sent: %s" % String(sent["reason"]))
	assert(desk.estimate.is_frozen(), "which freezes it")
	assert(desk.freeze_holds(), "and the hash still describes the content")
	# An edit after it went out does not change what went out: that is the whole point of the hash.
	desk.estimate.lines[0].quantity_milli += 1000
	assert(not desk.freeze_holds(), "an edit after sending is visible as a broken hash")
	var again: Dictionary = desk.send("Jane Doe")
	assert(not bool(again["ok"]), "and it cannot be sent twice: %s" % String(again["reason"]))


func test_a_proposal_that_has_gone_is_revised_and_a_draft_is_edited() -> void:
	var desk: DeskScript = _desk()
	desk.take_off()
	var early: Dictionary = desk.revision()
	assert(not bool(early["ok"]), "a draft is not revised: %s" % String(early["reason"]))
	desk.send("Jane Doe")
	var lines: int = desk.estimate.line_count()
	var next: Dictionary = desk.revision()
	assert(bool(next["ok"]), "the sent one is: %s" % String(next["reason"]))
	assert(int(next["revision"]) == 1, "revision 1")
	assert(not desk.estimate.is_frozen(), "and it is open for editing")
	assert(desk.estimate.line_count() == lines, "with the same lines in it")


func test_the_totals_block_is_the_estimate_s_own_figures() -> void:
	var desk: DeskScript = _desk()
	desk.take_off()
	desk.estimate.overhead_ppm = 100000
	desk.estimate.profit_ppm = 200000
	desk.estimate.deposit_ppm = 250000
	var text: String = desk.totals_text()
	assert(text.contains("subtotal"), text)
	assert(text.contains("total"), text)
	assert(text.contains(desk.estimate.total(desk.book).format_with_currency()), "the total is its total")
	assert(text.contains("gross margin"), "and the margin is named")
	assert(text.contains("25.000%"), "the deposit share is stated: %s" % text)
	# The line a person reads is the line the engine writes.
	for line: EstimateLine in desk.estimate.lines:
		assert(desk.estimate_lines().has(line.line_text()), "every line is printed as it prints")
	# And a line that orders waste says so, because otherwise the printed line does not multiply: the
	# paving in the starter book is material with 5% waste for the cuts.
	var paving: EstimateLine = desk.estimate.lines[0]
	assert(paving.waste_ppm == 50000, "the starter paving carries waste: %d" % paving.waste_ppm)
	assert(paving.line_text().contains("+5.0% waste"), paving.line_text())
	assert(
		paving.line_text().contains(paving.extension().format_with_currency()),
		"and the extension beside it is the one it prints: %s" % paving.line_text()
	)


func test_the_proposal_is_written_beside_the_drawings_and_reads_back() -> void:
	var desk: DeskScript = _desk()
	desk.take_off()
	desk.send("Jane Doe")
	var written: Dictionary = desk.write_proposal()
	assert(bool(written["ok"]), "written: %s" % String(written["reason"]))
	var path: String = String(written["path"])
	assert(path.begins_with(PROPOSAL_PATH), "into the proposals folder: %s" % path)
	assert(FileAccess.file_exists(path), "and it is there")
	var text: String = FileAccess.open(path, FileAccess.READ).get_as_text()
	assert(text.contains("Jane Doe"), "with the customer on it")
	assert(text.contains("total"), "and the total")
	assert(text.contains(desk.estimate.total(desk.book).format_with_currency()), "which is the total")
	_clean_proposals()


func test_a_desk_with_no_drawing_or_no_book_says_which() -> void:
	var empty: DeskScript = DeskScript.new()
	var no_drawing: Dictionary = empty.take_off()
	assert(not bool(no_drawing["ok"]), "nothing to measure")
	assert(String(no_drawing["reason"]).contains("drawing"), String(no_drawing["reason"]))
	assert(empty.describe().contains("no drawing"), empty.describe())
	var bound: DeskScript = DeskScript.new()
	bound.bind(_drawing())
	var no_book: Dictionary = bound.take_off()
	assert(not bool(no_book["ok"]), "and nothing to price with")
	assert(String(no_book["reason"]).contains("cost book"), String(no_book["reason"]))
	assert(bound.describe().contains("no cost book"), bound.describe())
	# Measuring without a book is refused rather than done and left unpriced, and `is_ready` is the
	# question a panel asks before offering the button at all.
	assert(not bound.is_ready(), "not ready to price")
	assert(bound.load_book()["ok"] and bound.is_ready(), "and ready once the book is read")


func test_the_desk_names_the_codes_the_tax_table_and_the_book_hold() -> void:
	var desk: DeskScript = _desk()
	var codes: Array[StringName] = desk.tax_codes()
	assert(codes.has(&"NONE") and codes.has(&"HST-ON"), "the shipped codes: %s" % str(codes))
	assert(desk.tax_code_name(&"HST-ON") == "HST 13%", desk.tax_code_name(&"HST-ON"))
	# A code a business added to its own book is offered too, which is the point of tax being data.
	desk.book.add_tax_code(&"CITY-LEVY", {
		"name": "City levy 2%", "components": [{"name": "Levy", "rate_ppm": 20000, "compounds": false}],
	})
	assert(desk.tax_codes().has(&"CITY-LEVY"), "the book's own code is offered")
	assert(desk.tax_code_name(&"CITY-LEVY") == "City levy 2%", desk.tax_code_name(&"CITY-LEVY"))
	assert(desk.set_tax_code(&"CITY-LEVY"), "and can be chosen")


func test_the_desk_does_not_recompute_a_figure_the_estimate_owns() -> void:
	# Every money figure in the desk comes from the estimate. The way to see that is to change the
	# estimate and read the desk again: if the desk had its own arithmetic they would drift.
	var desk: DeskScript = _desk()
	desk.take_off()
	var first: String = desk.totals_text()
	desk.estimate.lines[0].waste_ppm = 100000
	var second: String = desk.totals_text()
	assert(first != second, "the desk followed the estimate")
	assert(
		second.contains(desk.estimate.subtotal().format_with_currency()),
		"and its subtotal is the estimate's"
	)
	var summary: Dictionary = desk.estimate.summary(desk.book)
	var amounts: Array = [summary["subtotal"] as MoneyScript]
	assert(amounts[0] is MoneyScript, "the summary hands back money and not numbers")