use std::process::Command;
#[cfg(unix)]
use std::os::unix::process::CommandExt;

pub struct Launcher;

impl Launcher {
    pub fn launch(command_template: &str, rom_path: &str, mut working_dir: Option<&str>, _env_vars: Option<&str>, wrapper: Option<&str>, eos_overlay: bool, track: bool) -> Result<std::process::Child, String> {
        if command_template.trim().is_empty() {
            return Err("Command template is empty.".to_string());
        }

        // 1. Working Directory logic
        if rom_path.starts_with("steam://") || rom_path.starts_with("flatpak://") || rom_path.starts_with("heroic://") || rom_path.starts_with("lutris:") {
            working_dir = None;
        }

        let is_flatpak = std::path::Path::new("/.flatpak-info").exists();
        
        // 2. Base Command Construction
        let mut cmd_string = if rom_path.starts_with("flatpak://") {
            let app_id = &rom_path[10..];
            let flatpak_run = if is_flatpak { "flatpak-spawn --host flatpak run" } else { "flatpak run" };
            format!("{} \"{}\"", flatpak_run, app_id)
        } else if rom_path.starts_with("steam://") || rom_path.starts_with("heroic://") || rom_path.starts_with("lutris:") {
            let xdg_cmd = if is_flatpak { "flatpak-spawn --host xdg-open" } else { "xdg-open" };
            format!("{} \"{}\"", xdg_cmd, rom_path)
        } else if rom_path.starts_with("epic://") {
            let app_id = rom_path.split('/').last().unwrap_or(rom_path);
            let binary = crate::core::legendary::LegendaryWrapper::find_binary()
                .map(|p| p.to_string_lossy().to_string())
                .unwrap_or_else(|| "legendary".to_string());
            
            let mut extra_args = String::new();
            let wrapper_arg = if let Some(w) = wrapper {
                if !w.trim().is_empty() {
                    extra_args.push_str(" --no-wine");
                    format!(" --wrapper \"{}\"", w.trim())
                } else { String::new() }
            } else { String::new() };
                
            let overlay_arg = if eos_overlay { " --eos-overlay" } else { "" };
            let config_dir = crate::core::paths::get_config_dir().join("legendary");
            
            // For Legendary, we always want environmental stability
            format!("LEGENDARY_CONFIG_PATH=\"{}\" {} launch \"{}\"{}{}{}", 
                config_dir.to_string_lossy(), binary, app_id, wrapper_arg, extra_args, overlay_arg)
        } else if rom_path.ends_with(".desktop") {
            Self::parse_desktop_exec(rom_path).unwrap_or_else(|| format!("xdg-open \"{}\"", rom_path))
        } else if rom_path.ends_with(".command") {
            Self::find_terminal_wrapped_cmd(rom_path).unwrap_or_else(|| format!("bash \"{}\"", rom_path))
        } else {
            format!("\"{}\"", rom_path)
        };

        // Apply command template if it contains %ROM%
        if command_template.contains("%ROM%") {
            cmd_string = command_template.replace("%ROM%", &cmd_string);
        }

        // 3. Final Command String with Optional Tracking
        let final_cmd = if track {
            // Simplified marker wrapping
            let escaped_cmd = cmd_string.replace("'", "'\\''");
            if is_flatpak && !cmd_string.starts_with("flatpak-spawn") {
                format!("flatpak-spawn --host sh -c 'printf \"THEOPHANY_PGID:%s\\n\" \"$(ps -o pgid= -p $$)\"; exec env {}'", escaped_cmd)
            } else {
                format!("sh -c 'printf \"THEOPHANY_PGID:%s\\n\" \"$(ps -o pgid= -p $$)\"; exec env {}'", escaped_cmd)
            }
        } else {
            // No tracking: just ensure host escape if needed
            if is_flatpak && !cmd_string.starts_with("flatpak-spawn") {
                format!("flatpak-spawn --host sh -c 'exec env {}'", cmd_string.replace("'", "'\\''"))
            } else {
                cmd_string
            }
        };

        log::info!("[Launcher] Simplified final command: {}", final_cmd);

        let mut cmd = Command::new("sh");
        cmd.arg("-c").arg(final_cmd.as_str());
        cmd.stdin(std::process::Stdio::null());
        
        if track {
            cmd.stdout(std::process::Stdio::piped());
            cmd.stderr(std::process::Stdio::piped());
        }

        #[cfg(unix)]
        {
            cmd.process_group(0);
        }

        // Only set current_dir if not spawning on host via flatpak-spawn
        if !final_cmd.starts_with("flatpak-spawn") {
            if let Some(wd) = working_dir {
                if !wd.is_empty() && std::path::Path::new(wd).exists() {
                    cmd.current_dir(wd);
                }
            }
        }

        log::info!("[Launcher] Final command spawned: {}", final_cmd);
        cmd.spawn().map_err(|e| format!("Failed to spawn process: {}", e))
    }

    fn parse_desktop_exec(path: &str) -> Option<String> {
        let content = std::fs::read_to_string(path).ok()?;
        for line in content.lines() {
            if line.starts_with("Exec=") {
                let exec = line[5..].to_string();
                // Strip placeholders
                let cleaned = exec
                    .replace("%f", "")
                    .replace("%F", "")
                    .replace("%u", "")
                    .replace("%U", "")
                    .replace("%i", "")
                    .replace("%c", "")
                    .replace("%k", "")
                    .trim()
                    .to_string();
                return Some(cleaned);
            }
        }
        None
    }

    fn find_terminal_wrapped_cmd(rom_path: &str) -> Option<String> {
        let terminals = [
            ("konsole", "-e"),
            ("gnome-terminal", "--"),
            ("xfce4-terminal", "-x"),
            ("kgx", "-e"),
            ("xterm", "-e"),
            ("mate-terminal", "-e"),
            ("terminator", "-x"),
            ("foot", "-e"),
            ("kitty", "-e"),
            ("urxvt", "-e"),
            ("rxvt", "-e"),
            ("termit", "-e"),
            ("terminology", "-e"),
            ("aterm", "-e"),
            ("uxterm", "-e"),
            ("eterm", "-e"),
        ];

        let is_flatpak = std::path::Path::new("/.flatpak-info").exists();
        
        for (term, arg) in terminals {
            let exists = if is_flatpak {
                std::process::Command::new("flatpak-spawn")
                    .arg("--host")
                    .arg("which")
                    .arg(term)
                    .stderr(std::process::Stdio::null()) // Silence stderr for 'which'
                    .output()
                    .map(|o| o.status.success())
                    .unwrap_or(false)
            } else {
                which::which(term).is_ok()
            };
            
            if exists {
              
                // This allows Theophany to track the terminal process itself.
                return Some(format!("{} {} /bin/bash \"{}\"", term, arg, rom_path));
            }
        }
        None
    }
}
