extends Node
## Tests for direct distance entry: what a person can type, what it means, and where the point lands.
##
## The grammar is the heart of it. A length may be typed in the drawing's own unit, an inch mark is
## honoured whatever the drawing thinks it measures in, and a `<` states the angle outright. What is
## *refused* is proved as carefully as what is accepted: a letter can never be typed, because every A-Z
## key in this program is a command; a length cannot begin with a sign; and nothing here mistakes a
## failed parse for a length of nothing.

const Entry := preload("res://scripts/draft/distance_entry.gd")
const Units := preload("res://scripts/draft/units.gd")


func _metric() -> DraftUnits:
	return Units.new()


func _imperial() -> DraftUnits:
	var units := Units.new()
	units.system = Units.System.IMPERIAL
	return units


## Type a string a character at a time, the way a hand does, so that anything the grammar refuses is
## dropped exactly as it would be at the keyboard and the result is what could really have been typed.
func _typed(text: String) -> DistanceEntry:
	var entry := Entry.new()
	for index in text.length():
		entry.type(text.substr(index, 1))
	return entry


func test_a_plain_number_is_the_drawing_s_own_unit() -> void:
	var ten := _typed("10")
	assert(ten.problem(_metric()) == "", "ten is a length")
	assert(is_equal_approx(ten.metres(_metric()), 10.0), "ten in a metre drawing is ten metres")
	assert(is_equal_approx(ten.metres(_imperial()), 3.048), "and in a feet drawing it is ten feet")


func test_a_number_and_a_point_inside_it() -> void:
	assert(is_equal_approx(_typed("12.5").metres(_metric()), 12.5))
	assert(is_equal_approx(_typed(".5").metres(_metric()), 0.5), "a bare point leads a fraction")


func test_an_inch_mark_is_read_in_the_drawing_it_is_typed_into() -> void:
	var six := _typed("6\"")
	assert(is_equal_approx(six.metres(_metric()), 0.1524), "six inches is six inches in a metre drawing")
	assert(is_equal_approx(six.metres(_imperial()), 0.1524), "and in a feet drawing")
	# Feet and inches read as one length, which is why both marks are typeable.
	var straddle := _typed("5'6\"")
	assert(is_equal_approx(straddle.metres(_metric()), 1.6764), "five foot six is five foot six")
	assert(is_equal_approx(straddle.metres(_imperial()), 1.6764), "in either drawing")


func test_the_angle_marker_states_the_direction_outright() -> void:
	var diagonal := _typed("10<45")
	assert(diagonal.has_angle(), "the angle was stated")
	assert(diagonal.length_text() == "10", "the length comes first: %s" % diagonal.length_text())
	assert(diagonal.angle_text() == "45", "and the angle after it")
	assert(diagonal.problem(_metric()) == "")
	# A cursor pointing the other way is overruled: the angle is the direction.
	var run := diagonal.direction(Vector2.ZERO, Vector2(1, 0))
	assert(run.is_equal_approx(Vector2.RIGHT.rotated(deg_to_rad(45.0))), "the angle wins")
	var at := diagonal.point_at(Vector2.ZERO, Vector2(1, 0), _metric())
	var want := Vector2(cos(deg_to_rad(45.0)), sin(deg_to_rad(45.0))) * 10.0
	assert(at.is_equal_approx(want), "and the length is the one typed: %s" % at)


func test_the_angle_is_measured_the_way_polar_tracking_measures_it() -> void:
	# The engine's polar tracking rounds `atan2(offset.y, offset.x)` of the plan's own two axes, so a
	# typed angle has to say the same thing: 0 is +x, 90 is +y, 180 is -x and 270 is -y. The cursors
	# below point the opposite way to each answer, so each one can only come from the typed angle.
	assert(_typed("1<0").direction(Vector2.ZERO, Vector2.DOWN).is_equal_approx(Vector2.RIGHT))
	assert(_typed("1<90").direction(Vector2.ZERO, Vector2.LEFT).is_equal_approx(Vector2.DOWN))
	assert(_typed("1<180").direction(Vector2.ZERO, Vector2.UP).is_equal_approx(Vector2.LEFT))
	assert(_typed("1<270").direction(Vector2.ZERO, Vector2.RIGHT).is_equal_approx(Vector2.UP))
	assert(_typed("1<-90").direction(Vector2.ZERO, Vector2.RIGHT).is_equal_approx(Vector2.UP))


func test_without_an_angle_the_cursor_gives_the_direction_and_the_length_is_kept_exactly() -> void:
	var entry := _typed("10")
	var at := entry.point_at(Vector2.ZERO, Vector2(30, 40), _metric())
	assert(at.is_equal_approx(Vector2(6, 8)), "ten along the way the cursor points: %s" % at)
	assert(is_equal_approx(at.length(), 10.0), "and exactly ten from the first point")
	var elsewhere := entry.point_at(Vector2(100, 100), Vector2(100, 200), _metric())
	assert(elsewhere.is_equal_approx(Vector2(100, 110)), "measured from wherever the first point was")


func test_a_cursor_sitting_on_the_first_point_says_nothing_about_direction() -> void:
	var entry := _typed("10")
	assert(
		entry.direction(Vector2(3, 4), Vector2(3, 4)) == Vector2.ZERO,
		"no direction has been said"
	)
	assert(
		entry.point_at(Vector2(3, 4), Vector2(3, 4), _metric()).is_equal_approx(Vector2(3, 4)),
		"and a point on top of the last one is not placed"
	)
	# A typed angle needs no cursor at all, which is the whole point of typing one.
	assert(
		_typed("10<30").direction(Vector2(3, 4), Vector2(3, 4)) != Vector2.ZERO,
		"an angle is a direction without a cursor"
	)


func test_a_letter_is_never_typed_because_every_letter_is_a_command() -> void:
	var entry := Entry.new()
	for character: String in ["m", "a", "z", "c", "k", "p", "o", "x", "q", "w", "e"]:
		assert(not entry.type(character), "%s is refused" % character)
	assert(entry.is_empty(), "and nothing got in")
	for character: String in ["+", "=", " ", "(", "*", "!", ""]:
		assert(not Entry.accepts(character), "%s is not part of a length or an angle" % character)


func test_a_length_begins_with_a_number_and_nothing_else() -> void:
	for character: String in ["0", "1", "9", "."]:
		assert(Entry.starts_length(character), "%s can begin a length" % character)
	for character: String in ["<", "-", "'", "\"", "m", "", " "]:
		assert(not Entry.starts_length(character), "%s cannot" % character)
	assert(not Entry.new().type("<"), "an angle with no length in front of it is refused")
	assert(not Entry.new().type("-"), "and so is a sign")
	assert(not Entry.new().type("'"), "an inch mark with nothing to mark is refused")
	assert(not Entry.new().type("\""), "nor a mark of its own")
	# A refused character is dropped and the typing carries on, so a hand that reaches for the angle a
	# moment too early still ends up with the length it was going to type.
	assert(_typed("<45").text == "45", "the refused mark left the number behind: %s" % _typed("<45").text)


func test_one_angle_and_one_point_a_part() -> void:
	var angled := _typed("10<45")
	assert(not angled.type("<"), "a second angle is refused")
	assert(angled.text == "10<45", "and nothing was added")
	var whole := _typed("10.5")
	assert(not whole.type("."), "a second point in the same number is refused")
	assert(whole.text == "10.5")
	var point := _typed(".")
	assert(not point.type("."), "and a point is not a number by itself either")
	assert(point.text == ".")
	assert(_typed("10<4.5").angle_text() == "4.5", "the angle has a point of its own")


func test_what_cannot_be_placed_says_why_in_words() -> void:
	var units := _metric()
	assert(Entry.new().problem(units) == "no length typed")
	# An angle with no length in front of it cannot be typed at all, so this branch answers for an entry
	# that arrived some other way.
	var no_length := Entry.new()
	no_length.text = "<45"
	assert(no_length.problem(units) == Entry.NO_LENGTH, "%s" % no_length.problem(units))
	assert(_typed("0").problem(units) == "a length has to be more than nothing")
	assert(_typed("0.0").problem(units) == "a length has to be more than nothing")
	assert(_typed("10<").problem(units).contains("is not an angle"), "%s" % _typed("10<").problem(units))
	# The grammar stops a hand from typing a non-length, so the branch is proved on an entry that came
	# from somewhere else - which is what a restored or half-read entry is.
	var hand := Entry.new()
	hand.text = "1.2.3"
	assert(hand.problem(units) == "1.2.3 is not a length", "%s" % hand.problem(units))


func test_backspace_peels_one_character_at_a_time() -> void:
	var entry := _typed("12.5")
	assert(entry.backspace())
	assert(entry.text == "12.")
	assert(entry.backspace())
	assert(entry.text == "12")
	assert(entry.backspace())
	assert(entry.text == "1")
	assert(entry.backspace())
	assert(entry.is_empty(), "down to nothing")
	assert(not entry.backspace(), "and an empty entry has nothing to drop")


func test_clear_puts_it_back_to_the_start() -> void:
	var entry := _typed("10<45")
	assert(entry.has_angle())
	entry.clear()
	assert(entry.is_empty())
	assert(not entry.has_angle())
	assert(entry.text == "")
	assert(entry.problem(_metric()) == "no length typed")


func test_describe_reads_as_a_length_in_the_drawing_s_own_words() -> void:
	var units := _metric()
	var ten := _typed("10").describe(units)
	assert(ten.contains("10"), "%s" % ten)
	assert(ten.contains("m"), "a metre drawing words a length in metres: %s" % ten)
	assert(
		_typed("10<45").describe(units).contains("at 45"),
		"%s" % _typed("10<45").describe(units)
	)
	# A problem is the words instead, so the line on screen says what is wrong rather than showing a
	# number that means nothing.
	assert(_typed("0").describe(units) == "a length has to be more than nothing")
	assert(Entry.new().describe(units) == "no length typed")


func test_an_angle_still_being_typed_is_not_a_mistake() -> void:
	var units := _metric()
	# A `<` with nothing written after it yet is a number in the middle of being typed, so the words say
	# what has been typed of it rather than naming it wrong. Placing the point still refuses it, because
	# that is a request to put a point somewhere and there is no angle to point it at yet.
	assert(_typed("6<").describe(units) == "6.0 m at", "%s" % _typed("6<").describe(units))
	assert(not _typed("6<").describe(units).contains("not an angle"), "and it is not called a mistake")
	assert(_typed("6<").problem(units).contains("is not an angle"), "though placing it says why not")
	# A single digit is already a legal angle - six metres at four degrees - so it can be placed.
	assert(_typed("6<4").describe(units) == "6.0 m at 4.0°", "%s" % _typed("6<4").describe(units))
	assert(_typed("6<4").problem(units) == "", "and it is a length that can go down")
	assert(_typed("6<45").describe(units).contains("at 45"), "%s" % _typed("6<45").describe(units))
	# A length that really is wrong is still said so at once, typing or not.
	assert(_typed("0<4").describe(units) == "a length has to be more than nothing")