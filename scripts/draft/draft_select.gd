class_name DraftSelect
extends RefCounted
## Window and crossing selection: which shapes a rubber band catches.
##
## Two modes, and the difference between them is the whole point of having two:
##
## - A **window** catches only what lies wholly inside it. That is the mode that
##   makes "these three beds and nothing else" safe, and it is the reason a
##   designer drags left-to-right over nothing by accident and gets nothing.
## - A **crossing** catches anything the band touches, which is how a run of
##   linework is swept off a sheet without hunting each piece.
##
## A shape that *encloses* the band without touching it is caught by neither. That
## is the convention, and it is also the honest answer: the band has not met the
## shape, so a sweep over the middle of a big circle must not select the circle.
##
## Nothing here knows about a document, a screen or a layer: it is handed shapes
## and a rectangle in model space, so the whole rule is testable with four numbers
## and no scene.

const Geom := preload("res://scripts/draft/geom2d.gd")

const MODE_WINDOW := &"window"
const MODE_CROSSING := &"crossing"
const MODES: Array[StringName] = [MODE_WINDOW, MODE_CROSSING]

## How finely a curve is sampled to decide whether it is inside the band. A coarse
## sample would call a curve that just dips outside the band "inside", so this is
## fine - a centimetre on a garden of tens of metres.
const TOLERANCE := 0.01


static func is_mode(mode: StringName) -> bool:
	return MODES.has(mode)


## What the mode is called, so the status line, the menu and the module cannot
## call the same mode three different things.
static func mode_name(mode: StringName) -> String:
	if mode == MODE_CROSSING:
		return "Crossing"
	if mode == MODE_WINDOW:
		return "Window"
	return "?"


## The band as a rectangle, whatever order its corners were picked in.
static func band(first: Vector2, second: Vector2) -> Rect2:
	return Rect2(first, Vector2.ZERO).expand(second)


## Whether a band describes anything. A band with no area is a double click, not a
## selection, and it is refused rather than treated as a zero-size window.
static func band_reason(first: Vector2, second: Vector2) -> String:
	var rect := band(first, second)
	if rect.size.x <= Geom.EPS or rect.size.y <= Geom.EPS:
		return "a selection band with no area"
	return ""


## Whether a point is within the band. The edges count as inside: a shape that
## stops exactly on the band's edge has not left it.
static func within(rect: Rect2, point: Vector2) -> bool:
	return (
		point.x >= rect.position.x and point.x <= rect.end.x
		and point.y >= rect.position.y and point.y <= rect.end.y
	)


static func outline_of(entity, tolerance: float = TOLERANCE) -> PackedVector2Array:
	if entity == null:
		return PackedVector2Array()
	var points: PackedVector2Array = entity.outline(tolerance)
	if points.is_empty():
		# A label has a place but no linework, so it is caught by where it stands.
		# Without this a text entity could never be selected by anything at all.
		points = PackedVector2Array([entity.point(0)])
	return points


## Whether every point of a shape is within the band.
static func inside(entity, rect: Rect2, tolerance: float = TOLERANCE) -> bool:
	var outline := outline_of(entity, tolerance)
	if outline.is_empty():
		return false
	for point: Vector2 in outline:
		if not within(rect, point):
			return false
	return true


## Index-pairs of the band's four edges, as segments.
static func _edges(rect: Rect2) -> Array:
	var corners := PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	])
	var out: Array = []
	for index in 4:
		out.append([corners[index], corners[(index + 1) % 4]])
	return out


## The linework of a shape, as pairs of points.
##
## Only a **closed** shape is joined end to end. Joining an open one would invent a
## chord across it - an arc from (20,0) to (0,20) would grow a line straight through
## the middle of a band it never comes near, and a crossing sweep would take it.
static func _segments(entity, outline: PackedVector2Array) -> Array:
	var out: Array = []
	if outline.size() < 2:
		return out
	var closed: bool = entity != null and entity.is_closed()
	var last := outline.size() - 1 if not closed else outline.size()
	for index in last:
		out.append([outline[index], outline[(index + 1) % outline.size()]])
	return out


## Whether a shape meets the band: any of it inside, or any of its linework
## crossing the band's edge.
static func crossing(entity, rect: Rect2, tolerance: float = TOLERANCE) -> bool:
	var outline := outline_of(entity, tolerance)
	if outline.is_empty():
		return false
	for point: Vector2 in outline:
		if within(rect, point):
			return true
	var edges := _edges(rect)
	for segment: Array in _segments(entity, outline):
		for edge: Array in edges:
			var hit: Dictionary = Geom.segment_segment(segment[0], segment[1], edge[0], edge[1])
			if hit.get("hit", false):
				return true
	return false


## Whether a shape is caught by a band in this mode.
static func catches(entity, rect: Rect2, mode: StringName, tolerance: float = TOLERANCE) -> bool:
	if mode == MODE_CROSSING:
		return crossing(entity, rect, tolerance)
	return inside(entity, rect, tolerance)


## The ids a band catches, in the order the shapes were handed over.
##
## Annotations are *not* filtered out here. Selecting a dimension to move or erase
## is legitimate; it is the *action* that decides whether annotations are its
## business (an edit refuses them, because a drawing does not measure itself), and
## a selection that quietly dropped them would be a selection that lied about what
## is on the sheet. A label, which has a place and no linework, is caught by where
## it stands.
static func pick(
	entities: Array, rect: Rect2, mode: StringName, tolerance: float = TOLERANCE
) -> Dictionary:
	var ids: Array[int] = []
	for entity in entities:
		if catches(entity, rect, mode, tolerance):
			ids.append(int(entity.id))
	return {"ok": true, "reason": "", "ids": ids, "mode": mode, "rect": rect}


## The same rule by corners, which is what a person picks.
static func pick_between(
	entities: Array, first: Vector2, second: Vector2, mode: StringName, tolerance: float = TOLERANCE
) -> Dictionary:
	var reason := band_reason(first, second)
	if reason != "":
		return {"ok": false, "reason": reason, "ids": [], "mode": mode, "rect": band(first, second)}
	return pick(entities, band(first, second), mode, tolerance)


## One line for a status bar: what the band caught, and how it was swept.
static func describe(count: int, mode: StringName) -> String:
	var noun := "shape" if count == 1 else "shapes"
	return "%d %s selected (%s)" % [count, noun, mode_name(mode).to_lower()]