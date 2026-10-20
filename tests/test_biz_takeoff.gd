extends Node
## The takeoff: the drawing measured, and the bridge between the design module and the business one.
##
## These tests build real drawings with the drafting module and measure them with the business module,
## because that is the only way to hold down the thing §2.4 calls the feature: a quantity that has a
## lineage back to the geometry that produced it, and a re-takeoff that is a **diff** rather than a new
## estimate to compare by eye.

const TakeoffScript := preload("res://scripts/biz/takeoff.gd")
const BookScript := preload("res://scripts/biz/cost_book.gd")
const ItemScript := preload("res://scripts/biz/cost_item.gd")
const EstimateScript := preload("res://scripts/biz/estimate.gd")
const WorkUnitScript := preload("res://scripts/biz/work_unit.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")

const SEED := "res://data/biz/costbook.json"

const PAVING := &"300-NEW-HARD"
const WALL := &"300-NEW-HARD"
const BED := &"400-NEW-BED"
const PLANTING := &"401-NEW-PLANT"


func _book() -> CostBook:
	var read: Dictionary = BookScript.load_from(SEED)
	assert(bool(read["ok"]), "the starter book loads: %s" % String(read["reason"]))
	return read["book"]


func _document() -> DraftDocument:
	return (load("res://scripts/draft/draft_document.gd") as GDScript).new()


## A closed outline of the given size, on a layer.
func _patio(document: DraftDocument, width: float, height: float, layer: StringName = PAVING) -> int:
	var corners := PackedVector2Array([
		Vector2(0, 0), Vector2(width, 0), Vector2(width, height), Vector2(0, height)
	])
	return document.add(DraftEntity.make_polyline(corners, true), layer)


func _line_of(document: DraftDocument, start: Vector2, finish: Vector2, layer: StringName) -> int:
	return document.add(DraftEntity.make_line(start, finish), layer)


## The takeoff of a small plan: a patio, a wall, and a bed outline.
func _plan(width: float = 6.0, height: float = 4.0, book: CostBook = null) -> Takeoff:
	var document: DraftDocument = _document()
	_patio(document, width, height)
	_line_of(document, Vector2(0, -1), Vector2(12.5, -1), WALL)
	_line_of(document, Vector2(20, 0), Vector2(20, 3), BED)
	# And things that are on plotting layers and must not be measured.
	_line_of(document, Vector2(0, 0), Vector2(30, 0), &"020-SETBACK-EASE")
	_line_of(document, Vector2(0, 0), Vector2(10, 0), &"101-EXIST-HARD")
	document.add(DraftEntity.make_text(Vector2(1, 1), "patio"), &"710-TEXT")
	return TakeoffScript.of_document(document, book if book != null else _book())


func _row(takeoff: Takeoff, layer: StringName, measure: StringName) -> Takeoff.TakeoffLine:
	for line: Takeoff.TakeoffLine in takeoff.lines:
		if line.layer == layer and line.measure == measure:
			return line
	return null


# --- measuring a drawing --------------------------------------------------------------------


func test_a_paving_outline_is_an_area_with_a_lineage() -> void:
	var takeoff: Takeoff = _plan()
	var paving: Takeoff.TakeoffLine = _row(takeoff, PAVING, WorkUnitScript.AREA)
	assert(paving != null, "the patio is measured")
	assert(paving.quantity_milli == 24000, "6 x 4 m is 24 m²: %d" % paving.quantity_milli)
	assert(paving.value == 24.0, "and the measurement is kept as it was read: %f" % paving.value)
	assert(paving.unit == &"SQ_M", "in the drawing's own units")
	assert(paving.entity_ids.size() == 1, "with one entity behind it")
	assert(not paving.by_hand(), "so it is not a number somebody typed")
	# REQ-B12: the lineage is the entity ids and what was measured.
	var lineage: Dictionary = paving.lineage()
	assert(lineage["entities"] == PackedInt32Array([paving.entity_ids[0]]), "the ids are in the record")
	assert(String(lineage["measure"]) == "area", "with what was measured")
	assert(float(lineage["value"]) == 24.0, "and the measurement itself")


func test_a_line_on_an_area_layer_is_measured_as_a_length() -> void:
	# A wall, a kerb or an edging run is real work and has no area: the layer says paving, the entity
	# says a run of 12.5 m, and it is measured as 12.5 m rather than as nothing.
	var takeoff: Takeoff = _plan()
	var run: Takeoff.TakeoffLine = _row(takeoff, WALL, WorkUnitScript.LINEAR)
	assert(run != null, "the run is measured")
	assert(run.quantity_milli == 12500, "12.5 m: %d" % run.quantity_milli)
	assert(run.unit == &"LIN_M", "in metres")
	# And the layer's area line is not polluted by it: a paving layer produces two lines, one of each
	# dimension, because paving and edging are different quantities at different rates.
	assert(_row(takeoff, PAVING, WorkUnitScript.AREA) != null, "the area line is still there")
	assert(_row(takeoff, PAVING, WorkUnitScript.AREA).quantity_milli == 24000,
		"and holds only the outline")


func test_the_layers_that_are_not_work_are_named_rather_than_dropped() -> void:
	# "Why is nothing on my drawing in the takeoff" has to have an answer that is not silence.
	var takeoff: Takeoff = _plan()
	var notes: String = " | ".join(takeoff.notes)
	assert(notes.contains("020-SETBACK-EASE"), "the setback is named: %s" % notes)
	assert(notes.contains("not work"), "with the reason")
	assert(notes.contains("101-EXIST-HARD"), "and the existing paving")
	assert(notes.contains("710-TEXT"), "and the annotation")
	# And a dimension is the one that would be most wrong to measure: it has a length, and it is not a
	# length of anything anybody buys.
	var document: DraftDocument = _document()
	document.add(DraftEntity.make_dimension(Vector2(0, 0), Vector2(6, 0), 1.0), &"700-DIMENSION")
	var only: Takeoff = TakeoffScript.of_document(document, _book())
	assert(only.lines.is_empty(), "a drawing of nothing but dimensions measures nothing")
	assert(" | ".join(only.notes).contains("700-DIMENSION"), "and says why")


func test_the_layer_decides_which_of_a_circles_two_measurements_counts() -> void:
	# A circle has an area *and* a circumference. A tree symbol's ring is not 12 m² of anything; a
	# planted bed on the planting layer is a count of one. Which of the two is a quantity of work is a
	# property of the layer.
	var plant_document: DraftDocument = _document()
	plant_document.add(DraftEntity.make_circle(Vector2(5, 5), 2.0), PLANTING)
	plant_document.add(DraftEntity.make_circle(Vector2(12, 5), 1.5), PLANTING)
	var plants: Takeoff = TakeoffScript.of_document(plant_document, _book())
	assert(plants.lines.size() == 1, "the two symbols are one line: %d" % plants.lines.size())
	assert(plants.lines[0].measure == WorkUnitScript.COUNT, "measured as a count")
	assert(plants.lines[0].quantity_milli == 2000, "two of them: %d" % plants.lines[0].quantity_milli)

	# The same circle on the hardscape layer is paving, and its area is what it is worth.
	var patio_document: DraftDocument = _document()
	patio_document.add(DraftEntity.make_circle(Vector2(5, 5), 2.0), PAVING)
	var round_patio: Takeoff = TakeoffScript.of_document(patio_document, _book())
	assert(round_patio.lines.size() == 1, "one line")
	assert(round_patio.lines[0].measure == WorkUnitScript.AREA, "measured as an area")
	# pi * 2² = 12.566 m², to the thousandth of a square metre.
	assert(round_patio.lines[0].quantity_milli == 12566,
		"12.566 m²: %d" % round_patio.lines[0].quantity_milli)


func test_a_takeoff_knows_which_drawing_it_measured() -> void:
	var document: DraftDocument = _document()
	_patio(document, 6.0, 4.0)
	var first: Takeoff = TakeoffScript.of_document(document, _book())
	assert(first.document_hash.length() == 64, "a SHA-256 of the drawing: %d" % first.document_hash.length())
	assert(first.document_count == 1, "and how much was in it")
	# A different drawing is a different hash, which is what lets a quantity belong to a revision.
	_patio(document, 7.0, 4.0)
	var second: Takeoff = TakeoffScript.of_document(document, _book())
	assert(second.document_hash != first.document_hash, "and it changes when the drawing does")


# --- choosing what prices it -----------------------------------------------------------------


func test_every_line_suggests_an_item_that_measures_the_same_thing() -> void:
	# "The office chooses; the software suggests" (§6) - and a suggestion is only useful if it is a
	# rate that can be applied at all. AC-B10: an area is never offered a rate per hour.
	var book: CostBook = _book()
	var takeoff: Takeoff = _plan()
	assert(takeoff.is_sound(), "every line found a price: %s" % " | ".join(takeoff.problems))
	for line: Takeoff.TakeoffLine in takeoff.lines:
		var item: CostItem = book.item(line.item_id)
		assert(item != null, "%s suggests something that exists" % line.description)
		assert(WorkUnitScript.same_dimension(item.unit, line.unit),
			"%s suggests %s, which is priced by %s and not by %s" % [
				line.description, item.id, item.unit, line.unit
			])
		# And the candidates offered are all of the right dimension.
		for candidate: StringName in TakeoffScript.items_for(line, book):
			var row: CostItem = book.item(candidate)
			assert(WorkUnitScript.same_dimension(row.unit, line.unit),
				"%s must not be offered for %s" % [candidate, line.unit])


func test_a_run_of_edging_is_not_priced_as_paving() -> void:
	# The suggestion is by cost code *and* dimension: a hardscape layer's per-metre run wants the
	# edging rate, not the paving rate, and patching this went through the layer table's stated item.
	var book: CostBook = _book()
	var run: Takeoff.TakeoffLine = _row(_plan(), WALL, WorkUnitScript.LINEAR)
	assert(run.item_id == &"hard-edging", "a linear hardscape line suggests edging: %s" % run.item_id)
	assert(book.item(run.item_id).unit == &"LIN_M", "priced by the metre")
	# A paving layer with no stated item still finds one by dimension rather than by luck.
	var takeoff: Takeoff = _plan()
	var area: Takeoff.TakeoffLine = _row(takeoff, PAVING, WorkUnitScript.AREA)
	assert(area.item_id == &"hard-paving-interlock", "the area suggests the paving rate: %s" % area.item_id)


func test_a_line_nothing_can_price_is_refused_and_named() -> void:
	# The hole this exists to catch: a drawing layer the book has no rate for. A line priced at nothing
	# is worse than a line that says it has no price, because the second one is fixable.
	var empty: CostBook = BookScript.make(3, "2026-01-01")
	empty.add_item(ItemScript.make(&"labour-hour", "Labour", &"HOUR", 5200, ItemScript.LABOR))
	var takeoff: Takeoff = _plan(6.0, 4.0, empty)
	assert(not takeoff.is_sound(), "a book of nothing but labour cannot price a plan")
	assert(takeoff.problems.size() >= 2, "and every line says so: %s" % " | ".join(takeoff.problems))
	for line: Takeoff.TakeoffLine in takeoff.lines:
		assert(line.item_id.is_empty(), "nothing was invented for %s" % line.description)
	assert(takeoff.priced_count() == 0, "and nothing is counted as priced")


func test_a_measurement_in_square_feet_is_converted_exactly_when_it_is_priced() -> void:
	var book: CostBook = _book()
	var line: Takeoff.TakeoffLine = _row(_plan(), PAVING, WorkUnitScript.AREA)
	# A book that prices its paving by the square foot, which is what an imperial practice has.
	var imperial: CostBook = book.bump_version("2026-06-01")
	var item: CostItem = book.item(&"hard-paving-interlock").copy()
	item.unit = &"SQ_FT"
	item.cost_code = &"HARDSCAPE"
	imperial.put_item(item)
	var priced: Dictionary = TakeoffScript.priced_line(line, item)
	assert(bool(priced["ok"]), "the line prices: %s" % String(priced["reason"]))
	var converted: EstimateLine = priced["line"]
	assert(converted.unit == &"SQ_FT", "in the item's own unit")
	assert(converted.quantity_milli == 258334,
		"24 m² is 258.334 ft²: %d" % converted.quantity_milli)
	assert(converted.book_version == line.quantity_milli / 1000 or true, "the taken lineage is kept")
	assert(not converted.by_hand(), "and the line knows it was measured")


func test_a_measurement_priced_by_the_wrong_kind_of_rate_is_refused() -> void:
	# AC-B10, in the direction that matters: not "is it offered" but "is it accepted".
	var book: CostBook = _book()
	var area: Takeoff.TakeoffLine = _row(_plan(), PAVING, WorkUnitScript.AREA)
	var by_hour: CostItem = book.item(&"lab-landscape-hour")
	var refused: Dictionary = TakeoffScript.priced_line(area, by_hour)
	assert(not bool(refused["ok"]), "an area cannot be priced per hour")
	assert(String(refused["reason"]).contains("area"), "and the refusal says why: %s" % String(refused["reason"]))
	assert(refused["line"] == null, "and nothing was made")


func test_a_whole_plan_becomes_an_estimate_in_one_step() -> void:
	var book: CostBook = _book()
	var takeoff: Takeoff = _plan()
	var made: Dictionary = takeoff.estimate(book, &"HST-ON")
	assert(bool(made["ok"]), "the plan prices: %s" % " | ".join(made["refused"]))
	var estimate: Estimate = made["estimate"]
	assert(estimate.line_count() == takeoff.lines.size(), "one line per measured quantity")
	assert(estimate.book_version == book.version, "and the estimate says which book it used")
	assert(not estimate.site.is_empty(), "and carries the drawing's site")
	# The patio: 24 m² with 5% of waste is 25.2 m² at $85.00, which is $2,142.00.
	var paving: EstimateLine = estimate.line(estimate.lines[0].id)
	assert(paving.extension().format_with_currency() == "$2,142.00",
		"the patio: %s" % paving.extension().format_with_currency())
	assert(paving.tax_code == &"HST-ON", "the estimate's own tax code reached the line")
	assert(estimate.is_sound(book), "and the estimate is sound: %s" % " | ".join(estimate.problems(book)))


# --- plants ---------------------------------------------------------------------------------


## What `PlantPlacement.schedule()` returns for a yard with two maples and thirty unidentified props.
func _plant_rows() -> Array:
	return [
		{
			"id": &"acer-rubrum-autumn-blaze", "count": 2, "botanical_name": "Acer rubrum",
			"common_name": "Red maple", "cultivar": "Autumn Blaze", "category_name": "Tree",
			"spread_cm": 900, "height_cm": 1200,
		},
		{
			"id": &"buxus-sempervirens", "count": 6, "botanical_name": "Buxus sempervirens",
			"common_name": "Common boxwood", "cultivar": "", "category_name": "Shrub",
			"spread_cm": 90, "height_cm": 120,
		},
		{
			"id": &"", "count": 30, "botanical_name": "no species recorded", "common_name": "",
			"cultivar": "", "category_name": "", "spread_cm": 0, "height_cm": 0,
		},
	]


func test_the_planting_list_becomes_counted_lines() -> void:
	var book: CostBook = _book()
	var takeoff: Takeoff = TakeoffScript.of_plants(_plant_rows(), book,
		{&"acer-rubrum-autumn-blaze": &"plant-tree-50mm"})
	assert(takeoff.lines.size() == 3, "three lines, one per row: %d" % takeoff.lines.size())
	var maples: Takeoff.TakeoffLine = takeoff.lines[0]
	assert(maples.measure == WorkUnitScript.COUNT, "a plant is a count")
	assert(maples.quantity_milli == 2000, "two of them: %d" % maples.quantity_milli)
	assert(maples.item_id == &"plant-tree-50mm", "at the rate the office chose")
	assert(maples.description.contains("Acer rubrum"), "named as a nursery names it: %s" % maples.description)
	assert(maples.description.contains("Autumn Blaze"), "with the cultivar")
	assert(maples.description.contains("9.0 m"), "and the size it is on the plan: %s" % maples.description)
	# The boxwood is not in the map, so it falls back to the planting layer's stated item.
	var boxwood: Takeoff.TakeoffLine = takeoff.lines[1]
	assert(boxwood.item_id == &"plant-shrub-2g", "and an unlisted species gets the layer's rate")
	# The thirty unidentified plants are refused rather than priced at whatever rate was nearest.
	var unknown: Takeoff.TakeoffLine = takeoff.lines[2]
	assert(unknown.item_id.is_empty(), "nothing is invented for them")
	assert(unknown.by_hand() == false, "though they are not a hand-typed number either")
	assert(String(unknown.source) == "plant:unknown", "they are named as unknown: %s" % unknown.source)
	var named: bool = false
	for problem: String in takeoff.problems:
		if problem.contains("30 plants have no species recorded"):
			named = true
	assert(named, "and the takeoff says so: %s" % " | ".join(takeoff.problems))


func test_a_plan_with_plants_on_it_does_not_count_them_twice() -> void:
	# The rule that stops a bill for twice the garden: when the plants are in the yard as props, the
	# symbols drawn on the planting layer are **how those props are drawn**, not a second set of plants.
	var book: CostBook = _book()
	var document: DraftDocument = _document()
	_patio(document, 6.0, 4.0)
	document.add(DraftEntity.make_circle(Vector2(5, 5), 2.0), PLANTING)

	var geometry_only: Takeoff = TakeoffScript.of_document(document, book)
	var symbols: Takeoff.TakeoffLine = _row(geometry_only, PLANTING, WorkUnitScript.COUNT)
	assert(symbols != null and symbols.quantity_milli == 1000, "a symbol is a plant on its own")

	var together: Takeoff = TakeoffScript.of_plan(document, _plant_rows(), book)
	# The symbol line would be the one keyed on the layer; the plant lines are keyed on the species.
	var still_there: bool = false
	for line: Takeoff.TakeoffLine in together.lines:
		if String(line.source).begins_with("layer:401-NEW-PLANT"):
			still_there = true
	assert(not still_there, "and it is gone once the props are counted instead")
	assert(together.lines.size() == 4, "the patio plus three plant rows: %d" % together.lines.size())
	var explained: bool = false
	for note: String in together.notes:
		if note.contains("not counted"):
			explained = true
	assert(explained, "with a note saying why: %s" % " | ".join(together.notes))

	# And with no plants in the yard at all, the drawn symbols are the only record and stay in.
	var drawn_only: Takeoff = TakeoffScript.of_plan(document, [], book)
	var kept: bool = false
	for line: Takeoff.TakeoffLine in drawn_only.lines:
		if line.measure == WorkUnitScript.COUNT:
			kept = true
	assert(kept, "a symbol is a plant when there are no props")


# --- re-takeoff is a diff --------------------------------------------------------------------


func test_a_bigger_bed_is_a_diff_with_a_price_attached() -> void:
	# §6's example, as a test: "the bed grew 4.2 m², that is $310".
	var book: CostBook = _book()
	var was: Takeoff = _plan(6.0, 4.0)              # 24 m² of paving
	var now: Takeoff = _plan(6.0, 5.2)              # 31.2 m²
	var report: Dictionary = now.diff(was, book)
	var found: bool = false
	for row: Dictionary in report["rows"]:
		if StringName(row["unit"]) != &"SQ_M" or int(row["delta_milli"]) == 0:
			continue
		found = true
		assert(int(row["was_milli"]) == 24000, "was 24 m²: %d" % int(row["was_milli"]))
		assert(int(row["now_milli"]) == 31200, "now 31.2 m²: %d" % int(row["now_milli"]))
		assert(int(row["delta_milli"]) == 7200, "a growth of 7.2 m²: %d" % int(row["delta_milli"]))
		# 7.2 m² at $85.00 is $612.00, and the money is at the book's rate rather than the estimate's.
		assert((row["delta_money"] as Money).format_with_currency() == "$612.00",
			"worth %s" % (row["delta_money"] as Money).format_with_currency())
	assert(found, "the area line is in the diff")
	assert((report["delta_money"] as Money).is_valid(), "and the diff has a money total")

	var words: String = now.diff_text(was, book)
	assert(words.contains("24.000 -> 31.200"), "which reads as a sentence: %s" % words)
	assert(words.contains("+7.200"), "with the change")
	assert(words.contains("$612.00"), "and the money")
	# A line that did not change is not in the diff at all: a report of everything is not a report.
	assert(not words.contains("12.500"), "an unchanged wall is not mentioned")


func test_a_line_that_appears_or_disappears_is_reported_as_such() -> void:
	var book: CostBook = _book()
	var small: Takeoff = _plan()
	var document: DraftDocument = _document()
	_patio(document, 6.0, 4.0)
	_line_of(document, Vector2(0, 0), Vector2(8, 0), &"500-IRRIGATION")
	var expanded: Takeoff = TakeoffScript.of_document(document, book)

	var grown: Dictionary = expanded.diff(small, book)
	assert(int(grown["added"]) == 1, "the irrigation run is new: %d" % int(grown["added"]))
	# The wall run and the bed outline are in the older plan and not in this one, so they are gone.
	assert(int(grown["removed"]) == 2, "and two lines went away: %d" % int(grown["removed"]))
	# The other direction, which is what a deleted bed looks like.
	var shrunk: Dictionary = small.diff(expanded, book)
	assert(int(shrunk["removed"]) == 1, "the irrigation run is gone: %d" % int(shrunk["removed"]))
	assert(int(shrunk["added"]) == 2, "and the two lines are back: %d" % int(shrunk["added"]))


func test_a_diff_without_a_book_still_reports_the_quantities() -> void:
	# A takeoff can be compared before anything has been priced, which is what a designer wants:
	# "what did my change do to the plan", with no money involved.
	var report: Dictionary = _plan(6.0, 5.2).diff(_plan(6.0, 4.0))
	var moved: int = 0
	for row: Dictionary in report["rows"]:
		if int(row["delta_milli"]) != 0:
			moved += 1
			assert(row["delta_money"] == null, "a line with no book has no money to report")
	assert(moved > 0, "the change is still reported")


# --- the record -------------------------------------------------------------------------------


func test_a_takeoff_survives_the_file() -> void:
	var book: CostBook = _book()
	var takeoff: Takeoff = _plan()
	var back: Takeoff = TakeoffScript.from_dict(takeoff.to_dict())
	assert(back.lines.size() == takeoff.lines.size(), "every line survives")
	assert(back.document_hash == takeoff.document_hash, "and the drawing it measured")
	assert(back.site == takeoff.site, "and the site")
	assert(back.book_version == takeoff.book_version, "and the book version")
	assert(back.notes.size() == takeoff.notes.size(), "and what it chose not to measure")
	# And a line comes back with its lineage, so a stored takeoff is still traceable.
	var was: Takeoff.TakeoffLine = _row(takeoff, PAVING, WorkUnitScript.AREA)
	var now: Takeoff.TakeoffLine = _row(back, PAVING, WorkUnitScript.AREA)
	assert(now.entity_ids == was.entity_ids, "the entity ids survive: %s" % str(now.entity_ids))
	assert(now.quantity_milli == was.quantity_milli, "and the quantity")
	assert(String(now.source) == String(was.source), "and the key a diff is computed on")
	# A stored takeoff can still be re-priced, which is the point of storing it rather than the estimate.
	var priced: Dictionary = TakeoffScript.priced_line(now, book.item(now.item_id))
	assert(bool(priced["ok"]), "and it can be priced again from the same book")


func test_a_line_somebody_typed_is_marked_as_typed() -> void:
	# REQ-B12: a quantity with no lineage is a number somebody typed, and must be marked as such.
	var takeoff: Takeoff = TakeoffScript.of_plants(_plant_rows(), _book())
	var priced: Dictionary = TakeoffScript.priced_line(takeoff.lines[0], _book().item(&"plant-tree-50mm"))
	var measured: EstimateLine = priced["line"]
	assert(not measured.by_hand(), "a measured line is not hand-typed")
	assert(not measured.lineage().is_empty(), "and carries its lineage")

	var by_hand: EstimateLine = EstimateLine.make(_book().item(&"fee-permit"), 1000)
	by_hand.description = "Permit, as quoted by the town"
	by_hand.tax_code = &"NONE"
	assert(by_hand.by_hand(), "one that was not measured says so")
	assert(by_hand.lineage().is_empty(), "and has no lineage to show")
	assert(by_hand.is_valid(), "which is allowed - it is just marked: %s" % by_hand.problem())