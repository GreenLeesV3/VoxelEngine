// Procedural sky dome rendered as a fullscreen triangle before the scene.
// Uses Rayleigh + Mie scattering approximation driven by the day/night
// sun direction. Outputs sky color + sun disc, replacing the flat clear.

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

struct SkyFOut {
    @location(0) color: vec4f,
    @location(1) normal: vec4f,
    @location(2) linear_depth: vec4f,
};

@fragment
fn fs(in: VOut) -> SkyFOut {
    // Reconstruct the world-space view ray per-pixel from the
    // interpolated NDC coordinates. Computing it per-vertex and
    // interpolating the normalized direction causes squashing at
    // screen edges — the linear interpolation doesn't preserve
    // angular distribution. Per-fragment reconstruction is correct.
    let tan_half_fov = cam.cam_pos.w;
    let aspect = cam.sky_color.w;
    let dir = normalize(
        cam.cam_forward.xyz
        + cam.cam_right.xyz * (in.ndc.x * tan_half_fov * aspect)
        + cam.cam_up.xyz * (in.ndc.y * tan_half_fov)
    );
    let sun_dir = normalize(cam.sun_dir.xyz);
    let sun_strength = cam.sun_dir.w;

    // Sun elevation: 0 = horizon, 1 = directly overhead.
    let sun_up = clamp(sun_dir.y, 0.0, 1.0);
    let dir_up = clamp(dir.y, -1.0, 1.0);

    // Cosine of angle between view direction and sun.
    let cos_angle = dot(dir, sun_dir);

    // Sky colors from the 6-phase ToD system (cam.sky_color.xyz
    // carries the weighted blend from day_night.rs). Use it as the
    // horizon color and derive zenith + mid colors from it.
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
    let sun_atmo = exp(-sun_angle * sun_angle * 30.0) * 0.3;
    sky += cam.sun_color.xyz * sun_atmo * sun_strength;

    // Sun halo — softer glow around the disc, fades with the sun.
    let halo = exp(-sun_angle * sun_angle * 80.0) * 0.4;
    sky += cam.sun_color.xyz * halo * sun_strength;

    // Stars at night — CazToon-style with density, size, and twinkle.
    if (sun_strength < 0.15) {
        let star_fade = (0.15 - sun_strength) / 0.15;
        let above_horizon = step(0.0, dir.y);

        // Grid-based star field (STAR_SCALE=40, STAR_DENSITY=0.20)
        let grid_dir = floor(dir * 40.0) / 40.0;
        let star_hash = fract(sin(grid_dir.x * 127.1 + grid_dir.y * 311.7 + grid_dir.z * 74.7) * 43758.5453);
        let star_density = step(0.80, star_hash);  // 20% of cells have stars

        // Star size (STAR_SIZE=0.18) — soft circle within the cell
        let cell_fract = fract(dir * 40.0);
        let star_dist = length(cell_fract - 0.5);
        let star_shape = 1.0 - smoothstep(0.0, 0.18, star_dist);

        // Twinkle (STAR_TWINKLE=0.6) — time-based brightness variation
        let twinkle = 0.7 + 0.3 * sin(cam.sun_color.w * 3.0 + star_hash * 6.28);
        let star_brightness = star_density * star_shape * star_fade * 0.5 * twinkle * above_horizon;
        sky += vec3f(star_brightness);

        // Night nebula — subtle colored cloud patches (CazToon-style)
        let neb_noise = fract(sin(grid_dir.x * 13.1 + grid_dir.z * 27.7) * 43758.5453);
        let nebula = smoothstep(0.7, 0.95, neb_noise) * star_fade * 0.15 * above_horizon;
        sky += vec3f(nebula * 0.2, nebula * 0.1, nebula * 0.8);  // blue-purple
    }

    var out: SkyFOut;
    out.color = vec4f(sky, 1.0);
    out.normal = vec4f(0.0, 0.0, 0.0, 0.0);
    out.linear_depth = vec4f(1.0, 0.0, 0.0, 0.0);
    return out;
}
