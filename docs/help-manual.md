# The manual — design

An in-app manual, opened from the **Help** menu, that describes what the program
is and how to use each part of it. It exists because the program is broad — fourteen
menus, nine drawing tools, plants, water, light, estimating, jobs, billing, presenting,
plotting — and none of that breadth is discoverable from the screen alone. The key
reference (`Help > Drawing keys`) answers *which key*; this answers *what is this and why
would I want it*.

---

## 1. Content is data, the page is a screen

The manual is split in two on purpose, and the split is the same rule that keeps the
layers, the plant catalogue and the bookkeeping tables honest:

- **`scripts/help_doc.gd`** (`HelpDoc`) is the **content**. It is one static table of
  subjects — a title and a body of plain prose each — and knows nothing about any window.
  Its `SUBJECTS` list names every subject in reading order, and a test checks that every one
  of them is a clean title with a body under it and that the manual documents exactly the
  subjects it names.
- **`scripts/help_window.gd`** (`HelpWindow`) is the **screen**. It is handed topics and
  shows them: a contents list, the chosen subject beside it, and a box to search the whole
  thing with. It knows nothing about any one subject. A page that knew its own contents
  would be a second copy of them.

`scripts/hud.gd` is the join: `help_topics()` is `HelpDoc.topics()` plus one more subject,
`Keys`, whose body is `keys_text()` — the very string the key reference panel shows.

## 2. The keys are derived, not written twice

The one subject the manual does not carry as prose is the key reference. It is built by
`keys_text()`, which reads the input map and the tool tables — the same string the
`Help > Drawing keys` panel shows — so the manual **cannot name a key that does nothing**.
The half worth deriving is derived; there is no fourth copy of the bindings to drift.
`KEYS_TOPIC := "Keys"` is the subject it lives under, appended after the manual's own
topics. A test compares the body byte for byte against `keys_text()`.

## 3. A window, and the keyboard

The page is a `Window`, for the one reason a window exists anywhere in this HUD: it has a
field to type into, and a text field is the one thing the HUD may not own outside a
window. Everything inside is behind that boundary — the contents list and the prose are
`FOCUS_NONE`, so no key of the drawing is taken from them, and the search box is the only
control that may hold the keyboard. The same rule the plant library and the ground window
keep.

The page is built by hand and built once (`build()` is idempotent, and callable off-tree so
a test can drive the same controls the program shows), and it ends in `hide()` like every
other page a `Window` node defaults to visible.

## 4. Finding a subject

The first thing somebody does with a manual this long is look for a word in it, so the
search box sits above everything. A search is matched lowercased against the title *and*
the body, so it is neither case-sensitive nor limited to body text — somebody typing
"invoice" is asking about a subject, not about a mention. A search narrows the contents
list rather than the topics, which is what makes emptying the box the way back to the whole
manual without re-reading anything.

A search that finds nothing says so in those words and turns the page to a `Nothing found`
body — it does not show a near miss. A page handed **no topics at all** says the manual is
empty, which is a different claim from a search that found nothing, and it is careful not
to blame the search box for it.

## 5. Where the entries point

The subjects are written to match how a person actually moves through the program, and to
say what each menu is *for* rather than only listing its rows:

| Subject | What it covers |
|---|---|
| What this program is | the one model, three views, where things live |
| The three views | 2D plan, 3D overhead, ground view and how to move between them |
| Drawing: the nine tools | each drawing tool and the key that selects it |
| Snapping and precision | object snap, exact entry, constraints |
| Editing shapes | offset, trim, extend, fillet, erase, rotate, select bands |
| Layers, units and the site | layers, locking, metric/imperial, the site |
| The ground under the garden | stating ground conditions per area — the plant-suitability feed |
| Importing somebody else's file | survey, DXF, OSM, LandXML — the one shape table |
| Plants | the library, placing, filling a bed, labelling, the 3D models |
| Water: irrigation | supply, laying heads out, zones, the schedule |
| Light: garden lighting | transformer, fixtures, circuits, cover |
| What it costs: takeoff and estimate | the drawing as the takeoff, the priced estimate |
| Leads and the pipeline | leads, stages, win/loss, the funnel |
| Jobs, crews and the schedule | handing an estimate to a job, booking, clashes |
| Billing and the books | rates, milestones, invoices, payments, the ledger |
| Presenting the garden | the painted plan, stills, the proposal page |
| Sheets and plotting | the sheet set, sizes, scale, plotting |
| Working with others | presence — a session started on purpose |
| Undo, revisions and where your files are | the gesture history, revisions, `user://` |
| Keys | the key reference itself, derived from the input map |

Every menu in the bar has something written about it: a test checks it.

---

## 6. The files

| File | What it is |
|---|---|
| `scripts/help_doc.gd` | the content — one topic per subject, plus search/index helpers |
| `scripts/help_window.gd` | the page — contents, search, body, status |
| `scripts/hud.gd` (`_build_help_window`, `help_topics`, `open_help_window`, …) | the join and the Help-menu entry |
| `tests/test_help_doc.gd` | the content is clean and complete |
| `tests/test_help_window.gd` | the page behaves — search, selection, keyboard, close |
| `tests/test_hud_help.gd` | the HUD offers it, hands it the right topics, and it takes nothing from the scene |
| `tools/help_demo.gd` + `scenes/help_demo.tscn` | a live look at the page on the real program |
