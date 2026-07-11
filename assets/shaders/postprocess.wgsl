// Post-processing pass: edge detection (Sobel on depth + normal),
// material-tinted outlines, saturation boost, and dreamy color grading.
// Renders as a fullscreen triangle (3 vertices, no vertex buffer).

struct Params {
    resolution: vec2f,   // screen size in pixels
    texel_size: vec2f,   // 1.0 / resolution
    cam_pos: vec3f,      // camera world position
    _pad0: f32,
    cam_forward: vec3f,  // camera forward (unit)
    _pad1: f32,
    cam_right: vec3f,    // camera right (unit)
    _pad2: f32,
    cam_up: vec3f,       // camera up (unit)
    tan_half_fov: f32,   // tan(fov_y / 2)
    aspect: f32,         // width / height
    z_far: f32,          // far clip distance (600.0)
    _pad3: f32,
    _pad4: f32,
    _pad5: f32,
};

@group(0) @binding(0) var<uniform> params: Params;
@group(0) @binding(1) var color_tex: texture_2d<f32>;
@group(0) @binding(2) var depth_tex: texture_2d<f32>;
@group(0) @binding(3) var normal_tex: texture_2d<f32>;
@group(0) @binding(4) var samp: sampler;

// Sobel edge detection on depth (rendered to Rgba16Float color texture).
fn sobel_depth(uv: vec2f, ts: vec2f) -> f32 {
    let tl = textureSample(depth_tex, samp, uv + vec2f(-ts.x, -ts.y)).r;
    let tm = textureSample(depth_tex, samp, uv + vec2f(0.0,  -ts.y)).r;
    let tr = textureSample(depth_tex, samp, uv + vec2f( ts.x, -ts.y)).r;
    let ml = textureSample(depth_tex, samp, uv + vec2f(-ts.x,  0.0)).r;
    let mr = textureSample(depth_tex, samp, uv + vec2f( ts.x,  0.0)).r;
    let bl = textureSample(depth_tex, samp, uv + vec2f(-ts.x,  ts.y)).r;
    let bm = textureSample(depth_tex, samp, uv + vec2f(0.0,   ts.y)).r;
    let br = textureSample(depth_tex, samp, uv + vec2f( ts.x,  ts.y)).r;
    let gx = abs(tr + 2.0 * mr + br - tl - 2.0 * ml - bl);
    let gy = abs(bl + 2.0 * bm + br - tl - 2.0 * tm - tr);
    return clamp(gx + gy, 0.0, 1.0);
}

// Fullscreen triangle: 3 vertices covering the screen.
@vertex
fn vs(@builtin(vertex_index) vi: u32) -> @builtin(position) vec4f {
    // Triangle covering [-1, 1] clip space.
    var p = array<vec2f, 3>(
        vec2f(-1.0, -3.0),
        vec2f(-1.0, 1.0),
        vec2f(3.0, 1.0),
    );
    return vec4f(p[vi], 0.0, 1.0);
}


// Sobel on a vec3 texture (normal).
fn sobel_vec3(tex: texture_2d<f32>, uv: vec2f, ts: vec2f) -> f32 {
    let tl = textureSample(tex, samp, uv + vec2f(-ts.x, -ts.y)).rgb;
    let tm = textureSample(tex, samp, uv + vec2f(0.0,  -ts.y)).rgb;
    let tr = textureSample(tex, samp, uv + vec2f( ts.x, -ts.y)).rgb;
    let ml = textureSample(tex, samp, uv + vec2f(-ts.x,  0.0)).rgb;
    let mr = textureSample(tex, samp, uv + vec2f( ts.x,  0.0)).rgb;
    let bl = textureSample(tex, samp, uv + vec2f(-ts.x,  ts.y)).rgb;
    let bm = textureSample(tex, samp, uv + vec2f(0.0,   ts.y)).rgb;
    let br = textureSample(tex, samp, uv + vec2f( ts.x,  ts.y)).rgb;
    let gx = length(tr + 2.0 * mr + br - tl - 2.0 * ml - bl);
    let gy = length(bl + 2.0 * bm + br - tl - 2.0 * tm - tr);
    return clamp(gx + gy, 0.0, 1.0);
}

// Boost saturation by a factor. Uses luminance-weighted mixing.
fn boost_saturation(c: vec3f, amount: f32) -> vec3f {
    let lum = dot(c, vec3f(0.299, 0.587, 0.114));
    return mix(vec3f(lum), c, amount);
}

// Screen-Space Reflections (SSR): ray-march the linear depth buffer
// for reflections, blended subtly (max 20%) into bright/smooth surfaces.
// Depth is linear (dist / 600.0), so world position is reconstructed
fn ssr(uv: vec2f, color: vec3f) -> vec3f {
    let depth_sample = textureSampleLevel(depth_tex, samp, uv, 0.0);
    let depth = depth_sample.r;
    let reflectivity = depth_sample.g;
    if (depth >= 0.99 || reflectivity < 0.05) { return color; }  // sky or matte

    // Reconstruct world position from linear depth using camera basis.
    let ndc = vec2f(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    let view_dir = normalize(
        params.cam_forward
        + params.cam_right * (ndc.x * params.tan_half_fov * params.aspect)
        + params.cam_up * (ndc.y * params.tan_half_fov)
    );
    let world_pos = params.cam_pos + view_dir * (depth * params.z_far);

    // Normal from MRT (world-space).
    let normal = normalize(textureSampleLevel(normal_tex, samp, uv, 0.0).xyz);

    // Reflection direction (view_dir points from cam to surface).
    let refl_dir = reflect(view_dir, normal);

    // Screen-space ray-march: step along the reflection direction.
    var step_uv = uv;
    let step_size = params.texel_size * 3.0;
    let step_dir = normalize(refl_dir.xy);
    var hit_color = vec3f(0.0);
    var hit_weight = 0.0;

    for (var i = 0u; i < 24u; i++) {
        step_uv += step_dir * step_size;
        if (step_uv.x < 0.0 || step_uv.x > 1.0 || step_uv.y < 0.0 || step_uv.y > 1.0) {
            break;
        }
        let sample_depth = textureSampleLevel(depth_tex, samp, step_uv, 0.0).r;
        if (sample_depth < depth - 0.002 && sample_depth < 0.99) {
            hit_color = textureSampleLevel(color_tex, samp, step_uv, 0.0).rgb;
            hit_color = hit_color / (hit_color + vec3f(0.6));  // tone map
            hit_weight = (1.0 - f32(i) / 24.0) * 0.2 * reflectivity;
            break;
        }
    }

    return mix(color, hit_color, hit_weight);
}

@fragment
fn fs(@builtin(position) frag_pos: vec4f) -> @location(0) vec4f {
    let uv = frag_pos.xy * params.texel_size;

    // Sample base color.
    var c = textureSample(color_tex, samp, uv).rgb;

    // Very subtle tone mapping — just a soft knee in highlights to
    // prevent harsh clipping, not full ACES which creates artifacts
    // with the water's flat color values.
    c = c / (c + vec3f(0.6));
    c = clamp(c, vec3f(0.0), vec3f(1.0));

    // Saturation boost (+30%) — luminance-weighted mix toward the
    // original color so colors pop without going neon (design doc §2.4).
    let lum = dot(c, vec3f(0.299, 0.587, 0.114));
    c = mix(vec3f(lum), c, 1.3);

    // Color grading: slight lift in shadows, warm tint, gentle contrast.
    c = c * vec3f(1.02, 1.0, 0.98);

    // Screen-space reflections (#SSR): subtle ray-marched reflections
    // on water/smooth surfaces, max 20% blend weight.
    c = ssr(uv, c);

    // Edge detection (#64): Sobel on depth + normal. Now that MRT
    // writes real data to depth_copy_tex and normal_tex, the sobel
    // functions have real edges to detect. Subtle dark outlines on
    // geometry boundaries for a toon look.
    // Edge detection (#64): Sobel on depth + normal. Only apply on
    // flat-shaded voxels (axis-aligned normals), not on Mario's
    // smooth interpolated normals which create false edges.
    let n_sample = textureSampleLevel(normal_tex, samp, uv, 0.0);
    let is_flat = max(max(abs(n_sample.x), abs(n_sample.y)), abs(n_sample.z)) > 0.95;
    if (is_flat) {
        let edge_d = sobel_depth(uv, params.texel_size);
        let edge_n = sobel_vec3(normal_tex, uv, params.texel_size);
        let edge = clamp(edge_d + edge_n * 0.5, 0.0, 1.0);
        c = mix(c, c * vec3f(0.3, 0.25, 0.2), edge * 0.6);
    }

    return vec4f(clamp(c, vec3f(0.0), vec3f(1.0)), 1.0);
}
