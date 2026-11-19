extends Node
## The one owner of the HUD's chrome plates: `scripts/chrome_style.gd` builds the plate a phone's bar wears
## where the scene's own is pushed clear of a camera band, and **derives it from the plate the scene drew**.
##
## These tests exist because that derivation is exactly the shape of fault this project works hardest to avoid:
## two statements of one colour, one corner radius or one inset, drifting apart until a phone's bar is a subtly
## different pane from a desk's. The first test holds the scene's plate and this file's declared numbers
## together, so a change made to one and not the other fails here rather than on the glass; the rest fix what the
## phone's plate must be - the scene's look, the row's own inset, and a rule wide enough to survive the
## anti-aliasing that erased the first version of it.

const ChromeStyleScript := preload("res://scripts/chrome_style.gd")

## The top inset a lifted bar hands the plate: a row starting below the 110 px band a phone keeps.
const LIFTED_BY := 131.0


## The plate the scene draws, and the numbers this file states for the case it cannot read one. They are the same
## look, and this is the only thing in the project that says so.
func test_the_scenes_plate_is_the_look_this_file_states() -> void:
	var drawn: StyleBoxFlat = _the_scenes_plate()
	assert(drawn != null, "the HUD's scene draws a flat plate for its own bar")
	assert(drawn.bg_color == ChromeStyleScript.PAPER, "and it is the paper this file states: %s" % str(drawn.bg_color))
	assert(
		drawn.corner_radius_top_left == ChromeStyleScript.CORNER
		and drawn.corner_radius_top_right == ChromeStyleScript.CORNER
		and drawn.corner_radius_bottom_right == ChromeStyleScript.CORNER
		and drawn.corner_radius_bottom_left == ChromeStyleScript.CORNER,
		"and the same corner on all four",
	)
	assert(
		is_equal_approx(drawn.content_margin_left, ChromeStyleScript.SIDE)
		and is_equal_approx(drawn.content_margin_right, ChromeStyleScript.SIDE),
		"and the same inset down the sides",
	)
	assert(
		is_equal_approx(drawn.content_margin_bottom, ChromeStyleScript.FOOT),
		"and the same inset at the foot",
	)


## What a phone's bar wears: the scene's own look, with the row pushed down by the number handed in.
func test_the_phone_plate_is_the_scenes_look_with_the_row_lifted() -> void:
	var drawn: StyleBoxFlat = _the_scenes_plate()
	var plate: StyleBox = ChromeStyleScript.bar_plate(drawn, LIFTED_BY)
	assert(
		is_equal_approx(plate.content_margin_top, LIFTED_BY),
		"the row is lifted by the number handed in, not by this file's own idea of it: %s" % str(plate.content_margin_top),
	)
	assert(
		is_equal_approx(plate.content_margin_left, drawn.content_margin_left)
		and is_equal_approx(plate.content_margin_bottom, drawn.content_margin_bottom),
		"and the sides and the foot are the scene's",
	)
	var ink: Color = plate.get(&"color")
	assert(ink == drawn.bg_color, "and the paper is the scene's: %s" % str(ink))
	var corner: int = plate.get(&"corner_radius_top_left")
	assert(corner == drawn.corner_radius_top_left, "and it keeps the scene's corner: %d" % corner)
	assert(
		plate.get_script() == ChromeStyleScript.FancyScript,
		"and the plate is the addon's own stylebox, which is the only one here that can stack a rule",
	)


## **A rule narrower than the anti-aliasing draws nothing at all**, which is what the first plate did: in the
## addon's anti-aliased path the ring that reaches the glass is the border's own width less the anti-aliasing's
## width, so a one-pixel hairline leaves the two rects coincident and the ring is dropped.
func test_the_rule_is_wider_than_the_anti_aliasing_that_would_erase_it() -> void:
	var plate: StyleBox = ChromeStyleScript.bar_plate(_the_scenes_plate(), LIFTED_BY)
	var rules: Array = plate.get(&"borders")
	assert(rules.size() == 1, "the plate wears one rule: %d" % rules.size())
	if rules.size() != 1:
		return
	var rule: Variant = rules[0]
	var aa: float = plate.get(&"anti_aliasing_size")
	assert(
		float(rule.width_left) - aa > 0.0 and float(rule.width_bottom) - aa > 0.0,
		"and every side of it survives the anti-aliasing: %s wide against %s" % [str(rule.width_left), str(aa)],
	)


## **Two bars do not share one plate.** The scene gives its bar, its palette and its hint plates the *same*
## sub-resource, so a lift that grew a plate in place would push the contents of all of them at once; the phone's
## plate is a new stylebox precisely so that covering the bar cannot move anything else.
func test_covering_the_bar_does_not_move_the_panels_that_share_the_scenes_plate() -> void:
	var drawn: StyleBoxFlat = _the_scenes_plate()
	var was_side: float = drawn.content_margin_left
	var was_top: float = drawn.content_margin_top
	var one: StyleBox = ChromeStyleScript.bar_plate(drawn, LIFTED_BY)
	var two: StyleBox = ChromeStyleScript.bar_plate(drawn, LIFTED_BY)
	assert(one != two, "each lift is a stylebox of its own")
	assert(two != drawn, "and never the scene's own plate")
	assert(
		is_equal_approx(drawn.content_margin_left, was_side)
		and is_equal_approx(drawn.content_margin_top, was_top),
		"and the plate it was derived from is left exactly as it was",
	)


## The scene's own bar plate, read off a tree of its own that is freed again - a test about a scene loads one.
## The plate is duplicated before the free so the numbers survive the node, and it is a reading either way.
func _the_scenes_plate() -> StyleBoxFlat:
	var scene: PackedScene = load("res://scenes/ui/hud.tscn")
	assert(scene != null, "the HUD's scene is the file the HUD's own name resolves to")
	var board: Node = scene.instantiate()
	var bar: Node = board.get_node_or_null("Root/TopBar")
	var plate: StyleBox = null if bar == null else bar.get_theme_stylebox(&"panel")
	var out: StyleBoxFlat = null
	if plate is StyleBoxFlat:
		out = (plate as StyleBoxFlat).duplicate() as StyleBoxFlat
	board.free()
	return out
