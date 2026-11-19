extends Control

## Three panels side by side: the stylebox this project uses now, and two a StyleBoxFancy makes.
##
## A dev tool, not part of the program. It exists because "a panel with more borders" is not a picture:
## the only honest way to judge a StyleBox is to draw the same panel three ways and look, and the third
## one is the reason the addon exists at all - two borders stacked one inside the other, which
## `StyleBoxFlat` cannot do without a texture.
##
## Every property named here is read off the addon rather than guessed (`StyleBoxFancy.gd`'s own
## `@export`s): `color`, `corner_radius_*`, `corner_curvature_*` (1.0 round, 2.0 squircle, per its
## `Curvatures` table), `corner_detail`, `expand_margin_*`, `shadow_*`, and a `StyleBorder`'s `color`
## with its four `width_*`. The nodes are preloaded by path rather than by their global class names, so
## this runs whether or not a language server has registered them.
##
## The still is written by the program, so it needs no editor bridge - which matters, because a headless
## run of `execute_script` binds this project's runtime port and takes it from a real game session.

const FancyScript := preload("res://addons/StyleboxFancy/StyleBoxFancy.gd")
const BorderScript := preload("res://addons/StyleboxFancy/StyleBorder.gd")

const PAPER := Color(0.14, 0.15, 0.17)
const INK := Color(0.86, 0.88, 0.91)
const PANEL_SIZE := Vector2(430.0, 250.0)


func _ready() -> void:
	var paper := ColorRect.new()
	paper.color = PAPER
	add_child(paper)
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 30)
	add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	row.add_child(_a_panel("StyleBoxFlat - what this project uses now", _the_plain_one()))
	row.add_child(_a_panel("StyleBoxFancy - round corners, one border", _a_fancy_one(1.0, 1)))
	row.add_child(_a_panel("Squircle corners, two borders stacked", _a_fancy_one(2.0, 2)))

	for frame: int in 3:
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	var shot: Image = get_viewport().get_texture().get_image()
	var where: String = ProjectSettings.globalize_path("res://build/stylebox_fancy.png")
	var saved: int = shot.save_png(where)
	print(
		"STYLEBOX wrote %s (%dx%d): %s"
		% [where, shot.get_width(), shot.get_height(), "ok" if saved == OK else "SAVE FAILED %d" % saved]
	)
	get_tree().quit()


## A caption over a panel, so the three are told apart in the still without a key.
func _a_panel(caption: String, box: StyleBox) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)

	var label := Label.new()
	label.text = caption
	label.add_theme_color_override("font_color", INK)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(label)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = PANEL_SIZE
	panel.add_theme_stylebox_override("panel", box)
	column.add_child(panel)
	return column


## The program's current look, for comparison: one flat colour, one rounded rectangle.
func _the_plain_one() -> StyleBoxFlat:
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0.20, 0.21, 0.24)
	flat.set_corner_radius_all(14)
	flat.border_width_left = 1
	flat.border_width_top = 1
	flat.border_width_right = 1
	flat.border_width_bottom = 1
	flat.border_color = Color(0.32, 0.34, 0.38)
	return flat


## A StyleBoxFancy at a given corner curvature and border count.
##
## The two borders are the point: a 3 px light rule inset from the edge and a warmer one inside it, drawn
## one inside the other. `expand_margin_*` is what gives the shadow room, so the panel is not clipped.
func _a_fancy_one(curvature: float, border_count: int) -> StyleBox:
	var fancy: StyleBox = FancyScript.new()
	fancy.color = Color(0.20, 0.21, 0.24)
	fancy.corner_radius_top_left = 14
	fancy.corner_radius_top_right = 14
	fancy.corner_radius_bottom_right = 14
	fancy.corner_radius_bottom_left = 14
	fancy.corner_curvature_top_left = curvature
	fancy.corner_curvature_top_right = curvature
	fancy.corner_curvature_bottom_right = curvature
	fancy.corner_curvature_bottom_left = curvature
	fancy.corner_detail = 12
	fancy.shadow_enabled = true
	fancy.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	fancy.shadow_blur = 12

	# **Filled, not replaced.** `borders` is a typed `Array[StyleBorder]`, so assigning an array literal to
	# it is refused at run time - "Invalid assignment of property or key 'borders' with value of type
	# 'Array'" - which is what the first run of this demo printed for both fancy panels. Appending to the
	# array the stylebox already owns is what keeps it typed, and needs no class name spelled here.
	var outside: Variant = BorderScript.new()
	outside.color = Color(0.55, 0.58, 0.64)
	outside.width_left = 2
	outside.width_top = 2
	outside.width_right = 2
	outside.width_bottom = 2
	fancy.borders.append(outside)

	if border_count > 1:
		var inside: Variant = BorderScript.new()
		inside.color = Color(0.35, 0.62, 0.45)
		inside.width_left = 1
		inside.width_top = 1
		inside.width_right = 1
		inside.width_bottom = 1
		inside.ignore_stack = true
		fancy.borders.append(inside)

	print(
		"STYLEBOX fancy: curvature %s, %d border(s), %d corners at radius %d, detail %d"
		% [curvature, fancy.borders.size(), 4, fancy.corner_radius_top_left, fancy.corner_detail]
	)
	return fancy
