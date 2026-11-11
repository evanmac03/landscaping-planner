class_name HudProbe
extends RefCounted
## What is on the screen, printed where a person driving this program from another computer can read it.
##
## A page is a rectangle on a screen, and anything driving one from outside has only pixels to go by: it can
## take a screenshot, but it cannot ask the program where a button is, what the foot of the screen says, or
## whether this machine was answered as a device with a finger. So time is spent tapping at coordinates read
## off an old screenshot which a scrollbar has since moved. That is the *program's* fault rather than the
## driver's: every one of those figures is known here already, and none of them was being said.
##
## ## What it says, and when
##
## One block, whenever a page is put on the screen: where this device was answered from, the room everything
## lands in, the two lines at the foot of the screen with the words they are showing, and then the board's
## own controls and the page itself - its title, its rectangle in the pixels a screenshot is taken in, and
## one line for each control a finger could hit, with the centre of it, so that a fixture can be tapped
## without measuring anything at all.
##
## ## A release build says nothing
##
## `on()` is `OS.is_debug_build()`, so a build exported for release carries this code and never runs it.
## That is also why it lives here rather than in `tools/`: the export excludes that folder on purpose, and
## anything that drives a phone has to be *in* the phone.
##
## ## It reports; it never decides
##
## Every figure is read off the object it belongs to - `Control.get_global_rect()`, the window's own
## `position`, `Viewport.get_screen_transform()` - and nothing is worked out a second time here. A reading
## that could disagree with the program would be worse than no reading at all.
##
## ## Where the pixels come from
##
## A control's rectangle is in the coordinates of the viewport it lives in, which for a control on a page is
## the page's *own* window rather than the screen. `Viewport.get_screen_transform()` is the engine's own
## answer for turning one into the other - this project's stretched canvas included - so a rectangle is
## composed through it and the numbers printed are the numbers `adb shell input tap` wants.

## The word every line starts with, so that one command finds them all:
## `adb logcat -d | grep PROBE`.
const PREFIX := "PROBE"

## A control a finger can hit.
##
## Deliberately not `PageChrome.ACTED_WITH`, which answers a different question - what takes the *keyboard* -
## and leaves out the things a finger presses without ever tabbing to them: a field, a spinner, a slider, a
## list. A `ScrollBar` is in here on purpose and is not an oversight: a page whose last row is below the fold
## is scrolled by dragging its bar, and the bar's rectangle is exactly the thing a driver cannot otherwise
## find.
const TAPPABLE: Array[String] = ["BaseButton", "LineEdit", "SpinBox", "Range", "ItemList"]

const PageLayoutScript := preload("res://scripts/page_layout.gd")
const PageChromeScript := preload("res://scripts/page_chrome.gd")


## Whether this build says anything at all. A release export carries every line below and runs none of it.
static func on() -> bool:
	return OS.is_debug_build()


## What a line of two lines is printed as. Several captions here are genuinely two rows - a tool button is
## `"Line"` over its shortcut letter, and a hint can be two rows of words - and the report is read back out
## of a logcat line, which is cut off rather than wrapped. A newline left in would throw away everything after
## it, and what comes after it is the part a driver came for: the centre of the button. The first report this
## ever printed lost a whole column of the tool grid that way.
const LINE_BREAK := " / "


## One line, fit to be read back from logcat.
static func line_for_printing(text: String) -> String:
	return text.replace("\r\n", LINE_BREAK).replace("\n", LINE_BREAK).replace("\r", LINE_BREAK)


## Print a block, one line at a time: a logcat line is cut off rather than wrapped, so a whole report on one
## `print` would lose its end - and so would any one line holding a newline of its own, which is why every
## line goes through `line_for_printing` rather than being trusted to be one line already.
static func publish(lines: PackedStringArray) -> void:
	if not on():
		return
	for line: String in lines:
		print("%s %s" % [PREFIX, line_for_printing(line)])


## Where this device was answered from, the room everything lands in, and the two lines a person reads at the
## foot of the screen. The words are handed in rather than read here: what is printed is what the label is
## actually showing, which is the only reading that can settle a question about what a phone was told.
static func device_lines(
	finger: bool,
	zooming: bool,
	dpi: float,
	scale: float,
	room: Vector2i,
	native: Vector2i,
	touchscreen: bool,
	foot: String,
	tool: String
) -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("--- what is on the screen ---")
	lines.append("device   finger=%s zooming=%s touchscreen=%s dpi=%.1f scale=%.2f" % [
		str(finger), str(zooming), str(touchscreen), dpi, scale])
	lines.append("room     viewport=%s native=%s" % [str(room), str(native)])
	lines.append("foot     \"%s\"" % foot)
	lines.append("tool     \"%s\"" % tool)
	return lines


## A row of controls as it came out: the room it was given, what the row itself asks for, and one line per
## child with where it stands and how much room it wants.
##
## The top bar is why this exists. An `HBoxContainer` lays its children out at their own minimum widths and
## lets the row run past the edge of the screen rather than shrink one of them, so the controls at its end are
## drawn where no finger can reach them - measured on a phone, the view buttons at x=1860 on a 1080-wide
## screen, entirely off it. Which child it is that will not fit cannot be read off a screenshot, and it is not
## worked out a second time here either: the row is asked what it holds, and each child what it needs.
static func row_lines(row: Control, what: String, room: float) -> PackedStringArray:
	var lines := PackedStringArray()
	if row == null:
		return lines
	lines.append("row      %s  room=%.0f  min=%s  size=%s  at=%s" % [
		what, room, str(row.get_combined_minimum_size()), str(row.size), _point_words(row.position)])
	for child: Node in row.get_children():
		var control: Control = child as Control
		if control == null:
			continue
		var words: String = ""
		if control is Button:
			words = (control as Button).text
		elif control is Label:
			words = (control as Label).text
		lines.append("row      %s  %-14s  min=%s  size=%s  at=%s  font=%d  shown=%s  \"%s\"" % [
			what, control.name, str(control.get_combined_minimum_size()), str(control.size),
			_point_words(control.position), control.get_theme_font_size(&"font_size"),
			str(control.is_visible_in_tree()), words])
	return lines


## Everything a finger could hit in a tree, with the centre of each: what to tap and where.
##
## The walk **stops at a `Window`**: a page answers for its own controls, and this is asked once for the
## board's own chrome and once inside each page that is up, so the two lists never overlap.
static func tap_lines(root: Node, scope: String) -> PackedStringArray:
	var lines := PackedStringArray()
	for control: Control in _controls_under(root):
		if not _tappable(control):
			continue
		var rect: Rect2 = screen_rect(control)
		if rect.size.x < 1.0 or rect.size.y < 1.0:
			continue
		lines.append("tap      %-28s %-34s screen %s  centre %s" % [
			scope, "\"%s\"" % _caption(control), _rect_words(rect), _point_words(rect.get_center())])
	return lines


## One page as it stands: what it is, the rectangle it was given, and every control a finger could hit.
static func page_lines(page: Window) -> PackedStringArray:
	var lines := PackedStringArray()
	if page == null:
		return lines
	lines.append("page     %s  \"%s\"  at %s size %s  ->  screen %s" % [
		PageLayoutScript.page_name(page), page.title, str(page.position), str(page.size),
		_rect_words(window_rect(page))])
	lines.append_array(tap_lines(page, PageLayoutScript.page_name(page)))
	return lines


## Every control under a root, **stopping at a `Window`**: a page answers for its own controls, and this is
## asked once for the board's own chrome and once inside each page that is up, so the two lists never overlap
## and a page under another page is still listed as itself.
##
## `PageChrome.every_node_under` walks the whole tree instead, and deliberately: it is looking *for* the
## windows - a picker's menu is one - where this is walking round them. Internal children are read in both,
## because a `ScrollContainer`'s bars are internal and a bar is exactly what a driver needs the rectangle of.
static func _controls_under(root: Node) -> Array[Control]:
	var found: Array[Control] = []
	for child: Node in root.get_children(true):
		if child is Window:
			continue
		var control: Control = child as Control
		if control != null:
			found.append(control)
		found.append_array(_controls_under(child))
	return found


## Where a control stands in the pixels a screenshot is taken in.
static func screen_rect(control: Control) -> Rect2:
	var where: Viewport = control.get_viewport()
	if where == null:
		return Rect2()
	return _compose(where.get_screen_transform(), control.get_global_rect())


## Where a *page* stands in those same pixels.
##
## A `Window` is placed in its **parent viewport's** coordinates and not in its own, so its own transform
## would say where it is not: the rectangle is composed through the parent's transform instead. A page with
## no parent at all - one a test built and never added - is reported in its own coordinates, which is the
## only thing that is true about it.
static func window_rect(page: Window) -> Rect2:
	var rect := Rect2(page.position, page.size)
	var parent: Node = page.get_parent()
	var where: Viewport = parent.get_viewport() if parent != null else null
	if where == null:
		return rect
	return _compose(where.get_screen_transform(), rect)


## A rectangle and a point, in the words a screenshot's pixels are counted in: whole numbers, because a tap
## wants one, and `(x, y)` so that a line can be read straight off.
static func _rect_words(rect: Rect2) -> String:
	return "(%.0f, %.0f) .. (%.0f, %.0f) %0.fx%0.f px" % [
		rect.position.x, rect.position.y, rect.end.x, rect.end.y, rect.size.x, rect.size.y]


static func _point_words(point: Vector2) -> String:
	return "(%.0f, %.0f)" % [point.x, point.y]


## A rectangle taken through a transform, both corners moved and the box that holds them handed back: a
## transform that scales may also mirror, so the two corners are put in order rather than assumed.
static func _compose(xform: Transform2D, rect: Rect2) -> Rect2:
	var corner: Vector2 = xform * (rect.position + rect.size)
	var origin: Vector2 = xform * rect.position
	return Rect2(origin.min(corner), (corner - origin).abs())


## Whether a control is one a finger could hit rather than something to read or lay out.
static func _tappable(control: Control) -> bool:
	if not control.is_visible_in_tree():
		return false
	for kind: String in TAPPABLE:
		if control.is_class(kind):
			return true
	return false


## What a control is called on the screen, in the words a person looking at the phone would use: a button
## says its caption, a field what it holds, a bar what it is.
static func _caption(control: Control) -> String:
	if control is Button:
		return (control as Button).text
	if control is LineEdit:
		return (control as LineEdit).text
	if control is SpinBox:
		return str((control as SpinBox).value)
	if control is OptionButton:
		return (control as OptionButton).text
	if control is ItemList:
		return "%d rows" % (control as ItemList).item_count
	return control.get_class()