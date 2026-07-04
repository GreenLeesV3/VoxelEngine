//! Coordinate math between world space (meters), world-voxel space, and
//! chunk-local space. Every mapping uses euclidean division/remainder so the
//! results stay correct across the negative axes.

use glam::{IVec3, UVec3, Vec3};

/// Voxels per chunk axis as an `i32`, for coordinate arithmetic.
pub const CHUNK: i32 = crate::consts::CHUNK_SIZE as i32;

/// Chunk position containing a world-voxel position.
pub fn chunk_of(v: IVec3) -> IVec3 {
    v.div_euclid(IVec3::splat(CHUNK))
}

/// Position within its chunk (0..32 on each axis).
pub fn local_of(v: IVec3) -> UVec3 {
    v.rem_euclid(IVec3::splat(CHUNK)).as_uvec3()
}

/// World-voxel position of a chunk's minimum corner.
pub fn chunk_origin(c: IVec3) -> IVec3 {
    c * CHUNK
}

/// Voxel containing a world-space point (meters).
pub fn voxel_at(p_m: Vec3, voxel_size_m: f32) -> IVec3 {
    (p_m / voxel_size_m).floor().as_ivec3()
}

/// Center of a voxel in meters.
pub fn voxel_center_m(v: IVec3, voxel_size_m: f32) -> Vec3 {
    (v.as_vec3() + 0.5) * voxel_size_m
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chunk_of_negative_voxel() {
        assert_eq!(chunk_of(IVec3::new(-1, 0, 31)), IVec3::new(-1, 0, 0));
        assert_eq!(local_of(IVec3::new(-1, 0, 33)), UVec3::new(31, 0, 1));
    }

    #[test]
    fn world_voxel_roundtrip() {
        let v = voxel_at(Vec3::new(1.05, -0.32, 0.0), 0.1);
        assert_eq!(v, IVec3::new(10, -4, 0));
        let c = voxel_center_m(v, 0.1);
        assert!((c - Vec3::new(1.05, -0.35, 0.05)).abs().max_element() < 1e-6);
    }

    /// `chunk_origin(chunk_of(v)) + local_of(v)` must reconstruct `v` exactly,
    /// and the local part must stay inside `0..CHUNK`, on both sides of zero.
    #[test]
    fn chunk_local_decomposition_is_exact() {
        let samples = [-65, -64, -33, -32, -31, -1, 0, 1, 31, 32, 33, 63, 64, 100];
        for &x in &samples {
            for &y in &samples {
                for &z in &samples {
                    let v = IVec3::new(x, y, z);
                    let local = local_of(v);
                    assert!(
                        local.max_element() < CHUNK as u32,
                        "local {local} out of range for voxel {v}"
                    );
                    assert_eq!(
                        chunk_origin(chunk_of(v)) + local.as_ivec3(),
                        v,
                        "decomposition failed for voxel {v}"
                    );
                }
            }
        }
    }

    /// Floor semantics: a point exactly on a voxel boundary belongs to the
    /// voxel whose minimum corner it is (the higher cell).
    #[test]
    fn voxel_at_boundary_belongs_to_higher_cell() {
        // Scales exactly representable in f32 keep the boundary itself exact.
        assert_eq!(
            voxel_at(Vec3::new(1.0, -1.0, 0.0), 1.0),
            IVec3::new(1, -1, 0)
        );
        assert_eq!(
            voxel_at(Vec3::new(0.5, -0.5, 2.0), 0.5),
            IVec3::new(1, -1, 4)
        );
        // 0.2_f32 is exactly 2 * 0.1_f32 (same mantissa, exponent + 1).
        assert_eq!(voxel_at(Vec3::splat(0.2), 0.1), IVec3::splat(2));
    }

    /// A chunk's origin maps back to that chunk with zero local offset, and
    /// the chunk's maximum corner still lies inside the same chunk.
    #[test]
    fn chunk_origin_roundtrip() {
        let chunks = [
            IVec3::new(0, 0, 0),
            IVec3::new(1, 2, 3),
            IVec3::new(-1, -2, -3),
            IVec3::new(-100, 50, -7),
        ];
        for &c in &chunks {
            let origin = chunk_origin(c);
            assert_eq!(chunk_of(origin), c, "origin of {c} must map back");
            assert_eq!(local_of(origin), UVec3::ZERO);
            let max_corner = origin + IVec3::splat(CHUNK - 1);
            assert_eq!(
                chunk_of(max_corner),
                c,
                "max corner of {c} must stay inside"
            );
            assert_eq!(local_of(max_corner), UVec3::splat(CHUNK as u32 - 1));
        }
    }
}
