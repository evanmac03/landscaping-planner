class_name DraftSnapEngine
extends RefCounted
## Object snapping for the drafting subsystem.
##
## Snapping is a candidate-generation problem with a strict priority order. The
## cursor is converted to a double world point, an aperture is applied in
## *pixels* so tolerance is a property of the pointer rather than of the drawing
## scale, candidates are generated only for entities near the cursor, and the
## winner is chosen lexicographically by (priority, pixel distance).
##
## Two rules matter more than the rest:
##
##  - **Grid and polar are constraints, not targets.** They rank below every
##    object snap, and they act on the cursor rather than competing in the
##    candidate list. A grid that outranks object snaps hijacks every point that
##    happens to sit near a grid line.
##  - **Snap has hysteresis.** Once locked, a snap holds until the cursor leaves
##    a larger exit aperture. Without it, one pixel of mouse jitter changes the
##    target and the drawing becomes unstable to place a point in.
##
## Constraint versus target: an exact object snap wins. Ortho and polar apply
## only when no exact target is within the aperture. This keeps the common
## workflow — start on a snapped endpoint, then draw orthogonally — behaving as
## expected.

const Geom := preload("res://scripts/draft/geom2d.gd")
const Grid := preload("res://scripts/draft/spatial_grid.gd")
const EntityScript := preload("res://scripts/draft/draft_entity.gd")

enum Mode {
	NONE,
	ENDPOINT,
	INTERSECTION,
	MIDPOINT,
	CENTRE,
	QUADRANT,
	PERPENDICULAR,
	TANGENT,
	NEAREST,
	GRID,
	POLAR,
}

## Lower wins. Object snaps are all ranked above the constraints.
const PRIORITY := {
	Mode.ENDPOINT: 0,
	Mode.INTERSECTION: 1,
	Mode.MIDPOINT: 2,
	Mode.CENTRE: 3,
	Mode.QUADRANT: 4,
	Mode.PERPENDICULAR: 5,
	Mode.TANGENT: 6,
	Mode.NEAREST: 7,
	Mode.GRID: 8,
}

const LABELS := {
	Mode.NONE: "",
	Mode.ENDPOINT: "endpoint",
	Mode.INTERSECTION: "intersection",
	Mode.MIDPOINT: "midpoint",
	Mode.CENTRE: "centre",
	Mode.QUADRANT: "quadrant",
	Mode.PERPENDICULAR: "perpendicular",
	Mode.TANGENT: "tangent",
	Mode.NEAREST: "nearest",
	Mode.GRID: "grid",
	Mode.POLAR: "polar",
}

## Marker glyphs, so the active snap and its target are visible at the cursor
## (REQ 2.3.4).
const GLYPHS := {
	Mode.NONE: "",
	Mode.ENDPOINT: "⌐",
	Mode.INTERSECTION: "✕",
	Mode.MIDPOINT: "△",
	Mode.CENTRE: "○",
	Mode.QUADRANT: "◇",
	Mode.PERPENDICULAR: "⊥",
	Mode.TANGENT: "⌒",
	Mode.NEAREST: "⌐",
	Mode.GRID: "⊞",
	Mode.POLAR: "∠",
}

var grid: DraftSpatialGrid
var entities_by_id: Dictionary = {}

## Aperture in pixels, converted to metres at the current zoom (REQ 2.3.1).
var aperture_pixels: float = 12.0
## Once locked, a snap holds until the cursor is this many apertures away
## (REQ 2.3.3).
var exit_factor: float = 1.6

## Which snap modes are live. Everything exact is on by default; nearest is the
## catch-all and can be turned off by anyone who finds it noisy.
var enabled: Dictionary = {}

var grid_snap: bool = false
var grid_step: float = 0.5
var ortho: bool = false
var polar: bool = false
var polar_step_degrees: float = 45.0

var _locked: Dictionary = {}


static func _new() -> DraftSnapEngine:
	return (load("res://scripts/draft/snap_engine.gd") as GDScript).new()


func _init() -> void:
	grid = Grid.new()
	for mode: Mode in [Mode.ENDPOINT, Mode.INTERSECTION, Mode.MIDPOINT, Mode.CENTRE,
			Mode.QUADRANT, Mode.PERPENDICULAR, Mode.TANGENT, Mode.NEAREST]:
		enabled[mode] = true


## Point the engine at a set of entities, or at a whole document.
func bind(entities: Array) -> void:
	entities_by_id.clear()
	for entry in entities:
		entities_by_id[entry.id] = entry
	grid.rebuild(entities)
	clear_lock()


func clear_lock() -> void:
	_locked = {}


func locked_point() -> Vector2:
	return _locked.get("point", Vector2.ZERO)


func set_enabled(mode: Mode, on: bool) -> void:
	enabled[mode] = on
	if not on and _locked.get("mode", Mode.NONE) == mode:
		clear_lock()


# --- resolution ---------------------------------------------------------------------


## Resolve the cursor to a snapped point.
##
## `previous` is the previous point of the tool in progress, needed for
## perpendicular and tangent snaps, which are undefined without it.
func resolve(
	cursor: Vector2,
	pixels_per_metre: float,
	previous: Vector2 = Vector2.ZERO,
	has_previous: bool = false
) -> Dictionary:
	var scale := maxf(pixels_per_metre, 0.0001)
	var aperture := aperture_pixels / scale

	# Hysteresis first: hold the lock until the cursor leaves the exit aperture.
	if not _locked.is_empty():
		var locked: Vector2 = _locked["point"]
		if cursor.distance_to(locked) * scale <= aperture_pixels * exit_factor:
			return _result(locked, _locked, true, 0)

	var box := Rect2(cursor - Vector2(aperture, aperture), Vector2(aperture, aperture) * 2.0)
	var nearby := grid.query(box)
	var gathered: Array = []
	var candidates: Array = []
	for id in nearby:
		var entity = entities_by_id.get(id, null)
		if entity == null:
			continue
		gathered.append(entity)
		_collect(entity, box, previous, has_previous, candidates)

	# Intersections are generated only between entities that both overlap the
	# aperture. Generating them across the whole drawing is O(n^2) and unusable
	# on a real plan (REQ 2.3.5).
	if enabled.get(Mode.INTERSECTION, true):
		for first in gathered.size():
			for second in range(first + 1, gathered.size()):
				_collect_intersections(gathered[first], gathered[second], box, candidates)

	var best: Dictionary = {}
	var best_score := INF
	for candidate in candidates:
		var point: Vector2 = candidate["point"]
		var pixels := cursor.distance_to(point) * scale
		if pixels > aperture_pixels:
			continue
		# Lexicographic: priority dominates, pixel distance breaks ties.
		var score := float(PRIORITY.get(candidate["mode"], 99)) * 1000000.0 + pixels
		if score < best_score:
			best_score = score
			best = candidate

	if not best.is_empty():
		_locked = best
		return _result(best["point"], best, true, candidates.size())

	# No exact target. Constraints act on the cursor itself.
	_locked = {}
	var constrained := _apply_constraint(cursor, previous, has_previous)
	if constrained["constrained"]:
		var constraint_mode: Mode = constrained["mode"]
		return {
			"point": constrained["point"],
			"mode": constraint_mode,
			"snapped": true,
			"label": LABELS.get(constraint_mode, ""),
			"glyph": GLYPHS.get(constraint_mode, ""),
			"entity": 0,
			"candidates": 0,
		}
	return {
		"point": cursor, "mode": Mode.NONE, "snapped": false,
		"label": "", "glyph": "", "entity": 0, "candidates": 0,
	}


func _result(point: Vector2, source: Dictionary, snapped: bool, candidate_count: int) -> Dictionary:
	var mode: Mode = source.get("mode", Mode.NONE)
	return {
		"point": point,
		"mode": mode,
		"snapped": snapped,
		"label": LABELS.get(mode, ""),
		"glyph": GLYPHS.get(mode, ""),
		"entity": int(source.get("entity", 0)),
		"candidates": candidate_count,
	}


## Ortho and polar tracking. Applied only when nothing exact was found. Reports
## which constraint it actually applied, so a caller never sees "polar" when the
## grid is what moved the point.
func _apply_constraint(point: Vector2, previous: Vector2, has_previous: bool) -> Dictionary:
	if has_previous and ortho:
		var offset := point - previous
		if absf(offset.x) >= absf(offset.y):
			return {"point": Vector2(point.x, previous.y), "constrained": true, "mode": Mode.POLAR}
		return {"point": Vector2(previous.x, point.y), "constrained": true, "mode": Mode.POLAR}
	if has_previous and polar:
		var offset := point - previous
		if offset.length_squared() > Geom.EPS:
			var step := deg_to_rad(maxf(polar_step_degrees, 0.001))
			var angle := roundf(atan2(offset.y, offset.x) / step) * step
			var distance := offset.length()
			return {
				"point": previous + Vector2(cos(angle), sin(angle)) * distance,
				"constrained": true,
				"mode": Mode.POLAR,
			}
	if grid_snap:
		return {
			"point": Vector2(
				roundf(point.x / grid_step) * grid_step,
				roundf(point.y / grid_step) * grid_step),
			"constrained": true,
			"mode": Mode.GRID,
		}
	return {"point": point, "constrained": false, "mode": Mode.NONE}


# --- candidate generation -----------------------------------------------------------


func _push(out: Array, point: Vector2, mode: Mode, entity_id: int, box: Rect2, on: bool = true) -> void:
	if not on or not enabled.get(mode, true):
		return
	if box.has_point(point):
		out.append({"point": point, "mode": mode, "entity": entity_id})


func _collect(entity: EntityScript, box: Rect2, previous: Vector2, has_previous: bool, out: Array) -> void:
	var kind: int = entity.kind
	if kind == EntityScript.Kind.LINE:
		_push(out, entity.point(0), Mode.ENDPOINT, entity.id, box)
		_push(out, entity.point(1), Mode.ENDPOINT, entity.id, box)
		_push(out, (entity.point(0) + entity.point(1)) * 0.5, Mode.MIDPOINT, entity.id, box)
	elif kind == EntityScript.Kind.CIRCLE:
		var centre: Vector2 = entity.point(0)
		var radius: float = entity.params[2]
		_push(out, centre, Mode.CENTRE, entity.id, box)
		for quarter in 4:
			var angle := float(quarter) * PI * 0.5
			_push(out, centre + Vector2(cos(angle), sin(angle)) * radius, Mode.QUADRANT, entity.id, box)
	elif kind == EntityScript.Kind.ARC:
		var arc_centre: Vector2 = entity.point(0)
		_push(out, arc_centre, Mode.CENTRE, entity.id, box)
		_push(out, entity.point(1), Mode.ENDPOINT, entity.id, box)
		_push(out, entity.point(2), Mode.ENDPOINT, entity.id, box)
		_push(out, Geom.arc_point(arc_centre, entity.params[2], entity.params[3], entity.params[4], 0.5),
			Mode.MIDPOINT, entity.id, box)
	elif kind == EntityScript.Kind.RECT or kind == EntityScript.Kind.REGULAR_POLY:
		_push(out, entity.point(0), Mode.CENTRE, entity.id, box)
		var outline := entity.outline()
		for vertex: Vector2 in outline:
			_push(out, vertex, Mode.ENDPOINT, entity.id, box)
		for index in outline.size():
			var next: Vector2 = outline[(index + 1) % outline.size()]
			_push(out, (outline[index] + next) * 0.5, Mode.MIDPOINT, entity.id, box)
	elif kind == EntityScript.Kind.POLYLINE or kind == EntityScript.Kind.POLYGON:
		var count := entity.point_count()
		for index in count:
			_push(out, entity.point(index), Mode.ENDPOINT, entity.id, box)
		var segments := count if entity.is_closed() else count - 1
		for index in segments:
			var next := entity.point((index + 1) % count)
			_push(out, (entity.point(index) + next) * 0.5, Mode.MIDPOINT, entity.id, box)
	else:
		# Dimensions, text and anything else: their definition points.
		for index in entity.point_count():
			_push(out, entity.point(index), Mode.ENDPOINT, entity.id, box)

	if has_previous:
		_collect_from_previous(entity, previous, box, out)
	if enabled.get(Mode.NEAREST, true):
		var nearest := _nearest_on_outline(entity, box)
		if not nearest.is_empty():
			_push(out, nearest[0], Mode.NEAREST, entity.id, box)


## Perpendicular and tangent snaps, which are defined relative to the previous
## point of the tool in progress.
func _collect_from_previous(entity: EntityScript, previous: Vector2, box: Rect2, out: Array) -> void:
	var kind: int = entity.kind
	if enabled.get(Mode.PERPENDICULAR, true):
		for segment: PackedVector2Array in _segments_near(entity, box):
			var foot := Geom.foot_of_perpendicular(previous, segment[0], segment[1])
			# Only where the foot actually lands on the segment.
			if Geom.distance_to_segment(foot, segment[0], segment[1]) <= 0.000001:
				_push(out, foot, Mode.PERPENDICULAR, entity.id, box)
	if enabled.get(Mode.TANGENT, true) and (kind == EntityScript.Kind.CIRCLE or kind == EntityScript.Kind.ARC):
		var centre: Vector2 = entity.point(0)
		var radius: float = entity.params[2]
		var to_point := previous - centre
		var distance := to_point.length()
		if distance > radius + 0.000001:
			var base := atan2(to_point.y, to_point.x)
			var spread := acos(clampf(radius / distance, -1.0, 1.0))
			for sign_value: float in [1.0, -1.0]:
				var angle := base + spread * sign_value
				var tangent := centre + Vector2(cos(angle), sin(angle)) * radius
				if kind == EntityScript.Kind.ARC:
					if not Geom.angle_in_sweep(angle, entity.params[3], entity.params[4]):
						continue
				_push(out, tangent, Mode.TANGENT, entity.id, box)


func _collect_intersections(a: EntityScript, b: EntityScript, box: Rect2, out: Array) -> void:
	if not enabled.get(Mode.INTERSECTION, true):
		return
	var first_segments := _segments_near(a, box)
	var second_segments := _segments_near(b, box)
	for first: PackedVector2Array in first_segments:
		for second: PackedVector2Array in second_segments:
			var result := Geom.segment_segment(first[0], first[1], second[0], second[1])
			if result.get("hit", false):
				_push(out, result["point"], Mode.INTERSECTION, a.id, box)


## Outline segments whose own bounding box overlaps the aperture, so a long
## entity does not cost a walk over every segment it owns.
func _segments_near(entity: EntityScript, box: Rect2) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var outline := entity.outline()
	var count := outline.size()
	if count < 2:
		return out
	var closed: bool = entity.is_closed()
	var last := count if closed else count - 1
	for index in last:
		var a: Vector2 = outline[index]
		var b: Vector2 = outline[(index + 1) % count]
		if Rect2(a, Vector2.ZERO).expand(b).intersects(box):
			out.append(PackedVector2Array([a, b]))
	return out


## The point on an entity's outline nearest the cursor, or an empty array.
## Returned as a one-element array rather than a nullable Vector2 so the result
## keeps a static type.
func _nearest_on_outline(entity: EntityScript, box: Rect2) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_distance := INF
	var centre := box.get_center()
	for segment: PackedVector2Array in _segments_near(entity, box):
		var point := Geom.closest_point_on_segment(centre, segment[0], segment[1])
		var distance := point.distance_squared_to(centre)
		if distance < best_distance:
			best_distance = distance
			best = PackedVector2Array([point])
	return best