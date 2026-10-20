class_name WorkUnit
extends RefCounted
## The units a cost book prices in, and the dimension each one measures.
##
## A dimension is what makes a takeoff checkable instead of hopeful: a paving area measured in m²
## may only price a line priced per m², and a rate per hour applied to an area is not a typo a
## program should accept (REQ-B9).
##
## Conversions are **exact ratios of integers**, not the rounded decimals a price list prints:
## 1 ft is exactly 0.3048 m, so a square foot is exactly (381/1250)² of a square metre rather than
## the 0.092903 a supplier's spreadsheet carries. Each conversion rounds at most once per unit hop,
## to the nearest thousandth of a unit - the resolution a quantity is stored at - which is three
## orders of magnitude finer than the rounding of a line.

const MoneyScript := preload("res://scripts/biz/money.gd")

const LINEAR := &"linear"
const AREA := &"area"
const VOLUME := &"volume"
const TIME := &"time"
const COUNT := &"count"

const UNITS := {
	&"EACH": {"name": "each", "dimension": COUNT},
	&"SQ_M": {"name": "m²", "dimension": AREA},
	&"SQ_FT": {"name": "ft²", "dimension": AREA},
	&"LIN_M": {"name": "m", "dimension": LINEAR},
	&"LIN_FT": {"name": "ft", "dimension": LINEAR},
	&"CU_M": {"name": "m³", "dimension": VOLUME},
	&"CU_YD": {"name": "yd³", "dimension": VOLUME},
	&"HOUR": {"name": "hour", "dimension": TIME},
	&"DAY": {"name": "day", "dimension": TIME},
	&"LOAD": {"name": "load", "dimension": COUNT},
}

## Each unit as an exact ratio to its dimension's canonical unit - metres, square metres, cubic
## metres, hours, items - in lowest terms, so the products in `convert` cannot overflow a 64-bit
## int at any quantity a garden can hold.
const RATIOS := {
	&"LIN_M": [1, 1],
	&"LIN_FT": [381, 1250],                # 0.3048 m exactly
	&"SQ_M": [1, 1],
	&"SQ_FT": [145161, 1562500],           # (381/1250)², the square of the exact ratio
	&"CU_M": [1, 1],
	&"CU_YD": [1493271207, 1953125000],    # 0.9144³ m³
	&"EACH": [1, 1],
	&"LOAD": [1, 1],
	&"HOUR": [1, 1],
	&"DAY": [24, 1],
}


static func has(id: StringName) -> bool:
	return UNITS.has(id)


static func dimension(id: StringName) -> StringName:
	var entry: Dictionary = UNITS.get(id, {})
	return StringName(entry.get("dimension", &""))


static func name_of(id: StringName) -> String:
	var entry: Dictionary = UNITS.get(id, {})
	return String(entry.get("name", String(id)))


static func describe(id: StringName) -> String:
	if not has(id):
		return "unknown work unit '%s'" % String(id)
	return "%s (%s)" % [name_of(id), String(dimension(id))]


static func same_dimension(first: StringName, second: StringName) -> bool:
	if not has(first) or not has(second):
		return false
	return dimension(first) == dimension(second)


## Convert a quantity in thousandths of its unit.
##
## Refuses across dimensions and refuses a unit it does not know, naming which - rather than
## returning the number unconverted, which would price a patio by its perimeter and look plausible
## in the total.
static func convert(quantity_milli: int, from_id: StringName, to_id: StringName) -> Dictionary:
	if not has(from_id):
		return {"ok": false, "quantity_milli": 0, "reason": "unknown work unit '%s'" % String(from_id)}
	if not has(to_id):
		return {"ok": false, "quantity_milli": 0, "reason": "unknown work unit '%s'" % String(to_id)}
	if dimension(from_id) != dimension(to_id):
		return {
			"ok": false,
			"quantity_milli": 0,
			"reason": "%s measures %s, and %s measures %s" % [
				name_of(from_id), String(dimension(from_id)),
				name_of(to_id), String(dimension(to_id)),
			],
		}
	var from_ratio: Array = RATIOS[from_id]
	var to_ratio: Array = RATIOS[to_id]
	var canonical: int = MoneyScript.rounded_div(
		quantity_milli * int(from_ratio[0]), int(from_ratio[1])
	)
	var converted: int = MoneyScript.rounded_div(
		canonical * int(to_ratio[1]), int(to_ratio[0])
	)
	return {"ok": true, "quantity_milli": converted, "reason": ""}


## The unit a measurement of a given dimension should be priced in, for a document drawn in
## metric or in imperial. This is what makes a takeoff offer the right column.
static func preferred(dimension_id: StringName, metric: bool = true) -> StringName:
	match dimension_id:
		LINEAR:
			return &"LIN_M" if metric else &"LIN_FT"
		AREA:
			return &"SQ_M" if metric else &"SQ_FT"
		VOLUME:
			return &"CU_M" if metric else &"CU_YD"
		TIME:
			return &"HOUR"
		COUNT:
			return &"EACH"
	return &""