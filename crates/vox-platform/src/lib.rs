//! Windowing, input, and platform integration via winit.
//!
//! [`run_app`] owns the window, the event loop, the [`FrameClock`], and the
//! [`InputState`]; the application supplies an [`App`] implementation built
//! from the window (builder pattern, because GPU setup needs the window
//! before the loop starts). The fixed timestep is injected by the caller so
//! this crate stays independent of vox-core.
//!
//! The platform never interprets gameplay input: all keys (including
//! Escape) flow through [`App::window_event`] and [`InputState`]; the app
//! requests shutdown by returning [`FrameControl::Exit`] from
//! [`App::frame`].

pub mod input;
pub mod time;

pub use input::{GamepadButton, InputState};
pub use time::{FrameClock, FrameTiming};

use std::sync::Arc;

use winit::dpi::LogicalSize;
use winit::event::{Event, WindowEvent};
use winit::event_loop::{ControlFlow, EventLoop};
use winit::window::{Window, WindowBuilder};

/// Environment variable for mechanized smoke testing: when set to a frame
/// count `N >= 1`, the loop exits cleanly after presenting `N` frames.
/// Zero or non-numeric values are rejected with a warning and disable the
/// hook.
pub const SMOKE_FRAMES_ENV: &str = "VOX_SMOKE_FRAMES";

/// Initial window inner size in logical pixels.
const WINDOW_SIZE: (f64, f64) = (1600.0, 900.0);

/// Returned by [`App::frame`] to tell the platform loop whether to keep
/// running.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[must_use]
pub enum FrameControl {
    /// Keep running.
    Continue,
    /// Exit the event loop cleanly.
    Exit,
}

/// Application callbacks driven by the platform loop.
pub trait App {
    /// Called once per rendered frame after input has been gathered.
    /// Return [`FrameControl::Exit`] to shut the loop down cleanly.
    fn frame(&mut self, input: &mut InputState, timing: FrameTiming) -> FrameControl;

    /// Called when the window's inner size changes (physical pixels).
    /// Never called with a zero-sized area (minimization is handled by the
    /// platform loop).
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
    AppBuild(Box<dyn std::error::Error + Send + Sync>),
}

/// Create the window, build the app, and run the event loop until exit.
///
/// * `fixed_dt` — fixed physics timestep in seconds, forwarded to the
///   [`FrameClock`].
/// * `build` — constructs the [`App`] from the shared window handle before
///   the loop starts (e.g. to create the GPU surface).
///
/// The loop exits on window close, when the app returns
/// [`FrameControl::Exit`], or — when the [`SMOKE_FRAMES_ENV`] variable is
/// set — after the requested number of frames.
///
/// While the window is minimized (zero-sized), no frames run and the loop
/// waits on OS events instead of polling: presenting to a zero-sized
/// surface is impossible, and attempting it busy-spins on surface errors.
pub fn run_app(
    fixed_dt: f32,
    build: impl FnOnce(Arc<Window>) -> Result<Box<dyn App>, Box<dyn std::error::Error + Send + Sync>>,
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
    let mut gilrs = gilrs::Gilrs::new().ok();
    if gilrs.is_none() {
        tracing::warn!("Gamepad support unavailable (gilrs init failed) — keyboard/mouse only");
    }
    let mut clock = FrameClock::new(fixed_dt);

    let smoke_frames = read_smoke_frames();
    let mut frames_presented: u64 = 0;
    let mut minimized = false;

    event_loop.run(move |event, elwt| {
        // Game loop: render continuously — except while minimized, where
        // there is nothing to present and we park until the next OS event.
        elwt.set_control_flow(if minimized {
            ControlFlow::Wait
        } else {
            ControlFlow::Poll
        });

        match event {
            Event::WindowEvent { window_id, event } if window_id == window.id() => match event {
                WindowEvent::CloseRequested => elwt.exit(),
                WindowEvent::Resized(size) => {
                    let was_minimized = minimized;
                    minimized = size.width == 0 || size.height == 0;
                    if !minimized {
                        if was_minimized {
                            // Clear per-frame deltas accumulated while
                            // minimized — RedrawRequested early-returns
                            // before `input.end_frame()` during that
                            // span, so MouseMotion/wheel deltas would
                            // otherwise carry into the first restored
                            // frame as a huge jump.
                            input.mouse_delta = glam::Vec2::ZERO;
                            input.wheel_delta = 0.0;
                        }
                        app.resize(size.width, size.height);
                    }
                }
                WindowEvent::RedrawRequested => {
                    if minimized {
                        return;
                    }
                let timing = clock.tick();
                if let Some(g) = &mut gilrs {
                    input.poll_gamepad(g);
                }
                let control = app.frame(&mut input, timing);
                    input.end_frame();
                    if control == FrameControl::Exit {
                        elwt.exit();
                    }

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
            Event::AboutToWait => {
                if !minimized {
                    window.request_redraw();
                }
            }
            _ => {}
        }
    })?;

    Ok(())
}

/// Read [`SMOKE_FRAMES_ENV`] once at startup. Unset, zero, or invalid
/// values disable the smoke-exit hook.
fn read_smoke_frames() -> Option<u64> {
    let raw = std::env::var(SMOKE_FRAMES_ENV).ok()?;
    match raw.trim().parse::<u64>() {
        Ok(0) => {
            tracing::warn!("{SMOKE_FRAMES_ENV}=0 is invalid (must be >= 1); ignoring");
            None
        }
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
