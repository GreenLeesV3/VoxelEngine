//! Spatial-hash broadphase over body AABBs.

use std::collections::{HashMap, HashSet};

use glam::IVec3;

use crate::body::Body;

/// Hash cell edge in meters (≈ typical debris size).
const CELL_M: f32 = 2.0;

/// Candidate body pairs whose AABBs overlap. Pairs where both bodies sleep
/// are skipped (they cannot move); pairs are unique with `a < b`.
pub fn candidate_pairs(slots: &[Option<Body>]) -> Vec<(usize, usize)> {
    let mut cells: HashMap<IVec3, Vec<usize>> = HashMap::new();
    for (i, entry) in slots.iter().enumerate() {
        let Some(body) = entry else { continue };
        let lo = (body.aabb_min / CELL_M).floor().as_ivec3();
        let hi = (body.aabb_max / CELL_M).floor().as_ivec3();
        for y in lo.y..=hi.y {
            for z in lo.z..=hi.z {
                for x in lo.x..=hi.x {
                    cells.entry(IVec3::new(x, y, z)).or_default().push(i);
                }
            }
        }
    }

    let mut seen: HashSet<(usize, usize)> = HashSet::new();
    let mut pairs = Vec::new();
    for bucket in cells.values() {
        for (idx, &a) in bucket.iter().enumerate() {
            for &b in &bucket[idx + 1..] {
                let (a, b) = if a < b { (a, b) } else { (b, a) };
                if !seen.insert((a, b)) {
                    continue;
                }
                let (Some(ba), Some(bb)) = (&slots[a], &slots[b]) else {
                    continue;
                };
                if ba.sleep.asleep && bb.sleep.asleep {
                    continue;
                }
                // Exact AABB overlap check (cells are coarse).
                let overlap =
                    ba.aabb_min.cmple(bb.aabb_max).all() && ba.aabb_max.cmpge(bb.aabb_min).all();
                if overlap {
                    pairs.push((a, b));
                }
            }
        }
    }
    pairs
}
