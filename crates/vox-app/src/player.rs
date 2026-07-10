//! The first-person player: character controller + look state + eye camera.

use glam::Vec3;
use vox_core::consts::{PHYSICS_DT, PLAYER_EYE};
use vox_physics::CharacterController;
use vox_platform::InputState;
use vox_world::World;
use winit::keyboard::KeyCode;

/// Walking speed in m/s.
const WALK_SPEED: f32 = 4.3;
/// Mouse look sensitivity in radians per pixel.
const LOOK_SENSITIVITY: f32 = 0.0025;
/// Pitch limit just short of straight up/down.
const PITCH_LIMIT: f32 = std::f32::consts::FRAC_PI_2 - 0.001;

/// Player state: controller plus view angles and interpolation snapshots.
pub struct Player {
    pub ctrl: CharacterController,
    pub yaw: f32,
    pub pitch: f32,
    /// Noclip/fly speed in m/s (`Ctrl` multiplies by 5); live-tunable via the
    /// debug overlay, synced each frame from `vox_core::Tunables::fly_speed`.
    pub fly_speed: f32,
    prev_pos: Vec3,
}

impl Player {
    pub fn new(pos: Vec3) -> Self {
        Self {
            ctrl: CharacterController::new(pos),
            yaw: 0.0,
            pitch: 0.0,
            fly_speed: vox_core::Tunables::default().fly_speed,
            prev_pos: pos,
        }
    }

    /// Apply mouse look (call once per frame while the cursor is grabbed).
    pub fn look(&mut self, delta: glam::Vec2) {
        self.yaw = (self.yaw - delta.x * LOOK_SENSITIVITY) % std::f32::consts::TAU;
        self.pitch = (self.pitch - delta.y * LOOK_SENSITIVITY).clamp(-PITCH_LIMIT, PITCH_LIMIT);
    }

    /// View direction (unit).
    pub fn look_dir(&self) -> Vec3 {
        let (sy, cy) = self.yaw.sin_cos();
        let (sp, cp) = self.pitch.sin_cos();
        Vec3::new(-sy * cp, sp, -cy * cp)
    }

    /// Horizontal facing vectors for movement.
    fn move_basis(&self) -> (Vec3, Vec3) {
        let (sy, cy) = self.yaw.sin_cos();
        (Vec3::new(-sy, 0.0, -cy), Vec3::new(cy, 0.0, -sy))
    }

    /// Toggle fly/noclip.
    pub fn toggle_fly(&mut self) {
        self.ctrl.noclip = !self.ctrl.noclip;
        tracing::info!(noclip = self.ctrl.noclip, "fly mode toggled");
    }

    /// Run the fixed physics steps for this frame.
    pub fn fixed_steps(&mut self, world: &World, input: &InputState, steps: u32) {
        for _ in 0..steps {
            self.prev_pos = self.ctrl.pos;
            let (forward, right) = self.move_basis();
            let mut wish = Vec3::ZERO;
            if input.key_down(KeyCode::KeyW) {
                wish += forward;
            }
            if input.key_down(KeyCode::KeyS) {
                wish -= forward;
            }
            if input.key_down(KeyCode::KeyD) {
                wish += right;
            }
            if input.key_down(KeyCode::KeyA) {
                wish -= right;
            }
            if self.ctrl.noclip {
                if input.key_down(KeyCode::Space) {
                    wish += Vec3::Y;
                }
                if input.key_down(KeyCode::ShiftLeft) {
                    wish -= Vec3::Y;
                }
            }
            let speed = if self.ctrl.noclip {
                let boost = if input.key_down(KeyCode::ControlLeft) {
                    5.0
                } else {
                    1.0
                };
                self.fly_speed * boost
            } else {
                WALK_SPEED
            };
            let wish_vel = if wish == Vec3::ZERO {
                Vec3::ZERO
            } else {
                wish.normalize() * speed
            };
            let jump = input.key_down(KeyCode::Space);
            self.ctrl.step(world, wish_vel, jump, PHYSICS_DT);
        }
    }

    /// Snap the render-interpolation snapshot to the current position so
    /// `eye()` returns exactly `ctrl.pos` (plus eye height). Used by the
    /// replay system during playback, where `fixed_steps` is skipped and
    /// `prev_pos` would otherwise lag behind snapshots written directly to
    /// `ctrl.pos`.
    pub fn sync_prev_pos(&mut self) {
        self.prev_pos = self.ctrl.pos;
    }

    /// Interpolated eye position for rendering.
    pub fn eye(&self, alpha: f32) -> Vec3 {
        self.prev_pos.lerp(self.ctrl.pos, alpha) + Vec3::new(0.0, PLAYER_EYE, 0.0)
    }
}
