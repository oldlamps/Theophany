use qmetaobject::prelude::*;
use crate::core::ollama::OllamaClient;
use crate::core::models::AiContext;
use chrono::Timelike; // Timelike for hour/minute

use std::cell::RefCell;
use tokio::sync::mpsc;

#[derive(Default, QObject)]
pub struct AiAssistantBridge {
    base: qt_base_class!(trait QObject),
    
    // Properties
    currentResponse: qt_property!(QString; NOTIFY responseChanged),
    isGenerating: qt_property!(bool; NOTIFY generatingChanged),
    
    // Methods
    pollResponse: qt_method!(fn(&mut self)),
    stopGeneration: qt_method!(fn(&mut self)),
    generateDescription: qt_method!(fn(&mut self, title: String, current_desc: String, ollama_url: String, model: String, template: String, gemini_key: String, openai_key: String, provider: String)),
    fetchLocalModels: qt_method!(fn(&mut self, ollama_url: String)),
    testConnection: qt_method!(fn(&mut self, ollama_url: String)),
    
    // Internals
    rx: RefCell<Option<mpsc::Receiver<String>>>,
    model_rx: RefCell<Option<mpsc::Receiver<Vec<String>>>>,
    test_rx: RefCell<Option<mpsc::Receiver<String>>>,
    
    responseChanged: qt_signal!(),
    generatingChanged: qt_signal!(),
    modelsLoaded: qt_signal!(models: QString), // JSON Array
    connectionTested: qt_signal!(success: bool, message: QString),
}

impl AiAssistantBridge {
    fn trigger_generation(&mut self, ollama_url: String, model: String, template: String, title: String, current_desc: String, gemini_key: String, openai_key: String, provider: String) {
        if self.isGenerating {
            return;
        }
        
        self.currentResponse = QString::from("");
        self.responseChanged();
        
        self.isGenerating = true;
        self.generatingChanged();
        
        let (tx, rx) = mpsc::channel(32);
        *self.rx.borrow_mut() = Some(rx);
        
        std::thread::spawn(move || {
            let rt = tokio::runtime::Runtime::new().unwrap();
            rt.block_on(async {
                let prompt = template
                    .replace("{title}", &title)
                    .replace("{description}", &current_desc);

                if provider == "Ollama" {
                    let client = OllamaClient::new(ollama_url, model);
                    if let Err(e) = client.generate_stream(&prompt, None, tx.clone()).await {
                        let _ = tx.send(format!("(Connection Error: {})", e)).await;
                    }
                } else if provider == "Gemini" {
                    if gemini_key.is_empty() {
                        let _ = tx.send("(Error: Gemini API Key is missing)".to_string()).await;
                        return;
                    }
                    // Reuse LlmApiProvider-like logic but direct text
                    let url = format!("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={}", gemini_key);
                    let body = serde_json::json!({
                        "contents": [{ "parts": [{ "text": prompt }] }]
                    });
                    
                    let client = reqwest::Client::new();
                    match client.post(&url).json(&body).send().await {
                        Ok(resp) => {
                            if let Ok(json) = resp.json::<serde_json::Value>().await {
                                if let Some(text) = json["candidates"][0]["content"]["parts"][0]["text"].as_str() {
                                    let _ = tx.send(text.to_string()).await;
                                } else {
                                    let _ = tx.send(format!("(Error parsing Gemini response: {})", json)).await;
                                }
                            } else {
                                let _ = tx.send("(Error parsing Gemini JSON)".to_string()).await;
                            }
                        }
                        Err(e) => { let _ = tx.send(format!("(Gemini Request Error: {})", e)).await; }
                    }
                } else if provider == "OpenAI" {
                    if openai_key.is_empty() {
                        let _ = tx.send("(Error: OpenAI API Key is missing)".to_string()).await;
                        return;
                    }
                    let url = "https://api.openai.com/v1/chat/completions";
                    let body = serde_json::json!({
                        "model": "gpt-3.5-turbo",
                        "messages": [
                            {"role": "system", "content": "You are a helpful assistant that writes video game descriptions."},
                            {"role": "user", "content": prompt}
                        ]
                    });
                    
                    let client = reqwest::Client::new();
                    match client.post(url)
                        .header("Authorization", format!("Bearer {}", openai_key))
                        .json(&body)
                        .send()
                        .await {
                        Ok(resp) => {
                            if let Ok(json) = resp.json::<serde_json::Value>().await {
                                if let Some(text) = json["choices"][0]["message"]["content"].as_str() {
                                    let _ = tx.send(text.to_string()).await;
                                } else {
                                    let _ = tx.send("(Error parsing OpenAI response)".to_string()).await;
                                }
                            } else {
                                let _ = tx.send("(Error parsing OpenAI JSON)".to_string()).await;
                            }
                        }
                        Err(e) => { let _ = tx.send(format!("(OpenAI Request Error: {})", e)).await; }
                    }
                }
            });
        });
    }

    fn fetchLocalModels(&mut self, ollama_url: String) {
        let (tx, rx) = mpsc::channel(1);
        *self.model_rx.borrow_mut() = Some(rx);
        
        std::thread::spawn(move || {
            let rt = tokio::runtime::Runtime::new().unwrap();
            rt.block_on(async {
                let client = OllamaClient::new(ollama_url, "none".to_string());
                match client.list_models().await {
                    Ok(models) => { 
                        let _ = tx.send(models).await; 
                    }
                    Err(e) => { 
                        log::error!("[AiAssistantBridge] Error fetching models: {}", e);
                        let _ = tx.send(vec![]).await; 
                    }
                }
            });
        });
    }

    fn testConnection(&mut self, ollama_url: String) {
        let (tx, rx) = mpsc::channel(1);
        *self.test_rx.borrow_mut() = Some(rx);
        
        std::thread::spawn(move || {
            let rt = tokio::runtime::Runtime::new().unwrap();
            rt.block_on(async {
                let client = OllamaClient::new(ollama_url, "none".to_string());
                match client.check_connection().await {
                    Ok(_) => { let _ = tx.send("OK".to_string()).await; }
                    Err(e) => { let _ = tx.send(e.to_string()).await; }
                }
            });
        });
    }

    fn pollResponse(&mut self) {
        let mut disconnected = false;
        let mut buffer = String::new();
        
        {
            let mut rx_opt = self.rx.borrow_mut();
            if let Some(rx) = rx_opt.as_mut() {
                loop {
                    match rx.try_recv() {
                        Ok(chunk) => { buffer.push_str(&chunk); },
                        Err(mpsc::error::TryRecvError::Empty) => break,
                        Err(mpsc::error::TryRecvError::Disconnected) => {
                            disconnected = true;
                            break; 
                        }
                    }
                }
            }
        } 

        if !buffer.is_empty() {
             let mut current = self.currentResponse.to_string();
             current.push_str(&buffer);
             self.currentResponse = QString::from(current);
             self.responseChanged();
        }
        
        if disconnected {
            self.isGenerating = false;
            self.generatingChanged();
            *self.rx.borrow_mut() = None;
        }

        // Check for model list
        {
            let mut rx_opt = self.model_rx.borrow_mut();
            if let Some(rx) = rx_opt.as_mut() {
                if let Ok(models) = rx.try_recv() {
                    let json = serde_json::to_string(&models).unwrap_or_else(|_| "[]".to_string());
                    self.modelsLoaded(QString::from(json));
                    *rx_opt = None;
                }
            }
        }

        // Check for test result
        {
            let mut rx_opt = self.test_rx.borrow_mut();
            if let Some(rx) = rx_opt.as_mut() {
                if let Ok(result) = rx.try_recv() {
                    if result == "OK" {
                        self.connectionTested(true, QString::from("Connect Successful"));
                    } else {
                        self.connectionTested(false, QString::from(result));
                    }
                    *rx_opt = None;
                }
            }
        }
    }
    
    fn stopGeneration(&mut self) {
        // Drop receiver to stop stream
        *self.rx.borrow_mut() = None;
        self.isGenerating = false;
        self.generatingChanged();
    }

    fn generateDescription(&mut self, title: String, current_desc: String, ollama_url: String, model: String, custom_prompt: String, gemini_key: String, openai_key: String, provider: String) {
        self.trigger_generation(ollama_url, model, custom_prompt, title, current_desc, gemini_key, openai_key, provider);
    }

    fn build_prompt(&self, context: Option<AiContext>) -> String {
        let mut prompt = String::from("Here is the user's current status:\n");
        
        // Add Temporal Context
        let now = chrono::Local::now();
        let hour = now.hour();
        let time_of_day = if hour < 12 { "Morning" } else if hour < 18 { "Afternoon" } else if hour < 22 { "Evening" } else { "Late Night" };
        prompt.push_str(&format!("Time: {} ({:02}:{:02}).\n", time_of_day, hour, now.minute()));
        
        if let Some(ctx) = context {
            if !ctx.recent_games.is_empty() {
                prompt.push_str("Recently Played:\n");
                for game in ctx.recent_games.iter() {
                    prompt.push_str(&format!("- {} (Played for {}s)\n", game.title, game.total_play_time));
                }
            } else {
                 prompt.push_str("User hasn't played anything recently.\n");
            }
            
            if !ctx.near_completion.is_empty() {
                prompt.push_str("Near Completion (>75%):\n");
                 for game in ctx.near_completion.iter() {
                    prompt.push_str(&format!("- {} ({:.0}% done)\n", game.title, game.completion_rate * 100.0));
                }
            }
            
            if !ctx.ignored_favorites.is_empty() {
                 prompt.push_str("Long lost favorites:\n");
                 for game in ctx.ignored_favorites.iter() {
                    prompt.push_str(&format!("- {}\n", game.title));
                }
            }
        } else {
            prompt.push_str("No play history available.\n");
        }
        
        prompt.push_str("\nSuggest what to play next based on this context.");
        prompt
    }
}
