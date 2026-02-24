#![allow(dead_code)]
use crate::core::models::{Platform, Rom, GameResource};
use rusqlite::{params, Connection, Result};
use std::path::Path;

pub struct DbManager {
    conn: Connection,
}

impl DbManager {
    /// Simply opens a connection without initializing the schema (Fast)
    pub fn open<P: AsRef<Path>>(path: P) -> Result<Self> {
        let conn = Connection::open(path)?;
        conn.execute("PRAGMA foreign_keys = ON;", [])?;
        Ok(DbManager { conn })
    }

    /// Opens a connection and ensures the schema is up to date (Heavier)
    pub fn new<P: AsRef<Path>>(path: P) -> Result<Self> {
        let manager = Self::open(path)?;
        manager.init_schema()?;
        Ok(manager)
    }

    pub fn init_schema(&self) -> Result<()> {
        self.conn.execute_batch(
            "BEGIN;
            CREATE TABLE IF NOT EXISTS platforms (
                id TEXT PRIMARY KEY,
                slug TEXT NOT NULL,
                name TEXT NOT NULL,
                icon TEXT,
                extension_filter TEXT,
                command_template TEXT,
                default_emulator_id TEXT,
                platform_type TEXT,
                pc_config_json TEXT
            );

            CREATE TABLE IF NOT EXISTS roms (
                id TEXT PRIMARY KEY,
                platform_id TEXT NOT NULL,
                path TEXT NOT NULL,
                filename TEXT NOT NULL,
                file_size INTEGER,
                hash_sha1 TEXT,
                date_added INTEGER,
                boxart_path TEXT,
                icon_path TEXT,
                background_path TEXT,
                FOREIGN KEY(platform_id) REFERENCES platforms(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS metadata (
                rom_id TEXT PRIMARY KEY,
                title TEXT,
                description TEXT,
                rating REAL,
                release_date TEXT,
                developer TEXT,
                publisher TEXT,
                genre TEXT,
                tags TEXT,
                region TEXT,
                is_favorite INTEGER DEFAULT 0,
                play_count INTEGER DEFAULT 0,
                last_played INTEGER,
                total_play_time INTEGER DEFAULT 0,
                achievement_count INTEGER DEFAULT 0,
                achievement_unlocked INTEGER DEFAULT 0,
                ra_game_id INTEGER,
                ra_recent_badges TEXT,
                is_installed INTEGER DEFAULT 1,
                FOREIGN KEY(rom_id) REFERENCES roms(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS emulator_profiles (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                executable_path TEXT NOT NULL,
                arguments TEXT NOT NULL,
                is_retroarch INTEGER DEFAULT 0,
                retroarch_core TEXT
            );

            CREATE TABLE IF NOT EXISTS platform_emulators (
                 platform_id TEXT,
                 emulator_id TEXT,
                 FOREIGN KEY(platform_id) REFERENCES platforms(id) ON DELETE CASCADE,
                 FOREIGN KEY(emulator_id) REFERENCES emulator_profiles(id) ON DELETE CASCADE,
                 PRIMARY KEY (platform_id, emulator_id)
            );
            
            CREATE TABLE IF NOT EXISTS assets (
                rom_id TEXT NOT NULL,
                type TEXT NOT NULL,
                local_path TEXT NOT NULL,
                FOREIGN KEY(rom_id) REFERENCES roms(id) ON DELETE CASCADE,
                PRIMARY KEY (rom_id, type, local_path)
            );
            
            CREATE TABLE IF NOT EXISTS ignore_list (
                platform_id TEXT NOT NULL,
                path TEXT NOT NULL,
                PRIMARY KEY (platform_id, path),
                FOREIGN KEY(platform_id) REFERENCES platforms(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS playlists (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                created_at INTEGER
            );

            CREATE TABLE IF NOT EXISTS playlist_entries (
                playlist_id TEXT NOT NULL,
                rom_id TEXT NOT NULL,
                added_at INTEGER,
                FOREIGN KEY(playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
                FOREIGN KEY(rom_id) REFERENCES roms(id) ON DELETE CASCADE,
                PRIMARY KEY (playlist_id, rom_id)
            );

            CREATE TABLE IF NOT EXISTS platform_sources (
                platform_id TEXT NOT NULL,
                path TEXT NOT NULL,
                PRIMARY KEY (platform_id, path),
                FOREIGN KEY(platform_id) REFERENCES platforms(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS pc_configurations (
                rom_id TEXT PRIMARY KEY,
                umu_proton_version TEXT,
                umu_store TEXT,
                wine_prefix TEXT,
                working_dir TEXT,
                umu_id TEXT,
                env_vars TEXT,
                extra_args TEXT,
                proton_verb TEXT,
                disable_fixes INTEGER,
                no_runtime INTEGER,
                log_level TEXT,
                wrapper TEXT,
                use_gamescope INTEGER,
                gamescope_args TEXT,
                use_mangohud INTEGER,
                pre_launch_script TEXT,
                post_launch_script TEXT,
                cloud_saves_enabled INTEGER,
                cloud_save_path TEXT,
                cloud_save_auto_sync INTEGER,
                FOREIGN KEY(rom_id) REFERENCES roms(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS game_resources (
                id TEXT PRIMARY KEY,
                rom_id TEXT NOT NULL,
                type TEXT NOT NULL,
                url TEXT NOT NULL,
                label TEXT,
                FOREIGN KEY(rom_id) REFERENCES roms(id) ON DELETE CASCADE
            );

            COMMIT;",
        )?;

        // Migration: Ensure all tables have ON DELETE CASCADE where needed
        // We check 'roms' as a canary. If it doesn't have CASCADE, we recreate the tables.
        let roms_sql = self.conn.query_row(
            "SELECT sql FROM sqlite_master WHERE type='table' AND name='roms'",
            [],
            |row| row.get::<_, String>(0)
        ).unwrap_or_default();
        
        let resources_sql = self.conn.query_row(
            "SELECT sql FROM sqlite_master WHERE type='table' AND name='game_resources'",
            [],
            |row| row.get::<_, String>(0)
        ).unwrap_or_default();

        if !roms_sql.contains("ON DELETE CASCADE") || !resources_sql.contains("ON DELETE CASCADE") {
            log::info!("[Migration] Recreating tables with ON DELETE CASCADE for structural integrity...");
            
            // Disable FKs temporarily to allow dropping/recreating tables in any order
            let _ = self.conn.execute("PRAGMA foreign_keys = OFF;", []);
            
            let _ = self.conn.execute_batch(
                "BEGIN;
                 -- 1. Metadata
                 CREATE TABLE IF NOT EXISTS metadata_new (
                    rom_id TEXT PRIMARY KEY,
                    title TEXT, description TEXT, rating REAL, release_date TEXT, developer TEXT, publisher TEXT, genre TEXT, tags TEXT, region TEXT,
                    is_favorite INTEGER DEFAULT 0, play_count INTEGER DEFAULT 0, last_played INTEGER, total_play_time INTEGER DEFAULT 0,
                    achievement_count INTEGER DEFAULT 0, achievement_unlocked INTEGER DEFAULT 0, ra_game_id INTEGER, ra_recent_badges TEXT, is_installed INTEGER DEFAULT 1,
                    FOREIGN KEY(rom_id) REFERENCES roms(id) ON DELETE CASCADE
                 );
                 INSERT OR IGNORE INTO metadata_new SELECT * FROM metadata;
                 DROP TABLE metadata;
                 ALTER TABLE metadata_new RENAME TO metadata;

                 -- 2. Assets
                 CREATE TABLE IF NOT EXISTS assets_new (
                    rom_id TEXT NOT NULL,
                    type TEXT NOT NULL,
                    local_path TEXT NOT NULL,
                    FOREIGN KEY(rom_id) REFERENCES roms(id) ON DELETE CASCADE,
                    PRIMARY KEY (rom_id, type, local_path)
                 );
                 INSERT OR IGNORE INTO assets_new SELECT rom_id, type, local_path FROM assets;
                 DROP TABLE assets;
                 ALTER TABLE assets_new RENAME TO assets;

                 -- 3. PC Configurations
                 CREATE TABLE IF NOT EXISTS pc_configurations_new (
                    rom_id TEXT PRIMARY KEY,
                    umu_proton_version TEXT, umu_store TEXT, wine_prefix TEXT, working_dir TEXT, umu_id TEXT, env_vars TEXT, extra_args TEXT, proton_verb TEXT,
                    disable_fixes INTEGER, no_runtime INTEGER, log_level TEXT, wrapper TEXT, use_gamescope INTEGER, gamescope_args TEXT, use_mangohud INTEGER,
                    pre_launch_script TEXT, post_launch_script TEXT,
                    cloud_saves_enabled INTEGER, cloud_save_path TEXT, cloud_save_auto_sync INTEGER,
                    FOREIGN KEY(rom_id) REFERENCES roms(id) ON DELETE CASCADE
                 );
                 INSERT OR IGNORE INTO pc_configurations_new SELECT rom_id, umu_proton_version, umu_store, wine_prefix, working_dir, umu_id, env_vars, extra_args, proton_verb, disable_fixes, no_runtime, log_level, wrapper, use_gamescope, gamescope_args, use_mangohud, pre_launch_script, post_launch_script, NULL, NULL, NULL FROM pc_configurations;
                 DROP TABLE pc_configurations;
                 ALTER TABLE pc_configurations_new RENAME TO pc_configurations;

                 -- 4. Game Resources
                 CREATE TABLE IF NOT EXISTS game_resources_new (
                    id TEXT PRIMARY KEY,
                    rom_id TEXT NOT NULL,
                    type TEXT NOT NULL,
                    url TEXT NOT NULL,
                    label TEXT,
                    FOREIGN KEY(rom_id) REFERENCES roms(id) ON DELETE CASCADE
                 );
                 INSERT OR IGNORE INTO game_resources_new SELECT * FROM game_resources;
                 DROP TABLE game_resources;
                 ALTER TABLE game_resources_new RENAME TO game_resources;

                 -- 5. Playlist Entries
                 CREATE TABLE IF NOT EXISTS playlist_entries_new (
                    playlist_id TEXT NOT NULL,
                    rom_id TEXT NOT NULL,
                    added_at INTEGER,
                    FOREIGN KEY(playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
                    FOREIGN KEY(rom_id) REFERENCES roms(id) ON DELETE CASCADE,
                    PRIMARY KEY (playlist_id, rom_id)
                 );
                 INSERT OR IGNORE INTO playlist_entries_new SELECT * FROM playlist_entries;
                 DROP TABLE playlist_entries;
                 ALTER TABLE playlist_entries_new RENAME TO playlist_entries;

                 -- 6. Platform Emulators
                 CREATE TABLE IF NOT EXISTS platform_emulators_new (
                     platform_id TEXT,
                     emulator_id TEXT,
                     FOREIGN KEY(platform_id) REFERENCES platforms(id) ON DELETE CASCADE,
                     FOREIGN KEY(emulator_id) REFERENCES emulator_profiles(id) ON DELETE CASCADE,
                     PRIMARY KEY (platform_id, emulator_id)
                 );
                 INSERT OR IGNORE INTO platform_emulators_new SELECT * FROM platform_emulators;
                 DROP TABLE platform_emulators;
                 ALTER TABLE platform_emulators_new RENAME TO platform_emulators;

                 -- 7. Ignore List
                 CREATE TABLE IF NOT EXISTS ignore_list_new (
                    platform_id TEXT NOT NULL,
                    path TEXT NOT NULL,
                    PRIMARY KEY (platform_id, path),
                    FOREIGN KEY(platform_id) REFERENCES platforms(id) ON DELETE CASCADE
                 );
                 INSERT OR IGNORE INTO ignore_list_new SELECT * FROM ignore_list;
                 DROP TABLE ignore_list;
                 ALTER TABLE ignore_list_new RENAME TO ignore_list;

                 -- 8. Platform Sources
                 CREATE TABLE IF NOT EXISTS platform_sources_new (
                    platform_id TEXT NOT NULL,
                    path TEXT NOT NULL,
                    PRIMARY KEY (platform_id, path),
                    FOREIGN KEY(platform_id) REFERENCES platforms(id) ON DELETE CASCADE
                 );
                 INSERT OR IGNORE INTO platform_sources_new SELECT * FROM platform_sources;
                 DROP TABLE platform_sources;
                 ALTER TABLE platform_sources_new RENAME TO platform_sources;

                 -- 9. Roms (Needs to be done after its children are moved if we want to be safe, or just recreate)
                 CREATE TABLE IF NOT EXISTS roms_new (
                    id TEXT PRIMARY KEY,
                    platform_id TEXT NOT NULL,
                    path TEXT NOT NULL,
                    filename TEXT NOT NULL,
                    file_size INTEGER,
                    hash_sha1 TEXT,
                    date_added INTEGER,
                    boxart_path TEXT,
                    icon_path TEXT,
                    background_path TEXT,
                    FOREIGN KEY(platform_id) REFERENCES platforms(id) ON DELETE CASCADE
                 );
                 INSERT OR IGNORE INTO roms_new SELECT * FROM roms;
                 DROP TABLE roms;
                 ALTER TABLE roms_new RENAME TO roms;

                 COMMIT;"
            );
            
            // Re-enable FKs
            let _ = self.conn.execute("PRAGMA foreign_keys = ON;", []);
        }

        // Migration: Add default_emulator_id to platforms if missing
        let has_default_emulator_id = self.conn.prepare("SELECT default_emulator_id FROM platforms LIMIT 1")
            .is_ok();
        
        if !has_default_emulator_id {
            log::info!("[Migration] Adding default_emulator_id column to platforms table...");
            let _ = self.conn.execute("ALTER TABLE platforms ADD COLUMN default_emulator_id TEXT", []);
        }

        // Migration: Add is_installed to metadata if missing
        let has_is_installed = self.conn.prepare("SELECT is_installed FROM metadata LIMIT 1")
            .is_ok();
        
        if !has_is_installed {
            log::info!("[Migration] Adding is_installed column to metadata table...");
            let _ = self.conn.execute("ALTER TABLE metadata ADD COLUMN is_installed INTEGER DEFAULT 1", []);
            let _ = self.conn.execute("UPDATE metadata SET is_installed = 1 WHERE is_installed IS NULL", []);
        }

        // Migration: Add cloud save columns to pc_configurations if missing
        if self.conn.prepare("SELECT cloud_saves_enabled FROM pc_configurations LIMIT 1").is_err() {
            log::info!("[Migration] Adding cloud save columns to pc_configurations table...");
            let _ = self.conn.execute("ALTER TABLE pc_configurations ADD COLUMN cloud_saves_enabled INTEGER", []);
            let _ = self.conn.execute("ALTER TABLE pc_configurations ADD COLUMN cloud_save_path TEXT", []);
            let _ = self.conn.execute("ALTER TABLE pc_configurations ADD COLUMN cloud_save_auto_sync INTEGER", []);
        }

        Ok(())
    }

    pub fn get_connection(&self) -> &Connection {
        &self.conn
    }

    pub fn insert_platform_source(&self, platform_id: &str, path: &str) -> Result<()> {
        self.conn.execute(
            "INSERT OR IGNORE INTO platform_sources (platform_id, path) VALUES (?1, ?2)",
            params![platform_id, path],
        )?;
        Ok(())
    }

    pub fn get_platform_sources(&self, platform_id: &str) -> Result<Vec<String>> {
        let mut stmt = self.conn.prepare("SELECT path FROM platform_sources WHERE platform_id = ?1")?;
        let rows = stmt.query_map(params![platform_id], |row| row.get::<_, String>(0))?;
        let mut paths = Vec::new();
        for path in rows {
            paths.push(path?);
        }
        Ok(paths)
    }

    pub fn delete_platform_sources(&self, platform_id: &str) -> Result<()> {
        self.conn.execute(
            "DELETE FROM platform_sources WHERE platform_id = ?1",
            params![platform_id],
        )?;
        Ok(())
    }

    pub fn insert_platform(&self, platform: &Platform) -> Result<()> {
        self.conn.execute(
            "INSERT INTO platforms (id, slug, name, icon, extension_filter, command_template, default_emulator_id, platform_type, pc_config_json)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
             ON CONFLICT(id) DO UPDATE SET
                slug = excluded.slug,
                name = excluded.name,
                icon = COALESCE(excluded.icon, platforms.icon),
                extension_filter = excluded.extension_filter,
                command_template = excluded.command_template,
                default_emulator_id = excluded.default_emulator_id,
                platform_type = excluded.platform_type,
                pc_config_json = COALESCE(excluded.pc_config_json, platforms.pc_config_json)",
            params![
                platform.id,
                platform.slug,
                platform.name,
                platform.icon,
                platform.extension_filter,
                platform.command_template,
                platform.default_emulator_id,
                platform.platform_type,
                platform.pc_config_json
            ],
        )?;
        Ok(())
    }

    pub fn insert_rom(&self, rom: &Rom) -> Result<()> {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() as i64;
        
        let date_added = rom.date_added.unwrap_or(now);

        self.conn.execute(
            "INSERT INTO roms (id, platform_id, path, filename, file_size, hash_sha1, date_added, boxart_path, icon_path, background_path)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
             ON CONFLICT(id) DO UPDATE SET 
                platform_id = excluded.platform_id,
                path = excluded.path,
                filename = excluded.filename,
                file_size = excluded.file_size,
                hash_sha1 = excluded.hash_sha1,
                boxart_path = COALESCE(excluded.boxart_path, roms.boxart_path),
                icon_path = COALESCE(excluded.icon_path, roms.icon_path),
                background_path = COALESCE(excluded.background_path, roms.background_path)",
            params![
                rom.id,
                rom.platform_id,
                rom.path,
                rom.filename,
                rom.file_size,
                rom.hash_sha1,
                date_added,
                rom.boxart_path,
                rom.icon_path,
                rom.background_path
            ],
        )?;
        Ok(())
    }

    pub fn get_platforms(&self) -> Result<Vec<Platform>> {
        let mut stmt = self.conn.prepare("SELECT id, slug, name, icon, extension_filter, command_template, default_emulator_id, platform_type, pc_config_json FROM platforms")?;
        let rows = stmt.query_map([], |row| {
            Ok(Platform {
                id: row.get(0)?,
                slug: row.get(1)?,
                name: row.get(2)?,
                icon: row.get(3)?,
                extension_filter: row.get(4)?,
                command_template: row.get(5)?,
                default_emulator_id: row.get(6)?,
                platform_type: row.get(7)?,
                pc_config_json: row.get(8)?,
            })
        })?;

        let mut platforms = Vec::new();
        for platform in rows {
            platforms.push(platform?);
        }
        Ok(platforms)
    }

    pub fn get_platform(&self, id: &str) -> Result<Option<Platform>> {
        let mut stmt = self.conn.prepare("SELECT id, slug, name, icon, extension_filter, command_template, default_emulator_id, platform_type, pc_config_json FROM platforms WHERE id = ?1")?;
        let mut rows = stmt.query(params![id])?;
        if let Some(row) = rows.next()? {
            Ok(Some(Platform {
                id: row.get(0)?,
                slug: row.get(1)?,
                name: row.get(2)?,
                icon: row.get(3)?,
                extension_filter: row.get(4)?,
                command_template: row.get(5)?,
                default_emulator_id: row.get(6)?,
                platform_type: row.get(7)?,
                pc_config_json: row.get(8)?,
            }))
        } else {
            Ok(None)
        }
    }

    pub fn get_rom_paths_by_platform(&self, platform_id: &str) -> Result<std::collections::HashSet<String>> {
        let mut stmt = self.conn.prepare("SELECT path FROM roms WHERE platform_id = ?1")?;
        let rows = stmt.query_map(params![platform_id], |row| row.get::<_, String>(0))?;
        let mut paths = std::collections::HashSet::new();
        for path in rows {
            paths.insert(path?);
        }
        Ok(paths)
    }

    pub fn get_rom_ids_by_platform(&self, platform_id: &str) -> Result<std::collections::HashSet<String>> {
        let mut stmt = self.conn.prepare("SELECT id FROM roms WHERE platform_id = ?1")?;
        let rows = stmt.query_map(params![platform_id], |row| row.get::<_, String>(0))?;
        let mut ids = std::collections::HashSet::new();
        for id in rows {
            ids.insert(id?);
        }
        Ok(ids)
    }

    pub fn get_all_platforms(&self) -> Result<Vec<Platform>> {
        let mut stmt = self.conn.prepare("SELECT id, slug, name, icon, extension_filter, command_template, default_emulator_id, platform_type, pc_config_json FROM platforms")?;
        let platform_iter = stmt.query_map([], |row| {
            Ok(Platform {
                id: row.get(0)?,
                slug: row.get(1)?,
                name: row.get(2)?,
                icon: row.get(3)?,
                extension_filter: row.get(4)?,
                command_template: row.get(5)?,
                default_emulator_id: row.get(6)?,
                platform_type: row.get(7)?,
                pc_config_json: row.get(8)?,
            })
        })?;

        let mut platforms = Vec::new();
        for platform in platform_iter {
            platforms.push(platform?);
        }
        Ok(platforms)
    }

    pub fn get_all_platform_types(&self) -> Result<Vec<String>> {
        let mut stmt = self.conn.prepare("SELECT DISTINCT platform_type FROM platforms WHERE platform_type IS NOT NULL AND platform_type != '' ORDER BY platform_type ASC")?;
        let rows = stmt.query_map([], |row| row.get::<_, String>(0))?;
        let mut types = Vec::new();
        for row in rows {
            types.push(row?);
        }
        Ok(types)
    }

    pub fn get_all_roms(&self) -> Result<Vec<Rom>> {
        let mut stmt = self.conn.prepare("SELECT r.id, r.platform_id, r.path, r.filename, r.file_size, r.hash_sha1, r.date_added, r.boxart_path, r.icon_path, r.background_path, m.is_installed FROM roms r LEFT JOIN metadata m ON r.id = m.rom_id")?;
        let rom_iter = stmt.query_map([], |row| {
            Ok(Rom {
                id: row.get(0)?,
                platform_id: row.get(1)?,
                path: row.get(2)?,
                filename: row.get(3)?,
                file_size: row.get(4)?,
                hash_sha1: row.get(5)?,
                date_added: row.get(6)?,
                boxart_path: row.get::<_, Option<String>>(7).unwrap_or(None),
                icon_path: row.get::<_, Option<String>>(8).unwrap_or(None),
                background_path: row.get::<_, Option<String>>(9).unwrap_or(None),
                title: None,
                region: None,
                platform_name: None,
                platform_type: None,
                play_count: None,
                total_play_time: None,
                last_played: None,
                platform_icon: None,
                is_installed: Some(row.get::<_, Option<i32>>(10).ok().flatten().map(|v| v != 0).unwrap_or_else(|| {
                    let r_id: String = row.get(0).unwrap_or_default();
                    if r_id.starts_with("steam-") {
                        crate::core::store::StoreManager::get_local_steam_appids().contains(&r_id.replace("steam-", ""))
                    } else if r_id.starts_with("legendary-") {
                        false
                    } else {
                        true
                    }
                })),
                is_favorite: None,
                genre: None,
                developer: None,
                publisher: None,
                rating: None,
                tags: None,
                release_date: None,
                description: None,
            })
        })?;

        let mut roms = Vec::new();
        for rom in rom_iter {
            roms.push(rom?);
        }
        Ok(roms)
    }

    pub fn get_roms_by_platform(&self, platform_id: &str) -> Result<Vec<Rom>> {
        let mut stmt = self.conn.prepare("SELECT r.id, r.platform_id, r.path, r.filename, r.file_size, r.hash_sha1, r.date_added, r.boxart_path, r.icon_path, r.background_path, m.is_installed FROM roms r LEFT JOIN metadata m ON r.id = m.rom_id WHERE r.platform_id = ?1")?;
        let rom_iter = stmt.query_map(params![platform_id], |row| {
            Ok(Rom {
                id: row.get(0)?,
                platform_id: row.get(1)?,
                path: row.get(2)?,
                filename: row.get(3)?,
                file_size: row.get(4)?,
                hash_sha1: row.get(5)?,
                date_added: row.get(6)?,
                title: None,
                region: None,
                platform_name: None,
                platform_type: None,
                boxart_path: row.get::<_, Option<String>>(7).unwrap_or(None),
                play_count: None,
                total_play_time: None,
                last_played: None,
                platform_icon: None,
                icon_path: row.get::<_, Option<String>>(8).unwrap_or(None),
                background_path: row.get::<_, Option<String>>(9).unwrap_or(None),
                is_favorite: None,
                genre: None,
                developer: None,
                publisher: None,
                rating: None,
                tags: None,
                release_date: None,
                description: None,
                is_installed: Some(row.get::<_, Option<i32>>(10).ok().flatten().map(|v| v != 0).unwrap_or_else(|| {
                    let r_id: String = row.get(0).unwrap_or_default();
                    if r_id.starts_with("steam-") {
                        crate::core::store::StoreManager::get_local_steam_appids().contains(&r_id.replace("steam-", ""))
                    } else if r_id.starts_with("legendary-") {
                        false
                    } else {
                        true
                    }
                })),
            })
        })?;

        let mut roms = Vec::new();
        for rom in rom_iter {
            roms.push(rom?);
        }
        Ok(roms)
    }

    pub fn get_metadata(&self, rom_id: &str) -> Result<Option<crate::core::models::GameMetadata>> {
        let mut stmt = self.conn.prepare("SELECT rom_id, title, description, rating, release_date, developer, publisher, genre, tags, region, is_favorite, play_count, last_played, total_play_time, achievement_count, achievement_unlocked, ra_game_id, ra_recent_badges, is_installed FROM metadata WHERE rom_id = ?1")?;
        
        let mut rows = stmt.query(params![rom_id])?;
        
        if let Some(row) = rows.next()? {
            let resources = self.get_resources(rom_id).unwrap_or_default();
            Ok(Some(crate::core::models::GameMetadata {
                rom_id: row.get(0)?,
                title: row.get(1)?,
                description: row.get(2)?,
                rating: row.get(3)?,
                release_date: {
                    let val: Option<rusqlite::types::Value> = row.get(4)?;
                    match val {
                        Some(rusqlite::types::Value::Text(s)) => Some(s),
                        Some(rusqlite::types::Value::Integer(i)) => Some(i.to_string()),
                        Some(rusqlite::types::Value::Real(f)) => Some(f.to_string()),
                        _ => None,
                    }
                },
                developer: row.get(5)?,
                publisher: row.get(6)?,
                genre: row.get(7)?,
                tags: row.get(8)?,
                region: row.get(9)?,
                is_favorite: row.get::<_, i32>(10)? != 0,
                play_count: row.get(11)?,
                last_played: row.get(12)?,
                total_play_time: row.get(13)?,
                achievement_count: row.get(14).unwrap_or(Some(0)),
                achievement_unlocked: row.get(15).unwrap_or(Some(0)),
                ra_game_id: row.get::<_, Option<u64>>(16).unwrap_or(None),
                ra_recent_badges: row.get(17).unwrap_or(None),
                is_installed: row.get::<_, i32>(18)? != 0,
                resources: Some(resources),
            }))
        } else {
            Ok(None)
        }
    }

    pub fn get_launch_info(&self, rom_id: &str) -> Result<Option<(String, String, Option<String>, Option<String>)>> {
        let mut stmt = self.conn.prepare(
            "SELECT r.path, p.command_template, p.default_emulator_id, p.platform_type, p.pc_config_json 
             FROM roms r 
             JOIN platforms p ON r.platform_id = p.id 
             WHERE r.id = ?1"
        )?;

        let mut rows = stmt.query(params![rom_id])?;

        if let Some(row) = rows.next()? {
            let rom_path: String = row.get(0)?;
            let command_template: Option<String> = row.get(1)?;
            let emulator_id: Option<String> = row.get(2)?;
            let platform_type: Option<String> = row.get(3)?;
            let pc_config_json: Option<String> = row.get(4)?;

            if let Some(em_id) = emulator_id {
                if !em_id.is_empty() {
                    // Fetch from profile
                    let mut em_stmt = self.conn.prepare("SELECT executable_path, arguments FROM emulator_profiles WHERE id = ?1")?;
                    let mut em_rows = em_stmt.query(params![em_id])?;
                    
                    if let Some(em_row) = em_rows.next()? {
                        let exe: String = em_row.get(0)?;
                        let args: String = em_row.get(1)?;
                        let full_cmd = format!("{} {}", exe, args);
                        return Ok(Some((rom_path, full_cmd, platform_type, pc_config_json)));
                    } else {
                        // Emulator ID exists but profile not found in DB? Fallback to command template or empty
                        log::warn!("Emulator profile {} not found for platform/game. Falling back to command template.", em_id);
                    }
                }
            }

            // Fallback to command_template
            if let Some(cmd) = command_template {
                Ok(Some((rom_path, cmd, platform_type, pc_config_json)))
            } else {
                // Return platform_type anyway so we can handle manual PC launches
                Ok(Some((rom_path, "".to_string(), platform_type, pc_config_json)))
            }
        } else {
            Ok(None)
        }
    }

    pub fn get_rom_path_info(&self, rom_id: &str) -> Result<Option<(String, String)>> {
        let mut stmt = self.conn.prepare(
            "SELECT COALESCE(p.platform_type, p.name), r.filename 
             FROM roms r 
             JOIN platforms p ON r.platform_id = p.id 
             WHERE r.id = ?1"
        )?;
        let mut rows = stmt.query(params![rom_id])?;
        if let Some(row) = rows.next()? {
            Ok(Some((row.get(0)?, row.get(1)?)))
        } else {
            Ok(None)
        }
    }

    pub fn get_all_emulator_profiles(&self) -> Result<Vec<crate::core::models::EmulatorProfile>> {
        let mut stmt = self.conn.prepare("SELECT id, name, executable_path, arguments, is_retroarch, retroarch_core FROM emulator_profiles")?;
        let profile_iter = stmt.query_map([], |row| {
            Ok(crate::core::models::EmulatorProfile {
                id: row.get(0)?,
                name: row.get(1)?,
                executable_path: row.get(2)?,
                arguments: row.get(3)?,
                is_retroarch: row.get::<_, i32>(4)? != 0,
                retroarch_core: row.get(5)?,
            })
        })?;

        let mut profiles = Vec::new();
        for profile in profile_iter {
            profiles.push(profile?);
        }
        Ok(profiles)
    }

    pub fn get_emulator_profiles(&self, platform_id: &str) -> Result<Vec<crate::core::models::EmulatorProfile>> {
        let mut stmt = self.conn.prepare(
            "SELECT e.id, e.name, e.executable_path, e.arguments, e.is_retroarch, e.retroarch_core
             FROM emulator_profiles e
             JOIN platform_emulators pe ON e.id = pe.emulator_id
             WHERE pe.platform_id = ?1"
        )?;
        let profile_iter = stmt.query_map(params![platform_id], |row| {
            Ok(crate::core::models::EmulatorProfile {
                id: row.get(0)?,
                name: row.get(1)?,
                executable_path: row.get(2)?,
                arguments: row.get(3)?,
                is_retroarch: row.get::<_, i32>(4)? != 0,
                retroarch_core: row.get(5)?,
            })
        })?;

        let mut profiles = Vec::new();
        for profile in profile_iter {
            profiles.push(profile?);
        }
        Ok(profiles)
    }

    pub fn insert_emulator_profile(&self, profile: &crate::core::models::EmulatorProfile) -> Result<()> {
        self.conn.execute(
            "INSERT OR REPLACE INTO emulator_profiles (id, name, executable_path, arguments, is_retroarch, retroarch_core)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![
                profile.id,
                profile.name,
                profile.executable_path,
                profile.arguments,
                profile.is_retroarch as i32,
                profile.retroarch_core
            ],
        )?;
        Ok(())
    }

    pub fn delete_emulator_profile(&self, id: &str) -> Result<()> {
        self.conn.execute(
            "DELETE FROM emulator_profiles WHERE id = ?1",
            params![id],
        )?;
        Ok(())
    }

     pub fn delete_platform(&self, platform_id: &str) -> Result<()> {
         self.conn.execute("DELETE FROM platforms WHERE id = ?1", params![platform_id])?;
         Ok(())
     }

    pub fn update_platform(&self, id: &str, name: &str, extensions: &str, command: &str, emulator_id: Option<&str>, platform_type: Option<&str>, icon: Option<&str>) -> Result<()> {
        self.conn.execute(
            "UPDATE platforms SET name = ?1, extension_filter = ?2, command_template = ?3, default_emulator_id = ?4, platform_type = ?5, icon = ?6 WHERE id = ?7",
            params![name, extensions, command, emulator_id, platform_type, icon, id],
        )?;
        Ok(())
    }

    pub fn insert_metadata(&self, meta: &crate::core::models::GameMetadata) -> Result<()> {
        self.conn.execute(
            "INSERT OR REPLACE INTO metadata (rom_id, title, description, rating, release_date, developer, publisher, genre, tags, region, is_favorite, play_count, last_played, total_play_time, achievement_count, achievement_unlocked, ra_game_id, ra_recent_badges, is_installed)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19)",
            params![
                meta.rom_id,
                meta.title,
                meta.description,
                meta.rating,
                meta.release_date,
                meta.developer,
                meta.publisher,
                meta.genre,
                meta.tags,
                meta.region,
                meta.is_favorite as i32,
                meta.play_count,
                meta.last_played,
                meta.total_play_time,
                meta.achievement_count.unwrap_or(0),
                meta.achievement_unlocked.unwrap_or(0),
                meta.ra_game_id,
                meta.ra_recent_badges,
                meta.is_installed as i32
            ],
        )?;

        if let Some(resources) = &meta.resources {
            for res in resources {
                let _ = self.insert_resource(res);
            }
        }
        Ok(())
    }

    pub fn update_achievements(&self, rom_id: &str, count: i32, unlocked: i32, badges: Option<&str>) -> Result<()> {
        // Ensure row exists
        self.conn.execute("INSERT OR IGNORE INTO metadata (rom_id) VALUES (?1)", params![rom_id])?;
        
        self.conn.execute(
            "UPDATE metadata SET achievement_count = ?2, achievement_unlocked = ?3, ra_recent_badges = ?4 WHERE rom_id = ?1",
            params![rom_id, count, unlocked, badges]
        )?;
        Ok(())
    }

    pub fn bulk_update_playtimes(&self, updates: &[(String, i64, i64)]) -> Result<()> {
        self.conn.execute_batch("BEGIN;")?;
        
        let mut ins_stmt = self.conn.prepare("INSERT OR IGNORE INTO metadata (rom_id) VALUES (?1)")?;
        let mut upd_stmt = self.conn.prepare("UPDATE metadata SET total_play_time = MAX(COALESCE(total_play_time, 0), ?1), last_played = MAX(COALESCE(last_played, 0), ?2) WHERE rom_id = ?3")?;
        
        for (rom_id, playtime, last_played) in updates {
            let _ = ins_stmt.execute(params![rom_id]);
            let _ = upd_stmt.execute(params![playtime, last_played, rom_id]);
        }
        
        drop(ins_stmt);
        drop(upd_stmt);
        self.conn.execute_batch("COMMIT;")?;
        Ok(())
    }

    pub fn update_game_metadata_if_empty(&self, rom_id: &str, meta: &crate::core::models::GameMetadata) -> Result<()> {
        // Ensure row exists so UPDATE works
        self.conn.execute("INSERT OR IGNORE INTO metadata (rom_id) VALUES (?1)", params![rom_id])?;

        
        let _count = self.conn.execute(
            "UPDATE metadata SET 
                developer = CASE WHEN developer IS NULL OR developer = '' THEN ?2 ELSE developer END,
                publisher = CASE WHEN publisher IS NULL OR publisher = '' THEN ?3 ELSE publisher END,
                genre = CASE WHEN genre IS NULL OR genre = '' THEN ?4 ELSE genre END,
                release_date = CASE WHEN release_date IS NULL OR release_date = '' THEN ?5 ELSE release_date END,
                description = CASE WHEN description IS NULL OR description = '' THEN ?6 ELSE description END
             WHERE rom_id = ?1",
            params![
                rom_id,
                meta.developer,
                meta.publisher,
                meta.genre,
                meta.release_date,
                meta.description
            ]
        )?;
        
        // println!("DEBUG [DB]: Updated metadata for {}. Rows affected: {}", rom_id, count);
        Ok(())
    }

    pub fn update_rom_images_if_empty(&self, rom_id: &str, boxart: Option<&str>, icon: Option<&str>) -> Result<()> {
        if let Some(b) = boxart {
            self.conn.execute(
                "UPDATE roms SET boxart_path = ?1 WHERE id = ?2 AND (boxart_path IS NULL OR boxart_path = '')",
                params![b, rom_id]
            )?;
        }
        if let Some(i) = icon {
            self.conn.execute(
                "UPDATE roms SET icon_path = ?1 WHERE id = ?2 AND (icon_path IS NULL OR icon_path = '')",
                params![i, rom_id]
            )?;
        }
        Ok(())
    }

    pub fn update_rom_images(&self, rom_id: &str, boxart: Option<&str>, icon: Option<&str>) -> Result<()> {
         if let Some(b) = boxart {
             self.conn.execute("UPDATE roms SET boxart_path = ?1 WHERE id = ?2", params![b, rom_id])?;
         }
         if let Some(i) = icon {
             self.conn.execute("UPDATE roms SET icon_path = ?1 WHERE id = ?2", params![i, rom_id])?;
         }
         Ok(())
    }

    pub fn delete_rom(&self, rom_id: &str) -> Result<()> {
        self.conn.execute("DELETE FROM roms WHERE id = ?1", params![rom_id])?;
        Ok(())
    }

    pub fn insert_ignore_entry(&self, platform_id: &str, path: &str) -> Result<()> {
        self.conn.execute(
            "INSERT OR REPLACE INTO ignore_list (platform_id, path) VALUES (?1, ?2)",
            params![platform_id, path],
        )?;
        Ok(())
    }

    pub fn get_ignore_list(&self, platform_id: &str) -> Result<Vec<String>> {
        let mut stmt = self.conn.prepare("SELECT path FROM ignore_list WHERE platform_id = ?1")?;
        let rows = stmt.query_map(params![platform_id], |row| row.get::<_, String>(0))?;
        let mut list = Vec::new();
        for row in rows {
            list.push(row?);
        }
        Ok(list)
    }

    pub fn resource_exists(&self, rom_id: &str, url: &str) -> Result<bool> {
        let mut stmt = self.conn.prepare("SELECT COUNT(*) FROM game_resources WHERE rom_id = ?1 AND url = ?2")?;
        let count: i64 = stmt.query_row(params![rom_id, url], |row| row.get(0))?;
        Ok(count > 0)
    }

    pub fn get_all_ignored(&self) -> Result<Vec<(String, String)>> {
        let mut stmt = self.conn.prepare("SELECT platform_id, path FROM ignore_list")?;
        let rows = stmt.query_map([], |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)))?;
        let mut list = Vec::new();
        for row in rows {
            list.push(row?);
        }
        Ok(list)
    }

    pub fn remove_ignore_entry(&self, platform_id: &str, path: &str) -> Result<()> {
        self.conn.execute(
            "DELETE FROM ignore_list WHERE platform_id = ?1 AND path = ?2",
            params![platform_id, path],
        )?;
        Ok(())
    }

    pub fn insert_asset(&self, rom_id: &str, asset_type: &str, local_path: &str) -> Result<()> {
        self.conn.execute(
            "INSERT OR REPLACE INTO assets (rom_id, type, local_path) VALUES (?1, ?2, ?3)",
            params![rom_id, asset_type, local_path],
        )?;
        Ok(())
    }

    pub fn delete_assets_by_type(&self, rom_id: &str, asset_type: &str) -> Result<()> {
        self.conn.execute(
            "DELETE FROM assets WHERE rom_id = ?1 AND type = ?2",
            params![rom_id, asset_type],
        )?;
        Ok(())
    }

    pub fn get_assets(&self, rom_id: &str) -> Result<std::collections::HashMap<String, Vec<String>>> {
        let mut stmt = self.conn.prepare("SELECT type, local_path FROM assets WHERE rom_id = ?1")?;
        let rows = stmt.query_map(params![rom_id], |row| {
             Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })?;

        let mut assets: std::collections::HashMap<String, Vec<String>> = std::collections::HashMap::new();
        for row in rows {
            if let Ok((t, p)) = row {
                assets.entry(t).or_default().push(p);
            }
        }
        Ok(assets)
    }

    pub fn insert_resource(&self, res: &GameResource) -> Result<()> {
        self.conn.execute(
            "INSERT OR REPLACE INTO game_resources (id, rom_id, type, url, label) VALUES (?1, ?2, ?3, ?4, ?5)",
            params![res.id, res.rom_id, res.type_, res.url, res.label],
        )?;
        Ok(())
    }

    pub fn get_resources(&self, rom_id: &str) -> Result<Vec<GameResource>> {
        let mut stmt = self.conn.prepare("SELECT id, rom_id, type, url, label FROM game_resources WHERE rom_id = ?1")?;
        let rows = stmt.query_map(params![rom_id], |row| {
            Ok(GameResource {
                id: row.get(0)?,
                rom_id: row.get(1)?,
                type_: row.get(2)?,
                url: row.get(3)?,
                label: row.get(4)?,
            })
        })?;

        let mut resources = Vec::new();
        for row in rows {
            resources.push(row?);
        }
        Ok(resources)
    }

    pub fn delete_resource(&self, id: &str) -> Result<()> {
        self.conn.execute(
            "DELETE FROM game_resources WHERE id = ?1",
            params![id],
        )?;
        Ok(())
    }

    pub fn update_resource(&self, id: &str, type_: &str, url: &str, label: Option<&str>) -> Result<()> {
        self.conn.execute(
            "UPDATE game_resources SET type = ?1, url = ?2, label = ?3 WHERE id = ?4",
            params![type_, url, label, id],
        )?;
        Ok(())
    }

    pub fn get_pc_config(&self, rom_id: &str) -> Result<Option<crate::core::models::PcConfig>> {
        let mut stmt = self.conn.prepare(
            "SELECT rom_id, umu_proton_version, umu_store, wine_prefix, working_dir, umu_id, env_vars, extra_args, proton_verb, disable_fixes, no_runtime, log_level, wrapper, use_gamescope, gamescope_args, use_mangohud, pre_launch_script, post_launch_script, cloud_saves_enabled, cloud_save_path, cloud_save_auto_sync 
             FROM pc_configurations WHERE rom_id = ?1"
        )?;
        let mut rows = stmt.query(params![rom_id])?;
        if let Some(row) = rows.next()? {
            Ok(Some(crate::core::models::PcConfig {
                rom_id: row.get(0)?,
                umu_proton_version: row.get(1)?,
                umu_store: row.get(2)?,
                wine_prefix: row.get(3)?,
                working_dir: row.get(4)?,
                umu_id: row.get(5)?,
                env_vars: row.get(6)?,
                extra_args: row.get(7)?,
                proton_verb: row.get(8)?,
                disable_fixes: row.get(9)?,
                no_runtime: row.get(10)?,
                log_level: row.get(11)?,
                wrapper: row.get(12)?,
                use_gamescope: row.get(13)?,
                gamescope_args: row.get(14)?,
                use_mangohud: row.get(15)?,
                pre_launch_script: row.get(16)?,
                post_launch_script: row.get(17)?,
                cloud_saves_enabled: row.get::<_, Option<i32>>(18)?.map(|v| v != 0),
                cloud_save_path: row.get(19)?,
                cloud_save_auto_sync: row.get::<_, Option<i32>>(20)?.map(|v| v != 0),
            }))
        } else {
            Ok(None)
        }
    }

    pub fn insert_pc_config(&self, config: &crate::core::models::PcConfig) -> Result<()> {
        self.conn.execute(
            "INSERT OR REPLACE INTO pc_configurations (rom_id, umu_proton_version, umu_store, wine_prefix, working_dir, umu_id, env_vars, extra_args, proton_verb, disable_fixes, no_runtime, log_level, wrapper, use_gamescope, gamescope_args, use_mangohud, pre_launch_script, post_launch_script, cloud_saves_enabled, cloud_save_path, cloud_save_auto_sync)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21)",
            params![
                config.rom_id,
                config.umu_proton_version,
                config.umu_store,
                config.wine_prefix,
                config.working_dir,
                config.umu_id,
                config.env_vars,
                config.extra_args,
                config.proton_verb,
                config.disable_fixes,
                config.no_runtime,
                config.log_level,
                config.wrapper,
                config.use_gamescope,
                config.gamescope_args,
                config.use_mangohud,
                config.pre_launch_script,
                config.post_launch_script,
                config.cloud_saves_enabled.map(|b| b as i32),
                config.cloud_save_path,
                config.cloud_save_auto_sync.map(|b| b as i32),
            ],
        )?;
        Ok(())
    }

    pub fn get_ai_context(&self) -> Result<crate::core::models::AiContext> {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() as i64;
        let one_month_ago = now - (30 * 24 * 60 * 60);

        // 1. Recent Games (Last 5)
        let mut recent_stmt = self.conn.prepare(
            "SELECT title, last_played, total_play_time 
             FROM metadata 
             WHERE last_played IS NOT NULL AND last_played > 0
             ORDER BY last_played DESC 
             LIMIT 5"
        )?;
        
        let recent_games = recent_stmt.query_map([], |row| {
            Ok(crate::core::models::GameSession {
                title: row.get::<_, Option<String>>(0)?.unwrap_or("Unknown".to_string()),
                last_played: row.get(1)?,
                total_play_time: row.get(2)?,
            })
        })?.filter_map(|r| r.ok()).collect();

        // 2. Ignored Favorites (Favorites not played in 30 days)
        let mut fav_stmt = self.conn.prepare(
            "SELECT title, last_played, total_play_time 
             FROM metadata 
             WHERE is_favorite = 1 
             AND (last_played IS NULL OR last_played < ?1)
             ORDER BY RANDOM() 
             LIMIT 2"
        )?;

        let ignored_favorites = fav_stmt.query_map(params![one_month_ago], |row| {
             Ok(crate::core::models::GameSession {
                title: row.get::<_, Option<String>>(0)?.unwrap_or("Unknown".to_string()),
                last_played: row.get::<_, Option<i64>>(1)?.unwrap_or(0),
                total_play_time: row.get(2)?,
            })
        })?.filter_map(|r| r.ok()).collect();

        // 3. Near Completion (> 75% but < 100%)
        let mut prog_stmt = self.conn.prepare(
            "SELECT title, achievement_count, achievement_unlocked 
             FROM metadata 
             WHERE achievement_count > 0 
             AND (CAST(achievement_unlocked AS REAL) / achievement_count) > 0.75
             AND (CAST(achievement_unlocked AS REAL) / achievement_count) < 1.0
             LIMIT 3"
        )?;

        let near_completion = prog_stmt.query_map([], |row| {
            let count: i32 = row.get(1)?;
            let unlocked: i32 = row.get(2)?;
            let rate = if count > 0 { unlocked as f32 / count as f32 } else { 0.0 };
            
            Ok(crate::core::models::GameProgress {
                title: row.get::<_, Option<String>>(0)?.unwrap_or("Unknown".to_string()),
                achievement_count: count,
                achievement_unlocked: unlocked,
                completion_rate: rate,
            })
        })?.filter_map(|r| r.ok()).collect();

        Ok(crate::core::models::AiContext {
            recent_games,
            ignored_favorites,
            near_completion,
        })
    }

    // Playlist Management
    pub fn create_playlist(&self, name: &str) -> Result<String> {
        let id = uuid::Uuid::new_v4().to_string();
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() as i64;

        self.conn.execute(
            "INSERT INTO playlists (id, name, created_at) VALUES (?1, ?2, ?3)",
            params![id, name, now],
        )?;
        Ok(id)
    }

    pub fn delete_playlist(&self, id: &str) -> Result<()> {
        self.conn.execute_batch(&format!(
            "BEGIN;
             DELETE FROM playlist_entries WHERE playlist_id = '{0}';
             DELETE FROM playlists WHERE id = '{0}';
             COMMIT;",
            id
        ))
    }

    pub fn rename_playlist(&self, id: &str, new_name: &str) -> Result<()> {
        self.conn.execute(
            "UPDATE playlists SET name = ?1 WHERE id = ?2",
            params![new_name, id],
        )?;
        Ok(())
    }

    pub fn get_playlists(&self) -> Result<Vec<crate::core::models::Playlist>> {
        let mut stmt = self.conn.prepare("SELECT id, name, created_at FROM playlists ORDER BY name ASC")?;
        let rows = stmt.query_map([], |row| {
            Ok(crate::core::models::Playlist {
                id: row.get(0)?,
                name: row.get(1)?,
                created_at: row.get(2)?,
            })
        })?;

        let mut list = Vec::new();
        for row in rows {
            list.push(row?);
        }
        Ok(list)
    }

    pub fn add_to_playlist(&self, playlist_id: &str, rom_id: &str) -> Result<()> {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() as i64;
            
        self.conn.execute(
            "INSERT OR IGNORE INTO playlist_entries (playlist_id, rom_id, added_at) VALUES (?1, ?2, ?3)",
            params![playlist_id, rom_id, now],
        )?;
        Ok(())
    }

    pub fn remove_from_playlist(&self, playlist_id: &str, rom_id: &str) -> Result<()> {
        self.conn.execute(
            "DELETE FROM playlist_entries WHERE playlist_id = ?1 AND rom_id = ?2",
            params![playlist_id, rom_id],
        )?;
        Ok(())
    }

    // Get games for "Favorites", "Recently Played", or specific "Playlist"
    // Returns full Rom details joined with metadata
    pub fn get_library_view(&self, view_type: &str, id_filter: Option<&str>) -> Result<Vec<Rom>> {
         let mut sql = String::from(
            "SELECT r.id, r.platform_id, r.path, r.filename, r.file_size, r.hash_sha1, r.date_added,
                    p.name, p.platform_type,
                    m.title, m.region, m.play_count, m.total_play_time, m.last_played, p.icon, m.is_favorite,
                    COALESCE(r.boxart_path, a_box.local_path), 
                    COALESCE(r.icon_path, a_icon.local_path),
                    COALESCE(r.background_path, a_bg.local_path, a_ss.local_path),
                    m.is_installed
             FROM roms r
             JOIN platforms p ON r.platform_id = p.id
             LEFT JOIN metadata m ON r.id = m.rom_id 
             LEFT JOIN assets a_box ON r.id = a_box.rom_id AND a_box.type = 'Box - Front'
             LEFT JOIN assets a_icon ON r.id = a_icon.rom_id AND a_icon.type = 'Icon'
             LEFT JOIN assets a_bg ON r.id = a_bg.rom_id AND a_bg.type = 'Background'
             LEFT JOIN assets a_ss ON r.id = a_ss.rom_id AND a_ss.type = 'Screenshot' "
         );

         let mut params_vec: Vec<&dyn rusqlite::ToSql> = Vec::new();
         // Temporary owner for id_filter if needed
         let filter_val = id_filter.unwrap_or(""); 

         if view_type == "Favorites" {
             sql.push_str("WHERE m.is_favorite = 1 GROUP BY r.id ORDER BY m.title ASC");
         } else if view_type == "Recent" {
             sql.push_str("WHERE m.last_played IS NOT NULL AND m.last_played > 0 AND m.play_count > 0 GROUP BY r.id ORDER BY m.last_played DESC LIMIT 50");
         } else if view_type == "Playlist" {
             sql.push_str("JOIN playlist_entries pe ON r.id = pe.rom_id WHERE pe.playlist_id = ?1 GROUP BY r.id ORDER BY m.title ASC");
             params_vec.push(&filter_val);
         } else {
             // Default All
             sql.push_str("GROUP BY r.id ORDER BY m.title ASC");
         }

         let mut stmt = self.conn.prepare(&sql)?;
         let mut roms = Vec::new();
         if view_type == "Playlist" {
             let rows = stmt.query_map(params![filter_val], |row| self.row_to_rom(row))?;
             for row in rows {
                 roms.push(row?);
             }
         } else {
             let rows = stmt.query_map([], |row| self.row_to_rom(row))?;
             for row in rows {
                 roms.push(row?);
             }
         }
         Ok(roms)
    }

    pub fn get_random_game_by_genre(&self, genre: &str, exclude_id: &str) -> Result<Option<Rom>> {
        let sql = "SELECT r.id, r.platform_id, r.path, r.filename, r.file_size, r.hash_sha1, r.date_added,
                          p.name, p.platform_type,
                          m.title, m.region, m.play_count, m.total_play_time, m.last_played, p.icon, m.is_favorite,
                          COALESCE(r.boxart_path, a_box.local_path), 
                          COALESCE(r.icon_path, a_icon.local_path),
                          COALESCE(r.background_path, a_bg.local_path, a_ss.local_path)
                   FROM roms r
                   JOIN platforms p ON r.platform_id = p.id
                   LEFT JOIN metadata m ON r.id = m.rom_id
                   LEFT JOIN assets a_box ON r.id = a_box.rom_id AND a_box.type = 'Box - Front'
                   LEFT JOIN assets a_icon ON r.id = a_icon.rom_id AND a_icon.type = 'Icon'
                   LEFT JOIN assets a_bg ON r.id = a_bg.rom_id AND a_bg.type = 'Background'
                   LEFT JOIN assets a_ss ON r.id = a_ss.rom_id AND a_ss.type = 'Screenshot'
                   WHERE m.genre = ?1 AND r.id != ?2
                   ORDER BY RANDOM()
                   LIMIT 1";
        
        let mut stmt = self.conn.prepare(sql)?;
        let mut rows = stmt.query(params![genre, exclude_id])?;
        if let Some(row) = rows.next()? {
            Ok(Some(self.row_to_rom(row)?))
        } else {
            Ok(None)
        }
    }

    pub fn get_random_game(&self, exclude_id: Option<&str>) -> Result<Option<Rom>> {
        let mut sql = String::from("SELECT r.id, r.platform_id, r.path, r.filename, r.file_size, r.hash_sha1, r.date_added,
                          p.name, p.platform_type,
                          m.title, m.region, m.play_count, m.total_play_time, m.last_played, p.icon, m.is_favorite,
                          COALESCE(r.boxart_path, a_box.local_path), 
                          COALESCE(r.icon_path, a_icon.local_path),
                          COALESCE(r.background_path, a_bg.local_path, a_ss.local_path)
                   FROM roms r
                   JOIN platforms p ON r.platform_id = p.id
                   LEFT JOIN metadata m ON r.id = m.rom_id 
                   LEFT JOIN assets a_box ON r.id = a_box.rom_id AND a_box.type = 'Box - Front'
                   LEFT JOIN assets a_icon ON r.id = a_icon.rom_id AND a_icon.type = 'Icon'
                   LEFT JOIN assets a_bg ON r.id = a_bg.rom_id AND a_bg.type = 'Background'
                   LEFT JOIN assets a_ss ON r.id = a_ss.rom_id AND a_ss.type = 'Screenshot' ");
        
        let mut params_vec: Vec<String> = Vec::new();
        if let Some(id) = exclude_id {
            sql.push_str("WHERE r.id != ?1 ");
            params_vec.push(id.to_string());
        }
        
        sql.push_str("ORDER BY RANDOM() LIMIT 1");
        
        let mut stmt = self.conn.prepare(&sql)?;
        let mut rows = if params_vec.is_empty() {
            stmt.query([])?
        } else {
            stmt.query(params![params_vec[0]])?
        };

        if let Some(row) = rows.next()? {
            Ok(Some(self.row_to_rom(row)?))
        } else {
            Ok(None)
        }
    }

    pub fn row_to_rom(&self, row: &rusqlite::Row) -> std::result::Result<Rom, rusqlite::Error> {
        Ok(Rom {
            id: row.get(0)?,
            platform_id: row.get(1)?,
            path: row.get(2)?,
            filename: row.get(3)?,
            file_size: row.get(4)?,
            hash_sha1: row.get(5)?,
            date_added: row.get(6)?,
            platform_name: row.get(7)?,
            platform_type: row.get(8)?,
            title: row.get(9)?,
            region: row.get(10)?,
            play_count: row.get(11)?,
            total_play_time: row.get(12)?,
            last_played: row.get(13)?,
            platform_icon: row.get(14)?,
            is_favorite: Some(row.get::<_, i32>(15).unwrap_or(0) != 0),
            boxart_path: row.get(16).ok(), 
            icon_path: row.get(17).ok(),
            background_path: row.get(18).ok(),
            is_installed: Some(row.get::<_, i32>(19).unwrap_or(1) != 0),
            genre: None,
            developer: None,
            publisher: None,
            rating: None,
            tags: None,
            release_date: None,
            description: None,
        })
    }

    pub fn get_all_genres(&self) -> Result<Vec<String>> {
        let mut stmt = self.conn.prepare("SELECT DISTINCT genre FROM metadata WHERE genre IS NOT NULL AND genre != ''")?;
        let rows = stmt.query_map([], |row| row.get::<_, String>(0))?;
        let mut set = std::collections::HashSet::new();
        for row in rows {
            let s = row?;
            // Split by comma, semicolon, pipe, or full-width comma
            for part in s.split(|c| c == ',' || c == ';' || c == '|' || c == '，') {
                let mut trimmed = part.trim();
                // Also trim trailing punctuation (just in case)
                trimmed = trimmed.trim_matches(|c| c == '.' || c == ',');
                
                if !trimmed.is_empty() {
                    set.insert(trimmed.to_string());
                }
            }
        }
        let mut list: Vec<String> = set.into_iter().collect();
        list.sort();
        Ok(list)
    }

    pub fn get_all_tags(&self) -> Result<Vec<String>> {
        let mut stmt = self.conn.prepare("SELECT DISTINCT tags FROM metadata WHERE tags IS NOT NULL AND tags != ''")?;
        let rows = stmt.query_map([], |row| row.get::<_, String>(0))?;
        let mut set = std::collections::HashSet::new();
        for row in rows {
            let s = row?;
             // Split by comma, semicolon, pipe, or full-width comma
            for part in s.split(|c| c == ',' || c == ';' || c == '|' || c == '，') {
                let mut trimmed = part.trim();
                // Also trim trailing punctuation
                trimmed = trimmed.trim_matches(|c| c == '.' || c == ',');
                
                if !trimmed.is_empty() {
                    set.insert(trimmed.to_string());
                }
            }
        }
        let mut list: Vec<String> = set.into_iter().collect();
        list.sort();
        Ok(list)
    }

    pub fn get_all_developers(&self) -> Result<Vec<String>> {
        let mut stmt = self.conn.prepare("SELECT DISTINCT developer FROM metadata WHERE developer IS NOT NULL AND developer != ''")?;
        let rows = stmt.query_map([], |row| row.get::<_, String>(0))?;
        let mut set = std::collections::HashSet::new();
        for row in rows {
            let s = row?;
            for part in s.split(',') {
                let trimmed = part.trim();
                if !trimmed.is_empty() {
                    set.insert(trimmed.to_string());
                }
            }
        }
        let mut list: Vec<String> = set.into_iter().collect();
        list.sort();
        Ok(list)
    }

    pub fn get_all_publishers(&self) -> Result<Vec<String>> {
        let mut stmt = self.conn.prepare("SELECT DISTINCT publisher FROM metadata WHERE publisher IS NOT NULL AND publisher != ''")?;
        let rows = stmt.query_map([], |row| row.get::<_, String>(0))?;
        let mut set = std::collections::HashSet::new();
        for row in rows {
            let s = row?;
            for part in s.split(',') {
                let trimmed = part.trim();
                if !trimmed.is_empty() {
                    set.insert(trimmed.to_string());
                }
            }
        }
        let mut list: Vec<String> = set.into_iter().collect();
        list.sort();
        Ok(list)
    }

    pub fn get_all_regions(&self) -> Result<Vec<String>> {
        let mut stmt = self.conn.prepare("SELECT DISTINCT region FROM metadata WHERE region IS NOT NULL AND region != ''")?;
        let rows = stmt.query_map([], |row| row.get::<_, String>(0))?;
        let mut set = std::collections::HashSet::new();
        for row in rows {
            let s = row?;
            for part in s.split(',') {
                let trimmed = part.trim();
                if !trimmed.is_empty() {
                    set.insert(trimmed.to_string());
                }
            }
        }
        let mut list: Vec<String> = set.into_iter().collect();
        list.sort();
        Ok(list)
    }
}
