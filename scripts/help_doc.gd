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
##
## ## The four claims about the manual
##
## Which subjects it covers (`SUBJECTS`), how they are grouped (`SECTIONS`), which ones point at which
## (`SEE_ALSO`), and which are shown with a picture (`PICTURES`). Each is a table, and each has a test
## that holds it against the written topics - "the manual covers everything", "the contents is grouped"
## and "the manual is illustrated" are only claims if something reads them.

## The subjects the manual has to cover, in the order they are shown.
##
## Written out rather than derived, and a test reads it: "document everything" is only a claim if
## somebody has said what *everything* is. A topic that is dropped from `topics()` should fail a
## test rather than quietly stop being documented.
const SUBJECTS: Array[String] = [
	"What this program is",
	"Where you start: the front door",
	"Finding any command: the palette",
	"The three views",
	"Drawing: the tools",
	"Snapping and precision",
	"Editing shapes",
	"Layers, units and the site",
	"The ground under the garden",
	"Stating levels and falls",
	"Importing somebody else's file",
	"Tracing over a picture",
	"What is on site: the field survey",
	"Reading a photograph",
	"Plants",
	"Food: what will crop here",
	"Food: what to grow here next",
	"Food: what's ready when",
	"Food: when to sow",
	"Food: how much to plant",
	"Ordering the plants from a nursery",
	"Water: irrigation",
	"Light: garden lighting",
	"What it costs: takeoff and estimate",
	"Leads and the pipeline",
	"Jobs, crews and the schedule",
	"Billing and the books",
	"Presenting the garden",
	"The sun and the shadows",
	"Sheets and plotting",
	"Sending the drawing out",
	"Working with others",
	"Undo, revisions and where your files are",
	"What the drawing has said",
]


# --- the shape of the manual ------------------------------------------------------------------
#
# Four things about the manual are *structure* rather than prose: the order of the subjects
# (`SUBJECTS`), the sections the subjects are grouped into (`SECTIONS`), the subjects that point at
# each other (`SEE_ALSO`) and the pictures they are shown with (`PICTURES`). Each is a table, and each
# has a test that holds it against the manual, for the reason `SUBJECTS` has one: a claim about the
# manual is only a claim if something reads it.

## The sections the contents is grouped into, in the order they are read.
##
## The list of subjects is flat - one entry per thing to know - but thirty-two flat rows is a wall to
## look at, so the same subjects arrive under eight headings. A section names the subjects in it and
## nothing else: the *order* of the subjects is still `SUBJECTS`, and a test checks that the sections
## are exactly that list, in that order, split up and not rearranged.
##
## Written here rather than on each `_topic(...)` call so a section is one edit and a whole group of
## subjects cannot be half-moved.
const SECTIONS: Array[Dictionary] = [
	{"title": "Getting started", "topics": [
		"What this program is",
		"Where you start: the front door",
		"Finding any command: the palette",
		"The three views",
	]},
	{"title": "Drawing", "topics": [
		"Drawing: the tools",
		"Snapping and precision",
		"Editing shapes",
	]},
	{"title": "The site", "topics": [
		"Layers, units and the site",
		"The ground under the garden",
		"Stating levels and falls",
		"Importing somebody else's file",
		"Tracing over a picture",
		"What is on site: the field survey",
		"Reading a photograph",
	]},
	{"title": "Plants and food", "topics": [
		"Plants",
		"Food: what will crop here",
		"Food: what to grow here next",
		"Food: what's ready when",
		"Food: when to sow",
		"Food: how much to plant",
		"Ordering the plants from a nursery",
	]},
	{"title": "Water and light", "topics": [
		"Water: irrigation",
		"Light: garden lighting",
	]},
	{"title": "The business", "topics": [
		"What it costs: takeoff and estimate",
		"Leads and the pipeline",
		"Jobs, crews and the schedule",
		"Billing and the books",
	]},
	{"title": "Presenting and output", "topics": [
		"Presenting the garden",
		"The sun and the shadows",
		"Sheets and plotting",
		"Sending the drawing out",
	]},
	{"title": "History and other people", "topics": [
		"Working with others",
		"Undo, revisions and where your files are",
		"What the drawing has said",
	]},
]

## Subjects that point at other subjects: the ones a reader of that subject most often wants next.
##
## A cross-reference rather than a mention: a body can name another part of the program in prose, but a
## person who is standing in the wrong topic needs a way *out* of it. The page draws one button per
## entry, and a test checks that every subject named here is a subject the manual actually has and that
## nothing is left pointing at itself.
##
## Deliberately short. A topic that links to everything links to nothing.
##
## The food subjects read as a chain - what will crop, what to grow next, what is ready when, when to
## sow, how much to plant, and the order that comes out of it - so each points at the next, and a reader
## who came in at the middle can walk it either way.
const SEE_ALSO: Dictionary = {
	"Where you start: the front door": ["What this program is", "The three views"],
	"The three views": ["Presenting the garden", "The sun and the shadows"],
	"Drawing: the tools": ["Snapping and precision", "Editing shapes"],
	"The ground under the garden": ["Stating levels and falls", "Plants"],
	"What is on site: the field survey": ["Reading a photograph", "Plants"],
	"Reading a photograph": ["What is on site: the field survey", "Plants"],
	"Plants": ["Food: what will crop here", "Ordering the plants from a nursery"],
	"Food: what will crop here": ["Food: what to grow here next", "The sun and the shadows"],
	"Food: what to grow here next": ["Food: what will crop here", "Food: when to sow"],
	"Food: what's ready when": ["Food: when to sow", "Plants"],
	"Food: when to sow": ["Food: what's ready when", "Food: how much to plant"],
	"Food: how much to plant": ["Ordering the plants from a nursery", "Food: what will crop here"],
	"What it costs: takeoff and estimate": ["Jobs, crews and the schedule", "Billing and the books"],
	"Presenting the garden": ["The sun and the shadows", "Sending the drawing out"],
	"Sheets and plotting": ["Sending the drawing out"],
	"Undo, revisions and where your files are": ["What the drawing has said", "Working with others"],
}


## The pictures the subjects are shown with: file names in `PICTURE_DIR`, one to three to a subject.
##
## A picture is of the **program**, not of the subject in the abstract: each one is a shot of the real
## running window - the page, the panel or the view the prose is describing - taken off the program by
## `tools/help_shot.gd` and saved as a file. What a reader wants when a page names a button is to see
## where the button is.
##
## A table, for the reason the other three are: "the manual is illustrated" is a claim about the whole
## manual rather than about any one subject, so it is written once and a test reads it - in particular
## that every file a subject names is a file that is *there*, because a picture that failed to load is
## the quietest defect here. The page still reads and the prose is still true; the only symptom is a
## page that is less helpful than it was meant to be.
##
## A subject names a picture rather than a path, so the folder is one edit and a subject need not know
## where the manual keeps its pictures. No file type either: there is one, and `picture_path` writes it.
##
## Not every subject is shown one. A picture earns its place by showing a reader where something *is*,
## and a subject that describes a way of working rather than a page - "Editing shapes", "Sending the
## drawing out" - has nothing to point at.
const PICTURE_DIR := "res://assets/help/"
const PICTURES: Dictionary = {
	"What this program is": ["view-overhead"],
	"Finding any command: the palette": ["palette"],
	# The one subject that needs three: it is about the three views of one garden, and one picture of one
	# view would leave the reader to imagine the other two.
	"The three views": ["view-plan", "view-overhead", "view-ground"],
	"Drawing: the tools": ["drawing"],
	"Snapping and precision": ["snapping"],
	"Layers, units and the site": ["layers"],
	"The ground under the garden": ["ground-page"],
	"Stating levels and falls": ["grading"],
	"Importing somebody else's file": ["osm"],
	"Tracing over a picture": ["underlay"],
	"Plants": ["plants"],
	"Food: what will crop here": ["food"],
	"Food: what to grow here next": ["rotation"],
	"Food: what's ready when": ["harvest"],
	"Food: when to sow": ["sowing"],
	"Food: how much to plant": ["yield"],
	"Ordering the plants from a nursery": ["plant-order"],
	"Water: irrigation": ["water"],
	"Light: garden lighting": ["light"],
	"What it costs: takeoff and estimate": ["estimate", "cost"],
	"Leads and the pipeline": ["pipeline", "analytics"],
	"Jobs, crews and the schedule": ["schedule"],
	"Billing and the books": ["billing", "closeout", "ledger"],
	"Presenting the garden": ["walk"],
	"The sun and the shadows": ["sun"],
	"Sheets and plotting": ["sheet"],
	"Working with others": ["sync"],
	"Undo, revisions and where your files are": ["revision"],
	"What the drawing has said": ["status"],
}


## Where a picture's file is, from the name a subject gives it. One file type, so a subject names a
## *picture* and never has to say what sort of file it is in.
static func picture_path(name: String) -> String:
	return PICTURE_DIR + name + ".webp"


# --- reading the manual ----------------------------------------------------------------------


## Every topic, in the order they are read, each stamped with the section it sits in and the subjects
## it points at.
##
## A topic is handed to the page as one dictionary, so the section and the cross-references travel with
## it: a page that had to look them up in a second table would be a page that knows where the manual
## keeps its structure, and the manual's structure is `HelpDoc`'s business.
static func topics() -> Array[Dictionary]:
	return _annotate(_topics())


## The topics as they are written: a title and its prose, and nothing about where they are filed.
static func _topics() -> Array[Dictionary]:
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
		"Past the front door - which has a heading of its own just below - the drawing opens on the "
		+ "flat 2D plan, where an empty sheet reads as empty; Q, or the View menu, crossfades between it and "
		+ "the overhead 3D garden. The menu bar across the top is "
		+ "the whole program: File, Edit, "
		+ "View, Draft, Site, Plant, Water, Light, Pipeline, Jobs, Estimate, Present, Team and Help. The "
		+ "palette down the left holds the drawing tools and the layers. The line along the foot of the "
		+ "screen names the keys, and keeps up with what is in hand: a view's own controls while nothing "
		+ "is, and what the tool in hand is waiting for - with the keys that answer that tool - while one "
		+ "of them is.",
		"",
		"Help > Landscaping Planner help opens this manual, Help > Drawing keys opens the key "
		+ "reference, and Help > Command palette opens one box that reaches every command there is. "
		+ "In the manual, typing a word into the box at the top narrows the contents to the subjects "
		+ "that match it, best first, and the up and down arrows step from one subject to the next. "
		+ "Everything the bar offers is described in here.",
		"",
		"There are two ways out of the program and they agree with each other. Escape puts away "
		+ "whatever page is in front - the key reference, the painted sheet, and every page that opens "
		+ "over the drawing - so the one key that means \"not this\" means it everywhere. And closing "
		+ "the window asks the same question File > Quit asks whenever there is work that has not been "
		+ "written, rather than dropping it. A page that has a box to type into takes the first Escape "
		+ "for the box itself and the second to put the page away, because a box cannot be talked out of "
		+ "the keyboard while somebody is typing into it.",
		"",
		"On a phone the Back gesture is that same Escape: it puts away the page in front, and then the "
		+ "shape in hand, and only when there is nothing left at all does it ask about leaving the "
		+ "program. That is deliberate. A thumb brushes that gesture by accident, and a drawing lives in "
		+ "memory until it is written.",
	]))
	out.append(_topic("Where you start: the front door", [
		"On opening, the program asks which of its two halves you have come for: the drawing board, or a "
		+ "camera for the site you are standing on. Neither half is a mode. Choosing the drawing board puts "
		+ "the page away, because the drawing is already standing behind it; choosing the camera opens it "
		+ "over the page rather than instead of it, so a run of photographs does not mean coming back "
		+ "through the door once a picture. Closing the door - its Close button, or Escape - is the drawing "
		+ "board, which is what is behind it.",
		"",
		"Choosing the drawing board asks one more thing before you are at it: how the drawing should "
		+ "start. There are four ways, and they are the File menu's own commands - a new drawing, a "
		+ "drawing you saved earlier, one this program has opened recently, and the example garden below. "
		+ "Drawing is the last question before the board.",
		"",
		"That board is a blank page to begin with. The garden this program ships with - the house, the "
		+ "lawn, the paving and the planting - is one fixed example, so it is put away rather than standing "
		+ "behind a new drawing: what you draw, you draw on paper. View > Show the site puts that garden "
		+ "back under your drawing and takes it away again, and loading the example garden turns it on for "
		+ "you, since that garden is what the example is.",
		"",
		"The door stands there only when there is nothing behind it: a drawing that has never been saved "
		+ "and has had nothing done to it. That is the state a launch begins in, so it is what you see - and "
		+ "a launch that opens a drawing goes straight to the drawing instead of asking.",
		"",
		"The camera is reachable from inside the drawing as well, and deliberately without needing one: "
		+ "Site > Take a photograph... opens it from anywhere, and its shutter keeps the picture in the same "
		+ "folder as a picture you chose from a file. The survey's own door beside it, Record what is on "
		+ "site..., is about the drawing, and says so by needing one.",
		"",
		"On a phone the camera takes the screen over while it is open, because the thing you are aiming at "
		+ "is the thing you are looking at, and it turns with the phone rather than with the board behind it "
		+ "- so a picture is never left lying on its side. The button beside the shutter names what you go "
		+ "back to: Back to the drawing when a drawing is standing behind it, and Back to the menu when the "
		+ "door is.",
		"",
		"To start from something rather than from nothing, File > Examples > The example garden lays out a "
		+ "small backyard - the site, a house, a patio, a path, four beds and two trees, with one dimension "
		+ "across it - as a drawing you can move, measure, plant, price and save like any other.",
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
		"The commands you used last are not forgotten when the box closes: before anything is typed the "
		+ "list is the whole bar with those at the top, so Ctrl+P twice in a row is the shortest way back "
		+ "to whatever you were just doing.",
		"",
		"There is a second way in, for the times you are already looking at a page and cannot tell what it "
		+ "is asking you. F1 - or Help > What this page is about - opens this manual at the subject for the "
		+ "page in front of you, so the answer arrives without your having to guess which of the headings "
		+ "below it is filed under. If the page is one this manual has not reached yet, the status line "
		+ "says so, and says what that page is about so the gap can be filled.",
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
		"View > Control hints switches the line at the foot of the screen off once you know those keys "
		+ "and want the room back.",
		"",
		"View > Screen orientation decides which way up the board is asked to be: Landscape, which is how "
		+ "the board opens and what a plan drawn along a wide screen wants, Portrait for a phone propped "
		+ "in a stand, or Follow the phone, which turns the board with the device itself. What you choose "
		+ "is kept, so the next run opens the way you left this one. A desktop's window cannot be asked to "
		+ "change which way up it is, and the three choices are shown switched off there rather than doing "
		+ "nothing when they are pressed.",
		"",
		"The front door and the page it leads to follow the phone whatever the board has been told, so the "
		+ "first thing you meet stands up when the phone does and turns with it. The board takes your own "
		+ "answer back as soon as a drawing begins, because a plan is drawn along a wide screen and a menu "
		+ "is not a plan.",
		"",
		"On a touch screen the plan is moved with two fingers: pinch them apart to zoom in, together to "
		+ "zoom out, and drag both to slide the design about. One finger is the mouse, so it moves "
		+ "whatever it is over rather than the view - which is why the views are moved with two.",
		"",
		"In the ground view a phone is walked with the thumbs. The left half of the screen is a stick: "
		+ "push it in any direction to walk that way, and past its ring the walk becomes a run. The right "
		+ "half is the head, where a drag turns you. Both are live at once, so one thumb can walk while "
		+ "the other looks, and the stick lets go the moment the fingers leave the glass.",
		"",
		"On a phone the whole screen is also drawn larger - by about a third - and the palette's buttons "
		+ "are made as tall as a thumb needs rather than as tall as a desk did. Nothing about a computer "
		+ "changes: the same measurements leave a desk's controls exactly the size its layout made them.",
	]))
	out.append(_topic("Drawing: the tools", [
		"Turn the tools on with 0 (Draft > Drawing tools). Nothing can be drawn while they are away, "
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
		".  angular dim  the corner, a point along each of its two sides, and where the arc stands",
		"",
		"Enter finishes a polyline, C closes it into a polygon, Backspace drops the last point picked, "
		+ "and Escape cancels the shape in hand without putting the tool away. The foot of the screen "
		+ "keeps up with the tool in hand: it says what that tool is waiting for and names the keys that "
		+ "answer it, so the plan never has to be left to find out what to press next. Only the keys that "
		+ "tool honours are named - a line is finished by its second pick, so it is never offered the keys "
		+ "that finish a polyline. The angular dimension is "
		+ "the one tool that is not on a digit: the nine number keys are already spoken for, so it takes "
		+ "the full stop.",
		"",
		"Once a shape has its first point down, the number keys stop picking tools and say how far away "
		+ "the next point is. Type 12.5 and press Enter and the point goes twelve and a half units along "
		+ "the way the cursor points, in whatever unit the drawing is drawn in; an inch mark is honoured, "
		+ "so 6\" is six inches. Put an angle after a < to state the direction outright - 10<45 is ten "
		+ "units at forty-five degrees - and the angle is measured the way polar tracking measures one. "
		+ "Backspace peels a digit back, and Escape drops the typed length without putting the shape away.",
		"",
		"The measure tool is a check rather than a drawing: it never commits anything. The four "
		+ "dimension commands are annotations - they are drawn on the dimension layer, they are kept out "
		+ "of the 3D views, and they are never counted as work to be priced.",
		"",
		"Everything is drawn on the layer in hand, and nothing can be drawn onto a locked layer.",
		"",
		"The four dimension commands share one standard - the marks at their ends, the lines that set "
		+ "them out, which side the text sits on, and how finely it is written. K steps to the next "
		+ "standard, and Edit > Dimension standard picks one; the shipped ones are architectural, "
		+ "engineering and minimal.",
		"",
		"Draft > Hatch a region... is the one drafting act that is not a tool in hand: it asks which "
		+ "closed shape to fill and with what, and lays a hatch, a crosshatch, dots or a solid on the "
		+ "hatch layer.",
	]))
	out.append(_topic("Snapping and precision", [
		"The cursor is snapped by priority rather than by closeness, so a snap that is merely the "
		+ "nearest thing to the pointer never wins over one the design intends.",
		"",
		"Endpoints, midpoints, centres, quadrant points and the intersections of the shapes near the "
		+ "cursor; perpendicular and tangent points from the previous pick; and a point along an outline. "
		+ "Ortho and polar tracking hold the direction from the previous point, and Draft > Snapping "
		+ "turns them on - or hold Shift while you pick to hold a point to the axes for that one pick "
		+ "without switching anything on.",
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
		"Eight commands, on letters, for geometry that already exists. Arm one and it prompts for its own "
		+ "picks.",
		"",
		"O  offset   draw a new shape a fixed distance out from the one you pick",
		"T  trim     cut the picked piece of a line away at whatever crosses it",
		"X  extend   grow the picked end of a line out to the next shape",
		"I  fillet   round the corner where two lines meet, to a radius",
		"E  erase    take the picked shape off the drawing",
		"U  rotate   turn the picked shape about a point you pick, to the direction you click",
		"J  move     pick a point on the shape, then click where it should go",
		"Y  copy     the same, leaving the original where it was",
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
		"",
		"Site > How long the season is states the growing season - the last frost of spring and the "
		+ "first frost of autumn - for the whole site. It is kept with the drawing beside the latitude, "
		+ "because it is the same kind of fact, and it is the one thing about the site that no drawing "
		+ "can supply.",
		"",
		"With a season stated, every food crop in the plant list is measured against its length: a crop "
		+ "that takes longer to ripen than the season lasts will not finish before the frost comes back, "
		+ "and one that finishes only just in time is shown as a narrow fit rather than a comfortable "
		+ "one. A season nobody has stated checks nothing, which is not the same as finding that "
		+ "everything fits.",
	]))
	out.append(_topic("Stating levels and falls", [
		"Ground levels are facts about the plan rather than decoration: a spot level says how high the "
		+ "ground is at a point, a contour says where it reaches a height, and a slope arrow says which "
		+ "way it falls and how steeply. Site > The ground's heights opens the page that states them.",
		"",
		"The three grading tools are on keys of their own once the drawing tools are on: Z takes a spot "
		+ "level, B draws a contour and M draws a slope arrow, carrying the level or the fall already in "
		+ "hand - so the ground can be stated without leaving the drawing for the page.",
		"",
		"A spot level is placed with one click: set the level on the page, then press Spot level here. "
		+ "The level is a number in the drawing's own units.",
		"",
		"A contour is drawn like a polyline - pick its points and press Enter - and it carries the level "
		+ "in hand.",
		"",
		"A slope arrow is two picks, where the fall starts and where it ends, and it carries the fall "
		+ "percentage in hand. It runs downhill in the direction it was drawn.",
		"",
		"Site > Check the grading reads the drawing back and reports what contradicts itself: a spot that "
		+ "disagrees with the contour it stands on, an arrow that contradicts the levels at its ends, two "
		+ "contours at the same level, or contours that cross. An arrow with no levels under it is "
		+ "unchecked, which is not the same as wrong.",
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
		"",
		"On a phone each of those doors is the phone's own file picker rather than a folder drawn by this "
		+ "program, because Android gives a program permission to one document at a time and the picker "
		+ "is how a document is handed over. What comes back is read once and taken into the design - a "
		+ "photograph is copied into the program's own pictures, a survey becomes rows on the drawing - "
		+ "so nothing stays tied to a file the phone could take away again.",
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
	out.append(_topic("What is on site: the field survey", [
		"A visit to the site is a record before it is a drawing, and Site > Record what is on site... is "
		+ "where a plant you have just looked at goes: what you think it is, which part you photographed, "
		+ "how much sun and water it has, how big it is, and where it stands.",
		"",
		"Say what you saw and this program will not pretend you said more. A name below the confidence "
		+ "the plant library needs is kept as a name that was offered and not as an identification, so a "
		+ "shrub you could not place arrives on the plan as the shrub you could not place - with the "
		+ "photograph and the note attached to it. A height or a spread of zero means nobody measured it, "
		+ "and the plant library's own figure is used instead; type the measurement and the drawing "
		+ "follows yours, and the plant records which of the two it was sized from.",
		"",
		"Photographs are kept in the program's own folder under a name made from the picture's own "
		+ "contents, so the same photograph arriving twice is one file and two different photographs can "
		+ "never overwrite each other. What a picture is - JPEG, PNG, WebP or BMP - is read from its "
		+ "header rather than trusted from the name it arrived under.",
		"",
		"On a phone the photograph can be taken where you are standing: the page offers Take a photo... "
		+ "beside Choose a picture..., and the shutter puts the picture in the same folder as any other. The "
		+ "first time, Android asks whether this program may use the camera; say no and the page says so and "
		+ "carries on, because nothing else on it needs a camera, and on a computer the same button asks for "
		+ "a webcam instead.",
		"",
		"A survey recorded away from this machine arrives as a file. The program watches for it, plants "
		+ "what it names, and files the species it could identify into the plant library as Field Survey "
		+ "Captures, where the plant browser will show them. A capture read twice is planted once, even "
		+ "when the file it came in names none of its records.",
		"",
		"A capture goes in wherever it was found, even when the drawing says the spot is wrong for it: a "
		+ "survey is a record of what is on site, and the import is not the place to overrule the person "
		+ "who was standing there. What it does instead is ask what the plan's own conditions make of each "
		+ "spot it planted in, and say so in one line: how many suit the spot, how many are in the wrong "
		+ "place - naming the first of them and what it wants - and how many the drawing says nothing "
		+ "about.",
		"",
		"On a proposal page, up to three of those photographs sit under the picture of the garden, each "
		+ "captioned with what it shows rather than with a file name - and a page handed more than three "
		+ "says how many it left out instead of shrinking them past being read.",
		"",
		"There is no plant-identification model built into this program: reading a species off a "
		+ "photograph is a model you point the page at, if you want one, and Reading a photograph is where "
		+ "that is described. Without one the page does what it has always done - it keeps the photograph, "
		+ "it sends it nowhere, and the name is yours to type.",
	]))
	out.append(_topic("Reading a photograph", [
		"The page that records what is on site can also read the photograph for you, if you point it at "
		+ "something that can: a vision model running on your own machine, a service over the internet, or "
		+ "the two together. It is off until you choose one, and off is what this program has always done - "
		+ "the photograph is kept, it is never sent anywhere, and the name is yours to type.",
		"",
		"The dropdown on that page has four answers, and each one says in a sentence what leaves your "
		+ "machine. Off sends nothing. Local model sends the photograph to a model on this machine, or on "
		+ "one on your own network, and it does not leave it. Online model sends it to the service you name. "
		+ "Local shortlist, then online narrows the photograph to a few likely plants on your own machine "
		+ "first, and then sends the photograph and those few names to the service, which picks.",
		"",
		"Under the dropdown are the settings that answer needs - an address, the name of the model to ask, "
		+ "and, for a service, the key it is used with. The key is masked as you type it, and it is not "
		+ "written down anywhere: it is held while the program is running and asked for again next time, "
		+ "because the folder this program keeps your work in is a folder people copy and hand to somebody "
		+ "else when they need help.",
		"",
		"Press Read the photograph and the name goes into the field, with the alternatives beside it as "
		+ "buttons - each one the plant and how sure the model was. What the record keeps is who said so: a "
		+ "name a model offered is recorded at that model's own confidence, and names the model, so somebody "
		+ "reading the survey later can weigh it. Edit the name and it is yours again, recorded as yours.",
		"",
		"If the reading cannot be made, the line says what is missing - an address, the name of the model, "
		+ "a key - rather than that the feature is unavailable. And when the mixed way gets its shortlist "
		+ "but cannot reach the service, you are shown both: why nothing was decided, and the plants the "
		+ "first half found, for you to choose from yourself.",
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
	out.append(_topic("Food: what will crop here", [
		"The food garden answers the question a vegetable bed is really for: will this crop get the sun "
		+ "it needs where I am putting it? Plant > What will crop here... asks it of one bed at a time.",
		"",
		"Choose a bed and a crop. A bed's light is the one stated for that ground - full sun, part shade "
		+ "or full shade - and those words stand for a span of hours: full sun is six or more, part shade "
		+ "three to six, shade under three. A crop carries its own number of hours, taken from the plant "
		+ "list rather than guessed, and the two are put side by side.",
		"",
		"The site's own longest day is the ceiling. No bed is outdoors after the sun has set, so a crop "
		+ "wanting more hours than midsummer can give is refused however sunny the corner: the answer "
		+ "there is a different crop and not a better bed.",
		"",
		"The page reads what the ground is *stated* to be and never measures the shade of a wall or a "
		+ "tree; the sun and shadow study is the tool for that, and it says as much itself. A bed nobody "
		+ "has described comes back unknown rather than green, because a crop that was never checked is "
		+ "not the same as one that will crop.",
		"",
		"The list beside the check shows every food plant in the plant list against the bed in hand, best "
		+ "first, so you can see what the ground would carry rather than only whether one crop fits.",
		]))
	out.append(_topic("Food: what to grow here next", [
		"Plant > What to grow here next... asks the other half of the question: not what will crop, but "
		+ "what should follow what. A food crop belongs to a family - a brassica, a nightshade, a legume - and "
		+ "the one law of crop rotation is that the same family shall not follow itself, because a "
		+ "brassica after a brassica shares its pests and its diseases year on year. A legume in front of "
		+ "it is a gift: beans and peas are grown in a rotation because they leave the ground richer than "
		+ "they found it.",
		"",
		"Say what grew in the bed last - the page asks, because a drawing was never told a season it was "
		+ "never in - choose a crop, and the page says whether it follows on well. It also says what each "
		+ "crop grows well beside and what to keep it from: that is companion planting, and it is mostly "
		+ "tradition rather than science, so the page holds the pairings a kitchen gardener would "
		+ "recognise and claims no more than that. A bed whose history nobody has stated comes back "
		+ "unknown rather than green.",
		"",
		"Companions come in two layers, and the difference matters. Most pairings are between families "
		+ "- a herb among the fruiting crops, an allium kept from a legume. A few name a *plant*: "
		+ "marigold, which is no crop at all and belongs to no family, and fennel, which the tradition "
		+ "keeps from everything. A plant's own rule is read before its family's, which is how fennel can "
		+ "be kept from a nightshade when the herb row would otherwise allow it.",
		"",
		"Marigold is the pairing that earns its keep. Its roots give off a compound the root-knot "
		+ "nematode cannot live with, so a bed given to marigolds comes back cleaner than it was - but it "
		+ "is the ground it helps rather than the plant beside it, and the benefit shows the year after.",
		"",
		"Where a pairing has been looked into rather than repeated, the page says what the mechanism is "
		+ "and which work it came from. Where it is only tradition, it says that too, because a gardener "
		+ "is owed the difference.",
		]))
	out.append(_topic("Food: what's ready when", [
		"Plant > What's ready when... is the calendar. Pick a month and read every crop the plant list "
		+ "records as ready then, with what of each one is cut - the leaves, the fruit, the root.",
		"",
		"It reads the plant list alone, because when a crop is ready is a fact about the crop and not "
		+ "about the ground, so it needs no drawing at all. It opens on the month with the most in it "
		+ "rather than on a blank January. A crop the list says nothing about is counted apart rather "
		+ "than shown on a month it was never given, and a month with nothing ready simply says so.",
		]))
	out.append(_topic("Food: when to sow", [
		"Plant > When to sow... is the season spent rather than stated: a day to sow on, a crop to sow, "
		+ "and what the two come to together. A crop takes a stated number of days from sowing to its first "
		+ "harvest, so sown on a given day it is ready on a day you can count - and that day either comes "
		+ "before the first frost or it does not. Sowing before the last frost is a gamble the page calls "
		+ "tolerated rather than right or wrong, because a hardy crop shrugs it off and a tender one does "
		+ "not.",
		"",
		"Sow the same crop again every few weeks and its harvest moves on rather than ripening all at "
		+ "once: that is a succession, and the page works out how many sowings fit before the frost and "
		+ "when the last one is. It reads the season the Site menu holds and never touches the drawing - "
		+ "it works out the day a crop would be ready, not that the ground is warm - so a sowing it calls "
		+ "in time still needs the weather to agree. A crop the list gives no time to maturity is counted "
		+ "as unknown rather than assumed to fit.",
		]))
	out.append(_topic("Food: how much to plant", [
		"Plant > How much to plant... asks a household's question rather than the ground's: how many of a "
		+ "crop it takes to feed a given number of people. One plant gives so many grams in a season - "
		+ "that is its yield - and one person eats so many, so the amount eaten divided by the yield is "
		+ "how many plants are wanted. That is rounded up, because half a plant is not a plant, and then "
		+ "lifted by a spare, because no garden brings every plant in whole.",
		"",
		"It reads the plant list alone, like the calendar, and gives a count rather than a verdict: a "
		+ "count is a fact, not a judgement. A crop that states neither its yield nor how much a person "
		+ "eats is counted apart, naming the fact that is missing, rather than given a number nobody "
		+ "stated.",
		"",
		"The count is what a nursery order is written from: Order these plants on this page hands the "
		+ "crops straight to Plant > Order the plants for this drawing..., which prices them from the "
		+ "cost book, while this page says what you would need to plant. Working the number out plants "
		+ "nothing - it is a plan, and the plants still have to go in the ground.",
	]))
	out.append(_topic("Ordering the plants from a nursery", [
		"Plant > Order the plants for this drawing... prices everything standing in the drawing from the "
		+ "cost book and writes it out as a nursery order: one line per kind of plant, carrying the "
		+ "count, the size, the book's own item and the money.",
		"",
		"The page asks for the two things it cannot work out for itself - which job the plants are for, "
		+ "and which nursery they come from. Everything else it already knows from the drawing. N opens the "
		+ "same page, and the same key puts it away again.",
		"",
		"A plant the book cannot price is named rather than quietly left out, and in that case no order "
		+ "is written at all: an order missing a species would look like a smaller garden than the plan "
		+ "draws. A plant listed with no species recorded is a yard prop nobody has identified yet, and "
		+ "that is what the page is telling you.",
		"",
		"What is written is plant material at the book's rate - not the soil preparation, the labour or "
		+ "the mulch, which belong to the estimate - and it is written as a draft purchase order, so it "
		+ "says what the job would commit to rather than what it has committed.",
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
		"Estimate > Takeoff and estimate... is the page this all happens on. Take off the plan measures "
		+ "the drawing: the areas, the lengths and the counts, by layer, from the same linework the plan "
		+ "is drawn with. Nothing is measured twice, because the drawing was measured as it was drawn.",
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
		"",
		"Jobs > Finishing the job is the punch list walked at the end: each item is raised with where "
		+ "it is and what is wrong, put right, and then checked - an item nobody checked is not "
		+ "finished. Stating the day the garden was handed over starts the warranty, which covers "
		+ "plant material, hardscape, irrigation and lighting for a stated term; a claim against it has "
		+ "to be answered, covered or not, before it can be done. Moving the hand-over date needs a "
		+ "reason, because the warranty runs from it.",
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
		+ "rendering budget. Present > Quality chooses that budget - a better tier costs more and buys "
		+ "sharper shadows, and no tier ever takes the shadows off the garden.",
		"",
		"Frame the garden puts the camera above the design looking down at it. The sun is the drawing's "
		+ "own site at a moment you choose, aimed by the clock - so a still of a summer afternoon is the "
		+ "afternoon that place really has.",
		"",
		"Render a still writes a picture at the size Still size has chosen above it, into the proposals "
		+ "folder, and a still is two files: the picture and the record of how it was taken, so it can be "
		+ "taken again.",
		"",
		"Present > Save the site to the drawing keeps the camera and the sun with the drawing rather "
		+ "than with this session.",
		"",
		"The painted plan and the ground view are the other two ways of showing the same garden: one is "
		+ "the plan as a drawing would be coloured by hand, the other is standing in it.",
	]))
	out.append(_topic("The sun and the shadows", [
		"Present > Sun and shadow study... opens the page that answers the questions a client "
		+ "actually asks: will the patio be in shade by four, and will it be in shade in June. A "
		+ "study is a list of moments rather than one moment, so the four buttons are a June day, a "
		+ "December day, the equinoxes and the two solstices, and the day and hour fields add any "
		+ "moment of your own. H opens the same page from anywhere in the program.",
		"",
		"Each row says where the sun stands and how far the shadow of the height you type reaches, "
		+ "in the drawing's own units. A moment after dark casts nothing and says so rather than "
		+ "showing nought, and a moment with the sun very low says its number is really about the "
		+ "hour rather than the garden.",
		"",
		"Aim the sun at it points the presentation at the moment you have chosen, and Render the "
		+ "stills writes one picture per moment the sun is up, each named for the moment it shows "
		+ "rather than for when it was rendered.",
		"",
		"The site a study is of is the drawing's own - the latitude, longitude and zone offset on "
		+ "the presentation panel - because a place is stated once.",
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
	out.append(_topic("Sending the drawing out", [
		"The drawing leaves the program as more than a sheet. Two of the ways out are files another "
		+ "program can open, and one is a picture for a proposal.",
		"",
		"File > Save the drawing as a DXF... writes the design as two-dimensional linework, on the layers "
		+ "it was drawn on and in the drawing's own units, at a scale the file states. It is what hands a "
		+ "plan to somebody else's CAD program, and what this program can read back in as an underlay.",
		"",
		"File > Save the yard as a 3D model... writes the garden itself - the ground, the built elements "
		+ "and the plants - as a model file a builder, a lighting designer or the next program can open. "
		+ "It is the one export here that carries the third dimension rather than a projection of it.",
		"",
		"File > Render a proposal still, and Present > Render a still, write a picture of the garden from "
		+ "the client presentation - the same act from two places, and the topic on presenting says what "
		+ "the picture comes to.",
		"",
		"Writing a drawing out changes nothing about it. Each door says where the file went, and the two "
		+ "that ask for a name will take the extension it needs.",
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
	out.append(_topic("What the drawing has said", [
		"Every line the status line shows is kept. Edit > What just happened... opens a page listing the "
		+ "last sixty things the drawing has said, newest first, so a message that has already scrolled "
		+ "away or been replaced can be read again.",
		"",
		"A history is not a log. It is capped rather than growing without bound, the newest answer is "
		+ "tinted, and the page says how many it is holding rather than pretending to have everything. "
		+ "The same words said twice are two answers, because they were said about two different things, "
		+ "and a drawing that has only just been opened says it has said nothing rather than showing a "
		+ "blank page.",
		"",
		"It is about the drawing and not the program: opening another drawing, or making a new one, "
		+ "begins a fresh history, and the page keeps up while it is open by reading what the drawing has "
		+ "said behind it.",
	]))
	return out


## Each topic with the section it sits in, the subjects it points at and the pictures it is shown
## with, read off `SECTIONS`, `SEE_ALSO` and `PICTURES`.
##
## A subject in none of those tables gets an empty section, no links and no pictures, which is what the
## keys topic the HUD appends gets for the last two: a topic with no section is simply not under a
## heading, rather than broken. That is the honest reading of a topic nobody has filed.
##
## The parameter is not called `topics`, because that is this class's own function and a parameter of
## that name shadows it.
static func _annotate(entries: Array[Dictionary]) -> Array[Dictionary]:
	var filed := {}
	for section: Dictionary in SECTIONS:
		for title: String in section["topics"]:
			filed[title] = String(section["title"])
	for topic: Dictionary in entries:
		var title := String(topic.get("title", ""))
		topic["section"] = String(filed.get(title, ""))
		var links: Array[String] = []
		for target: Variant in (SEE_ALSO.get(title, []) as Array):
			links.append(String(target))
		topic["see"] = links
		# The pictures travel the same way, resolved to paths: the page is handed what it is to show and
		# never needs to know where the manual keeps its pictures.
		var pictures: Array[String] = []
		for name: Variant in (PICTURES.get(title, []) as Array):
			pictures.append(picture_path(String(name)))
		topic["pictures"] = pictures
	return entries


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


## The sections, in the order a person reads them. The headings the contents is grouped under.
static func section_titles() -> Array[String]:
	var out: Array[String] = []
	for section: Dictionary in SECTIONS:
		out.append(String(section["title"]))
	return out


## The section a subject sits in, or "" when no section names it.
static func section_of(title: String) -> String:
	var at: int = index_of(title)
	if at < 0:
		return ""
	return String(topics()[at].get("section", ""))


## The subjects a subject points at - its "read next", empty when it points at none.
static func see_for(title: String) -> Array[String]:
	var out: Array[String] = []
	var at: int = index_of(title)
	if at < 0:
		return out
	for target: Variant in topics()[at].get("see", []):
		out.append(String(target))
	return out


## The topics a search finds, best first. An empty search finds every topic, which is what makes
## emptying the search box the way back to the whole manual.
##
## The words are matched lowercased over the title, the body and the section, so a search is not
## case-sensitive and a subject is found by its own name as readily as by a word in its prose -
## somebody typing "invoice" is asking about a subject, not about a mention.
##
## The order is the **command palette's rule**, with this manual's own third field in the middle of it.
## A palette row is read by its own name first and by the menu it is filed under last; a subject is
## read by its title first and by the section it is filed under last, and it has a third thing a
## command in a bar has not got, which is prose. So: a title that *starts* with the word beats one that
## merely contains it, either beats a body that discusses it, and any of those beats a subject that is
## only *filed* somewhere the word is written. Ties keep the reading order, so the same search gives the
## same list every time - and a manual is read in order, so its order is the one to keep them in.
##
## The last tier is the one to be careful of talking up: a subject that comes back because its section
## is named for the word need not itself contain the word. That is why the page says the search
## *matches* rather than that every subject it found *mentions* it.
static func find_in(among: Array[Dictionary], query: String) -> Array[int]:
	var wanted := query.strip_edges().to_lower()
	if wanted == "":
		var everything: Array[int] = []
		for index in among.size():
			everything.append(index)
		return everything
	# One list per way of matching, each filled in the order the topics are given - so every tier is
	# already in reading order and only the tiers have to be joined.
	var named_for_it: Array[int] = []
	var in_the_name: Array[int] = []
	var in_the_prose: Array[int] = []
	var filed_under_it: Array[int] = []
	for index in among.size():
		var topic: Dictionary = among[index]
		var title := String(topic.get("title", "")).to_lower()
		if title.begins_with(wanted):
			named_for_it.append(index)
		elif title.contains(wanted):
			in_the_name.append(index)
		elif String(topic.get("body", "")).to_lower().contains(wanted):
			in_the_prose.append(index)
		elif String(topic.get("section", "")).to_lower().contains(wanted):
			filed_under_it.append(index)
	var out: Array[int] = []
	out.append_array(named_for_it)
	out.append_array(in_the_name)
	out.append_array(in_the_prose)
	out.append_array(filed_under_it)
	return out


## The same search over the manual itself.
static func find(query: String) -> Array[int]:
	return find_in(topics(), query)


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
