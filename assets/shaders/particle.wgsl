// Camera-facing billboard particles: one instanced quad per particle, soft
// circular falloff in the fragment shader, alpha-blended.
//
// Soft particles (#70): the fragment shader reads the scene depth texture
// and fades alpha to zero as the particle fragment approaches the scene
// surface behind it, eliminating hard-cut intersections with terrain.
// The particle pass has NO depth attachment — the depth texture is bound
// as a sampled resource, and both the behind-terrain occlusion test and
// the soft fade are done manually in the shader via textureLoad.

struct Camera {
    view_proj: mat4x4f,
    right: vec4f, // xyz = camera right (unit)
    up: vec4f,    // xyz = camera up (unit)
};

@group(0) @binding(0) var<uniform> cam: Camera;
@group(0) @binding(1) var scene_depth: texture_depth_2d;

// Depth range (in NDC 0..1) over which a particle fades when it meets the
// scene surface. Must match the Rust-side _SOFT_FADE_RANGE constant.
const SOFT_FADE_RANGE: f32 = 0.02;

struct Inst {
    @location(0) center_size: vec4f, // xyz = world center (m), w = half-size (m)
    @location(1) color: vec4f,       // premultiplied nothing -- straight rgba
};

struct VOut {
    @builtin(position) clip: vec4f,
    @location(0) color: vec4f,
    @location(1) corner: vec2f, // -1..1 across the quad
};

// Two triangles of a unit quad, indexed by vertex_index 0..6.
fn corner_of(i: u32) -> vec2f {
    switch i {
        case 0u: { return vec2f(-1.0, -1.0); }
        case 1u: { return vec2f(1.0, -1.0); }
        case 2u: { return vec2f(1.0, 1.0); }
        case 3u: { return vec2f(-1.0, -1.0); }
        case 4u: { return vec2f(1.0, 1.0); }
        default: { return vec2f(-1.0, 1.0); }
    }
}

@vertex
fn vs(@builtin(vertex_index) vi: u32, inst: Inst) -> VOut {
    let c = corner_of(vi);
    let half = inst.center_size.w;
    let world = inst.center_size.xyz
        + cam.right.xyz * (c.x * half)
        + cam.up.xyz * (c.y * half);

    var out: VOut;
    out.clip = cam.view_proj * vec4f(world, 1.0);
    out.color = inst.color;
    out.corner = c;
    return out;
}

@fragment
fn fs(in: VOut) -> @location(0) vec4f {
    // Soft round sprite: opaque-ish core, feathered edge, nothing outside
    // the inscribed circle.
    let d = length(in.corner);
    let a = in.color.a * (1.0 - smoothstep(0.55, 1.0, d));
    if a <= 0.003 {
        discard;
    }

    // Soft particle fade + behind-terrain test (#70): read the scene depth
    // at this fragment's pixel and compare it to the particle's NDC depth.
    // The engine uses standard NDC (0=near, 1=far, clear=1.0, LessEqual),
    // NOT reverse-Z. A particle well in front of terrain has
    // particleDepth < sceneDepth, so softness → 1 (fully visible). As the
    // particle sinks into the surface the gap shrinks to zero and softness
    // → 0 (fades out). A particle fully behind terrain (particleDepth >
    // sceneDepth) is discarded entirely — the old hardware depth_compare
    // LessEqual behavior, now done in-shader since the particle pass has no
    // depth attachment.
    //
    // `in.clip.xy` is the fragment's pixel coordinate (the @builtin(position)
    // in a fragment input is the pixel-center position, not interpolated).
    let texel = vec2i(in.clip.xy);
    let scene_depth_val = textureLoad(scene_depth, texel, 0);
    let particle_depth = in.clip.z;

    // Behind terrain — discard (replaces the old hardware depth test).
    // Use step() instead of > comparison (naga doesn't support > on
    // depth texture samples). step(a, b) = 1.0 if b >= a, 0.0 if b < a.
    // behind = step(scene_depth_val, particle_depth) — 1.0 if particle is behind.
    let behind = step(scene_depth_val, particle_depth);
    if behind > 0.5 {
        discard;
    }

    // Intersection fade: 1 when well in front, 0 at the surface.
    let softness = clamp((scene_depth_val - particle_depth) / SOFT_FADE_RANGE, 0.0, 1.0);

    return vec4f(in.color.rgb, a * softness);
}
