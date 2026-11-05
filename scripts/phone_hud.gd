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
## `PhoneFiles.on_phone()`, asked once in one place rather than twice in two.
class_name PhoneHud
extends RefCounted

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


## Draw the canvas up on a phone, and leave a computer's window exactly as it was.
static func apply(window: Window) -> void:
	if window == null or not PhoneFiles.on_phone():
		return
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


## The screen's density, or 0 when the platform will not say - and 0 means "cannot be worked out"
## rather than "no density", everywhere below.
static func dpi() -> float:
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


## The height a row of answers has to be, in logical pixels - and 0 on anything but a phone, which
## means "no minimum of mine": the HUD's own layout is the layout a desk was drawn for.
static func row_height(scale: float, density: float) -> float:
	if not PhoneFiles.on_phone():
		return 0.0
	return maxf(logical_for_mm(TOUCH_MM, scale, density), 0.0)


## The font size that draws a capital TEXT_MM tall, in logical pixels - and 0 where there is no
## minimum to apply.
static func font_size(scale: float, density: float) -> int:
	if not PhoneFiles.on_phone():
		return 0
	var em: float = logical_for_mm(TEXT_MM, scale, density) / CAP_RATIO
	if em <= 0.0:
		return 0
	# Rounded up, not down: the constant is a floor - "at least this tall" - and a font size rounded
	# down is a font a hair short of it.
	return ceili(em)


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
		words = font.get_string_size(said, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
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
