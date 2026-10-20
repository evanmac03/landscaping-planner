class_name CostKit
extends RefCounted
## A recipe: the priced lines that make one unit of output, so that a patio is priced once and
## used in fifty estimates.
##
## A kit is priced **per unit of output** - a 45 m² patio is `45 x kit` - so its lines are
## quantities per `yield_milli` of `output_unit`, and everything scales from that. The alternative,
## pricing a fixed 45 m² recipe, means every estimate re-prices the same work by hand.
##
## A kit's line may name an item **or another kit**: a patio kit that needs a compacted-base kit
## says so, and which of the two it is is the book's business, not the kit's (§4.5).

const MoneyScript := preload("res://scripts/biz/money.gd")
const WorkUnitScript := preload("res://scripts/biz/work_unit.gd")

## One unit of output, in thousandths - the resolution a quantity is stored at.
const DEFAULT_YIELD_MILLI := 1000

var id: StringName = &""
var name: String = ""
## `{item_id, quantity_milli, note}`, per `yield_milli` of output.
##
## A plain Array, not `Array[Dictionary]`: this has to survive a round trip through JSON, and
## Godot's parser hands back plain arrays however the field was typed on the way out.
var lines: Array = []
## What the kit is priced per. A kit's output unit is also what a takeoff's dimension is checked
## against, which is what stops a paving area being priced as hours.
var output_unit: StringName = &"SQ_M"
## How much output one run of this recipe makes, in thousandths.
var yield_milli: int = DEFAULT_YIELD_MILLI
## A reporting figure, not arithmetic: what the recipe assumes it takes, in thousandths of an hour.
var labour_hours_milli: int = 0


func _init(kit_id: StringName = &"", kit_name: String = "", unit: StringName = &"SQ_M") -> void:
	id = kit_id
	name = kit_name
	output_unit = unit


static func make(kit_id: StringName, kit_name: String, unit: StringName = &"SQ_M") -> CostKit:
	return (load("res://scripts/biz/cost_kit.gd") as GDScript).new(kit_id, kit_name, unit)


## Put one line into the recipe. A quantity of zero is not a small line, it is a mistake: it would
## vanish from the estimate while still looking like work that was priced.
func add_line(item_id: StringName, quantity_milli: int, note: String = "") -> bool:
	if item_id.is_empty() or quantity_milli <= 0:
		return false
	lines.append({"item_id": String(item_id), "quantity_milli": quantity_milli, "note": note})
	return true


## A line of the recipe as read, with its id back as a StringName.
func line_at(index: int) -> Dictionary:
	if index < 0 or index >= lines.size():
		return {}
	var raw: Variant = lines[index]
	if not (raw is Dictionary):
		return {}
	var line: Dictionary = raw
	return {
		"item_id": StringName(line.get("item_id", "")),
		"quantity_milli": int(line.get("quantity_milli", 0)),
		"note": String(line.get("note", "")),
	}


## The quantity of one recipe line needed to make `made_milli` units of output, rounded half away
## from zero.
##
## The rounding rule is `Money.rounded_div`, borrowed rather than restated: a quantity and an amount
## that rounded differently would be two rules to keep in step, and this module only has one.
static func scaled_quantity(line_quantity_milli: int, made_milli: int, per_run_milli: int) -> int:
	if per_run_milli <= 0 or made_milli <= 0:
		return 0
	return MoneyScript.rounded_div(line_quantity_milli * made_milli, per_run_milli)


func problem() -> String:
	if id.is_empty():
		return "a cost kit needs an id"
	if name.strip_edges().is_empty():
		return "cost kit %s has no name" % id
	if not WorkUnitScript.has(output_unit):
		return "cost kit %s produces \"%s\", which is not a unit" % [id, output_unit]
	if yield_milli <= 0:
		return "cost kit %s has a yield of %d, so what one run makes is nothing" % [id, yield_milli]
	if labour_hours_milli < 0:
		return "cost kit %s has negative labour hours" % id
	for index in lines.size():
		var line: Dictionary = line_at(index)
		if StringName(line.get("item_id", &"")).is_empty():
			return "cost kit %s has a line with no item on it" % id
		if int(line.get("quantity_milli", 0)) <= 0:
			return "cost kit %s, line %d: a quantity of %d is not a quantity" % [
				id, index + 1, int(line.get("quantity_milli", 0))
			]
	return ""


func is_valid() -> bool:
	return problem().is_empty()


func describe() -> String:
	return "%s - %d line%s per %s" % [
		name, lines.size(), "" if lines.size() == 1 else "s",
		WorkUnitScript.name_of(output_unit),
	]


func copy() -> CostKit:
	return from_dict(to_dict())


func to_dict() -> Dictionary:
	var out_lines: Array = []
	for index in lines.size():
		var line: Dictionary = line_at(index)
		out_lines.append({
			"item_id": String(line["item_id"]),
			"quantity_milli": int(line["quantity_milli"]),
			"note": String(line["note"]),
		})
	return {
		"id": String(id),
		"name": name,
		"lines": out_lines,
		"output_unit": String(output_unit),
		"yield_milli": yield_milli,
		"labour_hours_milli": labour_hours_milli,
	}


static func from_dict(data: Dictionary) -> CostKit:
	var kit: CostKit = (load("res://scripts/biz/cost_kit.gd") as GDScript).new()
	kit.id = StringName(data.get("id", ""))
	kit.name = String(data.get("name", ""))
	kit.output_unit = StringName(data.get("output_unit", "SQ_M"))
	kit.yield_milli = int(data.get("yield_milli", DEFAULT_YIELD_MILLI))
	kit.labour_hours_milli = int(data.get("labour_hours_milli", 0))
	var raw_lines: Variant = data.get("lines", [])
	if raw_lines is Array:
		for raw: Variant in raw_lines:
			if raw is Dictionary:
				var line: Dictionary = raw
				kit.lines.append({
					"item_id": String(line.get("item_id", "")),
					"quantity_milli": int(line.get("quantity_milli", 0)),
					"note": String(line.get("note", "")),
				})
	return kit