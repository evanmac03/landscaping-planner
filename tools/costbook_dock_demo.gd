extends Control
## A live pass over the **cost book dock**: a supplier's price list read and planned, what the plan
## would do to a job already quoted, the next version of the book written, and the list of things
## wrong with what it found (spec §12, §1's `addons/biz_tools/`).
##
## This is a development tool, not part of the game, and it exists for one reason: the dock is an
## **editor** panel, so the only way to watch it work without opening the editor's Project Settings is
## to put the very same `Control` on screen and drive the same methods the buttons call. It also makes
## the reload pass compile `addons/biz_tools/costbook_dock.gd` - nothing else in the project loads it,
## and a file the running scene never reaches reports no warnings whether or not it has any.
##
## It writes to `user://demo_costbook` and nothing in the game reads it; the folder is wiped first so
## the run reads the same every time. Run `res://scenes/costbook_dock_demo.tscn`.

const BookScript := preload("res://scripts/biz/cost_book.gd")
const ItemScript := preload("res://scripts/biz/cost_item.gd")
const EstimateScript := preload("res://scripts/biz/estimate.gd")
const LineScript := preload("res://scripts/biz/estimate_line.gd")
const StoreScript := preload("res://scripts/biz/store.gd")
const DockScript := preload("res://addons/biz_tools/costbook_dock.gd")

const ROOT := "user://demo_costbook"
const STORE_ROOT := "user://demo_costbook/store"
const NEW_BOOK := "user://demo_costbook/costbook.json"
const PRICE_LIST := "user://demo_costbook/greenco-prices.csv"
## A September morning, stated rather than read off the clock.
const MOMENT := 1788000000

var _dock: Control = null


func _ready() -> void:
	_wipe(ROOT)
	_write_price_list()
	_seed_a_quote()

	_dock = DockScript.new()
	_dock.store_root = STORE_ROOT
	var scroller: ScrollContainer = ScrollContainer.new()
	scroller.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroller)
	_dock.custom_minimum_size = Vector2(560, 1400)
	scroller.add_child(_dock)
	_dock.build()
	_dock.set_output_path(NEW_BOOK)

	print("--- the dock, with nothing open ---")
	print("status: ", _dock.status_text())
	print("diagnostics: ", _dock.diagnostic_rows())

	print("")
	print("--- the project's starter book is read ---")
	var loaded: Dictionary = _dock.load_book(DockScript.SHIPPED_BOOK)
	print("read: ", loaded["ok"])
	print(_dock.book_text())

	print("")
	print("--- a supplier's price list is read and planned ---")
	var read: Dictionary = _dock.read_price_list(PRICE_LIST)
	print("rows read: ", read["rows"].size())
	print("status: ", _dock.status_text())
	print("what the plan would change:")
	for row: String in _dock.plan_rows():
		print("  ", row)

	print("")
	print("--- what it would do to the job already quoted ---")
	print("the estimate in the store is EST-2026-0001: 20 m3 of bark mulch, priced at 1.5x")
	for row: String in _dock.preview_rows():
		print("  ", row)

	print("")
	print("--- the next version of the book is written ---")
	_dock.read_price_list(PRICE_LIST)
	_dock.set_effective_date("2026-11-01")
	var applied: Dictionary = _dock.apply_plan()
	print("applied: ", applied["ok"], " - ", applied.get("reason", ""))
	print("status: ", _dock.status_text())
	print("the file is there: ", FileAccess.file_exists(NEW_BOOK))
	var written: Dictionary = BookScript.load_from(NEW_BOOK)
	if bool(written["ok"]):
		var next: CostBook = written["book"]
		print("read back: ", next.describe())
		print("source: ", next.source)
		print("bark mulch is now ", next.item(&"bed-mulch").rate.format_with_currency(),
			" and the project's own starter book still says ",
			BookScript.load_from(DockScript.SHIPPED_BOOK)["book"].item(&"bed-mulch").rate.format_with_currency())

	print("")
	print("--- a bulk update, and what it would do this time ---")
	_dock.set_supplier("")
	var bare: Control = DockScript.new()
	print("a dock with no book refuses rather than failing: ", bare.plan_bulk("-5%")["reason"])
	bare.free()
	var bulk: Dictionary = _dock.plan_bulk("-5%")
	print("planned: ", bulk["ok"], " - ", (bulk["changes"] as Array).size(), " items")
	print("status: ", _dock.status_text())
	print("rows:")
	for row: String in _dock.plan_rows().slice(0, 3):
		print("  ", row)

	print("")
	print("--- what a percentage nobody could mean does ---")
	var nonsense: Dictionary = _dock.plan_bulk("five")
	print("refused: ", not nonsense["ok"], " - ", nonsense["reason"])

	print("")
	print("--- the diagnostics, which name what is wrong and stop nothing ---")
	for row: String in _dock.diagnostic_rows():
		print("  ", row)


## A price list from a supplier, in the shape a nursery or a stone yard sends: a code, a description,
## a unit, a cost - one row of which the book has no item for.
func _write_price_list() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)
	var text := "SKU,Description,UOM,Unit Cost,Waste\n"
	text += "bed-mulch,\"Bark mulch, bulk bag\",m3,64.50,8%\n"
	text += "bed-edge-steel,Steel bed edging,m,28.00,\n"
	text += "crew-hour,Landscape crew,hour,46.00,\n"
	text += "hb-4x8,\"Bloomsdale 4x8\",ea,3.24,\n"
	var file: FileAccess = FileAccess.open(PRICE_LIST, FileAccess.WRITE)
	file.store_string(text)
	file.close()


## A job with one estimate against it, priced from the starter book, plus one line priced from an item
## the book no longer holds - so the diagnostics have something real to report.
func _seed_a_quote() -> void:
	var book: CostBook = BookScript.load_from(DockScript.SHIPPED_BOOK)["book"]
	var store: BizStore = StoreScript.new(STORE_ROOT)
	store.put(StoreScript.JOB_KIND, "J-1001", {
		"number": "J-1001",
		"label": "Smith, back garden",
	}, "", -1, "evan", MOMENT, "the job was opened")

	var mulch: CostItem = book.item(&"bed-mulch")
	var line: EstimateLine = LineScript.make(mulch, 20000)
	line.unit_price = mulch.rate.scale_ppm(1500000)
	var estimate: Estimate = EstimateScript.make("E-1")
	estimate.number = "EST-2026-0001"
	estimate.customer["name"] = "Ada Lovelace"
	estimate.add_line(line, book)
	var body: Dictionary = estimate.to_dict()

	var ghost: CostItem = ItemScript.make(&"discontinued-thing", "Discontinued thing", &"EACH", 1200)
	var ghost_line: EstimateLine = LineScript.make(ghost, 4000)
	(body["lines"] as Array).append(ghost_line.to_dict())
	store.put("estimate", "E-1", body, "J-1001", -1, "evan", MOMENT)


func _wipe(folder: String) -> void:
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		return
	for file_name in dir.get_files():
		DirAccess.remove_absolute(folder.path_join(String(file_name)))
	for subfolder in dir.get_directories():
		_wipe(folder.path_join(String(subfolder)))
	DirAccess.remove_absolute(folder)
