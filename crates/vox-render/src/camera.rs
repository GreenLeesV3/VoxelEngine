//! Free-flying perspective camera. Input mapping lives in the app; this type
//! only holds pose and produces matrices.

use glam::{Mat4, Vec3};

/// Vertical field of view in degrees.
const FOV_Y_DEG: f32 = 70.0;
/// Near clip plane in meters (small: voxels can be 0.1 m).
const Z_NEAR: f32 = 0.05;
/// Far clip plane in meters.
const Z_FAR: f32 = 600.0;
/// Pitch limit just short of straight up/down to avoid gimbal flip.
const PITCH_LIMIT: f32 = std::f32::consts::FRAC_PI_2 - 0.001;

/// A fly camera: position plus yaw/pitch in radians.
#[derive(Clone, Debug)]
pub struct Camera {
    pub pos: Vec3,
    /// Rotation around +Y; `0` looks toward -Z.
    pub yaw: f32,
    /// Positive looks up.
    pub pitch: f32,
}

impl Camera {
    pub fn new(pos: Vec3) -> Self {
        Self {
            pos,
            yaw: 0.0,
            pitch: 0.0,
        }
    }

    /// Apply a mouse-look delta in radians.
    pub fn look(&mut self, d_yaw: f32, d_pitch: f32) {
        self.yaw = (self.yaw + d_yaw) % std::f32::consts::TAU;
        self.pitch = (self.pitch + d_pitch).clamp(-PITCH_LIMIT, PITCH_LIMIT);
    }

    /// Unit vector the camera looks along.
    pub fn forward(&self) -> Vec3 {
        let (sy, cy) = self.yaw.sin_cos();
        let (sp, cp) = self.pitch.sin_cos();
        Vec3::new(-sy * cp, sp, -cy * cp)
    }

    /// Unit vector to the camera's right, horizontal.
    pub fn right(&self) -> Vec3 {
        let (sy, cy) = self.yaw.sin_cos();
        Vec3::new(cy, 0.0, -sy)
    }

    /// View-projection matrix for the given surface aspect ratio (0..1 depth).
    pub fn view_proj(&self, aspect: f32) -> Mat4 {
        let proj = Mat4::perspective_rh(FOV_Y_DEG.to_radians(), aspect, Z_NEAR, Z_FAR);
        let view = Mat4::look_to_rh(self.pos, self.forward(), Vec3::Y);
        proj * view
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_orientation_looks_toward_negative_z() {
        let cam = Camera::new(Vec3::ZERO);
        assert!((cam.forward() - Vec3::NEG_Z).length() < 1e-6);
        assert!((cam.right() - Vec3::X).length() < 1e-6);
    }

    #[test]
    fn pitch_is_clamped() {
        let mut cam = Camera::new(Vec3::ZERO);
        cam.look(0.0, 10.0);
        assert!(cam.pitch < std::f32::consts::FRAC_PI_2);
        cam.look(0.0, -20.0);
        assert!(cam.pitch > -std::f32::consts::FRAC_PI_2);
    }

    #[test]
    fn forward_and_right_stay_orthogonal() {
        let mut cam = Camera::new(Vec3::ZERO);
        cam.look(1.234, 0.567);
        assert!(cam.forward().dot(cam.right()).abs() < 1e-5);
        assert!((cam.forward().length() - 1.0).abs() < 1e-5);
    }
}
