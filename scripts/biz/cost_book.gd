class_name CostBook
extends RefCounted
## The catalogue: what things cost, what recipes make them, and which version of that a price came
## from.
##
## JSON rather than a `.tres`, for a reason that is not stylistic (§2.3): a cost book is edited by
## a bookkeeper in a spreadsheet, imported from a supplier, diffed in a review and mailed to an
## accountant, and every one of those wants a text file that a program which has never heard of
## Godot can read. A `.tres` names script paths and class names, so it is editable only by this
## build of this project (REQ-B7).
##
## A book is **versioned**, and that version is what an estimate records. Prices change; an estimate
## that was priced from v3 must still cost the same after the book becomes v4, which is only true if
## the estimate copied what it needed (REQ-B6) and the book states which version it was.

const MoneyScript := preload("res://scripts/biz/money.gd")
const TaxScript := preload("res://scripts/biz/tax.gd")
const ItemScript := preload("res://scripts/biz/cost_item.gd")
const KitScript := preload("res://scripts/biz/cost_kit.gd")
const WorkUnitScript := preload("res://scripts/biz/work_unit.gd")

const DEFAULT_PATH := "user://biz/costbook.json"
## What a save goes through on its way to the real file (§2.3, and the same rule as a drawing).
const TEMP_SUFFIX := ".writing"

## How deep a kit may nest. A cycle is refused outright; this catches the other runaway case, a
## generated book that is merely deep, which would otherwise be a hang rather than an answer.
const MAX_DEPTH := 8

var version: int = 1
## ISO date the prices take effect from, so two books can be compared by when they were in force.
var effective_from: String = ""
var currency: StringName = &"CAD"
## Where it came from: a supplier import, a hand edit, a file.
var source: String = ""
## StringName -> CostItem. Keyed by the item's own id, and a query with either a String or a
## StringName finds it, which matters because JSON hands keys back as Strings.
var items: Dictionary = {}
var kits: Dictionary = {}
## StringName -> the same entry shape `Tax.SHIPPED` uses, so a business may ship its own codes with
## its book without a new build.
var tax_codes: Dictionary = {}
## Entries a loaded file carried that could not be used, with the reason. A kit that was in the
## file and is not in this book is not a detail to swallow: a price list that quietly lost a recipe
## is a price list that will price the work wrongly, and it will do it silently.
var rejected: Array[String] = []


func _init(book_version: int = 1, effective: String = "") -> void:
	version = book_version
	effective_from = effective


static func make(book_version: int, effective: String, code: StringName = &"CAD") -> CostBook:
	var book: CostBook = (load("res://scripts/biz/cost_book.gd") as GDScript).new(book_version, effective)
	book.currency = code
	return book


# --- items ------------------------------------------------------------------------------


## Add an item. A duplicate id is refused rather than replaced: changing what a price *is* is a new
## version of the book, and a silent replace is how a catalogue loses a price nobody meant to lose.
func add_item(item: CostItem) -> bool:
	if item == null or not item.is_valid() or items.has(item.id):
		return false
	items[item.id] = item
	return true


## Add or replace, for an importer that has already decided this is the item's new price.
func put_item(item: CostItem) -> bool:
	if item == null or not item.is_valid():
		return false
	items[item.id] = item
	return true


func item(id: StringName) -> CostItem:
	return items.get(id, null) as CostItem


func has_item(id: StringName) -> bool:
	return items.has(id)


func erase_item(id: StringName) -> bool:
	return items.erase(id)


func item_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: Variant in items.keys():
		out.append(StringName(key))
	out.sort()
	return out


# --- kits -------------------------------------------------------------------------------


func add_kit(kit: CostKit) -> bool:
	if kit == null or not kit.is_valid() or kits.has(kit.id):
		return false
	kits[kit.id] = kit
	return true


func put_kit(kit: CostKit) -> bool:
	if kit == null or not kit.is_valid():
		return false
	kits[kit.id] = kit
	return true


func kit(id: StringName) -> CostKit:
	return kits.get(id, null) as CostKit


func has_kit(id: StringName) -> bool:
	return kits.has(id)


func erase_kit(id: StringName) -> bool:
	return kits.erase(id)


func kit_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: Variant in kits.keys():
		out.append(StringName(key))
	out.sort()
	return out


# --- tax codes --------------------------------------------------------------------------


## A book may carry its own codes. Anything it does not define comes from the shipped table, so a
## book that says nothing about tax is still a book that can price a line.
func has_tax_code(id: StringName) -> bool:
	return tax_codes.has(id) or TaxScript.has(id)


func tax_code(id: StringName) -> Dictionary:
	if tax_codes.has(id):
		var own: Variant = tax_codes[id]
		if own is Dictionary:
			return own
	return TaxScript.code(id)


func add_tax_code(id: StringName, entry: Dictionary) -> bool:
	if id.is_empty() or not entry.has("components"):
		return false
	tax_codes[id] = entry.duplicate(true)
	return true


# --- expansion --------------------------------------------------------------------------


## Expand a kit into the lines it makes, for `made_milli` of its output.
##
## Returns `{ok, reason, lines}`. Each line is `{item_id, quantity_milli, unit, kind, cost_code,
## tax_code, note}`: the item resolved, its quantity scaled from the recipe by one rounding rule,
## and **the item's own** cost and tax code kept - so a kit that spans materials, labour and a
## subcontract still costs to the right phases (§5.3).
##
## It refuses rather than looping, on a cycle (naming the chain) and on nesting deeper than
## `MAX_DEPTH`. Repeated items are deliberately **not** merged: the estimate groups lines by cost
## code, and a merged expansion would no longer be the recipe the book states.
func expand_kit(kit_id: StringName, made_milli: int = 1000) -> Dictionary:
	var out: Array = []
	var reason: String = _expand_into(kit_id, made_milli, [], out, &"")
	if not reason.is_empty():
		return {"ok": false, "reason": reason, "lines": []}
	return {"ok": true, "reason": "", "lines": out}


func _expand_into(
	kit_id: StringName, made_milli: int, chain: Array, out: Array, named_by: StringName
) -> String:
	if chain.has(kit_id):
		return "cost kit %s is circular: %s" % [kit_id, _chain_text(chain, kit_id)]
	if chain.size() >= MAX_DEPTH:
		return "cost kit %s nests deeper than %d: %s" % [
			kit_id, MAX_DEPTH, _chain_text(chain, kit_id)
		]
	if made_milli <= 0:
		return "cost kit %s was asked for a quantity of %d, which is not a quantity" % [
			kit_id, made_milli
		]
	var kit: CostKit = self.kit(kit_id)
	if kit == null:
		return "there is no cost kit %s in this book%s" % [kit_id, _named_by_text(named_by)]
	chain.append(kit_id)
	for index in kit.lines.size():
		var line: Dictionary = kit.line_at(index)
		var line_id: StringName = line["item_id"]
		var quantity: int = KitScript.scaled_quantity(
			int(line["quantity_milli"]), made_milli, kit.yield_milli
		)
		if quantity <= 0:
			# A ratio so small that a recipe line rounds away: not an error, but it must not be
			# reported as a line that was priced, so it is left out and the reason is the maths.
			continue
		var nested: CostKit = self.kit(line_id)
		if nested != null:
			var reason: String = _expand_into(line_id, quantity, chain, out, kit_id)
			if not reason.is_empty():
				return reason
			continue
		var item: CostItem = self.item(line_id)
		if item == null:
			return "cost kit %s names %s, which is not an item or a kit in this book" % [
				kit_id, line_id
			]
		out.append({
			"item_id": item.id,
			"quantity_milli": quantity,
			"unit": item.unit,
			"kind": item.kind,
			"cost_code": item.cost_code,
			"tax_code": item.tax_code,
			"note": String(line["note"]) if not String(line["note"]).is_empty() else item.note,
		})
	chain.pop_back()
	return ""


static func _chain_text(chain: Array, repeated: StringName) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for step: Variant in chain:
		parts.append(String(step))
	parts.append(String(repeated))
	return " -> ".join(parts)


static func _named_by_text(named_by: StringName) -> String:
	return "" if named_by.is_empty() else ", named by cost kit %s" % named_by


## Every problem in the book, named, in the order a reader would fix them. An empty list is a book
## that can be priced from.
##
## The last check is the interesting one: it expands every kit, which is how a cycle or a runaway
## nesting is found *before* an estimate is priced from the book rather than at the moment a
## customer is waiting for a number.
func problems() -> Array[String]:
	var out: Array[String] = []
	# First, what a load could not use at all: those are the entries that are *missing* from a book
	# somebody believes they have.
	out.append_array(rejected)
	if version <= 0:
		out.append("the book has version %d, so an estimate could not say which prices it used" % version)
	if effective_from.is_empty():
		out.append("the book has no effective date")
	for id: StringName in item_ids():
		var item: CostItem = self.item(id)
		var problem: String = item.problem()
		if not problem.is_empty():
			out.append(problem)
			continue
		if item.rate.currency != currency:
			out.append("cost item %s is priced in %s, and the book is in %s" % [
				id, item.rate.currency, currency
			])
		if not has_tax_code(item.tax_code):
			out.append("cost item %s names tax code %s, which is not a code" % [id, item.tax_code])
	for id: StringName in kit_ids():
		var kit: CostKit = self.kit(id)
		var problem: String = kit.problem()
		if not problem.is_empty():
			out.append(problem)
			continue
		var expanded: Dictionary = expand_kit(id, 1000)
		if not bool(expanded["ok"]):
			out.append(String(expanded["reason"]))
	return out


func is_sound() -> bool:
	return problems().is_empty()


func item_count() -> int:
	return items.size()


func kit_count() -> int:
	return kits.size()


func describe() -> String:
	return "Cost book v%d (%s), %d item%s, %d kit%s, %s" % [
		version, effective_from if not effective_from.is_empty() else "no date",
		items.size(), "" if items.size() == 1 else "s",
		kits.size(), "" if kits.size() == 1 else "s", currency,
	]


func copy() -> CostBook:
	return from_dict(to_dict())


## The next version of this book, with its own effective date. A price that changed is a new
## version and a new date - never an edit to the one an estimate was priced from.
func bump_version(effective: String) -> CostBook:
	var next: CostBook = copy()
	next.version = version + 1
	next.effective_from = effective
	return next


# --- persistence ------------------------------------------------------------------------


func to_dict() -> Dictionary:
	var out_items: Dictionary = {}
	for key: Variant in items.keys():
		var item: CostItem = items[key]
		out_items[String(item.id)] = item.to_dict()
	var out_kits: Dictionary = {}
	for key: Variant in kits.keys():
		var kit: CostKit = kits[key]
		out_kits[String(kit.id)] = kit.to_dict()
	var out_taxes: Dictionary = {}
	for key: Variant in tax_codes.keys():
		var entry: Variant = tax_codes[key]
		if entry is Dictionary:
			out_taxes[String(key)] = (entry as Dictionary).duplicate(true)
	return {
		"version": version,
		"effective_from": effective_from,
		"currency": String(currency),
		"source": source,
		"items": out_items,
		"kits": out_kits,
		"tax_codes": out_taxes,
	}


## The book as text a bookkeeper can open. Indented, because the first reader of a cost book is a
## person.
func to_json() -> String:
	return JSON.stringify(to_dict(), "  ")


static func from_dict(data: Dictionary) -> CostBook:
	var book: CostBook = (load("res://scripts/biz/cost_book.gd") as GDScript).new()
	book.version = int(data.get("version", 1))
	book.effective_from = String(data.get("effective_from", ""))
	book.currency = StringName(data.get("currency", "CAD"))
	book.source = String(data.get("source", ""))
	var raw_items: Variant = data.get("items", {})
	if raw_items is Dictionary:
		for key: Variant in (raw_items as Dictionary).keys():
			var entry: Variant = (raw_items as Dictionary)[key]
			if not (entry is Dictionary):
				book.rejected.append("cost item %s is not an object" % key)
				continue
			var item: CostItem = ItemScript.from_dict(entry)
			if not book.put_item(item):
				book.rejected.append("cost item %s was in the book but is not usable: %s" % [
					key, item.problem()
				])
	var raw_kits: Variant = data.get("kits", {})
	if raw_kits is Dictionary:
		for key: Variant in (raw_kits as Dictionary).keys():
			var entry: Variant = (raw_kits as Dictionary)[key]
			if not (entry is Dictionary):
				book.rejected.append("cost kit %s is not an object" % key)
				continue
			var kit: CostKit = KitScript.from_dict(entry)
			if not book.add_kit(kit):
				book.rejected.append("cost kit %s was in the book but is not usable: %s" % [
					key, kit.problem()
				])
	var raw_taxes: Variant = data.get("tax_codes", {})
	if raw_taxes is Dictionary:
		for key: Variant in (raw_taxes as Dictionary).keys():
			var entry: Variant = (raw_taxes as Dictionary)[key]
			if entry is Dictionary:
				book.add_tax_code(StringName(key), entry)
	return book


## Write the book. Through a temporary file and a rename, so that a save which fails cannot leave a
## shorter book where the prices used to be.
func save_to(path: String = DEFAULT_PATH) -> Dictionary:
	var folder: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(folder):
		if DirAccess.make_dir_recursive_absolute(folder) != OK:
			return {"ok": false, "reason": "the folder %s cannot be made" % folder, "path": path}
	var temp: String = path + TEMP_SUFFIX
	var file: FileAccess = FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "reason": "the cost book cannot be written to %s" % path, "path": path}
	file.store_string(to_json())
	file.close()
	if DirAccess.rename_absolute(temp, path) != OK:
		return {"ok": false, "reason": "the written cost book could not be moved into place", "path": path}
	return {"ok": true, "reason": "", "path": path}


## Read a book from a file. Returns `{ok, reason, book}`.
##
## A book with no version is refused rather than defaulted: everything downstream records which
## version it priced from, and a book that cannot say is a book whose estimates cannot explain
## themselves.
static func load_from(path: String = DEFAULT_PATH) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "reason": "there is no cost book at %s" % path, "book": null}
	var text: String = file.get_as_text()
	file.close()
	var reader := JSON.new()
	if reader.parse(text) != OK:
		return {
			"ok": false,
			"reason": "%s is not readable JSON: %s (line %d)" % [
				path, reader.get_error_message(), reader.get_error_line()
			],
			"book": null,
		}
	if not (reader.data is Dictionary):
		return {"ok": false, "reason": "%s is not a cost book: it is not a JSON object" % path, "book": null}
	var data: Dictionary = reader.data
	if not data.has("version"):
		return {
			"ok": false,
			"reason": "%s has no version, so an estimate priced from it could not say which prices it used" % path,
			"book": null,
		}
	return {"ok": true, "reason": "", "book": from_dict(data)}