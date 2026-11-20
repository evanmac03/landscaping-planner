extends Node
## A dev tool: **how a finger would find each page** - the questions that need a device, asked of every page at a
## real phone's numbers, on a desk.
##
## The gap this fills is named by the two tools either side of it. `gui_sweep` opens the pages and asks everything
## that a rectangle can show on a **desk**, and says in its own words that the questions depending on the *device* -
## a floor in pixels, two things a thumb cannot tell apart, words too small for the screen - are "asked where the
## device is, which is the phone itself". `page_layout_check` holds every page to the size it declares for itself,
## and it builds each page **standalone**, so it never sees one fitted for a finger at all. `phone_gui_probe` states
## a phone's numbers but asks only the **board**. So until this, one page's finger rows could only be asked one page
## at a time, on a device, with a `--press` and a look each. Measured on the A16W, 2026-11-14: three separate
## sessions went into asking those questions of three pages.
##
## ## What it states, and what it deliberately does not
##
## The device is stated through the two doors a test uses - `PhoneHud.force_density` and `TouchInput.force` - so the
## page fitting passes under it do what a phone would do, and the floor is read from `HudProbe.finger_floor`. The
## floor is computed **once, off the board's own `Root`**, and handed to every page: one device has one row, and
## `finger_floor` needs a control that spans the room. A page is a viewport of its own, so asking *it* for the floor
## would read the page's own size as if it were the screen's.
##
## **The room is this window's, not a phone's**, and two consequences are named rather than hidden: the band
## questions (`unsafe` and `middle`) are **not asked at all**, because the bands a system keeps belong to a phone's
## own display and the promise `DisplayServer` makes here is about a monitor; and a target this window cannot hold
## is left out by the rule itself, so a page edge off *this* window is a question for `gui_sweep` and
## `page_layout_check`, which are the tools about the room. What is left is everything that is counted in the
## device's own pixels: the row a target is given, the space between two of them, the size of its words, and whether
## its words fit the box they were drawn in.
##
## ## How it is run
##
## It needs a screen, in words, because the rules it asks count in screen pixels - so it is run in the editor with
## `run_scene`, which is the only way this machine has a framebuffer:
##
##     res://tools/phone_touch_sweep.tscn
##
## `run(tree, there_is_a_screen)` is the whole of it, so a test can call it with the fact handed in - the shape
## `page_layout_check` and `hud_layout_check` already have - and the screen is the one owner's answer rather than a
## question asked a second time here.

const MainScene: PackedScene = preload("res://scenes/main.tscn")

## Which pages are swept comes from `gui_sweep`, which is the one list of the doors a person can reach a page by -
## and a page must be opened through its door rather than built on its own, or it is measured at the size a desk
## lays it out at rather than the one a finger is given. A second list here would be a second opinion about which
## pages a finger may meet.
##
## **What a door opened is read through the same file**, for the same reason: six of the doors open a panel, which
## is a `Control` laid over the drawing rather than a page, and a search for a `Window` here would report every one
## of them as *nothing came up* - a panel being something a finger has to press just as much as a page is.
const SweepScript := preload("res://tools/gui_sweep.gd")
const PAGES: Array[String] = SweepScript.PAGES

const HudProbeScript := preload("res://scripts/hud_probe.gd")
const PhoneHudScript := preload("res://scripts/phone_hud.gd")
const TouchInputScript := preload("res://scripts/touch_input.gd")

## The phone this is measured at: the A16W's own 450 dots to the inch, which is the number the probe's log carries
## from the real device (`dpi=450.0`), so a reading here can be held against one taken there.
const PHONE_DPI := 450.0


func _ready() -> void:
	await run(get_tree(), HudProbeScript._a_real_screen())
	# **The window closes itself when the sweep is done**, so the report is not followed by half a minute of the
	# running board's own lines: the first run of this was read out of the log only by filtering it for the tool's
	# own prefix, because the game went on playing for the whole `run_scene` window after the sweep had finished.
	# (It is still worth filtering for that prefix: the last page to leave prints a block of its own.)
	get_tree().quit()


## The sweep itself. Returns `{ran, pages, faults}` when it ran, and `{ran, why}` when it could not.
static func run(tree: SceneTree, there_is_a_screen: bool) -> Dictionary:
	if not there_is_a_screen:
		print("PHONE SWEEP there is no screen here, so nothing is asked: every question below counts in the pixels")
		print("PHONE SWEEP   a screenshot is taken in, and a headless run's framebuffer is a dummy display. Run this")
		print("PHONE SWEEP   with a window open, or read the probe's own lines off the device itself.")
		return { "ran": false, "why": "there is no screen to count pixels in" }

	# **State the phone before the program is built, not after.** The pages are fitted as they are opened, so a
	# device stated afterwards would leave every page at the size a desk lays it out at - which is the state
	# `page_layout_check` measures, and the reason it cannot answer these questions.
	PhoneHudScript.force_density(PHONE_DPI)
	TouchInputScript.force(TouchInputScript.Answer.FINGER)
	PhoneHudScript.apply_if(tree.root, true)

	# **A frame before anything is added, and not for tidiness.** This is called from `_ready`, and a node cannot be
	# added to the root while the root is still setting up its own children. Measured 2026-11-14: the first version
	# of this tool added it straight away, the game went into a tree that never took it, all 38 doors answered
	# "nothing came up" because the pages were built outside the tree, every placement answered
	# `!is_inside_tree()`, and the floor came back 0 because a detached control has no viewport. `page_layout_check`
	# waits the same frame for the same reason.
	await tree.process_frame
	var main: Node = MainScene.instantiate()
	tree.root.add_child(main)
	for _i: int in 40:
		await tree.process_frame
	var hud: Node = main.get_node_or_null("Hud")
	if hud == null:
		print("PHONE SWEEP no Hud, so there are no pages to open")
		main.free()
		_leave_the_device_as_it_was()
		return { "ran": false, "why": "the game scene has no Hud" }

	# The board's own rectangle is the one that spans the room, so the floor is read off it - once, for the screen.
	var root: Control = hud.get_node_or_null(^"Root") as Control
	var least: int = HudProbeScript.finger_floor(root)
	var scale: float = PhoneHudScript.canvas_scale(tree.root)
	var density: float = PhoneHudScript.dpi()
	print("PHONE SWEEP === %d page(s), at %.0f dpi ===" % [PAGES.size(), density])
	print(
		"PHONE SWEEP   a target a finger is meant to press wants %d px here; the bands a system keeps are not asked,"
		% least
	)
	print("PHONE SWEEP   because this window is a monitor and a monitor promises nothing about a cutout.")

	var swept: int = 0
	var faults: int = 0
	var worst: Array[String] = []
	for door: String in PAGES:
		if not hud.has_method(door):
			print("PHONE SWEEP   %-24s - no such door" % door)
			continue
		# What a door put up is read through `gui_sweep`'s own walk rather than a second search here: the two
		# sweeps drive one door list, so they must agree about what a door opened.
		var before: Array[Node] = SweepScript.doors_up(hud)
		hud.call(door)
		for _i: int in 8:
			await tree.process_frame
		var up: Node = SweepScript.what_came_up(before, SweepScript.doors_up(hud))
		if up == null:
			print("PHONE SWEEP   %-24s - nothing came up" % door)
			continue
		swept += 1
		var scope: String = SweepScript.scope_of(up)
		var short: PackedStringArray = HudProbeScript.small_lines(up, scope, least)
		var close: PackedStringArray = HudProbeScript.close_lines(up, scope)
		var tiny: PackedStringArray = HudProbeScript.tiny_lines(up, scope, scale, density)
		var cut: PackedStringArray = HudProbeScript.clipped_lines(up, scope)
		var found: int = short.size() + close.size() + tiny.size() + cut.size()
		faults += found
		if found > 0:
			worst.append("%s (%d)" % [scope, found])
		print(
			"PHONE SWEEP   %-24s %-22s %d short, %d close, %d tiny, %d clipped"
			% [door, scope, short.size(), close.size(), tiny.size(), cut.size()]
		)
		# A page a finger would have nothing to complain about still gets its sentence, rather than reading like one
		# that was never opened.
		if found == 0:
			print("PHONE SWEEP           nothing a finger would have: every target is a row tall, clear of its")
			print("PHONE SWEEP           neighbour, legible, and showing all of its words")
		for line: String in short + close + tiny + cut:
			print("PHONE SWEEP           %s" % line)
		SweepScript.put_away(up)
		for _i: int in 4:
			await tree.process_frame

	print("PHONE SWEEP --- what the sweep found ---")
	if swept == 0:
		print("PHONE SWEEP   no page came up at all, so not one of these questions was asked. That is a fault in this")
		print("PHONE SWEEP   run rather than a clean sweep: a sweep that opened nothing says nothing.")
	elif worst.is_empty():
		print(
			"PHONE SWEEP   %d page(s) opened, and every one of them asks a finger for nothing it could not do" % swept
		)
	else:
		print(
			"PHONE SWEEP   %d page(s) opened, and %d ask a finger for something: %s"
			% [swept, worst.size(), ", ".join(worst)]
		)
	print("PHONE SWEEP === end ===")
	main.free()
	_leave_the_device_as_it_was()
	return { "ran": true, "pages": swept, "faults": faults }


## The device put back the way it was found, which is what every other tool that states one does as well: a sweep
## prints its answer and ends, and has no window anyone is looking at.
static func _leave_the_device_as_it_was() -> void:
	PhoneHudScript.force_density(0.0)
	TouchInputScript.force(TouchInputScript.Answer.AUTO)
