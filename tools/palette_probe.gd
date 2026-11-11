extends Node
## Why the palette is as wide as it is on a phone, and which of its rows is the reason.
##
## A development tool rather than part of the game. It does what `tools/phone_hud_demo.gd` does - states the
## readings a phone would give instead of pretending to be one - and then walks the palette's own column,
## printing the width every row asks for. The palette is the one panel whose width is decided at run time
## rather than in the scene, and on the glass it took half the canvas, so the arithmetic needs a place where
## it can be read rather than inferred from a screenshot.
##
## Run `res://tools/palette_probe.tscn` and read the console. To read a *device's* own answer rather than
## this tool's stated phone, point `application/run/main_scene` at it for one build: `tools/` is excluded
## from every export, so the scene has to be run as the main scene to reach glass. The `DEVICE` line then
## says whether the device agreed with the reading the tool states - on the phone this was written for it
## does, and the report below is that phone's own.

const PhoneHudScript := preload("res://scripts/phone_hud.gd")
const TouchInputScript := preload("res://scripts/touch_input.gd")

## The phone this program is aimed at: 2340 x 1080 on a 6.7 inch screen. `PHONE_SCALE` is that screen's
## physical pixels per logical one, which is the number the fonts are worked out from - stated here because
## a desk window is drawn at its own scale and would otherwise answer a different phone's question.
const PHONE_DPI := 450.0
const PHONE_SCALE := 1.62

var _app: Node = null


func _ready() -> void:
	# What the machine says about itself, read before it is told what to say: on a desktop this is a desk's
	# answer and the numbers below are a phone's, and the two lines together are what show the difference.
	var own_scale: float = PhoneHudScript.canvas_scale(get_window())
	print("DEVICE dpi=%.0f touchscreen=%s canvas_scale=%.2f row=%.1f font=%d" % [
		PhoneHudScript.dpi(), str(TouchInputScript.has_a_touchscreen()), own_scale,
		PhoneHudScript.row_height(own_scale, PhoneHudScript.dpi()),
		PhoneHudScript.font_size(own_scale, PhoneHudScript.dpi()),
	])
	PhoneHudScript.force_density(PHONE_DPI)
	TouchInputScript.force(TouchInputScript.Answer.FINGER)
	PhoneHudScript.apply_if(get_window(), true)
	_app = load("res://scenes/main.tscn").instantiate()
	_app.name = "App"
	add_child(_app)
	# The palette's finger pass is deferred twice, so the row is re-flowed and the panel grown over three
	# frames: read before those and every number is the frame before's.
	for i in 8:
		await get_tree().process_frame
	_report()
	# And sized again, which is what happens every time the palette is put on the screen. If the panel comes
	# back wider, the room it fits its rows into is the width a row before it grew the panel to.
	var hud: Node = _find_scripted(_app, "hud.gd")
	if hud != null:
		hud._size_palette_for_a_finger()
		for i in 5:
			await get_tree().process_frame
		print("")
		print("--- sized a second time, as it is every time the palette is shown ---")
		_report()
	PhoneHudScript.force_density(0.0)
	TouchInputScript.force(TouchInputScript.Answer.AUTO)
	await get_tree().process_frame
	get_tree().quit(0)


## The palette's own numbers, and every row inside it that could be asking for the width.
func _report() -> void:
	var hud: Node = _find_scripted(_app, "hud.gd")
	if hud == null:
		print("PALETTE: no HUD in main.tscn")
		return
	var palette: Control = hud.palette
	var column: Control = hud.palette_column
	if palette == null or column == null:
		print("PALETTE: the HUD has no palette")
		return
	var canvas: Vector2 = get_window().get_visible_rect().size
	print("canvas            %d x %d, drawn up by %.2f" % [
		int(canvas.x), int(canvas.y), get_window().content_scale_factor,
	])
	print("palette panel     %s = %.0f%% of the canvas width" % [
		str(palette.get_rect()), 100.0 * palette.get_rect().size.x / canvas.x,
	])
	print("  panel floor     %s (what it asks for itself)" % str(palette.custom_minimum_size))
	print("  panel room      %.0f (what its anchors say it was designed at)" % hud._palette_room())
	print("  column minimum  %s" % str(column.get_combined_minimum_size()))
	# Each row's buttons are then re-measured at the font a phone's screen asks for, so the numbers below are
	# the phone's own rather than this window's - that is the one thing a desk cannot borrow.
	print("  (each row re-measured at a phone's font: %d px)" % PhoneHudScript.font_size(
		PHONE_SCALE, PHONE_DPI
	))
	for row: Node in column.get_children():
		var control: Control = row as Control
		if control == null:
			continue
		var grid: GridContainer = control as GridContainer
		if grid != null:
			# The shape of that row's own cell widths, at each column count it could be given: what a
			# palette with a cap on its width would have to choose between.
			_measure_at_a_phones_font(grid)
			print("    row %-18s %6.0f wide, %6.0f tall, %d column(s) chosen" % [
				String(grid.name),
				grid.get_combined_minimum_size().x,
				grid.get_combined_minimum_size().y,
				grid.columns,
			])
		else:
			print("    row %-18s %6.0f wide, %6.0f tall" % [
				String(control.name),
				control.get_combined_minimum_size().x,
				control.get_combined_minimum_size().y,
			])
			# And what is inside the row that asks for that width. A row's minimum is the SUM of its
			# controls unless it wraps, and where it wraps it is the widest single control - so the
			# control named here is the one a wrapped row would ask for instead of the sum.
			for child: Node in control.get_children():
				var kid: Control = child as Control
				if kid == null:
					continue
				print("      %-22s %6.0f wide%s" % [
					String(kid.name),
					kid.get_combined_minimum_size().x,
					"" if not (kid is Container) or kid.get_child_count() == 0
						else ", holding %d control(s)" % kid.get_child_count(),
				])
	print("PALETTE: measured")


## Give every button in a grid the font a phone's screen asks for and print what the grid would then need at
## one, two, three and four columns.
func _measure_at_a_phones_font(grid: GridContainer) -> void:
	var widths: Array[float] = []
	var words: Array[String] = []
	for child: Node in grid.get_children():
		var button: Button = child as Button
		if button == null:
			continue
		PhoneHudScript.size_for_a_finger(button, PHONE_SCALE, PHONE_DPI)
		widths.append(PhoneHudScript.button_width(button))
		words.append("%s %.0f" % [button.text, PhoneHudScript.button_width(button)])
	if widths.is_empty():
		return
	var separation: float = float(grid.get_theme_constant(&"h_separation"))
	var out: Array[String] = []
	for columns: int in [1, 2, 3, 4]:
		var per_column: Array[float] = []
		for c in columns:
			per_column.append(0.0)
		for i in widths.size():
			per_column[i % columns] = maxf(per_column[i % columns], widths[i])
		var total: float = separation * float(columns - 1)
		for width: float in per_column:
			total += width
		out.append("%d col %.0f" % [columns, total])
	print("        %s" % "  |  ".join(out))
	print("        %s" % "  |  ".join(words))


## The first node under the app carrying a given script, found by the script rather than by a node path
## that a scene edit would move out from under this tool.
func _find_scripted(root: Node, file: String) -> Node:
	for node: Node in root.find_children("*", "", true, false):
		var script: Script = node.get_script()
		if script != null and String(script.resource_path).ends_with(file):
			return node
	return null