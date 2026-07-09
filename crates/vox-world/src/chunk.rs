//! Chunk voxel storage: a 32³ block of material ids with a uniform fast path.
//!
//! Storage form is private behind `get`/`set` so palette compression can be
//! added later without touching callers. Layout of the dense form is y-major
//! (`y * 32² + z * 32 + x`) so horizontal slices are contiguous.

use glam::UVec3;
use vox_core::consts::CHUNK_SIZE;

/// A voxel: material id into the registry. `0` = air.
#[derive(Copy, Clone, PartialEq, Eq, Hash, Debug, Default)]
pub struct Voxel(pub u16);

/// The empty voxel (material id 0).
pub const AIR: Voxel = Voxel(0);

/// Voxels in one chunk (32³).
pub const CHUNK_VOLUME: usize = CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE;

enum ChunkStorage {
    /// Every voxel in the chunk is this value (~16 bytes; most of any world).
    Uniform(Voxel),
    /// One `u16` per voxel (64 KiB; the interesting shell of the world).
    Dense(Box<[Voxel; CHUNK_VOLUME]>),
}

/// A 32³ block of voxels with a cached count of solid (non-air) voxels.
pub struct Chunk {
    storage: ChunkStorage,
    solid_count: u32,
}

/// Dense-array index of a chunk-local position.
#[inline]
fn index(l: UVec3) -> usize {
    debug_assert!(
        l.max_element() < CHUNK_SIZE as u32,
        "chunk-local coordinate out of range: {l}"
    );
    (l.y as usize) * (CHUNK_SIZE * CHUNK_SIZE) + (l.z as usize) * CHUNK_SIZE + (l.x as usize)
}

/// Heap-allocate a dense voxel array without a 64 KiB stack round-trip.
fn dense_box(fill: Voxel) -> Box<[Voxel; CHUNK_VOLUME]> {
    let slice = vec![fill; CHUNK_VOLUME].into_boxed_slice();
    match slice.try_into() {
        Ok(array) => array,
        // Length is CHUNK_VOLUME by construction.
        Err(_) => unreachable!("boxed slice has CHUNK_VOLUME elements"),
    }
}

impl Chunk {
    /// A chunk with every voxel set to `v`.
    pub fn uniform(v: Voxel) -> Self {
        let solid_count = if v == AIR { 0 } else { CHUNK_VOLUME as u32 };
        Self {
            storage: ChunkStorage::Uniform(v),
            solid_count,
        }
    }

    /// An all-air chunk.
    pub fn new() -> Self {
        Self::uniform(AIR)
    }

    /// Voxel at chunk-local position `l` (each axis `0..32`).
    pub fn get(&self, l: UVec3) -> Voxel {
        match &self.storage {
            ChunkStorage::Uniform(v) => {
                debug_assert!(
                    l.max_element() < CHUNK_SIZE as u32,
                    "chunk-local coordinate out of range: {l}"
                );
                *v
            }
            ChunkStorage::Dense(data) => data[index(l)],
        }
    }

    /// Write voxel `v` at chunk-local position `l`, promoting uniform storage
    /// to dense on the first differing write.
    pub fn set(&mut self, l: UVec3, v: Voxel) {
        let old = match &mut self.storage {
            ChunkStorage::Uniform(u) => {
                let u = *u;
                if v == u {
                    debug_assert!(
                        l.max_element() < CHUNK_SIZE as u32,
                        "chunk-local coordinate out of range: {l}"
                    );
                    return; // No-op write keeps the uniform fast path.
                }
                let mut data = dense_box(u);
                data[index(l)] = v;
                self.storage = ChunkStorage::Dense(data);
                u
            }
            ChunkStorage::Dense(data) => std::mem::replace(&mut data[index(l)], v),
        };
        if old != AIR && v == AIR {
            self.solid_count -= 1;
        } else if old == AIR && v != AIR {
            self.solid_count += 1;
        }
    }

    /// `Some(v)` if every voxel in the chunk is `v`.
    pub fn uniform_value(&self) -> Option<Voxel> {
        match &self.storage {
            ChunkStorage::Uniform(v) => Some(*v),
            ChunkStorage::Dense(_) => None,
        }
    }

    /// Number of solid (non-air) voxels.
    pub fn solid_count(&self) -> u32 {
        self.solid_count
    }

    /// True when the chunk contains no solid voxels.
    pub fn is_empty(&self) -> bool {
        self.solid_count == 0
    }

    /// For each of the 3 axes, a `[bool; 32]` array marking which slices
    /// (along that axis) contain at least one solid (non-air) voxel.
    /// `mask[axis][slice]` is true iff some voxel with that axis-coordinate
    /// is solid. Used to skip empty slices in greedy surface generation.
    ///
    /// Computed in a single pass over the chunk's voxels; for uniform
    /// storage the answer is constant and produced without iteration.
    pub fn solid_slice_masks(&self) -> [[bool; CHUNK_SIZE]; 3] {
        let mut masks = [[false; CHUNK_SIZE]; 3];
        match &self.storage {
            ChunkStorage::Uniform(v) => {
                if *v != AIR {
                    for axis in 0..3 {
                        for s in 0..CHUNK_SIZE {
                            masks[axis][s] = true;
                        }
                    }
                }
                masks
            }
            ChunkStorage::Dense(data) => {
                // Layout is y * 32² + z * 32 + x (see `index`).
                for y in 0..CHUNK_SIZE {
                    for z in 0..CHUNK_SIZE {
                        let row = y * (CHUNK_SIZE * CHUNK_SIZE) + z * CHUNK_SIZE;
                        for x in 0..CHUNK_SIZE {
                            if data[row + x] != AIR {
                                masks[0][x] = true;
                                masks[1][y] = true;
                                masks[2][z] = true;
                            }
                        }
                    }
                }
                masks
            }
        }
    }
    /// Collapse dense storage back to uniform when all voxels are equal.
    /// Returns true if the chunk is uniform afterwards.
    pub fn try_demote(&mut self) -> bool {
        match &self.storage {
            ChunkStorage::Uniform(_) => true,
            ChunkStorage::Dense(data) => {
                let first = data[0];
                if data.iter().all(|&v| v == first) {
                    self.storage = ChunkStorage::Uniform(first);
                    true
                } else {
                    false
                }
            }
        }
    }
}

impl Default for Chunk {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const STONE: Voxel = Voxel(1);
    const DIRT: Voxel = Voxel(2);

    #[test]
    fn new_chunk_is_uniform_air() {
        let chunk = Chunk::new();
        assert_eq!(chunk.uniform_value(), Some(AIR));
        assert_eq!(chunk.solid_count(), 0);
        assert!(chunk.is_empty());
        for corner in [
            UVec3::new(0, 0, 0),
            UVec3::new(31, 0, 0),
            UVec3::new(0, 31, 0),
            UVec3::new(0, 0, 31),
            UVec3::new(31, 31, 31),
        ] {
            assert_eq!(chunk.get(corner), AIR);
        }
    }

    #[test]
    fn set_same_value_keeps_uniform_storage() {
        let mut chunk = Chunk::new();
        chunk.set(UVec3::new(5, 6, 7), AIR);
        assert_eq!(
            chunk.uniform_value(),
            Some(AIR),
            "writing the uniform value must not promote to dense"
        );

        let mut stone = Chunk::uniform(STONE);
        stone.set(UVec3::new(0, 0, 0), STONE);
        assert_eq!(stone.uniform_value(), Some(STONE));
    }

    #[test]
    fn set_promotes_to_dense_and_reads_back() {
        let mut chunk = Chunk::new();
        let pos = UVec3::new(12, 3, 30);
        chunk.set(pos, STONE);

        assert_eq!(chunk.uniform_value(), None, "differing write promotes");
        assert_eq!(chunk.get(pos), STONE);
        assert_eq!(chunk.get(UVec3::new(11, 3, 30)), AIR);
        assert_eq!(chunk.get(UVec3::new(12, 4, 30)), AIR);
        assert_eq!(chunk.solid_count(), 1);
    }

    #[test]
    fn promotion_from_solid_uniform_preserves_contents() {
        let mut chunk = Chunk::uniform(STONE);
        assert_eq!(chunk.solid_count(), CHUNK_VOLUME as u32);

        let pos = UVec3::new(0, 31, 15);
        chunk.set(pos, AIR);
        assert_eq!(chunk.get(pos), AIR);
        assert_eq!(chunk.get(UVec3::new(1, 31, 15)), STONE);
        assert_eq!(chunk.solid_count(), CHUNK_VOLUME as u32 - 1);
    }

    #[test]
    fn solid_count_tracks_all_transition_kinds() {
        let mut chunk = Chunk::new();
        let pos = UVec3::new(8, 8, 8);

        chunk.set(pos, STONE); // air -> solid
        assert_eq!(chunk.solid_count(), 1);
        chunk.set(pos, DIRT); // solid -> solid
        assert_eq!(chunk.solid_count(), 1);
        chunk.set(pos, AIR); // solid -> air
        assert_eq!(chunk.solid_count(), 0);
        chunk.set(pos, AIR); // air -> air
        assert_eq!(chunk.solid_count(), 0);
        assert!(chunk.is_empty());
    }

    #[test]
    fn try_demote_collapses_all_equal_dense_chunk() {
        let mut chunk = Chunk::new();
        for y in 0..CHUNK_SIZE as u32 {
            for z in 0..CHUNK_SIZE as u32 {
                for x in 0..CHUNK_SIZE as u32 {
                    chunk.set(UVec3::new(x, y, z), STONE);
                }
            }
        }
        assert_eq!(chunk.uniform_value(), None, "still dense before demote");
        assert_eq!(chunk.solid_count(), CHUNK_VOLUME as u32);

        assert!(chunk.try_demote());
        assert_eq!(chunk.uniform_value(), Some(STONE));
        assert_eq!(chunk.get(UVec3::new(17, 2, 29)), STONE);
    }

    #[test]
    fn try_demote_leaves_mixed_chunk_dense() {
        let mut chunk = Chunk::new();
        chunk.set(UVec3::new(1, 1, 1), STONE);
        assert!(!chunk.try_demote());
        assert_eq!(chunk.uniform_value(), None);
        assert_eq!(chunk.get(UVec3::new(1, 1, 1)), STONE);
    }

    #[test]
    fn try_demote_on_uniform_chunk_is_true() {
        let mut chunk = Chunk::uniform(STONE);
        assert!(chunk.try_demote());
        assert_eq!(chunk.uniform_value(), Some(STONE));
    }

    #[cfg(debug_assertions)]
    #[test]
    #[should_panic(expected = "out of range")]
    fn out_of_range_get_panics_in_debug() {
        let mut chunk = Chunk::new();
        // Force dense storage so `get` actually indexes.
        chunk.set(UVec3::new(0, 0, 0), STONE);
        let _ = chunk.get(UVec3::new(32, 0, 0));
    }

    #[test]
    fn solid_slice_masks_empty_chunk_is_all_false() {
        let chunk = Chunk::new();
        let masks = chunk.solid_slice_masks();
        for axis in 0..3 {
            assert!(masks[axis].iter().all(|&s| !s), "axis {axis} all-air");
        }
    }

    #[test]
    fn solid_slice_masks_uniform_solid_is_all_true() {
        let chunk = Chunk::uniform(STONE);
        let masks = chunk.solid_slice_masks();
        for axis in 0..3 {
            assert!(masks[axis].iter().all(|&s| s), "axis {axis} all-solid");
        }
    }

    #[test]
    fn solid_slice_masks_dense_marks_only_occupied_slices() {
        let mut chunk = Chunk::new();
        // Place solids at (x=5, y=7, z=9) and (x=5, y=7, z=20).
        chunk.set(UVec3::new(5, 7, 9), STONE);
        chunk.set(UVec3::new(5, 7, 20), DIRT);
        let masks = chunk.solid_slice_masks();

        // X axis: only slice 5 has solids.
        for x in 0..CHUNK_SIZE {
            assert_eq!(masks[0][x], x == 5, "x={x}");
        }
        // Y axis: only slice 7 has solids.
        for y in 0..CHUNK_SIZE {
            assert_eq!(masks[1][y], y == 7, "y={y}");
        }
        // Z axis: slices 9 and 20 have solids.
        for z in 0..CHUNK_SIZE {
            assert_eq!(masks[2][z], z == 9 || z == 20, "z={z}");
        }
    }
}
