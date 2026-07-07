//! A tiny per-label frame-timing profiler: a fixed-size ring buffer per
//! system, fed by an RAII scope guard. Lives in vox-core so lower crates
//! (physics, world, mesh) can eventually be timed too, not just vox-app.

use std::time::Instant;

/// Samples kept per label (≈4 s of history at 60 Hz).
const RING_LEN: usize = 240;

/// A rolling window of one label's per-frame timings, in milliseconds.
#[derive(Clone, Debug)]
pub struct TimingRing {
    samples: [f32; RING_LEN],
    /// Index the next `push` writes to.
    head: usize,
    /// Number of valid samples (grows to `RING_LEN`, then stays there).
    len: usize,
}

impl Default for TimingRing {
    fn default() -> Self {
        Self {
            samples: [0.0; RING_LEN],
            head: 0,
            len: 0,
        }
    }
}

impl TimingRing {
    pub fn new() -> Self {
        Self::default()
    }

    /// Record one sample, in milliseconds.
    pub fn push(&mut self, ms: f32) {
        self.samples[self.head] = ms;
        self.head = (self.head + 1) % RING_LEN;
        self.len = (self.len + 1).min(RING_LEN);
    }

    /// Most recently recorded sample, or 0.0 if empty.
    pub fn last(&self) -> f32 {
        if self.len == 0 {
            0.0
        } else {
            let idx = (self.head + RING_LEN - 1) % RING_LEN;
            self.samples[idx]
        }
    }

    /// Mean of all recorded samples, or 0.0 if empty.
    pub fn average(&self) -> f32 {
        if self.len == 0 {
            return 0.0;
        }
        self.oldest_to_newest().sum::<f32>() / self.len as f32
    }

    /// Samples in chronological order (oldest first), for plotting.
    pub fn oldest_to_newest(&self) -> impl Iterator<Item = f32> + '_ {
        let start = if self.len < RING_LEN { 0 } else { self.head };
        (0..self.len).map(move |i| self.samples[(start + i) % RING_LEN])
    }
}

/// Per-frame timings for the engine's major phases.
#[derive(Clone, Debug, Default)]
pub struct FrameProfile {
    pub input: TimingRing,
    pub player: TimingRing,
    pub tools: TimingRing,
    pub physics: TimingRing,
    pub remesh: TimingRing,
    pub render: TimingRing,
}

impl FrameProfile {
    pub fn new() -> Self {
        Self::default()
    }

    /// Iterate all labeled rings for display (label, ring).
    pub fn labeled(&self) -> [(&'static str, &TimingRing); 6] {
        [
            ("input", &self.input),
            ("player", &self.player),
            ("tools", &self.tools),
            ("physics", &self.physics),
            ("remesh", &self.remesh),
            ("render", &self.render),
        ]
    }
}

/// RAII scope: records elapsed wall-clock time into `ring` when dropped.
/// `let _t = ScopedTimer::new(&mut profile.physics);` at the top of a block.
pub struct ScopedTimer<'a> {
    ring: &'a mut TimingRing,
    start: Instant,
}

impl<'a> ScopedTimer<'a> {
    pub fn new(ring: &'a mut TimingRing) -> Self {
        Self {
            ring,
            start: Instant::now(),
        }
    }
}

impl Drop for ScopedTimer<'_> {
    fn drop(&mut self) {
        self.ring.push(self.start.elapsed().as_secs_f32() * 1000.0);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::thread::sleep;
    use std::time::Duration;

    #[test]
    fn ring_tracks_last_and_average() {
        let mut ring = TimingRing::new();
        assert_eq!(ring.last(), 0.0);
        assert_eq!(ring.average(), 0.0);

        ring.push(1.0);
        ring.push(2.0);
        ring.push(3.0);
        assert_eq!(ring.last(), 3.0);
        assert!((ring.average() - 2.0).abs() < 1e-6);
        assert_eq!(
            ring.oldest_to_newest().collect::<Vec<_>>(),
            vec![1.0, 2.0, 3.0]
        );
    }

    #[test]
    fn ring_wraps_after_capacity() {
        let mut ring = TimingRing::new();
        for i in 0..RING_LEN + 5 {
            ring.push(i as f32);
        }
        // Oldest 5 samples (0..5) must have been evicted.
        let values: Vec<f32> = ring.oldest_to_newest().collect();
        assert_eq!(values.len(), RING_LEN);
        assert_eq!(values[0], 5.0);
        assert_eq!(*values.last().unwrap(), (RING_LEN + 4) as f32);
        assert_eq!(ring.last(), (RING_LEN + 4) as f32);
    }

    #[test]
    fn scoped_timer_records_a_positive_duration() {
        let mut ring = TimingRing::new();
        {
            let _t = ScopedTimer::new(&mut ring);
            sleep(Duration::from_millis(2));
        }
        assert!(ring.last() > 0.0, "elapsed time must be recorded");
    }

    #[test]
    fn frame_profile_labeled_covers_all_six_phases() {
        let profile = FrameProfile::new();
        let labels: Vec<&str> = profile.labeled().iter().map(|(l, _)| *l).collect();
        assert_eq!(
            labels,
            vec!["input", "player", "tools", "physics", "remesh", "render"]
        );
    }
}
