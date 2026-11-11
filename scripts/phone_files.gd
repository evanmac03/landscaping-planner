## Where a file comes from on the device this program is running on.
##
## On a phone, a file that belongs to another program is not a path. Android hands out permission to
## one document at a time, through its own file picker, and what comes back is an address the engine
## can read once - not a file this program owns, and not a path it should file away. So every door
## here that reaches outside the program's own folder is handed to that picker where the device has
## one, and every door that stays inside the folder is left exactly as it was made: a drawing is
## written to a temporary file and renamed into place, and a hand-over cannot rename anything.
##
## Nothing about a computer changes. `prepare()` asks the device, decides, and returns without
## touching the dialog when the device is not a phone, so the desktop's doors are the doors they have
## always been - which is what the tests that build them hold true.
class_name PhoneFiles
extends RefCounted

## Which device to answer for. `AUTO` reads the machine this program is running on; the other two
## exist so a demonstration or a test can ask what a phone would be told without having one.
enum Device { AUTO, COMPUTER, PHONE }

## The filter a picker door offers. Android's picker works out one media type from the filters it is
## given, so "any file" is the only filter that cannot hide the file the door was opened for.
const ANY_FILE_FILTER := "Any file ; *.*"

static var _device: Device = Device.AUTO


## Answer for a device rather than for the one this program is running on.
##
## For demonstrations and tests only - nothing in the program calls it - and `Device.AUTO` puts the
## reading back. It is the same door `Hud.force_touch_controls` is, because the question is the same
## question: what would this do on a phone, asked on a computer.
static func force(device: Device) -> void:
	_device = device


## Whether this program is running on a phone.
static func on_phone() -> bool:
	match _device:
		Device.PHONE:
			return true
		Device.COMPUTER:
			return false
		_:
			return OS.has_feature("android")


## Whether the system this program is running on has a file picker of its own.
##
## A phone has one; a computer may or may not, depending on what it is running. The answer is asked
## rather than assumed, because a door handed to a picker that does not exist is a door that does
## nothing at all when it is pressed.
static func has_picker() -> bool:
	return DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE)


## Whether a door should be handed to the phone's picker rather than drawn by this program.
static func uses_the_picker() -> bool:
	return on_phone() and has_picker()


## Hand a door that reaches outside the program's own folder to the phone's picker, where there is
## one, and leave every other door exactly as it was made.
##
## The access mode decides, and it is the dialog's own statement of what it is for: a dialog
## restricted to `user://` is a dialog about this program's files, and those are paths it owns. A
## dialog that already reaches the filesystem is a door either to somebody else's file or to a place
## the person chose, and on a phone that is the picker's business.
static func prepare(dialog: FileDialog) -> void:
	if dialog == null:
		return
	if dialog.access != FileDialog.ACCESS_FILESYSTEM:
		return
	dialog.use_native_dialog = uses_the_picker()
	# Widened to every file for the picker, and that is not cosmetic. Android takes one media type from the
	# filter list: the survey door asked for a survey and the picker was opened as `text/plain`, so a
	# `.survey` - the only type the door is for - was drawn greyed out in the folder and could not be
	# tapped at all. Every picker door now opens with all files offered, and the reader behind it is what
	# refuses a file it cannot use, by name.
	if dialog.use_native_dialog:
		dialog.filters = PackedStringArray([ANY_FILE_FILTER])


## What to say about where a file comes from, in the sentence a page or the manual can print.
static func describe() -> String:
	if not on_phone():
		return "a folder on this computer"
	if uses_the_picker():
		return "the phone's own file picker, which is how a file on a phone is handed to a program"
	return "a folder this phone lets the program see"


## Whether a path this program was handed is one it may open again later.
##
## A file picked on a phone is read once and taken into the program - a survey becomes rows on the
## drawing, a photograph is copied into the app's own pictures - and afterwards the path it came from
## is somebody else's again. Anything kept for the next session therefore has to be something this
## program wrote itself, and that is what `user://` is.
static func is_kept_here(path: String) -> bool:
	return path.begins_with("user://") or path.begins_with("res://")
