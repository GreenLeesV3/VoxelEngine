# Bloom + SSAO Post-Processing — Design Document

**Date:** 2026-07-10
**Status:** Approved
**Builds on:** The existing HDR post-processing pipeline (`postprocess.rs`, `postprocess.wgsl`).
This document adds two industry-standard screen-space passes: bloom (bright light
bleeding) and SSAO (contact shadows in crevices). No scene pass changes — both
passes read the existing HDR color + depth textures.

---

## 1. Decisions of Record

| Question | Decision |
|---|---|
| SSAO normal source | **Reconstruct from depth gradients** (Sobel/Cross on depth buffer). The current pipeline doesn't write a normal G-buffer; adding one would require modifying the scene render pass. Depth-reconstruction is the standard approach for forward renderers and avoids that. |
| SSAO resolution | **Half-resolution** AO buffer (width/2 × height/2), bilinearly upsampled in the final composite. Bandwidth is the bottleneck; half-res is visually equivalent for soft AO. |
| Bloom approach | **Downsample chain**: bright-pass at full-res → downsample to half-res → horizontal+vertical Gaussian blur at each mip level (3 levels) → upsample and additive-blend back. Standard approach for wide-spread bloom at low cost. |
| Bloom resolution | Bright pass at full-res, blur chain at half/third/quarter res. Upsample blends back to full-res in the final composite. |
| Pipeline architecture | New `BloomSsaoPipeline` struct in `vox-render`, owning its own textures, shaders, and render pipelines. The existing `PostProcessPipeline` is modified to sample the AO buffer and bloom texture in its final composite pass. |
| Shader files | Two new WGSL files: `ssao.wgsl` (SSAO generation) and `bloom.wgsl` (bright pass + blur chain). The existing `postprocess.wgsl` gains AO sampling and bloom additive blending in its final composite. |
| Tone mapping | The existing soft-knee tone map stays in the final composite. Bloom is added *before* tone mapping (bright areas push the knee). AO is applied *before* tone mapping (darkens ambient in crevices). |
| Tunability | Both effects get debug-overlay sliders (intensity, radius, threshold) via the existing `vox-debug` tunable system. |
| Testing | Shader validation test (naga parse). Visual verification by running the engine. No headless unit tests for screen-space effects (they're GPU-only). |

## 2. SSAO (Screen-Space Ambient Occlusion)

### 2.1 Algorithm

1. **Reconstruct view-space position** from the depth buffer at each pixel:
   - Sample `depth_tex` at the pixel
   - Inverse-project from NDC to view space using the camera's inverse view-projection
2. **Reconstruct view-space normal** from depth gradients:
   - Sample depth at the 4 neighbors (cross pattern)
   - Reconstruct their view positions
   - Cross product of the two difference vectors gives the face normal
3. **Sample a hemisphere kernel** of ~16-32 directions (precomputed on CPU, uploaded as a uniform/storage buffer):
   - Each kernel sample is a view-space direction
   - Project the sample point onto the screen, sample depth there
   - If the sampled depth is closer than the sample's depth, it's an occluder → reduce AO
4. **Smooth** the raw AO with a 4×4 blur pass (box or Gaussian) to remove noise
5. **Output** to a half-res `R16Float` texture (0 = fully occluded, 1 = unoccluded)

### 2.2 Textures and bindings

- **Input**: `depth_tex` (existing `Depth32Float`, full-res, `TEXTURE_BINDING` already set)
- **Input**: camera inverse view-projection (new uniform, or pack into existing camera uniform)
- **Input**: kernel samples (storage buffer or uniform array, ~32 vec3s)
- **Output**: `ao_tex` — `R16Float`, half-res, `RENDER_ATTACHMENT | TEXTURE_BINDING`

### 2.3 Shader (`ssao.wgsl`)

Two entry points in one file (compiled as two pipelines):
- `vs` / `fs_ssao` — SSAO generation (fullscreen triangle, half-res target)
- `vs` / `fs_blur` — 4×4 box blur (fullscreen triangle, half-res target)

The blur pass reads the raw AO texture and writes a blurred AO texture (separate texture or ping-pong).

### 2.4 Application in final composite

In `postprocess.wgsl`'s `fs`, after computing the lit color `c`:
```wgsl
let ao = textureSample(ao_tex, samp, uv).r;
c = c * mix(1.0, ao, ssao_intensity);
```
This multiplies the full color (ambient + sun) by the AO factor. The `ssao_intensity`
uniform controls strength (0 = off, 1 = full effect).

## 3. Bloom

### 3.1 Algorithm

1. **Bright pass** (full-res): threshold the HDR color buffer. Pixels above a luminance
   threshold are extracted; below are black. Output to `bright_tex` (full-res, `Rgba16Float`).
   ```wgsl
   let lum = dot(color, vec3f(0.299, 0.587, 0.114));
   let bright = color * smoothstep(threshold, threshold + knee, lum);
   ```

2. **Downsample chain** (3 levels): each level halves the resolution and applies a
   5×5 Gaussian blur. The downsampled result is stored in a mip chain of `bright_tex`.
   - Level 0: full-res bright → half-res blurred
   - Level 1: half-res → quarter-res blurred
   - Level 2: quarter-res → eighth-res blurred

   Each level reads the previous level's output and writes to the next smaller target.

3. **Upsample + composite**: blend the bloom mip chain back up, additive:
   - Start at the smallest mip (level 2)
   - Upsample to level 1, add level 1's blurred result
   - Upsample to level 0, add level 0's blurred result
   - The final upsampled bloom is added to the scene color in the final composite

   Alternatively (simpler): just sample the smallest mip with a large blur radius and
   add it directly. This is less accurate but requires only one extra texture read.

### 3.2 Textures and bindings

- **Input**: `color_tex` (existing `Rgba16Float`, full-res HDR scene)
- **Output**: `bright_tex` — `Rgba16Float`, with mip levels (full → half → quarter → eighth)
  - Created with `mip_level_count: 4` and `COPY_DST | TEXTURE_BINDING | RENDER_ATTACHMENT`
- **Intermediate blur textures**: either ping-pong pair at each mip level, or use the
  mip chain itself (write to mip N, read from mip N for the next pass). The simplest
  approach: separate textures for each blur step.

### 3.3 Shader (`bloom.wgsl`)

Three entry points (compiled as three pipelines):
- `vs` / `fs_bright` — bright-pass extraction (fullscreen, full-res → full-res)
- `vs` / `fs_blur_h` / `fs_blur_v` — separable Gaussian blur (one pipeline, two
  fragment shaders or one with a direction uniform)
- `vs` / `fs_composite` — upsample and additive blend (could be folded into the
  final postprocess pass instead)

**Simplification for v1**: Instead of a full downsample/upsample chain, use a single
half-res blur pass with a large kernel (13-tap Gaussian). This is less physically
accurate but much simpler to implement and still gives a convincing glow:

1. Bright pass at full-res → `bright_tex` (full-res)
2. Blur `bright_tex` with a 13-tap separable Gaussian at half-res → `bloom_tex` (half-res)
3. In the final composite, sample `bloom_tex` at full-res and add it to the scene color

This avoids mip chains and multiple render passes — just 2 extra passes (bright + blur).

### 3.4 Application in final composite

In `postprocess.wgsl`'s `fs`, after tone mapping:
```wgsl
let bloom = textureSample(bloom_tex, samp, uv).rgb;
c = c + bloom * bloom_intensity;
```

## 4. Pipeline architecture

### 4.1 New struct: `BloomSsaoPipeline`

```rust
pub struct BloomSsaoPipeline {
    // SSAO
    ssao_pipeline: wgpu::RenderPipeline,
    ssao_blur_pipeline: wgpu::RenderPipeline,
    ao_tex: wgpu::TextureView,       // half-res R16Float
    ao_blur_tex: wgpu::TextureView,  // half-res R16Float (ping-pong)
    ssao_bind_group: wgpu::BindGroup,
    ssao_blur_bind_group: wgpu::BindGroup,
    ssao_kernel_buf: wgpu::Buffer,   // 32 vec3 kernel samples

    // Bloom
    bright_pipeline: wgpu::RenderPipeline,
    blur_h_pipeline: wgpu::RenderPipeline,
    blur_v_pipeline: wgpu::RenderPipeline,
    bright_tex: wgpu::TextureView,   // half-res Rgba16Float
    bloom_tex: wgpu::TextureView,    // half-res Rgba16Float (blurred)
    bright_bind_group: wgpu::BindGroup,
    blur_h_bind_group: wgpu::BindGroup,
    blur_v_bind_group: wgpu::BindGroup,

    // Shared
    sampler: wgpu::Sampler,
    width: u32,
    height: u32,
}
```

### 4.2 Render flow

```
1. Scene render pass (existing, unchanged)
   → color_tex (HDR, full-res) + depth_tex (full-res)

2. SSAO generation pass (new)
   → reads depth_tex, writes ao_tex (half-res)
   → SSAO blur pass reads ao_tex, writes ao_blur_tex (half-res)

3. Bloom bright pass (new)
   → reads color_tex, writes bright_tex (half-res, thresholded)
   → Bloom blur-H pass reads bright_tex, writes bloom_tex (half-res)
   → Bloom blur-V pass reads bloom_tex, writes bright_tex (half-res, ping-pong)

4. Final composite pass (modified postprocess)
   → reads color_tex + depth_copy_tex + normal_tex + ao_blur_tex + bloom_tex
   → writes to swapchain
```

### 4.3 Integration with PostProcessPipeline

The `PostProcessPipeline::process` method currently does one pass. It needs to either:
- Call `BloomSsaoPipeline::process` before its own composite pass, OR
- Be merged into a single `process` method that runs all passes in sequence

**Recommended**: `BloomSsaoPipeline` owns its own passes and is called by the app
between the scene pass and the postprocess composite. The `PostProcessPipeline` is
modified to accept the AO and bloom textures as additional bindings.

### 4.4 Bind group changes

The postprocess bind group currently has 5 bindings (params, color, depth_copy, normal, sampler). It gains 2 more:
- binding 5: `ao_tex` (sampled, filtered)
- binding 6: `bloom_tex` (sampled, filtered)

The postprocess shader reads both and applies them in the final composite.

## 5. Uniforms

### 5.1 SSAO params

```rust
#[repr(C, packed)]
struct SsaoParams {
    inv_view_proj: [[f32; 4]; 4],  // inverse view-projection for depth reconstruction
    resolution: [f32; 2],          // half-res screen size
    texel_size: [f32; 2],          // 1/resolution
    radius: f32,                   // sample radius in view space (tunable)
    intensity: f32,                // AO strength (tunable)
    bias: f32,                     // depth bias to prevent self-occlusion
    kernel_size: u32,              // number of kernel samples (32)
    _pad: [f32; 3],                // align to 16 bytes
}
```

### 5.2 Bloom params

```rust
#[repr(C, packed)]
struct BloomParams {
    resolution: [f32; 2],
    texel_size: [f32; 2],
    threshold: f32,    // luminance threshold for bright pass (tunable, ~1.0)
    knee: f32,         // soft knee for threshold transition (~0.2)
    intensity: f32,    // bloom strength (tunable)
    _pad: [f32; 3],
}
```

## 6. Tunability

Both effects get debug-overlay sliders via `vox-debug`:
- SSAO: intensity (0-2), radius (0.1-2.0)
- Bloom: intensity (0-2), threshold (0.5-3.0)

These join the existing tunable parameters in the F3 debug overlay.

## 7. Testing plan

- **Shader validation**: `cargo test -p vox-render shader_validate` must parse both new WGSL files.
- **Compilation**: `cargo check --workspace` must pass.
- **Visual verification**: Run the engine, confirm:
  - Fire/ember glow with bloom
  - Crevices and under-overhangs darken with SSAO
  - Both effects respond to debug sliders
  - Performance is acceptable (60 FPS at default settings)
- No headless unit tests — screen-space effects are GPU-only.

## 8. Explicitly out of scope

- SSR (screen-space reflections) — separate future task.
- Volumetric fog / god rays — separate future task.
- Multi-cascade shadow mapping — separate future task.
- Deferred rendering / G-buffer restructure — separate future task.
- Motion blur, depth of field — separate future tasks.
- Normal G-buffer for SSAO — depth reconstruction is sufficient for v1.
- Full downsample/upsample bloom chain — the simplified 13-tap blur is sufficient for v1.
