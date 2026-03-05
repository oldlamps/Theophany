#![allow(dead_code)]
use serde::{Deserialize, Serialize};
use std::process::Command;
use std::path::{Path, PathBuf};
use walkdir::WalkDir;
use crate::core::models::Rom;
use uuid::Uuid;

#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct FlatpakApp {
    pub app_id: String,
    pub name: String,
    pub summary: String,
    pub icon_url: Option<String>,
    pub version: Option<String>,
    pub developer: Option<String>,
    pub sub_categories: Vec<String>,
    pub trending: Option<f64>,
    pub installs_last_month: Option<i64>,
    pub added_at: Option<i64>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct StoreSearchResponse {
    pub results: Vec<FlatpakApp>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct FeaturedContent {
    pub app_of_the_day: Option<FlatpakAppDetails>,
    pub trending: Vec<FlatpakApp>,
    pub popular: Vec<FlatpakApp>,
    pub new_releases: Vec<FlatpakApp>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct Screenshot {
    pub src: String,
    pub width: Option<serde_json::Value>, // Can be string "1920" or int
    pub height: Option<serde_json::Value>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct FlatpakAppDetails {
    pub app_id: String,
    pub name: String,
    pub summary: String,
    pub description: String,
    pub icon: Option<String>,
    pub developer_name: Option<String>,
    pub project_license: Option<String>,
    pub screenshots: Vec<Screenshot>,
    // Flathub specific fields
    #[serde(default)]
    pub categories: Vec<String>,
    #[serde(default)]
    pub keywords: Vec<String>,
}

pub struct StoreManager;

impl StoreManager {
    /// Searches Flathub for games.
    pub fn search_flathub(query: &str) -> anyhow::Result<Vec<FlatpakApp>> {
        let client = reqwest::blocking::Client::new();
        let body = serde_json::json!({
            "query": query,
            // Categories filter is currently causing internal server errors on Flathub's API v2 search
            /*"filters": [
                {
                    "filterType": "category",
                    "value": "Game"
                }
            ]*/
        });

        let resp = client.post("https://flathub.org/api/v2/search")
            .json(&body)
            .send()?
            .json::<serde_json::Value>()?;

        Self::parse_apps_from_hits(&resp)
    }

    /// Fetches detailed app info from Flathub
    pub fn get_app_details(app_id: &str) -> anyhow::Result<FlatpakAppDetails> {
        let client = reqwest::blocking::Client::new();
        let url = format!("https://flathub.org/api/v2/appstream/{}", app_id);
        
        let resp = client.get(&url)
            .send()?
            .json::<serde_json::Value>()?;

        // Helper to extract nested screenshots
        let mut screenshots = Vec::new();
        if let Some(ss_array) = resp["screenshots"].as_array() {
            for item in ss_array {
                if let Some(sizes) = item["sizes"].as_array() {
                    // Grab the first one usually being high res, or find "orig"
                    if let Some(best) = sizes.first() {
                         screenshots.push(Screenshot {
                             src: best["src"].as_str().unwrap_or_default().to_string(),
                             width: Some(best["width"].clone()),
                             height: Some(best["height"].clone()),
                         });
                    }
                }
            }
        }
        
        // Handle icon field which might be a string or object in some API versions
        let icon_url = resp["icon"].as_str().map(|s| s.to_string());

        let details = FlatpakAppDetails {
            app_id: resp["id"].as_str().or(resp["app_id"].as_str()).unwrap_or_default().to_string(),
            name: resp["name"].as_str().unwrap_or_default().to_string(),
            summary: resp["summary"].as_str().unwrap_or_default().to_string(),
            description: resp["description"].as_str().unwrap_or_default().to_string(),
            icon: icon_url,
            developer_name: resp["developer_name"].as_str().map(|s| s.to_string()),
            project_license: resp["project_license"].as_str().map(|s| s.to_string()),
            screenshots,
            categories: resp["categories"].as_array().map(|a| a.iter().map(|v| v.as_str().unwrap_or_default().to_string()).collect()).unwrap_or_default(),
            keywords: resp["keywords"].as_array().map(|a| a.iter().map(|v| v.as_str().unwrap_or_default().to_string()).collect()).unwrap_or_default(),
        };

        Ok(details)
    }

    /// Fetches a list of games from Flathub (default storefront view).
    pub fn browse_flathub(category: &str) -> anyhow::Result<Vec<FlatpakApp>> {
        let client = reqwest::blocking::Client::new();
        
        // If category is "Featured", we should use fetch_featured_games instead, but this acts as fallback
        // or for the "All Games" view if we had one.
        
        let url = if category.is_empty() || category == "Featured" || category == "Game" {
             "https://flathub.org/api/v2/collection/category/Game".to_string()
        } else {
             format!("https://flathub.org/api/v2/collection/category/Game/subcategories?subcategory={}", category)
        };
        
        log::info!("Fetching Flathub games from: {}", url);
        
        let resp = client.get(&url)
            .send()?
            .json::<serde_json::Value>()?;

        Self::parse_apps_from_hits(&resp)
    }

    /// Fetches featured content for the main page.
    pub fn fetch_featured_games() -> anyhow::Result<FeaturedContent> {
        let client = reqwest::blocking::Client::new();
        
        // 1. App of the Day
        let date_str = chrono::Local::now().format("%Y-%m-%d").to_string();
        let aotd_url = format!("https://flathub.org/api/v2/app-picks/app-of-the-day/{}", date_str);
        
        let mut app_of_the_day: Option<FlatpakAppDetails> = None;
        if let Ok(resp) = client.get(&aotd_url).send() {
            if let Ok(json) = resp.json::<serde_json::Value>() {
                 if let Some(app_id) = json.get("app_id").and_then(|v| v.as_str()) {
                     // Check if it's a game or emulator, or just fallback to showing it (it's "Featured" after all)
                     if let Ok(details) = Self::get_app_details(app_id) {
                         // Relaxed filter: Allow if it has "Game" valid category OR if it's the specific App of the Day
                         // Users might want to see the App of the Day regardless.
                         app_of_the_day = Some(details);
                     }
                 }
            }
        }

        let mut games_pool: Vec<FlatpakApp> = Vec::new();
        let url = "https://flathub.org/api/v2/collection/category/Game?sort=trending";
        if let Ok(resp) = client.get(url).send() {
            if let Ok(json) = resp.json::<serde_json::Value>() {
                if let Ok(apps) = Self::parse_apps_from_hits(&json) {
                    games_pool = apps;
                    log::info!("Fetched {} games for featured processing", games_pool.len());
                }
            }
        }
        
        // Helper to clone and sort
        let get_sorted = |mut apps: Vec<FlatpakApp>, sort_fn: fn(&FlatpakApp, &FlatpakApp) -> std::cmp::Ordering| -> Vec<FlatpakApp> {
            apps.sort_by(sort_fn);
            apps.into_iter().take(15).collect()
        };

        // Trending: Sort by trending score (descending)
        let trending = get_sorted(games_pool.clone(), |a, b| {
            b.trending.partial_cmp(&a.trending).unwrap_or(std::cmp::Ordering::Equal)
        });

        // Popular: Sort by installs_last_month (descending)
        let popular = get_sorted(games_pool.clone(), |a, b| {
            b.installs_last_month.unwrap_or(0).cmp(&a.installs_last_month.unwrap_or(0))
        });

        // New: Sort by added_at (descending)
        let new_releases = get_sorted(games_pool.clone(), |a, b| {
            b.added_at.unwrap_or(0).cmp(&a.added_at.unwrap_or(0))
        });

        Ok(FeaturedContent {
            app_of_the_day,
            trending,
            popular,
            new_releases,
        })
    }

    fn parse_apps_from_hits(resp: &serde_json::Value) -> anyhow::Result<Vec<FlatpakApp>> {
        let mut apps = Vec::new();
        if let Some(hits) = resp["hits"].as_array() {
            for hit in hits {
                let mut sub_cats: Vec<String> = hit["sub_categories"]
                    .as_array()
                    .map(|arr| arr.iter().filter_map(|v| v.as_str().map(|s| s.to_string())).collect())
                    .unwrap_or_default();
                
                // Also grab main categories if available to help with filtering
                if let Some(main) = hit["main_categories"].as_array() {
                    for m in main {
                         if let Some(s) = m.as_str() {
                             sub_cats.push(s.to_string());
                         }
                    }
                }

                apps.push(FlatpakApp {
                    app_id: hit["app_id"].as_str().or(hit["id"].as_str()).unwrap_or_default().to_string(),
                    name: hit["name"].as_str().unwrap_or_default().to_string(),
                    summary: hit["summary"].as_str().unwrap_or_default().to_string(),
                    icon_url: Some(hit["icon_url"].as_str().or(hit["icon"].as_str()).unwrap_or_default().to_string()),
                    version: Some(hit["version"].as_str().unwrap_or_default().to_string()),
                    developer: Some(hit["developer_name"].as_str().or(hit["developer"].as_str()).unwrap_or_default().to_string()),
                    sub_categories: sub_cats,
                    trending: hit.get("trending").and_then(|v| v.as_f64()),
                    installs_last_month: hit.get("installs_last_month").and_then(|v| v.as_i64()),
                    added_at: hit.get("added_at").and_then(|v| v.as_i64()),
                });
            }
        }
        Ok(apps)
    }

    /// Installs a Flatpak application with detailed metadata.
    pub fn install_flatpak_with_details(
        app_id: &str, 
        description: &str, 
        screenshots: &[crate::core::store::Screenshot],
        icon_url: &str
    ) -> anyhow::Result<()> {
        
        // 1. Run the installation
        Self::install_flatpak(app_id)?;
        
        // Box Front (Use first screenshot or icon if no screenshots)
        if !icon_url.is_empty() {
             let _ = Self::download_media(app_id, icon_url, "Box - Front");
             // Also save as "Icon" for list view
             let _ = Self::download_media(app_id, icon_url, "Icon");
             // Also try to save as Clear Logo if it looks like a logo (often icons are logos)
             let _ = Self::download_media(app_id, icon_url, "Clear Logo");
        }
        
        // Screenshots
        for (i, ss) in screenshots.iter().enumerate() {
            if i >= 5 { break; } // Limit to 5 screenshots
            let _ = Self::download_media(app_id, &ss.src, "Screenshot");
        }


        // Strategy: Save a sidecar JSON in the same media folder which is unique to the app.
        // ~/.local/share/theophany/Images/PC (Linux)/{AppId}/metadata.json
        let metadata_dir = crate::core::paths::get_data_dir()
            .join("Images")
            .join("PC (Linux)")
            .join(app_id);
            
        if !metadata_dir.exists() {
             let _ = std::fs::create_dir_all(&metadata_dir);
        }
        
        let metadata_path = metadata_dir.join("metadata.json");
        let metadata = serde_json::json!({
            "description": description,
            "app_id": app_id
        });
        
        if let Ok(file) = std::fs::File::create(metadata_path) {
            let _ = serde_json::to_writer_pretty(file, &metadata);
        }

        Ok(())
    }

    /// Installs a Flatpak application.
    pub fn install_flatpak(app_id: &str) -> anyhow::Result<()> {
        let is_flatpak = std::path::Path::new("/.flatpak-info").exists();
        
        let mut cmd = if is_flatpak {
            let mut c = Command::new("flatpak-spawn");
            c.arg("--host").arg("flatpak");
            c
        } else {
            Command::new("flatpak")
        };

        let status = cmd
            .arg("install")
            .arg("--user")
            .arg("-y")
            .arg("--noninteractive")
            .arg(app_id)
            .status()?;

        if !status.success() {
            return Err(anyhow::anyhow!("Flatpak install failed with status: {}", status));
        }

        Ok(())
    }

    fn download_media(app_id: &str, url: &str, media_type: &str) -> anyhow::Result<String> {
        let base_dir = crate::core::paths::get_data_dir()
            .join("Images")
            .join("PC (Linux)")
            .join(app_id)
            .join(media_type);

        if !base_dir.exists() {
            std::fs::create_dir_all(&base_dir)?;
        }

        // Create a filename from the URL or a random one + extension
        let ext = if url.contains(".svg") { "svg" } else { "png" }; // Simple heuristic, better to check header or url path
        // Actually best to look at the URL path
        let url_path = Path::new(url);
        let final_ext = url_path.extension().and_then(|s| s.to_str()).unwrap_or(ext);
        
        let filename = format!("{}.{}", Uuid::new_v4(), final_ext);
        let target_path = base_dir.join(&filename);
        
        // If specific media types like Box Front, we might want to clear existing or just add.
        // For Screenshots, adding is fine. For Box Front, maybe we want just one.
        if media_type == "Box - Front" || media_type == "Clear Logo" {
            // Remove existing files in this dir to avoid clutter/ambiguity
            let _ = std::fs::remove_dir_all(&base_dir);
            let _ = std::fs::create_dir_all(&base_dir);
        }

        let mut resp = reqwest::blocking::get(url)?;
        if !resp.status().is_success() {
            return Err(anyhow::anyhow!("Download failed with status: {}", resp.status()));
        }
        let mut file = std::fs::File::create(&target_path)?;
        std::io::copy(&mut resp, &mut file)?;
        
        Ok(target_path.to_string_lossy().to_string())
    }

    /// Finds the absolute path to a system icon.
    pub fn find_icon_path(icon_name: &str) -> Option<String> {
        if icon_name.is_empty() { return None; }
        // If it's already an absolute path, return it
        if icon_name.starts_with('/') {
            return Some(icon_name.to_string());
        }

        // Use linicon for robust lookup
        if let Some(Ok(icon)) = linicon::lookup_icon(icon_name).with_size(48).next() {
             return Some(icon.path.to_string_lossy().to_string());
        }
        
        // Fallback: search common locations if linicon fails
        let common_paths = vec![
            "/usr/share/pixmaps",
            "/usr/share/icons/hicolor/48x48/apps",
            "/usr/share/icons/hicolor/scalable/apps",
        ];

        for base in common_paths {
            let path = Path::new(base).join(format!("{}.png", icon_name));
            if path.exists() { return Some(path.to_string_lossy().to_string()); }
            let path = Path::new(base).join(format!("{}.svg", icon_name));
            if path.exists() { return Some(path.to_string_lossy().to_string()); }
        }

        None
    }

    /// Scans for local .desktop files that are categorized as Games.
    pub fn scan_local_apps() -> Vec<Rom> {
        let mut apps = Vec::new();
        let is_flatpak = std::path::Path::new("/.flatpak-info").exists();
        
        let mut search_paths = Vec::new();

        // System paths
        if is_flatpak {
            // In Flatpak, we need to look at /run/host for system-wide applications
            // assuming we have --filesystem=/usr/share/applications:ro
            search_paths.push(PathBuf::from("/run/host/usr/share/applications"));
            search_paths.push(PathBuf::from("/run/host/usr/local/share/applications"));
            search_paths.push(PathBuf::from("/run/host/var/lib/flatpak/exports/share/applications"));
        } else {
            search_paths.push(PathBuf::from("/usr/share/applications"));
            search_paths.push(PathBuf::from("/usr/local/share/applications"));
            search_paths.push(PathBuf::from("/var/lib/flatpak/exports/share/applications"));
        }

        if let Ok(home) = std::env::var("HOME") {
            let home_path = PathBuf::from(home);
            if is_flatpak {
              
                search_paths.push(home_path.join(".local/share/applications"));
                search_paths.push(home_path.join(".local/share/flatpak/exports/share/applications"));
            } else {
                search_paths.push(home_path.join(".local/share/applications"));
                search_paths.push(home_path.join(".local/share/flatpak/exports/share/applications"));
            }
        }

        for path in search_paths {
            if !path.exists() { continue; }
            log::info!("Scanning directory: {:?}", path);
            for entry in WalkDir::new(path).max_depth(1).into_iter().filter_map(|e| e.ok()) {
                if entry.path().extension().and_then(|s| s.to_str()) == Some("desktop") {
                    if let Some(rom) = Self::parse_desktop_file(entry.path()) {
                        apps.push(rom);
                    }
                }
            }
        }
        apps
    }

    /// Downloads and caches an icon from a URL.
    pub fn cache_icon(url: &str, app_id: &str) -> Option<String> {
        let cache_dir = crate::core::paths::get_assets_dir().join("cache").join("icons").join("flatpak");
        let _ = std::fs::create_dir_all(&cache_dir);
        
        let ext = if url.contains(".svg") { "svg" } else { "png" };
        let icon_path = cache_dir.join(format!("{}.{}", app_id, ext));
        
        if icon_path.exists() {
            return Some(icon_path.to_string_lossy().to_string());
        }

        log::info!("Caching icon for {}: {}", app_id, url);
        if let Ok(mut resp) = reqwest::blocking::get(url) {
            if let Ok(mut file) = std::fs::File::create(&icon_path) {
                if let Ok(_) = std::io::copy(&mut resp, &mut file) {
                    return Some(icon_path.to_string_lossy().to_string());
                }
            }
        }
        None
    }

    fn parse_desktop_file(path: &Path) -> Option<Rom> {
        let content = std::fs::read_to_string(path).ok()?;
        let mut name = None;
        let mut exec = None;
        let mut icon = None;
        let mut is_game = false;

        for line in content.lines() {
            if line.starts_with("Name=") && name.is_none() {
                name = Some(line[5..].to_string());
            } else if line.starts_with("Exec=") && exec.is_none() {
                exec = Some(line[5..].to_string());
            } else if line.starts_with("Icon=") && icon.is_none() {
                icon = Some(line[5..].to_string());
            } else if line.starts_with("Categories=") {
                if line.to_lowercase().contains("game;") || line.to_lowercase().ends_with("game") {
                    is_game = true;
                }
            }
        }

        if is_game && name.is_some() && exec.is_some() {
             let mut final_path = path.to_string_lossy().to_string();
             if final_path.contains("flatpak/exports") {
                 if let Some(stem) = path.file_stem() {
                     final_path = format!("flatpak://{}", stem.to_string_lossy());
                 }
             }

             return Some(Rom {
                id: Uuid::new_v4().to_string(),
                platform_id: "local-app".to_string(), // Transient ID
                path: final_path,
                filename: path.file_name().unwrap_or_default().to_string_lossy().to_string(),
                file_size: 0,
                hash_sha1: None,
                title: name,
                region: None,
                platform_name: Some("Local App".to_string()),
                platform_type: Some("PC (Linux)".to_string()),
                boxart_path: None,
                date_added: None,
                play_count: None,
                total_play_time: None,
                last_played: None,
                platform_icon: None,
                is_favorite: None,
                genre: None,
                developer: None,
                publisher: None,
                rating: None,
                tags: None,
                icon_path: icon, 
                background_path: None,
                release_date: None,
                description: None,
                is_installed: Some(true),
                cloud_saves_supported: None,
                resources: None,
             });
        }

        None
    }
    pub fn detect_local_steam_ids() -> Vec<String> {
        let mut ids = Vec::new();
        if let Ok(home) = std::env::var("HOME") {
            let config_paths = vec![
                PathBuf::from(&home).join(".steam/steam/config/loginusers.vdf"),
                PathBuf::from(&home).join(".local/share/Steam/config/loginusers.vdf"),
                PathBuf::from(&home).join(".var/app/com.valvesoftware.Steam/.steam/steam/config/loginusers.vdf"),
            ];

            for path in config_paths {
                if path.exists() {
                    if let Ok(content) = std::fs::read_to_string(&path) {
                        for line in content.lines() {
                            let trimmed = line.trim();
                            if trimmed.starts_with("\"7656") && trimmed.ends_with("\"") {
                                let id = trimmed.trim_matches('"').to_string();
                                if !ids.contains(&id) {
                                    ids.push(id);
                                }
                            }
                        }
                    }
                }
            }
        }
        ids
    }

    pub fn get_local_steam_appids() -> std::collections::HashSet<String> {
        let mut appids = std::collections::HashSet::new();
        // Use logic similar to scan_steam_games to find .acf files
        let mut steam_roots = Vec::new();
        if let Ok(home) = std::env::var("HOME") {
            let home_p = PathBuf::from(home);
            let paths = vec![
                home_p.join(".steam/steam"),
                home_p.join(".local/share/Steam"),
                home_p.join(".var/app/com.valvesoftware.Steam/.steam/steam"),
                home_p.join(".var/app/com.valvesoftware.Steam/.local/share/Steam"),
                PathBuf::from("/usr/share/steam"),
            ];
            for p in paths {
                if p.exists() && !steam_roots.contains(&p) {
                    steam_roots.push(p);
                }
            }
        }

        let mut library_paths = Vec::new();
        for root in &steam_roots {
            let vdf_path = root.join("steamapps/libraryfolders.vdf");
            if vdf_path.exists() {
                if let Ok(content) = std::fs::read_to_string(&vdf_path) {
                    for line in content.lines() {
                        let trimmed = line.trim();
                        if trimmed.starts_with("\"path\"") {
                            let parts: Vec<&str> = trimmed.split('\"').collect();
                            if parts.len() >= 4 {
                                library_paths.push(PathBuf::from(parts[3]));
                            }
                        }
                    }
                }
            }
            let root_apps = root.join("steamapps");
            if root_apps.exists() && !library_paths.contains(&root) {
                if !library_paths.iter().any(|p| p.join("steamapps") == root_apps) {
                    library_paths.push(root.clone());
                }
            }
        }

        for lib in library_paths {
            let apps_dir = lib.join("steamapps");
            if !apps_dir.exists() { continue; }
            if let Ok(entries) = std::fs::read_dir(apps_dir) {
                for entry in entries.filter_map(|e| e.ok()) {
                    let path = entry.path();
                    if path.extension().and_then(|s| s.to_str()) == Some("acf") {
                        if let Some(stem) = path.file_stem().and_then(|s| s.to_str()) {
                            if stem.starts_with("appmanifest_") {
                                let id = stem.replace("appmanifest_", "");
                                appids.insert(id);
                            }
                        }
                    }
                }
            }
        }
        appids
    }

    pub fn fetch_remote_steam_games(steam_id: &str, api_key: &str) -> anyhow::Result<Vec<Rom>> {
        let client = reqwest::blocking::Client::new();
        let url = format!(
            "http://api.steampowered.com/IPlayerService/GetOwnedGames/v0001/?key={}&steamid={}&format=json&include_appinfo=true&include_played_free_games=true",
            api_key, steam_id
        );

        let resp = client.get(&url).send()?.json::<serde_json::Value>()?;
        let local_ids = Self::get_local_steam_appids();
        
        let mut apps = Vec::new();
        if let Some(games) = resp["response"]["games"].as_array() {
            for game in games {
                if let Some(appid) = game["appid"].as_i64() {
                    let title = game["name"].as_str().unwrap_or("Unknown Game").to_string();
                    let playtime = game["playtime_forever"].as_i64().unwrap_or(0);
                    let rtime_last_played = game["rtime_last_played"].as_i64().unwrap_or(0);
                    
                    if title.starts_with("Proton") || 
                       title.starts_with("Steam Linux Runtime") ||
                       title.ends_with("Soundtrack") ||
                       title.ends_with("Bonus Content") {
                        continue;
                    }

                    let icon_hash = game["img_icon_url"].as_str().unwrap_or("");
                    let icon_url = if !icon_hash.is_empty() {
                        format!("https://cdn.akamai.steamstatic.com/steamcommunity/public/images/apps/{}/{}.jpg", appid, icon_hash)
                    } else {
                        // Fallback to high-res icon if hash is missing (rare but possible)
                        format!("https://cdn.akamai.steamstatic.com/steam/apps/{}/icon.jpg", appid)
                    };

                    let boxart_url = format!("https://cdn.akamai.steamstatic.com/steam/apps/{}/library_600x900.jpg", appid);
                    let background_url = format!("https://cdn.akamai.steamstatic.com/steam/apps/{}/library_hero.jpg", appid);

                    let is_installed = local_ids.contains(&appid.to_string());
                    
                    // For remote games, we always provide the CDN URLs. 
                    // BulkImporter will download them if needed.
                    let final_icon = if !icon_url.is_empty() { Some(icon_url) } else { None };

                    apps.push(Rom {
                        id: format!("steam-{}", appid),
                        platform_id: "steam".to_string(),
                        path: format!("steam://rungameid/{}", appid),
                        filename: format!("{}.acf", appid),
                        file_size: 0,
                        hash_sha1: None,
                        title: Some(title),
                        region: None,
                        platform_name: Some("Steam".to_string()),
                        platform_type: Some("PC (Linux)".to_string()),
                        date_added: None,
                        play_count: Some(0),
                        total_play_time: Some(playtime * 60),
                        last_played: if rtime_last_played > 0 { Some(rtime_last_played) } else { None },
                        platform_icon: Some("steam".to_string()),
                        is_favorite: Some(false),
                        genre: None,
                        developer: None,
                        publisher: None,
                        rating: None,
                        tags: None,
                        icon_path: final_icon,
                        background_path: Some(background_url),
                        boxart_path: Some(boxart_url),
                        release_date: None,
                        description: None,
                        is_installed: Some(is_installed),
                        cloud_saves_supported: None,
                        resources: None,
                    });
                }
            }
        } else {
            return Err(anyhow::anyhow!("Failed to parse response or no games found"));
        }

        Ok(apps)
    }

    pub fn fetch_steam_game_achievements(app_id: &str, steam_id: &str, api_key: &str) -> anyhow::Result<serde_json::Value> {
        let client = reqwest::blocking::Client::new();
        
        // 1. Fetch User Achievements (Unlocked status)
        let stats_url = format!(
            "http://api.steampowered.com/ISteamUserStats/GetPlayerAchievements/v0001/?appid={}&key={}&steamid={}&format=json",
            app_id, api_key, steam_id
        );
        let stats_resp = client.get(&stats_url).send()?.json::<serde_json::Value>()?;
        
        // 2. Fetch Game Schema (Titles, Descriptions, Icons)
        let schema_url = format!(
            "http://api.steampowered.com/ISteamUserStats/GetSchemaForGame/v2/?key={}&appid={}&format=json",
            api_key, app_id
        );
        let schema_resp = client.get(&schema_url).send()?.json::<serde_json::Value>()?;
        
        let mut results = serde_json::Map::new();
        let mut unlocked_count = 0;
        let mut total_count = 0;
        let mut merged_list = Vec::new();

        // Create a map of API name -> Unlocked (bool)
        let mut user_achievements = std::collections::HashMap::new();
        
        if let Some(success) = stats_resp["playerstats"]["success"].as_bool() {
            if success {
                if let Some(achievements) = stats_resp["playerstats"]["achievements"].as_array() {
                    for ach in achievements {
                        if let Some(apiname) = ach["apiname"].as_str() {
                            let achieved = ach["achieved"].as_i64().unwrap_or(0) == 1;
                            let unlock_time = ach["unlocktime"].as_u64().unwrap_or(0);
                            user_achievements.insert(apiname.to_string(), (achieved, unlock_time));
                        }
                    }
                }
            } else {
                return Err(anyhow::anyhow!("Failed or hidden achievements. Steam user might not have profile public."));
            }
        } else {
            return Err(anyhow::anyhow!("Failed or hidden achievements. Request failed."));
        }

        // Merge with Schema
        if let Some(schema_achievements) = schema_resp["game"]["availableGameStats"]["achievements"].as_array() {
            for ach in schema_achievements {
                total_count += 1;
                let mut merged_ach = ach.as_object().unwrap().clone();
                let apiname = ach["name"].as_str().unwrap_or("");
                
                let (is_unlocked, unlock_time) = user_achievements.get(apiname).unwrap_or(&(false, 0));
                
                if *is_unlocked {
                    unlocked_count += 1;
                }
                
                merged_ach.insert("unlocked".to_string(), serde_json::Value::Bool(*is_unlocked));
                merged_ach.insert("unlock_time".to_string(), serde_json::Value::Number(serde_json::Number::from(*unlock_time)));
                
                // Keep naming consistent with QML expectations (badgeName -> icon, title -> displayName)
                merged_list.push(serde_json::Value::Object(merged_ach));
            }
        }

        results.insert("success".to_string(), serde_json::Value::Bool(true));
        results.insert("unlocked_count".to_string(), serde_json::Value::Number(serde_json::Number::from(unlocked_count)));
        results.insert("total_count".to_string(), serde_json::Value::Number(serde_json::Number::from(total_count)));
        results.insert("achievements".to_string(), serde_json::Value::Array(merged_list));
        
        Ok(serde_json::Value::Object(results))
    }

    /// Scans for installed Steam games across all library folders.
    pub fn scan_steam_games() -> Vec<Rom> {
        let mut apps = Vec::new();
        let mut steam_roots = Vec::new();

        if let Ok(home) = std::env::var("HOME") {
            let home_p = PathBuf::from(home);
            // Common paths for Steam
            let paths = vec![
                home_p.join(".steam/steam"),
                home_p.join(".local/share/Steam"),
                home_p.join(".var/app/com.valvesoftware.Steam/.steam/steam"),
                home_p.join(".var/app/com.valvesoftware.Steam/.local/share/Steam"),
                PathBuf::from("/usr/share/steam"),
            ];
            for p in paths {
                if p.exists() {
                    steam_roots.push(p);
                }
            }
        }

        let mut library_paths = Vec::new();

        for root in &steam_roots {
            let vdf_path = root.join("steamapps/libraryfolders.vdf");
            if vdf_path.exists() {
                if let Ok(content) = std::fs::read_to_string(&vdf_path) {
                    // Extract all "path" values from VDF
                    for line in content.lines() {
                        let trimmed = line.trim();
                        if trimmed.starts_with("\"path\"") {
                            let parts: Vec<&str> = trimmed.split('\"').collect();
                            if parts.len() >= 4 {
                                library_paths.push(PathBuf::from(parts[3]));
                            }
                        }
                    }
                }
            }
            // Add root's own steamapps just in case it wasn't in VDF (rare)
            let root_apps = root.join("steamapps");
            if root_apps.exists() && !library_paths.contains(&root) {
                // libraryfolders.vdf paths point to the DIR CONTAINING steamapps
                if !library_paths.iter().any(|p| p.join("steamapps") == root_apps) {
                    library_paths.push(root.clone());
                }
            }
        }

        // Deduplicate and filter non-existent paths
        library_paths.sort();
        library_paths.dedup();

        let mut seen_app_ids = std::collections::HashSet::new();

        for lib in library_paths {
            let apps_dir = lib.join("steamapps");
            if !apps_dir.exists() { continue; }

            for entry in WalkDir::new(&apps_dir).max_depth(1).into_iter().filter_map(|e| e.ok()) {
                let path = entry.path();
                if path.extension().and_then(|s| s.to_str()) == Some("acf") {
                    if let Some(rom) = Self::parse_steam_acf(path, &steam_roots) {
                        // Filter Logic
                        if let Some(title) = &rom.title {
                            if title.starts_with("Proton") || 
                               title.starts_with("Steam Linux Runtime") ||
                               title.ends_with("Soundtrack") ||
                               title.ends_with("Bonus Content") {
                                continue;
                            }
                        }

                        // Deduplication Logic
                        let app_id_clean = rom.id.replace("steam-", "");
                        if !seen_app_ids.contains(&app_id_clean) {
                            seen_app_ids.insert(app_id_clean);
                            apps.push(rom);
                        }
                    }
                }
            }
        }

        apps
    }

    fn find_steam_icon(id: &str, steam_roots: &[PathBuf]) -> Option<String> {
        // 1. Check System Icons (Hicolor)
        let resolutions = ["256x256", "128x128", "64x64", "48x48", "32x32", "16x16"];
        
        // Check local share first
        if let Ok(home) = std::env::var("HOME") {
            let home_icons = PathBuf::from(home).join(".local/share/icons/hicolor");
            for res in &resolutions {
                let p = home_icons.join(res).join("apps").join(format!("steam_icon_{}.png", id));
                if p.symlink_metadata().is_ok() {
                    return Some(p.to_string_lossy().to_string());
                }
            }
        }
        
        // Check system share
        let system_icons = PathBuf::from("/usr/share/icons/hicolor");
        for res in &resolutions {
            let p = system_icons.join(res).join("apps").join(format!("steam_icon_{}.png", id));
            if p.symlink_metadata().is_ok() {
                return Some(p.to_string_lossy().to_string());
            }
        }

        // 2. Fallback: appcache/librarycache/{id}_icon.jpg (Legacy/Known)
        for root in steam_roots {
            let cache_p = root.join("appcache/librarycache").join(format!("{}_icon.jpg", id));
            if cache_p.exists() {
                return Some(cache_p.to_string_lossy().to_string());
            }
        }

        // 3. Fallback: Scan appcache/librarycache/{id}/ for any image that looks like an icon
        for root in steam_roots {
            let cache_dir = root.join("appcache/librarycache").join(id);
            if cache_dir.exists() && cache_dir.is_dir() {
                if let Ok(entries) = std::fs::read_dir(cache_dir) {
                    for entry in entries.flatten() {
                        let path = entry.path();
                        if let Ok(fft) = entry.file_type() {
                            if fft.is_file() || fft.is_symlink() {
                                let ext = path.extension().and_then(|s| s.to_str()).unwrap_or("");
                                if ext == "jpg" || ext == "png" {
                                    let filename = path.file_name().and_then(|s| s.to_str()).unwrap_or("");
                                    // Skip known non-icon assets
                                    if filename == "header.jpg" || 
                                       filename == "library_hero.jpg" || 
                                       filename == "library_hero_blur.jpg" ||
                                       filename == "library_600x900.jpg" ||
                                       filename == "logo.png" ||
                                       filename == "icon.jpg" || // Skip self if we already have it in local assets
                                       filename == "icon.png" {
                                        continue;
                                    }
                                    // Usually the icon is a hashed filename like 06f134e7...jpg
                                    // We prefer small JPGs (32x32) found in these folders
                                    return Some(path.to_string_lossy().to_string());
                                }
                            }
                        }
                    }
                }
            }
        }

        None
    }

    fn find_steam_boxart(id: &str, steam_roots: &[PathBuf]) -> Option<String> {
        for root in steam_roots {
            let cache_dir = root.join("appcache/librarycache");
            let candidates = [
                cache_dir.join(format!("{}_library_600x900.jpg", id)),
                cache_dir.join(format!("{}_library_600x900.png", id)),
                cache_dir.join(id).join("library_600x900.jpg"),
                cache_dir.join(id).join("library_600x900.png"),
                cache_dir.join(format!("{}_header.jpg", id)), // Vertical header fallback
            ];

            for p in candidates {
                if p.exists() {
                    log::debug!("[SteamAsset] Found boxart for {}: {:?}", id, p);
                    return Some(p.to_string_lossy().to_string());
                }
            }
        }
        log::debug!("[SteamAsset] No boxart found for {}", id);
        None
    }

    fn find_steam_background(id: &str, steam_roots: &[PathBuf]) -> Option<String> {
        for root in steam_roots {
            let cache_dir = root.join("appcache/librarycache");
            let candidates = [
                cache_dir.join(format!("{}_library_hero.jpg", id)),
                cache_dir.join(format!("{}_library_hero.png", id)),
                cache_dir.join(id).join("library_hero.jpg"),
                cache_dir.join(id).join("library_hero.png"),
            ];

            for p in candidates {
                if p.exists() {
                    log::debug!("[SteamAsset] Found background for {}: {:?}", id, p);
                    return Some(p.to_string_lossy().to_string());
                }
            }
        }
        log::debug!("[SteamAsset] No background found for {}", id);
        None
    }

    fn parse_steam_acf(path: &Path, steam_roots: &[PathBuf]) -> Option<Rom> {
        let content = std::fs::read_to_string(path).ok()?;
        let mut appid = None;
        let mut name = None;

        for line in content.lines() {
            let trimmed = line.trim();
            if trimmed.starts_with("\"appid\"") {
                let parts: Vec<&str> = trimmed.split('\"').collect();
                if parts.len() >= 4 { appid = Some(parts[3].to_string()); }
            } else if trimmed.starts_with("\"name\"") {
                let parts: Vec<&str> = trimmed.split('\"').collect();
                if parts.len() >= 4 { name = Some(parts[3].to_string()); }
            }
            if appid.is_some() && name.is_some() { break; }
        }

        if let (Some(id), Some(title)) = (appid, name) {
            // Ignore redistributables and common tools usually
            if title.contains("Steamworks Common Redistributables") || title.contains("Steam Linux Runtime") {
                return None;
            }

            // Find assets
            let icon_path = Self::find_steam_icon(&id, steam_roots);
            let boxart_path = Self::find_steam_boxart(&id, steam_roots);
            let background_path = Self::find_steam_background(&id, steam_roots);

            return Some(Rom {
                id: format!("steam-{}", id),
                platform_id: "steam".to_string(), 
                path: format!("steam://rungameid/{}", id),
                filename: format!("{}.acf", id),
                file_size: 0,
                hash_sha1: None,
                title: Some(title),
                region: None,
                platform_name: Some("Steam".to_string()),
                platform_type: Some("PC (Linux)".to_string()),
                boxart_path,
                date_added: None,
                play_count: Some(0),
                total_play_time: Some(0),
                last_played: None,
                platform_icon: Some("steam".to_string()),
                is_favorite: Some(false),
                genre: None,
                developer: None,
                publisher: None,
                rating: None,
                tags: None,
                icon_path, 
                background_path,
                release_date: None,
                description: None,
                is_installed: Some(true),
                cloud_saves_supported: None,
                resources: None,
            });
        }

        None
    }

    /// Scans for Heroic Games Launcher games with enriched metadata.
    pub fn scan_heroic_games() -> Vec<Rom> {

        
        let mut apps = Vec::new();
        let home = std::env::var("HOME").unwrap_or_default();
        let home_p = PathBuf::from(home);

        let heroic_config_paths = vec![
            home_p.join(".config/heroic"),
            home_p.join(".var/app/com.heroicgameslauncher.hgl/config/heroic"),
        ];

        let mut heroic_config_dir = PathBuf::new();
        let mut found = false;
        for p in heroic_config_paths {
            if p.exists() {
                heroic_config_dir = p;
                found = true;
                break;
            }
        }

        if !found {
            return apps;
        }

        // 1. Load Playtime Data
        let timestamps = Self::load_heroic_timestamps(&heroic_config_dir);

        // 2. Scan Epic Games (Legendary)
        let epic_library = Self::load_heroic_library_metadata(&heroic_config_dir, "legendary_library.json");
        let epic_installed_path = heroic_config_dir.join("legendaryConfig/legendary/installed.json");

        let mut handles = Vec::new();
        if let Ok(content) = std::fs::read_to_string(&epic_installed_path) {
            if let Ok(installed) = serde_json::from_str::<serde_json::Value>(&content) {
                if let Some(map) = installed.as_object() {
                    for (id, val) in map {
                        if let (Some(title), Some(_install_path)) = (val["title"].as_str(), val["install_path"].as_str()) {
                            let id = id.clone();
                            let title = title.to_string();
                            let metadata = epic_library.get(&id).cloned();
                            let ts = timestamps.get(&id).cloned();
                            let heroic_config_dir = heroic_config_dir.clone();
                            
                            let handle = crate::core::runtime::get_runtime().spawn(async move {
                                let mut rom = Rom {
                                    id: format!("heroic-epic-{}", id),
                                    platform_id: "heroic".to_string(),
                                    path: format!("heroic://launch/epic/{}", id),
                                    filename: format!("{}.json", id),
                                    file_size: 0,
                                    hash_sha1: None,
                                    title: Some(title),
                                    region: None,
                                    platform_name: Some("Heroic (Epic)".to_string()),
                                    platform_type: Some("PC (Linux)".to_string()),
                                    boxart_path: None,
                                    date_added: None,
                                    play_count: None,
                                    total_play_time: None,
                                    last_played: None,
                                    tags: Some("Epic Store".to_string()),
                                    icon_path: None,
                                    background_path: None,
                                    platform_icon: Some("heroic".to_string()),
                                    is_favorite: Some(false),
                                    genre: None,
                                    developer: None,
                                    publisher: None,
                                    rating: None,
                                    release_date: None,
                                    description: None,
                                    is_installed: Some(true),
                                    cloud_saves_supported: None,
                                    resources: None,
                                };

                                // Enriched Metadata
                                if let Some(meta) = metadata {
                                    rom.developer = meta.developer.clone();
                                    rom.genre = meta.genre.clone();
                                    rom.description = meta.description.clone();
                                    // art_cover for Epic is a wide landscape image — use as background
                                    // boxart_path is intentionally left None here; the local icon file
                                    // discovered below will be symlinked into the Box-Front slot instead.
                                    rom.background_path = meta.art_cover.clone();
                                    rom.icon_path = meta.art_icon.clone();
                                }

                                // 2a. Epic Specific: Parse Metadata for cover/background from keyImages
                                let meta_file = heroic_config_dir.join("legendaryConfig/legendary/metadata").join(format!("{}.json", id));
                                if rom.boxart_path.is_none() || rom.background_path.is_none() {
                                    if let Ok(meta_content) = std::fs::read_to_string(&meta_file) {
                                        if let Ok(meta_json) = serde_json::from_str::<serde_json::Value>(&meta_content) {
                                            if let Some(images) = meta_json["keyImages"].as_array() {
                                                for img in images {
                                                    if let (Some(url), Some(itype)) = (img["url"].as_str(), img["type"].as_str()) {
                                                        // Tall portrait cover (box front)
                                                        if rom.boxart_path.is_none() && (itype == "OfferImageTall" || itype == "DieselStoreFront" || itype == "DieselGameBoxTall") {
                                                            rom.boxart_path = Some(url.to_string());
                                                        }
                                                        // Wide background
                                                        if rom.background_path.is_none() && (itype == "DieselGameBox" || itype == "DieselGameBackground" || itype == "OfferImageWide") {
                                                            rom.background_path = Some(url.to_string());
                                                        }
                                                        if rom.boxart_path.is_some() && rom.background_path.is_some() {
                                                            break;
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Local Asset Discovery
                                if let Some(p) = Self::find_heroic_icon(&heroic_config_dir, &id) {
                                    if rom.icon_path.is_none() || rom.icon_path.as_ref().map_or(false, |s| s.starts_with("http")) {
                                         rom.icon_path = Some(p.clone());
                                    }
                                    // If we still have no box art (e.g. art_cover was empty), reuse the
                                    // local icon file — the importer will symlink it into the Box-Front slot.
                                    if rom.boxart_path.is_none() || rom.boxart_path.as_ref().map_or(false, |s| s.starts_with("http")) {
                                        rom.boxart_path = Some(p);
                                    }
                                }

                                // Playtime
                                if let Some(ts) = ts {
                                    rom.total_play_time = Some(ts.total_played * 60); 
                                    if let Ok(dt) = chrono::DateTime::parse_from_rfc3339(&ts.last_played) {
                                        rom.last_played = Some(dt.timestamp());
                                    }
                                }
                                rom
                            });
                            handles.push(handle);
                        }
                    }
                }
            }
        }

        // Collect Epic Results
        for handle in handles {
            if let Ok(rom) = crate::core::runtime::get_runtime().block_on(handle) {
                apps.push(rom);
            }
        }

        // 3. Scan GOG Games
        let mut gog_handles = Vec::new();
        let gog_library = Self::load_heroic_library_metadata(&heroic_config_dir, "gog_library.json");
        let gog_installed_path = heroic_config_dir.join("gog_store/installed.json");
        if let Ok(content) = std::fs::read_to_string(&gog_installed_path) {
            if let Ok(json) = serde_json::from_str::<serde_json::Value>(&content) {
                if let Some(installed_list) = json["installed"].as_array() {
                    for item in installed_list {
                        if let (Some(app_id), Some(install_path)) = (item["appName"].as_str(), item["install_path"].as_str()) {
                            let app_id = app_id.to_string();
                            let install_path = install_path.to_string();
                            let metadata = gog_library.get(&app_id).cloned();
                            let ts = timestamps.get(&app_id).cloned();
                            let heroic_config_dir = heroic_config_dir.clone();

                            let handle = crate::core::runtime::get_runtime().spawn(async move {
                                // Try to derive title from path first, or metadata
                                let title = if let Some(meta) = &metadata {
                                    meta.title.clone().unwrap_or_else(|| {
                                        Path::new(&install_path)
                                            .file_name()
                                            .map(|s| s.to_string_lossy().to_string())
                                            .unwrap_or_else(|| app_id.to_string())
                                    })
                                } else {
                                    Path::new(&install_path)
                                        .file_name()
                                        .map(|s| s.to_string_lossy().to_string())
                                        .unwrap_or_else(|| app_id.to_string())
                                };

                                let mut rom = Rom {
                                    id: format!("heroic-gog-{}", app_id),
                                    platform_id: "heroic".to_string(),
                                    path: format!("heroic://launch/gog/{}", app_id),
                                    filename: format!("{}.json", app_id),
                                    file_size: 0,
                                    hash_sha1: None,
                                    title: Some(title),
                                    region: None,
                                    platform_name: Some("Heroic (GOG)".to_string()),
                                    platform_type: Some("PC (Linux)".to_string()),
                                    boxart_path: None,
                                    date_added: None,
                                    play_count: None,
                                    total_play_time: None,
                                    last_played: None,
                                    platform_icon: Some("heroic".to_string()),
                                    is_favorite: Some(false),
                                    genre: None,
                                    developer: None,
                                    publisher: None,
                                    rating: None,
                                    tags: Some("GOG".to_string()),
                                    icon_path: None,
                                    background_path: None,
                                    release_date: None,
                                    description: None,
                                    is_installed: Some(true),
                                    cloud_saves_supported: None,
                                    resources: None,
                                };

                                // Enriched Metadata
                                if let Some(meta) = metadata {
                                    rom.developer = meta.developer.clone();
                                    rom.genre = meta.genre.clone();
                                    rom.description = meta.description.clone();
                                    rom.boxart_path = meta.art_cover.clone();
                                    rom.icon_path = meta.art_icon.clone();
                                    rom.background_path = meta.art_background.clone();
                                }

                                // Local Asset Discovery
                                if let Some(p) = Self::find_heroic_icon(&heroic_config_dir, &app_id) {
                                    if rom.icon_path.is_none() || rom.icon_path.as_ref().map_or(false, |s| s.starts_with("http")) {
                                        rom.icon_path = Some(p);
                                    }
                                }

                                // Playtime
                                if let Some(ts) = ts {
                                    rom.total_play_time = Some(ts.total_played * 60);
                                    if let Ok(dt) = chrono::DateTime::parse_from_rfc3339(&ts.last_played) {
                                        rom.last_played = Some(dt.timestamp());
                                    }
                                }
                                rom
                            });
                            gog_handles.push(handle);
                        }
                    }
                }
            }
        }

        // Collect GOG Results
        for handle in gog_handles {
            if let Ok(rom) = crate::core::runtime::get_runtime().block_on(handle) {
                apps.push(rom);
            }
        }

        // 4. Scan Amazon Games
        let amazon_installed_path = heroic_config_dir.join("amazon_store/installed.json");
        if let Ok(content) = std::fs::read_to_string(&amazon_installed_path) {
            if let Ok(installed) = serde_json::from_str::<serde_json::Value>(&content) {
                if let Some(map) = installed.as_object() {
                    for (id, val) in map {
                        if let (Some(title), Some(_install_path)) = (val["title"].as_str(), val["install_path"].as_str()) {
                            apps.push(Rom {
                                id: format!("heroic-amazon-{}", id),
                                platform_id: "heroic".to_string(),
                                path: format!("heroic://launch/amazon/{}", id),
                                filename: format!("{}.json", id),
                                file_size: 0,
                                hash_sha1: None,
                                title: Some(title.to_string()),
                                region: None,
                                platform_name: Some("Heroic (Amazon)".to_string()),
                                platform_type: Some("PC (Linux)".to_string()),
                                boxart_path: None,
                                date_added: None,
                                play_count: Some(0),
                                total_play_time: Some(0),
                                last_played: None,
                                platform_icon: Some("heroic".to_string()),
                                is_favorite: Some(false),
                                genre: None,
                                developer: None,
                                publisher: None,
                                rating: None,
                                tags: Some("Amazon".to_string()),
                                icon_path: Self::find_heroic_icon(&heroic_config_dir, id),
                                background_path: None,
                                release_date: None,
                                description: None,
                                is_installed: Some(true),
                                cloud_saves_supported: None,
                                resources: None,
                            });
                        }
                    }
                }
            }
        }

        apps
    }

    // --- Heroic Helper Functions ---

    fn load_heroic_timestamps(config_dir: &Path) -> std::collections::HashMap<String, HeroicPlaytime> {
        let ts_path = config_dir.join("store/timestamp.json");
        let mut map = std::collections::HashMap::new();
        
        if let Ok(content) = std::fs::read_to_string(&ts_path) {
            if let Ok(json) = serde_json::from_str::<serde_json::Value>(&content) {
                if let Some(obj) = json.as_object() {
                    for (key, val) in obj {
                        let total = val["totalPlayed"].as_i64().unwrap_or(0);
                        let last = val["lastPlayed"].as_str().unwrap_or("").to_string();
                        map.insert(key.clone(), HeroicPlaytime {
                            total_played: total,
                            last_played: last,
                        });
                    }
                }
            }
        }
        map
    }

    fn find_heroic_icon(config_dir: &Path, app_id: &str) -> Option<String> {
        let icons_dir = config_dir.join("icons");
        let png = icons_dir.join(format!("{}.png", app_id));
        if png.symlink_metadata().is_ok() { return Some(png.to_string_lossy().to_string()); }
        let jpg = icons_dir.join(format!("{}.jpg", app_id));
        if jpg.symlink_metadata().is_ok() { return Some(jpg.to_string_lossy().to_string()); }
        let jpeg = icons_dir.join(format!("{}.jpeg", app_id));
        if jpeg.symlink_metadata().is_ok() { return Some(jpeg.to_string_lossy().to_string()); }
        None
    }

    fn load_heroic_library_metadata(config_dir: &Path, filename: &str) -> std::collections::HashMap<String, HeroicMetadata> {
        let lib_path = config_dir.join("store_cache").join(filename);
        let mut map = std::collections::HashMap::new();

        if let Ok(content) = std::fs::read_to_string(&lib_path) {
            if let Ok(json) = serde_json::from_str::<serde_json::Value>(&content) {
                let items = if filename.contains("gog") {
                    json["games"].as_array()
                } else {
                    json["library"].as_array()
                };

                if let Some(list) = items {
                    for item in list {
                        let app_name = item["app_name"].as_str().unwrap_or("").to_string();
                        if app_name.is_empty() { continue; }

                        let title = item["title"].as_str().map(|s| s.to_string());
                        let developer = item["developer"].as_str().map(|s| s.to_string());
                        let description = item["extra"]["about"]["description"].as_str().map(|s| s.to_string());
                        
                        let mut genres = Vec::new();
                        if let Some(g_arr) = item["extra"]["genres"].as_array() {
                            for g in g_arr {
                                if let Some(s) = g.as_str() { genres.push(s.to_string()); }
                            }
                        } else if let Some(g_arr) = item["tags"].as_array() {
                             for g in g_arr {
                                if let Some(s) = g.as_str() { genres.push(s.to_string()); }
                            }
                        }
                        let genre_str = if genres.is_empty() { None } else { Some(genres.join(", ")) };

                        // Art URLs
                        let art_cover = item["art_cover"].as_str().map(|s| s.to_string());
                        let art_icon = item["art_icon"].as_str().map(|s| s.to_string());
                        let art_background = item["art_background"].as_str()
                            .or_else(|| item["background"].as_str())
                            .or_else(|| item["extra"]["background"].as_str())
                            .or_else(|| item["extra"]["banner"].as_str())
                            .map(|s| s.to_string());

                        map.insert(app_name, HeroicMetadata {
                            title,
                            developer,
                            description,
                            genre: genre_str,
                            art_cover,
                            art_icon,
                            art_background,
                        });
                    }
                }
            }
        }
        map
    }

    /// Scans for Lutris games.
    pub fn scan_lutris_games() -> Vec<Rom> {
        let mut apps = Vec::new();
        let home = std::env::var("HOME").unwrap_or_default();
        let home_p = PathBuf::from(home);

        let lutris_db_paths = vec![
            home_p.join(".local/share/lutris/pga.db"),
            home_p.join(".var/app/net.lutris.Lutris/data/lutris/pga.db"),
        ];

        for db_path in lutris_db_paths {
            if !db_path.exists() { continue; }

            if let Ok(conn) = rusqlite::Connection::open(&db_path) {
                let stmt = conn.prepare("SELECT id, name, slug, installer_slug FROM games WHERE installed = 1").ok();
                if let Some(mut stmt) = stmt {
                    let rows = stmt.query_map([], |row| {
                        Ok((
                            row.get::<_, i32>(0)?,
                            row.get::<_, String>(1)?,
                            row.get::<_, String>(2)?,
                            row.get::<_, Option<String>>(3)?,
                        ))
                    }).ok();

                    if let Some(rows) = rows {
                        for row in rows.flatten() {
                            let (id, name, slug, _installer_slug) = row;
                            apps.push(Rom {
                                id: format!("lutris-{}", id),
                                platform_id: "lutris".to_string(),
                                path: format!("lutris:rungameid/{}", id),
                                filename: format!("{}.lutris", slug),
                                file_size: 0,
                                hash_sha1: None,
                                title: Some(name),
                                region: None,
                                platform_name: Some("Lutris".to_string()),
                                platform_type: Some("PC (Linux)".to_string()),
                                boxart_path: None,
                                date_added: None,
                                play_count: Some(0),
                                total_play_time: Some(0),
                                last_played: None,
                                platform_icon: Some("lutris".to_string()),
                                is_favorite: Some(false),
                                genre: None,
                                developer: None,
                                publisher: None,
                                rating: None,
                                tags: Some("Lutris".to_string()),
                                icon_path: None,
                                background_path: None,
                                cloud_saves_supported: None,
                                release_date: None,
                                description: None,
                                is_installed: Some(true),
                                resources: None,
                            });
                        }
                    }
                }
            }
        }

        apps
    }

    /// Synchronizes playtime for all Heroic games in the database with their local tracking.
    pub fn sync_heroic_playtime_bulk(db: &crate::core::db::DbManager) -> anyhow::Result<usize> {
        let home = std::env::var("HOME").unwrap_or_default();
        let config_dir = std::path::PathBuf::from(home).join(".config/heroic");
        log::info!("[SyncHeroic] Checking Heroic config dir: {:?}", config_dir);
        let timestamps = Self::load_heroic_timestamps(&config_dir);
        
        if timestamps.is_empty() {
            log::warn!("[SyncHeroic] No Heroic timestamps found (file missing or empty)");
            return Ok(0);
        }
        log::info!("[SyncHeroic] Found {} Heroic timestamps", timestamps.len());

        let conn = db.get_connection();
        let mut updated_count = 0;

        // Get all heroic roms and their current metadata
        let mut stmt = conn.prepare("
            SELECT r.id, COALESCE(m.total_play_time, 0), m.last_played 
            FROM roms r
            LEFT JOIN metadata m ON r.id = m.rom_id
            WHERE r.id LIKE 'heroic-%'
        ")?;

        let heroic_rows = stmt.query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, i64>(1)?,
                row.get::<_, Option<i64>>(2)?,
            ))
        })?;

        log::info!("[SyncHeroic] Querying database for Heroic ROMs...");
        for row in heroic_rows {
            if let Ok((rom_id, db_total, db_last)) = row {
                let parts: Vec<&str> = rom_id.split('-').collect();
                if parts.len() < 3 { 
                    log::warn!("[SyncHeroic] Skipping malformed ROM ID: {}", rom_id);
                    continue; 
                }
                let app_id = parts[2..].join("-");

                if let Some(ts) = timestamps.get(&app_id) {
                    let heroic_total = ts.total_played * 60;
                    let heroic_last = chrono::DateTime::parse_from_rfc3339(&ts.last_played)
                        .map(|dt| dt.timestamp())
                        .ok();

                    log::info!("[SyncHeroic] Found match for {}: DB={}s, Heroic={}s", 
                        rom_id, db_total, heroic_total);

                    let mut needs_update = false;
                    if heroic_total != db_total {
                        log::info!("[SyncHeroic] Playtime mismatch for {}: DB={} != Heroic={}", rom_id, db_total, heroic_total);
                        needs_update = true;
                    }
                    if heroic_last != db_last && heroic_last.is_some() {
                        log::info!("[SyncHeroic] Last played mismatch for {}: DB={:?} != Heroic={:?}", rom_id, db_last, heroic_last);
                        needs_update = true;
                    }

                    if needs_update {
                        log::info!("[SyncHeroic] SAVING UPDATE for {}: {} -> {} seconds", rom_id, db_total, heroic_total);
                        let res = conn.execute(
                            "UPDATE metadata SET total_play_time = ?1, last_played = ?2 WHERE rom_id = ?3",
                            rusqlite::params![heroic_total, heroic_last, rom_id]
                        );
                        match res {
                            Ok(_) => {
                                log::info!("[SyncHeroic] Successfully updated {} in database", rom_id);
                                updated_count += 1;
                            },
                            Err(e) => log::error!("[SyncHeroic] FAILED to update {}: {}", rom_id, e),
                        }
                    }
                } else {
                    log::info!("[SyncHeroic] No Heroic tracking found for app_id: {} (ROM: {})", app_id, rom_id);
                }
            }
        }

        Ok(updated_count)
    }

    /// Scans for games available via Legendary CLI (Epic Games Store).
    pub fn scan_legendary_games() -> Vec<Rom> {
        log::info!("[Legendary] Scanning for Epic Games via Legendary CLI...");
        match crate::core::legendary::LegendaryWrapper::list_games() {
            Ok(games) => {
                log::info!("[Legendary] Found {} games in Legendary library", games.len());
                games.iter()
                    .map(crate::core::legendary::LegendaryWrapper::to_rom)
                    .collect()
            },
            Err(e) => {
                log::warn!("[Legendary] Failed to list games: {}", e);
                Vec::new()
            }
        }
    }

    /// Triggers installation of a Legendary game.
    pub fn install_legendary_game(app_name: String, install_path: Option<String>, with_dlcs: bool) -> anyhow::Result<std::process::Child> {
        crate::core::legendary::LegendaryWrapper::install(&app_name, install_path.as_deref(), with_dlcs)
    }

    pub fn import_legendary_game(app_name: String, path: String) -> anyhow::Result<std::process::Child> {
        crate::core::legendary::LegendaryWrapper::import(&app_name, &path)
    }

    /// Triggers uninstallation of a Legendary game and updates DB.
    pub fn uninstall_legendary_game(app_name: String) -> anyhow::Result<()> {
        crate::core::legendary::LegendaryWrapper::uninstall(&app_name)?;
        
        // Update database to reflect uninstalled status
        let db_path = crate::core::paths::get_data_dir().join("games.db");
        if let Ok(db) = crate::core::db::DbManager::open(&db_path) {
            let rom_id = format!("legendary-{}", app_name);
            let conn = db.get_connection();
            let _ = conn.execute("UPDATE roms SET is_installed = 0 WHERE id = ?1", [&rom_id]);
            let _ = conn.execute("UPDATE metadata SET is_installed = 0 WHERE rom_id = ?1", [&rom_id]);
        }

        Ok(())
    }
}

#[derive(Clone)]
struct HeroicPlaytime {
    pub total_played: i64,
    pub last_played: String,
}

#[derive(Clone)]
struct HeroicMetadata {
    pub title: Option<String>,
    pub developer: Option<String>,
    pub description: Option<String>,
    pub genre: Option<String>,
    pub art_cover: Option<String>,
    pub art_icon: Option<String>,
    pub art_background: Option<String>,
}
