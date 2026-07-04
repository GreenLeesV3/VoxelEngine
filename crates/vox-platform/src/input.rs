//! Per-frame input state fed from winit window and device events.
//!
//! Keyboard uses physical key codes (layout-independent). Mouse look input
//! comes from raw `DeviceEvent::MouseMotion` deltas, not cursor position, so
//! it keeps working when the cursor is grabbed or hits a screen edge.

use std::collections::HashSet;

use glam::Vec2;
use winit::event::{DeviceEvent, ElementState, MouseButton, MouseScrollDelta, WindowEvent};
use winit::keyboard::{KeyCode, PhysicalKey};

/// Approximate pixels per scroll "line", used to normalize trackpad
/// `PixelDelta` scrolling to line units.
const WHEEL_PIXELS_PER_LINE: f32 = 16.0;

/// Snapshot of input state for the current frame.
///
/// Fed by the platform loop via [`InputState::handle_window_event`] /
/// [`InputState::handle_device_event`]; per-frame edges and deltas are
/// cleared by [`InputState::end_frame`] after the app has run.
#[derive(Debug, Default)]
pub struct InputState {
    keys_down: HashSet<KeyCode>,
    pressed_this_frame: HashSet<KeyCode>,
    mouse_buttons_down: HashSet<MouseButton>,
    clicked_this_frame: HashSet<MouseButton>,
    /// Raw mouse motion accumulated this frame, in device units
    /// (approximately pixels; +x right, +y down).
    pub mouse_delta: Vec2,
    /// Scroll wheel movement this frame, in lines (positive = scroll up /
    /// away from the user).
    pub wheel_delta: f32,
}

impl InputState {
    /// Create an empty input state.
    pub fn new() -> Self {
        Self::default()
    }

    /// True while the key is held.
    pub fn key_down(&self, key: KeyCode) -> bool {
        self.keys_down.contains(&key)
    }

    /// True only on the frame the key transitioned to pressed.
    pub fn key_pressed(&self, key: KeyCode) -> bool {
        self.pressed_this_frame.contains(&key)
    }

    /// True while the mouse button is held.
    pub fn mouse_down(&self, button: MouseButton) -> bool {
        self.mouse_buttons_down.contains(&button)
    }

    /// True only on the frame the mouse button transitioned to pressed.
    pub fn mouse_clicked(&self, button: MouseButton) -> bool {
        self.clicked_this_frame.contains(&button)
    }

    /// Feed a winit window event (keyboard, mouse buttons, wheel, focus).
    pub fn handle_window_event(&mut self, event: &WindowEvent) {
        match event {
            WindowEvent::KeyboardInput { event, .. } => {
                if let PhysicalKey::Code(code) = event.physical_key {
                    self.on_key(code, event.state);
                }
            }
            WindowEvent::MouseInput { state, button, .. } => {
                self.on_mouse_button(*button, *state);
            }
            WindowEvent::MouseWheel { delta, .. } => self.on_wheel(delta),
            // Release everything on focus loss so alt-tab cannot leave keys
            // stuck down (the matching release event goes to another window).
            WindowEvent::Focused(false) => {
                self.keys_down.clear();
                self.mouse_buttons_down.clear();
            }
            _ => {}
        }
    }

    /// Feed a winit device event (raw mouse motion for look input).
    pub fn handle_device_event(&mut self, event: &DeviceEvent) {
        if let DeviceEvent::MouseMotion { delta: (dx, dy) } = event {
            self.mouse_delta += Vec2::new(*dx as f32, *dy as f32);
        }
    }

    /// Clear per-frame edges and deltas. The platform loop calls this after
    /// the app's frame callback; held-key state persists.
    pub fn end_frame(&mut self) {
        self.pressed_this_frame.clear();
        self.clicked_this_frame.clear();
        self.mouse_delta = Vec2::ZERO;
        self.wheel_delta = 0.0;
    }

    fn on_key(&mut self, key: KeyCode, state: ElementState) {
        match state {
            ElementState::Pressed => {
                // `insert` returns false while held, so OS auto-repeat never
                // re-triggers the press edge.
                if self.keys_down.insert(key) {
                    self.pressed_this_frame.insert(key);
                }
            }
            ElementState::Released => {
                self.keys_down.remove(&key);
            }
        }
    }

    fn on_mouse_button(&mut self, button: MouseButton, state: ElementState) {
        match state {
            ElementState::Pressed => {
                if self.mouse_buttons_down.insert(button) {
                    self.clicked_this_frame.insert(button);
                }
            }
            ElementState::Released => {
                self.mouse_buttons_down.remove(&button);
            }
        }
    }

    fn on_wheel(&mut self, delta: &MouseScrollDelta) {
        self.wheel_delta += match delta {
            MouseScrollDelta::LineDelta(_, y) => *y,
            MouseScrollDelta::PixelDelta(pos) => pos.y as f32 / WHEEL_PIXELS_PER_LINE,
        };
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn key_press_sets_down_and_pressed_until_end_frame() {
        let mut input = InputState::new();
        input.on_key(KeyCode::KeyW, ElementState::Pressed);
        assert!(input.key_down(KeyCode::KeyW));
        assert!(input.key_pressed(KeyCode::KeyW));
        input.end_frame();
        assert!(input.key_down(KeyCode::KeyW), "held key survives end_frame");
        assert!(
            !input.key_pressed(KeyCode::KeyW),
            "press edge is consumed by end_frame"
        );
    }

    #[test]
    fn os_key_repeat_does_not_retrigger_pressed() {
        let mut input = InputState::new();
        input.on_key(KeyCode::KeyW, ElementState::Pressed);
        input.end_frame();
        // OS auto-repeat delivers more Pressed events while held.
        input.on_key(KeyCode::KeyW, ElementState::Pressed);
        assert!(!input.key_pressed(KeyCode::KeyW));
        assert!(input.key_down(KeyCode::KeyW));
    }

    #[test]
    fn key_release_clears_down_and_allows_repress() {
        let mut input = InputState::new();
        input.on_key(KeyCode::Space, ElementState::Pressed);
        input.end_frame();
        input.on_key(KeyCode::Space, ElementState::Released);
        assert!(!input.key_down(KeyCode::Space));
        input.on_key(KeyCode::Space, ElementState::Pressed);
        assert!(input.key_pressed(KeyCode::Space), "fresh press re-triggers");
    }

    #[test]
    fn mouse_buttons_mirror_key_semantics() {
        let mut input = InputState::new();
        input.on_mouse_button(MouseButton::Left, ElementState::Pressed);
        assert!(input.mouse_down(MouseButton::Left));
        assert!(input.mouse_clicked(MouseButton::Left));
        input.end_frame();
        assert!(input.mouse_down(MouseButton::Left));
        assert!(!input.mouse_clicked(MouseButton::Left));
        input.on_mouse_button(MouseButton::Left, ElementState::Released);
        assert!(!input.mouse_down(MouseButton::Left));
    }

    #[test]
    fn device_mouse_motion_accumulates_and_end_frame_clears() {
        let mut input = InputState::new();
        input.handle_device_event(&DeviceEvent::MouseMotion { delta: (3.0, -2.0) });
        input.handle_device_event(&DeviceEvent::MouseMotion { delta: (1.0, 1.0) });
        assert_eq!(input.mouse_delta, Vec2::new(4.0, -1.0));
        input.end_frame();
        assert_eq!(input.mouse_delta, Vec2::ZERO);
    }

    #[test]
    fn line_wheel_accumulates_and_end_frame_clears() {
        let mut input = InputState::new();
        input.on_wheel(&MouseScrollDelta::LineDelta(0.0, 1.0));
        input.on_wheel(&MouseScrollDelta::LineDelta(0.0, 2.0));
        assert_eq!(input.wheel_delta, 3.0);
        input.end_frame();
        assert_eq!(input.wheel_delta, 0.0);
    }

    #[test]
    fn focus_loss_releases_held_keys_and_buttons() {
        let mut input = InputState::new();
        input.on_key(KeyCode::KeyW, ElementState::Pressed);
        input.on_mouse_button(MouseButton::Right, ElementState::Pressed);
        input.handle_window_event(&WindowEvent::Focused(false));
        assert!(
            !input.key_down(KeyCode::KeyW),
            "alt-tab must not leave stuck keys"
        );
        assert!(!input.mouse_down(MouseButton::Right));
    }
}
