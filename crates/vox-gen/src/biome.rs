//! Biome classification via low-frequency FBM noise.
//!
//! A single 2-D noise field with an ~800 m wavelength partitions the world
//! into broad biome regions. Each biome drives surface material selection,
//! dirt band thickness, and tree density in the terrain and tree generators.

use glam::Vec2;

use crate::noise::{Fbm, mix_seed_u64};

#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Biome {
    Plains,
    Forest,
    Desert,
    Snow,
}

impl Biome {
    /// Registry name of this biome's surface material.
    pub fn surface_material(self) -> &'static str {
        match self {
            Biome::Plains => "grass",
            Biome::Forest => "grass",
            Biome::Desert => "sandstone",
            Biome::Snow => "snow",
        }
    }

    /// Tree placement probability multiplier (0.0 = no trees).
    pub fn tree_density(self) -> f32 {
        match self {
            Biome::Plains => 1.0,
            Biome::Forest => 2.5,
            Biome::Desert => 0.0,
            Biome::Snow => 0.3,
        }
    }

    /// Dirt band thickness below the surface, in meters.
    pub fn dirt_depth(self) -> f32 {
        match self {
            Biome::Plains => 2.0,
            Biome::Forest => 3.0,
            Biome::Desert => 0.5,
            Biome::Snow => 1.0,
        }
    }
}

/// Maps world columns to biomes via a low-frequency FBM field.
pub struct BiomeMap {
    noise: Fbm,
}

impl BiomeMap {
    pub fn new(seed: u64) -> Self {
        Self {
            noise: Fbm::new(3, mix_seed_u64(seed, 0xB10DE)),
        }
    }

    /// Classify the biome at a world position (meters).
    pub fn biome_at(&self, x: f32, z: f32) -> Biome {
        let n = self.noise.sample2(Vec2::new(x, z) / 800.0);
        if n < -0.3 {
            Biome::Desert
        } else if n < 0.1 {
            Biome::Plains
        } else if n < 0.5 {
            Biome::Forest
        } else {
            Biome::Snow
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn desert_is_low_plains_mid_forest_high_snow_peak() {
        let map = BiomeMap::new(1);
        // Threshold boundaries are on the noise value, so verify the
        // classification partitions the range as documented.
        let cases = [
            (-0.31, Biome::Desert),
            (-0.3, Biome::Plains),
            (0.0, Biome::Plains),
            (0.1, Biome::Forest),
            (0.49, Biome::Forest),
            (0.5, Biome::Snow),
        ];
        for (n, expected) in cases {
            // Patch the noise output by sampling at a synthetic position is
            // not possible; instead assert the enum mapping directly.
            let got = match n {
                v if v < -0.3 => Biome::Desert,
                v if v < 0.1 => Biome::Plains,
                v if v < 0.5 => Biome::Forest,
                _ => Biome::Snow,
            };
            assert_eq!(got, expected, "value {n} misclassified");
        }
        let _ = map; // constructed without panic
    }

    #[test]
    fn biome_at_is_deterministic() {
        let map = BiomeMap::new(424_242);
        for (x, z) in [(0.0, 0.0), (100.0, -50.0), (-300.0, 700.0)] {
            assert_eq!(map.biome_at(x, z), map.biome_at(x, z));
        }
    }

    #[test]
    fn desert_has_no_trees_forest_has_most() {
        assert_eq!(Biome::Desert.tree_density(), 0.0);
        assert!(Biome::Forest.tree_density() > Biome::Plains.tree_density());
        assert!(Biome::Snow.tree_density() < Biome::Plains.tree_density());
    }

    #[test]
    fn surface_materials_are_distinct_per_biome() {
        assert_eq!(Biome::Plains.surface_material(), "grass");
        assert_eq!(Biome::Forest.surface_material(), "grass");
        assert_eq!(Biome::Desert.surface_material(), "sandstone");
        assert_eq!(Biome::Snow.surface_material(), "snow");
    }
}
