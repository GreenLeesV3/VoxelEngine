// Grass blade pipeline: renders thin 3D blades baked into chunk meshes.
// Each blade is a double-sided quad with wind sway applied to the tip
// in the vertex shader (CazToon-style patch wind). Alpha-tested, depth-tested.
// Lighting matches the voxel pipeline for day/night consistency.

struct Camera {
    view_proj: mat4x4f,
    cam_pos: vec4f,
    sun_dir: vec4f,          // xyz = sun direction, w = sun strength
    fog: vec4f,              // x = start, y = end, z = voxel size, w = ambient strength
    sky_color: vec4f,        // xyz = sky/fog color, w = fill strength
    sun_color: vec4f,        // xyz = sun color, w = game time
    ambient_sky: vec4f,      // xyz = ambient sky tint, w = unused
    ambient_ground: vec4f,   // xyz = ambient ground tint, w = unused
};

@group(0) @binding(0) var<uniform> cam: Camera;

// Instance transform comes via vertex buffer slot 1 (mat4 split into
// 4 vec4s at locations 4-7), same as the voxel pipeline.



struct VIn {
    @location(0) pos: vec3f,         // voxel-unit position relative to chunk origin
    @location(1) height_factor: f32, // 0=base, 1=tip — drives wind + color
    @location(4) instance_col0: vec4f,
    @location(5) instance_col1: vec4f,
    @location(6) instance_col2: vec4f,
    @location(7) instance_col3: vec4f,
};

struct VOut {
    @builtin(position) clip: vec4f,
    @location(0) height_factor: f32,
    @location(1) world_pos: vec3f,
};

// --- CazToon wind displacement (simplified from v6352ws3pq.glsl) ---
// Patch-based wind: bilinear-interpolated wind vectors per 6-block patch,
// plus gust events and turbulence. Scaled down for voxel-engine units.

fn wind_hash21(p: vec2f) -> f32 {
    var v = fract(p * vec2f(0.1031, 0.1030));
    v = v + dot(v, v.yx + 33.33);
    return fract((v.x + v.y) * v.x);
}

fn sample_patch_wind(patch_id: vec2f, t: f32) -> vec2f {
    let speed_hash = wind_hash21(patch_id + vec2f(67.3, 29.1));
    var speed_mult = 0.2;
    if speed_hash > 0.75 { speed_mult = 1.0; }
    else if speed_hash > 0.50 { speed_mult = 0.7; }
    else if speed_hash > 0.25 { speed_mult = 0.5; }
    let tt = t * speed_mult;

    let base_mag = 0.8 + 0.2 * wind_hash21(patch_id + vec2f(5.1, 2.3));
    let patch_phase = wind_hash21(patch_id + vec2f(41.3, 11.9)) * 6.28318;
    let t_local = tt + patch_phase;

    let ph0 = wind_hash21(patch_id + vec2f(77.0, 13.0)) * 6.28318;
    let ph1 = wind_hash21(patch_id + vec2f(19.0, 57.0)) * 6.28318;
    let ph2 = wind_hash21(patch_id + vec2f(91.0, 31.0)) * 6.28318;
    let ph3 = wind_hash21(patch_id + vec2f(43.0, 71.0)) * 6.28318;
    let ph4 = wind_hash21(patch_id + vec2f(11.0, 97.0)) * 6.28318;
    let ph5 = wind_hash21(patch_id + vec2f(59.0, 23.0)) * 6.28318;

    var dir_vec = vec2f(
        sin(t_local * 0.37 + ph0) + 0.55 * sin(t_local * 0.91 + ph1) + 0.25 * sin(t_local * 1.63 + ph2),
        cos(t_local * 0.33 + ph3) + 0.50 * cos(t_local * 0.79 + ph4) + 0.22 * cos(t_local * 1.47 + ph5),
    );
    let dir_len = max(length(dir_vec), 0.0001);
    let dir = dir_vec / dir_len;

    let mag_pulse = 0.88
        + 0.10 * sin(t_local * 0.41 + ph1)
        + 0.06 * sin(t_local * 1.07 + ph4);
    let mag = base_mag * clamp(mag_pulse, 0.72, 1.08);
    return dir * mag;
}

fn get_wind_displacement(world_xz: vec2f, time: f32) -> vec3f {
    let GRASS_WIND_SPEED = 1.0;
    let GRASS_WAVING_INTENSITY = 0.15; // scaled for voxel units
    let PATCH_SIZE = 6.0;
    let AMPLITUDE = 0.15;

    let t = time * GRASS_WIND_SPEED * 3.9;

    let fp = world_xz / PATCH_SIZE;
    let base = floor(fp);
    let f = smoothstep(vec2f(0.0), vec2f(1.0), fp - base);

    let w00 = sample_patch_wind(base + vec2f(0.0, 0.0), t);
    let w10 = sample_patch_wind(base + vec2f(1.0, 0.0), t);
    let w01 = sample_patch_wind(base + vec2f(0.0, 1.0), t);
    let w11 = sample_patch_wind(base + vec2f(1.0, 1.0), t);

    let w0 = mix(w00, w10, f.x);
    let w1 = mix(w01, w11, f.x);
    let total = mix(w0, w1, f.y) * AMPLITUDE;
    let y_bob = sin(t * 7.0 + world_xz.x * 0.3 + world_xz.y * 0.3) * 0.02 * length(total);
    let stretch = sin(t * 2.3 + world_xz.x * 0.2 + world_xz.y * 0.2) * 0.04 * length(total);

    return vec3f(total.x, stretch + y_bob, total.y) * GRASS_WAVING_INTENSITY;
}

@vertex
fn vs_main(in: VIn) -> VOut {
    var out: VOut;

    // Reconstruct instance matrix from vertex attributes (chunk origin transform).
    let instance = mat4x4f(in.instance_col0, in.instance_col1, in.instance_col2, in.instance_col3);
    let voxel_size = cam.fog.z;
    var local_pos = in.pos * voxel_size;
    let world_pos = (instance * vec4f(local_pos, 1.0)).xyz;

    // Wind sway only on tips (height_factor > 0).
    var final_pos = world_pos;
    if (in.height_factor > 0.5) {
        let wind = get_wind_displacement(world_pos.xz, cam.sun_color.w);
        final_pos = final_pos + wind * in.height_factor;
    }

    out.clip = cam.view_proj * vec4f(final_pos, 1.0);
    out.height_factor = in.height_factor;
    out.world_pos = final_pos;
    return out;
}

struct GrassFOut {
    @location(0) color: vec4f,
    @location(1) normal: vec4f,
    @location(2) linear_depth: vec4f,
};

@fragment
fn fs_main(in: VOut) -> GrassFOut {
    // Color gradient: match the voxel grass palette (material 3).
    let base_green = vec3f(0.20, 0.35, 0.15);
    let tip_green = vec3f(0.33, 0.55, 0.25);
    let color = mix(base_green, tip_green, in.height_factor);

    // Sky-tinted lighting matching voxel.wgsl (CazToon-style).
    let sky_tint = normalize(cam.sky_color.xyz + vec3f(0.001));
    let lit_tint = normalize(mix(vec3f(1.0), sky_tint, 0.35));
    let shadow_tint = normalize(mix(vec3f(0.5), sky_tint, 0.45));
    let ambient = cam.ambient_sky.xyz * shadow_tint * cam.fog.w;
    let ndotl = dot(vec3f(0.0, 1.0, 0.0), cam.sun_dir.xyz);
    let raw = clamp(ndotl * 0.5 + 0.5, 0.0, 1.0);
    let bands = 4.0;
    let quantized = floor(raw * bands + 0.5) / bands;
    let smooth_q = mix(quantized, raw, smoothstep(0.45, 0.55, fract(raw * bands)));
    let sun = pow(smooth_q, 1.5) * cam.sun_dir.w * cam.sun_color.xyz * lit_tint;
    let fill = max(-ndotl, 0.0) * cam.sky_color.w;
    let lit = color * (ambient + sun + vec3f(fill));

    // Distance fog — matches the voxel pipeline.
    let dist = length(cam.cam_pos.xyz - in.world_pos);
    let f = clamp((dist - cam.fog.x) / (cam.fog.y - cam.fog.x), 0.0, 1.0);
    let final_color = mix(lit, cam.sky_color.xyz, f * f);

    // Distance fade: fade out grass beyond ~60m to hide the draw radius cutoff.
    let grass_fade = 1.0 - smoothstep(40.0, 60.0, dist);

    // Discard faded blades so they don't write depth (prevents holes in water).
    if grass_fade < 0.01 { discard; }

    var out: GrassFOut;
    out.color = vec4f(final_color, grass_fade);
    out.normal = vec4f(0.0, 1.0, 0.0, 1.0);
    out.linear_depth = vec4f(dist / 600.0, 0.0, 0.0, 0.0);
    return out;
}
