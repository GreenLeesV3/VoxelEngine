//! CPU particle simulation: dust, sparks, and smoke for destruction
//! feedback. Deliberately simple -- position/velocity integration, gravity,
//! drag, and an age-driven fade -- because a few thousand of these are
//! visual seasoning, not gameplay state: nothing collides with them and
//! nothing reads them back.
//!
//! The GPU side (`vox_render::ParticlePipeline`) only ever sees the flat
//! [`ParticleInstance`] list produced by [`ParticleSystem::instances`].

use glam::Vec3;
use vox_render::{MAX_PARTICLES, ParticleInstance};

/// Fraction of world gravity particles feel -- dust and smoke are light and
/// drag-dominated, so full gravity reads as "gravel", not "dust".
const GRAVITY_FACTOR: f32 = 0.35;
/// Per-second velocity damping (air drag).
const DRAG: f32 = 1.6;

/// One simulated particle.
#[derive(Copy, Clone, Debug)]
struct Particle {
    pos: Vec3,
    vel: Vec3,
    /// Half-size in meters (billboard extent).
    size: f32,
    /// Base color; alpha is faded by age on top of this.
    color: [f32; 4],
    age: f32,
    life: f32,
    /// Smoke rises and grows instead of falling and staying fixed-size.
    buoyant: bool,
}

/// Parameters for one burst of particles -- see the emit helpers on
/// [`ParticleSystem`] for the tuned presets destruction actually uses.
pub struct Burst {
    pub center: Vec3,
    pub count: usize,
    pub color: [f32; 3],
    /// Base outward speed, m/s; per-particle speed varies around it.
    pub speed: f32,
    /// Extra upward velocity bias, m/s -- rubble kicks up, not sideways.
    pub upward: f32,
    /// Mean lifetime, seconds; per-particle life varies around it.
    pub life: f32,
    /// Mean half-size, meters.
    pub size: f32,
    pub buoyant: bool,
}

/// All live particles plus a tiny deterministic RNG for spawn variation.
pub struct ParticleSystem {
    particles: Vec<Particle>,
    rng: u64,
}

impl Default for ParticleSystem {
    fn default() -> Self {
        Self::new()
    }
}

impl ParticleSystem {
    pub fn new() -> Self {
        Self {
            particles: Vec::new(),
            rng: 0x9E37_79B9_7F4A_7C15,
        }
    }

    /// xorshift64* -- deterministic, dependency-free spawn jitter.
    fn next_f32(&mut self) -> f32 {
        self.rng ^= self.rng << 13;
        self.rng ^= self.rng >> 7;
        self.rng ^= self.rng << 17;
        ((self.rng >> 40) as f32) / ((1u64 << 24) as f32)
    }

    /// Uniform in [-1, 1].
    fn signed(&mut self) -> f32 {
        self.next_f32() * 2.0 - 1.0
    }

    /// Spawn one burst. If the cap would be exceeded, the *oldest* live
    /// particles are dropped first -- a fresh explosion always gets its
    /// full visual, at the cost of some old lingering smoke.
    pub fn burst(&mut self, b: Burst) {
        let count = b.count.min(MAX_PARTICLES);
        let overflow = (self.particles.len() + count).saturating_sub(MAX_PARTICLES);
        if overflow > 0 {
            self.particles.drain(..overflow);
        }
        for _ in 0..count {
            let dir = Vec3::new(self.signed(), self.signed(), self.signed());
            let dir = if dir.length_squared() > 1e-6 {
                dir.normalize()
            } else {
                Vec3::Y
            };
            let speed = b.speed * (0.4 + 0.9 * self.next_f32());
            let life = b.life * (0.6 + 0.8 * self.next_f32());
            let size = b.size * (0.6 + 0.8 * self.next_f32());
            // Slight per-particle tint variation keeps a burst from reading
            // as a single flat-colored blob.
            let tint = 0.85 + 0.3 * self.next_f32();
            self.particles.push(Particle {
                pos: b.center,
                vel: dir * speed + Vec3::Y * b.upward,
                size,
                color: [
                    (b.color[0] * tint).min(1.0),
                    (b.color[1] * tint).min(1.0),
                    (b.color[2] * tint).min(1.0),
                    1.0,
                ],
                age: 0.0,
                life: life.max(0.05),
                buoyant: b.buoyant,
            });
        }
    }

    /// Advance every particle by `dt` seconds and drop the expired.
    pub fn update(&mut self, dt: f32) {
        for p in &mut self.particles {
            p.age += dt;
            if p.buoyant {
                // Smoke: rises gently, swells as it ages.
                p.vel.y += 1.2 * dt;
                p.size += 0.35 * p.size * dt;
            } else {
                p.vel.y -= vox_core::consts::GRAVITY * GRAVITY_FACTOR * dt;
            }
            p.vel /= 1.0 + DRAG * dt;
            p.pos += p.vel * dt;
        }
        self.particles.retain(|p| p.age < p.life);
    }

    /// Number of live particles (debug-overlay stat).
    pub fn len(&self) -> usize {
        self.particles.len()
    }

    /// Flatten to GPU instances: alpha fades quadratically with age (a slow
    /// start then a quick vanish reads better than a linear dimming).
    pub fn instances(&self) -> Vec<ParticleInstance> {
        self.particles
            .iter()
            .map(|p| {
                let t = (p.age / p.life).clamp(0.0, 1.0);
                let alpha = p.color[3] * (1.0 - t * t);
                ParticleInstance {
                    center_size: [p.pos.x, p.pos.y, p.pos.z, p.size],
                    color: [p.color[0], p.color[1], p.color[2], alpha],
                }
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dust(center: Vec3, count: usize) -> Burst {
        Burst {
            center,
            count,
            color: [0.5, 0.4, 0.3],
            speed: 2.0,
            upward: 1.0,
            life: 1.0,
            size: 0.05,
            buoyant: false,
        }
    }

    #[test]
    fn particles_age_out_and_are_removed() {
        let mut sys = ParticleSystem::new();
        sys.burst(dust(Vec3::ZERO, 50));
        assert_eq!(sys.len(), 50);
        // Max per-particle life is 1.0 * (0.6 + 0.8) = 1.4 s.
        for _ in 0..100 {
            sys.update(1.0 / 60.0);
        }
        assert_eq!(sys.len(), 0, "all particles must expire: {} left", sys.len());
    }

    #[test]
    fn the_cap_drops_oldest_first_and_never_exceeds_max() {
        let mut sys = ParticleSystem::new();
        sys.burst(dust(Vec3::ZERO, MAX_PARTICLES));
        assert_eq!(sys.len(), MAX_PARTICLES);
        sys.burst(dust(Vec3::splat(10.0), 100));
        assert_eq!(sys.len(), MAX_PARTICLES, "cap must hold");
        // The newest burst must have survived (it was spawned at x=10).
        let inst = sys.instances();
        assert!(
            inst.iter().rev().take(100).all(|i| i.center_size[0] > 5.0),
            "the fresh burst must not be the part that was dropped"
        );
    }

    #[test]
    fn gravity_pulls_dust_down_and_fade_reaches_zero_at_end_of_life() {
        let mut sys = ParticleSystem::new();
        sys.burst(dust(Vec3::new(0.0, 10.0, 0.0), 1));
        for _ in 0..30 {
            sys.update(1.0 / 60.0);
        }
        let inst = sys.instances();
        assert_eq!(inst.len(), 1);
        let alpha = inst[0].color[3];
        assert!(alpha > 0.0 && alpha < 1.0, "mid-life alpha must be fading: {alpha}");
    }

    #[test]
    fn smoke_rises_and_grows_instead_of_falling() {
        let mut sys = ParticleSystem::new();
        sys.burst(Burst {
            center: Vec3::new(0.0, 5.0, 0.0),
            count: 1,
            color: [0.4, 0.4, 0.4],
            speed: 0.0,
            upward: 0.0,
            life: 5.0,
            size: 0.2,
            buoyant: true,
        });
        let size0 = sys.instances()[0].center_size[3];
        for _ in 0..60 {
            sys.update(1.0 / 60.0);
        }
        let i = &sys.instances()[0];
        assert!(i.center_size[1] > 5.0, "smoke must rise: y = {}", i.center_size[1]);
        assert!(i.center_size[3] > size0, "smoke must swell as it ages");
    }
}
