# Water Pollution — Muddy Water Suspension Lifecycle — Design Document

**Date:** 2026-07-10
**Status:** Approved
**Builds on:** `2026-07-09-water-refinement-design.md` (weathering + contact events),
`2026-07-09-fluid-sim-design.md` (the CA fluid sim), `2026-07-09-powder-design.md`
(powders). This document adds a new fluid material and a suspension lifecycle that
lets mud pollute water and sand settle out. Nothing here changes the sim's core
premises: binary full/empty cells, conserved volume, active-cell sleeping,
settled water costs nothing.

---

## 1. Decisions of Record

| Question | Decision |
|---|---|
| Representation | **New material `muddy_water`** — a discrete fluid, not a concentration field. Fits the binary-cell design contract. Murky brown, slightly denser than water, flows like water. |
| How pollution spreads | **Diffusion-by-contact**: clean `water` adjacent to `muddy_water` converts on a timer. NOT by flowing into water cells — the fluid sim's `is_open == AIR` makes two fluids grid-immiscible, so pollution can't spread by mixing. Contact-timer conversion sidesteps this. |
| Lifecycle | **One suspension lifecycle**: mud → muddy_water (dissolve), muddy_water → water + sand (settle). The user's "mud mixes into water" and "sand settle out" are two halves of one system. |
| Mass conservation | mud (1 cell) → muddy_water (1 cell) → water (1 cell) + sand (1 cell, deposited on terrain below). Net volume grows by 1: the sediment settles onto the floor and the terrain it landed on becomes sand. If below is air/water, no deposit (simplification — sediment stays suspended). |
| Fluid generalization | Replace the single `water: Voxel` in `FluidSim` with `fluids: Vec<Voxel>`. Generalize every hardcoded `== water` / `Voxel(9)` across sim, weathering, fire, physics, meshing, and shader to a fluid-set check. Fixes the latent `Voxel(9)` tech debt as a bonus. Extensible to future fluids (lava, oil). |
| Muddy_water flow | Muddy_water is a full fluid — it flows, levels, and spreads identically to water. The `is_supported` and `has_water_above` checks in the tick loop must recognize muddy_water as fluid, or it won't level/spread correctly. |
| Fire extinguish | Muddy_water extinguishes fire (it's still wet). Fire system's `== table.water` checks generalize to recognize both fluids. |
| Buoyancy | Debris floats/sinks in muddy_water same as water. Physics solver's `water_voxel: Option<Voxel>` generalizes to `fluid_voxels`. |
| Rendering | Muddy_water shares the fluid pass (translucent, depth-write-off, drawn after opaque) but gets its own murky brown palette color, slightly higher alpha (0.80), no ripple, no blue tint. Clean water's visual treatment is unchanged. |
| Enabling | Weathering is opt-in via material table built by name lookup. A missing `muddy_water` name disables weathering gracefully (same pattern as existing). |

## 2. The suspension lifecycle

```
mud ──(water contact, ~4s)──→ muddy_water ──(still ~10s)──→ water + sand below
                                  ↑ diffusion-by-contact (~6s)
                           clean water adjacent
```

Three material transitions, all weathering-style contact-timer driven:

1. **Dissolve**: mud adjacent to water (or muddy_water) → `muddy_water`. The mud cell
   *becomes* polluted water — a 1:1 volume swap. Reuses the existing soak pattern.
2. **Diffusion**: clean `water` adjacent to `muddy_water` → `muddy_water` on a contact
   timer. This spreads pollution *without* grid mixing — it's contact conversion, not
   flow. Sidesteps the `is_open == AIR` immiscibility constraint.
3. **Settle**: `muddy_water` that has been still (`ContactEvent::Settled`, no moves) for
   N ticks → clean `water` + deposits `sand` on the solid cell below it. If below is
   air or water, no deposit (sediment stays suspended). If below is already sand, skip.

No concentration field. No world scanning. All maps drain to empty at steady state.
This preserves the "settled water costs nothing" sleep guarantee.

## 3. Fluid generalization (the cross-cutting change)

### 3.1 Complete touchpoint inventory

**Sim (`fluid.rs`)** — 5 spots, all become `is_fluid(...)`:

| Line | Current | Change |
|---|---|---|
| `:97` `is_simmed` | `v == self.water \|\| powders.contains(&v)` | `self.fluids.contains(&v) \|\| powders.contains(&v)` |
| `:165` `let water = self.water` | feeds `:208`, `:210` | replaced by fluid-set closure/method |
| `:208` `is_supported` | `world.get_voxel(p) == water` | `self.is_fluid(world.get_voxel(p))` |
| `:210` `has_water_above` | `world.get_voxel(pos + IVec3::Y) == water` | `self.is_fluid(...)` |
| `:257` momentum recruit | `nv == water` | `self.is_fluid(nv)` |

`FluidSim` struct: `water: Voxel` → `fluids: Vec<Voxel>`. New method `fn is_fluid(&self, v: Voxel) -> bool { self.fluids.contains(&v) }`. Constructor `with_powders` gains a `fluids` parameter (or a new constructor `with_fluids_and_powders`). The `place_blob` method's `water_material` parameter stays — the caller chooses which fluid to place.

**Weathering (`weathering.rs`)** — 2 spots in existing behavior:

| Line | Current | Change |
|---|---|---|
| `:130` soak water-adjacency | `world.get_voxel(pos + n) == t.water` | `v == t.water \|\| v == t.muddy_water` |
| `:170` dry water-adjacency | `world.get_voxel(pos + n) == t.water` | `v == t.water \|\| v == t.muddy_water` |

`WeatherTable` gains `pub muddy_water: Voxel`. A helper `fn is_wet(&self, v: Voxel) -> bool { v == self.water || v == self.muddy_water }` avoids repeating the check.

**Fire (`fire.rs`)** — 2 spots:

| Line | Current | Change |
|---|---|---|
| `:223` extinguish | `world.get_voxel(pos + n) == table.water` | `table.is_wet(v)` (water or muddy_water) |
| `:240` dark_ash wetting | `world.get_voxel(q + d) == table.water` | `table.is_wet(v)` |

`FireTable` gains `pub muddy_water: Voxel` and `fn is_wet(&self, v: Voxel) -> bool`.

**Physics (`solver.rs`)** — 1 spot:

| Line | Current | Change |
|---|---|---|
| `:481-482` buoyancy | `water_voxel: Option<Voxel>`, `world.get_voxel(bottom_vox) == wv` | `fluid_voxels: Vec<Voxel>` (or `SmallVec`), `self.fluid_voxels.contains(&world.get_voxel(bottom_vox))` |

`set_water_voxel` → `set_fluid_voxels` (or add `add_fluid_voxel`).

**Rendering** — 4 code spots + shader:

| Location | Current | Change |
|---|---|---|
| `slab.rs:121` `opaque()` | `v != AIR && v != Voxel(9)` | `v != AIR && !fluids.contains(&v)` (fluid set passed in) |
| `greedy.rs:162` `is_water` | `slab.get(p) == Voxel(9)` | `fluids.contains(&slab.get(p))` — fixes latent bug where `water_voxel` param is ignored on this line |
| `greedy.rs:186,297` depth baking | `mat == water_voxel` | `fluids.contains(&mat)` |
| `voxel.wgsl:203,204,223,241,251,252` | `mat_id == 9u` (6×) | `is_fluid(mat_id)` helper for pass/shadow/crack/alpha; blue-tint+ripple stays `mat_id == 9u` only |
| `voxel_pipeline.rs:227,271` | `water_pass` specialization constant | generalizes to "fluid pass" — same mechanism |

**Total: 12 code spots + 6 shader lines.**

### 3.2 Shader approach

The shader hardcodes `mat_id == 9u` in 6 places with different purposes:

- `:203` pass selection (opaque skips water) → `is_fluid(mat_id)`
- `:204` pass selection (water pass skips non-water) → `is_fluid(mat_id)`
- `:223` shadow skip (water doesn't receive shadows) → `is_fluid(mat_id)`
- `:241` crack skip (water doesn't get crack decals) → `is_fluid(mat_id)`
- `:251` alpha (water is 0.85, else 1.0) → `select(1.0, fluid_alpha, is_fluid(mat_id))`
- `:252` blue tint + ripple block → stays `mat_id == 9u` only (clean water visual)

Replace with a WGSL helper:
```wgsl
override muddy_water_id: u32 = 0u;  // 0 = no muddy water material
fn is_fluid(id: u32) -> bool { return id == 9u || id == muddy_water_id; }
```
`muddy_water_id` is a specialization constant set at pipeline creation from the registry.
Muddy_water gets alpha 0.80 (murkier), its own palette color, no ripple, no blue tint.

### 3.3 Why `is_supported` and `has_water_above` matter

The leveling/spread path in `step_cell_with_momentum` (lines 421-449) is gated on
`has_water_above` — a cell with no water directly above it cannot level sideways.
And `is_supported` checks whether the destination's down-cell can hold the mover up.
If muddy_water isn't recognized as fluid in these checks:

- A muddy_water column with muddy_water above it can never level sideways → it falls
  and settles like a powder instead of flowing.
- A muddy_water cell above a muddy_water puddle won't see the puddle as support →
  no leveling across the puddle.

Both are required for muddy_water to behave as a fluid, not a powder.

## 4. Weathering pollution logic (`weathering.rs`)

### 4.1 New maps

```
pub struct Weathering {
    table: WeatherTable,
    soaking:    FxHashMap<IVec3, u32>,  // existing — grass/dirt/stone → water contact
    drying:     FxHashMap<IVec3, u32>,  // existing — mud → dirt when water leaves
    dissolving: FxHashMap<IVec3, u32>,  // NEW — mud → muddy_water (water-adjacent mud)
    polluting:  FxHashMap<IVec3, u32>,  // NEW — clean water → muddy_water (muddy_water-adjacent)
    settling:   FxHashMap<IVec3, u32>,  // NEW — muddy_water → water+sand (still for N ticks)
}
```

All five maps drain to empty at steady state, preserving the zero-cost-sleep guarantee.

### 4.2 Tick logic (extends existing `tick`)

**Step 1 — Register** (from `ContactEvent`s):

Existing soak/dry registration, plus:
- For each `Fell`/`Flowed`/`Settled` event on a water or muddy_water cell: mud neighbors
  enter `dissolving` at 0 (if absent).
- For each `Fell`/`Flowed`/`Settled` event on a `muddy_water` cell: clean `water`
  neighbors enter `polluting` at 0 (if absent).
- For each `Settled` event on a `muddy_water` cell: enter `settling` at 0 (if absent).
- For each `Fell`/`Flowed` event on a `muddy_water` cell: remove from `settling`
  (moving = not settling; the timer resets when motion resumes).
- `Vacated` events: existing mud-drying registration, plus remove the vacated cell
  from `settling` (if it was muddy_water and moved, it's no longer settling).

**Step 2 — Advance dissolving**: each `dissolving` entry re-verifies it's still mud with
an adjacent water/muddy_water cell. No wet neighbor → remove. Otherwise count up; at
threshold, `world.set_voxel(pos, muddy_water)`. The converted cell enters `settling`
at 0 (fresh muddy_water starts its settle clock) and its clean-water neighbors enter
`polluting` at 0 (diffusion seed).

**Step 3 — Advance polluting**: each `polluting` entry re-verifies it's still clean
water adjacent to muddy_water. No muddy_water neighbor → remove. Otherwise count up;
at threshold, `world.set_voxel(pos, muddy_water)`. The converted cell enters `settling`
at 0; its clean-water neighbors enter `polluting` at 0 (chain diffusion).

**Step 4 — Advance settling**: each `settling` entry re-verifies it's still muddy_water.
If the cell has moved (material changed, or it's in the active set — meaning it was
re-woken), remove. Otherwise count up; at threshold:
- `world.set_voxel(pos, water)` — clarify to clean water.
- Deposit sand: check cell directly below (`pos - Y`). If it's a solid material
  (stone, dirt, grass, etc., not air/water/muddy_water/sand), `world.set_voxel(below, sand)`.
  If below is air, water, muddy_water, or already sand, skip the deposit.

**Step 5 — Advance soaking/drying**: unchanged logic, but water-adjacency checks now
use `is_wet` (recognizes muddy_water as wet).

### 4.3 Thresholds (fluid ticks @ ~15 Hz)

| Constant | Ticks | ~Seconds | Purpose |
|---|---|---|---|
| `MUD_DISSOLVE_TICKS` | 60 | ~4s | mud → muddy_water when water-adjacent |
| `POLLUTE_SPREAD_TICKS` | 90 | ~6s | clean water → muddy_water when muddy_water-adjacent |
| `MUDDY_SETTLE_TICKS` | 150 | ~10s | muddy_water → water + sand when still |

Tuned by playtesting. Dissolve is fastest (mud readily enters water), diffusion is
moderate (pollution spreads gradually), settle is slowest (suspended sediment takes
time to drop out of still water).

### 4.4 Why sleep stays free

Every map entry is either actively counting toward a conversion or gets removed on
its next verify. A fully-settled polluted lake (all water or all muddy_water at rest)
has no dissolving, polluting, or settling entries left. Wet mud is not tracked in
dissolving unless it has an active water neighbor emitting contact events. Steady
state for any settled body of water: all five maps empty, zero cost.

Conversions call `world.set_voxel`, so remeshing, physics wake, and fluid wake all
flow through the existing dirty-region pipeline. A conversion under settled water
briefly wakes that water; it re-settles the next tick. Bounded and accepted, same
trade-off class as the existing weathering design (§3.3 of water-refinement-design).

## 5. Material definition

`assets/materials/core.toml` gains:

```toml
[[material]]
name = "muddy_water"
color = [0.28, 0.24, 0.18]   # murky brown-green
jitter = 0.04
density = 1100.0              # slightly denser than water (1000)
strength = 0.0
solid = false
fluid = true
```

## 6. Integration (`vox-app/main.rs`)

- `weather_table()`: add `muddy_water: id("muddy_water")?`. Missing → weathering
  disabled (same graceful-fallback pattern).
- `FluidSim::with_powders` → gains `fluids: Vec<Voxel>` parameter. The app builds
  it from all materials where `def.fluid == true` (same pattern as `powder_materials`).
- `fire_table()`: add `muddy_water: id("muddy_water")?`. Missing → fire's wet-check
  falls back to clean water only (fire still works, just muddy_water doesn't extinguish).
- `PhysicsWorld::set_water_voxel` → `set_fluid_voxels` (or `add_fluid_voxel`). The app
  passes all fluid materials.
- Meshing: `mesh_slab`'s `water_voxel: Voxel` parameter → `fluids: &[Voxel]` (or a
  small set). All callers updated.
- After each fluid tick: `weathering.tick(...)` — same call, now handles pollution.

## 7. Testing plan

All headless in `vox-sim` unless noted:

- **Dissolve**: mud adjacent to water → muddy_water after `MUD_DISSOLVE_TICKS`, not
  before. Mud under muddy_water also dissolves (the `is_wet` generalization).
- **Diffusion**: clean water adjacent to muddy_water → muddy_water after
  `POLLUTE_SPREAD_TICKS`. A line of water cells converts outward from a muddy_water
  source.
- **Settle**: muddy_water still for `MUDDY_SETTLE_TICKS` → water + sand below. A
  `Fell` event on the muddy_water cell resets the settle timer (moving water doesn't
  settle). If below is air, no sand deposit.
- **Mass tracking**: through the full lifecycle, mud count decreases, muddy_water
  appears then clears, sand appears, water count is preserved or grows. Water-cell
  count stays conserved by the fluid sim throughout.
- **Sleep**: a fully settled polluted lake → zero active cells AND zero entries in
  all five weathering maps.
- **Existing weathering tests**: all pass unmodified — the `is_wet` generalization
  is behavior-preserving when muddy_water is absent (single-fluid world).
- **Existing fluid tests**: all pass unmodified — the `is_fluid` generalization is
  behavior-preserving when `fluids == [water]`.
- **Fire**: muddy_water adjacent to burning wood → extinguished to char (same as
  clean water).
- **Integration (`vox-app`)**: the drain-lake test still passes. A new test carves
  a pool, places mud in it, fills with water, and confirms the mud dissolves, water
  turns muddy, and sand eventually deposits on the pool floor.

## 8. Explicitly out of scope

- Multiple pollution tiers (muddy → dirty → murky). One material is enough for v1.
- Concentration field / fractional sediment per cell. Violates the binary-cell contract.
- Sand sinking through water (powder-water displacement). Deferred by powder-design §6.
- Erosion transporting sediment downstream beyond the settle-and-deposit model.
- Wetness rendering on terrain (darkened wet mud/dirt beside water).
- Pollution sources beyond mud (e.g. ash, oil, dye).
