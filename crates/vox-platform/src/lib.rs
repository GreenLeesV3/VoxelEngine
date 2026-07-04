//! Windowing, input, and platform integration via winit.
//!
//! [`run_app`] owns the window, the event loop, the [`FrameClock`], and the
//! [`InputState`]; the application supplies an [`App`] implementation built
//! from the window (builder pattern, because GPU setup needs the window
//! before the loop starts). The fixed timestep is injected by the caller so
//! this crate stays independent of vox-core.

pub mod input;
pub mod time;

pub use input::InputState;
pub use time::{FrameClock, FrameTiming};

use std::sync::Arc;

use winit::dpi::LogicalSize;
use winit::event::{ElementState, Event, KeyEvent, WindowEvent};
use winit::event_loop::{ControlFlow, EventLoop};
use winit::keyboard::{KeyCode, PhysicalKey};
use winit::window::{Window, WindowBuilder};

/// Environment variable for mechanized smoke testing: when set to a frame
/// count `N`, the loop exits cleanly after presenting `N` frames.
pub const SMOKE_FRAMES_ENV: &str = "VOX_SMOKE_FRAMES";

/// Initial window inner size in logical pixels.
const WINDOW_SIZE: (f64, f64) = (1600.0, 900.0);

/// Application callbacks driven by the platform loop.
pub trait App {
    /// Called once per rendered frame after input has been gathered.
    fn frame(&mut self, input: &mut InputState, timing: FrameTiming);

    /// Called when the window's inner size changes (physical pixels).
    fn resize(&mut self, width: u32, height: u32);

    /// Raw window event hook, called before the platform input state sees
    /// the event. Return true if the event was consumed (e.g. by a UI
    /// overlay later).
    fn window_event(&mut self, event: &winit::event::WindowEvent) -> bool;
}

/// Errors from window/event-loop setup and execution.
#[derive(Debug, thiserror::Error)]
pub enum PlatformError {
    /// The winit event loop could not be created or exited abnormally.
    #[error("event loop error: {0}")]
    EventLoop(#[from] winit::error::EventLoopError),
    /// The OS refused to create the window.
    #[error("failed to create window: {0}")]
    Window(#[from] winit::error::OsError),
    /// The application builder passed to [`run_app`] failed.
    #[error("failed to build app: {0}")]
    AppBuild(Box<dyn std::error::Error>),
}

/// Create the window, build the app, and run the event loop until exit.
///
/// * `fixed_dt` — fixed physics timestep in seconds, forwarded to the
///   [`FrameClock`].
/// * `build` — constructs the [`App`] from the shared window handle before
///   the loop starts (e.g. to create the GPU surface).
///
/// The loop exits on window close, the Escape key, or — when the
/// [`SMOKE_FRAMES_ENV`] variable is set — after the requested number of
/// frames.
pub fn run_app(
    fixed_dt: f32,
    build: impl FnOnce(Arc<Window>) -> Result<Box<dyn App>, Box<dyn std::error::Error>>,
) -> Result<(), PlatformError> {
    let event_loop = EventLoop::new()?;
    let window = Arc::new(
        WindowBuilder::new()
            .with_title("voxelengine")
            .with_inner_size(LogicalSize::new(WINDOW_SIZE.0, WINDOW_SIZE.1))
            .build(&event_loop)?,
    );

    let mut app = build(Arc::clone(&window)).map_err(PlatformError::AppBuild)?;
    let mut input = InputState::new();
    let mut clock = FrameClock::new(fixed_dt);

    let smoke_frames = read_smoke_frames();
    let mut frames_presented: u64 = 0;

    event_loop.run(move |event, elwt| {
        // Game loop: render continuously instead of waiting for OS events.
        elwt.set_control_flow(ControlFlow::Poll);

        match event {
            Event::WindowEvent { window_id, event } if window_id == window.id() => match event {
                WindowEvent::CloseRequested => elwt.exit(),
                WindowEvent::KeyboardInput {
                    event:
                        KeyEvent {
                            physical_key: PhysicalKey::Code(KeyCode::Escape),
                            state: ElementState::Pressed,
                            ..
                        },
                    ..
                } => elwt.exit(),
                WindowEvent::Resized(size) => app.resize(size.width, size.height),
                WindowEvent::RedrawRequested => {
                    let timing = clock.tick();
                    app.frame(&mut input, timing);
                    input.end_frame();

                    frames_presented += 1;
                    if smoke_frames.is_some_and(|n| frames_presented >= n) {
                        tracing::info!(
                            frames = frames_presented,
                            "smoke-test frame budget reached; exiting"
                        );
                        elwt.exit();
                    }
                }
                other => {
                    if !app.window_event(&other) {
                        input.handle_window_event(&other);
                    }
                }
            },
            Event::DeviceEvent { event, .. } => input.handle_device_event(&event),
            Event::AboutToWait => window.request_redraw(),
            _ => {}
        }
    })?;

    Ok(())
}

/// Read [`SMOKE_FRAMES_ENV`] once at startup. Unset or invalid values
/// disable the smoke-exit hook.
fn read_smoke_frames() -> Option<u64> {
    let raw = std::env::var(SMOKE_FRAMES_ENV).ok()?;
    match raw.trim().parse::<u64>() {
        Ok(frames) => {
            tracing::info!(frames, "smoke-test mode: will exit after N frames");
            Some(frames)
        }
        Err(err) => {
            tracing::warn!(value = %raw, %err, "ignoring invalid {SMOKE_FRAMES_ENV}");
            None
        }
    }
}
