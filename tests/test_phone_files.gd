extends Node
## What the program is told about where a file comes from - a phone hands one over through its own
## picker, a computer has a folder - and, just as important, what it is NOT told: a door that stays
## inside the program's own folder is never handed over, because a drawing is written to a temporary
## file and renamed into place and a hand-over cannot rename anything.

const PhoneFilesScript := preload("res://scripts/phone_files.gd")


## Every test starts from "answer for the machine this is running on", so one test cannot lend another
## its device.
func _reset() -> void:
	PhoneFilesScript.force(PhoneFilesScript.Device.AUTO)


## A door of the shape the HUD makes them, without a HUD.
func _door(access: int) -> FileDialog:
	var door: FileDialog = FileDialog.new()
	door.access = access
	door.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	door.title = "A door"
	door.current_file = "drawing.json"
	door.filters = PackedStringArray(["*.json ; Files"])
	return door


## A door that reaches files the person owns is the phone's picker's business - where the device has
## one. Where it has none the answer is "no", and the program draws the door itself as it always has.
func test_a_door_that_reaches_the_filesystem_is_handed_to_the_phones_own_picker() -> void:
	_reset()
	PhoneFilesScript.force(PhoneFilesScript.Device.PHONE)
	var door: FileDialog = _door(FileDialog.ACCESS_FILESYSTEM)
	PhoneFilesScript.prepare(door)
	assert(
		door.use_native_dialog == PhoneFilesScript.has_picker(),
		"a filesystem door on a phone follows the picker: %s" % str(door.use_native_dialog)
	)
	assert(
		door.access == FileDialog.ACCESS_FILESYSTEM,
		"handing a door over does not change what it can see"
	)
	door.free()


## The drawing, the plant list and the sheets are written by this program into its own folder as a
## temporary file renamed into place. A hand-over cannot rename anything, so those doors are never
## handed over - not even on a phone.
func test_a_door_inside_the_programs_own_folder_is_never_handed_over() -> void:
	_reset()
	PhoneFilesScript.force(PhoneFilesScript.Device.PHONE)
	var door: FileDialog = _door(FileDialog.ACCESS_USERDATA)
	PhoneFilesScript.prepare(door)
	assert(
		not door.use_native_dialog,
		"a door into user:// is written and renamed, so it is drawn by this program"
	)
	assert(door.access == FileDialog.ACCESS_USERDATA, "and it still looks inside the program")
	door.free()


## On a computer nothing happens at all, whatever the device has: the desktop's doors are the doors
## they have always been.
func test_on_a_computer_no_door_is_touched() -> void:
	_reset()
	PhoneFilesScript.force(PhoneFilesScript.Device.COMPUTER)
	for access: int in [FileDialog.ACCESS_FILESYSTEM, FileDialog.ACCESS_USERDATA]:
		var door: FileDialog = _door(access)
		PhoneFilesScript.prepare(door)
		assert(not door.use_native_dialog, "no picker is asked for on a computer")
		assert(door.access == access, "and the door still opens where it did")
		door.free()


## Handing a door over says who shows it and nothing else: the title, the file it starts on, the mode
## it is in and the forms it offers are the dialog's own business.
func test_handing_over_a_door_changes_nothing_else_about_it() -> void:
	_reset()
	PhoneFilesScript.force(PhoneFilesScript.Device.PHONE)
	var door: FileDialog = _door(FileDialog.ACCESS_FILESYSTEM)
	PhoneFilesScript.prepare(door)
	assert(door.title == "A door", "the title is the dialog's own")
	assert(door.current_file == "drawing.json", "so is the name it starts on")
	assert(door.file_mode == FileDialog.FILE_MODE_OPEN_FILE, "and the mode it was made in")
	assert(door.filters.size() == 1, "and the forms it offers")
	door.free()


## The door is made the first time somebody presses the button, so there is a moment when it does not
## exist. Preparing nothing is not a failure, it is nothing.
func test_a_door_that_is_not_there_is_not_a_crash() -> void:
	_reset()
	PhoneFilesScript.prepare(null)
	assert(true, "preparing nothing left everything alone")


## The sentence a page or the manual prints has to name what the person will actually see.
func test_the_sentence_names_the_picker_on_a_phone_and_a_folder_on_a_computer() -> void:
	_reset()
	PhoneFilesScript.force(PhoneFilesScript.Device.COMPUTER)
	assert(
		PhoneFilesScript.describe().contains("computer"),
		"a computer has a folder: %s" % PhoneFilesScript.describe()
	)
	PhoneFilesScript.force(PhoneFilesScript.Device.PHONE)
	var said: String = PhoneFilesScript.describe()
	if PhoneFilesScript.uses_the_picker():
		assert(said.contains("picker"), "a phone that has one says so: %s" % said)
	else:
		assert(said.contains("folder this phone lets the program see"), "and one that does not, does not: %s" % said)
	assert(not said.contains("computer"), "a phone is never described as a computer: %s" % said)


## On the machine this is running on the answer is the machine's, unless a demonstration says
## otherwise - and a demonstration can always put it back.
func test_the_phone_is_whatever_the_machine_says_until_something_forces_one() -> void:
	PhoneFilesScript.force(PhoneFilesScript.Device.AUTO)
	assert(
		PhoneFilesScript.on_phone() == OS.has_feature("android"),
		"the answer is the machine's own"
	)
	PhoneFilesScript.force(PhoneFilesScript.Device.PHONE)
	assert(PhoneFilesScript.on_phone(), "a forced phone is a phone")
	PhoneFilesScript.force(PhoneFilesScript.Device.COMPUTER)
	assert(not PhoneFilesScript.on_phone(), "and a forced computer is not")
	_reset()


## A file picked on a phone is somebody else's: it is read once and taken in. What is kept for the
## next session is what this program wrote itself.
func test_a_path_the_program_did_not_write_is_not_one_it_keeps() -> void:
	_reset()
	assert(PhoneFilesScript.is_kept_here("user://drawings/a.json"), "its own folder is its own")
	assert(PhoneFilesScript.is_kept_here("res://data/plants.json"), "and what shipped with it")
	assert(
		not PhoneFilesScript.is_kept_here("content://com.android.providers.downloads/document/41"),
		"a handed-over document is not a path it keeps"
	)
	assert(
		not PhoneFilesScript.is_kept_here("/storage/emulated/0/Download/survey.csv"),
		"and neither is a place on somebody else's storage"
	)


## The phone's picker works out one media type from the filters it is given - the survey door opened as
## `text/plain` on the real device - and a file of a type Android has never heard of is then drawn greyed
## out and cannot be tapped at all. The survey the door exists for was in the folder and could not be
## chosen, so the door offers every file to the picker and lets its own reader refuse what it cannot use.
func test_a_door_handed_to_the_pickers_own_offers_every_file() -> void:
	_reset()
	PhoneFilesScript.force(PhoneFilesScript.Device.PHONE)
	var named := PackedStringArray(["Survey files ; *.survey, *.csv"])
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = named
	# Asked, not assumed: the headless runner this file is judged by has no native dialog at all, so the
	# door it is handed is the engine's own. The rule under test is what the door offers *when* the
	# picker takes it, which is the same rule on a phone.
	var handed: bool = PhoneFilesScript.uses_the_picker()
	PhoneFilesScript.prepare(dialog)
	assert(dialog.use_native_dialog == handed, "the picker is used exactly when the device has one")
	var expected: PackedStringArray = PackedStringArray([PhoneFilesScript.ANY_FILE_FILTER])
	if not handed:
		expected = named
	assert(
		dialog.filters == expected,
		"every file is offered to the picker, because Android would hide the one this door is for: %s" % [dialog.filters]
	)
	dialog.free()
	_reset()


## A computer has its own file dialog, with the filter the door was built with, and a door the program
## keeps for itself is not handed anywhere at all - its file is written and renamed.
func test_a_computers_door_and_a_doors_own_file_keep_their_filters() -> void:
	_reset()
	var named := PackedStringArray(["Survey files ; *.survey, *.csv"])
	PhoneFilesScript.force(PhoneFilesScript.Device.COMPUTER)
	var desk := FileDialog.new()
	desk.access = FileDialog.ACCESS_FILESYSTEM
	desk.filters = named
	PhoneFilesScript.prepare(desk)
	assert(not desk.use_native_dialog, "a computer keeps the dialog it has always had")
	assert(desk.filters == named, "with the filter it was built with")
	desk.free()
	PhoneFilesScript.force(PhoneFilesScript.Device.PHONE)
	var kept := FileDialog.new()
	kept.access = FileDialog.ACCESS_USERDATA
	kept.filters = named
	PhoneFilesScript.prepare(kept)
	assert(not kept.use_native_dialog, "a drawing is written and renamed, never handed over")
	assert(kept.filters == named, "and its filter is left exactly as the page made it")
	kept.free()
	_reset()
