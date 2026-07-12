# Progressive Damage / Cracking Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Add per-voxel damage to debris bodies so sub-threshold impacts progressively weaken material (visible darkening) before it crumbles and fractures.

**Architecture:** VoxelGrid gains a parallel `damage: Vec<f32>` field (0.0 pristine → 1.0 crumbled). Sub-threshold impacts accumulate damage on contacted voxels. At damage 1.0, voxels crumble to air and trigger connectivity-based splitting. Damage decays at 0.05/s while awake. Visual feedback via mesh color darkening. A `damage_dirty` flag on Body avoids unnecessary re-meshing.

**Tech Stack:** Rust, glam, wgpu/WGSL

**Design doc:** `docs/plans/2026-07-11-progressive-damage-design.md`

---

## Task 1: Add damage field to VoxelGrid

**Files:**
- Modify: `crates/vox-physics/src/body.rs:8-57` (VoxelGrid struct + impl)

**Step 1: Add damage field and update constructors**

Add `damage: Vec<f32>` to VoxelGrid struct:
```rust
pub struct VoxelGrid {
    pub dims: IVec3,
    pub voxels: Vec<Voxel>,
    pub damage: Vec<f32>,
}
```

Update `VoxelGrid::new` to initialize damage:
```rust
pub fn new(dims: IVec3, voxels: Vec<Voxel>) -> Self {
    debug_assert_eq!(
        voxels.len() as i64,
        dims.x as i64 * dims.y as i64 * dims.z as i64
    );
    let damage = vec![0.0; voxels.len()];
    Self { dims, voxels, damage }
}
```

Add `new_with_damage` for split_components:
```rust
pub fn new_with_damage(dims: IVec3, voxels: Vec<Voxel>, damage: Vec<f32>) -> Self {
    debug_assert_eq!(voxels.len(), damage.len());
    Self { dims, voxels, damage }
}
```

Add damage accessors:
```rust
#[inline]
pub fn damage_at(&self, p: IVec3) -> f32 {
    if p.cmpge(IVec3::ZERO).all() && p.cmplt(self.dims).all() {
        self.damage[self.index(p)]
    } else {
        0.0
    }
}

#[inline]
pub fn add_damage(&mut self, p: IVec3, amount: f32) -> bool {
    if p.cmpge(IVec3::ZERO).all() && p.cmplt(self.dims).all() {
        let idx = self.index(p);
        if self.voxels[idx] != AIR {
            self.damage[idx] = (self.damage[idx] + amount).min(1.0);
            return true;
        }
    }
    false
}

pub fn tick_damage_decay(&mut self, dt: f32, decay_rate: f32) -> bool {
    let mut changed = false;
    for d in &mut self.damage {
        if *d > 0.0 {
            *d = (*d - decay_rate * dt).max(0.0);
            changed = true;
        }
    }
    changed
}

pub fn has_damage(&self) -> bool {
    self.damage.iter().any(|&d| d > 0.0)
}
```

**Step 2: Fix all compilation errors**

Every place that constructs VoxelGrid with struct literal (not `::new()`) needs the damage field. Search for `VoxelGrid {` and add `damage: vec![0.0; voxels.len()]` or use `VoxelGrid::new()`. The `new()` constructor handles this — most callers use `::new()` already.

**Step 3: Verify compilation**

Run: `cargo check -p vox-physics`
Expected: PASS (all existing callers use `VoxelGrid::new()`)

**Step 4: Run physics tests**

Run: `cargo test -p vox-physics -- --nocapture`
Expected: ALL PASS

**Step 5: Commit**

```bash
git add crates/vox-physics/src/body.rs
git commit -m "feat(physics): add per-voxel damage field to VoxelGrid"
```

---

## Task 2: Sync damage through split_components

**Files:**
- Modify: `crates/vox-physics/src/body_destruction.rs:182-230` (split_components)

**Step 1: Update split_components to carry damage**

In the crop section (lines 218-225), add damage copying:

```rust
let dims = max - min + IVec3::ONE;
let total = (dims.x * dims.y * dims.z) as usize;
let mut voxels = vec![AIR; total];
let mut damage = vec![0.0; total];
for &v in &comp {
    let mat = grid.get(v);
    let dmg = grid.damage_at(v);
    let l = v - min;
    let idx = grid_index(dims, l);
    voxels[idx] = mat;
    damage[idx] = dmg;
}
out.push((VoxelGrid::new_with_damage(dims, voxels, damage), min));
```

**Step 2: Verify compilation and tests**

Run: `cargo test -p vox-physics -- --nocapture`
Expected: ALL PASS (split still works, damage carried through)

**Step 3: Commit**

```bash
git add crates/vox-physics/src/body_destruction.rs
git commit -m "feat(physics): carry damage through split_components"
```

---

## Task 3: Add damage_dirty flag to Body and decay in solver

**Files:**
- Modify: `crates/vox-physics/src/body.rs:262-303` (Body struct — add field)
- Modify: `crates/vox-physics/src/body.rs:307-343` (Body::from_grid — init field)
- Modify: `crates/vox-physics/src/solver.rs` (tick decay in step)
- Modify: `crates/vox-core/src/consts.rs` (add DAMAGE_DECAY_PER_S constant)

**Step 1: Add damage_dirty to Body**

Add to Body struct (after `lifetime_s`):
```rust
/// True when damage values changed since last mesh. Cleared after re-mesh.
pub damage_dirty: bool,
```

In `Body::from_grid`, add `damage_dirty: false` to the struct initializer.

**Step 2: Add decay constant**

In `crates/vox-core/src/consts.rs`, add:
```rust
/// Damage decay per second for awake debris bodies (20s to fully heal).
pub const DAMAGE_DECAY_PER_S: f32 = 0.05;
```

**Step 3: Tick decay in solver**

In `PhysicsWorld::step`, after the solver iterations but before returning, add decay ticking for awake bodies that have damage:

```rust
// Tick damage decay on awake bodies with damage.
let decay = vox_core::consts::DAMAGE_DECAY_PER_S;
for (_, body) in self.bodies.iter_mut() {
    if !body.sleep.asleep && body.grid.has_damage() {
        body.grid.tick_damage_decay(dt, decay);
    }
}
```

Find the right spot in `step` — after all substeps are done, before returning ImpactEvents. Read the step method to find where substep loop ends.

**Step 4: Verify compilation and tests**

Run: `cargo test -p vox-physics -- --nocapture`
Expected: ALL PASS

**Step 5: Commit**

```bash
git add crates/vox-physics/src/body.rs crates/vox-physics/src/solver.rs crates/vox-core/src/consts.rs
git commit -m "feat(physics): damage_dirty flag + damage decay in solver"
```

---

## Task 4: Add damage constants and sub-threshold damage logic in apply_impact_fracture

**Files:**
- Modify: `crates/vox-app/src/main.rs:832-898` (apply_impact_fracture)
- Modify: `crates/vox-app/src/main.rs` (add constants near fracture constants)

**Step 1: Add damage constants**

Near the existing fracture constants (search for `FRACTURE_RADIUS_VOX` or `MIN_FRACTURE_BODY_VOXELS`):

```rust
/// Impacts below this fraction of the fracture threshold do nothing.
const DAMAGE_THRESHOLD_FACTOR: f32 = 0.3;
/// Damage gained per hit at exactly the fracture threshold.
const DAMAGE_RATE: f32 = 0.3;
/// Damage at which a voxel crumbles (becomes air).
const DAMAGE_CRUMBLE: f32 = 1.0;
```

**Step 2: Add the damage path to apply_impact_fracture**

In `apply_impact_fracture`, after the existing fracture threshold check (the `fracture_radius_vox(...)` call that returns `None` for sub-threshold), add the damage path:

```rust
// --- Sub-threshold damage path ---
// The impact didn't exceed the fracture threshold, but it may still
// weaken the material. Compute how close it was as a fraction.
let fracture_threshold = self.tunables.fracture_sensitivity * def.strength;
if impact_speed >= fracture_threshold * DAMAGE_THRESHOLD_FACTOR {
    let ratio = impact_speed / fracture_threshold;
    let damage_amount = ratio * ratio * DAMAGE_RATE;
    
    // Despawn the body, add damage to the cloned grid, crumble any
    // fully-damaged voxels, then respawn. Reuses the existing pipeline.
    let voxel_size_m = body.half_voxel * 2.0;
    let mut grid = body.grid.clone();
    let parent = ParentState { /* same as fracture path */ };
    let local = body.rot.inverse() * (event.point_m - body.pos) - body.grid_offset;
    let local_voxel = (local / voxel_size_m).floor().as_ivec3();
    
    // Add damage to contacted voxel + 6 face-neighbors.
    const DIRS6: [IVec3; 6] = [IVec3::X, IVec3::NEG_X, IVec3::Y, IVec3::NEG_Y, IVec3::Z, IVec3::NEG_Z];
    let mut crumbled = false;
    for &dv in [&local_voxel].into_iter().chain(DIRS6.iter().map(|&d| local_voxel + d)) {
        if grid.add_damage(dv, damage_amount) {
            if grid.damage_at(dv) >= DAMAGE_CRUMBLE && grid.solid(dv) {
                grid.set(dv, AIR);
                crumbled = true;
            }
        }
    }
    
    self.phys.despawn(event.body);
    if crumbled {
        let spawned = finish_carve(/* same as fracture path */);
        // Dust + replace_body, same as fracture
    } else {
        // No voxels crumbled — just respawn with updated damage.
        let new_id = self.phys.spawn(Body::from_grid(grid, &self.registry, voxel_size_m, body.pos).unwrap());
        // Copy velocity/rotation from parent
        if let Some(new_body) = self.phys.get_mut(new_id) {
            new_body.vel = parent.vel;
            new_body.omega = parent.omega;
            new_body.rot = parent.rot;
            new_body.damage_dirty = true;
        }
        self.replace_body(event.body, vec![new_id]);
    }
}
```

IMPORTANT: You need to import `ParentState` or construct it the same way the fracture path does. Read the existing fracture code to see how `ParentState` is built (it's a private struct in body_destruction.rs — you may need to make it public or duplicate the fields). Actually, looking at the code, `apply_impact_fracture` doesn't build ParentState directly — it calls `carve_body_sphere_at_impact` which does it internally. For the damage path, you'll need to despawn, modify the grid, and call `finish_carve` directly — but `finish_carve` is also private. 

**Alternative approach**: Instead of despawning/respawning, directly mutate the body's grid in-place. Since we're not carving (no split needed for the no-crumble case), we can just:
```rust
if let Some(body) = self.phys.get_mut(event.body) {
    // Add damage directly to the body's grid.
    for &dv in [&local_voxel].into_iter().chain(DIRS6.iter().map(|&d| local_voxel + d)) {
        body.grid.add_damage(dv, damage_amount);
    }
    body.damage_dirty = true;
}
```

For the crumble case, we DO need to despawn/respawn (the body might split). Make `finish_carve` public, or add a new public function `apply_damage_fracture` in body_destruction.rs that takes the grid + damage + parent state.

**Simplest approach**: Add a new public function in body_destruction.rs:
```rust
pub fn apply_body_damage(
    phys: &mut PhysicsWorld,
    registry: &MaterialRegistry,
    id: BodyId,
    damage_voxels: &[(IVec3, f32)],  // (local voxel, damage amount)
    voxel_size_m: f32,
) -> Vec<BodyId> {
    // 1. Get body, clone grid.
    // 2. Add damage to each voxel. Crumble any at >= 1.0.
    // 3. If any crumbled: despawn, finish_carve (split + respawn). Return new IDs.
    // 4. If none crumbled: mutate body's grid in-place, set damage_dirty. Return empty.
}
```

This keeps the damage logic in body_destruction.rs where the fracture pipeline lives, and the app just calls it.

**Step 3: Verify compilation**

Run: `cargo check -p vox-app`
Expected: PASS

**Step 4: Run tests**

Run: `cargo test -p vox-app -p vox-physics -- --nocapture`
Expected: ALL PASS

**Step 5: Commit**

```bash
git add crates/vox-app/src/main.rs crates/vox-physics/src/body_destruction.rs
git commit -m "feat(fracture): sub-threshold damage accumulation + crumble"
```

---

## Task 5: Visual feedback — damage darkening in body mesh

**Files:**
- Modify: `crates/vox-app/src/body_mesh.rs:49-67` (dispatch — pass damage)
- Modify: `crates/vox-app/src/main.rs:694-715` (upload_debris_mesh — pass damage)
- Modify: `crates/vox-mesh/src/greedy.rs` (mesh_slab — darken by damage)
- Modify: `crates/vox-mesh/src/slab.rs` (VoxelSlab — store damage)

**Step 1: Pass damage through the mesh pipeline**

`body_mesh.rs::dispatch` currently receives `voxels: Vec<Voxel>` and `dims: IVec3`. Add `damage: Vec<f32>` parameter. Pass it to `VoxelSlab::from_grid_with_damage` (new method) or extend `from_grid`.

`upload_debris_mesh` in main.rs currently calls `body_mesh.dispatch(key, dims, voxels, fluids)`. Add `damage: body.grid.damage.clone()`.

**Step 2: Store damage in VoxelSlab**

Add `damage: Vec<f32>` to VoxelSlab (parallel to the voxel data). Add a `from_grid_with_damage` constructor.

**Step 3: Darken vertices by damage in greedy meshing**

In `mesh_slab`, when computing the vertex color for a voxel at position `p`:
```rust
let damage = slab.damage_at(p);
let color = palette[material] * (1.0 - damage * 0.6);
```

This requires the mesh builder to have access to both the palette (already passed as `fluids` + the palette storage binding) and the per-voxel damage. The color is currently baked from the material palette in the shader (not in the mesh). 

Actually, looking at the meshing code more carefully: the mesh stores `material: u16` per vertex, and the shader looks up the color from the palette buffer. Damage darkening would need to either:
- (a) Bake darkened color into the mesh (change vertex format to include color), or
- (b) Pass damage as a per-vertex attribute and darken in the shader.

Option (b) is cleaner — add a `damage: u8` field to VoxelVertex (0-255, where 0 = pristine, 255 = fully damaged). The shader multiplies the palette color by `(1.0 - damage/255.0 * 0.6)`.

**Step 4: Update VoxelVertex format**

Add `damage: u8` to VoxelVertex. Update the vertex layout in voxel_pipeline.rs. Update the shader to read and apply it.

**Step 5: Verify compilation**

Run: `cargo check --workspace`
Expected: PASS

**Step 6: Commit**

```bash
git add crates/vox-mesh/src/slab.rs crates/vox-mesh/src/greedy.rs crates/vox-app/src/body_mesh.rs crates/vox-app/src/main.rs crates/vox-render/src/voxel_pipeline.rs assets/shaders/voxel.wgsl
git commit -m "feat(render): damage darkening on debris body meshes"
```

---

## Task 6: Re-mesh on damage change

**Files:**
- Modify: `crates/vox-app/src/main.rs` (render loop — check damage_dirty, re-mesh)

**Step 1: Re-mesh bodies with damage_dirty**

In the render/update loop, after `apply_impact_fracture`, check for bodies with `damage_dirty` and re-mesh them:

```rust
// Re-mesh bodies whose damage changed this frame.
let dirty_ids: Vec<BodyId> = self.phys.iter()
    .filter(|(_, b)| b.damage_dirty)
    .map(|(id, _)| id)
    .collect();
for id in dirty_ids {
    self.upload_debris_mesh(id);
    if let Some(body) = self.phys.get_mut(id) {
        body.damage_dirty = false;
    }
}
```

Find the right place in the update loop — after fracture processing, before rendering.

**Step 2: Verify compilation**

Run: `cargo check -p vox-app`
Expected: PASS

**Step 3: Commit**

```bash
git add crates/vox-app/src/main.rs
git commit -m "feat(app): re-mesh debris bodies when damage changes"
```

---

## Task 7: Tests for damage system

**Files:**
- Modify: `crates/vox-physics/src/body.rs` (test module — VoxelGrid damage tests)
- Modify: `crates/vox-app/src/main.rs` (fracture_tests module — damage threshold tests)

**Step 1: Write VoxelGrid damage tests**

In body.rs test module:
```rust
#[test]
fn damage_accumulates_and_caps_at_1() {
    let mut grid = VoxelGrid::new(IVec3::new(2, 2, 2), vec![STONE; 8]);
    assert_eq!(grid.damage_at(IVec3::new(0,0,0)), 0.0);
    grid.add_damage(IVec3::new(0,0,0), 0.5);
    assert_eq!(grid.damage_at(IVec3::new(0,0,0)), 0.5);
    grid.add_damage(IVec3::new(0,0,0), 0.7);
    assert_eq!(grid.damage_at(IVec3::new(0,0,0)), 1.0, "damage caps at 1.0");
}

#[test]
fn damage_does_not_accumulate_on_air() {
    let mut grid = VoxelGrid::new(IVec3::new(2, 1, 1), vec![AIR, STONE]);
    assert!(!grid.add_damage(IVec3::new(0,0,0), 0.5), "air rejects damage");
    assert!(grid.add_damage(IVec3::new(1,0,0), 0.5), "solid accepts damage");
}

#[test]
fn damage_decays() {
    let mut grid = VoxelGrid::new(IVec3::new(1, 1, 1), vec![STONE]);
    grid.add_damage(IVec3::ZERO, 0.5);
    grid.tick_damage_decay(1.0, 0.05);
    assert_eq!(grid.damage_at(IVec3::ZERO), 0.45);
    // Decay to zero
    for _ in 0..20 {
        grid.tick_damage_decay(1.0, 0.05);
    }
    assert_eq!(grid.damage_at(IVec3::ZERO), 0.0);
}

#[test]
fn split_components_carries_damage() {
    // Build a 4x1x1 grid, damage the left half, split by removing middle.
    // The left fragment should carry its damage.
    let mut grid = VoxelGrid::new(IVec3::new(4, 1, 1), vec![STONE; 4]);
    grid.add_damage(IVec3::new(0,0,0), 0.7);
    grid.set(IVec3::new(2,0,0), AIR); // disconnect left from right
    let components = split_components(&grid);
    assert_eq!(components.len(), 2);
    // Left component (voxel 0) should have damage 0.7
    let left = components.iter().find(|(_, min)| min.x == 0).unwrap();
    assert_eq!(left.0.damage_at(IVec3::ZERO), 0.7);
}
```

**Step 2: Run tests**

Run: `cargo test -p vox-physics -- --nocapture`
Expected: ALL PASS

**Step 3: Commit**

```bash
git add crates/vox-physics/src/body.rs crates/vox-physics/src/body_destruction.rs
git commit -m "test(physics): damage accumulation, decay, and split sync"
```

---

## Task 8: Full verification

**Step 1: Run all tests**

Run: `cargo test --workspace --lib -- --nocapture`
Expected: ALL PASS

**Step 2: Run the engine and verify visually**

Run: `cargo run -p vox-app --release`
- Spawn a debris body (press B to spawn a wood cube)
- Hit it repeatedly with sub-threshold impacts (drop small debris on it, or push it into walls at moderate speed)
- Confirm: impact site darkens progressively
- Confirm: after enough hits, voxels crumble and the body fractures
- Confirm: a body left alone gradually heals (damage decays)

**Step 3: Commit**

```bash
git add README.md
git commit -m "docs: document progressive damage system"
```

---

## Summary

| # | Task | Key change |
|---|---|---|
| 1 | VoxelGrid damage field | `damage: Vec<f32>` + accessors + decay |
| 2 | split_components sync | Carry damage through crop |
| 3 | Body damage_dirty + decay | Flag on Body, decay tick in solver |
| 4 | Sub-threshold damage logic | `apply_body_damage` in body_destruction, called from main.rs |
| 5 | Visual feedback | Damage darkening via per-vertex attribute |
| 6 | Re-mesh on damage change | Check damage_dirty in render loop |
| 7 | Tests | Damage accumulation, decay, split sync |
| 8 | Verify | Full suite + visual confirmation |
