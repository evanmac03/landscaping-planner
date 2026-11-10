class_name OrientationChoice
## Which way up the window is asked to be, and where that answer is kept between runs.
##
## Three answers, not two. A drawing board is wider than it is tall, so a person who has said nothing
## gets the wide screen and the board never turns under a plan that was drawn along it. A person may
## want it upright instead, on a phone propped in a stand. Or the phone may be allowed to decide for
## itself, which is the only one of the three that means anything about how the phone is being held.
##
## Those three are about the *board*, which is a plan drawn along a screen. The front of the program is
## not a board, and it is asked for separately: `DOORWAY` follows the phone, so the first thing a person
## meets stands up when the phone does. Nothing about a plan's wide screen has any business deciding how
## a menu with two choices on it is held.
##
## The answer is turned into a `DisplayServer` screen orientation here and nowhere else, because a
## window can only be asked for a reading and the reading is one of seven numbers two of which look
## alike: `SCREEN_SENSOR_LANDSCAPE` is 4 and `SCREEN_SENSOR` is 6, and asking for the wrong one pins
## the window to landscape without saying so.
##
## Whether the window can turn at all is the platform's answer, passed in rather than assumed:
## `can_turn` is the arithmetic and `can_turn_here` asks. A desk's window cannot be asked to stand
## upright, and a reading given to one that cannot take it is a reading that means nothing.

extends RefCounted

const LANDSCAPE := &"landscape"
const PORTRAIT := &"portrait"
const FOLLOW := &"follow"

const CHOICES: Array[StringName] = [LANDSCAPE, PORTRAIT, FOLLOW]

## What the board does when nobody has said anything, which is what the front of this program has
## always been: a plan is drawn along a wide screen.
const DEFAULT: StringName = LANDSCAPE

## What the window is asked for while the *doorway* is up: the front door and the begin-a-drawing page
## it leads to, which are the two pages that stand on the doorway sheet before there is a drawing.
##
## The board's answer above is about a plan, and neither doorway page is a plan: one is a door with two
## choices on it and the other is the list of ways a drawing can begin. Neither is drawn along a wide
## screen, so neither has any business being pinned to one - and the only answer that means anything
## about a menu is how the phone in the hand is being held, which is what `FOLLOW` is. A person who has
## said nothing therefore meets a menu that stands up when the phone does, and steps out of it onto the
## wide board this program has always drawn on.
##
## It is not a fourth answer on the menu: it is the same hold `FOLLOW` already is, kept under the name of
## the thing it is for, so that "the doorway follows the phone" is said in one place rather than at every
## page that counts as a doorway. A person who has already chosen Follow the phone therefore sees no change
## at all when the doorway comes and goes.
const DOORWAY: StringName = FOLLOW

const FILE_PATH := "user://orientation.json"
const KEY := "orientation"


## The reading a hold is turned into, for `DisplayServer.screen_set_orientation`.
##
## A hold with no meaning behind it is answered with the default's reading rather than with nothing:
## a window asked for no orientation keeps whatever the platform last gave it, which is the one
## outcome nobody could describe.
static func reading_for(choice: StringName) -> int:
	match choice_for(choice):
		PORTRAIT:
			return DisplayServer.SCREEN_PORTRAIT
		FOLLOW:
			return DisplayServer.SCREEN_SENSOR
	return DisplayServer.SCREEN_LANDSCAPE


## How a hold is written on a menu, in a person's words rather than the platform's.
static func word(choice: StringName) -> String:
	match choice_for(choice):
		PORTRAIT:
			return "Portrait"
		FOLLOW:
			return "Follow the phone"
	return "Landscape"


## What a hold means, for a page or a manual to say rather than for a menu to squeeze in.
static func sentence(choice: StringName) -> String:
	match choice_for(choice):
		PORTRAIT:
			return "The board stands upright, however the phone is held."
		FOLLOW:
			return "The board turns with the phone, so it fills the screen either way up."
	return "The board stays wide, however the phone is held."


## One of the three, from anything a file or a dictionary may hand over - and the default for
## anything else.
##
## A JSON round trip gives every value back as a `String` and never as the `StringName` a choice is
## written as, so both are taken. A number, a list or a word nobody offers is not a fourth answer:
## it is a board that has not been told, which is the wide one.
static func choice_for(value: Variant) -> StringName:
	var named: StringName = &""
	if value is StringName:
		named = value
	elif value is String:
		named = StringName(value)
	if CHOICES.has(named):
		return named
	return DEFAULT


## What the window should be asked for, with the doorway's own state handed in: the doorway's hold while
## it is up, and the board's own answer the rest of the time.
##
## The state is handed in rather than worked out here, because whether the doorway is up is a question
## about the drawing and not one this file can answer - `StartChoices.should_show` is the one rule and
## every caller asks it. Handing it in is also what lets the whole startup decision be made *once*: a
## window asked for landscape and then for the sensor in the same breath is a phone that turns twice
## where a person sees it turn once.
static func for_the_window(doorway_is_up: bool, kept: StringName) -> StringName:
	return DOORWAY if doorway_is_up else choice_for(kept)


## Whether a window on this platform can be asked to change which way up it is - the arithmetic,
## with the platform's own answer handed in so that a computer can do a phone's sum.
static func can_turn(platform_is_mobile: bool) -> bool:
	return platform_is_mobile


## Whether the window running this is one that can turn.
static func can_turn_here() -> bool:
	return can_turn(OS.has_feature("mobile"))


## Ask the window for a hold, on a platform that can take the asking.
##
## The half that can be told the answer instead of reading it, so that a test can hold what a desk
## and what a phone would be told without being either - the same pair of doors `PhoneHud` has.
static func apply_if(choice: StringName, can_turn_here_now: bool) -> void:
	if not can_turn_here_now:
		return
	DisplayServer.screen_set_orientation(reading_for(choice))


## Ask the window running this for a hold. On a desk nothing is asked, because nothing would happen.
static func apply(choice: StringName) -> void:
	apply_if(choice, can_turn_here())


## The hold that was kept, or the board's own answer when nothing has been kept or what is on disk
## is not one of the three.
##
## A file that cannot be read is not a failure and is not reported as one: never having chosen and
## having chosen the default are the same answer, and the person who has chosen nothing should not
## be told about a fault they did not cause.
static func stored(path: String = FILE_PATH) -> StringName:
	if not FileAccess.file_exists(path):
		return DEFAULT
	# `JSON.new().parse` rather than `JSON.parse_string`, which prints an error for every file it
	# cannot read: a corrupt file is a board that has not been told, not a fault to report at somebody
	# who only wanted the board wide. A parser that talks to the log is a parser that fails a test run.
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return DEFAULT
	var record: Variant = json.data
	if not (record is Dictionary):
		return DEFAULT
	return choice_for((record as Dictionary).get(KEY, DEFAULT))


## Keep a hold, through a temporary file and a rename, so a save that fails never leaves a shorter
## file where the real one was - and so that a half-written file is never read back as a hold.
static func remember(choice: StringName, path: String = FILE_PATH) -> bool:
	var record: Dictionary = {KEY: String(choice_for(choice))}
	var temp: String = path + ".writing"
	var file: FileAccess = FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(record, "\t"))
	file.close()
	return DirAccess.rename_absolute(temp, path) == OK