use std::process::Command;
#[cfg(unix)]
use std::os::unix::process::CommandExt;

pub struct Launcher;

impl Launcher {
    pub fn launch(command_template: &str, rom_path: &str, mut working_dir: Option<&str>, env_vars: Option<&str>, wrapper: Option<&str>, eos_overlay: bool, track: bool) -> Result<std::process::Child, String> {
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
            let binary_path = crate::core::legendary::LegendaryWrapper::find_binary();
            let binary = binary_path
                .as_ref()
                .map(|p| p.to_string_lossy().to_string())
                .unwrap_or_else(|| "legendary".to_string());
            


            let mut extra_args = String::new();
            let wrapper_arg = if let Some(w) = wrapper {
                if !w.trim().is_empty() {
                    extra_args.push_str(" --no-wine");
                    if is_flatpak {
                        let tools_dir = crate::core::paths::get_tools_dir();
                        let wrapper_path = tools_dir.join("wrapper.sh");
                        
                        let mut env_exports = String::new();
                        if let Some(e) = env_vars {
                            let mut current_var = String::new();
                            let mut in_quotes = false;
                            
                            for c in e.chars() {
                                match c {
                                    '"' => {
                                        in_quotes = !in_quotes;
                                        current_var.push(c);
                                    }
                                    ' ' if !in_quotes => {
                                        if !current_var.is_empty() {
                                            env_exports.push_str(&format!("export {}\n", current_var));
                                            current_var.clear();
                                        }
                                    }
                                    _ => {
                                        current_var.push(c);
                                    }
                                }
                            }
                            if !current_var.is_empty() {
                                env_exports.push_str(&format!("export {}\n", current_var));
                            }
                        }

                        let script_content = format!(
                            "#!/bin/sh\n\
                            {}\n\
                            printf \"THEOPHANY_HOST_PGID:%s\\n\" \"$(ps -o pgid= -p $$)\"\n\
                            exec {} \"$@\"\n",
                            env_exports,
                            w.trim()
                        );

                        if let Err(e) = std::fs::write(&wrapper_path, &script_content) {
                            log::error!("[Launcher] Failed to write Flatpak wrapper script: {}", e);
                        } else {
                            log::debug!("[Launcher] Generated wrapper script at {:?}:\n{}", wrapper_path, script_content);
                        }
                        
                        // Make sure to chmod +x just in case
                        #[cfg(unix)]
                        {
                            use std::os::unix::fs::PermissionsExt;
                            if let Ok(mut perms) = std::fs::metadata(&wrapper_path).map(|m| m.permissions()) {
                                perms.set_mode(0o755);
                                let _ = std::fs::set_permissions(&wrapper_path, perms);
                            }
                        }

                        format!(" --wrapper \"flatpak-spawn --host sh {}\"", wrapper_path.to_string_lossy())
                    } else {
                        let wrapper_env_prefix = match env_vars {
                            Some(e) if !e.trim().is_empty() => format!("env {} ", e.trim().replace("\"", "\\\"")),
                            _ => String::new(),
                        };
                        format!(" --wrapper \"{}{}\"", wrapper_env_prefix, w.trim())
                    }
                } else { String::new() }
            } else { String::new() };
                
            let overlay_arg = if eos_overlay { " --eos-overlay" } else { "" };
            
            let config_dir = crate::core::paths::get_config_dir().join("legendary");
            let config_env = format!("LEGENDARY_CONFIG_PATH=\"{}\"", config_dir.to_string_lossy());
            
            // Use `env VAR=val binary ...` — the Flatpak runtime's sh doesn't support
            // inline env assignments with exec, which would try to run the assignment as a path.
            format!("env {} {} launch \"{}\"{}{}{}", 
                config_env, binary, app_id, wrapper_arg, extra_args, overlay_arg)
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
        // For epic:// games, legendary runs inside the sandbox. The wrapper (e.g. umu-run)
        // already handles host-escaping via flatpak-spawn --host internally.
        // We should NOT wrap the whole command in flatpak-spawn --host again.
        let is_epic = rom_path.starts_with("epic://");
        let final_cmd = if track {
            let escaped_cmd = cmd_string.replace("'", "'\\''");
            if is_flatpak && is_epic {
                // Legendary runs inside sandbox; wrapper already escaped to host.
                // Use a local PGID marker so we track the legendary process group.
                format!("sh -c 'printf \"THEOPHANY_PGID:%s\\n\" \"$(ps -o pgid= -p $$)\"; exec {}'", escaped_cmd)
            } else if is_flatpak && !cmd_string.starts_with("flatpak-spawn") {
                // Other non-epic commands (e.g. native PC games) need host escape.
                format!("flatpak-spawn --host sh -c 'printf \"THEOPHANY_HOST_PGID:%s\\n\" \"$(ps -o pgid= -p $$)\"; exec env {}'", escaped_cmd)
            } else {
                format!("sh -c 'printf \"THEOPHANY_PGID:%s\\n\" \"$(ps -o pgid= -p $$)\"; exec env {}'", escaped_cmd)
            }
        } else {
            // No tracking: just ensure host escape if needed (not for epic)
            if is_flatpak && !is_epic && !cmd_string.starts_with("flatpak-spawn") {
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
