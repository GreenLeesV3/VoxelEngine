// Mario pipeline: renders libsm64's dynamic per-frame geometry (up to
// 1024 triangles). Vertices come from sm64_mario_tick's geometry
// buffers: position (float3), normal (float3), color (float3), uv
// (float2). Textured with Mario's 704×64 RGBA atlas extracted from
// the ROM. Simple sun + ambient lighting matching the voxel pipeline's
// look, plus distance fog for consistency.

struct Camera {
    view_proj: mat4x4f,
    cam_pos: vec4f,
    sun_dir: vec4f,          // xyz = sun direction (unit), w = sun strength
    fog: vec4f,              // x = fog start (m), y = fog end (m), z = SM64 units per meter, w = ambient strength
    interp_pos: vec4f,       // xyz = interpolated Mario position (SM64 units)
    tick_pos: vec4f,         // xyz = tick position the geometry was authored at (SM64 units)
    sky_color: vec4f,        // xyz = sky/fog color, w = fill light strength
    sun_color: vec4f,        // xyz = sun color (linear RGB), w = model scale
    ambient_sky: vec4f,      // xyz = ambient sky tint, w = unused
    ambient_ground: vec4f,   // xyz = ambient ground tint, w = unused
};

@group(0) @binding(0) var<uniform> cam: Camera;
@group(0) @binding(1) var mario_sampler: sampler;
@group(0) @binding(2) var mario_texture: texture_2d<f32>;

struct VIn {
    @location(0) position: vec3f,
    @location(1) normal: vec3f,
    @location(2) color: vec3f,
    @location(3) uv: vec2f,
};

struct VOut {
    @builtin(position) clip: vec4f,
    @location(0) color: vec3f,
    @location(1) world_normal: vec3f,
    @location(2) world_pos: vec3f,
    @location(3) uv: vec2f,
};

// SM64 units per meter is passed via cam.fog.z; model_scale is in
// cam.sun_color.w (fog.w is ambient_strength for day/night cycle).
// Mario's vertex positions are raw SM64 units authored at cam.tick_pos;
// the CPU uploads them verbatim and we apply the per-frame translate
// (interp_pos - tick_pos) and model_scale here so the vertex buffer
// only needs to change when the geometry actually changes.

@vertex
fn vs_main(in: VIn) -> VOut {
    var out: VOut;
    // libsm64 outputs absolute positions in SM64 integer units, authored
    // at cam.tick_pos. Translate to the interpolated camera target
    // model_scale is in cam.sun_color.w (fog.w is ambient_strength for day/night)
    let model_scale = cam.sun_color.w;
    let sm64_pos = cam.interp_pos.xyz + (in.position - cam.tick_pos.xyz) * model_scale;
    let world_pos = sm64_pos / cam.fog.z;
    out.clip = cam.view_proj * vec4f(world_pos, 1.0);
    out.color = in.color;
    out.world_normal = normalize(in.normal);
    out.world_pos = world_pos;
    out.uv = in.uv;
    return out;
}

struct MarioFOut {
    @location(0) color: vec4f,
    @location(1) normal: vec4f,
    @location(2) linear_depth: vec4f,
};

@fragment
fn fs_main(in: VOut) -> MarioFOut {
    let normal = normalize(in.world_normal);
    let sun_dir = normalize(cam.sun_dir.xyz);
    let ndotl = dot(normal, sun_dir);

    let raw = clamp(ndotl * 0.5 + 0.5, 0.0, 1.0);
    let bands = 4.0;
    let quantized = floor(raw * bands + 0.5) / bands;
    let smooth_q = mix(quantized, raw, smoothstep(0.45, 0.55, fract(raw * bands)));
    let sky_tint = normalize(cam.sky_color.xyz + vec3f(0.001));
    let lit_tint = normalize(mix(vec3f(1.0), sky_tint, 0.35));
    let shadow_tint = normalize(mix(vec3f(0.5), sky_tint, 0.45));
    let sun = pow(smooth_q, 1.5) * cam.sun_dir.w * cam.sun_color.xyz * lit_tint;
    let fill = max(-ndotl, 0.0) * cam.sky_color.w;
    let hemi_t = clamp(0.5 + 0.5 * normal.y, 0.0, 1.0);
    let ambient = mix(cam.ambient_ground.xyz, cam.ambient_sky.xyz * shadow_tint, hemi_t) * cam.fog.w;

    let tex_color = textureSample(mario_texture, mario_sampler, in.uv);
    let main_color = mix(in.color, tex_color.rgb, tex_color.a);
    let lit = main_color * (ambient + sun + vec3f(fill));

    let dist = length(cam.cam_pos.xyz - in.world_pos);
    let fog_factor = clamp((cam.fog.y - dist) / (cam.fog.y - cam.fog.x), 0.0, 1.0);
    let final_color = mix(cam.sky_color.xyz, lit, fog_factor);

    var out: MarioFOut;
    out.color = vec4f(final_color, 1.0);
    out.normal = vec4f(normal, 0.0);  // w=0: exclude from edge detection
    out.linear_depth = vec4f(dist / 600.0, 0.0, 0.0, 0.0);
    return out;
}
