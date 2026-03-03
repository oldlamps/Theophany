use std::process::Command;

pub struct Launcher;

impl Launcher {
    pub fn launch(command_template: &str, rom_path: &str, mut working_dir: Option<&str>, env_vars: Option<&str>, wrapper: Option<&str>, eos_overlay: bool) -> Result<std::process::Child, String> {
        if command_template.trim().is_empty() {
            return Err("Command template is empty.".to_string());
        }

        // 1. Correct Working Directory for URIs
        if rom_path.starts_with("steam://") || rom_path.starts_with("flatpak://") || rom_path.starts_with("heroic://") || rom_path.starts_with("lutris:") {
            working_dir = None;
        }

        let is_flatpak = std::path::Path::new("/.flatpak-info").exists();
        
        // 2. Construct Command String
        let cmd_string = if rom_path.starts_with("flatpak://") {
            let app_id = &rom_path[10..];
            let flatpak_run = if is_flatpak { "flatpak-spawn --host flatpak run" } else { "flatpak run" };
            let launch_cmd = if command_template.contains("flatpak run") {
                // If template already has flatpak run, we just need to ensure host prefix if sandboxed
                if is_flatpak && !command_template.contains("flatpak-spawn") {
                    command_template.replace("flatpak run", "flatpak-spawn --host flatpak run")
                } else {
                    command_template.to_string()
                }
            } else {
                format!("{} \"{}\"", flatpak_run, app_id)
            };

            if launch_cmd.contains("%ROM%") {
                launch_cmd.replace("%ROM%", &format!("\"{}\"", app_id))
            } else {
                launch_cmd
            }
        } else if rom_path.starts_with("steam://") || rom_path.starts_with("heroic://") || rom_path.starts_with("lutris:") {
            let xdg_cmd = if is_flatpak { "flatpak-spawn --host xdg-open" } else { "xdg-open" };
            let launch_cmd = format!("{} \"{}\"", xdg_cmd, rom_path);
            if command_template.contains("%ROM%") {
                command_template.replace("%ROM%", &launch_cmd)
            } else {
                launch_cmd
            }
        } else if rom_path.starts_with("epic://") {
            let app_id = rom_path.split('/').last().unwrap_or(rom_path);
            let binary = crate::core::legendary::LegendaryWrapper::find_binary()
                .map(|p| p.to_string_lossy().to_string())
                .unwrap_or_else(|| "legendary".to_string());
            
            // Legendary in Flatpak is usually 'flatpak-spawn --host legendary' if using host binary, 
            // but we might be using an internal one. LegendaryWrapper::find_binary should handle it.
            // If it's a host path like /usr/bin/legendary, and we are in flatpak, we need prefix.
            let binary = if is_flatpak && binary.starts_with('/') {
                format!("flatpak-spawn --host {}", binary)
            } else {
                binary
            };
                
            let mut extra_args = String::new();
            let wrapper_arg = match wrapper {
                Some(w) if !w.trim().is_empty() => {
                    // When using a wrapper (like umu-run), we usually want legendary 
                    // to not prepend 'wine' itself, as the wrapper handles it.
                    extra_args.push_str(" --no-wine");
                    format!(" --wrapper \"{}\"", w.trim())
                },
                _ => String::new(),
            };
                
            let overlay_arg = if eos_overlay { " --eos-overlay" } else { "" };
            let launch_cmd = format!("{} launch \"{}\"{}{}{}", binary, app_id, wrapper_arg, extra_args, overlay_arg);
            if command_template.contains("%ROM%") {
                command_template.replace("%ROM%", &launch_cmd)
            } else {
                launch_cmd
            }
        } else if rom_path.ends_with(".desktop") {
            // Parse desktop file for direct execution
            if let Some(exec) = Self::parse_desktop_exec(rom_path) {
                command_template.replace("%ROM%", &exec)
            } else {
                command_template.replace("%ROM%", &format!("xdg-open \"{}\"", rom_path))
            }
        } else if rom_path.ends_with(".command") {
            let cmd = if let Some(wrapped) = Self::find_terminal_wrapped_cmd(rom_path) {
                wrapped
            } else {
                format!("bash \"{}\"", rom_path)
            };
            
            if is_flatpak && !cmd.starts_with("flatpak-spawn") {
                command_template.replace("%ROM%", &format!("flatpak-spawn --host {}", cmd))
            } else {
                command_template.replace("%ROM%", &cmd)
            }
        } else {
            let quoted_path = format!("\"{}\"", rom_path);
            command_template.replace("%ROM%", &quoted_path)
        };

        // 3. Final Command Wrapping for Sandbox Escape
        let final_cmd_string = if is_flatpak {
            let trimmed = cmd_string.trim();
            let is_host_targeted = trimmed.starts_with("/usr/") || trimmed.starts_with("/bin/") || trimmed.starts_with("/sbin/") || trimmed.starts_with("/opt/") || trimmed.starts_with("xdg-open") || trimmed.starts_with("flatpak run");
            
            if is_host_targeted && !trimmed.starts_with("flatpak-spawn") {
                format!("flatpak-spawn --host {}", trimmed)
            } else {
                trimmed.to_string()
            }
        } else {
            cmd_string
        };

        let mut cmd = Command::new("sh");
        cmd.arg("-c").arg(&final_cmd_string);

        // Only set working directory if it's likely accessible (not spawning on host)
        if !final_cmd_string.starts_with("flatpak-spawn") {
            if let Some(wd) = working_dir {
                if !wd.is_empty() && std::path::Path::new(wd).exists() {
                    cmd.current_dir(wd);
                }
            }
        }

        log::info!("[Launcher] Final command: {}", final_cmd_string);
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
            ("tilix", "-e"),
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
                    .output()
                    .map(|o| o.status.success())
                    .unwrap_or(false)
            } else {
                which::which(term).is_ok()
            };
            
            if exists {
                // By launching via a terminal emulator that ExoDOS recognizes,
                // the .command script will source the .bsh logic in the current window
                // INSTEAD of spawning its own backgrounded terminal.
                // This allows Theophany to track the terminal process itself.
                return Some(format!("{} {} /bin/bash \"{}\"", term, arg, rom_path));
            }
        }
        None
    }
}
