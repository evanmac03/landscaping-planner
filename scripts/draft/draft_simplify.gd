class_name DraftSimplify
extends RefCounted
## The auto-simplify pass: work out which shapes can lose vertices, refuse the ones that
## cannot, and carry the answer out as one undo step.
##
## The refusal is the whole design. A simplifier that drops a vertex two shapes share
## detaches one from the other - a wall pulls off the bed it meets, and the drawing looks
## right and measures wrong - so a shape whose shared corner would move is left exactly as
## it is and named in the report. A curved shape is refused for a different reason: its
## corners are arcs, and a pass over vertices would straighten them, which is the pass
## throwing away information the model can carry.
##
## The tolerance is a *measurement*, not a taste: `default_tolerance` converts a paper
## length by the same law every other paper length in this project uses, so "invisible on
## the sheet" is a statement about the plot scale rather than about a number somebody
## liked.

const EntityScript := preload("res://scripts/draft/draft_entity.gd")
const Geom := preload("res://scripts/draft/geom2d.gd")
const ReportScript := preload("res://scripts/draft/simplify_report.gd")
const LineStyleScript := preload("res://scripts/draft/line_style.gd")

## The furthest a dropped vertex may move on paper, in millimetres. Under half a
## millimetre is inside a plotted line's own width at any scale a garden plan uses, so a
## simplification at this tolerance is invisible on the sheet and only there.
const PAPER_MM := 0.4

## How close a corner must lie to a shape to count as touching it, in model metres. Looser
## than float32 noise and tighter than any gap that means anything: a tenth of a millimetre.
const SHARE_TOLERANCE := 1.0e-4


## The default tolerance in model metres at a plot scale of 1:S, by the same conversion
## every paper length in this project uses. A scale of zero or less falls back to 1:100
## rather than producing a tolerance of nothing.
static func default_tolerance(plot_scale: float) -> float:
	var scale := plot_scale if plot_scale > 0.0 else 100.0
	return LineStyleScript.model_width_m(PAPER_MM, scale)


## Whether a shape has vertices a pass can consider at all: a polyline or a polygon with
## three or more of them and no curved (bulged) segment.
static func is_simplifiable(entity: EntityScript) -> bool:
	return refusal_for(entity) == ""


## Why a shape will not be simplified, or "" when it can be. Naming the reason is the
## point: a shape quietly left out of a pass is a shape a person will simplify by hand,
## and never find out why it was skipped.
static func refusal_for(entity: EntityScript) -> String:
	if entity == null:
		return "there is no shape"
	if entity.kind != EntityScript.Kind.POLYLINE and entity.kind != EntityScript.Kind.POLYGON:
		return "only a polyline or a polygon has vertices to take out"
	if entity.point_count() < 3:
		return "there are fewer than three points to simplify"
	for bulge: float in entity.bulges:
		if absf(bulge) > Geom.EPS:
			return "its corners are arcs, which vertices cannot stand for"
	return ""


## Work out what the pass would do to a set of shapes, without changing any of them.
##
## A shape that cannot be simplified at all never reaches the report - `refusal_for` keeps
## it out - while a shape that *can* but whose shared corner would move is reported as a
## refusal, because that is a decision about this drawing rather than about the shape.
static func plan(entities: Array, tolerance: float) -> ReportScript:
	var report := ReportScript.new()
	report.tolerance = tolerance
	for entity in entities:
		if refusal_for(entity) != "":
			continue
		var points: PackedVector2Array = entity.points()
		var simplified: PackedVector2Array = Geom.simplify(points, tolerance, entity.is_closed())
		if _moves_a_shared_corner(points, simplified, entity.is_closed(), entities, entity):
			report.refusals.append({
				"id": int(entity.id),
				"reason": "a corner it shares with another shape would move",
			})
			continue
		report.entries.append({
			"id": int(entity.id),
			"layer": entity.layer,
			"before": points.size(),
			"after": simplified.size(),
			"removed": points.size() - simplified.size(),
			"points": simplified,
		})
	return report


## Carry out a plan as one undo step. Returns how many shapes were replaced. A plan that
## changes nothing touches neither the drawing nor the undo stack.
static func apply(document, report: ReportScript) -> int:
	var replacing: Array[Dictionary] = []
	for entry in report.entries:
		if int(entry["removed"]) > 0:
			replacing.append(entry)
	if replacing.is_empty() or document == null:
		return 0
	document.begin_gesture()
	var written := 0
	for entry in replacing:
		var original: EntityScript = document.get_entity(int(entry["id"]))
		if original == null:
			# The shape was taken off the drawing between planning and applying; a
			# plan outlives the geometry it named, so a missing shape is skipped, not
			# chased.
			continue
		var rebuilt := EntityScript.make_polyline(entry["points"], original.is_closed())
		rebuilt.layer = original.layer
		rebuilt.style = original.style
		rebuilt.meta = original.meta.duplicate(true)
		if document.replace(int(entry["id"]), rebuilt):
			written += 1
	return written


## Whether simplifying this shape would take a corner it shares with another shape off the
## drawing. The shared corner counts as kept when the simplified shape still passes through
## it - a vertex dropped on a straight run leaves the geometry touching.
static func _moves_a_shared_corner(
	original: PackedVector2Array,
	simplified: PackedVector2Array,
	closed: bool,
	entities: Array,
	subject: EntityScript
) -> bool:
	for corner: Vector2 in original:
		if not _shared_with_another(corner, entities, subject):
			continue
		if not _passes_through(simplified, closed, corner):
			return true
	return false


## Whether any shape other than the subject has a vertex at this position.
static func _shared_with_another(corner: Vector2, entities: Array, subject: EntityScript) -> bool:
	for other in entities:
		if other == null or other == subject:
			continue
		for vertex: Vector2 in other.points():
			if corner.distance_squared_to(vertex) <= SHARE_TOLERANCE * SHARE_TOLERANCE:
				return true
	return false


## Whether a point lies on a polyline, within the sharing tolerance.
static func _passes_through(polyline: PackedVector2Array, closed: bool, point: Vector2) -> bool:
	var count := polyline.size()
	if count == 0:
		return false
	if count == 1:
		return point.distance_squared_to(polyline[0]) <= SHARE_TOLERANCE * SHARE_TOLERANCE
	var segments := count if closed else count - 1
	for index in segments:
		var a: Vector2 = polyline[index]
		var b: Vector2 = polyline[(index + 1) % count]
		if Geom.distance_to_segment(point, a, b) <= SHARE_TOLERANCE:
			return true
	return false