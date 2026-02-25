# Configuration & Compatibility

Technical documentation for runtime environments and compatibility layer management.

## UMU (Universal Management Utility)

Execution management for Windows-based games is standardized via **UMU Core**. 
- **Legendary Integration**: For Epic Games Store titles, UMU is invoked as a wrapper (`--wrapper umu-run`) while bypassing Legendary's internal Wine management (`--no-wine`). This ensures consistent playtime tracking and prefix isolation.

## Compatibility Profiles

Games can be individually configured with specific compatibility parameters:
- **Runner Selection**: Detects and uses Proton or Wine versions from system paths (e.g., Steam's `compatibilitytools.d`).
- **Isolation**: Supports per-game custom Wine prefixes.
- **System Optimizations**: Optional integration with `gamemode` and environment variables (e.g., `DXVK_HUD`).

## Gamescope Configuration

Integrated support for the **Gamescope** micro-compositor allows for precise control over scaling and performance. The application assembles the command line using the following flags based on user input:

- **Internal Resolution**: Rendering width (`-w`) and height (`-h`).
- **Output Resolution**: Display output width (`-W`) and height (`-H`).
- **Framerate Limit**: Sets the target framerate limit (`-r`).
- **Scaling Filter**: Managed via `-S` (e.g., `integer`, `fit`, `fill`, `stretch`).
- **Upscaler Mode**: Support for various upscalers via `-U` (e.g., `fsr`, `nis`, `pixel`).
- **Fullscreen**: Toggle fullscreen mode via `-f`.

Additional parameters can be passed directly through the **Extra Args** field in the per-game or global settings.

## RetroAchievements

Provides integration with [RetroAchievements.org](https://retroachievements.org) for supported platforms:
- **Authentication**: Requires a valid username and API token (Web API Key) in the settings.
- **Visibility**: Toggle global achievement tracking and verify platform compatibility (e.g., RA is disabled for PC-native platforms).
- **Data Sync**: Automatically fetches badges and unlock status for supported system types.
