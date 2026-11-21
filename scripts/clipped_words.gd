class_name ClippedWords
extends RefCounted
## Whether words need more room than the box they are drawn in.
##
## A caption is given a rectangle and told to say something, and the two are not always the same size. Where they
## disagree the engine either wraps the words onto another line or cuts them off - and a cut caption is the worse
## of the two, because the words it keeps still read like a sentence. The phone's own foot line showed
## "Pinch: zoo" where the program had written "Pinch: zoom", and nothing in this project could see it: the walk
## that measures a control against the room only knows that the *box* was placed past an edge.
##
## **How wide a line of words is, is the caller's measurement and not this file's.** It is the font this program
## is drawn with, asked at the control's own size, and a second copy of that arithmetic here would be a copy of
## the sizes the program draws at rather than a reading of them. What lives here is the comparison the
## measurement leaves to be made: what the words want against what they were given.

## How much narrower than its words a box may be before it is worth naming, in pixels. Every font rounds, and a
## caption that misses by a pixel or two is not a caption a person can see anything wrong with - the fault worth
## naming is a word that has been cut.
const LEAST := 8


## How many pixels of its words a box cannot show; 0 when they fit.
static func shortfall(item: Dictionary) -> int:
	var wanted: float = float(item.get("wanted", 0.0))
	var given: float = float(item.get("given", 0.0))
	return maxi(roundi(wanted - given), 0)


## Whether a box has room for the words it was asked to show.
static func fits(item: Dictionary, least: int = LEAST) -> bool:
	return shortfall(item) < least


## Every caption whose words want more room than it has, each
## `{ "name", "said", "wanted", "given", "short", "least" }`. An item is
## `{ "name", "said", "wanted", "given" }`, with both widths in the pixels a screenshot is counted in.
static func faults(items: Array, least: int = LEAST) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for item: Dictionary in items:
		var short := shortfall(item)
		if short < least:
			continue
		found.append(
			{
				"name": String(item.get("name", "a caption")),
				"said": String(item.get("said", "")),
				"wanted": roundi(float(item.get("wanted", 0.0))),
				"given": roundi(float(item.get("given", 0.0))),
				"short": short,
				"least": least,
			}
		)
	return found


## The caption losing most of its words, which is the one to fix first.
static func worst(found: Array) -> Dictionary:
	var biggest: Dictionary = { }
	for fault: Dictionary in found:
		if biggest.is_empty() or int(fault["short"]) > int(biggest["short"]):
			biggest = fault
	return biggest


## One caption as a person reads it, quoting what it says so that a reader can see which words were cut.
static func sentence(fault: Dictionary) -> String:
	return (
		"%s is given %d px for \"%s\", which wants %d: %d px of its words are not shown"
		% [fault["name"], fault["given"], fault["said"], fault["wanted"], fault["short"]]
	)
