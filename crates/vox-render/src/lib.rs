//! wgpu-based renderer for voxel meshes.
//!
//! Currently provides GPU bootstrap and per-frame surface acquisition
//! ([`Gpu`], [`Frame`]); mesh rendering arrives in later milestones. This
//! crate deliberately has no winit dependency: window types enter only as
//! [`wgpu::SurfaceTarget`].

pub mod gpu;

pub use gpu::{DEPTH_FORMAT, Frame, Gpu};

/// Errors from GPU initialization and per-frame surface operations.
#[derive(Debug, thiserror::Error)]
pub enum RenderError {
    /// No surface-compatible adapter was found on any backend. Usually
    /// means missing/broken GPU drivers.
    #[error(
        "no compatible GPU adapter found (searched all backends for a surface-compatible adapter)"
    )]
    NoAdapter,
    /// The window could not be turned into a rendering surface.
    #[error("failed to create rendering surface from window: {0}")]
    CreateSurface(#[from] wgpu::CreateSurfaceError),
    /// The adapter refused the device request (features/limits mismatch or
    /// driver loss during init).
    #[error("failed to acquire GPU device from adapter: {0}")]
    RequestDevice(#[from] wgpu::RequestDeviceError),
    /// The surface reports no usable texture formats for this adapter.
    #[error("surface reports no supported texture formats for the selected adapter")]
    NoSurfaceFormat,
    /// Acquiring the next swapchain frame failed; the frame should be
    /// skipped (the surface is reconfigured internally when recoverable).
    #[error("failed to acquire frame from surface: {0}")]
    AcquireFrame(#[from] wgpu::SurfaceError),
}
