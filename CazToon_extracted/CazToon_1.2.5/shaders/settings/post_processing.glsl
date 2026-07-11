// ============================================================================
// =====                      POST PROCESSING                             =====
// ============================================================================

// Shader credits display (UI label only, not a real setting)
#define SHADER_CREDITS 0 // [0]

// ----------------------------------------------------------------------------
//   Bloom
// ----------------------------------------------------------------------------

// Enable bloom glow effect
#define BLOOM_ENABLED

// Internal bloom render scale. Bloom is blurred anyway, so the blur chain can
// run lower-res and get scaled back up in final.
#define BLOOM_RENDER_SCALE 0.50 // [0.50 0.75 1.00]

// Bloom intensity (glow brightness)
#define BLOOM_INTENSITY 0.15// [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.25 1.50 1.75 2.00 2.50 3.00]
// Bloom radius (glow spread distance)
#define BLOOM_RADIUS 0.6// [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.2 1.4 1.6 1.8 2.0 2.5 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 12.0 14.0 16.0 20.0 25.0 30.0]

// Close bloom strength multiplier (near lights)
#define BLOOM_CLOSE_STRENGTH 1.0 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.45 1.50 1.60 1.70 1.80 1.90 2.00 2.25 2.50 2.75 3.00 3.50 4.00]
// Close bloom radius multiplier (near lights)
#define BLOOM_CLOSE_RADIUS 1.0 // [0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.45 1.50 1.60 1.70 1.80 1.90 2.00 2.25 2.50 2.75 3.00 3.50 4.00 4.50 5.00 6.00 7.00 8.00 9.00 10.0 12.0 14.0 16.0 18.0 20.0]
// Far bloom strength multiplier (distant lights)
#define BLOOM_FAR_STRENGTH 1.0 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.45 1.50 1.60 1.70 1.80 1.90 2.00 2.25 2.50 2.75 3.00 3.50 4.00]
// Far bloom radius multiplier (distant lights)
#define BLOOM_FAR_RADIUS 1.0 // [0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.45 1.50 1.60 1.70 1.80 1.90 2.00 2.25 2.50 2.75 3.00 3.50 4.00 4.50 5.00 6.00 7.00 8.00 9.00 10.0 12.0 14.0 16.0 18.0 20.0]
// Entity bloom strength multiplier (emissive mob eyes, glow layers, etc.)
#define ENTITY_BLOOM_STRENGTH 2.25 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.45 1.50 1.60 1.70 1.80 1.90 2.00 2.25 2.50 2.75 3.00 3.50 4.00 5.00 6.00]
// Entity bloom radius multiplier (pushes emissive entity bloom farther into the halo)
#define ENTITY_BLOOM_RADIUS 1.20 // [0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.45 1.50 1.60 1.70 1.80 1.90 2.00 2.25 2.50 2.75 3.00 3.50 4.00 5.00 6.00 8.00 10.0]
// Distance compensation (boost bloom for far objects, 0 = off)
#define BLOOM_DISTANCE_COMPENSATION 0.25 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0 3.0 4.0]
// Bloom saturation (color vividness of bloom glow)
#define BLOOM_SATURATION 5.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 1.75 2.0 2.5 3.0 4.0 5.0]

// Bloom in sunlight (reduces bloom on surface during day, underground unaffected)
#define BLOOM_DAY_STRENGTH 0.70// [0.00 0.02 0.04 0.06 0.08 0.10 0.12 0.14 0.16 0.18 0.20 0.22 0.24 0.26 0.28 0.30 0.32 0.34 0.36 0.38 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]
// --- Particle Bloom ---
// Particle bloom intensity
#define PARTICLE_BLOOM_INTENSITY 2.50 // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 1.75 2.00 2.25 2.50 2.75 3.00 3.50 4.00 5.00 6.00 8.00]

// Particle brightness threshold (lower = more glow)
#define PARTICLE_BLOOM_THRESHOLD 0.10// [0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90]

// Particle warmth threshold
#define PARTICLE_BLOOM_WARMTH 0.25 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40]


// ----------------------------------------------------------------------------
//   Metalness (Fake PBR for metallic blocks)
// ----------------------------------------------------------------------------

// Enable metalness effect on metal/gem blocks
#define METALNESS_ENABLED

// Metalness intensity (reflection strength)
#define METALNESS_INTENSITY 0.1// [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.2 1.5 2.0 3.0]
// Fresnel effect strength (edge reflection boost)
#define METALNESS_FRESNEL 0.8// [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]

// Specular highlight sharpness (lower = sharper, tighter highlight)
#define METALNESS_ROUGHNESS 0.30// [0.05 0.08 0.10 0.12 0.15 0.18 0.20 0.25 0.30 0.40 0.50 0.60 0.70 0.80]
#define GEM_SPARKLE 0.0 // [0.0 0.25 0.50 0.75 1.0]


// ----------------------------------------------------------------------------
//   PBR Materials (LabPBR 1.3 + legacy oldPBR resource pack support)
// ----------------------------------------------------------------------------

// Enable PBR material support (normal maps + specular maps from resource packs)
#define PBR_ENABLED
// Resource pack format — 0=Auto (detect via Iris), 1=LabPBR 1.3, 2=oldPBR (SEUS/Continuum)
// Auto follows the MC_TEXTURE_FORMAT_LAB_PBR Iris macro set by the pack's shaders.properties.
#define PBR_FORMAT 0 // [0 1 2]

// Specular highlight strength — controls brightness of the PBR sheen.
// Size of the highlight is governed by roughness, not strength.
#define PBR_SPECULAR_STRENGTH 2.0// [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.2 1.5 2.0 2.5 3.0]
// Normal map influence strength
#define PBR_NORMAL_STRENGTH 1.0// [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0]

// LabPBR ambient-occlusion strength (how much _n.b darkens indirect lighting)
#define PBR_AO_STRENGTH 1.0// [0.0 0.25 0.5 0.75 1.0]

// LabPBR porosity strength (how much _s.b darkens wet surfaces in rain)
#define PBR_POROSITY_STRENGTH 1.0// [0.0 0.25 0.5 0.75 1.0 1.5]

// LabPBR subsurface scattering strength (_s.b range 65-255)
#define PBR_SSS_STRENGTH 1.0// [0.0 0.25 0.5 0.75 1.0 1.5 2.0]

// Metal tint intensity (how strongly reflections pick up the metal's own colour)
#define PBR_METAL_TINT_STRENGTH 1.0// [0.0 0.25 0.5 0.75 1.0 1.25 1.5]

// Default wood roughness (when no PBR resource pack)
#define DEFAULT_WOOD_ROUGHNESS 0.3// [0.3 0.4 0.5 0.6 0.7 0.75 0.8 0.85 0.9]
// Default stone roughness (when no PBR resource pack)
#define DEFAULT_STONE_ROUGHNESS 0.85// [0.5 0.6 0.7 0.75 0.8 0.85 0.9 0.95]

// ----------------------------------------------------------------------------
//   Leaf Sheen (Subsurface Scattering + Fresnel for natural foliage)
// ----------------------------------------------------------------------------

// Enable leaf sheen effect on leaf blocks
#define LEAF_SHEEN_ENABLED

// Subsurface scattering strength (warm glow through back-lit leaves)
#define LEAF_SSS_STRENGTH 0.4// [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.2 1.5 2.0]

// Fresnel rim strength (bright edge at grazing viewing angles)
#define LEAF_FRESNEL_STRENGTH 0.8 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.2 1.5 2.0 3.0]

// Shadow transmittance (subtle light leak onto back faces of leaves)
#define LEAF_SHADOW_TRANSMITTANCE 0.10// [0.0 0.05 0.10 0.15 0.20 0.25 0.30 0.40 0.50]

// Shadow softness on leaf blocks (wider = blurrier shadows, hides blocky geometry)
#define LEAF_SHADOW_SOFTNESS 3.0// [0.0 1.0 2.0 3.0 4.0 5.0 6.0 8.0 10.0 12.0 16.0 20.0 24.0 32.0 48.0 64.0]
// ----------------------------------------------------------------------------
//   Outlines
// ----------------------------------------------------------------------------

// Outline mode: 0 = off, 1 = standard, 2 = dungeons style
#define OUTLINES 2 // [0 1 2]

// Outline brightness/darkness
#define OUTLINE_BRIGHTNESS 0.20// [-1.00 -0.90 -0.80 -0.70 -0.60 -0.50 -0.40 -0.30 -0.20 -0.10 0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.50 2.00 3.00 5.00]
// Outline color saturation (1 = keep current scene color, higher = more vivid)
#define OUTLINE_SATURATION 1.35// [0.00 0.25 0.50 0.75 1.00 1.10 1.25 1.35 1.50 1.75 2.00 2.50 3.00 4.00 5.00]

// Outline thickness (in pixels)
#define OUTLINE_PIXEL_SIZE 2// [1 2 3 4 5 6 8 10 12 16 24 32 48 64]


// ----------------------------------------------------------------------------
//   Color Correction
// ----------------------------------------------------------------------------

// Enable sharpening filter
#define POST_SHARPEN
// Sharpening strength
#define POST_SHARPEN_STRENGTH 0.15// [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80]
// Color saturation (1 = neutral)
#define POST_SATURATION 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00 2.50 3.00 4.00 5.00 10.00 25.00 50.00 100.00]

// Color contrast (1 = neutral)
#define POST_CONTRAST 1.05 // [0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.45 1.50 1.60 1.70 1.80 1.90 2.00 3.00]
// Brightness offset (0 = neutral)
#define POST_BRIGHTNESS 0.00// [-0.50 -0.45 -0.40 -0.35 -0.30 -0.25 -0.20 -0.15 -0.10 -0.05 0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.60 0.70 0.80 0.90 1.00 1.50 2.00]

// ----------------------------------------------------------------------------
//   Temporal Anti-Aliasing (TAA)
// ----------------------------------------------------------------------------

// Enable TAA ? blends frames over time for smoother volumetrics and reduced aliasing
#define TAA_ENABLED

#ifdef TAA_ENABLED
const bool TAA_ENABLED_ANCHOR = true;
#else
const bool TAA_ENABLED_ANCHOR = false;
#endif

// Blend factor ? how much of the previous frame to keep (higher = smoother but more ghosting)
#define TAA_BLEND 0.90 // [0.75 0.80 0.85 0.90 0.92 0.95]

// ----------------------------------------------------------------------------
//   FXAA (Fast Approximate Anti-Aliasing)
// ----------------------------------------------------------------------------

// Enable FXAA — smooths jagged block geometry edges at distance
#define FXAA_ENABLED

// Sub-pixel smoothing quality (higher = smoother edges but slightly softer image)
#define FXAA_QUALITY 0.75 // [0.50 0.75 1.00 1.25 1.50]

// Debug view — visualizes which pixels FXAA is actually smoothing.
// Non-Voxy pixels turn grayscale, Voxy non-edge pixels also grayscale,
// Voxy edges are colored: RED = weak smoothing, GREEN = strong smoothing.
// Turn OFF for normal rendering.
//#define FXAA_DEBUG

// ----------------------------------------------------------------------------
//   Color Grading (Cinematic Vibes)
// ----------------------------------------------------------------------------

// Enable color grading system
#define COLOR_GRADING_ENABLED

// --- Tonal & Range (caztoon-grader values, surface) ---
#define CG_EXPOSURE    0.16  // [-2.00 -1.50 -1.00 -0.75 -0.50 -0.25 -0.10 0.00 0.10 0.16 0.25 0.50 0.75 1.00 1.50 2.00]
#define CG_BRIGHTNESS -0.16  // [-1.00 -0.50 -0.25 -0.16 -0.10 0.00 0.10 0.25 0.50 1.00]
#define CG_CONTRAST    0.14  // [-1.00 -0.50 -0.25 -0.10 0.00 0.10 0.14 0.25 0.50 1.00]
#define CG_BLACKS     -0.14  // [-1.00 -0.50 -0.25 -0.14 -0.10 0.00 0.10 0.25 0.50 1.00]
#define CG_WHITES      0.08  // [-1.00 -0.50 -0.25 -0.10 0.00 0.08 0.10 0.25 0.50 1.00]
#define CG_SHADOWS     0.16  // [-1.00 -0.50 -0.25 -0.10 0.00 0.10 0.16 0.25 0.50 1.00]
#define CG_HIGHLIGHTS  0.27  // [-1.00 -0.50 -0.25 -0.10 0.00 0.10 0.25 0.27 0.50 1.00]

// --- Saturation ---
#define CG_SATURATION  0.0   // [-1.00 -0.75 -0.50 -0.25 0.00 0.25 0.50 0.75 1.00]

// --- Temperature & Tint ---
// Temperature: negative = cool/blue, positive = warm/orange
#define CG_TEMPERATURE 0.55  // [-1.00 -0.90 -0.80 -0.70 -0.60 -0.50 -0.40 -0.30 -0.20 -0.10 0.00 0.10 0.20 0.30 0.40 0.50 0.55 0.60 0.70 0.80 0.90 1.00]

// Tint: negative = green, positive = magenta
#define CG_TINT 0.17  // [-1.00 -0.90 -0.80 -0.70 -0.60 -0.50 -0.40 -0.30 -0.20 -0.10 0.00 0.10 0.17 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]


// --- Split Toning (Color different parts of the image) ---
// Enable split toning (shadows/highlights tinting)
#define CG_SPLIT_TONING_ENABLED

// Shadow tint color (RGB 0-1)
#define CG_SHADOW_TINT_R 0.1 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define CG_SHADOW_TINT_G 0.1 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define CG_SHADOW_TINT_B 0.2 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

// Highlight tint color (RGB 0-1)
#define CG_HIGHLIGHT_TINT_R 0.2 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define CG_HIGHLIGHT_TINT_G 0.15 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
#define CG_HIGHLIGHT_TINT_B 0.1 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]

// Split toning intensity (0 = off, 1 = full strength)
#define CG_SPLIT_TONING_INTENSITY 0.15 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.25 1.50 2.00 3.00]

// Split toning balance (-1 = more shadows, 0 = balanced, 1 = more highlights)
#define CG_SPLIT_TONING_BALANCE 0.0 // [-1.00 -0.75 -0.50 -0.25 0.00 0.25 0.50 0.75 1.00]

// --- Lift/Gamma/Gain (Professional Color Grading) ---
// Lift affects shadows (RGB multiplier)
#define CG_LIFT_R 1.0 // [0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50]
#define CG_LIFT_G 1.0 // [0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50]
#define CG_LIFT_B 1.0 // [0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50]

// Gamma affects midtones (RGB power)
#define CG_GAMMA_R 1.0 // [0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50]
#define CG_GAMMA_G 1.0 // [0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50]
#define CG_GAMMA_B 1.0 // [0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50]

// Gain affects highlights (RGB multiplier)
#define CG_GAIN_R 1.0 // [0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50]
#define CG_GAIN_G 1.0 // [0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50]
#define CG_GAIN_B 1.0 // [0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50]

// --- Color Palette / Posterization ---
// Enable color palette limiting (retro/stylized look) - applies to EVERYTHING
//#define CG_POSTERIZE_ENABLED  // Disabled - causes noise

// Number of color levels per channel (lower = more stylized)
#define CG_POSTERIZE_LEVELS 3// [2 3 4 5 6 8 10 12 16 24 32 48 64]

// Posterize dithering (reduces banding)
#define CG_POSTERIZE_DITHER 0.0 // [0.0 0.25 0.5 0.75 1.0]

// --- Texture Palette Limiting ---
// Apply palette limiting directly to block/entity textures (not post-process, no fog)
//#define TEXTURE_PALETTE_ENABLED

// Number of color levels per channel for textures
#define TEXTURE_PALETTE_LEVELS 16 // [2 3 4 5 6 8 10 12 16 24 32]

// --- Vignette ---
// Enable vignette (darkened edges)
//#define CG_VIGNETTE_ENABLED

// Vignette intensity (0 = none, 1 = heavy)
#define CG_VIGNETTE_INTENSITY 0.3 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.50 0.60 0.70 0.80 0.90 1.00]

// Vignette radius (how far from center the darkening starts)
#define CG_VIGNETTE_RADIUS 0.75 // [0.30 0.40 0.50 0.60 0.70 0.75 0.80 0.85 0.90 1.00]

// Vignette softness (smooth transition)
#define CG_VIGNETTE_SOFTNESS 0.4 // [0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80]

// Vignette roundness (1 = circular, lower = more elliptical)
#define CG_VIGNETTE_ROUNDNESS 1.0 // [0.50 0.60 0.70 0.80 0.90 1.00]

// --- Film Grain ---
// Enable film grain (cinematic noise)
//#define CG_FILM_GRAIN_ENABLED

// Film grain intensity
#define CG_FILM_GRAIN_INTENSITY 0.1 // [0.02 0.04 0.06 0.08 0.10 0.12 0.15 0.18 0.20 0.25 0.30 0.40 0.50]

// Film grain size (higher = larger grain)
#define CG_FILM_GRAIN_SIZE 1.5 // [0.5 0.75 1.0 1.25 1.5 2.0 2.5 3.0 4.0]

// Film grain is luminance only (monochrome) vs colored
#define CG_FILM_GRAIN_LUMINANCE

// --- Color Lookup / Preset Styles ---
// Color style preset (adds themed color adjustments)
#define CG_STYLE_PRESET 7// [0 1 2 3 4 5 6 7 8]
// 0 = None (manual settings)
// 1 = Cinematic (warm highlights, cool shadows, slight desaturation)
// 2 = Vintage (sepia-ish, reduced contrast, warm tones)
// 3 = Cyberpunk (teal & orange, high contrast, saturated)
// 4 = Horror (desaturated, green tint, crushed blacks)
// 5 = Fantasy (vibrant, purple shadows, golden highlights)
// 6 = Nordic (cold, desaturated, blue shadows)
// 7 = Tropical (warm, saturated greens and blues)
// 8 = Noir (heavy desaturation, slight blue tint, high contrast)

// Preset intensity (blend between no preset and full preset)
#define CG_STYLE_INTENSITY 0.30// [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]

// --- Hue Shift ---
// Global hue rotation (degrees, for creative effects)
#define CG_HUE_SHIFT 0.0 // [-180.0 -150.0 -120.0 -90.0 -60.0 -30.0 0.0 30.0 60.0 90.0 120.0 150.0 180.0]

// --- Vibrance (intelligent saturation) ---
// Vibrance: boosts less saturated colors more than already saturated ones
#define CG_VIBRANCE 0.15 // [-1.00 -0.75 -0.50 -0.25 0.00 0.10 0.15 0.25 0.50 0.75 1.00]
