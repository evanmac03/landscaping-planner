class_name PlantOrder
extends RefCounted
## The nursery order: the drawing's planting list turned into what to buy, and from whom.
##
## Three documents, and this is the join from the first two to the third:
##
##     the planting schedule   what is standing, and how many of each (PlantPlacement.schedule)
##     the cost book           what one of them costs, and which item prices it
##     a purchase order        what to buy, from whom, as a draft (PurchaseOrder, on JobDesk)
##
## ## The two decisions
##
## * **The book prices the plant; a person names the nursery.** A rate is the office's own knowledge and
##   belongs in the book. *Which nursery* is a fact about that business's relationships - one office
##   buys trees from one grower and perennials from another - and a book shipped with the program cannot
##   carry it. That is why every plant item in the starter book has an empty supplier, and why the one
##   thing an order insists on is that somebody says who it goes to.
## * **A plant the book cannot price is refused by name, never ordered at nothing.** The rule the
##   takeoff, the tax table and the estimate already keep. An order that quietly dropped a species
##   reads as a smaller planting than the plan drew, and the office finds out at the gate.
##
## ## What it is not
##
## It is not the installed work. Soil preparation, labour and mulch are the estimate's business, priced
## per square metre off the bed outlines; this is the **plant material itself**, at the book's rate,
## written as a **draft** purchase order. Nothing is committed to a job until somebody issues it, and
## this module deliberately stops at the draft - ordering is a decision the office takes in the one
## place orders are managed.

const CostItemScript := preload("res://scripts/biz/cost_item.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")
const OrderScript := preload("res://scripts/biz/purchase_order.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")
const DeskScript := preload("res://scripts/biz/job_desk.gd")

## The phase a planting is bought against. The same name the takeoff's own layer table uses for
## `401-NEW-PLANT`, so a nursery order lands in the phase the estimate already has for it.
const PLANTING_CODE := &"PLANTING"

## One plant category to the item in the book that prices one of them.
##
## A category rather than a species, because the book has no entry per cultivar and should not: a
## thirty-centimetre herb and a two-metre tree are not the same money, and a category is the finest
## grain a price list actually carries. It is the software's **suggestion** - the office overrides it
## by handing `item_for` in, because the office knows a 50 mm caliper from a 100 mm one and a category
## does not (§6: the office chooses, the software suggests).
##
## A `static var` rather than a `const` for the reason the takeoff's own `LAYER_MEASURES` gives: a
## constant expression may not be built out of another script's constants.
static var CATEGORY_ITEMS: Dictionary = {
	SpeciesScript.TREE: &"plant-tree-50mm",
	SpeciesScript.SHRUB: &"plant-shrub-2g",
	SpeciesScript.PERENNIAL: &"plant-perennial-1g",
	SpeciesScript.ANNUAL: &"plant-perennial-1g",
	SpeciesScript.GRASS: &"plant-grass-2g",
	SpeciesScript.GROUNDCOVER: &"plant-perennial-1g",
	SpeciesScript.VINE: &"plant-shrub-2g",
	SpeciesScript.FERN: &"plant-perennial-1g",
	SpeciesScript.BULB: &"plant-perennial-1g",
	SpeciesScript.HERB: &"plant-perennial-1g",
}


# --- what one plant of this kind is priced with -------------------------------------------------


## The item in the book that prices one plant of this category, or empty when this program has no
## opinion about that category. Empty is a real answer: a new category somebody adds to the catalogue
## has no price until the office states one, and inventing a neighbour's price would be inventing a
## number.
static func category_item(category: int) -> StringName:
	return StringName(CATEGORY_ITEMS.get(category, &""))


# --- the plan ----------------------------------------------------------------------------------


## Plan the order: one line for each kind of plant the drawing stands.
##
## `rows` is what `PlantPlacement.schedule()` returns - pure dictionaries of a species id, a count and
## the names - so this file needs no yard, no scene, no catalogue and no window. That is the whole
## reason a planting list was written as data in the first place.
##
## `item_for` maps a species id to the book item that prices one of them, and takes precedence over the
## category suggestion, because the office's own answer beats the program's guess.
##
## The returned dictionary carries:
##
##     lines        one Dictionary per kind, priced or not, in botanical-name order
##     problems     what could not be priced, in sentences naming the plant
##     total        what the whole order comes to (Money), invalid when anything is unpriced
##     priced_total what the priced lines alone come to (Money)
##     priced       how many lines carry a rate
##     unpriced     how many do not
##     plants       how many plants the lines stand for
##     currency     the book's currency, so every figure above is in one money
static func plan(rows: Array, book: CostBook = null, item_for: Dictionary = {}) -> Dictionary:
	var currency: StringName = _currency(book)
	var lines: Array[Dictionary] = []
	var problems: Array[String] = []
	var priced := 0
	var unpriced := 0
	var plants := 0
	for row: Dictionary in rows:
		var quantity: int = int(row.get("count", 0))
		if quantity <= 0:
			continue
		plants += quantity
		var held: Dictionary = _line_for(row, quantity, book, item_for, currency)
		if bool(held["priced"]):
			priced += 1
		else:
			unpriced += 1
			problems.append(String(held["problem"]))
		lines.append(held)
	lines.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["sort_key"]).naturalnocasecmp_to(String(b["sort_key"])) < 0)
	var everything: Array = []
	var priced_only: Array = []
	for held: Dictionary in lines:
		everything.append(held["amount"])
		if bool(held["priced"]):
			priced_only.append(held["amount"])
	return {
		"lines": lines,
		"problems": problems,
		"total": MoneyScript.sum(everything, currency),
		"priced_total": MoneyScript.sum(priced_only, currency),
		"priced": priced,
		"unpriced": unpriced,
		"plants": plants,
		"currency": currency,
	}


## One kind of plant, priced or refused. `quantity_milli` is the quantity in the module's thousandths,
## which is what a purchase order line takes, so the count never has to be converted twice.
static func _line_for(row: Dictionary, quantity: int, book: CostBook, item_for: Dictionary,
		currency: StringName) -> Dictionary:
	var species: StringName = StringName(row.get("id", ""))
	var category: int = int(row.get("category", -1))
	var item_id: StringName = &""
	if not species.is_empty():
		item_id = StringName(item_for.get(species, &""))
		if item_id.is_empty():
			item_id = category_item(category)
	var item: CostItem = null if book == null else book.item(item_id)
	var held := {
		"species": species,
		"words": _plant_words(row),
		"sort_key": _sort_key(row),
		"count": quantity,
		"quantity_milli": quantity * OrderScript.QUANTITY_MILLI,
		"category": category,
		"category_name": String(row.get("category_name", "")),
		"item_id": item_id,
		"item_name": "" if item == null else item.name,
		"unit": "EACH" if item == null else String(item.unit),
		"supplier": "" if item == null else String(item.supplier),
		"unit_cost": MoneyScript.invalid(currency),
		"amount": MoneyScript.invalid(currency),
		"priced": false,
		"price_words": "",
		"problem": "",
	}
	if item == null or not item.is_valid():
		held["price_words"] = _unpriced_words(species, category, item_id, book)
		held["problem"] = "%s: %s" % [held["words"], held["price_words"]]
		return held
	held["unit_cost"] = item.rate
	held["amount"] = MoneyScript.round_div(
		item.rate.cents * int(held["quantity_milli"]), OrderScript.QUANTITY_MILLI, currency
	)
	held["priced"] = true
	held["price_words"] = "%d at %s = %s (%s)" % [
		quantity, item.rate.format_with_currency(),
		(held["amount"] as MoneyScript).format_with_currency(), item.name,
	]
	return held


## Why a kind could not be priced, saying which of the two things is missing: an item for the category
## or an item in the book. "There is nothing in the book" and "nothing here knows what prices a fern"
## are different errands, and the office needs to know which one it is.
static func _unpriced_words(species: StringName, category: int, item_id: StringName,
		book: CostBook) -> String:
	if species.is_empty():
		return "no species recorded, so there is nothing to price it with"
	if item_id.is_empty():
		return "nothing in the book prices a %s yet" % _category_words(category)
	if book == null:
		return "there is no cost book to price %s from" % String(item_id)
	return "the book has no item %s" % String(item_id)


static func _category_words(category: int) -> String:
	var name: String = String(SpeciesScript.CATEGORY_NAMES.get(category, ""))
	return name.to_lower() if not name.is_empty() else "plant of that kind"


## The plant as a planting plan writes it: the botanical name, the cultivar, the name a person uses,
## and the size it is bought at. The same sentence the takeoff writes, so the order and the proposal
## cannot describe one plant two ways.
static func _plant_words(row: Dictionary) -> String:
	var words: String = String(row.get("botanical_name", ""))
	if words.is_empty():
		words = "a plant nobody can name"
	if not String(row.get("cultivar", "")).is_empty():
		words = "%s '%s'" % [words, String(row["cultivar"])]
	var common: String = String(row.get("common_name", ""))
	if not common.is_empty():
		words = "%s (%s)" % [words, common]
	var size: int = int(row.get("spread_cm", 0))
	if size > 0:
		words = "%s, %.1f m" % [words, float(size) / 100.0]
	return words


## The sort key: botanical name, then cultivar. A row with no species sorts **last** whatever it is
## called, because a plant nobody can name is the thing a list must not bury in the middle.
static func _sort_key(row: Dictionary) -> String:
	var named := "0" if not String(row.get("id", "")).is_empty() else "1"
	return "%s%s|%s" % [named, String(row.get("botanical_name", "")), String(row.get("cultivar", ""))]


static func _currency(book: CostBook) -> StringName:
	return book.currency if book != null else &"CAD"


# --- what a person reads -----------------------------------------------------------------------


## One kind of plant as a row: the count, the plant, and what the book prices it at.
static func row_words(held: Dictionary) -> String:
	return "%d x %s - %s" % [int(held["count"]), String(held["words"]), String(held["price_words"])]


## Every row, in the plan's order, for a list on a page.
static func plan_rows(planned: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for held: Dictionary in planned.get("lines", []):
		out.append(row_words(held))
	return out


## The one line a menu or a page opens with: how much planting there is, and what it comes to.
##
## A total that leaves out a kind the book cannot price is **not a total**, and this says so rather
## than printing a smaller number as though it were the answer.
static func summary(planned: Dictionary) -> String:
	var plants: int = int(planned.get("plants", 0))
	if plants <= 0:
		return "nothing is planted on this drawing"
	var kinds: int = (planned.get("lines", []) as Array).size()
	var words := "%d plant%s in %d kind%s" % [plants, _plural(plants), kinds, _plural(kinds)]
	var unpriced: int = int(planned.get("unpriced", 0))
	if unpriced == 0:
		return "%s: %s" % [words, (planned["total"] as MoneyScript).format_with_currency()]
	return "%s: %s priced, and %d kind%s the book cannot price, so that is not the whole order" % [
		words, (planned["priced_total"] as MoneyScript).format_with_currency(),
		unpriced, _plural(unpriced),
	]


## The same sentence with the book it was priced from on it: an order whose rate cannot be traced to a
## book is a number nobody can check.
static func describe(planned: Dictionary, book: CostBook = null) -> String:
	if book == null:
		return summary(planned)
	return "%s (priced from %s)" % [summary(planned), book.describe()]


static func _plural(number: int) -> String:
	return "" if number == 1 else "s"


# --- what to buy, from whom --------------------------------------------------------------------


## The priced lines gathered by the nursery they come from: one order per supplier, because that is what
## a purchase order is - it goes to one place.
##
## A line's supplier is the one the book states for its item; where the book states nobody, the
## `default_supplier` the person gave is used, so an office that buys everything from one grower states
## it once. A line with neither ends up in the group whose supplier is empty, and `write_orders` refuses
## that by name rather than writing an order addressed to nobody.
static func by_supplier(lines: Array, default_supplier: String = "",
		currency: StringName = &"CAD") -> Array[Dictionary]:
	var order: Array[String] = []
	var groups: Dictionary = {}
	for held: Dictionary in lines:
		var who := String(held.get("supplier", ""))
		if who.strip_edges().is_empty():
			who = default_supplier.strip_edges()
		if not groups.has(who):
			groups[who] = []
			order.append(who)
		(groups[who] as Array).append(held)
	var out: Array[Dictionary] = []
	for who: String in order:
		var held_lines: Array = groups[who]
		var amounts: Array = []
		for line: Dictionary in held_lines:
			amounts.append(line["amount"])
		out.append({
			"supplier": who,
			"lines": held_lines,
			"total": MoneyScript.sum(amounts, currency),
		})
	return out


## Write the orders: a draft purchase order per nursery, one line per kind of plant, on the job's
## planting phase.
##
## **Refused for the whole plan** rather than writing part of it, whenever part of it cannot be ordered:
## a job that has a nursery order for three of its five kinds and no word about the other two is worse
## than no order, because it looks finished.
##
## Nothing is issued here (§8.4): the office sees what the order would commit the job to and issues it
## in the one place orders are managed.
##
## Returns `{ok, orders, reason}` - `orders` holds whatever was written, so a caller can say where it
## went even when the answer is no.
static func write_orders(desk: DeskScript, job_id: String, planned: Dictionary,
		supplier: String) -> Dictionary:
	var made: Array = []
	if desk == null:
		return {"ok": false, "orders": made, "reason": "there is no job desk to write an order on"}
	if desk.job(job_id) == null:
		return {"ok": false, "orders": made,
			"reason": "there is no job %s to order the plants for" % job_id}
	var lines: Array = planned.get("lines", [])
	if lines.is_empty():
		return {"ok": false, "orders": made, "reason": "there is nothing planted to order"}
	for held: Dictionary in lines:
		if not bool(held.get("priced", false)):
			return {"ok": false, "orders": made,
				"reason": "%s cannot be ordered: %s" % [
					String(held["words"]), String(held["price_words"])]}
	var currency: StringName = planned.get("currency", &"CAD")
	for group: Dictionary in by_supplier(lines, supplier, currency):
		var who := String(group["supplier"])
		var group_lines: Array = group["lines"]
		if who.is_empty():
			return {"ok": false, "orders": made,
				"reason": "say which nursery %s comes from" % String((group_lines[0] as Dictionary)["words"])}
		var first: Dictionary = group_lines[0]
		var rate: Money = first["unit_cost"]
		var order: PurchaseOrder = desk.make_purchase_order(
			job_id, PLANTING_CODE, String(first["words"]),
			int(first["quantity_milli"]), rate, who, StringName(first["unit"])
		)
		if order == null:
			return {"ok": false, "orders": made,
				"reason": "the order for %s could not be written" % who}
		for index in range(1, group_lines.size()):
			var held: Dictionary = group_lines[index]
			var held_rate: Money = held["unit_cost"]
			if not order.add_line(String(held["words"]), StringName(held["unit"]),
					int(held["quantity_milli"]), held_rate):
				return {"ok": false, "orders": made,
					"reason": "a line for %s could not be added" % who}
		made.append(order)
	return {"ok": true, "orders": made, "reason": ""}


## What the written orders say, for the line that reports where they went.
static func orders_words(orders: Array) -> String:
	if orders.is_empty():
		return "no order was written"
	var parts: PackedStringArray = PackedStringArray()
	for held: PurchaseOrder in orders:
		parts.append("%s to %s for %s" % [
			held.number, held.supplier, held.ordered_total().format_with_currency(),
		])
	return ", ".join(parts)