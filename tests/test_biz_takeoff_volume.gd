extends Node
## The takeoff measured as a **volume**: an outline at a depth its layer states.
##
## The hole these tests close is one this module named itself. A practice buys mulch, soil amendment
## and a lift of aggregate by the cubic metre, and the starter cost book ships rates for exactly that -
## `bed-mulch` and `hard-paving-base`, both priced per m³ - which the takeoff could never reach,
## because nothing in a drawing says how deep the work is and nothing on a layer could say it either.
##
## So the depth is the fourth dimension, and it lives on the **layer**: the same bed at 75 mm and at
## 150 mm is one decision about the whole garden and not a fact about one closed outline. These tests
## hold down the two rules that keep a volume honest - the depth is a property of the layer, and a
## volume layer with no depth is **refused and named** rather than measured as its area and quietly
## priced as though the depth were zero.

const TakeoffScript := preload("res://scripts/biz/takeoff.gd")
const BookScript := preload("res://scripts/biz/cost_book.gd")
const WorkUnitScript := preload("res://scripts/biz/work_unit.gd")
const LayerScript := preload("res://scripts/draft/draft_layer.gd")

const SEED := "res://data/biz/costbook.json"

## A layer a practice adds, and the reason these tests add it to the **document's own layer set** as
## well as to the takeoff's table: a document refuses a layer it does not carry and lands the entity
## on the bed layer instead (REQ 5.1.1), so a takeoff plan for a layer no drawing can hold is
## unreachable - which is a fact worth meeting once in a test.
const MULCH := &"403-NEW-MULCH"


func _book() -> CostBook:
	var read: Dictionary = BookScript.load_from(SEED)
	assert(bool(read["ok"]), "the starter book loads: %s" % String(read["reason"]))
	return read["book"]


## A document that carries the mulch layer, so an entity can actually land on it.
func _document() -> DraftDocument:
	var document: DraftDocument = (load("res://scripts/draft/draft_document.gd") as GDScript).new()
	var layer: DraftLayer = LayerScript.new()
	layer.name = MULCH
	layer.purpose = "mulch and soil amendment, bought by the cubic metre"
	document.layers.add(layer)
	return document


## The mulch layer as work, suggesting a **per-square-metre** item on purpose: a practice's bed layer
## usually names its amendment, and the volume rule then has to reach past it for a rate of the right
## dimension rather than pricing 1.8 m³ at a rate for 24 m².
func _mulch_is_work() -> void:
	TakeoffScript.LAYER_MEASURES[MULCH] = {
		"measure": WorkUnitScript.AREA,
		"cost_code": &"BEDS",
		"item": &"bed-soil-amend",
	}


func _forget_mulch() -> void:
	TakeoffScript.LAYER_MEASURES.erase(MULCH)


## A closed outline of the given size, on the mulch layer. 6 x 4 m is 24 m².
func _bed(document: DraftDocument, width: float = 6.0, height: float = 4.0) -> int:
	var corners := PackedVector2Array([
		Vector2(0, 0), Vector2(width, 0), Vector2(width, height), Vector2(0, height)
	])
	return document.add(DraftEntity.make_polyline(corners, true), MULCH)


func _row(takeoff: Takeoff, measure: StringName) -> Takeoff.TakeoffLine:
	for line: Takeoff.TakeoffLine in takeoff.lines:
		if line.layer == MULCH and line.measure == measure:
			return line
	return null


# --- a depth on a layer turns an area into a volume -------------------------------------------


func test_a_mulch_layer_with_no_depth_is_measured_as_its_area() -> void:
	# The layer the practice has always had, unchanged: 24 m² of bed is 24 m² of amendment.
	_mulch_is_work()
	var document: DraftDocument = _document()
	_bed(document)
	var takeoff: Takeoff = TakeoffScript.of_document(document, _book())
	var line: Takeoff.TakeoffLine = _row(takeoff, WorkUnitScript.AREA)
	assert(line != null, "the bed is measured")
	assert(line.quantity_milli == 24000, "6 x 4 m is 24 m²: %d" % line.quantity_milli)
	assert(line.unit == &"SQ_M", "in square metres")
	assert(takeoff.is_sound(), "with nothing to complain about")
	_forget_mulch()


func test_stating_a_depth_turns_the_same_outline_into_a_volume() -> void:
	# 24 m² at 75 mm is 1.8 m³, and it is the *volume* that is bought: the outline has not changed,
	# the decision about how deep the mulch goes has.
	_mulch_is_work()
	assert(TakeoffScript.set_depth(MULCH, 75), "the depth is stated")
	var document: DraftDocument = _document()
	_bed(document)
	var takeoff: Takeoff = TakeoffScript.of_document(document, _book())
	assert(_row(takeoff, WorkUnitScript.AREA) == null, "there is no area line left to double-bill")
	var line: Takeoff.TakeoffLine = _row(takeoff, WorkUnitScript.VOLUME)
	assert(line != null, "the bed is measured as a volume")
	assert(line.quantity_milli == 1800, "24 m² x 75 mm is 1.8 m³: %d" % line.quantity_milli)
	assert(line.unit == &"CU_M", "in cubic metres")
	assert(absf(line.value - 1.8) < 1e-9, "and the measurement is kept as it was read: %f" % line.value)
	_forget_mulch()


func test_the_depth_is_a_property_of_the_layer_and_comes_back_out_of_it() -> void:
	# Read once, in one place, the way the layer lock is: the question "how deep is this layer" has a
	# single answer and it is not stored on any outline.
	_mulch_is_work()
	assert(TakeoffScript.depth_of(MULCH) == 0, "a layer that has never been given a depth has none")
	assert(not TakeoffScript.is_volume_layer(MULCH), "and is not a volume layer")
	TakeoffScript.set_depth(MULCH, 150)
	assert(TakeoffScript.depth_of(MULCH) == 150, "the depth reads back")
	assert(TakeoffScript.is_volume_layer(MULCH), "and the layer is now bought by the cubic metre")
	_forget_mulch()


func test_set_depth_refuses_a_layer_that_is_not_measured_and_a_depth_of_nothing() -> void:
	# Refusing rather than inventing: a layer with no plan has no cost code and no suggested item, and
	# a depth is not a good enough reason to decide those. And no depth is not a very thin layer of
	# mulch - it is the absence of the one fact that makes the measurement possible.
	_mulch_is_work()
	assert(not TakeoffScript.set_depth(&"950-UNDERLAY", 75), "an unmeasured layer is refused")
	assert(not TakeoffScript.set_depth(MULCH, 0), "a depth of nothing is refused")
	assert(not TakeoffScript.set_depth(MULCH, -25), "and so is a negative one")
	assert(TakeoffScript.depth_of(MULCH) == 0, "neither attempt changed anything")
	assert(not TakeoffScript.is_volume_layer(MULCH), "and the layer still measures as an area")
	_forget_mulch()


func test_a_volume_layer_with_no_depth_is_refused_and_named() -> void:
	# The one answer this file gives to anything it will not measure: count it, name it, say why. The
	# tempting alternative - measure the outline as an area and let a per-m³ rate price it - is a
	# number that looks plausible in a total, and that is the kind of wrong this module exists to stop.
	TakeoffScript.LAYER_MEASURES[MULCH] = {
		"measure": WorkUnitScript.VOLUME,
		"cost_code": &"BEDS",
		"item": &"bed-mulch",
	}
	var document: DraftDocument = _document()
	_bed(document)
	var takeoff: Takeoff = TakeoffScript.of_document(document, _book())
	assert(takeoff.lines.is_empty(), "nothing was measured: %d lines" % takeoff.lines.size())
	assert(not takeoff.is_sound(), "and it is not a sound takeoff")
	var problems: String = " | ".join(takeoff.problems)
	assert(problems.contains(String(MULCH)), "the layer is named: %s" % problems)
	assert(problems.contains("volume"), "with what it is measured as")
	assert(problems.contains("no depth"), "and what is missing")
	assert(problems.contains("set_depth"), "and how to state one")
	_forget_mulch()


# --- a volume in the drawing's own units ------------------------------------------------------


func test_a_volume_is_stated_in_the_drawing_own_units() -> void:
	# A practice drawing in feet buys mulch by the cubic yard, and the number has to be a cubic-yard
	# number. Stating the unit without converting the quantity - 1.8 labelled yd³ - is a quantity out
	# by a factor of more than thirty that would look entirely at home in a total.
	_mulch_is_work()
	TakeoffScript.set_depth(MULCH, 75)
	var document: DraftDocument = _document()
	document.units.system = DraftUnits.System.IMPERIAL
	_bed(document)
	var takeoff: Takeoff = TakeoffScript.of_document(document, _book())
	var line: Takeoff.TakeoffLine = _row(takeoff, WorkUnitScript.VOLUME)
	assert(line != null, "the bed is still measured as a volume")
	assert(line.unit == &"CU_YD", "stated in cubic yards")
	var expected: Dictionary = WorkUnitScript.convert(1800, &"CU_M", &"CU_YD")
	assert(bool(expected["ok"]), "the conversion is one the unit table knows")
	assert(line.quantity_milli == int(expected["quantity_milli"]),
		"1.8 m³ is %d thousandths of a cubic yard: %d" % [
			int(expected["quantity_milli"]), line.quantity_milli
		])
	assert(absf(line.value - 1.8) < 1e-9, "while the measurement itself stays in metres: %f" % line.value)
	_forget_mulch()


func test_an_area_in_an_imperial_drawing_is_a_square_foot_number() -> void:
	# The same rule for the older dimensions, which is where it was once got wrong: a 24 m² patio is
	# 258.334 ft², and the unit said SQ_FT while the number stayed at 24.
	_mulch_is_work()
	var document: DraftDocument = _document()
	document.units.system = DraftUnits.System.IMPERIAL
	_bed(document)
	var takeoff: Takeoff = TakeoffScript.of_document(document, _book())
	var line: Takeoff.TakeoffLine = _row(takeoff, WorkUnitScript.AREA)
	assert(line != null, "the bed is measured as an area")
	assert(line.unit == &"SQ_FT", "in square feet")
	var expected: Dictionary = WorkUnitScript.convert(24000, &"SQ_M", &"SQ_FT")
	assert(line.quantity_milli == int(expected["quantity_milli"]),
		"24 m² is %d thousandths of a square foot: %d" % [
			int(expected["quantity_milli"]), line.quantity_milli
		])
	assert(absf(line.value - 24.0) < 1e-9, "and the measurement stays 24 m²: %f" % line.value)
	_forget_mulch()


# --- what a volume does with a shape that has no area ------------------------------------------


func test_a_run_of_edging_through_a_mulch_bed_is_still_a_length() -> void:
	# A bed is usually edged, and the edging is real work with no depth to it. It falls back to its
	# length exactly as it does on an area layer, and it lands in a line of its own - so a volume layer
	# produces a volume and a length, and neither is billed as the other.
	_mulch_is_work()
	assert(TakeoffScript.set_depth(MULCH, 75), "the depth is stated")
	var document: DraftDocument = _document()
	_bed(document)
	document.add(DraftEntity.make_line(Vector2(0, -0.5), Vector2(6, -0.5)), MULCH)
	var takeoff: Takeoff = TakeoffScript.of_document(document, _book())
	assert(takeoff.lines.size() == 2, "two lines: %d" % takeoff.lines.size())
	var volume: Takeoff.TakeoffLine = _row(takeoff, WorkUnitScript.VOLUME)
	var run: Takeoff.TakeoffLine = _row(takeoff, WorkUnitScript.LINEAR)
	assert(volume != null and run != null, "one of each dimension")
	assert(volume.quantity_milli == 1800, "the bed is 1.8 m³: %d" % volume.quantity_milli)
	assert(run.quantity_milli == 6000, "the edging is 6 m: %d" % run.quantity_milli)
	assert(volume.source != run.source, "and the two are keyed apart, so a re-takeoff can tell them apart")
	_forget_mulch()


# --- the rate the takeoff could not reach ------------------------------------------------------


func test_a_volume_reaches_the_per_cubic_metre_rate_it_could_not() -> void:
	# This is the whole point of the feature. The layer suggests a per-square-metre item; the
	# measurement is a volume; so the suggestion has to be an item of the same dimension, and the one
	# the starter book ships is `bed-mulch` at $58.00 a cubic metre - a rate that was in the book and
	# unreachable from any drawing.
	_mulch_is_work()
	assert(TakeoffScript.set_depth(MULCH, 75), "the depth is stated")
	var document: DraftDocument = _document()
	_bed(document)
	var book: CostBook = _book()
	var takeoff: Takeoff = TakeoffScript.of_document(document, book)
	var line: Takeoff.TakeoffLine = _row(takeoff, WorkUnitScript.VOLUME)
	assert(line.item_id == &"bed-mulch", "the per-m³ rate, not the per-m² one: %s" % String(line.item_id))
	# 1.8 m³ with the mulch's 8% of waste is 1.944 m³, at $58.00 a cubic metre.
	var priced: Dictionary = takeoff.estimate(book)
	assert(bool(priced["ok"]), "the takeoff prices: %s" % " | ".join(priced["refused"]))
	var estimate: Estimate = priced["estimate"]
	assert(estimate.lines.size() == 1, "one priced line: %d" % estimate.lines.size())
	var row: EstimateLine = estimate.lines[0]
	assert(row.unit == &"CU_M", "in cubic metres: %s" % String(row.unit))
	assert(row.quantity_with_waste() == 1944, "1.944 m³: %d" % row.quantity_with_waste())
	assert(row.extension().format_with_currency() == "$112.75",
		"1.944 m³ at $58.00: %s" % row.extension().format_with_currency())
	_forget_mulch()


func test_a_volume_line_says_what_it_is_in_words() -> void:
	# The line is read by a person in the estimate panel, so it says which dimension it is and how
	# many of them - the same words an area line uses.
	_mulch_is_work()
	TakeoffScript.set_depth(MULCH, 75)
	var document: DraftDocument = _document()
	_bed(document)
	var takeoff: Takeoff = TakeoffScript.of_document(document, _book())
	var line: Takeoff.TakeoffLine = _row(takeoff, WorkUnitScript.VOLUME)
	var words: String = line.describe()
	assert(words.contains("1.800 m³"), "the quantity is written in cubic metres: %s" % words)
	assert(words.contains("volume"), "and the line says what it is: %s" % words)
	assert(words.contains(String(MULCH)), "on the layer that produced it: %s" % words)
	_forget_mulch()


# --- the shipped layers are untouched by any of this -------------------------------------------


func test_the_shipped_layers_still_measure_as_they_did() -> void:
	# The guard on the whole feature: a depth is something a practice states, so no layer that ships
	# with the program may have acquired one. A bed is an area, and a paving layer is an area.
	for layer_name: StringName in [&"300-NEW-HARD", &"400-NEW-BED", &"402-NEW-TURF"]:
		var plan: Dictionary = TakeoffScript.measure_plan(layer_name)
		assert(not plan.is_empty(), "%s is measured" % String(layer_name))
		assert(StringName(plan["measure"]) == WorkUnitScript.AREA,
			"%s measures as an area: %s" % [String(layer_name), String(plan["measure"])])
		assert(not plan.has("depth_mm"), "%s states no depth" % String(layer_name))
		assert(TakeoffScript.depth_of(layer_name) == 0, "%s has no depth to read" % String(layer_name))
		assert(not TakeoffScript.is_volume_layer(layer_name), "%s is not a volume layer" % String(layer_name))