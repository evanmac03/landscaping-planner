class_name SketchBaker
extends Node
## Bakes the painted plan's layers into textures, at one framing shared by all of
## them (§3.4).
##
## The framing is shared on purpose. The wash and the ink are composited against
## each other, so two layers framed even slightly differently would put the colour
## beside the line it belongs to — and the error would be a fraction of a millimetre,
## which is exactly the size of error nobody notices until a client does.
##
## "How big is the sheet" and "how many pixels" are two questions with two answers:
## `paper_mm` is the first, `texels_per_mm` the second. The bake is made at the
## second, and the still path supersamples and downsizes from it (§10.2).

## A3 landscape, in millimetres, which is the sheet this project plots to.
const PAPER_A3 := Vector2(420.0, 297.0)
## Texels per paper millimetre. Six gives 2520 x 1782 for A3: enough for the grain
## and the hatch to have somewhere to live without a bake that takes a second.
const TEXELS_PER_MM := 6.0

var paper_mm: Vector2 = PAPER_A3
var texels_per_mm: float = TEXELS_PER_MM


## The bake's pixel size, which is the paper's size at this resolution.
func pixel_size() -> Vector2i:
	return Vector2i(
		maxi(1, roundi(paper_mm.x * texels_per_mm)),
		maxi(1, roundi(paper_mm.y * texels_per_mm))
	)


## Model metres to paper millimetres, with the drawing centred on the paper.
##
## Centring rather than top-lefting: the drawing's position in the world is a
## survey coordinate, and a plan is framed by its own extent. `plot_scale` is the
## only place the two units meet, which is why it is a parameter and not a field.
static func paper_transform(bounds: Rect2, plot_scale: float, paper: Vector2) -> Transform2D:
	var metres_per_mm: float = maxf(plot_scale * 0.001, 1.0e-9)
	var per_metre: float = 1.0 / metres_per_mm
	var origin: Vector2 = paper * 0.5 - bounds.get_center() * per_metre
	return Transform2D(Vector2(per_metre, 0.0), Vector2(0.0, per_metre), origin)


## Bake one layer per painter, all at this bake's size and framing.
##
## Returns `{"textures": Array[Texture2D], "pixel_size": Vector2i, "mm": Vector2}`
## with one texture per painter **in the order the painters were given**, so the
## caller knows which layer is which without a second table of names to keep in step.
##
## A dictionary rather than a typed pair because the layers are a list whose length
## the caller decides: today two, tomorrow a third for a shadow pass.
##
## **The textures belong to their viewports.** They are valid exactly until `release()`
## is called, because a layer is a render target rather than a copy of one. That is what
## makes a black sheet possible: the first version of this freed the viewports on the way
## out, so the compositor sampled freed render targets and the entire sheet came out
## black at every uniform the look asked for. Releasing is the caller's job because the
## caller is what knows when compositing is finished.
##
## Asynchronous. The bake has to have finished before its texture can be read, and
## the only honest way to know that is to wait for the frame (REQ-V3.5). Two frames,
## not one: the first draws, the second redraws once the viewport's own buffers and
## any recompiled shader have settled.
func bake(painters: Array[Node2D], bounds: Rect2, plot_scale: float) -> Dictionary:
	if painters.is_empty():
		push_error("SketchBaker: there is nothing to bake.")
		return {}
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		push_error("SketchBaker: the drawing has no extent to frame.")
		return {}
	var size := pixel_size()
	var transform := paper_transform(bounds, plot_scale, paper_mm)
	var viewports: Array[SubViewport] = []
	for painter: Node2D in painters:
		var viewport := _make_layer(size)
		# The paper node is what turns the painter's millimetres into texels, so the
		# painter itself can stay in model metres like every other view in the
		# project.
		var paper := Node2D.new()
		paper.name = "Paper"
		paper.scale = Vector2(texels_per_mm, texels_per_mm)
		viewport.add_child(paper)
		painter.transform = transform
		paper.add_child(painter)
		add_child(viewport)
		viewports.append(viewport)

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var textures: Array[Texture2D] = []
	for viewport: SubViewport in viewports:
		textures.append(viewport.get_texture())
	return {
		"textures": textures, "viewports": viewports,
		"pixel_size": size, "mm": paper_mm,
	}


## Let go of a bake's render targets. Call this once nothing is going to sample them.
static func release(baked: Dictionary) -> void:
	for viewport: SubViewport in baked.get("viewports", []):
		if is_instance_valid(viewport):
			viewport.queue_free()


## One layer's viewport. Transparent where nothing is drawn, because paper is the
## compositor's job and a layer that arrives with an opaque background cannot be
## composited (REQ-V3.6).
func _make_layer(size: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = "Layer"
	viewport.size = size
	viewport.transparent_bg = true
	viewport.disable_3d = true
	# MSAA 2D is unavailable on this renderer (§1.2) and supersampling happens once,
	# at the end, rather than twice (§10.2).
	viewport.msaa_2d = Viewport.MSAA_DISABLED
	# UPDATE_ALWAYS rather than UPDATE_ONCE: the bake is a one-off that costs a frame
	# either way, and a mode that renders exactly once has to be told to render again
	# by everyone who touches the layers before reading them.
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	return viewport