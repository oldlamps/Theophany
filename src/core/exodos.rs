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

                                    roms.push(Rom {
                                        id: format!("exodos-{}", Uuid::new_v4()),
                                        platform_id: "DOS".to_string(), 
                                        path: path.to_string_lossy().to_string(),
                                        filename: path.file_name().unwrap_or_default().to_string_lossy().to_string(),
                                        file_size: 0,
                                        hash_sha1: None,
                                        title: Some(title),
                                        region: None,
                                        platform_name: Some("DOS".to_string()),
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
            log::info!("Found XML metadata file, parsing...");
            let xml_games = Self::parse_exodos_metadata(&xml_path);
            
            for rom in roms.iter_mut() {
                // Try to match by filename or fallback to title
                let rom_filename = &rom.filename;
                let rom_title = rom.title.as_deref().unwrap_or("");
                
                let matched_game = xml_games.iter().find(|xml| {
                    let xml_path_str = &xml.application_path;
                    let xml_file_name_opt = Path::new(xml_path_str).file_name().and_then(|n| n.to_str());
                    let has_path_match = xml_file_name_opt.map_or(false, |xml_fn| xml_fn == rom_filename);
                    
                    has_path_match || xml.title.eq_ignore_ascii_case(rom_title)
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

            // We use the normalized target name for the final symlink filename
            let norm_name = target_cat.to_lowercase().replace(" ", "_");

            // Check if we already have an asset for this category (even if it's a broken symlink)
            let mut already_has_asset = false;
            if let Ok(entries) = fs::read_dir(&dest_dir) {
                for e in entries.flatten() {
                    if e.file_name().to_string_lossy().starts_with(&norm_name) {
                        already_has_asset = true;
                        break;
                    }
                }
            }

            if already_has_asset {
                continue; // Skip WalkDir scanning if we already have the asset!
            }

            for entry in WalkDir::new(&cat_path).into_iter().flatten() {
                if entry.file_type().is_file() {
                    let path = entry.path();
                    let file_name = path.file_name().unwrap_or_default().to_string_lossy();
                    
                    if file_name.starts_with(title) {
                        let extension = path.extension().and_then(|e| e.to_str()).unwrap_or("jpg");
                        let target_path = dest_dir.join(format!("{}.{}", norm_name, extension));
                        if !printed_log {
                            log::info!("Linking artwork for {} from {:?} to {:?}", title, images_base_path, base_assets_dir);
                            printed_log = true;
                        }

                        log::debug!("Linking artwork: {:?} -> {:?}", path, target_path);
                        #[cfg(unix)]
                        if let Err(e) = symlink(path, &target_path) {
                            log::error!("Failed to create symlink: {}", e);
                        }
                        #[cfg(not(unix))]
                        if let Err(e) = fs::copy(path, &target_path) {
                            log::error!("Failed to copy artwork: {}", e);
                        }
                        
                        // If it's a screenshot or background, we might have multiple files.
                        // But for simplicity of the initial import, we break after the first match per Exo category.
                        // Since we have multiple Exo categories mapping to one target, we'll get one file from each source folder if it exists.
                        break; 
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

        let roms = ExoDosManager::scan_directory(root);
        
        assert_eq!(roms.len(), 2);
        let titles: Vec<String> = roms.iter().map(|r| r.title.clone().unwrap()).collect();
        assert!(titles.contains(&"Digger".to_string()));
        assert!(titles.contains(&"Zork I".to_string()));
        assert!(!titles.contains(&"install".to_string()));
        assert!(roms.iter().all(|r| r.platform_id == "DOS"));
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
}
