class_name StillExporter
extends Node
## Renders the scene into an image good enough to put in a proposal.
##
## The path is: a SubViewport at the *render* size, waited on until the frame has
## actually been drawn, read back to an Image, downsampled by hand, and saved.
##
## Every step is here rather than delegated because this project cannot use the
## window for a high-resolution still: the stretch mode is `canvas_items`, so the
## window's size sets the output resolution, and a 1600x900 window can never
## produce a 4K image however the numbers are set. The SubViewport is sized for the
## job instead, and the camera is moved into it for the duration of the shot.
##
## Two things about this renderer shape the rest of it (see
## docs/visualization-subsystem-spec.md §1): 2D MSAA is unavailable, so the
## antialiasing *is* the supersample; and a shadowed light is drawn in a different
## colour space, so the frame has to settle before it is read.

## Supersample factor. Two is enough for a line drawing - the first doubling does
## most of the work - and four is four times the pixels for a little more.
const SUPERSAMPLE := 2
## Where stills go. `user://` because a proposal image belongs to the user rather
## than to the project, and the project folder is in version control.
const OUT_DIR := "user://proposals"

## Loaded rather than named, because a `class_name` declared in this batch of work
## is not in the global class registry until the editor rescans - and this file has
## to compile either way.
const SidecarScript := preload("res://scripts/vis/still_sidecar.gd")


## The pixel size a still is actually rendered at before it is downsampled.
static func render_size_for(output_size: Vector2i) -> Vector2i:
	return Vector2i(output_size.x * SUPERSAMPLE, output_size.y * SUPERSAMPLE)


## A file name that says what the still is and when it was taken, so a folder of
## them sorts into the order they were made.
static func timestamp_name(base: String) -> String:
	var now: Dictionary = Time.get_datetime_dict_from_system()
	return "%s-%04d%02d%02d-%02d%02d%02d" % [
		base, int(now["year"]), int(now["month"]), int(now["day"]),
		int(now["hour"]), int(now["minute"]), int(now["second"]),
	]


## Render `render_nodes` at `output_size`, save it as a PNG, and write the sidecar
## beside it.
##
## The nodes are moved *into* the render viewport for the duration of the shot and put
## back afterwards, at the same position among their siblings. That is the whole trick:
## a SubViewport only draws what is below it in the tree, so a camera that is not inside
## the viewport renders nothing at all.
##
## For a 3D still the node is the camera. The garden itself does not move: a SubViewport
## shares its parent's World3D, so a camera inside the viewport sees the same world -
## and moving the whole scene instead does not work, because the engine refuses to
## reparent the scene root out of the tree it is the root of.
##
## Returns the absolute path, or "" when the image could not be made or written.
## `flatten` composites the result over `paper`, which the 2D layer renders need: they
## arrive transparent where nothing is drawn, and many image viewers show a transparent
## PNG as black.
func render_still(
	render_nodes: Array[Node],
	output_size: Vector2i,
	file_name: String,
	sidecar: Dictionary = {},
	flatten: bool = false,
	paper: Color = Color(0.945, 0.937, 0.906)
) -> String:
	if render_nodes.is_empty():
		push_error("StillExporter: there is nothing to render.")
		return ""
	if output_size.x <= 0 or output_size.y <= 0:
		push_error("StillExporter: a still needs a positive size, got %s" % output_size)
		return ""
	for node in render_nodes:
		if node == null or node.get_parent() == null:
			push_error("StillExporter: everything to render must be in the tree.")
			return ""

	# The viewport is a child of the *root* viewport and not of anything being moved: a
	# viewport cannot contain the node it lives inside of.
	var host: Node = get_tree().root
	var viewport := SubViewport.new()
	viewport.name = "StillRender"
	viewport.size = render_size_for(output_size)
	viewport.transparent_bg = flatten
	# MSAA 3D is cheap here and helps the geometry. MSAA 2D is unavailable on this
	# renderer, so the downsample below is what antialiases the lines.
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.msaa_2d = Viewport.MSAA_DISABLED
	# FXAA after the fact would blur the very edges the supersample just made clean, so
	# it stays off and the downsample is the only filter applied.
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.add_child(viewport)

	# Where each one came from, so it goes back exactly there rather than to the end of
	# its parent's children.
	#
	# `reparent()`, not `add_child()`: `add_child()` does not move a node that already
	# has a parent, it just errors ("Can't add child 'Camera' to 'StillRender', already
	# has a parent 'Boom'") and leaves it where it was - so the viewport stays empty and
	# the still comes back blank. Global transform is kept, which for a camera is the
	# whole point: it must stay pointing at the garden while it changes parent.
	var homes: Array[Dictionary] = []
	for node in render_nodes:
		homes.append({
			"node": node, "parent": node.get_parent(), "index": node.get_index(),
		})
		node.reparent(viewport, true)

	# Two frames. The first draws; the second redraws once the shadow atlas, the viewport
	# size and any recompiled light have settled. One frame catches the previous state,
	# which is the classic "the still is subtly wrong" bug.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()

	# Put everything back *before* anything that can fail, so a failed shot never leaves
	# the game inside a viewport.
	for home in homes:
		var node: Node = home["node"]
		var parent: Node = home["parent"]
		if node == null or parent == null or not is_instance_valid(parent):
			continue
		node.reparent(parent, true)
		var index: int = int(home["index"])
		if index >= 0 and index < parent.get_child_count() - 1:
			parent.move_child(node, index)
	viewport.queue_free()

	if image == null or image.is_empty():
		push_error("StillExporter: the render came back empty.")
		return ""
	if looks_blank(image):
		# The failure that quietly writes a grey rectangle into a proposal: a viewport
		# nothing was drawn into is not *empty*, it is one flat colour, and the size and
		# the record would both look perfectly correct.
		push_error("StillExporter: the render came back blank; nothing was drawn into it.")
		return ""

	# Downsample by hand, so the filter is known rather than whichever one the driver
	# happens to pick for a scaled blit.
	image.resize(output_size.x, output_size.y, Image.INTERPOLATE_LANCZOS)
	if flatten:
		image = flatten_over(image, paper)

	var path: String = write_png(image, file_name)
	if path != "" and not sidecar.is_empty():
		SidecarScript.write(path, sidecar)
	return path


## Whether an image is one flat colour, which is what a render that nothing was drawn
## into comes back as.
##
## Read byte by byte rather than sampled on a grid. A grid seems obviously good enough
## for a picture of a garden - and it is, for the blank render this guards - but the
## same function has to answer for the 2D layer renders (REQ-V10.4), where a mostly
## empty layer is legitimate and one small wash patch is a real result. A grid sampled
## every twelfth pixel *misses* that patch and refuses a still that was perfectly good.
## The whole image is a few megabytes and this runs once per still, so it is read in
## full. This is the one filter in the path that must never be wrong in either
## direction: false means a grey rectangle is filed as a proposal.
static func looks_blank(image: Image) -> bool:
	if image == null or image.is_empty():
		return true
	var data: PackedByteArray = image.get_data()
	if data.is_empty():
		return true
	var stride: int = _channel_stride(image.get_format())
	if stride == 0:
		# A format whose channels are not one byte each cannot be compared this way.
		# Grid sampling is the fallback, and it is only reached by images this project
		# does not produce - an 8-bit render is the path that matters.
		return _looks_blank_sampled(image)
	for i in range(0, data.size() - stride + 1, stride):
		for channel in range(stride):
			if data[i + channel] != data[channel]:
				return false
	return true


## Bytes per pixel for the 8-bit formats this function can read directly, or 0 for a
## format it cannot.
static func _channel_stride(format: int) -> int:
	match format:
		Image.FORMAT_RGB8:
			return 3
		Image.FORMAT_RGBA8:
			return 4
	return 0


## The grid fallback, for formats whose bytes mean something other than eight bits per
## channel. Denser than it looks because it has to be right about small features.
static func _looks_blank_sampled(image: Image, samples_per_axis: int = 64) -> bool:
	var first: Color = image.get_pixel(0, 0)
	var step_x: int = maxi(1, int(float(image.get_width()) / float(samples_per_axis)))
	var step_y: int = maxi(1, int(float(image.get_height()) / float(samples_per_axis)))
	for y in range(0, image.get_height(), step_y):
		for x in range(0, image.get_width(), step_x):
			if not image.get_pixel(x, y).is_equal_approx(first):
				return false
	return true


## Composite a transparent image over a flat colour. Pure, so it can be tested
## without a renderer.
##
## The blending happens in the source's own four-channel format and the result is
## converted afterwards, because `Image.blend_rect` refuses a source whose format
## differs from its own - and rendering straight into a three-channel image would
## discard the alpha that the blend needs.
static func flatten_over(image: Image, paper: Color) -> Image:
	var source := image
	if source.get_format() != Image.FORMAT_RGBA8:
		# A copy converted, rather than the same bytes relabelled: rebuilding an image
		# from another format's data would reinterpret every channel.
		source = Image.new()
		source.copy_from(image)
		source.convert(Image.FORMAT_RGBA8)
	# Paper is opaque even if the caller hands over a colour with an alpha in it: the
	# point of the pass is to leave nothing transparent to show as black.
	var flat := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	flat.fill(Color(paper.r, paper.g, paper.b, 1.0))
	flat.blend_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), Vector2i.ZERO)
	flat.convert(Image.FORMAT_RGB8)
	return flat


## Write an image into the proposals folder, making it if it is not there.
## Returns the absolute path, or "" when the write failed.
static func write_png(image: Image, file_name: String) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/%s.png" % [OUT_DIR, file_name]
	var error := image.save_png(path)
	if error != OK:
		push_error("StillExporter: could not write %s (%d)" % [path, error])
		return ""
	return ProjectSettings.globalize_path(path)