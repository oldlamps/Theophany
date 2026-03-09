use crate::core::scraper::{ScrapedMetadata, ScraperSearchResult, ScraperProvider, client::ScraperClient};
use async_trait::async_trait;
use scraper::{Html, Selector};
use std::sync::Arc;
use anyhow::Result;
use serde_json::Value;


pub struct SearchEngineProvider {
    client: Arc<ScraperClient>,
}

impl SearchEngineProvider {
    pub fn new(client: Arc<ScraperClient>) -> Self {
        Self { client }
    }
}

#[async_trait]
impl ScraperProvider for SearchEngineProvider {
    fn name(&self) -> &'static str {
        "Bing Images"
    }

    async fn search(&self, query: &str, _platform: Option<&str>) -> Result<Vec<ScraperSearchResult>> {
        // Bing Images Search
        let url = format!("https://www.bing.com/images/search?q={}", urlencoding::encode(query));
        let html_content = self.client.get(&url).await?;
        let document = Html::parse_document(&html_content);
        
        let mut results = Vec::new();
        
        // Bing image results are usually in 'a.iusc' elements with 'm' attribute containing JSON
        // JSON format: {"murl":"...", "turl":"...", "w": 1920, "h": 1080, ...}
        let link_selector = Selector::parse("a.iusc").unwrap();

        for element in document.select(&link_selector) {
            if let Some(m_attr) = element.value().attr("m") {
                // Parse the JSON attribute
                if let Ok(json) = serde_json::from_str::<Value>(m_attr) {
                    let full_url = json["murl"].as_str().unwrap_or("").to_string();
                    let thumb_url = json["turl"].as_str().unwrap_or("").to_string();
                    
                    if !full_url.is_empty() {
                         // Extract resolution
                         let mut resolution = None;
                         if let (Some(w), Some(h)) = (json["w"].as_u64(), json["h"].as_u64()) {
                             resolution = Some(format!("{}x{}", w, h));
                         }

                         results.push(ScraperSearchResult {
                            id: full_url.clone(), // Use URL as ID
                            title: json["t"].as_str().unwrap_or("Image Result").to_string(), // 't' often holds the title/alt text
                            platform: "Web".to_string(),
                            platforms: None,
                            platform_ids: None,
                            region: None,
                            release_year: None,
                            thumbnail_url: Some(thumb_url),
                            resolution,
                            can_add_to_collection: false,
                            metadata: None,
                        });
                    }
                }
            }
        }

        // Limit results
        if results.len() > 30 {
            results.truncate(30);
        }
        
        Ok(results)
    }

    async fn fetch_details(&self, result_id: &str) -> Result<ScrapedMetadata> {
        // For Image Search, the "details" is just the image itself.
        // We populate the assets with the full URL.
        let mut metadata = ScrapedMetadata::default();
        metadata.source = "Bing Images".to_string();
        metadata.source_id = result_id.to_string();
        metadata.title = "Image Search Result".to_string();
        metadata.description = "Image found via Bing Search.".to_string();
        
        // Default to "Box - Front" to be useful immediately.
        metadata.assets.entry("Box - Front".to_string())
            .or_insert_with(Vec::new)
            .push(result_id.to_string());
        
        // Also add as "Background" just in case they want it there? 
        // No, let's keep it specific.
        
        Ok(metadata)
    }
}
