use std::path::PathBuf;

pub fn get_data_dir() -> PathBuf {
    // Respect XDG_DATA_HOME if set (Flatpak sets this to the sandboxed data dir).
    // Falls back to the XDG default of ~/.local/share for native installs.
    let base = std::env::var("XDG_DATA_HOME").unwrap_or_else(|_| {
        let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
        format!("{}/.local/share", home)
    });
    let path = PathBuf::from(base).join("theophany");
    if !path.exists() {
        let _ = std::fs::create_dir_all(&path);
    }
    path
}

pub fn get_default_prefix_dir() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    let path = PathBuf::from(home).join("Games").join("theophany").join("default");
    if !path.exists() {
        let _ = std::fs::create_dir_all(&path);
    }
    path
}

pub fn get_default_install_dir() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    let path = PathBuf::from(home).join("Games");
    if !path.exists() {
        let _ = std::fs::create_dir_all(&path);
    }
    path
}


pub fn get_assets_dir() -> PathBuf {
    let path = get_data_dir().join("assets");
    if !path.exists() {
        let _ = std::fs::create_dir_all(&path);
    }
    path
}

pub fn get_tools_dir() -> PathBuf {
    let path = get_data_dir().join("tools");
    if !path.exists() {
        let _ = std::fs::create_dir_all(&path);
    }
    path
}

pub fn get_metadata_dir() -> PathBuf {
    let path = get_data_dir().join("Metadata");
    if !path.exists() {
        let _ = std::fs::create_dir_all(&path);
    }
    path
}

pub fn get_config_dir() -> PathBuf {
    // Respect XDG_CONFIG_HOME if set. In Flatpak this is the sandboxed config dir;
    // in native builds it falls back to the XDG default ~/.config.
    let base = std::env::var("XDG_CONFIG_HOME").unwrap_or_else(|_| {
        let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
        format!("{}/.config", home)
    });
    let path = PathBuf::from(base).join("theophany");
    if !path.exists() {
        let _ = std::fs::create_dir_all(&path);
    }
    path
}
pub fn get_proton_versions() -> Vec<(String, String)> {
    let mut versions = Vec::new();
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    
    // 1. compatibilitytools.d (Custom Protons like GE)
    let custom_path = PathBuf::from(&home).join(".local/share/Steam/compatibilitytools.d");
    if custom_path.exists() {
        if let Ok(entries) = std::fs::read_dir(custom_path) {
            for entry in entries.flatten() {
                if entry.path().is_dir() {
                    let name = entry.file_name().to_string_lossy().to_string();
                    versions.push((name, entry.path().to_string_lossy().to_string()));
                }
            }
        }
    }

    // 2. Steam common (Official Protons)
    let official_path = PathBuf::from(&home).join(".local/share/Steam/steamapps/common");
    if official_path.exists() {
         if let Ok(entries) = std::fs::read_dir(official_path) {
            for entry in entries.flatten() {
                let name = entry.file_name().to_string_lossy().to_string();
                if name.starts_with("Proton") && entry.path().is_dir() {
                    versions.push((name, entry.path().to_string_lossy().to_string()));
                }
            }
        }
    }

    versions.sort_by(|a, b| b.0.cmp(&a.0));
    versions
}
