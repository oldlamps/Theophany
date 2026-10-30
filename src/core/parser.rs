use std::path::Path;
use regex::Regex;
use crate::core::models::GameMetadata;

pub struct FileNameParser;

impl FileNameParser {
    pub fn parse(filename: &str, rom_id: &str) -> GameMetadata {
        let working_filename = Path::new(filename)
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or(filename)
            .to_string();

        let mut region = None;
        let mut final_tags = Vec::new();
        
        // Regex to find all (...) and [...]
        let tag_re = Regex::new(r"[\(\[][^\]\)]*[\)\]]").unwrap();
        
        let tags_content: Vec<String> = tag_re.find_iter(&working_filename)
            .map(|m| m.as_str().to_string())
            .collect();

        // 1. Identify specific metadata from tags
        for tag in &tags_content {
            let inner = &tag[1..tag.len()-1].trim();
            if inner.is_empty() { continue; }

            let mut is_region_tag = false;

            // Region Detection (expanded list)
            if region.is_none() {
                let region_names = ["USA", "Europe", "Japan", "World", "Australia", "Canada", "China", "Korea", "Brazil", "Netherlands", "Sweden", "France", "Germany", "Italy", "Spain", "En,Fr,De", "USA, Europe"];
                for r in region_names {
                    if inner.contains(r) {
                        region = Some(inner.to_string());
                        is_region_tag = true;
                        break;
                    }
                }
                
                // Fallback for No-Intro 1-letter codes if still not found
                if region.is_none() {
                    match *inner {
                        "U" => { region = Some("USA".to_string()); is_region_tag = true; },
                        "E" => { region = Some("Europe".to_string()); is_region_tag = true; },
                        "J" => { region = Some("Japan".to_string()); is_region_tag = true; },
                        "W" => { region = Some("World".to_string()); is_region_tag = true; },
                        "A" => { region = Some("Australia".to_string()); is_region_tag = true; },
                        _ => {}
                    }
                }
            }

            // Version/Revision/Disc - we keep these in final_tags but they help identify what to remove from title
            if !is_region_tag {
                final_tags.push(inner.to_string());
            }
        }

        // 2. Clean up title by removing ALL tags (at start, middle or end)
        let mut clean_title = tag_re.replace_all(&working_filename, "").to_string();
        
        clean_title = clean_title.replace("_", " ")
                     .replace("-", " ")
                     .replace(".", " ");
        
        // Final trim and collapse multiple spaces
        let re_spaces = Regex::new(r"\s+").unwrap();
        clean_title = re_spaces.replace_all(&clean_title, " ").trim().to_string();

        // If title is empty (it was all tags?), fallback to filename stem
        if clean_title.is_empty() {
             clean_title = working_filename;
        }

        GameMetadata {
            rom_id: rom_id.to_string(),
            title: Some(clean_title),
            description: None,
            rating: None,
            release_date: None,
            developer: None,
            publisher: None,
            genre: None,
            tags: if final_tags.is_empty() { None } else { Some(final_tags.join(", ")) },
            region,
            is_favorite: false,
            play_count: 0,
            last_played: None,
            total_play_time: 0,
            achievement_count: None,
            achievement_unlocked: None,
            ra_game_id: None,
            ra_recent_badges: None,
            is_installed: true,
            cloud_saves_supported: false,
            resources: None,
        }
    }
}
