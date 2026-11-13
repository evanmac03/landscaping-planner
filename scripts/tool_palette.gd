class_name ToolPalette
extends RefCounted
## Fitting the left-hand palette to the words it is drawn with: how many columns each of its grids can have,
## how wide its panel has to grow to hold them, and how big its buttons become for a finger.
##
## This is the **measuring** half of the palette and nothing else. It owns no control and holds no design
## state: every function here is handed the panel and the column it is about, and - where the answer depends
## on the device - the scale and the density rather than a window, so that a test can hold what a phone would
## be told without being one. `PageChrome.size_for_a_finger` is the same door on the other side of the program.
##
## Every rule below was *measured* on a phone rather than reasoned about, and the reason is kept beside the
## rule: the two-pass deferral, reading the anchors instead of the size, and growing rightward are each the
## answer to a frame that came out wrong.

const PhoneHudScript := preload("res://scripts/phone_hud.gd")

## The palette: three tools across, which is what makes it a palette rather than a
## list of nine, and a cell wide enough for the longest tool name on one line with
## its key underneath.
const PALETTE_COLUMNS := 3
## The room the palette's panel keeps around the column it holds, 12 px either side. A phone needs it named
## rather than written into a scene: the panel is widened from its own contents there, because the words
## on its buttons are bigger than the ones the desk's panel was drawn around.
const PALETTE_INSET := 24.0
const PALETTE_CELL_WIDTH := 86.0
## The editing commands share one row: they have one-word names, and the palette has
## to fit the whole column without widening the palette - which is centre-anchored, so
## growing it would walk the plant list out from under the clicks a person has learned.
## Six across at 50 keeps the column inside the width the panel already had.
const PALETTE_EDIT_COLUMNS := 6
const PALETTE_EDIT_CELL_WIDTH := 50.0
## The fewest columns a re-flowed grid may be given, whatever the room says. A grid's own minimum is
## `columns x cell`, so a floor of two is a floor on the *panel's* width: on a phone, where one tool's cell
## is 155 px, two across would hold the panel open at 310 when one per row is what fits. One is the honest
## answer - a palette squeezed to a single column is still a palette, and the alternative is a panel that
## takes the drawing.
const PALETTE_FEWEST_COLUMNS := 1


## Make every answering control in the palette big enough for a finger.
##
## Whether to fit at all is the caller's question, not this one's: the HUD asks the device and then hands the
## answer here as a scale and a density, which is why a computer never reaches this at all and a desk's
## palette is left exactly as the scene laid it out.
##
## One pass over the column rather than a call at each button: the palette's rows are made in five places, and
## a rule applied in five places is a rule that drifts.
static func fit(column: Node, drawn_at: float, density: float) -> void:
	if column == null:
		return
	for node: Node in column.find_children("*", "Button", true, false):
		var button: Button = node as Button
		if button != null:
			PhoneHudScript.size_for_a_finger(button, drawn_at, density)
	# A picker is as wide as its longest item by default, and one of the layers here is named "500-IRRIGATION"
	# while the one in use reads "Design": the layer picker stood 453 px wide for a word that fits in a third
	# of that. Turned off for **every** picker in the panel - the plant panel's tag, spacing, arrangement and
	# bed pickers included - because it is one rule about one kind of control. The popup is unaffected: it
	# still sizes itself to its contents when it opens.
	for node: Node in column.find_children("*", "OptionButton", true, false):
		var picker: OptionButton = node as OptionButton
		if picker != null:
			picker.fit_to_longest_item = false


## Give the row of drawing tools as many columns as the panel has room for, at the words they are drawn with.
##
## The tools are built three across - which is what makes the palette a palette rather than a list of ten -
## and the cell was the desk's 86 px whatever the words on it were, so on a phone "Aligned dim" at 155 px ran
## across its neighbour's cell and its last letter sat under the panel's edge. A cell is now `max(the words,
## the desk's cell)`, and the number of them comes from the room rather than from a constant: three on a desk,
## fewer wherever the words are larger.
##
## The caller defers both re-flows by a frame, for one reason: a control asked for a size it has not laid out
## yet answers the size it had before, and the fonts were changed in the pass before this one.
static func reflow_the_tool_row(panel: Control, column: Node, tool_buttons: Array) -> void:
	var grid: GridContainer = null
	if column != null:
		grid = column.get_node_or_null("Tools") as GridContainer
	if grid != null and not tool_buttons.is_empty():
		var widths: Array = []
		for made: Button in tool_buttons:
			widths.append(maxf(PhoneHudScript.button_width(made), PALETTE_CELL_WIDTH))
		var separation: float = float(grid.get_theme_constant(&"h_separation"))
		grid.columns = PhoneHudScript.columns_that_fit(
			widths,
			PALETTE_COLUMNS,
			room(panel) - PALETTE_INSET,
			separation,
			PALETTE_FEWEST_COLUMNS,
		)


## Give the row of edit buttons as many columns as its panel has room for.
##
## The buttons are built with a fixed number of columns and the words on them are whatever size the screen
## asks for, and the two were never compared. Measured at the theme's own 16 px, "Extend" is 64 px wide, so
## a cell needs 72: eight of them in six columns want 456 px of a panel that has 368, and the row was drawn
## wider than its panel on a computer before a thumb was ever considered. The count is measured from the
## words now, so the row has as many columns as fit - four on this desk, and fewer wherever the words are
## larger, which is what a phone asks for.
static func reflow_the_edit_row(panel: Control, column: Node, edit_buttons: Array) -> void:
	var tools: GridContainer = null
	if column != null:
		tools = column.get_node_or_null("EditTools") as GridContainer
	if tools != null and panel != null and not edit_buttons.is_empty():
		var widths: Array = []
		for made: Button in edit_buttons:
			widths.append(PhoneHudScript.button_width(made))
		var separation: float = float(tools.get_theme_constant(&"h_separation"))
		tools.columns = PhoneHudScript.columns_that_fit(
			widths,
			PALETTE_EDIT_COLUMNS,
			room(panel) - PALETTE_INSET,
			separation,
			PALETTE_FEWEST_COLUMNS,
		)


## How wide the palette panel is meant to be, from the scene that placed it.
##
## Asked of the anchors rather than of `panel.size.x`, because a control's size is only the size it was
## designed at once a layout pass has run, and these passes run before that: asked in the frame after the
## fonts change, the panel still reports the width of its own contents, which is how the desk's six edit
## columns were re-flowed to four. Anchors and offsets are what the scene wrote down, so they answer on the
## first frame and every frame after it.
static func room(panel: Control) -> float:
	if panel == null:
		return 0.0
	# The scene's own anchors and **nothing else** - never `panel.size.x`, which is the width the last
	# re-flow grew the panel to. Reading that back is a ratchet: it was measured doing it, the edit row going
	# from three columns to four on the second showing and four on every one after, because each pass read
	# the room the previous pass had widened the panel into. Anchors and offsets are what the scene wrote
	# down, so they answer the same on the first frame and on the hundredth.
	var across: float = panel.get_parent_area_size().x
	var left: float = panel.anchor_left * across + panel.offset_left
	var right: float = panel.anchor_right * across + panel.offset_right
	return maxf(right - left, 0.0)


## Widen the palette's panel to hold the column it carries.
##
## The words grew with the row, so the panel has to grow with the words: a column wider than the panel it
## sits in is drawn with its ends off the screen, which is how the phone showed "awing (0)" where
## "Drawing (0)" was. The panel keeps its left edge and takes the width its own contents ask for.
static func grow_to_its_contents(panel: Control, column: Node) -> void:
	if panel == null or column == null:
		return
	var wanted: float = column.get_combined_minimum_size().x
	if wanted > 0.0:
		# Rightward, because that is the way the panel was drawn: a control's default is to grow both ways,
		# and the phone drew its left-hand edge 24 px into the bezel that way.
		panel.grow_horizontal = Control.GROW_DIRECTION_END
		panel.custom_minimum_size.x = maxf(panel.custom_minimum_size.x, wanted + PALETTE_INSET)
