//! Voxel engine application: world, player, tools, threaded remeshing, render.

mod player;
mod remesh;
mod tools;

use std::path::PathBuf;
use std::sync::Arc;
use std::time::Instant;

use glam::{IVec3, Mat4, Vec3};
use rayon::prelude::*;

use player::Player;
use remesh::RemeshQueue;
use tools::{Tool, Tools};

use vox_core::consts::CHUNK_SIZE;
use vox_core::{MaterialRegistry, WorldConfig, chunk_origin, voxel_at};
use vox_gen::{TerrainGen, TerrainMaterials, TreeMaterials, generate_trees};
use vox_mesh::{VoxelSlab, mesh_slab};
use vox_physics::{Body, PhysicsWorld, VoxelGrid};
use vox_platform::{App, FrameControl, FrameTiming, InputState, run_app};
use vox_render::{Camera, Frustum, Gpu, VoxelPipeline};
use vox_world::{Voxel, World};
use winit::event::MouseButton;
use winit::keyboard::KeyCode;
use winit::window::{CursorGrabMode, Window};

/// Sky-blue clear color (linear-space RGBA); must match the shader's fog sky.
const CLEAR_COLOR: wgpu::Color = wgpu::Color {
    r: 0.45,
    g: 0.66,
    b: 0.90,
    a: 1.0,
};

/// Fog end distance in meters.
const FOG_END_M: f32 = 220.0;

/// Locate the `assets/` directory: the workspace copy during development,
/// else `assets/` beside the executable.
fn assets_dir() -> PathBuf {
    let dev = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../assets");
    if dev.is_dir() {
        return dev;
    }
    PathBuf::from("assets")
}

/// Build the world: noise terrain + forest from the world config.
fn build_terrain_world(
    registry: &MaterialRegistry,
) -> Result<World, Box<dyn std::error::Error + Send + Sync>> {
    let cfg = WorldConfig {
        voxel_size_m: 0.1,
        extent_m: [128.0, 48.0, 128.0],
        ..WorldConfig::default()
    };
    cfg.validate()?;
    let mut world = World::new(cfg);
    let mats = TerrainMaterials::from_registry(registry)?;
    let terrain = TerrainGen::new(&world.cfg);
    terrain.generate(&mut world, mats);
    let tree_mats = TreeMaterials::from_registry(registry)?;
    let planted = generate_trees(&mut world, &terrain, tree_mats);
    tracing::info!(trees = planted, "forest planted");
    Ok(world)
}

/// The engine application.
struct VoxApp {
    window: Arc<Window>,
    gpu: Gpu,
    pipeline: VoxelPipeline,
    world: World,
    registry: MaterialRegistry,
    player: Player,
    camera: Camera,
    tools: Tools,
    remesh: RemeshQueue,
    phys: PhysicsWorld,
    grabbed: bool,
    frames: u32,
    last_report: Instant,
}

impl VoxApp {
    fn new(window: Arc<Window>) -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        let assets = assets_dir();
        let registry = MaterialRegistry::load_dir(&assets.join("materials"))?;
        let shader = std::fs::read_to_string(assets.join("shaders/voxel.wgsl"))?;

        let build_start = Instant::now();
        let world = build_terrain_world(&registry)?;
        tracing::info!(
            chunks = world.chunk_count(),
            elapsed_ms = build_start.elapsed().as_millis() as u64,
            "world built"
        );

        let size = window.inner_size();
        let gpu = Gpu::new(window.clone(), size.width, size.height)?;
        let pipeline = VoxelPipeline::new(&gpu, &shader, &registry, world.cfg.voxel_size_m);
        let tools = Tools::new(&registry);

        let mut app = Self {
            window,
            gpu,
            pipeline,
            world,
            registry,
            player: Player::new(Vec3::ZERO),
            camera: Camera::new(Vec3::ZERO),
            tools,
            remesh: RemeshQueue::new(),
            phys: PhysicsWorld::new(),
            grabbed: false,
            frames: 0,
            last_report: Instant::now(),
        };
        app.initial_mesh();

        // Spawn on the terrain surface at the world center.
        let center = Vec3::from(app.world.cfg.extent_m) * 0.5;
        let surface = TerrainGen::surface_height_m(&app.world, center.x, center.z)
            .unwrap_or(app.world.cfg.extent_m[1] * 0.5);
        app.player = Player::new(Vec3::new(center.x, surface + 0.2, center.z));
        Ok(app)
    }

    /// Synchronous parallel meshing of the freshly generated world.
    fn initial_mesh(&mut self) {
        let keys = self.world.drain_dirty();
        let _ = self.world.drain_dirty_regions();
        let start = Instant::now();
        let world = &self.world;
        let meshes: Vec<(IVec3, vox_mesh::MeshData)> = keys
            .par_iter()
            .filter(|key| world.chunk_at(**key).is_some())
            .map(|key| {
                let slab =
                    VoxelSlab::extract(world, chunk_origin(*key), IVec3::splat(CHUNK_SIZE as i32));
                (*key, mesh_slab(&slab))
            })
            .collect();
        let meshed = meshes.len();
        let mut quads = 0usize;
        for (key, mesh) in meshes {
            quads += mesh.quads();
            self.pipeline.upload_chunk(&self.gpu, key, &mesh);
        }
        tracing::info!(
            chunks = meshed,
            quads,
            elapsed_ms = start.elapsed().as_millis() as u64,
            "initial world mesh"
        );
    }

    /// Spawn a debris body at `origin_m` (a solid `extent`^3 wood cube),
    /// meshing and uploading it immediately, with `vel_m_s` initial velocity.
    fn spawn_debris(&mut self, origin_m: Vec3, extent: i32, vel_m_s: Vec3) {
        let wood = self
            .registry
            .id_by_name("wood")
            .map(|m| Voxel(m.0))
            .unwrap_or(Voxel(1));
        let dims = IVec3::splat(extent);
        let voxels = vec![wood; (dims.x * dims.y * dims.z) as usize];
        let grid = VoxelGrid::new(dims, voxels.clone());
        let Some(mut body) =
            Body::from_grid(grid, &self.registry, self.world.cfg.voxel_size_m, origin_m)
        else {
            return; // Massless grid (shouldn't happen for a solid cube).
        };
        body.vel = vel_m_s;
        let id = self.phys.spawn(body);

        let slab = VoxelSlab::from_grid(dims, &voxels);
        let mesh = mesh_slab(&slab);
        self.pipeline
            .upload_body(&self.gpu, (id.slot, id.generation), &mesh);
        tracing::info!(?id, ?origin_m, "spawned debris body");
    }

    /// Rewrite every awake debris body's GPU transform from the interpolated
    /// physics state. Chunk mesh vertices are in grid-voxel corner units
    /// scaled by `voxel_size_m` in the shader; the same scaling applies to
    /// debris, so the model matrix carries only translation and rotation.
    fn sync_debris_render(&mut self, alpha: f32) {
        for (id, body) in self.phys.iter() {
            let (pos, rot) = self
                .phys
                .interpolated_transform(id, alpha)
                .expect("id came from iter()");
            // grid_offset is already in meters (mass_props computes com_local
            // in meters); the shader's `local` is also meters after scaling
            // grid-corner units by voxel_size_m, so no unit conversion here.
            let model = Mat4::from_rotation_translation(rot, pos)
                * Mat4::from_translation(body.grid_offset);
            self.pipeline
                .update_body_transform(&self.gpu, (id.slot, id.generation), model);
        }
    }

    fn set_grab(&mut self, grab: bool) {
        let mode = if grab {
            CursorGrabMode::Locked
        } else {
            CursorGrabMode::None
        };
        let result = self.window.set_cursor_grab(mode).or_else(|_| {
            self.window.set_cursor_grab(if grab {
                CursorGrabMode::Confined
            } else {
                CursorGrabMode::None
            })
        });
        match result {
            Ok(()) => {
                self.window.set_cursor_visible(!grab);
                self.grabbed = grab;
            }
            Err(err) => tracing::warn!(%err, "cursor grab change failed"),
        }
    }

    /// Tool input: LMB uses the active tool (break/blast), RMB places.
    fn apply_tools(&mut self, input: &InputState) {
        let eye = self.player.eye(1.0);
        let look = self.player.look_dir();
        if input.mouse_clicked(MouseButton::Left) {
            match self.tools.tool {
                Tool::Blast => {
                    tracing::info!("blast tool arrives with the destruction milestone (M5)");
                }
                _ => self.tools.break_voxel(&mut self.world, eye, look),
            }
        }
        if input.mouse_clicked(MouseButton::Right) {
            self.tools
                .place_voxel(&mut self.world, eye, look, self.player.ctrl.aabb());
        }
        if input.wheel_delta.abs() >= 1.0 {
            let steps = input.wheel_delta as i32;
            self.tools.cycle_material(steps, &self.registry);
        }
    }

    fn report_stats(&mut self, stats: vox_render::DrawStats) {
        self.frames += 1;
        if self.last_report.elapsed().as_secs_f32() >= 1.0 {
            tracing::info!(
                fps = self.frames,
                drawn = stats.drawn,
                culled = stats.culled,
                queue = self.remesh.pending_len(),
                in_flight = self.remesh.in_flight,
                bodies = self.phys.body_count(),
                bodies_awake = self.phys.awake_count(),
                pos = ?voxel_at(self.player.ctrl.pos, self.world.cfg.voxel_size_m),
                grounded = self.player.ctrl.grounded,
                "frame stats"
            );
            self.frames = 0;
            self.last_report = Instant::now();
        }
    }
}

impl App for VoxApp {
    fn frame(&mut self, input: &mut InputState, timing: FrameTiming) -> FrameControl {
        if input.key_pressed(KeyCode::Escape) {
            if self.grabbed {
                self.set_grab(false);
            } else {
                return FrameControl::Exit;
            }
        }
        let mut grabbed_this_frame = false;
        if input.mouse_clicked(MouseButton::Left) && !self.grabbed {
            self.set_grab(true);
            grabbed_this_frame = true;
        }
        if input.key_pressed(KeyCode::KeyF) {
            self.player.toggle_fly();
        }
        if input.key_pressed(KeyCode::KeyB) {
            let origin = self.player.eye(1.0) + self.player.look_dir() * 4.0;
            self.spawn_debris(origin, 4, self.player.look_dir() * 8.0);
        }
        if input.key_pressed(KeyCode::KeyX) {
            let removed = self.phys.clear_sleeping();
            for id in &removed {
                self.pipeline.remove_body((id.slot, id.generation));
            }
            if !removed.is_empty() {
                tracing::info!(count = removed.len(), "cleared sleeping debris");
            }
        }
        for (key, tool) in [
            (KeyCode::Digit1, Tool::Place),
            (KeyCode::Digit2, Tool::Break),
            (KeyCode::Digit3, Tool::Blast),
        ] {
            if input.key_pressed(key) {
                self.tools.tool = tool;
                tracing::info!(tool = ?tool, "tool selected");
            }
        }

        if self.grabbed {
            self.player.look(input.mouse_delta);
            if !grabbed_this_frame {
                self.apply_tools(input);
            }
        }
        self.player
            .fixed_steps(&self.world, input, timing.physics_steps);
        for _ in 0..timing.physics_steps {
            self.phys.step(&self.world, vox_core::consts::PHYSICS_DT);
        }

        // Remeshing: absorb edits, dispatch to workers, upload results.
        // Physics wake-up consumption arrives with the destruction milestone.
        let _ = self.world.drain_dirty_regions();
        self.remesh.absorb_dirty(&mut self.world);
        let eye = self.player.eye(timing.alpha);
        self.remesh.dispatch(&self.world, eye);
        self.remesh.collect(&self.gpu, &mut self.pipeline);
        self.sync_debris_render(timing.alpha);

        // Camera from the interpolated player eye.
        self.camera.pos = eye;
        self.camera.yaw = self.player.yaw;
        self.camera.pitch = self.player.pitch;
        let (w, h) = self.gpu.surface_size();
        let aspect = w as f32 / h.max(1) as f32;
        let view_proj = self.camera.view_proj(aspect);
        self.pipeline
            .write_camera(&self.gpu, view_proj, self.camera.pos, FOG_END_M);
        let frustum = Frustum::from_view_proj(view_proj);

        let frame = match self.gpu.begin_frame() {
            Ok(frame) => frame,
            Err(err) if err.is_transient() => {
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
        let stats;
        {
            let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("voxel-pass"),
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
            stats = self.pipeline.draw_chunks(&mut pass, &frustum);
            self.pipeline.draw_bodies(&mut pass);
        }
        self.gpu.queue().submit([encoder.finish()]);
        frame.present();

        self.report_stats(stats);
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
