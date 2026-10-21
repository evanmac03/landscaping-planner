# Workflow and efficiency

An audit of eight requested capabilities against what is actually in this repository: what exists,
which file it is in, what holds it down, and what is genuinely missing. Written so that a
"already built" verdict can be checked rather than trusted - every claim names a script and, where
there is one, the test that would fail if it stopped being true.

All eight are now built or answered: sections 1 to 5 are in the drawing, section 6 is presence on
demand, section 7's business chain runs phases 0 to 11, and section 8 is the box that reaches
all of it. Section 9 names what is left, and the order.

## 0. The shape everything hangs off

Every capability in the list is a way of **getting at the drawing**, so the drawing is the thing to
understand first:

    DraftDocument            the design. Entities, layers, units, the site, dimension styles.
    DraftSpatialGrid         what is near the cursor, without walking the drawing
    SnapEngine               the cursor's position, decided by priority rather than by distance
    DraftTool                nine pure state machines: picks in, an entity out
    DraftRender              the one renderer the plan, the sheet and the 3D all use
    PlanCanvas / ViewController   one world, two projections
    PlantCatalogue           a JSON list of species, and the link from a species to a prop
    CostBook                 a JSON list of priced items and kits
    PresentationDirector     the camera, the sun and the still

A plan is small - a few thousand vertices is tens of kilobytes - so this project spends
memory to remove classes of failure: whole-document snapshots for undo, JSON for every file, and one
data model projected twice rather than two models kept in step. Anything added below should be
checked against that: **the document is the design, and every picture is a projection of it**.

## 1. Snap-to-geometry and smart guides - BUILT

`scripts/draft/snap_engine.gd` (`SnapEngine`) plus `scripts/draft/spatial_grid.gd`
(`DraftSpatialGrid`). Held down by `tests/test_snap.gd` - 22 tests.

The decisions that make it usable rather than merely present:

* **Priority outranks distance.** An endpoint beats a closer midpoint; an object snap beats a tracking
  constraint. A snap that is merely the nearest thing to the cursor is a snap that fights the user.
* **Hysteresis, 1.6x.** Once a candidate is locked it holds until another beats it by that factor, and
  the lock survives leaving the aperture. Otherwise the cursor flickers between two candidates that
  are equally valid, and a drawing gets made at the wrong one.
* **The aperture is in pixels**, not model units (`test_the_aperture_is_measured_in_pixels_not_metres`),
  so it behaves the same at every zoom, and it converts through the one tested function.
* **Intersections are pruned** to entities that are actually nearby, so the O(n^2) test never runs on
  the whole drawing.
* **The grid is a uniform grid, not an R-tree** (`spatial_grid.gd`), because a residential plan is
  hundreds to low thousands of entities and a grid rebuilds in microseconds. Entities spanning more
  than `MAX_BUCKETS_PER_ENTITY` (64) buckets go on an overflow list checked on every query, which is
  what stops one 600 m site boundary with a 4 m cell becoming quadratic. The file states its own
  revisit threshold: past roughly fifty thousand entities.

Modes: endpoint, midpoint, centre, quadrant, intersection, nearest, perpendicular, tangent, grid.
Object snapping to **planted props on the plan** goes through the same engine (props are in the
`placeable` group and are entities in the plan projection), so a new plant snaps to the bed it is
going in.

**Missing:** a smart guide that is *drawn* as a guide rather than inferred from a snap - the tracking
constraints draw their guides, but there is no "alignment guide while dragging" line for a moved
object, because nothing is draggable yet (see section 2).

## 2. Auto-cleanup - AUTO-SIMPLIFY BUILT; ALIGN AND GROUP NOT

**Auto-simplify is built** (commit `f98b6dd`); nothing aligns and nothing groups. What exists is adjacent and worth knowing before designing it:

* `Geom2D.offset_polygon` insets exactly, and a self-intersecting ring is refused *with a reason*.
* `bulge` on a polyline vertex expands into a real arc, so a "simplify" that turned curves into
  vertices would be throwing away information the model can carry.
* Hatching clips to holes rather than filling them, so a fill does not depend on cleanup having run.

The three tools, and what each actually costs:

**Auto-simplify** is the cheap one, because it is a pure function over a frozen entity list: a
Douglas-Peucker pass with a tolerance in model units, then a *refusal* if the result would move an
endpoint that another entity shares. That last rule is the whole design - a simplifier that silently
detaches a wall from a bed is worse than no simplifier. It belongs in `scripts/draft/geom2d.gd` beside
`offset_polygon`, as `simplify(points, tolerance) -> PackedVector2Array` plus a `SimplifyReport`.

**As built.** `Geom2D.simplify(points, tolerance, closed)` is the pure pass; `SimplifyReport` is
the plan - what would change, and every refusal with its reason - worked out before anything is
touched; `DraftSimplify.plan` builds it and `DraftSimplify.apply` carries it out as one undo step.
Three corrections the build forced:

1. **A ring is simplified as two chains** meeting at its two opposite extremes, not as one chain
   run from its start back to itself: a chain Douglas-Peucker'd against its own start and end keeps
   nothing, and for a small bed that is the bed disappearing.
2. **A shared corner counts as kept when the simplified shape still passes through it**, not only
   when the vertex survives - a vertex dropped on a straight run leaves the two shapes touching, and
   refusing that would refuse the simplification that is obviously safe.
3. **A curved (bulged) shape is refused, naming the arcs.** The note above is right that a vertex
   pass cannot carry an arc, so the pass steps around such a shape rather than straightening it.

The tolerance is a paper length - `DraftSimplify.PAPER_MM` (0.4 mm) through the same
`LineStyleScript.model_width_m` every other paper length uses - so "invisible" is a statement about
the plot scale. It is reachable from **Edit > Simplify...**, which asks with the pass's own report
before it changes anything.

**Auto-align** is a batch snap: an edge, a midpoint or an axis taken from whichever entity is
selected first, applied to everything else selected, recorded as **one undo step** per run (the
document already supports a gesture as one step). It is mostly a UI question - what is the reference -
and it needs a selection model, which is the real missing piece: **the document has no multi-entity
selection**. That is the prerequisite for this and for auto-group.

**Auto-group** is the expensive one, because it is not a tool at all: it is a **new entity kind**.
Layers exist, but a group is an object with its own id, a member list, and a transform, and then every
selection, render, bounds and snap path has to decide what a group means to it. Recommend not building
it until a real drawing demands it; a layer rename plus selection does most of the work.

## 3. Revision tracking - BUILT, apart from the audit journal

**Built:** undo and redo, as whole-document snapshots - `scripts/draft/undo_stack.gd`
(`DraftUndoStack`, `DEFAULT_LIMIT := 200`). The file argues its own case: inverse commands are the
textbook answer, but every tool then needs a correct inverse, and a subtly wrong one corrupts a
drawing in a way the user cannot see or repair. A snapshot per committed edit costs almost nothing at
this size and removes that whole class of failure. One push per *gesture*, never per motion event.
`tests/test_draft_document.gd` holds it down, including that a gesture undoes and redoes as one step
and that new edits clear the redo branch.

**Built:** file persistence - `scripts/draft/drawing_store.gd`, atomic (temp file then rename), one
JSON file per drawing, a version field, and legacy reads (`to_dict()` writes version 6 while
`restore()` still reads the old flat site fields). A failed open never touches the open drawing.

**Built:** the named revisions, and the difference between two of them.

* **A revision is a record, not a stack.** `scripts/draft/revision_log.gd` (`DraftRevisionLog`):
  `capture(state, message, author)` keeps `{message, author, when, snapshot}`, where the snapshot is
  the drawing's own `to_dict()` - whole, as `undo_stack.gd` argues for, because a capture happens on
  a person's command rather than on every keystroke. `LIMIT := 50` keeps the last fifty and counts
  what it let go, so a history can say it is not the whole story. `record_at(index)` is what a list
  shows - message, author, when, and how many shapes the drawing had - and `snapshot(index)` hands
  out a copy, so a restore cannot alter the revision it came from.
* **Where a history lives.** `user://revisions/<name>.json`, one per drawing, written atomically by
  `drawing_store.write_revisions` through the same temp-file-and-rename the drawing itself goes
  through. Deliberately **not** in `user://drawings`: the file dialogs open on that folder, so
  anything kept there is offered to a person as a drawing and can be saved over - the same reason
  the recent list is kept outside it. Keyed by the drawing's *name*, which means Save As starts a
  fresh history: the revisions belong to the design that was sent, and the copy somebody keeps
  working on is a new document.
* **The diff, as built.** `DraftRevisionLog.compare(before, after)` is the sketch above with two
  corrections it turned out to need. The first: the document stores its entities as a **Dictionary
  keyed by id** (`{"3": {...}}`), not as an array of records that each carry an `"id"` field, so the
  loop walks the dictionary's keys and coerces them with `int()`. The second, and the one that
  would have bitten: a snapshot held in memory carries integer keys and integer lengths, and the
  same snapshot read back from a file carries strings and floats - compared directly, a revision
  reports *itself* as changed. Both sides are therefore compared after a JSON round trip, and
  `tests/test_revision_log.gd` holds that down on purpose.
* **What it does not do** is unchanged: it points at the shapes that changed and does not say what
  changed *inside* one. "This bed got wider" is a human sentence about geometry, and a diff's job
  is to point at the bed so somebody can look at it. `describe_diff()` reads as
  `1 added, 1 changed, 1 removed  (added: #7; changed: #3; removed: #9)`.
* **Putting one back** is `DraftController.restore_revision(index)`, and it is a change like any
  other: the state it replaces goes onto the undo stack first, so a designer who puts back the
  wrong revision can get back the drawing they had a moment before. It leaves the drawing's file
  where it is and marks the drawing dirty, because what is on screen is an earlier revision of it.
* **The way in** is Edit > Revisions..., which opens `scripts/revision_window.gd`. The window owns
  no drawing: it lists the rows it is handed, says what the selected revision changed, takes the
  message for the next one, and announces `revision_recorded` / `restore_requested` for the HUD to
  answer with the controller - the hatch panel's arrangement, which is what lets the whole window be
  tested with no drawing and no screen.
* **A revision recorded before the drawing has ever been saved** is kept in memory and goes to the
  file at the first save, with the window saying where it is rather than refusing: the designer has
  done their part, and the file name is a separate errand.
**Still missing:** the audit journal, and it belongs to the business specification:
* **The append-only journal** exists in the business specification
  (`docs/business-operations-spec.md` section 11.1, section 2.12, phase 10 - **built**) as
  `journals/events-<month>.jsonl`: who did what, when, to which record. That is the right home for it.
  A drawing should not grow a second audit trail that disagrees with the business one.

**Not recommended:** storing a diff *instead of* a snapshot for undo. Deltas are what the project
already decided against, for the reason `undo_stack.gd` gives.


## 4. Fast symbol placement - BUILT, and instancing was cancelled on purpose

`scripts/plant_placement.gd`. `place()` fills in the scene path, gives the node a unique name, scales
it by `planting_scale` (the species' spread over the prop's base size), adds it to the `Plants` subtree
*and* to the `placeable` group, and writes the species, height and spread into the node's metadata. So
the size a plant is drawn at is not a copy of the catalogue - it is the catalogue, applied.

Choosing is `PlantBrowser` (`scripts/plant_browser.gd`, the window with search and filters) or the
palette panel (`scripts/plant_panel.gd`, built this turn). Either way: one click to choose, one click
on the plan, and it stays armed, because a bed is a dozen clicks and not a dozen trips through a
window. Escape puts it away. Arming a plant puts the drawing tools away, so planting and drafting
never both own the left button.

**A whole bed at a spacing - BUILT, and it makes the sentence above the slow way.** Clicking a
bed a plant at a time is right when a designer is composing it - that is what the reach argument
is for - but it is not how a bed of a hundred groundcover plants gets planted. `PlantSpacing`
(`scripts/plant_spacing.gd`) plants a bed from the outline the plan already draws: two controls in
the palette say at what spacing and in which arrangement, the drop-down says which bed, and one
press puts the planting down and reports what it did. Square or staggered, half a spread in from
the edge by default, and a refusal rather than a half-planted bed when there is no answer -
`docs/plant-database-spec.md` section 5a. One press per bed, not one click per plant.

Caching, in two layers:

* `PlantCatalogue.thumbnail_for` / `scene_for` cache **including misses**, so a species with no
  photograph does not stat the disk on every frame, and `clear_cache` / `cache_loads` make the cache
  inspectable.
* `PlantIcons.CACHE` is keyed `"form|category"`, not by species: seventeen species drawn as three
  props are three pictures, four thousand are thirty. Shared with the browser, so the grid and the
  palette cannot show one plant two ways.

**Instancing.** The 3D props are scenes, and what is instanced is the practice rather than the API:
one scene file per prop, reused by every placement, with the per-instance facts in metadata instead of
copied into a variant scene. MultiMesh batching was considered and **cancelled** (visualization
specification, phase 5): the count does not justify it. The threshold is worth writing down, because
"instancing" is usually asked for reflexively - a residential plan is tens of props; MultiMesh pays
past thousands of *identical* meshes, and what it costs you is per-instance picking, per-instance
scale by species, and every instance sharing one material and one shadow batch. A meadow planted as a
matrix of one grass, or a nursery row, is where to revisit it.

**Drag-and-drop is not built, deliberately.** A drag needs a drag source, a drop target, a ghost, and
a rule for a drag that ends nowhere; a click needs a click. The plan is also a 3D world seen through a
camera, so a "drop" lands on the ground plane - which is exactly what the click already resolves, and
it resolves it through the same bounds clamp and the same snap engine. What would be worth building is
the reverse gesture: dragging a plant that is already on the plan in order to move it. That needs the
multi-entity selection named in section 2.

## 5. Flexible drawing modes - BUILT

The concept-to-construction axis is not implemented as two modes, and that is the design: it is four
settings that vary independently, so a drawing is not in one mode or the other but at a point on
several.

| what varies | where | concept end | construction end |
| layers and pens | `draft_layer.gd`, `layer_set.gd`, `plot_style.gd` | a few fat layers | 14 layers, each resolving to a pen slot |
| weight on paper | `draft_render.gd` | one weight | the hierarchy, in paper mm, constant at any zoom |
| presentation tier | `presentation_tier.gd` | `STILL`: ssao, supersample 2, stylised | `WORKING`: budget, no shadows |
| look | `sketch_style.gd`, `sketch_baker.gd`, `sketch_compositor.gd` | the painted plan | the working plan, or the plotted sheet |

Weight is *paper* millimetres and never model units (`test_weight_is_constant_on_paper`), the wobble is
geometry rather than a shader, the compositor takes no pixel counts, and supersample-then-downsample
is the antialiasing. A sketch and a construction sheet are therefore the same document seen at two
tiers with two looks - one data model, two projections.

**Missing at the concept end:** a tool that is deliberately not to scale (a "sketch line"). Not
recommended. The wobble already gives a drawing the look of a sketch without letting it *be* wrong,
and a CAD document with a line whose length is not its length is a document nothing downstream can
measure - which would break the takeoff in section 7 on the day it is built.

## 6. Solo designers and teams - PRESENCE BUILT, ON DEMAND

Presence is built, and it is presence and nothing more - the drawing stays one person's file and
nothing is merged: `scripts/presence.gd` and `scripts/presence_member.gd` carry it, a `Presence` node sits in `scenes/main.tscn`, and the Hud grows a Team menu.

**What is ready** is the data model, and it is ready by accident of the other decisions: every record
is JSON with a stable id; a book carries a `version` and a new version is a new book; collections are
stored separately from the catalogue; writes are atomic (temp file, then rename); and a failed open
never touches the open drawing. That is the shape a second person's copy has to travel in - identity
per record, and a version to cite - and building it that way was not wasted work.

**What is still missing**, in the order it has to be *decided* rather than coded:

1. **Who owns the drawing.** **Answered, provisionally.** Two people drawing in one document is a
   different product from two people working on one garden, and the cheap useful answer was taken:
   presence and hand-off - "Bob is in Backyard Design" - rather than a merge strategy over geometry.
2. **The unit of change.** With whole-document snapshots for undo, the honest unit is the document,
   with an explicit save and an explicit lock, until somebody demonstrates a need for finer. Merging
   two sets of entity edits is a research problem, and doing it because it sounds right is how a
   drawing gets corrupted in a way nobody can see.
3. **The transport.** **Answered.** Ziva's relay is provisioned, and a session connects a
   `WebSocketMultiplayerPeer` to the room address only when somebody chooses Share - never on launch.

**This is built.** The relay is provisioned, and a `MultiplayerSynchronizer` per member over a
`Presence` node carries the name, the current drawing and the cursor - presence only, no geometry.
One real peer is the host (the lowest real peer id, computed identically by every peer, with no
election and no handoff), and a session is opened on purpose from the Team menu, never on launch.

## 7. Integration between the modules - SPEC'D; PHASES 0-11 OF 12 ARE BUILT

The chain, what each link is made of, and where it stands:

| stage | the shared model | state |
| design | `DraftDocument`, plus `PlantCatalogue` for the planting | built |
| takeoff | measures the design: lengths, areas, counts, hours | **built** - `takeoff.gd`, 18 tests |
| estimate | takeoff lines x rates, money per line, tax per code | **built** - `estimate_line.gd`, `estimate.gd`, 29 tests |
| pipeline | prospect, quoted, approved, scheduled | **built** - `lead.gd`, `pipeline.gd`, `pipeline_board.gd`, 48 tests |
| jobs and crews | the estimate becomes a job, with crews and dates | **built** - `job.gd`, `crew.gd`, `schedule.gd`, `route.gd`, `time_entry.gd`, `job_desk.gd`, `schedule_board.gd`, 109 tests |
| job costing | actuals against the estimate | **built** - `purchase_order.gd`, `change_order.gd`, `job_cost.gd`, `job_cost_window.gd`, 121 tests |
| billing | invoices off the job, `Tax` per component | **built** - `rate.gd`, `milestone.gd`, `billing.gd`, `invoice.gd`, `payment.gd`, `invoice_sheet.gd`, `billing_desk.gd`, `billing_window.gd`, 213 tests |
| ledger adapters | invoices posted to a service or a folder, and what it would not take | **built** - `ledger_adapter.gd`, `file_ledger.gd`, `invoice_ninja.gd`, `akaunting.gd`, `ledger_push.gd`, `credit_note.gd`, `ledger_desk.gd`, `ledger_window.gd`, 194 tests |
| analytics | what the records say: win rate, profitability, what is owed, how busy the crew is | **built** - `analytics.gd`, `analytics_window.gd`, 92 tests |
| store and sync | per-record revisions, append-only journal, HTTP | **built** - `store.gd`, `sync_transport.gd`, `http_transport.gd`, `sync.gd`, 119 tests |
| editor tooling | a supplier's price list read into the book, and what it would change before it does | **built** - `book_import.gd`, `price_preview.gd`, `addons/biz_tools/`, 107 tests |

The primitives that already exist and are tested: `Money` (integer minor units, invalid is contagious,
one rounding per line), `Tax` (rates as integer parts per million - a basis point cannot state QST at
9.975 percent - components that may compound, a missing code refused rather than treated as zero),
`WorkUnit` (a dimension with an exact ratio, so a perimeter cannot be priced as paving), and
`CostItem` / `CostKit` / `CostBook` (kits expand and scale, a cycle is refused *naming the chain*).

**The takeoff is the piece that makes the design module and the business module one program rather
than two**, and it was the smallest of the missing links, because it is measurement plus bookkeeping
over APIs that already exist. **It is built**: `scripts/biz/takeoff.gd` measures a `DraftDocument`
and a planting schedule, suggests a priced item per layer, prices a line by exact conversion, and
diffs one takeoff against another; `scripts/biz/estimate.gd` rolls the lines up and freezes them.
The example below is therefore the shape it was built to, and it was written before the file was - with
three differences the build found, all recorded in the business specification's section 15: the
measurement's `measure` is a **dimension** and not a unit; a layer can produce **two** lines (an area
and a length), so the key a diff hangs on must name the measure as well as the layer; and a plant with
no species is refused rather than priced at whatever rate was nearest.

```gdscript
# TakeoffLine is an inner `class` of Takeoff in the real file: GDScript allows one `class_name`
# per file, so an example that wrote two would not run.
class TakeoffLine extends RefCounted

var source: StringName = &""        # "layer:401-NEW-PLANT|count", or "plant:acer-rubrum-autumn-blaze"
var description: String = ""
var unit: StringName = &"m2"        # a WorkUnit name, so the dimension travels with the number
var quantity: float = 0.0
var item_id: StringName = &""       # the CostBook item that prices it, or empty
var note: String = ""


class_name Takeoff
extends RefCounted

var revision: Dictionary = {}       # the document's own to_dict(), so a line traces to a drawing
var lines: Array = []               # of TakeoffLine
var problems: Array[String] = []

static func of_document(document: DraftDocument, book: CostBook) -> Takeoff:
	var takeoff := Takeoff.new()
	takeoff.revision = document.to_dict()
	for entity: DraftEntity in document.entities():
		var line := TakeoffLine.new()
		line.source = StringName("entity:%d" % entity.id)
		if entity.area() > 0.0:
			line.unit = &"m2"
			line.quantity = entity.area()
		elif entity.length() > 0.0:
			line.unit = &"m"
			line.quantity = entity.length()
		else:
			continue
		line.description = "%s on %s" % [entity.kind_name(), entity.layer]
		line.item_id = item_for(entity, book)
		if line.item_id.is_empty():
			takeoff.problems.append("%s has nothing to price it" % line.description)
		takeoff.lines.append(line)
	return takeoff
```

The four rules it has to obey, every one of them already a decision in this project:

1. **A takeoff measures and never prices.** Money appears once, in the estimate, and rounds once per
   line (`Money.rounded_div`) - a rate is integer parts per million for exactly this reason.
2. **A quantity keeps its unit and its dimension** (`WorkUnit`), so paving is priced by the square
   metre and a fence by the metre and neither can be billed as the other.
3. **Every line names its source.** That is what makes the integration real rather than a copy: run
   the takeoff against a newer revision, diff the lines, and the answer is "what did this change cost
   me" - which is the question the whole chain exists to answer.
4. **A line with no rate is refused and named, never silently zero.** The same rule the cost book, the
   tax table and the plant catalogue already use, and the one that stops an estimate being quietly
   short.

`PlantPlacement.schedule()` is already a takeoff in one dimension - the planting list, "2 x Acer rubrum
'Autumn Blaze'", "30 x unidentified" - and it already counts what it cannot name as its own row. The
takeoff's first job is to generalise that to every layer.

## 8. One box for the whole bar - BUILT

`scripts/command_palette.gd` (`CommandPalette`) and the HUD's join in `scripts/hud.gd`. Held
down by `tests/test_command_palette.gd` (19 tests) and `tests/test_hud_palette.gd` (19 tests),
and looked at live by `tools/palette_demo.gd`.

The problem it answers is not "I cannot find the command" but "I know its name and not its
menu". The bar is fourteen menus and a hundred and twelve commands in the shipped scene, and the
handful of keys that reach the ones used every minute are the only ones anybody remembers.

* **It holds no list of commands of its own.** The rows are built from `menu_plan()` - the bar's
  one source - so a command cannot be in the box and missing from the menu, or called two
  different things in the two places. Every row carries the entry it stands for, and the HUD runs
  it through the same door a press in the menu uses (`Hud.run_entry`): that one line is what makes
  the box and the bar the same program rather than two lists of the same commands.
* **A command that cannot run here is shown rather than dropped.** The bar greys out what the
  scene cannot do instead of hiding it, so a menu still says what the program does in a scene that
  cannot do it. The box keeps that rule and takes it further: the row says *what is missing* in
  place of its menu - "there is no drawing open" - and picking it refuses it in the same words
  rather than doing nothing. An entry that vanishes cannot teach anybody anything.
* **The ranking is the usability.** A command whose *name* begins with the word beats one that
  merely contains it, and either beats one that is only in a menu of that name. Ties keep the
  bar's order, so the same search gives the same list every time. Reaching one of the ten plot
  scales by typing `A2` is the whole point of the box.
* **The keys are the box's own.** While a `Window` has the keyboard the HUD never sees a key
  event at all, so Escape, Enter and the arrows are answered for on the one control that holds it
  - the field - which is also why the field takes focus the moment the box opens. Nothing else in
  the box can hold the keyboard, and the box never holds it while it is closed.
* **`Ctrl+P` sits inside the file-dialog guard**, beside Ctrl+N/O/S and for the same reason: the
  box can reach a command that opens a dialog, and a second box behind an open Save dialog could
  open another one.

The manual gained `Finding any command: the palette` as its second subject, because a way in that
is all keyboard is exactly what prose is for. The live check presses the real keys through
`Input.parse_input_event` rather than `Input.action_press`, which sets an action's state and sends
no event at all - a check built on it would never have exercised the handler Ctrl+P lives in.

## 8b. A picture under the drawing, to trace over - BUILT

`scripts/draft/raster_underlay.gd` (`RasterUnderlay`), `scripts/underlay_window.gd`, and the joins in
`scripts/hud.gd`, `scripts/draft/draft_controller.gd` and `scripts/plan_canvas.gd`. Held down by
`tests/test_raster_underlay.gd` (20 tests), `tests/test_underlay_tools.gd` (12),
`tests/test_underlay_window.gd` (9) and `tests/test_hud_underlay.gd` (9); looked at live by
`tools/underlay_demo.gd`.

The problem it answers is the one most redesigns start with: the thing you have to draw over already
exists, and it arrived as a picture - a scan of a surveyor's plat, a marked-up print, an aerial
photograph, the consultant's concept.

* **The header, not the pixels.** Only the format and the pixel size are read before the picture is
  drawn, and the decoder is only ever handed bytes whose header has already been understood. A
  12000 x 9000 scan is 400 MB decoded, and Godot's own loaders print an error on anything that is not
  an image: reading the header first makes both of those somebody else's problem.
* **The picture is copied, not pointed at.** It is kept in `user://underlays`, because a drawing is a
  document that gets sent to other people, and one pointing at `D:\scans\site-plan.png` is broken
  everywhere but on the machine it was drawn on.
* **It is placed by how far it lies across the ground**, in the drawing's own unit, and the picture's
  own proportion supplies the other direction - so a plan cannot be stretched out of shape by a
  mistyped number, and the second number never has to be typed at all.
* **A picture is not geometry**, and the design follows from that one sentence: it never plots, never
  snaps, is never measured and is never bought by the square metre, and it cannot drag the drawing's
  extent - and so the plot scale - around with it.
* **It lies over the ground and under every line**, which was a live finding rather than the drawing
  order it was written with. It was written to draw before *everything*, which in this app hides it:
  the 2D plan paints the yard's own lawn, house and paving as flat shapes after the paper, so the
  picture was there, held by the canvas, and completely covered. What settled it was not reading the
  code but reading the framebuffer - the same pixel with the picture drawn and with it put away. Two
  numbers are worth more than an inspection.
* **A gesture only when something changed.** Moving a picture, turning it and fading it are each one
  named undoable step, and the change is worked out on a copy and compared first, so asking for the
  turn it already has records nothing. Taking a picture off leaves its copy where it is, because undo
  has to be able to put it back.


## 9. What I would build next, in this order

1. ~~**The takeoff and the estimate (business phases 2 and 3, together).**~~ **Done.** Built as
   `takeoff.gd`, `estimate_line.gd` and `estimate.gd` with 47 tests, and verified against the shipped
   scene: a patio drawn into the live document priced to a $3,687.27 proposal, and the 30 unidentified
   plants in the shipped yard refused rather than priced.
2. ~~**Multi-entity selection.**~~ **Done.** Built as `scripts/draft/draft_select.gd`: window and
   crossing bands in the two modes the plan asks for, swept over the drawing's own geometry, armed
   from the Edit menu. What is still missing is *dragging* what is selected - the band says which
   shapes, and moving them is a separate step.
3. ~~**Auto-simplify.**~~ **Done.** Built as `Geom2D.simplify`, `SimplifyReport` and
   `DraftSimplify`, with the shared-corner refusal that is the whole design and reachable from Edit > Simplify... See section 2.
4. ~~**Named revisions and the document diff.**~~ **Done.** Built as `scripts/draft/revision_log.gd`,
   `scripts/revision_window.gd` and the store's own `write_revisions`; see section 3, which is now
   built down to the audit journal.

5. ~~**Presence.**~~ **Done.** One synchronizer per member, no merge problem, and it is what a team asks for first; see section 6.
6. ~~Then the rest of the business chain in specification order (4 pipeline, 5 jobs and crews, 6 job
   costing, 7 billing, 8 ledger adapters, 9 analytics, 10 store and sync, 11 the editor plugin).~~ **Done.** Phases 4 to 11 are built; see section 7.
7. ~~**Autosave and crash recovery.**~~ **Done.** Unsaved work is copied while the drawing
   is dirty, one file per drawing identity under `user://recovery`; the next run offers it
   through File > Recover unsaved work with Recover / Discard it / Not now, and recovering is
   one undoable step. See the drafting subsystem spec, REQ 8.9.

8. ~~**A picture to trace over.**~~ **Done.** Built as `RasterUnderlay`, `UnderlayWindow` and the
   plan canvas's `_draw_underlays`, with four test files; see section 8b. It is the first thing in the
   program that reads a file without making entities out of it, which is what made it cheap: no
   editing, no takeoff, no plot, no sheet.

Sections 1 to 5 above were checked by reading the scripts and their tests; section 6 by reading
`presence.gd` and its own fifteen tests; section 7 against the business specification's own
phase table, where phases 0 to 11 are marked built.
Section 8 was checked by reading the box in the running program rather than by reading the
script that builds it: `tools/palette_demo.gd` presses Ctrl+P, types a word, presses Enter and
presses Escape through the real input pipeline, and each of the four acts on the real controls.

Section 8b was checked by reading the picture's own pixels back off the framebuffer in
`tools/underlay_demo.gd`, once with the picture drawn and once with it put away, because the first
version of it was held by the canvas and drawn nowhere.
