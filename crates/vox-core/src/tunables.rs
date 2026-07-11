//! Live-tunable engine parameters, exposed to the debug overlay.
//!
//! These mirror a subset of [`crate::consts`] but are runtime-mutable: each
//! consuming system (the physics solver, the player controller, the blast
//! tool) reads its own copy each frame rather than the compile-time
//! constant, so a debug-overlay slider takes effect immediately.

use crate::consts;

/// Runtime-adjustable engine parameters. Defaults match the compile-time
/// constants in [`crate::consts`].
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Tunables {
    /// Coulomb friction coefficient (μ) for rigidbody contacts.
    pub friction: f32,
    /// Baumgarte positional-correction factor for contacts.
    pub contact_beta: f32,
    /// Linear speed below which a body may sleep, in m/s.
    pub sleep_lin: f32,
    /// Angular speed below which a body may sleep, in rad/s.
    pub sleep_ang: f32,
    /// Blast impulse base strength.
    pub blast_power: f32,
    /// Noclip/fly speed in m/s.
    pub fly_speed: f32,
    /// Impact speed (m/s) a strength-1.0 material can just barely survive
    /// before an impact fractures it; a material's actual threshold is this
    /// *multiplied* by its own `strength` -- the same "higher survives more"
    /// convention every other destruction tool uses (see
    /// `MaterialDef::strength`'s doc comment). Higher `fracture_sensitivity`
    /// raises every material's threshold uniformly (tougher overall, less
    /// sensitive to impacts); it doesn't change materials' *relative*
    /// toughness to each other, which comes entirely from `strength`.
    pub fracture_sensitivity: f32,
}

impl Default for Tunables {
    fn default() -> Self {
        Self {
            friction: consts::FRICTION,
            contact_beta: consts::CONTACT_BETA,
            sleep_lin: consts::SLEEP_LIN,
            sleep_ang: consts::SLEEP_ANG,
            blast_power: 40.0,
            fly_speed: 12.0,
            // With the core material set (leaves 0.5, wood 4.0, stone 8.0),
            // this gives fracture thresholds of 0.5 / 4.0 / 8.0 m/s: leaves
            // give way at the slightest bump, wood needs a real fall or
            // throw, stone needs a genuinely hard impact.
            fracture_sensitivity: 1.0,
        }
    }
}

impl Tunables {
    /// Check that all parameters are within physically valid ranges.
    /// Returns `Err` with a message naming the first violation.
    pub fn validate(&self) -> Result<(), String> {
        if !(0.0..=1.0).contains(&self.contact_beta) {
            return Err(format!(
                "contact_beta must be in [0, 1], got {}",
                self.contact_beta
            ));
        }
        if self.friction < 0.0 {
            return Err(format!("friction must be >= 0, got {}", self.friction));
        }
        if self.sleep_lin < 0.0 {
            return Err(format!("sleep_lin must be >= 0, got {}", self.sleep_lin));
        }
        if self.sleep_ang < 0.0 {
            return Err(format!("sleep_ang must be >= 0, got {}", self.sleep_ang));
        }
        if self.blast_power < 0.0 {
            return Err(format!(
                "blast_power must be >= 0, got {}",
                self.blast_power
            ));
        }
        if self.fly_speed < 0.0 {
            return Err(format!("fly_speed must be >= 0, got {}", self.fly_speed));
        }
        if self.fracture_sensitivity < 0.0 {
            return Err(format!(
                "fracture_sensitivity must be >= 0, got {}",
                self.fracture_sensitivity
            ));
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_match_engine_constants() {
        let t = Tunables::default();
        assert_eq!(t.friction, consts::FRICTION);
        assert_eq!(t.contact_beta, consts::CONTACT_BETA);
        assert_eq!(t.sleep_lin, consts::SLEEP_LIN);
        assert_eq!(t.sleep_ang, consts::SLEEP_ANG);
    }
}
