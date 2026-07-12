//! Greedy voxel meshing with baked vertex AO, over copied region slabs.
//!
//! Pure data-in/data-out: no GPU types, runs headless, serves both world
//! chunks and debris-body grids.

pub mod greedy;
pub mod slab;

pub use greedy::{GrassVertex, MeshData, VoxelVertex, mesh_slab};
pub use slab::{MAX_SLAB_DIM, VoxelSlab};
