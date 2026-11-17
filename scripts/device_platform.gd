## Which platform this program is running on: the machine itself, asked of it in exactly one place.
##
## Three of the ways a phone differs from a desk come down to the same fact - which platform this is - and each
## of the three used to go and ask for it: `PhoneFiles` whether a door may be handed to a phone's own file
## picker, `OrientationChoice` whether the window may be asked to change the way up it is, and `CameraWindow`
## whose permission to ask for. Four readings of one fact is four answers that drift apart, and the drift here
## is not hypothetical: this program's phone fixes were once wiped and had to be restored in six parts, and an
## `OS.has_feature` in a new file reads as one line and is a second answer nobody diffs. So the feature is read
## here, twice, in one file - and every other file is handed the answer.
##
## **Two readings, because they are not one question.** `is_android` is the platform whose file picker and
## whose runtime permission API this program's code is written against - the narrow fact the two doors that
## *do* something on a phone need. `is_mobile` is Godot's wider feature, true on iOS as well, and the only
## thing this program asks of it is whether a window may be asked to change the way up it is. One "is this a
## phone" would have to be the wrong answer for one of them, which is why the reading is named for the
## platform rather than for a phone.
##
## **What is deliberately not here.** Whether a device is answered with a *finger* is `TouchInput`'s, asked of
## the touchscreen and the density rather than of the operating system, because that is the question the layout
## is sized by and it calls an Android tablet and a Windows tablet the same device; the device's own numbers -
## the density, the glass, the band it keeps for itself - are `PhoneHud`'s; and which platform *some other*
## machine is running is read from a name that was handed in, which is `DeviceModelFit`'s own judgement. This
## file owns the platform this program is running on, and nothing else.
class_name DevicePlatform
extends RefCounted


## Whether this program is running on Android.
##
## The narrow reading, and the one that decides behaviour rather than a size: the platform whose file picker
## takes a door from `PhoneFiles`, and the only one whose camera permission Godot can ask for. Both are things
## this program *does* on Android, so a caller that needs neither has no business asking this.
static func is_android() -> bool:
	return OS.has_feature("android")


## Whether the platform is one whose window may be asked to change the way up it is - Godot's own `mobile`,
## which is true on iOS as well as Android, and the answer `OrientationChoice.can_turn` is handed.
static func is_mobile() -> bool:
	return OS.has_feature("mobile")
