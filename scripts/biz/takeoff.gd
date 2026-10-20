class_name Takeoff
extends RefCounted
## The drawing, measured: the bridge between the design module and the business module (§2.4, §6).
##
## ```
## pick geometry on a layer  →  measure by kind  →  cost code and a priced item  →  a line with lineage
## ```
##
## This is the feature the whole business module exists for. Pricing a planting bed is
## `area_m2 x rate`, and the quantity has a lineage back to the geometry that produced it, so a
## revised plan can be re-priced and **diffed** against the old estimate: "the bed grew 4.2 m², that
## is $310".
##
## Three rules decide everything here, and each of them is a decision this project already made:
##
## 1. **A takeoff measures; it never prices.** Every quantity in this file is a measurement in
##    thousandths of a unit. Money appears when `priced_line()` hands a line to an `EstimateLine`,
##    where it is frozen and rounded exactly once.
## 2. **A quantity keeps its dimension.** A paving area measured in m² may only be priced by an item
##    priced per m² (REQ-B9), and the conversion to a book's own unit is an exact ratio of integers,
##    not a rounded constant (§6).
## 3. **A line with no price is refused and named, not left at zero.** The same rule the cost book,
##    the tax table and the plant catalogue already follow, and the one that stops an estimate being
##    quietly short.

const MoneyScript := preload("res://scripts/biz/money.gd")
const WorkUnitScript := preload("res://scripts/biz/work_unit.gd")
const ItemScript := preload("res://scripts/biz/cost_item.gd")
const LineScript := preload("res://scripts/biz/estimate_line.gd")
const BookScript := preload("res://scripts/biz/cost_book.gd")

## The thousandths a measurement is stored in, so a takeoff has no float in it either. A metre is
## 1000; an area is measured in whole thousandths of a square metre, which is a square millimetre.
const SCALE := 1000

## Which layers are worth money, and how each one is measured.
##
## A takeoff is **the schedule of the work**, not the schedule of the drawing: property lines, survey
## annotations, existing paving and the sheet furniture are all on plotting layers and none of them is
## something a business buys. So the table below is an allow-list, and a layer that is not in it is
## reported in `notes` rather than silently dropped - the person reading the takeoff should be able to
## see what it decided not to measure and why.
##
## `measure` is a `WorkUnit` dimension, and it decides which of an entity's two measurements is the
## one that counts: a circle has both an area and a circumference, and which of them is a quantity of
## work is a property of the **layer**, not of the circle. A tree symbol's ring is not 12 m² of
## anything; a round patio on the hardscape layer is.
##
## `static var`, not `const`, for the reason the tax table is: a `const` Dictionary is read-only to
## its contents as well, and a practice's own layer set has to be addable at run time.
##
## `item` is the item the layer **suggests**, and it is here rather than inferred so that a suggestion
## is a decision somebody made. Without it the suggestion would be whichever matching item the book
## happened to list first, which is how a paving layer comes to suggest precast slabs.
static var LAYER_MEASURES: Dictionary = {
	&"300-NEW-HARD": {
		"measure": WorkUnitScript.AREA, "cost_code": &"HARDSCAPE",
		"item": &"hard-paving-interlock",
	},
	&"301-NEW-STRUCT": {
		"measure": WorkUnitScript.AREA, "cost_code": &"STRUCTURE",
		"item": &"struct-deck-composite",
	},
	&"400-NEW-BED": {
		"measure": WorkUnitScript.AREA, "cost_code": &"BEDS",
		"item": &"bed-soil-amend",
	},
	&"401-NEW-PLANT": {
		"measure": WorkUnitScript.COUNT, "cost_code": &"PLANTING",
		"item": &"plant-shrub-2g",
	},
	&"402-NEW-TURF": {
		"measure": WorkUnitScript.AREA, "cost_code": &"TURF",
		"item": &"turf-sod",
	},
	&"500-IRRIGATION": {
		"measure": WorkUnitScript.COUNT, "cost_code": &"IRRIGATION",
		"item": &"irr-head-spray",
	},
	&"501-LIGHTING": {
		"measure": WorkUnitScript.COUNT, "cost_code": &"LIGHTING",
		"item": &"light-path-fixture",
	},
}

## Layers that are deliberately not measured, with the reason, so "why is nothing on my drawing in the
## takeoff" has an answer that is not "silence".
const NOT_MEASURED := {
	&"000-PROPERTY": "property lines are not work",
	&"011-SURVEY-ANNO": "a survey note is not work",
	&"020-SETBACK-EASE": "a setback is not work",
	&"100-EXIST-STRUCT": "existing building, not new work",
	&"101-EXIST-HARD": "existing paving, not new work",
	&"110-EXIST-PLANT": "existing planting, not new work",
	&"200-GRADE-CONT": "grading is measured as volume, which this takeoff does not do",
	&"201-GRADE-SPOT": "a spot elevation is not a quantity",
	&"600-HATCH": "a hatch is a pattern over work that is measured on its own layer",
	&"700-DIMENSION": "an annotation, and it has a length that must not be billed",
	&"710-TEXT": "an annotation",
	&"720-CALLOUT": "an annotation",
	&"900-SHEET-BORDER": "sheet furniture",
	&"901-SHEET-VPORT": "sheet furniture",
	&"950-UNDERLAY": "a tracing aid",
	&"960-GUIDES": "a tracing aid",
}


## One measured quantity, and where it was measured from.
##
## `entity_ids` is the lineage REQ-B12 requires. Empty means the quantity was **typed by hand**, which
## is allowed and is marked rather than hidden: a number somebody typed is not the same kind of fact
## as a number the drawing produced, and an estimate that confused the two would be a quote that
## cannot be checked against the plan.
class TakeoffLine extends RefCounted:
	## "entity:<id>" for geometry, "plant:<species>" for a planting count. A stable key, which is what
	## makes re-takeoff a diff rather than a comparison by eye.
	var source: StringName = &""
	var entity_ids: PackedInt32Array = PackedInt32Array()
	var layer: StringName = &""
	## The measurement's dimension: `WorkUnit.AREA`, `LINEAR`, `COUNT`.
	var measure: StringName = &""
	## The unit the measurement is stated in, in the drawing's own system.
	var unit: StringName = &"EACH"
	var quantity_milli: int = 0
	## The measurement in its own unit's base - m², m, items - kept as it was read off the drawing, so
	## the record says what the geometry measured and not only what was priced.
	var value: float = 0.0
	var description: String = ""
	var cost_code: StringName = &""
	## The item that prices it, once the office has chosen one, or the one the layer suggested.
	var item_id: StringName = &""
	var note: String = ""

	func by_hand() -> bool:
		return entity_ids.is_empty() and String(source).is_empty()

	## The `takeoff` dictionary an `EstimateLine` carries (§4.8), or empty when there is no lineage.
	func lineage() -> Dictionary:
		if by_hand():
			return {}
		return {
			"entities": entity_ids,
			"measure": String(measure),
			"value": value,
		}

	func quantity_text() -> String:
		return "%.3f %s" % [float(quantity_milli) / float(SCALE), WorkUnitScript.name_of(unit)]

	func describe() -> String:
		# "1 entities" is the kind of thing a line that only ever went to a log file can get away
		# with; these lines are read by a person in the estimate panel, so they are written for one.
		var count: int = entity_ids.size()
		var where: String = "by hand"
		if count == 1:
			where = "1 entity"
		elif count > 1:
			where = "%d entities" % count
		return "%s  %s  (%s, %s)" % [quantity_text(), description, String(layer), where]

	func copy() -> TakeoffLine:
		var other: TakeoffLine = TakeoffLine.new()
		other.source = source
		other.entity_ids = entity_ids.duplicate()
		other.layer = layer
		other.measure = measure
		other.unit = unit
		other.quantity_milli = quantity_milli
		other.value = value
		other.description = description
		other.cost_code = cost_code
		other.item_id = item_id
		other.note = note
		return other

	func to_dict() -> Dictionary:
		var ids: Array = []
		for id: int in entity_ids:
			ids.append(id)
		return {
			"source": String(source),
			"entity_ids": ids,
			"layer": String(layer),
			"measure": String(measure),
			"unit": String(unit),
			"quantity_milli": quantity_milli,
			"value": value,
			"description": description,
			"cost_code": String(cost_code),
			"item_id": String(item_id),
			"note": note,
		}

	static func from_dict(data: Dictionary) -> TakeoffLine:
		var line: TakeoffLine = TakeoffLine.new()
		line.source = StringName(data.get("source", ""))
		var ids: Variant = data.get("entity_ids", [])
		if ids is Array:
			for id: Variant in ids:
				line.entity_ids.append(int(id))
		line.layer = StringName(data.get("layer", ""))
		line.measure = StringName(data.get("measure", ""))
		line.unit = StringName(data.get("unit", "EACH"))
		line.quantity_milli = int(data.get("quantity_milli", 0))
		line.value = float(data.get("value", 0.0))
		line.description = String(data.get("description", ""))
		line.cost_code = StringName(data.get("cost_code", ""))
		line.item_id = StringName(data.get("item_id", ""))
		line.note = String(data.get("note", ""))
		return line


var lines: Array[TakeoffLine] = []
## What was not measured, and why: "why is nothing on my drawing in the takeoff" has an answer.
var notes: Array[String] = []
## Everything wrong with the takeoff, in sentences: an unpriced line, a layer with no code.
var problems: Array[String] = []
## Which drawing was measured, so a line's numbers have a version to belong to.
var document_hash: String = ""
var document_count: int = 0
var layer_count: int = 0
var site: Dictionary = {}
var metric: bool = true
var book_version: int = 1
var book_source: String = ""


# --- measuring a drawing -------------------------------------------------------------------


## Measure every entity of a drawing that is worth money.
##
## `document` is a `DraftDocument`: this is the one file that reaches into the drafting module, because
## measuring a drawing is exactly what it is for, and it reaches through three methods only -
## `plotting_entities()`, `entity.area()`, `entity.length()` - so the coupling is one function wide.
static func of_document(document: DraftDocument, book: CostBook = null) -> Takeoff:
	var takeoff: Takeoff = (load("res://scripts/biz/takeoff.gd") as GDScript).new()
	if document == null:
		takeoff.problems.append("a takeoff needs a drawing")
		return takeoff
	takeoff.metric = document.units.system == DraftUnits.System.METRIC
	takeoff.document_hash = _hash_document(document)
	takeoff.document_count = document.count()
	takeoff.site = {"latitude": document.site_latitude, "longitude": document.site_longitude}
	if book != null:
		takeoff.book_version = book.version
		takeoff.book_source = book.source

	var buckets: Dictionary = {}
	var order: Array = []
	var unmeasured: Dictionary = {}
	for entity: DraftEntity in document.plotting_entities():
		var plan: Dictionary = measure_plan(entity.layer)
		if plan.is_empty():
			if not unmeasured.has(entity.layer):
				unmeasured[entity.layer] = 0
			unmeasured[entity.layer] = int(unmeasured[entity.layer]) + 1
			continue
		var found: Dictionary = _measure(entity, plan["measure"], takeoff.metric)
		if found.is_empty():
			continue
		var key: String = "%s|%s" % [String(entity.layer), String(found["measure"])]
		if not buckets.has(key):
			buckets[key] = {
				"layer": entity.layer,
				"measure": found["measure"],
				"unit": found["unit"],
				"quantity_milli": 0,
				"value": 0.0,
				"ids": PackedInt32Array(),
				"cost_code": plan["cost_code"],
			}
			order.append(key)
		var bucket: Dictionary = buckets[key]
		bucket["quantity_milli"] = int(bucket["quantity_milli"]) + int(found["quantity_milli"])
		bucket["value"] = float(bucket["value"]) + float(found["value"])
		var ids: PackedInt32Array = bucket["ids"]
		ids.append(entity.id)
		bucket["ids"] = ids

	for key: String in order:
		var bucket: Dictionary = buckets[key]
		var line: TakeoffLine = TakeoffLine.new()
		line.layer = bucket["layer"]
		line.measure = bucket["measure"]
		line.unit = bucket["unit"]
		line.quantity_milli = int(bucket["quantity_milli"])
		line.value = float(bucket["value"])
		line.entity_ids = bucket["ids"]
		line.cost_code = bucket["cost_code"]
		# The key a diff is computed on, and it must distinguish **what was measured** as well as
		# where: one layer can produce an area line and a length line (a paved patio and its edging),
		# and a key that named only the layer would make the second line overwrite the first - so a
		# re-takeoff would report a growth in the paving that was really a change to the edging.
		line.source = StringName("layer:%s|%s" % [String(line.layer), String(line.measure)])
		line.description = "%s on %s" % [
			_measure_words(line.measure), String(line.layer)
		]
		line.item_id = suggest_item(line, book)
		if line.item_id.is_empty():
			# Said as a sentence a person reads, and it names the **unit** rather than only the
			# layer, because the reason a layer with a price on it can still be unpriceable is that
			# the book prices the right work by the wrong dimension - an edging rate where the line
			# is an area. This text is read in the estimate panel, not only in a log.
			takeoff.problems.append(
				"%s has no price: nothing in the cost book is priced by %s" % [
					line.description, WorkUnitScript.name_of(line.unit)
				]
			)
		takeoff.lines.append(line)

	for layer: Variant in unmeasured.keys():
		var layer_name: StringName = StringName(layer)
		var reason: String = String(NOT_MEASURED.get(layer_name, "no cost code for this layer"))
		takeoff.notes.append("%d on %s not measured: %s" % [
			int(unmeasured[layer]), String(layer_name), reason
		])
	takeoff.layer_count = order.size()
	return takeoff


## Count the plants that are standing, one line per species.
##
## `rows` is what `PlantPlacement.schedule()` returns: pure dictionaries of `id`, `count`, and the
## names, so this file needs no yard, no scene tree and no catalogue. That is the whole reason the
## planting list was written as data in the first place.
##
## `item_for` maps a species id to the cost book item that prices one of them, because a plant is not
## a rate - a 2 m tree and a 1 m tree are different money, and the office decides which item applies
## (§6: the office chooses, the software suggests).
static func of_plants(rows: Array, book: CostBook = null, item_for: Dictionary = {}) -> Takeoff:
	var takeoff: Takeoff = (load("res://scripts/biz/takeoff.gd") as GDScript).new()
	takeoff.metric = true
	if book != null:
		takeoff.book_version = book.version
		takeoff.book_source = book.source
	for row: Dictionary in rows:
		var species: StringName = StringName(row.get("id", ""))
		var count: int = int(row.get("count", 0))
		if count <= 0:
			continue
		var line: TakeoffLine = TakeoffLine.new()
		line.source = StringName("plant:%s" % String(species)) if not species.is_empty() \
			else &"plant:unknown"
		line.layer = &"401-NEW-PLANT"
		line.measure = WorkUnitScript.COUNT
		line.unit = &"EACH"
		line.quantity_milli = count * SCALE
		line.value = float(count)
		line.cost_code = &"PLANTING"
		line.description = _plant_words(row)
		if species.is_empty():
			# A row with no species is the planting list saying "somebody has to go and look at these".
			# Pricing them at whatever rate the planting layer suggests would be inventing a plant, and
			# an invented plant on a proposal is a number the office cannot defend.
			takeoff.problems.append(
				"%d plants have no species recorded, so there is nothing to price them with" % count
			)
		else:
			line.item_id = StringName(item_for.get(species, suggest_item(line, book)))
			if line.item_id.is_empty():
				takeoff.problems.append("there is nothing in the book to price %s" % line.description)
		takeoff.lines.append(line)
	return takeoff


## Measure a whole plan: the geometry, and the plants that are standing on it.
##
## The double-count rule: when the plants are in the yard as props, the symbolic circles drawn on the
## planting layer are **the way those props are drawn**, not a second set of plants - so the planting
## layer's own geometry is left out and a note says so. Without that rule, every planted shrub would
## be counted twice, once as a symbol and once as a prop, and the bill would be for twice the garden.
static func of_plan(
	document: DraftDocument,
	plant_rows: Array,
	book: CostBook = null,
	item_for: Dictionary = {}
) -> Takeoff:
	var takeoff: Takeoff = of_document(document, book)
	var counted: bool = false
	for row: Dictionary in plant_rows:
		if int(row.get("count", 0)) > 0:
			counted = true
	if not counted:
		# There are no plants in the yard, so a ring drawn on the planting layer is a plant somebody
		# drew, and it is the only record of it - it stays in.
		return takeoff
	var kept: Array[TakeoffLine] = []
	for line: TakeoffLine in takeoff.lines:
		if line.layer == &"401-NEW-PLANT" and line.measure == WorkUnitScript.COUNT:
			takeoff.notes.append(
				"%d symbols on 401-NEW-PLANT not counted: the plants are in the yard as props already"
				% (line.quantity_milli / SCALE)
			)
			continue
		kept.append(line)
	takeoff.lines = kept
	var planted: Takeoff = of_plants(plant_rows, book, item_for)
	takeoff.lines.append_array(planted.lines)
	takeoff.problems.append_array(planted.problems)
	return takeoff


# --- the layer table ------------------------------------------------------------------------


## How a layer is measured, or an empty dictionary when it is not measured at all.
static func measure_plan(layer_name: StringName) -> Dictionary:
	var entry: Variant = LAYER_MEASURES.get(layer_name)
	return (entry as Dictionary) if entry is Dictionary else {}


static func is_measured(layer_name: StringName) -> bool:
	return LAYER_MEASURES.has(layer_name)


## The cost code a layer's work belongs to, so a takeoff groups by phase before anybody says so.
static func cost_code_for(layer_name: StringName) -> StringName:
	var plan: Dictionary = measure_plan(layer_name)
	if plan.is_empty():
		return StringName("")
	return StringName(plan.get("cost_code", ""))


static func measure_for(layer_name: StringName) -> StringName:
	var plan: Dictionary = measure_plan(layer_name)
	return StringName(plan.get("measure", "")) if not plan.is_empty() else StringName("")


## The unit a measurement of this dimension should be stated in, in the drawing's own system.
static func unit_for(dimension: StringName, metric: bool = true) -> StringName:
	return WorkUnitScript.preferred(dimension, metric)


## The item the layer suggests: the one the layer table names, or failing that the first in the book
## that costs to this layer's code **and is priced by a unit of the same dimension**.
##
## The second half matters as much as the first: a book whose only hardscape rate is per cubic metre
## must not offer it against 48 m² of paving, which is AC-B10. And a suggestion is not a decision -
## §6's rule is that the office chooses and the software suggests - so this only ever fills in a
## default that the caller can overrule.
static func suggest_item(line: TakeoffLine, book: CostBook) -> StringName:
	if book == null:
		return &""
	var preferred: StringName = StringName(measure_plan(line.layer).get("item", ""))
	if not preferred.is_empty():
		var named: CostItem = book.item(preferred)
		if named != null and WorkUnitScript.same_dimension(named.unit, line.unit):
			return preferred
	for item_id: StringName in book.item_ids():
		var item: CostItem = book.item(item_id)
		if item == null or item.cost_code != line.cost_code:
			continue
		if WorkUnitScript.same_dimension(item.unit, line.unit):
			return item_id
	return &""


## Every item in the book that could price this line, in book order. What a "choose a cost item" list
## in a panel is built from.
static func items_for(line: TakeoffLine, book: CostBook) -> Array[StringName]:
	var out: Array[StringName] = []
	if book == null:
		return out
	for item_id: StringName in book.item_ids():
		var item: CostItem = book.item(item_id)
		if item == null:
			continue
		if not WorkUnitScript.same_dimension(item.unit, line.unit):
			continue
		if item.cost_code == line.cost_code:
			out.append(item_id)
	if out.is_empty():
		# Nothing costs to this code, so fall back to anything of the right dimension rather than
		# offering nothing at all: a painter painting a fence is still priced per m².
		for item_id: StringName in book.item_ids():
			var item: CostItem = book.item(item_id)
			if item != null and WorkUnitScript.same_dimension(item.unit, line.unit):
				out.append(item_id)
	# Whatever is already on the line comes first: it is what the line is priced at, and a list that
	# buried it would make a panel look as though the choice had been lost.
	var at: int = out.find(line.item_id)
	if at > 0:
		var chosen: StringName = out[at]
		out.remove_at(at)
		out.insert(0, chosen)
	return out


# --- pricing a line -------------------------------------------------------------------------


## Turn a measured line into an estimate line at a chosen item's rate.
##
## The quantity is **converted** to the item's unit first, by the exact ratio the unit table holds, and
## the conversion rounds by the module's one rule - so a plan drawn in metres priced by a book in
## square feet is `area_m2 x 10.7639...` computed in integers rather than with a constant somebody
## typed from a spreadsheet (§6). A dimension that does not match is refused rather than converted.
##
## Returns `{ok, reason, line}`.
static func priced_line(line: TakeoffLine, item: CostItem) -> Dictionary:
	if line == null or item == null:
		return {"ok": false, "reason": "a line and an item are both needed", "line": null}
	var quantity: Dictionary = WorkUnitScript.convert(
		line.quantity_milli, line.unit, item.unit
	)
	if not bool(quantity["ok"]):
		return {"ok": false, "reason": String(quantity["reason"]), "line": null}
	var priced: EstimateLine = LineScript.make(item, int(quantity["quantity_milli"]))
	priced.description = line.description if priced.description.is_empty() else priced.description
	priced.cost_code = line.cost_code if not line.cost_code.is_empty() else priced.cost_code
	priced.takeoff = line.lineage()
	priced.note = line.note
	return {"ok": true, "reason": "", "line": priced}


## Price every line the takeoff can price. Returns `{ok, estimate, refused}`: the estimate is a draft
## with one line per measured quantity, and `refused` names every line it would not price - which is
## the honest answer to a cost book that does not cover the drawing yet.
func estimate(book: CostBook, tax_code: StringName = &"NONE", currency: StringName = &"CAD") -> Dictionary:
	var priced: Estimate = Estimate.make()
	priced.currency = currency
	priced.tax_code = tax_code
	priced.book_version = book_version
	priced.book_source = book_source
	priced.site = site.duplicate(true)
	var refused: Array[String] = []
	for line: TakeoffLine in lines:
		var item: CostItem = book.item(line.item_id) if book != null else null
		if item == null:
			refused.append("%s has no cost item" % line.description)
			continue
		var result: Dictionary = priced_line(line, item)
		if not bool(result["ok"]):
			refused.append(String(result["reason"]))
			continue
		if not priced.add_line(result["line"], book):
			refused.append("%s was refused by the estimate" % line.description)
	return {"ok": refused.is_empty(), "estimate": priced, "refused": refused}


# --- re-takeoff, which is a diff ------------------------------------------------------------


## Price the same quantities again and compare them, line by line, keyed by what each line was
## measured from.
##
## This is the feature §6 names: a revision to a drawing produces "bed grew 4.2 m², +$310" rather than
## a new estimate to compare by eye. Returns `{rows, added, removed, delta, delta_money, ok}` where
## each row is `{source, description, was_milli, now_milli, delta_milli, unit, item_id, delta_money}`.
##
## `delta_money` is `null` where the line has no priced item: a quantity nobody has priced yet has no
## money to report, and inventing zero would make it look like a line that did not change.
func diff(previous: Takeoff, book: CostBook = null) -> Dictionary:
	var before: Dictionary = {}
	for line: TakeoffLine in previous.lines:
		before[line.source] = line
	var rows: Array = []
	var delta_money: Money = MoneyScript.zero()
	var added: int = 0
	var removed: int = 0
	var seen: Dictionary = {}
	for line: TakeoffLine in lines:
		seen[line.source] = true
		var was: TakeoffLine = before.get(line.source)
		var was_milli: int = was.quantity_milli if was != null else 0
		var is_new: bool = was == null
		if is_new:
			added += 1
		var row: Dictionary = {
			"source": line.source,
			"description": line.description,
			"was_milli": was_milli,
			"now_milli": line.quantity_milli,
			"delta_milli": line.quantity_milli - was_milli,
			"unit": line.unit,
			"item_id": line.item_id,
			"delta_money": null,
		}
		if book != null and (not line.item_id.is_empty() or (was != null and not was.item_id.is_empty())):
			var item_id: StringName = line.item_id if not line.item_id.is_empty() else was.item_id
			var item: CostItem = book.item(item_id)
			if item != null and WorkUnitScript.same_dimension(item.unit, line.unit):
				var converted: Dictionary = WorkUnitScript.convert(
					int(row["delta_milli"]), line.unit, item.unit
				)
				if bool(converted["ok"]):
					var money: Money = MoneyScript.round_div(
						item.rate.cents * int(converted["quantity_milli"]), SCALE, item.rate.currency
					)
					row["delta_money"] = money
					delta_money = delta_money.add(money)
		rows.append(row)
	for source: Variant in before:
		if not seen.has(source):
			removed += 1
			rows.append({
				"source": source,
				"description": (before[source] as TakeoffLine).description,
				"was_milli": (before[source] as TakeoffLine).quantity_milli,
				"now_milli": 0,
				"delta_milli": -(before[source] as TakeoffLine).quantity_milli,
				"unit": (before[source] as TakeoffLine).unit,
				"item_id": (before[source] as TakeoffLine).item_id,
				"delta_money": null,
			})
	return {
		"rows": rows,
		"added": added,
		"removed": removed,
		"delta": lines.size() - previous.lines.size(),
		"delta_money": delta_money,
	}


## The diff as sentences: "E-300-NEW-HARD 48.000 -> 52.200 m², +4.200, +$176.40".
func diff_text(previous: Takeoff, book: CostBook = null) -> String:
	var report: Dictionary = diff(previous, book)
	var out: PackedStringArray = PackedStringArray()
	for row: Dictionary in report["rows"]:
		var delta: int = int(row["delta_milli"])
		if delta == 0:
			continue
		var money: Variant = row["delta_money"]
		var money_words: String = " unpriced" if money == null else " %s" % (money as Money).format_with_currency()
		out.append("%s  %.3f -> %.3f %s, %+.3f%s" % [
			row["description"],
			float(int(row["was_milli"])) / float(SCALE),
			float(int(row["now_milli"])) / float(SCALE),
			WorkUnitScript.name_of(StringName(row["unit"])),
			float(delta) / float(SCALE),
			money_words,
		])
	return "\n".join(out)


# --- describing it --------------------------------------------------------------------------


func line_count() -> int:
	return lines.size()


func is_sound() -> bool:
	return problems.is_empty()


func priced_count() -> int:
	var count: int = 0
	for line: TakeoffLine in lines:
		if not line.item_id.is_empty():
			count += 1
	return count


func describe() -> String:
	return "%d measured, %d priced, %d not measured, %d problems" % [
		lines.size(), priced_count(), notes.size(), problems.size()
	]


func to_dict() -> Dictionary:
	var rows: Array = []
	for line: TakeoffLine in lines:
		rows.append(line.to_dict())
	return {
		"lines": rows,
		"notes": notes.duplicate(),
		"problems": problems.duplicate(),
		"document_hash": document_hash,
		"document_count": document_count,
		"layer_count": layer_count,
		"site": site.duplicate(true),
		"metric": metric,
		"book_version": book_version,
		"book_source": book_source,
	}


static func from_dict(data: Dictionary) -> Takeoff:
	var takeoff: Takeoff = (load("res://scripts/biz/takeoff.gd") as GDScript).new()
	var rows: Variant = data.get("lines", [])
	if rows is Array:
		for record: Variant in rows:
			if record is Dictionary:
				takeoff.lines.append(TakeoffLine.from_dict(record))
	for note: Variant in data.get("notes", []) as Array:
		takeoff.notes.append(String(note))
	for problem: Variant in data.get("problems", []) as Array:
		takeoff.problems.append(String(problem))
	takeoff.document_hash = String(data.get("document_hash", ""))
	takeoff.document_count = int(data.get("document_count", 0))
	takeoff.layer_count = int(data.get("layer_count", 0))
	var where: Variant = data.get("site", {})
	takeoff.site = (where as Dictionary).duplicate(true) if where is Dictionary else {}
	takeoff.metric = bool(data.get("metric", true))
	takeoff.book_version = int(data.get("book_version", 1))
	takeoff.book_source = String(data.get("book_source", ""))
	return takeoff


# --- the measuring itself -------------------------------------------------------------------


## What one entity contributes: its measure, its unit, and the quantity in thousandths.
##
## A circle has both an area and a circumference, and the layer decides which is the quantity of work
## (see `LAYER_MEASURES`). An entity on an **area** layer that has no area - a line of wall, a kerb, an
## edging run - contributes its **length** instead of nothing, because a wall is real work; the two
## never mix in one line, since the line is keyed by layer *and* measure.
static func _measure(entity: DraftEntity, wanted: StringName, metric: bool) -> Dictionary:
	if entity == null:
		return {}
	if wanted == WorkUnitScript.COUNT:
		return {
			"measure": WorkUnitScript.COUNT,
			"unit": &"EACH",
			"quantity_milli": SCALE,
			"value": 1.0,
		}
	var area: float = entity.area()
	var length: float = entity.length()
	if wanted == WorkUnitScript.AREA and area > 0.0:
		return {
			"measure": WorkUnitScript.AREA,
			"unit": unit_for(WorkUnitScript.AREA, metric),
			"quantity_milli": int(round(area * float(SCALE))),
			"value": area,
		}
	if length > 0.0:
		return {
			"measure": WorkUnitScript.LINEAR,
			"unit": unit_for(WorkUnitScript.LINEAR, metric),
			"quantity_milli": int(round(length * float(SCALE))),
			"value": length,
		}
	return {}


static func _measure_words(measure: StringName) -> String:
	match measure:
		WorkUnitScript.AREA:
			return "area"
		WorkUnitScript.LINEAR:
			return "length"
		WorkUnitScript.COUNT:
			return "count of items"
	return String(measure)


static func _plant_words(row: Dictionary) -> String:
	var words: String = String(row.get("botanical_name", ""))
	if not String(row.get("cultivar", "")).is_empty():
		words = "%s '%s'" % [words, String(row["cultivar"])]
	var common: String = String(row.get("common_name", ""))
	if not common.is_empty():
		words = "%s (%s)" % [words, common]
	var size: int = int(row.get("spread_cm", 0))
	if size > 0:
		words = "%s, %.1f m" % [words, float(size) / 100.0]
	return words


## A drawing's identity, for the record: what the quantities in this takeoff were measured from.
static func _hash_document(document: DraftDocument) -> String:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(document.to_dict()).to_utf8_buffer())
	return (context.finish() as PackedByteArray).hex_encode()