use qmetaobject::prelude::*;
use crate::core::store::StoreManager;
use std::sync::mpsc;
use std::cell::RefCell;
use std::collections::HashMap;
use crate::core::metadata_manager::MetadataManager;
use std::path::Path;

#[derive(QObject, Default)]
pub struct StoreBridge {
    base: qt_base_class!(trait QObject),
    
    // Signals
    searchFinished: qt_signal!(results: QString),
    installProgress: qt_signal!(app_id: QString, progress: f32, status: QString),
    installFinished: qt_signal!(app_id: QString, success: bool, message: QString),
    localAppsFinished: qt_signal!(results: QString),
    steamLibraryFinished: qt_signal!(results: QString),
    remoteSteamLibraryFinished: qt_signal!(results: QString, success: bool, message: QString),
    heroicLibraryFinished: qt_signal!(results: QString),
    lutrisLibraryFinished: qt_signal!(results: QString),
    appDetailsReceived: qt_signal!(json: QString),
    featuredContentReceived: qt_signal!(json: QString),
    folderAnalyzed: qt_signal!(json: QString),
    steamAchievementsFinished: qt_signal!(json: QString, success: bool, message: QString),

    // Methods
    search_store: qt_method!(fn(&self, query: String)),
    browse_store: qt_method!(fn(&self, category: String)),
    install_app: qt_method!(fn(&self, app_id: String, platform_id: String, name: String, summary: String, icon_url: String, description: String, screenshots_json: String, developer: String)),
    import_local_app: qt_method!(fn(&self, rom_json: String, platform_id: String)),
    import_steam_games_bulk: qt_method!(fn(&self, roms_json_array: String, platform_id: String)),
    refresh_local_apps: qt_method!(fn(&self)),
    refresh_steam_library: qt_method!(fn(&self)),
    refresh_remote_steam_library: qt_method!(fn(&self, steam_id: QString, api_key: QString)),
    auto_detect_steam_id: qt_method!(fn(&self) -> QString),
    refresh_steam_achievements: qt_method!(fn(&self, app_id: QString, steam_id: QString, api_key: QString)),
    refresh_heroic_library: qt_method!(fn(&self)),
    refresh_lutris_library: qt_method!(fn(&self)),
    find_icon_path: qt_method!(fn(&self, icon_name: String) -> String),
    get_app_details: qt_method!(fn(&self, app_id: String)),
    analyze_folder: qt_method!(fn(&self, path: String)),
    poll: qt_method!(fn(&mut self)),

    // Internal
    tx: RefCell<Option<mpsc::Sender<StoreMsg>>>,
    rx: RefCell<Option<mpsc::Receiver<StoreMsg>>>,
    
    // Cache
    category_cache: RefCell<HashMap<String, String>>,
}

enum StoreMsg {
    SearchFinished(String),
    InstallProgress(String, f32, String),
    InstallFinished(String, bool, String),
    LocalAppsFinished(String),
    SteamLibraryFinished(String),
    RemoteSteamLibraryFinished(String, bool, String),
    HeroicLibraryFinished(String),
    LutrisLibraryFinished(String),
    AppDetailsReceived(String),
    CategoryFinished(String, String), // Category, JSON
    FeaturedContentReceived(String),
    FolderAnalyzed(String),
    SteamAchievementsFinished(String, bool, String),
}

impl StoreBridge {
    fn ensure_channels(&self) {
        if self.tx.borrow().is_none() {
             let (tx, rx) = mpsc::channel();
             *self.tx.borrow_mut() = Some(tx);
             *self.rx.borrow_mut() = Some(rx);
        }
    }

    fn poll(&mut self) {
        let rx_borrow = self.rx.borrow();
        if let Some(rx) = rx_borrow.as_ref() {
            while let Ok(msg) = rx.try_recv() {
                match msg {
                    StoreMsg::SearchFinished(j) => self.searchFinished(j.into()),
                    StoreMsg::InstallProgress(id, p, s) => self.installProgress(id.into(), p, s.into()),
                    StoreMsg::InstallFinished(id, s, m) => self.installFinished(id.into(), s, m.into()),
                    StoreMsg::LocalAppsFinished(j) => self.localAppsFinished(j.into()),
                    StoreMsg::SteamLibraryFinished(j) => self.steamLibraryFinished(j.into()),
                    StoreMsg::RemoteSteamLibraryFinished(j, s, m) => self.remoteSteamLibraryFinished(j.into(), s, m.into()),
                    StoreMsg::HeroicLibraryFinished(j) => self.heroicLibraryFinished(j.into()),
                    StoreMsg::LutrisLibraryFinished(j) => self.lutrisLibraryFinished(j.into()),
                    StoreMsg::AppDetailsReceived(j) => self.appDetailsReceived(j.into()),
                    StoreMsg::CategoryFinished(cat, json) => {
                        self.category_cache.borrow_mut().insert(cat, json.clone());
                        self.searchFinished(json.into());
                    }
                    StoreMsg::FeaturedContentReceived(j) => self.featuredContentReceived(j.into()),
                    StoreMsg::FolderAnalyzed(j) => self.folderAnalyzed(j.into()),
                    StoreMsg::SteamAchievementsFinished(j, s, m) => self.steamAchievementsFinished(j.into(), s, m.into()),
                }
            }
        }
    }

    fn install_app(&self, app_id: String, platform_id: String, name: String, _summary: String, icon_url: String, description: String, screenshots_json: String, developer: String) {
        log::info!("Starting Flatpak install for: {} ({})", name, app_id);
        self.ensure_channels();
        let tx = self.tx.borrow().as_ref().unwrap().clone();
        let app_id_clone = app_id.clone();
        let platform_id_clone = platform_id.clone();
        let name_clone = name.clone();
        let mut description_clone = description.clone();
        let screenshots_json_clone = screenshots_json.clone();
        let icon_url_clone = icon_url.clone();
        let developer_clone = developer.clone();
        
        // Strip HTML tags from description with better formatting handling
        let desc_tagged = description_clone
            .replace("<br>", "\n")
            .replace("<br/>", "\n")
            .replace("<br />", "\n")
            .replace("</p>", "\n\n")
            .replace("<li>", "\n• ");
            
        let mut stripped = String::new();
        let mut inside_tag = false;
        for c in desc_tagged.chars() {
            if c == '<' { inside_tag = true; continue; }
            if c == '>' { inside_tag = false; continue; }
            if !inside_tag { stripped.push(c); }
        }
        
        // Clean up whitespace: split by lines, trim each line, then rejoin
        description_clone = stripped.lines()
            .map(|l| l.trim())
            .filter(|l| !l.is_empty())
            .collect::<Vec<&str>>()
            .join("\n");

        
        std::thread::spawn(move || {
            let _ = tx.send(StoreMsg::InstallProgress(app_id_clone.clone(), 0.1, "Starting install...".into()));
            
            let screenshots: Vec<crate::core::store::Screenshot> = serde_json::from_str(&screenshots_json_clone).unwrap_or_default();
            
            match StoreManager::install_flatpak_with_details(&app_id_clone, &description_clone, &screenshots, &icon_url_clone) {
                Ok(_) => {
                    log::info!("[FlatpakStore] Install successful, creating library entry...");
                    
                    // Attempt to cache icon logic (library facing)
                    let mut final_icon_path = None;
                    if !icon_url_clone.is_empty() {
                        final_icon_path = StoreManager::cache_icon(&icon_url_clone, &app_id_clone);
                    }

                    // Create library entry
                    let rom = crate::core::models::Rom {
                        id: app_id_clone.clone(),
                        platform_id: platform_id_clone.clone(),
                        path: format!("flatpak://{}", app_id_clone),
                        filename: format!("{}.desktop", app_id_clone), // Append .desktop so file_stem() works correctly
                        file_size: 0,
                        hash_sha1: None,
                        title: Some(name_clone.clone()),
                        region: None,
                        platform_name: None,
                        platform_type: None,
                        platform_icon: None,
                        boxart_path: None, 
                        icon_path: final_icon_path,
                        background_path: None,
                        date_added: Some(chrono::Utc::now().timestamp()),
                        play_count: Some(0),
                        total_play_time: Some(0),
                        last_played: None,
                        is_favorite: Some(false),
                        genre: None,
                        developer: Some(developer_clone.clone()),
                        publisher: None,
                        rating: None,
                        tags: None,
                        release_date: None,
                        description: Some(description_clone.clone()),
                    };

                    let db_path = crate::core::paths::get_data_dir().join("games.db");
                    if let Ok(db) = crate::core::db::DbManager::open(&db_path) {
                        let _ = db.insert_rom(&rom);
                        let mut meta = crate::core::models::GameMetadata::default();
                        meta.rom_id = rom.id.clone();
                        meta.title = Some(name_clone.clone());
                        meta.description = Some(description_clone);
                        meta.developer = Some(developer_clone);
                        let _ = db.insert_metadata(&meta);
                        
                        // Auto-scan for assets immediately so they show up
                        log::info!("Scanning assets for new install: {}", app_id_clone);
                        let _ = crate::core::asset_scanner::scan_game_assets(&db, &rom.id);
                    }

                    let _ = tx.send(StoreMsg::InstallFinished(app_id_clone, true, "Installed and added to library".into()));
                },
                Err(e) => {
                    log::error!("Flatpak install failed: {}", e);
                    let _ = tx.send(StoreMsg::InstallFinished(app_id_clone, false, e.to_string().into()));
                }
            }
        });
    }

    fn search_store(&self, query: String) {
        log::info!("Searching Flathub for: {}", query);
        self.ensure_channels();
        let tx = self.tx.borrow().as_ref().unwrap().clone();
        std::thread::spawn(move || {
            match StoreManager::search_flathub(&query) {
                Ok(results) => {
                    // Pre-cache icons for search results to make UI snappier later
                    for app in &results {
                        if let Some(ref icon) = app.icon_url {
                            if icon.starts_with("http") {
                                let _ = StoreManager::cache_icon(icon, &app.app_id);
                            }
                        }
                    }
                    let json = serde_json::to_string(&results).unwrap_or_default();
                    let _ = tx.send(StoreMsg::SearchFinished(json));
                },
                Err(e) => {
                    log::error!("Flathub search failed: {}", e);
                    let _ = tx.send(StoreMsg::SearchFinished("[]".into()));
                }
            }
        });
    }

    fn browse_store(&self, category: String) {
        log::info!("Browsing Flathub storefront for category: {}", category);
        self.ensure_channels();
        
        // check cache first (skip for Featured as we want fresh daily content or short TTL)
        if category != "Featured" {
             if let Some(json) = self.category_cache.borrow().get(&category) {
                 log::info!("Cache hit for category: {}", category);
                 let tx = self.tx.borrow().as_ref().unwrap().clone();
                 let json_clone: String = json.clone();
                 std::thread::spawn(move || {
                     let _ = tx.send(StoreMsg::CategoryFinished(category, json_clone)); // Use CategoryFinished to update UI properly
                 });
                 return;
             }
        }

        let tx = self.tx.borrow().as_ref().unwrap().clone();
        let cat_clone = category.clone();
        
        std::thread::spawn(move || {
            if cat_clone == "Featured" {
                match StoreManager::fetch_featured_games() {
                    Ok(content) => {
                        let json = serde_json::to_string(&content).unwrap_or_default();
                        let _ = tx.send(StoreMsg::FeaturedContentReceived(json));
                    },
                    Err(e) => {
                         log::error!("Flathub featured fetch failed: {}", e);
                         let _ = tx.send(StoreMsg::FeaturedContentReceived("{}".into()));
                    }
                }
            } else {
                match StoreManager::browse_flathub(&cat_clone) {
                    Ok(results) => {
                        // Pre-cache icons for results
                        for app in &results {
                             if let Some(ref icon) = app.icon_url {
                                 if icon.starts_with("http") {
                                     let _ = StoreManager::cache_icon(icon, &app.app_id);
                                 }
                             }
                        }
                        
                        let json = serde_json::to_string(&results).unwrap_or_default();
                        let _ = tx.send(StoreMsg::CategoryFinished(cat_clone, json));
                    },
                    Err(e) => {
                        log::error!("Flathub browse failed: {}", e);
                        let _ = tx.send(StoreMsg::SearchFinished("[]".into()));
                    }
                }
            }
        });
    }



    fn refresh_local_apps(&self) {
        log::info!("Scanning local apps...");
        self.ensure_channels();
        let tx = self.tx.borrow().as_ref().unwrap().clone();
        std::thread::spawn(move || {
            let results = StoreManager::scan_local_apps();
            let json = serde_json::to_string(&results).unwrap_or_default();
            let _ = tx.send(StoreMsg::LocalAppsFinished(json));
        });
    }

    fn refresh_steam_library(&self) {
        log::info!("Scanning Steam library...");
        self.ensure_channels();
        let tx = self.tx.borrow().as_ref().unwrap().clone();
        std::thread::spawn(move || {
            let results = StoreManager::scan_steam_games();
            let json = serde_json::to_string(&results).unwrap_or_default();
            let _ = tx.send(StoreMsg::SteamLibraryFinished(json));
        });
    }

    fn refresh_steam_achievements(&self, app_id: QString, steam_id: QString, api_key: QString) {
        let aid = app_id.to_string();
        let sid = steam_id.to_string();
        let key = api_key.to_string();
        
        self.ensure_channels();
        let tx = self.tx.borrow().as_ref().unwrap().clone();
        
        std::thread::spawn(move || {
            match StoreManager::fetch_steam_game_achievements(&aid, &sid, &key) {
                Ok(results) => {
                    let json = serde_json::to_string(&results).unwrap_or_default();
                    let _ = tx.send(StoreMsg::SteamAchievementsFinished(json, true, "Success".into()));
                }
                Err(e) => {
                    log::error!("Failed to fetch Steam achievements: {}", e);
                    let _ = tx.send(StoreMsg::SteamAchievementsFinished("{}".into(), false, e.to_string()));
                }
            }
        });
    }

    fn auto_detect_steam_id(&self) -> QString {
        let ids = StoreManager::detect_local_steam_ids();
        if !ids.is_empty() {
            QString::from(ids[0].clone())
        } else {
            QString::from("")
        }
    }

    fn refresh_remote_steam_library(&self, steam_id: QString, api_key: QString) {
        let sid = steam_id.to_string();
        let key = api_key.to_string();
        log::info!("Fetching remote Steam library for: {}", sid);
        self.ensure_channels();
        let tx = self.tx.borrow().as_ref().unwrap().clone();
        
        std::thread::spawn(move || {
            match StoreManager::fetch_remote_steam_games(&sid, &key) {
                Ok(results) => {
                    let json = serde_json::to_string(&results).unwrap_or_default();
                    let _ = tx.send(StoreMsg::RemoteSteamLibraryFinished(json, true, "Success".into()));
                }
                Err(e) => {
                    log::error!("Failed to fetch remote Steam games: {}", e);
                    let _ = tx.send(StoreMsg::RemoteSteamLibraryFinished("[]".into(), false, e.to_string()));
                }
            }
        });
    }

    fn refresh_heroic_library(&self) {
        log::info!("Scanning Heroic library...");
        self.ensure_channels();
        let tx = self.tx.borrow().as_ref().unwrap().clone();
        std::thread::spawn(move || {
            let results = StoreManager::scan_heroic_games();
            let json = serde_json::to_string(&results).unwrap_or_default();
            let _ = tx.send(StoreMsg::HeroicLibraryFinished(json));
        });
    }

    fn refresh_lutris_library(&self) {
        log::info!("Scanning Lutris library...");
        self.ensure_channels();
        let tx = self.tx.borrow().as_ref().unwrap().clone();
        std::thread::spawn(move || {
            let results = StoreManager::scan_lutris_games();
            let json = serde_json::to_string(&results).unwrap_or_default();
            let _ = tx.send(StoreMsg::LutrisLibraryFinished(json));
        });
    }

    fn import_local_app(&self, rom_json: String, platform_id: String) {
        log::info!("[LocalImport] Received request for platform: {}", platform_id);
        self.ensure_channels();
        let tx = self.tx.borrow().as_ref().unwrap().clone();
        std::thread::spawn(move || {
            match serde_json::from_str::<crate::core::models::Rom>(&rom_json) {
                Ok(rom) => {
                    let db_path = crate::core::paths::get_data_dir().join("games.db");
                    match crate::core::db::DbManager::open(&db_path) {
                        Ok(db) => {
                            let mut final_rom = rom.clone();
                            final_rom.platform_id = platform_id.clone();
                            
                            log::info!("[LocalImport] Inserting ROM: {:?}", final_rom.title);
                            if let Ok(_) = db.insert_rom(&final_rom) {
                                let mut meta = crate::core::models::GameMetadata::default();
                                meta.rom_id = final_rom.id.clone();
                                meta.title = final_rom.title.clone();
                                meta.tags = final_rom.tags.clone();

                                // Get platform folder for sidecar
                                if let Ok(Some(platform)) = db.get_platform(&platform_id) {
                                    let platform_folder = platform.platform_type.clone().or(Some(platform.name.clone())).unwrap_or_else(|| "Unknown".to_string());
                                    
                                    // Sidecar Recovery
                                    let rom_stem = Path::new(&final_rom.filename).file_stem().and_then(|s| s.to_str()).unwrap_or(&final_rom.filename);

                                    
                                    if let Some(sidecar) = MetadataManager::load_sidecar(&platform_folder, rom_stem) {

                                        meta = sidecar;
                                        meta.rom_id = final_rom.id.clone();
                                        
                                        if let Some(tags) = &meta.tags {
                                            let _ = db.get_connection().execute("UPDATE roms SET tags = ?1 WHERE id = ?2", [tags, &final_rom.id]);
                                        }
                                    }

                                    let _ = db.insert_metadata(&meta);

                                    // Asset Discovery
                                    let data_dir = crate::core::paths::get_data_dir();
                                    let sanitized_folder = platform_folder.replace("/", "-").replace("\\", "-");
                                    let assets_base_dir = data_dir.join("Images").join(sanitized_folder).join(rom_stem);

                                    if assets_base_dir.exists() && assets_base_dir.is_dir() {
                                        let mut boxart_path = None;
                                        let mut icon_path = None;

                                        if let Ok(entries) = std::fs::read_dir(&assets_base_dir) {
                                            for entry in entries.flatten() {
                                                if let Ok(file_type) = entry.file_type() {
                                                    if file_type.is_dir() {
                                                        let asset_type = entry.file_name().to_string_lossy().to_string();
                                                        if let Ok(files) = std::fs::read_dir(entry.path()) {
                                                            for file in files.flatten() {
                                                                if let Ok(ft) = file.file_type() {
                                                                    if ft.is_file() || ft.is_symlink() {
                                                                        let path = file.path().to_string_lossy().to_string();
                                                                        let _ = db.insert_asset(&final_rom.id, &asset_type, &path);
                                                                        
                                                                        if asset_type == "boxart" || asset_type == "Steam Library Capsule" {
                                                                            boxart_path = Some(path.clone());
                                                                        }
                                                                        if asset_type == "icon" || asset_type == "Steam Icon" {
                                                                            icon_path = Some(path.clone());
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        if boxart_path.is_some() || icon_path.is_some() {
                                             let conn = db.get_connection();
                                             if let Some(bp) = boxart_path {
                                                 let _ = conn.execute("UPDATE roms SET boxart_path = ?1 WHERE id = ?2", [&bp, &final_rom.id]);
                                             }
                                             if let Some(ip) = icon_path {
                                                 let _ = conn.execute("UPDATE roms SET icon_path = ?1 WHERE id = ?2", [&ip, &final_rom.id]);
                                             }
                                        }
                                    }
                                }

                                log::info!("[LocalImport] Successfully imported: {:?}", final_rom.title);
                                let _ = tx.send(StoreMsg::InstallFinished(final_rom.title.unwrap_or_default(), true, "Imported successfully".into()));
                            } else {
                                log::error!("[LocalImport] Failed to insert ROM into database");
                                let _ = tx.send(StoreMsg::InstallFinished(final_rom.title.unwrap_or_default(), false, "Failed to insert ROM".into()));
                            }
                        },
                        Err(e) => {
                            log::error!("[LocalImport] Could not open database: {}", e);
                        }
                    }
                },
                Err(e) => {
                    log::error!("[LocalImport] Failed to parse ROM JSON: {}", e);
                }
            }
        });
    }

    fn import_steam_games_bulk(&self, roms_json_array: String, platform_id: String) {
        log::info!("[SteamBulkImport] Requested import for {} bytes of JSON", roms_json_array.len());
            
        self.ensure_channels();
        let tx = self.tx.borrow().as_ref().unwrap().clone();
        let platform_id_clone = platform_id.clone();
        
        std::thread::spawn(move || {
            match serde_json::from_str::<Vec<crate::core::models::Rom>>(&roms_json_array) {
                Ok(roms) => {
                    log::info!("[SteamBulkImport] Decoded {} ROMs from JSON", roms.len());
                    let db_path = crate::core::paths::get_data_dir().join("games.db");
                    match crate::core::db::DbManager::open(&db_path) {
                        Ok(db) => {
                            use crate::core::importer::BulkImporter;
                            let total = roms.len();
                            let save_locally = crate::bridge::settings::AppSettings::should_save_heroic_assets_locally();
                            let result = BulkImporter::import_roms(&db, roms, &platform_id_clone, save_locally, |i, total, title| {
                                // Periodic status update
                                if i % 5 == 0 || i == total - 1 {
                                    let progress = (i as f32 + 1.0) / total as f32;
                                    let msg = format!("Importing {}/{}", i + 1, total);
                                    let _ = tx.send(StoreMsg::InstallProgress(title, progress, msg.into()));
                                }
                            });

                            match result {
                                Ok(count) => {
                                    log::info!("[SteamBulkImport] Successfully imported {}/{} games", count, total);
                                    let msg = format!("Imported {} of {} games", count, total);
                                    let _ = tx.send(StoreMsg::InstallFinished("Selected Steam Games".into(), true, msg.into()));
                                },
                                Err(e) => {
                                    log::error!("[SteamBulkImport] Import failed: {}", e);
                                    let _ = tx.send(StoreMsg::InstallFinished("Steam Import".into(), false, e.to_string().into()));
                                }
                            }
                        },
                        Err(e) => {
                            log::error!("[SteamBulkImport] Could not open database: {}", e);
                            let _ = tx.send(StoreMsg::InstallFinished("Steam Import".into(), false, "Database access failed".into()));
                        }
                    }
                },
                Err(e) => {
                    log::error!("[SteamBulkImport] Failed to parse ROMs JSON array: {}", e);
                    let _ = tx.send(StoreMsg::InstallFinished("Steam Import".into(), false, "Invalid import data format".into()));
                }
            }
        });
    }

    fn find_icon_path(&self, icon_name: String) -> String {
        StoreManager::find_icon_path(&icon_name).unwrap_or_default()
    }

    fn get_app_details(&self, app_id: String) {
        log::info!("Fetching details for app: {}", app_id);
        self.ensure_channels();
        let tx = self.tx.borrow().as_ref().unwrap().clone();
        std::thread::spawn(move || {
            match StoreManager::get_app_details(&app_id) {
                Ok(details) => {
                    let json = serde_json::to_string(&details).unwrap_or_default();
                    let _ = tx.send(StoreMsg::AppDetailsReceived(json));
                },
                Err(e) => {
                    log::error!("Failed to fetch app details: {}", e);
                    let _ = tx.send(StoreMsg::AppDetailsReceived("{}".into()));
                }
            }
        });
    }

    fn analyze_folder(&self, path: String) {
        log::info!("Analyzing folder: {}", path);
        self.ensure_channels();
        let tx = self.tx.borrow().as_ref().unwrap().clone();
        
        std::thread::spawn(move || {
            let p = Path::new(&path);
            if !p.exists() || !p.is_dir() {
                let _ = tx.send(StoreMsg::FolderAnalyzed("{}".into()));
                return;
            }

            let mut extensions = HashMap::new();
            log::info!("[FolderAnalyze] Scanning: {:?}", p);
            let mut file_count = 0;
            
            // Scan top level and 3 levels deep for frequency, limit to 2000 files
            for entry in walkdir::WalkDir::new(p).max_depth(4).into_iter().filter_map(|e| e.ok()) {
                if entry.file_type().is_file() {
                    file_count += 1;
                    if file_count > 2000 { break; }

                    if let Some(ext) = entry.path().extension().and_then(|s| s.to_str()) {
                        let ext = ext.to_lowercase();
                        // Ignore common non-game extensions
                        let ignored = ["txt", "pdf", "jpg", "png", "nfo", "db", "ini", "xml", "json", "url", "html", "htm"];
                        if !ignored.contains(&ext.as_str()) {
                            log::info!("[FolderAnalyze] Found file: {:?} with ext: {}", entry.path(), ext);
                            *extensions.entry(ext).or_insert(0) += 1;
                        }
                    }
                }
            }

            // Find most common extensions
            let mut sorted_exts: Vec<_> = extensions.into_iter().collect();
            sorted_exts.sort_by(|a, b| b.1.cmp(&a.1));

            let top_exts: Vec<String> = sorted_exts.iter().take(3).map(|(e, _)| e.clone()).collect();
            let primary_ext = top_exts.get(0).cloned().unwrap_or_default();
            log::info!("[FolderAnalyze] Top extensions: {:?}, primary: {}", top_exts, primary_ext);

            // Suggest platform type based on common extensions
            let mut platform_type = match primary_ext.as_str() {
                "nes" => "NES",
                "sfc" | "smc" => "SNES",
                "gb" => "GameBoy",
                "gba" => "GBA",
                "gbc" => "GBC",
                "n64" | "z64" | "v64" => "N64",
                "nds" => "NDS",
                "3ds" => "3DS",
                "pce" => "PCE",
                "sms" => "MasterSystem",
                "md" | "gen" => "Genesis",
                "gg" => "GameGear",
                "sg" => "SG1000",
                "bin" | "img" | "mdf" | "cue" => "PS1",
                "ps2" | "iso" => "PS2",
                "cso" | "psp" => "PSP",
                "gcm" | "rvz" => "GameCube",
                "wii" | "wud" | "wux" => "Wii",
                "lnk" | "exe" => "PC (Windows)",
                "desktop" => "PC (Linux)",
                "zip" | "7z" => "Arcade", // Often arcade games are zipped
                _ => "",
            }.to_string();

            // Fallback: search folder name for platform keywords if extension mapping is weak or missing
            if platform_type.is_empty() {
                let folder_name = p.file_name().and_then(|s| s.to_str()).unwrap_or_default().to_lowercase();
                let platforms = crate::bridge::static_platforms::get_default_platforms();
                for plat in platforms {
                    let slug_lower = plat.slug.to_lowercase();
                    let name_lower = plat.name.to_lowercase();
                    // Avoid matching very short slugs like "PS" unless preceded by space or start of string
                    if folder_name.contains(&slug_lower) || folder_name.contains(&name_lower) {
                        platform_type = plat.slug.clone();
                        break;
                    }
                }
            }

            let result = serde_json::json!({
                "extensions": top_exts.join(","),
                "platform_type": platform_type,
                "collection_name": p.file_name().and_then(|s| s.to_str()).unwrap_or_default()
            });
            log::info!("[FolderAnalyze] Result: {}", result);

            let _ = tx.send(StoreMsg::FolderAnalyzed(result.to_string()));
        });
    }
}
