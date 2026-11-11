## Which way up the board is asked to be: the three holds, the readings they mean, and the file that
## keeps the answer. No scene and no node: the whole of it is static, so the window is only ever
## *asked* in `apply`, and a test holds the arithmetic down without turning anything.
extends Node

const OrientationChoiceScript := preload("res://scripts/orientation_choice.gd")

const TEMP := "user://orientation_test.json"


func _forget() -> void:
	if FileAccess.file_exists(TEMP):
		DirAccess.remove_absolute(TEMP)


func _write(text: String) -> void:
	var file: FileAccess = FileAccess.open(TEMP, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_a_drawing_board_comes_up_wide_when_nobody_has_chosen_anything() -> void:
	_forget()
	assert(
		OrientationChoiceScript.DEFAULT == OrientationChoiceScript.LANDSCAPE,
		"the default hold is the wide one: %s" % String(OrientationChoiceScript.DEFAULT)
	)
	assert(
		OrientationChoiceScript.stored(TEMP) == OrientationChoiceScript.LANDSCAPE,
		"a file that is not there reads as the wide board"
	)


func test_every_hold_gets_words_and_a_sentence_and_no_two_of_them_alike() -> void:
	var words: Array[String] = []
	var sentences: Array[String] = []
	for choice: StringName in OrientationChoiceScript.CHOICES:
		var said: String = OrientationChoiceScript.word(choice)
		var meant: String = OrientationChoiceScript.sentence(choice)
		assert(said != "", "every hold has a word: %s" % String(choice))
		assert(meant != "", "every hold has a sentence: %s" % String(choice))
		assert(not words.has(said), "no two holds read the same: %s" % said)
		assert(not sentences.has(meant), "no two holds mean the same: %s" % meant)
		words.append(said)
		sentences.append(meant)
	assert(
		OrientationChoiceScript.word(OrientationChoiceScript.DEFAULT).contains("Landscape"),
		"the default's own word says what it is"
	)


func test_each_hold_asks_the_window_for_the_reading_it_means() -> void:
	assert(
		OrientationChoiceScript.reading_for(OrientationChoiceScript.LANDSCAPE)
			== DisplayServer.SCREEN_LANDSCAPE,
		"the wide board asks for a landscape screen"
	)
	assert(
		OrientationChoiceScript.reading_for(OrientationChoiceScript.PORTRAIT)
			== DisplayServer.SCREEN_PORTRAIT,
		"the upright board asks for a portrait screen"
	)
	# The one that is easy to write wrongly: `SCREEN_SENSOR` is 6, and 4 is `SCREEN_SENSOR_LANDSCAPE`,
	# which pins a window to landscape while every sentence about it says it follows the phone.
	assert(
		OrientationChoiceScript.reading_for(OrientationChoiceScript.FOLLOW)
			== DisplayServer.SCREEN_SENSOR,
		"following the phone asks for the sensor and not for a sensor landscape"
	)


func test_the_doorway_follows_the_phone_whatever_the_board_has_been_told() -> void:
	# The front of the program is not a board: a door with two choices on it is not a plan drawn along a
	# wide screen, so it is the one answer that means anything about how the phone is being held.
	assert(
		OrientationChoiceScript.reading_for(OrientationChoiceScript.DOORWAY)
			== DisplayServer.SCREEN_SENSOR,
		"the doorway asks for the sensor, so a menu stands up when the phone does"
	)
	for told: StringName in OrientationChoiceScript.CHOICES:
		assert(
			OrientationChoiceScript.for_the_window(true, told) == OrientationChoiceScript.DOORWAY,
			"the doorway follows the phone whatever the board has been told: %s" % String(told)
		)
		assert(
			OrientationChoiceScript.for_the_window(false, told) == told,
			"and the board keeps its own answer once the doorway is over: %s" % String(told)
		)
	assert(
		OrientationChoiceScript.for_the_window(false, &"sideways")
			== OrientationChoiceScript.LANDSCAPE,
		"with nothing recorded, the board is still the wide one"
	)


func test_the_doorways_hold_is_the_one_the_menu_already_offers_and_not_a_fourth() -> void:
	# It is the follow-the-phone hold under the name of the thing it is for, which is deliberate: a person
	# who has already chosen to follow the phone sees no change at all when the doorway comes and goes, and
	# nobody is ever offered a fourth answer that cannot be chosen for.
	assert(
		OrientationChoiceScript.DOORWAY == OrientationChoiceScript.FOLLOW,
		"the doorway's hold is the follow-the-phone hold"
	)
	assert(
		OrientationChoiceScript.CHOICES.size() == 3,
		"the menu is the three answers a person can give: %s" % str(OrientationChoiceScript.CHOICES)
	)
	assert(
		OrientationChoiceScript.CHOICES.count(OrientationChoiceScript.DOORWAY) == 1,
		"and the doorway's hold is one of them rather than a fourth entry beside the three"
	)
	assert(
		OrientationChoiceScript.choice_for(OrientationChoiceScript.DOORWAY)
			== OrientationChoiceScript.FOLLOW,
		"so a file that recorded it would read back as following the phone"
	)


func test_a_hold_nobody_offers_falls_back_to_the_drawing_boards_own_answer() -> void:
	for offered: Variant in ["upside down", 7, [], {}, null, "LANDSCAPE"]:
		assert(
			OrientationChoiceScript.choice_for(offered) == OrientationChoiceScript.LANDSCAPE,
			"%s is not one of the three, so it reads as the wide board" % str(offered)
		)
	assert(
		OrientationChoiceScript.choice_for(OrientationChoiceScript.PORTRAIT)
			== OrientationChoiceScript.PORTRAIT,
		"a hold that is one of the three is kept as itself"
	)


func test_a_hold_survives_the_file_and_a_file_of_nonsense_is_refused() -> void:
	_forget()
	assert(
		OrientationChoiceScript.remember(OrientationChoiceScript.PORTRAIT, TEMP),
		"a hold is kept in a file"
	)
	assert(
		OrientationChoiceScript.stored(TEMP) == OrientationChoiceScript.PORTRAIT,
		"and comes back the way it went in, through the JSON round trip that makes it a String"
	)
	_write("this is not a record at all")
	assert(
		OrientationChoiceScript.stored(TEMP) == OrientationChoiceScript.LANDSCAPE,
		"a file that is not a record is a board that has not been told"
	)
	_write("{\"%s\": \"sideways\"}" % OrientationChoiceScript.KEY)
	assert(
		OrientationChoiceScript.stored(TEMP) == OrientationChoiceScript.LANDSCAPE,
		"a recorded word nobody offers is refused in favour of the default"
	)
	_forget()


func test_a_desk_cannot_be_asked_to_turn_and_a_phone_can() -> void:
	assert(
		not OrientationChoiceScript.can_turn(false),
		"a window that cannot turn is not asked to, however the choice is set"
	)
	assert(OrientationChoiceScript.can_turn(true), "a phone's window can be asked to turn")
	# Nothing is turned here: `apply_if` is handed a platform that cannot turn, which is the path a
	# desk takes and has to be a window that is left exactly as it was.
	OrientationChoiceScript.apply_if(OrientationChoiceScript.PORTRAIT, false)
	assert(
		DisplayServer.screen_get_orientation() == DisplayServer.SCREEN_LANDSCAPE,
		"the window a desk is running on was not turned by a test"
	)