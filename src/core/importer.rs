use crate::core::db::DbManager;
use crate::core::models::{Rom, GameMetadata, GameResource};
use crate::core::metadata_manager::MetadataManager;
use crate::core::paths;
use std::path::Path;
use std::fs;
use uuid::Uuid;

pub struct BulkImporter;

impl BulkImporter {
    pub fn import_roms<F>(
        db: &DbManager,
        roms: Vec<Rom>,
        platform_id: &str,
        save_assets_locally: bool,
        progress_callback: F,
    ) -> Result<usize, Box<dyn std::error::Error>>
    where
        F: Fn(usize, usize, String),
    {
        let platform = db.get_platform(platform_id)?
            .ok_or_else(|| format!("Platform {} not found", platform_id))?;
        
        let platform_folder = platform.platform_type.clone()
            .or(Some(platform.name.clone()))
            .unwrap_or_else(|| "Unknown".to_string());
        
        let sanitized_platform_folder = platform_folder.replace("/", "-").replace("\\", "-");
        let total = roms.len();
        let mut success_count = 0;

        let existing_ids = db.get_rom_ids_by_platform(platform_id).unwrap_or_default();

        let mut asset_tasks = Vec::new();
        // forced_symlink_ids logic was removed
        // let mut forced_symlink_ids = std::collections::HashSet::new();

        // BEGIN TRANSACTION
        let _ = db.get_connection().execute("BEGIN TRANSACTION", []);

        for (i, rom) in roms.iter().enumerate() {
            let mut final_rom = rom.clone();
            final_rom.platform_id = platform_id.to_string();

            if existing_ids.contains(&rom.id) {
                log::info!("[BulkImporter] ROM already exists, checking assets: {}", rom.id);
            } else {
                if let Err(e) = db.insert_rom(&final_rom) {
                    log::error!("[BulkImporter] Failed to insert ROM {}: {}", final_rom.id, e);
                    continue;
                }

                // 1. Metadata
                let mut meta = GameMetadata::default();
                meta.rom_id = final_rom.id.clone();
                meta.title = final_rom.title.clone();
                meta.tags = final_rom.tags.clone();
                meta.developer = final_rom.developer.clone();
                meta.genre = final_rom.genre.clone();
                meta.description = final_rom.description.clone();
                
                if let Some(played) = final_rom.last_played {
                    meta.last_played = Some(played);
                }
                if let Some(total_time) = final_rom.total_play_time {
                    meta.total_play_time = total_time;
                }
                meta.is_installed = final_rom.is_installed.unwrap_or_else(|| {
                    if final_rom.id.starts_with("steam-") {
                        crate::core::store::StoreManager::get_local_steam_appids().contains(&final_rom.id.replace("steam-", ""))
                    } else if final_rom.id.starts_with("legendary-") {
                        // For legendary, if it's not explicitly marked, it might be from a cloud scan
                        // We default to false for store platforms if unknown during bulk import
                        false
                    } else {
                        // Generic ROMs (SNES, etc) are assumed to be "installed" (existent)
                        true
                    }
                });

                // Sidecar Recovery
                let mut rom_stem_temp = Path::new(&final_rom.filename)
                    .file_stem()
                    .and_then(|s| s.to_str())
                    .unwrap_or(&final_rom.filename)
                    .to_string();
                
                if final_rom.id.starts_with("steam-") {
                    rom_stem_temp = final_rom.id.replace("steam-", "");
                }

                if let Some(mut sidecar) = MetadataManager::load_sidecar(&platform_folder, &rom_stem_temp) {
                    sidecar.rom_id = final_rom.id.clone();
                    // Preserving local status: if the incoming ROM has an explicit is_installed, keep it.
                    // Sidecars might have stale "installed=true" from previous defaults.
                    if final_rom.is_installed.is_some() {
                        sidecar.is_installed = meta.is_installed;
                    }
                    meta = sidecar;
                    
                    // Ensure resources from sidecar are correctly associated with the new rom_id
                    if let Some(ref mut resources) = meta.resources {
                        for r in resources {
                            r.rom_id = final_rom.id.clone();
                        }
                    }
                    if let Some(tags) = &meta.tags {
                        let _ = db.get_connection().execute("UPDATE roms SET tags = ?1 WHERE id = ?2", [tags, &final_rom.id]);
                    }
                }

                // 2. Resources (Steam specific defaults if not already present)
                if final_rom.id.starts_with("steam-") && meta.resources.as_ref().map_or(true, |r| r.is_empty()) {
                    if let Some(appid_str) = final_rom.id.strip_prefix("steam-") {
                        let base_url = format!("https://steamcommunity.com/app/{}", appid_str);
                        let mut steam_resources = Vec::new();
                        steam_resources.push(GameResource {
                            id: Uuid::new_v4().to_string(),
                            rom_id: final_rom.id.clone(),
                            type_: "generic".to_string(),
                            url: format!("https://store.steampowered.com/app/{}/", appid_str),
                            label: Some("Store Page".to_string()),
                        });
                        steam_resources.push(GameResource {
                            id: Uuid::new_v4().to_string(),
                            rom_id: final_rom.id.clone(),
                            type_: "generic".to_string(),
                            url: base_url.clone(),
                            label: Some("Community Hub".to_string()),
                        });
                        steam_resources.push(GameResource {
                            id: Uuid::new_v4().to_string(),
                            rom_id: final_rom.id.clone(),
                            type_: "generic".to_string(),
                            url: format!("{}/discussions/", base_url),
                            label: Some("Discussions".to_string()),
                        });
                        steam_resources.push(GameResource {
                            id: Uuid::new_v4().to_string(),
                            rom_id: final_rom.id.clone(),
                            type_: "generic".to_string(),
                            url: format!("{}/guides/", base_url),
                            label: Some("Guides".to_string()),
                        });
                        meta.resources = Some(steam_resources);
                    }
                }

                let _ = db.insert_metadata(&meta);
                let _ = MetadataManager::save_sidecar(&platform_folder, &rom_stem_temp, &meta);
            }

            // 3. Asset Task Collection (Always run, even for existing games)
            let rom_stem = if final_rom.id.starts_with("steam-") {
                final_rom.id.replace("steam-", "")
            } else {
                Path::new(&final_rom.filename)
                    .file_stem()
                    .and_then(|s| s.to_str())
                    .unwrap_or(&final_rom.filename)
                    .to_string()
            };

            let data_dir = paths::get_data_dir();
            let assets_base_dir = data_dir.join("Images").join(&sanitized_platform_folder).join(&rom_stem);

            if final_rom.id.starts_with("steam-") {
                let assets_to_collect = [
                    ("Icon", &final_rom.icon_path),
                    ("Box - Front", &final_rom.boxart_path),
                    ("Background", &final_rom.background_path),
                ];

                for (atype, path_opt) in assets_to_collect {
                    if let Some(src) = path_opt {
                        asset_tasks.push(AssetTask {
                            rom_id: final_rom.id.clone(),
                            asset_type: atype.to_string(),
                            src: src.clone(),
                            dest_base: assets_base_dir.clone(),
                            save_locally: true,
                        });
                    }
                }
            } else if final_rom.id.starts_with("heroic-") {
                let mut assets_to_collect = vec![
                    ("Box - Front", final_rom.boxart_path.clone()),
                    ("Icon", final_rom.icon_path.clone()),
                    ("Background", final_rom.background_path.clone()),
                ];

                // Heroic Epic Optimization: Use Box - Front task to handle BOTH Box and Icon symlinking
                if final_rom.id.starts_with("heroic-epic-") {
                    // Dedup: remove explicit Icon task to avoid race conditions
                    assets_to_collect.retain(|(t, _)| *t != "Icon");
                    
                    if let Some(local_icon) = &final_rom.icon_path {
                        if !local_icon.starts_with("http") && !save_assets_locally {
                             // Override Box Art with local icon if we aren't saving locally
                             assets_to_collect[0].1 = Some(local_icon.clone());
                        }
                    }
                }

                for (atype, path_opt) in assets_to_collect {
                    if let Some(src) = path_opt {
                        // Deduplication: if Icon URL is same as Boxart URL, we'll symlink it after Boxart is saved.
                        // With the override above, this might trigger if boxart was replaced by icon path.
                        // But since we want explicit symlinks for checks later, we might just let it process normally.
                        // But if both are local paths now, they will both be processed as local symlink tasks, which is fine.
                        
                        // We skip the dedup optimization for Heroic now to ensure robust individual symlinking
                        
                        asset_tasks.push(AssetTask {
                            rom_id: final_rom.id.clone(),
                            asset_type: atype.to_string(),
                            src: src.clone(),
                            dest_base: assets_base_dir.clone(),
                            save_locally: save_assets_locally,
                        });
                    }
                }
            }

            success_count += 1;
            progress_callback(i, total, final_rom.title.unwrap_or_default());
        }

        // COMMIT TRANSACTION for ROMs/Metadata
        let _ = db.get_connection().execute("COMMIT", []);

        // 4. Parallel Asset Processing
        if !asset_tasks.is_empty() {

            let mut handles = Vec::new();
            
            for task in asset_tasks {
                let handle = crate::core::runtime::get_runtime().spawn(async move {
                    task.execute().await
                });
                handles.push(handle);
            }

            // Wait for all downloads to finish and update DB
            // Wait for all downloads to finish and update DB
            crate::core::runtime::get_runtime().block_on(async {
                for handle in handles {
                    if let Ok(Some((rom_id, atype, path_str, src_path))) = handle.await {
                            // We need a fresh DB connection because we're in a different thread/async context
                            let db_path = paths::get_data_dir().join("games.db");
                            if let Ok(db) = DbManager::open(&db_path) {

                                 let _ = db.insert_asset(&rom_id, &atype, &path_str);
                                 let conn = db.get_connection();
                                 match atype.as_str() {
                                     "Box - Front" => { let _ = conn.execute("UPDATE roms SET boxart_path = ?1 WHERE id = ?2", [&path_str, &rom_id]); },
                                     "Icon" | "icon" | "Steam Icon" => { let _ = conn.execute("UPDATE roms SET icon_path = ?1 WHERE id = ?2", [&path_str, &rom_id]); },
                                     "Background" | "Fanart - Background" => { let _ = conn.execute("UPDATE roms SET background_path = ?1 WHERE id = ?2", [&path_str, &rom_id]); },
                                     _ => {}
                                 }

                                    // Heroic Symlink Logic: Use Boxart as Icon if a symlink is needed or missing
                                    // AND create a named symlink in Box - Front folder
                                    // STRICTLY for Epic Games
                                    if atype == "Box - Front" && rom_id.starts_with("heroic-epic-") {

                                        let box_path = Path::new(&path_str);
                                        
                                        // Determine the actual target for our symlinks.
                                        // If source is local, point directly to it.
                                        // If source is http, point to the downloaded file (box_path).
                                        let symlink_target = if src_path.starts_with("http") {
                                            box_path
                                        } else {
                                            Path::new(&src_path)
                                        };

                                        if let (Some(parent), Some(ext)) = (box_path.parent(), box_path.extension()) {
                                            if let Some(grandparent) = parent.parent() {
                                                // Fetch title from DB to use as filename
                                                let game_title: String = conn.query_row(
                                                    "SELECT title FROM roms WHERE id = ?1", 
                                                    [&rom_id], 
                                                    |r| r.get(0)
                                                ).unwrap_or_else(|_| grandparent.file_name().unwrap_or_default().to_string_lossy().to_string());

                                                let safe_title = game_title.replace("/", "_").replace("\\", "_").replace(":", "").trim().to_string();


                                                // 1. Box - Front Symlink: {Title}.{ext} -> TARGET
                                                let box_symlink_path = parent.join(format!("{}.{}", safe_title, ext.to_string_lossy()));
                                                let box_symlink_str = box_symlink_path.to_string_lossy().to_string();
                                                
                                                if box_symlink_path.symlink_metadata().is_ok() {
                                                    let _ = fs::remove_file(&box_symlink_path);
                                                }
                                                
                                                #[cfg(unix)]
                                                { 
                                                    let _res = std::os::unix::fs::symlink(symlink_target, &box_symlink_path); 

                                                }
                                                #[cfg(not(unix))]
                                                { let _ = fs::copy(symlink_target, &box_symlink_path); }

                                                // CLEANUP: Remove the standard 'box_-_front.jpg' if it's redundant/double
                                                // Only if we actually created the named symlink successfully
                                                if box_symlink_path.symlink_metadata().is_ok() && box_path.symlink_metadata().is_ok() && box_path != &box_symlink_path {
                                                     // We keep the named one, remove the generic one to avoid "double symlink" confusion
                                                     let _ = fs::remove_file(box_path);
                                                }

                                                // Update DB for Box - Front to point to the named symlink
                                                // We delete existing entries to avoid "phantom" blank entries from generic tasks
                                                let _ = db.delete_assets_by_type(&rom_id, "Box - Front");
                                                let _ = db.insert_asset(&rom_id, "Box - Front", &box_symlink_str);
                                                let _ = conn.execute("UPDATE roms SET boxart_path = ?1 WHERE id = ?2", [&box_symlink_str, &rom_id]);


                                                // 2. Icon Symlink: {Title}.{ext} -> TARGET
                                                let icon_dir = grandparent.join("Icon");
                                                let _ = fs::create_dir_all(&icon_dir);
                                                let icon_path = icon_dir.join(format!("{}.{}", safe_title, ext.to_string_lossy()));
                                                let icon_path_str = icon_path.to_string_lossy().to_string();
                                                
                                                // Clean up any old "icon.jpg" or existing target
                                                let old_icon_path = icon_dir.join(format!("icon.{}", ext.to_string_lossy()));
                                                if old_icon_path.symlink_metadata().is_ok() {
                                                    let _ = fs::remove_file(&old_icon_path);
                                                }
                                                if icon_path.symlink_metadata().is_ok() {
                                                     let _ = fs::remove_file(&icon_path);
                                                }

                                                #[cfg(unix)]
                                                { 
                                                    let _res = std::os::unix::fs::symlink(symlink_target, &icon_path);

                                                }
                                                #[cfg(not(unix))]
                                                { let _ = fs::copy(symlink_target, &icon_path); }
                                                
                                                // Always update the DB to point to the new icon path
                                                // Again, cleanup generic or previous icons
                                                let _ = db.delete_assets_by_type(&rom_id, "Icon");
                                                let _ = db.insert_asset(&rom_id, "Icon", &icon_path_str);
                                                let _ = conn.execute("UPDATE roms SET icon_path = ?1 WHERE id = ?2", [&icon_path_str, &rom_id]);
                                            }
                                        }
                                    }
                        }
                    }
                }
            });
        }

        Ok(success_count)
    }
}

struct AssetTask {
    rom_id: String,
    asset_type: String,
    src: String,
    dest_base: std::path::PathBuf,
    save_locally: bool,
}

impl AssetTask {
    async fn execute(self) -> Option<(String, String, String, String)> {
        let dest_dir = self.dest_base.join(&self.asset_type);
        let _ = fs::create_dir_all(&dest_dir);
        
        let ext = if self.src.contains(".png") { "png" } 
                 else if self.src.contains(".svg") { "svg" } 
                 else { "jpg" };
                 
        let filename = format!("{}.{}", self.asset_type.to_lowercase().replace(" ", "_"), ext);
        let dest_path = dest_dir.join(filename);

        if self.src.starts_with("http") {
            if !dest_path.symlink_metadata().is_ok() {
                // Use async reqwest for parallel downloads
                let client = reqwest::Client::new();
                if let Ok(resp) = client.get(&self.src).send().await {
                    if resp.status().is_success() {
                        if let Ok(bytes) = resp.bytes().await {
                            if fs::write(&dest_path, &bytes).is_ok() {
                                 return Some((self.rom_id, self.asset_type, dest_path.to_string_lossy().to_string(), self.src));
                            }
                        }
                    }
                }
            } else {
                return Some((self.rom_id, self.asset_type, dest_path.to_string_lossy().to_string(), self.src));
            }
        } else {
            let src_path = Path::new(&self.src);
            // Check for existence or symlink (even if dangling)
            if src_path.symlink_metadata().is_ok() {
                if !dest_path.symlink_metadata().is_ok() {
                    if self.save_locally {
                        let _ = fs::copy(src_path, &dest_path);
                    } else {
                        #[cfg(unix)]
                        {
                            let _ = std::os::unix::fs::symlink(src_path, &dest_path);
                        }
                        #[cfg(not(unix))]
                        {
                            let _ = fs::copy(src_path, &dest_path);
                        }
                    }
                }
                // Return original path even if it may be dangling (at least we have a local path in DB)
                if dest_path.symlink_metadata().is_ok() {
                    return Some((self.rom_id, self.asset_type, dest_path.to_string_lossy().to_string(), self.src));
                }
            }
        }
        None
    }
}
