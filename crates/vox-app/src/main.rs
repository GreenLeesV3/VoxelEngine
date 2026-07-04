//! Voxel engine application entry point: window, GPU clear, frame loop.

use std::sync::Arc;

use vox_platform::{App, FrameControl, FrameTiming, InputState, run_app};
use vox_render::{Gpu, RenderError};
use winit::keyboard::KeyCode;
use winit::window::Window;

/// Sky-blue clear color (linear-space RGBA).
const CLEAR_COLOR: wgpu::Color = wgpu::Color {
    r: 0.45,
    g: 0.66,
    b: 0.90,
    a: 1.0,
};

/// The engine application: currently clears the screen to sky blue.
struct VoxApp {
    gpu: Gpu,
}

impl VoxApp {
    fn new(window: Arc<Window>) -> Result<Self, RenderError> {
        let size = window.inner_size();
        let gpu = Gpu::new(window, size.width, size.height)?;
        Ok(Self { gpu })
    }
}

impl App for VoxApp {
    fn frame(&mut self, input: &mut InputState, _timing: FrameTiming) -> FrameControl {
        if input.key_pressed(KeyCode::Escape) {
            return FrameControl::Exit;
        }

        let frame = match self.gpu.begin_frame() {
            Ok(frame) => frame,
            Err(err) if err.is_transient() => {
                // Lost/Outdated surfaces were already reconfigured inside
                // begin_frame; just skip this frame.
                tracing::warn!(error = %err, "transient surface error; skipping frame");
                return FrameControl::Continue;
            }
            Err(err) => {
                tracing::error!(error = %err, "fatal render error; shutting down");
                return FrameControl::Exit;
            }
        };

        let mut encoder =
            self.gpu
                .device()
                .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                    label: Some("frame-encoder"),
                });
        {
            let _pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("clear-pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: frame.view(),
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(CLEAR_COLOR),
                        store: wgpu::StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: Some(wgpu::RenderPassDepthStencilAttachment {
                    view: self.gpu.depth_view(),
                    depth_ops: Some(wgpu::Operations {
                        load: wgpu::LoadOp::Clear(1.0),
                        store: wgpu::StoreOp::Store,
                    }),
                    stencil_ops: None,
                }),
                timestamp_writes: None,
                occlusion_query_set: None,
            });
        }
        self.gpu.queue().submit([encoder.finish()]);
        frame.present();
        FrameControl::Continue
    }

    fn resize(&mut self, width: u32, height: u32) {
        self.gpu.resize(width, height);
    }

    fn window_event(&mut self, _event: &winit::event::WindowEvent) -> bool {
        false
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info")),
        )
        .init();

    run_app(vox_core::consts::PHYSICS_DT, |window| {
        Ok(Box::new(VoxApp::new(window)?))
    })?;
    Ok(())
}
