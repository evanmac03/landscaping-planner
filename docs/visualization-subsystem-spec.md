# Visualization and presentation subsystem specification

A specification for turning the design the planner already holds into something a
client looks at and buys from: a hand-drawn-looking plan, colour-washed planting
areas, textured hardscape, a walk-through 3D preview, and a high-resolution image
for the proposal.

This is the companion to `docs/drafting-subsystem-spec.md`. That one is about
*measuring* a design exactly; this one is about *showing* it honestly. They share
one rule, and it is the rule that keeps this subsystem from becoming a second
product: **the document is the design.** Every picture here is a projection of the
same `DraftDocument` and the same 3D yard that already exist. No picture owns
geometry of its own, and nothing in this subsystem may be the only place a fact
lives.

---

## 0. Scope, and what this is not

### 0.1 What is in scope

| # | Capability | Lands in |
|---|---|---|
| V1 | Sketch / hand-drawn linework rendering (`CanvasItem`, shaders) | §3 |
| V2 | Colour-wash overlays for planting, lawn, mulch and water | §4 |
| V3 | Texture-based material rendering (hardscape, paving, timber) | §5 |
| V4 | Shadows, highlights and soft edges | §6 |
| V5 | A 3D preview mode for client presentations | §7 |
| V6 | Importing 2D CAD geometry into 3D meshes | §8 |
| V7 | Presentation camera controls (orbit, walk-through) | §9 |
| V8 | High-resolution image export for proposals | §10 |
| V9 | An editor plugin for authoring and rendering the presentation | §11 |

### 0.2 What is out of scope

- A second scene. The preview is the same `Yard`, lit the same way, with a
  different camera and a different material set on top.
- A render farm or a path tracer. Everything here is real-time Godot, plus a
  still-image supersample pass (§10). A photograph-grade render is a different
  project.
- A texture library. The subsystem ships *procedural* materials (§5.1) and the
  *catalog* a purchased texture pack drops into (§5.4). It does not ship
  photographs of paving.
- Anything that changes the design. Presentation is read-only over the document.
  If a picture needs geometry that is not there, the answer is to draw it in the
  2D plan (§8), not to invent it in the view.

REQ-V0.1 The presentation views shall not be able to modify the `DraftDocument`
or the `Yard`'s placeable transforms. They may only read them.

REQ-V0.2 Every technique in this specification shall run under the GL
Compatibility renderer this project uses, or shall be explicitly marked as
unavailable and given a substitute (§1).

### 0.3 Relationship to what already exists

| Existing | Used by this spec as |
|---|---|
| `scripts/plan_canvas.gd` | The working 2D view. Gains a painted mode (§3.6). |
| `scripts/plan_style.gd` | The flat colour table, extended with a wash table (§4.2). |
| `scripts/draft/draft_render.gd` | The one linework converter. Sketch passes and 3D extrusion both call `strokes()`. |
| `scripts/draft/draft_entity.gd` | The source geometry for every mesh made in §8. |
| `resources/materials/*.tres` | The 12 procedural materials, extended not replaced (§5.1). |
| `scenes/world/yard.tscn` | The preview scene. Props are already tagged `placeable`. |
| `scripts/view_controller.gd` | Owns the working views. Presentation is additive. |

---

## 1. What the renderer actually allows

The project is on `rendering_method = "gl_compatibility"`, MSAA 3D ×4, 1600×900,
`canvas_items` stretch. Compatibility is not a lesser Forward+; it is a *different*
feature set, and a presentation pipeline that assumes Forward+ will silently lose
whole effects. What follows was verified for this document, and it is a design
input, not a footnote.

### 1.1 Available

| Feature | Status | Note |
|---|---|---|
| Glow | Yes | Different implementation; Levels, Strength, Blend Mode, Mix and Map are hidden. |
| SSAO | Yes, since 4.6 | Simplified version. **Only radius and intensity** are adjustable. |
| Tonemapping, Adjustments | Yes | `tonemap_mode`, `adjustment_*` all work. |
| Depth and height fog | Yes | `fog_*` works. |
| MSAA 3D | Yes | Already at ×4. |
| Directional shadows | Yes | With the caveat in §1.3. |
| `hint_screen_texture` in `canvas_item` | Yes | With the `BackBufferCopy` rule in §4.5. |
| Custom 2D post-processing | Yes | `CanvasLayer` + `ColorRect` with a `canvas_item` shader. |
| Per-instance uniforms (3D and 2D) | Yes | `instance uniform` + `set_instance_shader_parameter`. 16 per shader. |
| MultiMesh instancing | Yes | `MultiMeshInstance3D`. |
| Triplanar mapping | Yes | `uv1_world_triplanar`. |

### 1.2 Unavailable, and the substitute this specification uses

| Missing | Consequence | Substitute |
|---|---|---|
| SSR, SSIL, SDFGI, VoxelGI | No screen-space or voxel indirect light. | Constant ambient + sky, and a *painted* contact shadow (§6.4). |
| Volumetric fog | No light shafts. | Depth fog only. |
| Depth-of-field blur | Cannot defocus a background. | Two renders through a mask, still path only (§10.6). |
| PCSS soft directional shadows | Sun shadows have a fixed edge. | `shadow_blur` on the light (to be confirmed on this machine), plus supersampling. |
| Lightmap baking | `LightmapGI` baking needs RenderingDevice, so it cannot bake here. | No baked GI; contact darkening is painted instead (§6.4). |
| MSAA 2D | 2D lines get no hardware antialiasing. | **Supersample and downscale** (§10.2). This is the most important line in this table. |
| `Viewport.set_size_2d_override` | The method does not exist in 4.7. | Set `Viewport.size` directly. |
| Custom fullscreen *3D* post-process | No quad-with-screen-texture over the 3D frame in this renderer. | Composite in 2D: the 3D frame arrives as a `ViewportTexture`, so `canvas_item` shaders still get at it (§10.3). |

### 1.3 Two Compatibility behaviours that will otherwise look like bugs

1. **A shadowed light is rendered in sRGB space, not linear**, because shadows on
   this renderer use a multi-pass path. Turning `shadow_enabled` on a light
   measurably changes its brightness. Energy must be re-tuned **with shadows on**,
   and the sun's energy in this project (`1.15`) is already tuned that way — do
   not "correct" it for a shadows-off render.
2. **2D MSAA is unavailable**, so no hand-drawn look may rely on it. Every soft
   edge in the painted path comes from supersampling or from an alpha ramp in a
   shader.

REQ-V1.1 Any effect that §1.2 marks unavailable shall be implemented by the
substitute named there, and the substitute shall be a tested code path, not a
comment. A capability the renderer lacks shall never be silently no-oped.

REQ-V1.2 The still-image path shall not depend on any renderer feature above the
Compatibility set, because the still is the deliverable that leaves the building.

---

## 2. The look: three layers, one rule

### 2.1 The layers

Every picture this subsystem makes — the painted plan, the presentation view of
the 3D scene, the exported still — is built in the same three layers:

```
   ┌──────────────────────────────────────────────┐
   │ 3. LINEWORK   ink, wobbled, weighted          │  §3
   ├──────────────────────────────────────────────┤
   │ 2. WASH       flat colour, mottled, bleeding  │  §4
   ├──────────────────────────────────────────────┤
   │ 1. GROUND     paper grain, or textured 3D     │  §5, §6
   └──────────────────────────────────────────────┘
```

The order is not decorative. It is the order a person draws in: wash first, ink
over it, paper underneath. It also happens to be the order that makes each layer
independently testable — the wash is a polygon list, the linework is a stroke
list, the ground is a material or a tile.

### 2.2 The one rule

**A layer may add appearance; it may not add facts.** The wash knows which bed a
colour belongs to because the bed exists in the document. The linework knows where
a kerb runs because the kerb is an entity. If a layer wants to show something that
is not in the document, that something must first be drawn in the plan.

REQ-V2.1 The linework layer shall be produced by `DraftRender.strokes()` and
`DraftRender.layout()`. No component in this subsystem shall parse an entity's
geometry for itself.

REQ-V2.2 The wash layer shall be keyed by the same layer names and material
resources the rest of the project uses, so a renamed layer turns up as a missing
key rather than as a wrong colour.

### 2.3 Two rendering paths, for one reason

| Path | When | How | Fidelity |
|---|---|---|---|
| **Working** | While designing | `_draw()` on a `Node2D`, live | Instant, no wobble, no grain |
| **Painted** | Presenting, exporting | Baked to textures, shaded, composited | Slow, beautiful, deterministic |

The working path must stay instant — it is the mouse's feedback loop, and the
drafting subsystem's whole feel depends on it. The painted path may take a second
because it runs once per picture.

REQ-V2.3 Switching to the painted path shall not change what is drawn: the same
entities, at the same coordinates, with the same weights. A test shall compare the
two stroke lists for equality before the wobble is applied.

---

## 3. Sketch and hand-drawn rendering

### 3.1 Where the wobble lives: geometry, not shader

The obvious implementation of a hand-drawn line is a shader that displaces
vertices by noise. It is the wrong one here, for two reasons:

1. **A shader that displaces by screen position makes the drawing swim.** Pan the
   view and every line writhes, because the displacement follows the window rather
   than the drawing. A pencil line belongs to the paper.
2. **A shader cannot be measured.** The drafting subsystem's culture is that the
   geometry is the part worth testing. A wobbled line can be asserted to stay
   within a tolerance of the line it stands for. A displaced pixel cannot.

So the wobble is generated in GDScript, deterministically, from a seed stored per
entity. Same entity, same wobble, every frame and every render.

REQ-V3.1 The wobble shall be deterministic from the entity's id and shall not
depend on the camera, the frame number or `TIME`.

REQ-V3.2 A wobbled stroke shall stay within `WOBBLE_LIMIT_MM` of the true stroke
at every sample. The limit is a requested line width or less — a pencil mark that
wanders further than its own width is measuring something else.

### 3.2 The wobble

```gdscript
class_name SketchStroke
extends RefCounted
## A drawn line, handed back wobbling like a pencil rather than a plotter.
##
## The wobble is geometry, not a shader effect. A shader that displaces by
## screen position makes the line swim as the view pans, because the
## displacement follows the window instead of the paper; and geometry can be
## measured, which is how the drawing stays honest (REQ-V3.2).

## Sideways wander, in paper millimetres.
const AMPLITUDE_MM := 0.28
## How far along the line one wander lasts.
const WAVELENGTH_MM := 7.0
## Sampling step. A 6 m bed edge becomes about fifty points at 1:100.
const SEGMENT_MM := 1.2
## How far a mark may stray from the line it stands for. Asserted by test.
const WOBBLE_LIMIT_MM := 0.45


## One stroke, wobbled. `seed_value` makes the same line wobble the same way
## every time, so the drawing is stable between frames and between renders.
static func wobble(
	stroke: PackedVector2Array, seed_value: int, plot_scale: float
) -> PackedVector2Array:
	if stroke.size() < 2:
		return stroke
	var out := PackedVector2Array()
	# The wander is authored in paper millimetres and scaled into model metres,
	# because a wobble is a property of the mark, not of the drawing.
	var amplitude: float = AMPLITUDE_MM * 0.001 * plot_scale
	var wavelength: float = WAVELENGTH_MM * 0.001 * plot_scale
	var step: float = SEGMENT_MM * 0.001 * plot_scale
	var phase_seed: float = float(seed_value % 977) * 0.13
	for index in stroke.size() - 1:
		var from: Vector2 = stroke[index]
		var to: Vector2 = stroke[index + 1]
		var length: float = from.distance_to(to)
		if length <= 0.0:
			continue
		var direction: Vector2 = (to - from) / length
		var sideways := Vector2(direction.y, -direction.x)
		var samples: int = maxi(1, int(ceil(length / step)))
		for sample in samples:
			var t: float = float(sample) / float(samples)
			var at: Vector2 = from.lerp(to, t)
			# Two frequencies walking along the stroke, so the wander never reads
			# as one neat wave. Both are functions of *position along the line*,
			# so where two segments meet the wander agrees and the stroke does
			# not kink at every sample boundary.
			var along: float = t * length / wavelength
			var wander: float = (
				sin(along * TAU + phase_seed) * 0.72
				+ sin(along * TAU * 2.37 + phase_seed * 1.7) * 0.28
			)
			out.append(at + sideways * amplitude * wander)
	# The final point is appended once, after the loop, rather than at the end of
	# every segment: otherwise each shared point appears twice.
	out.append(stroke[stroke.size() - 1])
	return out


## A whole entity's strokes, wobbled together, one seed per stroke so two sides
## of one shape do not wobble in step.
static func wobble_strokes(
	strokes: Array[PackedVector2Array], seed_value: int, plot_scale: float
) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for index in strokes.size():
		out.append(wobble(strokes[index], seed_value + index * 31, plot_scale))
	return out
```

### 3.3 The ink pass, drawn twice

A pencil line is a light broad pass with a darker narrow one on top. Drawing only
the dark one is what makes a digital line look like a plotter.

| Pass | Width | Alpha | Colour |
|---|---|---|---|
| Under | `width × 1.8` | 0.28 | Layer ink, lightened toward paper |
| Over | `width × 1.0` | 0.92 | Layer ink |

REQ-V3.3 Weights shall come from `DraftRender.width_pixels()`, and shall be the
same numbers the working path and the sheet use. A sketch that changes a line's
weight has changed the drawing's hierarchy, and the hierarchy is the drawing.

REQ-V3.4 The ink pass's coverage shall be ramped, not thresholded. A `step()` on
coverage is what makes an unantialiased line look like a printout — and with no
2D MSAA available (§1.3), the ramp is the only antialiasing the *compositor* has.

### 3.4 The layers are baked, then shaded

The painted path draws its wash into one texture and its ink into another, then
shades the pair over paper. Baking is what lets the shader hatch and grain the
drawing with a proper UV, and it is why the shader never needs to read the screen.

```gdscript
class_name SketchBaker
extends Node
## Bakes the current drawing's layers to textures, then hands them to the
## compositor. One bake per layer, two layers, one framing shared by both.

## Paper size in millimetres, and the texels per millimetre the bake is made at.
## The output pixel size is these two multiplied, so "how big is the sheet" and
## "how many pixels" are separate questions with separate answers.
var paper_mm: Vector2 = Vector2(420.0, 297.0)   # A3 landscape
var texels_per_mm: float = 6.0                  # 2520 x 1782 at this setting
## The plot scale the drawing is presented at. Sets every weight, and the wobble.
var plot_scale: float = 100.0


## Bake the wash, then the ink, into two textures sharing one framing.
## Returns {"wash": Texture2D, "ink": Texture2D, "pixel_size": Vector2i, "mm": Vector2}.
func bake(document, viewport_size: Vector2i) -> Dictionary:
	var wash: SubViewport = _make_layer(viewport_size)
	var ink: SubViewport = _make_layer(viewport_size)
	# The layers are drawn by two small painters rather than by PlanCanvas, so
	# the painted path cannot disturb the working view's state - nor be disturbed
	# by its zoom, its hover, its selection ring or its status line.
	wash.add_child(WashPainter.new(document, plot_scale))     # §4.4
	ink.add_child(InkPainter.new(document, plot_scale))       # §3.3
	wash.render_target_update_mode = SubViewport.UPDATE_ONCE
	ink.render_target_update_mode = SubViewport.UPDATE_ONCE
	# The bake has to have finished before its texture can be read, and the only
	# honest way to know that is to wait for the frame (REQ-V3.5).
	await RenderingServer.frame_post_draw
	var result := {
		"wash": wash.get_texture(),
		"ink": ink.get_texture(),
		"pixel_size": viewport_size,
		"mm": paper_mm,
	}
	wash.queue_free()
	ink.queue_free()
	return result


func _make_layer(size: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	# The layers are composited by the sketch shader, so they must be
	# transparent where nothing is drawn rather than cleared to paper.
	viewport.transparent_bg = true
	viewport.size = size
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	# MSAA is off here on purpose: supersampling happens once, at the end
	# (§10.2), rather than twice. And MSAA 2D is unavailable here in any case.
	viewport.msaa_2d = Viewport.MSAA_DISABLED
	return viewport
```

REQ-V3.5 The bake shall wait for `RenderingServer.frame_post_draw` before its
texture is read. A texture read in the same frame returns an empty image, and an
empty image written into a proposal is a bug that leaves the building.

REQ-V3.6 A layer bake shall be transparent where nothing is drawn. Paper is the
compositor's job; a layer that arrives with an opaque background cannot be
composited.

### 3.5 The compositor shader

```glsl
// resources/shaders/sketch_paper.gdshader
//
// Composes one painted picture over paper: paper under everything, the wash on
// it, a wet edge where the wash stops, and the ink over all of it.
//
// Nothing here reads hint_screen_texture, deliberately. A screen read would force
// a back-buffer copy (see the note in section 4.5) and would make the result
// depend on the order things happened to be drawn in; reading its own two layers
// makes this shader order-independent, and therefore testable.
shader_type canvas_item;

/** The sheet, in millimetres. The conversion for every length below. */
uniform vec2 paper_mm = vec2(420.0, 297.0);
/** Millimetres per repeat of the paper fibre. A *repeat*, not a count: the count is
 *  whatever fits on the sheet, which is what makes this resolution-independent. */
uniform float grain_mm = 3.0;
/** Millimetres per repeat of the cross-hatch. */
uniform float hatch_mm = 1.6;
/** Grain strength. */
uniform float grain : hint_range(0.0, 1.0) = 0.16;
/** Hatch strength in the wash's mid-tones. */
uniform float hatch : hint_range(0.0, 1.0) = 0.22;
/** How far the wash bleeds past its own edge, in paper millimetres. */
uniform float bleed_mm : hint_range(0.0, 12.0) = 1.8;
/** How much darker the wash is at its own edge, which is what a wet edge does. */
uniform float edge_darkening : hint_range(0.0, 1.0) = 0.30;
/** Ink edge softness, as a share of full coverage. The one antialiasing the
 *  compositor has: it turns a threshold into a ramp. Dimensionless on purpose - a ramp
 *  in coverage is not a distance on the paper. */
uniform float ink_softness : hint_range(0.0, 1.0) = 0.45;

void fragment() {
    // --- the wash, its bleed and its wet edge -----------------------------
    // The bleed is a paper length converted to the sheet's own UV: a millimetre is
    // the same fraction of the sheet whatever the sheet is drawn at.
    vec2 bleed_uv = vec2(bleed_mm) / paper_mm;
    float w_c = texture(texture_wash, UV).a;
    float w_n = texture(texture_wash, UV - vec2(0.0, bleed_uv.y)).a;
    float w_s = texture(texture_wash, UV + vec2(0.0, bleed_uv.y)).a;
    float w_w = texture(texture_wash, UV - vec2(bleed_uv.x, 0.0)).a;
    float w_e = texture(texture_wash, UV + vec2(bleed_uv.x, 0.0)).a;
    // Bleeding outward is the *maximum* of the neighbours, not the average: a
    // wet edge spreads, so coverage should grow wherever a neighbour has it.
    float covered = max(w_c, max(max(w_n, w_s), max(w_w, w_e)));
    vec4 wash = texture(texture_wash, UV);
    // The wet edge is coverage minus its own blur, which is dark exactly at the
    // boundary and zero in the middle and outside.
    float blurred = (w_c + w_n + w_s + w_w + w_e) * 0.2;
    float edge = clamp(w_c - blurred, 0.0, 1.0);

    // --- grain and hatch are sampled in paper millimetres ------------------
    // This is why the shader is told the paper size instead of the pixel size: a
    // still rendered at twice the resolution has the same grain size as the one on
    // screen, just more of it resolved (REQ-V3.7).
    vec2 paper_uv = UV * (paper_mm / grain_mm);
    vec2 hatch_uv = UV * (paper_mm / hatch_mm);
    float fibre = texture(texture_grain, paper_uv).r;
    vec3 paper = paper_colour.rgb * mix(vec3(1.0), vec3(fibre), grain);

    // --- hatch follows the wash's mid-tones --------------------------------
    float mid = smoothstep(0.15, 0.55, wash.a) * (1.0 - smoothstep(0.65, 1.0, wash.a));
    float hatch_mask = mix(1.0, texture(texture_hatch, hatch_uv).r, mid * hatch);

    // --- compose -----------------------------------------------------------
    // The pigment's strength is the layer's own alpha, which the wash table set: the
    // table is the one place that knows what medium it is describing, so there is no
    // second global opacity on top of it.
    vec3 pigment = wash.rgb * hatch_mask * mix(vec3(1.0), vec3(0.72), edge * edge_darkening);
    vec3 colour = mix(paper, pigment, wash.a * covered);

    // The ink goes over all of it.
    float ink = texture(texture_ink, UV).a;
    ink = smoothstep(0.5 - ink_softness * 0.5, 0.5 + ink_softness * 0.5, ink) * ink;
    vec3 ink_colour = texture(texture_ink, UV).rgb;
    colour = mix(colour, ink_colour, ink);

    COLOR = vec4(colour, 1.0);
}
```

**Two corrections to this shader's first draft, both forced by building it.** They are
the two ways a paper texture quietly stops working:

1. **It took pixel counts.** The first draft converted its lengths with
   `texels_per_mm`, and bled in pixels (`bleed_pixels`). With `paper_uv = UV *
   (paper_mm * texels_per_mm)` the grain's repeat is fixed in *texels*, so a 2× bake
   came out with grain half the size — the exact failure REQ-V3.7 names, on the page
   that names it. Every length is now millimetres and the sheet converts them; the
   shader has no uniform a resolution could arrive through, and a test asserts the
   uniform set is what it says (§14, AC-V6).
2. **The repeat and the texture's size are a pair.** A grain repeat of 0.25 mm put the
   whole 64-texel fibre texture inside one and a half texels of the sheet, where the
   mip filter averaged it into a flat colour: the sheet came out *perfectly smooth*
   with the grain set to 0.16, and nothing failed. The shipped repeat is 3 mm, the
   texture is 64 texels, and `SketchCompositor.minification_for()` with a test holds
   the two together. The measurement that caught it was crude and worth repeating:
   sample a row of the finished sheet and count how many adjacent pixels are identical.
   Grain means that count is near zero.

Also corrected: `wash_opacity` is gone. The wash table's per-layer `opacity` is the
pigment's strength, and a second global opacity on top of it was two controls for one
thing — with the per-layer one being the one that knows what medium it is describing.

REQ-V3.7 Grain, hatch and bleed shall be expressed in paper millimetres, and
converted using the paper size, so that a still rendered at 2× or 4× has the same
texture scale as the screen. A 4K export that looks like a zoomed 1080p export is
a failure of this requirement.

REQ-V3.8 The sketch shader shall not sample `hint_screen_texture`. Its inputs are
its own layers, which makes it order-independent and testable.

---

## 4. Colour-wash overlays

### 4.1 What a wash is

A wash is a closed region of ground, filled with a flat translucent colour that
bleeds a little past its own edge and is darker where it stops. It is not a texture
and it is not a light. It is the watercolour tray: planting beds, lawn, mulch,
water, and nothing else.

The wash is *under* the ink (§2.1), which means a wash edge is drawn by the colour
stopping, not by an outline — unless the design draws one, in which case the ink
puts it on top.

### 4.2 The wash table

Keyed by layer, because a layer is what the drawer already chose, and mirrored on
`PlanStyle.COLOURS` so the flat working view and the painted view agree about which
green is lawn.

```gdscript
class_name WashTable
extends RefCounted
## What colour each layer washes in, and how it behaves when it does.
##
## Keyed by layer name, like PlotStyleTable is keyed by pen slot and PlanStyle by
## material resource. A layer missing from this table is a wash that does not
## happen, and `wash_for()` says so by returning an empty dictionary rather than
## guessing: a bed washed in the wrong colour is worse than a bed that is only
## inked.
##
## `colour` is the pigment, `opacity` how much paper it lets through, `bleed_mm`
## how far it runs past its own edge, `mottle` how much it wanders within the
## region, and `wet_edge` how dark it goes where it stops. All lengths are paper
## millimetres, like every other authored length in this project.

## A plant is washed by its own name rather than by a layer, because a plant is not
## on a layer: it is a prop that happens to sit on one. Naming it here keeps every
## wash behind one lookup, so `wash_for()` stays the only way in.
const PLANTING_PROPS := "planting_props"

const WASHES := {
    LayerSet.NEW_HARDSCAPE: {
        "colour": Color(0.804, 0.792, 0.753), "material": STONE,
        "opacity": 0.34, "bleed_mm": 0.6, "mottle": 0.10, "wet_edge": 0.10,
    },
    LayerSet.NEW_STRUCTURE: {
        "colour": Color(0.616, 0.502, 0.361), "material": FENCE_WOOD,
        "opacity": 0.40, "bleed_mm": 0.8, "mottle": 0.14, "wet_edge": 0.16,
    },
    LayerSet.NEW_BED: {
        "colour": Color(0.706, 0.596, 0.451), "material": SOIL,
        "opacity": 0.50, "bleed_mm": 1.2, "mottle": 0.45, "wet_edge": 0.22,
    },
    LayerSet.NEW_PLANTING: {
        "colour": Color(0.42, 0.62, 0.329), "material": FOLIAGE,
        "opacity": 0.50, "bleed_mm": 2.0, "mottle": 0.38, "wet_edge": 0.30,
    },
    LayerSet.NEW_TURF: {
        "colour": Color(0.655, 0.784, 0.451), "material": LAWN,
        "opacity": 0.42, "bleed_mm": 1.0, "mottle": 0.30, "wet_edge": 0.16,
    },
    LayerSet.EXISTING_HARDSCAPE: {
        "colour": Color(0.804, 0.792, 0.753), "material": STONE,
        "opacity": 0.20, "bleed_mm": 0.5, "mottle": 0.08, "wet_edge": 0.06,
    },
    LayerSet.EXISTING_STRUCTURE: {
        "colour": Color(0.929, 0.918, 0.878), "material": STUCCO,
        "opacity": 0.22, "bleed_mm": 0.4, "mottle": 0.05, "wet_edge": 0.05,
    },
    LayerSet.EXISTING_PLANTING: {
        "colour": Color(0.871, 0.863, 0.792), "material": ROUGH_GRASS,
        "opacity": 0.35, "bleed_mm": 1.6, "mottle": 0.35, "wet_edge": 0.24,
    },
    PLANTING_PROPS: {
        "colour": Color(0.42, 0.62, 0.329), "material": FOLIAGE,
        "opacity": 0.58, "bleed_mm": 2.2, "mottle": 0.42, "wet_edge": 0.38,
    },
}


## The wash for a layer, or {} when that layer does not wash. Takes a name in either
## form: a layer name arrives as a StringName from the document and as a String from a
## literal.
static func wash_for(layer_name) -> Dictionary:
    return WASHES.get(StringName(layer_name), {})
```

**Three corrections to this table's first draft, all found by building it.** They are
recorded because each one is a trap that the specification itself set:

1. **The keys were invented layer names.** The first draft washed
   `LayerSet.PLANTING_BED`, `WATER`, `MULCH` and `GROUNDCOVER`, none of which this
   project has — which violates REQ-V13.1 on the specification's own page. The keys are
   now the real ones: `300-NEW-HARD`, `301-NEW-STRUCT`, `400-NEW-BED`, `401-NEW-PLANT`,
   `402-NEW-TURF` and the existing layers.
2. **There is no water or mulch layer**, so REQ-V4.6's "water and mulch differ from
   planting" has nowhere to land as written. Mulch *patterns* live on `600-HATCH` — a
   pattern layer, which must not wash (REQ-V4.2) — so the bed layer carries the soil
   medium's behaviour instead. A water feature layer is the open question (§16), not a
   wash entry nobody can select.
3. **Each entry names the material its pigment comes from**, and a test asserts
   `colour == PlanStyle.COLOURS[material]`. That is REQ-V4.1 made mechanical rather
   than remembered: the working view's flat colour and the painted wash cannot drift,
   because a palette change the wash table does not follow fails the test.

**A layer that deliberately does not wash says why**, in `WashTable.NO_WASH`: a contour
is a line, irrigation is below ground, an annotation is an annotation, a tracing aid
does not plot. A reader asking why their irrigation layer has no colour gets the answer
from the code rather than from a missing entry that looks like an oversight.
```

REQ-V4.1 The wash table shall be keyed by layer name, and a washable layer shall
have one entry serving both the working view's flat colour and the painted view's
wash, so the two cannot drift.

REQ-V4.2 Non-plotting layers (construction, tracing aids) shall not wash. A wash
is a picture of what will be built.

### 4.3 Which regions wash

A wash region is the closed area of an entity that *is* an area:

| Entity | Washes? | Region |
|---|---|---|
| `POLYGON`, `RECTANGLE`, `CIRCLE` | Yes | Its own closed outline |
| `ARC`, `LINE`, `POLYLINE` | No | Nothing encloses ground until the drawer closes it |
| A planted prop | Yes | Its footprint from `PlanStyle.footprint_radius()` |
| `DIMENSION`, `TEXT` | No | Annotations are not ground (drafting spec §4) |

Canopy washes are the one that changes how a plan reads. A tree's wash is its
footprint circle, in the species colour, drawn *over* the bed wash and *under* its
own ink. Shrubs and beds the same way. That single rule is what turns a planting
plan from a field of symbols into masses of foliage, and it is the largest visual
return in this whole subsystem.

REQ-V4.3 A bed's wash shall be drawn beneath every plant wash inside it, so a
planted bed reads as foliage over soil rather than soil over foliage.

REQ-V4.4 A prop's wash colour shall come from the same `PlanStyle` entry that
colours it in the working view.

### 4.4 Mottle: one region, three passes

Watercolour is not flat. The wash is painted as three passes of the same region,
each slightly offset and each with its own alpha, which produces the uneven
coverage that reads as pigment:

1. **Flood** — the region at full `opacity`, offset by a quarter of the bleed.
2. **Body** — the region at `opacity × 0.55`, offset the other way.
3. **Pool** — the region at `opacity × 0.30`, offset by the mottle.

```gdscript
class_name WashPainter
extends Node2D
## Paints the wash layer for one bake: the colours under the drawing.
##
## Plain CanvasItem calls rather than an ink shader, because the mottle is a
## property of the *region* - three offset passes of one polygon - and not of the
## pixels. The compositor then adds paper, grain, the wet edge and the ink on top
## (§3.5).
##
## The painter works in **model metres**, like every other view in this project, and
## the paper millimetres it is authored in (bleed, mottle) are converted by the same
## law the line weights use. Its transform is set by the baker, which owns the one
## framing both layers share (§3.4) - a painter that positioned itself would be a
## second opinion about where the drawing sits on the paper.

## The three passes, as a share of the pigment and an offset in bleed units.
const PASSES := [
    {"alpha": 1.00, "offset": Vector2(0.25, -0.18)},
    {"alpha": 0.55, "offset": Vector2(-0.40, 0.30)},
    {"alpha": 0.30, "offset": Vector2(0.60, 0.60)},
]

var _document = null
var _plot_scale: float = 100.0
var _props: Array[Node3D] = []


func _init(document, plot_scale: float, props: Array[Node3D] = []) -> void:
    _document = document
    _plot_scale = plot_scale
    _props = props


func _draw() -> void:
    for region: Dictionary in regions():
        _paint_region(region["region"], region["wash"])


## Every region that washes, in the order it is painted: the drawing's own draw
## order first, then a canopy for every planted prop, so foliage stands over the
## beds it grows in rather than under them (REQ-V4.3).
##
## Separate from `_draw()` because this is the part with a promise in it. "A bed
## washes and a dimension does not" is a list, and a list can be asserted; what
## `draw_colored_polygon` did with it cannot be (REQ-V14.2).
func regions() -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    if _document != null:
        for entity in _document.plotting_entities():
            var layer = _document.layers.get_layer(entity.layer)
            if layer == null:
                continue
            var wash: Dictionary = WashTable.wash_for(layer.name)
            if wash.is_empty():
                continue
            var region: PackedVector2Array = CadSolid.outline_of(entity)
            if region.size() < CadSolid.MIN_RING_POINTS:
                continue
            out.append({
                "region": region, "wash": wash,
                "seed": int(entity.id), "what": String(layer.name),
            })
    for entry: Dictionary in canopies():
        out.append(entry)
    return out


## A plant's footprint as a closed ring in model metres, in the shape the working
## plan draws it: a disc for a tree or a shrub, a rectangle for a bed.
##
## Found by looking at a painted plan rather than by reasoning about it. A circle is
## right for a trunk and a canopy and wrong for a bed 2.6 m by 1.4 m: the first
## version washed every prop as a disc and put round colour under oblong symbols. The
## shape therefore comes from the same table as the colour - the one entry that
## describes the prop in the plan.
func _canopy_region(node: Node3D) -> PackedVector2Array:
    var size: Vector2 = PlanStyle.footprint_size(node)
    var centre := Vector2(node.global_position.x, node.global_position.z)
    if size.x <= 0.0 or size.y <= 0.0:
        return PackedVector2Array()
    var symbol: int = int(PlanStyle.spec_for(node.scene_file_path)["symbol"])
    if symbol in [PlanStyle.Symbol.TREE, PlanStyle.Symbol.SHRUB]:
        return _disc(centre, size.x * 0.5)
    return _rectangle(centre, size)


## A plant's canopy, washed in its species colour. One entry per prop that has a
## colour; a prop the style table does not describe gets none, and keeps its ink, so
## what is missing reads as a plant with no foliage wash rather than as a plant with
## the wrong one.
func canopies() -> Array[Dictionary]:
    ...
    var colour: Color = PlanStyle.wash_colour_for(node)
    if colour.a <= 0.0:
        continue
    var wash: Dictionary = WashTable.wash_for(WashTable.PLANTING_PROPS)
    wash["colour"] = colour
    ...


## One region, painted as three offset passes.
##
## Every length the wash is authored in is a paper length, so it is converted here
## and nowhere else: `model_width_m` is the same law the line weights use, which is
## what stops the wash and the ink disagreeing about how big a millimetre is.
func _paint_region(region: PackedVector2Array, wash: Dictionary) -> void:
    var colour: Color = wash["colour"]
    var bleed: float = LineStyle.model_width_m(float(wash["bleed_mm"]), _plot_scale)
    var mottle: float = float(wash["mottle"])
    var opacity: float = float(wash["opacity"])
    for pass_index in PASSES.size():
        var pass_data: Dictionary = PASSES[pass_index]
        var offset: Vector2 = pass_data["offset"] * bleed
        var shifted := PackedVector2Array()
        for point in region:
            shifted.append(point + offset)
        # Each pass carries its own share of the pigment. The wobble (REQ-V4.5)
        # arrives with the ink pass in phase 2, from the region's own seed.
        draw_colored_polygon(shifted, Color(colour, opacity * float(pass_data["alpha"])))
```

**`PlanStyle` was the second correction.** A prop's wash colour was first specified as
coming from "the species", and the obvious reading of that was the first
`MeshInstance3D` under the prop — which is a tree's *trunk*, so trees washed in bark
brown. The colour now comes from the prop's own `SYMBOLS` entry, which already describes
the symbol and the size: one entry that says how a prop looks in the plan, whether the
plan is flat or painted.

REQ-V4.5 A wash region shall be wobbled with a seed derived from the entity's id,
so the wash edge and the ink drawn over it wander together rather than apart.

REQ-V4.6 Water and mulch shall differ from planting in `bleed_mm`, `mottle` and
`wet_edge`, not by adding a pattern. Their difference is how the medium behaves,
and the table is where a medium's behaviour belongs.

### 4.5 The screen-texture rule, and why the wash does not need it

Reading the screen from a 2D shader is available in Compatibility, but it has a
rule that bites as soon as there are two such shaders: the first node to use
`hint_screen_texture` triggers **one** full-screen copy, and every later node reads
that same copy — so a second screen-reading effect cannot see the first one's
output, and one of them appears to do nothing at all. The documented fix is an
explicit `BackBufferCopy` between them.

This specification avoids the problem rather than solving it: **no layer reads the
screen.** The compositor reads its own baked layers as ordinary textures (§3.5), so
the layers compose in a defined order by construction.

REQ-V4.7 No shader in this subsystem shall use `hint_screen_texture`. If an effect
genuinely needs the accumulated frame, it shall be a final compositor pass with an
explicit `BackBufferCopy` before it, and the reason shall be recorded at the call
site.

---

## 5. Texture-based rendering for hardscape

### 5.1 Extend the procedural pattern; do not replace it

The yard's 12 materials are procedural: a `Gradient` ramped into a
`NoiseTexture2D`, with `uv1_scale` set. That pattern is worth keeping — it is
small, it is version-control friendly (a `.tres` of numbers, not a photograph), and
it already covers lawn, stone, soil, stucco, shingle, timber and foliage.

A textured hardscape is the same resource with real maps added:

```gdscript
class_name HardscapeMaterial
extends RefCounted
## Builds a hardscape material from a texture set.
##
## StandardMaterial3D, not a spatial shader, wherever it will do. That is what the
## Compatibility renderer is tuned for, it already supports ORM packing and
## triplanar projection, and it can be inspected and tweaked by hand in the editor
## - which a customer-facing material library has to be.

## One entry per texture set. Files are relative to
## `resources/textures/hardscape/`. `tile_m` is how many metres one repeat of the
## texture covers, which is the number that decides whether paving reads as paving:
## a paver texture stretched across a patio reads as wallpaper.
const SETS := {
    "paver_granite": {
        "albedo": "paver_granite_albedo.png",
        "normal": "paver_granite_normal.png",
        "orm": "paver_granite_orm.png",
        "tile_m": 1.6, "roughness": 0.82, "metallic": 0.0,
    },
    "paver_sandstone": {
        "albedo": "paver_sandstone_albedo.png",
        "normal": "paver_sandstone_normal.png",
        "orm": "paver_sandstone_orm.png",
        "tile_m": 1.6, "roughness": 0.88, "metallic": 0.0,
    },
    "deck_timber": {
        "albedo": "deck_timber_albedo.png",
        "normal": "deck_timber_normal.png",
        "orm": "deck_timber_orm.png",
        "tile_m": 0.9, "roughness": 0.74, "metallic": 0.0,
    },
    "mulch_bark": {
        "albedo": "mulch_bark_albedo.png",
        "normal": "mulch_bark_normal.png",
        "orm": "mulch_bark_orm.png",
        "tile_m": 0.8, "roughness": 0.95, "metallic": 0.0,
    },
    "render_stucco": {
        "albedo": "render_stucco_albedo.png",
        "normal": "render_stucco_normal.png",
        "orm": "render_stucco_orm.png",
        "tile_m": 1.2, "roughness": 0.92, "metallic": 0.0,
    },
}


## A material for a set name. `world_triplanar` defaults on for the reason in
## §5.2: geometry extruded from an outline has no useful UVs of its own.
static func build(set_name: String, world_triplanar: bool = true) -> StandardMaterial3D:
    var spec: Dictionary = SETS.get(set_name, {})
    if spec.is_empty():
        # Loud, per REQ-V5.4: a paving texture that is silently grey is a bug
        # nobody reports.
        push_error("HardscapeMaterial: no texture set named '%s'" % set_name)
        return null
    var material := StandardMaterial3D.new()
    material.albedo_texture = _load(spec["albedo"])
    material.normal_enabled = true
    material.normal_texture = _load(spec["normal"])
    # One texture, three channels: Godot reads occlusion from R, roughness from G
    # and metallic from B, which is exactly what a purchased ORM map already is.
    material.orm_texture = _load(spec["orm"])
    material.roughness = float(spec["roughness"])
    material.metallic = float(spec["metallic"])
    var tile: float = float(spec["tile_m"])
    material.uv1_scale = Vector3.ONE / tile
    if world_triplanar:
        material.uv1_world_triplanar = true
        # A soft blend: a hard triplanar seam is visible on a low-poly slab, and
        # every slab here is low-poly.
        material.uv1_triplanar_sharpness = 1.4
    return material


static func _load(file_name: String) -> Texture2D:
    var path := "res://resources/textures/hardscape/" + file_name
    var texture: Texture2D = load(path)
    if texture == null:
        push_error("HardscapeMaterial: missing texture %s" % path)
    return texture
```

**Three corrections from building this.** The table above is the shipped one.

1. **The sets are generated, not bought** — which answers §16's fourth question, and the
   answer changes the shape of the work. Only the **albedo** of a set is drawn; the
   `normal` and `orm` maps are *derived from it* by `TextureSetBuilder`, so a set cannot
   have a normal map that disagrees with the picture it normal-maps. The derivation is
   script in the repository rather than a step somebody ran once: it can be re-run at a
   different resolution or a different strength, and it tiles, because the albedo does.
2. **`water_still` is gone.** The specification lists it and this project has no water
   layer to draw a pond on — `SolidTable.MISSING` records the same finding from the other
   end. A texture set nothing can use is a setting that does nothing, which is the
   failure mode this whole specification's "corrections" sections exist to catch.
   `render_stucco` takes its place, because a building is the one hardscape that already
   exists in the drawing.
3. **`uv1_scale = Vector3.ONE / tile` is right and worth spelling out**, because the
   obvious reading of "tile_m: 1.6" is a scale of 1.6. It is a *tile size*, so the scale
   goes the other way — and a material built the wrong way round gives paving that is
   1.6× too coarse, which reads as plausible and is not a set anybody will report.

### 5.2 World triplanar, because CAD geometry has no UVs

Geometry extruded from a 2D outline (§8) has positional data and nothing else.
Generating UVs for it means deciding which axis is "up the wall", and getting that
wrong on a rotated patio is exactly the kind of bug that appears only in a render.
`uv1_world_triplanar` projects from world axes and blends by normal, so *any*
geometry receives a correctly scaled texture with no UV work at all.

The cost is a seam where a surface turns a corner — softened by
`uv1_triplanar_sharpness` — and a slightly higher shader cost. For hardscape, which
is flat surfaces meeting at right angles, that is a good trade.

REQ-V5.1 Extruded geometry shall use world-triplanar mapping, or shall be given
authored UVs deliberately with the reason recorded. It shall never ship with
default box-projected UVs and a stretched texture.

REQ-V5.2 `tile_m` shall be a property of the texture set, in metres, and shall be
the number the material is built from. Texel density that lives only in an
inspector is a number that drifts.

### 5.3 Where a spatial shader is justified, and nowhere else

Three cases:

1. **A stylised preview** that quantises diffuse light into bands, so the 3D view
   reads as the same medium as the painted plan. This is a `spatial` shader with a
   `light()` function on `DIFFUSE_LIGHT`, and it is what the presentation tier
   switches the hardscape to when the client wants the drawing's look in 3D (§7.2).
2. **Foliage**, with per-instance colour variation, wind sway and a two-sided leaf
   cutout (§7.4).
3. **Water**, with a normal map drifting at two speeds and a fresnel term.

Everything else — paving, timber, render, stone — is a `StandardMaterial3D`. A
custom shader is a thing that must be tested and re-tuned whenever the renderer
changes; it is not a default.

REQ-V5.3 A hardscape material shall be a `StandardMaterial3D` unless it falls in
one of the three cases above.

### 5.4 The catalog is a table, and a missing entry is loud

The set table (§5.1) is the catalog. It is keyed by name rather than by file path,
so moving the texture pack does not break the materials, and a set missing its
normal map raises at load rather than rendering flat.

REQ-V5.4 Requesting an unknown texture set shall raise an error and return null,
not a default material.

---

## 6. Shadow, highlight and soft edges

### 6.1 The sun

The scene already has one `DirectionalLight3D` with shadows, `energy = 1.15` and
`directional_shadow_max_distance = 90.0`. The yard is 28 × 20 m inside a fence, so a
shorter max distance buys shadow resolution for nothing:

| Property | Working | Presentation | Why |
|---|---|---|---|
| `shadow_enabled` | true | true | The one shadow that matters outdoors. |
| `directional_shadow_max_distance` | 90.0 | 45.0 | A smaller range means sharper shadows, and nothing outside the fence casts one worth seeing. A **floor** rather than the whole answer: the framing raises it to cover the garden (REQ-V6.6, §8.8 item 10). |
| `directional_shadow_mode` | PSSM 4 splits | PSSM 2 splits | Two splits at this scale, more texels in each. |
| `shadow_blur` | 0.0 | by tier | §6.6; support on this renderer to be confirmed on the machine. |
| `shadow_bias`, `shadow_normal_bias` | as-is | as-is | Already tuned. Changing bias for a render is how peter-panning gets shipped. |

REQ-V6.1 A presentation tier may change shadow resolution, split count and blur,
but shall not silently change light energy. Because this renderer draws a shadowed
light in a different colour space (§1.3), energy tuned with shadows on looks wrong
with them off and vice versa.

REQ-V6.6 A tier's shadow range shall be the greater of its own budget and the distance that
covers the framed garden as the camera sees it. A range shorter than that is not a cheaper
shadow, it is no shadow at all, over the whole subject at once - which is the failure a sun
path renders in six frames and a table of numbers cannot show at all.

### 6.2 What stands in for global illumination

There is no GI here. The 3D picture is lit by the sky (`ProceduralSkyMaterial`) as
ambient at `ambient_light_energy = 0.55`, the sun as direct light, and a *painted*
contact darkening as the cue that objects sit on the ground.

That is enough for a garden, because a garden is outdoors, mostly flat, and lit
from one direction. The thing that would give it away is missing contact shadow,
which is why §6.4 exists and why it is not optional.

REQ-V6.2 The presentation environment shall use the sky as its ambient light
source and shall not substitute a flat `ambient_light_color`.

### 6.3 Simplified SSAO

Available since 4.6 on this renderer, with **radius and intensity only**. It is
genuinely useful for planting beds and wall-to-ground junctions:

```
ssao_enabled = true
ssao_radius = 1.2      # metres: roughly a shrub's width
ssao_intensity = 1.6
```

Everything else on the environment's SSAO block (`ssao_power`, `ssao_detail`,
`ssao_horizon`, `ssao_sharpness`, `ssao_light_affect`) is ignored by this renderer,
so setting it is a misleading no-op.

REQ-V6.3 The presentation shall not set SSAO properties this renderer does not
honour. Setting `ssao_power` here does nothing, and a reader of the code would
believe it did.

### 6.4 Contact shadow, painted

Under every plant, and along every wall and kerb, the presentation adds a soft
darkening that is *authored* rather than computed: concentric passes of translucent
dark brown under each footprint, at falling alpha.

This is the trick the working plan view already uses (`PlanStyle.SHADOW_OFFSET`
plus a soft underlay), promoted to the presentation layer, and it is what makes an
un-GI'd scene read as grounded.

```gdscript
class_name ContactShadow
extends RefCounted
## The darkening under a thing, which is what says the thing is standing on the
## ground rather than pasted over it.
##
## There is no GI on this renderer (§6.2), so this is authored. Concentric passes
## at falling alpha stand in for a blur: cheaper than a real blur, and - unlike a
## blur - it has a defined size on paper.

## Radii as multiples of the footprint radius, and their alphas. Three passes is
## enough for an edge to read as soft at any size a client will look at.
const PASSES := [
    {"scale": 1.30, "alpha": 0.16},
    {"scale": 1.10, "alpha": 0.20},
    {"scale": 0.90, "alpha": 0.26},
]
const COLOUR := Color(0.20, 0.18, 0.14)
## How oblong a shadow is across the direction it falls. A shadow on the ground is
## longer along the ground than across it.
const FORESHORTEN := 0.72
## Segments around the ellipse. Below 20 the wobble has nothing to work with and
## the shadow goes visibly polygonal.
const SEGMENTS := 28


## Draw one contact shadow, offset along the ground direction the sun casts.
## `sun_azimuth` is the sun's bearing in radians, from `SunStudy` (§7.3), so the
## 2D shading and the 3D sun agree about where the light is.
static func draw_shadow(
    canvas: CanvasItem, centre: Vector2, radius_m: float,
    plot_scale: float, sun_azimuth: float
) -> void:
    # The offset is authored as a share of the footprint and scaled into paper
    # millimetres, like every other mark in this subsystem.
    var offset_m: float = radius_m * 0.45 * plot_scale * 0.001
    var direction := Vector2(sin(sun_azimuth), cos(sun_azimuth))
    var at: Vector2 = centre + direction * offset_m
    # The shadow's own axis is the direction the sun throws it, so it is drawn in
    # a rotated frame rather than always across the screen.
    var frame := Transform2D(direction.angle(), at)
    for pass_data in PASSES:
        var scale: float = float(pass_data["scale"])
        var points := PackedVector2Array()
        for step in SEGMENTS:
            var angle: float = TAU * float(step) / float(SEGMENTS)
            var local := Vector2(
                cos(angle) * radius_m * scale,
                sin(angle) * radius_m * scale * FORESHORTEN
            )
            points.append(frame * local)
        canvas.draw_colored_polygon(points, Color(COLOUR, float(pass_data["alpha"])))
```

REQ-V6.4 Every planted prop, wall and kerb shall contribute a contact shadow in
the painted path, using a footprint from the same `PlanStyle` table the working
view uses. A prop with no contact shadow floats.

REQ-V6.5 The shadow's offset direction shall be derived from the sun's azimuth, so
the 2D shading and the 3D sun point the same way. Two shadows pointing different
ways in one proposal is exactly what a client notices without being able to say
why.

### 6.5 Highlights

Two cheap and honest tools:

1. **Rim light** on planting: `StandardMaterial3D.rim_enabled`, a low `rim` and a
   green-ish `rim_tint`, so foliage edges separate from the ground behind.
2. **`grow` outlines** at the stylised tier: `BaseMaterial3D.grow` plus
   `grow_amount` pushes a copy of the geometry outward and draws it in the ink
   colour, giving a 3D object a drawn edge. This is the 3D counterpart of §3.3's
   double stroke, and it is the same idea: the edge is drawn, not computed.

REQ-V6.6 The stylised tier's outline colour and width shall be derived from the
plotted pen table (`PlotStyleTable`), so the 3D outline and the 2D ink agree about
which line is heavy.

### 6.6 Soft edges

Three places, in order of how much they matter:

1. **Supersampling** (§10.2) — the only soft edge that is free of artefacts and the
   only one that works regardless of the renderer.
2. **`shadow_blur`** on the sun — confirm on this machine before relying on it. If
   it is ignored, the fallback is supersampling plus a small blur in the still
   compositor.
3. **A softened compositor edge** — in the still path only, the shader's ink ramp
   (§3.5) plus a half-pixel blur after compositing, which rounds whatever
   stair-stepping survived the supersample.

REQ-V6.7 Any softening that depends on a renderer feature shall have a working
fallback, and the fallback shall be the one the still export uses.

---

## 7. The 3D preview mode

### 7.1 One scene, a different eye

The preview is `scenes/main.tscn` with a presentation camera and an optional
material override. It is not a copy of the yard: a copy would drift, and the first
time a client's preview showed a plant the designer had deleted two weeks ago the
whole feature would be abandoned.

```gdscript
class_name PresentationDirector
extends Node3D
## Drives the presentation: which eye, which quality, which materials.
##
## Everything this node does is reversible. It holds no design state and writes
## none; it records what it changed and puts it back, so a presentation can end
## mid-sentence and the designer's session is exactly as they left it.

const Tier := preload("res://scripts/vis/presentation_tier.gd")

@export var yard: Node3D
@export var sun: DirectionalLight3D
@export var orbit_rig: Node3D
@export var world_environment: WorldEnvironment
@export var drafting_overlay: Node3D
@export var planning_hud: CanvasLayer

var _tier: int = Tier.WORKING
## Everything the director changed, so it can be un-changed (REQ-V7.1).
var _restore: Array[Dictionary] = []


## Enter presentation. `tier` picks the look; nothing here touches the document.
func begin(tier: int = Tier.PRESENTATION) -> void:
    _tier = tier
    var environment: Environment = world_environment.environment
    _remember(sun, "directional_shadow_max_distance")
    _remember(sun, "shadow_blur")
    _remember(environment, "ssao_enabled")
    _remember(environment, "ssao_radius")
    _remember(environment, "ssao_intensity")
    _remember(drafting_overlay, "visible")
    _remember(planning_hud, "visible")
    var look: Dictionary = Tier.LOOKS[tier]
    sun.directional_shadow_max_distance = float(look["shadow_max_distance"])
    sun.shadow_blur = float(look["shadow_blur"])
    environment.ssao_enabled = bool(look["ssao"])
    environment.ssao_radius = float(look["ssao_radius"])
    environment.ssao_intensity = float(look["ssao_intensity"])
    # The drafting overlay is an annotation layer, not sure design (§7.5), and the
    # HUD is the cursor's furniture.
    drafting_overlay.visible = false
    planning_hud.visible = false


## Leave presentation, putting back every property that was changed.
func end() -> void:
    # Reversed, so a property recorded twice is restored in the order it was set.
    for index in range(_restore.size() - 1, -1, -1):
        var change: Dictionary = _restore[index]
        # `set` rather than a typed assignment: the recorded target is an Object
        # and the property is a name, which is the only honest way to undo a
        # heterogeneous list of changes without a branch per property.
        change["target"].set(String(change["property"]), change["value"])
    _restore.clear()
    _tier = Tier.WORKING


func _remember(target: Object, property: String) -> void:
    _restore.append({
        "target": target, "property": property, "value": target.get(property),
    })
```

REQ-V7.1 Presentation mode shall be reversible, and shall record what it changed
before it changes it. A presentation that leaves the designer's lighting altered is
worse than no presentation mode.

REQ-V7.2 The preview shall use the same `Yard` node. It shall not instantiate a
second copy of the design.

### 7.2 Quality tiers

```gdscript
class_name PresentationTier
extends RefCounted
## One value that sets every rendering budget at once.
##
## A quality setting scattered across five scripts cannot be changed with
## confidence, and cannot be tested: this is the table those settings live in.

const WORKING := 0
const PRESENTATION := 1
const STILL := 2

## The budgets. `supersample` is the render scale the still path uses (§10.2);
## it is 1 for the interactive tiers because the screen is the screen.
const LOOKS := {
    WORKING: {
        "shadow_max_distance": 90.0, "shadow_blur": 0.0,
        "ssao": false, "ssao_radius": 1.2, "ssao_intensity": 1.6,
        "textured": false, "supersample": 1, "stylised": false,
    },
    PRESENTATION: {
        "shadow_max_distance": 45.0, "shadow_blur": 1.2,
        "ssao": true, "ssao_radius": 1.2, "ssao_intensity": 1.6,
        "textured": true, "supersample": 1, "stylised": false,
    },
    STILL: {
        # A still is allowed to be slow: it is rendered once and looked at for
        # months. This is where every budget is spent.
        # The distance below is a floor under the framing and not a promise about where
        # the camera stands: a garden framed from 62 m raises it to 84 m, because at 30 m
        # the whole subject falls outside the range and the still comes back with no cast
        # shadow anywhere in it (REQ-V6.6).
        "shadow_max_distance": 30.0, "shadow_blur": 1.4,
        "ssao": true, "ssao_radius": 1.0, "ssao_intensity": 2.0,
        "textured": true, "supersample": 2, "stylised": true,
    },
}


## The budget for a tier. An unknown tier gets the working budget rather than an
## empty dictionary, because a preview that renders too plainly is recoverable and
## a preview that renders with no shadow map is not.
static func look(tier: int) -> Dictionary:
    return LOOKS.get(tier, LOOKS[WORKING])


static func name_of(tier: int) -> String:
    match tier:
        PRESENTATION:
            return "Presentation"
        STILL:
            return "Still (proposal)"
        _:
            return "Working"
```

REQ-V7.3 A tier shall be a single value that sets every budget, and the budgets
shall live in one table. No presentation setting shall be read from anywhere else.

### 7.3 Sun study

A client asks what the patio looks like at four in the afternoon in June. The sun is one
node, and the answer needs more than a latitude: a longitude, the zone offset in force at the
site, and a sun that will stand up to being checked against the client's own kitchen window.

**Answered (spec §16.6): astronomical.** The position comes from Meeus's *Astronomical
Algorithms* as the NOAA solar calculator uses it - the mean longitude and anomaly, the
equation of the centre, the apparent longitude with aberration and nutation, the obliquity of
the ecliptic, the declination, and the equation of time - with Saemundsson's expression for
atmospheric refraction. That is good to about a hundredth of a degree in any year a garden is
designed for, which is a centimetre of shadow direction for every metre of shadow. **So the
astronomy is no longer the limiting error in a study; the drawing is** - a survey point a
metre out or a roof height guessed by eye moves a shadow further than the sun ever will, and
REQ-V7.14 is there to stop this subsystem claiming otherwise.

Two consequences are visible to a user, and they are the reasons to have done it:

- **A noon that is the clock's noon.** The equation of time is worth up to sixteen minutes,
  and a site's longitude and zone offset up to an hour between them. The panel's hour is the
  clock at the site (REQ-V7.11), so "four in the afternoon" means what the client's watch
  says, and the shadow is cast for that moment rather than for one sixteen minutes away.
- **A sunrise and a sunset.** The same machinery gives them, on the site's own clock, and a
  day that has no sunrise at all says so rather than being given one (REQ-V7.13).

```gdscript
class_name SunStudy
extends RefCounted

## The year the study is computed for. Fixed, so that a study repeats and a test is not a
## race with the calendar: the sun moves by less than a hundredth of a degree a year, and
## the day-of-year numbering only tells leap years apart after 28 February.
const EPOCH_YEAR := 2025

## The sun's angular radius, and the refraction at the horizon at the pressure and
## temperature the expression assumes. Together they are why sunrise is the moment the
## upper limb appears rather than the moment the centre's altitude passes zero.
const SEMIDIAMETER_DEG := 0.2666
const REFRACTION_AT_HORIZON_DEG := 0.5667
const SUNRISE_ALTITUDE_DEG := -(SEMIDIAMETER_DEG + REFRACTION_AT_HORIZON_DEG)


# --- the calendar ---
static func julian_day(year: int, month: int, day: int, hour_utc: float = 0.0) -> float
static func month_day_from_day_of_year(day_of_year: int, year: int = EPOCH_YEAR) -> Vector2i
static func day_of_year_from_month_day(month: int, day: int, year: int = EPOCH_YEAR) -> int

# --- the astronomy ---
static func mean_obliquity(jd: float) -> float                # the tilt, without the wobble
static func obliquity(jd: float) -> float                     # the tilt, with the nutation
static func declination_at(jd: float) -> float
static func declination(day_of_year: int) -> float
static func equation_of_time(jd: float) -> float              # minutes: sundial - clock
static func equation_of_time_on(day_of_year: int) -> float
static func refraction(true_altitude_deg: float) -> float     # degrees; 0.57 at the horizon

# --- a site, and a moment ---
static func site(latitude: float, longitude: float, utc_offset_hours: float) -> Dictionary
static func moment(day_of_year: int, clock_hour: float, year: int = EPOCH_YEAR) -> Dictionary
static func solar_time(site: Dictionary, moment: Dictionary) -> float
static func clock_time(site: Dictionary, moment: Dictionary, solar: float) -> float
static func clock_text(hours: float) -> String                # "05:25"

# --- the sun, as seen ---
static func position(latitude: float, day_of_year: int, solar_hour: float) -> Dictionary
static func position_for(site: Dictionary, moment: Dictionary) -> Dictionary
static func daylight(latitude: float, day_of_year: int) -> Dictionary
static func daylight_for(site: Dictionary, moment: Dictionary) -> Dictionary
static func apply_for(light: DirectionalLight3D, site: Dictionary, moment: Dictionary) -> bool
static func describe_for(site: Dictionary, moment: Dictionary) -> String
```

The third argument of `position` is a **solar** hour and the second key of a moment is a clock
hour, and the two are up to sixteen minutes apart: that difference is the point of the site,
and the parameter names say which is which, because the same number meaning two things in two
functions is a trap.

`position_for` returns everything a still's record needs to stand on its own - the altitude,
the azimuth, the declination and the equation of time that produced them, the solar hour, and
the site and the moment they came from (see the record in §10.4).

REQ-V7.4 Sun azimuth shall use the same north-up convention as the plan and the sheet, so a
shadow in the 3D view falls the same way the north arrow promises.

REQ-V7.5 A sun below the horizon shall be reported, not clamped. Whether that becomes a night
scene, a twilight scene or an error is the caller's decision. A sun shall count as up while
its upper limb is above the horizon - half a degree before its centre is - because that is
when it can be seen, and it is also when it begins to cast.

REQ-V7.10 The sun's position shall be computed astronomically, by the routine Meeus gives and
the NOAA calculator uses, with the equation of time and atmospheric refraction in it. The
harmonic approximations are not to be used: a study is worth what it can be checked against,
and the published zeros of the equation of time are the check.

REQ-V7.11 A site shall be a latitude, a longitude and a zone offset, stored together with the
drawing, because a sun study is a question about a place and any two of the three is not an
answer to it. The presentation's hour shall be the **clock** time at the site, which the
study converts to solar time with the longitude, the offset and the equation of time. Daylight
saving shall be part of the offset the site carries and shall not be inferred from a rule,
since every rule is right in one country and wrong in the next.

REQ-V7.12 Refraction shall be reported beside the sun's geometric altitude rather than folded
into it: a shadow is cast by where the light really is, and the horizon is brightened by where
the eye thinks it is. The light a shadow is cast by shall use the geometric altitude.

REQ-V7.13 A study shall report its sunrise and sunset on the site's own clock, and a day with
no sunrise or no sunset shall be reported as polar rather than given a time it does not have.

REQ-V7.14 A study's accuracy shall not be claimed beyond its inputs. The astronomy shall be
good to a hundredth of a degree, which leaves the *drawing* in charge of the error, and the
documentation shall say so rather than implying that a stiller number makes a truer shadow.

### 7.3b The study: a season of moments

Section 7.3's `SunStudy` answers *where is the sun at this moment*, which is a camera position.
The question a garden actually gets asked is a different one - "will the patio be in shade by
four", "will it be in shade in June" - and it is a question about a **list** of moments, because
the person asking does not yet know which moment matters. That list is a **study**, and it is
`SunReport`.

**A study is a list, not a moment.** The page's own subject is the list, and the four ready-made
studies it offers are the four questions gardens get asked: a June day, a December day, the two
equinoxes and the two solstices. Two of those are stated as *sets of days*, because a season is
read the way a day is.

**The site is not stated on the study page.** A latitude, a longitude and a zone offset are a fact
about the drawing, and the presentation panel is where they are edited - a second site form would
be a second answer to one question. The page is *told* a site, and the HUD tells it the
presentation's own `current_site()`; the site's one wording, `site_words`, is also what the
presentation's own `site_text()` prints, so the panel and a study cannot describe one site two
ways.

**The height is stated on the page, and that is the whole of what a study claims.** An entity on
the plan is a shape on the ground and carries no height above it, so a study reports what a
*stated* height casts and never claims to know what is in the shade. `DEFAULT_HEIGHT_M` is 1.8 m,
and the figure is in the drawing's own units, because a drawing in feet gets a field in feet.

**A sun that is not up casts nothing, and that is a refusal rather than a zero.** Zero is what a
sun straight overhead casts - the shortest length a shadow can have - so a garden after dark is
reported by naming the moment, and a sun whose *centre* is on the horizon is refused in different
words again ("so the shadow has no end"), because that length is a division by a tangent near zero
rather than a shadow. A sun below `MIN_ALTITUDE_DEG` (5 degrees) is a third case: the length is
stated, because it is arithmetically right, and a note beside it says the number says more about
the hour than the garden - a 46 m shadow at 2 degrees is the honest answer to a question nobody
should be asking with a tree.

**A study's still is named for the moment it shows** - `sun-study-172-1600`, not the wall clock the
render happened to run at - so a folder of a season's stills sorts into the order of the study.
That is why the presenter's `render_still` takes a `base_name`.

**The page promises only the stills it can render.** `render_requested` hands over the moments
with the sun up, so a caller does not have to sort them out and cannot render a garden after dark
by accident; the dark moments are still *rows* of the table, because they are part of the answer.
Nothing is written by the page: the sun is aimed and the stills rendered by signals the HUD acts
on.

```gdscript
class_name SunReport
extends RefCounted

const DAY_HOURS := [8.0, 10.0, 12.0, 14.0, 16.0, 18.0]
const MIN_ALTITUDE_DEG := 5.0          # below this the length is stated, with a note
const DEFAULT_HEIGHT_M := 1.8
static func preset_names() -> Array[StringName]                # june_day, december_day, ...
static func preset(name: StringName) -> Array[Dictionary]      # no such name: EMPTY, not a default
static func still_name(moment: Dictionary) -> String           # "sun-study-172-1600"
static func shadow(site, moment, height_m) -> Dictionary       # the length, the bearing, or why not
static func row_for(site, moment, height_m, units) -> Dictionary  # one row of the table, as words
static func rows(site, moments, height_m, units) -> Array[Dictionary]
static func days(site, moments) -> Array[Dictionary]           # each day once: rise, set, length
static func summary(site, moments, height_m, units) -> String  # the page's own opening sentence
```

The page is `SunWindow`, a `Window` rather than a `Control` for the reason the grading page is:
it has a height to *type into*, so it must take the keyboard while it is up and give it back when
it closes. It holds the study, the day and hour fields the moments are built from, the four preset
buttons, the table of rows, the day lines and the summary.

The HUD joins it in three places: the Present menu's `Sun and shadow study...` entry, a menu line
saying how big the study in hand is and how many of its moments have the sun up, and a
`_tick_sun_window` that rebinds the *site* while the page is up - the study is the page's own and
is never rebound, because a refresh that threw away what a person was building would be the page
arguing with the hand. Rendering is one still at a time and signal-driven: `render_sun_study`
walks the moments, aiming the sun before each shot, and each step is finished by the director's own
report - which is why the walk checks the file name it is handed, so a still the panel's own button
asked for in between is not counted as a step of the study.

REQ-V7.15 A study shall be a list of moments rather than a single moment, read in the order the
moments were chosen. Its ready-made studies shall be the four questions a garden is asked - a June
day, a December day, the equinoxes and the two solstices - and a preset name nobody has shall be an
empty study rather than a default one.

REQ-V7.16 A study's site shall be the drawing's own site, stated in one place, and the study page
shall be told it rather than stating it. A study's cast shall be computed for the height stated in
the study, in the drawing's own units, and no study shall claim to know what is in the shade.

REQ-V7.17 A sun that is below the horizon shall be refused by naming the moment, and a sun whose
centre is on the horizon shall be refused as a shadow with no end. Both are different from a zero,
which is what a sun straight overhead casts. A sun below five degrees shall state its length and a
note saying the hour is doing the talking.

REQ-V7.18 A study's still shall be named for the moment it shows rather than for the time it was
rendered, and a study shall ask for stills only for the moments the sun is up. The page shall
write nothing itself: aiming the sun and rendering the stills are the HUD's acts.

### 7.4 Planting at scale: instancing, with per-instance variation

A planting plan holds hundreds of plants. As nodes, that is hundreds of objects; as
instances of one mesh, it is one draw call.

The verified API in 4.7 is the `use_colors` and `use_custom_data` booleans with the
`color_array` and `custom_data_array` properties. The older
`color_format = MultiMesh.COLOR_FLOAT` constants **no longer exist**, so code
written against them will not compile.

```gdscript
class_name PlantingInstancer
extends MultiMeshInstance3D
## Many of one plant, drawn as instances of one mesh.
##
## Per-instance colour is what stops a mass planting looking like a rubber stamp:
## the same mesh, each instance nudged toward its own green and its own size. The
## nudge comes from the *design* - a plant's position - so the same plan always
## previews the same way (REQ-V7.7).

const PlanStyleScript := preload("res://scripts/plan_style.gd")

## Below this many of one species the props stay ordinary nodes, because an
## instance cannot be hovered, selected or dragged - and picking a plant out of the
## plan is worth more than a draw call (REQ-V7.6).
const INSTANCE_THRESHOLD := 25
## How far an instance may vary, as a fraction of its colour and its size. Small:
## this is a hint, not a kaleidoscope.
const HUE_JITTER := 0.045
const SCALE_JITTER := 0.12


## Instance one mesh across a species. `plants` are the design's 3D props.
func build(plants: Array[Node3D], mesh: Mesh) -> void:
    var multimesh := MultiMesh.new()
    multimesh.mesh = mesh
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    # Colour and custom data are switched on as booleans, and the buffers carry
    # the values.
    multimesh.use_colors = true
    multimesh.use_custom_data = true
    # instance_count must be set before any per-instance value: Godot sizes the
    # buffers from it and refuses the rest until it knows how many there are.
    multimesh.instance_count = plants.size()
    for index in plants.size():
        var plant: Node3D = plants[index]
        # A deterministic jitter from the plant's own position, so two runs of one
        # design are identical. A random jitter would make two renders of the same
        # garden incomparable, which is the one thing a preview must never be.
        var jitter: float = fposmod(
            plant.global_position.x * 12.9898 + plant.global_position.z * 78.233, 1.0
        )
        var size_factor: float = 1.0 + (jitter - 0.5) * 2.0 * SCALE_JITTER
        var basis := Basis.IDENTITY.scaled(
            plant.global_transform.basis.get_scale() * size_factor
        )
        multimesh.set_instance_transform(
            index, Transform3D(basis, plant.global_position)
        )
        # The plant's colour is its plan colour, which is keyed by material - so
        # the wash, the 3D view and the planting schedule all name one green.
        var base: Color = PlanStyleScript.colour_for_material(_species_material(plant))
        multimesh.set_instance_color(index, Color(
            clampf(base.r + (jitter - 0.5) * 2.0 * HUE_JITTER, 0.0, 1.0),
            clampf(base.g - (jitter - 0.5) * HUE_JITTER, 0.0, 1.0),
            clampf(base.b + (jitter - 0.5) * HUE_JITTER, 0.0, 1.0),
            1.0
        ))
        # Custom data carries the sway phase, read in the shader as INSTANCE_CUSTOM,
        # so a mass of foliage does not breathe in unison.
        multimesh.set_instance_custom_data(index, Color(jitter, 1.0 - jitter, 0.0, 0.0))
    multi_mesh = multimesh


## The material that carries a prop's species colour. A prop's mesh may be nested,
## so the first MeshInstance3D found is the one that has it.
func _species_material(plant: Node3D) -> Material:
    for node in plant.find_children("*", "MeshInstance3D", true, false):
        var material: Material = (node as MeshInstance3D).get_surface_override_material(0)
        if material != null:
            return material
    return null
```

REQ-V7.6 Instancing shall be justified by count, not by fashion: below
`INSTANCE_THRESHOLD` of one species the props stay ordinary nodes. An instance
cannot be selected, hovered or dragged individually, and the designer's ability to
pick a plant out of the plan outranks a draw call.

REQ-V7.7 Per-instance variation shall be derived deterministically from the plant's
position or id. A preview that differs between two runs cannot be compared,
reviewed or regressed.

REQ-V7.8 A plant's 3D colour and its 2D wash colour shall come from the same
`PlanStyle` entry.

### 7.5 What the preview hides

| Hidden | Because |
|---|---|
| `DraftOverlay` | Drafting linework in 3D is a working aid; the design's own geometry is what the client is buying. |
| Snap markers, the status line, the selection ring | They are the cursor's furniture. |
| The planning HUD | A client does not need the pen table. |

REQ-V7.9 Entering presentation shall hide the drafting overlay and the working HUD,
and leaving it shall restore exactly what was visible before.

---

## 8. Importing 2D CAD geometry into 3D meshes

### 8.1 The direction of the conversion

The 2D plan is not an import here: it is *the* design, and the 3D is derived from
it. This section is that derivation — the travel of a drawn kerb, patio or raised
bed from a `DraftEntity` into a mesh with a material, a normal and a collider.

One way, always:

```
   DraftEntity ──► outline (metres) ──► prism ──► ArrayMesh ──► MeshInstance3D
        │                                   │                        │
        │                                   └──► collider ◄──────────┘
        └── the entity stays the source of truth; the mesh pictures it
```

REQ-V8.1 A mesh derived from an entity shall be rebuilt from the entity whenever
the entity changes, and shall never be edited in place. A mesh edited in place is a
design fact living in two places, which is the failure this whole specification
exists to prevent.

### 8.2 Entity to outline

`DraftRender.strokes()` already turns every entity kind into model-space polylines,
with arcs and circles expanded to sampled curves. It does not close a polygon's
loop for you and it does not say which way round the loop runs, so the outline
builder adds that and nothing else:

```gdscript
class_name CadSolid
extends RefCounted
## Turns a drawing's entities into solids: patios, kerbs, raised beds, walls.
##
## Every outline comes from DraftRender.strokes(), the same function the working
## plan and the plotted sheet draw from, so a patio in the 3D preview is exactly
## the shape that was drawn and plotted. Nothing here reads an entity's fields: if
## the drawing says it, the mesh says it.

const RenderScript := preload("res://scripts/draft/draft_render.gd")
const EntityScript := preload("res://scripts/draft/draft_entity.gd")
const SolidTableScript := preload("res://scripts/vis/solid_table.gd")
const HardscapeScript := preload("res://scripts/vis/hardscape_material.gd")

## Entity kinds that enclose ground and can become a solid.
const AREA_KINDS: Array[int] = [
    EntityScript.Kind.POLYGON,
    EntityScript.Kind.RECTANGLE,
    EntityScript.Kind.CIRCLE,
]


## The closed outline of an area entity in model metres, wound so that
## `Geometry2D` and the triangulator both trust it. Empty for anything that does
## not enclose ground.
static func outline_of(entity, layer, plot_scale: float) -> PackedVector2Array:
    if not AREA_KINDS.has(int(entity.kind)):
        return PackedVector2Array()
    var strokes: Array[PackedVector2Array] = RenderScript.strokes(entity, layer, plot_scale)
    if strokes.is_empty():
        return PackedVector2Array()
    # A polygon arrives as one closed stroke, a rectangle as four sides, a circle
    # as one sampled ring. Joining them in order gives one loop for all three,
    # which is why the caller never has to know which it was.
    var loop := PackedVector2Array()
    for stroke in strokes:
        for point in stroke:
            if loop.is_empty() or loop[loop.size() - 1].distance_to(point) > 1e-5:
                loop.append(point)
    # A closing point equal to the first is dropped: the loop closes by geometry,
    # and a repeated vertex is a zero-length edge that some of the operations
    # below will object to.
    if loop.size() > 1 and loop[0].distance_to(loop[loop.size() - 1]) < 1e-5:
        loop.remove_at(loop.size() - 1)
    if loop.size() < 3:
        return PackedVector2Array()
    # The winding has to be known, and a hand-drawn loop can arrive either way
    # round depending on the order the picks were made.
    return loop if is_clockwise(loop) else _reversed(loop)


## The shoelace sum: positive when the winding is clockwise in screen coordinates,
## where +y runs down the plan.
static func is_clockwise(loop: PackedVector2Array) -> bool:
    var twice_area: float = 0.0
    for index in loop.size():
        var from: Vector2 = loop[index]
        var to: Vector2 = loop[(index + 1) % loop.size()]
        twice_area += (to.x - from.x) * (to.y + from.y)
    return twice_area > 0.0


static func _reversed(loop: PackedVector2Array) -> PackedVector2Array:
    var out := PackedVector2Array()
    for index in range(loop.size() - 1, -1, -1):
        out.append(loop[index])
    return out
```

### 8.3 A closed outline becomes a slab

The algorithm, in full, because this is the part that has to be right:

1. **Offset the outline** by `inset_m` with `Geometry2D.offset_polygon` and
   `Geometry2D.JOIN_ROUND`. A negative delta shrinks. An offset may return *more
   than one* polygon — a concave outline can pinch into pieces — and each piece is
   a separate slab top.
2. **Triangulate** each piece with `Geometry2D.triangulate_polygon`. It returns
   vertex indices in triples, and an **empty array for a self-intersecting
   outline**, which is a refusal and not an error to paper over.
3. **Build the top face** at `height_m`, and the **bottom face** at `base_m` wound
   the other way so its normal points down.
4. **Join them with sides.** Walk the loop; for each edge, emit two triangles. The
   side walk makes no assumption that the loop is convex.
5. **Normals and tangents** from `SurfaceTool.generate_normals()` and
   `generate_tangents()`, with one smooth group on the top so a patio does not get
   a crease down its middle.
6. **Commit** into an `ArrayMesh`, and derive the collider from that same mesh with
   `MeshInstance3D.create_trimesh_collision()`.

```gdscript
## A slab: a closed outline given thickness. Returns null and says why when the
## outline cannot be made solid, rather than making a broken solid.
static func slab(
    loop: PackedVector2Array,
    base_m: float,
    height_m: float,
    inset_m: float = 0.0,
    uv_scale_metres: float = 1.0
) -> ArrayMesh:
    if loop.size() < 3:
        push_error("CadSolid.slab: an outline needs three points, got %d" % loop.size())
        return null
    var pieces: Array[PackedVector2Array] = []
    if is_zero_approx(inset_m):
        pieces.append(loop)
    else:
        # A negative delta insets. Round joins, because a sawn paving edge is
        # round at this scale, and a mitre join overshoots on a sharp corner and
        # can self-intersect the outline it is supposed to be shortening.
        for piece in Geometry2D.offset_polygon(loop, -absf(inset_m), Geometry2D.JOIN_ROUND):
            if piece.size() >= 3:
                pieces.append(piece)
    if pieces.is_empty():
        push_error("CadSolid.slab: insetting by %.2f m consumed the outline" % inset_m)
        return null

    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    for piece in pieces:
        var indices: PackedInt32Array = Geometry2D.triangulate_polygon(piece)
        if indices.is_empty():
            # Named, because the drawing can be fixed and the mesh cannot be
            # guessed at.
            push_error("CadSolid.slab: the outline self-intersects; not a valid solid")
            return null
        # One smooth group for the whole top: a patio is a plane, not a fan of
        # faceted triangles.
        surface.set_smooth_group(0)
        for index in indices:
            _add_vertex(surface, piece[index], height_m, Vector3.UP, uv_scale_metres)
        surface.set_smooth_group(-1)
        # Sides, flat-shaded, so a kerb has a crisp arris.
        for edge in piece.size():
            _add_side(
                surface, piece[edge], piece[(edge + 1) % piece.size()],
                base_m, height_m, uv_scale_metres
            )
        # The underside, wound downward.
        var bottom := _reversed(piece)
        surface.set_smooth_group(0)
        for index in Geometry2D.triangulate_polygon(bottom):
            _add_vertex(surface, bottom[index], base_m, Vector3.DOWN, uv_scale_metres)
        surface.set_smooth_group(-1)

    surface.generate_normals()
    surface.generate_tangents()
    return surface.commit()


## One vertex, with a UV in metres, so a world-triplanar material and a UV-mapped
## material both have something sensible to read.
static func _add_vertex(
    surface: SurfaceTool, point: Vector2, y: float, normal: Vector3, uv_scale: float
) -> void:
    surface.set_normal(normal)
    surface.set_uv(Vector2(point.x, point.y) / uv_scale)
    surface.add_vertex(Vector3(point.x, y, point.y))


## Two triangles standing on edge between two points of the outline.
static func _add_side(
    surface: SurfaceTool, from: Vector2, to: Vector2,
    base_m: float, height_m: float, uv_scale: float
) -> void:
    var edge := to - from
    # The outward normal of a clockwise loop is the edge turned right. The loop
    # was normalised to clockwise by outline_of(), which is what makes this one
    # line correct instead of a guess per face.
    var normal := Vector3(edge.y, 0.0, -edge.x).normalized()
    var run: float = edge.length() / uv_scale
    # Four corners, in the order that makes two triangles facing outward:
    # (from,base) (to,base) (to,top) and (from,base) (to,top) (from,top).
    for corner in 4:
        var at_top: bool = corner == 1 or corner == 2
        var at_end: bool = corner >= 2
        var point: Vector2 = to if at_end else from
        var y: float = height_m if at_top else base_m
        surface.set_normal(normal)
        surface.set_uv(Vector2(run if at_end else 0.0, y))
        surface.add_vertex(Vector3(point.x, y, point.y))
```

REQ-V8.2 A solid shall refuse an outline it cannot triangulate, and shall say so,
naming the entity. A silently missing patio is a support call; a named
self-intersection is a two-minute fix in the plan.

REQ-V8.3 Extruded geometry shall carry normals and tangents generated from the
mesh, and a slab's top face shall be one smooth group. A patio that shades as
facets looks like a modelling error because it is one.

### 8.4 Open linework becomes a ribbon

A kerb, a low wall, a deck edge and a path border are *lines* in the plan and
*solids* in the view. `Geometry2D.offset_polyline` gives the two sides:

1. Offset the polyline by `+width/2` and by `-width/2`.
2. The two offsets plus the end caps form a closed loop.
3. Feed that loop to `slab()` at the given base and height.

```gdscript
## A ribbon: open linework given a width and a thickness.
static func ribbon(
    line: PackedVector2Array,
    width_m: float,
    base_m: float,
    height_m: float,
    uv_scale_metres: float = 1.0
) -> ArrayMesh:
    if line.size() < 2:
        push_error("CadSolid.ribbon: a ribbon needs two points, got %d" % line.size())
        return null
    var half: float = width_m * 0.5
    var left: Array[PackedVector2Array] = Geometry2D.offset_polyline(
        line, half, Geometry2D.JOIN_ROUND, Geometry2D.END_BUTT
    )
    var right: Array[PackedVector2Array] = Geometry2D.offset_polyline(
        line, -half, Geometry2D.JOIN_ROUND, Geometry2D.END_BUTT
    )
    if left.is_empty() or right.is_empty():
        push_error("CadSolid.ribbon: offsetting by %.2f m consumed the line" % half)
        return null
    # One side forward, the other back, gives one loop with no crossing at the
    # ends. This is what turns two open polylines into a closed outline.
    var loop := PackedVector2Array()
    for point in left[0]:
        loop.append(point)
    var far: PackedVector2Array = right[0]
    for index in range(far.size() - 1, -1, -1):
        loop.append(far[index])
    return slab(loop, base_m, height_m, 0.0, uv_scale_metres)
```

REQ-V8.4 A ribbon shall be built from `Geometry2D.offset_polyline`, not from a
hand-rolled perpendicular offset. The engine's version already answers the
mitre-or-butt question at a corner, and a hand-rolled one is where
self-intersections on tight curves come from.

### 8.5 Circles and arcs

| Entity | Solid |
|---|---|
| `CIRCLE` — a raised bed, a planter, a pond | A ring wall: the outer loop minus an inner offset loop, extruded as a band, plus a surface at water level. |
| `ARC` — a curved kerb, a lawn edge | A ribbon along the sampled arc, exactly as §8.4. |

REQ-V8.5 A pond shall be a surface at water level plus a rim at coping level, with
the water on its own material. A pond drawn as a flat disc of the ground material
is a mud puddle.

### 8.6 Which entity becomes what

Nothing is extruded automatically. Extrusion is a decision that carries a height,
and **a height is not in the drawing**: a patio at 0.05 m and a raised bed at 0.45 m
are the same rectangle in plan. The mapping is therefore a table, keyed by the layer
the drawer already chose:

```gdscript
class_name SolidTable
extends RefCounted
## Which layer becomes which solid, and how thick.
##
## A height cannot be read off a plan - a patio and a raised bed are the same
## rectangle - so it is a table, and the table is where the designer's intent
## lives. Keyed by layer name, like every other table in this project.

enum Shape { SLAB, RIBBON, SURFACE }

## `collide` is deliberately per entry: a mulch surface the player trips over is a
## bug, and a wall the player walks through is a worse one (REQ-V8.7).
const SOLIDS := {
    LayerSet.NEW_HARDSCAPE: {
        "shape": Shape.RIBBON, "height_m": 0.05, "width_m": 0.60,
        "base_m": -0.02, "material_set": "paver_granite", "collide": false,
    },
    LayerSet.WALLS: {
        "shape": Shape.RIBBON, "height_m": 0.90, "width_m": 0.20,
        "base_m": 0.0, "material_set": "paver_sandstone", "collide": true,
    },
    LayerSet.WATER: {
        "shape": Shape.SURFACE, "height_m": -0.15, "width_m": 0.0,
        "base_m": -0.35, "material_set": "water_still", "collide": false,
    },
    LayerSet.DECK: {
        "shape": Shape.SLAB, "height_m": 0.30, "width_m": 0.0,
        "base_m": 0.25, "material_set": "deck_timber", "collide": true,
    },
    LayerSet.PLANTING_BED: {
        "shape": Shape.SURFACE, "height_m": 0.06, "width_m": 0.0,
        "base_m": 0.0, "material_set": "mulch_bark", "collide": false,
    },
}


## The solid specification for a layer, or {} when that layer stays flat.
static func solid_for(layer_name: String) -> Dictionary:
    return SOLIDS.get(layer_name, {})
```

REQ-V8.6 Solid heights, bases and materials shall come from a table keyed by layer,
and shall never be inferred from an entity's geometry or its layer's plotted weight.

REQ-V8.7 Only solids whose `collide` is true shall get a collider.

### 8.7 Rebuilding, and when

Derived solids are rebuilt when the document changes, not per frame. The trigger is
the document's own edit signal, with a debounce — because dragging a patio's corner
emits a change per frame, and rebuilding a mesh per frame is what turns a smooth
drag into a stutter.

```gdscript
class_name DerivedBuilder
extends Node3D
## Rebuilds the solids implied by the drawing, and keeps one mesh per entity.
##
## The mapping is deliberately one-to-one in both directions: a mesh knows the id
## of the entity it pictures, and an entity's edit replaces its mesh rather than
## adding a second one. That is what makes "the mesh is a picture of the entity"
## true over time and not just at first build (REQ-V8.1).

## At most one rebuild per this many seconds. A drag emits a change per frame, and
## a mesh per frame is a stutter (§8.7).
const REBUILD_INTERVAL := 0.15

var document = null
var surfaces: Node3D
var ribbons: Node3D

var _dirty: bool = false
var _timer: float = 0.0
## Entity id -> the mesh node picturing it. Also what makes a delete a removal.
var _built: Dictionary = {}


func _process(delta: float) -> void:
    if not _dirty:
        return
    _timer += delta
    if _timer < REBUILD_INTERVAL:
        return
    _dirty = false
    _timer = 0.0
    rebuild()


## Called from the document's change signal. Cheap on purpose: it only raises a
## flag, so a drag costs a flag per frame rather than a mesh.
func mark_dirty() -> void:
    _dirty = true


func rebuild() -> void:
    if document == null:
        return
    for entry in document.draw_order():
        var entity = entry["entity"]
        var layer = entry["layer"]
        var spec: Dictionary = SolidTableScript.solid_for(String(layer.name))
        if spec.is_empty() or not layer.plots:
            continue
        var mesh: ArrayMesh = _mesh_for(entity, layer, spec)
        # A refused outline returns null and has already said why. Nothing is
        # added, and last time's mesh is removed rather than left behind: a solid
        # the drawing no longer supports must not keep standing.
        _place(int(entity.id), mesh, bool(spec["collide"]))
    _remove_deleted()


func _mesh_for(entity, layer, spec: Dictionary) -> ArrayMesh:
    var outline: PackedVector2Array = CadSolidScript.outline_of(
        entity, layer, document.plot_scale
    )
    if outline.size() < 3:
        return null
    match int(spec["shape"]):
        SolidTableScript.Shape.RIBBON:
            return CadSolidScript.ribbon(
                outline, float(spec["width_m"]), float(spec["base_m"]),
                float(spec["height_m"])
            )
        SolidTableScript.Shape.SURFACE:
            return CadSolidScript.slab(
                outline, float(spec["base_m"]), float(spec["height_m"])
            )
        _:
            return CadSolidScript.slab(
                outline, float(spec["base_m"]), float(spec["height_m"])
            )
```

REQ-V8.8 Derived geometry shall be rebuilt on a debounced document change, at most
once per `REBUILD_INTERVAL` seconds, and never once per input event.

REQ-V8.9 The 2D-to-3D conversion shall be a pure function of the document plus the
solid table: same document, same table, the same mesh. Two builds shall be
comparable by vertex count and bounds, and that comparison shall be a test.

---

### 8.8 What building this changed

Seven corrections. Six of them were invisible in the code and are visible in a render —
which is the argument for building a phase rather than only specifying it — and five of
the six are about **winding**, which is where every face in this section is decided.

**The convention, first, because everything else follows from it.** Godot's front faces
are **clockwise**, so a triangle's front normal is *minus* the right-hand-rule product of
its edges: `-(b - a).cross(c - a)`. That one sign is the difference between a patio and a
hole in the ground. It is written down once, in `CadSolid.front_normal()`, and asserted
against a *built mesh* rather than reasoned about at each face:

```gdscript
## The front normal of a triangle, per Godot's clockwise convention.
static func front_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
    return -((b - a).cross(c - a)).normalized()
```

1. **A quad is six vertices, not four.** The specification's side panel is built with
   `for corner in 4` and committed as `PRIMITIVE_TRIANGLES`. Four vertices are a *strip*:
   the renderer is handed a triangle list whose length is not a multiple of three, drops
   the odd tail, and — this is the part that matters — `create_trimesh_collision()`
   **refuses the surface outright**, so the solid has no collider and can be walked
   through. The two triangles of a quad need six corners naming four places: `(A, B, C)`
   and `(A, C, D)`.
2. **The underside cannot be made by re-triangulating a reversed ring.** The
   specification writes `_reversed(piece)` and feeds it back to `triangulate_polygon`,
   which looks right and is a no-op: the triangulator answers with the *same triangle
   sequence* whichever order the ring is given in — the indices differ, the points they
   name do not — so both windings come back facing the same way and the underside comes
   out pointing up. The bottom face reverses *each triangle's corner order* instead. (The
   first diagnosis of this was wrong in an instructive way: a reversed ring's index array
   *does* read as reversed, and comparing index arrays rather than the points they name
   says the opposite of the truth.)
3. **The side panels are wound inward.** With the convention above, the four corners in
   the specification's loop order — `(from,base), (from,top), (to,top), (to,base)` — make
   every wall of a raised bed face *into* the bed. The outward normal formula in the same
   paragraph, `Vector3(edge.y, 0.0, -edge.x)`, is correct, so the section disagrees with
   itself and only a render can say which half is right.
4. **`Geometry2D.offset_polyline` already returns a closed loop.** §8.4 offsets the line by
   `+width/2` and by `-width/2` and joins the two, one of them reversed. It does not need
   to: a single call returns the whole band — four points for a straight segment, the
   mitered outline for a bent one — and asking for both signs gives two copies of the same
   loop, whose join crosses itself and is then refused by the triangulator. Ask once.
5. **A layer cannot have one shape.** §8.6 gives every layer a single `Shape`, which reads
   as a simplification and is a contradiction: paving is a patio where it is drawn as a
   rectangle and a kerb where it is drawn as a line, so `NEW_HARDSCAPE` with one shape
   either extrudes a patio as a 60 cm ribbon or a kerb as a sliver of paving. The table
   says **how thick**; the **entity** says whether it is a surface or a centreline
   (`SolidTable.wants_ribbon()`). The requirement it must keep — heights, bases and
   materials from a layer-keyed table (REQ-V8.6) — it still keeps, because a width is not
   a height.
6. **Three of §8.6's five keys name layers that do not exist.** `WALLS`, `WATER` and
   `PLANTING_BED` are not in this project's preset layer set, so two thirds of the table
   could never have fired. `SolidTable` is keyed by the real names, and `SolidTable.MISSING`
   records what became of the others — including §8.5's pond, which has nowhere to be drawn
   yet.
7. **`document.draw_order()` does not exist.** §8.7's rebuild walks it. The document's own
   order is `entities()`, the order the working plan and the plotted sheet draw in.

One more, about the derived maps rather than the solids: a *sampled* check for "is this
normal map flat" reports a map with one seam as flat. Every byte is read instead — the
lesson the still exporter's blank-render guard learned, learned twice.

**Two more, from the sun study**, which was built after these and is the one part of this
subsystem whose answer can be checked against the world and not only against a render:

8. **The declination was a cosine and the hour was the sun's own.** §7.3 opened with
   `-23.44 * cos(TAU * (day_of_year + 10.0) / 365.0)`, "good to about a degree", and took its
   hour as a *solar* time. Both were defensible, and both are gone. The cosine is exact at the
   solstices and out by up to half a degree around the equinoxes, and a solar hour is a time
   the client's watch does not keep — so the shadow was cast for a moment up to sixteen
   minutes from the one the study was asked about. The specification's own reason for the
   approximation, "well inside the accuracy of the question being asked", is what turned out
   to be false: the question a client asks ("will it be in the shade by four?") is one they can
   answer from their own window, which makes the accuracy of the answer the point rather than a
   nicety. Meeus's routine costs about the same to write and is good to a hundredth of a
   degree, the equation of time is worth sixteen minutes and refraction half a degree, and each
   of the three is larger than the error it displaces.
9. **A latitude is not a site, and an hour without one is not a moment.** §7.3's
   `position(latitude, day_of_year, hour)` cannot be asked in a clock time at all. The same
   number means a sun up to an hour away from the one described, depending on where the site
   sits in its zone, so the study now has two doors — `position()` for a solar hour with no
   place, `position_for()` for a clock at a place — and the parameter names carry which is
   which. A test asserts that the two agree to three arcseconds once the difference is paid,
   which is what makes the site machinery the same trigonometry rather than a second copy of
   it, and another rebuilds a recorded sun from the keys it recorded.

**And one the sun path found, which no test in this repository could have.** Building
`tools/sun_demo.gd` - a day rendered six times, one an hour - produced six shadowless
pictures:

10. **A tier's shadow distance is a floor, not a distance.** §6.6's table gives the still tier
   30 m, on the reasoning that a smaller range buys sharper shadows. A shadow is drawn
    *from the camera outward*, so a range shorter than the framed garden is not a cheaper
    shadow: it is no shadow, over the whole subject at once. The presentation camera stands
    **61.9 m** from this yard's middle to fit it in frame, so at the still tier - the tier
   whose entire purpose is a picture a client keeps - every hour of the day came back with no
   cast shadow in it, while the same scene at the working tier showed every shadow the study
   implies. `PresentationDirector` now takes the greater of the table's number and what the
   framing needs (`required_shadow_distance()`), on the tier *and* on every re-framing, and
   AC-V31 holds it there. The lesson is the one this section keeps relearning: the numbers in
   a budget table are only as good as the thing they are measured against, and a render is
   what says which of them is wrong.

---

## 9. Presentation camera controls

### 9.1 The orbit rig

An orbit camera is a pivot with a camera held away from it:

```
OrbitRig (Node3D)              ← the point of interest, on the ground
 └── Arm (Node3D)              ← yaw, turned by a drag
      └── Elevation (Node3D)   ← pitch, clamped
           └── Boom (Node3D)   ← distance along its own +Z
                └── Camera3D   ← looks back down the boom at the pivot
```

Splitting yaw, pitch and distance onto three nodes means each is one number on one
axis: no quaternion arithmetic, no gimbal surprise at the poles, and a pitch clamp
that is a clamp on a single value.

```gdscript
class_name OrbitCamera
extends Node3D
## A presentation camera a client can be walked around a garden with.
##
## Three axes on three nodes: yaw on the arm, pitch on the elevation, distance on
## the boom. Each is then one number, which is why the clamps below are one line
## each and why the camera cannot get into a state that has to be repaired.

## Closest and furthest the camera may sit from the subject, in metres.
@export var min_distance: float = 3.0
@export var max_distance: float = 60.0
## Below this the camera is under the ground; above it, it is a map.
@export var min_elevation_deg: float = 5.0
@export var max_elevation_deg: float = 85.0
## Multiplier per wheel notch, and radians per pixel of drag.
@export var dolly_step: float = 1.35
@export var orbit_step: float = 0.006

@onready var arm: Node3D = $Arm
@onready var elevation: Node3D = $Arm/Elevation
@onready var boom: Node3D = $Arm/Elevation/Boom
@onready var camera: Camera3D = $Arm/Elevation/Boom/Camera3D


## Frame a box: put the pivot at its centre and pull back until it fits, leaving
## `margin` of the frame empty around it.
func frame(box: AABB, margin: float = 0.18) -> void:
    if box.size.length() <= 0.0:
        return
    global_position = box.get_center()
    # Half the box's diagonal against the tangent of half the field of view: the
    # distance at which that diagonal exactly spans the frame. Using the diagonal
    # rather than the widest side means a tall object frames as well as a wide one,
    # whichever way the camera is pointed.
    var radius: float = box.size.length() * 0.5
    var half_vertical: float = deg_to_rad(camera.fov * 0.5)
    # A frame is usually wider than it is tall, so the vertical half-angle is the
    # one that runs out first; taking the minimum means neither edge is clipped
    # whatever the aspect is.
    var aspect: float = get_viewport().get_visible_rect().size.aspect()
    var half_horizontal: float = atan(tan(half_vertical) * aspect)
    var half: float = minf(half_vertical, half_horizontal)
    set_distance(radius / tan(half) * (1.0 + margin))


## Set the boom length, clamped. One number to keep in range.
func set_distance(distance: float) -> void:
    boom.position.z = clampf(distance, min_distance, max_distance)


func distance() -> float:
    return boom.position.z


## Yaw and pitch from a drag, in pixels. Both clamps are here, so no caller needs
## to know about them.
func orbit(delta_pixels: Vector2) -> void:
    arm.rotate_y(-delta_pixels.x * orbit_step)
    var pitch: float = elevation.rotation.x - delta_pixels.y * orbit_step
    elevation.rotation.x = clampf(
        pitch, deg_to_rad(min_elevation_deg), deg_to_rad(max_elevation_deg)
    )


## Dolly in and out. Proportional to the current distance, so one wheel notch is
## the same visual step at 3 m as at 30 m.
func dolly(notches: float) -> void:
    set_distance(distance() * pow(dolly_step, -notches))


## Swing the pivot across the ground, keeping distance and heading. This is what
## you want when the subject is off to one side: a pan, not a re-frame.
func truck(ground_delta: Vector2) -> void:
    var yaw: float = arm.rotation.y
    var right := Vector2(cos(yaw), -sin(yaw))
    var forward := Vector2(-sin(yaw), -cos(yaw))
    var moved: Vector2 = right * ground_delta.x + forward * ground_delta.y
    global_position += Vector3(moved.x, 0.0, moved.y)
```

REQ-V9.1 The orbit camera shall clamp pitch and distance, and shall never place the
camera below the ground plane.

REQ-V9.2 `frame()` shall derive its distance from the camera's actual field of view
and the viewport's aspect, never from a table of magic numbers.

### 9.2 The walk-through

The ground view already exists (`ViewController.ViewMode.GROUND`, the `Player` with
WASD and mouse look). The presentation walk-through is that path plus a route: a
client can be shown the garden the way they will walk it.

```gdscript
class_name WalkRoute
extends RefCounted
## An ordered walk through the garden: the stops a client is shown, and how long
## the camera dwells at each.
##
## A route is authored data, not a camera path. The stops are places a person would
## stand - "living room door", "end of the path" - which is what makes a walk-through
## feel like a visit rather than a drone flight.

## A stop is a place to stand, a thing to look at, and a dwell in seconds.
var _stops: Array[Dictionary] = []


func add_stop(name: String, at: Vector3, look_at: Vector3, dwell_s: float = 2.5) -> void:
    _stops.append({"name": name, "at": at, "look": look_at, "dwell": dwell_s})


func stops() -> Array[Dictionary]:
    return _stops


func is_empty() -> bool:
    return _stops.is_empty()


## The route as a smooth path through the stops, in the order they were added.
## Catmull-Rom through the positions, so the camera travels through a stop rather
## than stopping dead and turning on the spot.
func path() -> Curve3D:
    var curve := Curve3D.new()
    for stop in _stops:
        curve.add_point(stop["at"])
    # A Curve3D with fewer than two points has no length and cannot be followed;
    # the caller is told rather than given an empty path that silently does nothing.
    return curve if curve.point_count >= 2 else null


## What the camera is pointed at at a given distance along the route: the next
## stop's look-at, so the camera turns *while* it travels.
func look_target_at(distance_along: float) -> Vector3:
    var travelled: float = 0.0
    for index in _stops.size() - 1:
        var from: Vector3 = _stops[index]["at"]
        var to: Vector3 = _stops[index + 1]["at"]
        var leg: float = from.distance_to(to)
        if distance_along <= travelled + leg:
            return _stops[index + 1]["look"]
        travelled += leg
    return _stops[_stops.size() - 1]["look"]
```

**What building this changed** (`scripts/vis/walk_route.gd`). Two corrections, both because
the route had to be *testable*, and neither visible until it was written:

1. **The route is its own clock.** The sketch above follows a `Curve3D` the caller steps; the
   built `WalkRoute` answers `duration()`, `position_at(elapsed)` and `look_at(elapsed)`
   itself, so "where is the camera at 12.4 seconds" is a question with an answer that does
   not need a frame rendered to check. A walk-through that can only be inspected by watching
   it is one no test can hold. The `Curve3D` still exists - `path()` returns it - but it is a
   description of the route, not the thing that is followed. `stage_at()` gathers the whole
   answer (position, look, stop index, travelling, done, progress) in one call.
2. **`add_stop`'s target is named `aim_at`, not `look_at`.** `look_at` is a method of
   `WalkRoute` itself (`look_at(elapsed)`), and in Godot 4.7 a method name claims that name
   for the whole file, so a parameter may not share it. Same value, same meaning, a spelling
   the compiler accepts.

The stops also lie along the *open* side of the garden and each aims across it: a stop behind
the house looks at the back of the house, and a stop inside it looks at nothing.

REQ-V9.3 A walk-through shall move between authored stops along a smoothed path and
dwell at each for a stated time. A continuous fly-through with no stops cannot be
described to a client, and a walk-through nobody can describe is a screensaver.

REQ-V9.4 A walk-through shall use the ground view's floor height and the yard's
collision, so the camera cannot walk through the house or float above the lawn.

REQ-V9.5 A route with fewer than two stops shall be refused, not followed
silently.

### 9.3 The camera never fights the planner

While presenting, the drafting input must be off — not because a client would press
`D`, but because a stray `Q`, `Tab` or `Enter` would change the view out from under
the presenter, and because the drafting tools write to the document while
presentation must not (§0.2).

REQ-V9.6 Presentation mode shall suspend the drafting controller's input handling
by the same means `ViewController` already uses to disable panning while the tools
are armed, and shall restore it on exit.

REQ-V9.7 Presentation mode shall take the keyboard without taking the mouse: a
client must be able to drag to orbit even while the drafting keys are suspended.

---

## 10. High-resolution image export

### 10.1 Why a `SubViewport` and not the window

This project's stretch mode is `canvas_items`, which means **the window size sets
the output resolution**. On a 1600×900 window, reading the root viewport's texture
can never produce a 4K image, whatever numbers are set elsewhere. The still must be
rendered into a `SubViewport` whose `size` is the output size.

REQ-V10.1 The still export shall render into a `SubViewport`, not the root viewport,
and shall state the output size explicitly. Nothing in the path shall depend on the
window's size.

### 10.2 Supersample, then downsample

There is no 2D MSAA on this renderer and no TAA. Supersampling is therefore the
antialiasing, and it is done by hand so it is identical on every machine:

| Output | Render at | Downsample |
|---|---|---|
| 1920 × 1080 | 3840 × 2160 | 2× LANCZOS |
| 3840 × 2160 | 7680 × 4320 | 2× LANCZOS |
| A3 at 300 dpi (4961 × 3508) | 9922 × 7016 | 2× LANCZOS |

```gdscript
class_name StillExporter
extends Node
## Renders a view into an image good enough to put in a proposal.
##
## The path is: a SubViewport at the *render* size, waited on until the frame has
## actually been drawn, read back to an Image, downsampled by hand, and saved.
## Every step is here rather than delegated, because a proposal image that is one
## frame stale, or that came out at the window's size instead of the asked-for
## size, is a bug the client finds and a test does not - unless the test is on this
## function, which is why it is a function.

## Supersample factor. Two is enough for a line drawing: the first doubling does
## most of the work, and four is four times the pixels for a little more.
const SUPERSAMPLE := 2
## Where stills go. `user://` because a proposal image belongs to the user rather
## than to the project, and because the project folder is in version control.
const OUT_DIR := "user://proposals"


## Render `render_nodes` at `output_size` and save it as a PNG. Returns the absolute
## path, or "" if the image could not be written.
##
## The nodes are moved *into* the render viewport for the duration of the shot, and
## put back at the same position among their siblings afterwards.
##
## For a 3D still that node is the **camera**, not the scene. A `SubViewport` shares
## its parent's `World3D`, so a camera inside the viewport renders the same garden,
## and the garden never moves. Moving the whole scene was the first attempt and it
## does not work: **the engine refuses to reparent the scene root out of the tree it
## is the root of** ("Can't add child 'Main' to 'StillRender', already has a parent
## 'root'"), the viewport stays empty, and the still is written anyway - see the
## blankness guard below.
##
## `flatten` composites over paper, which matters because a layer render arrives
## with a transparent background and many image viewers show transparent PNGs as
## black (REQ-V10.4).
func render_still(
    render_nodes: Array[Node],
    output_size: Vector2i,
    file_name: String,
    paper: Color = Color(0.945, 0.937, 0.906),
    flatten: bool = true
) -> String:
    var viewport := SubViewport.new()
    viewport.size = output_size * SUPERSAMPLE
    viewport.transparent_bg = not flatten
    # MSAA 3D is cheap here and helps the geometry; MSAA 2D is unavailable on this
    # renderer in any case, and the downsample is what antialiases the lines.
    viewport.msaa_3d = Viewport.MSAA_4X
    viewport.msaa_2d = Viewport.MSAA_DISABLED
    # FXAA after the fact would blur the very edges the supersample just made
    # clean, so it stays off and the downsample is the only filter applied.
    viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    add_child(viewport)
    # `reparent()`, not `add_child()`: `add_child()` does not move a node that already
    # has a parent, it errors and leaves it where it was, so the viewport renders
    # nothing. Global transform kept - a camera must stay pointed at the garden.
    for node in render_nodes:
        node.reparent(viewport, true)

    # The frame has to be *finished* before its texture can be read: reading in the
    # same frame returns an empty image. This is the classic "my screenshot is
    # blank" bug, and the reason this is an await rather than a call. **Two** frames,
    # not one: the first draws, and the second redraws once the shadow atlas, the
    # viewport size and any recompiled light have settled. One frame catches the
    # previous state.
    await RenderingServer.frame_post_draw
    await RenderingServer.frame_post_draw
    var image: Image = viewport.get_texture().get_image()

    # Put everything back before anything that can fail, so a failed shot never
    # leaves the game inside a viewport.
    for node in render_nodes:
        ...

    # `is_empty()` is not enough. A viewport nothing was drawn into is not *empty*:
    # it comes back at exactly the right size, one flat colour, and the record and
    # the file both look perfectly correct. The first still written by this project
    # was a 1920x1080 grey rectangle that passed every check but this one
    # (REQ-V10.7).
    if image == null or image.is_empty() or _looks_blank(image):
        push_error("StillExporter: the render came back blank; nothing was drawn into it.")
        viewport.queue_free()
        return ""

    # Downsample by hand, so the filter is known rather than whichever one the
    # driver happens to pick for a scaled blit.
    image.resize(output_size.x, output_size.y, Image.INTERPOLATE_LANCZOS)
    if flatten:
        image = _flatten(image, paper)

    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
    var path := "%s/%s.png" % [OUT_DIR, file_name]
    var error := image.save_png(path)
    viewport.queue_free()
    if error != OK:
        push_error("StillExporter: could not write %s (%d)" % [path, error])
        return ""
    return ProjectSettings.globalize_path(path)


## Composite a transparent image over paper.
##
## Not cosmetic: the painted path's layers are transparent where nothing is drawn,
## and a proposal image that opens as a black rectangle in the client's viewer has
## failed at the very last step.
func _flatten(image: Image, paper: Color) -> Image:
    var flat := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGB8)
    flat.fill(paper)
    flat.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
    return flat
```

REQ-V10.2 The exporter shall produce an image of exactly the requested pixel size,
whatever the window's size is.

REQ-V10.3 The exporter shall be a function of its arguments. It shall not read the
editor's state, the current view mode, or the HUD's visibility: the caller decides
what is in the picture, and the exporter records it.

REQ-V10.4 A still shall be able to flatten a transparent render over paper, and the
painted 2D path shall always use that.

### 10.3 The capture sequence for the 3D view

```
  1. director.begin(Tier.STILL)              ← §7.1, remembers what it changes
  2. await two frames                        ← so a shadow-atlas rebuild and the
                                               light-space recompile never land
                                               in the shot
  3. orbit.frame(subject_box)                ← §9.1
  4. StillExporter.render_still(...)         ← waits for frame_post_draw itself
  5. write the sidecar (§10.4)
  6. director.end()                          ← puts the session back
```

REQ-V10.5 The still path shall wait for a settled frame after entering the still
tier and before capturing. A capture taken on the first frame after a quality change
catches the previous tier's shadow atlas.

REQ-V10.6 The render viewport shall hold the **camera**, not the scene, and shall move
it with `Node.reparent()` rather than `add_child()`. A `SubViewport` shares its parent's
`World3D`, so a camera inside it renders the same world. Two API traps make the naive
version fail silently:

- **`add_child()` does not reparent.** A node that already has a parent is refused
  ("Can't add child 'Camera' to 'StillRender', already has a parent 'Boom'") and stays
  where it was, so the viewport renders nothing. `reparent(new_parent, true)` is the
  call; the global transform must be kept, or the camera ends up looking somewhere else.
- **The scene root cannot be moved at all** ("Can't add child 'Main' to 'StillRender',
  already has a parent 'root'"), which is why the camera is the thing that moves.

Everything the exporter moves shall be put back at the same position among its siblings,
and put back *before* anything that can fail, so a failed shot never leaves the game
inside a viewport.

REQ-V10.7 A render that comes back one flat colour shall be refused and named as
blank, and nothing shall be written. `Image.is_empty()` does not catch it: a viewport
nothing was drawn into is not empty, it is the requested size and a single colour, so
the file, its size and its sidecar all look correct. The first still this project
wrote was a 1920×1080 grey rectangle that passed every check but this one.

### 10.4 The sidecar

A proposal image with no record of how it was made cannot be re-made. Each still
writes a `.json` beside it:

```json
{
  "app": "Backyard Design",
  "view": "3D preview",
  "rendered": "2026-10-19T21:53:38",
  "output_px": [3840, 2160],
  "supersample": 2,
  "tier": "Still (proposal)",
  "sun": {"latitude_deg": 45.0, "longitude_deg": -75.0, "utc_offset_hours": -5.0,
          "day_of_year": 172, "clock_hour": 16.0, "year": 2025,
          "solar_hour": 15.97, "declination_deg": 23.44,
          "equation_of_time_minutes": -1.96,
          "azimuth_deg": 266.55, "altitude_deg": 37.6,
          "apparent_altitude_deg": 37.63, "is_up": true},
  "plot_scale": 100,
  "camera": {"eye": [4.2, 1.6, 9.1], "look": [0.0, 0.0, 0.0], "fov": 32.0},
  "document": {"entities": 17, "units": "metric"},
  "godot": "4.7.2.stable"
}
```

REQ-V10.6 Every still shall write a sidecar recording the sun, the camera, the plot
scale, the document's entity count and Godot's version. The version is included
because a renderer change is the one thing that silently changes a picture.

### 10.5 Sequences and video

Godot's Movie Maker renders offline, at a fixed frame rate, with no dropped frames
and perfect pacing — and its resolution comes from the **viewport**, so a video
needs the window sized on startup or a viewport override. The `movie` feature tag is
available to a script through `OS.has_feature("movie")`, and is the documented way
to raise quality only while recording.

REQ-V10.7 The still path shall be the primary deliverable and a sequence secondary.
A proposal image is opened by a person; a video is watched once. Features shall be
prioritised accordingly.

### 10.6 The one effect that needs two renders

Depth of field is unavailable (§1.2). If a client wants the background soft, the
honest route is two renders through a mask: the frame, and the subject; and the
region where they differ is blurred. That is a compositing job and it belongs in the
still path only.

REQ-V10.8 Any effect requiring more than one render pass shall be available in the
still path only, and shall never be attempted interactively.

---

## 11. The editor plugin

### 11.1 Why a plugin, rather than more game HUD

Three jobs belong in the editor rather than in the running game:

1. **Authoring presentation data** — the sun study's four numbers, the walk route's
   stops, which framing a proposal uses. A dock with a form beats editing a `.tres`
   by hand.
2. **Batch rendering** — "render all four views" is a button in a dock, not a
   feature of the game's HUD.
3. **Diagnostics** — which layers have no wash entry, which texture sets are
   missing a map, which solids were refused. The editor is where those get fixed.

### 11.2 Layout, and why not under `addons/ziva_agent/`

```
res://addons/vis_tools/
├── plugin.cfg
├── plugin.gd
├── presentation_dock.tscn
├── presentation_dock.gd
└── diagnostics_panel.gd
```

`addons/ziva_agent/` is gitignored — 1.5 GB of vendored binaries owned by Ziva. A
plugin of ours goes in its own directory so it is version-controlled and so a Ziva
update cannot overwrite it.

```ini
; res://addons/vis_tools/plugin.cfg
[plugin]
name="Visualization Tools"
description="Author and render the presentation: sun study, routes, batch stills."
author="Backyard Design"
version="0.1.0"
script="plugin.gd"
```

```gdscript
@tool
extends EditorPlugin
## Authoring and batch rendering for the presentation subsystem.
##
## A dock rather than a toolbar button, because everything here is a form: a sun
## study is four numbers, a route is a list, a batch is a list of checkboxes. A
## toolbar button would open a dialog that is a worse dock.

const StillExporterScript := preload("res://scripts/vis/still_exporter.gd")

var _dock: Control = null


func _enter_tree() -> void:
    _dock = preload("res://addons/vis_tools/presentation_dock.tscn").instantiate()
    # Right-bottom: a working panel, so it does not displace the inspector or the
    # file system while somebody is designing.
    add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_BL, _dock)


func _exit_tree() -> void:
    if _dock == null:
        return
    remove_control_from_docks(_dock)
    # The dock is ours to free: this plugin created it, so this plugin destroys it.
    # A plugin that leaks a panel on disable grows a new panel every time it is
    # toggled off and on again.
    _dock.queue_free()
    _dock = null


## Render one still from the editor, as a preview of what a batch will produce.
## Runs the *project's own* exporter over the currently edited scene, because a
## second render path in the editor is a second thing to keep in step with the
## first - and the first one is the one that has tests.
func render_preview(output_size: Vector2i) -> String:
    var edited: Node = EditorInterface.get_edited_scene_root()
    if edited == null:
        push_warning("Visualization Tools: no scene is open to render.")
        return ""
    var exporter := StillExporterScript.new()
    return await exporter.render_still(edited, output_size, "preview")
```

**What building this changed** (`addons/vis_tools/`). Three corrections:

1. **The dock is a plain `Control`, built in code, with no `presentation_dock.tscn`.** The
   tree above shows a scene for the dock and a separate `diagnostics_panel.gd`; both were
   folded into two files. The dock adds no children a scene would save for it - a few labels,
   a list, a few buttons - and a scene whose only job is to be instantiated and then have its
   nodes found by name is a second file to keep in step with the first. What was a *panel* is
   now a *list in the dock* (`VisPresentationDock`, one `ItemList` of findings beside the
   jobs), so `diagnostics_panel.gd` does not exist. The dock is a plain `Control` with no
   editor API precisely so it can be tested off-tree.
2. **`add_control_to_dock` is gone in Godot 4.7.** An editor dock is attached with
   `EditorDock` + `add_dock(dock)` / `remove_dock(dock)` - the same correction the business
   work's cost-book dock forced (§15.17 of `business-operations-spec.md`). The `EditorDock`
   needs a `title`, a `default_slot` and `available_layouts`, and the plugin owns and frees it.
3. **The plugin finds the drawing by polling the edited scene, not in `_enter_tree`.** A
   non-`@tool` script's `_ready` never runs in the editor, so `main.tscn`'s `DraftController`
   has no document when the plugin enters the tree, and `EditorInterface.get_edited_scene_root()`
   is itself null during `_enter_tree`. `_process` polls the edited root and re-adopts when it
   changes, falling back to the most recent saved drawing before an empty layer set, so the
   dock shows something useful the moment it is turned on.

### 11.3 Diagnostics

The dock's diagnostics panel answers the questions whose answers are currently
found by looking at a picture:

```gdscript
class_name VisDiagnostics
extends RefCounted
## What the presentation is missing, named by file, so it can be fixed where it
## was authored rather than where it showed up.
##
## A report rather than a validator: every finding names the thing to change, and
## none of them stop the render. A proposal with one unwashed layer is still a
## proposal.

const WashTableScript := preload("res://scripts/vis/wash_table.gd")
const SolidTableScript := preload("res://scripts/vis/solid_table.gd")
const HardscapeScript := preload("res://scripts/vis/hardscape_material.gd")


## Every finding, as {"severity": "warning", "where": file, "what": description}.
static func report(document, layer_set) -> Array[Dictionary]:
    var findings: Array[Dictionary] = []
    for layer in layer_set.layers():
        var name := String(layer.name)
        if name.begins_with("_"):
            # Construction and tracing layers are not pictures (§4.2).
            continue
        if layer.plots and WashTableScript.wash_for(name).is_empty():
            findings.append({
                "severity": "warning", "where": "scripts/vis/wash_table.gd",
                "what": "layer '%s' plots but has no wash entry" % name,
            })
        if layer.plots and SolidTableScript.solid_for(name).is_empty():
            # Not a warning: most layers are flat on purpose. Reported as a note
            # so that "no solid" is a decision on the record rather than an
            # oversight nobody can see.
            findings.append({
                "severity": "note", "where": "scripts/vis/solid_table.gd",
                "what": "layer '%s' builds no solid (flat, as authored)" % name,
            })
    for set_name in HardscapeScript.SETS:
        var spec: Dictionary = HardscapeScript.SETS[set_name]
        for channel in ["albedo", "normal", "orm"]:
            var path: String = "res://resources/textures/hardscape/%s" % spec[channel]
            if not ResourceLoader.exists(path):
                findings.append({
                    "severity": "error", "where": path,
                    "what": "texture set '%s' is missing its %s map" % [set_name, channel],
                })
    return findings
```

**The severities, and how a deliberate omission is told from an oversight.** The built
`VisDiagnostics` reports three levels rather than the sketch's two, and reads the *two halves*
of each table rather than matching on prose:

- A plotting layer carrying geometry that is in neither `WashTable.WASHES` nor
  `WashTable.NO_WASH` is a **warning** naming `scripts/vis/wash_table.gd` - somebody drew on a
  layer nobody decided how to paint.
- A layer in `NO_WASH` is **silent**: a decision already on the record.
- The same shape for solids - in neither `SolidTable.SOLIDS` nor `SolidTable.NO_SOLID` is a
  **warning** naming `solid_table.gd`; in `NO_SOLID` is a **note** quoting `reason_for`, so
  "flat on purpose" stays visible without reading as a problem.
- A solid naming a material set `HardscapeMaterial.has_set` does not have is an **error**, and
  every path in `missing_paths()` is an error of its own - the one class of finding that is
  *missing data* rather than *an authoring decision*, which is why it is the only error.

A layer nobody has drawn on (`document.entities_on_layer` returns nothing) and a non-plotting
layer are not reported at all, because "you have not used this layer" is not a finding.

REQ-V11.1 The plugin shall render through the project's own exporter and shall not
implement a second render path.

REQ-V11.2 The plugin shall be `@tool` and shall remove every node it added, so
disabling it leaves the editor as it was.

REQ-V11.3 The plugin shall report missing presentation data as findings that name
the file to fix, and no finding shall block a render.

---

## 12. Node structure added to `main.tscn`

```
Main (Node3D)
├── WorldEnvironment
├── Sun (DirectionalLight3D)
├── Yard
├── FlightCamera (Camera3D)                  ← existing: the working overhead eye
├── Player                                   ← existing: the ground view
├── PlanLayer
│   └── PlanCanvas                           ← existing: the working 2D view
├── SelectionRing                            ← existing
├── ViewController                           ← existing
├── DraftController                          ← existing
├── DraftOverlay                             ← existing
├── Hud                                      ← existing
│
├── Presentation (Node3D)                    [new]  scripts/vis/presentation_director.gd
│   ├── OrbitRig (Node3D)                    [new]  scripts/vis/orbit_camera.gd
│   │   └── Arm (Node3D)
│   │       └── Elevation (Node3D)
│   │           └── Boom (Node3D)
│   │               └── Camera3D             [new]  the presentation eye
│   └── WalkRoute (Node3D)                   [new]  scripts/vis/walk_route.gd
│
├── Derived (Node3D)                         [new]  scripts/vis/derived_builder.gd
│   ├── Surfaces (Node3D)                    [new]  slabs and ground surfaces
│   ├── Ribbons (Node3D)                     [new]  kerbs, walls, edgings
│   └── Planting (Node3D)                    [new]  a MultiMeshInstance3D per species
│
└── StillExport (Node)                       [new]  scripts/vis/still_exporter.gd
```

The painted 2D path adds nothing to the scene: it bakes through `SubViewport`s
created per render (§3.4), because its layers exist only for the duration of one
picture and a permanent layer tree would be a second scene to keep in step.

REQ-V12.1 Presentation and derivation shall be *additive* children of `Main`.
`main.tscn`'s existing node paths shall not change, because every path in this
project's tests is a promise.

### 12.1 New files, in full

| Path | What |
|---|---|
| `scripts/vis/sketch_stroke.gd` | The wobble (§3.2) |
| `scripts/vis/sketch_baker.gd` | Layer bakes (§3.4) |
| `scripts/vis/ink_painter.gd` | The ink pass (§3.3) |
| `scripts/vis/wash_table.gd` | Wash colours by layer (§4.2) |
| `scripts/vis/wash_painter.gd` | The muddled wash (§4.4) |
| `scripts/vis/contact_shadow.gd` | Authored contact darkening (§6.4) |
| `scripts/vis/hardscape_material.gd` | Texture sets to materials (§5.1) |
| `scripts/vis/solid_table.gd` | Layer to solid (§8.6) |
| `scripts/vis/cad_solid.gd` | Outline, ribbon, slab (§8.2-8.5) |
| `scripts/vis/derived_builder.gd` | Debounced rebuild (§8.7) |
| `scripts/vis/presentation_tier.gd` | The budget table (§7.2) |
| `scripts/vis/presentation_director.gd` | Enter and leave presentation (§7.1) |
| `scripts/vis/sun_study.gd` | The sun, astronomically, for a site and a clock (§7.3) |
| `scripts/vis/planting_instancer.gd` | MultiMesh planting (§7.4) |
| `scripts/vis/orbit_camera.gd` | The orbit rig (§9.1) |
| `scripts/vis/walk_route.gd` | Walk-through stops (§9.2) |
| `scripts/vis/still_exporter.gd` | High-resolution stills (§10.2) |
| `scripts/vis/still_sidecar.gd` | The render record (§10.4) |
| `tools/sun_demo.gd` + `scenes/sun_demo.tscn` | A sun path: a day in one picture (§7.3) |
| `resources/shaders/sketch_paper.gdshader` | The compositor (§3.5) |
| `resources/shaders/stylised_surface.gdshader` | Banded diffuse for the preview (§5.3) |
| `resources/shaders/foliage.gdshader` | Per-instance colour and sway (§7.4) |
| `resources/vis/sketch_default.tres` | The look (§13) |
| `addons/vis_tools/*` | The editor surface (§11) |

---

## 13. Data structures

| Name | Kind | Keyed by | Lives in |
|---|---|---|---|
| `SketchStyle` | Resource | — | `resources/vis/sketch_default.tres` |
| `WashTable.WASHES` | `const` Dictionary | layer name | `scripts/vis/wash_table.gd` |
| `HardscapeMaterial.SETS` | `const` Dictionary | set name | `scripts/vis/hardscape_material.gd` |
| `SolidTable.SOLIDS` | `const` Dictionary | layer name | `scripts/vis/solid_table.gd` |
| `PresentationTier.LOOKS` | `const` Dictionary | tier | `scripts/vis/presentation_tier.gd` |
| `WalkRoute` | RefCounted, stops array | — | authored in the scene, saved as a resource |
| A still's sidecar | JSON | — | written beside the PNG |

```gdscript
class_name SketchStyle
extends Resource
## The look of the painted plan: how much wobble, how much grain, how wet.
##
## A Resource rather than constants, because a designer will want two of these -
## "client presentation" and "council submission" - and the only honest way to ship
## two looks is to make the look a thing that can be saved, copied and compared.

## Wobble amplitude in paper millimetres. Zero gives a plotted line.
@export var wobble_mm: float = 0.28
## Sampling step along a stroke, in paper millimetres. This is the setting that
## trades time for fidelity.
@export var segment_mm: float = 1.2
## Paper colour.
@export var paper: Color = Color(0.945, 0.937, 0.906)
## Paper grain strength.
@export_range(0.0, 1.0) var grain: float = 0.16
## Hatch strength in the wash's mid-tones.
@export_range(0.0, 1.0) var hatch: float = 0.22
## How far a wash bleeds past its edge, in paper millimetres.
@export var bleed_mm: float = 1.8
## How dark a wash goes at its own edge.
@export_range(0.0, 1.0) var edge_darkening: float = 0.30
## The ink pass: a light broad stroke under a dark narrow one.
@export var ink_under_width: float = 1.8
@export var ink_over_width: float = 1.0
@export_range(0.0, 1.0) var ink_under_alpha: float = 0.28
@export_range(0.0, 1.0) var ink_over_alpha: float = 0.92
@export_range(0.0, 1.0) var ink_lighten: float = 0.45
## Ink edge softness, as a share of full coverage rather than a length.
@export_range(0.0, 1.0) var ink_softness: float = 0.45
## Texels per paper millimetre. The one field about pixels, and it says so.
@export_range(1.0, 24.0) var texels_per_mm: float = 6.0
## Millimetres per repeat of the paper fibre, and of the cross-hatch. Paired with the
## texture sizes: a repeat that puts a whole texture inside two texels of the sheet is
## a grain setting that does nothing.
@export var grain_mm: float = 3.0
@export var hatch_mm: float = 1.6
## Supersample factor for a still rendered with this look. This is the antialiasing.
@export_range(1, 3) var supersample: int = 2
```

REQ-V13.1 Every table in §13 shall be keyed by a name the rest of the project
already uses — a layer name, a material path, a pen slot — and never by an index or
by an identifier invented here.

REQ-V13.2 A look shall be a savable resource, so two presentation styles can
coexist without either of them being a code change.

---

## 14. Acceptance criteria

| # | Criterion | Verified by |
|---|---|---|
| AC-V1 | A wobbled stroke stays within `WOBBLE_LIMIT_MM` of its true stroke at every sample, for every entity kind. | test |
| AC-V2 | The same entity wobbles identically across two calls with the same seed, and differently with a different seed. | test |
| AC-V3 | The painted path and the working path produce the same strokes, entity for entity, before the wobble is applied. | test |
| AC-V4 | A wash region is produced for every area entity, and for no annotation. | test |
| AC-V5 | A layer with no wash entry produces no wash, and raises nothing. | test |
| AC-V6 | Grain and hatch scale with paper millimetres: the same paper size at two pixel sizes gives the same paper UV. | test |
| AC-V7 | A texture set with a missing map raises and returns null. | test |
| AC-V8 | `uv1_world_triplanar` is set on every material built for extruded geometry. | test |
| AC-V9 | A self-intersecting outline is refused, with a message naming it, and produces no mesh. | test |
| AC-V10 | A slab's mesh has the requested height, base and area, within a tolerance. | test on the committed mesh's bounds |
| AC-V11 | Insetting an outline by more than its own width is refused, not returned empty. | test |
| AC-V12 | Two builds from one document and one solid table produce identical vertex counts and bounds. | test |
| AC-V13 | A solid is rebuilt after its entity changes and not before the debounce has elapsed. | test |
| AC-V14 | `OrbitCamera.frame()` fits a known box inside the frame at the camera's own FOV and the viewport's aspect. | test |
| AC-V15 | Pitch and distance stay inside their clamps after a large drag, including one that crosses a clamp. | test |
| AC-V16 | `SunStudy.position()` is stable for fixed inputs; a northern summer noon is high and southerly. | test |
| AC-V17 | `SunStudy.apply()` returns false and leaves the light untouched when the sun is below the horizon. | test |
| AC-V18 | Presentation mode restores every property it changed, visibility included. | test on `begin()` then `end()` |
| AC-V19 | The still exporter produces exactly the requested pixel size, whatever the window size. | test |
| AC-V20 | A still rendered with `flatten` has no transparent pixel. | test |
| AC-V21 | A still's sidecar names the sun, the camera, the plot scale and the entity count. | test |
| AC-V22 | The stylised tier's outline colour is the layer's plotted pen colour. | test |
| AC-V23 | A plant's 3D instance colour and its 2D wash colour come from the same `PlanStyle` entry. | test |
| AC-V24 | A texture-set name with no set raises and returns null rather than a default material. | test |
| AC-V25 | The plugin loads, adds exactly one dock, and removes it leaving nothing behind. | manual, in the editor |
| AC-V26 | The sun's declination is zero to within a hundredth of a degree at the published instant of an equinox, and equals the obliquity of the ecliptic at the solstice. | test |
| AC-V27 | The equation of time is within half a minute of zero on 15 April, 13 June, 1 September and 25 December, and reaches its published extremes in early November and mid-February. | test |
| AC-V28 | A site's clock time becomes a solar time through the longitude, the zone offset and the equation of time; the two paths through the study agree to three arcseconds once that difference is paid. | test |
| AC-V29 | A site is a latitude, a longitude and a zone offset together: saved with the drawing, restored from an older file that carries only a latitude, carried through an undo, and returned by `DraftDocument.site()` in the shape the study takes. | test |
| AC-V30 | A moment whose sun never rises reports a polar day or night rather than a time, and refraction is reported beside the geometric altitude rather than in it. | test |
| AC-V31 | A tier's shadow range covers the framed garden and is never less than the tier's own budget, whichever order the tier and the framing arrive in. | test |

REQ-V14.1 AC-V1 to AC-V31 shall be automated tests in `tests/test_vis_*.gd`,
following this project's existing test convention, and shall run in the existing
suite, except AC-V25, which needs a running editor and is manual. The numbers a
sun study is held to are published ones - Meeus's worked example, the dates the
equation of time is zero, the almanac's sunrise - because a test that agreed only
with this project would pass for a study that was consistently wrong.

REQ-V14.2 No acceptance criterion shall be satisfied by a visual claim. Every
criterion above is a number, a count, a size or a refusal.

REQ-V14.3 The subsystem shall not regress the existing suite: every test that
passed before a change to this subsystem shall still pass after it, including with
the presentation nodes added to `main.tscn`. A count written into a specification is
a number that goes stale in silence, which is the one thing this section is against.

---

## 15. Phasing

Each phase is a shippable increment with its own tests, ordered to get a usable
picture soonest.

| Phase | Content | Why here |
|---|---|---|
| **1. Wash** | `WashTable`, `WashPainter`, the three-pass mottle, planting canopies, `SketchBaker`, a flat painted still of the plan. | The largest visual return for the least machinery, and it exercises the bake-and-composite path everything else needs. |
| **2. Sketch** | `SketchStroke`, the ink pass and its double stroke, `sketch_paper.gdshader`, `SketchStyle`, supersampling in the still path. | Makes it look hand-drawn, on top of a bake path that already works. |
| **3. Hardscape** | `HardscapeMaterial`, the texture sets, world triplanar, and `SolidTable` + `CadSolid` for the first slabs and ribbons. | The first time the plan and the 3D agree about a *shape*, which is the point of §8. |
| **4. Preview** | `PresentationTier`, `PresentationDirector`, `SunStudy`, `OrbitCamera`, the presentation eye and the HUD hiding. | A client can now be given the mouse. |
| **5. Planting at scale** | `PlantingInstancer`, the foliage shader, per-instance colour and sway. | Once there are enough plants for it to matter, and not before (REQ-V7.6). |
| **6. Still** | `StillExporter`, the sidecar, the batch, the A3-at-300-dpi preset. | The deliverable. It needs everything above it to be worth rendering. |
| **7. Walk-through and video** | `WalkRoute`, the dwell, Movie Maker. | The least-used output, and the only one that needs a settled scene. |
| **8. Plugin** | `addons/vis_tools`, the dock, the diagnostics panel, batch rendering. | Last, because it is an authoring surface over things that must already work. |

REQ-V15.1 A phase shall be shippable on its own: no phase shall leave the project
with a half-built feature that a user can reach.

REQ-V15.2 Every phase shall add its tests in the same commit as its code.

### 15.1 What is built, and what is still only here

A specification that reads as though everything in it exists is worse than no
specification, so the status of each phase is recorded with the phase. "Built" means
the file exists, has tests, and is reachable from the running game.

| Phase | Status | What exists |
|---|---|---|
| **1. Wash** | **built** | `wash_table.gd`, `wash_painter.gd`, `cad_solid.gd` (outline only), `sketch_baker.gd`, `painted_plan.gd`, the painted sheet in the HUD, `R` to open it, *Save a still*. `tests/test_vis_wash.gd`, 25 tests. |
| **2. Sketch** | **built** | `sketch_stroke.gd` (the wobble), `sketch_style.gd` + `resources/vis/sketch_default.tres` (the look), `ink_painter.gd` (the two-pass ink), `sketch_compositor.gd` + `resources/shaders/sketch_paper.gdshader` (paper, grain, hatch, bleed, wet edge, ink), supersampling in the painted path. So the painted plan is colour *and* linework. `tests/test_vis_sketch.gd`, 18 tests. |
| **3. Hardscape** | **built** | `solid_table.gd` (keyed by the real layers), `cad_solid.gd`'s `slab()` and `ribbon()` with the winding decided and tested, `hardscape_material.gd` + `texture_set_builder.gd` and five generated texture sets in `resources/textures/hardscape/`, `derived_builder.gd` as a node in `main.tscn`. Draw a rectangle on 300-NEW-HARD and a paving slab stands up in the 3D view. `tests/test_vis_solid.gd`, 38 tests. §8.8 records the seven corrections building it forced. |
| **4. Preview** | **built** | Phase 4 was built before phase 1, because a presentation needed a camera: `presentation_tier.gd`, `presentation_director.gd`, `sun_study.gd`, `orbit_camera.gd`, the Presentation panel. The sun study is **astronomical** since §16.6 was answered: Meeus's routine with the equation of time and refraction in it, a site of three fields on the drawing, and a clock hour that means the client's own clock, exposed as five labelled fields on the panel with a button that saves the site back to the plan. `tests/test_vis_presentation.gd` and `tests/test_vis_sun.gd`, 35 tests between them. §3–§4 of this table's order is a dependency order for the *painted* path, not a commitment about which comes first. |
| **5. Planting at scale** | **not needed at this scale** | `planting_instancer.gd` does not exist and should not: §16's answer is *dozens of plants per plan*, and forty plants want ordinary nodes. Recorded as a decision rather than as a gap — REQ-V7.6's threshold is the whole argument, and a plan that grows to hundreds is the event that reopens it. |
| **6. Still** | **built** | `still_exporter.gd` and `still_sidecar.gd` write real PNGs with sidecar records, from the presentation camera and from the painted plan. `still_preset.gd` holds the four output sizes with the proposal default at A3-at-300-dpi; `render_batch.gd` is the batch as a *ledger* (`next_job`/`record`, not a loop); `proposal_page.gd` places a still on a sheet and reads the sheet's own title block rather than inventing a second one; and `pdf_writer.gd` gained image XObjects, byte-identical when there are no images. §10.5's Movie Maker remains the documented route for video, not a built feature. `tests/test_vis_still_preset.gd`, `test_vis_render_batch.gd`, `test_vis_proposal_page.gd`. |
| **7. Walk-through** | **built** | `walk_route.gd` (the stops, and the route as its own clock: `duration`, `position_at`, `look_at`, `stage_at`) and `walk_director.gd` (the camera that follows it). A route of fewer than two stops is refused by name (REQ-V9.5); a stalled frame is clamped and cannot teleport the camera; a camera standing exactly on what it looks at keeps its own orientation. Movie Maker stays the documented recorder (`OS.has_feature("movie")`). `tests/test_vis_walk.gd`, 30 tests; `tools/walk_demo.gd` + `scenes/walk_demo.tscn` take a still at each stop. |
| **8. Plugin** | **built** | `addons/vis_tools/` — `plugin.gd` (`@tool EditorPlugin`, an `EditorDock` on `DOCK_SLOT_RIGHT_BL`), `presentation_dock.gd` (a plain `Control` with no editor API, so it is testable off-tree) and `scripts/vis/vis_diagnostics.gd`. The dock holds no arithmetic and does no rendering: findings from `VisDiagnostics`, jobs from `VisRenderBatch`, and `render_requested` answered by the plugin through the project's own `StillExporter` (REQ-V11.1). `tests/test_vis_diagnostics.gd` (18) and `test_vis_presentation_dock.gd` (19). |

**Two design corrections the build forced**, both recorded in §4.2 and §4.4: the wash
table's layer names, and where a prop's wash colour comes from. Neither was visible
until the table was written against the project's own layers, which is the argument for
building a phase rather than only specifying it.

**Three more, from building the sketch pass**, all recorded in §3.5 and §13. Two of them
were the same mistake in different clothes — a length written in pixels — and the third
was a setting that did nothing:

1. **The compositor's shader took pixel counts** (`texels_per_mm`, `bleed_pixels`),
   which is exactly the failure REQ-V3.7 exists to prevent, on the page that states the
   requirement: a 2× bake would have come out with grain half the size.
2. **The grain repeat was a quarter of a millimetre**, which put the whole fibre texture
   inside one and a half texels of the sheet, where the mip filter averaged it into flat
   colour. The sheet was rendered, filed, and perfectly smooth, with no error. Every
   length in the shader is now paper millimetres and the texture sizes are paired with
   the repeats by a test.
3. **`wash_opacity` was a second opacity over the wash table's own.** The per-layer
   `opacity` is the one that knows what medium it is describing; the global one was
   deleted rather than reconciled, because two controls for one value is one control and
   one bug — and the bug is the setting that does nothing when a designer turns it.

The lesson the three share: a visual feature must be *looked at*, at its real size, and
not only unit-tested. All three passed their tests.

**Four more, from phases 6 to 8**, each a place the sketch was wrong and the build said so:

1. **The batch is a ledger, not a loop** (§10, phase 6). `for job in jobs: await render(job)`
   cannot be stopped, cannot say which job failed, and cannot be driven from an editor dock
   where each render answers later. `VisRenderBatch` hands out one job (`next_job`) and takes
   its answer back (`record`), and the dock holds exactly one in flight - which is what makes
   "3 of 7 written, one refused" something the dock can show.
2. **The proposal page reads the sheet's own furniture** (§16.1, phase 6). The page does not
   lay out a second title block; it takes the one the sheet exporter already draws, so the
   proposal and the plotted sheet cannot disagree about where the border is. An embedded still
   is never enlarged and is capped, so a small render is not stretched into a soft one.
3. **The route is its own clock** (§9.2, phase 7): a walk-through that can only be checked by
   watching it is one nobody can test.
4. **A deliberate non-wash is silent and a deliberate non-solid is a note** (§11.3, phase 8).
   The first sketch treated "no wash entry" and "no solid" alike; they are not alike, and the
   tables already say which is which by having two halves.

---

## 16. Open questions

Answers change the phasing, not the architecture.

**Answered 2026-10-20.** Recorded here rather than in a conversation, because two of them
changed the plan:

1. **Which output matters most?** — **All three, in that order: the sheet, then a 4K image,
   then video.** Phase 6 (the still and the batch) is therefore next, and phase 7 (the
   walk-through) stays last. The most valuable single thing phase 6 can add is a **proposal
   page**: a still placed on a sheet with the title block. That is the two outputs that come
   first, joined, and it is why the still exporter and the sheet exporter should learn about
   each other.
2. **Is the hand-drawn look for the client, or for the drawing set?** — **The client now,
   the drawing set later.** So the painted path stays a compositor over the bake: images and
   stills get the look, and the plotted PDF does not, yet. The door must not close, and it
   has not: the wash and the ink both take their geometry from `DraftRender` — the same
   `strokes()` and `layout()` the sheet plots from — so a sketch-style plot later is a new
   *emitter* over existing geometry, not a second drawing engine.
3. **Does the client ever see the software?** — **Probably later.** The orbit rig and the
   presentation panel stay, and stay in working order.
4. **Are texture sets being bought, or generated?** — **Generated**, and this is answered by
   building it (§5.1): only a set's albedo is drawn, and its normal and ORM maps are derived
   from it.
5. **How many plants per plan, really?** — **Dozens.** **This cancels phase 5.** Instancing,
   per-instance colour and a foliage shader are not worth their complexity for a plan with
   forty plants, and the yard's ordinary nodes are what such a plan wants. The status table
   below records it as *not needed* rather than as *not built*, which is a different thing
   and a better one: REQ-V7.6's own threshold is the reason — instancing is justified by
   count, not by fashion.
6. **Sun-study accuracy:** — **Astronomical.** The equation of time, the aberration and
   nutation in longitude, the obliquity of the ecliptic and atmospheric refraction are all in
   it, so the sun stands where Meeus and the NOAA calculator put it: a hundredth of a degree,
   which is a centimetre of shadow direction for every metre of shadow. The reason is that a
   shadow is evidence. A client who says "it will be in the shade by four" is asking a
   question whose answer they can check against their own kitchen window, and a cosine
   approximation read off a solar hour is not an answer to that. It also settles what the hour
   *means*: the panel's hour is the clock at the site, not the sun's own time, so the shift
   the equation of time causes - up to sixteen minutes, twice a year, in opposite directions -
   is paid rather than ignored. Built in `scripts/vis/sun_study.gd` and checked against
   published values rather than against itself: the four dates the equation of time is zero,
   the sun on the equator at the instant of the March equinox, the tilt at the solstice, and
   the almanac's sunrise in Ottawa - 05:14 and 20:54 Eastern Daylight Time on 21 June, which
   needs the calendar, the longitude, the zone offset, the equation of time, the refraction,
   the tilt and the trigonometry to be right all at once.
7. **Which latitude and time zone?** — **~45°N, eastern Canada / northern US**, and the site is
   now three fields rather than one. A latitude, a longitude and a zone offset are stored
   together on the *drawing* (`DraftDocument.site()`, defaulting to 45°N 75°W on standard
   time), because they are facts about the site in the way the units are a fact about the
   practice: saved with the document, carried through an undo, read by the presenter, and
   offered back to the drawing by a button on the presentation panel - a site the panel can
   edit and the drawing cannot keep would be a study of somewhere else. **The zone offset is
   the one in force at the site, daylight saving included**, because a rule for it would be
   right in Ontario and wrong in Portugal; the panel says so and leaves the hour to the
   designer who lives there. So the clock is the client's clock: 16:00 in Ontario in June is a
   sun 38° up and bearing 267°, rising at 04:13 standard time and setting at 19:50.
8. **Do stills go into the repository, or into `user://`?** — **`user://`**, as §10.2 says.
   The sample sheets are generated on demand by `tools/sample_sheets.gd`, and the rasterised
   previews of them are gitignored: a committed picture of output goes stale the moment the
   exporter changes and then disagrees with the code in silence.