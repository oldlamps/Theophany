use crate::core::models::Rom;
use crate::core::paths::get_data_dir;
use std::path::{Path, PathBuf};
use std::fs;
use std::os::unix::fs::symlink;
use walkdir::WalkDir;
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
                                        platform_id: "DOS".to_string(), 
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

    /// Creates symbolic links for the artwork of a game.
    /// title: The title of the game (as used in ExoDOS filenames).
    /// images_base_path: The base path for ExoDOS images (e.g., .../Images/MS-DOS/).
    /// platform_folder: The folder name for the platform (e.g., "dos").
    /// rom_stem: The filename stem of the game (e.g., "Digger").
    pub fn link_artwork(title: &str, images_base_path: &Path, platform_folder: &str, rom_stem: &str) {
        let base_assets_dir = get_data_dir().join("Images").join(platform_folder).join(rom_stem);
        
        let mappings = [
            ("Box - Front", "Box - Front"),
            ("Box - Back", "Box - Back"),
            ("Box - 3D", "Box - 3D"),
            ("Screenshot - Gameplay", "Screenshot"),
            ("Screenshot - Game Title", "Screenshot"),
            ("Fanart - Background", "Background"),
            ("Clear Logo", "Logo"),
        ];

        log::info!("Linking artwork for {} from {:?} to {:?}", title, images_base_path, base_assets_dir);

        for (exo_cat, target_cat) in mappings {
            let cat_path = images_base_path.join(exo_cat);
            if !cat_path.exists() {
                continue;
            }

            let dest_dir = base_assets_dir.join(target_cat);
            if !dest_dir.exists() {
                let _ = fs::create_dir_all(&dest_dir);
            }

            // We use the normalized target name for the final symlink filename
            let norm_name = target_cat.to_lowercase().replace(" ", "_");

            for entry in WalkDir::new(&cat_path).into_iter().flatten() {
                if entry.file_type().is_file() {
                    let path = entry.path();
                    let file_name = path.file_name().unwrap_or_default().to_string_lossy();
                    
                    if file_name.starts_with(title) {
                        let extension = path.extension().and_then(|e| e.to_str()).unwrap_or("jpg");
                        
                        // Check if we already have a file for this target category from a previous match
                        // (e.g. if we already linked Gameplay screenshot, we might not want to overwrite it with Title screenshot)
                        // Actually, for screenshots it's fine to have multiple, but our current system expects 
                        // a single {target_cat}.ext in the folder.
                        let target_path = dest_dir.join(format!("{}.{}", norm_name, extension));
                        
                        if !target_path.exists() {
                            log::debug!("Linking artwork: {:?} -> {:?}", path, target_path);
                            #[cfg(unix)]
                            if let Err(e) = symlink(path, &target_path) {
                                log::error!("Failed to create symlink: {}", e);
                            }
                            #[cfg(not(unix))]
                            if let Err(e) = fs::copy(path, &target_path) {
                                log::error!("Failed to copy artwork: {}", e);
                            }
                            
                            // If it's a screenshot or background, we might have multiple files.
                            // But for simplicity of the initial import, we break after the first match per Exo category.
                            // Since we have multiple Exo categories mapping to one target, we'll get one file from each source folder if it exists.
                            break; 
                        }
                    }
                }
            }
        }
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
        assert!(roms.iter().all(|r| r.platform_id == "DOS"));
    }
}
