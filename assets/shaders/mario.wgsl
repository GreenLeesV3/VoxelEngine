// Mario pipeline: renders libsm64's dynamic per-frame geometry (up to
// 1024 triangles). Vertices come from sm64_mario_tick's geometry
// buffers: position (float3), normal (float3), color (float3), uv
// (float2). Textured with Mario's 704×64 RGBA atlas extracted from
// the ROM. Simple sun + ambient lighting matching the voxel pipeline's
// look, plus distance fog for consistency.

struct Camera {
    view_proj: mat4x4f,
    cam_pos: vec4f,
    sun_dir: vec4f,          // xyz = direction the sun shines toward (unit)
    fog: vec4f,              // x = fog start (m), y = fog end (m), z = SM64 units per meter, w = unused
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

const SKY_COLOR = vec3f(0.45, 0.66, 0.90);
const AMBIENT_SKY = vec3f(0.40, 0.46, 0.56);
const AMBIENT_GROUND = vec3f(0.24, 0.22, 0.19);
const AMBIENT_STRENGTH = 0.35;
const SUN_COLOR = vec3f(1.0, 0.95, 0.85);
const SUN_STRENGTH = 0.45;
const FOG_COLOR = vec3f(0.45, 0.66, 0.90);

// SM64 units per meter is passed via cam.fog.z (set by the CPU each frame).
// Mario's vertex positions are in SM64 units; divide by this to get meters.

@vertex
fn vs_main(in: VIn) -> VOut {
    var out: VOut;
    // libsm64 outputs absolute positions in SM64 integer units.
    // Convert to meters using the uniform scale (cam.fog.z).
    let world_pos = in.position / cam.fog.z;
    out.clip = cam.view_proj * vec4f(world_pos, 1.0);
    out.color = in.color;
    out.world_normal = normalize(in.normal);
    out.world_pos = world_pos;
    out.uv = in.uv;
    return out;
}

@fragment
fn fs_main(in: VOut) -> @location(0) vec4f {
    let normal = normalize(in.world_normal);
    let sun_dir = normalize(cam.sun_dir.xyz);

    // Lighting: simple half-Lambert (matches libsm64's reference renderer)
    let light = 0.5 + 0.5 * clamp(dot(normal, sun_dir), 0.0, 1.0);

    // Alpha-masked overlay: vertex color is the base body color
    // (skin, hat, overalls), texture overrides only where alpha=1
    // (eyes, buttons, sideburns, emblem). This is exactly how
    // libsm64's reference GL renderer does it.
    let tex_color = textureSample(mario_texture, mario_sampler, in.uv);
    let main_color = mix(in.color, tex_color.rgb, tex_color.a);
    let lit = main_color * light;

    // Distance fog — matches the voxel pipeline
    let dist = length(cam.cam_pos.xyz - in.world_pos);
    let fog_factor = clamp((cam.fog.y - dist) / (cam.fog.y - cam.fog.x), 0.0, 1.0);
    let final_color = mix(FOG_COLOR, lit, fog_factor);

    return vec4f(final_color, 1.0);
}
