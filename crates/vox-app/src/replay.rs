//! Snapshot-based replay: records player + camera + debris body state
//! periodically and plays it back. The voxel world itself is NOT snapshotted
//! (268M voxels would be ~500MB per the research); replay shows the player
//! and debris flying around over whatever terrain state is currently live.
//!
//! This is a first-pass replay system: enough to watch a recorded run back,
//! deliberately cheap to capture and apply.

use std::collections::VecDeque;

use crate::player::Player;
use glam::{Quat, Vec3};
use vox_physics::{BodyId, PhysicsWorld};

/// Maximum snapshots retained. At one snapshot per second that's 10 minutes
/// of recording; older frames are dropped from the front as it fills.
const MAX_SNAPSHOTS: usize = 600;

/// Record one snapshot every this many frames (~1 second at 60 Hz).
const RECORD_INTERVAL: u32 = 60;

/// A single point-in-time capture of the lightweight, replay-relevant
/// simulation state: the player/camera transform, the day/night clock, and
/// every debris body's transform + velocity. Voxel world state is
/// intentionally excluded (see module docs).
#[derive(Clone)]
pub struct Snapshot {
    pub player_pos: Vec3,
    pub player_yaw: f32,
    pub player_pitch: f32,
    pub game_time: f32,
    pub bodies: Vec<(Vec3, Quat, Vec3)>,
}

/// Replay recording/playback state. Either `recording` or `playback` is true
/// at a time, never both. During playback, snapshots are consumed in order
/// from the front of `snapshots` (the same buffer they were recorded into).
#[derive(Default)]
pub struct ReplayState {
    pub recording: bool,
    pub playback: bool,
    pub snapshots: VecDeque<Snapshot>,
    frame_counter: u32,
}

impl ReplayState {
    /// Begin (or resume) recording. Clears any in-progress playback.
    pub fn start_recording(&mut self) {
        self.recording = true;
        self.playback = false;
        self.snapshots.clear();
        self.frame_counter = 0;
        tracing::info!("replay: recording started");
    }

    /// Stop recording without playing back.
    pub fn stop_recording(&mut self) {
        if self.recording {
            self.recording = false;
            tracing::info!(count = self.snapshots.len(), "replay: recording stopped");
        }
    }

    /// Toggle recording on/off. Used by the KeyR handler.
    pub fn toggle_recording(&mut self) {
        if self.recording {
            self.stop_recording();
        } else {
            self.start_recording();
        }
    }

    /// Begin playback of whatever was last recorded. Does nothing if there
    /// are no snapshots to play.
    pub fn start_playback(&mut self) {
        if self.snapshots.is_empty() {
            tracing::info!("replay: no recording to play back");
            return;
        }
        self.recording = false;
        self.playback = true;
        tracing::info!(count = self.snapshots.len(), "replay: playback started");
    }

    /// Record a snapshot, throttled to one per `RECORD_INTERVAL` frames.
    /// Call this every frame while recording; it internally decides whether
    /// to actually capture.
    pub fn record(&mut self, player: &Player, game_time: f32, phys: &PhysicsWorld) {
        if !self.recording {
            return;
        }
        self.frame_counter = self.frame_counter.wrapping_add(1);
        if self.frame_counter % RECORD_INTERVAL != 0 {
            return;
        }
        let bodies: Vec<(Vec3, Quat, Vec3)> =
            phys.iter().map(|(_, b)| (b.pos, b.rot, b.vel)).collect();
        let snap = Snapshot {
            player_pos: player.ctrl.pos,
            player_yaw: player.yaw,
            player_pitch: player.pitch,
            game_time,
            bodies,
        };
        self.snapshots.push_back(snap);
        while self.snapshots.len() > MAX_SNAPSHOTS {
            self.snapshots.pop_front();
        }
    }

    /// Apply the next playback snapshot to the player + physics bodies.
    /// Returns `false` when the recording is exhausted (and leaves
    /// `playback` false so the caller stops calling); `true` if a snapshot
    /// was applied and playback continues.
    ///
    /// Player position/yaw/pitch are written directly (the caller suppresses
    /// normal input handling while `playback` is true). Debris bodies are
    /// moved to their recorded transforms by matching against the live body
    /// set by index order — this is a best-effort visual replay, not an exact
    /// physics reconstruction, so a body that no longer exists is simply
    /// skipped.
    pub fn playback_step(
        &mut self,
        player: &mut Player,
        phys: &mut PhysicsWorld,
        game_time: &mut f32,
    ) -> bool {
        if !self.playback {
            return false;
        }
        let Some(snap) = self.snapshots.pop_front() else {
            self.playback = false;
            tracing::info!("replay: playback finished");
            return false;
        };
        player.ctrl.pos = snap.player_pos;
        player.yaw = snap.player_yaw;
        player.pitch = snap.player_pitch;
        *game_time = snap.game_time;
        // Apply recorded body states to the live bodies, matched in iteration
        // order. Extra live bodies (spawned after recording) keep their state;
        // missing ones are skipped. We can't mutate through `iter()`, so
        // collect ids then update by id.
        let live_ids: Vec<BodyId> = phys.iter().map(|(id, _)| id).collect();
        for (i, id) in live_ids.iter().enumerate() {
            if let Some(&(pos, rot, vel)) = snap.bodies.get(i) {
                if let Some(b) = phys.get_mut(*id) {
                    b.pos = pos;
                    b.rot = rot;
                    b.vel = vel;
                }
            }
        }
        true
    }

    /// True iff playback is currently active (caller uses this to suppress
    /// player input and let `playback_step` drive the camera).
    pub fn is_playing(&self) -> bool {
        self.playback
    }
}
