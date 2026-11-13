extends Node
## The style of a control a finger presses, held to the two things a thumb cannot be told any other way: that
## a press is visible, and that a control which cannot be pressed does not look like one that can.
##
## Nothing here needs the game. The boxes are read off the theme this file builds and off the engine's own, and
## the controls built to drive the lookup are freed in the test that made them.
##
## **Four facts about Godot's theme system this file had to be corrected by rather than assumed.** A `Theme`'s
## `get_stylebox` **falls back to the default theme**, so it answers "what would be drawn" and not "what does
## this theme state" - `has_stylebox` is the question about this theme. A `CheckBox`/`CheckButton` states
## every button state with a `StyleBoxEmpty`: its tick is what says whether it is on, so there is no fill to
## repaint and none is invented for it. **A `CanvasLayer` stops the theme walk**, which is where this style has
## to be worn rather than a detail of it - see `test_a_canvas_layer_stops_the_theme_walk`. And **a finger
## always hovers**: a touch arrives as a pointer that stays, so a held button or a toggle that is on is drawn
## in the engine's *press-while-hovered* state, for which a `Button` states nothing at all - see
## `test_a_press_is_drawn_the_same_whether_or_not_a_pointer_is_over_it`.

const TouchStyleScript := preload("res://scripts/touch_style.gd")

var _made: Array[Node] = []
var _states: Array[StringName] = [&"pressed", &"hover_pressed", &"disabled"]


## A finger has no hover, so the press state is the whole of what it is told, and the fault this holds was
## measured rather than supposed: Godot's own default takes a press **darker** than rest - `#1a1a1a` to
## `#000000`, a luminance change of 0.10, with the border untouched - which is close to invisible in daylight.
func test_a_press_is_brighter_than_every_other_state() -> void:
	var theme: Theme = TouchStyleScript.build()
	var defaults: Theme = ThemeDB.get_default_theme()
	var rest: float = (defaults.get_stylebox(&"normal", &"Button") as StyleBoxFlat).bg_color.get_luminance()
	var before: float = (defaults.get_stylebox(&"pressed", &"Button") as StyleBoxFlat).bg_color.get_luminance()
	assert(before < rest, "the engine's own press goes darker than rest: %.3f against %.3f" % [before, rest])
	var seen: float = (theme.get_stylebox(&"pressed", &"Button") as StyleBoxFlat).bg_color.get_luminance()
	assert(seen > rest + 0.25, "a press now stands out from rest: %.3f against %.3f" % [seen, rest])
	var hover: float = (defaults.get_stylebox(&"hover", &"Button") as StyleBoxFlat).bg_color.get_luminance()
	assert(seen > hover, "and outshines hover, so a press is the brightest thing a thumb can be shown")
	var flat := theme.get_stylebox(&"pressed", &"Button") as StyleBoxFlat
	var theirs := defaults.get_stylebox(&"pressed", &"Button") as StyleBoxFlat
	assert(
		theirs.bg_color.a < 1.0,
		"the engine's own press is a black at %.0f%% that darkens whatever is behind it" % (theirs.bg_color.a * 100.0),
	)
	assert(
		is_equal_approx(flat.bg_color.a, 1.0),
		"and this one is a solid fill, so what it covers cannot show through it",
	)


## A press is drawn **the same whether or not a pointer is over it**, because the two are one box.
##
## This is the fault the glass found and no reading of the theme would have: a finger always hovers - a touch
## arrives as a pointer that stays - so a button being held, and a toggle that is on, are drawn in the engine's
## *press-while-hovered* state; and the engine states **nothing at all** for a `Button`'s `hover_pressed`, so
## the box a lookup falls back to draws no centre. Measured on the phone: with only `pressed` stated, the
## palette's tool-in-hand showed this program's border around the panel behind it - no fill at all.
func test_a_press_is_drawn_the_same_whether_or_not_a_pointer_is_over_it() -> void:
	var theme: Theme = TouchStyleScript.build()
	var defaults: Theme = ThemeDB.get_default_theme()
	assert(
		not defaults.has_stylebox(&"hover_pressed", &"Button"),
		"the engine states nothing for a Button's press-while-hovered, which is the whole reason for this",
	)
	for kind: StringName in TouchStyleScript.BUTTON_KINDS:
		var pressed := theme.get_stylebox(&"pressed", kind) as StyleBoxFlat
		var hovered := theme.get_stylebox(&"hover_pressed", kind) as StyleBoxFlat
		if pressed == null:
			assert(hovered == null, "%s's press draws nothing, and this says nothing beside it" % kind)
			continue
		assert(hovered != null, "%s states its press-while-hovered too" % kind)
		assert(hovered.bg_color == pressed.bg_color, "%s: one fill under both names" % kind)
		assert(hovered.border_color == pressed.border_color, "%s: and one border" % kind)
		assert(hovered.draw_center, "%s: with the fill really drawn, which the fallback box does not do" % kind)
		assert(
			hovered.corner_radius_top_left == pressed.corner_radius_top_left,
			"%s: and the engine's own corners rather than a fallback box's" % kind,
		)


## A stylebox in this program is **layout**: a page's padding is read off the box it draws with, the room
## arithmetic subtracts it, and the audit measures a page's contents against its panel. So every box here is
## the engine's own for that state, duplicated and recoloured, and this holds that nothing but a colour moved -
## which is what lets a styling pass be trusted not to have moved a fit.
##
## A kind whose states are **icons** rather than fills is left completely alone, and that is held here too: a
## `CheckBox`'s tick is what says whether it is on, so a painted press would be a second answer to a question
## the engine already draws.
func test_every_box_keeps_the_engines_geometry_and_changes_only_its_colour() -> void:
	var theme: Theme = TouchStyleScript.build()
	var defaults: Theme = ThemeDB.get_default_theme()
	var painted := 0
	var left_alone := 0
	for kind: StringName in TouchStyleScript.BUTTON_KINDS:
		for state: StringName in _states:
			# A press is one box drawn under two names, so the press-while-hovered state is held to the
			# engine's own *pressed* box rather than to one it never states: what a lookup falls back to for
			# `hover_pressed` is a box that draws no centre, which is the fault measured on the glass.
			var like: StringName = &"pressed" if state == &"hover_pressed" else state
			# Both sides are read the way a control reads them, so a state the engine resolves through the
			# type chain is compared against the same resolution rather than against an absence.
			var theirs := defaults.get_stylebox(like, kind) as StyleBoxFlat
			var mine := theme.get_stylebox(state, kind) as StyleBoxFlat
			if theirs == null:
				# A `StyleBoxEmpty`: the engine states the item and draws nothing for it, because the answer
				# is an icon - a `CheckBox`'s tick. No fill is invented for it, which is held here.
				assert(
					mine == null,
					"%s %s draws nothing, so nothing is drawn for it here either" % [kind, state],
				)
				left_alone += 1
				continue
			assert(mine != null, "%s %s is repainted" % [kind, state])
			assert(_same_geometry(mine, theirs), "%s %s keeps the engine's margins, borders and corners" % [kind, state])
			assert(
				mine.bg_color != theirs.bg_color or mine.border_color != theirs.border_color,
				"%s %s is actually repainted" % [kind, state],
			)
			painted += 1
	# `Button`, `OptionButton` and `MenuButton` each paint a fill in all three states, and a `CheckBox` and a
	# `CheckButton` paint none - so the floor is nine, and the kinds left alone are real rather than skipped.
	assert(painted == 9, "every kind that paints a fill was repainted in all three states: %d" % painted)
	assert(left_alone == 6, "and the two icon kinds were left entirely alone: %d" % left_alone)


## A disabled button was painted **identically** to a live one - same fill, same border, only a dimmer label.
## On a phone nothing hovers first, so there was no way to see it coming.
func test_a_control_that_cannot_be_pressed_no_longer_reads_as_a_live_one() -> void:
	var theme: Theme = TouchStyleScript.build()
	var defaults: Theme = ThemeDB.get_default_theme()
	var live := defaults.get_stylebox(&"normal", &"Button") as StyleBoxFlat
	var engine_dead := defaults.get_stylebox(&"disabled", &"Button") as StyleBoxFlat
	assert(
		engine_dead.border_color == live.border_color,
		"the engine paints a dead button with a live one's border, which is the fault",
	)
	assert(
		engine_dead.bg_color.to_html(false) == live.bg_color.to_html(false),
		"and with a live one's own colour, so only the words tell the two apart over this program's panels",
	)
	var dead := theme.get_stylebox(&"disabled", &"Button") as StyleBoxFlat
	assert(
		dead.bg_color.get_luminance() < live.bg_color.get_luminance(),
		"this one is painted with a quieter fill than a live control: %.3f against %.3f"
		% [dead.bg_color.get_luminance(), live.bg_color.get_luminance()],
	)
	assert(
		dead.border_color == live.border_color,
		"and the border is left exactly as the engine draws it, because a `Button`'s boxes have none to dim",
	)
	var words: Color = theme.get_color(&"font_color_disabled", &"Button")
	assert(
		words.get_luminance() < defaults.get_color(&"font_color", &"Button").get_luminance(),
		"and words dimmer than a live control's",
	)


## The theme is put on the application's root and nowhere else, and this drives the lookup a **real control**
## makes rather than trusting that a theme is inherited - because a `CheckBox` and an `OptionButton` are
## `Button`s underneath while having theme entries of their own, and which way that chain is walked is exactly
## the sort of thing that is true until it is not.
func test_what_a_real_control_resolves_is_what_this_program_states() -> void:
	var holder := Control.new()
	add_child(holder)
	_made.append(holder)
	holder.theme = TouchStyleScript.build()
	var defaults: Theme = ThemeDB.get_default_theme()
	for control: Control in [Button.new(), OptionButton.new(), MenuButton.new()]:
		holder.add_child(control)
		var kind: StringName = StringName(control.get_class())
		var pressed := control.get_theme_stylebox(&"pressed") as StyleBoxFlat
		assert(pressed != null, "%s resolves a press" % kind)
		assert(
			pressed.bg_color == TouchStyleScript.PRESSED_BG,
			"%s draws the press this program states: %s" % [kind, pressed.bg_color.to_html(false)],
		)
		var rest := control.get_theme_stylebox(&"normal") as StyleBoxFlat
		var theirs := defaults.get_stylebox(&"normal", kind) as StyleBoxFlat
		assert(
			rest != null and theirs != null and rest.bg_color == theirs.bg_color,
			"%s keeps the engine's own rest state, which this program says nothing about" % kind,
		)
	var check := CheckBox.new()
	holder.add_child(check)
	var box := check.get_theme_stylebox(&"pressed")
	assert(
		not (box is StyleBoxFlat),
		"a CheckBox still draws the engine's own empty box - its tick is what says it is on: %s" % box.get_class(),
	)
	_free_made()


## **A `CanvasLayer` stops the theme walk, and that is why this program wears its style on two carriers rather
## than on the tree's root.** Measured, not supposed - it corrected where the style was first put: the tree's
## root reaches nothing inside this program's HUD, because the HUD *is* a `CanvasLayer`. A control inside the
## layer, and a page `Window` beside the board's `Root`, both resolve it, which is the whole of the arrangement
## `hud.gd` and `page_chrome.gd` make.
func test_a_canvas_layer_stops_the_theme_walk() -> void:
	var engine_press: Color = (
		(ThemeDB.get_default_theme().get_stylebox(&"pressed", &"Button") as StyleBoxFlat).bg_color
	)
	# An application root of this file's own, rather than the test runner's, so that no other test in the run
	# is answered by whatever this one leaves behind.
	var app := Window.new()
	app.visible = true
	add_child(app)
	_made.append(app)
	app.theme = TouchStyleScript.build()

	var layer := CanvasLayer.new()
	app.add_child(layer)
	var carrier := Control.new()
	layer.add_child(carrier)
	var under_it := Button.new()
	carrier.add_child(under_it)
	var page := Window.new()
	page.visible = true
	layer.add_child(page)
	var on_the_page := Button.new()
	page.add_child(on_the_page)

	assert(
		(under_it.get_theme_stylebox(&"pressed", &"Button") as StyleBoxFlat).bg_color == engine_press,
		"a theme on the window above the layer does not cross it: the fault this placement was cured of",
	)

	assert(TouchStyleScript.apply_to(carrier), "the board's own `Root` control is a carrier")
	assert(TouchStyleScript.apply_to(page), "and so is a page")
	assert(
		(under_it.get_theme_stylebox(&"pressed", &"Button") as StyleBoxFlat).bg_color == TouchStyleScript.PRESSED_BG,
		"a button under the control inside the layer now wears the program's press",
	)
	assert(
		(on_the_page.get_theme_stylebox(&"pressed", &"Button") as StyleBoxFlat).bg_color
		== TouchStyleScript.PRESSED_BG,
		"and so does a button on a page beside it",
	)
	_free_made()


## What the style is worn *by*: a page `Window` and a `Control` are carriers, a plain `Node` is refused rather
## than quietly doing nothing, and a carrier that already wears a theme keeps it - which is what makes a page
## landing again on every change of the room's shape cost nothing.
func test_a_carrier_takes_the_style_a_plain_node_is_refused_and_a_worn_theme_is_kept() -> void:
	var window := Window.new()
	window.visible = true
	add_child(window)
	_made.append(window)
	assert(TouchStyleScript.apply_to(window), "a page Window is a carrier")
	assert(window.theme != null, "and keeps the theme it is given")
	assert(window.theme.has_stylebox(&"pressed", &"Button"), "with the press stated in it")
	assert(
		not window.theme.has_stylebox(&"normal", &"Button"),
		"and nothing said about the rest state to argue with the engine's",
	)
	var worn: Theme = window.theme
	assert(TouchStyleScript.apply_to(window), "handing the same carrier the style again answers the same")
	assert(window.theme == worn, "and leaves the theme it already wears alone rather than building a fresh one")

	var holder := Control.new()
	add_child(holder)
	_made.append(holder)
	assert(TouchStyleScript.apply_to(holder), "a Control is a carrier too - it is what the board's Root is")
	assert(holder.theme != null, "and keeps it")

	var plain := Node.new()
	assert(not TouchStyleScript.apply_to(plain), "a plain node has nowhere to wear a theme")
	plain.free()
	_free_made()


## Whether two boxes are the same shape: what they reserve around their contents, what they draw as a border,
## how round their corners are, how far they expand, and whether they antialias. A box that agrees on all of
## these cannot move a fit, whatever it is coloured.
func _same_geometry(mine: StyleBoxFlat, theirs: StyleBoxFlat) -> bool:
	return (
		mine.content_margin_left == theirs.content_margin_left
		and mine.content_margin_right == theirs.content_margin_right
		and mine.content_margin_top == theirs.content_margin_top
		and mine.content_margin_bottom == theirs.content_margin_bottom
		and mine.border_width_left == theirs.border_width_left
		and mine.border_width_right == theirs.border_width_right
		and mine.border_width_top == theirs.border_width_top
		and mine.border_width_bottom == theirs.border_width_bottom
		and mine.corner_radius_top_left == theirs.corner_radius_top_left
		and mine.corner_radius_top_right == theirs.corner_radius_top_right
		and mine.corner_radius_bottom_right == theirs.corner_radius_bottom_right
		and mine.corner_radius_bottom_left == theirs.corner_radius_bottom_left
		and mine.expand_margin_left == theirs.expand_margin_left
		and mine.expand_margin_right == theirs.expand_margin_right
		and mine.expand_margin_top == theirs.expand_margin_top
		and mine.expand_margin_bottom == theirs.expand_margin_bottom
		and mine.anti_aliasing == theirs.anti_aliasing
	)


func _free_made() -> void:
	for node: Node in _made:
		node.free()
	_made.clear()