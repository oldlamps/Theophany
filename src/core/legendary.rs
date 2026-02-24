use std::process::Command;
use std::path::{PathBuf, Component};
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
        // 1. Check PATH
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

    /// Checks if the user is authenticated with Legendary.
    pub fn is_authenticated() -> bool {
        let binary = match Self::find_binary() {
            Some(p) => p,
            None => return false,
        };

        let output = Command::new(binary)
            .arg("status")
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
        
        let output = Command::new(&binary)
            .arg("auth")
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

        let mut child = Command::new(binary)
            .arg("auth")
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()?;

        if let Some(mut stdin) = child.stdin.take() {
            use std::io::Write;
            writeln!(stdin, "{}", code)?;
        }

        let output = child.wait_with_output()?;
        if !output.status.success() {
            let error = String::from_utf8_lossy(&output.stderr);
            return Err(anyhow::anyhow!("Authentication failed: {}", error));
        }

        Ok(())
    }

    /// Lists all games (both installed and uninstalled) from Epic Games Store.
    pub fn list_games() -> anyhow::Result<Vec<LegendaryGame>> {
        let binary = Self::find_binary().ok_or_else(|| anyhow::anyhow!("Legendary binary not found"))?;

        let output = Command::new(binary)
            .arg("list-games")
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

        let mut cmd = Command::new(binary);
        cmd.env("PYTHONUNBUFFERED", "1")
            .arg("install")
            .arg(app_name)
            .arg("--yes");

        if let Some(path) = install_path {
            cmd.arg("--base-path").arg(path);
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

        let output = Command::new(binary)
            .arg("uninstall")
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
    /// Example: "[cli] INFO: Downloading ... (10.5% done, ...)"
    pub fn parse_progress(line: &str) -> Option<f32> {
        if let Some(pos) = line.find("% done") {
            let start = line[..pos].rfind('(')?;
            let percent_str = &line[start + 1..pos].trim();
            if let Ok(p) = percent_str.parse::<f32>() {
                return Some(p / 100.0);
            }
        }
        None
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

        let output = Command::new(binary)
            .arg("info")
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

        match direction {
            SyncDirection::Pull => { cmd.arg("--skip-upload"); }
            SyncDirection::Push => { cmd.arg("--skip-download"); }
            SyncDirection::Both => {}
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

    /// Converts a LegendaryGame to a Theophany Rom.
    pub fn to_rom(game: &LegendaryGame) -> Rom {
        let title = game.title.clone().unwrap_or_else(|| game.app_name.clone());
        Rom {
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
            boxart_path: None, // Will be filled by scraper or Heroic cache
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
            tags: Some("Epic Games Store".to_string()),
            icon_path: None,
            background_path: None,
            release_date: None,
            description: None,
            is_installed: Some(game.is_installed),
        }
    }
}
