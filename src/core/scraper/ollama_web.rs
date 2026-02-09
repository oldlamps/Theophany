use crate::core::scraper::{ScrapedMetadata, ScraperSearchResult, ScraperProvider, client::ScraperClient};
use crate::core::ollama::OllamaClient;
use async_trait::async_trait;
use scraper::{Html, Selector};
use std::sync::Arc;
use anyhow::{Result, anyhow};
use serde::Deserialize;
use rand;
use tokio;
use futures_util::future::join_all;

pub struct OllamaWebProvider {
    client: Arc<ScraperClient>,
    ollama_url: String,
    ollama_model: String,
}

impl OllamaWebProvider {
    pub fn new(client: Arc<ScraperClient>, ollama_url: String, ollama_model: String) -> Self {
        Self { 
            client,
            ollama_url,
            ollama_model,
        }
    }

    fn extract_clean_text(&self, html: &str) -> String {
        let document = Html::parse_document(html);
        let mut content = String::new();
        
        for node in document.tree.nodes() {
            if let Some(el) = node.value().as_element() {
                // Add formatting for block elements
                let tag = el.name();
                if ["p", "div", "br", "li", "h1", "h2", "h3", "h4", "h5", "h6", "article", "section", "tr", "td", "th", "blockquote"].contains(&tag) {
                    content.push('\n');
                }
            } else if let Some(text) = node.value().as_text() {
                let text_content = text.trim();
                if text_content.is_empty() {
                    continue;
                }

                let mut skip = false;
                let mut parent_id = node.parent();
                
                // Check ancestors for blacklist
                while let Some(id) = parent_id {
                    let parent_node = document.tree.get(id.id()).unwrap();
                    if let Some(el) = parent_node.value().as_element() {
                        let tag = el.name();
                        // 1. Blacklisted tags (narrowed down)
                        if ["script", "style", "nav", "footer", "noscript", "iframe", "svg", "button", "input", "form"].contains(&tag) {
                            skip = true;
                            break;
                        }
                        // 2. Blacklisted classes (narrowed down)
                        if let Some(class) = el.attr("class") {
                            let class_lower = class.to_lowercase();
                            if class_lower.contains("cookie") || class_lower.contains("popup") || class_lower.contains("advert") {
                                skip = true;
                                break;
                            }
                        }
                    }
                    parent_id = parent_node.parent();
                }
                
                if !skip {
                    content.push_str(text_content);
                    content.push(' ');
                }
            }
        }
        
        // Clean up whitespace
        content.lines()
            .map(|l| l.trim())
            .filter(|l| !l.is_empty())
            .collect::<Vec<&str>>()
            .join("\n")
    }

    async fn fetch_and_extract(&self, url: String) -> Result<(String, String)> {
        let html = self.client.get(&url).await?;
        let text = self.extract_clean_text(&html);
        Ok((url, text))
    }
}


#[async_trait]
impl ScraperProvider for OllamaWebProvider {
    fn name(&self) -> &'static str {
        "Ollama + Web Search"
    }

    async fn search(&self, query: &str, platform: Option<&str>) -> Result<Vec<ScraperSearchResult>> {
        let platform_str = platform.unwrap_or("");
        
        // Normalize launcher-based platforms to "PC" for better search results
        let normalized_platform = match platform_str.to_lowercase().as_str() {
            "heroic" | "lutris" | "steam" | "gog" | "epic" | "bottles" => "PC",
            _ => platform_str,
        };
        
        let search_term = if normalized_platform.is_empty() {
            format!("{} video game", query)
        } else {
            format!("{} {}", query, normalized_platform)
        };
        
        // Using DuckDuckGo HTML
        let url = format!("https://html.duckduckgo.com/html?q={}", urlencoding::encode(&search_term));
        // println!("[OllamaWeb] Searching URL: {}", url);
        
        let delay = rand::random::<u64>() % 1000 + 500;
        tokio::time::sleep(std::time::Duration::from_millis(delay)).await;

        let html_content = self.client.get(&url).await?;
        
        let mut candidate_urls = Vec::new();
        {
            let document = Html::parse_document(&html_content);
            let selector = Selector::parse(".result__a").unwrap();
            
            for link in document.select(&selector) {
                if let Some(href) = link.value().attr("href") {
                     if href.contains("y.js") || href.contains("ad_domain") || 
                        href.contains("amazon.com") || href.contains("ebay.com") || 
                        href.contains("walmart.com") || href.contains("gamestop.com") {
                          continue;
                     }

                     let mut target_url = String::new();
                     if href.starts_with("http") && !href.contains("duckduckgo") && !href.contains("bing.com") {
                         target_url = href.to_string();
                     } else if href.contains("uddg=") {
                         if let Some(start) = href.find("uddg=") {
                             let remainder = &href[start + 5..];
                             if let Some(end) = remainder.find('&') {
                                 if let Ok(decoded) = urlencoding::decode(&remainder[..end]) {
                                     target_url = decoded.to_string();
                                 }
                             } else if let Ok(decoded) = urlencoding::decode(remainder) {
                                 target_url = decoded.to_string();
                             }
                         }
                     }

                     if !target_url.is_empty() {
                         candidate_urls.push(target_url);
                         if candidate_urls.len() >= 3 { break; } // Top 3 for synthesis
                     }
                }
            }
        }

        if candidate_urls.is_empty() {
            return Ok(vec![]);
        }

        // println!("[OllamaWeb] Parallel fetching {} sources...", candidate_urls.len());
        
        // Parallel Fetching
        let fetch_futures = candidate_urls.into_iter().map(|url| self.fetch_and_extract(url));
        let fetch_results = join_all(fetch_futures).await;
        
        let mut context_block = String::new();
        let mut successful_urls = Vec::new();
        
        for res in fetch_results {
            if let Ok((url, text)) = res {
                if !text.is_empty() {
                    context_block.push_str(&format!("\nSOURCE: {}\n---\n{}\n---\n", url, text));
                    successful_urls.push(url);
                }
            }
        }

        if context_block.is_empty() {
            return Err(anyhow!("Failed to extract content from any search results."));
        }

        // println!("[OllamaWeb] Synthesizing metadata from {} sources (total {} chars) using Ollama...", successful_urls.len(), context_block.len());

        // Synthesis Prompt
        let ollama = OllamaClient::new(self.ollama_url.clone(), self.ollama_model.clone());
        let mut truncated_len = 18000.min(context_block.len());
        while !context_block.is_char_boundary(truncated_len) && truncated_len > 0 {
            truncated_len -= 1;
        }
        let truncated_context = &context_block[..truncated_len];

        let prompt = format!(
            "You are a video game historian and metadata expert. Synthesize high-quality metadata from the following multiple sources.\n\n\
            Return ONLY a single flat JSON object with these exact keys: \"title\", \"description\", \"developer\", \"publisher\", \"genre\", \"release_date\", \"links\".
            
            RULES:
            1. For 'description', synthesize a comprehensive and engaging overview of the game's gameplay, story, and significance based on ALL provided sources. 
            2. For other fields, use simple strings. 
            3. For 'links', provide an array of objects with \"type\" (e.g., 'Official', 'Steam', 'MobyGames', 'GOG', 'Web'), \"url\", and \"label\". Identify these from the source context.
            4. DO NOT nest the result inside another object (like \"metadata\").
            5. DO NOT include any text before or after the JSON.
            6. For \"title\", provide only the official name of the game.
            CONTEXT:\n\
            {}\n",
            truncated_context
        );

        let system_prompt = "You are a helpful assistant that synthesizes accurate video game metadata in JSON format. Be descriptive and precise.";
        
        let response_json = ollama.generate(&prompt, Some(system_prompt), true).await?;
        // println!("[OllamaWeb] Synthesis Response: {}", response_json);
        
        let v: serde_json::Value = match serde_json::from_str(&response_json) {
            Ok(v) => v,
            Err(_) => {
                let repaired = repair_json(&response_json);
                serde_json::from_str(&repaired)
                    .map_err(|e| anyhow!("Failed to parse Ollama JSON (even after repair): {}. Response: {}", e, response_json))?
            }
        };
        
        let data = if let Some(meta) = v.get("metadata").or_else(|| v.get("Metadata")) {
            if meta.is_object() { meta } else { &v }
        } else if let Some(game) = v.get("game").or_else(|| v.get("Game")) {
            if game.is_object() { game } else { &v }
        } else {
            &v
        };

        let parsed: OllamaScrapeResult = serde_json::from_value(data.clone())
            .map_err(|e| anyhow!("Failed to map Ollama metadata: {}. Response: {}", e, response_json))?;
        
        // println!("[OllamaWeb] Parsed Title: '{:?}'", parsed.title);

        let mut metadata = ScrapedMetadata::default();
        metadata.source = "Ollama + Web Search".to_string();
        metadata.source_id = successful_urls.get(0).cloned().unwrap_or_default(); // Primary source
        metadata.title = parsed.title.unwrap_or_default();
        metadata.description = parsed.description.unwrap_or_default();
        metadata.developer = flatten_json_value(parsed.developer);
        metadata.publisher = flatten_json_value(parsed.publisher);
        metadata.genre = flatten_json_value(parsed.genre);
        // Filter out resources with null/empty URLs (LLM sometimes returns these)
        metadata.resources = parsed.links.unwrap_or_default()
            .into_iter()
            .filter(|r| r.url.as_ref().map(|u| !u.is_empty()).unwrap_or(false))
            .map(|r| r.into())
            .collect();
        
        let date_str = flatten_json_value(parsed.release_date);
        metadata.release_year = date_str.split(|c: char| !c.is_numeric())
            .find(|s| s.len() == 4)
            .and_then(|y| y.parse::<i32>().ok());

        // Return as a single synthesized result
        Ok(vec![ScraperSearchResult {
            id: metadata.source_id.clone(),
            title: metadata.title.clone(),
            platform: platform.unwrap_or("Web").to_string(),
            platforms: None,
            platform_ids: None,
            region: Some(metadata.region.clone()),
            release_year: metadata.release_year,
            resolution: Some(format!("Synthesized from {} sources", successful_urls.len())),
            thumbnail_url: None,
            can_add_to_collection: true,
            metadata: Some(metadata),
        }])
    }

    async fn fetch_details(&self, result_id: &str) -> Result<ScrapedMetadata> {
        // DESIGN NOTE: search() already synthesizes metadata from 3 sources.
        // This fetch_details() is called when the UI clicks "Import" but ends up
        // extracting from ONLY the single result_id URL, which is less comprehensive.
        // Ideally, the UI should use the already-synthesized metadata from search().
        // For now, this provides single-source extraction as a fallback.
        
        let html_content = self.client.get(result_id).await?;
        let text = self.extract_clean_text(&html_content);
        
        if text.is_empty() {
            return Err(anyhow!("Failed to extract content from {}", result_id));
        }

        let context = format!("\nSOURCE: {}\n---\n{}\n---\n", result_id, text);
        
        // println!("[OllamaWeb] Extracting metadata from single source: {}", result_id);

        let ollama = OllamaClient::new(self.ollama_url.clone(), self.ollama_model.clone());
        let truncated_context = if context.len() > 15000 { &context[..15000] } else { &context };

        let prompt = format!(
            "You are a video game historian and metadata expert. Extract high-quality metadata from the following source.\n\n\
            Return ONLY a JSON object with these fields: title, description, developer, publisher, genre, release_date (YYYY-MM-DD), links (array of objects with type, url, label).\n\n\
            RULES:\n\
            1. For 'description', write a comprehensive overview based on the source text.\n\
            2. For other fields, use strings. If multiple values exist, join with commas. If missing, use 'null'.\n\
            3. Identify external links (Steam, MobyGames, etc.) and list them in 'links'.\n\
            4. DO NOT make up info not present in the text.\n\n\
            CONTEXT:\n\
            {}\n",
            truncated_context
        );

        let system_prompt = "You are a helpful assistant that extracts accurate video game metadata in JSON format.";
        
        let response_json = ollama.generate(&prompt, Some(system_prompt), true).await?;
        
        /* println!("[OllamaWeb] Ollama Raw Response ({} chars): {}", response_json.len(), 
                 if response_json.len() > 500 { 
                     format!("{}...[truncated]", &response_json[..500]) 
                 } else { 
                     response_json.clone() 
                 }); */
        
        let v: serde_json::Value = match serde_json::from_str(&response_json) {
            Ok(v) => {
                // println!("[OllamaWeb] JSON parsed successfully");
                v
            },
            Err(_e) => {
                // println!("[OllamaWeb] JSON parse failed: {}. Attempting repair...", e);
                let repaired = repair_json(&response_json);
                /* println!("[OllamaWeb] Repaired JSON ({} chars): {}", repaired.len(),
                         if repaired.len() > 300 {
                             format!("{}...[truncated]", &repaired[..300])
                         } else {
                             repaired.clone()
                         }); */
                serde_json::from_str(&repaired)
                    .map_err(|e| anyhow!("Failed to parse Ollama extraction (even after repair): {}. Response: {}", e, response_json))?
            }
        };

        let data = if let Some(meta) = v.get("metadata").or_else(|| v.get("Metadata")) {
            if meta.is_object() { meta } else { &v }
        } else if let Some(game) = v.get("game").or_else(|| v.get("Game")) {
            if game.is_object() { game } else { &v }
        } else {
            &v
        };

        let parsed: OllamaScrapeResult = serde_json::from_value(data.clone())
            .map_err(|e| anyhow!("Failed to map Ollama metadata: {}. Data: {:?}", e, data))?;

        let mut metadata = ScrapedMetadata::default();
        metadata.source = "Ollama + Web Search".to_string();
        metadata.source_id = result_id.to_string();
        metadata.title = parsed.title.unwrap_or_default();
        metadata.description = parsed.description.filter(|s| !s.is_empty()).unwrap_or_default();
        metadata.developer = flatten_json_value(parsed.developer);
        metadata.publisher = flatten_json_value(parsed.publisher);
        metadata.genre = flatten_json_value(parsed.genre);
        // Filter out resources with null/empty URLs (LLM sometimes returns these)
        metadata.resources = parsed.links.unwrap_or_default()
            .into_iter()
            .filter(|r| r.url.as_ref().map(|u| !u.is_empty()).unwrap_or(false))
            .map(|r| r.into())
            .collect();
        
        let date_str = flatten_json_value(parsed.release_date);
        metadata.release_year = date_str.split(|c: char| !c.is_numeric())
            .find(|s| s.len() == 4)
            .and_then(|y| y.parse::<i32>().ok());

        Ok(metadata)
    }
}

fn flatten_json_value(val: Option<serde_json::Value>) -> String {
    match val {
        Some(serde_json::Value::String(s)) => s,
        Some(serde_json::Value::Array(arr)) => {
            arr.iter()
               .map(|v| flatten_json_value(Some(v.clone())))
               .filter(|s| !s.is_empty())
               .collect::<Vec<_>>()
               .join(", ")
        },
        Some(serde_json::Value::Object(obj)) => {
             obj.iter()
                .map(|(k, v)| {
                    let val_str = flatten_json_value(Some(v.clone()));
                    if val_str.is_empty() { k.clone() } else { format!("{}: {}", k, val_str) }
                })
                .filter(|s| !s.is_empty())
                .collect::<Vec<_>>()
                .join(", ")
        },
        Some(serde_json::Value::Number(n)) => n.to_string(),
        Some(serde_json::Value::Bool(b)) => b.to_string(),
        _ => String::new(),
    }
}

fn repair_json(s: &str) -> String {
    let s = s.trim();
    if s.is_empty() { return "{}".to_string(); }
    
    // Find first '{' 
    let start = match s.find('{') {
        Some(idx) => idx,
        None => return "{}".to_string(),
    };
    
    let mut result = String::new();
    let mut brace_count = 0;
    let mut bracket_count = 0;
    let mut in_string = false;
    let mut escape_next = false;
    
    for ch in s[start..].chars() {
        if escape_next {
            result.push(ch);
            escape_next = false;
            continue;
        }
        
        if ch == '\\' && in_string {
            escape_next = true;
            result.push(ch);
            continue;
        }
        
        if ch == '"' {
            in_string = !in_string;
        }
        
        if !in_string {
            match ch {
                '{' => brace_count += 1,
                '}' => brace_count -= 1,
                '[' => bracket_count += 1,
                ']' => bracket_count -= 1,
                _ => {}
            }
        }
        
        result.push(ch);
        
        // If we've balanced all braces and brackets, we have a complete object
        if brace_count == 0 && bracket_count == 0 && !in_string {
            break;
        }
    }
    
    // If we still have unclosed braces/brackets, close them
    // First close any unclosed strings
    if in_string {
        result.push('"');
    }
    
    // Remove trailing commas before closing
    let trimmed = result.trim_end_matches(|c: char| c.is_whitespace() || c == ',');
    result = trimmed.to_string();
    
    // Close unclosed brackets
    for _ in 0..bracket_count {
        result.push(']');
    }
    
    // Close unclosed braces
    for _ in 0..brace_count {
        result.push('}');
    }
    
    result
}

#[derive(Deserialize)]
struct OllamaScrapeResult {
    #[serde(alias = "name", alias = "game", alias = "game_title", alias = "game_name", alias = "name_of_game", alias = "Title", alias = "Name", alias = "Game")]
    title: Option<String>,
    #[serde(alias = "Description", alias = "Synopsis", alias = "Summary", alias = "synopsis")]
    description: Option<String>,
    #[serde(alias = "developers", alias = "Developer", alias = "Developers")]
    developer: Option<serde_json::Value>,
    #[serde(alias = "publishers", alias = "Publisher", alias = "Publishers")]
    publisher: Option<serde_json::Value>,
    #[serde(alias = "genres", alias = "Genre", alias = "Genres")]
    genre: Option<serde_json::Value>,
    #[serde(alias = "release_year", alias = "year", alias = "releaseDate", alias = "Release Date", alias = "release date", alias = "ReleaseDate", alias = "Released")]
    release_date: Option<serde_json::Value>,
    #[serde(default, alias = "Resources", alias = "links", alias = "external_links", deserialize_with = "deserialize_links")]
    links: Option<Vec<OllamaResource>>,
}

/// Custom deserializer to handle links as either array of strings or array of objects
fn deserialize_links<'de, D>(deserializer: D) -> Result<Option<Vec<OllamaResource>>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    let value: Option<serde_json::Value> = Option::deserialize(deserializer)?;
    
    match value {
        None => Ok(None),
        Some(serde_json::Value::Array(arr)) => {
            let mut resources = Vec::new();
            
            for item in arr {
                match item {
                    // Handle string URLs
                    serde_json::Value::String(url) => {
                        resources.push(OllamaResource {
                            type_: None,
                            url: Some(url),
                            label: None,
                        });
                    },
                    // Handle objects
                    serde_json::Value::Object(_) => {
                        match serde_json::from_value::<OllamaResource>(item) {
                            Ok(res) => resources.push(res),
                            Err(_) => continue, // Skip malformed objects
                        }
                    },
                    _ => continue, // Skip other types
                }
            }
            
            Ok(Some(resources))
        },
        _ => Ok(None),
    }
}

/// Permissive struct for parsing Ollama responses where any field might be null
#[derive(Deserialize)]
struct OllamaResource {
    #[serde(rename = "type")]
    type_: Option<String>,
    url: Option<String>,
    label: Option<String>,
}

impl From<OllamaResource> for crate::core::scraper::ScrapedResource {
    fn from(r: OllamaResource) -> Self {
        Self {
            type_: r.type_.unwrap_or_default(),
            url: r.url.unwrap_or_default(),
            label: r.label.unwrap_or_default(),
        }
    }
}
