extends Node
## Throwaway: takes the manual's pictures off the real running program.
##
## The manual's pictures are the program itself, so they are *taken* rather than drawn: a shot of the
## real page, with the real drawing behind it, saved as a PNG the manual then points at by name. The
## camera is the viewport - whatever is on the screen at that moment is what a reader would be looking
## at - and nothing here is a mock-up of a screen.
##
## Run `res://scenes/help_shot.tscn`.

const MAIN := preload("res://scenes/main.tscn")
const ToolScript := preload("res://scripts/draft/draft_tool.gd")
## Where the manual's pictures live. Beside the program rather than with the specifications in `docs/`:
## `docs/` is not shipped, and these are files the program itself reads when a page is turned.
const OUT := "res://assets/help"
## How hard the lossy save is pressed. High enough that the small text on a page is still legible,
## which is the whole point of a picture of a page.
const QUALITY := 0.9
## Set to a subject's name to shoot the manual open on that subject instead of the full set. For looking
## at how a *page* carries its pictures, which a capture of the pages themselves cannot show. Empty for
## the real run.
const PROBE_SUBJECT := ""

var _hud: Node = null
var _view: ViewController = null
var _shots: Array[Dictionary] = []
var _at: int = 0
var _wait: int = 0
var _phase: int = 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var main: Node = MAIN.instantiate()
	add_child(main)
	_shots = _shot_list()


func _shot_list() -> Array[Dictionary]:
	if not PROBE_SUBJECT.is_empty():
		return [{"name": "probe", "do": "help"}]
	return [
		# The view the program opens on, and the other two views of the same garden.
		{"name": "view-overhead", "do": "none"},
		{"name": "view-plan", "do": "plan"},
		{"name": "view-ground", "do": "ground"},
		# The drawing itself: a shape half made, with the palette that made it and the line saying where
		# it has got to. Taken through the drafting controller, which is what a click on the plan does.
		{"name": "drawing", "do": "drawing"},
		# Drawing.
		{"name": "snapping", "do": "window", "call": "open_snap_window"},
		{"name": "layers", "do": "window", "call": "open_layer_window"},
		{"name": "ground-page", "do": "window", "call": "open_ground_window"},
		{"name": "grading", "do": "window", "call": "open_grading_window"},
		{"name": "osm", "do": "window", "call": "open_osm_window"},
		{"name": "underlay", "do": "window", "call": "open_underlay_window"},
		# Plants and food.
		{"name": "plants", "do": "window", "call": "open_plant_browser"},
		{"name": "food", "do": "window", "call": "open_food_window"},
		{"name": "rotation", "do": "window", "call": "open_rotation_window"},
		{"name": "harvest", "do": "window", "call": "open_harvest_window"},
		{"name": "sowing", "do": "window", "call": "open_sowing_window"},
		{"name": "yield", "do": "window", "call": "open_yield_window"},
		{"name": "plant-order", "do": "window", "call": "open_plant_order_window"},
		# The business.
		{"name": "estimate", "do": "window", "call": "open_estimate_window"},
		{"name": "pipeline", "do": "window", "call": "open_pipeline_board"},
		{"name": "schedule", "do": "window", "call": "open_schedule_board"},
		{"name": "billing", "do": "window", "call": "open_billing_window"},
		{"name": "cost", "do": "window", "call": "open_cost_window"},
		{"name": "closeout", "do": "window", "call": "open_closeout_window"},
		{"name": "ledger", "do": "window", "call": "open_ledger_window"},
		{"name": "analytics", "do": "window", "call": "open_analytics_window"},
		# Presenting and output.
		{"name": "walk", "do": "window", "call": "open_walk_window"},
		{"name": "sun", "do": "window", "call": "open_sun_window"},
		{"name": "sheet", "do": "window", "call": "open_sheet_window"},
		# History and other people.
		{"name": "sync", "do": "window", "call": "open_sync_window"},
		{"name": "revision", "do": "window", "call": "open_revision_window"},
		{"name": "status", "do": "window", "call": "open_status_window"},
		# Last, because these are not pages: a docked panel and the palette stand over everything, so
		# each is put away by name once it has been shot.
		{"name": "water", "do": "window", "call": "open_water_panel", "undo": "close_water_panel"},
		{"name": "light", "do": "window", "call": "open_light_panel", "undo": "close_light_panel"},
		{"name": "palette", "do": "window", "call": "open_command_palette", "undo": "toggle_command_palette"},
	]


func _process(_delta: float) -> void:
	if _hud == null:
		_hud = get_child(0).get_node_or_null(^"Hud")
		_view = _find_view(self)
		if _hud == null or _view == null:
			return
		print("hud ", _hud != null, " view ", _view != null)
		return
	match _phase:
		0:
			if _at >= _shots.size():
				print("DONE ", _at, " shots")
				set_process(false)
				return
			_begin(_shots[_at])
			_phase = 1
			_wait = int(_shots[_at].get("settle", 8))
		1:
			_wait -= 1
			if _wait <= 0:
				_take(String(_shots[_at]["name"]))
				_phase = 2
				_wait = 3
		2:
			_wait -= 1
			if _wait <= 0:
				_undo(_shots[_at])
				_close_windows()
				_at += 1
				_phase = 0


## Put the program into the state this picture is of.
func _begin(shot: Dictionary) -> void:
	var how := String(shot.get("do", "none"))
	match how:
		"none":
			pass
		"plan":
			_view.show_mode(ViewController.ViewMode.PLAN_2D)
		"ground":
			_view.show_mode(ViewController.ViewMode.GROUND)
		"window":
			# Over the flat plan, which is the view a page about the drawing is read in.
			_view.show_mode(ViewController.ViewMode.PLAN_2D)
			_open(String(shot.get("call", "")))
			shot["settle"] = 45
		"drawing":
			_view.show_mode(ViewController.ViewMode.PLAN_2D)
			var draft: DraftController = _view.draft_controller()
			draft.set_drawing(true)
			draft.arm(ToolScript.Kind.POLYLINE)
			# Two picks down and the cursor away, so the plan carries a shape with a rubber band to the
			# point it is about to take - which is what the palette and the status line are for.
			draft.click(Vector2(660.0, 630.0))
			draft.click(Vector2(980.0, 500.0))
			draft.hover(Vector2(1060.0, 700.0))
			shot["settle"] = 45
		"help":
			_help_on(PROBE_SUBJECT)
			shot["settle"] = 45
	print("--- ", shot["name"], " (", how, ")")


## Open a page through the HUD's own door, the way its menu entry does.
func _open(call_name: String) -> void:
	if _hud.has_method(call_name):
		_hud.call(call_name)
	else:
		print("  no such page: ", call_name)


## Take the shot. The frame read here is the one already drawn, so the wait before it is what makes
## the capture settled rather than half-drawn.
##
## Saved lossy rather than as a PNG: a photograph of a textured garden does not compress, and the same
## picture comes out at a sixth of the size without a reader being able to tell - which is what decides
## whether a manual can carry thirty of them.
func _take(shot_name: String) -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var image: Image = viewport.get_texture().get_image()
	if image == null:
		print("  ", shot_name, ": nothing to read off the viewport")
		return
	var path := "%s/%s.webp" % [OUT, shot_name]
	print("  ", path, "  ", image.get_size(), "  save=", image.save_webp(path, true, QUALITY))


## Put away anything this shot opened that is not a page - a docked panel, the palette - through the
## HUD's own door for it, named by the shot that opened it.
func _undo(shot: Dictionary) -> void:
	var closer := String(shot.get("undo", ""))
	if closer.is_empty():
		return
	if _hud.has_method(closer):
		_hud.call(closer)
	else:
		print("  no such closer: ", closer)


## Close every page that is still up, wherever it hangs in the HUD: one page left over would be standing
## over the next picture.
func _close_windows() -> void:
	for window: Window in _all_windows(_hud):
		if window.visible:
			window.hide()


func _all_windows(node: Node) -> Array[Window]:
	var out: Array[Window] = []
	for child: Node in node.get_children():
		if child is Window:
			out.append(child)
		out.append_array(_all_windows(child))
	return out


## The manual itself, open on a subject: used to look at how a page carries its pictures, which no
## capture of a page can show.
func _help_on(subject: String) -> void:
	_hud.call("open_help_window")
	var window: Window = _hud.get(&"_help_window")
	if window == null:
		print("  no help window")
		return
	window.call("select_topic", subject)


func _find_view(node: Node) -> ViewController:
	if node is ViewController:
		return node
	for child: Node in node.get_children():
		var found: ViewController = _find_view(child)
		if found != null:
			return found
	return null
