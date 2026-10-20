class_name EstimateLine
extends RefCounted
## One priced row of an estimate.
##
## A line carries **its own prices**, frozen: the unit cost and the unit price it was priced with, and
## the version of the cost book they came from (§2.2, REQ-B6). A cost book changes - bark mulch is $48
## this spring and $54 next - and a proposal that quoted $48 must still cost $48 when it is opened in
## two years, or a report about it disagrees with the paper the customer signed. A quoted number is a
## promise.
##
## Everything here is exact integers: a quantity in thousandths of a unit, money in minor units, waste
## and markups in parts per million. There is no float in a price, and the one rounding happens in
## `extension()`.

const MoneyScript := preload("res://scripts/biz/money.gd")
const WorkUnitScript := preload("res://scripts/biz/work_unit.gd")
const ItemScript := preload("res://scripts/biz/cost_item.gd")

## How much waste an item may carry, in parts per million. The same bound the cost item uses, refused
## in the same way: a line carrying 300% of waste would quietly inflate every takeoff priced from it.
const MAX_WASTE_PPM := ItemScript.MAX_WASTE_PPM

## The markup an estimate may apply to its direct cost, as a signed bound: +/-500%.
const MAX_MARKUP_PPM := 5000000

## A uuid, for a line that has to survive being re-ordered or merged.
##
## Built from a hash rather than from `Crypto`, which this module has no other use for: it is an
## **identity**, not a token. Uniqueness within a run comes from the counter, unpredictability across
## files from the clock, and if two machines ever disagree it is because a person merged two estimates,
## which is the case the uuid is there to survive. The version and variant bits are set so it is a
## well-formed v4 if anything downstream ever validates the shape.
static var _serial: int = 0

static func new_id() -> String:
	_serial += 1
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	var seed_text: String = "%d|%d|%s" % [
		Time.get_ticks_usec(), _serial, Time.get_datetime_string_from_system(true, true)
	]
	context.update(seed_text.to_utf8_buffer())
	var digest: PackedByteArray = context.finish()
	var bytes: PackedByteArray = digest.slice(0, 16)
	bytes[6] = (bytes[6] & 0x0f) | 0x40        # version 4
	bytes[8] = (bytes[8] & 0x3f) | 0x80        # variant 1
	var hex: String = bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)
	]


var id: String = ""
## Where it came from: a cost book item, or a kit that expanded into it.
var cost_item: StringName = &""
var description: String = ""
## Thousandths of `unit`. Waste is applied to this quantity, never to the price (§5.1).
var quantity_milli: int = 0
var unit: StringName = &"EACH"
## The phase it costs to.
var cost_code: StringName = &""
## What kind of thing it is - material, labour, equipment, subcontract, fee, other.
##
## On the line rather than read from the item at roll-up time, because a book is edited: an item
## reclassified from material to fee next spring would silently re-mean an estimate that was priced
## and sent last autumn, which is the whole class of change `unit_cost` and `book_version` exist to
## prevent.
var kind: int = ItemScript.MATERIAL
## **Frozen**: what the business pays per unit, at `book_version`.
var unit_cost: Money = null
## **Frozen**: what the customer is charged per unit.
var unit_price: Money = null
## Waste applied to the quantity of material lines only.
var waste_ppm: int = 0
var tax_code: StringName = &""
## The drawing lineage: `{entities, measure, value}`, or empty for a number somebody typed (§2.4).
var takeoff: Dictionary = {}
## The cost book version these prices came from (REQ-B6).
var book_version: int = 1
var note: String = ""


func _init(line_id: String = "") -> void:
	id = line_id if not line_id.is_empty() else new_id()
	unit_cost = MoneyScript.zero()
	unit_price = MoneyScript.zero()


## The ordinary way to make one, from a cost item and a quantity.
static func make(
	item: CostItem,
	quantity_milli: int,
	line_unit: StringName = &"",
	price: Money = null,
	line_id: String = ""
) -> EstimateLine:
	var line: EstimateLine = (load("res://scripts/biz/estimate_line.gd") as GDScript).new(line_id)
	line.cost_item = item.id
	line.description = item.name
	line.quantity_milli = quantity_milli
	line.unit = item.unit if line_unit.is_empty() else line_unit
	line.cost_code = item.cost_code
	line.kind = item.kind
	line.unit_cost = item.rate.copy()
	line.unit_price = item.rate.copy() if price == null else price.copy()
	line.waste_ppm = item.waste_ppm
	line.tax_code = item.tax_code
	return line


# --- the arithmetic ---------------------------------------------------------------------


## Whether waste inflates this line's quantity. Material only: labour is not wasted, and a fee is not
## either. A rate per square metre of finished paving is a **selling** rate, so it already contains the
## installer's own waste (§5.1).
func is_material() -> bool:
	return kind == ItemScript.MATERIAL


## The quantity after waste, in thousandths.
##
## Rounded by the module's one rule - half away from zero - rather than truncated. The specification
## writes this as an integer division, which truncates; the difference is at most a thousandth of a
## unit, and rounding is the rule every other quantity in this module follows, including a credit
## reversing the charge it reverses.
func quantity_with_waste() -> int:
	if not is_material() or waste_ppm == 0:
		return quantity_milli
	return MoneyScript.rounded_div(
		quantity_milli * (1000000 + waste_ppm), 1000000
	)


## What the work costs, in minor units: the waste-inflated quantity at the frozen unit cost.
func cost() -> Money:
	return MoneyScript.round_div(
		unit_cost.cents * quantity_with_waste(), 1000, unit_cost.currency
	)


## The line's extended price, in minor units (§5.1).
##
## The order is: waste inflates the quantity for material lines, the quantity is multiplied by the
## frozen unit price in exact integers, and the **single** rounding happens here - half away from zero,
## so a credit reverses the charge it reverses to the cent.
func extension() -> Money:
	return MoneyScript.round_div(
		unit_price.cents * quantity_with_waste(), 1000, unit_price.currency
	)


## The quantity in some other unit of the same dimension, or a refusal naming both.
##
## This is what lets a cost book priced in square feet price a plan drawn in metres: the conversion is
## an exact ratio of integers (§6), not the rounded constant a supplier's spreadsheet carries.
func quantity_in(target_unit: StringName) -> Dictionary:
	if target_unit == unit:
		return {"ok": true, "quantity_milli": quantity_with_waste(), "reason": ""}
	var converted: Dictionary = WorkUnitScript.convert(quantity_with_waste(), unit, target_unit)
	return converted


# --- what is wrong with it ----------------------------------------------------------------


## What is wrong with this line, in a sentence, or "" when nothing is.
##
## `exempt` is the customer's tax status, because a line with no tax code is a different problem on an
## exempt customer than on a taxable one (§5.4).
func problem(exempt: bool = false) -> String:
	if id.is_empty():
		return "an estimate line needs an id"
	if description.strip_edges().is_empty():
		return "an estimate line needs a description"
	if not WorkUnitScript.has(unit):
		return "estimate line %s is priced in \"%s\", which is not a unit" % [id, String(unit)]
	if quantity_milli <= 0:
		return "estimate line %s has a quantity of %d, which is not a quantity" % [id, quantity_milli]
	if unit_cost == null or not unit_cost.is_valid():
		return "estimate line %s has no readable unit cost" % id
	if unit_price == null or not unit_price.is_valid():
		return "estimate line %s has no readable unit price" % id
	if unit_cost.currency != unit_price.currency:
		return "estimate line %s costs in %s and prices in %s" % [
			id, String(unit_cost.currency), String(unit_price.currency)
		]
	if waste_ppm < 0 or waste_ppm > MAX_WASTE_PPM:
		return "estimate line %s carries %d ppm of waste, which is outside 0..%d" % [
			id, waste_ppm, MAX_WASTE_PPM
		]
	if not ItemScript.KINDS.has(kind):
		return "estimate line %s has kind %d, which is not a kind of thing" % [id, kind]
	# REQ-B9, AC-B10: a unit's dimension is checked against the measurement's dimension. `measure` is
	# *what was measured* - "area", "linear", "count" (§2.4) - which is a dimension and not a unit, so
	# the question is whether the unit's dimension is the one that was measured. Asking instead whether
	# the measure is a *unit* would skip the check silently for every real lineage.
	if not takeoff.is_empty():
		var measured: StringName = StringName(takeoff.get("measure", ""))
		if not measured.is_empty() and measured != WorkUnitScript.dimension(unit):
			return "estimate line %s was measured in %s and is priced in %s" % [
				id, String(measured), WorkUnitScript.name_of(unit)
			]
	# A **missing** code is refused, and a zero-rated one is not: `NONE` and `EXEMPT` are real codes
	# that charge nothing, which is the distinction the tax table already makes ("exempt is a zero
	# charge and not a missing one"). Conflating them would refuse a legitimately untaxed permit line
	# on a taxable customer, which is a real thing a landscape business sells.
	if not exempt and tax_code.is_empty():
		return "estimate line %s has no tax code, and the customer is not exempt" % id
	return ""


func is_valid(exempt: bool = false) -> bool:
	return problem(exempt).is_empty()


## REQ-B12: a quantity with no lineage is a number somebody typed, and is marked as such.
func by_hand() -> bool:
	return takeoff.is_empty()


## The lineage, or empty when there is none.
func lineage() -> Dictionary:
	return takeoff.duplicate(true)


## How the line reads on a proposal: "48.00 m²  Paving, interlock @ $42.00 = $2,016.00".
func line_text() -> String:
	var quantity: String = "%.3f" % (float(quantity_milli) / 1000.0)
	# A line that orders waste says so on itself, **after** the unit so that the measured quantity and
	# its unit still read as one phrase. Without it the printed line does not multiply: a reader takes
	# the quantity times the rate, gets less than the extension beside it, and has no way from the page
	# to learn that the difference is the material ordered to cover the cuts. The quantity printed stays
	# the quantity the drawing **measured** - the takeoff's own number - and the waste is named rather
	# than folded into it, because a figure that quietly grew between the plan and the proposal is the
	# kind of thing nobody can check.
	var waste: String = ""
	if is_material() and waste_ppm > 0:
		waste = " +%.1f%% waste" % (float(waste_ppm) / 10000.0)
	return "%s %s%s  %s @ %s = %s" % [
		quantity, WorkUnitScript.name_of(unit), waste, description,
		unit_price.format_with_currency(), extension().format_with_currency(),
	]


func copy() -> EstimateLine:
	return from_dict(to_dict())


func to_dict() -> Dictionary:
	return {
		"id": id,
		"cost_item": String(cost_item),
		"description": description,
		"quantity_milli": quantity_milli,
		"unit": String(unit),
		"cost_code": String(cost_code),
		"kind": kind,
		"unit_cost": unit_cost.to_dict(),
		"unit_price": unit_price.to_dict(),
		"waste_ppm": waste_ppm,
		"tax_code": String(tax_code),
		"takeoff": takeoff.duplicate(true),
		"book_version": book_version,
		"note": note,
	}


## Read one back. Numbers come out of JSON as floats, so every integer field is coerced (§2.1a).
static func from_dict(data: Dictionary) -> EstimateLine:
	var line: EstimateLine = (load("res://scripts/biz/estimate_line.gd") as GDScript).new(
		String(data.get("id", ""))
	)
	line.cost_item = StringName(data.get("cost_item", ""))
	line.description = String(data.get("description", ""))
	line.quantity_milli = int(data.get("quantity_milli", 0))
	line.unit = StringName(data.get("unit", "EACH"))
	line.cost_code = StringName(data.get("cost_code", ""))
	line.kind = int(data.get("kind", ItemScript.MATERIAL))
	var cost_data: Variant = data.get("unit_cost", null)
	line.unit_cost = MoneyScript.from_dict(cost_data) if cost_data is Dictionary \
		else MoneyScript.invalid()
	var price_data: Variant = data.get("unit_price", null)
	line.unit_price = MoneyScript.from_dict(price_data) if price_data is Dictionary \
		else MoneyScript.invalid()
	line.waste_ppm = int(data.get("waste_ppm", 0))
	line.tax_code = StringName(data.get("tax_code", ""))
	var lineage: Variant = data.get("takeoff", {})
	line.takeoff = (lineage as Dictionary).duplicate(true) if lineage is Dictionary else {}
	line.book_version = int(data.get("book_version", 1))
	line.note = String(data.get("note", ""))
	return line