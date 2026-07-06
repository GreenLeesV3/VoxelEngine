//! View-frustum extraction and AABB visibility tests (Gribb–Hartmann).

use glam::{Mat4, Vec3, Vec4, Vec4Swizzles};

/// One frustum plane: `normal · p + d >= 0` for points inside.
#[derive(Copy, Clone, Debug)]
pub struct Plane {
    pub normal: Vec3,
    pub d: f32,
}

impl Plane {
    fn from_vec4(v: Vec4) -> Self {
        let len = v.xyz().length();
        Self {
            normal: v.xyz() / len,
            d: v.w / len,
        }
    }
}

/// The six planes of a view frustum (left, right, bottom, top, near, far).
#[derive(Copy, Clone, Debug)]
pub struct Frustum {
    pub planes: [Plane; 6],
}

impl Frustum {
    /// Extract planes from a view-projection matrix with 0..1 clip depth
    /// (wgpu/D3D convention, as produced by `Mat4::perspective_rh`).
    pub fn from_view_proj(m: Mat4) -> Self {
        let r0 = m.row(0);
        let r1 = m.row(1);
        let r2 = m.row(2);
        let r3 = m.row(3);
        Self {
            planes: [
                Plane::from_vec4(r3 + r0), // left
                Plane::from_vec4(r3 - r0), // right
                Plane::from_vec4(r3 + r1), // bottom
                Plane::from_vec4(r3 - r1), // top
                Plane::from_vec4(r2),      // near (z >= 0 in 0..1 depth)
                Plane::from_vec4(r3 - r2), // far
            ],
        }
    }

    /// Conservative AABB test: false only when the box is fully outside.
    pub fn aabb_visible(&self, min: Vec3, max: Vec3) -> bool {
        for plane in &self.planes {
            // p-vertex: the box corner farthest along the plane normal.
            let p = Vec3::select(plane.normal.cmpge(Vec3::ZERO), max, min);
            if plane.normal.dot(p) + plane.d < 0.0 {
                return false;
            }
        }
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn camera_at_origin_looking_neg_z() -> Frustum {
        let proj = Mat4::perspective_rh(70f32.to_radians(), 16.0 / 9.0, 0.05, 600.0);
        let view = Mat4::look_at_rh(Vec3::ZERO, Vec3::NEG_Z, Vec3::Y);
        Frustum::from_view_proj(proj * view)
    }

    #[test]
    fn plane_normals_are_unit_length() {
        let f = camera_at_origin_looking_neg_z();
        for plane in f.planes {
            assert!((plane.normal.length() - 1.0).abs() < 1e-5);
        }
    }

    #[test]
    fn box_in_front_is_visible() {
        let f = camera_at_origin_looking_neg_z();
        assert!(f.aabb_visible(Vec3::new(-1.0, -1.0, -12.0), Vec3::new(1.0, 1.0, -10.0)));
    }

    #[test]
    fn box_behind_is_culled() {
        let f = camera_at_origin_looking_neg_z();
        assert!(!f.aabb_visible(Vec3::new(-1.0, -1.0, 10.0), Vec3::new(1.0, 1.0, 12.0)));
    }

    #[test]
    fn box_far_to_the_side_is_culled() {
        let f = camera_at_origin_looking_neg_z();
        assert!(!f.aabb_visible(Vec3::new(500.0, -1.0, -12.0), Vec3::new(502.0, 1.0, -10.0)));
    }

    #[test]
    fn box_beyond_far_plane_is_culled() {
        let f = camera_at_origin_looking_neg_z();
        assert!(!f.aabb_visible(Vec3::new(-1.0, -1.0, -700.0), Vec3::new(1.0, 1.0, -650.0)));
    }

    #[test]
    fn huge_box_straddling_frustum_is_visible() {
        let f = camera_at_origin_looking_neg_z();
        assert!(f.aabb_visible(Vec3::splat(-1000.0), Vec3::splat(1000.0)));
    }
}
