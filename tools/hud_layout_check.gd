extends Node

## A dev tool: instance the real game, then measure every HUD panel's on-screen rectangle and report
## which ones meet. The panels are laid out by anchors and by their own contents, so the only honest
## way to know whether they collide is to let the engine lay them out and read the rectangles back.
##
## Run it with run_scene and read the console:
##     res://tools/hud_layout_check.tscn

const MAIN := preload("res://scenes/main.tscn")

const PANELS: Array[String] = [
	"TopBar", "Hints", "DraftHints", "Palette", "Presentation", "PaintedSheet",
	"KeysPanel", "SiteReportPanel", "SurveyPanel", "DxfPanel",
	"HatchPanel", "WaterPanel", "LightPanel", "PlantWindow",
]

## Panels that are on screen with nothing opened: a collision with one of these is one a person sees.
const ALWAYS: Array[String] = ["TopBar", "Hints", "Presentation"]

## Full-screen modes: they cover the drawing on purpose, so they are measured but never called a clash.
const OVERLAY_MODE: Array[String] = ["PaintedSheet"]

## Panels built as a full-rect centering wrapper: the wrapper is a transparent, click-through device
## that spans the screen, so measuring it would report a clash with everything. Measure the page inside.
const PAGE_OF: Dictionary = {
	"KeysPanel": "Page", "SiteReportPanel": "Page", "SurveyPanel": "Page", "DxfPanel": "Page",
	"HatchPanel": "Page", "WaterPanel": "Page", "LightPanel": "Page",
}


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	for i in 5:
		await get_tree().process_frame
	var root: Control = main.get_node_or_null(^"Hud/Root") as Control
	if root == null:
		print("LAYOUT: no Hud/Root")
		return
	# The Hud rewrites panel visibility every frame; stop it so a forced panel stays forced.
	var hud: Node = main.get_node_or_null(^"Hud")
	if hud != null:
		hud.set_process(false)
		hud.set_process_input(false)

	print("=== HUD LAYOUT (viewport %d x %d) ===" % [int(root.size.x), int(root.size.y)])

	var measured: Dictionary = {}
	var shown: Dictionary = {}
	for panel_name in PANELS:
		var node: Control = root.get_node_or_null(NodePath(panel_name)) as Control
		if node == null:
			print("  %-16s -" % panel_name)
			continue
		var was: bool = node.visible
		node.visible = true
		await get_tree().process_frame
		# A centering wrapper is measured through to its page; everything else is measured as it stands.
		var page: Control = node
		if PAGE_OF.has(panel_name):
			page = node.get_node_or_null(NodePath(String(PAGE_OF[panel_name]))) as Control
			if page == null:
				page = node
		var r: Rect2 = page.get_global_rect()
		node.visible = was
		measured[panel_name] = r
		shown[panel_name] = was
		print("  %-16s x %7.1f .. %-7.1f  y %7.1f .. %-7.1f   (%s)" % [
			panel_name, r.position.x, r.end.x, r.position.y, r.end.y,
			"on by default" if was else "opened from a menu",
		])

	var top_bar: Control = root.get_node_or_null(^"TopBar") as Control
	var row: Control = root.get_node_or_null(^"TopBar/Row") as Control
	if top_bar != null and row != null:
		var wants: float = row.get_combined_minimum_size().x
		print("  TopBar row wants %.1f px, panel is %.1f px  ->  %s" % [
			wants, top_bar.size.x,
			"FITS" if wants <= top_bar.size.x else "OVERFLOWS BY %.1f px" % (wants - top_bar.size.x),
		])

	print("--- panel rectangles that meet ---")
	var names: Array = measured.keys()
	var clashes := 0
	var touching := 0
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a: String = names[i]
			var b: String = names[j]
			var ra: Rect2 = measured[a]
			var rb: Rect2 = measured[b]
			if not ra.intersects(rb):
				continue
			if a in OVERLAY_MODE or b in OVERLAY_MODE:
				continue
			var live: bool = (a in ALWAYS) or (b in ALWAYS)
			if live:
				clashes += 1
			else:
				touching += 1
			print("  %-14s x %-14s   %s" % [
				a, b, "BOTH CAN BE UP -> a real clash" if live else "not up at the same time",
			])
	if clashes == 0:
		print("  no clash with a panel that is always on screen")
	if touching > 0:
		print("  (%d further pairs that cannot be open together)" % touching)

	# Leave the drafting state on screen so the capture shows the panels the check is about.
	var draft_hints: Control = root.get_node_or_null(^"DraftHints") as Control
	if draft_hints != null:
		draft_hints.visible = true
	for i in 3:
		await get_tree().process_frame
	print("=== END LAYOUT ===")