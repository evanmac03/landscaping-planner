# Landscaping Planner - instructions for an agent working in this repository

A landscape-design tool written in **Godot 4.7, GDScript only**: draw a site plan to scale, place
plants from a nursery catalogue, price the work, and present the design. Roughly 186 scripts under
`res://scripts`, 213 test files under `res://tests`, and twelve specifications in `docs/`.

There is no build step and no compiled language in the project. GDScript is read at run time, so
"does it work" always means "does the suite pass".

## Read the specification before you change a subsystem

`docs/` is the design authority, and each file is the reasoned record of a module - what it does,
why it does it that way, and what was rejected. Read the one for the area you are touching:

| spec | what it covers |
| --- | --- |
| `docs/drafting-subsystem-spec.md`, `docs/drafting-module.md` | the drawing: model space, tools, layers, survey import |
| `docs/plant-database-spec.md` | species, catalogue, symbols, placement, suitability |
| `docs/field-capture-spec.md` | the field capture: photographs, stated measurements, the manifest and the import |
| `docs/food-garden-spec.md` | the food garden: sun, rotation and companions, the calendar, the season, sowing, yield |
| `docs/business-operations-spec.md` | jobs, estimates, billing, ledgers, analytics |
| `docs/visualization-subsystem-spec.md` | painted plans, proposals, render batches, walk-throughs |
| `docs/irrigation-subsystem-spec.md`, `docs/lighting-subsystem-spec.md` | those two modules |
| `docs/workflow-efficiency-spec.md` | the quality-of-life features |
| `docs/help-manual.md`, `docs/github-releases.md` | the in-app manual, and the release workflow |

## The shape of a feature

Every feature here has the same six parts. A change that adds one and not the others is not finished:

1. **The model** - one or more `class_name` scripts, `extends RefCounted`, with the arithmetic in
   `static` functions that need no scene, no node and no file. This is the part tests hold down.
2. **The page** - a `<X>Window extends Window` in a scene, which takes its model and states what it
   cannot work out rather than showing a zero.
3. **The menu entry** - the HUD (`res://scripts/hud.gd`) is where a person reaches it. A page nothing
   opens is a page nobody has.
4. **The tests** - `res://tests/test_<module>.gd`, one file per module.
5. **The manual** - a subject in `res://scripts/help_doc.gd`, so the in-app Help describes it.
6. **The specification** - the section in `docs/` that says what it is for.

## Conventions - how this project is written

- **GDScript, Godot 4.7.** A file opens with `class_name X` then `extends Y`; the file name is the
  snake_case of the class name, and there is one class per file.
- **Everything is typed** - members, parameters and return types. `var x: Node = get_x()`, never
  `var x = get_x()`.
- **Pure logic is `static` on a `RefCounted` class**, so a whole module is testable with no scene, no
  node and no file. `Survey`, `DraftUnits`, `BitMaskUtils`, `PlantSymbols` and `FieldManifestExporter`
  are all written that way.
- **There is exactly one of each thing.** One measuring engine (`Takeoff`), one survey engine
  (`Survey`), one symbol vocabulary (`PlantSymbols`), one catalogue (the HUD's `plant_list()`), one
  place that words an area (`DraftUnits.format_area`). Grep before you write: a second engine that
  can disagree with the first is the defect this project spends the most effort avoiding.
- **JSON is the interchange format** for data a person or another program edits; a `.tres` is only
  ever a runtime handle (`PackedScene`, `Texture2D`). A dictionary that came out of
  `JSON.parse_string` is deliberately left untyped, because every number returns as a float and
  nothing comes back typed, so a round-tripped record cannot be compared with `==`.
- **Writes go through a temporary file and a rename**, so a save that fails never leaves a shorter
  file where the real one was.
- **The model is metres as a double.** Imperial exists only as a display and entry format - no
  geometry is ever stored in feet.
- **Undo is a named, serial-numbered gesture** (`DraftGestureHistory`), never a snapshot of state.
  One gesture is one action a person took, and its serial is what joins it to the revision log.
- **Autoloads are allowed, and there is exactly one.** It is the MCP toolkit's runtime server
  (`MCPRuntimeServer`, `addons/godot_mcp_toolkit/runtime/mcp_runtime_server.gd`), registered by that
  addon's own editor plugin. It is the one thing an autoload is genuinely for here: a development
  bridge that has to be reachable from outside the running game. Everything else is unchanged -
  whatever a script needs is still handed to it by the scene as an `@export var x: SomeClass`, which
  Godot wires as a `NodePath` in the `.tscn`, and a second autoload has to earn its place the way this
  one did.
- **An autoload has to be inert in an export.** It must destroy itself on `Engine.is_editor_hint()`
  or `not OS.has_feature("editor")` - never on `is_debug_build()`, which is true in a debug export -
  so a shipped build neither listens nor logs. The toolkit's runtime server is the worked example, and
  its own export plugin nulls the autoload for the bake besides.
- **A page is a `Window`, a model is a `RefCounted`.**
- **Human-facing strings are plain sentences**, and a refusal names what is missing. There is no
  `Error: invalid input` in this program, and no message that could have been written by a compiler.
- **Comments explain why, not what.** A `##` doc comment on the class opens with one sentence saying
  what the thing is, in the author's own words. That sentence is read by tooling, so keep it complete
  and do not wrap it into a fragment.
- **Match the local style.** This codebase is written in long, reasoned prose; a bare
  `# TODO: fix` stands out and will be sent back.

## Tests

- One file per module: `res://tests/test_<module>.gd`.
- `extends Node`, with several methods named `test_*`; helpers are prefixed `_`.
- Classes are preloaded **by path** (`const X := preload("res://scripts/x.gd")`), not by global name.
- A test creates no scene and no node unless the test is *about* a scene. Any node it does create is
  freed in the test, or the runner reports resources in use and fails the run.
- Prefer a sword-proof test name that says the rule: `test_a_payment_larger_than_the_balance_is_refused`
  beats `test_payment_validation`.
- Run the whole suite, not just the file you touched. It is the arbiter, and it is fast.

## Running things

- **The game**: open the project in Godot 4.7 and run `res://scenes/main.tscn` (also
  `application/run/main_scene`). The renderer is `gl_compatibility`, the physics engine Jolt.
- **The tests**: `res://tools/run_tests.tscn`, headless and with no editor or plugin needed -
  `GODOT_MCP_RUNTIME=0 Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tools/run_tests.tscn`.
  That variable keeps the MCP toolkit's runtime server inert for the run; without it a headless run binds
  127.0.0.1:6570 and claims this project's runtime entry from a real game session. It exits
  non-zero when anything failed. One file with `-- res://tests/test_<module>.gd`; a name filter with
  `-- res://tests plant_`. Ziva's `run_tests` runs the same files. **CI runs the suite** -
  `.github/workflows/workflow-checks.yml` runs it on every pull request and on a push to `main`, and validates the release workflow guide.
- **The dev tools**: `res://tools/` holds one-off checks that are run, not shipped - `audit.gd` (one
  pass: plant check, HUD layout, every scene loads), `plant_scene_check.gd`, `hud_layout_check.gd`, `console.gd`,
  and the per-feature `*_demo.gd` scripts. Run them with Ziva's `execute_script` or as a scene.
- **The development console**: run `res://tools/console.tscn` and the console opens over the running
  game; `:help` lists its commands and a line without a leading `:` runs as GDScript. When the question
  is about the running program - where a control sits on screen, what the live tree holds, what changes
  each frame - **ask here before you rebuild**. The verbs: `:where <path>` reports a control's on-screen
  rectangle, or a page's whole report; `:pages` lists every page the project has and, for each one that
  is up, where it stands and whether its contents fit; `:probe` says what is on the screen, in the very
  words the phone's `PROBE` block prints; `:mode` gives the view, the tool in hand, the layer and the
  status line; and `:doc` gives the drawing - its entity count, its layers, its file and whether it is
  unsaved. Every figure comes from the module that already owns it (`scripts/hud_probe.gd`,
  `scripts/page_index.gd`, `scripts/page_layout.gd`, the drawing's own controller), so nothing is worded
  a second time. Reach the live tree from free-form GDScript through `root` or `get_node("/root/...")`
  - not `get_tree()`, and not a bare node name. It is a development tool, so `tools/` only: nothing in
  `scripts/` or `scenes/` may depend on it.
- **The context exporter**: `tools/context_report.gd` builds a text snapshot of this project for an
  outside AI (`-- plant-id` for a scoped pack). Use the **AI Context** editor dock (`addons/context_tools/`)
  or run `tools/export_project_context.gd` with Ctrl+Shift+X in the editor. If you add a subsystem,
  add a subject to `ContextReport.SUBJECTS`.

## Seeing the GUI

The GUI is asked, not looked at, and every figure comes from the module that already owns it. Four
instruments, cheapest first.

**The probe's blocks.** A debug build prints a `PROBE` block at launch, whenever a page is shown, moved
or resized, and when the bar is rebuilt; a phone cannot show a console, so the block also goes to
`user://probe.log`, oldest lines given up first, through a temporary file and a rename. Read it off a
phone with `adb exec-out run-as ca.storm.landscapingplanner cat files/probe.log`. A block carries `page`
and `tap` lines (every control a finger could hit, at its centre - which is also how a page's own
rectangle is read on a phone, with no screenshot needed), `overlap` lines (what is *drawn* against what
may not share rows with it, because a page's title bar hangs *above* the rectangle the page reports
where no layout can see it) and `drawn` lines (the run of colour above a page's top edge, read off the
framebuffer, printed beside the height the theme claims - a phone draws that bar taller than the theme
says). The rule an `overlap` is decided by lives in `scripts/drawn_surfaces.gd`, which reports and never
decides. `tools/page_chrome_probe.tscn` is the page-side of it: the strip, and a colour walk of the
screen.

**The console**, `res://tools/console.tscn`, over a running game: `:where <path>`, `:pages`, `:probe`,
`:mode`, `:doc`. Ask it before rebuilding.

**The audit**, `res://tools/audit.tscn`, one pass: the plant check, the HUD layout, the page layout and
every scene loading. `tools/hud_layout_check.gd` consults `drawn_surfaces` too: a meeting with the bar at
the top of the screen fails the check, and every other meeting is named and left to be judged, because
whether a page over the palette's first button is wrong is a judgement and not a measurement.

**The glass.** `scripts/screenshot_reader.gd` reads a picture as numbers: `bands_down` walks one column
and says where each colour starts and ends, `band_containing` gives the whole run of a colour around a
row, and `doubled` hands a region back twice as big with every pixel kept square. That is how a bar's
drawn height is found without asking anyone, and how two title bars in the same rows - words drawn over
words - are read straight off a picture with a person's eye. Write a crop with `ScreenshotReader.write`
and look at it.

**The words.** `scripts/gui_words.gd` owns what is wrong with the text itself, which no rectangle can
show: a note to the author left in place, a message a compiler would write, a sentence where a name
belongs, two spaces that are a slip rather than the separator this program uses. A rule belongs there only
when every reader agrees - letters in capitals in the middle of a sentence are deliberately **not**
policed, because this program's text is full of codes and names in capitals (`NONE`, `CAD`, `UTC-5`,
`L1.1`, `010-SURVEY-PROP`) and a rule that cannot tell a shout from a layer name names the vocabulary
rather than a fault. `tools/gui_sweep.tscn` opens every page that holds prose or a list and reports each
one's cut boxes and wrong words; `tools/hud_layout_check.gd` names the same two things for whatever is up,
and names rather than counts them, because a deliberate scroller and a caption a person chose are
judgements. `tools/gui_sense_demo.tscn` is the same page placed with the page strip and without it.
**The screen itself.** `scripts/in_view.gd` owns the one comparison nothing else here makes: a control
against the *room*, rather than against another control. A button drawn past the edge of the screen cannot
be pressed by anybody, and the phone's own view buttons were drawn wholly off it and had to be found by
eye. A control something is clipping is left out, because for one of those being past the edge is the
design - a tool in the palette's scroll, a page's contents in the scroller `PageChrome` gives an over-tall
page. The room is the **root viewport's** rectangle and not whichever viewport is at hand: a page is a
viewport of its own, so asking a page for its visible rectangle answers with the page's own size while the
controls inside it are measured in screen pixels, and the first version reported the front door's scroll
container 540 px past the edge of a 520-wide room.

`scripts/topmost.gd` owns the other question a driver asks: what a tap at a point would actually **reach**,
and whether the thing it reached is switched off. The rectangles are handed over in the order they are
drawn - a parent before its children, an earlier sibling before a later one - and the last of them holding
the point is what the engine gives the click to. Two judgements belong to the walk and not to the rule: a
control the mouse passes through is not handed over at all, and a control covering the whole room is the
screen's own backdrop rather than something in the way.

`Hud`'s own block asks both of these once for the board and every page that is up; `tools/gui_sweep.tscn`
asks them page by page, and `tools/hud_layout_check.gd` names them for whatever is on the screen. The
room one is **counted** there - a control the room cannot hold is something a person cannot reach, which is
not a judgement - and the tap one is **named**, because a page standing over the board is what a page is
for.
**What is inside a rectangle.** Four more questions, and they ask what a rectangle *holds* rather than where it stands. `scripts/contrast.gd` is whether a caption's ink can be read against the paper behind it, which is known only where a program can find both colours - a button's own plate, a panel, a plain filled rectangle - so a caption drawn onto the plan, which has no paper, is left alone rather than judged against a guess. `scripts/stacked.gd` is two controls of one kind in exactly one rectangle, so that only the later is ever seen. `scripts/blank_picture.gd` is a picture with no texture, or one that is a single colour from corner to corner, compared every byte at a time because a sampled grid has twice stepped over a real mark here. And `InView` applied to a *page's own* rectangle, since every control inside a page can be placed perfectly in a page that has itself been put past the edge of the screen. All four are named and not counted, and both `tools/hud_layout_check.gd` and `tools/gui_sweep.gd` report them.

**A screen that will not hold still.** No single picture can show one, and nothing here compared the screen *with itself over time* until `scripts/stillness.gd` did: `bands(before, after)` groups the rows that differ into runs, with the span of each and the busiest single row. `tools/gui_stillness.tscn` takes two frames with nothing touching the program, and then a second pair across a keypress, so that the rule is shown to be able to see movement at all. What it measured on the desk is that the screen holds still - the HUD asks its palette for its own state sixty times a second and not one pixel of that reaches the glass.

**A caption that never changed.** The one fault in a GUI with no rule: whether a label *should* have followed an action depends on what the page promised it when it handed the label its words, and that promise lives in the page. So `tools/gui_captions.tscn` takes the screen's words down twice, around one action, and prints what moved - `scripts/caption_ledger.gd` compares the two readings. A caption that held still while everything around it moved is the suspect list. That is how the box beside the plan was found saying whichever tool was in hand.

**And the phone's own question.** `scripts/touch_target.gd` is a target a finger is meant to press and could not hit: measured in screen pixels, and asked only while `shows_touch_controls()` is true, because the desk's own 31 px buttons are right for a mouse. The probe prints those as `small` lines.

**A finger has more than a size.** Three questions about a target, none of which is about how big it is. `scripts/spacing.gd` is the gap between two targets a finger must choose between - a thumb covers an area about a centimetre across, so two controls closer than about 8 px are one control to the person pressing, and which one answers is decided by the draw order; two controls in *exactly* one rectangle are left to `Stacked`, and a control standing on a plate is not a pair. `scripts/safe_area.gd` is a target standing in a band the device keeps for itself - the swipe up from the bottom, the swipe in from the side, the notification shade at the top - and the device's numbers are handed in rather than restated, so `PhoneHud.cutout_here` owns them and this only judges a rectangle against them; a device that has promised nothing names nothing. `scripts/legibility.gd` is whether words are big enough for the screen they land on, against the floor `PhoneHud.font_size` already states for the device's density - a second copy of that number could disagree with the sizes the program draws at, and `ReadingSize` is the different question of how much *bigger* than that floor a reader has asked for. The probe prints them as `close`, `unsafe` and `tiny`, beside `small`, and only while `shows_touch_controls()` - the desk's own 31 px buttons are right for a mouse.

**What the touch GUI is asked, in the words the instruments use.** `small` is a target shorter than the
floor the caller states - and it is the *device's* floor that goes in, `PhoneHud.row_height`, not the 44 px a desk
is laid out at: on a 450 dpi phone that is about 107 px, and the unsaved-changes question's 50 px buttons clear the
desk's floor while being half of what the program itself asks for. `close` is two targets a thumb cannot tell
apart. `unsafe` is a target *reaching* into a band the system keeps, and `middle` is the sharper half of that
question: a finger lands where it was aimed, which is the middle - the phone's three view buttons each reach 81 px
into the top band with their middles at y=68 inside it, and a large button merely overlapping an edge is named by
neither. `tiny` is words below the floor the device states. `clipped` is words wanting more room than the box they
are drawn in, the one of the six that means the same on a desk as on a phone, and the one the glass found: the
phone's own foot line said "Pinch: zoo" where the program had written "Pinch: zoom".

**A floor counted in pixels needs a screen to count it on.** A headless run's dummy display reports a 64 x 64
window with the canvas drawn at 0.04, so a 109 x 50 button measures 4 x 2 px of "screen" and every control in the
program is named for a fault nobody could have. `small` and `close` refuse the question where there is no screen,
which is the guard the framebuffer needs too (`DisplayServer.get_name()`, never `OS.has_feature("headless")`).
Questions that compare a shape with a shape - `offscreen`, `page-edge`, `reach` - survive any scale, because
scaling both sides changes neither answer.

**The phone's own report** is `tools/phone_touch_pass.tscn`: one command that pulls `probe.log` off the device and
prints the newest block's touch lines in that order. **`--build`** makes the build before installing it - the
engine's own export, run only when a script, a scene or the preset has moved - and **`--turn`** holds the device
the way up it is asked for while the program starts, handing it back when the run ends. **`--numbers`** checks the
numbers this project states for a phone against the phone's own, which is the one check a desk cannot make. It
also installs and launches (`--install --launch`) and presses at a centre the probe itself reported (`--tap X Y`).
A real OS tap *does* reach a control inside a page's `Window` on the device - measured on the A16W - which is the
opposite of what `run_scene`'s injection can do, so pages on a phone are driven by tapping the probe's own centres.

**On a phone**: `phone_touch_pass --build --launch` is the whole of it - it exports if anything that reaches the
phone has moved (three minutes, and nothing is exported when nothing has), installs, starts, waits for a block, and
hashes the phone's own copy against the file to say they are the same build. `--turn landscape` (or `portrait`)
holds the device's own rotation while the program starts, and hands it back when the run ends. By hand the same
steps are `--export-debug "Android (phone)" build/phone-adapt.apk`, `adb install -r`, start it, then pull
`probe.log` and `adb exec-out screencap -p > build/phone.png`. An injected *tap* does not reach a control inside an
embedded `Window`; a keyevent does, so a page is reached with TAB and ENTER. `screencap` comes out in the display's
own orientation, and `adb` is not on the PATH - the SDK copy is.

**The discipline.** A rectangle is a statement by the program about itself; the glass is what a person
sees. When the two disagree, the disagreement gets a name - a line, a measurement of the glass, or a
test that pins the number - rather than a guess about which of them is right.
## Do not

- **Do not touch `addons/`.** It is third-party: the Godot AI bridge (`addons/godot_ai`, gitignored, its plugin off), the GitHub
  release dock, and the business/visualization editor docks. Generate nothing that depends on its
  internals. The development console in `addons/crabbyconsole/` is used the same way - through
  `tools/console.tscn`, by path, never by naming what is inside it.
- **Do not rename the project** (`application/config/name`) or move `user://` data. A drawing, the
  plant catalogue, sheets, revisions and the autosave copies all live under `user://`; renaming moves
  all of it.
- **Do not commit a generated context snapshot** or anything else produced by a tool run.
- **Do not commit without being asked.** The repository is worked on a branch at a time, and the
  release workflow refuses a dirty tree.
