// Procedural sky dome rendered as a fullscreen triangle before the scene.
// Uses Rayleigh + Mie scattering approximation driven by the day/night
// sun direction. Outputs sky color + sun disc, replacing the flat clear.

struct SkyCam {
    view_proj: mat4x4f,
    cam_pos: vec4f,      // xyz = cam pos, w = tan(fov_y / 2)
    sun_dir: vec4f,      // xyz = sun direction (unit), w = sun strength
    sky_color: vec4f,    // xyz = sky/fog color, w = aspect ratio
    sun_color: vec4f,    // xyz = sun color, w = game time
    cam_forward: vec4f,  // xyz = camera forward (unit)
    cam_right: vec4f,    // xyz = camera right (unit)
    cam_up: vec4f,       // xyz = camera up (unit)
};
@group(0) @binding(0) var<uniform> cam: SkyCam;

struct VOut {
    @builtin(position) clip: vec4f,
    @location(0) view_dir: vec3f,  // direction from camera to fragment
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
    // Reconstruct the world-space view ray for this pixel using the
    // actual FOV and aspect ratio so the sky matches the camera frustum.
    // NDC x,y ∈ [-1,1] map to tan(fov/2) * aspect on X and tan(fov/2)
    // on Y, then normalize the resulting direction.
    let ndc = p[vi];
    let tan_half_fov = cam.cam_pos.w;
    let aspect = cam.sky_color.w;
    let ray = cam.cam_forward.xyz
        + cam.cam_right.xyz * (ndc.x * tan_half_fov * aspect)
        + cam.cam_up.xyz * (ndc.y * tan_half_fov);
    out.view_dir = normalize(ray);
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

@fragment
fn fs(in: VOut) -> @location(0) vec4f {
    let dir = normalize(in.view_dir);
    let sun_dir = normalize(cam.sun_dir.xyz);
    let sun_strength = cam.sun_dir.w;

    // Sun elevation: 0 = horizon, 1 = directly overhead.
    let sun_up = clamp(sun_dir.y, 0.0, 1.0);
    let dir_up = clamp(dir.y, -1.0, 1.0);

    // Cosine of angle between view direction and sun.
    let cos_angle = dot(dir, sun_dir);

    // Day sky colors (top vs horizon).
    let day_top = vec3f(0.25, 0.45, 0.85);
    let day_horizon = vec3f(0.55, 0.70, 0.90);

    // Sunset/sunrise tint.
    let sunset_tint = vec3f(0.95, 0.45, 0.20);
    let sunset_factor = clamp(1.0 - abs(sun_dir.y) * 4.0, 0.0, 1.0);

    // Night sky.
    let night_top = vec3f(0.02, 0.02, 0.05);
    let night_horizon = vec3f(0.04, 0.04, 0.08);

    // Blend day/night by sun strength.
    let top_color = mix(night_top, day_top, sun_strength);
    let horizon_color = mix(night_horizon, day_horizon, sun_strength);

    // Sky gradient: horizon at dir.y=0, top at dir.y=1.
    let gradient = clamp(dir_up * 0.5 + 0.5, 0.0, 1.0);
    var sky = mix(horizon_color, top_color, pow(gradient, 0.8));

    // Sunset/sunrise warm tint near horizon.
    let horizon_glow = clamp(1.0 - abs(dir.y) * 3.0, 0.0, 1.0) * sunset_factor;
    sky = mix(sky, sunset_tint, horizon_glow * 0.4 * sun_strength);

    // Rayleigh scattering — sky brighter near sun.
    let rayleigh_val = rayleigh(cos_angle);
    sky += cam.sun_color.xyz * rayleigh_val * 0.15 * sun_strength;

    // Sun disc — bright spot at sun direction.
    // Use a smooth gaussian falloff instead of Mie pow() which
    // overflows to inf/NaN at cos_angle=1 (the "black hole" bug).
    let sun_angle = acos(clamp(cos_angle, -1.0, 1.0));
    let sun_disc = exp(-sun_angle * sun_angle * 800.0); // sharp gaussian
    let sun_glow = sun_disc * 3.0;
    // Sun disc always visible during day (not multiplied by sun_strength
    // which would zero it out). Use max(strength, 0.3) so even near
    // dusk the disc is visible.
    let disc_visibility = max(sun_strength, 0.3);
    sky += cam.sun_color.xyz * sun_glow * disc_visibility;

    // Sun halo — softer glow around the disc.
    let halo = exp(-sun_angle * sun_angle * 80.0) * 0.4;
    sky += cam.sun_color.xyz * halo * disc_visibility;

    // Stars at night — snap direction to a grid to prevent shimmer.
    if (sun_strength < 0.15) {
        let grid_dir = floor(dir * 200.0) / 200.0;
        let star_hash = fract(sin(grid_dir.x * 127.1 + grid_dir.y * 311.7 + grid_dir.z * 74.7) * 43758.5453);
        let star_brightness = smoothstep(0.992, 1.0, star_hash);
        let star_fade = (0.15 - sun_strength) / 0.15;
        // Only show stars above the horizon.
        let above_horizon = step(0.0, dir.y);
        sky += vec3f(star_brightness * star_fade * above_horizon);
    }

    return vec4f(sky, 1.0);
}
