# Landscaping Planner

A landscape design tool, written in **Godot 4.7 with GDScript only**: draw a site plan to scale,
place plants from a nursery catalogue, check whether they will grow where they are going, price the
work, and present the design.

## Running it

Open the project in Godot 4.7 and run `res://scenes/main.tscn`, or from a shell:

```
Godot_v4.7.2-stable_win64_console.exe --path .
```

## Running the tests

Headless, with no editor and no plugins - it exits non-zero when anything failed:

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tools/run_tests.tscn
```

One file, or a name filter:

```
... res://tools/run_tests.tscn -- res://tests/test_plants.gd
... res://tools/run_tests.tscn -- res://tests plant_
```

## Where things are

| folder | what it holds |
| --- | --- |
| `scenes/` | the scenes, starting at `main.tscn` |
| `scripts/` | the program: a model per concept, a window per page, the controllers |
| `tests/` | one test file per module, run by `tools/run_tests.tscn` |
| `tools/` | one-off checks that are run and not shipped - the audit, the demos, the context exporter |
| `docs/` | the specifications: the design authority for each subsystem |
| `data/` | shipped data - the nursery list, the starter cost book |
| `addons/` | third-party - the Ziva bridge, the GitHub release dock, the editor docks |

## Working on it

**`AGENTS.md` is the first thing to read**: the conventions, the shape every feature has here, how the
tests are written, and what not to touch. `docs/` holds the reasoning for each subsystem - read the
one for the area you are changing before you change it.

## Handing the project to an outside AI

`tools/context_report.gd` builds a text snapshot of the project - its conventions, every script with
its members, constants, method signatures and signals, the scene tree, and one record of each data
file - for pasting into a chat assistant:

- in the editor dock: open the **AI Context** dock (bottom-right panel, beside Cost book and
  Presentation), choose the whole snapshot or a subject pack, optionally type your request, and
  click **Copy to clipboard** (or **Write file** / **Build preview**).
- in the script editor: open `tools/export_project_context.gd` and press **Ctrl+Shift+X**; the
  snapshot is written to `user://gemini_context.md` **and copied to the clipboard**.
- headless: `godot --headless -s res://tools/export_context_cli.gd`, with `-- plant-id`,
  `-- planting` or `-- drafting` for a scoped pack instead of the whole project.