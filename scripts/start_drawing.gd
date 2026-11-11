class_name StartDrawing
extends RefCounted
## The four ways to begin a drawing, offered once a person has chosen the drawing board at the front door.
##
## The door asks which half of the program somebody has come for; this page asks the next question, which is
## what the drawing should start as. There are exactly four honest answers, and they are the four doors the
## File menu already has - a new drawing, a drawing saved earlier, one this program has opened recently, and
## the example garden - so nothing here is a second way of doing something the menu does: `id()` names the
## command, and the HUD runs the same handler the menu entry runs.
##
## ## The words, and where they live
##
## Every label and every line comes from here, so the page and the tests hold one list rather than each
## writing its own. `WAYS` is the whole of what the page offers, in the order a person meets it: the empty
## sheet first, because that is where a drawing begins, then something already made - a file, then one of the
## drawings this program remembers, then the example.
##
## ## The recent drawings, named not counted
##
## `recent_rows` turns the paths the store remembers into the rows the page shows: a name to recognise the
## drawing by, and the path it opens. A drawing that is no longer on disk never reaches here - the store
## drops it as it reads - so a row is always a file that is there. With none remembered, the page says so in
## words (`nothing_recent_line`) rather than showing an empty list or a zero.

## The way that means an empty sheet.
const NEW := &"new"
## The way that means a drawing saved earlier, found in a file.
const OPEN := &"open"
## The way that means one of the drawings this program has opened before.
const RECENT := &"recent"
## The way that means the example garden this program ships.
const EXAMPLE := &"example"

## What the page is called.
const TITLE := "Begin a drawing"
## What it says before the four ways, in the page's own voice.
const OPENING := (
	"The drawing board is ready. Start with an empty sheet and draw the site from nothing, open a "
	+ "drawing you saved earlier, come back to one you have opened recently, or lay out the example "
	+ "garden."
)

## The four ways, in the order a person meets them. Each has the id its button answers with, the words on
## the button, and a line explaining what taking it does.
const WAYS: Array[Dictionary] = [
	{
		"id": NEW,
		"label": "New drawing",
		"line": "Start with an empty sheet and draw the site from nothing.",
	},
	{
		"id": OPEN,
		"label": "Open drawing...",
		"line": "Open a drawing you saved earlier, from a file.",
	},
	{
		"id": RECENT,
		"label": "Open recent",
		"line": "Return to a drawing this program has opened before.",
	},
	{
		"id": EXAMPLE,
		"label": "The example garden",
		"line": "Lay out the small backyard this program ships as a starting point.",
	},
]

## What the recent list is headed with, and what to do once it is showing.
const RECENT_HEADING := "Recently opened"
const RECENT_HINT := "Choose a drawing to open it."
## What is said when there is nothing to come back to. A sentence, not a zero.
const NOTHING_RECENT := "No drawings have been saved yet, so there are none to come back to."


## The ids of the four ways, in the order they are offered, for the page and for a test.
static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for entry: Dictionary in WAYS:
		out.append(StringName(entry["id"]))
	return out


## One way, by its id, or an empty dictionary for an id nothing here offers.
static func way(id: StringName) -> Dictionary:
	for entry: Dictionary in WAYS:
		if StringName(entry["id"]) == id:
			return entry
	return {}


## The recent drawings as the rows the page shows: the name a person recognises each by, and the path it
## opens, newest first as the store gives them. A path that no longer exists never arrives here - the store
## drops it as it reads - so every row is a drawing that is there.
static func recent_rows(paths: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for path: String in paths:
		out.append({"path": path, "label": DrawingStore.display_name(path)})
	return out