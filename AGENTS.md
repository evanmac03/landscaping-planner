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
