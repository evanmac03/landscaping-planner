extends Node

## The phone's own finger questions, asked of every page on a desk: what the sweep is allowed to say where there is
## no screen, and the two things it must never grow - a second list of pages, or a second opinion about whether a
## screen is there at all.

const SweepScript := preload("res://tools/phone_touch_sweep.gd")
const GuiSweepScript := preload("res://tools/gui_sweep.gd")
const PhoneHudScript := preload("res://scripts/phone_hud.gd")
const TouchInputScript := preload("res://scripts/touch_input.gd")


## **A sweep that cannot count pixels says so and states nothing.** Every question it asks counts in the pixels a
## screenshot is taken in, and a headless run's framebuffer is a dummy display - so the refusal is the honest
## answer. And the device must be exactly as it was found: a refusal that had already forced a density would leave
## it behind for whatever ran next, which is why the device is stated after the screen is checked rather than before.
func test_a_sweep_with_no_screen_refuses_and_states_no_device() -> void:
	TouchInputScript.force(TouchInputScript.Answer.AUTO)
	PhoneHudScript.force_density(0.0)
	var was_dpi: float = PhoneHudScript.dpi()
	var was_finger: bool = PhoneHudScript.on_a_finger_here()
	var said: Dictionary = await SweepScript.run(get_tree(), false)
	assert(not bool(said["ran"]), "with no screen it did not run: %s" % str(said))
	assert(String(said["why"]).contains("screen"), "and it says what was missing: %s" % String(said["why"]))
	assert(PhoneHudScript.dpi() == was_dpi, "the density it was found at is the density it leaves")
	assert(
		PhoneHudScript.on_a_finger_here() == was_finger,
		"and whether a finger is being served is left as it was too",
	)


## **One list of pages.** The sweep opens each page through its own door, because a page built on its own is
## measured at the size a desk lays it out at rather than the one a finger is given - so the doors are the only list
## that can be right here, and it is `gui_sweep`'s rather than a second one written out again.
func test_the_pages_swept_are_the_pages_the_prose_sweep_opens() -> void:
	assert(SweepScript.PAGES == GuiSweepScript.PAGES, "the finger sweep sweeps the doors the prose sweep opens")
	assert(SweepScript.PAGES.size() > 30, "and it sweeps the pages there are: %d" % SweepScript.PAGES.size())


## **The screen is the one owner's answer, asked once.** Whether there is a screen is `HudProbe._a_real_screen`'s
## question and no other file's - `tests/test_screen_doctrine.gd` holds that for the whole project - and a tool that
## spelled it out again would be a second opinion about the fact it then hands in.
func test_the_screen_is_handed_in_and_not_asked_a_second_time() -> void:
	var source: String = FileAccess.get_file_as_string("res://tools/phone_touch_sweep.gd")
	assert(source.contains("HudProbeScript._a_real_screen()"), "the one owner is asked, for this tool's own run")
	assert(source.count("_a_real_screen") == 1, "and the question is not spelled anywhere else in it")
