extends Node2D
## A live pass over the nursery order: the shipped yard's own planting turned into draft purchase orders
## on the job desk.
##
## This is a development tool, not part of the game. It instances the **real main scene**, opens the
## **real page** and presses it by the caption a person reads, so the module, the page, the HUD, the job
## desk, the price list and the planting all shipped the ones under test. It prints every step, and it
## reads the page off the framebuffer rather than assuming a window that exists on screen.
##
## Run `res://scenes/plant_order_demo.tscn`.
##
## The nursery is put into the field by script rather than typed, because a demonstration cannot type.
## Everything else - opening the page, pressing the button, the write - goes through the same calls the
## program makes.

const MAIN := preload("res://scenes/main.tscn")
const ViewScript := preload("res://scripts/view_controller.gd")
const PlacementScript := preload("res://scripts/plant_placement.gd")
const OrderScript := preload("res://scripts/biz/plant_order.gd")
const DeskScript := preload("res://scripts/biz/job_desk.gd")
const EstimateScript := preload("res://scripts/biz/estimate.gd")
const LineScript := preload("res://scripts/biz/estimate_line.gd")
const ItemScript := preload("res://scripts/biz/cost_item.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")

## The grower the demonstration buys from. The book that ships names nobody, which is exactly why the
## page asks for one.
const NURSERY := "Greenwood Nursery"

## Two species the shipped list can name, put down the way the program puts one down: a tree and a
## perennial, because a nursery order prices the two differently.
const MAPLE := &"acer-rubrum-autumn-blaze"
const RUDBECKIA := &"rudbeckia-fulgida-goldsturm"


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	var hud: Node = main.get_node_or_null(^"Hud")
	if hud == null:
		print("no HUD in the main scene")
		return

	var view_controller: Node = main.get_node_or_null(^"ViewController")
	if view_controller != null:
		view_controller.show_mode(ViewScript.ViewMode.PLAN_2D)
		for _frame in 90:
			await get_tree().process_frame
	print("the view is the flat plan: ",
		view_controller != null and view_controller.mode == ViewScript.ViewMode.PLAN_2D)

	print("--- what the shipped yard plants ---")
	var rows: Array = hud._planting_rows()
	print("the yard holds ", rows.size(), " kind(s) of plant")
	for row: Dictionary in rows:
		print("  ", int(row["count"]), " x ", String(row["botanical_name"]), "  (",
			String(row["category_name"]), ", ", int(row["spread_cm"]), " cm)")
	# The props the yard was built with carry no species, and the list says so rather than guessing: a
	# plant nobody can name is the one thing a planting list must not hide. So the demonstration puts
	# down two it can name, the way the plant library puts one down.
	print("--- two plants the list can name, put down as the library puts one down ---")
	var yard: Node3D = view_controller.yard
	var catalogue = hud.plant_list()
	for placed: Dictionary in [
		PlacementScript.place(catalogue, MAPLE, yard, Vector3(0.0, 0.0, 0.0)),
		PlacementScript.place(catalogue, RUDBECKIA, yard, Vector3(3.0, 0.0, 0.0)),
	]:
		if not bool(placed["ok"]):
			print("  could not plant: ", String(placed["reason"]))
	print("the yard now holds ", hud._planting_rows().size(), " kinds, the unnamed ones still counted")
	# The plan is a projection of the yard and the picker caches what it can select, so a yard that has
	# changed has to say so - which is what the program does after it plants anything at all.
	view_controller.refresh_after_planting()

	print("--- the plan: the planting priced from the price list ---")
	var planned: Dictionary = hud.plant_order_plan()
	print(OrderScript.summary(planned))
	for words: String in OrderScript.plan_rows(planned):
		print("  ", words)
	for problem: String in planned["problems"]:
		print("  CANNOT PRICE: ", problem)

	if int(planned["unpriced"]) > 0:
		# What a person does about that refusal - the unnamed props are named, or taken off - and the
		# demonstration takes them off rather than ordering around them, because an order that quietly
		# left out thirty plants would read as a smaller garden than the plan drew.
		print("--- so the props with no species recorded come off, and the plan is read again ---")
		var unnamed := 0
		for node: Node3D in PlacementScript.planted(yard):
			if PlacementScript.species_of(node).is_empty():
				node.free()
				unnamed += 1
		print("  ", unnamed, " props with nothing recorded came off; ",
			hud._planting_rows().size(), " kinds are left")
		# Taking something off the yard is a change to the yard like any other, and the picker's cache
		# and the plan both hold the nodes that just went - so they are told, the same way planting
		# tells them.
		view_controller.refresh_after_planting()
		planned = hud.plant_order_plan()
		print("  and now: ", OrderScript.summary(planned))
		for words: String in OrderScript.plan_rows(planned):
			print("    ", words)

	print("--- a job for the plants to be ordered against ---")
	hud._build_job_desk()
	var desk: DeskScript = hud._job_desk
	var job = desk.make_job_from(_estimate())
	if job == null:
		print("no job could be made from the estimate")
		return
	var job_id: String = job.id
	print("the job is ", desk.job_label(job_id))

	print("--- the page, opened the way the menu opens it ---")
	await _settle()
	var before := _shot()
	hud.open_plant_order_window()
	await _settle()
	var window: Node = hud._plant_order_window
	print("the page is up: ", hud.is_plant_order_window_open())
	print("it lists ", window.line_count(), " rows, one per kind of plant")
	for words: String in window.line_texts():
		print("  ", words)
	print("it says: ", window.summary_text())
	print("the jobs it can order for: ", window.job_ids())
	print("and before a nursery is named it says: ", window.order_hint())
	print("the button is dead: ", not window.order_enabled(),
		", and it reads \"", window.order_words(), "\"")

	print("--- naming the grower, and ordering ---")
	window.set_supplier(NURSERY)
	print("with ", NURSERY, " named it says: ", window.order_hint())
	print("now the button is live: ", window.order_enabled())
	print("pressing \"", window.order_words(), "\": ", _press(hud, window.order_words()))
	await _settle()
	print("  the page says: ", window.said())

	print("--- what landed on the job desk ---")
	print("the desk holds ", desk.purchase_orders.size(), " order(s)")
	for held in desk.purchase_orders:
		print("  ", held.number, " to ", held.supplier, ": ", held.state_name())
		for row: Dictionary in held.line_rows():
			print("    ", row["description"], "  ", int(row["ordered_milli"]), " thousandths at ",
				(row["unit_cost"] as MoneyScript).format_with_currency())
		print("    ordered total ", held.ordered_total().format_with_currency(),
			", committed ", held.committed().format_with_currency())
	print("what the job has committed: ",
		(desk.cost_report(job_id).totals()["committed"] as MoneyScript).format_with_currency(),
		" (a draft commits nothing until somebody issues it)")

	print("--- and the page really is on the screen ---")
	var after := _shot()
	var middle := Vector2(window.position) + Vector2(window.size) * 0.5
	var corner := Vector2(get_viewport().get_visible_rect().size.x - 60.0,
		get_viewport().get_visible_rect().size.y - 40.0)
	print("  the middle of the page at screen ", middle, " changed ",
		_changed_pixels(before, after, middle), " pixels of the 625 around it")
	print("  and a corner nowhere near it changed ",
		_changed_pixels(before, after, corner), " pixels, so it is the page that appeared")
	print("  the screen is ", after.get_size(), ", saved to res://preview/plant_order_demo.png")
	for found: Node in _every_window(main):
		var rect := Rect2i((found as Window).position, (found as Window).size)
		print("  window ", found.name, " is ", "shown" if found.visible else "put away", " at ", rect)
	DirAccess.make_dir_recursive_absolute("res://preview")
	after.save_png("res://preview/plant_order_demo.png")


## An estimate with a planting phase on it, so the job has a code the plants are bought against.
func _estimate() -> EstimateScript:
	var estimate: EstimateScript = EstimateScript.new("E-DEMO")
	estimate.customer = {"name": "the shipped yard"}
	var line: LineScript = LineScript.new()
	line.cost_code = OrderScript.PLANTING_CODE
	line.kind = ItemScript.MATERIAL
	line.quantity_milli = 100000
	line.unit = &"EACH"
	line.unit_cost = MoneyScript.of(750)
	line.unit_price = MoneyScript.of(1500)
	estimate.lines.append(line)
	return estimate


## Two frames and a drawn frame, so a capture is of a settled screen.
func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _shot() -> Image:
	return get_viewport().get_texture().get_image()


## How many pixels of the square around a place on the screen changed between two captures.
func _changed_pixels(before: Image, after: Image, at: Vector2, half: int = 12) -> int:
	var changed := 0
	for dy in range(-half, half + 1):
		for dx in range(-half, half + 1):
			var x := clampi(int(at.x) + dx, 0, after.get_width() - 1)
			var y := clampi(int(at.y) + dy, 0, after.get_height() - 1)
			if not before.get_pixel(x, y).is_equal_approx(after.get_pixel(x, y)):
				changed += 1
	return changed


## Every `Window` under a node, however deep, because the ones that matter here are built in code and
## hang off the HUD rather than sitting in the scene file.
func _every_window(under: Node) -> Array[Window]:
	var found: Array[Window] = []
	for child: Node in under.get_children():
		if child is Window:
			found.append(child as Window)
		found.append_array(_every_window(child))
	return found


## Press a button on the page by the caption a person reads, so the pass goes through the same signal
## the program does rather than calling the handler behind it.
func _press(hud: Node, caption: String) -> bool:
	var window: Node = hud._plant_order_window
	if window == null:
		return false
	for found: Node in window.find_children("*", "Button", true, false):
		var button := found as Button
		if button.text == caption:
			button.pressed.emit()
			return true
	return false