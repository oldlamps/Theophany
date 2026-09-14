use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;
use std::sync::Mutex;
use std::thread;

static PENDING_LAUNCH_QUEUE: Mutex<Vec<String>> = Mutex::new(Vec::new());

pub fn push_pending_launch(rom_id: String) {
    if let Ok(mut queue) = PENDING_LAUNCH_QUEUE.lock() {
        if !rom_id.trim().is_empty() {
            queue.push(rom_id.trim().to_string());
        }
    }
}

pub fn pop_pending_launch() -> Option<String> {
    if let Ok(mut queue) = PENDING_LAUNCH_QUEUE.lock() {
        if !queue.is_empty() {
            return Some(queue.remove(0));
        }
    }
    None
}

/// Tries to send launch or activate command to an existing running instance via Unix domain socket.
/// Returns true if a running instance handled the command (so current process can exit).
pub fn send_to_existing_instance(sock_path: &PathBuf, launch_id: Option<&str>) -> bool {
    if let Ok(mut stream) = UnixStream::connect(sock_path) {
        let msg = match launch_id {
            Some(id) => format!("LAUNCH:{}\n", id),
            None => "ACTIVATE\n".to_string(),
        };
        if stream.write_all(msg.as_bytes()).is_ok() {
            let _ = stream.flush();
            log::info!("[IPC] Sent command to running instance: {}", msg.trim());
            return true;
        }
    }
    false
}

/// Spawns the IPC Unix domain socket listener thread for the primary instance.
pub fn start_ipc_server(sock_path: PathBuf) {
    let _ = std::fs::remove_file(&sock_path);

    let listener = match UnixListener::bind(&sock_path) {
        Ok(l) => l,
        Err(e) => {
            log::warn!("[IPC] Failed to bind socket at {:?}: {}", sock_path, e);
            return;
        }
    };

    thread::spawn(move || {
        log::info!("[IPC] Listening on socket: {:?}", sock_path);
        for stream in listener.incoming() {
            match stream {
                Ok(stream) => {
                    let mut reader = BufReader::new(stream);
                    let mut line = String::new();
                    if reader.read_line(&mut line).is_ok() {
                        let trimmed = line.trim();
                        if trimmed.starts_with("LAUNCH:") {
                            let rom_id = trimmed.trim_start_matches("LAUNCH:").to_string();
                            log::info!("[IPC] Received remote launch request for ROM: {}", rom_id);
                            push_pending_launch(rom_id);
                        } else if trimmed == "ACTIVATE" {
                            log::info!("[IPC] Received activate request.");
                        }
                    }
                }
                Err(e) => {
                    log::warn!("[IPC] Socket error: {}", e);
                }
            }
        }
    });
}
