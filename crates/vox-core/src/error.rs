//! Typed errors shared across engine crates.

/// Errors produced by vox-core: configuration validation and asset loading.
#[derive(Debug, thiserror::Error)]
pub enum CoreError {
    /// A [`WorldConfig`](crate::config::WorldConfig) field failed validation.
    #[error("invalid config field `{field}`: {reason}")]
    Config {
        /// Name of the offending configuration field.
        field: &'static str,
        /// Human-readable explanation of the failure.
        reason: String,
    },
    /// An asset file could not be loaded or parsed.
    #[error("failed to load asset `{path}`: {reason}")]
    Asset {
        /// Path of the asset that failed to load.
        path: String,
        /// Human-readable explanation of the failure.
        reason: String,
    },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn config_display_names_the_field() {
        let err = CoreError::Config {
            field: "voxel_size_m",
            reason: "must be positive".to_string(),
        };
        let msg = err.to_string();
        assert!(msg.contains("voxel_size_m"), "must name the field: {msg}");
        assert!(
            msg.contains("must be positive"),
            "must keep the reason: {msg}"
        );
    }

    #[test]
    fn asset_display_names_the_path() {
        let err = CoreError::Asset {
            path: "assets/materials.toml".to_string(),
            reason: "missing key `albedo`".to_string(),
        };
        let msg = err.to_string();
        assert!(
            msg.contains("assets/materials.toml"),
            "must name the path: {msg}"
        );
        assert!(
            msg.contains("missing key `albedo`"),
            "must keep the reason: {msg}"
        );
    }
}
