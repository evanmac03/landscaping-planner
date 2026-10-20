extends Node
## Tax: components, parts per million, compounding, and the refusal that keeps an invoice legal.

const MoneyScript := preload("res://scripts/biz/money.gd")
const TaxScript := preload("res://scripts/biz/tax.gd")


func test_hst_is_thirteen_percent_to_the_cent() -> void:
	var grossed: Dictionary = TaxScript.gross(MoneyScript.of(10000, &"CAD"), &"HST-ON")
	assert(bool(grossed["ok"]), String(grossed["reason"]))
	var tax: MoneyScript = grossed["tax"]
	assert(tax.cents == 1300)
	assert(TaxScript.total(MoneyScript.of(10000), &"HST-ON").cents == 11300)
	# The component carries the base it was charged on, because that is what an invoice prints and
	# what a bookkeeper checks.
	var components: Array = grossed["components"]
	assert(components.size() == 1)
	assert(String(components[0]["name"]) == "HST")
	assert(int(components[0]["rate_ppm"]) == 130000)
	var base: MoneyScript = components[0]["base"]
	assert(base.cents == 10000)


func test_two_components_are_charged_on_the_same_base_unless_they_compound() -> void:
	# British Columbia's GST and PST both apply to the price, not one to the other. Charging PST on
	# the GST would overcharge every customer in the province by 35 cents on the hundred.
	var grossed: Dictionary = TaxScript.gross(MoneyScript.of(10000, &"CAD"), &"GST-PST-BC")
	var tax: MoneyScript = grossed["tax"]
	assert(tax.cents == 1200)
	var components: Array = grossed["components"]
	for component: Dictionary in components:
		var base: MoneyScript = component["base"]
		assert(base.cents == 10000, "a non-compounding component is charged on the price")


func test_a_compounding_component_is_charged_on_the_rounded_amount_before_it() -> void:
	# No Canadian jurisdiction compounds today, so this adds one to the table - which is the point
	# of the codes being data rather than code: a business working somewhere that does can add it
	# without touching the engine.
	TaxScript.add_code(&"TEST-COMPOUND", {
		"name": "Test, compounding",
		"components": [
			{"name": "A", "rate_ppm": 50000, "compounds": false},
			{"name": "B", "rate_ppm": 70000, "compounds": true},
		],
	})
	var grossed: Dictionary = TaxScript.gross(MoneyScript.of(10000, &"CAD"), &"TEST-COMPOUND")
	assert(bool(grossed["ok"]))
	# 5% of 100.00 is 5.00; 7% of the 105.00 that results is 7.35; the tax is 12.35.
	var tax: MoneyScript = grossed["tax"]
	assert(tax.cents == 1235)
	var components: Array = grossed["components"]
	var second_base: MoneyScript = components[1]["base"]
	assert(second_base.cents == 10500, "the second component is charged on the first, rounded first")
	assert(TaxScript.erase_code(&"TEST-COMPOUND"))
	# The flag marks the component that *does* the compounding. Marking the earlier one instead is a
	# different table with a different answer, and the engine must not read the two as one.
	TaxScript.add_code(&"TEST-COMPOUND-A", {
		"name": "Test, flag on the first",
		"components": [
			{"name": "A", "rate_ppm": 50000, "compounds": true},
			{"name": "B", "rate_ppm": 70000, "compounds": false},
		],
	})
	var other: Dictionary = TaxScript.gross(MoneyScript.of(10000, &"CAD"), &"TEST-COMPOUND-A")
	var other_tax: MoneyScript = other["tax"]
	assert(other_tax.cents == 1200, "an unmarked component is charged on the price")
	assert(TaxScript.erase_code(&"TEST-COMPOUND-A"))


func test_a_compounding_component_is_charged_on_everything_the_others_added() -> void:
	# Three components: two charged on the price, and a third charged on the price plus both of
	# them. It is the arithmetic of a tax on a tax, and the accumulator has to carry the unmarked
	# components forward too, not only the marked ones.
	TaxScript.add_code(&"TEST-THREE", {
		"name": "Test, three components",
		"components": [
			{"name": "A", "rate_ppm": 50000, "compounds": false},
			{"name": "B", "rate_ppm": 70000, "compounds": false},
			{"name": "C", "rate_ppm": 100000, "compounds": true},
		],
	})
	var grossed: Dictionary = TaxScript.gross(MoneyScript.of(10000, &"CAD"), &"TEST-THREE")
	var tax: MoneyScript = grossed["tax"]
	# 5.00 + 7.00 charged on 100.00, then 10% of the 112.00 those two make: 11.20. Tax 23.20.
	assert(tax.cents == 2320)
	var components: Array = grossed["components"]
	assert(components[0]["base"].cents == 10000)
	assert(components[1]["base"].cents == 10000)
	assert(components[2]["base"].cents == 11200)
	assert(TaxScript.erase_code(&"TEST-THREE"))


func test_a_half_written_code_is_refused() -> void:
	# A code with a rate but no name, or with no components at all, would charge nothing and look
	# like an exemption. It is refused at the door.
	assert(not TaxScript.add_code(&"TEST-HALF", {"name": "Half"}))
	assert(not TaxScript.add_code(&"TEST-HALF", {"components": []}))
	assert(not TaxScript.has(&"TEST-HALF"))
	assert(TaxScript.add_code(&"TEST-ZERO", {"name": "Deliberate zero", "components": []}))
	assert(TaxScript.has(&"TEST-ZERO"))
	assert(TaxScript.erase_code(&"TEST-ZERO"))
	assert(not TaxScript.erase_code(&"NEVER-WAS"))


func test_the_component_amounts_add_to_the_tax() -> void:
	# An invoice prints one line per component and a total. Those have to agree, or the customer's
	# own adding-up disagrees with the invoice's.
	for cents in [12345, 999, 1, 100000000]:
		var grossed: Dictionary = TaxScript.gross(MoneyScript.of(cents, &"CAD"), &"GST-QST")
		var parts: Array = []
		for component: Dictionary in grossed["components"]:
			parts.append(component["amount"])
		var tax: MoneyScript = grossed["tax"]
		assert(MoneyScript.sum(parts).cents == tax.cents, "parts add to the whole at %d" % cents)
	# Worked by hand: GST at 5% of 123.45 is 6.17 (6.1725 rounded away from zero); QST at 9.975% is
	# 12.31 (12.3141375 rounded down - and 9.975% is a rate a basis-point table cannot state at all);
	# the tax is 18.48 and the invoice total is 141.93.
	var worked: Dictionary = TaxScript.gross(MoneyScript.of(12345, &"CAD"), &"GST-QST")
	var worked_tax: MoneyScript = worked["tax"]
	assert(worked_tax.cents == 1848)
	assert(worked["components"][0]["amount"].cents == 617)
	assert(worked["components"][1]["amount"].cents == 1231)
	assert(TaxScript.total(MoneyScript.of(12345), &"GST-QST").cents == 14193)
	assert(TaxScript.rate_ppm(&"GST-QST") == 149750, "the nominal 14.975%")


func test_an_unknown_tax_code_is_refused_rather_than_treated_as_no_tax() -> void:
	# A missing tax code is not a tax rate of zero. It is a question somebody has to answer.
	var grossed: Dictionary = TaxScript.gross(MoneyScript.of(10000, &"CAD"), &"NOT-A-CODE")
	assert(not bool(grossed["ok"]))
	assert(String(grossed["reason"]).contains("unknown tax code"))
	var tax: MoneyScript = grossed["tax"]
	assert(not tax.is_valid())
	assert(not TaxScript.total(MoneyScript.of(10000), &"NOT-A-CODE").is_valid())
	assert(TaxScript.describe(&"NOT-A-CODE").contains("unknown"))


func test_exempt_is_a_zero_charge_and_not_a_missing_one() -> void:
	# EXEMPT and NONE both charge nothing and print differently, because exempt is a legal status
	# the customer's bookkeeper will look for.
	var exempt: Dictionary = TaxScript.gross(MoneyScript.of(10000, &"CAD"), &"EXEMPT")
	assert(bool(exempt["ok"]))
	var tax: MoneyScript = exempt["tax"]
	assert(tax.cents == 0)
	assert(TaxScript.describe(&"EXEMPT") == "Exempt")
	assert(TaxScript.describe(&"NONE") == "No tax")
	assert(TaxScript.total(MoneyScript.of(10000), &"EXEMPT").cents == 10000)


func test_an_unreadable_amount_is_refused_rather_than_taxed_at_zero() -> void:
	var grossed: Dictionary = TaxScript.gross(MoneyScript.parse("nonsense", &"CAD"), &"HST-ON")
	assert(not bool(grossed["ok"]))
	assert(String(grossed["reason"]).contains("readable"))


func test_the_nominal_rate_is_the_sum_of_the_components() -> void:
	assert(TaxScript.rate_ppm(&"HST-ON") == 130000)
	assert(TaxScript.rate_ppm(&"GST-QST") == 149750)
	assert(TaxScript.rate_ppm(&"EXEMPT") == 0)
	assert(TaxScript.rate_ppm(&"NONE") == 0)
	assert(TaxScript.rate_ppm(&"NOT-A-CODE") == 0)
	assert(TaxScript.has(&"HST-ON"))
	assert(not TaxScript.has(&"NOT-A-CODE"))
	assert(TaxScript.components(&"GST-PST-BC").size() == 2)
	assert(TaxScript.code(&"NOT-A-CODE").is_empty())