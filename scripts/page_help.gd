class_name PageHelp
extends RefCounted
## Which page of this program is described by which subject of the in-app manual.
##
## Every feature here is meant to have a subject in `HelpDoc`, so that a person who has opened a page and
## cannot tell what it is asking them can read about it. A subject nobody can reach *from the thing it is
## about* is a subject only someone who already knows the answer will find: the manual is a list of
## thirty-two headings, and knowing which heading answers "what does this page want from me" is exactly
## the knowledge the person who needs it does not have. This table is what joins the two.
##
## It is keyed by page **script name**, which is what `PageIndex.page_name` reports and what
## `PageLayout` reports a page by - so a page is one row here, one row in the layout check and one row in
## the manual.
##
## ## Where there is no subject, said out loud
##
## Two lists, and they say different things:
##
## - `WITHOUT_NEED` - a page that has no business pointing at the manual, and why. There is one of these.
## - `NOT_YET_WRITTEN` - a page a person can open that the manual **does not describe at all**. These are
##   gaps in the manual rather than in this table, and they are written down rather than left out so that
##   they cannot be forgotten, and so that a page added tomorrow cannot quietly join them: the test that
##   holds this file takes a page that is in none of the three lists as a failure.
##
## A page being here is not a claim that the subject is *about* that page and nothing else - several pages
## share one, because a person who has the food garden's sowing page open wants the same subject as the
## one who has the calendar open. It is a claim that the subject is where the answer is.

## The page, and the manual subject that answers what it is asking.
const SUBJECT_OF: Dictionary = {
	"billing_window": "Billing and the books",
	"command_palette": "Finding any command: the palette",
	"estimate_window": "What it costs: takeoff and estimate",
	"field_window": "What is on site: the field survey",
	"food_window": "Food: what will crop here",
	"grading_window": "Stating levels and falls",
	"ground_window": "The ground under the garden",
	"harvest_window": "Food: what's ready when",
	"layer_window": "Layers, units and the site",
	"osm_window": "Importing somebody else's file",
	"pipeline_board": "Leads and the pipeline",
	"plant_order_window": "Ordering the plants from a nursery",
	"revision_window": "Undo, revisions and where your files are",
	"rotation_window": "Food: what to grow here next",
	"schedule_board": "Jobs, crews and the schedule",
	"sheet_window": "Sheets and plotting",
	"snap_window": "Snapping and precision",
	"sowing_window": "Food: when to sow",
	"status_window": "What the drawing has said",
	"sun_window": "The sun and the shadows",
	"sync_window": "Working with others",
	"underlay_window": "Tracing over a picture",
	"walk_window": "Presenting the garden",
	"yield_window": "Food: how much to plant",
}

## The pages that should not point at the manual at all, and the reason each one is right.
const WITHOUT_NEED: Dictionary = {
	"help_window": "it is the manual: a door from the manual to the manual explains nothing",
}

## The pages the manual has not reached yet, and what each one is about. Every one of these is a person
## opening a page and having nowhere to read about it.
const NOT_YET_WRITTEN: Dictionary = {
	"analytics_window": (
		"the figures a business is read by - margin, crew utilisation, ageing, the funnel - have no "
		+ "subject; `Billing and the books` is about the documents, not the report drawn from them"
	),
	"closeout_window": (
		"releasing retainage and settling the last of a job has no subject; the billing topic stops at "
		+ "raising an invoice"
	),
	"job_cost_window": (
		"what a job has cost against what it was budgeted has no subject; `Jobs, crews and the schedule` "
		+ "is about the work and who is doing it"
	),
	"ledger_window": (
		"sending the books to another program has no subject; the manual does not mention it at all"
	),
	"season_window": (
		"how long the growing season is has no subject of its own; the food topics assume a season rather "
		+ "than explain one"
	),
}


## The subject that answers what a page is asking, or an empty string for a page with none. A page with
## no subject is not a page with no answer: `WITHOUT_NEED` and `NOT_YET_WRITTEN` are where those are.
static func subject_for(page: String) -> String:
	return String(SUBJECT_OF.get(page, ""))


## Whether opening the manual from this page is worth a door. A page in either of the two lists has
## nowhere to go, and a control that leads nowhere is worse than no control.
static func has_a_way_to_the_manual(page: String) -> bool:
	return SUBJECT_OF.has(page)