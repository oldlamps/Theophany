#![allow(non_snake_case)]
use qmetaobject::prelude::*;
use crate::core::retroachievements::RetroAchievementsClient;
use crate::core::hasher::Hasher;
use crate::core::ra_cache::{RaCache, RaGameHash};
use crate::core::ra_mapping::get_console_id;
use crate::core::paths;
use std::thread;
use std::sync::mpsc;
use std::cell::RefCell;

#[derive(QObject, Default)]
pub struct RetroAchievementsBridge {
    base: qt_base_class!(trait QObject),

    // Signals
    loginSuccess: qt_signal!(username: QString),
    loginError: qt_signal!(message: QString),
    gameDataReady: qt_signal!(json: QString),
    userSummaryReady: qt_signal!(json: QString),
    errorOccurred: qt_signal!(message: QString),

    // Methods
    login: qt_method!(fn(&mut self, username: String, api_key: String)),
    fetchGameData: qt_method!(fn(&mut self, rom_id: String, game_path: String, game_title: String, platform_name: String, username: String, api_key: String)),
    fetchUserSummary: qt_method!(fn(&mut self, username: String, api_key: String)),
    poll: qt_method!(fn(&mut self)),

    // Internal
    tx: RefCell<Option<mpsc::Sender<RAMsg>>>,
    rx: RefCell<Option<mpsc::Receiver<RAMsg>>>,
}

enum RAMsg {
    LoginSuccess(String),
    LoginError(String),
    GameDataReady(String),
    UserSummaryReady(String),
    Error(String),
}

impl RetroAchievementsBridge {
    fn login(&mut self, username: String, api_key: String) {
        self.ensure_channels();
        let tx = self.tx.borrow().as_ref().unwrap().clone();
        
        thread::spawn(move || {
            let client = RetroAchievementsClient::new(username.clone(), api_key);
            match client.verify_credentials() {
                Ok(_) => {
                    let _ = tx.send(RAMsg::LoginSuccess(username));
                },
                Err(e) => {
                    // println!("RA Login Error: {}", e);
                    let _ = tx.send(RAMsg::LoginError(e.to_string()));
                }
            }
        });
    }

    fn fetchGameData(&mut self, rom_id: String, game_path: String, game_title: String, platform_name: String, username: String, api_key: String) {
        self.ensure_channels();
        let tx = self.tx.borrow().as_ref().unwrap().clone();
        
        thread::spawn(move || {
            let client = RetroAchievementsClient::new(username, api_key);
            match perform_ra_scrape(&client, &rom_id, &game_path, &game_title, &platform_name) {
                Ok(json) => {
                    // println!("RA Game Data Ready: {}", json);
                    let _ = tx.send(RAMsg::GameDataReady(json));
                },
                Err(e) => {
                    // println!("RA Game Data Error: {}", e);
                    let _ = tx.send(RAMsg::Error(e.to_string()));
                }
            }
        });
    }



    fn fetchUserSummary(&mut self, username: String, api_key: String) {
        self.ensure_channels();
        let tx = self.tx.borrow().as_ref().unwrap().clone();
        let username_target = username.clone();
        
        thread::spawn(move || {
            let client = RetroAchievementsClient::new(username, api_key);
            match client.get_user_summary(&username_target, 10) {
                Ok(summary) => {
                     if let Ok(json) = serde_json::to_string(&summary) {
                         // println!("RA User Summary Ready: {}", json);
                         let _ = tx.send(RAMsg::UserSummaryReady(json));
                     }
                },
                Err(e) => {
                    // println!("RA User Summary Error: {}", e);
                    let _ = tx.send(RAMsg::Error(format!("Failed to fetch user summary: {}", e)));
                }
            }
        });
    }


    fn poll(&mut self) {
        let rx_borrow = self.rx.borrow();
        if let Some(rx) = rx_borrow.as_ref() {
            while let Ok(msg) = rx.try_recv() {
                match msg {
                    RAMsg::LoginSuccess(u) => self.loginSuccess(u.into()),
                    RAMsg::LoginError(e) => self.loginError(e.into()),
                    RAMsg::GameDataReady(j) => self.gameDataReady(j.into()),
                    RAMsg::UserSummaryReady(j) => self.userSummaryReady(j.into()),
                    RAMsg::Error(e) => self.errorOccurred(e.into()),
                }
            }
        }
    }

    fn ensure_channels(&self) {
        if self.tx.borrow().is_none() {
             let (tx, rx) = mpsc::channel();
             *self.tx.borrow_mut() = Some(tx);
             *self.rx.borrow_mut() = Some(rx);
        }
    }
}

pub fn perform_ra_scrape(
    client: &RetroAchievementsClient,
    rom_id: &str,
    game_path: &str,
    game_title: &str,
    platform_name: &str,
) -> Result<String, String> {
        // Resolve Console ID: Try Cache DB Name Lookup -> Fallback to Hardcoded Map
        let data_dir = paths::get_data_dir();
        let db_path = data_dir.join("ra_cache.db");
        let mut console_id_opt = get_console_id(&platform_name);

        // Try dynamic lookup if naive map fails or verifying priority
        if let Ok(cache) = RaCache::new(&db_path) {
            if let Ok(Some(id)) = cache.get_console_id_by_name(&platform_name) {
                    console_id_opt = Some(id);
            }
        }

        // 1. Try Cache Lookup (Title Match)
        let mut resolved_id: Option<u64> = None;

        if let Some(cid) = console_id_opt {
            let data_dir = paths::get_data_dir();
            let db_path = data_dir.join("ra_cache.db");
            
            if let Ok(mut cache) = RaCache::new(&db_path) {
                let has_cache = cache.has_cache(cid).unwrap_or(false);
                if !has_cache {
                        if let Ok(list) = client.get_game_list(cid) {
                            let hashes: Vec<RaGameHash> = list.into_iter().map(|g| RaGameHash {
                                game_id: g.id,
                                console_id: g.console_id,
                                title: g.title,
                                checksum: "NO_HASH".to_string(), // We are using this for Title lookup mostly
                            }).collect();
                            let _ = cache.update_console_cache(cid, hashes);
                        }
                }

                // Manual Fuzzy Lookup
                if let Ok(games) = cache.get_console_games(cid) {
                    let normalize = |s: &str| -> String {
                        let lower = s.to_lowercase();
                        let s_no_the = if lower.starts_with("the ") { &lower[4..] } else { &lower };
                        s_no_the.chars().filter(|c| c.is_alphanumeric()).collect()
                    };

                    let target_norm = normalize(&game_title);

                    for (id, title) in games {
                        let title_norm = normalize(&title);
                        // Exact normalized match
                        if title_norm == target_norm {
                            resolved_id = Some(id);
                            break;
                        }
                    }
                }
            }
        }

        // 2. Fallback: MD5 Hash
        // We skip large image formats as they are CPU intensive and often don't match RA hashes anyway (compressed or partition-based)
        let should_skip_hashing = std::path::Path::new(game_path)
            .extension()
            .and_then(|e| e.to_str())
            .map(|s| {
                let s_lower = s.to_lowercase();
                s_lower == "chd" || s_lower == "rvz" || s_lower == "iso" || s_lower == "xiso"
            })
            .unwrap_or(false);

        if resolved_id.is_none() && !should_skip_hashing {
                match Hasher::calculate_md5(&game_path) {
                Ok(md5) => {
                        if let Ok(id) = client.resolve_hash(&md5) {
                            resolved_id = Some(id);
                        }
                },
                Err(_e) => {
                        // println!("Hashing failed: {}", e);
                }
            };
        } else if resolved_id.is_none() && should_skip_hashing {
            // println!("Skipping MD5 hash for large image format: {}", game_path);
        }
        
        // 3. Fetch Game Data & Scrape
        if let Some(game_id) = resolved_id {
            match client.get_game_data(game_id) {
                Ok(info) => {
                    let release_date_str = if let Some(date_str) = &info.released {
                        if let Ok(dt) = chrono::NaiveDateTime::parse_from_str(date_str, "%Y-%m-%d %H:%M:%S") {
                            Some(dt.format("%Y-%m-%d").to_string())
                        } else {
                            Some(date_str.clone())
                        }
                    } else {
                        None
                    };

                    // println!("DEBUG [RA]: Fetched for {}: Dev={:?}, Pub={:?}, Genre={:?}, Rel={:?}", 
                    //     rom_id, info.developer, info.publisher, info.genre, release_date_str);

                    // --- METADATA & SCRAPING ---
                    let achievement_count = info.total_achievements.map(|n| n as i32).or_else(|| {
                        info.achievements.as_ref().map(|m| m.len() as i32)
                    });
                    let achievement_unlocked = info.num_awarded.map(|n| n as i32);

                    // Extract 5 most recent badges
                    let mut recent_badges_json: Option<String> = None;
                    if let Some(ach_map) = &info.achievements {
                        let mut earned: Vec<_> = ach_map.values()
                            .filter(|a| a.date_earned.is_some())
                            .collect();
                        
                        // Sort by date earned (descending)
                        earned.sort_by(|a, b| {
                             b.date_earned.as_ref().unwrap().cmp(a.date_earned.as_ref().unwrap())
                        });

                        let top_5: Vec<String> = earned.iter()
                            .take(5)
                            .map(|a| a.badge_name.clone())
                            .collect();
                        
                        if !top_5.is_empty() {
                            recent_badges_json = serde_json::to_string(&top_5).ok();
                        }
                    }

                    let meta = crate::core::models::GameMetadata {
                        rom_id: rom_id.to_string(),
                        title: None,
                        description: None,
                        rating: None,
                        release_date: release_date_str,
                        developer: info.developer.clone(),
                        publisher: info.publisher.clone(),
                        genre: info.genre.clone(),
                        tags: None,
                        region: None,
                        is_favorite: false,
                        play_count: 0,
                        last_played: None,
                        total_play_time: 0,
                        achievement_count,
                        achievement_unlocked,
                        ra_game_id: info.id,
                        ra_recent_badges: recent_badges_json.clone(),
                        is_installed: if rom_id.starts_with("steam-") {
                            crate::core::store::StoreManager::get_local_steam_appids().contains(&rom_id.replace("steam-", ""))
                        } else {
                            true
                        },
                        cloud_saves_supported: false,
                        resources: None,
                    };
                    
                    let data_dir_main = paths::get_data_dir();
                    let db_path_main = data_dir_main.join("games.db");
                    
                    if let Ok(db) = crate::core::db::DbManager::open(&db_path_main) {
                            // Update Metadata
                            if let Err(e) = db.update_game_metadata_if_empty(&rom_id, &meta) {
                                log::error!("[RA] Failed to update metadata DB: {}", e);
                            }

                            // Update Achievements (Count, Unlocked, Badges) - Always update this!
                            if let Err(e) = db.update_achievements(&rom_id, achievement_count.unwrap_or(0), achievement_unlocked.unwrap_or(0), recent_badges_json.as_deref()) {
                                log::error!("[RA] Failed to update achievements DB: {}", e);
                            }
                            
                            // Calculate Image Paths (Use Local Platform Name for folder match)
                            // CRITICAL: Must match asset_scanner.rs logic (Type > Name)
                            let mut platform_folder = platform_name.replace("/", "-").replace("\\", "-");
                            
                            // Try to resolve canonical folder from DB to match scanner (e.g. NES over Nintendo...)
                            {
                                let conn = db.get_connection();
                                if let Ok(mut stmt) = conn.prepare("SELECT p.platform_type, p.name FROM roms r JOIN platforms p ON r.platform_id = p.id WHERE r.id = ?1") {
                                    if let Ok(mut rows) = stmt.query([&rom_id]) {
                                        if let Ok(Some(row)) = rows.next() {
                                            let p_type: Option<String> = row.get(0).unwrap_or(None);
                                            let p_name: String = row.get(1).unwrap_or("Unknown".to_string());
                                            let folder = p_type.or(Some(p_name)).unwrap_or("Unknown".to_string());
                                            platform_folder = folder.replace("/", "-").replace("\\", "-");
                                        }
                                    }
                                }
                            }
                            
                            let rom_path_obj = std::path::Path::new(&game_path);
                            if let Some(rom_stem) = rom_path_obj.file_stem().and_then(|s| s.to_str()) {
                                let images_base = data_dir_main.join("Images").join(&platform_folder).join(rom_stem);
                                
                                // Box Art
                                if let Some(url_part) = &info.image_box_art {
                                    let target = images_base.join("Box - Front").join("box.png");
                                    
                                    // Check if DB already has a path
                                    let mut has_boxart = false;
                                    if let Ok(mut stmt) = db.get_connection().prepare("SELECT boxart_path FROM roms WHERE id = ?1") {
                                        if let Ok(mut rows) = stmt.query([&rom_id]) {
                                            if let Ok(Some(row)) = rows.next() {
                                                let existing: Option<String> = row.get(0).unwrap_or(None);
                                                has_boxart = existing.is_some() && !existing.as_ref().unwrap().is_empty();
                                            }
                                        }
                                    }

                                    if !has_boxart && !target.exists() {
                                        if let Ok(_) = client.download_image(url_part, &target) {
                                            let _ = db.update_rom_images_if_empty(&rom_id, Some(target.to_str().unwrap()), None);
                                        }
                                    }
                                }
                                        
                                // Icon
                                if let Some(url_part) = &info.image_icon {
                                    let target = images_base.join("Icon").join("icon.png");
                                    
                                    let mut has_icon = false;
                                    if let Ok(mut stmt) = db.get_connection().prepare("SELECT icon_path FROM roms WHERE id = ?1") {
                                        if let Ok(mut rows) = stmt.query([&rom_id]) {
                                            if let Ok(Some(row)) = rows.next() {
                                                let existing: Option<String> = row.get(0).unwrap_or(None);
                                                has_icon = existing.is_some() && !existing.as_ref().unwrap().is_empty();
                                            }
                                        }
                                    }

                                    if !has_icon && !target.exists() {
                                        if let Ok(_) = client.download_image(url_part, &target) {
                                            let _ = db.update_rom_images_if_empty(&rom_id, None, Some(target.to_str().unwrap()));
                                        }
                                    }
                                }

                                // Screenshot
                                if let Some(url_part) = &info.image_ingame {
                                    let target = images_base.join("Screenshot").join("screen.png");
                                    if !target.exists() {
                                        let _ = client.download_image(url_part, &target);
                                    }
                                }
                                
                                // Force Sync DB with Filesystem
                                let _ = crate::core::asset_scanner::scan_game_assets(&db, &rom_id);
                            }
                    }

                    match serde_json::to_string(&info) {
                        Ok(json) => Ok(json),
                        Err(e) => Err(e.to_string())
                    }
                },
                Err(e) => Err(format!("Failed to fetch info: {}", e))
            }
        } else {
                Err("Game could not be identified via Title or Hash.".to_string())
        }
}
