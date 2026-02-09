use qmetaobject::prelude::*;

#[derive(QObject, Default)]
pub struct AppInfo {
    base: qt_base_class!(trait QObject),
    getDataPath: qt_method!(fn(&self) -> QString),
    getConfigPath: qt_method!(fn(&self) -> QString),
    getAssetsDir: qt_method!(fn(&self) -> QString),
    getTrayIconPath: qt_method!(fn(&self) -> QString),
    checkYtdlp: qt_method!(fn(&self, custom_path: String) -> String),
    getVersion: qt_method!(fn(&self) -> QString),
    checkForUpdates: qt_method!(fn(&self)),
    updateAvailable: qt_signal!(version: String, notes: String, url: String),
}

impl AppInfo {
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

    fn checkForUpdates(&self) {
        let current_version = env!("CARGO_PKG_VERSION");
        let client = reqwest::blocking::Client::builder()
            .user_agent("Theophany")
            .build()
            .unwrap_or_default();

        let latest_url = "https://api.github.com/repos/oldlamps/theophany/releases/latest";
        
        match client.get(latest_url).send() {
            Ok(response) => {
                if let Ok(json) = response.json::<serde_json::Value>() {
                    if let Some(tag_name) = json["tag_name"].as_str() {
                        let latest_version = tag_name.trim_start_matches('v');
                        
                        if is_version_greater(latest_version, current_version) {
                            let notes = json["body"].as_str().unwrap_or("").to_string();
                            let url = json["html_url"].as_str().unwrap_or("").to_string();
                            self.updateAvailable(latest_version.to_string(), notes, url);
                        }
                    }
                }
            }
            Err(e) => {
                log::error!("Failed to check for updates: {}", e);
            }
        }
    }
}

fn is_version_greater(latest: &str, current: &str) -> bool {
    let latest_parts: Vec<&str> = latest.split('.').collect();
    let current_parts: Vec<&str> = current.split('.').collect();

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
