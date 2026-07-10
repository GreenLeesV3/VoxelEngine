//! GPU side of the particle system: instanced camera-facing quads with a
//! soft circular sprite, alpha-blended, depth-tested against the world but
//! never depth-written.
//!
//! This crate only draws; simulation (spawning, gravity, lifetimes, fading)
//! lives with the app, which hands over a flat [`ParticleInstance`] slice
//! once a frame. One persistent instance buffer sized for
//! [`MAX_PARTICLES`] is reused every frame -- a single `write_buffer` per
//! frame, no per-frame allocation or buffer churn.

use bytemuck::{Pod, Zeroable};
use glam::{Mat4, Vec3};
use wgpu::util::DeviceExt;

use crate::gpu::{DEPTH_FORMAT, Gpu};

/// Hard cap on live particles, mirrored by the app-side simulation. Sized
/// for rich smoke that fills rooms: 16384 quads is ~98k vertices of trivially
/// cheap fragment work, well within any modern GPU's budget. The app-side
/// spatial hash and world-collision checks stay cheap at this count.
pub const MAX_PARTICLES: usize = 16384;

/// One particle, as the GPU sees it. The app's simulation state (velocity,
/// age, ...) never crosses the boundary; only where/how-big/what-color.
#[repr(C)]
#[derive(Copy, Clone, Pod, Zeroable)]
pub struct ParticleInstance {
    /// xyz = world center (m), w = half-size (m).
    pub center_size: [f32; 4],
    /// Straight (non-premultiplied) rgba; alpha carries the fade.
    pub color: [f32; 4],
}

#[repr(C)]
#[derive(Copy, Clone, Pod, Zeroable)]
struct CameraUniform {
    view_proj: [[f32; 4]; 4],
    right: [f32; 4],
    up: [f32; 4],
}

/// Depth over which a particle fades to zero alpha when it intersects
/// terrain, in normalized device coordinates (0..1). A particle fragment
/// whose depth is within this range *behind* the scene depth is faded out
/// smoothly instead of hard-cutting at the depth boundary. The value is
/// consumed by the WGSL shader (particle.wgsl `SOFT_FADE_RANGE`); this
/// constant exists as a documented mirror.
const _SOFT_FADE_RANGE: f32 = 0.02;

/// Pipeline + persistent buffers for particle drawing.
pub struct ParticlePipeline {
    pipeline: wgpu::RenderPipeline,
    camera_buf: wgpu::Buffer,
    bgl: wgpu::BindGroupLayout,
    bind_group: wgpu::BindGroup,
    instances: wgpu::Buffer,
    count: u32,
}

impl ParticlePipeline {
    pub fn new(gpu: &Gpu, shader_source: &str) -> Self {
        let device = gpu.device();
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("particle shader"),
            source: wgpu::ShaderSource::Wgsl(shader_source.into()),
        });

        let camera_buf = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("particle camera uniform"),
            size: std::mem::size_of::<CameraUniform>() as u64,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        // No sampler needed — the fragment shader uses textureLoad on the
        // depth texture (exact pixel read, no filtering), which avoids the
        // sampler binding entirely and is correct for Depth32Float.
        let bgl = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("particle bind group layout"),
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::VERTEX,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Uniform,
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                // Scene depth texture — read in the fragment shader via
                // textureLoad for both the behind-terrain test and the
                // soft-particle surface fade. Depth32Float is non-
                // filterable, so the sample type must be Depth.
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Texture {
                        sample_type: wgpu::TextureSampleType::Depth,
                        view_dimension: wgpu::TextureViewDimension::D2,
                        multisampled: false,
                    },
                    count: None,
                },
            ],
        });

        let layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("particle pipeline layout"),
            bind_group_layouts: &[&bgl],
            push_constant_ranges: &[],
        });
        let instance_layout = wgpu::VertexBufferLayout {
            array_stride: std::mem::size_of::<ParticleInstance>() as u64,
            step_mode: wgpu::VertexStepMode::Instance,
            attributes: &[
                wgpu::VertexAttribute {
                    format: wgpu::VertexFormat::Float32x4,
                    offset: 0,
                    shader_location: 0,
                },
                wgpu::VertexAttribute {
                    format: wgpu::VertexFormat::Float32x4,
                    offset: 16,
                    shader_location: 1,
                },
            ],
        };

        let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("particle pipeline"),
            layout: Some(&layout),
            vertex: wgpu::VertexState {
                module: &shader,
                entry_point: "vs",
                compilation_options: Default::default(),
                buffers: &[instance_layout],
            },
            fragment: Some(wgpu::FragmentState {
                module: &shader,
                entry_point: "fs",
                compilation_options: Default::default(),
                targets: &[Some(wgpu::ColorTargetState {
                    format: crate::postprocess::COLOR_FORMAT,
                    blend: Some(wgpu::BlendState::ALPHA_BLENDING),
                    write_mask: wgpu::ColorWrites::ALL,
                })],
            }),
            primitive: wgpu::PrimitiveState {
                topology: wgpu::PrimitiveTopology::TriangleList,
                // Billboards always face the camera; culling buys nothing.
                cull_mode: None,
                ..Default::default()
            },
            // No depth_stencil: the particle render pass does not attach
            // depth (the depth texture is bound as a sampled resource
            // instead). The fragment shader performs both the behind-
            // terrain test and the soft fade via textureLoad on the
            // bound scene depth — see particle.wgsl fs().
            depth_stencil: None,
            multisample: Default::default(),
            multiview: None,
        });

        let instances = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("particle instances"),
            contents: &vec![0u8; MAX_PARTICLES * std::mem::size_of::<ParticleInstance>()],
            usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
        });

        // Placeholder bind group with a 1x1 dummy depth view — the real one
        // is set by `set_depth_view` before the first frame.
        let dummy_depth = device.create_texture(&wgpu::TextureDescriptor {
            label: Some("particle-dummy-depth"),
            size: wgpu::Extent3d { width: 1, height: 1, depth_or_array_layers: 1 },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: DEPTH_FORMAT,
            usage: wgpu::TextureUsages::TEXTURE_BINDING,
            view_formats: &[],
        });
        let dummy_depth_view = dummy_depth.create_view(&wgpu::TextureViewDescriptor::default());
        let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("particle bind group"),
            layout: &bgl,
            entries: &[
                wgpu::BindGroupEntry { binding: 0, resource: camera_buf.as_entire_binding() },
                wgpu::BindGroupEntry { binding: 1, resource: wgpu::BindingResource::TextureView(&dummy_depth_view) },
            ],
        });

        Self {
            pipeline,
            camera_buf,
            bgl,
            bind_group,
            instances,
            count: 0,
        }
    }

    /// Update the camera uniform. `right`/`up` are the camera's world-space
    /// basis vectors the billboards align to.
    pub fn write_camera(&self, gpu: &Gpu, view_proj: Mat4, right: Vec3, up: Vec3) {
        let uniform = CameraUniform {
            view_proj: view_proj.to_cols_array_2d(),
            right: [right.x, right.y, right.z, 0.0],
            up: [up.x, up.y, up.z, 0.0],
        };
        gpu.queue()
            .write_buffer(&self.camera_buf, 0, bytemuck::bytes_of(&uniform));
    }

    /// Recreate the bind group with the scene depth texture view (for soft
    /// particles). Call once after construction and again whenever the
    /// depth texture is recreated (e.g. on resize). The depth view must
    /// have `TEXTURE_BINDING` usage.
    pub fn set_depth_view(&mut self, device: &wgpu::Device, depth_view: &wgpu::TextureView) {
        self.bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("particle bind group"),
            layout: &self.bgl,
            entries: &[
                wgpu::BindGroupEntry { binding: 0, resource: self.camera_buf.as_entire_binding() },
                wgpu::BindGroupEntry { binding: 1, resource: wgpu::BindingResource::TextureView(depth_view) },
            ],
        });
    }

    /// Upload this frame's live particles (anything past [`MAX_PARTICLES`]
    /// is silently dropped; the app-side cap should make that unreachable).
    pub fn upload(&mut self, gpu: &Gpu, particles: &[ParticleInstance]) {
        let n = particles.len().min(MAX_PARTICLES);
        self.count = n as u32;
        if n > 0 {
            gpu.queue()
                .write_buffer(&self.instances, 0, bytemuck::cast_slice(&particles[..n]));
        }
    }

    /// Draw the last-uploaded particles. Call after the opaque world so
    /// depth testing hides particles behind terrain.
    pub fn draw<'p>(&'p self, pass: &mut wgpu::RenderPass<'p>) {
        if self.count == 0 {
            return;
        }
        pass.set_pipeline(&self.pipeline);
        pass.set_bind_group(0, &self.bind_group, &[]);
        pass.set_vertex_buffer(0, self.instances.slice(..));
        pass.draw(0..6, 0..self.count);
    }
}
