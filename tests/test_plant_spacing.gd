extends Node
## Planting a bed at a spacing: where the plants go, how many there are, and the refusal when there is
## no answer.
##
## The outline here is a rectangle written out rather than a `DraftEntity`, because the arithmetic
## takes an outline and not an entity: a bed drawn as a rectangle, a closed polyline or a circle all
## arrive here as the same ring of points, and a test that went through the entity layer would be a
## test about the entity layer.
##
## Every test that counts plants uses a **clearance** rather than filling a bed edge to edge. A grid
## line that lands exactly on the outline is a point every polygon test is entitled to answer either
## way, and a count that depends on which way is a count that will fail on another machine.

const SpacingScript := preload("res://scripts/plant_spacing.gd")
const CatalogueScript := preload("res://scripts/plant_catalogue.gd")
const PlacementScript := preload("res://scripts/plant_placement.gd")
const Document := preload("res://scripts/draft/draft_document.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")

const SEED := "res://data/plants/nursery_list.json"

## A 0.3 m groundcover, a 0.45 m perennial and a 9 m tree: the three sizes that make the arithmetic
## look different.
const THYME := &"thymus-serpyllum"
const RUDBECKIA := &"rudbeckia-fulgida-goldsturm"
const MAPLE := &"acer-rubrum-autumn-blaze"


func _catalogue() -> PlantCatalogue:
	var read: Dictionary = CatalogueScript.load_from(SEED)
	assert(bool(read["ok"]), "the shipped list loads: %s" % String(read["reason"]))
	return read["catalogue"]


func _yard() -> Node3D:
	var yard := Node3D.new()
	yard.name = "Yard"
	return yard


## A square bed of `size` metres with its corner at the origin.
func _bed(size: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(size, 0.0), Vector2(size, size), Vector2(0.0, size),
	])


## A ring with its corner at `left`/`top`, so a grid can be laid over it without its lines landing on
## the edges.
func _ring(left: float, top: float, size: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(left, top), Vector2(left + size, top),
		Vector2(left + size, top + size), Vector2(left, top + size),
	])


func _same(a: float, b: float, slack: float = 1e-6) -> bool:
	return absf(a - b) <= slack


# --- the grid ------------------------------------------------------------------------------


## A square grid at a spacing, inset so no grid line lands on the edge: a 10 m bed at 1 m with half a
## metre of clearance keeps the lines at 1..9, which is 9 x 9.
func test_a_square_grid_is_rows_and_columns_one_spacing_apart() -> void:
	var points := SpacingScript.positions(_bed(10.0), 1.0, SpacingScript.SQUARE, 0.5)
	assert(points.size() == 81, "81 plants: %d" % points.size())

	var xs := {}
	var ys := {}
	for point: Vector2 in points:
		xs[snappedf(point.x, 0.001)] = true
		ys[snappedf(point.y, 0.001)] = true
	assert(xs.size() == 9, "nine columns: %d" % xs.size())
	assert(ys.size() == 9, "nine rows: %d" % ys.size())
	for key: float in xs.keys():
		assert(key >= 1.0 and key <= 9.0, "and every column is inside the clearance: %f" % key)


## The spacing is the distance between neighbours, which is the one property a planting plan is read
## for. Checked against every pair of plants rather than against the grid the fill built them from: a
## test that read the grid back would agree with a fill that was wrong.
func test_no_two_plants_are_closer_than_the_spacing() -> void:
	for arrangement in SpacingScript.ARRANGEMENTS:
		var points := SpacingScript.positions(_bed(10.0), 1.0, arrangement, 0.5)
		var closest := INF
		for i in points.size():
			for j in range(i + 1, points.size()):
				closest = minf(closest, points[i].distance_to(points[j]))
		# A fifth of a millimetre of slack, which is what a double and a snapped grid are worth.
		assert(closest >= 1.0 - 0.0002, "%s: closest pair is %.4f m apart" % [arrangement, closest])


## Staggered rows: what makes the arrangement worth having is that the same ground takes more plants
## while no two of them are any closer. Both halves are asserted, because either one alone is a
## different feature.
func test_staggered_rows_are_offset_by_half_a_spacing_and_fill_the_bed_more_full() -> void:
	var square := SpacingScript.positions(_bed(10.0), 1.0, SpacingScript.SQUARE, 0.5)
	var staggered := SpacingScript.positions(_bed(10.0), 1.0, SpacingScript.TRIANGULAR, 0.5)
	assert(staggered.size() > square.size(),
		"staggered takes more: %d against %d" % [staggered.size(), square.size()])

	var rows := {}
	for point: Vector2 in staggered:
		var y := snappedf(point.y, 0.001)
		if not rows.has(y):
			rows[y] = []
		(rows[y] as Array).append(point.x)
	var heights: Array = rows.keys()
	heights.sort()
	assert(heights.size() > 2, "several rows: %d" % heights.size())
	for index in range(1, heights.size()):
		var gap: float = float(heights[index]) - float(heights[index - 1])
		assert(_same(gap, sqrt(3.0) * 0.5, 0.0002), "rows are sqrt(3)/2 apart: %.4f" % gap)
	# Alternate rows are half a spacing across from each other.
	var first: Array = rows[heights[0]]
	var second: Array = rows[heights[1]]
	first.sort()
	second.sort()
	assert(_same(fmod(absf(float(second[0]) - float(first[0])), 1.0), 0.5, 0.0002),
		"the second row starts half a spacing across")


func test_a_plant_is_kept_half_a_spread_inside_the_bed_it_is_in() -> void:
	var points := SpacingScript.positions(_bed(10.0), 1.0, SpacingScript.SQUARE, 1.25)
	assert(not points.is_empty())
	for point: Vector2 in points:
		assert(SpacingScript.distance_to_outline(point, _bed(10.0)) >= 1.25 - 1e-6,
			"every plant keeps its distance: %f" % SpacingScript.distance_to_outline(point, _bed(10.0)))


## A grid line landing on the outline is outside the bed, whatever a polygon test says about a point
## on an edge. Filling a bed of ten metres at a metre must not put plants on the fence line.
func test_no_plant_stands_on_the_outline_itself() -> void:
	var points := SpacingScript.positions(_ring(0.2, 0.2, 9.5), 1.0)
	assert(points.size() == 81, "the inner nine by nine: %d" % points.size())
	for point: Vector2 in points:
		assert(point.x > 0.2 and point.x < 9.7 and point.y > 0.2 and point.y < 9.7,
			"inside the bed: %s" % point)


## Two beds filled one after another carry on one grid, so a planting does not restart its pattern at
## every bed's own corner. The phase comes from the fill's own origin, which is what makes this true -
## an outline that starts at 0.1 m gets no say in where the columns are.
func test_the_grid_has_one_phase_for_every_bed() -> void:
	var first := SpacingScript.positions(_ring(0.1, 0.1, 4.0), 1.0)
	var second := SpacingScript.positions(_ring(10.4, 0.1, 4.0), 1.0)
	assert(not first.is_empty() and not second.is_empty())
	for point: Vector2 in first:
		assert(_same(fmod(absf(point.x), 1.0), 0.0, 0.0002), "a whole-metre column: %f" % point.x)
	for point: Vector2 in second:
		assert(_same(fmod(absf(point.y), 1.0), 0.0, 0.0002), "the same grid: %f" % point.y)

	# And the origin is what moves it: both beds move together, which the corners could not do.
	var shifted := SpacingScript.positions(
		_ring(0.1, 0.1, 4.0), 1.0, SpacingScript.SQUARE, 0.0, Vector2(0.25, 0.25)
	)
	assert(not shifted.is_empty())
	for point: Vector2 in shifted:
		assert(_same(fmod(absf(point.x - 0.25), 1.0), 0.0, 0.0002), "on the shifted phase: %f" % point.x)


# --- the refusals --------------------------------------------------------------------------


func test_an_outline_with_no_ground_is_refused_rather_than_filled() -> void:
	assert(SpacingScript.positions(PackedVector2Array(), 1.0).is_empty())
	assert(SpacingScript.positions(PackedVector2Array([Vector2.ZERO, Vector2.ONE]), 1.0).is_empty())
	assert(SpacingScript.problem(PackedVector2Array(), 1.0, 0.0) != "")
	assert(SpacingScript.problem(
		PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(2, 0)]), 1.0, 0.0
	) != "")


func test_a_spacing_tighter_than_a_plan_draws_is_refused() -> void:
	assert(SpacingScript.problem(_bed(10.0), 0.001, 0.0) != "")
	assert(SpacingScript.positions(_bed(10.0), 0.0).is_empty())
	# And the floor is the floor: what it refuses is below it and not at it.
	assert(SpacingScript.problem(_bed(10.0), SpacingScript.MIN_SPACING_M, 0.0) == "")


func test_a_bed_that_takes_more_than_one_fill_is_refused_and_names_the_limit() -> void:
	var worked: Dictionary = SpacingScript.plan_fill(_bed(20.0), 0.3, SpacingScript.SQUARE, 0.5)
	assert(not bool(worked["ok"]))
	var said: String = String(worked["reason"])
	assert(said.contains("more than"), "the refusal names the limit: %s" % said)
	assert(said.contains(str(SpacingScript.MAX_PLANTS)))
	# The working-out stops at the answer rather than counting four thousand plants, and what it did
	# work out is capped either way.
	assert((worked["points"] as PackedVector2Array).size() <= SpacingScript.MAX_PLANTS)
	assert(SpacingScript.positions(_bed(20.0), 0.3, SpacingScript.SQUARE, 0.5).size() <= SpacingScript.MAX_PLANTS)


func test_a_bed_too_narrow_for_the_plant_is_refused_in_words() -> void:
	var catalogue: PlantCatalogue = _catalogue()
	var yard: Node3D = _yard()
	# A maple spreads nine metres. A bed half a metre wide cannot hold one, and the refusal has to say
	# that rather than leaving a button that did nothing.
	var report: Dictionary = SpacingScript.fill(
		catalogue, yard, MAPLE, _ring(0.0, 0.0, 0.5), {"spacing": 9.0}
	)
	assert(not bool(report["ok"]))
	assert(String(report["reason"]).contains("more than"), "the refusal is a sentence: %s" % report["reason"])
	assert(int(report["placed"]) == 0)
	assert(PlacementScript.planted(yard).is_empty(), "and nothing was planted")
	yard.free()


func test_a_species_the_list_does_not_have_is_refused_by_name() -> void:
	var catalogue: PlantCatalogue = _catalogue()
	var yard: Node3D = _yard()
	var report: Dictionary = SpacingScript.fill(catalogue, yard, &"not-a-plant", _bed(6.0))
	assert(not bool(report["ok"]))
	assert(String(report["reason"]).contains("not-a-plant"), "%s" % report["reason"])
	var bare: Dictionary = SpacingScript.fill(null, yard, THYME, _bed(6.0))
	assert(not bool(bare["ok"]))
	assert(String(bare["reason"]) != "", "a refusal is never silent")
	yard.free()


# --- planting it ----------------------------------------------------------------------------


## A filled bed is a bed of ordinary planted props: the schedule counts them, the nodes carry their
## species, and they stand where the drawing says - `Vector3(x, 0, y)`, north being -Z.
func test_filling_a_bed_plants_the_plants_the_schedule_then_counts() -> void:
	var catalogue: PlantCatalogue = _catalogue()
	var yard: Node3D = _yard()
	var outline := _ring(0.0, 0.0, 4.0)
	var wanted: int = SpacingScript.count_for(
		outline, 0.6, SpacingScript.TRIANGULAR, SpacingScript.clearance_of(catalogue.get_species(THYME))
	)
	var report: Dictionary = SpacingScript.fill(
		catalogue, yard, THYME, outline, {"spacing": 0.6, "arrangement": SpacingScript.TRIANGULAR}
	)
	assert(bool(report["ok"]), "the bed fills: %s" % report["reason"])
	assert(int(report["placed"]) == wanted, "as many as the count said: %d against %d" % [
		int(report["placed"]), wanted
	])
	assert(wanted > 20, "which is a planting worth having: %d" % wanted)

	var points: PackedVector2Array = report["points"]
	var nodes: Array = report["nodes"]
	assert(nodes.size() == points.size())
	for index in nodes.size():
		var node: Node3D = nodes[index]
		assert(PlacementScript.species_of(node) == THYME, "every one carries its species")
		assert(node.position.is_equal_approx(Vector3(points[index].x, 0.0, points[index].y)),
			"and stands where the plan says: %s against %s" % [node.position, points[index]])

	var rows: Array[Dictionary] = PlacementScript.schedule(catalogue, yard)
	assert(rows.size() == 1, "one species, one row: %d" % rows.size())
	assert(int(rows[0]["count"]) == wanted, "and the schedule counts the bed: %d" % int(rows[0]["count"]))
	yard.free()


func test_the_spacing_defaults_to_the_species_own_spread_and_the_clearance_to_half_of_it() -> void:
	var catalogue: PlantCatalogue = _catalogue()
	var yard: Node3D = _yard()
	var species: PlantSpecies = catalogue.get_species(RUDBECKIA)
	var report: Dictionary = SpacingScript.fill(catalogue, yard, RUDBECKIA, _bed(6.0), {})
	assert(bool(report["ok"]), "%s" % report["reason"])
	assert(_same(float(report["spacing"]), species.spread_m(), 0.0002),
		"just touching: %f against %f" % [float(report["spacing"]), species.spread_m()])
	assert(_same(float(report["clearance"]), species.spread_m() * 0.5, 0.0002),
		"and half a spread in from the edge: %f" % float(report["clearance"]))
	yard.free()


func test_a_watered_down_spacing_plants_a_denser_bed() -> void:
	var catalogue: PlantCatalogue = _catalogue()
	var yard: Node3D = _yard()
	var outline := _bed(4.0)
	var close: Dictionary = SpacingScript.fill(catalogue, yard, RUDBECKIA, outline, {"spacing": 0.3})
	var wide: Dictionary = SpacingScript.fill(catalogue, yard, RUDBECKIA, outline, {"spacing": 0.9})
	assert(int(close["placed"]) > int(wide["placed"]),
		"half the spacing is more plants: %d against %d" % [int(close["placed"]), int(wide["placed"])])
	yard.free()


# --- what the palette is offered -------------------------------------------------------------


func test_the_choices_are_the_ones_a_palette_shows_and_read_the_way_a_person_says_them() -> void:
	var choices: Array[float] = SpacingScript.spacing_choices_m()
	assert(choices.size() > 4)
	# The first choice is the species' own spread, which is the answer most of the time and needs no
	# thinking about.
	assert(choices[0] == 0.0)
	for index in range(1, choices.size()):
		assert(choices[index] > choices[index - 1], "in order: %f" % choices[index])
		assert(choices[index] >= SpacingScript.MIN_SPACING_M)

	assert(SpacingScript.spacing_words(0.45) == "0.45 m")
	assert(SpacingScript.spacing_words(1.2) == "1.2 m")
	assert(SpacingScript.spacing_words(2.0) == "2 m")

	assert(SpacingScript.is_arrangement(SpacingScript.SQUARE))
	assert(SpacingScript.is_arrangement(SpacingScript.TRIANGULAR))
	assert(not SpacingScript.is_arrangement("hexagonal"))
	assert(SpacingScript.arrangement_words(SpacingScript.TRIANGULAR) == "Staggered")


## A line a person reads after pressing the button, and the same line when there was nothing to read.
func test_a_report_reads_as_one_line_and_a_refusal_reads_as_its_reason() -> void:
	var catalogue: PlantCatalogue = _catalogue()
	var yard: Node3D = _yard()
	var report: Dictionary = SpacingScript.fill(catalogue, yard, THYME, _bed(3.0), {"spacing": 0.6})
	var words: String = SpacingScript.report_words(report)
	assert(words.begins_with("%d x " % int(report["placed"])), "%s" % words)
	assert(words.contains("0.6 m"), "the spacing is in it: %s" % words)
	assert(words.contains("square"), "and the arrangement: %s" % words)
	assert(SpacingScript.report_words(SpacingScript.fill(catalogue, yard, &"nope", _bed(3.0))) \
		.contains("nope"))
	yard.free()


# --- the beds a plan offers ------------------------------------------------------------------


## The list a fill picks from is the areas a plan encloses, narrowed to the ones a planting goes in:
## the beds and the planting already there, and not the paving, the lawn or the house.
func test_the_beds_a_plan_offers_are_the_ones_a_planting_goes_in() -> void:
	var document = Document.new()
	document.add(Entity.make_rectangle(Vector2(3.0, 3.0), Vector2(4.0, 2.0)), LayerSet.NEW_BED)
	document.add(Entity.make_rectangle(Vector2(12.0, 3.0), Vector2(4.0, 2.0)), LayerSet.EXISTING_PLANTING)
	document.add(Entity.make_rectangle(Vector2(3.0, 12.0), Vector2(6.0, 3.0)), LayerSet.NEW_TURF)
	document.add(Entity.make_rectangle(Vector2(12.0, 12.0), Vector2(6.0, 3.0)), LayerSet.NEW_HARDSCAPE)

	var beds: Array[Dictionary] = SpacingScript.bed_areas(document)
	assert(beds.size() == 2, "a bed and the planting: %d" % beds.size())
	var labels: Array[String] = []
	for row: Dictionary in beds:
		assert(SpacingScript.PLANTABLE.has(StringName(row["layer"])), "of a plantable layer")
		assert((row["outline"] as PackedVector2Array).size() >= 3, "with an outline to fill")
		assert(float(row["area_m2"]) > 0.0)
		assert(String(row["key"]) != "", "and a key, so it can be found again")
		labels.append(String(row["label"]))
	labels.sort()
	var wanted: Array[String] = ["bed", "existing planting"]
	assert(labels == wanted, "and it is the two of them: %s" % " | ".join(labels))

	# And a plan that encloses no bed offers none, rather than offering everything.
	var lawn = Document.new()
	lawn.add(Entity.make_rectangle(Vector2(4.0, 4.0), Vector2(8.0, 4.0)), LayerSet.NEW_TURF)
	assert(SpacingScript.bed_areas(lawn).is_empty())
	assert(SpacingScript.bed_areas(Document.new()).is_empty())


## The size a bed reads as: a square metre and a half of bed is "6.2", and a whole garden bed is a
## whole number, because a decimal on a hundred square metres is noise.
func test_a_bed_reads_as_one_line_with_its_size() -> void:
	var document = Document.new()
	document.add(Entity.make_rectangle(Vector2(3.0, 3.0), Vector2(4.0, 3.0)), LayerSet.NEW_BED)
	var beds: Array[Dictionary] = SpacingScript.bed_areas(document)
	assert(beds.size() == 1)
	assert(SpacingScript.bed_words(beds[0]) == "%s, 12 m2" % String(beds[0]["name"]),
		"%s" % SpacingScript.bed_words(beds[0]))

	# A bed of 5.76 m2, which is a size with no argument about how it rounds.
	var small = Document.new()
	small.add(Entity.make_rectangle(Vector2(3.0, 3.0), Vector2(2.4, 2.4)), LayerSet.NEW_BED)
	var small_beds: Array[Dictionary] = SpacingScript.bed_areas(small)
	assert(SpacingScript.bed_words(small_beds[0]) == "%s, 5.8 m2" % String(small_beds[0]["name"]),
		"%s" % SpacingScript.bed_words(small_beds[0]))