# Rope + Joints Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Add distance-constraint joints between debris bodies and a rope material with 5 spawnable rope segments connected by joints.

**Architecture:** A `Joint` struct stores a distance constraint between two body slots with body-local anchor points, rest length, and a warm-start accumulator. Joints are solved inside the existing `SOLVER_ITERS` loop (interleaved with contacts), with position correction in the split-impulse pass. Joint body pairs feed into the island union-find for sleep/wake coordination. Rope segments are standard debris bodies (2×2×5 voxel grids of `rope` material, 20 voxels each) connected end-to-end by joints.

**Tech Stack:** Rust, glam, wgpu

**Design doc:** `docs/plans/2026-07-11-rope-joints-design.md`

---

## Task 1: Add Joint struct and storage to PhysicsWorld

**Files:**
- Modify: `crates/vox-physics/src/solver.rs` (add Joint struct, joints field, add/remove methods)
- Modify: `crates/vox-physics/src/lib.rs` (re-export Joint)

**Step 1: Add Joint struct**

Add near the top of `solver.rs` (after the `ImpactEvent` struct, around line 61):

```rust
/// A distance constraint between two bodies. Maintains a fixed rest length
/// between two anchor points. Used for rope/chain segments.
#[derive(Clone, Debug)]
pub struct Joint {
    /// Slot index of body A.
    pub body_a: usize,
    /// Slot index of body B.
    pub body_b: usize,
    /// Anchor on body A, relative to COM, body-local frame (meters).
    pub anchor_a: Vec3,
    /// Anchor on body B, relative to COM, body-local frame.
    pub anchor_b: Vec3,
    /// Rest length between anchors (meters).
    pub rest_length: f32,
    /// Accumulated Lagrange multiplier (warm start).
    pub acc_lambda: f32,
    /// Compliance (inverse stiffness). 0 = rigid.
    pub compliance: f32,
}
```

**Step 2: Add joints field to PhysicsWorld**

Add `joints: Vec<Joint>` to the `PhysicsWorld` struct (around line 141-155). Initialize to `Vec::new()` in `PhysicsWorld::new`.

**Step 3: Add joint management methods**

```rust
/// Add a distance joint between two bodies. Returns the joint index.
pub fn add_joint(
    &mut self,
    a: BodyId,
    b: BodyId,
    anchor_a: Vec3,
    anchor_b: Vec3,
    rest_length: f32,
) -> usize {
    let joint = Joint {
        body_a: a.slot as usize,
        body_b: b.slot as usize,
        anchor_a,
        anchor_b,
        rest_length,
        acc_lambda: 0.0,
        compliance: 0.0,
    };
    self.joints.push(joint);
    self.joints.len() - 1
}

/// Remove all joints referencing a given body slot (called on despawn).
fn remove_joints_for_slot(&mut self, slot: usize) {
    self.joints.retain(|j| j.body_a != slot && j.body_b != slot);
}

/// Read access to joints (for debugging/rendering).
pub fn joints(&self) -> &[Joint] {
    &self.joints
}
```

**Step 4: Call remove_joints_for_slot in despawn**

In `despawn()` (line 240-247), after setting `self.slots[slot] = None`:
```rust
self.remove_joints_for_slot(slot);
```

**Step 5: Re-export Joint from lib.rs**

In `crates/vox-physics/src/lib.rs`, add `Joint` to the re-exports from solver.

**Step 6: Verify compilation**

Run: `cargo check -p vox-physics`
Expected: PASS

**Step 7: Run tests**

Run: `cargo test -p vox-physics -- --nocapture`
Expected: ALL PASS

**Step 8: Commit**

```bash
git add crates/vox-physics/src/solver.rs crates/vox-physics/src/lib.rs
git commit -m "feat(physics): Joint struct and storage on PhysicsWorld"
```

---

## Task 2: Joint velocity solve in substep

**Files:**
- Modify: `crates/vox-physics/src/solver.rs` (substep method — add joint solve)

**Step 1: Add joint warm start**

In `substep()`, after the contact warm start block (line 576-585), add joint warm start:

```rust
// Warm start joints.
for j in &mut self.joints {
    if j.acc_lambda == 0.0 {
        continue;
    }
    let (ba, bb) = match (self.slots[j.body_a].as_ref(), self.slots[j.body_b].as_ref()) {
        (Some(a), Some(b)) => (a, b),
        _ => continue,
    };
    if ba.sleep.asleep && bb.sleep.asleep {
        continue;
    }
    let ra = ba.rot * j.anchor_a;
    let rb = bb.rot * j.anchor_b;
    let pa = ba.pos + ra;
    let pb = bb.pos + rb;
    let d = pb - pa;
    let dist = d.length();
    if dist < 1e-6 {
        continue;
    }
    let n = d / dist;
    let p = n * j.acc_lambda;
    // Apply using two_mut (same pattern as apply_contact_impulse).
    let (ba, bb) = two_mut(&mut self.slots, j.body_a, j.body_b);
    if !ba.sleep.asleep {
        ba.vel += p * ba.inv_mass;
        ba.omega += ba.inv_iw * ra.cross(p);
    }
    if !bb.sleep.asleep {
        bb.vel -= p * bb.inv_mass;
        bb.omega -= bb.inv_iw * rb.cross(p);
    }
}
```

**Step 2: Add joint solve inside SOLVER_ITERS loop**

In the velocity iterations loop (line 602-623), after the `for c in &mut contacts` block (line 622, before the closing `}` of the `for _ in 0..SOLVER_ITERS` loop), add:

```rust
// Joint distance constraints (interleaved with contacts for convergence).
for j in &mut self.joints {
    let (ba, bb) = match (self.slots[j.body_a].as_ref(), self.slots[j.body_b].as_ref()) {
        (Some(a), Some(b)) => (a, b),
        _ => continue,
    };
    if ba.sleep.asleep && bb.sleep.asleep {
        continue;
    }
    let asleep_a = ba.sleep.asleep;
    let asleep_b = bb.sleep.asleep;
    let ra = ba.rot * j.anchor_a;
    let rb = bb.rot * j.anchor_b;
    let pa = ba.pos + ra;
    let pb = bb.pos + rb;
    let d = pb - pa;
    let dist = d.length();
    if dist < 1e-6 {
        continue;
    }
    let n = d / dist;
    let c = dist - j.rest_length;
    // Effective mass: 1/ma + 1/mb + (ra×n)·Ia⁻¹·(ra×n) + (rb×n)·Ib⁻¹·(rb×n)
    let ima = if asleep_a { 0.0 } else { ba.inv_mass };
    let imb = if asleep_b { 0.0 } else { bb.inv_mass };
    let iwa = if asleep_a { Mat3::ZERO } else { ba.inv_iw };
    let iwb = if asleep_b { Mat3::ZERO } else { bb.inv_iw };
    let ra_cross_n = ra.cross(n);
    let rb_cross_n = rb.cross(n);
    let keff = ima + imb
        + iwa.mul_vec3(ra_cross_n).dot(ra_cross_n)
        + iwb.mul_vec3(rb_cross_n).dot(rb_cross_n);
    if keff <= 0.0 {
        continue;
    }
    let lambda = -c / (keff + j.compliance);
    j.acc_lambda += lambda;
    let p = n * lambda;
    let (ba, bb) = two_mut(&mut self.slots, j.body_a, j.body_b);
    if !ba.sleep.asleep {
        ba.vel += p * ba.inv_mass;
        ba.omega += ba.inv_iw * ra.cross(p);
    }
    if !bb.sleep.asleep {
        bb.vel -= p * bb.inv_mass;
        bb.omega -= bb.inv_iw * rb.cross(p);
    }
}
```

IMPORTANT: The `ba`/`bb` from the read-only borrow (for computing keff) must be dropped before calling `two_mut`. The code above uses two separate match/borrow blocks — the first reads, the second writes. Rust's borrow checker will require the read borrow to end before `two_mut`. The code is structured correctly: the read borrow is in the `let (ba, bb) = match ...` block, and the `two_mut` call is after all read-only uses.

Actually, there's a borrow issue: `self.slots[j.body_a].as_ref()` borrows `self.slots` immutably, and then `two_mut(&mut self.slots, ...)` borrows it mutably. The immutable borrow must end first. In the code above, `ba` and `bb` are used to compute `ra`, `rb`, `pa`, `pb`, `keff` — all before `two_mut`. But `ra`, `rb` are `Vec3` (Copy), so the borrow ends when they're computed. The issue is `ba.inv_mass`, `ba.inv_iw` — these are `f32` and `Mat3` (Copy), so the borrow also ends. As long as no reference to `ba`/`bb` is held when `two_mut` is called, this compiles. The code is correct.

Wait — `iwa` and `iwb` are `Mat3` which is Copy, so that's fine. But the `match` creates `ba` and `bb` as `&Body` references. These references must be dropped before `two_mut`. In Rust, the references are dropped at the end of their last use. Since all uses are Copy types (f32, Mat3, Vec3, Quat), the last use of `ba` is `bb.inv_iw` (for `iwb`), and after that, the references are dead. The `two_mut` call should compile.

Actually, the NLL (non-lexical lifetimes) in Rust should handle this correctly. The references `ba` and `bb` are last used at the `keff` computation, and `two_mut` is called after that. NLL will end the borrows at the last use point.

**Step 3: Reset acc_lambda before velocity iterations**

Before the `for _ in 0..SOLVER_ITERS` loop (after warm start), reset joint accumulators:
```rust
for j in &mut self.joints {
    // Warm start already applied; reset for this substep's accumulation.
    // Actually, the standard pattern is: warm start applies the old lambda,
    // then we reset to 0 and re-accumulate during iterations. But for
    // simplicity, we can keep accumulating (the lambda from warm start
    // is the starting point, and iterations add corrections). Let's
    // NOT reset — just accumulate on top of the warm-started value.
}
```

Actually, the standard warm-start pattern for distance constraints is:
1. Warm start: apply `acc_lambda` from previous substep
2. Reset `acc_lambda = 0`
3. Velocity iterations: accumulate `lambda` into `acc_lambda`
4. Persist `acc_lambda` for next substep

But since we don't have a separate persist step for joints (they're persistent on the struct), `acc_lambda` is already persisted. So the pattern is:
1. Warm start: apply old `acc_lambda`
2. Reset `acc_lambda = 0`
3. Velocity iterations: `acc_lambda += lambda` each iteration
4. `acc_lambda` is now the new accumulated value for next substep's warm start

Add the reset after the warm start block:
```rust
for j in &mut self.joints {
    j.acc_lambda = 0.0;
}
```

**Step 4: Add joint position correction**

In the split-impulse position correction loop (line 712-735), after the contact correction (`for c in &contacts` block), add joint distance correction:

```rust
// Joint distance drift correction.
for j in &self.joints {
    let (ba, bb) = match (self.slots[j.body_a].as_ref(), self.slots[j.body_b].as_ref()) {
        (Some(a), Some(b)) => (a, b),
        _ => continue,
    };
    if ba.sleep.asleep && bb.sleep.asleep {
        continue;
    }
    let ra = ba.rot * j.anchor_a;
    let rb = bb.rot * j.anchor_b;
    let pa = ba.pos + ra;
    let pb = bb.pos + rb;
    let d = pb - pa;
    let dist = d.length();
    if dist < 1e-6 {
        continue;
    }
    let n = d / dist;
    let c = dist - j.rest_length;
    let asleep_a = ba.sleep.asleep;
    let asleep_b = bb.sleep.asleep;
    let ra = ba.rot * j.anchor_a;
    let rb = bb.rot * j.anchor_b;
    let ima = if asleep_a { 0.0 } else { ba.inv_mass };
    let imb = if asleep_b { 0.0 } else { bb.inv_mass };
    let iwa = if asleep_a { Mat3::ZERO } else { ba.inv_iw };
    let iwb = if asleep_b { Mat3::ZERO } else { bb.inv_iw };
    let ra_cross_n = ra.cross(n);
    let rb_cross_n = rb.cross(n);
    let w = ima + imb
        + iwa.mul_vec3(ra_cross_n).dot(ra_cross_n)
        + iwb.mul_vec3(rb_cross_n).dot(rb_cross_n);
    if w <= 0.0 {
        continue;
    }
    let corr = c * 0.5; // gentle correction
    self.pos_corr[j.body_a] += n * (corr * ima / w);
    self.pos_corr[j.body_b] -= n * (corr * imb / w);
}
```

**Step 5: Verify compilation**

Run: `cargo check -p vox-physics`
Expected: PASS (may need to fix borrow checker issues — see notes above)

**Step 6: Run tests**

Run: `cargo test -p vox-physics -- --nocapture`
Expected: ALL PASS

**Step 7: Commit**

```bash
git add crates/vox-physics/src/solver.rs
git commit -m "feat(physics): joint velocity solve + position correction in substep"
```

---

## Task 3: Joint island union-find for sleep coordination

**Files:**
- Modify: `crates/vox-physics/src/solver.rs` (islands method — add joint edges)

**Step 1: Add joint edges to islands()**

In `islands()` (line 442-464), after the broadphase pair union loop, add:

```rust
// Joint-connected bodies are in the same island.
for j in &self.joints {
    if self.slots[j.body_a].is_some() && self.slots[j.body_b].is_some() {
        union(&mut parent, j.body_a, j.body_b);
    }
}
```

Read the existing `islands()` to find the `union` function or inline the union logic.

**Step 2: Verify**

Run: `cargo test -p vox-physics -- --nocapture`
Expected: ALL PASS

**Step 3: Commit**

```bash
git add crates/vox-physics/src/solver.rs
git commit -m "feat(physics): joint pairs in island union-find for sleep coordination"
```

---

## Task 4: Add rope material

**Files:**
- Modify: `assets/materials/core.toml` (append rope material)
- Modify: `crates/vox-core/src/material.rs` (update shipped material count test)

**Step 1: Add rope material**

Append to `assets/materials/core.toml`:

```toml
[[material]]
name = "rope"
color = [0.65, 0.50, 0.30]
jitter = 0.06
density = 400.0
strength = 2.0
solid = true
flammable = true
```

**Step 2: Update material count test**

In `crates/vox-core/src/material.rs`, find the test that checks `reg.len() == 16` and update to `17`.

**Step 3: Verify**

Run: `cargo test -p vox-core material -- --nocapture`
Expected: PASS

**Step 4: Commit**

```bash
git add assets/materials/core.toml crates/vox-core/src/material.rs
git commit -m "feat(assets): add rope material"
```

---

## Task 5: Rope spawning in main.rs

**Files:**
- Modify: `crates/vox-app/src/main.rs` (add rope spawn function + key binding)

**Step 1: Add rope spawn function**

Add a method to `VoxApp`:

```rust
/// Spawn a rope: 5 segments of 2×2×5 rope voxels (20 voxels each),
/// connected by joints, hanging from a point above the player.
fn spawn_rope(&mut self) {
    let rope_voxel = self.registry.id_by_name("rope").map(|m| Voxel(m.0));
    let Some(rope_voxel) = rope_voxel else {
        tracing::warn!("rope material not found, cannot spawn rope");
        return;
    };

    let voxel_size = self.world.cfg.voxel_size_m;
    let seg_dims = IVec3::new(2, 5, 2);
    let seg_voxels = vec![rope_voxel; (2 * 5 * 2) as usize]; // 20 voxels
    let seg_height_m = 5.0 * voxel_size; // 0.5m at 0.1m scale
    let half_height = seg_height_m * 0.5; // 0.25m

    // Spawn point: 3m above player, slightly forward.
    let base_pos = self.player.pos + Vec3::new(0.0, 3.0, 0.0) + self.camera.forward() * 2.0;

    let mut prev_id: Option<BodyId> = None;

    for i in 0..5 {
        // Stack segments vertically, top segment first.
        let seg_center = base_pos + Vec3::new(0.0, -i as f32 * seg_height_m, 0.0);
        let grid = VoxelGrid::new(seg_dims, seg_voxels.clone());
        let Some(mut body) = Body::from_grid(grid, &self.registry, voxel_size, seg_center) else {
            continue;
        };
        let id = self.phys.spawn(body);
        self.upload_debris_mesh(id);

        if let Some(prev) = prev_id {
            // Connect bottom of previous segment to top of this segment.
            // Anchors are body-local, relative to COM (= geometric center
            // for a uniform grid). For a 2×2×5 grid at voxel_size, the
            // half-height is 2.5 * voxel_size = 0.25m at 0.1m scale.
            let anchor_prev = Vec3::new(0.0, -half_height, 0.0); // bottom of prev
            let anchor_this = Vec3::new(0.0, half_height, 0.0);   // top of this
            self.phys.add_joint(prev, id, anchor_prev, anchor_this, 0.0);
        }

        prev_id = Some(id);
    }

    tracing::info!(?prev_id, "spawned 5-segment rope");
}
```

The anchors are in body-local frame relative to COM. For a uniform 2×2×5 grid,
COM = geometric center. `half_height = 5 * voxel_size / 2`. At 0.1m scale:
`half_height = 0.25m`. `anchor_top = (0, +0.25, 0)`, `anchor_bottom = (0, -0.25, 0)`.

Update the spawn function to use these correct values.

**Step 2: Add key binding**

Find the key handling in main.rs (search for `VirtualKeyCode::B` — the spawn-wood-cube key). Add a rope spawn on a new key (e.g., `VirtualKeyCode::T` for rope/Tie):

```rust
// In the keyboard input handler:
if key == VirtualKeyCode::T {
    self.spawn_rope();
}
```

Read the existing key handling to find the exact location and pattern.

**Step 3: Verify compilation**

Run: `cargo check -p vox-app`
Expected: PASS

**Step 4: Run the app and verify**

Run: `cargo run -p vox-app --release`
- Press T to spawn a rope near the player
- Confirm: 5 segments appear, connected, hanging/swinging
- Confirm: rope falls, collides with ground, swings naturally
- Confirm: cutting through a segment with a tool severs the rope

**Step 5: Commit**

```bash
git add crates/vox-app/src/main.rs
git commit -m "feat(app): spawn 5-segment rope with joints on T key"
```

---

## Task 6: Joint test

**Files:**
- Modify: `crates/vox-physics/src/solver.rs` (test module)

**Step 1: Write joint test**

```rust
#[test]
fn joint_holds_two_bodies_at_rest_length() {
    let mut world = test_world();
    let reg = registry();
    let mut phys = PhysicsWorld::new();

    // Two 2x2x2 stone bodies, 1m apart, joined at rest length 1.0.
    let grid = VoxelGrid::new(IVec3::new(2, 2, 2), vec![Voxel(1); 8]);
    let body_a = Body::from_grid(grid.clone(), &reg, 0.5, Vec3::new(10.0, 10.0, 10.0)).unwrap();
    let body_b = Body::from_grid(grid, &reg, 0.5, Vec3::new(11.0, 10.0, 10.0)).unwrap();
    let id_a = phys.spawn(body_a);
    let id_b = phys.spawn(body_b);

    // Joint at COM of each body (anchor = 0,0,0 local), rest length 1.0.
    phys.add_joint(id_a, id_b, Vec3::ZERO, Vec3::ZERO, 1.0);

    // Run physics: gravity pulls both down, but the joint should keep
    // them ~1m apart. After settling, distance should be close to 1.0.
    for _ in 0..300 {
        phys.step(&world, PHYSICS_DT);
    }

    let a = phys.get(id_a).unwrap();
    let b = phys.get(id_b).unwrap();
    let dist = (a.pos - b.pos).length();
    assert!(
        (dist - 1.0).abs() < 0.15,
        "joint should maintain rest length ~1.0m, got {dist}"
    );
}
```

Read the existing test module to find `test_world()`, `registry()`, `PHYSICS_DT`, and `Voxel` constants.

**Step 2: Run test**

Run: `cargo test -p vox-physics joint -- --nocapture`
Expected: PASS

**Step 3: Commit**

```bash
git add crates/vox-physics/src/solver.rs
git commit -m "test(physics): joint maintains rest length between two bodies"
```

---

## Task 7: Update README and verify

**Files:**
- Modify: `README.md`

**Step 1: Add rope + joints to README**

In the Simulation section, add:
```
- **Joints + rope**: Distance-constraint joints connect debris bodies,
  maintaining a rest length between anchor points. Solved interleaved with
  contacts in the sequential-impulse solver. Rope segments (2×2×5 voxel
  bodies of rope material) connect end-to-end via joints. Press T to spawn
  a 5-segment rope near the player. Rope can be cut, burned, and destroyed
  — severing a segment breaks the joint chain.
```

In the Controls table, add:
```
| `T` | Spawn a 5-segment rope near the player |
```

**Step 2: Run full test suite**

Run: `cargo test --workspace --lib -- --nocapture`
Expected: ALL PASS

**Step 3: Commit**

```bash
git add README.md
git commit -m "docs: document rope + joints system"
```

---

## Summary

| # | Task | Key change |
|---|---|---|
| 1 | Joint struct + storage | `Joint` struct, `joints: Vec<Joint>` on PhysicsWorld, add/remove methods, despawn cleanup |
| 2 | Joint velocity solve | Warm start + solve inside SOLVER_ITERS + position correction |
| 3 | Island union-find | Joint pairs in islands() for sleep coordination |
| 4 | Rope material | `rope` in core.toml (density 400, strength 2.0, flammable) |
| 5 | Rope spawning | 5 segments on T key, connected by joints |
| 6 | Joint test | Distance constraint maintains rest length |
| 7 | README + verify | Documentation, full test suite |
