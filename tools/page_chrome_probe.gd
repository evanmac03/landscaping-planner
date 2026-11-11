extends Node
## A dev tool: opens a page and reports where its window and its chrome actually landed on the screen.
##
## The point is the title bar. Godot draws an embedded window's title bar itself, and a page whose contents
## want the whole screen has to lose something - the title bar is what this measures. The framebuffer is
## read rather than the window's own numbers, because the window's numbers were right while the picture was
## wrong: `size` read the clamped floor and `position` read a centred page, and the title bar was still off
## the top of the screen.

const MainScene: PackedScene = preload("res://scenes/main.tscn")

## The HUD method that opens the page under test.
const OPEN := "open_analytics_window"


func _ready() -> void:
	var main: Node = MainScene.instantiate()
	add_child(main)
	for _i: int in 40:
		await get_tree().process_frame
	var hud: Node = main.get_node_or_null("Hud")
	if hud == null:
		print("PROBE no Hud")
		return
	hud.call(OPEN)
	for _i: int in 20:
		await get_tree().process_frame
	var page: Window = _the_page(hud)
	if page != null:
		print("PROBE pos=%s size=%s room=%s title_height=%d contents=%s" % [
			page.position, page.size, PageChrome.room_for(page),
			page.get_theme_constant(&"title_height", &"Window"), page.get_contents_minimum_size(),
		])
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	print("PROBE screen %dx%d" % [img.get_width(), img.get_height()])
	_runs(img, floori(img.get_width() / 2.0))


## The page the HUD just put up: the visible Window it holds.
func _the_page(hud: Node) -> Window:
	for node: Node in hud.get_children():
		var page: Window = node as Window
		if page != null and page.visible:
			return page
	return null


## The colours down one column, so a title bar and a content area are told apart by what is drawn.
func _runs(img: Image, x: int) -> void:
	var last: Color = img.get_pixel(x, 0)
	var start: int = 0
	for y: int in range(1, img.get_height()):
		var c: Color = img.get_pixel(x, y)
		if absf(c.r - last.r) + absf(c.g - last.g) + absf(c.b - last.b) > 0.02:
			print("  y %4d..%4d  %s" % [start, y - 1, last.to_html(false)])
			start = y
			last = c
	print("  y %4d..%4d  %s" % [start, img.get_height() - 1, last.to_html(false)])