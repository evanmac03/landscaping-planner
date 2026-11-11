class_name ContextReport
extends RefCounted
## Builds the **context snapshot** the two exporter tools write: everything an outside code
## generator needs to write code that fits this project.
##
## **One** builder rather than two, because the two runners - the editor tool and its headless
## CLI twin - must not drift apart: one of them had drifted to printing bare type ids while the
## other printed names. Both now call `build()`.
##
## The snapshot has four parts, and three of them are **derived from the filesystem**, so they
## cannot go stale:
##
## * the **project header** - engine, main scene, viewport, renderer, autoloads, plugins - read
##   from `ProjectSettings`;
## * the **inventory** - every script under `res://scripts`, with its `class_name`, its base type,
##   its member and signal counts and its own one-line summary, read from the files themselves;
## * the **data models in detail** - the members, constants and signals of the scripts in
##   `SCRIPTS`, asked of each script.
##
## The conventions block is **quoted from `AGENTS.md`**, so the rules an agent working in the
## repository reads and the rules an outside reader is handed are one set rather than two. The other
## hand-written block is the **hook points** of the feature this snapshot exists for.
##
## **A scoped pack** (`SUBJECTS`) is the other thing this builds: one subject's slice of the
## project rather than all of it. A three-thousand-line visualization specification is not merely
## noise when the question is about plant capture - it is what makes a generator answer about the
## wrong subsystem - so a pack names the scripts, the specification sections and the data files
## that one piece of work needs, and says what it has left out.
##
## The detail sections carry the four things a reader needs in order to *use* a model rather
## than guess at it: **script variables**, **constants** (the bit values and the enums - a
## GDScript enum *is* a constant, and arrives as a Dictionary), **methods** (full signatures,
## so a generated call has the right arguments) and **signals**.

const SCRIPTS := [
	"res://scripts/plant_species.gd",
	"res://scripts/plant_catalogue.gd",
	"res://scripts/plant_id_resolver.gd",
	"res://scripts/plant_symbols.gd",
	"res://scripts/crop_sun.gd",
	"res://scripts/plant_placement.gd",
	"res://scripts/plant_suitability.gd",
	"res://scripts/io/field_manifest_exporter.gd",
	"res://scripts/utils/bitmask_utils.gd",
	"res://scripts/survey_watcher.gd",
	"res://scripts/view_controller.gd",
	"res://scripts/plant_browser.gd",
	"res://scripts/draft/units.gd",
	"res://scripts/draft/survey.gd",
]

## The subjects a **scoped pack** can be built for.
##
## Every entry names plain paths and heading texts. A heading is named **without** its `#` markers
## and matched on its text, so `"2. The files"` picks up `## 2. The files, and where they live`; a
## heading that no longer exists is reported *in* the pack rather than passed over, because a
## subject whose section silently went missing is a pack that answers with a rule it does not hold.
##
## * `title` - what the work is, for the pack's heading.
## * `when` - one sentence saying when a person should choose this pack, shown in the dock under the
##   scope picker. A person who has never read a specification picks by this line.
## * `brief` - hand-written lines: what is being built and what to reuse rather than rebuild.
## * `scripts` - the paths detailed in full (members, constants, methods, signals).
## * `also` - class names worth knowing exist, without the detail.
## * `sections` - specification sections quoted verbatim, as `{doc, headings}`.
## * `data` - data files the work reads or writes.
## * `hooks` - set on the one subject the feature hook points belong to.
## The sentence the dock shows for the whole snapshot, which is not a subject and so has no `when`
## line of its own.
const WHOLE_WHEN := "Everything. Choose it when the request is not about one part of the project, or when you are not sure yet - the summary will say if it is too big for one chat message."

const SUBJECTS := {
	"plant-id": {
		"title": "naming a plant - the resolver, the catalogue and where a plant belongs",
		"when": "Turning a name somebody typed, spoke or read into a species, and deciding whether that species suits the spot it is going into.",
		"brief": [
			"The work: giving a plant a name. A person types, speaks or reads one; `PlantIDResolver`",
			"turns it into a `PlantSpecies` and **refuses below a floor** rather than answering with",
			"the nearest species, and `PlantSuitability` then says whether that species suits the spot",
			"it is going into.",
			"",
			"Already built, to be **used and not rebuilt**: `PlantSpecies` is the record and the HUD's",
			"`PlantCatalogue` is the one catalogue; `PlantSymbols` owns the shape vocabulary;",
			"`PlantPlacement` is the one door that puts a species into the yard; and `BitMaskUtils`",
			"turns sun hours into the model's bits - the sun and drainage masks are bitfields, never",
			"enums, and nothing stated is zero.",
			"",
			"**The capture that produces a name from a photograph is its own pack** - `field-capture`.",
			"This one is the plant-model half of knowing what a plant is.",
		],
		"scripts": [
			"res://scripts/plant_species.gd",
			"res://scripts/plant_catalogue.gd",
			"res://scripts/plant_id_resolver.gd",
			"res://scripts/plant_placement.gd",
			"res://scripts/plant_suitability.gd",
			"res://scripts/utils/bitmask_utils.gd",
		],
		"also": [
			"PlantBrowser", "PlantSymbols", "PlantIcons", "PlantLabels", "PlantPanel", "ZoneMap",
			"CropSun", "TerrainProfile",
		],
		"sections": [
			{
				"doc": "res://docs/plant-database-spec.md",
				"headings": [
					"2. The files, and where they live",
					"3. One species",
					"5. Planting: what the catalogue does to the plan",
					"7a. Suitability: whether the plant belongs where it is going",
				],
			},
		],
		"data": ["res://data/plants/nursery_list.json"],
	},
	"field-capture": {
		"title": "the field capture - what is on site, photographed, measured and recorded",
		"when": "Recording what is on site - a photograph, a typed or spoken name, a stated height or spread - and the survey file it writes arriving in the plan.",
		"brief": [
			"The work: an offline phone tool records what is on site and writes a manifest this",
			"project imports. A capture is **identified** (`FieldCapture.identify`), keeps a",
			"**photograph** when it has one (`FieldPhotoStore`), carries a **stated size** where",
			"somebody measured one (`PlantPlacement.place` substitutes it into the species' own",
			"ratio), and arrives as a file `SurveyWatcher` imports.",
			"",
			"Three rules that are easy to undo by accident. **One writer**:",
			"`FieldManifestExporter.export_manifest` is the only function that writes a manifest, and",
			"it writes through a temporary file and a rename. **One identity answer, asked twice**:",
			"`FieldManifestExporter.identity_of` is what the writer's duplicate check and the watcher's",
			"\"already planted\" check both read - never restore a rule that skips an empty",
			"`instance_id`. And **a capture is planted even where the ground says it does not belong**:",
			"the import reports the verdicts afterwards and never refuses, because a survey is the",
			"record of what is on site.",
			"",
			"Whether a file is a picture is `RasterUnderlay.sniff`'s answer and `FieldPhotoStore` adds",
			"only the content address: there is no second \"is this a picture\" rule in the project.",
			"Survey geometry is `Survey` and `SurveyFile`'s, so a capture side must not grow a second",
			"survey engine.",
		],
		"scripts": [
			"res://scripts/field_capture.gd",
			"res://scripts/field_photo_store.gd",
			"res://scripts/plant_identifier.gd",
			"res://scripts/survey_watcher.gd",
			"res://scripts/io/field_manifest_exporter.gd",
			"res://scripts/plant_id_resolver.gd",
			"res://scripts/utils/bitmask_utils.gd",
		],
		"also": [
			"ViewController", "FieldCaptureWindow", "PlantCatalogue", "PlantPlacement", "RasterUnderlay",
			"PlannerHud", "SiteReport", "VisProposalPage", "PlantSuitability", "Survey", "SurveyFile",
			"DraftUnits",
		],
		"sections": [
			{
				"doc": "res://docs/field-capture-spec.md",
				"headings": [
					"2. One capture, and the two ways it can be true",
					"4. The manifest, and the one writer",
					"5. The import: a file becomes plants",
					"7. A stated measurement, and what it changes",
				],
			},
		],
		"data": ["user://site_manifest.json"],
		"hooks": true,
	},
	"planting": {
		"title": "the plant database - species, catalogue, symbols, placement, browser",
		"when": "Anything about a species record, the catalogue, the plant list in the game, plant symbols, or putting a plant on the plan.",
		"brief": [
			"The work: the plant side of the planner - what a species is, how a catalogue of them is",
			"read, written, searched and shown, what symbol a species is drawn as, and what happens to",
			"the plan when one is planted.",
			"",
			"A species is a record in JSON, never a `.tres`; the runtime handles it caches (a",
			"`PackedScene`, a `Texture2D`) are the only `Resource`s in the picture. `PlantSymbols`",
			"owns the shape vocabulary, so a symbol a list can name is a symbol the plan can draw.",
			"",
			"The catalogue the app uses is the HUD's (`Hud.plant_list()`), never a second one.",
			"",
			"**This pack is kept inside one chat message**, so `PlanStyle` - which decides how big and",
			"what shape the planted prop is - is named below rather than detailed here. Ask for the",
			"whole snapshot when a change is about how a planted species is *drawn* rather than what it",
			"is.",
		],
		"scripts": [
			"res://scripts/plant_species.gd",
			"res://scripts/plant_catalogue.gd",
			"res://scripts/plant_symbols.gd",
			"res://scripts/plant_placement.gd",
			"res://scripts/plant_spacing.gd",
			"res://scripts/plant_suitability.gd",
			"res://scripts/plant_browser.gd",
		],
		"also": [
			"PlannerHud", "PlantIcons", "PlantLabels", "PlantPanel", "ZoneMap", "CropSun",
			"PlanStyle",
		],
		"sections": [
			{
				"doc": "res://docs/plant-database-spec.md",
				"headings": [
					"2. The files, and where they live",
					"2a. More plants, and the rule that keeps them from being duplicates",
					"3. One species",
					"4a. The symbol a species is drawn as",
					"5. Planting: what the catalogue does to the plan",
					"5a. A bed at a spacing",
					"6. The browser",
				],
			},
		],
		"data": [
			"res://data/plants/nursery_list.json",
			"res://data/plants/nursery_list_more.json",
		],
	},
	"drafting": {
		"title": "the drafting subsystem - model space, tools, layers, survey import",
		"when": "The drawing itself: entities, layers, snapping, measuring, undo, or importing a surveyed boundary.",
		"brief": [
			"The work: the drawing itself - the document and its entities, the layers, the precision",
			"tools, snapping, undo, and the survey import that aligns a surveyed boundary to the plan.",
			"",
			"Two rules that are easy to undo by accident: the model is **metres as a double** and",
			"imperial exists only as a display and entry format (no geometry is ever stored in feet);",
			"and an area is turned into words in exactly one place, `DraftUnits.format_area`.",
			"",
			"Undo is a named, serial-numbered **gesture** (`DraftGestureHistory`), never a snapshot of",
			"state, and the serial is what joins it to the revision log.",
			"",
			"**Snapping, the guides, simplify and the command palette are the `workflow` pack's**, which",
			"details `SnapEngine` and `Geom2D`; ask for both when a change reaches across them.",
		],
		"scripts": [
			"res://scripts/draft/draft_document.gd",
			"res://scripts/draft/draft_entity.gd",
			"res://scripts/draft/draft_layer.gd",
			"res://scripts/draft/units.gd",
			"res://scripts/draft/geom2d.gd",
			"res://scripts/draft/gesture_history.gd",
			"res://scripts/draft/draft_tool.gd",
			"res://scripts/draft/survey.gd",
			"res://scripts/draft/survey_file.gd",
		],
		"also": [
			"DraftController", "DraftOverlay", "DraftRender", "DraftSelect", "DraftEdit",
			"DraftSpatialGrid", "PlanCanvas", "PlannerHud", "SnapEngine", "DraftSimplify",
		],
		"sections": [
			{
				"doc": "res://docs/drafting-subsystem-spec.md",
				"headings": [
					"1. Coordinate space, model space and paper space",
					"7. Data structures added by this specification",
					"8. UI surfaces",
				],
			},
			{
				"doc": "res://docs/drafting-module.md",
				"headings": [
					"D2 — Metre is the only internal unit; imperial is a display and entry format",
					"D3 — Display rounding never writes back",
					"5.5 Undo / redo: the gesture history",
				],
			},
		],
		"data": [],
	},
	"estimating": {
		"title": "estimating - the priced estimate taken off the drawing",
		"when": "Turning a drawing into a price: the cost book, a priced line, an estimate and its total, or the takeoff that measures the plan.",
		"brief": [
			"The work: what a landscape job costs before anybody agrees to it - a cost book of",
			"materials and work, a priced estimate taken off the drawing, and the takeoff that",
			"measures the plan.",
			"",
			"Three rules that are easy to undo by accident. **Money is integer minor units, never a",
			"float** (`Money`), because this build's floats are 32-bit and lose cents. **A quantity",
			"keeps its unit and its dimension** (`WorkUnit`), so paving is priced by the square metre",
			"and a perimeter cannot be priced as one. And the **takeoff is the only measuring pass**",
			"- a second one that can disagree with `Takeoff` is the defect this project spends the",
			"most effort avoiding.",
			"",
			"The arithmetic lives in one place per thing: `EstimateLine` prices a line, and `Estimate`",
			"rolls it up and **refuses to foot when a line is unreadable** rather than showing a zero,",
			"which is a figure a person will bill from.",
			"",
			"**The job, what it cost, the invoices and the ledger are the `jobs-billing` pack.**",
		],
		"scripts": [
			"res://scripts/biz/money.gd",
			"res://scripts/biz/tax.gd",
			"res://scripts/biz/work_unit.gd",
			"res://scripts/biz/cost_item.gd",
			"res://scripts/biz/cost_book.gd",
			"res://scripts/biz/estimate_line.gd",
			"res://scripts/biz/estimate.gd",
			"res://scripts/biz/estimate_desk.gd",
			"res://scripts/biz/takeoff.gd",
		],
		"also": [
			"EstimateWindow", "BizBookImport", "SiteReport", "PlantOrder", "PlantOrderWindow",
		],
		"sections": [
			{
				"doc": "res://docs/business-operations-spec.md",
				"headings": [
					"1. Shape of the module",
					"2.1 Money is integer minor units",
					"2.2 An estimate line carries its own prices",
					"2.11 Tax is per line, and may compound",
					"5. The estimating engine",
				],
			},
		],
		"data": ["res://data/biz/costbook.json"],
	},
	"jobs-billing": {
		"title": "jobs and billing - the job, what it cost, what it billed, and the ledger",
		"when": "A job rather than a price: what it actually cost, what has been billed, an invoice, a payment, a ledger push, or a report of figures over the lot.",
		"brief": [
			"The work: what happens after the price is agreed - the job, what it cost against what",
			"was committed, the invoices that bill it, the money that arrives, the ledger those",
			"invoices go out to, and the figures read back over a year of them.",
			"",
			"Two rules that are easy to undo by accident. **A sent document is frozen**: a later",
			"change is a revision, and `BizStore` is where that lives - one record per file, an",
			"append-only journal, and an `If-Match` on every write. And **a page reads a desk and",
			"states what it cannot work out rather than showing a zero**, because a zero is a figure",
			"somebody will bill from.",
			"",
			"`Billing` is the one place that says what a period is worth, and `JobCost` holds",
			"committed against actual. The ledger adapters never invent a customer id or a figure the",
			"service did not state - a missing one is refused by name.",
			"",
			"**Estimating - the cost book, the priced estimate and the takeoff - is the `estimating`",
			"pack.**",
		],
		"scripts": [
			"res://scripts/biz/job.gd",
			"res://scripts/biz/job_desk.gd",
			"res://scripts/biz/job_cost.gd",
			"res://scripts/biz/billing.gd",
			"res://scripts/biz/billing_desk.gd",
			"res://scripts/biz/invoice.gd",
			"res://scripts/biz/payment.gd",
			"res://scripts/biz/store.gd",
		],
		"also": [
			"JobCostWindow", "ScheduleBoard", "BillingWindow", "InvoiceSheet", "CreditNote",
			"Milestone", "Rate", "LedgerDesk", "LedgerWindow", "LedgerAdapter", "FileLedger",
			"AkauntingLedger", "InvoiceNinjaLedger", "BizSync", "SyncWindow", "Analytics",
			"AnalyticsWindow", "CrewMember", "TimeEntry", "PurchaseOrder", "ChangeOrder",
			"CloseoutDesk", "Money",
		],
		"sections": [
			{
				"doc": "res://docs/business-operations-spec.md",
				"headings": [
					"2.10 Everything is a revision, and a sent document is frozen",
					"9. Billing, invoices, and the ledger",
					"11.1 The store",
				],
			},
		],
		"data": [],
	},
	"visualization": {
		"title": "the visualization subsystem - painted plans, proposals, renders, sun study, walk-throughs",
		"when": "Showing the design rather than drawing it: a painted plan, a still, a proposal, a batch of renders, a shadow study, or walking through the finished garden.",
		"brief": [
			"The work: presenting the design rather than drawing it - a painted plan, a still, a",
			"proposal page, a batch of renders, a shadow study over a day, and a walk-through of",
			"the finished garden.",
			"",
			"Three rules that are easy to undo by accident. The wobble that makes a line read as",
			"hand-drawn is **geometry, not a shader** (`SketchStroke`): a shader that displaces by",
			"screen position makes the line swim as the view pans, because the displacement follows",
			"the window instead of the paper, and geometry can be measured, which is how the drawing",
			"stays honest. The look is **three layers governed by one rule** - the wash table picks",
			"the pigment, and a layer missing from it washes in nothing rather than in the wrong",
			"colour. And **every authored length is paper millimetres**.",
			"",
			"The renderer is `gl_compatibility`, which has no `SubViewport` post-processing to lean",
			"on, so a composite is a shader over baked layer textures (`SketchBaker` into a",
			"`SketchCompositor` material). `PaintedPlan` is the drawer the still, the proposal page",
			"and the walk-through all read, so none of them may draw the plan its own way.",
		],
		"scripts": [
			"res://scripts/vis/painted_plan.gd",
			"res://scripts/vis/wash_table.gd",
			"res://scripts/vis/wash_painter.gd",
			"res://scripts/vis/solid_table.gd",
			"res://scripts/vis/hardscape_material.gd",
			"res://scripts/vis/orbit_camera.gd",
			"res://scripts/vis/ink_painter.gd",
			"res://scripts/vis/sketch_baker.gd",
			"res://scripts/vis/sketch_compositor.gd",
			"res://scripts/vis/sketch_stroke.gd",
			"res://scripts/vis/sketch_style.gd",
			"res://scripts/vis/still_preset.gd",
			"res://scripts/vis/render_batch.gd",
			"res://scripts/vis/proposal_page.gd",
			"res://scripts/vis/sun_report.gd",
			"res://scripts/vis/walk_route.gd",
			"res://scripts/vis/walk_director.gd",
			"res://scripts/vis/vis_diagnostics.gd",
			"res://scripts/vis/presentation_tier.gd",
			"res://scripts/vis/derived_builder.gd",
		],
		"also": [
			"SunStudy", "SunWindow", "WalkWindow", "StillExporter", "StillSidecar",
			"PresentationDirector", "CadSolid", "TextureSetBuilder", "YardExporter",
		],
		"sections": [
			{
				"doc": "res://docs/visualization-subsystem-spec.md",
				"headings": [
					"2. The look: three layers, one rule",
					"3.1 Where the wobble lives: geometry, not shader",
					"3.3 The ink pass, drawn twice",
					"4.2 The wash table",
				],
			},
		],
		"data": [],
	},
	"irrigation-lighting": {
		"title": "the irrigation and lighting modules - heads, zones, fixtures, circuits, transformers",
		"when": "The services that go into the ground: irrigation heads, zones and a stated supply, or lighting fixtures, circuits and a transformer.",
		"brief": [
			"The work: the two services that go into the ground - irrigation heads grouped into",
			"zones against a stated supply, and lighting fixtures grouped into circuits on a",
			"transformer. Both are drawn as entities on a layer of their own, and both refuse a",
			"figure they cannot work out rather than showing a plausible one.",
			"",
			"The two modules are **deliberately twins**, and a change to one is a question about",
			"the other: a head kind and a fixture kind are each a **table, not a free-text field**;",
			"a zone is a valve and the heads it runs, a circuit is a run of cable on a transformer",
			"and the fixtures it feeds; the supply or the transformer is **stated, never assumed**;",
			"**one place does the arithmetic and it refuses**; a head or fixture tiles the area",
			"head-to-head at a spacing it is designed for; **coverage and load are measured on a",
			"grid rather than asserted**; and **a head is not a plant**, so it is an entity on the",
			"drawing (`500-IRRIGATION`, `501-LIGHTING`) rather than a prop under `<yard>/Plants`.",
		],
		"scripts": [
			"res://scripts/draft/irrigation.gd",
			"res://scripts/irrigation_panel.gd",
			"res://scripts/draft/lighting.gd",
			"res://scripts/lighting_panel.gd",
		],
		"also": ["PlannerHud", "GroundWindow", "DraftDocument", "DraftLayer", "PlanCanvas"],
		"sections": [
			{
				"doc": "res://docs/irrigation-subsystem-spec.md",
				"headings": [
					"2.9 Heads are entities on `500-IRRIGATION`",
					"3. Data models",
					"4. The algorithms",
				],
			},
			{
				"doc": "res://docs/lighting-subsystem-spec.md",
				"headings": [
					"2.9 Fixtures are entities on `501-LIGHTING`",
					"3. Data models",
					"4. The algorithms",
				],
			},
		],
		"data": [],
	},
	"food-garden": {
		"title": "the food garden - what will crop, what follows what, what is ready, when to sow, how much",
		"when": "Growing food: will a crop get its sun, what to grow next year, what grows well beside what, what is ready in a month, when to sow, and how many plants to buy.",
		"brief": [
			"The work: the edible side of a plan, in five questions and one hand-off - does a crop",
			"get the sun it needs where it is going (`CropSun`), what should grow here next after",
			"this year's crop (`CropRotation`), what is ready in a given month (`HarvestCalendar`),",
			"how long the season is and when the last frost falls (`GrowingSeason`), when to sow and",
			"what succession sowings follow (`SowingPlanner`), and how many plants feed a household",
			"(`PlantYield`, which hands the count to `PlantOrder`).",
			"",
			"One rule runs through all of them: a figure that cannot be worked out is **refused by",
			"name**, not shown as a zero, and the refusal names the input that is missing. Every one",
			"reads the species record (`PlantSpecies`) rather than a second crop table, so an",
			"edible's days to harvest, its sun and its hardiness come from the catalogue the browser",
			"already shows. A page states the model's own verdict in the model's own words.",
			"",
			"**The specification is `docs/food-garden-spec.md`**, quoted below for the parts a change to",
			"this module usually needs - the refuse-not-zero rule, the two companion layers and which",
			"of them wins, and the shape of the companion tables. The doc comments on the models carry",
			"the rest, and the in-app manual describes each page under Help. A generator that needs a",
			"rule this pack does not state should ask for one to be written down rather than invent it.",
		],
		"scripts": [
			"res://scripts/plant_species.gd",
			"res://scripts/crop_sun.gd",
			"res://scripts/crop_rotation.gd",
			"res://scripts/harvest_calendar.gd",
			"res://scripts/growing_season.gd",
			"res://scripts/sowing_planner.gd",
			"res://scripts/plant_yield.gd",
		],
		"also": [
			"FoodWindow", "RotationWindow", "HarvestWindow", "SeasonWindow", "SowingWindow",
			"YieldWindow", "PlantCatalogue", "PlantBrowser", "PlantOrder", "PlantOrderWindow",
		],
		"sections": [
			{
				"doc": "res://docs/food-garden-spec.md",
				"headings": [
					"2.2 A question nobody answered",
					"2.8 A companion is read at the level it is stated",
					"2.9 Every pairing says how it is known",
					"3.3 The companion tables",
					"4.2 The rotation check",
					"4.3 Which companion pairing wins",
				],
			},
		],
		"data": ["res://data/plants/nursery_list.json"],
	},
	"workflow": {
		"title": "working fast - snapping, cleanup, the revision log, the command palette, a picture to trace",
		"when": "A feature that makes drawing quicker rather than drawing itself: snapping and guides, simplify, the revision log, the command palette, or a picture under the plan to trace over.",
		"brief": [
			"The work: the features that make the drawing quicker rather than different - snapping",
			"to geometry and guides, auto-cleanup (simplify), the revision log, one box for the whole",
			"command bar, and a picture under the plan to trace over.",
			"",
			"Three rules that are easy to undo by accident. The **wobble that makes a hand-drawn",
			"line is geometry, not a shader**. A **revision is a record, not a stack**, and its",
			"serial is what joins it to the named undo gesture. And **a picture under the plan is a",
			"picture**: `RasterUnderlay.sniff` decides whether a file is one by reading its bytes,",
			"and nothing else in the project gives a second opinion about that.",
			"",
			"The keys a new feature takes are the project's scarce resource: every `A`-`Z` key is",
			"bound already, so a new one has to be argued for rather than assumed - see the spec's",
			"own note about how many features had no key.",
		],
		"scripts": [
			"res://scripts/draft/snap_engine.gd",
			"res://scripts/draft/geom2d.gd",
			"res://scripts/draft/revision_log.gd",
			"res://scripts/command_palette.gd",
			"res://scripts/draft/raster_underlay.gd",
			"res://scripts/underlay_window.gd",
		],
		"also": [
			"PlannerHud", "DraftController", "DraftSimplify", "DraftSpatialGrid", "Presence",
			"PresenceMember", "StatusHistory", "PageEscape", "DraftGestureHistory",
		],
		"sections": [
			{
				"doc": "res://docs/workflow-efficiency-spec.md",
				"headings": [
					"1. Snap-to-geometry and smart guides - BUILT",
					"2. Auto-cleanup - AUTO-SIMPLIFY BUILT; ALIGN AND GROUP NOT",
					"3. Revision tracking - BUILT, apart from the audit journal",
					"8. One box for the whole bar - BUILT",
					"8b. A picture under the drawing, to trace over - BUILT",
				],
			},
		],
		"data": [],
	},
	"help": {
		"title": "the in-app manual - the help subjects and the page that shows them",
		"when": "The Help window and what it says: adding or rewording a subject, the keys topic, the prose guards, or a picture in the manual.",
		"brief": [
			"The work: the manual inside the program, under Help. `HelpDoc` holds every subject, its",
			"sections, its see-also links and its pictures; `HelpWindow` shows them and adds nothing",
			"of its own.",
			"",
			"Three rules that are easy to undo by accident. **The content is data and the page is a",
			"screen**: a sentence in the manual is a line in `HelpDoc`, never a label built by the",
			"window. **The keys topic is derived** (`keys_text()`), so the manual cannot claim a",
			"binding the project does not have. And **the prose is guarded**: a test file holds the",
			"wording rules down, because a manual is exactly the kind of prose that drifts.",
			"",
			"Adding a feature means adding a subject here as well - it is one of the six parts of a",
			"feature this project asks for.",
		],
		"scripts": [
			"res://scripts/help_doc.gd",
			"res://scripts/help_window.gd",
		],
		"also": ["PlannerHud", "PageEscape", "CommandPalette"],
		"sections": [
			{
				"doc": "res://docs/help-manual.md",
				"headings": [
					"1. Content is data, the page is a screen",
					"2. The keys are derived, not written twice",
					"6. The shape of a subject",
					"7. The files",
				],
			},
		],
		"data": [],
	},
}

## The specifications **no pack quotes**, each with a sentence saying why not.
##
## A pack exists for a piece of work somebody is about to do; a document that is about something else
## has no pack to belong to, and saying so is better than leaving it out of sight. It is the other half
## of a rule rather than an exemption from it: a test holds the whole of `docs/` to being either quoted
## by a pack or named here, so a specification that quietly stops being quoted fails rather than going
## silent.
const PACKLESS_DOCS := [
	{
		"doc": "res://docs/github-releases.md",
		"why": "it documents the third-party Godot Dev Workflow dock under `addons/`, which is not this project's own code and is not what a context pack is written to change",
	},
	{
		"doc": "res://docs/phone-target.md",
		"why": "it is about the platform rather than about one subsystem: it spans drawing, walking and every import door at once, so any single pack quoting it would be quoting rules for work it does not describe",
	},
]

const FieldManifestExporterScript := preload("res://scripts/io/field_manifest_exporter.gd")

const FENCE := "```gdscript"

## Where this project's conventions are written down, and the one place they are: an agent working in
## the repository reads this file, and the snapshot quotes it so an outside reader gets the same set
## of rules rather than a second copy that can drift from it.
const AGENTS_PATH := "res://AGENTS.md"

const FENCE_JSON := "```json"

## How much of one record to show. A species record is ~25 lines; the point is the shape of a
## record, not a copy of the file.
const SAMPLE_LINES := 40

## How much of an open script's own source a pack will quote. Generous enough that no script in this
## project is cut off, and low enough that the one file nobody wants cut cannot make a pack
## unpasteable; the heading says in words when the cap has bitten.
const SOURCE_LINE_CAP := 1200

## How much of `git diff` a pack will carry. Enough for a real change; past it the cut is stated in
## words rather than the rest silently dropped.
const DIFF_LINE_CAP := 200
const COMMIT_LINE_CAP := 40

## How much of the **end** of a test log a pack keeps, because the verdict and the failures are the
## last things a run prints.
const RUN_TAIL_LINES := 60

## How many of a test file's rule names a pack lists before it stops and says how many it stopped at.
## A rule name is the cheapest useful thing this file can print - it is the acceptance criteria in the
## tests' own words - but a file with two hundred of them would be most of the pack.
const TEST_RULE_CAP := 25
## And how many test files a pack lists rules from, for the same reason.
const TEST_FILE_CAP := 6
## How many of the work's scripts a test file has to name before it counts as a test *about* the work.
##
## Two, not one: a pack carrying a hub - `plant_species.gd` above all - would otherwise drag in every
## test file in the project that mentions a species, which is most of the suite and none of the rules
## this work is held to. A test that names two of these files is exercising the work itself.
const TEST_RELATION := 2

## How many callers of one symbol a pack names before it says "and N more".
const CALLER_CAP := 2
## And how many symbol lines the caller block prints, for the same reason as the rule cap.
const CALLER_LINE_CAP := 40
## How many arrows the call graph draws before it stops and says how many it left out. A diagram is a
## shape rather than a list, so it is cheap in tokens; the cap is there so a pack with two hundred calls
## in it does not become a diagram nobody can read.
const GRAPH_EDGE_CAP := 24

## How many characters of a pack's **content address** are printed. Eight hexadecimal characters is four
## billion possibilities - enough that "the same contents" and "different contents" are told apart at a
## glance, and short enough to sit at the end of a sentence.
const FINGERPRINT_CHARS := 8

## **There is exactly one of each thing.** `AGENTS.md` states the doctrine; this names the things, which
## is what a generator needs *before* it writes a line: the defect this project spends the most effort
## avoiding is a second engine that can disagree with the first, and a second one is usually written
## because nobody said where the first one was.
##
## The line that matters is *what it is* and *where it is*: if the thing somebody was about to write
## already has a home, the pack has saved them from writing it. Every path here is held to the disk by a
## test - a table naming a file that has gone is a table that has drifted, and it would send a reader
## looking for something that is no longer there.
const SINGLE_SOURCES := [
	{
		"what": "the plant catalogue",
		"one": "`PlantCatalogue`",
		"path": "res://scripts/plant_catalogue.gd",
		"note": "every species the program knows; the HUD's `plant_list()` is the one instance a page is handed",
	},
	{
		"what": "the measuring engine",
		"one": "`Takeoff`",
		"path": "res://scripts/biz/takeoff.gd",
		"note": "every length, area and count a plan is priced from",
	},
	{
		"what": "the survey engine",
		"one": "`Survey`, with `SurveyFile` for the file half",
		"path": "res://scripts/draft/survey.gd",
		"note": "a survey file read into points; nothing else parses one",
	},
	{
		"what": "the symbol vocabulary",
		"one": "`PlantSymbols`",
		"path": "res://scripts/plant_symbols.gd",
		"note": "which shape a plant is drawn as, derived from what the plant is",
	},
	{
		"what": "the place that words an area",
		"one": "`DraftUnits.format_area`",
		"path": "res://scripts/draft/units.gd",
		"note": "the only file in `scripts/` allowed to turn an area into words, enforced by `tests/test_area_units_doctrine.gd`",
	},
	{
		"what": "the undo history",
		"one": "`DraftGestureHistory`",
		"path": "res://scripts/draft/gesture_history.gd",
		"note": "a named, serial-numbered gesture, never a snapshot of state",
	},
	{
		"what": "the companion knowledge",
		"one": "`CropRotation`",
		"path": "res://scripts/crop_rotation.gd",
		"note": "the one place that answers what grows beside what - two tables, one answer",
	},
	{
		"what": "reading and writing JSON",
		"one": "`PlantCatalogue.read_json` and `PlantCatalogue.write_json`",
		"path": "res://scripts/plant_catalogue.gd",
		"note": "every write goes through a temporary file and a rename; these two are that one place",
	},
	{
		"what": "the verdict ordering",
		"one": "`PlantSuitability.worst_of`",
		"path": "res://scripts/plant_suitability.gd",
		"note": "every check in the food garden asks it for its verdict rather than carrying a copy of the rule",
	},
	{
		"what": "a caption shortened to fit its column",
		"one": "`SheetExporter.clipped_text`",
		"path": "res://scripts/draft/sheet_exporter.gd",
		"note": "both PDF pages shorten through it, the invoice sheet included",
	},
	{
		"what": "writing a manifest",
		"one": "`FieldManifestExporter.export_manifest`",
		"path": "res://scripts/io/field_manifest_exporter.gd",
		"note": "the only function that writes one, through a temporary file and a rename, so a save that fails never leaves a shorter file where the real one was",
	},
	{
		"what": "whether a file is a picture",
		"one": "`RasterUnderlay.sniff`",
		"path": "res://scripts/draft/raster_underlay.gd",
		"note": "the photo store and the underlay both ask it, and it reads the bytes rather than trusting an extension - nothing else gives a second opinion about a file",
	},
	{
		"what": "the sentinel for \"not stated\"",
		"one": "`TerrainProfile.no_value` and `value_stated`",
		"path": "res://scripts/terrain_profile.gd",
		"note": "the sentinel differs per set - 0 for sun, -1 for moisture, empty for soil - and lives in one place, so no check can read silence as an average",
	},
	{
		"what": "what the ground is like at one point",
		"one": "`ZoneMap.profile_at`",
		"path": "res://scripts/zone_map.gd",
		"note": "whether the answer came from the drawing or from a statement by hand, this is the one place the two are settled",
	},
	{
		"what": "the money",
		"one": "`Money`",
		"path": "res://scripts/biz/money.gd",
		"note": "integer minor units everywhere and never a float, because this build's floats are 32-bit and lose cents",
	},
	{
		"what": "the one context builder",
		"one": "`ContextReport`",
		"path": "res://tools/context_report.gd",
		"note": "the editor dock, the Ctrl+Shift+X tool and the headless runner all build through it, so they cannot disagree about what a pack holds",
	},
]


## The whole snapshot, as one markdown string. This is what the runners write.
static func build() -> String:
	var out := PackedStringArray()
	out.append("# Landscaping Planner - context snapshot")
	out.append("")
	out.append("Written for an outside code generator. Everything under **Derived** was read from")
	out.append("this project's files and settings at the moment of writing; the two hand-written")
	out.append("blocks are marked as such.")
	out.append("")
	_append_prose(out, "Project", _header_lines())
	_append_prose(out, "Specifications in docs/", _spec_lines())
	_append_prose(out, "Folder map", _folder_map_lines())
	_append_prose(out, "Tests and tools (names only)", _names_lines())
	_append_prose(out, "Data file shapes (derived) - one record of each",
			_data_shape_lines(_json_under("res://data")))
	_append_prose(out, "Conventions (from AGENTS.md)", _convention_lines())
	_append_prose(out, "The one of each thing - hand-written, checked against the disk",
			_single_source_lines())
	_append_prose(out, "A test file, as this project writes one", _test_file_lines())
	_append_prose(out, "The scene tree of the main scene (derived)", _scene_section_lines())
	_append_prose(out, "Hook points for the plant-ID / site-survey feature - hand-written",
			_feature_lines())
	_append_prose(out, "Script inventory (derived)", _inventory_lines())
	_append_prose(out, "If a rule you need is not here - hand-written", _ask_lines())
	out.append(build_models())
	return "\n".join(out)


## Only the per-script property, constant and signal sections - the part that is asked of each
## script rather than read off the filesystem.
static func build_models() -> String:
	var out := PackedStringArray()
	out.append("## Data models in detail (derived)")
	out.append("")
	for path: String in SCRIPTS:
		_append_script(out, path)
	return "\n".join(out) + "\n"


# --- subject packs --------------------------------------------------------------------------


static func subject_names() -> PackedStringArray:
	var names := PackedStringArray()
	for name: Variant in SUBJECTS.keys():
		names.append(String(name))
	names.sort()
	return names


static func has_subject(subject: String) -> bool:
	return SUBJECTS.has(subject)


## When to choose a subject: the one sentence a person picks by, shown in the dock under the scope
## picker. `""` is the whole snapshot, which is not a subject and has a sentence of its own. Asking for
## a subject that does not exist answers with nothing rather than inventing advice for it.
static func when_for(subject: String) -> String:
	if subject.is_empty():
		return WHOLE_WHEN
	if subject == REVIEW:
		return REVIEW_WHEN
	if not SUBJECTS.has(subject):
		return ""
	return String((SUBJECTS[subject] as Dictionary).get("when", ""))


## Where a runner writes. The whole snapshot keeps its own file and every pack gets one of its
## own, so a scoped export never overwrites the full one.
static func output_path(subject: String) -> String:
	if subject.is_empty():
		return "user://gemini_context.md"
	if subject == REVIEW:
		return "user://gemini_context_review.md"
	return "user://gemini_context_%s.md" % subject


# --- what a pack was built from ---------------------------------------------------------------


## A short **content address** for the files a pack quotes: its scripts and the documents it quotes
## sections from.
##
## It is a content address and not a timestamp or a commit, deliberately. A timestamp changes when a
## file is merely touched and a commit changes when an unrelated file is committed; "these exact bytes"
## is the claim a reader of a pack actually needs, and it is the same idea as the way this project names
## a photograph by its own bytes. It is eight characters of a SHA-256 over each path and its contents,
## so the same contents always give the same address and any edit gives a different one.
##
## Empty for a name that is not a subject: there is nothing to address, and inventing an address for a
## pack that does not exist would make the "nothing to say is left out" rule a lie.
static func fingerprint_for(subject: String) -> String:
	return _address_of(fingerprint_paths(subject))


## The content address of the files a **set** of subjects is about. A two-subject build is addressed
## over both of them, so its stale check covers everything the payload quotes.
static func pack_fingerprint(subjects: PackedStringArray) -> String:
	return _address_of(pack_paths(subjects))


## The union of several subjects' files, sorted and without duplicates.
static func pack_paths(subjects: PackedStringArray) -> PackedStringArray:
	var paths := PackedStringArray()
	for subject: String in subjects:
		for path: String in fingerprint_paths(subject):
			if not paths.has(path):
				paths.append(path)
	paths.sort()
	return paths


## A short content address over a list of files: each path and its contents, in the order given.
static func _address_of(paths: PackedStringArray) -> String:
	if paths.is_empty():
		return ""
	var parts := PackedStringArray()
	for path: String in paths:
		parts.append(path)
		parts.append(_read_text(path))
	return "\n".join(parts).sha256_text().substr(0, FINGERPRINT_CHARS)


## Where a two-subject build writes: a file named for both, so it can overwrite neither pack's own file
## nor the whole snapshot.
static func pair_output_path(first: String, second: String) -> String:
	return "user://gemini_context_%s+%s.md" % [first, second]


## The files a pack is **about**: its detailed scripts and the documents it quotes sections from,
## sorted. The content address is taken over exactly these, and a caller that wants to ask git what has
## changed lately passes the same list - so the two answers cannot be about different sets of files.
static func fingerprint_paths(subject: String) -> PackedStringArray:
	var paths := PackedStringArray()
	if not SUBJECTS.has(subject):
		return paths
	var entry: Dictionary = SUBJECTS[subject]
	for path: String in _string_lines(entry.get("scripts", [])):
		if not paths.has(path):
			paths.append(path)
	for section: Dictionary in (entry.get("sections", []) as Array):
		var doc := String(section["doc"])
		if not paths.has(doc):
			paths.append(doc)
	paths.sort()
	return paths


## What a pack carries, in words, for the line that names what it was built from.
static func _contents_words(entry: Dictionary) -> String:
	var scripts_n: int = (entry.get("scripts", []) as Array).size()
	var words: String = "%d script%s" % [scripts_n, "" if scripts_n == 1 else "s"]
	var docs := PackedStringArray()
	for section: Dictionary in (entry.get("sections", []) as Array):
		var doc := String(section["doc"])
		if not docs.has(doc):
			docs.append(doc)
	if not docs.is_empty():
		words += " and %d document%s" % [docs.size(), "" if docs.size() == 1 else "s"]
	return words


## The one line saying what a pack was built from, and what to do when it has moved on.
##
## A pack is pasted into a chat, and nothing in a chat can say whether it still describes the project:
## the reader cannot see a file that has changed underneath it. This line is the fact that can be
## checked, and the dock checks it every couple of seconds so the person pasting is told.
static func _fingerprint_lines(subject: String, entry: Dictionary) -> PackedStringArray:
	var address := fingerprint_for(subject)
	if address.is_empty():
		return PackedStringArray()
	var out := PackedStringArray()
	out.append("*Built from %s, content address `%s`. If a file it quotes has changed since, this pack"
			% [_contents_words(entry), address])
	out.append("is out of date - the dock says so, and rebuilding it is one press.*")
	return out


# --- a change under review --------------------------------------------------------------------


## The pack that is not a slice of the code but a slice of *time*: the change in hand. It is deliberately
## not in `SUBJECTS`, because it is not a part of the project - it is a question about the work going on
## in it, and its answer moves every time somebody edits a file.
const REVIEW := "review"
const REVIEW_LABEL := "A change under review"
const REVIEW_WHEN := "pick this to have a change judged or the next step suggested: it carries the work in progress, the commit it sits on, the files it touches and the rules those files' tests hold down."
## The characters `git status --short` writes in its two status columns. A line that starts with
## anything else is not a status line.
const STATUS_CHARS := " MADRCUT?!"


## Everything about the change in hand, and nothing about the rest of the project: the uncommitted work,
## the commit it sits on, the files it touches, and the rules their tests hold down. The same attachment
## the packs take, read for a different purpose - here the change is the subject rather than an extra, so
## a clean tree is answered by name instead of by an empty pack.
static func build_review(attachment: Dictionary = {}) -> String:
	var index: Dictionary = _use_index()
	var touched: PackedStringArray = touched_paths(String(attachment.get("git_status", "")))
	var out := PackedStringArray()
	out.append("# Context pack: a change under review")
	out.append("")
	out.append("One change, cut out of the project. Ask for it to be reviewed, argued with, or for the")
	out.append("next step - not for the whole design, which this does not carry.")
	out.append("")
	_append_prose(out, "Project", _header_lines())
	_append_prose(out, "Conventions (from AGENTS.md)", _convention_lines())
	_append_prose(out, "The one of each thing - hand-written, checked against the disk",
			_single_source_lines())
	_append_attachment(out, attachment)
	if touched.is_empty():
		_append_prose(out, "There is nothing uncommitted to review", _nothing_to_review())
		return "\n".join(out) + "\n"
	_append_prose(out, "The files this change touches - derived", _review_file_lines(touched, index))
	var rules: PackedStringArray = _review_rule_lines(touched, index)
	if not rules.is_empty():
		_append_prose(out, "The rules those files' tests hold down - derived", rules)
	_append_prose(out, "How to check a change to this work - derived",
			_verify_lines({"scripts": _touched_scripts(touched)}, index))
	_append_prose(out, "If a rule you need is not here - hand-written", _ask_lines())
	return "\n".join(out) + "\n"


## The files a `git status --short` names, as project paths. Porcelain prints two status letters and a
## space before each path and a rename as `old -> new`; a line that is neither is passed over rather than
## guessed at, so a caller that hands over a different format gets a shorter answer, not a wrong one.
static func touched_paths(status_text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for line: String in _lines_of(status_text):
		# A porcelain line is two status letters and a space, then the path. Anything else - a branch
		# header, a sentence - is passed over: a caller that hands over `git status` instead of
		# `--short` gets a shorter answer rather than a list of files that were never mentioned.
		if line.length() < 4 or line[2] != " ":
			continue
		if not STATUS_CHARS.contains(line[0]) or not STATUS_CHARS.contains(line[1]):
			continue
		var rest: String = line.substr(3).strip_edges()
		var arrow: int = rest.find(" -> ")
		if arrow >= 0:
			rest = rest.substr(arrow + 4).strip_edges()
		rest = rest.trim_prefix("\"").trim_suffix("\"")
		rest = rest.trim_prefix("res://")
		if rest.is_empty():
			continue
		var path := "res://" + rest
		if not out.has(path):
			out.append(path)
	return out


## One line per touched file saying what it is, because "review my change" is unanswerable until the
## reviewer knows which of these files is a rule, which is a page, and which is a record.
static func _review_file_lines(paths: PackedStringArray, index: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for path: String in paths:
		out.append("* `%s` - %s" % [path, _file_kind_words(path, index)])
	return out


static func _file_kind_words(path: String, index: Dictionary) -> String:
	if not FileAccess.file_exists(path):
		return "deleted, so the diff above is the only place it still exists"
	if path.begins_with("res://tests/") and path.ends_with(".gd"):
		return "a test file - the rules it holds down are listed below"
	if path.begins_with("res://scripts/") and path.ends_with(".gd"):
		var tests: PackedStringArray = _test_files_about(PackedStringArray([path]), index["texts"])
		if tests.is_empty():
			return "a script - no test file names it, which this project would want said out loud"
		return "a script - its rules are in `%s`" % tests[0]
	if path.ends_with(".md"):
		return "a document"
	if path.ends_with(".tscn"):
		return "a scene"
	if path.ends_with(".json"):
		return "a data file"
	if path.ends_with(".tres"):
		return "a resource"
	if path.ends_with(".gdshader"):
		return "a shader"
	if path.ends_with(".cfg") or path.get_file() == "project.godot":
		return "a project or plugin setting"
	if path.ends_with(".cs"):
		return "a C# script, which this project does not use - a change here is worth asking about"
	return "not a kind of file this project knows by its extension"


## The `func test_*` names of the tests that hold the touched scripts down. Prose can be argued with; a
## test name is the project's own statement of what it will not let break, which is what a reviewer of a
## change most needs and what a diff never shows.
static func _review_rule_lines(touched: PackedStringArray, index: Dictionary) -> PackedStringArray:
	var scripts: Array = _touched_scripts(touched)
	if scripts.is_empty():
		return PackedStringArray()
	return _rule_lines({"scripts": scripts}, index)


## The touched paths that are scripts: the half of a change that has rules and a test file of its own.
## A document, a scene or a deleted file has no test to run, so it is not named as one.
static func _touched_scripts(touched: PackedStringArray) -> Array:
	var scripts: Array = []
	for path: String in touched:
		if path.begins_with("res://scripts/") and path.ends_with(".gd") and not scripts.has(path):
			scripts.append(path)
	return scripts


static func _nothing_to_review() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("The repository is clean, so there is no change in hand to review. Leave the work")
	out.append("uncommitted or commit it and rebuild this pack, and the files it touches will be listed")
	out.append("here. The conventions above still say what a change to this project has to satisfy.")
	return out


## What a runner should build for a subject: the pack, or the whole snapshot for an empty name.
##
## `attachment` is what a caller can add beyond the subject, and every key is optional:
##
##     {"source_path": String, "source_text": String, "git_status": String, "git_diff": String,
##      "last_commit": String, "recent_commits": String, "last_run": String}
##
## the script somebody has open, the uncommitted work in the repository, the commit the work sits on,
## the commits that touched this work's own files, and the last test run. All of
## it is **text a caller has already obtained**: this file reads no file, runs no command and asks no
## editor for anything, which is what keeps packing testable with no repository and no editor present.
static func build_for(subject: String, attachment: Dictionary = {}) -> String:
	if subject == REVIEW:
		return build_review(attachment)
	if subject.is_empty():
		return _with_attachment(build(), attachment)
	return build_subject(subject, attachment)


## One subject's pack. An unknown subject is **refused by name** with the list of the ones that
## exist, rather than quietly building the whole snapshot - which would answer a different question
## than the one that was asked, and say nothing about it.
static func build_subject(subject: String, attachment: Dictionary = {}) -> String:
	if not SUBJECTS.has(subject):
		return "# Unknown subject: %s\n\nThere is no pack for that. The subjects are: %s\n" % [
				subject, ", ".join(subject_names()),
		]
	var entry: Dictionary = SUBJECTS[subject]
	var out := PackedStringArray()
	# The project, read once: the rules, the callers and where each named class lives all come out of
	# this, and building it per block would read four hundred files three times over.
	var index := _use_index()
	out.append("# Context pack: %s" % String(entry["title"]))
	out.append("")
	out.append("A scoped slice of this project: one subject, not the whole codebase.")
	out.append("")
	var address: PackedStringArray = _fingerprint_lines(subject, entry)
	if not address.is_empty():
		out.append_array(address)
		out.append("")
	_append_prose(out, "What this pack is for - hand-written", _string_lines(entry["brief"]))
	_append_shared(out)
	_append_derived(out, entry, index)
	_append_attachment(out, attachment)
	_append_prose(out, "Also worth knowing by name", _also_lines(entry, index))
	_append_prose(out, "Data file shapes - one record of each", _data_shape_lines(entry["data"]))
	_append_prose(out, "If a rule you need is not here - hand-written", _ask_lines())
	_append_prose(out, "What this pack leaves out", _left_out_lines(entry))
	return "\n".join(out) + "\n"


## Two subjects as **one** payload.
##
## A question that reaches across two subsystems otherwise forces a choice that loses the other half -
## and pasting two packs one after the other pastes the conventions, the one-of-each table and the test
## convention twice, which is several thousand tokens of the same text. So everything a pack has to say
## that is the same whatever it is about is printed once, and each subject's own blocks follow.
##
## An unknown name is refused **by name**, and two of the same is one pack rather than a payload that
## carries it twice.
static func build_pair(first: String, second: String, attachment: Dictionary = {}) -> String:
	for subject: String in [first, second]:
		if not SUBJECTS.has(subject):
			return "# Unknown subject: %s\n\nThere is no pack for that. The subjects are: %s\n" % [
					subject, ", ".join(subject_names()),
			]
	if first == second:
		return build_subject(first, attachment)
	var index := _use_index()
	var subjects := PackedStringArray([first, second])
	var out := PackedStringArray()
	out.append("# Context pack: two subjects - %s" % ", ".join(subjects))
	out.append("")
	out.append("Two scoped slices of this project in one payload. Everything a pack has to say that is the")
	out.append("same whatever it is about is printed **once**; each subject's own rules, scripts and callers")
	out.append("follow under a heading of its own.")
	out.append("")
	var address := pack_fingerprint(subjects)
	if not address.is_empty():
		out.append("*Built from both subjects' files, content address `%s`. If a file either of them quotes"
				% address)
		out.append("has changed since, this pack is out of date - rebuilding it is one press.*")
		out.append("")
	for subject: String in subjects:
		_append_prose(out, "What the '%s' pack is for - hand-written" % subject,
				_string_lines((SUBJECTS[subject] as Dictionary)["brief"]))
	_append_shared(out)
	for subject: String in subjects:
		out.append("## The '%s' pack" % subject)
		out.append("")
		_append_derived(out, (SUBJECTS[subject] as Dictionary), index)
	_append_attachment(out, attachment)
	_append_prose(out, "If a rule you need is not here - hand-written", _ask_lines())
	for subject: String in subjects:
		_append_prose(out, "What the '%s' pack leaves out" % subject,
				_left_out_lines(SUBJECTS[subject] as Dictionary))
	return "\n".join(out) + "\n"


## The blocks that are the **same in every pack**: the project header, the conventions quoted from
## `AGENTS.md`, the one-of-each table and the test convention. A two-subject build prints them once
## rather than twice, so a payload that carries two subjects is not carrying two copies of the rules.
static func _append_shared(out: PackedStringArray) -> void:
	_append_prose(out, "Project", _header_lines())
	_append_prose(out, "Conventions (from AGENTS.md)", _convention_lines())
	_append_prose(out, "The one of each thing - hand-written, checked against the disk",
			_single_source_lines())
	_append_prose(out, "A test file, as this project writes one", _test_file_lines())


## What is about **this work and nothing else**: the rules its tests hold down, how to check a change,
## its hook points, the specification sections quoted for it, its scripts, who uses what it declares,
## and the call graph. `index` is handed in rather than rebuilt, because a two-subject build reads the
## project once.
static func _append_derived(out: PackedStringArray, entry: Dictionary, index: Dictionary) -> void:
	_append_prose(out, "The rules this work's tests hold down - derived", _rule_lines(entry, index))
	_append_prose(out, "How to check a change to this work - derived", _verify_lines(entry, index))
	if bool(entry.get("hooks", false)):
		_append_prose(out, "Hook points - hand-written", _feature_lines())
	_append_specification(out, entry["sections"])
	out.append("## The scripts this work touches (derived)")
	out.append("")
	for path: String in entry["scripts"]:
		_append_script(out, path)
	_append_prose(out, "Who uses what this work declares - derived", _caller_lines(entry, index))
	_append_prose(out, "Who calls whom - derived", _graph_lines(entry, index))


## The open script's own source, so a pack can be about **editing** a file and not only about calling
## it. Everything else in a pack is derived from what a script declares; this is the one part that is
## the code as it stands, so a change can be proposed against what is really there.
##
## Capped at `SOURCE_LINE_CAP`, and the heading admits the cut in words when it bites: a silently
## shortened file would have a generator rewrite the lines it was never shown.
static func _source_lines(path: String, text: String) -> PackedStringArray:
	var lines: PackedStringArray = _lines_of(text)
	var out := PackedStringArray()
	if lines.size() <= SOURCE_LINE_CAP:
		out.append("## Full source of `%s` - %d lines" % [path, lines.size()])
	else:
		out.append("## The start of `%s` - the first %d of %d lines" % [
				path, SOURCE_LINE_CAP, lines.size()])
	out.append("")
	out.append("This is the file the request is about, quoted verbatim rather than summarised.")
	out.append("")
	out.append(FENCE)
	for index: int in mini(lines.size(), SOURCE_LINE_CAP):
		out.append(lines[index])
	out.append("```")
	return out


## Everything a caller attached beyond the subject, in a fixed order: the script in hand, the
## uncommitted work, then the last test run. A part with nothing to say is left out entirely, because
## an empty heading reads as "there was nothing" and "the export failed" in the same way.
static func _append_attachment(out: PackedStringArray, attachment: Dictionary) -> void:
	if attachment.is_empty():
		return
	var source_path: String = String(attachment.get("source_path", ""))
	if not source_path.is_empty():
		out.append_array(_source_lines(source_path, String(attachment.get("source_text", ""))))
		out.append("")
	out.append_array(_git_lines(
			String(attachment.get("git_status", "")), String(attachment.get("git_diff", ""))))
	out.append_array(_commit_lines(String(attachment.get("last_commit", ""))))
	out.append_array(_recent_lines(String(attachment.get("recent_commits", ""))))
	out.append_array(_last_run_lines(String(attachment.get("last_run", ""))))


## `text` with everything attached put at the foot, when anything was. The whole snapshot has no
## scripts section to file it after, so there it goes last; a pack puts it with the scripts.
static func _with_attachment(text: String, attachment: Dictionary) -> String:
	if attachment.is_empty():
		return text
	var out := PackedStringArray()
	var base: String = text
	if not base.ends_with("\n"):
		base += "\n"
	out.append(base)
	out.append("")
	_append_attachment(out, attachment)
	return "\n".join(out)


## The work that is in the repository but not committed, as `git status --short` and `git diff` printed
## it. A clean tree prints **nothing at all** rather than an empty section: "nothing is uncommitted"
## and "git is not installed here" would otherwise read the same way, and only the caller can tell them
## apart.
static func _git_lines(status_text: String, diff_text: String) -> PackedStringArray:
	if status_text.strip_edges().is_empty() and diff_text.strip_edges().is_empty():
		return PackedStringArray()
	var out := PackedStringArray()
	out.append("## Uncommitted changes")
	out.append("")
	out.append("The work in the repository that is not committed, read when this pack was built, so a")
	out.append("question about it can be asked with the code in hand.")
	out.append("")
	out.append("`git status --short`:")
	out.append("")
	_capped_block(out, status_text, "", DIFF_LINE_CAP)
	if not diff_text.strip_edges().is_empty():
		out.append("")
		out.append("`git diff`:")
		out.append("")
		_capped_block(out, diff_text, "diff", DIFF_LINE_CAP)
	out.append("")
	return out


## The commit the change in hand sits on, as `git log -1 --stat` printed it. A reviewer who cannot see
## the line the work continues will argue with a decision made two commits ago that is not in question;
## one commit shows the shape of that line without carrying the history.
static func _commit_lines(text: String) -> PackedStringArray:
	if text.strip_edges().is_empty():
		return PackedStringArray()
	var out := PackedStringArray()
	out.append("## The commit this change sits on")
	out.append("")
	out.append("`git log -1 --stat`, read when this pack was built.")
	out.append("")
	_capped_block(out, text, "", COMMIT_LINE_CAP)
	out.append("")
	return out


## The commits that touched this work's own files, as `git log --oneline` printed them.
##
## The rules and the one-of-each table say what the project **is**; this says what is moving in it,
## which is what a reader needs before proposing a change to a file somebody has been editing all week.
## Capped like every other pasted block, and the cut is said in words.
static func _recent_lines(text: String) -> PackedStringArray:
	if text.strip_edges().is_empty():
		return PackedStringArray()
	var out := PackedStringArray()
	out.append("## What has changed here lately")
	out.append("")
	out.append("The most recent commits touching the files this pack is about, read when it was built - so")
	out.append("a change can be proposed knowing what is in flux rather than against a file nobody has")
	out.append("opened since it was written.")
	out.append("")
	_capped_block(out, text, "", COMMIT_LINE_CAP)
	out.append("")
	return out


## The last test run, as `tools/run_tests.gd` left it. The **tail** is kept rather than the head,
## because the verdict and the failures are the last things a run prints, and a failure is the usual
## reason somebody is asking for help with a file.
static func _last_run_lines(text: String) -> PackedStringArray:
	if text.strip_edges().is_empty():
		return PackedStringArray()
	var lines: PackedStringArray = _lines_of(text)
	var from: int = maxi(0, lines.size() - RUN_TAIL_LINES)
	var out := PackedStringArray()
	out.append("## The last test run")
	out.append("")
	out.append("What `tools/run_tests.gd` last reported, so a rule that failed can be answered with the")
	out.append("run that failed rather than with a description of it.")
	out.append("")
	if from > 0:
		out.append("*The first %d of %d lines are not shown; the verdict is at the end.*" % [
				from, lines.size()])
		out.append("")
	out.append("```")
	for index: int in range(from, lines.size()):
		out.append(lines[index])
	out.append("```")
	out.append("")
	return out


## Fenced text, capped, with the cut stated in words after it. The one place pasted text is shown, so
## a status, a diff and a test log all read the same way.
static func _capped_block(
		out: PackedStringArray, text: String, language: String, cap: int
) -> void:
	var lines: PackedStringArray = _lines_of(text)
	out.append("```" + language)
	for index: int in mini(lines.size(), cap):
		out.append(lines[index])
	out.append("```")
	if lines.size() > cap:
		out.append("")
		out.append("*The last %d of %d lines are not shown.*" % [lines.size() - cap, lines.size()])


## A text's lines, with the empty last "line" a trailing newline produces taken off - that is not a
## line of the file, and printing it puts a blank line inside every fence.
static func _lines_of(text: String) -> PackedStringArray:
	var lines: PackedStringArray = text.split("\n")
	if not lines.is_empty() and lines[lines.size() - 1].is_empty():
		lines.remove_at(lines.size() - 1)
	return lines


static func _append_script(out: PackedStringArray, path: String) -> void:
	out.append("### %s" % path)
	out.append("")
	var script: Script = load(path) as Script
	if script == null:
		out.append("(not readable)")
		out.append("")
		return
	_append_section(out, "Script variables", _variable_lines(script))
	_append_section(out, "Constants", _constant_lines(script))
	_append_section(out, "Methods", _method_lines(script))
	_append_section(out, "Signals", _signal_lines(script))


## A section, or nothing at all when the script has none of that thing: an empty heading is
## worse than no heading, because it reads as "this script has none" and "the export failed"
## in the same way.
static func _append_section(out: PackedStringArray, title: String, lines: PackedStringArray) -> void:
	if lines.is_empty():
		return
	out.append("#### %s" % title)
	out.append(FENCE)
	out.append_array(lines)
	out.append("```")
	out.append("")


static func _variable_lines(script: Script) -> PackedStringArray:
	var lines := PackedStringArray()
	for prop in script.get_script_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			lines.append("- %s: %s" % [
					String(prop.name),
					_type_text(int(prop.type), String(prop.get("class_name", ""))),
			])
	return lines


static func _constant_lines(script: Script) -> PackedStringArray:
	var lines := PackedStringArray()
	var map: Dictionary = script.get_script_constant_map()
	var names: Array = map.keys()
	names.sort()
	for name: Variant in names:
		lines.append("- %s = %s" % [String(name), _value_text(map[name])])
	return lines


static func _signal_lines(script: Script) -> PackedStringArray:
	var lines := PackedStringArray()
	for sig: Dictionary in script.get_script_signal_list():
		var args := PackedStringArray()
		for arg: Dictionary in (sig["args"] as Array):
			args.append("%s: %s" % [String(arg["name"]), type_to_name(int(arg["type"]))])
		lines.append("- %s(%s)" % [String(sig["name"]), ", ".join(args)])
	return lines


## The functions, with the arguments they take and what they give back. This is the part a
## generator cannot guess from the member list, and the part it most needs: a call it invents
## with the wrong argument count is a parse error in a file it cannot run.
static func _method_lines(script: Script) -> PackedStringArray:
	var lines := PackedStringArray()
	for method: Dictionary in script.get_script_method_list():
		lines.append("- %s%s(%s) -> %s" % [
				"static " if (int(method["flags"]) & METHOD_FLAG_STATIC) != 0 else "",
				String(method["name"]),
				", ".join(_argument_texts(method)),
				_return_text(method),
		])
	return lines


static func _argument_texts(method: Dictionary) -> PackedStringArray:
	var args: Array = method["args"]
	var defaults: Array = method.get("default_args", [])
	# `default_args` are the *last* N arguments, so the first one carrying a default is the one
	# N from the end - not the first argument with a default written after it.
	var first_default: int = args.size() - defaults.size()
	var parts := PackedStringArray()
	for index: int in args.size():
		var arg: Dictionary = args[index]
		var text := "%s: %s" % [
				String(arg["name"]),
				_arg_type_text(int(arg["type"]), String(arg.get("class_name", ""))),
		]
		if index >= first_default:
			text += " = %s" % _default_text(defaults[index - first_default])
		parts.append(text)
	return parts


static func _return_text(method: Dictionary) -> String:
	var ret: Dictionary = method["return"]
	var named := String(ret.get("class_name", ""))
	if not named.is_empty():
		return named
	var type_id := int(ret["type"])
	# A return with `TYPE_NIL` is `void` when the function really returns nothing, and `Variant`
	# when it returns a value whose type is Variant (`PROPERTY_USAGE_NIL_IS_VARIANT`).
	if type_id == TYPE_NIL:
		if (int(ret.get("usage", 0)) & PROPERTY_USAGE_NIL_IS_VARIANT) != 0:
			return "Variant"
		return "void"
	return type_to_name(type_id)


## A parameter or member type as a caller would write it. A script or engine **class** names
## itself - `PlantCatalogue`, `Error`, `Node3D` - which says more than the bare `Object`/`int` id
## underneath it, and an enum arrives as `DraftUnits.System`. `TYPE_NIL` on a parameter or member
## is always `Variant`, never `void` (`void` is not a legal parameter type in GDScript).
static func _arg_type_text(type_id: int, named_type: String) -> String:
	if not named_type.is_empty():
		return named_type
	return type_to_name(type_id)


## Kept as an alias so existing callers of `_type_text` work unchanged.
static func _type_text(type_id: int, named_type: String) -> String:
	return _arg_type_text(type_id, named_type)


static func _default_text(value: Variant) -> String:
	if value == null:
		return "null"
	if value is StringName:
		return "&\"%s\"" % String(value)
	if value is String:
		return "\"%s\"" % String(value)
	return str(value)


## A constant's value as text. A preloaded script is named by its path rather than by its
## object id, which is the thing a reader can act on.
static func _value_text(value: Variant) -> String:
	if value is Script:
		return "(script) %s" % (value as Script).resource_path
	return str(value)


## The Godot type id as a person (or another program) names it. The real `TYPE_*` constants,
## because their values are not 0..9 and a hardcoded run of them is wrong from the second entry.
static func type_to_name(type_id: int) -> String:
	match type_id:
		TYPE_BOOL: return "bool"
		TYPE_INT: return "int"
		TYPE_FLOAT: return "float"
		TYPE_STRING: return "String"
		TYPE_STRING_NAME: return "StringName"
		TYPE_VECTOR2: return "Vector2"
		TYPE_VECTOR2I: return "Vector2i"
		TYPE_VECTOR3: return "Vector3"
		TYPE_COLOR: return "Color"
		TYPE_ARRAY: return "Array"
		TYPE_DICTIONARY: return "Dictionary"
		TYPE_OBJECT: return "Object"
		_: return "Variant"


# --- sections -------------------------------------------------------------------------------


## Prose, not code: a heading and the lines under it, with no fence.
static func _append_prose(out: PackedStringArray, title: String, lines: PackedStringArray) -> void:
	if lines.is_empty():
		return
	out.append("## %s" % title)
	out.append("")
	out.append_array(lines)
	out.append("")


# --- the project header, read from ProjectSettings -----------------------------------------


static func _setting(name: String, fallback: String) -> String:
	if not ProjectSettings.has_setting(name):
		return fallback
	return str(ProjectSettings.get_setting(name))


static func _autoload_names() -> PackedStringArray:
	var names := PackedStringArray()
	for prop in ProjectSettings.get_property_list():
		var key := String(prop.name)
		if key.begins_with("autoload/"):
			var autoload_name := key.trim_prefix("autoload/")
			if autoload_name == "ZivaPlaytestIO":
				continue
			names.append(autoload_name)
	names.sort()
	return names


static func _header_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("- Engine: Godot %s" % Engine.get_version_info().string)
	out.append("- Main scene: %s" % _setting("application/run/main_scene", "(none)"))
	out.append("- Viewport: %s x %s, stretch %s / %s" % [
			_setting("display/window/size/viewport_width", "?"),
			_setting("display/window/size/viewport_height", "?"),
			_setting("display/window/stretch/mode", "?"),
			_setting("display/window/stretch/aspect", "?"),
	])
	out.append("- Renderer: %s" % _setting("rendering/renderer/rendering_method", "?"))
	out.append("- Physics: %s" % _setting("physics/3d/physics_engine", "?"))
	var autoloads := _autoload_names()
	out.append("- Autoloads: %s" % ("none" if autoloads.is_empty() else ", ".join(autoloads)))
	out.append("- Editor plugins enabled: %s" % _setting("editor_plugins/enabled", "(none)"))
	return out


# --- what the folders hold, and what the specs say ------------------------------------------


static func _names_in(folder: String, suffix: String) -> PackedStringArray:
	var names := PackedStringArray()
	var dir := DirAccess.open(folder)
	if dir == null:
		return names
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(suffix):
			names.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	names.sort()
	return names


static func _names_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("Tests (one file per module, `extends Node`, several `test_*` methods):")
	out.append("")
	out.append(", ".join(_names_in("res://tests", ".gd")))
	out.append("")
	out.append("Dev tools (`tools/`, run headless with `-s` or live with run_scene, not shipped):")
	out.append("")
	out.append(", ".join(_names_in("res://tools", ".gd")))
	return out


# --- the shape of a data file ---------------------------------------------------------------


static func _json_under(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	for path: String in _files_under(dir_path):
		if path.ends_with(".json"):
			out.append(path)
	out.append("user://site_manifest.json")
	return out


## One record from each data file, under its own heading.
##
## A caller that names files gets those; the snapshot names every JSON under `res://data`. An
## importer written against a class's members alone gets the *keys* wrong - the file is keyed by id
## and a record's fields are the model's own, lower-cased - so the shape itself is shown.
static func _data_shape_lines(paths: Array) -> PackedStringArray:
	var out := PackedStringArray()
	if paths.is_empty():
		return out
	out.append("One record of each file, read with `JSON.parse_string` - so every number prints as a")
	out.append("float (`0.0` where the file says `0`), which is also what a Godot reader gets.")
	out.append("")
	for path: String in paths:
		var sample := _sample_record(path)
		out.append("### %s" % path)
		out.append("")
		if sample.is_empty():
			out.append("(not readable as JSON)")
			out.append("")
			continue
		out.append(FENCE_JSON)
		out.append_array(sample)
		out.append("```")
		out.append("")
	return out


static func _sample_record(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	if path == "user://site_manifest.json":
		var sample_manifest: Dictionary = FieldManifestExporterScript.to_manifest(
			"Elm Street",
			[
				{
					"instance_id": "capture-1",
					"species_id": "acer-platanoides-crimson-king",
					"confidence": 0.92,
					"position": Vector3(2.0, 0.0, 2.0),
					"sun_mask": 1,
					"drainage_mask": 7,
					"notes": "front border",
				},
			]
		)
		for line: String in JSON.stringify(sample_manifest, "  ").split("\n"):
			out.append(line)
		return out
	var parsed: Variant = JSON.parse_string(_read_text(path))
	if parsed == null:
		return out
	var block: PackedStringArray = JSON.stringify(_first_record(parsed), "  ").split("\n")
	var shown: int = min(block.size(), SAMPLE_LINES)
	for index: int in range(shown):
		out.append(block[index])
	if block.size() > shown:
		out.append("  ... %d more lines" % (block.size() - shown))
	return out


## The first record in a parsed file: the first entry of the first collection it holds, kept under
## its collection's key so the reader sees how records are keyed rather than only what one holds.
static func _first_record(parsed: Variant) -> Variant:
	if parsed is Array:
		var list: Array = parsed
		return list[0] if not list.is_empty() else {}
	if parsed is Dictionary:
		var dict: Dictionary = parsed
		for key: Variant in dict.keys():
			var value: Variant = dict[key]
			if value is Dictionary and not (value as Dictionary).is_empty():
				var inner: Dictionary = value
				var first: Variant = inner.keys()[0]
				return {String(key): {String(first): inner[first]}}
			if value is Array and not (value as Array).is_empty():
				return {String(key): (value as Array)[0]}
		return dict
	return parsed


static func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


# --- a worked test file ---------------------------------------------------------------------


## The test convention, as a file. It is short enough to state and long enough to get wrong, and a
## generated test that does not match it is a test the runner will not find or will not report.
static func _test_file_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("One file per module at `res://tests/test_<module>.gd`, `extends Node`, with several")
	out.append("`test_*` methods. Each test gets a **fresh instance** of the file, so state kept in a member")
	out.append("starts empty; helpers are `_`-prefixed and are never run as tests; and a test that makes a")
	out.append("node frees it, or the leak is inherited by the next run.")
	out.append("")
	out.append(FENCE)
	out.append("extends Node")
	out.append("## One sentence saying what this file holds down.")
	out.append("")
	out.append("const ThingScript := preload(\"res://scripts/thing.gd\")")
	out.append("const ThingWindowScript := preload(\"res://scripts/thing_window.gd\")")
	out.append("")
	out.append("")
	out.append("## The name states the rule, so a failure here reads as the rule that broke.")
	out.append("func test_a_spread_that_cannot_be_worked_out_is_refused_rather_than_guessed() -> void:")
	out.append("\tvar thing: Thing = ThingScript.new()")
	out.append("")
	out.append("\tassert(thing.spread() == ThingScript.UNKNOWN, \"it refuses rather than answering 0\")")
	out.append("\tassert(thing.spread_text() == \"\", \"and it hands on no words rather than \\\"0 m\\\"\")")
	out.append("")
	out.append("")
	out.append("## A page is built directly: no scene, no window server, no dock.")
	out.append("func test_the_page_shows_the_refusal_the_model_gave() -> void:")
	out.append("\tvar page: ThingWindow = ThingWindowScript.new()")
	out.append("\tpage.build()")
	out.append("")
	out.append("\tassert(page.figure_text() == ThingWindowScript.NO_FIGURE, \"the page says what is missing\")")
	out.append("")
	out.append("\tpage.free()   # a node a test makes is freed by the test")
	out.append("```")
	out.append("")
	out.append("Run the whole suite with `res://tools/run_tests.tscn`, headless and with no editor; one file")
	out.append("with `-- res://tests/test_<module>.gd`. It exits non-zero when anything failed.")
	out.append("")
	out.append("A headless CLI tool in `res://tools/*.gd` (`godot --headless -s res://tools/x.gd -- arg1`):")
	out.append("")
	out.append(FENCE)
	out.append("extends SceneTree")
	out.append("## One sentence saying what this tool does.")
	out.append("")
	out.append("func _init() -> void:")
	out.append("\tvar args := OS.get_cmdline_user_args()")
	out.append("\tquit(0)")
	out.append("```")
	return out


# --- the rules the tests hold down -----------------------------------------------------------


## The rules the pack's tests hold down, in the tests' own words.
##
## Every `func test_*` name in this project is a sentence saying a rule - that is the convention, and the
## runner reports a failure as that sentence. So the names are the **acceptance criteria** for a change
## to this work, for a fraction of the tokens the bodies would cost: a change that breaks one of them is
## a change that broke the project.
##
## Derived, so it cannot go stale. In this project a test preloads the scripts it is about **by path**,
## so a test file that names one of the pack's scripts is a test about this work and nothing has to be
## guessed. Capped per file, and the cap is said in words rather than applied in silence.
static func _rule_lines(entry: Dictionary, index: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var files := _test_files_about(_string_lines(entry.get("scripts", [])), index["texts"])
	if files.is_empty():
		return out
	out.append("Every test name in this project is a sentence saying a rule, so the list below is the")
	out.append("acceptance criteria for a change to this work, in the tests' own words:")
	for file: String in files:
		var names := _test_names(file)
		if names.is_empty():
			continue
		out.append("")
		if names.size() > TEST_RULE_CAP:
			out.append("`%s` - the first %d of %d rules:" % [file, TEST_RULE_CAP, names.size()])
		else:
			out.append("`%s` - %d rule%s:" % [file, names.size(), "" if names.size() == 1 else "s"])
		for row in mini(names.size(), TEST_RULE_CAP):
			out.append("* `%s`" % names[row])
	return out


## How a change to this work is checked: the test files that hold it down, as **files**, and the
## command that runs them.
##
## The rules block above says what the tests assert, in the tests' own words; this is the half a
## reader can *act* on, because a command can be run and a convention can only be read. It carries the
## project's own rule - run the **whole** suite, not only the file you touched - because the suite is
## the arbiter of "does it work", and it is fast enough to be run every time.
##
## Derived, like the rules: the files come from `_test_files_about`, so the list cannot name a test
## file that has gone.
static func _verify_lines(entry: Dictionary, index: Dictionary) -> PackedStringArray:
	var files := _test_files_about(_string_lines(entry.get("scripts", [])), index["texts"])
	if files.is_empty():
		return PackedStringArray()
	var out := PackedStringArray()
	out.append("Every rule above is a test. Run the files that hold this work down while you work, then")
	out.append("**the whole suite**: it is the arbiter, and it is fast. `res://tools/run_tests.tscn` runs")
	out.append("headless with no editor and exits non-zero when anything failed (`godot` below is this")
	out.append("project's engine binary, whatever it is called on the machine you are on):")
	out.append("")
	out.append("```")
	out.append("# the whole suite, after every change")
	out.append("godot --headless --path . res://tools/run_tests.tscn")
	out.append("")
	out.append("# one file, while you are working on it")
	out.append("godot --headless --path . res://tools/run_tests.tscn -- %s" % files[0])
	out.append("```")
	out.append("")
	var named := PackedStringArray()
	for file: String in files:
		named.append("`%s`" % file)
	out.append("The files that hold this work down: %s." % ", ".join(named))
	return out


## The test files that are about this work, in path order, capped.
##
## Two signals, both from conventions this project already keeps, so neither has to be guessed:
##
## * **The name.** *One file per module*: `res://scripts/x.gd` is tested by `res://tests/test_x.gd`.
## * **The preload.** A test preloads the scripts it is about **by path**, so a test naming two or more
##   of this work's scripts is a test of this work - which is how a page's test arrives, since a page is
##   named in `also` and its file path is not derivable from the pack.
static func _test_files_about(script_paths: PackedStringArray, texts: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if script_paths.is_empty():
		return out
	var all := PackedStringArray()
	for path: Variant in texts.keys():
		var where := String(path)
		if where.begins_with("res://tests/"):
			all.append(where)
	all.sort()
	# The module's own test file first, so the rules a *model* holds are never crowded out by the rules a
	# page holds - the models are where the invariants live.
	for path: String in script_paths:
		var named := "res://tests/test_%s.gd" % path.get_file().get_basename()
		if all.has(named) and not out.has(named):
			out.append(named)
	if out.size() >= TEST_FILE_CAP:
		return out
	for path: String in all:
		if out.has(path):
			continue
		var text: String = String(texts[path])
		var named_count: int = 0
		for wanted: String in script_paths:
			if text.contains("\"%s\"" % wanted):
				named_count += 1
		if named_count < TEST_RELATION:
			continue
		out.append(path)
		if out.size() >= TEST_FILE_CAP:
			break
	return out


## Every `func test_*` name in a test file, in the order they are written. Helpers are `_`-prefixed by
## the convention and so are never named here.
static func _test_names(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	for line: String in _read_lines(path):
		var trimmed: String = line.strip_edges()
		if not trimmed.begins_with("func test_"):
			continue
		out.append(trimmed.trim_prefix("func ").split("(")[0].strip_edges())
	return out


# --- the one of each thing -------------------------------------------------------------------


## The one-of-each-thing table as prose: what the thing is, where it is, and why there must not be a
## second one. A reader who was about to write one of these is the reader this block is for.
static func _single_source_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("**There is exactly one of each thing.** A second engine that can disagree with the first is")
	out.append("the defect this project spends the most effort avoiding. Before writing anything that looks")
	out.append("like one of these, use the one that is there - and if it does not fit, say so rather than")
	out.append("adding a second:")
	out.append("")
	for row: Dictionary in SINGLE_SOURCES:
		out.append("* **%s** - %s in `%s`: %s" % [
			String(row["what"]), String(row["one"]), String(row["path"]), String(row["note"]),
		])
	return out


# --- the scene tree of the main scene --------------------------------------------------------


## Which node carries which script, read out of the `.tscn` itself rather than restated.
static func _scene_section_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var path := _setting("application/run/main_scene", "res://scenes/main.tscn")
	out.append("`%s`, in full. A node that is an **instance** of another scene carries that scene's nodes" % path)
	out.append("in its own file, so they are not listed here; everything else is the node's own.")
	out.append("")
	out.append_array(_scene_lines(path))
	return out


static func _scene_lines(scene_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var lines := _read_lines(scene_path)
	if lines.is_empty():
		return out
	var resources: Dictionary = {}
	var nodes: Array = []
	for line: String in lines:
		if line.begins_with("[ext_resource"):
			var id := _attribute(line, "id")
			if not id.is_empty():
				resources[id] = _attribute(line, "path")
			continue
		if line.begins_with("[node "):
			nodes.append({"path": _node_path_in(line), "type": _attribute(line, "type"),
					"instance": _instance_id(line), "script": ""})
			continue
		if line.strip_edges().begins_with("script = ExtResource(") and not nodes.is_empty():
			var id := line.strip_edges().trim_prefix("script = ExtResource(").trim_suffix(")")
			(nodes[nodes.size() - 1] as Dictionary)["script"] = String(
					resources.get(id.replace("\"", ""), ""))
	for node: Dictionary in nodes:
		var detail := String(node["type"])
		var instance := String(node["instance"])
		if not instance.is_empty():
			detail = "instance of `%s`" % String(resources.get(instance, "?"))
		var script := String(node["script"])
		out.append("- `%s` (%s)%s" % [
				String(node["path"]), detail, "" if script.is_empty() else " - script `%s`" % script])
	return out


## A quoted attribute of a `[node ...]` or `[ext_resource ...]` line, e.g. `name="Hud"`.
##
## The marker has to be **preceded by a space**, or `id="..."` finds the `id="` inside `uid="..."` and
## every resource that carries a uid answers with its uid instead of its id.
static func _attribute(line: String, key: String) -> String:
	var marker := key + "=\""
	var at := line.find(marker)
	while at >= 0:
		if at == 0 or line[at - 1] == " ":
			var from := at + marker.length()
			var to := line.find("\"", from)
			return "" if to < 0 else line.substr(from, to - from)
		at = line.find(marker, at + 1)
	return ""


## The scene an instanced node comes from, written `instance=ExtResource("4_yard")` - an id, not a
## quoted attribute, so it needs its own reader.
static func _instance_id(line: String) -> String:
	var marker := "instance=ExtResource(\""
	var at := line.find(marker)
	if at < 0:
		return ""
	var from := at + marker.length()
	var to := line.find("\"", from)
	return "" if to < 0 else line.substr(from, to - from)


## A `[node name="X" parent="Y" ...]` line's path inside its scene: `/Name`, or `/Parent/Name`. The one
## place the rule lives, because the scene tree and the binding report have to agree about it.
static func _node_path_in(line: String) -> String:
	var node_name := _attribute(line, "name")
	var parent := _attribute(line, "parent")
	if parent.is_empty() or parent == ".":
		return "/" + node_name
	return "/%s/%s" % [parent, node_name]


static func _first_heading(text: String) -> String:
	for line: String in text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("# "):
			return trimmed.trim_prefix("# ").strip_edges()
	return ""


static func _spec_lines() -> PackedStringArray:
	var out := PackedStringArray()
	for name: String in _names_in("res://docs", ".md"):
		var path := "res://docs/" + name
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var text := file.get_as_text()
		file.close()
		out.append("- `%s` - %d lines - %s" % [path, text.count("\n") + 1, _first_heading(text)])
	return out


static func _folder_summary(folder: String) -> String:
	var dir := DirAccess.open(folder)
	if dir == null:
		return "not present"
	var scripts_n := 0
	var scenes_n := 0
	var other_n := 0
	var folders_n := 0
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if dir.current_is_dir():
			if not name.begins_with("."):
				folders_n += 1
		elif name.ends_with(".gd"):
			scripts_n += 1
		elif name.ends_with(".tscn"):
			scenes_n += 1
		else:
			other_n += 1
		name = dir.get_next()
	dir.list_dir_end()
	# "here" is this folder's own files and "in the subtree" is everything below it, so a folder
	# that holds only subfolders does not read as an empty one.
	return "%d scripts, %d scenes, %d other files here, %d subfolders; %d scripts in the subtree" % [
			scripts_n, scenes_n, other_n, folders_n, _gd_paths(folder).size(),
	]


static func _folder_map_lines() -> PackedStringArray:
	var out := PackedStringArray()
	for folder: String in [
		"res://scenes", "res://scripts", "res://scripts/biz", "res://scripts/draft",
		"res://scripts/io", "res://scripts/utils", "res://scripts/vis",
		"res://tests", "res://tools", "res://data", "res://docs", "res://addons",
	]:
		out.append("- `%s/` - %s" % [folder, _folder_summary(folder)])
	var data_files := _files_under("res://data")
	if not data_files.is_empty():
		out.append("")
		out.append("Data files: %s" % ", ".join(data_files))
	out.append("")
	out.append("`addons/` is third-party (the Ziva MCP bridge, the GitHub release dock and the")
	out.append("business/visualization editor docks). Generate nothing that depends on its internals.")
	return out


# --- the inventory, derived from the scripts themselves --------------------------------------


static func _gd_paths(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	for path: String in _files_under(dir_path):
		if path.ends_with(".gd"):
			out.append(path)
	return out


## Every file under a folder, recursively, sorted. Directories beginning with a `.` are skipped.
static func _files_under(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		var path := dir_path.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with("."):
				out.append_array(_files_under(path))
		else:
			out.append(path)
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


## The class's own summary: the whole first paragraph of the `##` doc comment that follows the
## class declaration.
##
## A **paragraph** and not a line: these doc comments are hard-wrapped, so one line of one is a
## sentence cut off in the middle ("...how big it gets, and"), which reads as a broken summary
## rather than as a summary that was kept short.
##
## And the comment that *follows the declaration*, not simply the first `##` line in the file: in
## a file whose class was never given a doc comment, the first `##` line is a *member's* doc
## comment, and printing it states a rule about one constant as if it described the whole class.
static func _doc_line(path: String) -> String:
	var lines := _read_lines(path)
	if lines.is_empty():
		return ""

	var anchor := -1
	for index: int in lines.size():
		if lines[index].strip_edges().begins_with("extends"):
			anchor = index + 1
			break
	if anchor < 0:
		for index: int in lines.size():
			if lines[index].strip_edges().begins_with("##"):
				anchor = index
				break
	if anchor < 0:
		return ""
	return _paragraph_from(lines, anchor)


## The first paragraph of `##` lines from `start`: everything up to the first bare `##` or the
## first line that is not a doc comment, joined into one line. A leading bare `##` is skipped,
## because a doc comment may open with one.
static func _paragraph_from(lines: PackedStringArray, start: int) -> String:
	var parts := PackedStringArray()
	for index: int in range(start, lines.size()):
		var trimmed := lines[index].strip_edges()
		if trimmed.is_empty():
			continue
		if not trimmed.begins_with("##"):
			break
		var text := _strip_hashes(trimmed)
		if text.is_empty():
			if parts.is_empty():
				continue
			break
		parts.append(text)
	return " ".join(parts)


static func _strip_hashes(line: String) -> String:
	var text := line
	while text.begins_with("#"):
		text = text.substr(1)
	return text.strip_edges()


static func _inventory_line(path: String) -> String:
	var script: Script = load(path) as Script
	if script == null:
		return "- `%s` - could not be read" % path
	var named := String(script.get_global_name())
	if named.is_empty():
		named = "(no class_name) " + path.get_file().get_basename()
	var members := 0
	for prop in script.get_script_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			members += 1
	var methods_n: int = script.get_script_method_list().size()
	var signals_n: int = script.get_script_signal_list().size()
	var summary := _doc_line(path)
	return "- `%s` (%s) - %d members, %d methods, %d signals - `%s`%s" % [
			named, String(script.get_instance_base_type()), members, methods_n, signals_n, path,
			"" if summary.is_empty() else " - " + summary,
	]


static func _inventory_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var paths := _gd_paths("res://scripts")
	out.append("%d scripts under `res://scripts`, sorted by path. Each line: class name (base type) -"
			% paths.size())
	out.append("member, method and signal counts - path - the script's own doc comment, first paragraph.")
	out.append("")
	for path: String in paths:
		out.append(_inventory_line(path))
	return out


# --- the two hand-written blocks -------------------------------------------------------------


## The project's conventions, **quoted from `AGENTS.md`** - which is where an agent working in this
## repository reads them, and the one place they are written down. Restating them here would be two
## copies of the rules, and two copies drift; the quoting machinery is the same one that cuts a
## specification section out of `docs/`.
static func _convention_lines() -> PackedStringArray:
	var lines := _section_lines(AGENTS_PATH, "Conventions", true)
	if lines.is_empty():
		lines.append("> **MISSING SECTION** - `%s` has no \"Conventions\" heading." % AGENTS_PATH)
	return lines


static func _feature_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("The feature being built is an **offline mobile plant-ID and site-survey** tool that")
	out.append("writes files this project imports. The pieces already here to hang it on:")
	out.append("")
	out.append("- **The catalogue is owned by the HUD.** `Hud.plant_list()` (scripts/hud.gd) reads")
	out.append("  `user://plants/catalogue.json`, else seeds `res://data/plants/nursery_list.json`, and")
	out.append("  is the one instance the browser shows. Never build a second `PlantCatalogue` inside the")
	out.append("  running app: a capture filed in a second one is invisible to the browser. In a standalone")
	out.append("  headless tool with no HUD, load via `PlantCatalogue.load_from(path) -> {\"ok\": bool,")
	out.append("  \"catalogue\": PlantCatalogue, \"reason\": String}` (falling back to")
	out.append("  `\"res://data/plants/nursery_list.json\"`).")
	out.append("- **Placement:** `PlantPlacement.place(catalogue, species_id, yard, at) -> {\"ok\": bool,")
	out.append("  \"node\": Node3D, \"reason\": String}` instances and sizes the prop under `<yard>/Plants`,")
	out.append("  and touches no camera, view mode or dock. `PlantPlacement.planted(yard)` reads the")
	out.append("  planted nodes back; `PlantPlacement.schedule(catalogue, yard)` and")
	out.append("  `PlantPlacement.schedule_text(catalogue, yard)` build the planting schedule.")
	out.append("- **The manifest:** `FieldManifestExporter` (`export_manifest`, `to_manifest`,")
	out.append("  `read_manifest(path) -> {\"ok\": bool, \"reason\": String, \"data\": Dictionary}`,")
	out.append("  `FORMAT_VERSION`). `SurveyWatcher` (scripts/survey_watcher.gd) watches")
	out.append("  `user://site_manifest.json` on a 1.5 s Timer and imports what is new.")
	out.append("- **Naming a capture:** `PlantIDResolver` (`resolve(raw_name, catalogue) -> PlantSpecies`,")
	out.append("  `resolve_identification(text, confidence) -> {\"status\": String, \"match_type\": String,")
	out.append("  \"species\": PlantSpecies, \"confidence\": float}`, `as_id`, `best_id_match`, `rank_of`)")
	out.append("  turns a typed or spoken name into a species with a confidence, and refuses below a")
	out.append("  floor rather than filing an unsure capture.")
	out.append("- **Bits:** `BitMaskUtils` (scripts/utils/) for sun hours and edible parts, against the")
	out.append("  constants on `PlantSpecies`. The sun and drainage masks are bitfields, not enums.")
	out.append("- **Survey geometry already exists:** `Survey` (scripts/draft/survey.gd, all static and")
	out.append("  pure) does bearings, metes and bounds and alignment as a similarity transform, and")
	out.append("  `SurveyFile` reads a surveyor's own tabular file. Reuse them rather than writing a")
	out.append("  second survey engine; `Geom2D` and `DraftUnits` sit underneath.")
	out.append("- **Reporting what a drawing holds:** `SiteReport` reads the takeoff rather than measuring")
	out.append("  a second time.")
	out.append("- **Specification:** `docs/plant-database-spec.md` is the authority on the plant model.")
	return out


# --- reading a file's lines, and a specification's sections ---------------------------------


## Every line of a file. The one reader: a document is read here and nowhere else.
static func _read_lines(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return out
	while not file.eof_reached():
		out.append(file.get_line())
	file.close()
	return out


static func _string_lines(value: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if value is Array:
		for item: Variant in (value as Array):
			out.append(String(item))
	return out


## A heading's text with the `#` markers taken off, or "" when the line is not a heading.
static func _heading_text(line: String) -> String:
	var text := line.strip_edges()
	if not text.begins_with("#"):
		return ""
	return _strip_hashes(text)


static func _heading_level(line: String) -> int:
	var level := 0
	for character: String in line.strip_edges():
		if character != "#":
			break
		level += 1
	return level


## One section of a specification: the heading whose text begins with `heading_prefix`, and
## everything up to the next heading of the same or a higher level. Empty when nothing matches,
## which the caller reports rather than hides.
##
## `drop_heading` is for the one caller whose own heading already names the section - quoting
## `AGENTS.md`'s conventions under a `## Conventions (from AGENTS.md)` heading would otherwise print
## a heading immediately followed by the same heading again.
static func _section_lines(
		doc_path: String, heading_prefix: String, drop_heading: bool = false
) -> PackedStringArray:
	var lines := _read_lines(doc_path)
	var start := -1
	var level := 0
	var body := PackedStringArray()
	for index: int in lines.size():
		var text := _heading_text(lines[index])
		if text.is_empty():
			continue
		if start < 0:
			if text.begins_with(heading_prefix):
				start = index
				level = _heading_level(lines[index])
			continue
		if _heading_level(lines[index]) <= level:
			body = _slice(lines, start, index)
			break
	if start < 0:
		return PackedStringArray()
	if body.is_empty():
		body = _slice(lines, start, lines.size())
	return _body_after_heading(body) if drop_heading else body


## A section's body: its first line is the heading, and this is that line and any blank lines under
## it taken off.
static func _body_after_heading(lines: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for index: int in range(1, lines.size()):
		if out.is_empty() and lines[index].strip_edges().is_empty():
			continue
		out.append(lines[index])
	return out


static func _slice(lines: PackedStringArray, from: int, to: int) -> PackedStringArray:
	var out := PackedStringArray()
	for index: int in range(from, to):
		out.append(lines[index])
	return out


## The specification sections, quoted verbatim. A heading the document no longer has is printed as
## a **MISSING SECTION** line in the pack itself: a section that silently went missing would leave
## the reader with rules that are not in the pack it is reading.
static func _append_specification(out: PackedStringArray, sections: Array) -> void:
	if sections.is_empty():
		return
	out.append("## Specification (quoted verbatim from `docs/`)")
	out.append("")
	for section: Dictionary in sections:
		var doc := String(section["doc"])
		for heading: String in section["headings"]:
			var body := _section_lines(doc, heading)
			if body.is_empty():
				out.append("> **MISSING SECTION** - `%s` has no heading starting \"%s\"." % [doc, heading])
				out.append("")
				continue
			out.append("*From `%s`:*" % doc)
			out.append("")
			out.append_array(body)
			out.append("")


# --- who uses what this work declares ---------------------------------------------------------


## The project's calls, indexed once per build: `"<owner>.<name>" -> the files making that call`, where
## an owner is either the **path** of the script an alias loads, or the class name a call was written
## against.
##
## Two patterns do the work, and both are C++ rather than a per-character walk in GDScript: a call
## written `receiver.name(`, and an alias written `const Alias := preload("res://...")`. Resolving the
## receiver is what makes this a fact rather than a word count - `crop_sun.gd` has its own `check`, and
## without the receiver it would be counted as a caller of `CropRotation.check` and of every other
## `check` in the project.
##
## The index is rebuilt for each pack rather than cached. It costs one pass over `res://scripts` and
## `res://tests`; a cache in an editor that stays open would answer about a file that has since changed
## shape, and a wrong answer here is worse than a slow one.
## The project as the derived blocks need to see it: every script and test read once, every call
## resolved, every class located and every scene's script bindings - built once and kept while the
## corpus is unchanged.
##
## The stamp is every indexed file's path and **modification time**, scenes included: a stat per file
## rather than a read, and any write touches it, so the cache cannot answer about a file that has since
## changed shape. Without the cache the index costs about a second and every pack pays it again; with it
## every pack after the first costs the stats.
static var _index_cache: Dictionary = {}
static var _index_stamp: String = ""


static func _use_index() -> Dictionary:
	var scripts := PackedStringArray()
	for folder: String in ["res://scripts", "res://tests"]:
		scripts.append_array(_gd_paths(folder))
	var scenes := PackedStringArray()
	for path: String in _files_under("res://scenes"):
		if path.ends_with(".tscn"):
			scenes.append(path)
	var stamp := PackedStringArray()
	for path: String in scripts:
		stamp.append("%s:%d" % [path, FileAccess.get_modified_time(path)])
	for path: String in scenes:
		stamp.append("%s:%d" % [path, FileAccess.get_modified_time(path)])
	var words := "|".join(stamp)
	if _index_stamp == words and not _index_cache.is_empty():
		return _index_cache

	var call_pattern := RegEx.new()
	call_pattern.compile("([A-Za-z_][A-Za-z0-9_]*)\\.([A-Za-z_][A-Za-z0-9_]*)\\(")
	var alias_pattern := RegEx.new()
	alias_pattern.compile("const[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]*:=[ \t]*preload\\(\"([^\"]+)\"\\)")
	var by_call: Dictionary = {}
	var texts: Dictionary = {}
	var classes: Dictionary = {}
	for path: String in scripts:
		var text := _read_text(path)
		texts[path] = text
		var named := _class_name_in(text)
		if not named.is_empty() and not classes.has(named):
			classes[named] = path
		var aliases := _aliases_in(text, alias_pattern)
		for found: RegExMatch in call_pattern.search_all(text):
			var owner := String(aliases.get(found.get_string(1), found.get_string(1)))
			_record_call(by_call, "%s.%s" % [owner, found.get_string(2)], path)
	_index_cache = {
		"by_call": by_call,
		"texts": texts,
		"classes": classes,
		"bindings": _scene_bindings(scenes),
	}
	_index_stamp = words
	return _index_cache


## The class a script declares, read from its opening lines. The convention is that a file opens with
## `class_name X` and then `extends Y`, so this reads the head of the file and stops at the first thing
## that is neither a comment nor the declaration.
static func _class_name_in(text: String) -> String:
	var seen := 0
	for line: String in text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.is_empty() or trimmed.begins_with("#") or trimmed.begins_with("@"):
			continue
		if trimmed.begins_with("class_name "):
			return trimmed.trim_prefix("class_name ").strip_edges()
		seen += 1
		if seen >= 2:
			break
	return ""


## Every `const Alias := preload("res://...")` in a text, as alias -> the path it loads.
static func _aliases_in(text: String, pattern: RegEx) -> Dictionary:
	var out: Dictionary = {}
	for found: RegExMatch in pattern.search_all(text):
		var alias := found.get_string(1)
		if not out.has(alias):
			out[alias] = found.get_string(2)
	return out


## One caller against one "owner.name" key, without ever listing a file twice under it.
static func _record_call(by_call: Dictionary, key: String, path: String) -> void:
	var callers: Array = by_call.get(key, [])
	if not callers.has(path):
		callers.append(path)
	by_call[key] = callers


## What a script declares that somebody else could depend on: its public functions and its signals.
## A `_`-prefixed function is a helper of its own file - and the engine's callbacks are `_`-prefixed
## too, which is the right answer for both: nobody calls `_ready` on purpose.
static func _symbols(script: Script) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for method: Dictionary in script.get_script_method_list():
		var name := String(method.get("name", ""))
		if name.begins_with("_") or name.is_empty():
			continue
		out.append({"name": name, "kind": "func"})
	for sig: Dictionary in script.get_script_signal_list():
		var name := String(sig.get("name", ""))
		if not name.is_empty():
			out.append({"name": name, "kind": "signal"})
	return out


## Who uses one symbol, as file paths, sorted.
##
## A **function** is answered from the call index, whose keys have their receiver already resolved - so
## `CropRotationScript.check(` and `CropRotation.check(` both land on this class and nobody else's
## `check` does.
##
## A **signal** cannot be resolved that way: `closed.connect(` does not say whose `closed` it is, and
## half the pages in this program have a `closed`. So a signal's users are found **by name**, and the
## block says so rather than letting a name match read as a fact.
static func _users_of(
		name: String, kind: String, decl_path: String, decl_class: String, index: Dictionary
) -> PackedStringArray:
	var out := PackedStringArray()
	if kind == "signal":
		var texts: Dictionary = index["texts"]
		for path: Variant in texts.keys():
			var where := String(path)
			if where == decl_path:
				continue
			var text := String(texts[path])
			if text.contains("%s.emit(" % name) or text.contains("%s.connect(" % name):
				out.append(where)
		out.sort()
		return out
	var by_call: Dictionary = index["by_call"]
	for owner: String in [decl_path, decl_class]:
		if owner.is_empty():
			continue
		for path: Variant in (by_call.get("%s.%s" % [owner, name], []) as Array):
			var where := String(path)
			if where != decl_path and not out.has(where):
				out.append(where)
	out.sort()
	return out


## How many files use a symbol, and which: the count is always given, because "2 files" and "and 6
## more" are different answers to "is it safe to change this".
static func _caller_words(callers: PackedStringArray) -> String:
	var shown := PackedStringArray()
	for index in mini(callers.size(), CALLER_CAP):
		shown.append("`%s`" % callers[index])
	var words: String = ", ".join(shown)
	if callers.size() > shown.size():
		words += " and %d more" % (callers.size() - shown.size())
	return "%d file%s - %s" % [callers.size(), "" if callers.size() == 1 else "s", words]


## Who uses what this work declares.
##
## The list exists for the failure this project has had before and is built to avoid: a change that
## quietly broke a caller, or a second implementation of something half the project already calls. A
## reader about to rename or re-shape one of these can see what is holding on to it first.
static func _caller_lines(entry: Dictionary, index: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var texts: Dictionary = index
	var lines := PackedStringArray()
	for path: String in _string_lines(entry.get("scripts", [])):
		var script: Script = load(path) as Script
		if script == null:
			continue
		for symbol: Dictionary in _symbols(script):
			var callers := _users_of(
				String(symbol["name"]), String(symbol["kind"]), path,
				String(script.get_global_name()), texts
			)
			if callers.is_empty():
				continue
			lines.append("* `%s.%s`%s - %s" % [
				path.get_file().get_basename(), String(symbol["name"]),
				" (a signal)" if String(symbol["kind"]) == "signal" else "",
				_caller_words(callers),
			])
	if lines.is_empty():
		return out
	lines.sort()
	out.append("What each of these files' public functions and signals is used by, read out of")
	out.append("`res://scripts` and `res://tests`. Before renaming or reshaping one of these, this is what")
	out.append("is holding on to it - and a second implementation of one is a second implementation of")
	out.append("something already in use. A function's callers are resolved through the file's own preload")
	out.append("aliases, so they are a fact; a signal's are a **name match**, because `closed.connect(` does")
	out.append("not say whose `closed` it is:")
	out.append("")
	for row in mini(lines.size(), CALLER_LINE_CAP):
		out.append(lines[row])
	if lines.size() > CALLER_LINE_CAP:
		out.append("")
		out.append("*%d more are not shown.*" % (lines.size() - CALLER_LINE_CAP))
	return out


## Whether `caller` calls any public function `other` declares, from the resolved call index. The same
## facts the caller block reads, asked the other way round.
static func _calls_any_of(caller: String, other: String, by_call: Dictionary) -> bool:
	var script: Script = load(other) as Script
	if script == null:
		return false
	var symbols: Array[Dictionary] = _symbols(script)
	for owner: String in [other, String(script.get_global_name())]:
		if owner.is_empty():
			continue
		for symbol: Dictionary in symbols:
			var key := "%s.%s" % [owner, String(symbol["name"])]
			for path: Variant in (by_call.get(key, []) as Array):
				if String(path) == caller:
					return true
	return false


## The pack's own files drawn as a **call graph**: an arrow from one file to another means a file in
## this pack calls a public function of the other.
##
## This is the one thing a reader otherwise has to assemble by hand out of the caller block, which
## lists callers one symbol at a time. It is derived from the same resolved index, so an arrow is the
## same kind of fact - a receiver alias is followed, and a file with its own `check` is not drawn as
## calling another module's. Only the pack's own scripts are nodes: the shape of *this* work is what the
## graph is for, not the shape of the project.
##
## Nothing at all when there is nothing to draw: a work of one file, or of files that call nothing in
## each other, gets no empty diagram.
static func _graph_lines(entry: Dictionary, index: Dictionary) -> PackedStringArray:
	var scripts := PackedStringArray()
	for path: String in _string_lines(entry.get("scripts", [])):
		if FileAccess.file_exists(path):
			scripts.append(path)
	if scripts.size() < 2:
		return PackedStringArray()
	var by_call: Dictionary = index["by_call"]
	var ids: Dictionary = {}
	var nodes := PackedStringArray()
	for at: int in scripts.size():
		ids[scripts[at]] = "n%d" % at
		nodes.append("n%d[\"%s\"]" % [at, scripts[at].get_file().get_basename()])
	var edges := PackedStringArray()
	for caller: String in scripts:
		for other: String in scripts:
			if other != caller and _calls_any_of(caller, other, by_call):
				edges.append("%s --> %s" % [ids[caller], ids[other]])
	if edges.is_empty():
		return PackedStringArray()
	var out := PackedStringArray()
	out.append("An arrow from one file to another means a file in this pack **calls** a public function of")
	out.append("the other - the same resolved index the block above reads, drawn instead of listed. It is")
	out.append("the shape of this work, which a reader would otherwise have to assemble by hand:")
	out.append("")
	out.append("```mermaid")
	out.append("flowchart LR")
	for node: String in nodes:
		out.append("  " + node)
	for at: int in mini(edges.size(), GRAPH_EDGE_CAP):
		out.append("  " + edges[at])
	out.append("```")
	if edges.size() > GRAPH_EDGE_CAP:
		out.append("")
		out.append("*%d further arrow%s are not drawn.*" % [
				edges.size() - GRAPH_EDGE_CAP, "" if edges.size() - GRAPH_EDGE_CAP == 1 else "s"])
	return out


static func _also_lines(entry: Dictionary, index: Dictionary) -> PackedStringArray:
	var names := _string_lines(entry.get("also", []))
	if names.is_empty():
		return PackedStringArray()
	var out := PackedStringArray()
	out.append("Named so a reader knows they exist and can ask for them; the full snapshot carries")
	out.append("their members, constants, methods and signals. Where each one is, and whether a scene binds")
	out.append("it, is read off the disk - a class by its own `class_name` line, a scene by naming the script.")
	out.append("")
	for name: String in names:
		var path: String = _class_path(name, index)
		if path.is_empty():
			out.append("* `%s` - no script in `res://scripts` declares that name, so this one has drifted" % name)
			continue
		out.append("* `%s` - `%s` - %s" % [name, path, _binding_words(path, index)])
	return out


## Where a class is: the script whose own `class_name` line declares it, found once in the index.
static func _class_path(name: String, index: Dictionary) -> String:
	return String((index["classes"] as Dictionary).get(name, ""))


## Which scenes bind which script, and **which node** carries it: read out of the `.tscn` files, where
## an `ext_resource` line gives a script its id and a node that carries `script = ExtResource("<id>")`
## names the node. A script named by an `ext_resource` line that no node carries is not reported as
## bound, because the binding this reports has to be a fact.
##
## The value of a script's entry is `<scene> - <node path>`, so a reader of a pack is told not only that
## something binds the script but where.
static func _scene_bindings(scenes: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for path: String in scenes:
		var by_id: Dictionary = {}
		var node_path := ""
		for line: String in _read_lines(path):
			if line.begins_with("[ext_resource"):
				var id := _attribute(line, "id")
				var script_path := _attribute(line, "path")
				if not id.is_empty() and script_path.begins_with("res://scripts/"):
					by_id[id] = script_path
				continue
			var trimmed := line.strip_edges()
			if trimmed.begins_with("[node "):
				node_path = _node_path_in(trimmed)
				continue
			if not trimmed.begins_with("script = ExtResource(") or node_path.is_empty():
				continue
			var held := trimmed.trim_prefix("script = ExtResource(").trim_suffix(")")
			held = held.trim_prefix("\"").trim_suffix("\"")
			if not by_id.has(held):
				continue
			var bound: String = by_id[held]
			var binders: Array = out.get(bound, [])
			var entry := "%s - %s" % [path, node_path]
			if not binders.has(entry):
				binders.append(entry)
			out[bound] = binders
	return out


## How a script is reached: the scene and node that bind it, or that none does. A page in this project
## is usually built in code (`build()`) rather than laid out in a scene, and a generator that assumes
## the other one writes a node path that is not there.
##
## The **node** is named and not only the scene: a scene path is half an answer, and the node path is
## what a generated line needs in order to work.
static func _binding_words(script_path: String, index: Dictionary) -> String:
	var scenes: Array = (index["bindings"] as Dictionary).get(script_path, [])
	if scenes.is_empty():
		return "no scene binds it, so it is made in code"
	var shown := PackedStringArray()
	for entry: Variant in scenes:
		var parts := String(entry).split(" - ")
		shown.append("`%s` at `%s`" % [parts[0], parts[1] if parts.size() > 1 else "?"])
	if shown.size() > CALLER_CAP:
		return "bound in %s and %d more" % [shown[0], shown.size() - 1]
	return "bound in %s" % ", ".join(shown)


static func _ask_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("This is a slice of a larger project, and a slice always has an edge. **If a rule you need is")
	out.append("not stated here, say so and ask for it to be written down** rather than inventing one: a rule")
	out.append("invented in a file that cannot be run is a rule nobody can check. The same goes for a figure -")
	out.append("if a number is not in this material, ask where it comes from instead of choosing one.")
	return out


static func _left_out_lines(entry: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	out.append("One subject of %d scripts in `res://scripts` (the %d above are detailed in full, with"
			% [_gd_paths("res://scripts").size(), (entry["scripts"] as Array).size()])
	out.append("their members, constants, methods and signals). The specification sections quoted above are")
	out.append("the ones this work has to obey; the rest of the project - and the rest of `docs/` - is")
	out.append("deliberately absent. Run the exporter with no subject for the whole snapshot when the work")
	out.append("reaches past this list, or pick the pack for the other half of it.")
	return out