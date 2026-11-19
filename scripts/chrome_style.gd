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

## The top bar's plate: the plate the scene drew, with the row's own top inset handed in and the rule laid just
## inside its edge.
##
## **The top inset is an argument rather than a constant, because it is the whole of what the lift does.** The
## plate is asked to run to the screen's own top so that a band the device keeps - a phone's camera cutout - is
## covered by the bar rather than by bare board, and the row inside it is pushed down by exactly what the device
## keeps, plus the distance the plate's own top moved up. The caller knows that figure, because it is the caller
## that read the display and moved the bar; this file only draws.
static func bar_plate(drawn: StyleBox, content_top: float) -> StyleBox:
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
		plate.content_margin_bottom = flat.content_margin_bottom
		plate.anti_aliasing_size = flat.anti_aliasing_size
	# The row is the one margin the caller states, and it is set **after** the scene's, or the scene's would win.
	plate.content_margin_top = content_top
	# **Filled, not replaced.** `borders` is a typed `Array[StyleBorder]`, so an array literal is refused at run
	# time; appending to the array the stylebox already owns is what keeps it typed, and needs no class name
	# spelled here.
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
	return plate as StyleBox
