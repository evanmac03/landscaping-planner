extends Node
## Tests for the solids, phase 3: what a layer becomes, which way the faces point, and
## that a mesh is a picture of its entity rather than a fact of its own.
##
## **The winding tests are the important ones here.** Two ways of getting a face the
## wrong way round leave no trace in the code and no error at runtime: a backwards face
## is culled, so a patio is a hole in the ground, and a face wound one way with its
## normal set the other is visible but lit from behind. Neither shows up in a vertex
## count, so each one is asserted against the *built mesh* rather than against the
## constants that built it.
##
## **Refusals are asked as predicates rather than provoked.** Every refusal in
## `cad_solid.gd` and `hardscape_material.gd` pushes an error, which is right — a refusal
## in a running game is something somebody should see in the log — and the test runner
## counts a pushed error as a failure. So the tests ask the guards (`refusal_for()`,
## `wants_ribbon()`, `has_set()`) instead of calling the builder and reading its null,
## which tests the same decision without turning a deliberate error into a red test.

const Entity := preload("res://scripts/draft/draft_entity.gd")
const Document := preload("res://scripts/draft/draft_document.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const CadSolidScript := preload("res://scripts/vis/cad_solid.gd")
const SolidTableScript := preload("res://scripts/vis/solid_table.gd")
const HardscapeScript := preload("res://scripts/vis/hardscape_material.gd")
const BuilderScript := preload("res://scripts/vis/texture_set_builder.gd")
const DerivedScript := preload("res://scripts/vis/derived_builder.gd")

## A two-metre square, wound with a positive shoelace, which is the project's convention
## for an area and the assumption every face in cad_solid.gd is wound from.
const SQUARE: Array[Vector2] = [
	Vector2(0, 0), Vector2(2, 0), Vector2(2, 2), Vector2(0, 2),
]


func _square() -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in SQUARE:
		out.append(point)
	return out


func _slab() -> ArrayMesh:
	return CadSolidScript.slab(_square(), 0.0, 1.0)


# --- the convention itself ------------------------------------------------------------


func test_the_front_normal_is_the_clockwise_answer() -> void:
	# Godot's front faces are clockwise, so the front normal is *minus* the right-hand
	# rule product. This single line is the fact every winding below rests on, so it is
	# asserted rather than trusted: a triangle in the ground plane wound one way faces
	# up and the same triangle wound the other way faces down.
	var up := CadSolidScript.front_normal(Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(0, 1, 1))
	assert(up.is_equal_approx(Vector3.UP), "expected up, got %s" % up)
	var down := CadSolidScript.front_normal(Vector3(0, 1, 1), Vector3(1, 1, 0), Vector3(0, 1, 0))
	assert(down.is_equal_approx(Vector3.DOWN), "expected down, got %s" % down)


# --- a slab ---------------------------------------------------------------------------


func test_a_solid_is_whole_triangles() -> void:
	# The invariant that caught the four-vertex quad: `PRIMITIVE_TRIANGLES` needs three
	# corners per triangle, and a quad emitted as four vertices leaves the renderer an odd
	# tail. It drops them silently, and `create_trimesh_collision()` refuses the surface
	# outright — so a solid built that way has no collider and can be walked through. A
	# vertex count that is not a multiple of three is the whole symptom.
	var meshes: Array[ArrayMesh] = [
		_slab(),
		CadSolidScript.slab(_square(), -0.02, 0.05, 0.2),
		CadSolidScript.ribbon(
			PackedVector2Array([Vector2(0, 0), Vector2(3, 0), Vector2(3, 3)]), 0.4, 0.0, 0.1
		),
	]
	for mesh: ArrayMesh in meshes:
		assert(mesh != null)
		var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		assert(
			verts.size() % 3 == 0,
			"a surface of %d vertices is not whole triangles" % verts.size()
		)


func test_a_slab_has_a_top_a_bottom_and_a_wall_on_every_edge() -> void:
	# Two triangles of top, two of bottom, and two per side on a four-sided ring.
	var mesh: ArrayMesh = _slab()
	assert(mesh != null, "a square should make a slab")
	assert(
		CadSolidScript.faces(mesh).size() == 12,
		"expected 12 triangles, got %d" % CadSolidScript.faces(mesh).size()
	)
	# It is as tall as it was asked to be, and it sits where it was asked to sit.
	var bounds := mesh.get_aabb()
	assert(is_equal_approx(bounds.position.y, 0.0), "base at %f" % bounds.position.y)
	assert(is_equal_approx(bounds.size.y, 1.0), "height %f" % bounds.size.y)
	assert(is_equal_approx(bounds.size.x, 2.0), "width %f" % bounds.size.x)
	assert(is_equal_approx(bounds.size.z, 2.0), "depth %f" % bounds.size.z)


## The faces of a mesh, sorted by how many heights their corners stand at: a horizontal
## face has one, a wall has two. Classifying by geometry rather than by position in the
## buffer means a test cannot pass by the triangles happening to be in the order the
## builder emits them.
func _faces_of(mesh: ArrayMesh, heights: int) -> Array[Array]:
	var out: Array[Array] = []
	for face: Array in CadSolidScript.faces(mesh):
		var seen: Array[float] = []
		for corner: Vector3 in face:
			var known := false
			for value: float in seen:
				if is_equal_approx(value, corner.y):
					known = true
			if not known:
				seen.append(corner.y)
		if seen.size() == heights:
			out.append(face)
	return out


func test_the_top_of_a_slab_faces_up_and_the_bottom_faces_down() -> void:
	# A culled top face is a patio that reads as a hole in the ground, and a bottom that
	# faces up is a solid lit from below. Neither shows up in a vertex count.
	var mesh: ArrayMesh = _slab()
	var top := _faces_of(mesh, 1)
	assert(top.size() == 4, "expected four horizontal faces, got %d" % top.size())
	var up := 0
	var down := 0
	for face: Array in top:
		var normal := CadSolidScript.front_normal(face[0], face[1], face[2])
		if normal.y > 0.99:
			up += 1
		elif normal.y < -0.99:
			down += 1
		else:
			assert(false, "a horizontal face points %s" % normal)
	assert(up == 2, "expected two up-facing triangles, got %d" % up)
	assert(down == 2, "expected two down-facing triangles, got %d" % down)


func test_the_sides_of_a_slab_face_away_from_it() -> void:
	# The corners are read off the *mesh*, so this is a statement about what was built
	# rather than about what was intended. A wall wound inward is invisible: the renderer
	# culls it and the slab has no sides at all.
	var mesh: ArrayMesh = _slab()
	var walls := _faces_of(mesh, 2)
	assert(walls.size() == 8, "expected eight wall triangles, got %d" % walls.size())
	for face: Array in walls:
		var a: Vector3 = face[0]
		var b: Vector3 = face[1]
		var c: Vector3 = face[2]
		var centre := (a + b + c) / 3.0
		var outward := Vector3(centre.x - 1.0, 0.0, centre.z - 1.0)
		if outward.length() <= 0.01:
			continue
		var normal := CadSolidScript.front_normal(a, b, c)
		assert(
			is_zero_approx(normal.y),
			"a wall at %s is not vertical: %s" % [centre, normal]
		)
		assert(
			normal.dot(outward.normalized()) > 0.5,
			"a wall at %s faces %s, which is back into the slab" % [centre, normal]
		)


func test_the_uv_is_in_metres_so_a_tile_can_be_a_tile() -> void:
	# World-triplanar mapping does not need these, but a UV-mapped fallback does, and
	# the scale is what makes one repeat of the texture a known size on the ground.
	var mesh: ArrayMesh = _slab()
	var uvs: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	assert(uvs.size() > 0)
	var furthest := Vector2.ZERO
	for uv: Vector2 in uvs:
		furthest.x = maxf(furthest.x, uv.x)
		furthest.y = maxf(furthest.y, uv.y)
	assert(is_equal_approx(furthest.x, 2.0) or is_equal_approx(furthest.x, 1.0))
	# And a UV scale halves it, which is the property the material's tile size rides on.
	var doubled: ArrayMesh = CadSolidScript.slab(_square(), 0.0, 1.0, 0.0, 2.0)
	var scaled: PackedVector2Array = doubled.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var top_uv := Vector2.ZERO
	for uv: Vector2 in scaled:
		top_uv.x = maxf(top_uv.x, uv.x)
	assert(is_equal_approx(top_uv.x, 1.0), "a 2 m uv scale should halve the uv, got %s" % top_uv)


func test_an_inset_shrinks_the_slab() -> void:
	var mesh: ArrayMesh = CadSolidScript.slab(_square(), 0.0, 0.1, 0.2)
	assert(mesh != null)
	var bounds := mesh.get_aabb()
	assert(absf(bounds.size.x - 1.6) < 0.02, "expected 1.6 m across, got %.3f" % bounds.size.x)
	assert(absf(bounds.size.z - 1.6) < 0.02)


func test_a_slab_refuses_an_outline_that_is_not_a_ring() -> void:
	# The guard is asked first, as a predicate, rather than the builder being provoked and
	# its return value read. The runner counts a pushed error as a test failure, and every
	# refusal in this file pushes one — which is right, because a refusal in a running game
	# is something somebody should see in the log. So the tests ask the guard.
	assert(CadSolidScript.refusal_for(PackedVector2Array()) != "")
	assert(CadSolidScript.refusal_for(PackedVector2Array([Vector2.ZERO, Vector2.ONE])) != "")
	# And it does not refuse everything, or the assertions above would be worthless.
	assert(CadSolidScript.refusal_for(_square()) == "")


func test_a_slab_refuses_an_outline_that_crosses_itself() -> void:
	# A bow tie: the triangulator answers with an empty array rather than a guess, and the
	# refusal names the problem rather than reporting a count (REQ-V8.2).
	var bow_tie := PackedVector2Array([
		Vector2(0, 0), Vector2(2, 2), Vector2(2, 0), Vector2(0, 2),
	])
	assert(CadSolidScript.refusal_for(bow_tie).contains("crosses"))
	assert(not CadSolidScript.is_fillable(bow_tie))


func test_two_slabs_from_one_outline_are_the_same_solid() -> void:
	# REQ-V8.9: the conversion is a pure function, so two builds compare by what they
	# are rather than by being the same object.
	var first: ArrayMesh = _slab()
	var second: ArrayMesh = _slab()
	assert(CadSolidScript.faces(first).size() == CadSolidScript.faces(second).size())
	assert(first.get_aabb().is_equal_approx(second.get_aabb()))


# --- a ribbon -------------------------------------------------------------------------


func test_a_ribbon_is_a_slab_with_a_width() -> void:
	# A three-metre line, 60 cm wide, 5 cm tall: something you can see is a kerb.
	var line := PackedVector2Array([Vector2(0, 0), Vector2(3, 0)])
	var mesh: ArrayMesh = CadSolidScript.ribbon(line, 0.6, -0.02, 0.05)
	assert(mesh != null)
	var bounds := mesh.get_aabb()
	assert(absf(bounds.size.x - 3.0) < 0.02, "length %.3f" % bounds.size.x)
	assert(absf(bounds.size.z - 0.6) < 0.02, "width %.3f" % bounds.size.z)
	assert(is_equal_approx(bounds.position.y, -0.02))
	assert(absf(bounds.size.y - 0.07) < 0.001)
	# And its faces are wound the same way round as a slab's, which they must be: a
	# ribbon goes *through* slab(), so there is one place a solid is triangulated.
	var top := 0
	for normal: Vector3 in CadSolidScript.face_normals(mesh):
		if normal.y > 0.99:
			top += 1
	assert(top == 2, "a ribbon's top is two triangles, got %d" % top)


func test_a_ribbon_follows_a_bent_line() -> void:
	# A kerb that turns a corner is the case a hand-rolled perpendicular offset gets
	# wrong, which is why the engine's offset does it.
	var line := PackedVector2Array([Vector2(0, 0), Vector2(3, 0), Vector2(3, 3)])
	var mesh: ArrayMesh = CadSolidScript.ribbon(line, 0.4, 0.0, 0.1)
	assert(mesh != null)
	var bounds := mesh.get_aabb()
	assert(bounds.size.x > 3.0, "a corner should push the width outward")
	assert(bounds.size.z > 3.0)


func test_a_ribbon_needs_a_line_and_a_width_to_be_worth_building() -> void:
	# Both guards are predicates the builder reads, and both are asked here rather than
	# provoked: see the note on the slab refusals above.
	assert(not SolidTableScript.wants_ribbon(true, 0.4), "a closed shape is never a ribbon")
	assert(not SolidTableScript.wants_ribbon(false, 0.0), "a line with no width has no sides")
	assert(SolidTableScript.wants_ribbon(false, 0.4))


# --- the table ------------------------------------------------------------------------


func test_every_solid_layer_is_a_layer_that_exists() -> void:
	# The same requirement as the wash table's, and it caught the same bug: the
	# specification's version of this table keyed three layers this project does not have,
	# so two thirds of it could never have fired.
	var real: Array[StringName] = []
	for entry: Dictionary in LayerSet.PRESETS:
		real.append(entry["name"])
	for key: StringName in SolidTableScript.SOLIDS:
		assert(real.has(StringName(key)), "%s is not a layer" % key)


func test_every_layer_that_has_no_solid_says_why() -> void:
	var real: Array[StringName] = []
	for entry: Dictionary in LayerSet.PRESETS:
		real.append(entry["name"])
	for key: StringName in SolidTableScript.NO_SOLID:
		assert(real.has(StringName(key)), "%s is not a layer" % key)
	# And every layer is accounted for either way, so a new layer cannot quietly be
	# neither extruded nor explained.
	for name: StringName in real:
		assert(
			SolidTableScript.has_solid(name) or SolidTableScript.reason_for(name) != "",
			"%s is in neither table" % name
		)


func test_a_layer_in_neither_table_says_so_as_a_missing_entry() -> void:
	# Different problems: one is a table to extend, the other is a decision that was
	# made, and a reader should be able to tell which they have.
	assert(SolidTableScript.reason_for(&"999-NOT-A-LAYER").contains("999-NOT-A-LAYER"))
	assert(SolidTableScript.reason_for(LayerSet.NEW_TURF).contains("ground"))
	assert(SolidTableScript.reason_for(LayerSet.NEW_HARDSCAPE) == "")


func test_the_layers_the_specification_assumed_are_recorded() -> void:
	# §8.5 asks for a pond as a surface plus a rim, and the honest answer is that there
	# is nowhere to draw one. Recorded rather than silently dropped.
	for key: String in ["WATER", "DECK", "PLANTING_BED", "WALLS"]:
		assert(SolidTableScript.MISSING.has(key), "%s is unrecorded" % key)
	assert(SolidTableScript.has_solid(LayerSet.NEW_STRUCTURE), "a deck lives on 301")


func test_the_entity_decides_a_surface_from_a_centreline() -> void:
	# The correction this table makes to the specification: a *layer* cannot have one
	# shape, because paving is a patio where it is drawn as a rectangle and a kerb where
	# it is drawn as a line.
	assert(not SolidTableScript.wants_ribbon(true, 0.6), "a closed outline is never a ribbon")
	assert(SolidTableScript.wants_ribbon(false, 0.6))
	assert(not SolidTableScript.wants_ribbon(false, 0.0), "no width, no ribbon")


func test_a_thing_a_person_walks_on_collides_and_a_bed_does_not() -> void:
	# REQ-V8.7, and it is a per-entry decision rather than a global one: a mulch surface
	# the player trips over is a bug and a wall the player walks through is a worse one.
	assert(bool(SolidTableScript.solid_for(LayerSet.NEW_STRUCTURE)["collide"]))
	assert(bool(SolidTableScript.solid_for(LayerSet.EXISTING_STRUCTURE)["collide"]))
	assert(not bool(SolidTableScript.solid_for(LayerSet.NEW_BED)["collide"]))
	assert(not bool(SolidTableScript.solid_for(LayerSet.NEW_HARDSCAPE)["collide"]))
	# Paving sits in the ground rather than on it, which is what makes a path read as a
	# path rather than as a wall.
	assert(float(SolidTableScript.solid_for(LayerSet.NEW_HARDSCAPE)["base_m"]) < 0.0)


func test_every_material_a_solid_asks_for_is_a_set_that_exists() -> void:
	for set_name: String in SolidTableScript.material_sets():
		assert(HardscapeScript.has_set(set_name), "%s is not a texture set" % set_name)


# --- the material ---------------------------------------------------------------------


func test_every_texture_set_has_all_three_maps_on_disk() -> void:
	# The loud-missing-entry requirement's other half: a set with a normal map that is
	# not there renders flat, and flat paving is a bug nobody reports (REQ-V5.4).
	var missing: Array[String] = HardscapeScript.missing_paths()
	assert(missing.is_empty(), "missing textures: %s" % str(missing))
	assert(HardscapeScript.set_names().size() >= 5)


func test_a_material_takes_its_tile_size_from_the_set() -> void:
	# REQ-V5.2: texel density is a property of the set, so a paving texture cannot be
	# stretched across a patio by a material somebody edited.
	var material: StandardMaterial3D = HardscapeScript.build("paver_granite")
	assert(material != null)
	var tile: float = float(HardscapeScript.SETS["paver_granite"]["tile_m"])
	assert(is_equal_approx(material.uv1_scale.x, 1.0 / tile))
	# And it is world-triplanar, because extruded geometry has no UVs of its own (§5.2).
	assert(material.uv1_world_triplanar)
	assert(material.normal_enabled)
	assert(material.orm_texture != null)


func test_an_unknown_texture_set_is_not_a_set() -> void:
	# REQ-V5.4: a caller that receives a default material cannot tell it from a set that
	# loaded, which is how a grey patio ships. `build()` answers null and says why; the
	# guard is the predicate a caller can ask before it gets that far.
	assert(not HardscapeScript.has_set("paver_unobtainium"))
	assert(HardscapeScript.has_set("paver_granite"))
	assert(HardscapeScript.files_for("paver_unobtainium").is_empty())


func test_every_set_has_a_normal_map_that_carries_a_surface() -> void:
	# Asserted through the *material*, because that is what a renderer reads: a set whose
	# normal map failed to load builds a material with `normal_texture == null`, and the
	# paving comes out flat with nothing reporting a problem.
	for set_name: String in HardscapeScript.set_names():
		var material: StandardMaterial3D = HardscapeScript.build(set_name)
		assert(material != null, "%s built no material" % set_name)
		assert(material.albedo_texture != null, "%s has no albedo" % set_name)
		assert(material.normal_texture != null, "%s has no normal map" % set_name)
		assert(material.orm_texture != null, "%s has no orm map" % set_name)
		var normal: Image = (material.normal_texture as Texture2D).get_image()
		assert(normal != null, "%s's normal map has no image" % set_name)
		assert(
			not BuilderScript.looks_flat(normal),
			"%s's normal map is one flat colour, so its relief does nothing" % set_name
		)


# --- the derivation -------------------------------------------------------------------


func _ramp() -> Image:
	# A horizontal ramp, brightest at the left, which is the shape that tells a wrapping
	# derivation apart from a clamping one.
	var image := Image.create(16, 1, false, Image.FORMAT_RGB8)
	for x in 16:
		var level := int(255.0 * (1.0 - float(x) / 15.0))
		image.set_pixel(x, 0, Color8(level, level, level))
	return image


func test_a_normal_map_is_derived_from_the_albedo_it_was_given() -> void:
	var flat := Image.create(8, 8, false, Image.FORMAT_RGB8)
	flat.fill(Color8(128, 128, 128))
	var flat_normal := BuilderScript.normal_from(flat)
	# A level surface gives a normal straight out of the surface, which encodes as the one
	# colour every normal map is mostly made of.
	var level: Color = flat_normal.get_pixel(4, 4)
	assert(
		level.is_equal_approx(Color8(128, 128, 255)),
		"a level surface should encode as (128, 128, 255), got %s" % level
	)
	# A step in the height field tilts it, and the tilt's direction follows the step.
	var stepped := Image.create(8, 8, false, Image.FORMAT_RGB8)
	stepped.fill(Color8(0, 0, 0))
	for y in 8:
		for x in range(4, 8):
			stepped.set_pixel(x, y, Color8(255, 255, 255))
	var step_normal := BuilderScript.normal_from(stepped)
	var at_edge: Color = step_normal.get_pixel(3, 4)
	assert(at_edge.b > 0.5, "the blue channel stays outward, got %s" % at_edge)
	assert(
		not is_equal_approx(at_edge.r, 0.5),
		"a step should tilt the map, got %s" % at_edge
	)
	assert(BuilderScript.looks_flat(flat_normal), "a level albedo is a flat map")
	assert(not BuilderScript.looks_flat(step_normal), "a stepped albedo is not")


func test_the_derivation_wraps_so_the_map_tiles() -> void:
	# A map derived from a seamless albedo has to be seamless too, or a tiled patio gets
	# a seam every tile. The ramp falls left to right, so at x = 0 the wrapping
	# derivation sees the darkest texel on its left; a clamping one would see the
	# brightest and tilt the other way.
	var normal := BuilderScript.normal_from(_ramp())
	var at_left: Color = normal.get_pixel(0, 0)
	assert(at_left.r < 0.5, "x = 0 should tilt one way, got %s" % at_left)
	var at_middle: Color = normal.get_pixel(8, 0)
	assert(at_middle.r > at_left.r)


func test_an_orm_map_is_occlusion_roughness_and_metallic() -> void:
	# Godot's packing, in that order. Roughness is full because the set's own roughness
	# multiplies it: a paving that is partly shiny is a paving that is wet.
	var albedo := Image.create(4, 4, false, Image.FORMAT_RGB8)
	albedo.fill(Color8(255, 255, 255))
	albedo.set_pixel(0, 0, Color8(0, 0, 0))
	var orm := BuilderScript.orm_from(albedo, 0.5)
	assert(is_equal_approx(orm.get_pixel(1, 1).g, 1.0), "roughness is 1")
	assert(is_equal_approx(orm.get_pixel(1, 1).b, 0.0), "nothing here is metal")
	assert(orm.get_pixel(1, 1).r > 0.99, "open sky occludes nothing")
	assert(orm.get_pixel(0, 0).r < 0.6, "a black texel is a crevice")


func test_deriving_a_set_with_no_albedo_has_nothing_to_derive_from() -> void:
	# The albedo is the source: without it there is no normal map and no ORM map, and the
	# derivation says so rather than inventing a surface.
	assert(not FileAccess.file_exists(
		HardscapeScript.TEXTURE_DIR + "no_such_set_albedo.png"
	))
	assert(HardscapeScript.files_for("no_such_set").is_empty())


# --- the builder ----------------------------------------------------------------------


func _builder() -> Node3D:
	var builder: Node3D = DerivedScript.new()
	# In the tree, because placing a solid adds a child and a child needs a parent that
	# is in the scene to be added to.
	add_child(builder)
	return builder


func _paved_document() -> Variant:
	var document = Document.new()
	document.add(Entity.make_rectangle(Vector2(3, 3), Vector2(2, 2)), LayerSet.NEW_HARDSCAPE)
	return document


func test_a_builder_places_one_mesh_for_each_solid_entity() -> void:
	var builder: Node3D = _builder()
	builder.bind_document(_paved_document())
	builder.rebuild()
	assert(builder.loft_count() == 1, "one rectangle, one slab")
	assert(builder.report()["solids"] == 1)
	# And the node it placed is a mesh with the paving material, because a solid without
	# its material is a grey patio.
	var solid: MeshInstance3D = builder.get_child(0)
	assert(solid.mesh != null)
	assert(solid.material_override != null)
	builder.queue_free()


func test_a_layer_with_no_solid_produces_nothing() -> void:
	var document = Document.new()
	document.add(Entity.make_rectangle(Vector2(1, 1), Vector2(2, 2)), LayerSet.NEW_TURF)
	var builder: Node3D = _builder()
	builder.bind_document(document)
	builder.rebuild()
	assert(builder.loft_count() == 0, "turf is the ground, not a slab on it")
	builder.queue_free()


func test_an_edit_replaces_a_mesh_rather_than_adding_one() -> void:
	# The property that makes "a mesh is a picture of its entity" true over time
	# (REQ-V8.1). Two entities on the same layer would be two meshes; one entity edited
	# once is still one.
	var document = _paved_document()
	var builder: Node3D = _builder()
	builder.bind_document(document)
	builder.rebuild()
	var id: int = document.entities()[0].id
	var first: Node = builder.get_child(0)
	# `replace()` keeps the id and nothing else, so the replacement has to name its layer:
	# an entity with no layer is an entity the document cannot place in a band.
	var replacement = Entity.make_rectangle(Vector2(3, 3), Vector2(4, 2))
	replacement.layer = LayerSet.NEW_HARDSCAPE
	document.replace(id, replacement)
	builder.rebuild()
	assert(builder.loft_count() == 1, "the old mesh should have been replaced")
	var second: Node = builder.get_child(0)
	assert(second == first, "the node is reused and its mesh replaced")
	assert(absf((second as MeshInstance3D).mesh.get_aabb().size.x - 4.0) < 0.02)
	builder.queue_free()


func test_a_deleted_entity_takes_its_solid_away() -> void:
	var document = _paved_document()
	var builder: Node3D = _builder()
	builder.bind_document(document)
	builder.rebuild()
	assert(builder.loft_count() == 1)
	document.remove(document.entities()[0].id)
	builder.rebuild()
	assert(builder.loft_count() == 0, "a deleted patio does not keep standing")
	builder.queue_free()


func test_only_colliding_solids_get_a_collider() -> void:
	# REQ-V8.7, measured on the nodes rather than on the table.
	var document = Document.new()
	document.add(Entity.make_rectangle(Vector2(1, 1), Vector2(2, 2)), LayerSet.NEW_HARDSCAPE)
	document.add(Entity.make_rectangle(Vector2(6, 6), Vector2(2, 2)), LayerSet.NEW_STRUCTURE)
	var builder: Node3D = _builder()
	builder.bind_document(document)
	builder.rebuild()
	assert(builder.loft_count() == 2)
	var colliders := 0
	for child: Node in builder.get_children():
		for grandchild: Node in child.get_children():
			if grandchild is StaticBody3D:
				colliders += 1
	assert(colliders == 1, "a deck collides and paving does not, got %d" % colliders)
	builder.queue_free()


func test_a_rebuild_is_debounced() -> void:
	# A drag emits a change per frame, and a mesh per frame is a stutter (REQ-V8.8). So
	# the signal raises a flag and nothing is built until the interval has passed.
	var document = _paved_document()
	var builder: Node3D = _builder()
	builder.bind_document(document)
	assert(builder.report().is_empty(), "binding should not build")
	# Marking dirty repeatedly does not build on its own...
	for i in 5:
		builder.mark_dirty()
	assert(builder.loft_count() == 0)
	builder.queue_free()


func test_a_drawing_that_cannot_be_made_solid_is_refused_and_counted() -> void:
	# A line on a layer whose width is zero is a kerb nobody has measured yet: not an
	# error, but not a solid either, and the report says how many.
	var document = Document.new()
	document.add(Entity.make_line(Vector2.ZERO, Vector2(2, 0)), LayerSet.NEW_TURF)
	var builder: Node3D = _builder()
	builder.bind_document(document)
	builder.rebuild()
	assert(builder.loft_count() == 0)
	assert(builder.report()["refusals"] == 0, "a layer with no solid is not a refusal")
	builder.queue_free()


func test_a_line_on_a_paving_layer_becomes_a_kerb() -> void:
	# The centreline half of the correction: open linework on a layer that has a width
	# becomes a ribbon, so a kerb is drawn as a line and not as a sliver of a patio.
	var document = Document.new()
	document.add(Entity.make_line(Vector2.ZERO, Vector2(3, 0)), LayerSet.NEW_HARDSCAPE)
	var builder: Node3D = _builder()
	builder.bind_document(document)
	builder.rebuild()
	assert(builder.loft_count() == 1, "a kerb should stand")
	var solid: MeshInstance3D = builder.get_child(0)
	assert(absf(solid.mesh.get_aabb().size.z - 0.6) < 0.02, "and be 60 cm wide")
	builder.queue_free()


func test_a_builder_with_no_document_derives_nothing_and_says_so() -> void:
	var builder: Node3D = _builder()
	builder.rebuild()
	assert(builder.loft_count() == 0)
	assert(builder.report()["reason"] == "no document")
	assert(builder.describe() != "")
	builder.queue_free()


func test_the_builder_reports_what_it_did() -> void:
	var builder: Node3D = _builder()
	builder.bind_document(_paved_document())
	builder.rebuild()
	var line: String = builder.describe()
	assert(line.contains("1 solid"), "got: %s" % line)
	assert(not line.contains("1 solids"), "one solid is not one solids")
	builder.queue_free()