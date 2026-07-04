//! Immutable per-world configuration: seed, voxel scale, and world extents,
//! with validation into typed errors.

use glam::{IVec3, Vec3};

use crate::consts::CHUNK_SIZE;
use crate::error::CoreError;

/// Minimum accepted voxel size in meters.
const MIN_VOXEL_SIZE_M: f32 = 0.01;
/// Maximum accepted voxel size in meters.
const MAX_VOXEL_SIZE_M: f32 = 4.0;
/// Maximum accepted world extent per axis, in voxels (keeps downstream
/// chunk/voxel index math comfortably inside `i32`).
const MAX_EXTENT_VOXELS: f32 = 1_048_576.0;

/// Immutable per-world configuration. All lengths in meters.
#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct WorldConfig {
    /// PRNG seed for world generation.
    pub seed: u64,
    /// Edge length of one voxel in meters.
    pub voxel_size_m: f32,
    /// World extent per axis (x, y, z) in meters.
    pub extent_m: [f32; 3],
}

impl Default for WorldConfig {
    fn default() -> Self {
        Self {
            seed: 1337,
            voxel_size_m: 0.1,
            extent_m: [256.0, 64.0, 256.0],
        }
    }
}

impl WorldConfig {
    /// World extent in whole chunks (ceil), per axis.
    pub fn extent_chunks(&self) -> IVec3 {
        let chunk_m = self.voxel_size_m * CHUNK_SIZE as f32;
        (Vec3::from(self.extent_m) / chunk_m).ceil().as_ivec3()
    }

    /// World extent in voxels (ceil), per axis.
    pub fn extent_voxels(&self) -> IVec3 {
        (Vec3::from(self.extent_m) / self.voxel_size_m)
            .ceil()
            .as_ivec3()
    }

    /// Validate the configuration: `voxel_size_m` must lie in
    /// [`MIN_VOXEL_SIZE_M`, `MAX_VOXEL_SIZE_M`] and every extent must be
    /// finite, positive, and at most [`MAX_EXTENT_VOXELS`] voxels.
    pub fn validate(&self) -> Result<(), CoreError> {
        // NaN and infinities fail the range check as well.
        if !(MIN_VOXEL_SIZE_M..=MAX_VOXEL_SIZE_M).contains(&self.voxel_size_m) {
            return Err(CoreError::Config {
                field: "voxel_size_m",
                reason: format!(
                    "must be in [{MIN_VOXEL_SIZE_M}, {MAX_VOXEL_SIZE_M}] m, got {}",
                    self.voxel_size_m
                ),
            });
        }
        for (axis, &extent) in ["x", "y", "z"].iter().zip(&self.extent_m) {
            if !extent.is_finite() || extent <= 0.0 {
                return Err(CoreError::Config {
                    field: "extent_m",
                    reason: format!("{axis} extent must be finite and > 0 m, got {extent}"),
                });
            }
            if extent / self.voxel_size_m > MAX_EXTENT_VOXELS {
                return Err(CoreError::Config {
                    field: "extent_m",
                    reason: format!(
                        "{axis} extent of {extent} m exceeds {MAX_EXTENT_VOXELS} voxels at {} m per voxel",
                        self.voxel_size_m
                    ),
                });
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_config_validates() {
        let cfg = WorldConfig::default();
        assert_eq!(cfg.seed, 1337);
        cfg.validate().expect("default config must validate");
    }

    #[test]
    fn default_extents_in_chunks_and_voxels() {
        // 0.1 m voxels over 256 x 64 x 256 m => 3.2 m chunks => 80 x 20 x 80.
        let cfg = WorldConfig::default();
        assert_eq!(cfg.extent_chunks(), IVec3::new(80, 20, 80));
        assert_eq!(cfg.extent_voxels(), IVec3::new(2560, 640, 2560));
    }

    #[test]
    fn extent_chunks_rounds_up_partial_chunks() {
        let cfg = WorldConfig {
            voxel_size_m: 1.0,
            extent_m: [33.0, 32.0, 1.0],
            ..WorldConfig::default()
        };
        assert_eq!(cfg.extent_chunks(), IVec3::new(2, 1, 1));
        assert_eq!(cfg.extent_voxels(), IVec3::new(33, 32, 1));
    }

    #[test]
    fn invalid_voxel_sizes_are_rejected_naming_the_field() {
        for bad in [0.0_f32, -0.1, f32::NAN, 0.0099, 4.1, f32::INFINITY] {
            let cfg = WorldConfig {
                voxel_size_m: bad,
                ..WorldConfig::default()
            };
            let err = cfg
                .validate()
                .err()
                .unwrap_or_else(|| panic!("voxel size {bad} must be rejected"));
            assert!(
                err.to_string().contains("voxel_size_m"),
                "error must name the field: {err}"
            );
        }
    }

    #[test]
    fn boundary_voxel_sizes_are_accepted() {
        for ok in [0.01_f32, 4.0] {
            let cfg = WorldConfig {
                voxel_size_m: ok,
                ..WorldConfig::default()
            };
            cfg.validate()
                .unwrap_or_else(|e| panic!("voxel size {ok} should validate: {e}"));
        }
    }

    #[test]
    fn non_positive_or_non_finite_extents_are_rejected() {
        let bad_extents = [
            [0.0_f32, 64.0, 256.0],
            [256.0, -1.0, 256.0],
            [256.0, 64.0, f32::NAN],
            [f32::INFINITY, 64.0, 256.0],
        ];
        for bad in bad_extents {
            let cfg = WorldConfig {
                extent_m: bad,
                ..WorldConfig::default()
            };
            let err = cfg
                .validate()
                .expect_err("non-positive/non-finite extent must be rejected");
            assert!(
                err.to_string().contains("extent_m"),
                "error must name the field: {err}"
            );
        }
    }

    #[test]
    fn absurdly_large_extents_are_rejected() {
        let cfg = WorldConfig {
            voxel_size_m: 0.01,
            extent_m: [1.0e9, 64.0, 256.0],
            ..WorldConfig::default()
        };
        let err = cfg
            .validate()
            .expect_err("oversized extent must be rejected");
        assert!(
            err.to_string().contains("extent_m"),
            "error must name the field: {err}"
        );
    }

    #[test]
    fn serde_toml_roundtrip() {
        let cfg = WorldConfig::default();
        let text = toml::to_string(&cfg).expect("serialize");
        let back: WorldConfig = toml::from_str(&text).expect("deserialize");
        assert_eq!(back.seed, cfg.seed);
        assert_eq!(back.voxel_size_m, cfg.voxel_size_m);
        assert_eq!(back.extent_m, cfg.extent_m);
    }
}
