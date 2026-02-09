use crate::core::scraper::{ScrapedMetadata, ScraperSearchResult, ScraperProvider, client::ScraperClient};
use async_trait::async_trait;
use scraper::{Html, Selector, ElementRef};
use std::sync::Arc;
use anyhow::Result;

pub struct LaunchBoxProvider {
    client: Arc<ScraperClient>,
}

impl LaunchBoxProvider {
    pub fn new(client: Arc<ScraperClient>) -> Self {
        Self { client }
    }

    fn clean_metadata_field(input: &str) -> String {
        if input.is_empty() { return String::new(); }
        
        let mut result = String::new();
        let chars: Vec<char> = input.chars().collect();
        
        for i in 0..chars.len() {
            let c = chars[i];
            if i > 0 && c.is_uppercase() {
                let prev = chars[i-1];
                // Split if Current is Upper and Prev is Lower (e.g. "FightingSports")
                if prev.is_lowercase() {
                    result.push_str(", ");
                } 
                // Split if Prev is Upper and Current is Upper and NEXT is Lower (e.g. "GBAAction")
                else if i + 1 < chars.len() && chars[i+1].is_lowercase() && prev.is_uppercase() {
                    result.push_str(", ");
                }
            }
            result.push(c);
        }
        // Deduplicate commas that might have been added next to existing ones
        result.replace(", , ", ", ").replace(" , ", ", ")
    }
}

#[async_trait]
impl ScraperProvider for LaunchBoxProvider {
    fn name(&self) -> &'static str {
        "LaunchBox"
    }

    async fn search(&self, query: &str, _platform: Option<&str>) -> Result<Vec<ScraperSearchResult>> {
        let url = format!("https://gamesdb.launchbox-app.com/games/results/{}", urlencoding::encode(query));
        let html_content = self.client.get(&url).await?;
        let document = Html::parse_document(&html_content);
        
        // The search results on LaunchBox are often links starting with /games/details/
        // LaunchBox Results Structure Analysis:
        // Rows are in <div class="row"> inside <div class="col-sm-12"> (not robust)
        // But the game links are <a> tags with href starting with /games/details
        // The previous selector `a[href^='/games/details/']` was actually closer than `.game-list .row`.
        // Let's go back to finding all detail links but filter them better.
        
        // Declare results vector here so it remains in scope
        let mut results = Vec::new();

        let link_selector = Selector::parse("a[href^='/games/details/']").unwrap();
        // We need to avoid duplicates or images wrapping the link.
        // Usually the text link is what we want.

        for element in document.select(&link_selector) {
            // Check if this element contains an image - if so, it might be the thumbnail link.
            // Launchbox often has: <a href="..."><img ...></a> AND <a href="...">Title</a>
            // We can process both or prefer one.
            // If it has text content, use it for title.
            
            let href = element.value().attr("href").unwrap_or("");
            // Example: /games/details/369934-
            let parts: Vec<&str> = href.split('/').collect();
            if parts.len() < 4 { continue; }
            let id_and_slug = parts[3];
            let id = id_and_slug.split('-').next().unwrap_or("").to_string();
            
            if id.is_empty() { continue; }

            // Extract text components (Title, Platform, Year)
            let text_parts: Vec<String> = element.text()
                .map(|t| t.trim().to_string())
                .filter(|t| !t.is_empty())
                .collect();
            
            if text_parts.is_empty() { 
                continue; 
            }
            
            let title = text_parts[0].clone();
            
            let mut platform = String::new();
            let mut release_year: Option<i32> = None;
            
            let mut can_add_to_collection = false;
            
            for part in text_parts.iter().skip(1) {
                let part = part.trim();
                if part.is_empty() { continue; }
                
                if part.to_lowercase().contains("collection") {
                    can_add_to_collection = true;
                }

                if let Ok(year) = part.parse::<i32>() {
                    if year > 1900 && year < 2100 {
                        release_year = Some(year);
                    }
                } else if let Some(year_match) = part.split_whitespace().find_map(|s| s.trim_matches(&[',', '.'] as &[_]).parse::<i32>().ok()) {
                    if year_match > 1900 && year_match < 2100 {
                        release_year = Some(year_match);
                    }
                } else if platform.is_empty() && part.len() < 35 && !part.contains("LaunchBox") && part != "Unreleased" && part != "Unlicensed" && !part.contains("collection") {
                    platform = part.to_string();
                }
            }

            // Thumbnail
            let mut thumbnail_url = None;
            let img_selector = Selector::parse("img").unwrap();
            if let Some(img) = element.select(&img_selector).next() {
                thumbnail_url = img.value().attr("src").map(|s| s.to_string());
            }

            results.push(ScraperSearchResult {
                id,
                title,
                platform,
                platforms: None,
                platform_ids: None,
                region: None,
                release_year,
                thumbnail_url,
                resolution: None,
                can_add_to_collection,
                metadata: None,
            });
            
            if results.len() >= 50 { break; }
        }
        
        Ok(results)
    }

    async fn fetch_details(&self, result_id: &str) -> Result<ScrapedMetadata> {
        let url = format!("https://gamesdb.launchbox-app.com/games/details/{}", result_id);
        let html_content = self.client.get(&url).await?;
        let document = Html::parse_document(&html_content);
        
        let mut metadata = ScrapedMetadata::default();
        metadata.source = "LaunchBox".to_string();
        metadata.source_id = result_id.to_string();

        // Title
        // Title
        let title_selector = Selector::parse("h1").unwrap();
        if let Some(el) = document.select(&title_selector).next() {
            metadata.title = el.text().collect::<String>().trim().to_string();
        }

        // Details via <dt> and <dd> pairs
        let dt_selector = Selector::parse("dt").unwrap();
        for dt in document.select(&dt_selector) {
            let label = dt.text().collect::<String>().trim().to_lowercase();
            // The value is in the next sibling <dd>
            if let Some(parent) = dt.parent().and_then(ElementRef::wrap) {
                let dd_selector = Selector::parse("dd").unwrap();
                if let Some(dd) = parent.select(&dd_selector).next() {
                      // Collect text nodes and join with a separator to prevent concatenation
                      let raw_value = dd.text()
                          .map(|t| t.trim())
                          .filter(|t| !t.is_empty())
                          .collect::<Vec<_>>()
                          .join(", ");
                      
                      let value = Self::clean_metadata_field(&raw_value);
                      
                      if label.contains("genre") { metadata.genre = value; }
                      else if label.contains("developer") { metadata.developer = value; }
                      else if label.contains("publisher") { metadata.publisher = value; }
                      else if label.contains("region") { metadata.region = value; }
                      else if label.contains("release date") {
                          // Format often: "February 21, 1986"
                          if let Some(year) = value.split(',').last().and_then(|y| y.trim().parse::<i32>().ok()) {
                              metadata.release_year = Some(year);
                          }
                      }
                }
            }
        }

        // Description
        // Targeted via class: "mt-4 text-body-lg text-dark-100"
        let desc_selector = Selector::parse("p.mt-4.text-body-lg.text-dark-100").unwrap();
        if let Some(el) = document.select(&desc_selector).next() {
            metadata.description = el.text().collect::<String>().trim().to_string();
        }

        // Images/Assets
        let img_link_selector = Selector::parse("a[data-lightbox='game-images']").unwrap();
        for link in document.select(&img_link_selector) {
            let title_attr = link.value().attr("title").unwrap_or("").to_lowercase();
            let href = link.value().attr("href").unwrap_or("");
            
            if !href.is_empty() {
                let category = if title_attr.contains("box - front") {
                    "Box - Front"
                } else if title_attr.contains("fanart - background") || title_attr.contains("background") {
                    "Background"
                } else if title_attr.contains("logo") {
                    "Clear Logo"
                } else if title_attr.contains("box - back") {
                    "Box - Back"
                } else if title_attr.contains("screenshot") || title_attr.contains("gameplay") {
                     "Screenshot"
                } else if title_attr.contains("banner") {
                    "Banner"
                } else {
                    ""
                };

                if !category.is_empty() {
                    metadata.assets.entry(category.to_string())
                        .or_insert_with(Vec::new)
                        .push(href.to_string());
                }
            }
        }
        
        Ok(metadata)
    }
}
