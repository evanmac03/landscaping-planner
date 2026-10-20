class_name DraftDimension
extends RefCounted
## Sets a dimension out into the linework, the marks at its ends and the text a
## view must draw.
##
## A dimension is stored as two measured points, an offset and a kind, which is
## the minimum anyone actually picks. Everything that then appears on the paper
## - the extension lines, the dimension line set out from the measured points,
## the marks at its ends and the measurement text - is derived here, once, so the
## flat plan, the 3D overlay and the plotted sheet cannot disagree about what a
## dimension looks like.
##
## Sizes come from a DraftDimensionStyle and are paper properties, so an
## arrowhead is 2.5 mm on the paper whatever the plot scale, exactly as a line
## weight is. That is what keeps a 1:100 sheet and a 1:50 sheet legible in the
## same sizes.

const EntityScript := preload("res://scripts/draft/draft_entity.gd")
const LineStyleScript := preload("res://scripts/draft/line_style.gd")
const DimensionStyleScript := preload("res://scripts/draft/dimension_style.gd")
const UnitsScript := preload("res://scripts/draft/units.gd")

## A linear dimension measures along an axis, so its direction is snapped to one.
const AXIS_EPSILON := 1e-9


## The whole dimension, ready to draw, in the style the entity draws with.
##
## Returns lines to stroke, marks to fill and labels to place. A view that only
## wants linework can ignore the other two, which is what the 3D overlay does: it
## has no way to draw filled triangles or text.
static func layout(
	entity,
	plot_scale: float,
	units = null,
	style = null
) -> Dictionary:
	var looks: DraftDimensionStyle = style if style != null else DimensionStyleScript.architectural()
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
		return _radius(from, to, plot_scale, units, looks)

	if kind == EntityScript.DimensionKind.LINEAR:
		var delta := to - from
		if absf(delta.x) >= absf(delta.y):
			var line_y := from.y + offset
			return _assemble(
				from, to,
				Vector2(from.x, line_y), Vector2(to.x, line_y),
				absf(delta.x), plot_scale, units, "", looks
			)
		var line_x := from.x + offset
		return _assemble(
			from, to,
			Vector2(line_x, from.y), Vector2(line_x, to.y),
			absf(delta.y), plot_scale, units, "", looks
		)

	# Aligned: the dimension line runs parallel to the measured points.
	var along := (to - from).normalized()
	var sideways := Vector2(along.y, -along.x)
	return _assemble(
		from, to,
		from + sideways * offset, to + sideways * offset,
		from.distance_to(to), plot_scale, units, "", looks
	)


## The style a dimension draws with: its own override if it carries one, else the
## document's standard, else the shipped default. The same shape an entity's line
## style already has, so there is one rule rather than two.
static func style_for(entity, document = null) -> DraftDimensionStyle:
	var override: Variant = entity.meta.get("dimension_style", null)
	if override is Dictionary and not (override as Dictionary).is_empty():
		return DimensionStyleScript.from_dict(override)
	if document != null and document.dimension_style != null:
		return document.dimension_style
	return DimensionStyleScript.architectural()


## A radius is a leader out to the edge with the value beside it.
static func _radius(from: Vector2, to: Vector2, plot_scale: float, units, looks) -> Dictionary:
	var radius := from.distance_to(to)
	var direction := (to - from).normalized()
	var lines: Array[PackedVector2Array] = [PackedVector2Array([from, to])]
	var marks: Array[Dictionary] = []
	_append_mark(lines, marks, to, direction, direction, looks, plot_scale)
	var height := _model(looks.text_height_mm, plot_scale)
	var normal := Vector2(direction.y, -direction.x)
	var side := 1.0 if looks.text_above else -1.0
	return {
		"lines": lines,
		"marks": marks,
		"labels": [{
			"text": "R" + _format(radius, units, looks, plot_scale),
			"position": (from + to) * 0.5 \
				+ normal * side * (_model(looks.text_gap_mm, plot_scale) + height),
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
	prefix: String,
	looks
) -> Dictionary:
	var axis := dimension_to - dimension_from
	if axis.length_squared() <= AXIS_EPSILON:
		return empty_layout()
	var direction := axis.normalized()

	# Which way the dimension line sits off the measured points. Taken from the
	# geometry rather than from the sign of the offset, so a zero offset still
	# produces something drawable instead of a division by nothing.
	var sideways := dimension_from - measured_from
	sideways = sideways.normalized() if sideways.length_squared() > AXIS_EPSILON \
		else Vector2(-direction.y, direction.x)

	var lines: Array[PackedVector2Array] = []
	var marks: Array[Dictionary] = []

	# Extension lines: a gap off the measured point, then past the dimension line
	# by an overshoot, which is what makes a dimension read as one object rather
	# than as strokes that happen to nearly touch.
	if looks.extension_lines:
		var gap := _model(looks.extension_gap_mm, plot_scale)
		var overshoot := _model(looks.extension_overshoot_mm, plot_scale)
		lines.append(PackedVector2Array([
			measured_from + sideways * gap,
			dimension_from + sideways * overshoot,
		]))
		lines.append(PackedVector2Array([
			measured_to + sideways * gap,
			dimension_to + sideways * overshoot,
		]))

	lines.append(PackedVector2Array([dimension_from, dimension_to]))
	# Marks point outward at the ends, so an arrowhead's body lies inside the
	# dimension line; a tick, which is crosswise, leans the same way at both ends
	# because it leans off the line's own direction rather than off each arrow.
	_append_mark(lines, marks, dimension_from, -direction, direction, looks, plot_scale)
	_append_mark(lines, marks, dimension_to, direction, direction, looks, plot_scale)

	var height := _model(looks.text_height_mm, plot_scale)
	var angle := direction.angle()
	# Text stays upright. A dimension you have to tilt your head to read is a
	# dimension nobody reads.
	if angle > PI * 0.5 or angle < -PI * 0.5:
		angle += PI
	var side := 1.0 if looks.text_above else -1.0

	return {
		"lines": lines,
		"marks": marks,
		"labels": [{
			"text": prefix + _format(measured, units, looks, plot_scale),
			"position": (dimension_from + dimension_to) * 0.5 \
				- sideways * side * (_model(looks.text_gap_mm, plot_scale) + height),
			"angle": angle,
			"height": height,
		}],
	}


## The mark at one end of a dimension line, in whichever convention the style
## asks for. A tick is linework and joins the lines; an arrowhead and a dot are
## fills and go to the marks, so a view that cannot fill anything still draws the
## dimension correctly.
static func _append_mark(
	lines: Array[PackedVector2Array],
	marks: Array[Dictionary],
	at: Vector2,
	outward: Vector2,
	axis: Vector2,
	looks,
	plot_scale: float
) -> void:
	var size := _model(looks.mark_size_mm, plot_scale)
	match looks.mark:
		DimensionStyleScript.Mark.ARROW:
			marks.append({
				"kind": &"arrow",
				"tip": at,
				"direction": outward,
				"size": size,
				"width_ratio": looks.mark_width_ratio,
			})
		DimensionStyleScript.Mark.DOT:
			marks.append({"kind": &"dot", "at": at, "size": size})
		DimensionStyleScript.Mark.TICK:
			lines.append(tick_stroke(at, axis, size))
		_:
			pass


## The stroke a tick mark is drawn with: a short line crossing the dimension line
## at the conventional lean. It leans off the line's direction, so both ends of a
## dimension lean the same way rather than mirroring.
static func tick_stroke(at: Vector2, axis: Vector2, size: float) -> PackedVector2Array:
	var lean := axis.rotated(deg_to_rad(DimensionStyleScript.TICK_ANGLE_DEGREES))
	return PackedVector2Array([at - lean * (size * 0.5), at + lean * (size * 0.5)])


static func empty_layout() -> Dictionary:
	var no_lines: Array[PackedVector2Array] = []
	var no_marks: Array[Dictionary] = []
	var no_labels: Array[Dictionary] = []
	return {"lines": no_lines, "marks": no_marks, "labels": no_labels}


## The three corners of an arrowhead, so every view fills the same triangle. The
## width ratio comes from the mark the layout emitted, so a slimmer or broader
## arrowhead is a style decision rather than a change in three places.
static func arrow_triangle(
	tip: Vector2,
	direction: Vector2,
	size: float,
	width_ratio: float = -1.0
) -> PackedVector2Array:
	var ratio := width_ratio if width_ratio > 0.0 else DimensionStyleScript.DEFAULT_WIDTH_RATIO
	var back := tip - direction * size
	var sideways := Vector2(-direction.y, direction.x) * (size * ratio)
	return PackedVector2Array([tip, back + sideways, back - sideways])


## A paper size in millimetres, at a plot scale of 1:S, expressed in model metres.
static func _model(paper_mm: float, plot_scale: float) -> float:
	return LineStyleScript.model_width_m(paper_mm, plot_scale)


## A measurement is a number someone reads off a sheet, so it is written to a
## fixed precision: String.num trims trailing zeros, which would put "10 m" and
## "10.5 m" on two dimensions of the same drawing.
##
## The count comes from the style at the plot scale in force. A metric document
## whose style names no count of its own takes it from the scale; an imperial one
## writes feet and inches, where the fraction *is* the precision and a decimal
## count would mean something else entirely.
static func _format(metres: float, units, looks, plot_scale: float) -> String:
	var decimals: int = looks.decimals_at(plot_scale)
	if decimals >= 0 and (units == null or units.system == UnitsScript.System.METRIC):
		return "%s m" % _fixed(metres, decimals)
	if units != null:
		return units.format_length(metres)
	return "%s m" % _fixed(metres, 3)


## A number written to an exact number of decimals. The format string is built
## rather than written out, because the count is the style's to choose.
static func _fixed(metres: float, decimals: int) -> String:
	return ("%." + str(maxi(decimals, 0)) + "f") % metres