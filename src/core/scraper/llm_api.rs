#![allow(dead_code)]
use crate::core::scraper::{ScrapedMetadata, ScraperSearchResult, ScraperProvider, client::ScraperClient};
use async_trait::async_trait;
use std::sync::Arc;
use anyhow::{Result, anyhow};
use serde::Deserialize;
use serde_json::json;

pub struct LlmApiProvider {
    client: Arc<ScraperClient>,
    gemini_key: String,
    openai_key: String,
    active_provider: String, // "Gemini" or "OpenAI"
}

impl LlmApiProvider {
    pub fn new(client: Arc<ScraperClient>, gemini_key: String, openai_key: String, active_provider: String) -> Self {
        Self { 
            client,
            gemini_key,
            openai_key,
            active_provider,
        }
    }

    async fn call_gemini(&self, prompt: &str) -> Result<String> {
        if self.gemini_key.is_empty() {
             return Err(anyhow!("Gemini API Key is missing. Please add it in Settings."));
        }

        let url = format!("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key={}", self.gemini_key);
        
        let body = json!({
            "systemInstruction": {
                "parts": [{ "text": "You are an expert video game historian and librarian. Your goal is to provide comprehensive, accurate, and detailed metadata for video games. Always return valid JSON." }]
            },
            "contents": [{
                "parts": [{
                    "text": prompt
                }]
            }],
            "generationConfig": {
                "responseMimeType": "application/json"
            }
        });

        let response_text = self.client.post_json(&url, &body).await?;
        
        // With native JSON mode, we don't need extensive repair, just standard parsing
        let response_json: serde_json::Value = serde_json::from_str(&response_text)?;
        
        if let Some(text) = response_json["candidates"][0]["content"]["parts"][0]["text"].as_str() {
            Ok(text.to_string())
        } else {
             Err(anyhow!("Failed to parse Gemini response: {}", response_text))
        }
    }

    async fn call_openai(&self, prompt: &str) -> Result<String> {
        if self.openai_key.is_empty() {
             return Err(anyhow!("OpenAI API Key is missing. Please add it in Settings."));
        }

        let url = "https://api.openai.com/v1/chat/completions";
        
        let body = json!({
            "model": "gpt-3.5-turbo",
            "messages": [
                {"role": "system", "content": "You are a helpful assistant that returns JSON."},
                {"role": "user", "content": prompt}
            ],
            "temperature": 0.7
        });


        let response_text = self.client.post_json_bearer(url, &body, &self.openai_key).await?;
        
        let response_json: serde_json::Value = serde_json::from_str(&response_text)?;
         if let Some(text) = response_json["choices"][0]["message"]["content"].as_str() {
            Ok(text.to_string())
        } else {
             Err(anyhow!("Failed to parse OpenAI response: {}", response_text))
        }
    }

    async fn generate(&self, prompt: &str) -> Result<String> {
        match self.active_provider.as_str() {
            "OpenAI" => self.call_openai(prompt).await,
            _ => self.call_gemini(prompt).await,
        }
    }
}

#[async_trait]
impl ScraperProvider for LlmApiProvider {
    fn name(&self) -> &'static str {
        "LLM API"
    }

    async fn search(&self, query: &str, platform: Option<&str>) -> Result<Vec<ScraperSearchResult>> {
        let platform_str = platform.unwrap_or("Any Platform");
        
        let prompt = format!(
            "Find the single best matching video game for the query '{}' on platform '{}'. \
            Return a JSON array containing EXACTLY ONE object representing the best match. \
            The object must strictly follow this structure: \
            {{ \
                \"title\": \"Game Title\", \
                \"platform\": \"Platform Name\", \
                \"release_year\": 1999, \
                \"region\": \"Region\", \
                \"description\": \"Short summary\" \
            }}",
            query, platform_str
        );

        let response = self.generate(&prompt).await?;
        // Native JSON mode returns raw JSON, no markdown stripping needed usually, 
        // but keeping extraction is safe if the model adds whitespace.
        // However, extract_json_array handles the outer brackets.
        let cleaned_json = extract_json_array(&response);
        
        let results: Vec<LlmSearchResult> = serde_json::from_str(&cleaned_json)
            .map_err(|e| anyhow!("Failed to parse LLM JSON: {}. Response: {}", e, response))?;

        let search_results = results.into_iter().map(|r| {
            // Encode Platform in ID so fetch_details has context
            ScraperSearchResult {
                id: format!("llm:{}|{}", r.title, r.platform),
                title: r.title.clone(),
                platform: r.platform,
                platforms: None,
                platform_ids: None,
                region: r.region,
                release_year: r.release_year,
                resolution: Some("LLM Generated".to_string()),
                thumbnail_url: None,
                can_add_to_collection: true,
                metadata: None, // Force fetch_details to get full metadata
            }
        }).collect();

        Ok(search_results)
    }

    async fn fetch_details(&self, result_id: &str) -> Result<ScrapedMetadata> {
        let (title, platform) = if result_id.contains('|') {
            let parts: Vec<&str> = result_id.split('|').collect();
            let t = parts[0].strip_prefix("llm:").unwrap_or(parts[0]);
            (t, parts[1])
        } else {
            (result_id.strip_prefix("llm:").unwrap_or(result_id), "Any Platform")
        };

        let prompt = format!(
            "Provide detailed metadata for the video game '{}' on platform '{}'. \
            Return a SINGLE valid JSON object. \
            The 'description' field MUST be detailed, engaging, and at least 3 sentences long. \
            Schema example: \
            {{ \
                \"title\": \"Game Title\", \
                \"description\": \"Long and detailed description...\", \
                \"developer\": \"Developer Name\", \
                \"publisher\": \"Publisher Name\", \
                \"genre\": \"Action, RPG\", \
                \"release_year\": 1999, \
                \"region\": \"USA\", \
                \"links\": [{{ \"type\": \"Official\", \"url\": \"https://example.com\", \"label\": \"Official Website\" }}] \
            }}",
            title, platform
        );

        let response = self.generate(&prompt).await?;
        let cleaned_json = extract_json_object(&response);
        // println!("[LLM Debug] Fetch Details JSON: {}", cleaned_json);
        
        let data: LlmGameDetails = serde_json::from_str(&cleaned_json)
            .map_err(|e| anyhow!("Failed to parse LLM JSON: {}. Response: {}", e, response))?;

        Ok(ScrapedMetadata {
            title: data.title,
            description: data.description,
            developer: data.developer,
            publisher: data.publisher,
            genre: data.genre,
            region: data.region,
            release_year: data.release_year,
            rating: None,
            assets: std::collections::HashMap::new(),
            resources: data.links.unwrap_or_default(),
            source: "LLM".to_string(),
            source_id: result_id.to_string(),
        })
    }
}

fn extract_json_array(s: &str) -> String {
    let s = s.trim();
    if let Some(start) = s.find('[') {
        if let Some(end) = s.rfind(']') {
             if end > start { return s[start..=end].to_string(); }
        }
    }
    s.to_string()
}

fn extract_json_object(s: &str) -> String {
    let s = s.trim();
    if let Some(start) = s.find('{') {
        if let Some(end) = s.rfind('}') {
             if end > start { return s[start..=end].to_string(); }
        }
    }
    s.to_string()
}

#[derive(Deserialize)]
struct LlmSearchResult {
    title: String,
    platform: String,
    release_year: Option<i32>,
    region: Option<String>,
    description: String,
}

#[derive(Deserialize)]
struct LlmGameDetails {
    title: String,
    description: String,
    developer: String,
    publisher: String,
    genre: String,
    release_year: Option<i32>,
    region: String,
    #[serde(default)]
    links: Option<Vec<crate::core::scraper::ScrapedResource>>,
}
