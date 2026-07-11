//! Greedy meshing with baked vertex ambient occlusion.
//!
//! For each of the six face directions, exposed faces are collected into a
//! per-slice 2-D mask and merged into maximal rectangles. Cells merge only
//! when material AND all four corner AO values match, so merged quads never
//! smear AO across a seam.

use glam::IVec3;
use vox_core::consts::CHUNK_SIZE;
use vox_world::Voxel;

use crate::slab::VoxelSlab;

/// One mesh vertex, 8 bytes. Positions are voxel-corner coordinates relative
/// to the slab's inner minimum (`0..=dims`), scaled by `voxel_size` and
/// transformed in the shader.
///
/// The `ao` byte packs two fields: bits 0-1 are the corner AO level (0..=3),
/// bits 4-7 are the skylight level (0..=15, 15 = open sky). Bits 2-3 are
/// unused. The shader extracts both with bitmask ops.
///
/// The `normal` byte packs the face normal id (bits 0-3, 0..=5) and the
/// blocklight level (bits 4-7, 0..=15). The shader extracts both with
/// bitmask ops.
#[repr(C)]
#[derive(Copy, Clone, PartialEq, Eq, Debug, bytemuck::Pod, bytemuck::Zeroable)]
pub struct VoxelVertex {
    /// Corner position in voxel units, relative to the region minimum.
    pub pos: [u8; 3],
    /// Packed AO (bits 0-1, 0..=3) and skylight (bits 4-7, 0..=15).
    pub ao: u8,
    /// Face normal id: 0..6 = +X, -X, +Y, -Y, +Z, -Z.
    pub normal: u8,
    /// Deterministic per-vertex jitter (0..=255), baked in once at mesh-build
    /// time from this vertex's position -- see `mesh_slab`'s `jitter_seed`
    /// parameter for why this has to be baked rather than computed from
    /// world position in the shader every frame.
    pub jitter: u8,
    /// Material id of the face.
    pub material: u16,
}

/// Mesh geometry for one region: quads as an indexed triangle list.
#[derive(Default)]
pub struct MeshData {
    pub vertices: Vec<VoxelVertex>,
    pub indices: Vec<u32>,
}

impl MeshData {
    /// Number of quads (each quad is 4 vertices / 6 indices).
    pub fn quads(&self) -> usize {
        self.vertices.len() / 4
    }

    /// True when the mesh has no geometry.
    pub fn is_empty(&self) -> bool {
        self.vertices.is_empty()
    }
}

/// The six face directions: (normal id, axis, sign).
const FACE_DIRS: [(u8, usize, i32); 6] = [
    (0, 0, 1),
    (1, 0, -1),
    (2, 1, 1),
    (3, 1, -1),
    (4, 2, 1),
    (5, 2, -1),
];

/// Ambient occlusion for a face corner given its three outer-plane neighbors.
/// Classic rule: two occluded sides fully darken the corner regardless of the
/// diagonal.
#[inline]
fn ao(side1: bool, side2: bool, corner: bool) -> u8 {
    if side1 && side2 {
        0
    } else {
        3 - (u8::from(side1) + u8::from(side2) + u8::from(corner))
    }
}

/// A meshable face cell: merged only with cells equal in material AND all
/// four corner AO values AND skylight. Water depth is NOT part of the merge
/// comparison (it varies across a surface over uneven terrain) — merged
/// density low. Blocklight is also excluded from the merge comparison
/// (like water_depth) — it varies per-voxel in 3D near emissive sources,
/// so including it would fragment greedy merges into single-quad strips.
#[derive(Copy, Clone)]
struct Cell {
    material: Voxel,
    /// Corner AO in (du, dv) order: `[ao00, ao10, ao01, ao11]`.
    ao4: [u8; 4],
    /// Water column depth: how many voxels of the same material extend
    /// downward from this face before a different material. 0 for
    /// non-water materials. Used by the shader for depth-based water
    /// darkening (stored in the jitter field for water faces).
    water_depth: u8,
    /// Skylight level (0..=15): how many air voxels are above this face's
    /// voxel before hitting something solid (or the slab top). 15 = open
    /// sky, 0 = enclosed/underground. Packed into the vertex `ao` byte's
    /// upper nibble so the shader can attenuate ambient light by it.
    skylight: u8,
    /// Blocklight level (0..=15): propagated light from emissive sources
    /// (fire, ember, lava). NOT part of the merge comparison (like
    /// water_depth) — it varies per-voxel in 3D and would fragment greedy
    /// merges near light sources; merged quads take the first cell's value.
    /// Packed into the vertex `normal` byte's high nibble.
    blocklight: u8,
}

impl PartialEq for Cell {
    fn eq(&self, other: &Self) -> bool {
        self.material == other.material && self.ao4 == other.ao4 && self.skylight == other.skylight
    }
}

impl Eq for Cell {}


/// Deterministic per-vertex jitter hash, baked into the mesh once here
/// rather than recomputed from world position in the shader every frame.
/// An earlier version hashed the vertex's *world* position dynamically in
/// WGSL so per-voxel color variation stayed put in world space instead of
/// tiling identically with the mesh's own local coordinates -- fine for a
/// chunk (which never moves), but for a tumbling debris body, world
/// position changes continuously as it rotates/translates, so the "fixed"
/// per-voxel jitter recomputed each frame actually shifted constantly,
/// reading as flicker on every moving body's surface. Baking it in at mesh
/// time instead makes it a fixed property of the geometry, stable
/// regardless of how the object subsequently moves.
///
/// `seed` anchors the pattern to roughly where in a larger space this mesh
/// sits (a chunk's origin, so neighboring chunks don't all tile the
/// identical repeating pattern chunk meshes' own 0..32 local coordinates
/// would otherwise produce); bodies pass `IVec3::ZERO` since their own
/// local grid is already small and irregular enough per shape.
#[inline]
fn jitter_hash(seed: IVec3, local: [u8; 3]) -> u8 {
    let p = seed + IVec3::new(local[0] as i32, local[1] as i32, local[2] as i32);
    let mut x = (p.x as u32)
        .wrapping_mul(0x8529_7a4d)
        ^ (p.y as u32).wrapping_mul(0x68e3_1da4)
        ^ (p.z as u32).wrapping_mul(0x1b56_c4e9);
    x ^= x >> 15;
    x = x.wrapping_mul(0x2c1b_3c6d);
    x ^= x >> 12;
    x = x.wrapping_mul(0x297a_2d39);
    x ^= x >> 15;
    (x & 0xFF) as u8
}

/// Skylight at a face voxel: count air voxels above `p` (starting at
/// `p.y + 1`) until hitting something solid or the slab's top padding row
/// (`inner_dims.y`). Capped at 15. This is a simple top-down column scan --
/// no horizontal propagation -- so voxels under overhangs get a gradient
/// (air gap depth) and fully enclosed voxels get 0. Water (material 9) is
/// treated as transparent to skylight, matching its visual translucency.
#[inline]
fn skylight_above(slab: &VoxelSlab, p: IVec3) -> u8 {
    let top = slab.inner_dims.y;
    let mut count: u8 = 0;
    let mut y = p.y + 1;
    while y <= top && count < 15 {
        if slab.opaque(IVec3::new(p.x, y, p.z)) {
            break;
        }
        count += 1;
        y += 1;
    }
    count
}

/// Blocklight field for a slab: a per-voxel light level (0..=15) propagated
/// from emissive sources (fire, ember, lava) via BFS through air and water.
///
/// Emissive voxels (any position whose material is in `emissive_set`) seed
/// the field at 15. Light then floods outward through non-opaque voxels,
/// decrementing by 1 per Manhattan step, until it reaches 0. Opaque voxels
/// block propagation (light doesn't pass through solid terrain), matching
/// how blocklight works in voxel games.
///
/// The scan covers the full padded volume (inner region + 1-voxel shell) so
/// emissive voxels in neighboring chunks (sampled into the shell) contribute
/// light that bleeds across chunk boundaries. Returns an empty Vec when
/// there are no emissive materials, letting callers skip the lookup.
fn blocklight_field(slab: &VoxelSlab, emissive_set: &[Voxel]) -> Vec<u8> {
    if emissive_set.is_empty() {
        return Vec::new();
    }
    let dims = slab.inner_dims;
    let d = dims + IVec3::splat(2); // padded dims
    let total = (d.x * d.y * d.z) as usize;
    let mut light = vec![0u8; total];

    // Index matching VoxelSlab::index (private): (rel+1) in x-major rows.
    let idx = |rel: IVec3| -> usize {
        let p = rel + IVec3::ONE;
        (p.x + p.z * d.x + p.y * d.x * d.z) as usize
    };

    // BFS queue (Vec + head index avoids importing VecDeque).
    let mut queue: Vec<IVec3> = Vec::new();
    let mut head: usize = 0;

    // Seed: scan the full padded volume for emissive voxels.
    for y in -1..=dims.y {
        for z in -1..=dims.z {
            for x in -1..=dims.x {
                let p = IVec3::new(x, y, z);
                if emissive_set.contains(&slab.get(p)) {
                    let i = idx(p);
                    if light[i] < 15 {
                        light[i] = 15;
                        queue.push(p);
                    }
                }
            }
        }
    }

    // BFS: propagate through non-opaque voxels (air + water).
    while head < queue.len() {
        let p = queue[head];
        head += 1;
        let cur = light[idx(p)];
        if cur <= 1 {
            continue;
        }
        let next = cur - 1;
        for dir in [
            IVec3::X,
            -IVec3::X,
            IVec3::Y,
            -IVec3::Y,
            IVec3::Z,
            -IVec3::Z,
        ] {
            let n = p + dir;
            if n.x < -1 || n.x > dims.x || n.y < -1 || n.y > dims.y || n.z < -1 || n.z > dims.z {
                continue;
            }
            let ni = idx(n);
            if light[ni] < next && !slab.opaque(n) {
                light[ni] = next;
                queue.push(n);
            }
        }
    }

    light
}

/// Look up the blocklight level at a slab-relative position from a field
/// produced by `blocklight_field`. Returns 0 when the field is empty (no
/// emissive materials in this slab).
#[inline]
fn light_at(field: &[u8], padded: IVec3, rel: IVec3) -> u8 {
    if field.is_empty() {
        return 0;
    }
    let p = rel + IVec3::ONE;
    let i = (p.x + p.z * padded.x + p.y * padded.x * padded.z) as usize;
    field[i]
}

/// Greedy-mesh a slab into quads. `jitter_seed` anchors the baked per-vertex
/// jitter pattern (see `jitter_hash`) -- pass a chunk's world origin for
/// chunks, `IVec3::ZERO` for a body's own local mesh. `emissive_set` lists
/// material ids that emit blocklight; the mesher BFS-propagates their light
/// through air and bakes the per-voxel level into each vertex.
pub fn mesh_slab(
    slab: &VoxelSlab,
    jitter_seed: IVec3,
    water_voxel: Voxel,
    emissive_set: &[Voxel],
    slice_masks: Option<&[[bool; CHUNK_SIZE]; 3]>,
) -> MeshData {
    let mut mesh = MeshData::default();
    let dims = slab.inner_dims;
    let padded = dims + IVec3::splat(2);
    let blocklight = blocklight_field(slab, emissive_set);

    // Hoist the mask buffer outside the face loop: allocate once, clear and
    // reuse per face direction. The buffer is always sized to the largest
    // (du * dv) face plane; each face direction reuses it after clearing.
    let max_plane = (dims[1] * dims[2]).max(dims[0] * dims[2]).max(dims[0] * dims[1]);
    let mut mask: Vec<Option<Cell>> = vec![None; max_plane as usize];

    for (normal_id, axis, sign) in FACE_DIRS {
        let slice_mask = slice_masks.map(|m| m[axis]);
        // Tangent axes: u, v are the other two axes in ascending order.
        let (u_axis, v_axis) = match axis {
            0 => (1, 2),
            1 => (0, 2),
            _ => (0, 1),
        };
        let (du, dv) = (dims[u_axis], dims[v_axis]);
        let mut normal = IVec3::ZERO;
        normal[axis] = sign;
        let mut u_dir = IVec3::ZERO;
        u_dir[u_axis] = 1;
        let mut v_dir = IVec3::ZERO;
        v_dir[v_axis] = 1;

        // Reuse the hoisted mask buffer for this face direction.
        let plane_len = (du * dv) as usize;
        debug_assert!(plane_len <= mask.len());
        let mask = &mut mask[..plane_len];
        for slot in mask.iter_mut() {
            *slot = None;
        }

        for slice in 0..dims[axis] {
            // Skip slices with no solid (non-air) voxels — no faces can be
            // generated. The slice mask marks slices that contain at least
            // one non-air voxel; a false slice is all-air, so the inner
            // loop would produce only `None` cells.
            if let Some(sm) = slice_mask {
                if slice < CHUNK_SIZE as i32 && !sm[slice as usize] {
                    continue;
                }
            }

            // Build the mask of exposed faces in this slice.
            for v in 0..dv {
                for u in 0..du {
                    let mut p = IVec3::ZERO;
                    p[axis] = slice;
                    p[u_axis] = u;
                    p[v_axis] = v;
                    let is_water = slab.get(p) == vox_world::Voxel(9);
                    let cell = if (slab.opaque(p) && !slab.opaque(p + normal))
                        || (is_water && !slab.solid(p + normal))
                    {
                        let outer = p + normal;
                        let mut ao4 = [0u8; 4];
                        for (i, (cu, cv)) in
                            [(0, 0), (1, 0), (0, 1), (1, 1)].into_iter().enumerate()
                        {
                            let u_off = if cu == 0 { -u_dir } else { u_dir };
                            let v_off = if cv == 0 { -v_dir } else { v_dir };
                            ao4[i] = ao(
                                slab.opaque(outer + u_off),
                                slab.opaque(outer + v_off),
                                slab.opaque(outer + u_off + v_off),
                            );
                        }
                        // Compute water column depth: for water faces,
                        // count same-material voxels below (Y down) until
                        // a different material or out of bounds. This is
                        // baked into the jitter field for the shader's
                        // depth-based darkening.
                        let mat = slab.get(p);
                        let mut depth: u8 = 0;
                        if mat == water_voxel {
                            // Start at 1: the face voxel itself is one
                            // layer of water. Then count additional
                            // water voxels below.
                            depth = 1;
                            let mut below = p - IVec3::Y;
                            while below.y >= 0 && slab.get(below) == mat {
                                depth = depth.saturating_add(1);
                                below -= IVec3::Y;
                            }
                        }
                        Some(Cell {
                            material: mat,
                            ao4,
                            water_depth: depth,
                            skylight: skylight_above(slab, p),
                            blocklight: light_at(&blocklight, padded, outer),
                        })
                    } else {
                        None
                    };
                    mask[(u + v * du) as usize] = cell;
                }
            }

            // Greedy rectangle merge over the mask.
            for v0 in 0..dv {
                let mut u0 = 0;
                while u0 < du {
                    let Some(cell) = mask[(u0 + v0 * du) as usize] else {
                        u0 += 1;
                        continue;
                    };
                    // Grow width while cells match.
                    let mut w = 1;
                    while u0 + w < du && mask[(u0 + w + v0 * du) as usize] == Some(cell) {
                        w += 1;
                    }
                    // Grow height while the whole row of width `w` matches.
                    let mut h = 1;
                    'grow: while v0 + h < dv {
                        for uu in u0..u0 + w {
                            if mask[(uu + (v0 + h) * du) as usize] != Some(cell) {
                                break 'grow;
                            }
                        }
                        h += 1;
                    }
                    emit_quad(
                        &mut mesh, cell, normal_id, axis, sign, slice, u_axis, v_axis, u0, v0, w, h,
                        jitter_seed, water_voxel,
                    );
                    for vv in v0..v0 + h {
                        for uu in u0..u0 + w {
                            mask[(uu + vv * du) as usize] = None;
                        }
                    }
                    u0 += w;
                }
            }
        }
    }
    mesh
}

/// Append one merged quad as 4 vertices and 6 indices.
#[expect(clippy::too_many_arguments, reason = "internal plumbing of mesh_slab")]
fn emit_quad(
    mesh: &mut MeshData,
    cell: Cell,
    normal_id: u8,
    axis: usize,
    sign: i32,
    slice: i32,
    u_axis: usize,
    v_axis: usize,
    u0: i32,
    v0: i32,
    w: i32,
    h: i32,
    jitter_seed: IVec3,
    water_voxel: Voxel,
) {
    // Corner positions on the face plane, in (du, dv) order 00, 10, 01, 11.
    let plane = if sign > 0 { slice + 1 } else { slice };
    let corner = |cu: i32, cv: i32| -> [u8; 3] {
        let mut p = IVec3::ZERO;
        p[axis] = plane;
        p[u_axis] = u0 + cu * w;
        p[v_axis] = v0 + cv * h;
        debug_assert!(p.cmpge(IVec3::ZERO).all() && p.cmple(IVec3::splat(255)).all());
        [p.x as u8, p.y as u8, p.z as u8]
    };
    let positions = [corner(0, 0), corner(1, 0), corner(0, 1), corner(1, 1)];

    let base = mesh.vertices.len() as u32;
    for (i, pos) in positions.into_iter().enumerate() {
        mesh.vertices.push(VoxelVertex {
            pos,
            ao: cell.ao4[i] | (cell.skylight << 4),
            normal: normal_id | (cell.blocklight << 4),
            jitter: if cell.material == water_voxel { cell.water_depth } else { jitter_hash(jitter_seed, pos) },
            material: cell.material.0,
        });
    }

    // Vertex order is 00, 10, 01, 11. Triangulate along the diagonal that
    // matches the AO gradient (standard anisotropy fix), then orient the
    // winding so the face normal points outward: for +axis faces
    // cross(u_dir, v_dir) already equals +normal when (axis, u, v) is an even
    // permutation of XYZ — which (x,yz), (y,xz) flipped, (z,xy) are not all,
    // so derive orientation from the axis directly.
    let [a00, a10, a01, a11] = cell.ao4;
    let flipped = u32::from(a00) + u32::from(a11) < u32::from(a10) + u32::from(a01);
    // Winding for a face whose cross(u, v) points toward +axis:
    //   axis 0 (u=y, v=z): cross(y, z) = +x
    //   axis 1 (u=x, v=z): cross(x, z) = -y  (odd permutation)
    //   axis 2 (u=x, v=y): cross(x, y) = +z
    let uv_cross_matches_positive = axis != 1;
    let ccw_for_positive = sign > 0;
    let forward = uv_cross_matches_positive == ccw_for_positive;

    let quad: [u32; 6] = match (flipped, forward) {
        // Diagonal 00-11.
        (false, true) => [0, 1, 3, 0, 3, 2],
        (false, false) => [0, 3, 1, 0, 2, 3],
        // Diagonal 10-01.
        (true, true) => [1, 3, 2, 1, 2, 0],
        (true, false) => [1, 2, 3, 1, 0, 2],
    };
    mesh.indices.extend(quad.into_iter().map(|i| base + i));
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;
    use vox_world::AIR;

    const STONE: Voxel = Voxel(1);
    const DIRT: Voxel = Voxel(2);

    /// Deterministic splitmix64 (dependency-free test randomness).
    struct Rng(u64);

    impl Rng {
        fn next_u64(&mut self) -> u64 {
            self.0 = self.0.wrapping_add(0x9e37_79b9_7f4a_7c15);
            let mut z = self.0;
            z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
            z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
            z ^ (z >> 31)
        }
    }

    /// Build a slab from a set of solid voxels inside `dims`.
    fn slab_of(dims: IVec3, solids: &[(IVec3, Voxel)]) -> VoxelSlab {
        let mut data = vec![AIR; (dims.x * dims.y * dims.z) as usize];
        for &(p, v) in solids {
            let idx = (p.x + p.z * dims.x + p.y * dims.x * dims.z) as usize;
            data[idx] = v;
        }
        VoxelSlab::from_grid(dims, &data)
    }

    #[test]
    fn empty_slab_zero_quads() {
        let slab = slab_of(IVec3::splat(4), &[]);
        let mesh = mesh_slab(&slab, IVec3::ZERO, Voxel(0), &[], None);
        assert_eq!(mesh.quads(), 0);
        assert!(mesh.is_empty());
    }

    #[test]
    fn single_voxel_six_quads() {
        let slab = slab_of(IVec3::splat(3), &[(IVec3::splat(1), STONE)]);
        let mesh = mesh_slab(&slab, IVec3::ZERO, Voxel(0), &[], None);
        assert_eq!(mesh.quads(), 6);
        assert_eq!(mesh.indices.len(), 36);
    }

    /// Regression test for a rendering bug: jitter used to be recomputed in
    /// the shader from each vertex's *world* position every frame. That's
    /// stable for a chunk (which never moves) but not for a tumbling debris
    /// body, whose world position changes continuously -- the "fixed"
    /// per-voxel jitter recomputed from a moving position actually shifted
    /// every frame, which read as flicker on every rotating fragment. Baking
    /// the jitter into the mesh at build time (this test's whole point)
    /// means it's a pure function of local geometry and the caller's seed:
    /// re-meshing identical geometry with the same seed must produce
    /// byte-for-byte identical jitter, with no hidden dependency on anything
    /// that could vary as an object moves.
    #[test]
    fn jitter_is_deterministic_from_local_geometry_and_seed_alone() {
        let slab = slab_of(
            IVec3::splat(5),
            &[
                (IVec3::new(1, 1, 1), STONE),
                (IVec3::new(2, 1, 1), STONE),
                (IVec3::new(1, 2, 1), STONE),
            ],
        );
        let mesh_a = mesh_slab(&slab, IVec3::new(7, -3, 42), Voxel(0), &[], None);
        let mesh_b = mesh_slab(&slab, IVec3::new(7, -3, 42), Voxel(0), &[], None);
        let jitter_a: Vec<u8> = mesh_a.vertices.iter().map(|v| v.jitter).collect();
        let jitter_b: Vec<u8> = mesh_b.vertices.iter().map(|v| v.jitter).collect();
        assert_eq!(jitter_a, jitter_b, "same geometry + same seed must match exactly");

        // A body (seed always zero) meshed twice must also match, and a
        // *different* seed (a different chunk's origin) must generally
        // produce a different pattern -- confirming the seed actually
        // participates, not just the local position.
        let mesh_c = mesh_slab(&slab, IVec3::ZERO, Voxel(0), &[], None);
        let jitter_c: Vec<u8> = mesh_c.vertices.iter().map(|v| v.jitter).collect();
        assert_ne!(jitter_a, jitter_c, "different seeds should not collide onto the same pattern");
    }

    #[test]
    fn two_same_material_merge_to_six_quads() {
        let slab = slab_of(
            IVec3::new(2, 1, 1),
            &[(IVec3::new(0, 0, 0), STONE), (IVec3::new(1, 0, 0), STONE)],
        );
        let mesh = mesh_slab(&slab, IVec3::ZERO, Voxel(0), &[], None);
        assert_eq!(mesh.quads(), 6, "coplanar same-material faces must merge");
    }

    #[test]
    fn two_materials_do_not_merge() {
        let slab = slab_of(
            IVec3::new(2, 1, 1),
            &[(IVec3::new(0, 0, 0), STONE), (IVec3::new(1, 0, 0), DIRT)],
        );
        let mesh = mesh_slab(&slab, IVec3::ZERO, Voxel(0), &[], None);
        // 2 end caps + 4 long sides split in two each = 2 + 8 = 10.
        assert_eq!(mesh.quads(), 10);
    }

    #[test]
    fn full_uniform_region_meshes_to_six_quads() {
        let dims = IVec3::splat(32);
        let mut solids = Vec::new();
        for y in 0..32 {
            for z in 0..32 {
                for x in 0..32 {
                    solids.push((IVec3::new(x, y, z), STONE));
                }
            }
        }
        let slab = slab_of(dims, &solids);
        let mesh = mesh_slab(&slab, IVec3::ZERO, Voxel(0), &[], None);
        // Skylight splits each side face at the top row (the topmost voxel
        // sees air above in the padding, so skylight=1; the rest see solid
        // above, skylight=0). Top and bottom faces are uniform. So: 2 caps
        // + 4 sides × 2 = 10 quads, not 6.
        assert_eq!(mesh.quads(), 10, "skylight seam splits side faces at the top row");
        // Corner coordinates must span the whole region.
        let max = mesh.vertices.iter().map(|v| v.pos[0]).max().unwrap();
        assert_eq!(max, 32);
    }

    /// Every exposed face must be covered by exactly one emitted quad cell.
    #[test]
    fn watertight_on_random_slabs() {
        let mut rng = Rng(0xFACADE);
        for round in 0..20 {
            let dims = IVec3::splat(12);
            let mut solids = Vec::new();
            for y in 0..dims.y {
                for z in 0..dims.z {
                    for x in 0..dims.x {
                        if rng.next_u64() % 10 < 3 {
                            let mat = Voxel((rng.next_u64() % 3 + 1) as u16);
                            solids.push((IVec3::new(x, y, z), mat));
                        }
                    }
                }
            }
            let slab = slab_of(dims, &solids);
            let mesh = mesh_slab(&slab, IVec3::ZERO, Voxel(0), &[], None);

            // Brute-force expected exposed faces.
            let mut expected: HashSet<(IVec3, u8)> = HashSet::new();
            for y in 0..dims.y {
                for z in 0..dims.z {
                    for x in 0..dims.x {
                        let p = IVec3::new(x, y, z);
                        if !slab.solid(p) {
                            continue;
                        }
                        for (normal_id, axis, sign) in FACE_DIRS {
                            let mut n = IVec3::ZERO;
                            n[axis] = sign;
                            if !slab.solid(p + n) {
                                expected.insert((p, normal_id));
                            }
                        }
                    }
                }
            }

            // Rasterize emitted quads back into face cells.
            let mut actual: HashSet<(IVec3, u8)> = HashSet::new();
            for quad in mesh.vertices.chunks_exact(4) {
                let normal_id = quad[0].normal;
                let (_, axis, sign) = FACE_DIRS[normal_id as usize];
                let (u_axis, v_axis) = match axis {
                    0 => (1, 2),
                    1 => (0, 2),
                    _ => (0, 1),
                };
                let corner =
                    |v: &VoxelVertex| IVec3::new(v.pos[0] as i32, v.pos[1] as i32, v.pos[2] as i32);
                let (c00, c11) = (corner(&quad[0]), corner(&quad[3]));
                let plane = c00[axis];
                let cell_slice = if sign > 0 { plane - 1 } else { plane };
                for u in c00[u_axis]..c11[u_axis] {
                    for v in c00[v_axis]..c11[v_axis] {
                        let mut cell = IVec3::ZERO;
                        cell[axis] = cell_slice;
                        cell[u_axis] = u;
                        cell[v_axis] = v;
                        assert!(
                            actual.insert((cell, normal_id)),
                            "round {round}: face covered twice: {cell} dir {normal_id}"
                        );
                    }
                }
            }
            assert_eq!(actual, expected, "round {round}: coverage mismatch");
        }
    }

    /// Triangle winding: geometric normals must point along the face normal.
    #[test]
    fn winding_is_outward_ccw() {
        let mut rng = Rng(0xBEEF);
        let dims = IVec3::splat(8);
        let mut solids = Vec::new();
        for y in 0..dims.y {
            for z in 0..dims.z {
                for x in 0..dims.x {
                    if rng.next_u64() % 10 < 4 {
                        solids.push((IVec3::new(x, y, z), STONE));
                    }
                }
            }
        }
        let slab = slab_of(dims, &solids);
        let mesh = mesh_slab(&slab, IVec3::ZERO, Voxel(0), &[], None);
        assert!(!mesh.is_empty());

        for tri in mesh.indices.chunks_exact(3) {
            let p = |i: u32| {
                let v = &mesh.vertices[i as usize];
                glam::Vec3::new(v.pos[0] as f32, v.pos[1] as f32, v.pos[2] as f32)
            };
            let (a, b, c) = (p(tri[0]), p(tri[1]), p(tri[2]));
            let geometric = (b - a).cross(c - a);
            let (_, axis, sign) = FACE_DIRS[mesh.vertices[tri[0] as usize].normal as usize];
            let mut n = glam::Vec3::ZERO;
            n[axis] = sign as f32;
            assert!(
                geometric.dot(n) > 0.0,
                "triangle winding not CCW toward face normal: {a} {b} {c} vs {n}"
            );
        }
    }

    #[test]
    fn ao_darkens_corners_next_to_walls() {
        // A 2x1x2 floor with a wall voxel standing on one corner.
        let slab = slab_of(
            IVec3::new(2, 2, 2),
            &[
                (IVec3::new(0, 0, 0), STONE),
                (IVec3::new(1, 0, 0), STONE),
                (IVec3::new(0, 0, 1), STONE),
                (IVec3::new(1, 0, 1), STONE),
                (IVec3::new(0, 1, 0), STONE), // wall on top of (0,0,0)
            ],
        );
        let mesh = mesh_slab(&slab, IVec3::ZERO, Voxel(0), &[], None);

        // Top faces (+Y, normal id 2) of the floor at y=1 (excluding the wall
        // voxel's own top at y=2).
        let top_floor: Vec<&VoxelVertex> = mesh
            .vertices
            .iter()
            .filter(|v| v.normal == 2 && v.pos[1] == 1)
            .collect();
        assert!(!top_floor.is_empty(), "floor top faces exist");
        let occluded = top_floor.iter().filter(|v| (v.ao & 3) < 3).count();
        let open = top_floor.iter().filter(|v| (v.ao & 3) == 3).count();
        assert!(occluded > 0, "vertices near the wall must darken");
        assert!(open > 0, "vertices away from the wall must stay open");

        // And the differing AO must have split the floor into >1 top quad.
        let top_quads = mesh
            .vertices
            .chunks_exact(4)
            .filter(|q| q[0].normal == 2 && q[0].pos[1] == 1)
            .count();
        assert!(
            top_quads > 1,
            "AO seam must prevent merging into a single quad"
        );
    }

    /// Skylight: a top face under open sky gets skylight > 0, while a side
    /// face of a voxel buried under a solid block gets skylight=0. Values
    /// are packed into the upper nibble of the vertex `ao` byte.
    #[test]
    fn skylight_open_vs_enclosed() {
        // An L-shaped structure: a floor voxel at (0,0,0) with open air
        // above, and a 2-tall pillar at (2,0,0)+(2,1,0). The bottom voxel
        // of the pillar (2,0,0) has solid directly above it, so its -Z
        // side face (normal 4) has skylight=0. The isolated floor voxel's
        // top face (0,0,0) has skylight > 0.
        let slab = slab_of(
            IVec3::new(4, 3, 3),
            &[
                (IVec3::new(0, 0, 0), STONE), // open above
                (IVec3::new(2, 0, 0), STONE), // buried (solid above)
                (IVec3::new(2, 1, 0), STONE), // covers (2,0,0)
            ],
        );
        let mesh = mesh_slab(&slab, IVec3::ZERO, Voxel(0), &[], None);

        // Top face (+Y, normal 2) of (0,0,0): plane at y=1. Corner (1,1,1).
        // Air above → skylight > 0.
        let open_top: Vec<&VoxelVertex> = mesh
            .vertices
            .iter()
            .filter(|v| v.normal == 2 && v.pos[0] == 1 && v.pos[1] == 1 && v.pos[2] == 1)
            .collect();
        assert!(!open_top.is_empty(), "open-sky top face exists");
        for v in &open_top {
            let sky = (v.ao >> 4) & 0xF;
            assert!(sky > 0, "open-sky top must have skylight > 0, got {sky}");
        }

        // -Z face (normal 5) of (2,0,0): plane at z=0. Corner (3,1,0).
        // Voxel above (2,1,0) is solid → skylight=0. This face is unique
        // to the bottom voxel (the top voxel (2,1,0) has its -Z face at
        // z=0 too, but its corners are at y=1..2, not y=0..1). The corner
        // (3,1,0) is at the top edge of the bottom voxel's -Z face.
        // However (3,1,0) is also the bottom edge of the top voxel's -Z
        // face. To disambiguate, use the bottom corner (2,0,0) which is
        // unique to the bottom voxel.
        let enclosed_side: Vec<&VoxelVertex> = mesh
            .vertices
            .iter()
            .filter(|v| v.normal == 5 && v.pos[0] == 2 && v.pos[1] == 0 && v.pos[2] == 0)
            .collect();
        assert!(!enclosed_side.is_empty(), "enclosed side face exists");
        for v in &enclosed_side {
            let sky = (v.ao >> 4) & 0xF;
            assert_eq!(sky, 0, "enclosed side must have skylight 0, got {sky}");
        }
    }

    #[test]
    fn vertex_is_pod_and_8_bytes() {
        assert_eq!(std::mem::size_of::<VoxelVertex>(), 8);
        let v = VoxelVertex {
            pos: [1, 2, 3],
            ao: 3,
            normal: 0,
            jitter: 0,
            material: 7,
        };
        let bytes: &[u8] = bytemuck::bytes_of(&v);
        assert_eq!(bytes.len(), 8);
    }
}
