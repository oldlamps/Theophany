#![allow(non_snake_case)]
use qmetaobject::prelude::*;
use crate::core::store::StoreManager;
use std::sync::mpsc;
use std::cell::RefCell;
use std::collections::HashMap;
use crate::core::metadata_manager::MetadataManager;
use std::path::Path;
use std::os::unix::process::ExitStatusExt;
use std::sync::{Mutex, OnceLock};

struct GlobalStoreState {
    active_processes: HashMap<String, u32>,
    senders: Vec<mpsc::Sender<StoreMsg>>,
}

static GLOBAL_STATE: OnceLock<Mutex<GlobalStoreState>> = OnceLock::new();

fn get_global_state() -> &'static Mutex<GlobalStoreState> {
    GLOBAL_STATE.get_or_init(|| Mutex::new(GlobalStoreState {
        active_processes: HashMap::new(),
        senders: Vec::new(),
    }))
}

fn broadcast_msg(msg: StoreMsg) {
    let state = get_global_state().lock().unwrap();
    for tx in &state.senders {
        let _ = tx.send(msg.clone());
    }
}

#[derive(QObject, Default)]
#[allow(non_snake_case)]
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
    legendaryLibraryFinished: qt_signal!(results: QString),
    legendaryAuthUrlReceived: qt_signal!(url: QString),
    legendaryAuthFinished: qt_signal!(success: bool, message: QString),
    legendaryLogoutFinished: qt_signal!(success: bool, message: QString),
    legendaryAppInfoReceived: qt_signal!(json: QString),
    appDetailsReceived: qt_signal!(json: QString),
    featuredContentReceived: qt_signal!(json: QString),
    folderAnalyzed: qt_signal!(json: QString),
    steamAchievementsFinished: qt_signal!(json: QString, success: bool, message: QString),
    exodosLibraryFinished: qt_signal!(results: QString),

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
    refresh_legendary_library: qt_method!(fn(&self)),
    refresh_exodos_library: qt_method!(fn(&self, path: String)),
    check_legendary_auth: qt_method!(fn(&self) -> bool),
    get_legendary_auth_url: qt_method!(fn(&self)),
    authenticate_legendary: qt_method!(fn(&self, code: String)),
    logout_legendary: qt_method!(fn(&self)),
    install_legendary_game: qt_method!(fn(&self, app_name: String, path: String, with_dlcs: bool)),
    import_legendary_game: qt_method!(fn(&self, app_name: String, path: String)),
    uninstall_legendary_game: qt_method!(fn(&self, app_name: String)),
    get_legendary_app_info: qt_method!(fn(&self, app_name: String)),
    get_epic_config: qt_method!(fn(&self, rom_id: String) -> String),
    save_epic_config: qt_method!(fn(&self, rom_id: String, runner: String, prefix: String)),
    find_icon_path: qt_method!(fn(&self, icon_name: String) -> String),
    get_app_details: qt_method!(fn(&self, app_id: String)),
    analyze_folder: qt_method!(fn(&self, path: String)),
    poll: qt_method!(fn(&mut self)),
    pause_legendary_install: qt_method!(fn(&self, app_name: String)),
    resume_legendary_install: qt_method!(fn(&self, app_name: String)),
    cancel_legendary_install: qt_method!(fn(&self, app_name: String)),
    import_exodos_games: qt_method!(fn(&self, roms_json: String, platform_id: String, exodos_base_path: String)),

    // Internal
    tx: RefCell<Option<mpsc::Sender<StoreMsg>>>,
    rx: RefCell<Option<mpsc::Receiver<StoreMsg>>>,
    
    // Cache
    category_cache: RefCell<HashMap<String, String>>,
}

#[derive(Clone)]
enum StoreMsg {
    SearchFinished(String),
    InstallProgress(String, f32, String),
    InstallFinished(String, bool, String),
    LocalAppsFinished(String),
    SteamLibraryFinished(String),
    RemoteSteamLibraryFinished(String, bool, String),
    HeroicLibraryFinished(String),
    LutrisLibraryFinished(String),
    LegendaryLibraryFinished(String),
    LegendaryAuthUrlReceived(String),
    LegendaryAuthFinished(bool, String),
    LegendaryLogoutFinished(bool, String),
    LegendaryAppInfoReceived(String),
    AppDetailsReceived(String),
    CategoryFinished(String, String), // Category, JSON
    FeaturedContentReceived(String),
    FolderAnalyzed(String),
    SteamAchievementsFinished(String, bool, String),
    InstallStarted(String, u32),
    ExoDosLibraryFinished(String),
}

#[allow(non_snake_case)]
impl StoreBridge {
    fn ensure_channels(&self) {
        if self.tx.borrow().is_none() {
             let (tx, rx) = mpsc::channel();
             *self.tx.borrow_mut() = Some(tx.clone());
             *self.rx.borrow_mut() = Some(rx);
             
             // Register sender globally
             let mut state = get_global_state().lock().unwrap();
             state.senders.push(tx);
        }
    }

    fn poll(&mut self) {
        let rx_borrow = self.rx.borrow();
        if let Some(rx) = rx_borrow.as_ref() {
            while let Ok(msg) = rx.try_recv() {
                match msg {
                    StoreMsg::SearchFinished(j) => self.searchFinished(j.into()),
                    StoreMsg::InstallProgress(id, p, s_json) => {
                        // Use global state to check if process is active
                        let is_background = id == "exodos" || id == "Artwork" || id == "exodos_immediate" || id == "exodos_batch";
                        let is_active = get_global_state().lock().unwrap().active_processes.contains_key(&id);
                        if is_background || is_active {
                            self.installProgress(id.into(), p, s_json.into());
                        }
                    },
                    StoreMsg::InstallFinished(id, s, m) => {
                        // Clean up active process globally
                        get_global_state().lock().unwrap().active_processes.remove(&id);
                        self.installFinished(id.into(), s, m.into());
                    },
                    StoreMsg::InstallStarted(id, pid) => {
                        get_global_state().lock().unwrap().active_processes.insert(id, pid);
                    },
                    StoreMsg::LocalAppsFinished(j) => self.localAppsFinished(j.into()),
                    StoreMsg::SteamLibraryFinished(j) => self.steamLibraryFinished(j.into()),
                    StoreMsg::RemoteSteamLibraryFinished(j, s, m) => self.remoteSteamLibraryFinished(j.into(), s, m.into()),
                    StoreMsg::HeroicLibraryFinished(j) => self.heroicLibraryFinished(j.into()),
                    StoreMsg::LutrisLibraryFinished(j) => self.lutrisLibraryFinished(j.into()),
                    StoreMsg::LegendaryLibraryFinished(j) => self.legendaryLibraryFinished(j.into()),
                    StoreMsg::LegendaryAuthUrlReceived(url) => {
                        log::debug!("[StoreBridge] Emitting QML signal onLegendaryAuthUrlReceived for URL: {}", url);
                        self.legendaryAuthUrlReceived(url.into());
                    },
                    StoreMsg::LegendaryAuthFinished(s, m) => self.legendaryAuthFinished(s, m.into()),
                    StoreMsg::LegendaryLogoutFinished(s, m) => self.legendaryLogoutFinished(s, m.into()),
                    StoreMsg::LegendaryAppInfoReceived(j) => self.legendaryAppInfoReceived(j.into()),
                    StoreMsg::AppDetailsReceived(j) => self.appDetailsReceived(j.into()),
                    StoreMsg::CategoryFinished(cat, json) => {
                        self.category_cache.borrow_mut().insert(cat, json.clone());
                        self.searchFinished(json.into());
                    }
                    StoreMsg::FeaturedContentReceived(j) => self.featuredContentReceived(j.into()),
                    StoreMsg::FolderAnalyzed(j) => self.folderAnalyzed(j.into()),
                    StoreMsg::SteamAchievementsFinished(j, s, m) => self.steamAchievementsFinished(j.into(), s, m.into()),
                    StoreMsg::ExoDosLibraryFinished(j) => self.exodosLibraryFinished(j.into()),
                }
            }
        }
    }

    fn install_app(&self, app_id: String, platform_id: String, name: String, _summary: String, icon_url: String, description: String, screenshots_json: String, developer: String) {
        log::debug!("Starting Flatpak install for: {} ({})", name, app_id);
        self.ensure_channels();
        let tx = self.tx.borrow().as_ref().unwrap().clone();
        let app_id_clone = app_id.clone();
        let platform_id_clone = platform_id.clone();
        let name_clone = name.clone();
        let description_clone = description.clone();
        let screenshots_json_clone = screenshots_json.clone();
        let icon_url_clone = icon_url.clone();
        let developer_clone = developer.clone();
        
        std::thread::spawn(move || {
            let _ = tx.send(StoreMsg::InstallProgress(app_id_clone.clone(), 0.1, "Starting install...".into()));
            
            // If description or screenshots are missing (e.g. installed from Grid instead of Details), fetch them
            let (mut final_desc, final_screenshots) = if description_clone.is_empty() {
                match StoreManager::get_app_details(&app_id_clone) {
                    Ok(details) => (details.description, details.screenshots),
                    Err(_) => (description_clone, serde_json::from_str(&screenshots_json_clone).unwrap_or_default())
                }
            } else {
                (description_clone, serde_json::from_str(&screenshots_json_clone).unwrap_or_default())
            };

            // Strip HTML tags from description with better formatting handling
            let desc_tagged = final_desc
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
            final_desc = stripped.lines()
                .map(|l| l.trim())
                .filter(|l| !l.is_empty())
                .collect::<Vec<&str>>()
                .join("\n");

            match StoreManager::install_flatpak_with_details(&app_id_clone, &final_desc, &final_screenshots, &icon_url_clone) {
                Ok(_) => {
                    log::debug!("[FlatpakStore] Install successful, creating library entry...");
                    
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
                        description: Some(final_desc.clone()),
                        is_installed: Some(true),
                        cloud_saves_supported: None,
                        resources: None,
                    };

                    let db_path = crate::core::paths::get_data_dir().join("games.db");
                    if let Ok(db) = crate::core::db::DbManager::open(&db_path) {
                        let _ = db.insert_rom(&rom);
                        let mut meta = crate::core::models::GameMetadata::default();
                        meta.rom_id = rom.id.clone();
                        meta.title = Some(name_clone.clone());
                        meta.description = Some(final_desc);
                        meta.developer = Some(developer_clone);
                        meta.is_installed = true;
                        let _ = db.insert_metadata(&meta);
                        
                        // Auto-scan for assets immediately so they show up
                        log::debug!("Scanning assets for new install: {}", app_id_clone);
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
        log::debug!("Searching Flathub for: {}", query);
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
        log::debug!("Browsing Flathub storefront for category: {}", category);
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
        log::debug!("Scanning local apps...");
        self.ensure_channels();
        let tx = self.tx.borrow().as_ref().unwrap().clone();
        std::thread::spawn(move || {
            let results = StoreManager::scan_local_apps();
            let json = serde_json::to_string(&results).unwrap_or_default();
            let _ = tx.send(StoreMsg::LocalAppsFinished(json));
        });
    }

    fn refresh_steam_library(&self) {
        log::debug!("Scanning Steam library...");
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
        log::debug!("Fetching remote Steam library for: {}", sid);
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
        log::debug!("Scanning Heroic library...");
        self.ensure_channels();
        let tx = self.tx.borrow().as_ref().unwrap().clone();
        std::thread::spawn(move || {
            let results = StoreManager::scan_heroic_games();
            let json = serde_json::to_string(&results).unwrap_or_default();
            let _ = tx.send(StoreMsg::HeroicLibraryFinished(json));
        });
    }

    fn refresh_lutris_library(&self) {
        log::debug!("Scanning Lutris library...");
        self.ensure_channels();
        let tx = self.tx.borrow().as_ref().unwrap().clone();
        std::thread::spawn(move || {
            let results = StoreManager::scan_lutris_games();
            let json = serde_json::to_string(&results).unwrap_or_default();
            let _ = tx.send(StoreMsg::LutrisLibraryFinished(json));
        });
    }

    fn refresh_legendary_library(&self) {
        log::debug!("Scanning Legendary library...");
        self.ensure_channels();
        let tx = self.tx.borrow().as_ref().unwrap().clone();
        std::thread::spawn(move || {
            let results = StoreManager::scan_legendary_games();
            let json = serde_json::to_string(&results).unwrap_or_default();
            let _ = tx.send(StoreMsg::LegendaryLibraryFinished(json));
        });
    }

    fn refresh_exodos_library(&self, path: String) {
        log::debug!("Scanning eXoDOS library at: {}", path);
        self.ensure_channels();
        let tx = self.tx.borrow().as_ref().unwrap().clone();
        std::thread::spawn(move || {
            let results = crate::core::exodos::ExoDosManager::scan_directory(Path::new(&path));
            let json = serde_json::to_string(&results).unwrap_or_default();
            let _ = tx.send(StoreMsg::ExoDosLibraryFinished(json));
        });
    }

    fn check_legendary_auth(&self) -> bool {
        crate::core::legendary::LegendaryWrapper::is_authenticated()
    }

    fn get_legendary_auth_url(&self) {
        log::debug!("[StoreBridge] get_legendary_auth_url() was called from QML!");
        self.ensure_channels();
        let tx = self.tx.borrow().as_ref().unwrap().clone();
        std::thread::spawn(move || {
            match crate::core::legendary::LegendaryWrapper::get_auth_url() {
                Ok(url) => {
                    log::debug!("[StoreBridge] LegendaryWrapper successfully returned URL to Bridge. Sending to tx.");
                    let _ = tx.send(StoreMsg::LegendaryAuthUrlReceived(url));
                },
                Err(e) => {
                    log::error!("Failed to get Legendary auth URL: {}", e);
                    let _ = tx.send(StoreMsg::LegendaryAuthFinished(false, e.to_string()));
                }
            }
        });
    }

    fn authenticate_legendary(&self, code: String) {
        self.ensure_channels();
        let tx = self.tx.borrow().as_ref().unwrap().clone();
        std::thread::spawn(move || {
            match crate::core::legendary::LegendaryWrapper::authenticate(&code) {
                Ok(_) => {
                    let _ = tx.send(StoreMsg::LegendaryAuthFinished(true, "Authentication successful".into()));
                },
                Err(e) => {
                    log::error!("Legendary authentication failed: {}", e);
                    let _ = tx.send(StoreMsg::LegendaryAuthFinished(false, e.to_string()));
                }
            }
        });
    }

    fn logout_legendary(&self) {
        self.ensure_channels();
        let tx = self.tx.borrow().as_ref().unwrap().clone();
        std::thread::spawn(move || {
            match crate::core::legendary::LegendaryWrapper::logout() {
                Ok(_) => {
                    let _ = tx.send(StoreMsg::LegendaryLogoutFinished(true, "Logout successful".into()));
                },
                Err(e) => {
                    log::error!("Legendary logout failed: {}", e);
                    let _ = tx.send(StoreMsg::LegendaryLogoutFinished(false, e.to_string()));
                }
            }
        });
    }

    fn install_legendary_game(&self, app_name: String, path: String, with_dlcs: bool) {
        log::debug!("[LegendaryBridge] Starting install for: {} at {:?} with_dlcs={}", app_name, path, with_dlcs);
        self.ensure_channels();
        let _tx = self.tx.borrow().as_ref().unwrap().clone();
        let app_name_clone = app_name.clone();
        let install_path = if path.trim().is_empty() { None } else { Some(path.clone()) };

        std::thread::spawn(move || {
            let _ = broadcast_msg(StoreMsg::InstallProgress(app_name_clone.clone(), 0.0, "Initializing Legendary...".into()));
            
            match StoreManager::install_legendary_game(app_name_clone.clone(), install_path, with_dlcs) {
                Ok(mut child) => {
                    use std::io::{BufReader, Read};
                    
                    // Send PID to main thread to be stored in active processes BEFORE spawning reader
                    let _ = broadcast_msg(StoreMsg::InstallStarted(app_name_clone.clone(), child.id()));

                    let stderr = child.stderr.take().unwrap();
                    let stderr_reader = BufReader::new(stderr);
                    
                    let app_id_for_reader = app_name_clone.clone();
                    
                    // Legendary usually uses stderr for progress. Read byte-by-byte to handle both \n and \r
                    std::thread::spawn(move || {
                        let mut buf = Vec::new();
                        let mut last_progress = 0.0;
                        let mut last_dl = String::new();
                        let mut last_disk = String::new();
                        let mut last_eta = String::new();
                        
                        for byte_result in stderr_reader.bytes() {
                            if let Ok(b) = byte_result {
                                if b == b'\r' || b == b'\n' {
                                    if !buf.is_empty() {
                                        if let Ok(line) = String::from_utf8(buf.clone()) {
                                            let trimmed = line.trim();
                                            if !trimmed.is_empty() {
                                                log::debug!("[Legendary-CLI] {}", trimmed);
                                                
                                                let mut updated = false;
                                                if let Some(progress) = crate::core::legendary::LegendaryWrapper::parse_progress(trimmed) {
                                                    last_progress = progress;
                                                    updated = true;
                                                }
                                                
                                                if let Some(val) = crate::core::legendary::LegendaryWrapper::extract_value(trimmed, "ETA: ") {
                                                    last_eta = format!("ETA: {}", val);
                                                    updated = true;
                                                }

                                                if let Some(val) = crate::core::legendary::LegendaryWrapper::extract_value(trimmed, "Download") {
                                                    if val.contains("/s") {
                                                        last_dl = format!("DL: {}", val);
                                                        updated = true;
                                                    }
                                                }
                                                
                                                if let Some(val) = crate::core::legendary::LegendaryWrapper::extract_value(trimmed, "Disk") {
                                                    if val.contains("/s") {
                                                        last_disk = format!("Disk: {}", val);
                                                        updated = true;
                                                    }
                                                }
                                                
                                                if updated {
                                                    let clean = crate::core::legendary::LegendaryWrapper::clean_status_line(trimmed);
                                                    let mut status_map = serde_json::Map::new();
                                                    status_map.insert("progress".to_string(), serde_json::json!(last_progress));
                                                    status_map.insert("dl_rate".to_string(), serde_json::json!(last_dl));
                                                    status_map.insert("disk_rate".to_string(), serde_json::json!(last_disk));
                                                    status_map.insert("eta".to_string(), serde_json::json!(last_eta));
                                                    status_map.insert("raw_line".to_string(), serde_json::json!(clean));
                                                    
                                                    if let Some(val) = crate::core::legendary::LegendaryWrapper::extract_value(trimmed, "Downloaded: ") {
                                                        status_map.insert("downloaded".to_string(), serde_json::json!(val));
                                                    }
                                                    if let Some(val) = crate::core::legendary::LegendaryWrapper::extract_value(trimmed, "Written: ") {
                                                        status_map.insert("written".to_string(), serde_json::json!(val));
                                                    }

                                                    let status_json = serde_json::Value::Object(status_map).to_string();
                                                    let _ = broadcast_msg(StoreMsg::InstallProgress(app_id_for_reader.clone(), last_progress, status_json));
                                                }
                                            }
                                        }
                                        buf.clear();
                                    }
                                } else {
                                    buf.push(b);
                                }
                            } else {
                                break;
                            }
                        }
                    });

                    match child.wait() {
                        Ok(status) if status.success() => {
                            // Update DB to mark as installed
                            let db_path = crate::core::paths::get_data_dir().join("games.db");
                            if let Ok(db) = crate::core::db::DbManager::open(&db_path) {
                                let rom_id = format!("legendary-{}", app_name_clone);
                                let conn = db.get_connection();
                                let _ = conn.execute("UPDATE roms SET is_installed = 1 WHERE id = ?1", [&rom_id]);
                                let _ = conn.execute("UPDATE metadata SET is_installed = 1 WHERE rom_id = ?1", [&rom_id]);
                            }
                            let _ = broadcast_msg(StoreMsg::InstallFinished(app_name_clone, true, "Installed successfully".into()));
                        },
                        Ok(status) => {
                            let msg = if status.signal() == Some(15) {
                                "Cancelled".to_string()
                            } else {
                                format!("Legendary exited with status: {}", status)
                            };
                            let _ = broadcast_msg(StoreMsg::InstallFinished(app_name_clone, false, msg.into()));
                        },
                        Err(e) => {
                            let _ = broadcast_msg(StoreMsg::InstallFinished(app_name_clone, false, e.to_string().into()));
                        }
                    }
                },
                Err(e) => {
                    log::error!("Legendary install failed to start: {}", e);
                    let _ = broadcast_msg(StoreMsg::InstallFinished(app_name_clone, false, e.to_string().into()));
                }
            }
        });
    }

    fn get_legendary_app_info(&self, app_name: String) {
        log::debug!("[StoreBridge] get_legendary_app_info called for: {}", app_name);
        self.ensure_channels();
        let tx = self.tx.borrow().as_ref().unwrap().clone();
        
        std::thread::spawn(move || {
            match crate::core::legendary::LegendaryWrapper::get_game_info(&app_name) {
                Ok(json) => {
                    let _ = tx.send(StoreMsg::LegendaryAppInfoReceived(json));
                },
                Err(e) => {
                    log::error!("Failed to get legendary app info: {}", e);
                    // Could send an error signal here if needed, or just an empty json
                    let error_json = serde_json::json!({"error": e.to_string()}).to_string();
                    let _ = tx.send(StoreMsg::LegendaryAppInfoReceived(error_json));
                }
            }
        });
    }

    fn save_epic_config(&self, rom_id: String, runner: String, prefix: String) {
        log::debug!("[StoreBridge] Saving Epic config for {}: runner={}, prefix={}", rom_id, runner, prefix);
        let db_path = crate::core::paths::get_data_dir().join("games.db");
        if let Ok(db) = crate::core::db::DbManager::open(&db_path) {
            let conn = db.get_connection();
            // Check if config exists
            let mut stmt = conn.prepare("SELECT 1 FROM pc_configurations WHERE rom_id = ?1").unwrap();
            let exists = stmt.exists([&rom_id]).unwrap_or(false);

            if exists {
                let _ = conn.execute(
                    "UPDATE pc_configurations SET umu_proton_version = ?1, wine_prefix = ?2 WHERE rom_id = ?3",
                    [&runner, &prefix, &rom_id]
                );
            } else {
                let _ = conn.execute(
                    "INSERT INTO pc_configurations (rom_id, umu_proton_version, wine_prefix) VALUES (?1, ?2, ?3)",
                    [&rom_id, &runner, &prefix]
                );
            }
        }
    }

    fn get_epic_config(&self, rom_id: String) -> String {
        log::debug!("[StoreBridge] Fetching Epic config for {}", rom_id);
        let db_path = crate::core::paths::get_data_dir().join("games.db");
        if let Ok(db) = crate::core::db::DbManager::open(&db_path) {
            let conn = db.get_connection();
            let mut stmt = conn.prepare("SELECT umu_proton_version, wine_prefix FROM pc_configurations WHERE rom_id = ?1").unwrap();
            
            let mut rows = stmt.query([&rom_id]).unwrap();
            
            if let Ok(Some(row)) = rows.next() {
                let runner: Option<String> = row.get(0).unwrap_or(None);
                let prefix: Option<String> = row.get(1).unwrap_or(None);
                
                let mut map = serde_json::Map::new();
                if let Some(r) = runner { map.insert("runner".to_string(), serde_json::json!(r)); }
                if let Some(p) = prefix { map.insert("prefix".to_string(), serde_json::json!(p)); }
                
                return serde_json::Value::Object(map).to_string();
            }
        }
        "{}".to_string()
    }

    fn import_legendary_game(&self, app_name: String, path: String) {
        log::debug!("[LegendaryBridge] Starting import for: {} at {:?}", app_name, path);
        self.ensure_channels();
        let app_name_clone = app_name.clone();
        let import_path = path.clone();

        std::thread::spawn(move || {
            let _ = broadcast_msg(StoreMsg::InstallProgress(app_name_clone.clone(), 0.0, "Importing to Legendary...".into()));
            
            match StoreManager::import_legendary_game(app_name_clone.clone(), import_path) {
                Ok(mut child) => {
                    use std::io::{BufReader, Read};
                    
                    // Track PID for import
                    let _ = broadcast_msg(StoreMsg::InstallStarted(app_name_clone.clone(), child.id()));

                    let stderr = child.stderr.take().unwrap();
                    let stderr_reader = BufReader::new(stderr);
                    
                    let app_id_for_reader = app_name_clone.clone();
                    
                    // Legendary usually uses stderr. Read byte-by-byte to handle both \n and \r
                    std::thread::spawn(move || {
                        let mut buf = Vec::new();
                        let mut last_progress = 0.0;
                        let mut last_dl = String::new();
                        let mut last_disk = String::new();
                        let mut last_eta = String::new();
                        
                        for byte_result in stderr_reader.bytes() {
                            if let Ok(b) = byte_result {
                                if b == b'\r' || b == b'\n' {
                                    if !buf.is_empty() {
                                        if let Ok(line) = String::from_utf8(buf.clone()) {
                                            let trimmed = line.trim();
                                            if !trimmed.is_empty() {
                                                log::debug!("[Legendary-CLI] {}", trimmed);
                                                
                                                let mut updated = false;
                                                if let Some(progress) = crate::core::legendary::LegendaryWrapper::parse_progress(trimmed) {
                                                    last_progress = progress;
                                                    updated = true;
                                                }
                                                
                                                if let Some(val) = crate::core::legendary::LegendaryWrapper::extract_value(trimmed, "ETA: ") {
                                                    last_eta = format!("ETA: {}", val);
                                                    updated = true;
                                                }

                                                if let Some(val) = crate::core::legendary::LegendaryWrapper::extract_value(trimmed, "Download -") {
                                                    last_dl = format!("DL: {}", val).replace("  ", " ");
                                                    updated = true;
                                                } else if let Some(val) = crate::core::legendary::LegendaryWrapper::extract_value(trimmed, "Download") {
                                                    if val.contains("MiB/s") || val.contains("KiB/s") {
                                                        last_dl = format!("DL: {}", val).replace("  ", " ");
                                                        updated = true;
                                                    }
                                                }
                                                
                                                if let Some(val) = crate::core::legendary::LegendaryWrapper::extract_value(trimmed, "Disk -") {
                                                    last_disk = format!("Disk: {}", val).replace("  ", " ");
                                                    updated = true;
                                                } else if let Some(val) = crate::core::legendary::LegendaryWrapper::extract_value(trimmed, "Disk") {
                                                    if val.contains("MiB/s") || val.contains("KiB/s") {
                                                        last_disk = format!("Disk: {}", val).replace("  ", " ");
                                                        updated = true;
                                                    }
                                                }
                                                
                                                if updated {
                                                    let clean = crate::core::legendary::LegendaryWrapper::clean_status_line(trimmed);
                                                    let mut status_map = serde_json::Map::new();
                                                    status_map.insert("progress".to_string(), serde_json::json!(last_progress));
                                                    status_map.insert("dl_rate".to_string(), serde_json::json!(last_dl));
                                                    status_map.insert("disk_rate".to_string(), serde_json::json!(last_disk));
                                                    status_map.insert("eta".to_string(), serde_json::json!(last_eta));
                                                    status_map.insert("raw_line".to_string(), serde_json::json!(clean));

                                                    let status_json = serde_json::Value::Object(status_map).to_string();
                                                    let _ = broadcast_msg(StoreMsg::InstallProgress(app_id_for_reader.clone(), last_progress, status_json));
                                                }
                                            }
                                        }
                                        buf.clear();
                                    }
                                } else {
                                    buf.push(b);
                                }
                            } else {
                                break;
                            }
                        }
                    });

                    match child.wait() {
                        Ok(status) if status.success() => {
                            // Update DB to mark as installed
                            let db_path = crate::core::paths::get_data_dir().join("games.db");
                            if let Ok(db) = crate::core::db::DbManager::open(&db_path) {
                                let rom_id = format!("legendary-{}", app_name_clone);
                                let conn = db.get_connection();
                                let _ = conn.execute("UPDATE roms SET is_installed = 1 WHERE id = ?1", [&rom_id]);
                                let _ = conn.execute("UPDATE metadata SET is_installed = 1 WHERE rom_id = ?1", [&rom_id]);
                            }
                            let _ = broadcast_msg(StoreMsg::InstallFinished(app_name_clone, true, "Imported successfully".into()));
                        },
                        Ok(status) => {
                            let msg = if status.signal() == Some(15) {
                                "Cancelled".to_string()
                            } else {
                                format!("Legendary exited with status: {}", status)
                            };
                            let _ = broadcast_msg(StoreMsg::InstallFinished(app_name_clone, false, msg.into()));
                        },
                        Err(e) => {
                            let _ = broadcast_msg(StoreMsg::InstallFinished(app_name_clone, false, e.to_string().into()));
                        }
                    }
                },
                Err(e) => {
                    log::error!("Legendary import failed to start: {}", e);
                    let _ = broadcast_msg(StoreMsg::InstallFinished(app_name_clone, false, e.to_string().into()));
                }
            }
        });
    }
    fn uninstall_legendary_game(&self, app_name: String) {
        log::debug!("[LegendaryBridge] Starting uninstall for: {}", app_name);
        self.ensure_channels();
        let tx = self.tx.borrow().as_ref().unwrap().clone();
        let app_name_clone = app_name.clone();

        std::thread::spawn(move || {
            match StoreManager::uninstall_legendary_game(app_name_clone.clone()) {
                Ok(_) => {
                    let _ = tx.send(StoreMsg::InstallFinished(app_name_clone, true, "Uninstalled successfully".into()));
                },
                Err(e) => {
                    log::error!("Legendary uninstall failed: {}", e);
                    let _ = tx.send(StoreMsg::InstallFinished(app_name_clone, false, e.to_string().into()));
                }
            }
        });
    }

    fn import_local_app(&self, rom_json: String, platform_id: String) {
        log::debug!("[LocalImport] Received request for platform: {}", platform_id);
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
                            
                            log::debug!("[LocalImport] Inserting ROM: {:?}", final_rom.title);
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
                                    let _ = MetadataManager::save_sidecar(&platform_folder, rom_stem, &meta);

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

                                log::debug!("[LocalImport] Successfully imported: {:?}", final_rom.title);
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
        log::debug!("[SteamBulkImport] Requested import for {} bytes of JSON", roms_json_array.len());
            
        self.ensure_channels();
        let tx = self.tx.borrow().as_ref().unwrap().clone();
        let platform_id_clone = platform_id.clone();
        
        std::thread::spawn(move || {
            match serde_json::from_str::<Vec<crate::core::models::Rom>>(&roms_json_array) {
                Ok(roms) => {
                    log::debug!("[SteamBulkImport] Decoded {} ROMs from JSON", roms.len());
                    let db_path = crate::core::paths::get_data_dir().join("games.db");
                    match crate::core::db::DbManager::open(&db_path) {
                        Ok(db) => {
                            use crate::core::importer::BulkImporter;
                            let total = roms.len();
                            let save_locally = crate::bridge::settings::AppSettings::should_save_heroic_assets_locally();
                            let result = BulkImporter::import_roms(&db, roms, &platform_id_clone, save_locally, |progress, msg| {
                                let _ = tx.send(StoreMsg::InstallProgress("Artwork".into(), progress, msg.into()));
                            });

                            match result {
                                Ok(count) => {
                                    log::debug!("[SteamBulkImport] Successfully imported {}/{} games", count, total);
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
        log::debug!("Fetching details for app: {}", app_id);
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
        log::debug!("Analyzing folder: {}", path);
        self.ensure_channels();
        let tx = self.tx.borrow().as_ref().unwrap().clone();
        
        std::thread::spawn(move || {
            let p = Path::new(&path);
            if !p.exists() || !p.is_dir() {
                let _ = tx.send(StoreMsg::FolderAnalyzed("{}".into()));
                return;
            }

            let mut extensions = HashMap::new();
            log::debug!("[FolderAnalyze] Scanning: {:?}", p);
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
                            log::debug!("[FolderAnalyze] Found file: {:?} with ext: {}", entry.path(), ext);
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
            log::debug!("[FolderAnalyze] Top extensions: {:?}, primary: {}", top_exts, primary_ext);

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

            let folder_name = p.file_name().and_then(|s| s.to_str()).unwrap_or_default();
            let collection_name = if folder_name.to_lowercase() == "exodos" {
                "eXoDOS".to_string()
            } else {
                folder_name.to_string()
            };

            let result = serde_json::json!({
                "extensions": top_exts.join(","),
                "platform_type": platform_type,
                "collection_name": collection_name
            });
            log::debug!("[FolderAnalyze] Result: {}", result);

            let _ = tx.send(StoreMsg::FolderAnalyzed(result.to_string()));
        });
    }
    fn pause_legendary_install(&self, app_name: String) {
        log::info!("[LegendaryBridge] Requested pause for: {}", app_name);
        let pid = get_global_state().lock().unwrap().active_processes.get(&app_name).copied();
        
        if let Some(pid) = pid {
            log::info!("[LegendaryBridge] Pausing install for: {} (PGID: {})", app_name, pid);
            // Send STOP to the process group (negative PID)
            let status = std::process::Command::new("kill").arg("-STOP").arg(format!("-{}", pid)).status();
            log::info!("[LegendaryBridge] Pause command status: {:?}", status);
        } else {
            let active = get_global_state().lock().unwrap().active_processes.keys().cloned().collect::<Vec<_>>();
            log::warn!("[LegendaryBridge] No active process found for: {}. Active: {:?}", app_name, active);
        }
    }

    fn resume_legendary_install(&self, app_name: String) {
        log::info!("[LegendaryBridge] Requested resume for: {}", app_name);
        let pid = get_global_state().lock().unwrap().active_processes.get(&app_name).copied();

        if let Some(pid) = pid {
            log::info!("[LegendaryBridge] Resuming install for: {} (PGID: {})", app_name, pid);
            // Send CONT to the process group
            let status = std::process::Command::new("kill").arg("-CONT").arg(format!("-{}", pid)).status();
            log::info!("[LegendaryBridge] Resume command status: {:?}", status);
        } else {
            let active = get_global_state().lock().unwrap().active_processes.keys().cloned().collect::<Vec<_>>();
            log::warn!("[LegendaryBridge] No active process found for resume: {}. Active: {:?}", app_name, active);
        }
    }

    fn cancel_legendary_install(&self, app_name: String) {
        log::info!("[LegendaryBridge] Requested cancel for: {}", app_name);
        let pid = get_global_state().lock().unwrap().active_processes.remove(&app_name);

        if let Some(pid) = pid {
            log::info!("[LegendaryBridge] Cancelling install for: {} (PGID: {})", app_name, pid);
            // Send TERM to the entire process group
            let status = std::process::Command::new("kill").arg("-TERM").arg(format!("-{}", pid)).status();
            log::info!("[LegendaryBridge] Cancel command status: {:?}", status);
        } else {
            let active = get_global_state().lock().unwrap().active_processes.keys().cloned().collect::<Vec<_>>();
            log::warn!("[LegendaryBridge] No active process found for cancel: {}. Active: {:?}", app_name, active);
        }
    }

    fn import_exodos_games(&self, roms_json: String, platform_id: String, exodos_base_path: String) {
        log::debug!("Importing eXoDOS games for platform: {}", platform_id);
        self.ensure_channels();
        let tx = self.tx.borrow().as_ref().unwrap().clone();
        log::debug!("Importing eXoDOS games for platform: {}. JSON length: {}", platform_id, roms_json.len());
        let roms: Vec<crate::core::models::Rom> = match serde_json::from_str(&roms_json) {
            Ok(r) => r,
            Err(e) => {
                log::error!("[StoreBridge] Failed to parse eXoDOS ROMs JSON: {}. JSON was: {}", e, roms_json);
                let _ = tx.send(StoreMsg::InstallFinished("exodos".to_string(), false, format!("Failed to parse game data: {}", e)));
                return;
            }
        };
        let db_path = crate::core::paths::get_data_dir().join("games.db");
        let images_path = std::path::Path::new(&exodos_base_path).join("Images/MS-DOS");

        std::thread::spawn(move || {
            if let Ok(db) = crate::core::db::DbManager::open(&db_path) {
                // Determine platform folder name
                let platform_folder = match db.get_platform(&platform_id) {
                    Ok(Some(p)) => p.platform_type.clone()
                        .or(Some(p.name.clone()))
                        .unwrap_or_else(|| "DOS".to_string())
                        .replace(" ", "_")
                        .replace("/", "-")
                        .replace("\\", "-"),
                    _ => "DOS".to_string(),
                };

                let total = roms.len();
                
                // --- Phase 1: Immediate Batch Insertion ---
                // We do a fast pass to get games into the library immediately.
                if let Ok(db) = crate::core::db::DbManager::open(&db_path) {
                    // VERIFY PLATFORM EXISTS (due to FK constraints)
                    match db.get_platform(&platform_id) {
                        Ok(Some(_)) => log::info!("[StoreBridge] Confirmed platform {} exists in DB", platform_id),
                        Ok(None) => {
                            log::error!("[StoreBridge] Platform {} NOT FOUND in database. Import will fail FK constraints.", platform_id);
                            let _ = tx.send(StoreMsg::InstallFinished("exodos".to_string(), false, format!("Platform {} not found. Try scanning again.", platform_id)));
                            return;
                        },
                        Err(e) => {
                            log::error!("[StoreBridge] Database error checking platform: {}", e);
                            return;
                        }
                    }

                    let _ = db.get_connection().execute("BEGIN TRANSACTION", []);
                    for rom in &roms {
                        let mut final_rom = rom.clone();
                        final_rom.platform_id = platform_id.clone();
                        
                        // Phase 1: fast insert — no disk I/O (no sidecar), use ROM data directly
                        final_rom.is_installed = Some(false); // default; Phase 2 will fix from sidecars
                        
                        log::debug!("[StoreBridge] Inserting ROM: {} ({})", final_rom.title.as_deref().unwrap_or("Unknown"), final_rom.id);
                        if let Err(e) = db.insert_rom(&final_rom) {
                            log::error!("[StoreBridge] Failed to insert ROM {}: {}", final_rom.id, e);
                            continue;
                        }

                        // Basic metadata from ROM data only (no sidecar disk read)
                        let mut meta = crate::core::models::GameMetadata::default();
                        meta.rom_id = final_rom.id.clone();
                        meta.title = final_rom.title.clone();
                        meta.tags = final_rom.tags.clone();
                        meta.developer = final_rom.developer.clone();
                        meta.publisher = final_rom.publisher.clone();
                        meta.genre = final_rom.genre.clone();
                        meta.release_date = final_rom.release_date.clone();
                        meta.description = final_rom.description.clone();
                        meta.is_installed = false;
                        
                        if let Err(e) = db.insert_metadata(&meta) {
                            log::error!("[StoreBridge] Failed to insert metadata for {}: {}", final_rom.id, e);
                        }

                        // Insert resources if any
                        if let Some(resources) = &final_rom.resources {
                            for res in resources {
                                if let Err(e) = db.insert_resource(res) {
                                    log::error!("[StoreBridge] Failed to insert resource for {}: {}", final_rom.id, e);
                                }
                            }
                        }
                    }
                    match db.get_connection().execute("COMMIT", []) {
                        Ok(_) => log::debug!("[StoreBridge] Successfully committed eXoDOS import transaction"),
                        Err(e) => log::error!("[StoreBridge] Failed to commit eXoDOS import transaction: {}", e),
                    }
                }

                
                // Notify UI that library should be refreshed to show new entries
                let _ = tx.send(StoreMsg::InstallFinished("exodos_immediate".to_string(), true, "Games added to library, processing artwork...".to_string()));

                // --- Phase 2: Background Enrichment ---
                if let Ok(db) = crate::core::db::DbManager::open(&db_path) {
                    for (i, rom) in roms.into_iter().enumerate() {
                        let title = rom.title.clone().unwrap_or_else(|| "Unknown".to_string());
                        
                        if i % 20 == 0 || i == total - 1 {
                            let progress = i as f32 / total as f32;
                            let _ = tx.send(StoreMsg::InstallProgress("exodos".to_string(), progress, format!("Processing {}...", title)));
                        }

                        let rom_stem_str = std::path::Path::new(&rom.filename)
                            .file_stem()
                            .and_then(|s| s.to_str())
                            .unwrap_or(&rom.filename)
                            .to_string();
                        let rom_stem = &rom_stem_str;

                        let current_platform_folder = if platform_id == "DOS" || platform_id == "dos" {
                            "DOS".to_string()
                        } else {
                            platform_folder.clone()
                        };

                        // 1. Link artwork
                        if images_path.exists() {
                            crate::core::exodos::ExoDosManager::link_artwork(&title, &images_path, &current_platform_folder, rom_stem);
                            
                            let data_dir = crate::core::paths::get_data_dir();
                            let base_image_path = data_dir.join("Images").join(&current_platform_folder).join(rom_stem);

                            let standard_mappings = [
                                ("Box - Front", "box"),
                                ("Background", "background"),
                                ("Screenshot", "none"),
                                ("Box - Back", "none"),
                                ("Box - 3D", "none"),
                                ("Logo", "none"),
                            ];

                            for (target_cat, rom_target) in standard_mappings {
                                let norm_name = target_cat.to_lowercase().replace(" ", "_");
                                let cat_dir = base_image_path.join(target_cat);
                                
                                if let Ok(entries) = std::fs::read_dir(&cat_dir) {
                                    for entry in entries.flatten() {
                                        let path = entry.path();
                                        if path.is_file() {
                                            let file_name = path.file_name().unwrap_or_default().to_string_lossy();
                                            if file_name.starts_with(&norm_name) {
                                                let abs_path = path.to_string_lossy().to_string();
                                                let _ = db.insert_asset(&rom.id, target_cat, &abs_path);
                                                
                                                if rom_target == "box" {
                                                    let _ = db.get_connection().execute("UPDATE roms SET boxart_path = ?1 WHERE id = ?2", rusqlite::params![abs_path, rom.id]);
                                                } else if rom_target == "background" {
                                                    let _ = db.get_connection().execute("UPDATE roms SET background_path = ?1 WHERE id = ?2", rusqlite::params![abs_path, rom.id]);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // 2. Metadata Sidecar (Ensure sidecar is updated/created)
                        let sidecar = crate::core::metadata_manager::MetadataManager::load_sidecar(&current_platform_folder, rom_stem);
                        let meta = if let Some(mut m) = sidecar {
                            m.rom_id = rom.id.clone();
                            if m.title.is_none() || m.title.as_deref() == Some("") { m.title = rom.title.clone(); }
                            if m.description.is_none() || m.description.as_deref() == Some("") { m.description = rom.description.clone(); }
                            let current_tags2 = m.tags.as_deref().unwrap_or("");
                            if current_tags2 == "eXoDOS" || current_tags2 == "" { m.tags = rom.tags.clone(); }
                            if m.developer.is_none() || m.developer.as_deref() == Some("") { m.developer = rom.developer.clone(); }
                            if m.publisher.is_none() || m.publisher.as_deref() == Some("") { m.publisher = rom.publisher.clone(); }
                            if m.genre.is_none() || m.genre.as_deref() == Some("") { m.genre = rom.genre.clone(); }
                            if m.release_date.is_none() || m.release_date.as_deref() == Some("") { m.release_date = rom.release_date.clone(); }
                            m
                        } else {
                            // Minimal: basic metadata from ROM if no sidecar exists
                            let mut m = crate::core::models::GameMetadata::default();
                            m.rom_id = rom.id.clone();
                            m.title = rom.title.clone();
                            m.description = rom.description.clone();
                            m.tags = rom.tags.clone();
                            m.developer = rom.developer.clone();
                            m.publisher = rom.publisher.clone();
                            m.genre = rom.genre.clone();
                            m.release_date = rom.release_date.clone();
                            m
                        };
                        
                        let _ = db.insert_metadata(&meta);
                        let _ = crate::core::metadata_manager::MetadataManager::save_sidecar(&current_platform_folder, rom_stem, &meta);
                        // (No sidecar = metadata already inserted correctly in Phase 1, skip disk write)

                        // Incremental Refresh every 500 games
                        if i > 0 && i % 500 == 0 {
                            let _ = tx.send(StoreMsg::InstallFinished("exodos_immediate".to_string(), true, "Batch update".to_string()));
                        }
                    }
                    
                    let _ = tx.send(StoreMsg::InstallFinished("exodos".to_string(), true, "Import completed".to_string()));
                }
            }
        });
    }
}
