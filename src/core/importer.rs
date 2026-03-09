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
        F: Fn(f32, String),
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
                            sort_order: 0,
                        });
                        steam_resources.push(GameResource {
                            id: Uuid::new_v4().to_string(),
                            rom_id: final_rom.id.clone(),
                            type_: "generic".to_string(),
                            url: base_url.clone(),
                            label: Some("Community Hub".to_string()),
                            sort_order: 0,
                        });
                        steam_resources.push(GameResource {
                            id: Uuid::new_v4().to_string(),
                            rom_id: final_rom.id.clone(),
                            type_: "generic".to_string(),
                            url: format!("{}/discussions/", base_url),
                            label: Some("Discussions".to_string()),
                            sort_order: 0,
                        });
                        steam_resources.push(GameResource {
                            id: Uuid::new_v4().to_string(),
                            rom_id: final_rom.id.clone(),
                            type_: "generic".to_string(),
                            url: format!("{}/guides/", base_url),
                            label: Some("Guides".to_string()),
                            sort_order: 0,
                        });
                        meta.resources = Some(steam_resources);
                    }
                } else if final_rom.id.starts_with("legendary-") && meta.resources.as_ref().map_or(true, |r| r.is_empty()) {
                    let mut slug = final_rom.title.as_deref().unwrap_or("").to_lowercase();
                    // Slugify: Replace non-alphanumeric chars with dashes
                    if let Ok(re_slug) = regex::Regex::new(r"[^a-z0-9]+") {
                        slug = re_slug.replace_all(&slug, "-").to_string();
                        slug = slug.trim_matches('-').to_string();
                        
                        if !slug.is_empty() {
                            let mut epic_resources = Vec::new();
                            epic_resources.push(GameResource {
                                id: Uuid::new_v4().to_string(),
                                rom_id: final_rom.id.clone(),
                                type_: "generic".to_string(),
                                url: format!("https://store.epicgames.com/en-US/p/{}", slug),
                                label: Some("Epic Store Page".to_string()),
                                sort_order: 0,
                            });
                            meta.resources = Some(epic_resources);
                        }
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

            // PC Config Inheritance (Minimal Fix)
            let platform_type_lower = platform.platform_type.as_deref().map(|t| t.to_lowercase()).unwrap_or_default();
            let platform_name_lower = platform.name.to_lowercase();
            
            if platform_type_lower == "epic" || platform_name_lower.contains("epic") || platform_type_lower == "pc (windows)" {
                let mut settings_to_apply = platform.pc_config_json.clone();
                
                // Fallback: If the collection is empty, check for global defaults (EPIC ONLY)
                if (platform_type_lower == "epic" || platform_name_lower.contains("epic")) && (settings_to_apply.is_none() || settings_to_apply.as_ref().map_or(true, |s| s.is_empty())) {
                    let config_path = crate::core::paths::get_config_dir().join("settings.json");
                    if let Ok(content) = std::fs::read_to_string(&config_path) {
                        if let Ok(data) = serde_json::from_str::<serde_json::Value>(&content) {
                            settings_to_apply = Some(serde_json::json!({
                                "umu_proton_version": data.get("default_proton_runner"),
                                "wine_prefix": data.get("default_proton_prefix"),
                                "wrapper": data.get("default_proton_wrapper"),
                                "use_gamescope": data.get("default_proton_use_gamescope"),
                                "use_mangohud": data.get("default_proton_use_mangohud"),
                                "gamescope_args": data.get("default_proton_gamescope_args"),
                                "gs_state": {
                                    "w": data.get("default_proton_gamescope_w"),
                                    "h": data.get("default_proton_gamescope_h"),
                                    "W": data.get("default_proton_gamescope_out_w"),
                                    "H": data.get("default_proton_gamescope_out_h"),
                                    "r": data.get("default_proton_gamescope_refresh"),
                                    "S": data.get("default_proton_gamescope_scaling"),
                                    "U": data.get("default_proton_gamescope_upscaler"),
                                    "f": data.get("default_proton_gamescope_fullscreen")
                                },
                            }).to_string());
                        }
                    }
                }

                if let Some(pc_json) = settings_to_apply {
                    if !pc_json.is_empty() {
                        if let Ok(defaults) = serde_json::from_str::<serde_json::Value>(&pc_json) {
                            let has_config = db.get_pc_config(&final_rom.id).ok().flatten().is_some();
                            if !has_config {
                                let new_config = crate::core::models::PcConfig {
                                    rom_id: final_rom.id.clone(),
                                    umu_proton_version: defaults.get("umu_proton_version").and_then(|v| v.as_str()).map(|s| s.to_string()),
                                    umu_store: defaults.get("umu_store").and_then(|v| v.as_str()).map(|s| s.to_string())
                                        .or(Some("none".to_string())),
                                    wine_prefix: defaults.get("wine_prefix").and_then(|v| v.as_str()).map(|s| s.to_string()),
                                    working_dir: defaults.get("working_dir").and_then(|v| v.as_str()).map(|s| s.to_string()),
                                    umu_id: defaults.get("umu_id").and_then(|v| v.as_str()).map(|s| s.to_string())
                                        .or(Some("".to_string())),
                                    env_vars: defaults.get("env_vars").and_then(|v| v.as_str()).map(|s| s.to_string()),
                                    extra_args: defaults.get("extra_args").and_then(|v| v.as_str()).map(|s| s.to_string()),
                                    proton_verb: defaults.get("proton_verb").and_then(|v| v.as_str()).map(|s| s.to_string()),
                                    disable_fixes: defaults.get("disable_fixes").and_then(|v| v.as_bool()),
                                    no_runtime: defaults.get("no_runtime").and_then(|v| v.as_bool()),
                                    log_level: defaults.get("log_level").and_then(|v| v.as_str()).map(|s| s.to_string()),
                                    wrapper: defaults.get("wrapper").and_then(|v| v.as_str()).map(|s| s.to_string()),
                                    use_gamescope: defaults.get("use_gamescope").and_then(|v| v.as_bool()),
                                    gamescope_args: defaults.get("gamescope_args").and_then(|v| v.as_str()).map(|s| s.to_string()),
                                    use_mangohud: defaults.get("use_mangohud").and_then(|v| v.as_bool()),
                                    pre_launch_script: defaults.get("pre_launch_script").and_then(|v| v.as_str()).map(|s| s.to_string()),
                                    post_launch_script: defaults.get("post_launch_script").and_then(|v| v.as_str()).map(|s| s.to_string()),
                                    cloud_saves_enabled: defaults.get("cloud_saves_enabled").and_then(|v| v.as_bool()),
                                    cloud_save_path: defaults.get("cloud_save_path").and_then(|v| v.as_str()).map(|s| s.to_string()),
                                    cloud_save_auto_sync: defaults.get("cloud_save_auto_sync").and_then(|v| v.as_bool()),
                                };
                                let _ = db.insert_pc_config(&new_config);
                            }
                        }
                    }
                }
            }

            success_count += 1;
            if i % 20 == 0 || i == total - 1 {
                let progress = (i as f32 + 1.0) / total as f32;
                progress_callback(progress, format!("Importing {}: {}/{}", final_rom.title.as_deref().unwrap_or("Unknown"), i + 1, total));
            }
        }

        // COMMIT TRANSACTION for ROMs/Metadata
        let _ = db.get_connection().execute("COMMIT", []);

        // 4. Parallel Asset Processing (Throttled)
        if !asset_tasks.is_empty() {
            use futures_util::StreamExt;
            let total_assets = asset_tasks.len();
            let mut completed_assets = 0;

            crate::core::runtime::get_runtime().block_on(async {
                let mut stream = futures_util::stream::iter(asset_tasks)
                    .map(|task| async move {
                        // Small delay to avoid hitting servers too fast
                        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
                        task.execute().await
                    })
                    .buffer_unordered(5); // Concurrency limit: 5

                while let Some(item) = stream.next().await {
                    completed_assets += 1;
                    
                    let mut action_label = "Processing artwork";
                    if let Some((_, _, _, _, did_download)) = &item {
                        action_label = if *did_download { "Downloading artwork" } else { "Importing artwork" };
                    }

                    if completed_assets % 5 == 0 || completed_assets == total_assets {
                        let progress = completed_assets as f32 / total_assets as f32;
                        progress_callback(progress, format!("{}: {}/{}", action_label, completed_assets, total_assets));
                    }

                    if let Some((rom_id, atype, path_str, _, _)) = item {
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
    async fn execute(self) -> Option<(String, String, String, String, bool)> {
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
                
                log::debug!("[AssetTask] Downloading {} to {:?}", self.asset_type, dest_path);
                // Use async reqwest for parallel downloads
                let client = reqwest::Client::new();
                if let Ok(resp) = client.get(&self.src).send().await {
                    if resp.status().is_success() {
                        if let Ok(bytes) = resp.bytes().await {
                            if fs::write(&dest_path, &bytes).is_ok() {
                                 return Some((self.rom_id, self.asset_type, dest_path.to_string_lossy().to_string(), self.src, true));
                            }
                        }
                    } else if self.src.contains("library_600x900.jpg") {
                        let fallback_src = self.src.replace("library_600x900.jpg", "header.jpg");
                        log::info!("[AssetTask] Failed to download 600x900 boxart, falling back to {}", fallback_src);
                        if let Ok(fallback_resp) = client.get(&fallback_src).send().await {
                            if fallback_resp.status().is_success() {
                                if let Ok(bytes) = fallback_resp.bytes().await {
                                    if fs::write(&dest_path, &bytes).is_ok() {
                                        // Return self.src instead of fallback_src to match the Box Front mapping
                                        return Some((self.rom_id, self.asset_type, dest_path.to_string_lossy().to_string(), self.src, true));
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                return Some((self.rom_id, self.asset_type, dest_path.to_string_lossy().to_string(), self.src, false));
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
                    return Some((self.rom_id, self.asset_type, dest_path.to_string_lossy().to_string(), self.src, false));
                }
            }
        }
        None
    }
}
