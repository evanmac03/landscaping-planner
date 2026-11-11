class_name PageChrome
extends RefCounted
## The one place a page's own chrome is made.
##
## Thirty pages grew their own helpers for the same four things, and no two of them agree. `_heading`
## exists in eleven pages and is 15 px on the ground page, 16 on the revision and sheet pages, 18 in the
## manual and 20 on the field and status pages. `_button` exists in fourteen pages with six different
## signatures - `(words, method)`, `(parent, node_name, text)`, `(row, node_name, caption)`,
## `(words, handler, live)`, `(parent, words)` and `(parent, text)` - so a button's focus, its name and
## its width are decided in six places that can drift apart.
##
## That is this project's own rule left unapplied: there is exactly one of each thing, and a second
## engine that can disagree with the first is the defect this project spends the most effort avoiding.
## Six button-makers is six answers to "what is a button on a page".
##
## ## What it owns, and what it does not
##
## It builds controls and nothing else: no page state, no arithmetic, no scene, every function `static`
## and handing back the node it made. A page keeps writing its own `build()` in its own words and simply
## stops re-inventing the same four widgets.
##
## Three things it holds for every page, because they are the same on every page:
##
## - **The content root is named "Column"**, which is what `PageLayout` finds a page's contents by. The
##   name is written here a second time on purpose, and `tests/test_page_chrome.gd` holds the two to each
##   other, because a literal that must agree in two files is a fact that has to be asserted somewhere.
##   A page too tall for the screen it lands on gets the same column inside a `ScrollContainer`
##   (`scrolling_column`), which puts it one level down: the name is what a measurement goes by, never
##   the depth it was found at.
## - **A control here does not take the keyboard by itself.** That is the HUD's own rule for its buttons,
##   and a control made here follows it. What a page does with the keyboard once it is *open* is decided
##   once, by `takes_the_keyboard` below, which the shared show calls - so a page's buttons, checkboxes,
##   pickers and lists can all be reached with Tab without thirty pages each guessing where the keys go.
## - **A line that wraps is given the width it wraps into.** A row hands a child that does not ask for
##   the spare room only its own minimum width, and a wrapped `Label`'s minimum width is its longest
##   word - so a sentence beside a button wraps to a line per word and stands the page on end. Measured:
##   the billing page's note beside its invoice button made that page 1,217 px tall on its own.
##
## ## A name is a default, not a decision
##
## A caption becomes a node name by a rule (the words run together, without the punctuation a caption
## ends in), because that is what the pages that already name their buttons do. A page whose own tests
## already hold a name - `Column/CloseRow/Close` - sets it after building, and that is expected rather
## than a workaround: the builder's name is only there so a control is never nameless.

## The page's title. One size, on every page: the same words heading the same kind of thing.
const HEADING_SIZE := 20
## A heading inside a page's own sections, under the title.
const SUBHEADING_SIZE := 16
## Everything that is read rather than glanced at: sentences, notes, status lines.
const BODY_SIZE := 12

## What a page declares its own size to be, read through the one place that answers that question rather
## than by looking the `SIZE` constant up a second time here: a second reader is a second answer, and the
## two can drift apart.
const PageLayoutScript := preload("res://scripts/page_layout.gd")

## The node name of a page's content root. `PageLayout.CONTENT_NODE` says the same word, and the two are
## held to each other by a test.
const COLUMN_NAME := "Column"

## The node name of the `ScrollContainer` a page whose contents may be longer than itself puts its column
## inside. The column keeps `COLUMN_NAME` even there, so a page's contents are found and measured the same
## way on every page; what moves is where they sit, and a page's own tests move with them.
const SCROLL_NAME := "Scroll"

## The same, for the title bar: the size the theme drew a page's title in, remembered for the same reason.
const TITLE_DRAWN_AT := &"title_drawn_at"

## A note explaining what a page is for - dimmer than the words it is about.
const NOTE_COLOR := Color(0.78, 0.8, 0.72)
## A hint under a list or a field: what to do next.
const HINT_COLOR := Color(0.68, 0.72, 0.62)
## The status line at the foot of a page: what just happened, or what could not be done.
const STATUS_COLOR := Color(0.72, 0.76, 0.68)

## The marks a caption ends in, which no node name ends in.
const TRAILING_MARKS: Array[String] = [".", ",", ":", ";", "!", "?", "…"]

## Where a page's contents remember the padding the page laid them out with, so that a page fitted for a
## finger twice - or fitted again when it is shown again - is inset once rather than twice. An override is
## one-way, which is the same reason `PhoneHud.DRAWN_AT` exists.
const PADDING_DRAWN_AT := &"padding_drawn_at"

## How much of the screen a page may take when it lands. Nearly all of it, because a page is a working
## surface rather than a dialog, but not all of it: a sliver of the drawing stays visible around every
## page, which is what says the page is *over* the drawing rather than instead of it.
const SCREEN_RATIO := 0.95

## The controls a person acts with, and so the ones the keyboard is for. A caption, a picture, a
## separation line and a container are things to read or things to lay out; none of them is a control a
## person presses, and none of them should hold a Tab.
const ACTED_WITH: Array[String] = ["Button", "ItemList"]

## The two pages that answer for their own keyboard, and are left exactly as they are built.
##
## Both are shown by their own `open()` rather than by the shared show, so it never reaches them, and
## neither needs this list to be safe today. It is here because a rule with a boundary should say where
## the boundary is: the palette's list must stay out of the focus chain *for the palette's own reason*
## (its search field answers the arrows and Enter, and a list that took them would be a second place
## deciding where they go), and the manual moves its own topic selection.
##
## Named by the file, because a file cannot be two things and a node name can be changed by whoever adds
## the page to a tree. `tests/test_page_keyboard.gd` holds both to the pages they name.
const ANSWER_FOR_THEIR_OWN_KEYBOARD: Array[String] = [
	"res://scripts/command_palette.gd",
	"res://scripts/help_window.gd",
]


## The content root: the column a page lays its own controls into, filled to the page and named so
## `PageLayout` finds it.
##
## `inset` is the padding around the page's contents. It is the page's business - 16 by 12 on the field
## and food pages, none at all on most - and it is counted by the measurement, so a page that insets has
## to declare room for the words *and* the space around them.
static func column(page: Window, separation: int = 8, inset: Vector2 = Vector2.ZERO) -> VBoxContainer:
	var root := VBoxContainer.new()
	root.name = COLUMN_NAME
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = inset.x
	root.offset_top = inset.y
	root.offset_right = -inset.x
	root.offset_bottom = -inset.y
	root.add_theme_constant_override("separation", separation)
	page.add_child(root)
	return root


## The content root of a page whose contents may be **longer than the page**: the same "Column", inside a
## `ScrollContainer`, so a page clamped to a screen with less room than it asked for scrolls the rest of
## itself into view instead of cutting its own bottom off.
##
## Whichever screen it lands on, the **sideways** scroll is off. A row too wide for its page is a fault a
## person can see, and one a fresh page does not yet have a habit of avoiding, so leaving it scrollable
## would only hide it: what scrolls is the length of a page, never its width.
##
## The column inside keeps `COLUMN_NAME`, because the name is what `PageLayout` finds a page's contents by
## and it is worth more than the depth. What moves is the path a page's own test holds: a page that scrolls
## has its controls at `Scroll/Column/...` rather than `Column/...`.
##
## `inset` is the padding around the contents, and it is set **here** rather than on the column: a
## `ScrollContainer` positions the child it holds and would overwrite an offset written on it. `PageLayout`
## reads the padding off whichever of the two is the page's own child, so the size a page declares for
## itself still has to hold the words *and* the space around them.
static func scrolling_column(
	page: Window, separation: int = 8, inset: Vector2 = Vector2.ZERO
) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = SCROLL_NAME
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = inset.x
	scroll.offset_top = inset.y
	scroll.offset_right = -inset.x
	scroll.offset_bottom = -inset.y
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	# A page is walked with Tab, and a button below the fold has to come into view when it takes the
	# keyboard: without this, Tab reaches a control nobody can see, and Enter presses it.
	scroll.follow_focus = true
	page.add_child(scroll)

	var root := VBoxContainer.new()
	root.name = COLUMN_NAME
	# The column takes the width it is given - so its sentences wrap at the page's width rather than at
	# their longest word - and its own height, so a longer one scrolls: a `ScrollContainer` gives a child
	# the room it asks for on an axis only when that axis is expanded, and nothing here asks for more
	# height, which is precisely the scrolling.
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", separation)
	scroll.add_child(root)
	return root


## The page's title, in the one size a title is.
static func heading(words: String) -> Label:
	return _label(words, "Heading", HEADING_SIZE)


## A heading inside a page, under its title, for a section of it.
static func subheading(words: String) -> Label:
	return _label(words, "Subheading", SUBHEADING_SIZE)


## The plain body line: a sentence a page says in its own right - the count of what is listed, the state of
## the thing the page is about - rather than one of the dimmed kinds below it.
##
## It is here because a page with a line to say that is neither a title nor a note was growing a `_label`
## of its own for it, and the body size was being decided in as many places as there were such pages. The
## name is a default like every other name here: a page whose own tests hold `Count` or `Summary` sets it
## after building.
static func text(words: String = "", wrap_text: bool = true) -> Label:
	return _label(words, "Text", BODY_SIZE, wrap_text)


## A sentence explaining what a page is for, wrapped to the page's width.
static func note(words: String) -> Label:
	return _dim(_label(words, "Note", BODY_SIZE, true), NOTE_COLOR)


## What to do next, under a list or a field.
static func hint(words: String = "") -> Label:
	return _dim(_label(words, "Hint", BODY_SIZE, true), HINT_COLOR)


## The status line at the foot of a page: what just happened, or the refusal that says what is missing.
##
## It carries no minimum height, deliberately. A status line that reserves room whether or not it has
## anything to say is a page asking for space it is not using, and with wrapping on, a long refusal is
## already the tallest thing on most pages - which is why the shortest pages reserve *nothing* and the
## measurement refuses a page that has not left room for the longest one.
static func status(words: String = "") -> Label:
	return _dim(_label(words, "Status", BODY_SIZE, true), STATUS_COLOR)


## A button showing a caption, named from it, and taking no keyboard of its own: `takes_the_keyboard`
## gives it one when the page is shown, so every page's buttons are reachable in the same way.
static func button(caption: String) -> Button:
	# `button` is this function's own name, so a local of that name shadows it and the reload pass says
	# so; the control is built as `made` for that reason and for no other.
	var made := Button.new()
	made.name = node_name_for(caption)
	made.text = caption
	made.focus_mode = Control.FOCUS_NONE
	return made


## A caption and the control it names, in one row: "Bed [Front lawn]", "every [30°]".
##
## The row is named after the control it carries, so a page that labels `GridStep` gets a `GridStepRow`
## without having to say so. A page whose tests already hold a different name sets it afterwards.
##
## A control the page has already added somewhere is **moved** into the row rather than refused: a
## `Control` can only have one parent, and "build the field, then wrap it in a labelled row" is the order
## a page naturally writes, not a mistake to be reported at run time.
static func labelled(caption: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = (String(control.name) + "Row") if control.name != &"" else "Row"
	row.add_theme_constant_override("separation", 6)
	row.add_child(_label(caption, "Caption", BODY_SIZE))
	if control.get_parent() != null:
		control.reparent(row, false)
	else:
		row.add_child(control)
	return row


## The row a page's buttons sit in, at its foot: right-aligned, the last thing on the page.
static func button_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.alignment = BoxContainer.ALIGNMENT_END
	return row


# --- putting a page on the screen ------------------------------------------------------------------


## The floor a page should open at, brought down to what a screen actually has room for.
##
## A `min_size` bigger than the screen fights the clamp and wins: it pushes the page's own controls off
## the edge, which is the opposite of what taking the room away was for. So the floor comes down to fit
## as well, and is never bigger than the page asked for in the first place. A screen that cannot be
## asked - a headless run reports no size at all - leaves the page its own floor rather than shrinking it
## to nothing.
static func clamped_minimum(preferred: Vector2i, available: Vector2i) -> Vector2i:
	if available.x <= 0 or available.y <= 0:
		return preferred
	return Vector2i(mini(preferred.x, available.x), mini(preferred.y, available.y))


## The room a page has to land in: the viewport it will be shown inside, which for this program is the
## game window a person is looking at rather than the monitor behind it. A page with no tree yet - one a
## test built and never added - falls back to the display, and a display that cannot be asked answers
## zero, which `clamped_minimum` reads as "no answer".
static func room_for(page: Window) -> Vector2i:
	var node: Node = page.get_parent()
	while node != null:
		var viewport: Viewport = node as Viewport
		if viewport != null:
			return Vector2i(viewport.get_visible_rect().size)
		node = node.get_parent()
	var screen: int = DisplayServer.window_get_current_screen()
	return DisplayServer.screen_get_usable_rect(screen).size


## How tall the chrome Godot draws above a page's contents is: the window's own title bar.
##
## It is a fact about the theme rather than a number to write down here - 36 on this project's theme - and
## zero for a page with no title bar to draw, which is what `borderless` means. The bar is drawn *above* the
## rectangle a `Window` reports as its position and size, so it is the part of a page that hangs off the top
## of the screen while every number the page can report still says it fits.
static func chrome_above(page: Window) -> int:
	if page == null or page.borderless:
		return 0
	return maxi(page.get_theme_constant(&"title_height", &"Window"), 0)


## The room a page's *contents* have to land in: the viewport it lands inside with its own title bar, and a
## phone's camera cutout, taken out of it. A display that cannot be asked still answers zero, which
## `clamped_minimum` reads as "no answer" - neither a bar that is not drawn nor a cutout that is not there is
## allowed to turn a real screen into a negative one.
static func content_room(page: Window) -> Vector2i:
	var room: Vector2i = room_for(page)
	if room.x <= 0 or room.y <= 0:
		return room
	return Vector2i(room.x, room.y - chrome_above(page) - PhoneHud.cutout_top(room))


## Put a page on the screen: centred, with everything it asked for kept inside the room it lands in.
##
## The one place a page is shown, so that "what happens when a page opens" is answered once instead of
## thirty times: the floor, the clamp and the keyboard are the same question on every page. Returns the
## floor the page was given, which is the part a test can hold.
##
## A page whose *contents* then want more room than the clamped height has to scroll to show the rest;
## the clamp stops a page hanging off the edge of the screen, and a scrolling column is what stops the
## bottom of a tall page being unreachable inside it.
##
## ## The title bar is drawn above the contents, and it is the part that hangs off
##
## Godot draws an embedded window's title bar itself, and it draws it *above* the rectangle the window
## reports as its position and size: the page a person sees is the contents with a title bar hanging off the
## top of them. `popup_centered_clamped` centres the contents alone. So a page lost the top of its own title
## bar as soon as its floor came within twice the bar's height of the room, and the four pages that declare
## 850 pixels on a 900-pixel desk lost 11 pixels of it - `tools/page_chrome_probe.tscn` opens the figures
## page and shows `position.y` 25 with its title text drawn from -11, which is what the tool was written to
## measure. A phone is worse, because there the floor is brought down to the room exactly: the camera page's
## 720 came down to the 666 a phone has, which put the *whole* bar - its title and its close cross - above
## the top of the screen. Nothing measurable was wrong: the size read the clamped floor, the position read
## (282, 0), a centred page on a screen it exactly matched, and the layout fitted.
##
## So the room is taken down by the bar's height before the floor is clamped, and the page is moved down by
## half of it - which is exactly what centres the whole window rather than its contents.
##
## ## A page too tall for a phone is widened before it is scrolled
##
## Two cures, in one order, both in `_land` below: a page whose contents want more height than the room it
## landed in is first given **the room's width**, because a wider page is a shorter page, and only then - if
## it is still too tall - a scroll. On a phone the door declared 520 px across a screen of well over a
## thousand and wrapped one paragraph onto eight lines, which is what pushed its buttons below the fold. The
## width is given only on a device answered with a finger, so a desk lays every page out exactly as it
## always did.
static func show_centred(page: Window) -> Vector2i:
	# Before the clamp, because a taller control makes a taller page and the floor is worked out after.
	size_for_a_finger(page)
	takes_the_keyboard(page)
	return _land(page, page.min_size)


## Land a page in the room: place it at the floor it asked for, give it the whole room if what it holds wants
## more than it got, and scroll it if even the room cannot hold it.
##
## The one place a page lands, so that "what happens when a page opens" and "what happens when the room
## changes shape under it" cannot come to two different answers: `show_centred` and `placed_again` differ in
## the floor they start from, and in nothing else.
##
## **A page that has outgrown the size it declared for itself is given the room**, both ways across and down,
## and on a phone that is the whole of the fault. The numbers a page declares were worked out for a desk: the
## front door's 520 by 540 came out 45% of a phone's width with its one paragraph wrapped onto eight lines and
## its buttons below the fold, and the phone's own room - 1137 across by 2600-odd logical pixels down - is the
## honest answer to both. The scroll is what is left for what even the room cannot hold.
static func _land(page: Window, preferred: Vector2i) -> Vector2i:
	var landed_at: Vector2i = _place(page, preferred)
	# After it, because what a page's contents have to fit is the room the page was actually given: a phone
	# brings a page down to its own screen, and a page brought down shorter than its contents has its last row
	# - nearly always the buttons - below its bottom edge.
	if fit_the_room_to_the_page(page, landed_at):
		landed_at = _place(page, content_room(page))
	# And last, for what the room itself cannot hold.
	scroll_if_it_does_not_fit(page, landed_at)
	return landed_at


## Whether a page should be given the room rather than the size it declared for itself. Three things and
## nothing else: it is a device answered with a finger, it is not already the room, and what it holds wants
## more height than the room gave it.
##
## On a computer the first of those is false, so this answers `false` before reading anything at all - which is
## what keeps the pages a desk sees the pages this project designed, to the pixel.
##
## The room is taken whole rather than at `SCREEN_RATIO`. That ratio is there so a sliver of the *drawing*
## stays visible around a page, which says the page is over the drawing rather than instead of it; a page that
## has outgrown the size it declared has earned the room, and a sliver is not worth a paragraph wrapped onto
## eight lines with the buttons beneath it below the fold.
##
## **The height it reads is conservative on purpose.** A `Container` works out what it needs on the frame
## after its width changes, so a figure read in the same call has not wrapped yet and over-estimates: measured
## with a page two sentences long, one just widened to 1000 px reported 122 px of contents where the wrap it
## settled into wants 62. A page is therefore *given* a room it may not need rather than ever being clipped,
## and `PageLayout.measure` - which does wait for the frames - stays the arbiter of a page that really fits.
static func fit_the_room_to_the_page(page: Window, landed_at: Vector2i) -> bool:
	if page == null or landed_at.y <= 0 or not PhoneHud.on_a_finger_here():
		return false
	if content_room(page) == landed_at:
		return false
	return not _fits_the_height(page, landed_at)


## Whether a page's contents fit the height the page was given. The measurement is `PageLayout`'s own - the
## figure the page-layout check reports a page against - rather than a second sum worked out here that could
## disagree with it.
static func _fits_the_height(page: Window, landed_at: Vector2i) -> bool:
	var contents: Control = PageLayoutScript.content_root(page)
	return contents == null or PageLayoutScript.wanted_size(contents).y <= float(landed_at.y)


## Put a page over the whole of the room rather than in the middle of it: a viewfinder is not a form.
##
## The one page this is for is the camera on a phone, where the picture being aimed at is the only thing on
## the screen that wants every pixel - and where a page in the middle of a wide board spends most of the
## screen showing the board through the thing a person is trying to fit a leaf into.
##
## The same arithmetic as `show_centred` - the same clamp, the same title bar, the same keyboard - with the
## whole content room asked for instead of the page's own floor. It is one function on purpose: a page that
## fills the screen and a page that sits in the middle of it must not come to be placed by two different
## sums, which is exactly how a page ends up half a title bar off the top of a phone.
static func takes_the_room(page: Window) -> Vector2i:
	size_for_a_finger(page)
	takes_the_keyboard(page)
	# Not asked whether it fits, deliberately: the one page this is for is a viewfinder, and what a viewfinder
	# has to fit is the *sight* rather than a list of rows - a scroll around one would shrink the picture to
	# its own minimum. What is on that page is a feed, a caption and a row of buttons, which is short.
	return _place(page, content_room(page))


## Put a page on the screen again, after the room it lands in has changed shape under it.
##
## Opening a page is a *place*, not an anchor: `popup_centered_clamped` reads the room once, when the page
## opens, and a page left up through a turn of the phone stays exactly where it was opened. Measured on the
## glass: the front door opened on a phone's 1444 by 666 landscape canvas and, after the phone was turned,
## sat near the top of a canvas 2567 pixels tall - which is where a menu opened in a room less than a third
## that height is left. So the room is read again and the page is put back in the middle of it.
##
## The doorway is what made that reachable: the front door follows the phone (`OrientationChoice.DOORWAY`),
## so a page *is* up through a turn, and a menu that turned with the phone without moving with it would be
## the worst of both.
##
## Only the page's place is asked for again. The keyboard is not taken a second time and the buttons are
## not made big for a finger a second time, because a page somebody is already using has already answered
## both of those questions - and a page that grabbed the keyboard every time the screen changed shape would
## take the caret out of whatever field a person was typing in.
##
## The floor is the page's *declared* size rather than its `min_size`, because `min_size` holds last time's
## clamp: a page brought down to 630 to fit a landscape phone would never grow back to the 720 it asked for
## once the phone was held the other way.
## The page lands by the same door it opened by (`_land`), so a page turned with the phone is widened for
## the new room and scrolled in it exactly as a page opened into that room would be. Nothing a person has
## already answered is asked again: the floor, the clamp, the width and the scroll are all placement.
static func placed_again(page: Window) -> Vector2i:
	if page == null:
		return Vector2i.ZERO
	return _land(page, PageLayoutScript.declared_size(page))


## Where a page goes and how big it is: the one arithmetic both doors share, `show_centred` when a page
## opens and `placed_again` when the room under one that is already up changes shape. The floor they start
## from is the only thing they differ in, and it is handed in rather than read here, so that neither door
## can come to place a page differently from the other.
static func _place(page: Window, preferred: Vector2i) -> Vector2i:
	var clamped_floor: Vector2i = clamped_minimum(preferred, content_room(page))
	page.min_size = clamped_floor
	page.popup_centered_clamped(clamped_floor, SCREEN_RATIO)
	# Godot centred the contents, and the bar hangs above them with a phone's cutout above that; the half of
	# the two together that was off the top is what the page moves down by. The room was taken down by the
	# same two, so the whole window - bar, cutout and contents - lands below the cutout and inside the screen.
	page.position += Vector2i(0, roundi((chrome_above(page) + PhoneHud.cutout_top(room_for(page))) / 2.0))
	return clamped_floor


## Give a page that has outgrown the room it landed in a `ScrollContainer`, so that its own bottom - nearly
## always the buttons it ends with - can still be reached rather than being cut off at the bottom edge.
##
## This is what makes making a page's words legible on a phone safe. Bigger words make every page taller, and
## a phone brings a page down to its own screen: without this, the front door's second way in would simply be
## below the fold with no way to get to it. The measurement is `PageLayout`'s own - the figure the page-layout
## check reports a page against - rather than a second one worked out here that could disagree with it.
##
## The page has **already been placed** when this is asked, because the thing to compare against is the
## height the page actually got rather than the one it asked for.
##
## A page that was *built* to scroll is left with the wrapper it built, and a page that fits is left exactly
## as it was built. On a computer the room is larger than every page this project declares, so nothing is
## wrapped there and a desk's pages are the pages they always were.
##
## Returns whether a wrapper was put in, which is the part a test can hold.
static func scroll_if_it_does_not_fit(page: Window, landed_at: Vector2i) -> bool:
	if page == null or landed_at.y <= 0:
		return false
	var contents: Control = PageLayoutScript.content_root(page)
	# `scroll_of` walks upwards from the contents and answers with the wrapper they are inside, which is the
	# right question: what lets a person reach a page's last row is *being inside one*, not its node name.
	if contents == null or PageLayoutScript.scroll_of(contents) != null:
		return false
	if _fits_the_height(page, landed_at):
		return false
	_wrap_in_a_scroll(page, contents)
	return true


## Put a page's column inside a scroll where it stands.
##
## The insets move from the column onto the wrapper, because a `ScrollContainer` positions the child it holds
## and would overwrite an offset left on it - and `PageLayout` reads the padding off whichever of the two is
## the page's own child, so a wrapped page is still measured for the space around its words and the size it
## declares still means what it meant. The column keeps its name and is put back at the index it held, so the
## keyboard walk and a page's own tests find it where the page built it, one level down.
static func _wrap_in_a_scroll(page: Window, contents: Control) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = SCROLL_NAME
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = contents.offset_left
	scroll.offset_top = contents.offset_top
	scroll.offset_right = contents.offset_right
	scroll.offset_bottom = contents.offset_bottom
	# The same two settings a page that was built to scroll gets: sideways scrolling is off, because a row too
	# wide for its page is a fault a person can see and leaving it scrollable would only hide it, and the
	# length scrolls, which is the whole point.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	# A page is walked with Tab, and a control below the fold has to come into view when it takes the keyboard.
	scroll.follow_focus = true
	var stood_at: int = contents.get_index()
	page.add_child(scroll)
	page.move_child(scroll, stood_at)
	contents.reparent(scroll, false)
	# The column stops being anchored to the page and becomes the thing the scroll holds: the scroll gives it
	# the page's width and the height its contents ask for, which is what makes a longer column scroll instead
	# of being stretched to the room and clipped.
	for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		contents.set_anchor(side, 0.0)
	contents.offset_left = 0.0
	contents.offset_top = 0.0
	contents.offset_right = 0.0
	contents.offset_bottom = 0.0
	contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL


## Make a page's buttons big enough for a finger, when this device is answered with a finger.
##
## The rule the palette is held to, asked in the same one place a page is shown - because a rule applied
## in thirty pages is thirty answers that drift apart, which is the whole reason this file exists. On a
## computer `TouchInput` has nothing to say and every page is exactly the page a desk was drawn for, which
## is what keeps the page layout check measuring the pages this project designed.
##
## **Only buttons.** A page's text field, its picker, its list and its labels keep the size the page's own
## layout gave them: a field grows with its font, and making one grow is a change to that page rather than
## a change to a thumb. The buttons are what a thumb presses.
static func size_for_a_finger(page: Window) -> int:
	if page == null or not PhoneHud.on_a_finger_here():
		return 0
	var drawn_at: float = PhoneHud.canvas_scale(page)
	var density: float = PhoneHud.dpi()
	return (
		size_buttons_for_a_finger(page, drawn_at, density)
		+ size_the_words_for_a_finger(page, drawn_at, density)
		+ inset_the_contents_for_a_finger(page, drawn_at, density)
	)


## Make a page's own words big enough to read on a device answered with a finger.
##
## The other half of the pass `show_centred` runs, and the half a phone was left without: every page's
## *buttons* were made a thumb's size while its sentences stayed the twelve pixels a desk was drawn with.
## Twelve pixels comes to about a millimetre of capital on a phone - legible in the hand and not at arm's
## length, which is the measurement `PhoneHud.TEXT_MM` is there to refuse - and beside a button drawn at
## 5.5 mm it is the difference a person sees first.
##
## A line is grown from **the size the page gave it**, so a heading stays a heading and a page keeps its
## shape rather than collapsing every line onto one size. A page's own title bar is a page's words too, and
## it is grown with them: it is Godot's rather than a page's, and it is the one line on a page that no page
## builds. Returns how many lines were measured, which is the part a test can hold.
static func size_the_words_for_a_finger(page: Window, drawn_at: float, density: float) -> int:
	if page == null or PhoneHud.row_height(drawn_at, density) <= 0.0:
		return 0
	var measured: int = 0
	for node: Node in page.find_children("*", "Label", true, false):
		var line: Label = node as Label
		# The growing is `PhoneHud`'s, asked of the line itself, so that a page's words and a panel's words
		# are grown by one rule and one remembered size rather than by two that can drift apart.
		if line != null and PhoneHud.size_its_words_for_a_finger(line, drawn_at, density):
			measured += 1
	return (
		measured
		+ _size_the_menus_for_a_finger(page, drawn_at, density)
		+ _size_the_title_bar_for_a_finger(page, drawn_at, density)
	)


## The margin a page's contents keep from the sides of the screen on a device answered with a finger.
##
## The one part of the fitting that is not about the size of a control: on a phone the page **is** the screen,
## so a page whose contents fill it has nothing at all between its words and the glass. Measured on the
## SM-A166W, 2026-11: the front door's opening sentence ran to within three pixels of the edge of a
## 1080-pixel screen and its two choices ran the whole width of it, the Close button ending in the strip
## Android keeps for its own back gesture.
##
## **Across only, never down.** A margin taken off the length would push a page's last row - nearly always the
## buttons - below its own bottom edge, which is the fault `fit_the_room_to_the_page` is there to answer. A
## margin taken off the width can only make a page wrap *more*, and a page that wraps taller is given the room
## it needs by that same rule, or a scroll by `scroll_if_it_does_not_fit`.
##
## The margin is written on whichever node the page's own padding is already on - the `ScrollContainer` for a
## page whose contents scroll, the column otherwise, which is what `PageLayout.padding_of` reads - and the
## padding the page laid out with is remembered there, so that fitting twice insets once. Returns how many
## pages were inset, which is the part a test can hold.
static func inset_the_contents_for_a_finger(page: Window, drawn_at: float, density: float) -> int:
	var margin: int = PhoneHud.edge_margin(drawn_at, density)
	if margin <= 0:
		return 0
	var contents: Control = PageLayoutScript.content_root(page)
	if contents == null:
		return 0
	# A `ScrollContainer` positions the column it holds and would overwrite an offset written on it, so the
	# margin goes where the page's own padding already is rather than where the words are.
	var scrolling: ScrollContainer = PageLayoutScript.scroll_of(contents)
	var padded: Control = scrolling if scrolling != null else contents
	# Written down the first time only. Asked with `has_meta` rather than with a default, because a
	# `get_meta` whose default is `null` logs an engine error when the key is absent - and a logged error
	# fails the test that provoked it, which is how this was found.
	if not padded.has_meta(PADDING_DRAWN_AT):
		padded.set_meta(PADDING_DRAWN_AT, Vector2(padded.offset_left, padded.offset_right))
	var laid_out: Vector2 = padded.get_meta(PADDING_DRAWN_AT)
	padded.offset_left = laid_out.x + float(margin)
	padded.offset_right = laid_out.y - float(margin)
	return 1


## The menus a page's pickers and menu buttons open.
##
## A menu is drawn over the whole screen rather than inside the page's layout, so making it legible does not
## move anything the page laid out - which is why it is grown here, while a field or a list that stays inside
## the page is deliberately left to the page. A page on a phone whose sentences are a thumb's size and whose
## every picker still opens a desk-sized menu is the same defect in a smaller place.
##
## The walk reads **internal children too**: a picker's menu is one, and `find_children` leaves those out - a
## menu invisible to this walk is a menu still drawn at a desk's size, which is exactly what was seen live
## before this line used the right door.
static func _size_the_menus_for_a_finger(page: Window, drawn_at: float, density: float) -> int:
	var measured: int = 0
	for node: Node in _every_node_under(page):
		var menu: Window = node as Window
		if menu != null and PhoneHud.size_a_windows_words_for_a_finger(menu, drawn_at, density):
			measured += 1
	return measured


## Every node under a root, internal children included.
static func _every_node_under(root: Node) -> Array[Node]:
	var all: Array[Node] = []
	for child: Node in root.get_children(true):
		all.append(child)
		all.append_array(_every_node_under(child))
	return all


## The bar Godot draws above a page's contents carries the page's own title, and a title is words. Its
## height is room for those words rather than room for anything else, so it is grown with them - a title
## drawn at a thumb's size inside a bar drawn for a desk's would be words bigger than the box meant to hold
## them, and the bar is what `chrome_above` takes out of the room the contents may use.
static func _size_the_title_bar_for_a_finger(page: Window, drawn_at: float, density: float) -> int:
	if page.borderless:
		return 0
	var was: int = int(page.get_meta(TITLE_DRAWN_AT, page.get_theme_font_size(&"title_font_size", &"Window")))
	page.set_meta(TITLE_DRAWN_AT, was)
	var size: int = PhoneHud.text_size_for_a_finger(was, drawn_at, density)
	if size <= 0:
		return 0
	var was_bar: int = maxi(page.get_theme_constant(&"title_height", &"Window"), 0)
	page.add_theme_font_size_override(&"title_font_size", size)
	page.add_theme_constant_override(
		&"title_height", PhoneHud.grown_for_a_finger(was_bar, was, size)
	)
	return 1


## The measuring half of `size_for_a_finger`, with the scale and the density stated rather than read, so a
## test can hold what a phone would be told without being one. Returns how many buttons were measured,
## and 0 when there is nothing to impose or nowhere to measure from.
static func size_buttons_for_a_finger(page: Window, drawn_at: float, density: float) -> int:
	if page == null or PhoneHud.row_height(drawn_at, density) <= 0.0:
		return 0
	var measured: int = 0
	for node: Node in page.find_children("*", "Button", true, false):
		# `button` is this class's own function name, so a local of that name shadows it; the control is
		# `made` for that reason, the same one the builder above is named by.
		var made: Button = node as Button
		if made == null:
			continue
		PhoneHud.size_for_a_finger(made, drawn_at, density)
		measured += 1
	return measured


## Give a page's own controls the keyboard: every button, checkbox, picker and list inside it, so the
## whole page can be walked with Tab and pressed with Enter.
##
## Asked here, in the one place a page is put on the screen, because the answer is the same on every page
## and thirty pages each answering it is thirty answers that can drift apart. The builders above make a
## control *without* a keyboard of its own - that is the HUD's rule for its buttons, and a page's buttons
## are the same kind of thing - and this is what a page that is *open* does with them.
##
## It is safe because a page in a `Window` holds the keyboard while it is up: the drawing behind the page
## sees no key at all while the page is open, so a control that takes a key from the page has taken it
## from nothing that was going to use it. **Measured rather than assumed** -
## `tools/page_keyboard_probe.tscn` presses real keys and reports which view the drawing ended up in with
## nothing up, with a page up, with a button inside that page focused, and again once the page is gone.
##
## Nothing inside a `Window` *within* the page is touched. A page with a file dialog in it is the case
## this is written for: the engine hands the keyboard to that dialog, and taking one of its controls out
## of the focus chain once left the Save dialog untypeable.
##
## Returns how many controls were given the keyboard, which is the part a test can hold.
static func takes_the_keyboard(page: Window) -> int:
	if page == null or not is_instance_valid(page):
		return 0
	if _answers_for_its_own_keyboard(page):
		return 0
	return _give_the_keyboard_to(page)


## Give a page's own controls the keyboard **if the page is up**, and do nothing otherwise.
##
## This is the form a page that rebuilds its own rows needs. The shared show ran when the page was
## *opened*, so a control made afterwards has never been offered the keyboard; a page that is up gives
## the new ones theirs by calling this after it rebuilds. A page that is not on the screen needs nothing
## at all - the show is what decides it then, and it decides it once.
##
## **"Up" means in the tree *and* visible**, and both halves are asked for a reason: a `Window` reports
## itself visible before it is ever shown, so a page a test built and never added would otherwise be
## swept as though somebody were looking at it. Returns how many controls were given the keyboard.
static func takes_the_keyboard_if_up(page: Window) -> int:
	if page == null or not is_instance_valid(page) or not page.is_inside_tree() or not page.visible:
		return 0
	return takes_the_keyboard(page)


## Walk a page's controls, giving the keyboard to the ones a person acts with, and stopping at any
## `Window` inside it: a dialog owns its own keyboard, wherever it is asked for.
static func _give_the_keyboard_to(node: Node) -> int:
	var given := 0
	for child: Node in node.get_children():
		if child is Window:
			continue
		var control: Control = child as Control
		if control != null and control.focus_mode == Control.FOCUS_NONE and _acted_with(control):
			control.focus_mode = Control.FOCUS_ALL
			given += 1
		given += _give_the_keyboard_to(child)
	return given


## Whether a control is one a person acts with, rather than one that is read or laid out.
static func _acted_with(control: Control) -> bool:
	for kind: String in ACTED_WITH:
		if control.is_class(kind):
			return true
	return false


## Whether a page answers for its own keyboard, and is therefore left exactly as it is built.
static func _answers_for_its_own_keyboard(page: Window) -> bool:
	var page_script: Script = page.get_script()
	if page_script == null:
		return false
	return page_script.resource_path in ANSWER_FOR_THEIR_OWN_KEYBOARD


## A line between two parts of a page.
static func separator() -> HSeparator:
	var line := HSeparator.new()
	line.name = "Separator"
	return line


## The node name a caption becomes: the words run together, without the marks a caption may end in.
## "What just happened..." is `WhatjusthappenedButton`, and a caption of nothing but punctuation is
## simply `Button` rather than a nameless node.
static func node_name_for(caption: String) -> String:
	var words: String = caption.strip_edges()
	while words.length() > 0 and words.substr(words.length() - 1) in TRAILING_MARKS:
		words = words.substr(0, words.length() - 1)
	var out := ""
	for part: String in words.split(" ", false):
		out += part
	return (out + "Button") if out != "" else "Button"


static func _label(words: String, node_name: String, size: int, wrap_text: bool = false) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = words
	label.add_theme_font_size_override("font_size", size)
	if wrap_text:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# A wrapped line has to be *given* the width it wraps into. In a column it already is, so this
		# changes nothing there; in a row it is the difference between one line and a line per word,
		# because a row hands a child that does not ask for the spare room only its own minimum width,
		# and a wrapped `Label`'s minimum width is its longest word. A caption is the other case and is
		# built with `wrap_text` false for it: a caption is a word, and its own width is what holds the
		# row open.
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


static func _dim(label: Label, color: Color) -> Label:
	label.add_theme_color_override("font_color", color)
	return label
