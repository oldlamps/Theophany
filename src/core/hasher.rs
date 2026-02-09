use sha1::{Digest, Sha1};
use std::fs::File;
use std::io::{self, Read, BufRead};
use std::path::Path;

pub struct Hasher;

impl Hasher {
    /// Calculates the SHA1 hash of a file at the given path.
    /// Returns a lowercase hex string.
    pub fn calculate_sha1<P: AsRef<Path>>(path: P) -> io::Result<String> {
        let mut file = File::open(path)?;
        let mut hasher = Sha1::new();
        let mut buffer = [0; 8192]; // 8KB buffer

        loop {
            let count = file.read(&mut buffer)?;
            if count == 0 {
                break;
            }
            hasher.update(&buffer[..count]);
        }

        let result = hasher.finalize();
        Ok(hex::encode(result))
    }

    /// Calculates the MD5 hash of a file at the given path.
    /// If the file is a ZIP archive, it hashes the first file inside.
    /// Returns a lowercase hex string.
    pub fn calculate_md5<P: AsRef<Path>>(path: P) -> io::Result<String> {
        let path_str = path.as_ref().to_string_lossy();
        // handling file:// prefix if present
        let clean_path = if path_str.starts_with("file://") {
            &path_str[7..]
        } else {
            &path_str
        };
        
        let file_path = Path::new(clean_path);
        let file = File::open(file_path)?;

        // Check if zip or m3u
        if let Some(ext) = file_path.extension() {
            let ext_str = ext.to_string_lossy().to_lowercase();
            if ext_str == "zip" {
                 return Self::calculate_zip_md5(file);
            } else if ext_str == "m3u" || ext_str == "m3u8" {
                 return Self::calculate_m3u_md5(file_path);
            } else if ext_str == "m3u" || ext_str == "m3u8" {
                 return Self::calculate_m3u_md5(file_path);
            }
        }

        let mut context = md5::Context::new();
        let mut buffer = [0; 8192];
        let mut reader = std::io::BufReader::new(file);

        // RetroAchievements Special Handling: NES Header Skipping
        // If extension is .nes, skip first 16 bytes
        if let Some(ext) = file_path.extension() {
            if ext.to_string_lossy().to_lowercase() == "nes" {
                 let mut header = [0; 16];
                 let _ = reader.read(&mut header)?;
                 // We don't verify the header, just skip it as RA does
            }
        }

        loop {
            let count = reader.read(&mut buffer)?;
            if count == 0 {
                break;
            }
            context.consume(&buffer[..count]);
        }

        let result = context.compute();
        Ok(format!("{:x}", result))
    }

    fn calculate_zip_md5(file: File) -> io::Result<String> {
        let mut archive = zip::ZipArchive::new(file)?;
        
        // Find the "best" file to hash. RA emphasizes hashing the ROM file.
        // Simple heuristic: First file that looks like a ROM (not txt, nfo, etc)
        // Or just the largest file.
        
        let mut target_index = 0;
        let mut max_size = 0;
        let mut target_is_nes = false;
        
        for i in 0..archive.len() {
            let file = archive.by_index(i)?;
            if file.is_file() {
                // Ignore MacOS resource forks
                if file.name().contains("__MACOSX") { continue; }
                
                // Track largest
                if file.size() > max_size {
                    max_size = file.size();
                    target_index = i;
                    target_is_nes = file.name().to_lowercase().ends_with(".nes");
                }
            }
        }
        
        // Hash the target file
        let mut target_file = archive.by_index(target_index)?;
        let mut context = md5::Context::new();
        let mut buffer = [0; 8192];
        
        // Skip header if NES
        if target_is_nes {
             let mut header = [0; 16];
             let _ = target_file.read(&mut header)?;
        }
        
        loop {
            let count = target_file.read(&mut buffer)?;
            if count == 0 { break; }
            context.consume(&buffer[..count]);
        }
        
        let result = context.compute();
        Ok(format!("{:x}", result))
    }

    fn calculate_m3u_md5(path: &Path) -> io::Result<String> {
        let file = File::open(path)?;
        let reader = std::io::BufReader::new(file);
        
        for line in reader.lines() {
            let line = line?;
            let trimmed = line.trim();
            if trimmed.is_empty() || trimmed.starts_with("#") {
                continue;
            }
            
            // Filter for valid game extensions to avoid hashing non-game files (e.g. images)
            let lower = trimmed.to_lowercase();
            if lower.ends_with(".cue") || 
               lower.ends_with(".bin") || 
               lower.ends_with(".iso") || 
               lower.ends_with(".chd") ||
               lower.ends_with(".gdi") ||
               lower.ends_with(".cdi") || 
               lower.ends_with(".nes") ||
               lower.ends_with(".sfc") ||
               lower.ends_with(".smc") ||
               lower.ends_with(".md") ||
               lower.ends_with(".pce") {
                
                // Found a likely game file path
                // Handle relative paths correctly
                let target_path = path.parent().unwrap_or(Path::new("")).join(trimmed);
                
            // Debugging removed

                if !target_path.exists() {

                }

                // Recursively hash the target
                return Self::calculate_md5(target_path);
            }
        }
        
        // Fallback: Hash the M3U content itself if no valid file found
        // Re-open to read from start
        let mut file = File::open(path)?;
        let mut context = md5::Context::new();
        let mut buffer = [0; 8192];
        loop {
            let count = file.read(&mut buffer)?;
            if count == 0 { break; }
            context.consume(&buffer[..count]);
        }
        let result = context.compute();
        Ok(format!("{:x}", result))
    }
}
