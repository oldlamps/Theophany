# User Guide

Detailed instructions for library management and media enrichment.

## Content Import

### File and Directory Scanning
- **Drag and Drop**: ROM files or directories can be dragged directly into the main interface to trigger the import scanner.
- **Manual Addition**: The "Add Content" button opens a file picker for specific titles.
- **Rules**: The scanner identifies content based on file extensions. Validated items appear in a preview dialog for library confirmation.

### Metadata Enrichment
- **Scraper Integration**: Use "Scrape Metadata" from the game context menu to query **IGDB** for rich game data. The following fields are mapped:
    - **Summary**: Game description and notes.
    - **Release Date**: Fetches the first available release year.
    - **Genres**: Categorization and tags.
    - **Developer & Publisher**: Studio and distribution attribution.
- **Asset Discovery**: Automated background scanning fetches:
    - **Cover Art**: High-resolution front box art.
    - **Screenshots**: Gameplay captures.
    - **Backgrounds**: Full-screen artwork and fanart.

### Video Management
- **Video Explorer**: Integrated search for trailers and gameplay videos; requires `yt-dlp` in the system path or a custom path in settings.
- **Playback**: Supports streaming and local downloads for offline library viewing.

## Library Organization

### Mass Editing
Multiple games can be updated simultaneously by selecting several entries in the list view. Shared fields like Developer, Publisher, and Playlists can be modified in bulk.

### Global Search
- **Trigger**: `Ctrl+F` or `Ctrl+Alt+F` for a dedicated search overlay.
- **Scope**: Performs real-time filtering across all platforms, including Steam, Epic, local ROMs, and eXoDOS libraries.

## Keyboard Shortcuts

| Category | Action | Shortcut |
| :--- | :--- | :--- |
| **Global** | Local Search | `Ctrl + F` |
| | Global Search (Island) | `Ctrl + Alt + F` |
| | Open Settings | `Ctrl + ,` |
| | Toggle Sidebar | `Ctrl + B` |
| | Toggle Filter Bar | `Ctrl + I` |
| | Refresh Library | `F5` |
| | Quit Application | `Ctrl + Q` |
| **Navigation** | Back / Forward | `Backspace` / `Alt + Right` |
| | Next / Prev Platform | `Ctrl + Tab` / `Ctrl + Shift + Tab` |
| | Jump to Start / End | `Home` / `End` |
| | Page Up / Down | `PgUp` / `PgDown` |
| | Next / Prev Letter | `Shift + PgDown` / `Shift + PgUp` |
| **Library** | Launch Selected Game | `Return` |
| | Edit Metadata | `E` |
| | Scrape (Manual / Auto) | `Shift + S` / `Shift + A` |
| | Update Achievements | `Shift + D` |
| | Open Image Viewer / Video Explorer | `I` / `V` |
| **Selection** | Select All | `Ctrl + A` |
| | Range Selection | `Shift + Arrow Keys` |
