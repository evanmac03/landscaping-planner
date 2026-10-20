class_name PresentationTier
extends RefCounted
## One value that sets every rendering budget at once.
##
## A quality setting scattered across five scripts cannot be changed with
## confidence, and cannot be tested at all. This is the table those settings live
## in, so "make it prettier" is one edit in one place.
##
## The budgets were chosen against what the GL Compatibility renderer actually
## supports (docs/visualization-subsystem-spec.md §1): glow and a simplified SSAO
## (radius and intensity only) are available, and screen-space reflections,
## indirect light, volumetric fog and depth of field are not. Nothing here sets a
## property this renderer ignores, because a setting that does nothing is worse
## than no setting - it reads as though it were doing something.

const WORKING := 0
const PRESENTATION := 1
const STILL := 2

## The budgets.
##
## `supersample` is the render scale the still path uses; it is 1 for the
## interactive tiers because the screen is the screen.
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
		# months, so this is where every budget is spent.
		"shadow_max_distance": 30.0, "shadow_blur": 1.4,
		"ssao": true, "ssao_radius": 1.0, "ssao_intensity": 2.0,
		"textured": true, "supersample": 2, "stylised": true,
	},
}

## The tiers the user can choose between, in the order a picker should offer them.
const CHOICES: Array[int] = [WORKING, PRESENTATION, STILL]

## The SSAO properties the Compatibility renderer honours. Anything else on that
## block is ignored, so a tier must not carry it.
const HONOURED_SSAO := ["enabled", "radius", "intensity"]


## The budget for a tier.
##
## An unknown tier gets the working budget rather than an empty dictionary: a
## preview that renders too plainly is recoverable, and a preview that renders
## with no shadow map at all is not.
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


## The tier a name refers to, or WORKING when it is not a tier at all.
static func by_name(tier_name: String) -> int:
	for tier in CHOICES:
		if name_of(tier) == tier_name:
			return tier
	return WORKING