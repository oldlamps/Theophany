use std::process::Command;
use std::path::PathBuf;
use serde::{Deserialize, Serialize};
use crate::core::models::Rom;

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
