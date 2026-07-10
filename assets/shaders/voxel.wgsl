// Opaque voxel pipeline: chunks and debris bodies share this shader.
// Shading: material palette color + per-vertex jitter hash, directional sun
// with a soft (half-Lambert) terminator, a faint opposite-direction fill
// light, a two-tone sky/ground ambient, baked vertex AO, distance fog.

struct Camera {
    view_proj: mat4x4f,
    cam_pos: vec4f,
    sun_dir: vec4f,          // xyz = sun direction (unit), w = sun strength
    fog: vec4f,              // x = start (m), y = end (m), z = voxel size (m), w = ambient strength
    sky_color: vec4f,        // xyz = sky/fog color, w = fill light strength
    sun_color: vec4f,        // xyz = sun color (linear RGB), w = game time (seconds)
    ambient_sky: vec4f,      // xyz = ambient sky tint, w = unused
    ambient_ground: vec4f,   // xyz = ambient ground tint, w = unused
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
    @location(1) norm_mat: vec4<u32>, // normal id, jitter 0..255, material lo, material hi
};

struct VOut {
    @builtin(position) clip: vec4f,
    @location(0) color: vec3f,
    @location(1) world_normal: vec3f,
    @location(2) ao: f32,
    @location(3) world_pos: vec3f,
};
// All lighting constants are now uniforms (cam.*) for day/night cycle.

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
    var wp = (model * vec4f(local, 1.0)).xyz;

    // Grass sway: displace top-face vertices of grass material (ID 3)
    // with a sin wave based on world XZ + time. Only +Y faces (normal id 2)
    // sway — sides and bottom stay fixed. Amplitude scales with height
    // above the voxel base so the root stays planted.
    let mat_id = v.norm_mat.z | (v.norm_mat.w << 8u);
    let normal_id = v.norm_mat.x;
    if (mat_id == 3u && normal_id == 2u) {
        let t = cam.sun_color.w; // game time
        let phase = wp.x * 0.8 + wp.z * 0.6 + t * 2.0;
        let sway = sin(phase) * 0.03 + sin(phase * 2.3 + 1.0) * 0.015;
        wp.x += sway;
        wp.z += cos(phase * 0.9) * 0.02;
    }


    let base = palette[mat_id];
    // Jitter is baked into the mesh once at build time (see vox-mesh's
    // `jitter_hash`), not recomputed here from world position: hashing a
    // *moving* vertex's world position dynamically made the jitter shift
    // continuously as a debris body translated/rotated, which read as
    // flicker on its surface -- chunks never move, so they never showed it,
    // matching the exact "only on detached bodies" symptom this fixed.
    let h = f32(v.norm_mat.y) / 255.0;

    var out: VOut;
    out.clip = cam.view_proj * vec4f(wp, 1.0);
    out.color = base.rgb * (1.0 + (h - 0.5) * 2.0 * base.a);
    // Chunks never rotate, so their local and world axes coincide -- but a
    // debris body's instance matrix carries real rotation (it tumbles), and
    // lighting a tumbling body against its *local* (un-rotated) face normal
    // makes the lit/shadowed faces stay fixed to the body instead of the
    // world's actual sun direction: it looks like the light is glued to the
    // object and spinning with it. Rotating the normal by the model matrix
    // here (translation-free, via w=0) fixes that for both cases uniformly.
    let local_n = face_normal(v.norm_mat.x);
    out.world_normal = normalize((model * vec4f(local_n, 0.0)).xyz);
    out.ao = f32(v.pos_ao.w) / 3.0;
    out.world_pos = wp;
    return out;
}

@fragment
fn fs(in: VOut) -> @location(0) vec4f {
    let n = normalize(in.world_normal);
    let ndotl = dot(n, -cam.sun_dir.xyz);
    // Half-Lambert wrap: softens the sun terminator into a gradient.
    let sun = pow(clamp(ndotl * 0.5 + 0.5, 0.0, 1.0), 1.5) * cam.sun_dir.w * cam.sun_color.xyz;
    let fill = max(-ndotl, 0.0) * cam.sky_color.w;

    let hemi_t = clamp(0.5 + 0.5 * n.y, 0.0, 1.0);
    let ambient = mix(cam.ambient_ground.xyz, cam.ambient_sky.xyz, hemi_t) * cam.fog.w;

    let ao = 0.45 + 0.55 * in.ao;
    var c = in.color * (ambient + sun + vec3f(fill)) * ao;

    let dist = length(in.world_pos - cam.cam_pos.xyz);
    let f = clamp((dist - cam.fog.x) / (cam.fog.y - cam.fog.x), 0.0, 1.0);
    c = mix(c, cam.sky_color.xyz, f * f);
    return vec4f(c, 1.0);
}
