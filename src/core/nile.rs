use std::process::Command;
use std::path::{PathBuf, Component};
#[cfg(unix)]
use std::os::unix::process::CommandExt;
use serde::{Deserialize, Serialize};
use crate::core::models::Rom;
use std::sync::Mutex;

pub static PENDING_NILE_AUTH: Mutex<Option<NileAuthData>> = Mutex::new(None);

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct NileAuthData {
    pub client_id: String,
    pub code_verifier: String,
    pub serial: String,
    pub url: String,
}

fn normalize_path(path: &std::path::Path) -> PathBuf {
    let mut components: Vec<Component> = Vec::new();
    for component in path.components() {
        match component {
            Component::CurDir => {}
            Component::ParentDir => { components.pop(); }
            other => components.push(other),
        }
    }
    components.iter().collect()
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct NileGame {
    pub app_name: String,
    #[serde(alias = "app_title")]
    pub title: Option<String>,
    #[serde(default)]
    pub version: String,
    #[serde(default)]
    pub is_installed: bool,
    pub install_path: Option<String>,
    #[serde(default)]
    pub base_urls: Vec<String>,
    pub metadata: Option<serde_json::Value>,
}

pub struct NileWrapper;

impl NileWrapper {
    pub fn find_binary() -> Option<PathBuf> {
        let is_flatpak = std::path::Path::new("/.flatpak-info").exists();

        if is_flatpak {
            let fp_binary = PathBuf::from("/app/bin/nile");
            if fp_binary.exists() {
                return Some(fp_binary);
            }
            let tools_binary = crate::core::paths::get_tools_dir().join("nile");
            if tools_binary.exists() {
                return Some(tools_binary);
            }
            log::error!("[Nile] Running inside Flatpak but no nile binary found in /app/bin or tools dir.");
            return None;
        }

        let path = crate::core::paths::get_config_dir().join("settings.json");
        if let Ok(content) = std::fs::read_to_string(&path) {
            if let Ok(data) = serde_json::from_str::<serde_json::Value>(&content) {
                if data["use_custom_nile"].as_bool().unwrap_or(false) {
                    if let Some(custom_path) = data["custom_nile_path"].as_str() {
                        let p = PathBuf::from(custom_path);
                        if !custom_path.is_empty() && p.exists() {
                            return Some(p);
                        }
                    }
                }
            }
        }

        let internal = crate::core::paths::get_tools_dir().join("nile");
        if internal.exists() {
            return Some(internal);
        }

        if let Ok(path) = which::which("nile") {
            return Some(path);
        }

        None
    }

    fn build_command(binary: &PathBuf, subcommand: &str) -> Command {
        let mut cmd = Command::new(binary);
        cmd.arg(subcommand);
        
        let nile_config = crate::core::paths::get_config_dir().join("nile");
        cmd.env("NILE_CONFIG_PATH", nile_config.to_string_lossy().to_string());
        
        cmd
    }

    pub fn is_authenticated() -> bool {
        let binary = match Self::find_binary() {
            Some(p) => p,
            None => return false,
        };

        let output = Self::build_command(&binary, "auth").arg("--status").output();

        match output {
            Ok(out) => {
                let stdout = String::from_utf8_lossy(&out.stdout);
                
                // nile auth --status returns JSON like {"Username": "<not logged in>", "LoggedIn": false}
                if out.status.success() {
                    let mut is_logged_in = false;
                    if let Ok(parsed) = serde_json::from_str::<serde_json::Value>(&stdout) {
                        if let Some(logged_in) = parsed.get("LoggedIn").and_then(|v| v.as_bool()) {
                            is_logged_in = logged_in;
                        }
                    } else if stdout.contains("\"LoggedIn\": true") {
                        is_logged_in = true;
                    }
                    is_logged_in
                } else {
                    false
                }
            },
            Err(_) => false,
        }
    }

    pub fn get_auth_url() -> anyhow::Result<String> {
        let binary = Self::find_binary().ok_or_else(|| anyhow::anyhow!("Nile binary not found"))?;

        let output = Self::build_command(&binary, "auth")
            .arg("--login")
            .arg("--non-interactive")
            .output()?;

        let json_str = String::from_utf8_lossy(&output.stdout);
        
        let auth_data: NileAuthData = match serde_json::from_str(&json_str) {
            Ok(data) => data,
            Err(_) => return Err(anyhow::anyhow!("Could not parse nile auth data. output: {}", json_str)),
        };
        
        let url = auth_data.url.clone();
        
        if let Ok(mut lock) = PENDING_NILE_AUTH.lock() {
            *lock = Some(auth_data);
        }

        Ok(url)
    }

    pub fn authenticate(code: &str) -> anyhow::Result<()> {
        let binary = Self::find_binary().ok_or_else(|| anyhow::anyhow!("Nile binary not found"))?;

        let auth_data = {
            let mut lock = PENDING_NILE_AUTH.lock().map_err(|_| anyhow::anyhow!("Mutex poisoned"))?;
            lock.take().ok_or_else(|| anyhow::anyhow!("No pending Amazon Games authentication found!"))?
        };

        let mut final_code = code.trim().to_string();
        if final_code.contains("openid.oa2.authorization_code=") {
            if let Some(start) = final_code.find("openid.oa2.authorization_code=") {
                let after = &final_code[start + "openid.oa2.authorization_code=".len()..];
                let end = after.find('&').unwrap_or(after.len());
                final_code = after[..end].to_string();
            }
        }

        let output = Self::build_command(&binary, "register")
            .arg("--code")
            .arg(&final_code)
            .arg("--client-id")
            .arg(&auth_data.client_id)
            .arg("--code-verifier")
            .arg(&auth_data.code_verifier)
            .arg("--serial")
            .arg(&auth_data.serial)
            .output()?;

        let combined = format!("{}{}", String::from_utf8_lossy(&output.stdout), String::from_utf8_lossy(&output.stderr));

        if !output.status.success() || combined.contains("ERROR:") || combined.contains("failed") {
            return Err(anyhow::anyhow!("Registration failed: {}", combined));
        }
        
        if !Self::is_authenticated() {
            return Err(anyhow::anyhow!("Nile still reports not authenticated. The authorization code may be invalid or expired."));
        }

        Ok(())
    }

    pub fn logout() -> anyhow::Result<()> {
        let binary = Self::find_binary().ok_or_else(|| anyhow::anyhow!("Nile binary not found"))?;

        let output = Self::build_command(&binary, "auth")
            .arg("--logout")
            .output()?;

        if !output.status.success() {
            return Err(anyhow::anyhow!("Logout failed"));
        }

        Ok(())
    }

    pub fn import_game(id: &str, path: &str) -> anyhow::Result<()> {
        let binary = Self::find_binary().ok_or_else(|| anyhow::anyhow!("Nile binary not found"))?;

        let output = Self::build_command(&binary, "import")
            .arg("--path")
            .arg(path)
            .arg(id)
            .output()?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(anyhow::anyhow!("Import failed: {}", stderr));
        }

        Ok(())
    }

    pub fn list_games() -> anyhow::Result<Vec<NileGame>> {
        let binary = Self::find_binary().ok_or_else(|| anyhow::anyhow!("Nile binary not found"))?;

        let output = Self::build_command(&binary, "library")
            .arg("list")
            .arg("--json")
            .output()?;

        if !output.status.success() {
            let error = String::from_utf8_lossy(&output.stderr);
            return Err(anyhow::anyhow!("Nile failed: {}", error));
        }

        let json_str = String::from_utf8_lossy(&output.stdout);
        
        // Nile's JSON output might be a dict or a list, but Legendary assumes array.
        // Let's assume Nile outputs array of games, or dict.
        let parsed: serde_json::Value = serde_json::from_str(&json_str)?;
        let games_array = if let Some(arr) = parsed.as_array() {
            arr.clone()
        } else if let Some(obj) = parsed.as_object() {
            obj.values().cloned().collect()
        } else {
            vec![]
        };

        let mut games = Vec::new();

        for item in games_array {
            if let Some(product) = item.get("product") {
                let app_name = product.get("id").and_then(|v| v.as_str()).unwrap_or("").to_string();
                let title = product.get("title").and_then(|v| v.as_str()).unwrap_or("").to_string();
                
                if app_name.is_empty() { continue; }

                let mut game = NileGame {
                    app_name,
                    title: Some(title),
                    version: String::new(),
                    is_installed: false,
                    install_path: None,
                    base_urls: vec![],
                    metadata: Some(item.clone()),
                };
                
                games.push(game);
            }
        }

        Ok(games)
    }

    pub fn get_game_info(app_name: &str) -> anyhow::Result<String> {
        let binary = Self::find_binary().ok_or_else(|| anyhow::anyhow!("Nile binary not found"))?;

        let output = Self::build_command(&binary, "install")
            .arg(app_name)
            .arg("--info")
            .output()?;

        let stdout = String::from_utf8_lossy(&output.stdout);
        let stderr = String::from_utf8_lossy(&output.stderr);
        let combined = format!("{}\n{}", stdout, stderr);

        let mut title = "Unknown".to_string();
        let mut disk_size = 0u64;

        for line in combined.lines() {
            if line.contains("Found:") {
                if let Some(t) = line.split("Found:").last() {
                    title = t.trim().to_string();
                }
            }
            if line.contains("Download size:") {
                 if let Some(s) = line.split("Download size:").last() {
                     let size_str = s.trim().to_uppercase();
                     let mut multiplier = 1.0;
                     let val_str = if size_str.contains("G") {
                         multiplier = 1024.0 * 1024.0 * 1024.0;
                         size_str.replace("GIB", "").replace("GB", "").replace("G", "")
                     } else if size_str.contains("M") {
                         multiplier = 1024.0 * 1024.0;
                         size_str.replace("MIB", "").replace("MB", "").replace("M", "")
                     } else if size_str.contains("K") {
                         multiplier = 1024.0;
                         size_str.replace("KIB", "").replace("KB", "").replace("K", "")
                     } else {
                         size_str.replace("B", "")
                     };
                     
                     if let Ok(v) = val_str.trim().parse::<f32>() {
                         disk_size = (v * multiplier) as u64;
                     }
                 }
            }
        }

        Ok(format!(r#"{{"game": {{"title": "{}"}}, "install": {{"disk_size": {} }}, "manifest": {{"disk_size": {} }} }}"#, 
            title.replace("\"", "\\\""), disk_size, disk_size))
    }

    pub fn install(app_name: &str, install_path: Option<&str>, _with_dlcs: bool) -> anyhow::Result<std::process::Child> {
        let binary = Self::find_binary().ok_or_else(|| anyhow::anyhow!("Nile binary not found"))?;

        let mut cmd = Self::build_command(&binary, "install");
        cmd.env("PYTHONUNBUFFERED", "1")
            .arg(app_name);

        if let Some(path) = install_path {
            let p = std::path::Path::new(path);
            if let Some(parent) = p.parent() {
                cmd.arg("--base-path").arg(parent.to_string_lossy().to_string());
            }
            cmd.arg("--path").arg(path);
        }

        #[cfg(unix)]
        {
            cmd.process_group(0);
        }

        let child = cmd
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()?;

        Ok(child)
    }

    pub fn import(app_name: &str, install_path: &str) -> anyhow::Result<std::process::Child> {
        let binary = Self::find_binary().ok_or_else(|| anyhow::anyhow!("Nile binary not found"))?;

        let mut cmd = Self::build_command(&binary, "import");
        cmd.env("PYTHONUNBUFFERED", "1")
            .arg("--path")
            .arg(install_path)
            .arg(app_name);

        #[cfg(unix)]
        {
            cmd.process_group(0);
        }

        let child = cmd
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()?;

        Ok(child)
    }

    pub fn uninstall(app_name: &str) -> anyhow::Result<()> {
        let binary = Self::find_binary().ok_or_else(|| anyhow::anyhow!("Nile binary not found"))?;

        let output = Self::build_command(&binary, "uninstall")
            .arg(app_name)
            .arg("--yes")
            .output()?;

        if !output.status.success() {
            let error = String::from_utf8_lossy(&output.stderr);
            return Err(anyhow::anyhow!("Uninstall failed: {}", error));
        }

        Ok(())
    }

    pub fn parse_progress(line: &str) -> Option<f32> {
        crate::core::legendary::LegendaryWrapper::parse_progress(line)
    }

    pub fn clean_status_line(line: &str) -> String {
        crate::core::legendary::LegendaryWrapper::clean_status_line(line)
    }

    pub fn extract_value(line: &str, keyword: &str) -> Option<String> {
        crate::core::legendary::LegendaryWrapper::extract_value(line, keyword)
    }

    pub fn to_rom(game: &NileGame) -> Rom {
        let app_name = game.app_name.clone();
        
        let title = game.title.clone().unwrap_or_else(|| app_name.clone());
        let mut developer = "".to_string();
        let mut genre_str = "".to_string();
        let mut description = "".to_string();
        let mut icon = "".to_string();
        
        if let Some(metadata) = &game.metadata {
            if let Some(product) = metadata.get("product") {
                if let Some(product_detail) = product.get("productDetail") {
                    if let Some(icon_url) = product_detail.get("iconUrl").and_then(|v| v.as_str()) {
                        icon = icon_url.to_string();
                    }
                    if let Some(details) = product_detail.get("details") {
                        if let Some(dev) = details.get("developer").and_then(|v| v.as_str()) {
                            developer = dev.to_string();
                        }
                        if let Some(desc) = details.get("shortDescription").and_then(|v| v.as_str()) {
                            description = desc.to_string();
                        }
                        if let Some(genres) = details.get("genres").and_then(|v| v.as_array()) {
                            let g_list: Vec<String> = genres.iter().filter_map(|x| x.as_str().map(String::from)).collect();
                            genre_str = g_list.join(", ");
                        }
                    }
                }
            }
        }

        let mut rom = Rom {
            id: format!("amazon-{}", app_name),
            platform_id: "amazon-games".to_string(),
            path: format!("amazon://launch/{}", app_name),
            filename: format!("{}.nile", app_name),
            file_size: 0,
            hash_sha1: None,
            title: Some(title),
            region: None,
            platform_name: Some("Amazon Games".to_string()),
            platform_type: Some("PC (Linux)".to_string()),
            boxart_path: Some(icon.clone()),
            date_added: None,
            play_count: Some(0),
            total_play_time: Some(0),
            last_played: None,
            platform_icon: Some("amazon".to_string()),
            is_favorite: Some(false),
            genre: Some(genre_str),
            developer: Some(developer),
            publisher: None,
            rating: None,
            tags: None,
            icon_path: None,
            background_path: None,
            release_date: None,
            description: None,
            is_installed: Some(game.is_installed),
            cloud_saves_supported: None,
            resources: None,
        };

        if let Some(metadata) = &game.metadata {
            if let Some(desc) = metadata.get("description").and_then(|v| v.as_str()) {
                rom.description = Some(desc.to_string());
            }

            if let Some(dev) = metadata.get("developer").and_then(|v| v.as_str()) {
                rom.developer = Some(dev.to_string());
            }
            if let Some(publ) = metadata.get("publisher").and_then(|v| v.as_str()) {
                rom.publisher = Some(publ.to_string());
            }

            if let Some(rd) = metadata.get("releaseDate").and_then(|v| v.as_str()) {
                rom.release_date = Some(rd.to_string());
            }

            if let Some(images) = metadata.get("keyImages").and_then(|v| v.as_array()) {
                for img in images {
                    let url = img.get("url").and_then(|v| v.as_str());
                    let itype = img.get("type").and_then(|v| v.as_str());

                    match (url, itype) {
                        (Some(u), Some("DieselGameBoxTall")) | (Some(u), Some("OfferImageTall")) => {
                            rom.boxart_path = Some(u.to_string());
                        },
                        (Some(u), Some("DieselGameBackground")) | (Some(u), Some("OfferImageWide")) => {
                            rom.background_path = Some(u.to_string());
                        },
                        (Some(u), Some("Thumbnail")) => {
                            rom.icon_path = Some(u.to_string());
                        },
                        _ => {}
                    }
                }
            }
            
            if rom.icon_path.is_none() {
                rom.icon_path = rom.boxart_path.clone();
            }
        }

        rom
    }
}
