# The plant database

A landscape plan is mostly plants, and until this module existed the planner had props: three
scenes - a tree, a shrub, a flower bed - placed by hand in `yard.tscn`. What it did not have was a
*species*: a red maple that is hardy in zone 3, spreads 9 m, blooms in March, wants sun and average
water, and is drawn as a tree. This module is that, and everything that hangs off it.

**Status.** Built: the catalogue, the placement link, the planting list, the browser. 46 tests in
`test_plants.gd` (20), `test_plant_placement.gd` (11) and `test_plant_browser.gd` (15), plus the
Plant menu in `test_hud_menu.gd`.

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
| `res://data/plants/nursery_list.json` | the project | the 17 species shipped with it |

Collections are **apart** from the catalogue on purpose. A catalogue ships and an import replaces it
wholesale; nobody's "front bed" list may be replaced with it.

The first run has no catalogue of its own, so the shipped list is the list - read from `res://` and
held in memory until something changes it, at which point it is written to `user://`. A shipped list
stays a shipped list and a catalogue somebody has edited is theirs.

Writes go through a temporary file and a rename, as a drawing and a cost book do: a save that fails
must not leave a shorter plant list where the real one was.

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
| `form` | scene path | the prop it is drawn as - its 2D symbol *and* its 3D model |
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
photographs, and a grid of empty boxes is one nobody can look through. Swatches are cached by form
and category - thirty pictures, not four thousand - and what tells two trees apart in the grid is a
*tint* from the species' bloom colour, not another texture.

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
    | Autumn fern                   |  ItemList, ICON_MODE_LEFT, 26 px swatches
    | Black-eyed Susan              |  by common name, one tag drop-down
    | Christmas rose                |  capped at MAX_LISTED (40)
    | ...                           |
    +-------------------------------+
    17 species.                        Status
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

`MAX_LISTED` is 40 and the status line says so - "Showing the first 40 of 120. Open the library to
search." A panel that quietly showed forty of somebody's four thousand plants would be a worse answer
than one that admits it is not the browser.

The pictures come from `PlantIcons` (`scripts/plant_icons.gd`), shared with the browser, so the two
cannot show one plant two ways: the form decides the shape, the species' bloom colour decides the
tint, and the cache is keyed "form|category" rather than by species - seventeen species drawn as three
props are three pictures, and four thousand are thirty.

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

Choosing a plant arms it and closes the library, so the very next click is on the plan. It stays armed
afterwards: a bed is a dozen clicks, not a dozen trips back. Escape puts it away. Planting and the
drawing tools never both own the left button - arming a plant puts the tools away.

## 8. What is not built

* **A planting schedule on a sheet.** `schedule()` and `schedule_text()` exist and are tested; nothing
  plots them yet. Sheet furniture has a cross-reference table and a key, and a planting plan wants a
  third.
* **Editing a species in the library.** The browser reads; a catalogue is edited in a spreadsheet or
  added to by an import. That is the design, and an editor pane is a decision to revisit rather than
  an omission to fill.
* **Photographs.** `thumbnail` is read and drawn when present; nothing generates or files them.
* **Naming the shipped yard's plants.** Its 30 props have no species, and guessing which one is which
  would be inventing data. It is a five-minute job in the editor for whoever knows the garden.
* **Sun and water from the drawing's own site.** A species knows what it needs; nothing yet checks it
  against the bed it is put in.

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
* a species with no photograph is drawn as the symbol the plan uses, and two species drawn as the same
  prop in the same category share one picture
* the swatch is the pigment the painted plan would use, and a bed is drawn as an oblong rather than a
  disc (found by reading every pixel, not by sampling one)
* the two pictures of a plant are one picture: the grid and the palette share `PlantIcons`, and
  clearing the cache really clears it (`test_plant_icons.gd`)
* nothing in the palette panel takes the keyboard, the list does not search, and a panel with no
  catalogue says so rather than failing (`test_plant_panel.gd`)
* a catalogue bigger than the panel lists is capped, and says how much of itself it is not showing
* a plant that is not on the list cannot be chosen, and choosing it does not silently pick another
* a tag the catalogue no longer carries falls back to every plant rather than to an empty panel
