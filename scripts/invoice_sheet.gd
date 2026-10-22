class_name InvoiceSheet
extends RefCounted
## The invoice page: a plain grid of lines, a totals block, and terms (spec §9.5).
##
## An invoice page is a **simpler** page than a landscape plan and it is drawn on the same paper with
## the same writer, at true millimetres: `pdf_writer.gd`, the one that plots sheets. Both the page and
## `Invoice.to_dict()` come out of the same `Invoice`, which is the point - PDF is for the customer
## and the file, JSON is what a ledger adapter posts, and neither can drift from the other because
## neither is a second source of truth.
##
## Three rules are the shape of this file:
##
## * **The printed column foots to the printed total.** Every figure comes from the invoice's own
##   `totals()`, never from arithmetic done here.
## * **Paper axes, y up the page.** Text is positioned by its *baseline*, and a caption that sits
##   "above" its value is at the larger y (the same convention the sheet furniture uses).
## * **A row that does not fit is counted, not run on.** The page is one page; lines beyond what it
##   holds are left off and the number left off is printed, which is a thing to notice rather than a
##   thing to hide.
## * **The company's own picture sits where a letterhead has one, and the name moves over to clear
##   it.** A business that has a logo gets its logo; a business that has none gets the same page it
##   has always got, down to the last byte, because the shift is zero rather than a second layout.
##
## `plan_page` is the layout as **data** - every row, every figure and every y - so the layout can be
## checked without opening a PDF, and `export_pdf` is then a dumb drawer.

const PdfWriterScript := preload("res://scripts/draft/pdf_writer.gd")
const PlotScaleScript := preload("res://scripts/draft/plot_scale.gd")
## The company logo is a picture, and this is where a picture's format and pixel size are read. The
## same reader an underlay uses, for the same reason: it establishes what a file is from its header
## rather than handing Godot's loader a file that might not be an image at all.
const UnderlayScript := preload("res://scripts/draft/raster_underlay.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")
const TaxScript := preload("res://scripts/biz/tax.gd")
const InvoiceScript := preload("res://scripts/biz/invoice.gd")

const POINTS_PER_MM := 72.0 / 25.4

## The two papers an invoice goes on, named the way a business says them. The plotter's own name for
## the small one is "ANSI A (8.5x11 in)", which is right on a sheet list and wrong on an invoice.
const SHEETS := {
	"LETTER": "ANSI A (8.5x11 in)",
	"A4": "A4",
}
const DEFAULT_SHEET := "LETTER"

const MARGIN_MM := 12.0
const TITLE_TEXT_MM := 6.0
const HEADING_TEXT_MM := 4.2
const BODY_TEXT_MM := 3.4
const SMALL_TEXT_MM := 2.9
const CAPTION_COLOUR := Color(0.35, 0.35, 0.35)
const RULE_COLOUR := Color(0.55, 0.55, 0.55)

## Exempt is a customer's legal status rather than a rate, so it prints even though it charges
## nothing (spec §2.11 on the tax table).
const EXEMPT_CODE := &"EXEMPT"

## Where each column ends, as a fraction of the printable width. Fractions rather than millimetres, so
## Letter and A4 lay the same table out on different paper.
const COLUMN_QTY := 0.62
const COLUMN_RATE := 0.79
const COLUMN_AMOUNT := 1.0
## How much of the width the description may use: everything before the quantity column, less a gap.
const DESCRIPTION_FRACTION := 0.58

## The page, ticking down from the top edge in millimetres. The numbers are chosen so the longest
## header a business actually has - a name, a street, a city, a phone and a tax number - still clears
## the rule under it, and so the totals block always clears the footer.
const TOP_MM := 18.0
const ADDRESS_MM := 25.0
const ADDRESS_STEP_MM := 4.4
## How many lines of its own address a business may put above the rule: an address, a phone number and
## a tax registration. Lines beyond that are counted rather than drawn over the rule, and the count
## says so at the foot of the page.
const MAX_ADDRESS_LINES := 7

## The company logo: a picture the business supplies, drawn at the top-left of the letterhead. A
## height **on paper** rather than a size in pixels, because a logo is furniture on a page like
## everything else here - the width follows from the picture's own proportion. It is capped, so a
## very wide logo cannot shove the name and the address off the page, and when it is capped the
## height comes down with it so the picture keeps its shape.
const LOGO_TOP_MM := 16.0
const LOGO_HEIGHT_MM := 16.0
## How far the name and the address move right to clear the logo. Zero-width when there is no logo,
## so a page with no picture is the page it has always been.
const LOGO_GAP_MM := 3.0
const LOGO_MAX_WIDTH_FRACTION := 0.28

const HEAD_RULE_MM := 64.0
const BILLED_BLOCK_MM := 70.0
const BLOCK_FIRST_MM := 76.0
const BLOCK_STEP_MM := 4.6
## How many lines a party may take: a name, a street, a city and a postal code.
const MAX_BLOCK_LINES := 4
const DATES_MM := 98.0
const HEAD_RULE_TWO_MM := 104.0
## A rule is never drawn through a line of text: every rule sits at least this far below the glyphs it
## follows, which is the fault a render caught that no coordinate test did.
const RULE_CLEARANCE_MM := 2.3
const TABLE_HEAD_MM := 110.0
const TABLE_RULE_MM := 115.6
const FIRST_ROW_MM := 122.0
const ROW_STEP_MM := 6.0
## The gap between the last line of the table and the first figure of the totals: room for the
## heading of the totals block and the rule under it, and for nothing to touch.
const TOTALS_GAP_MM := 13.0
## Where the heading and the rule sit inside that gap.
const TOTALS_CAPTION_MM := 8.0
const TOTALS_RULE_MM := 4.0
const TOTALS_STEP_MM := 5.4
## The gap between the last figure of the totals and the payments list.
const PAYMENTS_GAP_MM := 5.5
const FOOTER_MM := 14.0
## Room the terms and the note may take above the footer, so a long note cannot run off the paper.
const FOOTER_ROOM_MM := 16.0


static func sheet_names() -> Array[String]:
	var out: Array[String] = []
	for key in SHEETS.keys():
		out.append(String(key))
	out.sort()
	return out


## The plotter's name for a paper a business named. A paper nobody has is the default rather than an
## error: an invoice still has to print.
static func plotter_sheet(sheet: String) -> String:
	return String(SHEETS.get(sheet.to_upper(), SHEETS[DEFAULT_SHEET]))


static func page_size_mm(sheet: String = DEFAULT_SHEET, portrait: bool = true) -> Vector2:
	return PlotScaleScript.sheet_size_mm(plotter_sheet(sheet), portrait)


static func page_size_points(sheet: String = DEFAULT_SHEET, portrait: bool = true) -> Vector2:
	return PlotScaleScript.sheet_size_points(plotter_sheet(sheet), portrait)


# --- the layout, as data -----------------------------------------------------------------------


## Everything the page draws, positioned. See the file comment for why this is separate from the
## drawing: a layout that can be read is a layout that can be tested.
static func plan_page(invoice: InvoiceScript, options: Dictionary = {}) -> Dictionary:
	var sheet: String = String(options.get("sheet", DEFAULT_SHEET)).to_upper()
	var portrait: bool = bool(options.get("portrait", true))
	var page_mm: Vector2 = page_size_mm(sheet, portrait)
	var printable_mm: float = page_mm.x - 2.0 * MARGIN_MM
	var left_mm: float = MARGIN_MM
	var right_mm: float = page_mm.x - MARGIN_MM

	var rows: Array[Dictionary] = line_rows(invoice)
	var totals: Array[Dictionary] = totals_rows(invoice)
	var payments: Array[String] = payment_rows(invoice)

	# How many lines fit between the table head and the totals block, which itself has to clear the
	# footer. The totals are never cut: a document that hides its own total is not an invoice.
	var totals_height: float = TOTALS_GAP_MM + float(totals.size()) * TOTALS_STEP_MM
	var payments_height: float = 0.0 if payments.is_empty() else (float(payments.size()) + 1.0) * ROW_STEP_MM
	var floor_mm: float = page_mm.y - MARGIN_MM - FOOTER_MM - FOOTER_ROOM_MM - payments_height - totals_height
	var room: int = floori((floor_mm - FIRST_ROW_MM) / ROW_STEP_MM) + 1
	var kept: Array[Dictionary] = []
	var dropped: int = 0
	for index in rows.size():
		if index < room:
			kept.append(rows[index])
		else:
			dropped += 1
	var last_row_mm: float = FIRST_ROW_MM + float(maxi(kept.size(), 1) - 1) * ROW_STEP_MM
	var totals_top_mm: float = last_row_mm + TOTALS_GAP_MM
	var payments_top_mm: float = totals_top_mm + float(totals.size()) * TOTALS_STEP_MM + PAYMENTS_GAP_MM

	var company: Array[String] = _lines(options.get("company", []))
	var contact: Array[String] = _lines(options.get("contact", []))
	# The company's own picture, if the business has one, and how far the name and the address have to
	# move right to clear it. With no logo the shift is nothing, so the page is byte-for-byte the page
	# it has always been - which is the reason the header's x is a field rather than the margin const.
	var logo: Dictionary = logo_placement(String(options.get("logo", "")), printable_mm)
	var name_x_mm: float = left_mm
	if not logo.is_empty():
		name_x_mm = left_mm + float((logo["rect_mm"] as Rect2).size.x) + LOGO_GAP_MM
	# Every line a business gives is printed: the name, then its own address lines, then whatever it
	# put in `contact`. Dropping the tail of the company list when a contact list is also given would
	# silently lose a tax registration number, which is a line an invoice is expected to carry.
	var address_all: Array[String] = []
	for index in range(1, company.size()):
		address_all.append(company[index])
	for entry in contact:
		address_all.append(entry)
	var address: Dictionary = _capped(address_all, MAX_ADDRESS_LINES)
	var billed: Dictionary = _capped(_party_lines(invoice.customer), MAX_BLOCK_LINES)
	var job: Dictionary = _capped(_job_lines(invoice), MAX_BLOCK_LINES)

	return {
		"sheet": sheet,
		"portrait": portrait,
		"page_mm": page_mm,
		"margin_mm": MARGIN_MM,
		"printable_mm": printable_mm,
		"left_mm": left_mm,
		"right_mm": right_mm,
		"columns": {
			"description_mm": left_mm + printable_mm * DESCRIPTION_FRACTION,
			"qty_right_mm": left_mm + printable_mm * COLUMN_QTY,
			"rate_right_mm": left_mm + printable_mm * COLUMN_RATE,
			"amount_right_mm": left_mm + printable_mm * COLUMN_AMOUNT,
		},
		"header": {
			"name": company[0] if not company.is_empty() else "",
			"name_x_mm": name_x_mm,
			"logo": logo,
			"address": address["lines"],
			"address_y": ADDRESS_MM,
			"address_step": ADDRESS_STEP_MM,
			"contact": contact,
			"title": "INVOICE",
			"number_text": invoice.number if not invoice.number.strip_edges().is_empty() else "DRAFT - NOT YET ISSUED",
			"draft": invoice.number.strip_edges().is_empty(),
			"billed_to": billed["lines"],
			"job": job["lines"],
			"dates_text": _dates_text(invoice),
			"number_y": TOP_MM + TITLE_TEXT_MM + 2.0,
			"rule_y": HEAD_RULE_MM,
		},
		"table": {
			"head_y": TABLE_HEAD_MM,
			"rule_y": TABLE_RULE_MM,
			"first_row_y": FIRST_ROW_MM,
			"row_step": ROW_STEP_MM,
			"headings": ["DESCRIPTION", "QUANTITY", "RATE", "AMOUNT"],
		},
		"rows": kept,
		"dropped": dropped,
		"billed_block_y": BILLED_BLOCK_MM,
		"block_first_y": BLOCK_FIRST_MM,
		"block_step": BLOCK_STEP_MM,
		"dates_y": DATES_MM,
		"totals": {
			"caption": "WHAT THIS INVOICE COMES TO",
			"caption_y": totals_top_mm - TOTALS_CAPTION_MM,
			"rule_y": totals_top_mm - TOTALS_RULE_MM,
			"first_y": totals_top_mm,
			"step": TOTALS_STEP_MM,
			"rows": totals,
		},
		"payments": {
			"caption": "PAYMENTS RECEIVED",
			"caption_y": payments_top_mm - 4.0,
			"first_y": payments_top_mm,
			"step": ROW_STEP_MM,
			"rows": payments,
		},
		"footer": {
			"text": _footer_text(invoice),
			"note": _note_text(invoice, dropped, int(address["dropped"]) + int(billed["dropped"]) + int(job["dropped"])),
			"y": page_mm.y - MARGIN_MM - FOOTER_MM,
			"page_text": "page 1 of 1",
		},
	}


## One row per line of the invoice, in the invoice's own order, with the figures the model holds.
## `deduction` marks a row that takes money off rather than adding it - the retainage - so the drawer
## can print it the way a bookkeeper expects to see it.
static func line_rows(invoice: InvoiceScript) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for index in invoice.line_count():
		var held: Dictionary = invoice.line(index)
		var amount: MoneyScript = held.get("amount", null)
		var rate: MoneyScript = held.get("rate", null)
		out.append({
			"kind": int(held.get("kind", InvoiceScript.MILESTONE_LINE)),
			"description": String(held.get("description", "")),
			"quantity_text": _quantity_text(int(held.get("quantity_milli", InvoiceScript.QUANTITY_MILLI)),
				String(held.get("unit", ""))),
			"rate_text": _money_text(rate),
			"amount_text": _money_text(amount),
			"amount": amount,
			"deduction": false,
		})
	return out


## The totals block: the invoice's own figures, one row each, in the order a customer reads them.
## Tax is one row per code and names the code *and* the share it was charged on, because a customer
## checking a tax line wants to know what it was charged against.
static func totals_rows(invoice: InvoiceScript) -> Array[Dictionary]:
	var figures: Dictionary = invoice.totals()
	var out: Array[Dictionary] = []
	out.append(_figure_row("Subtotal", figures["subtotal"], false))
	for entry in invoice.tax_lines():
		var code: StringName = StringName(entry["tax_code"])
		var charged: MoneyScript = entry["tax"]
		# "No tax: 0.00" is noise the subtotal already covers, so a zero-rated code is left off. A
		# refusal and an EXEMPT customer are both different: the first has to be visible, and the
		# second is a legal statement a customer's bookkeeper looks for.
		if bool(entry["ok"]) and charged != null and charged.is_zero() and code != EXEMPT_CODE:
			continue
		var caption: String = TaxScript.describe(code)
		if bool(entry["ok"]):
			caption = "%s on %s" % [caption, _money_text(entry["taxable"])]
		else:
			caption = "%s (%s)" % [caption, String(entry["reason"])]
		out.append(_figure_row(caption, charged, false))
	var retained: MoneyScript = figures["retainage"]
	if retained != null and retained.is_valid() and not retained.is_zero():
		out.append({
			"caption": "Less retainage withheld",
			"value_text": _money_text(retained.neg()),
			"emphasis": false,
			"deduction": true,
		})
	out.append(_figure_row("Total", figures["total"], true))
	var applied: MoneyScript = figures["applied"]
	if applied != null and applied.is_valid() and not applied.is_zero():
		out.append({
			"caption": "Payments received",
			"value_text": _money_text(applied.neg()),
			"emphasis": false,
			"deduction": true,
		})
	out.append(_figure_row("Balance due", figures["balance"], true))
	return out


## One line per payment, in the words the payment record already uses: what arrived, how, and when.
static func payment_rows(invoice: InvoiceScript) -> Array[String]:
	var out: Array[String] = []
	for entry in invoice.payments:
		out.append(entry.describe())
	return out


# --- drawing it --------------------------------------------------------------------------------


## The page, as bytes a customer can open. The same writer that plots a landscape sheet draws this,
## at true paper millimetres, so an invoice and a plan come out of one program that measures paper
## the same way in both.
static func export_pdf(invoice: InvoiceScript, options: Dictionary = {}) -> PackedByteArray:
	var plan: Dictionary = plan_page(invoice, options)
	var page_mm: Vector2 = plan["page_mm"]
	var writer = PdfWriterScript.new()
	writer.begin_page(page_mm.x * POINTS_PER_MM, page_mm.y * POINTS_PER_MM)

	_emit_header(writer, plan)
	_emit_table(writer, plan)
	_emit_totals(writer, plan)
	_emit_payments(writer, plan)
	_emit_footer(writer, plan)
	return writer.build()


static func _emit_header(writer, plan: Dictionary) -> void:
	var header: Dictionary = plan["header"]
	var left: float = _pt(plan["left_mm"])
	var right: float = _pt(plan["right_mm"])

	_emit_logo(writer, plan)
	# The letterhead's own column, which is the margin when there is no logo and the margin shifted
	# right of the picture when there is one.
	var name_x: float = _pt(float(header["name_x_mm"]))
	writer.set_fill_colour(Color.BLACK)
	writer.draw_text(Vector2(name_x, _baseline(plan, TOP_MM, TITLE_TEXT_MM)), String(header["name"]),
		_pt(TITLE_TEXT_MM))
	writer.set_fill_colour(CAPTION_COLOUR)
	var y_mm: float = float(header["address_y"])
	var step_mm: float = float(header["address_step"])
	for entry in (header["address"] as Array):
		var text: String = String(entry)
		writer.draw_text(Vector2(name_x, _baseline(plan, y_mm, BODY_TEXT_MM)), text, _pt(SMALL_TEXT_MM))
		y_mm += step_mm

	writer.set_fill_colour(Color.BLACK)
	_draw_right(writer, String(header["title"]), right, _baseline(plan, TOP_MM, TITLE_TEXT_MM), _pt(TITLE_TEXT_MM))
	var number_text: String = String(header["number_text"])
	var number_y: float = _baseline(plan, float(header["number_y"]), HEADING_TEXT_MM)
	if bool(header["draft"]):
		writer.set_fill_colour(CAPTION_COLOUR)
	_draw_right(writer, number_text, right, number_y, _pt(HEADING_TEXT_MM))
	writer.set_fill_colour(Color.BLACK)
	_rule(writer, plan, float(header["rule_y"]), left, right)

	var block_y: float = float(plan["billed_block_y"])
	var first_y: float = float(plan["block_first_y"])
	var block_step: float = float(plan["block_step"])
	_draw_caption(writer, plan, float(plan["left_mm"]), block_y, "BILLED TO")
	_emit_block(writer, plan, left, first_y, block_step, header["billed_to"])

	var half_mm: float = float(plan["left_mm"]) + float(plan["printable_mm"]) * 0.52
	_draw_caption(writer, plan, half_mm, block_y, "JOB AND SITE")
	_emit_block(writer, plan, _pt(half_mm), first_y, block_step, header["job"])

	writer.set_fill_colour(Color.BLACK)
	var dates: String = String(header["dates_text"])
	writer.draw_text(Vector2(left, _baseline(plan, float(plan["dates_y"]), BODY_TEXT_MM)), dates, _pt(BODY_TEXT_MM))
	_rule(writer, plan, HEAD_RULE_TWO_MM, left, right)


## The company's picture, if the page has one. The image is loaded here, at the one moment a page is
## actually drawn - `plan_page` read only the file's header to place it - so a layout can be checked
## without decoding anything and the file is still opened exactly once per page.
##
## **This is the one place a logo's rectangle crosses from paper axes to the writer's.** The layout
## measures millimetres down from the top edge; the writer draws with y running up from the bottom, so
## the rectangle's foot is `page_height - (top + height)`. Passing the from-the-top number straight
## through is the fault that put every rule on this page at its mirror height (see `_rule`).
static func _emit_logo(writer, plan: Dictionary) -> void:
	var logo: Dictionary = (plan["header"] as Dictionary).get("logo", {})
	if logo.is_empty():
		return
	var image: Image = logo_image(String(logo.get("path", "")))
	if image == null:
		return
	var page_mm: Vector2 = plan["page_mm"]
	var rect_mm: Rect2 = logo["rect_mm"]
	writer.place_image(image, Rect2(
		_pt(rect_mm.position.x),
		(page_mm.y - rect_mm.end.y) * POINTS_PER_MM,
		_pt(rect_mm.size.x),
		_pt(rect_mm.size.y)
	))


## A party's lines: the first is the name and the rest are its address, so only the name is drawn in
## full black. All of them are clipped to the half of the page the block owns.
static func _emit_block(writer, plan: Dictionary, x_points: float, first_mm: float, step_mm: float,
		lines: Array) -> void:
	var room: float = _pt(float(plan["printable_mm"]) * 0.46)
	var y_mm: float = first_mm
	for index in lines.size():
		var size: float = BODY_TEXT_MM if index == 0 else SMALL_TEXT_MM
		writer.set_fill_colour(Color.BLACK if index == 0 else CAPTION_COLOUR)
		writer.draw_text(
			Vector2(x_points, _baseline(plan, y_mm, size)),
			clipped_text(writer, String(lines[index]), _pt(size), room),
			_pt(size)
		)
		y_mm += step_mm
	writer.set_fill_colour(Color.BLACK)


static func _emit_table(writer, plan: Dictionary) -> void:
	var table: Dictionary = plan["table"]
	var columns: Dictionary = plan["columns"]
	var left: float = _pt(plan["left_mm"])
	var right: float = _pt(plan["right_mm"])
	var headings: Array = table["headings"]
	writer.set_fill_colour(CAPTION_COLOUR)
	var head_y: float = _baseline(plan, float(table["head_y"]), SMALL_TEXT_MM)
	writer.draw_text(Vector2(left, head_y), String(headings[0]), _pt(SMALL_TEXT_MM))
	_draw_right(writer, String(headings[1]), _pt(columns["qty_right_mm"]), head_y, _pt(SMALL_TEXT_MM))
	_draw_right(writer, String(headings[2]), _pt(columns["rate_right_mm"]), head_y, _pt(SMALL_TEXT_MM))
	_draw_right(writer, String(headings[3]), _pt(columns["amount_right_mm"]), head_y, _pt(SMALL_TEXT_MM))
	_rule(writer, plan, float(table["rule_y"]), left, right)

	var rows: Array = plan["rows"]
	var y_mm: float = float(table["first_row_y"])
	var description_room: float = _pt(float(columns["description_mm"]) - float(plan["left_mm"]))
	for entry in rows:
		var baseline: float = _baseline(plan, y_mm, BODY_TEXT_MM)
		writer.set_fill_colour(Color.BLACK)
		writer.draw_text(
			Vector2(left, baseline),
			clipped_text(writer, String(entry["description"]), _pt(BODY_TEXT_MM), description_room),
			_pt(BODY_TEXT_MM)
		)
		writer.set_fill_colour(CAPTION_COLOUR)
		_draw_right(writer, String(entry["quantity_text"]), _pt(columns["qty_right_mm"]), baseline, _pt(SMALL_TEXT_MM))
		_draw_right(writer, String(entry["rate_text"]), _pt(columns["rate_right_mm"]), baseline, _pt(SMALL_TEXT_MM))
		_draw_right(writer, String(entry["amount_text"]), _pt(columns["amount_right_mm"]), baseline, _pt(BODY_TEXT_MM))
		writer.set_fill_colour(Color.BLACK)
		y_mm += float(table["row_step"])


## The totals block: a heading, a rule starting at the heading's own left edge, the figures against the
## right margin, and the balance in the large type a customer's eye lands on.
static func _emit_totals(writer, plan: Dictionary) -> void:
	var totals: Dictionary = plan["totals"]
	var rows: Array = totals["rows"]
	var block_left_mm: float = float(plan["left_mm"]) + float(plan["printable_mm"]) * 0.45
	_draw_caption(writer, plan, block_left_mm, float(totals["caption_y"]), String(totals["caption"]))
	var y_mm: float = float(totals["first_y"])
	var right: float = _pt(float(plan["right_mm"]))
	var caption_right: float = _pt(float(plan["left_mm"]) + float(plan["printable_mm"]) * 0.78)
	for index in rows.size():
		var entry: Dictionary = rows[index]
		var size: float = HEADING_TEXT_MM if bool(entry["emphasis"]) else BODY_TEXT_MM
		var baseline: float = _baseline(plan, y_mm, size)
		writer.set_fill_colour(Color.BLACK if bool(entry["emphasis"]) else CAPTION_COLOUR)
		_draw_right(writer, String(entry["caption"]), caption_right, baseline, _pt(size))
		_draw_right(writer, String(entry["value_text"]), right, baseline, _pt(size))
		y_mm += float(totals["step"])
	writer.set_fill_colour(Color.BLACK)
	_rule(writer, plan, float(totals["rule_y"]), _pt(block_left_mm), right)


static func _emit_payments(writer, plan: Dictionary) -> void:
	var payments: Dictionary = plan["payments"]
	var rows: Array = payments["rows"]
	if rows.is_empty():
		return
	_draw_caption(writer, plan, float(plan["left_mm"]), float(payments["caption_y"]),
		String(payments["caption"]))
	var y_mm: float = float(payments["first_y"])
	for entry in rows:
		writer.set_fill_colour(CAPTION_COLOUR)
		writer.draw_text(
			Vector2(_pt(plan["left_mm"]), _baseline(plan, y_mm, SMALL_TEXT_MM)),
			clipped_text(writer, String(entry), _pt(SMALL_TEXT_MM),
				_pt(float(plan["printable_mm"]) * 0.6)),
			_pt(SMALL_TEXT_MM)
		)
		y_mm += float(payments["step"])
	writer.set_fill_colour(Color.BLACK)


static func _emit_footer(writer, plan: Dictionary) -> void:
	var footer: Dictionary = plan["footer"]
	var left: float = _pt(plan["left_mm"])
	var right: float = _pt(plan["right_mm"])
	_rule(writer, plan, float(footer["y"]) - 3.0, left, right)
	writer.set_fill_colour(CAPTION_COLOUR)
	writer.draw_text(Vector2(left, _baseline(plan, float(footer["y"]) + 4.0, SMALL_TEXT_MM)),
		String(footer["text"]), _pt(SMALL_TEXT_MM))
	_draw_right(writer, String(footer["page_text"]), right,
		_baseline(plan, float(footer["y"]) + 4.0, SMALL_TEXT_MM), _pt(SMALL_TEXT_MM))
	var note: String = String(footer["note"])
	if not note.is_empty():
		writer.draw_text(Vector2(left, _baseline(plan, float(footer["y"]) + 8.0, SMALL_TEXT_MM)),
			clipped_text(writer, note, _pt(SMALL_TEXT_MM), _pt(float(plan["printable_mm"]))),
			_pt(SMALL_TEXT_MM))
	writer.set_fill_colour(Color.BLACK)


# --- the company logo -------------------------------------------------------------------------


## Where the company's picture goes on the page, in millimetres from the top edge, as
## `{path, rect_mm}` - or an empty Dictionary when there is no logo, or the file cannot be a logo.
##
## The size comes from the picture's **header** rather than from decoding it, so laying a page out
## stays cheap and a file that is not a picture is a page with no logo rather than a page that fails.
## The height is the stated one and the width follows from the proportion, capped to the fraction of
## the page a letterhead may use; when it is capped the height falls with it, so a wide banner ends up
## shorter rather than squashed.
static func logo_placement(path: String, printable_mm: float) -> Dictionary:
	if path.strip_edges().is_empty():
		return {}
	var info: Dictionary = UnderlayScript.sniff(path)
	if not bool(info.get("ok", false)):
		return {}
	var width_px := int(info.get("width_px", 0))
	var height_px := int(info.get("height_px", 0))
	if width_px <= 0 or height_px <= 0:
		return {}
	var width_mm: float = LOGO_HEIGHT_MM * float(width_px) / float(height_px)
	var height_mm: float = LOGO_HEIGHT_MM
	var cap_mm: float = printable_mm * LOGO_MAX_WIDTH_FRACTION
	if width_mm > cap_mm:
		width_mm = cap_mm
		height_mm = width_mm * float(height_px) / float(width_px)
	return {
		"path": path,
		"rect_mm": Rect2(MARGIN_MM, LOGO_TOP_MM, width_mm, height_mm),
	}


## The picture at `path` as an Image, at the one moment a page is drawn, or null. It is **flattened
## onto paper white**: a logo is normally a PNG with a transparent background, and the writer's image
## object is raw RGB8 with no alpha channel, so a transparent pixel would otherwise print whatever
## colour sits under its transparency - black, as often as not, which is a black box round the
## letterhead. Blending it onto white first is what makes the picture sit on the page rather than in
## a frame.
static func logo_image(path: String) -> Image:
	var info: Dictionary = UnderlayScript.sniff(path)
	if not bool(info.get("ok", false)):
		return null
	var decoded: Image = UnderlayScript.decode(FileAccess.get_file_as_bytes(path), String(info["format"]))
	if decoded == null:
		return null
	if not decoded.detect_alpha():
		return decoded
	var flattened: Image = Image.create_empty(decoded.get_width(), decoded.get_height(), false, Image.FORMAT_RGBA8)
	flattened.fill(Color.WHITE)
	flattened.blend_rect(decoded, Rect2i(Vector2i.ZERO, decoded.get_size()), Vector2i.ZERO)
	flattened.convert(Image.FORMAT_RGB8)
	return flattened


# --- small shared pieces -----------------------------------------------------------------------


## The width law the writer uses, applied to a column: a caption that would run into the next column
## is shortened and says so with dots, which is a page short of room rather than a mistake.
static func clipped_text(writer, text: String, size_points: float, room_points: float) -> String:
	if room_points <= 0.0:
		return ""
	if writer.text_width(text, size_points) <= room_points:
		return text
	var clipped := text
	while not clipped.is_empty() and writer.text_width(clipped + "...", size_points) > room_points:
		clipped = clipped.substr(0, clipped.length() - 1)
	return clipped + "..."


## A line of a table read as text, for a test or a log: what the row says, in one line.
static func row_text(row: Dictionary) -> String:
	return "%s, %s at %s, %s" % [
		String(row["description"]),
		String(row["quantity_text"]),
		String(row["rate_text"]),
		String(row["amount_text"]),
	]


## What the invoice charges tax on, per code, in the words the totals block prints.
static func tax_text(invoice: InvoiceScript) -> String:
	var parts := PackedStringArray()
	for entry in invoice.tax_lines():
		parts.append("%s on %s: %s" % [
			TaxScript.describe(StringName(entry["tax_code"])),
			_money_text(entry["taxable"]),
			_money_text(entry["tax"]),
		])
	return ", ".join(parts)


static func _figure_row(caption: String, amount: MoneyScript, emphasis: bool) -> Dictionary:
	return {
		"caption": caption,
		"value_text": _money_text(amount),
		"emphasis": emphasis,
		"deduction": false,
	}


## A figure as a customer reads it. An amount the invoice cannot read is a dash, which is the same
## thing Money prints for it: a page that hides an unreadable total is worse than one that admits it.
static func _money_text(amount: MoneyScript) -> String:
	if amount == null:
		return "—"
	return amount.format()


## A quantity as a plan writes it: whole units where the count is whole, and thousands where it is
## not. "1 EACH" is a document; "1.000 EACH" is a machine talking.
static func _quantity_text(quantity_milli: int, unit: String) -> String:
	if quantity_milli <= 0:
		return ""
	var whole: int = floori(float(quantity_milli) / float(InvoiceScript.QUANTITY_MILLI))
	var rest: int = quantity_milli % InvoiceScript.QUANTITY_MILLI
	var text: String = str(whole)
	if rest > 0:
		text += "." + str(rest).lpad(3, "0").rstrip("0")
	return "%s %s" % [text, unit] if not unit.strip_edges().is_empty() else text


static func _dates_text(invoice: InvoiceScript) -> String:
	var parts := PackedStringArray()
	if invoice.is_issued():
		parts.append("issued %s" % invoice.issued_at)
		parts.append("terms %d days" % invoice.terms_days)
		parts.append("due %s" % invoice.due_at)
	else:
		parts.append("not yet issued")
	if not invoice.period_start.strip_edges().is_empty() or not invoice.period_end.strip_edges().is_empty():
		parts.append("work %s to %s" % [invoice.period_start, invoice.period_end])
	return "  |  ".join(parts)


static func _footer_text(invoice: InvoiceScript) -> String:
	if invoice.is_issued():
		return "%s, due %s" % [invoice.number, invoice.due_at]
	return "not yet issued"


static func _note_text(invoice: InvoiceScript, dropped: int, dropped_header: int) -> String:
	var parts := PackedStringArray()
	if not invoice.note.strip_edges().is_empty():
		parts.append(invoice.note.strip_edges())
	if invoice.is_void():
		parts.append(invoice.voided_text())
	if dropped > 0:
		parts.append("%d further line(s) do not fit on this page" % dropped)
	if dropped_header > 0:
		parts.append("%d address line(s) do not fit above the rule" % dropped_header)
	return "  |  ".join(parts)


## The first `limit` lines, and how many were left over. A block with more lines than the page has
## room for is counted rather than drawn over the rule, and the count reaches the foot of the page.
static func _capped(lines: Array[String], limit: int) -> Dictionary:
	if lines.size() <= limit:
		return {"lines": lines, "dropped": 0}
	var kept: Array[String] = []
	for index in limit:
		kept.append(lines[index])
	return {"lines": kept, "dropped": lines.size() - limit}


## A party's own lines: the first is the name, the rest are its address.
static func _party_lines(party: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if party.is_empty():
		return out
	var name: String = String(party.get("name", "")).strip_edges()
	if not name.is_empty():
		out.append(name)
	for key in ["address", "address2", "city", "postal", "phone", "email"]:
		var value: String = String(party.get(key, "")).strip_edges()
		if not value.is_empty():
			out.append(value)
	if out.is_empty():
		out.append("the customer")
	return out


## The job's own name and the place the drawing already knows, which is the address on the invoice.
static func _job_lines(invoice: InvoiceScript) -> Array[String]:
	var out: Array[String] = []
	if not invoice.job.strip_edges().is_empty():
		out.append("job %s" % invoice.job)
	var site: Array[String] = _party_lines(invoice.site)
	for entry in site:
		out.append(entry)
	if out.is_empty():
		out.append("no job stated")
	return out


static func _lines(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for entry in (value as Array):
			var text: String = String(entry).strip_edges()
			if not text.is_empty():
				out.append(text)
	elif value is String and not (value as String).strip_edges().is_empty():
		out.append((value as String).strip_edges())
	return out


# --- paper arithmetic --------------------------------------------------------------------------


static func _pt(millimetres: float) -> float:
	return millimetres * POINTS_PER_MM


## The baseline of a line whose *top* is `top_mm` down from the paper's top edge. Paper y runs up the
## page, so a line lower down the sheet is a smaller y.
static func _baseline(plan: Dictionary, top_mm: float, size_mm: float) -> float:
	var page_mm: Vector2 = plan["page_mm"]
	return (page_mm.y - top_mm - size_mm) * POINTS_PER_MM


static func _draw_right(writer, text: String, right_points: float, baseline: float, size_points: float) -> void:
	if text.is_empty():
		return
	writer.draw_text(Vector2(right_points - writer.text_width(text, size_points), baseline), text, size_points)


static func _draw_caption(writer, plan: Dictionary, x_mm: float, top_mm: float, text: String) -> void:
	writer.set_fill_colour(CAPTION_COLOUR)
	writer.draw_text(Vector2(_pt(x_mm), _baseline(plan, top_mm, SMALL_TEXT_MM)), text, _pt(SMALL_TEXT_MM))
	writer.set_fill_colour(Color.BLACK)


## A straight rule across the page, `top_mm` down from the paper's top edge.
##
## **Everything in this file is millimetres from the top edge**, and this is the one place that turns
## them into PDF points. It is one place because it was two: the rules were passed a y from the top
## and drawn in the writer's own space, where y runs *up* from the bottom, so every rule on the page
## sat at its mirrored height - the table rule through the column headings, the totals rule through
## the totals heading, and nothing in a set of coordinate tests or a reading of the words to say so.
## A render said so, and `test_no_rule_is_drawn_through_a_line_of_text` now says so.
static func _rule(writer, plan: Dictionary, top_mm: float, from_points: float, to_points: float) -> void:
	var page_mm: Vector2 = plan["page_mm"]
	var y_points: float = (page_mm.y - top_mm) * POINTS_PER_MM
	writer.save_state()
	writer.set_line_width_points(0.5)
	writer.set_stroke_colour(RULE_COLOUR)
	writer.move_to(Vector2(from_points, y_points))
	writer.line_to(Vector2(to_points, y_points))
	writer.stroke()
	writer.restore_state()
	writer.set_fill_colour(Color.BLACK)