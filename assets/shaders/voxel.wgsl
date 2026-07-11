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
    ambient_sky: vec4f,      // xyz = ambient sky tint, w = crack decal intensity (0 = off)
    ambient_ground: vec4f,   // xyz = ambient ground tint, w = unused
};

@group(0) @binding(0) var<uniform> cam: Camera;
@group(0) @binding(1) var<storage, read> palette: array<vec4f>; // rgb + jitter
@group(0) @binding(2) var<storage, read> emissive: array<vec4f>; // xyz = emissive color, w = intensity (w < 0 = not emissive)
@group(0) @binding(3) var<storage, read> pbr_params: array<vec4f>; // x = roughness, y = metalness, z/w unused
// Shadow camera uniform, must match `shadow.wgsl`'s `ShadowCam`.
struct ShadowCam {
    view_proj: mat4x4f,
    params: vec4f,  // x = voxel_size_m; y/z/w unused
};

@group(1) @binding(0) var<uniform> shadow_cam: ShadowCam;
@group(1) @binding(1) var shadow_map: texture_depth_2d;
@group(1) @binding(2) var shadow_sampler: sampler_comparison;

struct Inst {
    @location(4) m0: vec4f,
    @location(5) m1: vec4f,
    @location(6) m2: vec4f,
    @location(7) m3: vec4f,
};

struct VIn {
    @location(0) pos_ao: vec4<u32>,   // x, y, z corner (voxel units), w = packed AO(0-3) | skylight(<<4)
    @location(1) norm_mat: vec4<u32>, // normal id (low nibble) | blocklight (high nibble), jitter 0..255, material lo, material hi
};

struct VOut {
    @builtin(position) clip: vec4f,
    @location(0) color: vec3f,
    @location(1) world_normal: vec3f,
    // Packed in the low byte: bits 0-1 = corner AO (0..3), bits 4-7 =
    // skylight (0..=15). Unpacked in the fragment shader.
    @location(2) ao: f32,
    @location(3) world_pos: vec3f,
    @location(4) @interpolate(flat) mat_id: u32,
    // Blocklight level (0..=15), passed flat to the fragment shader for
    // the warm orange emissive-light contribution.
    @location(5) @interpolate(flat) blocklight: u32,
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

// --- Procedural crack decals (#43) ---
// Pure-visual crack overlay driven by cam.ambient_sky.w (crack_intensity).
// Not tied to real damage state yet; intensity is 0 by default so the
// pattern is invisible until a future change drives it from per-voxel damage.
// Branching dark lines are built from a hash of world position: several
// ridges at different frequencies + offsets are combined, and only the
// sharpest crests read as cracks.

// Integer hash -> [0,1). Used to seed per-cell crack jitter so the pattern
// isn't a perfectly regular grid of lines.
fn hash13(x: i32, y: i32, z: i32) -> f32 {
    var h = bitcast<u32>(x) * 374761393u + bitcast<u32>(y) * 668265263u + bitcast<u32>(z) * 2147483647u;
    h = (h ^ (h >> 13u)) * 1274126177u;
    h = h ^ (h >> 16u);
    return f32(h) / 4294967296.0;
}

// One crack ridge: a high-frequency sin field whose near-zero crossings form
// a thin line. Returns ~1 near a line, ~0 elsewhere. `freq` sets line
// spacing, `width` sets line thickness, `off` shifts the grid per cell so
// ridges at different frequencies don't align into a single pattern.
fn crack_ridge(p: vec3f, freq: f32, width: f32, off: f32) -> f32 {
    let v = sin(p.x * freq + off) * 1.7 + sin(p.y * freq * 1.3 + off * 2.1) * 1.3 + sin(p.z * freq * 0.9 + off * 0.7) * 1.1;
    // Ridge: peak at v≈0, decays smoothly. width controls falloff.
    return 1.0 - smoothstep(0.0, width, abs(v));
}

// Combined crack intensity in [0,1]. `p` must be in VOXEL-space (world_pos
// divided by voxel size) so the pattern is scale-invariant. Three ridges of
// decreasing frequency (~1-2 crossings per voxel face) layered for a
// branching feel, plus a per-voxel-cell hash gate so not every voxel cracks.
fn crack_factor(p: vec3f) -> f32 {
    let cell = vec3<i32>(floor(p));
    let gate = hash13(cell.x, cell.y, cell.z);
    // Only ~60% of voxels get cracks; the rest stay clean.
    if (gate < 0.4) {
        return 0.0;
    }
    let r1 = crack_ridge(p, 2.2, 0.20, gate * 6.28);
    let r2 = crack_ridge(p, 3.7, 0.14, gate * 12.4);
    let r3 = crack_ridge(p, 5.5, 0.10, gate * 3.7);
    // Sharpen: cracks are thin, so take a max-ish combination but keep the
    // strongest ridge dominant to avoid a flat noisy overlay.
    let m = max(r1, max(r2, r3));
    return clamp(m, 0.0, 1.0);
}

// --- Shadow mapping (#14) ---
// PCF 3x3 sampling of the directional shadow map. Returns a visibility
// factor in [0,1]: 1.0 = fully lit, 0.0 = fully shadowed. The comparison
// sampler (sampler_comparison with LessEqual) returns 1.0 when the
// fragment's depth is <= the stored depth, i.e. the fragment is closer to
// the light and thus lit.
//
// A constant receiver bias (in clip-space depth units) is subtracted from
// the fragment depth before the comparison to fight shadow acne on
// surfaces that face the sun nearly head-on. The shadow pipeline also
// applies a constant + slope-scaled depth bias on the *writer* side; the
// receiver bias here is the second line of defense.
fn shadow_visibility(world_pos: vec3f) -> f32 {
    let clip = shadow_cam.view_proj * vec4f(world_pos, 1.0);
    // Outside the shadow camera's near/far or clip box: treat as lit so we
    // don't black out terrain beyond the 100 m shadow extent.
    if (clip.w <= 0.0) {
        return 1.0;
    }
    let ndc = clip.xyz / clip.w;
    // NDC outside [-1,1]: beyond the orthographic box -- lit.
    if (abs(ndc.x) > 1.0 || abs(ndc.y) > 1.0 || ndc.z > 1.0 || ndc.z < 0.0) {
        return 1.0;
    }
    // Convert to shadow-map UV (flip Y: WGSL texture coords have origin at
    // the top-left, NDC y=+1 is the top of the viewport).
    let uv = vec2f(ndc.x * 0.5 + 0.5, ndc.y * -0.5 + 0.5);
    // Depth the fragment *would* write to the shadow map, biased to avoid
    // self-shadowing (acne). 0.001 was tuned for a 100 m ortho box at
    // 2048x2048 with the writer-side bias of constant 1 / slope 1.5.
    let ref_depth = ndc.z - 0.001;

    // PCF 3x3: sample the comparison sampler at 9 offsets, average the
    // result. texel size is 1/2048.
    let texel = 1.0 / 2048.0;
    var sum = 0.0;
    for (var y = -1; y <= 1; y = y + 1) {
        for (var x = -1; x <= 1; x = x + 1) {
            let offset = vec2f(f32(x), f32(y)) * texel;
            sum += textureSampleCompareLevel(shadow_map, shadow_sampler, uv + offset, ref_depth);
        }
    }
    return sum / 9.0;
}

@vertex
fn vs(v: VIn, inst: Inst) -> VOut {
    let model = mat4x4f(inst.m0, inst.m1, inst.m2, inst.m3);
    let local = vec3f(f32(v.pos_ao.x), f32(v.pos_ao.y), f32(v.pos_ao.z)) * cam.fog.z;
    var wp = (model * vec4f(local, 1.0)).xyz;

    let mat_id = v.norm_mat.z | (v.norm_mat.w << 8u);

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
    out.ao = f32(v.pos_ao.w);  // packed AO + skylight byte
    let packed_norm = v.norm_mat.x;
    let local_n = face_normal(packed_norm & 0x0Fu);
    out.world_normal = normalize((model * vec4f(local_n, 0.0)).xyz);
    out.world_pos = wp;
    out.mat_id = mat_id;
    out.blocklight = (packed_norm >> 4u) & 0x0Fu;
    return out;
}

// --- PBR specular (GGX) ---
// Only materials whose pbr_params has roughness < 1.0 or metalness > 0.0
// get this specular term; the rest keep the cel-shaded Lambert diffuse.
// Microfacet model: D = GGX/Trowbridge-Reitz NDF, F = Schlick Fresnel,
// G = Smith geometric shadowing, combined as D*F*G / (4 * n·v * n·l).

fn d_ggx(noth: f32, a: f32) -> f32 {
    let a2 = a * a;
    let denom = noth * noth * (a2 - 1.0) + 1.0;
    return a2 / (3.14159265 * denom * denom + 0.0001);
}

fn f_schlick(ct: f32, f0: vec3f) -> vec3f {
    return f0 + (1.0 - f0) * pow(1.0 - ct, 5.0);
}

fn g_smith(nov: f32, nol: f32, a: f32) -> f32 {
    let a2 = a * a;
    let gv = nov / (nov * (1.0 - a2) + a2 + 0.0001);
    let gl = nol / (nol * (1.0 - a2) + a2 + 0.0001);
    return gv * gl;
}

// Specialization constant: 0 = opaque pass (skip water), 1 = water pass
// (skip non-water). Two pipelines share this shader; the opaque pipeline
// has depth_write_enabled=true, the water pipeline has it false so terrain
// behind water is not depth-culled.
override water_pass: u32 = 0u;

struct FOut {
    @location(0) color: vec4f,
    @location(1) normal: vec4f,       // xyz = world normal, w = 1
    @location(2) linear_depth: vec4f, // x = linear depth (0..1), yzw = unused
};

@fragment
fn fs(in: VOut) -> FOut {
    // Pass selection: each pipeline variant only draws its own materials.
    if (water_pass == 0u && in.mat_id == 9u) { discard; }
    if (water_pass == 1u && in.mat_id != 9u) { discard; }

    // Emissive materials (fire, ember, lava): render at full brightness,
    // skipping sun/shadow/ambient/AO so they glow regardless of time of day
    // or occlusion. `in.color` already carries base rgb * jitter factor, so
    // we tint with the emissive color and scale by intensity. Fog is still
    // applied so distant emissive voxels fade into the sky correctly.
    let emi = emissive[in.mat_id];
    if (emi.w >= 0.0) {
        var ec = in.color * emi.xyz * emi.w;
        let dist = length(in.world_pos - cam.cam_pos.xyz);
        let f = clamp((dist - cam.fog.x) / (cam.fog.y - cam.fog.x), 0.0, 1.0);
        ec = mix(ec, cam.sky_color.xyz, f * f);
        var out: FOut;
        out.color = vec4f(ec, 1.0);
        out.normal = vec4f(normalize(in.world_normal), 1.0);
        out.linear_depth = vec4f(dist / 600.0, 0.0, 0.0, 0.0);
        return out;
    }

    let n = normalize(in.world_normal);
    let ndotl = dot(n, cam.sun_dir.xyz);
    // Half-Lambert wrap: softens the sun terminator into a gradient.
    let raw = clamp(ndotl * 0.5 + 0.5, 0.0, 1.0);
    // Cel-shading: quantize into 4 bands with smooth transitions for a
    // painterly, comic-book look (design doc §3).
    let bands = 4.0;
    let quantized = floor(raw * bands + 0.5) / bands;
    let smooth_q = mix(quantized, raw, smoothstep(0.45, 0.55, fract(raw * bands)));

    // Per-face shade (CazToon-style): each face direction gets a fixed
    // brightness multiplier for a crisp, directional block look.
    // bottom=0.5, top=1.0, north/south=0.8, east/west=0.6
    let abs_n = abs(n);
    var face_shade: f32 = 0.8; // default for Z faces
    if (abs_n.y > abs_n.x && abs_n.y > abs_n.z) {
        face_shade = select(0.5, 1.0, n.y > 0.0); // bottom=0.5, top=1.0
    } else if (abs_n.x > abs_n.z) {
        face_shade = 0.6; // east/west
    } else {
        face_shade = 0.8; // north/south
    }

    // Sky-tinted lighting (CazToon-style): tint both lit and shadow
    // terms by the current sky color so terrain takes on the sky's
    // color temperature — warm at sunset, cool blue at noon, dim at night.
    let sky_tint = normalize(cam.sky_color.xyz + vec3f(0.001));
    let lit_tint = normalize(mix(vec3f(1.0), sky_tint, 0.35));
    let shadow_tint = normalize(mix(vec3f(0.5), sky_tint, 0.45));

    var sun = pow(smooth_q, 1.5) * cam.sun_dir.w * cam.sun_color.xyz * lit_tint;
    let fill = max(-ndotl, 0.0) * cam.sky_color.w;

    // Shadow visibility for the fragment, fetched once and reused by both the
    // diffuse sun attenuation below and the PBR specular term further down.
    // 1.0 = fully lit; <1.0 = occluded. Water (mat 9) skips the fetch and
    // stays 1.0 — water specular is not shadow-attenuated, which is fine for
    // a translucent surface.
    var vis: f32 = 1.0;
    // Shadow mapping (#14): sample the directional shadow map and attenuate
    // direct sunlight by ~50% on occluded fragments. At night (sun_strength
    // ~0) the sun term is already zero, so skip the texture fetch entirely.
    if (cam.sun_dir.w > 0.0 && in.mat_id != 9u) {
        vis = shadow_visibility(in.world_pos);
        sun = sun * mix(0.5, 1.0, vis);
    }

    let hemi_t = clamp(0.5 + 0.5 * n.y, 0.0, 1.0);
    // Ambient uses sky tint: shadow areas get sky-colored ambient (not flat gray)
    var ambient = mix(cam.ambient_ground.xyz, cam.ambient_sky.xyz * shadow_tint, hemi_t) * cam.fog.w;

    // Unpack AO (bits 0-1, 0..3) and skylight (bits 4-7, 0..=15) from the
    // packed vertex byte. Skylight attenuates ambient so enclosed/underground
    // voxels are dimmer than open-sky ones, with a floor so they're not black.
    let ao_raw = u32(in.ao);
    let ao = 0.45 + 0.55 * (f32(ao_raw & 3u) / 3.0);
    let skylight = f32((ao_raw >> 4u) & 15u) / 15.0;
    ambient = ambient * mix(0.3, 1.0, skylight);

    // Apply per-face shade: multiply final lit color by face brightness
    var c = in.color * (ambient + sun + vec3f(fill)) * ao * mix(1.0, face_shade, cam.sun_dir.w);
    // Blocklight: warm orange contribution from emissive sources (fire,
    // ember, lava) propagated through air by the mesher's BFS. Quadratic
    // falloff so the glow concentrates near sources and fades naturally.
    // Added before fog so distant lit voxels still fade into the sky.
    let bl = f32(in.blocklight) / 15.0;
    if (bl > 0.0) {
        let bl_falloff = bl * bl;
        c += in.color * vec3f(1.0, 0.9, 0.8) * bl_falloff;
    }

    // PBR specular (GGX): for materials flagged as PBR (roughness < 1.0 or
    // metalness > 0.0), add a microfacet specular highlight on top of the
    // cel-shaded diffuse. Metals (metalness=1) replace the diffuse tint with
    // specular; dielectrics (metalness=0) keep diffuse and add a bright
    // highlight. Shadow attenuation is applied so occluded PBR surfaces
    // don't sparkle through walls. Skipped at night (no sun) or for water.
    let pbr = pbr_params[in.mat_id];
    let is_pbr = pbr.x < 0.999 || pbr.y > 0.001;
    if (is_pbr && cam.sun_dir.w > 0.0 && in.mat_id != 9u) {
        let roughness = pbr.x;
        let metalness = pbr.y;
        let v = normalize(cam.cam_pos.xyz - in.world_pos);
        let l = cam.sun_dir.xyz;
        let h = normalize(v + l);
        let nov = max(dot(n, v), 0.0);
        let nol = max(dot(n, l), 0.0);
        let noh = max(dot(n, h), 0.0);
        let loh = max(dot(l, h), 0.0);

        let f0 = mix(vec3f(0.04), in.color, metalness);
        let f = f_schlick(loh, f0);
        let d = d_ggx(noh, roughness);
        let g = g_smith(nov, nol, roughness);

        let specular = (d * g / (4.0 * nov * nol + 0.0001)) * f * cam.sun_dir.w * cam.sun_color.xyz;
        // Shadow attenuation: reuse the `vis` fetched above so specular
        // respects occlusion the same way diffuse does (no second fetch).
        c = c * (1.0 - metalness) + specular * mix(0.5, 1.0, vis);
    }


    // Procedural crack decals (#43): dark branching lines on solid voxels,
    // driven by cam.ambient_sky.w. Intensity 0 => no cracks (clean multiply
    // by 0). Water (mat 9) is skipped — cracks belong on solid terrain.
    // Applied to lit color before fog so distant cracked voxels still fog.
    if (cam.ambient_sky.w > 0.0 && in.mat_id != 9u) {
        let k = crack_factor(in.world_pos / cam.fog.z) * cam.ambient_sky.w;
        c = mix(c, vec3f(0.05, 0.04, 0.03), clamp(k, 0.0, 1.0) * 0.55);
    }

    let dist = length(in.world_pos - cam.cam_pos.xyz);
    let f = clamp((dist - cam.fog.x) / (cam.fog.y - cam.fog.x), 0.0, 1.0);
    c = mix(c, cam.sky_color.xyz, f * f);
    // Water (material ID 9): semi-transparent with a subtle refraction ripple
    // that perturbs the fog mix slightly via a sin wave on world XZ + time.
    let alpha = select(1.0, 0.85, in.mat_id == 9u);
    if (in.mat_id == 9u) {
        let t = cam.sun_color.w;
        let ripple = sin(in.world_pos.x * 3.0 + t * 2.0) * 0.5 + sin(in.world_pos.z * 2.3 + t * 1.7) * 0.5;
        c = mix(c, cam.sky_color.xyz, clamp(f * f + ripple * 0.04, 0.0, 1.0));
        // Blue tint — scaled by sun strength so water dims at night
        let night_factor = 0.15 + 0.85 * cam.sun_dir.w;
        c = mix(c, vec3f(0.12, 0.28, 0.50) * night_factor, 0.30);
    }

    // MRT outputs: normal + linear depth for postprocess (SSR, edge detection).
    // linear_depth.y = reflectivity (0 = matte, 1 = mirror) so SSR can skip
    // non-reflective surfaces without needing the PBR buffer.
    var out: FOut;
    out.color = vec4f(c, alpha);
    out.normal = vec4f(normalize(in.world_normal), 1.0);
    let pbr = pbr_params[in.mat_id];
    let reflectivity = (1.0 - pbr.x) * max(pbr.y, 0.04);
    out.linear_depth = vec4f(dist / 600.0, reflectivity, 0.0, 0.0);
    return out;
}
