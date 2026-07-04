# Voxel Engine — Design Document

**Date:** 2026-07-04
**Status:** Approved
**Vision:** A from-scratch, modular voxel game engine that runs anywhere from Teardown-scale (10 cm) to Minecraft-scale (1 m) voxels per world, with voxel-native rigidbody destruction physics. First milestone: "Teardown-scale Minecraft" — walk a generated world with trees, place and break voxels, and blast structures into physically simulated debris. The architecture must accept future systems (cellular-automata simulation, ecosystem/life) as new modules without rework.

This replaces the February 2026 prototype, archived at `sandboxing/_archive/voxelengine-feb2026` (build artifacts removed; uncommitted changes preserved).

---

## 1. Decisions of Record

| Question | Decision |
|---|---|
| Prior Feb 2026 engine | Fresh start; old project archived, new engine takes the `voxelengine` folder |
| Voxel scale semantics | **Per-world setting** (`voxel_size_m`), fixed at world creation; every system written scale-agnostic |
| Rigidbody solver | **Custom voxel-native solver** — debris collides via its actual voxel grid (Teardown lineage), no physics library |
| Rendering | **Greedy-meshed rasterization** behind a renderer interface; raytraced path possible later |
| World extent | **Finite now, streaming-ready** — chunk map + APIs assume nothing about world shape; MVP pre-generates a fixed extent |
| MVP player | **Walker + destruction tools** — kinematic first-person character, place/break, blast tool, noclip toggle |
| Foundation | **Rust layered Cargo workspace**, strict one-way crate dependencies |

## 2. Dependency Policy ("entirely ours")

Third-party code is limited to **infrastructure**: `wgpu` (GPU), `winit` (window/input), `glam` (vector math), `rayon` (thread pools), `egui` (debug overlay only, quarantined in one crate), `tracing` (logs), `thiserror` (error derive), `toml`/`serde` (data files). 

Everything that defines engine **behavior** is written in-house: voxel storage, noise, worldgen, tree generation, greedy meshing, the entire rigidbody solver, destruction/connectivity, player controller, game loop, save formats. No game engine (Bevy etc.), no physics engine (Rapier etc.), no noise crate, no ECS crate — MVP entities live in typed generational arenas we write; a full ECS is deferred until ecosystem creatures demand it.

## 3. Architecture

Cargo workspace, nine crates, dependencies flow strictly downward:

```
vox-app        playable binary: game loop, player, tools, wiring
  │
vox-debug      egui debug overlay (HUD, timings, tuning) — quarantined
vox-render     wgpu pipelines, camera, chunk/debris draw, culling
vox-platform   winit window, input mapping, fixed-timestep loop
  │
vox-physics    custom rigidbody solver + destruction→debris pipeline
vox-mesh       greedy meshing (pure functions, headless)
vox-gen        noise, terrain, trees (ours, deterministic)
  │
vox-world      chunk storage, world edits, raycasting, dirty tracking
  │
vox-core       coordinates, voxel scale, material registry, config, errors
```

Load-bearing rules:
- `vox-world` knows nothing about rendering or physics.
- `vox-mesh` is data-in/data-out; testable without a GPU.
- Everything below `vox-render` runs headless (CI-able).
- Future systems (CA fluids/fire, ecosystem life) land as **new sibling crates** at the gen/physics tier; existing crates don't change.

Layout: `crates/vox-*`, `assets/materials/*.toml`, `assets/shaders/*.wgsl`, `docs/plans/`.

## 4. World Data Model

- **Voxel** = `u16` material id, `0` = air. Per-voxel state (damage, temperature) added later as sidecar arrays.
- **Chunk** = 32³ voxels. Storage enum, private behind `get/set`:
  - `Uniform(material)` — homogeneous chunks (~16 bytes; most of any world),
  - `Dense(Box<[u16; 32768]>)` — 64 KB, the interesting shell.
  - Palette compression can be added later without touching callers.
- **World** = `HashMap<ChunkPos, Chunk>` — no fixed array; this is the streaming-ready contract. MVP pre-generates a finite extent (default ≈ 256×256×64 m) and treats outside as void.
- **Edits** go through a world edit API that records dirty chunks (for remeshing) and dirty regions (for physics wake-ups).
- **Raycast**: DDA voxel traversal, verified against brute force in tests.

### Scale-agnosticism (the core contract)
`WorldConfig { seed, voxel_size_m, extent }`. All gameplay-meaningful quantities are in **meters/SI** — player height 1.8 m, dirt layer 1.5 m, tree height 6–10 m, density kg/m³ — converted to voxel counts at point of use. One module in `vox-core` owns all world↔voxel conversion. A test generates the same seed at 0.1 m and 1.0 m and asserts terrain/tree heights match in meters: the contract is enforced mechanically.

### Materials
`assets/materials/*.toml`: name, base color + per-voxel jitter, density (kg/m³), strength (destruction resistance). Voxel mass = density × voxel_size³ → physics is scale-correct by construction.

## 5. World Generation (`vox-gen`)

- **Noise**: our own seeded value + gradient noise with FBM combinators; deterministic, unit-tested against golden values.
- **Terrain**: layered heightmap (continentalness / hills / roughness) → grass/dirt/stone bands, band depths in meters.
- **Trees**: parameterized in meters — tapered trunk, a few recursive branches, ellipsoid leaf canopies — stamped through the world edit API (chunk-boundary safe). Jittered-grid placement by density. At 0.1 m voxels: chunky detailed trees with visible branches; at 1 m: Minecraft-ish.

## 6. Physics & Destruction (`vox-physics`)

### Destruction pipeline (carve → flood → detach)
1. Tool carves a shape from the world (removed voxels + materials recorded).
2. **Connectivity analysis** in the affected neighborhood: flood-fill from the region's anchored boundary (voxels connecting onward to the untouched world).
3. Components the flood does not reach are unsupported → cut from world, converted to **VoxelBody** rigidbodies (own local voxel grid; mass + full inertia tensor summed per-voxel from material density). Components under a size threshold become short-lived particles instead.
4. Blast imparts impulse to spawned bodies.

### Solver (custom, voxel-native, SI units)
- **Bodies**: position, quaternion, linear/angular velocity, mass, inverse inertia; local voxel grid + precomputed surface-voxel sample points.
- **Collision**: point-vs-grid. Body-vs-world: surface points tested against world voxels (normal from hit face). Body-vs-body: one body's points tested in the other's local grid. Voxel-accurate, no hull approximations — the reason we went custom.
- **Dynamics**: fixed 60 Hz with substeps; sequential impulses, Coulomb friction, split-impulse penetration correction, warm starting (stable stacking); spatial-hash broadphase; rayon-parallel narrowphase.
- **Sleeping**: settled bodies cost ~zero; woken by impulses or nearby world edits. Target ≈ 100–200 awake bodies at 60 Hz.
- **Interpolation**: prev/curr transforms blended by accumulator alpha for smooth rendering at any framerate.

### Player
Kinematic controller (not a rigidbody): swept AABB/capsule vs voxel grid, gravity, jump, step-up, noclip/fly toggle. Sized in meters (1.8 m) → works at every voxel scale.

## 7. Meshing & Rendering

- **`vox-mesh`**: greedy meshing (coplanar same-material faces merged into quads). Vertices: quantized chunk-local position, face-normal id, material id, baked vertex AO (corner-count technique). Pure function of chunk + 1-voxel neighbor shell. Tests: exact quad counts on known patterns; watertight, non-overlapping surfaces on random chunks.
- **Remesh scheduling**: dirty chunks → rayon worker pool, prioritized by camera distance; never blocks the frame.
- **`vox-render`**: wgpu; single opaque pipeline for MVP — material palette color, directional sun + hemisphere ambient, vertex AO, distance fog. Camera UBO, CPU frustum culling, chunk mesh manager. Debris: each VoxelBody greedy-meshed once at spawn, drawn with per-body model matrix. No shadowmaps in MVP; pass structure leaves room.
- **`vox-debug`**: egui overlay — FPS, per-system timings from our own scoped-timer profiler, chunk/body counts, physics tuning sliders, material picker.

## 8. Platform & Game Loop

`vox-platform`: winit window, raw input → action mapping, fixed-timestep accumulator.
`vox-app`: owns the Engine; frame order: **input → player → tools → destruction → physics steps → remesh dispatch → interpolated render**. Tools: place voxel, break voxel, blast (sphere carve + impulse). World bootstrap from `WorldConfig`.

## 9. Error Handling

- Fallible **initialization** (GPU device, shaders, asset TOML) returns typed `Result`s (thiserror) surfaced with context — a bad material file names the file and field.
- **Per-frame paths never panic on data**: failed mesh job logs and retries next frame; invariant violations are `debug_assert!` in hot paths.
- `tracing` structured logging throughout; GPU init errors via wgpu error scopes.

## 10. Testing

- Headless unit tests (everything below `vox-render`): noise golden values; chunk storage invariants (Uniform→Dense promotion, bounds); mesher quad counts + watertightness; raycast DDA vs brute force; connectivity detachment cases (cut bridge → island detaches; anchored → nothing detaches); inertia tensor vs analytic box; physics scenarios (drop-and-settle: no NaN, energy decays, nothing below floor; 5-body stacks sleep).
- **Scale-invariance test**: same seed at 0.1 m and 1.0 m → terrain/tree heights match in meters within tolerance.
- `cargo test` at workspace root is the gate; `cargo clippy -D warnings` clean.

## 11. Milestones

| # | Deliverable |
|---|---|
| M0 | Workspace scaffold, window, wgpu clear, debug HUD skeleton |
| M1 | Chunks + flat world + greedy meshing + fly camera |
| M2 | Noise terrain + materials + trees |
| M3 | Walking player + place/break tools + solid remesh pipeline |
| M4 | Rigidbody solver (bodies, world collision, stacking, sleep) |
| M5 | Destruction: carve + connectivity + debris bodies + blast tool |
| M6 | Polish: AO/fog/interpolation tuning, 0.1 m vs 1.0 m scale demo, README |

Implementation tasks: #7 scaffold, #8 core+world, #9 gen, #10 solver, #11 destruction+player, #12 mesh, #13 render+debug, #14 platform+app, #15 polish. Dependencies: 7→8→{9,10,12}, 10→11, 12→13, {9,11,13}→14→15.

## 12. Future Roadmap (designed-for, not built)

- **Streaming worlds**: chunk load/unload + background gen behind the existing HashMap contract.
- **Palette-compressed chunks** and RLE binary save format (chunk API already hides storage).
- **CA simulation crate** (`vox-sim`): falling sand, fire, water — sibling crate at the physics tier.
- **Ecosystem/life crate**: creatures, growth, populations; typed arenas grow into an ECS when needed.
- **Structural stress** (load propagation → creaking collapses) on top of the connectivity pass.
- **Debris re-freeze**: settled bodies re-voxelize into the world.
- **Raytraced renderer path** behind the renderer interface; shadowmaps; transparents.
- **Tooling**: in-engine editor panels beyond debug (brush tools, prefab stamps).
