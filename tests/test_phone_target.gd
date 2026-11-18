extends Node
## The phone's design rules against the platform's own, and against the modules that own them.
##
## Most of this project's numbers are not its own invention - the touch floor and the two contrast ratios come from
## Android and Material - and the risk of a rule written down is that the document and the module drift apart. So
## each number the authority quotes is read back out of the module that owns it, and the section itself is read out
## of the file rather than trusted: a floor moved in `PhoneHud` without moving the paragraph fails here.
##
## No node and no scene: this is a question about two files and two constants.

const PhoneHudScript := preload("res://scripts/phone_hud.gd")
const ContrastScript := preload("res://scripts/contrast.gd")

## The design authority for the phone: the one place the rules, and the one rule that is not met, are written down.
const SPEC := "res://docs/phone-target.md"


## The authority's own words, or nothing when it cannot be read - which fails every assertion below with the
## message that says what is wrong, rather than inside a helper.
func _the_spec() -> String:
	var reading: FileAccess = FileAccess.open(SPEC, FileAccess.READ)
	if reading == null:
		return ""
	var text: String = reading.get_as_text()
	reading.close()
	return text


## **The floor is this project's own, and the authority says whose number it is measured against.** Android asks for
## 48 by 48 dp; this program states 5.5 mm, because 48 dp is a 135 px row in a 349-pixel palette. Both halves are
## held here so neither can move alone: a floor raised to the platform's would have to change the paragraph saying
## why it is not.
func test_the_touch_floor_is_stated_and_the_platforms_number_is_beside_it() -> void:
	assert(
		PhoneHudScript.TOUCH_MM == 5.5,
		"the thumb floor this program chose: %s" % str(PhoneHudScript.TOUCH_MM),
	)
	var spec: String = _the_spec()
	assert(spec.contains("`TOUCH_MM` **5.5**"), "and the authority states it as the module does")
	assert(spec.contains("48 by 48 dp"), "beside the platform's own rule")
	assert(spec.contains("7.6 mm, or 135 px"), "worked into this phone's own pixels")


## The two ratios are the platform's own numbers, carried as the module's constants rather than as a sentence - so a
## page is judged by the rule itself and not by a restatement of it.
func test_the_contrast_ratios_are_the_platforms_own_two_numbers() -> void:
	assert(ContrastScript.LEAST == 4.5, "body text against its background: %s" % str(ContrastScript.LEAST))
	assert(ContrastScript.LEAST_LARGE == 3.0, "and larger text: %s" % str(ContrastScript.LEAST_LARGE))
	var spec: String = _the_spec()
	assert(
		spec.contains("`LEAST` and `LEAST_LARGE`"),
		"and the authority names the constants rather than restating the numbers",
	)


## **The one rule that is broken is written down.** Android 15 enforces edge-to-edge for an app targeting API 35 or
## higher, and the navigation bar's ground cannot be had through Godot at all - so that gap is a sentence in the
## authority rather than a silence, and this is what stops it being forgotten.
func test_the_navigation_bar_gap_is_written_down_rather_than_forgotten() -> void:
	var spec: String = _the_spec()
	assert(spec.contains("Android 15 enforces edge-to-edge"), "the platform rule the program breaks is named")
	assert(spec.contains("`targetSdk=36`"), "with the target this build really reports")
	assert(
		spec.contains("compliance gap and not a nicety"),
		"and what it is - a gap that cannot be seen, rather than a preference",
	)
	assert(
		spec.contains("screen_get_usable_rect"),
		"as is the second door measured and found wanting, so nobody tries it a third time",
	)


## A rule that is only remembered is what this section exists to stop, so the sources are cited where a reader can
## go and check them rather than take anybody's word - including this project's.
func test_the_authority_is_cited_so_it_need_not_be_remembered() -> void:
	var spec: String = _the_spec()
	assert(
		spec.contains("developer.android.com/guide/topics/ui/accessibility/apps"),
		"the touch target and the contrast ratios come from there",
	)
	assert(
		spec.contains("developer.android.com/about/versions/15/behavior-changes-15"),
		"and the behaviour change that makes the gap a compliance one, from there",
	)
