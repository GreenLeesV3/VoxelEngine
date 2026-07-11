//! Day/night cycle: computes sun direction, sky color, and lighting
//! parameters from a time-of-day value.
//!
//! Uses a 6-phase smoothstep-weighted time-of-day system inspired by
//! CazToon's sky_timeline.glsl. Instead of hard phase boundaries, all
//! phase weights are computed via smoothstep from a single normalized
//! sun angle, producing naturally continuous transitions with no pops.
//!
//! Phases: day, sunset, blue hour, night, sunrise, dawn.
//! Cycle: 10 min day + 1.5 min sunset + 1 min blue hour + 7 min night
//!        + 1 min dawn + 1.5 min sunrise = 22 min total.

use glam::Vec3;

/// Cycle timing (seconds of real time).
const DAY_SECS: f32 = 600.0;       // 10 minutes
const SUNSET_SECS: f32 = 90.0;     // 1.5 minutes
const BLUE_HOUR_SECS: f32 = 60.0;  // 1 minute
const NIGHT_SECS: f32 = 420.0;     // 7 minutes
const DAWN_SECS: f32 = 60.0;       // 1 minute
const SUNRISE_SECS: f32 = 90.0;    // 1.5 minutes
const CYCLE_SECS: f32 = DAY_SECS + SUNSET_SECS + BLUE_HOUR_SECS + NIGHT_SECS + DAWN_SECS + SUNRISE_SECS; // 1320

/// Phase start times within the cycle.
const DAY_START: f32 = 0.0;
const SUNSET_START: f32 = DAY_SECS;                                    // 600
const BLUE_HOUR_START: f32 = SUNSET_START + SUNSET_SECS;               // 690
const NIGHT_START: f32 = BLUE_HOUR_START + BLUE_HOUR_SECS;             // 750
const DAWN_START: f32 = NIGHT_START + NIGHT_SECS;                      // 1170
const SUNRISE_START: f32 = DAWN_START + DAWN_SECS;                     // 1230
// CYCLE_END = CYCLE_SECS = 1320

/// Per-phase sky color constants (zenith colors from CazToon).
const DAY_SKY: Vec3 = Vec3::new(0.45, 0.66, 0.90);
const SUNSET_SKY: Vec3 = Vec3::new(0.95, 0.45, 0.25);
const BLUE_HOUR_SKY: Vec3 = Vec3::new(0.20, 0.25, 0.55);
const NIGHT_SKY: Vec3 = Vec3::new(0.03, 0.04, 0.08);
const DAWN_SKY: Vec3 = Vec3::new(0.12, 0.18, 0.45);
const SUNRISE_SKY: Vec3 = Vec3::new(0.65, 0.45, 0.55);

/// Per-phase brightness values (from CazToon's getTimelineBrightness).
const DAY_BRIGHTNESS: f32 = 1.0;
const SUNSET_BRIGHTNESS: f32 = 0.85;
const BLUE_HOUR_BRIGHTNESS: f32 = 0.45;
const NIGHT_BRIGHTNESS: f32 = 0.04;
const DAWN_BRIGHTNESS: f32 = 0.45;
const SUNRISE_BRIGHTNESS: f32 = 0.80;

/// Lighting parameters computed from game_time.
pub struct DayNightParams {
    pub sun_dir: Vec3,
    pub sun_strength: f32,
    pub sun_color: Vec3,
    pub sky_color: Vec3,
    pub fill_strength: f32,
    pub ambient_strength: f32,
    pub ambient_sky: Vec3,
    pub ambient_ground: Vec3,
}

/// Phase weights — each is 0..1, all sum to ~1.0. Computed via smoothstep
/// from the normalized sun angle so transitions are continuous.
struct TimeWeights {
    day: f32,
    sunset: f32,
    blue_hour: f32,
    night: f32,
    sunrise: f32,
    dawn: f32,
}

/// Compute phase weights from the normalized cycle position (0..1).
/// Edges are derived from the actual timing constants so the user's
/// requested phase durations are authoritative.
fn get_time_weights(cycle_t: f32) -> TimeWeights {
    let t = cycle_t / CYCLE_SECS;

    // Convert phase boundaries to normalized 0..1 positions.
    let day_e = DAY_START / CYCLE_SECS;
    let sunset_s = SUNSET_START / CYCLE_SECS;
    let sunset_e = BLUE_HOUR_START / CYCLE_SECS;
    let blue_e = NIGHT_START / CYCLE_SECS;
    let night_e = DAWN_START / CYCLE_SECS;
    let dawn_e = SUNRISE_START / CYCLE_SECS;
    let sunrise_e = 1.0; // wraps to cycle end

    // Overlap regions for smooth transitions: each phase ramps in
    // over a small normalized width and out at the next boundary.
    let ramp = 0.005; // normalized overlap width

    let w = TimeWeights {
        day: smoothstep(day_e - ramp, day_e + ramp, t)
            * (1.0 - smoothstep(sunset_s - ramp, sunset_s + ramp, t)),
        sunset: smoothstep(sunset_s - ramp, sunset_s + ramp, t)
            * (1.0 - smoothstep(sunset_e - ramp, sunset_e + ramp, t)),
        blue_hour: smoothstep(sunset_e - ramp, sunset_e + ramp, t)
            * (1.0 - smoothstep(blue_e - ramp, blue_e + ramp, t)),
        night: smoothstep(blue_e - ramp, blue_e + ramp, t)
            * (1.0 - smoothstep(night_e - ramp, night_e + ramp, t)),
        dawn: smoothstep(night_e - ramp, night_e + ramp, t)
            * (1.0 - smoothstep(dawn_e - ramp, dawn_e + ramp, t)),
        // Sunrise wraps around the cycle boundary (0/1).
        sunrise: smoothstep(dawn_e - ramp, dawn_e + ramp, t)
            + (1.0 - smoothstep(sunrise_e - ramp, sunrise_e + ramp, t))
            + (1.0 - smoothstep(0.0, ramp, t)),
    };

    // Normalize so weights sum to 1.0
    let total = w.day + w.sunset + w.blue_hour + w.night + w.dawn + w.sunrise;
    if total > 0.001 {
        let inv = 1.0 / total;
        TimeWeights {
            day: w.day * inv,
            sunset: w.sunset * inv,
            blue_hour: w.blue_hour * inv,
            night: w.night * inv,
            dawn: w.dawn * inv,
            sunrise: w.sunrise * inv,
        }
    } else {
        TimeWeights { day: 1.0, sunset: 0.0, blue_hour: 0.0, night: 0.0, dawn: 0.0, sunrise: 0.0 }
    }
}

/// Compute lighting parameters from game_time (seconds).
pub fn compute(game_time: f32) -> DayNightParams {
    let cycle_t = (game_time % CYCLE_SECS).max(0.0);
    let w = get_time_weights(cycle_t);
    let t = cycle_t / CYCLE_SECS;

    // Brightness: weighted sum of per-phase brightness values.
    let brightness = w.day * DAY_BRIGHTNESS
        + w.sunset * SUNSET_BRIGHTNESS
        + w.blue_hour * BLUE_HOUR_BRIGHTNESS
        + w.night * NIGHT_BRIGHTNESS
        + w.dawn * DAWN_BRIGHTNESS
        + w.sunrise * SUNRISE_BRIGHTNESS;

    // Sun height: arcs across the sky during day, dips below at night.
    // During day (t=0..0.5): sin(t * 2π) gives 0→1→0 arc.
    // During night (t=0.5..1.0): negative, dipping lowest at midnight.
    let sun_height = if t < 0.5 {
        (t * 2.0 * std::f32::consts::PI).sin()
    } else {
        // Night: sun below horizon, gentle dip
        -0.3 - 0.5 * ((t - 0.5) * 2.0 * std::f32::consts::PI).sin().abs()
    };

    // Azimuth: east→west sweep during day, west→east during night.
    let azimuth_phase = if t < 0.5 { t * 2.0 } else { 1.0 - (t - 0.5) * 2.0 };
    let sun_azimuth = (azimuth_phase - 0.5) * -2.0;
    let sun_dir = Vec3::new(
        sun_azimuth * sun_height.abs().max(0.15),
        sun_height,
        -0.2,
    ).normalize();

    // Sun color: warm at sunset/sunrise, white at noon, cool at night.
    let warm = Vec3::new(1.0, 0.6, 0.3);
    let white = Vec3::new(1.0, 0.95, 0.85);
    let night_tint = Vec3::new(0.3, 0.35, 0.5);
    let sunset_glow = w.sunset + w.sunrise;
    let sun_color = if sun_height > 0.0 {
        warm.lerp(white, brightness * (1.0 - sunset_glow * 0.7))
    } else {
        night_tint
    };

    // Sun strength: zero at night, full at noon.
    let sun_strength = brightness.max(0.0) * 0.85;

    // Sky color: weighted blend of all 6 phase colors.
    // Special blends for day↔sunset and sunset↔blue hour transitions.
    let mut sky = DAY_SKY * w.day
        + SUNSET_SKY * w.sunset
        + BLUE_HOUR_SKY * w.blue_hour
        + NIGHT_SKY * w.night
        + DAWN_SKY * w.dawn
        + SUNRISE_SKY * w.sunrise;

    // Day↔sunset warm blend
    let day_sunset_mix = (w.day.min(w.sunset + w.sunrise) * 2.5).min(1.0);
    sky = sky.lerp(Vec3::new(0.92, 0.55, 0.35), day_sunset_mix * 0.5);

    // Sunset↔blue hour purple blend
    let sunset_blue_mix = (w.sunset.min(w.blue_hour) * 2.0).min(1.0);
    sky = sky.lerp(Vec3::new(0.40, 0.15, 0.75), sunset_blue_mix * 0.5);

    // Fill light: dimmer at night.
    let fill_strength = 0.12 * brightness.max(0.15);

    // Ambient: dimmer and cooler at night.
    let ambient_strength = 0.55 * brightness.max(0.15);
    let ambient_sky = Vec3::new(0.50, 0.58, 0.70).lerp(Vec3::new(0.15, 0.18, 0.25), 1.0 - brightness);
    let ambient_ground = Vec3::new(0.30, 0.27, 0.24).lerp(Vec3::new(0.08, 0.07, 0.06), 1.0 - brightness);

    DayNightParams {
        sun_dir,
        sun_strength,
        sun_color,
        sky_color: sky,
        fill_strength,
        ambient_strength,
        ambient_sky,
        ambient_ground,
    }
}

fn smoothstep(edge0: f32, edge1: f32, x: f32) -> f32 {
    let t = ((x - edge0) / (edge1 - edge0)).max(0.0).min(1.0);
    t * t * (3.0 - 2.0 * t)
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
