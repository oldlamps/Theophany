use crate::core::models::GameMetadata;
use crate::core::paths;
use std::fs;

pub struct MetadataManager;

impl MetadataManager {
    pub fn save_sidecar(platform_folder: &str, rom_stem: &str, metadata: &GameMetadata) -> Result<(), Box<dyn std::error::Error>> {
        let metadata_dir = paths::get_metadata_dir();
        // Sanitize platform folder to avoid path traversal or illegal chars
        let sanitized_platform = platform_folder.replace("/", "-").replace("\\", "-");
        let target_dir = metadata_dir.join(sanitized_platform);
        
        if !target_dir.exists() {
            fs::create_dir_all(&target_dir)?;
        }
        
        let file_path = target_dir.join(format!("{}.json", rom_stem));
        let json = serde_json::to_string_pretty(metadata)?;
        fs::write(file_path, json)?;
        
        Ok(())
    }

    pub fn load_sidecar(platform_folder: &str, rom_stem: &str) -> Option<GameMetadata> {
        let metadata_dir = paths::get_metadata_dir();
        let sanitized_platform = platform_folder.replace("/", "-").replace("\\", "-");
        let file_path = metadata_dir.join(sanitized_platform).join(format!("{}.json", rom_stem));
        // println!("[MetadataManager] Loading sidecar from: {:?}", file_path);
        
        if file_path.exists() {
            if let Ok(content) = fs::read_to_string(file_path) {
                if let Ok(metadata) = serde_json::from_str::<GameMetadata>(&content) {
                    return Some(metadata);
                }
            }
        }
        None
    }

    pub fn delete_assets(platform_folder: &str, rom_stem: &str) -> Result<(), Box<dyn std::error::Error>> {
        // 1. Delete sidecar
        let metadata_dir = paths::get_metadata_dir();
        let sanitized_platform = platform_folder.replace("/", "-").replace("\\", "-");
        let sidecar_path = metadata_dir.join(&sanitized_platform).join(format!("{}.json", rom_stem));
        if sidecar_path.exists() {
            fs::remove_file(sidecar_path)?;
        }

        // 2. Delete Images folder
        let data_dir = paths::get_data_dir();
        let asset_dir = data_dir.join("Images").join(&sanitized_platform).join(rom_stem);
        if asset_dir.exists() && asset_dir.is_dir() {
            fs::remove_dir_all(asset_dir)?;
        }

        Ok(())
    }

    pub fn delete_platform_assets(platform_folder: &str) -> Result<(), Box<dyn std::error::Error>> {
        let sanitized_platform = platform_folder.replace("/", "-").replace("\\", "-");
        
        // 1. Delete sidecars
        let metadata_dir = paths::get_metadata_dir().join(&sanitized_platform);
        if metadata_dir.exists() && metadata_dir.is_dir() {
            fs::remove_dir_all(metadata_dir)?;
        }

        // 2. Delete Images folder
        let data_dir = paths::get_data_dir();
        let asset_dir = data_dir.join("Images").join(&sanitized_platform);
        if asset_dir.exists() && asset_dir.is_dir() {
            fs::remove_dir_all(asset_dir)?;
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::core::models::GameMetadata;

    #[test]
    fn test_sidecar_roundtrip() {
        let mut meta = GameMetadata::default();
        meta.rom_id = "test-rom".to_string();
        meta.title = Some("Test Game".to_string());
        meta.tags = Some("Tag1, Tag2".to_string());
        meta.is_favorite = true;
        
        let json = serde_json::to_string_pretty(&meta).unwrap();
        let deserialized: GameMetadata = serde_json::from_str(&json).unwrap();
        
        assert_eq!(deserialized.title, meta.title);
        assert_eq!(deserialized.tags, meta.tags);
        assert_eq!(deserialized.is_favorite, meta.is_favorite);
    }
}
