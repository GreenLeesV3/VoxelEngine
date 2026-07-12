//! Player-centered chunk streaming: generates chunks around the player on
//! demand, evicts them beyond render distance. Mirrors `SurfaceProvider`'s
//! center/threshold/radius idiom.
//!
//! Pristine chunks (generated, never edited) evict fully — regenerated
//! deterministically on return. Edited chunks keep their voxel data; only
//! their GPU mesh drops.

use glam::{IVec3, Vec3};
use vox_core::consts::CHUNK_SIZE;
use vox_core::{WorldConfig, chunk_of, chunk_origin};
use vox_gen::{BiomeMap, ChunkBand, TerrainGen, TerrainMaterials, TreeMaterials, stamp_tree, trees_for_chunk};
use vox_render::{Gpu, VoxelPipeline};
use vox_world::{AIR, Chunk, World};

use crate::args::Quality;

/// Don't re-scan unless the player moved at least this many meters.
const RELOAD_THRESHOLD_M: f32 = 8.0;

pub struct ChunkLoader {
    quality: Quality,
    last_center_chunk: IVec3,
    terrain: TerrainGen,
    terrain_mats: TerrainMaterials,
    tree_mats: TreeMaterials,
    biomes: BiomeMap,
}

impl ChunkLoader {
    pub fn new(
        cfg: &WorldConfig,
        quality: Quality,
        terrain: TerrainGen,
        terrain_mats: TerrainMaterials,
        tree_mats: TreeMaterials,
    ) -> Self {
        Self {
            quality,
            last_center_chunk: IVec3::splat(i32::MAX),
            terrain,
            terrain_mats,
            tree_mats,
            biomes: BiomeMap::new(cfg.seed),
        }
    }

    pub fn quality(&self) -> Quality {
        self.quality
    }

    pub fn set_quality(&mut self, q: Quality) {
        self.quality = q;
        // Force reload on next update.
        self.last_center_chunk = IVec3::splat(i32::MAX);
    }

    /// Player's chunk key from world position.
    fn player_chunk(pos: Vec3, voxel_size: f32) -> IVec3 {
        let chunk_m = CHUNK_SIZE as f32 * voxel_size;
        IVec3::new(
            (pos.x / chunk_m).floor() as i32,
            (pos.y / chunk_m).floor() as i32,
            (pos.z / chunk_m).floor() as i32,
        )
    }

    /// Pre-generate chunks around a position for spawn. Synchronous —
    /// generates all chunks within the detail ring before returning.
    pub fn pregenerate_spawn(
        &mut self,
        player_pos: Vec3,
        world: &mut World,
        pipeline: &mut VoxelPipeline,
        gpu: &Gpu,
    ) {
        let center = Self::player_chunk(player_pos, world.cfg.voxel_size_m);
        let s = world.cfg.voxel_size_m;
        // Synchronous spawn: generate enough chunks to fill the initial view.
        // Capped at 16 chunks radius (matches render_distance cap).
        let spawn_radius = self.quality.render_distance(s).min(8);
        let ring = self.quality.detail_ring();
        self.generate_ring(world, pipeline, gpu, center, spawn_radius, ring);
        self.last_center_chunk = center;
    }

    /// Per-frame update: generate missing chunks near the player, evict
    /// chunks beyond render distance. Returns whether any changes were made.
    pub fn update(
        &mut self,
        player_pos: Vec3,
        world: &mut World,
        pipeline: &mut VoxelPipeline,
        gpu: &Gpu,
    ) -> bool {
        let s = world.cfg.voxel_size_m;
        let center = Self::player_chunk(player_pos, s);
        // Skip the full missing-chunk scan unless the player moved enough
        // meters OR we haven't filled the render distance yet. At 0.1m
        // voxels chunks are only 3.2m, so the threshold prevents scanning
        // every frame — but we still need to fill in chunks after spawn.
        let chunk_m = CHUNK_SIZE as f32 * s;
        let moved_chunks = (center - self.last_center_chunk).abs().max_element();
        let moved_m = moved_chunks as f32 * chunk_m;
        let moved_enough = moved_m >= RELOAD_THRESHOLD_M;
        if moved_enough {
            self.last_center_chunk = center;
        }

        let render_dist = self.quality.render_distance(world.cfg.voxel_size_m);
        let detail_ring = self.quality.detail_ring();

        // Only scan + generate when the player moved enough meters.
        // Standing still = no scan (chunks near player are already loaded).
        if !moved_enough {
            return false;
        }

        let budget = self.quality.gen_budget(world.cfg.voxel_size_m);
        let generated = self.generate_missing(world, pipeline, gpu, center, render_dist, detail_ring, budget);
        let evicted = self.evict_beyond_range(world, pipeline, center, render_dist);

        generated || evicted
    }

    /// Generate missing chunks within render distance, up to `budget`,
    /// nearest to `center` first.
    fn generate_missing(
        &self,
        world: &mut World,
        pipeline: &mut VoxelPipeline,
        gpu: &Gpu,
        center: IVec3,
        render_dist: i32,
        detail_ring: i32,
        budget: usize,
    ) -> bool {
        let (bmin, bmax) = world.bounds_voxels();
        let chunk_min = chunk_of(bmin);
        let chunk_max = chunk_of(bmax - IVec3::ONE);

        // Only scan a small radius around the player each frame — not the
        // full render distance sphere. At 0.1m with render_dist=40, scanning
        // the full sphere is 531k iterations. Instead, check a growing ring
        // starting from the player outward, stopping once we've found enough
        // missing chunks to fill the budget. This is O(small) per frame.
        let mut missing: Vec<(i64, IVec3)> = Vec::new();
        let max_scan_r = render_dist.min(12); // Cap scan radius for perf
        'outer: for r in 0..=max_scan_r {
            // Shell at distance r: only check chunks where max(|dx|,|dy|,|dz|) == r
            for dz in -r..=r {
                for dy in -r..=r {
                    for dx in -r..=r {
                        if dx.abs().max(dy.abs()).max(dz.abs()) != r { continue; }
                        let key = center + IVec3::new(dx, dy, dz);
                        if key.x < chunk_min.x || key.x > chunk_max.x { continue; }
                        if key.y < chunk_min.y || key.y > chunk_max.y { continue; }
                        if key.z < chunk_min.z || key.z > chunk_max.z { continue; }
                        if world.chunk_at(key).is_some() { continue; }
                        let dist = (dx * dx + dy * dy + dz * dz) as i64;
                        missing.push((dist, key));
                        if missing.len() >= budget * 2 {
                            break 'outer;
                        }
                    }
                }
            }
        }

        let mut generated = false;
        for (_, key) in missing.into_iter() {
            self.generate_chunk(world, pipeline, gpu, key, center, detail_ring);
            generated = true;
        }
        generated
    }

    /// Generate all chunks within `radius` (synchronous, for spawn).
    fn generate_ring(
        &self,
        world: &mut World,
        pipeline: &mut VoxelPipeline,
        gpu: &Gpu,
        center: IVec3,
        radius: i32,
        detail_ring: i32,
    ) {
        let (bmin, bmax) = world.bounds_voxels();
        let chunk_min = chunk_of(bmin);
        let chunk_max = chunk_of(bmax - IVec3::ONE);

        for dz in -radius..=radius {
            for dy in -radius..=radius {
                for dx in -radius..=radius {
                    let key = center + IVec3::new(dx, dy, dz);
                    if key.x < chunk_min.x || key.x > chunk_max.x { continue; }
                    if key.y < chunk_min.y || key.y > chunk_max.y { continue; }
                    if key.z < chunk_min.z || key.z > chunk_max.z { continue; }
                    if world.chunk_at(key).is_some() { continue; }
                    self.generate_chunk(world, pipeline, gpu, key, center, detail_ring);
                }
            }
        }
    }

    /// Generate one chunk using the three-case height-band optimization
    /// (mirrors `TerrainGen::generate`): uniform stone below the surface
    /// band, skipped air above, per-column surface fill (with clipped trees)
    /// only in the surface band. Avoids allocating air chunks and dense
    /// 64 KB stone chunks.
    ///
    /// Tree stamping is UNCONDITIONAL across the canopy-reach neighborhood:
    /// the loop stamps all trees rooted in near (detail-ring) chunks whose
    /// canopy overlaps this chunk. When this chunk is itself near, dx=0/dz=0
    /// includes self → own-rooted trees stamp. When far, self is filtered
    /// out by the detail-ring check → only near-neighbor canopy stamps.
    /// This keeps trees whole across ALL chunk boundaries, not just the
    /// detail-ring boundary.
    fn generate_chunk(
        &self,
        world: &mut World,
        _pipeline: &mut VoxelPipeline,
        _gpu: &Gpu,
        key: IVec3,
        center_chunk: IVec3,
        detail_ring: i32,
    ) {
        let s = world.cfg.voxel_size_m;

        // Suppress edit tracking during generation.
        world.set_suppress_edit_tracking(true);

        match self.terrain.chunk_band(key, s) {
            ChunkBand::Stone => {
                world.insert_chunk(key, Chunk::uniform(self.terrain_mats.stone));
            }
            ChunkBand::Air => {
                // Insert an empty chunk so tree canopy voxels from
                // surface chunks below have somewhere to land.
                world.insert_chunk(key, Chunk::uniform(AIR));
            }
            ChunkBand::Surface => {
                let chunk = self.terrain.fill_surface_chunk(key, s, self.terrain_mats, &self.biomes);
                world.insert_chunk(key, chunk);
            }
        }

        // Canopy stamping runs for both Surface AND Air chunks so trees
        // whose canopy extends into the chunk above (Air) get their
        // upper leaves stamped. Stone chunks are too deep for canopy.
        if matches!(self.terrain.chunk_band(key, s), ChunkBand::Surface | ChunkBand::Air) {
            let origin = chunk_origin(key);
            let clip_min = origin;
            let clip_max = origin + IVec3::splat(CHUNK_SIZE as i32);
            world.set_clip(clip_min, clip_max);

            // Canopy reach: trees are ~10m tall. At 0.5m voxels, chunk_m=16m
            // so 1 chunk suffices. At 0.1m voxels, chunk_m=3.2m so we need
            // ceil(10/3.2)+1 = 4 chunks. Compute from voxel size.
            let chunk_m = CHUNK_SIZE as f32 * s;
            let canopy_reach_chunks = ((10.0 / chunk_m).ceil() as i32 + 1).max(2);
            for dy in -canopy_reach_chunks..=canopy_reach_chunks {
                for dz in -canopy_reach_chunks..=canopy_reach_chunks {
                    for dx in -canopy_reach_chunks..=canopy_reach_chunks {
                        let neighbor = IVec3::new(key.x + dx, key.y + dy, key.z + dz);
                        // Trees are structural terrain, not LOD detail —
                        // always root regardless of distance tier.
                        let trees = trees_for_chunk(&world.cfg, &self.terrain, neighbor);
                        for tree in &trees {
                            stamp_tree(world, tree, self.tree_mats);
                        }
                    }
                }
            }

            world.clear_clip();
        }

        world.set_suppress_edit_tracking(false);
    }

    /// Evict pristine chunks beyond render distance. Edited chunks keep
    /// their voxel data (only mesh drops — handled by caller via
    /// `pipeline.remove_chunk`).
    fn evict_beyond_range(
        &self,
        world: &mut World,
        pipeline: &mut VoxelPipeline,
        center: IVec3,
        render_dist: i32,
    ) -> bool {
        let render_dist_sq = (render_dist + 1) as i64; // +1 for hysteresis
        let render_dist_sq = render_dist_sq * render_dist_sq;
        let cap = self.quality.chunk_cap(world.cfg.voxel_size_m, world.cfg.extent_m[1]);
        let to_evict: Vec<IVec3> = world
            .chunks()
            .filter(|(key, _)| {
                let dx = key.x - center.x;
                let dy = key.y - center.y;
                let dz = key.z - center.z;
                (dx * dx + dy * dy + dz * dz) as i64 > render_dist_sq
            })
            .map(|(k, _)| k)
            .collect();

        let mut evicted = false;
        for key in to_evict {
            if world.is_edited(key) {
                // Edited: drop mesh only, keep data.
                pipeline.remove_chunk(key);
            } else {
                // Pristine: evict fully.
                world.remove_chunk(key);
                pipeline.remove_chunk(key);
            }
            evicted = true;
        }

        // Budget guard: if still over cap, evict farthest pristine first.
        let loaded = world.chunk_count();
        if loaded > cap {
            let mut pristine: Vec<(i64, IVec3)> = world
                .chunks()
                .filter(|(k, _)| !world.is_edited(*k))
                .map(|(k, _)| {
                    let dx = k.x - center.x;
                    let dy = k.y - center.y;
                    let dz = k.z - center.z;
                    (dx as i64 * dx as i64 + dy as i64 * dy as i64 + dz as i64 * dz as i64, k)
                })
                .collect();
            pristine.sort_by_key(|(d, _)| *d);
            for (_, key) in pristine.iter().rev().take(loaded - cap) {
                world.remove_chunk(*key);
                pipeline.remove_chunk(*key);
                evicted = true;
            }
        }

        evicted
    }
}
