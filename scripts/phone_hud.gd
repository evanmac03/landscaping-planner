## How big a control has to be to be pressed by a finger, and what that costs in the units the HUD is
## laid out in.
##
## This HUD was drawn for a desk: a 1600 by 900 canvas, twelve-pixel text, and rows about 29 pixels
## high. On a phone the same canvas is stretched by the window's own scale factor, so a logical pixel
## is no longer roughly a millimetre - on the phone this was written for, one is 0.079 mm, which is
## why a palette button measured 2.3 mm across and body text about 1 mm.
##
## The answers here are stated in millimetres and converted, because a millimetre is the only unit in
## which "big enough for a thumb" means anything. The scale and the density are arguments, never
## assumptions, so a computer can ask what a phone would be told - and the device question itself is
## `TouchInput`'s, asked once in one place rather than twice in two.
@tool
class_name PhoneHud
extends RefCounted

const TouchInputScript := preload("res://scripts/touch_input.gd")
## What class a window is, which is what decides whether the whole canvas is drawn up: see `zooming_here`.
const WindowClassScript := preload("res://scripts/window_class.gd")

## What a thumb needs to hit on glass. Material asks for 48 dp, which on this phone is 7.6 mm; a row
## that big in a 349-pixel palette is twelve screens of scrolling, and this palette scrolls. 5.5 mm
## is the floor of a comfortable thumb, and the number can be raised here without touching a layout.
const TOUCH_MM := 5.5

## What text has to be to be read at arm's length in the field. Measured as the height of a capital,
## which is what the eye actually reads, not as the em the font is set in.
const TEXT_MM := 1.6

## A capital letter is about this much of the em it is set in. The conversion from "millimetres of
## capital" to "a font size" goes through it, and so does the reading the demonstration prints.
const CAP_RATIO := 0.7

## How far up the whole canvas is drawn on a phone. Everything laid out in logical pixels grows by it
## and the logical canvas shrinks by it - which is the trade a phone makes: a bigger button means
## fewer of them on the screen, and the HUD's panels scroll.
const UI_SCALE := 1.35

## The size a desk's body text is set in: the size `font_size` was measured against, and so the size a
## piece of a page's own text is compared with to see whether the page drew it bigger than the body.
## `PageChrome.BODY_SIZE` says the same number, and `tests/test_page_chrome.gd` holds the two to each other -
## a literal that must agree in two files is a fact someone has to assert.
const DESK_TEXT := 12


## Draw the canvas up on a phone, and leave a computer's window exactly as it was.
static func apply(window: Window) -> void:
	apply_if(window, zooming_here())


## Whether this device is answered with a finger - the one question the layout is sized by.
##
## Both halves are `TouchInput`'s, and both are needed: a touchscreen alone is not enough (this desk's own
## monitor has one, at 144 dots to the inch) and a density read from the platform is not enough either
## (Windows reports its scaling as a density and never says a panel's 450). `force_density` and
## `TouchInput.force` are the two doors a demonstration or a test states a device through.
static func on_a_finger_here() -> bool:
	var density: float = dpi()
	var desk_mm: float = millimetres(TouchInputScript.DESK_ROW_PX, 1.0, density)
	return TouchInputScript.answered_by_a_thumb(TouchInputScript.has_a_touchscreen(), density, desk_mm, TOUCH_MM)


## Whether this device is a phone rather than a tablet: a finger, on a window small enough that the canvas
## is worth drawing up as well. A tablet is sized for a finger and left at its own scale, because drawing a
## ten-inch screen up by a third costs it a third of its drawing area and gains nothing.
##
## Asked of the window's own **class** (`WindowClass`), which is where the breakpoints are stated, rather than
## of a screen's diagonal, which is how this was first answered: a diagonal is the right answer in the wrong
## unit, and the two real devices show it - the phone this program is aimed at is 832 dp across, so by width
## it is not a phone at all, and it is its 384 dp of *height* that has no room. The screen is handed in as it
## really is, so the scale is 1.0.
static func zooming_here() -> bool:
	return on_a_finger_here() and WindowClassScript.is_small(screen_here(), 1.0, dpi())


## What a phone's own furniture - the camera cutout, the status bar, a rounded edge - takes off each side of
## the screen, given in the room's own pixels, as (left, top, right, bottom).
##
## The arithmetic and nothing else: hand it a screen, a safe area and a room, and it answers. That is what
## lets a test hold it down, and it is why the display is read in `cutout_here` and not here.
##
## The safe area is a fact about the display, in the display's pixels; the room a page lands in is the
## viewport's, and on a phone those are not the same number - the SM-A166W reports 1080 by 2340 natively and
## a 1185 by 2567 room, so a figure in one is not a figure in the other. Each answer is that side's share of
## the screen's own side and nothing more: a fraction, which is the one thing that travels between the two.
##
## A phone held sideways puts its cutout on the left or the right, so all four sides are answered rather
## than the top alone - a page that only gave ground at the top would sit under the camera in landscape.
static func cutout_insets(room: Vector2i, screen: Vector2i, safe: Rect2i) -> Vector4i:
	if room.x <= 0 or room.y <= 0 or screen.x <= 0 or screen.y <= 0:
		return Vector4i.ZERO
	var edges: Vector4i = band_edges(screen, safe)
	return Vector4i(
		share_of_the_room(edges.x, screen.x, room.x),
		share_of_the_room(edges.y, screen.y, room.y),
		share_of_the_room(edges.z, screen.x, room.x),
		share_of_the_room(edges.w, screen.y, room.y),
	)


## **One side's share of the room it becomes, and the only arithmetic that turns a figure read off a display into
## one laid out in a room.** A band is a fact about the glass and a room's pixels are not the glass's, so the two
## are joined by that screen's own side and nothing else. Written once because it has two callers - the four sides
## of a cutout and the foot band below - and a second conversion that rounded the other way would be the same fact
## in two places, disagreeing by a pixel, which is the fault this file exists to avoid.
static func share_of_the_room(of_the_screen: int, screen_side: int, room_side: int) -> int:
	if screen_side <= 0 or room_side <= 0:
		return 0
	return roundi(float(room_side) * (float(of_the_screen) / float(screen_side)))


## **The band as the display itself reports it**, in the display's own pixels, as (left, top, right, bottom). Kept
## apart from the share of a room it becomes, because the two are different numbers in different spaces and reading
## one as the other is how the menu bar was guessed at: the block printed what a control did wrong *inside* the
## band and never how big the band was, so 212 px of bare sheet above the first button had no figure beside it. This
## is the raw reading a person compares with what the phone is asked; a desk, and a display that promises nothing,
## answer zero on every side.
##
## **The safe area is clipped to the screen it is a reading about, and a desk is where that is measured.** The two
## are read from the display and this assumes they are in one space: `screen_here` answers the screen the program
## is on and `safe_area_here` the usable rectangle of it. Measured on this desk, they are not - the screen reads
## 2880 by 1620 while the usable rectangle begins at x 3840, a second monitor's space - so the band came out
## **wider than the screen it was a share of** (the block printed `display l=3840` beside a 2880 px screen) and
## every control given ground on that side was pushed off the glass. What is kept is the part of this screen the
## safe area actually covers, and one covering none of it - or all of it - answers zero on every side, which is
## the answer a display that has promised nothing already gives.
static func band_edges(screen: Vector2i, safe: Rect2i) -> Vector4i:
	if screen.x <= 0 or screen.y <= 0:
		return Vector4i.ZERO
	var inside: Rect2i = Rect2i(Vector2i.ZERO, screen).intersection(safe)
	if inside.size.x <= 0 or inside.size.y <= 0:
		return Vector4i.ZERO
	return Vector4i(inside.position.x, inside.position.y, screen.x - inside.end.x, screen.y - inside.end.y)


## The same reading for the display this program is running on - the half that asks the platform, kept beside the
## arithmetic so that there is exactly one place a display's furniture is read.
##
## **This is the cutout and nothing more, and that is measured rather than assumed.** The A16W keeps a further 42 px
## along its foot for the nav bar - its own report says `overrideNonDecorFrame=[0,100][1080,2298]`, and
## `[100,0][2340,1038]` lying down - and Godot has **no answer for it**: `screen_get_usable_rect` reports the whole
## screen there, so a band built out of both of them comes back to the cutout. Upright on that phone the two readings
## agree exactly (`display l=0 t=100 r=0 b=0` against a cutout of `Rect(0, 100 - 0, 0)`). Holding the phone's own
## numbers needs them over JNI, which is an Android plugin - so this answers the one thing the API answers, and the
## block's `insets` line prints it so that nobody has to guess what it covers.
static func band_as_reported() -> Vector4i:
	if not on_a_finger_here():
		return Vector4i.ZERO
	return band_edges(screen_here(), safe_area_here())


## The same answer for the display this program is running on. All four zero on a desk - this furniture is a
## phone's - and on a display that reports no safe area at all.
static func cutout_here(room: Vector2i) -> Vector4i:
	if not on_a_finger_here():
		return Vector4i.ZERO
	return cutout_insets(room, screen_here(), safe_area_here())


## How far that furniture reaches down from the top of the screen, in the room's own pixels. Its own reading
## because the top is the one a page's title bar is measured against, and the one this device can measure.
static func cutout_top(room: Vector2i) -> int:
	return cutout_here(room).y


## The band the devices this project has measured keep along their **foot**, in the display's own pixels, keyed by
## the size of the screen it was measured on.
##
## **This is the one piece of a phone's furniture the program has to be told, and the reason is in the paragraph
## above `band_as_reported`.** The A16W keeps 42 px there for the nav bar - its own report,
## `overrideNonDecorFrame=[0,100][1080,2298]`, says so - and Godot has **no answer for it**, so the number is
## written down here rather than read from anywhere. A screen this table does not name is answered with a zero,
## because a band guessed at is worse than the clearance the scene already keeps: 8 px of bare board under the foot
## line is a small fault, and a foot line pushed up the screen on a device that keeps nothing is a large one.
##
## **Both ways up, because the key is the screen the display reports and that follows the rotation.** The A16W's
## own reports name the band twice - `[0,100][1080,2298]` upright and `[100,0][2340,1038]` lying, **42 px along the
## foot either way** - and `screen_here` answers 1080 by 2340 for the first and 2340 by 1080 for the second, so a
## table naming only the upright one gave a phone held sideways no ground at all: measured on the glass lying down,
## the front door's own `Take a photograph` took a finger at its middle 13 px above the screen's foot, inside the
## band. A phone held sideways is a phone this project measures, and the spec states the figure for both.
const KEPT_FEET: Dictionary = { Vector2i(1080, 2340): 42, Vector2i(2340, 1080): 42 }


## How far that foot band reaches up from the bottom of the screen this program is running on, in the display's own
## pixels - the reading a person compares with what the phone itself reports. Zero on a desk, on a device nobody
## has measured, and on anything not served a finger.
static func stated_foot() -> int:
	if not on_a_finger_here():
		return 0
	return int(KEPT_FEET.get(screen_here(), 0))


## The same band in the room's own pixels, which is the space the foot line is laid out in: the figure `Hud` gives
## the plates at the foot their ground by, and the room's half of what the block prints beside the display's. Its
## own function, beside `cutout_top`, because the two are the top and the foot of the same question.
static func kept_foot(room: Vector2i) -> int:
	if not on_a_finger_here() or room.y <= 0:
		return 0
	var size: Vector2i = screen_here()
	if size.y <= 0:
		return 0
	return share_of_the_room(int(KEPT_FEET.get(size, 0)), size.y, room.y)


## State what a device would be told about its density, for a demonstration or a test - and 0 puts the
## real reading back. The same door `TouchInput.force` and `PhoneFiles.force` are, asked of a third thing.
static func force_density(density: float) -> void:
	_forced_density = density


## State the display a device would be answering from, for a demonstration or a test - and a size of nothing puts
## the real display back. The same door `force_density` and `TouchInput.force` are, asked of the thing they both
## assume.
##
## **A screen and its safe area together, because they are one fact and either half alone is a lie.** The A16W's
## glass is 1080 by 2340 with its camera cut into the top 100 px; a desk has no cutout and reports the whole screen
## as the area it will draw in. A stated size with no furniture leaves every phone band answering zero - a phone
## drawn with nothing to clear - and stated furniture with no size takes its share of whatever screen is at hand,
## which is how a desk-stated phone came out with a 1580 px band down its left side.
static func force_display(screen: Vector2i, safe: Rect2i) -> void:
	_forced_screen = screen
	_forced_safe = safe


## The display's own size, as this program is told it: the stated one, or the real screen when nothing is stated.
##
## **The one place it is read**, so that the cutout, the foot band and the class of window cannot be answered from
## two different screens in the same pass - which is the shape of fault the arithmetic beside them exists to avoid.
static func screen_here() -> Vector2i:
	if _forced_screen.x > 0 and _forced_screen.y > 0:
		return _forced_screen
	return DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())


## The same for the safe area, which is what a display promises a program it will not draw over.
static func safe_area_here() -> Rect2i:
	if _forced_screen.x > 0 and _forced_screen.y > 0:
		return _forced_safe
	return DisplayServer.get_display_safe_area()


## Where a stated display is held, beside the one door that states it and the two that answer it. **`static`,
## because every door in this file is**: the whole file is arithmetic about a device nobody has to have, so there is
## no instance to keep a stated screen on - and a plain member here is a parse error at the two functions that read
## it, not a warning.
static var _forced_screen: Vector2i = Vector2i.ZERO
static var _forced_safe: Rect2i = Rect2i()


## The half of `apply` that can be told the answer rather than reading it, so that a test can hold what a
## desk and what a phone would be told without being either.
static func apply_if(window: Window, draw_up: bool) -> void:
	if window == null:
		return
	# Touched **only when drawing up**. A computer's window is left exactly as it was - not set back to 1.0,
	# which is not "as it was" - because something else may have drawn it up on purpose: a demonstration
	# states the answer a phone would give and would otherwise have its own answer overwritten a frame later
	# by a program that rightly thinks it is on a desk.
	if draw_up:
		window.content_scale_factor = UI_SCALE


## How many physical pixels one logical pixel is drawn at, which is what turns a layout number into a
## measurement. Read from the window rather than recomputed: the stretch mode, the scale factor and
## the screen are all the window's own business.
static func canvas_scale(window: Window) -> float:
	if window == null:
		return 0.0
	var shown: Vector2 = window.get_visible_rect().size
	if shown.x <= 0.0:
		return 0.0
	return float(window.size.x) / shown.x


## A density stated for a device that is not this one, so a demonstration or a test can ask what a phone
## would be told without being one. 0 means "read the real screen".
static var _forced_density: float = 0.0


## How much bigger than the sizes stated below the words are to be drawn, from the reader's own choice in
## `ReadingSize` - the one Android states and Godot does not. 1.0 is the sizes this file states, and it
## stays 1.0 until the program hands over what was kept, so that nothing which asks about a size reads a
## file and every test that says nothing measures the sizes this project was laid out at.
static var _reading_scale: float = 1.0


## State how much bigger the words are to be drawn: for the program at launch, which is the only place that
## reads the choice, and for a demonstration or a test.
##
## **A factor under one is refused**, and 0 or less means the stated sizes. Every number below is a floor -
## what a thumb can hit, what an eye can read at arm's length - and a scale under one would be this file
## agreeing to be illegible. The same door `force_density` is, one question over.
static func use_reading_scale(factor: float) -> void:
	_reading_scale = factor if factor > 1.0 else 1.0


## The screen's density, or 0 when the platform will not say - and 0 means "cannot be worked out"
## rather than "no density", everywhere below.
static func dpi() -> float:
	if _forced_density > 0.0:
		return _forced_density
	return maxf(float(DisplayServer.screen_get_dpi()), 0.0)


## How many millimetres a length of logical pixels comes to, or 0 when the density is not known.
static func millimetres(logical_px: float, scale: float, density: float) -> float:
	if scale <= 0.0 or density <= 0.0:
		return 0.0
	return logical_px * scale / density * 25.4


## How many logical pixels a length in millimetres comes to, or 0 when the density is not known.
static func logical_for_mm(mm: float, scale: float, density: float) -> float:
	if scale <= 0.0 or density <= 0.0:
		return 0.0
	return mm / 25.4 * density / scale


## The reader's own scale, **and never zero**.
##
## **This file is `@tool` because of one measured fault, and this door is the second half of it.** A `static var`
## initialiser does not run for a script loaded in an editor without `@tool`, so `_reading_scale` read the engine's
## own default - 0 - and every length this file computes from a millimetre came out nothing. Measured, a
## development view on a desk showed furniture 31 px tall with the theme's 16 px type beside the phone's 97 and 41,
## and the same scene run with F6 was right: two sides differing by exactly this factor. **`use_reading_scale`
## refuses a factor under one and the type's own default is 0, so the honest answer is the stated sizes rather than
## a zero nobody asked for.**
static func reading_scale() -> float:
	return _reading_scale if _reading_scale > 0.0 else 1.0


## The height a row of answers has to be on a screen of this density, in logical pixels - and 0 when the
## density or the scale could not be read, which means "no minimum of mine": a size worked out from a
## number that does not exist is worse than the size the layout already has.
##
## This is arithmetic, not the device decision. Whether a device is answered with a finger at all is
## `on_a_finger_here`'s question, asked once in the one place a page is shown - so this answers for any
## screen a caller states, and a desk's own density is converted rather than refused.
static func row_height(scale: float, density: float) -> float:
	return maxf(logical_for_mm(TOUCH_MM * reading_scale(), scale, density), 0.0)


## The font size that draws a capital TEXT_MM tall, in logical pixels - and 0 where there is no
## minimum to apply.
static func font_size(scale: float, density: float) -> int:
	var em: float = logical_for_mm(TEXT_MM * reading_scale(), scale, density) / CAP_RATIO
	if em <= 0.0:
		return 0
	# Rounded up, not down: the constant is a floor - "at least this tall" - and a font size rounded
	# down is a font a hair short of it.
	return ceili(em)


## The size to draw a piece of a page's own text at on a device answered with a finger, given the size the
## page laid it out at.
##
## `font_size` is the floor: the size a capital TEXT_MM tall comes to. A line a page drew *bigger* than its
## own body - a heading, a page's title - is kept bigger by the same proportion, so a page keeps its shape
## when it is made readable rather than every line collapsing onto one size. 0 keeps the layout's own size,
## which is what a line with no size of its own and a density that cannot be read both ask for.
static func text_size_for_a_finger(was: int, scale: float, density: float) -> int:
	var legible: int = font_size(scale, density)
	if legible <= 0 or was <= 0:
		return 0
	return maxi(legible, roundi(float(was) * float(legible) / float(DESK_TEXT)))


## A theme measurement that is *room for text* - a title bar's height, which is room for the title rather
## than room for anything else - grown for a finger by the same proportion the text it was drawn for grew
## by. The bar stays the bar the theme drew, only bigger; a measurement that cannot be grown is left alone.
static func grown_for_a_finger(was: int, was_text: int, now_text: int) -> int:
	if was <= 0 or was_text <= 0 or now_text <= 0:
		return maxi(was, 0)
	return maxi(was, roundi(float(was) * float(now_text) / float(was_text)))


## The margin a page's contents keep from the sides of the screen on a device answered with a finger.
##
## A page is a window on a computer, and the window's frame and its own border are the margin between a page's
## words and the edge of the screen. On a phone the page **is** the screen: there is no frame, so a page whose
## contents are laid out to the whole rectangle puts its sentences and its buttons against the glass. Measured
## on the SM-A166W, 2026-11: the front door's opening sentence came out with its last letters three pixels
## from the edge of a 1080-pixel screen, inside the strip Android keeps for its own back gesture.
##
## Half a `TOUCH_MM` - half the thumb a button is drawn for - is the figure: enough that a sentence is not
## shaved by the edge and a control is not under it, and small enough that a phone does not pay for it in
## width. Zero where the scale or the density could not be read, which every caller reads as "no margin of
## mine" rather than as no margin at all.
static func edge_margin(scale: float, density: float) -> int:
	return roundi(logical_for_mm(TOUCH_MM * 0.5 * reading_scale(), scale, density))


## Where a control remembers the size its words were laid out with. A control that has been made readable on
## a phone can no longer answer that question - the size this file wrote is what `get_theme_font_size`
## reports - and a control fitted every time a panel is shown must not grow every time a panel is shown.
const DRAWN_AT := &"drawn_at"

## The kinds of control this program shows words with. A container, a colour patch, a picture, a separation
## line and a spacer show none, and a size worked out for one of those is a size worked out for nothing.
## `Button` and its kin are not here: a caption is not sized by this rule but by the flat one below, because
## a button's words are a caption rather than a piece of the surface's own prose.
const WORDED: Array[String] = ["Label", "LineEdit", "TextEdit", "RichTextLabel", "ItemList", "MenuBar", "Tree"]


## Whether a control shows words at all.
static func shows_words(control: Control) -> bool:
	if control == null:
		return false
	for kind: String in WORDED:
		if control.is_class(kind):
			return true
	return false


## The size a **window that draws its own words** is drawn at - a menu's items are drawn by the menu rather
## than by a control inside it, which is why a menu is not reached by the rule above. The theme type is the
## window's own class, because that is the type a menu's font is looked up under.
##
## A page is a `Window` too and is not this: a page answers for its own controls in the one place a page is
## shown. What is left here is a pop-up, and a menu that opened at a desk's size on a phone is the very
## defect this exists to stop. Returns whether it was fitted.
static func size_a_windows_words_for_a_finger(window: Window, scale: float, density: float) -> bool:
	if not window_shows_words(window):
		return false
	var kind: StringName = StringName(window.get_class())
	var was: int = int(window.get_meta(DRAWN_AT, window.get_theme_font_size(&"font_size", kind)))
	window.set_meta(DRAWN_AT, was)
	var size: int = text_size_for_a_finger(was, scale, density)
	if size <= 0:
		return false
	window.add_theme_font_size_override(&"font_size", size)
	# The words are what a person reads; the row is what a thumb hits, and those were not the same question.
	_raise_the_row_to_a_thumb(window, size, scale, density)
	return true


## The row a menu draws its items in, raised to the row a thumb needs - and never lowered.
##
## A row is the font's own line plus the separation between items, and the theme's separation is drawn for a
## desk. So a menu whose *words* had been grown for a phone still drew a band shorter than everything around
## it: measured at this phone's own scale, a page's menu came out at **44 px against the 51 px a button
## gets** - the menus being the smallest thing a thumb had to hit on a page, and the very thing the growing
## above was written to stop. The slack goes into the separation, which is the one part of a row that is not
## the words.
##
## Fitting twice is fitting once, and for the same reason every other measurement here remembers what it
## found: the separation is only ever **raised**, so a menu shown again reads the row it already has and
## leaves it alone rather than growing every time somebody opens it. Rounded **up**, like a font size here:
## the constant is a floor - "at least this tall" - and a row a hair under it is a row a thumb misses.
static func _raise_the_row_to_a_thumb(window: Window, size: int, scale: float, density: float) -> void:
	var wanted: float = row_height(scale, density)
	if wanted <= 0.0:
		return
	var font: Font = window.get_theme_font(&"font")
	if font == null:
		return
	var slack: int = ceili(wanted - font.get_height(size))
	if slack > window.get_theme_constant(&"v_separation"):
		window.add_theme_constant_override(&"v_separation", slack)


## Whether a window shows words of its own, rather than being a page its contents answer for.
static func window_shows_words(window: Window) -> bool:
	return window != null and window.is_class("PopupMenu")


## Fit one control to a finger: **a control a thumb presses** is given the row it has to be hit in and the
## flat size its caption is drawn at; **a control that shows words** is given a size grown from the size the
## surface laid it out with, so a surface keeps its shape - a title stays bigger than the sentence under it
## rather than every line coming out one size. Anything else is left exactly as it is. Returns whether the
## control was fitted.
static func fit_for_a_finger(control: Control, scale: float, density: float) -> bool:
	if control == null:
		return false
	if control is BaseButton:
		size_for_a_finger(control, scale, density)
		return row_height(scale, density) > 0.0
	return size_its_words_for_a_finger(control, scale, density)


## The size a control's own words are drawn at on a device answered with a finger, grown from the size the
## surface laid it out with - and what it was laid out with is **remembered on the control**, because Godot
## keeps only the answer that replaced it, so that fitting twice is the same as fitting once. Returns
## whether the control was fitted.
static func size_its_words_for_a_finger(control: Control, scale: float, density: float) -> bool:
	if not shows_words(control):
		return false
	var was: int = int(control.get_meta(DRAWN_AT, control.get_theme_font_size(&"font_size")))
	control.set_meta(DRAWN_AT, was)
	var size: int = text_size_for_a_finger(was, scale, density)
	if size <= 0:
		return false
	control.add_theme_font_size_override(&"font_size", size)
	return true


## Fit every control under a node to a finger, and say how many were fitted.
##
## A **page** met on the way is left alone and is not walked into: a page answers for its own controls in the
## one place a page is shown, and a page fitted by two passes is two answers that can disagree. A **menu** is
## the other kind of window here and is fitted - it draws its own items rather than holding controls that
## could be reached - and a menu that opened at a desk's size on a phone is the very defect this exists to
## stop. The two are told apart the way the engine tells them apart: a page is a `Window`, a menu is a
## `Popup`.
static func fit_the_chrome_for_a_finger(root: Node, scale: float, density: float) -> int:
	if root == null or row_height(scale, density) <= 0.0:
		return 0
	var fitted: int = 0
	# Walked **including the internal children**: the menus a `MenuBar` owns and the list a picker opens are
	# made as internal children, which `get_children()` leaves out by default - and a menu whose items came
	# out at a desk's size while everything around it was fitted is the defect this exists to stop, seen live.
	for child: Node in root.get_children(true):
		var window: Window = child as Window
		if window != null:
			# A page is left standing and is not walked into at all, and a menu is the same: it draws its own
			# items rather than holding controls this could reach, and what it is fitted *for* is the font its
			# items are drawn at - its internals are the engine's. A menu is an internal child of the picker
			# that owns it, which is the whole reason this walk reads internal children in the first place.
			# Measured: a menu that has entered a tree grows internals of its own, a search field among them,
			# and walking in there fits machinery rather than the program's own interface.
			if window is Popup and size_a_windows_words_for_a_finger(window, scale, density):
				fitted += 1
			continue
		var control: Control = child as Control
		if control != null and fit_for_a_finger(control, scale, density):
			fitted += 1
		fitted += fit_the_chrome_for_a_finger(child, scale, density)
	return fitted


## Make one control's answers big enough for a finger: the row it sits in and the text on it.
##
## Nothing happens on a computer, and nothing happens when the density could not be read - a control
## is not given a size worked out from a number that does not exist. The width the caller set is kept:
## how wide a palette cell is belongs to the palette, not to the thumb.
##
## **Where the caller set no width, the width is raised to the same row.** A button with no stated width has
## only its own words to give it one, and a word is narrower than a thumb: on the A16W the top bar's `Fit` came
## out **56 px wide against the 107 px** this device's own 5.5 mm row asks for - a target less than half of what
## the program demands of every other one, and it passed the desk's 44 px floor for three passes before the
## device's own floor was asked. A width the caller *did* state is left exactly as it was, which is the same
## promise this function keeps for a palette cell - and it is why the palette's own cells, which state theirs,
## come out of this unchanged. Measured as a fault on the phone, in portrait: `Fit` 56 x 97, 51 px short.
static func size_for_a_finger(control: Control, scale: float, density: float) -> void:
	if control == null:
		return
	var height: float = row_height(scale, density)
	if height > 0.0:
		control.custom_minimum_size.y = height
		if control.custom_minimum_size.x <= 0.0:
			control.custom_minimum_size.x = height
		give_a_dialogs_own_button_the_row(control, height)
	var size: int = font_size(scale, density)
	if size > 0:
		control.add_theme_font_size_override("font_size", size)


## The row a **dialog's own** button is given, through its frame rather than through its minimum.
##
## The two buttons a `ConfirmationDialog` answers with are the engine's, and it takes their minimum away the
## moment the dialog is shown: measured on the desk with the phone's own numbers handed in,
## `custom_minimum_size` read `(107.078, 107.078)` before `popup_centered_clamped()` and `(0, 0)` after it,
## with the font override surviving - and measured again on the A16W held upright, where the probe named the
## result: `Button "Keep editing" is 254 x 64, 33 px short of the 97 a finger wants`. So for these two a
## minimum is no lever at all.
##
## What the engine does keep is the **frame**. A button's own minimum is its font plus its stylebox, which is
## exactly why 45 px of type in a 13 px frame came out at the 71 it did. A frame that asks for the row
## therefore gives the row, in the engine's own arithmetic, and there is nothing left to argue with. The
## styleboxes are **duplicated** before they are changed, because the ones handed out by a theme are shared by
## every button drawn with them and growing one in place would move the whole program.
##
## Only a dialog's own buttons are touched. Every other button keeps the minimum this pass sets and is measured
## with it, and a frame grown there as well would be that same row twice.
static func give_a_dialogs_own_button_the_row(control: Control, row: float) -> void:
	var button: Button = control as Button
	if button == null or not _is_a_dialogs_own_button(button):
		return
	var font: Font = button.get_theme_font(&"font")
	var size: int = button.get_theme_font_size(&"font_size")
	var frame: StyleBox = button.get_theme_stylebox(&"normal")
	if font == null or size <= 0 or frame == null:
		return
	var asks: float = (
		float(font.get_height(size)) + frame.get_content_margin(SIDE_TOP) + frame.get_content_margin(SIDE_BOTTOM)
	)
	var gap: float = row - asks
	if gap <= 0.0:
		# Already the row - which is what a second pass over the same question finds, so this is idempotent
		# rather than cumulative.
		return
	for state: StringName in DIALOG_BUTTON_STATES:
		var box: StyleBox = button.get_theme_stylebox(state)
		if box == null:
			continue
		var grown: StyleBox = box.duplicate()
		grown.content_margin_top = box.get_content_margin(SIDE_TOP) + gap * 0.5
		grown.content_margin_bottom = box.get_content_margin(SIDE_BOTTOM) + gap * 0.5
		button.add_theme_stylebox_override(state, grown)


## The states a button draws itself in, so that the row is kept when it is hovered, held and switched off as
## well as when it is at rest.
const DIALOG_BUTTON_STATES: Array[StringName] = [&"normal", &"hover", &"pressed", &"disabled", &"focus"]


## Whether a button is one a dialog draws itself - `get_ok_button()` or `get_cancel_button()`.
##
## Told apart by its place rather than by its look: it is a `Button` inside an `AcceptDialog`, which the walk
## reaches by climbing rather than by remembering how deep the engine nests its button bar. The climb stops at
## the first `Window` it meets, so a button inside a page - a window that is not a dialog - is never mistaken
## for one.
static func _is_a_dialogs_own_button(button: Button) -> bool:
	var node: Node = button.get_parent()
	while node != null:
		if node is AcceptDialog:
			return true
		if node is Window:
			return false
		node = node.get_parent()
	return false


## The width a button will actually ask for, worked out from its own words and its own frame.
##
## Asked of a button whose font has just been changed, before the layout has had a frame to settle:
## `get_combined_minimum_size()` still answers the width it had under the old font there, which is how a
## palette widened in that same pass came out 180 px too narrow and drew "awing (0)" where "Drawing (0)"
## was. The words and the style box are what the button is measured by in the end, so measuring them
## directly is the answer that cannot be a frame behind.
static func button_width(button: Control) -> float:
	if button == null:
		return 0.0
	var said: String = ""
	if button is Button:
		said = (button as Button).text
	var words: float = 0.0
	var font: Font = button.get_theme_font(&"font")
	var size: int = button.get_theme_font_size(&"font_size")
	if font != null and size > 0 and said != "":
		# The widest line, not the whole string run together: a palette button carries its word and the
		# key that runs it on two lines, and the key sits *under* the word rather than beside it, so a
		# short key must not widen the button and a long one must.
		for line: String in said.split("\n"):
			words = maxf(words, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	var frame: StyleBox = button.get_theme_stylebox(&"normal")
	if frame != null:
		words += frame.get_minimum_size().x
	return maxf(words, button.custom_minimum_size.x)


## How many columns a row of buttons may have and still fit the room it is given.
##
## A row of six short words is one row on a computer and two rows of three on a phone, because the words
## are twice as tall there and six of them then want twice the width. Never more columns than the row was
## built with, and never fewer than `fewest` - a palette squeezed to one column is a list, not a palette.
static func columns_that_fit(widths: Array, columns: int, room: float, separation: float, fewest: int) -> int:
	var built: int = maxi(columns, 1)
	if widths.is_empty() or room <= 0.0:
		return built
	var widest: float = 0.0
	for width: float in widths:
		widest = maxf(widest, width)
	if widest <= 0.0:
		return built
	var fitting: int = int(floorf((room + separation) / (widest + separation)))
	return clampi(fitting, maxi(fewest, 1), built)
