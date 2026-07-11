# Voxel Engine — Comprehensive Audit Findings

**Date:** 2026-07-11  
**Method:** 16-agent parallel audit swarm across all crates, shaders, and config  
**Scope:** Full codebase analysis — bugs, risks, quality, performance, todos  
**Rule:** Documentation only — no code changes were made

---

## Summary

| Severity | Count |
|---|---|
| **Critical** | 4 |
| **High** | 12 |
| **Medium** | 40+ |
| **Low** | 60+ |
| **Info** | 15+ |

Total findings: **130+** across 16 audit areas.

---

## 1. vox-app/main.rs — Game Loop, Rendering, State

### BUG-1 (Medium): Double-push to debris_order in fire-detach path
**File:** `main.rs` (~line 1400+)  
Fire-triggered detach path pushes body ids to `debris_order` without checking if they're already queued. Can cause duplicate draw calls and wasted body mesh uploads.  
**Fix:** Check `debris_order` for existing entry before push, or use a HashSet for dedup.

### RISK-1 (Medium): Replay playback doesn't sync debris prev_pos/prev_rot
Replay restores body transforms but doesn't update interpolation snapshots, causing visual jitter during playback.  
**Fix:** Update `prev_pos`/`prev_rot` when restoring body state during replay.

### RISK-2 (Medium): Shadow pass culls with main camera frustum instead of shadow camera frustum
Shadow pass uses the main view frustum for culling, but the shadow camera has a different (orthographic) view. Chunks outside the main view but inside the shadow volume won't cast shadows — missing shadows at screen edges.  
**Fix:** Build a frustum from the shadow camera's view-projection and use it for shadow pass culling.

### PERF-1 (Low): Mario HUD textures cloned into new Arc+Vecs every frame
`MarioHudTextures` reconstructs ~64KB of `Arc<[u8]>` from `Vec<u8>::as_slice().into()` every frame. ~7.7MB/s at 120fps.  
**Fix:** Cache the `Arc<MarioHudTextures>` in `MarioMode` and only rebuild when ROM is loaded.

---

## 2. vox-app/mario.rs, player.rs, tools.rs — Gameplay

### BUG-0/FFI-0 (Critical): MarioMode::Drop use-after-free
**File:** `mario.rs` Drop impl  
`sm64` (field 33) drops before `mario` (field 35) and `debris_objects` (field 90) due to Rust declaration-order field drops. `sm64_global_terminate()` frees all C state, then `Mario::drop` calls `sm64_mario_delete` and `SurfaceObject::drop` calls `sm64_surface_object_delete` into terminated state.  
**Fix:** Add `self.mario = None; self.debris_objects.clear();` to `Drop::drop` body before `sm64` is dropped.

### BUG-8 (Low): place_ember not undoable
`place_ember` returns `Option<IVec3>` discarding the old voxel — ember placement can't be undone (unlike `place_voxel` which returns `(IVec3, Voxel)` diff).  
**Fix:** Return `(IVec3, Voxel)` diff like other tools.

### RISK-1 (Low): Gamepad left stick overrides keyboard at tiny deflections
After deadzone rescaling, even 0.16 stick deflection takes priority over WASD.  
**Fix:** Only use gamepad stick when `left_stick.length() > 0.3` or merge keyboard+gamepad vectors.

### RISK-2 (Medium): Gamepad right_stick look is frame-rate dependent
Turn speed varies with FPS, not scaled by dt. At 120fps you turn 2x faster than at 60fps.  
**Fix:** Scale look delta by `dt_frame` or accumulate and apply per fixed timestep.

### RISK-5 (Medium): Death laser collects body IDs after laser spawns new fragments
`death_laser` collects body IDs, then `laser()` carves and spawns new fragments — the collected IDs may include freshly spawned bodies, causing re-carve.  
**Fix:** Collect body IDs into a snapshot before carving.

### FFI-1 (Medium): sm64_audio_tick concurrent with sm64_mario_tick
Audio feeder thread calls `sm64_audio_tick` while main thread calls `sm64_mario_tick` — data race risk in non-thread-safe libsm64. Audio uses separate globals so it works in practice, but it's undocumented.  
**Fix:** Document the concurrency contract or add a mutex.

### PERF-3 (Low): prev_positions/prev_vertex_count are dead code
~36KB allocated, never read or written since interpolation is disabled (`if false &&`).  
**Fix:** Remove fields and their constructor initialization.

### PERF-3b (Medium): voxel_surfaces_near iterates all world chunks
Every resurface call scans all chunks, not just those near Mario.  
**Fix:** Use spatial query or chunk-range iteration.

---

## 3. vox-app/day_night.rs, grass.rs, audio.rs, remesh.rs

### BUG-G1 (High): Grass chunk math wrong for negative coordinates
**File:** `grass.rs:76-81`  
Truncating division (`IVec3 / CHUNK`) instead of euclidean div produces wrong chunk range for negative camera coords. Grass missing near negative world origin.  
**Fix:** Use `div_euclid` / `rem_euclid` or `vox_core::chunk_of`.

### BUG-R1 (High): remesh.rs chunk_at(key).expect() can panic
**File:** `remesh.rs:88`  
Panics if chunk removed between `absorb_dirty` and `dispatch`.  
**Fix:** Use `chunk_at(key).unwrap_or_else()` with graceful skip.

### BUG-D1 (Medium): Day/night sun_height discontinuities at phase boundaries
**File:** `day_night.rs:63-92`  
Sun height jumps 0.15-0.3 at all 4 phase boundaries, causing visible sky/light pops every 20-min cycle.  
**Fix:** Smoothly interpolate sun_height across phase transitions, or ensure continuity at boundaries.

### RISK-A3 (Medium): Audio resampler underrun causes phase discontinuity clicks
**File:** `audio.rs:401-413`  
Underrun resets pos/scratch, producing audible click.  
**Fix:** Crossfade or zero-pad on underrun recovery.

### RISK-A6 (Medium): Non-stereo fallback channel count breaks interleaving
**File:** `audio.rs:245-254`  
If fallback config isn't stereo, interleaving logic breaks.  
**Fix:** Validate channel count and adapt interleaving.

### PERF-G3 (Medium): Grass per-voxel get_voxel over full radius/height
No chunk-existence skip or Uniform fast-path.  
**Fix:** Check chunk Uniform state before iterating voxels.

### PERF-R4 (Medium): Remesh full O(n log n) sort every frame
All pending chunks sorted every frame, only 64 dispatched.  
**Fix:** Use a priority queue or partial sort.

### QUALITY-G2 (Low): game_time param in grass.rs is dead code
Wind animation is in vertex shader via `cam.sun_color.w`.  
**Fix:** Remove the parameter.

---

## 4. vox-render — All Pipelines & GPU Resources

### BUG-1 (Critical): Shadow NDC z double-remap in voxel.wgsl
**File:** `voxel.wgsl:144`  
`ref_depth = ndc.z * 0.5 + 0.5` assumes `ndc.z` is in `[-1,1]` but `orthographic_rh` produces `[0,1]`. This pushes ref_depth ~0.5 too high, effectively disabling shadows. The bounds check `ndc.z < -1.0` should be `ndc.z < 0.0`.  
**Fix:** Remove the `* 0.5 + 0.5` remap, change bounds check to `ndc.z < 0.0`.

### RISK-1 (High): Mario vertex buffer overflow — no bounds check
No bounds check before `write_buffer`, 3072-vertex cap not enforced. If libsm64 produces more vertices, buffer overflow.  
**Fix:** Clamp or assert `num_vertices <= 3072` before write.

### QUALITY-1 (Medium): Dead MRT scaffolding — ~24MB wasted
`normal_tex` + `depth_copy_tex` allocated and bound but never written to or sampled (~24MB wasted at 1080p).  
**Fix:** Remove allocations and bind group entries until MRT is implemented.

### QUALITY-2 (Medium): Dead Gpu::depth_view — ~8MB wasted
Allocated in `new()` and recreated on `resize()` but never read by any consumer.  
**Fix:** Remove the field and its resize logic.

### QUALITY-4 (Medium): Shadow depth bias clamp=0.05 over 400m range
~20m peter-panning. `constant=2` is misleading dead weight.  
**Fix:** Tune bias values for the actual shadow range.

---

## 5. vox-physics/solver.rs, broadphase.rs, contact.rs

### BUG-B1 (Medium): effective_mass zero-divide guard gap in velocity solve
Latent — safe under current spawn paths but no guard mirrors the positional `w<=0` check.  
**Fix:** Add `if eff_mass > 0.0` guard in velocity solve.

### BUG-B3 (Low): apply_impulse adds angular directly to omega, not scaled by inv_iw
Inconsistent with linear side and `apply_contact_impulse`.  
**Fix:** Scale angular impulse by `inv_iw`.

### BUG-B5 (Low): Warm-start map never cleared on despawn
`ContactKey` uses slot index not generation, so recycled slot inherits prior body's accumulated impulse seed. Low impact (8 iters + clamp correct it within one substep).  
**Fix:** Clear warm-start entries for despawned body slots.

### RISK-R1 (Medium): Broadphase stale AABBs across substeps
Built once per step, reused across substeps. Stale start-of-step AABBs can miss pairs that begin overlapping mid-step.  
**Fix:** Rebuild broadphase after position integration, or expand AABBs by max velocity.

### RISK-R7 (Low): Quaternion normalize not length-gated
**File:** `solver.rs:694`  
Unlike vector normalizes at 510/513/684 which are safe, this one can produce NaN on degenerate rotation.  
**Fix:** Add `if q.length_squared() > 0.0` guard.

### PERF-P1 (Medium): Broadphase bucket pair generation is O(B²) per dense cell
Many bodies in one grid cell cause quadratic pair generation.  
**Fix:** Subdivide dense cells or use sort-and-sweep.

### TODO-Q1 (Low): rayon declared but never used
`vox-physics` Cargo.toml declares rayon but zero `par_iter`/`join`/`scope`/`spawn` in src. Dead dependency.  
**Fix:** Remove rayon from Cargo.toml or actually parallelize.

---

## 6. vox-physics/destruction.rs, body_destruction.rs, character.rs

### BUG-1 (Medium): detach_unsupported includes non-solid materials in flood
`lookup.present()` includes non-solid materials (water/leaves); extracted components get mass via `mass_props`, so water can become a mass-bearing flying rigidbody.  
**Fix:** Use `lookup.solid()` instead of `lookup.present()` in flood fill.

### RISK-3 (Medium): ExplosionShape spike zero-length NaN
`contains` divides by `seg.length_squared()` with no zero-guard — zero-length spikes produce NaN. `radius_m==0` triggers it.  
**Fix:** Skip zero-length spikes or add `if seg.length_squared() > 0.0` guard.

### RISK-5 (Low): carve_body_explosion vs carve_explosion off-by-one
Body bomb uses `ceil()` for max while world bomb uses `floor()+1` — slightly less carve area.  
**Fix:** Unify the boundary calculation.

### RISK-9 (Medium): mass_props inertia inverse on near-singular tensors
Thin bars produce huge but non-zero inverse inertia — unstable spinning.  
**Fix:** Add minimum inertia threshold or clamp inverse.

### PERF-4 (Medium): ExplosionShape::contains is O(18 spikes × box_volume)
At 0.1m voxels with radius 3m, ~54M distance computations.  
**Fix:** Add sphere fast-reject before spike tests.

### QUALITY-4/5 (Low): grid_index and DIRS duplicated across 3 files
Divergence risk if indexing formula changes.  
**Fix:** Move to a shared module.

---

## 7. vox-world — Chunk Storage & World Operations

### RISK-1 (Medium): edit_box marks dirty per-voxel instead of per-chunk
O(changes) hash-set inserts instead of O(chunks) — contradicts its own "resolve chunk once" design.  
**Fix:** Accumulate affected chunk coords in a HashSet, call `wake_region` once per chunk.

### RISK-2 (Medium): All-air Dense chunks never demoted
`try_demote` exists but has zero production callers. Cleared chunks stay as 64KB Dense in HashMap forever.  
**Fix:** Call `try_demote` after `edit_box` or `set_voxel` operations.

### PERF-1 (Medium): Dense storage 64KB per chunk, no palette compression
~8x memory reduction available with palette variant.  
**Fix:** Implement `ChunkStorage::Palette` variant (ideas.md #126).

### PERF-2 (Medium): chunks HashMap only grows, never shrinks
No `remove_chunk` API.  
**Fix:** Add chunk eviction for future streaming (#7).

### QUALITY-1 (Medium): No serde/save-load on World/Chunk
WorldConfig is serde-ready but World/Chunk have no Serialize impls.  
**Fix:** Add serde derives and chunk serializer (#8).

---

## 8. vox-mesh — Greedy Meshing & Slab Extraction

### BUG-1 (High): Hardcoded Voxel(9) for water face detection
**File:** `greedy.rs:192`, `slab.rs:152`  
Ignores the `water_voxel` parameter that `mesh_slab` correctly uses elsewhere. If a caller passes a different water material, faces get garbage depth data.  
**Fix:** Derive `is_water` and `opaque` from `water_voxel` parameter, not literal 9.

### BUG-2 (Medium): slice_masks passthrough assumes CHUNK_SIZE=32
If CHUNK_SIZE changes, the `[[bool; CHUNK_SIZE]; 3]` type changes but callers aren't updated.  
**Fix:** Make the type generic or assert CHUNK_SIZE at call sites.

### RISK-2 (Low): Slab position overflow near MAX_SLAB_DIM
u8 overflow possible for very large chunk sizes.  
**Fix:** Use u16 or assert range.

### PERF-1 (Low): extract_uniform still allocates output Vec
For uniform chunks, the output is trivial but still allocates.  
**Fix:** Return a static or pre-allocated mesh for uniform chunks.

---

## 9. vox-sm64 — FFI, Surfaces, HUD Textures, Audio

### BUG-01 (Critical): Mario/SurfaceObject no lifetime tie to Sm64 — use-after-free
`Sm64::drop` calls `sm64_global_terminate()` which frees all C state. `Mario::drop` and `SurfaceObject::drop` then call into freed state.  
**Fix:** Add `PhantomData<&'a Sm64>` to Mario and SurfaceObject, or have Sm64 own all handles.

### BUG-02 (Critical): All structs auto Send+Sync but libsm64 uses mutable globals
Two Marios ticked on two threads = data race via safe Rust.  
**Fix:** Add `PhantomData<*const ()>` to make `!Send + !Sync`.

### BUG-03 (High): SurfaceObject::create callable before sm64_global_init
No `&Sm64` parameter — can be called on uninitialized state.  
**Fix:** Make `create` take `&Sm64`.

### BUG-04 (Medium): render_interpolated doesn't update num_triangles/version
Stale geometry when interpolation is enabled. Currently latent (`if false &&`).  
**Fix:** Update `num_triangles` and `version` after `sm64_mario_render_geometry`.

### RISK-01 (Medium): No ROM length validation
C functions read at hardcoded offsets with no length parameter. SHA1 is single point of failure.  
**Fix:** Add explicit `rom.len()` check against known US ROM size (8,388,608 bytes).

### RISK-02 (Medium): MIO0 get_bit can panic on out-of-bounds bit stream
`mio0_decode` is public — corrupt data causes panic.  
**Fix:** Add bounds check before `get_bit` access.

### RISK-04 (Medium): SurfaceProvider doesn't force refresh after terrain edits
Stale collision when player edits near stationary Mario.  
**Fix:** Add `force_update` method or world version number.

---

## 10. vox-platform — Input, Event Loop, Gamepad

### BUG-1 (High): Stale mouse_delta on restore from minimized
`end_frame()` only runs inside `RedrawRequested`, which early-returns while minimized. `DeviceEvent::MouseMotion` accumulates uncleared and is delivered on first restored frame — camera jump.  
**Fix:** Call `end_frame()` or clear `mouse_delta` even while minimized.

### RISK-1 (Low): Focused(false) doesn't clear gamepad state
Gamepad buttons/sticks remain active when window loses focus.  
**Fix:** Clear gamepad state on focus loss.

### RISK-2 (Low): Triggers lack deadzone
Small trigger values register as pressed.  
**Fix:** Apply deadzone to triggers.

### PERF-1 (Low): poll_gamepad allocates HashSet per frame
`new_down` HashSet allocated every frame.  
**Fix:** Reuse a persistent HashSet with `.clear()`.

---

## 11. vox-debug — HUD & Overlay

### BUG-1 (High): action_name has incorrect hardcoded action values
Ground Pound `0x0C000220` vs actual `0x008008A9`, Pound Land `0x0800023C` vs actual `0x0080023C` — both never match, falling through to generic "Attacking".  
**Fix:** Use correct SM64 action constants from `vox-sm64::ffi`.

### BUG-2 (Medium): Fallback mode doesn't draw lives/coins/stars counters
Only power meter and action label shown when ROM textures unavailable.  
**Fix:** Draw text-based counters in fallback mode.

### PERF-1 (Low): MarioHudTextures reconstructed every frame
~64KB of `Arc<[u8]>` copies per frame.  
**Fix:** Cache `Arc<MarioHudTextures>` in MarioMode.

### RISK-1 (Low): get_hud_cache returns stale TextureHandles
No content hash/version — if source tex data changed, stale handles returned.  
**Fix:** Add a version counter or content hash.

---

## 12. vox-core & vox-gen — Constants, Tunables, Terrain

### BUG-1 (High): height_m panics via f32::clamp when world y-extent < 10.0m
`max_m = extent-6.0 < 4.0 = MIN_HEIGHT_M`. WorldConfig::validate skipped by both `World::new` and `TerrainGen::new`.  
**Fix:** Validate WorldConfig before terrain gen, or use `max_m.max(MIN_HEIGHT_M)`.

### BUG-2 (Medium): Fbm::sample2 returns NaN when octaves==0
`0.0/0.0=NaN`. Fbm::new and octaves field are pub. NaN propagates to `height_m` then `NaN.clamp()` panics.  
**Fix:** Guard `if self.octaves == 0 { return 0.0; }` or enforce octaves >= 1 in constructor.

### RISK-1 (Medium): Tunables fields pub with no validation
Negative friction, NaN blast_power, contact_beta outside [0,1] all accepted silently.  
**Fix:** Add validation in Tunables or clamp in the debug overlay.

### RISK-5 (Low): 64-bit seed folded to 32 bits
Different seeds that differ only in upper 32 bits produce identical terrain.  
**Fix:** Use full 64-bit hash or document the collision.

---

## 13. vox-sim — Fluid, Fire, Weathering CA

### BUG-1 (Medium): Mud never dries when water removed by tool
No `ContactEvent::Vacated` emitted when water is dug/blasted — drying clock never starts.  
**Fix:** Emit vacated events on tool-based water removal, or check for water absence each tick.

### BUG-2 (Low): FireSim::wake_region never called from main.rs
Editor-placed embers won't ignite.  
**Fix:** Call `fire_sim.wake_region()` when editor places ember.

### BUG-3 (Low): Newly ignited fire cells get ticks+=1 on ignition tick
Off-by-one acceleration.  
**Fix:** Don't increment ticks on the ignition tick.

### PERF-1 (Medium): No SolidLookup chunk cache in fluid sim
~3.2M hash-map lookups/tick at 50k active water cells.  
**Fix:** Use `SolidLookup` like the physics solver does.

---

## 14. Shaders — All WGSL Files

### BUG-1 (High): mario.wgsl lighting inverted
`dot(normal, sun_dir)` without negation — lighting inverted vs voxel/grass shaders which use `dot(normal, -sun_dir)`.  
**Fix:** Negate sun_dir in mario.wgsl fragment shader.

### BUG-2 (Medium): grass.wgsl missing fill light
Voxel and mario have fill light contribution; grass doesn't.  
**Fix:** Add fill light term to grass.wgsl.

### BUG-3 (Medium): postprocess.wgsl sobel functions are dead code
`sobel_depth()`, `sobel_vec3()`, `boost_saturation` never called — edge detection not applied. `normal_tex` and `depth_copy_tex` never rendered into.  
**Fix:** Wire MRT or remove dead code (see #64 in ideas.md).

### BUG-4 (Low): Water pipeline comment says depth_write enabled but code sets false
Misleading comment.  
**Fix:** Update comment to match code.

### RISK: mesh_compute.wgsl is entirely dead code with its own bugs
**Fix:** Remove or implement GPU compute meshing (#40).

### TODO: Shader validation test only covers voxel.wgsl
7 other shaders untested.  
**Fix:** Add validation tests for all shaders.

---

## 15. Build Config & Dependencies

### BUG-1 (High): Broken libsm64 submodule
Gitlink committed without `.gitmodules` — fresh clones impossible.  
**Fix:** Add `.gitmodules` or vendor the source.

### BUG-2 (Medium): import-mario-geo.py prerequisite undocumented
Required for vox-sm64 build but not mentioned in README quickstart.  
**Fix:** Document in README or automate in build.rs.

### QUALITY: Unused dependencies
- `thiserror` in vox-world
- `rayon` in vox-physics  
- `tracing` in vox-gen  
**Fix:** Remove unused deps.

### QUALITY: thiserror v1+v2 coexist in Cargo.lock
Transitive deps pull v1, workspace pins v2.  
**Fix:** Update transitive deps or pin consistently.

---

## 16. Cross-Cutting — Error Handling, Threading, Unsafe, Panics

### RES-1/UNS-4 (Medium): MarioMode drop order violates Mario::drop SAFETY precondition
Same as BUG-0 in section 2 — sm64 terminates before mario deletes.  
**Fix:** Clear mario and debris_objects in Drop before sm64 drops.

### EH-1 (Medium): Box<dyn Error> at app boundary discards typed errors
`VoxApp::new` returns `Box<dyn Error>`, losing all type info.  
**Fix:** Create unified `VoxError` enum with `#[from]` conversions (ideas.md #80).

### UNS-1 (Medium): RingBuffer SPSC invariant not runtime-enforced
**Fix:** Add debug_assert for head/tail bounds.

### UNS-3 (Medium): No guard against double Sm64::init
Two `Sm64::init` calls = double `sm64_global_init` — UB.  
**Fix:** Add `static INITIALIZED: AtomicBool` guard.

### UNS-6 (Medium): sm64_audio_tick concurrency undocumented
Audio thread + main thread both call into libsm64.  
**Fix:** Document the concurrency contract.

### THR-1 (Medium): rayon::spawn no panic isolation
If a rayon worker panics, it propagates.  
**Fix:** Wrap rayon tasks in `catch_unwind`.

### PAN-1 (Medium): mario_mode.unwrap() cluster
Multiple `.unwrap()` calls on `self.mario_mode` in main.rs — panic if state is inconsistent.  
**Fix:** Use `if let Some(mode) = &self.mario_mode` pattern consistently.

### PAN-2 (Medium): solver .expect('body alive') in hot path
Solver hot loop has expect on body slot — panic if body despawned mid-solve.  
**Fix:** Use `continue` on None body.

### TEST: vox-debug has zero tests
No test coverage for HUD rendering, texture caching, or overlay panels.  
**Fix:** Add unit tests for HUD state and texture cache logic.

### TEST: GPU-dependent pipeline code untested
All render pipeline creation and frame loop code has no tests.  
**Fix:** Add integration tests or headless GPU tests.

---

## Top Priority Fixes (Ranked)

1. **Shadow NDC z double-remap** (BUG-1 §4) — shadows effectively disabled
2. **MarioMode Drop use-after-free** (BUG-0 §2 / RES-1 §16) — UB on every mode exit
3. **Mario/SurfaceObject !Send + !Sync** (BUG-02 §9) — soundness hole
4. **Mario.wgsl lighting inverted** (BUG-1 §14) — Mario lit from wrong direction
5. **Grass chunk math for negative coords** (BUG-G1 §3) — grass missing
6. **remesh chunk_at expect panic** (BUG-R1 §3) — crash on chunk eviction
7. **action_name wrong action constants** (BUG-1 §11) — HUD shows wrong labels
8. **height_m panic on small worlds** (BUG-1 §12) — crash with small extent
9. **Stale mouse_delta on restore** (BUG-1 §10) — camera jump from minimized
10. **MIO0 get_bit panic on corrupt data** (RISK-02 §9) — crash on bad ROM
11. **detach_unsupported includes non-solid** (BUG-1 §6) — water becomes rigidbody
12. **Dead MRT scaffolding ~24MB wasted** (QUALITY-1 §4) — memory waste
13. **Warm-start stale on despawn** (BUG-B5 §5) — physics impulse carryover
14. **Audio underrun clicks** (RISK-A3 §3) — audio quality
15. **Day/night phase discontinuities** (BUG-D1 §3) — visual pops

---

*Generated by 16-agent parallel audit swarm. Each agent analyzed a specific crate or cross-cutting concern. Full detailed reports available in agent transcripts.*
