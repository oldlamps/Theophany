use std::process::Command;
use std::path::PathBuf;
use crate::core::models::Rom;

/// Strips ANSI escape codes from a string (e.g. colour codes emitted by lgogdownloader --list).
pub fn strip_ansi(s: &str) -> String {
    // Matches ESC [ ... m sequences and bare ESC sequences.
    let mut out = String::with_capacity(s.len());
    let mut chars = s.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '\x1b' {
            // Skip the escape sequence
            if chars.peek() == Some(&'[') {
                chars.next(); // consume '['
                // Consume until we hit a letter (the final byte of the CSI sequence)
                for nc in chars.by_ref() {
                    if nc.is_ascii_alphabetic() {
                        break;
                    }
                }
            }
            // else: lone ESC — just drop it
        } else {
            out.push(c);
        }
    }
    out
}

#[derive(Debug, Clone)]
pub struct GogGame {
    pub slug: String,
    pub title: Option<String>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct GogWishlistItem {
    pub title: String,
    pub url: String,
    pub platforms: Vec<String>,
    pub price: String,
    pub has_discount: bool,
}

pub struct GogDownloader;

impl GogDownloader {
    /// Finds the `lgogdownloader` binary.
    pub fn find_binary() -> Option<PathBuf> {
        let is_flatpak = std::path::Path::new("/.flatpak-info").exists();

        if is_flatpak {
            // Prefer bundled binary inside the sandbox.
            let fp_binary = PathBuf::from("/app/bin/lgogdownloader");
            if fp_binary.exists() {
                return Some(fp_binary);
            }
            let tools_binary = crate::core::paths::get_tools_dir().join("lgogdownloader");
            if tools_binary.exists() {
                return Some(tools_binary);
            }
            log::error!("[GogDownloader] Running inside Flatpak but no lgogdownloader binary found.");
            return None;
        }

        // Native: check tools dir then PATH.
        let internal = crate::core::paths::get_tools_dir().join("lgogdownloader");
        if internal.exists() {
            return Some(internal);
        }

        if let Ok(path) = which::which("lgogdownloader") {
            return Some(path);
        }

        None
    }

    /// Helper to build a base Command with the binary.
    fn build_command(binary: &PathBuf) -> Command {
        Command::new(binary)
    }

    /// Checks whether the user is authenticated with GOG.
    /// lgogdownloader exits 0 and prints nothing alarming when credentials exist.
    pub fn is_authenticated() -> bool {
        let binary = match Self::find_binary() {
            Some(p) => p,
            None => return false,
        };

        // `--check-login` verifies credentials without doing anything else.
        let output = Self::build_command(&binary)
            .arg("--check-login")
            .output();

        match output {
            Ok(out) => {
                let combined = format!(
                    "{}{}",
                    String::from_utf8_lossy(&out.stdout),
                    String::from_utf8_lossy(&out.stderr)
                );
                out.status.success()
                    && !combined.contains("ERROR")
                    && !combined.contains("not logged in")
                    && !combined.contains("Login failed")
            }
            Err(_) => false,
        }
    }

    /// Starts the browser-based login flow. Returns the OAuth URL that should be opened.
    pub fn get_auth_url() -> anyhow::Result<String> {
        let binary =
            Self::find_binary().ok_or_else(|| anyhow::anyhow!("lgogdownloader binary not found"))?;

        let output = Self::build_command(&binary)
            .arg("--browser-login")
            .output()?;

        let combined = format!(
            "{}{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );

        for line in combined.lines() {
            let clean = strip_ansi(line);
            if clean.contains("https://") {
                if let Some(start) = clean.find("https://") {
                    return Ok(clean[start..].trim().to_string());
                }
            }
        }

        Err(anyhow::anyhow!(
            "Could not find authentication URL in lgogdownloader output"
        ))
    }


    pub fn authenticate(redirect_url: &str) -> anyhow::Result<()> {
        let binary =
            Self::find_binary().ok_or_else(|| anyhow::anyhow!("lgogdownloader binary not found"))?;

        let output = Self::build_command(&binary)
            .arg("--browser-login")
            .arg(format!("--browser-login-redirect-url={}", redirect_url))
            .output()?;

        let combined = format!(
            "{}{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );

        if !output.status.success()
            || combined.to_lowercase().contains("error")
            || combined.to_lowercase().contains("failed")
            || combined.to_lowercase().contains("invalid")
        {
            return Err(anyhow::anyhow!("GOG authentication failed: {}", combined));
        }

        // Double-check
        if !Self::is_authenticated() {
            return Err(anyhow::anyhow!(
                "lgogdownloader still reports not authenticated after login attempt."
            ));
        }

        Ok(())
    }

    /// Logs out by removing the lgogdownloader credentials/cookie files.
    pub fn logout() -> anyhow::Result<()> {
        // lgogdownloader stores credentials in ~/.config/lgogdownloader/
        // The main credential file is cookies.sqlite (session) and config.cfg (access token).
        let home = std::env::var("HOME").unwrap_or_default();
        if home.is_empty() {
            return Err(anyhow::anyhow!("Cannot determine HOME directory for logout"));
        }

        let config_dir = PathBuf::from(&home).join(".config").join("lgogdownloader");
        let files_to_remove = ["cookies.sqlite", "config.cfg"];
        let mut removed_any = false;

        for filename in &files_to_remove {
            let path = config_dir.join(filename);
            if path.exists() {
                std::fs::remove_file(&path).map_err(|e| {
                    anyhow::anyhow!("Failed to remove {}: {}", path.display(), e)
                })?;
                removed_any = true;
                log::info!("[GogDownloader] Removed: {}", path.display());
            }
        }

        if !removed_any {
            log::warn!("[GogDownloader] No credential files found to remove.");
        }

        Ok(())
    }

    /// Lists all GOG games in the library via `lgogdownloader --list`.
    /// Strips ANSI escape codes from the output before parsing.
    pub fn list_games() -> anyhow::Result<Vec<GogGame>> {
        let binary =
            Self::find_binary().ok_or_else(|| anyhow::anyhow!("lgogdownloader binary not found"))?;

        let output = Self::build_command(&binary)
            .arg("--list")
            .output()?;

        if !output.status.success() {
            let err = String::from_utf8_lossy(&output.stderr);
            return Err(anyhow::anyhow!("lgogdownloader --list failed: {}", err));
        }

        let raw = String::from_utf8_lossy(&output.stdout);
        let games = Self::parse_list_output(&raw);

        log::info!("[GogDownloader] Found {} games in library", games.len());
        Ok(games)
    }

    /// Lists the user's GOG wishlist via `lgogdownloader --list w`.
    pub fn list_wishlist() -> anyhow::Result<Vec<GogWishlistItem>> {
        let binary =
            Self::find_binary().ok_or_else(|| anyhow::anyhow!("lgogdownloader binary not found"))?;

        let output = Self::build_command(&binary)
            .arg("--list")
            .arg("w")
            .output()?;

        if !output.status.success() {
            let err = String::from_utf8_lossy(&output.stderr);
            return Err(anyhow::anyhow!("lgogdownloader --list w failed: {}", err));
        }

        let raw = String::from_utf8_lossy(&output.stdout);
        let items = Self::parse_wishlist_output(&raw);

        log::info!("[GogDownloader] Found {} items in wishlist", items.len());
        Ok(items)
    }

    pub fn get_game_info(slug: &str) -> anyhow::Result<String> {
        let binary =
            Self::find_binary().ok_or_else(|| anyhow::anyhow!("lgogdownloader binary not found"))?;

        let output = Self::build_command(&binary)
            .arg("--list")
            .arg("details")
            .arg("--game")
            .arg(slug)
            .output()?;

        if !output.status.success() {
            let err = String::from_utf8_lossy(&output.stderr);
            return Err(anyhow::anyhow!("lgogdownloader --list details failed: {}", err));
        }

        let raw = String::from_utf8_lossy(&output.stdout).to_string();
        Ok(raw)
    }

    pub(crate) fn parse_wishlist_output(raw: &str) -> Vec<GogWishlistItem> {
        let mut items = Vec::new();
        let mut current_block = Vec::new();

        for line in raw.lines() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                if !current_block.is_empty() {
                    if let Some(item) = Self::parse_wishlist_block(&current_block) {
                        items.push(item);
                    }
                    current_block.clear();
                }
                continue;
            }
            current_block.push(line.to_string());
        }

        if !current_block.is_empty() {
            if let Some(item) = Self::parse_wishlist_block(&current_block) {
                items.push(item);
            }
        }

        items
    }

    fn parse_wishlist_block(lines: &[String]) -> Option<GogWishlistItem> {
        if lines.is_empty() { return None; }

        let title_line = strip_ansi(&lines[0]).trim().to_string();
        if title_line.is_empty() { return None; }

        let has_discount = title_line.contains("[Discount]");
        let title = title_line.replace("[Discount]", "").trim().to_string();

        let mut url = String::new();
        let mut platforms = Vec::new();
        let mut price = String::new();

        for line in &lines[1..] {
            let clean = strip_ansi(line).trim().to_string();
            if clean.starts_with("https://") {
                url = clean;
            } else if let Some(p_list) = clean.strip_prefix("Platforms: ") {
                platforms = p_list.split(',')
                    .map(|s| s.trim().to_string())
                    .filter(|s| !s.is_empty())
                    .collect();
            } else if let Some(p_val) = clean.strip_prefix("Price: ") {
                price = p_val.to_string();
            }
        }

        if title.is_empty() { return None; }

        Some(GogWishlistItem {
            title,
            url,
            platforms,
            price,
            has_discount,
        })
    }

   
    pub(crate) fn parse_list_output(raw: &str) -> Vec<GogGame> {
        let mut games = Vec::new();

        for line in raw.lines() {
            let clean = strip_ansi(line).trim().to_string();
            if clean.is_empty() {
                continue;
            }

            // Skip header / summary lines
            if clean.starts_with("Getting game list")
                || clean.starts_with("Total games found")
                || clean.starts_with("Listing")
                || clean.contains("INFO")
            {
                continue;
            }

            // Strip optional leading "N. " or "Game: " prefixes
            let slug = if let Some(rest) = clean.strip_prefix("Game: ") {
                rest.trim().to_string()
            } else if let Some(dot_pos) = clean.find(". ") {
                // e.g. "1. witcher3"
                let prefix = &clean[..dot_pos];
                if prefix.chars().all(|c| c.is_ascii_digit()) {
                    clean[dot_pos + 2..].trim().to_string()
                } else {
                    clean.clone()
                }
            } else {
                clean.clone()
            };

            let slug = {
                let s = slug.trim_end();
                if let Some(bracket_pos) = s.rfind(" [") {
                    let suffix = &s[bracket_pos..];
                    // Only strip if the suffix is " [<digits>]"
                    if suffix.starts_with(" [") && suffix.ends_with(']')
                        && suffix[2..suffix.len()-1].chars().all(|c| c.is_ascii_digit())
                    {
                        s[..bracket_pos].trim().to_string()
                    } else {
                        s.to_string()
                    }
                } else {
                    s.to_string()
                }
            };

            if slug.is_empty() || slug.contains(' ') && !slug.contains('_') {
                // Likely not a slug — skip free-text lines
                continue;
            }

            // Convert slug to a display title: "the_witcher_3" → "The Witcher 3"
            let title = Self::slug_to_title(&slug);

            games.push(GogGame {
                slug: slug.clone(),
                title: Some(title),
            });
        }

        games
    }

    /// Converts a GOG slug like `the_witcher_3_wild_hunt` to `The Witcher 3 Wild Hunt`.
    fn slug_to_title(slug: &str) -> String {
        slug.split('_')
            .map(|word| {
                let mut chars = word.chars();
                match chars.next() {
                    None => String::new(),
                    Some(first) => first.to_uppercase().to_string() + chars.as_str(),
                }
            })
            .collect::<Vec<_>>()
            .join(" ")
    }

    pub fn to_rom(game: &GogGame) -> Rom {
        let title = game.title.clone().unwrap_or_else(|| game.slug.clone());

        Rom {
            id: format!("gog-{}", game.slug),
            platform_id: "gog".to_string(),
            // Path placeholder — will be updated if/when an install path is found.
            path: format!("/gog/{}", game.slug),
            filename: format!("{}.gog", game.slug),
            file_size: 0,
            hash_sha1: None,
            title: Some(title),
            region: None,
            platform_name: Some("GOG".to_string()),
            platform_type: Some("gog".to_string()),
            boxart_path: None,
            date_added: None,
            play_count: Some(0),
            total_play_time: Some(0),
            last_played: None,
            platform_icon: Some("gog".to_string()),
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
            is_installed: Some(false),
            cloud_saves_supported: None,
            resources: None,
        }
    }

    pub fn install_game(
        slug: &str,
        install_path: &str,
        platform: &str,
        no_dependencies: bool,
    ) -> anyhow::Result<std::process::Child> {
        let binary =
            Self::find_binary().ok_or_else(|| anyhow::anyhow!("lgogdownloader binary not found"))?;

        std::fs::create_dir_all(install_path).ok();

        let mut cmd = Self::build_command(&binary);
        cmd.arg("--galaxy-platform").arg(platform)
           .arg("--galaxy-install").arg(format!("{}/0", slug))
           .arg("--directory").arg(install_path)
           .arg("--no-color");

        if no_dependencies {
            cmd.arg("--galaxy-no-dependencies");
        }

        cmd.stdout(std::process::Stdio::piped())
           .stderr(std::process::Stdio::piped());

        cmd.spawn().map_err(|e| anyhow::anyhow!("Failed to spawn lgogdownloader: {}", e))
    }

    pub fn parse_install_progress(line: &str, last_progress: f32) -> Option<(Option<f32>, String)> {
        let clean = strip_ansi(line.trim());
        if clean.is_empty() { return None; }

        let is_thread_line = clean.contains('▕') || clean.starts_with('#');
        if is_thread_line {
            return None;
        }

        let mut opt_progress = None;
        let pct = Self::extract_percent(&clean);
        if let Some(p) = pct {
            opt_progress = Some((p / 100.0).clamp(0.0, 1.0));
        }

        let is_total_line = clean.starts_with("Total: ");
        if opt_progress.is_none() && !is_total_line {
            return None;
        }

        let current_progress = opt_progress.unwrap_or(last_progress);

        let mut status = serde_json::Map::new();
        status.insert("progress".to_string(), serde_json::json!(current_progress));

        if let Some(eta_rest) = Self::extract_after(&clean, "ETA: ") {
            let eta_val = eta_rest.split_whitespace().next().unwrap_or("").to_string();
            status.insert("eta".to_string(), serde_json::json!(format!("ETA: {}", eta_val)));
        }

        if let Some(dl_rest) = Self::extract_after(&clean, "DL: ") {
            let dl_val: String = dl_rest.split_whitespace().take(2).collect::<Vec<_>>().join(" ");
            status.insert("dl_rate".to_string(), serde_json::json!(format!("DL: {}", dl_val)));
        } else if let Some(total_rest) = Self::extract_after(&clean, "Total: ") {
            let dl_val: String = total_rest.split_whitespace().take(1).collect::<Vec<_>>().join(" ");
            status.insert("dl_rate".to_string(), serde_json::json!(format!("DL: {}", dl_val)));
        }
        
        if let Some(rem_rest) = Self::extract_after(&clean, "Remaining: ") {
            if let Some(pipe_idx) = rem_rest.find(" ETA:") {
                let remaining_val = rem_rest[..pipe_idx].trim();
                status.insert("remaining".to_string(), serde_json::json!(remaining_val));
            }
        }

        status.insert("raw_line".to_string(), serde_json::json!(clean.chars().take(120).collect::<String>()));

        Some((opt_progress, serde_json::Value::Object(status).to_string()))
    }

    fn extract_percent(s: &str) -> Option<f32> {
        let mut iter = s.char_indices().peekable();
        while let Some((i, c)) = iter.next() {
            if c.is_ascii_digit() || c == '.' {
                let start = i;
                let mut end = i + c.len_utf8();
                while let Some(&(j, nc)) = iter.peek() {
                    if nc.is_ascii_digit() || nc == '.' {
                        end = j + nc.len_utf8();
                        iter.next();
                    } else {
                        break;
                    }
                }
                if matches!(iter.peek(), Some(&(_, '%'))) {
                    if let Ok(v) = s[start..end].parse::<f32>() {
                        return Some(v);
                    }
                }
            }
        }
        None
    }

    fn extract_after<'a>(s: &'a str, prefix: &str) -> Option<&'a str> {
        s.find(prefix).map(|i| s[i + prefix.len()..].trim())
    }


    pub fn find_exe_from_info_dir(game_dir: &str) -> Option<String> {
        let dir = std::path::Path::new(game_dir);
        if !dir.is_dir() { return None; }

        let mut info_path = None;
        if let Ok(entries) = std::fs::read_dir(dir) {
            for entry in entries.filter_map(|e| e.ok()) {
                let p = entry.path();
                if p.is_file() && p.extension().is_some_and(|e| e == "info") {
                    info_path = Some(p);
                    break;
                }
            }
        }

        if let Some(info_file) = info_path {
            if let Ok(content) = std::fs::read_to_string(&info_file) {
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&content) {
                    if let Some(tasks) = json.get("playTasks").and_then(|t| t.as_array()) {
                        let mut best_exe = None;
                        for task in tasks {
                            let is_primary = task.get("isPrimary").and_then(|p| p.as_bool()).unwrap_or(false);
                            let category = task.get("category").and_then(|c| c.as_str()).unwrap_or("");
                            let path_opt = task.get("path").and_then(|p| p.as_str());

                            if let Some(path_str) = path_opt {
                                if is_primary && (category == "game" || category == "launcher") {
                                    best_exe = Some(path_str.to_string());
                                    break;
                                } else if best_exe.is_none() && (category == "game" || category == "launcher") {
                                    best_exe = Some(path_str.to_string());
                                }
                            }
                        }

                        if let Some(exe) = best_exe {
                            let mut full_path = std::path::Path::new(&info_file).parent().unwrap().to_path_buf();
                            let clean_exe = exe.replace('\\', "/");
                            full_path.push(clean_exe);
                            if full_path.exists() {
                                return Some(full_path.to_string_lossy().to_string());
                            }
                        }
                    }
                }
            }
        }
        None
    }
}
