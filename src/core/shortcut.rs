use crate::core::db::DbManager;
use crate::core::paths;
use std::fs;
use std::path::PathBuf;
use std::process::Command;

pub fn create_application_shortcut(db_path: &str, rom_id: &str) -> Result<String, String> {
    create_shortcut(db_path, rom_id, false)
}

pub fn create_desktop_shortcut(db_path: &str, rom_id: &str) -> Result<String, String> {
    create_shortcut(db_path, rom_id, true)
}

pub fn create_shortcut(db_path: &str, rom_id: &str, to_desktop: bool) -> Result<String, String> {
    let db = DbManager::open(db_path).map_err(|e| format!("Failed to open database: {}", e))?;
    let conn = db.get_connection();

    let mut stmt = conn.prepare(
        "SELECT COALESCE(m.title, r.filename), r.boxart_path, r.icon_path, p.icon 
         FROM roms r 
         LEFT JOIN metadata m ON r.id = m.rom_id 
         LEFT JOIN platforms p ON r.platform_id = p.id 
         WHERE r.id = ?1"
    ).map_err(|e| format!("Failed to prepare query: {}", e))?;

    let row = stmt.query_row([rom_id], |row| {
        let title: String = row.get(0)?;
        let boxart_path: Option<String> = row.get(1)?;
        let rom_icon_path: Option<String> = row.get(2)?;
        let platform_icon: Option<String> = row.get(3)?;
        Ok((title, boxart_path, rom_icon_path, platform_icon))
    }).map_err(|e| format!("Game not found: {}", e))?;

    let (title, boxart_path, rom_icon_path, platform_icon) = row;

    let icon_path = resolve_icon_path(boxart_path.as_deref().or(rom_icon_path.as_deref()), platform_icon.as_deref());

    let exec_cmd = format!("theophany --launch \"{}\"", rom_id);

    let safe_title = sanitize_filename(&title);

    let (target_dir, desktop_filename, msg_label) = if to_desktop {
        (paths::get_desktop_dir(), format!("{}.desktop", safe_title), "Desktop shortcut")
    } else {
        (paths::get_applications_dir(), format!("theophany-{}.desktop", safe_title), "Application shortcut")
    };

    let desktop_filepath = target_dir.join(&desktop_filename);

    let desktop_content = format!(
        "[Desktop Entry]\n\
         Type=Application\n\
         Name={}\n\
         Exec={}\n\
         Icon={}\n\
         Terminal=false\n\
         Categories=Game;\n\
         StartupNotify=true\n",
        title,
        exec_cmd,
        icon_path
    );

    fs::write(&desktop_filepath, desktop_content)
        .map_err(|e| format!("Failed to write desktop file: {}", e))?;

    if !to_desktop {
        let _ = Command::new("update-desktop-database")
            .arg(target_dir.to_string_lossy().to_string())
            .output();
    }

    Ok(format!("{} created for '{}'", msg_label, title))
}

fn resolve_icon_path(cover_url: Option<&str>, platform_icon: Option<&str>) -> String {
    if let Some(cover) = cover_url {
        if !cover.is_empty() {
            let path_str = if cover.starts_with("file://") {
                cover.trim_start_matches("file://")
            } else if cover.starts_with("assets/") {
                return paths::get_data_dir().join(cover).to_string_lossy().to_string();
            } else {
                cover
            };
            if PathBuf::from(path_str).exists() {
                return path_str.to_string();
            }
        }
    }

    if let Some(p_icon) = platform_icon {
        if !p_icon.is_empty() {
            let path_str = if p_icon.starts_with("file://") {
                p_icon.trim_start_matches("file://")
            } else if p_icon.starts_with("assets/") {
                return paths::get_data_dir().join(p_icon).to_string_lossy().to_string();
            } else {
                p_icon
            };
            if PathBuf::from(path_str).exists() {
                return path_str.to_string();
            }
        }
    }

    let logo_path = paths::get_assets_dir().join("logo.png");
    if logo_path.exists() {
        logo_path.to_string_lossy().to_string()
    } else {
        "theophany".to_string()
    }
}

fn sanitize_filename(title: &str) -> String {
    let mut safe = String::new();
    for c in title.chars() {
        match c {
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' => {
                safe.push('_');
            }
            _ => safe.push(c),
        }
    }
    let trimmed = safe.trim().to_string();
    if trimmed.is_empty() {
        "Game".to_string()
    } else {
        trimmed
    }
}
