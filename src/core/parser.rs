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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_standard_parsing() {
        let meta = FileNameParser::parse("Sonic the Hedgehog (USA).zip", "1");
        assert_eq!(meta.title.unwrap(), "Sonic the Hedgehog");
        assert_eq!(meta.region.unwrap(), "USA");
        assert!(meta.tags.is_none());
    }

    #[test]
    fn test_no_intro_style() {
        let meta = FileNameParser::parse("[No-Intro] Super Mario World (USA) (Rev 1).sfc", "1");
        assert_eq!(meta.title.as_ref().unwrap(), "Super Mario World");
        assert_eq!(meta.region.as_ref().unwrap(), "USA");
        let tags = meta.tags.as_ref().unwrap();
        assert!(tags.contains("No-Intro"));
        assert!(!tags.contains("USA")); // Should NOT contain region
        assert!(tags.contains("Rev 1"));
    }

    #[test]
    fn test_redump_disc_style() {
        let meta = FileNameParser::parse("Final Fantasy VII (USA) (Disc 1).iso", "1");
        assert_eq!(meta.title.as_ref().unwrap(), "Final Fantasy VII");
        assert_eq!(meta.region.as_ref().unwrap(), "USA");
        assert!(meta.tags.as_ref().unwrap().contains("Disc 1"));
        assert!(!meta.tags.as_ref().unwrap().contains("USA"));
    }

    #[test]
    fn test_prefix_tags() {
        let meta = FileNameParser::parse("(Disc 1) Chrono Cross (USA).chd", "1");
        assert_eq!(meta.title.as_ref().unwrap(), "Chrono Cross");
        assert_eq!(meta.region.as_ref().unwrap(), "USA");
        assert!(meta.tags.as_ref().unwrap().contains("Disc 1"));
        assert!(!meta.tags.as_ref().unwrap().contains("USA"));
    }

    #[test]
    fn test_multiple_tags() {
        let meta = FileNameParser::parse("Game [!] (Europe) [v1.2] (Beta).zip", "1");
        assert_eq!(meta.title.as_ref().unwrap(), "Game");
        assert_eq!(meta.region.as_ref().unwrap(), "Europe");
        let tags = meta.tags.as_ref().unwrap();
        assert!(tags.contains("!"));
        assert!(!tags.contains("Europe")); // Should NOT contain region
        assert!(tags.contains("v1.2"));
        assert!(tags.contains("Beta"));
    }

    #[test]
    fn test_short_region_codes() {
        let meta = FileNameParser::parse("Metroid (U).zip", "1");
        assert_eq!(meta.title.as_ref().unwrap(), "Metroid");
        assert_eq!(meta.region.as_ref().unwrap(), "USA");
    }

    #[test]
    fn test_with_underscores_and_dots() {
        let meta = FileNameParser::parse("Street_Fighter_II.Turbo.sfc", "1");
        assert_eq!(meta.title.as_ref().unwrap(), "Street Fighter II Turbo");
    }
}
