#![allow(non_snake_case)]
#![allow(dead_code)]
use crate::core::db::DbManager;
use crate::core::models::{Platform, Rom, GameResource};
use crate::core::scanner::Scanner;
use crate::core::scraper::client::ScraperClient;
use crate::core::scraper::manager::ScraperManager;
use crate::core::metadata_manager::MetadataManager;
use crate::core::scraper::{ScraperProvider, ScrapedMetadata, ScraperSearchResult};
use crate::core::scraper::search_engine::SearchEngineProvider;
use qmetaobject::prelude::*;
use qmetaobject::{QVariantList, QVariantMap};
use std::cell::RefCell;
use std::sync::{Arc, mpsc};
use std::path::Path;
use uuid::Uuid;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;
use std::process::Command;
use rand::Rng;
use crate::core::retroachievements::RetroAchievementsClient;
use crate::bridge::retroachievements::perform_ra_scrape;
use crate::core::paths;
use rusqlite::ToSql;
use tokio::sync::Notify;
use crate::core::store::StoreManager;
use std::collections::HashMap;


use crate::core::runtime::get_runtime;

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

fn normalize_url(url: &str) -> String {
    let mut s = url.trim().to_lowercase();
    
    // Protocol normalization
    if s.starts_with("http://") {
        s = s.replace("http://", "https://");
    }

    // Strip all trailing slashes
    while s.ends_with('/') {
        s.pop();
    }
    s
}

fn resolve_local_path(path: &str) -> String {
    if path.is_empty() {
        return "".to_string();
    }
    
    if path.starts_with("assets/") {
        let full_path = paths::get_data_dir().join(path);
        return full_path.to_string_lossy().to_string();
    }
    
    path.to_string()
}

enum AsyncResponse {
    SearchFinished(String),
    FetchFinished(String),
    FetchFailed(String),
    AssetDownloadFinished(String, String),
    AssetDownloadFailed(String, String),
    PlaytimeUpdated(String),
    GameDataChanged(String), // For asset updates - doesn't trigger RA check
    ImportProgress(f32, String),
    AssetDownloadProgress(String), // New signal for lightweight status updates

    ImportFinished(String, Vec<String>), // platform_id, list_of_rom_ids
    AutoScrapeFinished(String, String), // rom_id, JSON
    AutoScrapeFailed(String, String), // rom_id, Message
    RefreshFinished(Vec<Rom>, u64, i32, i32, String, String, String), // Data, Request ID, Lib Count, Total Games, Time Str, Last Played Game, Last Played ID
    
    // Bulk Scraper
    BulkProgress(f32, String), // Progress, Status Message
    BulkGameUpdate(String, String), // ID, JSON
    BulkItemFinished(String), // ID (Iteration complete, regardless of success)
    BulkFinished(String), // Status Message
    
    // Generic Image Search
    ImagesSearchFinished(String), // JSON results

    // Cloud Saves
    CloudSaveSyncFinished(String, bool, String), // rom_id, success, message

    // Process Tracking
    GameStopped(String, i64), // rom_id, duration

    // EOS Overlay
    EosOverlayEnabled(String, bool),
}

#[derive(QObject, Default)]
pub struct GameListModel {
    // Parent class: QAbstractListModel
    base: qt_base_class!(trait QAbstractListModel),

    // Internal data storage
    roms: RefCell<Vec<Rom>>,
    total_library_count: RefCell<i32>,
    current_platform_filter: RefCell<Option<String>>,
    current_playlist_filter: RefCell<Option<String>>,
    current_genre_filter: RefCell<Option<String>>,
    current_region_filter: RefCell<Option<String>>,
    current_developer_filter: RefCell<Option<String>>,
    current_publisher_filter: RefCell<Option<String>>,
    current_year_filter: RefCell<Option<String>>,
    current_rating_filter: RefCell<i32>,
    current_favorites_only: RefCell<bool>,
    current_sort_method: RefCell<String>,
    current_search_text: RefCell<String>,
    current_platform_type_filter: RefCell<Option<String>>,
    current_recent_only: RefCell<bool>,
    current_installed_only: RefCell<bool>,
    current_tag_filters: RefCell<Vec<String>>,
    
    // Process Tracking
    running_games: RefCell<HashMap<String, i32>>, // ROM ID -> PGID
    
    pub sortMethod: qt_property!(QString; NOTIFY sortMethodChanged),
    pub sortMethodChanged: qt_signal!(),

    ignore_the_in_sort: RefCell<bool>,
    last_refresh_id: RefCell<u64>,
    is_loading: RefCell<bool>,
    
    // Bulk Scraper State
    bulk_is_scraping: RefCell<bool>,
    bulk_is_paused: RefCell<bool>,
    bulk_progress_val: RefCell<f32>,
    bulk_status_msg: RefCell<String>,
    
    // Bulk Thread Control (Shared with thread)
    bulk_cancel_flag: Arc<AtomicBool>,
    bulk_pause_flag: Arc<AtomicBool>,
    bulk_pause_notify: Arc<Notify>,
    
    pub bulkScraping: qt_property!(bool; NOTIFY bulkScrapingChanged),
    pub bulkScrapingChanged: qt_signal!(),
    
    pub bulkPaused: qt_property!(bool; NOTIFY bulkPausedChanged),
    pub bulkPausedChanged: qt_signal!(),
    
    pub bulkProgress: qt_property!(f32; NOTIFY bulkProgressChanged),
    pub bulkProgressChanged: qt_signal!(),
    
    pub bulkStatus: qt_property!(QString; NOTIFY bulkStatusChanged),
    pub bulkStatusChanged: qt_signal!(),
    
    pub bulkItemFinished: qt_signal!(rom_id: QString),
    
    // Scraper Client
    scraper_client: RefCell<Option<Arc<ScraperClient>>>,
    
    // Async Response Channel
    tx: RefCell<Option<mpsc::Sender<AsyncResponse>>>,
    rx: RefCell<Option<mpsc::Receiver<AsyncResponse>>>,

    // DB Access (initialized later or lazily)
    db_path: RefCell<String>,

    // Methods exposed to QML
    init: qt_method!(fn(&mut self, db_path: String)),
    refresh: qt_method!(fn(&mut self)),
    setIgnoreTheInSort: qt_method!(fn(&mut self, ignore: bool)),
    addSystem: qt_method!(fn(&mut self, name: String, extensions: String, rom_path: String, command: String, emulator_id: String, platform_type: String, icon: String)),
    getSystemStats: qt_method!(fn(&mut self)), // Helper to trigger stats update manually if needed (mostly auto)
    setFilter: qt_method!(fn(&mut self, platform_id: String)),
    setPlaylistFilter: qt_method!(fn(&mut self, playlist_id: String)),
    addToPlaylist: qt_method!(fn(&mut self, playlist_id: String, rom_id: String)),
    setGenreFilter: qt_method!(fn(&mut self, genre: String)),
    setRegionFilter: qt_method!(fn(&mut self, region: String)),
    setDeveloperFilter: qt_method!(fn(&mut self, developer: String)),
    setPublisherFilter: qt_method!(fn(&mut self, publisher: String)),
    setYearFilter: qt_method!(fn(&mut self, year: String)),
    setRatingFilter: qt_method!(fn(&mut self, rating: i32)),
    setTagFilter: qt_method!(fn(&mut self, tag: String, active: bool)),
    clearTagFilters: qt_method!(fn(&mut self)),
    getTags: qt_method!(fn(&mut self) -> QVariantList),
    setFavoritesOnly: qt_method!(fn(&mut self, favorites_only: bool)),
    setSortMethod: qt_method!(fn(&mut self, method: String)),
    setRecentOnly: qt_method!(fn(&mut self, recent_only: bool)),
    setSearchFilter: qt_method!(fn(&mut self, text: String)),
    setInstalledOnly: qt_method!(fn(&mut self, installed_only: bool)),
    setPlatformTypeFilter: qt_method!(fn(&mut self, platform_type: String)),
    toggleFavorite: qt_method!(fn(&mut self, rom_id: String)),
    startBulkScrape: qt_method!(fn(&mut self, json_ids: String, json_categories: String, json_fields: String, min_delay_ms: i32, max_delay_ms: i32, ra_user: String, ra_key: String, metadata_provider: String, prefer_ra: bool, ollama_url: String, ollama_model: String, gemini_key: String, openai_key: String, llm_provider: String)),
    stopBulkScrape: qt_method!(fn(&mut self)),
    pauseBulkScrape: qt_method!(fn(&mut self)),
    resumeBulkScrape: qt_method!(fn(&mut self)),
    getAvailableScrapers: qt_method!(fn(&mut self) -> QVariantList),
    getGenres: qt_method!(fn(&mut self) -> QVariantList),
    getAllGenres: qt_method!(fn(&mut self) -> QVariantList),
    getRegions: qt_method!(fn(&mut self) -> QVariantList),
    getAllRegions: qt_method!(fn(&mut self) -> QVariantList),
    getDevelopers: qt_method!(fn(&mut self) -> QVariantList),
    getAllDevelopers: qt_method!(fn(&mut self) -> QVariantList),
    getPublishers: qt_method!(fn(&mut self) -> QVariantList),
    getAllPublishers: qt_method!(fn(&mut self) -> QVariantList),
    getYears: qt_method!(fn(&mut self) -> QVariantList),
    getAllYears: qt_method!(fn(&mut self) -> QVariantList),
    getAllTags: qt_method!(fn(&mut self) -> QVariantList),
    getGameMetadata: qt_method!(fn(&mut self, rom_id: String) -> QString),
    updateGameMetadata: qt_method!(fn(&mut self, rom_id: String, json_data: String)),
    updateGameAchievements: qt_method!(fn(&mut self, rom_id: String, count: i32, unlocked: i32, badges: String)), // New method
    getUpNextSuggestion: qt_method!(fn(&mut self, last_played_id: String) -> QString),
    updateGameAsset: qt_method!(fn(&mut self, rom_id: String, asset_type: String, file_path: String)),
    refreshGameAssets: qt_method!(fn(&mut self, rom_id: String)),
    deleteGameAsset: qt_method!(fn(&mut self, rom_id: String, asset_type: String, file_path: String)),
    getGameId: qt_method!(fn(&mut self, row: i32) -> QString),
    getRowById: qt_method!(fn(&mut self, rom_id: String) -> i32),
    launchGame: qt_method!(fn(&mut self, rom_id: String)),
    uninstallSteamGame: qt_method!(fn(&mut self, rom_id: String)),
    getEmulatorProfiles: qt_method!(fn(&mut self, platform_id: String) -> QString),
    launchWithProfile: qt_method!(fn(&mut self, rom_id: String, profile_id: String)),
    rescanSystem: qt_method!(fn(&mut self, platform_id: String)),
    deleteGame: qt_method!(fn(&mut self, rom_id: String, ignore: bool, uninstall_flatpak: bool, delete_data: bool, delete_assets: bool)),
    getIgnoreList: qt_method!(fn(&mut self) -> String),
    removeFromIgnoreList: qt_method!(fn(&mut self, platform_id: String, path: String)),
    bulkUpdateMetadata: qt_method!(fn(&mut self, rom_ids_json: String, json_data: String)),
    deleteGamesBulk: qt_method!(fn(&mut self, rom_ids_json: String, ignore: bool, delete_assets: bool)),
    enableEosOverlay: qt_method!(fn(&mut self, rom_id: String) -> bool),
    disableEosOverlay: qt_method!(fn(&mut self, rom_id: String) -> bool),
    isEosOverlayEnabled: qt_method!(fn(&mut self, rom_id: String) -> bool),
    checkEosOverlayEnabled: qt_method!(fn(&mut self, rom_id: String)),
    eosOverlayEnabledResult: qt_signal!(rom_id: String, enabled: bool),

    // Process Tracking
    isGameRunning: qt_method!(fn(&self, rom_id: String) -> bool),
    stopGame: qt_method!(fn(&mut self, rom_id: String)),
    runningGamesChanged: qt_signal!(),

    // Scraping
    searchGameImages: qt_method!(fn(&mut self, query: String)),
    searchOnline: qt_method!(fn(&mut self, query: String, platform: String, provider: String, ollama_url: String, ollama_model: String, gemini_key: String, openai_key: String, llm_provider: String)),
    fetchOnlineMetadata: qt_method!(fn(&mut self, source_id: String, provider: String, ollama_url: String, ollama_model: String, gemini_key: String, openai_key: String, llm_provider: String)),
    globalSearch: qt_method!(fn(&mut self, query: String) -> String),
    downloadAsset: qt_method!(fn(&mut self, rom_id: String, asset_type: String, url: String)),
    
    // Resources
    addGameResource: qt_method!(fn(&mut self, rom_id: String, type_: String, url: String, label: String)),
    removeGameResource: qt_method!(fn(&mut self, resource_id: String)),
    updateGameResource: qt_method!(fn(&mut self, resource_id: String, type_: String, url: String, label: String)),
    launchResource: qt_method!(fn(&mut self, rom_id: String, url: String)),

    getPlatformTypes: qt_method!(fn(&mut self) -> QVariantList),

    batchSetFilters: qt_method!(fn(&mut self, platform_id: String, favorites: bool, sort: String, recent_only: bool, installed_only: bool)),
    checkAsyncResponses: qt_method!(fn(&mut self)),
    
    // System Import (New Flow)
    previewSystemImport: qt_method!(fn(&mut self, name: String, extensions: String, rom_path: String, emulator_id: String, platform_type: String, recursive: bool) -> String),
    commitSystemImport: qt_method!(fn(&mut self, name: String, extensions: String, rom_path: String, command: String, emulator_id: String, platform_type: String, icon: String, pc_config: String, selected_roms_json: String)),
    commitContentImport: qt_method!(fn(&mut self, platform_id: String, name: String, extensions: String, rom_path: String, command: String, emulator_id: String, platform_type: String, icon: String, pc_config: String, selected_roms_json: String)),
    isDirectory: qt_method!(fn(&self, path: QString) -> bool),



    // Auto Scrape
    autoScrape: qt_method!(fn(&mut self, rom_id: String)),
    refreshExoDosResources: qt_method!(fn(&mut self, rom_id: String)),

    // Navigation
    findNextLetter: qt_method!(fn(&mut self, current_index: i32) -> i32),
    findPrevLetter: qt_method!(fn(&mut self, current_index: i32) -> i32),
    getLetterAt: qt_method!(fn(&mut self, index: i32) -> QString),
    getRecentGamesJSON: qt_method!(fn(&mut self, limit: i32) -> QString),
    refreshHeroicPlaytime: qt_method!(fn(&mut self)),

    // PC Config
    getPcConfig: qt_method!(fn(&mut self, rom_id: String) -> QString),
    getPlatformPcDefaults: qt_method!(fn(&mut self, rom_id: String) -> QString),
    savePcConfig: qt_method!(fn(&mut self, json: String)),
    getRomPath: qt_method!(fn(&mut self, rom_id: String) -> QString),
    updateRomPath: qt_method!(fn(&mut self, rom_id: String, new_path: String)),

    // Cloud Saves
    resolveCloudSavePath: qt_method!(fn(&mut self, rom_id: String, wine_prefix: String) -> QString),
    syncCloudSaves: qt_method!(fn(&mut self, rom_id: String, direction: String, force: bool)),

    // Signals
    loading: qt_property!(bool; READ is_loading NOTIFY loadingChanged),
    loadingChanged: qt_signal!(),
    loadingStartedSignal: qt_signal!(),
    loadingFinishedSignal: qt_signal!(),
    searchFinished: qt_signal!(json_results: String),
    fetchFinished: qt_signal!(json_metadata: String),
    fetchFailed: qt_signal!(message: String),
    assetDownloadFinished: qt_signal!(category: String, local_path: String),
    assetDownloadFailed: qt_signal!(category: String, message: String),
    playtimeUpdated: qt_signal!(rom_id: String),
    statsUpdated: qt_signal!(total_games: i32, total_time: String, last_played: String, last_played_id: String, library_count: i32),
    importProgress: qt_signal!(p: f32, status: String),
    assetDownloadProgress: qt_signal!(message: String), // New signal

    importFinished: qt_signal!(platform_id: String, json_ids: String),
    autoScrapeFinished: qt_signal!(rom_id: String, json_metadata: String),
    autoScrapeFailed: qt_signal!(rom_id: String, message: String),
    imagesSearchFinished: qt_signal!(json: String),
    gameDataChanged: qt_signal!(rom_id: String),
    platformTypesChanged: qt_signal!(),
    cloudSaveSyncFinished: qt_signal!(rom_id: String, success: bool, message: String),
    filterOptionsChanged: qt_signal!(),
}

impl QAbstractListModel for GameListModel {
    fn row_count(&self) -> i32 {
        self.roms.borrow().len() as i32
    }

    fn data(&self, index: QModelIndex, role: i32) -> QVariant {
        let roms = self.roms.borrow();
        let idx = index.row() as usize;

        if idx >= roms.len() {
            return QVariant::default();
        }

        let rom = &roms[idx];

        match role {
            // Qt::DisplayRole = 0
            0 => QVariant::from(QString::from(rom.title.as_deref().unwrap_or(rom.filename.as_str()))), 
            
            // Custom Roles
            256 => QVariant::from(QString::from(rom.id.as_str())),       // idRole
            257 => QVariant::from(QString::from(rom.title.as_deref().unwrap_or(rom.filename.as_str()))), // titleRole
            258 => QVariant::from(QString::from(rom.path.as_str())),     // pathRole
            259 => QVariant::from(QString::from(rom.region.as_deref().unwrap_or(""))), // regionRole
            260 => QVariant::from(QString::from(rom.platform_name.as_deref().unwrap_or(""))), // platformNameRole
            261 => QVariant::from(QString::from(rom.platform_type.as_deref().unwrap_or(""))), // platformTypeRole
            262 => QVariant::from(QString::from(rom.boxart_path.as_deref().map(resolve_asset_path).unwrap_or_default())), // gameBoxArt role
            263 => QVariant::from(QString::from(rom.filename.as_str())),                 // gameRomFileName role
            264 => QVariant::from(QString::from(rom.platform_id.as_str())),             // gamePlatformId role
            265 => QVariant::from(QString::from(rom.platform_type.as_deref().or(rom.platform_name.as_deref()).unwrap_or("Unknown"))), // gamePlatformFolder role
            266 => QVariant::from(QString::from(rom.platform_icon.as_deref().map(resolve_asset_path).unwrap_or_default())), // gamePlatformIcon role
            267 => QVariant::from(rom.is_favorite.unwrap_or(false)), // gameIsFavorite role

            // New Roles
            268 => QVariant::from(QString::from(rom.genre.as_deref().unwrap_or(""))),
            269 => QVariant::from(QString::from(rom.developer.as_deref().unwrap_or(""))),
            270 => QVariant::from(QString::from(rom.publisher.as_deref().unwrap_or(""))),
            271 => QVariant::from(rom.rating.unwrap_or(0.0)),
            272 => QVariant::from(QString::from(rom.tags.as_deref().unwrap_or(""))),
            273 => {
                if let Some(date_str) = &rom.release_date {
                     if date_str == "0" || date_str.is_empty() {
                         QVariant::from(QString::from(""))
                     } else if date_str.len() >= 4 {
                         QVariant::from(QString::from(date_str[0..4].to_string()))
                     } else {
                         QVariant::from(QString::from(date_str.clone()))
                     }
                } else {
                    QVariant::from(QString::from(""))
                }
            },
            274 => QVariant::from(QString::from(rom.icon_path.as_deref().map(resolve_asset_path).unwrap_or_default())), // gameIcon
            275 => QVariant::from(QString::from(rom.background_path.as_deref().map(resolve_asset_path).unwrap_or_default())), // gameBackground
            276 => QVariant::from(rom.is_installed.unwrap_or_else(|| {
                if rom.id.starts_with("steam-") || rom.id.starts_with("legendary-") {
                    false
                } else {
                    true
                }
            })), // gameIsInstalled role
            277 => QVariant::from(rom.cloud_saves_supported.unwrap_or(false)), // gameCloudSavesSupported role
            278 => QVariant::from(self.running_games.borrow().contains_key(&rom.id)), // gameIsRunning role
            _ => QVariant::default(),
        }
    }

    fn role_names(&self) -> std::collections::HashMap<i32, QByteArray> {
        let mut roles = std::collections::HashMap::new();
        roles.insert(256, QByteArray::from("gameId"));
        roles.insert(257, QByteArray::from("gameTitle"));
        roles.insert(258, QByteArray::from("gamePath"));
        roles.insert(259, QByteArray::from("gameRegion"));
        roles.insert(260, QByteArray::from("gamePlatformName"));
        roles.insert(261, QByteArray::from("gamePlatformType"));
        roles.insert(262, QByteArray::from("gameBoxArt"));
        roles.insert(263, QByteArray::from("gameRomFileName"));
        roles.insert(264, QByteArray::from("gamePlatformId"));
        roles.insert(265, QByteArray::from("gamePlatformFolder"));
        roles.insert(266, QByteArray::from("gamePlatformIcon"));
        roles.insert(267, QByteArray::from("gameIsFavorite"));
        roles.insert(268, QByteArray::from("gameGenre"));
        roles.insert(269, QByteArray::from("gameDeveloper"));
        roles.insert(270, QByteArray::from("gamePublisher"));
        roles.insert(271, QByteArray::from("gameRating"));
        roles.insert(272, QByteArray::from("gameTags"));
        roles.insert(273, QByteArray::from("gameReleaseYear"));
        roles.insert(274, QByteArray::from("gameIcon"));
        roles.insert(275, QByteArray::from("gameBackground"));
        roles.insert(276, QByteArray::from("gameIsInstalled"));
        roles.insert(277, QByteArray::from("gameCloudSavesSupported"));
        roles.insert(278, QByteArray::from("gameIsRunning"));
        roles
    }
}

impl GameListModel {
    fn init(&mut self, db_path: String) {
        log::debug!("[GameListModel] Initializing with DB path: {}", db_path);
        *self.db_path.borrow_mut() = db_path.clone();
        *self.current_sort_method.borrow_mut() = "TitleAZ".to_string();
        self.sortMethod = "TitleAZ".into();
        *self.current_playlist_filter.borrow_mut() = None;
        
        // Initialize Bulk Control
        // Initialize Bulk Control
        self.bulk_cancel_flag = Arc::new(AtomicBool::new(false));
        self.bulk_pause_flag = Arc::new(AtomicBool::new(false));
        self.bulk_pause_notify = Arc::new(Notify::new());
        
        // Ensure database schema is initialized/migrated (Heavier op)
        if !db_path.is_empty() {
            match DbManager::new(&db_path) {
                Ok(_) => {},
                Err(e) => log::error!("[GameListModel] Database initialization FAILED: {}", e),
            }
        }

        // Initialize Channels
        let (tx, rx) = mpsc::channel();
        *self.tx.borrow_mut() = Some(tx);
        *self.rx.borrow_mut() = Some(rx);

        self.refresh();
    }

    fn is_loading(&self) -> bool {
        *self.is_loading.borrow()
    }

    fn loadingStarted(&mut self) {
        *self.is_loading.borrow_mut() = true;
        self.loadingChanged();
        self.loadingStartedSignal();
    }

    fn loadingFinished(&mut self) {
        *self.is_loading.borrow_mut() = false;
        self.loadingChanged();
        self.loadingFinishedSignal();
    }

    // Initial Load - We need to modify this to include metadata columns
    fn refresh(&mut self) {
        self.loadingStarted();
        
        let db_path = self.db_path.borrow().clone();
        if db_path.is_empty() { 
            self.loadingFinished();
            return; 
        }

        let platform_id_filter = self.current_platform_filter.borrow().clone();
        let playlist_filter = self.current_playlist_filter.borrow().clone();
        let genre_filter = self.current_genre_filter.borrow().clone();
        let region_filter = self.current_region_filter.borrow().clone();
        let developer_filter = self.current_developer_filter.borrow().clone();
        let publisher_filter = self.current_publisher_filter.borrow().clone();
        let year_filter = self.current_year_filter.borrow().clone();
        let rating_filter = *self.current_rating_filter.borrow();
        let favorites_only = *self.current_favorites_only.borrow();
        let sort_method = self.current_sort_method.borrow().clone();
        let search_text = self.current_search_text.borrow().clone();
        let platform_type_filter = self.current_platform_type_filter.borrow().clone();
        let recent_only = *self.current_recent_only.borrow();
        let ignore_the = *self.ignore_the_in_sort.borrow();
        let installed_only = *self.current_installed_only.borrow();
        let tag_filters = self.current_tag_filters.borrow().clone();

        // Unique ID for this request to avoid race conditions
        let my_id = {
            let mut id_ref = self.last_refresh_id.borrow_mut();
            *id_ref += 1;
            *id_ref
        };

        let tx = match self.tx.borrow().as_ref() {
            Some(t) => t.clone(),
            None => return,
        };

        get_runtime().spawn(async move {
            let mut new_roms = Vec::new();
            let mut total_library_rec = 0;

            if let Ok(db) = DbManager::open(&db_path) {
                // Background Sync for Heroic Playtime if needed
                if let Some(pid) = &platform_id_filter {
                    if let Ok(Some(platform)) = db.get_platform(pid) {
                        if platform.platform_type.as_deref().unwrap_or("").to_lowercase() == "heroic" {
                            log::debug!("[GameListModel] Background Heroic sync for platform: {}", pid);
                            let _ = StoreManager::sync_heroic_playtime_bulk(&db);
                        }
                    }
                }
                
                let conn = db.get_connection();
                let mut query = String::from("SELECT r.id, r.platform_id, r.path, r.filename, m.title, m.region, p.name, p.platform_type, 
                                              COALESCE(r.boxart_path, (SELECT local_path FROM assets WHERE rom_id = r.id AND type = 'Box - Front' LIMIT 1)), 
                                              r.date_added, m.play_count, m.total_play_time, m.last_played, p.icon, m.is_favorite, m.genre, m.developer, m.publisher, m.rating, m.tags, m.release_date, 
                                              COALESCE(r.icon_path, (SELECT local_path FROM assets WHERE rom_id = r.id AND type = 'Icon' LIMIT 1)), 
                                              COALESCE(r.background_path, (SELECT local_path FROM assets WHERE rom_id = r.id AND type = 'Background' LIMIT 1), (SELECT local_path FROM assets WHERE rom_id = r.id AND type = 'Screenshot' LIMIT 1)), 
                                              m.is_installed
                                              FROM roms r 
                                              LEFT JOIN metadata m ON r.id = m.rom_id 
                                              JOIN platforms p ON r.platform_id = p.id");

                if let Some(pid) = &playlist_filter {
                    if !pid.is_empty() {
                        query.push_str(" JOIN playlist_entries pe ON r.id = pe.rom_id");
                    }
                }

                query.push_str(" WHERE 1=1");

                if installed_only {
                    query.push_str(" AND m.is_installed = 1");
                }
                
                let mut params: Vec<Box<dyn ToSql>> = Vec::new();
                
                if let Some(pid) = platform_id_filter {
                    if !pid.is_empty() {
                        query.push_str(" AND r.platform_id = ?");
                        params.push(Box::new(pid));
                    }
                }

                if let Some(pt) = platform_type_filter {
                    if !pt.is_empty() {
                        query.push_str(" AND p.platform_type = ?");
                        params.push(Box::new(pt));
                    }
                }

                if let Some(pid) = playlist_filter {
                    if !pid.is_empty() {
                        query.push_str(" AND pe.playlist_id = ?");
                        params.push(Box::new(pid));
                    }
                }

                if let Some(g) = genre_filter {
                    if !g.is_empty() && g != "All Genres" {
                        query.push_str(" AND instr(', ' || m.genre || ', ', ', ' || ? || ', ') > 0");
                        params.push(Box::new(g));
                    }
                }

                if let Some(r) = region_filter {
                    if !r.is_empty() && r != "All Regions" {
                        query.push_str(" AND instr(', ' || m.region || ', ', ', ' || ? || ', ') > 0");
                        params.push(Box::new(r));
                    }
                }

                if let Some(d) = developer_filter {
                    if !d.is_empty() && d != "All Developers" {
                        query.push_str(" AND instr(', ' || m.developer || ', ', ', ' || ? || ', ') > 0");
                        params.push(Box::new(d));
                    }
                }

                if let Some(p) = publisher_filter {
                    if !p.is_empty() && p != "All Publishers" {
                        query.push_str(" AND instr(', ' || m.publisher || ', ', ', ' || ? || ', ') > 0");
                        params.push(Box::new(p));
                    }
                }

                if let Some(y) = year_filter {
                    if !y.is_empty() && y != "All Years" {
                        query.push_str(" AND m.release_date LIKE ?");
                        params.push(Box::new(format!("{}%", y)));
                    }
                }

                if rating_filter > 0 {
                    query.push_str(" AND m.rating >= ?");
                    params.push(Box::new(rating_filter as f32 / 10.0));
                }

                if favorites_only {
                    query.push_str(" AND m.is_favorite = 1");
                }

                if !search_text.is_empty() {
                    query.push_str(" AND (m.title LIKE ? OR r.filename LIKE ?)");
                    let pattern = format!("%{}%", search_text);
                    params.push(Box::new(pattern.clone()));
                    params.push(Box::new(pattern));
                }

                if recent_only {
                    query.push_str(" AND m.last_played > 0");
                }

                // Tag Filter (Multi-select AND logic)
                if !tag_filters.is_empty() {
                    for tag in tag_filters.iter() {
                        query.push_str(" AND instr(', ' || m.tags || ', ', ', ' || ? || ', ') > 0");
                        params.push(Box::new(tag.clone()));
                    }
                }

                query.push_str(" GROUP BY r.id");

                match sort_method.as_str() {
                    "Recent" => {
                        query.push_str(" ORDER BY r.date_added DESC");
                    },
                    "LastPlayed" => {
                        query.push_str(" ORDER BY m.last_played DESC");
                    },
                    "TitleZA" | "TitleDESC" => {
                        if ignore_the {
                            query.push_str(" ORDER BY 
                                CASE 
                                    WHEN UPPER(COALESCE(m.title, r.filename)) LIKE 'THE %' 
                                    THEN SUBSTR(COALESCE(m.title, r.filename), 5) 
                                    ELSE COALESCE(m.title, r.filename) 
                                END COLLATE NOCASE DESC");
                        } else {
                            query.push_str(" ORDER BY COALESCE(m.title, r.filename) COLLATE NOCASE DESC");
                        }
                    },
                    "Platform" => query.push_str(" ORDER BY p.name COLLATE NOCASE ASC"),
                    "PlatformDESC" => query.push_str(" ORDER BY p.name COLLATE NOCASE DESC"),
                    "Region" => query.push_str(" ORDER BY m.region COLLATE NOCASE ASC"),
                    "RegionDESC" => query.push_str(" ORDER BY m.region COLLATE NOCASE DESC"),
                    "Genre" => query.push_str(" ORDER BY m.genre COLLATE NOCASE ASC"),
                    "GenreDESC" => query.push_str(" ORDER BY m.genre COLLATE NOCASE DESC"),
                    "Developer" => query.push_str(" ORDER BY m.developer COLLATE NOCASE ASC"),
                    "DeveloperDESC" => query.push_str(" ORDER BY m.developer COLLATE NOCASE DESC"),
                    "Publisher" => query.push_str(" ORDER BY m.publisher COLLATE NOCASE ASC"),
                    "PublisherDESC" => query.push_str(" ORDER BY m.publisher COLLATE NOCASE DESC"),
                    "Year" => query.push_str(" ORDER BY m.release_date ASC"),
                    "YearDESC" => query.push_str(" ORDER BY m.release_date DESC"),
                    "Rating" => query.push_str(" ORDER BY m.rating ASC"),
                    "RatingDESC" => query.push_str(" ORDER BY m.rating DESC"),
                    "Tags" => query.push_str(" ORDER BY m.tags COLLATE NOCASE ASC"),
                    "TagsDESC" => query.push_str(" ORDER BY m.tags COLLATE NOCASE DESC"),
                    _ => {
                        if ignore_the {
                            query.push_str(" ORDER BY 
                                CASE 
                                    WHEN UPPER(COALESCE(m.title, r.filename)) LIKE 'THE %' 
                                    THEN SUBSTR(COALESCE(m.title, r.filename), 5) 
                                    ELSE COALESCE(m.title, r.filename) 
                                END COLLATE NOCASE ASC");
                        } else {
                            query.push_str(" ORDER BY COALESCE(m.title, r.filename) COLLATE NOCASE ASC");
                        }
                    },
                }

                if let Ok(mut stmt) = conn.prepare(&query) {
                    let param_refs: Vec<&dyn ToSql> = params.iter().map(|p| p.as_ref()).collect();
                    if let Ok(stmt_iter) = stmt.query_map(rusqlite::params_from_iter(param_refs), |row| {
                        Ok(Rom {
                            id: row.get(0)?,
                            platform_id: row.get(1)?,
                            path: row.get(2)?,
                            filename: row.get(3)?,
                            file_size: 0,
                            hash_sha1: None,
                            title: row.get(4)?,
                            region: row.get(5)?,
                            platform_name: Some(row.get(6)?),
                            platform_type: row.get(7)?,
                            date_added: row.get(9)?,
                            play_count: row.get(10)?,
                            total_play_time: row.get(11)?,
                            last_played: row.get(12)?,
                            platform_icon: row.get(13)?,
                            is_favorite: Some(row.get::<_, i32>(14).unwrap_or(0) != 0),
                            boxart_path: row.get(8).ok(),
                            genre: row.get(15).ok(),
                            developer: row.get(16).ok(),
                            publisher: row.get(17).ok(),
                            rating: row.get::<_, f32>(18).ok(),
                            tags: row.get(19).ok(),
                            release_date: {
                                let val: Option<rusqlite::types::Value> = row.get(20)?;
                                match val {
                                    Some(rusqlite::types::Value::Text(s)) => Some(s),
                                    Some(rusqlite::types::Value::Integer(i)) => Some(i.to_string()),
                                    Some(rusqlite::types::Value::Real(f)) => Some(f.to_string()),
                                    _ => None,
                                }
                            },
                            icon_path: row.get(21)?,
                            background_path: row.get(22)?,
                            is_installed: Some(row.get::<_, Option<i32>>(23).ok().flatten().unwrap_or(1) != 0),
                            cloud_saves_supported: None,
                            description: None,
                            resources: None,
                        })
                    }) {
                        for rom in stmt_iter {
                            if let Ok(r) = rom {
                                new_roms.push(r);
                            }
                        }
                    }
                } // End of complex query block
                
                // Calculate Total Library Count (Common)
                if let Ok(count) = db.get_connection().query_row("SELECT COUNT(*) FROM roms", [], |row| row.get(0)) {
                    total_library_rec = count;
                }

                // Calculate Stats in background thread
                let total_games = new_roms.len() as i32;
                let mut total_time_seconds: i64 = 0;
                let mut last_played_game = String::from("None");
                let mut last_played_id = String::from("");
                let mut last_played_time: i64 = 0;
                
                for rom in new_roms.iter() {
                    if let Some(time) = rom.total_play_time {
                        total_time_seconds += time;
                    }
                    if let Some(lp) = rom.last_played {
                        if lp > last_played_time {
                            last_played_time = lp;
                            last_played_game = rom.title.as_ref().unwrap_or(&rom.filename).clone();
                            last_played_id = rom.id.clone();
                        }
                    }
                }
                
                let hours = total_time_seconds / 3600;
                let minutes = (total_time_seconds % 3600) / 60;
                let time_str = if hours > 0 {
                    format!("{}h {}m", hours, minutes)
                } else {
                    format!("{}m", minutes)
                };

                let _ = tx.send(AsyncResponse::RefreshFinished(
                    new_roms, 
                    my_id, 
                    total_library_rec,
                    total_games,
                    time_str,
                    last_played_game,
                    last_played_id
                ));
            }
        });
    }

    
    fn calculateStats(&mut self) {
        let roms = self.roms.borrow();
        let total_games = roms.len() as i32;
        
        let mut total_time_seconds: i64 = 0;
        let mut last_played_game = String::from("None");
        let mut last_played_id = String::from("");
        let mut last_played_time: i64 = 0;
        
        for rom in roms.iter() {
            if let Some(time) = rom.total_play_time {
                total_time_seconds += time;
            }
            
            if let Some(lp) = rom.last_played {
                if lp > last_played_time {
                    last_played_time = lp;
                    last_played_game = rom.title.as_ref().unwrap_or(&rom.filename).clone();
                    last_played_id = rom.id.clone();
                }
            }
        }
        
        // Format time
        let hours = total_time_seconds / 3600;
        let minutes = (total_time_seconds % 3600) / 60;
        let time_str = if hours > 0 {
            format!("{}h {}m", hours, minutes)
        } else {
            format!("{}m", minutes)
        };
        
        // Emit signal
        let lib_count = *self.total_library_count.borrow();
        self.statsUpdated(total_games, time_str, last_played_game, last_played_id, lib_count);
    }

    #[allow(non_snake_case)]
    fn setFilter(&mut self, platform_id: String) {
        let normalized_filter = if platform_id.is_empty() { None } else { Some(platform_id) };
        let current_filter = self.current_platform_filter.borrow().clone();
        
        if current_filter != normalized_filter {
            *self.current_platform_filter.borrow_mut() = normalized_filter.clone();
            *self.current_platform_type_filter.borrow_mut() = None; // Clear platform type filter
            *self.current_playlist_filter.borrow_mut() = None; // Clear playlist filter
            
            if let Some(id) = normalized_filter {
                log::debug!("[GameListModel] Filter changed to platform ID: {}", id);
                let db_path = self.db_path.borrow().clone();
                if !db_path.is_empty() {
                    if let Ok(db) = DbManager::open(&db_path) {
                        if let Ok(Some(platform)) = db.get_platform(&id) {
                            let p_type = platform.platform_type.as_deref().unwrap_or("unknown");
                            log::debug!("[GameListModel] Platform type for {} is: {}", id, p_type);
                            if p_type.to_lowercase() == "heroic" {
                                self.refreshHeroicPlaytime();
                            }
                        } else {
                            log::warn!("[GameListModel] Could not find platform details for ID: {}", id);
                        }
                    }
                }
            }
            
            self.refresh();
        }
    }

    #[allow(non_snake_case)]
    fn refreshHeroicPlaytime(&mut self) {
        log::debug!("[GameListModel] Refreshing all Heroic playtime data...");
        let db_path = self.db_path.borrow().clone();
        if db_path.is_empty() { return; }

        if let Ok(db) = DbManager::open(&db_path) {
            match StoreManager::sync_heroic_playtime_bulk(&db) {
                Ok(count) => {
                    if count > 0 {
                        log::debug!("[GameListModel] Updated playtime for {} Heroic games", count);
                    }
                },
                Err(e) => log::error!("[GameListModel] Failed to sync Heroic playtime: {}", e),
            }
        }
    }

    #[allow(non_snake_case)]
    fn setPlatformTypeFilter(&mut self, platform_type: String) {
        let normalized_filter = if platform_type.is_empty() { None } else { Some(platform_type) };
        let current_filter = self.current_platform_type_filter.borrow().clone();
        
        if current_filter != normalized_filter {
            *self.current_platform_type_filter.borrow_mut() = normalized_filter;
            *self.current_platform_filter.borrow_mut() = None; // Clear platform id filter
            *self.current_playlist_filter.borrow_mut() = None; // Clear playlist filter
            self.refresh();
        }
    }

    #[allow(non_snake_case)]
    fn setPlaylistFilter(&mut self, playlist_id: String) {
        *self.current_playlist_filter.borrow_mut() = if playlist_id.is_empty() { None } else { Some(playlist_id) };
        *self.current_platform_filter.borrow_mut() = None; // Clear platform filter
        *self.current_platform_type_filter.borrow_mut() = None; // Clear platform type filter
        self.refresh();
    }

    #[allow(non_snake_case)]
    fn addToPlaylist(&mut self, playlist_id: String, rom_id: String) {
        let db_path = self.db_path.borrow().clone();
        if let Ok(db) = DbManager::open(&db_path) {
            let _ = db.add_to_playlist(&playlist_id, &rom_id);
            // We do not refresh automatically here as the current view might not be the playlist
        }
    }

    fn setGenreFilter(&mut self, genre: String) {
        let normalized = if genre.is_empty() || genre == "All Genres" { None } else { Some(genre) };
        if *self.current_genre_filter.borrow() == normalized { return; }
        *self.current_genre_filter.borrow_mut() = normalized;
        self.refresh();
    }

    fn setInstalledOnly(&mut self, installed_only: bool) {
        if *self.current_installed_only.borrow() == installed_only { return; }
        log::debug!("[GameListModel] Setting installed only filter: {}", installed_only);
        *self.current_installed_only.borrow_mut() = installed_only;
        self.refresh();
    }

    fn setRegionFilter(&mut self, region: String) {
        let normalized_region = if region.is_empty() || region == "All Regions" { None } else { Some(region) };
        let current_filter = self.current_region_filter.borrow().clone();
        if current_filter != normalized_region {
            *self.current_region_filter.borrow_mut() = normalized_region;
            self.refresh();
        }
    }

    fn setDeveloperFilter(&mut self, developer: String) {
        *self.current_developer_filter.borrow_mut() = if developer.is_empty() || developer == "All Developers" { None } else { Some(developer) };
        self.refresh();
    }

    fn setPublisherFilter(&mut self, publisher: String) {
        *self.current_publisher_filter.borrow_mut() = if publisher.is_empty() || publisher == "All Publishers" { None } else { Some(publisher) };
        self.refresh();
    }

    fn setYearFilter(&mut self, year: String) {
        *self.current_year_filter.borrow_mut() = if year.is_empty() || year == "All Years" { None } else { Some(year) };
        self.refresh();
    }

    fn setRatingFilter(&mut self, rating: i32) {
        *self.current_rating_filter.borrow_mut() = rating;
        self.refresh();
    }

    fn setTagFilter(&mut self, tag: String, active: bool) {
        let mut filters = self.current_tag_filters.borrow_mut();
        if active {
            if !filters.contains(&tag) {
                filters.push(tag);
            }
        } else {
            filters.retain(|t| t != &tag);
        }
        drop(filters);
        self.refresh();
    }

    fn clearTagFilters(&mut self) {
        self.current_tag_filters.borrow_mut().clear();
        self.refresh();
    }

    fn getTags(&mut self) -> QVariantList {
        let db_path = self.db_path.borrow().clone();
        if let Ok(db) = DbManager::open(&db_path) {
            let platform_filter = self.current_platform_filter.borrow().clone();
            let platform_type_filter = self.current_platform_type_filter.borrow().clone();
            let playlist_filter = self.current_playlist_filter.borrow().clone();
            let installed_only = *self.current_installed_only.borrow();
            let favorites_only = *self.current_favorites_only.borrow();

            if let Ok(tags) = db.get_tags_filtered(
                platform_filter.as_deref(),
                platform_type_filter.as_deref(),
                playlist_filter.as_deref(),
                installed_only,
                favorites_only
            ) {
                return tags.into_iter().map(|s| QVariant::from(QString::from(s))).collect();
            }
        }
        QVariantList::default()
    }

    fn setFavoritesOnly(&mut self, favorites_only: bool) {
        *self.current_favorites_only.borrow_mut() = favorites_only;
        self.refresh();
    }

    fn setSortMethod(&mut self, method: String) {
        *self.current_sort_method.borrow_mut() = method.clone();
        self.sortMethod = method.into();
        self.sortMethodChanged();
        self.refresh();
    }

    fn setRecentOnly(&mut self, recent_only: bool) {
        *self.current_recent_only.borrow_mut() = recent_only;
        self.refresh();
    }

    fn setSearchFilter(&mut self, text: String) {
        *self.current_search_text.borrow_mut() = text;
        self.refresh();
    }

    #[allow(non_snake_case)]
    fn setIgnoreTheInSort(&mut self, ignore: bool) {
        let current_value = *self.ignore_the_in_sort.borrow();
        if current_value != ignore {
            *self.ignore_the_in_sort.borrow_mut() = ignore;
            self.refresh();
        }
    }

    fn toggleFavorite(&mut self, rom_id: String) {
        let db_path = self.db_path.borrow().clone();
        if let Ok(db) = DbManager::open(&db_path) {
            if let Ok(Some(mut meta)) = db.get_metadata(&rom_id) {
                meta.is_favorite = !meta.is_favorite;
                let _ = db.insert_metadata(&meta);
                
                // Save Sidecar
                if let Ok(Some((platform_folder, filename))) = db.get_rom_path_info(&rom_id) {
                    let rom_stem = Path::new(&filename).file_stem().and_then(|s| s.to_str()).unwrap_or(&filename);
                    let _ = MetadataManager::save_sidecar(&platform_folder, rom_stem, &meta);
                }
            } else {
                // Create basic metadata if it doesn't exist
                let meta = crate::core::models::GameMetadata {
                    rom_id: rom_id.clone(),
                    title: None,
                    description: None,
                    rating: None,
                    release_date: None,
                    developer: None,
                    publisher: None,
                    genre: None,
                    tags: None,
                    region: None,
                    is_favorite: true,
                    play_count: 0,
                    last_played: None,
                    total_play_time: 0,
                    achievement_count: None,
                    achievement_unlocked: None,
                    ra_game_id: None,
                    ra_recent_badges: None,
                    is_installed: if rom_id.starts_with("steam-") {
                        crate::core::store::StoreManager::get_local_steam_appids().contains(&rom_id.replace("steam-", ""))
                    } else if rom_id.starts_with("legendary-") {
                        false
                    } else {
                        true
                    },
                    cloud_saves_supported: false,
                    resources: None,
                };
                let _ = db.insert_metadata(&meta);
            }
        }
        self.refresh(); // Refresh to reflect favorite status change if filtered
    }

    #[allow(non_snake_case)]
    fn getAvailableScrapers(&mut self) -> QVariantList {
        ScraperManager::get_available_providers()
            .into_iter()
            .map(|s| QVariant::from(QString::from(s)))
            .collect()
    }

    #[allow(non_snake_case)]
    fn getPlatformTypes(&mut self) -> QVariantList {
        let db_path = self.db_path.borrow().clone();
        let mut result = QVariantList::default();
        
        // Get types from DB
        let mut db_types = Vec::new();
        if let Ok(db) = DbManager::open(&db_path) {
            if let Ok(types) = db.get_all_platform_types() {
                db_types = types;
            }
        }

        // Get static info for icons
        let static_platforms = crate::bridge::static_platforms::get_default_platforms();
        
        for p_type in db_types {
            let mut icon = "🏷️".to_string(); // Default icon
            
            // Try to find matching static platform
            if let Some(info) = static_platforms.iter().find(|p| p.name == p_type || p.slug == p_type) {
                icon = info.icon_url.clone();
            }
            
            let mut map = QVariantMap::default();
            map.insert("name".into(), QVariant::from(QString::from(p_type)));
            map.insert("icon".into(), QVariant::from(QString::from(icon)));
            result.push(QVariant::from(map));
        }
        
        result
    }

    #[allow(non_snake_case)]
    fn batchSetFilters(&mut self, platform_id: String, favorites: bool, sort: String, recent_only: bool, installed_only: bool) {
        let p_filter = if platform_id.is_empty() { None } else { Some(platform_id) };
        *self.current_platform_filter.borrow_mut() = p_filter.clone();
        *self.current_favorites_only.borrow_mut() = favorites;
        *self.current_sort_method.borrow_mut() = sort;
        *self.current_recent_only.borrow_mut() = recent_only;
        *self.current_installed_only.borrow_mut() = installed_only;
        *self.current_platform_type_filter.borrow_mut() = None;
        *self.current_playlist_filter.borrow_mut() = None;

        self.refresh();
    }

    fn bulkUpdateMetadata(&mut self, rom_ids_json: String, json_data: String) {
        let rom_ids: Vec<String> = serde_json::from_str(&rom_ids_json).unwrap_or_default();
        if rom_ids.is_empty() { return; }

        let data: serde_json::Value = serde_json::from_str(&json_data).unwrap_or(serde_json::Value::Null);
        if !data.is_object() { return; }

        let db_path = self.db_path.borrow().clone();
        if let Ok(db) = DbManager::open(&db_path) {
            for rom_id in rom_ids {
                // Get existing or new metadata
                let mut meta = if let Ok(Some(m)) = db.get_metadata(&rom_id) {
                    m
                } else {
                    crate::core::models::GameMetadata {
                        rom_id: rom_id.clone(),
                        title: None, description: None, rating: None, release_date: None,
                        developer: None, publisher: None, genre: None, tags: None,
                        region: None, is_favorite: false, play_count: 0, last_played: None,
                        total_play_time: 0, achievement_count: None, achievement_unlocked: None, ra_game_id: None,
                        ra_recent_badges: None,
                        is_installed: if rom_id.starts_with("steam-") {
                            crate::core::store::StoreManager::get_local_steam_appids().contains(&rom_id.replace("steam-", ""))
                        } else if rom_id.starts_with("legendary-") {
                            false // Default to false for Legendary if unknown
                        } else {
                            true
                        },
                        cloud_saves_supported: false,
                        resources: None,
                    }
                };

                // Apply updates if fields are present in the JSON object (and not null)
                if let Some(v) = data.get("genre").and_then(|v| v.as_str()) { meta.genre = Some(v.to_string()); }
                if let Some(v) = data.get("developer").and_then(|v| v.as_str()) { meta.developer = Some(v.to_string()); }
                if let Some(v) = data.get("publisher").and_then(|v| v.as_str()) { meta.publisher = Some(v.to_string()); }
                if let Some(v) = data.get("tags").and_then(|v| v.as_str()) { 
                    // Optional: maybe append tags? For now, we overwrite as per "Bulk Edit" usually implying "Set to X"
                     meta.tags = Some(v.to_string()); 
                }
                if let Some(v) = data.get("region").and_then(|v| v.as_str()) { meta.region = Some(v.to_string()); }
                
                if let Some(v) = data.get("rating").and_then(|v| v.as_f64()) { meta.rating = Some(v as f32); }
                if let Some(v) = data.get("release_date").and_then(|v| v.as_str()) { meta.release_date = Some(v.to_string()); }
                
                if let Some(v) = data.get("is_favorite").and_then(|v| v.as_bool()) { meta.is_favorite = v; }
                
                // Allow clearing via empty string if explicitly sent? 
                // Currently UI usually sends the value. If we want to "Delete", we might need a separate flag or special value.
                // For now, standard behavior: if checked in UI, it sends the value to apply.

                let _ = db.insert_metadata(&meta);

                // Save Sidecar
                if let Ok(Some((platform_folder, filename))) = db.get_rom_path_info(&rom_id) {
                    let rom_stem = Path::new(&filename).file_stem().and_then(|s| s.to_str()).unwrap_or(&filename);
                    let _ = MetadataManager::save_sidecar(&platform_folder, rom_stem, &meta);
                }
            }
        }
        self.refresh();
    }

    fn getGenres(&mut self) -> QVariantList {
        let mut result = QVariantList::default();
        result.push(QString::from("All Genres").into());
        let all = self.getAllGenres();
        for i in 0..all.len() { result.push(all[i].clone()); }
        result
    }

    fn getAllGenres(&mut self) -> QVariantList {
        self.get_metadata_list(|db| db.get_all_genres())
    }

    fn getRegions(&mut self) -> QVariantList {
        let mut result = QVariantList::default();
        result.push(QString::from("All Regions").into());
        let all = self.getAllRegions();
        for i in 0..all.len() { result.push(all[i].clone()); }
        result
    }

    fn getAllRegions(&mut self) -> QVariantList {
        self.get_metadata_list(|db| db.get_all_regions())
    }

    fn getDevelopers(&mut self) -> QVariantList {
        let mut result = QVariantList::default();
        result.push(QString::from("All Developers").into());
        let all = self.getAllDevelopers();
        for i in 0..all.len() { result.push(all[i].clone()); }
        result
    }

    fn getAllDevelopers(&mut self) -> QVariantList {
        self.get_metadata_list(|db| db.get_all_developers())
    }

    fn getPublishers(&mut self) -> QVariantList {
        let mut result = QVariantList::default();
        result.push(QString::from("All Publishers").into());
        let all = self.getAllPublishers();
        for i in 0..all.len() { result.push(all[i].clone()); }
        result
    }

    fn getAllPublishers(&mut self) -> QVariantList {
        self.get_metadata_list(|db| db.get_all_publishers())
    }

    fn getYears(&mut self) -> QVariantList {
        let mut result = QVariantList::default();
        result.push(QString::from("All Years").into());
        let all = self.getAllYears();
        for i in 0..all.len() { result.push(all[i].clone()); }
        result
    }

    fn getAllYears(&mut self) -> QVariantList {
        self.get_metadata_list(|db| {
            let mut stmt = db.get_connection().prepare("SELECT DISTINCT SUBSTR(CAST(release_date AS TEXT), 1, 4) as year FROM metadata WHERE release_date IS NOT NULL AND release_date != '' ORDER BY year DESC")?;
            let rows = stmt.query_map([], |row| row.get::<_, String>(0))?;
            let mut list = Vec::new();
            for y in rows {
                let name = y?;
                if name.len() == 4 && name.chars().all(|c| c.is_digit(10)) {
                    list.push(name);
                }
            }
            Ok(list)
        })
    }

    fn getAllTags(&mut self) -> QVariantList {
        self.get_metadata_list(|db| db.get_all_tags())
    }

    // Helper for repetitive metadata list fetching
    fn get_metadata_list<F>(&self, f: F) -> QVariantList 
    where F: FnOnce(&DbManager) -> Result<Vec<String>, rusqlite::Error> {
        let db_path = self.db_path.borrow().clone();
        if let Ok(db) = DbManager::open(&db_path) {
            if let Ok(items) = f(&db) {
                return items.into_iter().map(|s| QVariant::from(QString::from(s))).collect();
            }
        }
        QVariantList::default()
    }

    #[allow(non_snake_case)]
    fn previewSystemImport(&mut self, name: String, extensions: String, rom_path: String, emulator_id: String, _platform_type: String, recursive: bool) -> String {

        
        let clean_path = if rom_path.starts_with("file://") {
            rom_path.replace("file://", "")
        } else {
            rom_path
        };
        let scan_path = Path::new(&clean_path);

        let extensions_lower = extensions.to_lowercase();
        let ext_list: Vec<&str> = extensions_lower.split(',')
            .map(|s| s.trim())
            .filter(|s| !s.is_empty())
            .collect();

        // If it's a file, we "scan" just that file. If it's a directory, we scan recursively.
        let roms_found = if scan_path.is_file() || scan_path.is_symlink() {
            // Manual creation of a Rom entry for a single file import
            let mut single_roms = Vec::new();
            if let Some(ext) = scan_path.extension().and_then(|e| e.to_str()) {
                if ext_list.is_empty() || ext_list.contains(&ext.to_lowercase().as_str()) {
                    single_roms.push(Rom {
                        id: Uuid::new_v4().to_string(),
                        platform_id: "preview".to_string(),
                        path: scan_path.to_string_lossy().to_string(),
                        filename: scan_path.file_name().and_then(|s| s.to_str()).unwrap_or_default().to_string(),
                        file_size: std::fs::metadata(scan_path).map(|m| m.len()).unwrap_or(0) as i64,
                        hash_sha1: None,
                        title: None, region: None, platform_name: None, platform_type: None, boxart_path: None,
                        date_added: None, play_count: None, total_play_time: None, last_played: None,
                        platform_icon: None, is_favorite: None, genre: None, developer: None, publisher: None,
                        rating: None, tags: None, icon_path: None, background_path: None, release_date: None, description: None,
                        is_installed: Some(true),
                        cloud_saves_supported: None,
                        resources: None,
                    });
                }
            }
            single_roms
        } else {
            Scanner::scan_directory("preview", scan_path, &ext_list, recursive)
        };
        
        let mut results = Vec::new();
        for rom in roms_found {
            let metadata = crate::core::parser::FileNameParser::parse(&rom.filename, &rom.id);
            
            let mut map = serde_json::Map::new();
            map.insert("id".to_string(), serde_json::json!(rom.id));
            map.insert("path".to_string(), serde_json::json!(rom.path));
            map.insert("filename".to_string(), serde_json::json!(rom.filename));
            map.insert("title".to_string(), serde_json::json!(metadata.title.unwrap_or_default()));
            map.insert("region".to_string(), serde_json::json!(metadata.region.unwrap_or_default()));
            map.insert("system".to_string(), serde_json::json!(name));
            map.insert("emulator".to_string(), serde_json::json!(emulator_id)); 
            
            // New fields for preview
            map.insert("genre".to_string(), serde_json::json!(metadata.genre.unwrap_or_default()));
            map.insert("developer".to_string(), serde_json::json!(metadata.developer.unwrap_or_default()));
            map.insert("publisher".to_string(), serde_json::json!(metadata.publisher.unwrap_or_default()));
            map.insert("year".to_string(), serde_json::json!(metadata.release_date.unwrap_or_default())); // Send as string for UI textfield
            map.insert("rating".to_string(), serde_json::json!(metadata.rating.unwrap_or(0.0).to_string()));
            map.insert("tags".to_string(), serde_json::json!(metadata.tags.unwrap_or_default()));

            results.push(serde_json::Value::Object(map));
        }

        serde_json::Value::Array(results).to_string()
    }

    #[allow(non_snake_case)]
    fn isDirectory(&self, path: QString) -> bool {
        let p = path.to_string();
        let cleaned = p.trim_start_matches("file://");
        Path::new(cleaned).is_dir()
    }

    #[allow(non_snake_case)]
    fn commitSystemImport(&mut self, name: String, extensions: String, rom_path: String, command: String, emulator_id: String, platform_type: String, icon: String, pc_config: String, selected_roms_json: String) {

        self.commitContentImport(String::new(), name, extensions, rom_path, command, emulator_id, platform_type, icon, pc_config, selected_roms_json);
    }

    #[allow(non_snake_case)]
    fn commitContentImport(&mut self, platform_id: String, name: String, extensions: String, rom_path: String, command: String, emulator_id: String, platform_type: String, icon: String, pc_config: String, selected_roms_json: String) {
        let is_existing = !platform_id.is_empty();
        log::info!("Committing Content Import: {} (Existing: {})", if is_existing { &platform_id } else { &name }, is_existing);
        
        let db_path = self.db_path.borrow().clone();
        if db_path.is_empty() { return; }

        let tx = match self.tx.borrow().as_ref() {
            Some(t) => t.clone(),
            None => return,
        };

        let clean_path_input = if rom_path.starts_with("file://") {
            rom_path.replace("file://", "")
        } else {
            rom_path
        };

        // Parse selected ROMs
        let selected_roms: Vec<serde_json::Value> = serde_json::from_str(&selected_roms_json).unwrap_or_default();
        // Removed early return if empty to allow platform creation without ROMs

        get_runtime().spawn(async move {
            if let Ok(db) = DbManager::open(&db_path) {
                // 1. Setup Platform if new, or get existing
                let final_platform_id = if is_existing {
                    platform_id
                } else {
                    let new_id = Uuid::new_v4().to_string();
                    let slug = name.to_lowercase().replace(" ", "-");
                    let em_id_opt = if emulator_id.is_empty() { None } else { Some(emulator_id.clone()) };
                    
                    // Normalize Platform Type
                    let normalized_type = if platform_type.to_lowercase() == "windows" {
                        "PC (Windows)".to_string()
                    } else if platform_type.to_lowercase() == "linux" {
                        "PC (Linux)".to_string()
                    } else {
                        platform_type.clone()
                    };

                    let type_opt = if normalized_type.is_empty() { None } else { Some(normalized_type.clone()) };
                    let icon_opt = if icon.is_empty() { None } else { Some(icon.clone()) };

                    let platform = Platform {
                        id: new_id.clone(),
                        slug,
                        name: name.clone(),
                        icon: icon_opt,
                        extension_filter: extensions.clone(),
                        command_template: Some(command),
                        default_emulator_id: em_id_opt,
                        platform_type: type_opt.clone(),
                        pc_config_json: if pc_config.is_empty() {
                            // If no config provided (e.g. from AddContentDialog quick import),
                            // and it's a PC platform, try to use Global Defaults.
                            if let Some(ref t) = type_opt {
                                let t_lower = t.to_lowercase();
                                if t_lower.contains("windows") || t_lower.contains("epic") {
                                    let (def_proton, def_prefix, def_wrapper, def_gamescope, def_mangohud, def_gs_args, 
                                         def_gs_w, def_gs_h, def_gs_out_w, def_gs_out_h, def_gs_r, def_gs_s, def_gs_u, def_gs_f) = crate::bridge::settings::AppSettings::get_pc_defaults();
                                    if !def_proton.is_empty() {
                                        log::info!("[GameModel] Applying Default PC Config for new platform: Proton={}", def_proton);
                                        Some(serde_json::json!({
                                            "umu_proton_version": def_proton,
                                            "wine_prefix": def_prefix,
                                            "wrapper": def_wrapper,
                                            "use_gamescope": def_gamescope,
                                            "use_mangohud": def_mangohud,
                                            "gamescope_args": def_gs_args,
                                            "gs_state": {
                                                "w": def_gs_w,
                                                "h": def_gs_h,
                                                "W": def_gs_out_w,
                                                "H": def_gs_out_h,
                                                "r": def_gs_r,
                                                "S": def_gs_s,
                                                "U": def_gs_u,
                                                "f": def_gs_f
                                            },
                                            "umu_id": "",
                                            "umu_store": "none"
                                        }).to_string())
                                    } else {
                                        None
                                    }
                                } else {
                                    None
                                }
                            } else {
                                None
                            }
                        } else { 
                            Some(pc_config) 
                        },
                    };

                    if let Err(e) = db.insert_platform(&platform) {
                        log::error!("Failed to insert platform: {}", e);
                        return;
                    }
                    new_id
                };

                // Add to source paths ONLY if it's a directory (Add Folder flow)
                if Path::new(&clean_path_input).is_dir() {
                    let _ = db.insert_platform_source(&final_platform_id, &clean_path_input);
                }

                // 1.5 Handle Icon Download if it's a remote URL
                let final_id_for_icon = final_platform_id.clone();
                let icon_str = icon.clone();
                if icon_str.starts_with("http") {
                    log::debug!("[Import] Triggering system icon download: {}", icon_str);
                    let db_path_icon = db_path.clone();
                    let slug = name.to_lowercase().replace(" ", "-");
                    let client = ScraperClient::new();
                    
                    get_runtime().spawn(async move {
                        if let Ok(bytes) = client.get_bytes(&icon_str).await {
                             let assets_dir = paths::get_assets_dir();
                             let systems_dir = assets_dir.join("systems");
                             if !systems_dir.exists() {
                                 let _ = std::fs::create_dir_all(&systems_dir);
                             }
                             
                             let ext = if icon_str.to_lowercase().ends_with(".jpg") || icon_str.to_lowercase().ends_with(".jpeg") {
                                 "jpg"
                             } else if icon_str.to_lowercase().ends_with(".svg") {
                                 "svg"
                             } else {
                                 "png"
                             };
                             
                             let filename = format!("{}.{}", slug, ext);
                             let file_path = systems_dir.join(&filename);
                             
                             if let Ok(mut file) = std::fs::File::create(&file_path) {
                                 if let Ok(_) = std::io::Write::write_all(&mut file, &bytes) {
                                     let rel_path = format!("assets/systems/{}", filename);
                                     // Update the platform in the DB
                                     if let Ok(db) = DbManager::open(&db_path_icon) {
                                         if let Ok(p) = db.get_platform(&final_id_for_icon) {
                                             if let Some(mut p) = p {
                                                 p.icon = Some(rel_path);
                                                 let _ = db.insert_platform(&p);
                                                 log::debug!("[Import] System icon assigned: {}", filename);
                                             }
                                         }
                                     }
                                 }
                             }
                        }
                    });
                }

                let total = selected_roms.len();
                // We need to fetch platform details for metadata processing if it was existing
                let platform_info = db.get_platform(&final_platform_id).ok().flatten();
                let platform_folder = platform_info.as_ref()
                    .and_then(|p| p.platform_type.clone().or(Some(p.name.clone())))
                    .unwrap_or_else(|| "Unknown".to_string());
                
                // Parse default PC settings if available
                let default_pc_settings = platform_info.as_ref()
                    .and_then(|p| p.pc_config_json.as_ref())
                    .and_then(|json| serde_json::from_str::<serde_json::Value>(json).ok());

                let mut imported_ids = Vec::new();

                // 2. Import ROMs
                for (i, rom_val) in selected_roms.iter().enumerate() {
                    let path = rom_val.get("path").and_then(|v| v.as_str()).unwrap_or_default();
                    let filename = rom_val.get("filename").and_then(|v| v.as_str()).unwrap_or_default();

                    let r_title = rom_val.get("title").and_then(|v| v.as_str()).filter(|s| !s.is_empty()).map(|s| s.to_string());
                    let r_region = rom_val.get("region").and_then(|v| v.as_str()).filter(|s| !s.is_empty()).map(|s| s.to_string());
                    let r_genre = rom_val.get("genre").and_then(|v| v.as_str()).filter(|s| !s.is_empty()).map(|s| s.to_string());
                    let r_dev = rom_val.get("developer").and_then(|v| v.as_str()).filter(|s| !s.is_empty()).map(|s| s.to_string());
                    let r_pub = rom_val.get("publisher").and_then(|v| v.as_str()).filter(|s| !s.is_empty()).map(|s| s.to_string());
                    let r_tags = rom_val.get("tags").and_then(|v| v.as_str()).filter(|s| !s.is_empty()).map(|s| s.to_string());
                    
                    let r_year = rom_val.get("year").and_then(|v| v.as_str()).map(|s| s.to_string());
                    let r_rating = rom_val.get("rating").and_then(|v| v.as_str()).and_then(|s| s.parse::<f32>().ok()).filter(|&r| r > 0.0);
                    let r_playtime = rom_val.get("total_play_time").and_then(|v| v.as_i64());
                    
                    let mut rom = Rom {
                        id: Uuid::new_v4().to_string(),
                        platform_id: final_platform_id.clone(),
                        path: path.to_string(),
                        filename: filename.to_string(),
                        file_size: 0,
                        hash_sha1: None,
                        title: r_title,
                        region: r_region,
                        platform_name: None,
                        platform_type: None,
                        boxart_path: None,
                        date_added: None,
                        play_count: None,
                        total_play_time: r_playtime,
                        last_played: None,
                        platform_icon: None,
                        is_favorite: None,
                        genre: r_genre,
                        developer: r_dev,
                        publisher: r_pub,
                        rating: r_rating,
                        tags: r_tags,
                        release_date: r_year,
                        icon_path: None,
                        background_path: None,
                        description: None,
                        is_installed: Some(true),
                        cloud_saves_supported: None,
                        resources: None, // Will be filled from JSON if present
                    };

                    // Extract resources from JSON if present
                    if let Some(res_val) = rom_val.get("resources").and_then(|v| v.as_array()) {
                        let mut resources = Vec::new();
                        for rv in res_val {
                            if let Ok(res) = serde_json::from_value::<crate::core::models::GameResource>(rv.clone()) {
                                resources.push(res);
                            }
                        }
                        if !resources.is_empty() {
                            rom.resources = Some(resources);
                        }
                    }

                    if platform_folder == "windows" || platform_folder == "PC (Windows)" {
                        rom.icon_path = Some("assets/systems/windows.png".to_string());
                    }

                    // Send Progress BEFORE processing to show current file
                    let _ = tx.send(AsyncResponse::ImportProgress((i as f32) / (total as f32), filename.to_string()));

                    if let Err(e) = db.insert_rom(&rom) {
                        log::error!("Failed to insert rom: {}", e);
                        continue;
                    }

                    // Insert resources if any
                    if let Some(resources) = &rom.resources {
                        for res in resources {
                            if let Err(e) = db.insert_resource(res) {
                                log::error!("Failed to insert resource: {}", e);
                            }
                        }
                    }

                    imported_ids.push(rom.id.clone());

                    // PC Config Inheritance
                    // If the platform has default PC settings, copy them to this game's individual config
                    if let Some(defaults) = &default_pc_settings {
                         let new_config = crate::core::models::PcConfig {
                            rom_id: rom.id.clone(),
                            umu_proton_version: defaults.get("umu_proton_version").and_then(|v| v.as_str()).map(|s| s.to_string()),
                            umu_store: defaults.get("umu_store").and_then(|v| v.as_str()).map(|s| s.to_string()),
                            wine_prefix: defaults.get("wine_prefix").and_then(|v| v.as_str()).map(|s| s.to_string()),
                            // working_dir is usually specific to the game, so we don't copy a default
                            working_dir: None, 
                            umu_id: defaults.get("umu_id").and_then(|v| v.as_str()).map(|s| s.to_string()),
                            env_vars: None, // Env vars are usually specific or complex, ignoring for now unless requested
                            extra_args: defaults.get("extra_args").and_then(|v| v.as_str()).map(|s| s.to_string()),
                            proton_verb: defaults.get("proton_verb").and_then(|v| v.as_str()).map(|s| s.to_string()),
                            disable_fixes: defaults.get("disable_fixes").and_then(|v| v.as_bool()),
                            no_runtime: defaults.get("no_runtime").and_then(|v| v.as_bool()),
                            log_level: defaults.get("log_level").and_then(|v| v.as_str()).map(|s| s.to_string()),
                            wrapper: defaults.get("wrapper").and_then(|v| v.as_str()).map(|s| s.to_string()),
                            use_gamescope: defaults.get("use_gamescope").and_then(|v| v.as_bool()),
                            gamescope_args: defaults.get("gamescope_args").and_then(|v| v.as_str()).map(|s| s.to_string()),
                            use_mangohud: defaults.get("use_mangohud").and_then(|v| v.as_bool()),
                             pre_launch_script: None,
                             post_launch_script: None,
                             cloud_saves_enabled: None,
                             cloud_save_path: None,
                             cloud_save_auto_sync: None,
                         };
                        
                        if let Err(e) = db.insert_pc_config(&new_config) {
                            log::error!("Failed to insert inherited PC config: {}", e);
                        } else {
                            log::info!("Inherited default PC settings for {}", rom.id);
                        }
                    }
                    // End: PC Config Inheritance

                    // Metadata
                    let mut metadata = crate::core::parser::FileNameParser::parse(filename, &rom.id);
                    
                    let rom_stem = Path::new(filename).file_stem().and_then(|s| s.to_str()).unwrap_or(filename);

                    // Sidecar Recovery
                    if let Some(sidecar) = MetadataManager::load_sidecar(&platform_folder, rom_stem) {
                        metadata = sidecar;
                        metadata.rom_id = rom.id.clone();
                    }

                    // Override with user-edited values if present in JSON (Import Dialog edits)
                    if let Some(t) = rom_val.get("title").and_then(|v| v.as_str()) {
                        metadata.title = Some(t.to_string());
                    }
                    if let Some(r) = rom_val.get("region").and_then(|v| v.as_str()) {
                        metadata.region = Some(r.to_string());
                    }
                    // Extract new fields
                    if let Some(v) = rom_val.get("genre").and_then(|v| v.as_str()) {
                        metadata.genre = Some(v.to_string());
                    }
                    if let Some(v) = rom_val.get("developer").and_then(|v| v.as_str()) {
                        metadata.developer = Some(v.to_string());
                    }
                    if let Some(v) = rom_val.get("publisher").and_then(|v| v.as_str()) {
                        metadata.publisher = Some(v.to_string());
                    }
                    if let Some(v) = rom_val.get("tags").and_then(|v| v.as_str()) {
                        metadata.tags = Some(v.to_string());
                    }
                    if let Some(v) = rom_val.get("year").and_then(|v| v.as_str()) {
                        if v == "0" || v.is_empty() {
                            metadata.release_date = None;
                        } else if let Ok(y) = v.parse::<i64>() {
                            metadata.release_date = Some(y.to_string());
                        } else {
                            metadata.release_date = Some(v.to_string());
                        }
                    }
                    if let Some(v) = rom_val.get("rating").and_then(|v| v.as_str()) {
                        if let Ok(r) = v.parse::<f32>() {
                            metadata.rating = Some(r);
                        }
                    }

                    let _ = db.insert_metadata(&metadata);
                    let _ = MetadataManager::save_sidecar(&platform_folder, rom_stem, &metadata);

                    // Assets
                    // Note: discover_assets_internal is a &self method, so we can't call it easily here in static context
                    // We'll duplicate the logic for now or move it to a helper.
                    // Actually, let's just use the logic from discover_assets_internal directly.
                    let data_dir = crate::core::paths::get_data_dir();
                    let rom_stem = Path::new(filename).file_stem().and_then(|s| s.to_str()).unwrap_or(filename);
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
                                                        let _ = db.insert_asset(&rom.id, &asset_type, &path);
                                                        
                                                        // Auto-link primary assets
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

                        // Update ROM table with found assets
                        if boxart_path.is_some() || icon_path.is_some() {
                             let conn = db.get_connection();
                             if let Some(bp) = boxart_path {
                                 let _ = conn.execute("UPDATE roms SET boxart_path = ?1 WHERE id = ?2", [&bp, &rom.id]);
                             }
                             if let Some(ip) = icon_path {
                                 let _ = conn.execute("UPDATE roms SET icon_path = ?1 WHERE id = ?2", [&ip, &rom.id]);
                             }
                        }
                    }
                }

                let _ = tx.send(AsyncResponse::ImportProgress(1.0, "Done".to_string()));
                let _ = tx.send(AsyncResponse::ImportFinished(final_platform_id, imported_ids));
            }
        });
    }

    #[allow(non_snake_case)]
    fn addSystem(&mut self, name: String, extensions: String, rom_path: String, command: String, emulator_id: String, platform_type: String, icon: String) {
        // Keeping this for backward compatibility or simple one-click import if needed,
        // but it could also just call preview then commit with everything selected.
        log::info!("Adding System (Legacy): {}", name);
        self.commitSystemImport(name, extensions, rom_path, command, emulator_id, platform_type, icon, String::new(), "[]".to_string()); // Added empty pc_config
    }

    #[allow(non_snake_case)]
    fn getGameMetadata(&mut self, rom_id: String) -> QString {
        let db_path = self.db_path.borrow().clone();
        if db_path.is_empty() {
            return QString::from("{}");
        }

        if let Ok(db) = DbManager::open(&db_path) {
            let metadata = db.get_metadata(&rom_id).unwrap_or(None);
            let assets = db.get_assets(&rom_id).unwrap_or_default();
            
            
            // Query for platform info for simple JSON return
            let conn = db.get_connection();
            let mut platform_id = String::new();
            let mut platform_type = String::new();
            let mut platform_name = String::new();
            let mut rom_path = String::new();
            let mut rom_filename = String::new();
            let mut rom_file_size: i64 = 0;
            
            if let Ok(mut stmt) = conn.prepare("SELECT r.platform_id, p.platform_type, p.name, r.path, r.filename, r.file_size FROM roms r LEFT JOIN platforms p ON r.platform_id = p.id WHERE r.id = ?1") {
                if let Ok(mut rows) = stmt.query([&rom_id]) {
                    if let Ok(Some(row)) = rows.next() {
                         platform_id = row.get::<_, Option<String>>(0).unwrap_or_default().unwrap_or_default();
                         platform_type = row.get::<_, Option<String>>(1).unwrap_or_default().unwrap_or_default();
                         platform_name = row.get::<_, Option<String>>(2).unwrap_or_default().unwrap_or_default();
                         rom_path = row.get::<_, Option<String>>(3).unwrap_or_default().unwrap_or_default();
                         rom_filename = row.get::<_, Option<String>>(4).unwrap_or_default().unwrap_or_default();
                         rom_file_size = row.get::<_, Option<i64>>(5).unwrap_or_default().unwrap_or_default();
                    }
                }
            }
            
            if platform_id.is_empty() {
                if rom_id.starts_with("legendary-") {
                    platform_id = "epic".to_string();
                    platform_type = "PC (Windows)".to_string();
                    platform_name = "Epic Games".to_string();
                } else if rom_id.starts_with("steam-") {
                    platform_id = "steam".to_string();
                    platform_type = "PC (Windows)".to_string();
                    platform_name = "Steam".to_string();
                }
            }
            
            // Construct JSON
            let mut map = serde_json::Map::new();
            map.insert("platform_id".to_string(), serde_json::Value::String(platform_id));
            map.insert("platform_type".to_string(), serde_json::Value::String(platform_type));
            map.insert("platform_name".to_string(), serde_json::Value::String(platform_name));
            map.insert("rom_path".to_string(), serde_json::Value::String(rom_path.clone()));
            map.insert("rom_filename".to_string(), serde_json::Value::String(rom_filename));
            map.insert("rom_file_size".to_string(), serde_json::json!(rom_file_size));
            
            if let Some(meta) = metadata {
                map.insert("title".to_string(), serde_json::Value::String(meta.title.unwrap_or_default()));
                map.insert("description".to_string(), serde_json::Value::String(meta.description.unwrap_or_default()));
                map.insert("developer".to_string(), serde_json::Value::String(meta.developer.unwrap_or_default()));
                map.insert("publisher".to_string(), serde_json::Value::String(meta.publisher.unwrap_or_default()));
                map.insert("genre".to_string(), serde_json::Value::String(meta.genre.unwrap_or_default()));
                map.insert("tags".to_string(), serde_json::Value::String(meta.tags.unwrap_or_default()));
                map.insert("region".to_string(), serde_json::Value::String(meta.region.unwrap_or_default()));
                map.insert("rating".to_string(), serde_json::json!(meta.rating.unwrap_or(0.0)));
                map.insert("release_date".to_string(), serde_json::json!(meta.release_date.unwrap_or_default()));
                map.insert("play_count".to_string(), serde_json::json!(meta.play_count));
                map.insert("last_played".to_string(), serde_json::json!(meta.last_played.unwrap_or(0)));
                
                let play_time = meta.total_play_time;
                map.insert("total_play_time".to_string(), serde_json::json!(play_time));
                
                map.insert("is_favorite".to_string(), serde_json::json!(meta.is_favorite));
                map.insert("achievement_count".to_string(), serde_json::json!(meta.achievement_count.unwrap_or(0)));
                map.insert("achievement_unlocked".to_string(), serde_json::json!(meta.achievement_unlocked.unwrap_or(0)));
                map.insert("ra_recent_badges".to_string(), serde_json::json!(meta.ra_recent_badges.unwrap_or("[]".to_string())));
                map.insert("is_installed".to_string(), serde_json::json!(meta.is_installed));
                map.insert("cloud_saves_supported".to_string(), serde_json::json!(meta.cloud_saves_supported));
            } else {
                 map.insert("title".to_string(), serde_json::Value::String(String::new()));
                 map.insert("is_installed".to_string(), serde_json::json!(if rom_id.starts_with("steam-") {
                     crate::core::store::StoreManager::get_local_steam_appids().contains(&rom_id.replace("steam-", ""))
                 } else if rom_id.starts_with("legendary-") {
                     // For Legendary, if metadata is missing, we check if it's in the installed list
                     // but for now we default to false as store games need explicit installation
                     false
                 } else {
                     true
                 }));
                 map.insert("cloud_saves_supported".to_string(), serde_json::json!(false));
            }

            let mut assets_map = serde_json::Map::new();
            for (curr_type, paths) in assets {
                 let json_paths: Vec<serde_json::Value> = paths.into_iter()
                    .map(|p| serde_json::Value::String(resolve_local_path(&p)))
                    .collect();
                 assets_map.insert(curr_type, serde_json::Value::Array(json_paths));
            }
            map.insert("assets".to_string(), serde_json::Value::Object(assets_map));

            // Resources
            if let Ok(resources) = db.get_resources(&rom_id) {
                let json_resources: Vec<serde_json::Value> = resources.into_iter().map(|r| {
                    let mut r_map = serde_json::Map::new();
                    r_map.insert("id".to_string(), serde_json::Value::String(r.id));
                    r_map.insert("type".to_string(), serde_json::Value::String(r.type_));
                    r_map.insert("url".to_string(), serde_json::Value::String(r.url));
                    r_map.insert("label".to_string(), serde_json::Value::String(r.label.unwrap_or_default()));
                    serde_json::Value::Object(r_map)
                }).collect();
                map.insert("resources".to_string(), serde_json::Value::Array(json_resources));
            }
            
            return QString::from(serde_json::Value::Object(map).to_string());
        }
        
        QString::from("{}")
    }

    #[allow(non_snake_case)]
    fn getUpNextSuggestion(&mut self, last_played_id: String) -> QString {
        let db_path = self.db_path.borrow().clone();
        if db_path.is_empty() { return QString::from("{}"); }

        if let Ok(db) = DbManager::open(&db_path) {
            let mut suggestion = None;

            // 1. Try same genre
            if !last_played_id.is_empty() {
                if let Ok(Some(meta)) = db.get_metadata(&last_played_id) {
                    if let Some(genre) = meta.genre {
                        if !genre.is_empty() {
                            suggestion = db.get_random_game_by_genre(&genre, &last_played_id).unwrap_or(None);
                        }
                    }
                }
            }

            // 2. Fallback to any random game
            if suggestion.is_none() {
                suggestion = db.get_random_game(if last_played_id.is_empty() { None } else { Some(&last_played_id) }).unwrap_or(None);
            }

            if let Some(rom) = suggestion {
                let mut map = serde_json::Map::new();
                map.insert("id".to_string(), serde_json::Value::String(rom.id));
                map.insert("title".to_string(), serde_json::Value::String(rom.title.unwrap_or(rom.filename)));
                map.insert("platform".to_string(), serde_json::Value::String(rom.platform_name.unwrap_or_default()));
                return QString::from(serde_json::Value::Object(map).to_string());
            }
        }

        QString::from("{}")
    }

    #[allow(non_snake_case)]
    fn getRecentGamesJSON(&mut self, limit: i32) -> QString {
        let db_path = self.db_path.borrow().clone();
        if db_path.is_empty() { return QString::from("[]"); }

        if let Ok(db) = DbManager::open(&db_path) {
            if let Ok(roms) = db.get_library_view("Recent", None) {
                let recent: Vec<serde_json::Value> = roms.into_iter()
                    .take(limit as usize)
                    .map(|rom| {
                        let mut map = serde_json::Map::new();
                        map.insert("id".to_string(), serde_json::Value::String(rom.id.clone()));
                        map.insert("title".to_string(), serde_json::Value::String(rom.title.unwrap_or(rom.filename)));
                        
                        // Fetch icon if available
                        if let Ok(assets) = db.get_assets(&rom.id) {
                            if let Some(icons) = assets.get("Icon").or_else(|| assets.get("icon")) {
                                if let Some(icon) = icons.first() {
                                    map.insert("icon".to_string(), serde_json::Value::String(icon.clone()));
                                }
                            }
                        }
                        
                        serde_json::Value::Object(map)
                    })
                    .collect();
                return QString::from(serde_json::Value::Array(recent).to_string());
            }
        }
        QString::from("[]")
    }


    fn updateGameAchievements(&mut self, rom_id: String, count: i32, unlocked: i32, badges: String) {
        let db_path = self.db_path.borrow().clone();
        if db_path.is_empty() { return; }
        
        let badges_opt = if badges.is_empty() { None } else { Some(badges.as_str()) };
        
        if let Ok(db) = DbManager::open(&db_path) {
            if let Err(e) = db.update_achievements(&rom_id, count, unlocked, badges_opt) {
                log::error!("Failed to update achievements: {}", e);
            } else {
                self.update_row_by_id(&rom_id);
            }
        }
    }

    fn updateGameMetadata(&mut self, rom_id: String, json_data: String) {
        let db_path = self.db_path.borrow().clone();
        if db_path.is_empty() { return; }

        let client = self.get_scraper_client();
        let tx = match self.tx.borrow().as_ref() {
            Some(t) => t.clone(),
            None => {
                log::error!("No async channel available for metadata update");
                return;
            }
        };

        if let Ok(json) = serde_json::from_str::<serde_json::Value>(&json_data) {
             if let Ok(db) = DbManager::open(&db_path) {
                  let mut meta = db.get_metadata(&rom_id).unwrap_or(None).unwrap_or(crate::core::models::GameMetadata {
                      rom_id: rom_id.clone(),
                      title: None, description: None, rating: None, release_date: None, developer: None, 
                      publisher: None, genre: None, tags: None, region: None, 
                      is_favorite: false,
                      play_count: 0, last_played: None, total_play_time: 0,
                      achievement_count: None, achievement_unlocked: None,
                      ra_game_id: None,
                      ra_recent_badges: None,
                      is_installed: if rom_id.starts_with("steam-") {
                          crate::core::store::StoreManager::get_local_steam_appids().contains(&rom_id.replace("steam-", ""))
                      } else if rom_id.starts_with("legendary-") {
                          false
                      } else {
                          true
                      },
                      cloud_saves_supported: false,
                      resources: None,
                  });

                  if let Some(v) = json.get("title").and_then(|v| v.as_str()) { meta.title = Some(v.to_string()); }
                  if let Some(v) = json.get("description").and_then(|v| v.as_str()) { meta.description = Some(v.to_string()); }
                  if let Some(v) = json.get("developer").and_then(|v| v.as_str()) { meta.developer = Some(v.to_string()); }
                  if let Some(v) = json.get("publisher").and_then(|v| v.as_str()) { meta.publisher = Some(v.to_string()); }
                  if let Some(v) = json.get("genre").and_then(|v| v.as_str()) { meta.genre = Some(v.to_string()); }
                  if let Some(v) = json.get("tags").and_then(|v| v.as_str()) { meta.tags = Some(v.to_string()); }
                  if let Some(v) = json.get("region").and_then(|v| v.as_str()) { meta.region = Some(v.to_string()); }
                  if let Some(v) = json.get("rating").and_then(|v| v.as_f64()) { meta.rating = Some(v as f32); }
                  if let Some(v) = json.get("release_date") {
                      if let Some(i) = v.as_i64() {
                          meta.release_date = if i == 0 { None } else { Some(i.to_string()) };
                      } else if let Some(s) = v.as_str() {
                          meta.release_date = if s == "0" || s.is_empty() { None } else { Some(s.to_string()) };
                      }
                  }
                  if let Some(v) = json.get("achievement_count").and_then(|v| v.as_i64()) { meta.achievement_count = Some(v as i32); }
                  if let Some(v) = json.get("achievement_unlocked").and_then(|v| v.as_i64()) { meta.achievement_unlocked = Some(v as i32); }

                  // Handle Resources
                  if let Some(resources) = json.get("resources").and_then(|v| v.as_array()) {
                      for res in resources {
                          if let (Some(url), Some(label), Some(type_)) = (
                              res.get("url").and_then(|v| v.as_str()),
                              res.get("label").and_then(|v| v.as_str()),
                              res.get("type").and_then(|v| v.as_str())
                          ) {
                              let normalized_url = normalize_url(url);
                              if let Ok(existing_resources) = db.get_resources(&rom_id) {
                                  let exists = existing_resources.iter().any(|r| normalize_url(&r.url) == normalized_url);
                                  if !exists {
                                      let new_res = crate::core::models::GameResource {
                                          id: uuid::Uuid::new_v4().to_string(),
                                          rom_id: rom_id.clone(),
                                          type_: type_.to_string(),
                                          url: url.to_string(),
                                          label: Some(label.to_string()),
                                      };
                                      let _ = db.insert_resource(&new_res);
                                  }
                              }
                          }
                      }
                  }

                  if let Err(e) = db.insert_metadata(&meta) {
                      log::error!("Failed to update metadata: {}", e);
                  } else {
                      self.update_row_by_id(&rom_id);
                      
                      // Save Sidecar
                      if let Ok(Some((platform_folder, filename))) = db.get_rom_path_info(&rom_id) {
                          let rom_stem = Path::new(&filename).file_stem().and_then(|s| s.to_str()).unwrap_or(&filename);
                          let _ = MetadataManager::save_sidecar(&platform_folder, rom_stem, &meta);
                      }
                  }

                  // Handle Assets (Images) - Asynchronously Download
                  if let Some(assets_json_obj) = json.get("assets").and_then(|v| v.as_object()) {
                      let mut assets_map: std::collections::HashMap<String, Vec<String>> = std::collections::HashMap::new();
                      for (k, v) in assets_json_obj {
                          if let Some(arr) = v.as_array() {
                              let urls: Vec<String> = arr.iter()
                                  .filter_map(|val: &serde_json::Value| val.as_str().map(|s| s.to_string()))
                                  .collect();
                              assets_map.insert(k.clone(), urls);
                          }
                      }

                      if !assets_map.is_empty() {
                          let client_clone = client.clone();
                          let rom_id_clone = rom_id.clone();
                          let db_path_clone = db_path.clone();
                          let tx_clone = tx.clone();
                          
                          // Get Rom Info for Pathing (Sync before spawn)
                          let mut platform_folder = String::from("Unknown");
                          let mut rom_stem = String::from("unknown");
                          {
                               let roms = self.roms.borrow();
                               if let Some(rom) = roms.iter().find(|r| r.id == rom_id) {
                                   platform_folder = rom.platform_type.as_ref()
                                       .or(rom.platform_name.as_ref())
                                       .cloned()
                                       .unwrap_or(String::from("Unknown"));
                                   rom_stem = std::path::Path::new(&rom.filename)
                                       .file_stem()
                                       .and_then(|s| s.to_str())
                                       .unwrap_or(&rom.filename)
                                       .to_string();
                               }
                          }

                          get_runtime().spawn(async move {
                              download_game_assets(
                                  client_clone,
                                  tx_clone,
                                  rom_id_clone,
                                  db_path_clone,
                                  platform_folder,
                                  rom_stem,
                                  assets_map,
                              ).await;
                          });
                      }
                  }
             }
        }
    }

    #[allow(non_snake_case)]
    fn updateGameAsset(&mut self, rom_id: String, asset_type: String, file_path: String) {
        let db_path = self.db_path.borrow().clone();
        if db_path.is_empty() { return; }
        
        let src_path = if file_path.starts_with("file://") {
            file_path.replace("file://", "")
        } else {
            file_path
        };
        let src_path = std::path::Path::new(&src_path);

        if let Ok(db) = DbManager::open(&db_path) {
            // Get ROM details for pathing
            if let Ok(Some((platform_name, rom_filename))) = db.get_rom_path_info(&rom_id) {
                let media_type = match asset_type.as_str() {
                    "boxart" => "Box - Front",
                    "boxart_back" => "Box - Back",
                    "screenshot" => "Screenshot",
                    "banner" => "Banner",
                    "logo" => "Clear Logo",
                    "clearlogo" => "Clear Logo",
                    "background" => "Background",
                    "video" => "Video",
                    _ => &asset_type,
                };

                let data_dir = crate::core::paths::get_data_dir();
                let rom_stem = std::path::Path::new(&rom_filename).file_stem().and_then(|s| s.to_str()).unwrap_or(&rom_filename);
                let platform_folder = platform_name.replace("/", "-").replace("\\", "-");
                let dest_dir = data_dir.join("Images").join(&platform_folder).join(rom_stem).join(media_type);
                
                if let Err(e) = std::fs::create_dir_all(&dest_dir) {
                    log::error!("Failed to create asset dir: {}", e);
                    return;
                }

                let ext = src_path.extension().and_then(|s| s.to_str()).unwrap_or("png");
                let mut dest_filename = format!("{}.{}", rom_stem, ext);
                let mut dest_path = dest_dir.join(&dest_filename);
                
                let mut counter = 1;
                while dest_path.exists() {
                     dest_filename = format!("{} ({}).{}", rom_stem, counter, ext);
                     dest_path = dest_dir.join(&dest_filename);
                     counter += 1;
                }

                let mut final_path = src_path.to_string_lossy().to_string();
                if src_path != dest_path && !dest_path.exists() {
                    // Only copy if paths are different AND destination doesn't exist already
                    // This avoids redundant copies from downloadAsset
                    if let Err(e) = std::fs::copy(src_path, &dest_path) {
                        log::error!("Failed to copy asset from {:?} to {:?}: {}", src_path, dest_path, e);
                    } else {
                        final_path = dest_path.to_string_lossy().to_string();
                        // Cleanup source if it was a temporary file
                        if src_path.components().any(|c| c.as_os_str() == "Temp") {
                            let _ = std::fs::remove_file(src_path);
                        }
                    }
                } else if dest_path.exists() {
                     // If it already exists, just use that path
                     final_path = dest_path.to_string_lossy().to_string();
                     // Still cleanup source if it was temporary
                     if src_path != dest_path && src_path.components().any(|c| c.as_os_str() == "Temp") {
                         let _ = std::fs::remove_file(src_path);
                     }
                }

                if let Err(e) = db.insert_asset(&rom_id, media_type, &final_path) {
                    log::error!("Failed to insert asset record: {}", e);
                }
            } else {
                log::error!("Could not find ROM path info for {}", rom_id);
                if let Err(e) = db.insert_asset(&rom_id, &asset_type, &src_path.to_string_lossy()) {
                     log::error!("Failed to insert asset record (fallback): {}", e);
                }
            }
        }
        self.update_row_by_id(&rom_id);
    }

    #[allow(non_snake_case)]
    fn refreshGameAssets(&mut self, rom_id: String) {
        let db_path = self.db_path.borrow().clone();
        if let Ok(db) = DbManager::open(&db_path) {
            match crate::core::asset_scanner::scan_game_assets(&db, &rom_id) {
                Ok(_) => {
                    log::debug!("refreshGameAssets: Successfully rescanned assets for {}", rom_id);
                    self.update_row_by_id(&rom_id);
                },
                Err(e) => {
                    log::error!("refreshGameAssets: Failed to scan assets: {}", e);
                }
            }
        }
    }

    #[allow(non_snake_case)]
    fn deleteGameAsset(&mut self, rom_id: String, asset_type: String, file_path: String) {
        let db_path = self.db_path.borrow().clone();
        if db_path.is_empty() { return; }

        let path_obj = Path::new(&file_path);
        
        // 1. Delete the physical file
        if path_obj.exists() {
            let _ = std::fs::remove_file(path_obj);
        }

        // 2. Remove from database
        if let Ok(db) = DbManager::open(&db_path) {
            let conn = db.get_connection();
            
            // Clear legacy columns in roms table if they match (to ensure GridView updates correctly)
            let column = match asset_type.as_str() {
                "Box - Front" => Some("boxart_path"),
                "Icon" => Some("icon_path"),
                "Background" => Some("background_path"),
                _ => None,
            };
            
            if let Some(col) = column {
                let sql = format!("UPDATE roms SET {} = NULL WHERE id = ?1 AND {} = ?2", col, col);
                let _ = conn.execute(&sql, [&rom_id, &file_path]);
            }

            let _ = conn.execute(
                "DELETE FROM assets WHERE rom_id = ?1 AND type = ?2 AND local_path = ?3",
                [rom_id, asset_type, file_path]
            );
        }
        self.refresh();
    }

    fn getGameId(&mut self, row: i32) -> QString {
        let roms = self.roms.borrow();
        if row >= 0 && (row as usize) < roms.len() {
            QString::from(roms[row as usize].id.clone())
        } else {
            QString::from("")
        }
    }

    #[allow(non_snake_case)]
    fn getRowById(&mut self, rom_id: String) -> i32 {
        let roms = self.roms.borrow();
        for (idx, rom) in roms.iter().enumerate() {
            if rom.id == rom_id {
                return idx as i32;
            }
        }
        -1
    }

    fn get_effective_char(&self, rom: &Rom) -> char {
        let title = rom.title.as_deref().unwrap_or(rom.filename.as_str());
        let ignore_the = *self.ignore_the_in_sort.borrow();
        
        let effective_title = if ignore_the && (title.to_uppercase().starts_with("THE ")) {
            &title[4..]
        } else {
            title
        };
        
        effective_title.chars().next().unwrap_or('?').to_uppercase().next().unwrap_or('?')
    }

    fn get_display_char(&self, index: usize) -> char {
        let roms = self.roms.borrow();
        if index >= roms.len() { return '?'; }
        
        self.get_effective_char(&roms[index])
    }

    #[allow(non_snake_case)]
    fn findNextLetter(&mut self, current_index: i32) -> i32 {
        let roms = self.roms.borrow();
        let total = roms.len() as i32;
        if current_index < 0 || current_index >= total - 1 { return -1; }
        
        // Temporarily borrow logic helper
        // Since we can't call &self method while borrowing roms (refcell), we duplicate logic or clone
        // Cloning title string is cheap enough for this navigation op
        let idx = current_index as usize;
        let start_char = self.get_effective_char(&roms[idx]);

        for i in (idx + 1)..roms.len() {
            let current_char = self.get_effective_char(&roms[i]);
            
            if current_char != start_char {
                return i as i32;
            }
        }

        -1
    }

    #[allow(non_snake_case)]
    fn findPrevLetter(&mut self, current_index: i32) -> i32 {
        let roms = self.roms.borrow();
        if current_index <= 0 { return 0; }
        
        let idx = current_index as usize;
        let start_char = self.get_effective_char(&roms[idx]);

        // 1. Find previous DIFFERENT character (end of previous section)
        let mut diff_index = None;
        for i in (0..idx).rev() {
            let current_char = self.get_effective_char(&roms[i]);
            
            if current_char != start_char {
                diff_index = Some(i);
                break;
            }
        }

        if let Some(mut prev_idx) = diff_index {
             // 2. We found the last item of the previous section. 
             // Now find the START of that section.
             let target_char = self.get_effective_char(&roms[prev_idx]);
            
            // Iterate backwards from prev_idx
            while prev_idx > 0 {
                let prev_char = self.get_effective_char(&roms[prev_idx - 1]);
                
                if prev_char != target_char {
                    break;
                }
                prev_idx -= 1;
            }
            return prev_idx as i32;

        } else {
            // If no different char found (e.g. we are at 'A' game #5, and all before are 'A'), go to 0
            return 0;
        }
    }

    #[allow(non_snake_case)]
    fn getLetterAt(&mut self, index: i32) -> QString {
        let roms = self.roms.borrow();
        if index < 0 || (index as usize) >= roms.len() { return QString::from(""); }
        
        let rom = &roms[index as usize];
        let c = self.get_effective_char(rom);
        QString::from(c.to_string())
    }



    #[allow(non_snake_case)]
    fn getEmulatorProfiles(&mut self, platform_id: String) -> QString {
        let db_path = self.db_path.borrow().clone();
        if db_path.is_empty() { return QString::from("[]"); }

        if let Ok(db) = DbManager::open(&db_path) {
            let conn = db.get_connection();
            if let Ok(mut stmt) = conn.prepare(
                "SELECT ep.id, ep.name, ep.executable_path, ep.arguments 
                 FROM emulator_profiles ep
                 JOIN platform_emulators pe ON ep.id = pe.emulator_id
                 WHERE pe.platform_id = ?1"
            ) {
                let profiles = stmt.query_map([platform_id], |row| {
                    Ok(serde_json::json!({
                        "id": row.get::<_, String>(0)?,
                        "name": row.get::<_, String>(1)?,
                        "executable": row.get::<_, String>(2)?,
                        "args": row.get::<_, String>(3)?
                    }))
                }).map(|iter| iter.filter_map(|r| r.ok()).collect::<Vec<_>>()).unwrap_or_default();

                return QString::from(serde_json::to_string(&profiles).unwrap_or("[]".to_string()));
            }
        }
        QString::from("[]")
    }

    #[allow(non_snake_case)]
    fn launchWithProfile(&mut self, rom_id: String, profile_id: String) {
        let db_path = self.db_path.borrow().clone();
        if db_path.is_empty() { return; }

        if let Ok(db) = DbManager::open(&db_path) {
            let conn = db.get_connection();
            // 1. Get ROM path
            let rom_path: String = if let Ok(mut rom_stmt) = conn.prepare("SELECT path FROM roms WHERE id = ?1") {
                rom_stmt.query_row([&rom_id], |row| row.get(0)).unwrap_or_default()
            } else { String::new() };

            if rom_path.is_empty() { return; }

            // 2. Get Profile
            let profile = if let Ok(mut p_stmt) = conn.prepare("SELECT executable_path, arguments FROM emulator_profiles WHERE id = ?1") {
                p_stmt.query_row([profile_id], |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)))
            } else { Err(rusqlite::Error::QueryReturnedNoRows) };

            if let Ok((exe, args)) = profile {
                let cmd = format!("{} {}", exe, args);
                let wd = std::path::Path::new(&rom_path).parent().map(|p| p.to_string_lossy().to_string());
                let _ = crate::core::launcher::Launcher::launch(&cmd, &rom_path, wd.as_deref(), None, None, false);
                
                let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs() as i64;
                let _ = conn.execute(
                    "UPDATE metadata SET play_count = play_count + 1, last_played = ?1 WHERE rom_id = ?2",
                    rusqlite::params![now, rom_id]
                );
            }
        }
    }

    #[allow(non_snake_case)]
    fn rescanSystem(&mut self, platform_id: String) {
        log::debug!("Rescanning System: ID={}", platform_id);
        let db_path = self.db_path.borrow().clone();
        if db_path.is_empty() { return; }

        if let Ok(db) = DbManager::open(&db_path) {
            // 1. Get Platform details
            if let Ok(Some(platform)) = db.get_platform(&platform_id) {
                let platform_type = platform.platform_type.clone().unwrap_or_default().to_lowercase();
                
                if platform_type == "steam" || platform_type == "heroic" || platform_type == "lutris" {
                    log::debug!("[Rescan] Specialized rescan for store platform: {}", platform_type);
                    
                    let scanned_roms = match platform_type.as_str() {
                        "steam" => {
                            let mut local = crate::core::store::StoreManager::scan_steam_games();
                            let (steam_id, api_key) = crate::bridge::settings::AppSettings::get_steam_credentials();
                            if !steam_id.is_empty() && !api_key.is_empty() {
                                if let Ok(remote) = crate::core::store::StoreManager::fetch_remote_steam_games(&steam_id, &api_key) {
                                    local.extend(remote);
                                }
                            }
                            local
                        },
                        "heroic" => crate::core::store::StoreManager::scan_heroic_games(),
                        "lutris" => crate::core::store::StoreManager::scan_lutris_games(),
                        _ => Vec::new(),
                    };

                    let existing_roms = db.get_roms_by_platform(&platform_id).unwrap_or_default();
                    let existing_paths: std::collections::HashSet<String> = existing_roms.iter().map(|r| r.path.clone()).collect();
                    
                    if platform_type == "steam" {
                        let existing_map: std::collections::HashMap<String, String> = existing_roms.into_iter().map(|r| (r.path, r.id)).collect();
                        let mut updates = Vec::new(); // will be Vec<(String, i64, i64)>
                        for remote_rom in &scanned_roms {
                            if let Some(existing_id) = existing_map.get(&remote_rom.path) {
                                let remote_time = remote_rom.total_play_time.unwrap_or(0);
                                let remote_last_played = remote_rom.last_played.unwrap_or(0);
                                if remote_time > 0 || remote_last_played > 0 {
                                    updates.push((existing_id.clone(), remote_time, remote_last_played));
                                }
                            }
                        }
                        if !updates.is_empty() {
                            let _ = db.bulk_update_playtimes(&updates);
                        }

                        // Sync is_installed status
                        for remote_rom in &scanned_roms {
                            if let Some(existing_id) = existing_map.get(&remote_rom.path) {
                                let installed = remote_rom.is_installed.unwrap_or(true);
                                let _ = db.get_connection().execute("UPDATE metadata SET is_installed = ?1 WHERE rom_id = ?2", rusqlite::params![installed as i32, existing_id]);
                            }
                        }
                    }

                    let ignored_paths = db.get_ignore_list(&platform_id).unwrap_or_default();
                    
                    let to_import: Vec<crate::core::models::Rom> = scanned_roms.into_iter()
                        .filter(|r| !existing_paths.contains(&r.path) && !ignored_paths.contains(&r.path))
                        .collect();

                    if !to_import.is_empty() {
                        log::debug!("[Rescan] Found {} new games to import for {}", to_import.len(), platform_type);
                        use crate::core::importer::BulkImporter;
                        let save_locally = crate::bridge::settings::AppSettings::should_save_heroic_assets_locally();
                        let _ = BulkImporter::import_roms(&db, to_import, &platform_id, save_locally, |_, _| {});
                    } else {
                        log::debug!("[Rescan] No new games found for {}", platform_type);
                    }
                    
                    self.refresh();
                    return;
                }

                // --- Standard Rescan Logic (Directory Based) ---
                // 2. Get all source paths
                let mut source_paths = db.get_platform_sources(&platform_id).unwrap_or_default();
                
                // Fallback to legacy behavior: infer from existing ROMs if no sources stored
                if source_paths.is_empty() {
                    if let Ok(roms) = db.get_roms_by_platform(&platform_id) {
                        if let Some(first_rom) = roms.first() {
                            if let Some(parent) = Path::new(&first_rom.path).parent() {
                                source_paths.push(parent.to_string_lossy().to_string());
                            }
                        }
                    }
                }

                if source_paths.is_empty() {
                    log::error!("Could not determine ROM directory for rescan (no games and no sources stored)");
                    return;
                }

                let extensions_lower = platform.extension_filter.to_lowercase();
                let ext_list: Vec<&str> = extensions_lower.split(',')
                    .map(|s| s.trim())
                    .filter(|s| !s.is_empty())
                    .collect();

                let existing_paths = db.get_rom_paths_by_platform(&platform_id).unwrap_or_default();
                let ignored_paths = db.get_ignore_list(&platform_id).unwrap_or_default();
                let platform_folder = platform.platform_type.clone().or(Some(platform.name.clone())).unwrap_or_else(|| "Unknown".to_string());

                let mut new_count = 0;
                
                for source_path in source_paths {

                    let scanned_roms = Scanner::scan_directory(&platform_id, Path::new(&source_path), &ext_list, true);
                    
                    for rom in scanned_roms {
                        if !existing_paths.contains(&rom.path) && !ignored_paths.contains(&rom.path) {
                            // New game found and not ignored!
                            if let Ok(_) = db.insert_rom(&rom) {
                                // Parse metadata
                                use crate::core::parser::FileNameParser;
                                let mut metadata = FileNameParser::parse(&rom.filename, &rom.id);

                                // Sidecar Recovery
                                let rom_stem = Path::new(&rom.filename).file_stem().and_then(|s| s.to_str()).unwrap_or(&rom.filename);
                                if let Some(sidecar) = MetadataManager::load_sidecar(&platform_folder, rom_stem) {
                                    metadata = sidecar;
                                    metadata.rom_id = rom.id.clone();
                                }

                                let _ = db.insert_metadata(&metadata);
                                let _ = MetadataManager::save_sidecar(&platform_folder, rom_stem, &metadata);

                                // Automatic Asset Discovery
                                self.discover_assets_internal(&db, &rom.id, &platform_folder, &rom.filename);
                                new_count += 1;
                            }
                        }
                    }
                }
                log::debug!("Rescan complete: {} new games found.", new_count);
            }
        }
        self.refresh();
    }

    #[allow(non_snake_case)]
    fn launchGame(&mut self, rom_id: String) {
        log::debug!("Requesting launch for ROM: {}", rom_id);
        let path_str = self.db_path.borrow().clone();
        
        // We need to clone specific data to move into the thread
        let rom_id_clone = rom_id.clone();
        
        if let Ok(db) = DbManager::open(&path_str) {
             if let Ok(Some((rom_path, mut command_template, platform_type, platform_pc_defaults))) = db.get_launch_info(&rom_id) {
                 use crate::core::launcher::Launcher;

                 let mut working_dir = std::path::Path::new(&rom_path).parent().map(|p| p.to_string_lossy().to_string());

                  let p_type = platform_type.unwrap_or_default();
                  let is_pc = p_type.contains("PC") || rom_path.starts_with("epic://");
                  
                  let mut env_prefix = String::new();
                  let mut wrapper_cmd = String::new();
                  let mut extra = String::new();
                  let mut pre_script = None;
                  let mut post_script = None;
                  // Cloud save values hoisted out of `if is_pc` so they survive to launch/exit
                  let mut cloud_saves_enabled = false;
                  let mut cloud_save_auto_sync = false;
                  let mut cloud_save_path_opt: Option<String> = None;
                  let mut cloud_wine_prefix_opt: Option<String> = None;

                  if is_pc {
                      // 1. Get platform defaults
                          let pc_config = db.get_pc_config(&rom_id).ok().flatten();
                          let platform_defaults = platform_pc_defaults.as_ref().and_then(|json| serde_json::from_str::<serde_json::Value>(json).ok());

                          // 2. Resolve Settings (Strict Precedence: Local Config -> Defaults)
                          // If PC Config exists, we use IT as the source of truth. We do NOT fallback to defaults for individual fields.
                          // Defaults are only used if NO PC Config exists at all.

                          if let Some(c) = &pc_config {
                              // --- LOCAL CONFIG EXISTS: USE ONLY LOCAL VALUES ---
                              // Extract cloud save settings while pc_config is in scope
                              cloud_saves_enabled = c.cloud_saves_enabled.unwrap_or(false);
                              cloud_save_auto_sync = c.cloud_save_auto_sync.unwrap_or(false);
                              cloud_save_path_opt = c.cloud_save_path.clone().filter(|s: &String| !s.trim().is_empty());
                              cloud_wine_prefix_opt = c.wine_prefix.clone().filter(|s: &String| !s.trim().is_empty());

                              if let Some(wd) = c.working_dir.as_ref().filter(|s| !s.trim().is_empty()) {
                                  working_dir = Some(wd.clone());
                              }

                              if c.use_mangohud.unwrap_or(false) { env_prefix.push_str("MANGOHUD=1 "); }

                              pre_script = c.pre_launch_script.clone().filter(|s| !s.trim().is_empty());
                              post_script = c.post_launch_script.clone().filter(|s| !s.trim().is_empty());

                              let use_gs = c.use_gamescope.unwrap_or(false);
                              let gs_args = c.gamescope_args.clone();
                              
                              let wrapper = c.wrapper.clone();

                              if let Some(w) = wrapper.filter(|s| !s.trim().is_empty()) { wrapper_cmd.push_str(&format!("{} ", w.trim())); }
                              
                              if use_gs {
                                  wrapper_cmd.push_str(&format!("gamescope {} -- ", gs_args.as_deref().unwrap_or("").trim()));
                              }

                              // Env Vars
                              if let Some(ev_json) = c.env_vars.as_ref() {
                                  if let Ok(ev_map) = serde_json::from_str::<std::collections::HashMap<String, String>>(ev_json) {
                                      for (k, v) in ev_map { env_prefix.push_str(&format!("{}=\"{}\" ", k, v)); }
                                  }
                              }

                              extra = c.extra_args.clone().unwrap_or_default();

                              if p_type == "PC (Windows)" || rom_path.starts_with("epic://") {
                                  env_prefix.push_str("UMU_LOG=1 ");
                                  
                                  if let Some(v) = c.umu_proton_version.as_ref().filter(|s| !s.trim().is_empty()) { 
                                      env_prefix.push_str(&format!("PROTONPATH=\"{}\" ", v)); 
                                      if rom_path.starts_with("epic://") && !wrapper_cmd.contains("umu-run") {
                                          wrapper_cmd.push_str("umu-run ");
                                      }
                                  }
                                  if let Some(s) = c.umu_store.as_ref().filter(|s| !s.trim().is_empty()) { env_prefix.push_str(&format!("UMU_STORE=\"{}\" ", s)); }
                                  if let Some(p) = c.wine_prefix.as_ref().filter(|s| !s.trim().is_empty()) { env_prefix.push_str(&format!("WINEPREFIX=\"{}\" ", p)); }
                                  
                                  if let Some(uid) = c.umu_id.as_ref().filter(|s| !s.trim().is_empty()) { 
                                      env_prefix.push_str(&format!("GAMEID=\"{}\" ", uid)); 
                                  } else if rom_path.starts_with("epic://") {
                                      let app_id = rom_path.split('/').last().unwrap_or_default();
                                      if !app_id.is_empty() {
                                          env_prefix.push_str(&format!("GAMEID=\"{}\" ", app_id));
                                      }
                                  }

                                  if let Some(v) = c.proton_verb.as_ref().filter(|s| !s.trim().is_empty()) { env_prefix.push_str(&format!("PROTON_VERB=\"{}\" ", v)); }

                                  if c.disable_fixes.unwrap_or(false) { env_prefix.push_str("PROTONFIXES_DISABLE=1 "); }
                                  if c.no_runtime.unwrap_or(false) { env_prefix.push_str("UMU_NO_RUNTIME=1 "); }

                                  if let Some(l) = &c.log_level {
                                      match l.as_str() {
                                          "None" => env_prefix = env_prefix.replace("UMU_LOG=1 ", ""),
                                          "Debug" => { env_prefix = env_prefix.replace("UMU_LOG=1 ", ""); env_prefix.push_str("UMU_LOG=debug "); },
                                          _ => {} 
                                      }
                                  }
                              }

                          } else {
                              // --- NO LOCAL CONFIG: FALLBACK TO DEFAULTS ---
                              
                              let use_mangohud = platform_defaults.as_ref().and_then(|d| d["use_mangohud"].as_bool()).unwrap_or(false);
                              if use_mangohud { env_prefix.push_str("MANGOHUD=1 "); }

                              let use_gs = platform_defaults.as_ref().and_then(|d| d["use_gamescope"].as_bool()).unwrap_or(false);
                              let gs_args = platform_defaults.as_ref().and_then(|d| d["gamescope_args"].as_str().map(|s| s.to_string()));
                              
                              let wrapper = platform_defaults.as_ref().and_then(|d| d["wrapper"].as_str().map(|s| s.to_string()));

                              if let Some(w) = wrapper.filter(|s| !s.trim().is_empty()) { wrapper_cmd.push_str(&format!("{} ", w.trim())); }
                              
                              if use_gs {
                                  wrapper_cmd.push_str(&format!("gamescope {} -- ", gs_args.as_deref().unwrap_or("").trim()));
                              }

                              extra = platform_defaults.as_ref().and_then(|d| d["extra_args"].as_str().map(|s| s.to_string())).unwrap_or_default();

                              if p_type == "PC (Windows)" || rom_path.starts_with("epic://") {
                                  env_prefix.push_str("UMU_LOG=1 ");
                                  
                                  let proton = platform_defaults.as_ref().and_then(|d| d["umu_proton_version"].as_str().map(|s| s.to_string())).filter(|s| !s.trim().is_empty());
                                  if let Some(v) = proton { 
                                      env_prefix.push_str(&format!("PROTONPATH=\"{}\" ", v)); 
                                      if rom_path.starts_with("epic://") && !wrapper_cmd.contains("umu-run") {
                                          wrapper_cmd.push_str("umu-run ");
                                      }
                                  }

                                  let store = platform_defaults.as_ref().and_then(|d| d["umu_store"].as_str().map(|s| s.to_string())).filter(|s| !s.trim().is_empty());
                                  if let Some(s) = store { env_prefix.push_str(&format!("UMU_STORE=\"{}\" ", s)); }

                                  let prefix = platform_defaults.as_ref().and_then(|d| d["wine_prefix"].as_str().map(|s| s.to_string())).filter(|s| !s.trim().is_empty());
                                  if let Some(p) = prefix { env_prefix.push_str(&format!("WINEPREFIX=\"{}\" ", p)); }

                                  let umu_id = platform_defaults.as_ref().and_then(|d| d["umu_id"].as_str().map(|s| s.to_string())).filter(|s| !s.trim().is_empty());
                                  if let Some(uid) = umu_id { 
                                      env_prefix.push_str(&format!("GAMEID=\"{}\" ", uid)); 
                                  } else if rom_path.starts_with("epic://") {
                                      let app_id = rom_path.split('/').last().unwrap_or_default();
                                      if !app_id.is_empty() {
                                          env_prefix.push_str(&format!("GAMEID=\"{}\" ", app_id));
                                      }
                                  }

                                  let verb = platform_defaults.as_ref().and_then(|d| d["proton_verb"].as_str().map(|s| s.to_string())).filter(|s| !s.trim().is_empty());
                                  if let Some(v) = verb { env_prefix.push_str(&format!("PROTON_VERB=\"{}\" ", v)); }

                                  let disable_fixes = platform_defaults.as_ref().and_then(|d| d["disable_fixes"].as_bool()).unwrap_or(false);
                                  if disable_fixes { env_prefix.push_str("PROTONFIXES_DISABLE=1 "); }

                                  let no_runtime = platform_defaults.as_ref().and_then(|d| d["no_runtime"].as_bool()).unwrap_or(false);
                                  if no_runtime { env_prefix.push_str("UMU_NO_RUNTIME=1 "); }

                                  let log = platform_defaults.as_ref().and_then(|d| d["log_level"].as_str().map(|s| s.to_string()));
                                  if let Some(l) = log {
                                      match l.as_str() {
                                          "None" => env_prefix = env_prefix.replace("UMU_LOG=1 ", ""),
                                          "Debug" => { env_prefix = env_prefix.replace("UMU_LOG=1 ", ""); env_prefix.push_str("UMU_LOG=debug "); },
                                          _ => {} 
                                      }
                                  }
                              }
                          }
                  }

                  // 3. Command Template Construction
                  
                  if rom_path.starts_with("heroic://") || rom_path.starts_with("lutris:") || rom_path.ends_with(".desktop") || rom_path.starts_with("steam://") || rom_path.starts_with("flatpak://") || rom_path.ends_with(".command") {
                      // These still bypass wrappers and use %ROM%
                      command_template = "%ROM%".to_string();
                  } else if rom_path.starts_with("epic://") {
                      command_template = "%ROM%".to_string();
                      // Keep env_prefix and wrapper_cmd to pass to Launcher::launch via options
                  } else if is_pc {
                      let base_cmd = if command_template.is_empty() || command_template == "%ROM%" { "%ROM%" } else { &command_template };
                      
                      if p_type == "PC (Windows)" {
                          let runner = if base_cmd.contains("umu-run") { "" } else { "umu-run " };
                          command_template = format!("{} {}{}{} {}", env_prefix.trim(), wrapper_cmd, runner, base_cmd, extra).trim().to_string();
                      } else {
                          // PC (Linux)
                          command_template = format!("{} {} {} {}", env_prefix.trim(), wrapper_cmd, base_cmd, extra).trim().to_string();
                      }

                      // Envs and wrappers are already integrated into command_template for regular PC Games
                      env_prefix.clear();
                      wrapper_cmd.clear();
                  }

                  // Wrap with scripts if present
                  let mut final_cmd = command_template.clone();
                  if let Some(pre) = pre_script {
                      final_cmd = format!("{} && {}", pre, final_cmd);
                  }
                  if let Some(post) = post_script {
                      final_cmd = format!("{} ; {}", final_cmd, post);
                  }
                  command_template = final_cmd;

                  // Clean up double spaces if not empty
                  if !command_template.is_empty() {
                      // Avoid this breaking quoted strings by doing basic multi-space to single space
                      while command_template.contains("  ") {
                          command_template = command_template.replace("  ", " ");
                      }
                  }

                 if command_template.is_empty() {
                     log::error!("Launch failed: No command template or emulator defined for this platform.");
                     return;
                 }
                 
                 let env_vars_opt = if env_prefix.trim().is_empty() { None } else { Some(env_prefix.as_str()) };
                 let wrapper_opt = if wrapper_cmd.trim().is_empty() { None } else { Some(wrapper_cmd.as_str()) };

                 // ── Cloud Save: Pull before launch (blocking) ──────────────────────
                 // Only for Epic games with auto-sync enabled
                 if rom_path.starts_with("epic://") && cloud_saves_enabled && cloud_save_auto_sync {
                     use crate::core::legendary::{LegendaryWrapper, SyncDirection};
                     let app_name = rom_path.trim_start_matches("epic://launch/");
                     let save_path_resolved: Option<std::path::PathBuf> =
                         cloud_save_path_opt.as_deref().map(|p| std::path::PathBuf::from(p))
                         .or_else(|| {
                             let prefix = cloud_wine_prefix_opt.as_deref()?;
                             LegendaryWrapper::resolve_cloud_save_path(app_name, prefix).ok()?
                         });
                     if let Some(sp) = save_path_resolved {
                         log::debug!("[cloud-save] Pulling saves before launch for {}", app_name);
                         match LegendaryWrapper::sync_saves(app_name, &sp, SyncDirection::Pull, false) {
                             Ok(res) => log::debug!("[cloud-save] Pull complete: {:?}", res),
                             Err(e) => log::warn!("[cloud-save] Pull failed (launching anyway): {}", e),
                         }
                     }
                 }

                 let mut eos_overlay_enabled = false;
                 if rom_path.starts_with("epic://") {
                     let _app_name = rom_path.trim_start_matches("epic://launch/");
                     let prefix = self.get_wine_prefix(&rom_id_clone);
                     eos_overlay_enabled = crate::core::legendary::LegendaryWrapper::is_eos_overlay_enabled(prefix.as_deref());
                 }

                 // Launch process
                 match Launcher::launch(&command_template, &rom_path, working_dir.as_deref(), env_vars_opt, wrapper_opt, eos_overlay_enabled) {
                     Ok(mut child) => {
                         log::debug!("Launched successfully.");
                         
                         let pgid = child.id() as i32;
                         log::info!("[Launcher] Game {} started with PGID {}", rom_id_clone, pgid);
                         
                         // Immediate metadata update for last_played
                         if let Ok(db) = DbManager::open(&path_str) {
                             if let Ok(Some(mut meta)) = db.get_metadata(&rom_id_clone) {
                                 meta.last_played = Some(
                                     std::time::SystemTime::now()
                                     .duration_since(std::time::UNIX_EPOCH)
                                     .unwrap_or_default()
                                     .as_secs() as i64
                                 );
                                  let _ = db.insert_metadata(&meta);
                                  self.update_row_by_id(&rom_id_clone);
                                   let should_refresh = *self.current_recent_only.borrow() || *self.current_sort_method.borrow() == "Recent" || *self.current_sort_method.borrow() == "LastPlayed";
                                   if should_refresh {
                                       self.refresh();
                                   }
                                  self.calculateStats();
                             }
                         }

                          // Steam URIs launch via a background service, so tracking the child process
                          // usually just tracks the persistent client. We skip timing for these.
                          // Flatpaks are tracked directly.
                          if rom_path.starts_with("steam://") || rom_path.starts_with("heroic://") || rom_path.starts_with("lutris:") {
                              log::info!("Steam game detected. Skipping timing thread but updating usage stats immediately.");
                              if let Ok(db) = DbManager::open(&path_str) {
                                  if let Ok(Some(mut meta)) = db.get_metadata(&rom_id_clone) {
                                      meta.play_count += 1;
                                      meta.last_played = Some(
                                          std::time::SystemTime::now()
                                          .duration_since(std::time::UNIX_EPOCH)
                                          .unwrap_or_default()
                                          .as_secs() as i64
                                      );
                                       let _ = db.insert_metadata(&meta);
                                       self.update_row_by_id(&rom_id_clone);
                                       self.calculateStats();
                                       self.playtimeUpdated(rom_id_clone.clone().into());
                                       
                                       // If in Recent mode, refresh to update list order
                                       let should_refresh = *self.current_recent_only.borrow() || *self.current_sort_method.borrow() == "Recent" || *self.current_sort_method.borrow() == "LastPlayed";
                                       if should_refresh {
                                           self.refresh();
                                       }
                                   }
                               }
                               return;
                           }

                         self.running_games.borrow_mut().insert(rom_id_clone.clone(), pgid);
                         self.runningGamesChanged();


                         
                         // Spawn a thread to wait for the process and track time
                         let db_path_thread = path_str.clone();
                         let rom_id_thread = rom_id_clone.clone();
                         let tx = self.tx.borrow().clone();
                         // Clone cloud save info for the exit thread
                         let cloud_app_name: Option<String> = if rom_path.starts_with("epic://") {
                             Some(rom_path.trim_start_matches("epic://launch/").to_string())
                         } else { None };
                         let cloud_save_path_for_push: Option<std::path::PathBuf> = if cloud_saves_enabled && cloud_save_auto_sync {
                             cloud_save_path_opt.as_deref().map(|p| std::path::PathBuf::from(p))
                             .or_else(|| {
                                 use crate::core::legendary::LegendaryWrapper;
                                 let app_name = cloud_app_name.as_deref()?;
                                 let prefix = cloud_wine_prefix_opt.as_deref()?;
                                 LegendaryWrapper::resolve_cloud_save_path(app_name, prefix).ok()?
                             })
                         } else { None };
                         
                         let rom_path_thread = rom_path.clone();
                         let tx_thread = self.tx.borrow().clone();
                         
                         std::thread::spawn(move || {                             let start_time = std::time::SystemTime::now();
                             
                             // 1. Wait for the primary child to exit (reaps the process)
                             let exit_status = child.wait();
                             log::debug!("[Launcher] Primary child for {} exited with {:?}", rom_id_thread, exit_status);

                             // 2. Use process group polling to wait for grandchildren (umu-run, wine, etc.)
                             #[cfg(unix)]
                             {
                                 log::debug!("[Launcher] Polling PGID {} for grandchildren...", pgid);
                                 loop {
                                     // Use system kill command to check group status without libc
                                     let status = std::process::Command::new("kill")
                                         .arg("-0")
                                         .arg(format!("-{}", pgid))
                                         .status();
                                     
                                     if status.map(|s| !s.success()).unwrap_or(true) {
                                         log::debug!("[Launcher] PGID {} group cleared", pgid);
                                         break;
                                     }
                                     std::thread::sleep(std::time::Duration::from_millis(1000));
                                 }
                             }

                             // ── Cloud Save: Push after game exits ─────────────
                              if let (Some(app_name), Some(sp)) = (&cloud_app_name, &cloud_save_path_for_push) {
                                  use crate::core::legendary::{LegendaryWrapper, SyncDirection};
                                   log::debug!("[cloud-save] Pushing saves after exit for {}", app_name);
                                   match LegendaryWrapper::sync_saves(app_name, sp, SyncDirection::Push, false) {
                                       Ok(res) => log::debug!("[cloud-save] Push complete for {}: {:?}", app_name, res),
                                       Err(e) => log::warn!("[cloud-save] Push failed: {}", e),
                                   }
                              }

                             let end_time = std::time::SystemTime::now();
                             let duration = end_time.duration_since(start_time).unwrap_or_default().as_secs() as i64;

                             if let Some(ref t) = tx_thread {
                                 let _ = t.send(AsyncResponse::GameStopped(rom_id_thread.clone(), duration));
                             }

                             log::debug!("Game exited. Duration: {} seconds", duration);
                             
                             // Update DB
                             if let Ok(db) = DbManager::open(&db_path_thread) {

                                 // We need to fetch existing metadata first to increment
                                 if let Ok(Some(mut meta)) = db.get_metadata(&rom_id_thread) {
                                     meta.play_count += 1;
                                     meta.total_play_time += duration;
                                     meta.last_played = Some(
                                         std::time::SystemTime::now()
                                         .duration_since(std::time::UNIX_EPOCH)
                                         .unwrap_or_default()
                                         .as_secs() as i64
                                     );
                                     
                                     // Assume ExoDOS games (.command) are installed after first launch
                                     if rom_path_thread.ends_with(".command") {
                                         let is_first_install = !meta.is_installed;
                                         meta.is_installed = true;
                                         let _ = db.get_connection().execute("UPDATE roms SET is_installed = 1 WHERE id = ?1", [&rom_id_thread]);

                                         // Rescan for resources (Extras, Magazines, etc.)
                                         if let Some(game_dir) = std::path::Path::new(&rom_path_thread).parent() {
                                             let resources = crate::core::exodos::ExoDosManager::scan_resources(game_dir, &rom_id_thread);
                                             for resource in resources {
                                                 if let Ok(false) = db.resource_exists(&rom_id_thread, &resource.url) {
                                                     let _ = db.insert_resource(&resource);
                                                 }
                                             }
                                         }

                                         // Also check for a manual PDF in the global Manuals folder on first install
                                         if is_first_install {
                                             let exodos_path = crate::bridge::settings::AppSettings::get_exodos_path();
                                             if !exodos_path.is_empty() {
                                                 if let Some(stem) = std::path::Path::new(&rom_path_thread).file_stem().and_then(|s| s.to_str()) {
                                                     let pdf = std::path::Path::new(&exodos_path).join("Manuals").join("MS-DOS").join(format!("{}.pdf", stem));
                                                     if pdf.exists() {
                                                         let url = pdf.to_string_lossy().to_string();
                                                         if let Ok(false) = db.resource_exists(&rom_id_thread, &url) {
                                                              log::info!("[ExoDOS] Found global manual for {}: {:?}", rom_id_thread, pdf);
                                                              let resource = crate::core::models::GameResource {
                                                                  id: uuid::Uuid::new_v4().to_string(),
                                                                  rom_id: rom_id_thread.clone(),
                                                                  type_: "manual".to_string(),
                                                                  url,
                                                                  label: Some(stem.to_string()),
                                                              };
                                                              let _ = db.insert_resource(&resource);
                                                         }
                                                     }
                                                 }
                                             }
                                         }
                                     }


                                     
                                     if let Err(e) = db.insert_metadata(&meta) {
                                         log::error!("Failed to update playtime metadata: {}", e);
                                     } else {
                                         log::debug!("Playtime updated for {}.", rom_id_thread);
                                     }
                                 } else {
                                     // Create new metadata if missing (unlikely if game exists)

                                     let now = std::time::SystemTime::now()
                                         .duration_since(std::time::UNIX_EPOCH)
                                         .unwrap_or_default()
                                         .as_secs() as i64;
                                         
                                     let meta = crate::core::models::GameMetadata {
                                         rom_id: rom_id_thread.clone(),
                                         title: None, description: None, rating: None, release_date: None, developer: None, 
                                         publisher: None, genre: None, tags: None, region: None, 
                                         is_favorite: false,
                                         play_count: 1, 
                                         last_played: Some(now), 
                                         total_play_time: duration,
                                         achievement_count: None,
                                         achievement_unlocked: None,
                                         ra_game_id: None,
                                         ra_recent_badges: None,
                                           is_installed: if rom_id_thread.starts_with("steam-") {
                                               crate::core::store::StoreManager::get_local_steam_appids().contains(&rom_id_thread.replace("steam-", ""))
                                           } else {
                                               true
                                           },
                                         cloud_saves_supported: false,
                                         resources: None,
                                     };
                                     if let Err(e) = db.insert_metadata(&meta) {
                                         log::error!("Failed to insert new metadata: {}", e);
                                     }
                                 }
                                 
                                 // Signal UI to update stats
                                 if let Some(sender) = tx {
                                     let _ = sender.send(AsyncResponse::PlaytimeUpdated(rom_id_thread));
                                 }
                             }
                         });
                     },
                     Err(e) => log::error!("Launch failed: {}", e),
                 }
             } else {
                 log::error!("Could not find launch info for ROM: {}", rom_id);
             }
        }
    }

    #[allow(non_snake_case)]
    fn launchResource(&mut self, rom_id: String, url: String) {
        log::debug!("Requesting launch for resource: {} (ROM: {})", url, rom_id);
        
        let path_str = self.db_path.borrow().clone();
        if path_str.is_empty() { return; }

        let is_alternate_launcher = (url.ends_with(".command") || url.ends_with(".sh"))
            && url.contains("Alternate Launcher");
        let is_script = url.ends_with(".command") || url.ends_with(".sh");

        if is_alternate_launcher {
            // Alternate Launcher: launch + track playtime
            use crate::core::launcher::Launcher;
            let tx = self.tx.borrow().as_ref().map(|s| s.clone());

            match Launcher::launch("%ROM%", &url, None, None, None, false) {
                Ok(mut child) => {
                    let rom_id_thread = rom_id.clone();
                    let db_path_thread = path_str.clone();
                    std::thread::spawn(move || {
                        let start_time = std::time::SystemTime::now();
                        let _ = child.wait();
                        let end_time = std::time::SystemTime::now();
                        let duration = end_time.duration_since(start_time).unwrap_or_default().as_secs() as i64;

                        log::debug!("Alternate launcher exited for {}. Duration: {} seconds", rom_id_thread, duration);

                        if let Ok(db) = DbManager::open(&db_path_thread) {
                            if let Ok(Some(mut meta)) = db.get_metadata(&rom_id_thread) {
                                meta.play_count += 1;
                                meta.total_play_time += duration;
                                meta.last_played = Some(
                                    std::time::SystemTime::now()
                                    .duration_since(std::time::UNIX_EPOCH)
                                    .unwrap_or_default()
                                    .as_secs() as i64
                                );
                                if let Err(e) = db.insert_metadata(&meta) {
                                    log::error!("Failed to update playtime after alternate launch: {}", e);
                                }
                            }
                        }

                        if let Some(sender) = tx {
                            let _ = sender.send(AsyncResponse::PlaytimeUpdated(rom_id_thread));
                        }
                    });
                },
                Err(e) => log::error!("Failed to launch script resource: {}", e),
            }
        } else if is_script {
            // Other .command/.sh resources (magazines, extras): launch the same way but no playtime tracking
            use crate::core::launcher::Launcher;
            match Launcher::launch("%ROM%", &url, None, None, None, false) {
                Ok(mut child) => {
                    std::thread::spawn(move || { let _ = child.wait(); });
                },
                Err(e) => log::error!("Failed to launch script resource: {}", e),
            }
        } else {
            // For other resources (PDFs, images etc.), just open with system default
            get_runtime().spawn(async move {
                // Only prepend file:// for bare paths; preserve http://, https://, etc. as-is
                let clean_url = if url.contains("://") { url } else { format!("file://{}", url) };
                
                #[cfg(target_os = "linux")]
                { let _ = std::process::Command::new("xdg-open").arg(&clean_url).spawn(); }
                #[cfg(target_os = "windows")]
                { let _ = std::process::Command::new("cmd").args(["/c", "start", &clean_url]).spawn(); }
                #[cfg(target_os = "macos")]
                { let _ = std::process::Command::new("open").arg(&clean_url).spawn(); }
            });
        }
    }

    #[allow(non_snake_case)]
    fn uninstallSteamGame(&mut self, rom_id: String) {
        // Only valid for Steam games
        if !rom_id.starts_with("steam-") {
            log::warn!("[uninstallSteamGame] Called on non-Steam game: {}", rom_id);
            return;
        }

        let appid = rom_id.replacen("steam-", "", 1);
        let steam_uri = format!("steam://uninstall/{}", appid);

        // Open the Steam uninstall dialog
        log::info!("[uninstallSteamGame] Opening Steam uninstall URI: {}", steam_uri);
        let _ = Command::new("xdg-open").arg(&steam_uri).spawn();

        // Immediately mark as uninstalled in the DB
        let db_path = self.db_path.borrow().clone();
        if let Ok(db) = DbManager::open(&db_path) {
            let result = db.get_connection().execute(
                "UPDATE metadata SET is_installed = 0 WHERE rom_id = ?1",
                rusqlite::params![rom_id],
            );
            match result {
                Ok(rows) => log::debug!("[uninstallSteamGame] Marked uninstalled in DB ({} rows)", rows),
                Err(e) => log::error!("[uninstallSteamGame] DB update failed: {}", e),
            }
        }

        // Update the in-memory roms vec so the cloud icon shows immediately
        {
            let mut roms = self.roms.borrow_mut();
            if let Some(rom) = roms.iter_mut().find(|r| r.id == rom_id) {
                rom.is_installed = Some(false);
            }
        }

        // Notify QML that this row changed
        self.gameDataChanged(rom_id.clone().into());

        // Trigger a full refresh so all views update consistently
        self.refresh();
    }

    #[allow(non_snake_case)]
    #[allow(non_snake_case)]
    fn getPcConfig(&mut self, rom_id: String) -> QString {
        let db_path = self.db_path.borrow().clone();
        if db_path.is_empty() { return QString::from("{}"); }
        if let Ok(db) = DbManager::open(&db_path) {
            match db.get_pc_config(&rom_id) {
                Ok(Some(config)) => {
                    return QString::from(serde_json::to_string(&config).unwrap_or("{}".to_string()));
                },
                _ => return QString::from("{}"),
            }
        }
        QString::from("{}")
    }

    #[allow(non_snake_case)]
    fn getPlatformPcDefaults(&mut self, rom_id: String) -> QString {
        let db_path = self.db_path.borrow().clone();
        if db_path.is_empty() { return QString::from("{}"); }
        if let Ok(db) = DbManager::open(&db_path) {
            if let Ok(Some((_, _, _, platform_pc_defaults))) = db.get_launch_info(&rom_id) {
                return QString::from(platform_pc_defaults.unwrap_or("{}".to_string()));
            }
        }
        QString::from("{}")
    }

    #[allow(non_snake_case)]
    fn savePcConfig(&mut self, json: String) {
        let db_path = self.db_path.borrow().clone();
        if db_path.is_empty() { return; }
        if let Ok(db) = DbManager::open(&db_path) {
            if let Ok(config) = serde_json::from_str::<crate::core::models::PcConfig>(&json) {
                let _ = db.insert_pc_config(&config);
            }
        }
    }

    /// Resolves the full host-side save path for an Epic game using legendary info.
    /// `wine_prefix` is passed directly from QML so unsaved prefix values work.
    /// Returns the resolved path string, or a string starting with "error:" on failure.
    #[allow(non_snake_case)]
    fn resolveCloudSavePath(&mut self, rom_id: String, wine_prefix: String) -> QString {
        use crate::core::legendary::LegendaryWrapper;

        // Strip "legendary-" prefix to get app_name
        let app_name = match rom_id.strip_prefix("legendary-") {
            Some(a) => a.to_string(),
            None => return QString::from("error:not an epic game"),
        };

        let prefix = wine_prefix.trim().to_string();
        if prefix.is_empty() {
            return QString::from("error:no wine prefix set — configure it in the Proton/UMU section first");
        }

        match LegendaryWrapper::resolve_cloud_save_path(
            &app_name,
            &prefix,
        ) {
            Ok(Some(path)) => QString::from(path.to_string_lossy().as_ref()),
            Ok(None) => QString::from("error:game does not support cloud saves"),
            Err(e) => QString::from(format!("error:{}", e).as_str()),
        }
    }

    /// Runs legendary sync-saves for an Epic game in a background thread.
    /// `direction` should be "pull", "push", or "both".
    /// Emits `cloudSaveSyncFinished(rom_id, success, message)` when done.
    #[allow(non_snake_case)]
    fn syncCloudSaves(&mut self, rom_id: String, direction: String, force: bool) {
        use crate::core::legendary::{LegendaryWrapper, SyncDirection};

        let app_name = match rom_id.strip_prefix("legendary-") {
            Some(a) => a.to_string(),
            None => {
                self.cloudSaveSyncFinished(
                    rom_id.clone().into(),
                    false,
                    "error:not an epic game".into(),
                );
                return;
            }
        };

        let db_path = self.db_path.borrow().clone();

        // Fetch prefix and save path from DB
        let (prefix_opt, existing_save_path) = if let Ok(db) = DbManager::open(&db_path) {
            let config = db.get_pc_config(&rom_id).ok().flatten();
            (
                config.as_ref().and_then(|c| c.wine_prefix.clone()).filter(|s| !s.trim().is_empty()),
                config.and_then(|c| c.cloud_save_path).filter(|s| !s.trim().is_empty()),
            )
        } else {
            (None, None)
        };

        let sync_dir = match direction.to_lowercase().as_str() {
            "pull" => SyncDirection::Pull,
            "push" => SyncDirection::Push,
            _ => SyncDirection::Both,
        };

        let tx = self.tx.borrow().clone();
        let rom_id_clone = rom_id.clone();

        std::thread::spawn(move || {
            // Resolve the save path: prefer previously stored path, then auto-resolve
            let save_path = if let Some(p) = existing_save_path {
                std::path::PathBuf::from(p)
            } else if let Some(prefix) = prefix_opt {
                match LegendaryWrapper::resolve_cloud_save_path(&app_name, &prefix) {
                    Ok(Some(p)) => p,
                    Ok(None) => {
                        if let Some(tx) = tx {
                            let _ = tx.send(AsyncResponse::CloudSaveSyncFinished(
                                rom_id_clone,
                                false,
                                "Game does not support cloud saves".to_string(),
                            ));
                        }
                        return;
                    }
                    Err(e) => {
                        if let Some(tx) = tx {
                            let _ = tx.send(AsyncResponse::CloudSaveSyncFinished(
                                rom_id_clone,
                                false,
                                format!("Failed to resolve save path: {}", e),
                            ));
                        }
                        return;
                    }
                }
            } else {
                if let Some(tx) = tx {
                    let _ = tx.send(AsyncResponse::CloudSaveSyncFinished(
                        rom_id_clone,
                        false,
                        "No wine prefix configured".to_string(),
                    ));
                }
                return;
            };

            match LegendaryWrapper::sync_saves(&app_name, &save_path, sync_dir, force) {
                Ok(res) => {
                    if let Some(tx) = tx {
                        let mut msg = String::from("Sync complete");
                        
                        if res.up_to_date && res.downloaded == 0 && res.uploaded == 0 {
                            msg = "Sync complete — Already up-to-date".to_string();
                        } else {
                            let mut parts = Vec::new();
                            if res.downloaded > 0 {
                                parts.push(format!("pulled {} file{}", res.downloaded, if res.downloaded == 1 { "" } else { "s" }));
                            }
                            if res.uploaded > 0 {
                                parts.push(format!("pushed {} file{}", res.uploaded, if res.uploaded == 1 { "" } else { "s" }));
                            }
                            
                            if !parts.is_empty() {
                                msg = format!("Sync complete — {}", parts.join(", "));
                            } else if res.up_to_date {
                                msg = "Sync complete — Already up-to-date".to_string();
                            }
                        }

                        log::debug!("[cloud-save] Sync result for {}: {:?} -> Message: {}", rom_id_clone, res, msg);

                        let _ = tx.send(AsyncResponse::CloudSaveSyncFinished(
                            rom_id_clone,
                            true,
                            msg,
                        ));
                    }
                }
                Err(e) => {
                    if let Some(tx) = tx {
                        let _ = tx.send(AsyncResponse::CloudSaveSyncFinished(
                            rom_id_clone,
                            false,
                            format!("Sync failed: {}", e),
                        ));
                    }
                }
            }
        });
    }
    #[allow(non_snake_case)]
    fn getRomPath(&mut self, rom_id: String) -> QString {
        let db_path = self.db_path.borrow().clone();
        if db_path.is_empty() { return QString::from(""); }
        if let Ok(db) = DbManager::open(&db_path) {
             let conn = db.get_connection();
             if let Ok(mut stmt) = conn.prepare("SELECT path FROM roms WHERE id = ?1") {
                 let path: String = stmt.query_row([&rom_id], |row| row.get(0)).unwrap_or_default();
                 return QString::from(path);
             }
        }
        QString::from("")
    }

    #[allow(non_snake_case)]
    fn updateRomPath(&mut self, rom_id: String, new_path: String) {
        if new_path.is_empty() { return; }
        let db_path = self.db_path.borrow().clone();
        if db_path.is_empty() { return; }
        if let Ok(db) = DbManager::open(&db_path) {
            let conn = db.get_connection();
            let filename = Path::new(&new_path).file_stem().and_then(|s| s.to_str()).unwrap_or("").to_string();
            let size = std::fs::metadata(&new_path).map(|m| m.len() as i64).unwrap_or(0);
            
            let _ = conn.execute(
                "UPDATE roms SET path = ?1, filename = ?2, file_size = ?3 WHERE id = ?4",
                rusqlite::params![new_path, filename, size, rom_id]
            );
            
            self.update_row_by_id(&rom_id);
        }
    }

    #[allow(non_snake_case)]
    fn getSystemStats(&mut self) {
        self.calculateStats();
    }

    #[allow(non_snake_case)]
    fn startBulkScrape(&mut self, 
        json_ids: String, 
        json_categories: String, 
        json_fields: String,
        min_delay_ms: i32, 
        max_delay_ms: i32, 
        ra_user: String, 
        ra_key: String, 
        metadata_provider: String, 
        prefer_ra: bool, 
        ollama_url: String, 
        ollama_model: String,
        gemini_key: String,
        openai_key: String,
        llm_provider: String
    ) {
        let ids: Vec<String> = serde_json::from_str(&json_ids).unwrap_or_default();
        let categories: Vec<String> = serde_json::from_str(&json_categories).unwrap_or_default();
        
        #[derive(serde::Deserialize, Clone, Copy)]
        struct FieldConfig {
            #[serde(default = "default_true")] title: bool,
            #[serde(default = "default_true")] description: bool,
            #[serde(default = "default_true")] dev_pub: bool,
            #[serde(default = "default_true")] genre_tags: bool,
            #[serde(default = "default_true")] date: bool,
            #[serde(default = "default_true")] rating: bool,
            #[serde(default = "default_true")] resources: bool,
            #[serde(default = "default_true")] asset_boxart: bool,
            #[serde(default = "default_true")] asset_icon: bool,
            #[serde(default = "default_true")] asset_logo: bool,
            #[serde(default = "default_true")] asset_screenshot: bool,
            #[serde(default = "default_true")] asset_background: bool,
        }
        fn default_true() -> bool { true }
        
        let field_config: FieldConfig = serde_json::from_str(&json_fields).unwrap_or(FieldConfig {
            title: true, description: true, dev_pub: true, genre_tags: true, 
            date: true, rating: true, resources: true, asset_boxart: true,
            asset_icon: true, asset_logo: true, asset_screenshot: true, asset_background: true
        });
        
        if ids.is_empty() { return; }
        
        log::info!("[BulkScrape] Request. Items: {}, MetaProvider: {}, RA_Priority: {}, Cats: {}", ids.len(), metadata_provider, prefer_ra, json_categories);
        
        // Prepare job data (must happen on main thread to access self.roms)
        struct JobData {
            id: String,
            title: String,
            platform_name: String,
            platform_type: String,
            path: String,
        }
        
        let mut jobs = Vec::new();
        {
            let roms = self.roms.borrow();
            for id in &ids {
                if let Some(rom) = roms.iter().find(|r| r.id == *id) {
                     jobs.push(JobData {
                         id: rom.id.clone(),
                         title: rom.title.as_ref().unwrap_or(&rom.filename).clone(),
                         platform_name: rom.platform_name.as_deref().unwrap_or("").to_string(),
                         platform_type: rom.platform_type.as_deref().unwrap_or("").to_string(),
                         path: rom.path.clone(),
                     });
                }
            }
        }
        
        let total_jobs = jobs.len() as f32;
        if total_jobs == 0.0 { return; }

        log::info!("[BulkScrape] Starting for {} items. Min: {}ms, Max: {}ms", total_jobs, min_delay_ms, max_delay_ms);
        
        // Reset State
        *self.bulk_is_scraping.borrow_mut() = true;
        *self.bulk_is_paused.borrow_mut() = false;
        *self.bulk_progress_val.borrow_mut() = 0.0;
        *self.bulk_status_msg.borrow_mut() = "Initializing...".to_string();
        
        self.bulkScraping = true;
        self.bulkPaused = false;
        self.bulkProgress = 0.0;
        self.bulkStatus = "Initializing...".into();
        
        self.bulkScrapingChanged();
        self.bulkPausedChanged();
        self.bulkProgressChanged();
        self.bulkStatusChanged();
        
        // Thread Communication
        let cancel_flag = self.bulk_cancel_flag.clone();
        let pause_flag = self.bulk_pause_flag.clone();
        let pause_notify = self.bulk_pause_notify.clone();
        
        // Reset flags
        cancel_flag.store(false, Ordering::SeqCst);
        pause_flag.store(false, Ordering::SeqCst);
        
        let client = self.get_scraper_client();
        let tx = match self.tx.borrow().as_ref() {
            Some(t) => t.clone(),
            None => return,
        };
        
        let ra_user_clone = ra_user.clone();
        let ra_key_clone = ra_key.clone();
        let db_path_clone = self.db_path.borrow().clone();
        let provider_name = metadata_provider.clone();
        let _o_url = ollama_url.clone();
        let o_url = ollama_url.clone();
        let o_model = ollama_model.clone();
        let g_key = gemini_key.clone();
        let oa_key = openai_key.clone();
        let l_prov = llm_provider.clone();

        // Spawn Background Task
        get_runtime().spawn(async move {
            let metadata_enabled = categories.contains(&"Metadata".to_string());
            let ra_enabled = categories.contains(&"RetroAchievements".to_string()) && !ra_user_clone.is_empty() && !ra_key_clone.is_empty();
            let steam_enabled = categories.contains(&"SteamAchievements".to_string());
            let (steam_id, steam_key) = if steam_enabled {
                crate::bridge::settings::AppSettings::get_steam_credentials()
            } else {
                (String::new(), String::new())
            };
            let steam_enabled = steam_enabled && !steam_id.is_empty() && !steam_key.is_empty();
            
            log::debug!("[BulkScrape] Worker Start. Meta: {}, RA: {}, Steam: {}, Priority: {}", 
                metadata_enabled, ra_enabled, steam_enabled, if prefer_ra { "RA" } else { "Meta" });
            
            let provider = ScraperManager::get_provider(&provider_name, client.clone(), o_url, o_model, g_key, oa_key, l_prov);
            
            for (index, job) in jobs.iter().enumerate() {
                // Check Cancellation
                if cancel_flag.load(Ordering::SeqCst) {
                    log::info!("[BulkScrape] Cancelled.");
                    break;
                }
                
                // Check Paused
                if pause_flag.load(Ordering::SeqCst) {
                    let _ = tx.send(AsyncResponse::BulkProgress(
                        index as f32 / total_jobs, 
                        "Paused".to_string()
                    ));
                    
                    // Wait until notified
                    log::info!("[BulkScrape] Paused... waiting.");
                    pause_notify.notified().await;
                    log::info!("[BulkScrape] Resumed.");
                }
                
                // Update Status
                let _ = tx.send(AsyncResponse::BulkProgress(
                    index as f32 / total_jobs, 
                    format!("Processing: {}", job.title)
                ));

                // Helper to perform metadata scrape for current job
                let do_metadata = async {
                    if !metadata_enabled { return; }
                    
                    log::debug!("[BulkScrape] Running Metadata for {}", job.title);
                    let _ = tx.send(AsyncResponse::BulkProgress(
                index as f32 / total_jobs, 
                        format!("Scraping Metadata: {}", job.title)
                    ));

                    let title = job.title.clone();
                    let query_title = {
                        let mut t = title.to_lowercase();
                        // Handle ", the" pattern for search
                        if t.ends_with(", the") {
                            t = format!("the {}", &t[..t.len() - 5].trim());
                        }
                        // Replace trademark/etc symbols and hyphens with spaces to avoid word merging
                        t = t.replace("™", " ").replace("®", " ").replace("©", " ").replace("-", " ");
                        // Clean edges and non-alphanumeric (except spaces)
                        let re_clean = regex::Regex::new(r"[^a-z0-9 ]").unwrap();
                        t = re_clean.replace_all(&t, " ").to_string();
                        // Standardize whitespace
                        t = t.split_whitespace().collect::<Vec<_>>().join(" ");
                        if t.is_empty() { title.clone() } else { t }
                    };
        

                    // Platform Detection
                    let platform_str = if !job.platform_type.is_empty() { 
                        &job.platform_type 
                    } else if !job.platform_name.is_empty() { 
                        &job.platform_name 
                    } else { 
                        "" 
                    };
                    let platform_opt = if platform_str.is_empty() { None } else { Some(platform_str) };

                    // Get target platform ID for better matching if it's IGDB
                    let target_p_id = if provider_name == "IGDB" {
                        crate::core::scraper::igdb::IGDBProvider::map_platform_id_static(platform_str)
                    } else {
                        None
                    };

                    match provider.search(&query_title, platform_opt).await {
                        Ok(results) => {
                            if results.is_empty() {
                                log::warn!("[BulkScrape] Search returned 0 results for '{}'", title);
                            }

                            let mut best_match: Option<ScraperSearchResult> = None;
                            let norm_t2 = GameListModel::normalize_title(&title);
                            for res in results {
                                let norm_t1 = GameListModel::normalize_title(&res.title);
                                let exact = norm_t1 == norm_t2;
                                let contains = norm_t1.contains(&norm_t2) || norm_t2.contains(&norm_t1);
                                
                                if (exact || contains) && GameListModel::is_platform_match(
                                    platform_str, 
                                    &res.platform, 
                                    target_p_id, 
                                    res.platform_ids.as_deref()
                                ) {
                                    best_match = Some(res);
                                    break;
                                }
                            }
                            
                            if let Some(res) = best_match {
                                // Try cached metadata only for LLM/Ollama providers to save costs/time,
                                // but for standard scrapers like IGDB we always want full fetch_details (ratings, etc)
                                let use_cache = if let Some(_) = &res.metadata {
                                    provider_name.contains("Ollama") || provider_name.contains("LLM")
                                } else {
                                    false
                                };

                                let meta_result = if use_cache {
                                    log::debug!("[BulkScrape] Using cached metadata for {}", job.title);
                                    Ok(res.metadata.unwrap())
                                } else {
                                    provider.fetch_details(&res.id).await
                                };

                                if let Ok(m) = meta_result {
                                    let db_p = db_path_clone.clone();
                                    let r_id = job.id.clone();
                                    let _ = tokio::task::spawn_blocking(move || {
                                        if let Ok(db) = DbManager::open(&db_p) {
                                            let mut final_meta = crate::core::models::GameMetadata {
                                                rom_id: r_id.clone(),
                                                title: if m.title.is_empty() { None } else { Some(m.title.clone()) },
                                                description: if m.description.is_empty() { None } else { Some(m.description.clone()) },
                                                rating: m.rating,
                                                release_date: m.release_year.map(|y| y.to_string()),
                                                developer: if m.developer.is_empty() { None } else { Some(m.developer.clone()) },
                                                publisher: if m.publisher.is_empty() { None } else { Some(m.publisher.clone()) },
                                                genre: if m.genre.is_empty() { None } else { Some(m.genre.clone()) },
                                                tags: None,
                                                region: if m.region.is_empty() { None } else { Some(m.region.clone()) },
                                                is_favorite: false,
                                                play_count: 0,
                                                last_played: None,
                                                total_play_time: 0,
                                                achievement_count: None,
                                                achievement_unlocked: None,
                                                ra_game_id: None,
                                                ra_recent_badges: None,
                                                is_installed: if r_id.starts_with("steam-") {
                                                    crate::core::store::StoreManager::get_local_steam_appids().contains(&r_id.replace("steam-", ""))
                                                } else if r_id.starts_with("legendary-") {
                                                    false
                                                } else {
                                                    true
                                                },
                                                cloud_saves_supported: false,
                                                resources: None,
                                            };
                                            
                                            if let Ok(existing) = db.get_metadata(&r_id) {
                                                if let Some(ex) = existing {
                                                    final_meta.play_count = ex.play_count;
                                                    final_meta.last_played = ex.last_played;
                                                    final_meta.total_play_time = ex.total_play_time;
                                                    final_meta.is_favorite = ex.is_favorite;
                                                    final_meta.achievement_count = ex.achievement_count;
                                                    final_meta.achievement_unlocked = ex.achievement_unlocked;
                                                    final_meta.ra_game_id = ex.ra_game_id;
                                                    final_meta.is_installed = ex.is_installed; // PRESERVE STATUS
                                                    
                                                    // FIELD: Title
                                                    if field_config.title {
                                                        if final_meta.title.is_none() { final_meta.title = ex.title.clone(); }
                                                    } else {
                                                        final_meta.title = ex.title.clone();
                                                    }
                                                    
                                                    // FIELD: Description
                                                    if field_config.description {
                                                        if final_meta.description.is_none() { final_meta.description = ex.description.clone(); }
                                                    } else {
                                                        final_meta.description = ex.description.clone();
                                                    }
                                                    
                                                    // FIELD: Rating
                                                    if field_config.rating {
                                                        if final_meta.rating.is_none() { final_meta.rating = ex.rating; }
                                                    } else {
                                                        final_meta.rating = ex.rating;
                                                    }

                                                    // FIELD: Date
                                                    if field_config.date {
                                                        if final_meta.release_date.is_none() { final_meta.release_date = ex.release_date.clone(); }
                                                    } else {
                                                        final_meta.release_date = ex.release_date.clone();
                                                    }

                                                    // FIELD: Dev / Pub
                                                    if field_config.dev_pub {
                                                        if final_meta.developer.is_none() { final_meta.developer = ex.developer.clone(); }
                                                        if final_meta.publisher.is_none() { final_meta.publisher = ex.publisher.clone(); }
                                                    } else {
                                                        final_meta.developer = ex.developer.clone();
                                                        final_meta.publisher = ex.publisher.clone();
                                                    }

                                                    // FIELD: Genre / Tags
                                                    if field_config.genre_tags {
                                                        if final_meta.genre.is_none() { final_meta.genre = ex.genre.clone(); }
                                                        if final_meta.tags.is_none() { final_meta.tags = ex.tags.clone(); }
                                                        if final_meta.region.is_none() { final_meta.region = ex.region.clone(); }
                                                    } else {
                                                        final_meta.genre = ex.genre.clone();
                                                        final_meta.tags = ex.tags.clone();
                                                        final_meta.region = ex.region.clone();
                                                    }
                                                }
                                                let _ = db.insert_metadata(&final_meta);

                                                // Save Sidecar
                                                if let Ok(Some((platform_folder, filename))) = db.get_rom_path_info(&r_id) {
                                                    let rom_stem = Path::new(&filename).file_stem().and_then(|s| s.to_str()).unwrap_or(&filename);
                                                    let _ = MetadataManager::save_sidecar(&platform_folder, rom_stem, &final_meta);
                                                }
                                                                                                // Save Resources (Filtered)
                                                 if field_config.resources {
                                                     for r in &m.resources {
                                                         if let Ok(exists) = db.resource_exists(&r_id, &r.url) {
                                                             if !exists {
                                                                  let res = crate::core::models::GameResource {
                                                                      id: uuid::Uuid::new_v4().to_string(),
                                                                      rom_id: r_id.clone(),
                                                                      type_: r.type_.clone(),
                                                                      url: r.url.clone(),
                                                                      label: Some(r.label.clone()),
                                                                 };
                                                                 let _ = db.insert_resource(&res);
                                                             }
                                                         }
                                                     }
                                                 }
                                            }
                                        }
                                    }).await;
                                    // Removed: let _ = tx.send(AsyncResponse::BulkGameSaved(job.id.clone()));
                                    // Moving this to end of loop as BulkItemFinished

                                    // Asset Downloads
                                    let has_any_asset_checked = field_config.asset_boxart || field_config.asset_icon || field_config.asset_logo || field_config.asset_screenshot || field_config.asset_background;
                                    if has_any_asset_checked {
                                        let mut filtered_assets = std::collections::HashMap::new();
                                        if !m.assets.is_empty() {
                                            for (k, v) in &m.assets {
                                                let k_lower = k.to_lowercase();
                                                let mut keep = false;
                                                
                                                if field_config.asset_boxart && (k_lower.contains("boxart") || k_lower.contains("cover") || k_lower.contains("capsule") || k_lower.contains("poster") || k_lower.contains("box - front")) {
                                                    keep = true;
                                                } else if field_config.asset_icon && k_lower.contains("icon") {
                                                    keep = true;
                                                } else if field_config.asset_logo && (k_lower.contains("logo") || k_lower.contains("clearlogo")) {
                                                    keep = true;
                                                } else if field_config.asset_screenshot && (k_lower.contains("screenshot") || k_lower.contains("snap")) {
                                                    keep = true;
                                                } else if field_config.asset_background && (k_lower.contains("background") || k_lower.contains("fanart") || k_lower.contains("hero") || k_lower.contains("artwork")) {
                                                    keep = true;
                                                }
                                                
                                                if keep {
                                                    filtered_assets.insert(k.clone(), v.clone());
                                                }
                                            }
                                        }

                                        if !filtered_assets.is_empty() {
                                            let p_folder = if !job.platform_type.is_empty() { 
                                                &job.platform_type 
                                            } else { 
                                                &job.platform_name 
                                            };
                                            let r_stem = std::path::Path::new(&job.path)
                                                .file_stem()
                                                .and_then(|s| s.to_str())
                                                .unwrap_or(&job.path)
                                                .to_string();

                                            download_game_assets(
                                                client.clone(),
                                                tx.clone(),
                                                job.id.clone(),
                                                db_path_clone.clone(),
                                                p_folder.to_string(),
                                                r_stem,
                                                filtered_assets,
                                            ).await;
                                        }
                                    }
                                }
                            } else {
                                log::info!("[BulkScrape] Results found but no match for '{}' (Platform: '{}')", title, job.platform_name);
                            }
                        },
                        Err(e) => {
                            log::error!("[BulkScrape] Search failed for '{}': {}", title, e);
                        }
                    }
                    
                    let delay = rand::thread_rng().gen_range(min_delay_ms..=max_delay_ms);
                    tokio::time::sleep(Duration::from_millis(delay as u64)).await;
                };

                // Helper to perform RA scrape for current job
                let do_ra = async {
                    if !ra_enabled { return; }
                    
                    log::debug!("[BulkScrape] Running RA for {}", job.title);
                    let _ = tx.send(AsyncResponse::BulkProgress(
                        index as f32 / total_jobs, 
                        format!("Checking Achievements: {}", job.title)
                    ));
                        
                    let r_user = ra_user_clone.clone();
                    let r_key = ra_key_clone.clone();
                    let j_id = job.id.clone();
                    let j_path = job.path.clone();
                    let j_title = job.title.clone();
                    let j_platform = job.platform_name.clone();

                    let res = tokio::task::spawn_blocking(move || {
                        let client = RetroAchievementsClient::new(r_user, r_key);
                        perform_ra_scrape(&client, &j_id, &j_path, &j_title, &j_platform)
                    }).await;

                    match res {
                        Ok(Ok(_)) => { /* Success */ },
                        Ok(Err(e)) => { log::error!("Bulk RA Scraping Error for {}: {}", job.title, e); },
                        Err(e) => { log::error!("Bulk RA Task Join Error: {}", e); }
                    }
                    
                    let delay = rand::thread_rng().gen_range(min_delay_ms..=max_delay_ms);
                    tokio::time::sleep(Duration::from_millis(delay as u64)).await;
                };

                // Helper to perform Steam scrape for current job
                let do_steam = async {
                    if !steam_enabled || !job.id.starts_with("steam-") { return; }
                    
                    log::debug!("[BulkScrape] Running Steam achievements for {}", job.title);
                    let _ = tx.send(AsyncResponse::BulkProgress(
                        index as f32 / total_jobs, 
                        format!("Checking Steam Achievements: {}", job.title)
                    ));
                    
                    let app_id = job.id.replace("steam-", "");
                    let s_id = steam_id.clone();
                    let s_key = steam_key.clone();
                    let j_id = job.id.clone();
                    let db_p = db_path_clone.clone();

                    let _res = tokio::task::spawn_blocking(move || {
                        if let Ok(results) = crate::core::store::StoreManager::fetch_steam_game_achievements(&app_id, &s_id, &s_key) {
                            if let Ok(db) = DbManager::open(&db_p) {
                                let unlocked = results["unlocked_count"].as_i64().unwrap_or(0) as i32;
                                let total = results["total_count"].as_i64().unwrap_or(0) as i32;
                                let _ = db.update_achievements(&j_id, total, unlocked, None);
                            }
                        }
                    }).await;
                    
                    let delay = rand::thread_rng().gen_range(min_delay_ms..=max_delay_ms);
                    tokio::time::sleep(Duration::from_millis(delay as u64)).await;
                };

                // Execute based on priority
                if prefer_ra {
                    do_ra.await;
                    do_metadata.await;
                } else {
                    do_metadata.await;
                    do_ra.await;
                }
                do_steam.await;

                // ALWAYS signal that this item is finished processing
                let _ = tx.send(AsyncResponse::BulkItemFinished(job.id.clone()));
            }
            
            let _ = tx.send(AsyncResponse::BulkFinished(
                format!("Finished. Checked {} files.", total_jobs)
            ));
        });
    }

    #[allow(non_snake_case)]
    fn stopBulkScrape(&mut self) {
        log::info!("[BulkScrape] Stopping...");
        self.bulk_cancel_flag.store(true, Ordering::SeqCst);
        // Wake up if paused
        self.bulk_pause_notify.notify_waiters();
    }

    #[allow(non_snake_case)]
    fn pauseBulkScrape(&mut self) {
        self.bulk_pause_flag.store(true, Ordering::SeqCst);
        *self.bulk_is_paused.borrow_mut() = true;
        self.bulkPaused = true;
        self.bulkPausedChanged();
    }

    #[allow(non_snake_case)]
    fn resumeBulkScrape(&mut self) {
        self.bulk_pause_flag.store(false, Ordering::SeqCst);
        self.bulk_pause_notify.notify_waiters();
        *self.bulk_is_paused.borrow_mut() = false;
        self.bulkPaused = false;
        self.bulkPausedChanged();
    }

    #[allow(non_snake_case)]
    fn deleteGame(&mut self, rom_id: String, ignore: bool, uninstall_flatpak: bool, delete_data: bool, delete_assets: bool) {
        log::info!("Deleting game: {} (ignore={}, uninstall_flatpak={}, delete_data={}, delete_assets={})", rom_id, ignore, uninstall_flatpak, delete_data, delete_assets);
        let db_path = self.db_path.borrow().clone();
        if db_path.is_empty() { return; }

        if let Ok(db) = DbManager::open(&db_path) {
            // Get path and platform_id before deleting
            let mut game_path = String::new();
            let mut platform_id = String::new();

            let conn = db.get_connection();
            if let Ok(mut stmt) = conn.prepare("SELECT platform_id, path FROM roms WHERE id = ?1") {
                if let Ok(mut rows) = stmt.query([&rom_id]) {
                    if let Ok(Some(row)) = rows.next() {
                        platform_id = row.get(0).unwrap_or_default();
                        game_path = row.get(1).unwrap_or_default();
                    }
                }
            }

            if ignore && !platform_id.is_empty() && !game_path.is_empty() {
                let _ = db.insert_ignore_entry(&platform_id, &game_path);
            }

            if delete_assets {
                 if let Ok(Some((platform_folder, filename))) = db.get_rom_path_info(&rom_id) {
                     // 1. Try standard stem (Game.nes -> Game) - Correct for most ROMs
                     let rom_stem_std = Path::new(&filename).file_stem().and_then(|s| s.to_str()).unwrap_or(&filename);
                     let _ = MetadataManager::delete_assets(&platform_folder, rom_stem_std);
                     
                     // 2. Try full filename (org.app.Id -> org.app.Id) - Correct for Flatpaks and some others
                     if rom_stem_std != filename {
                         let _ = MetadataManager::delete_assets(&platform_folder, &filename);
                     }
                 }
            }

            if uninstall_flatpak && game_path.starts_with("flatpak://") {
                let flatpak_id = game_path.replace("flatpak://", "");
                if !flatpak_id.is_empty() {
                    log::info!("Uninstalling flatpak: {}", flatpak_id);
                    let mut cmd = Command::new("flatpak");
                    cmd.arg("uninstall").arg("-y").arg("--noninteractive");
                    if delete_data {
                        cmd.arg("--delete-data");
                    }
                    cmd.arg(&flatpak_id);

                    match cmd.spawn() {
                        Ok(mut child) => {
                            // We don't want to block the whole UI for this, so we just let it run
                            // but we could also wait in a separate thread if we wanted to notify completion
                            std::thread::spawn(move || {
                                let _ : Result<std::process::ExitStatus, std::io::Error> = child.wait();
                                log::info!("Flatpak uninstall finished for: {}", flatpak_id);
                            });
                        },
                        Err(e) => log::error!("Failed to start flatpak uninstall for {}: {}", flatpak_id, e),
                    }
                }
            }

            let _ = db.delete_rom(&rom_id);
        }
        self.refresh();
    }

    fn deleteGamesBulk(&mut self, rom_ids_json: String, ignore: bool, delete_assets: bool) {
        let rom_ids: Vec<String> = serde_json::from_str(&rom_ids_json).unwrap_or_default();
        if rom_ids.is_empty() { return; }

        let db_path = self.db_path.borrow().clone();
        if db_path.is_empty() { return; }

        if let Ok(db) = DbManager::open(&db_path) {
            for rom_id in rom_ids {
                // Get path and platform_id before deleting
                let mut game_path = String::new();
                let mut platform_id = String::new();

                let conn = db.get_connection();
                if let Ok(mut stmt) = conn.prepare("SELECT platform_id, path FROM roms WHERE id = ?1") {
                    if let Ok(mut rows) = stmt.query([&rom_id]) {
                        if let Ok(Some(row)) = rows.next() {
                            platform_id = row.get(0).unwrap_or_default();
                            game_path = row.get(1).unwrap_or_default();
                        }
                    }
                }

                if ignore && !platform_id.is_empty() && !game_path.is_empty() {
                    let _ = db.insert_ignore_entry(&platform_id, &game_path);
                }

                if delete_assets {
                     if let Ok(Some((platform_folder, filename))) = db.get_rom_path_info(&rom_id) {
                         let rom_stem = Path::new(&filename).file_stem().and_then(|s| s.to_str()).unwrap_or(&filename);
                         let _ = MetadataManager::delete_assets(&platform_folder, rom_stem);
                     }
                }

                let _ = db.delete_rom(&rom_id);
            }
        }
        self.refresh();
    }

    #[allow(non_snake_case)]
    fn getIgnoreList(&mut self) -> String {
        let db_path = self.db_path.borrow().clone();
        if db_path.is_empty() { return "[]".to_string(); }

        if let Ok(db) = DbManager::open(&db_path) {
            if let Ok(list) = db.get_all_ignored() {
                let mut results = Vec::new();
                for (pid, path) in list {
                    let mut map = serde_json::Map::new();
                    map.insert("platform_id".to_string(), serde_json::Value::String(pid));
                    map.insert("path".to_string(), serde_json::Value::String(path));
                    results.push(serde_json::Value::Object(map));
                }
                return serde_json::Value::Array(results).to_string();
            }
        }
        "[]".to_string()
    }

    #[allow(non_snake_case)]
    fn removeFromIgnoreList(&mut self, platform_id: String, path: String) {
        let db_path = self.db_path.borrow().clone();
        if db_path.is_empty() { return; }

        if let Ok(db) = DbManager::open(&db_path) {
            let _ = db.remove_ignore_entry(&platform_id, &path);
        }
        // No need to refresh main view list, but we might want to refresh settings if it's open.
        // QML will usually re-call getIgnoreList if we trigger a change.
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
    pub fn searchOnline(&mut self, query: String, platform: String, provider: String, ollama_url: String, ollama_model: String, gemini_key: String, openai_key: String, llm_provider: String) {
        if provider == "Ollama + Web Search" || provider == "LLM API" {
            log::debug!("[Rust] searchOnline: '{}' ({}) via {} [Ollama: {} model: {}]", query, platform, provider, ollama_url, ollama_model);
        } else {
            log::debug!("[Rust] searchOnline: '{}' ({}) via {}", query, platform, provider);
        }
        let client = self.get_scraper_client();
        let tx = match self.tx.borrow().as_ref() {
            Some(t) => t.clone(),
            None => return,
        };
        
        let platform_opt = if platform.trim().is_empty() { None } else { Some(platform.clone()) };
        
        get_runtime().spawn(async move {
            let scraper = ScraperManager::get_provider(&provider, client, ollama_url, ollama_model, gemini_key, openai_key, llm_provider);
            
            // Pass platform_opt.as_deref() which is Option<&str>
            match scraper.search(&query, platform_opt.as_deref()).await {
                Ok(results) => {
                    let json = serde_json::to_string(&results).unwrap_or_default();
                    let _ = tx.send(AsyncResponse::SearchFinished(json));
                },
                Err(e) => log::error!("Search error: {}", e),
            }
        });
    }

    #[allow(non_snake_case)]
    fn globalSearch(&mut self, query: String) -> String {
        let db_path = self.db_path.borrow().clone();
        if db_path.is_empty() { 
            return "[]".to_string(); 
        }

        let mut results = Vec::new();
        let pattern = format!("%{}%", query);

        if let Ok(db) = DbManager::open(&db_path) {
            let conn = db.get_connection();

            // 1. Search Platforms (Collections)
            let sql_platforms = "SELECT id, name, platform_type, icon FROM platforms WHERE name LIKE ?1 LIMIT 5";
            if let Ok(mut stmt) = conn.prepare(sql_platforms) {
                if let Ok(rows) = stmt.query_map([&pattern], |row| {
                    Ok(serde_json::json!({
                        "id": row.get::<_, String>(0)?,
                        "title": row.get::<_, String>(1)?,
                        "platform": "Collection",
                        "type": row.get::<_, Option<String>>(2)?.unwrap_or_default(),
                        "icon": resolve_asset_path(&row.get::<_, Option<String>>(3)?.unwrap_or_default()),
                        "boxart": "",
                        "result_type": "collection"
                    }))
                }) {
                    for row in rows.flatten() { results.push(row); }
                }
            }

            // 2. Search Playlists
            let sql_playlists = "SELECT id, name FROM playlists WHERE name LIKE ?1 LIMIT 5";
            if let Ok(mut stmt) = conn.prepare(sql_playlists) {
                if let Ok(rows) = stmt.query_map([&pattern], |row| {
                    Ok(serde_json::json!({
                        "id": row.get::<_, String>(0)?,
                        "title": row.get::<_, String>(1)?,
                        "platform": "Playlist",
                        "type": "",
                        "icon": "",
                        "boxart": "",
                        "result_type": "playlist"
                    }))
                }) {
                    for row in rows.flatten() { results.push(row); }
                }
            }

            // 3. Search Games (Enhanced)
            let sql_games = "SELECT r.id, COALESCE(m.title, r.filename), p.name, p.platform_type, r.icon_path, r.boxart_path 
                             FROM roms r
                             LEFT JOIN metadata m ON r.id = m.rom_id
                             JOIN platforms p ON r.platform_id = p.id
                             WHERE m.title LIKE ?1 
                                OR r.filename LIKE ?1 
                                OR m.developer LIKE ?1 
                                OR m.publisher LIKE ?1 
                                OR m.genre LIKE ?1 
                                OR m.tags LIKE ?1
                             LIMIT 30";
            
            if let Ok(mut stmt) = conn.prepare(sql_games) {
                if let Ok(rows) = stmt.query_map([&pattern], |row| {
                    Ok(serde_json::json!({
                        "id": row.get::<_, String>(0)?,
                        "title": row.get::<_, String>(1)?,
                        "platform": row.get::<_, String>(2)?,
                        "type": row.get::<_, String>(3)?,
                        "icon": resolve_asset_path(&row.get::<_, Option<String>>(4)?.unwrap_or_default()),
                        "boxart": resolve_asset_path(&row.get::<_, Option<String>>(5)?.unwrap_or_default()),
                        "result_type": "game"
                    }))
                }) {
                    for row in rows.flatten() { results.push(row); }
                }
            }
        }
        
        serde_json::to_string(&results).unwrap_or_else(|_| "[]".to_string())
    }

    #[allow(non_snake_case)]
    fn fetchOnlineMetadata(&mut self, source_id: String, provider: String, ollama_url: String, ollama_model: String, gemini_key: String, openai_key: String, llm_provider: String) {
        let client = self.get_scraper_client();
        let tx = match self.tx.borrow().as_ref() {
            Some(t) => t.clone(),
            None => return,
        };
        
        get_runtime().spawn(async move {
            let scraper = ScraperManager::get_provider(&provider, client, ollama_url, ollama_model, gemini_key, openai_key, llm_provider);
            
            match scraper.fetch_details(&source_id).await {
                Ok(metadata) => {
                    let json = serde_json::to_string(&metadata).unwrap_or_default();
                    log::debug!("[GameModel] fetchOnlineMetadata success.");
                    let _ = tx.send(AsyncResponse::FetchFinished(json));
                },
                Err(e) => {
                    log::error!("Fetch error: {}", e);
                    let _ = tx.send(AsyncResponse::FetchFailed(e.to_string()));
                },
            }
        });
    }

    #[allow(non_snake_case)]
    fn searchGameImages(&mut self, query: String) {
        let client = self.get_scraper_client();
        let tx = match self.tx.borrow().as_ref() {
            Some(t) => t.clone(),
            None => return,
        };
        
        get_runtime().spawn(async move {
            let provider = SearchEngineProvider::new(client);
            match provider.search(&query, None).await {
                Ok(results) => {
                    let json = serde_json::to_string(&results).unwrap_or_default();
                    let _ = tx.send(AsyncResponse::ImagesSearchFinished(json));
                },
                Err(e) => {
                    log::error!("Image search failed: {}", e);
                    let _ = tx.send(AsyncResponse::ImagesSearchFinished("[]".to_string()));
                }
            }
        });
    }

    #[allow(non_snake_case)]
    fn downloadAsset(&mut self, rom_id: String, asset_type: String, url: String) {
        let client = self.get_scraper_client();
        let tx = match self.tx.borrow().as_ref() {
            Some(t) => t.clone(),
            None => return,
        };
        
        // 1. Resolve Path Info Synchronously
        let mut platform_folder = String::from("Unknown");
        let mut rom_stem = String::from("unknown");
        let mut platform_id = String::new();
        
        {
            let roms = self.roms.borrow();
            if let Some(rom) = roms.iter().find(|r| r.id == rom_id) {
                platform_id = rom.platform_id.clone();
                
                rom_stem = std::path::Path::new(&rom.filename)
                    .file_stem()
                    .and_then(|s| s.to_str())
                    .unwrap_or(&rom.filename)
                    .to_string();
            }
        }

        // Resolving Folder Name from DB (Matches RetroAchievements/Scanner logic)
        // Order: Platform Type -> Platform Name -> ID (Fallback)
        if !platform_id.is_empty() {
             let db_path_str = self.db_path.borrow().clone();
             if let Ok(db) = DbManager::open(&db_path_str) {
                  // Try to resolve canonical folder
                   if let Ok(Some(plat)) = db.get_platform(&platform_id) {
                       let p_type = plat.platform_type.unwrap_or_default();
                       let p_name = plat.name;
                       
                       let folder = if !p_type.is_empty() { p_type } else { p_name };
                       
                       // Match RA Logic: replace slashes with dashes
                       platform_folder = folder.replace("/", "-").replace("\\", "-");
                   }
             }
        }

        // Sanitize platform folder name (Legacy hygiene, RA logic acts before this but good to double check)
        let safe_platform = platform_folder.trim().to_string(); 
 
            
        // Map asset_type to folder name

        let media_type = match asset_type.as_str() {
             "Box - Front" | "boxart" => "Box - Front",
             "Box - Back" | "boxart_back" => "Box - Back",
             "Screenshot" | "Screenshot - Gameplay" | "screenshot" => "Screenshot",
             "Banner" | "banner" => "Banner",
             "Clear Logo" | "logo" | "clear_logo" | "Logo" => "Logo",
             "Background" | "Fanart - Background" | "background" | "fanart" => "Background",
             "Icon" | "icon" => "Icon",
             "Grid" => "Grid",
             "Hero" => "Hero",
             "Box - 3D" => "Box - 3D",
             "Box - Spine" => "Box - Spine",
             "Disc" => "Disc",
             "Cartridge" => "Cartridge",
             "Title Screen" => "Title Screen",
             "Marquee" => "Marquee",
             _ => asset_type.as_str(), // Fallback: Use provided type
        }.to_string();

        let db_path = self.db_path.borrow().clone();

        get_runtime().spawn(async move {

            match client.get_bytes(&url).await {
                Ok(bytes) => {
                    // Determine extension
                    let ext = if url.to_lowercase().ends_with(".png") { "png" }
                    else if url.to_lowercase().ends_with(".jpg") || url.to_lowercase().ends_with(".jpeg") { "jpg" }
                    else if url.to_lowercase().ends_with(".webp") { "webp" }
                    else { "png" }; // Default
                    
                    // Extract original filename or fallback to rom_stem if opaque
                    let url_filename = url.split('/').last().unwrap_or("image").split('?').next().unwrap_or("image");
                    let mut safe_filename = url_filename.chars()
                        .filter(|c| c.is_alphanumeric() || *c == '.' || *c == '-' || *c == '_')
                        .collect::<String>();
                        
                    if safe_filename.is_empty() || safe_filename == "." {
                         safe_filename = format!("{}.{}", rom_stem, ext);
                    }
                    if !safe_filename.contains('.') {
                        safe_filename = format!("{}.{}", safe_filename, ext);
                    }

                    let data_dir = crate::core::paths::get_data_dir();
                    let dest_dir = data_dir.join("Images").join(&safe_platform).join(&rom_stem).join(&media_type);
                    
                    if !dest_dir.exists() {
                         let _ = std::fs::create_dir_all(&dest_dir);
                    }
                    
                    let final_path = dest_dir.join(&safe_filename);
                    let final_path_str = final_path.to_string_lossy().to_string();

                    if final_path.exists() {

                         // Return success with the existing path
                         let _ = tx.send(AsyncResponse::AssetDownloadFinished(asset_type, final_path_str.clone()));
                         
                         // Ensure DB has it (idempotent)
                         if let Ok(db) = DbManager::open(&db_path) {
                            let _ = db.insert_asset(&rom_id, &media_type, &final_path_str);
                         }
                         return; 
                    }
                    
                    if let Ok(_) = std::fs::write(&final_path, &bytes) {
                        
                         // Update DB immediately
                        if let Ok(db) = DbManager::open(&db_path) {
                            let _ = db.insert_asset(&rom_id, &media_type, &final_path_str);
                            
                            // fallback: if we downloaded Grid and boxart_path is empty, update it
                            if media_type == "Grid" {
                                let conn = db.get_connection();
                                let boxart_empty: bool = conn.query_row(
                                    "SELECT (boxart_path IS NULL OR boxart_path = '') FROM roms WHERE id = ?1",
                                    [&rom_id],
                                    |row| row.get(0)
                                ).unwrap_or(true);

                                if boxart_empty {
                                    let _ = conn.execute("UPDATE roms SET boxart_path = ?1 WHERE id = ?2", [&final_path_str, &rom_id]);
                                }
                            }
                        }

                        // Pass back the original category (asset_type) 
                        let _ = tx.send(AsyncResponse::AssetDownloadFinished(asset_type, final_path_str.clone()));
                        
                        // Signal game data change to force row refresh without triggering RA check
                        // Using GameDataChanged instead of PlaytimeUpdated to avoid unwanted RA overlay on asset download
                        let _ = tx.send(AsyncResponse::GameDataChanged(rom_id));
                        
                    } else {
                        log::error!("Failed to write file");
                        let _ = tx.send(AsyncResponse::AssetDownloadFailed(asset_type, "Failed to write file".to_string()));
                    }
                },
                Err(e) => {
                    log::error!("Download failed: {}", e);
                    let _ = tx.send(AsyncResponse::AssetDownloadFailed(asset_type, e.to_string()));
                },
            }
        });
    }

    #[allow(non_snake_case)]
    fn checkAsyncResponses(&mut self) {
        // Collect responses first to drop the immutable borrow of self.rx
        let mut responses = Vec::new();
        {
            let rx = self.rx.borrow();
            if let Some(ref rx) = *rx {
                while let Ok(response) = rx.try_recv() {
                    responses.push(response);
                }
            }
        } // rx borrow ends here

        for response in responses {
            match response {
                AsyncResponse::SearchFinished(json) => self.searchFinished(json),
                AsyncResponse::ImagesSearchFinished(json) => self.imagesSearchFinished(json),
                AsyncResponse::FetchFinished(json) => self.fetchFinished(json.into()),
                AsyncResponse::FetchFailed(msg) => self.fetchFailed(msg.into()),
                AsyncResponse::AssetDownloadFinished(cat, path) => self.assetDownloadFinished(cat.into(), path.into()),
            AsyncResponse::AssetDownloadFailed(cat, msg) => self.assetDownloadFailed(cat, msg),
                 AsyncResponse::PlaytimeUpdated(rom_id) => {
                      self.update_row_by_id(&rom_id);
                      self.calculateStats();
                      self.playtimeUpdated(rom_id.into());
                      
                      // Refresh list order if in Recent mode
                      let should_refresh = *self.current_recent_only.borrow() || *self.current_sort_method.borrow() == "Recent" || *self.current_sort_method.borrow() == "LastPlayed";
                      if should_refresh {
                          self.refresh();
                      }
                 }
                AsyncResponse::ImportProgress(p, status) => {
                    self.importProgress(p, status.into());
                },
                AsyncResponse::AssetDownloadProgress(msg) => {
                    self.assetDownloadProgress(msg.into());
                },
                AsyncResponse::ImportFinished(pid, ids) => {
                    let json_ids = serde_json::to_string(&ids).unwrap_or_else(|_| "[]".to_string());
                    self.importFinished(pid.into(), json_ids.into());
                    self.refresh();
                },
                AsyncResponse::AutoScrapeFinished(id, json) => {
                    self.update_row_by_id(&id);
                    self.autoScrapeFinished(id, json);
                },
                AsyncResponse::AutoScrapeFailed(id, msg) => self.autoScrapeFailed(id, msg),
                
                AsyncResponse::BulkProgress(p, s) => {
                    *self.bulk_progress_val.borrow_mut() = p;
                    *self.bulk_status_msg.borrow_mut() = s.clone();
                    self.bulkProgress = p;
                    self.bulkStatus = s.into();
                    self.bulkProgressChanged();
                    self.bulkStatusChanged();
                },
                
                AsyncResponse::BulkGameUpdate(id, json) => {
                    self.updateGameMetadata(id, json);
                },
                
                AsyncResponse::BulkItemFinished(id) => {
                    self.update_row_by_id(&id);
                    self.bulkItemFinished(id.into());
                },
                
                AsyncResponse::BulkFinished(msg) => {
                    // Update Status First
                    *self.bulk_status_msg.borrow_mut() = msg.clone();
                    self.bulkStatus = msg.into();
                    self.bulkStatusChanged();
                    
                    *self.bulk_is_scraping.borrow_mut() = false;
                    *self.bulk_is_paused.borrow_mut() = false;
                    self.bulkScraping = false;
                    self.bulkPaused = false;
                    self.bulkScrapingChanged();
                    self.bulkPausedChanged();

                    // Short sleep to ensure DB commits are visible to new thread?
                    std::thread::sleep(Duration::from_millis(500));
                    
                    self.refresh();
                },
                AsyncResponse::RefreshFinished(new_roms, rid, total_count, total_games, time_str, lp_game, lp_id) => {
                    if rid >= *self.last_refresh_id.borrow() {
                        self.begin_reset_model();
                        *self.roms.borrow_mut() = new_roms;
                        *self.total_library_count.borrow_mut() = total_count;
                        self.end_reset_model();
                        
                        // Emit stats signal directly from background calculation
                        self.statsUpdated(total_games, time_str.into(), lp_game.into(), lp_id.into(), total_count);

                        self.platformTypesChanged();
                        self.filterOptionsChanged();
                        self.loadingFinished();
                    }
                },
                AsyncResponse::GameDataChanged(rom_id) => {
                    // Refresh the row UI without triggering RA check
                    self.update_row_by_id(&rom_id);
                    self.gameDataChanged(rom_id.into());
                }
                AsyncResponse::CloudSaveSyncFinished(rom_id, success, message) => {
                    self.cloudSaveSyncFinished(rom_id.into(), success, message.into());
                }
                AsyncResponse::GameStopped(rom_id, duration) => {
                    log::info!("[Launcher] Game {} stopped after {}s", rom_id, duration);
                    self.running_games.borrow_mut().remove(&rom_id);
                    self.playtimeUpdated(rom_id.into());
                    self.runningGamesChanged();
                }
                AsyncResponse::EosOverlayEnabled(rom_id, enabled) => {
                    self.eosOverlayEnabledResult(rom_id.into(), enabled);
                }
            }
        }
    }

    #[allow(non_snake_case)]
    fn addGameResource(&mut self, rom_id: String, type_: String, url: String, label: String) {
        let db_path = self.db_path.borrow().clone();
        if db_path.is_empty() { return; }
        
        if let Ok(db) = DbManager::open(&db_path) {
            // Check if exists first
            let normalized_url = normalize_url(&url);
            if let Ok(existing_resources) = db.get_resources(&rom_id) {
                if existing_resources.iter().any(|r| normalize_url(&r.url) == normalized_url) {
                    log::warn!("Resource already exists (normalized): {} ({})", url, type_);
                    return;
                }
            }

            let res = GameResource {
                id: Uuid::new_v4().to_string(),
                rom_id,
                type_,
                url,
                label: if label.is_empty() { None } else { Some(label) },
            };
            let _ = db.insert_resource(&res);
        }
    }

    #[allow(non_snake_case)]
    fn removeGameResource(&mut self, resource_id: String) {
        let db_path = self.db_path.borrow().clone();
        if db_path.is_empty() { return; }
        
        if let Ok(db) = DbManager::open(&db_path) {
            let _ = db.delete_resource(&resource_id);
        }
    }

    #[allow(non_snake_case)]
    fn updateGameResource(&mut self, resource_id: String, type_: String, url: String, label: String) {
        let db_path = self.db_path.borrow().clone();
        if db_path.is_empty() { return; }
        
        if let Ok(db) = DbManager::open(&db_path) {
            let label_opt = if label.is_empty() { None } else { Some(label.as_str()) };
            let _ = db.update_resource(&resource_id, &type_, &url, label_opt);
        }
    }

    #[allow(non_snake_case)]
    fn refreshExoDosResources(&mut self, rom_id: String) {
        log::info!("[ExoDos] Manual refresh requested for rom_id: {}", rom_id);
        let db_path = self.db_path.borrow().clone();
        if db_path.is_empty() { return; }

        if let Ok(db) = DbManager::open(&db_path) {
            if let Ok(Some((rom_path, _, _, _))) = db.get_launch_info(&rom_id) {
                if rom_path.ends_with(".command") {
                    if let Some(game_dir) = Path::new(&rom_path).parent() {
                        let resources = crate::core::exodos::ExoDosManager::scan_resources(game_dir, &rom_id);
                        let mut added = 0;
                        for resource in resources {
                            if let Ok(false) = db.resource_exists(&rom_id, &resource.url) {
                                if let Ok(_) = db.insert_resource(&resource) {
                                    added += 1;
                                }
                            }
                        }

                        // Also check global manuals folder
                        let exodos_path = crate::bridge::settings::AppSettings::get_exodos_path();
                        if !exodos_path.is_empty() {
                            if let Some(stem) = Path::new(&rom_path).file_stem().and_then(|s| s.to_str()) {
                                let pdf = Path::new(&exodos_path).join("Manuals").join("MS-DOS").join(format!("{}.pdf", stem));
                                if pdf.exists() {
                                    let url = pdf.to_string_lossy().to_string();
                                    if let Ok(false) = db.resource_exists(&rom_id, &url) {
                                        let resource = crate::core::models::GameResource {
                                            id: uuid::Uuid::new_v4().to_string(),
                                            rom_id: rom_id.clone(),
                                            type_: "manual".to_string(),
                                            url,
                                            label: Some(stem.to_string()),
                                        };
                                        if let Ok(_) = db.insert_resource(&resource) {
                                            added += 1;
                                        }
                                    }
                                }
                            }
                        }

                        if added > 0 {
                            log::info!("[ExoDos] Added {} new resources for {}", added, rom_id);
                            self.update_row_by_id(&rom_id);
                            self.calculateStats();
                        }
                    }
                }
            }
        }
    }

    fn autoScrape(&mut self, rom_id: String) {
        let client = self.get_scraper_client();
        let tx = match self.tx.borrow().as_ref() {
            Some(t) => t.clone(),
            None => return,
        };

        // Get info locally
        let mut title = String::new();
        let mut platform_name = String::new();
        
        {
             let roms = self.roms.borrow();
             if let Some(rom) = roms.iter().find(|r| r.id == rom_id) {
                 title = rom.title.as_ref().unwrap_or(&rom.filename).clone();
                 // Prioritize platform_type (short name like NES) over platform_name (collection name)
                 platform_name = rom.platform_type.as_deref()
                     .filter(|s| !s.is_empty())
                     .or(rom.platform_name.as_deref())
                     .unwrap_or("")
                     .trim()
                     .to_string();
             }
        }
        
        if title.is_empty() {
             self.autoScrapeFailed(rom_id.clone(), "Game not found".to_string());
             return;
        }

        let query_title = {
            let mut t = title.to_lowercase();
            // Handle ", the" pattern for search
            if t.ends_with(", the") {
                t = format!("the {}", &t[..t.len() - 5].trim());
            }
            // Replace trademark/etc symbols and hyphens with spaces to avoid word merging
            t = t.replace("™", " ").replace("®", " ").replace("©", " ").replace("-", " ");
            // Clean non-alphanumeric (except spaces)
            let re_clean = regex::Regex::new(r"[^a-z0-9 ]").unwrap();
            t = re_clean.replace_all(&t, " ").to_string();
            // Standardize whitespace
            t = t.split_whitespace().collect::<Vec<_>>().join(" ");
            if t.is_empty() { title.clone() } else { t }
        };
        


        let settings_path = crate::core::paths::get_config_dir().join("settings.json");
        let mut provider_name = "IGDB".to_string();
        let mut ollama_url = String::new();
        let mut ollama_model = String::new();
        let mut gemini_key = String::new();
        let mut openai_key = String::new();
        let mut llm_provider = String::from("Gemini");

        if let Ok(content) = std::fs::read_to_string(&settings_path) {
            if let Ok(json) = serde_json::from_str::<serde_json::Value>(&content) {
                if let Some(s) = json["active_metadata_scraper"].as_str() {
                    if !s.is_empty() { provider_name = s.to_string(); }
                }
                if let Some(s) = json["ollama_url"].as_str() {
                    ollama_url = s.to_string();
                }
                if let Some(s) = json["ollama_model"].as_str() {
                    ollama_model = s.to_string();
                }
                if let Some(s) = json["gemini_api_key"].as_str() {
                    gemini_key = s.to_string();
                }
                if let Some(s) = json["openai_api_key"].as_str() {
                    openai_key = s.to_string();
                }
                if let Some(s) = json["llm_api_provider"].as_str() {
                    llm_provider = s.to_string();
                }
            }
        } else {
            // Default to IGDB if settings missing (matches shift+a legacy behavior)
            provider_name = "IGDB".to_string();
        }

        log::info!("[AutoScrape] Using scraper: {}", provider_name);

        get_runtime().spawn(async move {
            let provider = ScraperManager::get_provider(&provider_name, client.clone(), ollama_url, ollama_model, gemini_key, openai_key, llm_provider);
            // Search with platform
            let platform_opt = if platform_name.is_empty() { None } else { Some(platform_name.as_str()) };
            
            // Get target platform ID for better matching if it's IGDB
            let target_p_id = if provider_name == "IGDB" {
                crate::core::scraper::igdb::IGDBProvider::map_platform_id_static(&platform_name)
            } else {
                None
            };

            match provider.search(&query_title, platform_opt).await {
                Ok(results) => {
                    // Try to find a match
                    let mut matched_id = String::new();
                    let mut fallback_id = String::new();
                    let mut cached_metadata: Option<ScrapedMetadata> = None;
                    
                    let norm_t2 = GameListModel::normalize_title(&title);

                    for res in results {
                        let t1 = res.title.to_lowercase();
                        let t2 = title.to_lowercase();
                        let norm_t1 = GameListModel::normalize_title(&res.title);
                        
                        // 1. Exact Title Match (Case-Insensitive) gets priority
                        let exact_title = t1 == t2 || norm_t1 == norm_t2;
                        
                        // 2. Contains Match
                        let contains_title = norm_t1.contains(&norm_t2) || norm_t2.contains(&norm_t1);
                        

                        
                        if exact_title || contains_title {

                            
                            // Platform Match
                            if GameListModel::is_platform_match(
                                &platform_name, 
                                &res.platform, 
                                target_p_id, 
                                res.platform_ids.as_deref()
                            ) {
                                matched_id = res.id;
                                cached_metadata = res.metadata;
                                log::debug!("[AutoScrape] MATCH FOUND: {}", matched_id);
                                break;
                            } else {

                                // If platform doesn't match, but it's an "Add to collection" result, 
                                // we keep it as a fallback if it's an exact title match.
                                if res.can_add_to_collection && fallback_id.is_empty() && (exact_title || norm_t1.starts_with(&norm_t2)) {
                                    log::info!("[AutoScrape] Using as Fallback (Add to Collection + Title Match)");
                                    fallback_id = res.id;
                                    if cached_metadata.is_none() {
                                        cached_metadata = res.metadata;
                                    }
                                }
                            }
                        }
                    }

                    let final_id = if !matched_id.is_empty() { matched_id } else { fallback_id };
                    
                    if !final_id.is_empty() {
                        // If we already have synthesized metadata from the search (e.g. OllamaWeb), use it directly.
                        // However, for standard scrapers (IGDB, LaunchBox), we ALWAYS fetch_details 
                        // because search results usually lack screenshots/artworks which causes skipping!
                        if let Some(meta) = cached_metadata {
                            if provider_name.contains("Ollama") || provider_name.contains("LLM") {
                                log::info!("[AutoScrape] Using cached metadata for '{}' (LLM Provider)", final_id);
                                let json = serde_json::to_string(&meta).unwrap_or_default();
                                let _ = tx.send(AsyncResponse::AutoScrapeFinished(rom_id.clone(), json));
                                return;
                            }
                        }

                        // Otherwise Fetch
                        match provider.fetch_details(&final_id).await {
                            Ok(meta) => {
                                let json = serde_json::to_string(&meta).unwrap_or_default();
                                let _ = tx.send(AsyncResponse::AutoScrapeFinished(rom_id.clone(), json));
                            },
                            Err(e) => {
                                let _ = tx.send(AsyncResponse::AutoScrapeFailed(rom_id.clone(), format!("Fetch error: {}", e)));
                            }
                        }
                    } else {
                        log::info!("No strict match found for '{}' on '{}'", title, platform_name);
                        let _ = tx.send(AsyncResponse::AutoScrapeFailed(rom_id.clone(), "No matching system found".to_string()));
                    }
                },
                Err(e) => {
                     let _ = tx.send(AsyncResponse::AutoScrapeFailed(rom_id.clone(), format!("Search error: {}", e)));
                }
            }
        });
    }

    pub fn is_platform_match(local: &str, remote: &str, target_p_id: Option<i32>, remote_p_ids: Option<&[i32]>) -> bool {
        // 1. Check ID match if available (highest confidence)
        if let (Some(t_id), Some(r_ids)) = (target_p_id, remote_p_ids) {
            if r_ids.contains(&t_id) {
                return true;
            }
        }

        // Normalize both strings: lowercase and remove all non-alphanumeric characters
        let normalize = |s: &str| -> String {
            s.to_lowercase()
                .chars()
                .filter(|c| c.is_ascii_alphanumeric())
                .collect()
        };

        let l = normalize(local);
        let r = normalize(remote);
        
        if l == r { return true; }
        if l == "wikipedia" || r == "wikipedia" { return true; }
        
        // 2. Multi-platform remote string parsing
        // Some scrapers (IGDB, Launchbox) return comma-separated lists
        if remote.contains(',') || remote.contains('/') || remote.contains('|') {
            let separators = [',', '/', '|'];
            for part in remote.split(&separators[..]) {
                if GameListModel::is_platform_match(local, part.trim(), target_p_id, remote_p_ids) {
                    return true;
                }
            }
        }

        // 3. Strict containment: "Super Nintendo" in "Super Nintendo Entertainment System"
        if (l.len() > 3 && r.contains(&l)) || (r.len() > 3 && l.contains(&r)) { return true; }
        
        // 4. Common Aliases & Variations
        let aliases = vec![
            ("nes", "nintendoentertainmentsystem"),
            ("famicon", "nintendoentertainmentsystem"),
            ("snes", "supernintendoentertainmentsystem"),
            ("snes", "supernintendo"),
            ("supernintendo", "supernintendoentertainmentsystem"),
            ("n64", "nintendo64"),
            ("gba", "nintendogameboyadvance"),
            ("gameboyadvance", "nintendogameboyadvance"),
            ("gb", "nintendogameboy"),
            ("gameboy", "nintendogameboy"),
            ("genesis", "segagenesis"),
            ("megadrive", "segagenesis"),
            ("genesis", "megadrive"),
            ("genesis", "segamegadrive"),
            ("megadrive", "segamegadrive"),
            ("genesis", "segamegadrivegenesis"),
            ("megadrive", "segamegadrivegenesis"),
            ("psx", "playstation"),
            ("ps1", "playstation"),
            ("ps2", "playstation2"),
            ("ps3", "playstation3"),
            ("ps4", "playstation4"),
            ("pc", "windows"),
            ("pc", "dos"),
            ("pc", "linux"),
            ("pc", "steam"),
            ("pc", "heroic"),
            ("pc", "lutris"),
            ("linux", "windows"),
            ("steam", "windows"),
            ("heroic", "pc"),
            ("lutris", "pc"),
            ("heroic", "windows"),
            ("lutris", "windows"),
            ("heroic", "linux"),
            ("lutris", "linux"),
            ("steam", "pc"),
            ("mame", "arcade"),
            ("pce", "turbografx16"),
            ("engine", "turbografx16"),
            ("pce", "pceengine"),
            ("tg16", "turbografx16"),
            ("tg16", "pcengine"),
            ("segadreamcast", "dreamcast"),
            ("saturn", "segasaturn"),
            ("gamecube", "nintendogamecube"),
            ("wii", "nintendowii"),
            ("switch", "nintendoswitch"),
            // LLM Common Returns
            ("snes", "superfamicom"),
            ("megadrive", "genesis"),
            ("pc", "windows"),
            ("dos", "msdos"),
        ];
        
        for (a, b) in aliases {
        // a = alias/shorthand (e.g., "nes")
        // b = canonical-ish name (e.g., "nintendoentertainmentsystem")

        // 1. Both match the same alias or canonical name exactly
        if (l == a && r == a) || (l == b && r == b) { return true; }

        // 2. Cross-match: local is alias, remote is canonical (or vice versa)
        if (l == a && r == b) || (r == a && l == b) { return true; }
        
        // 3. Selective containment: 
        // We only allow 'contains' logic for the canonical name (b) to avoid 
        // short aliases like "nes" matching inside "genesis".
        if (l == a && r.contains(b)) || (r == a && l.contains(b)) { return true; }
        
        // 4. Double containment for full names (e.g. "nintendosuperfamicom" vs "supernintendo")
        if l.contains(b) && r.contains(b) { return true; }
    }
    
    false
}

    fn discover_assets_internal(&self, db: &DbManager, rom_id: &str, platform_folder: &str, rom_filename: &str) {
        let data_dir = crate::core::paths::get_data_dir();
        let rom_stem = Path::new(rom_filename).file_stem().and_then(|s| s.to_str()).unwrap_or(rom_filename);
        let sanitized_folder = platform_folder.replace("/", "-").replace("\\", "-");
        let assets_base_dir = data_dir.join("Images").join(sanitized_folder).join(rom_stem);

        if !assets_base_dir.exists() || !assets_base_dir.is_dir() {
            return;
        }

        let mut box_front_path = None;
        let mut grid_path = None;
        let mut icon_path = None;

        // Walk through type directories (e.g. Box - Front, Screenshot)
        if let Ok(entries) = std::fs::read_dir(assets_base_dir) {
            for entry in entries.flatten() {
                if let Ok(file_type) = entry.file_type() {
                    if file_type.is_dir() {
                        let asset_type = entry.file_name().to_string_lossy().to_string();
                        if let Ok(files) = std::fs::read_dir(entry.path()) {
                            for file in files.flatten() {
                                if let Ok(ft) = file.file_type() {
                                    if ft.is_file() || ft.is_symlink() {
                                        let path = file.path().to_string_lossy().to_string();
                                        let _ = db.insert_asset(rom_id, &asset_type, &path);

                                        // Auto-link primary assets
                                        if asset_type == "Box - Front" || asset_type == "boxart" || asset_type == "Steam Library Capsule" {
                                            box_front_path = Some(path.clone());
                                        } else if asset_type == "Grid" {
                                            grid_path = Some(path.clone());
                                        }

                                        if asset_type == "Icon" || asset_type == "icon" || asset_type == "Steam Icon" {
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

        // Update ROM table with found assets
        let final_boxart = box_front_path.or(grid_path);

        if final_boxart.is_some() || icon_path.is_some() {
             let conn = db.get_connection();
             if let Some(bp) = final_boxart {
                 let _ = conn.execute("UPDATE roms SET boxart_path = ?1 WHERE id = ?2", [&bp, rom_id]);
             }
             if let Some(ip) = icon_path {
                 let _ = conn.execute("UPDATE roms SET icon_path = ?1 WHERE id = ?2", [&ip, rom_id]);
             }
        }
    }

    fn normalize_title(title: &str) -> String {
    // 1. To Lowercase
    let mut t = title.to_lowercase();
    
    // 2. Remove Parenthesized content: "Game Name (Region) (Tags)" -> "Game Name"
    let re_paren = regex::Regex::new(r"\(.*?\)").unwrap();
    t = re_paren.replace_all(&t, "").to_string();

    // 3. Remove Brackets: "Game Name [Region] [Tags]" -> "Game Name"
    let re_bracket = regex::Regex::new(r"\[.*?\]").unwrap();
    t = re_bracket.replace_all(&t, "").to_string();

    // 4. Handle ", the" pattern: "Game, The" -> "The Game"
    if t.ends_with(", the") {
        t = format!("the {}", &t[..t.len() - 5].trim());
    }

    // 5. Replace common symbols and hyphens with spaces
    t = t.replace("™", " ")
         .replace("®", " ")
         .replace("©", " ")
         .replace("-", " ")
         .replace(":", " ")
         .replace(".", " ")
         .replace("_", " ");
    
    // 6. Remove non-alphanumeric (keep spaces)
    let re_clean = regex::Regex::new(r"[^a-z0-9 ]").unwrap();
    t = re_clean.replace_all(&t, "").to_string();
    
    // 7. Standardize whitespace
    t.split_whitespace().collect::<Vec<_>>().join(" ")
}

    fn update_row_by_id(&mut self, rom_id: &str) {
        let db_path = self.db_path.borrow().clone();
        if db_path.is_empty() { return; }

        if let Ok(db) = DbManager::open(&db_path) {
            let conn = db.get_connection();
            let query = "SELECT r.id, r.platform_id, r.path, r.filename, m.title, m.region, p.name, p.platform_type, 
                         COALESCE(r.boxart_path, a.local_path), r.date_added, m.play_count, m.total_play_time, m.last_played, 
                         p.icon, m.is_favorite, m.genre, m.developer, m.publisher, m.rating, m.tags, m.release_date,                          COALESCE(r.icon_path, a_icon.local_path), COALESCE(r.background_path, a_bg.local_path, a_ss.local_path),
                          m.is_installed, m.description
                         FROM roms r 
                         LEFT JOIN metadata m ON r.id = m.rom_id 
                         JOIN platforms p ON r.platform_id = p.id 
                         LEFT JOIN assets a ON r.id = a.rom_id AND a.type = 'Box - Front'
                         LEFT JOIN assets a_icon ON r.id = a_icon.rom_id AND a_icon.type = 'Icon'
                         LEFT JOIN assets a_bg ON r.id = a_bg.rom_id AND a_bg.type = 'Background'
                         LEFT JOIN assets a_ss ON r.id = a_ss.rom_id AND a_ss.type = 'Screenshot'
                         WHERE r.id = ?
                         GROUP BY r.id";
            
            if let Ok(mut stmt) = conn.prepare(query) {
                if let Ok(mut rows) = stmt.query_map([&rom_id], |row| {
                    Ok(Rom {
                        id: row.get(0)?,
                        platform_id: row.get(1)?,
                        path: row.get(2)?,
                        filename: row.get(3)?,
                        file_size: 0,
                        hash_sha1: None,
                        title: row.get(4)?,
                        region: row.get(5)?,
                        platform_name: Some(row.get(6)?),
                        platform_type: row.get(7)?,
                        date_added: row.get(9)?,
                        play_count: row.get(10)?,
                        total_play_time: row.get(11)?,
                        last_played: row.get(12)?,
                        platform_icon: row.get(13)?,
                        is_favorite: Some(row.get::<_, i32>(14).unwrap_or(0) != 0),
                        boxart_path: row.get(8).ok(),
                        genre: row.get(15).ok(),
                        developer: row.get(16).ok(),
                        publisher: row.get(17).ok(),
                        rating: row.get::<_, f32>(18).ok(),
                        tags: row.get(19).ok(),
                        release_date: {
                            let val: Option<rusqlite::types::Value> = row.get(20)?;
                            match val {
                                Some(rusqlite::types::Value::Text(s)) => Some(s),
                                Some(rusqlite::types::Value::Integer(i)) => Some(i.to_string()),
                                Some(rusqlite::types::Value::Real(f)) => Some(f.to_string()),
                                _ => None,
                            }
                        },
                        icon_path: row.get(21)?,
                        cloud_saves_supported: None,
                        is_installed: Some(row.get::<_, Option<i32>>(23).ok().flatten().map(|v| v != 0).unwrap_or_else(|| {
                            if rom_id.starts_with("steam-") {
                                crate::core::store::StoreManager::get_local_steam_appids().contains(&rom_id.replace("steam-", ""))
                            } else {
                                true
                            }
                        })),
                        background_path: row.get(22)?,
                        description: row.get(24).ok(),
                        resources: None,
                    })
                }) {
                    if let Some(Ok(updated_rom)) = rows.next() {
                        let mut roms = self.roms.borrow_mut();
                        if let Some(pos) = roms.iter().position(|r| r.id == rom_id) {
                            roms[pos] = updated_rom;
                            drop(roms);
                            let q_idx = self.row_index(pos as i32);
                            self.data_changed(q_idx, q_idx);
                            self.gameDataChanged(rom_id.to_string());
                        }
                    }
                }
            }
        }
    }

    fn get_wine_prefix(&self, rom_id: &str) -> Option<String> {
        let db_path = self.db_path.borrow().clone();
        if let Ok(db) = crate::core::db::DbManager::open(&db_path) {
            if let Ok(Some(config)) = db.get_pc_config(rom_id) {
                if let Some(prefix) = config.wine_prefix.filter(|s| !s.trim().is_empty()) {
                    log::info!("[EOS Overlay] Found wine prefix in PC config for {}: {}", rom_id, prefix);
                    return Some(prefix);
                }
            }
            if let Ok(Some((_, _, _, platform_pc_defaults))) = db.get_launch_info(rom_id) {
                let platform_defaults = platform_pc_defaults.as_ref().and_then(|json| serde_json::from_str::<serde_json::Value>(json).ok());
                if let Some(d) = platform_defaults {
                    if let Some(prefix) = d["wine_prefix"].as_str().map(|s| s.to_string()).filter(|s| !s.trim().is_empty()) {
                        log::info!("[EOS Overlay] Found wine prefix in platform defaults for {}: {}", rom_id, prefix);
                        return Some(prefix);
                    }
                }
            }
        }
        log::info!("[EOS Overlay] No wine prefix found for {}", rom_id);
        None
    }

    #[allow(non_snake_case)]
    fn enableEosOverlay(&mut self, rom_id: String) -> bool {
        log::info!("[EOS Overlay] Attempting to ENABLE overlay for {}", rom_id);
        if let Some(_app_id) = rom_id.strip_prefix("legendary-") {
            let prefix = self.get_wine_prefix(&rom_id);
            let tools_dir = crate::core::paths::get_data_dir().join("tools").join("eos-overlay");
            let result = crate::core::legendary::LegendaryWrapper::eos_overlay_enable(prefix.as_deref(), Some(tools_dir)).is_ok();
            log::info!("[EOS Overlay] Result of enabling overlay for {}: {}", rom_id, result);
            return result;
        }
        false
    }

    #[allow(non_snake_case)]
    fn disableEosOverlay(&mut self, rom_id: String) -> bool {
        log::info!("[EOS Overlay] Attempting to DISABLE overlay for {}", rom_id);
        if let Some(_app_id) = rom_id.strip_prefix("legendary-") {
            let prefix = self.get_wine_prefix(&rom_id);
            let tools_dir = crate::core::paths::get_data_dir().join("tools").join("eos-overlay");
            let result = crate::core::legendary::LegendaryWrapper::eos_overlay_disable(prefix.as_deref(), Some(tools_dir)).is_ok();
            log::info!("[EOS Overlay] Result of disabling overlay for {}: {}", rom_id, result);
            return result;
        }
        false
    }

    #[allow(non_snake_case)]
    fn isEosOverlayEnabled(&mut self, rom_id: String) -> bool {
        if let Some(_app_id) = rom_id.strip_prefix("legendary-") {
            let prefix = self.get_wine_prefix(&rom_id);
            let state = crate::core::legendary::LegendaryWrapper::is_eos_overlay_enabled(prefix.as_deref());
            log::info!("[EOS Overlay] Synchronous state check for {}: {}", rom_id, state);
            return state;
        }
        false
    }
    
    #[allow(non_snake_case)]
    fn checkEosOverlayEnabled(&mut self, rom_id: String) {
        log::info!("[EOS Overlay] Triggering async state check for {}", rom_id);
        if let Some(_app_id) = rom_id.strip_prefix("legendary-").map(|s| s.to_string()) {
            let prefix = self.get_wine_prefix(&rom_id);
            if let Some(ref tx) = *self.tx.borrow() {
                let tx_clone = tx.clone();
                let r_id = rom_id.clone();
                std::thread::spawn(move || {
                    let enabled = crate::core::legendary::LegendaryWrapper::is_eos_overlay_enabled(prefix.as_deref());
                    log::info!("[EOS Overlay] Async state check result for {}: {}", r_id, enabled);
                    let _ = tx_clone.send(AsyncResponse::EosOverlayEnabled(r_id, enabled));
                });
            }
        }
    }

    #[allow(non_snake_case)]
    fn isGameRunning(&self, rom_id: String) -> bool {
        self.running_games.borrow().contains_key(&rom_id)
    }

    #[allow(non_snake_case)]
    fn stopGame(&mut self, rom_id: String) {
        let pgid_opt = self.running_games.borrow().get(&rom_id).cloned();
        if let Some(pgid) = pgid_opt {
            log::info!("[Launcher] Stopping game {} with PGID {} (SIGKILL)", rom_id, pgid);
            #[cfg(unix)]
            {
                // Definitively stop the process group using system kill command
                let _ = std::process::Command::new("kill")
                    .arg("-9")
                    .arg(format!("-{}", pgid))
                    .status();
            }
            
            // Proactively remove from map and trigger UI update for instant feedback.
            self.running_games.borrow_mut().remove(&rom_id);
            self.runningGamesChanged();
        }
    }
}

async fn download_game_assets(
    client: Arc<ScraperClient>,
    tx: mpsc::Sender<AsyncResponse>,
    rom_id: String,
    db_path: String,
    platform_folder: String,
    rom_stem: String,
    assets: std::collections::HashMap<String, Vec<String>>,
) {
    // Collect all downloads first
    let mut downloads = Vec::new();
    for (category, urls) in assets {
        for url in urls {
            if !url.starts_with("file://") { // Only download remote URLs
                downloads.push((category.clone(), url.to_string()));
            }
        }
    }

    if !downloads.is_empty() {
        let total = downloads.len();
        for (i, (category, url)) in downloads.iter().enumerate() {
            // Calculate destination paths BEFORE download
            let media_type = match category.as_str() {
                "boxart" => "Box - Front",
                "boxart_back" => "Box - Back",
                "screenshot" => "Screenshot",
                "banner" => "Banner",
                "logo" => "Clear Logo",
                "background" => "Background",
                "video" => "Video",
                _ => category.as_str(),
            };
            
            let data_dir = crate::core::paths::get_data_dir();
            let p_safe = platform_folder.replace("/", "-").replace("\\", "-");
            let dest_dir = data_dir.join("Images").join(&p_safe).join(&rom_stem).join(media_type);

            // Create dir if needed
            if let Err(e) = std::fs::create_dir_all(&dest_dir) {
                log::error!("Failed to create asset directory: {}", e);
                continue;
            }

            // Extract filename from URL (e.g., "co2abc.jpg")
            // Fallback to "image.png" if parsing fails, but IGDB usually sends good filenames
            let url_obj = url::Url::parse(&url);
            let filename = if let Ok(u) = url_obj {
                u.path_segments().and_then(|segments| segments.last()).unwrap_or("image.png").to_string()
            } else {
                 url.split('/').last().unwrap_or("image.png").to_string()
            };

            // Sanitized just in case (though hash filenames are usually safe)
            let safe_filename = filename.replace("?", "").replace("&", ""); 
            let dest_path = dest_dir.join(&safe_filename);

            // CHECK IF EXISTS
            if dest_path.exists() {
                // Skip Download!
                let msg = format!("Skipping download (exists) {}/{}...", i + 1, total);
                let _ = tx.send(AsyncResponse::AssetDownloadProgress(msg));
                log::info!("Asset already exists, skipping download: {}", dest_path.display());

                // Ensure it's linked in DB
                if let Ok(db_async) = DbManager::open(&db_path) {
                    let local_path = dest_path.to_string_lossy().to_string();
                    let _ = db_async.insert_asset(&rom_id, media_type, &local_path);
                    
                    // Update main table links
                    if media_type == "Box - Front" || media_type == "Icon" || media_type == "Background" {
                         let _ = db_async.update_rom_images(&rom_id, 
                            if media_type == "Box - Front" { Some(&local_path) } else { None },
                            if media_type == "Icon" { Some(&local_path) } else { None }
                        );
                        if media_type == "Background" {
                            let _ = db_async.get_connection().execute(
                                "UPDATE roms SET background_path = ?1 WHERE id = ?2",
                                rusqlite::params![local_path, rom_id]
                            );
                        }
                    }
                }
            } else {
                // Download needed
                // Emit Progress
                let msg = format!("Downloading image {}/{} for {}...", i + 1, total, rom_stem);
                let _ = tx.send(AsyncResponse::AssetDownloadProgress(msg));

                // Download logic
                match client.get_bytes(&url).await {
                    Ok(bytes) => {
                        if let Ok(_) = std::fs::write(&dest_path, &bytes) {
                            if let Ok(db_async) = DbManager::open(&db_path) {
                                let local_path = dest_path.to_string_lossy().to_string();
                                let _ = db_async.insert_asset(&rom_id, media_type, &local_path);
                                
                                // Also update the main roms table for quick display if it's a primary asset
                                if media_type == "Box - Front" || media_type == "Icon" || media_type == "Background" {
                                    let _ = db_async.update_rom_images(&rom_id, 
                                        if media_type == "Box - Front" { Some(&local_path) } else { None },
                                        if media_type == "Icon" { Some(&local_path) } else { None }
                                    );
                                    
                                    if media_type == "Background" {
                                        let _ = db_async.get_connection().execute(
                                            "UPDATE roms SET background_path = ?1 WHERE id = ?2",
                                            rusqlite::params![local_path, rom_id]
                                        );
                                    }
                                }
                            }
                        }
                    },
                    Err(e) => log::error!("Failed to download {}: {}", url, e),
                }
            }
        }
    }
    
    let _ = tx.send(AsyncResponse::AssetDownloadProgress("".to_string()));
        // Trigger a refresh/update signal for the game to show new images
        let _ = tx.send(AsyncResponse::BulkItemFinished(rom_id)); 
}
