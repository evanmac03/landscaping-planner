class_name HelpDoc
extends RefCounted
## The manual: what this program is and everything it does, in the order a person meets it.
##
## One topic per subject, each a title and a body of plain text. It is data rather than a screen: the
## page that shows it (`HelpWindow`) reads topics and does not know one subject from another, and a
## test can read the whole manual without a window at all.
##
## ## Why the words are here rather than in the documentation folder
##
## `docs/` holds specifications - what was decided and why, written for somebody changing the code.
## This holds the manual - what a person sitting in front of the program can do, and what happens
## when they do it. They answer different questions, so they are different documents, and a
## specification that drifted from the program would still be a useful record of a decision.
##
## ## What is not written down here
##
## The **keys**. Every key is already in one place - the input map and the tool tables - and the
## reference built from them is a view of those tables rather than a fourth copy of them. The HUD
## appends that reference as the last topic, so the manual cannot name a key that does nothing.

## The subjects the manual has to cover, in the order they are shown.
##
## Written out rather than derived, and a test reads it: "document everything" is only a claim if
## somebody has said what *everything* is. A topic that is dropped from `topics()` should fail a
## test rather than quietly stop being documented.
const SUBJECTS: Array[String] = [
	"What this program is",
	"Finding any command: the palette",
	"The three views",
	"Drawing: the nine tools",
	"Snapping and precision",
	"Editing shapes",
	"Layers, units and the site",
	"The ground under the garden",
	"Importing somebody else's file",
	"Tracing over a picture",
	"Plants",
	"Water: irrigation",
	"Light: garden lighting",
	"What it costs: takeoff and estimate",
	"Leads and the pipeline",
	"Jobs, crews and the schedule",
	"Billing and the books",
	"Presenting the garden",
	"Sheets and plotting",
	"Working with others",
	"Undo, revisions and where your files are",
]


# --- reading the manual ----------------------------------------------------------------------


## Every topic, in the order they are read.
static func topics() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append(_topic("What this program is", [
		"A design studio for a garden: it draws the plan, plants it, waters it, lights it, prices the "
		+ "work, schedules the crews, bills the client and renders the picture.",
		"",
		"There is one 3D world and three views of it - the 2D plan, the 3D overhead and the ground view "
		+ "at eye level - so a shape moved in one place is moved in all of them. The drawing is the "
		+ "design: the plan, the sheet, the picture and the price are all projections of it, and nothing "
		+ "is measured twice.",
		"",
		"The app opens in the 2D plan. The menu bar across the top is the whole program: File, Edit, "
		+ "View, Draft, Site, Plant, Water, Light, Pipeline, Jobs, Estimate, Present, Team and Help. The "
		+ "palette down the left holds the drawing tools and the layers. The lines in the corners name "
		+ "the keys.",
		"",
		"Help > Landscaping Planner help opens this manual, Help > Drawing keys opens the key "
		+ "reference, and Help > Command palette opens one box that reaches every command there is. "
		+ "Everything the bar offers is described in here.",
	]))
	out.append(_topic("Finding any command: the palette", [
		"Help > Command palette opens a box holding every command the program has, with a field to type "
		+ "into. It is the shortest way to reach something whose name you know and whose menu you do "
		+ "not: type a word and the list narrows to the commands that mention it - the ones named after "
		+ "it first, then the ones merely filed under a menu of that name.",
		"",
		"Ctrl+P opens the same box from anywhere in the program. Type to narrow the list, the up and "
		+ "down arrows move through it, Enter runs the command that is chosen, and Escape puts the box "
		+ "away.",
		"",
		"A row says three things: what the command is called, the key that also does it, and the menu it "
		+ "lives under. A command that cannot be used in the drawing you have open says so in place of "
		+ "its menu, and picking it says the same thing rather than doing nothing - the bar greys out "
		+ "what the scene cannot do instead of hiding it, and this box keeps that rule. Nothing is ever "
		+ "offered that is not in the menus, because the list is read out of the bar itself.",
		"",
		"The rest of this manual describes what each of those commands does; this is only the way in.",
	]))
	out.append(_topic("The three views", [
		"2D plan - the drafting view: linework, dimensions, planting symbols and hatching, measured and "
		+ "drawn exactly.",
		"3D overhead - the same garden from above in three dimensions, with the plants and the built "
		+ "elements standing on the ground.",
		"Ground view - eye level in the garden. Walk it, look around, and see what the design is like "
		+ "from the path.",
		"",
		"Q swaps the 2D plan and the 3D overhead; V and Tab do the same thing. G goes into the ground "
		+ "view and back out of it. View > 2D plan / 3D overhead / Ground view goes to any of the three "
		+ "directly, and View > Fit the design to the screen does what F does.",
		"",
		"F fits the design to the screen. In the overhead views, W A S D pans, a right-drag pans and the "
		+ "wheel zooms. In the ground view, W A S D walks, Shift runs, the mouse or the arrow keys look "
		+ "around, and Esc gives the cursor back.",
		"",
		"Painted plan (R) draws the plan the way it would be printed and coloured by hand, with the beds "
		+ "washed and the species in their own colours. It is a picture of the same drawing, not a second "
		+ "drawing.",
		"",
		"View > Control hints switches the corner hints off once you know the keys and want the screen "
		+ "back.",
	]))
	out.append(_topic("Drawing: the nine tools", [
		"Turn the tools on with D (Draft > Drawing tools). Nothing can be drawn while they are away, "
		+ "which is also what stops a stray key from putting a shape on the plan.",
		"",
		"Each tool is a small state machine: it takes the picks it needs and then commits one shape.",
		"",
		"1  line         two picks",
		"2  polyline     as many picks as you like, finished or closed",
		"3  rectangle    two opposite corners, and that is the diagonal",
		"4  circle       the centre, then a point on the circle",
		"5  arc          the centre, the start, and the direction to sweep to",
		"6  measure      two picks: reports the distance and the direction, draws nothing",
		"7  aligned dim  two points to measure and somewhere to put the line",
		"8  linear dim   the same, measured along the axis the picks lie along",
		"9  radial dim   the centre and a point on the circle, with a leader",
		"",
		"Enter finishes a polyline, C closes it into a polygon, Backspace drops the last point picked, "
		+ "and Escape cancels the shape in hand without putting the tool away.",
		"",
		"The measure tool is a check rather than a drawing: it never commits anything. The three "
		+ "dimension commands are annotations - they are drawn on the dimension layer, they are kept out "
		+ "of the 3D views, and they are never counted as work to be priced.",
		"",
		"Everything is drawn on the layer in hand, and nothing can be drawn onto a locked layer.",
	]))
	out.append(_topic("Snapping and precision", [
		"The cursor is snapped by priority rather than by closeness, so a snap that is merely the "
		+ "nearest thing to the pointer never wins over one the design intends.",
		"",
		"Endpoints, midpoints, centres, quadrant points and the intersections of the shapes near the "
		+ "cursor; perpendicular and tangent points from the previous pick; and a point along an outline. "
		+ "Ortho and polar tracking hold the direction from the previous point.",
		"",
		"The aperture is measured in pixels rather than in metres, so it behaves the same at every zoom. "
		+ "Once a candidate has locked it is held until another clearly beats it, and the lock survives "
		+ "leaving the aperture - otherwise the cursor flickers between two equally good candidates and a "
		+ "line gets made at the wrong one.",
		"",
		"A pick is snapped before the tool sees it, so a tool never has to know what the cursor is "
		+ "holding. Two points closer than a micron describe nothing, and are refused rather than "
		+ "committed.",
	]))
	out.append(_topic("Editing shapes", [
		"Six commands, on letters, for geometry that already exists. Arm one and it prompts for its own "
		+ "picks.",
		"",
		"O  offset   draw a new shape a fixed distance out from the one you pick",
		"T  trim     cut the picked piece of a line away at whatever crosses it",
		"X  extend   grow the picked end of a line out to the next shape",
		"I  fillet   round the corner where two lines meet, to a radius",
		"E  erase    take the picked shape off the drawing",
		"U  rotate   turn the picked shape about a point you pick, to the direction you click",
		"",
		"A turn is rigid and spelled out for every kind of shape, so a turned bed is the same bed and a "
		+ "circle's centre moves while its radius does not.",
		"",
		"Edit > Simplify reduces the number of points on a straight-sided shape, by a tolerance measured "
		+ "on paper. It asks before it changes anything, it refuses a shape whose shared corner would be "
		+ "dragged off a neighbour's, and it refuses curved work by name rather than flattening an arc.",
		"",
		"The selection band comes in two modes from the Edit menu. Window takes only what is wholly "
		+ "inside the band; crossing takes anything the band touches. Neither one sweeps up a locked "
		+ "layer, and an annotation cannot be erased with the erase command.",
		"",
		"Every one of these is a single undo step, with a name of its own.",
	]))
	out.append(_topic("Layers, units and the site", [
		"The preset layer set covers the work a landscape drawing is made of: the property, the ground, "
		+ "planting beds, lawn, paving, water, lighting, the irrigation, the hatch, the dimensions, the "
		+ "text, the site's existing conditions, and an underlay.",
		"",
		"Each layer has a purpose, a pen weight and whether it plots. The underlay layer does not plot, "
		+ "which is what makes an imported DXF or site map something to trace over rather than something "
		+ "that can reach a client's sheet by accident.",
		"",
		"A layer may be hidden - drawn nowhere - or locked. A locked layer's geometry is still drawn on "
		+ "the screen, but it cannot be picked, edited, or drawn onto; locking is shown in the palette "
		+ "beside the layer and in the Edit menu, and it is one undoable step.",
		"",
		"The drawing states its units, metric or imperial, and every length and area in the program is "
		+ "written in them. An area is turned into words in exactly one place, so a plan cannot end up "
		+ "with two spellings of a square metre.",
		"",
		"The site itself - where it is, and what the ground is like - belongs to the drawing and travels "
		+ "with the file.",
	]))
	out.append(_topic("The ground under the garden", [
		"A plant's suitability is a question about the ground it stands in: how much sun, how wet it is, "
		+ "what the soil is, how it drains, and how cold the winters get.",
		"",
		"Site > What the ground is like states those five things for the whole site, and then for any "
		+ "single area of the plan that is not like the rest - the strip under the eaves is dry, the far "
		+ "corner is wet all spring, the bed on the north side never sees the sun. Whatever is not stated "
		+ "is drawn grey rather than green: a check that guessed would be inventing a garden.",
		"",
		"Site > Draw a ground zone states the ground for a piece of land that nothing on the plan "
		+ "encloses - a frost pocket, a strip of shade - by drawing its outline with the polygon tool.",
		"",
		"Site > Read the ground from the drawing reads what the buildings and the hard surfaces on the "
		+ "plan already imply. It cannot tell you about shade, soil or the fall of the land: those are "
		+ "site visits.",
		"",
		"Site > Check the planting reports what is planted in the wrong place, and Site > Site statistics "
		+ "reports what the drawing covers, measured by layer.",
	]))
	out.append(_topic("Importing somebody else's file", [
		"Four imports, all from the File menu, and all of them land on a layer that does not plot.",
		"",
		"Import a survey - a plan of survey as bearings and distances, as an azimuth list, or as a list "
		+ "of coordinates. A file that does not state its units is refused until you say what they are, "
		+ "and a unit you give never overrides one the file states. The closure of the traverse, the area "
		+ "it comes to and its extent are checked and reported: a loose traverse is a warning, not a "
		+ "refusal.",
		"",
		"Import a DXF underlay - somebody else's CAD drawing, read as linework, arcs, curves and text, "
		+ "with the curves of a polyline kept as curves. What cannot be drawn is counted and named rather "
		+ "than quietly dropped.",
		"",
		"Import a site map (OpenStreetMap) - the site's surroundings from the public map, fetched for a "
		+ "radius around the drawing's own coordinates or read from a saved response. Buildings come in "
		+ "as outlines, streets as lines, trees as rings, and a feature that runs off the extract is "
		+ "named.",
		"",
		"Import a LandXML plat - a surveyor's plat, read as parcels, points and alignments. A curve "
		+ "becomes the curve of the line it is part of, and a spiral breaks the line it is in and is "
		+ "named.",
		"",
		"Each import is one undo step whatever the file holds, and each one says what it read before the "
		+ "drawing takes it.",
	]))
	out.append(_topic("Tracing over a picture", [
		"A picture under the drawing is a tracing aid: a scan of a surveyor's plan, a marked-up print, an "
		+ "aerial photograph, a consultant's concept drawing. File > Put a picture under the drawing "
		+ "opens the page for it.",
		"",
		"Only the format and the pixel size are read out of the file's header, so a very large scan is "
		+ "not decoded just to be measured, and the picture is copied into the program's own folder. A "
		+ "drawing that pointed at a picture on somebody else's drive would be broken on every other "
		+ "machine it was sent to.",
		"",
		"It is placed by how far it lies across the ground, in the drawing's own units; the picture's own "
		+ "proportion supplies the other direction, so a plan cannot be stretched out of shape. The same "
		+ "page turns it and sets how see-through it is, and all three can be changed afterwards by "
		+ "choosing the picture out of the list at the foot of the page.",
		"",
		"A picture is not geometry. It never plots, never snaps, is never measured and is never bought "
		+ "by the square metre, and it does not enlarge the drawing's own extent - so putting one under a "
		+ "drawing cannot change the scale a sheet is plotted at.",
		"",
		"It lies over the yard's own ground and under every line, which is what makes it possible to "
		+ "trace over. Putting it under the drawing is one undoable step and taking it off is another, "
		+ "and the copy stays where it is, so undo can always put the picture back.",
	]))
	out.append(_topic("Plants", [
		"The plant library (L) is the catalogue: every species with its mature spread, its hardiness, the "
		+ "light and the water it wants, the months it blooms and what it is tagged for. Narrow it by "
		+ "zone, month, light, water or tag, sort it the way you think, and choose the plant you want.",
		"",
		"A planted plant is one object in both views, standing where you click and sized at the spread "
		+ "the catalogue states. Place the chosen plant, then Stop planting when you are done.",
		"",
		"Filling a bed is a spacing and an arrangement: choose a bed the plan encloses, a spacing and "
		+ "whether the rows are square or staggered, and the bed is planted with the number that fits, "
		+ "kept clear of its own edges.",
		"",
		"Label the planting writes a label at the middle of each group, naming the species and counting "
		+ "it. The plan's plant symbols come from the species themselves - nine shapes - and a conifer is "
		+ "recognised by its botanical name rather than by being called an evergreen.",
		"",
		"The ground you have stated is what turns a plant's ring green or red while you place it: a plant "
		+ "in the right place for the light, the water, the soil and the cold.",
		"",
		"A plant list can be imported and exported, so a nursery's list can be brought in without "
		+ "retyping it.",
	]))
	out.append(_topic("Water: irrigation", [
		"Water > Water an area lays a zone out: choose the area, the kind of head, the spacing as a "
		+ "fraction of the head's throw, and whether the rows are staggered.",
		"",
		"The supply - the flow and the pressure at the tap - is stated once for the drawing, and a zone "
		+ "is checked against it: a zone that would need more water than the supply gives is refused, "
		+ "naming the numbers and what does fit. A rotor on a supply that will not drive it is refused "
		+ "too.",
		"",
		"Every zone is given a valve number, and the heads, the runs and the valve are drawn on the plan "
		+ "on the irrigation layer. The sheet carries an irrigation schedule: the zones, what they water, "
		+ "how many heads, and what they come to.",
		"",
		"Taking the water off an area takes its heads with it.",
	]))
	out.append(_topic("Light: garden lighting", [
		"Light > Light an area lays a circuit out the way irrigation lays out a zone: the area, the kind "
		+ "of fixture, the spacing and the stagger.",
		"",
		"The transformer is stated once for the drawing - its voltage and what it can carry - and each "
		+ "circuit's load is checked against it. A circuit over the transformer is refused, naming what it "
		+ "would draw and what the transformer gives; a line-voltage fixture on a low-voltage transformer "
		+ "is refused as well.",
		"",
		"Unlike irrigation, two kinds of fixture may share one circuit, because a lighting circuit is not "
		+ "a valve with one reason.",
		"",
		"Cover is reported rather than refused: if the fixtures do not quite reach the edges of the area, "
		+ "the shortfall is said, with the figures.",
		"",
		"Fixtures, runs and the transformer are drawn on the lighting layer, and the sheet carries a "
		+ "lighting schedule with each circuit's load.",
	]))
	out.append(_topic("What it costs: takeoff and estimate", [
		"Estimate > Take off the plan measures the drawing: the areas, the lengths and the counts, by "
		+ "layer, from the same linework the plan is drawn with. Nothing is measured twice, because the "
		+ "drawing was measured as it was drawn.",
		"",
		"The takeoff is priced from the cost book: a list of items with their unit, their cost, their "
		+ "waste and their markup, and the kits that expand into their own lines. A line the book cannot "
		+ "price is named rather than dropped, and a figure that cannot be worked out is refused, naming "
		+ "what is missing, rather than reported as nothing.",
		"",
		"The estimate window shows what the plan measures, what that prices at, and the price list it "
		+ "came from. Tax is charged through the codes, each for its own share of the lines it applies "
		+ "to, with the components of a code compounding in the order the code states.",
		"",
		"Estimate > Check the numbers says whether the arithmetic foots. Sending an estimate names the "
		+ "customer and freezes what went out; a change to a sent estimate is a new draft, and the sent "
		+ "one never moves. Starting a job hands the estimate over, with its lines and its cost codes, to "
		+ "the job.",
	]))
	out.append(_topic("Leads and the pipeline", [
		"Pipeline > Open the pipeline board is the sales board: a card per lead, moving across the "
		+ "stages.",
		"",
		"A lead records where it came from, what it is worth and when it is expected to close. Every "
		+ "move from one stage to the next is written down as it happens, rather than the stage being set "
		+ "as a field that can be edited away, and a lead cannot be lost without saying why.",
		"",
		"The board reports the open pipeline raw and weighted by the odds of each stage, and the funnel "
		+ "counts where leads entered each stage rather than where they are now - so a figure for a past "
		+ "window is worked out from the events again rather than remembered.",
	]))
	out.append(_topic("Jobs, crews and the schedule", [
		"Jobs > Open the schedule board is the week: a block per crew member per day, with the clashes "
		+ "reported rather than hidden.",
		"",
		"A job is made from an estimate and carries its cost codes, the contract sum and how it is "
		+ "billed - fixed price, milestones, time and materials, cost plus, or a period. A job's phases "
		+ "group its estimate by cost code, so the budget is what was sold and the cost is what is spent.",
		"",
		"Jobs > What the job has cost shows the four numbers side by side: what was budgeted, what is "
		+ "committed by orders that have gone out, what has actually been spent, and what has been "
		+ "billed. More committed than budgeted is reported at the moment it happens. The billed figure "
		+ "here is a number somebody states, because the report deliberately leaves the documents to the "
		+ "billing desk.",
		"",
		"Time on the job is logged against a person and a day and approved by somebody; only an approved "
		+ "entry is an hour of cost. A purchase order commits money when it is issued and turns it into "
		+ "cost as what arrives is recorded. A change order is proposed, sent and approved, and only an "
		+ "approved one joins the contract sum - a declined or withdrawn one is neither agreed nor "
		+ "pending.",
	]))
	out.append(_topic("Billing and the books", [
		"Jobs > What has been billed is the billing desk: the schedule a job is billed by, the invoices "
		+ "that went out, and the money that came in.",
		"",
		"An invoice is numbered for the business's own fiscal year, goes out on a date, and is never "
		+ "edited after it is issued - it is voided with a reason, or reversed by a credit note that "
		+ "mirrors it. A payment cannot be more than the balance and cannot be applied to a draft. "
		+ "Retainage is withheld step by step and released only by an explicit act at closeout.",
		"",
		"Jobs > What has been handed to a ledger is the outbox: the invoices, payments and credit notes "
		+ "queued for the business's accounting, one push for each document for each ledger. Each ledger "
		+ "is described by what it can actually do - a file ledger that writes CSV, JSON and IIF files, "
		+ "and hosted services that need their own settings. Credentials are never written into the "
		+ "outbox.",
		"",
		"Jobs > The figures is the report on the business: the numbers from the pipeline, the jobs, the "
		+ "billing and the timesheets - the win rate, the average sale, the backlog, the work in progress, "
		+ "the ageing of unpaid invoices, crew utilisation, cost tracking and the rest. A figure that "
		+ "cannot be worked out is refused, naming what it is waiting for, rather than shown as nought.",
	]))
	out.append(_topic("Presenting the garden", [
		"Present > Client presentation turns the client presentation on: the camera, the sun and the "
		+ "rendering budget. A better tier costs more and buys sharper shadows; no tier ever takes the "
		+ "shadows off the garden.",
		"",
		"Frame the garden puts the camera above the design looking down at it. The sun is the drawing's "
		+ "own site at a moment you choose, aimed by the clock - so a still of a summer afternoon is the "
		+ "afternoon that place really has.",
		"",
		"Render a still writes a picture at the size chosen above it, into the proposals folder, and a "
		+ "still is two files: the picture and the record of how it was taken, so it can be taken again.",
		"",
		"Present > Save the site to the drawing keeps the camera and the sun with the drawing rather "
		+ "than with this session.",
		"",
		"The painted plan and the ground view are the other two ways of showing the same garden: one is "
		+ "the plan as a drawing would be coloured by hand, the other is standing in it.",
	]))
	out.append(_topic("Sheets and plotting", [
		"A sheet is paper, not geometry: the drawing goes on it at a scale, with a border, a title block, "
		+ "a key, the schedules and a north point.",
		"",
		"File > Sheet setup names the project, the date and the sheet itself, and chooses the paper and "
		+ "its orientation. File > Sheet size and File > Plot scale set the same two things for the sheet "
		+ "in hand, because a sheet is what the drawing is printed on rather than a property of a shape.",
		"",
		"A drawing may go out as a set of sheets - a planting plan, a layout, a lighting plan - each "
		+ "with its own number, title and paper. Plot a sheet (P) writes the sheet in hand; plotting the "
		+ "set writes every sheet of it and moves nothing.",
		"",
		"The key lists the layers that plot and counts what is on them; the planting schedule lists the "
		+ "species and how many of each; the irrigation and lighting schedules list the zones and the "
		+ "circuits. If a table is too long for its column the remainder is counted rather than run off "
		+ "the page, and a drawing that will not fit at the chosen scale says so instead of hanging off "
		+ "the paper.",
		"",
		"Sheets are written as PDFs where the program can write files, so a plan can be sent to a "
		+ "printer or a client from here.",
	]))
	out.append(_topic("Working with others", [
		"Team > Share this drawing opens a session: whoever is in it sees who else is there, and the "
		+ "line under the menu says who that is without anybody having to turn anything on.",
		"",
		"A session is started on purpose and never at launch, because it uses the network and is billed "
		+ "to the account. Leaving the session closes it; nothing about a design is shared until somebody "
		+ "asks for it.",
		"",
		"Business records have their own way of travelling: a store keeps one file per record with a "
		+ "revision on each, so two people changing the same record is a disagreement that is shown "
		+ "rather than one of them silently winning.",
	]))
	out.append(_topic("Undo, revisions and where your files are", [
		"Undo (Ctrl+Z) and Redo (Ctrl+Y) walk the drawing's history. Every step has a name - drawing a "
		+ "new line, hatching a region, locking a layer - so the Edit menu and the status line can say "
		+ "what would be undone rather than just that something would be.",
		"",
		"Edit > Revisions is the other half of that, and the difference between them: undo is a stack you "
		+ "walk and forget, while a revision is a record you keep. A revision is a named moment of the "
		+ "drawing - usually one that has just been sent to a client - with a message, who recorded it and "
		+ "when, and what changed since the one before. Restoring one puts the drawing back, and that "
		+ "restore can itself be undone.",
		"",
		"The window also says how much has happened since a revision was recorded, counted in gestures, "
		+ "and it keeps up while it is open. A revision recorded before gestures were counted says that "
		+ "rather than claiming nothing has been done - the two are different claims.",
		"",
		"Work that has not been saved is copied while the drawing is dirty, so a program that stops "
		+ "unexpectedly does not take it with it. The next time the program opens, File > Recover "
		+ "unsaved work offers the copy: Recover puts it back as one undoable step, Discard it throws "
		+ "it away, and Not now decides nothing and leaves it for later.",
		"",
		"Where things are kept: drawings and their histories under the user data folder, one history per "
		+ "drawing beside it rather than among the drawings, so it is never offered as a drawing to open "
		+ "or to save over. Plotted sheets, rendered stills and the business records have folders of "
		+ "their own, which the keys reference names in full.",
	]))
	return out


## The subjects, so a test can compare the manual against what it claims to cover.
static func titles() -> Array[String]:
	var all: Array[Dictionary] = topics()
	var out: Array[String] = []
	for topic: Dictionary in all:
		out.append(String(topic["title"]))
	return out


## How many topics there are.
static func topic_count() -> int:
	return topics().size()


## Where a topic sits, or -1 when there is no such topic.
static func index_of(title: String) -> int:
	var all: Array[Dictionary] = topics()
	var wanted := title.strip_edges().to_lower()
	for index in all.size():
		if String(all[index]["title"]).to_lower() == wanted:
			return index
	return -1


## A topic's title, or the empty string past the end.
static func title_at(index: int) -> String:
	var all: Array[Dictionary] = topics()
	if index < 0 or index >= all.size():
		return ""
	return String(all[index]["title"])


## A topic's body, or the empty string when no topic has that title. A search that finds nothing
## hands back nothing rather than a near miss, which is why this is not a fuzzy match.
static func body_for(title: String) -> String:
	var at: int = index_of(title)
	if at < 0:
		return ""
	return String(topics()[at]["body"])


## The topics a search finds, in the order they are read. An empty search finds every topic, which
## is what makes emptying the search box the way back to the whole manual.
##
## The words are matched lowercased, so a search is not case-sensitive, and the title counts as well
## as the body - somebody typing "invoice" is asking about a subject, not about a mention.
static func find_in(among: Array[Dictionary], query: String) -> Array[int]:
	var out: Array[int] = []
	var needle := query.strip_edges().to_lower()
	for index in among.size():
		if needle == "" or _mentions(among[index], needle):
			out.append(index)
	return out


## The same search over the manual itself.
static func find(query: String) -> Array[int]:
	return find_in(topics(), query)


static func _mentions(topic: Dictionary, needle: String) -> bool:
	if String(topic.get("title", "")).to_lower().contains(needle):
		return true
	return String(topic.get("body", "")).to_lower().contains(needle)


## One line about the manual, for a status line or a log.
static func describe() -> String:
	return "the manual: %d topics, %d words" % [topic_count(), _word_count()]


static func _word_count() -> int:
	var total := 0
	for topic: Dictionary in topics():
		var body := String(topic["body"]).replace("\n", " ")
		total += body.split(" ", false).size()
	return total


# --- building one topic ----------------------------------------------------------------------


## A topic from a title and its lines. The lines are joined with newlines, so a blank line in the
## list is a paragraph break and the body reads as it is written here.
static func _topic(title: String, lines: Array) -> Dictionary:
	return {"title": title, "body": "\n".join(PackedStringArray(lines))}