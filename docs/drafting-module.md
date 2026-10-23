# Precision drafting module — design

A design for adding CAD-grade drafting to the landscaping planner: exact
coordinate entry, object snapping, measurement, imperial + metric units, and
parametric geometry.

The existing app already has the right spine for this. It keeps **one 3D world
and treats the flat plan as a second projection of it**, so an object moved in
one view is moved in both with no state to reconcile. This module extends that
principle rather than bolting a separate drawing engine beside it.

---

## 1. What already exists, and what changes

| Today | This module adds |
|---|---|
| `PlanCanvas` draws the yard's meshes and prop symbols, in metres | draws **drafting entities** too, from a document |
| Props are `Node3D` instances in the `placeable` group | props stay as they are; linework lives in a document |
| `ViewController` drags a prop to a new XZ | a **tool mode** adds draw/measure tools alongside Select |
| Everything is metres, implicitly | an explicit **unit system** at the edges, metres inside |
| Picking is a screen-space linear scan (`nearest_placeable`) | a **spatial index** plus a snap engine |

The two views and the ground view stay; nothing is rewritten.

### The one model rule, restated

The codebase deliberately has one home for each fact. That rule survives:

- **Placed assets** (plants, features) keep their home in the scene graph —
  a node transform is the truth, and `PlanCanvas` projects it.
- **Drafting linework** (bed outlines, paving edges, arcs, dimensions) gets a
  new home: the *document*. The document is the truth; the scene draws it.

Neither is duplicated, so the two overhead views still cannot disagree. The
distinction is natural — a CAD drawing has both *linework* and *inserted
blocks*, and they are stored differently.

---

## 2. Load-bearing decisions

These are the choices everything else follows from. Each is justified below.

### D1 — Coordinates are stored as definitions in double precision, in a site-local frame

**Measured on this machine** (Godot 4.7.2, single-precision build — confirmed:
`Vector2(0.1).x == 0.1` is `false`, so `Vector2` is 32-bit). The smallest
distinguishable step through a `Vector2` round-trip:

| Coordinate magnitude | float32 step | Verdict |
|---|---|---|
| 10 m (garden) | 0.95 µm | fine |
| 100 m (large estate) | 7.6 µm | fine |
| 1 km | 61 µm | fine |
| 10 km | 0.98 mm | fine |
| 500,000 m (UTM easting) | 31 mm | useless for drafting |
| 5,000,000 m (UTM northing) | **0.5 m** | **useless** |
| 5,000,000 m, as `float` (double) | 9.3e-10 m | fine |

So the rule is not "Vector2 is unsafe" — at garden scale it resolves to about a
micrometre, which no landscaping plan can perceive. The rule is:

- **Store** coordinates in `PackedFloat64Array` (GDScript `float` is 64-bit),
  never as `Vector2`.
- **Draw** by converting to `Vector2` at the last moment; a micrometre of error
  at draw time is invisible.
- **Never store absolute, georeferenced survey coordinates in model space.** If
  a plan is georeferenced, keep the georeference as a *separate* transform from
  site-local drawing coordinates. A float32 UTM northing is half a metre of
  garbage; doubling precision everywhere would be the expensive way to avoid a
  problem that a site origin solves for free.

This also matches the engine's own guidance: it recommends large-world
coordinates only past ~8192 m for 3D, and notes 2D rendering gains nothing from
them.

### D2 — Metre is the only internal unit; imperial is a display and entry format

Storing lengths in the unit they were typed in is the classic CAD trap: two
entities measured in different units can no longer be compared, offset, or
snapped together without a conversion at every touch. Instead:

- **Model:** metres, double, always.
- **Edges:** parse from the active unit system on entry, format to it on display.
- **Constants** for conversion are exact by definition (see §6), so round-trips
  are lossless to within double precision.

### D3 — Display rounding never writes back

A length typed as `12'6"` is stored as `3.81` m exactly (12.5 × 0.3048). A
display precision of two decimals would print `3.81`, and if that were ever
written back the plan would drift. So formatting is a pure *read* operation:
`format_length(value) -> String` has no counterpart that stores its output.

### D4 — Snap and pick apertures are defined in pixels, converted at the current zoom

A tolerance in metres is unusable: at one zoom an 0.05 m aperture is
unreachable, at another it swallows the whole drawing. The aperture is a
property of the pointing device, so it is set in pixels and converted:

```
aperture_metres = aperture_pixels / pixels_per_metre
```

`pixels_per_metre` already exists as `viewport_height / plan_size`, so the plan
and the 3D overhead view share it exactly.

### D5 — Use Godot's built-in 2D boolean kernel for polygon work; hand-write only the precision-critical primitives

Verified present in this build: `Geometry2D` has `offset_polygon`,
`offset_polyline`, `merge_polygons`, `clip_polygons`, `intersect_polygons`,
`exclude_polygons`, `convex_hull`, `is_point_in_polygon`, `triangulate_polygon`,
`decompose_polygon_in_convex`, `is_polygon_clockwise`,
`segment_intersects_segment`, `segment_intersects_circle`, `line_intersects_line`,
`get_closest_point_to_segment`, and `JOIN_MITER` / `JOIN_ROUND` / `JOIN_SQUARE`.
Checked: `offset_polygon(10×10 square, -1.0, JOIN_MITER)` returns exactly
`(1,1)..(9,9)`.

That is a Clipper-grade polygon engine for free, and hand-rolling polygon
booleans is a well-known way to lose a month. **Use it for:** polygon offsets,
unions/differences, point-in-polygon, hulls, triangulation.

**Hand-write instead** the small set of routines where we need double precision
and exact predicate behaviour: point/segment distance, segment×segment
intersection, line×circle, circle×circle, and the offset-line intersection used
for bed borders. These take and return doubles and never touch `Vector2`.

---

## 3. Architecture

### Layers

The standalone `scripts/draft/layer_dialog.gd` helper is not wired into the main
HUD. Assign its `controller` before use; it reads the controller's current
document, filters the actual layer records and delegates layer selection to the
controller. Lock changes use the document's undo history and change signal.
`tests/test_layer_dialog.gd` covers filtering, layer properties, selection and
undoable locking.

```
  L5  presentation      plan_canvas.gd (extended)   draft_view_3d.gd (new)
                                    \                    /
  L4  interaction        tool_select  tool_line  tool_arc  tool_polygon  tool_measure
                                  \        |        /
                          draft_controller.gd   +   hud (command line, status bar, snaps)
                                    |
  L3  snapping             snap_engine.gd  ---  spatial_grid.gd
                                    |
  L2  model                draft_document.gd  ---  draft_entity.gd (+ kinds)  ---  gesture_history.gd
                                    |
  L1  geometry kernel      geom2d.gd  (double precision, pure)   ---  units.gd
                                    |
  L0  units                units.gd  (metre canonical, metric + imperial)
```

Every layer only calls downward. `geom2d.gd` and `units.gd` are pure and
static, exactly like the existing `ViewMath`, so both are unit-testable with no
scene at all — which is how the current test suite already works.

### Data flow

```
pointer / keyboard
      |
      v
draft_controller  -- screen(t)-->  geom2d/units   (screen -> double world XZ)
      |                                   |
      |                                   v
      |                            snap_engine  --uses-->  spatial_grid
      |                                   |
      |                    snapped double point + snap kind (for the marker)
      v                                   |
   active tool  --- builds/edits entities (double params)
      |                                   |
      v                                   v
  draft_document  --changed(id)-->  plan_canvas.cue_redraw() + draft_view_3d.rebuild(id)
      |
      v
   gesture_history (a named snapshot before each committed gesture)
```

The `changed` signal is the whole sync mechanism. Both views subscribe; neither
holds a copy. This is the same guarantee the app already gives for props.

### Screen ↔ world, in double

`PlanCanvas.screen_to_world` currently goes through `position` and `scale`,
which are `Vector2` (float32). For drafting, compute straight from the shared
view state so the arithmetic stays in double:

```
pixels_per_metre = viewport.y / plan_size            # both doubles
world.x = focus.x + (screen.x - viewport.x * 0.5) / pixels_per_metre
world.y = focus.y + (screen.y - viewport.y * 0.5) / pixels_per_metre
```

`focus`, `plan_size` and the viewport size are already available on
`ViewController`, so no new state is needed. The forward direction is the
inverse and is used for drawing and for sizing the snap marker.

### Files

| File | Role |
|---|---|
| `scripts/draft/units.gd` | unit system, parse/format, area & volume |
| `scripts/draft/geom2d.gd` | pure double geometry kernel |
| `scripts/draft/spatial_grid.gd` | uniform-grid AABB index |
| `scripts/draft/snap_engine.gd` | candidate generation and prioritised selection |
| `scripts/draft/draft_entity.gd` | entity base + parameter layouts |
| `scripts/draft/draft_document.gd` | entity store, layers, change signals |
| `scripts/draft/gesture_history.gd` | named, serial-numbered gesture history |
| `scripts/draft/draft_controller.gd` | tool modes, input routing, dynamic input |
| `scripts/draft/tools/*.gd` | one state machine per tool |
| `scripts/draft/draft_view_3d.gd` | projects entities into the 3D scene |
| tests | `tests/test_geom2d.gd`, `test_units.gd`, `test_snap.gd`, `test_draft_document.gd` |

### Integration points with existing code

| Existing file | Change |
|---|---|
| `plan_canvas.gd` | draw `document.entities` between context and props; take a document reference; switch from repaint-every-frame to repaint-on-change |
| `view_controller.gd` | expose `screen_to_world_exact()`; hand input to `draft_controller` when a drawing tool is active, otherwise keep the current drag-to-move |
| `main.tscn` | add the document resource, `DraftController`, `DraftView3D` |
| `hud.tscn` / `hud.gd` | add a snappable tool strip, a dynamic-input line edit, and a status readout |
| `plan_style.gd` | add drafting colours/line styles alongside the material palette |
| `project.godot` | input actions for the tools, ortho toggle, snap toggles |

**Tool mode versus the existing drag.** The current behaviour (left-drag moves a
plant) becomes the `SELECT` tool. When any drawing tool is active, left-click
feeds that tool and prop-dragging is suppressed. `Escape` returns to `SELECT`.
That keeps the existing interaction intact and makes the new one additive.

---

## 4. Data structures

### Entity

```gdscript
class_name DraftEntity extends RefCounted

enum Kind { LINE, ARC, CIRCLE, POLYLINE, POLYGON, RECT, REGULAR_POLY, DIMENSION, TEXT }

var id: int                  # stable, assigned by the document
var kind: Kind
var layer: StringName = &"design"
var params: PackedFloat64Array   # the geometry — see table
var style: StringName = &"solid"
var meta: Dictionary = {}    # notes, plant refs, takeoff class
```

Geometry lives in **one flat double array per entity**, not a list of objects.
That keeps a 5,000-vertex planting bed outline at 80 KB in one contiguous
allocation instead of 5,000 `RefCounted` instances, and it serialises directly.

| Kind | `params` layout | Notes |
|---|---|---|
| `LINE` | `[x0, y0, x1, y1]` | start, end |
| `CIRCLE` | `[cx, cy, r]` | r > 0 |
| `ARC` | `[cx, cy, r, start_angle, sweep_angle]` | centre form; signed sweep sets direction |
| `POLYLINE` | `[n, x0,y0, x1,y1, …]` | open; `n` = vertex count |
| `POLYGON` | `[n, x0,y0, x1,y1, …]` | implicit closing edge |
| `RECT` | `[cx, cy, w, h, rotation]` | parametric: centre, size, angle |
| `REGULAR_POLY` | `[cx, cy, circumradius, n, rotation]` | parametric |
| `DIMENSION` | `[x0,y0, x1,y1, offset, kind]` | associative: stores *pointers* (see below) |
| `TEXT` | `[x, y, rotation]` + `meta.text` | |

Two representation notes worth stating explicitly:

- **Arcs are stored centre-form** (`cx, cy, r, start, sweep`), because that is
  the form every computation wants: point-on-arc, tangents, intersection. The
  *tool* accepts centre-start-end and three-point input and converts once.
- **Polyline bulges.** To let an arc live inside a polyline (rounded bed
  corners, which landscape drawings are full of), add a parallel
  `PackedFloat64Array bulges` where `bulge = tan(sweep / 4)`. This is the DXF
  convention and it composes with the single flat-array layout. Signed bulge
  defines arc direction, and `bulge == 0` is a straight segment.

### Parametric versus frozen

Every entity above is **parametric**: it stores a definition, so editing means
changing a parameter, not moving sampled points. Editing a `RECT`'s `w`
regenerates its outline; editing an `ARC`'s radius keeps its endpoints' angles.
A polyline is "frozen" in the sense that its vertices are the definition — which
is correct, because that *is* the geometry the user drew.

Associativity: a `DIMENSION` stores entity id + parameter index at each end
(e.g. "vertex 3 of entity 12") rather than raw coordinates, so moving the bed
updates its dimension text. That is what makes measurement trustworthy.

### Document

```gdscript
class_name DraftDocument extends RefCounted

signal changed()                  # any edit, for view repaint
signal entity_added(id: int)
signal entity_removed(id: int)

var entities: Dictionary = {}     # id -> DraftEntity
var draw_order: PackedInt32Array  # z-order; entities draw in this sequence
var layers: Dictionary = {}       # name -> {colour, visible, locked, line_width}
var units: UnitSystem
var next_id: int = 1

func add(entity) -> int
func remove(id: int) -> void
func replace(id: int, entity) -> void
func commit(undo: UndoStack) -> void   # push snapshot, emit changed
```

### Spatial index

A **uniform grid** of buckets over the site AABB, cell ≈ 4 m:

```gdscript
class_name SpatialGrid extends RefCounted
var cell_size: float
var buckets: Dictionary        # Vector2i -> PackedInt32Array of entity ids
var entity_aabb: Dictionary    # id -> Rect2 (double, stored as 4 floats)
```

Chosen over an R-tree because a residential plan is hundreds to low thousands of
entities, edits are incremental, and a grid rebuilds in microseconds while an
R-tree needs rebalancing on every insert. Revisit past ~50k entities.

Rebuild cost is O(n). For interactive adds, insert into the touched buckets
only (the entity's AABB), and on delete remove from those same buckets.

### Snap candidate

```gdscript
{ "point": Vector2, "kind": int, "entity": int, "priority": int, "label": String }
```

Point stays `Vector2` here deliberately: candidates are transient and are only
ever compared at pixel tolerance.

### Tool state

Each tool is a small state machine with an explicit pending-point buffer:

```gdscript
# tool_line.gd
var _pending: Array[Vector2] = []
func on_click(world: Vector2, snapped: Dictionary) -> void
func on_move(world: Vector2, snapped: Dictionary) -> void   # preview only
func on_cancel() -> void
func on_enter_value(text: String) -> void                   # dynamic input
```

Two-point tools (line, rectangle) commit on the second click; polyline and
polygon accumulate until `Enter`/`Close`. Keeping the preview in `on_move`
means an aborted tool has changed nothing.

---

## 5. Algorithms

### 5.1 Snapping

Object snapping is what makes drafting feel exact; the algorithm is a
candidate-generation problem with a strict priority order.

**Pipeline**

1. Cursor pixel → double world point `p` (`§3`).
2. Aperture `A = aperture_pixels / pixels_per_metre`.
3. Query the grid for entities whose AABB (grown by `A`) contains `p`.
4. Generate candidates per entity by kind, cheapest first:
   - **endpoint / vertex** — every vertex in the AABB.
   - **midpoint** — segment midpoints.
   - **centre / quadrant** — arc and circle centres, and the four cardinal
     points on a circle.
   - **intersection** — only when two or more candidate entities overlap the
     aperture, and only between those; this keeps intersections off the hot path.
   - **perpendicular / tangent / nearest** — computed against the *previous*
     point of the active tool, since a perpendicular foot is undefined alone.
5. Score and pick by lexicographic `(priority, pixel_distance)`. A candidate
   outside `A` is discarded.
6. **Snap lock / hysteresis.** Keep the current snap while the cursor stays
   inside an enlarged exit aperture (`A × 1.6`). Without this a snap flickers
   between two coincident candidates as the mouse jitters by one pixel, which
   reads as instability and causes mis-clicks.
7. Draw the marker and its label (`×`, endpoint; `△`, midpoint; `○`, centre).

**Priority order** (lower wins, so a nearer-but-weaker candidate cannot steal
the snap from a stronger one):

| Priority | Snap | Rationale |
|---|---|---|
| 0 | endpoint | exact, intentional coincidence |
| 1 | intersection | exact |
| 2 | midpoint | exact |
| 3 | centre | exact |
| 4 | quadrant | exact |
| 5 | perpendicular | derived from the previous point |
| 6 | tangent | derived |
| 7 | nearest-on-entity | inexact — fallback only |
| 8 | grid | see below |
| 9 | polar / ortho tracking | see below |

**Grid snap is last.** A grid that outranks object snaps is a common design
mistake: it hijacks every point that happens to be near a grid line. Grid and
ortho are *tracking constraints*, not targets — better modelled as a
constraint pass that quantises the final point, enabled independently of object
snap, with its own toggle. Same for ortho (0°/90°) and polar (multiples of a
configured increment relative to the previous point).

**Intersection tolerance.** All kernel intersections must be computed in double
and tested with an *absolute* epsilon (`1e-9` m) rather than an exact equality.
Collinear-overlap is a distinct case: parallel segments within tolerance and
overlapping in projection have no unique intersection point, so either suppress
the candidate or offer the two overlap endpoints instead of inventing a point.

**Nearest-point-on-arc** is the one routine worth calling out, because the naive
form is wrong:

```
d = p - centre
angle = atan2(d.y, d.x)
candidate = centre + r * (cos, sin)
if angle is outside [start, start + sweep]: candidate = nearer of the two endpoints
```

### 5.2 Intersections (double precision, hand-written)

- **Segment × segment.** Solve parametrically — `p = a + t(b−a)`,
  `q = c + u(d−c)`; `denom = cross(b−a, d−c)`. If `|denom| < eps` the segments
  are parallel; otherwise `t = cross(c−a, d−c) / denom` and the hit counts only
  when `t, u ∈ [−eps, 1+eps]`. Clamp `t, u` into `[0,1]` before evaluating, so
  an endpoint-touching hit returns the exact endpoint rather than a
  nearly-endpoint point.
- **Line × circle.** Project the centre onto the line, then the half-chord is
  `sqrt(r² − d²)` with `d` the perpendicular distance; no hit if `d > r`.
- **Circle × circle.** Reduce to a line: the radical axis. Compute the
  centre-to-centre vector and the distance `d`; the chord's distance from `c0`
  along the axis is `a = (d² + r0² − r1²) / (2d)`, and the half-chord is
  `h = sqrt(r0² − a²)`. Then it is a line×circle with the line through
  `c0 + a·û` perpendicular to `û`. One code path instead of two special cases.
- **Segment × arc.** Intersect the full circle, then discard hits whose angle
  lies outside the arc's sweep (with the same wrap handling as §5.1).

### 5.3 Offsetting — used for bed borders

The domain operation that matters most: a planting bed with a uniform border, or
a paving area inset. Delegate to `Geometry2D.offset_polygon(polygon, delta,
join)`, `JOIN_ROUND` for beds (soil curving round a corner), `JOIN_MITER` for
paving.

Two caveats to design around:

1. **`Geometry2D` takes `Vector2` (float32).** Per D1 that is acceptable here —
   an offset is a drawing-scale operation over metres, and 10 µm of error is
   invisible. But the *result* is re-snapped to exact values where it must meet
   other geometry, and offsets are always committed as new entities (the source
   polygon is untouched), so error cannot accumulate across a session.
2. **Self-intersection.** Offsetting a concave polygon inward past a local
   width produces loops. `Geometry2D.offset_polygon` returns an `Array` of
   polygons for exactly this reason — take all of them rather than assuming one,
   and if the count changes, surface it in the status bar ("border makes 2
   regions") rather than silently dropping geometry.

### 5.4 Measurement

- **Distance / bearing.** `dx, dy` between two snapped points; report the length
  in the active unit and the bearing in survey convention (degrees clockwise
  from north, i.e. from −Z).
- **Running total.** A chain of picked points accumulates a total, which is the
  "tape measure" behaviour people expect for a fence run or a path length.
- **Area.** Shoelace: `A = ½ |Σ (xᵢ·yᵢ₊₁ − xᵢ₊₁·yᵢ)|`. Doubles, so a 20-vertex
  bed is exact. Also report perimeter, and `Geometry2D.is_polygon_clockwise` to
  get the sign convention right.
- **Arc length** = `r × |sweep|`; **chord** = `2r·sin(|sweep|/2)`.
- **Area takeoff (domain-specific).** Because the document knows which entity a
  measured region came from, area feeds derived quantities: mulch volume at a
  given depth, turf rolls, gravel tonnage. Store those as **properties on the
  entity** (`meta.takeoff = {class = "mulch", depth_m = 0.05}`) so they
  recompute automatically when the outline is edited, rather than being a
  one-off number that goes stale.
- **Dimension entities** are associative (§4) and are drawn, not just printed —
  extension lines, dimension line, arrowheads, text, with the text offset
  perpendicular by `offset` in `params`.

**Label placement.** Dimension text at a fixed offset collides in dense areas. A
cheap, effective rule: try eight anchor offsets (four perpendicular, four
diagonal), measure each against the AABBs of labels already placed this frame,
and take the first non-overlapping one, falling back to the perpendicular
default. Enough to look deliberate without a full layout engine.

### 5.5 Undo / redo: the gesture history

**Whole-document snapshots, not inverse commands.** A command/inverse
system is the textbook answer, but every tool then needs a correct inverse
— and a subtly wrong inverse corrupts the drawing in a way the user cannot
see or repair. A plan is small: 5,000 vertices is 40 KB, so a snapshot per
committed gesture costs ~40 KB. Cap the history at 200 gestures (8 MB) and
the whole problem disappears.

**A snapshot is taken on entry to the gesture, never on motion.** A drag that
moves a selected set, or a polyline tool mid-draw, pushes **one** snapshot,
not one per `on_move`.

**Undo is a gesture, not an anonymous stack.** `DraftGestureHistory`
(`scripts/draft/gesture_history.gd`, reached as `document.gestures` — the file
was renamed from `undo_stack.gd` because a file named for what it no longer is
is a lie) records each act with two extra facts beside its snapshot:

- a **label** — the words an undo button reads back, e.g. `drawing a new line`,
  `erasing`, `importing a DXF underlay`. `DraftController` names the gesture at
  every `begin_gesture(...)` site (the tool words come from
  `ToolScript.label_for(kind)` lower-cased, so `"drawing a new %s"` is correct
  for every kind); an act nobody labelled records as `UNNAMED` = `"an edit"`.
  Undo/redo button **text stays "Undo"/"Redo"** for width discipline — the
  gesture name goes in the **tooltip** (`Undo erasing (Ctrl+Z)`) and the status line.
- a **serial** — which gesture it was in the drawing's life, counted from 1 and
  **never reset by trimming or by `clear()`**: a count that went backwards would
  tell a revision that gestures had *un*happened.

**The serial is the join to the revision log.** `DraftRevisionLog.capture(...)`
records the serial the drawing was at, so a revision can answer *how many
gestures have happened since it was sent*. `"nothing has been done"` and `"not
known"` are different claims: a revision recorded before gestures were counted
says so (`gestures_since` returns 0 for a history written earlier, because the
`serial` field is simply absent), and the revision window shows it on its
**"Done since"** line. `DraftController.gestures_since_text(index)` is the one
place that turns the difference into words; restoring a revision records the
state it replaced as one named gesture (`putting a revision back`), so the
restore can itself be undone.

An open history **keeps up with the drawing it is about**: the HUD refreshes the window from its
own per-frame poll while the window is up (the same discipline the open water and lighting panels
follow), guarded by a signature of the drawing's name, the number of revisions kept and the gesture
the drawing is at. Without that a window left up while a designer keeps drawing would go on
claiming nothing had been done, which is a wrong answer rather than a stale one. An undo does *not*
put the count back - what happened to the drawing does not unhappen, and a revision sent in between
really did go out before those acts.

### 5.6 Hit-testing and culling

- Cull by viewport AABB before drawing (the grid makes this cheap).
- **Hit-test order is the reverse of draw order**: topmost entity under the
  cursor wins, which is what a user expects from overlapping linework.
- Hit tolerance is `pick_pixels / pixels_per_metre`, matching D4 — the existing
  prop picking already does exactly this, so the two interact consistently.
- Long entities must not be culled wrongly: test against the entity's AABB, and
  for an `ARC` store the AABB of the *arc* (endpoints plus any cardinal point
  inside the sweep), not of its bounding circle.

### 5.7 Trim, extend, fillet (scoped small)

These are the three edits that make drafting feel complete, and each reduces to
work already specified:

- **Trim**: intersect the target with the cutting edge, keep the fragment on the
  side the user clicked.
- **Extend**: intersect the target's unbounded ray with the boundary, keep
  direction.
- **Fillet**: given two entities meeting at a corner and a radius, find the
  tangent points and produce `LINE, ARC, LINE` — the arc in centre form, which
  is why that representation was chosen.

No general constraint solver. Genuine parametric constraints (tangency,
concentricity, equal-length) are a much larger project; this design deliberately
stops at associativity for dimensions.

---

## 6. Units

### Canonical unit and exact constants

The model is metres. Imperial conversion uses the international definitions,
which are **exact**, so no round-trip error is introduced:

| Unit | Metres |
|---|---|
| 1 inch | 0.0254 (exact) |
| 1 foot | 0.3048 (exact) |
| 1 yard | 0.9144 (exact) |
| 1 mile | 1609.344 (exact) |
| 1 metre | 1.0 |

Derived: `m²`, `ft²`, `yd²`, `m³`, `yd³`, and for takeoff, tonnes via a
per-material density.

### Parse and format

```gdscript
class_name UnitSystem extends RefCounted

enum System { METRIC, IMPERIAL }
enum LengthStyle { DECIMAL, ARCHITECTURAL, ENGINEERING }

var system: System = System.METRIC
var length_style: LengthStyle = LengthStyle.DECIMAL
## Display only. Never written back into the model.
var display_precision: int = 3
## Smallest inch fraction accepted, e.g. 16 for 1/16".
var inch_denominator: int = 16

static func parse_length(text: String) -> float      # -> metres, double; NAN on failure
func format_length(metres: float) -> String
func format_area(sq_metres: float) -> String
```

Accepted input (suffix optional; a bare number uses the active system):

| Typed | Meaning |
|---|---|
| `1500mm`, `1.5m`, `1.5` (metric) | metric lengths |
| `12"`, `6in`, `0.5ft`, `3yd` | imperial lengths |
| `12'6"`, `12-6`, `12 6` | feet and inches |
| `10'6 1/2"` | with a fraction |
| `@10<45` | relative polar: 10 m at 45° |
| `@5,-2` | relative cartesian |
| `100,250` | absolute cartesian |
| `1,250.5` | grouping separators stripped |

Two rules matter:

- **Ambiguity is resolved by the active system, never guessed.** `6` is six
  metres in metric, six feet in imperial.
- **Architectural fractions round *at display*, to `inch_denominator`**, which is
  how imperial drawings are dimensioned — but the stored double keeps full
  precision. Rounding here is a formatting choice, consistent with D3.

**Area parsing** should accept unit-qualified values (`45m2`, `450ft2`,
`5yd2`) because area is what users actually type for takeoff, and infer the
square unit from the linear one so `format_area` round-trips.

**An area is turned into words in exactly one place: `DraftUnits.format_area`.** Nothing else
may append a unit word to an area. A whole number stays whole and anything else carries one
decimal (`18` / `18.4`), because a bed of 12.4 m² written as `12` is a small lie on a drawing
dimensioned to the millimetre; a hectare takes over above a hectare, and an imperial document
reads `ft2` and `ac` and never `m2`. `DraftUnits.area_words(m2)` is the same words for a caller
with no document in hand, and `DraftUnits.is_whole` is the whole-or-decimal question on its own.

The list a UI shows must not become a second writer. `ZoneMap.areas_of(document, min_area)` is
the single **producer** of area rows, and every row it makes carries both the number and the
words - `{..., "area_m2": size, "area_text": area_words(document, size)}`. Every module with
an optional `units: DraftUnits = null` parameter funnels its **writing** through
`DraftUnits.area_words_in(m2, units)` and its **reading of a row** through
`DraftUnits.row_area_text(row, units)`; passing null gives the metre default, so a caller with
no document - a test, a hand-built row - keeps working and keeps saying metres. Both used to be
private copies, one in `Irrigation` and one in `Lighting`, until they were collapsed onto the one
pair: of two copies of a one-line rule it is always one of them that stops being true.
`ZoneMap.row_area_text(row)` and `ZoneMap.area_words(document, m2)` are thin wrappers over the
same two, kept because a page handed the drawing rather than the units has something these do
not. The module functions that state an area (`Irrigation.verdict_words`, `Irrigation.schedule`,
`Lighting.verdict_words`, `Lighting.schedule` and the row readers beside them) take that same
optional parameter.

**And a test says so rather than asking a reader to remember.** `tests/test_area_units_doctrine.gd`
walks every script under `res://scripts` and asserts that the only one which puts a space and an
area unit into a string literal is `DraftUnits`. That is a stronger statement than the doctrine, and
a cheaper one to keep: it does not care *how* a second writer would spell an area, only that a
person could read one out of a literal. The unit has to end at a boundary - `" has no area"`
begins with the letters of `ha` and is not a hectare, `"the can"` is not two acres - and a
literal with no space in front of the unit (`"m2": 1.0` in a parsing table, `"unit": "m2"` in
a record) is a name rather than a sentence and is left alone. `tests/` is deliberately not walked:
quoting the words is how a test checks the writer. The guard is also run against hand-written
samples of both the shape it catches and the shape it must not, because a guard that cannot fail
is not a guard.

A **reader that words what it read** obeys the same rule. `SurveyFile.read_text(text, options)`
takes `options["display_units"]`, the drawing's own `DraftUnits` - a different question from
`options["units"]`, which is what the file's numbers are *in* - and threads it into
`Survey.check_area` and `Survey.check_extent`, the two checks that say an area in words.
`SurveyFile.describe(parsed, units)` words the parcel's perimeter through
`DraftUnits.format_length` and its area through `format_area`, so the line carries its units: a
bare number does not, and a plat read onto an imperial drawing used to be told about 557.42 m2.
`DraftUnits.or_default(units)` resolves the metre default once, and `DraftUnits.length_words(m)`
is `format_length` for a caller with no document.

The units the read was given are remembered on the result (`parsed["display_units"]`), so the
report the panel shows and the description beside it are worded the same way, and
`Hud._on_survey_chosen` passes the drawing's units at the moment the file is read; they are not in
`to_dict`, because they are the drawing's units rather than the survey's. `SurveyFile.report_lines`
deliberately takes no units parameter: each check record carries the sentence it was made with, and
re-wording it there would make a second writer of the same sentence.

### Scale bar (both systems)

`HudOverlay` currently picks a round metre value from
`NICE_METRES = [1,2,5,10,20,50,100]` and draws it at the current zoom. Add a
parallel imperial progression in feet — `[1, 2, 5, 10, 20, 50]` ft — and select
the progression by the active system. The bar must still be *drawn* at its true
length for the current `pixels_per_metre`; only the chosen label changes.

### Precision display policy

Display precision is a **zoom-dependent** function, not a fixed setting: at
`plan_size = 100` m nobody needs micrometres, and printing six decimals makes
the readout unreadable. Derive it from metres-per-pixel:

```
decimals = clamp(ceil(log10(pixels_per_metre)) + 1, 0, 6)
```

The stored value never changes — this only affects `format_length`. Worth
stating because a "precision" setting that rounded storage would violate D3.

---

## 7. Parametric shapes

Each kind is defined by a short parameter vector (§4) and is edited through
**grips** that map one-to-one onto those parameters. This is what makes a shape
parametric rather than a bag of points: dragging the circumference of a `CIRCLE`
changes `r` and leaves `cx, cy` alone.

| Kind | Grips | Editing a grip changes |
|---|---|---|
| `LINE` | 2 endpoints, 1 midpoint | an endpoint |
| `CIRCLE` | centre, 4 circumference | `cx,cy` or `r` |
| `ARC` | centre, 2 endpoints, 1 mid-arc | `cx,cy`, or both angles, or `r` |
| `RECT` | 4 corners, 4 edge midpoints, 1 rotate | `w` or `h`, or `rotation` |
| `REGULAR_POLY` | centre, 1 radius, 1 rotate | `circumradius`, `rotation`, `n` |
| `POLYLINE` / `POLYGON` | every vertex, every segment midpoint | insert a vertex, move one |

Segment-midpoint grips on a polyline **insert** a vertex (the standard CAD
gesture), which keeps vertex counts honest instead of silently extending a
segment.

Rounding corners is a `RECT`/`POLYGON` operation producing an arc-carrying
polyline via bulges (§4) — the shape landscape drawings need most, since beds
and patios rarely have sharp corners.

Grip edits run through the same double-precision snap engine as new geometry, so
an edited vertex snaps to the same targets as a drawn one. That consistency is
easy to lose and expensive to retrofit.

---

## 8. Performance

| Concern | Approach |
|---|---|
| Snap query | uniform grid, O(entities near cursor), not O(n) |
| Draw | cull by viewport AABB; the current per-frame `queue_redraw` becomes repaint-on-`changed` |
| Large polylines | cull at segment level if a single entity exceeds the viewport by a large factor |
| 3D projection | one `MultiMesh` per layer (or per line style), rebuilt on `changed`; not one node per entity |
| Undo | capped snapshot stack, coalesced per gesture |
| Dynamic input | parse on change, ~free |

The change in `PlanCanvas` from repaint-every-frame to repaint-on-change is
necessary, not cosmetic: with props alone, repainting a few dozen shapes a frame
is free, but the same policy over a thousand entities with several thousand
segments is wasted work. Props keep their cheap path by having the view mark
itself dirty when a dragged node moves.

**Linework in 3D.** A bed border is a physical edge, so project drafting
linework into the 3D scene as thin ground-hugging strips at `floor_y` rather
than as 1-pixel lines: they then read correctly in the overhead 3D view *and*
underfoot in the ground view, which is the whole point of having a walk-around
mode. This is why `draft_view_3d.gd` exists rather than reusing `PlanCanvas`.

---

## 9. Testing

The existing suite (`tests/`, `extends Node`, `test_*` methods, 19 passing) sets
the pattern: pure functions get thorough tests, and nothing needs a live scene.
The kernel and units are ideal for that.

**Kernel** (`test_geom2d.gd`)
- segment×segment: crossing, touching at an endpoint, parallel, collinear
  overlap, zero-length segment.
- line×circle: two hits, tangent (one hit), miss.
- circle×circle: two hits, externally tangent, internally tangent, concentric
  (no solution), separate.
- arc membership: angles either side of the ±π wrap.
- nearest-point-on-arc inside and outside the sweep.

**Units** (`test_units.gd`)
- exact conversions both ways; `12'6"` → `3.81` → `12'6"` (idempotence).
- every accepted input form in the table above.
- architectural rounding to `inch_denominator`.
- ambiguity follows the active system.
- malformed input returns `NAN` rather than a silent zero.

**Snap** (`test_snap.gd`)
- priority: an endpoint 3 px away beats a midpoint 1 px away.
- aperture: a candidate at `aperture+1` px is rejected.
- hysteresis: a snap does not change while the cursor stays in the exit aperture.
- intersections are generated only between entities actually near the cursor.

**Document** (`test_draft_document.gd`)
- snapshot undo/redo restores byte-identical parameter arrays.
- a gesture pushes exactly one snapshot.
- associative dimensions follow a moved vertex.

**Properties** worth testing because they catch whole classes of bug:
- offsetting a convex polygon by `d` then `−d` returns the original within
  tolerance.
- any entity round-trips through save → load with no parameter change.
- snapping to a point then reading the coordinate returns that same point.

---

## 10. Suggested build order

Each step is independently useful and testable, and none requires the next.

1. **Units + kernel** — pure, no UI, fully tested. Highest value per unit of risk.
2. **Document + undo** with the existing props untouched.
3. **Snap engine + spatial grid**, verified against the existing pick behaviour.
4. **Select tool parity** — drafting entities become selectable in both views;
   the existing drag still works.
5. **Line, rectangle, polyline tools** with dynamic input and ortho.
6. **Arc, circle, regular polygon**, then bulges and corner rounding.
7. **Measurement and associative dimensions.**
8. **Offsets and area takeoff** — where the module starts paying for itself
   against the landscaping domain.
9. **Trim / extend / fillet.**

Milestones 1–4 keep the app shippable throughout; the drawing tools are additive
behind a tool mode.

---

## 11. Open questions

These change the design materially, so they are worth settling before step 3:

1. **Is this site-local or georeferenced?** If plans carry real survey
   coordinates, the georeference must be a separate transform (D1) and a site
   origin must be introduced from the start. Retrofitting it later means
   touching every coordinate in every saved plan.
2. **Do we need a general constraint solver?** This design stops at associative
   dimensions and parametric definitions. Tangency/concentricity constraints are
   a different order of project and should be decided explicitly, not drifted
   into.
3. **Is DXF or a survey format an interchange requirement?** Reading a surveyor's
   DXF is a common entry point for this kind of tool, and it would set the
   polyline/bulge representation in stone.
4. **Does drawing linework have to become physical in the 3D view?** If a bed
   border should raise a real edging mesh, `draft_view_3d.gd` needs a height and
   profile per layer, which is a small extra parameter set rather than a
   redesign — but better decided now than assumed.