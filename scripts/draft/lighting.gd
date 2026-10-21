class_name Lighting

## The arithmetic of where the light goes: fixtures, circuits, and whether a circuit can be run.
##
## A garden plan says where the light goes, and this is the part of that which is arithmetic rather
## than drawing. It is the sibling of `Irrigation`, and it holds the same three things:
##
## * A **fixture kind** is a table row, not a free field: a wattage, a voltage, a throw in metres and
##   a beam spread in degrees. A plan holding a fixture that throws nine metres and draws nothing
##   would make every check downstream arithmetic on a number nobody could check.
## * A **circuit** is a run of cable on a transformer, and the fixtures it feeds. Its load is the sum
##   of its fixtures, and that is the whole reason a plan is divided into circuits at all.
## * A **transformer** is a capacity at a voltage, and it is *stated*. A circuit with no transformer
##   stated is refused rather than blessed - the same decision the irrigation module makes about the
##   supply: a check that silently assumed a hundred volt-amperes would pass a plan that cannot be
##   built, and a designer would find out from a run that trips its own protection.
##
## The two questions a designer actually asks are answered here, and both are measured rather than
## asserted:
##
## * **Will it run?** `check()` sums the fixtures and compares them with the transformer, in words
##   that name the numbers: not "too many fixtures" but "9 floodlights draw 108 W and the transformer
##   gives 100 VA - 8 of them fit".
## * **Does it cover the ground?** `cover()` samples the area on a stated grid and asks, point by
##   point, whether some fixture reaches it - inside its throw *and* inside its aimed beam. A
##   shortfall is reported as a fraction, because a designer may light a bed with one uplight on a
##   tree and leave the rest to the moon: a gap is a fact, where an overloaded run is a defect.
##
## The one deliberate difference from irrigation: a circuit does **not** hold one kind. A valve runs
## one kind because a rotor zone and a spray zone are different schedules; a 12 V transformer happily
## feeds path lights and uplights on the same run. What a circuit cannot do is mix **voltages**, and
## that the check refuses.
##
## Laying the fixtures out is not re-invented either: a circuit is set on the **same grid a bed is
## planted on** (`PlantSpacing`), because fixture-to-fixture and triangular spacing are the same rule
## as plant and head spacing, and because two implementations of one grid would eventually disagree.
##
## Nothing here draws. A placed fixture is a circle on `501-LIGHTING` carrying its kind, its circuit
## and its aim, so the takeoff and the sheet already see it with no second model to keep in step.
##
## Specified in `docs/lighting-subsystem-spec.md`.

const Geom := preload("res://scripts/draft/geom2d.gd")
const SpacingScript := preload("res://scripts/plant_spacing.gd")
const LayerSetScript := preload("res://scripts/draft/layer_set.gd")
const EntityScript := preload("res://scripts/draft/draft_entity.gd")

## The kinds of fixture. Strings rather than StringNames because these are keys in a constant
## dictionary, and a constant expression cannot hold a StringName key.
const PATH := "path"
const UPLIGHT := "uplight"
const FLOOD := "flood"
const WELL := "well"
const STEP := "step"
const LANTERN := "lantern"
const KINDS: Array[String] = [PATH, UPLIGHT, FLOOD, WELL, STEP, LANTERN]

## The fixture table. Wattages and voltages are the real numbers a manufacturer's sheet carries. The
## lantern is the one line-voltage fixture, and it is here so the voltage check has something to
## refuse: a 120 V lantern will not run on a 12 V transformer.
const FIXTURES := {
	PATH: {"name": "path light", "watts": 4.0, "volts": 12.0, "throw": 2.5, "spread": 360.0},
	UPLIGHT: {"name": "uplight", "watts": 7.0, "volts": 12.0, "throw": 6.0, "spread": 40.0},
	FLOOD: {"name": "floodlight", "watts": 12.0, "volts": 12.0, "throw": 9.0, "spread": 90.0},
	WELL: {"name": "well light", "watts": 5.0, "volts": 12.0, "throw": 3.0, "spread": 90.0},
	STEP: {"name": "step light", "watts": 2.0, "volts": 12.0, "throw": 1.5, "spread": 180.0},
	LANTERN: {"name": "lantern", "watts": 60.0, "volts": 120.0, "throw": 8.0, "spread": 180.0},
}

## A full circle is the spread that has no aim: where the point is, a full fixture reaches it.
const SPREAD_FULL := 360.0

## How far inside a beam's edge counts as lit, in radians - about half a degree. A point lying
## exactly on the boundary of a half beam is lit by that fixture, and without this the cover check
## would report a shortfall that is float arithmetic rather than a dark bed.
const BEAM_EDGE := 0.01

## A layout sets a fixture on the grid line and not pulled in from it: a *fixture* is not a plant. A
## plant is pulled in by half its spread so its canopy lands on the edge rather than over the lawn,
## but a fixture stands where its light is wanted, and the boundary is exactly where that is.
const CLEARANCE_SHARE := 0.0

## The spacing a triangular grid can carry over the same ground as a square one at one throw:
## 2 / sqrt(3), which is the ~15% saving in fixtures.
const TRIANGULAR_SPACING := 1.1547005383792517

const MIN_SPACING_M := 0.05

## How many fixtures one circuit is laid out with. A *stated* limit rather than a performance guard:
## a circuit that wants more wants dividing into circuits.
const MAX_FIXTURES := 300

## The grid the cover check samples the area on, in metres. Stated because a cover figure without its
## sampling is a number nobody can argue with.
const SAMPLE_GRID := 0.5

## How many rays round a fixture are sampled to work out the aim it wants, and at what fraction of
## its throw they are tested.
const AIM_STEPS := 24
const AIM_RADIUS := 0.9

## What a panel offers as the starting transformer. The model never assumes it.
const DEFAULT_TRANSFORMER_VA := 100.0
const DEFAULT_TRANSFORMER_VOLTS := 12.0

const TOLERANCE := 1e-6


# --- the fixture table --------------------------------------------------------------


## The layer fixtures and runs live on, taken from the layer set so a layer renamed in one place
## cannot leave a fixture on a driveway.
static func layer() -> StringName:
	return LayerSetScript.LIGHTING


static func is_kind(value: String) -> bool:
	return FIXTURES.has(value)


## The kinds, in the order a palette offers them: the one a designer reaches for most first.
static func kind_list() -> Array[String]:
	return KINDS.duplicate()


## What a drop-down shows for each kind.
static func kind_names() -> Array[String]:
	var out: Array[String] = []
	for kind in KINDS:
		out.append(String(FIXTURES[kind]["name"]))
	return out


## The kind behind a name a drop-down was showing, so a panel can turn its own choice back into one.
static func kind_for_name(shown: String) -> String:
	for kind in KINDS:
		if String(FIXTURES[kind]["name"]) == shown:
			return kind
	return ""


## "a path light", for a sentence: "a circuit of 4 path lights".
static func kind_words(kind: String) -> String:
	if not is_kind(kind):
		return "a fixture nobody knows"
	return "a " + String(FIXTURES[kind]["name"])


## "path light", for a table cell.
static func kind_name(kind: String) -> String:
	if not is_kind(kind):
		return "unknown fixture"
	return String(FIXTURES[kind]["name"])


## The plural a schedule writes: "4 path lights".
static func kind_count_words(kind: String, count: int) -> String:
	var one := kind_name(kind)
	if count == 1:
		return "1 %s" % one
	return "%d %ss" % [count, one]


static func watts_of_kind(kind: String) -> float:
	if not is_kind(kind):
		return 0.0
	return float(FIXTURES[kind]["watts"])


static func volts_of_kind(kind: String) -> float:
	if not is_kind(kind):
		return 0.0
	return float(FIXTURES[kind]["volts"])


static func throw_of_kind(kind: String) -> float:
	if not is_kind(kind):
		return 0.0
	return float(FIXTURES[kind]["throw"])


static func spread_of_kind(kind: String) -> float:
	if not is_kind(kind):
		return 0.0
	return float(FIXTURES[kind]["spread"])


# --- the transformer ----------------------------------------------------------------


## A transformer: a capacity in volt-amperes at a stated voltage.
static func make_transformer(va: float, volts: float) -> Dictionary:
	return {"va": va, "volts": volts}


## Whether anything has actually been stated. A transformer with no capacity is not a transformer,
## and neither is a dictionary that never held one, so a circuit is checked against this first.
static func has_transformer(transformer: Dictionary) -> bool:
	return float(transformer.get("va", 0.0)) > TOLERANCE \
		and float(transformer.get("volts", 0.0)) > TOLERANCE


static func transformer_words(transformer: Dictionary) -> String:
	if not has_transformer(transformer):
		return "no transformer stated"
	return "%s VA at %s V" % [_number(float(transformer.get("va", 0.0))),
		_number(float(transformer.get("volts", 0.0)))]


## How many fixtures of a kind the transformer can carry. This is the number a refusal quotes, and the
## number a panel shows beside the transformer so a designer sees the budget before laying anything.
static func power_budget(transformer: Dictionary, kind: String) -> int:
	var per_fixture := watts_of_kind(kind)
	if per_fixture <= TOLERANCE or not has_transformer(transformer):
		return 0
	return int(floor(float(transformer["va"]) / per_fixture + TOLERANCE))


# --- a circuit ----------------------------------------------------------------------


static func make_circuit(number: int, kind: String = PATH) -> Dictionary:
	return {
		"number": number,
		"tap": number,
		"kind": kind,
		"area": PackedVector2Array(),
		"area_m2": 0.0,
		"fixtures": [],
		"spacing": 0.0,
		"staggered": false,
	}


static func circuit_label(circuit: Dictionary) -> String:
	return "Circuit %d" % int(circuit.get("number", 0))


## The number a new circuit takes: one past the highest in use, so a deleted circuit's number is not
## handed to a different bed.
static func next_number(circuits: Array) -> int:
	var highest := 0
	for entry in circuits:
		highest = maxi(highest, int((entry as Dictionary).get("number", 0)))
	return highest + 1


## The lowest tap number not in use. Taps are numbered by place on the transformer, so a tap freed by
## a circuit that went away is the next one to hand out.
static func next_tap(circuits: Array) -> int:
	var taken: Array[int] = []
	for entry in circuits:
		taken.append(int((entry as Dictionary).get("tap", 0)))
	var candidate := 1
	while taken.has(candidate):
		candidate += 1
	return candidate


## Give a circuit the ring it lights. A circuit can be laid out without one - fixtures placed by hand
## know where they are - and then cover cannot be worked out, which the report says rather than
## guessing.
static func set_area(circuit: Dictionary, ring: PackedVector2Array) -> void:
	circuit["area"] = ring
	circuit["area_m2"] = 0.0 if ring.size() < 3 else Geom.polygon_area(ring)


static func area_m2(circuit: Dictionary) -> float:
	return float(circuit.get("area_m2", 0.0))


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


static func has_area(circuit: Dictionary) -> bool:
	return area_m2(circuit) > TOLERANCE


static func ring_of(circuit: Dictionary) -> PackedVector2Array:
	return circuit.get("area", PackedVector2Array())


# --- fixtures -----------------------------------------------------------------------


## Set a fixture at a position. `spread` of zero means the kind's own beam; the heading is the
## direction the fixture is aimed, in radians, and is ignored by a full-circle fixture.
static func add_fixture(circuit: Dictionary, at: Vector2, kind: String = "",
		heading: float = 0.0, spread: float = 0.0) -> Dictionary:
	var use := kind if is_kind(kind) else String(circuit.get("kind", PATH))
	var fixture := {"kind": use, "at": at, "heading": heading, "spread": spread}
	(circuit["fixtures"] as Array).append(fixture)
	return fixture


static func fixture_count(circuit: Dictionary) -> int:
	return (circuit.get("fixtures", []) as Array).size()


static func fixtures_of(circuit: Dictionary) -> Array:
	return circuit.get("fixtures", [])


static func clear_fixtures(circuit: Dictionary) -> void:
	circuit["fixtures"] = []


static func remove_fixture(circuit: Dictionary, index: int) -> bool:
	var fixtures: Array = circuit.get("fixtures", [])
	if index < 0 or index >= fixtures.size():
		return false
	fixtures.remove_at(index)
	return true


## The beam a fixture is fitted with: its own if it was given one, the kind's default otherwise.
static func spread_of_fixture(fixture: Dictionary) -> float:
	var spread := float(fixture.get("spread", 0.0))
	if spread > TOLERANCE:
		return minf(spread, SPREAD_FULL)
	var kind := String(fixture.get("kind", ""))
	var own := spread_of_kind(kind)
	return SPREAD_FULL if own <= TOLERANCE else own


## Whether a fixture's light reaches a point: within its throw, and within its aimed beam.
static func reaches(fixture: Dictionary, point: Vector2) -> bool:
	var kind := String(fixture.get("kind", ""))
	var away := point - Vector2(fixture.get("at", Vector2.ZERO))
	var distance := away.length()
	if distance > throw_of_kind(kind) + TOLERANCE:
		return false
	var spread := deg_to_rad(spread_of_fixture(fixture))
	if spread >= deg_to_rad(SPREAD_FULL) - TOLERANCE or distance <= TOLERANCE:
		return true
	var heading := float(fixture.get("heading", 0.0))
	return Geom.angle_in_sweep(Geom.angle_of(away), heading - spread * 0.5 - BEAM_EDGE, spread
		+ BEAM_EDGE * 2.0)


static func covered_by(fixtures: Array, point: Vector2) -> bool:
	for entry in fixtures:
		if reaches(entry as Dictionary, point):
			return true
	return false


## The aim a position wants: the mean of the directions round the fixture that lie over the area,
## sampled every 15 degrees at 0.9 of the throw. The spread is *not* set here - a designer buys an
## optic and does not reshape a beam on plan - so this returns only the heading.
static func aim_for(ring: PackedVector2Array, at: Vector2, kind: String) -> float:
	var radius := throw_of_kind(kind) * AIM_RADIUS
	if ring.size() < 3 or radius <= TOLERANCE:
		return 0.0
	var facing := Vector2.ZERO
	for step in AIM_STEPS:
		var angle := TAU * float(step) / float(AIM_STEPS)
		var direction := Vector2(cos(angle), sin(angle))
		if Geom.point_in_polygon(at + direction * radius, ring):
			facing += direction
	if facing.length() <= TOLERANCE:
		return 0.0
	return Geom.angle_of(facing)


# --- laying fixtures out ------------------------------------------------------------


## What is wrong with the numbers, or "" when nothing is. Kept apart from the working-out so a panel
## can ask whether an answer is any use *before* it is given.
static func layout_problem(ring: PackedVector2Array, spacing: float, clearance: float) -> String:
	if ring.size() < 3:
		return "that is not an area the plan encloses"
	if Geom.polygon_area(ring) <= TOLERANCE:
		return "that area encloses no ground"
	if spacing < MIN_SPACING_M:
		return "fixtures %s apart is tighter than a plan draws" % SpacingScript.spacing_words(spacing)
	if clearance < 0.0:
		return "a fixture cannot stand outside the area it lights"
	return ""


## The default spacing for a kind: one throw, fixture to fixture - each fixture throws to the next,
## so no ground is missed between them. Triangular arrangement carries `TRIANGULAR_SPACING` times
## that over the same ground, which is the saving; `spacing_for()` is here so a panel can show the
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


## Lay a circuit out: set fixtures across its area on the planting grid, aim each one at the ground
## its position wants, and replace whatever the circuit held before - laying a bed out again is not
## adding a second set of fixtures to it.
##
## Returns `{ok, reason, placed, wanted, points, spacing, clearance, staggered}`. A refusal sets no
## fixtures at all: over the fixture cap, or an area the grid cannot land in, is refused in words and
## the circuit is left as it was.
static func lay_out(circuit: Dictionary, kind: String = "", spacing: float = 0.0,
		staggered: bool = false, clearance: float = -1.0,
		origin: Vector2 = Vector2.INF) -> Dictionary:
	var use := kind if is_kind(kind) else String(circuit.get("kind", PATH))
	var ring := ring_of(circuit)
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
	if not bool(report["ok"]) or int(report["wanted"]) > MAX_FIXTURES:
		return _refused("at %s apart this area wants more than %d fixtures, which is more than one "
			% [SpacingScript.spacing_words(step), MAX_FIXTURES]
			+ "circuit is laid out with. Space them further apart.", step, edge, staggered)
	var points: PackedVector2Array = report["points"]
	if points.is_empty():
		return _refused("at %s apart no fixture of this grid lands in that area at all: no grid line "
			% SpacingScript.spacing_words(step) + "falls inside it.", step, edge, staggered)
	clear_fixtures(circuit)
	circuit["kind"] = use
	circuit["spacing"] = step
	circuit["staggered"] = staggered
	for point: Vector2 in points:
		add_fixture(circuit, point, use, aim_for(ring, point, use), 0.0)
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


# --- a circuit on the plan ----------------------------------------------------------


## How wide a fixture is drawn on the sheet, in millimetres. A fixture on a plan is a *symbol* rather
## than a measurement: its circle is a fixed size on paper, so its model radius follows the plot
## scale - a 3 mm circle is 0.3 m of ground at 1:100 and 0.6 m at 1:200.
const FIXTURE_SYMBOL_MM := 3.0

## The smallest model radius a fixture is ever drawn at, so a drawing whose plot scale has not been
## set still shows something rather than nothing.
const FIXTURE_MIN_RADIUS := 0.05

## The metadata a placed fixture carries, so the drawing can say what a circle on the lighting layer
## is without a second model to keep in step.
const META_CIRCUIT := "lighting_circuit"
const META_KIND := "lighting_kind"
const META_AIM := "lighting_aim"
const META_SPREAD := "lighting_spread"


static func _metres_per_paper_mm(plot_scale: float) -> float:
	if plot_scale <= TOLERANCE:
		return 0.0
	return plot_scale / 1000.0


## A fixture as the drawing holds it: a circle on the lighting layer, sized in paper millimetres,
## carrying its kind, its circuit, its aim and its beam in its own metadata - so the takeoff counts
## it, the sheet keys it, and selecting it can say what it is.
static func fixture_entity(fixture: Dictionary, circuit_number: int, plot_scale: float) -> DraftEntity:
	var radius := maxf(FIXTURE_MIN_RADIUS, FIXTURE_SYMBOL_MM * _metres_per_paper_mm(plot_scale))
	var entity := EntityScript.make_circle(Vector2(fixture.get("at", Vector2.ZERO)), radius)
	entity.layer = LayerSetScript.LIGHTING
	entity.meta[META_CIRCUIT] = circuit_number
	entity.meta[META_KIND] = String(fixture.get("kind", ""))
	entity.meta[META_AIM] = float(fixture.get("heading", 0.0))
	entity.meta[META_SPREAD] = spread_of_fixture(fixture)
	return entity


## A cable run as the drawing holds it: a polyline on the lighting layer. A run of one point is not a
## run, so it produces nothing rather than a dot nobody can select.
static func run_entity(points: PackedVector2Array) -> DraftEntity:
	if points.size() < 2:
		return null
	var entity := EntityScript.make_polyline(points, false)
	entity.layer = LayerSetScript.LIGHTING
	return entity


## Whether an entity is a fixture this module placed.
static func is_fixture_entity(entity: DraftEntity) -> bool:
	return entity != null and entity.meta.has(META_KIND)


## The circuit an entity belongs to, or 0 for anything that is not a fixture. Used to take a
## circuit's fixtures back off the drawing when the circuit goes.
static func circuit_of_entity(entity: DraftEntity) -> int:
	if not is_fixture_entity(entity):
		return 0
	return int(entity.meta.get(META_CIRCUIT, 0))


## A beam as a person says it: "a narrow beam", "a wide beam", "a half circle", "a full circle".
static func beam_words(spread: float) -> String:
	if spread >= SPREAD_FULL - TOLERANCE:
		return "a full circle"
	if spread >= 180.0 - TOLERANCE:
		return "a half circle"
	if spread >= 90.0 - TOLERANCE:
		return "a wide beam"
	return "a narrow beam"


## A fixture as a line on a status bar: "uplight, a narrow beam".
static func fixture_words(fixture: Dictionary) -> String:
	var kind := String(fixture.get("kind", ""))
	return "%s, %s" % [kind_name(kind), beam_words(spread_of_fixture(fixture))]


# --- the load check -----------------------------------------------------------------


## The circuit's load: the sum of its fixtures' own wattages.
static func demand_of(circuit: Dictionary) -> float:
	var total := 0.0
	for entry in fixtures_of(circuit):
		total += watts_of_kind(String((entry as Dictionary).get("kind", "")))
	return total


## Whether a circuit will run off a transformer, and every reason it will not. `reasons` are refusals
## - a defect, such as an overloaded run - and `notes` are facts to report, such as ground no fixture
## reaches.
##
## Returns `{ok, reasons, notes, fixtures, load, capacity, volts, budget, area_m2, cover, worst}`.
static func check(circuit: Dictionary, transformer: Dictionary) -> Dictionary:
	var kind := String(circuit.get("kind", PATH))
	var fixtures := fixtures_of(circuit)
	var demand := demand_of(circuit)
	var stated := has_transformer(transformer)
	var capacity := float(transformer.get("va", 0.0))
	var volts := float(transformer.get("volts", 0.0))
	var reasons: Array[String] = []
	var notes: Array[String] = []

	if not stated:
		reasons.append("the transformer has not been stated, and a circuit cannot be blessed on a guess")
	if fixtures.is_empty():
		reasons.append("the circuit has no fixtures")
	if fixtures.size() > MAX_FIXTURES:
		reasons.append("the circuit holds %d fixtures, which is more than the %d one circuit is laid out with"
			% [fixtures.size(), MAX_FIXTURES])

	# Voltage before load: a fixture that will not light is a refusal about voltage, not about how many
	# there are. A circuit may hold several kinds - that is the difference from irrigation - but only
	# one voltage.
	var unknown := false
	var wrong_volts := 0
	var other_kind := ""
	var other_volts := 0.0
	for entry in fixtures:
		var held := String((entry as Dictionary).get("kind", ""))
		if not is_kind(held):
			unknown = true
			continue
		if stated and absf(volts_of_kind(held) - volts) > TOLERANCE:
			wrong_volts += 1
			if other_kind.is_empty():
				other_kind = held
				other_volts = volts_of_kind(held)
	if unknown:
		reasons.append("a fixture in the circuit is not a kind of fixture this knows")
	if wrong_volts > 0 and stated:
		if wrong_volts == 1:
			reasons.append("a %s needs %s V and the transformer gives %s V"
				% [kind_name(other_kind), _number(other_volts), _number(volts)])
		else:
			reasons.append("%d fixtures need %s V and the transformer gives %s V"
				% [wrong_volts, _number(other_volts), _number(volts)])

	if stated and demand > capacity + TOLERANCE and is_kind(kind):
		reasons.append("%s draw %s W and the transformer gives %s VA - %d of them fit"
			% [kind_count_words(kind, fixtures.size()), _number(demand), _number(capacity),
				power_budget(transformer, kind)])

	# A fixture outside the area it was put on a circuit for lights somewhere it was not set for.
	if has_area(circuit):
		var outside_count := 0
		var ring := ring_of(circuit)
		for entry in fixtures:
			var at := Vector2((entry as Dictionary).get("at", Vector2.ZERO))
			if not Geom.point_in_polygon(at, ring):
				outside_count += 1
		if outside_count > 0:
			reasons.append("%s stand outside the area this circuit lights"
				% ("1 fixture" if outside_count == 1 else "%d fixtures" % outside_count))

	# Not `cover`: that is the name of the function this asks, and a local may not shadow a method of
	# its own class.
	var lit := cover(circuit)
	if not has_area(circuit):
		notes.append("no area is stated, so cover cannot be worked out")
	elif not bool(lit["ok"]):
		notes.append(String(lit["reason"]))
	elif float(lit["fraction"]) < 1.0 - TOLERANCE:
		notes.append("%d%% of the area is beyond every fixture - worst at %s"
			% [int(round((1.0 - float(lit["fraction"])) * 100.0)), _point_words(lit["worst"])])

	return {
		"ok": reasons.is_empty(),
		"reasons": reasons,
		"notes": notes,
		"fixtures": fixtures.size(),
		"load": demand,
		"capacity": capacity,
		"volts": volts,
		"budget": power_budget(transformer, kind),
		"area_m2": area_m2(circuit),
		"cover": lit,
		"worst": lit.get("worst", null),
	}


static func sound(circuit: Dictionary, transformer: Dictionary) -> bool:
	return bool(check(circuit, transformer)["ok"])


## The verdict as one line a person reads after pressing a button.
static func verdict_words(circuit: Dictionary, transformer: Dictionary, units: DraftUnits = null) -> String:
	var result := check(circuit, transformer)
	var label := circuit_label(circuit)
	if not bool(result["ok"]):
		var reasons: Array[String] = result["reasons"]
		return "%s: %s" % [label, reasons[0]]
	var line := "%s will run: %s, %s W of %s VA" % [
		label, kind_count_words(String(circuit.get("kind", PATH)), int(result["fixtures"])),
		_number(float(result["load"])), _number(float(result["capacity"])),
	]
	if float(result["area_m2"]) > TOLERANCE:
		line += ", over %s" % _area_text(float(result["area_m2"]), units)
	for note in (result["notes"] as Array[String]):
		line += "; " + note
	return line


# --- cover --------------------------------------------------------------------------


## Does a circuit's own set of fixtures light its own area? Sampled on `SAMPLE_GRID`, and answered
## with a fraction and the first point nothing reaches rather than a yes: a designer may leave a tree
## pit to a single uplight, so a gap is a fact to report.
##
## Returns `{ok, reason, sampled, covered, fraction, worst}`.
static func cover(circuit: Dictionary) -> Dictionary:
	if not has_area(circuit):
		return {"ok": false, "reason": "the area has not been stated", "sampled": 0, "covered": 0,
			"fraction": 0.0, "worst": null}
	var ring := ring_of(circuit)
	var samples := Geom.fill_grid(ring, SAMPLE_GRID)
	if samples.is_empty():
		return {"ok": false, "reason": "the area is smaller than the %s m cover grid"
			% _number(SAMPLE_GRID), "sampled": 0, "covered": 0, "fraction": 0.0, "worst": null}
	var fixtures := fixtures_of(circuit)
	var covered := 0
	var worst: Variant = null
	for point: Vector2 in samples:
		if covered_by(fixtures, point):
			covered += 1
		elif worst == null:
			worst = point
	return {
		"ok": true, "reason": "", "sampled": samples.size(), "covered": covered,
		"fraction": float(covered) / float(samples.size()), "worst": worst,
	}


# --- the schedule -------------------------------------------------------------------


## The rows a schedule shows, one per circuit, in the order the circuits are held.
static func schedule(circuits: Array, transformer: Dictionary, units: DraftUnits = null) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for entry in circuits:
		var circuit: Dictionary = entry
		var result := check(circuit, transformer)
		rows.append({
			"number": int(circuit.get("number", 0)),
			"label": circuit_label(circuit),
			"tap": int(circuit.get("tap", 0)),
			"kind": String(circuit.get("kind", PATH)),
			"kind_name": kind_name(String(circuit.get("kind", PATH))),
			"fixtures": int(result["fixtures"]),
			"load": float(result["load"]),
			"area_m2": float(result["area_m2"]),
			"area_text": _area_text(float(result["area_m2"]), units),
			"verdict": "will run" if bool(result["ok"]) else String((result["reasons"] as Array)[0]),
		})
	return rows


## One schedule row as a line a sheet can carry.
static func schedule_row_words(row: Dictionary, units: DraftUnits = null) -> String:
	var kind := String(row.get("kind", PATH))
	var line := "%s   tap %d   %s   %s W" % [
		String(row.get("label", "Circuit")), int(row.get("tap", 0)),
		kind_count_words(kind, int(row.get("fixtures", 0))), _number(float(row.get("load", 0.0))),
	]
	if float(row.get("area_m2", 0.0)) > TOLERANCE:
		line += "   %s" % _row_area_text(row, units)
	return line + "   " + String(row.get("verdict", ""))


static func schedule_lines(circuits: Array, transformer: Dictionary, units: DraftUnits = null) -> Array[String]:
	var out: Array[String] = []
	for row in schedule(circuits, transformer, units):
		out.append(schedule_row_words(row, units))
	return out


# --- the file -----------------------------------------------------------------------


## The circuits as they go into the drawing file. A position is written as two numbers because JSON
## has no vector, and the ring as a flat run of pairs, the way every other shape here is written.
static func to_dict(circuits: Array) -> Dictionary:
	var written: Array = []
	for entry in circuits:
		var circuit: Dictionary = entry
		var fixtures: Array = []
		for fixture_entry in fixtures_of(circuit):
			var fixture: Dictionary = fixture_entry
			var at: Vector2 = fixture.get("at", Vector2.ZERO)
			fixtures.append({
				"kind": String(fixture.get("kind", "")),
				"at": [at.x, at.y],
				"heading": float(fixture.get("heading", 0.0)),
				"spread": float(fixture.get("spread", 0.0)),
			})
		var ring := ring_of(circuit)
		var flat := PackedFloat64Array()
		for point: Vector2 in ring:
			flat.append(point.x)
			flat.append(point.y)
		written.append({
			"number": int(circuit.get("number", 0)),
			"tap": int(circuit.get("tap", 0)),
			"kind": String(circuit.get("kind", PATH)),
			"area": flat,
			"fixtures": fixtures,
			"spacing": float(circuit.get("spacing", 0.0)),
			"staggered": bool(circuit.get("staggered", false)),
		})
	return {"circuits": written}


## The circuits back out of a file, and a record that is not a circuit is **dropped rather than
## invented**: a circuit with no number is not circuit zero, and a circuit of a kind nobody has is not
## a path light. A fixture that is not a fixture is dropped and the circuit it was in is kept, because
## losing one fixture is not losing the bed.
static func from_dict(data: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var held = data.get("circuits", [])
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
		var circuit := make_circuit(int(record["number"]), kind)
		circuit["tap"] = int(record.get("tap", record["number"]))
		circuit["spacing"] = float(record.get("spacing", 0.0))
		circuit["staggered"] = bool(record.get("staggered", false))
		set_area(circuit, _ring_from(record.get("area", null)))
		var fixtures: Array = []
		var written = record.get("fixtures", [])
		if written is Array:
			for fixture_entry in (written as Array):
				var fixture := _fixture_from(fixture_entry)
				if not fixture.is_empty():
					fixtures.append(fixture)
		circuit["fixtures"] = fixtures
		out.append(circuit)
	return out


static func _fixture_from(entry: Variant) -> Dictionary:
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
		"spread": float(record.get("spread", 0.0)),
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


## A number as a plan writes it: one decimal, because a second one is noise on a wattage.
static func _number(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return "%d" % int(round(value))
	return "%.1f" % value


static func _point_words(point: Variant) -> String:
	if not (point is Vector2):
		return "nowhere"
	var at: Vector2 = point
	return "(%s, %s)" % [_number(at.x), _number(at.y)]