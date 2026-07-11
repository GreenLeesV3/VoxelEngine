//! Day/night cycle: computes sun direction, sky color, and lighting
//! parameters from a time-of-day value (0..24 hours).
//!
//! The cycle runs continuously, advancing `game_time` each frame. All
//! lighting parameters (sun direction, sun color/intensity, ambient
//! colors, sky/fog color) are derived from the time and passed to both
//! the voxel and Mario pipelines via their camera uniforms.

use glam::Vec3;

/// Seconds per game-day. At 120 real-seconds per cycle, a full day/night
/// takes 2 minutes of real time — long enough to appreciate, short enough
/// to see transitions.
const DAY_LENGTH_SECS: f32 = 120.0;

/// Computes all lighting parameters for the current time of day.
/// `game_time` is in seconds (unbounded — wraps modulo DAY_LENGTH_SECS).
pub struct DayNightParams {
    /// Normalized sun direction (points toward the sun from the scene).
    pub sun_dir: Vec3,
    /// Sun brightness multiplier (0 at night, 1 at noon).
    pub sun_strength: f32,
    /// Sun color (warm at dawn/dusk, white at noon, cool at night).
    pub sun_color: Vec3,
    /// Sky/fog color (blue at day, dark blue at night, orange at dawn/dusk).
    pub sky_color: Vec3,
    /// Fill light strength (bounce light from opposite direction).
    pub fill_strength: f32,
    /// Ambient light strength multiplier.
    pub ambient_strength: f32,
    /// Ambient sky tint (cool blue during day, dim at night).
    pub ambient_sky: Vec3,
    /// Ambient ground tint (warm during day, dim at night).
    pub ambient_ground: Vec3,
    /// Normalized time of day 0..1 (0 = midnight, 0.25 = dawn, 0.5 = noon, 0.75 = dusk).
    pub time_of_day: f32,
}

/// Compute lighting parameters from game_time (seconds).
pub fn compute(game_time: f32) -> DayNightParams {
    // Wrap time into 0..1 cycle.
    let t = (game_time / DAY_LENGTH_SECS).fract();
    // Sun angle: t=0 midnight (sun below), t=0.5 noon (sun overhead).
    // The sun sweeps east→west in a proper arc across the sky.
    // angle goes from -pi/2 (midnight, below) through 0 (horizon) to
    // +pi/2 (noon, overhead) and back to -pi/2 (next midnight).
    let sun_angle = (t * 2.0 - 0.5) * std::f32::consts::PI;
    let sun_height = sun_angle.sin(); // -1 (midnight) to +1 (noon)

    // Azimuth sweeps east→west over the full cycle. At dawn (t=0.25)
    // the sun is in the +X direction (east), at noon (t=0.5) it's
    // overhead, at dusk (t=0.75) it's in the -X direction (west).
    // Use cos to get a smooth 0→1→0 daylight arc and negate for
    // proper east→west direction.
    let sun_azimuth = -((t * 2.0 - 0.5) * std::f32::consts::PI).cos();

    // Sun direction: arcs across the sky from east to west.
    // X = azimuth (east→west sweep), Y = height (up/down), Z = slight
    // southward tilt for visual variety.
    let sun_dir = Vec3::new(sun_azimuth * sun_height.abs().max(0.15), sun_height, -0.2).normalize();

    // Daylight factor: 0 at night, 1 at full day. Smooth transition at horizon.
    let daylight = clamp01((sun_height + 0.1) * 2.5);

    // Dawn/dusk warmth: peaks when sun is near the horizon.
    let horizon_glow = clamp01(1.0 - (sun_height.abs() * 3.0));

    // Sun color: warm orange at horizon, white at noon, dim cool at night.
    let warm = Vec3::new(1.0, 0.6, 0.3);
    let white = Vec3::new(1.0, 0.95, 0.85);
    let night_tint = Vec3::new(0.3, 0.35, 0.5);
    let sun_color = if sun_height > 0.0 {
        warm.lerp(white, daylight)
    } else {
        night_tint
    };

    // Sun strength: zero at night, full at noon.
    let sun_strength = daylight.max(0.0) * 0.85;

    // Sky color: blue sky during day, dark navy at night, orange at dawn/dusk.
    let day_sky = Vec3::new(0.45, 0.66, 0.90);
    let night_sky = Vec3::new(0.03, 0.04, 0.08);
    let dusk_sky = Vec3::new(0.6, 0.35, 0.2);
    let sky_color = if sun_height > 0.05 {
        night_sky.lerp(day_sky, daylight)
    } else {
        // Blend night → dusk → day near the horizon.
        let glow = clamp01(sun_height + 0.15) / 0.2;
        night_sky.lerp(dusk_sky, glow).lerp(day_sky, daylight)
    };

    // Fill light: dimmer at night.
    let fill_strength = 0.12 * daylight.max(0.15);

    // Ambient: dimmer and cooler at night.
    let ambient_strength = 0.55 * daylight.max(0.15);
    let ambient_sky = Vec3::new(0.50, 0.58, 0.70).lerp(Vec3::new(0.15, 0.18, 0.25), 1.0 - daylight);
    let ambient_ground = Vec3::new(0.30, 0.27, 0.24).lerp(Vec3::new(0.08, 0.07, 0.06), 1.0 - daylight);

    DayNightParams {
        sun_dir,
        sun_strength,
        sun_color,
        sky_color,
        fill_strength,
        ambient_strength,
        ambient_sky,
        ambient_ground,
        time_of_day: t,
    }
}

/// Clear color (wgpu format) derived from the sky color.
pub fn clear_color(p: &DayNightParams) -> wgpu::Color {
    wgpu::Color {
        r: p.sky_color.x as f64,
        g: p.sky_color.y as f64,
        b: p.sky_color.z as f64,
        a: 1.0,
    }
}

fn clamp01(v: f32) -> f32 {
    v.max(0.0).min(1.0)
}
