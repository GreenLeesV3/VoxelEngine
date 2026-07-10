//! Build-safe Mario facade used when the optional `mario` feature is off.

use glam::{Quat, Vec2, Vec3};

/// Keep the same nearby-body culling contract as the native integration.
pub const SURFACE_RADIUS_M: f32 = 15.0;

/// Inert state that preserves the application control flow without linking
/// libsm64. Pressing the toggle key explains how to enable the real mode.
pub struct MarioMode {
    pub cam_yaw: f32,
    pub cam_pitch: f32,
}

impl MarioMode {
    pub fn is_active(&self) -> bool {
        false
    }

    pub fn look(&mut self, _delta: Vec2) {}

    pub fn tick(
        &mut self,
        _world: &vox_world::World,
        _input: &vox_platform::InputState,
        _dt: f32,
    ) -> Vec3 {
        Vec3::ZERO
    }

    pub fn pending_ground_pound(&mut self) -> Option<Vec3> {
        None
    }

    pub fn mario_pos_m(&self) -> Vec3 {
        Vec3::ZERO
    }

    pub fn update_debris(&mut self, _bodies: impl Iterator<Item = (u64, Vec3, Quat, Vec3, Vec3)>) {}

    pub fn camera_pos(&self, mario_pos_m: Vec3) -> Vec3 {
        mario_pos_m
    }

    #[allow(clippy::too_many_arguments)]
    pub fn render<'p>(
        &'p self,
        _queue: &wgpu::Queue,
        _pass: &mut wgpu::RenderPass<'p>,
        _view_proj: [[f32; 4]; 4],
        _cam_pos: Vec3,
        _sun_dir: Vec3,
        _sun_strength: f32,
        _sky_color: Vec3,
        _fill_strength: f32,
        _ambient_strength: f32,
        _sun_color: Vec3,
        _ambient_sky: Vec3,
        _ambient_ground: Vec3,
        _fog_start: f32,
        _fog_end: f32,
    ) {
    }
}
