//! Foundation types for the voxel engine: engine-wide constants, coordinate
//! math, per-world configuration, and shared error types.
//!
//! Unit contract: gameplay quantities in public APIs are SI — lengths in
//! meters (`_m` suffix) — and are converted to voxel units (`_voxels`) at the
//! point of use.

pub mod config;
pub mod consts;
pub mod coords;
pub mod error;
pub mod material;
pub mod profile;
pub mod tunables;

pub use config::WorldConfig;
pub use coords::{CHUNK, chunk_of, chunk_origin, local_of, voxel_at, voxel_center_m};
pub use error::CoreError;
pub use material::{MaterialDef, MaterialId, MaterialRegistry};
pub use profile::{FrameProfile, ScopedTimer, TimingRing};
pub use tunables::Tunables;
