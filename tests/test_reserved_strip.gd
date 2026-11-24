extends Node
## The strip no page may be placed in: the foot of the HUD's own top bar, stated from the bar's rectangle.
##
## Stated once was not enough. Measured on the SM-A166W, the bar's foot reads **357** on the block taken as the
## HUD starts and **247** on every block taken after it - the bar is built and folded over the first dozen frames,
## so its foot moves under a page that was placed before it settled. The front door is shown as the HUD starts, so
## it was placed by the 357; and on the glass that was the begin-a-drawing page drawing its own title bar straight
## over the menu titles in landscape.
##
## `test_page_chrome.gd` holds what a page *does* with the strip. These three hold what the strip *is*: the
## foot it follows, that a foot which has moved puts the pages back, and that a strip too tall for a room is
## not allowed to make that room a negative one.

const HudScript := preload("res://scripts/hud.gd")
const PageChromeScript := preload("res://scripts/page_chrome.gd")


## A bar at a place, of a size: the statement reads the rectangle it is handed and nothing else, so a bar
## built here is the whole of what it needs - and it is freed by the test that made it, or the runner
## reports a resource still in use at the end of the run.
func _a_bar_at(top: float, height: float) -> PanelContainer:
	var bar := PanelContainer.new()
	bar.position = Vector2(0, top)
	bar.size = Vector2(1200, height)
	return bar


func test_the_foot_of_the_bar_is_what_a_page_may_not_reach() -> void:
	var hud: HudScript = HudScript.new()
	hud.top_bar = _a_bar_at(9.0, 61.0)
	assert(hud._state_the_strip_the_pages_may_not_use(), "a foot stated for the first time is a move")
	var stated: int = PageChromeScript.reserved_above
	hud.top_bar.size = Vector2(1200, 111.0)
	assert(hud._state_the_strip_the_pages_may_not_use(), "a taller bar says so once")
	var moved: int = PageChromeScript.reserved_above
	assert(not hud._state_the_strip_the_pages_may_not_use(), "the same foot twice is not a change")
	PageChromeScript.reserved_above = 0
	hud.top_bar.free()
	hud.free()
	assert(stated == 70, "the foot is where the bar's own rectangle ends: 9 + 61, not the scene's offset")
	assert(moved == 120, "and a bar 50 px taller is a foot 50 px further down")


func test_a_foot_that_moved_puts_the_pages_back_by_the_rooms_own_door() -> void:
	# The join, held the way the camera's own is: the HUD's per-frame menu pass must state the strip and then
	# put the pages up back - and by the door a change of the room's shape already uses, because a second door
	# for "the room moved" is the second answer this project works hardest to avoid.
	#
	# Read line by line and trimmed rather than as one two-line phrase, because what this file holds on disk
	# depends on the machine's line endings: the repository is checked out with CRLF, so a search for a phrase
	# with a bare newline in the middle of it finds nothing at all - which is how this guard read on its first
	# run, and the phrase it was looking for was on disk the whole time.
	var board: String = FileAccess.get_file_as_string("res://scripts/hud.gd")
	var lines: PackedStringArray = board.split("\n")
	var followed: bool = false
	for i in range(lines.size() - 1):
		if not lines[i].strip_edges().begins_with("if _state_the_strip_the_pages_may_not_use()"):
			continue
		if lines[i + 1].strip_edges().begins_with("_the_canvas_changed_shape()"):
			followed = true
			break
	assert(followed, "the foot being stated is followed at once by the pages being put back")


func test_a_strip_taller_than_the_room_never_makes_that_room_negative() -> void:
	# The strip is a number a *bar* states rather than one `PageChrome` can bound, and it is read while the bar
	# is still being built: 357 against a 247 that comes later, on a phone screen shorter than that difference.
	# So a strip left over from another moment is taller than the room it is taken out of - and a page placed in
	# a negative room is a page placed nowhere.
	PageChromeScript.reserved_above = 100000
	var nowhere: Vector2i = PageChromeScript.content_room_in(null, Vector2i(1185, 666))
	PageChromeScript.reserved_above = 62
	var desk: Vector2i = PageChromeScript.content_room_in(null, Vector2i(1600, 900))
	PageChromeScript.reserved_above = 0
	assert(nowhere == Vector2i(1185, 0), "a bar too tall leaves the room's width and no height at all")
	assert(desk == Vector2i(1600, 838), "and a room that a strip fits in is left exactly as it was, less it")
