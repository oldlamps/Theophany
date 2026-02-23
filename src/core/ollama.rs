#![allow(dead_code)]
use serde::{Deserialize, Serialize};
use reqwest::Client;
use anyhow::{Result, anyhow};
use futures_util::stream::StreamExt; // Correct trait import
use tokio::sync::mpsc;

#[derive(Clone)]
pub struct OllamaClient {
    base_url: String,
    model: String,
    client: Client,
}

#[derive(Serialize)]
struct GenerateRequest {
    model: String,
    prompt: String,
    stream: bool,
    system: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    format: Option<String>,
}

#[derive(Deserialize, Debug)]
struct GenerateResponse {
    model: String,
    created_at: String,
    response: String,
    done: bool,
}

#[derive(Deserialize, Debug)]
struct ModelTagsResponse {
    models: Vec<ModelTag>,
}

#[derive(Deserialize, Debug)]
struct ModelTag {
    name: String,
}

impl OllamaClient {
    pub fn new(base_url: String, model: String) -> Self {
        let base_url = base_url.trim_end_matches('/').to_string();
        Self {
            base_url,
            model,
            client: Client::new(),
        }
    }

    pub async fn check_connection(&self) -> Result<()> {
        let url = format!("{}/api/tags", self.base_url);
        let resp = self.client.get(&url).send().await?;
        if resp.status().is_success() {
            Ok(())
        } else {
            let status = resp.status();
            let body = resp.text().await.unwrap_or_else(|_| "Empty body".to_string());
            Err(anyhow!("Failed to connect to Ollama ({}): {}", status, body))
        }
    }

    pub async fn list_models(&self) -> Result<Vec<String>> {
        let url = format!("{}/api/tags", self.base_url);
        let resp = self.client.get(&url).send().await?.json::<ModelTagsResponse>().await?;
        Ok(resp.models.into_iter().map(|m| m.name).collect())
    }

    pub async fn generate(
        &self,
        prompt: &str,
        system_prompt: Option<&str>,
        json_mode: bool,
    ) -> Result<String> {
        let url = format!("{}/api/generate", self.base_url);
        
        let req = GenerateRequest {
            model: self.model.clone(),
            prompt: prompt.to_string(),
            stream: false,
            system: system_prompt.map(|s| s.to_string()),
            format: if json_mode { Some("json".to_string()) } else { None },
        };

        let resp = self.client.post(&url)
            .json(&req)
            .send()
            .await?
            .json::<GenerateResponse>()
            .await?;

        Ok(resp.response)
    }

    pub async fn generate_stream(
        &self, 
        prompt: &str, 
        system_prompt: Option<&str>,
        tx: mpsc::Sender<String>
    ) -> Result<()> {
        let url = format!("{}/api/generate", self.base_url);
        
        let req = GenerateRequest {
            model: self.model.clone(),
            prompt: prompt.to_string(),
            stream: true,
            system: system_prompt.map(|s| s.to_string()),
            format: None,
        };

        let mut stream = self.client.post(&url)
            .json(&req)
            .send()
            .await?
            .bytes_stream();

        while let Some(item) = stream.next().await {
            match item {
                Ok(bytes) => {
                    let chunk_str = String::from_utf8_lossy(&bytes);
                    // Parse JSON - Ollama sends multiple JSON objects in the stream, but sometimes they might be chunked weirdly in the bytes?
                    // Usually each chunk is a valid JSON line or we need to handle buffering.
                    // For simplicitly via bytes_stream(), often each chunk is one or more lines.
                    // Let's iterate over lines if possible.
                    
                    for line in chunk_str.split('\n') {
                        if line.trim().is_empty() { continue; }
                        
                        if let Ok(resp) = serde_json::from_str::<GenerateResponse>(line) {
                             if !resp.response.is_empty() {
                                 if tx.send(resp.response).await.is_err() {
                                     return Ok(()); // Receiver dropped
                                 }
                             }
                             if resp.done {
                                 return Ok(());
                             }
                        } else {
                            // error parsing incomplete chunk? 
                            // In a robust impl we'd buffer. For now assuming lines align.
                        }
                    }
                }
                Err(e) => return Err(anyhow!("Stream error: {}", e)),
            }
        }

        Ok(())
    }
}
