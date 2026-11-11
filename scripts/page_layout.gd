class_name PageLayout
extends RefCounted
## Measuring a page against the size it declares for itself.
##
## Every page here is a `Window` that names a `SIZE` - the floor it opens at - and that number was
## chosen by hand, one page at a time. The pages' own comments admit as much: the snapping page says
## its 600 pixels are "shorter than the 900-pixel screen the other pages are sized for", and the ground
## page records that its first version was 640 tall and "the row ... fell off the bottom edge, which is
## a button that exists and cannot be pressed".
##
## That last sentence is the fault this measures. A page whose contents want more room than the page
## declares for them clips its own bottom, and a control that exists and cannot be pressed is a bug no
## test that looks at the page's controls can see - the control is there, it is named, and it answers
## when a person who cannot reach it is not the one asking.
##
## ## A page that scrolls is not a page that clips
##
## A page whose contents are longer than it is only at fault when the page *cuts* them. A page whose column
## sits inside a `ScrollContainer` - a page built with `PageChrome.scrolling_column` - scrolls the rest of
## itself into view, so its last row, nearly always the buttons, can still be reached. The verdict is
## therefore per axis: a page too **wide** is a fault either way, because a scrolling page never scrolls
## sideways and nothing can reach a column that has run off the side, while a page too **tall** is a fault
## only when it cannot scroll. `SCROLLS` is said rather than `FITS`, because it is not the same thing: the
## page has more in it than it shows at once.
##
## ## A page has to be shown to be measured
##
## A `Container` does not work out what it needs until it has a real width, and an autowrapped `Label`
## at no width reports one line per *word*: the food page measured 12,499 px tall while it was hidden
## and 681 px once it was on screen. So a measurement shows the page, sets it to the size it declares
## for itself, and gives the containers and the wrapped text a few frames to settle before reading
## anything back. A caller must expect the page to be on screen while this runs, and must have put the
## page in the tree first - whether a page is added and freed is the caller's business, because that is
## the part a test has to be able to control.
##
## ## A check that did not run has not passed
##
## A page with nothing to read comes back `read = false` saying `UNKNOWN`, never `FITS`. The one thing
## this must never do is report a page as sound because it failed to look at it.


## The node a page lays its own column into. Thirty pages name it "Column", and the convention is worth
## holding to: it is what lets one measurement find the contents of any page without a page declaring
## anything extra. A page that names its root something else is still measured - `content_root` falls
## back to its first control child - so a new page is measured before it is taught the name.
const CONTENT_NODE := "Column"

## The frames given for the containers and the wrapped text to settle before anything is read. One is
## not enough: a container resizes its children on the frame after its own size changes, and an
## autowrapped label re-wraps on the frame after that.
const SETTLING_FRAMES := 2

## What a thing that has the room it wants is said to do, so a verdict can be counted without any of
## the prose being compared.
const FITS := "FITS"

## What is said about a page whose contents are longer than the page and scroll to be reached. Deliberately
## not `FITS`: the page has more in it than it shows at once, and calling that a fit would describe a page
## somebody still has to scroll as a page that is finished with.
const SCROLLS := "SCROLLS"

## What is said about a page that could not be read at all.
const UNKNOWN := "UNKNOWN"


## The size a page declares for itself: the `SIZE` constant on its script, or the floor it set if its
## script names none. Zero means the page declares nothing and nothing can be measured against it.
static func declared_size(page: Window) -> Vector2i:
	var script: Script = page.get_script() as Script
	if script != null:
		var constants: Dictionary = script.get_script_constant_map()
		var named: Variant = constants.get("SIZE", null)
		if named is Vector2i:
			return named
	return page.min_size


## The page's own name, read off its script rather than its node. The node of a page the HUD has not
## built yet has no name at all, and "Column" and "Status" are the same two words on thirty pages, so a
## fault has to be reported against something that says which page it is on.
static func page_name(page: Window) -> String:
	var script: Script = page.get_script() as Script
	if script == null:
		return String(page.name)
	return script.resource_path.get_file().get_basename()


## The node a page builds its contents into: the one named `CONTENT_NODE`, or the first control child
## for a page that names it something else. Null is a page with nothing to read, which `measure` refuses
## rather than passing.
##
## It is looked for **anywhere** inside the page rather than straight under it, because a page whose
## contents can scroll keeps the same column one level down inside a `ScrollContainer`. The name is what a
## measurement goes by; the depth it was found at is not a fact about the page.
static func content_root(page: Window) -> Control:
	var named: Control = page.find_child(CONTENT_NODE, true, false) as Control
	if named != null:
		return named
	for child: Node in page.get_children():
		var control: Control = child as Control
		if control != null:
			return control
	return null


## The `ScrollContainer` a page's contents would scroll inside, or null for a page whose contents cannot
## scroll at all. Walked upwards from the contents rather than looked for by name, because it is *being
## inside one* that lets a person reach a page's last row, not the word the node was given.
static func scroll_of(root: Control) -> ScrollContainer:
	var node: Node = root
	while node != null:
		var scrolling: ScrollContainer = node as ScrollContainer
		if scrolling != null:
			return scrolling
		node = node.get_parent()
	return null


## The padding a page puts around its own contents: the offsets of whichever node is the page's own child.
## A page that scrolls carries them on the `ScrollContainer` - a container positions the child it holds, so
## an offset written on that child would be overwritten and its offsets are its rectangle instead - and a
## page whose column the page anchored itself carries them on the column. Either way, exactly one of the
## two is the page's padding, which is why this reads one rather than adding both.
static func padding_of(root: Control, scrolling: ScrollContainer) -> Vector2:
	return _offsets(scrolling if scrolling != null else root)


## What the contents want, per axis: the widest child across, and the children stacked down the page
## with the gaps between them. The content root's own offsets are added on, because they are the page's
## padding - a full-rect root is inset by them - and what a page declares for itself has to hold the
## words *and* the space around them.
##
## A hidden child is skipped: a row that is not being shown is not asking for room, and a page should
## not be blamed for space nothing is using.
static func wanted_size(root: Control) -> Vector2:
	return wanted_contents(root) + _offsets(root)


## The same figure without the root's own offsets: what the children want on their own. A page that scrolls
## asks for this one instead, because there the column's offsets are the rectangle the `ScrollContainer`
## gave it rather than a pad the page chose - reading them as padding reports a page as wanting *less* than
## nothing, and a negative width passes every check there is.
static func wanted_contents(root: Control) -> Vector2:
	var gap: float = float(root.get_theme_constant("separation"))
	var wanted := Vector2.ZERO
	var first := true
	for child: Node in root.get_children():
		var control: Control = child as Control
		if control == null or not control.visible:
			continue
		var minimum: Vector2 = control.get_combined_minimum_size()
		wanted.x = maxf(wanted.x, minimum.x)
		wanted.y += minimum.y
		if not first:
			wanted.y += gap
		first = false
	return wanted


## The padding a control's own offsets describe. It is what a page's column carries when the page anchored
## it itself - `offset_left` is the pad on one side and `offset_right` the pad on the other, negative -
## and it is the control's rectangle rather than a pad when a container positioned it.
static func _offsets(control: Control) -> Vector2:
	return Vector2(
		control.offset_left - control.offset_right, control.offset_top - control.offset_bottom)


## Measure one page against the size it declares for itself, and against the screen it would land on.
##
## The page must already be in the tree. Returns
## `{name, declared, wanted, viewport, read, fits_declared, fits_viewport, words}`: `read` is false for
## a page that could not be looked at, and `words` is the line a person reads, naming the page and how
## much of it does not fit.
static func measure(page: Window, tree: SceneTree, viewport: Vector2i) -> Dictionary:
	var declared: Vector2i = declared_size(page)
	var name: String = page_name(page)
	var was_visible: bool = page.visible
	page.show()
	page.size = declared
	for i: int in SETTLING_FRAMES:
		await tree.process_frame

	var row: Dictionary = {
		"name": name,
		"declared": declared,
		"wanted": Vector2.ZERO,
		"viewport": viewport,
		"read": false,
		"fits_declared": false,
		"fits_width": false,
		"fits_height": false,
		"scrolls": false,
		"fits_viewport": declared.x <= viewport.x and declared.y <= viewport.y,
		"words": "",
	}
	var root: Control = content_root(page)
	if root == null or declared == Vector2i.ZERO:
		row["words"] = "%s: %s" % [UNKNOWN, (
			"%s has no contents to measure" % name
			if root == null
			else "%s declares no size to measure it against" % name
		)]
		page.visible = was_visible
		return row

	var scrolling: ScrollContainer = scroll_of(root)
	var scrolls: bool = scrolling != null and _scrolls_its_length(scrolling)
	var wanted: Vector2 = wanted_contents(root) + padding_of(root, scrolling)
	var fits_width: bool = wanted.x <= float(declared.x)
	var fits_height: bool = wanted.y <= float(declared.y)
	# Sound for the room it has: nothing runs off the side, and the length either fits or can be scrolled
	# to. A page that cannot scroll and does not fit is cutting its own bottom off, which is the fault this
	# whole measurement exists for.
	var sound: bool = fits_width and (fits_height or scrolls)
	row["wanted"] = wanted
	row["read"] = true
	row["scrolls"] = scrolls
	row["fits_width"] = fits_width
	row["fits_height"] = fits_height
	row["fits_declared"] = sound
	row["words"] = "%s wants %5.0f x %-5.0f in %d x %-4d  ->  %s" % [
		name, wanted.x, wanted.y, declared.x, declared.y,
		_verdict(wanted, declared, scrolls),
	]
	page.visible = was_visible
	return row


## How much of the content does not fit, named per axis. Both axes are said separately because they are
## different faults for a person: a page too wide has a column running off the side, and a page too tall
## has its last row - nearly always the buttons - below the bottom edge.
static func _overflows(wanted: Vector2, declared: Vector2i) -> String:
	var parts := PackedStringArray()
	if wanted.x > float(declared.x):
		parts.append("%.1f px too wide" % (wanted.x - float(declared.x)))
	if wanted.y > float(declared.y):
		parts.append("%.1f px too tall" % (wanted.y - float(declared.y)))
	return "OVERFLOWS BY " + ", ".join(parts)


## The one line that says what a page's contents do against the size the page declares. The two axes are
## asked separately because they are different things to a person: a page too wide has a column running off
## the side, where nothing can reach it, and a page too tall has its last row below the bottom edge -
## reachable by scrolling, and cut off when it is not.
static func _verdict(wanted: Vector2, declared: Vector2i, scrolls: bool) -> String:
	if wanted.x <= float(declared.x) and wanted.y <= float(declared.y):
		return FITS
	if scrolls and wanted.x <= float(declared.x):
		return "%s BY %.1f px too tall" % [SCROLLS, wanted.y - float(declared.y)]
	return _overflows(wanted, declared)


## Whether a page's contents really scroll their length. A `ScrollContainer` can be told not to, and a page
## whose length cannot scroll is a page that cuts its own bottom, so this asks what the wrapper is set to
## rather than taking a wrapper for an answer.
static func _scrolls_its_length(scrolling: ScrollContainer) -> bool:
	return scrolling.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED