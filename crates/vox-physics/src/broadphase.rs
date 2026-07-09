//! Spatial-hash broadphase over body AABBs.

use glam::IVec3;
use vox_core::{FxHashMap, FxHashSet};

use crate::body::Body;

/// Hash cell edge in meters (≈ typical debris size).
const CELL_M: f32 = 2.0;

/// Persistent broadphase scratch state. `PhysicsWorld` owns one and reuses
/// it across a whole physics step instead of allocating a fresh hash map,
/// hash set, and output vector each call. The broadphase is a coarse 2 m
/// uniform grid, and body AABBs only move by at most `MAX_SPEED * h`
/// (≈1 m) per substep -- well under one cell -- so the candidate pair set
/// is built *once per step* (before the substep loop) and reused for every
/// substep's narrowphase plus the end-of-step sleep-island grouping. That
/// turns three full grid builds per step into one, with no behavioral
/// change the coarse grid can resolve: a pair appearing or disappearing
/// mid-step would require a body to cross a 2 m cell boundary inside a
/// single substep, which the speed ceiling forbids.
#[derive(Default)]
pub struct Broadphase {
    cells: FxHashMap<IVec3, Vec<usize>>,
    seen: FxHashSet<(usize, usize)>,
    pairs: Vec<(usize, usize)>,
}

impl Broadphase {
    /// Rebuild the candidate-pair set from scratch, reusing `self`'s
    /// existing buffer capacity (`.clear()` keeps allocations). Call this
    /// once per physics step, then hand out the result via [`pairs`]
    /// throughout the substeps and island grouping.
    ///
    /// Candidate body pairs whose AABBs overlap. Pairs where both bodies
    /// sleep are skipped (they cannot move); pairs are unique with `a < b`.
    pub fn build(&mut self, slots: &[Option<Body>]) {
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
    }

    /// The candidate pairs produced by the last [`build`] call. Borrows
    /// from `self`, so callers must finish with the slice before the next
    /// `build`.
    pub fn pairs(&self) -> &[(usize, usize)] {
        &self.pairs
    }

    /// Convenience: build and return the pairs in one call. Equivalent to
    /// [`build`] followed by [`pairs`]; kept for tests and standalone use.
    pub fn candidate_pairs(&mut self, slots: &[Option<Body>]) -> &[(usize, usize)] {
        self.build(slots);
        self.pairs()
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

    #[test]
    fn build_then_pairs_reuses_last_result() {
        // Mirrors how `PhysicsWorld::step` uses it: `build` once, then
        // `pairs()` handed out repeatedly (substeps + islands) with no
        // rebuild in between.
        let reg = registry();
        let slots = vec![
            Some(cube(&reg, Vec3::new(0.0, 0.0, 0.0))),
            Some(cube(&reg, Vec3::new(0.4, 0.0, 0.0))),
            Some(cube(&reg, Vec3::new(50.0, 0.0, 0.0))),
        ];
        let mut bp = Broadphase::default();
        bp.build(&slots);
        // Repeated `pairs()` calls return the same slice without rebuilding.
        let a = bp.pairs().to_vec();
        let b = bp.pairs().to_vec();
        assert_eq!(a, b);
        assert_eq!(a, vec![(0, 1)]);
        // A fresh `build` with different slots replaces the cached pairs.
        let far = vec![Some(cube(&reg, Vec3::new(100.0, 100.0, 100.0)))];
        bp.build(&far);
        assert!(bp.pairs().is_empty());
        // And rebuilding the original slots recovers them -- no stale leak.
        bp.build(&slots);
        assert_eq!(bp.pairs(), &[(0, 1)]);
    }
}
