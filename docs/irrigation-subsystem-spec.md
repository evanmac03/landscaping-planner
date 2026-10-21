# The irrigation module

A garden plan says where the water goes. This is the arithmetic of that: what a head is,
what a zone is, and - the part a drawing alone cannot tell you - whether the zone can
actually be run off the water supply that is there.

It is a module in the same sense the planting is: a table of facts (a head kind has a flow,
a throw and a pressure), a rule that turns an area into a layout, and a check that refuses a
zone that would not work. Nothing here draws. Drawing is a layer and a symbol, and the plan
it lands on is the drawing the rest of the app already reads.

## 1. What already exists, and what this adds

The plan already has the places irrigation goes:

* `500-IRRIGATION` - heads, zones and pipe runs, cyan at 0.18 mm, and it plots. From the
  layer set, so a renamed layer cannot leave a head on a driveway.
* The **Irrigation plan** layer state, which is the base plan plus this layer.
* The takeoff already prices anything on the layer as a **count** with cost code
  `IRRIGATION`, and the estimate desk already refuses a plan whose irrigation nothing can
  price.
* The planting grid, the bed areas a planting goes in, and the sheet's key and schedule.

What is added here is the part that is arithmetic rather than drawing: a head table, a
layout rule, and the **flow check**. A plan of heads that cannot all run at once is not a
design, and no amount of linework will say so.

## 2. Load-bearing decisions

### 2.1 A head kind is a table, not a free-text field

A designer picks a *kind* - a spray head, a gear rotor, a micro-spray, a bubbler - and the
kind carries the three numbers that decide everything else: its **flow** in litres per
minute, its **throw** in metres, and the **pressure** it needs to do that. A free field
would let a plan hold a head that waters four metres and draws nothing, and every check
downstream would be arithmetic on a number nobody could check.

| Kind | Flow | Throw | Default arc | Pressure |
|---|---|---|---|---|
| Spray head | 9.0 L/min | 4.5 m | 180 deg | 210 kPa |
| Gear rotor | 13.0 L/min | 11.0 m | 360 deg | 350 kPa |
| Micro-spray | 3.0 L/min | 2.5 m | 180 deg | 200 kPa |
| Bubbler | 8.0 L/min | 0.9 m | 360 deg | 150 kPa |

### 2.2 A zone is a valve, and the heads it runs

A zone is not a colour on a plan. It is the set of heads that open together on one valve,
and that is why it has a **flow demand** - the sum of its heads - and why two zones on one
supply must not both be asked to run at once. Numbering is per plan, and a valve number is
handed out once.

### 2.3 The supply is stated, never assumed

A supply is a flow at a pressure: `40 L/min at 350 kPa` is a service line. It is **asked
for**, and a zone with no supply stated is **refused rather than blessed** - the same
decision the DXF reader makes about `$INSUNITS`, for the same reason. A check that silently
assumed forty litres a minute would pass a plan that cannot be built, and a designer would
find out from a dry bed.

The pressure is not decoration either: a rotor wants 350 kPa, and a supply at 220 kPa will
not drive one. That is a refusal, not a warning.

### 2.4 One place does the arithmetic, and it refuses

The checks live in one script and return a verdict with reasons in words, so the panel that
reports them and the test that holds them down read the same sentence. A refusal names the
numbers: not `too many heads`, but `12 spray heads draw 108 L/min and the supply gives 40 -
4 of them fit`.

### 2.5 Heads tile the area, spacing is head-to-head, and a head is not a plant

Heads are set one **throw** apart, which is the head-to-head layout every manufacturer's
sheet draws: each head waters to the next, so no ground is missed between them. The grid is
phased from the area's own bounding box, so a bed whose side is a whole number of throws
gets a line of heads **on each edge and on every grid line between them**. Heads on the
boundary are the point of the layout: the corner ones take quarter nozzles facing in, the
edge ones halves, the middle ones full circles - and the ground is watered edge to edge.
That is why a layout does **not** pull a head in from the edge. A plant is pulled in by
half its spread and its *canopy* meets the edge; a head is where its *water* is wanted, and
a head shoved half a throw inside leaves the strip behind it dry, which measuring the
coverage shows at once.

A **triangular** grid - each row half a spacing across from the one before it - covers the
same ground with rows `sqrt(3)/2` of a spacing apart, so the spacing can be taken out to
`2/sqrt(3)` (1.155) of the throw. Measured on a 30 m square: **49 heads square against 42
staggered**, one head in seven saved for the same coverage, at 0.94 of it either way.

### 2.6 The nozzle a position wants is the ground around it

A head's **arc** and **heading** belong to the head that was placed, not to its kind: a kind
has a default, and every head a layout sets is fitted the nozzle its own position wants.
That rule is not "a corner is a quarter" as a lookup - it is the honest reading of it:
**the arc of the head's own throw circle that lies over the area**, sampled round the head
every 15 degrees at 0.9 of the throw and rounded to a quarter circle a person can buy. The
heading is the direction of the ground it does have.

Worked on a 9 m square, which is two throws each way, the layout comes out exactly the
textbook plan: **four quarter nozzles on the corners, four halves on the edges and one full
circle in the middle**, and the coverage of the bed is 1.000. A head on the edge of a 1 m
strip, where only a quarter of its throw is over the bed, comes out a quarter - and the
check then reports that the strip is only half watered, which is the truth about putting a
4.5 m spray head on a 1 m bed.

### 2.7 The precipitation rate is the number a designer checks

Flow over area, in millimetres per hour: `flow x 60 / area`, because one litre over one
square metre is one millimetre. It is the number that tells a spray zone (about 25 mm/h)
from a rotor zone (about 6 mm/h), and it is why a plan cannot mix them on one valve. It is
a zone-level number and it is *not* a per-head one: heads are set to overlap, and what
reaches the ground is the zone's flow over the zone's whole area.

### 2.8 Coverage is measured on a grid, not asserted

The zone's area is sampled on a stated grid (0.5 m), and every sample point is asked whether
some head reaches it - inside the throw **and** inside that head's arc. The answer is a
fraction and the point of the worst gap, and a shortfall is reported rather than hidden. A
designer may water a bed on drip and leave a mature tree to the rain, so a gap is a fact to
report, not a defect to refuse - unlike an overloaded valve, which is a defect.

### 2.9 Heads are entities on `500-IRRIGATION`

A placed head is a circle on the irrigation layer carrying its kind, its zone and its
heading in its own metadata, so the takeoff counts it, the sheet keys it, and selecting it
says what it is - with no second model to keep in step. The radius is a *paper* size -
`HEAD_SYMBOL_MM`, three millimetres - so a head is 0.3 m of ground at 1:100 and 0.6 m at
1:200: a head is a symbol on a plan rather than a measured object, and drawing it in model
metres instead would make it invisible on a garden plan and enormous on a detail. The plan
canvas draws it by the same path as every other shape.

A zone is a property of the **drawing**, not of a caller's memory: the module writes
`{zones: [...], supply: {...}}` under the document's `irrigation` key, which is what makes a
zone and the heads that belong to it arrive together and leave together.

## 3. Data models

### 3.1 A head

```
{ kind: String, at: Vector2, heading: float (radians), arc: float (degrees, 0 = the kind's own) }
```

### 3.2 A zone

```
{
  number: int, valve: int, kind: String, area: PackedVector2Array, area_m2: float,
  heads: Array, spacing: float, staggered: bool
}
```

A zone holds one kind, because a valve runs one kind. Its area is the ring a plan encloses,
and it is optional: heads can be set without one, and then coverage and precipitation cannot
be worked out and the report says so.

### 3.3 The supply

```
{ flow: float (L/min), pressure: float (kPa) }
```

### 3.4 The file

A zone survives the drawing file: numbers and strings as themselves, and a head's position
as a two-number pair, because JSON has no vector. Reading back is defensive for the reason
every other reader here is: a record that is not a zone is dropped rather than invented,
and a head that is not a head is dropped without losing the zone it was in.

## 4. The algorithms

### 4.1 Laying heads out

1. Refuse an outline that is not a ring, encloses no ground, or a spacing tighter than a
   plan draws.
2. Set the grid: `spacing` (defaulting to the kind's own throw, and to 1.155 times it when
   staggered), phased from the area's bounding box, with rows `sqrt(3)/2` of a spacing apart
   and each odd row shifted half a spacing when triangular.
3. Keep the points inside the ring. A point on the boundary counts as inside - head to the
   edge is head to the edge - which is what makes the outer row of a whole-throw bed
   possible.
4. Refuse more heads than one zone is laid out with, and refuse an area no grid line falls
   in, naming the limit or the reason and setting nothing.
5. Fit each head the nozzle its position wants (section 2.6) and put the heads in the zone.

The grid maths is `PlantSpacing`'s, so a bed and the zone that waters it are laid out by one
implementation of one rule, and potted or staggered mean the same thing in both.

### 4.2 The flow check

demand = the sum of the heads' own flows. Then, in order:

| Refused when | Because |
|---|---|
| no supply is stated | the answer would be a guess |
| the zone has no heads | there is nothing to run |
| more than the head cap | it is more than one zone |
| two kinds on one valve | a rotor zone and a spray zone are different schedules |
| a head's kind wants more pressure than the supply gives | it will not run at all |
| demand > supply flow | the valve cannot be opened; the report says how many heads fit |
| a head stands outside the zone's own area | it waters somewhere it was not set for |

### 4.3 The coverage check

Sample the area inside its ring on a 0.5 m grid; for every sample, ask whether any head
reaches it. A head reaches a point when the distance is within its throw and the direction
from the head to the point lies inside its arc - which a 360-degree head passes wherever the
point is - with half a degree of slack at the arc's edge, because a point lying exactly on a
half head's edge is watered and a check that called it dry would be measuring floating point
rather than a bed.

Report the fraction covered and the first point nothing reaches. Two honest outcomes worth
knowing about, because they are what the numbers look like:

* A bed whose side **is** a whole number of throws comes out at 1.000 (9 m, 18 m).
* A bed that is not comes out short and says by how much: a 20 m bed at a 4.5 m throw lays
  out five grid lines and leaves 4% of the ground beyond every head. The tool's answer to
  that is another head or a tighter spacing, and it is the designer's to make.

The check is **geometric**: it says a point is inside some head's pattern, not how much water
lands on it. Uniformity is hydraulics, which is not built (section 7) - so a design that the
check calls covered is covered in the sense that no head was forgotten, which is the mistake
a coverage check exists to catch.

## 5. Requirements

**REQ-IRR-1** A head kind MUST be one of the stated kinds, and a kind MUST carry a flow, a
throw, a default arc and a pressure.

**REQ-IRR-2** A zone MUST hold one kind, one valve number and its heads, and MUST be
numbered per plan.

**REQ-IRR-3** A zone MUST NOT be reported as sound without a stated supply.

**REQ-IRR-4** A zone whose demand exceeds the supply MUST be refused, naming the demand, the
supply and the number of heads that would fit.

**REQ-IRR-5** A zone whose kind wants more pressure than the supply gives MUST be refused.

**REQ-IRR-6** Two kinds MUST NOT share one valve.

**REQ-IRR-7** A head MUST NOT stand outside the area it is zoned for, where an area is
stated.

**REQ-IRR-8** A layout MUST set heads one throw apart head-to-head, MUST keep them on the
area (its boundary included), MUST fit each head the nozzle its position wants, and MUST
refuse rather than truncate a zone over the head cap.

**REQ-IRR-9** The precipitation rate MUST be the zone's own flow over its own area, in
millimetres per hour.

**REQ-IRR-10** Coverage MUST be measured, and a shortfall reported as a fraction rather than
refused.

**REQ-IRR-11** A zone MUST survive the drawing file, and an unreadable record MUST be dropped
rather than invented.

## 6. Acceptance criteria

| # | Criterion |
|---|---|
| AC-IRR-1 | Twelve spray heads draw 108 L/min, a 40 L/min supply is refused, and the
refusal names the demand, the supply and the four heads that fit. |
| AC-IRR-2 | A zone on a supply that has not been stated is refused, and never reported as
sound. |
| AC-IRR-3 | A half-circle head facing one way leaves the ground behind it uncovered, and the
coverage check says so - as a report, not a refusal. |
| AC-IRR-4 | A zone of 100 m2 drawing 6.0 L/min reports 3.6 mm/h, and says so in its own line. |
| AC-IRR-5 | A rotor wanted on a 220 kPa supply is refused, and a spray head on the same supply
is not. |
| AC-IRR-6 | A triangular layout at 1.155 throws sets 42 heads where the square one sets 49,
over the same 30 m bed. |
| AC-IRR-7 | A 9 m square lays out nine heads, four of them quarter nozzles on the corners and
four halves on the edges, one on each grid line including the edges, and covers the bed
completely. |
| AC-IRR-8 | A layout that wants more heads than the cap is refused, naming the cap, and sets
no heads - and leaves the heads the zone already had alone. |
| AC-IRR-9 | A zone round-trips through the file with its heads at their own positions and
headings; a record that is not a zone is dropped, and a damaged head is dropped without
losing its zone. |
| AC-IRR-10 | A bed that is not a whole number of throws reports the ground it misses as a
fraction naming the worst point, and is not refused for it. |

## 7. What is built, and what is not

**Built:** the head table, a zone, the supply, the layout rule on the planting grid with the
nozzle each position wants, the flow check with its seven refusals, the precipitation rate,
the measured coverage check, the schedule rows, and the zone's file format.
`scripts/draft/irrigation.gd` is the arithmetic, with `tests/test_irrigation.gd` over it -
36 tests, every count and every fraction in them hand-computed from the grid.

**Built, the drawing slice:** heads are entities on `500-IRRIGATION` (section 2.9), a zone and
the supply travel in the drawing file, and the Water menu opens the page that states a supply,
waters an area and lists the zones. The pieces are `scripts/draft/irrigation.gd`
(`head_entity`, `run_entity`, `is_head_entity`, `zone_of_entity`, `head_words`),
`draft_controller.gd` (`irrigation_zones`, `irrigation_supply`, `set_irrigation_supply`,
`waterable_areas`, `water_area`, `remove_zone`, `irrigation_rows`, `irrigation_summary`), the
document's `irrigation` property (format **7**), and `scripts/irrigation_panel.gd` with its HUD
page and its Water menu. Watering an area is **one undo step** whether it sets one head or
fifty: a zone and its heads are one act, and Ctrl+Z takes the whole thing back. A zone that
would not run off the stated supply is **not put on the drawing at all** - the page says why
and leaves the plan alone.

**Not built yet, and why:**

* **Drip.** A drip zone is a run of tubing rather than a set of points: its flow is
  per metre and its wetted ground is a strip either side of the line. That wants a second
  geometry and a second coverage rule, and it is deliberately not faked as small point heads.
* **Pipe runs as a connected system.** `run_entity` writes the polyline a run would be on
  `500-IRRIGATION`, and the takeoff measures a line there as a length - but no palette places
  a run yet, and nothing holds the runs as a graph, so where the water goes and how far it has
  to travel are not modelled.
* **Hydraulics proper:** pressure loss along a pipe run, matched precipitation rates across
  zones, and a valve count against the manifold. Stated here so nobody mistakes the flow
  check for a hydraulic calculation - it is a capacity check, which is what a plan needs.
* **The lighting module**, which is 501 and a sibling of this one.

## 8. The tests, and what they hold down

`tests/test_irrigation.gd` holds the arithmetic: the table is complete and every kind is named
and reachable; a full-circle head covers its throw and no further while a half-circle one
covers only its own half; the flow check refuses each of its seven cases with the numbers in
the sentence; the
precipitation rate is the stated law (3.6 mm/h) and the verdict line carries it; the layout
lands on the grid lines including the edges and lays out the textbook nine-head square; a
triangular layout sets 42 where the square sets 49 and both cover the bed; a bed that is not a
whole number of throws reports what it misses; the cap refuses without setting anything and
without disturbing the zone; a zone round-trips through the file while a broken record is
dropped and a damaged head is dropped on its own; and the schedule, the schedule lines and the
verdict line read as a designer reads them.

`tests/test_irrigation_tools.gd` holds the drawing slice: the supply is stated for the whole
drawing and one undo step returns it; a bed is watered in one step and the heads land on
`500-IRRIGATION` carrying their zone, kind and nozzle; a head's radius is three millimetres of
paper however the scale changes; an over-supply, a tiny area and an unknown kind are all
refused *without touching the drawing*; a zone that would not run is not put on the plan;
zones are numbered and valved apart; a zone travels in the file (version 7) while a damaged
record is dropped; and taking a zone off takes its heads with it.

`tests/test_irrigation_panel.gd` holds the page: the areas the drawing offers are the ones the
drop-down shows and a redraw does not move the choice; the spacing is the factor applied to
the chosen head's own throw, so a rotor's 11 m and a spray's 4.5 m are the same choice and
different numbers; the water button is dead until there is both an area and a *stated* supply
- it reads the drawing's supply, never its own default; a supply that is not one of the
conventional values is shown as itself rather than rounded; the budget line names what the
supply buys; the zone list carries the selection across a refresh; and nothing in the panel
takes the keyboard.

`tests/test_hud_water.gd` holds the wiring: the Water menu offers watering an area, with the
controller's own summary and the supply on its info line; stating the supply and watering an
area through the page's own signals change the drawing and say what happened; watering an area
the page has that has since gone says so rather than failing; and the page's line reports the
verdict until it is cleared, then the zones the drawing holds.

---

See also: `drafting-subsystem-spec.md` section 5 for the layer this lands on,
`plant-database-spec.md` section 5a for the grid it is laid out on,
`business-operations-spec.md` section 6 for what prices it, and
`visualization-subsystem-spec.md` for why this layer has no colour wash.
