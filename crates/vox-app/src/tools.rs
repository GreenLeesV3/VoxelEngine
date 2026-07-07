//! Player tools: place, break (with a connectivity check), and blast.

use glam::{IVec3, Vec3};
use vox_core::consts::REACH;
use vox_core::{MaterialRegistry, voxel_center_m};
use vox_physics::{Aabb, PhysicsWorld};
use vox_world::{AIR, Voxel, World, raycast};

/// The selectable tools.
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub enum Tool {
    Place,
    Break,
    Blast,
}

/// Blast radius bounds adjustable via `[`/`]`, in meters.
const BLAST_RADIUS_MIN: f32 = 0.5;
const BLAST_RADIUS_MAX: f32 = 4.0;
/// Per-keypress blast radius step, in meters.
const BLAST_RADIUS_STEP: f32 = 0.25;
/// Padding (voxels) searched around a single broken voxel for the
/// connectivity check — a lone support beam knocked out should drop
/// whatever it held up.
const BREAK_CONNECTIVITY_PAD: i32 = 2;

/// Tool state: active tool, selected build material, and blast radius.
pub struct Tools {
    pub tool: Tool,
    pub blast_radius: f32,
    /// Index into the registry (skips air).
    material_index: usize,
    material_count: usize,
}

impl Tools {
    pub fn new(registry: &MaterialRegistry) -> Self {
        Self {
            tool: Tool::Place,
            blast_radius: vox_core::consts::BLAST_RADIUS,
            material_index: 1,
            material_count: registry.len(),
        }
    }

    /// Shrink the blast radius by one step, clamped to [`BLAST_RADIUS_MIN`].
    pub fn shrink_blast_radius(&mut self) {
        self.blast_radius = (self.blast_radius - BLAST_RADIUS_STEP).max(BLAST_RADIUS_MIN);
    }

    /// Grow the blast radius by one step, clamped to [`BLAST_RADIUS_MAX`].
    pub fn grow_blast_radius(&mut self) {
        self.blast_radius = (self.blast_radius + BLAST_RADIUS_STEP).min(BLAST_RADIUS_MAX);
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

    /// Break the voxel under the crosshair. Returns its position if
    /// something was removed, so the caller can run a connectivity check
    /// (a lone support beam knocked out should drop whatever it held up).
    pub fn break_voxel(&self, world: &mut World, eye_m: Vec3, look: Vec3) -> Option<IVec3> {
        let hit = raycast(world, eye_m, look, REACH)?;
        world.set_voxel(hit.voxel, AIR);
        Some(hit.voxel)
    }

    /// Run the connectivity check around a just-broken voxel, detaching
    /// anything that's now unsupported.
    pub fn check_broken_support(
        world: &mut World,
        phys: &mut PhysicsWorld,
        registry: &MaterialRegistry,
        broken: IVec3,
    ) {
        let pad = IVec3::splat(BREAK_CONNECTIVITY_PAD);
        let region = (broken - pad, broken + pad + IVec3::ONE);
        vox_physics::detach_unsupported(world, phys, registry, region);
    }

    /// Blast the crosshair target: carve a sphere, detach whatever becomes
    /// unsupported, and give the debris a blast impulse. `seed` drives
    /// per-body spin variation — pass a different value each call.
    pub fn blast(
        &self,
        world: &mut World,
        phys: &mut PhysicsWorld,
        registry: &MaterialRegistry,
        eye_m: Vec3,
        look: Vec3,
        seed: u32,
    ) {
        let Some(hit) = raycast(world, eye_m, look, REACH) else {
            return;
        };
        let hit_point_m = eye_m + look * hit.dist_m;
        vox_physics::blast(world, phys, registry, hit_point_m, self.blast_radius, seed);
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

#[cfg(test)]
mod tests {
    use super::*;
    use vox_core::WorldConfig;
    use vox_core::consts::PHYSICS_DT;

    fn registry() -> MaterialRegistry {
        MaterialRegistry::from_toml_str(
            r#"
            [[material]]
            name = "stone"
            color = [0.5, 0.5, 0.5]
            density = 2600.0
            strength = 8.0
            [[material]]
            name = "wood"
            color = [0.5, 0.4, 0.3]
            density = 700.0
            strength = 4.0
            "#,
            "test.toml",
        )
        .expect("registry")
    }

    /// A 1-voxel-wide wood pillar at a fixed, known footprint (x,z = 5,5),
    /// resting on a thick stone floor, rising to `height_vox` voxels above
    /// it. Single-voxel cross-section: no corners, so a centered sphere
    /// carve clears it uniformly at every height (matching the proven
    /// geometry in `vox_physics::destruction`'s own pillar tests). The floor
    /// is thick enough (4 m) that a generous blast severing the pillar's
    /// base can't also blow all the way through it — otherwise the debris
    /// would fall through the blast's own crater, which is realistic but
    /// not what this test is checking.
    const FLOOR_THICKNESS_VOX: i32 = 20;
    /// Pillar footprint, centered in a generously large floor so debris
    /// picking up lateral velocity from the blast (plus several rampage
    /// blasts) has real room to drift without exiting the world's bounds
    /// entirely — once outside, there's no floor anywhere and it free-falls
    /// forever, which is a test-world-sizing issue, not a solver bug.
    const PILLAR_XZ_VOX: i32 = 160;

    fn wood_tower(voxel_size_m: f32, height_vox: i32) -> World {
        let mut world = World::new(WorldConfig {
            voxel_size_m,
            extent_m: [64.0, 24.0, 64.0],
            ..WorldConfig::default()
        });
        let (_, max) = world.bounds_voxels();
        world.fill_box(
            IVec3::ZERO,
            IVec3::new(max.x, FLOOR_THICKNESS_VOX, max.z),
            Voxel(1),
        );
        let base = IVec3::new(PILLAR_XZ_VOX, FLOOR_THICKNESS_VOX, PILLAR_XZ_VOX);
        world.fill_box(base, base + IVec3::new(1, height_vox, 1), Voxel(2));
        world
    }

    /// The full player-facing entry point (raycast → carve → detach →
    /// impulse), exercised end to end: blasting a wood tower's base
    /// detaches the upper section as tumbling debris that eventually
    /// settles, with no NaNs or solver blow-up across repeated blasts.
    #[test]
    fn blasting_a_tower_base_detaches_the_top_which_settles() {
        let s = 0.2;
        let mut world = wood_tower(s, 40); // an 8m tall tower
        let reg = registry();
        let mut phys = PhysicsWorld::new();
        let mut tools = Tools::new(&reg);
        tools.tool = Tool::Blast;
        tools.blast_radius = 3.0;

        // Footprint is voxel x,z = PILLAR_XZ_VOX -> center at (+0.5)*s
        // meters. Aim a level, axis-aligned ray straight down +X at the
        // pillar's western face, low enough to be within the base stub.
        let floor_top_m = FLOOR_THICKNESS_VOX as f32 * s;
        let tower_top_m = floor_top_m + 40.0 * s;
        let px = PILLAR_XZ_VOX as f32 * s;
        let cz = px + 0.5 * s;
        let eye = Vec3::new(px - 2.0, floor_top_m + 1.0, cz);
        let look = Vec3::X;
        tools.blast(&mut world, &mut phys, &reg, eye, look, 1);

        assert!(phys.body_count() > 0, "the upper tower section must detach");
        for (_, body) in phys.iter() {
            assert!(body.vel.is_finite() && body.pos.is_finite());
            assert!(
                body.pos.y < tower_top_m + 1.0,
                "detached body should be part of the tower, not the whole extent"
            );
        }

        // "Blast rampage": a few more blasts well up in open air near the
        // remaining structure (not the ground the first blast already
        // exposed — repeatedly blasting the exact same low spot would just
        // carve a hole straight through the floor, which is a floor design
        // problem, not a solver one), watching for divergence.
        for i in 0..5 {
            let y = floor_top_m + 3.0 + i as f32 * 0.5;
            let rampage_eye = Vec3::new(px - 2.0, y, cz);
            tools.blast(&mut world, &mut phys, &reg, rampage_eye, look, 2 + i);
            for _ in 0..30 {
                phys.step(&world, PHYSICS_DT);
                for (_, body) in phys.iter() {
                    assert!(
                        body.vel.is_finite() && body.pos.is_finite() && body.vel.length() < 200.0,
                        "solver diverged after blast {i}"
                    );
                }
            }
        }

        // Let everything finish settling.
        for _ in 0..600 {
            phys.step(&world, PHYSICS_DT);
        }
        let awake = phys.awake_count();
        assert!(
            awake * 4 <= phys.body_count().max(1),
            "most debris should be asleep by now: {awake}/{} awake",
            phys.body_count()
        );
        for (_, body) in phys.iter() {
            assert!(body.pos.y > -1.0, "nothing should fall through the floor");
        }
    }
}
