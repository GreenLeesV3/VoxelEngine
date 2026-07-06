//! Voxel raycasting via Amanatides–Woo DDA traversal.

use glam::{IVec3, Vec3};

use crate::world::World;

/// Result of a voxel raycast.
#[derive(Copy, Clone, PartialEq, Debug)]
pub struct RayHit {
    /// The solid voxel that was hit.
    pub voxel: IVec3,
    /// Outward normal of the face crossed to enter the voxel; `None` when the
    /// ray origin was already inside a solid voxel.
    pub face: Option<IVec3>,
    /// Distance from the origin to the entry point, in meters.
    pub dist_m: f32,
}

/// Cast a ray from `origin_m` along `dir` (need not be normalized) for at
/// most `max_dist_m` meters, returning the first solid voxel hit.
pub fn raycast(world: &World, origin_m: Vec3, dir: Vec3, max_dist_m: f32) -> Option<RayHit> {
    let s = world.cfg.voxel_size_m;
    let dir = dir.normalize_or_zero();
    if dir == Vec3::ZERO || !origin_m.is_finite() || max_dist_m <= 0.0 {
        return None;
    }

    let p = origin_m / s; // Ray origin in voxel units.
    let mut cell = p.floor().as_ivec3();
    if world.solid(cell) {
        return Some(RayHit {
            voxel: cell,
            face: None,
            dist_m: 0.0,
        });
    }

    let step = IVec3::new(
        dir.x.signum() as i32,
        dir.y.signum() as i32,
        dir.z.signum() as i32,
    );
    // Per-axis: distance along the ray (in voxel units) to the next grid
    // boundary, and the ray-distance between successive boundaries. Axes the
    // ray never crosses stay at infinity.
    let mut t_max = Vec3::ZERO;
    let mut t_delta = Vec3::ZERO;
    for a in 0..3 {
        if dir[a] > 0.0 {
            t_max[a] = (cell[a] as f32 + 1.0 - p[a]) / dir[a];
            t_delta[a] = 1.0 / dir[a];
        } else if dir[a] < 0.0 {
            t_max[a] = (p[a] - cell[a] as f32) / -dir[a];
            t_delta[a] = -1.0 / dir[a];
        } else {
            t_max[a] = f32::INFINITY;
            t_delta[a] = f32::INFINITY;
        }
    }

    let max_t = max_dist_m / s;
    loop {
        let a = if t_max.x < t_max.y {
            if t_max.x < t_max.z { 0 } else { 2 }
        } else if t_max.y < t_max.z {
            1
        } else {
            2
        };
        if t_max[a] > max_t {
            return None;
        }
        cell[a] += step[a];
        let t_enter = t_max[a];
        t_max[a] += t_delta[a];
        if world.solid(cell) {
            let mut face = IVec3::ZERO;
            face[a] = -step[a];
            return Some(RayHit {
                voxel: cell,
                face: Some(face),
                dist_m: t_enter * s,
            });
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::chunk::Voxel;
    use vox_core::WorldConfig;

    const STONE: Voxel = Voxel(1);

    /// Deterministic splitmix64 for dependency-free test randomness.
    struct Rng(u64);

    impl Rng {
        fn next_u64(&mut self) -> u64 {
            self.0 = self.0.wrapping_add(0x9e37_79b9_7f4a_7c15);
            let mut z = self.0;
            z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
            z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
            z ^ (z >> 31)
        }

        /// Uniform in [0, 1).
        fn unit(&mut self) -> f32 {
            (self.next_u64() >> 40) as f32 / (1u64 << 24) as f32
        }

        fn range(&mut self, lo: f32, hi: f32) -> f32 {
            lo + self.unit() * (hi - lo)
        }

        fn int(&mut self, below: u32) -> i32 {
            (self.next_u64() % u64::from(below)) as i32
        }
    }

    fn test_world(voxel_size_m: f32) -> World {
        World::new(WorldConfig {
            voxel_size_m,
            extent_m: [voxel_size_m * 64.0; 3],
            ..WorldConfig::default()
        })
    }

    /// Brute-force reference: march the ray in tiny steps sampling solidity.
    fn brute_force(world: &World, origin_m: Vec3, dir: Vec3, max_dist_m: f32) -> Option<IVec3> {
        let dir = dir.normalize_or_zero();
        let step = world.cfg.voxel_size_m / 100.0;
        let mut t = 0.0;
        while t <= max_dist_m {
            let cell = vox_core::voxel_at(origin_m + dir * t, world.cfg.voxel_size_m);
            if world.solid(cell) {
                return Some(cell);
            }
            t += step;
        }
        None
    }

    #[test]
    fn matches_brute_force_on_random_worlds() {
        let mut rng = Rng(0xD1CE);
        for world_i in 0..30 {
            let s = if world_i % 2 == 0 { 0.1 } else { 1.0 };
            let mut world = test_world(s);
            // ~40 random solid voxels inside a 16^3 region.
            for _ in 0..40 {
                let v = IVec3::new(rng.int(16) + 8, rng.int(16) + 8, rng.int(16) + 8);
                world.set_voxel(v, STONE);
            }
            for _ in 0..40 {
                let origin = Vec3::new(
                    rng.range(0.0, 32.0) * s,
                    rng.range(0.0, 32.0) * s,
                    rng.range(0.0, 32.0) * s,
                );
                let dir = Vec3::new(
                    rng.range(-1.0, 1.0),
                    rng.range(-1.0, 1.0),
                    rng.range(-1.0, 1.0),
                );
                if dir.length() < 1e-3 {
                    continue;
                }
                let max_dist = 40.0 * s;
                let dda = raycast(&world, origin, dir, max_dist);
                let brute = brute_force(&world, origin, dir, max_dist);
                match (dda, brute) {
                    (Some(hit), Some(cell)) => {
                        assert_eq!(
                            hit.voxel, cell,
                            "world {world_i}: DDA and brute force disagree \
                             (origin {origin}, dir {dir})"
                        );
                        assert!(hit.dist_m <= max_dist);
                    }
                    (None, None) => {}
                    (dda, brute) => panic!(
                        "world {world_i}: hit disagreement dda={dda:?} brute={brute:?} \
                         (origin {origin}, dir {dir})"
                    ),
                }
            }
        }
    }

    #[test]
    fn axis_aligned_ray_reports_entry_face() {
        let mut world = test_world(0.1);
        world.set_voxel(IVec3::new(5, 5, 5), STONE);

        // Straight down onto the top face.
        let hit = raycast(
            &world,
            Vec3::new(0.55, 1.55, 0.55),
            Vec3::new(0.0, -1.0, 0.0),
            5.0,
        )
        .expect("must hit the column");
        assert_eq!(hit.voxel, IVec3::new(5, 5, 5));
        assert_eq!(hit.face, Some(IVec3::Y), "top face normal is +Y");
        assert!((hit.dist_m - 0.95).abs() < 1e-3, "got {}", hit.dist_m);

        // From the -X side onto the -X face.
        let hit = raycast(
            &world,
            Vec3::new(0.05, 0.55, 0.55),
            Vec3::new(1.0, 0.0, 0.0),
            5.0,
        )
        .expect("must hit the column");
        assert_eq!(hit.face, Some(IVec3::NEG_X));
    }

    #[test]
    fn ray_starting_inside_solid_reports_no_face_and_zero_distance() {
        let mut world = test_world(1.0);
        world.set_voxel(IVec3::new(3, 3, 3), STONE);

        let hit = raycast(
            &world,
            Vec3::new(3.5, 3.5, 3.5),
            Vec3::new(1.0, 0.0, 0.0),
            10.0,
        )
        .expect("origin inside solid must hit");
        assert_eq!(hit.voxel, IVec3::new(3, 3, 3));
        assert_eq!(hit.face, None);
        assert_eq!(hit.dist_m, 0.0);
    }

    #[test]
    fn miss_within_max_distance_returns_none() {
        let mut world = test_world(1.0);
        world.set_voxel(IVec3::new(50, 1, 1), STONE);

        // Pointing at the voxel but out of reach.
        let hit = raycast(
            &world,
            Vec3::new(0.5, 1.5, 1.5),
            Vec3::new(1.0, 0.0, 0.0),
            10.0,
        );
        assert_eq!(hit, None);

        // Pointing away entirely.
        let hit = raycast(
            &world,
            Vec3::new(0.5, 1.5, 1.5),
            Vec3::new(0.0, 1.0, 0.0),
            100.0,
        );
        assert_eq!(hit, None);
    }

    #[test]
    fn degenerate_inputs_return_none() {
        let world = test_world(1.0);
        assert_eq!(raycast(&world, Vec3::ZERO, Vec3::ZERO, 10.0), None);
        assert_eq!(raycast(&world, Vec3::ZERO, Vec3::X, 0.0), None);
        assert_eq!(
            raycast(&world, Vec3::new(f32::NAN, 0.0, 0.0), Vec3::X, 10.0),
            None
        );
    }
}
