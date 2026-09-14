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
        let trimmed_query = query.trim();
        let encoded_q = urlencoding::encode(trimmed_query).replace("%20", "+");
        
        // Disable Bing's query rewriting/spellcheck truncation by passing pq, qs=n, and sp=-1
        let url = format!(
            "https://www.bing.com/images/search?q={}&pq={}&qs=n&form=QBIR&sp=-1",
            encoded_q, encoded_q
        );

        let html_content = self.client.get(&url).await?;
        let document = Html::parse_document(&html_content);
        
        let mut results = Vec::new();
        
        // Bing image results are in 'a.iusc' elements with 'm' attribute containing JSON
        let link_selector = Selector::parse("a.iusc").unwrap();

        for element in document.select(&link_selector) {
            if let Some(m_attr) = element.value().attr("m") {
                if let Ok(json) = serde_json::from_str::<Value>(m_attr) {
                    let full_url = json["murl"].as_str().unwrap_or("").to_string();
                    let thumb_url = json["turl"].as_str().unwrap_or("").to_string();
                    
                    if !full_url.is_empty() {
                         let mut resolution = None;
                         if let (Some(w), Some(h)) = (json["w"].as_u64(), json["h"].as_u64()) {
                             resolution = Some(format!("{}x{}", w, h));
                         }

                         results.push(ScraperSearchResult {
                            id: full_url.clone(),
                            title: json["t"].as_str().unwrap_or("Image Result").to_string(),
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

        if results.len() > 30 {
            results.truncate(30);
        }
        
        Ok(results)
    }

    async fn fetch_details(&self, result_id: &str) -> Result<ScrapedMetadata> {
        let mut metadata = ScrapedMetadata::default();
        metadata.source = "Bing Images".to_string();
        metadata.source_id = result_id.to_string();
        metadata.title = "Image Search Result".to_string();
        metadata.description = "Image found via Bing Search.".to_string();
        
        metadata.assets.entry("Box - Front".to_string())
            .or_insert_with(Vec::new)
            .push(result_id.to_string());
        
        Ok(metadata)
    }
}
