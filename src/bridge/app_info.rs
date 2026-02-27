#![allow(non_snake_case)]
use qmetaobject::prelude::*;
use std::sync::mpsc;
use std::cell::RefCell;

enum AsyncResponse {
    LegendaryDownloadStatus(bool, String),
    EosOverlayStatus(bool, String),
    EosOverlayInfo(String),
}

#[derive(QObject, Default)]
#[allow(non_snake_case)]
pub struct AppInfo {
    base: qt_base_class!(trait QObject),
    getDataPath: qt_method!(fn(&self) -> QString),
    getConfigPath: qt_method!(fn(&self) -> QString),
    getAssetsDir: qt_method!(fn(&self) -> QString),
    getTrayIconPath: qt_method!(fn(&self) -> QString),
    checkYtdlp: qt_method!(fn(&self, custom_path: String) -> String),
    checkLegendary: qt_method!(fn(&self, custom_path: String) -> String),
    downloadLegendary: qt_method!(fn(&self)),
    checkAsyncResponses: qt_method!(fn(&mut self)),
    getVersion: qt_method!(fn(&self) -> QString),
    checkForUpdates: qt_method!(fn(&self)),
    triggerEosOverlayCheck: qt_method!(fn(&self)),
    getEosOverlayInfo: qt_method!(fn(&self) -> String),
    installEosOverlay: qt_method!(fn(&self)),
    updateEosOverlay: qt_method!(fn(&self)),
    removeEosOverlay: qt_method!(fn(&self) -> bool),
    updateAvailable: qt_signal!(version: String, notes: String, url: String),
    legendaryDownloadStatus: qt_signal!(success: bool, message: String),
    eosOverlayStatus: qt_signal!(success: bool, message: String),
    eosOverlayInfoReceived: qt_signal!(info: String),

    // Internals
    tx: RefCell<Option<mpsc::Sender<AsyncResponse>>>,
    rx: RefCell<Option<mpsc::Receiver<AsyncResponse>>>,
}

#[allow(non_snake_case)]
impl AppInfo {
    fn ensure_channels(&self) {
        if self.tx.borrow().is_none() {
            let (tx, rx) = mpsc::channel();
            *self.tx.borrow_mut() = Some(tx);
            *self.rx.borrow_mut() = Some(rx);
        }
    }

    fn getDataPath(&self) -> QString {
        crate::core::paths::get_data_dir().to_string_lossy().to_string().into()
    }

    fn getConfigPath(&self) -> QString {
        crate::core::paths::get_config_dir().to_string_lossy().to_string().into()
    }

    fn getAssetsDir(&self) -> QString {
        crate::core::paths::get_assets_dir().to_string_lossy().to_string().into()
    }

    fn getTrayIconPath(&self) -> QString {
        let path = crate::core::paths::get_assets_dir().join("tray_icon.png");
        format!("file://{}", path.to_string_lossy()).into()
    }

    fn getVersion(&self) -> QString {
        env!("CARGO_PKG_VERSION").into()
    }

    fn checkLegendary(&self, custom_path: String) -> String {
        let binary = if custom_path.is_empty() {
            // Check tools dir first
            let internal = crate::core::paths::get_tools_dir().join("legendary");
            if internal.exists() {
                internal.to_string_lossy().to_string()
            } else {
                "legendary".to_string()
            }
        } else {
            custom_path
        };

        match std::process::Command::new(&binary).arg("--version").output() {
            Ok(output) => {
                if output.status.success() {
                    let version = String::from_utf8_lossy(&output.stdout).trim().to_string();
                    serde_json::json!({
                        "found": true,
                        "path": binary,
                        "version": version
                    }).to_string()
                } else {
                    serde_json::json!({ "found": false }).to_string()
                }
            }
            Err(_) => {
                serde_json::json!({ "found": false }).to_string()
            }
        }
    }

    fn downloadLegendary(&self) {
        self.ensure_channels();
        let tx = match self.tx.borrow().as_ref() {
            Some(t) => t.clone(),
            None => return,
        };

        std::thread::spawn(move || {
            let tools_dir = crate::core::paths::get_tools_dir();
            let dest_path = tools_dir.join("legendary");
            let url = "https://github.com/oldlamps/legendary/releases/latest/download/legendary";

            log::info!("[AppInfo] Downloading Legendary from: {}", url);
            
            let client = reqwest::blocking::Client::builder()
                .user_agent("Theophany")
                .build()
                .unwrap_or_default();

            match client.get(url).send() {
                Ok(mut response) => {
                    if response.status().is_success() {
                        if let Err(e) = std::fs::create_dir_all(&tools_dir) {
                            let _ = tx.send(AsyncResponse::LegendaryDownloadStatus(false, format!("Failed to create tools directory: {}", e)));
                            return;
                        }

                        let mut file = match std::fs::File::create(&dest_path) {
                            Ok(f) => f,
                            Err(e) => {
                                let _ = tx.send(AsyncResponse::LegendaryDownloadStatus(false, format!("Failed to create file: {}", e)));
                                return;
                            }
                        };

                        if let Err(e) = std::io::copy(&mut response, &mut file) {
                            let _ = tx.send(AsyncResponse::LegendaryDownloadStatus(false, format!("Download failed: {}", e)));
                            return;
                        }

                        // Set executable permissions
                        #[cfg(unix)]
                        {
                            use std::os::unix::fs::PermissionsExt;
                            if let Ok(metadata) = std::fs::metadata(&dest_path) {
                                let mut perms = metadata.permissions();
                                perms.set_mode(perms.mode() | 0o111);
                                let _ = std::fs::set_permissions(&dest_path, perms);
                            }
                        }

                        log::info!("[AppInfo] Legendary downloaded successfully to {:?}", dest_path);
                        let _ = tx.send(AsyncResponse::LegendaryDownloadStatus(true, "Download complete".to_string()));
                    } else {
                        let _ = tx.send(AsyncResponse::LegendaryDownloadStatus(false, format!("Server returned error: {}", response.status())));
                    }
                }
                Err(e) => {
                    let _ = tx.send(AsyncResponse::LegendaryDownloadStatus(false, format!("Request failed: {}", e)));
                }
            }
        });
    }

    fn checkAsyncResponses(&mut self) {
        self.ensure_channels();
        let mut messages = Vec::new();
        {
            let mut rx_borrow = self.rx.borrow_mut();
            if let Some(rx) = rx_borrow.as_mut() {
                while let Ok(msg) = rx.try_recv() {
                    messages.push(msg);
                }
            }
        }

        for msg in messages {
            match msg {
                AsyncResponse::LegendaryDownloadStatus(success, message) => {
                    self.legendaryDownloadStatus(success, message);
                }
                AsyncResponse::EosOverlayStatus(success, message) => {
                    self.eosOverlayStatus(success, message);
                }
                AsyncResponse::EosOverlayInfo(info) => {
                    self.eosOverlayInfoReceived(info.into());
                }
            }
        }
    }

    fn checkYtdlp(&self, custom_path: String) -> String {
        let binary = if custom_path.is_empty() {
            "yt-dlp".to_string()
        } else {
            custom_path
        };

        match std::process::Command::new(&binary).arg("--version").output() {
            Ok(output) => {
                if output.status.success() {
                    let version = String::from_utf8_lossy(&output.stdout).trim().to_string();
                    serde_json::json!({
                        "found": true,
                        "path": binary,
                        "version": version
                    }).to_string()
                } else {
                    serde_json::json!({ "found": false }).to_string()
                }
            }
            Err(_) => {
                serde_json::json!({ "found": false }).to_string()
            }
        }
    }


    fn getEosOverlayInfo(&self) -> String {
        match crate::core::legendary::LegendaryWrapper::eos_overlay_info() {
            Ok(info) => info,
            Err(e) => format!("Error: {}", e),
        }
    }

    fn triggerEosOverlayCheck(&self) {
        self.ensure_channels();
        let tx = match self.tx.borrow().as_ref() {
            Some(t) => t.clone(),
            None => return,
        };

        std::thread::spawn(move || {
            let info = match crate::core::legendary::LegendaryWrapper::eos_overlay_info() {
                Ok(i) => i,
                Err(e) => format!("Error: {}", e),
            };
            let _ = tx.send(AsyncResponse::EosOverlayInfo(info));
        });
    }

    fn installEosOverlay(&self) {
        self.ensure_channels();
        let tx = match self.tx.borrow().as_ref() {
            Some(t) => t.clone(),
            None => return,
        };

        std::thread::spawn(move || {
            let path = crate::core::paths::get_tools_dir().join("eos-overlay");
            match crate::core::legendary::LegendaryWrapper::eos_overlay_install(Some(path)) {
                Ok(mut child) => {
                    use std::io::{BufRead, BufReader};
                    
                    // Drain stdout and stderr in background threads to avoid deadlocks
                    let stdout = child.stdout.take();
                    let stderr = child.stderr.take();
                    
                    if let Some(out) = stdout {
                        std::thread::spawn(move || {
                            let reader = BufReader::new(out);
                            for line in reader.lines().flatten() {
                                log::info!("[EosOverlay] {}", line);
                            }
                        });
                    }
                    if let Some(err) = stderr {
                        std::thread::spawn(move || {
                            let reader = BufReader::new(err);
                            for line in reader.lines().flatten() {
                                log::error!("[EosOverlay] {}", line);
                            }
                        });
                    }

                    let status = child.wait();
                    let success = status.map(|s| s.success()).unwrap_or(false);
                    let msg = if success { "Installation complete".to_string() } else { "Installation failed".to_string() };
                    let _ = tx.send(AsyncResponse::EosOverlayStatus(success, msg));
                }
                Err(e) => {
                    let _ = tx.send(AsyncResponse::EosOverlayStatus(false, format!("Failed to start installation: {}", e)));
                }
            }
        });
    }

    fn updateEosOverlay(&self) {
        self.ensure_channels();
        let tx = match self.tx.borrow().as_ref() {
            Some(t) => t.clone(),
            None => return,
        };

        std::thread::spawn(move || {
            let path = crate::core::paths::get_tools_dir().join("eos-overlay");
            match crate::core::legendary::LegendaryWrapper::eos_overlay_update(Some(path)) {
                Ok(mut child) => {
                    use std::io::{BufRead, BufReader};
                    
                    let stdout = child.stdout.take();
                    let stderr = child.stderr.take();
                    
                    if let Some(out) = stdout {
                        std::thread::spawn(move || {
                            let reader = BufReader::new(out);
                            for line in reader.lines().flatten() {
                                log::info!("[EosOverlay] {}", line);
                            }
                        });
                    }
                    if let Some(err) = stderr {
                        std::thread::spawn(move || {
                            let reader = BufReader::new(err);
                            for line in reader.lines().flatten() {
                                log::error!("[EosOverlay] {}", line);
                            }
                        });
                    }

                    let status = child.wait();
                    let success = status.map(|s| s.success()).unwrap_or(false);
                    let msg = if success { "Update complete".to_string() } else { "Update failed".to_string() };
                    let _ = tx.send(AsyncResponse::EosOverlayStatus(success, msg));
                }
                Err(e) => {
                    let _ = tx.send(AsyncResponse::EosOverlayStatus(false, format!("Failed to start update: {}", e)));
                }
            }
        });
    }

    fn removeEosOverlay(&self) -> bool {
        crate::core::legendary::LegendaryWrapper::eos_overlay_remove().is_ok()
    }

    fn checkForUpdates(&self) {
        let current_version = env!("CARGO_PKG_VERSION");
        let client = reqwest::blocking::Client::builder()
            .user_agent("Theophany")
            .build()
            .unwrap_or_default();

        let latest_url = "https://api.github.com/repos/oldlamps/theophany/releases/latest";
        
        log::info!("[AppInfo] Checking for updates at: {}", latest_url);
        log::info!("[AppInfo] Current version: {}", current_version);

        match client.get(latest_url).send() {
            Ok(response) => {
                log::info!("[AppInfo] GitHub Response Status: {}", response.status());
                if let Ok(json) = response.json::<serde_json::Value>() {
                    if let Some(tag_name) = json["tag_name"].as_str() {
                        let latest_version = tag_name.trim_start_matches('v');
                        log::info!("[AppInfo] Latest release version found: {}", latest_version);
                        
                        if is_version_greater(latest_version, current_version) {
                            log::info!("[AppInfo] New update available! {} > {}", latest_version, current_version);
                            let notes = json["body"].as_str().unwrap_or("").to_string();
                            let url = json["html_url"].as_str().unwrap_or("").to_string();
                            self.updateAvailable(latest_version.to_string(), notes, url);
                        } else {
                            log::info!("[AppInfo] App is up to date ({} <= {})", latest_version, current_version);
                        }
                    } else {
                        log::warn!("[AppInfo] No tag_name found in GitHub response");
                    }
                } else {
                    log::error!("[AppInfo] Failed to parse GitHub JSON response");
                }
            }
            Err(e) => {
                log::error!("[AppInfo] Failed to check for updates: {}", e);
            }
        }
    }
}

fn is_version_greater(latest: &str, current: &str) -> bool {
    fn sanitize(v: &str) -> &str {
        v.trim_start_matches('v').split('-').next().unwrap_or("0")
    }
    
    let latest_clean = sanitize(latest);
    let current_clean = sanitize(current);

    let latest_parts: Vec<&str> = latest_clean.split('.').collect();
    let current_parts: Vec<&str> = current_clean.split('.').collect();

    for i in 0..std::cmp::max(latest_parts.len(), current_parts.len()) {
        let latest_part = latest_parts.get(i).and_then(|&s| s.parse::<u32>().ok()).unwrap_or(0);
        let current_part = current_parts.get(i).and_then(|&s| s.parse::<u32>().ok()).unwrap_or(0);

        if latest_part > current_part {
            return true;
        } else if latest_part < current_part {
            return false;
        }
    }
    false
}
