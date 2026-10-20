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
`test_hud_menu.gd`, the palette in `test_plant_panel.gd` (17) and the expansion in
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
afterwards: a bed is a dozen clicks, not a dozen trips back. Escape puts it away. Planting and the
drawing tools never both own the left button - arming a plant puts the tools away.

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
* the ground travels in a version 5 file, a version 4 file gets "nothing stated", and stating the
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
