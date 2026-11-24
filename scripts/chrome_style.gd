class_name ChromeStyle
## The one place the HUD's own chrome plates are styled, so that the bar and the panels behind the program's
## furniture cannot drift into two different panes.
##
## **This is not a second `PageChrome`, and the line between them is the one the engine draws.** A page is a
## `Window` whose contents `PageChrome` builds, places and gives the keyboard; what this styles is the furniture
## standing over the board - the top bar, and whatever joins it - which is a `PanelContainer` and never a page.
## The fault this project works hardest to avoid is a second engine that can disagree with the first, so when the
## bar's plate stopped being the scene's own `StyleBoxFlat` it was given one owner rather than a call site - and
## that owner **derives the plate from the one the scene drew**, rather than stating the colour, the corners and
## the insets a second time. `tests/test_chrome_style.gd` holds the two together.
##
## The plate is a `StyleBoxFancy` from the vendored addon (`addons/StyleboxFancy/`, MIT) rather than a
## `StyleBoxFlat`, for the one thing a flat box cannot draw: a **rule laid inside the plate's own edge**. A
## `StyleBoxFlat` has a single border and draws it on the edge itself, where over a rounded corner it thickens
## the corner instead of reading as a seam; a border stack can hold a second line inset from the edge, and that
## is what makes this bar read as a pane lying over the board. The addon does not override
## `StyleBox.get_minimum_size`, so the content margins the scene's plate carries come across unchanged and the
## row inside the bar is inset identically - which is why swapping the plate cannot move the row that sits in it.
##
## The addon is reached **by path**, the way every other addon here is (`tools/stylebox_fancy_demo.gd` says why):
## the file parses whether or not a language server has registered the global class name.

const FancyScript := preload("res://addons/StyleboxFancy/StyleBoxFancy.gd")
const BorderScript := preload("res://addons/StyleboxFancy/StyleBorder.gd")

## The rule laid inside the plate's edge: a shade lighter than the plate, which is what makes the bar read as a
## pane lying over the board rather than as a hole cut out of it.
const RULE := Color(0.62, 0.71, 0.63, 0.7)
## **The rule is three pixels wide and sits six inside the edge, and both numbers are forced by the addon's own
## arithmetic rather than chosen by eye.** In `StyleBoxFancy._draw_border`'s anti-aliased path the outer rect is
## pulled in by half the anti-aliasing width and the inner rect pushed out by the same half, so the ring that
## reaches the glass is `width - anti_aliasing_size` wide - a one-pixel rule therefore draws *nothing at all*,
## and the first version of this plate was indistinguishable from the flat box it replaced. Three against an
## anti-aliasing width of one leaves two pixels, which is a line a person can see. The inset is what keeps the
## rule off the plate's own rounded edge. A person wanting a thinner line must turn anti-aliasing off and accept
## a jagged corner with it.
const RULE_WIDTH := 3
const RULE_INSET := 6

## The look `res://scenes/ui/hud.tscn` states for its own plate, kept here for the one case that plate cannot be
## read: a theme that hands a `StyleBox` which is not a `StyleBoxFlat`. `tests/test_chrome_style.gd` holds these
## equal to the scene's, so a change made to one and not the other fails the suite rather than the glass.
const PAPER := Color(0.07, 0.09, 0.1, 0.82)
const CORNER := 8
const CORNER_DETAIL := 8
const SIDE := 16.0
const FOOT := 9.0
const ANTI_ALIASING_SIZE := 1.0


## The top bar's plate: the plate the scene drew, with the row's own insets handed in and the rule laid just
## inside its edge.
##
## **The three insets are arguments rather than constants, because they are the whole of what a lift does.** The
## plate is asked to run to the screen's own edges so that a band the device keeps - a phone's camera cutout - is
## covered by the bar rather than by bare board, and the row inside it is pushed clear by exactly what the device
## keeps, plus the distance the plate's own edge moved. **The sides are here because a phone held sideways keeps
## its camera on the left**: measured on the A16W lying down, the bar's row stood at x 28 while the device kept the
## room's first 62 px, so the row was under the camera and a thumb aimed at `Menu` met the system. The caller knows
## every one of those figures, because it is the caller that read the display and moved the bar; this file only
## draws, and it states no inset of its own.
##
## **The fifth argument is the corner the display rounds, and a zero leaves the look exactly as the scene drew it.**
## Where the bar runs to the glass's own edges its two top corners stand *in* the display's rounded corner, and the
## radius there is the display's own figure rather than the scene's eight: a plate whose own curve was wider than the
## glass's would leave a sliver of bare board in a corner the bar is meant to cover, and one whose curve was narrower
## would simply be cut by the glass. Stating the display's radius makes the two curves the same curve, which is what
## a person sees as a bar that follows the screen. A desk, and a display that rounds nothing, hand in nothing.
static func bar_plate(
	drawn: StyleBox,
	content_top: float,
	content_left: float,
	content_right: float,
	corner: int = 0,
) -> StyleBox:
	var plate: Variant = _plate_from(drawn)
	# The row's insets are the ones the caller states, and they are set **after** the scene's, or the scene's would
	# win - which is what makes the same call put the row back where the scene drew it when there is no band.
	plate.content_margin_top = content_top
	plate.content_margin_left = content_left
	plate.content_margin_right = content_right
	_add_the_round_to_the_top_corners(plate, corner)
	_add_the_full_rule(plate)
	return plate as StyleBox


## **The corners the plate meets the glass at, which the glass itself decides.** The bar's own two top corners are
## the only ones it has standing in a screen corner - its foot is out on the board - so those are the two this
## rounds, and the scene's own radius is **replaced** rather than raised: the eight px was this program's statement
## about a pane lying in the middle of a board, and inside the display's own rounded corner the glass's figure is the
## one that is true.
##
## A zero draws nothing here and leaves every corner exactly as `_plate_from` read it, which is the whole of the desk.
static func _add_the_round_to_the_top_corners(plate: Variant, corner: int) -> void:
	if corner <= 0:
		return
	plate.corner_radius_top_left = corner
	plate.corner_radius_top_right = corner


## A plate anchored to the foot of the screen: `TouchDock` under a finger, and the sheets that open over it.
##
## Two things make it a dock rather than a bar stood on its head. **The corners are round at the top and square
## at the foot** - the top is the edge a person sees against the board, and the foot runs off the glass - and
## **the rule is drawn on the top edge alone**, for the same reason: it is the seam where the plate meets the
## board, not a frame around an edge nothing can see.
##
## The top margin is the caller's, exactly as the bar's lift is: this file only draws, and the caller is the one
## that read the device and knows how far down the plate's own contents have to stand.
static func dock_plate(drawn: StyleBox, content_top: float) -> StyleBox:
	var plate: Variant = _plate_from(drawn)
	plate.corner_radius_bottom_left = 0
	plate.corner_radius_bottom_right = 0
	plate.content_margin_top = content_top
	_add_a_top_rule(plate)
	return plate as StyleBox


## A plate that floats clear of every edge, with all four corners round and the rule all the way round: the
## `ToolStrip` drawn above the dock. It states no margin of its own, so the one the scene drew is the one it
## wears - a floating plate has not been lifted by anything.
static func floating_plate(drawn: StyleBox) -> StyleBox:
	var plate: Variant = _plate_from(drawn)
	_add_the_full_rule(plate)
	return plate as StyleBox


## The plate the scene drew, as the addon's own stylebox - **the one statement of the look this file has**, so
## that a plate made for a new piece of furniture cannot be a subtly different pane from the bar's.
##
## Everything the scene states is read back here: the colour, all four corners, the corner detail, the
## anti-aliasing and **all four** content margins - the top one included, which a lifted plate then overrides.
## Copying the top rather than leaving it is what keeps that fourth margin from arriving as the stylebox class's
## own unset value and being resolved against a theme this project does not have.
##
## The constants declared above stand in only where the plate cannot be read, which is a `StyleBox` that is not a
## `StyleBoxFlat` - the case `tests/test_chrome_style.gd` holds against the scene for exactly that reason.
static func _plate_from(drawn: StyleBox) -> Variant:
	var plate: Variant = FancyScript.new()
	plate.draw_center = true
	plate.color = PAPER
	plate.corner_radius_top_left = CORNER
	plate.corner_radius_top_right = CORNER
	plate.corner_radius_bottom_right = CORNER
	plate.corner_radius_bottom_left = CORNER
	plate.corner_detail = CORNER_DETAIL
	plate.content_margin_left = SIDE
	plate.content_margin_right = SIDE
	plate.content_margin_top = FOOT
	plate.content_margin_bottom = FOOT
	plate.anti_aliasing_size = ANTI_ALIASING_SIZE
	# The scene's own plate is read wherever it is one this file can read, so that the colour, the corners and the
	# insets have one statement in the project rather than two free to drift apart.
	if drawn is StyleBoxFlat:
		var flat: StyleBoxFlat = drawn as StyleBoxFlat
		plate.color = flat.bg_color
		plate.draw_center = flat.draw_center
		plate.corner_radius_top_left = flat.corner_radius_top_left
		plate.corner_radius_top_right = flat.corner_radius_top_right
		plate.corner_radius_bottom_right = flat.corner_radius_bottom_right
		plate.corner_radius_bottom_left = flat.corner_radius_bottom_left
		plate.corner_detail = flat.corner_detail
		plate.content_margin_left = flat.content_margin_left
		plate.content_margin_right = flat.content_margin_right
		plate.content_margin_top = flat.content_margin_top
		plate.content_margin_bottom = flat.content_margin_bottom
		plate.anti_aliasing_size = flat.anti_aliasing_size
	return plate


## The rule laid just inside the plate's edge, **on all four sides** - the bar's own, and the floating strip's.
##
## **Filled, not replaced.** `borders` is a typed `Array[StyleBorder]`, so an array literal is refused at run
## time; appending to the array the stylebox already owns is what keeps it typed, and needs no class name
## spelled here.
static func _add_the_full_rule(plate: Variant) -> void:
	var rule: Variant = BorderScript.new()
	rule.color = RULE
	rule.width_left = RULE_WIDTH
	rule.width_top = RULE_WIDTH
	rule.width_right = RULE_WIDTH
	rule.width_bottom = RULE_WIDTH
	rule.inset_left = RULE_INSET
	rule.inset_top = RULE_INSET
	rule.inset_right = RULE_INSET
	rule.inset_bottom = RULE_INSET
	plate.borders.append(rule)


## The same rule on the **top edge alone**, which is the seam a plate anchored to the foot of the screen meets
## the board at. The sides and the foot run off the glass, so a ring drawn there would be a line at an edge
## nothing can see, and the two corners it would round are square besides.
##
## A width of zero draws no ring at all, so this is the one rule narrowed rather than a second look stated
## differently - which is what keeps a dock's seam and a bar's seam the same colour, the same width and the same
## distance inside the plate.
static func _add_a_top_rule(plate: Variant) -> void:
	var rule: Variant = BorderScript.new()
	rule.color = RULE
	rule.width_left = 0
	rule.width_top = RULE_WIDTH
	rule.width_right = 0
	rule.width_bottom = 0
	rule.inset_top = RULE_INSET
	plate.borders.append(rule)
