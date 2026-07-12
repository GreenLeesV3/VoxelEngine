//! The always-on game HUD: crosshair and a bottom-center hotbar with the
//! active tool highlighted, plus contextual info (tool radius, build
//! material). Distinct from the F3 debug windows in `panels` -- this is
//! player-facing UI, drawn every frame whether or not debug is open.
//!
//! In Mario mode the FPS HUD is replaced by the authentic SM64 HUD:
//! the power meter (real ROM-extracted textures), coin/star/lives
//! counters with outlines for when collectibles are implemented, and
//! an action label. Textures are uploaded to egui once and cached.

use egui::{Align2, Color32, Context, FontId, Rect, Rounding, Stroke, TextureHandle, TextureOptions, pos2, vec2};
use std::sync::Arc;

/// Raw RGBA8 textures extracted from the SM64 ROM, passed from MarioMode
/// to the HUD each frame. The HUD uploads them to egui TextureHandles on
/// first encounter and caches them in the egui context for reuse.
pub struct MarioHudTextures {
    /// Power meter base left half (32×64, RGBA8)
    pub power_meter_left: Arc<[u8]>,
    /// Power meter base right half (32×64, RGBA8)
    pub power_meter_right: Arc<[u8]>,
    /// 8 health segment textures (32×32 each, RGBA8), index 0 = 1 wedge
    pub power_meter_segments: [Arc<[u8]>; 8],
    /// Coin icon (16×16, RGBA8)
    pub coin_icon: Arc<[u8]>,
    /// Star icon (16×16, RGBA8)
    pub star_icon: Arc<[u8]>,
    /// Mario head icon (16×16, RGBA8) — for lives display
    pub mario_head: Arc<[u8]>,
    /// "×" multiply icon (16×16, RGBA8)
    pub multiply: Arc<[u8]>,
    /// Digit 0-9 (16×16 each, RGBA8)
    pub digits: [Arc<[u8]>; 10],
}

/// Cached egui texture handles for the SM64 HUD. Stored in egui's
/// memory so they persist across frames and are uploaded only once.
struct MarioHudCache {
    power_meter_left: TextureHandle,
    power_meter_right: TextureHandle,
    power_meter_segments: [TextureHandle; 8],
    coin_icon: TextureHandle,
    star_icon: TextureHandle,
    mario_head: TextureHandle,
    multiply: TextureHandle,
    digits: [TextureHandle; 10],
}

/// Mario-mode HUD data. When present in [`HudState`], the FPS hotbar/
/// crosshair is suppressed and the authentic SM64 HUD is drawn instead.
pub struct MarioHudState {
    /// Health 0-8 (8 = full). Drives the power meter.
    pub health: i16,
    /// Current action bitmask for a short label.
    pub action: u32,
    /// ROM-extracted textures. When None, falls back to egui-drawn
    /// approximation.
    pub textures: Option<Arc<MarioHudTextures>>,
    /// Coin count (placeholder — collectibles not yet implemented).
    pub coins: i32,
    /// Star count (placeholder — collectibles not yet implemented).
    pub stars: i32,
    /// Lives (placeholder — death/respawn not yet implemented).
    pub lives: i32,
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
    /// When `Some`, the engine is in Mario mode — draw the SM64 HUD
    /// instead of the FPS crosshair/hotbar.
    pub mario: Option<MarioHudState>,
}

const SLOT_SIZE: f32 = 52.0;
const SLOT_GAP: f32 = 6.0;
const BAR_MARGIN_BOTTOM: f32 = 16.0;

/// egui memory key for the cached HUD textures.
const HUD_CACHE_KEY: &str = "mario_hud_texture_cache";

/// Upload raw RGBA8 data to an egui TextureHandle.
fn make_texture(ctx: &Context, name: &str, data: &[u8], w: usize, h: usize) -> TextureHandle {
    ctx.load_texture(name, egui::ColorImage {
        size: [w, h],
        pixels: data.chunks_exact(4)
            .map(|c| egui::Color32::from_rgba_unmultiplied(c[0], c[1], c[2], c[3]))
            .collect(),
    }, TextureOptions::NEAREST)
}

/// Get or create the cached egui texture handles from raw ROM data.
fn get_hud_cache(ctx: &Context, tex: &MarioHudTextures) -> Arc<MarioHudCache> {
    let id = egui::Id::new(HUD_CACHE_KEY);
    if let Some(cached) = ctx.data(|d| d.get_temp::<Arc<MarioHudCache>>(id)) {
        return cached;
    }
    let cache = Arc::new(MarioHudCache {
        power_meter_left: make_texture(ctx, "pm_left", &tex.power_meter_left, 32, 64),
        power_meter_right: make_texture(ctx, "pm_right", &tex.power_meter_right, 32, 64),
        power_meter_segments: std::array::from_fn(|i| {
            make_texture(ctx, &format!("pm_seg_{i}"), &tex.power_meter_segments[i], 32, 32)
        }),
        coin_icon: make_texture(ctx, "coin_icon", &tex.coin_icon, 16, 16),
        star_icon: make_texture(ctx, "star_icon", &tex.star_icon, 16, 16),
        mario_head: make_texture(ctx, "mario_head", &tex.mario_head, 16, 16),
        multiply: make_texture(ctx, "multiply", &tex.multiply, 16, 16),
        digits: std::array::from_fn(|i| {
            make_texture(ctx, &format!("digit_{i}"), &tex.digits[i], 16, 16)
        }),
    });
    ctx.data_mut(|d| d.insert_temp(id, cache.clone()));
    cache
}

/// Draw the full HUD for one frame.
pub fn build(ctx: &Context, state: &HudState<'_>) {
    if let Some(mario) = &state.mario {
        mario_hud(ctx, mario);
    } else {
        crosshair(ctx);
        hotbar(ctx, state);
        info_line(ctx, state);
    }
}

/// SM64 HUD: power meter (upper-right), lives/coins/stars (upper-left),
/// and action label. Uses authentic ROM-extracted textures when available.
fn mario_hud(ctx: &Context, mario: &MarioHudState) {
    if let Some(tex_arc) = &mario.textures {
        let cache = get_hud_cache(ctx, tex_arc);
        authentic_power_meter(ctx, &cache, mario.health);
        authentic_counters(ctx, &cache, mario.lives, mario.coins, mario.stars);
    } else {
        power_meter_fallback(ctx, mario.health);
        fallback_counters(ctx, mario.lives, mario.coins, mario.stars);
    }
    action_label(ctx, mario.action);
}

/// Fallback counters drawn with egui text when ROM textures are not
/// available. Mirrors `authentic_counters` layout (upper-left): lives,
/// stars, then coins — rendered as plain ASCII since the HUD digit
/// textures are absent.
fn fallback_counters(ctx: &Context, lives: i32, coins: i32, stars: i32) {
    let screen = ctx.screen_rect();
    let painter = ctx.layer_painter(egui::LayerId::background());
    let pos = pos2(screen.left() + 20.0, screen.top() + 20.0);
    let font = FontId::proportional(18.0);
    let color = Color32::from_rgba_unmultiplied(255, 255, 255, 220);
    let line_h = 24.0;

    let lines = [
        format!("x {lives}"),
        format!("* {stars}"),
        format!("o {coins}"),
    ];

    for (i, line) in lines.iter().enumerate() {
        painter.text(
            pos2(pos.x, pos.y + (i as f32) * line_h),
            Align2::LEFT_TOP,
            line,
            font.clone(),
            color,
        );
    }
}

/// A small dot at the exact center of the viewport, with a faint outline so
/// it stays visible over bright terrain.
fn crosshair(ctx: &Context) {
    let center = ctx.screen_rect().center();
    let painter = ctx.layer_painter(egui::LayerId::background());
    painter.circle_filled(
        center,
        2.5,
        Color32::from_rgba_unmultiplied(255, 255, 255, 220),
    );
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

/// Authentic SM64 power meter using ROM-extracted textures.
/// Draws the base (left+right halves = 64×64) with the health segment
/// overlay on top. Positioned in the upper-right, matching SM64.
fn authentic_power_meter(ctx: &Context, cache: &MarioHudCache, health: i16) {
    let screen = ctx.screen_rect();
    let painter = ctx.layer_painter(egui::LayerId::background());

    // SM64 draws the power meter at ~140,166 in its 320×240 screen.
    // We scale to match the upper-right area. The base is 64×64.
    let scale = 2.0; // 2x for visibility on modern displays
    let size = 64.0 * scale;
    // Position: upper-right with some margin
    let x = screen.right() - size - 20.0;
    let y = screen.top() + 20.0;

    // Draw the base: left half (32×64) then right half (32×64).
    let half_w = 32.0 * scale;
    painter.image(
        cache.power_meter_left.id(),
        Rect::from_min_size(pos2(x, y), vec2(half_w, size)),
        Rect::from_min_size(pos2(0.0, 0.0), vec2(1.0, 1.0)),
        Color32::WHITE,
    );
    painter.image(
        cache.power_meter_right.id(),
        Rect::from_min_size(pos2(x + half_w, y), vec2(half_w, size)),
        Rect::from_min_size(pos2(0.0, 0.0), vec2(1.0, 1.0)),
        Color32::WHITE,
    );

    // Draw the health segment overlay (32×32) centered on the base.
    let h = health.clamp(0, 8) as usize;
    if h > 0 {
        let seg_size = 32.0 * scale;
        let seg_x = x + (size - seg_size) * 0.5;
        let seg_y = y + (size - seg_size) * 0.5;
        painter.image(
            cache.power_meter_segments[h - 1].id(),
            Rect::from_min_size(pos2(seg_x, seg_y), vec2(seg_size, seg_size)),
            Rect::from_min_size(pos2(0.0, 0.0), vec2(1.0, 1.0)),
            Color32::WHITE,
        );
    }
}

/// Authentic SM64 HUD counters: lives (Mario head × N), coins (coin × N),
/// stars (star × N). Uses the colorful HUD font digits from the ROM.
/// Positioned in the upper-left, matching SM64's layout.
fn authentic_counters(ctx: &Context, cache: &MarioHudCache, lives: i32, coins: i32, stars: i32) {
    let screen = ctx.screen_rect();
    let painter = ctx.layer_painter(egui::LayerId::background());
    let scale = 2.0;
    let icon_size = 16.0 * scale;
    let gap = 4.0 * scale;
    let digit_w = 16.0 * scale;

    // SM64 layout (top-left, y from top):
    // Lives:  MarioHead × N        (y ≈ 209 in 240-tall screen)
    // Coins:  Coin × N             (y ≈ 209, x ≈ 168)
    // Stars:  Star × N             (y ≈ 209, x ≈ 78)
    // We adapt: lives top-left, stars below, coins below that.

    let mut y = screen.top() + 20.0;
    let x = screen.left() + 20.0;

    // Lives: Mario head icon, ×, then digit(s)
    draw_icon_with_count(
        &painter, &cache.mario_head, &cache.multiply, &cache.digits,
        lives, pos2(x, y), icon_size, digit_w, gap,
    );
    y += icon_size + 8.0;

    // Stars: star icon, ×, then digit(s)
    draw_icon_with_count(
        &painter, &cache.star_icon, &cache.multiply, &cache.digits,
        stars, pos2(x, y), icon_size, digit_w, gap,
    );
    y += icon_size + 8.0;

    // Coins: coin icon, ×, then digit(s)
    draw_icon_with_count(
        &painter, &cache.coin_icon, &cache.multiply, &cache.digits,
        coins, pos2(x, y), icon_size, digit_w, gap,
    );
}

/// Draw an icon followed by "×" and a count using the ROM font digits.
fn draw_icon_with_count(
    painter: &egui::Painter,
    icon: &TextureHandle,
    multiply: &TextureHandle,
    digits: &[TextureHandle; 10],
    count: i32,
    pos: egui::Pos2,
    icon_size: f32,
    digit_w: f32,
    gap: f32,
) {
    let mut x = pos.x;
    let y = pos.y;

    // Icon
    painter.image(
        icon.id(),
        Rect::from_min_size(pos2(x, y), vec2(icon_size, icon_size)),
        Rect::from_min_size(pos2(0.0, 0.0), vec2(1.0, 1.0)),
        Color32::WHITE,
    );
    x += icon_size + gap;

    // × symbol
    painter.image(
        multiply.id(),
        Rect::from_min_size(pos2(x, y), vec2(icon_size, icon_size)),
        Rect::from_min_size(pos2(0.0, 0.0), vec2(1.0, 1.0)),
        Color32::WHITE,
    );
    x += icon_size + gap;

    // Digits
    let s = count.to_string();
    for ch in s.chars() {
        if let Some(d) = ch.to_digit(10) {
            painter.image(
                digits[d as usize].id(),
                Rect::from_min_size(pos2(x, y), vec2(digit_w, icon_size)),
                Rect::from_min_size(pos2(0.0, 0.0), vec2(1.0, 1.0)),
                Color32::WHITE,
            );
            x += digit_w;
        }
    }
}

/// Fallback power meter drawn with egui primitives when ROM textures
/// are not available.
fn power_meter_fallback(ctx: &Context, health: i16) {
    let screen = ctx.screen_rect();
    let radius = 36.0;
    let center = pos2(screen.right() - 60.0, screen.top() + 60.0);
    let painter = ctx.layer_painter(egui::LayerId::background());

    painter.circle_filled(
        center,
        radius + 4.0,
        Color32::from_rgba_unmultiplied(10, 10, 20, 180),
    );

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

    for i in 0..n_wedges {
        let a0 = (i as f32 / n_wedges as f32) * std::f32::consts::TAU - std::f32::consts::FRAC_PI_2;
        let a1 = ((i + 1) as f32 / n_wedges as f32) * std::f32::consts::TAU - std::f32::consts::FRAC_PI_2;
        let filled = i < h;
        let color = if filled { health_color } else { empty_color };
        let am = (a0 + a1) * 0.5;
        let p0 = pos2(center.x + a0.cos() * radius, center.y + a0.sin() * radius);
        let p1 = pos2(center.x + a1.cos() * radius, center.y + a1.sin() * radius);
        let pm = pos2(center.x + am.cos() * radius, center.y + am.sin() * radius);
        painter.add(egui::Shape::convex_polygon(
            vec![center, p0, pm, p1],
            color,
            Stroke::NONE,
        ));
    }

    painter.circle_stroke(
        center,
        radius,
        Stroke::new(2.0, Color32::from_rgba_unmultiplied(255, 255, 255, 160)),
    );

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
        } else if action == 0x008008A9 {
            "Ground Pound"
        } else {
            "Airborne"
        }
    } else if action == vox_sm64_act_flag::IDLE {
        "Idle"
    } else if action == 0x04000440 {
        "Running"
    } else if action == 0x04000447 {
        "Walking"
    } else if action == 0x0080023C {
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

#[cfg(test)]
mod tests {
    use super::action_name;

    #[test]
    fn ground_pound_action_name() {
        assert_eq!(action_name(0x008008A9), "Ground Pound");
    }

    #[test]
    fn pound_land_action_name() {
        assert_eq!(action_name(0x0080023C), "Pound Land");
    }

    #[test]
    fn triple_jump_action_name() {
        assert_eq!(action_name(0x01000882), "Triple Jump");
    }

    #[test]
    fn unknown_action_is_nonempty() {
        let name = action_name(0);
        assert!(!name.is_empty(), "action_name(0) should return a non-empty label");
    }
}
