class_name Geom2D
extends RefCounted
## Pure 2D geometry for the drafting subsystem.
##
## Every function is static and side-effect free, so the whole kernel is
## testable with no scene at all — the same shape as ViewMath. Where an
## operation has no answer (parallel lines, a chord that misses its circle, a
## discrete case) it returns an empty result rather than a sentinel point, so a
## caller cannot accidentally treat "no intersection" as "intersection at the
## origin".
##
## Points are Vector2, which is float32 in a standard Godot build. That is
## deliberate: this kernel runs on site-local coordinates, which REQ 6.6.1
## guarantees by rebasing a survey to a site origin, and at that scale a float32
## step is about a micrometre. Stored geometry is double (see DraftEntity) and is
## only widened into Vector2 here, at the point of computation or drawing, so no
## *stored* value is ever rounded.

## Absolute tolerance in metres for coincident points and parallel directions.
const EPS := 1.0e-9
## Tolerance for angles, in radians.
const ANGLE_EPS := 1.0e-9


# --- segments and lines -------------------------------------------------------------


## Intersect two segments. Returns a dictionary with "hit". Endpoint-touching
## hits are clamped onto the segment so they return the exact endpoint rather
## than a point a hair away from it. Parallel and collinear cases are reported
## separately, because a collinear overlap has no single intersection point and
## a caller must decide what to offer instead of inventing one.
static func segment_segment(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> Dictionary:
	var rx := float(a1.x) - float(a0.x)
	var ry := float(a1.y) - float(a0.y)
	var sx := float(b1.x) - float(b0.x)
	var sy := float(b1.y) - float(b0.y)
	var qx := float(b0.x) - float(a0.x)
	var qy := float(b0.y) - float(a0.y)
	var denominator := rx * sy - ry * sx
	if absf(denominator) <= EPS:
		var collinear := absf(qx * ry - qy * rx) <= EPS
		return {"hit": false, "parallel": true, "collinear": collinear}
	var t := (qx * sy - qy * sx) / denominator
	var u := (qx * ry - qy * rx) / denominator
	if t < -EPS or t > 1.0 + EPS or u < -EPS or u > 1.0 + EPS:
		return {"hit": false, "parallel": false, "collinear": false, "t": t, "u": u}
	var tc := clampf(t, 0.0, 1.0)
	return {
		"hit": true,
		"point": Vector2(float(a0.x) + rx * tc, float(a0.y) + ry * tc),
		"t": tc,
		"u": clampf(u, 0.0, 1.0),
		"parallel": false,
		"collinear": false,
	}


## Intersect an infinite line (through `origin` along `direction`) with a circle.
static func line_circle(origin: Vector2, direction: Vector2, centre: Vector2, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var dx := float(direction.x)
	var dy := float(direction.y)
	var a := dx * dx + dy * dy
	if a <= EPS:
		return out
	var mx := float(origin.x) - float(centre.x)
	var my := float(origin.y) - float(centre.y)
	var b := mx * dx + my * dy
	var c := mx * mx + my * my - float(radius) * float(radius)
	var discriminant := b * b - a * c
	if discriminant < -EPS:
		return out
	var root := sqrt(maxf(discriminant, 0.0))
	var t0 := (-b - root) / a
	out.append(Vector2(float(origin.x) + dx * t0, float(origin.y) + dy * t0))
	if root > EPS:
		var t1 := (-b + root) / a
		out.append(Vector2(float(origin.x) + dx * t1, float(origin.y) + dy * t1))
	return out


## Intersect a segment with a circle, keeping only hits within the segment.
static func segment_circle(a0: Vector2, a1: Vector2, centre: Vector2, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var direction := a1 - a0
	var length_squared := float(direction.x) * float(direction.x) + float(direction.y) * float(direction.y)
	if length_squared <= EPS:
		return out
	for point: Vector2 in line_circle(a0, direction, centre, radius):
		var t := (float(point.x) - float(a0.x)) * float(direction.x) \
			+ (float(point.y) - float(a0.y)) * float(direction.y)
		t /= length_squared
		if t >= -EPS and t <= 1.0 + EPS:
			out.append(point)
	return out


## Intersect two circles by reducing to a line: the radical axis.
##
## The chord sits at distance `a` from the first centre along the centre line,
## with half-length `h`. Solving it this way means there is one code path rather
## than a special case per configuration, and the tangency cases fall out of
## `h == 0` for free.
static func circle_circle(c0: Vector2, r0: float, c1: Vector2, r1: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var dx := float(c1.x) - float(c0.x)
	var dy := float(c1.y) - float(c0.y)
	var distance_squared := dx * dx + dy * dy
	var distance := sqrt(distance_squared)
	if distance <= EPS:
		return out                                   # concentric: no unique answer
	if distance > float(r0) + float(r1) + EPS:
		return out                                   # separate
	if distance < absf(float(r0) - float(r1)) - EPS:
		return out                                   # one inside the other
	var a := (distance_squared + float(r0) * float(r0) - float(r1) * float(r1)) / (2.0 * distance)
	var h := sqrt(maxf(float(r0) * float(r0) - a * a, 0.0))
	var mid := Vector2(float(c0.x) + a * dx / distance, float(c0.y) + a * dy / distance)
	var ox := -dy / distance * h
	var oy := dx / distance * h
	out.append(Vector2(mid.x + ox, mid.y + oy))
	if h > EPS:
		out.append(Vector2(mid.x - ox, mid.y - oy))
	return out


## Where a segment meets a circle, keeping only hits whose angle lies on the arc.
static func segment_arc(
	a0: Vector2, a1: Vector2, centre: Vector2, radius: float,
	start: float, sweep: float
) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point: Vector2 in segment_circle(a0, a1, centre, radius):
		if angle_in_sweep(angle_of(point - centre), start, sweep):
			out.append(point)
	return out


## Intersect two arcs, keeping only hits on both sweeps.
static func arc_arc(
	c0: Vector2, r0: float, s0: float, w0: float,
	c1: Vector2, r1: float, s1: float, w1: float
) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point: Vector2 in circle_circle(c0, r0, c1, r1):
		if angle_in_sweep(angle_of(point - c0), s0, w0) \
			and angle_in_sweep(angle_of(point - c1), s1, w1):
			out.append(point)
	return out


static func closest_point_on_segment(point: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var dx := float(b.x) - float(a.x)
	var dy := float(b.y) - float(a.y)
	var length_squared := dx * dx + dy * dy
	if length_squared <= EPS:
		return a
	var t := ((float(point.x) - float(a.x)) * dx + (float(point.y) - float(a.y)) * dy) / length_squared
	t = clampf(t, 0.0, 1.0)
	return Vector2(float(a.x) + dx * t, float(a.y) + dy * t)


static func distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	return point.distance_to(closest_point_on_segment(point, a, b))


## Perpendicular distance from a point to an infinite line through a and b.
static func distance_to_line(point: Vector2, a: Vector2, b: Vector2) -> float:
	var dx := float(b.x) - float(a.x)
	var dy := float(b.y) - float(a.y)
	var length := sqrt(dx * dx + dy * dy)
	if length <= EPS:
		return point.distance_to(a)
	return absf((float(point.x) - float(a.x)) * dy - (float(point.y) - float(a.y)) * dx) / length


## The foot of the perpendicular from `point` onto the infinite line a-b.
static func foot_of_perpendicular(point: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var dx := float(b.x) - float(a.x)
	var dy := float(b.y) - float(a.y)
	var length_squared := dx * dx + dy * dy
	if length_squared <= EPS:
		return a
	var t := ((float(point.x) - float(a.x)) * dx + (float(point.y) - float(a.y)) * dy) / length_squared
	return Vector2(float(a.x) + dx * t, float(a.y) + dy * t)


# --- arcs and circles ---------------------------------------------------------------


static func angle_of(v: Vector2) -> float:
	return atan2(float(v.y), float(v.x))


## Whether `angle` lies on the arc that starts at `start` and turns by `sweep`.
##
## The measure used is the turning distance in the sweep's own direction, so a
## negative sweep (clockwise) works without a special case, and a full turn
## contains every angle.
static func angle_in_sweep(angle: float, start: float, sweep: float) -> bool:
	if absf(sweep) >= TAU:
		return true
	if sweep >= 0.0:
		return fposmod(angle - start, TAU) <= sweep + ANGLE_EPS
	return fposmod(start - angle, TAU) <= -sweep + ANGLE_EPS


## Point at parameter `t` in [0, 1] along the arc.
static func arc_point(centre: Vector2, radius: float, start: float, sweep: float, t: float) -> Vector2:
	var angle := start + sweep * t
	return Vector2(
		float(centre.x) + float(radius) * cos(angle),
		float(centre.y) + float(radius) * sin(angle)
	)


## The two endpoints of an arc.
static func arc_ends(centre: Vector2, radius: float, start: float, sweep: float) -> PackedVector2Array:
	return PackedVector2Array([
		arc_point(centre, radius, start, sweep, 0.0),
		arc_point(centre, radius, start, sweep, 1.0),
	])


## Closest point on an arc to `point`, falling back to the nearer endpoint when
## the projected angle is off the sweep.
static func closest_point_on_arc(
	point: Vector2, centre: Vector2, radius: float, start: float, sweep: float
) -> Vector2:
	var offset := point - centre
	if offset.length_squared() <= EPS:
		return arc_point(centre, radius, start, sweep, 0.0)
	var angle := angle_of(offset)
	if angle_in_sweep(angle, start, sweep):
		return Vector2(
			float(centre.x) + float(radius) * cos(angle),
			float(centre.y) + float(radius) * sin(angle)
		)
	var ends := arc_ends(centre, radius, start, sweep)
	return ends[0] if point.distance_squared_to(ends[0]) <= point.distance_squared_to(ends[1]) else ends[1]


static func arc_length(radius: float, sweep: float) -> float:
	return absf(float(radius) * float(sweep))


static func arc_chord(radius: float, sweep: float) -> float:
	return 2.0 * float(radius) * sin(absf(float(sweep)) * 0.5)


## How many straight segments an arc needs so no chord departs from the true arc
## by more than `tolerance`. Chosen from the sagitta, so a small arc is not
## over-tessellated and a large one is not visibly faceted.
static func arc_segment_count(radius: float, sweep: float, tolerance: float) -> int:
	if radius <= tolerance or absf(sweep) <= ANGLE_EPS:
		return 1
	var cos_step := 1.0 - tolerance / radius
	if cos_step <= -1.0:
		return 1
	var step := 2.0 * acos(clampf(cos_step, -1.0, 1.0))
	if step <= ANGLE_EPS:
		return 4096
	return clampi(int(ceil(absf(sweep) / step)), 1, 4096)


## Sample an arc into a polyline within a chord tolerance.
static func arc_points(
	centre: Vector2, radius: float, start: float, sweep: float, tolerance: float
) -> PackedVector2Array:
	var out := PackedVector2Array()
	var count := arc_segment_count(radius, sweep, tolerance)
	for index in count + 1:
		out.append(arc_point(centre, radius, start, sweep, float(index) / float(count)))
	return out


## Bulge is the DXF convention for an arc inside a polyline: tan(sweep / 4).
## Positive is counter-clockwise. It is what lets a rounded bed corner live in a
## flat vertex array without a second entity.
static func bulge_from_sweep(sweep: float) -> float:
	return tan(sweep * 0.25)


static func sweep_from_bulge(bulge: float) -> float:
	return 4.0 * atan(float(bulge))


## Centre and radius of the arc described by a chord with a given bulge.
static func arc_from_bulge(a: Vector2, b: Vector2, bulge: float) -> Dictionary:
	var chord := b - a
	var chord_length := chord.length()
	if absf(float(bulge)) <= EPS or chord_length <= EPS:
		return {"ok": false}
	var sweep := sweep_from_bulge(bulge)
	var radius := chord_length / (2.0 * absf(sin(sweep * 0.5)))
	# The centre lies on the perpendicular bisector, at (chord / 2) * cot(sweep / 2)
	# from the midpoint. The tangent half-angle carries the *sign* of the sweep, so
	# the same expression puts the centre on the correct side for a minor arc and
	# crosses to the far side of the chord for a major one — which is where the
	# centre belongs for a bulge past 1. Dropping that sign points the arc away from
	# its own endpoint, and the sampled curve then sweeps the long way round the
	# circle instead of arriving at `b`.
	var mid := (a + b) * 0.5
	var normal := Vector2(-float(chord.y), float(chord.x)).normalized()
	var offset := (chord_length * 0.5) / tan(sweep * 0.5)
	var centre := mid + normal * offset
	var start := angle_of(a - centre)
	return {"ok": true, "centre": centre, "radius": radius, "start": start, "sweep": sweep}


# --- polygons -----------------------------------------------------------------------


## Signed area by the shoelace formula. Positive means counter-clockwise.
static func polygon_signed_area(points: PackedVector2Array) -> float:
	var count := points.size()
	if count < 3:
		return 0.0
	var total := 0.0
	for index in count:
		var a: Vector2 = points[index]
		var b: Vector2 = points[(index + 1) % count]
		total += float(a.x) * float(b.y) - float(b.x) * float(a.y)
	return total * 0.5


static func polygon_area(points: PackedVector2Array) -> float:
	return absf(polygon_signed_area(points))


static func is_polygon_clockwise(points: PackedVector2Array) -> bool:
	return polygon_signed_area(points) < 0.0


static func polygon_perimeter(points: PackedVector2Array, closed: bool = true) -> float:
	var count := points.size()
	if count < 2:
		return 0.0
	var total := 0.0
	var last := count if closed else count - 1
	for index in last:
		total += points[index].distance_to(points[(index + 1) % count])
	return total


## Area-weighted centroid. Falls back to the vertex mean for a degenerate ring.
static func polygon_centroid(points: PackedVector2Array) -> Vector2:
	var count := points.size()
	if count == 0:
		return Vector2.ZERO
	if count < 3:
		var sum := Vector2.ZERO
		for point: Vector2 in points:
			sum += point
		return sum / float(count)
	var area := polygon_signed_area(points)
	if absf(area) <= EPS:
		var sum := Vector2.ZERO
		for point: Vector2 in points:
			sum += point
		return sum / float(count)
	var cx := 0.0
	var cy := 0.0
	for index in count:
		var a: Vector2 = points[index]
		var b: Vector2 = points[(index + 1) % count]
		var cross := float(a.x) * float(b.y) - float(b.x) * float(a.y)
		cx += (float(a.x) + float(b.x)) * cross
		cy += (float(a.y) + float(b.y)) * cross
	var factor := 1.0 / (6.0 * area)
	return Vector2(cx * factor, cy * factor)


## Whether a ring has no self-intersection. A self-intersecting parcel is a
## tracing error, and REQ 6.5 blocks the import rather than accepting it.
static func polygon_is_simple(points: PackedVector2Array) -> bool:
	var count := points.size()
	if count < 3:
		return false
	for i in count:
		var a0: Vector2 = points[i]
		var a1: Vector2 = points[(i + 1) % count]
		for j in range(i + 1, count):
			# Skip the edge itself and the edges that share a vertex with it.
			if j == i or (j + 1) % count == i or j == (i + 1) % count:
				continue
			var b0: Vector2 = points[j]
			var b1: Vector2 = points[(j + 1) % count]
			var result := segment_segment(a0, a1, b0, b1)
			if result.get("hit", false):
				return false
	return true


static func point_in_polygon(point: Vector2, polygon: PackedVector2Array) -> bool:
	return Geometry2D.is_point_in_polygon(point, polygon)


# --- simplification -----------------------------------------------------------------


## Douglas-Peucker simplification of a polyline or a closed ring, in model units.
##
## The first and last point are always kept, so an open polyline still ends where it
## ended; a ring keeps its shape without collapsing. `tolerance` is the furthest a
## dropped vertex's true position may lie from the simplified line, in model metres -
## the same unit every other authored length in this project uses. A tolerance of zero,
## or fewer than three points, returns a copy of the input unchanged.
##
## Curves are not simplified here: a vertex with a bulge carries an arc no set of
## vertices can reproduce, so the caller keeps such an entity out of the pass rather
## than having its corners quietly straightened (`DraftSimplify`).
static func simplify(points: PackedVector2Array, tolerance: float, closed: bool = false) -> PackedVector2Array:
	var count := points.size()
	if count < 3 or tolerance <= 0.0:
		return points.duplicate()
	if not closed:
		return _simplify_open(points, tolerance)
	# A ring is simplified as two open chains meeting at its two opposite extremes. A
	# chain Douglas-Peucker'd against its own start and end would collapse a small
	# regular ring to a single point, which for a bed is the bed disappearing.
	var far := 0
	var far_distance := -1.0
	for index in count:
		var reach := points[0].distance_squared_to(points[index])
		if reach > far_distance:
			far_distance = reach
			far = index
	var first_chain := PackedVector2Array()
	for index in range(0, far + 1):
		first_chain.append(points[index])
	var second_chain := PackedVector2Array()
	for index in range(far, count):
		second_chain.append(points[index])
	second_chain.append(points[0])
	var head := _simplify_open(first_chain, tolerance)
	var tail := _simplify_open(second_chain, tolerance)
	var out := PackedVector2Array()
	for vertex: Vector2 in head:
		out.append(vertex)
	# The tail repeats the meeting point at each end; neither is a new vertex.
	for index in range(1, tail.size() - 1):
		out.append(tail[index])
	return out


## Douglas-Peucker over an open chain with its endpoints pinned.
##
## The work list is explicit rather than recursive: a five-thousand-vertex bed outline
## is a legal input, and a recursive pass over it is a stack the size of the drawing.
static func _simplify_open(points: PackedVector2Array, tolerance: float) -> PackedVector2Array:
	var count := points.size()
	if count < 3:
		return points.duplicate()
	var keep := PackedByteArray()
	keep.resize(count)
	keep.fill(0)
	keep[0] = 1
	keep[count - 1] = 1
	var spans: Array = [[0, count - 1]]
	while not spans.is_empty():
		var span: Array = spans.pop_back()
		var first: int = int(span[0])
		var last: int = int(span[1])
		var worst := -1
		var worst_distance := tolerance
		for index in range(first + 1, last):
			var gap := distance_to_segment(points[index], points[first], points[last])
			if gap > worst_distance:
				worst_distance = gap
				worst = index
		if worst >= 0:
			keep[worst] = 1
			spans.append([first, worst])
			spans.append([worst, last])
	var out := PackedVector2Array()
	for index in count:
		if keep[index] == 1:
			out.append(points[index])
	return out


# --- offsetting ---------------------------------------------------------------------


## Offset a closed polygon. Returns every ring the operation produces: an inward
## offset past a local width splits into several regions, and dropping the extra
## rings silently would lose geometry.
static func offset_polygon(polygon: PackedVector2Array, distance: float, round_joins: bool = true) -> Array:
	return Geometry2D.offset_polygon(
		polygon,
		distance,
		Geometry2D.JOIN_ROUND if round_joins else Geometry2D.JOIN_MITER
	)


## Offset an open polyline. This is also how a thick stroke becomes geometry with
## correct joins, since Godot's draw_polyline has no join parameter (REQ 4.2.4).
static func offset_polyline(polyline: PackedVector2Array, distance: float, round_joins: bool = true) -> Array:
	return Geometry2D.offset_polyline(
		polyline,
		distance,
		Geometry2D.JOIN_ROUND if round_joins else Geometry2D.JOIN_MITER
	)


# --- hatching -----------------------------------------------------------------------


## Clip a line hatch to a set of rings, returning the hatch as segments.
##
## Rings are treated together under the even-odd rule, which is what makes a hole
## come out unfilled without special handling (REQ 4.6.4). The region is rotated
## so hatch lines become horizontal, each scanline's crossings with the ring edges
## are sorted and paired, and the pairs are rotated back.
static func hatch_lines(
	rings: Array[PackedVector2Array], spacing: float, angle_rad: float
) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if spacing <= EPS:
		return out
	var to_pattern := Transform2D(-angle_rad, Vector2.ZERO)
	var min_y := INF
	var max_y := -INF
	var rotated: Array[PackedVector2Array] = []
	for ring: PackedVector2Array in rings:
		if ring.size() < 3:
			continue
		var turned := PackedVector2Array()
		for point: Vector2 in ring:
			var q := to_pattern * point
			turned.append(q)
			min_y = minf(min_y, q.y)
			max_y = maxf(max_y, q.y)
		rotated.append(turned)
	if rotated.is_empty() or min_y > max_y:
		return out

	var from_pattern := Transform2D(angle_rad, Vector2.ZERO)
	var y := ceilf(min_y / spacing) * spacing
	var guard := 0
	while y <= max_y and guard < 100000:
		var crossings: Array[float] = []
		for ring: PackedVector2Array in rotated:
			var count := ring.size()
			for index in count:
				var a: Vector2 = ring[index]
				var b: Vector2 = ring[(index + 1) % count]
				var ay := float(a.y)
				var by := float(b.y)
				# Half-open test, so a vertex exactly on the scanline is counted
				# once rather than twice or not at all.
				if (ay <= y and by > y) or (by <= y and ay > y):
					var t := (y - ay) / (by - ay)
					crossings.append(float(a.x) + (float(b.x) - float(a.x)) * t)
		crossings.sort()
		var index := 0
		while index + 1 < crossings.size():
			var x0 := crossings[index]
			var x1 := crossings[index + 1]
			if x1 - x0 > EPS:
				out.append(PackedVector2Array([
					from_pattern * Vector2(x0, y),
					from_pattern * Vector2(x1, y),
				]))
			index += 2
		y += spacing
		guard += 1
	return out


## Positions for a symbol fill on the hatch grid, keeping only those inside the
## region (REQ 4.6.3).
static func fill_grid(polygon: PackedVector2Array, spacing: float, origin: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var out := PackedVector2Array()
	if spacing <= EPS or polygon.size() < 3:
		return out
	var box := polygon_aabb(polygon)
	var y := ceilf((box.position.y - origin.y) / spacing) * spacing + origin.y
	var guard := 0
	while y <= box.end.y and guard < 100000:
		var x := ceilf((box.position.x - origin.x) / spacing) * spacing + origin.x
		var inner := 0
		while x <= box.end.x and inner < 100000:
			var point := Vector2(x, y)
			if Geometry2D.is_point_in_polygon(point, polygon):
				out.append(point)
			x += spacing
			inner += 1
		y += spacing
		guard += 1
	return out


# --- bounds -------------------------------------------------------------------------


## Bounding box of a set of points, as a Rect2.
static func points_aabb(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var minimum := points[0]
	var maximum := points[0]
	for point: Vector2 in points:
		minimum = Vector2(minf(minimum.x, point.x), minf(minimum.y, point.y))
		maximum = Vector2(maxf(maximum.x, point.x), maxf(maximum.y, point.y))
	return Rect2(minimum, maximum - minimum)


static func polygon_aabb(polygon: PackedVector2Array) -> Rect2:
	return points_aabb(polygon)


## Bounding box of an arc: its endpoints plus whichever cardinal points the sweep
## actually contains. Using the bounding circle instead is a common error that
## makes culling and picking wrong for small arcs.
static func arc_aabb(centre: Vector2, radius: float, start: float, sweep: float) -> Rect2:
	var points := arc_ends(centre, radius, start, sweep)
	for quarter in 4:
		var angle := float(quarter) * PI * 0.5
		if angle_in_sweep(angle, start, sweep):
			points.append(arc_point(centre, radius, start, sweep, arc_parameter(angle, start, sweep)))
	return points_aabb(points)


## Where along an arc an angle sits, as t in [0, 1]. Measured as turning distance
## in the sweep's own direction, so an arc that crosses the +/-PI wrap still
## yields a parameter inside the arc rather than a negative one.
static func arc_parameter(angle: float, start: float, sweep: float) -> float:
	if absf(sweep) <= ANGLE_EPS:
		return 0.0
	var delta := fposmod(angle - start, TAU) if sweep >= 0.0 else -fposmod(start - angle, TAU)
	return delta / sweep


## Bounding box of a stitched vertex list, arc segments included.
static func polyline_aabb(points: PackedVector2Array, _closed: bool = false) -> Rect2:
	return points_aabb(points)


# --- formatting helpers -------------------------------------------------------------


## The point at a fraction along a polyline, for placing labels on a dimension.
static func point_along(polyline: PackedVector2Array, fraction: float) -> Vector2:
	if polyline.is_empty():
		return Vector2.ZERO
	if polyline.size() == 1:
		return polyline[0]
	var total := polygon_perimeter(polyline, false)
	if total <= EPS:
		return polyline[0]
	var target := clampf(fraction, 0.0, 1.0) * total
	var walked := 0.0
	for index in polyline.size() - 1:
		var a: Vector2 = polyline[index]
		var b: Vector2 = polyline[index + 1]
		var length := a.distance_to(b)
		if walked + length >= target:
			var t := 0.0 if length <= EPS else (target - walked) / length
			return a.lerp(b, t)
		walked += length
	return polyline[polyline.size() - 1]


## Direction of a polyline at a fraction along it, for orienting a label.
static func direction_along(polyline: PackedVector2Array, fraction: float) -> Vector2:
	if polyline.size() < 2:
		return Vector2.RIGHT
	var total := polygon_perimeter(polyline, false)
	if total <= EPS:
		return Vector2.RIGHT
	var target := clampf(fraction, 0.0, 1.0) * total
	var walked := 0.0
	for index in polyline.size() - 1:
		var a: Vector2 = polyline[index]
		var b: Vector2 = polyline[index + 1]
		var length := a.distance_to(b)
		if walked + length >= target:
			return (b - a).normalized()
		walked += length
	return (polyline[polyline.size() - 1] - polyline[polyline.size() - 2]).normalized()


## Apply a sequence of dashed on/off lengths to a polyline, returning the dash
## segments. Patterns are computed from the polyline's own geometry, never from
## screen space, or dashes crawl as the view pans (REQ 4.3.2).
## Which pattern entry a distance falls in, and how much of it is left.
## `pattern` alternates on and off, starting on, so an even index is drawn.
static func pattern_entry(pattern: Array[float], position_in_cycle: float) -> Array:
	var walked := 0.0
	for index in pattern.size():
		var length: float = maxf(pattern[index], 0.0)
		if position_in_cycle < walked + length - EPS:
			return [index, walked + length - position_in_cycle]
		walked += length
	return [maxi(pattern.size() - 1, 0), EPS]


## Apply a dashed pattern to a polyline, returning the drawn runs.
##
## The pattern is measured along the polyline's own arc length and the phase
## carries across vertices, so a dashed polyline does not restart its pattern at
## every corner, and the dashes stay put when the view pans (REQ 4.3.2, 4.3.4).
static func dash_polyline(polyline: PackedVector2Array, pattern: Array[float]) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if polyline.size() < 2:
		return out
	var cycle := 0.0
	for length: float in pattern:
		cycle += maxf(length, 0.0)
	if pattern.is_empty() or cycle <= EPS:
		out.append(polyline)
		return out

	var travelled := 0.0
	var current := PackedVector2Array()
	for index in polyline.size() - 1:
		var a: Vector2 = polyline[index]
		var b: Vector2 = polyline[index + 1]
		var segment := b - a
		var segment_length := segment.length()
		if segment_length <= EPS:
			continue
		var direction := segment / segment_length
		var walked := 0.0
		while walked < segment_length - EPS:
			var entry := pattern_entry(pattern, fposmod(travelled + walked, cycle))
			var entry_index: int = entry[0]
			var remaining: float = entry[1]
			var take := minf(remaining, segment_length - walked)
			var from := a + direction * walked
			var to := a + direction * (walked + take)
			if entry_index % 2 == 0:
				if current.is_empty():
					current.append(from)
				current.append(to)
			else:
				if current.size() >= 2:
					out.append(current)
				current = PackedVector2Array()
			walked += take
		travelled += segment_length
	if current.size() >= 2:
		out.append(current)
	return out