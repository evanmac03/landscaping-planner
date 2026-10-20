extends Node
## Tests for the painted plan, phase 1: the wash table, which regions wash, the
## outlines they come from, and the framing that puts them on paper.
##
## What is deliberately not tested here is the pigment itself. Whether three passes of
## a green read as a bed of foliage is a matter of eyes, and the picture is looked at;
## what *is* tested is every number around it - which layers wash, which entities
## produce a region, where the drawing lands on the sheet, and how big a millimetre is.

const Entity := preload("res://scripts/draft/draft_entity.gd")
const Geom := preload("res://scripts/draft/geom2d.gd")
const Document := preload("res://scripts/draft/draft_document.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const WashTableScript := preload("res://scripts/vis/wash_table.gd")
const WashPainterScript := preload("res://scripts/vis/wash_painter.gd")
const CadSolidScript := preload("res://scripts/vis/cad_solid.gd")
const SketchBakerScript := preload("res://scripts/vis/sketch_baker.gd")
const PaintedPlanScript := preload("res://scripts/vis/painted_plan.gd")


## A document built the way the drafting tools build one, so the layers this test
## washes are the layers the drawer actually draws on.
func _document() -> Variant:
	return Document.new()


# --- the wash table -------------------------------------------------------------------


func test_every_washed_layer_is_a_layer_that_exists() -> void:
	# A wash keyed by a layer name nobody can select is an entry that can never fire.
	# This is REQ-V13.1, and it is the reason this table does not carry the invented
	# names of the specification's first draft.
	var real: Array[StringName] = []
	for entry: Dictionary in LayerSet.PRESETS:
		real.append(entry["name"])
	for key in WashTableScript.WASHES:
		if String(key) == WashTableScript.PLANTING_PROPS:
			continue
		assert(real.has(StringName(key)), "%s is not a layer" % key)


func test_the_wash_pigment_is_the_plan_palette() -> void:
	# REQ-V4.1 made mechanical: the flat working view and the painted wash read one
	# source, so a change to the palette that the wash table does not follow fails
	# here rather than shipping as two greens.
	for key in WashTableScript.WASHES:
		var wash: Dictionary = WashTableScript.WASHES[key]
		var material: String = wash["material"]
		assert(
			PlanStyle.COLOURS.has(material),
			"%s names %s, which the plan palette does not have" % [key, material]
		)
		var pigment: Color = wash["colour"]
		var palette: Color = PlanStyle.COLOURS[material]
		assert(
			pigment.is_equal_approx(palette),
			"%s washes %s but the palette says %s" % [key, pigment, palette]
		)


func test_a_layer_with_no_wash_entry_produces_no_wash() -> void:
	assert(WashTableScript.wash_for(LayerSet.HATCH).is_empty())
	assert(not WashTableScript.washes(LayerSet.HATCH))
	# And a name that is not a layer at all is not a wash either: the table answers
	# "no" rather than inventing a colour for it.
	assert(WashTableScript.wash_for(&"999-NOT-A-LAYER").is_empty())
	assert(WashTableScript.wash_for("").is_empty())


func test_a_wash_can_be_asked_for_by_name_in_either_form() -> void:
	# A layer name arrives as a StringName from the document and as a String from a
	# literal, and a table that answered only one of them would work from one call
	# site and not another.
	var by_symbol: Dictionary = WashTableScript.wash_for(LayerSet.NEW_BED)
	var by_string: Dictionary = WashTableScript.wash_for("400-NEW-BED")
	assert(by_symbol == by_string)
	assert(not by_symbol.is_empty())


func test_every_layer_that_does_not_wash_says_why() -> void:
	# A reader asking why their irrigation layer has no colour should get an answer
	# rather than a missing entry that looks like an oversight.
	var unwashed := 0
	for entry: Dictionary in LayerSet.PRESETS:
		var name: StringName = entry["name"]
		if WashTableScript.washes(name):
			continue
		unwashed += 1
		assert(
			WashTableScript.reason_against(name) != "",
			"%s does not wash and gives no reason" % name
		)
	assert(unwashed > 0, "this test would pass vacuously if every layer washed")


func test_a_non_plotting_layer_never_washes() -> void:
	# A wash is a picture of what will be built, so a tracing aid that does not plot
	# cannot be the one layer that paints over the drawing (REQ-V4.2).
	for entry: Dictionary in LayerSet.PRESETS:
		if bool(entry["plots"]):
			continue
		assert(
			not WashTableScript.washes(entry["name"]),
			"%s does not plot but washes anyway" % entry["name"]
		)


func test_water_and_mulch_differ_from_planting_in_how_they_behave() -> void:
	# REQ-V4.6: a medium's difference is bleed, mottle and wet edge - not a pattern
	# laid over the top. Checked on the two pairs whose media really differ: paving
	# against a bed, and a bed against a planting mass.
	var paving: Dictionary = WashTableScript.wash_for(LayerSet.NEW_HARDSCAPE)
	var bed: Dictionary = WashTableScript.wash_for(LayerSet.NEW_BED)
	var mass: Dictionary = WashTableScript.wash_for(LayerSet.NEW_PLANTING)
	assert(float(paving["bleed_mm"]) < float(bed["bleed_mm"]))
	assert(float(paving["mottle"]) < float(bed["mottle"]))
	assert(float(paving["wet_edge"]) < float(bed["wet_edge"]))
	assert(float(bed["mottle"]) > float(mass["mottle"]))
	assert(float(mass["bleed_mm"]) > float(bed["bleed_mm"]))


# --- which regions wash ---------------------------------------------------------------


func test_a_bed_washes_and_a_dimension_does_not() -> void:
	# AC-V4: a wash region for every area entity, and for no annotation.
	var document = _document()
	var bed: int = document.add(
		Entity.make_rectangle(Vector2.ZERO, Vector2(6.0, 4.0)), LayerSet.NEW_BED
	)
	var paving: int = document.add(
		Entity.make_circle(Vector2(9.0, 0.0), 2.5), LayerSet.NEW_HARDSCAPE
	)
	document.add(
		Entity.make_dimension(Vector2(0.0, 0.0), Vector2(6.0, 0.0), 1.0, 0),
		LayerSet.DIMENSION
	)
	document.add(Entity.make_text(Vector2(1.0, 1.0), "BED"), LayerSet.TEXT)
	# An open shape encloses no ground until the drawer closes it.
	document.add(
		Entity.make_polyline(PackedVector2Array([
			Vector2(0.0, 0.0), Vector2(3.0, 0.0), Vector2(3.0, 1.0),
		]), false),
		LayerSet.NEW_TURF
	)
	var painter := WashPainterScript.new(document, 100.0)
	var seeds: Array[int] = []
	for entry: Dictionary in painter.regions():
		seeds.append(int(entry["seed"]))
	assert(seeds.size() == 2, "expected the bed and the paving, got %s" % [seeds])
	assert(seeds.has(bed))
	assert(seeds.has(paving))
	painter.free()


func test_only_area_kinds_have_outlines() -> void:
	var areas: Array = [
		Entity.make_rectangle(Vector2.ZERO, Vector2(2.0, 2.0)),
		Entity.make_circle(Vector2.ZERO, 2.0),
		Entity.make_regular_polygon(Vector2.ZERO, 2.0, 6),
		Entity.make_polyline(PackedVector2Array([
			Vector2(0.0, 0.0), Vector2(2.0, 0.0), Vector2(2.0, 2.0),
		]), true),
	]
	for entity in areas:
		assert(CadSolidScript.is_area(entity), "kind %d should be an area" % entity.kind)
		assert(CadSolidScript.outline_of(entity).size() >= 3)
	var lines: Array = [
		Entity.make_line(Vector2.ZERO, Vector2(2.0, 0.0)),
		Entity.make_arc(Vector2.ZERO, 2.0, 0.0, PI),
		Entity.make_polyline(PackedVector2Array([
			Vector2(0.0, 0.0), Vector2(2.0, 0.0), Vector2(2.0, 2.0),
		]), false),
		Entity.make_dimension(Vector2.ZERO, Vector2(2.0, 0.0), 1.0, 0),
		Entity.make_text(Vector2.ZERO, "NOTE"),
	]
	for entity in lines:
		assert(not CadSolidScript.is_area(entity), "kind %d is not an area" % entity.kind)
		assert(CadSolidScript.outline_of(entity).is_empty())


func test_an_outline_is_a_ring_that_closes_itself_once() -> void:
	# A sampled circle arrives with its last point equal to its first, and a bed drawn
	# clockwise arrives backwards. Both are fixed here so nobody downstream has to ask.
	var circle := Entity.make_circle(Vector2(1.0, 2.0), 3.0)
	var ring: PackedVector2Array = CadSolidScript.outline_of(circle)
	var sampled: PackedVector2Array = circle.outline()
	assert(ring.size() == sampled.size() - 1, "the closing point was not dropped")
	assert(not ring[0].is_equal_approx(ring[ring.size() - 1]))
	assert(Geom.polygon_signed_area(ring) > 0.0, "the ring is wound backwards")


func test_a_backwards_ring_is_turned_the_right_way_round() -> void:
	var clockwise := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.0, 4.0), Vector2(6.0, 4.0), Vector2(6.0, 0.0),
	])
	assert(Geom.polygon_signed_area(clockwise) < 0.0)
	var ring: PackedVector2Array = CadSolidScript.ring(clockwise)
	assert(Geom.polygon_signed_area(ring) > 0.0)
	# And the area is unchanged, so turning it round moved nothing.
	assert(is_equal_approx(CadSolidScript.area_m2(ring), 24.0))


func test_a_ring_that_crosses_itself_is_refused_with_a_reason() -> void:
	# AC-V9, in the shape the wash needs it: a bow tie has an inside that cannot be
	# filled, and saying so is better than filling one of its halves.
	var bow := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(4.0, 4.0), Vector2(4.0, 0.0), Vector2(0.0, 4.0),
	])
	assert(not CadSolidScript.is_fillable(bow))
	assert(CadSolidScript.refusal_for(bow) != "")
	# A square, by contrast, is fillable and gives no reason against it.
	var square := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(4.0, 0.0), Vector2(4.0, 4.0), Vector2(0.0, 4.0),
	])
	assert(CadSolidScript.is_fillable(square))
	assert(CadSolidScript.refusal_for(square) == "")


func test_two_points_are_not_an_area() -> void:
	var thin: PackedVector2Array = CadSolidScript.ring(
		PackedVector2Array([Vector2(0.0, 0.0), Vector2(2.0, 0.0)])
	)
	assert(thin.is_empty())
	assert(CadSolidScript.refusal_for(thin) != "")
	assert(is_equal_approx(CadSolidScript.area_m2(thin), 0.0))


# --- planting ------------------------------------------------------------------------

## A prop of a known species, placed the way the yard places one.
##
## The real scene, instantiated: a prop's species is its `scene_file_path`, and a node
## that merely claims to be a tree would test this table against itself rather than
## against the prop it describes.
func _prop(scene_path: String, at: Vector2) -> Node3D:
	var scene: PackedScene = load(scene_path)
	var node: Node3D = scene.instantiate()
	node.position = Vector3(at.x, 0.0, at.y)
	add_child(node)
	return node


func test_a_plant_washes_in_its_species_colour() -> void:
	# AC-V23's rule, on the species this project has: the wash colour is the plan
	# palette's colour for the plant's own material.
	assert(PlanStyle.FOLIAGE_WASH.is_equal_approx(
		PlanStyle.COLOURS["res://resources/materials/foliage.tres"]
	))
	assert(PlanStyle.BLOOM_WASH.is_equal_approx(
		PlanStyle.COLOURS["res://resources/materials/flower_pink.tres"]
	))
	# And the real props agree: the tree and the shrub are foliage green because the
	# foliage material is what they are made of, and the flower bed is in bloom.
	var tree := _prop("res://scenes/props/tree.tscn", Vector2.ZERO)
	var shrub := _prop("res://scenes/props/shrub.tscn", Vector2(3.0, 0.0))
	var bed := _prop("res://scenes/props/flower_bed.tscn", Vector2(6.0, 0.0))
	assert(PlanStyle.wash_colour_for(tree) == PlanStyle.FOLIAGE_WASH)
	assert(PlanStyle.wash_colour_for(shrub) == PlanStyle.FOLIAGE_WASH)
	assert(PlanStyle.wash_colour_for(bed) == PlanStyle.BLOOM_WASH)
	assert(PlanStyle.footprint_radius(tree) > PlanStyle.footprint_radius(shrub))
	tree.free()
	shrub.free()
	bed.free()


func test_a_prop_the_style_table_does_not_describe_gets_no_canopy() -> void:
	# The loud option: a plant missing from the table is left out of the colour rather
	# than washed in a guessed grey, because a wrong colour looks deliberate.
	var unknown := Node3D.new()
	add_child(unknown)
	assert(PlanStyle.wash_colour_for(unknown) == Color.TRANSPARENT)
	var painter := WashPainterScript.new(null, 100.0, [unknown] as Array[Node3D])
	assert(painter.canopies().is_empty())
	painter.free()
	unknown.free()


func test_canopies_are_painted_over_the_beds_they_stand_in() -> void:
	# REQ-V4.3. The order is the whole requirement, so the order is what is asserted.
	var document = _document()
	document.add(Entity.make_rectangle(Vector2.ZERO, Vector2(8.0, 6.0)), LayerSet.NEW_BED)
	var tree := _prop("res://scenes/props/tree.tscn", Vector2(2.0, 2.0))
	var shrub := _prop("res://scenes/props/shrub.tscn", Vector2(4.0, 1.0))
	var painter := WashPainterScript.new(document, 100.0, [shrub, tree] as Array[Node3D])
	var regions: Array[Dictionary] = painter.regions()
	assert(regions.size() == 3, "a bed and two canopies, got %d" % regions.size())
	# The bed first, then the bigger canopy before the smaller one, so a shrub sits in
	# front of the tree behind it.
	assert(String(regions[0]["what"]) == String(LayerSet.NEW_BED))
	assert(String(regions[1]["what"]) == String(tree.name))
	assert(String(regions[2]["what"]) == String(shrub.name))
	painter.free()
	tree.free()
	shrub.free()


func test_a_canopy_wash_has_the_shape_the_working_plan_draws() -> void:
	# Found by looking at a painted plan: the beds washed as discs while the working
	# view drew them as oblongs. The colour and the shape come from the same entry, so
	# both agree with the symbol the plan draws.
	var tree := _prop("res://scenes/props/tree.tscn", Vector2.ZERO)
	var bed := _prop("res://scenes/props/flower_bed.tscn", Vector2(6.0, 0.0))
	var painter := WashPainterScript.new(null, 100.0, [tree, bed] as Array[Node3D])
	var canopies: Array[Dictionary] = painter.canopies()
	assert(canopies.size() == 2)
	# Largest first, so the tree comes before the bed.
	var tree_region: PackedVector2Array = canopies[0]["region"]
	var bed_region: PackedVector2Array = canopies[1]["region"]
	# A tree is a disc: every point is the same distance from the middle.
	var tree_size: Vector2 = Geom.points_aabb(tree_region).size
	assert(is_equal_approx(tree_size.x, tree_size.y), "a canopy should be round: %s" % tree_size)
	# A bed is oblong, and oblong the same way the symbol is: wider than it is deep.
	var bed_size: Vector2 = Geom.points_aabb(bed_region).size
	assert(bed_size.x > bed_size.y * 1.5, "a bed should be oblong: %s" % bed_size)
	assert(is_equal_approx(bed_size.x, PlanStyle.footprint_size(bed).x))
	painter.free()
	tree.free()
	bed.free()


func test_a_region_carries_the_seed_of_the_entity_it_came_from() -> void:
	# The wobble is phase 2, but the seed is decided here and it is decided from the
	# entity's id: the same drawing must wobble the same way every frame and every
	# render (REQ-V3.1), and a seed from the frame number would not.
	var document = _document()
	var id: int = document.add(
		Entity.make_rectangle(Vector2.ZERO, Vector2(4.0, 3.0)), LayerSet.NEW_BED
	)
	var first_painter := WashPainterScript.new(document, 100.0)
	var second_painter := WashPainterScript.new(document, 100.0)
	var first: Array[Dictionary] = first_painter.regions()
	var second: Array[Dictionary] = second_painter.regions()
	assert(first.size() == 1)
	assert(int(first[0]["seed"]) == id)
	assert(first[0]["region"] == second[0]["region"])
	assert(int(first[0]["seed"]) == int(second[0]["seed"]))
	# A Node2D owns a canvas item, and a canvas item that outlives its test is a leak
	# the engine reports at exit rather than a test that fails where it happened.
	first_painter.free()
	second_painter.free()


# --- the sheet and the framing --------------------------------------------------------


func test_the_bake_size_is_the_paper_at_the_bake_resolution() -> void:
	var baker := SketchBakerScript.new()
	assert(baker.pixel_size() == Vector2i(2520, 1782))
	baker.texels_per_mm = 3.0
	assert(baker.pixel_size() == Vector2i(1260, 891))
	baker.free()


func test_the_framing_centres_the_drawing_on_the_paper() -> void:
	var bounds := Rect2(Vector2(100.0, 50.0), Vector2(20.0, 10.0))
	var transform: Transform2D = SketchBakerScript.paper_transform(
		bounds, 100.0, SketchBakerScript.PAPER_A3
	)
	var centre: Vector2 = transform * bounds.get_center()
	assert(centre.is_equal_approx(SketchBakerScript.PAPER_A3 * 0.5))
	# Ten metres at 1:100 is a hundred millimetres, which is the whole point of the
	# scale being a number rather than a zoom.
	var corner: Vector2 = transform * bounds.position
	var span: Vector2 = (transform * bounds.end) - corner
	assert(is_equal_approx(span.x, 200.0), str(span))
	assert(is_equal_approx(span.y, 100.0), str(span))


func test_the_same_drawing_lands_in_the_same_place_twice() -> void:
	# AC-V12's cousin for phase 1: the framing is a function of the bounds and the
	# scale, so two builds of one drawing put it in one place.
	var bounds := Rect2(Vector2(-3.0, 7.0), Vector2(12.0, 9.0))
	var first: Transform2D = SketchBakerScript.paper_transform(bounds, 200.0, SketchBakerScript.PAPER_A3)
	var second: Transform2D = SketchBakerScript.paper_transform(bounds, 200.0, SketchBakerScript.PAPER_A3)
	assert(first == second)


func test_a_wash_length_is_a_paper_length() -> void:
	# The bleed is authored in paper millimetres, so it grows with the scale: the same
	# wash must bleed the same distance *on the paper* at 1:200 as at 1:100 bleeds on
	# the paper of a drawing half the size.
	var wash: Dictionary = WashTableScript.wash_for(LayerSet.NEW_BED)
	var at_100_painter := WashPainterScript.new(null, 100.0)
	var at_200_painter := WashPainterScript.new(null, 200.0)
	var at_100: float = at_100_painter.bleed_m(wash)
	var at_200: float = at_200_painter.bleed_m(wash)
	assert(is_equal_approx(at_100, float(wash["bleed_mm"]) * 0.001 * 100.0))
	assert(is_equal_approx(at_200, at_100 * 2.0))
	at_100_painter.free()
	at_200_painter.free()


func test_a_wash_painter_can_be_asked_for_nothing() -> void:
	# The empty document is a real state, and every function here has to survive it
	# rather than pushing an error in a designer's face.
	var painter := WashPainterScript.new(null, 100.0)
	assert(painter.regions().is_empty())
	assert(painter.canopies().is_empty())
	assert(WashTableScript.wash_for(LayerSet.NEW_BED).is_empty() == false)
	painter.free()


# --- the plan that is painted ---------------------------------------------------------


func test_a_scene_with_nothing_in_it_says_so_rather_than_painting() -> void:
	# A person with a new document presses the key and is told why nothing happened,
	# in a sentence, rather than getting a blank sheet and wondering.
	var plan := PaintedPlanScript.new()
	add_child(plan)
	assert(plan.document() == null)
	assert(plan.props().is_empty())
	assert(plan.paint_bounds() == Rect2())
	assert(plan.refusal() != "")
	plan.free()


func test_the_painted_plan_reads_the_same_paper_as_the_working_plan() -> void:
	# One paper colour for both paths, so switching between them does not restyle the
	# sheet under the drawing.
	var plan := PaintedPlanScript.new()
	add_child(plan)
	assert(plan.paper_colour().is_equal_approx(PlanCanvas.PAPER))
	plan.free()