//! Procedural world generation: custom noise, heightmap terrain, and trees.
//! Deterministic per seed; all gameplay-scale parameters in meters.

pub mod noise;
pub mod terrain;

pub use noise::{Fbm, gradient2, hash2, hash3, value3};
pub use terrain::{TerrainGen, TerrainMaterials};
