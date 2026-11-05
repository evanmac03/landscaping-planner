extends Node
## A proposal page: one real still of the garden, laid on a titled A3 sheet and filed as a
## PDF and a preview image.
##
## A development tool rather than part of the game, and deliberately end to end: it
## instances `main.tscn`, frames the garden with the real presentation camera, renders a
## real still through the real exporter, and then places *that* image on the sheet through
## `proposal_page.gd`. Nothing here draws a rectangle by hand, so what it makes is what the
## feature makes.
##
## It also prints the four-view batch a proposal is usually asked for, which is the other
## half of phase 6: a page is one deliverable, a batch is the set.

const AppScene := preload("res://scenes/main.tscn")
const PresetScript := preload("res://scripts/vis/still_preset.gd")
const BatchScript := preload("res://scripts/vis/render_batch.gd")
const PageScript := preload("res://scripts/vis/proposal_page.gd")

## The view the still is rendered from, and the still's own size before it is placed.
const VIEW := "3D presentation"
const STILL_SIZE := Vector2i(1600, 900)
## Where the proposal lands. `user://` because it is the user's deliverable, and this tool
## writes the PDF where a person can open it rather than into the version-controlled tree.
const OUT_DIR := "user://proposals"
## How long to wait for the still, in frames: a tool that blocks forever on a refused
## render is worse than one that reports it.
const WAIT_FRAMES := 900

var _app: Node = null
var _director: Node3D = null


func _ready() -> void:
	_app = AppScene.instantiate()
	_app.name = "App"
	add_child(_app)
	await get_tree().process_frame
	await get_tree().process_frame
	_director = _app.get_node_or_null("Presentation") as Node3D
	if _director == null:
		print("proposal_demo: main.tscn has no Presentation node")
		return
	await _run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_show_batch()
	var still: Image = await _one_still()
	if still == null:
		print("proposal_demo: no still came back, so there is no page to lay out")
		return
	_lay_the_page(still)


## The batch a proposal is usually asked for, planned but not rendered: the point of this
## half is that a batch is a list a person makes, and the report says what is in it.
func _show_batch() -> void:
	var batch = BatchScript.new()
	var added: int = batch.add_every_view(PresetScript.PROPOSAL_DEFAULT)
	print("batch: %d views at %s" % [added, PresetScript.label(PresetScript.PROPOSAL_DEFAULT)])
	print(batch.report_text())
	print(batch.summary())


## One still from the real camera, read back off disk as an image. A refusal is reported
## and returns null rather than being drawn over.
func _one_still() -> Image:
	_director.frame_yard()
	var written: Array[String] = []
	var refused: Array[String] = []
	var on_written := func(path: String) -> void: written.append(path)
	var on_refused := func(reason: String) -> void: refused.append(reason)
	_director.still_written.connect(on_written)
	_director.still_failed.connect(on_refused)
	# Not awaited: `render_still` reports by signal, which is how a caller learns it
	# finished and, when it did not, why.
	_director.render_still(STILL_SIZE)
	var waited := 0
	while written.is_empty() and refused.is_empty() and waited < WAIT_FRAMES:
		await get_tree().process_frame
		waited += 1
	_director.still_written.disconnect(on_written)
	_director.still_failed.disconnect(on_refused)
	if not refused.is_empty():
		print("proposal_demo: the still was refused: %s" % refused[0])
		return null
	if written.is_empty():
		print("proposal_demo: no still came back in %d frames" % WAIT_FRAMES)
		return null
	var image: Image = Image.load_from_file(written[0])
	if image == null:
		print("proposal_demo: the still could not be read back")
		return null
	print("still: %s (%d x %d)" % [written[0], image.get_width(), image.get_height()])
	return image


## Lay the still on an A3 sheet, write the PDF and the preview, and say what was placed.
func _lay_the_page(still: Image) -> void:
	var paper: Vector2 = PresetScript.paper_mm(PresetScript.PROPOSAL_DEFAULT)
	var fields := {
		"project": ProjectSettings.get_setting("application/config/name", "Backyard Design"),
		"view": VIEW,
		"sheet": "A-1",
		"scale": "as rendered",
		"date": Time.get_date_string_from_system(false),
	}
	# Stand-in site photographs, and the captions say so: this project ships no photographs of anybody's
	# garden, and a demo that invented one would be telling a story about a survey nobody made. Two crops
	# of the still it just rendered are enough to prove the strip, the frames and the captions, which is
	# what the page's photograph support is.
	var half: int = int(still.get_width() * 0.5)
	var photos: Array = [
		{
			"image": still.get_region(Rect2i(0, 0, half, still.get_height())),
			"caption": "Stand-in photograph: the still's left half",
		},
		{
			"image": still.get_region(Rect2i(half, 0, still.get_width() - half, still.get_height())),
			"caption": "Stand-in photograph: the still's right half",
		},
	]
	var options := {"photos": photos}
	var plan: Dictionary = PageScript.layout(paper, still.get_size(), options)
	print("page: %s" % PageScript.describe(plan))
	var laid: Dictionary = PageScript.photo_bands(photos.size(), plan["photos_mm"])
	print("photographs: %d placed, %d left out, strip %.0f mm deep" % [
		int(laid["shown"]), int(laid["dropped"]), (plan["photos_mm"] as Rect2).size.y,
	])

	var pdf: PackedByteArray = PageScript.build_pdf(still, paper, fields, options)
	if pdf.is_empty():
		print("proposal_demo: the page was refused; nothing was written")
		return
	var pdf_path := "%s/proposal-page.pdf" % OUT_DIR
	var file := FileAccess.open(pdf_path, FileAccess.WRITE)
	if file == null:
		print("proposal_demo: could not write %s" % pdf_path)
		return
	file.store_buffer(pdf)
	file.close()
	# Decoded as text only up to the first NUL, which is inside the image's deflated
	# samples - and the image's own header comes before that, so the two facts below are
	# readable. Everything after the samples (the cross-reference) is not, which is why the
	# trailer is checked from the file's own tail bytes.
	print("pdf: %s (%d bytes, image XObject: %s)" % [
		ProjectSettings.globalize_path(pdf_path), pdf.size(),
		pdf.get_string_from_utf8().contains("/Subtype /Image"),
	])
	print("pdf tail: %s" % pdf.slice(pdf.size() - 20, pdf.size()).get_string_from_utf8().strip_edges())

	var preview: Image = PageScript.render_image(still, paper, fields, 96.0, options)
	if preview == null:
		print("proposal_demo: the preview could not be drawn")
		return
	var preview_path := "%s/proposal-page-preview.png" % OUT_DIR
	var error := preview.save_png(preview_path)
	if error != OK:
		print("proposal_demo: could not write the preview (%d)" % error)
		return
	print("preview: %s (%d x %d)" % [
		ProjectSettings.globalize_path(preview_path), preview.get_width(), preview.get_height(),
	])