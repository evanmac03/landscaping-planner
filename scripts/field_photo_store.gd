class_name FieldPhotoStore
extends RefCounted
## Where a field photograph is kept: `user://field_photos/`, under a name made from the picture's own
## bytes.
##
## **The name is the point.** A phone hands over `IMG_2043.jpg` and so does the next phone, and a
## survey that overwrote last week's photograph with this week's would be a survey that lost evidence
## without saying so. Naming the file after its own content means the same photograph arriving twice
## is one file and two different photographs can never collide - and a manifest that names a
## photograph goes on naming the right one however many times the file is sent again.
##
## This class does **not** decide what a picture is. `RasterUnderlay.sniff` is the one reader in this
## program that establishes a file's format from its header rather than handing it to Godot's loader
## on trust - the same reader every kept picture in this app goes through - and a second one here
## could disagree with it about the same file. What this adds is the content address, a folder of its
## own, and the one thing a photograph needs that a tracing underlay does not: the same bytes have to
## land on the same name.
##
## A field photograph and a tracing underlay are kept apart because they are different kinds of the
## same thing - one is a record of what somebody saw and the other is a picture they chose to work
## over - and a folder that mixes them is a folder nobody can read.

const UnderlayScript := preload("res://scripts/draft/raster_underlay.gd")
const FieldCaptureScript := preload("res://scripts/field_capture.gd")

## Where the photographs a field capture came from are kept.
const DIR := "user://field_photos"

## The name a half-written photograph carries while it is being written, the same suffix the manifest
## and the catalogue use.
const TEMP_SUFFIX := ".writing"

## How much of the content hash names the file. Sixteen hex characters is sixty-four bits: with a few
## thousand photographs, two of them sharing a name is far less likely than the disk losing a sector.
const NAME_CHARS := 16

## The file extension for each format `sniff` establishes. The format comes from the picture's header
## and the extension follows from the format rather than from the name it arrived under, so a JPEG
## called `.png` is kept as a JPEG.
const EXTENSION_OF_FORMAT := {
	"PNG": "png",
	"JPEG": "jpg",
	"WebP": "webp",
	"BMP": "bmp",
}


## Keep a photograph and answer with the project path it is kept under. Returns
## `{ok, reason, path, duplicate}`.
##
## `duplicate` is true when these exact bytes were already kept: nothing is written and the path is the
## file that was already there. A refusal is `RasterUnderlay`'s own sentence, so the two doors into
## this program tell a person the same thing about the same file.
static func add(source_path: String, folder: String = DIR) -> Dictionary:
	var facts: Dictionary = UnderlayScript.sniff(source_path)
	if not bool(facts["ok"]):
		return _refused(String(facts["reason"]))
	var format: String = String(facts.get("format", ""))
	var extension: String = String(EXTENSION_OF_FORMAT.get(format, "png"))

	# Named `content_hash` rather than `hash`, which is a built-in function's name in this language and a
	# warning this project treats as an error.
	var content_hash: String = FileAccess.get_sha256(source_path)
	if content_hash.is_empty():
		return _refused("%s could not be read, so no name could be made for it" % source_path)
	var kept_path: String = "%s/%s.%s" % [folder, content_hash.substr(0, NAME_CHARS), extension]
	if FileAccess.file_exists(kept_path):
		return {"ok": true, "reason": "", "path": kept_path, "duplicate": true}

	var made: Error = DirAccess.make_dir_recursive_absolute(folder)
	if made != OK and made != ERR_ALREADY_EXISTS:
		return _refused("the folder %s cannot be made, so %s cannot be kept" % [folder, kept_path])
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(source_path)
	if bytes.is_empty():
		return _refused("%s read as no bytes, so nothing was kept" % source_path)
	var temp: String = kept_path + TEMP_SUFFIX
	var file: FileAccess = FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return _refused("%s cannot be written" % kept_path)
	file.store_buffer(bytes)
	file.close()
	if DirAccess.rename_absolute(temp, kept_path) != OK:
		DirAccess.remove_absolute(temp)
		return _refused("the photograph could not be moved into place at %s" % kept_path)
	return {"ok": true, "reason": "", "path": kept_path, "duplicate": false}


## Whether this path is one the store made. A HUD line can then say "kept" about its own file and
## nothing at all about somebody else's.
static func is_kept(path: String, folder: String = DIR) -> bool:
	return path.begins_with(folder + "/") and FileAccess.file_exists(path)


## The photographs kept in a folder, sorted, so a page can offer what is already there.
static func kept(folder: String = DIR) -> PackedStringArray:
	var out := PackedStringArray()
	for name: String in DirAccess.get_files_at(folder):
		if not name.ends_with(TEMP_SUFFIX):
			out.append(folder.path_join(name))
	out.sort()
	return out


## The photographs a set of captures names, ready for a proposal page's `options["photos"]`.
##
## Returns `{ok, reason, photos, missing}`. `photos` is a list of `{image, caption, path}`, in the order
## the captures were given; `caption` is `FieldCapture.words` plus which part was photographed - a person's
## words for what the picture shows, never a file name, because "IMG_2043.jpg" tells a client nothing.
##
## `missing` names, in a sentence each, every photograph that could not be opened, and `reason` repeats
## them when there is nothing to show at all. A survey whose photographs have been moved says so rather
## than printing a proposal with two pictures on it and a third silently gone.
##
## Every capture that names a photograph is loaded: how many fit on the page is `photo_bands`'s question,
## so this program has one cap and the page is the place that says how many it left out.
static func for_page(captures: Array, catalogue) -> Dictionary:
	var photos: Array[Dictionary] = []
	var missing: Array[String] = []
	for entry: Variant in captures:
		if not (entry is Dictionary):
			continue
		var capture: Dictionary = entry
		var path: String = String(capture.get("photo_path", "")).strip_edges()
		if path.is_empty():
			continue
		var words: String = FieldCaptureScript.words(capture, catalogue)
		var facts: Dictionary = UnderlayScript.sniff(path)
		if not bool(facts["ok"]):
			missing.append("%s: %s" % [words, String(facts["reason"])])
			continue
		var image: Image = Image.load_from_file(path)
		if image == null or image.is_empty():
			missing.append("%s: the photograph at %s opened as nothing" % [words, path])
			continue
		photos.append({"image": image, "caption": _caption_of(words, capture), "path": path})
	var reason := ""
	if photos.is_empty():
		reason = (
			"none of these captures names a photograph" if missing.is_empty()
			else " ".join(missing)
		)
	return {"ok": not photos.is_empty(), "reason": reason, "photos": photos, "missing": missing}


## What a photograph is of, in words: what the capture says the plant is and which part was photographed.
static func _caption_of(words: String, capture: Dictionary) -> String:
	var part: String = String(capture.get("part", ""))
	if part.is_empty():
		return words
	return "%s (%s)" % [words, String(FieldCaptureScript.PART_NAMES.get(part, part))]


static func _refused(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "path": "", "duplicate": false}