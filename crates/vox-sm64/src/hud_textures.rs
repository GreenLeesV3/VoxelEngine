//! Runtime extraction of SM64 HUD textures from the US ROM.
//!
//! This module decompresses the two MIO0-compressed texture segments
//! embedded in the US Super Mario 64 ROM and converts the N64 RGBA16
//! pixel format to RGBA8 for direct use with egui.
//!
//! - Segment 2 (font + HUD icons) — MIO0 at ROM offset `0x108A40`
//! - Segment 3 (actors/common1 — power meter, etc.) — MIO0 at `0x201410`
//!
//! The MIO0 decoder is a faithful port of the C implementation at
//! `libsm64/src/decomp/tools/libmio0.c`.

// ── Error type ────────────────────────────────────────────────────────

/// Errors that can occur while extracting HUD textures.
#[derive(Debug)]
pub enum HudTextureError {
    /// MIO0 decompression failed (corrupt header or data).
    Mio0Decode(String),
    /// The ROM is too short or does not contain the expected MIO0 blocks.
    InvalidRom,
}

impl std::fmt::Display for HudTextureError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            HudTextureError::Mio0Decode(msg) => {
                write!(f, "MIO0 decode error: {msg}")
            }
            HudTextureError::InvalidRom => write!(f, "invalid or incomplete ROM"),
        }
    }
}

impl std::error::Error for HudTextureError {}

// ── MIO0 decompression ────────────────────────────────────────────────

/// MIO0 header length in bytes (magic + three big-endian u32 fields).
const MIO0_HEADER_LENGTH: usize = 16;

/// Decode a single bit from the MIO0 bit stream.
///
/// Bit 0 is the MSB of byte 0 (matching the C macro `GET_BIT`).
#[inline]
fn get_bit(buf: &[u8], bit: usize) -> bool {
    (buf[bit / 8] & (1 << (7 - (bit % 8)))) != 0
}

/// Read a big-endian `u32` from a byte slice (no bounds checking beyond
/// the slice's own length; caller ensures 4 bytes are available).
#[inline]
fn read_u32_be(buf: &[u8]) -> u32 {
    u32::from_be_bytes([buf[0], buf[1], buf[2], buf[3]])
}

/// Decompress an MIO0-compressed block.
///
/// `input` must start at the beginning of the MIO0 block (the `"MIO0"`
/// magic) and contain the entire block: header + bit stream + compressed
/// data + uncompressed data.
///
/// Returns the decompressed bytes.
pub fn mio0_decode(input: &[u8]) -> Result<Vec<u8>, HudTextureError> {
    if input.len() < MIO0_HEADER_LENGTH {
        return Err(HudTextureError::Mio0Decode(
            "input too short for MIO0 header".to_owned(),
        ));
    }

    // Validate magic.
    if &input[0..4] != b"MIO0" {
        return Err(HudTextureError::Mio0Decode("bad MIO0 magic".to_owned()));
    }

    // Header fields (offsets are absolute within the MIO0 block).
    let dest_size = read_u32_be(&input[4..8]) as usize;
    let comp_offset = read_u32_be(&input[8..12]) as usize;
    let uncomp_offset = read_u32_be(&input[12..16]) as usize;

    let mut out: Vec<u8> = Vec::with_capacity(dest_size);

    let mut bit_idx: usize = 0;
    let mut comp_idx: usize = 0;
    let mut uncomp_idx: usize = 0;

    // Bit stream starts right after the header; hoist the slice so the
    // loop only does a bounds check, not a reslice each iteration.
    let bit_buf = &input[MIO0_HEADER_LENGTH..];
    while out.len() < dest_size {
        // Bounds-check before indexing: corrupt/truncated input would
        // otherwise panic inside `get_bit` (`buf[bit / 8]`).
        if bit_idx / 8 >= bit_buf.len() {
            return Err(HudTextureError::Mio0Decode(
                "bit stream read out of bounds".to_owned(),
            ));
        }
        if get_bit(bit_buf, bit_idx) {
            // 1 — pull one raw byte from the uncompressed section.
            let src = uncomp_offset
                .checked_add(uncomp_idx)
                .ok_or_else(|| HudTextureError::Mio0Decode("uncomp offset overflow".to_owned()))?;
            if src >= input.len() {
                return Err(HudTextureError::Mio0Decode(
                    "uncompressed read out of bounds".to_owned(),
                ));
            }
            out.push(input[src]);
            uncomp_idx += 1;
        } else {
            // 0 — read a 2-byte backreference from the compressed section.
            let base = comp_offset
                .checked_add(comp_idx)
                .ok_or_else(|| HudTextureError::Mio0Decode("comp offset overflow".to_owned()))?;
            if base + 1 >= input.len() {
                return Err(HudTextureError::Mio0Decode(
                    "compressed read out of bounds".to_owned(),
                ));
            }
            let vals = &input[base..base + 2];
            comp_idx += 2;

            let length = (((vals[0] & 0xF0) >> 4) + 3) as usize;
            let idx = (((vals[0] & 0x0F) as usize) << 8 | vals[1] as usize) + 1;

            if idx > out.len() {
                return Err(HudTextureError::Mio0Decode(format!(
                    "backreference index {idx} exceeds output length {}",
                    out.len()
                )));
            }

            let start = out.len() - idx;
            for i in 0..length {
                // Copy from `start + i`; the copy may overlap with the
                // region being written (LZ77-style sliding window).
                let byte = out[start + i];
                out.push(byte);
            }
        }
        bit_idx += 1;
    }

    Ok(out)
}

// ── RGBA16 → RGBA8 conversion ─────────────────────────────────────────

/// Convert N64 RGBA16 texture data to RGBA8.
///
/// Each pixel is a big-endian `u16`:
/// - bits `[15:11]` = R (5 bits)
/// - bits `[10:6]`  = G (5 bits)
/// - bits `[5:1]`   = B (5 bits)
/// - bit  `[0]`     = A (1 bit)
///
/// 5-bit channels are expanded to 8 bits via `(v << 3) | (v >> 2)`.
/// Alpha is 0 or 255.
pub fn rgba16_to_rgba8(data: &[u8], width: usize, height: usize) -> Vec<u8> {
    let pixel_count = width * height;
    let mut out = Vec::with_capacity(pixel_count * 4);

    for px in 0..pixel_count {
        let off = px * 2;
        if off + 1 >= data.len() {
            break;
        }
        let pixel = u16::from_be_bytes([data[off], data[off + 1]]);

        let r5 = ((pixel >> 11) & 0x1F) as u8;
        let g5 = ((pixel >> 6) & 0x1F) as u8;
        let b5 = ((pixel >> 1) & 0x1F) as u8;
        let a1 = (pixel & 0x1) as u8;

        out.push((r5 << 3) | (r5 >> 2));
        out.push((g5 << 3) | (g5 >> 2));
        out.push((b5 << 3) | (b5 >> 2));
        out.push(if a1 != 0 { 255 } else { 0 });
    }

    out
}

// ── ROM offset constants ──────────────────────────────────────────────

/// MIO0 block offset for segment 2 (font + HUD icons) in the US ROM.
const SEG2_ROM_OFFSET: usize = 0x108A40;
/// MIO0 block offset for segment 3 (actors/common1 — power meter) in the US ROM.
const SEG3_ROM_OFFSET: usize = 0x201410;

// ── Texture offsets within decompressed segments ──────────────────────

// Segment 2: 16×16 RGBA16 textures (512 bytes each).
const TEX_DIGIT_OFFSETS: [usize; 10] = [
    0x00000, // 0
    0x00200, // 1
    0x00400, // 2
    0x00600, // 3
    0x00800, // 4
    0x00A00, // 5
    0x00C00, // 6
    0x00E00, // 7
    0x01000, // 8
    0x01200, // 9
];
const TEX_MULTIPLY_OFFSET: usize = 0x05600;
const TEX_COIN_OFFSET: usize = 0x05800;
const TEX_MARIO_HEAD_OFFSET: usize = 0x05A00;
const TEX_STAR_OFFSET: usize = 0x05C00;

// Segment 3: power meter textures.
const TEX_PM_LEFT_OFFSET: usize = 0x233E0; // 32×64 RGBA16 = 4096 bytes
const TEX_PM_RIGHT_OFFSET: usize = 0x243E0; // 32×64 RGBA16 = 4096 bytes

// 8 power-meter segment textures (32×32 RGBA16 = 2048 bytes each).
// Index 0 = 1 wedge, index 7 = 8 wedges (full).
const TEX_PM_SEGMENT_OFFSETS: [usize; 8] = [
    0x28BE0, // 1 wedge
    0x283E0, // 2 wedges
    0x27BE0, // 3 wedges
    0x273E0, // 4 wedges
    0x26BE0, // 5 wedges
    0x263E0, // 6 wedges
    0x25BE0, // 7 wedges
    0x253E0, // 8 wedges (full)
];

// Texture dimensions.
const SMALL: usize = 16; // icons & digits
const PM_HALF_W: usize = 32;
const PM_HALF_H: usize = 64;
const PM_SEG: usize = 32;


// ── HudTextures struct ────────────────────────────────────────────────

/// HUD textures extracted from a US SM64 ROM, all in RGBA8 format ready
/// for upload to a GPU texture or use with egui.
#[derive(Debug, Clone)]
pub struct HudTextures {
    /// Power meter base left half (32×64, RGBA8).
    pub power_meter_left: Vec<u8>, // 8192 bytes
    /// Power meter base right half (32×64, RGBA8).
    pub power_meter_right: Vec<u8>, // 8192 bytes
    /// 8 health segment textures (32×32 each, RGBA8).
    /// Index 0 = 1 wedge, index 7 = 8 wedges (full).
    pub power_meter_segments: [Vec<u8>; 8], // each 4096 bytes
    /// Coin icon (16×16, RGBA8).
    pub coin_icon: Vec<u8>, // 1024 bytes
    /// Star icon (16×16, RGBA8).
    pub star_icon: Vec<u8>, // 1024 bytes
    /// Mario head icon (16×16, RGBA8) — used for lives display.
    pub mario_head: Vec<u8>, // 1024 bytes
    /// "×" multiply icon (16×16, RGBA8) — used between icon and count.
    pub multiply: Vec<u8>, // 1024 bytes
    /// Digits 0–9 (16×16 each, RGBA8) — the colorful HUD font.
    pub digits: [Vec<u8>; 10], // each 1024 bytes
}

impl HudTextures {
    /// Extract all HUD textures from a US SM64 ROM.
    ///
    /// The ROM must contain valid MIO0 blocks at the known US-ROM offsets
    /// for segment 2 (`0x108A40`) and segment 3 (`0x201410`).
    pub fn from_rom(rom: &[u8]) -> Result<Self, HudTextureError> {
        // Helper: slice an MIO0 block starting at `offset` out of the ROM
        // and decompress it. We don't know the block's total size ahead of
        // time, so we pass the entire tail of the ROM — `mio0_decode`
        // only reads as far as the header-specified offsets require.
        fn decode_segment(rom: &[u8], offset: usize) -> Result<Vec<u8>, HudTextureError> {
            if offset >= rom.len() {
                return Err(HudTextureError::InvalidRom);
            }
            mio0_decode(&rom[offset..])
        }

        // Helper: extract a single RGBA16 texture and convert to RGBA8.
        fn extract(
            seg: &[u8],
            offset: usize,
            width: usize,
            height: usize,
            label: &str,
        ) -> Result<Vec<u8>, HudTextureError> {
            let byte_len = width * height * 2;
            let end = offset
                .checked_add(byte_len)
                .ok_or(HudTextureError::InvalidRom)?;
            if end > seg.len() {
                return Err(HudTextureError::Mio0Decode(format!(
                    "{label} at 0x{offset:X} extends past segment end ({} bytes)",
                    seg.len()
                )));
            }
            Ok(rgba16_to_rgba8(&seg[offset..end], width, height))
        }

        let seg2 = decode_segment(rom, SEG2_ROM_OFFSET)?;
        let seg3 = decode_segment(rom, SEG3_ROM_OFFSET)?;

        // ── Segment 2: digits ──
        let mut digits: [Vec<u8>; 10] = Default::default();
        for (i, &off) in TEX_DIGIT_OFFSETS.iter().enumerate() {
            digits[i] = extract(&seg2, off, SMALL, SMALL, &format!("digit {i}"))?;
        }

        // ── Segment 2: icons ──
        let multiply = extract(&seg2, TEX_MULTIPLY_OFFSET, SMALL, SMALL, "multiply")?;
        let coin_icon = extract(&seg2, TEX_COIN_OFFSET, SMALL, SMALL, "coin")?;
        let mario_head = extract(&seg2, TEX_MARIO_HEAD_OFFSET, SMALL, SMALL, "mario_head")?;
        let star_icon = extract(&seg2, TEX_STAR_OFFSET, SMALL, SMALL, "star")?;

        // ── Segment 3: power meter halves ──
        let power_meter_left =
            extract(&seg3, TEX_PM_LEFT_OFFSET, PM_HALF_W, PM_HALF_H, "pm_left")?;
        let power_meter_right =
            extract(&seg3, TEX_PM_RIGHT_OFFSET, PM_HALF_W, PM_HALF_H, "pm_right")?;

        // ── Segment 3: power meter segments (1..8 wedges) ──
        let mut power_meter_segments: [Vec<u8>; 8] = Default::default();
        for (i, &off) in TEX_PM_SEGMENT_OFFSETS.iter().enumerate() {
            power_meter_segments[i] =
                extract(&seg3, off, PM_SEG, PM_SEG, &format!("pm_seg {i}"))?;
        }

        Ok(HudTextures {
            power_meter_left,
            power_meter_right,
            power_meter_segments,
            coin_icon,
            star_icon,
            mario_head,
            multiply,
            digits,
        })
    }
}

// ── Tests ─────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    /// End-to-end extraction test against a real US ROM.
    ///
    /// Marked `#[ignore]` so it doesn't run in CI without a ROM present.
    /// Run manually with:
    /// ```sh
    /// cargo test -p vox-sm64 hud_textures::tests::test_hud_textures_from_rom -- --ignored
    /// ```
    #[test]
    #[ignore]
    fn test_hud_textures_from_rom() {
        let rom_path = "C:/tmp/voxel-engine/roms/baserom.us.z64";
        let rom = std::fs::read(rom_path)
            .unwrap_or_else(|_| panic!("expected ROM at {rom_path}"));

        let hud = HudTextures::from_rom(&rom).expect("from_rom should succeed");

        // Power meter halves: 32×64×4 = 8192 bytes.
        assert_eq!(
            hud.power_meter_left.len(),
            8192,
            "power_meter_left size"
        );
        assert_eq!(
            hud.power_meter_right.len(),
            8192,
            "power_meter_right size"
        );

        // Power meter segments: 32×32×4 = 4096 bytes each.
        for (i, seg) in hud.power_meter_segments.iter().enumerate() {
            assert_eq!(seg.len(), 4096, "power_meter_segments[{i}] size");
        }

        // Small icons: 16×16×4 = 1024 bytes each.
        assert_eq!(hud.coin_icon.len(), 1024, "coin_icon size");
        assert_eq!(hud.star_icon.len(), 1024, "star_icon size");
        assert_eq!(hud.mario_head.len(), 1024, "mario_head size");
        assert_eq!(hud.multiply.len(), 1024, "multiply size");

        // Digits: 16×16×4 = 1024 bytes each.
        for (i, d) in hud.digits.iter().enumerate() {
            assert_eq!(d.len(), 1024, "digit[{i}] size");
        }
    }

    /// Verify the RGBA16→RGBA8 conversion for known pixel values.
    #[test]
    fn test_rgba16_conversion() {
        // Fully opaque white: R=31, G=31, B=31, A=1 → 0xFFFF.
        let white = [0xFF, 0xFFu8];
        let w = rgba16_to_rgba8(&white, 1, 1);
        assert_eq!(w, [255, 255, 255, 255]);

        // Fully transparent black: 0x0000.
        let black = [0x00, 0x00u8];
        let b = rgba16_to_rgba8(&black, 1, 1);
        assert_eq!(b, [0, 0, 0, 0]);

        // Mid red: R=16(0b10000), G=0, B=0, A=1.
        // Pixel = 10000_00000_00000_1 = 0x8001.
        let red = [0x80, 0x01u8];
        let r = rgba16_to_rgba8(&red, 1, 1);
        // (16 << 3) | (16 >> 2) = 128 | 4 = 132
        assert_eq!(r, [132, 0, 0, 255]);
    }

    /// MIO0 decode should reject bad magic.
    #[test]
    fn test_mio0_bad_magic() {
        let bad = [0u8; 32];
        assert!(matches!(
            mio0_decode(&bad),
            Err(HudTextureError::Mio0Decode(_))
        ));
    }

    /// Decode a hand-crafted MIO0 block that uses both raw bytes and a
    /// backreference, verifying the decoder handles the LZ77 sliding
    /// window correctly.
    #[test]
    fn test_mio0_roundtrip_synthetic() {
        // Input to reconstruct: [A, B, A, B]  (4 bytes)
        // Strategy:
        //   bit 0 = 1 (raw A)    → uncomp[0] = A
        //   bit 1 = 1 (raw B)    → uncomp[1] = B
        //   bit 2 = 0 (backref)  → length=2, offset=2  (copy 2 bytes from -2)
        //
        // Backref encoding: length = ((b0 & 0xF0) >> 4) + 3, so length=2
        // → (2-3) is negative; we need length=2+3=5? No:
        // length = ((b0 >> 4) + 3), so for length=2 we'd need (b0>>4) = -1
        // which is impossible. Minimum backref length is 3.
        //
        // Revised input: [A, B, C, A, B, C]  (6 bytes)
        //   bit 0 = 1 (raw A)
        //   bit 1 = 1 (raw B)
        //   bit 2 = 1 (raw C)
        //   bit 3 = 0 (backref length=3 offset=3 → copy ABC from -3)
        //
        // Backref bytes: length-3 = 0 → upper nibble = 0
        // offset-1 = 2 → 0x0002 split as (0x00, 0x02)
        // So comp = [0x00, 0x02]

        let dest_size: u32 = 6;
        // Layout: header(16) + bits(1 byte, padded to 4) + comp(2) + uncomp(3)
        // bit_length = (4 + 7) / 8 = 1 byte
        // comp_offset = align(16 + 1, 4) = 20
        // uncomp_offset = 20 + 2 = 22
        // total = 22 + 3 = 25

        let mut block = vec![0u8; 25];
        // Header
        block[0..4].copy_from_slice(b"MIO0");
        block[4..8].copy_from_slice(&dest_size.to_be_bytes()); // dest_size
        block[8..12].copy_from_slice(&20u32.to_be_bytes()); // comp_offset
        block[12..16].copy_from_slice(&22u32.to_be_bytes()); // uncomp_offset

        // Bit stream at offset 16: bits = 1,1,1,0 (MSB first in byte)
        // byte = 0b11100000 = 0xE0
        block[16] = 0xE0;

        // Compressed data at offset 20: [0x00, 0x02] → length=3, offset=3
        block[20] = 0x00;
        block[21] = 0x02;

        // Uncompressed data at offset 22: [A, B, C] = [0xAA, 0xBB, 0xCC]
        block[22] = 0xAA;
        block[23] = 0xBB;
        block[24] = 0xCC;

        let decoded = mio0_decode(&block).expect("decode should succeed");
        assert_eq!(decoded, [0xAA, 0xBB, 0xCC, 0xAA, 0xBB, 0xCC]);
    }
}
