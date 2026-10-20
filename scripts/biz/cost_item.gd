class_name CostItem
extends RefCounted
## One priced thing a business buys: a material, an hour of labour, a load, a subcontract.
##
## `rate` is the **cost** per unit, never the selling price. A cost book is what the business pays;
## the price a customer sees is a policy applied to that cost (a markup, and the line's own
## override), and the two are kept apart on purpose - a margin can change without rewriting the
## book, and a price list that went out to a customer can never be mistaken for what the work
## cost (REQ-B6).

const MoneyScript := preload("res://scripts/biz/money.gd")
const WorkUnitScript := preload("res://scripts/biz/work_unit.gd")

## What kind of thing this is. It is data rather than a note because a string of kinds is what
## "labour is 40% of that estimate" is computed from (§10).
const MATERIAL := 0
const LABOR := 1
const EQUIPMENT := 2
const SUBCONTRACT := 3
const FEE := 4
const OTHER := 5

const KINDS := {
	MATERIAL: "Material",
	LABOR: "Labour",
	EQUIPMENT: "Equipment",
	SUBCONTRACT: "Subcontract",
	FEE: "Fee",
	OTHER: "Other",
}

## The most waste an item may carry, in parts per million: 50%. Bulk mulch at 8% (80000) is a
## business decision; 300% is a data error, and it would quietly inflate every takeoff priced from
## the item - so it is refused rather than stored.
const MAX_WASTE_PPM := 500000

var id: StringName = &""
var name: String = ""
var kind: int = MATERIAL
var unit: StringName = &"EACH"
## What the business pays for one `unit`.
var rate: Money = null
## Waste, in parts per million: 80000 is 8% more material bought than the drawing measures.
var waste_ppm: int = 0
## The phase this item normally costs to, so an expanded kit still costs to the right place.
var cost_code: StringName = &""
## The tax code a line made from this item gets, and **empty by default**: an item that says nothing
## about tax leaves an estimate line with an empty code, which the estimate then fills in from its own
## default (§4.9: "the usual tax, overridable per line").
##
## This is `""` rather than `"NONE"` on purpose. `NONE` is a real code that charges nothing, so an item
## defaulting to it meant every line in an estimate came out zero-rated whatever jurisdiction the
## business was in - the estimate's own HST was never applied, and a proposal for a $4,284 patio went
## out untaxed without anything saying so. Empty means "this item has no opinion"; `NONE` means "this
## item is zero-rated", and an item that is genuinely zero-rated says so.
var tax_code: StringName = &""
## Who it is bought from, for grouping a purchase order.
var supplier: StringName = &""
var note: String = ""


func _init(item_id: StringName = &"", item_name: String = "", item_unit: StringName = &"EACH") -> void:
	id = item_id
	name = item_name
	unit = item_unit
	rate = MoneyScript.zero()


## The ordinary way to make one: everything that has no sensible default, in one line.
##
## `currency` is the last parameter and is the **money's** currency, not the item's cost code. The two
## are easy to confuse - this parameter was called `code` until a takeoff passed a cost code into it and
## every item in a starter book came out priced in "HARDSCAPE" - and `cost_code` is deliberately left
## for the caller to set, because which phase a thing costs to is a business decision and not something
## this function can guess.
static func make(
	item_id: StringName,
	item_name: String,
	item_unit: StringName,
	rate_cents: int,
	item_kind: int = MATERIAL,
	currency: StringName = &"CAD"
) -> CostItem:
	var item: CostItem = (load("res://scripts/biz/cost_item.gd") as GDScript).new(
		item_id, item_name, item_unit
	)
	item.kind = item_kind
	item.rate = MoneyScript.of(rate_cents, currency)
	return item


## What is wrong with this item, in a sentence, or "" when nothing is.
##
## Refuse and name it, as the rest of this project does: an item priced in a unit that does not
## exist, or carrying an unreadable rate, is not a cheap item - it is a line that would price
## something at nothing.
func problem() -> String:
	if id.is_empty():
		return "a cost item needs an id"
	if name.strip_edges().is_empty():
		return "cost item %s has no name" % id
	if not KINDS.has(kind):
		return "cost item %s has kind %d, which is not a kind of thing" % [id, kind]
	if not WorkUnitScript.has(unit):
		return "cost item %s is priced in \"%s\", which is not a unit" % [id, unit]
	if rate == null or not rate.is_valid():
		return "cost item %s has no readable rate" % id
	if waste_ppm < 0 or waste_ppm > MAX_WASTE_PPM:
		return "cost item %s carries %d ppm of waste, which is outside 0..%d" % [
			id, waste_ppm, MAX_WASTE_PPM
		]
	return ""


func is_valid() -> bool:
	return problem().is_empty()


## The rate and its unit, for a price list: "$42.00 / yd³".
func rate_text() -> String:
	return "%s / %s" % [rate.format_with_currency(), WorkUnitScript.name_of(unit)]


func describe() -> String:
	var kind_name: String = String(KINDS.get(kind, "?"))
	return "%s - %s, %s" % [name, kind_name, rate_text()]


## An independent copy. A book's prices are edited by replacing items, not by reaching into a
## stored estimate's item, so nothing shares a Money instance by accident.
func copy() -> CostItem:
	return from_dict(to_dict())


func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"name": name,
		"kind": kind,
		"unit": String(unit),
		"rate": rate.to_dict(),
		"waste_ppm": waste_ppm,
		"cost_code": String(cost_code),
		"tax_code": String(tax_code),
		"supplier": String(supplier),
		"note": note,
	}


## Read one back. Numbers come out of JSON as floats - Godot's parser has one number type - so
## every integer field is coerced rather than trusted (§2.1a, §15.1).
static func from_dict(data: Dictionary) -> CostItem:
	var item: CostItem = (load("res://scripts/biz/cost_item.gd") as GDScript).new()
	item.id = StringName(data.get("id", ""))
	item.name = String(data.get("name", ""))
	item.kind = int(data.get("kind", MATERIAL))
	item.unit = StringName(data.get("unit", "EACH"))
	var rate_data: Variant = data.get("rate", null)
	if rate_data is Dictionary:
		item.rate = MoneyScript.from_dict(rate_data)
	else:
		item.rate = MoneyScript.invalid()
	item.waste_ppm = int(data.get("waste_ppm", 0))
	item.cost_code = StringName(data.get("cost_code", ""))
	item.tax_code = StringName(data.get("tax_code", ""))
	item.supplier = StringName(data.get("supplier", ""))
	item.note = String(data.get("note", ""))
	return item