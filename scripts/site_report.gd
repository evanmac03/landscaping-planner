class_name SiteReport
extends RefCounted
## A coverage report for a plan: what the drawing says is there, grouped by layer and
## measured the way a takeoff measures it.
##
## It does not measure anything itself. The takeoff already knows which layers are work
## and which are not, what dimension each is measured in, and how to add a layer's
## entities up - so the report is a *reading* of that, not a second measuring engine
## that could quietly disagree with the estimate.
##
## The report is deliberately not priced. "How much paving is on this plan" is a question
## about the design, asked long before a cost book exists, and answering it with money
## would make a design question depend on an office's rates.

const TakeoffScript := preload("res://scripts/biz/takeoff.gd")
const WorkUnitScript := preload("res://scripts/biz/work_unit.gd")

## Quantities are held in thousandths, the way the takeoff holds them.
const MILLI := 1000

## The dimensions a plan is reported in, in the order a report reads them. Read from the
## work-unit table rather than spelled here, so a report cannot disagree with the takeoff
## about what an area is called.
static func dimensions() -> Array[StringName]:
	return [WorkUnitScript.AREA, WorkUnitScript.LINEAR, WorkUnitScript.COUNT]


## One line of the report.
class Row extends RefCounted:
	var layer: StringName = &""
	## The measurement's dimension: `WorkUnit.AREA`, `LINEAR`, `COUNT`.
	var measure: StringName = &""
	var unit: StringName = &"EACH"
	var quantity_milli: int = 0
	## How many shapes produced the quantity, or 0 when it was counted rather than measured.
	var shape_count: int = 0
	var description: String = ""

	func quantity_text() -> String:
		return "%.3f %s" % [float(quantity_milli) / float(MILLI), WorkUnitScript.name_of(unit)]

	## Where the quantity came from, so a number a person can check is not confused with one
	## that was counted off the plan.
	func source_text() -> String:
		if shape_count == 1:
			return "1 shape"
		if shape_count > 1:
			return "%d shapes" % shape_count
		return "counted"

	func text() -> String:
		return "%s  %s  (%s)" % [quantity_text(), description, source_text()]


var _rows: Array[Row] = []
var _plant_rows: Array[Row] = []
var _notes: Array[String] = []
var _problem: String = ""


## Read a drawing into a report. `plant_rows` is what `PlantPlacement.schedule()` returns,
## handed in rather than read here for the same reason the takeoff takes it: this file has
## no yard and no catalogue.
static func of_plan(document, planting_rows: Array = []) -> SiteReport:
	var report: SiteReport = (load("res://scripts/site_report.gd") as GDScript).new()
	if document == null:
		report._problem = "a report needs a drawing"
		return report
	var work = TakeoffScript.of_document(document)
	for line in work.lines:
		var row: Row = Row.new()
		row.layer = line.layer
		row.measure = line.measure
		row.unit = line.unit
		row.quantity_milli = line.quantity_milli
		row.shape_count = line.entity_ids.size()
		row.description = line.description
		report._rows.append(row)
	var planting = TakeoffScript.of_plants(planting_rows)
	for line in planting.lines:
		var row: Row = Row.new()
		row.layer = &"401-NEW-PLANT"
		row.measure = line.measure
		row.unit = line.unit
		row.quantity_milli = line.quantity_milli
		row.description = line.description
		report._plant_rows.append(row)
	report._notes = work.notes.duplicate()
	return report


func problem() -> String:
	return _problem


func work_rows() -> Array[Row]:
	return _rows.duplicate()


func plant_rows() -> Array[Row]:
	return _plant_rows.duplicate()


## The layers with geometry that the report deliberately does not measure, each with its
## reason - so "why is nothing on my drawing in the report" has an answer.
func notes() -> Array[String]:
	return _notes.duplicate()


func row_count() -> int:
	return _rows.size() + _plant_rows.size()


func is_empty() -> bool:
	return _rows.is_empty() and _plant_rows.is_empty()


## How much of one dimension the whole plan comes to, in thousandths.
func total_milli(measure: StringName) -> int:
	var total := 0
	for row: Row in _rows:
		if row.measure == measure:
			total += row.quantity_milli
	for row: Row in _plant_rows:
		if row.measure == measure:
			total += row.quantity_milli
	return total


## One dimension's total as words, or "" when the plan has none of it.
func total_text(measure: StringName, in_metric: bool = true) -> String:
	var total := total_milli(measure)
	if total <= 0:
		return ""
	var unit: StringName = TakeoffScript.unit_for(measure, in_metric)
	return "%.3f %s" % [float(total) / float(MILLI), WorkUnitScript.name_of(unit)]


## The report in one line, which is what goes on a status line or into a menu.
func summary() -> String:
	if not _problem.is_empty():
		return _problem
	if is_empty():
		return "the drawing has nothing measurable on it"
	var parts: Array[String] = []
	for measure: StringName in dimensions():
		var words := total_text(measure)
		if words != "":
			parts.append(words)
	return "%d line%s: %s" % [
		row_count(), "" if row_count() == 1 else "s", ", ".join(PackedStringArray(parts)),
	]


## The whole report, as the block of text a person reads.
func text() -> String:
	var lines: Array[String] = []
	if not _problem.is_empty():
		lines.append(_problem)
		return "\n".join(PackedStringArray(lines))
	lines.append("Site statistics")
	lines.append(summary())
	if not _rows.is_empty():
		lines.append("")
		lines.append("Work")
		for row: Row in _rows:
			lines.append("  " + row.text())
	if not _plant_rows.is_empty():
		lines.append("")
		lines.append("Planting")
		for row: Row in _plant_rows:
			lines.append("  " + row.text())
	if not _notes.is_empty():
		lines.append("")
		lines.append("Not measured")
		for note: String in _notes:
			lines.append("  " + note)
	return "\n".join(PackedStringArray(lines))


# --- serialisation --------------------------------------------------------------------


func to_dict() -> Dictionary:
	var rows: Array = []
	for row: Row in _rows:
		rows.append(_row_dict(row))
	var planting: Array = []
	for row: Row in _plant_rows:
		planting.append(_row_dict(row))
	return {
		"problem": _problem,
		"work": rows,
		"planting": planting,
		"notes": _notes.duplicate(),
	}


static func _row_dict(row: Row) -> Dictionary:
	return {
		"layer": String(row.layer),
		"measure": String(row.measure),
		"unit": String(row.unit),
		"quantity_milli": row.quantity_milli,
		"shape_count": row.shape_count,
		"description": row.description,
	}


static func from_dict(data: Dictionary) -> SiteReport:
	var report: SiteReport = (load("res://scripts/site_report.gd") as GDScript).new()
	report._problem = String(data.get("problem", ""))
	for entry: Dictionary in data.get("work", []):
		report._rows.append(_row_from_dict(entry))
	for entry: Dictionary in data.get("planting", []):
		report._plant_rows.append(_row_from_dict(entry))
	for note in data.get("notes", []):
		report._notes.append(String(note))
	return report


static func _row_from_dict(entry: Dictionary) -> Row:
	var row: Row = Row.new()
	row.layer = StringName(entry.get("layer", ""))
	row.measure = StringName(entry.get("measure", ""))
	row.unit = StringName(entry.get("unit", "EACH"))
	row.quantity_milli = int(entry.get("quantity_milli", 0))
	row.shape_count = int(entry.get("shape_count", 0))
	row.description = String(entry.get("description", ""))
	return row