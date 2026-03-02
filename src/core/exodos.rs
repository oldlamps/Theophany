use crate::core::models::Rom;
use crate::core::paths::get_data_dir;
use std::path::Path;
use std::fs;
use std::os::unix::fs::symlink;
use walkdir::WalkDir;
use uuid::Uuid;
use chrono;
use quick_xml::events::Event;
use quick_xml::reader::Reader;

pub struct ExoDosManager;

#[derive(Debug, Default, Clone)]
pub struct ExoDosXmlGame {
    pub title: String,
    pub application_path: String,
    pub developer: Option<String>,
    pub publisher: Option<String>,
    pub genre: Option<String>,
    pub release_date: Option<String>,
    pub notes: Option<String>,
    pub favorite: bool,
    pub play_mode: Option<String>,
}

impl ExoDosManager {
    /// Scans a directory for ExoDOS games.
    /// The base_path is the folder selected by the user.
    /// We expect to find eXo/eXoDOS/!dos/ within it.
    pub fn scan_directory(base_path: &Path) -> Vec<Rom> {
        let mut roms = Vec::new();
        let dos_path = base_path.join("eXo/eXoDOS/!dos");
        
        log::info!("Scanning eXoDOS directory: {:?}", dos_path);

        if !dos_path.exists() {
            log::warn!("eXoDOS path not found: {:?}", dos_path);
            return roms;
        }

        // Each subfolder in !dos is a game
        if let Ok(entries) = std::fs::read_dir(&dos_path) {
            for entry in entries.flatten() {
                if let Ok(file_type) = entry.file_type() {
                    if file_type.is_dir() {
                        let game_dir = entry.path();
                        // Each game dir has a .command file
                        if let Ok(game_entries) = std::fs::read_dir(&game_dir) {
                            for game_entry in game_entries.flatten() {
                                let path = game_entry.path();
                                if path.extension().and_then(|s| s.to_str()) == Some("command") {
                                    let filename = path.file_name().unwrap_or_default().to_string_lossy().to_string();
                                    if filename.to_lowercase() == "install.command" {
                                        continue;
                                    }

                                    let mut title = path.file_stem().and_then(|s| s.to_str()).unwrap_or("Unknown Game").to_string();
                                    
                                    // Remove (Year) from title
                                    if let Some(pos) = title.find(" (") {
                                        if title.ends_with(')') {
                                            let potential_year = &title[pos + 2..title.len() - 1];
                                            if potential_year.chars().all(|c| c.is_ascii_digit()) && potential_year.len() == 4 {
                                                title = title[..pos].to_string();
                                            }
                                        }
                                    }

                                    let game_folder_name = game_dir.file_name().unwrap_or_default().to_string_lossy().to_string();
                                    let rom_id = format!("exodos-{}", game_folder_name.replace(" ", "-").to_lowercase());
                                    let mut resources = Vec::new();

                                     let mut extras_path = game_dir.join("Extras");
                                     if !extras_path.exists() {
                                         extras_path = game_dir.join("extras");
                                     }

                                     // Alternate Launcher always exists for eXoDOS games — add it without scanning
                                     resources.push(crate::core::models::GameResource {
                                         id: Uuid::new_v4().to_string(),
                                         rom_id: rom_id.clone(),
                                         type_: "launcher".to_string(),
                                         url: extras_path.join("Alternate Launcher.command").to_string_lossy().to_string(),
                                         label: Some("Alternate Launcher".to_string()),
                                     });

                                     // Still scan Extras for other resources (manuals, maps, etc.)
                                     if extras_path.exists() && extras_path.is_dir() {
                                         if let Ok(extras_entries) = std::fs::read_dir(&extras_path) {
                                             for extra_entry in extras_entries.flatten() {
                                                 let extra_path = extra_entry.path();
                                                 if extra_path.is_file() {
                                                     let extra_filename = extra_path.file_name().unwrap_or_default().to_string_lossy().to_string();
                                                     // Skip Alternate Launcher variants — already added above
                                                     if extra_filename.starts_with("Alternate Launcher") {
                                                         continue;
                                                     }
                                                     log::debug!("Found extra resource: {}", extra_filename);
                                                     resources.push(crate::core::models::GameResource {
                                                         id: Uuid::new_v4().to_string(),
                                                         rom_id: rom_id.clone(),
                                                         type_: "generic".to_string(),
                                                         url: extra_path.to_string_lossy().to_string(),
                                                         label: Some(extra_path.file_stem().unwrap_or_default().to_string_lossy().to_string()),
                                                     });
                                                 }
                                             }
                                         }
                                     }

                                     // Scan Magazines folder for .command files
                                     let magazines_path = game_dir.join("Magazines");
                                     if magazines_path.exists() && magazines_path.is_dir() {
                                         if let Ok(mag_entries) = std::fs::read_dir(&magazines_path) {
                                             for mag_entry in mag_entries.flatten() {
                                                 let mag_path = mag_entry.path();
                                                 if mag_path.is_file() && mag_path.extension().and_then(|e| e.to_str()) == Some("command") {
                                                     let label = mag_path.file_stem().unwrap_or_default().to_string_lossy().to_string();
                                                     log::debug!("Found magazine: {}", label);
                                                     resources.push(crate::core::models::GameResource {
                                                         id: Uuid::new_v4().to_string(),
                                                         rom_id: rom_id.clone(),
                                                         type_: "magazine".to_string(),
                                                         url: mag_path.to_string_lossy().to_string(),
                                                         label: Some(label),
                                                     });
                                                 }
                                             }
                                         }
                                     }

                                    roms.push(Rom {
                                        id: rom_id,
                                        platform_id: "DOS".to_string(), 
                                        path: path.to_string_lossy().to_string(),
                                        filename: path.file_name().unwrap_or_default().to_string_lossy().to_string(),
                                        file_size: 0,
                                        hash_sha1: None,
                                        title: Some(title),
                                        region: None,
                                        platform_name: Some("eXoDOS".to_string()),
                                        platform_type: Some("DOS".to_string()),
                                        platform_icon: Some("dos".to_string()),
                                        boxart_path: None,
                                        icon_path: None,
                                        background_path: None,
                                        date_added: Some(chrono::Utc::now().timestamp()),
                                        play_count: Some(0),
                                        total_play_time: Some(0),
                                        last_played: None,
                                        is_favorite: Some(false),
                                        genre: None,
                                        developer: None,
                                        publisher: None,
                                        rating: None,
                                        tags: None,
                                        release_date: None,
                                        description: None,
                                        is_installed: Some(true),
                                        cloud_saves_supported: None,
                                        resources: if resources.is_empty() { None } else { Some(resources) },
                                    });
                                }
                            }
                        }
                    }
                }
            }
        }

        // Attempt to enrich with XML metadata if available
        let xml_path = base_path.join("xml/all/MS-DOS.xml");
        if xml_path.exists() {
            log::debug!("Found XML metadata file, parsing...");
            let xml_games = Self::parse_exodos_metadata(&xml_path);
            
            for rom in roms.iter_mut() {
                // Try to match by filename or fallback to title
                let rom_filename = &rom.filename;
                let rom_title = rom.title.as_deref().unwrap_or("");
                
                let matched_game = xml_games.iter().find(|xml| {
                    // Extract the filename stem from the XML ApplicationPath (handling Windows backslashes)
                    let xml_path_str = &xml.application_path;
                    let xml_file_name = xml_path_str.split('\\').last().unwrap_or("");
                    let xml_stem = Path::new(xml_file_name).file_stem().and_then(|s| s.to_str()).unwrap_or("");
                    
                    // Extract the filename stem from our actual scanned ROM
                    let rom_stem = Path::new(rom_filename).file_stem().and_then(|s| s.to_str()).unwrap_or("");
                    
                    // Match by filename stem (case-insensitive) - e.g. "Amulet, The (1983)"
                    let has_stem_match = !xml_stem.is_empty() && xml_stem.eq_ignore_ascii_case(rom_stem);
                    
                    has_stem_match || xml.title.eq_ignore_ascii_case(rom_title)
                });
                
                if let Some(xml_game) = matched_game {
                    rom.title = Some(xml_game.title.clone());
                    rom.developer = xml_game.developer.clone();
                    rom.publisher = xml_game.publisher.clone();
                    rom.genre = xml_game.genre.clone();
                    // Just the year for ReleaseDate
                    if let Some(mut rd) = xml_game.release_date.clone() {
                        if let Ok(dt) = chrono::DateTime::parse_from_rfc3339(&rd) {
                            rd = dt.format("%Y").to_string();
                        } else if rd.len() >= 4 {
                           rd = rd[0..4].to_string(); 
                        }
                        rom.release_date = Some(rd);
                    }
                    rom.description = xml_game.notes.clone();
                    
                    let mut tag_list = Vec::new(); // Don't add ExoDOS tag per user request
                    if xml_game.favorite {
                       rom.is_favorite = Some(true);
                       tag_list.push("Favorite".to_string());
                    }
                    if let Some(pm) = xml_game.play_mode.as_ref() {
                        for mode in pm.split(';') {
                            let m = mode.trim();
                            if !m.is_empty() {
                                tag_list.push(m.to_string());
                            }
                        }
                    }
                    if !tag_list.is_empty() {
                        rom.tags = Some(tag_list.join(", "));
                    } else {
                        rom.tags = None;
                    }
                }
            }
        }

        roms
    }

    /// Parses the LaunchBox XML file to extract game metadata
    pub fn parse_exodos_metadata(xml_path: &Path) -> Vec<ExoDosXmlGame> {
        let mut reader = match Reader::from_file(xml_path) {
            Ok(r) => r,
            Err(_) => return Vec::new(),
        };
        reader.trim_text(true);

        let mut buf = Vec::new();
        let mut games = Vec::new();
        let mut current_game = ExoDosXmlGame::default();
        let mut in_game = false;
        let mut current_tag = String::new();

        loop {
            match reader.read_event_into(&mut buf) {
                Ok(Event::Start(ref e)) => {
                    let tag_name = String::from_utf8_lossy(e.name().as_ref()).to_string();
                    if tag_name == "Game" {
                        in_game = true;
                        current_game = ExoDosXmlGame::default();
                    } else if in_game {
                        current_tag = tag_name;
                    }
                }
                Ok(Event::Text(e)) => {
                    if in_game {
                        let text = e.unescape().unwrap_or_default().into_owned();
                        match current_tag.as_str() {
                            "Title" => current_game.title = text,
                            "ApplicationPath" => current_game.application_path = text,
                            "Developer" => current_game.developer = Some(text),
                            "Publisher" => current_game.publisher = Some(text),
                            "Genre" => current_game.genre = Some(text.replace("; ", ", ").replace(";", ", ")),
                            "ReleaseDate" => current_game.release_date = Some(text),
                            "Notes" => current_game.notes = Some(text),
                            "Favorite" => current_game.favorite = text == "true",
                            "PlayMode" => current_game.play_mode = Some(text),
                            _ => {}
                        }
                    }
                }
                Ok(Event::End(ref e)) => {
                    let tag_name = String::from_utf8_lossy(e.name().as_ref()).to_string();
                    if tag_name == "Game" {
                        in_game = false;
                        games.push(current_game.clone());
                    }
                    current_tag.clear();
                }
                Ok(Event::Eof) => break,
                Err(e) => {
                    log::error!("Error parsing ExoDOS XML at position {}: {:?}", reader.buffer_position(), e);
                    break;
                }
                _ => (),
            }
            buf.clear();
        }
        games
    }

    /// Creates symbolic links for the artwork of a game.
    /// title: The title of the game (as used in ExoDOS filenames).
    /// images_base_path: The base path for ExoDOS images (e.g., .../Images/MS-DOS/).
    /// platform_folder: The folder name for the platform (e.g., "dos").
    /// rom_stem: The filename stem of the game (e.g., "Digger").
    pub fn link_artwork(title: &str, images_base_path: &Path, platform_folder: &str, rom_stem: &str) {
        let base_assets_dir = get_data_dir().join("Images").join(platform_folder).join(rom_stem);
        
        let mappings = [
            ("Box - Front", "Box - Front"),
            ("Box - Back", "Box - Back"),
            ("Box - 3D", "Box - 3D"),
            ("Screenshot - Gameplay", "Screenshot"),
            ("Screenshot - Game Title", "Screenshot"),
            ("Fanart - Background", "Background"),
            ("Clear Logo", "Logo"),
        ];

        let mut printed_log = false;

        for (exo_cat, target_cat) in mappings {
            let cat_path = images_base_path.join(exo_cat);
            if !cat_path.exists() {
                continue;
            }

            let dest_dir = base_assets_dir.join(target_cat);
            if !dest_dir.exists() {
                let _ = fs::create_dir_all(&dest_dir);
            }

            let norm_name = target_cat.to_lowercase().replace(" ", "_");

            for entry in WalkDir::new(&cat_path).into_iter().flatten() {
                if entry.file_type().is_file() {
                    let path = entry.path();
                    let file_name = path.file_name().unwrap_or_default().to_string_lossy();
                    
                    let normalized_title = title.replace('\'', "_").replace(':', "_");
                    if file_name.starts_with(normalized_title.as_str()) {
                        let extension = path.extension().and_then(|e| e.to_str()).unwrap_or("jpg");
                        
                        // Extract suffix from file_name (e.g. "-01")
                        let stem = path.file_stem().map(|s| s.to_string_lossy()).unwrap_or_default();
                        let suffix = if stem.len() > normalized_title.len() {
                            &stem[normalized_title.len()..]
                        } else {
                            ""
                        };

                        let target_path = dest_dir.join(format!("{}{}.{}", norm_name, suffix, extension));
                        
                        if target_path.exists() || target_path.is_symlink() {
                            continue;
                        }

                        if !printed_log {
                            log::debug!("Linking artwork for {} from {:?} to {:?}", title, images_base_path, base_assets_dir);
                            printed_log = true;
                        }

                        log::debug!("Linking artwork: {:?} -> {:?}", path, target_path);
                        #[cfg(unix)]
                        let _ = symlink(path, &target_path);
                        #[cfg(not(unix))]
                        let _ = fs::copy(path, &target_path);
                    }
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs::{self, File};
    use tempfile::tempdir;

    #[test]
    fn test_exodos_scanner() {
        let dir = tempdir().unwrap();
        let root = dir.path();
        
        // Create ExoDOS structure: eXo/eXoDOS/!dos/GameName/GameName.command
        let dos_path = root.join("eXo/eXoDOS/!dos");
        fs::create_dir_all(&dos_path).unwrap();
        
        let game1_dir = dos_path.join("Digger (1983)");
        fs::create_dir(&game1_dir).unwrap();
        File::create(game1_dir.join("Digger (1983).command")).unwrap();
        File::create(game1_dir.join("readme.txt")).unwrap();
        
        let game2_dir = dos_path.join("Zork I (1980)");
        fs::create_dir(&game2_dir).unwrap();
        File::create(game2_dir.join("Zork I (1980).command")).unwrap();
        File::create(game2_dir.join("install.command")).unwrap();

        // Create Extras folder for game2
        let extras_dir = game2_dir.join("Extras");
        fs::create_dir(&extras_dir).unwrap();
        File::create(extras_dir.join("Alternate Launcher.command")).unwrap();
        File::create(extras_dir.join("Manual.pdf")).unwrap();
        File::create(extras_dir.join("Map.jpg")).unwrap();

        let roms = ExoDosManager::scan_directory(root);
        
        assert_eq!(roms.len(), 2);
        let titles: Vec<String> = roms.iter().map(|r| r.title.clone().unwrap()).collect();
        assert!(titles.contains(&"Digger".to_string()));
        assert!(titles.contains(&"Zork I".to_string()));
        assert!(!titles.contains(&"install".to_string()));
        assert!(roms.iter().all(|r| r.platform_id == "DOS"));

        // Verify Extras for Zork I
        let zork = roms.iter().find(|r| r.title.as_ref().unwrap() == "Zork I").unwrap();
        let resources = zork.resources.as_ref().expect("Zork I should have resources");
        assert_eq!(resources.len(), 3);
        
        let launcher = resources.iter().find(|r| r.type_ == "launcher").expect("Should have a launcher");
        assert_eq!(launcher.label.as_ref().unwrap(), "Alternate Launcher");
        
        let generic_count = resources.iter().filter(|r| r.type_ == "generic").count();
        assert_eq!(generic_count, 2, "Should have 2 generic resources");
    }

    #[test]
    fn test_parse_exodos_metadata() {
        let dir = tempdir().unwrap();
        let xml_path = dir.path().join("MS-DOS.xml");
        
        let xml_content = r#"<?xml version="1.0"?>
<LaunchBox>
  <Game>
    <Title>Test Game</Title>
    <ApplicationPath>..\eXo\eXoDOS\!dos\Test\Test.bat</ApplicationPath>
    <Developer>DevInc</Developer>
    <Publisher>PubCorp</Publisher>
    <Genre>Action; Adventure</Genre>
    <ReleaseDate>1993-05-01T00:00:00-05:00</ReleaseDate>
    <Notes>This is a test game.</Notes>
    <Favorite>true</Favorite>
  </Game>
</LaunchBox>"#;

        fs::write(&xml_path, xml_content).unwrap();
        
        let games = ExoDosManager::parse_exodos_metadata(&xml_path);
        assert_eq!(games.len(), 1);
        let game = &games[0];
        
        assert_eq!(game.title, "Test Game");
        assert_eq!(game.application_path, "..\\eXo\\eXoDOS\\!dos\\Test\\Test.bat");
        assert_eq!(game.developer, Some("DevInc".to_string()));
        assert_eq!(game.publisher, Some("PubCorp".to_string()));
        assert_eq!(game.genre, Some("Action, Adventure".to_string()));
        assert_eq!(game.release_date, Some("1993-05-01T00:00:00-05:00".to_string()));
        assert_eq!(game.notes, Some("This is a test game.".to_string()));
        assert_eq!(game.favorite, true);
    }

    #[test]
    fn test_exodos_xml_stem_matching() {
        let dir = tempdir().unwrap();
        let root = dir.path();
        
        // 1. Create scanned structure
        let dos_path = root.join("eXo/eXoDOS/!dos");
        fs::create_dir_all(&dos_path).unwrap();
        let game_dir = dos_path.join("Amulet, The (1983)");
        fs::create_dir(&game_dir).unwrap();
        // Local file is .command
        File::create(game_dir.join("Amulet, The (1983).command")).unwrap();
        
        // 2. Create XML registry
        let xml_dir = root.join("xml/all");
        fs::create_dir_all(&xml_dir).unwrap();
        let xml_path = xml_dir.join("MS-DOS.xml");
        
        let xml_content = r#"<?xml version="1.0"?>
<LaunchBox>
  <Game>
    <Title>The Amulet</Title>
    <ApplicationPath>..\eXo\eXoDOS\!dos\Amulet83\Amulet, The (1983).bat</ApplicationPath>
    <Notes>Matched by stem!</Notes>
  </Game>
</LaunchBox>"#;
        fs::write(&xml_path, xml_content).unwrap();
        
        // 3. Scan and verify enrichment
        let roms = ExoDosManager::scan_directory(root);
        
        assert_eq!(roms.len(), 1);
        let rom = &roms[0];
        // Title should be pulled from XML ("The Amulet") instead of filename ("Amulet, The")
        assert_eq!(rom.title.as_ref().unwrap(), "The Amulet");
        // Notes should be pulled from XML
        assert_eq!(rom.description.as_ref().unwrap(), "Matched by stem!");
    }
}
