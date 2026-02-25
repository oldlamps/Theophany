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
                log::info!("[BulkImporter] ROM already exists, updating metadata: {}", rom.id);
                // Even if exists, we update metadata from the scan to catch enrichment (e.g. descriptions, developer)
                let mut meta = GameMetadata::default();
                meta.rom_id = final_rom.id.clone();
                meta.title = final_rom.title.clone();
                meta.developer = final_rom.developer.clone();
                meta.publisher = final_rom.publisher.clone();
                meta.genre = final_rom.genre.clone();
                meta.description = final_rom.description.clone();
                meta.tags = final_rom.tags.clone();
                meta.release_date = final_rom.release_date.clone();
                meta.cloud_saves_supported = final_rom.cloud_saves_supported.unwrap_or(false);

                if let Some(played) = final_rom.last_played {
                    meta.last_played = Some(played);
                }
                if let Some(total_time) = final_rom.total_play_time {
                    meta.total_play_time = total_time;
                }
                
                // For store games, we update the metadata. For local generic roms, we might want to be more careful, 
                // but store scanning is almost always "better" or equal info.
                let _ = db.insert_metadata(&meta);
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
                meta.publisher = final_rom.publisher.clone();
                meta.release_date = final_rom.release_date.clone();
                meta.cloud_saves_supported = final_rom.cloud_saves_supported.unwrap_or(false);
                
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
                            custom_filename: None,
                        });
                    }
                }
            } else if final_rom.id.starts_with("heroic-") {
                let assets_to_collect = vec![
                    ("Box - Front", final_rom.boxart_path.clone()),
                    ("Icon", final_rom.icon_path.clone()),
                    ("Background", final_rom.background_path.clone()),
                ];

                for (atype, path_opt) in assets_to_collect {
                    if let Some(src) = path_opt {
                        asset_tasks.push(AssetTask {
                            rom_id: final_rom.id.clone(),
                            asset_type: atype.to_string(),
                            src: src.clone(),
                            dest_base: assets_base_dir.clone(),
                            save_locally: save_assets_locally,
                            custom_filename: None, // Heroic keep default naming
                        });
                    }
                }
            } else if final_rom.id.starts_with("legendary-") {
                // Base assets from Rom fields (already correctly mapped in legendary.rs)
                let assets_to_collect = vec![
                    ("Box - Front".to_string(), final_rom.boxart_path.clone()),
                    ("Icon".to_string(), final_rom.icon_path.clone()),
                    ("Background".to_string(), final_rom.background_path.clone()),
                ];

                for (atype, path_opt) in assets_to_collect {
                    if let Some(src) = path_opt {
                        asset_tasks.push(AssetTask {
                            rom_id: final_rom.id.clone(),
                            asset_type: atype,
                            src: src.clone(),
                            dest_base: assets_base_dir.clone(),
                            save_locally: true,
                            custom_filename: None, // Reverted: use default system naming
                        });
                    }
                }
            }

            success_count += 1;
            progress_callback(i, total, final_rom.title.unwrap_or_default());
        }

        // COMMIT TRANSACTION for ROMs/Metadata
        let _ = db.get_connection().execute("COMMIT", []);

        // 4. Parallel Asset Processing (Throttled)
        if !asset_tasks.is_empty() {
            use futures_util::StreamExt;
            
            crate::core::runtime::get_runtime().block_on(async {
                let mut stream = futures_util::stream::iter(asset_tasks)
                    .map(|task| async move {
                        // Small delay to avoid hitting servers too fast
                        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
                        task.execute().await
                    })
                    .buffer_unordered(5); // Concurrency limit: 5

                while let Some(result) = stream.next().await {
                    if let Some((rom_id, atype, path_str, src_path)) = result {
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
    custom_filename: Option<String>,
}

impl AssetTask {
    async fn execute(self) -> Option<(String, String, String, String)> {
        let dest_dir = self.dest_base.join(&self.asset_type);
        let _ = fs::create_dir_all(&dest_dir);
        
        let ext = if self.src.contains(".png") { "png" } 
                 else if self.src.contains(".svg") { "svg" } 
                 else { "jpg" };
                 
        let filename = if let Some(custom) = &self.custom_filename {
            format!("{}.{}", custom, ext)
        } else {
            format!("{}.{}", self.asset_type.to_lowercase().replace(" ", "_"), ext)
        };
        let dest_path = dest_dir.join(filename);

        if self.src.starts_with("http") {
            // Check if file exists and is not empty. If it's a broken symlink or 0 bytes, we re-download.
            let needs_download = if let Ok(meta) = dest_path.symlink_metadata() {
                meta.len() == 0 || meta.file_type().is_symlink() // Re-download if 0b or is a symlink (we want direct files now)
            } else {
                true
            };

            if needs_download {
                if dest_path.symlink_metadata().is_ok() {
                    let _ = fs::remove_file(&dest_path);
                }
                
                log::info!("[AssetTask] Downloading {} to {:?}", self.asset_type, dest_path);
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
            if src_path.exists() {
                 let needs_update = if let Ok(meta) = dest_path.symlink_metadata() {
                    meta.len() == 0 || meta.file_type().is_symlink()
                } else {
                    true
                };

                if needs_update {
                    if dest_path.symlink_metadata().is_ok() {
                        let _ = fs::remove_file(&dest_path);
                    }
                    
                    log::info!("[AssetTask] Processing local asset {} to {:?}", self.asset_type, dest_path);
                    if self.save_locally {
                         let _ = fs::copy(src_path, &dest_path);
                    } else {
                        // Heroic/Other symlink path
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
                if dest_path.exists() {
                    return Some((self.rom_id, self.asset_type, dest_path.to_string_lossy().to_string(), self.src));
                }
            }
        }
        None
    }
}
