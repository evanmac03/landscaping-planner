shader_type canvas_item;
// Composes one painted picture over paper: paper under everything, the wash on it, a
// wet edge where the wash stops, and the ink over all of it.
//
// Nothing here reads hint_screen_texture, deliberately. A screen read would force a
// back-buffer copy (see the note in section 4.5) and would make the result depend on
// the order things happened to be drawn in; reading its own two layers makes this
// shader order-independent, and therefore testable (REQ-V3.8).
//
// **No uniform here is a pixel count.** Grain, hatch, bleed and the light's edge are
// all paper millimetres, and the sheet's size is what converts them, so a bake at
// twice the resolution puts the same grain on the same paper (REQ-V3.7). The
// specification's first draft had `texels_per_mm` and `bleed_pixels` in this list,
// which made the grain finer as the render got bigger - the exact failure the
// requirement names.

/** The paper. Slightly warm, slightly green, never pure white. */
uniform vec4 paper_colour : source_color = vec4(0.945, 0.937, 0.906, 1.0);
/** The wash layer. Its alpha is coverage, its colour is pigment. */
uniform sampler2D texture_wash : source_color, repeat_disable, filter_linear;
/** The ink layer. Its alpha is ink coverage. */
uniform sampler2D texture_ink : source_color, repeat_disable, filter_linear;
/** A tiling paper fibre. */
uniform sampler2D texture_grain : hint_default_white, repeat_enable, filter_linear_mipmap;
/** A tiling cross-hatch, revealed in the wash's mid-tones. */
uniform sampler2D texture_hatch : hint_default_white, repeat_enable, filter_linear_mipmap;
/** The sheet, in millimetres. The conversion for every length below. */
uniform vec2 paper_mm = vec2(420.0, 297.0);
/** Millimetres per repeat of the paper fibre. */
uniform float grain_mm = 0.25;
/** Millimetres per repeat of the cross-hatch. */
uniform float hatch_mm = 1.6;
/** How much paper the ink's grain texture is allowed to modulate the paper. */
uniform float grain : hint_range(0.0, 1.0) = 0.16;
/** Hatch strength in the wash's mid-tones. */
uniform float hatch : hint_range(0.0, 1.0) = 0.22;
/** How far the wash bleeds past its own edge, in paper millimetres. */
uniform float bleed_mm : hint_range(0.0, 12.0) = 1.8;
/** How much darker the wash is at its own edge, which is what a wet edge does. */
uniform float edge_darkening : hint_range(0.0, 1.0) = 0.30;
/** Ink edge softness, as a share of full coverage. The one antialiasing the
 *  *compositor* has: it turns a threshold into a ramp, so a half-covered texel reads
 *  as a soft line rather than a hard one (REQ-V3.4). Dimensionless on purpose - a
 *  ramp in coverage is not a distance on the paper. */
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
	// Bleeding outward is the *maximum* of the neighbours, not the average: a wet
	// edge spreads, so coverage should grow wherever a neighbour has it.
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
	// The pigment's strength is the layer's own alpha, which the wash table set: a
	// second global opacity on top of it would be two controls for one thing, and the
	// one that is per-layer is the one that knows what medium it is describing.
	vec3 pigment = wash.rgb * hatch_mask * mix(vec3(1.0), vec3(0.72), edge * edge_darkening);
	vec3 colour = mix(paper, pigment, wash.a * covered);

	// The ink goes over all of it. Its coverage is fetched once; the ramp is applied
	// to the alpha so a fractional-covered edge texel reads as a soft line rather than
	// a hard one.
	float ink = texture(texture_ink, UV).a;
	ink = smoothstep(0.5 - ink_softness * 0.5, 0.5 + ink_softness * 0.5, ink) * ink;
	vec3 ink_colour = texture(texture_ink, UV).rgb;
	colour = mix(colour, ink_colour, ink);

	COLOR = vec4(colour, 1.0);
}