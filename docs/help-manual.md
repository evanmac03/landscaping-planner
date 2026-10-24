# The manual — design

An in-app manual, opened from the **Help** menu, that describes what the program
is and how to use each part of it. It exists because the program is broad — fourteen
menus, ten drawing tools, plants, water, light, estimating, jobs, billing, presenting,
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

The box is what the keyboard is here *for*, so it is also where the up and down arrows
walk the contents: they are not keys a single-line box uses, and taking them costs a
typist nothing. Section headings are stepped over — a heading is furniture, not a
subject — and either end stops rather than wrapping, because a manual has a first
subject and a last one. `move_selection` is the rule; the tests drive it off-tree, and
the live pass presses real arrow keys at the open window to prove the key reaches the box.

The window also fits the screen it lands on. `min_size` is a floor — 960×720, big enough
for a page of prose and a list of twenty subjects — but a floor taller than the display
would push the page's own buttons off the bottom, so `clamped_minimum` brings it down to
the screen's usable rect and `open` applies it before `popup_centered_clamped` centres the
page. A screen that reports nothing (a headless run) leaves the floor at its full size:
the page is made smaller for want of room, never for want of knowing.

## 4. Finding a subject

The first thing somebody does with a manual this long is look for a word in it, so the
search box sits above everything. A search is matched lowercased against the title, the
body *and* the section the subject is filed under, so it is neither case-sensitive nor
limited to body text — somebody typing "invoice" is asking about a subject, not about a
mention. A search narrows the contents list rather than the topics, which is what makes
emptying the box the way back to the whole manual without re-reading anything.

The results come back **best first**, on the same rule the command palette searches its rows
by: a subject whose *name* starts with the word beats one whose name only contains it, either
beats a subject whose prose discusses it, and all of those beat a subject that is only *filed*
where the word is written — a subject that comes back because its heading names the word need
not say the word itself. Where the palette sorts by the menu a command lives under, this sorts
by the section a subject is filed under, and a subject has one thing a command in a bar has not
got: prose, which is ranked above the section because a subject that discusses a thing is more
about it than one that merely sits near it. Within a tier the reading order is kept, so the same
search always gives the same list.

That last tier is why the page says a search *matches* rather than that every subject it found
*mentions* the word, and the whole rule is why typing "water" opens on "Water: irrigation"
rather than on whichever subject happens to say water first, which is what the reading order
used to do.

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
| Finding any command: the palette | every command in one box, Ctrl+P, what a row says |
| The three views | 2D plan, 3D overhead, ground view and how to move between them |
| Drawing: the tools | each drawing tool and the key that selects it |
| Snapping and precision | object snap, exact entry, constraints |
| Editing shapes | offset, trim, extend, fillet, erase, rotate, select bands |
| Layers, units and the site | layers, locking, metric/imperial, the site |
| The ground under the garden | stating ground conditions per area — the plant-suitability feed |
| Stating levels and falls | spot levels, contours and slope arrows, and the check that reads them back |
| Importing somebody else's file | survey, DXF, OSM, LandXML — the one shape table |
| Tracing over a picture | a scan or a photograph under the plan - kept beside the drawing, placed across the ground, never plotting or snapping |
| Plants | the library, placing, filling a bed, labelling, the 3D models |
| Food: what will crop here | whether a crop gets the sun it needs in a stated bed, and the site's longest day as the ceiling |
| Food: what to grow here next | crop rotation and companion planting — what follows what, and what grows beside what |
| Food: what's ready when | the harvest calendar — what the plant list records as ready in a month |
| Food: when to sow | sowing, the last safe day, and succession sowings before the frost |
| Food: how much to plant | how many plants feed a household, and the hand-off to the nursery order |
| Ordering the plants from a nursery | this drawing's planting priced from the book, and a draft nursery order |
| Water: irrigation | supply, laying heads out, zones, the schedule |
| Light: garden lighting | transformer, fixtures, circuits, cover |
| What it costs: takeoff and estimate | the drawing as the takeoff, the priced estimate |
| Leads and the pipeline | leads, stages, win/loss, the funnel |
| Jobs, crews and the schedule | handing an estimate to a job, booking, clashes |
| Billing and the books | rates, milestones, invoices, payments, the ledger |
| Presenting the garden | the painted plan, stills, the proposal page |
| The sun and the shadows | a season of moments, what a stated height casts, and a still for each |
| Sheets and plotting | the sheet set, sizes, scale, plotting |
| Working with others | presence — a session started on purpose |
| Undo, revisions and where your files are | the gesture history, revisions, the copy kept for unsaved work, `user://` |
| What the drawing has said | the status-line history — the last sixty things the drawing said, newest first |
| Keys | the key reference itself, derived from the input map |

Every menu in the bar has something written about it: a test checks it.

---

## 6. The shape of a subject

Two things about the *shape of a subject* are *structure* rather than prose, and each is a table with
a test holding it to the written topics. The third structural table - which pictures a subject is shown
with - has a section of its own below.

- **`SECTIONS`** groups the flat list of subjects under headings — eight of them — so the contents
  is scannable. The order of the subjects is still `SUBJECTS`: the sections are that list split up
  and not rearranged, and a test checks exactly that.
- **`SEE_ALSO`** gives a subject the ones to read next, drawn as buttons under its body. A link
  names a *subject* rather than a row, so it still works while a search is hiding it. The food
  subjects form a chain — what will crop, what to grow next, what is ready when, when to sow, how
  much to plant, and the order that comes out of it — and the page can be walked back and forward
  along what has been read.

**A subject is one subject.** This is the one rule with a number in it
(`tests/test_help_doc.gd::test_no_subject_is_a_wall_of_prose`): no body past 3,000 characters,
and no paragraph past 700. It exists because the food garden was once a single 4,798-character
subject covering six pages — every fact in it true, every other guard passing, and nobody able to
find the sowing in it. The fix was to split it and name the pieces, and that is what to do again if
a subject outgrows the cap.

## 7. The files

| File | What it is |
|---|---|
| `scripts/help_doc.gd` | the content — one topic per subject, the `SUBJECTS`/`SECTIONS`/`SEE_ALSO`/`PICTURES` tables, plus search and index helpers |
| `scripts/help_window.gd` | the page — contents with headings, read-next links, walking back and forward, search, body, status |
| `scripts/hud.gd` (`_build_help_window`, `help_topics`, `open_help_window`, …) | the join and the Help-menu entry |
| `tests/test_help_doc.gd` | the content is clean and complete, and held to every table it claims — tools, menu names, stated counts, sections, cross-references, keys, the search order, size, the pictures |
| `tests/test_help_window.gd` | the page behaves — search, selection, headings, read-next links, back and forward, keyboard, pictures, close |
| `tests/test_hud_help.gd` | the HUD offers it, hands it the right topics, and it takes nothing from the scene |
| `tools/help_demo.gd` + `scenes/help_demo.tscn` | a live look at the page on the real program |
| `tools/help_shot.gd` + `scenes/help_shot.tscn` | takes the manual's pictures off the running program, one webp per subject, into `assets/help/` |

## 8. The pictures

Twenty-nine of the thirty-one subjects are shown a picture, and the picture is of the **program**: a
shot of the real page, panel or view the prose is describing, taken off the running window rather than
drawn. A reader who has just been told that `Draft > Snapping...` exists wants to see where it is.

Three things make this work rather than clutter a page:

- **The picture is a file, read as bytes.** `HelpWindow.decode` is handed the bytes `FileAccess` read
and decodes them by the file's own kind, rather than handing `Image.load_from_file` a path. A picture
that ships *inside* the program lives in its pack file, and only `FileAccess` can see into one:
reading it by path works in the editor and stops working in a built copy, which is the worst way for
this to fail. The first few bytes are checked against the mark that kind of file begins with *before*
the engine is asked to read them, because the image loaders complain loudly about bytes that are not
a picture - and a stray file in the pictures folder must not fill the console with reasons it is not
one. A picture that cannot be read answers `null` and the page carries on without it; the path is
asked for once, whatever the answer.
- **Which pictures a subject is shown with is a fourth table** (`HelpDoc.PICTURES`), resolved by
`_annotate` into paths on the topic, exactly as the section and the cross-references are. The page is
handed what it is to show and never learns where the manual keeps its pictures. A test holds every
name against the file system *and* against `SUBJECTS`, because a picture filed under a name nobody
has is a picture nobody will ever be shown.
- **The row is given a definite height** (`PICTURE_HEIGHT`), and each picture is fitted inside it at its
own proportions. This is not a style choice. A container cannot lay out a child that will not be
sized until it has been laid out, so `EXPAND_FIT_WIDTH_PROPORTIONAL` left the row with **no height at
all**: the picture was on the page, `shown_pictures()` was non-empty, and every assertion passed
while nothing was drawn. `tests/test_help_window.gd` now asserts the row's own minimum height, which
is the one thing about a picture a test can see.

The pictures are **taken, not drawn** (`tools/help_shot.gd`). It instances the real `main.tscn`, opens
each page through the HUD's own door, and saves the viewport - so the picture is the program, and
re-taking one is running a scene rather than commissioning an artist. They are saved lossy at WebP
quality 0.9, a sixth of the PNG size for a photograph of a garden, without hurting the small text that
is the point of a picture of a page. Regenerate the whole set by running `res://scenes/help_shot.tscn`;
`PROBE_SUBJECT` shoots the manual itself open on one subject, which is how the three-picture strip was
looked at.

Not every subject is shown one. A picture earns its place by showing a reader where something *is*, and
a subject that describes a way of working rather than a page - **Editing shapes**, **Sending the drawing
out** - has nothing to point at.
