//! Post-processing pipeline: offscreen render targets + fullscreen
//! edge-detection / saturation / color-grading pass.
//!
//! The scene renders to an offscreen color texture + normal texture +
//! depth texture. A fullscreen triangle pass then samples all three,
//! applies Sobel edge detection (depth + normal discontinuities),
//! material-tinted outlines, saturation boost, and dreamy color grading,
//! writing the result to the swapchain.

use wgpu::util::DeviceExt;
use glam::Vec3;

use crate::gpu::{DEPTH_FORMAT, Gpu};

/// Offscreen texture format for the color buffer. High precision for
/// post-processing headroom.
pub const COLOR_FORMAT: wgpu::TextureFormat = wgpu::TextureFormat::Rgba16Float;
/// Offscreen texture format for the normal buffer.
pub const NORMAL_FORMAT: wgpu::TextureFormat = wgpu::TextureFormat::Rgba8Unorm;
/// Offscreen texture format for the linear depth copy (Rgba16Float color
/// texture, used for edge detection — sampled as texture_2d<f32>).
pub const DEPTH_COPY_FORMAT: wgpu::TextureFormat = wgpu::TextureFormat::Rgba16Float;

#[repr(C)]
#[derive(Copy, Clone, bytemuck::Pod, bytemuck::Zeroable)]
struct ParamsUniform {
    resolution: [f32; 2],
    texel_size: [f32; 2],
    cam_pos: [f32; 4],          // xyz + _pad0
    cam_forward: [f32; 4],      // xyz + _pad1
    cam_right: [f32; 4],        // xyz + _pad2
    cam_up_tan: [f32; 4],       // xyz + tan_half_fov
    aspect_zfar: [f32; 4],      // aspect + z_far + _pad3 + _pad4
    _trailing: [f32; 4],        // _pad5 + struct-align padding (112 total)
}

/// Owns the offscreen textures, the post-process pipeline, and the
/// fullscreen bindings. Call `resize` when the window size changes.
pub struct PostProcessPipeline {
    pipeline: wgpu::RenderPipeline,
    bind_group: wgpu::BindGroup,
    params_buf: wgpu::Buffer,
    color_tex: wgpu::TextureView,
    normal_tex: wgpu::TextureView,
    depth_copy_tex: wgpu::TextureView,
    depth_tex: wgpu::TextureView,
    sampler: wgpu::Sampler,
    width: u32,
    height: u32,
    // Camera basis for SSR world-position reconstruction.
    cam_pos: Vec3,
    cam_forward: Vec3,
    cam_right: Vec3,
    cam_up: Vec3,
    tan_half_fov: f32,
    aspect: f32,
}

impl PostProcessPipeline {
    /// Create the pipeline and offscreen textures at the given size.
    pub fn new(gpu: &Gpu, shader_source: &str, width: u32, height: u32) -> Self {
        let device = gpu.device();

        // --- Offscreen textures ---
        let color_tex = create_color_texture(device, width, height, COLOR_FORMAT);
        let normal_tex = create_color_texture(device, width, height, NORMAL_FORMAT);
        let depth_copy_tex = create_color_texture(device, width, height, DEPTH_COPY_FORMAT);
        let depth_tex = create_depth_texture_view(device, width, height);
        // --- Sampler ---
        let sampler = device.create_sampler(&wgpu::SamplerDescriptor {
            label: Some("postprocess-sampler"),
            address_mode_u: wgpu::AddressMode::ClampToEdge,
            address_mode_v: wgpu::AddressMode::ClampToEdge,
            address_mode_w: wgpu::AddressMode::ClampToEdge,
            mag_filter: wgpu::FilterMode::Linear,
            min_filter: wgpu::FilterMode::Linear,
            ..Default::default()
        });


        let params = ParamsUniform {
            resolution: [width as f32, height as f32],
            texel_size: [1.0 / width.max(1) as f32, 1.0 / height.max(1) as f32],
            cam_pos: [0.0, 0.0, 0.0, 0.0],
            cam_forward: [0.0, 0.0, 0.0, 0.0],
            cam_right: [0.0, 0.0, 0.0, 0.0],
            cam_up_tan: [0.0, 0.0, 0.0, 0.0],
            aspect_zfar: [1.0, 600.0, 0.0, 0.0],
            _trailing: [0.0; 4],
        };
        let params_buf = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("postprocess-params"),
            contents: bytemuck::bytes_of(&params),
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        });
        // --- Shader ---
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("postprocess-shader"),
            source: wgpu::ShaderSource::Wgsl(shader_source.into()),
        });

        // --- Bind group layout ---
        let bind_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("postprocess-bind-layout"),
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::FRAGMENT,
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
                    ty: wgpu::BindingType::Texture {
                        sample_type: wgpu::TextureSampleType::Float { filterable: true },
                        view_dimension: wgpu::TextureViewDimension::D2,
                        multisampled: false,
                    },
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
                wgpu::BindGroupLayoutEntry {
                    binding: 3,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Texture {
                        sample_type: wgpu::TextureSampleType::Float { filterable: true },
                        view_dimension: wgpu::TextureViewDimension::D2,
                        multisampled: false,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 4,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering),
                    count: None,
                },
            ],
        });

        let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("postprocess-bind"),
            layout: &bind_layout,
            entries: &[
                wgpu::BindGroupEntry { binding: 0, resource: params_buf.as_entire_binding() },
                wgpu::BindGroupEntry { binding: 1, resource: wgpu::BindingResource::TextureView(&color_tex) },
                wgpu::BindGroupEntry { binding: 2, resource: wgpu::BindingResource::TextureView(&depth_copy_tex) },
                wgpu::BindGroupEntry { binding: 3, resource: wgpu::BindingResource::TextureView(&normal_tex) },
                wgpu::BindGroupEntry { binding: 4, resource: wgpu::BindingResource::Sampler(&sampler) },

            ],
        });

        // --- Pipeline layout ---
        let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("postprocess-pipeline-layout"),
            bind_group_layouts: &[&bind_layout],
            push_constant_ranges: &[],
        });

        // --- Render pipeline (fullscreen triangle, no vertex buffer) ---
        let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("postprocess-pipeline"),
            layout: Some(&pipeline_layout),
            vertex: wgpu::VertexState {
                module: &shader,
                entry_point: "vs",
                buffers: &[],
                compilation_options: Default::default(),
            },
            fragment: Some(wgpu::FragmentState {
                module: &shader,
                entry_point: "fs",
                targets: &[Some(wgpu::ColorTargetState {
                    format: gpu.surface_format(),
                    blend: Some(wgpu::BlendState::REPLACE),
                    write_mask: wgpu::ColorWrites::ALL,
                })],
                compilation_options: Default::default(),
            }),
            primitive: wgpu::PrimitiveState {
                topology: wgpu::PrimitiveTopology::TriangleList,
                ..Default::default()
            },
            depth_stencil: None,
            multisample: wgpu::MultisampleState::default(),
            multiview: None,
        });

        Self {
            pipeline,
            bind_group,
            params_buf,
            color_tex,
            normal_tex,
            depth_copy_tex,
            depth_tex,
            sampler,
            width,
            height,
            cam_pos: Vec3::ZERO,
            cam_forward: Vec3::NEG_Z,
            cam_right: Vec3::X,
            cam_up: Vec3::Y,
            tan_half_fov: (70.0f32.to_radians() * 0.5).tan(),
            aspect: width as f32 / height.max(1) as f32,
        }
    }

    /// Resize the offscreen textures. Call when the window size changes.
    pub fn resize(&mut self, gpu: &Gpu, width: u32, height: u32) {
        if width == self.width && height == self.height {
            return;
        }
        self.width = width;
        self.height = height;
        self.color_tex = create_color_texture(gpu.device(), width, height, COLOR_FORMAT);
        self.normal_tex = create_color_texture(gpu.device(), width, height, NORMAL_FORMAT);
        self.depth_copy_tex = create_color_texture(gpu.device(), width, height, DEPTH_COPY_FORMAT);
        self.depth_tex = create_depth_texture_view(gpu.device(), width, height);
        // Update params uniform — preserve camera basis, update aspect.
        self.aspect = width as f32 / height.max(1) as f32;
        let params = self.build_params(width, height);
        gpu.queue().write_buffer(&self.params_buf, 0, bytemuck::bytes_of(&params));

        // Recreate bind group with new textures.
        self.bind_group = gpu.device().create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("postprocess-bind-resized"),
            layout: &self.pipeline.get_bind_group_layout(0),
            entries: &[
                wgpu::BindGroupEntry { binding: 0, resource: self.params_buf.as_entire_binding() },
                wgpu::BindGroupEntry { binding: 1, resource: wgpu::BindingResource::TextureView(&self.color_tex) },
                wgpu::BindGroupEntry { binding: 2, resource: wgpu::BindingResource::TextureView(&self.depth_copy_tex) },
                wgpu::BindGroupEntry { binding: 3, resource: wgpu::BindingResource::TextureView(&self.normal_tex) },
                wgpu::BindGroupEntry { binding: 4, resource: wgpu::BindingResource::Sampler(&self.sampler) },
            ],
        });
    }

    /// Build the params uniform from current camera state + resolution.
    fn build_params(&self, width: u32, height: u32) -> ParamsUniform {
        ParamsUniform {
            resolution: [width as f32, height as f32],
            texel_size: [1.0 / width.max(1) as f32, 1.0 / height.max(1) as f32],
            cam_pos: [self.cam_pos.x, self.cam_pos.y, self.cam_pos.z, 0.0],
            cam_forward: [self.cam_forward.x, self.cam_forward.y, self.cam_forward.z, 0.0],
            cam_right: [self.cam_right.x, self.cam_right.y, self.cam_right.z, 0.0],
            cam_up_tan: [self.cam_up.x, self.cam_up.y, self.cam_up.z, self.tan_half_fov],
            aspect_zfar: [self.aspect, 600.0, 0.0, 0.0],
            _trailing: [0.0; 4],
        }
    }

    /// Update camera basis for SSR. Call once per frame before drawing.
    /// `cam_pos`, `cam_forward`, `cam_right`, `cam_up` are world-space
    /// unit vectors; `tan_half_fov` is tan(fov_y/2); `aspect` is w/h.
    pub fn update_camera(
        &mut self,
        gpu: &Gpu,
        cam_pos: Vec3,
        cam_forward: Vec3,
        cam_right: Vec3,
        cam_up: Vec3,
        tan_half_fov: f32,
        aspect: f32,
    ) {
        self.cam_pos = cam_pos;
        self.cam_forward = cam_forward;
        self.cam_right = cam_right;
        self.cam_up = cam_up;
        self.tan_half_fov = tan_half_fov;
        self.aspect = aspect;
        let params = self.build_params(self.width, self.height);
        gpu.queue().write_buffer(&self.params_buf, 0, bytemuck::bytes_of(&params));
    }

    /// The offscreen color texture view (scene renders here).
    pub fn color_view(&self) -> &wgpu::TextureView {
        &self.color_tex
    }

    /// The offscreen normal texture view (scene renders normals here).
    pub fn normal_view(&self) -> &wgpu::TextureView {
        &self.normal_tex
    }


    /// The offscreen linear depth copy view (scene outputs depth here).
    pub fn depth_copy_view(&self) -> &wgpu::TextureView {
        &self.depth_copy_tex
    }
    /// The offscreen depth texture view (scene depth-tests here).
    pub fn depth_view(&self) -> &wgpu::TextureView {
        &self.depth_tex
    }

    /// Draw the fullscreen post-process pass into the given target view
    /// (the swapchain frame).
    pub fn draw<'a>(&'a self, pass: &mut wgpu::RenderPass<'a>) {
        pass.set_pipeline(&self.pipeline);
        pass.set_bind_group(0, &self.bind_group, &[]);
        pass.draw(0..3, 0..1);
    }

    /// Run the post-process fullscreen pass into `target_view` (the
    /// swapchain frame). Call after the scene render pass has completed
    /// (the encoder must still be open, but the scene pass must be dropped).
    pub fn process(&self, encoder: &mut wgpu::CommandEncoder, target_view: &wgpu::TextureView) {
        let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("postprocess-pass"),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: target_view,
                resolve_target: None,
                ops: wgpu::Operations {
                    load: wgpu::LoadOp::Clear(wgpu::Color::BLACK),
                    store: wgpu::StoreOp::Store,
                },
            })],
            depth_stencil_attachment: None,
            timestamp_writes: None,
            occlusion_query_set: None,
        });
        self.draw(&mut pass);
    }
}

fn create_color_texture(device: &wgpu::Device, width: u32, height: u32, format: wgpu::TextureFormat) -> wgpu::TextureView {
    let tex = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("offscreen-color"),
        size: wgpu::Extent3d { width, height, depth_or_array_layers: 1 },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format,
        usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING,
        view_formats: &[],
    });
    tex.create_view(&wgpu::TextureViewDescriptor::default())
}

fn create_depth_texture_view(device: &wgpu::Device, width: u32, height: u32) -> wgpu::TextureView {
    let tex = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("offscreen-depth"),
        size: wgpu::Extent3d { width, height, depth_or_array_layers: 1 },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: DEPTH_FORMAT,
        usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING,
        view_formats: &[],
    });
    tex.create_view(&wgpu::TextureViewDescriptor::default())
}
