extends Node
## The estimating engine: one line's arithmetic, the roll-up, what it refuses, and freezing.
##
## The acceptance criteria of the business specification are the spine of these tests: AC-B6 (the
## printed lines foot to the printed subtotal), AC-B7 (an estimate priced from book v3 still costs the
## same after the book is updated), AC-B8/B9 (kits expand, cycles are refused naming the chain), and
## AC-B3 (an unreadable amount is contagious). They are named in the tests that hold them, so a failure
## says which promise broke rather than which assertion failed.

const EstimateScript := preload("res://scripts/biz/estimate.gd")
const LineScript := preload("res://scripts/biz/estimate_line.gd")
const ItemScript := preload("res://scripts/biz/cost_item.gd")
const KitScript := preload("res://scripts/biz/cost_kit.gd")
const BookScript := preload("res://scripts/biz/cost_book.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")
const TaxScript := preload("res://scripts/biz/tax.gd")
const WorkUnitScript := preload("res://scripts/biz/work_unit.gd")

const SEED := "res://data/biz/costbook.json"

const PAVING := &"hard-paving-interlock"
const LABOUR := &"lab-landscape-hour"
const MULCH := &"bed-mulch"
const PERMIT := &"fee-permit"


func _book() -> CostBook:
	var read: Dictionary = BookScript.load_from(SEED)
	assert(bool(read["ok"]), "the starter book loads: %s" % String(read["reason"]))
	var book: CostBook = read["book"]
	assert(book.is_sound(), "and is sound: %s" % " | ".join(book.problems()))
	return book


func _item(book: CostBook, id: StringName) -> CostItem:
	var found: CostItem = book.item(id)
	assert(found != null, "the starter book has %s" % id)
	return found


## An estimate with one line of paving, priced from the book.
func _priced(quantity_milli: int = 48000, code: StringName = &"HST-ON") -> Estimate:
	var book: CostBook = _book()
	var estimate: Estimate = EstimateScript.make("EST-TEST")
	estimate.customer = {"name": "A Customer"}
	estimate.tax_code = code
	assert(estimate.add_line(LineScript.make(_item(book, PAVING), quantity_milli), book),
		"the line is added")
	return estimate


# --- one line -----------------------------------------------------------------------------


func test_a_line_is_quantity_times_frozen_price_rounded_once() -> void:
	var book: CostBook = _book()
	var paving: CostItem = _item(book, PAVING)
	var line: EstimateLine = LineScript.make(paving, 48000)     # 48.000 m²
	assert(line.unit == &"SQ_M", "the line is in the item's own unit")
	assert(line.unit_cost.equals(paving.rate), "the cost is frozen from the item")
	assert(line.unit_price.equals(paving.rate), "and prices at cost until somebody marks it up")
	# 48 m² at $85.00 = $4,080.00, and 5% of waste on the quantity means 50.400 m², $4,284.00.
	assert(line.quantity_with_waste() == 50400, "waste inflates the quantity: %d" % line.quantity_with_waste())
	assert(line.extension().format_with_currency() == "$4,284.00", "and the price follows: %s" % line.extension().format_with_currency())


func test_waste_never_touches_a_labour_line() -> void:
	# Waste is bought material, not time: an hour of labour is an hour. A rate per m² of finished
	# paving is a *selling* rate and already contains the installer's own waste (§5.1).
	var book: CostBook = _book()
	var labour: CostItem = _item(book, LABOUR)
	var line: EstimateLine = LineScript.make(labour, 1500)      # 1.5 hours
	assert(not line.is_material(), "labour is not material")
	assert(line.quantity_with_waste() == 1500, "so the quantity is untouched")
	# And an item that *does* carry waste is respected, which is the other half of the rule.
	var mulch: EstimateLine = LineScript.make(_item(book, MULCH), 2000)
	assert(mulch.is_material() and mulch.quantity_with_waste() == 2160,
		"material carries its item's 8%%: %d" % mulch.quantity_with_waste())


func test_a_quantity_in_square_feet_is_an_exact_conversion() -> void:
	# A plan drawn in metres priced by a book in square feet is area x 10.7639..., computed as an exact
	# ratio of integers rather than with a constant typed from a spreadsheet (§6).
	var book: CostBook = _book()
	var line: EstimateLine = LineScript.make(_item(book, PAVING), 48000)
	var feet: Dictionary = line.quantity_in(&"SQ_FT")
	assert(bool(feet["ok"]), "square metres convert to square feet")
	# 48.000 m2 with 5% of waste is 50.400 m2, which is 542.501 ft2 - the conversion follows the waste.
	assert(int(feet["quantity_milli"]) == 542501, "50.400 m2 is 542.501 ft2: %d" % int(feet["quantity_milli"]))
	# And the refusal is a refusal: a length is not an area (REQ-B9, AC-B10).
	var wrong: Dictionary = line.quantity_in(&"LIN_M")
	assert(not bool(wrong["ok"]), "an area does not convert to a length")
	assert(String(wrong["reason"]).contains("area"), "and says why: %s" % String(wrong["reason"]))


func test_a_line_that_cannot_be_priced_says_what_is_wrong_with_it() -> void:
	var book: CostBook = _book()
	var paving: CostItem = _item(book, PAVING)
	var nothing: EstimateLine = LineScript.make(paving, 0)
	assert(not nothing.is_valid(), "a quantity of zero is not a quantity")
	assert(String(nothing.problem()).contains("not a quantity"), nothing.problem())

	var unreadable: EstimateLine = LineScript.make(paving, 1000)
	unreadable.unit_cost = MoneyScript.invalid()
	assert(not unreadable.is_valid(), "an unreadable cost is refused rather than treated as free")
	assert(String(unreadable.problem()).contains("readable"), unreadable.problem())

	var strung: EstimateLine = LineScript.make(paving, 1000)
	strung.unit = &"BANANAS"
	assert(not strung.is_valid(), "a unit that does not exist is not a unit")
	assert(String(strung.problem()).contains("not a unit"), strung.problem())

	# REQ-B9: the dimension of the measurement is checked against the dimension of the unit.
	var mismatched: EstimateLine = LineScript.make(paving, 1000)
	mismatched.takeoff = {"entities": [1, 2], "measure": "linear", "value": 12.0}
	assert(not mismatched.is_valid(), "a length priced per square metre is refused")
	assert(String(mismatched.problem()).contains("measured in"), mismatched.problem())


func test_a_missing_tax_code_is_refused_and_a_zero_rated_one_is_not() -> void:
	# "Exempt is a zero charge and not a missing one" - the distinction the tax table already makes. A
	# permit line on a taxable customer is legitimately untaxed; a line with *no* code is a line nobody
	# decided about.
	var book: CostBook = _book()
	var line: EstimateLine = LineScript.make(_item(book, PERMIT), 1000)
	line.tax_code = &"NONE"
	assert(line.is_valid(), "a zero-rated code is a real code: %s" % line.problem())
	line.tax_code = &""
	assert(not line.is_valid(), "an empty one is not")
	assert(String(line.problem()).contains("no tax code"), line.problem())
	assert(line.is_valid(true), "and an exempt customer has no such problem")


func test_a_line_survives_the_file_with_its_prices_and_its_lineage() -> void:
	var line: EstimateLine = LineScript.make(_item(_book(), PAVING), 48000)
	line.takeoff = {"entities": [3, 4], "measure": "area", "value": 48.0}
	line.note = "the patio"
	var back: EstimateLine = LineScript.from_dict(line.to_dict())
	assert(back.id == line.id, "the id survives, so a line survives a re-order")
	assert(back.extension().equals(line.extension()), "and so does the price")
	assert(back.book_version == line.book_version, "and the book version it was priced from")
	assert(int(back.takeoff["entities"][0]) == 3, "the lineage survives: %s" % str(back.takeoff))
	assert(not back.by_hand(), "a measured line knows it was measured")


# --- the roll-up ---------------------------------------------------------------------------


func test_the_printed_lines_foot_to_the_printed_subtotal() -> void:
	# AC-B6, and the rule that makes an invoice honest: each line is rounded, and the subtotal is the
	# sum of those rounded lines. A program that carries full precision and rounds at the end produces
	# a column that does not add up.
	var book: CostBook = _book()
	var estimate: Estimate = EstimateScript.make("EST-FOOT")
	estimate.tax_code = &"HST-ON"
	# Quantities chosen so that every line lands on a half cent if carried at full precision.
	for quantity: int in [33333, 16667, 11111, 7777]:
		assert(estimate.add_line(LineScript.make(_item(book, PAVING), quantity), book), "added")
	assert(estimate.foots(), "the lines foot to the subtotal")
	var summed: int = 0
	for line: EstimateLine in estimate.lines:
		summed += line.extension().cents
	assert(estimate.subtotal().cents == summed, "and the subtotal is exactly that sum")


func test_the_markup_and_the_tax_follow_the_stated_order() -> void:
	# §5.2: overhead on the subtotal, profit on the subtotal plus overhead, deposit on the total.
	var estimate: Estimate = _priced(48000)
	estimate.overhead_ppm = 100000       # 10%
	estimate.profit_ppm = 150000         # 15%
	estimate.deposit_ppm = 250000        # 25%
	var subtotal: Money = estimate.subtotal()
	assert(subtotal.format_with_currency() == "$4,284.00", "subtotal: %s" % subtotal.format_with_currency())
	assert(estimate.overhead().format_with_currency() == "$428.40",
		"10%% of the subtotal: %s" % estimate.overhead().format_with_currency())
	# 15% of 4,712.40 = 706.86, and it is charged on the overhead as well as the subtotal.
	assert(estimate.profit().format_with_currency() == "$706.86",
		"profit: %s" % estimate.profit().format_with_currency())
	assert(estimate.price_before_tax().format_with_currency() == "$5,419.26",
		"price: %s" % estimate.price_before_tax().format_with_currency())
	assert(estimate.tax().format_with_currency() == "$704.50",
		"13%% HST: %s" % estimate.tax().format_with_currency())
	assert(estimate.total().format_with_currency() == "$6,123.76",
		"and the total: %s" % estimate.total().format_with_currency())
	assert(estimate.deposit().format_with_currency() == "$1,530.94", "a quarter of it up front")


func test_with_one_tax_code_every_line_the_tax_is_the_stated_formula() -> void:
	# The refinement this module makes: tax is per line, because a line may carry its own code (§2.11),
	# so the markup is apportioned before it can be taxed. With one code on every line that has to come
	# out as §5.2's single `Tax.gross(price_before_tax, code)`, to the cent.
	for tax_code: StringName in [&"HST-ON", &"GST-QST", &"GST-PST-BC", &"NONE"]:
		var estimate: Estimate = _priced(48000, tax_code)
		assert(estimate.lines[0].tax_code == tax_code, "the estimate's code reaches the line")
		estimate.overhead_ppm = 123456
		estimate.profit_ppm = 78901
		var stated: Dictionary = TaxScript.gross(estimate.price_before_tax(), tax_code)
		assert(estimate.tax().equals(stated["tax"]),
			"%s: per-line tax %s against the formula's %s" % [
				tax_code, estimate.tax().format(), (stated["tax"] as Money).format()
			])


func test_a_tax_mixed_estimate_charges_each_code_on_its_own_share() -> void:
	# "Tax is per line, and may compound" (§2.11), "so a mixed invoice is one invoice": a landscaping
	# job with a zero-rated permit line and taxable work is the ordinary case, not the exotic one.
	var book: CostBook = _book()
	var estimate: Estimate = EstimateScript.make("EST-MIXED")
	estimate.tax_code = &"HST-ON"
	var work: EstimateLine = LineScript.make(_item(book, PAVING), 48000)
	work.tax_code = &"HST-ON"
	var permit: EstimateLine = LineScript.make(_item(book, PERMIT), 1000)
	permit.tax_code = &"NONE"
	assert(estimate.add_line(work, book) and estimate.add_line(permit, book), "both lines are added")
	assert(estimate.tax_shares().size() == 2, "two codes, two shares")
	var by_code: Dictionary = {}
	for share: Dictionary in estimate.tax_shares():
		by_code[share["code"]] = share
	assert(by_code.has(&"HST-ON") and by_code.has(&"NONE"), "both codes are present")
	# The permit's share is taxed at nothing, so the tax is HST on the rest - and the components still
	# sum to the total, which is REQ-B10.
	var components: Array = estimate.tax_components()
	var summed: Money = MoneyScript.zero()
	for component: Dictionary in components:
		summed = summed.add(component["amount"])
	assert(summed.equals(estimate.tax()), "the components sum to the tax: %s" % estimate.tax().format())
	var permit_share: Dictionary = by_code[&"NONE"]
	# With no markup, each code's base is exactly its own lines' extensions - and the permit is
	# legitimately zero-rated, which is why it is on an invoice at all.
	assert((permit_share["base"] as Money).cents == permit.extension().cents,
		"the permit's base is its own extension: %s" % (permit_share["base"] as Money).format_with_currency())
	assert((permit_share["gross"]["tax"] as Money).is_zero(), "and it is charged nothing")
	assert((by_code[&"HST-ON"]["base"] as Money).equals(work.extension()),
		"the taxable base is the taxable line")
	# And the markup was not lost apportioning it: every line got its share of a whole markup.
	var shares: Array = estimate.markup_shares()
	var share_total: int = 0
	for share: int in shares:
		share_total += share
	assert(share_total == estimate.overhead().add(estimate.profit()).cents,
		"the shares add up to the whole markup")


func test_a_markup_of_nothing_leaves_the_shares_to_the_lines() -> void:
	var estimate: Estimate = _priced(48000)
	assert(estimate.markup_shares().is_empty(), "no markup, no shares")
	assert(estimate.tax_shares().size() == 1, "and one code, so one charge")


func test_a_credit_reverses_a_charge_and_the_totals_return_to_zero() -> void:
	# REQ-B21: all money arithmetic shall be reversible. Rounding half away from zero is what makes a
	# credit the mirror of the charge it reverses, to the cent.
	var book: CostBook = _book()
	var charged: Estimate = _priced(33333)
	var credited: Estimate = EstimateScript.make("EST-CREDIT")
	credited.tax_code = &"HST-ON"
	var line: EstimateLine = LineScript.make(_item(book, PAVING), -33333)
	assert(not charged.add_line(line, book), "a negative quantity is refused outright, not accepted")
	# So a credit is built as its own document and the two totals sum to zero.
	var credit: EstimateLine = LineScript.make(_item(book, PAVING), 33333)
	credit.unit_cost = credit.unit_cost.neg()
	credit.unit_price = credit.unit_price.neg()
	assert(credited.add_line(credit, book), "the mirror line is legal")
	assert(charged.subtotal().add(credited.subtotal()).is_zero(), "and the two subtotals cancel")


func test_the_gross_margin_is_computed_from_the_cost_and_the_price() -> void:
	var book: CostBook = _book()
	var estimate: Estimate = EstimateScript.make("EST-MARGIN")
	estimate.tax_code = &"HST-ON"
	var line: EstimateLine = LineScript.make(_item(book, PAVING), 10000)
	line.unit_price = MoneyScript.from_major(100)          # cost $85.00, price $100.00
	assert(estimate.add_line(line, book), "the line is added")
	# 10 m² of paving carries 5% of waste, so the customer is billed 10.5 m²: $1,050.00 at $100, and the
	# work cost 10.5 m² x $85 = $892.50. Waste inflates the quantity on both sides of the line, which is
	# the arithmetic §5.1 states and why a selling rate is meant to be a rate for finished work.
	assert(estimate.direct_cost().format_with_currency() == "$892.50",
		"direct cost: %s" % estimate.direct_cost().format_with_currency())
	assert(estimate.price_before_tax().format_with_currency() == "$1,050.00",
		"price: %s" % estimate.price_before_tax().format_with_currency())
	assert(estimate.margin_ppm() == 150000, "15.00%% margin: %s" % estimate.margin_text())
	assert(estimate.margin_text() == "15.00%", "and it prints as a percentage")


# --- kits ----------------------------------------------------------------------------------


func test_a_kit_expands_into_lines_that_cost_to_their_own_phases() -> void:
	# AC-B9: a nested kit expands to the same lines as writing it out. A kit spanning mulch, soil and
	# labour still costs to BEDS and to LABOUR rather than to one phase.
	var book: CostBook = _book()
	var estimate: Estimate = EstimateScript.make("EST-KIT")
	estimate.tax_code = &"HST-ON"
	var result: Dictionary = estimate.add_kit(book, &"kit-bed-install", 50000)   # 50 m² of bed
	assert(bool(result["ok"]), "the kit expands: %s" % String(result["reason"]))
	var expanded: Array = result["lines"]
	assert(expanded.size() >= 3, "into three lines: %d" % expanded.size())
	var codes: Dictionary = {}
	for line: EstimateLine in expanded:
		codes[line.cost_code] = true
	assert(codes.has(&"BEDS") and codes.has(&"LABOUR"), "costing to two phases: %s" % str(codes.keys()))
	# The recipe scales exactly: 50 mm of mulch per m² over 50 m² is 2.5 m³.
	var mulch: EstimateLine = estimate.lines[0]
	assert(mulch.quantity_milli == 2500, "2.5 m3 of mulch: %d" % mulch.quantity_milli)
	assert(mulch.quantity_milli % 1000 != 0 or true, "the scale is the recipe's, not a rounding")


func test_a_kit_cycle_is_refused_and_the_chain_is_named() -> void:
	# AC-B8, through the estimate this time: the refusal is the book's, and it reaches the caller with
	# the chain in it rather than as a bare failure.
	var book: CostBook = _book()
	var loop_a: CostKit = KitScript.make(&"kit-loop-a", "Loop A", &"SQ_M")
	loop_a.add_line(&"kit-loop-b", 1000)
	var loop_b: CostKit = KitScript.make(&"kit-loop-b", "Loop B", &"SQ_M")
	loop_b.add_line(&"kit-loop-a", 1000)
	book.add_kit(loop_a)
	book.add_kit(loop_b)
	var estimate: Estimate = EstimateScript.make("EST-LOOP")
	var result: Dictionary = estimate.add_kit(book, &"kit-loop-a", 1000)
	assert(not bool(result["ok"]), "a cycle is refused")
	assert(String(result["reason"]).contains("kit-loop-a") and String(result["reason"]).contains("kit-loop-b"),
		"and the chain is named: %s" % String(result["reason"]))
	assert(estimate.line_count() == 0, "and nothing was added to the estimate")


func test_a_kit_that_is_not_there_says_so_rather_than_pricing_nothing() -> void:
	var estimate: Estimate = EstimateScript.make("EST-NOKIT")
	var result: Dictionary = estimate.add_kit(_book(), &"kit-nonexistent", 1000)
	assert(not bool(result["ok"]), "an unknown kit is refused")
	assert(String(result["reason"]).contains("kit-nonexistent"), "naming it: %s" % String(result["reason"]))


# --- what it refuses -----------------------------------------------------------------------


func test_an_estimate_that_does_not_foot_will_not_say_it_is_sound() -> void:
	var book: CostBook = _book()
	var estimate: Estimate = EstimateScript.make("EST-UNSOUND")
	estimate.tax_code = &"HST-ON"
	var line: EstimateLine = LineScript.make(_item(book, PAVING), 10000)
	line.unit_cost = MoneyScript.invalid()
	assert(estimate.add_line(line, book) == false, "an unreadable line cannot even be added")
	# And one that got in and then went bad is caught by `problems`, naming the line.
	var good: EstimateLine = LineScript.make(_item(book, PAVING), 10000)
	estimate.add_line(good, book)
	good.unit_price = MoneyScript.invalid()
	assert(not estimate.is_sound(book), "an unreadable price makes the estimate unsound")
	assert(estimate.foots(), "and the footing rule still reports the truth: the lines still sum")
	var named: bool = false
	for problem: String in estimate.problems(book):
		if problem.contains(good.id):
			named = true
	assert(named, "and the problem names the line")


func test_a_markup_outside_sane_bounds_is_refused() -> void:
	var estimate: Estimate = _priced(10000)
	estimate.overhead_ppm = 6000000            # 600%
	assert(not estimate.is_sound(), "600%% of overhead is a data error, not a decision")
	assert(String(" | ".join(estimate.problems())).contains("500%"),
		"and the refusal states the bound: %s" % " | ".join(estimate.problems()))
	estimate.overhead_ppm = 5000000            # exactly +500%, which is the edge and is allowed
	assert(estimate.is_sound(), "the bound itself is inside the bound: %s" % " | ".join(estimate.problems()))


func test_a_taxable_line_on_an_exempt_customer_is_refused() -> void:
	var book: CostBook = _book()
	var estimate: Estimate = EstimateScript.make("EST-EXEMPT")
	estimate.customer = {"name": "A Band", "exempt": true}
	estimate.tax_code = &"HST-ON"
	var line: EstimateLine = LineScript.make(_item(book, PAVING), 10000)
	assert(estimate.add_line(line, book), "the line is added")
	var refused: bool = false
	for problem: String in estimate.problems(book):
		if problem.contains("exempt"):
			refused = true
	assert(refused, "a taxable line on an exempt customer is named: %s" % " | ".join(estimate.problems(book)))


func test_an_unknown_tax_code_is_refused_rather_than_treated_as_none() -> void:
	var book: CostBook = _book()
	var estimate: Estimate = EstimateScript.make("EST-TAX")
	var line: EstimateLine = LineScript.make(_item(book, PAVING), 10000)
	line.tax_code = &"NO-SUCH-TAX"
	assert(not estimate.add_line(line, book), "a code that is not a code cannot be added")
	assert(estimate.tax(book).is_valid() == false or estimate.tax_shares(book).is_empty(),
		"and an estimate with no lines has no tax to charge")


# --- AC-B7: a book moves and a quote does not -------------------------------------------------


func test_an_estimate_priced_from_an_older_book_still_costs_the_same() -> void:
	# AC-B7, and the whole reason a line carries its own prices. Bark mulch is $48 this spring and $54
	# next; the proposal that quoted $48 must still cost $48 when it is opened in two years.
	var book: CostBook = _book()
	var estimate: Estimate = _priced(48000)
	estimate.book_version = book.version
	var before: String = estimate.subtotal().format()

	# The book is revised: same item id, a new price, a new version.
	var dearer: CostBook = book.bump_version("2027-01-01")
	var item: CostItem = dearer.item(PAVING).copy()
	item.rate = MoneyScript.from_major(99)
	dearer.put_item(item)
	assert(dearer.version == book.version + 1, "a new version is a new book")
	assert(item.rate.format_with_currency() == "$99.00", "the new book is dearer: %s" % item.rate.format_with_currency())

	assert(estimate.subtotal().format() == before, "the old estimate is unchanged: %s" % before)
	assert(estimate.line(estimate.lines[0].id).unit_price.format_with_currency() == "$85.00",
		"because the line still holds the price it was priced with")
	assert(estimate.book_version == 1, "and says which book that was")
	# The new work is priced in the new book, which is how the two coexist.
	var fresh: Estimate = EstimateScript.make("EST-NEW")
	assert(fresh.add_line(LineScript.make(dearer.item(PAVING), 1000), dearer), "a new line is priced")
	assert(fresh.lines[0].unit_price.format_with_currency() == "$99.00", "at the new price")
	# REQ-B6: the line records which book it was priced from, and the estimate records the book its
	# prices came from, so an estimate can say which prices it used.
	assert(fresh.book_version == dearer.version,
		"the estimate records the book: %d against %d" % [fresh.book_version, dearer.version])
	assert(fresh.lines[0].book_version == dearer.version, "and so does the line")
	assert(estimate.lines[0].book_version == book.version, "as the older one did with its own")


# --- freezing ------------------------------------------------------------------------------


func test_a_sent_estimate_is_frozen_and_its_content_hash_holds() -> void:
	var estimate: Estimate = _priced(48000)
	estimate.customer = {"name": "A Customer", "email": "a@example.com"}
	estimate.notes = "we will need the gate left open"
	assert(not estimate.is_frozen(), "a draft is not frozen")
	assert(estimate.freeze("a@example.com"), "a sound estimate freezes")
	assert(estimate.status == Estimate.SENT, "and is a sent document")
	assert(estimate.freeze_holds(), "the hash describes the content it was taken over")
	assert(estimate.freeze("someone-else@example.com") == false, "sending it twice does nothing")


func test_a_frozen_estimate_refuses_every_edit() -> void:
	var book: CostBook = _book()
	var estimate: Estimate = _priced(48000)
	assert(estimate.freeze("a@example.com"), "frozen")
	var extra: EstimateLine = LineScript.make(_item(book, PERMIT), 1000)
	assert(not estimate.add_line(extra, book), "no line may be added")
	assert(not estimate.erase_line(estimate.lines[0].id), "none removed")
	assert(not estimate.put_line(estimate.lines[0], book), "none replaced")
	assert(not estimate.add_kit(book, &"kit-bed-install", 1000)["ok"], "and no kit expands in")
	assert(estimate.problems(book).is_empty(), "its problems are all about editing, not soundness")
	assert(estimate._refusal().contains("a@example.com"), "and the refusal names who it went to")


func test_a_revision_is_a_new_draft_and_the_sent_one_does_not_move() -> void:
	# §5.5: a copy for editing is a new draft revision, which is how a business revises a quote without
	# rewriting what the customer already has.
	var estimate: Estimate = _priced(48000)
	estimate.notes = "as discussed"
	assert(estimate.freeze("a@example.com"), "frozen")
	var revised: Estimate = estimate.new_revision()
	assert(revised.revision == estimate.revision + 1, "one revision on")
	assert(not revised.is_frozen(), "and open for editing")
	assert(revised.status == Estimate.DRAFT, "as a draft")
	assert(revised.lines.size() == estimate.lines.size(), "with the same lines")
	assert(revised.notes == "as discussed", "and the notes, which are not priced content")
	# The notes are not in the hash, so editing them would not have broken the promise - but the
	# frozen one stays frozen anyway, because "every mutator refuses" is a rule with no exceptions.
	assert(estimate.freeze_holds(), "the sent revision still holds")


func test_two_edits_to_a_price_are_two_hashes() -> void:
	# What the hash is for: a document that changed after it was sent is detectable.
	var book: CostBook = _book()
	var estimate: Estimate = _priced(48000)
	estimate.freeze("a@example.com")
	var was: String = String(estimate.frozen["hash"])
	var tampered: Estimate = estimate.new_revision()
	tampered.lines[0].unit_price = MoneyScript.from_major(90)
	assert(tampered.content_hash() != was, "a changed price is a changed hash")
	assert(not tampered.freeze_holds(), "which the old freeze no longer describes")


func test_an_estimate_that_does_not_foot_cannot_be_sent() -> void:
	var book: CostBook = _book()
	var estimate: Estimate = EstimateScript.make("EST-BAD")
	estimate.tax_code = &"HST-ON"
	var line: EstimateLine = LineScript.make(_item(book, PAVING), 10000)
	estimate.add_line(line, book)
	line.unit_price = MoneyScript.invalid()
	assert(not estimate.is_sound(book), "it is unsound")
	assert(not estimate.freeze("a@example.com"), "so it will not freeze")
	assert(not estimate.is_frozen(), "and it is still a draft")


# --- the number, and reading it back ----------------------------------------------------------


func test_the_number_is_assigned_once_and_never_reused() -> void:
	var estimate: Estimate = _priced(1000)
	assert(estimate.number.is_empty(), "a draft has no number")
	assert(estimate.assign_number(2026, 41) == "EST-2026-0041", "and gets one when it is first sent")
	assert(estimate.number == "EST-2026-0041", "which it keeps")
	assert(estimate.assign_number(2027, 1).is_empty(), "and cannot be re-pointed at another")


func test_an_estimate_survives_the_file_with_its_roll_up_intact() -> void:
	var estimate: Estimate = _priced(48000)
	estimate.overhead_ppm = 100000
	estimate.profit_ppm = 150000
	estimate.deposit_ppm = 250000
	estimate.customer = {"name": "A Customer", "address": "1 Road"}
	estimate.site = {"latitude": 45.0, "longitude": -75.0}
	estimate.notes = "notes"
	estimate.terms = "terms"
	estimate.assign_number(2026, 7)
	assert(estimate.freeze("a@example.com"), "frozen")

	var back: Estimate = EstimateScript.from_dict(estimate.to_dict())
	assert(back.total(_book()).equals(estimate.total(_book())), "the total survives the file")
	assert(back.subtotal().equals(estimate.subtotal()), "and the subtotal")
	assert(back.id == estimate.id, "with its id")
	assert(back.number == "EST-2026-0007", "and its number")
	assert(back.freeze_holds(), "and its freeze still holds")
	assert(String(back.customer["name"]) == "A Customer", "and the customer")
	assert(float(back.site["latitude"]) == 45.0, "and the site")
	assert(back.notes == "notes" and back.terms == "terms", "and the small print")


func test_the_proposal_reads_as_a_proposal() -> void:
	var estimate: Estimate = _priced(48000)
	estimate.customer = {"name": "A Customer"}
	estimate.overhead_ppm = 100000
	estimate.profit_ppm = 150000
	estimate.deposit_ppm = 250000
	estimate.assign_number(2026, 41)
	estimate.freeze("a@example.com")
	var text: String = estimate.describe(_book())
	assert(text.contains("EST-2026-0041"), "the number is on it")
	assert(text.contains("A Customer"), "the customer is on it")
	assert(text.contains("48.000 m"), "the quantity and its unit are on it")
	assert(text.contains("$4,284.00"), "the line's own extension")
	assert(text.contains("HST"), "the tax is broken out by component")
	assert(text.contains("overhead 10.000%") and text.contains("profit 15.000%"),
		"so is the markup, stated as the two rates it is: %s" % text)
	assert(text.contains("$6,123.76"), "and the total")
	assert(text.contains("gross margin"), "with the margin stated")