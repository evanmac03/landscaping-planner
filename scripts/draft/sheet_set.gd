class_name DraftSheetSet
extends RefCounted
## The sheets a drawing is plotted as: a *set*, not a pile of separate plots.
##
## A garden leaves the office as several sheets, not one. The layout plan is read at 1:200 on a big
## sheet to see how the whole property works; the planting plan is read at 1:100 on a smaller one
## because its subject is the beds and there are more of them; and a set arrives among other sets, so
## each sheet carries a drawing number - L1.1, L1.2 - rather than being the only sheet in the world.
##
## ## A sheet is paper, not geometry
##
## The drawing is the model. Every sheet in the set is that one drawing framed on its own sheet at its
## own scale, carrying its own identifying text and its own revision. A sheet therefore holds a title,
## a number, a revision, a paper size, a scale, whether it carries the layer key, and whether the sheet
## is turned to portrait - and **nothing else**. That is the property that keeps a set from quietly
## becoming a second copy of the drawing, which is what happens the moment a sheet is allowed to own
## entities: the same bed then exists twice and the two drift.
##
## ## What it is for
##
## A designer who plots twice - once for the planting and once for the layout - otherwise has to set
## the scale, the sheet size and the title block again between the two, and remembers the second time
## badly. With a set those are properties that persist, and plotting the set writes each sheet with the
## wording and the revision that sheet is supposed to carry. Nothing is switched by hand in between.

const PlotScaleScript := preload("res://scripts/draft/plot_scale.gd")

## The drawing-number prefix a sheet is numbered under. A landscape set is numbered under a drawing
## number - L1.1, L1.2 - rather than 1, 2, because a set is one document among the several that go to
## a client, and a sheet called "1" cannot be referred to on the telephone.
const PREFIX := "L1."

## The fields a sheet has, in the order a title block reads them. One list, so that `to_dict`, `from_dict`
## and every editor of a set cannot come to disagree about what a sheet is.
const FIELDS: Array[String] = ["title", "number", "revision", "sheet", "scale", "legend", "portrait"]

## What a sheet that says nothing is called. A sheet of a set says which drawing it is, so the default is
## the title this app has always plotted a drawing under: a fresh set then reaches the title block with
## exactly the words this build produced before sets existed, and the designer edits what differs.
const DEFAULT_TITLE := "Landscaping Plan"

## How many sheets a set may hold. Not a technical limit: it is the point at which a set has stopped
## being a set and become a document nobody scrolls to the bottom of.
const LIMIT := 24

## The size and scale a drawing is plotted at until somebody says otherwise. `"A3"` beside the
## plotter's own default, so a set with nothing set up plots exactly what this app plotted before
## sets existed.
const DEFAULT_SHEET := "A3"
const DEFAULT_SCALE := 100.0

var _sheets: Array[Dictionary] = []
var _current: int = 0

## What every sheet of the set shares: the job it belongs to, and the date it was drawn.
##
## Set-level rather than per-sheet, because a set is one transmittal - a client receives several sheets
## of one job on one date - and a date retyped on the second sheet is a title block that disagrees with
## the first. They are empty until somebody says otherwise, and an empty one is left out of the plot
## options so the plotter's own default stands: no date means today.
var project: String = ""
var date: String = ""


func _init() -> void:
	add(DEFAULT_TITLE)


# --- a sheet ------------------------------------------------------------------------


## A new sheet: the paper the drawing is already plotted at, because the second sheet of a drawing is
## usually the same paper as the first, and the key on.
static func make_sheet(title: String, number: String, over: Dictionary = {}) -> Dictionary:
	var row: Dictionary = {
		"title": title.strip_edges() if not title.strip_edges().is_empty() else DEFAULT_TITLE,
		"number": number,
		"revision": "",
		"sheet": DEFAULT_SHEET,
		"scale": DEFAULT_SCALE,
		"legend": true,
		"portrait": false,
	}
	for field: String in FIELDS:
		if over.has(field):
			row[field] = _coerce(field, over[field])
	return row


## One field of a sheet as the kind of value it is. A number that arrives from JSON is a float and a
## flag that arrives from JSON is a float too, so both are coerced where a sheet is built rather than
## at each of the places that reads them.
static func _coerce(field: String, value: Variant) -> Variant:
	match field:
		"scale":
			return float(value)
		"legend", "portrait":
			return bool(value)
		_:
			return String(value)


# --- the set ------------------------------------------------------------------------


func count() -> int:
	return _sheets.size()


func is_valid(index: int) -> bool:
	return index >= 0 and index < _sheets.size()


func current_index() -> int:
	return _current


func current() -> Dictionary:
	return sheet(_current)


## One sheet, or an empty dictionary. Read-only by convention: a caller that wants to change a sheet
## says so through `set_field`, which is where a typo in a field name is caught.
func sheet(index: int) -> Dictionary:
	if not is_valid(index):
		return {}
	return _sheets[index]


func select(index: int) -> bool:
	if not is_valid(index):
		return false
	_current = index
	return true


## What each sheet is called, in order. Enough to draw a list, and the thing a test reads when it
## wants to know what the set says without knowing how a sheet is stored.
func titles() -> Array[String]:
	var out: Array[String] = []
	for row: Dictionary in _sheets:
		out.append(String(row["title"]))
	return out


func numbers() -> Array[String]:
	var out: Array[String] = []
	for row: Dictionary in _sheets:
		out.append(String(row["number"]))
	return out


## The next number in the sequence, skipping one already in use - so removing the first sheet and
## adding another does not produce two L1.1s.
func next_number() -> String:
	var taken: Array[String] = numbers()
	var step: int = 1
	while taken.has("%s%d" % [PREFIX, step]):
		step += 1
	return "%s%d" % [PREFIX, step]


## Add a sheet and make it the current one. Returns its index, or the current index when the set is
## full: a set that silently grew without bound would be a list nobody could reach the bottom of.
func add(title: String = DEFAULT_TITLE, over: Dictionary = {}) -> int:
	if _sheets.size() >= LIMIT:
		return _current
	_sheets.append(make_sheet(title, next_number(), over))
	_current = _sheets.size() - 1
	return _current


## Take a sheet out of the set. The last one cannot go: a drawing always plots as at least one sheet,
## and a set of nothing is a set with nowhere to put the drawing.
func remove(index: int) -> bool:
	if _sheets.size() <= 1 or not is_valid(index):
		return false
	_sheets.remove_at(index)
	_current = clampi(_current, 0, _sheets.size() - 1)
	return true


## Move a sheet up (-1) or down (+1) the set. The order of a set is the order somebody reads it, so
## moving a sheet is a real edit rather than a nicety. Returns where the sheet is now - which is where it
## already was when it is at the top and asked to move up - or -1 when there is no such sheet.
func move(index: int, delta: int) -> int:
	if not is_valid(index):
		return -1
	var to: int = clampi(index + delta, 0, _sheets.size() - 1)
	if to == index:
		return index
	var row: Dictionary = _sheets[index]
	_sheets.remove_at(index)
	_sheets.insert(to, row)
	if _current == index:
		_current = to
	return to


## Set one field of one sheet. Refuses an unknown field and a value of the wrong kind, rather than
## storing it and letting the plotter find out.
func set_field(index: int, field: String, value: Variant) -> bool:
	if not is_valid(index) or not FIELDS.has(field):
		return false
	match field:
		"scale":
			if not (value is float or value is int):
				return false
		"legend", "portrait":
			if not (value is bool or value is int or value is float):
				return false
		_:
			if not value is String and not value is StringName:
				return false
	_sheets[index][field] = _coerce(field, value)
	return true


## Number every sheet from its place in the set: L1.1, L1.2, L1.3. Offered as a command rather than
## done on every edit, because a hand-typed number is often the reason a set matches the drawing it
## belongs to, and renumbering takes those away.
func renumber() -> void:
	for index in _sheets.size():
		_sheets[index]["number"] = "%s%d" % [PREFIX, index + 1]


## One sheet described in words, the way a set is listed in a transmittal: its number and title, what
## it is drawn at, and its revision.
func describe(index: int) -> String:
	var row: Dictionary = sheet(index)
	if row.is_empty():
		return ""
	var size: String = String(row["sheet"])
	if bool(row["portrait"]):
		size += " portrait"
	var revision := String(row["revision"]).strip_edges()
	var words := "%s  %s  %s on %s" % [
		String(row["number"]), String(row["title"]), PlotScaleScript.metric_label(float(row["scale"])), size
	]
	if not revision.is_empty():
		words += "  rev " + revision
	return words


## Everything the plotter needs for one sheet of the set, laid over the options the caller already
## builds. This is the whole of what plotting a sheet is: the set says what the sheet is, and the
## plotter does the rest.
func options_for(index: int, base: Dictionary = {}) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	if not is_valid(index):
		return out
	var row: Dictionary = _sheets[index]
	out["sheet"] = String(row["sheet"])
	out["scale"] = float(row["scale"])
	out["legend"] = bool(row["legend"])
	out["portrait"] = bool(row["portrait"])
	out["drawing"] = String(row["title"])
	out["revision"] = String(row["revision"])
	out["number"] = String(row["number"])
	# Only when they have been stated: an empty project or date is not an instruction to draw nothing
	# there, it is the absence of an instruction, and the plotter's own default is what should stand.
	if not project.strip_edges().is_empty():
		out["project"] = project
	if not date.strip_edges().is_empty():
		out["date"] = date
	return out


# --- what a file keeps --------------------------------------------------------------


func to_dict() -> Dictionary:
	var rows: Array = []
	for row: Dictionary in _sheets:
		var kept: Dictionary = {}
		for field: String in FIELDS:
			kept[field] = row[field]
		rows.append(kept)
	return {"current": _current, "project": project, "date": date, "sheets": rows}


## Read a set back. Anything it cannot understand becomes the default set rather than an error: a set
## is not worth refusing to open a drawing over, and one sheet of A3 is the drawing this app plotted
## before sets existed.
static func from_dict(data: Variant) -> DraftSheetSet:
	var made := DraftSheetSet.new()
	made._sheets = []
	if data is Dictionary and data.get("sheets") is Array and not (data["sheets"] as Array).is_empty():
		made.project = String(data.get("project", ""))
		made.date = String(data.get("date", ""))
		for record: Variant in data["sheets"]:
			if not record is Dictionary:
				continue
			var row: Dictionary = make_sheet(DEFAULT_TITLE, "", record)
			made._sheets.append(row)
		made._current = clampi(int(data.get("current", 0)), 0, made._sheets.size() - 1)
	if made._sheets.is_empty():
		made.add(DEFAULT_TITLE)
	return made