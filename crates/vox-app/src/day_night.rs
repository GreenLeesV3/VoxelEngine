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
const SUNSET_SECS: f32 = 90.0;     // 1.5 minutes (day→night transition)
const NIGHT_SECS: f32 = 420.0;     // 7 minutes
const SUNRISE_SECS: f32 = 90.0;    // 1.5 minutes (night→day transition)
const CYCLE_SECS: f32 = DAY_SECS + SUNSET_SECS + NIGHT_SECS + SUNRISE_SECS; // 1200

/// Phase boundaries (start times within the cycle).
const DAY_END: f32 = DAY_SECS;                          // 600
const SUNSET_END: f32 = DAY_END + SUNSET_SECS;          // 690
const NIGHT_END: f32 = SUNSET_END + NIGHT_SECS;         // 1110
// SUNRISE_END = CYCLE_SECS = 1200

/// Computes all lighting parameters for the current time of day.
/// `game_time` is in seconds (unbounded — wraps modulo CYCLE_SECS).
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
    // Cycle layout:
    //   0..600     DAY      — full daylight, sun arcs overhead
    //   600..690   SUNSET   — sun descends to horizon, warm light
    //   690..1110  NIGHT    — dark, stars
    //   1110..1200 SUNRISE  — sun rises from horizon, warm light

    let (sun_height, azimuth_phase, daylight, horizon_glow);

    if cycle_t < DAY_END {
        // DAY: sun arcs from east horizon → zenith → west horizon.
        // Starts at sin(0)=0 (matching sunrise end) and ends at sin(PI)=0
        // (matching sunset start).
        let day_t = cycle_t / DAY_END; // 0..1
        let angle = day_t * std::f32::consts::PI;
        sun_height = angle.sin(); // 0→1→0
        azimuth_phase = day_t; // 0=east, 1=west
        daylight = clamp01(sun_height * 1.8);
        horizon_glow = clamp01(1.0 - sun_height * 4.0);
    } else if cycle_t < SUNSET_END {
        // SUNSET: sun descends from the horizon into the start-of-night
        // depth. Continuous with day end (sin(PI)=0) and night start (-0.3).
        let sunset_t = (cycle_t - DAY_END) / SUNSET_SECS; // 0..1
        sun_height = sunset_t * -0.3; // 0→-0.3
        azimuth_phase = 1.0; // west
        daylight = clamp01((1.0 - sunset_t) * 0.6);
        horizon_glow = 1.0;
    } else if cycle_t < NIGHT_END {
        // NIGHT: sun well below horizon. Starts and ends at -0.3
        // (matching sunset end and sunrise start).
        let night_t = (cycle_t - SUNSET_END) / NIGHT_SECS; // 0..1
        sun_height = -0.3 - 0.5 * (night_t * std::f32::consts::PI).sin();
        azimuth_phase = 1.0 - night_t; // west→east
        daylight = 0.0;
        horizon_glow = 0.0;
    } else {
        // SUNRISE: sun rises from the start-of-night depth up to the
        // horizon. Continuous with night end (-0.3) and day start (0).
        let sunrise_t = (cycle_t - NIGHT_END) / SUNRISE_SECS; // 0..1
        sun_height = -0.3 + sunrise_t * 0.3; // -0.3→0
        azimuth_phase = 0.0; // east
        daylight = clamp01(sunrise_t * 0.6);
        horizon_glow = 1.0;
    }

    // Sun azimuth: 0 = east (+X), 1 = west (-X).
    let sun_azimuth = (azimuth_phase - 0.5) * -2.0; // 1→-1 east→west
    let sun_dir = Vec3::new(
        sun_azimuth * sun_height.abs().max(0.15),
        sun_height,
        -0.2,
    ).normalize();

    // Sun color: warm orange at horizon (driven by horizon_glow),
    // white at noon, dim cool at night.
    let warm = Vec3::new(1.0, 0.6, 0.3);
    let white = Vec3::new(1.0, 0.95, 0.85);
    let night_tint = Vec3::new(0.3, 0.35, 0.5);
    let sun_color = if sun_height > 0.0 {
        // Reduce white blend when horizon_glow is high so warm tones
        // dominate at sunrise/sunset.
        warm.lerp(white, daylight * (1.0 - horizon_glow * 0.7))
    } else {
        night_tint
    };

    // Sun strength: zero at night, full at noon.
    let sun_strength = daylight.max(0.0) * 0.85;

    // Sky color: blue sky during day, dark navy at night, orange at
    // dawn/dusk (driven by horizon_glow).
    let day_sky = Vec3::new(0.45, 0.66, 0.90);
    let night_sky = Vec3::new(0.03, 0.04, 0.08);
    let dusk_sky = Vec3::new(0.6, 0.35, 0.2);
    let sky_color = if sun_height > 0.05 {
        // Mix in dusk tint based on horizon_glow for warm sunrises/sunsets.
        day_sky.lerp(dusk_sky, horizon_glow * 0.5).lerp(night_sky, 1.0 - daylight)
    } else {
        let glow = clamp01(sun_height + 0.15) / 0.2;
        night_sky.lerp(dusk_sky, glow * horizon_glow).lerp(day_sky, daylight)
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
