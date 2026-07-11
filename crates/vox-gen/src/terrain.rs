//! Heightmap terrain generation.
//!
//! Heights are computed in **meters** from noise layers with meter
//! wavelengths and amplitudes, then quantized per world voxel scale at the
//! point of use — the same seed produces the same landscape at any scale
//! (enforced by the `scale_invariance` test).

use glam::{IVec3, UVec3, Vec2};
use vox_core::consts::CHUNK_SIZE;
use vox_core::{MaterialRegistry, WorldConfig};
use vox_world::{Chunk, Voxel, World};

use crate::noise::{Fbm, mix_seed_u64};

/// Terrain material ids resolved once from the registry.
#[derive(Copy, Clone, Debug)]
pub struct TerrainMaterials {
    pub stone: Voxel,
    pub dirt: Voxel,
    pub grass: Voxel,
    pub sandstone: Voxel,
    pub snow: Voxel,
}

impl TerrainMaterials {
    /// Resolve from the registry; missing core materials are a startup error.
    pub fn from_registry(reg: &MaterialRegistry) -> Result<Self, vox_core::CoreError> {
        let id = |name: &str| -> Result<Voxel, vox_core::CoreError> {
            reg.id_by_name(name)
                .map(|m| Voxel(m.0))
                .ok_or_else(|| vox_core::CoreError::Asset {
                    path: "assets/materials".into(),
                    reason: format!("terrain requires core material `{name}`"),
                })
        };
        Ok(Self {
            stone: id("stone")?,
            dirt: id("dirt")?,
            grass: id("grass")?,
            sandstone: id("sandstone")?,
            snow: id("snow")?,
        })
    }

    /// Surface voxel for a biome, matched directly on the enum (no registry
    /// is available at fill time).
    pub fn surface(self, biome: crate::biome::Biome) -> Voxel {
        match biome {
            crate::biome::Biome::Plains => self.grass,
            crate::biome::Biome::Forest => self.grass,
            crate::biome::Biome::Desert => self.sandstone,
            crate::biome::Biome::Snow => self.snow,
        }
    }
}

/// Conservative upper bound on the biome dirt band thickness, in meters.
/// Used only for the uniform-stone fast-path bound; the per-column dirt
/// depth is biome-driven (ranges 0.5–3.0 m, max = Forest).
const DIRT_DEPTH_M: f32 = 3.0;
/// Terrain height clamp margins (meters above floor / below ceiling).
const MIN_HEIGHT_M: f32 = 4.0;
const CEIL_MARGIN_M: f32 = 6.0;

/// Heightmap terrain generator for one world configuration.
pub struct TerrainGen {
    continents: Fbm,
    hills: Fbm,
    rough: Fbm,
    base_m: f32,
    max_m: f32,
}

impl TerrainGen {
    pub fn new(cfg: &WorldConfig) -> Self {
        debug_assert!(
            cfg.extent_m[1] >= MIN_HEIGHT_M + CEIL_MARGIN_M,
            "world extent_m.y must be >= MIN_HEIGHT_M + CEIL_MARGIN_M for terrain"
        );
        let s = |k: u32| -> u32 { mix_seed_u64(cfg.seed, k) };
        Self {
            continents: Fbm::new(5, s(0x0001)),
            hills: Fbm::new(4, s(0x00E2)),
            rough: Fbm::new(3, s(0x0F3A)),
            base_m: cfg.extent_m[1] * 0.45,
            max_m: cfg.extent_m[1] - CEIL_MARGIN_M,
        }
    }

    /// Terrain surface height at a world position, in meters.
    pub fn height_m(&self, x_m: f32, z_m: f32) -> f32 {
        let p = Vec2::new(x_m, z_m);
        let h = self.base_m
            + self.continents.sample2(p / 900.0) * 22.0
            + self.hills.sample2(p / 160.0) * 9.0
            + self.rough.sample2(p / 28.0) * 2.2;
        h.clamp(MIN_HEIGHT_M, self.max_m.max(MIN_HEIGHT_M))
    }

    /// Generate terrain into an empty world (chunk-batched: uniform stone
    /// below, air above, per-column fill in the surface band).
    pub fn generate(&self, world: &mut World, mats: TerrainMaterials, biomes: &crate::biome::BiomeMap) {
        let s = world.cfg.voxel_size_m;
        let chunks = world.cfg.extent_chunks();
        let chunk_m = CHUNK_SIZE as f32 * s;

        for cz in 0..chunks.z {
            for cx in 0..chunks.x {
                // Conservative height range over this chunk column.
                let x0 = cx as f32 * chunk_m;
                let z0 = cz as f32 * chunk_m;
                let mut min_h = f32::INFINITY;
                let mut max_h = f32::NEG_INFINITY;
                for (sx, sz) in [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0), (0.5, 0.5)] {
                    let h = self.height_m(x0 + sx * chunk_m, z0 + sz * chunk_m);
                    min_h = min_h.min(h);
                    max_h = max_h.max(h);
                }
                min_h -= 2.0;
                max_h += 2.0;

                for cy in 0..chunks.y {
                    let bottom_m = cy as f32 * chunk_m;
                    let top_m = bottom_m + chunk_m;
                    if top_m < min_h - DIRT_DEPTH_M {
                        world.insert_chunk(IVec3::new(cx, cy, cz), Chunk::uniform(mats.stone));
                    } else if bottom_m > max_h {
                        // Air: absent chunks already read as air.
                    } else {
                        let chunk = self.fill_surface_chunk(IVec3::new(cx, cy, cz), s, mats, biomes);
                        world.insert_chunk(IVec3::new(cx, cy, cz), chunk);
                    }
                }
            }
        }
    }

    /// Build one chunk in the surface band, column by column.
    fn fill_surface_chunk(
        &self,
        key: IVec3,
        s: f32,
        mats: TerrainMaterials,
        biomes: &crate::biome::BiomeMap,
    ) -> Chunk {
        let mut chunk = Chunk::new();
        let origin = key * CHUNK_SIZE as i32;
        for lz in 0..CHUNK_SIZE as i32 {
            for lx in 0..CHUNK_SIZE as i32 {
                let wx = origin.x + lx;
                let wz = origin.z + lz;
                // Column center, in meters.
                let cx_m = (wx as f32 + 0.5) * s;
                let cz_m = (wz as f32 + 0.5) * s;
                // Sample at the column center, in meters.
                let h_m = self.height_m(cx_m, cz_m);
                // Topmost solid voxel index for this column.
                let top = ((h_m / s).round() as i32 - 1).max(0);
                let biome = biomes.biome_at(cx_m, cz_m);
                let surface = mats.surface(biome);
                let dirt_depth = biome.dirt_depth();
                let dirt_from = top - (dirt_depth / s).round().max(1.0) as i32;
                for ly in 0..CHUNK_SIZE as i32 {
                    let wy = origin.y + ly;
                    if wy > top {
                        break;
                    }
                    let v = if wy == top {
                        surface
                    } else if wy >= dirt_from {
                        mats.dirt
                    } else {
                        mats.stone
                    };
                    chunk.set(UVec3::new(lx as u32, ly as u32, lz as u32), v);
                }
            }
        }
        chunk
    }

    /// Topmost solid voxel surface height in meters, by column scan.
    /// Test/spawn helper — O(world height).
    pub fn surface_height_m(world: &World, x_m: f32, z_m: f32) -> Option<f32> {
        let s = world.cfg.voxel_size_m;
        let (min, max) = world.bounds_voxels();
        let wx = (x_m / s).floor() as i32;
        let wz = (z_m / s).floor() as i32;
        for wy in (min.y..max.y).rev() {
            if world.solid(IVec3::new(wx, wy, wz)) {
                return Some((wy + 1) as f32 * s);
            }
        }
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::noise::hash2;

    fn mats() -> TerrainMaterials {
        TerrainMaterials {
            stone: Voxel(1),
            dirt: Voxel(2),
            grass: Voxel(3),
            sandstone: Voxel(4),
            snow: Voxel(5),
        }
    }

    fn biomes() -> crate::biome::BiomeMap {
        crate::biome::BiomeMap::new(424_242)
    }

    fn test_cfg(voxel_size_m: f32) -> WorldConfig {
        WorldConfig {
            seed: 424_242,
            voxel_size_m,
            extent_m: [64.0, 32.0, 64.0],
        }
    }

    /// Deterministic sample positions inside the world footprint (meters),
    /// away from the borders.
    fn sample_positions(n: usize) -> Vec<(f32, f32)> {
        (0..n)
            .map(|i| {
                let hx = hash2(i as i32, 17, 0xABCD) as f32 / u32::MAX as f32;
                let hz = hash2(i as i32, 99, 0xABCD) as f32 / u32::MAX as f32;
                (4.0 + hx * 56.0, 4.0 + hz * 56.0)
            })
            .collect()
    }

    #[test]
    fn heights_stay_in_bounds() {
        let cfg = test_cfg(0.1);
        let terrain = TerrainGen::new(&cfg);
        for (x, z) in sample_positions(200) {
            let h = terrain.height_m(x, z);
            assert!(
                (MIN_HEIGHT_M..=cfg.extent_m[1] - CEIL_MARGIN_M).contains(&h),
                "height {h} out of bounds at ({x}, {z})"
            );
        }
    }

    #[test]
    fn grass_on_top_dirt_below_stone_deep() {
        let cfg = test_cfg(0.25);
        let terrain = TerrainGen::new(&cfg);
        let mut world = World::new(cfg);
        terrain.generate(&mut world, mats(), &biomes());
        let s = world.cfg.voxel_size_m;
        let bm = biomes();

        for (x, z) in sample_positions(40) {
            let surface = TerrainGen::surface_height_m(&world, x, z).expect("column has terrain");
            let wx = (x / s).floor() as i32;
            let wz = (z / s).floor() as i32;
            let top = (surface / s).round() as i32 - 1;
            let biome = bm.biome_at(x, z);

            assert_eq!(
                world.get_voxel(IVec3::new(wx, top, wz)),
                mats().surface(biome),
                "top voxel must match biome surface at ({x}, {z}) ({biome:?})"
            );
            let below = top - 1;
            // Desert has a thin (0.5 m) dirt band; at coarse voxel sizes the
            // dirt layer may collapse to zero voxels, so only assert dirt when
            // the biome's band is deep enough to cover the voxel below.
            if biome.dirt_depth() > s {
                assert_eq!(
                    world.get_voxel(IVec3::new(wx, below, wz)),
                    mats().dirt,
                    "voxel below surface must be dirt ({biome:?})"
                );
            }
            let deep_m = 3.0;
            let deep = top - (deep_m / s) as i32;
            if deep > 0 {
                assert_eq!(
                    world.get_voxel(IVec3::new(wx, deep, wz)),
                    mats().stone,
                    "3 m down must be stone"
                );
            }
            // Above the surface must be air.
            assert_eq!(world.get_voxel(IVec3::new(wx, top + 1, wz)), Voxel(0));
        }
    }
    /// THE scale contract: the same seed produces the same landscape in
    /// meters at 0.1 m and 1.0 m voxels.
    #[test]
    fn scale_invariance() {
        let cfg_fine = test_cfg(0.1);
        let cfg_coarse = test_cfg(1.0);
        let gen_fine = TerrainGen::new(&cfg_fine);
        let gen_coarse = TerrainGen::new(&cfg_coarse);

        let mut fine = World::new(cfg_fine);
        let mut coarse = World::new(cfg_coarse);
        gen_fine.generate(&mut fine, mats(), &biomes());
        gen_coarse.generate(&mut coarse, mats(), &biomes());

        let tolerance = 2.0 * 1.0f32; // 2 x the coarser voxel size, meters
        for (x, z) in sample_positions(50) {
            let a = TerrainGen::surface_height_m(&fine, x, z).expect("fine terrain");
            let b = TerrainGen::surface_height_m(&coarse, x, z).expect("coarse terrain");
            assert!(
                (a - b).abs() <= tolerance,
                "surface diverges at ({x}, {z}): fine {a} m vs coarse {b} m"
            );
        }
    }

    #[test]
    fn deep_chunks_use_uniform_storage() {
        let cfg = test_cfg(0.25);
        let terrain = TerrainGen::new(&cfg);
        let mut world = World::new(cfg);
        terrain.generate(&mut world, mats(), &biomes());

        // The fast path must have produced at least one uniform-stone chunk
        // somewhere under the surface band.
        let uniform_stone = world
            .chunks()
            .filter(|(_, c)| c.uniform_value() == Some(mats().stone))
            .count();
        assert!(uniform_stone > 0, "no uniform stone chunks generated");

        // And the world floor is always stone.
        assert_eq!(world.get_voxel(IVec3::new(50, 0, 50)), mats().stone);
    }
}
