class_name Estimate
extends RefCounted
## A priced proposal: the lines, the markup, the tax, and the state of the thing.
##
## The roll-up is one function chain and every cent of it is an integer (§5.2). The rule that makes an
## invoice honest is that **the printed lines foot to the printed subtotal**: each line is rounded,
## and the subtotal is the sum of those rounded lines. A program that carries full precision and rounds
## at the end produces a column that does not add up, and the customer who adds up the column is the
## customer who calls the office (AC-B6).
##
## Tax is per line (§2.11) because a line may carry its own code, so the markup is apportioned across
## the lines before it can be taxed; `tax_shares()` is where that happens, and with one code on every
## line it reproduces `Tax.gross(price_before_tax, code)` to the cent.

const MoneyScript := preload("res://scripts/biz/money.gd")
const TaxScript := preload("res://scripts/biz/tax.gd")
const WorkUnitScript := preload("res://scripts/biz/work_unit.gd")
const LineScript := preload("res://scripts/biz/estimate_line.gd")
const ItemScript := preload("res://scripts/biz/cost_item.gd")
const KitScript := preload("res://scripts/biz/cost_kit.gd")
const BookScript := preload("res://scripts/biz/cost_book.gd")

const DRAFT := 0
const SENT := 1
const WON := 2
const LOST := 3
const EXPIRED := 4

const STATUS_NAMES := {
	DRAFT: "Draft",
	SENT: "Sent",
	WON: "Won",
	LOST: "Lost",
	EXPIRED: "Expired",
}

## A proposal number is `EST-2026-0041`. It is assigned when the estimate is first sent and never
## reused, so the number is a fact about a document rather than a label the program can re-point.
const NUMBER_PREFIX := "EST"

var id: String = ""
var number: String = ""
var customer: Dictionary = {}
## The drawing's own site, `{latitude, longitude}` (§4.9), so a proposal says where the work is.
var site: Dictionary = {}
var currency: StringName = &"CAD"
var lines: Array[EstimateLine] = []
## Markup applied to the direct cost, in parts per million.
var overhead_ppm: int = 0
var profit_ppm: int = 0
## The code a line gets when it does not name one (§4.9: the usual tax, overridable per line).
##
## The default is **NONE**, which is a real zero-rated code rather than a missing one, because there
## is no jurisdiction this program can assume: a business in Ontario wants HST and one in Quebec wants
## GST+QST, and a default guessed here would be charged to a customer in the wrong province. The
## office sets it, and an estimate left at NONE is a zero-tax proposal rather than an error.
var tax_code: StringName = &"NONE"
var deposit_ppm: int = 0
var revision: int = 0
var status: int = DRAFT
## Empty while drafting; `{hash, at, to}` once sent, and then immutable (§5.5).
var frozen: Dictionary = {}
## The cost book these prices came from, for provenance alongside each line's own `book_version`.
var book_version: int = 1
var book_source: String = ""
var notes: String = ""
var terms: String = ""


func _init(estimate_id: String = "") -> void:
	id = estimate_id if not estimate_id.is_empty() else LineScript.new_id()


static func make(estimate_id: String = "") -> Estimate:
	return (load("res://scripts/biz/estimate.gd") as GDScript).new(estimate_id)


static func new_id() -> String:
	return LineScript.new_id()


# --- the lines ----------------------------------------------------------------------------


## Whether the estimate may be edited at all. A sent proposal is a promise, so every mutator refuses.
func is_frozen() -> bool:
	return not frozen.is_empty()


func _refusal() -> String:
	if not is_frozen():
		return ""
	return "estimate %s was sent to %s and cannot be edited; revise it into a new draft" % [
		id, String(frozen.get("to", "the customer"))
	]


## Add a line. Refuses when the estimate is frozen, when the line is not sound, and **fills in the
## estimate's own tax code** for a line that names none, so the common case needs no code on a line.
func add_line(new_line: EstimateLine, book: CostBook = null) -> bool:
	var refusal: String = _refusal()
	if not refusal.is_empty():
		return false
	if new_line == null:
		return false
	# The estimate's own code fills in for a line that names none, **before** the line is checked:
	# "the usual tax, overridable per line" is the estimate's promise (§4.9), and a line refused for
	# having no code would make the promise unkeepable.
	if new_line.tax_code.is_empty():
		new_line.tax_code = tax_code
	var reason: String = new_line.problem(exempt())
	if not reason.is_empty():
		return false
	if not _tax_code_known(new_line.tax_code, book):
		return false
	# The book a line is added *from* is the book it was priced from, so the line records it (REQ-B6).
	# Left alone when no book is passed, because a line can also be added from a figure somebody read
	# off a supplier's quote, and claiming a version it never came from would be worse than saying
	# nothing.
	if book != null:
		new_line.book_version = book.version
		book_version = book.version
		book_source = book.source
	lines.append(new_line)
	return true


func put_line(new_line: EstimateLine, book: CostBook = null) -> bool:
	var at: int = _index_of(new_line.id)
	if at < 0:
		return false
	if not add_line(new_line, book):
		return false
	lines[at] = new_line
	return true


func erase_line(line_id: String) -> bool:
	if not _refusal().is_empty():
		return false
	var at: int = _index_of(line_id)
	if at < 0:
		return false
	lines.remove_at(at)
	return true


func line(line_id: String) -> EstimateLine:
	var at: int = _index_of(line_id)
	return lines[at] if at >= 0 else null


func line_count() -> int:
	return lines.size()


func _index_of(line_id: String) -> int:
	for index in lines.size():
		if lines[index].id == line_id:
			return index
	return -1


## Price a kit into the estimate: it expands to one line per item, at the quantity the recipe scaled
## to, and each keeps the item's own cost code and tax code (§5.3).
##
## Refuses on a cycle naming the chain, on a kit that nests too deep, and on any id the book does not
## have - all of them the book's own refusals, passed through rather than re-invented.
func add_kit(book: CostBook, kit_id: StringName, made_milli: int = KitScript.DEFAULT_YIELD_MILLI) -> Dictionary:
	var refusal: String = _refusal()
	if not refusal.is_empty():
		return {"ok": false, "reason": refusal, "lines": []}
	if book == null:
		return {"ok": false, "reason": "a kit needs a cost book", "lines": []}
	var expanded: Dictionary = book.expand_kit(kit_id, made_milli)
	if not bool(expanded["ok"]):
		return {"ok": false, "reason": String(expanded["reason"]), "lines": []}
	var added: Array[EstimateLine] = []
	for row: Dictionary in expanded["lines"]:
		var item: CostItem = book.item(row["item_id"])
		if item == null:
			continue
		var made_line: EstimateLine = LineScript.make(item, int(row["quantity_milli"]))
		if not add_line(made_line, book):
			return {"ok": false, "reason": "line %s was refused" % item.id, "lines": added}
		added.append(made_line)
	if added.is_empty():
		return {"ok": false, "reason": "cost kit %s made nothing" % kit_id, "lines": []}
	book_version = book.version
	book_source = book.source
	return {"ok": true, "reason": "", "lines": added}


# --- the roll-up --------------------------------------------------------------------------


func exempt() -> bool:
	return bool(customer.get("exempt", false))


func direct_cost() -> Money:
	var amounts: Array = []
	for each: EstimateLine in lines:
		amounts.append(each.cost())
	return MoneyScript.sum(amounts, currency)


## The sum of the rounded line extensions - the number that prints (§5.2, AC-B6).
func subtotal() -> Money:
	var amounts: Array = []
	for each: EstimateLine in lines:
		amounts.append(each.extension())
	return MoneyScript.sum(amounts, currency)


func overhead() -> Money:
	return subtotal().scale_ppm(overhead_ppm)


func profit() -> Money:
	return subtotal().add(overhead()).scale_ppm(profit_ppm)


func price_before_tax() -> Money:
	return subtotal().add(overhead()).add(profit())


## The markup, apportioned across the lines in proportion to what each line is worth.
##
## Tax is charged per line, so the markup has to belong to *some* line before it can be taxed. Each
## share is rounded by the module's one rule and the few cents that leaves over are handed to the
## largest line, so the shares add up to the markup **exactly** - a markup that came up a cent short
## would be a total that does not foot.
func markup_shares() -> Array:
	var markup: Money = overhead().add(profit())
	var shares: Array = []
	if lines.is_empty() or not markup.is_valid() or markup.cents == 0:
		return shares
	var weights: Array = []
	var total_weight: int = 0
	var biggest: int = 0
	for index in lines.size():
		var weight: int = lines[index].extension().cents
		weights.append(weight)
		total_weight += weight
		if weight > int(weights[biggest]):
			biggest = index
	if total_weight <= 0:
		return shares
	var assigned: int = 0
	for index in lines.size():
		var share: int = MoneyScript.rounded_div(
			markup.cents * int(weights[index]), total_weight
		)
		assigned += share
		shares.append(share)
	shares[biggest] = int(shares[biggest]) + (markup.cents - assigned)
	return shares


## The base each tax code is charged on, and what it came to, one entry per code.
##
## Lines sharing a code are charged **once on their sum**, which is what makes the ordinary case - one
## code on every line - identical to §5.2's single `Tax.gross(price_before_tax, code)`. The entries
## print as the components of an invoice's tax, so REQ-B10 (the components sum to the total) holds by
## construction rather than by luck.
func tax_shares(book: CostBook = null) -> Array:
	var shares: Array = markup_shares()
	var bases: Dictionary = {}
	var ordered: Array[StringName] = []
	for index in lines.size():
		var row: EstimateLine = lines[index]
		var code: StringName = row.tax_code if not row.tax_code.is_empty() else tax_code
		var base: Money = row.extension()
		if index < shares.size():
			base = base.add(MoneyScript.of(int(shares[index]), currency))
		if not bases.has(code):
			bases[code] = MoneyScript.zero(currency)
			ordered.append(code)
		bases[code] = (bases[code] as Money).add(base)
	var out: Array = []
	for code: StringName in ordered:
		out.append({
			"code": code,
			"base": bases[code],
			"gross": TaxScript.gross(bases[code], code) if _tax_code_known(code, book) \
				else {"ok": false, "reason": "unknown tax code '%s'" % String(code), "components": [], "tax": MoneyScript.invalid(currency)},
		})
	return out


func tax(book: CostBook = null) -> Money:
	var amounts: Array = []
	var shares: Array = tax_shares(book)
	for share: Dictionary in shares:
		var gross: Dictionary = share["gross"]
		if not bool(gross["ok"]):
			return MoneyScript.invalid(currency)
		amounts.append(gross["tax"])
	return MoneyScript.sum(amounts, currency)


## Every tax component of every code, in the order the codes were first used - what an invoice prints
## and what a bookkeeper checks.
func tax_components(book: CostBook = null) -> Array:
	var out: Array = []
	for share: Dictionary in tax_shares(book):
		var gross: Dictionary = share["gross"]
		var components: Array = gross.get("components", [])
		for component: Dictionary in components:
			out.append({
				"code": share["code"],
				"name": component["name"],
				"rate_ppm": component["rate_ppm"],
				"base": component["base"],
				"amount": component["amount"],
			})
	return out


func total(book: CostBook = null) -> Money:
	return price_before_tax().add(tax(book))


func deposit(book: CostBook = null) -> Money:
	return total(book).scale_ppm(deposit_ppm)


## Gross margin on the sale, in parts per million, computed in integers: what is left of the price
## before tax after what the work costs.
func margin_ppm() -> int:
	var price: Money = price_before_tax()
	if not price.is_valid() or price.cents == 0:
		return 0
	return MoneyScript.rounded_div(
		(price.cents - direct_cost().cents) * 1000000, price.cents
	)


func margin_text() -> String:
	return "%.2f%%" % (float(margin_ppm()) / 10000.0)


## The shape of the whole thing, for a panel or an export: every figure the roll-up produces.
func summary(book: CostBook = null) -> Dictionary:
	return {
		"direct_cost": direct_cost(),
		"subtotal": subtotal(),
		"overhead": overhead(),
		"profit": profit(),
		"price_before_tax": price_before_tax(),
		"tax": tax(book),
		"total": total(book),
		"deposit": deposit(book),
		"margin_ppm": margin_ppm(),
	}


# --- refusing -----------------------------------------------------------------------------


func _tax_code_known(code: StringName, book: CostBook) -> bool:
	if book != null and book.has_tax_code(code):
		return true
	return TaxScript.has(code)


## Everything wrong with this estimate, in sentences, or an empty list when it is sound.
##
## An estimate that does not foot is not an estimate with a warning on it: it is a document that must
## not go out, because a total that silently omits a line is worse than no total at all (§5.4).
func problems(book: CostBook = null) -> Array[String]:
	var out: Array[String] = []
	if id.is_empty():
		out.append("an estimate needs an id")
	for each: EstimateLine in lines:
		var reason: String = each.problem(exempt())
		if not reason.is_empty():
			out.append(reason)
			continue
		if not _tax_code_known(each.tax_code, book):
			out.append("estimate line %s carries tax code \"%s\", which is not a code" % [
				each.id, String(each.tax_code)
			])
			continue
		if exempt() and TaxScript.rate_ppm(each.tax_code) != 0:
			out.append("estimate line %s is taxable (%s) and the customer is exempt" % [
				each.id, String(each.tax_code)
			])
	if overhead_ppm < -LineScript.MAX_MARKUP_PPM or overhead_ppm > LineScript.MAX_MARKUP_PPM:
		out.append("overhead of %d ppm is outside +/-500%%" % overhead_ppm)
	if profit_ppm < -LineScript.MAX_MARKUP_PPM or profit_ppm > LineScript.MAX_MARKUP_PPM:
		out.append("profit of %d ppm is outside +/-500%%" % profit_ppm)
	if deposit_ppm < 0 or deposit_ppm > 1000000:
		out.append("a deposit of %d ppm is not a share of the total" % deposit_ppm)
	for share: Dictionary in tax_shares(book):
		var gross: Dictionary = share["gross"]
		if not bool(gross["ok"]):
			out.append(String(gross["reason"]))
	return out


func is_sound(book: CostBook = null) -> bool:
	return problems(book).is_empty()


## The rule AC-B6 states, as a question rather than an assertion: the printed lines foot to the
## printed subtotal. It holds by construction, and this is what proves the construction is the one in
## force.
func foots() -> bool:
	var summed: int = 0
	for each: EstimateLine in lines:
		summed += each.extension().cents
	return summed == subtotal().cents


# --- freezing -----------------------------------------------------------------------------


## The priced content, as one deterministic string: the lines, the markups, the tax default and the
## deposit. **Not** the notes, the terms, the customer or the number, which are not priced content
## (§5.5) - and so not the site either, which a proposal states but does not charge for.
func content_signature() -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append("currency:%s" % currency)
	parts.append("overhead_ppm:%d" % overhead_ppm)
	parts.append("profit_ppm:%d" % profit_ppm)
	parts.append("tax_code:%s" % String(tax_code))
	parts.append("deposit_ppm:%d" % deposit_ppm)
	for each: EstimateLine in lines:
		parts.append("%s|%s|%s|%d|%s|%d|%s|%d|%d|%d" % [
			each.id, each.cost_item, each.description, each.quantity_milli, String(each.unit),
			each.kind, String(each.tax_code), each.unit_cost.cents, each.unit_price.cents,
			each.waste_ppm,
		])
	return "\n".join(parts)


func content_hash() -> String:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(content_signature().to_utf8_buffer())
	return (context.finish() as PackedByteArray).hex_encode()


## Freeze the estimate, and refuse if it does not foot: an estimate that cannot be sent should not be
## able to look sent. Once frozen, every mutator refuses, and the copy for editing is a new draft
## revision - which is how a business revises a quote without rewriting what the customer holds.
func freeze(sent_to: String) -> bool:
	if is_frozen() or sent_to.strip_edges().is_empty():
		return false
	if not is_sound():
		return false
	frozen = {
		"hash": content_hash(),
		"at": Time.get_datetime_string_from_system(true, true),
		"to": sent_to,
	}
	status = SENT
	return true


## Whether the stored hash still describes the content. It always should, and the point of asking is
## that a project which trusts a hash without checking it does not have a hash.
func freeze_holds() -> bool:
	if not is_frozen():
		return false
	return String(frozen.get("hash", "")) == content_hash()


## A new draft revision of a frozen estimate: the same lines, revision + 1, and open for editing.
func new_revision() -> Estimate:
	var next: Estimate = from_dict(to_dict())
	next.revision = revision + 1
	next.frozen = {}
	next.status = DRAFT
	return next


## Assign the proposal number it will carry for ever. Refused once it has one.
func assign_number(year: int, sequence: int) -> String:
	if not number.is_empty() or sequence <= 0:
		return ""
	number = "%s-%04d-%04d" % [NUMBER_PREFIX, year, sequence]
	return number


# --- persistence --------------------------------------------------------------------------


func copy() -> Estimate:
	return from_dict(to_dict())


func to_dict() -> Dictionary:
	var rows: Array = []
	for each: EstimateLine in lines:
		rows.append(each.to_dict())
	return {
		"id": id,
		"number": number,
		"customer": customer.duplicate(true),
		"site": site.duplicate(true),
		"currency": String(currency),
		"lines": rows,
		"overhead_ppm": overhead_ppm,
		"profit_ppm": profit_ppm,
		"tax_code": String(tax_code),
		"deposit_ppm": deposit_ppm,
		"revision": revision,
		"status": status,
		"frozen": frozen.duplicate(true),
		"book_version": book_version,
		"book_source": book_source,
		"notes": notes,
		"terms": terms,
	}


## Read one back. Numbers come out of JSON as floats, so every integer field is coerced, and nothing
## comes back typed (§2.1a).
static func from_dict(data: Dictionary) -> Estimate:
	var estimate: Estimate = (load("res://scripts/biz/estimate.gd") as GDScript).new(
		String(data.get("id", ""))
	)
	estimate.number = String(data.get("number", ""))
	var person: Variant = data.get("customer", {})
	estimate.customer = (person as Dictionary).duplicate(true) if person is Dictionary else {}
	var where: Variant = data.get("site", {})
	estimate.site = (where as Dictionary).duplicate(true) if where is Dictionary else {}
	estimate.currency = StringName(data.get("currency", "CAD"))
	var rows: Variant = data.get("lines", [])
	if rows is Array:
		for record: Variant in rows:
			if record is Dictionary:
				estimate.lines.append(LineScript.from_dict(record))
	estimate.overhead_ppm = int(data.get("overhead_ppm", 0))
	estimate.profit_ppm = int(data.get("profit_ppm", 0))
	estimate.tax_code = StringName(data.get("tax_code", "NONE"))
	estimate.deposit_ppm = int(data.get("deposit_ppm", 0))
	estimate.revision = int(data.get("revision", 0))
	estimate.status = int(data.get("status", DRAFT))
	var seal: Variant = data.get("frozen", {})
	estimate.frozen = (seal as Dictionary).duplicate(true) if seal is Dictionary else {}
	estimate.book_version = int(data.get("book_version", 1))
	estimate.book_source = String(data.get("book_source", ""))
	estimate.notes = String(data.get("notes", ""))
	estimate.terms = String(data.get("terms", ""))
	return estimate


## A proposal as text, the way it reads on the page: the working document behind the PDF sheet that
## phase 7 writes.
func describe(book: CostBook = null) -> String:
	var out: PackedStringArray = PackedStringArray()
	var heading: String = number if not number.is_empty() else "(draft, unnumbered)"
	out.append("%s  rev %d  %s" % [heading, revision, String(STATUS_NAMES.get(status, "?"))])
	var client: String = String(customer.get("name", ""))
	if not client.is_empty():
		out.append("for %s" % client)
	for each: EstimateLine in lines:
		out.append("  %s" % each.line_text())
	out.append("  %-40s %s" % ["subtotal", subtotal().format_with_currency()])
	if overhead_ppm != 0:
		out.append("  %-40s %s" % [
			"overhead %.3f%%" % (float(overhead_ppm) / 10000.0), overhead().format_with_currency()
		])
	if profit_ppm != 0:
		out.append("  %-40s %s" % [
			"profit %.3f%%" % (float(profit_ppm) / 10000.0), profit().format_with_currency()
		])
	for component: Dictionary in tax_components(book):
		out.append("  %-40s %s" % [
			"%s at %.3f%%" % [component["name"], float(component["rate_ppm"]) / 10000.0],
			(component["amount"] as Money).format_with_currency(),
		])
	out.append("  %-40s %s" % ["total", total(book).format_with_currency()])
	if deposit_ppm != 0:
		out.append("  %-40s %s" % ["deposit", deposit(book).format_with_currency()])
	out.append("  %-40s %s" % ["direct cost", direct_cost().format_with_currency()])
	out.append("  %-40s %s" % ["gross margin", margin_text()])
	return "\n".join(out)