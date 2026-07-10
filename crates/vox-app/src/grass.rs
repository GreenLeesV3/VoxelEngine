//! Grass blade generation for nearby exposed grass voxels.
//!
//! Geometry is cached on the CPU. Wind animation lives entirely in the
//! shader, so stationary scenes regenerate only after a world edit.

use glam::{IVec3, UVec3, Vec3};
use vox_core::chunk_origin;
use vox_core::consts::CHUNK_SIZE;
use vox_render::GrassVertex;
use vox_world::{AIR, Voxel, World};

/// How far around the camera to generate grass blades (meters).
const GRASS_RADIUS_M: f32 = 30.0;
const BLADES_PER_VOXEL: usize = 4;

/// Cached grass geometry for the camera's nearby working set.
pub struct GrassCache {
    vertices: Vec<GrassVertex>,
    last_cam_pos: Vec3,
    dirty: bool,
}

impl GrassCache {
    pub fn new() -> Self {
        Self {
            vertices: Vec::new(),
            last_cam_pos: Vec3::splat(f32::MAX),
            dirty: true,
        }
    }

    /// Mark cached blades stale after terrain changes.
    pub fn invalidate(&mut self) {
        self.dirty = true;
    }

    /// Regenerate after a terrain edit or a five-meter camera movement.
    /// Time does not invalidate this cache because wind is shader-driven.
    pub fn get_or_regen(
        &mut self,
        world: &World,
        cam_pos: Vec3,
        voxel_size: f32,
        grass_voxel: Voxel,
    ) -> &[GrassVertex] {
        let moved = (cam_pos - self.last_cam_pos).length_squared() > 25.0;
        if self.dirty || moved {
            self.vertices = generate_grass(world, cam_pos, voxel_size, grass_voxel);
            self.last_cam_pos = cam_pos;
            self.dirty = false;
        }
        &self.vertices
    }
}

/// Generate six non-indexed vertices per blade for nearby grass-top voxels.
pub fn generate_grass(
    world: &World,
    cam_pos: Vec3,
    voxel_size: f32,
    grass_voxel: Voxel,
) -> Vec<GrassVertex> {
    let mut vertices = Vec::new();
    let radius_sq = GRASS_RADIUS_M * GRASS_RADIUS_M;
    let chunk_width = CHUNK_SIZE as f32 * voxel_size;

    // Iterate only resident chunks. The fork's original implementation
    // queried every possible Y chunk voxel-by-voxel, including absent chunks,
    // which exploded into hundreds of millions of hash lookups at 0.1 m.
    let mut nearby: Vec<_> = world
        .chunks()
        .filter_map(|(key, chunk)| {
            let min = chunk_origin(key).as_vec3() * voxel_size;
            let max = min + Vec3::splat(chunk_width);
            let dx = axis_distance(cam_pos.x, min.x, max.x);
            let dz = axis_distance(cam_pos.z, min.z, max.z);
            let distance_sq = dx * dx + dz * dz;
            (distance_sq <= radius_sq).then_some((distance_sq, key, chunk))
        })
        .collect();

    // If the safety cap is reached, preserve the grass nearest the camera.
    nearby.sort_by(|a, b| a.0.total_cmp(&b.0));
    let max_vertices = vox_render::MAX_GRASS_BLADES * 6;

    'chunks: for (_, key, chunk) in nearby {
        if chunk
            .uniform_value()
            .is_some_and(|voxel| voxel != grass_voxel)
        {
            continue;
        }

        let origin = chunk_origin(key);
        for lx in 0..CHUNK_SIZE as i32 {
            for lz in 0..CHUNK_SIZE as i32 {
                let world_x = (origin.x + lx) as f32 * voxel_size;
                let world_z = (origin.z + lz) as f32 * voxel_size;
                let dx = world_x - cam_pos.x;
                let dz = world_z - cam_pos.z;
                if dx * dx + dz * dz > radius_sq {
                    continue;
                }

                for ly in (0..CHUNK_SIZE as i32).rev() {
                    let local = UVec3::new(lx as u32, ly as u32, lz as u32);
                    if chunk.get(local) != grass_voxel {
                        continue;
                    }

                    let pos = origin + IVec3::new(lx, ly, lz);
                    let above = if ly + 1 < CHUNK_SIZE as i32 {
                        chunk.get(UVec3::new(lx as u32, ly as u32 + 1, lz as u32))
                    } else {
                        world.get_voxel(pos + IVec3::Y)
                    };
                    if above != AIR {
                        continue;
                    }

                    let center = Vec3::new(
                        pos.x as f32 * voxel_size + voxel_size * 0.5,
                        pos.y as f32 * voxel_size + voxel_size,
                        pos.z as f32 * voxel_size + voxel_size * 0.5,
                    );
                    for blade in 0..BLADES_PER_VOXEL {
                        push_blade(&mut vertices, pos, center, voxel_size, blade as i32);
                        if vertices.len() >= max_vertices {
                            break 'chunks;
                        }
                    }
                }
            }
        }
    }

    vertices
}

fn push_blade(
    vertices: &mut Vec<GrassVertex>,
    pos: IVec3,
    center: Vec3,
    voxel_size: f32,
    blade: i32,
) {
    let h = hash01(pos.x * 17 + blade, pos.y * 31 + blade, pos.z * 13 + blade);
    let h2 = hash01(
        pos.x * 7 + blade * 3,
        pos.y * 11 + blade * 5,
        pos.z * 19 + blade * 7,
    );
    let h3 = hash01(
        pos.x * 23 + blade * 11,
        pos.y * 5 + blade * 17,
        pos.z * 29 + blade * 2,
    );
    let base = Vec3::new(
        center.x + (h - 0.5) * voxel_size * 0.7,
        center.y,
        center.z + (h2 - 0.5) * voxel_size * 0.7,
    );
    let height = voxel_size * (0.3 + h3 * 0.5);
    let half_width = voxel_size * (0.15 + h * 0.15) * 0.5;
    let facing = h2 * std::f32::consts::TAU;
    let (fz, fx) = facing.sin_cos();
    let tip = base + Vec3::Y * height;

    let bl = Vec3::new(base.x - fx * half_width, base.y, base.z - fz * half_width);
    let br = Vec3::new(base.x + fx * half_width, base.y, base.z + fz * half_width);
    let tl = Vec3::new(tip.x - fx * half_width, tip.y, tip.z - fz * half_width);
    let tr = Vec3::new(tip.x + fx * half_width, tip.y, tip.z + fz * half_width);

    // Two triangles: (bl, br, tl) and (tl, br, tr). The fork accidentally
    // emitted `tr` twice in triangle two, making half of every blade vanish.
    for (point, height_factor) in [
        (bl, 0.0),
        (br, 0.0),
        (tl, 1.0),
        (tl, 1.0),
        (br, 0.0),
        (tr, 1.0),
    ] {
        vertices.push(GrassVertex {
            position: point.to_array(),
            height_factor,
        });
    }
}

fn axis_distance(value: f32, min: f32, max: f32) -> f32 {
    if value < min {
        min - value
    } else if value > max {
        value - max
    } else {
        0.0
    }
}

fn hash01(x: i32, y: i32, z: i32) -> f32 {
    let n = (x.wrapping_mul(374_761_393)
        ^ y.wrapping_mul(668_265_263)
        ^ z.wrapping_mul(2_147_483_647)) as u32;
    let n = n.wrapping_mul(2_246_822_519);
    (n >> 8) as f32 / 16_777_216.0
}

#[cfg(test)]
mod tests {
    use super::*;
    use vox_core::WorldConfig;

    #[test]
    fn every_blade_contains_two_non_degenerate_triangles() {
        let mut world = World::new(WorldConfig::default());
        let grass = Voxel(3);
        let pos = IVec3::new(2, 2, 2);
        world.set_voxel(pos, grass);

        let vertices = generate_grass(&world, Vec3::splat(0.25), 0.1, grass);

        assert_eq!(vertices.len(), BLADES_PER_VOXEL * 6);
        for triangle in vertices.chunks_exact(3) {
            let a = Vec3::from_array(triangle[0].position);
            let b = Vec3::from_array(triangle[1].position);
            let c = Vec3::from_array(triangle[2].position);
            assert!((b - a).cross(c - a).length_squared() > 1.0e-10);
        }
    }
}
