extends Node
## Money: exact amounts, one rounding rule, and a refusal that spreads.
##
## These tests are the arithmetic floor of the business module (spec §2.1). Every one of them is a
## statement about a number a customer could check: a column that must foot, a tax figure that must
## match a published example, a credit that must mirror its charge.

const MoneyScript := preload("res://scripts/biz/money.gd")


func test_cents_add_exactly_where_decimal_fractions_drift() -> void:
	# The reason the module counts cents, stated as the thing it prevents: ten cents plus twenty
	# cents is thirty cents, and in binary floating point it is not.
	var tenth: float = 0.1
	var fifth: float = 0.2
	assert(tenth + fifth != 0.3, "the float drift this module exists to avoid")
	var column: Array = []
	for line in 100000:
		column.append(MoneyScript.of(1))
	assert(MoneyScript.sum(column).cents == 100000, "a hundred thousand cents is a hundred thousand cents")


func test_a_contract_of_two_hundred_and_fifty_thousand_round_trips_exactly() -> void:
	var contract: MoneyScript = MoneyScript.from_major(250000, &"CAD")
	assert(contract.cents == 25000000)
	assert(contract.format() == "250,000.00")
	assert(contract.format_with_currency() == "$250,000.00")
	assert(contract.format_iso() == "CAD 250,000.00")
	# And not just the round number: a cent on the end survives.
	assert(MoneyScript.from_major(250000, &"CAD").add(MoneyScript.of(1)).format() == "250,000.01")


func test_an_unreadable_price_is_invalid_and_contagious() -> void:
	# Contagion is the point: one bad line must refuse the total, not vanish into it.
	var unreadable: MoneyScript = MoneyScript.parse("about four hundred", &"CAD")
	assert(not unreadable.is_valid())
	assert(not unreadable.add(MoneyScript.of(50000)).is_valid())
	assert(not unreadable.neg().is_valid())
	assert(not unreadable.scale_ppm(130000).is_valid())
	assert(not MoneyScript.sum([MoneyScript.of(100), unreadable]).is_valid())
	# A valid amount that meets an invalid one is refused, not silently kept.
	assert(not MoneyScript.of(100).sub(unreadable).is_valid())
	assert(not unreadable.is_zero(), "an invalid amount is not zero, and must not read as one")
	assert(unreadable.format() == "—")


func test_rounding_is_half_away_from_zero_in_both_directions() -> void:
	assert(MoneyScript.rounded_div(5, 2) == 3)
	assert(MoneyScript.rounded_div(-5, 2) == -3)
	assert(MoneyScript.rounded_div(5, -2) == -3)
	assert(MoneyScript.rounded_div(-5, -2) == 3)
	assert(MoneyScript.rounded_div(4, 2) == 2)
	assert(MoneyScript.rounded_div(1, 3) == 0)
	assert(MoneyScript.rounded_div(2, 3) == 1)
	assert(MoneyScript.rounded_div(7, 0) == MoneyScript.INVALID_CENTS, "dividing by nothing has no answer")


func test_a_credit_is_the_exact_mirror_of_its_charge() -> void:
	# A credit note that is a cent out from the invoice it reverses is a reconciliation that never
	# closes, so the rounding direction is chosen to make this exactly true.
	for amount in [12345, 999, 100, 7, 123456789]:
		var charge: MoneyScript = MoneyScript.of(amount, &"CAD")
		var tax: MoneyScript = charge.scale_ppm(130000)
		var reversal: MoneyScript = charge.neg().scale_ppm(130000)
		assert(charge.add(charge.neg()).cents == 0)
		assert(tax.add(reversal).cents == 0, "a credit reverses its charge to the cent")


func test_parsing_reads_what_a_person_types() -> void:
	assert(MoneyScript.parse("$1,234.56", &"CAD").cents == 123456)
	assert(MoneyScript.parse("1234.56", &"CAD").cents == 123456)
	assert(MoneyScript.parse("CAD 1234.56", &"CAD").cents == 123456)
	assert(MoneyScript.parse("  1234.56  ", &"CAD").cents == 123456)
	assert(MoneyScript.parse("1234", &"CAD").cents == 123400)
	assert(MoneyScript.parse(".5", &"CAD").cents == 50)
	assert(MoneyScript.parse("-1234.56", &"CAD").cents == -123456)
	# Accounting parentheses are a credit, which is how a credit note arrives from a bookkeeper.
	assert(MoneyScript.parse("(1,234.56)", &"CAD").cents == -123456)
	assert(MoneyScript.parse("+12.00", &"CAD").cents == 1200)
	# A currency with no decimals: 248 yen is 248 minor units.
	assert(MoneyScript.parse("248", &"JPY").cents == 248)
	assert(MoneyScript.parse("248", &"JPY").format() == "248")


func test_parsing_refuses_what_it_cannot_be_sure_of() -> void:
	# More precision than the currency has is refused rather than rounded: a price list that says
	# 0.0049 did not ask for a rounding, and the caller can round deliberately if that is the
	# intent.
	assert(not MoneyScript.parse("12.345", &"CAD").is_valid())
	assert(not MoneyScript.parse("1.2.3", &"CAD").is_valid())
	assert(not MoneyScript.parse("", &"CAD").is_valid())
	assert(not MoneyScript.parse("$", &"CAD").is_valid())
	assert(not MoneyScript.parse("12,34,56", &"CAD").is_valid(), "nonsense grouping is not a number")
	assert(not MoneyScript.parse("1234567890123456789", &"CAD").is_valid(), "past what a price can be")
	# A currency in the text that disagrees with the currency asked for is a mismatch, not a
	# conversion: reading "USD 10.00" as ten Canadian dollars is how a foreign price list corrupts
	# a book.
	assert(not MoneyScript.parse("USD 10.00", &"CAD").is_valid())
	assert(not MoneyScript.parse("€10.00", &"CAD").is_valid())
	assert(MoneyScript.parse("USD 10.00", &"USD").cents == 1000)


func test_two_currencies_do_not_add_up() -> void:
	var canadian: MoneyScript = MoneyScript.of(1000, &"CAD")
	var american: MoneyScript = MoneyScript.of(1000, &"USD")
	assert(not canadian.add(american).is_valid())
	assert(not MoneyScript.sum([canadian, american], &"CAD").is_valid())
	assert(canadian.equals(MoneyScript.of(1000, &"CAD")))
	assert(not canadian.equals(MoneyScript.of(1000, &"USD")))
	assert(not canadian.equals(american))
	assert(MoneyScript.sum([], &"CAD").is_zero())


func test_money_survives_the_file_format() -> void:
	# The store is JSON (spec §2.1a) and Godot's parser hands every number back as a float, so this
	# round-trip goes through the real writer and reader rather than through the objects - the file
	# is where a cent would be lost.
	for cents in [25000001, 1, 0, -123456, 999999999999]:
		var original: MoneyScript = MoneyScript.of(cents, &"CAD")
		var text: String = JSON.stringify(original.to_dict())
		var parsed: Variant = JSON.parse_string(text)
		var restored: MoneyScript = MoneyScript.from_dict(parsed)
		assert(restored.cents == cents, "cents %d survived the file" % cents)
		assert(restored.currency == &"CAD")
		assert(restored.equals(original))


func test_scaling_by_parts_per_million_is_how_rates_are_applied() -> void:
	var subtotal: MoneyScript = MoneyScript.of(137500, &"CAD")
	assert(subtotal.scale_ppm(100000).cents == 13750, "10% overhead")
	assert(subtotal.scale_ppm(150000).cents == 20625, "15% profit")
	assert(subtotal.scale_ppm(0).is_zero())
	assert(subtotal.times(3).cents == 412500)
	assert(MoneyScript.of(-500).abs().cents == 500)
	assert(MoneyScript.of(-500).is_negative())
	assert(not MoneyScript.of(0).is_negative())