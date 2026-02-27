use std::process::Command;
use std::path::{PathBuf, Component};
#[cfg(unix)]
use std::os::unix::process::CommandExt;
use serde::{Deserialize, Serialize};
use crate::core::models::Rom;

/// Resolves `.` and `..` components in a path without touching the filesystem.
/// This mirrors what `canonicalize` does for the path structure but works on
/// paths that may not exist yet (e.g. Wine prefix save directories).
fn normalize_path(path: &std::path::Path) -> PathBuf {
    let mut components: Vec<Component> = Vec::new();
    for component in path.components() {
        match component {
            Component::CurDir => {}                         // skip "."
            Component::ParentDir => { components.pop(); }  // pop on ".."
            other => components.push(other),
        }
    }
    components.iter().collect()
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct LegendaryGame {
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

/// Direction for cloud save synchronisation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SyncDirection {
    /// Download from cloud only.
    Pull,
    /// Upload to cloud only.
    Push,
    /// Bidirectional (default legendary behaviour).
    Both,
}

pub struct LegendaryWrapper;

impl LegendaryWrapper {
    /// Discovers the path to the legendary binary.
    pub fn find_binary() -> Option<PathBuf> {
        // 1. Check Settings
        let path = crate::core::paths::get_config_dir().join("settings.json");
        if let Ok(content) = std::fs::read_to_string(&path) {
            if let Ok(data) = serde_json::from_str::<serde_json::Value>(&content) {
                if data["use_custom_legendary"].as_bool().unwrap_or(false) {
                    if let Some(custom_path) = data["custom_legendary_path"].as_str() {
                        let p = PathBuf::from(custom_path);
                        if !custom_path.is_empty() && p.exists() {
                            return Some(p);
                        }
                    }
                }
            }
        }

        // 2. Check internal tools directory
        let internal = crate::core::paths::get_tools_dir().join("legendary");
        if internal.exists() {
            return Some(internal);
        }

        // 3. Check PATH
        if let Ok(path) = which::which("legendary") {
            return Some(path);
        }

        // 2. Check common paths and user-relative paths
        let mut check_paths = Vec::new();

        if let Ok(home) = std::env::var("HOME") {
            let home_p = PathBuf::from(home);
            check_paths.push(home_p.join(".local/share/heroic/bin/legendary"));
            check_paths.push(home_p.join(".config/heroic/bin/legendary"));
            check_paths.push(home_p.join("Downloads/legendary"));
        }

        // Current directory
        if let Ok(cwd) = std::env::current_dir() {
            check_paths.push(cwd.join("legendary"));
        }

        for p in check_paths {
            if p.exists() {
                // Ensure it's executable on Linux/macOS
                #[cfg(unix)]
                {
                    use std::os::unix::fs::PermissionsExt;
                    if let Ok(metadata) = std::fs::metadata(&p) {
                        let mut perms = metadata.permissions();
                        if (perms.mode() & 0o111) == 0 {
                            perms.set_mode(perms.mode() | 0o111);
                            let _ = std::fs::set_permissions(&p, perms);
                        }
                    }
                }
                return Some(p);
            }
        }

        None
    }

    /// Helper to create a Command configured with the correct paths and environment variables.
    fn build_command(binary: &PathBuf, subcommand: &str) -> Command {
        let mut cmd = Command::new(binary);
        cmd.arg(subcommand);
        
        let legendary_config = crate::core::paths::get_config_dir().join("legendary");
        cmd.env("LEGENDARY_CONFIG_PATH", legendary_config.to_string_lossy().to_string());
        
        cmd
    }

    /// Checks if the user is authenticated with Legendary.
    pub fn is_authenticated() -> bool {
        let binary = match Self::find_binary() {
            Some(p) => p,
            None => return false,
        };

        let output = Self::build_command(&binary, "status")
            .output();

        match output {
            Ok(out) => {
                let stdout = String::from_utf8_lossy(&out.stdout);
                // legendary status returns 0 and contains "<not logged in>" if not authenticated
                out.status.success() && !stdout.contains("<not logged in>")
            },
            Err(_) => false,
        }
    }

    /// Starts the authentication process. Returns the URL the user needs to visit.
    pub fn get_auth_url() -> anyhow::Result<String> {
        let binary = Self::find_binary().ok_or_else(|| anyhow::anyhow!("Legendary binary not found"))?;

        // legendary auth usually prints something like:
        // To log in, visit the following URL and log in with your Epic Games account:
        // https://...
        // Then paste the authorization code below:
        
        // Use --disable-webview to prevent Legendary from auto-opening the URL in an embedded browser,
        // which would cause duplicate tabs when the UI also launches it.
        // We also set BROWSER=/bin/true to prevent Python's webbrowser module from opening xdg-open.
        let output = Self::build_command(&binary, "auth")
            .arg("--disable-webview")
            .env("BROWSER", "/bin/true")
            .output()?;

        let stdout = String::from_utf8_lossy(&output.stdout);
        let stderr = String::from_utf8_lossy(&output.stderr);
        let combined = format!("{}{}", stdout, stderr);

        // Find the URL
        for line in combined.lines() {
            if line.contains("https://") {
                if let Some(start) = line.find("https://") {
                    let url = &line[start..];
                    return Ok(url.trim().to_string());
                }
            }
        }

        Err(anyhow::anyhow!("Could not find authentication URL in Legendary output"))
    }

    /// Completes authentication with the provided verification code.
    pub fn authenticate(code: &str) -> anyhow::Result<()> {
        let binary = Self::find_binary().ok_or_else(|| anyhow::anyhow!("Legendary binary not found"))?;

        // Use --code to bypass interactive stdin prompts and --disable-webview to prevent UI popups.
        let output = Self::build_command(&binary, "auth")
            .arg("--disable-webview")
            .arg("--code")
            .arg(code)
            .env("BROWSER", "/bin/true")
            .output()?;

        let combined = format!("{}{}", String::from_utf8_lossy(&output.stdout), String::from_utf8_lossy(&output.stderr));

        if !output.status.success() || combined.contains("ERROR:") || combined.contains("failed") {
            return Err(anyhow::anyhow!("Authentication failed: {}", combined));
        }
        
        // Final sanity check since `legendary auth` sometimes returns exit code 0 on failure
        if !Self::is_authenticated() {
            return Err(anyhow::anyhow!("Legendary still reports not authenticated. The authorization code may be invalid or expired."));
        }

        Ok(())
    }

    /// Logs out of the current Epic Games account by removing existing authentication.
    pub fn logout() -> anyhow::Result<()> {
        let binary = Self::find_binary().ok_or_else(|| anyhow::anyhow!("Legendary binary not found"))?;

        let output = Self::build_command(&binary, "auth")
            .arg("--delete")
            .output()?;

        if !output.status.success() {
            let error = String::from_utf8_lossy(&output.stderr);
            return Err(anyhow::anyhow!("Logout failed: {}", error));
        }

        Ok(())
    }

    /// Lists all games (both installed and uninstalled) from Epic Games Store.
    pub fn list_games() -> anyhow::Result<Vec<LegendaryGame>> {
        let binary = Self::find_binary().ok_or_else(|| anyhow::anyhow!("Legendary binary not found"))?;

        let output = Self::build_command(&binary, "list-games")
            .arg("--json")
            .output()?;

        if !output.status.success() {
            let error = String::from_utf8_lossy(&output.stderr);
            return Err(anyhow::anyhow!("Legendary failed: {}", error));
        }

        let json_str = String::from_utf8_lossy(&output.stdout);
        let games: Vec<LegendaryGame> = serde_json::from_str(&json_str)?;

        Ok(games)
    }



    /// Installs a game. Returns a Child process to monitor output.
    pub fn install(app_name: &str, install_path: Option<&str>) -> anyhow::Result<std::process::Child> {
        let binary = Self::find_binary().ok_or_else(|| anyhow::anyhow!("Legendary binary not found"))?;

        let mut cmd = Self::build_command(&binary, "install");
        cmd.env("PYTHONUNBUFFERED", "1")
            .arg(app_name)
            .arg("--yes");

        if let Some(path) = install_path {
            cmd.arg("--base-path").arg(path);
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

    /// Imports an already installed game.
    pub fn import(app_name: &str, install_path: &str) -> anyhow::Result<std::process::Child> {
        let binary = Self::find_binary().ok_or_else(|| anyhow::anyhow!("Legendary binary not found"))?;

        let mut cmd = Self::build_command(&binary, "import");
        cmd.env("PYTHONUNBUFFERED", "1")
            .arg(app_name)
            .arg(install_path);

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

    /// Uninstalls a game.
    pub fn uninstall(app_name: &str) -> anyhow::Result<()> {
        let binary = Self::find_binary().ok_or_else(|| anyhow::anyhow!("Legendary binary not found"))?;

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

    /// Parses progress percentage from legendary output line.
    /// Example: "[DLManager] INFO: = Progress: 6.05% ..."
    pub fn parse_progress(line: &str) -> Option<f32> {
        if let Some(pos) = line.find("Progress: ") {
            let start = pos + 10;
            if let Some(end) = line[start..].find('%') {
                if let Ok(p) = line[start..start + end].trim().parse::<f32>() {
                    return Some(p / 100.0);
                }
            }
        }
        
        // Fallback for older formats
        if let Some(pos) = line.find('%') {
            let start = line[..pos].rfind(|c: char| !c.is_digit(10) && c != '.').map(|i| i + 1).unwrap_or(0);
            let percent_str = &line[start..pos].trim();
            if let Ok(p) = percent_str.parse::<f32>() {
                return Some(p / 100.0);
            }
        }
        None
    }

    /// Cleans a Legendary output line to be more UI-friendly.
    pub fn clean_status_line(line: &str) -> String {
        let mut cleaned = line.to_string();
        if let Some(pos) = cleaned.find("INFO: ") {
            cleaned = cleaned[pos + 6..].to_string();
        }
        
        // Remove leading symbols used by Legendary DLManager
        cleaned = cleaned.trim_start_matches(|c: char| c == '=' || c == '+' || c == '-' || c == ' ' || c == '*').trim().to_string();
        
        // Replace long labels with short ones, handling multiple spaces
        while cleaned.contains("  ") {
            cleaned = cleaned.replace("  ", " ");
        }
        
        cleaned = cleaned.replace("Download -", "DL:")
                         .replace("Disk -", "Disk:")
                         .replace("Progress:", "P:")
                         .replace(" (raw) /", ",")
                         .replace(" (decompressed)", "")
                         .replace(" (write) / 0.00 MiB/s (read)", "");
                         
        cleaned
    }

    /// Extracts a specific value based on a keyword, handling variable whitespace.
    /// Example: "Download      - 5.43 MiB/s" -> "5.43 MiB/s"
    pub fn extract_value(line: &str, keyword: &str) -> Option<String> {
        if let Some(pos) = line.find(keyword) {
            let start = pos + keyword.len();
            let mut sub = &line[start..];
            
            // Skip leading whitespace and symbols like '-'
            sub = sub.trim_start_matches(|c: char| c.is_whitespace() || c == '-').trim();
            
            // Find next marker or end of group
            let end = sub.find(',').or_else(|| sub.find(')')).unwrap_or(sub.len());
            return Some(sub[..end].trim().to_string());
        }
        None
    }

    /// Parses the detailed status from legendary output line.
    pub fn parse_detailed_status(line: &str) -> Option<String> {
        let mut parts = Vec::new();
        
        // Clean the line first to remove junk
        let clean = Self::clean_status_line(line);
        if clean.contains("MiB/s") || clean.contains("GiB") || clean.contains("MiB") || clean.contains("ETA:") {
            return Some(clean);
        }

        let mut current_start_paren = None;
        let mut current_start_square = None;
        
        for (i, c) in line.char_indices() {
            match c {
                '(' => current_start_paren = Some(i + 1),
                ')' => if let Some(start) = current_start_paren {
                    parts.push(line[start..i].to_string());
                    current_start_paren = None;
                },
                '[' => current_start_square = Some(i + 1),
                ']' => if let Some(start) = current_start_square {
                    let part = &line[start..i];
                    if part != "cli" && part != "DLManager" {
                        parts.push(part.to_string());
                    }
                    current_start_square = None;
                },
                _ => {}
            }
        }
        
        if parts.is_empty() {
            None
        } else {
            Some(parts.join(", "))
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Cloud Save Helpers
    // ─────────────────────────────────────────────────────────────────────────

    /// Queries `legendary info <app_name> --json` and returns the Windows-style
    /// `cloud_save_folder` template string (e.g. `{AppData}/Publisher/Game`).
    /// Returns `Ok(None)` if legendary reports cloud saves are not supported.
    pub fn get_save_path_template(app_name: &str) -> anyhow::Result<Option<String>> {
        let binary = Self::find_binary()
            .ok_or_else(|| anyhow::anyhow!("Legendary binary not found"))?;

        let output = Self::build_command(&binary, "info")
            .arg(app_name)
            .arg("--json")
            .output()?;
        if !output.status.success() {
            let err = String::from_utf8_lossy(&output.stderr);
            return Err(anyhow::anyhow!("legendary info failed: {}", err));
        }

        let json: serde_json::Value = serde_json::from_slice(&output.stdout)?;

        // Structure: { game: { cloud_saves_supported: bool, cloud_save_folder: str|null, ... }, ... }
        let game = json.get("game")
            .ok_or_else(|| anyhow::anyhow!("Missing 'game' key in legendary info output"))?;

        let supported = game.get("cloud_saves_supported")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);

        if !supported {
            return Ok(None);
        }

        let folder = game.get("cloud_save_folder")
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty())
            .map(|s| s.to_string());

        Ok(folder)
    }

    /// Resolves the full host-side Linux path for a game's cloud saves.
    ///
    /// - `app_name`:   legendary app name (e.g. `"d6407c9e6fd54cb492b8c6635480d792"`)
    /// - `prefix`:     Wine/Proton prefix root (e.g. `"~/.local/share/Steam/steamapps/compatdata/…/pfx"`)
    ///
    /// Returns `Ok(None)` if the game doesn't support cloud saves.
    pub fn resolve_cloud_save_path(
        app_name: &str,
        prefix: &str,
        install_path: Option<&str>,
    ) -> anyhow::Result<Option<PathBuf>> {
        let template = match Self::get_save_path_template(app_name)? {
            Some(t) => t,
            None => return Ok(None),
        };

        // UMU always symlinks the real username → steamuser, so we use steamuser.
        let wine_user = "steamuser";

        let prefix_path = PathBuf::from(prefix);
        let user_root = prefix_path.join("drive_c").join("users").join(wine_user);
        let appdata_roaming  = user_root.join("AppData/Roaming");
        let appdata_local    = user_root.join("AppData/Local");
        let appdata_locallow = user_root.join("AppData/LocalLow");
        let saved_games      = user_root.join("Saved Games");
        let documents        = user_root.join("Documents");

        // Legendary (and EGS manifests) can return any of these casings.
        // Order: longest names first to avoid partial matches.
        let s = template.replace('\\', "/"); // normalise separators first
        let s = s
            .replace("{UserSavedGames}",  &*saved_games.to_string_lossy())
            .replace("{usersavedgames}",  &*saved_games.to_string_lossy())
            .replace("{USERSAVEDGAMES}",  &*saved_games.to_string_lossy())
            .replace("{LocalAppData}",    &*appdata_local.to_string_lossy())
            .replace("{localappdata}",    &*appdata_local.to_string_lossy())
            .replace("{LOCALAPPDATA}",    &*appdata_local.to_string_lossy())
            .replace("{LocalLow}",        &*appdata_locallow.to_string_lossy())
            .replace("{locallow}",        &*appdata_locallow.to_string_lossy())
            .replace("{LOCALLOW}",        &*appdata_locallow.to_string_lossy())
            .replace("{AppData}",         &*appdata_roaming.to_string_lossy())
            .replace("{appdata}",         &*appdata_roaming.to_string_lossy())
            .replace("{APPDATA}",         &*appdata_roaming.to_string_lossy())
            .replace("{UserDocuments}",   &*documents.to_string_lossy())
            .replace("{userdocuments}",   &*documents.to_string_lossy())
            .replace("{USERDOCUMENTS}",   &*documents.to_string_lossy())
            .replace("{UserDir}",         &*user_root.to_string_lossy())
            .replace("{userdir}",         &*user_root.to_string_lossy())
            .replace("{USERDIR}",         &*user_root.to_string_lossy())
            .replace("{InstallDir}",      install_path.unwrap_or(""))
            .replace("{installdir}",      install_path.unwrap_or(""))
            .replace("{INSTALLDIR}",      install_path.unwrap_or(""))
            // Some templates use the literal Wine username in braces
            .replace(&format!("{{{}}}", wine_user), &*user_root.to_string_lossy());

        // Expand ~ to HOME if present at start.
        let s = if s.starts_with('~') {
            if let Ok(home) = std::env::var("HOME") {
                s.replacen('~', &home, 1)
            } else {
                s
            }
        } else {
            s
        };

        // Resolve any ".." that appear after variable expansion (e.g. {appdata}/../LocalLow/…).
        let normalised = normalize_path(&PathBuf::from(s));

        // Fix casing for known Wine AppData sub-directories that legendary may emit lowercase.
        // We operate on the string representation since PathBuf has no case-aware API.
        let normalised_str = normalised.to_string_lossy()
            .replace("/locallow/",    "/LocalLow/")
            .replace("/localappdata/", "/Local/")
            .replace("/roaming/",     "/Roaming/");
        let normalised = PathBuf::from(normalised_str);

        log::debug!("[cloud-save] template='{}' → resolved='{}'", template, normalised.display());

        Ok(Some(normalised))
    }

    /// Synchronises cloud saves for a game, **blocking until legendary exits**.
    ///
    /// Streams stdout/stderr so progress lines are visible in the Theophany log.
    /// Returns `Ok(())` on success, `Err` on failure.
    ///
    /// `save_path` is the **host-side Linux path** passed to `--save-path`.
    pub fn sync_saves(
        app_name: &str,
        save_path: &std::path::Path,
        direction: SyncDirection,
        force: bool,
    ) -> anyhow::Result<()> {
        let binary = Self::find_binary()
            .ok_or_else(|| anyhow::anyhow!("Legendary binary not found"))?;

        let mut cmd = Command::new(&binary);
        cmd.env("PYTHONUNBUFFERED", "1")
            .arg("sync-saves")
            .arg(app_name)
            .arg("--save-path")
            .arg(save_path)
            .arg("--yes") // accept all prompts non-interactively
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped());

        log::info!("[legendary cloud-save] Executing: {:?} {:?}", binary, cmd.get_args());

        match direction {
            SyncDirection::Pull => {
                cmd.arg("--skip-upload");
                if force { cmd.arg("--force-download"); }
            }
            SyncDirection::Push => {
                cmd.arg("--skip-download");
                if force { cmd.arg("--force-upload"); }
            }
            SyncDirection::Both => {
                if force {
                    cmd.arg("--force-download");
                    cmd.arg("--force-upload");
                }
            }
        }

        // Ensure target directory exists before starting legendary sync
        let _ = std::fs::create_dir_all(save_path);

        #[cfg(unix)]
        {
            cmd.process_group(0);
        }

        let mut child = cmd.spawn()?;

        // Stream output so the log is useful.
        // We read stderr (legendary logs there) line by line.
        use std::io::{BufRead, BufReader};
        if let Some(stderr) = child.stderr.take() {
            let reader = BufReader::new(stderr);
            for line in reader.lines() {
                if let Ok(line) = line {
                    log::info!("[legendary cloud-save] {}", line);
                }
            }
        }
        // Also drain stdout (usually empty but be safe).
        if let Some(stdout) = child.stdout.take() {
            let reader = BufReader::new(stdout);
            for line in reader.lines() {
                if let Ok(line) = line {
                    log::debug!("[legendary cloud-save stdout] {}", line);
                }
            }
        }

        let status = child.wait()?;
        if !status.success() {
            return Err(anyhow::anyhow!(
                "legendary sync-saves exited with status: {}",
                status
            ));
        }

        log::info!(
            "[legendary cloud-save] sync-saves completed ({:?}) for {}",
            direction,
            app_name
        );
        Ok(())
    }

    pub fn to_rom(game: &LegendaryGame) -> Rom {
        let title = game.title.clone().unwrap_or_else(|| game.app_name.clone());
        
        let mut rom = Rom {
            id: format!("legendary-{}", game.app_name),
            platform_id: "epic".to_string(),
            path: format!("epic://launch/{}", game.app_name),
            filename: format!("{}.epic", game.app_name),
            file_size: 0,
            hash_sha1: None,
            title: Some(title),
            region: None,
            platform_name: Some("Epic Games".to_string()),
            platform_type: Some("PC (Linux)".to_string()),
            boxart_path: None,
            date_added: None,
            play_count: Some(0),
            total_play_time: Some(0),
            last_played: None,
            platform_icon: Some("epic".to_string()),
            is_favorite: Some(false),
            genre: None,
            developer: None,
            publisher: None,
            rating: None,
            tags: None,
            icon_path: None,
            background_path: None,
            release_date: None,
            description: None,
            is_installed: Some(game.is_installed),
            cloud_saves_supported: None,
        };

        // Enriched Metadata from Legendary JSON
        if let Some(metadata) = &game.metadata {
            // Cloud Save Support
            rom.cloud_saves_supported = metadata.get("cloud_saves_supported")
                .and_then(|v| v.as_bool());

            // Description
            if let Some(desc) = metadata.get("description").and_then(|v| v.as_str()) {
                rom.description = Some(desc.to_string());
            }

            // Developer / Publisher
            if let Some(dev) = metadata.get("developer").and_then(|v| v.as_str()) {
                rom.developer = Some(dev.to_string());
            }
            if let Some(publ) = metadata.get("publisher").and_then(|v| v.as_str()) {
                rom.publisher = Some(publ.to_string());
            }

            // Genre (from categories)
            if let Some(cats) = metadata.get("categories").and_then(|v| v.as_array()) {
                let genres: Vec<String> = cats.iter()
                    .filter_map(|v| v.as_str())
                    .filter(|s| !s.contains("App") && !s.contains("Game") && !s.contains("Engine"))
                    .map(|s| s.to_string())
                    .collect();
                if !genres.is_empty() {
                    rom.genre = Some(genres.join(", "));
                }
            }

            // Release Date
            if let Some(rd) = metadata.get("releaseDate").and_then(|v| v.as_str()) {
                rom.release_date = Some(rd.to_string());
            }

            // Artwork from keyImages
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
                        (Some(u), Some("DieselGameBox")) | (Some(u), Some("StoreFrontWide")) => {
                            // If we don't have a background yet, use this horizontal art.
                            if rom.background_path.is_none() {
                                rom.background_path = Some(u.to_string());
                            }
                        },
                        (Some(u), Some(t)) if t.to_lowercase().contains("logo") => {
                            // We don't have a Rom.logo_path, but the importer can pick this up 
                            // if we find a way to pass it. For now, let's at least ensure we have 
                            // the most common images correctly mapped.
                            // We'll use "Clear Logo" as the type for the assets table.
                             let _ = u; 
                        }
                        _ => {}
                    }
                }
            }
            
            // Fallback for Icon if still missing (use Boxart or Thumbnail)
            if rom.icon_path.is_none() {
                rom.icon_path = rom.boxart_path.clone();
            }
        }

        rom
    }

    // ─────────────────────────────────────────────────────────────────────────
    // EOS Overlay Management
    // ─────────────────────────────────────────────────────────────────────────

    /// Returns the status and version of the installed EOS overlay.
    pub fn eos_overlay_info() -> anyhow::Result<String> {
        let binary = Self::find_binary().ok_or_else(|| anyhow::anyhow!("Legendary binary not found"))?;
        let output = Self::build_command(&binary, "eos-overlay")
            .arg("info")
            .output()?;

        let combined = format!("{}{}", String::from_utf8_lossy(&output.stdout), String::from_utf8_lossy(&output.stderr));
        Ok(combined)
    }

    /// Installs the EOS overlay. Returns a Child process to monitor output.
    pub fn eos_overlay_install(path: Option<PathBuf>) -> anyhow::Result<std::process::Child> {
        let binary = Self::find_binary().ok_or_else(|| anyhow::anyhow!("Legendary binary not found"))?;
        let mut cmd = Self::build_command(&binary, "eos-overlay");
        cmd.arg("install").arg("--yes");
        if let Some(p) = path {
            cmd.arg("--path").arg(p.to_string_lossy().to_string());
        }
        cmd.stdout(std::process::Stdio::piped()).stderr(std::process::Stdio::piped());
        Ok(cmd.spawn()?)
    }

    /// Updates the EOS overlay. Returns a Child process to monitor output.
    pub fn eos_overlay_update(path: Option<PathBuf>) -> anyhow::Result<std::process::Child> {
        let binary = Self::find_binary().ok_or_else(|| anyhow::anyhow!("Legendary binary not found"))?;
        let mut cmd = Self::build_command(&binary, "eos-overlay");
        cmd.arg("update").arg("--yes");
        if let Some(p) = path {
            cmd.arg("--path").arg(p.to_string_lossy().to_string());
        }
        cmd.stdout(std::process::Stdio::piped()).stderr(std::process::Stdio::piped());
        Ok(cmd.spawn()?)
    }

    /// Removes the EOS overlay.
    pub fn eos_overlay_remove() -> anyhow::Result<()> {
        let binary = Self::find_binary().ok_or_else(|| anyhow::anyhow!("Legendary binary not found"))?;
        let output = Self::build_command(&binary, "eos-overlay")
            .arg("remove")
            .arg("--yes")
            .output()?;

        if !output.status.success() {
            let error = String::from_utf8_lossy(&output.stderr);
            return Err(anyhow::anyhow!("Failed to remove EOS overlay: {}", error));
        }
        Ok(())
    }

    /// Enables the EOS overlay for a specific Wine prefix.
    pub fn eos_overlay_enable(prefix: Option<&str>, path: Option<PathBuf>) -> anyhow::Result<()> {
        let binary = Self::find_binary().ok_or_else(|| anyhow::anyhow!("Legendary binary not found"))?;
        let mut cmd = Self::build_command(&binary, "eos-overlay");
        cmd.arg("enable");
        if let Some(pfx) = prefix {
            cmd.arg("--prefix").arg(pfx);
        }
        if let Some(p) = path {
            cmd.arg("--path").arg(p.to_string_lossy().to_string());
        }
        
        log::info!("[Legendary] Executing: {:?}", cmd);
        let output = cmd.output()?;

        if !output.status.success() {
            let error = String::from_utf8_lossy(&output.stderr);
            log::error!("[Legendary] eos-overlay enable failed: {}", error);
            return Err(anyhow::anyhow!("Failed to enable EOS overlay: {}", error));
        }
        
        log::info!("[Legendary] eos-overlay enable output: {}", String::from_utf8_lossy(&output.stdout));
        Ok(())
    }

    /// Disables the EOS overlay for a specific Wine prefix.
    pub fn eos_overlay_disable(prefix: Option<&str>, path: Option<PathBuf>) -> anyhow::Result<()> {
        let binary = Self::find_binary().ok_or_else(|| anyhow::anyhow!("Legendary binary not found"))?;
        let mut cmd = Self::build_command(&binary, "eos-overlay");
        cmd.arg("disable");
        if let Some(pfx) = prefix {
            cmd.arg("--prefix").arg(pfx);
        }
        if let Some(p) = path {
            cmd.arg("--path").arg(p.to_string_lossy().to_string());
        }
        
        log::info!("[Legendary] Executing: {:?}", cmd);
        let output = cmd.output()?;

        if !output.status.success() {
            let error = String::from_utf8_lossy(&output.stderr);
            log::error!("[Legendary] eos-overlay disable failed: {}", error);
            return Err(anyhow::anyhow!("Failed to disable EOS overlay: {}", error));
        }
        
        log::info!("[Legendary] eos-overlay disable output: {}", String::from_utf8_lossy(&output.stdout));
        Ok(())
    }

    /// Checks if the EOS overlay is enabled for a specific Wine prefix.
    pub fn is_eos_overlay_enabled(prefix: Option<&str>) -> bool {
        let binary = match Self::find_binary() {
            Some(b) => b,
            None => {
                log::warn!("[Legendary] Binary not found for is_eos_overlay_enabled");
                return false;
            }
        };
        let mut cmd = Self::build_command(&binary, "eos-overlay");
        cmd.arg("info");
        if let Some(pfx) = prefix {
            cmd.arg("--prefix").arg(pfx);
        }
        
        log::info!("[Legendary] Executing: {:?}", cmd);
        let output = match cmd.output() {
                Ok(o) => o,
                Err(e) => {
                    log::error!("[Legendary] Failed to execute eos-overlay info: {}", e);
                    return false;
                }
            };

        let stdout = String::from_utf8_lossy(&output.stdout);
        let stderr = String::from_utf8_lossy(&output.stderr);
        log::info!("[Legendary] eos-overlay info stdout: {}", stdout);
        if !stderr.is_empty() {
            log::warn!("[Legendary] eos-overlay info stderr: {}", stderr);
        }
        
        let is_enabled_str = "Overlay enabled: Yes";
        stdout.contains(is_enabled_str) || stderr.contains(is_enabled_str)
    }
}
