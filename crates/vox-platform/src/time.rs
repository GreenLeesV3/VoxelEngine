//! Fixed-timestep frame clock.
//!
//! Accumulates real elapsed time and converts it into a whole number of
//! fixed physics steps plus a sub-step interpolation remainder (`alpha`).
//! All durations are in seconds (SI).

use std::time::Instant;

/// Hard cap on the real time credited to a single frame, in seconds.
///
/// Survives debugger pauses, window drags, and OS stalls: without the clamp a
/// multi-second hitch would flood the accumulator and freeze the game in a
/// catch-up marathon.
pub const MAX_FRAME_DT: f32 = 0.25;

/// Hard cap on fixed steps emitted per frame (death-spiral guard).
///
/// If simulation is too slow to run in real time, emitting *more* steps per
/// frame makes each frame slower still, which demands even more steps — a
/// death spiral. Beyond this cap the clock drops the un-simulated whole steps
/// (simulated time dilates), which is survivable.
pub const MAX_STEPS_PER_FRAME: u32 = 4;

/// Timing outputs for one rendered frame.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct FrameTiming {
    /// Real elapsed seconds since the previous frame, clamped to
    /// `[0, MAX_FRAME_DT]`.
    pub dt_frame: f32,
    /// Number of fixed physics steps to run this frame
    /// (`0..=MAX_STEPS_PER_FRAME`).
    pub physics_steps: u32,
    /// Sub-step remainder as a fraction of the fixed step, in `[0, 1)`.
    /// Use it to interpolate render state between the two most recent
    /// physics states.
    pub alpha: f32,
}

/// Fixed-timestep accumulator clock.
///
/// The fixed timestep is injected by the caller (vox-platform deliberately
/// does not depend on vox-core, where the engine constant will live).
#[derive(Debug)]
pub struct FrameClock {
    fixed_dt: f32,
    accumulator: f32,
    last_instant: Instant,
}

impl FrameClock {
    /// Create a clock with the given fixed timestep in seconds.
    ///
    /// # Panics
    /// Panics if `fixed_dt` is not strictly positive and finite.
    pub fn new(fixed_dt: f32) -> Self {
        assert!(
            fixed_dt.is_finite() && fixed_dt > 0.0,
            "fixed_dt must be a positive, finite number of seconds (got {fixed_dt})"
        );
        Self {
            fixed_dt,
            accumulator: 0.0,
            last_instant: Instant::now(),
        }
    }

    /// Advance using the real wall clock. Call exactly once per rendered
    /// frame.
    pub fn tick(&mut self) -> FrameTiming {
        let now = Instant::now();
        let dt = now.duration_since(self.last_instant).as_secs_f32();
        self.last_instant = now;
        self.advance(dt)
    }

    /// Advance the accumulator by `dt` seconds.
    ///
    /// This is the core logic that [`FrameClock::tick`] wraps with the real
    /// clock; it is public so tests (and later, deterministic replay) can
    /// drive the clock with synthetic time.
    pub fn advance(&mut self, dt: f32) -> FrameTiming {
        // Non-finite dt cannot happen from the real clock; treat it as a
        // dropped frame rather than poisoning the accumulator with NaN.
        let dt_frame = if dt.is_finite() {
            dt.clamp(0.0, MAX_FRAME_DT)
        } else {
            0.0
        };
        self.accumulator += dt_frame;

        // Whole steps available. The f32 -> u32 cast truncates toward zero,
        // which is floor() for non-negative values (and saturates on
        // overflow).
        let whole_steps = (self.accumulator / self.fixed_dt) as u32;

        // Consume *all* whole steps from the accumulator, including any
        // beyond the cap: if the simulation cannot keep up, banking the
        // backlog would demand even more steps next frame (death spiral).
        // Dropping the excess dilates simulated time instead. The fractional
        // remainder is kept so alpha stays smooth.
        self.accumulator = (self.accumulator - whole_steps as f32 * self.fixed_dt).max(0.0);
        let physics_steps = whole_steps.min(MAX_STEPS_PER_FRAME);

        // Remainder is < fixed_dt by construction; the clamp guards f32
        // rounding at the boundary so alpha is always in [0, 1).
        let alpha = (self.accumulator / self.fixed_dt).clamp(0.0, 1.0 - f32::EPSILON);

        FrameTiming {
            dt_frame,
            physics_steps,
            alpha,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 60 Hz fixed step used by all tests.
    const DT: f32 = 1.0 / 60.0;
    const TOL: f32 = 1e-3;

    fn clock() -> FrameClock {
        FrameClock::new(DT)
    }

    #[test]
    fn frame_of_one_and_a_half_steps_emits_one_step_with_half_alpha() {
        let mut clock = clock();
        let timing = clock.advance(1.5 * DT);
        assert_eq!(timing.physics_steps, 1);
        assert!(
            (timing.alpha - 0.5).abs() < TOL,
            "alpha was {}",
            timing.alpha
        );
        assert!((timing.dt_frame - 1.5 * DT).abs() < TOL);
    }

    #[test]
    fn frame_of_three_point_seven_steps_emits_three_steps() {
        let mut clock = clock();
        let timing = clock.advance(3.7 * DT);
        assert_eq!(timing.physics_steps, 3);
        assert!(
            (timing.alpha - 0.7).abs() < TOL,
            "alpha was {}",
            timing.alpha
        );
    }

    #[test]
    fn fractional_time_accumulates_across_frames() {
        let mut clock = clock();
        let first = clock.advance(0.75 * DT);
        assert_eq!(first.physics_steps, 0);
        assert!(
            (first.alpha - 0.75).abs() < TOL,
            "alpha was {}",
            first.alpha
        );
        let second = clock.advance(0.75 * DT);
        assert_eq!(second.physics_steps, 1);
        assert!(
            (second.alpha - 0.5).abs() < TOL,
            "alpha was {}",
            second.alpha
        );
    }

    #[test]
    fn stall_clamps_dt_and_caps_steps() {
        let mut clock = clock();
        let timing = clock.advance(0.3);
        assert_eq!(timing.dt_frame, MAX_FRAME_DT);
        assert_eq!(timing.physics_steps, MAX_STEPS_PER_FRAME);
        assert!(
            (0.0..1.0).contains(&timing.alpha),
            "alpha was {}",
            timing.alpha
        );
    }

    #[test]
    fn capped_frame_drops_excess_whole_steps() {
        let mut clock = clock();
        // 0.25 s at 60 Hz is ~15 whole steps; only 4 may run. The un-run
        // steps must be dropped, not banked: an idle frame afterwards emits
        // zero steps.
        clock.advance(0.25);
        let next = clock.advance(0.0);
        assert_eq!(next.physics_steps, 0);
    }

    #[test]
    fn zero_dt_emits_nothing() {
        let mut clock = clock();
        let timing = clock.advance(0.0);
        assert_eq!(timing.physics_steps, 0);
        assert_eq!(timing.dt_frame, 0.0);
        assert_eq!(timing.alpha, 0.0);
    }

    #[test]
    fn negative_dt_is_treated_as_zero() {
        let mut clock = clock();
        let timing = clock.advance(-1.0);
        assert_eq!(timing.dt_frame, 0.0);
        assert_eq!(timing.physics_steps, 0);
    }

    #[test]
    fn alpha_stays_in_unit_range_over_many_odd_frames() {
        let mut clock = clock();
        let dts = [
            0.0,
            0.001,
            DT,
            1.5 * DT,
            0.049,
            0.1,
            0.24,
            0.25,
            0.3,
            2.0,
            DT * 0.999,
            DT * 1.001,
        ];
        for _ in 0..50 {
            for &dt in &dts {
                let timing = clock.advance(dt);
                assert!(
                    (0.0..1.0).contains(&timing.alpha),
                    "alpha {} out of [0,1) after dt {dt}",
                    timing.alpha
                );
                assert!(timing.physics_steps <= MAX_STEPS_PER_FRAME);
            }
        }
    }

    #[test]
    fn tick_reads_the_real_clock() {
        let mut clock = clock();
        std::thread::sleep(std::time::Duration::from_millis(20));
        let timing = clock.tick();
        assert!(timing.dt_frame > 0.0);
        assert!(timing.dt_frame <= MAX_FRAME_DT);
    }

    #[test]
    #[should_panic(expected = "fixed_dt")]
    fn zero_fixed_dt_panics() {
        let _ = FrameClock::new(0.0);
    }
}
