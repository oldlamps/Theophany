use rusqlite::{params, Connection, Result};
use std::path::Path;
use serde::Deserialize;

pub struct RaCache {
    conn: Connection,
}

#[derive(Debug, Deserialize)]
pub struct RaGameHash {
    #[serde(rename = "ID")]
    pub game_id: u64,
    #[serde(rename = "Title")]
    pub title: String,
    #[serde(rename = "ConsoleID")]
    pub console_id: u64,
    #[serde(rename = "MD5")]
    pub checksum: String,
}

#[derive(Debug)]
pub struct RaConsole {
    pub id: u64,
    pub name: String,
    pub is_active: bool,
}

impl RaCache {
    pub fn new<P: AsRef<Path>>(path: P) -> Result<Self> {
        let conn = Connection::open(path)?;
        let cache = RaCache { conn };
        cache.init_schema()?;
        Ok(cache)
    }

    fn init_schema(&self) -> Result<()> {
        self.conn.execute_batch(
            "BEGIN;
            CREATE TABLE IF NOT EXISTS ra_game_hashes (
                game_id INTEGER,
                console_id INTEGER,
                title TEXT,
                checksum TEXT,
                PRIMARY KEY (game_id, checksum)
            );
            CREATE INDEX IF NOT EXISTS idx_title_console ON ra_game_hashes (title, console_id);
            CREATE INDEX IF NOT EXISTS idx_console ON ra_game_hashes (console_id);
            CREATE TABLE IF NOT EXISTS ra_consoles (
                id INTEGER PRIMARY KEY,
                name TEXT,
                active INTEGER DEFAULT 1
            );
            COMMIT;",
        )?;
        Ok(())
    }

    pub fn has_cache(&self, console_id: u64) -> Result<bool> {
        let count: i64 = self.conn.query_row(
            "SELECT COUNT(*) FROM ra_game_hashes WHERE console_id = ?1 LIMIT 1",
            params![console_id],
            |row| row.get(0),
        )?;
        Ok(count > 0)
    }



    pub fn get_console_id_by_name(&self, name: &str) -> Result<Option<u64>> {
        let mut stmt = self.conn.prepare("SELECT id FROM ra_consoles WHERE name = ?1 LIMIT 1")?;
        let mut rows = stmt.query(params![name])?;
        
        if let Some(row) = rows.next()? {
            Ok(Some(row.get(0)?))
        } else {
            Ok(None)
        }
    }

    pub fn update_console_cache(&mut self, console_id: u64, hashes: Vec<RaGameHash>) -> Result<()> {
        let tx = self.conn.transaction()?;
        
        // Clear existing cache for this console to avoid stale data
        tx.execute("DELETE FROM ra_game_hashes WHERE console_id = ?1", params![console_id])?;

        {
            let mut stmt = tx.prepare(
                "INSERT INTO ra_game_hashes (game_id, console_id, title, checksum) VALUES (?1, ?2, ?3, ?4)"
            )?;

            for hash in hashes {
                stmt.execute(params![
                    hash.game_id, 
                    hash.console_id, 
                    hash.title, 
                    hash.checksum
                ])?;
            }
        }
        
        tx.commit()?;
        Ok(())
    }

    pub fn get_game_id(&self, console_id: u64, title: &str) -> Result<Option<u64>> {
         // Try exact match first
        let mut stmt = self.conn.prepare(
            "SELECT game_id FROM ra_game_hashes WHERE console_id = ?1 AND title = ?2 LIMIT 1"
        )?;
        
        let mut rows = stmt.query(params![console_id, title])?;
        
        if let Some(row) = rows.next()? {
             Ok(Some(row.get(0)?))
        } else {
            // Optional: Implement fuzzy matching logic here if desired later
            Ok(None)
        }
    }
    pub fn get_console_games(&self, console_id: u64) -> Result<Vec<(u64, String)>> {
        let mut stmt = self.conn.prepare(
            "SELECT game_id, title FROM ra_game_hashes WHERE console_id = ?1"
        )?;
        
        let rows = stmt.query_map(params![console_id], |row| {
            Ok((row.get(0)?, row.get(1)?))
        })?;

        let mut result = Vec::new();
        for row in rows {
            result.push(row?);
        }
        Ok(result)
    }
}
