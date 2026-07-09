// Camera-facing billboard particles: one instanced quad per particle, soft
// circular falloff in the fragment shader, alpha-blended, depth-tested but
// not depth-written (particles never occlude the world or each other).

struct Camera {
    view_proj: mat4x4f,
    right: vec4f, // xyz = camera right (unit)
    up: vec4f,    // xyz = camera up (unit)
};

@group(0) @binding(0) var<uniform> cam: Camera;

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
    return vec4f(in.color.rgb, a);
}
