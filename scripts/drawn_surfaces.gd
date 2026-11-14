class_name DrawnSurfaces
extends RefCounted
## The rectangles that are *drawn* on the screen, and which of them may not share rows.
##
## The HUD measures what it builds and the page measurement holds each page against the size it declares, and
## between them both of those were green while a page's own title bar was drawn straight over the menu titles
## and two pages' titles were drawn in the same rows. Neither instrument could see it: one compares HUD panels
## with each other, the other compares a page's contents with its own declared size, and **neither looks at a
## page and a panel together** - nor knows that Godot draws a `Window`'s title bar *above* the rectangle the
## window reports, so a page can hang 36 pixels of unmeasurable chrome into whatever is up there.
##
## This is that comparison and nothing else: **it measures nothing of its own**. Every rectangle handed in was
## already measured by `PageChrome` (a page's title bar), by `HudProbe` (every control a finger could hit) or
## by the HUD itself (its own bar and panels), so there is no second opinion anywhere in it about where
## anything stands.
##
## ## The rule, and why it needs no knowledge of what is on top
##
## A page's title bar is the one surface a person *reads* that is not a control: Godot draws the words, no node
## carries them, and nothing about that bar is measured by any layout. What it may not do is share rows with
## **words**: with another page's title bar, or with a control that says something - or with the HUD's own top
## bar, which is the fault this was written for. Either way round the fault is the same - one set of words is
## drawn over the other and neither can be read - so the rule does not need to know which surface is on top, and
## this module deliberately does not try to. Everything else is ordinary: a page over a page is how one page
## opens another, and a page over the HUD's own furniture is what a page is.
##
## **And two controls that say something may not be drawn over each other either** - the same fault with no title
## bar in it, which the rule's first version did not catch. It was measured, not reasoned: on the A16W held
## upright the board's bottom-left had the palette's own group header `Layer` drawn across the foot line's
## `Left-drag: move a plant` and its `Two fingers: pan`, so two sets of words sat in one another and neither
## could be read. **No instrument named it** - the probe reported `nothing meets anything it may not` for that
## very block, because neither of the two is a title bar. A crop of the glass is what settled it.

## A page's contents: the rectangle a `Window` reports as its position and size.
const PAGE := &"page"

## The title bar a page's window draws *above* that rectangle, which no node owns.
const BAR := &"bar"

## A control that says something - a button, a menu title, a caption.
const WORDS := &"words"

## The HUD's own top bar; the one surface a page must never reach, because the strip a page's title bar hangs
## in *is* that bar's own foot - which is what `PageChrome.reserved_above` is stated from. It is a kind of its
## own rather than another piece of `WORDS` so that a check can tell the fault this was written for (a page's
## title over the menu titles, which Godot's `MenuBar` draws itself and no node carries) from a judgement about
## the rest of the HUD's furniture, which a page covering is what a page is.
const TOP_BAR := &"top bar"


## The HUD's own bar at the top of the screen.
static func top_bar(name: String, rect: Rect2i) -> Dictionary:
	return { "kind": TOP_BAR, "name": name, "rect": rect }


## A page's contents, as the rectangle the window reports.
static func page(name: String, rect: Rect2i) -> Dictionary:
	return { "kind": PAGE, "name": name, "rect": rect }


## The title bar hanging above a page: `above` is `PageChrome.chrome_above(page)`, which is the theme's own
## answer and not a second one - a phone draws this taller than the theme says, and that gap is what
## `page_chrome_probe` measures on the glass rather than something this module could work out.
static func bar_of(name: String, rect: Rect2i, above: int) -> Dictionary:
	return { "kind": BAR, "name": name, "rect": Rect2i(rect.position.x, rect.position.y - above, rect.size.x, above) }


## A control that says something, at the rectangle it is drawn in.
static func words(name: String, rect: Rect2i) -> Dictionary:
	return { "kind": WORDS, "name": name, "rect": rect }


## Which of the surfaces handed in may not share rows, each with the rectangle they both cover. Empty is the
## good answer, and it is the answer a screen with one page on it - or with none - gives.
static func meetings(surfaces: Array) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for first: int in surfaces.size():
		for second: int in range(first + 1, surfaces.size()):
			var one: Dictionary = surfaces[first]
			var other: Dictionary = surfaces[second]
			var covered: Rect2i = (one["rect"] as Rect2i).intersection(other["rect"] as Rect2i)
			if covered.size.x <= 0 or covered.size.y <= 0:
				continue
			if _is_a_fault(one, other):
				found.append({ "a": one, "b": other, "covered": covered })
	return found


## Whether two surfaces that share rows are a fault: a title bar over words, two title bars over each other, or
## **two controls that both say something**. Nothing else meets the rule - see the class comment for why the
## answer does not depend on which is on top.
##
## The third case is the one that had to be measured. A `page` rectangle is not words however many words are
## inside it, so a page over the furniture it covers is still ordinary, and so is a page over the title of the
## page beneath it - that was a fault in the first version of this predicate, written as one test of `BAR` that
## every meeting passed, and the probe reported the front door standing under the figures page as a fault. Two
## `WORDS` over one another is the case at the other end: it was reported by nobody at all until the glass was
## read, and it is the same fault - one set of words drawn in the middle of another, with neither readable.
static func _is_a_fault(one: Dictionary, other: Dictionary) -> bool:
	var one_kind: StringName = StringName(one["kind"])
	var other_kind: StringName = StringName(other["kind"])
	if one_kind == WORDS and other_kind == WORDS:
		return true
	var one_bar: bool = one_kind == BAR
	var other_bar: bool = other_kind == BAR
	if not one_bar and not other_bar:
		return false
	if one_kind == WORDS or other_kind == WORDS:
		return true
	if one_kind == TOP_BAR or other_kind == TOP_BAR:
		return true
	return one_bar and other_bar


## One row a person can read: what met what, and the rows and columns they share. Worded here rather than in
## the tools, because this is the module the fault belongs to.
static func sentence(meeting: Dictionary) -> String:
	var one: Dictionary = meeting["a"]
	var other: Dictionary = meeting["b"]
	var covered: Rect2i = meeting["covered"]
	return "%s (%s) and %s (%s) share %d x %d px at (%d, %d) - rows %d..%d, columns %d..%d" % [
		String(one["name"]),
		String(one["kind"]),
		String(other["name"]),
		String(other["kind"]),
		covered.size.x,
		covered.size.y,
		covered.position.x,
		covered.position.y,
		covered.position.y,
		covered.position.y + covered.size.y - 1,
		covered.position.x,
		covered.position.x + covered.size.x - 1,
	]
