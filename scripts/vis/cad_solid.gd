class_name CadSolid
extends RefCounted
## Outline, and later solid, from the drawing's own entities (§8.2).
##
## Every outline comes from `DraftEntity.outline()`, the same function the working
## plan, the 3D overlay and the plotted sheet draw from, so a patio's wash, its
## plotted outline and (from phase 3) its 3D slab are the shape that was drawn.
## Nothing here reads an entity's parameter array for itself, which is what keeps
## "the mesh is a picture of the entity" true rather than approximately true
## (REQ-V2.1).
##
## This file grows into slabs and ribbons in phase 3; everything here is what the
## wash needs first.

const EntityScript := preload("res://scripts/draft/draft_entity.gd")
const Geom := preload("res://scripts/draft/geom2d.gd")

## Entity kinds that enclose ground. An arc, a line or an open polyline encloses
## nothing until the drawer closes it, and an annotation is not ground at all
## (drafting subsystem §4).
const AREAS: Array[int] = [
	EntityScript.Kind.CIRCLE,
	EntityScript.Kind.POLYGON,
	EntityScript.Kind.RECT,
	EntityScript.Kind.REGULAR_POLY,
]

## Fewer points than this and there is no ring: a triangle is the smallest thing
## with an inside.
const MIN_RING_POINTS := 3


## Whether an entity encloses ground.
static func is_area(entity: EntityScript) -> bool:
	return entity != null and AREAS.has(int(entity.kind))


## The closed outline of an area entity, in model metres, as a ring.
##
## Empty for anything that does not enclose ground: refused rather than guessed at,
## because a wash or a slab made from an open outline is a shape the designer never
## drew.
static func outline_of(entity: EntityScript) -> PackedVector2Array:
	if not is_area(entity):
		return PackedVector2Array()
	return ring(entity.outline())


## A ring: the closing duplicate dropped, and the winding made positive.
##
## A sampled circle arrives with its last point equal to its first, and every
## consumer here either triangulates the ring, offsets it or fills it - all three of
## which treat a repeated vertex as a zero-length edge. The winding is fixed here so
## no downstream function has to ask which way round a bed was drawn: positive
## shoelace, which is this project's convention for an area and the direction an
## offset grows outward in.
##
## Degenerate input gives an empty array rather than a small ring, so a caller can
## tell "no area" from "a tiny area" with one check.
static func ring(points: PackedVector2Array) -> PackedVector2Array:
	var out := points
	while out.size() >= 2 and out[out.size() - 1].is_equal_approx(out[0]):
		out = out.slice(0, out.size() - 1)
	if out.size() < MIN_RING_POINTS:
		return PackedVector2Array()
	if Geom.polygon_signed_area(out) < 0.0:
		out.reverse()
	return out


## The area of a ring in square metres, which is what a material quantity is
## measured in. Zero for anything degenerate.
static func area_m2(ring_points: PackedVector2Array) -> float:
	return Geom.polygon_area(ring_points)


## Whether a ring can be filled: enough points, and no edge crossing another.
##
## `Geom.polygon_is_simple` rather than a crossing test written here, because the
## drafting subsystem already refuses a self-intersecting polygon when it is drawn
## and one implementation of "does this cross itself" is one place to be wrong.
static func is_fillable(ring_points: PackedVector2Array) -> bool:
	if ring_points.size() < MIN_RING_POINTS:
		return false
	return Geom.polygon_is_simple(ring_points)


## Why a ring cannot be used, for a message that names the problem rather than
## reporting a count.
static func refusal_for(ring_points: PackedVector2Array) -> String:
	if ring_points.size() < MIN_RING_POINTS:
		return "an outline needs at least %d points and has %d" % [
			MIN_RING_POINTS, ring_points.size(),
		]
	if not Geom.polygon_is_simple(ring_points):
		return "the outline crosses itself"
	if absf(Geom.polygon_signed_area(ring_points)) <= Geom.EPS:
		return "the outline encloses no area"
	return ""