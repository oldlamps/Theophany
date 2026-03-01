// Core data models shared across modules
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Platform {
    pub id: String,
    pub slug: String,
    pub name: String,
    pub icon: Option<String>,
    pub extension_filter: String,
    pub command_template: Option<String>,
    pub default_emulator_id: Option<String>,
    pub platform_type: Option<String>, // "NES", "SNES", etc.
    pub pc_config_json: Option<String>, // Default PC config for this platform
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameResource {
    pub id: String,
    pub rom_id: String,
    #[serde(rename = "type")]
    pub type_: String, // "wikipedia", "mobygames", "manual", "generic", "video"
    pub url: String,
    pub label: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Rom {
    pub id: String,
    pub platform_id: String,
    pub path: String,
    pub filename: String,
    pub file_size: i64,
    pub hash_sha1: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub region: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub platform_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub platform_type: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub platform_icon: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub boxart_path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub icon_path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub background_path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub date_added: Option<i64>, // Unix Timestamp
    #[serde(skip_serializing_if = "Option::is_none")]
    pub play_count: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub total_play_time: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_played: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub is_favorite: Option<bool>,
    
    // New fields for extended metadata view
    #[serde(skip_serializing_if = "Option::is_none")]
    pub genre: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub developer: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub publisher: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rating: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tags: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub release_date: Option<String>, // Changed to String
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub is_installed: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cloud_saves_supported: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub resources: Option<Vec<GameResource>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct GameMetadata {
    pub rom_id: String,
    pub title: Option<String>,
    pub description: Option<String>,
    pub rating: Option<f32>,
    pub release_date: Option<String>, // Changed to String
    pub developer: Option<String>,
    pub publisher: Option<String>,
    pub genre: Option<String>,
    pub tags: Option<String>, // "Tag1, Tag2, Tag3"
    pub region: Option<String>,
    pub is_favorite: bool,
    pub play_count: i32,
    pub last_played: Option<i64>, // Unix Timestamp
    pub total_play_time: i64, // Seconds
    pub achievement_count: Option<i32>,
    pub achievement_unlocked: Option<i32>,
    pub ra_game_id: Option<u64>,
    pub ra_recent_badges: Option<String>, // JSON list of badge names
    pub is_installed: bool,
    pub cloud_saves_supported: bool,
    pub resources: Option<Vec<GameResource>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EmulatorProfile {
    pub id: String,
    pub name: String,
    pub executable_path: String,
    pub arguments: String,
    #[serde(default)]
    pub is_retroarch: bool,
    #[serde(default)]
    pub retroarch_core: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Playlist {
    pub id: String,
    pub name: String,
    pub created_at: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct AiContext {
    pub recent_games: Vec<GameSession>,
    pub ignored_favorites: Vec<GameSession>, // Favorites not played recently
    pub near_completion: Vec<GameProgress>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct GameSession {
    pub title: String,
    pub last_played: i64,
    pub total_play_time: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct GameProgress {
    pub title: String,
    pub achievement_count: i32,
    pub achievement_unlocked: i32,
    pub completion_rate: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PcConfig {
    pub rom_id: String,
    pub umu_proton_version: Option<String>,
    pub umu_store: Option<String>,
    pub wine_prefix: Option<String>,
    pub working_dir: Option<String>,
    pub umu_id: Option<String>,
    pub env_vars: Option<String>, // JSON string
    pub extra_args: Option<String>,
    pub proton_verb: Option<String>,
    pub disable_fixes: Option<bool>,
    pub no_runtime: Option<bool>,
    pub log_level: Option<String>,
    pub wrapper: Option<String>,
    pub use_gamescope: Option<bool>,
    pub gamescope_args: Option<String>,
    pub use_mangohud: Option<bool>,
    pub pre_launch_script: Option<String>,
    pub post_launch_script: Option<String>,
    pub cloud_saves_enabled: Option<bool>,
    pub cloud_save_path: Option<String>,    // resolved host path or user override
    pub cloud_save_auto_sync: Option<bool>, // pull before launch, push after exit
}
