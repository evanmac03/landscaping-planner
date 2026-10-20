extends RefCounted
## Writes the two sample plot sheets: the deliverable, and a turned one.
##
## **Why this is a file rather than a script somebody retypes.** The samples are the only
## way to see several dimensions, a layer key and sheet furniture on one page at once, and
## they were rebuilt from scratch every time they were needed — which is a recipe that
## rots, and had already begun to (the last one was written before the pen table learned
## about generated linework). They are content, so they live in the repository.
##
## Run it with `execute_script`:
##
##     var sheets := load("res://tools/sample_sheets.gd")
##     print(sheets.write_sheets())
##     quit()
##
## **`quit()` is not optional.** A `SceneTree` script without it runs forever and the
## tool times out having printed nothing at all.
##
## What the sheets contain, and why:
##
## * **A 20 × 12 m lot at 1:100 on A3.** The size matters: a viewport and a legend claim
##   part of the sheet and the auto-chosen scale is measured against what is *left*, so a
##   lot much larger than this drops a scale step and large much smaller one lands on
##   1:50. 20 × 12 m is what a real garden plan would use.
## * **A setback line and five dimensions on the same magenta pen slot.** The dashed pen
##   belongs to a setback line; a dimension's generated linework must ignore it. Both
##   appear on the finished sheet, so the rule is visible on the sample rather than only
##   in a test — the setback dashes and the dimensions do not.
## * **Both dimension standards**: the A3 sheet uses the shipped architectural (arrowhead)
##   standard, the turned A2 sheet the engineering (tick) one.

const Document := preload("res://scripts/draft/draft_document.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const Exporter := preload("res://scripts/draft/sheet_exporter.gd")
const PenStyle := preload("res://scripts/draft/plot_style_table.gd")
const DimensionStyle := preload("res://scripts/draft/dimension_style.gd")

const PROJECT := "Riverbend Residence"
const REVISION := "B"

## Where the sheets are written. Both files are outside the repository: they are output,
## like a still, and a regenerated sample is not a thing to commit over an old one.
const OUT_DIR := "user://"


## The design the samples are drawn from: a 20 × 12 m lot with a house, a patio, a path,
## a bed with five plants in it, an irrigation run, a setback line and five dimensions.
static func make_document() -> Variant:
	var document = Document.new()
	# The lot, the house that already stands on it, and the front setback that constrains
	# what can be built: three facts about the site before anything is proposed.
	document.add(
		Entity.make_rectangle(Vector2(10, 6), Vector2(20, 12)), LayerSet.SURVEY_PROPERTY
	)
	document.add(Entity.make_line(Vector2(3, 0), Vector2(3, 12)), LayerSet.SETBACK_EASEMENT)
	document.add(
		Entity.make_rectangle(Vector2(5, 2.5), Vector2(8, 5)), LayerSet.EXISTING_STRUCTURE
	)
	# Proposed: a patio and the path to it, a planting bed, five plants, and irrigation
	# under the bed.
	document.add(
		Entity.make_rectangle(Vector2(14.5, 3.5), Vector2(6, 5)), LayerSet.NEW_HARDSCAPE
	)
	document.add(
		Entity.make_polyline(PackedVector2Array([Vector2(9, 3), Vector2(11.5, 3)])),
		LayerSet.NEW_HARDSCAPE
	)
	document.add(
		Entity.make_rectangle(Vector2(14, 9), Vector2(8, 3)), LayerSet.NEW_BED
	)
	# Two trees and three shrubs. The biggest canopy is dimensioned by radius, so it is
	# the one at the right-hand end of the bed, where its leader and its measurement have
	# the bed to themselves: a dimension that reads over another symbol is unreadable, and
	# the first draft of this sample put a shrub under the text.
	document.add(Entity.make_circle(Vector2(11.5, 8.5), 1.2), LayerSet.NEW_PLANTING)
	document.add(Entity.make_circle(Vector2(16.5, 8.5), 1.5), LayerSet.NEW_PLANTING)
	document.add(Entity.make_circle(Vector2(13.0, 7.7), 0.5), LayerSet.NEW_PLANTING)
	document.add(Entity.make_circle(Vector2(14.2, 9.3), 0.5), LayerSet.NEW_PLANTING)
	document.add(Entity.make_circle(Vector2(13.9, 8.4), 0.5), LayerSet.NEW_PLANTING)
	document.add(
		Entity.make_polyline(PackedVector2Array([Vector2(11, 7.6), Vector2(17.5, 7.6)])),
		LayerSet.IRRIGATION
	)
	# Five dimensions, one of each command: the lot's width and depth, the patio's width,
	# an aligned measurement from the house's corner to the patio's, and the big tree's
	# radius. The aligned one crosses empty ground on purpose, which is the only kind of
	# dimension that is easy to misread.
	document.add(
		Entity.make_dimension(Vector2(0, 12), Vector2(20, 12), 1.2), LayerSet.DIMENSION
	)
	document.add(
		Entity.make_dimension(Vector2(0, 0), Vector2(0, 12), -1.2), LayerSet.DIMENSION
	)
	document.add(
		Entity.make_dimension(Vector2(11.5, 1), Vector2(17.5, 1), -1.2), LayerSet.DIMENSION
	)
	document.add(
		Entity.make_dimension(
			Vector2(9, 5), Vector2(11.5, 1), 0.6, Entity.DimensionKind.ALIGNED
		),
		LayerSet.DIMENSION
	)
	document.add(
		Entity.make_dimension(
			Vector2(16.5, 8.5), Vector2(18, 8.5), 0.0, Entity.DimensionKind.RADIUS
		),
		LayerSet.DIMENSION
	)
	# A note, inside the patio and clear of the dimension that measures it.
	document.add(Entity.make_text(Vector2(14.5, 4.5), "PATIO (NEW)"), LayerSet.TEXT)
	return document


## The options the A3 sheet is laid out with: the deliverable as a client would get it.
static func sheet_options() -> Dictionary:
	return {
		"sheet": "A3",
		"project": PROJECT,
		"drawing": "Planting & Hardscape Plan",
		"revision": REVISION,
		"date": Time.get_date_string_from_system(),
		"pen_table": PenStyle.default_table(),
		"legend": true,
	}


## The options the turned sheet is laid out with: the same design on A2, turned a quarter
## turn in a viewport, with the engineering tick standard, to exercise all three.
static func turned_options() -> Dictionary:
	var options := sheet_options()
	options["sheet"] = "A2"
	options["drawing"] = "Planting Plan, turned"
	options["scale"] = 100.0
	options["viewport"] = {"rotation_degrees": 90.0}
	return options


## Writes both sheets. Returns the paths it wrote, so a caller reports rather than assumes.
static func write_sheets() -> Array[String]:
	var written: Array[String] = []
	var plan = make_document()
	written.append(_write(plan, "sample-sheet.pdf", sheet_options()))
	# The engineering standard on the turned sheet, set on the document because the
	# standard is a property of the drawing rather than of the export.
	var turned = make_document()
	turned.dimension_style = DimensionStyle.engineering()
	written.append(_write(turned, "sample-sheet-turned.pdf", turned_options()))
	return written


static func _write(document, file_name: String, options: Dictionary) -> String:
	var path := OUT_DIR + file_name
	var bytes: PackedByteArray = Exporter.export_pdf(document, options)
	if bytes.is_empty():
		push_error("SampleSheets: %s came back empty" % file_name)
		return ""
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SampleSheets: could not write %s" % path)
		return ""
	file.store_buffer(bytes)
	file.close()
	return path