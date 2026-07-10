//! The always-on game HUD: crosshair and a bottom-center hotbar with the
//! active tool highlighted, plus contextual info (tool radius, build
//! material). Distinct from the F3 debug windows in `panels` -- this is
//! player-facing UI, drawn every frame whether or not debug is open.

use egui::{Align2, Color32, Context, FontId, Rect, Rounding, Stroke, pos2, vec2};

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
}

const SLOT_SIZE: f32 = 52.0;
const SLOT_GAP: f32 = 6.0;
const BAR_MARGIN_BOTTOM: f32 = 16.0;

/// Draw the full HUD for one frame.
pub fn build(ctx: &Context, state: &HudState<'_>) {
    crosshair(ctx);
    hotbar(ctx, state);
    info_line(ctx, state);
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
