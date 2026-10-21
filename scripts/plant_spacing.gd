class_name PlantSpacing
extends RefCounted
## Planting a bed at a spacing, rather than a plant at a time.
##
## A designer does not place a hedge fourteen clicks at a time. They say "45 cm apart, staggered" and
## the plan answers with the planting, and the reason to have that here rather than in the palette is
## that it is arithmetic: the bed is an outline the plan already draws, the spacing is a number, and
## what a plant goes at is decided by a rule that has to be the same rule every time. It is the *only*
## place those points are decided, so the symbols on the plan, the props in the yard, the count in the
## planting schedule and the quantity in the takeoff cannot disagree about how many plants there are.
##
## Two arrangements, because planting is not a lattice:
##
## * `SQUARE` sets rows and columns one spacing apart.
## * `TRIANGULAR` sets each row half a spacing across from the one before it and `sqrt(3)/2` of a
##   spacing apart, which is the denser arrangement a planting plan actually shows: every plant is the
##   same distance from its four neighbours in the row and its two in the rows above and below, so the
##   bed fills evenly instead of leaving diamond-shaped gaps. Over a large bed it packs `2/sqrt(3)`,
##   about 15%, more plants into the same ground - less than that in a small one, where the edges take
##   most of the gain. A design at 0.3 m in a four by three metre bed comes out 99 square and 104
##   staggered, which is the honest size of the difference on a bed somebody would actually plant.
##
## Nothing here knows about species, catalogues or nodes. `fill()` is the one function that plants
## anything, and it plants by asking `PlantPlacement` to place each point, so a filled bed is a bed of
## ordinary planted props that both views, the schedule and the takeoff already read.
##
## Two rules the arithmetic is built on, both of them horticulture rather than taste:
##
## * **A plant is pulled in from the edge by half its own spread**, so the plant drawn on the edge
##   stands inside the bed rather than hanging over the lawn beside it.
## * **The spacing defaults to the species' own spread**, so a bed filled with no number given has its
##   plants just touching - which is what a nursery means by "plant at the recommended spacing".
##
## Coordinates are the drawing's own: the outline is in model metres, and a point becomes a world
## position the way everything else in the draft does it, `Vector3(x, 0, y)`, north being -Z.

const Geom := preload("res://scripts/draft/geom2d.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")
const PlacementScript := preload("res://scripts/plant_placement.gd")
const ZoneMapScript := preload("res://scripts/zone_map.gd")
const LayerSetScript := preload("res://scripts/draft/layer_set.gd")

const SQUARE := "square"
const TRIANGULAR := "triangular"
const ARRANGEMENTS: Array[String] = [SQUARE, TRIANGULAR]
const ARRANGEMENT_NAMES := {
	SQUARE: "Square",
	TRIANGULAR: "Staggered",
}

## The layers a planting goes in. Taken from the layer set rather than written out here, so a layer
## renamed in one place cannot leave a fill planting into a driveway.
const PLANTABLE: Array[StringName] = [
	LayerSetScript.NEW_BED,
	LayerSetScript.EXISTING_PLANTING,
]

## The tightest spacing worth drawing. A plant 5 cm from its neighbour is a seed bed, not a plan,
## and a grid finer than this is also how a fill would turn into a million points by accident.
const MIN_SPACING_M := 0.05

## How many plants one fill puts down. This is a *stated* limit rather than a performance guard: a bed
## that wants two thousand plants wants a spacing that says so, and a fill that quietly put down the
## first few hundred would leave a half-planted bed with a planting schedule to match. Over it, the
## fill refuses and names the limit.
const MAX_PLANTS := 500

## A safety net and nothing else, for an outline with a huge bounding box and almost nothing in it. A
## person never reaches this; a loop that cannot end would be worse than a refusal.
const MAX_GRID := 250000

## Numbers here are compared against geometry the drawing produced, so equality is to a millimetre and
## not to the last bit of a double.
const TOLERANCE := 1e-6


# --- the numbers a fill is asked for ------------------------------------------------------


## The spacings a palette offers, in metres. Round steps a designer says out loud, plus zero, which
## means "the species' own spread" - first in the list because it is the right answer most of the time
## and the one that needs no thought.
static func spacing_choices_m() -> Array[float]:
	return [0.0, 0.15, 0.2, 0.3, 0.45, 0.6, 0.9, 1.2, 1.8, 2.4, 3.0]


## A spacing as a person writes it: "0.45 m", "1.2 m", "2 m". Trailing zeroes are noise in a status
## line and two decimals is a centimetre.
static func spacing_words(metres: float) -> String:
	var rounded := roundf(metres * 1000.0) / 1000.0
	if absf(rounded - roundf(rounded)) < TOLERANCE:
		return "%d m" % int(roundf(rounded))
	if absf(rounded * 10.0 - roundf(rounded * 10.0)) < TOLERANCE:
		return "%.1f m" % rounded
	return "%.2f m" % rounded


static func is_arrangement(value: String) -> bool:
	return ARRANGEMENTS.has(value)


## "Staggered", or the arrangement's own name back if something unknown got through - a label is not
## the place to enforce a rule, and a status line that says "unknown" helps nobody.
static func arrangement_words(arrangement: String) -> String:
	return String(ARRANGEMENT_NAMES.get(arrangement, arrangement))


## What the species spreads, floored at the tightest spacing this will draw. A species with no spread
## recorded cannot be spaced by its own size, so it gets the floor rather than an error: the catalogue
## already refuses a species that cannot be drawn, and this is a species that can be drawn but is not
## described.
static func spread_of(species: PlantSpecies) -> float:
	if species == null:
		return MIN_SPACING_M
	return maxf(species.spread_m(), MIN_SPACING_M)


## Half a spread from the edge, which puts the edge plant's canopy on the bed's edge instead of over
## the lawn.
static func clearance_of(species: PlantSpecies) -> float:
	return spread_of(species) * 0.5


# --- where the plants go ------------------------------------------------------------------


## The distance from a point to the nearest edge of a closed outline.
static func distance_to_outline(point: Vector2, outline: PackedVector2Array) -> float:
	var best := INF
	var count := outline.size()
	if count < 2:
		return best
	for index in count:
		var from := outline[index]
		var to := outline[(index + 1) % count]
		# A ring that repeats its first point has one edge of no length, and `distance_to_segment`
		# answers that one with the point itself rather than with a NaN. Skipped anyway, because an
		# edge of no length is not an edge.
		if from.distance_squared_to(to) <= TOLERANCE:
			continue
		best = minf(best, Geom.distance_to_segment(point, from, to))
	return best


## What is wrong with the numbers, or "" when nothing is.
##
## Kept apart from the working-out so a button can ask whether it is any use *before* it is pressed:
## a fill that has to be attempted to find out it was impossible is a fill that plants something
## first.
static func problem(outline: PackedVector2Array, spacing: float, clearance: float) -> String:
	if outline.size() < 3:
		return "that is not an outline the plan encloses"
	if Geom.polygon_area(outline) <= TOLERANCE:
		return "that outline encloses no ground"
	if spacing < MIN_SPACING_M:
		return "a spacing of %s is tighter than a plan draws" % spacing_words(spacing)
	if clearance < 0.0:
		return "a plant cannot stand outside the bed it is in"
	return ""


## The fill, worked out and not planted: `{ok, reason, points, wanted}`.
##
## `points` is at most `MAX_PLANTS` long; `wanted` is how many the rule actually asks for, which is
## what tells the difference between a bed that takes four hundred plants and one that wants forty
## thousand. `positions()` and `count_for()` are the two questions a caller usually has, and both are
## this function.
##
## The grid's phase comes from `origin`, so two beds filled one after another carry on one grid rather
## than each starting a pattern of its own at its own corner.
static func plan_fill(
	outline: PackedVector2Array, spacing: float, arrangement: String = SQUARE,
	clearance: float = 0.0, origin: Vector2 = Vector2.ZERO
) -> Dictionary:
	var refuse := problem(outline, spacing, clearance)
	if not refuse.is_empty():
		return {"ok": false, "reason": refuse, "points": PackedVector2Array(), "wanted": 0}
	var row_step := spacing
	if arrangement == TRIANGULAR:
		row_step = spacing * sqrt(3.0) * 0.5
	var box := Geom.points_aabb(outline)
	var points := PackedVector2Array()
	var wanted := 0
	var budget := MAX_GRID
	# The first grid line at or beyond the box, in each direction, so the points a fill returns do not
	# depend on where the outline happens to start.
	var y: float = origin.y + ceilf((box.position.y - origin.y) / row_step) * row_step
	var row := 0
	# The working-out stops the moment the answer is "more than a fill puts down": counting the rest
	# would be work nobody asked for, and a bed that takes two thousand plants is refused either way.
	var enough := false
	while y <= box.end.y + TOLERANCE and budget > 0 and not enough:
		# Every other row of a staggered grid starts half a spacing across, which is what makes the
		# neighbours in the rows above and below the same distance away as the ones beside it.
		var shift := 0.0
		if arrangement == TRIANGULAR and row % 2 == 1:
			shift = spacing * 0.5
		var x: float = origin.x + ceilf((box.position.x - origin.x - shift) / spacing) * spacing + shift
		while x <= box.end.x + TOLERANCE and budget > 0 and not enough:
			budget -= 1
			var candidate := Vector2(x, y)
			var keeps_clear := clearance <= 0.0 \
				or distance_to_outline(candidate, outline) >= clearance - TOLERANCE
			if keeps_clear and Geom.point_in_polygon(candidate, outline):
				wanted += 1
				if points.size() < MAX_PLANTS:
					points.append(candidate)
				enough = wanted > MAX_PLANTS
			x += spacing
		y += row_step
		row += 1
	if budget <= 0:
		return {
			"ok": false,
			"reason": "that outline covers more ground than a fill at %s can work out" % spacing_words(spacing),
			"points": PackedVector2Array(),
			"wanted": 0,
		}
	if wanted > MAX_PLANTS:
		# The count is not named because it was not counted: the working-out stops as soon as the
		# answer is "too many", and a refusal that quoted a number it did not finish counting would be
		# a lie that reads like precision.
		return {
			"ok": false,
			"reason": "at %s apart this bed takes more than %d plants, which is more than one fill puts down. Space them further apart." % [
				spacing_words(spacing), MAX_PLANTS
			],
			"points": points,
			"wanted": wanted,
		}
	return {"ok": true, "reason": "", "points": points, "wanted": wanted}


## The positions a fill would plant at, for a caller that wants only them.
static func positions(
	outline: PackedVector2Array, spacing: float, arrangement: String = SQUARE,
	clearance: float = 0.0, origin: Vector2 = Vector2.ZERO
) -> PackedVector2Array:
	return plan_fill(outline, spacing, arrangement, clearance, origin)["points"]


## How many plants a bed takes at a spacing, without planting any. This is the number a designer asks
## for before agreeing to it, and under the cap it is the same number the schedule will end up
## carrying. Over the cap it is `MAX_PLANTS + 1`, which is the question "is this too many" answered
## rather than a count nobody needs - the working-out stops as soon as the answer is "too many".
static func count_for(
	outline: PackedVector2Array, spacing: float, arrangement: String = SQUARE,
	clearance: float = 0.0, origin: Vector2 = Vector2.ZERO
) -> int:
	return int(plan_fill(outline, spacing, arrangement, clearance, origin)["wanted"])


# --- planting it ----------------------------------------------------------------------------


## Fill a bed: work out the points and plant one species at each of them.
##
## `options` carries `spacing` (0 or less means the species' own spread), `arrangement`, `clearance`
## (less than 0 means half the species' spread) and `origin`.
##
## Returns `{ok, reason, placed, wanted, points, nodes, species, species_id, spacing, arrangement,
## clearance, area_m2}`. A refusal names the reason, and a refusal on the *first* plant names the
## reason `PlantPlacement` gave, because a species whose scene is not on disk is a refusal about the
## plant and not about the spacing.
static func fill(
	catalogue: PlantCatalogue, yard: Node, species_id: StringName, outline: PackedVector2Array,
	options: Dictionary = {}
) -> Dictionary:
	if catalogue == null:
		return _report("there is no plant list open", species_id)
	var species: PlantSpecies = catalogue.get_species(species_id)
	if species == null:
		return _report("the plant list has no species %s" % species_id, species_id)

	var spacing := float(options.get("spacing", 0.0))
	if spacing < MIN_SPACING_M:
		spacing = spread_of(species)
	var arrangement := String(options.get("arrangement", SQUARE))
	if not is_arrangement(arrangement):
		arrangement = SQUARE
	var clearance := float(options.get("clearance", -1.0))
	if clearance < 0.0:
		clearance = clearance_of(species)
	var origin: Vector2 = options.get("origin", Vector2.ZERO)

	var worked: Dictionary = plan_fill(outline, spacing, arrangement, clearance, origin)
	var report := _report(String(worked["reason"]), species_id)
	report["species"] = species
	report["spacing"] = spacing
	report["arrangement"] = arrangement
	report["clearance"] = clearance
	report["wanted"] = int(worked["wanted"])
	report["points"] = worked["points"]
	report["area_m2"] = Geom.polygon_area(outline)
	if not bool(worked["ok"]):
		return report
	if (worked["points"] as PackedVector2Array).is_empty():
		# The arithmetic found no room at all, and a refusal that said nothing would be a button that
		# did nothing. The sentence says the two numbers that caused it, so the answer is a spacing or
		# a smaller plant rather than a guess.
		report["reason"] = (
			"a %s plant stood %s in from the edge needs a bed more than %s across, and this one has no room for it"
			% [spacing_words(spacing), spacing_words(clearance), spacing_words(spacing)]
		)
		return report

	var nodes: Array[Node3D] = []
	var first_reason := ""
	for point: Vector2 in worked["points"]:
		# Model metres to world: the draft's y runs south and the world's -Z is north, so a point
		# becomes `Vector3(x, 0, y)` - the mapping `CadSolid` builds its meshes with, so a filled bed
		# stands under the same drawing the plan shows.
		var landed: Dictionary = PlacementScript.place(
			catalogue, species_id, yard, Vector3(point.x, 0.0, point.y)
		)
		if bool(landed["ok"]):
			nodes.append(landed["node"])
		elif first_reason.is_empty():
			first_reason = String(landed["reason"])
	report["placed"] = nodes.size()
	report["nodes"] = nodes
	if nodes.is_empty():
		report["reason"] = first_reason
		return report
	report["ok"] = true
	# A plant that would not go in is named even when the rest of the bed did: a bed with three gaps
	# in it and a status line about the fourteen that landed is a bed somebody has to count.
	if not first_reason.is_empty():
		report["reason"] = "%d of %d went in: %s" % [
			nodes.size(), int(worked["wanted"]), first_reason
		]
	return report


static func _report(reason: String, species_id: StringName) -> Dictionary:
	var nodes: Array[Node3D] = []
	return {
		"ok": false,
		"reason": reason,
		"species": null,
		"species_id": species_id,
		"placed": 0,
		"wanted": 0,
		"points": PackedVector2Array(),
		"nodes": nodes,
		"spacing": 0.0,
		"arrangement": SQUARE,
		"clearance": 0.0,
		"area_m2": 0.0,
	}


## What a fill did, as one line for a status bar: "38 x Thymus serpyllum at 0.3 m, staggered". A
## refusal is that refusal, because the line a person reads after pressing the button has to be the
## line that says why nothing happened.
static func report_words(report: Dictionary) -> String:
	if not bool(report.get("ok", false)):
		var said := String(report.get("reason", ""))
		return said if not said.is_empty() else "nothing was planted"
	var species: PlantSpecies = report.get("species")
	var who := String(report.get("species_id", ""))
	if species != null:
		who = species.display_name()
	return "%d x %s at %s, %s" % [
		int(report.get("placed", 0)), who,
		spacing_words(float(report.get("spacing", 0.0))),
		arrangement_words(String(report.get("arrangement", SQUARE))).to_lower(),
	]


# --- the beds a plan offers ----------------------------------------------------------------


## The areas of a drawing a planting can go in, in draw order - the beds and the planting that is
## already there, and not the paving, the lawn or the house, which `ZoneMap.areas_of` also reports
## because the *ground* can be stated for any of them.
##
## Each row is `ZoneMap.areas_of`'s own: `{entity_id, layer, key, label, name, outline, area_m2}`.
static func bed_areas(document: DraftDocument, min_area: float = 0.5) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Dictionary in ZoneMapScript.areas_of(document, min_area):
		if PLANTABLE.has(StringName(row["layer"])):
			out.append(row)
	return out


## One bed as a list reads it: "bed 4, 6.2 m2". The name comes from the area rather than from a
## counter here, so the list a designer picks from and the list the ground window shows name the same
## bed the same way. The area is written in the drawing's own units, by the one function that writes
## one (see `ZoneMap.area_words`), so an imperial drawing says square feet here too.
static func bed_words(row: Dictionary) -> String:
	return "%s, %s" % [String(row.get("name", "")), ZoneMapScript.row_area_text(row)]