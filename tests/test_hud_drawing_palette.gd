extends Node
## The HUD's own side of the **drawing** palette: the one member it reads the scene's `PaletteColumn`
## into, and that the scene really carries the node that name resolves to.
##
## Not to be confused with `test_hud_palette.gd`, which is the *command* palette - the box of bar commands
## behind Ctrl+P. This is the panel beside the drawing, and these two tests exist because of a measured
## fault: `_build_palette` builds nothing unless `palette_column` is set, and every other use of it is
## null-guarded, so a second declaration standing beside it - the node's twin, left null - leaves the
## palette with no buttons at all and no check, no warning and no crash to say so. The palette is how a
## drawing is made, so the first test reads the file that names it and the second asks the scene itself
## for the node.


func test_the_hud_declares_one_palette_column_and_it_is_the_scenes_node() -> void:
	var board: String = FileAccess.get_file_as_string("res://scripts/hud.gd")
	assert(
		board.contains("@onready var palette_column: PalettePanelScript = %PaletteColumn"),
		"the palette's controls are read from the scene's own node, under the one name the HUD uses"
	)
	assert(
		not board.contains("palette_columnf"),
		"and nothing in the file goes by a name like it: a second one, left null, is how the palette came "
		+ "to have no buttons while every check still passed"
	)


func test_the_hud_scene_carries_the_node_that_name_resolves_to() -> void:
	var scene: PackedScene = load("res://scenes/ui/hud.tscn")
	assert(scene != null, "the HUD's scene is the file the code names it in")
	var board: Node = scene.instantiate()
	var column: Node = board.get_node_or_null("%PaletteColumn")
	assert(column != null, "the scene has a PaletteColumn for that name to find")
	var script: Script = null if column == null else column.get_script()
	assert(
		script != null and String(script.resource_path).ends_with("palette_panel.gd"),
		"and it carries the palette panel's own script, which is the class the member is typed as"
	)
	board.free()
