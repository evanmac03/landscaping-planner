class_name DraftEdit
extends RefCounted
## The editing operations a drawing needs on geometry that already exists:
## offset, trim, extend and fillet.
##
## Every function is static and returns *new* entities; nothing here mutates its
## arguments, and nothing here touches a document. Editing is a replacement, and
## the caller decides how the replacement is recorded - one undo step, or three.
##
## A refusal is a reason string in a result dictionary rather than an exception or
## a null, so a tool can put it on the status line the way every other refusal in
## the drafting subsystem is spoken. An operation that legitimately produces
## nothing (an inward offset that closes the shape away to nothing) returns an
## empty list with no reason, which is a different answer from "could not".

const Geom := preload("res://scripts/draft/geom2d.gd")
const EntityScript := preload("res://scripts/draft/draft_entity.gd")

## Below this a distance is not a distance, and offsetting by it is a no-op.
const MIN_DISTANCE := 1e-6
## A fillet radius has to be a real radius, and its tangent construction divides
## by the sine and tangent of half the corner, both of which vanish at a straight
## corner.
const MIN_RADIUS := 1e-6


# --- offset ---------------------------------------------------------------------------


## Offset one entity by a signed distance.
##
## For an open shape (a line, a polyline, an arc) a positive distance offsets to
## the *left* of the direction of travel, which is where a one-sided offset has a
## side at all. For a closed shape (a circle, a rectangle, a polygon) a positive
## distance offsets *outward*, which is what "make the bed 0.2 m bigger" means.
##
## Returns `{ok, reason, entities}`. `entities` may hold more than one shape: an
## inward offset of a ring that pinches in two produces two rings, and a closed
## ring offset past its own half-width produces none.
static func offset(entity, distance: float) -> Dictionary:
	if entity == null:
		return _failed("there is nothing to offset")
	if absf(distance) <= MIN_DISTANCE:
		return _failed("offset by nothing is nothing")
	match entity.kind:
		EntityScript.Kind.LINE:
			var a: Vector2 = entity.point(0)
			var b: Vector2 = entity.point(1)
			var direction := b - a
			if direction.length() <= MIN_DISTANCE:
				return _failed("a line of no length has no side to offset to")
			var normal := Vector2(-direction.y, direction.x).normalized() * distance
			return _ok([EntityScript.make_line(a + normal, b + normal)])
		EntityScript.Kind.CIRCLE:
			var radius: float = entity.params[2] + distance
			if radius <= MIN_DISTANCE:
				return _ok([])
			return _ok([EntityScript.make_circle(Vector2(entity.params[0], entity.params[1]), radius)])
		EntityScript.Kind.ARC:
			var arc_radius: float = entity.params[2] + distance
			if arc_radius <= MIN_DISTANCE:
				return _ok([])
			return _ok([EntityScript.make_arc(
				Vector2(entity.params[0], entity.params[1]),
				arc_radius, entity.params[3], entity.params[4]
			)])
		EntityScript.Kind.POLYLINE:
			var pts := _ring(entity)
			if pts.size() < 2:
				return _failed("a polyline needs two points to offset")
			return _ok([EntityScript.make_polyline(_offset_open(pts, distance), false)])
		EntityScript.Kind.POLYGON, EntityScript.Kind.RECT, EntityScript.Kind.REGULAR_POLY:
			var ring := _ring(entity)
			if ring.size() < 3:
				return _failed("a closed shape needs three points to offset")
			var out: Array = []
			for produced: PackedVector2Array in Geom.offset_polygon(ring, distance, true):
				if produced.size() >= 3:
					out.append(EntityScript.make_polyline(produced, true))
			return _ok(out)
	return _failed("this kind of shape cannot be offset")


## Compute the sign of the offset that puts the new geometry on the *pick* side:
## positive when the pick lies to the left of the direction of travel (open shapes)
## or outside the ring (closed shapes), so a tool can let the user choose a side by
## clicking the side they want.
static func offset_sign(entity, pick: Vector2) -> float:
	if entity == null:
		return 1.0
	match entity.kind:
		EntityScript.Kind.LINE, EntityScript.Kind.POLYLINE:
			var pts := _ring(entity)
			if pts.size() < 2:
				return 1.0
			# Left of the nearest segment: cross product, positive is to the left.
			var span := pts[1] - pts[0]
			var nearest := Geom.closest_point_on_segment(pick, pts[0], pts[1])
			var best := 0
			var best_distance := pick.distance_to(nearest)
			for index in pts.size() - 1:
				var foot := Geom.closest_point_on_segment(pick, pts[index], pts[index + 1])
				var distance := pick.distance_to(foot)
				if distance < best_distance:
					best_distance = distance
					best = index
					span = pts[index + 1] - pts[index]
			var cross := span.x * (pick.y - pts[best].y) - span.y * (pick.x - pts[best].x)
			return 1.0 if cross >= 0.0 else -1.0
		EntityScript.Kind.CIRCLE, EntityScript.Kind.ARC:
			# Positive means outward: is the pick outside the radius?
			var centre := Vector2(entity.params[0], entity.params[1])
			return 1.0 if pick.distance_to(centre) >= entity.params[2] else -1.0
		EntityScript.Kind.POLYGON, EntityScript.Kind.RECT, EntityScript.Kind.REGULAR_POLY:
			return -1.0 if Geom.point_in_polygon(pick, _ring(entity)) else 1.0
	return 1.0


## The definition ring of an entity, sampled to its vertex form. For a closed
## shape this is its copied corner list (a rectangle's four corners), which is what
## an offset consumes; sampling the outline instead would give the offset the noise
## of the tessellation.
static func _ring(entity) -> PackedVector2Array:
	if entity.kind == EntityScript.Kind.POLYLINE or entity.kind == EntityScript.Kind.POLYGON:
		return entity.points()
	return entity.outline()


## Offset an open polyline to one side, mitering the joins: each segment's offset
## line meets the next at the vertex, and an end vertex simply keeps its own
## segment's offset point.
static func _offset_open(points: PackedVector2Array, distance: float) -> PackedVector2Array:
	var count := points.size()
	var offset_segments: Array[PackedVector2Array] = []
	for index in count - 1:
		var a: Vector2 = points[index]
		var b: Vector2 = points[index + 1]
		var span := b - a
		if span.length() <= MIN_DISTANCE:
			continue
		var normal := Vector2(-span.y, span.x).normalized() * distance
		offset_segments.append(PackedVector2Array([a + normal, b + normal]))
	if offset_segments.is_empty():
		return PackedVector2Array()
	var out := PackedVector2Array()
	out.append(offset_segments[0][0])
	for index in range(1, offset_segments.size()):
		var previous: PackedVector2Array = offset_segments[index - 1]
		var current: PackedVector2Array = offset_segments[index]
		var hit := Geom.segment_segment(previous[0], previous[1], current[0], current[1])
		# A miter that runs a long way is a spike; fall back to the segment's own
		# start point, which is the bevel a CAD package shows for a sharp corner.
		if hit.get("hit", false) and Vector2(hit["point"]).distance_to(current[0]) <= absf(distance) * 12.0:
			out.append(hit["point"])
		else:
			out.append(current[0])
	out.append(offset_segments[offset_segments.size() - 1][1])
	return out


# --- rotate ---------------------------------------------------------------------------


## Turn one entity rigidly about a pivot, returning a copy.
##
## A copy rather than a change to the entity handed in, for the reason the whole module gives:
## editing is a replacement, and the caller decides how the replacement is recorded - wholesale, or
## in place of the original as the controller does.
##
## `angle` is in radians, read the way `Vector2.angle()` reads one - from +X toward +Y - so a caller
## can hand over the bearing of the point the user clicked and mean it. A turn of nothing is refused
## rather than returned as an unchanged copy, so no gesture that did nothing is ever recorded.
static func rotate(entity, centre: Vector2, angle: float) -> Dictionary:
	if entity == null:
		return _failed("there is nothing to turn")
	if is_zero_approx(angle):
		return _failed("turning by nothing is nothing")
	var turned = entity.copy()
	turned.rotate_about(centre, angle)
	return _ok([turned])


# --- trim and extend ------------------------------------------------------------------


## Trim a line back to the piece the cutters leave.
##
## The pick names the piece to *remove* - the CAD gesture - and the line is cut at
## every crossing with the cutters, so removing the middle of three pieces leaves
## two lines behind. Returns `{ok, reason, entities}`.
##
## Only a line is trimmed here: a polyline would need its picked span rebuilt, and
## a line is what a plan's guide and boundary geometry overwhelmingly is.
static func trim(target, pick: Vector2, cutters: Array) -> Dictionary:
	if target == null or target.kind != EntityScript.Kind.LINE:
		return _failed("trim works on a line")
	var a: Vector2 = target.point(0)
	var b: Vector2 = target.point(1)
	var span := b - a
	var length := span.length()
	if length <= MIN_DISTANCE:
		return _failed("a line of no length cannot be trimmed")
	var direction := span / length
	var cuts: Array[float] = []
	for cutter in cutters:
		if cutter == null or cutter == target:
			continue
		for point: Vector2 in _crossings(a, b, cutter):
			var t := (point - a).dot(direction) / length
			if t > 1e-6 and t < 1.0 - 1e-6:
				cuts.append(t)
	if cuts.is_empty():
		return _failed("no cutting edge crosses this line")
	cuts.sort()
	var pick_t := clampf((pick - a).dot(direction) / length, 0.0, 1.0)
	# The intervals the cuts divide the line into, as [from, to] parameter pairs.
	var bounds: Array[float] = [0.0]
	for t: float in cuts:
		bounds.append(t)
	bounds.append(1.0)
	var kept: Array = []
	for index in bounds.size() - 1:
		var from := bounds[index]
		var to := bounds[index + 1]
		if to - from <= 1e-6:
			continue
		# Drop the one interval the pick fell in.
		if pick_t >= from - 1e-9 and pick_t <= to + 1e-9:
			continue
		kept.append(EntityScript.make_line(a + direction * (from * length), a + direction * (to * length)))
	return _ok(kept)


## Extend the nearer end of a line out to the first boundary it meets.
##
## The pick says which end: the end nearest the pick is the one that grows, and the
## other end stays exactly where it was. Returns `{ok, reason, entities}` with a
## single line, or the unchanged line and a reason when nothing is in the way.
static func extend(target, pick: Vector2, boundaries: Array) -> Dictionary:
	if target == null or target.kind != EntityScript.Kind.LINE:
		return _failed("extend works on a line")
	var a: Vector2 = target.point(0)
	var b: Vector2 = target.point(1)
	var span := b - a
	var length := span.length()
	if length <= MIN_DISTANCE:
		return _failed("a line of no length cannot be extended")
	# The end to grow is the one nearer the pick; the other is anchored.
	var grow_from := b if pick.distance_to(b) <= pick.distance_to(a) else a
	var anchor := a if grow_from == b else b
	var outward := (grow_from - anchor).normalized()
	var reach := maxf(length * 1000.0, 1000.0)
	var frontier := grow_from + outward * reach
	var nearest := INF
	var hit_point := grow_from
	for boundary in boundaries:
		if boundary == null or boundary == target:
			continue
		for point: Vector2 in _crossings(grow_from, frontier, boundary):
			var distance := grow_from.distance_to(point)
			if distance > MIN_DISTANCE and distance < nearest:
				nearest = distance
				hit_point = point
	if nearest == INF:
		return _failed("nothing lies beyond this end to extend to")
	return _ok([EntityScript.make_line(anchor, hit_point)])


# --- fillet ---------------------------------------------------------------------------


## Round the corner where two lines meet, with an arc of the given radius.
##
## The two picks say which portion of each line is kept, which is what decides the
## side of the corner the arc lands on when the lines cross rather than merely
## meet. Returns `{ok, reason, arc, lines}`: the tangent arc, and the two lines
## trimmed back to its tangent points. A radius too large for the corner is refused
## rather than silently clamped.
static func fillet(a, b, radius: float, pick_a: Vector2, pick_b: Vector2) -> Dictionary:
	if a == null or b == null or a.kind != EntityScript.Kind.LINE or b.kind != EntityScript.Kind.LINE:
		return _failed("a fillet is between two lines")
	if radius <= MIN_RADIUS:
		return _failed("a fillet needs a radius")
	var corner := _line_intersection(a, b)
	if not corner.get("ok", false):
		return _failed("these two lines are parallel, so they have no corner to round")
	var p: Vector2 = corner["point"]
	# The kept half of each line is the half the pick lies on. A pick exactly on
	# the corner is ambiguous and is refused rather than guessed.
	var dir_a := _half_direction(a, p, pick_a)
	var dir_b := _half_direction(b, p, pick_b)
	if dir_a == Vector2.ZERO or dir_b == Vector2.ZERO:
		return _failed("pick each line clear of the corner")
	var theta := absf(wrapf(Geom.angle_of(dir_b) - Geom.angle_of(dir_a), -PI, PI))
	if theta <= 1e-4 or theta >= PI - 1e-4:
		return _failed("the lines meet too straight to round")
	var tangent_distance := radius / tan(theta * 0.5)
	var tangent_a := p + dir_a * tangent_distance
	var tangent_b := p + dir_b * tangent_distance
	# Keep each line's far end - the endpoint on the picked side - and trim it to
	# its tangent point.
	var far_a = _far_end(a, p, dir_a)
	var far_b = _far_end(b, p, dir_b)
	if far_a == null or far_b == null:
		return _failed("a fillet needs the corner to lie on the line, not beyond its end")
	var bisector := (dir_a + dir_b).normalized()
	if bisector == Vector2.ZERO:
		return _failed("the lines meet too straight to round")
	var centre := p + bisector * (radius / sin(theta * 0.5))
	var start := Geom.angle_of(tangent_a - centre)
	var sweep := wrapf(Geom.angle_of(tangent_b - centre) - start, -PI, PI)
	return {
		"ok": true,
		"reason": "",
		"arc": EntityScript.make_arc(centre, radius, start, sweep),
		"lines": [
			EntityScript.make_line(Vector2(far_a), tangent_a),
			EntityScript.make_line(Vector2(far_b), tangent_b),
		],
	}


## The endpoint of a line that lies on the same side of the corner as the pick,
## or null when both ends are on the other side (the corner is past the end).
static func _far_end(line, corner: Vector2, direction: Vector2):
	var best = null
	var best_dot := 0.0
	for index in 2:
		var end: Vector2 = line.point(index)
		var dot: float = (end - corner).dot(direction)
		if dot > MIN_DISTANCE and dot > best_dot:
			best_dot = dot
			best = end
	return best


## The unit direction from the corner into the half of the line the pick chose.
static func _half_direction(line, corner: Vector2, pick: Vector2) -> Vector2:
	var a0: Vector2 = line.point(0)
	var a1: Vector2 = line.point(1)
	var along: Vector2 = (a1 - a0).normalized()
	var to_pick: Vector2 = pick - corner
	var projection: float = to_pick.dot(along)
	if absf(projection) <= MIN_DISTANCE:
		return Vector2.ZERO
	return along * signf(projection)


## Where two infinite lines through the given pairs meet.
static func _line_intersection(a, b) -> Dictionary:
	var p: Vector2 = a.point(0)
	var r: Vector2 = a.point(1) - p
	var q: Vector2 = b.point(0)
	var s: Vector2 = b.point(1) - q
	var denominator: float = r.x * s.y - r.y * s.x
	if absf(denominator) <= Geom.EPS:
		return {"ok": false}
	var t: float = (q.x - p.x) * s.y - (q.y - p.y) * s.x
	t /= denominator
	return {"ok": true, "point": p + r * t}


# --- intersections --------------------------------------------------------------------


## Every point where the segment a-b meets an entity's outline.
##
## The outline is sampled to straight segments first, so a curve is crossed by
## chords fine enough that the crossing is exact to two millimetres - far below any
## distance a plan is drawn at.
static func _crossings(a: Vector2, b: Vector2, entity) -> PackedVector2Array:
	var out := PackedVector2Array()
	var outline: PackedVector2Array = entity.outline()
	if entity.kind == EntityScript.Kind.LINE or entity.kind == EntityScript.Kind.DIMENSION:
		outline = PackedVector2Array([entity.point(0), entity.point(1)])
	if outline.size() < 2:
		return out
	var closed: bool = entity.is_closed()
	var segments := outline.size() if closed else outline.size() - 1
	for index in segments:
		var c: Vector2 = outline[index]
		var d: Vector2 = outline[(index + 1) % outline.size()]
		var hit := Geom.segment_segment(a, b, c, d)
		if hit.get("hit", false):
			out.append(hit["point"])
	return out


# --- results --------------------------------------------------------------------------


static func _ok(entities: Array) -> Dictionary:
	return {"ok": true, "reason": "", "entities": entities}


static func _failed(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "entities": []}