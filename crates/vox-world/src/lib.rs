//! Voxel world storage: chunks, the sparse world map, edits, and raycasting.

pub mod chunk;

pub use chunk::{AIR, CHUNK_VOLUME, Chunk, Voxel};
