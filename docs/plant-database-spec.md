# The plant database

A landscape plan is mostly plants, and until this module existed the planner had props: three
scenes - a tree, a shrub, a flower bed - placed by hand in `yard.tscn`. What it did not have was a
*species*: a red maple that is hardy in zone 3, spreads 9 m, blooms in March, wants sun and average
water, and is drawn as a tree. This module is that, and everything that hangs off it.

**Status.** Built: the catalogue, the placement link, the planting list, the browser, the palette
section, the ground under a plant with the ring that reads it, and the fill that plants a whole
bed at a spacing (§5a). The starter list is **130 species**: the 17 it began with and the
expansion of §2a. 45 tests in `test_plants.gd` (20), `test_plant_placement.gd` (11) and
`test_plant_browser.gd` (14), plus the fill in `test_plant_spacing.gd` (18), the Plant menu in
`test_hud_menu.gd`, the palette in `test_plant_panel.gd` (18) and the expansion in
`test_plant_expansion.gd` (7).

## 1. JSON, not one `.tres` per species

The same decision the cost book makes, for the same reason: a count. A catalogue is four thousand
entries. It arrives from a nursery as a spreadsheet export, it is mailed to a colleague, it is
diffed in a review, and a buyer of this tool expects to edit it in Excel. Four thousand `.tres`
files would be four thousand files in version control, none of them readable by a program that has
never heard of Godot, and every one of them a chance to be out of step with its neighbours.

What *is* a `Resource` is the runtime handle: the `PackedScene` a species is planted as and the
`Texture2D` it is pictured with. `PlantCatalogue` loads each of those once and caches it - misses
included, because a grid asks for the same thumbnail on every redraw.

## 2. The files, and where they live

| file | who writes it | what it is |
| --- | --- | --- |
| `user://plants/catalogue.json` | the program | the species |
| `user://plants/collections.json` | the person | their own groups |
| `res://data/plants/nursery_list.json` | the project, through `PlantExpansion` | the species shipped with it - 130, and growing |
| `res://data/plants/nursery_list_more.json` | `tools/plant_expansion.gd` | the additions on their own, as data somebody can read and diff |

Collections are **apart** from the catalogue on purpose. A catalogue ships and an import replaces it
wholesale; nobody's "front bed" list may be replaced with it.

The first run has no catalogue of its own, so the shipped list is the list - read from `res://` and
held in memory until something changes it, at which point it is written to `user://`. A shipped list
stays a shipped list and a catalogue somebody has edited is theirs.

Writes go through a temporary file and a rename, as a drawing and a cost book do: a save that fails
must not leave a shorter plant list where the real one was.

## 2a. More plants, and the rule that keeps them from being duplicates

Seventeen species is a demonstration, not a nursery's list: a designer drawing a real garden reaches
the end of it in an afternoon. `tools/plant_expansion.gd` (`PlantExpansion`) adds the rest of the
trade's workhorses - 113 more, for 130 in all - and it does it through the module's **own importer**
rather than by editing the file, because that is what makes "do not add what is already there" a
property of the mechanism rather than a promise about the data:

* `PlantCatalogue.import_json` **skips an id the catalogue already has** and reports it as refused;
  `PlantCatalogue.add` will not replace an id at all. An id is what an import and a catalogue are
  matched on, and a silent replace is how one plant quietly becomes another.
* An entry the model will not accept is refused **with its reason**, so a mistyped zone cannot reach
  the list.
* The additions are also written out to `data/plants/nursery_list_more.json`, so they exist as JSON
  somebody can read and diff rather than only as GDScript in a tool.

Running the tool a second time is the proof of the rule: it reports `added=0, skipped=113` and the
shipped list is unchanged. The expansion **cannot** edit a plant that was already there.

The data makes the same claims the shipped entries do and no more: zones are USDA ranges, sizes are
whole centimetres as a label gives them, and `soils` and `drainage` (§7a) are stated **only where the
plant is particular** - a lavender wants sharp drainage and says so, a spirea does not and stays
silent. A question the catalogue does not answer is skipped by the suitability check rather than
guessed, so a plant with no soil stated cannot be marked wrong for the soil it is planted in.

## 3. One species

| field | type | why this and not something else |
| --- | --- | --- |
| `id` | string | a stable slug; what an import matches on. A duplicate is refused, never replaced |
| `botanical_name` | string | the name a nursery list sorts by |
| `common_name` | string | the name a designer types |
| `cultivar` | string | without quotes. `display_name()` puts them back: `Acer rubrum 'Autumn Blaze' - Red maple` |
| `category` | int 0..9 | tree, shrub, perennial, annual, grass, groundcover, vine, fern, bulb, herb |
| `zone_min`, `zone_max` | int 1..13 | USDA zones - a range, because "hardy in zone 7" is a range a plant has |
| `height_cm`, `spread_cm` | int | **whole centimetres.** A label says "60 cm tall, 45 cm across" |
| `sun` | bits | full sun / part shade / full shade. A *set*: many plants take two of the three |
| `water` | 0..2 | low, medium, high - a scale, not a set |
| `bloom_months` | 12 bits | bit `month - 1`. **Circular**: a Christmas rose is one run, December to February |
| `bloom_colour` | `#rrggbb` | with the `#`: a bare hex run is not the parse it looks like |
| `form` | scene path | the prop it is drawn as: its 3D model, and the symbol a species the catalogue cannot describe is drawn as |
| `model_scene` | scene path | its own model when it has one; empty means `form` stands in |
| `thumbnail` | image path | for the grid; empty means the symbol swatch is drawn instead |
| `tags` | list of strings | what a designer browses by |
| `note` | string | the thing that does not fit a column |

Dimensions are whole centimetres because a metre value in a float does not compare equal to itself
after a JSON round trip, so every "is this smaller than that" question would need a tolerance.
Centimetres are exact and they sort. Every integer is coerced on the way in, because Godot's JSON
parser has one number type and hands everything back as a float (spec §2.1a).

An entry that cannot be planted is **refused and named** - a zone of zero, a size of nothing, no
botanical name - by `PlantSpecies.problem()`. A species with no size at all is one that cannot be
drawn, and offering it would be offering a designer a plant that does not exist.

## 4. The picture: the link to sprite and model

Three fields, in order of preference: `thumbnail` for the grid, `model_scene` for the thing itself,
`form` for everything else. Nothing in the plant module knows what `tree.tscn` looks like; it knows
the *path*, which the table that already decides how a prop is drawn reads: `PlanStyle.SYMBOLS`.

A species with no photograph is drawn as a **swatch of the symbol the plan would draw it as**, in the
pigment `PlanStyle` washes that prop in. Four thousand species will not carry four thousand
photographs, and a grid of empty boxes is one nobody can look through.

## 4a. The symbol a species is drawn as

A **form** is one prop for four thousand trees. That is right for the model and was wrong for
the drawing: with the symbol read straight off the prop, a spruce and a maple came out as the
same green disc. So the symbol comes from the catalogue's own description of the plant
(`PlantSymbols.described_for`) and the vocabulary is nine shapes - `canopy`, `conifer`,
`shrub`, `grass`, `groundcover`, `vine`, `fern`, `bed`, `marker` - held in `PlantSymbols.NAMES`:

| the plant is | it is drawn as |
|---|---|
| a tree, a shrub | `conifer` when its genus is a conifer, else `canopy` / `shrub` |
| an ornamental grass | `grass` |
| a groundcover | `groundcover` |
| a vine | `vine` |
| a fern | `fern` |
| a perennial, annual, bulb or herb | whatever its `form` draws as - the planted `bed` |
| a species with no entry, or a prop nobody knows | its `form`'s symbol, and `marker` |

Whether a plant is a conifer is asked of its **botanical name** (`PlantSpecies.is_conifer()`),
not of the `evergreen` tag: a boxwood is evergreen without being a conifer, and drawing one as a
spruce would be a lie a designer reads at a glance.

Each symbol is one **figure** in `PlantSymbols`: a short list of parts in a normalised square -
fills, outlines and marks (a trunk, a bloom, a tuft) - and *both* the working plan and the swatch
walk the same list. That is what stops the grid and the drawing from disagreeing about what a
plant looks like, and it is why the symbol's own shape decides whether a plant is drawn round:
a round symbol is drawn square whatever its prop's footprint says (`is_round`, `shape_for`), so
a grass whose species stands in as a flower bed does not come out as an oblong blade of grass.

The footprint a symbol is drawn in comes from the prop, as it always did, with one correction:
a round symbol takes the *longest* side, which is what keeps a conifer round and a bed oblong.

A planted node carries its symbol as node metadata (`PlantSymbols.SYMBOL_META`), written by
`PlantPlacement.place` at the moment it is planted, beside its species, its height and its
spread - because the plan reads a *node* and not a catalogue, so a plant copied in the editor
must not lose the shape it is drawn as. Everything that asks what shape a plant is - the plan's
symbol, the selection ring, the wash and the painted plan's ink - reads it through
`PlanStyle.symbol_of`, so all of them agree.

Swatches are cached by **symbol, form and category** - a few dozen pictures, not four thousand -
and what tells two plants apart in the grid is a *tint* from the species' bloom colour, not
another texture. `PlantIcons.symbol_of` and `PlantSymbols.of` are the one call: a grid that
showed a plant as one shape while the plan drew another would be worse than no picture at all.

## 4b. The models, and where to get more

Three props stood in for all nine shapes until these were built: the plan drew a spruce as a conifer
while the garden stood a maple's crown in its place. `assets/plants/` now carries one **`.gltf`** model
per shape, built by `tools/plant_models.gd` and written out by Godot's own `GLTFDocument` - so the
project needs no Blender, no export step a person has to remember, and no download.

| model | what it is | footprint |
| --- | --- | --- |
| `conifer.gltf` | a spruce: a trunk under four cone tiers | 2.60 m across, 5.90 m tall |
| `grass.gltf` | a tuft: a mound with two rings of blades fanned out | 1.09 m, 0.70 m tall |
| `groundcover.gltf` | a flat mat with leaves lying on it | 0.64 m, 0.13 m tall |
| `vine.gltf` | a stem with foliage up it | 0.91 m, 1.70 m tall |
| `fern.gltf` | a crown with eleven fronds arching out of it | 1.13 m, 0.56 m tall |
| `perennial.gltf` | a planted bed: an oblong of leaves with bloom stems | 2.56 x 1.38 m, 0.90 m tall |

**A model is the size its `PlanStyle.SYMBOLS` entry says it is.** `PlantPlacement` plants an instance
at `spread / size.x`, so the declared footprint is where every one of those species' real size comes
from: a model rebuilt at another size without its declaration moving would put every one of its plants
at the wrong size, and no view would look broken. `tests/test_plant_models.gd` *measures the asset on
disk* against the table rather than trusting either.

`perennial` is oblong on purpose. A perennial, annual, bulb and herb is drawn as a `bed`, and a bed's
plan footprint is the *prop's own oblong* (`PlantSymbols.is_round`): a round model under an oblong
symbol stands in the garden as something other than what is on the paper, and `PlantPlacement` sizes
all sixty of those species by that one footprint.

### 4b.1 A downloaded model

Any `.gltf` or `.glb` drops in the same way, and there is no import step to remember: Godot writes the
`.import` beside it and the asset becomes a `PackedScene`. Four things, in this order:

1. Put the file under `res://` - `assets/plants/` is where the built ones live.
2. Add a `PlanStyle.SYMBOLS` entry keyed on that path: the `symbol` it draws as, one of the nine, plus
   the true footprint in metres and the `wash`. A path the table does not describe is still drawn - as
   a `marker` with no wash - which is what a half-finished import should look like.
3. Point the species at it: `model_scene` in `nursery_list.json`, or through the browser's import. The
   `form` is left alone, because it is both the prop that stood in and the record of what the list was
   grown with.
4. Nothing else. The plan symbol, the footprint, the wash, the 3D view and the planting list all read
   that one table, so there is no second place to keep in step.

Sources that need no account and no attribution for commercial work: **Poly Haven** and **ambientCG**,
**Kenney** and **Quaternius**, and the CC0 tree packs published on itch.io. Sketchfab and BlenderKit
are mixed - check the licence on the model rather than the site - and Botaniq, The Grove, Laubwerk and
SpeedTree are paid. A model arrives Y-up, which is what `.gltf` is and what the rest of the project
already assumes.

### 4b.2 What was pulled in, and what was refused

The models above are built here. A whole library can also be *pulled in* - and the useful part of doing
that was measuring, because the two obvious CC0 sources answer differently.

**Kenney's Nature Kit is in, under `assets/plants/kenney/`.** CC0-1.0, no account, one 10.5 MB zip of
329 `.glb` models - 72 of them plants - under `Models/GLTF format/`:

    https://kenney.nl/media/pages/assets/nature-kit/37ac38a37b-1677698939/kenney_nature-kit.zip

Thirteen of them are here, 3-32 KB each, one self-contained `<id>.glb` beside its siblings (no textures at
all: the materials are `baseColorFactor` under `KHR_materials_unlit`). The footprints are **measured off
the file, never typed** - they are the `SYMBOLS` sizes - and the shape is the symbol the plan draws the
species as.

| file | shape | footprint | height | triangles |
| --- | --- | --- | --- | --- |
| `tree_default.glb` | canopy | 0.76 m | 1.71 m | 114 |
| `tree_detailed.glb` | canopy | 0.85 m | 1.33 m | 402 |
| `tree_fat.glb` | canopy | 0.76 m | 1.15 m | 50 |
| `tree_oak.glb` | canopy | 0.74 m | 1.23 m | 196 |
| `plant_bushDetailed.glb` | shrub | 0.60 m | 0.36 m | 104 |
| `plant_bush.glb` | shrub | 0.40 m | 0.24 m | 32 |
| `plant_bushLarge.glb` | shrub | 0.37 m | 0.24 m | 60 |
| `plant_bushTriangle.glb` | shrub | 0.41 m | 0.30 m | 30 |
| `grass.glb` | grass | 0.39 m | 0.25 m | 132 |
| `grass_large.glb` | grass | 0.41 m | 0.25 m | 224 |
| `grass_leafsLarge.glb` | grass | 0.49 m | 0.14 m | 144 |
| `plant_flatTall.glb` | groundcover | 0.27 m | 0.28 m | 32 |
| `plant_bushSmall.glb` | groundcover | 0.38 m | 0.21 m | 16 |

Every one of them dips 5 cm below its own origin on purpose, so a model seated at `y = 0` sits *in* the
ground rather than on it; `tests/test_plant_packs.gd` grants it a floor of -0.10 m and a ceiling of
+0.02 m. They arrive in the kit's own palette whatever the scene lighting is, which is honest for a shape
and is also why they cannot be re-inked by the plan's pens.

**The library is not the point; the shape is.** `tools/plant_packs.gd` plants a species with *the model of
the shape the plan already draws it as*: `SHAPE_MODELS` is keyed by symbol (`canopy`, `shrub`, `grass`,
`groundcover`), and the four shapes the kit does not sell (`conifer`, `fern`, `vine`, `bed`) stay on the
models this project built. Several models share a shape and are shared out **by genus** - ranked
alphabetically, `index % count` - so a border of nine grasses is not nine copies of one tuft and every
cultivar of a genus gets the same model. A species is only pointed at a model that makes **no claim it
contradicts**: the file is named for a *shape* (`tree_oak`, `plant_bush`, `grass`), never for another
species.

`PlantPacks.apply()` writes `nursery_list.json` through `PlantCatalogue.save_to` - the same writer the
expansion tool uses - so the diff is one `model_scene` line per plant, and all **130** species now carry a
model: 65 from the pack and 65 of the four shapes the kit does not have. `PlantPacks.symbol_source()`
prints the `SYMBOLS` text so no size is ever retyped, and `tests/test_plant_packs.gd` measures the files on
disk against that table on every suite run.

**Poly Haven was measured and refused; nothing of it is kept.** Its trees are not plants you place on a
plan, they are scan-grade geometry:

| Poly Haven asset (1k) | downloaded |
| --- | --- |
| `pine_tree_01` | 958.12 MB |
| `fir_tree_01` | 487.36 MB |
| `pine_sapling_medium` | 267.82 MB |
| `jacaranda_tree` | 214.61 MB |
| `tree_small_02` | 100.97 MB |
| `island_tree_03` | 84.89 MB |
| `fir_sapling_medium` | 78.06 MB |
| `island_tree_01` | 66.34 MB |
| `island_tree_02` | 46.17 MB |

and its light botanical models are built for scattering and rendering, not for standing one plant on the
paper. Most are **flat alpha cards**: `grass_medium_01` measures 5.605 x 0.327 x 0.343 m, a sixty-to-one
sheet; `moss_01` 0.215 x 0.029 x 0.040; `dandelion_01` 4.214 x 0.258 x 0.170 at **54,764 triangles**;
`nettle_plant` 1.083 x 0.095 x 0.218. The volumetric ones are thickets or named after another species:
`didelta_spinosa` is 417,187 triangles, `leipoldtia_schultzei` 385,504, `othonna_cerarioides` 118,149
measuring 3.97 x 1.80 x 1.97 m, and `shrub_02` 6.57 x 2.54 x 2.55 m standing 0.61 m *below* its own
origin. One genuinely single 3-D plant did come out of it - `fern_02`, 1.973 x 1.724 x 0.428 m at 6,232
triangles - and even that is wrong here: a photoreal fern among flat-shaded primitives is exactly the
mismatch the pack was chosen to avoid. The measured table is the deliverable; the files were deleted.

**The re-pull recipe.** Poly Haven's API and CDN answer `403 Forbidden` to a client that sends no
`User-Agent`, so state one - `curl` already does, python's `urllib` does not. A download arrives as a
folder per asset and its relative texture URIs resolve only if the folder keeps that shape:

    python -c "import urllib.request as u; r = u.Request('https://api.polyhaven.com/files/fir_tree_01', headers = {'User-Agent': 'landscaping-planner/1.0'}); print(u.urlopen(r).read()[:200])"

Point `DIR` at the top of `tools/downloads_check.gd` at any folder laid out that way (a `<id>` folder
holding `<id>_1k.gltf`, or `.glb` files beside the scene) and that one scene photographs every model in it
at planting scale, measured, one per tile.

### 4b.3 Sources worth pulling next

Same list as section 4b.1, now with a rule of thumb: take a pack whose **models are named for shapes** and whose
**files are kilobytes**, not one whose models are named for species and whose files are hundreds of
megabytes. Kenney and Quaternius build the first kind; Poly Haven and ambientCG build the second, and are
for rendering a picture rather than drawing a plan.

### 4b.4 The check that runs the scene

The asset tests measure the files and the mapping tests read the catalogue, and both can pass while
the *scene* does something else: what lands on the plan is whatever `ViewController` instantiated from
the species the `Hud` armed, and nothing in either test drives that pair. `tools/plant_scene_check.gd`
(`.tscn`) does, and it is a check rather than a printout - each row is held up against the species' own
`model_scene`, the scale `spread / declared footprint` works out to, the symbol `PlanStyle` gives the
planted node, and the `placeable` group the views read:

    res://tools/plant_scene_check.tscn        # run_scene it, then read the console

It instances `scenes/main.tscn`, arms one species in each of the ten `PlantSpecies.category` values
through the HUD's own `_arm_planting`, plants each one through `ViewController.plant_at`, puts it away
between species so the next arm is the only plant in hand, and ends with a verdict line. One bad row is
one wrong plant in every garden, so this is the one place where the catalogue, the pack, the `PlanStyle`
table and the running game are held up together.

**Every check that needs the game running is one pass.** This check and the HUD layout check each
used to bring up their own copy of `main.tscn` - three startup costs, and three differently-aged
scenes, which cannot show a fault that appears only once something else has run. `tools/audit.gd`
(`.tscn`) brings the game up once, calls both checks as `run()` on it, and adds a third check that
loads every scene and resource in the project, then prints a pass/fail table:

    res://tools/audit.tscn                    # every check, one instance of the game, one table

Both checks are functions and not only scenes, so each can be called on a game somebody else
brought up. `tests/test_audit_tool.gd` holds the part the language cannot: a check is handed a bare
node - what a scene that is not `main.tscn` looks like - and has to refuse it, because a table that
says PASS is theatre if no check can fail.

## 5. Planting: what the catalogue does to the plan

A species is not a thing on the plan; it is a description of one. What stands on the plan is an
ordinary prop under the yard's `Plants` subtree, in the `placeable` group - the two things the plan
and the view controller already read. So planting is one operation: instance the scene, size it, put
it in the subtree. Picking, dragging, the plan symbol and the 3D model all keep working without a
second code path, because it is not a second kind of object.

The size is the whole point of the link: `PlantPlacement.place` scales the instance by
`species.planting_scale(base)`, where `base` is the footprint `PlanStyle` gives the prop. A red maple
spreads 9 m and the tree prop is 3.7 m across, so the instance is 2.43x - and its plan footprint, its
3D model, its shadow and its line in the planting list are all the same plant at the same size.

What a plant is is written on the node itself (`species`, `height_cm`, `spread_cm` metadata rather
than a side table), so moving or copying a plant in the editor carries its species with it.

`PlantPlacement.schedule()` is the planting list a planting plan carries: one row per species, sorted
by botanical name, with the count and the size. A plant the catalogue cannot name is **counted and
named separately** rather than dropped - a plant on the plan that the list hides is the one thing a
planting list must never do. The shipped yard shows this: its 30 hand-placed props come out as
"30 x no species recorded", which is exactly what they are.

The list reaches the **sheet**: the plotting exporter draws it as a third table against the
right edge, the drafting controller takes the rows from whoever knows the yard, and the
palette's plot button and the Plot entry in the menu both go through one door, so a plan
cannot be plotted carrying two different lists.

## 5a. A bed at a spacing

A designer does not place a hedge fourteen clicks at a time. They say "45 cm apart, staggered"
and the plan answers with the planting. `PlantSpacing` (`scripts/plant_spacing.gd`) is that
arithmetic and nothing else: given an outline the plan already draws, a spacing and an arrangement
it returns the points a plant goes at, and it is the only place those points are decided - which
is what keeps the symbols on the plan, the props in the yard, the count on the planting schedule
and the quantity in the takeoff from disagreeing about how many plants there are.

Two arrangements, because planting is not a lattice: **square**, and **staggered**, whose rows are
half a spacing across from each other and `sqrt(3)/2` of a spacing apart so that every plant is the
same distance from all six of its neighbours. Staggered is the default because it is what a
planting plan draws and because it packs more plants into the same ground - about 15% over a large
bed, and 104 against 99 at 0.3 m in a four by three metre one.

Two rules, both horticulture rather than taste:

* a plant is pulled in from the edge by **half its own spread**, so the plant on the edge stands
  inside the bed rather than hanging over the lawn beside it;
* the spacing **defaults to the species' own spread**, so a bed filled with no number given has its
  plants just touching, which is what a nursery means by "at the recommended spacing".

**A fill refuses rather than half-doing it.** A spacing tighter than a plan draws is refused, an
outline that encloses no ground is refused, a bed with no room for the plant is refused in a
sentence naming the two numbers that caused it, and a bed that wants more than 500 plants is
refused naming the limit rather than planting the first few hundred and leaving a schedule to match.

The beds it offers are the areas the plan already encloses, narrowed to the layers a planting goes
in (a bed and the planting that is already there), so nothing is planted into a driveway - the same
list the ground window shows, read through `ZoneMap.areas_of`.

## 6. The browser

`scripts/plant_browser.gd` is a `Control` built in code, like the palette and the menu bar, because
every control in it is derived from a table that already exists - the categories, the sun bits, the
water needs, the zones, the months, the tags in the catalogue and the collections a person has made.

    PlantBrowser                 (Control, fills its window)
    └ Margin                     (MarginContainer)
      └ Column                   (VBoxContainer)
        ├ Search                 (Query, Sort, In)
        ├ Filters                (Type, Light, Water, Zone, Bloom)
        ├ Tags                   (HFlowContainer: a CheckBox per tag, with its count)
        ├ Body                   (HSplitContainer)
        │  ├ Grid                (ItemList, ICON_MODE_TOP: the thumbnails)
        │  └ Detail              (ScrollContainer: the label, the collections, a new one)
        └ Footer                 (Place, Import, Export, Status)

It owns no design state: it answers questions about the catalogue and says what was chosen. Placing
is the caller's business, which is what keeps the file free of the yard, the plan and the view.

The filters are named setters - `set_zone_filter`, `set_sort`, `set_tag_filter` - rather than rows of a
drop-down, and `ANY` (`-1`) puts one back to everything. `-1` rather than `0`, because zero *is* a real
category and a real water need, and a filter that treated zero as "no filter" would answer a
different question from the one asked. A filter the catalogue does not understand is refused rather
than ignored.

Two rows of controls, not one: eight drop-downs in a line do not fit a readable width, and a filter
squeezed into sixty pixels is one nobody can read the state of.

## 6a. The same catalogue in the palette

`PlantPanel` (`scripts/plant_panel.gd`) is the other half of the browser, and the reason for it is
reach. The library answers *which* plant: it is a window with a search box and four thousand species
behind it, and it is the right answer to a question you have to think about. It is the wrong answer to
"put that one down again", which is what most of a planting day is - a bed is a dozen of the same
shrub.

So the same catalogue is also a section of the left palette, under the drawing tools:

    Plants                  Library...  (L)
    Tag  [ Any tag          v ]
    +-------------------------------+
    | American cranberrybush        |  ItemList, ICON_MODE_LEFT, 26 px swatches
    | American wisteria             |  by common name, one tag drop-down
    | Astilbe                       |  capped at MAX_LISTED (250)
    | ...                           |
    +-------------------------------+
    130 species.                       Status
    [      Place      ]  [ Stop ]      Actions

It is a plain `VBoxContainer` and not a `Window`, and that one difference decides everything else
about it: **nothing in it may hold the keyboard**. The list is `FOCUS_NONE`, the tag drop-down is
`FOCUS_NONE`, every button is `FOCUS_NONE`, and `allow_search` is off - incremental search is letter
keys, and letter keys belong to the drawing. `list_is_keyboard_free()` is the panel's own statement of
that rule, and a test asserts it, because this panel holds more kinds of control than anything else in
`Root`.

Which is also why there is no search box here, and why the ways in are deliberately few: **one tag
drop-down**, not the browser's eight. A palette is a quick picker; a second row of filters would be a
handler at the end of the design day rather than a shortcut in the middle of one.

`MAX_LISTED` is 250 and the status line says so when it bites - "Showing the first 250 of 400. Open
the library to search." The bound is set well clear of the whole shipped catalogue, because a
palette that could reach only the plants whose names happened to start with A would be a trap rather
than a quick picker; it is there for the four-thousand-row import, where a list that long in a
palette is slower than the window it is trying to save you from. A panel that quietly showed forty
of somebody's four thousand plants would be a worse answer than one that admits it is not the
browser.

The pictures come from `PlantIcons` (`scripts/plant_icons.gd`), shared with the browser, so the two
cannot show one plant two ways: the form decides the shape, the species' bloom colour decides the
tint, and the cache is keyed "form|category" rather than by species - a hundred and thirty
species drawn as three props are still three pictures, and four thousand are thirty.

Choosing here **does not close anything and does not stop the plant**. The library closes on a choice
because the choice was made to get back to the plan; the panel is already beside the plan. It arms the
plant and stays, so a bed is a run of clicks. The plant in hand is shown as the chosen row and the
status line names it - "Planting Common boxwood. 31 standing. Escape puts it away." - so the panel
always says what the next click would put down.

A row is also how the plant in hand is *changed*. The panel re-selects what is in hand on every
refresh - the HUD calls `refresh()` each frame, which is what keeps the palette saying what the next
click would put down - so a click on another row would be undone before the next frame and the list
would look broken. A click that lands on a different plant while one is already in hand is therefore
taken as a change of mind: the panel emits the same `plant_chosen` the Place button and the library
emit, the HUD arms it, and the panel then shows the new row. A click on the plant already in hand asks
for nothing, so putting down a bed of one shrub is a run of clicks rather than a re-arm each time.
With nothing in hand a row is only a *choice* - the Place button is the door to what is in hand - and
`test_choosing_another_plant_while_one_is_in_hand_replaces_what_is_in_hand` holds both halves of that
down, as does a live run of `scenes/main.tscn` that plants one species, clicks the next row and plants
that one without pressing Stop.

The panel owns no design state: it has no yard and no plan, it emits `plant_chosen`, and the HUD does
the planting. That is what keeps a palette section out of the file layer, the document and the view.

## 7. Where it is reached from

The **Plant** menu, between Draft and Present: the line describing the list, the library, place the
chosen plant, stop planting, then import and export. `L` opens or closes the library, which is the one
thing in the plant module reached for constantly while planting a bed.

The library is a `Window`, not a panel in `Root`. That is the whole reason it can have a search box:
`Root` is built focus-free so nothing in this HUD can take the drawing keys, and the one exception
this project allows is a window (spec REQ 8.7). Inside it the controls own the keyboard; outside it
nothing has changed. It is hidden until it is asked for.

The palette section is the second way in, and the one that asks you to remember nothing:
`scripts/plant_panel.gd` sits under the drawing tools whenever the working furniture is up, with the
same `L`-keyed button on it that opens the library. The library is for searching, the panel is for
reaching, and both roads arm the same plant in the same controller.

The third way in is the **Site** menu (§7a.8), which does not place a plant but says what the
ground is like where it would go.

Choosing a plant arms it and closes the library, so the very next click is on the plan. It stays armed
afterwards: a bed is a dozen clicks, not a dozen trips back. Escape puts it away, and a click on
another row of the palette changes it (section 6a), so a change of mind is one click and not two.
Planting and the drawing tools never both own the left button - arming a plant puts the tools away.

## 7a. Suitability: whether the plant belongs where it is going

A green ring on a plant that suits its spot and a red one on a plant that does not, with the reason
written beside it. **Warn, never block**: the plant goes in the ground and the ring tells the truth
about it, because deciding what a garden should be is the designer's job and this is a tool that
informs them.

### 7a.1 The ground is data on the drawing

`scripts/terrain_profile.gd` (`TerrainProfile`) is what one place is like; `scripts/zone_map.gd`
(`ZoneMap`) is the whole site's conditions as a base profile plus any number of areas laid over it.
The map lives on `DraftDocument.environment` (file version **5**), so it travels in the drawing, moves
with the undo stack, and there is no second document to keep in step with the plan.

### 7a.2 A profile states only what it was told

There is no default "medium" for a property nobody set. A plan that says nothing about how wet a spot
is has not said "medium" - it has said nothing - and a check that read silence as an average would
give a green ring to a willow in a bone-dry bed with exactly the confidence it gave to a willow in a
bog. An unstated attribute is absent from `attrs`; `describe()` says "nothing stated about this spot".

The vocabulary is the plant table's, reused rather than restated: a place's light level is the same
bit a species uses for the conditions it tolerates, moisture is the same 0..2 as a species' water
need, and a place's drainage is **one** of the bits a species may tolerate as a set - so every
comparison is a bit test or a table lookup with no translation layer to disagree with itself.

### 7a.3 A zone states only what it changes, and the last one drawn wins

A zone holds the attributes somebody stated about it, `merged_over` the site's base, so marking a bed
"full shade" does not also claim to know its soil. Zones answer in the order they were drawn and the
last one containing a point is the one that applies: that is the order a designer draws in, and
"smallest area wins" would silently reorder a map as somebody edited it.

### 7a.4 The drawing is evidence, and only for two things

`ZoneMap.from_document()` reads what a plan already states about the ground: **a building is shade and
its eaves are dry; a hard surface is full sun, dry and fast-draining.** Nothing else is derived. A bed
outline, a turf area or a hatch is a design intention about what will be planted, and reading it back
as the environment would be describing the design to itself. What a drawing cannot tell you - shade
cast by a tree, soil, the fall of the land - is named in `ZoneMap.NOT_DERIVED` and shown in the Site
menu, so a grey ring everywhere has an answer.

### 7a.5 Four verdicts, because two would be dishonest

`scripts/plant_suitability.gd` (`PlantSuitability`) compares a species against a profile and returns a
verdict **plus one finding per property asked about** (`{key, label, wanted, found, outcome, because,
brief}`):

| verdict | colour | what it means |
| --- | --- | --- |
| `GOOD` | green | every property the plan states matches |
| `TOLERATED` | amber | nothing against it, but something is not ideal |
| `UNSUITABLE` | red | a property is against it |
| `UNKNOWN` | grey | the plan does not say what the ground is like |

**`UNKNOWN` is not "fine".** It is the honest state of a plan nobody has described, and it is drawn
grey rather than green because a check that never ran must never read as a pass. `ok` is
`verdict != UNSUITABLE` and `certain` is `GOOD or TOLERATED`.

**A question nobody answered is skipped, not answered.** If the catalogue entry does not say which
soils it takes, soil is not asked about at all (the gap is the catalogue's); if the *plan* does not
say what the soil is, that is reported as unknown (the gap is the designer's). The two are different
and only the second is anybody's to fix.

Hardiness is asked about **only where the place claims a zone of its own** - a frost pocket, a
sheltered court - because a site's zone is stated once for the site and a plan that has not stated it
must not turn every ring grey.

The moisture rule is horticulture, not arithmetic. Wanting *less* water than the ground holds is not
the mirror image of wanting more: a drought-tolerant plant in a wet bed rots at the crown, while a
thirsty plant in a dry bed can be carried by irrigation. So both directions can be `UNSUITABLE`, and
the milder mismatch in each direction (medium where it wants low, or medium where it wants high) is
`TOLERATED`.

### 7a.6 The ring, and where it comes from

`ViewController` owns the question - it already knows the species, the document and the cursor - and
hands `PlanCanvas` a point, a radius and a colour (`PlanCanvas.plant_ghost`); the canvas draws the
ring, a washed disc at the plant's mature spread, a cross at the exact spot, and the short reason.
The verdict is recomputed every frame while a plant is in hand, because a pan, a zoom and a menu entry
that states the ground all change the answer while the mouse stands still.

Only a **placement** writes the status line ("…is the wrong plant for the rest of the site: it wants
full sun and this spot is in full shade. 31 planted."), never the cursor: a line rewritten every frame
flickers.

### 7a.7 The report on the planting already in the ground

`PlantSuitability.audit(catalogue, yard, zone_map)` checks every plant standing in the yard and counts
each verdict, **naming the plants with no species recorded** rather than passing over them - the
shipped yard is thirty of those. Reached from the Site menu as "Check the planting", which opens the
library and writes the summary and the worst rows into its status line.

### 7a.8 Where it is reached from

The **Site** menu, between Draft and Plant: one info line saying what the ground is, **What the
ground is like...**, **Draw a ground zone...**, **Read the ground from the drawing**, and **Check
the planting**.

"What the ground is like..." opens a `Window` (`scripts/ground_window.gd`, "What the ground is like"):
the site's own light, moisture, soil, drainage and hardiness zone as five dropdowns at the top, then
**every area
of the plan the drawing encloses** - each bed, lawn, paving, existing planting and building, with its
area in square metres - each of which can be stated separately. A window rather than sets of radios in
the menu because the second half of it is a *list*, and a list of the plan's areas is the one thing a
menu cannot show.

The site's dropdowns apply as they are chosen. So do an area's, and that is a deliberate change from
the first cut of this: choosing a condition for an area **states it there and then**, because the
ground a designer is describing is the ground they are looking at, and a "chosen but not yet stated"
half-state is a state nobody asked for. **State these conditions** is the same act said out loud, and
**Take them back** returns the area to the site it sits in - which is also what choosing "not stated"
for the last stated attribute means: not a statement that says nothing, but no statement at all.

A **ground zone** is the one outline this window's subject owns rather than borrows. Ground nothing
on the plan encloses - a wet corner, a frost pocket, a strip of shade - is drawn with the polygon
tool from the Site menu (**Draw a ground zone...**): the ring becomes a zone on the map rather than an
entity on the drawing, and it is listed here beside the plan's areas and stated like them. A hand
zone is keyed `by hand:zone#<n>` under the same `HAND_PREFIX` as an area, told apart by its `zone`
layer token, which is not a layer the plan has - so `areas_of` never doubles it, and stating it twice
edits one zone.

An area is keyed by what it *is* (`ZoneMap.area_key`), so stating an area twice **edits** it instead of
stacking a second zone on it. This is what makes a hand statement override what the drawing implies: the
paving in the run below is read as full sun from the drawing and then stated as full shade by hand, and
there is still one zone for it, saying shade.

The trap the dropdowns are built around: **zero is a real moisture level** (low water), so it cannot be
the value that means "not stated" - and it *is* that value for light and zone, where 0 is not a level
anybody can state. `TerrainProfile.no_value(key)` is the one place that knows this, and
`TerrainProfile.value_stated(key, value)` the one place that reads it back. The window's dropdowns show
a stated zone's **own** statement (`stated_profile`), never the site's conditions it inherits, or
opening the window would look like an edit nobody made; the line under the list shows what the area
comes to, both halves.

### 7a.9 The tests, and what they hold down

`tests/test_terrain.gd` (13) holds the profile, the zones, the derivation and the file. Roughly:

* a new profile states nothing, and reading it back says so rather than inventing an average
* a zone lays only its own statements over the site, and a later zone wins
* a profile refuses a value that is not a value (`sun: 3` is two levels at once; `drainage: ANY` is a
  set where a place drains one way)
* a zone with no area, or one that states nothing, is named as such
* the map survives a JSON round trip as levels and not as 2.0
* the drawing states a building and a hard surface and nothing else, and reading it twice does not
  double the zones
* the ground travels in a version 5 or later file, a version 4 file gets "nothing stated", and stating the
  ground is one undo step

`tests/test_plant_suitability.gd` (18) holds the verdicts - the tomato in shade, the hosta in shade,
the willow dry and damp, the lavender in a bog, the milder mismatch tolerated in both directions, a
gap in the plan outranking a mismatch, a stated fault outranking a gap, the catalogue not asked what
it does not say, hardiness only where a zone is claimed, two metres away being a different answer, and
the audit's counts, its lines and its unnamed plants. `tests/test_ground_window.gd` (14) holds the
window: every value it offers is a value the model accepts, an area stores only what was changed,
choosing a condition states it at once, the last stated attribute taken back is no statement at all,
stating an area twice edits it rather than stacking zones, reading the drawing keeps what a person
stated, and a window with no drawing says so instead of failing; a hand zone is listed beside
 the plan's areas and stated like one, and `areas_of` does not double it. `tests/test_ground_zone_tool.gd`
(9) holds the ring drawn by hand becoming a zone rather than geometry, numbered apart, one undo step,
and dropped with the tool. `tests/test_hud_menu.gd` holds the
menu that opens it.

## 7b. Ordering the planting from a nursery

A planting list is what the drawing plants; an order is what a truck brings. The two are the same
lines seen twice, and the join is `scripts/biz/plant_order.gd` (`PlantOrder`), which is static over
the planting rows and the cost book, and `scripts/plant_order_window.gd` (`PlantOrderWindow`), which
shows them and asks the two things only a person knows.

The book prices the plant and a person names the nursery. A rate is the office's knowledge and
belongs in the book; which nursery is a fact about that business's relationships, which a shipped
book cannot carry - so every plant item in the starter book has an empty `supplier`, and the one thing
the order insists on is that somebody says who the plants go to.

`PlantOrder.CATEGORY_ITEMS` chooses a book item per **category**, not per species: `TREE` at
`plant-tree-50mm`, `SHRUB` and the vines at `plant-shrub-2g`, the perennials and herbs at
`plant-perennial-1g`, the grasses at `plant-grass-2g`. A 30 cm herb and a 2 m tree are not the same
money, and a category is the finest thing the book is arranged to price. `plan(rows, book, item_for)`
takes an override per category, so the office's own judgement beats the suggestion.

A species the book cannot price is **refused by name**, and the refusal is of the whole plan: an order
that quietly dropped a species would read as a smaller planting than the plan drew. `write_orders`
writes one DRAFT purchase order per supplier against the `PLANTING` cost code and issues nothing, so
the desk shows what the job would commit to without committing to it (business specification 8.5 and
14i).

The planting rows carry the species' **category as a number** as well as its name, which is what lets
the order price a plant by asking what kind it is rather than by matching a display string.

`tests/test_plant_order.gd` (33) holds the arithmetic and the refusals;
`tests/test_plant_order_window.gd` (22) holds the page; `tests/test_hud_plant_order.gd` (11) holds the
menu line and the write.


## 7c. Naming a plant by answering questions

The plant library is the thing you search when you know what you are looking for. A key is for the
other moment: something is growing in front of you, you cannot name it, and there is nobody to ask.
Plant menu → **Name a plant by answering questions** - the page in `scripts/plant_key_window.gd`,
the arithmetic in `scripts/plant_key.gd` - asks what you can see, one question at a time, and the
candidates come down until one plant is left. It is the person's door onto the same question a
photograph is read to answer, and like that one it is reached from the menu rather than from
anything about the drawing: it narrows the catalogue, and where the plant then goes is the planting's
business.

### 7c.1 A key asks; the catalogue's one filter answers

The temptation is to give the key its own matching, and it is refused for the reason this module
refuses every second engine: `PlantCatalogue.filter` is this program's one filter, and the browser,
the palette and every planting check already go through it. So each answer is a **criteria fragment
in that filter's own words** - a kind is `category`, a light level is `sun`, "something you would
eat" is `edible`, "not grown to eat" is `not_edible`, whether it is a conifer is `conifer` - and the
key turns the answers into one `criteria` dictionary and hands it over. Which plants are left is the
filter's answer, and a plant the browser would find is a plant the key finds.

Two criteria were added to the filter for this and are now part of its vocabulary for everybody:
`conifer`, asked of `PlantSpecies.is_conifer()` rather than of a tag, because a boxwood is evergreen
without being a conifer; and `not_edible`, the far side of the `edible` question, because "not
something you eat" is a real answer and a key that could not give it would offer a way to eliminate
the right plant.

The vocabulary is not written down twice either: the kinds are `PlantSpecies.CATEGORY_NAMES`, the
light levels are `SUN_NAMES`, the water needs are `WATER_NAMES`. So a kind added to the species table
is offered by the key the day it is added, and a question cannot come to offer a category nothing in
the list is filed under.

### 7c.2 Which question to ask next is arithmetic

The order questions are asked in is written down nowhere. Every remaining question is scored by the
**entropy of the split its answers would make of the plants still in the running**, and the most
informative question is asked first - so a garden of two trees is asked about the conifer, and a list
of thirty is asked whatever cuts it most evenly. `QUESTIONS`' own order is only the tie-break between
two equally informative questions, which is what makes the same answers ask the same thing every
time. A question that cannot narrow the field any more is passed over rather than asked.

The answers offered are only those that would still leave something (`live_options`), and each shows
how many plants it would leave. A person cannot therefore eliminate the plant in front of them by
choosing something it cannot possibly be.

### 7c.3 Three answers that are not a plant

A key can end three ways, and none of them is a failure to be hidden behind a zero:

* **One plant left** - it is named, and *Use this plant* arms it exactly as the library does, through
  the HUD's one `_arm_planting`. Naming a plant is not a third way of choosing one.
* **Several the list cannot separate** - reported as exactly that, with the plants named. Measured on
  the shipped 130-species list: four answers - a small tree, something you would eat, full sun, and
  not a conifer - leave *Amelanchier canadensis* and *Malus 'Royalty'*, which no remaining question in
  the vocabulary separates. A key that chose between them would be inventing a fact.
* **Nothing fits** - said plainly, and naming the way back out: take the last answer back.

Undo is one answer at a time, newest first, because an answer that turns out to have been wrong is
the common case. *Start again* is the other door, and it is the one somebody wants when the first
answer was wrong and everything after it followed from it.

### 7c.4 Height is asked with its warning attached

The only question whose answer is a prediction: the catalogue states the height a plant **grows to**,
so a young plant in front of somebody is honestly shorter than the number the answer matches. The
prompt says so rather than pretending otherwise, and its bands partition every size - each band's
upper bound one centimetre below the next band's floor - so no plant falls between two answers.

### 7c.5 Where it is reached, and what holds it down

Plant menu → Name a plant by answering questions. It reads the drawing only for the bed the plant is going in (§7c.9); the key itself narrows the catalogue, and where the plant then goes is the planting's business. The manual
describes it under **Identifying a plant by answering questions**, and `PageHelp` is what joins the
page to that subject.

`tests/test_plant_key.gd` (27) holds the arithmetic and the wording; `tests/test_plant_key_window.gd`
(12) holds the page; `tests/test_plants.gd` holds the two criteria the key added to the filter; and
`tests/test_plants.gd` holds the criteria the key added to the filter, and `tools/plant_key_demo.gd`
stands the real game up, opens the page through the handler the menu names, and walks the shipped list.

### 7c.6 The leaves, and the rule that makes a partly-read list safe

Five more questions read the **leaf**: `leaf_arrangement`, `leaf_complexity`, `leaf_shape`,
`leaf_margin` and `leaf_venation`, stored on `PlantSpecies` as bits from its own `ARR_*`, `CMP_*`,
`SHP_*`, `MRG_*` and `VEN_*` tables - the vocabulary a field guide's key is built from, in plain
English, so somebody who has looked at a leaf can answer without learning this program's words.
**A leaf question's key is its trait's own name**, so an answer is a criterion in exactly that
trait's words and the key, the filter and a page cannot come to call one leaf two different things.
`PlantCatalogue` gained the five criteria, read through its own `can_be`.

**Zero means not stated** - the rule `soils` and `drainage` already keep - and every entry defaults
to it, which is what makes this safe to ship against a catalogue nobody has read leaf by leaf. A
plant that states nothing about a leaf **fails every answer** to a question about that leaf, so
asking one while such a plant is still in the running would eliminate it by a description nobody
gave: the silent, wrong answer this program is arranged against. `PlantKey.askable` is the cure - a
leaf question is asked only while every plant still in the running states that leaf. The leaf
questions appear, disappear and come back as the field narrows, and a list nobody has read leaf by
leaf is simply never asked about leaves.

So the key its whole life has two halves, and which one a person meets depends on the list they
have: against a list that states its leaves, the leaf questions are usually the most informative
ones there are and are asked early; against the shipped list, which states none, they are never
asked and the key behaves exactly as it did before they existed.


### 7c.7 The flowers: a colour a person can name, and a season

Two questions ask what only a flowering plant can answer: the colour of the flowers, and the season it
flowers in. Both are held behind the same rule the leaves are - asked only while every plant still in the
running states them - which, for a flower, means only while every one of those plants flowers at all.

**A colour answer is a bucket, not a shade.** The catalogue stores the colour a nursery chose, and the
shipped list holds 125 distinct shades; `PlantSpecies.flower_colour_name` is the one rule that turns a
shade into one of `PlantSpecies.FLOWER_COLOURS`. It is used twice - the plant's own shade is bucketed by
it, and the answer a person gives is that vocabulary - so "pink" cannot mean one flower to the key and
another to the person looking at it. The rule is deliberately coarse and written down: a flower that is
nearly colourless is white, or cream when it leans warm, and otherwise the hue decides, with a very pale
red called a pink and a violet on the blue side of purple.

**The season is what a person knows.** The catalogue stores months, and `PlantSpecies.SEASONS` is the one
place those become the four seasons; `bloom_season` is the criterion that reads it. A plant flowering
from April to June is honestly "spring", and the four seasons between them are the twelve months.

Both criteria refuse a plant the catalogue says never blooms, for the same reason a leaf criterion
refuses a plant whose leaf nobody has read: a fern's stored colour is the class's default, which is a
pink nobody chose, and answering "pink" must not keep a plant that has no flower at all.


**"Not sure" is a way past a question, not an answer.** `PlantKey.UNSURE` is kept as an answer - so the
question is not asked again - and carries no criterion, so the field is not narrowed by a guess nobody
made. It is deliberately absent from every `options_of`, so it can never appear as one of a question's own
answers; a page offers it beside them, only while there is a question to pass.


### 7c.8 The drawing beside an answer

An answer may carry a drawing, and where one has been made it is shown on the button beside the words
rather than instead of them. `PlantKey.picture_for(question, option)` is the one place the rule lives: a
drawing is named for the **question and the option** - `key_leaf_venation_a_midrib_with_side_veins.png`,
because a leaf question's key is its trait's own name and an option's key is the slug of its label - and
where no file matches, the answer is offered with its words alone.

**A missing drawing is answered with nothing, never with a stand-in.** A drawing is the *definition* of an
answer: a shape charted on "how do the veins run?" is what tells a person which words describe the leaf in
their hand, so a placeholder image would be a picture of some other leaf at the moment somebody is looking
for the word. That is also why the questions were built before any of the drawings were: an answer is its
words, the drawing only helps, and a drawing appears the day its file does - which is what
`test_a_drawing_of_an_answer_is_a_file_that_is_really_there` holds.

The drawings are line art in the page's own pale ink (`#c9d2b4`-ish) on a transparent background, because
the program's theme is dark. Black ink would be invisible on it; white would vanish on a light theme.

### 7c.9 The bed the plant is going in

A key answers two different questions, and until now it answered one. "What is this plant?" is the
question somebody standing in front of an unnamed plant is asking. The other is **"what can I plant
here?"**, and the drawing can already partly answer it: `ZoneMap.profile_at` says what the ground is
like where the drawing's cursor last was - which is the bed a person had in mind on their way to the
menu, and not the menu bar the pointer is over by the time anything asks.

The page is handed that spot and says what it leaves of the list - *"1 of 5 plants suit the front bed
(part shade, medium moisture)"* - with two buttons: **Only the plants that suit this spot**, and
**Every plant in the list** to widen back.

**It never narrows itself, and that is the decision worth stating.** A key opened to name the plant
already growing in front of somebody must not drop that plant for not suiting the bed it is
demonstrably living in - and that plant is exactly the one a designer most wants named. So the whole
list is where the page starts, narrowing is a deliberate press, and the count is said either way.

**The verdict is `PlantSuitability`'s own.** `PlantKey.suiting` keeps the plants whose `check` came
back `certain` - good or tolerated - which is the same predicate the survey import counts "suiting
where it stands" with, so a key and that report cannot come to different answers about the same bed.
No second suitability rule is written for the key.

Three refusals, each naming what is missing rather than showing a zero:

* a spot the plan has **not described** leaves the whole list in the key and says so - silence is not a
  pass, and a key narrowed to an undescribed spot would be a page with no plants on it at all;
* a spot that states neither the light nor the water **cannot be checked at all**, and
  `PlantSuitability.gaps_at` is what names which of the two is missing - so the page reports a gap in
  the plan rather than "nothing suits this spot", which would blame the plants for it;
* a spot nothing in the list suits leaves the key on the whole list, and the button says which fact
  stopped it.

A plant the plan cannot **judge** - one that names a soil the plan is silent about - is not counted as
suiting, for the same reason `UNKNOWN` is never drawn green. Narrowing therefore shows fewer plants
than "all those that would live here", the count is said out loud, and one press puts the whole list
back.

### 7c.10 From a photograph to the key

A reading that comes back with several names is a **choice**, and a choice of plants is what a key is
for. So the capture page offers a button - **Settle which of these it is** - and pressing it puts the
reading into the key, which then asks only the questions that tell those plants apart.

**The offer is a button on a page, not a menu entry**, and both reasons are load-bearing. The reading is
in hand on that page and nowhere else, so a menu entry would have to reach back for it. And the manual
guard builds a regular expression out of every menu title (`test_help_doc.gd`), so a menu entry
advertising the seed would have to say so in its own title, where a button says it in its own words.

**A shortlist seeds the field; it does not answer a question.** Letting the reading pre-answer, say, the
flower colour was rejected: the key would then assert what the model only guessed, and it would fix
which question came first. Seeding the field leaves `PlantKey.next_question` free to pick the
**highest-entropy question among the candidates**, which is the whole point of a key.

**The join from a name to a species belongs to `PlantIDResolver`**, and the page asks it of `resolve`
rather than `resolve_identification`. That second one applies the **confidence floors a record needs**; a
shortlist is not a record, and dropping a candidate for being uncertain would drop the very plant the key
is opened to ask about. The page hands the key **ids** and never names, so what a model said becomes a
species in exactly one place.

**One plant is not a choice, and neither is a reading this list cannot answer.** The button is built only
while more than one of the plants the reading named is in the catalogue: a key of one plant has nothing to
ask, and a key of none is a broken page. `PlantKey.among` skips ids the list does not have rather than
emptying the field, and `PlantKey.shortlist_words` is the one sentence that says what happened - where the
list came from, how much of it this catalogue knows, and what the key will do with it.

**The two narrowings compose.** A photograph says which plants it could be; a bed says which of those will
live here; `_rebuild_field` applies the shortlist first and the spot to what is left, so neither can undo
the other. The spot half refuses to empty the field - when none of the shortlist suits the spot, only the
shortlist narrows - and the line above the questions says both facts either way.
### 7c.11 Stating the leaves a list does not

The leaf questions are latent on the shipped list, and this is the way out of that: by **stating**
leaves, never by guessing them. `PlantSpecies` already carried the five traits - `to_dict` always
writes them and `from_dict` reads them as integers with zero meaning not stated - so storage was never
the missing piece. What was missing is that `ARR_OPPOSITE` is 2 and nobody remembers that from one week
to the next.

**The words are the file.** `LeafReadings` holds a readings file keyed by species id whose values are
the words a field guide uses:

    {
      "readings": {
        "acer-rubrum": { "leaf_arrangement": "opposite", "leaf_margin": "lobed" }
      }
    }

`words_to_bits` looks each word up in the trait's **own** table (`PlantSpecies.names_for`), so a word
and its value cannot come apart; `PlantSpecies.set_leaf_trait` is the writing half of the one `match`
`leaf_trait` reads, so a trait cannot be read under one name and written under another. A word a trait
does not have is refused **with the words it does have**, and a leaf this program does not have is
refused by name. Several words may be given - a trait is a set, and a plant takes two arrangements the
way it takes two kinds of light.

**Why not through the import, and why not an editor.** `PlantCatalogue.import_json` skips an id the
catalogue already holds, and a record read back through `from_dict` **defaults every field it omits** -
so a row stating only leaves arrives with no height and `problem()` refuses it as a plant that cannot
be drawn. A leaf is a fact about a plant that already exists rather than a new version of it, so
`apply` merges onto the plant in hand, and an id the list does not hold is **named and left alone**: a
plant invented out of a leaf would be a plant nobody chose. §8's rule stands besides - a catalogue is
edited in a spreadsheet or added to by an import, never in an editor pane - so the authoring path is
`tools/leaf_reading.gd` and a sheet in `user://`, and what it writes is
`res://data/plants/leaf_readings.json`: data somebody can read and diff, committed the way
`nursery_list_more.json` is.

**The line says what the list states, not what it lacks.** `LeafReadings.states_words` counts the
plants stating each trait and words it once. A list that states nothing is written out - *the list
states no leaf for any of its 130 plants, so the leaf questions are not asked* - rather than left as
five noughts, because the state this program ships in is a fact about the list and not an absence. The
key page shows that sentence and the module words it, so the figure and the sentence that gives it
away are one arithmetic. The word **coverage** is deliberately not used: it already means irrigation,
plot extent and closeout here.

**Nothing ships stated.** The readings file is absent until somebody has read a leaf, a blank cell is
not a statement, and the tool drops its own name column rather than passing it on as a leaf. No leaf
trait in this repository was written by a guess.
## 8. What is not built

The ground can be **read from the drawing** (§7a.4), stated for the site and for any area the
drawing encloses (§7a.8), and stated for ground the drawing does not enclose by drawing a
**ground zone** by hand (§7a.8).

* **Editing a species in the library.** The browser reads; a catalogue is edited in a spreadsheet or
  added to by an import. That is the design, and an editor pane is a decision to revisit rather than
  an omission to fill.
* **Photographs.** `thumbnail` is read and drawn when present; nothing generates or files them.
* **Naming the shipped yard's plants.** Its 30 props have no species, and guessing which one is which
  would be inventing data. It is a five-minute job in the editor for whoever knows the garden.

## 9. The tests, and what they hold down

* a species survives the file as whole numbers; nothing coerced is a float
* a filter for January finds the plant that blooms across the new year (`test_plants.gd`)
* a filter that is not understood is refused rather than ignored
* a catalogue takes plants and refuses a second one with the same id
* a model is loaded once however many plants share it
* the shipped list is sound and every form it names is on disk
* a planted species is as big as the catalogue says - the plan's *own* footprint function reports its
  spread, which is the proof the link is real and not a number that happens to be stored
* a species whose scene is missing is refused, naming the scene, rather than being a click that does
  nothing
* a planted plant is one object in both views: in the `placeable` group *and* in the `Plants` subtree
* the planting list counts what is standing and names what it cannot
* the browser will not describe a plant its grid is not showing
* a species with no photograph is drawn as the symbol the plan uses, and every plant states a
  symbol out of the vocabulary the plan can draw (`test_plant_symbols.gd`)
* a spruce and a maple - the same prop, the same category - are two pictures rather than one
  disc, and a conifer's crown differs from a canopy's where a needle ends
* a conifer is a conifer because its genus is one: a boxwood is evergreen and is not, so the
  question is asked of the botanical name rather than of a tag
* the plan and the picture in the grid reach the same symbol through the same call, plant by
  plant, so the grid cannot show a shape the drawing does not use
* a round symbol is drawn round whatever its prop's footprint says, and an oblong one keeps the
  prop's proportions (`shape_for`)
* a symbol is drawn from a figure whose every part the two renderers know, and a figure is built
  once rather than per frame
* the plan's own table names only symbols this module knows, and every symbol has inks
* a planted node carries its symbol, so the plan draws a conifer without knowing what a spruce
  is
* the swatch is the pigment the painted plan would use, and a bed is drawn as an oblong rather than a
  disc (found by reading every pixel, not by sampling one)
* the two pictures of a plant are one picture: the grid and the palette share `PlantIcons`, and
  clearing the cache really clears it (`test_plant_icons.gd`)
* nothing in the palette panel takes the keyboard, the list does not search, and a panel with no
  catalogue says so rather than failing (`test_plant_panel.gd`)
* a catalogue bigger than the panel lists is capped, and says how much of itself it is not showing
* a plant that is not on the list cannot be chosen, and choosing it does not silently pick another
* a tag the catalogue no longer carries falls back to every plant rather than to an empty panel
* a row clicked while a plant is in hand replaces it, a row clicked with nothing in hand asks for
  nothing, and clicking the plant already in hand is not a change (`test_plant_panel.gd`)
* a bigger starter list is added through the module's own importer, and running it twice adds nothing
  the second time: every addition is in the shipped list, an id already there is refused rather than
  replaced, and an entry already in the list is left alone (`test_plant_expansion.gd`)
* a species that states soil or drainage states a value the vocabulary knows and keeps it through a
  file, and one that states neither is still valid (`test_plant_suitability.gd`)
* a fill puts the plants no closer than the spacing, checked against every pair of them rather
  than against the grid they were built from: a test that read the grid back would agree with a
  fill that was wrong (`test_plant_spacing.gd`)
* staggered rows are sqrt(3)/2 of a spacing apart with alternate rows half a spacing across, no two
  plants are closer than they would be in square rows, and no plant stands on the outline itself
* what a fill plants is what the schedule then counts: every plant carries its species, stands at
  `Vector3(x, 0, y)`, and the count agrees to the one
* the refusals are refusals and not silent half-jobs: a spacing tighter than a plan draws, an
  outline enclosing no ground, a bed with no room for the plant, and a bed wanting more than a
  fill puts down
* the beds offered are the beds and the planting already there, and not the paving, the lawn or
  the house
* the fill controls take no keyboard, the button is dead until there is both a plant and a bed and
  says in its tooltip which is missing, a report stays until a new plant is chosen, and a bed the
  drawing no longer encloses cannot stay chosen (`test_plant_panel.gd`)
* the list reaches the plotted sheet: a species is one row with its count beside it, and the
  plants the catalogue cannot name are one row that says so rather than being dropped
  (`test_sheet_export.gd`)

* every answer becomes one of the catalogue filter's own criteria, so a key and the browser cannot
  come to disagree about which plants match (`test_plant_key.gd`)
* a conifer is a question about the genus and not about a tag, and "not grown to eat" is the other
  side of the food question, both asked of the plant itself (`test_plants.gd`)
* the question asked is the one that splits the field most evenly rather than the one written down
  first, and a question that cannot narrow the field is passed over
* a plant the list cannot separate is reported as such, naming the plants, rather than chosen between
* an answer that fits nothing says so, and taking the last answer back leaves the answers before it
* the height bands leave every plant in exactly one band, so no plant falls between two answers
* the page offers only answers that would still leave something, and a button that cannot act is
  disabled and says on its tooltip what it is waiting for (`test_plant_key_window.gd`)
* the shipped 130-species list is walked from the Plant menu through the handler that menu names
  (`tools/plant_key_demo.gd`)

* a plant states its leaves as bits or states nothing about them, an out-of-vocabulary bit is
  refused by name, and a record written before the leaves existed is simply not described
  (`test_plants.gd`)
* a leaf criterion finds the plants that are described and leaves out the ones nobody has read -
  which is why the filter's rule is not enough on its own
* a leaf question is asked only while every plant still in the running states that leaf, and comes
  back the moment an undescribed plant has been answered out of the way (`test_plant_key.gd`)
* the leaf answers are the species' own vocabulary, one table per trait, so a value added to a leaf
  is offered by the key the day it is added
