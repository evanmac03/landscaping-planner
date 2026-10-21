@tool
class_name BizCostBookDock
extends Control
## The cost book dock: read a supplier's price list, see what it would change, and put it into a new
## version of the book (spec §12, the cost book panel; §1's `addons/biz_tools/`).
##
## A dock rather than more game HUD, because nothing here is in the drawing: a price list, a
## percentage and an effective date are three fields a person edits while looking at the filesystem.
## The one thing it does that the running game cannot is **write a new version of the book beside the
## one in the project**, which is authoring rather than designing.
##
## It holds no arithmetic. Every figure comes from `BizBookImport` (reading and planning) and
## `BizPricePreview` (what a plan would do to the work already quoted), so the dock and the module
## cannot disagree about what a price change comes to - the same discipline `EstimateDesk` follows.
## What it adds is the three things a dock adds: a file to open, a place to say where the new book
## goes, and a list of the things that are wrong with what it found.
##
## Nothing here touches the editor. The dock is a plain `Control`, so every method below is driven in
## a test with the dock never added to a tree; `plugin.gd` is the only file that knows it is a plugin.

const BookScript := preload("res://scripts/biz/cost_book.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")
const ImportScript := preload("res://scripts/biz/book_import.gd")
const PreviewScript := preload("res://scripts/biz/price_preview.gd")
const StoreScript := preload("res://scripts/biz/store.gd")
const RateScript := preload("res://scripts/biz/rate.gd")

## The starter book the project ships. It is read here and never written to: a new version goes to
## the live path below, so a designer's first import cannot edit the catalogue in the repository.
const SHIPPED_BOOK := "res://data/biz/costbook.json"
## Where the live book lives (§11.1), which is where a new version is written by default.
const LIVE_BOOK := "user://biz/costbook.json"

## The book in hand, where it was read from, the plan in hand and what it would do.
var book: CostBook = null
var book_source: String = ""
var change_plan: Dictionary = {}
var preview_result: Dictionary = {}
## Where the store of records lives, so the preview can find the estimates already quoted.
var store_root: String = StoreScript.ROOT
var last_words: String = ""

var _price_rows: Array = []
var _built: bool = false

var _book_path: LineEdit = null
var _out_path: LineEdit = null
var _price_path: LineEdit = null
var _date_field: LineEdit = null
var _supplier_field: LineEdit = null
var _percent_field: LineEdit = null
var _book_line: Label = null
var _status: Label = null
var _plan_box: VBoxContainer = null
var _preview_box: VBoxContainer = null
var _diagnostic_box: VBoxContainer = null


func _ready() -> void:
	if not _built:
		build()


# --- the dock ----------------------------------------------------------------------------------


## Build the dock. Called by the plugin when the dock is added, and by a test directly, so the whole
## of it is reachable without the editor.
func build() -> void:
	if _built:
		return
	_built = true
	name = "Cost book"
	var column: VBoxContainer = _column("Dock")
	add_child(column)

	column.add_child(_heading("Cost book"))
	_book_line = _label(column, "no cost book is loaded")
	_book_line.name = "BookLine"
	_book_path = _field_row(column, "Book", SHIPPED_BOOK, "Load", load_book)
	_out_path = _field_row(column, "Write to", LIVE_BOOK, "", Callable())

	column.add_child(_heading("A supplier's price list"))
	_price_path = _field_row(column, "CSV", "", "Read it", read_price_list)
	_percent_field = LineEdit.new()
	column.add_child(_row_of("Reprice all by, %", _percent_field, "Plan it", plan_bulk))
	_supplier_field = _labelled_field(column, "Only from supplier", "")
	_date_field = LineEdit.new()
	_date_field.placeholder_text = "YYYY-MM-DD"
	column.add_child(_row_of("Effective from", _date_field, "Apply as a new version", apply_plan))

	column.add_child(_heading("What the plan would change"))
	_plan_box = _column("PlanRows")
	column.add_child(_plan_box)

	column.add_child(_heading("What it would do to the work already quoted"))
	_preview_box = _column("PreviewRows")
	column.add_child(_preview_box)

	column.add_child(_heading("What is wrong with it"))
	_diagnostic_box = _column("DiagnosticRows")
	column.add_child(_diagnostic_box)

	_status = _label(column, "Open a cost book to begin.")
	_status.name = "Status"
	refresh()


## Read the diagnostics again, and - when there is a plan in hand - work out again what it would do to
## the work already quoted. Every action that changes the book calls it, and so does a test that edits
## the book behind the dock's back: a report nobody re-reads is a report of a moment that has passed,
## which is exactly the kind of list a person stops trusting.
func refresh() -> void:
	_refresh_diagnostics()
	_clear(_preview_box)
	preview_result = {}
	if book == null or change_plan.is_empty() or _preview_box == null:
		return
	var preview: BizPricePreview = PreviewScript.new()
	preview.bind(book, PreviewScript.read_estimates(StoreScript.new(store_root)))
	preview_result = preview.preview(change_plan)
	if not bool(preview_result["ok"]):
		return
	var rows: Array = preview_result["rows"]
	if rows.is_empty():
		_label(_preview_box, "no estimate in the store, so nothing already quoted would move")
	for row: Dictionary in rows:
		var delta: int = int(row["delta_cents"])
		if delta == 0 and int(row["lines_touched"]) == 0:
			continue
		_label(_preview_box, "%s  cost %s -> %s  price %s unchanged  margin %.2f%% -> %.2f%%" % [
			String(row["number"]),
			_money(int(row["cost_before_cents"]), book.currency),
			_money(int(row["cost_after_cents"]), book.currency),
			_money(int(row["price_cents"]), book.currency),
			float(int(row["margin_before_ppm"])) / 10000.0,
			float(int(row["margin_after_ppm"])) / 10000.0,
		])


func _heading(words: String) -> Label:
	var line: Label = Label.new()
	line.text = words
	return line


func _column(node_name: String) -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new()
	box.name = node_name
	return box


func _label(parent: Node, words: String) -> Label:
	var line: Label = Label.new()
	line.text = words
	parent.add_child(line)
	return line


## An amount as a person reads it. One function, so a figure on this dock and a figure on a proposal
## are formatted the same way (§2.1).
static func _money(cents: int, currency: StringName) -> String:
	return MoneyScript.of(cents, currency).format_with_currency()


func _labelled_field(parent: Node, caption: String, value: String) -> LineEdit:
	var row: HBoxContainer = HBoxContainer.new()
	var caption_label: Label = Label.new()
	caption_label.text = caption
	row.add_child(caption_label)
	var field: LineEdit = LineEdit.new()
	field.text = value
	row.add_child(field)
	parent.add_child(row)
	return field


func _field_row(parent: Node, caption: String, value: String, button_words: String, action: Callable) -> LineEdit:
	var field: LineEdit = _labelled_field(parent, caption, value)
	if button_words.is_empty() or not action.is_valid():
		return field
	var row: HBoxContainer = field.get_parent()
	var button: Button = Button.new()
	button.text = button_words
	button.pressed.connect(func() -> void: action.call(field.text))
	row.add_child(button)
	return field


func _row_of(caption: String, field: LineEdit, button_words: String, action: Callable) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	var caption_label: Label = Label.new()
	caption_label.text = caption
	row.add_child(caption_label)
	row.add_child(field)
	var button: Button = Button.new()
	button.text = button_words
	button.pressed.connect(func() -> void: action.call(field.text))
	row.add_child(button)
	return row


# --- reading -----------------------------------------------------------------------------------


## Read a cost book and show what it is. Every other action needs one.
func load_book(path: String) -> Dictionary:
	var read: Dictionary = BookScript.load_from(path)
	if not bool(read["ok"]):
		book = null
		book_source = ""
		_say(String(read["reason"]))
		return read
	book = read["book"]
	book_source = path
	change_plan = {}
	preview_result = {}
	if _book_line != null:
		_book_line.text = "v%d from %s - %d items, %d kits" % [
			book.version, book.effective_from if not book.effective_from.is_empty() else "no date",
			book.item_count(), book.kit_count(),
		]
	_clear(_plan_box)
	_clear(_preview_box)
	_say("Read %s. %s" % [path, book.describe()])
	refresh()
	return read


## Read a supplier's price list and plan it against the book in hand. It does not apply anything: a
## plan is what the next two buttons argue about.
func read_price_list(path: String) -> Dictionary:
	if book == null:
		return _refuse("there is no cost book to plan a price list against")
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _refuse("there is no price list at %s" % path)
	var text: String = file.get_as_text()
	file.close()
	var read: Dictionary = ImportScript.read_csv(text, book.currency)
	if not bool(read["ok"]):
		return _refuse(String(read["reason"]))
	_price_rows = read["rows"]
	change_plan = ImportScript.plan(book, _price_rows, false)
	_show_plan()
	var words: String = ImportScript.describe(change_plan)
	var problems: Array = change_plan["problems"]
	if not problems.is_empty():
		words += ", starting with: %s" % String(problems[0])
	_say("Read %s. %s." % [path, words])
	refresh()
	return read


## Reprice every item in the book by a percentage, or only the items one supplier sells.
##
## The percentage is read the way every other rate in this module is read, so `-2.5`, `+5` and `5%`
## are all percentages and a change finer than a hundredth of a percent is refused rather than
## rounded into a price nobody asked for.
##
## The check is against `Rate.INVALID` and **not** `Rate.is_valid`, which is the trap worth naming: a
## rate is valid when it is not negative, and a **price change** is signed - a supplier cutting its
## prices is the ordinary case, and asking `is_valid` made every reduction refuse as unreadable. The
## cost is that the sentinel is also `-1`, so a change of a ten-thousandth of a percent reads as
## unreadable; that is a change nobody makes, and it is named rather than rounded to nothing.
func plan_bulk(percent_text: String) -> Dictionary:
	if book == null:
		return _refuse("there is no cost book to reprice")
	var percent_ppm: int = RateScript.parse_percent(percent_text)
	if percent_ppm == RateScript.INVALID:
		return _refuse("\"%s\" is not a percentage this can read, or is smaller than a hundredth of a percent" % percent_text)
	var supplier: StringName = &""
	if _supplier_field != null:
		supplier = StringName(_supplier_field.text.strip_edges())
	change_plan = PreviewScript.bulk_plan(book, percent_ppm, supplier)
	if not bool(change_plan["ok"]):
		_say(String(change_plan["reason"]))
		_clear(_plan_box)
		_clear(_preview_box)
		return change_plan
	_price_rows = []
	_show_plan()
	_say("Repricing %d item%s by %s." % [
		(change_plan["changes"] as Array).size(),
		"" if (change_plan["changes"] as Array).size() == 1 else "s",
		RateScript.percent_text(percent_ppm),
	])
	refresh()
	return change_plan


## What the plan in hand would do to the estimates already quoted. Reads it again rather than handing
## back whatever the last look found, so the figures are of this moment and this book.
func show_preview() -> Dictionary:
	if book == null:
		return _refuse("there is no cost book to preview a change against")
	if change_plan.is_empty():
		return _refuse("there is no plan in hand to preview")
	refresh()
	return preview_result


## Put the plan into the next version of the book and write it out. Returns `{ok, reason, path,
## version}`.
##
## The book it was read from is not touched (REQ-B6): what is written is the new version, at the
## path in the **Write to** field, through a temporary file and a rename, exactly as a drawing is.
func apply_plan(_unused: String = "") -> Dictionary:
	if book == null:
		return _refuse("there is no cost book to apply a plan to")
	var effective: String = _date_field.text.strip_edges() if _date_field != null else ""
	var applied: Dictionary = ImportScript.apply(book, change_plan, effective, "the cost book dock", 0)
	if not bool(applied["ok"]):
		return _refuse(String(applied["reason"]))
	var next: CostBook = applied["book"]
	var target: String = _out_path.text.strip_edges() if _out_path != null else LIVE_BOOK
	if target.is_empty():
		return _refuse("there is nowhere to write the new version")
	var written: Dictionary = next.save_to(target)
	if not bool(written["ok"]):
		return _refuse(String(written["reason"]))
	_say("Wrote %s to %s." % [next.describe(), target])
	refresh()
	return {"ok": true, "reason": "", "path": target, "version": next.version}


# --- showing what it found ---------------------------------------------------------------------


func _show_plan() -> void:
	_clear(_plan_box)
	if _plan_box == null:
		return
	var changes: Array = change_plan.get("changes", [])
	if changes.is_empty():
		_label(_plan_box, "nothing would change")
	if book != null:
		for entry: Dictionary in changes:
			var delta: int = int(entry["delta_cents"])
			_label(_plan_box, "%s  %s -> %s  (%s%s)" % [
				String(entry["name"]),
				_money(int(entry["before_cents"]), book.currency),
				_money(int(entry["after_cents"]), book.currency),
				"+" if delta > 0 else "-",
				_money(absi(delta), book.currency),
			])
	for entry: Dictionary in change_plan.get("unmatched", []):
		_label(_plan_box, "unmatched: %s (line %d)" % [String(entry["name"]), int(entry["line"])])
	for problem: String in change_plan.get("problems", []):
		_label(_plan_box, "unreadable: %s" % problem)


## Everything wrong with what the dock found, named so it can be fixed where it was authored: what
## the book itself refuses, what the store cannot read, items no phase claims, and lines in the
## stored estimates priced from an item the book no longer has.
##
## A **report** and not a validator: nothing here stops a price change, because a book with one
## item missing a cost code is still a book.
func diagnostics() -> Array[String]:
	var out: Array[String] = []
	if book == null:
		out.append("no cost book is loaded")
		return out
	for problem: String in book.problems():
		out.append(problem)
	var store: BizStore = StoreScript.new(store_root)
	for problem: String in store.problems():
		out.append(problem)
	var no_code: int = 0
	for item_id: StringName in book.item_ids():
		var each: CostItem = book.item(item_id)
		if each != null and each.cost_code.is_empty():
			no_code += 1
	if no_code > 0:
		out.append("%d item%s carries no cost code, so a takeoff line priced from it would cost to nowhere" % [
			no_code, "" if no_code == 1 else "s"
		])
	var stale: int = 0
	for estimate: Estimate in PreviewScript.read_estimates(store):
		for line: EstimateLine in estimate.lines:
			if not line.cost_item.is_empty() and not book.has_item(line.cost_item):
				stale += 1
	if stale > 0:
		out.append("%d line%s in the stored estimates is priced from an item this book no longer has" % [
			stale, "" if stale == 1 else "s"
		])
	if out.is_empty():
		out.append("the book, the store and the stored estimates agree")
	return out


func _refresh_diagnostics() -> void:
	_clear(_diagnostic_box)
	if _diagnostic_box == null:
		return
	for words: String in diagnostics():
		_label(_diagnostic_box, words)


func _clear(parent: Node) -> void:
	if parent == null:
		return
	for child in parent.get_children():
		parent.remove_child(child)
		child.free()


func _say(words: String) -> void:
	last_words = words
	if _status != null:
		_status.text = words


func _refuse(reason: String) -> Dictionary:
	_say(reason)
	return {"ok": false, "reason": reason}


# --- what a test (or a person) reads back ------------------------------------------------------


func status_text() -> String:
	return _status.text if _status != null else ""


func book_text() -> String:
	return _book_line.text if _book_line != null else ""


func plan_rows() -> Array[String]:
	return _rows_of(_plan_box)


func preview_rows() -> Array[String]:
	return _rows_of(_preview_box)


func diagnostic_rows() -> Array[String]:
	return _rows_of(_diagnostic_box)


func _rows_of(parent: Node) -> Array[String]:
	var out: Array[String] = []
	if parent == null:
		return out
	for child in parent.get_children():
		if child is Label:
			out.append((child as Label).text)
	return out


func book_path_text() -> String:
	return _book_path.text if _book_path != null else ""


func output_path_text() -> String:
	return _out_path.text if _out_path != null else ""


func price_path_text() -> String:
	return _price_path.text if _price_path != null else ""


func set_book_path(words: String) -> void:
	if _book_path != null:
		_book_path.text = words


func set_output_path(words: String) -> void:
	if _out_path != null:
		_out_path.text = words


func set_price_path(words: String) -> void:
	if _price_path != null:
		_price_path.text = words


func set_effective_date(words: String) -> void:
	if _date_field != null:
		_date_field.text = words


func set_supplier(words: String) -> void:
	if _supplier_field != null:
		_supplier_field.text = words


func set_percent(words: String) -> void:
	if _percent_field != null:
		_percent_field.text = words


func is_built() -> bool:
	return _built