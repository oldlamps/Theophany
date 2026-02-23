#![allow(non_snake_case)]
use crate::core::db::DbManager;
use crate::core::models::Platform;
use crate::core::scraper::{client::ScraperClient, search_engine::SearchEngineProvider, ScraperProvider};
use qmetaobject::prelude::*;
use std::cell::RefCell;
use std::sync::{Arc, mpsc};
use std::io::Write;
use uuid::Uuid;

use crate::core::runtime::get_runtime;
use crate::core::paths;

fn resolve_asset_path(path: &str) -> String {
    if path.is_empty() {
        return "".to_string();
    }
    
    // If it's already a full URI or an absolute path, don't touch it much
    if path.starts_with("http") || path.starts_with("file://") || path.starts_with("qrc:/") {
        return path.to_string();
    }
    
    // Handle relative assets
    if path.starts_with("assets/") {
        let full_path = paths::get_data_dir().join(path);
        return format!("file://{}", full_path.to_string_lossy());
    }
    
    // If it starts with / it's an absolute local path
    if path.starts_with("/") {
        return format!("file://{}", path);
    }
    
    // If none of the above, it might be an emoji or a raw string. 
    // Only prepend file:// if it actually looks like a path (has a slash or a known extension)
    if path.contains('/') || path.contains('\\') || path.contains('.') {
        return format!("file://{}", path);
    }
    
    // Fallback: Return as-is (e.g. for emojis)
    path.to_string()
}

enum AsyncResponse {
    IconSearchFinished(String),
    IconDownloadFinished(String),
}

#[derive(QObject, Default)]
pub struct PlatformListModel {
    // Parent class: QAbstractListModel
    base: qt_base_class!(trait QAbstractListModel),

    // Internal data storage
    platforms: RefCell<Vec<Platform>>,
    
    // DB Access
    db_path: RefCell<String>,

    // Scraper Client
    scraper_client: RefCell<Option<Arc<ScraperClient>>>,
    
    // Async Response Channel
    tx: RefCell<Option<mpsc::Sender<AsyncResponse>>>,
    rx: RefCell<Option<mpsc::Receiver<AsyncResponse>>>,

    // Cache Buster for QML Images
    pub cache_buster: qt_property!(i32; NOTIFY cache_buster_changed),
    pub cache_buster_changed: qt_signal!(),

    // Methods exposed to QML

    // Methods exposed to QML
    init: qt_method!(fn(&mut self, db_path: String)),
    refresh: qt_method!(fn(&mut self)),
    deleteSystem: qt_method!(fn(&mut self, id: String, delete_assets: bool)),
    getName: qt_method!(fn(&self, index: i32) -> String),
    updateSystem: qt_method!(fn(&mut self, id: String, name: String, extensions: String, command: String, emulator_id: String, platform_type: String, icon: String, pc_config: String)),
    
    // Scraping
    searchSystemIcons: qt_method!(fn(&mut self, query: String)),
    downloadSystemIcon: qt_method!(fn(&mut self, url: String, system_name: String)),
    checkAsyncResponses: qt_method!(fn(&mut self)),
    getProtonVersions: qt_method!(fn(&self) -> String),
    createPlatform: qt_method!(fn(&mut self, name: String) -> String),
    getId: qt_method!(fn(&self, index: i32) -> String),
    getRowById: qt_method!(fn(&self, id: String) -> i32),
    ensureSystemIcon: qt_method!(fn(&mut self, url: String, slug: String) -> String),

    // Signals
    iconSearchFinished: qt_signal!(json_results: String),
    iconDownloadFinished: qt_signal!(local_path: String),
}

impl QAbstractListModel for PlatformListModel {
    fn row_count(&self) -> i32 {
        self.platforms.borrow().len() as i32
    }

    fn data(&self, index: QModelIndex, role: i32) -> QVariant {
        let platforms = self.platforms.borrow();
        let idx = index.row() as usize;

        if idx >= platforms.len() {
            return QVariant::default();
        }

        let platform = &platforms[idx];

        match role {
            // Qt::DisplayRole = 0
            0 => QVariant::from(QString::from(platform.name.as_str())), 
            
            // Custom Roles
            256 => QVariant::from(QString::from(platform.id.as_str())),   // idRole
            257 => QVariant::from(QString::from(platform.name.as_str())), // nameRole
            258 => QVariant::from(QString::from(platform.extension_filter.as_str())), // extensionRole
            259 => QVariant::from(QString::from(platform.command_template.clone().unwrap_or_default().as_str())), // commandRole
            260 => QVariant::from(QString::from(platform.default_emulator_id.clone().unwrap_or_default().as_str())), // emulatorRole
            261 => QVariant::from(QString::from(platform.platform_type.clone().unwrap_or_default().as_str())), // typeRole
            262 => QVariant::from(QString::from(platform.icon.as_deref().map(resolve_asset_path).unwrap_or_default())), // iconRole
            263 => QVariant::from(QString::from(platform.pc_config_json.clone().unwrap_or_default().as_str())), // pcConfigRole
            _ => QVariant::default(),
        }
    }

    fn role_names(&self) -> std::collections::HashMap<i32, QByteArray> {
        let mut roles = std::collections::HashMap::new();
        roles.insert(256, QByteArray::from("platformId"));
        roles.insert(257, QByteArray::from("platformName"));
        roles.insert(258, QByteArray::from("platformExtensions"));
        roles.insert(259, QByteArray::from("platformCommand"));
        roles.insert(260, QByteArray::from("platformEmulatorId"));
        roles.insert(261, QByteArray::from("platformType"));
        roles.insert(262, QByteArray::from("platformIcon"));
        roles.insert(263, QByteArray::from("pcConfig"));
        roles
    }
}

impl PlatformListModel {
    fn init(&mut self, db_path: String) {
        *self.db_path.borrow_mut() = db_path;
        
        // Initialize Channels
        let (tx, rx) = mpsc::channel();
        *self.tx.borrow_mut() = Some(tx);
        *self.rx.borrow_mut() = Some(rx);

        self.refresh();
    }

    fn refresh(&mut self) {
        let path = self.db_path.borrow().clone();
        if path.is_empty() {
            return;
        }

        // Access DB
        if let Ok(db) = DbManager::open(&path) {
            if let Ok(mut new_platforms) = db.get_all_platforms() {
                new_platforms.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
                self.begin_reset_model();
                *self.platforms.borrow_mut() = new_platforms;
                self.end_reset_model();
                self.cache_buster += 1;
                self.cache_buster_changed();
            }
        }
    }

    #[allow(non_snake_case)]
    fn deleteSystem(&mut self, id: String, delete_assets: bool) {
        let path = self.db_path.borrow().clone();
        if let Ok(db) = DbManager::open(&path) {
            // Cascade Delete Games
            // 1. Get all game IDs for this platform
            let conn = db.get_connection();
            let mut game_ids = Vec::new();
            if let Ok(mut stmt) = conn.prepare("SELECT id, path, filename FROM roms WHERE platform_id = ?1") {
                if let Ok(rows) = stmt.query_map([&id], |row| {
                    Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?, row.get::<_, String>(2)?))
                }) {
                    for row in rows {
                        if let Ok(data) = row {
                            game_ids.push(data);
                        }
                    }
                }
            }

            // 2. Iterate and delete each game (Delete Assets + DB Entry only)
            for (game_id, _game_path, filename) in game_ids {
                // SKIP Flatpak Uninstall - User requested to NOT uninstall content
                
                // Delete Game Assets
                if delete_assets {
                     if let Ok(Some((platform_folder, _))) = db.get_rom_path_info(&game_id) {
                         // 1. Try standard stem
                         let rom_stem_std = std::path::Path::new(&filename).file_stem().and_then(|s| s.to_str()).unwrap_or(&filename);
                         let _ = crate::core::metadata_manager::MetadataManager::delete_assets(&platform_folder, rom_stem_std);
                         
                         // 2. Try full filename (fallback for flatpaks/etc)
                         if rom_stem_std != filename {
                             let _ = crate::core::metadata_manager::MetadataManager::delete_assets(&platform_folder, &filename);
                         }
                     }
                }
                
                // Delete Game from DB
                let _ = db.delete_rom(&game_id);
            }

            // 3. Delete Platform Assets Folder (if requested)
            if delete_assets {
                if let Ok(platforms) = db.get_platforms() {
                    if let Some(p) = platforms.iter().find(|p| p.id == id) {
                         // Use platform name as folder name (sanitized)
                         let folder_name = p.name.replace("/", "-").replace("\\", "-");
                         let _ = crate::core::metadata_manager::MetadataManager::delete_platform_assets(&folder_name);
                         
                         // Also try slug just in case
                         if p.slug != folder_name {
                             let _ = crate::core::metadata_manager::MetadataManager::delete_platform_assets(&p.slug);
                         }
                    }
                }
            }
            
            // 4. Delete Platform from DB
            if let Err(e) = db.delete_platform(&id) {
                log::error!("Failed to delete platform: {}", e);
            } else {
                self.refresh();
            }
        }
    }

    #[allow(non_snake_case)]
    fn updateSystem(&mut self, id: String, name: String, extensions: String, command: String, emulator_id: String, platform_type: String, icon: String, pc_config: String) {
        let path = self.db_path.borrow().clone();
        if let Ok(db) = DbManager::open(&path) {
            let em_id_opt = if emulator_id.is_empty() { None } else { Some(emulator_id.as_str()) };
            
            // Normalize ID
            let normalized_type = if platform_type.to_lowercase() == "windows" {
                "PC (Windows)".to_string()
            } else if platform_type.to_lowercase() == "linux" {
                "PC (Linux)".to_string()
            } else {
                platform_type
            };

            let type_opt = if normalized_type.is_empty() { None } else { Some(normalized_type.as_str()) };
            let icon_opt = if icon.is_empty() { None } else { Some(icon.as_str()) };
            let pc_opt = if pc_config.is_empty() { None } else { Some(pc_config.as_str()) };

            let platform = Platform {
                id: id.clone(),
                slug: name.to_lowercase().replace(" ", "-"),
                name,
                extension_filter: extensions,
                command_template: Some(command),
                default_emulator_id: em_id_opt.map(|s| s.to_string()),
                platform_type: type_opt.map(|s| s.to_string()),
                icon: icon_opt.map(|s| s.to_string()),
                pc_config_json: pc_opt.map(|s| s.to_string()),
            };

            if let Err(e) = db.insert_platform(&platform) {
                log::error!("Failed to update platform: {}", e);
            } else {
                self.refresh();
            }
        }
    }
    #[allow(non_snake_case)]
    fn createPlatform(&mut self, name: String) -> String {
        let path = self.db_path.borrow().clone();
        if let Ok(db) = DbManager::open(&path) {
            let new_id = Uuid::new_v4().to_string();
            let platform = Platform {
                id: new_id.clone(),
                slug: name.to_lowercase().replace(" ", "-"),
                name,
                extension_filter: String::new(),
                command_template: None,
                default_emulator_id: None,
                platform_type: None,
                icon: None,
                pc_config_json: None,
            };

            if let Ok(_) = db.insert_platform(&platform) {
                self.refresh();
                return new_id;
            }
        }
        String::new()
    }

    #[allow(non_snake_case)]
    fn getId(&self, index: i32) -> String {
        self.platforms.borrow().get(index as usize).map(|p| p.id.clone()).unwrap_or_default()
    }

    #[allow(non_snake_case)]
    fn getRowById(&self, id: String) -> i32 {
        self.platforms.borrow().iter().position(|p| p.id == id).map(|pos| pos as i32).unwrap_or(-1)
    }

    #[allow(non_snake_case)]
    fn getName(&self, index: i32) -> String {
        self.platforms.borrow().get(index as usize).map(|p| p.name.clone()).unwrap_or_default()
    }

    fn get_scraper_client(&self) -> Arc<ScraperClient> {
        let mut client = self.scraper_client.borrow_mut();
        if client.is_none() {
            let _guard = get_runtime().enter();
            *client = Some(Arc::new(ScraperClient::new()));
        }
        client.as_ref().unwrap().clone()
    }

    #[allow(non_snake_case)]
    fn searchSystemIcons(&mut self, query: String) {
        let client = self.get_scraper_client();
        let tx = match self.tx.borrow().as_ref() {
            Some(t) => t.clone(),
            None => return,
        };
        
        get_runtime().spawn(async move {
            let provider = SearchEngineProvider::new(client);
            // Append keywords to query to optimize for icons
            // e.g. "NES icon logo transparent"
            // But user might have already typed "icon", so let's rely on the query or append smart keywords?
            // User query is passed as is from the dialog (which adds suffix)
            
            match provider.search(&query, None).await {
                Ok(results) => {
                    let json = serde_json::to_string(&results).unwrap_or_default();
                    let _ = tx.send(AsyncResponse::IconSearchFinished(json));
                },
                Err(e) => {
                    log::error!("Icon Search error: {}", e);
                    let _ = tx.send(AsyncResponse::IconSearchFinished("[]".to_string()));
                },
            }
        });
    }

    #[allow(non_snake_case)]
    fn ensureSystemIcon(&mut self, url: String, slug: String) -> String {
        let assets_dir = crate::core::paths::get_assets_dir();
        let system_dir = assets_dir.join("systems");
        
        // Special case mappings for icon files that don't match slug
        let safe_slug = match slug.as_str() {
            "PC (Windows)" => "windows".to_string(),
            "PC (Linux)" => "linux".to_string(),
            _ => slug.to_lowercase()
        };
        
        // Check for common extensions
        let stems = ["png", "jpg", "jpeg", "svg"];
        for ext in stems {
            let filename = format!("{}.{}", safe_slug, ext);
            let path = system_dir.join(&filename);
            if path.exists() {
                return format!("assets/systems/{}", filename);
            }
        }
        
        // If we are here, file doesn't exist. Trigger download.
        if !url.is_empty() {
             self.downloadSystemIcon(url, safe_slug.clone());
             // Optimistically return the path we expect
             return format!("assets/systems/{}.png", safe_slug); 
        }
        
        String::new()
    }

    #[allow(non_snake_case)]
    fn downloadSystemIcon(&mut self, url: String, system_name: String) {
        let client = self.get_scraper_client();
        let tx = match self.tx.borrow().as_ref() {
            Some(t) => t.clone(),
            None => return,
        };
        
        get_runtime().spawn(async move {
            // Logic to download
            let assets_dir = crate::core::paths::get_assets_dir();
            let systems_dir = assets_dir.join("systems");
            if !systems_dir.exists() {
                let _ = std::fs::create_dir_all(&systems_dir);
            }
            
            // Use provided name (slug) directly if possible, or clean existing way
            // The previous logic was:
            // let safe_name = system_name...
            // But now for ensureSystemIcon we pass the slug as system_name.
            // Let's keep the sanitization just in case but slug should be safe.
            
            let safe_name = system_name.chars()
                .filter(|c| c.is_alphanumeric() || *c == ' ' || *c == '-' || *c == '_')
                .collect::<String>()
                .trim()
                .replace(" ", "_")
                .to_lowercase();
            
            let safe_name = if safe_name.is_empty() { "unknown".to_string() } else { safe_name };

            // Try to download
             match client.get_bytes(&url).await {
                Ok(bytes) => {
                    // Detect extension or default to png
                    let ext = if url.to_lowercase().ends_with(".jpg") || url.to_lowercase().ends_with(".jpeg") {
                        "jpg"
                    } else if url.to_lowercase().ends_with(".svg") {
                        "svg"
                    } else {
                        "png" 
                    };
                    
                    let filename = format!("{}.{}", safe_name, ext);
                    let file_path = systems_dir.join(&filename);
                    
                    if let Ok(mut file) = std::fs::File::create(&file_path) {
                         if let Ok(_) = file.write_all(&bytes) {
                             let rel_path = format!("assets/systems/{}", filename);
                             let _ = tx.send(AsyncResponse::IconDownloadFinished(rel_path));
                             return;
                         }
                    }
                },
                Err(e) => log::error!("Failed to download icon: {}", e),
             }
        });
    }

    #[allow(non_snake_case)]
    fn checkAsyncResponses(&mut self) {
        let mut rx_borrow = self.rx.borrow_mut();
        if let Some(rx) = rx_borrow.as_mut() {
            while let Ok(msg) = rx.try_recv() {
                match msg {
                    AsyncResponse::IconSearchFinished(json) => self.iconSearchFinished(json),
                    AsyncResponse::IconDownloadFinished(path) => {
                        self.cache_buster += 1;
                        self.cache_buster_changed();
                        self.iconDownloadFinished(path);
                    }
                }
            }
        }
    }

    #[allow(non_snake_case)]
    fn getProtonVersions(&self) -> String {
        let versions = crate::core::paths::get_proton_versions();
        // Return as JSON array of {name, path}
        let vec: Vec<serde_json::Value> = versions.into_iter().map(|(n, p)| {
            serde_json::json!({ "name": n, "path": p })
        }).collect();
        serde_json::to_string(&vec).unwrap_or_default()
    }
}
