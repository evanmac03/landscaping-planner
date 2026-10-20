class_name SketchCompositor
extends Node
## Composes the baked layers into the finished picture: paper, wash, wet edge, ink
## (§3.5).
##
## The compositing itself is a shader, which is why it is a `ColorRect` in a
## `SubViewport` rather than a call: a shader needs a surface, and reading the surface
## back is the same two-frame wait the bake uses.
##
## **Nothing here takes a pixel count as an input.** The uniforms are a function of the
## look and the sheet's size, and the shader converts every length from the sheet. That
## is REQ-V3.7 made structural rather than remembered: two bakes of one drawing at
## different resolutions composite with *identical* uniforms, so the grain on the paper
## cannot come out finer because somebody asked for a bigger picture.

const StyleScript := preload("res://scripts/vis/sketch_style.gd")

const SHADER_PATH := "res://resources/shaders/sketch_paper.gdshader"

## The paper's fibre and its cross-hatch, made rather than found.
##
## Procedural on purpose: a project whose paper grain is a downloaded file renders
## differently on the machine where that file is missing, and a proposal renderer that
## depends on a texture path is one refactor away from a flat grey sheet.
##
## **The texture sizes matter as much as the millimetre repeats.** A 256-texel noise
## squashed into one and a half texels of the sheet is averaged by the mip filter into a
## perfectly flat colour, and the result is a grain setting that does nothing while
## looking entirely reasonable. These two numbers and `grain_mm`/`hatch_mm` in the look
## are therefore a pair, and there is a test that holds them together: see
## `minification_for()`.
const GRAIN_PIXELS := 64
const HATCH_PIXELS := 32
## Fixed, so the paper is the same paper in every render of every drawing.
const GRAIN_SEED := 20240517
## How much minification a tiling texture may be under before it stops being texture.
## Four is generous: beyond it the mip filter has averaged the detail away and the sheet
## is flat, which is the bug this constant exists to prevent.
const MAX_MINIFICATION := 4.0

static var _grain: Texture2D = null
static var _hatch: Texture2D = null


## How many texels of a tiling texture land on one texel of the sheet.
##
## One means the texture is resolved exactly; more means it is being shrunk, and past
## `MAX_MINIFICATION` it is being averaged into a flat colour. A look with a grain
## repeat of a quarter of a millimetre is the case this catches.
static func minification_for(
	texture_pixels: int, repeat_mm: float, texels_per_mm: float
) -> float:
	if repeat_mm <= 0.0 or texels_per_mm <= 0.0:
		return INF
	return float(texture_pixels) / (repeat_mm * texels_per_mm)


## The shader's uniform values for a look on a sheet.
##
## The whole of AC-V6, and deliberately a pure function of two arguments: if this
## dictionary ever needs the bake's size, the grain has started depending on the
## resolution and the requirement has been broken.
static func uniform_values(style: StyleScript, paper_mm: Vector2) -> Dictionary:
	return {
		"paper_colour": style.paper,
		"paper_mm": paper_mm,
		# A zero-millimetre repeat would divide by zero in the shader and give an
		# infinity sampled as black, so the floor is inside this function rather than
		# trusted to whoever set the look.
		"grain_mm": maxf(style.grain_mm, 0.01),
		"hatch_mm": maxf(style.hatch_mm, 0.01),
		"grain": style.grain,
		"hatch": style.hatch,
		"bleed_mm": style.bleed_mm,
		"edge_darkening": style.edge_darkening,
		"ink_softness": style.ink_softness,
	}


## Composite the wash and the ink into one opaque picture.
##
## The wash first, then the ink, which is the order a person draws in and the order the
## two are baked in (§3.4).
##
## Asynchronous: the composited surface has to have finished before it can be read, and
## the only honest way to know that is to wait for the frame — twice, because the first
## frame draws and the second settles.
func composite(
	wash: Texture2D,
	ink: Texture2D,
	size: Vector2i,
	style: StyleScript,
	paper_mm: Vector2
) -> Image:
	if wash == null or ink == null:
		push_error("SketchCompositor: both layers are needed to composite.")
		return null
	if size.x <= 0 or size.y <= 0:
		push_error("SketchCompositor: a picture needs a positive size, got %s" % size)
		return null

	var viewport := SubViewport.new()
	viewport.name = "Composite"
	viewport.size = size
	viewport.disable_3d = true
	viewport.msaa_2d = Viewport.MSAA_DISABLED
	# Opaque: the compositor's whole job is to put paper under everything, so a
	# transparent result would be a layer with no sheet.
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var surface := ColorRect.new()
	surface.name = "Sheet"
	# Sized rather than anchored: a Control inside a SubViewport resolves its anchors
	# against the viewport, which is correct but not obvious, and a surface that came out
	# at the wrong size would composite a crop.
	surface.position = Vector2.ZERO
	surface.size = Vector2(size)
	var material := ShaderMaterial.new()
	material.shader = load(SHADER_PATH)
	var values := uniform_values(style, paper_mm)
	for uniform_name: String in values:
		material.set_shader_parameter(uniform_name, values[uniform_name])
	material.set_shader_parameter("texture_wash", wash)
	material.set_shader_parameter("texture_ink", ink)
	material.set_shader_parameter("texture_grain", grain_texture())
	material.set_shader_parameter("texture_hatch", hatch_texture())
	surface.material = material
	viewport.add_child(surface)

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	viewport.queue_free()
	return image


## The paper's fibre, made once per run.
##
## An `ImageTexture` from a `FastNoiseLite` drawn synchronously, rather than a
## `NoiseTexture2D`: the latter generates on a thread and reports when it is ready, which
## would make the paper a thing that is sometimes not there yet - a shader sampling it
## early draws a perfectly smooth sheet, and the grain appears to have stopped working for
## reasons nowhere near the setting. Drawing the image directly also makes the paper a
## thing a test can look at.
static func grain_texture() -> Texture2D:
	if _grain != null:
		return _grain
	var noise := FastNoiseLite.new()
	noise.seed = GRAIN_SEED
	noise.noise_type = FastNoiseLite.TYPE_VALUE
	noise.frequency = 0.25
	# Seamless, because it tiles across the sheet: a seam would be a visible grid line
	# every few millimetres of paper.
	_grain = ImageTexture.create_from_image(
		noise.get_seamless_image(GRAIN_PIXELS, GRAIN_PIXELS)
	)
	return _grain


## The cross-hatch, made once per run: a repeating sawtooth along a diagonal, so the
## lines run at about forty-five degrees and a wash's mid-tones pick up a tooth.
static func hatch_texture() -> Texture2D:
	if _hatch != null:
		return _hatch
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.82, 1.0])
	gradient.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color.BLACK])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = HATCH_PIXELS
	texture.height = HATCH_PIXELS
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(1.0, 1.0)
	texture.repeat = GradientTexture2D.REPEAT
	_hatch = texture
	return _hatch