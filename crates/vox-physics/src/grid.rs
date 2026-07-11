//! Shared helpers for voxel-grid indexing and face-adjacent traversal,
//! used by the destruction and body modules.

use glam::IVec3;

/// The six face-adjacent directions.
pub const DIRS: [IVec3; 6] = [
    IVec3::X,
    IVec3::NEG_X,
    IVec3::Y,
    IVec3::NEG_Y,
    IVec3::Z,
    IVec3::NEG_Z,
];

/// Linear index into a dense voxel grid indexed `x + z*dx + y*dx*dz`.
#[inline]
pub fn grid_index(dims: IVec3, p: IVec3) -> usize {
    (p.x + p.z * dims.x + p.y * dims.x * dims.z) as usize
}
