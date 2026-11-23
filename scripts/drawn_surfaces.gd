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

## **A control a person must press**, and the names of the surfaces it *stands inside*.
##
## The rectangle is the one `HudProbe` already reports for it - this module measures nothing of its own - and the
## names are the whole of what makes "covered by" mean anything: a panel meets its own children's rectangles by
## definition, so a hand-in that did not say what a control stands inside would report every button in the program
## as covered by the panel it is in.
const TARGET := &"target"

## **Something drawn that a person cannot press**: a panel's plate, a filled rectangle, a scrim.
##
## Apart from `WORDS` because the two failures differ - words over a button hides the button's *label*, a plate over a
## button takes the *press* - and apart from `PAGE`, which is a page, and a page over the furniture it covers is what
## a page is.
const PLATE := &"plate"


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


## A control that says something, at the rectangle it is drawn in, and **the surfaces it stands inside**.
##
## `inside` is what a control's own text makes necessary: a `SpinBox` is a thing a finger presses and the `LineEdit`
## inside it is what says the number, so the two rectangles differ by the box's own buttons and neither contains the
## other. Measured on the layout check itself - five fields were reported against their own text until the rule began
## asking this way round too.
static func words(name: String, rect: Rect2i, inside: PackedStringArray = PackedStringArray()) -> Dictionary:
	return { "kind": WORDS, "name": name, "rect": rect, "inside": inside }


## A control a person must press, and the surfaces it stands inside.
##
## **Those names are the rule's one difficulty and the reason they are an argument rather than a walk.** A panel
## covers its own children by definition, so a module that worked the ancestry out itself would be measuring the
## scene - which is the thing this file exists not to do.
static func target(name: String, rect: Rect2i, inside: PackedStringArray) -> Dictionary:
	return { "kind": TARGET, "name": name, "rect": rect, "inside": inside }


## Something drawn that a person cannot press: a panel's plate, a filled rectangle, a scrim.
static func plate(name: String, rect: Rect2i) -> Dictionary:
	return { "kind": PLATE, "name": name, "rect": rect }


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
	# **A control a person must press, with something drawn over it that is not one of the things it stands inside.**
	# This is the case the class comment records as the one *no instrument named*: on the A16W a palette group header
	# was drawn across the foot line's words, the probe reported `nothing meets anything it may not` because neither
	# of the two is a title bar, and a crop of the glass is what settled it. Here it is a rule - a plate over a
	# button takes the press away from the person, words over a button take its label - and the names a target stands
	# inside are what keeps a panel's own buttons out of the answer.
	if one_kind == TARGET or other_kind == TARGET:
		var pressed: Dictionary = one if one_kind == TARGET else other
		var over: Dictionary = other if one_kind == TARGET else one
		var over_kind: StringName = StringName(over["kind"])
		# **Two surfaces in exactly one rectangle are one thing**, which is `Stacked`'s question and not this one: a
		# control a finger presses is handed in as its words *and* as a target - that is how `HudProbe` reports what a
		# person reads and what a person presses - and the two agree by construction. Reporting that pair would put
		# every button in the program in the answer.
		if (one["rect"] as Rect2i) == (other["rect"] as Rect2i):
			return false
		if over_kind != PLATE and over_kind != WORDS:
			return false
		var stands_inside: PackedStringArray = PackedStringArray(pressed.get("inside", PackedStringArray()))
		if String(over["name"]) in stands_inside:
			return false
		# **And the same question the other way round**, which is the pair a control makes with its own text. A
		# `SpinBox` is a thing a finger presses and the `LineEdit` inside it says the number; their rectangles differ
		# by the box's own arrows, so neither contains the other and only the names can say they are one thing.
		# Measured on the layout check: five fields were named against their own text before this line existed.
		return String(pressed["name"]) not in PackedStringArray(over.get("inside", PackedStringArray()))
	if one_kind == WORDS and other_kind == WORDS:
		return true
	var one_bar: bool = one_kind == BAR
	var other_bar: bool = other_kind == BAR
	if not one_bar and not other_bar:
		return false
	if one_kind == WORDS or other_kind == WORDS:
		# **Words a bar covers whole are hidden, not jumbled, and only the second is this rule's business.**
		# Measured on the glass with the estimate page over the board: the palette's own header was not fighting
		# the page's title, it was behind it - which is what a floating page does. The fault this is written for
		# is the other case, two sets of words partly showing in one set of rows with neither of them readable.
		# So a bar holding the words entire is saying nothing at all about them. **The limit, stated rather than
		# hidden**: a bar sharing only part of a wide control's box is still named, because a rectangle cannot say
		# where the characters sit inside it - which is why a report of these says "named, not counted".
		var words_at: Rect2i = other["rect"]
		var bar_at: Rect2i = other["rect"]
		if one_kind == WORDS:
			words_at = one["rect"]
		if one_bar:
			bar_at = one["rect"]
		return not bar_at.encloses(words_at)
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
