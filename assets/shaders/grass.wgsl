// Grass blade pipeline: renders thin 3D blades standing up from grass
// voxels. Each blade is a 2-triangle quad with wind sway applied to the
// tip in the vertex shader. Alpha-blended, depth-tested.

struct Camera {
    view_proj: mat4x4f,
    cam_pos: vec4f,
    time: f32,           // game time for wind animation
    _pad0: f32,
    _pad1: f32,
    _pad2: f32,
};

@group(0) @binding(0) var<uniform> cam: Camera;

struct VIn {
    @location(0) position: vec3f,    // world position of this vertex (meters)
    @location(1) height_factor: f32, // 0=base, 1=tip — drives wind + color
};

struct VOut {
    @builtin(position) clip: vec4f,
    @location(0) height_factor: f32, // 0=base, 1=tip for color gradient
    @location(1) world_pos: vec3f,
};

@vertex
fn vs_main(in: VIn) -> VOut {
    var out: VOut;
    var world_pos = in.position;

    // Wind sway: offset blade tips (height_factor > 0) with time-based sin.
    // The blade base stays planted; only the tip moves.
    if (in.height_factor > 0.5) {
        let t = cam.time;
        let wind_x = sin(t * 1.5 + world_pos.x * 0.7 + world_pos.z * 0.5) * 0.15 * in.height_factor;
        let wind_z = cos(t * 1.1 + world_pos.z * 0.9 + world_pos.x * 0.3) * 0.10 * in.height_factor;
        world_pos.x += wind_x;
        world_pos.z += wind_z;
    }

    out.clip = cam.view_proj * vec4f(world_pos, 1.0);
    out.height_factor = in.height_factor;
    out.world_pos = world_pos;
    return out;
}

@fragment
fn fs_main(in: VOut) -> @location(0) vec4f {
    // Color gradient: dark green base → bright green tip
    let base_green = vec3f(0.18, 0.38, 0.12);
    let tip_green = vec3f(0.42, 0.72, 0.25);
    let color = mix(base_green, tip_green, in.height_factor);
    let ambient = 0.6;
    let lit = color * ambient;
    return vec4f(lit, 0.9);
}
