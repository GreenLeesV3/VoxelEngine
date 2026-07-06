// Opaque voxel pipeline: chunks and debris bodies share this shader.
// Shading: material palette color + per-vertex jitter hash, directional sun,
// hemisphere ambient, baked vertex AO, distance fog.

struct Camera {
    view_proj: mat4x4f,
    cam_pos: vec4f,
    sun_dir: vec4f,          // xyz = direction the sun shines toward (unit)
    fog: vec4f,              // x = start (m), y = end (m), z = voxel size (m)
};

@group(0) @binding(0) var<uniform> cam: Camera;
@group(0) @binding(1) var<storage, read> palette: array<vec4f>; // rgb + jitter

struct Inst {
    @location(4) m0: vec4f,
    @location(5) m1: vec4f,
    @location(6) m2: vec4f,
    @location(7) m3: vec4f,
};

struct VIn {
    @location(0) pos_ao: vec4<u32>,   // x, y, z corner (voxel units), ao 0..3
    @location(1) norm_mat: vec4<u32>, // normal id, pad, material lo, material hi
};

struct VOut {
    @builtin(position) clip: vec4f,
    @location(0) color: vec3f,
    @location(1) @interpolate(flat) normal_id: u32,
    @location(2) ao: f32,
    @location(3) world_pos: vec3f,
};

const SKY_COLOR = vec3f(0.45, 0.66, 0.90);

// Face normal from id (0..6 = +X, -X, +Y, -Y, +Z, -Z). Arithmetic instead of
// a const-array lookup: naga rejects dynamic indexing of module constants.
fn face_normal(id: u32) -> vec3f {
    let s = 1.0 - 2.0 * f32(id & 1u);
    let axis = id >> 1u;
    var n = vec3f(0.0, 0.0, 0.0);
    if axis == 0u {
        n.x = s;
    } else if axis == 1u {
        n.y = s;
    } else {
        n.z = s;
    }
    return n;
}

@vertex
fn vs(v: VIn, inst: Inst) -> VOut {
    let model = mat4x4f(inst.m0, inst.m1, inst.m2, inst.m3);
    let local = vec3f(f32(v.pos_ao.x), f32(v.pos_ao.y), f32(v.pos_ao.z)) * cam.fog.z;
    let wp = (model * vec4f(local, 1.0)).xyz;

    let mat_id = v.norm_mat.z | (v.norm_mat.w << 8u);
    let base = palette[mat_id];
    // Deterministic per-corner jitter; shared corners agree across quads.
    let cell = floor(wp / cam.fog.z + vec3f(0.5));
    let h = fract(sin(dot(cell, vec3f(12.9898, 78.233, 37.719))) * 43758.547);

    var out: VOut;
    out.clip = cam.view_proj * vec4f(wp, 1.0);
    out.color = base.rgb * (1.0 + (h - 0.5) * 2.0 * base.a);
    out.normal_id = v.norm_mat.x;
    out.ao = f32(v.pos_ao.w) / 3.0;
    out.world_pos = wp;
    return out;
}

@fragment
fn fs(in: VOut) -> @location(0) vec4f {
    let n = face_normal(in.normal_id);
    let sun = max(dot(n, -cam.sun_dir.xyz), 0.0);
    let hemi = 0.5 + 0.5 * n.y;
    let ao = 0.35 + 0.65 * in.ao;
    var c = in.color * (0.28 * hemi + 0.75 * sun) * ao;

    let dist = length(in.world_pos - cam.cam_pos.xyz);
    let f = clamp((dist - cam.fog.x) / (cam.fog.y - cam.fog.x), 0.0, 1.0);
    c = mix(c, SKY_COLOR, f * f);
    return vec4f(c, 1.0);
}
