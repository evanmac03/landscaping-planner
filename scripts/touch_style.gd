class_name TouchStyle
## The style of the controls a finger presses: what a press looks like, and what a control that cannot be
## pressed looks like.
##
## **Why a state needs styling at all: a finger has no hover.** A mouse answers "is this pressable, and did I
## hit it?" twice before a click even lands - the cursor changes shape, and the control lights up. A thumb gets
## only what is painted. Measured against Godot's own default theme, which is what this program's controls wear
## (the project sets no theme of its own), two of those answers were weak:
##
## - **a press went darker** - `#1a1a1a` to `#000000`, a luminance change of **0.10**, with the border
##   unchanged - which is close to invisible in daylight on a phone;
## - **a disabled button was painted exactly like a live one** - the same `#1a1a1a` fill and the same
##   `#cccccc` border, with only a dimmer label - so on a phone, where nothing hovers beforehand, a person had
##   no way to see it coming.
##
## So a press is now **a bright fill where the engine's own was a darkening** - measured on the glass, the
## held tool read `#6e7580` on the phone where the button beside it, untouched, read `#272828` - and a control
## that cannot be pressed is painted as inert.
##
## **Nothing about size changes, and that is a rule rather than a happy accident.** A stylebox's content
## margins, border widths and expand margins are *layout* here: they are what `PageLayout` reads as a page's
## padding, what the room arithmetic subtracts, and what the audit measures a page's contents against. So every
## box below is **the engine's own box for that state, duplicated and recoloured**, which makes the geometry
## the engine's by construction - a recolouring cannot move a fit, and a future change to Godot's own geometry
## is inherited rather than contradicted. `tests/test_touch_style.gd` holds exactly that.
##
## **A press carries no border, and that is this rule rather than a preference.** A `StyleBoxFlat`'s border
## widths are counted in its minimum size, so a border drawn here would make every button it touched a few
## pixels wider and taller - a styling pass that moved a fit, which is the one thing this may not do. A fill is
## free; a border is a size.
##
## **Where it is worn is part of the answer, and it is not where it was first put.** A theme lookup walks up
## the tree from each control and settles on the first theme it meets - and a **`CanvasLayer` breaks that
## walk**. Measured: a `Button` under `root > CanvasLayer > Control` answers the engine's own default theme,
## while the same theme worn by the `Control` inside the layer answers this program's. This HUD *is* a
## `CanvasLayer`, so the tree's root reaches none of it and the style is worn by the two carriers beneath the
## layer instead - the HUD's own `Root` control, and every page where `PageChrome` lands it.

extends RefCounted

## What a press is painted with: brighter than the rest state by about a third of the whole range, so a thumb
## that has just landed on a button is told so. It is the **whole** of the press, because a `Button`'s own boxes
## are borderless and a border would be a size.
const PRESSED_BG := Color(0.43, 0.46, 0.5, 1.0)

## What a control that cannot be pressed is painted with: its fill pulled down, and its words given this
## program's own dim - two differences from a live control rather than none, and both legible rather than
## invisible.
const DEAD_BG := Color(0.06, 0.06, 0.06, 1.0)
## The dim border a dead control is given, **where the engine's own box draws one at all**: a `Button`'s boxes
## are borderless, so on the controls here it is the fill and the words that say a control is dead. It is stated
## for a box that has a border to dim rather than left out, because a colour that nobody can see is not the same
## as a colour that was never chosen.
const DEAD_BORDER := Color(0.29, 0.29, 0.29, 1.0)
const DEAD_TEXT := Color(0.42, 0.42, 0.42, 1.0)

## The kinds of button this styles. A `Button`'s own subclasses reach these through the theme type chain, but
## every one of them has entries of its own in Godot's default theme, so they are named: whether a chain is
## walked from the control's type downwards or the nearest theme's entries win is exactly the sort of thing
## that is true until it is not. `tests/test_touch_style.gd` drives a real `CheckBox` and a real
## `OptionButton` through the applied theme rather than trusting this list.
##
## **Two of the five get nothing, and that is the answer rather than an oversight.** A `CheckBox` and a
## `CheckButton` state every one of these items with a `StyleBoxEmpty`: what says whether one is on is its own
## tick, so there is no fill to repaint and inventing one would be a second answer to a question the engine
## already draws. Measured, not assumed - the test counts them as left alone.
const BUTTON_KINDS: Array[StringName] = [
	&"Button",
	&"CheckBox",
	&"CheckButton",
	&"OptionButton",
	&"MenuButton",
]


## The theme this program's controls wear.
##
## Built fresh each call rather than kept in a static, because it is handed to one node once at startup and a
## cached stylesheet is the kind of thing that goes stale in a way nobody can see. The caller keeps it.
##
## **Why every kind is named, and why a kind that draws nothing has that nothing written down beside it.** A
## theme lookup walks the control's *type chain* inside the nearest theme before it ever reaches the engine's:
## asked for a `CheckBox`'s press state it looks for `CheckBox`, then `Button` - so stating `Button`'s states
## alone would hand a tick box the fill meant for a button. A `CheckBox` states its own as a `StyleBoxEmpty`
## precisely because its tick carries the answer, so where the engine draws nothing this states nothing, and
## the kinds that really are repainted are the ones that paint a fill themselves.
static func build() -> Theme:
	var theme := Theme.new()
	var defaults: Theme = ThemeDB.get_default_theme()
	for kind: StringName in BUTTON_KINDS:
		_press_states(theme, defaults, kind)
		_state(theme, defaults, kind, &"disabled", DEAD_BG, DEAD_BORDER)
		theme.set_color(&"font_color_disabled", kind, DEAD_TEXT)
	return theme


## One press, under both of the names the engine can draw it by.
##
## **Both names, and one box, and that is measured rather than tidy.** A finger always hovers - a touch arrives
## as a pointer that stays - so a button being held, and a toggle that is on, are drawn by the engine in its
## *press-while-hovered* state rather than in its pressed one; and the engine states **nothing at all** for
## `hover_pressed` on a `Button`, so a lookup for it lands on the fallback box, which draws no centre.
## Measured on the glass: with only `pressed` stated, a phone drew this program's border around **no fill at
## all** - the palette's tool-in-hand showed the panel behind it. So both names carry the one box a press
## draws: a finger has no separate hover, and a press that looked different because a pointer happened to be
## over it would be a distinction no thumb could make.
static func _press_states(theme: Theme, defaults: Theme, kind: StringName) -> void:
	var theirs: StyleBox = defaults.get_stylebox(&"pressed", kind)
	var recoloured: StyleBox = _recoloured(theirs, PRESSED_BG)
	if recoloured == null:
		# A kind whose press is no fill at all - a `CheckBox`'s tick is what says whether it is on. Where the
		# engine states that nothing, this states the same nothing beside it; where it states nothing at all,
		# saying nothing is the answer and no button's fill is written in its place.
		if not defaults.has_stylebox(&"pressed", kind):
			return
		recoloured = theirs
	theme.set_stylebox(&"pressed", kind, recoloured)
	theme.set_stylebox(&"hover_pressed", kind, recoloured)


## One state of one kind, in the three cases there are: the engine draws a fill for it (repaint a copy of the
## engine's own box), the engine states it and draws nothing (state that nothing, so this kind's answer is not
## lost to the `Button` entry above it), or the engine states nothing at all for this kind and the answer comes
## from an ancestor type - which is already handled here.
static func _state(
	theme: Theme,
	defaults: Theme,
	kind: StringName,
	item: StringName,
	fill: Color,
	border: Color
) -> void:
	var theirs: StyleBox = defaults.get_stylebox(item, kind)
	var recoloured: StyleBox = _recoloured(theirs, fill)
	if recoloured != null:
		# The border is dimmed only where the engine's own box draws one at all: a `Button`'s boxes are all
		# borderless, so writing a border colour on one of them would be a colour nobody could ever see.
		var flat := recoloured as StyleBoxFlat
		var bordered: bool = (
			flat.border_width_left > 0
			or flat.border_width_right > 0
			or flat.border_width_top > 0
			or flat.border_width_bottom > 0
		)
		if bordered:
			flat.border_color = border
		theme.set_stylebox(item, kind, recoloured)
	elif defaults.has_stylebox(item, kind):
		theme.set_stylebox(item, kind, theirs)


## Put this program's control style on one carrier.
##
## A carrier is a `Control` or a `Window`; anything else - a plain `Node`, a null - has nowhere to wear a
## theme and is answered `false` rather than failing. `true` means the node handed in is a carrier, whether it
## has just been given this style or already wore one.
##
## **It goes on the nodes inside the `Hud` `CanvasLayer`, and that is measured rather than reasoned.** A theme
## lookup walks up from each control and settles on the first theme it meets, but a **`CanvasLayer` in the
## chain stops the walk**: a `Button` under `root > CanvasLayer > Control` answers the engine's own default,
## and the same theme worn by the `Control` inside the layer answers this program's. This HUD is a
## `CanvasLayer`, so the tree's root reaches nothing in it, and there are two carriers under the layer:
## `hud.gd` puts it on the HUD's own `Root` control, and `page_chrome.gd` puts it on each page where the page
## lands - one stylesheet, worn in the two places the layer leaves reachable.
##
## **A carrier that already wears a theme keeps it.** This is the program's default look, not an override: a
## page that wants a look of its own is not overruled by a function whose whole job is to give a bare page the
## look everything else has. Handing the same carrier this style twice leaves the theme it already wears alone
## rather than building a fresh one, which is what makes a page landing again on every change of the room's
## shape cost nothing.
static func apply_to(carrier: Node) -> bool:
	if carrier is Control:
		var as_control := carrier as Control
		if as_control.theme == null:
			as_control.theme = build()
		return true
	if carrier is Window:
		var as_window := carrier as Window
		if as_window.theme == null:
			as_window.theme = build()
		return true
	return false


## The engine's own box for a state, repainted - and **nothing but repainted**. See the class comment: the
## margins, the border widths, the corners, the expand margins and the antialiasing all come along from the
## engine's box, which is what keeps this a styling change rather than a layout one.
##
## What it sets is the **fill and nothing else**, because a fill is the one part of a box that costs no room. A
## caller that has a border to write writes it itself, and only where the box draws one.
static func _recoloured(box: StyleBox, fill: Color) -> StyleBox:
	if box == null:
		return null
	var flat := box.duplicate() as StyleBoxFlat
	if flat == null:
		return null
	flat.bg_color = fill
	return flat