class_name Tax
extends RefCounted
## What is charged on an amount, as a list of components.
##
## Rates are integers in **parts per million** - because a tax rate is exact and a floating
## percentage is not (9.975% as a float is 9.97499999..., and rounding that lands a cent away from the
## authority's own worked example), and because a basis point is too coarse to state 9.975% at all
## (spec §15.2). Components are rounded once each, in order, and a component that compounds is
## charged on the amount *including* the rounded components before it, so the invoice's arithmetic
## is the arithmetic of the published table.
##
## A tax code is data, not code: a book may add its own (a city levy, a hotel tax, a country this
## business has never worked in), which is why nothing here is baked into the estimating engine.
## `EXEMPT` is a different thing from `NONE`: exempt is a *customer's* legal status and prints on
## the invoice, because a customer whose bookkeeper sees no tax line will ask.

const MoneyScript := preload("res://scripts/biz/money.gd")

## The codes that ship with the program, kept separate from the live table because a business adds
## its own - a city levy, another province, another country. (The first version of this file used
## this table as the live one, as a `const`; a test proved that impossible, since a GDScript
## constant is read-only to its contents as well as to its name.)
##
## A rate is an integer in **parts per million** (spec §2.1a): 13% is 130000. A component marked
## `compounds` is charged on what the earlier components added - "QST compounds on GST" marks QST -
## and an unmarked one is charged on the price itself.
const SHIPPED := {
	&"NONE": {"name": "No tax", "components": []},
	&"EXEMPT": {"name": "Exempt", "components": []},
	&"HST-ON": {
		"name": "HST 13%",
		"components": [{"name": "HST", "rate_ppm": 130000, "compounds": false}],
	},
	&"GST-5": {
		"name": "GST 5%",
		"components": [{"name": "GST", "rate_ppm": 50000, "compounds": false}],
	},
	&"GST-PST-BC": {
		"name": "GST 5% + PST 7%",
		"components": [
			{"name": "GST", "rate_ppm": 50000, "compounds": false},
			{"name": "PST", "rate_ppm": 70000, "compounds": false},
		],
	},
	&"GST-QST": {
		# QST has not compounded on GST since 1 January 2013, and a table that compounded it
		# would overcharge every Quebec customer by about half a percent. 9.975% is 99750 parts
		# per million - a rate no basis-point table can hold.
		"name": "GST 5% + QST 9.975%",
		"components": [
			{"name": "GST", "rate_ppm": 50000, "compounds": false},
			{"name": "QST", "rate_ppm": 99750, "compounds": false},
		],
	},
}

## The live table: the shipped codes, plus whatever a book or a business has added.
static var CODES := SHIPPED.duplicate(true)


## Add or replace a code. A code with no name or no component list is refused rather than accepted,
## because a half-written code is a line that silently charges nothing.
static func add_code(id: StringName, entry: Dictionary) -> bool:
	if not entry.has("name") or not entry.has("components"):
		return false
	CODES[id] = entry
	return true


static func erase_code(id: StringName) -> bool:
	if not CODES.has(id):
		return false
	CODES.erase(id)
	return true


## Back to the shipped table: for a test, or for abandoning a bad import.
static func reset_codes() -> void:
	CODES = SHIPPED.duplicate(true)


static func has(id: StringName) -> bool:
	return CODES.has(id)


static func code(id: StringName) -> Dictionary:
	return CODES.get(id, {})


static func components(id: StringName) -> Array:
	return code(id).get("components", [])


static func describe(id: StringName) -> String:
	var entry: Dictionary = code(id)
	if entry.is_empty():
		return "unknown tax code '%s'" % String(id)
	return String(entry.get("name", String(id)))


## The nominal rate in parts per million, for a column header or a report. For a compounding code
## this is the sum of the components rather than the effective rate, which is what `gross` computes.
static func rate_ppm(id: StringName) -> int:
	var total: int = 0
	for component: Dictionary in components(id):
		total += int(component.get("rate_ppm", 0))
	return total


## Charge tax on an amount.
##
## Returns `{"ok", "reason", "components", "tax"}`: `components` is one entry per component with
## the base it was charged on and the amount, which is what an invoice prints and what a
## bookkeeper checks. An unknown code or an unreadable amount is **refused with a reason** rather
## than treated as no tax - a silently untaxed invoice is a legal problem, not a display problem.
static func gross(amount: MoneyScript, id: StringName) -> Dictionary:
	var refused := {
		"ok": false,
		"reason": "",
		"components": [] as Array[Dictionary],
		"tax": MoneyScript.invalid(amount.currency),
	}
	if not has(id):
		refused["reason"] = "unknown tax code '%s'" % String(id)
		return refused
	if not amount.is_valid():
		refused["reason"] = "the amount is not a readable number"
		return refused
	# A component marked `compounds` is charged on what the earlier components added; an unmarked one
	# is charged on the price itself. The flag therefore marks the component that does the
	# compounding - "QST compounds on GST" marks QST - which is how the sentence is written in a tax
	# statute and how a bookkeeper would say it. (The first version marked the earlier component
	# instead, reading the flag as "become part of the base"; a test caught the two meanings
	# disagreeing, which is exactly the kind of quietly-wrong arithmetic a tax table must not have.)
	var charged: Array[Dictionary] = []
	var running: MoneyScript = MoneyScript.zero(amount.currency)
	var compounded: MoneyScript = amount
	for component: Dictionary in components(id):
		var rate: int = int(component.get("rate_ppm", 0))
		var base: MoneyScript = compounded if bool(component.get("compounds", false)) else amount
		var part: MoneyScript = base.scale_ppm(rate)
		charged.append({
			"name": String(component.get("name", "Tax")),
			"rate_ppm": rate,
			"base": base,
			"amount": part,
		})
		running = running.add(part)
		compounded = compounded.add(part)
	return {"ok": true, "reason": "", "components": charged, "tax": running}


## The amount including tax, or the invalid amount when the code is refused.
static func total(amount: MoneyScript, id: StringName) -> MoneyScript:
	var grossed: Dictionary = gross(amount, id)
	if not bool(grossed["ok"]):
		return MoneyScript.invalid(amount.currency)
	var charged: MoneyScript = grossed["tax"]
	return amount.add(charged)