class_name DraftTool
extends RefCounted
## The drawing tools, as a pure state machine.
##
## A tool owns nothing but the points the user has picked so far. It never
## touches the document: when a shape completes it *returns* the entity and the
## caller commits it. That keeps every tool testable without a scene tree, and
## keeps undo in one place.
##
## Points arrive already snapped, so nothing here knows about snapping, and
## ortho/polar stay a property of the pointer rather than of the shape.

const Geom := preload("res://scripts/draft/geom2d.gd")
const EntityScript := preload("res://scripts/draft/draft_entity.gd")

## The drawing tools. Dimension is appended after the shape tools rather than
## slotted in beside measure, because an enum's values are its numbers and
## renumbering a shipped one is a way to break a file that still reads correctly.
enum Kind {
	SELECT,
	LINE,
	POLYLINE,
	RECTANGLE,
	CIRCLE,
	ARC,
	MEASURE,
	DIMENSION,
	DIMENSION_LINEAR,
	DIMENSION_RADIUS,
}

## Smallest shape that is still a shape. Two points closer than this describe
## nothing, and committing a 0.000 mm line is a drafting mistake, not geometry.
const MIN_SIZE := 1e-6

var kind: Kind = Kind.SELECT
var layer: StringName = &""

var _points: PackedVector2Array = PackedVector2Array()
var _last_reason: String = ""


static func _new() -> DraftTool:
	return (load("res://scripts/draft/draft_tool.gd") as GDScript).new()


func begin(new_kind: Kind, new_layer: StringName = &"") -> void:
	kind = new_kind
	layer = new_layer
	cancel()


func is_active() -> bool:
	return not _points.is_empty()


func points() -> PackedVector2Array:
	return _points.duplicate()


func point_count() -> int:
	return _points.size()


func last_reason() -> String:
	return _last_reason


## How many picks a complete shape takes, or 0 when it is unbounded.
func needed_points() -> int:
	if kind == Kind.LINE or kind == Kind.RECTANGLE or kind == Kind.CIRCLE or kind == Kind.MEASURE:
		return 2
	if kind == Kind.DIMENSION_RADIUS:
		# A centre and a point on the circle: the radius is the distance, and the
		# direction of the second pick is where the leader goes.
		return 2
	# An arc is a centre, a start and a sweep; a linear or aligned dimension is
	# two points to measure and somewhere to put the line that measures them.
	if kind == Kind.ARC or kind == Kind.DIMENSION or kind == Kind.DIMENSION_LINEAR:
		return 3
	return 0


func is_measure() -> bool:
	return kind == Kind.MEASURE


## Whether a tool draws an annotation rather than a site feature. The caller uses
## this to put it on the dimension layer and to keep it out of the 3D ground view,
## so the three dimension commands cannot drift apart on that.
static func is_dimension(tool_kind: Kind) -> bool:
	return tool_kind == Kind.DIMENSION \
		or tool_kind == Kind.DIMENSION_LINEAR \
		or tool_kind == Kind.DIMENSION_RADIUS


## Drop the last picked point. Backspace, in a drawing tool.
func undo_point() -> bool:
	if _points.is_empty():
		return false
	_points.remove_at(_points.size() - 1)
	return true


func cancel() -> void:
	_points = PackedVector2Array()
	_last_reason = ""


# --- picking ------------------------------------------------------------------------


## Register a pick. Returns:
##   committed  a finished shape is ready to be added to the document
##   entity     that shape, for the caller to commit
##   measure    a measurement, when the measure tool completed
##   progress   how many points the shape now holds
##   rejected   true when the pick was refused (and popped back off)
func click(point: Vector2) -> Dictionary:
	_last_reason = ""
	if kind == Kind.SELECT:
		return _result(false, null, null, 0)

	if kind == Kind.POLYLINE:
		_points.append(point)
		return _result(false, null, null, _points.size())

	_points.append(point)

	# A dimension's measured pair is checked as soon as it is complete rather
	# than when the shape is. Two identical points measure nothing, and the
	# drawer wants to hear that on the bad pick, not one pick later - otherwise
	# the tool sits there refusing every placement with no way forward but
	# backing the point out. It applies to all three commands, since a length of
	# zero and a radius of zero are the same mistake.
	if is_dimension(kind) and _points.size() == 2:
		var reason := _measured_pair_reason(_points[0], _points[1])
		if reason != "":
			_points.remove_at(_points.size() - 1)
			_last_reason = reason
			return _result(false, null, null, _points.size())

	var needed := needed_points()
	if _points.size() < needed:
		return _result(false, null, null, _points.size())

	# Complete: build the shape, or refuse it and give the pick back so the
	# tool's state stays exactly where the user thinks it is.
	var built := _build()
	if not built.get("ok", false) or (built["entity"] == null and built["measure"] == null):
		_points.remove_at(_points.size() - 1)
		_last_reason = built.get("reason", "degenerate")
		return _result(false, null, null, _points.size())

	var entity = built["entity"]
	var measure = built["measure"]
	_points = PackedVector2Array()
	return _result(true, entity, measure, 0)


## Finish an open-ended shape (Enter). A polyline needs two points; the measure
## tool reports its last pair.
func finish() -> Dictionary:
	_last_reason = ""
	if kind != Kind.POLYLINE:
		if kind == Kind.MEASURE and _points.size() >= 2:
			var measure := _measure_between(_points[_points.size() - 2], _points[_points.size() - 1])
			_points = PackedVector2Array()
			return _result(true, null, measure, 0)
		return _result(false, null, null, _points.size())
	if _points.size() < 2:
		_last_reason = "a polyline needs two points"
		return _result(false, null, null, _points.size())
	var entity = EntityScript.make_polyline(_points, false)
	_points = PackedVector2Array()
	return _result(true, entity, null, 0)


func finish_closed() -> Dictionary:
	if kind != Kind.POLYLINE or _points.size() < 3:
		_last_reason = "a closed polyline needs three points"
		return _result(false, null, null, _points.size())
	var entity = EntityScript.make_polyline(_points, true)
	_points = PackedVector2Array()
	return _result(true, entity, null, 0)


func _result(committed: bool, entity, measure, progress: int) -> Dictionary:
	return {
		"committed": committed,
		"entity": entity,
		"measure": measure,
		"progress": progress,
		"rejected": not committed and _last_reason != "",
	}


func _build() -> Dictionary:
	if kind == Kind.LINE:
		if _points[0].distance_to(_points[1]) <= MIN_SIZE:
			return {"ok": false, "reason": "a line needs two distinct points"}
		return {"ok": true, "entity": EntityScript.make_line(_points[0], _points[1]), "measure": null}
	if kind == Kind.RECTANGLE:
		var size := (_points[1] - _points[0]).abs()
		if size.x <= MIN_SIZE or size.y <= MIN_SIZE:
			return {"ok": false, "reason": "a rectangle needs two distinct corners"}
		return {
			"ok": true,
			"entity": EntityScript.make_rectangle((_points[0] + _points[1]) * 0.5, size),
			"measure": null,
		}
	if kind == Kind.CIRCLE:
		var radius := _points[0].distance_to(_points[1])
		if radius <= MIN_SIZE:
			return {"ok": false, "reason": "a circle needs a radius"}
		return {"ok": true, "entity": EntityScript.make_circle(_points[0], radius), "measure": null}
	if kind == Kind.ARC:
		var arc := _arc_from(_points[0], _points[1], _points[2])
		return arc
	if kind == Kind.DIMENSION:
		return _dimension_between(_points[0], _points[1], _points[2])
	if kind == Kind.DIMENSION_LINEAR:
		return _linear_dimension_between(_points[0], _points[1], _points[2])
	if kind == Kind.DIMENSION_RADIUS:
		return _radius_dimension(_points[0], _points[1])
	if kind == Kind.MEASURE:
		return {"ok": true, "entity": null, "measure": _measure_between(_points[0], _points[1])}
	return {"ok": false, "reason": "the %s tool takes no points" % kind}


## Why a pair of picks cannot be dimensioned, or "" when it can. All three
## dimension commands need two points that are actually two points, so they share
## one rule rather than each phrasing the same refusal differently.
static func _measured_pair_reason(from: Vector2, to: Vector2) -> String:
	if from.distance_to(to) <= MIN_SIZE:
		return "a dimension needs two distinct points"
	return ""


## Two points to measure and somewhere to put the measuring line.
##
## The dimension is *aligned*: it measures the true distance between the picks and
## its line runs parallel to them. That is the reading a plan almost always wants
## - "how long is this edge of the patio" - and it is the one that cannot surprise
## the user, because an axis-locked reading of two diagonal picks measures
## something other than the distance between them, on a rule the drawer cannot
## see. The linear command below is that reading, asked for by name.
##
## The stored offset is the *signed perpendicular distance* from the first
## measured point out to where the line was placed, which is what the model holds
## and what a second person opening the drawing needs in order to find the same
## line again.
func _dimension_between(from: Vector2, to: Vector2, placed: Vector2) -> Dictionary:
	var reason := _measured_pair_reason(from, to)
	if reason != "":
		return {"ok": false, "reason": reason}
	var along := (to - from).normalized()
	# The same side vector the dimension layout uses, so the line this returns
	# lands exactly where the tool's own preview showed it.
	var sideways := Vector2(along.y, -along.x)
	return {
		"ok": true,
		"entity": EntityScript.make_dimension(
			from, to, (placed - from).dot(sideways), EntityScript.DimensionKind.ALIGNED
		),
		"measure": null,
	}


## An axis-locked dimension: it measures the extent along whichever axis the two
## picks lie mostly along, and sets its line out on the other one. That is the
## reading for an overall width or a boundary run, where the true diagonal
## distance between two corners is not the number anybody wants.
##
## The axis follows from the picks rather than from the placement, because the
## model stores one offset and derives the axis from the measured pair. A
## dimension whose axis followed the mouse would be a dimension the file could not
## remember, and reopening the drawing would move it.
func _linear_dimension_between(from: Vector2, to: Vector2, placed: Vector2) -> Dictionary:
	var reason := _measured_pair_reason(from, to)
	if reason != "":
		return {"ok": false, "reason": reason}
	var delta := to - from
	var horizontal := absf(delta.x) >= absf(delta.y)
	# The offset is a signed distance along the perpendicular axis, which is what
	# the layout adds to the measured point to find the line: a y offset for a
	# horizontal dimension, an x offset for a vertical one.
	var offset := (placed - from).y if horizontal else (placed - from).x
	return {
		"ok": true,
		"entity": EntityScript.make_dimension(
			from, to, offset, EntityScript.DimensionKind.LINEAR
		),
		"measure": null,
	}


## A radius: a leader from the centre out to the edge with the value beside it.
## Two picks and no placement, because which way the leader runs is the same act
## as naming the radius - and the second pick lands on the circle itself, where
## the centre and quadrant snaps are waiting for it.
func _radius_dimension(centre: Vector2, edge: Vector2) -> Dictionary:
	var reason := _measured_pair_reason(centre, edge)
	if reason != "":
		return {"ok": false, "reason": reason}
	return {
		"ok": true,
		"entity": EntityScript.make_dimension(
			centre, edge, 0.0, EntityScript.DimensionKind.RADIUS
		),
		"measure": null,
	}


## Centre, a point on the radius, and where the sweep ends.
func _arc_from(centre: Vector2, through: Vector2, finish_point: Vector2) -> Dictionary:
	var radius := centre.distance_to(through)
	if radius <= MIN_SIZE:
		return {"ok": false, "reason": "an arc needs a radius"}
	var start := Geom.angle_of(through - centre)
	var end := Geom.angle_of(finish_point - centre)
	var sweep := wrapf(end - start, -PI, PI)
	if absf(sweep) <= MIN_SIZE:
		return {"ok": false, "reason": "an arc needs a sweep"}
	return {
		"ok": true,
		"entity": EntityScript.make_arc(centre, radius, start, sweep),
		"measure": null,
	}


## What the measure tool reports. Deliberately raw numbers: formatting is the
## units module's business, and the units are the user's choice.
func _measure_between(from: Vector2, to: Vector2) -> Dictionary:
	var delta := to - from
	return {
		"distance": delta.length(),
		"delta": delta,
		"angle": Geom.angle_of(delta),
		"area": null,
	}


# --- preview ------------------------------------------------------------------------


## The shape as it would be if the user picked here. Null when there is nothing
## to show yet.
func preview(cursor: Vector2):
	var count := _points.size()
	if count == 0:
		return null
	if kind == Kind.LINE:
		return EntityScript.make_line(_points[0], cursor)
	if kind == Kind.POLYLINE:
		var rubber := _points.duplicate()
		rubber.append(cursor)
		if rubber.size() < 2:
			return null
		return EntityScript.make_polyline(rubber, false)
	if kind == Kind.RECTANGLE:
		var size := (cursor - _points[0]).abs()
		if size.x <= MIN_SIZE or size.y <= MIN_SIZE:
			return null
		return EntityScript.make_rectangle((_points[0] + cursor) * 0.5, size)
	if kind == Kind.CIRCLE:
		var radius := _points[0].distance_to(cursor)
		if radius <= MIN_SIZE:
			return null
		return EntityScript.make_circle(_points[0], radius)
	if kind == Kind.ARC:
		if count == 1:
			var span := _points[0].distance_to(cursor)
			if span <= MIN_SIZE:
				return null
			return EntityScript.make_circle(_points[0], span)
		var preview_arc := _arc_from(_points[0], _points[1], cursor)
		return preview_arc["entity"] if preview_arc.get("ok", false) else null
	if kind == Kind.DIMENSION or kind == Kind.DIMENSION_LINEAR:
		if count == 1:
			# With one point down there is nothing to measure yet, so the ghost
			# is the plain rubber band the line tool shows. The alternative - a
			# dimension with no measurement in it - would be a drawing of a
			# number that is not there.
			return EntityScript.make_line(_points[0], cursor)
		var placed: Dictionary = _dimension_between(_points[0], _points[1], cursor)
		if kind == Kind.DIMENSION_LINEAR:
			placed = _linear_dimension_between(_points[0], _points[1], cursor)
		return placed["entity"] if placed.get("ok", false) else null
	if kind == Kind.DIMENSION_RADIUS:
		if count == 0:
			return null
		# A radius takes no placement, so from the first pick onwards the ghost
		# can show the measurement it is about to make, value and all.
		var ghost: Dictionary = _radius_dimension(_points[0], cursor)
		return ghost["entity"] if ghost.get("ok", false) else null
	return null


## A measurement preview for the measure tool, without committing anything.
func preview_measure(cursor: Vector2) -> Dictionary:
	if kind != Kind.MEASURE or _points.is_empty():
		return {}
	return _measure_between(_points[0], cursor)


# --- status -------------------------------------------------------------------------


func status() -> String:
	if kind == Kind.SELECT:
		return "Click geometry to select it"
	if kind == Kind.LINE:
		return "Specify the first point" if _points.is_empty() else "Specify the second point"
	if kind == Kind.POLYLINE:
		return "Specify the first point" if _points.is_empty() \
			else "Specify the next point, Enter to finish, C to close"
	if kind == Kind.RECTANGLE:
		return "Specify the first corner" if _points.is_empty() else "Specify the opposite corner"
	if kind == Kind.CIRCLE:
		return "Specify the centre" if _points.is_empty() else "Specify the radius"
	if kind == Kind.ARC:
		if _points.is_empty():
			return "Specify the centre"
		return "Specify the start point" if _points.size() == 1 else "Specify the end point"
	if kind == Kind.MEASURE:
		return "Pick the first point" if _points.is_empty() else "Pick the second point"
	if kind == Kind.DIMENSION or kind == Kind.DIMENSION_LINEAR:
		if _points.is_empty():
			return "Specify the first point to measure from"
		if _points.size() == 1:
			return "Specify the point to measure to"
		return "Where the dimension line goes"
	if kind == Kind.DIMENSION_RADIUS:
		return "Specify the centre" if _points.is_empty() \
			else "Specify a point on the circle"
	return ""


static func label_for(tool_kind: Kind) -> String:
	if tool_kind == Kind.SELECT:
		return "Select"
	if tool_kind == Kind.LINE:
		return "Line"
	if tool_kind == Kind.POLYLINE:
		return "Polyline"
	if tool_kind == Kind.RECTANGLE:
		return "Rectangle"
	if tool_kind == Kind.CIRCLE:
		return "Circle"
	if tool_kind == Kind.ARC:
		return "Arc"
	if tool_kind == Kind.MEASURE:
		return "Measure"
	if tool_kind == Kind.DIMENSION:
		return "Aligned dimension"
	if tool_kind == Kind.DIMENSION_LINEAR:
		return "Linear dimension"
	if tool_kind == Kind.DIMENSION_RADIUS:
		return "Radial dimension"
	return "?"