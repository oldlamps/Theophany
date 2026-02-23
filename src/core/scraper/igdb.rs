use crate::core::scraper::{ScrapedMetadata, ScraperSearchResult, ScraperProvider, client::ScraperClient};
use async_trait::async_trait;
use std::sync::Arc;
use anyhow::Result;
use serde_json::Value;

pub struct IGDBProvider {
    client: Arc<ScraperClient>,
    base_url: String,
    ax_token: String,
}

impl IGDBProvider {
    pub fn new(client: Arc<ScraperClient>) -> Self {
        Self {
            client,
            base_url: "https://theophany.gg/api".to_string(), // No trailing slash, will append /games
            ax_token: "old-lamps-for-new-42".to_string(),
        }
    }

    fn get_headers(&self) -> Vec<(String, String)> {
        vec![
            ("x-app-secret".to_string(), self.ax_token.clone()),
            ("Accept".to_string(), "application/json".to_string()),
            ("Content-Type".to_string(), "text/plain".to_string()),
        ]
    }

    pub fn map_platform_id_static(platform_name: &str) -> Option<i32> {
        // Basic mapping for common platforms to IGDB IDs
        // This improves search relevance significantly
        // Reference: https://api-docs.igdb.com/?javascript#platform
        let p = platform_name.to_lowercase();
        
        // Nintendo
        if p.contains("snes") || p.contains("super nintendo") || p.contains("super famicom") || p == "sfc" { return Some(19); }
        if p.contains("nes") || (p.contains("nintendo") && p.contains("system")) || p.contains("famicom") { return Some(18); }
        if p.contains("n64") || p.contains("nintendo 64") { return Some(4); }
        if p.contains("gamecube") || p.contains("ngc") { return Some(21); }
        if p.contains("switch") { return Some(130); }
        if p.contains("gba") || p.contains("game boy advance") { return Some(24); }
        if p.contains("gbc") || p.contains("game boy color") { return Some(22); }
        if p.contains("gb") || p.contains("game boy") { return Some(33); }
        if p.contains("nds") || p.contains("nintendo ds") { return Some(20); }
        if p.contains("3ds") { return Some(37); }
        if p.contains("wii u") { return Some(41); }
        if p.contains("wii") { return Some(5); }
        if p.contains("virtual boy") || p == "vb" { return Some(87); }
        if p.contains("pokemon mini") { return Some(166); }
        
        // PlayStation
        if p.contains("ps2") || p.contains("playstation 2") { return Some(8); }
        if p.contains("ps3") || p.contains("playstation 3") { return Some(9); }
        if p.contains("ps4") || p.contains("playstation 4") { return Some(48); }
        if p.contains("ps5") || p.contains("playstation 5") { return Some(167); }
        if p.contains("ps1") || p.contains("psx") || p.contains("playstation") { return Some(7); }
        if p.contains("psp") { return Some(38); }
        if p.contains("vita") { return Some(46); }
        
        // Xbox
        if p.contains("xbox 360") { return Some(12); }
        if p.contains("xbox one") { return Some(49); }
        if p.contains("xbox series") { return Some(169); }
        if p.contains("xbox") { return Some(11); }
        
        // Sega
        if p.contains("genesis") || p.contains("mega drive") || p.contains("megadrive") || p == "md" { return Some(29); }
        if p.contains("dreamcast") || p == "dc" { return Some(23); }
        if p.contains("saturn") || p == "sat" { return Some(32); }
        if p.contains("master system") || p == "sms" { return Some(64); }
        if p.contains("game gear") || p == "gg" { return Some(35); }
        if p.contains("sega cd") || p.contains("mega cd") || p.contains("segacd") || p.contains("megacd") { return Some(78); }
        if p.contains("32x") { return Some(30); }
        if p.contains("sg-1000") || p == "sg1000" { return Some(25); }

        // Others
        if p.contains("arcade") || p.contains("mame") { return Some(52); }
        if p.contains("windows") || p.contains("pc") || p.contains("dos") || p.contains("heroic") || p.contains("lutris") || p.contains("steam") || p.contains("linux") || p.contains("epic") || p.contains("legendary") { return Some(6); }
        if p.contains("amiga") { return Some(16); }
        if p.contains("commodore 64") || p == "c64" { return Some(15); }
        if p.contains("atari 2600") || p == "a2600" { return Some(59); }
        if p.contains("atari 5200") || p == "a5200" { return Some(60); }
        if p.contains("atari 7800") || p == "a7800" { return Some(62); }
        if p.contains("lynx") { return Some(28); }
        if p.contains("neo geo") || p == "neo-geo" { return Some(79); } // Neo Geo MVS
        if p.contains("neo geo pocket color") || p == "ngpc" { return Some(27); }
        if p.contains("neo geo pocket") || p == "ngp" { return Some(26); }
        if p.contains("3do") { return Some(50); }
        if p.contains("turbografx") || p.contains("pce") || p.contains("engine") || p.contains("tg16") { return Some(86); }
        if p.contains("wonderswan color") || p == "wsc" { return Some(123); }
        if p.contains("wonderswan") || p == "ws" { return Some(57); }
        if p.contains("colecovision") { return Some(44); }
        if p.contains("intellivision") { return Some(45); }
        if p.contains("odyssey 2") || p == "odyssey2" || p.contains("videopac") { return Some(67); }
        
        None
    }
}

#[async_trait]
impl ScraperProvider for IGDBProvider {
    fn name(&self) -> &'static str {
        "IGDB"
    }

    async fn search(&self, query: &str, _platform: Option<&str>) -> Result<Vec<ScraperSearchResult>> {
        let url = format!("{}/games", self.base_url);
        
        // Sanitize and normalize query for Apicalypse string
        let mut normalized_query = query.to_lowercase();
        
        // 1. Handle ", the" at the end (e.g. "Legend of Zelda, The" -> "The Legend of Zelda")
        if normalized_query.ends_with(", the") {
            normalized_query = format!("the {}", &normalized_query[..normalized_query.len() - 5].trim());
        }

        // 2. Remove special symbols that can confuse search: ™ ® ©
        normalized_query = normalized_query.replace("™", "")
                                         .replace("®", "")
                                         .replace("©", "");

        // 3. Remove problematic punctuation: commas and colons
        normalized_query = normalized_query.replace(",", " ")
                                         .replace(":", " ");

        // 4. Final sanitization for JSON/Apicalypse
        let safe_query = normalized_query.replace("\"", "\\\"");
        
        // Use fuzzy search. We fetch platforms to handle filtering on the client side.
        // This is more robust than strict server-side filtering which can fail if IDs or slugs don't match perfectly.
        let body = format!(
            "fields name, alternative_names.name, platforms.name, first_release_date, cover.url, summary, screenshots.url, artworks.url, total_rating; \
             search \"{}\"; limit 20;", 
            safe_query
        );

        log::debug!("[IGDB] Sending Search Body: {}", body);

        let response = match self.client.post_raw(&url, body, self.get_headers()).await {
            Ok(res) => res,
            Err(e) => {
                log::error!("[IGDB] Request failed: {}", e);
                return Err(e);
            }
        };
        
        log::debug!("[IGDB] Response received ({} bytes)", response.len());
        
        let json: Value = serde_json::from_str(&response)?;
        
        if json.is_null() || (json.is_array() && json.as_array().unwrap().is_empty()) {
             log::warn!("[IGDB] No results for query: {}", safe_query);
        }

        let mut results = Vec::new();

        if let Some(arr) = json.as_array() {
            for item in arr {
                let id = item["id"].as_u64().unwrap_or(0).to_string();
                let title = item["name"].as_str().unwrap_or("").to_string();
                
                let mut platforms_vec = Vec::new();
                let mut platform_ids = Vec::new();
                if let Some(platforms) = item["platforms"].as_array() {
                    for p in platforms {
                        if let Some(name) = p["name"].as_str() {
                            platforms_vec.push(name.to_string());
                        }
                        if let Some(p_id) = p["id"].as_i64() {
                            platform_ids.push(p_id as i32);
                        }
                    }
                }
                
                let platforms_str = platforms_vec.join(", ");

                let release_year = item["first_release_date"].as_i64()
                    .map(|ts| {
                         1970 + (ts / 31536000) as i32
                    });

                let rating = item["total_rating"].as_f64().map(|r| (r / 10.0) as f32);

                let thumbnail_url = item["cover"]["url"].as_str().map(|u| {
                    if u.starts_with("//") {
                        format!("https:{}", u)
                    } else {
                        u.to_string()
                    }
                });

                // Construct metadata for search results (can be used as fallback or for rich preview)
                let mut metadata = ScrapedMetadata::default();
                metadata.source = "IGDB".to_string();
                metadata.source_id = id.clone();
                metadata.title = title.clone();
                metadata.description = item["summary"].as_str().unwrap_or("").to_string();
                metadata.release_year = release_year;
                metadata.rating = rating;
                
                let fix_url = |url: &str, size: &str| -> String {
                    let u = if url.starts_with("//") { format!("https:{}", url) } else { url.to_string() };
                    u.replace("t_thumb", size)
                };

                if let Some(cover) = item["cover"]["url"].as_str() {
                    metadata.assets.entry("Box - Front".to_string())
                        .or_default()
                        .push(fix_url(cover, "t_original"));
                }

                if let Some(screens) = item["screenshots"].as_array() {
                    for screen in screens {
                        if let Some(u) = screen["url"].as_str() {
                            metadata.assets.entry("Screenshot".to_string())
                                .or_default()
                                .push(fix_url(u, "t_1080p"));
                        }
                    }
                }

                if let Some(arts) = item["artworks"].as_array() {
                    for art in arts {
                        if let Some(u) = art["url"].as_str() {
                            metadata.assets.entry("Background".to_string())
                                .or_default()
                                .push(fix_url(u, "t_1080p"));
                        }
                    }
                }

                results.push(ScraperSearchResult {
                    id,
                    title,
                    platform: platforms_str,
                    platforms: Some(platforms_vec),
                    platform_ids: Some(platform_ids),
                    region: None,
                    release_year,
                    thumbnail_url,
                    resolution: None,
                    can_add_to_collection: true,
                    metadata: Some(metadata),
                });
            }
        }

        Ok(results)
    }

    async fn fetch_details(&self, result_id: &str) -> Result<ScrapedMetadata> {
        let url = format!("{}/games", self.base_url);
        
        // Fetch detailed fields
        // involved_companies.company.name needed for dev/pub
        let body = format!(
            "fields name, summary, first_release_date, genres.name, \
            involved_companies.company.name, involved_companies.developer, involved_companies.publisher, \
            cover.url, artworks.url, screenshots.url, total_rating; \
            where id = {};", 
            result_id
        );

        let response = self.client.post_raw(&url, body, self.get_headers()).await?;
         let json: Value = serde_json::from_str(&response)?;
        
        let item = json.as_array().and_then(|a| a.first())
            .ok_or_else(|| anyhow::anyhow!("No game found with ID {}", result_id))?;

        let mut metadata = ScrapedMetadata::default();
        metadata.source = "IGDB".to_string();
        metadata.source_id = result_id.to_string();
        metadata.title = item["name"].as_str().unwrap_or("").to_string();
        metadata.description = item["summary"].as_str().unwrap_or("").to_string();
        
        // Date
        if let Some(ts) = item["first_release_date"].as_i64() {
             metadata.release_year = Some(1970 + (ts / 31536000) as i32);
        }

        // Rating (IGDB is 0-100, we use 0-10)
        if let Some(r) = item["total_rating"].as_f64() {
            metadata.rating = Some((r / 10.0) as f32);
        }

        // Genres
        if let Some(genres) = item["genres"].as_array() {
            let names: Vec<String> = genres.iter()
                .filter_map(|g| g["name"].as_str().map(|s| s.to_string()))
                .collect();
            metadata.genre = names.join(", ");
        }

        // Developer / Publisher
        if let Some(companies) = item["involved_companies"].as_array() {
            for c in companies {
                let name = c["company"]["name"].as_str().unwrap_or("");
                if c["developer"].as_bool().unwrap_or(false) {
                    if !metadata.developer.is_empty() { metadata.developer.push_str(", "); }
                    metadata.developer.push_str(name);
                }
                if c["publisher"].as_bool().unwrap_or(false) {
                    if !metadata.publisher.is_empty() { metadata.publisher.push_str(", "); }
                    metadata.publisher.push_str(name);
                }
            }
        }

        // Assets
        // Helper to fix URLs (IGDB returns //images.igdb.com/...)
        // and upgrade quality (t_thumb to t_original or t_1080p)
        let fix_url = |url: &str, size: &str| -> String {
            let u = if url.starts_with("//") { format!("https:{}", url) } else { url.to_string() };
            u.replace("t_thumb", size)
        };

        if let Some(cover) = item["cover"]["url"].as_str() {
            metadata.assets.entry("Box - Front".to_string())
                .or_default()
                .push(fix_url(cover, "t_original"));
        }

        if let Some(arts) = item["artworks"].as_array() {
            for art in arts {
                if let Some(u) = art["url"].as_str() {
                    metadata.assets.entry("Background".to_string())
                        .or_default()
                        .push(fix_url(u, "t_1080p"));
                }
            }
        }

        if let Some(screens) = item["screenshots"].as_array() {
             for screen in screens {
                if let Some(u) = screen["url"].as_str() {
                    metadata.assets.entry("Screenshot".to_string())
                        .or_default()
                        .push(fix_url(u, "t_1080p"));
                }
            }
        }

        Ok(metadata)
    }
}
