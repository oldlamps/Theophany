use std::sync::Arc;
use crate::core::scraper::ScraperProvider;
use crate::core::scraper::client::ScraperClient;
use crate::core::scraper::launchbox::LaunchBoxProvider;
use crate::core::scraper::search_engine::SearchEngineProvider;
use crate::core::scraper::wikipedia::WikipediaProvider;
use crate::core::scraper::igdb::IGDBProvider;

pub struct ScraperManager;

impl ScraperManager {
    pub fn get_provider(name: &str, client: Arc<ScraperClient>, ollama_url: String, ollama_model: String, gemini_key: String, openai_key: String, active_llm_provider: String) -> Arc<dyn ScraperProvider> {
        match name {
            "LaunchBox" => Arc::new(LaunchBoxProvider::new(client)),
            "IGDB" => Arc::new(IGDBProvider::new(client)),
            "Ollama + Web Search" => Arc::new(crate::core::scraper::ollama_web::OllamaWebProvider::new(client, ollama_url, ollama_model)),
            "LLM API" => Arc::new(crate::core::scraper::llm_api::LlmApiProvider::new(client, gemini_key, openai_key, active_llm_provider)),
            "Wikipedia" => Arc::new(WikipediaProvider::new(client)),
            "Steam" => Arc::new(crate::core::scraper::steam::SteamProvider::new(client)),
            // Map "Web Search" to SearchEngineProvider (which reports "Bing Images" as name)
            "Bing Images" | "Web Search" => Arc::new(SearchEngineProvider::new(client)),
            _ => Arc::new(LaunchBoxProvider::new(client)), // Fallback
        }
    }

    pub fn get_available_providers() -> Vec<String> {
        vec![
            "IGDB".to_string(),
            "Wikipedia".to_string(),
            "Steam".to_string(),
            "Ollama + Web Search".to_string(),
            "LLM API".to_string(),
            "LaunchBox".to_string(),
        ]
    }
}
