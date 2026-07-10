//! Mario render pipeline: renders libsm64's dynamic per-frame geometry.
//!
//! Unlike the voxel pipeline (static chunk meshes + per-body instances),
//! Mario's mesh changes every frame — libsm64 outputs new vertex
//! buffers (position, normal, color, uv) from `sm64_mario_tick` as
//! Mario animates. This pipeline uploads those buffers fresh each frame
//! and draws them textured with Mario's 704×64 atlas.

use bytemuck::{Pod, Zeroable};
use wgpu::util::DeviceExt;

use crate::gpu::{DEPTH_FORMAT, Gpu};

/// Camera + environment uniform, must match `mario.wgsl`.
/// Shares the same lighting fields as the voxel pipeline's CameraUniform
/// for consistent day/night rendering.
#[repr(C)]
#[derive(Copy, Clone, Pod, Zeroable)]
pub struct MarioCameraUniform {
    pub view_proj: [[f32; 4]; 4],
    pub cam_pos: [f32; 4],
    pub sun_dir: [f32; 4],
    pub fog: [f32; 4],
    pub interp_pos: [f32; 4],
    pub tick_pos: [f32; 4],
    /// Day/night lighting — must match voxel pipeline CameraUniform.
    pub sky_color: [f32; 4],
    pub sun_color: [f32; 4],
    pub ambient_sky: [f32; 4],
    pub ambient_ground: [f32; 4],
}

/// Mario vertex: position + normal + color + uv, matching `mario.wgsl`.
/// libsm64 outputs these as separate float arrays; we interleave them
/// into this single vertex type for the GPU upload.
#[repr(C)]
#[derive(Copy, Clone, Pod, Zeroable, Debug)]
pub struct MarioVertex {
    pub position: [f32; 3],
    pub normal: [f32; 3],
    pub color: [f32; 3],
    pub uv: [f32; 2],
}

/// The Mario render pipeline: shader, bind group (camera + sampler +
/// texture), and dynamic vertex/index buffers rewritten each frame.
#[allow(dead_code)] // sampler/texture/texture_view are held alive for the bind group
pub struct MarioPipeline {
    pipeline: wgpu::RenderPipeline,
    camera_buf: wgpu::Buffer,
    bind_group: wgpu::BindGroup,
    sampler: wgpu::Sampler,
    texture: wgpu::Texture,
    texture_view: wgpu::TextureView,
    vertex_buf: wgpu::Buffer,
    index_buf: wgpu::Buffer,
    /// Geometry version stamp of the vertex data currently in
    /// `vertex_buf`. Compared against `MarioGeometry::version` to skip
    /// the per-frame `write_buffer` when Mario is idle.
    uploaded_version: std::sync::atomic::AtomicU64,
    /// Vertex count currently in `index_buf`. Re-uploading the index
    /// buffer is only needed when the vertex count changes.
    uploaded_vertex_count: std::sync::atomic::AtomicUsize,
}

impl MarioPipeline {
    /// Build the pipeline. `shader_source` is the WGSL text from
    /// `mario.wgsl`. `texture_rgba` is Mario's 704×64 atlas from
    /// `sm64_global_init`. `tex_w`/`tex_h` are its dimensions.
    pub fn new(
        gpu: &Gpu,
        shader_source: &str,
        texture_rgba: &[u8],
        tex_w: u32,
        tex_h: u32,
    ) -> Self {
        let device = gpu.device();
        let format = gpu.surface_format();

        // ── Shaders ───────────────────────────────────────────────
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("mario.wgsl"),
            source: wgpu::ShaderSource::Wgsl(shader_source.into()),
        });

        // ── Camera uniform ────────────────────────────────────────
        let camera_buf = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("mario camera uniform"),
            contents: bytemuck::bytes_of(&MarioCameraUniform::zeroed()),
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        });

        // ── Mario texture atlas ───────────────────────────────────
        let texture = device.create_texture(&wgpu::TextureDescriptor {
            label: Some("mario texture"),
            size: wgpu::Extent3d { width: tex_w, height: tex_h, depth_or_array_layers: 1 },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::Rgba8Unorm,
            usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
            view_formats: &[],
        });
        let texture_view = texture.create_view(&wgpu::TextureViewDescriptor::default());

        gpu.queue().write_texture(
            wgpu::ImageCopyTexture {
                texture: &texture,
                mip_level: 0,
                origin: wgpu::Origin3d::ZERO,
                aspect: wgpu::TextureAspect::All,
            },
            texture_rgba,
            wgpu::ImageDataLayout {
                offset: 0,
                bytes_per_row: Some(tex_w * 4),
                rows_per_image: Some(tex_h),
            },
            wgpu::Extent3d { width: tex_w, height: tex_h, depth_or_array_layers: 1 },
        );

        // ── Sampler ───────────────────────────────────────────────
        let sampler = device.create_sampler(&wgpu::SamplerDescriptor {
            label: Some("mario sampler"),
            address_mode_u: wgpu::AddressMode::ClampToEdge,
            address_mode_v: wgpu::AddressMode::ClampToEdge,
            address_mode_w: wgpu::AddressMode::ClampToEdge,
            mag_filter: wgpu::FilterMode::Linear,
            min_filter: wgpu::FilterMode::Linear,
            mipmap_filter: wgpu::FilterMode::Nearest,
            ..Default::default()
        });

        // ── Bind group ────────────────────────────────────────────
        let bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("mario bind group layout"),
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::VERTEX_FRAGMENT,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Uniform,
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering),
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 2,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Texture {
                        sample_type: wgpu::TextureSampleType::Float { filterable: true },
                        view_dimension: wgpu::TextureViewDimension::D2,
                        multisampled: false,
                    },
                    count: None,
                },
            ],
        });

        let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("mario bind group"),
            layout: &bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: camera_buf.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: wgpu::BindingResource::Sampler(&sampler),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: wgpu::BindingResource::TextureView(&texture_view),
                },
            ],
        });

        // ── Vertex buffers (dynamic, rewritten each frame) ────────
        // Pre-allocate for the max: 1024 triangles × 3 verts = 3072.
        let max_vertices = 1024 * 3;
        let vertex_buf = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("mario vertex buffer"),
            size: (max_vertices * std::mem::size_of::<MarioVertex>()) as u64,
            usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let index_buf = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("mario index buffer"),
            size: (max_vertices * 4) as u64, // u32 per index
            usage: wgpu::BufferUsages::INDEX | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        // ── Pipeline layout ───────────────────────────────────────
        let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("mario pipeline layout"),
            bind_group_layouts: &[&bind_group_layout],
            push_constant_ranges: &[],
        });

        // ── Render pipeline ───────────────────────────────────────
        let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("mario render pipeline"),
            layout: Some(&pipeline_layout),
            vertex: wgpu::VertexState {
                module: &shader,
                entry_point: "vs_main",
                compilation_options: Default::default(),
                buffers: &[wgpu::VertexBufferLayout {
                    array_stride: std::mem::size_of::<MarioVertex>() as u64,
                    step_mode: wgpu::VertexStepMode::Vertex,
                    attributes: &[
                        // position: float3
                        wgpu::VertexAttribute {
                            offset: 0,
                            shader_location: 0,
                            format: wgpu::VertexFormat::Float32x3,
                        },
                        // normal: float3
                        wgpu::VertexAttribute {
                            offset: 12,
                            shader_location: 1,
                            format: wgpu::VertexFormat::Float32x3,
                        },
                        // color: float3
                        wgpu::VertexAttribute {
                            offset: 24,
                            shader_location: 2,
                            format: wgpu::VertexFormat::Float32x3,
                        },
                        // uv: float2
                        wgpu::VertexAttribute {
                            offset: 36,
                            shader_location: 3,
                            format: wgpu::VertexFormat::Float32x2,
                        },
                    ],
                }],
            },
            fragment: Some(wgpu::FragmentState {
                module: &shader,
                entry_point: "fs_main",
                compilation_options: Default::default(),
                targets: &[Some(wgpu::ColorTargetState {
                    format,
                    blend: Some(wgpu::BlendState::REPLACE),
                    write_mask: wgpu::ColorWrites::ALL,
                })],
            }),
            primitive: wgpu::PrimitiveState {
                topology: wgpu::PrimitiveTopology::TriangleList,
                cull_mode: Some(wgpu::Face::Back),
                ..Default::default()
            },
            depth_stencil: Some(wgpu::DepthStencilState {
                format: DEPTH_FORMAT,
                depth_write_enabled: true,
                depth_compare: wgpu::CompareFunction::Less,
                stencil: wgpu::StencilState::default(),
                bias: wgpu::DepthBiasState::default(),
            }),
            multisample: wgpu::MultisampleState::default(),
            multiview: None,
        });

        Self {
            pipeline,
            camera_buf,
            bind_group,
            sampler,
            texture,
            texture_view,
            vertex_buf,
            index_buf,
            uploaded_version: std::sync::atomic::AtomicU64::new(0),
            uploaded_vertex_count: std::sync::atomic::AtomicUsize::new(0),
        }
    }
    /// Update the camera uniform. Call once per frame before drawing.
    pub fn update_camera(&self, queue: &wgpu::Queue, cam: &MarioCameraUniform) {
        queue.write_buffer(&self.camera_buf, 0, bytemuck::bytes_of(cam));
    }

    /// Draw Mario's mesh for this frame.
    ///
    /// `geometry` provides the raw positions, normals, colors, and uvs
    /// from `sm64_mario_tick`. The per-frame translate (interp_pos -
    /// tick_pos) and model scale are applied in the vertex shader using
    /// the camera uniform, so the vertex buffer only needs to change
    /// when the geometry actually changes — not every interpolated
    /// render frame. We compare `geometry.version()` against the last
    /// uploaded version and skip `write_buffer` when unchanged, while
    /// still issuing the draw call with the existing buffer contents.
    pub fn draw<'p>(
        &'p self,
        queue: &wgpu::Queue,
        render_pass: &mut wgpu::RenderPass<'p>,
        geometry: &vox_sm64::MarioGeometry,
    ) {
        let n_verts = geometry.num_vertices();
        if n_verts == 0 {
            return;
        }

        use std::sync::atomic::Ordering;

        // Only re-upload the vertex buffer when the geometry changed
        // this tick (new version stamp). Idle Mario keeps the same
        // mesh, so we skip the CPU->GPU copy entirely.
        let prev_version = self.uploaded_version.load(Ordering::Acquire);
        if prev_version != geometry.version() {
            // Interleave raw SM64 positions/normals/colors/uvs. The
            // shader applies the per-frame translate + scale.
            let mut vertices = Vec::with_capacity(n_verts);
            for i in 0..n_verts {
                vertices.push(MarioVertex {
                    position: geometry.positions[i],
                    normal: geometry.normals[i],
                    color: geometry.colors[i],
                    uv: geometry.uvs[i],
                });
            }
            queue.write_buffer(&self.vertex_buf, 0, bytemuck::cast_slice(&vertices));
            self.uploaded_version
                .store(geometry.version(), Ordering::Release);
        }

        // Sequential index list (0, 1, 2, ...). Only re-upload when the
        // vertex count changed (e.g. a different animation produced more
        // or fewer triangles).
        let prev_vcount = self.uploaded_vertex_count.load(Ordering::Acquire);
        if prev_vcount != n_verts {
            let indices: Vec<u32> = (0..n_verts as u32).collect();
            queue.write_buffer(&self.index_buf, 0, bytemuck::cast_slice(&indices));
            self.uploaded_vertex_count.store(n_verts, Ordering::Release);
        }

        render_pass.set_pipeline(&self.pipeline);
        render_pass.set_bind_group(0, &self.bind_group, &[]);
        render_pass.set_vertex_buffer(0, self.vertex_buf.slice(..));
        render_pass.set_index_buffer(self.index_buf.slice(..), wgpu::IndexFormat::Uint32);
        render_pass.draw_indexed(0..n_verts as u32, 0, 0..1);
    }
}
