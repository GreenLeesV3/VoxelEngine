# Progressive Damage / Cracking — Design Document

**Date:** 2026-07-11
**Status:** Approved
**Builds on:** The existing fracture system (`body_destruction.rs`, `destruction.rs`,
`solver.rs`, `main.rs::apply_impact_fracture`). This document adds a per-voxel damage
field to debris bodies so sub-threshold impacts weaken material progressively before
it fractures.

---

## 1. Decisions of Record

| Question | Decision |
|---|---|
| Damage storage | **Per-voxel `damage: Vec<f32>` inside `VoxelGrid`** — parallel to `voxels`, same length. Stays in sync through clone/crop/split automatically because those operations already manipulate `voxels` and `dims` together. |
| Damage scope | **Debris bodies only** (not world voxels). World damage would require modifying chunk storage, which is out of scope. Terrain hits use the existing binary fracture. |
| Damage accumulation | Sub-threshold impacts (above 30% of fracture threshold) add damage to the contacted voxel + face-neighbors. Damage ∝ (impact_speed / fracture_threshold)². A hit at 99% of threshold adds ~0.29; a hit at 50% adds ~0.075. |
| Damage trigger | When a voxel's damage reaches 1.0, it crumbles (becomes AIR). If enough voxels crumble to disconnect the body, `split_components` runs — the body fractures from accumulated damage. |
| Damage decay | 0.05/s — 20 seconds to fully heal. Prevents permanent weakening and keeps the damage field from being a persistent memory burden. |
| Visual feedback | Body mesh builder bakes damage into vertex color: `color *= (1.0 - damage * 0.6)`. A voxel at 0.5 damage is 30% darker; at 0.9 it's 54% darker. Re-mesh only when damage changes. |
| Threshold gates | `DAMAGE_THRESHOLD_FACTOR = 0.3` — impacts below 30% of fracture threshold do nothing. `DAMAGE_RATE = 0.3` — damage per hit at exactly the fracture threshold. |

## 2. VoxelGrid changes (`body.rs`)

### 2.1 Struct

```rust
pub struct VoxelGrid {
    pub dims: IVec3,
    pub voxels: Vec<Voxel>,
    /// Per-voxel damage, 0.0 (pristine) to 1.0 (crumbled). Parallel to
    /// `voxels`, same length. Only meaningful on debris bodies — world
    /// chunks don't use it (initialized to all-zeros, ignored).
    pub damage: Vec<f32>,
}
```

### 2.2 Constructor

`VoxelGrid::new` initializes `damage` to `vec![0.0; voxels.len()]`.

Add a `new_with_damage` constructor for split_components to pass damage through.

### 2.3 Damage accessors

```rust
pub fn damage_at(&self, p: IVec3) -> f32 { ... }
pub fn add_damage(&mut self, p: IVec3, amount: f32) { ... }
pub fn tick_damage_decay(&mut self, dt: f32, decay_rate: f32) { ... }
```

### 2.4 Sync points

Every place that constructs a new VoxelGrid must initialize damage:
- `VoxelGrid::new` — all-zeros (existing callers: chip templates, test grids)
- `split_components` — crop damage alongside voxels (the one manual sync point)
- Carve functions — damage entries for removed voxels are dropped (the `voxels` vec is rebuilt without them; damage vec must match)

The carve functions (`carve_body_sphere`, `carve_body_voxel`, etc.) set `voxels[idx] = AIR` for removed voxels. The damage at those positions becomes irrelevant (air has no damage). No change needed — the damage vec stays the same length, just has stale values at air positions, which are never read.

## 3. split_components sync (`body_destruction.rs`)

The crop at line 219-224 builds a new `voxels` Vec for each component. Add damage:

```rust
let mut voxels = vec![AIR; (dims.x * dims.y * dims.z) as usize];
let mut damage = vec![0.0; (dims.x * dims.y * dims.z) as usize];
for &v in &comp {
    let mat = grid.get(v);
    let l = v - min;
    let idx = grid_index(dims, l);
    voxels[idx] = mat;
    damage[idx] = grid.damage_at(v);
}
out.push((VoxelGrid::new_with_damage(dims, voxels, damage), min));
```

## 4. Impact damage accumulation (`main.rs::apply_impact_fracture`)

Current flow: for each ImpactEvent, check if impact_speed exceeds fracture threshold → carve.

New flow:
1. Compute `fracture_threshold = fracture_sensitivity * strength`.
2. If `impact_speed >= fracture_threshold` → **existing fracture path** (carve voxels). No change.
3. If `impact_speed >= fracture_threshold * DAMAGE_THRESHOLD_FACTOR` → **new damage path**:
   - `damage_amount = ((impact_speed / fracture_threshold).squared() * DAMAGE_RATE)`
   - Add `damage_amount` to the contacted voxel and its 6 face-neighbors (in the body's local grid).
   - If any voxel's damage reaches 1.0 → crumble it (set to AIR), then check if the body needs splitting (run `split_components` if any voxels crumbled).
4. If `impact_speed < fracture_threshold * DAMAGE_THRESHOLD_FACTOR` → nothing (too gentle).

The damage path requires access to the body's grid to write damage. Currently `apply_impact_fracture` only reads the body — it'll need to mutate the grid in-place for damage, or despawn+respawn with modified grid (same as fracture, but without carving).

**Simplest approach**: despawn the body, add damage to the cloned grid, crumble any fully-damaged voxels, then `finish_carve` (split + respawn). This reuses the existing despawn/respawn pipeline. If no voxels crumbled, just respawn the body with the updated damage (no split needed).


### 4.1 Mesh dirty-tracking

Add `damage_dirty: bool` to `Body`. Set `true` whenever any damage value
changes (impact adds damage, or a voxel crumbles). Cleared after the body
is re-meshed. Decay does NOT set the flag unless a voxel crumbles from
decay (rare — 0.05/s means ~20s to heal, and crumble from decay needs
damage already very close to 1.0). This avoids re-meshing every frame
for the decay case.

### 4.2 Damage decay vs sleep

Decay ticks **only while awake**. A sleeping body's damage freezes — it
isn't being hit, so healing while asleep is unnecessary. When woken (by
an impact or world edit), decay resumes. This keeps decay inside the
solver step (no app-loop hook needed) and avoids scanning sleeping bodies.
## 5. Damage decay (`solver.rs`)

In `PhysicsWorld::step`, after solving, tick damage decay on every awake (non-sleeping) body:

```rust
for (_, body) in self.bodies.iter_mut() {
    if !body.sleep.asleep {
        body.grid.tick_damage_decay(dt, DAMAGE_DECAY_PER_S);
    }
}
```

Sleeping bodies don't decay (no processing cost). Awake bodies decay slowly. This means a body that's being repeatedly hit stays damaged; once it settles and sleeps, damage freezes (it'll resume decaying when woken).

Actually — better: decay regardless of sleep state, but only tick it if any damage > 0. This avoids scanning all bodies every frame. Add a `has_damage` flag to Body or check `damage.iter().any(|&d| d > 0.0)` (cheap for small grids).

## 6. Visual feedback (`body_mesh.rs`)

The body mesh builder bakes per-vertex color from the material palette. Add damage darkening:

When building vertices for a voxel at grid position `p`:
```rust
let damage = grid.damage_at(p);
let color = palette[material] * (1.0 - damage * 0.6);
```

This requires passing the grid's damage to the mesh builder. Currently `body_mesh.rs` receives `voxels: Vec<Voxel>` and `dims: IVec3` — it'll need the damage vec too.

**Re-meshing**: Bodies are re-meshed when they're spawned or replaced. For damage to be visible, the body needs re-meshing when damage changes. Options:
- Re-mesh every time damage is added (expensive if many impacts per frame)
- Throttle: only re-mesh if max damage changed by > 0.1 since last mesh
- Simplest: re-mesh whenever `apply_impact_fracture` modifies a body's damage (one re-mesh per impact event, not per frame)

## 7. Constants

```rust
/// Impacts below this fraction of the fracture threshold do nothing.
const DAMAGE_THRESHOLD_FACTOR: f32 = 0.3;
/// Damage gained per hit at exactly the fracture threshold (squared scaling).
const DAMAGE_RATE: f32 = 0.3;
/// Damage decay per second (20s to fully heal).
const DAMAGE_DECAY_PER_S: f32 = 0.05;
/// Damage at which a voxel crumbles (becomes air).
const DAMAGE_CRUMBLE: f32 = 1.0;
/// Visual darkening: color *= (1.0 - damage * this).
const DAMAGE_DARKEN: f32 = 0.6;
```

## 8. Testing plan

- **Damage accumulation**: sub-threshold impact adds damage to contacted voxel + neighbors; damage ∝ (speed/threshold)²
- **Crumble**: voxel at damage 1.0 becomes air; body splits if disconnected
- **Decay**: damage decreases over time; body returns to pristine after 20s without hits
- **Below damage threshold**: impacts below 30% of fracture threshold add zero damage
- **Split sync**: fragments from a damage-triggered split carry their own damage values
- **Visual**: mesh builder darkens voxels by damage level
- **Existing tests**: all fracture tests pass unmodified (above-threshold path unchanged)

## 9. Explicitly out of scope

- World voxel damage (terrain damage would need chunk storage changes)
- Crack line rendering (procedural crack patterns — the darkening is sufficient for v1)
- Stress-based fragmentation (splitting along stress lines, not just connectivity)
- Cumulative damage from tool hits on terrain (only debris body impacts)
