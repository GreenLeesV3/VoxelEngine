//! Spatial-hash broadphase over body AABBs.

use glam::IVec3;
use vox_core::{FxHashMap, FxHashSet};

use crate::body::Body;

/// Hash cell edge in meters (≈ typical debris size).
const CELL_M: f32 = 2.0;

/// Persistent broadphase scratch state. `PhysicsWorld` owns one and reuses
/// it across every `candidate_pairs` call (three per physics step: once per
/// substep, plus once for the end-of-step sleep-island grouping) instead of
/// allocating a fresh hash map, hash set, and output vector each time --
/// with `MAX_DEBRIS_BODIES` debris around, that reallocation was real,
/// measurable overhead paid three times a frame for no behavioral benefit.
#[derive(Default)]
pub struct Broadphase {
    cells: FxHashMap<IVec3, Vec<usize>>,
    seen: FxHashSet<(usize, usize)>,
    pairs: Vec<(usize, usize)>,
}

impl Broadphase {
    /// Candidate body pairs whose AABBs overlap. Pairs where both bodies
    /// sleep are skipped (they cannot move); pairs are unique with `a < b`.
    /// Borrows the returned slice from `self`'s scratch buffers, so callers
    /// must finish using it before the next `candidate_pairs` call.
    pub fn candidate_pairs(&mut self, slots: &[Option<Body>]) -> &[(usize, usize)] {
        self.cells.clear();
        for (i, entry) in slots.iter().enumerate() {
            let Some(body) = entry else { continue };
            let lo = (body.aabb_min / CELL_M).floor().as_ivec3();
            let hi = (body.aabb_max / CELL_M).floor().as_ivec3();
            for y in lo.y..=hi.y {
                for z in lo.z..=hi.z {
                    for x in lo.x..=hi.x {
                        self.cells.entry(IVec3::new(x, y, z)).or_default().push(i);
                    }
                }
            }
        }

        self.seen.clear();
        self.pairs.clear();
        for bucket in self.cells.values() {
            for (idx, &a) in bucket.iter().enumerate() {
                for &b in &bucket[idx + 1..] {
                    let (a, b) = if a < b { (a, b) } else { (b, a) };
                    if !self.seen.insert((a, b)) {
                        continue;
                    }
                    let (Some(ba), Some(bb)) = (&slots[a], &slots[b]) else {
                        continue;
                    };
                    if ba.sleep.asleep && bb.sleep.asleep {
                        continue;
                    }
                    // Exact AABB overlap check (cells are coarse).
                    let overlap = ba.aabb_min.cmple(bb.aabb_max).all()
                        && ba.aabb_max.cmpge(bb.aabb_min).all();
                    if overlap {
                        self.pairs.push((a, b));
                    }
                }
            }
        }
        &self.pairs
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::body::VoxelGrid;
    use glam::Vec3;
    use vox_core::MaterialRegistry;
    use vox_world::Voxel;

    fn registry() -> MaterialRegistry {
        MaterialRegistry::from_toml_str(
            r#"
            [[material]]
            name = "stone"
            color = [0.5, 0.5, 0.5]
            density = 2600.0
            strength = 8.0
            "#,
            "test.toml",
        )
        .expect("registry")
    }

    fn cube(reg: &MaterialRegistry, com: Vec3) -> Body {
        let grid = VoxelGrid::new(IVec3::splat(2), vec![Voxel(1); 8]);
        Body::from_grid(grid, reg, 0.5, com).expect("massive body")
    }

    #[test]
    fn reused_scratch_state_gives_the_same_answer_every_call() {
        let reg = registry();
        let slots = vec![
            Some(cube(&reg, Vec3::new(0.0, 0.0, 0.0))),
            Some(cube(&reg, Vec3::new(0.4, 0.0, 0.0))),
            Some(cube(&reg, Vec3::new(50.0, 0.0, 0.0))),
        ];
        let mut bp = Broadphase::default();

        // Call it several times with different intervening slot sets, the
        // way `PhysicsWorld` does across substeps -- the scratch buffers
        // must not leak stale pairs or cells from an earlier call.
        let other_slots = vec![Some(cube(&reg, Vec3::new(100.0, 100.0, 100.0)))];
        assert_eq!(bp.candidate_pairs(&other_slots).len(), 0);
        let first = bp.candidate_pairs(&slots).to_vec();
        let other_slots2 = vec![Some(cube(&reg, Vec3::new(-100.0, 0.0, 0.0)))];
        assert_eq!(bp.candidate_pairs(&other_slots2).len(), 0);
        let second = bp.candidate_pairs(&slots).to_vec();

        assert_eq!(first, second);
        assert_eq!(first, vec![(0, 1)], "only the two overlapping cubes must pair up");
    }
}
