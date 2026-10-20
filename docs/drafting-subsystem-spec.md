# Drafting subsystem specification

Normative specification for the drafting subsystem: precision tools, true-to-scale
drawings, line weights and styles, the layer system, and property survey import.

**Conformance language** — *MUST* is required, *SHOULD* is strong guidance,
*MAY* is optional.

**Relationship to `docs/drafting-module.md`.** That document designs the
foundation: the double-precision geometry kernel, the unit system, the snap
engine, the entity/document model, parametric shapes, undo, and the build order.
**This document does not restate it.** It specifies the four areas that document
left open or undefined — true-to-scale output, line weight/style, layers, and
survey import — and adds the tool-level requirements for precision drafting.

Where a rule here depends on a measurement, the value was measured against this
project's engine build (Godot 4.7.2, single precision) and is quoted inline.

---

## 1. Coordinate space, model space and paper space

This is the foundation the other four areas rest on, and the one place a CAD
program most often gets structurally wrong.

### 1.1 Three distinct spaces

| Space | Unit | Meaning |
|---|---|---|
| **Model** | metres, double | the site at full size; all geometry lives here |
| **Sheet (paper)** | millimetres | a physical page: A3, ARCH C, … |
| **Screen** | pixels | a window onto either of the above |

**REQ 1.1.1** All geometry MUST be stored in model space at full size. A 10 m wall
is 10 in the model, never 100 mm and never 0.1.

**REQ 1.1.2** A **plot scale** is a property of a sheet viewport, never of
geometry. An entity MUST NOT record the scale it was drawn at.

**REQ 1.1.3** A **view zoom** is a property of the screen camera and is unrelated
to plot scale. Conflating them is a defect. In this project the existing
`ViewController.plan_size` (metres visible across the viewport height) is a *view
zoom*. It MUST NOT be presented to the user as a drawing scale.

**REQ 1.1.4** Model ↔ sheet conversion is a single scalar, the scale ratio `S`,
where `1:S` means 1 mm on paper equals `S` mm in the model:

```
model_metres_per_sheet_mm = S / 1000
sheet_mm  = model_metres * 1000 / S
```

**REQ 1.1.5** Screen projection MUST be computed from the view camera and MUST
NOT route through sheet space. Paper-space rendering computes sheet mm first,
then maps sheet mm to pixels through the page fit.

### 1.2 Orientation and north

**REQ 1.2.1** Model X MUST be east, model −Z MUST be north, model +Z MUST be
south, model Y MUST be up. This matches the existing plan canvas, whose screen
+y is world +z, and the existing north arrow, which already points at world −Z.

**REQ 1.2.2** Every sheet MUST show a north arrow, because site plans are
routinely rotated for sheet fit and a rotated plan without a north arrow is
unreadable.

**REQ 1.2.3** Survey data arrives Y-up with north up. The import MUST apply
`x_model = x_src`, `z_model = −y_src`. Getting this sign wrong produces a
mirrored site that looks plausible; it MUST be covered by a test.

---

## 2. Precision drafting tools

The tool *set* is designed in `docs/drafting-module.md` §7. This section fixes
their required behaviour so they can be tested.

### 2.1 Tool inventory

| Tool | Input | Commits on | Notes |
|---|---|---|---|
| Select | click, window, crossing | — | window = left-to-right, only fully enclosed; crossing = right-to-left, any overlap |
| Line | 2 points | 2nd point | chains with Enter-repeat |
| Polyline | n points | Enter / Close | optional arc segments via bulge |
| Rectangle | 2 corners | 2nd corner | parametric; corner or centre, with a modifier |
| Regular polygon | centre + radius + n | radius | n settable before/after |
| Circle | centre + radius | radius | also 2-point and 3-point diameter forms |
| Arc | centre-start-end, 3-point, or start-end-radius | final point | stored centre-form |
| Offset | distance + side pick | side pick | delegates to `Geometry2D.offset_polygon` |
| Trim | cutting edge + target | 2nd click | keeps the clicked fragment |
| Extend | boundary + target | 2nd click | extends toward the boundary |
| Fillet | radius + two entities | 2nd entity | produces line-arc-line |
| Measure | 1–n points | Enter | distance, bearing, running total, area |
| Dimension | 2 points + offset | offset click | associative; linear, aligned, angular, radius |
| Text / Note | point | text entry | height in paper mm |
| Leader | arrow point + text | text entry | |

**REQ 2.1.1** Every drawing tool MUST be cancellable with `Escape` having changed
nothing. A tool MUST NOT mutate the document before its commit condition.

**REQ 2.1.2** Every tool MUST show a live preview between clicks, and the
preview MUST reflect current snap resolution.

**REQ 2.1.3** Tool activation MUST suspend the existing prop-drag interaction.
`Select` MUST restore today's behaviour exactly, so nothing regresses.

**REQ 2.1.4** Fillet and offset MUST be transactional: a failure (parallel lines,
degenerate result, self-intersecting offset) MUST leave the document untouched
and report why.

### 2.2 Coordinate entry grammar

**REQ 2.2.1** Every point input MUST accept typed coordinates as an alternative
to clicking, in the format specified in `docs/drafting-module.md` §6: absolute
`x,y`; relative `@dx,dy`; relative polar `@dist<angle`; and bare lengths where a
tool has an implied direction (a rectangle's second corner, a circle's radius).

**REQ 2.2.2** Typed entry MUST bypass snapping. It is already exact; snapping it
would be a data-integrity bug.

**REQ 2.2.3** Length input MUST accept both unit systems regardless of the active
display system, so a metric plan can take a dimension typed in inches.

### 2.3 Snapping requirements

The engine is specified in `docs/drafting-module.md` §5.1. Requirements:

**REQ 2.3.1** The aperture MUST be defined in pixels (default 12) and converted at
the current zoom, so tolerance is a property of the pointer.

**REQ 2.3.2** Object snaps MUST outrank grid and polar tracking. Grid and polar
MUST be modelled as constraints applied after target selection, not as targets in
the same priority list.

**REQ 2.3.3** Snap MUST have hysteresis: once locked, it MUST hold until the
cursor leaves an enlarged exit aperture (1.6×). Without this, one pixel of mouse
jitter changes the snap and the drawing becomes unstable.

**REQ 2.3.4** The active snap mode and its target MUST be visible at the cursor
and in the status bar at all times.

**REQ 2.3.5** Intersections MUST only be generated between entities that both
overlap the aperture. Generating them globally is O(n²) and unusable on a real
plan.

### 2.4 Exactness requirements

**REQ 2.4.1** Storing, entering or manipulating geometry MUST NOT round.
Formatting for display is a read-only operation (`docs/drafting-module.md` D3).

**REQ 2.4.2** Displayed precision MUST be derived from zoom, so it is useful at
every scale, and MUST NOT be written back.

**REQ 2.4.3** An entity that is snapped to a point and then read back MUST return
that same point exactly. This is a testable invariant and MUST be covered by a
test.

---

## 3. True-to-scale drawings

A drawing is **true to scale** when a stated ratio `1:S` holds between any
distance measured on the sheet and the corresponding real distance, within the
plottable tolerance.

**REQ 3.1** The tolerance for a true-to-scale deliverable MUST be **±0.2 mm on
paper**, which is the ISO/ANSI drafting tolerance for a plotted sheet. It MUST be
stated on the sheet, alongside a graphic scale bar.

### 3.1 Standard scales

**REQ 3.1.1** Imperial scales MUST be offered by their conventional names and MUST
be stored as the exact ratio they reduce to:

| Conventional | Ratio |
|---|---|
| 1/16 in = 1 ft | 1:192 |
| 1/8 in = 1 ft | 1:96 |
| 1/4 in = 1 ft | 1:48 |
| 1/2 in = 1 ft | 1:24 |
| 1 in = 1 ft | 1:12 |
| 1 in = 10 ft | 1:120 |
| 1 in = 20 ft | 1:240 |
| 1 in = 30 ft | 1:360 |
| 1 in = 40 ft | 1:480 |

**REQ 3.1.2** Metric scales MUST be drawn from the ladder
`1:20, 1:25, 1:50, 1:100, 1:125, 1:150, 1:200, 1:250, 1:500, 1:1000`.

**REQ 3.1.3** The application MUST offer a **suggested scale** for a given design
extent and sheet, computed as the smallest ladder value that fits:

```
need = max(design_width_m * 1000 / printable_w_mm,
           design_height_m * 1000 / printable_h_mm)
choose the smallest S >= need
```

Worked, verified against this project's own yard (28 × 20 m) on A3 landscape with
15 mm margins (390 × 267 mm printable): `need = 74.9`, so **1:100**, covering
39.0 × 26.7 m.

Coverage of common sheet/scale combinations, computed (landscape, 15 mm margins):

| Sheet | printable | 1:50 | 1:100 | 1:200 | 1:250 |
|---|---|---|---|---|---|
| ANSI B (11×17 in) | 402 × 249 mm | 20.1 × 12.4 m | 40.2 × 24.9 m | 80.4 × 49.8 m | 100.5 × 62.3 m |
| A3 | 390 × 267 mm | 19.5 × 13.4 m | 39.0 × 26.7 m | 78.0 × 53.4 m | 97.5 × 66.8 m |
| ARCH C (24×18 in) | 580 × 427 mm | 29.0 × 21.4 m | 58.0 × 42.7 m | 116.0 × 85.4 m | 145.0 × 106.8 m |
| A2 | 564 × 390 mm | 28.2 × 19.5 m | 56.4 × 39.0 m | 112.8 × 78.0 m | 141.0 × 97.5 m |
| ARCH D (36×24 in) | 884 × 580 mm | 44.2 × 29.0 m | 88.4 × 58.0 m | 176.8 × 116.0 m | 221.0 × 145.0 m |

### 3.2 Sheet composition

A sheet MUST carry: a border, a title block, one or more **scale viewports**, a
graphic **scale bar**, a **north arrow**, and a stated **scale ratio**.

**REQ 3.2.1** A viewport MUST record: its rectangle on the sheet (mm), its scale
`S`, the model point at its centre, a layer state, and a freeze flag. Two
viewports on one sheet MAY show the same model at different scales — this is the
standard "overall 1:200 + detail 1:50" sheet and MUST be supported.

**REQ 3.2.2** Sheet sizes MUST be offered in both series: ANSI A–E and ISO A4–A0,
landscape by default.

**REQ 3.2.3** A graphic scale bar MUST be plotted on every sheet. This is not
decoration: it is the only way a recipient can detect that a PDF has been printed
with "fit to page" and is therefore no longer at the stated scale.

### 3.3 Exact output

**REQ 3.3.1** True-to-scale output MUST be **vector**, as PDF or SVG. A raster
image has no intrinsic physical size, so a PNG cannot itself be true to scale.
Raster export MAY be offered for reference, and MUST then carry the DPI and the
graphic scale bar, and MUST be labelled as reference-only in the UI.

**REQ 3.3.2** PDF output MUST set the page MediaBox from the sheet size so that
paper millimetres are physical millimetres. The conversion is exact and MUST be
applied unrounded until final emission:

```
1 pt = 1/72 in = 25.4/72 mm = 0.352777... mm
1 mm = 72/25.4 pt = 2.834645669... pt
sheet = 420 x 297 mm  ->  1190.551 x 841.890 pt   (A3)
10.000 m at 1:100 = 100 mm -> 283.465 pt
0.35 mm lineweight -> 0.992 pt
```

**REQ 3.3.3** "Fit to page", "scale to fit" and similar print options MUST be
documented as destroying the scale. The scale bar exists to make that detectable.

**REQ 3.3.4** Godot core provides no vector document writer. The sheet exporter
is therefore a **component of this subsystem**: a minimal writer covering
polylines, filled polygons, clipped hatch lines, and text. It MUST be
deterministic and MUST be covered by an output-geometry test. Third-party
exporters MAY be evaluated, but the subsystem MUST NOT depend on the availability
of one.

**REQ 3.3.5** Text height MUST be specified in paper millimetres (ISO 3098 series
`1.8, 2.5, 3.5, 5.0, 7.0`, default 2.5), so it is legible at every scale.
Model-space text size is `height_mm * S / 1000`.

### 3.4 On-screen scale fidelity

**REQ 3.4.1** When a viewport is being edited or previewed, the screen MUST
present the sheet at a consistent magnification, and the scale bar MUST be
correct for the current `pixels_per_metre`.

**REQ 3.4.2** Model-space editing MUST show line weights and text at their
plotted *equivalent*, using the equation in §4.2, so the drawing reads on screen
the way it will plot.

---

## 4. Line weights, hierarchy and styles

Line weight is a **plotted property**, not a model property. A 0.35 mm line is
0.35 mm on every sheet at every scale; what it covers in the model varies with
scale. This is why weight is authored in paper millimetres.

### 4.1 Weight series

**REQ 4.1.1** Weights MUST be chosen from the ISO 128 series, which doubles every
three steps (ratio `√2`):

`0.13, 0.18, 0.25, 0.35, 0.50, 0.70, 1.00, 1.40, 2.00` mm

**REQ 4.1.2** A style MUST carry: `plot_weight_mm`, `linetype`, `plot_colour`,
and `screen_colour`. Screen colour and plot appearance MUST be independently
settable — a plan is authored in colour and frequently plotted in grey.

### 4.2 Weight → screen and model

**REQ 4.2.1** The single equation governing weight at every scale:

```
screen_px   = plot_weight_mm * (S / 1000) * pixels_per_metre
model_width = plot_weight_mm * S / 1000        # metres
```

At true sheet zoom this MUST reduce to `plot_weight_mm * pixels_per_paper_mm`.
Verified on this build at 1:100 on A3 viewed 900 px tall (33.71 px/m), all
weights matching the paper-derived value exactly:

| Weight | via formula | via paper |
|---|---|---|
| 0.13 mm | 0.438 px | 0.438 px |
| 0.25 mm | 0.843 px | 0.843 px |
| 0.35 mm | 1.18 px | 1.18 px |
| 0.50 mm | 1.685 px | 1.685 px |
| 0.70 mm | 2.36 px | 2.36 px |

**REQ 4.2.2** Screen width MUST be clamped to a minimum of 1 px so hairlines
remain visible while drafting.

**REQ 4.2.3** A "display lineweights" toggle MUST exist. Off renders everything at
1 px, which is what a designer wants when tracing dense detail.

**REQ 4.2.4** Line **joins** and **caps** MUST be correct at weight. Godot's
`draw_polyline` has no join parameter, so above a threshold (about 1.5 px) a
stroke MUST be converted to a filled outline polygon via `Geometry2D.offset_polyline`
(confirmed present in this build), which also gives correct joins:
`JOIN_ROUND` for organic bed and contour outlines, `JOIN_MITER` for paving and
walls.

### 4.3 Dash patterns

**REQ 4.3.1** Patterns MUST be authored in **paper millimetres** and scaled by the
same law as weight:

```
model_pattern = paper_pattern_mm * S / 1000
```

**REQ 4.3.2** Patterns MUST be anchored to the **entity's own geometry**, not to
screen space. A dash pattern computed in screen space shimmers and crawls as the
view pans, which reads as a rendering fault. This requirement exists because the
naive implementation gets it wrong.

**REQ 4.3.3** The defined linetypes:

| Name | Pattern (mm) |
|---|---|
| Continuous | — |
| Dashed | 6, 2 |
| Hidden | 3, 1.5 |
| Centrelines | 12, 2, 2, 2 |
| Dotted | 0.25, 1.5 |
| Phantom | 12, 2, 4, 2 |

**REQ 4.3.4** Dash phase MUST be preserved across an entity's segments so a
dashed polyline does not restart its pattern at every vertex.

### 4.4 Weight hierarchy

The hierarchy is the drafting grammar: weight encodes importance, so the plan
reads correctly at a glance and photographs/plots legibly. The default assignment
MUST follow this table.

| Class of linework | Weight | Rationale |
|---|---|---|
| Sheet border and title block | 0.70 mm | defines the sheet; heaviest |
| Structures, both new and existing, cut in plan | 0.50 mm | the mass of the drawing |
| Retaining walls, steps, new hardscape edges | 0.50 mm | physical, load-bearing edges |
| Property lines | 0.35 mm | legally authoritative |
| Planting bed edges and edging | 0.35 mm | the primary landscape move |
| Existing hardscape, contours | 0.25 mm | context, one step back |
| Turf and seeding areas | 0.25 mm | soft boundary |
| Easements and setbacks | 0.18 mm | dashed; advisory |
| Dimensions, notes, leaders, spot elevations | 0.18 mm | annotation layer |
| Plant symbols and labels | 0.13 mm | dense detail, lightest plotted |
| Hatch and textures | 0.13 mm | background texture |
| Guides, construction lines, underlays | 0.13 mm, non-plotting | not part of the drawing |

**REQ 4.4.1** The hierarchy MUST be enforced by layer defaults (§5), with
per-entity override permitted. A user MUST NOT have to set weight per entity to
get a conventional drawing.

**REQ 4.4.2** Adjacent classes MUST NOT share a weight if that forces a user to
guess. The table above uses five distinct plotted weights across twelve classes.

### 4.5 Plot style table

**REQ 4.5.1** A plot style table MUST be supported, mapping layer colour index
(`1 red, 2 yellow, 3 green, 4 cyan, 5 blue, 6 magenta, 7 white`) to a plotted
colour and weight. Colour-indexed pen tables are how landscape CAD drawings have
conventionally been produced, and a practice adopting this tool MUST be able to
keep its existing pen assignments.

**REQ 4.5.2** A style table MUST be attachable per sheet, and its effect MUST be
previewable before plotting.

### 4.6 Hatch and texture fills

**REQ 4.6.1** Region fills MUST support: solid, line hatch (parallel lines at a
chosen angle and spacing, paper mm), crosshatch, and symbol fill (point symbols on
a clipped grid).

**REQ 4.6.2** Hatch MUST be generated by **scanline clipping**, which is exact and
simple: rotate the region into pattern space so pattern lines are horizontal at
`y = k * spacing`; for each scanline compute edge intersections, sort by x, and
pair them under the even-odd rule; draw the resulting segments. Cost is
`O(scanlines × edges)`.

**REQ 4.6.3** Symbol fill MUST place symbols on the pattern grid and reject those
outside the region using `Geometry2D.is_point_in_polygon` (confirmed present).

**REQ 4.6.4** Hatch MUST be clipped to the region including holes. `Geometry2D`
polygon booleans handle the region; the scanline pass handles the pairing. A
region with holes MUST NOT fill the holes.

---

## 5. Layer system with preset conventions

### 5.1 Preset layer set

**REQ 5.1.1** A new plan MUST be created with this layer set. Layer names are
conventional and the numeric prefix doubles as **draw order and plotting band** —
lower sorts underneath and plots first.

| Prefix | Layer | Purpose | Colour | Weight | Linetype | Plots |
|---|---|---|---|---|---|---|
| 010 | `010-SURVEY-PROP` | property lines | blue | 0.35 | Continuous | yes |
| 011 | `011-SURVEY-ANNO` | bearings, distances, stated area | blue | 0.18 | Continuous | yes |
| 020 | `020-SETBACK-EASE` | setbacks, easements, zoning | magenta | 0.18 | Dashed | yes |
| 100 | `100-EXIST-STRUCT` | existing buildings | cyan | 0.50 | Continuous | yes |
| 101 | `101-EXIST-HARD` | existing paving, walls, drives | cyan | 0.25 | Continuous | yes |
| 110 | `110-EXIST-PLANT` | existing plant material | green | 0.13 | Continuous | yes |
| 200 | `200-GRADE-CONT` | contours | yellow | 0.25 | Continuous | yes |
| 201 | `201-GRADE-SPOT` | spot elevations | yellow | 0.18 | Continuous | yes |
| 300 | `300-NEW-HARD` | new paving, walls, steps | red | 0.50 | Continuous | yes |
| 301 | `301-NEW-STRUCT` | deck, pergola, structure | red | 0.50 | Continuous | yes |
| 400 | `400-NEW-BED` | bed outlines and edging | red | 0.35 | Continuous | yes |
| 401 | `401-NEW-PLANT` | plant symbols and labels | green | 0.13 | Continuous | yes |
| 402 | `402-NEW-TURF` | lawn and seeding areas | green | 0.25 | Continuous | yes |
| 500 | `500-IRRIGATION` | heads, zones, pipe runs | cyan | 0.18 | Continuous | yes |
| 501 | `501-LIGHTING` | fixtures, cable runs | yellow | 0.18 | Continuous | yes |
| 600 | `600-HATCH` | paving, mulch, grading patterns | grey | 0.13 | Continuous | yes |
| 700 | `700-DIMENSION` | dimensions | magenta | 0.18 | Continuous | yes |
| 710 | `710-TEXT` | notes and labels | white | 0.18 | Continuous | yes |
| 720 | `720-CALLOUT` | leaders, keys, plant tags | white | 0.18 | Continuous | yes |
| 900 | `900-SHEET-BORDER` | border and title block | white | 0.70 | Continuous | yes |
| 901 | `901-SHEET-VPORT` | viewport frames | white | 0.13 | Continuous | yes |
| 950 | `950-UNDERLAY` | imported survey raster | grey | n/a | Continuous | **no** |
| 960 | `960-GUIDES` | construction lines, guides | grey | 0.13 | Dotted | **no** |

**REQ 5.1.2** Sorting MUST be by prefix first, then by creation order within a
layer, then by any explicit per-entity override. This gives the conventional
"big things underneath" stacking without a per-entity z value.

**REQ 5.1.3** The `950-UNDERLAY` and `960-GUIDES` layers MUST default to
non-plotting, locked, and, for the underlay, faded (default 40% opacity). Imported
survey imagery is a tracing aid, not part of the drawing.

### 5.2 Layer properties

**REQ 5.2.1** Each layer MUST carry: `name`, `purpose` (human text), `screen_colour`,
`plot_colour`, `plot_weight_mm`, `linetype`, `plots` (bool), `visible` (bool),
`locked` (bool), `frozen_in_sheets` (bool set), and `default_style` for its entity
kinds.

**REQ 5.2.2** Locked layers MUST be visible but not selectable. A locked layer that
can still be selected is a data-loss hazard.

**REQ 5.2.3** Hiding a layer MUST hide its content consistently in **all** views:
the flat plan, the 3D overhead, and the ground view. A plant layer hidden in plan
but still rendered in 3D is a defect. This is a direct consequence of the
one-model architecture and MUST be implemented through the single layer state
rather than per-view visibility.

**REQ 5.2.4** Deletion of a layer in use MUST require confirmation and MUST offer
to migrate or delete its entities. Silent entity loss is unacceptable.

### 5.3 Layer states

**REQ 5.3.1** A **layer state** MUST be a named, saved set of visible/frozen flags.
Preset states MUST ship:

| State | Shows |
|---|---|
| Base plan | survey, existing, grading |
| Layout / hardscape | base + new hardscape and structures |
| Planting plan | base + beds, plants, turf |
| Irrigation plan | base + irrigation |
| Presentation | everything plotting, weights emphasised |
| Working | everything including guides and underlay |

**REQ 5.3.2** A layer state MUST be attachable per sheet viewport, so two
viewports on one sheet can show different states.

### 5.4 Integration with the existing project

**REQ 5.4.1** The existing `PlanStyle.COLOURS` table maps 3D material resource
paths to plan colours. Under this specification it is superseded: the mapping
becomes *material → layer*, and colour/weight/linetype come from the layer. The
existing table MUST be migrated rather than duplicated, so there is still exactly
one place a colour is decided.

**REQ 5.4.2** Placed props (`Yard/Plants/*`) MUST be assigned to
`401-NEW-PLANT` by default, and MUST inherit its visibility, so the layer system
governs them like any other content.

---

## 6. Property survey import with automatic scale alignment

This is the subsystem's highest-value and highest-risk feature. It is specified
conservatively: it must be *verifiable*, and it must refuse to guess.

### 6.1 Accepted sources

| Source | Format | Geometry available | Alignment needed |
|---|---|---|---|
| Scanned plat / survey PDF | PNG, JPG, TIFF, PDF page | raster only | scale + rotation + position |
| Surveyor's CAD file | DXF (ASCII) | vector, units usually declared | position, usually rotation |
| Metes and bounds | text / CSV of bearings and distances | **exact** by definition | none; units only |
| Coordinate point list | CSV | points | units and origin |
| Existing plan | this app's document format | exact | none |

**REQ 6.1.1** Each source MUST have an adapter implementing a common interface
returning either a raster underlay plus a suggested transform, or exact model
geometry plus a georeference. Adapters MUST be independently testable.

### 6.2 Import pipeline

```
  select source
      -> detect format and, where possible, units
      -> [raster] establish source scale  (6.3)
      -> [raster] establish rotation and position (6.4)
      -> [vector] establish units, then register (6.4)
      -> rebase to the site origin           (6.6)
      -> run validation checks               (6.5)
      -> show the validation report; require acceptance
      -> map source layers to the preset layer set (5.1)
      -> place underlay on 950-UNDERLAY (non-plotting) and land traced/imported
         geometry on 010/011/020
```

**REQ 6.2.1** The pipeline MUST be interactive and MUST NOT commit until the
validation report has been shown and accepted.

**REQ 6.2.2** Every step MUST be reversible with one undo, and the import MUST
record its provenance (source path, file hash, chosen scale, alignment points,
residuals, checks) so it can be re-run or audited later.

### 6.3 Establishing scale for a raster

In strictly decreasing order of reliability:

| Method | Reliability | Rule |
|---|---|---|
| User states the scale | high | 1:100, 1/4"=1'-0" → `S` directly |
| **Known distance calibration** | **highest for a raster** | click the two ends of a dimension whose real length is known (`50.00'` frontage); `scale = real_length / measured_length` |
| Scale bar calibration | high | same rule, using the bar's ends |
| PDF page geometry | medium | known page size + stated scale gives `model_metres_per_px` from the raster DPI |
| OCR of a printed scale | low | MAY be offered as a hint; MUST NOT be applied without confirmation |

**REQ 6.3.1** Known-distance calibration MUST be the default offered method.
Scale bars and stated ratios are frequently stale on reproduced plats, whereas a
frontage dimension is a legal statement about that drawing.

**REQ 6.3.2** The importer MUST show the derived scale in both unit systems and
as a ratio, so the user can sanity-check it against the title block.

**REQ 6.3.3** Where a raster was scanned with non-square pixel pitch (for example
300 × 600 dpi), the importer MUST correct by the DPI ratio *before* alignment.
This is a scan-artefact correction and MUST be reported, never silently applied.

### 6.4 Alignment: least-squares similarity

**REQ 6.4.1** Alignment MUST use a **similarity transform** (uniform scale,
rotation, translation). It MUST NOT use a general affine or projective fit.
Rationale: a similarity preserves shape. An affine fit with few points can shear
and stretch a survey to "fit" and produce a plan that looks aligned while every
area and dimension in it is wrong. Scale alignment must never change the shape of
a survey.

**REQ 6.4.2** The fit MUST be solved in closed form by least squares over `N ≥ 2`
correspondences, using centroids and the `a, b` formulation:

```
u_i = src_i - centroid(src)          v_i = dst_i - centroid(dst)

a = Σ(u.x*v.x + u.y*v.y) / Σ|u|²
b = Σ(u.x*v.y - u.y*v.x) / Σ|u|²
scale   = sqrt(a² + b²)
rotation = atan2(b, a)
translation = centroid(dst) - R(rotation) * scale * centroid(src)

residual_rms = sqrt( mean( |pred_i - dst_i|² ) )
```

**Verified on this build.** Given a synthetic source with a true scale of
0.024 m/px and a true rotation of 30°, the fit recovered:

```
truth scale 0.024   recovered 0.024
truth angle 30.0°   recovered 30.0°
RMS residual 0.000000551 m
```

**REQ 6.4.3** Two correspondences determine the transform exactly; three or more
MUST be used when available and MUST be least-squares, so that a single
misclicked point degrades the fit rather than breaking it.

**REQ 6.4.4** The **RMS residual MUST be reported in model units** and shown in
the validation report. It is the user's only measure of fit quality.

**REQ 6.4.5** A fit whose residual exceeds a tolerance (default 50 mm) MUST
require explicit override to apply, and the override MUST be recorded in the
import provenance. **Verified that this rule bites:** taking the exact fit above
and shearing two of the three target points by 0.8 m raises the residual to
`0.181164 m` — a value a similarity fit cannot reduce, which is exactly the
signal that the source is distorted and must not be silently absorbed.

**REQ 6.4.6** Rotation MUST also be settable directly, for two cases: a raster
whose north is up but whose model is rotated, and a **"rotate to true north"**
operation using the survey's north arrow or a stated bearing reference.

**REQ 6.4.7** Alignment points MUST be snappable using the §2.3 engine, so a user
can click a dimension's endpoints exactly rather than approximately.

### 6.5 Validation and acceptance checks

These checks are what make the import trustworthy. All MUST run automatically and
all results MUST be shown before the user accepts.

| Check | Rule | Failure action |
|---|---|---|
| Transform residual | RMS from 6.4.2 | warn above 50 mm; require override |
| **Traverse closure** | for metes and bounds, the traverse MUST return to its start | report misclosure distance and ratio; warn past 1:10,000 |
| **Area cross-check** | computed polygon area vs. the area stated on the plat | warn past 0.5% difference |
| Dimension cross-check | a stated frontage vs. the model distance between the aligned points | warn past 0.5% |
| Aspect sanity | hinted scale vs. calibrated scale | warn past 5% |
| Self-intersection | the property polygon MUST be simple | block; a self-intersecting parcel is a tracing error |
| Extent sanity | the parcel MUST be plausible (> 20 m², < 100 ha) | warn |

**REQ 6.5.1** For metes and bounds, misclosure MUST be computed and reported
before any adjustment is offered.

**REQ 6.5.2** The **compass (Bowditch) rule** MUST be offered as an optional
adjustment, distributing the closure error in proportion to leg length:

```
e_N, e_E = misclosure components
per leg i:  dN_i -= e_N * len_i / perimeter
            dE_i -= e_E * len_i / perimeter
```

It MUST default to **off**. Adjusting a survey is a professional decision, and
the raw traverse MUST be preserved in the provenance either way.

**REQ 6.5.3** The area cross-check MUST be automated because it is the strongest
available independent verification of scale. Verified end to end on a synthetic
US plat (50.00 ft × 120.00 ft):

```
traverse closes at (0, 0) ft,  misclosure 0.0 ft
perimeter 340.00 ft = 103.632 m
area computed 6000.0 sq ft, stated 6000.0 sq ft, difference 0.0%
area = 557.4182 m2 = 0.137741 acres     (1 acre = 4046.8564224 m2, exact)
```

### 6.6 Georeference and the site origin

**REQ 6.6.1** Absolute survey coordinates (northing/easting) MUST NOT be used as
model coordinates. The import MUST subtract a site origin and store the
georeference separately.

This is not a preference. Measured on this build, a float32 coordinate step is:

| Magnitude | float32 step |
|---|---|
| 100 m | 7.6 µm |
| 10 km | 0.98 mm |
| 500,000 m (UTM easting) | 31 mm |
| 5,000,000 m (UTM northing) | **0.5 m** |

A site plan held in absolute UTM coordinates therefore quantises at half a metre
before any drafting happens. Rebased to a site origin, the same plan resolves to
about a micrometre.

**REQ 6.6.2** The georeference record MUST carry: coordinate reference system,
origin easting and northing, origin as model XZ, rotation to true north, and the
linear unit of the source.

**REQ 6.6.3** Unit conversion on import MUST use exact constants, and MUST offer
the **US survey foot** (`1200/3937` m, exact) as distinct from the international
foot (`0.3048` m, exact). These differ by 2.0 ppm — 0.61 mm over 1 km — which is
immaterial for planting layout but material for legal boundary work. US plats
drawn before 2023 are commonly in US survey feet.

### 6.7 Vector import (DXF)

**REQ 6.7.1** Phase 1 MUST support ASCII DXF for `LINE`, `LWPOLYLINE`, `POLYLINE`,
`ARC`, `CIRCLE`, `TEXT`, and layer table records. Blocks/`INSERT` MAY follow.

**REQ 6.7.2** `$INSUNITS` MUST be read when present and used to convert to metres
(`1`=inches, `2`=feet, `4`=mm, `6`=m, `0`=unitless). When it is `0`, the user MUST
be asked rather than a default assumed.

**REQ 6.7.3** DXF Y is up (north); the model is Z-south. The importer MUST apply
`z = -y` per REQ 1.2.3, and this MUST be covered by a test, because a mirrored
site is visually plausible and wrong.

**REQ 6.7.4** Layers MUST be mapped to the preset layer set through an explicit,
editable mapping table with a sensible default (`PROPERTY`/`BOUNDARY` →
`010-SURVEY-PROP`; `EASEMENT` → `020-SETBACK-EASE`; anything unrecognised →
`010-SURVEY-PROP` with a warning, never to a plotting layer by accident).

**REQ 6.7.5** Vector imports bypass scale estimation entirely — the geometry is
already at scale — but STILL require registration (rotation and position) and
georeferencing, and MUST run the validation checks in 6.5.

### 6.8 Tracing stance

**REQ 6.8.1** Automatic raster vectorisation MUST NOT be offered as a
scale-alignment feature. It is unreliable on scanned plats and its failures are
subtle (a wall picked up as one line, a dimension string traced as geometry).

**REQ 6.8.2** Instead, **semi-automatic tracing** MUST be provided: the user
clicks along a boundary, the snap engine locks onto the raster's line work where
it can, and a collinearity filter fits the clicked run to the smallest segment
set that stays within tolerance (default 10 mm). This gives the speed of
tracing with exact, rattachable geometry as the result.

**REQ 6.8.3** Traced geometry MUST land as real entities on the `010`/`011`/`020`
layers; the raster remains only as a non-plotting underlay.

---

## 7. Data structures added by this specification

```gdscript
class_name LineStyle extends RefCounted
var plot_weight_mm: float = 0.25
var linetype: StringName = &"continuous"
var plot_colour: Color = Color.WHITE
var screen_colour: Color = Color.WHITE
var dash_phase_anchored_to_geometry: bool = true   # REQ 4.3.2

class_name Layer extends RefCounted
var name: String                      # "400-NEW-BED"
var purpose: String
var screen_colour: Color
var plot_colour: Color
var plot_weight_mm: float
var linetype: StringName
var plots: bool = true
var visible: bool = true
var locked: bool = false
var default_style_by_kind: Dictionary  # DraftEntity.Kind -> LineStyle

class_name LayerState extends RefCounted
var name: String
var visible: PackedStringArray
var frozen: PackedStringArray

class_name SheetViewport extends RefCounted
var rect_mm: Rect2          # on the sheet
var scale: float            # S; 0.1 means 1:10
var centre_model: Vector2   # model XZ at viewport centre
var layer_state: StringName
var frozen: bool = false

class_name Sheet extends RefCounted
var size_mm: Vector2
var margins_mm: float = 15.0
var title_block: Dictionary
var viewports: Array[SheetViewport] = []
var scale_bar: bool = true
var north_arrow: bool = true
var plot_style_table: StringName

class_name Georeference extends RefCounted
var crs: String                   # e.g. "NAD83 / UTM 17N", or "" if local
var origin_easting_m: float = 0.0
var origin_northing_m: float = 0.0
var origin_model_xz: Vector2 = Vector2.ZERO
var rotation_to_true_north_rad: float = 0.0
var source_linear_unit: StringName = &"metre"   # "metre" | "intl_foot" | "us_survey_foot"

class_name SurveyImport extends RefCounted
var source_path: String
var source_hash: String
var format: StringName
var scale_method: StringName       # "stated" | "known_distance" | "scale_bar" | "page"
var scale_ratio: float
var correspondences: Array[Vector2]  # src px / model pairs
var fit_a: float
var fit_b: float
var fit_rms_m: float
var residual_override: bool = false
var checks: Array[Dictionary]      # {name, value, tolerance, passed, message}
var raw_metes: PackedFloat64Array  # preserved even if adjusted (REQ 6.5.2)
var georeference: Georeference

class_name Underlay extends RefCounted
var image_path: String
var transform: Array[float]        # 6 doubles: similarity to model XZ
var opacity: float = 0.4
var locked: bool = true
var plots: bool = false            # REQ 5.1.3
```

**REQ 7.1** `SurveyImport` MUST be persisted into the document so an import can be
re-run or audited. Undo of an import MUST remove the underlay, the traced
geometry and the record together.

---

## 8. UI surfaces

| Surface | Contents |
|---|---|
| Layer manager | the preset set; colour, weight, linetype, visible, lock, plots; layer state sets; per-column sorting |
| Style editor | weight series, linetype patterns, plot style table, textual/plot preview |
| Properties palette | selected entity: layer, style override, geometry parameters as editable fields |
| Sheet setup | size, orientation, margins, title block fields, viewports, scale per viewport, scale bar and north arrow |
| Print / plot | sheet selection, plot style table, output format, exact-scale confirmation, warning about fit-to-page |
| Import wizard | source → units → scale method → alignment points → **validation report** → layer mapping → commit |
| Status bar | active snap and its target, active layer, current drawn scale, display-lineweights toggle, units |
| Menu bar | File: plot a sheet, render a proposal still, sheet size, plot scale, quit. Edit: undo, redo, drop the last point, cancel the shape, dimension standard. View: the three views, fit, painted plan, control hints. Draft: the nine tools and the shape commands. Present: the client presentation, quality, framing, still size, save the site. Help: the key reference. Every entry that stands for a key prints that key, and a menu whose subject is absent from the scene is not offered at all. |

**REQ 8.1** The status bar MUST show the active snap mode and the snapped
coordinate numerically, so a user can draft precisely without a permanent
coordinate readout.

**REQ 8.2** The import wizard MUST present the validation report as a table of
pass/warn/fail with the measured value and the tolerance, and MUST NOT allow
commit past a `fail` without an explicit override.

**REQ 8.3** The menu bar MUST be built from the same tables the legend and the
palette are built from, so that a drawing tool cannot be in one of them and
missing from another. Every entry that stands for a key MUST name the key the
input map really binds, and every entry MUST name a method the HUD really has.
Both are checked by tests, because a menu entry that does nothing is
indistinguishable, until it is chosen, from one that does.

**REQ 8.4** The menu bar MUST NOT bind menu accelerators. An accelerator is a
second binding: it fires *as well as* the input action, so a key advertised in a
menu would run its command twice. The keys go into the entry labels instead, where
they are read and not obeyed. The bar MUST be focus-free, and choosing an entry
MUST release the keyboard again, so that the drawing keys still work after the
menu has been used - a menu that quietly takes Tab and Enter away from the tools
is worse than no menu.

---

## 9. Acceptance criteria

Each is testable and each maps to a requirement above.

| ID | Criterion |
|---|---|
| AC-1 | A 10.000 m dimension drawn at 1:100 measures 100.0 mm ±0.2 mm on the exported PDF. |
| AC-2 | A 0.35 mm line plotted at 1:100 measures 0.35 mm ±0.02 mm on paper. |
| AC-3 | A sheet at 1:100 on A3 fits a 39 × 26 m extent inside the border with a 15 mm margin. |
| AC-4 | The suggested scale for a 28 × 20 m design on A3 is 1:100. |
| AC-5 | Screen line weight equals `plot_mm × S/1000 × pixels_per_metre` for all weights, and equals the paper-derived width at sheet zoom. |
| AC-6 | A dash pattern does not change position or phase when the view is panned. |
| AC-7 | Hiding `401-NEW-PLANT` removes plants from the 2D plan, the 3D overhead and the ground view. |
| AC-8 | `950-UNDERLAY` and `960-GUIDES` do not appear in plotted output. |
| AC-9 | An imported survey with a stated 50.00 ft frontage yields a model distance of 15.240 m ±0.005 m. |
| AC-10 | A similarity fit to 3 corresponding points recovers scale and rotation exactly and reports RMS residual. |
| AC-11 | A source distorted by a shear produces a residual > 50 mm and the import requires an explicit override. |
| AC-12 | A metes-and-bounds traverse reports misclosure distance and ratio before any adjustment. |
| AC-13 | A 50.00 ft × 120.00 ft lot computes 557.42 m² and matches a stated area within 0.5%. |
| AC-14 | A DXF import maps Y-up to Z-south, verified by a mirrored-fixture test. |
| AC-15 | A DXF with `$INSUNITS = 2` (feet) produces model geometry in metres with the correct factor. |
| AC-16 | An import rebased to a site origin resolves coordinates to better than 0.1 mm at 100 m from origin. |
| AC-17 | Every entity in a new document belongs to a layer from the preset set. |
| AC-18 | A locked layer is visible but not selectable. |
| AC-19 | `Escape` during any tool leaves the document byte-identical. |
| AC-20 | A hatch clipped to a region with a hole leaves the hole unfilled. |

---

## 10. Phasing

| Phase | Deliverable | Depends on |
|---|---|---|
| 1 | Units, geometry kernel, document, undo | `docs/drafting-module.md` steps 1–2 |
| 2 | Layer system and preset conventions; layer states; visibility across all views | phase 1 |
| 3 | Line styles: weights, linetypes, screen/plot distinction, hierarchy defaults | phase 2 |
| 4 | Snap engine and §2 tool requirements | phase 1 |
| 5 | Sheet, viewports, scale, scale bar, north arrow, on-screen fidelity | phases 2–3 |
| 6 | Vector sheet exporter (PDF/SVG); exact-scale verification harness | phase 5 |
| 7 | Hatch and symbol fills | phases 3, 5 |
| 8 | Survey import: metes and bounds and CSV first (exact, no alignment) | phases 1, 2 |
| 9 | Survey import: DXF vector, units, layer mapping, georeference, origin rebasing | phase 8 |
| 10 | Survey import: raster calibration, similarity alignment, validation report, semi-automatic tracing | phases 4, 9 |
| 11 | Plot style tables | phases 3, 6 |

Phases 8–10 are ordered deliberately: the two import paths that are already exact
and need no alignment ship first and exercise the validation machinery, so by the
time raster alignment arrives the checks that catch a bad fit are already proven.

---

## 11. Open questions

Four decisions change this specification structurally rather than cosmetically.

1. **Is a plot style table (colour-indexed pen mapping) genuinely required, or is
   per-layer weight sufficient?** It is specified because practices adopting a CAD
   tool usually have existing pen standards, but it is real work and can be
   deferred if no such practice is a target user.

2. **In which unit system are sheets produced by default?** A US-market landscape
   practice plots in feet with `1/4" = 1'-0"` and tenths or inches; an
   international one plots in metric. The internal model stays metric either way,
   but the *sheet* default changes the title block, the scale ladder shown first,
   and the dimension defaults.

3. **How much of the survey import must be automatic?** This specification makes
   calibration explicit and interactive because it is verifiable. Full
   automation — reading a stated ratio and a dimension string from the sheet and
   aligning unattended — is possible but its failures are silent, and silent scale
   errors in a landscape plan are expensive. If unattended import is a hard
   requirement, the validation checks become mandatory gates rather than
   advisories, and that should be decided up front.

4. **Is the exported sheet a deliverable the business depends on?** If PDF output
   is customer-facing, the exporter needs its own conformance suite (AC-1, AC-2)
   and should be built early. If output is only ever on-screen or raster, phases 5
   and 6 can be much lighter and the true-to-scale requirement relaxes to the
   scale bar alone.