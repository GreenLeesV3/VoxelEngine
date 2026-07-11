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
/// Gamepad button identifiers matching common controller layouts.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum GamepadButton {
    /// A / Cross (bottom face button)
    South,
    /// B / Circle (right face button)
    East,
    /// X / Square (left face button)
    West,
    /// Y / Triangle (top face button)
    North,
    /// Left shoulder / L1
    LeftShoulder,
    /// Right shoulder / R1
    RightShoulder,
    /// Left trigger / L2
    LeftTrigger,
    /// Right trigger / R2
    RightTrigger,
    /// Select / Back / Share
    Select,
    /// Start / Options
    Start,
    /// Left stick press / L3
    LeftStick,
    /// Right stick press / R3
    RightStick,
    /// D-pad up
    DpadUp,
    /// D-pad down
    DpadDown,
    /// D-pad left
    DpadLeft,
    /// D-pad right
    DpadRight,
}

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
    /// Left stick: (-1..=1 left/right, -1..=1 down/up). Zero when no
    /// gamepad or stick centered.
    pub left_stick: Vec2,
    /// Right stick: (-1..=1 left/right, -1..=1 down/up). Used for camera
    /// look in Mario mode.
    pub right_stick: Vec2,
    /// Left trigger (0..=1), 0 when not pressed.
    pub left_trigger: f32,
    /// Right trigger (0..=1), 0 when not pressed.
    pub right_trigger: f32,
    /// Gamepad buttons currently held.
    gamepad_buttons_down: HashSet<GamepadButton>,
    /// Gamepad buttons pressed this frame (edge).
    gamepad_pressed_this_frame: HashSet<GamepadButton>,
    /// Scratch set reused across `poll_gamepad` calls to avoid per-frame
    /// allocation when building the new held-button set.
    gamepad_down_scratch: HashSet<GamepadButton>,
    /// True when a gamepad is connected and producing input.
    pub gamepad_connected: bool,
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

    /// True while a gamepad button is held.
    pub fn gamepad_down(&self, button: GamepadButton) -> bool {
        self.gamepad_buttons_down.contains(&button)
    }

    /// True only on the frame a gamepad button was pressed.
    pub fn gamepad_pressed(&self, button: GamepadButton) -> bool {
        self.gamepad_pressed_this_frame.contains(&button)
    }

    /// Apply a deadzone to a stick value: returns 0.0 if the magnitude
    /// is below the threshold, otherwise rescales to fill the 0..1 range.
    fn apply_deadzone(v: Vec2, dz: f32) -> Vec2 {
        let mag = v.length();
        if mag < dz {
            return Vec2::ZERO;
        }
        // Rescale so the edge of the deadzone maps to 0 and full
        // deflection maps to 1, giving smooth control across the range.
        let scale = (mag - dz) / (1.0 - dz) / mag;
        v * scale
    }

    /// Poll gilrs for gamepad events and update gamepad state. Called
    /// once per frame by the platform loop before `app.frame()`.
    pub fn poll_gamepad(&mut self, gilrs: &mut gilrs::Gilrs) {
        // Process events (connect/disconnect)
        while let Some(gilrs::Event { event, .. }) = gilrs.next_event() {
            if let gilrs::EventType::Connected = event {
                tracing::info!("Gamepad connected");
            }
        }

        // Find the first connected gamepad
        let Some(gamepad) = gilrs
            .gamepads()
            .find(|(_, gp)| gp.is_connected())
            .map(|(_, gp)| gp)
        else {
            self.gamepad_connected = false;
            self.left_stick = Vec2::ZERO;
            self.right_stick = Vec2::ZERO;
            self.left_trigger = 0.0;
            self.right_trigger = 0.0;
            self.gamepad_buttons_down.clear();
            self.gamepad_pressed_this_frame.clear();
            return;
        };

        self.gamepad_connected = true;

        // Sticks — gilrs uses -1..=1 with +Y up. We use +Y up too.
        const STICK_DZ: f32 = 0.15;
        let lx = gamepad.value(gilrs::Axis::LeftStickX);
        let ly = gamepad.value(gilrs::Axis::LeftStickY);
        let rx = gamepad.value(gilrs::Axis::RightStickX);
        let ry = gamepad.value(gilrs::Axis::RightStickY);
        self.left_stick = Self::apply_deadzone(Vec2::new(lx, ly), STICK_DZ);
        self.right_stick = Self::apply_deadzone(Vec2::new(rx, ry), STICK_DZ);

        // Triggers — 0..=1, with a deadzone so light rest pressure reads 0.
        const TRIGGER_DZ: f32 = 0.1;
        let lt = gamepad.value(gilrs::Axis::LeftZ).max(0.0);
        let rt = gamepad.value(gilrs::Axis::RightZ).max(0.0);
        self.left_trigger = if lt > TRIGGER_DZ { (lt - TRIGGER_DZ) / (1.0 - TRIGGER_DZ) } else { 0.0 };
        self.right_trigger = if rt > TRIGGER_DZ { (rt - TRIGGER_DZ) / (1.0 - TRIGGER_DZ) } else { 0.0 };
        // Map gilrs buttons to our GamepadButton enum
        let button_map = [
            (gilrs::Button::South, GamepadButton::South),
            (gilrs::Button::East, GamepadButton::East),
            (gilrs::Button::West, GamepadButton::West),
            (gilrs::Button::North, GamepadButton::North),
            (gilrs::Button::LeftTrigger, GamepadButton::LeftShoulder),
            (gilrs::Button::RightTrigger, GamepadButton::RightShoulder),
            (gilrs::Button::LeftTrigger2, GamepadButton::LeftTrigger),
            (gilrs::Button::RightTrigger2, GamepadButton::RightTrigger),
            (gilrs::Button::Select, GamepadButton::Select),
            (gilrs::Button::Start, GamepadButton::Start),
            (gilrs::Button::LeftThumb, GamepadButton::LeftStick),
            (gilrs::Button::RightThumb, GamepadButton::RightStick),
            (gilrs::Button::DPadUp, GamepadButton::DpadUp),
            (gilrs::Button::DPadDown, GamepadButton::DpadDown),
            (gilrs::Button::DPadLeft, GamepadButton::DpadLeft),
            (gilrs::Button::DPadRight, GamepadButton::DpadRight),
        ];

        // Build the held-button set in a scratch buffer to avoid a per-frame
        // allocation; swap it into place at the end.
        self.gamepad_down_scratch.clear();
        for (gb, our_btn) in &button_map {
            if gamepad.is_pressed(*gb) {
                self.gamepad_down_scratch.insert(*our_btn);
            }
        }

        // Detect newly pressed buttons (edge detection)
        for btn in &self.gamepad_down_scratch {
            if !self.gamepad_buttons_down.contains(btn) {
                self.gamepad_pressed_this_frame.insert(*btn);
            }
        }

        std::mem::swap(&mut self.gamepad_buttons_down, &mut self.gamepad_down_scratch);
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
                // Clear gamepad state too so a controller unplugged or
                // ignored during focus loss can't leave phantom input.
                self.gamepad_buttons_down.clear();
                self.gamepad_pressed_this_frame.clear();
                self.left_stick = Vec2::ZERO;
                self.right_stick = Vec2::ZERO;
                self.left_trigger = 0.0;
                self.right_trigger = 0.0;
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
    pub fn end_frame(&mut self) {
        self.pressed_this_frame.clear();
        self.clicked_this_frame.clear();
        self.mouse_delta = Vec2::ZERO;
        self.wheel_delta = 0.0;
        self.gamepad_pressed_this_frame.clear();
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
