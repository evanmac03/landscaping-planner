class_name CadSolid
extends RefCounted
## Outline, and later solid, from the drawing's own entities (§8.2).
##
## Every outline comes from `DraftEntity.outline()`, the same function the working
## plan, the 3D overlay and the plotted sheet draw from, so a patio's wash, its
## plotted outline and (from phase 3) its 3D slab are the shape that was drawn.
## Nothing here reads an entity's parameter array for itself, which is what keeps
## "the mesh is a picture of the entity" true rather than approximately true
## (REQ-V2.1).
##
## This file grew into slabs and ribbons in phase 3 (§8.3, §8.4); phase 1's washing
## needed only the outline at the top.

const EntityScript := preload("res://scripts/draft/draft_entity.gd")
const Geom := preload("res://scripts/draft/geom2d.gd")

## Entity kinds that enclose ground. An arc, a line or an open polyline encloses
## nothing until the drawer closes it, and an annotation is not ground at all
## (drafting subsystem §4).
const AREAS: Array[int] = [
	EntityScript.Kind.CIRCLE,
	EntityScript.Kind.POLYGON,
	EntityScript.Kind.RECT,
	EntityScript.Kind.REGULAR_POLY,
]

## Fewer points than this and there is no ring: a triangle is the smallest thing
## with an inside.
const MIN_RING_POINTS := 3


## Whether an entity encloses ground.
static func is_area(entity: EntityScript) -> bool:
	return entity != null and AREAS.has(int(entity.kind))


## The closed outline of an area entity, in model metres, as a ring.
##
## Empty for anything that does not enclose ground: refused rather than guessed at,
## because a wash or a slab made from an open outline is a shape the designer never
## drew.
static func outline_of(entity: EntityScript) -> PackedVector2Array:
	if not is_area(entity):
		return PackedVector2Array()
	return ring(entity.outline())


## A ring: the closing duplicate dropped, and the winding made positive.
##
## A sampled circle arrives with its last point equal to its first, and every
## consumer here either triangulates the ring, offsets it or fills it - all three of
## which treat a repeated vertex as a zero-length edge. The winding is fixed here so
## no downstream function has to ask which way round a bed was drawn: positive
## shoelace, which is this project's convention for an area and the direction an
## offset grows outward in.
##
## Degenerate input gives an empty array rather than a small ring, so a caller can
## tell "no area" from "a tiny area" with one check.
static func ring(points: PackedVector2Array) -> PackedVector2Array:
	var out := points
	while out.size() >= 2 and out[out.size() - 1].is_equal_approx(out[0]):
		out = out.slice(0, out.size() - 1)
	if out.size() < MIN_RING_POINTS:
		return PackedVector2Array()
	if Geom.polygon_signed_area(out) < 0.0:
		out.reverse()
	return out


## The area of a ring in square metres, which is what a material quantity is
## measured in. Zero for anything degenerate.
static func area_m2(ring_points: PackedVector2Array) -> float:
	return Geom.polygon_area(ring_points)


## Whether a ring can be filled: enough points, and no edge crossing another.
##
## `Geom.polygon_is_simple` rather than a crossing test written here, because the
## drafting subsystem already refuses a self-intersecting polygon when it is drawn
## and one implementation of "does this cross itself" is one place to be wrong.
static func is_fillable(ring_points: PackedVector2Array) -> bool:
	if ring_points.size() < MIN_RING_POINTS:
		return false
	return Geom.polygon_is_simple(ring_points)


## Why a ring cannot be used, for a message that names the problem rather than
## reporting a count.
static func refusal_for(ring_points: PackedVector2Array) -> String:
	if ring_points.size() < MIN_RING_POINTS:
		return "an outline needs at least %d points and has %d" % [
			MIN_RING_POINTS, ring_points.size(),
		]
	if not Geom.polygon_is_simple(ring_points):
		return "the outline crosses itself"
	if absf(Geom.polygon_signed_area(ring_points)) <= Geom.EPS:
		return "the outline encloses no area"
	return ""


# --- winding, and why it is written down ----------------------------------------------
##
## **Godot's front faces are clockwise**, so a triangle's front normal is *minus* the
## right-hand-rule product of its edges. Every winding in this file is decided here,
## once, and asserted by a test rather than reasoned about at each face — because the
## two ways to get it wrong are invisible in code and very visible in a render:
##
## * a **backwards face is culled**. A patio whose top face is wound downward is not a
##   dark patio, it is a *hole in the ground* with the yard showing through it, and it
##   looks like the slab was never built.
## * a face wound one way with its normal set the other is *lit from behind*: it is
##   visible, and shades as though the sun were underground.
##
## Both are in the first draft of this file's specification, which is why they are
## spelled out.
##
## The ring arrives from `ring()` wound with a **positive** shoelace, which is this
## project's convention for an area. In the plan's own coordinates that means the
## interior of the ring lies to the *left* of each directed edge, so the outward
## normal of an edge `from -> to` is that edge turned right: `(edge.y, 0, -edge.x)`.
## Every face below is wound so that it agrees with that, and the test walks the mesh
## and checks each one.

## The front normal of a triangle, per Godot's clockwise convention.
##
## Not `(b - a).cross(c - a)` — that is the *counter*-clockwise answer, and using it is
## how a solid ends up inside out while looking perfectly correct in the code.
static func front_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	return -((b - a).cross(c - a)).normalized()


# --- solids (§8.3, §8.4) --------------------------------------------------------------


## A slab: a closed outline given thickness, as a mesh of metre UVs.
##
## Returns null and says why when the outline cannot be made solid. Two refusals, both
## of them things a drawing can actually contain: an outline of fewer than three points,
## and a self-intersecting one, which `Geometry2D.triangulate_polygon` answers with an
## empty array rather than a guess (REQ-V8.2).
##
## Three faces, wound by the rules above:
##
## * the **top** at `height_m`, taking the triangulator's own triangle order, which is
##   wound with the ring and so already faces up;
## * the **bottom** at `base_m`, taking the triangulator's order on the *reversed* ring.
##   It has to be reversed here rather than straightened out later: `triangulate_polygon`
##   preserves the winding it is given, so reversing the ring is the whole mechanism.
## * the **sides**, one quad per edge, wound outward.
##
## Normals are set explicitly rather than generated, and `generate_normals()` is *not*
## called: it recomputes every normal from the winding and would overwrite the smooth
## top with one normal per triangle. Sides are flat and the top is smooth, which is what
## a sawn-edged patio looks like (REQ-V8.3).
static func slab(
	loop: PackedVector2Array,
	base_m: float,
	height_m: float,
	inset_m: float = 0.0,
	uv_scale_metres: float = 1.0
) -> ArrayMesh:
	if loop.size() < MIN_RING_POINTS:
		push_error("CadSolid.slab: an outline needs three points, got %d" % loop.size())
		return null
	var pieces: Array[PackedVector2Array] = []
	if is_zero_approx(inset_m):
		pieces.append(loop)
	else:
		# A negative delta insets. Round joins, because a sawn paving edge is round at
		# this scale, and a mitre join overshoots on a sharp corner and can
		# self-intersect the very outline it is meant to be shortening.
		for piece: PackedVector2Array in Geometry2D.offset_polygon(
			loop, -absf(inset_m), Geometry2D.JOIN_ROUND
		):
			if piece.size() >= MIN_RING_POINTS:
				pieces.append(piece)
	if pieces.is_empty():
		push_error("CadSolid.slab: insetting by %.2f m consumed the outline" % inset_m)
		return null

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for piece: PackedVector2Array in pieces:
		var indices: PackedInt32Array = Geometry2D.triangulate_polygon(piece)
		if indices.is_empty():
			# Named, because the drawing can be fixed and a mesh cannot be guessed at.
			push_error("CadSolid.slab: the outline crosses itself; not a valid solid")
			return null
		for index: int in indices:
			if index < 0 or index >= piece.size():
				push_error("CadSolid.slab: the triangulator returned a stray index")
				return null
		# The top, in the triangulator's own order: it is wound with the ring, so its
		# faces already point up.
		for index: int in indices:
			_add_vertex(surface, piece[index], height_m, Vector3.UP, uv_scale_metres)
		# The sides, one quad per edge, wound so the quad's face points outward.
		for edge in piece.size():
			_add_side(
				surface, piece[edge], piece[(edge + 1) % piece.size()],
				base_m, height_m, uv_scale_metres
			)
		# The underside: the same triangles with each one's cornices reversed, so they
		# face down.
		#
		# Not by re-triangulating the *reversed ring*, which is what the specification
		# does and which does not work. `triangulate_polygon` answers with the same
		# triangle sequence whichever order the ring is given in — the index values
		# differ, but the points they name do not, so both windings come back facing the
		# same way and the underside comes out pointing up.
		for tri in range(0, indices.size(), 3):
			for slot in [0, 2, 1]:
				_add_vertex(
					surface, piece[indices[tri + slot]], base_m, Vector3.DOWN,
					uv_scale_metres
				)

	surface.generate_tangents()
	return surface.commit()


## A ribbon: open linework given a width, a base and a height.
##
## A kerb, a lawn edge and a low wall are *lines* in the plan and *solids* in the view.
##
## **One offset, not two.** The specification joins an offset by `+width/2` with an offset
## by `-width/2` and reverses one of them, which reads correctly and is wrong:
## `Geometry2D.offset_polyline` already returns a **closed outline** of the band around
## the line — four points for a straight segment, the whole mitered shape for a bent one.
## Asking for both signs gives two copies of the same loop, and joining them gives an
## outline that crosses itself, which the triangulator then refuses. So the outline is
## asked for once and handed to `slab()`.
##
## The engine's own offset rather than a hand-rolled perpendicular (REQ-V8.4): it already
## answers the mitre-or-round question at a corner, and a hand-rolled one is where
## self-intersections on a tight curve come from.
static func ribbon(
	line: PackedVector2Array,
	width_m: float,
	base_m: float,
	height_m: float,
	uv_scale_metres: float = 1.0
) -> ArrayMesh:
	if line.size() < 2:
		push_error("CadSolid.ribbon: a ribbon needs two points, got %d" % line.size())
		return null
	if width_m <= 0.0:
		push_error("CadSolid.ribbon: a ribbon needs a width, got %.2f m" % width_m)
		return null
	var offset: Array[PackedVector2Array] = Geometry2D.offset_polyline(
		line, width_m * 0.5, Geometry2D.JOIN_ROUND, Geometry2D.END_BUTT
	)
	if offset.is_empty():
		push_error("CadSolid.ribbon: offsetting by %.2f m consumed the line" % (width_m * 0.5))
		return null
	# A line that doubles back on itself offsets into more than one piece. The largest is
	# the band; the rest is a sliver at the fold, and a sliver is not worth a solid.
	var band: PackedVector2Array = offset[0]
	for piece: PackedVector2Array in offset:
		if absf(Geom.polygon_signed_area(piece)) > absf(Geom.polygon_signed_area(band)):
			band = piece
	# `ring()` because the loop's winding comes from the engine and every face above is
	# wound from the assumption that the shoelace is positive.
	return slab(ring(band), base_m, height_m, 0.0, uv_scale_metres)


## One vertex, with its normal set explicitly and a UV in metres.
##
## A UV in **metres** rather than 0..1 because the material is world-triplanar and
## `uv1_scale` is a repeat per metre: an unnormalised UV is what lets paving keep its
## size whatever the patio is scaled to (REQ-V5.1).
static func _add_vertex(
	surface: SurfaceTool, point: Vector2, y: float, normal: Vector3, uv_scale: float
) -> void:
	surface.set_normal(normal)
	surface.set_uv(point / uv_scale)
	surface.add_vertex(Vector3(point.x, y, point.y))


## Two triangles standing on edge between two points of the outline.
##
## Six vertices, not four. `PRIMITIVE_TRIANGLES` needs three corners per triangle and
## the two triangles of a quad share an edge, so the corners are (A, B, C) and (A, C, D)
## — six vertices naming four places. Four vertices would be a triangle *strip*, and the
## mesh that comes out of it has a vertex count that is not a multiple of three: the
## renderer drops the odd ones and `create_trimesh_collision()` refuses the surface
## outright, which is how this was found.
##
## A = (from, base), B = (to, base), C = (to, top), D = (from, top), in that order. That
## order makes each triangle's face point *outward*, and the face is what the renderer
## culls on: the order (A, D, C, B) — the one the specification's loop happens to
## generate — makes every wall of a raised bed face inward, so the bed is a hole.
static func _add_side(
	surface: SurfaceTool, from: Vector2, to: Vector2,
	base_m: float, height_m: float, uv_scale: float
) -> void:
	var edge := to - from
	if edge.length() <= Geom.EPS:
		return
	# The outward normal of a positive-shoelace ring is its edge turned right.
	var normal := Vector3(edge.y, 0.0, -edge.x).normalized()
	var run: float = edge.length() / uv_scale
	for corner in [0, 1, 2, 0, 2, 3]:
		var at_end: bool = corner == 1 or corner == 2
		var at_top: bool = corner == 2 or corner == 3
		var point: Vector2 = to if at_end else from
		var y: float = height_m if at_top else base_m
		surface.set_normal(normal)
		surface.set_uv(Vector2(run if at_end else 0.0, y))
		surface.add_vertex(Vector3(point.x, y, point.y))


# --- reading a built mesh back, which is how the winding is tested --------------------


## Every triangle's front normal, in the order the triangles stand in the mesh.
##
## This exists so the test can ask the *mesh* what it faces rather than asking this
## file's constants what they meant. A fact asserted against the thing built is worth
## more than a fact asserted against the code that built it.
static func face_normals(mesh: ArrayMesh) -> PackedVector3Array:
	var out := PackedVector3Array()
	if mesh == null or mesh.get_surface_count() == 0:
		return out
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]
	var count: int = indices.size() if indices.size() > 0 else verts.size()
	for tri in range(0, count - count % 3, 3):
		var a: Vector3 = verts[indices[tri] if indices.size() > 0 else tri]
		var b: Vector3 = verts[indices[tri + 1] if indices.size() > 0 else tri + 1]
		var c: Vector3 = verts[indices[tri + 2] if indices.size() > 0 else tri + 2]
		out.append(front_normal(a, b, c))
	return out


## The triangles of a built mesh, as corners.
static func faces(mesh: ArrayMesh) -> Array[Array]:
	var out: Array[Array] = []
	if mesh == null or mesh.get_surface_count() == 0:
		return out
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for tri in range(0, verts.size() - verts.size() % 3, 3):
		out.append([verts[tri], verts[tri + 1], verts[tri + 2]])
	return out