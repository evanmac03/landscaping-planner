extends Control
## A dev demo: one of this project's own scripts, in a CodeEdit, coloured by the tree_sitter_gd
## extension - the tree-sitter highlighter from tools/tree_sitter_highlighter.gd turned on real code.
##
##     res://tools/tree_sitter_editor_demo.tscn
##
## It needs the desktop library: on a device with none the header says so and the text is left plain,
## rather than colouring nothing and leaving a person to wonder why.

const Highlighter := preload("res://tools/tree_sitter_highlighter.gd")

## The script shown. A tidy one - a class, constants, static functions and doc comments - so every colour
## the highlighter knows is on the screen at once.
const SHOWN := "res://scripts/legibility.gd"


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)

	var column := VBoxContainer.new()
	margin.add_child(column)

	var header := Label.new()
	header.text = _header()
	column.add_child(header)

	var edit := CodeEdit.new()
	edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(edit)
	edit.text = FileAccess.get_file_as_string(SHOWN)
	if ClassDB.class_exists(&"GDScriptTreeSitter"):
		edit.syntax_highlighter = Highlighter.new()
		edit.syntax_highlighter.update_cache()


func _header() -> String:
	if ClassDB.class_exists(&"GDScriptTreeSitter"):
		return "tree-sitter GDScript highlighter - " + SHOWN + " (colours read from the parse tree)"
	return "tree_sitter_gd is not loaded on this device; the text is shown plain."
