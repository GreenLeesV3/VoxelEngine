//! Player tools: place, break, and (from M5) blast.

use glam::Vec3;
use vox_core::consts::REACH;
use vox_core::{MaterialRegistry, voxel_center_m};
use vox_physics::Aabb;
use vox_world::{AIR, Voxel, World, raycast};

/// The selectable tools.
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub enum Tool {
    Place,
    Break,
    Blast,
}

/// Tool state: active tool and selected build material.
pub struct Tools {
    pub tool: Tool,
    /// Index into the registry (skips air).
    material_index: usize,
    material_count: usize,
}

impl Tools {
    pub fn new(registry: &MaterialRegistry) -> Self {
        Self {
            tool: Tool::Place,
            material_index: 1,
            material_count: registry.len(),
        }
    }

    /// Currently selected build material.
    pub fn material(&self) -> Voxel {
        Voxel(self.material_index as u16)
    }

    /// Cycle the build material by `steps` (mouse wheel), skipping air.
    pub fn cycle_material(&mut self, steps: i32, registry: &MaterialRegistry) {
        let n = self.material_count as i32 - 1; // excluding air
        if n <= 0 {
            return;
        }
        let cur = self.material_index as i32 - 1;
        let next = (cur + steps).rem_euclid(n) + 1;
        self.material_index = next as usize;
        if let Some(def) = registry.get(vox_core::MaterialId(next as u16)) {
            tracing::info!(material = %def.name, "selected build material");
        }
    }

    /// Break the voxel under the crosshair.
    pub fn break_voxel(&self, world: &mut World, eye_m: Vec3, look: Vec3) {
        if let Some(hit) = raycast(world, eye_m, look, REACH) {
            world.set_voxel(hit.voxel, AIR);
        }
    }

    /// Place the selected material against the hit face, unless it would
    /// intersect the player.
    pub fn place_voxel(&self, world: &mut World, eye_m: Vec3, look: Vec3, player: Aabb) {
        let Some(hit) = raycast(world, eye_m, look, REACH) else {
            return;
        };
        let Some(face) = hit.face else {
            return; // Eye inside a solid voxel; nowhere to place.
        };
        let target = hit.voxel + face;
        let s = world.cfg.voxel_size_m;
        let c = voxel_center_m(target, s);
        let half = s * 0.5;
        let overlaps = (c.x + half > player.min.x && c.x - half < player.max.x)
            && (c.y + half > player.min.y && c.y - half < player.max.y)
            && (c.z + half > player.min.z && c.z - half < player.max.z);
        if !overlaps {
            world.set_voxel(target, self.material());
        }
    }
}
