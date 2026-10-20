class_name SketchStroke
extends RefCounted
## A drawn line, handed back wobbling like a pencil rather than a plotter (§3.2).
##
## The wobble is geometry, not a shader effect. A shader that displaces by screen
## position makes the line swim as the view pans, because the displacement follows the
## window instead of the paper; and geometry can be measured, which is how the drawing
## stays honest (REQ-V3.2).
##
## Every length here is a **paper** length, converted to model metres by the plot
## scale, because a wobble is a property of the mark and not of the drawing: the same
## bed drawn at 1:50 and at 1:200 wanders the same distance on the paper.

## Sideways wander, in paper millimetres.
const AMPLITUDE_MM := 0.28
## How far along the line one wander lasts.
const WAVELENGTH_MM := 7.0
## Sampling step. A 6 m bed edge becomes about fifty points at 1:100.
const SEGMENT_MM := 1.2
## How far a mark may stray from the line it stands for. Asserted by test, and a
## requested line width or less: a pencil mark that wanders further than its own width
## is drawing something else.
const WOBBLE_LIMIT_MM := 0.45

## The seed's step between strokes, so two sides of one shape do not wander in step.
const SEED_STRIDE := 31
## The seed's range. Either prime would do; what matters is that a seed near another
## seed does not give a near-identical wander.
const SEED_MODULUS := 977
const SEED_PHASE := 0.13


## One stroke, wobbled. `seed_value` makes the same line wobble the same way every
## time, so the drawing is stable between frames and between renders.
##
## The amplitude and the step come from the look when it has an opinion (§13), and
## default to the specification's numbers when it does not.
static func wobble(
	stroke: PackedVector2Array,
	seed_value: int,
	plot_scale: float,
	amplitude_mm: float = AMPLITUDE_MM,
	segment_mm: float = SEGMENT_MM
) -> PackedVector2Array:
	if stroke.size() < 2:
		return stroke
	var out := PackedVector2Array()
	# The wander is authored in paper millimetres and scaled into model metres,
	# because a wobble is a property of the mark, not of the drawing.
	var amplitude: float = amplitude_mm * 0.001 * plot_scale
	var wavelength: float = WAVELENGTH_MM * 0.001 * plot_scale
	var step: float = maxf(segment_mm, 0.01) * 0.001 * plot_scale
	var phase_seed: float = float(seed_value % SEED_MODULUS) * SEED_PHASE
	for index in stroke.size() - 1:
		var from: Vector2 = stroke[index]
		var to: Vector2 = stroke[index + 1]
		var length: float = from.distance_to(to)
		if length <= 0.0:
			continue
		var direction: Vector2 = (to - from) / length
		var sideways := Vector2(direction.y, -direction.x)
		var samples: int = maxi(1, int(ceil(length / step)))
		for sample in samples:
			var t: float = float(sample) / float(samples)
			var at: Vector2 = from.lerp(to, t)
			# Two frequencies walking along the stroke, so the wander never reads as
			# one neat wave. Both are functions of *position along the line*, so where
			# two segments meet the wander agrees and the stroke does not kink at every
			# sample boundary.
			var along: float = t * length / wavelength
			var wander: float = (
				sin(along * TAU + phase_seed) * 0.72
				+ sin(along * TAU * 2.37 + phase_seed * 1.7) * 0.28
			)
			out.append(at + sideways * amplitude * wander)
	# The final point is appended once, after the loop, rather than at the end of every
	# segment: otherwise each shared point appears twice.
	out.append(stroke[stroke.size() - 1])
	return out


## A whole entity's strokes, wobbled together, one seed per stroke so two sides of one
## shape do not wander in step.
static func wobble_strokes(
	strokes: Array[PackedVector2Array],
	seed_value: int,
	plot_scale: float,
	amplitude_mm: float = AMPLITUDE_MM,
	segment_mm: float = SEGMENT_MM
) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for index in strokes.size():
		out.append(wobble(
			strokes[index], seed_value + index * SEED_STRIDE, plot_scale,
			amplitude_mm, segment_mm
		))
	return out


## How far a wobbled stroke strays from the one it stands for, at its worst. The
## measurement the limit is asserted with, kept here so the test and the claim are the
## same code.
##
## Each wobbled point is measured against the *closest point on the true stroke*, not
## against the nearest sample of it: a point that wandered along the line rather than
## across it has not left the line at all.
static func max_deviation(
	true_stroke: PackedVector2Array, wobbled: PackedVector2Array
) -> float:
	var worst := 0.0
	for point: Vector2 in wobbled:
		worst = maxf(worst, _distance_to_polyline(point, true_stroke))
	return worst


## The distance from a point to the nearest point on a polyline, in the same units.
static func _distance_to_polyline(
	point: Vector2, polyline: PackedVector2Array
) -> float:
	if polyline.is_empty():
		return 0.0
	var best := INF
	for index in maxi(polyline.size() - 1, 0):
		best = minf(
			best,
			_distance_to_segment(point, polyline[index], polyline[index + 1])
		)
	if polyline.size() == 1:
		best = point.distance_to(polyline[0])
	return best


## The distance from a point to a line segment.
static func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var along := b - a
	var length_squared := along.length_squared()
	if length_squared <= 0.0:
		return point.distance_to(a)
	var t: float = clampf((point - a).dot(along) / length_squared, 0.0, 1.0)
	return point.distance_to(a + along * t)