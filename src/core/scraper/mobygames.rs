use crate::core::scraper::{ScrapedMetadata, ScraperSearchResult, ScraperProvider, client::ScraperClient};
use async_trait::async_trait;
use scraper::{Html, Selector};
use std::sync::Arc;
use anyhow::Result;

pub struct MobyGamesProvider {
    client: Arc<ScraperClient>,
}

impl MobyGamesProvider {
    pub fn new(client: Arc<ScraperClient>) -> Self {
        Self { client }
    }
}

#[async_trait]
impl ScraperProvider for MobyGamesProvider {
    fn name(&self) -> &'static str {
        "MobyGames"
    }

    async fn search(&self, query: &str, _platform: Option<&str>) -> Result<Vec<ScraperSearchResult>> {
        let url = format!("https://www.mobygames.com/search/?q={}&type=game", urlencoding::encode(query));
        let html_content = self.client.get(&url).await?;
        let document = Html::parse_document(&html_content);
        
        let mut results = Vec::new();
        
        // Python Ref: soup.select('table.table tr')
        // Then: link = row.select_one('b a')
        let row_selector = Selector::parse("table.table tr").unwrap();
        let link_selector = Selector::parse("b > a").unwrap();
        let img_selector = Selector::parse("img").unwrap();

        for row in document.select(&row_selector) {
            if let Some(link) = row.select(&link_selector).next() {
                let title = link.text().collect::<String>().trim().to_string();
                let href = link.value().attr("href").unwrap_or("").to_string();
                
                // MobyGames hrefs are usually absolute or relative. If relative, prepend base.
                // Assuming scraped hrefs might be relative.
                // But wait, standard links on Moby are usually like https://www.mobygames.com/game/...
                // We'll treat the href as the ID for now, or extract the ID structure.
                // Actually, let's just use the full path relative to domain as ID since fetch uses it.
                // strip domain if present to keep ID clean?
                // Let's keep it simple: ID = href. It works for fetch.
                
                let id = href.clone(); 
                
                if title.is_empty() || id.is_empty() { continue; }

                // Try to find a thumbnail if possible (often Moby search results don't have thumbs in the table row)
                // But let's check if there is an img in the row
                let mut thumbnail_url = None;
                if let Some(img) = row.select(&img_selector).next() {
                     thumbnail_url = img.value().attr("src").map(|s| s.to_string());
                }

                results.push(ScraperSearchResult {
                    id,
                    title,
                    platform: "Mixed".to_string(), // Moby search results often don't list platform in the primary column easily without more parsing
                    platforms: None,
                    platform_ids: None,
                    region: None,
                    release_year: None, // Hard to parse from standard search table without specific column logic
                    thumbnail_url,
                    resolution: None,
                    can_add_to_collection: false,
                    metadata: None,
                });
            }
        }
        
        Ok(results)
    }

    async fn fetch_details(&self, result_id: &str) -> Result<ScrapedMetadata> {
        // result_id is likely a URL path like /game/1234/title
        // Ensure we have a full URL
        let url = if result_id.starts_with("http") {
            result_id.to_string()
        } else {
            format!("https://www.mobygames.com{}", result_id)
        };

        let html_content = self.client.get(&url).await?;
        let document = Html::parse_document(&html_content);
        
        let mut metadata = ScrapedMetadata::default();
        metadata.source = "MobyGames".to_string();
        metadata.source_id = result_id.to_string();

        // Title - usually in h1
        let title_selector = Selector::parse("h1.heading-title, h1").unwrap();
        if let Some(h1) = document.select(&title_selector).next() {
             metadata.title = h1.text().collect::<String>().trim().to_string();
        }

        // Description
        // Python Ref: section#gameDescription > div#description-text
        let desc_selector = Selector::parse("#description-text").unwrap();
        if let Some(desc) = document.select(&desc_selector).next() {
             metadata.description = desc.text().collect::<String>().trim().to_string();
        }

        // Metadata Parsing (Developer, Publisher, Release, Genre)
        // Python Ref: div#infoBlock dl.metadata -> dt (key), dd (value)
        // We'll select all dt and dd pairs in the infoBlock
        let info_block_selector = Selector::parse("#infoBlock dl.metadata").unwrap();
        let dt_selector = Selector::parse("dt").unwrap();
        let dd_selector = Selector::parse("dd").unwrap();

        for dl in document.select(&info_block_selector) {
            let terms: Vec<_> = dl.select(&dt_selector).collect();
            let defs: Vec<_> = dl.select(&dd_selector).collect();
            
            for (dt, dd) in terms.iter().zip(defs.iter()) {
                let key = dt.text().collect::<String>().trim().to_lowercase();
                let value = dd.text().collect::<String>().trim().to_string(); // Simple text collection
                
                if key.contains("published") || key.contains("released") {
                     // Try to extract year
                     if let Some(year_str) = value.split_whitespace().find(|s| s.len() == 4 && s.chars().all(char::is_numeric)) {
                         if let Ok(y) = year_str.parse::<i32>() {
                             metadata.release_year = Some(y);
                         }
                     }
                } else if key.contains("genre") {
                    metadata.genre = value;
                } else if key.contains("published by") {
                    metadata.publisher = value;
                } else if key.contains("developed by") {
                    metadata.developer = value;
                }
            }
        }
        
        // Assets - Try OG Image for Box Front
        // Assets - Try OG Image for Box Front and others if accessible
        // MobyGames puts images in a separate tab usually, but main page has a cover
        let meta_selector = Selector::parse("meta[property='og:image']").unwrap();
        if let Some(meta) = document.select(&meta_selector).next() {
            if let Some(content) = meta.value().attr("content") {
                metadata.assets.entry("Box - Front".to_string())
                    .or_insert_with(Vec::new)
                    .push(content.to_string());
            }
        }
        
        // Try to find promo images or screenshots in the gallery preview if present
        let screenshot_selector = Selector::parse("#gameScreenshots .thumbnail-image img, .screenshot-thumbnails img").unwrap();
        for img in document.select(&screenshot_selector) {
             if let Some(src) = img.value().attr("src") {
                 // Often thumbnails, need to modify url for full size?
                 // Moby thumb: /images/covers/s/... 
                 // Moby large: /images/covers/l/...
                 let large_src = src.replace("/s/", "/l/"); 
                 
                 metadata.assets.entry("Screenshot".to_string())
                    .or_insert_with(Vec::new)
                    .push(large_src);
             }
        }

        Ok(metadata)
    }
}
