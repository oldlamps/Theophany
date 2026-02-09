use crate::core::db::DbManager;
use crate::core::paths;
use rusqlite::params;
use std::path::Path;

pub fn scan_game_assets(db: &DbManager, rom_id: &str) -> Result<(), Box<dyn std::error::Error>> {
    let conn = db.get_connection();
    
    // 1. Get Platform & Filename info from DB
    let mut stmt = conn.prepare("
        SELECT p.platform_type, p.name, r.filename 
        FROM roms r 
        JOIN platforms p ON r.platform_id = p.id 
        WHERE r.id = ?1
    ")?;
    
    let (platform_type, platform_name, filename): (Option<String>, String, String) = stmt.query_row(params![rom_id], |row| {
        Ok((row.get(0)?, row.get(1)?, row.get(2)?))
    })?;
    
    // 2. Determine paths
    let platform_folder = platform_type.or(Some(platform_name)).unwrap_or("Unknown".to_string());
    // Sanitize to match Scraper/Convention
    let platform_folder = platform_folder.replace("/", "-").replace("\\", "-");
    
    let rom_stem = Path::new(&filename)
        .file_stem()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or(filename.clone());
        
    let data_dir = paths::get_data_dir();
    let assets_base = data_dir.join("Images").join(&platform_folder).join(&rom_stem);
    
    // 3. Scan Filesystem
    let mut found_assets: Vec<(String, String)> = Vec::new();
    let mut boxart_path: Option<String> = None;
    let mut icon_path: Option<String> = None;
    let mut background_path: Option<String> = None;
    
    if assets_base.exists() {
        if let Ok(entries) = std::fs::read_dir(assets_base) {
            for entry in entries.flatten() {
                if let Ok(ft) = entry.file_type() {
                    if ft.is_dir() {
                        let asset_type = entry.file_name().to_string_lossy().to_string();
                        if let Ok(files) = std::fs::read_dir(entry.path()) {
                            for file in files.flatten() {
                                if let Ok(fft) = file.file_type() {
                                    if fft.is_file() || fft.is_symlink() {
                                        let path_str = file.path().to_string_lossy().to_string();
                                        found_assets.push((asset_type.clone(), path_str.clone()));
                                        
                                        // Cache logic
                                        if asset_type == "Box - Front" && boxart_path.is_none() {
                                            boxart_path = Some(path_str.clone());
                                        }
                                        if asset_type == "Icon" && icon_path.is_none() {
                                            icon_path = Some(path_str.clone());
                                        }
                                         if (asset_type == "Background" || asset_type == "Fanart - Background") && background_path.is_none() {
                                             background_path = Some(path_str.clone());
                                         }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // 4. Update Database Transactionally
    // We can't use db.execute_batch easily with params, so we do manual transaction control relative to our connection, 
    // or just separate statements. Since DbManager exposes get_connection, we can do it.
    
    conn.execute("BEGIN IMMEDIATE", [])?;
    
    // Clear old assets
    conn.execute("DELETE FROM assets WHERE rom_id = ?1", params![rom_id])?;
    
    // Insert new assets
    let mut insert_stmt = conn.prepare("INSERT INTO assets (rom_id, type, local_path) VALUES (?1, ?2, ?3)")?;
    for (atype, path) in found_assets {
        insert_stmt.execute(params![rom_id, atype, path])?;
    }
    
    // Update Roms Cache
    // We only update if we found something, or should we clear it if not found?
    // "Smart" update: If we scanned and found nothing, maybe we should clear the cache? 
    // Yes, explicit sync means "make DB match FS". So if FS is empty, DB should be empty.
    
    conn.execute("UPDATE roms SET boxart_path = ?1, icon_path = ?2, background_path = ?3 WHERE id = ?4", 
        params![boxart_path, icon_path, background_path, rom_id])?;
        
    conn.execute("COMMIT", [])?;
    
    Ok(())
}
