class_name DraftDimension
extends RefCounted
## Sets a dimension out into the linework, arrowheads and text a view must draw.
##
## A dimension is stored as two measured points, an offset and a kind, which is
## the minimum anyone actually picks. Everything that then appears on the paper
## - the extension lines, the dimension line set out from the measured points,
## the arrowheads and the measurement text - is derived here, once, so the flat
## plan, the 3D overlay and the plotted sheet cannot disagree about what a
## dimension looks like.
##
## Sizes are paper properties, not model properties. An arrowhead is 2.5 mm long
## on the paper whatever the plot scale, so it is converted into model metres at
## the scale in force. That is the same law the line weights already follow, and
## it is what keeps a 1:100 sheet and a 1:50 sheet legible in the same sizes.

const EntityScript := preload("res://scripts/draft/draft_entity.gd")
const LineStyleScript := preload("res://scripts/draft/line_style.gd")

## Paper millimetres. These are chosen to look right on a printed sheet, which is
## the only place they are ever judged.
const ARROW_MM := 2.5
## Half-width of an arrowhead as a fraction of its length, which gives the long
## slim arrow a drafting standard uses rather than a fat triangle.
const ARROW_HALF_WIDTH_RATIO := 0.28
## The gap between a measured point and the start of its extension line.
const EXTENSION_GAP_MM := 1.5
## How far an extension line runs past the dimension line it serves.
const EXTENSION_OVERSHOOT_MM := 1.5
## The gap between the dimension line and the text above it.
const TEXT_GAP_MM := 1.0
const TEXT_HEIGHT_MM := LineStyleScript.DEFAULT_TEXT_HEIGHT

## A linear dimension measures along an axis, so its direction is snapped to one.
const AXIS_EPSILON := 1e-9


## The whole dimension, ready to draw.
##
## Returns lines to stroke, arrowheads to fill and labels to place. A view that
## only wants linework can ignore the other two, which is what the 3D overlay
## does: it has no way to draw filled triangles or text.
static func layout(entity, plot_scale: float, units = null) -> Dictionary:
	var from: Vector2 = entity.point(0)
	var to: Vector2 = entity.point(1)
	var offset: float = 0.0
	var kind: int = EntityScript.DimensionKind.LINEAR
	if entity.params.size() > 5:
		offset = entity.params[4]
		kind = int(entity.params[5])
	if from.distance_to(to) <= AXIS_EPSILON:
		return empty_layout()

	if kind == EntityScript.DimensionKind.RADIUS:
		return _radius(from, to, plot_scale, units)

	# ANGULAR needs a vertex and two arms, which two points cannot express. It is
	# set out as an aligned dimension instead of being silently dropped, so the
	# measurement is still on the sheet and visibly a straight one.
	if kind == EntityScript.DimensionKind.LINEAR:
		var delta := to - from
		if absf(delta.x) >= absf(delta.y):
			var line_y := from.y + offset
			return _assemble(
				from, to,
				Vector2(from.x, line_y), Vector2(to.x, line_y),
				absf(delta.x), plot_scale, units, ""
			)
		var line_x := from.x + offset
		return _assemble(
			from, to,
			Vector2(line_x, from.y), Vector2(line_x, to.y),
			absf(delta.y), plot_scale, units, ""
		)

	# Aligned: the dimension line runs parallel to the measured points.
	var along := (to - from).normalized()
	var sideways := Vector2(along.y, -along.x)
	return _assemble(
		from, to,
		from + sideways * offset, to + sideways * offset,
		from.distance_to(to), plot_scale, units, ""
	)


## A radius is a leader out to the edge with the value beside it.
static func _radius(from: Vector2, to: Vector2, plot_scale: float, units) -> Dictionary:
	var radius := from.distance_to(to)
	var lines: Array[PackedVector2Array] = [PackedVector2Array([from, to])]
	var direction := (to - from).normalized()
	var normal := Vector2(direction.y, -direction.x)
	var height := _model(TEXT_HEIGHT_MM, plot_scale)
	return {
		"lines": lines,
		"arrows": [{
			"tip": to,
			"direction": direction,
			"size": _model(ARROW_MM, plot_scale),
		}],
		"labels": [{
			"text": "R" + _format(radius, units),
			"position": (from + to) * 0.5 + normal * (_model(TEXT_GAP_MM, plot_scale) + height),
			"angle": direction.angle(),
			"height": height,
		}],
	}


## Build a linear or aligned dimension from the measured points and the two ends
## of the dimension line.
static func _assemble(
	measured_from: Vector2,
	measured_to: Vector2,
	dimension_from: Vector2,
	dimension_to: Vector2,
	measured: float,
	plot_scale: float,
	units,
	prefix: String
) -> Dictionary:
	var axis := dimension_to - dimension_from
	if axis.length_squared() <= AXIS_EPSILON:
		return empty_layout()
	var direction := axis.normalized()
	var gap := _model(EXTENSION_GAP_MM, plot_scale)
	var overshoot := _model(EXTENSION_OVERSHOOT_MM, plot_scale)
	var arrow := _model(ARROW_MM, plot_scale)

	# Which way the dimension line sits off the measured points. Taken from the
	# geometry rather than from the sign of the offset, so a zero offset still
	# produces something drawable instead of a division by nothing.
	var sideways := dimension_from - measured_from
	sideways = sideways.normalized() if sideways.length_squared() > AXIS_EPSILON \
		else Vector2(-direction.y, direction.x)

	var lines: Array[PackedVector2Array] = []
	# Extension lines: a gap off the measured point, then past the dimension line
	# by an overshoot, which is what makes a dimension read as one object rather
	# than as four strokes that happen to nearly touch.
	lines.append(PackedVector2Array([
		measured_from + sideways * gap,
		dimension_from + sideways * overshoot,
	]))
	lines.append(PackedVector2Array([
		measured_to + sideways * gap,
		dimension_to + sideways * overshoot,
	]))
	lines.append(PackedVector2Array([dimension_from, dimension_to]))

	# Arrowheads point outward at the ends, so their bodies lie inside the
	# dimension line.
	var arrows: Array[Dictionary] = [
		{"tip": dimension_from, "direction": -direction, "size": arrow},
		{"tip": dimension_to, "direction": direction, "size": arrow},
	]

	var height := _model(TEXT_HEIGHT_MM, plot_scale)
	var angle := direction.angle()
	# Text stays upright. A dimension you have to tilt your head to read is a
	# dimension nobody reads.
	if angle > PI * 0.5 or angle < -PI * 0.5:
		angle += PI

	return {
		"lines": lines,
		"arrows": arrows,
		"labels": [{
			"text": prefix + _format(measured, units),
			"position": (dimension_from + dimension_to) * 0.5 \
				- sideways * (_model(TEXT_GAP_MM, plot_scale) + height),
			"angle": angle,
			"height": height,
		}],
	}


static func empty_layout() -> Dictionary:
	var no_lines: Array[PackedVector2Array] = []
	var no_arrows: Array[Dictionary] = []
	var no_labels: Array[Dictionary] = []
	return {"lines": no_lines, "arrows": no_arrows, "labels": no_labels}


## The three corners of an arrowhead, so every view fills the same triangle.
static func arrow_triangle(tip: Vector2, direction: Vector2, size: float) -> PackedVector2Array:
	var back := tip - direction * size
	var sideways := Vector2(-direction.y, direction.x) * (size * ARROW_HALF_WIDTH_RATIO)
	return PackedVector2Array([tip, back + sideways, back - sideways])


## A paper size in millimetres, at a plot scale of 1:S, expressed in model metres.
static func _model(paper_mm: float, plot_scale: float) -> float:
	return LineStyleScript.model_width_m(paper_mm, plot_scale)


## A measurement is a number someone reads off a sheet, so it is written to a
## fixed precision: String.num trims trailing zeros, which would put "10 m" and
## "10.5 m" on two dimensions of the same drawing.
static func _format(metres: float, units) -> String:
	if units != null:
		return units.format_length(metres)
	return "%.3f m" % metres