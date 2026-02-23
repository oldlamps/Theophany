<p align="center">
  <img width="128" height="128" alt="tray_icon" src="https://github.com/user-attachments/assets/9df6d5ca-9b01-449e-88da-a2b41bf8c280" />
  <br>
  <img alt="theophany_logo" src="https://github.com/user-attachments/assets/125ac4aa-34ca-4e23-b834-9a6b37607692" />
</p>

<p align="center">
  <strong>A modern game library manager and launcher built with Rust and Qt/QML.</strong>
  <br>
  Theophany is a desktop client for managing and launching game collections on Linux.
</p>

<p align="center">
  <img width="800" height="429" alt="hero" src="https://github.com/user-attachments/assets/dc0535d1-1282-4a35-8468-07ebea687402" />

</p>

## Features

### ⬢ All your ROMs in One Place
- Support for dozens of consoles out of the box, just drag and drop your individual ROMs or ROM folder to start importing.
  
### ⬢ Media & Metadata
- **IGDB Integration**: Pull box art, backgrounds, and game data (developers, release dates, etc.) from IGDB.
- **Video Explorer**: Search, stream, or download game trailers and clips using `yt-dlp`.
- **Search & Filter**: Floating search bar for games and collections, with filters for genre, year, and rating.

---

### ⬢ Storefront & System Bridges
- **Storefront Sync**: Comprehensive integration for **Steam**, **Heroic**, and **Lutris**.
  - **Steam**: Full cloud library import (installed & uninstalled), achievement tracking, and playtime sync.
  - **Heroic/Lutris**: Sync installed games and playtime data.
- **Flatpak Integration**: Manage and install Flatpak apps directly within the interface.

---

### ⬢ Linux & Proton Integration
- **UMU Core**: Launcher based on the Universal Management Utility for Proton and Wine management.
- **Runtime Environment**: Set specific Proton versions, Wine paths, and prefixes per game.
- **Full configuration**: set wrappers, env variable, gamesscope settings and more with per game profiles.

---

### ⬢ RetroAchievements Integration
- **Dashboard**: Profile pane showing account rank, points, and gaming history.
- **Progress Tracking**: Achievement progress bars and badge tracking for supported titles.
- **Status & Art**: Rich presence tracking and automatic fetching of game icons, box art, and metadata.

---

### ⬢ Library Management
- **Themes**: Includes 15+ color palettes (Nord, Dracula, Tokyo Night, etc.) for UI customization.
- **Mass Edit**: Update metadata fields for multiple games simultaneously.
- **Resource Manager**: Add external links for manuals, wikis, and strategy guides.
- **Playlists**: Create manual groups to organize collections and series.

---

### ⬢ Coming Soon
- **Cloud Library Import**: Expand full library views to **Epic Games Store** and **GOG**.
- **Advanced Playlists**: Automated grouping based on dynamic filters.
- **Feature Requests Encouraged!**

---

## Getting Started

### Prerequisites

- **Rust**: [Install Rust](https://www.rust-lang.org/tools/install) (2021 edition).
- **Qt 6.2+**: Required for the QML frontend.
- **PROTOC**: Protocol Buffers compiler for internal API layers.
- **yt-dlp**: Required for video fetching.
- **Ollama** (Optional): For local metadata synthesis.

### Installation & Running

1. Clone the repository:
   ```bash
   git clone https://github.com/oldlamps/theophany.git
   cd theophany
   ```

2. Run the application:
   ```bash
   cargo run
   ```

3. Release Build:
   ```bash
   ./build_release.sh
   ```

## License

GNU General Public License v3.0
