use crate::core::models::Rom;
use std::path::Path;
use uuid::Uuid;
use walkdir::WalkDir;

pub struct Scanner;

impl Scanner {
    /// Recursively scans a directory for files matching the given extensions.
    ///
    /// # Arguments
    /// * `platform_id` - The ID of the platform these ROMs belong to.
    /// * `scan_path` - The root directory to scan.
    /// * `extensions` - A list of allowed file extensions (e.g., ["iso", "cso"]).
    ///
    /// Returns a vector of potential `Rom` objects.
    pub fn scan_directory(
        platform_id: &str,
        scan_path: &Path,
        extensions: &[&str],
        recursive: bool,
    ) -> Vec<Rom> {
        let mut roms = Vec::new();

        let walker = if recursive {
            WalkDir::new(scan_path).follow_links(true)
        } else {
            WalkDir::new(scan_path).max_depth(1).follow_links(true)
        };

        for entry in walker.into_iter().filter_map(|e| e.ok()) {
            let path = entry.path();
            if path.is_file() || path.is_symlink() {
                if let Some(ext) = path.extension().and_then(|s| s.to_str()) {
                    if extensions.contains(&ext.to_lowercase().as_str()) {
                        let filename = path
                            .file_name()
                            .and_then(|s| s.to_str())
                            .unwrap_or_default()
                            .to_string();

                        // For performance, we might want to delay hashing until import time or run it async.
                        // For now, we'll set it to None and let the importer handle it.
                        let file_size = entry.metadata().map(|m| m.len()).unwrap_or(0) as i64;
                        // let hash = Hasher::calculate_sha1(path).ok(); 

                        roms.push(Rom {
                            id: Uuid::new_v4().to_string(),
                            platform_id: platform_id.to_string(),
                            path: path.to_string_lossy().to_string(),
                            filename,
                            file_size,
                            hash_sha1: None, // Calculated later to keep UI responsive during scan
                            title: None,
                            region: None,
                            platform_name: None,
                            platform_type: None,
                            boxart_path: None,
                            date_added: None,
                            play_count: None,
                            total_play_time: None,
                            last_played: None,
                            platform_icon: None,
                            is_favorite: None,
                            genre: None,
                            developer: None,
                            publisher: None,
                            rating: None,
                            tags: None,
                            icon_path: None,
                            background_path: None,
                            release_date: None,
                            description: None,
                            is_installed: Some(true),
                        });
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
    fn test_scanner_finds_roms() {
        let dir = tempdir().unwrap();
        let root = dir.path();
        
        // Create dummy structure
        fs::create_dir(root.join("snes")).unwrap();
        File::create(root.join("snes/mario.sfc")).unwrap(); // Should find
        File::create(root.join("snes/zelda.smc")).unwrap(); // Should find
        File::create(root.join("snes/readme.txt")).unwrap(); // Should ignore

        let roms = Scanner::scan_directory("snes_id", root, &["sfc", "smc"], true);
        
        assert_eq!(roms.len(), 2);
        let filenames: Vec<String> = roms.iter().map(|r| r.filename.clone()).collect();
        assert!(filenames.contains(&"mario.sfc".to_string()));
        assert!(filenames.contains(&"zelda.smc".to_string()));
    }
}
