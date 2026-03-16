use async_trait::async_trait;
use crate::core::scraper::{ScrapedMetadata, ScraperProvider, ScraperSearchResult, ScrapedResource};
use crate::core::scraper::client::ScraperClient;
use std::sync::Arc;
use tokio::time::{sleep, Duration};
use crate::core::models::GameComment;

pub struct SteamProvider {
    client: Arc<ScraperClient>,
}

impl SteamProvider {
    pub fn new(client: Arc<ScraperClient>) -> Self {
        Self { client }
    }
}

#[async_trait]
impl ScraperProvider for SteamProvider {
    fn name(&self) -> &'static str {
        "Steam"
    }

    async fn search(&self, query: &str, _platform: Option<&str>) -> anyhow::Result<Vec<ScraperSearchResult>> {

        // It relies on exact Steam IDs passed down during processing.
        let appid = query.trim();
        if !appid.chars().all(|c| c.is_digit(10)) {
            // Provide a graceful fallback or empty return if trying to do a generic text search
            return Ok(Vec::new());
        }

        let result = ScraperSearchResult {
            id: appid.to_string(),
            title: format!("Steam App {}", appid), // Will be overwritten by fetch_details
            platform: "PC".to_string(),
            platforms: None,
            platform_ids: None,
            region: None,
            release_year: None,
            thumbnail_url: None,
            resolution: None,
            can_add_to_collection: false,
            metadata: None,
        };

        Ok(vec![result])
    }

    async fn fetch_details(&self, result_id: &str) -> anyhow::Result<ScrapedMetadata> {
        let mut meta = ScrapedMetadata {
            title: "".to_string(),
            developer: "".to_string(),
            publisher: "".to_string(),
            genre: "".to_string(),
            description: "".to_string(),
            rating: None,
            release_year: None,
            region: "Global".to_string(),
            assets: std::collections::HashMap::new(),
            resources: Vec::new(),
            comments: None,
            source: "Steam".to_string(),
            source_id: result_id.to_string(),
        };

        // Enforce safe scraping delay (Steam limit is 200 per 5 mins)
        sleep(Duration::from_millis(2500)).await;

        let details_url = format!("https://store.steampowered.com/api/appdetails?appids={}", result_id);
        
        log::debug!("[Scraper:Steam] Fetching details: {}", details_url);

        match self.client.get(&details_url).await {
            Ok(text) => {
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                    if let Some(app_data) = json.get(result_id).and_then(|v| v.get("data")) {
                        meta.title = app_data.get("name").and_then(|v| v.as_str()).unwrap_or("").to_string();
                        
                        // Clean HTML from description
                        if let Some(desc) = app_data.get("about_the_game").and_then(|v| v.as_str()) {
                            let text = desc.replace("<br>", "\n").replace("<br/>", "\n").replace("<p>", "\n").replace("</p>", "\n");
                            let re = regex::Regex::new(r"<[^>]*>").unwrap();
                            meta.description = re.replace_all(&text, "").to_string().trim().to_string();
                        }
                        
                        if let Some(devs) = app_data.get("developers").and_then(|v| v.as_array()) {
                            meta.developer = devs.iter().filter_map(|v| v.as_str()).collect::<Vec<_>>().join(", ");
                        }
                        if let Some(pubs) = app_data.get("publishers").and_then(|v| v.as_array()) {
                            meta.publisher = pubs.iter().filter_map(|v| v.as_str()).collect::<Vec<_>>().join(", ");
                        }
                        if let Some(genres) = app_data.get("genres").and_then(|v| v.as_array()) {
                            meta.genre = genres.iter().filter_map(|v| v.get("description").and_then(|d| d.as_str())).collect::<Vec<_>>().join(", ");
                        }
                        if let Some(date) = app_data.get("release_date").and_then(|v| v.get("date")).and_then(|d| d.as_str()) {
                            if date.len() >= 4 {
                                if let Ok(year) = date[date.len()-4..].parse::<i32>() {
                                    meta.release_year = Some(year);
                                }
                            }
                        }
                        
                        // Metacritic mapping (0-100 scale -> 0-5 stars)
                        if let Some(mc) = app_data.get("metacritic") {
                            if let Some(score) = mc.get("score").and_then(|v| v.as_f64()) {
                                meta.rating = Some((score / 20.0) as f32);
                            }
                            if let Some(url) = mc.get("url").and_then(|v| v.as_str()) {
                                meta.resources.push(ScrapedResource {
                                    type_: "metacritic".to_string(),
                                    url: url.to_string(),
                                    label: "Metacritic".to_string()
                                });
                            }
                        }

                        // Screenshots
                        if let Some(screenshots) = app_data.get("screenshots").and_then(|v| v.as_array()) {
                            let mut urls = Vec::new();
                            for shot in screenshots {
                                if let Some(url) = shot.get("path_full").and_then(|v| v.as_str()) {
                                    urls.push(url.to_string());
                                }
                            }
                            if !urls.is_empty() {
                                meta.assets.insert("Screenshot".to_string(), urls);
                            }
                        }

                        // Movies (Videos)
                        if let Some(movies) = app_data.get("movies").and_then(|v| v.as_array()) {
                            if let Some(best_movie) = movies.first() {
                                if let Some(video_url) = best_movie.get("mp4").and_then(|m| m.get("max")).and_then(|v| v.as_str()) {
                                    meta.resources.push(ScrapedResource {
                                        type_: "video".to_string(),
                                        url: video_url.to_string(),
                                        label: best_movie.get("name").and_then(|n| n.as_str()).unwrap_or("Trailer").to_string()
                                    });
                                }
                            }
                        }
                    }
                }
            }
            Err(e) => {
                log::error!("[Scraper:Steam] Failed appdetails: {}", e);
            }
        }

        // Fetch user reviews and sentiment
        let reviews_url = format!("https://store.steampowered.com/appreviews/{}?json=1&num_per_page=5", result_id);
        
        match self.client.get(&reviews_url).await {
            Ok(text) => {
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                    if let Some(summary) = json.get("query_summary") {
                        if let Some(desc) = summary.get("review_score_desc").and_then(|v| v.as_str()) {
                            // Prepend the sentiment to the description
                            if !meta.description.is_empty() {
                                meta.description = format!("Overall Reviews: {}\n\n{}", desc, meta.description);
                            } else {
                                meta.description = format!("Overall Reviews: {}", desc);
                            }
                        }
                    }
                    
                    if let Some(reviews) = json.get("reviews").and_then(|v| v.as_array()) {
                        let mut comments = Vec::new();
                        for r in reviews {
                            let author = "Steam User".to_string();
                            let text = r.get("review").and_then(|v| v.as_str()).unwrap_or("").to_string();
                            let is_positive = r.get("voted_up").and_then(|v| v.as_bool()).unwrap_or(true);
                            let upvotes = r.get("votes_up").and_then(|v| v.as_i64()).unwrap_or(0) as i32;
                            let id = r.get("recommendationid").and_then(|v| v.as_str()).unwrap_or("").to_string();
                            
                            if !text.is_empty() {
                                comments.push(GameComment {
                                    id,
                                    rom_id: "".to_string(), // Filled in by caller
                                    author,
                                    comment_text: text,
                                    is_positive,
                                    upvotes,
                                    source: "Steam".to_string(),
                                });
                            }
                        }
                        if !comments.is_empty() {
                            meta.comments = Some(comments);
                        }
                    }
                }
            }
            Err(e) => {
                log::error!("[Scraper:Steam] Failed appreviews: {}", e);
            }
        }

        Ok(meta)
    }
}
