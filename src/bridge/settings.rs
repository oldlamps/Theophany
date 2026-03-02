#![allow(non_snake_case)]
use std::fs;
use std::io::Write;
use std::collections::HashMap;
use serde::{Deserialize, Serialize};
use qmetaobject::prelude::*;

#[derive(Serialize, Deserialize, Clone)]
struct SettingsData {
    #[serde(default)]
    default_view: i32, // 0 = Grid, 1 = List
    #[serde(default)]
    show_filter_bar: bool,
    #[serde(default)]
    default_region: String,
    #[serde(default = "default_theme")]
    theme_name: String,
    #[serde(default)]
    retro_achievements_user: String,
    #[serde(default)]
    retro_achievements_token: String,
    #[serde(default)]
    retro_achievements_enabled: bool,
    #[serde(default = "default_true")]
    show_tray_icon: bool,
    #[serde(default)]
    close_to_tray: bool,
    #[serde(default)]
    ai_enabled: bool,
    #[serde(default = "default_ollama_url")]
    ollama_url: String,
    #[serde(default = "default_ollama_model")]
    ollama_model: String,
    #[serde(default)]
    gemini_api_key: String,
    #[serde(default)]
    openai_api_key: String,
    #[serde(default = "default_llm_provider")]
    llm_api_provider: String,
    #[serde(default)]
    details_prefer_video: bool,
    #[serde(default = "default_true")]
    ignore_the_in_sort: bool,
    #[serde(default = "default_description_prompt")]
    ai_description_prompt: String,
    #[serde(default)]
    pub column_widths: String,
    #[serde(default = "default_true")]
    pub default_ignore_on_delete: bool,
    #[serde(default = "default_hotkeys")]
    pub hotkeys: HashMap<String, String>,
    #[serde(default = "default_metadata_scraper")]
    pub active_metadata_scraper: String,
    #[serde(default = "default_image_scraper")]
    pub active_image_scraper: String,
    #[serde(default = "default_grid_scale")]
    pub grid_scale: f32,
    #[serde(default)]
    pub sidebar_library_collapsed: bool,
    #[serde(default)]
    pub sidebar_collections_collapsed: bool,
    #[serde(default)]
    pub sidebar_platforms_collapsed: bool,
    #[serde(default)]
    pub sidebar_playlists_collapsed: bool,
    #[serde(default)]
    pub save_heroic_assets_locally: bool,
    #[serde(default)]
    pub auto_rescan_on_startup: bool,
    #[serde(default = "default_true")]
    pub confirm_on_quit: bool,
    #[serde(default)]
    pub use_custom_ytdlp: bool,
    #[serde(default)]
    pub custom_ytdlp_path: String,
    #[serde(default)]
    pub default_proton_runner: String,
    #[serde(default = "default_prefix")]
    pub default_proton_prefix: String,
    #[serde(default)]
    pub default_proton_wrapper: String,
    #[serde(default)]
    pub default_proton_use_gamescope: bool,
    #[serde(default)]
    pub default_proton_use_mangohud: bool,
    #[serde(default)]
    pub default_proton_gamescope_args: String,
    #[serde(default)]
    pub default_proton_gamescope_w: String,
    #[serde(default)]
    pub default_proton_gamescope_h: String,
    #[serde(default)]
    pub default_proton_gamescope_out_w: String,
    #[serde(default)]
    pub default_proton_gamescope_out_h: String,
    #[serde(default)]
    pub default_proton_gamescope_refresh: String,
    #[serde(default)]
    pub default_proton_gamescope_scaling: i32,
    #[serde(default)]
    pub default_proton_gamescope_upscaler: i32,
    #[serde(default)]
    pub default_proton_gamescope_fullscreen: bool,
    #[serde(default)]
    pub sidebar_collapsed: bool,
    #[serde(default)]
    pub hide_platforms_sidebar: bool,
    #[serde(default)]
    pub first_run_completed: bool,
    #[serde(default = "default_true")]
    pub check_for_updates_on_startup: bool,
    #[serde(default)]
    pub steam_id: String,
    #[serde(default)]
    pub steam_api_key: String,
    #[serde(default)]
    pub exodos_path: String,
    #[serde(default = "default_sidebar_width")]
    pub sidebar_width: f32,
    #[serde(default = "default_details_width")]
    pub details_width: f32,
    #[serde(default)]
    pub use_custom_legendary: bool,
    #[serde(default)]
    pub custom_legendary_path: String,
    #[serde(default = "default_install_location")]
    pub default_install_location: String,
}

impl Default for SettingsData {
    fn default() -> Self {
        Self {
            default_view: 0,
            show_filter_bar: false,
            default_region: String::new(),
            theme_name: default_theme(),
            retro_achievements_user: String::new(),
            retro_achievements_token: String::new(),
            retro_achievements_enabled: false,
            show_tray_icon: true,
            close_to_tray: false,
            ai_enabled: false,
            ollama_url: default_ollama_url(),
            ollama_model: default_ollama_model(),
            gemini_api_key: String::new(),
            openai_api_key: String::new(),
            llm_api_provider: default_llm_provider(),
            details_prefer_video: false,
            ignore_the_in_sort: true,
            ai_description_prompt: default_description_prompt(),
            column_widths: String::new(),
            default_ignore_on_delete: true,
            hotkeys: default_hotkeys(),
            active_metadata_scraper: default_metadata_scraper(),
            active_image_scraper: default_image_scraper(),
            grid_scale: 1.0,
            sidebar_library_collapsed: false,
            sidebar_collections_collapsed: false,
            sidebar_platforms_collapsed: false,
            sidebar_playlists_collapsed: false,
            save_heroic_assets_locally: false,
            auto_rescan_on_startup: false,
            confirm_on_quit: true,
            use_custom_ytdlp: false,
            custom_ytdlp_path: String::new(),
            default_proton_runner: String::new(),
            default_proton_prefix: default_prefix(),
            default_proton_wrapper: String::new(),
            default_proton_use_gamescope: false,
            default_proton_use_mangohud: false,
            default_proton_gamescope_args: String::new(),
            default_proton_gamescope_w: String::new(),
            default_proton_gamescope_h: String::new(),
            default_proton_gamescope_out_w: String::new(),
            default_proton_gamescope_out_h: String::new(),
            default_proton_gamescope_refresh: String::new(),
            default_proton_gamescope_scaling: 0,
            default_proton_gamescope_upscaler: 0,
            default_proton_gamescope_fullscreen: false,
            sidebar_collapsed: false,
            hide_platforms_sidebar: false,
            first_run_completed: false,
            check_for_updates_on_startup: true,
            steam_id: String::new(),
            steam_api_key: String::new(),
            exodos_path: String::new(),
            sidebar_width: default_sidebar_width(),
            details_width: default_details_width(),
            use_custom_legendary: false,
            custom_legendary_path: String::new(),
            default_install_location: default_install_location(),
        }
    }
}

fn default_theme() -> String { "Default".to_string() }
fn default_ollama_url() -> String { "http://localhost:11434".to_string() }
fn default_ollama_model() -> String { "llama3".to_string() }

fn default_grid_scale() -> f32 { 1.0 }
fn default_metadata_scraper() -> String { "IGDB".to_string() }
fn default_image_scraper() -> String { "Web Search".to_string() }
fn default_llm_provider() -> String { "Gemini".to_string() }
fn default_sidebar_width() -> f32 { 250.0 }
fn default_details_width() -> f32 { 350.0 }
fn default_prefix() -> String { 
    crate::core::paths::get_default_prefix_dir().to_string_lossy().to_string() 
}

fn default_install_location() -> String {
    crate::core::paths::get_default_install_dir().to_string_lossy().to_string()
}

fn default_hotkeys() -> HashMap<String, String> {
    let mut map = HashMap::new();
    map.insert("Search".to_string(), "Ctrl+F".to_string());
    map.insert("Settings".to_string(), "Ctrl+,".to_string());
    map.insert("Quit".to_string(), "Ctrl+Q".to_string());
    map.insert("Refresh".to_string(), "F5".to_string());
    map.insert("Launch".to_string(), "Return".to_string());
    map.insert("Edit".to_string(), "E".to_string());
    map.insert("CycleNext".to_string(), "Ctrl+Tab".to_string());
    map.insert("CyclePrev".to_string(), "Ctrl+Shift+Tab".to_string());
    map.insert("Back".to_string(), "Backspace".to_string());
    map.insert("Forward".to_string(), "Alt+Right".to_string());
    map.insert("NextLetter".to_string(), "Shift+PgDown".to_string());
    map.insert("PrevLetter".to_string(), "Shift+PgUp".to_string());
    map.insert("PageDown".to_string(), "PgDown".to_string());
    map.insert("PageUp".to_string(), "PgUp".to_string());
    map.insert("Home".to_string(), "Home".to_string());
    map.insert("End".to_string(), "End".to_string());
    map.insert("ScrapeManual".to_string(), "Shift+S".to_string());
    map.insert("ScrapeAuto".to_string(), "Shift+A".to_string());
    map.insert("Achievements".to_string(), "Shift+D".to_string());
    map.insert("ImageViewer".to_string(), "I".to_string());
    map.insert("VideoExplorer".to_string(), "V".to_string());
    map.insert("FilterBar".to_string(), "Ctrl+I".to_string());
    map.insert("ToggleSidebar".to_string(), "Ctrl+B".to_string());
    map.insert("GlobalSearch".to_string(), "Ctrl+Alt+F".to_string());
    map.insert("Escape".to_string(), "Escape".to_string());
    map
}

fn default_description_prompt() -> String {
    "Write a concise, engaging description for the video game '{title}'. Use the following existing description as context if available: '{description}'. Focus on key gameplay mechanics and plot. Keep it under 150 words. Do not include conversational filler like 'Here is a description', just return the description text.".to_string()
}

fn default_true() -> bool { true }


#[derive(QObject)]
#[allow(non_snake_case)]
pub struct AppSettings {
    base: qt_base_class!(trait QObject),
    
    // Properties exposed to QML
    defaultView: qt_property!(i32; NOTIFY settingsChanged),
    showFilterBar: qt_property!(bool; NOTIFY settingsChanged),
    defaultRegion: qt_property!(QString; NOTIFY settingsChanged),
    themeName: qt_property!(QString; NOTIFY settingsChanged),
    retroAchievementsUser: qt_property!(QString; NOTIFY settingsChanged),
    retroAchievementsToken: qt_property!(QString; NOTIFY settingsChanged),
    retroAchievementsEnabled: qt_property!(bool; NOTIFY settingsChanged),
    
    showTrayIcon: qt_property!(bool; NOTIFY settingsChanged),
    closeToTray: qt_property!(bool; NOTIFY closeToTrayChanged),

    // AI Settings
    aiEnabled: qt_property!(bool; NOTIFY settingsChanged),
    ollamaUrl: qt_property!(QString; NOTIFY settingsChanged),
    ollamaModel: qt_property!(QString; NOTIFY settingsChanged),
    geminiApiKey: qt_property!(QString; NOTIFY settingsChanged),
    openaiApiKey: qt_property!(QString; NOTIFY settingsChanged),
    llmApiProvider: qt_property!(QString; NOTIFY settingsChanged),

    detailsPreferVideo: qt_property!(bool; NOTIFY settingsChanged),
    ignoreTheInSort: qt_property!(bool; NOTIFY settingsChanged),
    aiDescriptionPrompt: qt_property!(QString; NOTIFY settingsChanged),
    columnWidths: qt_property!(QString; NOTIFY settingsChanged),
    defaultIgnoreOnDelete: qt_property!(bool; NOTIFY settingsChanged),
    hotkeysJson: qt_property!(QString; NOTIFY settingsChanged),
    activeMetadataScraper: qt_property!(QString; NOTIFY settingsChanged),
    activeImageScraper: qt_property!(QString; NOTIFY settingsChanged),
    gridScale: qt_property!(f32; NOTIFY settingsChanged),
    
    sidebarLibraryCollapsed: qt_property!(bool; NOTIFY settingsChanged),
    sidebarCollectionsCollapsed: qt_property!(bool; NOTIFY settingsChanged),
    sidebarPlatformsCollapsed: qt_property!(bool; NOTIFY settingsChanged),
    sidebarPlaylistsCollapsed: qt_property!(bool; NOTIFY settingsChanged),
    saveHeroicAssetsLocally: qt_property!(bool; NOTIFY settingsChanged),
    autoRescanOnStartup: qt_property!(bool; NOTIFY settingsChanged),
    confirmOnQuit: qt_property!(bool; NOTIFY settingsChanged),
    useCustomYtdlp: qt_property!(bool; NOTIFY settingsChanged),
    customYtdlpPath: qt_property!(QString; NOTIFY settingsChanged),
    defaultProtonRunner: qt_property!(QString; NOTIFY settingsChanged),
    defaultProtonPrefix: qt_property!(QString; NOTIFY settingsChanged),
    defaultProtonWrapper: qt_property!(QString; NOTIFY settingsChanged),
    defaultProtonUseGamescope: qt_property!(bool; NOTIFY settingsChanged),
    defaultProtonUseMangohud: qt_property!(bool; NOTIFY settingsChanged),
    defaultProtonGamescopeArgs: qt_property!(QString; NOTIFY settingsChanged),
    defaultProtonGamescopeW: qt_property!(QString; NOTIFY settingsChanged),
    defaultProtonGamescopeH: qt_property!(QString; NOTIFY settingsChanged),
    defaultProtonGamescopeOutW: qt_property!(QString; NOTIFY settingsChanged),
    defaultProtonGamescopeOutH: qt_property!(QString; NOTIFY settingsChanged),
    defaultProtonGamescopeRefresh: qt_property!(QString; NOTIFY settingsChanged),
    defaultProtonGamescopeScaling: qt_property!(i32; NOTIFY settingsChanged),
    defaultProtonGamescopeUpscaler: qt_property!(i32; NOTIFY settingsChanged),
    defaultProtonGamescopeFullscreen: qt_property!(bool; NOTIFY settingsChanged),
    sidebarCollapsed: qt_property!(bool; NOTIFY settingsChanged),
    hidePlatformsSidebar: qt_property!(bool; NOTIFY settingsChanged),
    firstRunCompleted: qt_property!(bool; NOTIFY settingsChanged),
    checkForUpdatesOnStartup: qt_property!(bool; NOTIFY settingsChanged),
    steamId: qt_property!(QString; NOTIFY settingsChanged),
    steamApiKey: qt_property!(QString; NOTIFY settingsChanged),
    exodosPath: qt_property!(QString; NOTIFY settingsChanged),
    sidebarWidth: qt_property!(f32; NOTIFY settingsChanged),
    detailsWidth: qt_property!(f32; NOTIFY settingsChanged),
    useCustomLegendary: qt_property!(bool; NOTIFY settingsChanged),
    customLegendaryPath: qt_property!(QString; NOTIFY settingsChanged),
    defaultInstallLocation: qt_property!(QString; NOTIFY settingsChanged),
    closeToTrayChanged: qt_signal!(),
    settingsChanged: qt_signal!(),
    defaultPlatformsJson: qt_property!(QString; CONST),
    
    save: qt_method!(fn(&self)),
    load: qt_method!(fn(&mut self)),
    setHotkey: qt_method!(fn(&mut self, action: String, sequence: String)),
    isPlatformRaActive: qt_method!(fn(&self, slug: String) -> bool),
    settingsExist: qt_method!(fn(&self) -> bool),
    
    // Internal data
    data: SettingsData,
}

impl AppSettings {
    pub fn should_save_heroic_assets_locally() -> bool {
        let path = crate::core::paths::get_config_dir().join("settings.json");
        if let Ok(content) = fs::read_to_string(&path) {
            if let Ok(data) = serde_json::from_str::<SettingsData>(&content) {
                return data.save_heroic_assets_locally;
            }
        }
        false
    }

    pub fn get_steam_credentials() -> (String, String) {
        let path = crate::core::paths::get_config_dir().join("settings.json");
        if let Ok(content) = fs::read_to_string(&path) {
            if let Ok(data) = serde_json::from_str::<SettingsData>(&content) {
                return (data.steam_id, data.steam_api_key);
            }
        }
        (String::new(), String::new())
    }

    pub fn get_pc_defaults() -> (String, String, String, bool, bool, String, String, String, String, String, String, i32, i32, bool) {
        let path = crate::core::paths::get_config_dir().join("settings.json");
        if let Ok(content) = fs::read_to_string(&path) {
            if let Ok(data) = serde_json::from_str::<SettingsData>(&content) {
                return (
                    data.default_proton_runner, 
                    data.default_proton_prefix, 
                    data.default_proton_wrapper,
                    data.default_proton_use_gamescope,
                    data.default_proton_use_mangohud,
                    data.default_proton_gamescope_args,
                    data.default_proton_gamescope_w,
                    data.default_proton_gamescope_h,
                    data.default_proton_gamescope_out_w,
                    data.default_proton_gamescope_out_h,
                    data.default_proton_gamescope_refresh,
                    data.default_proton_gamescope_scaling,
                    data.default_proton_gamescope_upscaler,
                    data.default_proton_gamescope_fullscreen,
                );
            }
        }
        (String::new(), String::new(), String::new(), false, false, String::new(), String::new(), String::new(), String::new(), String::new(), String::new(), 0, 0, false)
    }

    pub fn get_exodos_path() -> String {
        let path = crate::core::paths::get_config_dir().join("settings.json");
        if let Ok(content) = fs::read_to_string(&path) {
            if let Ok(data) = serde_json::from_str::<SettingsData>(&content) {
                return data.exodos_path;
            }
        }
        String::new()
    }
}

impl AppSettings {
    fn save(&self) {
        let path = crate::core::paths::get_config_dir().join("settings.json");
        
        let data = SettingsData {
            default_view: self.defaultView,
            show_filter_bar: self.showFilterBar,
            default_region: self.defaultRegion.to_string(),
            theme_name: self.themeName.to_string(),
            retro_achievements_user: self.retroAchievementsUser.to_string(),
            retro_achievements_token: self.retroAchievementsToken.to_string(),
            retro_achievements_enabled: self.retroAchievementsEnabled,
            show_tray_icon: self.showTrayIcon,
            close_to_tray: self.closeToTray,
            ai_enabled: self.aiEnabled,
            ollama_url: self.ollamaUrl.to_string(),
            ollama_model: self.ollamaModel.to_string(),
            gemini_api_key: self.geminiApiKey.to_string(),
            openai_api_key: self.openaiApiKey.to_string(),
            llm_api_provider: self.llmApiProvider.to_string(),
            details_prefer_video: self.detailsPreferVideo,
            ignore_the_in_sort: self.ignoreTheInSort,
            ai_description_prompt: self.aiDescriptionPrompt.to_string(),
            column_widths: self.columnWidths.to_string(),
            default_ignore_on_delete: self.defaultIgnoreOnDelete,
            hotkeys: self.data.hotkeys.clone(),
            active_metadata_scraper: self.activeMetadataScraper.to_string(),
            active_image_scraper: self.activeImageScraper.to_string(),
            grid_scale: self.gridScale,
            sidebar_library_collapsed: self.sidebarLibraryCollapsed,
            sidebar_collections_collapsed: self.sidebarCollectionsCollapsed,
            sidebar_platforms_collapsed: self.sidebarPlatformsCollapsed,
            sidebar_playlists_collapsed: self.sidebarPlaylistsCollapsed,
            save_heroic_assets_locally: self.saveHeroicAssetsLocally,
            auto_rescan_on_startup: self.autoRescanOnStartup,
            confirm_on_quit: self.confirmOnQuit,
            use_custom_ytdlp: self.useCustomYtdlp,
            custom_ytdlp_path: self.customYtdlpPath.to_string(),
            default_proton_runner: self.defaultProtonRunner.to_string(),
            default_proton_prefix: self.defaultProtonPrefix.to_string(),
            default_proton_wrapper: self.defaultProtonWrapper.to_string(),
            default_proton_use_gamescope: self.defaultProtonUseGamescope,
            default_proton_use_mangohud: self.defaultProtonUseMangohud,
            default_proton_gamescope_args: self.defaultProtonGamescopeArgs.to_string(),
            default_proton_gamescope_w: self.defaultProtonGamescopeW.to_string(),
            default_proton_gamescope_h: self.defaultProtonGamescopeH.to_string(),
            default_proton_gamescope_out_w: self.defaultProtonGamescopeOutW.to_string(),
            default_proton_gamescope_out_h: self.defaultProtonGamescopeOutH.to_string(),
            default_proton_gamescope_refresh: self.defaultProtonGamescopeRefresh.to_string(),
            default_proton_gamescope_scaling: self.defaultProtonGamescopeScaling,
            default_proton_gamescope_upscaler: self.defaultProtonGamescopeUpscaler,
            default_proton_gamescope_fullscreen: self.defaultProtonGamescopeFullscreen,
            sidebar_collapsed: self.sidebarCollapsed,
            hide_platforms_sidebar: self.hidePlatformsSidebar,
            first_run_completed: self.firstRunCompleted,
            check_for_updates_on_startup: self.checkForUpdatesOnStartup,
            steam_id: self.steamId.to_string(),
            steam_api_key: self.steamApiKey.to_string(),
            exodos_path: self.exodosPath.to_string(),
            sidebar_width: self.sidebarWidth,
            details_width: self.detailsWidth,
            use_custom_legendary: self.useCustomLegendary,
            custom_legendary_path: self.customLegendaryPath.to_string(),
            default_install_location: self.defaultInstallLocation.to_string(),
        };
        
        if let Ok(json) = serde_json::to_string_pretty(&data) {
            if let Ok(mut file) = fs::File::create(&path) {
                let _ = file.write_all(json.as_bytes());
            }
        }
    }

    fn settingsExist(&self) -> bool {
        crate::core::paths::get_config_dir().join("settings.json").exists()
    }
    
    fn load(&mut self) {
        let path = crate::core::paths::get_config_dir().join("settings.json");
        if path.exists() {
            if let Ok(content) = fs::read_to_string(&path) {
                if let Ok(data) = serde_json::from_str::<SettingsData>(&content) {
                    self.defaultView = data.default_view;
                    self.showFilterBar = data.show_filter_bar;
                    self.defaultRegion = QString::from(data.default_region);
                    let t = if data.theme_name.is_empty() { "Default".to_string() } else { data.theme_name };
                    self.themeName = QString::from(t);
                    self.retroAchievementsUser = QString::from(data.retro_achievements_user);
                    self.retroAchievementsToken = QString::from(data.retro_achievements_token);
                    self.retroAchievementsEnabled = data.retro_achievements_enabled;
                    self.showTrayIcon = data.show_tray_icon;
                    self.closeToTray = data.close_to_tray;
                    
                    self.aiEnabled = data.ai_enabled;
                    let url = if data.ollama_url.is_empty() { "http://localhost:11434".to_string() } else { data.ollama_url };
                    self.ollamaUrl = QString::from(url);
                    let model = if data.ollama_model.is_empty() { "llama3".to_string() } else { data.ollama_model };
                    self.ollamaModel = QString::from(model);
                    self.geminiApiKey = QString::from(data.gemini_api_key);
                    self.openaiApiKey = QString::from(data.openai_api_key);
                    self.llmApiProvider = QString::from(if data.llm_api_provider.is_empty() { "Gemini".to_string() } else { data.llm_api_provider });
                    self.detailsPreferVideo = data.details_prefer_video;
                    self.ignoreTheInSort = data.ignore_the_in_sort;
                    self.aiDescriptionPrompt = QString::from(data.ai_description_prompt);
                    self.columnWidths = QString::from(data.column_widths);
                    self.defaultIgnoreOnDelete = data.default_ignore_on_delete;
                    
                    // Merge loaded hotkeys with defaults to ensure new defaults appear
                    self.data.hotkeys = default_hotkeys();
                    for (k, v) in &data.hotkeys {
                        self.data.hotkeys.insert(k.clone(), v.clone());
                    }
                    if let Ok(json) = serde_json::to_string(&self.data.hotkeys) {
                        self.hotkeysJson = QString::from(json);
                    }
                    
                    self.activeMetadataScraper = QString::from(if data.active_metadata_scraper.is_empty() || data.active_metadata_scraper == "LaunchBox" { 
                        "IGDB".to_string() 
                    } else { 
                        data.active_metadata_scraper 
                    });
                    self.activeImageScraper = QString::from(if data.active_image_scraper.is_empty() || data.active_image_scraper == "LaunchBox" { 
                        "Web Search".to_string() 
                    } else { 
                        data.active_image_scraper 
                    });
                    self.gridScale = data.grid_scale;
                    
                    self.sidebarLibraryCollapsed = data.sidebar_library_collapsed;
                    self.sidebarCollectionsCollapsed = data.sidebar_collections_collapsed;
                    self.sidebarPlatformsCollapsed = data.sidebar_platforms_collapsed;
                    self.sidebarPlaylistsCollapsed = data.sidebar_playlists_collapsed;
                    self.saveHeroicAssetsLocally = data.save_heroic_assets_locally;
                    self.autoRescanOnStartup = data.auto_rescan_on_startup;
                    self.confirmOnQuit = data.confirm_on_quit;
                    self.useCustomYtdlp = data.use_custom_ytdlp;
                    self.customYtdlpPath = QString::from(data.custom_ytdlp_path);
                    self.defaultProtonRunner = QString::from(data.default_proton_runner);
                    self.defaultProtonPrefix = QString::from(if data.default_proton_prefix.is_empty() { default_prefix() } else { data.default_proton_prefix });
                    self.defaultProtonWrapper = QString::from(data.default_proton_wrapper);
                    self.defaultProtonUseGamescope = data.default_proton_use_gamescope;
                    self.defaultProtonUseMangohud = data.default_proton_use_mangohud;
                    self.defaultProtonGamescopeArgs = QString::from(data.default_proton_gamescope_args);
                    self.defaultProtonGamescopeW = QString::from(data.default_proton_gamescope_w);
                    self.defaultProtonGamescopeH = QString::from(data.default_proton_gamescope_h);
                    self.defaultProtonGamescopeOutW = QString::from(data.default_proton_gamescope_out_w);
                    self.defaultProtonGamescopeOutH = QString::from(data.default_proton_gamescope_out_h);
                    self.defaultProtonGamescopeRefresh = QString::from(data.default_proton_gamescope_refresh);
                    self.defaultProtonGamescopeScaling = data.default_proton_gamescope_scaling;
                    self.defaultProtonGamescopeUpscaler = data.default_proton_gamescope_upscaler;
                    self.defaultProtonGamescopeFullscreen = data.default_proton_gamescope_fullscreen;
                    self.sidebarCollapsed = data.sidebar_collapsed;
                    self.hidePlatformsSidebar = data.hide_platforms_sidebar;
                    self.firstRunCompleted = data.first_run_completed;
                    self.checkForUpdatesOnStartup = data.check_for_updates_on_startup;
                    self.steamId = QString::from(data.steam_id);
                    self.steamApiKey = QString::from(data.steam_api_key);
                    self.exodosPath = QString::from(data.exodos_path);
                    self.sidebarWidth = data.sidebar_width;
                    self.detailsWidth = data.details_width;
                    self.useCustomLegendary = data.use_custom_legendary;
                    self.customLegendaryPath = QString::from(data.custom_legendary_path);
                    self.defaultInstallLocation = QString::from(if data.default_install_location.is_empty() { default_install_location() } else { data.default_install_location });
                    
                    self.settingsChanged();
                }
            }
        } else {
            // First run migration: Create settings.json if it doesn't exist
            self.save();
        }
    }
// ... (omitting remaining methods as they don't change or only minorly)
    fn isPlatformRaActive(&self, slug: String) -> bool {
        let platforms = super::static_platforms::get_default_platforms();
        for p in platforms {
            if p.slug.eq_ignore_ascii_case(&slug) || p.name.eq_ignore_ascii_case(&slug) {
                return p.is_active;
            }
        }
        // Fallback for types that might not be in the RA list (like PC)
        if slug.to_lowercase().contains("pc") {
             return false;
        }

        false
    }

    fn setHotkey(&mut self, action: String, sequence: String) {
        self.data.hotkeys.insert(action, sequence);
        
        // Update the JSON property
        if let Ok(json) = serde_json::to_string(&self.data.hotkeys) {
            self.hotkeysJson = QString::from(json);
            self.settingsChanged();
        }
        self.save();
    }

    pub fn get_default_platforms_json() -> String {
        let platforms = super::static_platforms::get_default_platforms();
        serde_json::to_string(&platforms).unwrap_or_else(|_| "[]".to_string())
    }
}

impl Default for AppSettings {
    fn default() -> Self {
        let mut s = AppSettings {
            base: Default::default(),
            defaultView: Default::default(),
            showFilterBar: Default::default(),
            defaultRegion: Default::default(),
            themeName: Default::default(),
            retroAchievementsUser: Default::default(),
            retroAchievementsToken: Default::default(),
            retroAchievementsEnabled: Default::default(),
            showTrayIcon: Default::default(),
            closeToTray: Default::default(),
            aiEnabled: Default::default(),
            ollamaUrl: Default::default(),
            ollamaModel: Default::default(),
            geminiApiKey: Default::default(),
            openaiApiKey: Default::default(),
            llmApiProvider: Default::default(),
            detailsPreferVideo: Default::default(),
            ignoreTheInSort: Default::default(),
            aiDescriptionPrompt: Default::default(),
            columnWidths: Default::default(),
            defaultIgnoreOnDelete: Default::default(),
            hotkeysJson: Default::default(),
            activeMetadataScraper: Default::default(),
            activeImageScraper: Default::default(),
            gridScale: 1.0,
            
            sidebarLibraryCollapsed: false,
            sidebarCollectionsCollapsed: false,
            sidebarPlatformsCollapsed: false,
            sidebarPlaylistsCollapsed: false,
            sidebarCollapsed: false,
            hidePlatformsSidebar: false,
            firstRunCompleted: false,
            checkForUpdatesOnStartup: true,
            steamId: Default::default(),
            steamApiKey: Default::default(),
            exodosPath: Default::default(),
            saveHeroicAssetsLocally: false,
            autoRescanOnStartup: false,
            confirmOnQuit: true,
            useCustomYtdlp: false,
            customYtdlpPath: Default::default(),
            defaultProtonRunner: Default::default(),
            defaultProtonPrefix: QString::from(default_prefix()),
            defaultProtonWrapper: Default::default(),
            defaultProtonUseGamescope: false,
            defaultProtonUseMangohud: false,
            defaultProtonGamescopeArgs: Default::default(),
            defaultProtonGamescopeW: Default::default(),
            defaultProtonGamescopeH: Default::default(),
            defaultProtonGamescopeOutW: Default::default(),
            defaultProtonGamescopeOutH: Default::default(),
            defaultProtonGamescopeRefresh: Default::default(),
            defaultProtonGamescopeScaling: 0,
            defaultProtonGamescopeUpscaler: 0,
            defaultProtonGamescopeFullscreen: false,
            sidebarWidth: default_sidebar_width(),
            detailsWidth: default_details_width(),
            useCustomLegendary: false,
            customLegendaryPath: Default::default(),
            defaultInstallLocation: QString::from(default_install_location()),
            
            settingsChanged: Default::default(),
            closeToTrayChanged: Default::default(),
            defaultPlatformsJson: QString::from(Self::get_default_platforms_json()),
            
            save: Default::default(),
            load: Default::default(),
            setHotkey: Default::default(),
            isPlatformRaActive: Default::default(),
            settingsExist: Default::default(),
            
            data: SettingsData::default(),
        };
        
        s.data.hotkeys = default_hotkeys();
        s.hotkeysJson = QString::from(serde_json::to_string(&s.data.hotkeys).unwrap_or_default());
        
        // Initialize from data
        s.defaultView = s.data.default_view;
        s.showFilterBar = s.data.show_filter_bar;
        s.defaultRegion = QString::from(s.data.default_region.clone());
        s.themeName = QString::from(s.data.theme_name.clone());
        s.retroAchievementsUser = QString::from(s.data.retro_achievements_user.clone());
        s.retroAchievementsToken = QString::from(s.data.retro_achievements_token.clone());
        s.retroAchievementsEnabled = s.data.retro_achievements_enabled;
        s.showTrayIcon = s.data.show_tray_icon;
        s.closeToTray = s.data.close_to_tray;
        s.aiEnabled = s.data.ai_enabled;
        s.ollamaUrl = QString::from(s.data.ollama_url.clone());
        s.ollamaModel = QString::from(s.data.ollama_model.clone());
        s.geminiApiKey = QString::from(s.data.gemini_api_key.clone());
        s.openaiApiKey = QString::from(s.data.openai_api_key.clone());
        s.llmApiProvider = QString::from(s.data.llm_api_provider.clone());
        s.detailsPreferVideo = s.data.details_prefer_video;
        s.ignoreTheInSort = s.data.ignore_the_in_sort;
        s.aiDescriptionPrompt = QString::from(s.data.ai_description_prompt.clone());
        s.columnWidths = QString::from(s.data.column_widths.clone());
        s.defaultIgnoreOnDelete = s.data.default_ignore_on_delete;
        s.gridScale = s.data.grid_scale;
        s.sidebarLibraryCollapsed = s.data.sidebar_library_collapsed;
        s.sidebarCollectionsCollapsed = s.data.sidebar_collections_collapsed;
        s.sidebarPlatformsCollapsed = s.data.sidebar_platforms_collapsed;
        s.sidebarPlaylistsCollapsed = s.data.sidebar_playlists_collapsed;
        s.saveHeroicAssetsLocally = s.data.save_heroic_assets_locally;
        s.autoRescanOnStartup = s.data.auto_rescan_on_startup;
        s.confirmOnQuit = s.data.confirm_on_quit;
        s.useCustomYtdlp = s.data.use_custom_ytdlp;
        s.customYtdlpPath = QString::from(s.data.custom_ytdlp_path.clone());
        s.defaultProtonRunner = QString::from(s.data.default_proton_runner.clone());
        s.defaultProtonPrefix = QString::from(s.data.default_proton_prefix.clone());
        s.defaultProtonWrapper = QString::from(s.data.default_proton_wrapper.clone());
        s.defaultProtonUseGamescope = s.data.default_proton_use_gamescope;
        s.defaultProtonUseMangohud = s.data.default_proton_use_mangohud;
        s.defaultProtonGamescopeArgs = QString::from(s.data.default_proton_gamescope_args.clone());
        s.defaultProtonGamescopeW = QString::from(s.data.default_proton_gamescope_w.clone());
        s.defaultProtonGamescopeH = QString::from(s.data.default_proton_gamescope_h.clone());
        s.defaultProtonGamescopeOutW = QString::from(s.data.default_proton_gamescope_out_w.clone());
        s.defaultProtonGamescopeOutH = QString::from(s.data.default_proton_gamescope_out_h.clone());
        s.defaultProtonGamescopeRefresh = QString::from(s.data.default_proton_gamescope_refresh.clone());
        s.defaultProtonGamescopeScaling = s.data.default_proton_gamescope_scaling;
        s.defaultProtonGamescopeUpscaler = s.data.default_proton_gamescope_upscaler;
        s.defaultProtonGamescopeFullscreen = s.data.default_proton_gamescope_fullscreen;
        s.sidebarCollapsed = s.data.sidebar_collapsed;
        s.hidePlatformsSidebar = s.data.hide_platforms_sidebar;
        s.firstRunCompleted = s.data.first_run_completed;
        s.checkForUpdatesOnStartup = s.data.check_for_updates_on_startup;
        s.steamId = QString::from(s.data.steam_id.clone());
        s.steamApiKey = QString::from(s.data.steam_api_key.clone());
        s.exodosPath = QString::from(s.data.exodos_path.clone());
        s.sidebarWidth = s.data.sidebar_width;
        s.detailsWidth = s.data.details_width;
        s.useCustomLegendary = s.data.use_custom_legendary;
        s.customLegendaryPath = QString::from(s.data.custom_legendary_path.clone());
        s.defaultInstallLocation = QString::from(s.data.default_install_location.clone());
 
        s
    }
}
