# The lighting module

A garden plan says where the light goes. This is the arithmetic of that: what a fixture is,
what a circuit is, and - the part a drawing alone cannot tell you - whether the circuit can
actually be run off the transformer that is there.

It is a module in the same sense the irrigation is: a table of facts (a fixture kind has a
wattage, a voltage, a throw and a beam spread), a rule that turns an area into a layout, and a
check that refuses a circuit that would not work. Nothing here draws. Drawing is a layer and a
symbol, and the plan it lands on is the drawing the rest of the app already reads.

## 1. What already exists, and what this adds

The plan already has the places lighting goes:

* `501-LIGHTING` - fixtures, circuits and cable runs, and it plots. From the layer set, so a
  renamed layer cannot leave a fixture on a driveway.
* The **Lighting plan** layer state, which is the base plan plus this layer.
* The takeoff already prices anything on the layer as a **count** with cost code `LIGHTING`,
  and the estimate desk already refuses a plan whose lighting nothing can price.
* The planting grid, the bed areas an outline encloses, and the sheet's key.

What is added here is the part that is arithmetic rather than drawing: a fixture table, a
layout rule, and the **load check**. A circuit of fixtures that would overload its transformer
is not a design, and no amount of linework will say so.

## 2. Load-bearing decisions

### 2.1 A fixture kind is a table, not a free-text field

A designer picks a *kind* - a path light, an uplight, a floodlight, a well light, a step light,
a line-voltage lantern - and the kind carries the four numbers that decide everything else: its
**wattage**, its **voltage**, its **throw** in metres, and its **beam spread** in degrees. A
free field would let a plan hold a fixture that throws eight metres and draws nothing, and every
check downstream would be arithmetic on a number nobody could check.

| Kind | Watts | Volts | Throw | Beam spread |
|---|---|---|---|---|
| Path light | 4.0 W | 12 V | 2.5 m | 360 deg |
| Uplight | 7.0 W | 12 V | 6.0 m | 40 deg |
| Floodlight | 12.0 W | 12 V | 9.0 m | 90 deg |
| Well light | 5.0 W | 12 V | 3.0 m | 90 deg |
| Step light | 2.0 W | 12 V | 1.5 m | 180 deg |
| Lantern | 60.0 W | 120 V | 8.0 m | 180 deg |

The lantern is the one line-voltage fixture, and it is in the table so the voltage check has
something to refuse: a 120 V lantern will not run on a 12 V transformer, and a plan that put one
there would be a plan for a fixture that never lights.

### 2.2 A circuit is a run of cable on a transformer, and the fixtures it feeds

A circuit is not a colour on a plan. It is the set of fixtures that share one run of cable off
one transformer tap, and that is why it has a **load** - the sum of its fixtures' wattages - and
why a circuit whose load exceeds its transformer cannot be run. Numbering is per plan, and a
transformer tap is handed out once.

A circuit does **not** hold one kind, and that is the deliberate difference from irrigation: a
valve runs one kind because a rotor zone and a spray zone are different *schedules*, but a 12 V
transformer happily feeds path lights and uplights on the same run. What a circuit cannot do is
mix **voltages**, which the check refuses.

### 2.3 The transformer is stated, never assumed

A transformer is a capacity at a voltage: `100 VA at 12 V` is a residential low-voltage
transformer. It is **asked for**, and a circuit with no transformer stated is **refused rather
than blessed** - the same decision the irrigation module makes about the supply, and the DXF
reader about `$INSUNITS`, for the same reason. A check that silently assumed a hundred
volt-amperes would pass a plan that cannot be built, and a designer would find out from a run
that trips its own protection.

The voltage is not decoration either: a 120 V lantern wants a 120 V supply, and a 12 V
transformer will not light one. That is a refusal, not a warning.

### 2.4 One place does the arithmetic, and it refuses

The checks live in one script and return a verdict with reasons in words, so the panel that
reports them and the test that holds them down read the same sentence. A refusal names the
numbers: not `too many fixtures`, but `9 floodlights draw 108 W and the transformer gives 100
VA - 8 of them fit`.

### 2.5 Fixtures tile the area, spacing is fixture-to-fixture, and a fixture is not a plant

Fixtures are set one **throw** apart, which is the fixture-to-fixture spacing that lights an
area evenly: each fixture throws to the next, so no ground is missed between them. The grid is
phased from the area's own bounding box, so a bed whose side is a whole number of throws gets a
row of fixtures **on each edge and on every grid line between them**. Fixtures on the boundary
are the point of the layout: the corner ones are aimed in, the edge ones across, the middle ones
wherever they will - and the ground is lit edge to edge. That is why a layout does **not** pull a
fixture in from the edge. A plant is pulled in by half its spread and its *canopy* meets the
edge; a fixture is where its *light* is wanted, and a fixture shoved half a throw inside leaves
the strip behind it dark, which measuring the cover shows at once.

A **triangular** grid - each row half a spacing across from the one before it - covers the same
ground with rows `sqrt(3)/2` of a spacing apart, so the spacing can be taken out to `2/sqrt(3)`
(1.155) of the throw. The same saving as irrigation: about one fixture in seven.

### 2.6 The aim a position wants is the ground around it

A fixture's **heading** belongs to the fixture that was placed, not to its kind: a kind has a
default beam spread, and every fixture a layout sets is aimed at the ground its own position
wants. Unlike irrigation, the **spread is the kind's own** - a designer buys an optic and does
not reshape a beam on plan - so only the aim is set per fixture. The aim is the direction of the
ground the fixture has, taken as the **mean of the directions that fall inside the area**,
sampled round the fixture every 15 degrees at 0.9 of the throw. A bollard, whose spread is a
full circle, ignores its aim entirely.

### 2.7 The load is the sum of the fixtures, and it is what a transformer checks

A circuit's load is the sum of its fixtures' wattages, and the transformer's capacity is in
volt-amperes. The two are compared directly, because on a nominal residential LED system the
power factor is taken as unity and one watt is one volt-ampere. It is a **circuit** number and
not a per-fixture one, because that is the number the transformer sees.

### 2.8 Cover is measured on a grid, not asserted

The circuit's area is sampled on a stated grid (0.5 m), and every sample point is asked whether
some fixture reaches it - inside the throw **and** inside that fixture's aimed beam. The answer
is a fraction and the point of the worst gap, and a shortfall is reported rather than hidden. A
designer may light a bed with a single uplight on a tree and leave the rest to the moon, so a gap
is a fact to report, not a defect to refuse - unlike an overloaded transformer, which is a
defect.

### 2.9 Fixtures are entities on `501-LIGHTING`

A placed fixture is a circle on the lighting layer carrying its kind, its circuit and its aim in
its own metadata, so the takeoff counts it, the sheet keys it, and selecting it says what it is -
with no second model to keep in step. The radius is a *paper* size - `FIXTURE_SYMBOL_MM`, three
millimetres - so a fixture is 0.3 m of ground at 1:100 and 0.6 m at 1:200: a fixture is a symbol
on a plan rather than a measured object, and drawing its real body in model metres instead would
make it invisible on a garden plan and enormous on a detail. The plan canvas draws it by the same
path as every other shape.

A circuit is a property of the **drawing**, not of a caller's memory: the module writes
`{circuits: [...], transformer: {...}}` under the document's `lighting` key, which is what makes
a circuit and the fixtures that belong to it arrive together and leave together.

## 3. Data models

### 3.1 A fixture

```
{ kind: String, at: Vector2, heading: float (radians), spread: float (degrees, 0 = the kind's own) }
```

### 3.2 A circuit

```
{
  number: int, tap: int, kind: String, area: PackedVector2Array, area_m2: float,
  fixtures: Array, spacing: float, staggered: bool
}
```

A circuit holds the fixtures that share its run. Its area is the ring a plan encloses, and it is
optional: fixtures can be set without one, and then cover and the load-per-area cannot be worked
out and the report says so.

### 3.3 The transformer

```
{ va: float (volt-amperes), volts: float }
```

### 3.4 The file

A circuit survives the drawing file: numbers and strings as themselves, and a fixture's position
as a two-number pair, because JSON has no vector. Reading back is defensive for the reason every
other reader here is: a record that is not a circuit is dropped rather than invented, and a
fixture that is not a fixture is dropped without losing the circuit it was in.

## 4. The algorithms

### 4.1 Laying fixtures out

1. Refuse an outline that is not a ring, encloses no ground, or a spacing tighter than a plan
   draws.
2. Set the grid: `spacing` (defaulting to the kind's own throw, and to 1.155 times it when
   staggered), phased from the area's bounding box, with rows `sqrt(3)/2` of a spacing apart and
   each odd row shifted half a spacing when triangular.
3. Keep the points inside the ring. A point on the boundary counts as inside - fixture to the
   edge is fixture to the edge - which is what makes the outer row of a whole-throw bed
   possible.
4. Refuse more fixtures than one circuit is laid out with, and refuse an area no grid line falls
   in, naming the limit or the reason and setting nothing.
5. Aim each fixture at the ground its position wants (section 2.6) and put the fixtures in the
   circuit.

The grid maths is `PlantSpacing`'s, so a bed, the zone that waters it and the circuit that lights
it are laid out by one implementation of one rule, and potted or staggered mean the same thing in
all three.

### 4.2 The load check

load = the sum of the fixtures' own wattages. Then, in order:

| Refused when | Because |
|---|---|
| no transformer is stated | the answer would be a guess |
| the circuit has no fixtures | there is nothing to run |
| more than the fixture cap | it is more than one circuit |
| a fixture's voltage differs from the transformer's | it will not light at all |
| a fixture's kind is not known | there is nothing to add up |
| load > transformer capacity | the transformer cannot carry it; the report says how many fit |
| a fixture stands outside the circuit's own area | it lights somewhere it was not set for |

### 4.3 The cover check

Sample the area inside its ring on a 0.5 m grid; for every sample, ask whether any fixture
reaches it. A fixture reaches a point when the distance is within its throw and the direction
from the fixture to the point lies inside its aimed beam - which a 360-degree fixture passes
wherever the point is - with half a degree of slack at the beam's edge, because a point lying
exactly on a half beam's edge is lit and a check that called it dark would be measuring floating
point rather than a bed.

Report the fraction covered and the first point nothing reaches. Two honest outcomes worth knowing
about, because they are what the numbers look like:

* A bed whose side **is** a whole number of throws comes out at 1.000.
* A bed that is not comes out short and says by how much. The tool's answer to that is another
  fixture or a tighter spacing, and it is the designer's to make.

The check is **geometric**: it says a point is inside some fixture's beam, not how much light
lands on it. Photometrics - illuminance in lux, uniformity, glare - is not built (section 7), so
a design that the check calls covered is covered in the sense that no fixture was forgotten,
which is the mistake a cover check exists to catch.

## 5. Requirements

**REQ-LIT-1** A fixture kind MUST be one of the stated kinds, and a kind MUST carry a wattage, a
voltage, a throw and a beam spread.

**REQ-LIT-2** A circuit MUST hold a tap number and its fixtures, and MUST be numbered per plan.

**REQ-LIT-3** A circuit MUST NOT be reported as sound without a stated transformer.

**REQ-LIT-4** A circuit whose load exceeds the transformer MUST be refused, naming the load, the
transformer and the number of fixtures that would fit.

**REQ-LIT-5** A circuit whose fixture voltage differs from the transformer's MUST be refused.

**REQ-LIT-6** A fixture MUST NOT stand outside the area it is on a circuit for, where an area is
stated.

**REQ-LIT-7** A layout MUST set fixtures one throw apart fixture-to-fixture, MUST keep them on the
area (its boundary included), MUST aim each fixture at the ground its position wants, and MUST
refuse rather than truncate a circuit over the fixture cap.

**REQ-LIT-8** The load MUST be the circuit's own sum of fixtures, in watts, compared with the
transformer's own stated capacity.

**REQ-LIT-9** Cover MUST be measured, and a shortfall reported as a fraction rather than refused.

**REQ-LIT-10** A circuit MUST survive the drawing file, and an unreadable record MUST be dropped
rather than invented.

## 6. Acceptance criteria

| # | Criterion |
|---|---|
| AC-LIT-1 | Nine floodlights draw 108 W, a 100 VA transformer is refused, and the refusal names the load, the transformer and the eight fixtures that fit. |
| AC-LIT-2 | A circuit on a transformer that has not been stated is refused, and never reported as sound. |
| AC-LIT-3 | A half-beam fixture aimed one way leaves the ground behind it uncovered, and the cover check says so - as a report, not a refusal. |
| AC-LIT-4 | A 120 V lantern on a 12 V transformer is refused, and a 12 V path light on the same transformer is not. |
| AC-LIT-5 | A triangular layout at 1.155 throws sets fewer fixtures than the square one over the same bed, and both cover it. |
| AC-LIT-6 | A layout that wants more fixtures than the cap is refused, naming the cap, and sets no fixtures - and leaves the fixtures the circuit already had alone. |
| AC-LIT-7 | A circuit round-trips through the file with its fixtures at their own positions and aims; a record that is not a circuit is dropped, and a damaged fixture is dropped without losing its circuit. |
| AC-LIT-8 | A bed that is not a whole number of throws reports the ground it misses as a fraction naming the worst point, and is not refused for it. |

## 7. What is built, and what is not

**Built:** the fixture table, a circuit, the transformer, the layout rule on the planting grid
with the aim each position wants, the load check with its refusals, the cover check, the schedule
rows, and the circuit's file format. `scripts/draft/lighting.gd` is the arithmetic, with
`tests/test_lighting.gd` over it.

**Built, the drawing slice:** fixtures are entities on `501-LIGHTING` (section 2.9) with `fixture_entity`, `run_entity`, `is_fixture_entity`, `circuit_of_entity` and `fixture_words`; a circuit and the transformer travel in the drawing file under the document's `lighting` key (format **8**); and `draft_controller.gd` adds `lighting_circuits`, `lighting_transformer`, `set_lighting_transformer`, `lightable_areas`, `light_area`, `remove_circuit`, `lighting_rows`, `lighting_lines` and `lighting_summary`. Lighting an area is **one undo step** however many fixtures it sets: a circuit and its fixtures are one act. A circuit that would not run off the stated transformer is **not put on the drawing at all**. The page that states the transformer and lights an area
is `scripts/lighting_panel.gd`, opened from the **Light** menu beside Water
(`_build_lighting_panel`, `open_light_panel`, `_on_light_transformer`, `_on_light_area`,
`_on_light_remove`), and the drawing slice is held down by `tests/test_lighting_tools.gd`.

**Not built yet, and why:**

* **Photometrics.** Illuminance, uniformity and glare want a light model - lumens, candela,
  beam curves - and a rendering pass. The cover check is geometric, and is stated as such.
* **Cable runs as a connected system.** A run is a polyline on `501-LIGHTING`, and the takeoff
  measures a line there as a length - but nothing holds the runs as a graph, and voltage drop
  along a run is not modelled. A long low-voltage run really does dim its far end, and stating
  that here is the point: the load check is a capacity check, not a voltage-drop calculation.
* **Transformer taps and load balancing across taps**, which is the analogue of the irrigation
  module's valve count against a manifold.
* **Control grouping** - which fixtures are on one switch, one timer or one photocell - which is
  a schedule and not a plan.
* **The lighting schedule on the sheet.** The module produces a circuit's row in words
  (`schedule`, `schedule_row_words`, `schedule_lines`) and the controller reads them off the
  drawing (`lighting_rows`), but `SheetExporter` does not yet emit a lighting table the way it
  emits the irrigation one. The mechanism is there; the block is not.

## 8. The tests, and what they hold down

`tests/test_lighting.gd` holds the arithmetic: the table is complete and every kind is named and
reachable; a full-circle fixture lights its throw and no further while a half-beam one lights
only its own half; the load check refuses each of its cases with the numbers in the sentence; the
fixture cap refuses without setting anything; a circuit round-trips through the file while a
broken record is dropped and a damaged fixture is dropped on its own; and the schedule and the
verdict line read as a designer reads them.

`tests/test_lighting_tools.gd` holds the drawing slice: the transformer is stated for the
whole drawing and one undo step returns it; a bed is lit in one step and the fixtures land on
`501-LIGHTING` carrying their circuit, kind and aim; a fixture's radius is three millimetres of
paper however the scale changes; an over-capacity circuit, a tiny area, an area the grid
cannot land in, an unknown kind and a line-voltage lantern on a low-voltage transformer are
all refused *without touching the drawing*; a circuit that would not run is not put on the
plan; circuits are numbered and tapped apart; a circuit travels in the file (version 8) while
a damaged record is dropped; and taking a circuit off takes its fixtures with it.

`tests/test_lighting_panel.gd` holds the page: the areas the drawing offers are the ones the
drop-down shows and a redraw does not move the choice; the spacing is the factor applied to
the chosen fixture's own throw, so a floodlight's 9 m and a path light's 2.5 m are the same
choice and different numbers; the light button is dead until there is both an area and a
*stated* transformer - it reads the drawing's transformer, never its own default; a capacity
that is not one of the conventional values is shown as itself rather than rounded; the budget
line names what the transformer buys; the circuit list carries the selection across a refresh;
and nothing in the page takes the keyboard.

`tests/test_hud_light.gd` holds the wiring: the Light menu offers lighting an area, with the
controller's own summary and the transformer on its info line; stating the transformer and
lighting an area through the page's own signals change the drawing and say what happened;
lighting an area the page has that has since gone says so rather than failing; and the page's
line reports the verdict until it is cleared, then the circuits the drawing holds.

---

See also: `drafting-subsystem-spec.md` section 5 for the layer this lands on,
`irrigation-subsystem-spec.md` for the sibling module it is built beside,
`plant-database-spec.md` section 5a for the grid it is laid out on, and
`business-operations-spec.md` section 6 for what prices it.
