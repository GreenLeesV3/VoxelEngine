// Procedural sky dome rendered as a fullscreen triangle before the scene.
// Uses Rayleigh + Mie scattering approximation driven by the day/night
// sun direction. Outputs sky color + sun disc + moon + stars + nebula +
// 3D volumetric clouds.
//
// Night features ported from CazToon's sky_night_features.glsl:
// - Cube-face projected star grid with hash-based density, twinkle, size variation
// - Shooting stars (3 slots, periodic, trail rendering)
// - Night nebula (3D FBM noise, two-color blend, drift)
// - Moon disc opposite the sun with soft glow
//
// Volumetric clouds ported from CazToon's volumetric_clouds.glsl:
// - 3D FBM noise density with height-varying cloud base
// - Light optical depth march toward sun for self-shadowing
// - Day/sunset/night lit+shadow coloring
// - LOD erosion detail, distance fade, edge glow

struct SkyCam {
    view_proj: mat4x4f,
    cam_pos: vec4f,      // xyz = cam pos, w = tan(fov_y / 2)
    sun_dir: vec4f,      // xyz = sun direction (unit), w = sun strength
    sky_color: vec4f,    // xyz = sky/fog color, w = aspect ratio
    zenith_color: vec4f, // xyz = zenith color (distinct hue), w = unused
    sun_color: vec4f,    // xyz = sun color, w = game time
    cam_forward: vec4f,  // xyz = camera forward (unit)
    cam_right: vec4f,    // xyz = camera right (unit)
    cam_up: vec4f,       // xyz = camera up (unit)
};
@group(0) @binding(0) var<uniform> cam: SkyCam;

struct VOut {
    @builtin(position) clip: vec4f,
    @location(0) ndc: vec2f,  // screen-space NDC (-1..1), interpolated
};

// Fullscreen triangle.
@vertex
fn vs(@builtin(vertex_index) vi: u32) -> VOut {
    var p = array<vec2f, 3>(
        vec2f(-1.0, -3.0),
        vec2f(-1.0, 1.0),
        vec2f(3.0, 1.0),
    );
    var out: VOut;
    out.clip = vec4f(p[vi], 1.0, 1.0);
    out.ndc = p[vi];
    return out;
}

// Rayleigh scattering coefficient (simplified).
fn rayleigh(dot_val: f32) -> f32 {
    return 0.5 + 0.5 * dot_val;
}

// Mie scattering (sun disc glow).
fn mie(dot_val: f32, g: f32) -> f32 {
    let num = 1.0 - g * g;
    let den = 1.0 + g * g - 2.0 * g * dot_val;
    return num / (den * sqrt(abs(den)) + 0.0001);
}

// ============================================================================
// CazToon night features — ported from sky_night_features.glsl
// ============================================================================

// --- Hash functions (CazToon's skyHash* functions) ---
fn sky_hash11(p: f32) -> f32 {
    var v = fract(p * 0.1031);
    v = v * v + 33.33;
    v = v * v + v;
    return fract(v);
}

fn sky_hash21(p: vec2f) -> f32 {
    let p3 = fract(vec3f(p.x, p.y, p.x) * 0.1031);
    let pp = p3 + dot(p3, p3.yzx + 33.33);
    return fract((pp.x + pp.y) * pp.z);
}

fn sky_hash22(p: vec2f) -> vec2f {
    let p3 = fract(vec3f(p.x, p.y, p.x) * vec3f(0.1031, 0.1030, 0.0973));
    let pp = p3 + dot(p3, p3.yzx + 33.33);
    return fract((pp.xx + pp.yz) * pp.zy);
}

fn sky_hash31(p: vec3f) -> f32 {
    var v = fract(p * 0.1031);
    v = v + dot(v, v.zyx + 31.32);
    return fract((v.x + v.y) * v.z);
}

// --- Cube-face projection (CazToon's skyCubeProject) ---
// Projects a 3D direction onto a cube face, returning 2D UV for star grid.
fn sky_cube_project(dir: vec3f) -> vec2f {
    let a = abs(dir);
    var uv = vec2f(0.0);
    var face = 0.0;
    if (a.x >= a.y && a.x >= a.z) {
        uv = dir.zy / a.x;
        face = select(1.0, 0.0, dir.x > 0.0);
    } else if (a.y >= a.z) {
        uv = dir.xz / a.y;
        face = select(3.0, 2.0, dir.y > 0.0);
    } else {
        uv = dir.xy / a.z;
        face = select(5.0, 4.0, dir.z > 0.0);
    }
    uv = uv + face * 100.0;
    return uv;
}

// --- 3D noise for nebula (CazToon's skyNoise3D + skyFbm3D) ---
fn sky_noise3d(p: vec3f) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let ff = f * f * (3.0 - 2.0 * f);
    let a = sky_hash31(i);
    let b = sky_hash31(i + vec3f(1.0, 0.0, 0.0));
    let c = sky_hash31(i + vec3f(0.0, 1.0, 0.0));
    let d = sky_hash31(i + vec3f(1.0, 1.0, 0.0));
    let e = sky_hash31(i + vec3f(0.0, 0.0, 1.0));
    let g = sky_hash31(i + vec3f(1.0, 0.0, 1.0));
    let h = sky_hash31(i + vec3f(0.0, 1.0, 1.0));
    let k = sky_hash31(i + vec3f(1.0, 1.0, 1.0));
    return mix(
        mix(mix(a, b, ff.x), mix(c, d, ff.x), ff.y),
        mix(mix(e, g, ff.x), mix(h, k, ff.x), ff.y),
        ff.z
    );
}

fn sky_fbm3d(p: vec3f, octaves: i32) -> f32 {
    var v = 0.0;
    var amp = 0.5;
    var pp = p;
    for (var i = 0; i < 4; i = i + 1) {
        if (i >= octaves) { break; }
        v = v + amp * sky_noise3d(pp);
        pp = pp * 2.0;
        amp = amp * 0.5;
    }
    return v;
}

// --- Star field (CazToon's skyStarField) ---
// STAR_SCALE=40, STAR_DENSITY=0.20, STAR_SIZE=0.18, STAR_BRIGHTNESS=0.5, STAR_TWINKLE=0.6
fn sky_star_field(dir: vec3f, time: f32) -> f32 {
    let d = normalize(dir);
    let star_uv = sky_cube_project(d) * 40.0;
    let cell = floor(star_uv);
    let local = fract(star_uv);

    var star = 0.0;
    for (var x = -1; x <= 1; x = x + 1) {
        for (var y = -1; y <= 1; y = y + 1) {
            let nc = cell + vec2f(f32(x), f32(y));
            let rnd = sky_hash21(nc);
            if (rnd > 0.20) { continue; }  // STAR_DENSITY

            let sp = sky_hash22(nc) * 0.6 + 0.2;
            let dd = local - vec2f(f32(x), f32(y)) - sp;
            let dist = length(dd);

            let base_bright = 0.4 + sky_hash21(nc + 500.0) * 0.6;
            let twinkle_phase = sky_hash21(nc + 700.0) * 6.28318;
            let twinkle_speed = 0.5 + sky_hash21(nc + 800.0) * 2.0;
            var twinkle = 0.7 + 0.3 * sin(time * twinkle_speed + twinkle_phase);
            let twinkle_amount = sky_hash21(nc + 900.0);
            twinkle = mix(1.0, twinkle, twinkle_amount * 0.6);

            let bright = base_bright * twinkle * 0.5;  // STAR_BRIGHTNESS
            let radius = 0.18 * (0.5 + sky_hash21(nc + 400.0) * 0.5);  // STAR_SIZE
            let s = 1.0 - smoothstep(0.0, radius, dist);
            star = max(star, s * bright);
        }
    }
    return star;
}

// --- Shooting stars (CazToon's skyShootingStar) ---
// STAR_SHOOTING_BRIGHTNESS=5.0, 3 slots
fn sky_shooting_star(dir: vec3f, time: f32) -> vec3f {
    let d = normalize(dir);
    var result = vec3f(0.0);

    for (var i = 0; i < 3; i = i + 1) {
        let slot_offset = f32(i) * 47.0;
        let cycle_time = 15.0 + sky_hash11(slot_offset) * 20.0;
        let t = (time + slot_offset) % cycle_time;

        let duration = 0.5 + sky_hash11(slot_offset + 10.0) * 1.0;
        if (t > duration) { continue; }

        let start_phi = sky_hash11(slot_offset + 20.0) * 6.28318;
        let start_theta = 0.2 + sky_hash11(slot_offset + 30.0) * 0.6;
        let start_dir = vec3f(
            cos(start_phi) * cos(start_theta),
            sin(start_theta),
            sin(start_phi) * cos(start_theta)
        );

        let travel_angle = sky_hash11(slot_offset + 40.0) * 6.28318;
        let travel_dir = normalize(vec3f(cos(travel_angle), -0.3, sin(travel_angle)));

        let speed = 0.3 + sky_hash11(slot_offset + 50.0) * 0.4;
        let current_pos = normalize(start_dir + travel_dir * t * speed);

        let to_viewer = d - current_pos;
        let along = dot(to_viewer, travel_dir);
        let perp_dist = length(to_viewer - travel_dir * along);

        let trail_width = 0.003;
        let trail_length = 0.08 * (1.0 - t / duration);

        if (perp_dist < trail_width && along > -trail_length && along < 0.01) {
            var intensity = (1.0 - perp_dist / trail_width);
            intensity = intensity * smoothstep(-trail_length, 0.0, along);
            intensity = intensity * (1.0 - t / duration);
            intensity = intensity * 5.0;  // STAR_SHOOTING_BRIGHTNESS
            result = result + vec3f(0.9, 0.95, 1.0) * intensity;
        }
    }
    return result;
}

// --- Night nebula (CazToon's skyNightNebula) ---
// NIGHT_NEBULA_INTENSITY=0.40, NIGHT_NEBULA_SCALE=0.8, NIGHT_NEBULA_SPEED=0.015
// R1=0.2 G1=0.1 B1=0.8, R2=0.0 G2=0.8 B2=0.9
fn sky_night_nebula(dir: vec3f, time: f32) -> vec3f {
    let d = normalize(dir);
    let scale = 0.8 * 2.0;  // NIGHT_NEBULA_SCALE * 2
    let drift = time * 0.015;  // NIGHT_NEBULA_SPEED

    let p1 = d * scale + vec3f(drift * 0.4, drift * 0.15, 0.0);
    let p2 = d * scale * 1.4 + vec3f(31.7, 17.3, 5.1) + vec3f(-drift * 0.25, drift * 0.35, 0.0);
    let p3 = d * scale * 0.3 + vec3f(-50.0, 25.0, 12.3) + vec3f(drift * 0.08, 0.0, 0.0);

    let large1 = sky_fbm3d(p1, 4);
    let large2 = sky_fbm3d(p2, 3);
    let color_layer = sky_fbm3d(p3, 3);

    var mask = smoothstep(0.28, 0.60, large1);
    mask = mask * (0.55 + 0.45 * large2);
    mask = max(mask, smoothstep(0.50, 0.80, large1) * 0.5);

    let height_fade = smoothstep(-0.05, 0.18, d.y) * (1.0 - smoothstep(0.88, 1.00, d.y));
    mask = mask * height_fade;

    let col1 = vec3f(0.2, 0.1, 0.8);   // NIGHT_NEBULA_R1,G1,B1
    let col2 = vec3f(0.0, 0.8, 0.9);   // NIGHT_NEBULA_R2,G2,B2
    var nebula_color = mix(col1, col2, smoothstep(0.3, 0.7, color_layer));
    nebula_color = nebula_color + vec3f(0.5, 0.4, 0.8) * smoothstep(0.65, 0.85, large1) * 0.35;

    return nebula_color * mask * 0.40;  // NIGHT_NEBULA_INTENSITY
}

struct SkyFOut {
    @location(0) color: vec4f,
    @location(1) normal: vec4f,
    @location(2) linear_depth: vec4f,
};
// ============================================================================
// Volumetric clouds — ported from CazToon's volumetric_clouds.glsl
// ============================================================================

// Cloud constants (CazToon settings/sky.glsl defaults)
const CLOUD_3D_STEPS     = 24;
const CLOUD_3D_COVERAGE  = 0.65;
const CLOUD_3D_DENSITY   = 2.00;
const CLOUD_3D_HEIGHT    = 300.0;
const CLOUD_3D_THICKNESS = 150.0;
const CLOUD_3D_SCALE     = 1.0;
const CLOUD_3D_CELL_SIZE = 60.0;
const CLOUD_3D_DETAIL    = 1.0;
const CLOUD_3D_SPEED     = 6.0;
const CLOUD_3D_BRIGHTNESS = 1.2;
const CLOUD_3D_DISTANCE   = 8000.0;
const CLOUD_3D_EDGE_GLOW  = 0.1;
const CYCLE_SECS          = 1320.0;
const SEA_LEVEL_OFFSET    = 0.0;

fn vc_hash31(p: vec3f) -> f32 {
    var v = fract(p * vec3f(0.1031, 0.1030, 0.0973));
    v = v + dot(v, v.yzx + 33.33);
    return fract((v.x + v.y) * v.z);
}

fn vc_hash21(p: vec2f) -> f32 {
    var v = fract(p * vec2f(0.1031, 0.1030));
    v = v + dot(v, v.yx + 33.33);
    return fract((v.x + v.y) * v.x);
}

fn vc_noise3d(p: vec3f) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let ff = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let a = vc_hash31(i);
    let b = vc_hash31(i + vec3f(1.0, 0.0, 0.0));
    let c = vc_hash31(i + vec3f(0.0, 1.0, 0.0));
    let d = vc_hash31(i + vec3f(1.0, 1.0, 0.0));
    let e = vc_hash31(i + vec3f(0.0, 0.0, 1.0));
    let g = vc_hash31(i + vec3f(1.0, 0.0, 1.0));
    let h = vc_hash31(i + vec3f(0.0, 1.0, 1.0));
    let k = vc_hash31(i + vec3f(1.0, 1.0, 1.0));
    return mix(
        mix(mix(a, b, ff.x), mix(c, d, ff.x), ff.y),
        mix(mix(e, g, ff.x), mix(h, k, ff.x), ff.y),
        ff.z
    );
}

fn vc_noise2d(p: vec2f) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let ff = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let a = vc_hash21(i);
    let b = vc_hash21(i + vec2f(1.0, 0.0));
    let c = vc_hash21(i + vec2f(0.0, 1.0));
    let d = vc_hash21(i + vec2f(1.0, 1.0));
    return mix(mix(a, b, ff.x), mix(c, d, ff.x), ff.y);
}

fn vc_cloud_density(world_pos: vec3f, time: f32, dist_from_cam: f32) -> f32 {
    let y = world_pos.y;
    let base_height = CLOUD_3D_HEIGHT + SEA_LEVEL_OFFSET;
    let thick = CLOUD_3D_THICKNESS;
    let cell_size = max(CLOUD_3D_CELL_SIZE, 1.0);
    let cell_norm = 25.0 / cell_size;

    let layer_bottom = base_height - thick * 0.8;
    let layer_top = base_height + thick * 2.0;
    if (y < layer_bottom || y > layer_top) { return 0.0; }

    let wind_angle = 1.2;
    let wind_dir = vec2f(cos(wind_angle), sin(wind_angle));
    let wind_vel = CLOUD_3D_SPEED * wind_dir;
    let alt_frac_raw = clamp((y - base_height) / thick, 0.0, 1.0);
    let wind_offset = wind_vel * (time + 30.0 * alt_frac_raw * alt_frac_raw);

    let h_pos = (world_pos.xz + wind_vel * time) * CLOUD_3D_SCALE * 0.001 * cell_norm;
    let height_offset = vc_noise2d(h_pos) * thick * 1.0
        + vc_noise2d(h_pos * 3.3) * thick * 0.4
        - thick * 0.5;

    let local_base = base_height + height_offset;
    let local_top = local_base + thick;
    if (y < local_base || y > local_top) { return 0.0; }

    let alt_frac = (y - local_base) / thick;

    let base_scale = CLOUD_3D_SCALE * 0.001 * cell_norm;
    let base_pos = vec3f(
        (world_pos.x + wind_offset.x) * base_scale,
        world_pos.y * base_scale * 0.8,
        (world_pos.z + wind_offset.y) * base_scale
    );

    let base_high_freq_fade = 1.0 - smoothstep(4000.0, 7000.0, dist_from_cam);
    let noise = vc_noise3d(base_pos) * (0.65 + 0.35 * (1.0 - base_high_freq_fade))
        + vc_noise3d(base_pos * 2.7) * 0.35 * base_high_freq_fade;

    let threshold = 1.0 - CLOUD_3D_COVERAGE;
    let t_val = clamp((noise - threshold) / 0.3, 0.0, 1.0);
    var density = t_val * t_val;

    if (density < 0.001) { return 0.0; }

    let bottom_clip = smoothstep(0.0, 0.12, alt_frac);
    let top_dome = 1.0 - smoothstep(0.6, 1.0, alt_frac);
    density = density * bottom_clip * top_dome;

    if (density < 0.001) { return 0.0; }

    let lod_fade_small  = 1.0 - smoothstep(1500.0, 3000.0, dist_from_cam);
    let lod_fade_medium = 1.0 - smoothstep(3000.0, 5000.0, dist_from_cam);
    let lod_fade_large  = 1.0 - smoothstep(5000.0, 8000.0, dist_from_cam);

    let wind3d = vec3f(wind_vel.x, 0.0, wind_vel.y) * time;

    var erosion = 0.0;
    if (lod_fade_large > 0.01) {
        let detail0 = vc_noise3d((world_pos + wind3d * 0.2) * 0.005);
        erosion = erosion + 0.7 * detail0 * detail0 * lod_fade_large;
    }
    if (lod_fade_medium > 0.01) {
        let detail1 = vc_noise3d((world_pos + wind3d * 0.15) * 0.012);
        erosion = erosion + 0.5 * detail1 * detail1 * lod_fade_medium;
    }
    if (lod_fade_small > 0.01) {
        let detail2 = vc_noise3d((world_pos + wind3d * 0.1) * 0.028);
        erosion = erosion + 0.3 * detail2 * detail2 * lod_fade_small;
    }
    density = density - CLOUD_3D_DETAIL * erosion;
    density = max(density, 0.0);

    return density;
}

const VC_LIGHT_STEPS = 5;
fn vc_light_optical_depth(origin: vec3f, light_dir: vec3f, time: f32, dist_from_cam: f32) -> f32 {
    var step_len = 10.0;
    var optical_depth = 0.0;
    var pos = origin;

    for (var i = 0; i < VC_LIGHT_STEPS; i = i + 1) {
        pos = pos + light_dir * step_len;
        optical_depth = optical_depth + vc_cloud_density(pos, time, dist_from_cam) * step_len;
        step_len = step_len * 2.0;
    }
    return optical_depth;
}

fn vc_cloud_color(light_opt_depth: f32, alt_frac: f32, sun_angle_frac: f32) -> vec3f {
    let angle = fract(sun_angle_frac);
    // Engine cycle: day=0.0-0.45, sunset=0.45-0.52, blue_hour=0.52-0.57,
    // night=0.57-0.89, dawn=0.89-0.93, sunrise=0.93-1.0 (wraps to day).
    let day_amount = smoothstep(0.0, 0.02, angle) * (1.0 - smoothstep(0.43, 0.45, angle));
    let twilight_amount = smoothstep(0.43, 0.45, angle) * (1.0 - smoothstep(0.57, 0.59, angle))
        + smoothstep(0.91, 0.93, angle);
    let night_amount = smoothstep(0.57, 0.59, angle) * (1.0 - smoothstep(0.91, 0.93, angle));

    let total = max(day_amount + twilight_amount + night_amount, 0.001);
    let day_amt = day_amount / total;
    let twl_amt = twilight_amount / total;
    let night_amt = night_amount / total;

    let day_lit = vec3f(1.0, 1.0, 1.0) * CLOUD_3D_BRIGHTNESS;
    let day_shadow = vec3f(0.45, 0.50, 0.70) * CLOUD_3D_BRIGHTNESS;

    let sunset_lit = vec3f(1.0, 0.85, 0.65) * CLOUD_3D_BRIGHTNESS;
    let sunset_shadow = vec3f(0.50, 0.38, 0.48) * CLOUD_3D_BRIGHTNESS;

    let night_lit = vec3f(0.20, 0.24, 0.38) * CLOUD_3D_BRIGHTNESS;
    let night_shadow = vec3f(0.08, 0.09, 0.18) * CLOUD_3D_BRIGHTNESS;

    let lit_color = day_lit * day_amt + sunset_lit * twl_amt + night_lit * night_amt;
    let shadow_color = day_shadow * day_amt + sunset_shadow * twl_amt + night_shadow * night_amt;

    var sun_shadow = exp(-light_opt_depth * 0.04);
    sun_shadow = max(sun_shadow, 0.15);

    let alt_light = mix(0.5, 1.0, alt_frac);
    let light_factor = sun_shadow * alt_light;

    return mix(shadow_color, lit_color, light_factor);
}

fn render_volumetric_clouds(world_dir: vec3f, time: f32, cam_pos: vec3f, sun_angle: f32, sun_dir_world: vec3f, max_dist: f32, frag_coord: vec2f, frame: f32) -> vec4f {
    let dir = normalize(world_dir);

    let base_height = CLOUD_3D_HEIGHT + SEA_LEVEL_OFFSET;
    let layer_bottom = base_height - CLOUD_3D_THICKNESS * 0.8;
    let layer_top = base_height + CLOUD_3D_THICKNESS * 2.0;

    var t_min = 0.0;
    var t_max = 0.0;
    if (abs(dir.y) < 0.0005) {
        if (cam_pos.y >= layer_bottom && cam_pos.y <= layer_top) {
            t_min = 0.0; t_max = 8000.0;
        } else {
            return vec4f(0.0);
        }
    } else {
        let t0 = (layer_bottom - cam_pos.y) / dir.y;
        let t1 = (layer_top - cam_pos.y) / dir.y;
        t_min = min(t0, t1);
        t_max = max(t0, t1);
    }

    t_min = max(t_min, 0.0);
    if (t_min >= t_max) { return vec4f(0.0); }
    t_max = min(t_max, max_dist);
    if (t_min >= t_max) { return vec4f(0.0); }

    let cloud_render_dist = CLOUD_3D_DISTANCE;
    let fade_start = cloud_render_dist * 0.4;

    if (t_min > cloud_render_dist * 1.2) { return vec4f(0.0); }

    let march_dist = min(t_max - t_min, 12000.0);
    let step_len = march_dist / f32(CLOUD_3D_STEPS);

    let dither = fract(sin(dot(frag_coord + frame * 0.7183, vec2f(12.9898, 78.233))) * 43758.5453);
    let ray_start = t_min + step_len * dither;

    let extinct_coeff = CLOUD_3D_DENSITY * 0.015;
    var acc_color = vec3f(0.0);
    var transmittance = 1.0;

    for (var i = 0; i < CLOUD_3D_STEPS; i = i + 1) {
        if (transmittance < 0.05) { break; }

        let t = ray_start + step_len * f32(i);
        if (t > t_max) { break; }

        let sample_pos = cam_pos + dir * t;
        var density = vc_cloud_density(sample_pos, time, t);

        if (density < 0.001) { continue; }

        let horiz_dist = length(sample_pos.xz - cam_pos.xz);
        var dist_fade = 1.0 - smoothstep(fade_start, cloud_render_dist * 0.95, horiz_dist);
        dist_fade = dist_fade * dist_fade;
        density = density * dist_fade;

        if (density < 0.001) { continue; }

        let step_opt_depth = density * extinct_coeff * step_len;
        let step_transmittance = exp(-step_opt_depth);

        let light_od = vc_light_optical_depth(sample_pos, sun_dir_world, time, t);
        let alt_frac = clamp((sample_pos.y - base_height) / max(CLOUD_3D_THICKNESS, 1.0), 0.0, 1.0);
        var step_color = vc_cloud_color(light_od, alt_frac, sun_angle);
        let edge_glow = (1.0 - smoothstep(0.18, 0.82, density)) * CLOUD_3D_EDGE_GLOW;
        step_color = step_color + step_color * edge_glow * 0.35;

        let weight = (1.0 - step_transmittance) * transmittance;
        acc_color = acc_color + step_color * weight;

        transmittance = transmittance * step_transmittance;
    }

    let alpha = 1.0 - transmittance;
    return vec4f(acc_color, alpha);
}

@fragment
fn fs(in: VOut) -> SkyFOut {
    let tan_half_fov = cam.cam_pos.w;
    let aspect = cam.sky_color.w;
    let dir = normalize(
        cam.cam_forward.xyz
        + cam.cam_right.xyz * (in.ndc.x * tan_half_fov * aspect)
        + cam.cam_up.xyz * (in.ndc.y * tan_half_fov)
    );
    let sun_dir = normalize(cam.sun_dir.xyz);
    let sun_strength = cam.sun_dir.w;
    let time = cam.sun_color.w;

    // Sun elevation: 0 = horizon, 1 = directly overhead.
    let sun_up = clamp(sun_dir.y, 0.0, 1.0);
    let dir_up = clamp(dir.y, -1.0, 1.0);

    // Cosine of angle between view direction and sun.
    let cos_angle = dot(dir, sun_dir);

    // Sky colors from the 6-phase ToD system.
    let horizon_color = cam.sky_color.xyz;
    let top_color = cam.zenith_color.xyz;
    let mid_color = mix(horizon_color, top_color, 0.5);

    // 3-layer sky gradient matching CazToon's horizon/mid/zenith blend.
    let gradient = clamp(dir_up * 0.5 + 0.5, 0.0, 1.0);
    var sky = mix(horizon_color, mid_color, smoothstep(0.0, 0.52, gradient));
    sky = mix(sky, top_color, smoothstep(0.52, 0.85, gradient));

    // Sky saturation boost (CazToon uses 2.0x saturation on sky).
    let sky_lum = dot(sky, vec3f(0.299, 0.587, 0.114));
    sky = mix(vec3f(sky_lum), sky, 1.8);

    // Sunset/sunrise warm tint near horizon — driven by sun elevation.
    let sunset_factor = clamp(1.0 - abs(sun_dir.y) * 4.0, 0.0, 1.0);
    let horizon_glow = clamp(1.0 - abs(dir.y) * 3.0, 0.0, 1.0) * sunset_factor;
    sky = mix(sky, cam.sun_color.xyz, horizon_glow * 0.35 * sun_strength);

    // Rayleigh scattering — sky brighter near sun.
    let rayleigh_val = rayleigh(cos_angle);
    sky += cam.sun_color.xyz * rayleigh_val * 0.15 * sun_strength;

    // Sun disc — bright spot at sun direction with CazToon-style glow.
    let sun_angle = acos(clamp(cos_angle, -1.0, 1.0));
    let sun_disc = exp(-sun_angle * sun_angle * 800.0);
    let sun_glow = sun_disc * 3.0;
    sky += cam.sun_color.xyz * sun_glow * sun_strength;

    // Sun atmospheric glow — wide halo, strong at sunrise/sunset.
    // CazToon: glow = exp(-d²/r²), r = SUN_GLOW_RADIUS * 0.08; halo = 1/(1+(d/r2)⁴)
    let glow_r = 0.08;
    let sun_atmo_glow = exp(-sun_angle * sun_angle / (glow_r * glow_r)) * 0.35;
    let halo_r2 = 0.2;
    let sun_atmo_halo = 1.0 / (1.0 + pow(sun_angle / halo_r2, 4.0)) * 0.08;
    sky += cam.sun_color.xyz * (sun_atmo_glow + sun_atmo_halo) * sun_strength;

    // --- Moon disc (opposite the sun) ---
    // CazToon renders the moon via the vanilla sun/moon texture. We draw
    // a procedural pale disc — soft, dim, with a subtle glow. Not a sun.
    let moon_dir = -sun_dir;
    let moon_cos = dot(dir, moon_dir);
    let moon_angle = acos(clamp(moon_cos, -1.0, 1.0));
    let moon_visibility = clamp(1.0 - sun_strength * 2.0, 0.0, 1.0);
    // Disc: tight but dim (pale grey, not white-hot)
    let moon_disc = exp(-moon_angle * moon_angle * 2000.0) * moon_visibility;
    // Soft glow halo
    let moon_glow = exp(-moon_angle * moon_angle * 100.0) * 0.15 * moon_visibility;
    let moon_halo = 1.0 / (1.0 + pow(moon_angle / 0.35, 4.0)) * 0.03 * moon_visibility;
    let moon_color = vec3f(0.65, 0.67, 0.72);
    sky += moon_color * (moon_disc * 0.8 + moon_glow + moon_halo);

    // --- Night features (CazToon's skyAddNightFeatures) ---
    // Night visibility: driven by how low sun_strength is (0 = full night).
    // CazToon uses smoothstep on the sun angle; we use sun_strength as a proxy.
    let night_vis = clamp((0.2 - sun_strength) / 0.2, 0.0, 1.0);
    let blue_hour_vis = clamp((0.3 - sun_strength) / 0.15, 0.0, 1.0) * (1.0 - night_vis);

    if (night_vis > 0.01 && dir.y > -0.1) {
        let horizon_fade = smoothstep(-0.1, 0.15, dir.y);

        // Star field
        let stars = sky_star_field(dir, time);
        sky += vec3f(stars) * night_vis * horizon_fade;

        // Shooting stars (only at full night)
        if (night_vis > 0.5) {
            let shooting = sky_shooting_star(dir, time);
            sky += shooting * horizon_fade * night_vis;
        }
    }

    // Night nebula (visible at night + partial during blue hour)
    let nebula_vis = night_vis + blue_hour_vis * 0.4;
    if (nebula_vis > 0.01) {
        let nebula = sky_night_nebula(dir, time);
        sky += nebula * nebula_vis;
    }

    // --- 3D Volumetric clouds (CazToon's renderVolumetricClouds) ---
    // Raymarch cloud layers only for upward-looking pixels (dir.y > 0).
    // Clouds sit at CLOUD_3D_HEIGHT (300m) above sea level.
    if (dir.y > 0.001 && cam.zenith_color.w > 0.5) {
        let sun_angle_frac = fract(time / CYCLE_SECS);
        let cloud_result = render_volumetric_clouds(
            dir, time, cam.cam_pos.xyz,
            sun_angle_frac, sun_dir,
            CLOUD_3D_DISTANCE,
            in.ndc * vec2f(512.0, 512.0), // approx frag coord for dither
            0.0 // frame counter (static dither for now)
        );
        if (cloud_result.a > 0.001) {
            sky = sky * (1.0 - clamp(cloud_result.a, 0.0, 1.0)) + cloud_result.rgb;
        }
    }

    var out: SkyFOut;
    out.color = vec4f(sky, 1.0);
    out.normal = vec4f(0.0, 0.0, 0.0, 0.0);
    out.linear_depth = vec4f(1.0, 0.0, 0.0, 0.0);
    return out;
}
