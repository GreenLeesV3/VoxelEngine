//! Day/night cycle: computes sun direction, sky color, and lighting
//! parameters from a time-of-day value (0..24 hours).
//!
//! The cycle runs continuously, advancing `game_time` each frame. All
//! lighting parameters (sun direction, sun color/intensity, ambient
//! colors, sky/fog color) are derived from the time and passed to both
//! the voxel and Mario pipelines via their camera uniforms.

use glam::Vec3;

/// Day/night cycle timing (in seconds of real time):
/// 10 min day, 1.5 min sunrise, 7 min night, 1.5 min sunset = 20 min total.
const DAY_SECS: f32 = 600.0;       // 10 minutes
const SUNRISE_SECS: f32 = 90.0;    // 1.5 minutes
const NIGHT_SECS: f32 = 420.0;     // 7 minutes
const SUNSET_SECS: f32 = 90.0;     // 1.5 minutes
const CYCLE_SECS: f32 = DAY_SECS + SUNRISE_SECS + NIGHT_SECS + SUNSET_SECS; // 1200

/// Phase boundaries (start times within the cycle).
const DAY_END: f32 = DAY_SECS;                          // 600
const SUNRISE_END: f32 = DAY_END + SUNRISE_SECS;        // 690
const NIGHT_END: f32 = SUNRISE_END + NIGHT_SECS;        // 1110
// SUNSET_END = CYCLE_SECS = 1200

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
    pub ambient_strength: f32,
    /// Ambient sky tint (cool blue during day, dim at night).
    pub ambient_sky: Vec3,
    /// Ambient ground tint (warm during day, dim at night).
    pub ambient_ground: Vec3,
    /// Normalized time of day 0..1.
    pub time_of_day: f32,
}

/// Compute lighting parameters from game_time (seconds).
pub fn compute(game_time: f32) -> DayNightParams {
    // Wrap into the 20-minute cycle.
    let cycle_t = (game_time % CYCLE_SECS).max(0.0);

    // Determine which phase we're in and compute a normalized sun
    // height (0=horizon, 1=zenith) and sun azimuth for each phase.
    //
    // Cycle layout (starts at dawn/sunrise):
    //   0..600         DAY        (sun rises→zenith→descends)
    //   600..690       SUNRISE→   (wait, this is actually "dusk/sunset"
    //                              — naming: phase 1 = day, phase 2 =
    //                              sunset transition, phase 3 = night,
    //                              phase 4 = sunrise transition)
    //
    // Actually let's lay it out as the user experiences it:
    //   0..600     DAY      — full daylight, sun arcs overhead
    //   600..690   SUNSET   — sun descends to horizon, warm light
    //   690..1110  NIGHT    — dark, stars, moon-ish
    //   1110..1200 SUNRISE  — sun rises from horizon, warm light

    let (sun_height, azimuth_phase, daylight, horizon_glow);

    if cycle_t < DAY_END {
        // DAY: sun arcs from east horizon → zenith → west horizon.
        // Map 0..DAY_END to angle 0..pi (east to west).
        let day_t = cycle_t / DAY_END; // 0..1
        let angle = day_t * std::f32::consts::PI;
        sun_height = angle.sin(); // 0→1→0
        azimuth_phase = day_t; // 0=east, 1=west
        daylight = clamp01(sun_height * 1.8);
        horizon_glow = clamp01(1.0 - sun_height * 4.0);
    } else if cycle_t < SUNRISE_END {
        // SUNSET: sun drops from horizon to below (0→-1).
        let sunset_t = (cycle_t - DAY_END) / SUNRISE_SECS; // 0..1
        sun_height = (1.0 - sunset_t) * 0.15; // 0.15→0 (just below horizon)
        // Continue azimuth westward.
        azimuth_phase = 1.0;
        daylight = clamp01((1.0 - sunset_t) * 0.6);
        horizon_glow = 1.0; // peak sunset glow
    } else if cycle_t < NIGHT_END {
        // NIGHT: sun well below horizon.
        let night_t = (cycle_t - SUNRISE_END) / NIGHT_SECS; // 0..1
        // Sun dips lowest at midpoint, then starts rising.
        sun_height = -0.3 - 0.5 * (night_t * std::f32::consts::PI).sin();
        // Azimuth sweeps from west back toward east during night.
        azimuth_phase = 1.0 - night_t;
        daylight = 0.0;
        horizon_glow = 0.0;
    } else {
        // SUNRISE: sun rises from below horizon toward east.
        let sunrise_t = (cycle_t - NIGHT_END) / SUNSET_SECS; // 0..1
        sun_height = sunrise_t * 0.15; // 0→0.15 (just above horizon)
        azimuth_phase = 0.0; // east
        daylight = clamp01(sunrise_t * 0.6);
        horizon_glow = 1.0; // peak sunrise glow
    }

    // Sun azimuth: 0 = east (+X), 0.5 = overhead, 1 = west (-X).
    let sun_azimuth = (azimuth_phase - 0.5) * -2.0; // 1→-1 east→west
    let sun_dir = Vec3::new(
        sun_azimuth * sun_height.abs().max(0.15),
        sun_height,
        -0.2,
    ).normalize();

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
        time_of_day: cycle_t / CYCLE_SECS,
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
