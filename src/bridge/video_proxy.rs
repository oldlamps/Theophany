#![allow(non_snake_case)]
use qmetaobject::prelude::*;
use std::process::Command;
use std::thread;
use std::sync::mpsc;
use std::cell::RefCell;
use serde::Deserialize;

// Helper to get the yt-dlp binary path from settings
fn get_ytdlp_binary() -> String {
    #[derive(Deserialize)]
    struct YtdlpSettings {
        #[serde(default)]
        use_custom_ytdlp: bool,
        #[serde(default)]
        custom_ytdlp_path: String,
    }

    // 1. Check Settings for custom path
    let path = crate::core::paths::get_config_dir().join("settings.json");
    if let Ok(content) = std::fs::read_to_string(&path) {
        if let Ok(data) = serde_json::from_str::<YtdlpSettings>(&content) {
            if data.use_custom_ytdlp && !data.custom_ytdlp_path.is_empty() {
                let p = std::path::PathBuf::from(&data.custom_ytdlp_path);
                if p.exists() {
                    return data.custom_ytdlp_path;
                }
            }
        }
    }

    // 2. Check internal tools directory
    let internal = crate::core::paths::get_tools_dir().join("yt-dlp");
    if internal.exists() {
        return internal.to_string_lossy().to_string();
    }

    // 3. Fallback to System PATH
    "yt-dlp".to_string()
}

#[derive(QObject, Default)]
pub struct VideoProxy {
    base: qt_base_class!(trait QObject),

    // Signals
    trailerUrlReady: qt_signal!(url: QString),
    videoAvailable: qt_signal!(url: QString),
    videoUnavailable: qt_signal!(),
    errorOccurred: qt_signal!(msg: QString),
    videoSearchFinished: qt_signal!(json_results: QString),
    videoDownloadFinished: qt_signal!(path: QString),
    videoListReady: qt_signal!(json: QString),
    videoDeleted: qt_signal!(path: QString),
    streamUrlReady: qt_signal!(url: QString, original_url: QString),

    // Methods
    init: qt_method!(fn(&mut self, path: String)),
    fetchTrailerUrl: qt_method!(fn(&mut self, id: String, title: String, platform: String, platform_folder: String)),
    checkCachedVideo: qt_method!(fn(&mut self, id: String, platform_folder: String)),
    getVideoList: qt_method!(fn(&mut self, id: String, platform_folder: String)),
    searchVideos: qt_method!(fn(&mut self, query: String)),
    downloadVideo: qt_method!(fn(&mut self, url: String, game_id: String, platform_folder: String, title: String)),
    deleteVideo: qt_method!(fn(&mut self, path: String)),
    getStreamUrl: qt_method!(fn(&mut self, url: String)),
    poll: qt_method!(fn(&mut self)),
    
    // Internal
    db_path: RefCell<String>,
    // We need different channels or message types for search vs download
    // Using a simple enum for message passing
    tx: RefCell<Option<mpsc::Sender<VideoWorkerMsg>>>,
    rx: RefCell<Option<mpsc::Receiver<VideoWorkerMsg>>>,
}

enum VideoWorkerMsg {
    LegacyUrlReady(String),
    VideoFound(String),
    VideoNotFound,
    SearchFinished(String),
    DownloadFinished(String),
    VideoListReady(String),
    VideoDeleted(String),
    StreamUrlReady(String, String), // resolved_url, original_url
    Error(String),
}

impl VideoProxy {
    fn init(&mut self, path: String) {
        *self.db_path.borrow_mut() = path;
    }

    fn fetchTrailerUrl(&mut self, id: String, title: String, platform: String, platform_folder: String) {
        // Initialize channel if needed
        if self.tx.borrow().is_none() {
             let (tx, rx) = mpsc::channel();
             *self.tx.borrow_mut() = Some(tx);
             *self.rx.borrow_mut() = Some(rx);
        }

        let tx = self.tx.borrow().as_ref().unwrap().clone();
        
        // println!("Fetching trailer for: {} ({}) in platform: {}", title, platform, platform_folder);

        thread::spawn(move || {
            // Setup cache path: Videos/<platform_id>/<game_id>/
            let data_dir = crate::core::paths::get_data_dir();
            let game_video_dir = data_dir.join("Videos").join(&platform_folder).join(&id);
            if !game_video_dir.exists() {
                let _ = std::fs::create_dir_all(&game_video_dir);
            }

            // Check for any video file in the directory
            if let Ok(entries) = std::fs::read_dir(&game_video_dir) {
                for entry in entries.flatten() {
                    let path = entry.path();
                    if path.is_file() {
                         let ext = path.extension().unwrap_or_default().to_string_lossy().to_lowercase();
                         if matches!(ext.as_str(), "mp4" | "mkv" | "webm" | "avi") {
                             // println!("Trailer found in folder: {:?}", path);
                             let url = format!("file://{}", path.to_string_lossy());
                             let _ = tx.send(VideoWorkerMsg::LegacyUrlReady(url));
                             return;
                         }
                    }
                }
            }

            // "ytsearch20:<title> <platform> gameplay" - Search 20 candidates
            let search_query = format!("ytsearch20:{} {} gameplay", title, platform);
            
            // For auto-fetch, we'll just pick a name like "Trailer" inside the folder
            let output_template = game_video_dir.join("Trailer.%(ext)s");
            // println!("Downloading trailer to template: {:?}", output_template);
            
            let output = Command::new(&get_ytdlp_binary())
                .arg("--no-config")
                .arg("-f")
                .arg("bestvideo[height<=720]+bestaudio/best[height<=720]")
                .arg("--merge-output-format")
                .arg("mp4")
                .arg("--match-filter")
                .arg("duration <= 600") // 10 minutes max
                .arg("--max-downloads")
                .arg("1")
                .arg("-o")
                .arg(output_template)
                .arg("--user-agent")
                .arg("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
                .arg(search_query)
                .output();

            match output {
                Ok(output) => {
                    if output.status.success() {
                        // Find the file that was created
                        let mut found_path = None;
                        if let Ok(entries) = std::fs::read_dir(&game_video_dir) {
                             for entry in entries.flatten() {
                                 let path = entry.path();
                                 if path.is_file() {
                                     found_path = Some(format!("file://{}", path.to_string_lossy()));
                                     break;
                                 }
                             }
                        }

                        if let Some(url) = found_path {
                            // println!("Download success: {}", url);
                            let _ = tx.send(VideoWorkerMsg::LegacyUrlReady(url));
                        } else {
                            let _ = tx.send(VideoWorkerMsg::Error("Download finished but no suitable video found.".to_string()));
                        }
                    } else {
                         let err = String::from_utf8_lossy(&output.stderr).to_string();
                         let _ = tx.send(VideoWorkerMsg::Error(err));
                    }
                }
                Err(e) => {
                     let _ = tx.send(VideoWorkerMsg::Error(e.to_string()));
                }
            }
        });
    }

    fn searchVideos(&mut self, query: String) {
        if self.tx.borrow().is_none() {
             let (tx, rx) = mpsc::channel();
             *self.tx.borrow_mut() = Some(tx);
             *self.rx.borrow_mut() = Some(rx);
        }
        let tx = self.tx.borrow().as_ref().unwrap().clone();

        thread::spawn(move || {
            let output = Command::new(&get_ytdlp_binary())
                .arg("--no-config")
                .arg("--dump-json")
                .arg("--flat-playlist")
                .arg("--user-agent")
                .arg("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
                .arg(format!("ytsearch20:{}", query))
                .output();

            match output {
                Ok(output) => {
                    if output.status.success() {
                        let stdout = String::from_utf8_lossy(&output.stdout);
                        // yt-dlp outputs one JSON object per line for flat-playlist
                        // We need to parse them and bundle into a single JSON array
                        let mut results = Vec::new();
                        for line in stdout.lines() {
                             if let Ok(json) = serde_json::from_str::<serde_json::Value>(line) {
                                 results.push(json);
                             }
                        }
                        let final_json = serde_json::to_string(&results).unwrap_or_default();
                        let _ = tx.send(VideoWorkerMsg::SearchFinished(final_json));
                    } else {
                        let _ = tx.send(VideoWorkerMsg::Error("Search failed".to_string()));
                    }
                },
                Err(e) => {
                     let _ = tx.send(VideoWorkerMsg::Error(e.to_string()));
                }
            }
        });
    }

    fn downloadVideo(&mut self, url: String, game_id: String, platform_folder: String, title: String) {
        // println!("VideoProxy::downloadVideo called for {} -> {} (Title: {})", url, game_id, title);
        if self.tx.borrow().is_none() {
             let (tx, rx) = mpsc::channel();
             *self.tx.borrow_mut() = Some(tx);
             *self.rx.borrow_mut() = Some(rx);
        }
        let tx = self.tx.borrow().as_ref().unwrap().clone();

        thread::spawn(move || {
            let data_dir = crate::core::paths::get_data_dir();
            let game_video_dir = data_dir.join("Videos").join(&platform_folder).join(&game_id);
            if !game_video_dir.exists() {
                let _ = std::fs::create_dir_all(&game_video_dir);
            }

            // Clean title for filename
            let clean_title = title.replace(|c: char| !c.is_alphanumeric() && c != ' ' && c != '-', "_");
            let output_template = game_video_dir.join(format!("{}.%(ext)s", clean_title));
            
            let output = Command::new(&get_ytdlp_binary())
                .arg("--no-config")
                .arg("-f")
                .arg("bestvideo[height<=720]+bestaudio/best[height<=720]")
                .arg("--merge-output-format")
                .arg("mp4")
                .arg("-o")
                .arg(output_template)
                .arg("--no-playlist")
                .arg("--user-agent")
                .arg("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
                .arg(&url)
                .output();

            match output {
                Ok(output) => {
                    if output.status.success() {
                         // Find the file we just downloaded
                         let mut found_path = None;
                         if let Ok(entries) = std::fs::read_dir(&game_video_dir) {
                            for entry in entries.flatten() {
                                let path = entry.path();
                                if path.is_file() {
                                    if let Some(stem) = path.file_stem() {
                                        if stem.to_string_lossy() == clean_title {
                                            found_path = Some(format!("file://{}", path.to_string_lossy()));
                                            break;
                                        }
                                    }
                                }
                            }
                        }
                        if let Some(path) = found_path {
                            let _ = tx.send(VideoWorkerMsg::DownloadFinished(path));
                        } else {
                            let _ = tx.send(VideoWorkerMsg::Error("Download appeared successful but file not found".to_string()));
                        }
                    } else {
                        let err_msg = String::from_utf8_lossy(&output.stderr).to_string();
                        let _ = tx.send(VideoWorkerMsg::Error(format!("Download failed: {}", err_msg)));
                    }
                },
                Err(e) => {
                    let _ = tx.send(VideoWorkerMsg::Error(e.to_string()));
                }
            }
        });
    }

    fn getStreamUrl(&mut self, url: String) {
        if self.tx.borrow().is_none() {
             let (tx, rx) = mpsc::channel();
             *self.tx.borrow_mut() = Some(tx);
             *self.rx.borrow_mut() = Some(rx);
        }
        let tx = self.tx.borrow().as_ref().unwrap().clone();

        thread::spawn(move || {
            // Check if it's already a direct streamable link to avoid yt-dlp overhead/failures
            let lower_url = url.to_lowercase();
            let is_direct = lower_url.contains("steamstatic.com") || 
                            lower_url.ends_with(".mp4") || 
                            lower_url.ends_with(".mkv") || 
                            lower_url.ends_with(".webm") || 
                            lower_url.ends_with(".m3u8") || 
                            lower_url.ends_with(".mpd") ||
                            lower_url.contains(".mp4?") || 
                            lower_url.contains(".webm?") || 
                            lower_url.contains(".m3u8?") || 
                            lower_url.contains(".mpd?");

            if is_direct {
                let _ = tx.send(VideoWorkerMsg::StreamUrlReady(url.clone(), url));
                return;
            }

            let output = Command::new(&get_ytdlp_binary())
                .arg("-g")
                .arg("--no-config")
                .arg("--no-playlist")
                .arg("--no-cache-dir")
                .arg("--live-from-start")
                .arg("--format-sort")
                .arg("res:720,ext:mp4:m4a")
                .arg("-f")
                // Prioritize progressive MP4 (itag 22 and 18) for maximum player compatibility
                .arg("22/18/best[ext=mp4][height<=720]/best[height<=720]/best")
                .arg(&url)
                .output();

            match output {
                Ok(output) => {
                    if output.status.success() {
                        let stdout = String::from_utf8_lossy(&output.stdout);
                        let mut stream_url = stdout.lines().next().unwrap_or_default().trim().to_string();
                        
                        // Sanitize URL: Strip any accidental time/start/begin parameters
                        let params_to_strip = ["&t=", "&start=", "&begin=", "&seek="];
                        for param in params_to_strip {
                            if let Some(pos) = stream_url.find(param) {
                                stream_url = stream_url[..pos].to_string();
                            }
                        }
                        
                        // Handle cases where the parameter might be at the end or mid-string without '&'
                        for p in &["begin=", "start=", "t=", "seek="] {
                            if let Some(pos) = stream_url.find(p) {
                                if pos > 0 {
                                    let prev_char = stream_url.as_bytes()[pos-1] as char;
                                    if prev_char == '?' || prev_char == '&' {
                                        stream_url = stream_url[..pos-1].to_string();
                                    }
                                }
                            }
                        }

                        if !stream_url.is_empty() {
                            let _ = tx.send(VideoWorkerMsg::StreamUrlReady(stream_url, url));
                        } else {
                            let _ = tx.send(VideoWorkerMsg::Error("Empty stream URL returned".to_string()));
                        }
                    } else {
                        let _ = tx.send(VideoWorkerMsg::Error("Failed to fetch stream URL".to_string()));
                    }
                },
                Err(e) => {
                    let _ = tx.send(VideoWorkerMsg::Error(e.to_string()));
                }
            }
        });
    }

    fn checkCachedVideo(&mut self, id: String, platform_folder: String) {
        // Just use getVideoList logic but trigger different signal for backward compatibility in QML where expected
        if self.tx.borrow().is_none() {
             let (tx, rx) = mpsc::channel();
             *self.tx.borrow_mut() = Some(tx);
             *self.rx.borrow_mut() = Some(rx);
        }
        let tx = self.tx.borrow().as_ref().unwrap().clone();
        
        thread::spawn(move || {
            let data_dir = crate::core::paths::get_data_dir();
            let game_video_dir = data_dir.join("Videos").join(&platform_folder).join(&id);
            
            if let Ok(entries) = std::fs::read_dir(&game_video_dir) {
                for entry in entries.flatten() {
                    let path = entry.path();
                    if path.is_file() {
                         let url = format!("file://{}", path.to_string_lossy());
                         let _ = tx.send(VideoWorkerMsg::VideoFound(url));
                         return;
                    }
                }
            }
            let _ = tx.send(VideoWorkerMsg::VideoNotFound);
        });
    }

    fn getVideoList(&mut self, id: String, platform_folder: String) {
        if self.tx.borrow().is_none() {
             let (tx, rx) = mpsc::channel();
             *self.tx.borrow_mut() = Some(tx);
             *self.rx.borrow_mut() = Some(rx);
        }
        let tx = self.tx.borrow().as_ref().unwrap().clone();
        let db_path = self.db_path.borrow().clone();
        
        thread::spawn(move || {
            let data_dir = crate::core::paths::get_data_dir();
            let game_video_dir = data_dir.join("Videos").join(&platform_folder).join(&id);
            
            let mut list = Vec::new();

            // 1. Fetch from Database Resources (Streamable Links)
            if !db_path.is_empty() {
                if let Ok(db) = crate::core::db::DbManager::open(&db_path) {
                    if let Ok(resources) = db.get_resources(&id) {
                        for res in resources {
                            if res.type_.to_lowercase() == "video" {
                                list.push(serde_json::json!({
                                    "title": res.label.unwrap_or_else(|| "Video Resource".to_string()),
                                    "url": res.url,
                                    "is_resource": true,
                                    "size": "--",
                                    "duration": "--:--",
                                    "duration_secs": 0.0
                                }));
                            }
                        }
                    }
                }
            }

            // 2. Fetch from Local Files
            if let Ok(entries) = std::fs::read_dir(&game_video_dir) {
                for entry in entries.flatten() {
                    let path = entry.path();
                    if path.is_file() {
                        let ext = path.extension().unwrap_or_default().to_string_lossy().to_lowercase();
                        if matches!(ext.as_str(), "mp4" | "mkv" | "webm" | "avi") {
                            let title = path.file_stem().unwrap_or_default().to_string_lossy().to_string();
                            let url = format!("file://{}", path.to_string_lossy());
                            
                            // Get Metadata
                            let mut size_str = "Unknown".to_string();
                            if let Ok(meta) = path.metadata() {
                                let len = meta.len();
                                if len < 1024 {
                                    size_str = format!("{} B", len);
                                } else if len < 1024 * 1024 {
                                    size_str = format!("{:.1} KB", len as f64 / 1024.0);
                                } else if len < 1024 * 1024 * 1024 {
                                    size_str = format!("{:.1} MB", len as f64 / (1024.0 * 1024.0));
                                } else {
                                    size_str = format!("{:.1} GB", len as f64 / (1024.0 * 1024.0 * 1024.0));
                                }
                            }

                            // Get Duration via ffprobe
                            let mut duration_str = "--:--".to_string();
                            let mut duration_secs = 0.0;
                            
                            if let Ok(output) = std::process::Command::new("ffprobe")
                                .args(&["-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1"])
                                .arg(&path)
                                .output() 
                            {
                                if output.status.success() {
                                    let out_str = String::from_utf8_lossy(&output.stdout);
                                    if let Ok(secs) = out_str.trim().parse::<f64>() {
                                        duration_secs = secs;
                                        let total_secs = secs as u64;
                                        let hours = total_secs / 3600;
                                        let minutes = (total_secs % 3600) / 60;
                                        let seconds = total_secs % 60;
                                        if hours > 0 {
                                            duration_str = format!("{:02}:{:02}:{:02}", hours, minutes, seconds);
                                        } else {
                                            duration_str = format!("{:02}:{:02}", minutes, seconds);
                                        }
                                    }
                                }
                            }

                            list.push(serde_json::json!({
                                "title": title,
                                "url": url,
                                "path": path.to_string_lossy(),
                                "size": size_str,
                                "duration": duration_str,
                                "duration_secs": duration_secs
                            }));
                        }
                    }
                }
            }
            
            let json = serde_json::to_string(&list).unwrap_or_else(|_| "[]".to_string());
            let _ = tx.send(VideoWorkerMsg::VideoListReady(json));
        });
    }

    fn deleteVideo(&mut self, path: String) {
        if self.tx.borrow().is_none() {
             let (tx, rx) = mpsc::channel();
             *self.tx.borrow_mut() = Some(tx);
             *self.rx.borrow_mut() = Some(rx);
        }
        let tx = self.tx.borrow().as_ref().unwrap().clone();
        
        thread::spawn(move || {
            let clean_path = if path.starts_with("file://") {
                path.replace("file://", "")
            } else {
                path.clone()
            };
            
            let p = std::path::Path::new(&clean_path);
            if p.exists() {
                if let Err(e) = std::fs::remove_file(p) {
                    let _ = tx.send(VideoWorkerMsg::Error(format!("Failed to delete: {}", e)));
                } else {
                    let _ = tx.send(VideoWorkerMsg::VideoDeleted(path));
                }
            } else {
                 let _ = tx.send(VideoWorkerMsg::Error("File not found for deletion".to_string()));
            }
        });
    }

    fn poll(&mut self) {
        let rx_borrow = self.rx.borrow();
        if let Some(rx) = rx_borrow.as_ref() {
            while let Ok(msg) = rx.try_recv() {
                match msg {
                    VideoWorkerMsg::LegacyUrlReady(url) => self.trailerUrlReady(url.into()),
                    VideoWorkerMsg::VideoFound(url) => self.videoAvailable(url.into()),
                    VideoWorkerMsg::VideoNotFound => self.videoUnavailable(),
                    VideoWorkerMsg::SearchFinished(json) => self.videoSearchFinished(json.into()),
                    VideoWorkerMsg::DownloadFinished(path) => self.videoDownloadFinished(path.into()),
                    VideoWorkerMsg::VideoListReady(json) => self.videoListReady(json.into()),
                    VideoWorkerMsg::VideoDeleted(path) => self.videoDeleted(path.into()),
                    VideoWorkerMsg::StreamUrlReady(url, original) => self.streamUrlReady(url.into(), original.into()),
                    VideoWorkerMsg::Error(e) => self.errorOccurred(e.into()),
                }
            }
        }
    }
}
