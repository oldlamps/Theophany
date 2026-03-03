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
            
            // We keep legendary sandboxed. If it's our internal tool, it's already in the sandbox.
            // If it's a system utility, the final wrapping logic below will handle it if it's in /usr/bin etc.
            
            let mut extra_args = String::new();
            
            // Handle host-escape for wrapper if needed (only if it's a known host utility)
            let final_wrapper = match wrapper {
                Some(w) if !w.trim().is_empty() => {
                    let w_trimmed = w.trim();
                    if is_flatpak && (w_trimmed == "umu-run" || w_trimmed == "gamescope" || w_trimmed == "mangohud") {
                        format!("flatpak-spawn --host {}", w_trimmed)
                    } else {
                        w_trimmed.to_string()
                    }
                },
                _ => String::new(),
            };

            let wrapper_arg = if !final_wrapper.is_empty() {
                extra_args.push_str(" --no-wine");
                format!(" --wrapper \"{}\"", final_wrapper)
            } else {
                String::new()
            };
                
            let overlay_arg = if eos_overlay { " --eos-overlay" } else { "" };
            
            // Ensure sandboxed config path is passed
            let config_dir = crate::core::paths::get_config_dir().join("legendary");
            let config_env = format!("LEGENDARY_CONFIG_PATH=\"{}\" ", config_dir.to_string_lossy());
            
            let launch_cmd = format!("{}{}{} launch \"{}\"{}{}{}", config_env, binary, if binary.ends_with(" ") { "" } else { " " }, app_id, wrapper_arg, extra_args, overlay_arg);
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
            
            // If already escaped, don't double escape
            if trimmed.starts_with("flatpak-spawn") {
                trimmed.to_string()
            } else {
                // Find the actual command by skipping leading environment variables (KEY=VALUE)
                let parts: Vec<&str> = trimmed.split_whitespace().collect();
                let mut actual_cmd = None;
                for part in &parts {
                    if !part.contains('=') {
                        actual_cmd = Some(*part);
                        break;
                    }
                }

                let is_host_targeted = if let Some(cmd) = actual_cmd {
                    // Strip quotes if any (e.g. "/usr/bin/foo")
                    let clean_cmd = cmd.trim_matches('"').trim_matches('\'');
                    
                    clean_cmd.starts_with("/usr/") || 
                    clean_cmd.starts_with("/bin/") || 
                    clean_cmd.starts_with("/sbin/") || 
                    clean_cmd.starts_with("/opt/") || 
                    clean_cmd == "xdg-open" || 
                    clean_cmd == "flatpak" ||
                    clean_cmd == "umu-run" ||
                    clean_cmd == "gamescope" ||
                    clean_cmd == "mangohud"
                } else {
                    false
                };
                
                if is_host_targeted {
                    // If the command contains environment variables (KEY=VALUE), prepend 'env'
                    // so flatpak-spawn --host can execute it correctly.
                    let final_host_cmd = if trimmed.contains('=') && !trimmed.starts_with("env ") && !trimmed.starts_with("/usr/bin/env ") {
                        format!("env {}", trimmed)
                    } else {
                        trimmed.to_string()
                    };
                    format!("flatpak-spawn --host {}", final_host_cmd)
                } else {
                    trimmed.to_string()
                }
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
