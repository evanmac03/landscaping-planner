extends Node
## The phone's furniture, held to the one rule a table of kinds can break: the tools it calls dimensions have to
## be tools this program has, or the `Dim` tab offers a row that opens nothing.

const TouchFurnitureScript := preload("res://scripts/touch_furniture.gd")
const PalettePanelScript := preload("res://scripts/palette_panel.gd")


## Every kind the furniture calls a dimension is a kind some drawing tool actually declares.
##
## The other half of the split is the reason this matters: a dimension kind mentioned nowhere in `DRAFTING_TOOLS`
## would put a button in the `Dim` tab that stands for no tool, and a tool whose kind is *both* categories would
## be offered in two tabs at once. Both are invisible in a table and both are a defect a person would meet.
func test_every_dimension_kind_is_a_tool_the_program_has() -> void:
	var kinds_in_use: Array = []
	for entry: Array in PalettePanelScript.DRAFTING_TOOLS:
		kinds_in_use.append(int(entry[2]))
	for kind: int in TouchFurnitureScript.DIMENSION_KINDS:
		assert(
			kinds_in_use.has(kind),
			"the dimension kind %d stands for a tool the palette builds: in use %s" % [kind, str(kinds_in_use)],
		)
	assert(TouchFurnitureScript.DIMENSION_KINDS.size() > 0, "and there is at least one dimension to put in that tab")
