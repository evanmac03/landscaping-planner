extends Node
## A dev tool: the two GUI-sensing instruments, shown on the fault they were written for.
##
## It opens the figures page on the real game and reports what is *drawn* twice: once with the strip the HUD
## states (`PageChrome.reserved_above`, the foot of its own bar), and once with that strip taken away - which
## is the state a page's title bar was drawn over the menu titles in. The page lands below the bar in the
## first case and the instrument says nothing meets anything it may not; in the second it is placed exactly as
## it was before the fix and the instrument names the fault, with the rows and columns the two share.
##
## Nothing on disk changes and nothing stays changed: the strip is put back and every page put up is placed
## again before the tool ends. Run it with run_scene and read the console:
##     res://tools/gui_sense_demo.tscn

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const HudProbeScript := preload("res://scripts/hud_probe.gd")
const PageChromeScript := preload("res://scripts/page_chrome.gd")
const DrawnSurfacesScript := preload("res://scripts/drawn_surfaces.gd")

## The HUD method that opens the page under test - the same one `page_chrome_probe` uses.
const OPEN := "open_analytics_window"

## The door the HUD itself uses to put back a page whose room changed shape. It is private and is reached by
## name on purpose: this tool is showing the same path a turn of a phone takes, and a public copy of it would
## be a second door that could disagree with the first.
const REPLACE := "_the_canvas_changed_shape"


func _ready() -> void:
	var main: Node = MainScene.instantiate()
	add_child(main)
	for _i: int in 40:
		await get_tree().process_frame
	var hud: Node = main.get_node_or_null("Hud")
	if hud == null:
		print("DEMO no Hud")
		return
	hud.call(OPEN)
	for _i: int in 20:
		await get_tree().process_frame
	var page: Window = _the_page(hud)
	if page == null:
		print("DEMO no page came up")
		return
	await _report("as it stands, with the strip the HUD states", hud, page)
	var stated: int = PageChromeScript.reserved_above
	PageChromeScript.reserved_above = 0
	hud.call(REPLACE)
	for _i: int in 10:
		await get_tree().process_frame
	await _report("with the strip taken away, which is where the fault lived", hud, page)
	PageChromeScript.reserved_above = stated
	hud.call(REPLACE)
	for _i: int in 10:
		await get_tree().process_frame
	print("")
	print("DEMO the strip is %d again, and the page is below the bar once more." % stated)


## What the instruments say about the page as it stands: where it landed, the bar at the top of the screen,
## everything that is drawn, and the run of colour above the page read off the glass.
func _report(title: String, hud: Node, page: Window) -> void:
	print("")
	print("=== %s ===" % title)
	print("  PageChrome.reserved_above = %d" % PageChromeScript.reserved_above)
	print("  the page stands at %s size %s" % [page.position, page.size])
	var surfaces: Array = hud.call("drawn_surfaces")
	print("  %d rectangles on the screen, each measured by the module that owns it:" % surfaces.size())
	for surface: Dictionary in surfaces:
		if StringName(surface["kind"]) == DrawnSurfacesScript.TOP_BAR:
			print("  the top bar is %s" % str(surface["rect"]))
	for line: String in HudProbeScript.meeting_lines(surfaces):
		print("  " + line)
	await RenderingServer.frame_post_draw
	for line: String in HudProbeScript.drawn_bar_lines(page, get_viewport().get_texture().get_image()):
		print("  " + line)


## The page the HUD just put up: the visible Window it holds.
func _the_page(hud: Node) -> Window:
	for node: Node in hud.get_children():
		var page: Window = node as Window
		if page != null and page.visible:
			return page
	return null
