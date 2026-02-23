#![allow(dead_code)]
use serde::{Deserialize, Serialize};
use async_trait::async_trait;
use std::collections::HashMap;

pub mod client;
pub mod launchbox;
pub mod screenscraper;
pub mod search_engine;
pub mod manager;
pub mod ollama_web;
pub mod llm_api;
pub mod wikipedia;
pub mod igdb;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScrapedResource {
    #[serde(rename = "type")]
    pub type_: String,
    pub url: String,
    pub label: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ScrapedMetadata {
    pub title: String,
    pub description: String,
    pub developer: String,
    pub publisher: String,
    pub genre: String,
    pub region: String,
    pub release_year: Option<i32>,
    pub rating: Option<f32>,
    pub assets: HashMap<String, Vec<String>>, // Category -> URLs
    #[serde(default)]
    pub resources: Vec<ScrapedResource>,
    pub source: String,
    pub source_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScraperSearchResult {
    pub id: String,
    pub title: String,
    pub platform: String,
    pub platforms: Option<Vec<String>>,
    pub platform_ids: Option<Vec<i32>>,
    pub region: Option<String>,
    pub release_year: Option<i32>,
    pub thumbnail_url: Option<String>,
    pub resolution: Option<String>,
    #[serde(default)]
    pub can_add_to_collection: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub metadata: Option<ScrapedMetadata>,
}

#[async_trait]
pub trait ScraperProvider: Send + Sync {
    fn name(&self) -> &'static str;
    async fn search(&self, query: &str, platform: Option<&str>) -> anyhow::Result<Vec<ScraperSearchResult>>;
    async fn fetch_details(&self, result_id: &str) -> anyhow::Result<ScrapedMetadata>;
}
