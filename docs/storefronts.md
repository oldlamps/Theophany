# Storefront Integration

Technical specifications for library syncing and storefront management.

## Epic Games Store (Legendary)

The launcher integrates with the **Legendary** CLI for Epic Games Store management.

### Authentication Flow
1. **Status Check**: Executes `legendary status` to verify credentials.
2. **Authorization**: If not logged in, `legendary auth` initiates the OAuth flow, providing a verification URL and token input.

### Library Syncing
- **Collection**: `legendary list-games --json` retrieves the user library.
- **Metadata**: Extracted from JSON output, including `keyImages` (box art, banners).
- **Cloud Saves**: Syncs using `legendary sync-saves --save-path`.

## Local Applications

The launcher identifies installed system-wide applications by scanning standard `.desktop` files.

### Scanning Paths
- **System**: `/usr/share/applications`, `/usr/local/share/applications`
- **User**: `~/.local/share/applications`

## Flatpak & Flathub

Native integration with the Flathub ecosystem for app discovery and management.

### App Discovery
- **Flathub API**: Uses Flathub API v2 (`/api/v2/search`, `/api/v2/appstream/`) to fetch featured content, search results, and detailed app metadata.

### Installation & Media
- **Installation**: Executed via `flatpak install --user -y --noninteractive`.
- **Media Caching**: Icons and screenshots are cached locally in `~/.local/share/theophany/Images/PC (Linux)/{AppId}/`.

## Heroic Games Launcher

Scans Heroic config directories (`~/.config/heroic` or the Flatpak equivalent) to sync Epic, GOG, and Amazon Game Studios libraries.
- **Data Source**: Parses `installed.json`, `gog_store/installed.json`, and `amazon_store/installed.json`.
- **Playtime**: Synchronizes playtime and last-played timestamps from `store/timestamp.json`.
- **Media**: Resolves local icons from Heroic's `icons/` cache.

## Lutris

- **Integration**: Scans the Lutris PostgreSQL-compatible SQLite database (`pga.db`) found in `~/.local/share/lutris/`.
- **Execution**: Games are launched using the `lutris:` URI scheme, respecting Lutris-managed runners and configurations.

## Steam Integration

- **Sync Logic**: Scans `libraryfolders.vdf` and `appmanifest_*.acf` files across all detected Steam library roots.
- **Web API**: Optionally uses the Steam Web API (`GetOwnedGames`, `GetSchemaForGame`) for achievements and playtime synchronization.
