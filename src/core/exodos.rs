use crate::core::models::Rom;
use std::path::Path;
use uuid::Uuid;
use chrono;

pub struct ExoDosManager;

impl ExoDosManager {
    /// Scans a directory for ExoDOS games.
    /// The base_path is the folder selected by the user.
    /// We expect to find eXo/eXoDOS/!dos/ within it.
    pub fn scan_directory(base_path: &Path) -> Vec<Rom> {
        let mut roms = Vec::new();
        let dos_path = base_path.join("eXo/eXoDOS/!dos");
        
        log::info!("Scanning ExoDOS directory: {:?}", dos_path);

        if !dos_path.exists() {
            log::warn!("ExoDOS path not found: {:?}", dos_path);
            return roms;
        }

        // Each subfolder in !dos is a game
        if let Ok(entries) = std::fs::read_dir(&dos_path) {
            for entry in entries.flatten() {
                if let Ok(file_type) = entry.file_type() {
                    if file_type.is_dir() {
                        let game_dir = entry.path();
                        // Each game dir has a .command file
                        if let Ok(game_entries) = std::fs::read_dir(&game_dir) {
                            for game_entry in game_entries.flatten() {
                                let path = game_entry.path();
                                if path.extension().and_then(|s| s.to_str()) == Some("command") {
                                    let filename = path.file_name().unwrap_or_default().to_string_lossy().to_string();
                                    if filename.to_lowercase() == "install.command" {
                                        continue;
                                    }

                                    let mut title = path.file_stem().and_then(|s| s.to_str()).unwrap_or("Unknown Game").to_string();
                                    
                                    // Remove (Year) from title
                                    if let Some(pos) = title.find(" (") {
                                        if title.ends_with(')') {
                                            let potential_year = &title[pos + 2..title.len() - 1];
                                            if potential_year.chars().all(|c| c.is_ascii_digit()) && potential_year.len() == 4 {
                                                title = title[..pos].to_string();
                                            }
                                        }
                                    }

                                    roms.push(Rom {
                                        id: format!("exodos-{}", Uuid::new_v4()),
                                        platform_id: "dos".to_string(), // Default platform ID
                                        path: path.to_string_lossy().to_string(),
                                        filename: path.file_name().unwrap_or_default().to_string_lossy().to_string(),
                                        file_size: 0,
                                        hash_sha1: None,
                                        title: Some(title),
                                        region: None,
                                        platform_name: Some("DOS".to_string()),
                                        platform_type: Some("DOS".to_string()),
                                        platform_icon: Some("dos".to_string()),
                                        boxart_path: None,
                                        icon_path: None,
                                        background_path: None,
                                        date_added: Some(chrono::Utc::now().timestamp()),
                                        play_count: Some(0),
                                        total_play_time: Some(0),
                                        last_played: None,
                                        is_favorite: Some(false),
                                        genre: None,
                                        developer: None,
                                        publisher: None,
                                        rating: None,
                                        tags: Some("ExoDOS".to_string()),
                                        release_date: None,
                                        description: None,
                                        is_installed: Some(true),
                                        cloud_saves_supported: None,
                                    });
                                }
                            }
                        }
                    }
                }
            }
        }

        roms
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs::{self, File};
    use tempfile::tempdir;

    #[test]
    fn test_exodos_scanner() {
        let dir = tempdir().unwrap();
        let root = dir.path();
        
        // Create ExoDOS structure: eXo/eXoDOS/!dos/GameName/GameName.command
        let dos_path = root.join("eXo/eXoDOS/!dos");
        fs::create_dir_all(&dos_path).unwrap();
        
        let game1_dir = dos_path.join("Digger (1983)");
        fs::create_dir(&game1_dir).unwrap();
        File::create(game1_dir.join("Digger (1983).command")).unwrap();
        File::create(game1_dir.join("readme.txt")).unwrap();
        
        let game2_dir = dos_path.join("Zork I (1980)");
        fs::create_dir(&game2_dir).unwrap();
        File::create(game2_dir.join("Zork I (1980).command")).unwrap();
        File::create(game2_dir.join("install.command")).unwrap();

        let roms = ExoDosManager::scan_directory(root);
        
        assert_eq!(roms.len(), 2);
        let titles: Vec<String> = roms.iter().map(|r| r.title.clone().unwrap()).collect();
        assert!(titles.contains(&"Digger".to_string()));
        assert!(titles.contains(&"Zork I".to_string()));
        assert!(!titles.contains(&"install".to_string()));
    }
}
