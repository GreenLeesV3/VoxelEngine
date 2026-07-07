# voxelengine

A from-scratch, modular voxel game engine — "Teardown-scale Minecraft."
Walk a procedurally generated world with trees, place and break voxels, and
blast structures into physically simulated debris that tumbles, collides,
and settles. The same engine runs at Teardown-scale (10 cm voxels) or
Minecraft-scale (1 m voxels), chosen per world at creation time.

Everything that defines engine *behavior* — voxel storage, noise, worldgen,
meshing, the rigidbody solver, destruction — is custom Rust, no game engine
or physics engine underneath. Third-party crates are infrastructure only
(GPU, windowing, math, threading, UI, data formats). See
[`docs/plans/2026-07-04-voxel-engine-design.md`](docs/plans/2026-07-04-voxel-engine-design.md)
for the full design rationale.

## Quickstart

```
cargo run -p vox-app --release
cargo run -p vox-app --release -- --scale 1.0 --seed 42
cargo run -p vox-app --release -- --help
```

Requires a DX12 or Vulkan-capable GPU (via wgpu). First launch generates
terrain and meshes it, which can take a second or two on the default 0.1 m
world.

## Controls

| Input | Action |
|---|---|
| `W A S D` | Move |
| Mouse | Look (click once to capture the cursor) |
| `Space` | Jump (walking) / fly up (noclip) |
| `Shift` | Fly down (noclip) |
| `Ctrl` (held, noclip) | 5x fly speed |
| `F` | Toggle fly / noclip |
| `1` / `2` / `3` | Select tool: Place / Break / Blast |
| Mouse wheel | Cycle build material (Place tool) |
| Left click | Use active tool (break voxel, or blast) |
| Right click | Place selected material |
| `[` / `]` | Shrink / grow blast radius (0.5–4 m) |
| `B` | Spawn a wood debris cube in front of the player |
| `X` | Clear all sleeping (settled) debris |
| `F3` | Toggle the debug overlay (FPS, timings, tuning sliders) |
| `Esc` | Release the cursor, then exit |

### CLI

```
voxelengine [--scale 0.1|1.0] [--seed N] [--extent X,Y,Z] [--help]
```

`--scale` is the voxel edge length in meters — this is the one setting that
switches the whole engine between Teardown-scale and Minecraft-scale.
`--extent` is the world's footprint in meters. See
[`crates/vox-app/src/args.rs`](crates/vox-app/src/args.rs).

## Architecture

Nine crates, strictly layered — nothing lower depends on anything higher:

```
vox-app        playable binary: game loop, player, tools, wiring
  |
vox-debug      egui debug overlay (HUD, timings, tuning) — quarantined
vox-render     wgpu pipelines, camera, chunk/debris draw, culling
vox-platform   winit window, input mapping, fixed-timestep loop
  |
vox-physics    rigidbody solver + destruction (carve -> connectivity -> debris)
vox-mesh       greedy meshing (pure functions, headless)
vox-gen        noise, terrain, trees (deterministic)
  |
vox-world      chunk storage, world edits, raycasting, dirty tracking
  |
vox-core       coordinates, voxel scale, material registry, config, errors
```

- `vox-world` knows nothing about rendering or physics.
- `vox-mesh` is pure data-in/data-out — no GPU types, runs headless.
- Everything below `vox-render` runs headless (unit-testable, CI-able).
- `vox-render` has no winit dependency; windows enter only as
  `wgpu::SurfaceTarget`. `vox-debug` owns egui entirely — vox-app never
  imports the `egui` crate directly.

### Unit contract

Gameplay-meaningful quantities are always in **meters/SI** in public APIs —
player height, tree height, blast radius, material density — converted to
voxel counts only at the point of use (`vox_core::coords`). This is what
makes one engine correctly run Teardown-scale or Minecraft-scale worlds:
every system is written against meters, not voxel counts, so changing
`voxel_size_m` doesn't require touching gameplay code. The scale-invariance
tests in `vox-gen` (terrain, trees) and `vox-physics` (character controller)
enforce this mechanically — the same seed produces matching terrain/tree
heights and matching player behavior at both 0.1 m and 1.0 m.

### The destruction pipeline

`vox-physics::destruction`: **carve** a shape from the world (recording what
was removed) -> **flood** 6-connected from anchors (voxels touching the
search region's edge, assumed connected to the wider world, or resting on
the world floor) through the remaining solid material -> **detach** anything
the flood never reaches into a `VoxelGrid` rigidbody. Tiny fragments are
discarded as dust; implausibly large components are left in place as a
safety valve. The search region grows adaptively until its outer shell is
verified free of solid material, so a tall column cut cleanly at its base
correctly detaches its *entire* upper section as one body, not just a local
chunk around the cut.

The rigidbody solver (`vox-physics::solver`) is a sequential-impulse solver
with warm starting, Baumgarte stabilization, Coulomb friction, and
island-consensus sleeping (touching bodies cross the sleep threshold and go
to sleep together, never individually mid-stack — see the commit history for
why that matters). Collision is voxel-grid-native: a body's surface voxels
are sampled directly against the world's or another body's voxel grid, no
convex-hull approximation.

## Extending the engine

The whole point of the crate layering is that new systems are *additions*,
not edits to existing ones.

**Add a material** — pure data, no code: drop a `.toml` file into
`assets/materials/`. Every `*.toml` in that directory loads in
case-insensitive filename order (see the header comment in
[`assets/materials/core.toml`](assets/materials/core.toml) for the schema).
Duplicate names across files are a load error, not a silent override.

**Add a tool** — add a variant to `Tool` in
[`crates/vox-app/src/tools.rs`](crates/vox-app/src/tools.rs), a method on
`Tools` implementing it, and one match arm in `VoxApp::apply_tools` (in
`main.rs`) to wire it to input. `Tool::Blast` is the fullest example: raycast
-> `vox_physics::blast` -> done.

**Add a whole new engine system** (e.g. the planned cellular-automata
fluid/fire sim, or ecosystem/creature life) — add it as a **new sibling
crate** at the `vox-gen`/`vox-physics` tier: it can depend on `vox-core` and
`vox-world` (and `vox-physics` if it needs bodies) without any existing
crate changing. This is deliberate: the layering was chosen so that
"add a concept" means "add a crate," not "thread a new dependency through
six existing files."

**Dependency policy**: third-party crates are infrastructure only (GPU,
windowing, math, threading, UI, data formats, error derives). Everything
that defines engine behavior is ours. Before adding a new crate dependency,
ask whether it *behaves* like part of the game (noise, ECS, physics) — if
so, it probably shouldn't be a dependency.

## Testing

```
cargo test              # ~150 tests, everything below vox-render runs headless
cargo clippy --all-targets -- -D warnings
```

Everything below `vox-render` is unit-tested, including the physics solver
(single/multi-body settling, stacking, a confined pile stress test),
destruction (bridge/pillar severing, floating-fragment detection, the
region-growth fix for tall-column cuts), procedural generation
(deterministic noise, terrain and tree scale-invariance), and the greedy
mesher (watertightness verified against a brute-force reference on random
inputs). `vox-app`'s tools/CLI have their own tests, including one that
drives the *actual* raycast-based blast entry point end to end: blast a
pillar's base, confirm the upper section detaches, tumbles, and sleeps.

## Roadmap (post-MVP, not built)

- Streaming chunk load/unload beyond the current finite-but-sparse world map
  (the `HashMap<ChunkPos, Chunk>` storage is already streaming-ready).
- Palette-compressed chunks and an RLE binary save format (the chunk
  storage's `Uniform`/`Dense` enum already hides this behind `get`/`set`).
- A cellular-automata simulation crate (`vox-sim`): falling sand, fire,
  water — a sibling crate at the physics tier.
- An ecosystem/life crate: creatures, growth, populations.
- Structural stress (load propagation -> creaking collapses) layered on top
  of the existing connectivity pass.
- Debris re-freezing into the world once fully settled, and debris
  re-fracturing under a second hit.
- A raytraced renderer path behind the existing renderer interface;
  shadow maps; transparency.
- **Dependency modernization**: wgpu 0.20 / winit 0.29 / egui 0.28 are
  pinned to the exact combination proven to compile and render on this
  machine at MVP time. Upgrading (e.g. to wgpu 26+, winit 0.30) is a
  contained follow-up isolated to `vox-render`, `vox-platform`, and
  `vox-debug` — no other crate touches these APIs directly.

## License

MIT OR Apache-2.0.
