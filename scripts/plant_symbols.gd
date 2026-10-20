class_name PlantSymbols
extends RefCounted
## What a plant is drawn as on the plan: the figure behind every symbol, and the rule that says which
## symbol a species gets.
##
## A symbol is a *shape*, and there is exactly one description of it here. Three things already draw
## plants - the working plan (`PlanCanvas`), the swatch a photograph-less species gets in the grid
## (`PlantIcons`), and the painted plan's colour - and a shape written out three times is a plant that
## looks like one thing in the list and another on the drawing, which is exactly what this module
## exists to prevent.
##
## A **figure** is a list of parts in a *normalised* square: x and y run -1..1 about the centre, y
## downwards as an image has it, and the renderer multiplies each axis by half the footprint, so an
## oblong footprint makes an oblong symbol without the figure knowing anything about it. A part is one
## of six shapes and says whether it is filled, outlined or a mark:
##
## * `{"ink": "fill", "kind": "disc", "c": Vector2, "r": float}`
## * `{"ink": "fill", "kind": "poly", "points": PackedVector2Array}` - an enclosing polygon
## * `{"ink": "fill", "kind": "rect", "c": Vector2, "half": Vector2}`
## * `{"ink": "edge", "kind": "disc", "c": Vector2, "r": float, "w": float}` - a ring
## * `{"ink": "edge", "kind": "rect", "c": Vector2, "half": Vector2, "w": float}` - a rectangle ring
## * `{"ink": "edge", "kind": "line", "points": PackedVector2Array, "closed": bool, "w": float}`
## * `{"ink": "mark", "kind": "disc", "c": Vector2, "r": float}` - drawn over everything, in the mark
##   colour: a trunk, a bloom, a tuft.
##
## Widths, radii and coordinates are all in the same normalised units, so a stroke keeps its weight
## against the symbol whatever size the plant is drawn at.

const SpeciesScript := preload("res://scripts/plant_species.gd")

## The symbols, in the order a list offers them. A **form** is the prop a species stands in as - one
## tree model for every tree - and a **symbol** is the shape the plan draws for it, which is the thing
## a designer actually reads. The vocabulary lives here, with the one module that knows a shape,
## because the two cannot drift apart: a symbol a list can name is a symbol this file can draw.
const CANOPY := &"canopy"
const CONIFER := &"conifer"
const SHRUB := &"shrub"
const GRASS := &"grass"
const GROUNDCOVER := &"groundcover"
const VINE := &"vine"
const FERN := &"fern"
const BED := &"bed"
const MARKER := &"marker"
const NAMES: Array[StringName] = [
	CANOPY, CONIFER, SHRUB, GRASS, GROUNDCOVER, VINE, FERN, BED, MARKER,
]

## How each symbol is said out loud, for a label that has to name one.
const WORDS := {
	CANOPY: "a broadleaf canopy",
	CONIFER: "a conifer",
	SHRUB: "a soft shrub",
	GRASS: "an ornamental grass",
	GROUNDCOVER: "a groundcover mat",
	VINE: "a climbing vine",
	FERN: "a fern",
	BED: "a planted bed",
	MARKER: "a marker",
}

const INK_FILL := &"fill"
const INK_EDGE := &"edge"
const INK_MARK := &"mark"

## Node metadata: the symbol a planted node is drawn as. Written by `PlantPlacement` from the species
## at the moment it is planted, and read by `PlanStyle` - so what stands on the plan carries its own
## symbol, exactly as it carries its species, its height and its spread, and moving or copying the
## node in the editor cannot lose it.
const SYMBOL_META := &"symbol"

## How many points a wobbled outline is made of. Enough that the wobble has something to wander along
## without the symbol reading as a polygon.
const BLOB_STEPS := 48

## Figures are built on demand and kept: the plan asks for one per plant every frame, and a figure
## rebuilt sixty times a second is allocation for nothing. Keyed by symbol, so there is one figure per
## symbol however many species are drawn as it.
static var FIGURES: Dictionary = {}


## Whether a name is one of the symbols a species can be drawn as.
static func is_symbol(name: StringName) -> bool:
	return NAMES.has(name)


## One symbol's name as a label says it.
static func words(name: StringName) -> String:
	return String(WORDS.get(name, WORDS[MARKER]))


## Whether a symbol's footprint is round. The rest are oblong, the way a bed is: this is the whole
## reason a bed's plan symbol is not a disc, and it is a property of the symbol rather than of the
## prop, so a grass drawn as a bed is still planted round.
static func is_round(name: StringName) -> bool:
	match name:
		BED, MARKER:
			return false
	return true


## The footprint a symbol is drawn in, given the prop's own footprint. A round symbol is drawn round
## whatever the prop's footprint says, so a grass whose species is standing in as a flower bed does
## not come out as an oblong blade of grass.
static func shape_for(name: StringName, size: Vector2) -> Vector2:
	if not is_round(name):
		return size
	var longest: float = maxf(size.x, size.y)
	return Vector2(longest, longest)


## The symbol a species is drawn as. What the plant *is* comes first - a grass is drawn as a grass, a
## spruce as a conifer rather than as the maple's canopy - and a species whose category the form
## already describes (a perennial planted as a bed) falls through to what its prop draws as. A species
## with no entry at all is drawn as its prop, and an unknown prop as the marker, so nothing becomes
## invisible.
static func of(species: PlantSpecies, form_symbol: StringName) -> StringName:
	var fallback: StringName = form_symbol if is_symbol(form_symbol) else MARKER
	if species == null:
		return fallback
	var described: StringName = described_for(species)
	return described if not described.is_empty() else fallback


## The symbol the catalogue's own description of the plant calls for, or "" when it does not call for
## one. The categories whose form already says it - a perennial, an annual, a bulb, an herb, all
## planted as a bed - answer "", and so does a plant that is not in the catalogue.
static func described_for(species: PlantSpecies) -> StringName:
	if species == null:
		return &""
	match species.category:
		SpeciesScript.TREE:
			return CONIFER if species.is_conifer() else CANOPY
		SpeciesScript.SHRUB:
			return CONIFER if species.is_conifer() else SHRUB
		SpeciesScript.GRASS:
			return GRASS
		SpeciesScript.GROUNDCOVER:
			return GROUNDCOVER
		SpeciesScript.VINE:
			return VINE
		SpeciesScript.FERN:
			return FERN
	return &""


## The figure for a symbol: the parts to draw it, in normalised units. Never fails; a symbol nobody
## has is drawn as the marker rather than as nothing.
static func figure(name: StringName) -> Array[Dictionary]:
	var found: Variant = FIGURES.get(name)
	if found is Array:
		return found
	var made: Array[Dictionary] = _build(name)
	FIGURES[name] = made
	return made


## Let go of the built figures. They are pure data and are made again on demand, so this is only for
## a test that wants to see the builder run.
static func clear_cache() -> void:
	FIGURES.clear()


static func _build(name: StringName) -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	match name:
		CANOPY:
			parts.append(_disc(1.0))
			parts.append(_ring(1.0, 0.07))
			parts.append(_mark(0.18))
		CONIFER:
			parts.append(_disc(0.7))
			parts.append(_ring(0.7, 0.06))
			for needle in 14:
				var angle: float = TAU * float(needle) / 14.0
				var way := Vector2(cos(angle), sin(angle))
				parts.append(_line(PackedVector2Array([way * 0.62, way]), false, 0.09))
			parts.append(_mark(0.15))
		SHRUB:
			var shrub_ring: PackedVector2Array = _blob(1.0, 7, 0.13)
			parts.append(_poly(shrub_ring))
			parts.append(_line(shrub_ring, true, 0.06))
		GRASS:
			parts.append(_disc(0.30))
			for blade in 9:
				var blade_angle: float = TAU * float(blade) / 9.0
				var lean: float = 0.18 * (1.0 if blade % 2 == 0 else -1.0)
				parts.append(_line(PackedVector2Array([
					Vector2.ZERO,
					Vector2(cos(blade_angle + lean), sin(blade_angle + lean)) * 0.55,
					Vector2(cos(blade_angle), sin(blade_angle)),
				]), false, 0.08))
		GROUNDCOVER:
			var mat: PackedVector2Array = _blob(1.0, 11, 0.09)
			parts.append(_poly(mat))
			parts.append(_line(mat, true, 0.05))
			for tuft: Vector2 in [
				Vector2(0.0, 0.0), Vector2(0.5, 0.34), Vector2(-0.5, 0.34),
				Vector2(0.5, -0.34), Vector2(-0.5, -0.34),
			]:
				parts.append(_mark(0.12, tuft))
		VINE:
			var leaf_mass: PackedVector2Array = _blob(0.9, 5, 0.16)
			parts.append(_poly(leaf_mass))
			parts.append(_line(leaf_mass, true, 0.05))
			# The tendril, which is what tells a vine from a shrub at a glance: a spiral climbing out
			# of the leaf mass rather than another lobed edge.
			var tendril := PackedVector2Array()
			for step in 26:
				var travelled: float = float(step) / 25.0
				var spiral_angle: float = TAU * 2.25 * travelled
				tendril.append(
					Vector2(cos(spiral_angle), sin(spiral_angle)) * (0.30 + 0.66 * travelled)
				)
			parts.append(_line(tendril, false, 0.07))
		FERN:
			parts.append(_disc(0.22))
			for frond in 8:
				var frond_angle: float = TAU * float(frond) / 8.0
				var out := Vector2(cos(frond_angle), sin(frond_angle))
				parts.append(_line(PackedVector2Array([
					Vector2.ZERO, out.rotated(0.16) * 0.58, out.rotated(0.30),
				]), false, 0.07))
		BED:
			# A figure fills the normalised square, and the oblongness comes from the *footprint*: the
			# bed's prop is wider than it is deep, so the same square figure comes out as the oblong a
			# bed is drawn as. A figure that baked its own proportions in would be round again the
			# moment a species was drawn at a different size.
			parts.append(_rect(Vector2(1.0, 1.0)))
			parts.append(_rect_ring(Vector2(1.0, 1.0), 0.09))
			parts.append(_rect_ring(Vector2(0.86, 0.86), 0.04))
			for bloom: Vector2 in [
				Vector2(-0.60, 0.72), Vector2(-0.20, -0.72),
				Vector2(0.20, 0.72), Vector2(0.60, -0.72),
			]:
				parts.append(_mark(0.16, bloom))
		_:
			parts.append(_rect(Vector2(1.0, 1.0)))
			parts.append(_rect_ring(Vector2(1.0, 1.0), 0.08))
			parts.append(_line(PackedVector2Array([Vector2(-1.0, -1.0), Vector2(1.0, 1.0)]), false, 0.07))
			parts.append(_line(PackedVector2Array([Vector2(-1.0, 1.0), Vector2(1.0, -1.0)]), false, 0.07))
	return parts


## A wobbled circle: the soft edge a shrub or a mat has. `lobes` is how many times the outline swells
## round the circle and `depth` how far, as a fraction of the radius.
static func _blob(radius: float, lobes: int, depth: float) -> PackedVector2Array:
	var ring := PackedVector2Array()
	for step in BLOB_STEPS:
		var angle: float = TAU * float(step) / float(BLOB_STEPS)
		var swell: float = 1.0 + depth * sin(float(lobes) * angle)
		ring.append(Vector2(cos(angle), sin(angle)) * radius * swell)
	return ring


static func _disc(radius: float) -> Dictionary:
	return {"ink": INK_FILL, "kind": "disc", "c": Vector2.ZERO, "r": radius}


static func _poly(points: PackedVector2Array) -> Dictionary:
	return {"ink": INK_FILL, "kind": "poly", "points": points}


static func _rect(half: Vector2) -> Dictionary:
	return {"ink": INK_FILL, "kind": "rect", "c": Vector2.ZERO, "half": half}


static func _ring(radius: float, width: float) -> Dictionary:
	return {"ink": INK_EDGE, "kind": "disc", "c": Vector2.ZERO, "r": radius, "w": width}


static func _rect_ring(half: Vector2, width: float) -> Dictionary:
	return {"ink": INK_EDGE, "kind": "rect", "c": Vector2.ZERO, "half": half, "w": width}


static func _line(points: PackedVector2Array, closed: bool, width: float) -> Dictionary:
	return {"ink": INK_EDGE, "kind": "line", "points": points, "closed": closed, "w": width}


static func _mark(radius: float, at: Vector2 = Vector2.ZERO) -> Dictionary:
	return {"ink": INK_MARK, "kind": "disc", "c": at, "r": radius}