extends Node
## Tests for the site-stats report: what a plan covers, measured by layer.
##
## The report is a reading of the takeoff, so these tests check the reading - which
## layers appear, how their quantities add up, what is deliberately left out, and that
## the whole thing survives a file.

const SiteReportScript := preload("res://scripts/site_report.gd")
const Document := preload("res://scripts/draft/draft_document.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const WorkUnitScript := preload("res://scripts/biz/work_unit.gd")

const AREA := WorkUnitScript.AREA
const COUNT := WorkUnitScript.COUNT


## A paving rectangle of a known area, so a quantity can be checked by hand.
func _paved(document) -> void:
	document.add(Entity.make_rectangle(Vector2(0, 0), Vector2(4, 5)), LayerSet.NEW_HARDSCAPE)


func test_a_drawing_with_nothing_on_it_reports_nothing() -> void:
	var report = SiteReportScript.of_plan(Document.new())
	assert(report.is_empty())
	assert(report.row_count() == 0)
	assert(report.summary().contains("nothing"))
	assert(report.text().contains("Site statistics"))


func test_a_report_with_no_drawing_says_so_rather_than_failing() -> void:
	var report = SiteReportScript.of_plan(null)
	assert(report.is_empty())
	assert(report.problem() != "")
	assert(report.summary() == report.problem())
	assert(report.text().contains("drawing"))


func test_a_paved_area_is_reported_as_an_area_on_its_layer() -> void:
	var document := Document.new()
	_paved(document)
	var report = SiteReportScript.of_plan(document)
	var rows = report.work_rows()
	assert(rows.size() == 1, "one layer of work")
	var row = rows[0]
	assert(row.layer == LayerSet.NEW_HARDSCAPE)
	assert(row.measure == AREA, "paving is measured as an area")
	assert(row.shape_count == 1, "and it came from one shape")
	# 4 x 5 m is 20 m2.
	assert(is_equal_approx(float(row.quantity_milli) / 1000.0, 20.0))
	assert(row.text().contains("1 shape"))


func test_areas_of_different_layers_add_up_by_dimension() -> void:
	var document := Document.new()
	_paved(document)
	document.add(Entity.make_rectangle(Vector2(20, 0), Vector2(2, 3)), LayerSet.NEW_BED)
	var report = SiteReportScript.of_plan(document)
	assert(report.work_rows().size() == 2, "paving and a bed are two layers")
	# 20 m2 of paving and 6 m2 of bed.
	assert(is_equal_approx(float(report.total_milli(AREA)) / 1000.0, 26.0))
	var text := report.total_text(AREA)
	assert(text.contains("26.000"), "the total reads as 26 %s" % text)


func test_a_dimension_is_named_as_not_measured_rather_than_dropped() -> void:
	var document := Document.new()
	_paved(document)
	document.add(
		Entity.make_dimension(Vector2(0, 0), Vector2(4, 0), 1.0), LayerSet.DIMENSION
	)
	var report = SiteReportScript.of_plan(document)
	assert(report.work_rows().size() == 1, "the dimension is not a line of work")
	assert(report.notes().size() == 1, "but it is not silent either")
	assert(report.notes()[0].contains("DIMENSION"), "the note names the layer")
	assert(report.text().contains("Not measured"))


func test_the_planting_list_becomes_planting_rows() -> void:
	var document := Document.new()
	_paved(document)
	var rows: Array = [
		{"id": "acer-rubrum", "count": 3, "common_name": "Red maple", "botanical_name": "Acer rubrum"},
	]
	var report = SiteReportScript.of_plan(document, rows)
	assert(report.plant_rows().size() == 1, "one species")
	assert(report.row_count() == 2, "the work and the planting")
	assert(is_equal_approx(float(report.total_milli(COUNT)) / 1000.0, 3.0), "three plants")
	var text := report.text()
	assert(text.contains("Planting"))
	assert(text.contains("Red maple"))


func test_a_dimension_the_plan_has_none_of_has_no_total() -> void:
	var document := Document.new()
	_paved(document)
	var report = SiteReportScript.of_plan(document)
	assert(report.total_text(COUNT) == "", "no plants, so no count total")
	assert(report.total_text(AREA) != "", "but there is an area")
	assert(not report.summary().contains("each"), "and the summary does not mention plants")


func test_the_summary_names_the_line_count_and_the_totals() -> void:
	var document := Document.new()
	_paved(document)
	var report = SiteReportScript.of_plan(document)
	var summary := report.summary()
	assert(summary.begins_with("1 line:"))
	assert(summary.contains("20.000"), "it states the area total: %s" % summary)


func test_a_report_survives_the_file_format() -> void:
	var document := Document.new()
	_paved(document)
	var rows: Array = [{"id": "acer-rubrum", "count": 2, "common_name": "Red maple"}]
	var report = SiteReportScript.of_plan(document, rows)
	var back = SiteReportScript.from_dict(report.to_dict())
	assert(back.text() == report.text(), "the report reads the same after a round trip")
	assert(back.row_count() == report.row_count())