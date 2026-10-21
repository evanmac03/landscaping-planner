class_name BizPricePreview
extends RefCounted
## What a change to the cost book would do to the work already quoted (§12: the cost book panel's
## "preview of what it changes").
##
## The one fact this file exists to keep true: **a cost book change does not move a quoted price**
## (REQ-B6, AC-B7). A cost book holds what the business *pays*; the price a customer sees is a
## policy applied on top of it (§4.3). So a preview shows two figures side by side - the **cost** of
## each stored estimate recomputed against the new prices, and the **price**, which does not move -
## and the figure that changes is the margin. A preview that recomputed a price would be a program
## quietly re-quoting a customer's job.
##
## Nothing here is written. The estimates are read and handed back untouched, and the new book is
## whichever one `BizBookImport.apply` returned rather than an edit to the old one, so an estimate
## priced from book v3 can be looked at all day without its prices moving.
##
## The estimates come from the store (`read_estimates`), because a proposal that has been sent is a
## record and not a panel's memory: an estimate is only worth previewing against a new price list if
## it survives the person who typed it.

const MoneyScript := preload("res://scripts/biz/money.gd")
const BookScript := preload("res://scripts/biz/cost_book.gd")
const EstimateScript := preload("res://scripts/biz/estimate.gd")
const LineScript := preload("res://scripts/biz/estimate_line.gd")

const PPM := 1000000

## The book a plan is read against, and the estimates it is read for. Both are handed in.
var book: CostBook = null
var estimates: Array[Estimate] = []


## Point the preview at a book and a list of estimates. Anything in the list that is not an estimate
## is dropped rather than assumed.
func bind(book_ref: CostBook, estimate_list: Array) -> void:
	book = book_ref
	estimates = []
	for each: Variant in estimate_list:
		if each is Estimate:
			estimates.append(each)


# --- proposing a change ---------------------------------------------------------------------


## Reprice every item - or every item from one supplier - by a percentage, into the same plan shape
## `BizBookImport.plan` returns, so a bulk update and an imported price list are previewed and
## applied by one path.
##
## `percent_ppm` is a signed change in parts per million: `50000` is +5%, `-25000` is -2.5%. A change
## of nothing is refused rather than applied, because a new version of a book with the same prices in
## it is a version that lies about when a price moved. Every price is scaled by the module's one
## rounding rule, so a +10% then a -10% returns to within the cent the arithmetic left (§2.1).
static func bulk_plan(source_book: CostBook, percent_ppm: int, supplier: StringName = &"") -> Dictionary:
	if source_book == null:
		return _no_plan("there is no cost book to plan against")
	if percent_ppm == 0:
		return _no_plan("a bulk update of nothing would be a new version of the book with the same prices in it")
	var changes: Array[Dictionary] = []
	var skipped: Array[Dictionary] = []
	for item_id: StringName in source_book.item_ids():
		var each: CostItem = source_book.item(item_id)
		if each == null:
			continue
		if not supplier.is_empty() and each.supplier != supplier:
			skipped.append({
				"id": String(each.id),
				"name": each.name,
				"supplier": String(each.supplier),
				"reason": "this item is from \"%s\", not \"%s\"" % [String(each.supplier), String(supplier)],
			})
			continue
		var after: Money = each.rate.scale_ppm(PPM + percent_ppm)
		changes.append({
			"id": String(each.id),
			"name": each.name,
			"before_cents": int(each.rate.cents),
			"after_cents": int(after.cents),
			"delta_cents": int(after.cents) - int(each.rate.cents),
			"currency": String(each.rate.currency),
			"row_currency": String(source_book.currency),
			"from_unit": String(each.unit),
			"unit": String(each.unit),
			"unit_changed": false,
			"kind_changed": false,
			"waste_changed": false,
			"kind": each.kind,
			"waste_ppm": each.waste_ppm,
			"supplier": String(each.supplier),
			"cost_code": String(each.cost_code),
			"line": 0,
			"is_new": false,
		})
	if changes.is_empty():
		if supplier.is_empty():
			return _no_plan("this book has no items to reprice")
		return _no_plan("no item in this book is from \"%s\"" % String(supplier))
	return {
		"ok": true,
		"reason": "",
		"changes": changes,
		"unchanged": skipped,
		"unmatched": [],
		"created": [],
		"problems": [],
		"currency": source_book.currency,
	}


static func _no_plan(reason: String) -> Dictionary:
	return {
		"ok": false, "reason": reason,
		"changes": [], "unchanged": [], "unmatched": [], "created": [], "problems": [],
		"currency": &"",
	}


# --- reading a plan -------------------------------------------------------------------------


## What this plan would do to the estimates in hand. Returns
## `{ok, reason, rows, moved, cost_before_cents, cost_after_cents, price_before_cents,
## price_after_cents, currency}`.
##
## `moved` counts the estimates whose **cost** would move, which is the number the preview exists to
## show. The two price totals are returned as well as equal, on purpose: a test asserts they are equal
## and a reader can see that the figure that is not supposed to move is carried rather than omitted.
func preview(change_plan: Dictionary) -> Dictionary:
	if book == null:
		return _nothing("there is no cost book to preview a change against")
	if not bool(change_plan.get("ok", false)):
		return _nothing("this plan did not read: %s" % String(change_plan.get("reason", "")))
	var prices: Dictionary = {}
	for entry: Dictionary in change_plan.get("changes", []):
		prices[StringName(entry["id"])] = MoneyScript.of(int(entry["after_cents"]), book.currency)
	var rows: Array[Dictionary] = []
	var moved: int = 0
	var cost_before: int = 0
	var cost_after: int = 0
	var price_before: int = 0
	var price_after: int = 0
	for estimate: Estimate in estimates:
		var row: Dictionary = row_for(estimate, prices)
		rows.append(row)
		cost_before += int(row["cost_before_cents"])
		cost_after += int(row["cost_after_cents"])
		price_before += int(row["price_cents"])
		price_after += int(row["price_cents"])
		if int(row["delta_cents"]) != 0:
			moved += 1
	return {
		"ok": true,
		"reason": "",
		"rows": rows,
		"moved": moved,
		"cost_before_cents": cost_before,
		"cost_after_cents": cost_after,
		"price_before_cents": price_before,
		"price_after_cents": price_after,
		"currency": book.currency,
	}


static func _nothing(reason: String) -> Dictionary:
	return {
		"ok": false, "reason": reason, "rows": [], "moved": 0,
		"cost_before_cents": 0, "cost_after_cents": 0,
		"price_before_cents": 0, "price_after_cents": 0,
		"currency": &"",
	}


## One estimate, costed against a map of item id -> new rate.
##
## A line whose item the plan does not touch keeps the **frozen** cost it was priced with, which is
## why the before figure is the estimate's own `direct_cost()` rather than a recomputation: an
## estimate's cost is what it was costed at, and this preview is about the difference a change would
## make to it.
static func row_for(estimate: Estimate, prices: Dictionary) -> Dictionary:
	var after: int = 0
	var touched: int = 0
	for line: EstimateLine in estimate.lines:
		var rate: Money = line.unit_cost
		var held: Variant = prices.get(line.cost_item, null)
		if held is Money:
			rate = held
			touched += 1
		after += int(MoneyScript.round_div(
			rate.cents * line.quantity_with_waste(), 1000, rate.currency
		).cents)
	var before: int = int(estimate.direct_cost().cents)
	var price: int = int(estimate.price_before_tax().cents)
	var heading: String = estimate.number if not estimate.number.is_empty() else estimate.id
	var client: String = String(estimate.customer.get("name", ""))
	return {
		"number": heading,
		"client": client,
		"lines_touched": touched,
		"cost_before_cents": before,
		"cost_after_cents": after,
		"delta_cents": after - before,
		"price_cents": price,
		"margin_before_ppm": margin_ppm(price, before),
		"margin_after_ppm": margin_ppm(price, after),
		"currency": String(estimate.currency),
	}


## Gross margin in parts per million, by the estimate's own rule (§4.9): what is left of the price
## before tax after what the work costs, computed in integers.
static func margin_ppm(price_cents: int, cost_cents: int) -> int:
	if price_cents == 0:
		return 0
	return MoneyScript.rounded_div((price_cents - cost_cents) * PPM, price_cents)


# --- what a person reads -----------------------------------------------------------------------


## The preview as a table of words, one line per estimate whose cost would move, and the totals.
func describe(change_plan: Dictionary) -> String:
	var result: Dictionary = preview(change_plan)
	if not bool(result["ok"]):
		return "this change could not be previewed: %s" % String(result["reason"])
	var out: PackedStringArray = PackedStringArray()
	out.append("%d estimate%s in hand, %d whose cost would move" % [
		estimates.size(), "" if estimates.size() == 1 else "s", int(result["moved"])
	])
	for row: Dictionary in result["rows"]:
		var delta: int = int(row["delta_cents"])
		if delta == 0:
			continue
		out.append("%s  cost %s -> %s (%s%s)  price %s unchanged  margin %.2f%% -> %.2f%%" % [
			String(row["number"]),
			MoneyScript.of(int(row["cost_before_cents"]), book.currency).format_with_currency(),
			MoneyScript.of(int(row["cost_after_cents"]), book.currency).format_with_currency(),
			"+" if delta > 0 else "-",
			MoneyScript.of(absi(delta), book.currency).format_with_currency(),
			MoneyScript.of(int(row["price_cents"]), book.currency).format_with_currency(),
			float(int(row["margin_before_ppm"])) / 10000.0,
			float(int(row["margin_after_ppm"])) / 10000.0,
		])
	out.append("cost %s -> %s across all of them" % [
		MoneyScript.of(int(result["cost_before_cents"]), book.currency).format_with_currency(),
		MoneyScript.of(int(result["cost_after_cents"]), book.currency).format_with_currency(),
	])
	return "\n".join(out)


# --- where the estimates come from -------------------------------------------------------------


## Every estimate in the store, read as estimates. A record that will not read is left out and
## named by `store.problems()` rather than half-handed to a preview.
##
## Estimates are filed a job at a time (§11.1), so this walks the jobs and then each job's
## estimates.
static func read_estimates(store: BizStore) -> Array[Estimate]:
	var out: Array[Estimate] = []
	if store == null:
		return out
	for job: Dictionary in store.records(BizStore.JOB_KIND):
		var job_id: String = String(job.get("id", ""))
		for record: Dictionary in store.records("estimate", job_id):
			var body: Variant = record.get("body", {})
			if not (body is Dictionary):
				continue
			var held: Dictionary = body
			if held.is_empty():
				continue
			out.append(Estimate.from_dict(held))
	return out