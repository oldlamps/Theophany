#![allow(non_snake_case)]
use crate::core::db::DbManager;
use crate::core::models::EmulatorProfile;
use qmetaobject::prelude::*;
use qmetaobject::QVariantList;
use std::cell::RefCell;
use uuid::Uuid;

#[derive(QObject, Default)]
pub struct EmulatorListModel {
    // Parent class: QAbstractListModel
    base: qt_base_class!(trait QAbstractListModel),

    // Internal data storage
    profiles: RefCell<Vec<EmulatorProfile>>,
    
    // DB Access
    db_path: RefCell<String>,

    // Methods exposed to QML
    init: qt_method!(fn(&mut self, db_path: String)),
    refresh: qt_method!(fn(&mut self)),
    addProfile: qt_method!(fn(&mut self, name: String, path: String, args: String, is_retroarch: bool, core: String)),
    updateProfile: qt_method!(fn(&mut self, id: String, name: String, path: String, args: String, is_retroarch: bool, core: String)),
    deleteProfile: qt_method!(fn(&mut self, id: String)),
    
    // RetroArch Helpers
    // RetroArch Helpers
    detectRetroArch: qt_method!(fn(&mut self) -> QString),
    getRetroArchCores: qt_method!(fn(&mut self) -> QVariantList),
    
    // New Generic Helpers
    getSupportedPresets: qt_method!(fn(&mut self) -> QString),
    detectEmulator: qt_method!(fn(&mut self, app_id: String, binary: String) -> QString),
}

impl QAbstractListModel for EmulatorListModel {
    fn row_count(&self) -> i32 {
        self.profiles.borrow().len() as i32
    }

    fn data(&self, index: QModelIndex, role: i32) -> QVariant {
        let profiles = self.profiles.borrow();
        let idx = index.row() as usize;

        if idx >= profiles.len() {
            return QVariant::default();
        }

        let profile = &profiles[idx];

        match role {
            // Qt::DisplayRole = 0
            0 => QVariant::from(QString::from(profile.name.as_str())), 
            
            // Custom Roles
            256 => QVariant::from(QString::from(profile.id.as_str())),       // idRole
            257 => QVariant::from(QString::from(profile.name.as_str())),     // nameRole
            258 => QVariant::from(QString::from(profile.executable_path.as_str())), // pathRole
            259 => QVariant::from(QString::from(profile.arguments.as_str())), // argsRole
            260 => QVariant::from(profile.is_retroarch),                      // isRetroArchRole
            261 => QVariant::from(QString::from(profile.retroarch_core.clone().unwrap_or_default().as_str())), // coreRole
            _ => QVariant::default(),
        }
    }

    fn role_names(&self) -> std::collections::HashMap<i32, QByteArray> {
        let mut roles = std::collections::HashMap::new();
        roles.insert(256, QByteArray::from("profileId"));
        roles.insert(257, QByteArray::from("profileName"));
        roles.insert(258, QByteArray::from("profilePath"));
        roles.insert(259, QByteArray::from("profileArgs"));
        roles.insert(260, QByteArray::from("isRetroArch"));
        roles.insert(261, QByteArray::from("profileCore"));
        roles
    }
}

impl EmulatorListModel {
    fn init(&mut self, db_path: String) {
        *self.db_path.borrow_mut() = db_path;
        self.refresh();
    }

    fn refresh(&mut self) {
        let path = self.db_path.borrow().clone();
        if path.is_empty() {
            return;
        }

        if let Ok(db) = DbManager::open(&path) {
             // We need to add get_all_emulator_profiles to DbManager first.
             // For now we will mock or implement that method.
             // Let's assume DbManager has it or we will add it shortly.
             if let Ok(profiles) = db.get_all_emulator_profiles() {
                 self.begin_reset_model();
                 *self.profiles.borrow_mut() = profiles;
                 self.end_reset_model();
             }
        }
    }

    #[allow(non_snake_case)]
    fn addProfile(&mut self, name: String, path: String, args: String, is_retroarch: bool, core: String) {
        let db_path = self.db_path.borrow().clone();
        if db_path.is_empty() { return; }

        let id = Uuid::new_v4().to_string();
        let retroarch_core = if core.is_empty() { None } else { Some(core) };

        let profile = EmulatorProfile {
            id,
            name,
            executable_path: path,
            arguments: args,
            is_retroarch,
            retroarch_core,
        };

        if let Ok(db) = DbManager::open(&db_path) {
            if let Err(e) = db.insert_emulator_profile(&profile) {
                log::error!("Failed to insert profile: {}", e);
            }
        }
        self.refresh();
    }

    #[allow(non_snake_case)]
    fn updateProfile(&mut self, id: String, name: String, path: String, args: String, is_retroarch: bool, core: String) {
         let db_path = self.db_path.borrow().clone();
        if db_path.is_empty() { return; }

        let retroarch_core = if core.is_empty() { None } else { Some(core) };

        let profile = EmulatorProfile {
            id,
            name,
            executable_path: path,
            arguments: args,
            is_retroarch,
            retroarch_core,
        };

        if let Ok(db) = DbManager::open(&db_path) {
             if let Err(e) = db.insert_emulator_profile(&profile) { // Using insert_or_replace
                log::error!("Failed to update profile: {}", e);
            }
        }
        self.refresh();
    }

    #[allow(non_snake_case)]
    fn deleteProfile(&mut self, id: String) {
         let db_path = self.db_path.borrow().clone();
        if db_path.is_empty() { return; }

        if let Ok(db) = DbManager::open(&db_path) {
            if let Err(e) = db.delete_emulator_profile(&id) {
                log::error!("Failed to delete profile: {}", e);
            }
        }
        self.refresh();
    }

    #[allow(non_snake_case)]
    fn detectRetroArch(&mut self) -> QString {
        // Check for flatpak
        if let Ok(output) = std::process::Command::new("flatpak").arg("info").arg("org.libretro.RetroArch").output() {
             if output.status.success() {
                 return QString::from("flatpak run org.libretro.RetroArch");
             }
        }
        
        // Check standard paths
        let paths = ["/usr/bin/retroarch", "/usr/local/bin/retroarch", "/opt/retroarch/bin/retroarch"];
        for p in paths.iter() {
            if std::path::Path::new(p).exists() {
                return QString::from(*p);
            }
        }
        
        QString::from("")
    }

    #[allow(non_snake_case)]
    fn getRetroArchCores(&mut self) -> QVariantList {
        let mut cores = Vec::new();
        let mut visited_paths = std::collections::HashSet::new();
        
        // Define search paths
        let mut search_paths = vec![
            "/usr/lib/libretro".to_string(),
            "/usr/lib/x86_64-linux-gnu/libretro".to_string(), 
            "/usr/lib64/libretro".to_string(), // Fedora/OpenSUSE
        ];
        
        // Add home directory paths
        if let Ok(home) = std::env::var("HOME") {
            search_paths.push(format!("{}/.var/app/org.libretro.RetroArch/config/retroarch/cores", home)); // Flatpak
            search_paths.push(format!("{}/.config/retroarch/cores", home)); // Standard
            search_paths.push(format!("{}/.local/share/retroarch/cores", home)); // Local/Self-built
            search_paths.push(format!("{}/snap/retroarch/current/.config/retroarch/cores", home)); // Snap
        }
        
        for path_str in search_paths {
            let path = std::path::Path::new(&path_str);
            if path.exists() && path.is_dir() {
                 if let Ok(entries) = std::fs::read_dir(path) {
                     for entry in entries.flatten() {
                         let p = entry.path();
                         if let Some(ext) = p.extension() {
                             if ext == "so" {
                                 if let Some(_name_os) = p.file_stem() {
                                     // let name = name_os.to_string_lossy().to_string().replace("_libretro", ""); 
                                     let full_path = p.to_string_lossy().to_string();
                                     
                                     if !visited_paths.contains(&full_path) {
                                          visited_paths.insert(full_path.clone());
                                          cores.push(QString::from(full_path));
                                     }
                                 }
                             }
                         }
                     }
                 }
            }
        }
        
        let mut q_list = QVariantList::default();
        for core in cores {
             q_list.push(QVariant::from(core));
        }
        q_list
    }


    #[allow(non_snake_case)]
    fn getSupportedPresets(&mut self) -> QString {
        let presets = r#"[
            {"name": "Custom", "id": "custom", "binary": "", "args": "", "isRa": false, "recommendation": ""},
            {"name": "RetroArch", "id": "retroarch", "binary": "retroarch", "args": "-L %CORE% %ROM% -f", "isRa": true, "recommendation": "<b>Gold Standard for 8-Bit & 16-Bit Eras.</b><br>Low hardware requirements, excellent features (shaders, rewind). Ideal for NES, SNES, Genesis, GB/GBA."},
            
            {"name": "Dolphin (Nintendo GameCube/Wii)", "id": "org.DolphinEmu.dolphin-emu", "binary": "dolphin-emu", "args": "-b -e %ROM%", "isRa": false, "recommendation": "<b>Recommendation:</b> Use standalone for better motion control support and performance."},
            {"name": "PCSX2 (Sony PlayStation 2)", "id": "net.pcsx2.PCSX2", "binary": "pcsx2-qt,pcsx2", "args": "-fullscreen %ROM%", "isRa": false, "recommendation": "<b>Recommendation:</b> Version 2.0+ has massive performance gains that the RetroArch core lacks."},
            {"name": "RPCS3 (Sony PlayStation 3)", "id": "net.rpcs3.RPCS3", "binary": "rpcs3", "args": "--no-gui %ROM%", "isRa": false, "recommendation": "<b>Note:</b> Extremely demanding; requires a high-end CPU."},
            {"name": "DuckStation (Sony PlayStation)", "id": "org.duckstation.DuckStation", "binary": "duckstation-qt,duckstation", "args": "-fullscreen -batch %ROM%", "isRa": false, "recommendation": "<b>Recommendation:</b> Preferred for its 'PGXP' feature which fixes shaky 3D graphics."},
            {"name": "Cemu (Nintendo Wii U)", "id": "info.cemu.Cemu", "binary": "cemu", "args": "-f -g %ROM%", "isRa": false, "recommendation": "<b>Recommendation:</b> Excellent performance for Wii U titles."},
            {"name": "Ryujinx/yuzu (Nintendo Switch)", "id": "org.ryujinx.Ryujinx", "binary": "ryujinx,yuzu", "args": "%ROM%", "isRa": false, "recommendation": "<b>Recommendation:</b> The main focus for Switch emulation in 2026."},
            {"name": "RMG (Nintendo 64)", "id": "io.github.rosalie241.RMG", "binary": "RMG,rmg", "args": "--fullscreen %ROM%", "isRa": false, "recommendation": "<b>Recommendation:</b> N64 is hard. Mupen64Plus-Next (RetroArch) is great, but RMG is a solid standalone option."},
            
            {"name": "Redream (Sega Dreamcast)", "id": "io.retype.Redream", "binary": "redream", "args": "%ROM%", "isRa": false, "recommendation": "<b>Recommendation:</b> Incredibly easy to use and very fast on Android/PC."},
            {"name": "PPSSPP (Sony PSP)", "id": "org.ppsspp.PPSSPP", "binary": "PPSSPPQt,ppsspp", "args": "%ROM%", "isRa": false, "recommendation": "<b>Recommendation:</b> Both versions are excellent, but standalone gets updates faster."},
            {"name": "MelonDS (Nintendo DS)", "id": "net.kuribo64.melonDS", "binary": "melonDS,melonds", "args": "%ROM%", "isRa": false, "recommendation": "<b>Recommendation:</b> Supports local multiplayer/Wi-Fi features better than cores."},
            {"name": "Citra/Azahar (Nintendo 3DS)", "id": "org.citra-emu.citra", "binary": "citra-qt,citra,azahar", "args": "%ROM%", "isRa": false, "recommendation": "<b>Recommendation:</b> Best handled by standalone forks for screen layout options."}
        ]"#;
        QString::from(presets)
    }

    #[allow(non_snake_case)]
    fn detectEmulator(&mut self, app_id: String, binary: String) -> QString {
        if app_id.is_empty() || app_id == "custom" { return QString::from(""); }

        // 1. Check Flatpak
        if let Ok(output) = std::process::Command::new("flatpak").arg("info").arg(&app_id).output() {
             if output.status.success() {
                 return QString::from(format!("flatpak run {}", app_id));
             }
        }

        // 2. Check Standard Paths (iterate over comma-separated binary names)
        if !binary.is_empty() {
             let binaries: Vec<&str> = binary.split(',').map(|s| s.trim()).collect();
             
             for bin_name in binaries {
                 if bin_name.is_empty() { continue; }
                 
                 let paths = [
                     format!("/usr/bin/{}", bin_name),
                     format!("/usr/local/bin/{}", bin_name),
                     format!("/opt/{}/bin/{}", bin_name, bin_name), // e.g. /opt/cemu/bin/cemu
                     format!("/opt/bin/{}", bin_name),
                 ];
                 
                 for p in paths.iter() {
                     if std::path::Path::new(p).exists() {
                         return QString::from(p.as_str());
                     }
                 }
                 
                 // 3. Check `which` command as fallback for this binary alias
                 if let Ok(output) = std::process::Command::new("which").arg(bin_name).output() {
                     if output.status.success() {
                         let path = String::from_utf8_lossy(&output.stdout).trim().to_string();
                         if !path.is_empty() {
                             return QString::from(path);
                         }
                     }
                 }
             }
        }
        
        QString::from("")
    }
}
