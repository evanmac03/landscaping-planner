extends RefCounted
## The one walk over this project's own source that a doctrine test needs: the `.gd` files under a tree, the
## code on a line with its comments cut off, and the places a rule's spellings are found.
##
## Two doctrines read source and look for a spelling - `test_screen_doctrine` for "is there a screen to
## measure on", `test_device_doctrine` for "which device is this". Both need the same three things: a
## recursive walk of the trees that hold this project's own code, one line read up to the `#` that begins a
## comment with its **literals kept**, and the offences on a script for a list of shapes. A second copy of
## that walk would be a second reader able to disagree with this one about what the source says, which is the
## defect this project spends the most effort avoiding, so it is written once, here, and both ask it.
##
## **Literals are kept, and that is the point:** the word a program asks the platform with is only ever
## written inside one (`"headless"`, `"android"`), so a walker that dropped literals would catch nothing at
## all. A `#` inside a literal does not cut a line short for the same reason - the quote is walked with the
## backslash in mind, so `"\""` opens and closes a literal on one line and a naive walk would call the rest
## of that line a string.

## The two trees that hold this project's own code, walked rather than listed, because a list is a thing to
## forget to add to. `addons/` is third-party and is never walked; `tests/` is left out because quoting a
## spelling is how a test checks it, and `scenes/` holds no code.
const ROOTS: Array[String] = ["res://scripts", "res://tools"]


## Every `.gd` under the roots, sorted, so a failure names the same files in the same order every time.
static func files() -> Array[String]:
	var found: Array[String] = []
	for root: String in ROOTS:
		_gather(root, found)
	found.sort()
	return found


## Every offence on one script, as `path:line: "the line as code"`, for the shapes handed in.
##
## `left_alone` is a spelling a line may carry **and be cleared of**: the editor question is not the device
## question, so a line naming that call has it removed before the shapes are looked for, and a device
## question beside it on the same line is still caught. The exception clears the call, never the line.
static func offences(
	text: String, path: String, shapes: Array[String], left_alone: Array[String] = []
) -> Array[String]:
	var out: Array[String] = []
	var lines := text.split("\n")
	for i in lines.size():
		var code := code_on(String(lines[i]))
		var kept := code
		for spare: String in left_alone:
			kept = kept.replace(spare, "")
		for shape: String in shapes:
			if kept.contains(shape):
				out.append("%s:%d: %s" % [path, i + 1, code.strip_edges()])
				break
	return out


## One line up to the `#` that begins a comment, with its literals kept: the note at the top of this file
## says why both halves of that matter.
static func code_on(line: String) -> String:
	var out := ""
	var inside := false
	var at := 0
	while at < line.length():
		var letter := line[at]
		if inside:
			out += letter
			if letter == "\\" and at + 1 < line.length():
				out += line[at + 1]
				at += 1
			elif letter == "\"":
				inside = false
		elif letter == "\"":
			inside = true
			out += letter
		elif letter == "#":
			break
		else:
			out += letter
		at += 1
	return out


## A file's text, or nothing at all when it cannot be opened - a doctrine asserts the second never happens,
## because a rule held by a file nobody could read is a rule that passes for the wrong reason.
static func read(path: String) -> String:
	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		return ""
	var text := handle.get_as_text()
	handle.close()
	return text


static func _gather(dir_path: String, into: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for name: String in dir.get_files():
		if name.ends_with(".gd"):
			into.append(dir_path.path_join(name))
	for name: String in dir.get_directories():
		_gather(dir_path.path_join(name), into)
