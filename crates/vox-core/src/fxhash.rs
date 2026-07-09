//! A fast, dependency-free hasher for the engine's hot-path collections
//! (the rustc-hash / FxHash algorithm: wrapping multiply + rotate per word).
//!
//! Rust's default `HashMap` hasher is SipHash-1-3, which is deliberately
//! slow: it buys resistance to attacker-crafted collision floods, a threat
//! model that matters for a web server parsing untrusted keys and not at
//! all for a game engine hashing its own voxel coordinates. The cost is
//! real, though -- the world's chunk map is consulted on *every single
//! voxel read* (contacts, raycasts, carves, connectivity floods), the
//! broadphase rebuilds a cell map three times per physics step, and the
//! solver's warm-start map churns every substep. On low-end CPUs the
//! default hasher's overhead on those paths is pure waste.
//!
//! FxHash is also fully deterministic (no per-process random seed the way
//! `RandomState` has), so iteration order quirks reproduce across runs
//! instead of flickering between them.

use std::collections::{HashMap, HashSet};
use std::hash::{BuildHasherDefault, Hasher};

/// The multiplier rustc-hash uses (derived from the golden ratio, the same
/// constant Fibonacci hashing is built on).
const SEED: u64 = 0x51_7c_c1_b7_27_22_0a_95;

/// Word-at-a-time multiply-rotate hasher. Not collision-attack resistant
/// -- see the module docs for why that's the right trade here.
#[derive(Default)]
pub struct FxHasher {
    hash: u64,
}

impl FxHasher {
    #[inline]
    fn add(&mut self, word: u64) {
        self.hash = (self.hash.rotate_left(5) ^ word).wrapping_mul(SEED);
    }
}

impl Hasher for FxHasher {
    #[inline]
    fn finish(&self) -> u64 {
        self.hash
    }

    #[inline]
    fn write(&mut self, bytes: &[u8]) {
        // Chunk into u64 words, then mop up the tail. Keys in this engine
        // are small (an IVec3 is 12 bytes; a contact key is 13), so this
        // loop runs once or twice.
        let mut chunks = bytes.chunks_exact(8);
        for c in chunks.by_ref() {
            self.add(u64::from_le_bytes(c.try_into().expect("8-byte chunk")));
        }
        let rem = chunks.remainder();
        if !rem.is_empty() {
            let mut tail = [0u8; 8];
            tail[..rem.len()].copy_from_slice(rem);
            self.add(u64::from_le_bytes(tail));
        }
    }

    #[inline]
    fn write_u8(&mut self, n: u8) {
        self.add(n as u64);
    }

    #[inline]
    fn write_u32(&mut self, n: u32) {
        self.add(n as u64);
    }

    #[inline]
    fn write_u64(&mut self, n: u64) {
        self.add(n);
    }

    #[inline]
    fn write_usize(&mut self, n: usize) {
        self.add(n as u64);
    }

    #[inline]
    fn write_i32(&mut self, n: i32) {
        self.add(n as u32 as u64);
    }
}

/// `BuildHasher` for [`FxHasher`]; plug into any `HashMap`/`HashSet`.
pub type FxBuildHasher = BuildHasherDefault<FxHasher>;
/// Drop-in `HashMap` with the fast hasher.
pub type FxHashMap<K, V> = HashMap<K, V, FxBuildHasher>;
/// Drop-in `HashSet` with the fast hasher.
pub type FxHashSet<T> = HashSet<T, FxBuildHasher>;

#[cfg(test)]
mod tests {
    use super::*;
    use std::hash::{BuildHasher, Hash};

    fn hash_of<T: Hash>(v: &T) -> u64 {
        FxBuildHasher::default().hash_one(v)
    }

    #[test]
    fn deterministic_across_hasher_instances() {
        let key = (1_i32, -42_i32, 7_i32);
        assert_eq!(hash_of(&key), hash_of(&key));
    }

    #[test]
    fn distinct_small_keys_do_not_trivially_collide() {
        // Not a statistical quality test -- just a guard against a broken
        // implementation hashing everything to the same bucket (e.g. a
        // `write` that ignores its input).
        let mut seen = std::collections::HashSet::new();
        for x in -8..8 {
            for y in -8..8 {
                for z in -8..8 {
                    seen.insert(hash_of(&(x, y, z)));
                }
            }
        }
        assert!(
            seen.len() > 4000,
            "16^3 = 4096 keys must hash nearly uniquely, got {} distinct",
            seen.len()
        );
    }

    #[test]
    fn maps_and_sets_round_trip() {
        let mut m: FxHashMap<(i32, i32, i32), u32> = FxHashMap::default();
        m.insert((1, 2, 3), 7);
        m.insert((-4, 0, 9), 8);
        assert_eq!(m.get(&(1, 2, 3)), Some(&7));
        assert_eq!(m.get(&(-4, 0, 9)), Some(&8));
        assert_eq!(m.get(&(0, 0, 0)), None);

        let mut s: FxHashSet<u64> = FxHashSet::default();
        assert!(s.insert(11));
        assert!(!s.insert(11));
    }
}
