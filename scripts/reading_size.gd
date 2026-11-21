class_name ReadingSize
## How big the program draws its words, as the person using it asks rather than as the platform says.
##
## Android states text in `sp` - the same unit as everything else, but scaled by the reader's own text-size
## setting - so an app that honours it stays legible to somebody who needs larger words. Godot exposes no
## reading of that setting at all: the screen queries are a size, a density and two scale factors, and none
## of them is a font scale. So the choice is stated here instead, kept between runs, and applied where every
## other measurement for a finger is made, `PhoneHud`.
##
## **Only larger, never smaller.** Every size in `PhoneHud` is a floor - "at least this tall" - worked out
## from what a thumb can hit and what an eye can read at arm's length. An answer below those floors would be
## this program agreeing to be illegible, so the three are the floor itself and two multiples of it.
##
## **A desk is untouched by it.** What the answer multiplies is the fitting done on a device answered with a
## finger, and a computer is never fitted: its panels are the ones this program was drawn for. The menu
## offers these three only where a finger is what presses the controls, which is what `Hud.is_enabled`'s
## `finger` state is for.
##
## The shape is `OrientationChoice`'s, deliberately: a small set of answers, one of them the default, each
## with a word for a menu and a sentence for a page, the kept one read from `user://` where the program
## starts, and written through a temporary file and a rename so that a save which fails never leaves a
## shorter file where the real one was.

extends RefCounted

const STANDARD := &"standard"
const LARGE := &"large"
const LARGEST := &"largest"

const CHOICES: Array[StringName] = [STANDARD, LARGE, LARGEST]

## What a program nobody has asked draws at: the sizes the rest of the program states.
const DEFAULT: StringName = STANDARD

## What each answer multiplies a stated size by, worked out from the answers people can actually tell apart
## rather than from a scale a platform may have: one of them is a quarter again, and one is half again.
const FACTORS: Dictionary = { STANDARD: 1.0, LARGE: 1.25, LARGEST: 1.5 }

const FILE_PATH := "user://reading-size.json"
const KEY := "reading_size"

## The answer in hand. The default until the kept one is read, so that nothing which asks about sizes - and
## every test that says nothing about them - measures exactly the sizes this project states.
static var _chosen: StringName = DEFAULT


## What an answer multiplies a stated size by, and the default's factor for anything that is not one of the
## three - the same way `choice_for` answers with the default for a word nobody offers.
static func factor_for(choice: StringName) -> float:
	return float(FACTORS.get(choice_for(choice), FACTORS[DEFAULT]))


## One of the three, from anything a file or a dictionary may hand over - and the default for anything else.
##
## A JSON round trip gives every value back as a `String` and never as the `StringName` an answer is written
## as, so both are taken. A number, a list or a word nobody offers is not a fourth answer: it is a program
## nobody has asked, which draws at the sizes it was laid out at.
static func choice_for(value: Variant) -> StringName:
	var named: StringName = &""
	if value is StringName:
		named = value
	elif value is String:
		named = StringName(value)
	if CHOICES.has(named):
		return named
	return DEFAULT


## How an answer is written on a menu, in a person's words rather than this file's.
static func word(choice: StringName) -> String:
	match choice_for(choice):
		LARGE:
			return "Large"
		LARGEST:
			return "Largest"
	return "Standard"


## What an answer means, for a manual or a page to say rather than for a menu to squeeze in.
static func sentence(choice: StringName) -> String:
	match choice_for(choice):
		LARGE:
			return "Words, and the controls that have to hold them, are drawn a quarter again as big."
		LARGEST:
			return "Words, and the controls that have to hold them, are drawn half again as big."
	return "Words are drawn at the size this program was laid out at."


## The answer in hand, as the factor `PhoneHud` multiplies its stated sizes by.
static func factor() -> float:
	return factor_for(_chosen)


## The answer in hand.
static func current() -> StringName:
	return _chosen


## The answer that was kept, read where the program starts, and the default when nothing has been kept or
## what is on disk is not one of the three.
##
## A file that cannot be read is not a failure and is not reported as one: never having chosen and having
## chosen the default are the same answer, and a person who has chosen nothing should not be told about a
## fault they did not cause.
static func stored(path: String = FILE_PATH) -> StringName:
	if not FileAccess.file_exists(path):
		return DEFAULT
	# `JSON.new().parse` rather than `JSON.parse_string`, which prints an error for every file it cannot
	# read: a corrupt file is a program nobody has asked, not a fault to report to somebody who only wanted
	# larger words. A parser that talks to the log is a parser that fails a test run.
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return DEFAULT
	var record: Variant = json.data
	if not (record is Dictionary):
		return DEFAULT
	return choice_for((record as Dictionary).get(KEY, DEFAULT))


## Read the kept answer into hand and answer with it. Called in one place, where the program starts - never
## lazily, so that a question about the size of a word never becomes a question about a file.
static func load_kept(path: String = FILE_PATH) -> StringName:
	_chosen = stored(path)
	return _chosen


## Take an answer: hold it, and keep it through a temporary file and a rename.
static func choose(choice: StringName, path: String = FILE_PATH) -> bool:
	_chosen = choice_for(choice)
	var record: Dictionary = { KEY: String(_chosen) }
	var temp: String = path + ".writing"
	var file: FileAccess = FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(record, "\t"))
	file.close()
	return DirAccess.rename_absolute(temp, path) == OK


## Hold an answer without keeping it, for a demonstration or a test - the same door
## `PhoneHud.force_density` and `TouchInput.force` are. A test that has used this says
## `force_choice(DEFAULT)` afterwards, so that one test's answer is not the next one's.
static func force_choice(choice: StringName) -> void:
	_chosen = choice_for(choice)
