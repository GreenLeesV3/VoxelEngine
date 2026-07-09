//! Water-driven material transformation, fed by `ContactEvent`s from the
//! fluid tick. Never scans the world: it tracks only cells currently
//! soaking (water-adjacent grass/dirt/stone) or drying (mud that lost its
//! water). Both maps drain to empty at steady state, preserving the
//! settled-water-costs-nothing guarantee. See
//! `docs/plans/2026-07-09-water-refinement-design.md` §3.

use glam::IVec3;
use vox_core::FxHashMap;
use vox_world::{Voxel, World};

use crate::fluid::ContactEvent;

/// Soak ticks (at the fluid tick rate, ~15 Hz) before grass dies to dirt.
pub const GRASS_SOAK_TICKS: u32 = 45; // ~3 s
/// Soak ticks before dirt turns to mud.
pub const DIRT_SOAK_TICKS: u32 = 105; // ~7 s
/// Soak ticks of *flowing* contact before stone erodes to sand.
pub const STONE_ERODE_TICKS: u32 = 450; // ~30 s
/// Waterfall multiplier: stone touched by *falling* water accrues this many
/// soak ticks per tick.
pub const STONE_FALL_BOOST: u32 = 5;
/// Dry ticks (no adjacent water) before mud firms back to dirt.
pub const MUD_DRY_TICKS: u32 = 300; // ~20 s

const NEIGHBORS_6: [IVec3; 6] = [
    IVec3::new(1, 0, 0),
    IVec3::new(-1, 0, 0),
    IVec3::new(0, 1, 0),
    IVec3::new(0, -1, 0),
    IVec3::new(0, 0, 1),
    IVec3::new(0, 0, -1),
];

/// Material ids weathering operates on -- resolved by name in the app;
/// tests build it from raw ids.
#[derive(Clone, Copy)]
pub struct WeatherTable {
    pub water: Voxel,
    pub stone: Voxel,
    pub grass: Voxel,
    pub dirt: Voxel,
    pub mud: Voxel,
    pub sand: Voxel,
}

#[derive(Clone, Copy)]
struct Soak {
    ticks: u32,
    /// Stone touched by falling water accrues `STONE_FALL_BOOST` per tick.
    fall_boost: bool,
}

pub struct Weathering {
    table: WeatherTable,
    soaking: FxHashMap<IVec3, Soak>,
    drying: FxHashMap<IVec3, u32>,
}

impl Weathering {
    pub fn new(table: WeatherTable) -> Self {
        Self { table, soaking: FxHashMap::default(), drying: FxHashMap::default() }
    }

    /// Debug/test stats.
    pub fn soaking_count(&self) -> usize {
        self.soaking.len()
    }
    pub fn drying_count(&self) -> usize {
        self.drying.len()
    }

    pub fn tick(&mut self, world: &mut World, events: &[ContactEvent]) {
        let t = self.table;

        // 1. Register: water contact puts transformable neighbors on the
        // soak clock; any contact re-wets mud (cancels drying). Stone only
        // registers for *moving* water -- a settled lake never eats its
        // basin.
        for &ev in events {
            let (pos, moving, fell) = match ev {
                ContactEvent::Fell(p) => (p, true, true),
                ContactEvent::Flowed(p) => (p, true, false),
                ContactEvent::Settled(p) => (p, false, false),
                ContactEvent::Vacated(p) => {
                    // Mud that just lost a water neighbor starts drying.
                    for n in NEIGHBORS_6 {
                        let q = p + n;
                        if world.get_voxel(q) == t.mud {
                            self.drying.entry(q).or_insert(0);
                        }
                    }
                    continue;
                }
            };
            for n in NEIGHBORS_6 {
                let q = pos + n;
                let v = world.get_voxel(q);
                if v == t.mud {
                    self.drying.remove(&q); // re-wetted
                } else if v == t.grass || v == t.dirt || (v == t.stone && moving) {
                    let entry = self.soaking.entry(q).or_insert(Soak { ticks: 0, fall_boost: false });
                    entry.fall_boost |= fell && v == t.stone;
                }
            }
        }

        // 2. Advance soaking. Entries whose water left, or whose material
        // changed under them (blasted, dug), simply drop out.
        let mut converted = Vec::new();
        self.soaking.retain(|&pos, soak| {
            let v = world.get_voxel(pos);
            let threshold = if v == t.grass {
                GRASS_SOAK_TICKS
            } else if v == t.dirt {
                DIRT_SOAK_TICKS
            } else if v == t.stone {
                STONE_ERODE_TICKS
            } else {
                return false;
            };
            // Water gone -> the soak dries up without converting.
            if !NEIGHBORS_6.iter().any(|&n| world.get_voxel(pos + n) == t.water) {
                return false;
            }
            soak.ticks += if v == t.stone && soak.fall_boost { STONE_FALL_BOOST } else { 1 };
            if soak.ticks >= threshold {
                converted.push((pos, v));
                return false;
            }
            true
        });
        for (pos, from) in converted {
            let to = if from == t.grass {
                t.dirt
            } else if from == t.dirt {
                t.mud
            } else {
                t.sand
            };
            world.set_voxel(pos, to);
            // Fresh dirt under standing water keeps soaking toward mud --
            // this is the grass -> dirt -> mud progression.
            if to == t.dirt {
                self.soaking.insert(pos, Soak { ticks: 0, fall_boost: false });
            }
        }

        // 3. Advance drying: mud with water back nearby stops; dry long
        // enough, it firms to dirt.
        let mut dried = Vec::new();
        self.drying.retain(|&pos, ticks| {
            if world.get_voxel(pos) != t.mud {
                return false;
            }
            if NEIGHBORS_6.iter().any(|&n| world.get_voxel(pos + n) == t.water) {
                return false; // wet again
            }
            *ticks += 1;
            if *ticks >= MUD_DRY_TICKS {
                dried.push(pos);
                return false;
            }
            true
        });
        for pos in dried {
            world.set_voxel(pos, self.table.dirt);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use glam::IVec3;
    use vox_core::WorldConfig;
    use vox_world::{AIR, Voxel, World};

    const WATER: Voxel = Voxel(1);
    const STONE: Voxel = Voxel(2);
    const GRASS: Voxel = Voxel(3);
    const DIRT: Voxel = Voxel(4);
    const MUD: Voxel = Voxel(5);
    const SAND: Voxel = Voxel(6);

    fn table() -> WeatherTable {
        WeatherTable { water: WATER, stone: STONE, grass: GRASS, dirt: DIRT, mud: MUD, sand: SAND }
    }

    fn world_with_floor(top: Voxel) -> World {
        let mut w = World::new(WorldConfig {
            voxel_size_m: 1.0,
            extent_m: [16.0, 16.0, 16.0],
            ..WorldConfig::default()
        });
        // air + water non-solid, everything else solid
        w.set_solid_table(vec![false, false, true, true, true, true, true]);
        let (_, max) = w.bounds_voxels();
        w.fill_box(IVec3::ZERO, IVec3::new(max.x, 5, max.z), STONE);
        w.fill_box(IVec3::new(0, 4, 0), IVec3::new(max.x, 5, max.z), top); // top layer
        w
    }

    #[test]
    fn grass_under_settled_water_dies_to_dirt_at_threshold_not_before() {
        let mut world = world_with_floor(GRASS);
        let mut weathering = Weathering::new(table());
        let cell = IVec3::new(8, 4, 8);
        world.set_voxel(cell + IVec3::Y, WATER); // still water directly on top
        let events = vec![ContactEvent::Settled(cell + IVec3::Y)];
        weathering.tick(&mut world, &events);
        for _ in 0..(GRASS_SOAK_TICKS - 2) {
            weathering.tick(&mut world, &[]);
            assert_eq!(world.get_voxel(cell), GRASS, "must not convert early");
        }
        weathering.tick(&mut world, &[]);
        assert_eq!(world.get_voxel(cell), DIRT, "grass must die to dirt at the soak threshold");
        assert_eq!(weathering.soaking_count(), 1, "the fresh dirt re-registers and keeps soaking");
    }

    #[test]
    fn soaked_dirt_becomes_mud() {
        let mut world = world_with_floor(DIRT);
        let mut weathering = Weathering::new(table());
        let cell = IVec3::new(8, 4, 8);
        world.set_voxel(cell + IVec3::Y, WATER);
        weathering.tick(&mut world, &[ContactEvent::Settled(cell + IVec3::Y)]);
        for _ in 0..DIRT_SOAK_TICKS {
            weathering.tick(&mut world, &[]);
        }
        assert_eq!(world.get_voxel(cell), MUD, "soaked dirt must become mud");
    }

    #[test]
    fn still_water_never_erodes_stone_but_flowing_does_and_falling_is_faster() {
        // Still: Settled event over stone -> no soak entry at all.
        let mut world = world_with_floor(STONE);
        let mut weathering = Weathering::new(table());
        let cell = IVec3::new(8, 4, 8);
        world.set_voxel(cell + IVec3::Y, WATER);
        weathering.tick(&mut world, &[ContactEvent::Settled(cell + IVec3::Y)]);
        assert_eq!(weathering.soaking_count(), 0, "still water must not register stone");

        // Flowing: erodes at STONE_ERODE_TICKS.
        let mut ticks_flowing = 0;
        weathering.tick(&mut world, &[ContactEvent::Flowed(cell + IVec3::Y)]);
        while world.get_voxel(cell) == STONE {
            weathering.tick(&mut world, &[]);
            ticks_flowing += 1;
            assert!(ticks_flowing <= STONE_ERODE_TICKS + 2, "flowing erosion must finish near its threshold");
        }
        assert_eq!(world.get_voxel(cell), SAND);

        // Falling: a second stone cell erodes ~5x sooner.
        let mut world = world_with_floor(STONE);
        let mut weathering = Weathering::new(table());
        world.set_voxel(cell + IVec3::Y, WATER);
        let mut ticks_falling = 0;
        weathering.tick(&mut world, &[ContactEvent::Fell(cell + IVec3::Y)]);
        while world.get_voxel(cell) == STONE {
            weathering.tick(&mut world, &[]);
            ticks_falling += 1;
            assert!(ticks_falling <= STONE_ERODE_TICKS / STONE_FALL_BOOST + 2, "waterfall erosion must be ~5x faster");
        }
        assert!(ticks_falling < ticks_flowing / 3, "falling ({ticks_falling}) must be much faster than flowing ({ticks_flowing})");
    }

    #[test]
    fn soak_entries_evaporate_when_the_water_leaves() {
        let mut world = world_with_floor(GRASS);
        let mut weathering = Weathering::new(table());
        let cell = IVec3::new(8, 4, 8);
        world.set_voxel(cell + IVec3::Y, WATER);
        weathering.tick(&mut world, &[ContactEvent::Settled(cell + IVec3::Y)]);
        assert_eq!(weathering.soaking_count(), 1);
        world.set_voxel(cell + IVec3::Y, AIR); // water gone before the threshold
        weathering.tick(&mut world, &[]);
        assert_eq!(weathering.soaking_count(), 0, "no adjacent water -> entry removed");
        assert_eq!(world.get_voxel(cell), GRASS, "and the grass survives");
    }
}
