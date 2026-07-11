//! The always-on game HUD: crosshair and a bottom-center hotbar with the
//! active tool highlighted, plus contextual info (tool radius, build
//! material). Distinct from the F3 debug windows in `panels` -- this is
//! player-facing UI, drawn every frame whether or not debug is open.
//!
//! In Mario mode the FPS HUD is replaced by the SM64 power meter: a
//! circular health pie (8 wedges, green→red as health drops) in the
//! upper-right corner, plus a short action label.

use egui::{Align2, Color32, Context, FontId, Rect, Rounding, Stroke, pos2, vec2};

/// Mario-mode HUD data. When present in [`HudState`], the FPS hotbar/
/// crosshair is suppressed and the SM64 power meter is drawn instead.
pub struct MarioHudState {
    /// Health 0-8 (8 = full). Drives the power meter pie.
    pub health: i16,
    /// Current action bitmask for a short label.
    pub action: u32,
}

/// Everything the HUD draws from. Built fresh by the app each frame.
pub struct HudState<'a> {
    /// Label per hotbar slot (1-9); `None` renders an empty slot.
    pub slots: [Option<&'a str>; 9],
    /// Index (0-8) of the active slot.
    pub active: usize,
    /// Adjustable radius of the active tool, if it has one.
    pub radius_m: Option<f32>,
    /// Currently selected build material (right-click placement).
    pub material_name: &'a str,
    /// Its palette color, for the little swatch next to the name.
    pub material_color: [f32; 3],
    /// When `Some`, the engine is in Mario mode — draw the SM64 power
    /// meter instead of the FPS crosshair/hotbar.
    pub mario: Option<MarioHudState>,
}

const SLOT_SIZE: f32 = 52.0;
const SLOT_GAP: f32 = 6.0;
const BAR_MARGIN_BOTTOM: f32 = 16.0;

/// Draw the full HUD for one frame.
pub fn build(ctx: &Context, state: &HudState<'_>) {
    if state.mario.is_some() {
        mario_hud(ctx, state.mario.as_ref().unwrap());
    } else {
        crosshair(ctx);
        hotbar(ctx, state);
        info_line(ctx, state);
    }
}

/// SM64 power meter: 8-wedge circular health pie in the upper-right,
/// plus a short action label below it.
fn mario_hud(ctx: &Context, mario: &MarioHudState) {
    power_meter(ctx, mario.health);
    action_label(ctx, mario.action);
}

/// A small dot at the exact center of the viewport, with a faint outline so
/// it stays visible over bright terrain.
fn crosshair(ctx: &Context) {
    let center = ctx.screen_rect().center();
    let painter = ctx.layer_painter(egui::LayerId::background());
    painter.circle_filled(center, 2.5, Color32::from_rgba_unmultiplied(255, 255, 255, 220));
    painter.circle_stroke(
        center,
        2.5,
        Stroke::new(1.0, Color32::from_rgba_unmultiplied(0, 0, 0, 160)),
    );
}

fn hotbar(ctx: &Context, state: &HudState<'_>) {
    let screen = ctx.screen_rect();
    let n = state.slots.len() as f32;
    let bar_w = n * SLOT_SIZE + (n - 1.0) * SLOT_GAP;
    let left = screen.center().x - bar_w * 0.5;
    let top = screen.bottom() - BAR_MARGIN_BOTTOM - SLOT_SIZE;
    let painter = ctx.layer_painter(egui::LayerId::background());

    for (i, label) in state.slots.iter().enumerate() {
        let x = left + i as f32 * (SLOT_SIZE + SLOT_GAP);
        let rect = Rect::from_min_size(pos2(x, top), vec2(SLOT_SIZE, SLOT_SIZE));
        let active = i == state.active;

        let fill = if active {
            Color32::from_rgba_unmultiplied(70, 90, 120, 210)
        } else {
            Color32::from_rgba_unmultiplied(20, 24, 30, 160)
        };
        let border = if active {
            Stroke::new(2.0, Color32::from_rgb(160, 200, 255))
        } else {
            Stroke::new(1.0, Color32::from_rgba_unmultiplied(255, 255, 255, 60))
        };
        painter.rect(rect, Rounding::same(6.0), fill, border);

        // Slot number, small, top-left corner.
        painter.text(
            rect.min + vec2(5.0, 3.0),
            Align2::LEFT_TOP,
            format!("{}", i + 1),
            FontId::proportional(11.0),
            Color32::from_rgba_unmultiplied(255, 255, 255, 140),
        );

        if let Some(label) = label {
            painter.text(
                rect.center() + vec2(0.0, 4.0),
                Align2::CENTER_CENTER,
                *label,
                FontId::proportional(13.0),
                if active {
                    Color32::WHITE
                } else {
                    Color32::from_rgba_unmultiplied(255, 255, 255, 170)
                },
            );
        }
    }
}

/// One line of contextual text above the hotbar: active tool's radius (when
/// it has one) and the current build material with a color swatch.
fn info_line(ctx: &Context, state: &HudState<'_>) {
    let screen = ctx.screen_rect();
    let y = screen.bottom() - BAR_MARGIN_BOTTOM - SLOT_SIZE - 14.0;
    let painter = ctx.layer_painter(egui::LayerId::background());

    let mut text = String::new();
    if let Some(r) = state.radius_m {
        text.push_str(&format!("radius {r:.2} m (scroll)   "));
    }
    text.push_str(&format!("build: {}", state.material_name));

    let text_rect = painter.text(
        pos2(screen.center().x + 8.0, y),
        Align2::CENTER_CENTER,
        text,
        FontId::proportional(12.0),
        Color32::from_rgba_unmultiplied(255, 255, 255, 190),
    );

    // Material swatch just left of the text.
    let c = state.material_color;
    painter.rect(
        Rect::from_center_size(pos2(text_rect.left() - 10.0, y), vec2(10.0, 10.0)),
        Rounding::same(2.0),
        Color32::from_rgb(
            (c[0] * 255.0) as u8,
            (c[1] * 255.0) as u8,
            (c[2] * 255.0) as u8,
        ),
        Stroke::new(1.0, Color32::from_rgba_unmultiplied(0, 0, 0, 120)),
    );
}

/// SM64 power meter: a circular pie chart with 8 wedges representing
/// health (0-8, 8 = full). Wedges are filled or empty depending on
/// current health. Color shifts green→yellow→red as health drops.
/// Drawn in the upper-right corner, matching SM64's HUD position.
fn power_meter(ctx: &Context, health: i16) {
    let screen = ctx.screen_rect();
    let radius = 36.0;
    let center = pos2(screen.right() - 60.0, screen.top() + 60.0);
    let painter = ctx.layer_painter(egui::LayerId::background());

    // Background circle (dark, semi-transparent).
    painter.circle_filled(
        center,
        radius + 4.0,
        Color32::from_rgba_unmultiplied(10, 10, 20, 180),
    );

    // Health color: green at 6-8, yellow at 3-5, red at 0-2.
    let health_color = if health >= 6 {
        Color32::from_rgb(80, 220, 80)
    } else if health >= 3 {
        Color32::from_rgb(240, 200, 60)
    } else {
        Color32::from_rgb(220, 60, 60)
    };

    let empty_color = Color32::from_rgba_unmultiplied(40, 40, 50, 120);
    let n_wedges = 8u16;
    let h = health.clamp(0, 8) as u16;

    // Draw 8 wedges as filled sectors. egui doesn't have a direct arc
    // sector primitive, so we approximate each wedge with a triangle
    // fan from the center to two points on the circle.
    for i in 0..n_wedges {
        let a0 = (i as f32 / n_wedges as f32) * std::f32::consts::TAU - std::f32::consts::FRAC_PI_2;
        let a1 = ((i + 1) as f32 / n_wedges as f32) * std::f32::consts::TAU - std::f32::consts::FRAC_PI_2;

        // Wedge i represents health unit (i+1). Filled if i < h.
        let filled = i < h;
        let color = if filled { health_color } else { empty_color };

        // Midpoint of the wedge arc for a triangle approximation.
        let am = (a0 + a1) * 0.5;
        let p0 = pos2(center.x + a0.cos() * radius, center.y + a0.sin() * radius);
        let p1 = pos2(center.x + a1.cos() * radius, center.y + a1.sin() * radius);
        let pm = pos2(center.x + am.cos() * radius, center.y + am.sin() * radius);

        // Draw the wedge as a filled triangle (center → p0 → pm → p1).
        // Two triangles for a better arc approximation.
        painter.add(egui::Shape::convex_polygon(
            vec![center, p0, pm, p1],
            color,
            Stroke::NONE,
        ));
    }

    // Outline ring.
    painter.circle_stroke(
        center,
        radius,
        Stroke::new(2.0, Color32::from_rgba_unmultiplied(255, 255, 255, 160)),
    );

    // Health number in the center.
    painter.text(
        center,
        Align2::CENTER_CENTER,
        format!("{h}"),
        FontId::proportional(20.0),
        Color32::WHITE,
    );
}

/// Short action label below the power meter. Maps SM64 action bitmasks
/// to readable names for the common actions.
fn action_label(ctx: &Context, action: u32) {
    let screen = ctx.screen_rect();
    let pos = pos2(screen.right() - 60.0, screen.top() + 108.0);
    let painter = ctx.layer_painter(egui::LayerId::background());

    let label = action_name(action);
    painter.text(
        pos,
        Align2::CENTER_CENTER,
        label,
        FontId::proportional(14.0),
        Color32::from_rgba_unmultiplied(255, 255, 255, 200),
    );
}

/// Map an SM64 action bitmask to a short human-readable name.
/// Based on the action flag bits in SM64's action enum.
fn action_name(action: u32) -> &'static str {
    // Check action flag bits first for broad categories.
    if action & vox_sm64_act_flag::AIR != 0 {
        if action == 0x01000882 {
            "Triple Jump"
        } else if action == 0x03000889 {
            "Double Jump"
        } else if action == 0x02000888 {
            "Jump"
        } else if action == 0x0801003C {
            "Wall Kick"
        } else if action == 0x00000880 {
            "Freefall"
        } else {
            "Airborne"
        }
    } else if action == vox_sm64_act_flag::IDLE {
        "Idle"
    } else if action == 0x04000440 {
        "Running"
    } else if action == 0x04000447 {
        "Walking"
    } else if action == 0x0C000220 {
        "Ground Pound"
    } else if action == 0x0800023C {
        "Pound Land"
    } else if action == 0x00000480 {
        "Crouching"
    } else if action & vox_sm64_act_flag::ATTACKING != 0 {
        "Attacking"
    } else {
        "—"
    }
}

/// SM64 action flag constants used by the action label.
mod vox_sm64_act_flag {
    /// Set while Mario is airborne (jump/fall/etc.).
    pub const AIR: u32 = 0x00000800;
    /// Set for attacking actions (ground pound, dive, punch, etc.).
    pub const ATTACKING: u32 = 0x00800000;
    /// Idle action value.
    pub const IDLE: u32 = 0x0C000200;
}
