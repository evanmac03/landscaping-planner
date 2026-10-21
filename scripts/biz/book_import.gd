class_name BizBookImport
extends RefCounted
## A supplier's price list, read into a proposed change to a cost book (§12: "bulk price update with
## an effective date and a preview of what it changes").
##
## The importer reads a CSV, matches its rows to the items a book already has, and produces a
## **plan**: what would change, from what to what, and what it could not match. It never edits a book.
## `apply` returns a *new version*, so an estimate priced from the old one keeps the prices it was
## priced with (REQ-B6, AC-B7) - a cost book that could be edited in place would move a proposal that
## has already gone to a customer.
##
## Three rules it will not break, all of them this module's own:
##
## * **Refuse and name.** A row whose cost will not read, whose unit is not a unit, whose kind is not
##   a kind, or whose id appears twice names its line number and the text it could not read. A price
##   that will not read is not a price of zero (§5.4).
## * **Never invent.** A row naming an item the book does not have is reported as unmatched rather
##   than created, unless the caller asks for `allow_new` - a supplier's list is not the authority on
##   what a business' catalogue contains.
## * **Nothing here reads a clock.** The effective date is an argument.
##
## All of it is static: the importer holds no state between a file and a plan.

const MoneyScript := preload("res://scripts/biz/money.gd")
const BookScript := preload("res://scripts/biz/cost_book.gd")
const ItemScript := preload("res://scripts/biz/cost_item.gd")
const UnitScript := preload("res://scripts/biz/work_unit.gd")
const RateScript := preload("res://scripts/biz/rate.gd")

## The column headings this understands, written the way a header is written once it has been
## lowercased and stripped of spaces, dashes and underscores. A supplier's spreadsheet is made by a
## person, so "Unit Cost", "unit-cost" and "UNIT COST" are one column.
const ALIASES := {
	"id": ["id", "code", "sku", "itemid", "itemcode", "productcode", "catalogue", "catalog"],
	"name": ["name", "description", "itemname", "desc", "product", "item"],
	"unit": ["unit", "uom", "units", "measure", "unitofmeasure"],
	"cost": ["cost", "price", "rate", "unitcost", "unitprice", "costeach", "ourprice", "netprice"],
	"kind": ["kind", "type", "category", "class"],
	"supplier": ["supplier", "vendor", "from"],
	"cost_code": ["costcode", "phase", "section", "division", "stage"],
	"waste": ["waste", "wastepercent", "wasteppm"],
}

## The unit spellings a supplier writes, mapped to the unit ids the module uses. The unit table stays
## the one place a unit is defined, so "sq ft" becomes `SQ_FT` and no second list of dimensions is
## born here.
const UNIT_WORDS := {
	"each": "EACH", "ea": "EACH", "unit": "EACH", "#": "EACH",
	"m": "LIN_M", "linm": "LIN_M", "lm": "LIN_M", "linearm": "LIN_M",
	"metre": "LIN_M", "meter": "LIN_M", "linearmetre": "LIN_M", "linearmeter": "LIN_M",
	"ft": "LIN_FT", "linft": "LIN_FT", "lf": "LIN_FT", "linearft": "LIN_FT",
	"foot": "LIN_FT", "feet": "LIN_FT",
	"m2": "SQ_M", "sqm": "SQ_M", "squaremetre": "SQ_M", "squaremeter": "SQ_M",
	"ft2": "SQ_FT", "sqft": "SQ_FT", "squarefoot": "SQ_FT", "squarefeet": "SQ_FT",
	"m3": "CU_M", "cum": "CU_M", "cubicmetre": "CU_M", "cubicmeter": "CU_M",
	"yd3": "CU_YD", "cuyd": "CU_YD", "cubicyard": "CU_YD", "cubicyards": "CU_YD",
	"yard": "CU_YD", "yards": "CU_YD",
	"hour": "HOUR", "hr": "HOUR", "hours": "HOUR", "h": "HOUR",
	"day": "DAY", "days": "DAY",
	"load": "LOAD", "loads": "LOAD",
}

## A supplier's list longer than this is a mistake being read as a catalogue.
const MAX_ROWS := 5000


# --- reading the file -------------------------------------------------------------------------


## Read the text of a CSV into rows. Returns `{ok, reason, rows, problems}`.
##
## `rows` holds every line that could be read, each carrying its own problem list; a row with a
## problem is **kept and named** rather than dropped, because a supplier's list with one unreadable
## cost is a list to fix, not a list to lose. `problems` is the flattened list for a status line.
static func read_csv(text: String, currency: StringName = &"CAD") -> Dictionary:
	var lines: PackedStringArray = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	var header: PackedStringArray = PackedStringArray()
	var columns: Dictionary = {}
	var rows: Array[Dictionary] = []
	var line_number: int = 0
	for raw: String in lines:
		line_number += 1
		var line: String = raw.strip_edges()
		if line.is_empty():
			continue
		var cells: PackedStringArray = _split(raw)
		if header.is_empty():
			header = cells
			columns = _columns_of(cells)
			if not columns.has("cost") or (not columns.has("id") and not columns.has("name")):
				return {
					"ok": false,
					"reason": "the first line names no cost column, or no id and no name: it reads \"%s\"" % line,
					"rows": [],
					"problems": [],
				}
			continue
		if rows.size() >= MAX_ROWS:
			return {
				"ok": false,
				"reason": "this file has more than %d price rows, which is a wrong file rather than a long one" % MAX_ROWS,
				"rows": [],
				"problems": [],
			}
		rows.append(_row_of(cells, columns, line_number, currency))
	if header.is_empty():
		return {
			"ok": false,
			"reason": "there is no heading line in this file, so nothing says which column a price is in",
			"rows": [],
			"problems": [],
		}
	var problems: Array[String] = []
	for row: Dictionary in rows:
		for problem: String in row["problems"]:
			problems.append(problem)
	return {"ok": true, "reason": "", "rows": rows, "problems": problems}


## Which cell holds which field, from the heading line. A heading nobody wrote is simply absent, and
## a heading written twice keeps the first: a spreadsheet that names "Cost" twice is one column.
static func _columns_of(headings: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for index in headings.size():
		var key: String = _column_key(headings[index])
		for field: String in ALIASES.keys():
			if out.has(field):
				continue
			for word: String in ALIASES[field]:
				if key == word:
					out[field] = index
					break
	return out


## A heading reduced to the form the alias table is written in.
static func _column_key(heading: String) -> String:
	return heading.strip_edges().to_lower().replace("-", "").replace("_", "").replace(" ", "")


static func _cell(cells: PackedStringArray, columns: Dictionary, field: String) -> String:
	if not columns.has(field):
		return ""
	var index: int = int(columns[field])
	if index < 0 or index >= cells.size():
		return ""
	return cells[index].strip_edges()


## One line, as a row with everything it could not tell us named.
static func _row_of(
	cells: PackedStringArray, columns: Dictionary, line_number: int, currency: StringName
) -> Dictionary:
	var problems: Array[String] = []
	var id: String = _cell(cells, columns, "id")
	var item_name: String = _cell(cells, columns, "name")
	if id.is_empty() and item_name.is_empty():
		problems.append("line %d names neither an id nor a name" % line_number)

	var cost_text: String = _cell(cells, columns, "cost")
	var amount: Money = MoneyScript.parse(cost_text, currency)
	if not amount.is_valid():
		problems.append("line %d has a cost this cannot read: \"%s\"" % [line_number, cost_text])

	var unit_text: String = _cell(cells, columns, "unit")
	var unit: StringName = &""
	if unit_text.is_empty():
		unit = &"EACH"
	else:
		unit = _unit_for(unit_text)
		if unit.is_empty():
			problems.append("line %d is priced in \"%s\", which is not a unit this knows" % [
				line_number, unit_text
			])

	var kind_text: String = _cell(cells, columns, "kind")
	var kind: int = ItemScript.MATERIAL
	if not kind_text.is_empty():
		var found: int = _kind_for(kind_text)
		if found < 0:
			problems.append("line %d is a \"%s\", which is not a kind of thing" % [line_number, kind_text])
		else:
			kind = found

	var waste_text: String = _cell(cells, columns, "waste")
	var waste_ppm: int = 0
	if not waste_text.is_empty():
		var waste: Dictionary = _waste_for(waste_text)
		if not bool(waste["ok"]):
			problems.append("line %d: %s" % [line_number, String(waste["reason"])])
		else:
			waste_ppm = int(waste["ppm"])

	return {
		"line": line_number,
		"id": StringName(id),
		"name": item_name,
		"unit": unit,
		"unit_text": unit_text,
		"kind": kind,
		"kind_text": kind_text,
		"cost": amount,
		"cost_text": cost_text,
		"waste_ppm": waste_ppm,
		"supplier": StringName(_cell(cells, columns, "supplier")),
		"cost_code": StringName(_cell(cells, columns, "cost_code")),
		"currency": currency,
		"problems": problems,
	}


## A unit id, from however the supplier wrote it.
static func _unit_for(words: String) -> StringName:
	var key: String = _flat(words)
	var candidate: StringName = StringName(key.to_upper())
	if UnitScript.has(candidate):
		return candidate
	if UNIT_WORDS.has(key):
		return StringName(UNIT_WORDS[key])
	return &""


## A kind, from however the supplier wrote it: "LABOR", "Labour" and "labour" are one kind.
static func _kind_for(words: String) -> int:
	var key: String = _flat(words)
	for kind: int in ItemScript.KINDS.keys():
		if _flat(String(ItemScript.KINDS[kind])) == key:
			return kind
	return -1


## A waste, as a supplier states it: a percentage. `8`, `8%` and `8.0 %` are eight percent; a
## percentage stated more finely than a hundredth of a percent is refused rather than rounded, and a
## waste past the item's own cap is refused with the cap named - the same two rules a rate follows.
static func _waste_for(words: String) -> Dictionary:
	var text: String = words.strip_edges().replace("%", "").strip_edges()
	if not text.is_valid_float():
		return {"ok": false, "reason": "\"%s\" is not a percentage" % words, "ppm": 0}
	var percent: float = text.to_float()
	var exact: float = percent * 10000.0
	var ppm: int = int(round(exact))
	if absf(exact - float(ppm)) > 0.001:
		return {
			"ok": false,
			"reason": "\"%s\" states a waste finer than a hundredth of a percent" % words,
			"ppm": 0,
		}
	if ppm < 0 or ppm > ItemScript.MAX_WASTE_PPM:
		return {
			"ok": false,
			"reason": "\"%s\" is outside 0%%..%.2f%%" % [
				words, float(ItemScript.MAX_WASTE_PPM) / 10000.0
			],
			"ppm": 0,
		}
	return {"ok": true, "reason": "", "ppm": ppm}


static func _flat(words: String) -> String:
	return words.strip_edges().to_lower().replace("-", "").replace("_", "").replace(" ", "")


## Split one line on commas, honouring quotes and a doubled quote inside them - the one piece of CSV
## that cannot be got out with `split(",")`.
static func _split(line: String) -> PackedStringArray:
	var cells: PackedStringArray = PackedStringArray()
	var cell: String = ""
	var quoted: bool = false
	var index: int = 0
	while index < line.length():
		var character: String = line[index]
		if quoted:
			if character == "\"":
				if index + 1 < line.length() and line[index + 1] == "\"":
					cell += "\""
					index += 1
				else:
					quoted = false
			else:
				cell += character
		elif character == "\"":
			quoted = true
		elif character == ",":
			cells.append(cell)
			cell = ""
		else:
			cell += character
		index += 1
	cells.append(cell)
	return cells


# --- the plan ---------------------------------------------------------------------------------


## What these rows would do to this book: `{ok, reason, changes, unchanged, unmatched, created,
## problems, currency}`.
##
## A **change** is an item whose cost, unit or kind would move; each carries the before and the after
## in cents, so a preview can add them up and a page can show them side by side. A row that agrees
## with the book is `unchanged` rather than a change of nothing, because "12 of 20 prices differ" is
## the figure a person decides on.
static func plan(book: CostBook, rows: Array, allow_new: bool = false) -> Dictionary:
	if book == null:
		return {
			"ok": false, "reason": "there is no cost book to plan against",
			"changes": [], "unchanged": [], "unmatched": [], "created": [], "problems": [],
			"currency": &"",
		}
	var changes: Array[Dictionary] = []
	var unchanged: Array[Dictionary] = []
	var unmatched: Array[Dictionary] = []
	var created: Array[Dictionary] = []
	var problems: Array[String] = []
	var taken: Dictionary = {}

	for row: Dictionary in rows:
		var row_problems: Array = row["problems"]
		if not row_problems.is_empty():
			for problem: String in row_problems:
				problems.append(problem)
			continue
		var row_id: StringName = row["id"]
		var row_name: String = row["name"]
		var matched: CostItem = _find(book, row_id, row_name)
		var named: String = row_name if not row_name.is_empty() else String(row_id)

		if matched != null:
			var key: String = String(matched.id)
			if taken.has(key):
				problems.append("line %d and line %d are both about \"%s\", so one of them would win" % [
					int(taken[key]), int(row["line"]), named
				])
				continue
			taken[key] = int(row["line"])
			var entry: Dictionary = _change_entry(matched, row, false)
			if int(entry["delta_cents"]) == 0 and not bool(entry["unit_changed"]) \
					and not bool(entry["kind_changed"]) and not bool(entry["waste_changed"]):
				unchanged.append(entry)
			else:
				changes.append(entry)
			continue

		if not allow_new:
			unmatched.append({
				"line": int(row["line"]),
				"id": String(row_id),
				"name": row_name,
				"cost_cents": int((row["cost"] as Money).cents),
				"reason": "the book has no item called \"%s\", and a supplier's list is not the authority on what the catalogue holds" % named,
			})
			continue
		var fresh: Dictionary = _fresh_entry(book, row)
		if not String(fresh.get("reason", "")).is_empty():
			problems.append("line %d: %s" % [int(row["line"]), String(fresh["reason"])])
			continue
		var fresh_id: String = String(fresh["id"])
		if taken.has(fresh_id):
			problems.append("line %d and line %d are both about \"%s\"" % [
				int(taken[fresh_id]), int(row["line"]), fresh_id
			])
			continue
		taken[fresh_id] = int(row["line"])
		created.append(fresh)

	return {
		"ok": true,
		"reason": "",
		"changes": changes,
		"unchanged": unchanged,
		"unmatched": unmatched,
		"created": created,
		"problems": problems,
		"currency": book.currency,
	}


## The item this row is about: by id when the row names one the book has, otherwise by name when
## exactly one item carries it. Two items of one name is a row that cannot be matched, and saying so
## is better than picking the first.
static func _find(book: CostBook, row_id: StringName, row_name: String) -> CostItem:
	if not row_id.is_empty() and book.has_item(row_id):
		return book.item(row_id)
	var wanted: String = _key(row_name)
	if wanted.is_empty():
		return null
	var found: CostItem = null
	for existing: StringName in book.item_ids():
		if _key(book.item(existing).name) != wanted:
			continue
		if found != null:
			return null
		found = book.item(existing)
	return found


## A name reduced to what two people would agree is the same name.
static func _key(words: String) -> String:
	var out: String = ""
	var last_space: bool = false
	for index in words.strip_edges().to_lower().length():
		var character: String = words.strip_edges().to_lower()[index]
		var letter: bool = character >= "a" and character <= "z"
		var digit: bool = character >= "0" and character <= "9"
		if letter or digit:
			out += character
			last_space = false
		elif not last_space:
			out += " "
			last_space = true
	return out.strip_edges()


static func _change_entry(item: CostItem, row: Dictionary, is_new: bool) -> Dictionary:
	var after: Money = row["cost"]
	return {
		"id": String(item.id),
		"name": item.name,
		"before_cents": int(item.rate.cents),
		"after_cents": int(after.cents),
		"delta_cents": int(after.cents) - int(item.rate.cents),
		"currency": String(item.rate.currency),
		"row_currency": String(row["currency"]),
		"from_unit": String(item.unit),
		"unit": String(row["unit"]),
		"unit_changed": item.unit != row["unit"],
		"kind_changed": item.kind != int(row["kind"]),
		"waste_changed": item.waste_ppm != int(row["waste_ppm"]),
		"kind": int(row["kind"]),
		"waste_ppm": int(row["waste_ppm"]),
		"supplier": String(row["supplier"]),
		"cost_code": String(row["cost_code"]),
		"line": int(row["line"]),
		"is_new": is_new,
	}


## A row that would **add** an item: it is filed under the id it names, or under a slug of its name
## when it names none. Refused rather than invented when an id cannot be made, or when the id is
## already taken - and a taken id in a price list is a row about the existing item, so `plan` has
## already matched it and this branch is the leftover.
static func _fresh_entry(book: CostBook, row: Dictionary) -> Dictionary:
	var row_id: StringName = row["id"]
	if row_id.is_empty():
		row_id = StringName(_slug(row["name"]))
	if row_id.is_empty():
		return {"reason": "a new item needs an id or a name to be filed under"}
	if book.has_item(row_id):
		return {"reason": "the book already has \"%s\"" % row_id}
	var row_name: String = row["name"]
	if row_name.is_empty():
		row_name = String(row_id)
	var after: Money = row["cost"]
	return {
		"id": String(row_id),
		"name": row_name,
		"before_cents": 0,
		"after_cents": int(after.cents),
		"delta_cents": int(after.cents),
		"currency": String(after.currency),
		"row_currency": String(row["currency"]),
		"from_unit": "",
		"unit": String(row["unit"]),
		"unit_changed": false,
		"kind_changed": false,
		"waste_changed": false,
		"kind": int(row["kind"]),
		"waste_ppm": int(row["waste_ppm"]),
		"supplier": String(row["supplier"]),
		"cost_code": String(row["cost_code"]),
		"line": int(row["line"]),
		"is_new": true,
	}


## An id a name can be filed under.
static func _slug(words: String) -> String:
	var key: String = _key(words)
	if key.is_empty():
		return ""
	return key.replace(" ", "-")


# --- putting a plan into a new book ------------------------------------------------------------


## The **next version** of this book, with this plan's prices in it. Returns
## `{ok, reason, book, version, changed}`.
##
## It refuses a plan that changes nothing (there is no new version of a book nobody changed), a
## plan read in another currency (a USD price list applied to a CAD book is a silent 35% error), an
## effective date that does not read as a date, and a plan whose `ok` is false. What it returns is a
## new `CostBook`; the one it was handed is not touched, which is what keeps a stored estimate's
## prices frozen (REQ-B6).
static func apply(
	book: CostBook, change_plan: Dictionary, effective: String, who: String = "", at: int = 0
) -> Dictionary:
	if book == null:
		return {"ok": false, "reason": "there is no cost book to apply a plan to", "book": null, "version": 0, "changed": 0}
	if not bool(change_plan.get("ok", false)):
		return {
			"ok": false, "reason": "this plan did not read: %s" % String(change_plan.get("reason", "")),
			"book": null, "version": 0, "changed": 0,
		}
	var changes: Array = change_plan.get("changes", [])
	var created: Array = change_plan.get("created", [])
	if changes.is_empty() and created.is_empty():
		return {
			"ok": false, "reason": "this plan changes no price, so there is no new version of the book",
			"book": null, "version": 0, "changed": 0,
		}
	if not RateScript.is_date(effective):
		return {
			"ok": false,
			"reason": "\"%s\" is not a date, and a price change without one could not say which prices an estimate used" % effective,
			"book": null, "version": 0, "changed": 0,
		}
	for entry: Dictionary in changes + created:
		var entry_currency: StringName = StringName(entry.get("row_currency", book.currency))
		if entry_currency != book.currency:
			return {
				"ok": false,
				"reason": "this plan is priced in %s and the book is in %s, and the two do not convert" % [
					String(entry_currency), String(book.currency)
				],
				"book": null, "version": 0, "changed": 0,
			}

	var next: CostBook = book.bump_version(effective)
	next.source = _source_text(who, at, changes.size(), created.size())
	var changed: int = 0
	for entry: Dictionary in changes:
		var target: CostItem = next.item(StringName(entry["id"]))
		if target == null:
			continue
		target.rate = MoneyScript.of(int(entry["after_cents"]), next.currency)
		target.unit = StringName(entry["unit"])
		target.kind = int(entry["kind"])
		target.waste_ppm = int(entry["waste_ppm"])
		if not String(entry["supplier"]).is_empty():
			target.supplier = StringName(entry["supplier"])
		if not String(entry["cost_code"]).is_empty():
			target.cost_code = StringName(entry["cost_code"])
		changed += 1
	for entry: Dictionary in created:
		var fresh: CostItem = ItemScript.make(
			StringName(entry["id"]),
			String(entry["name"]),
			StringName(entry["unit"]),
			int(entry["after_cents"]),
			int(entry["kind"]),
			next.currency
		)
		fresh.waste_ppm = int(entry["waste_ppm"])
		fresh.supplier = StringName(entry["supplier"])
		fresh.cost_code = StringName(entry["cost_code"])
		fresh.note = "imported from a supplier price list"
		next.put_item(fresh)
		changed += 1
	var trouble: Array[String] = next.problems()
	if not trouble.is_empty():
		return {
			"ok": false,
			"reason": "the new book would have a problem with it: %s" % String(trouble[0]),
			"book": null, "version": 0, "changed": 0,
		}
	return {"ok": true, "reason": "", "book": next, "version": next.version, "changed": changed}


## Where the new book's prices came from, written into the book itself: the first reader of a cost
## book is a person, and the second is whoever asks a year later why a price moved.
static func _source_text(who: String, at: int, changed: int, created: int) -> String:
	var parts: Array[String] = []
	parts.append("imported price list")
	if not who.is_empty():
		parts.append("by %s" % who)
	if at > 0:
		parts.append("at %s" % Time.get_datetime_string_from_unix_time(at, true))
	parts.append("%d repriced" % changed)
	if created > 0:
		parts.append("%d added" % created)
	return ", ".join(parts)


# --- what a person reads -----------------------------------------------------------------------


## The plan as one line, for a status line or a dock.
static func describe(change_plan: Dictionary) -> String:
	if not bool(change_plan.get("ok", false)):
		return "this price list did not read: %s" % String(change_plan.get("reason", ""))
	var changes: Array = change_plan.get("changes", [])
	var unchanged: Array = change_plan.get("unchanged", [])
	var unmatched: Array = change_plan.get("unmatched", [])
	var created: Array = change_plan.get("created", [])
	var problems: Array = change_plan.get("problems", [])
	return "%d repriced, %d unchanged, %d new, %d unmatched, %d unreadable" % [
		changes.size(), unchanged.size(), created.size(), unmatched.size(), problems.size()
	]