class_name Irrigation

## The arithmetic of where the water goes: heads, zones, and whether a zone will run.
##
## A garden plan says where the water goes, and this is the part of that which is arithmetic rather
## than drawing. It holds three things and no geometry of its own:
##
## * A **head kind** is a table row, not a free field: a flow in litres per minute, a throw in
##   metres, a default arc and the pressure it wants. A plan holding a head that waters four metres
##   and draws nothing would make every check downstream arithmetic on a number nobody could check.
## * A **zone** is a valve and the heads it opens. Its demand is the sum of its heads, and that is
##   the whole reason a plan is divided into zones at all.
## * A **supply** is a flow at a pressure, and it is *stated*. A zone with no supply stated is
##   refused rather than blessed - the same decision the DXF reader makes about `$INSUNITS`, for the
##   same reason: a check that silently assumed forty litres a minute would pass a plan that cannot
##   be built, and a designer would find out from a dry bed.
##
## The two questions a designer actually asks are answered here, and both are measured rather than
## asserted:
##
## * **Will it run?** `check()` sums the heads and compares them with the supply, in words that name
##   the numbers: not "too many heads" but "12 spray heads draw 108.0 L/min and the supply gives
##   40.0 - 4 heads fit".
## * **Does it cover the ground?** `coverage()` samples the area on a stated grid and asks, point by
##   point, whether some head reaches it - inside its throw *and* inside its arc. A shortfall is
##   reported as a fraction, because a designer may water a bed on drip and leave a mature tree to
##   the rain: a gap is a fact, where an overloaded valve is a defect.
##
## Laying the heads out is not re-invented either: a zone is set on the **same grid a bed is
## planted on** (`PlantSpacing`), because head-to-head spacing and triangular spacing are the same
## rule as plant spacing, and because two implementations of one grid would eventually disagree.
## Triangular is the arrangement that matters: rows `sqrt(3)/2` of a spacing apart cover the same
## ground with the spacing taken out to 1.155 times the throw, which is about 15% fewer heads - the
## biggest saving there is in an irrigation layout.
##
## Nothing here draws. A placed head is a circle on `500-IRRIGATION` carrying its kind, its zone
## and its heading (see `drafting-subsystem-spec.md` section 5 for the layer), so the takeoff and
## the sheet already see it with no second model to keep in step.
##
## Specified in `docs/irrigation-subsystem-spec.md`.

const Geom := preload("res://scripts/draft/geom2d.gd")
const SpacingScript := preload("res://scripts/plant_spacing.gd")
const LayerSetScript := preload("res://scripts/draft/layer_set.gd")
const EntityScript := preload("res://scripts/draft/draft_entity.gd")

## The kinds of head. Strings rather than StringNames because these are keys in a constant
## dictionary, and a constant expression cannot hold a StringName key.
const SPRAY := "spray"
const ROTOR := "rotor"
const MICRO := "micro"
const BUBBLER := "bubbler"
const KINDS: Array[String] = [SPRAY, ROTOR, MICRO, BUBBLER]

## The head table. Flows and pressures are the real numbers a manufacturer's sheet carries: a 4.5 m
## spray head at nine litres a minute is about 25 mm/h over the ground it waters, and a rotor at
## thirteen over the eleven metres it throws is about 6 mm/h - which is why the two cannot share a
## valve, and why the precipitation rate is the number a designer checks.
const HEADS := {
	SPRAY: {"name": "spray head", "flow": 9.0, "throw": 4.5, "arc": 180.0, "pressure": 210.0},
	ROTOR: {"name": "gear rotor", "flow": 13.0, "throw": 11.0, "arc": 360.0, "pressure": 350.0},
	MICRO: {"name": "micro-spray", "flow": 3.0, "throw": 2.5, "arc": 180.0, "pressure": 200.0},
	BUBBLER: {"name": "bubbler", "flow": 8.0, "throw": 0.9, "arc": 360.0, "pressure": 150.0},
}

## A full circle is the arc that has no heading: where the point is, a full head reaches it.
const ARC_FULL := 360.0

## How far inside a nozzle's edge counts as watered, in radians - about half a degree. A point lying
## exactly on the boundary of a half-circle's pattern is watered by that nozzle, and without this the
## coverage check would report a shortfall that is float arithmetic rather than a dry bed: a half
## head facing across a strip leaves every sample along the strip on its own ±90 degree edge.
const ARC_EDGE := 0.01

## The nozzles a head is sold with, in degrees. The arc a position wants is rounded to one of
## these, because that is what a designer can actually buy and fit.
const NOZZLES: Array[float] = [90.0, 180.0, 270.0, 360.0]

## A layout sets a head on the grid line and not pulled in from it: a *head* is not a plant. A plant
## is pulled in by half its spread so its canopy lands on the edge rather than over the lawn, but a
## head stands where its water is wanted, and the boundary is exactly where that is - the nozzle is
## what keeps the water in, and a head shoved half a throw inside leaves the ground behind it dry.
const CLEARANCE_SHARE := 0.0

## The spacing a triangular grid can carry over the same ground as a square one at one throw:
## 2 / sqrt(3), which is the ~15% saving in heads.
const TRIANGULAR_SPACING := 1.1547005383792517

const MIN_SPACING_M := 0.05

## How many heads one zone is laid out with. A *stated* limit rather than a performance guard: a
## zone that wants more wants dividing into zones, and a layout that quietly set down the first few
## hundred would leave a half-watered zone with a schedule to match.
const MAX_HEADS := 300

## The grid the coverage check samples the area on, in metres. Stated because a coverage figure
## without its sampling is a number nobody can argue with.
const SAMPLE_GRID := 0.5

## How many rays round a head are sampled to work out the arc of ground around it, and at what
## fraction of its throw they are tested.
const NOZZLE_STEPS := 24
const NOZZLE_RADIUS := 0.9

## What a panel offers as the starting supply. The model never assumes it: it is a number to type
## over, and a zone with no supply stated is refused.
const DEFAULT_SUPPLY_FLOW := 40.0
const DEFAULT_SUPPLY_PRESSURE := 350.0

const TOLERANCE := 1e-6


# --- the head table -----------------------------------------------------------------


## The layer heads and runs live on, taken from the layer set so a layer renamed in one place cannot
## leave a head on a driveway.
static func layer() -> StringName:
	return LayerSetScript.IRRIGATION


static func is_kind(value: String) -> bool:
	return HEADS.has(value)


## The kinds, in the order a palette offers them: the one a designer reaches for most first.
static func kind_list() -> Array[String]:
	return KINDS.duplicate()


## What a drop-down shows for each kind.
static func kind_names() -> Array[String]:
	var out: Array[String] = []
	for kind in KINDS:
		out.append(String(HEADS[kind]["name"]))
	return out


## The kind behind a name a drop-down was showing, so a panel can turn its own choice back into one.
static func kind_for_name(shown: String) -> String:
	for kind in KINDS:
		if String(HEADS[kind]["name"]) == shown:
			return kind
	return ""


## "a spray head", for a sentence: "a zone of 4 spray heads".
static func kind_words(kind: String) -> String:
	if not is_kind(kind):
		return "a head nobody knows"
	return "a " + String(HEADS[kind]["name"])


## "spray head", for a table cell.
static func kind_name(kind: String) -> String:
	if not is_kind(kind):
		return "unknown head"
	return String(HEADS[kind]["name"])


## The plural a schedule writes: "4 spray heads".
static func kind_count_words(kind: String, count: int) -> String:
	var one := kind_name(kind)
	if count == 1:
		return "1 %s" % one
	return "%d %ss" % [count, one]


static func flow_of_kind(kind: String) -> float:
	if not is_kind(kind):
		return 0.0
	return float(HEADS[kind]["flow"])


static func throw_of_kind(kind: String) -> float:
	if not is_kind(kind):
		return 0.0
	return float(HEADS[kind]["throw"])


static func arc_of_kind(kind: String) -> float:
	if not is_kind(kind):
		return 0.0
	return float(HEADS[kind]["arc"])


static func pressure_of_kind(kind: String) -> float:
	if not is_kind(kind):
		return 0.0
	return float(HEADS[kind]["pressure"])


# --- the supply ---------------------------------------------------------------------


## A supply: a flow in litres per minute at a stated pressure in kilopascals.
static func make_supply(flow: float, pressure: float) -> Dictionary:
	return {"flow": flow, "pressure": pressure}


## Whether anything has actually been stated. A supply with no flow is not a supply, and neither is
## a dictionary that never held one, so a zone is checked against this before anything else.
static func has_supply(supply: Dictionary) -> bool:
	return float(supply.get("flow", 0.0)) > TOLERANCE


static func supply_words(supply: Dictionary) -> String:
	if not has_supply(supply):
		return "no supply stated"
	return "%s L/min at %s kPa" % [_number(float(supply.get("flow", 0.0))),
		_number(float(supply.get("pressure", 0.0)))]


## How many heads of a kind the supply can run. This is the number a refusal quotes, and the number
## a panel shows beside the supply so a designer can see the budget before laying anything out.
static func head_budget(supply: Dictionary, kind: String) -> int:
	var per_head := flow_of_kind(kind)
	if per_head <= TOLERANCE or not has_supply(supply):
		return 0
	return int(floor(float(supply["flow"]) / per_head + TOLERANCE))


# --- a zone -------------------------------------------------------------------------


static func make_zone(number: int, kind: String = SPRAY) -> Dictionary:
	return {
		"number": number,
		"valve": number,
		"kind": kind,
		"area": PackedVector2Array(),
		"area_m2": 0.0,
		"heads": [],
		"spacing": 0.0,
		"staggered": false,
	}


static func zone_label(zone: Dictionary) -> String:
	return "Zone %d" % int(zone.get("number", 0))


## The number a new zone takes: one past the highest in use, so a deleted zone's number is not
## handed to a different bed.
static func next_number(zones: Array) -> int:
	var highest := 0
	for entry in zones:
		highest = maxi(highest, int((entry as Dictionary).get("number", 0)))
	return highest + 1


## The lowest valve number not in use. Valves are numbered by place on the manifold, so a valve
## freed by a zone that went away is the next one to hand out.
static func next_valve(zones: Array) -> int:
	var taken: Array[int] = []
	for entry in zones:
		taken.append(int((entry as Dictionary).get("valve", 0)))
	var candidate := 1
	while taken.has(candidate):
		candidate += 1
	return candidate


## Give a zone the ring it waters. A zone can be laid out without one - heads placed by hand know
## where they are - and then coverage and precipitation cannot be worked out, which the report says
## rather than guessing.
static func set_area(zone: Dictionary, ring: PackedVector2Array) -> void:
	zone["area"] = ring
	zone["area_m2"] = 0.0 if ring.size() < 3 else Geom.polygon_area(ring)


static func area_m2(zone: Dictionary) -> float:
	return float(zone.get("area_m2", 0.0))


## The area as words on this drawing: the drawing's own units when one was handed over, and the metre
## default otherwise. **This is the one place this module turns an area into text**, so the verdict
## line, the schedule row and the sheet cannot disagree about it.
static func _area_text(square_metres: float, units: DraftUnits) -> String:
	return units.format_area(square_metres) if units != null else DraftUnits.area_words(square_metres)


## A schedule row's own area words. A row built by this module carries `area_text`; a row built by hand
## falls back to the units it was handed, or the metre default.
static func _row_area_text(row: Dictionary, units: DraftUnits) -> String:
	if row.has("area_text"):
		return String(row["area_text"])
	return _area_text(float(row.get("area_m2", 0.0)), units)


static func has_area(zone: Dictionary) -> bool:
	return area_m2(zone) > TOLERANCE


static func ring_of(zone: Dictionary) -> PackedVector2Array:
	return zone.get("area", PackedVector2Array())


# --- heads --------------------------------------------------------------------------


## Set a head at a position. `arc` of zero means the kind's own default; the heading is the
## direction a part-circle nozzle faces, in radians, and is ignored by a full circle.
static func add_head(zone: Dictionary, at: Vector2, kind: String = "",
		heading: float = 0.0, arc: float = 0.0) -> Dictionary:
	var use := kind if is_kind(kind) else String(zone.get("kind", SPRAY))
	var head := {"kind": use, "at": at, "heading": heading, "arc": arc}
	(zone["heads"] as Array).append(head)
	return head


static func head_count(zone: Dictionary) -> int:
	return (zone.get("heads", []) as Array).size()


static func heads_of(zone: Dictionary) -> Array:
	return zone.get("heads", [])


static func clear_heads(zone: Dictionary) -> void:
	zone["heads"] = []


static func remove_head(zone: Dictionary, index: int) -> bool:
	var heads: Array = zone.get("heads", [])
	if index < 0 or index >= heads.size():
		return false
	heads.remove_at(index)
	return true


## The arc a head is fitted with: its own if it was given one, the kind's default otherwise.
static func arc_of_head(head: Dictionary) -> float:
	var arc := float(head.get("arc", 0.0))
	if arc > TOLERANCE:
		return minf(arc, ARC_FULL)
	var kind := String(head.get("kind", ""))
	var own := arc_of_kind(kind)
	return ARC_FULL if own <= TOLERANCE else own


## Whether a head's water reaches a point: within its throw, and within its arc.
static func reaches(head: Dictionary, point: Vector2) -> bool:
	var kind := String(head.get("kind", ""))
	var away := point - Vector2(head.get("at", Vector2.ZERO))
	var distance := away.length()
	if distance > throw_of_kind(kind) + TOLERANCE:
		return false
	var arc := deg_to_rad(arc_of_head(head))
	if arc >= deg_to_rad(ARC_FULL) - TOLERANCE or distance <= TOLERANCE:
		return true
	var heading := float(head.get("heading", 0.0))
	return Geom.angle_in_sweep(Geom.angle_of(away), heading - arc * 0.5 - ARC_EDGE, arc
		+ ARC_EDGE * 2.0)


static func covered_by(heads: Array, point: Vector2) -> bool:
	for entry in heads:
		if reaches(entry as Dictionary, point):
			return true
	return false


## The nozzle a position wants: the arc of the head's own throw circle that lies over the area,
## sampled round it and rounded to a quarter circle, with the heading facing the ground it has.
##
## This is the honest reading of "a corner head is a quarter and an edge head a half": it is not
## which edge the head is near but how much of the circle is over the bed. A head in the middle of
## an area wants a full circle, one near an edge three quarters, and one in a corner of a narrow
## bed a quarter - and the coverage check then says whether the answer was any good.
static func nozzle_for(ring: PackedVector2Array, at: Vector2, kind: String) -> Dictionary:
	var radius := throw_of_kind(kind) * NOZZLE_RADIUS
	if ring.size() < 3 or radius <= TOLERANCE:
		return {"arc": ARC_FULL, "heading": 0.0}
	var inside := 0
	var facing := Vector2.ZERO
	for step in NOZZLE_STEPS:
		var angle := TAU * float(step) / float(NOZZLE_STEPS)
		var direction := Vector2(cos(angle), sin(angle))
		if Geom.point_in_polygon(at + direction * radius, ring):
			inside += 1
			facing += direction
	var arc := nozzle_for_share(float(inside) / float(NOZZLE_STEPS))
	var heading := 0.0
	if facing.length() > TOLERANCE:
		heading = Geom.angle_of(facing)
	return {"arc": arc, "heading": heading}


## Which nozzle an arc of ground round a head rounds to.
static func nozzle_for_share(share: float) -> float:
	if share >= 0.85:
		return 360.0
	if share >= 0.6:
		return 270.0
	if share >= 0.35:
		return 180.0
	return 90.0


# --- laying heads out ---------------------------------------------------------------


## What is wrong with the numbers, or "" when nothing is. Kept apart from the working-out so a panel
## can ask whether an answer is any use *before* it is given: a layout that has to be run to find
## out it was impossible has already set some heads down.
static func layout_problem(ring: PackedVector2Array, spacing: float, clearance: float) -> String:
	if ring.size() < 3:
		return "that is not an area the plan encloses"
	if Geom.polygon_area(ring) <= TOLERANCE:
		return "that area encloses no ground"
	if spacing < MIN_SPACING_M:
		return "heads %s apart is tighter than a plan draws" % SpacingScript.spacing_words(spacing)
	if clearance < 0.0:
		return "a head cannot stand outside the area it waters"
	return ""


## The default spacing for a kind: one throw, head to head - each head waters to the next, so no
## ground is missed between them. Triangular arrangement carries `TRIANGULAR_SPACING` times that
## over the same ground, which is the saving; `spacing_for()` is here so a panel can show the
## number before anything is laid out.
static func spacing_for(kind: String, staggered: bool = false) -> float:
	var throw_distance := throw_of_kind(kind)
	if throw_distance <= TOLERANCE:
		return 0.0
	return throw_distance * (TRIANGULAR_SPACING if staggered else 1.0)


static func clearance_for(kind: String, spacing: float) -> float:
	if CLEARANCE_SHARE <= TOLERANCE:
		return 0.0
	var throw_distance := throw_of_kind(kind)
	if throw_distance > TOLERANCE:
		return throw_distance * CLEARANCE_SHARE
	return spacing * CLEARANCE_SHARE


## Lay a zone out: set heads across its area on the planting grid, fit each one the nozzle its
## position wants, and replace whatever the zone held before - laying a bed out again is not adding
## a second set of heads to it.
##
## The grid is phased from the area's own bounding box unless a caller states a phase, so a bed
## whose side is a whole number of throws gets a row of heads on each edge and on every grid line
## between them - which is what an irrigation plan draws. Heads on the boundary are the point: the
## cornermost heads take quarter nozzles and face into the bed, the edge ones take halves, and the
## ground between them is covered by heads that are as far apart as one throw.
##
## Returns `{ok, reason, placed, wanted, points, spacing, clearance, staggered}`. A refusal sets no
## heads at all: over the head cap, or an area the grid cannot land in, is refused in words and the
## zone is left as it was.
static func lay_out(zone: Dictionary, kind: String = "", spacing: float = 0.0,
		staggered: bool = false, clearance: float = -1.0,
		origin: Vector2 = Vector2.INF) -> Dictionary:
	var use := kind if is_kind(kind) else String(zone.get("kind", SPRAY))
	var ring := ring_of(zone)
	var step := spacing if spacing > TOLERANCE else spacing_for(use, staggered)
	var edge := clearance if clearance >= 0.0 else clearance_for(use, step)
	var refuse := layout_problem(ring, step, edge)
	if not refuse.is_empty():
		return _refused(refuse, step, edge, staggered)
	var phase := origin
	if not phase.is_finite():
		phase = Geom.points_aabb(ring).position
	var arrangement := SpacingScript.TRIANGULAR if staggered else SpacingScript.SQUARE
	var report := SpacingScript.plan_fill(ring, step, arrangement, edge, phase)
	if not bool(report["ok"]) or int(report["wanted"]) > MAX_HEADS:
		# The planting grid's own refusals are worded for plants, so they are not passed on: a
		# refused layout says what is wrong with *this* job, in its own words.
		return _refused("at %s apart this area wants more than %d heads, which is more than one "
			% [SpacingScript.spacing_words(step), MAX_HEADS]
			+ "zone is laid out with. Space them further apart.", step, edge, staggered)
	var points: PackedVector2Array = report["points"]
	if points.is_empty():
		return _refused("at %s apart no head of this grid lands in that area at all: no grid line "
			% SpacingScript.spacing_words(step) + "falls inside it.", step, edge, staggered)
	clear_heads(zone)
	zone["kind"] = use
	zone["spacing"] = step
	zone["staggered"] = staggered
	for point: Vector2 in points:
		var nozzle := nozzle_for(ring, point, use)
		add_head(zone, point, use, float(nozzle["heading"]), float(nozzle["arc"]))
	return {
		"ok": true, "reason": "", "placed": points.size(), "wanted": int(report["wanted"]),
		"points": points, "spacing": step, "clearance": edge, "staggered": staggered,
	}


static func _refused(reason: String, spacing: float, clearance: float,
		staggered: bool) -> Dictionary:
	return {
		"ok": false, "reason": reason, "placed": 0, "wanted": 0,
		"points": PackedVector2Array(), "spacing": spacing, "clearance": clearance,
		"staggered": staggered,
	}


# --- a zone on the plan -------------------------------------------------------------


## How wide a head is drawn on the sheet, in millimetres. A head on a plan is a *symbol* rather than
## a measurement: its circle is a fixed size on paper, so its model radius follows the plot scale - a
## 3 mm circle is 0.3 m of ground at 1:100 and 0.6 m at 1:200. Drawing the head's real 15 cm body
## instead would make it invisible on a garden plan and enormous on a detail.
const HEAD_SYMBOL_MM := 3.0

## The smallest model radius a head is ever drawn at, so a drawing whose plot scale has not been set
## still shows something rather than nothing.
const HEAD_MIN_RADIUS := 0.05

## The metadata a placed head carries, so the drawing can say what a circle on the irrigation layer
## is without a second model to keep in step.
const META_ZONE := "irrigation_zone"
const META_KIND := "irrigation_kind"
const META_HEADING := "irrigation_heading"
const META_ARC := "irrigation_arc"


static func _metres_per_paper_mm(plot_scale: float) -> float:
	if plot_scale <= TOLERANCE:
		return 0.0
	return plot_scale / 1000.0


## A head as the drawing holds it: a circle on the irrigation layer, sized in paper millimetres,
## carrying its kind, its zone, its heading and its nozzle in its own metadata - so the takeoff
## counts it, the sheet keys it, and selecting it can say what it is.
static func head_entity(head: Dictionary, zone_number: int, plot_scale: float) -> DraftEntity:
	var radius := maxf(HEAD_MIN_RADIUS, HEAD_SYMBOL_MM * _metres_per_paper_mm(plot_scale))
	var entity := EntityScript.make_circle(Vector2(head.get("at", Vector2.ZERO)), radius)
	entity.layer = LayerSetScript.IRRIGATION
	entity.meta[META_ZONE] = zone_number
	entity.meta[META_KIND] = String(head.get("kind", ""))
	entity.meta[META_HEADING] = float(head.get("heading", 0.0))
	entity.meta[META_ARC] = arc_of_head(head)
	return entity


## A pipe run as the drawing holds it: a polyline on the irrigation layer. A run of one point is not
## a run, so it produces nothing rather than a dot nobody can select.
static func run_entity(points: PackedVector2Array) -> DraftEntity:
	if points.size() < 2:
		return null
	var entity := EntityScript.make_polyline(points, false)
	entity.layer = LayerSetScript.IRRIGATION
	return entity


## Whether an entity is a head this module placed.
static func is_head_entity(entity: DraftEntity) -> bool:
	return entity != null and entity.meta.has(META_KIND)


## The zone an entity belongs to, or 0 for anything that is not a head. Used to take a zone's heads
## back off the drawing when the zone goes.
static func zone_of_entity(entity: DraftEntity) -> int:
	if not is_head_entity(entity):
		return 0
	return int(entity.meta.get(META_ZONE, 0))


## A nozzle as a person says it: "a quarter", "a half", "three quarters", "a full circle".
static func nozzle_words(arc: float) -> String:
	if arc >= ARC_FULL - TOLERANCE:
		return "a full circle"
	if arc >= 270.0 - TOLERANCE:
		return "three quarters of a circle"
	if arc >= 180.0 - TOLERANCE:
		return "a half circle"
	return "a quarter circle"


## A head as a line on a status bar: "spray head, Zone 3, a half circle".
static func head_words(head: Dictionary) -> String:
	var kind := String(head.get("kind", ""))
	return "%s, %s" % [kind_name(kind), nozzle_words(arc_of_head(head))]


# --- the flow check -----------------------------------------------------------------


## The zone's demand: the sum of its heads' own flows, in litres per minute.
static func demand_of(zone: Dictionary) -> float:
	var total := 0.0
	for entry in heads_of(zone):
		total += flow_of_kind(String((entry as Dictionary).get("kind", "")))
	return total


## The precipitation rate: the zone's own flow over the zone's own area, in millimetres per hour.
## One litre over one square metre is one millimetre, so a flow of litres a minute becomes
## millimetres an hour as `flow * 60 / area`. It is a *zone* number and not a per-head one: heads
## are set to overlap, and what reaches the ground is the zone's flow over its whole area.
static func precipitation_mm_hour(zone: Dictionary) -> float:
	var area := area_m2(zone)
	if area <= TOLERANCE:
		return 0.0
	return demand_of(zone) * 60.0 / area


## Whether a zone will run off a supply, and every reason it will not. `reasons` are refusals - a
## defect, such as a valve that cannot be opened - and `notes` are facts to report, such as ground
## no head reaches.
##
## Returns `{ok, reasons, notes, heads, flow, supply_flow, supply_pressure, budget, area_m2,
## precipitation, coverage, worst}`.
static func check(zone: Dictionary, supply: Dictionary) -> Dictionary:
	var kind := String(zone.get("kind", SPRAY))
	var heads := heads_of(zone)
	var flow := demand_of(zone)
	var stated := has_supply(supply)
	var supply_flow := float(supply.get("flow", 0.0))
	var supply_pressure := float(supply.get("pressure", 0.0))
	var reasons: Array[String] = []
	var notes: Array[String] = []

	if not stated:
		reasons.append("the supply has not been stated, and a zone cannot be blessed on a guess")
	if heads.is_empty():
		reasons.append("the zone has no heads")
	if heads.size() > MAX_HEADS:
		reasons.append("the zone holds %d heads, which is more than the %d one zone is laid out with"
			% [heads.size(), MAX_HEADS])

	# Two kinds on one valve is a defect rather than a preference: a rotor zone and a spray zone are
	# different schedules, and one valve cannot be both.
	var other := ""
	for entry in heads:
		var held := String((entry as Dictionary).get("kind", ""))
		if not is_kind(held):
			reasons.append("a head in the zone is not a kind of head this knows")
			break
		if held != kind:
			other = held
			break
	if not other.is_empty():
		reasons.append("a zone runs one kind: this one holds %s and %s"
			% [kind_name(kind), kind_name(other)])

	# Pressure before flow: a head that will not open is a refusal about the head, not about how
	# many of them there are.
	if stated and is_kind(kind) and supply_pressure + TOLERANCE < pressure_of_kind(kind):
		reasons.append("a %s wants %s kPa and the supply gives %s"
			% [kind_name(kind), _number(pressure_of_kind(kind)), _number(supply_pressure)])
	if stated and flow > supply_flow + TOLERANCE and is_kind(kind):
		reasons.append("%s draw %s L/min and the supply gives %s - %d of them fit"
			% [kind_count_words(kind, heads.size()), _number(flow), _number(supply_flow),
				head_budget(supply, kind)])

	# A head outside the area it was zoned for waters somewhere it was not set for.
	if has_area(zone):
		var outside_head_count := 0
		var ring := ring_of(zone)
		for entry in heads:
			var at := Vector2((entry as Dictionary).get("at", Vector2.ZERO))
			if not Geom.point_in_polygon(at, ring):
				outside_head_count += 1
		if outside_head_count > 0:
			reasons.append("%s stand outside the area this zone waters"
				% ("1 head" if outside_head_count == 1 else "%d heads" % outside_head_count))

	# Not `coverage`: that is the name of the function this asks, and a local may not shadow a method
	# of its own class.
	var covered := coverage(zone)
	if not has_area(zone):
		notes.append("no area is stated, so coverage and precipitation cannot be worked out")
	elif not bool(covered["ok"]):
		notes.append(String(covered["reason"]))
	elif float(covered["fraction"]) < 1.0 - TOLERANCE:
		notes.append("%d%% of the area is beyond every head - worst at %s"
			% [int(round((1.0 - float(covered["fraction"])) * 100.0)), _point_words(covered["worst"])])

	return {
		"ok": reasons.is_empty(),
		"reasons": reasons,
		"notes": notes,
		"heads": heads.size(),
		"flow": flow,
		"supply_flow": supply_flow,
		"supply_pressure": supply_pressure,
		"budget": head_budget(supply, kind),
		"area_m2": area_m2(zone),
		"precipitation": precipitation_mm_hour(zone),
		"coverage": covered,
		"worst": covered.get("worst", null),
	}


static func sound(zone: Dictionary, supply: Dictionary) -> bool:
	return bool(check(zone, supply)["ok"])


## The verdict as one line a person reads after pressing a button.
static func verdict_words(zone: Dictionary, supply: Dictionary, units: DraftUnits = null) -> String:
	var result := check(zone, supply)
	var label := zone_label(zone)
	if not bool(result["ok"]):
		var first: Array[String] = result["reasons"]
		return "%s: %s" % [label, first[0]]
	var line := "%s will run: %s, %s of %s L/min" % [
		label, kind_count_words(String(zone.get("kind", SPRAY)), int(result["heads"])),
		_number(float(result["flow"])), _number(float(result["supply_flow"])),
	]
	if float(result["area_m2"]) > TOLERANCE:
		line += ", %s mm/h over %s" % [_number(float(result["precipitation"])),
			_area_text(float(result["area_m2"]), units)]
	for note in (result["notes"] as Array[String]):
		line += "; " + note
	return line


# --- coverage -----------------------------------------------------------------------


## Does a zone's own set of heads cover its own area? Sampled on `SAMPLE_GRID`, and answered with a
## fraction and the first point nothing reaches rather than a yes: a designer may leave a tree pit
## to the rain, so a gap is a fact to report.
##
## Returns `{ok, reason, sampled, covered, fraction, worst}`.
static func coverage(zone: Dictionary) -> Dictionary:
	if not has_area(zone):
		return {"ok": false, "reason": "the area has not been stated", "sampled": 0, "covered": 0,
			"fraction": 0.0, "worst": null}
	var ring := ring_of(zone)
	var samples := Geom.fill_grid(ring, SAMPLE_GRID)
	if samples.is_empty():
		return {"ok": false, "reason": "the area is smaller than the %s m coverage grid"
			% _number(SAMPLE_GRID), "sampled": 0, "covered": 0, "fraction": 0.0, "worst": null}
	var heads := heads_of(zone)
	var covered := 0
	var worst: Variant = null
	for point: Vector2 in samples:
		if covered_by(heads, point):
			covered += 1
		elif worst == null:
			worst = point
	return {
		"ok": true, "reason": "", "sampled": samples.size(), "covered": covered,
		"fraction": float(covered) / float(samples.size()), "worst": worst,
	}


# --- the schedule -------------------------------------------------------------------


## The rows a schedule shows, one per zone, in the order the zones are held.
static func schedule(zones: Array, supply: Dictionary, units: DraftUnits = null) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for entry in zones:
		var zone: Dictionary = entry
		var result := check(zone, supply)
		rows.append({
			"number": int(zone.get("number", 0)),
			"label": zone_label(zone),
			"valve": int(zone.get("valve", 0)),
			"kind": String(zone.get("kind", SPRAY)),
			"kind_name": kind_name(String(zone.get("kind", SPRAY))),
			"heads": int(result["heads"]),
			"flow": float(result["flow"]),
			"area_m2": float(result["area_m2"]),
			"area_text": _area_text(float(result["area_m2"]), units),
			"precipitation": float(result["precipitation"]),
			"verdict": "will run" if bool(result["ok"]) else String((result["reasons"] as Array)[0]),
		})
	return rows


## One schedule row as a line a sheet can carry.
static func schedule_row_words(row: Dictionary, units: DraftUnits = null) -> String:
	var kind := String(row.get("kind", SPRAY))
	var line := "%s   valve %d   %s   %s L/min" % [
		String(row.get("label", "Zone")), int(row.get("valve", 0)),
		kind_count_words(kind, int(row.get("heads", 0))), _number(float(row.get("flow", 0.0))),
	]
	if float(row.get("area_m2", 0.0)) > TOLERANCE:
		line += "   %s   %s mm/h" % [_row_area_text(row, units),
			_number(float(row.get("precipitation", 0.0)))]
	return line + "   " + String(row.get("verdict", ""))


static func schedule_lines(zones: Array, supply: Dictionary, units: DraftUnits = null) -> Array[String]:
	var out: Array[String] = []
	for row in schedule(zones, supply, units):
		out.append(schedule_row_words(row, units))
	return out


# --- the file -----------------------------------------------------------------------


## The zones as they go into the drawing file. A position is written as two numbers because JSON
## has no vector, and the ring as a flat run of pairs, the way every other shape here is written.
static func to_dict(zones: Array) -> Dictionary:
	var written: Array = []
	for entry in zones:
		var zone: Dictionary = entry
		var heads: Array = []
		for head_entry in heads_of(zone):
			var head: Dictionary = head_entry
			var at: Vector2 = head.get("at", Vector2.ZERO)
			heads.append({
				"kind": String(head.get("kind", "")),
				"at": [at.x, at.y],
				"heading": float(head.get("heading", 0.0)),
				"arc": float(head.get("arc", 0.0)),
			})
		var ring := ring_of(zone)
		var flat := PackedFloat64Array()
		for point: Vector2 in ring:
			flat.append(point.x)
			flat.append(point.y)
		written.append({
			"number": int(zone.get("number", 0)),
			"valve": int(zone.get("valve", 0)),
			"kind": String(zone.get("kind", SPRAY)),
			"area": flat,
			"heads": heads,
			"spacing": float(zone.get("spacing", 0.0)),
			"staggered": bool(zone.get("staggered", false)),
		})
	return {"zones": written}


## The zones back out of a file, and a record that is not a zone is **dropped rather than
## invented**: a zone with no number is not zone zero, and a zone of a kind nobody has is not a
## spray zone. A head that is not a head is dropped and the zone it was in is kept, because losing
## one head is not losing the bed.
static func from_dict(data: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var held = data.get("zones", [])
	if not (held is Array):
		return out
	for entry in (held as Array):
		if not (entry is Dictionary):
			continue
		var record: Dictionary = entry
		if not (record.get("number") is float or record.get("number") is int):
			continue
		var kind := String(record.get("kind", ""))
		if not is_kind(kind):
			continue
		var zone := make_zone(int(record["number"]), kind)
		zone["valve"] = int(record.get("valve", record["number"]))
		zone["spacing"] = float(record.get("spacing", 0.0))
		zone["staggered"] = bool(record.get("staggered", false))
		set_area(zone, _ring_from(record.get("area", null)))
		var heads: Array = []
		var written = record.get("heads", [])
		if written is Array:
			for head_entry in (written as Array):
				var head := _head_from(head_entry)
				if not head.is_empty():
					heads.append(head)
		zone["heads"] = heads
		out.append(zone)
	return out


static func _head_from(entry: Variant) -> Dictionary:
	if not (entry is Dictionary):
		return {}
	var record: Dictionary = entry
	var kind := String(record.get("kind", ""))
	if not is_kind(kind):
		return {}
	var pair = record.get("at", null)
	if not (pair is Array) or (pair as Array).size() < 2:
		return {}
	var at: Array = pair
	if not (at[0] is float or at[0] is int) or not (at[1] is float or at[1] is int):
		return {}
	return {
		"kind": kind,
		"at": Vector2(float(at[0]), float(at[1])),
		"heading": float(record.get("heading", 0.0)),
		"arc": float(record.get("arc", 0.0)),
	}


static func _ring_from(flat: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	if flat == null:
		return out
	var numbers := PackedFloat64Array()
	if flat is PackedFloat64Array:
		numbers = flat
	elif flat is Array:
		for value in (flat as Array):
			if value is float or value is int:
				numbers.append(float(value))
			else:
				return PackedVector2Array()
	else:
		return out
	var index := 0
	while index + 1 < numbers.size():
		out.append(Vector2(numbers[index], numbers[index + 1]))
		index += 2
	return out


# --- words ---------------------------------------------------------------------------


## A number as a plan writes it: one decimal, because a second one is noise on a flow and no
## decimal at all turns 40 into "40" beside "36.0".
static func _number(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return "%d" % int(round(value))
	return "%.1f" % value


static func _point_words(point: Variant) -> String:
	if not (point is Vector2):
		return "nowhere"
	var at: Vector2 = point
	return "(%s, %s)" % [_number(at.x), _number(at.y)]