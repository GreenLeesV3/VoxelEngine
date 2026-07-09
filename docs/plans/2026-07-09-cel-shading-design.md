# Cel-Shading + Post-Processing Pipeline — Design Document

**Date:** 2026-07-09
**Status:** Approved

**User request:** "completely overhauled rendering and lighting system... outer edge
based cel shading, higher saturations, colors being more cartoony and vibrant...
comic booky but dreamy... detailed reflections, per layer depth on opacity for
water... light can pierce layers of translucent blocks."

**Phase 1:** Cel-shading + post-process edge detection + saturation boost.
This establishes the art style. Reflections, god rays, and water depth
translucency are future phases.

---

## 1. Decisions of Record

| Question | Decision |
|---|---|
| Lighting bands | 4+ bands (painterly). Quantized lighting with smooth-ish transitions. Not flat 2-band, not fully smooth — a stepped gradient that reads as hand-painted. |
| Outlines | Post-process edge detection on depth + normal discontinuities. Material-tinted (darker version of the surface color, not pure black). Variable width based on edge strength. |
| Saturation | +30% in post-processing. Colors pop without going neon. |
| Pipeline | Render scene to offscreen color + depth textures → post-process fullscreen pass → blit to swapchain. First render-to-texture infrastructure in the engine. |
| Shader changes | Voxel shader: quantize lighting into bands. Post-process shader: edge detection + saturation + color grading. |

## 2. Architecture

### 2.1 Current pipeline (before)

```
Scene render pass → swapchain (direct, no post-processing)
  ├─ chunks (opaque)
  ├─ debris bodies (opaque)
  ├─ particles (alpha-blended)
  └─ debug overlay (alpha-blended)
```

### 2.2 New pipeline (after)

```
Scene render pass → offscreen color + depth textures
  ├─ chunks (opaque, cel-shaded lighting)
  ├─ debris bodies (opaque, cel-shaded lighting)
  └─ particles (alpha-blended, unchanged)

Post-process pass → swapchain
  ├─ edge detection (Sobel on depth + normal)
  ├─ outline overlay (material-tinted)
  ├─ saturation boost (+30%)
  └─ color grading (dreamy: slight lift in shadows, warm tint)

UI pass → swapchain (on top of post-processed scene)
  ├─ debug overlay (unchanged)
```

### 2.3 Offscreen textures

Two offscreen textures, sized to the swapchain:

- **Color texture** (`RGBA16Float`): the cel-shaded scene. High precision
  for post-processing headroom.
- **Depth texture** (`Depth32Float`): same as the existing depth buffer,
  but accessible as a texture binding in the post-process shader (the
  existing depth view is attachment-only, not bindable).

A **normal texture** (`RGBA8Unorm`): world-space normals, rendered in
the scene pass via a second color attachment. Needed for edge detection
(normal discontinuities = material/silhouette edges). Alternatively,
reconstruct normals from depth in the post-process pass — cheaper but
less accurate. We'll use a proper normal attachment for quality.

### 2.4 Post-process shader

A fullscreen triangle (3 vertices, no vertex buffer) that samples the
color, depth, and normal textures:

1. **Edge detection**: Sobel operator on depth (silhouette edges) and
   normal (material/face edges). Combine into an edge mask.
2. **Outline color**: sample the color texture at the edge pixel, darken
   it by 60% to get the material-tinted outline color. Blend the outline
   over the base color.
3. **Saturation**: convert to HSV-like space, boost saturation by 30%,
   convert back. Or use a simpler luminance-based approach:
   `c = mix(lum(c), c, 1.3)`.
4. **Color grading**: slight lift in shadows (`c += 0.03`), warm tint
   (`c.r *= 1.02; c.b *= 0.98`), gentle contrast S-curve.

## 3. Voxel shader changes (`voxel.wgsl`)

The fragment shader's lighting is quantized into bands:

```wgsl
// Current: smooth half-Lambert
let sun = pow(clamp(ndotl * 0.5 + 0.5, 0.0, 1.0), 1.5) * SUN_STRENGTH;

// New: quantized into 4 bands with smooth transitions
let raw = clamp(ndotl * 0.5 + 0.5, 0.0, 1.0);
let bands = 4.0;
let quantized = floor(raw * bands + 0.5) / bands;
// Smooth the band edges slightly (0.1 width) to avoid hard stair-stepping.
let smooth_q = mix(quantized, raw, smoothstep(0.45, 0.55, fract(raw * bands)));
let sun = smooth_q * SUN_STRENGTH;
```

Also: the fragment shader now outputs to two color attachments (color +
normal) instead of one. The normal attachment stores `world_normal *
0.5 + 0.5` (encoded to 0..1 range for RGBA8).

## 4. New files

- `assets/shaders/postprocess.wgsl`: the post-process shader (edge
  detection + saturation + color grading).
- `crates/vox-render/src/postprocess.rs`: the post-process pipeline
  (offscreen textures, fullscreen pipeline, render pass management).

## 5. Testing plan

This is a visual system — tests are limited to:
- The post-process pipeline initializes without errors.
- The offscreen textures are the correct format and size.
- The fullscreen pass renders without crashing.

Visual verification is by running the app and checking:
- Outlines appear on voxel edges (depth discontinuities) and face
  boundaries (normal discontinuities).
- Lighting has visible bands (4 steps from shadow to bright).
- Colors are more saturated than before.
- The overall feel is "comic booky but dreamy."

## 6. Future phases (not in this PR)

- Water depth transparency (per-voxel opacity, light transmission).
- Screen-space reflections.
- God rays (volumetric light shafts).
- Translucent material light propagation.
