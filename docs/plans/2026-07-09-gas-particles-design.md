# Rich Visual Smoke Particles — Teardown-Style — Design Document

**Date:** 2026-07-09
**Status:** Implemented
**Builds on:** The existing CPU particle system in `vox-app/src/particles.rs`
and GPU instanced billboard pipeline in `vox-render/src/particles.rs`.

**User request:** "begin adding gasses... smoke should be a proper simulated
concept... taking the Teardown approach with 2D billboards that react to
themselves and each other, the volume of a space, etc."

**Scope pivot:** User initially considered a hybrid density-field + particle
approach, then chose to focus solely on the Teardown-style visual pipeline.
No volumetric simulation, no gameplay density field. This is a visual
rendering upgrade to the existing particle system.

---

## 1. Decisions of Record

| Question | Decision |
|---|---|
| Purpose | Visual-only. No gameplay state reads particles. Nothing collides with them. They don't affect the voxel grid, physics, or fluids. |
| World collision | Particles collide with the voxel world via `world.solid()` lookups. They deflect off walls, stop at ceilings, settle on floors, and sense enclosure (increased drag in rooms). This is the key Teardown effect. |
| Inter-particle | Repulsion at close range via a uniform-grid spatial hash. Prevents "bright dot" collapse, creates billowing volume. |
| Budget | 4096 → 16384 particles. GPU instance buffer pre-allocated at this size. Spatial hash rebuilt per frame. |
| Architecture | Upgrade the existing `ParticleSystem`, not a new crate or simulation system. Same GPU pipeline, same shader, same emit API. |
| Gas types | Smoke only for now. The system is general enough to add steam, fire, etc. later by adding new Burst presets. |
| Smoke lifetime | Retuned: 3-5s instead of 1.5s, larger initial size, slower rise, stronger repulsion. Smoke fills a room instead of vanishing. |

## 2. World collision (geometry-aware advection)

Each particle, during `update(dt)`, samples the voxel grid around its
position. The collision check is a single `world.solid(pos)` lookup — no
raycast, no AABB sweep. The particle's proposed next position
(`pos + vel * dt`) is checked against the world:

### 2.1 Wall deflection

If `world.solid(next_pos)` is true, the particle doesn't pass through.
Instead, its velocity is projected onto the wall surface:

1. Determine which axis the collision is on by checking
   `world.solid(pos + vel * dt)` component-wise (X, Y, Z separately).
2. Zero the velocity component along the blocked axis.
3. The remaining velocity carries the particle along the wall.

This produces "smoke flows around a corner" behavior: a particle moving
+X into a wall keeps its Y/Z velocity and slides along the wall face.

### 2.2 Ceiling stop (buoyant smoke)

A buoyant particle rising (vel.y > 0) that hits a solid above stops
rising: vel.y is zeroed, and the particle spreads sideways (existing
XZ velocity + random perturbation). This is what makes smoke pool
against ceilings and fill rooms from the top down.

### 2.3 Floor settle (non-buoyant)

A non-buoyant particle falling (vel.y < 0) that hits a solid below
loses vertical velocity and slides along the surface (existing XZ
velocity, damped by friction).

### 2.4 Enclosure sensing

Each particle samples its 6 face-neighbors via `world.solid()`. If 4+
are solid, the particle is "in a room": drag doubles (smoke lingers
and billows instead of streaming through). If 0-1 are solid, normal
drag (smoke spreads freely in open air). This is the "volume of a
space" effect — smoke in a tunnel behaves differently from smoke
outdoors.

Cost: 6 `world.solid()` lookups per particle per step. At 16k particles
and 60 Hz that's ~5.8M lookups/sec — each is a chunk-map hash lookup,
same cost as a raycast's first voxel check.

## 3. Inter-particle repulsion (spatial hash)

### 3.1 Spatial hash grid

A uniform grid with cell size = max particle diameter (~0.3m for smoke).
Built per frame from the live particle list: `FxHashMap<IVec3, Vec<usize>>`
mapping grid cell → indices of particles in that cell. At 16k particles
this is ~16k hash insertions per frame — sub-millisecond.

### 3.2 Repulsion force

For each particle, query its grid cell and the 26 neighboring cells
(3³ - 1). For each nearby particle within the repulsion radius, apply
a force pushing them apart:

```
force = (pos_a - pos_b).normalize() * REPEL_STRENGTH / max(dist², MIN_DIST²)
```

Capped to prevent explosions at coincident points. Typical neighbor
count: 3-8 particles per cell. Total force calculations: ~16k * 6 =
~96k per frame — negligible.

### 3.3 Effect

Without repulsion, smoke particles in a confined space compress into a
single bright dot (they all have the same position after collision
clamps). With repulsion, they push apart into a billowing cloud that
fills the available volume. This is the visual difference between
"smoke overlay" and "smoke filling a room."

## 4. Budget increase

`vox_render::MAX_PARTICLES`: 4096 → 16384. The GPU instance buffer is
already pre-allocated at `MAX_PARTICLES` size and reused every frame
(one `write_buffer` per frame, no per-frame allocation). The only cost
is a larger buffer (16k * 32 bytes = 512KB — trivial for any GPU).

The app-side `ParticleSystem` already drops oldest particles on
overflow. The cap just means more simultaneous smoke clouds can coexist
before old ones are recycled.

## 5. Smoke preset retuning

The existing `Burst` presets for smoke (bomb, laser) get retuned:

| Parameter | Old | New |
|---|---|---|
| Life | 1.5-2.5s | 3.0-5.0s |
| Size | 0.1-0.2m | 0.15-0.35m |
| Speed | 1.5 m/s | 0.8 m/s |
| Buoyant rise | 1.2 m/s² | 0.6 m/s² |
| Size growth | 0.35 * size * dt | 0.15 * size * dt (slower swell) |
| Count per burst | 14-20 | 20-30 |

Slower rise + longer life + repulsion = smoke that billows and lingers
in a room instead of shooting up and vanishing.

## 6. What stays the same

- **GPU pipeline**: `vox_render::ParticlePipeline`, `particle.wgsl`
  shader, instanced billboard quads, alpha-blended, depth-tested-no-
  write. No shader changes.
- **No gameplay state**: particles are visual-only. No system reads them
  back, nothing collides with them, they don't affect physics or the
  voxel grid.
- **No new crate**: all changes in `vox-app/src/particles.rs` (sim) and
  `vox-render/src/particles.rs` (budget constant).
- **Emit API**: `burst(Burst { ... })` still works. Tool-emit code in
  `main.rs` doesn't change (though the smoke presets get retuned values).

## 7. Testing plan

All in `vox-app/src/particles.rs` test module:

- **Wall deflection**: a particle moving toward a solid wall deflects
  along the wall surface instead of passing through.
- **Ceiling stop**: a buoyant particle under a solid block stops rising
  and spreads sideways.
- **Floor settle**: a non-buoyant particle falling onto a solid floor
  loses vertical velocity and slides.
- **Enclosure drag**: a particle surrounded by solids experiences higher
  drag than one in open air.
- **Repulsion**: two particles at the same position push apart over time.
- **Spatial hash**: neighbor query returns only nearby particles, not all
  16k.
- **Budget**: 16k particles can be alive without overflow; the 16k+1th
  drops the oldest.

## 8. Explicitly out of scope

- Volumetric density field (deferred by user — may return later).
- Gameplay effects (vision obscuring, suffocation, fluid interaction).
- Steam, fire, toxic gas (smoke only for now; system is general).
- GPU-compute particles (CPU sim + GPU render is sufficient at 16k).
- Particle lighting (no deferred lighting on billboards).
