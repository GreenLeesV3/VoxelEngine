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
        }
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
