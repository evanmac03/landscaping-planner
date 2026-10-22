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
const GradingScript := preload("res://scripts/draft/grading.gd")

## The drawing tools. Dimension is appended after the shape tools rather than
## slotted in beside measure, because an enum's values are its numbers and
## renumbering a shipped one is a way to break a file that still reads correctly.
##
## The three grading tools are appended for the same reason, and they are *different* from the shape
## tools in what they hand back: a spot level and a slope arrow complete with their picks rather than
## with an entity (see `_grading_result`). A contour is a ring, and is finished like the polyline.
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
	GRADE_SPOT,
	GRADE_CONTOUR,
	GRADE_SLOPE,
	# The fourth dimension command, appended after everything rather than slotted in beside the other
	# three for the reason given above: it arrived later, and moving the three values above it to make
	# the dimension commands a tidy run would be renumbering shipped values to please the eye.
	DIMENSION_ANGULAR,
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
	if kind == Kind.GRADE_SPOT:
		# A spot level is one place: where the level is. Which level it is belongs to the controller,
		# which holds the level in hand - a tool that held it would be a tool that could hold two.
		return 1
	if kind == Kind.GRADE_SLOPE:
		# The top of the fall and the bottom of it, which is the direction the arrow runs.
		return 2
	# An arc is a centre, a start and a sweep; a linear or aligned dimension is
	# two points to measure and somewhere to put the line that measures them.
	if kind == Kind.ARC or kind == Kind.DIMENSION or kind == Kind.DIMENSION_LINEAR:
		return 3
	if kind == Kind.DIMENSION_ANGULAR:
		# A corner, a point along each of its two sides, and somewhere for the arc to stand. One more
		# pick than any other command here, which is not an accident: an angle has two directions in it
		# rather than one, so a gesture that named only one of them would not describe an angle.
		return 4
	return 0


func is_measure() -> bool:
	return kind == Kind.MEASURE


## Whether a tool draws an annotation rather than a site feature. The caller uses
## this to put it on the dimension layer and to keep it out of the 3D ground view,
## so the three dimension commands cannot drift apart on that.
static func is_dimension(tool_kind: Kind) -> bool:
	return tool_kind == Kind.DIMENSION \
		or tool_kind == Kind.DIMENSION_LINEAR \
		or tool_kind == Kind.DIMENSION_RADIUS \
		or tool_kind == Kind.DIMENSION_ANGULAR


## Whether a tool states something about the ground's heights rather than drawing a shape: the spot
## level, the contour and the slope arrow. One question, asked by the controller, by the layer the
## tool draws on and by the commit itself, so those three cannot disagree about which tools these are.
static func is_grading(tool_kind: Kind) -> bool:
	return tool_kind == Kind.GRADE_SPOT \
		or tool_kind == Kind.GRADE_CONTOUR \
		or tool_kind == Kind.GRADE_SLOPE


## Which kind of grading record a grading tool states, or "" for any other tool. The words are the
## module's own, so a record cannot be filed under a name nothing else knows.
static func grading_kind(tool_kind: Kind) -> String:
	if tool_kind == Kind.GRADE_SPOT:
		return GradingScript.SPOT
	if tool_kind == Kind.GRADE_CONTOUR:
		return GradingScript.CONTOUR
	if tool_kind == Kind.GRADE_SLOPE:
		return GradingScript.SLOPE
	return ""


## Whether a tool collects points until it is told to stop - the polyline, and a contour, which is a
## polyline that happens to land on a grading layer and carry a level.
static func is_ring(tool_kind: Kind) -> bool:
	return tool_kind == Kind.POLYLINE or tool_kind == Kind.GRADE_CONTOUR


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

	if is_ring(kind):
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
	if not is_ring(kind):
		if kind == Kind.MEASURE and _points.size() >= 2:
			var measure := _measure_between(_points[_points.size() - 2], _points[_points.size() - 1])
			_points = PackedVector2Array()
			return _result(true, null, measure, 0)
		return _result(false, null, null, _points.size())
	if _points.size() < 2:
		_last_reason = "a polyline needs two points"
		return _result(false, null, null, _points.size())
	if is_grading(kind):
		return _grading_result(_points)
	var entity = EntityScript.make_polyline(_points, false)
	_points = PackedVector2Array()
	return _result(true, entity, null, 0)


func finish_closed() -> Dictionary:
	if not is_ring(kind) or _points.size() < 3:
		_last_reason = "a closed polyline needs three points"
		return _result(false, null, null, _points.size())
	if is_grading(kind):
		return _grading_result(_points, true)
	var entity = EntityScript.make_polyline(_points, true)
	_points = PackedVector2Array()
	return _result(true, entity, null, 0)


## A grading tool's completion: the picks, handed over for the controller to stamp.
##
## The tool builds no entity, and that is deliberate rather than an omission. What a spot level or a
## slope arrow is worth drawing as is a *set* - a mark and a label, sized on paper at the plot scale -
## and neither the plot scale nor the level in hand belongs to a tool. So the picks come back through
## the same channel a measurement does, and `DraftController` turns them into records and marks.
func _grading_result(picked: PackedVector2Array, closed: bool = false) -> Dictionary:
	if picked.is_empty():
		return {"ok": false, "reason": "that is not a place on the ground"}
	var payload := {"grading": grading_kind(kind), "points": picked, "closed": closed}
	_points = PackedVector2Array()
	return _result(true, null, payload, 0)


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
	if kind == Kind.DIMENSION_ANGULAR:
		return _angular_dimension(_points[0], _points[1], _points[2], _points[3])
	if kind == Kind.MEASURE:
		return {"ok": true, "entity": null, "measure": _measure_between(_points[0], _points[1])}
	if kind == Kind.GRADE_SPOT:
		return {
			"ok": true, "entity": null,
			"measure": {"grading": GradingScript.SPOT, "points": _points.duplicate(), "closed": false},
		}
	if kind == Kind.GRADE_SLOPE:
		var reason := _measured_pair_reason(_points[0], _points[1])
		if reason != "":
			return {"ok": false, "reason": "a slope arrow needs two distinct points"}
		return {
			"ok": true, "entity": null,
			"measure": {"grading": GradingScript.SLOPE, "points": _points.duplicate(), "closed": false},
		}
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


## An angular dimension: the corner, a point along each of the two sides, and somewhere for the arc to
## stand.
##
## The angle is measured between the two *directions* out of the corner, and the fourth pick decides one
## thing only: how far out the arc sits, since its distance from the corner is the radius. Its direction
## is not stored at all, and that is the honest division rather than a gap. Which of the two angles at a
## corner a person meant is settled by which sides they picked, and the arc is then always drawn on the
## side the corner opens onto - so nothing about the reading depends on a value the file would have to
## remember, and reopening the drawing cannot change what the angle says.
func _angular_dimension(
	corner: Vector2, along_a: Vector2, along_b: Vector2, placed: Vector2
) -> Dictionary:
	var reason := _measured_pair_reason(corner, along_a)
	if reason != "":
		return {"ok": false, "reason": reason}
	if corner.distance_to(along_b) <= MIN_SIZE:
		return {"ok": false, "reason": "the second side needs a direction"}
	var radius := corner.distance_to(placed)
	if radius <= MIN_SIZE:
		return {"ok": false, "reason": "the arc needs to stand off the corner"}
	# Two sides in the same direction enclose nothing, so there is no angle to write.
	var sweep := wrapf((along_b - corner).angle() - (along_a - corner).angle(), -PI, PI)
	if absf(sweep) <= MIN_SIZE:
		return {"ok": false, "reason": "those two sides are the same direction"}
	return {
		"ok": true,
		"entity": EntityScript.make_angular_dimension(corner, along_a, along_b, radius),
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
	if kind == Kind.POLYLINE or kind == Kind.GRADE_CONTOUR:
		var rubber := _points.duplicate()
		rubber.append(cursor)
		if rubber.size() < 2:
			return null
		return EntityScript.make_polyline(rubber, false)
	if kind == Kind.GRADE_SLOPE:
		# The rubber band is the arrow's own shaft, so what is being drawn is legible before it is
		# committed: a line from the top of the fall to wherever the bottom is going to be.
		if _points[0].distance_to(cursor) <= MIN_SIZE:
			return null
		return EntityScript.make_line(_points[0], cursor)
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
	if kind == Kind.DIMENSION_ANGULAR:
		# Until both sides are down there is no angle to show, so the ghost is the plain rubber band the
		# line tool shows and the picks made so far stay visible.
		if count < 3:
			return EntityScript.make_line(_points[0], cursor)
		var angle: Dictionary = _angular_dimension(_points[0], _points[1], _points[2], cursor)
		return angle["entity"] if angle.get("ok", false) else null
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
	if kind == Kind.POLYLINE or kind == Kind.GRADE_CONTOUR:
		return "Specify the first point" if _points.is_empty() \
			else "Specify the next point, Enter to finish, C to close"
	if kind == Kind.GRADE_SPOT:
		return "Click the place the level is at"
	if kind == Kind.GRADE_SLOPE:
		return "Specify the top of the fall" if _points.is_empty() \
			else "Specify the bottom - the arrow runs downhill"
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
	if kind == Kind.DIMENSION_ANGULAR:
		if _points.is_empty():
			return "Specify the corner of the angle"
		if _points.size() == 1:
			return "Specify a point along the first side"
		if _points.size() == 2:
			return "Specify a point along the second side"
		return "Where the arc goes"
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
	if tool_kind == Kind.DIMENSION_ANGULAR:
		return "Angular dimension"
	if tool_kind == Kind.GRADE_SPOT:
		return "Spot level"
	if tool_kind == Kind.GRADE_CONTOUR:
		return "Contour"
	if tool_kind == Kind.GRADE_SLOPE:
		return "Slope arrow"
	return "?"