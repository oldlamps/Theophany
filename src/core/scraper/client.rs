use reqwest::{Client, header::USER_AGENT};
use std::time::Duration;
use tokio::time::sleep;
use rand::seq::SliceRandom;
use anyhow::Result;

pub struct ScraperClient {
    client: Client,
    user_agents: Vec<String>,
}

impl ScraperClient {
    pub fn new() -> Self {
        let user_agents = vec![
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36".to_string(),
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36".to_string(),
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0".to_string(),
        ];
        
        let client = Client::builder()
            .timeout(Duration::from_secs(30))
            .build()
            .expect("Failed to build reqwest client");
            
        Self { client, user_agents }
    }
    
    pub async fn get(&self, url: &str) -> Result<String> {
        // Randomly wait to mask automation (500ms to 1500ms)
        let delay = rand::random::<u64>() % 1000 + 500;
        sleep(Duration::from_millis(delay)).await;
        
        let ua = self.user_agents.choose(&mut rand::thread_rng()).unwrap();
    
        let response = self.client.get(url)
            .header(USER_AGENT, ua)
            .header("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8")
            .header("Accept-Language", "en-US,en;q=0.9")
            // Referer is often required by MobyGames
            .header("Referer", "https://www.google.com/")
            .send()
            .await?;
            
        if !response.status().is_success() {
            return Err(anyhow::anyhow!("Request failed with status: {} for URL: {}", response.status(), url));
        }
        
        Ok(response.text().await?)
    }

    pub async fn get_bytes(&self, url: &str) -> Result<Vec<u8>> {
        let delay = rand::random::<u64>() % 1000 + 300;
        sleep(Duration::from_millis(delay)).await;
        
        let ua = self.user_agents.choose(&mut rand::thread_rng()).unwrap();
        
        let response = self.client.get(url)
            .header(USER_AGENT, ua)
            .send()
            .await?;
            
        if !response.status().is_success() {
            return Err(anyhow::anyhow!("Request failed with status: {} for URL: {}", response.status(), url));
        }
        
        Ok(response.bytes().await?.to_vec())
    }

    pub async fn post_json(&self, url: &str, body: &serde_json::Value) -> Result<String> {
        let response = self.client.post(url)
            .header("Content-Type", "application/json")
            .json(body)
            .send()
            .await?;
            
        if !response.status().is_success() {
             let status = response.status();
             let text = response.text().await.unwrap_or_default();
             return Err(anyhow::anyhow!("API Request failed: {} - {}", status, text));
        }
        
        Ok(response.text().await?)
    }

    pub async fn post_json_bearer(&self, url: &str, body: &serde_json::Value, token: &str) -> Result<String> {
        let response = self.client.post(url)
            .header("Content-Type", "application/json")
            .header("Authorization", format!("Bearer {}", token))
            .json(body)
            .send()
            .await?;

        if !response.status().is_success() {
             let status = response.status();
             let text = response.text().await.unwrap_or_default();
             return Err(anyhow::anyhow!("API Request failed: {} - {}", status, text));
        }

        Ok(response.text().await?)
    }

    pub async fn post_raw(&self, url: &str, body: String, extra_headers: Vec<(String, String)>) -> Result<String> {
        let mut req = self.client.post(url)
            .body(body);

        for (k, v) in extra_headers {
            req = req.header(k, v);
        }

        let response = req.send().await?;

        if !response.status().is_success() {
             let status = response.status();
             let text = response.text().await.unwrap_or_default();
             return Err(anyhow::anyhow!("API Request failed: {} - {}", status, text));
        }

        Ok(response.text().await?)
    }
}
