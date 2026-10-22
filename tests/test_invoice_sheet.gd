extends Node
## The invoice page: what a customer actually receives (spec §9.5).
##
## Two things are under test. The page is drawn on the **same writer that plots a landscape sheet**,
## at true paper millimetres - so the two documents come out of one program that measures paper the
## same way - and every figure on it is the invoice's **own** figure: the printed column foots to the
## printed subtotal because nothing here computes money, it only places it.
##
## The layout is asked for as data (`plan_page`) so a test can check where things are without
## unpacking a PDF, and the file itself is checked for the words a customer reads.

const PageScript := preload("res://scripts/invoice_sheet.gd")
const InvoiceScript := preload("res://scripts/biz/invoice.gd")
const PaymentScript := preload("res://scripts/biz/payment.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")
const UnderlayScript := preload("res://scripts/draft/raster_underlay.gd")

## Everything a logo test writes goes under this name, and every logo test sweeps it away first and
## last, so a test that throws half-way leaves nothing for the next person to find and a leftover
## from an earlier run cannot be the reason a later one passes.
const LOGO_PREFIX := "test-invoice-logo-"

const POINTS_PER_MM := 72.0 / 25.4
const ROW_STEP_MM := 6.0


## A real invoice: two lines, one of them taxed at 13%, 100.00 withheld, issued on 30 days' terms.
func _invoice() -> InvoiceScript:
	var invoice: InvoiceScript = InvoiceScript.new("INV1")
	invoice.job = "J1"
	invoice.customer = {"name": "Smith", "city": "Ottawa"}
	invoice.site = {"name": "Smith, back garden"}
	assert(invoice.add_amount(InvoiceScript.MILESTONE_LINE, "Deposit", MoneyScript.of(100000), &"HARDSCAPE", &"HST-ON"))
	assert(invoice.add_amount(InvoiceScript.PERIOD_LINE, "Bark mulch", MoneyScript.of(50000), &"PLANTING", &"NONE"))
	assert(invoice.set_retainage(MoneyScript.of(10000)))
	assert(bool(invoice.issue("2026-06-01", 30, "INV-2026-0001")["ok"]))
	return invoice


func _draft() -> InvoiceScript:
	var invoice: InvoiceScript = InvoiceScript.new("INV2")
	invoice.job = "J1"
	invoice.add_amount(InvoiceScript.MILESTONE_LINE, "Deposit", MoneyScript.of(100000), &"HARDSCAPE", &"NONE")
	return invoice


## The same invoice with something already paid, which is the busiest the totals block ever gets.
func _paid() -> InvoiceScript:
	var invoice := _invoice()
	var payment: PaymentScript = PaymentScript.new("PAY1")
	payment.invoice = "INV1"
	payment.received_at = "2026-06-10"
	payment.amount = MoneyScript.of(50000)
	payment.method = &"cheque"
	assert(bool(invoice.apply_payment(payment)["ok"]))
	return invoice


## Every horizontal rule on the page, with the span it covers, in points.
func _rules(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var from := Vector2.ZERO
	for line in text.split("\n"):
		var drawn := line.strip_edges()
		if drawn.ends_with(" m"):
			var parts := drawn.split(" ")
			if parts.size() == 3:
				from = Vector2(float(parts[0]), float(parts[1]))
		elif drawn.ends_with(" l"):
			var legs := drawn.split(" ")
			if legs.size() == 3:
				var to := Vector2(float(legs[0]), float(legs[1]))
				if is_equal_approx(from.y, to.y):
					out.append({"x0": minf(from.x, to.x), "x1": maxf(from.x, to.x), "y": from.y})
	return out


## Every run of text the page drew, with where it was drawn and how big. A test that only asks whether
## a word is somewhere in the file cannot tell a page that reads from one with its words in the wrong
## place.
func _drawn_text(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for line in text.split("\n"):
		var drawn := line.strip_edges()
		if not drawn.begins_with("BT /F1 ") or not drawn.ends_with(") Tj ET"):
			continue
		var open_paren := drawn.find("(")
		if open_paren < 0:
			continue
		var head := drawn.substr(0, open_paren).strip_edges().split(" ", false)
		if head.size() != 7:
			continue
		out.append({
			"text": drawn.substr(open_paren + 1, drawn.length() - 7 - open_paren - 1),
			"at": Vector2(float(head[4]), float(head[5])),
			"size": float(head[2]),
		})
	return out


func _y_of(rows: Array[Dictionary], wanted: String) -> float:
	for row in rows:
		if String(row["text"]) == wanted:
			return (row["at"] as Vector2).y
	return NAN


func _drawn_rows(invoice: InvoiceScript, options: Dictionary = {}) -> Array[Dictionary]:
	return _drawn_text(PageScript.export_pdf(invoice, options).get_string_from_utf8())


## A logo file, which is a picture with a transparent background when `transparent` is set - the way
## a real logo file arrives, and the case a naive RGB conversion gets wrong.
func _logo(name: String, width: int, height: int, transparent: bool = false) -> String:
	UnderlayScript.ensure_dir()
	var path: String = UnderlayScript.DIR.path_join(LOGO_PREFIX + name + ".png")
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.4, 0.6, 0.0 if transparent else 1.0))
	if transparent:
		image.set_pixel(0, 0, Color(0.0, 1.0, 0.0, 1.0))
	image.save_png(path)
	return path


func _forget_logos() -> void:
	for path: String in UnderlayScript.list():
		if path.get_file().begins_with(LOGO_PREFIX):
			DirAccess.remove_absolute(path)


## Every place the page placed an image, as `{name, rect}` in points, read out of the content stream.
## `place_image` writes `q w 0 0 h x y cm /ImN Do Q`.
func _placed_images(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for line in text.split("\n"):
		var drawn := line.strip_edges()
		if not drawn.contains(" cm ") or not drawn.contains(" Do "):
			continue
		var head := drawn.split(" ", false)
		if head.size() != 11:
			continue
		out.append({
			"name": String(head[8]),
			"rect": Rect2(float(head[5]), float(head[6]), float(head[1]), float(head[4])),
		})
	return out


# --- the paper ---------------------------------------------------------------------------------


func test_a_page_is_a_real_piece_of_paper_a_business_names() -> void:
	assert(PageScript.page_size_mm("LETTER", true).is_equal_approx(Vector2(216.0, 279.0)))
	assert(PageScript.page_size_mm("A4", true).is_equal_approx(Vector2(210.0, 297.0)))
	var names: Array[String] = PageScript.sheet_names()
	var expected: Array[String] = ["A4", "LETTER"]
	assert(names == expected)


func test_a_paper_nobody_has_prints_on_the_default_rather_than_failing() -> void:
	assert(PageScript.plotter_sheet("letter") == "ANSI A (8.5x11 in)")
	assert(PageScript.plotter_sheet("nonsense") == "ANSI A (8.5x11 in)")
	assert(PageScript.plotter_sheet("a4") == "A4")


func test_the_file_is_a_pdf_a_customer_can_open() -> void:
	var text := PageScript.export_pdf(_invoice()).get_string_from_utf8()
	assert(text.begins_with("%PDF-1.4"))
	assert(text.contains("/MediaBox [0 0 "))
	assert(text.strip_edges().ends_with("%%EOF"))
	assert(text.contains("INV-2026-0001"))


# --- what the page says ------------------------------------------------------------------------


func test_the_page_names_the_invoice_and_the_dates_and_the_terms() -> void:
	var text := PageScript.export_pdf(_invoice()).get_string_from_utf8()
	assert(text.contains("INV-2026-0001"))
	assert(text.contains("issued 2026-06-01"))
	assert(text.contains("due 2026-07-01"))
	assert(text.contains("terms 30 days"))
	assert(text.contains("page 1 of 1"))


func test_a_draft_says_it_is_a_draft_rather_than_showing_a_number_it_has_not_been_given() -> void:
	var plan: Dictionary = PageScript.plan_page(_draft())
	var header: Dictionary = plan["header"]
	assert(bool(header["draft"]))
	assert(String(header["number_text"]) == "DRAFT - NOT YET ISSUED")
	assert(String(plan["footer"]["text"]) == "not yet issued")
	var text := PageScript.export_pdf(_draft()).get_string_from_utf8()
	assert(text.contains("DRAFT - NOT YET ISSUED"))


func test_the_site_address_is_the_place_the_drawing_already_knows() -> void:
	var plan: Dictionary = PageScript.plan_page(_invoice())
	var job: Array = plan["header"]["job"]
	assert(job.size() == 2)
	assert(String(job[0]) == "job J1")
	assert(String(job[1]) == "Smith, back garden")
	var billed: Array = plan["header"]["billed_to"]
	assert(String(billed[0]) == "Smith")
	assert(String(billed[1]) == "Ottawa")


func test_the_company_address_reaches_the_top_of_the_page() -> void:
	var options := {"company": ["Green Thumb Landscaping", "12 Elm St", "Ottawa ON"]}
	var plan: Dictionary = PageScript.plan_page(_invoice(), options)
	assert(String(plan["header"]["name"]) == "Green Thumb Landscaping")
	var address: Array = plan["header"]["address"]
	assert(address.size() == 2, str(address))
	assert(String(address[0]) == "12 Elm St")
	assert(String(address[1]) == "Ottawa ON")
	var rows: Array[Dictionary] = _drawn_rows(_invoice(), options)
	var name_y := _y_of(rows, "Green Thumb Landscaping")
	var street_y := _y_of(rows, "12 Elm St")
	var town_y := _y_of(rows, "Ottawa ON")
	assert(not is_nan(name_y) and not is_nan(street_y) and not is_nan(town_y))
	assert(name_y > street_y and street_y > town_y, "the company name is above its address")


func test_a_void_invoice_says_so_on_the_page() -> void:
	var invoice := _invoice()
	assert(invoice.mark_void("2026-06-05", "the customer was changed", "INV-2026-0002"))
	var plan: Dictionary = PageScript.plan_page(invoice)
	var note: String = String(plan["footer"]["note"])
	assert(note.contains("voided on 2026-06-05"), note)
	assert(note.contains("reissued as INV-2026-0002"), note)
	assert(PageScript.export_pdf(invoice).get_string_from_utf8().contains("voided on 2026-06-05"))


# --- the lines ---------------------------------------------------------------------------------


func test_the_lines_are_the_invoices_own_and_the_column_foots_to_the_subtotal() -> void:
	var invoice := _invoice()
	var plan: Dictionary = PageScript.plan_page(invoice)
	var rows: Array = plan["rows"]
	assert(rows.size() == 2)
	assert(String(rows[0]["description"]) == "Deposit")
	assert(String(rows[0]["amount_text"]) == "1,000.00")
	assert(String(rows[1]["amount_text"]) == "500.00")
	var column: Array = []
	for row in rows:
		column.append(row["amount"])
	assert(MoneyScript.sum(column, &"CAD").cents == invoice.subtotal().cents)
	assert(invoice.subtotal().cents == 150000)


func test_a_row_reads_as_a_row_a_bookkeeper_can_check() -> void:
	var invoice := _invoice()
	var rows: Array[Dictionary] = PageScript.line_rows(invoice)
	assert(PageScript.row_text(rows[0]) == "Deposit, 1 EACH at 1,000.00, 1,000.00",
		PageScript.row_text(rows[0]))
	assert(String(rows[0]["quantity_text"]) == "1 EACH")


func test_a_quantity_that_is_not_whole_is_written_as_a_decimal() -> void:
	var invoice: InvoiceScript = InvoiceScript.new("INV3")
	invoice.job = "J1"
	assert(invoice.add_line(InvoiceScript.PERIOD_LINE, "Sod", 3500, &"SQ_FT", MoneyScript.of(250), &"PLANTING", &"NONE"))
	var rows: Array[Dictionary] = PageScript.line_rows(invoice)
	assert(String(rows[0]["quantity_text"]) == "3.5 SQ_FT", String(rows[0]["quantity_text"]))


# --- nothing drawn through anything else --------------------------------------------------------


## A rule through a line of type is a fault, and it is one only a *render* shows, so it is written
## down as a test: every rule is clear of every line of text it passes under. This test failed when
## it was written - the table rule cut through the column headings and the totals rule through the
## heading of the totals block - which is exactly why it exists.
func test_no_rule_is_drawn_through_a_line_of_text() -> void:
	var text := PageScript.export_pdf(_paid()).get_string_from_utf8()
	var rules: Array[Dictionary] = _rules(text)
	assert(rules.size() >= 4, "the page has its rules: %d" % rules.size())
	var rows: Array[Dictionary] = _drawn_text(text)
	for rule in rules:
		for row in rows:
			var at: Vector2 = row["at"]
			var size: float = float(row["size"])
			var text_left: float = at.x
			var text_right: float = text_left + float(String(row["text"]).length()) * size * 0.5
			if text_right < float(rule["x0"]) or text_left > float(rule["x1"]):
				continue
			var crossed: bool = float(rule["y"]) > at.y - 1.0 and float(rule["y"]) < at.y + size + 1.0
			assert(not crossed, "a rule at y %.1f crosses '%s' (baseline %.1f, size %.1f)" % [
				rule["y"], String(row["text"]), at.y, size])


func test_each_row_has_its_own_band_and_the_next_row_sits_below_it() -> void:
	var rows: Array[Dictionary] = _drawn_rows(_invoice())
	var first_y := _y_of(rows, "1,000.00")
	var second_y := _y_of(rows, "500.00")
	assert(not is_nan(first_y) and not is_nan(second_y))
	assert(is_equal_approx(first_y - second_y, ROW_STEP_MM * POINTS_PER_MM),
		"rows are one row step apart: %f against %f" % [first_y - second_y, ROW_STEP_MM * POINTS_PER_MM])


func test_a_line_too_long_for_its_column_is_shortened_rather_than_run_on() -> void:
	var invoice: InvoiceScript = InvoiceScript.new("INV4")
	invoice.job = "J1"
	var long_name := "Deposit for the complete renovation of the front garden including the path, the bed edging and every plant in it"
	assert(invoice.add_amount(InvoiceScript.MILESTONE_LINE, long_name, MoneyScript.of(100000), &"HARDSCAPE", &"NONE"))
	assert(PageScript.export_pdf(invoice).get_string_from_utf8().contains("Deposit for the complete"))
	var rows: Array[Dictionary] = _drawn_rows(invoice)
	var clipped := ""
	for row in rows:
		var drawn: String = String(row["text"])
		if drawn.begins_with("Deposit for the"):
			clipped = drawn
	assert(clipped.ends_with("..."), clipped)
	assert(clipped.length() < long_name.length())


func test_more_lines_than_fit_are_counted_rather_than_run_off_the_page() -> void:
	var invoice: InvoiceScript = InvoiceScript.new("INV5")
	invoice.job = "J1"
	for index in 60:
		assert(invoice.add_amount(InvoiceScript.MILESTONE_LINE, "Line %d" % index,
			MoneyScript.of(100 + index), &"PLANTING", &"NONE"))
	var plan: Dictionary = PageScript.plan_page(invoice)
	var rows: Array = plan["rows"]
	assert(rows.size() < 60)
	var dropped := int(plan["dropped"])
	assert(dropped == 60 - rows.size())
	var note: String = String(plan["footer"]["note"])
	assert(note.contains("further line(s) do not fit on this page"), note)
	assert(PageScript.export_pdf(invoice).get_string_from_utf8().contains("do not fit on this page"))


# --- the totals --------------------------------------------------------------------------------


func test_the_totals_block_is_the_invoices_own_figures() -> void:
	var invoice := _invoice()
	var rows: Array[Dictionary] = PageScript.totals_rows(invoice)
	var captions: Array[String] = []
	for row in rows:
		captions.append(String(row["caption"]))
	assert(captions.has("Subtotal"), str(captions))
	assert(captions.has("Total"), str(captions))
	assert(captions.has("Balance due"), str(captions))
	assert(String(rows[0]["value_text"]) == "1,500.00")
	for row in rows:
		if String(row["caption"]) == "Total":
			assert(String(row["value_text"]) == "1,530.00")
			assert(bool(row["emphasis"]))
		if String(row["caption"]) == "Balance due":
			assert(String(row["value_text"]) == "1,530.00")


func test_the_tax_row_names_the_code_and_the_share_it_was_charged_on() -> void:
	var invoice := _invoice()
	var rows: Array[Dictionary] = PageScript.totals_rows(invoice)
	var tax_caption := ""
	for row in rows:
		if String(row["caption"]).begins_with("HST"):
			tax_caption = String(row["caption"])
	assert(tax_caption == "HST 13% on 1,000.00", tax_caption)


func test_a_zero_rated_code_is_not_a_row_but_an_exempt_customer_is() -> void:
	var invoice := _invoice()
	var plain: Array[Dictionary] = PageScript.totals_rows(invoice)
	for row in plain:
		assert(not String(row["caption"]).begins_with("No tax"), str(plain))
	var exempt: InvoiceScript = InvoiceScript.new("INV6")
	exempt.job = "J1"
	assert(exempt.add_amount(InvoiceScript.MILESTONE_LINE, "Deposit", MoneyScript.of(100000), &"HARDSCAPE", &"EXEMPT"))
	var rows: Array[Dictionary] = PageScript.totals_rows(exempt)
	var found := false
	for row in rows:
		if String(row["caption"]).begins_with("Exempt"):
			found = true
	assert(found, "an exempt customer's bookkeeper looks for the line: %s" % str(rows))


func test_a_tax_code_the_table_does_not_have_is_named_rather_than_charged_at_nothing() -> void:
	var invoice: InvoiceScript = InvoiceScript.new("INV7")
	invoice.job = "J1"
	assert(invoice.add_amount(InvoiceScript.MILESTONE_LINE, "Deposit", MoneyScript.of(100000), &"HARDSCAPE", &"VAT-99"))
	var rows: Array[Dictionary] = PageScript.totals_rows(invoice)
	var named := false
	for row in rows:
		var caption: String = String(row["caption"])
		if caption.contains("VAT-99") and caption.contains("unknown tax code"):
			named = true
			assert(String(row["value_text"]) == "—", String(row["value_text"]))
	assert(named, str(rows))
	assert(PageScript.tax_text(invoice).contains("unknown tax code"), PageScript.tax_text(invoice))


func test_a_retainage_is_a_deduction_with_its_own_line_and_a_retainage_of_nothing_is_not() -> void:
	var invoice := _invoice()
	var rows: Array[Dictionary] = PageScript.totals_rows(invoice)
	var found := false
	for row in rows:
		if String(row["caption"]) == "Less retainage withheld":
			found = true
			assert(String(row["value_text"]) == "-100.00", String(row["value_text"]))
			assert(bool(row["deduction"]))
	assert(found, str(rows))
	var clean := _draft()
	for row in PageScript.totals_rows(clean):
		assert(String(row["caption"]) != "Less retainage withheld")


func test_what_has_been_paid_is_on_the_page_with_what_arrived_how_and_when() -> void:
	var invoice := _invoice()
	var payment: PaymentScript = PaymentScript.new("PAY1")
	payment.invoice = "INV1"
	payment.received_at = "2026-06-10"
	payment.amount = MoneyScript.of(50000)
	payment.method = &"cheque"
	assert(bool(invoice.apply_payment(payment)["ok"]))
	var rows: Array[String] = PageScript.payment_rows(invoice)
	var expected: Array[String] = ["$500.00 by cheque, on 2026-06-10"]
	assert(rows == expected, str(rows))
	var text := PageScript.export_pdf(invoice).get_string_from_utf8()
	assert(text.contains("$500.00 by cheque, on 2026-06-10"))
	var totals: Array[Dictionary] = PageScript.totals_rows(invoice)
	var paid_found := false
	for row in totals:
		if String(row["caption"]) == "Payments received":
			paid_found = true
			assert(String(row["value_text"]) == "-500.00", String(row["value_text"]))
		if String(row["caption"]) == "Balance due":
			assert(String(row["value_text"]) == "1,030.00", String(row["value_text"]))
	assert(paid_found, str(totals))


# --- text that has to survive the file ----------------------------------------------------------


func test_a_name_with_brackets_survives_the_page() -> void:
	var invoice: InvoiceScript = InvoiceScript.new("INV8")
	invoice.job = "J1"
	assert(invoice.add_amount(InvoiceScript.MILESTONE_LINE, "Mulch (2 yd)", MoneyScript.of(10000), &"PLANTING", &"NONE"))
	var text := PageScript.export_pdf(invoice).get_string_from_utf8()
	assert(text.contains("Mulch \\(2 yd\\)"), "brackets are escaped in a PDF string")


# --- the company logo ---------------------------------------------------------------------------


func test_a_page_with_no_logo_is_the_page_it_has_always_been() -> void:
	var plan: Dictionary = PageScript.plan_page(_invoice())
	var header: Dictionary = plan["header"]
	assert((header["logo"] as Dictionary).is_empty(), "no logo, no placement")
	assert(is_equal_approx(float(header["name_x_mm"]), PageScript.MARGIN_MM),
		"the letterhead stays on the margin")
	assert(_placed_images(PageScript.export_pdf(_invoice()).get_string_from_utf8()).is_empty(),
		"and nothing is placed on the page")


func test_the_logo_keeps_its_proportion_and_the_name_moves_over_to_clear_it() -> void:
	_forget_logos()
	var plan: Dictionary = PageScript.plan_page(_invoice(), {"logo": _logo("proportioned", 64, 32)})
	var logo: Dictionary = plan["header"]["logo"]
	assert(not logo.is_empty(), "the picture is placed")
	var rect: Rect2 = logo["rect_mm"]
	assert(is_equal_approx(rect.size.x, 32.0), "twice as wide as it is tall: %s" % str(rect.size.x))
	assert(is_equal_approx(rect.size.y, PageScript.LOGO_HEIGHT_MM), str(rect.size.y))
	assert(is_equal_approx(rect.position.x, PageScript.MARGIN_MM), str(rect.position.x))
	assert(is_equal_approx(rect.position.y, PageScript.LOGO_TOP_MM), str(rect.position.y))
	assert(is_equal_approx(float(plan["header"]["name_x_mm"]),
		PageScript.MARGIN_MM + 32.0 + PageScript.LOGO_GAP_MM),
		"the name clears the picture by the gap")
	_forget_logos()


func test_a_very_wide_logo_is_capped_and_comes_down_in_height() -> void:
	_forget_logos()
	var path := _logo("banner", 1000, 40)
	var printable: float = PageScript.page_size_mm("LETTER", true).x - 2.0 * PageScript.MARGIN_MM
	var rect: Rect2 = PageScript.plan_page(_invoice(), {"logo": path})["header"]["logo"]["rect_mm"]
	assert(is_equal_approx(rect.size.x, printable * PageScript.LOGO_MAX_WIDTH_FRACTION),
		"the width is capped: %s" % str(rect.size.x))
	assert(rect.size.y < PageScript.LOGO_HEIGHT_MM, "so the height comes down with it: %s" % str(rect.size.y))
	assert(is_equal_approx(rect.size.x / rect.size.y, 1000.0 / 40.0),
		"and the picture keeps its own shape: %s" % str(rect.size.x / rect.size.y))
	_forget_logos()


func test_a_file_that_is_not_a_picture_is_a_page_with_no_logo() -> void:
	var plan: Dictionary = PageScript.plan_page(_invoice(), {"logo": "user://there-is-no-such-logo.png"})
	assert((plan["header"]["logo"] as Dictionary).is_empty(), "a file that is not there is no logo")
	assert(is_equal_approx(float(plan["header"]["name_x_mm"]), PageScript.MARGIN_MM),
		"and the letterhead does not move for it")


func test_a_file_that_is_not_a_picture_is_not_an_image() -> void:
	UnderlayScript.ensure_dir()
	var path: String = UnderlayScript.DIR.path_join(LOGO_PREFIX + "notes.png")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("an address book")
	file.close()
	assert(PageScript.logo_image(path) == null, "a text file named .png is not a logo")
	assert(PageScript.logo_image("user://no-such-file.png") == null, "and neither is nothing at all")
	DirAccess.remove_absolute(path)


func test_the_logo_lands_on_the_page_above_the_letterhead_rule() -> void:
	_forget_logos()
	var text := PageScript.export_pdf(_invoice(), {"logo": _logo("landing", 64, 32)}).get_string_from_utf8()
	assert(text.contains("/Subtype /Image"), "the picture is a real image object")
	assert(text.contains("/XObject << /Im1 "), "and the page's resources name it")
	var placed: Array[Dictionary] = _placed_images(text)
	assert(placed.size() == 1, "one picture, placed once: %s" % str(placed))
	assert(String(placed[0]["name"]) == "/Im1", String(placed[0]["name"]))
	var rect: Rect2 = placed[0]["rect"]
	var page_mm: Vector2 = PageScript.page_size_mm("LETTER", true)
	# The layout measures down from the paper's top and the writer draws up from the foot, so the
	# logo's foot is the page height less its own top and height. Passing the from-the-top number
	# straight through is what put every rule on this page at its mirror height.
	var expected_y: float = (page_mm.y - (PageScript.LOGO_TOP_MM + PageScript.LOGO_HEIGHT_MM)) * POINTS_PER_MM
	assert(is_equal_approx(rect.position.x, PageScript.MARGIN_MM * POINTS_PER_MM), str(rect.position.x))
	assert(is_equal_approx(rect.position.y, expected_y), "%s vs %s" % [str(rect.position.y), str(expected_y)])
	assert(is_equal_approx(rect.size.x, 32.0 * POINTS_PER_MM), str(rect.size.x))
	var rule_y: float = (page_mm.y - PageScript.HEAD_RULE_MM) * POINTS_PER_MM
	assert(rect.position.y > rule_y, "the picture sits above the rule under the letterhead")
	assert(rect.position.y + rect.size.y < page_mm.y * POINTS_PER_MM, "and inside the paper")
	_forget_logos()


func test_a_transparent_logo_is_flattened_onto_the_paper() -> void:
	_forget_logos()
	var image: Image = PageScript.logo_image(_logo("transparent", 8, 8, true))
	assert(image != null, "a transparent PNG is still a logo")
	assert(image.get_format() == Image.FORMAT_RGB8, "the writer's image object is raw RGB8")
	# The background was fully transparent, so on paper it is paper - rather than whatever colour sits
	# under the alpha, which for a black-backed PNG is a black box round the letterhead.
	var paper: Color = image.get_pixel(4, 4)
	assert(paper.r > 0.99 and paper.g > 0.99 and paper.b > 0.99, "the background is paper: %s" % str(paper))
	var ink: Color = image.get_pixel(0, 0)
	assert(ink.g > 0.99 and ink.r < 0.01 and ink.b < 0.01, "the opaque pixel is untouched: %s" % str(ink))
	_forget_logos()