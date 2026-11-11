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
class_name PhoneHud
extends RefCounted

const TouchInputScript := preload("res://scripts/touch_input.gd")

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
	return TouchInputScript.answered_by_a_thumb(
		TouchInputScript.has_a_touchscreen(), density, desk_mm, TOUCH_MM
	)


## Whether this device is a phone rather than a tablet: a finger, on a screen small enough that the canvas
## is worth drawing up as well. A tablet is sized for a finger and left at its own scale, because drawing a
## ten-inch screen up by a third costs it a third of its drawing area and gains nothing.
static func zooming_here() -> bool:
	return on_a_finger_here() and TouchInputScript.needs_zooming(across_inches())


## How far a phone's own furniture - the camera cutout, the status bar - reaches down from the top of the
## screen, given in the room's own pixels. Zero on a desk, and on a display that reports no cutout.
##
## The safe area is a fact about the display, in the display's pixels; the room a page lands in is the
## viewport's, and on a phone those are not the same number - the SM-A166W reports 1080 by 2340 natively and
## a 1185 by 2567 room, so a figure in one is not a figure in the other. The answer is the cutout's share of
## the screen's height and nothing more: a fraction, which is the one thing that travels between the two.
static func cutout_top(room: Vector2i) -> int:
	if not on_a_finger_here() or room.y <= 0:
		return 0
	var screen: int = DisplayServer.window_get_current_screen()
	var full: Vector2i = DisplayServer.screen_get_size(screen)
	if full.y <= 0:
		return 0
	var inset: int = maxi(DisplayServer.get_display_safe_area().position.y, 0)
	if inset <= 0:
		return 0
	return roundi(float(room.y) * (float(inset) / float(full.y)))


## How many inches the screen is across its longer side, or 0 when the density is not known - the
## measurement `TouchInput.needs_zooming` is a comparison against.
static func across_inches() -> float:
	var density: float = dpi()
	if density <= 0.0:
		return 0.0
	var screen: Vector2i = DisplayServer.screen_get_size()
	return maxf(float(screen.x), float(screen.y)) / density


## State what a device would be told about its density, for a demonstration or a test - and 0 puts the
## real reading back. The same door `TouchInput.force` and `PhoneFiles.force` are, asked of a third thing.
static func force_density(density: float) -> void:
	_forced_density = density


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


## The height a row of answers has to be on a screen of this density, in logical pixels - and 0 when the
## density or the scale could not be read, which means "no minimum of mine": a size worked out from a
## number that does not exist is worse than the size the layout already has.
##
## This is arithmetic, not the device decision. Whether a device is answered with a finger at all is
## `on_a_finger_here`'s question, asked once in the one place a page is shown - so this answers for any
## screen a caller states, and a desk's own density is converted rather than refused.
static func row_height(scale: float, density: float) -> float:
	return maxf(logical_for_mm(TOUCH_MM, scale, density), 0.0)


## The font size that draws a capital TEXT_MM tall, in logical pixels - and 0 where there is no
## minimum to apply.
static func font_size(scale: float, density: float) -> int:
	var em: float = logical_for_mm(TEXT_MM, scale, density) / CAP_RATIO
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
	return roundi(logical_for_mm(TOUCH_MM * 0.5, scale, density))


## Where a control remembers the size its words were laid out with. A control that has been made readable on
## a phone can no longer answer that question - the size this file wrote is what `get_theme_font_size`
## reports - and a control fitted every time a panel is shown must not grow every time a panel is shown.
const DRAWN_AT := &"drawn_at"

## The kinds of control this program shows words with. A container, a colour patch, a picture, a separation
## line and a spacer show none, and a size worked out for one of those is a size worked out for nothing.
## `Button` and its kin are not here: a caption is not sized by this rule but by the flat one below, because
## a button's words are a caption rather than a piece of the surface's own prose.
const WORDED: Array[String] = [
	"Label", "LineEdit", "TextEdit", "RichTextLabel", "ItemList", "MenuBar", "Tree",
]


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
	return true


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
static func size_for_a_finger(control: Control, scale: float, density: float) -> void:
	if control == null:
		return
	var height: float = row_height(scale, density)
	if height > 0.0:
		control.custom_minimum_size.y = height
	var size: int = font_size(scale, density)
	if size > 0:
		control.add_theme_font_size_override("font_size", size)


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
static func columns_that_fit(
	widths: Array, columns: int, room: float, separation: float, fewest: int
) -> int:
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
