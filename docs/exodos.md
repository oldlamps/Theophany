# eXoDOS Linux Integration

Technical guide for [eXoDOS Linux](https://www.retro-exo.com/linux.html) library integration.

## Importer Mechanics

The importer maps the external eXoDOS structure and its metadata to the internal database.

### Metadata Parsing
The scanner searches for the LaunchBox metadata file at `xml/all/MS-DOS.xml` relative to the eXoDOS root. It extracts:
- **Game Identity**: Titles and relative paths in the `!dos` directory.
- **Technical Info**: Developer, publisher, genre, and release year.
- **Context**: Comprehensive game notes and descriptions.
- **Metadata Sync**: Favorite status and play modes are mapped to internal tags.

### Artwork Mapping
The importer creates symbolic links for artwork, scanning the `Images/MS-DOS/` directory and mapping categories as follows:

| eXoDOS Category | Internal Subdirectory | Filename |
| :--- | :--- | :--- |
| `Box - Front` | `Box - Front` | `box_-_front.[ext]` |
| `Box - Back` | `Box - Back` | `box_-_back.[ext]` |
| `Box - 3D` | `Box - 3D` | `box_-_3d.[ext]` |
| `Screenshot - Gameplay` | `Screenshot` | `screenshot.[ext]` |
| `Screenshot - Game Title` | `Screenshot` | `screenshot.[ext]` |
| `Fanart - Background` | `Background` | `background.[ext]` |
| `Clear Logo` | `Logo` | `logo.[ext]` |

## Launching and Environments

- **Directory Structure**: The importer expects games in `eXo/eXoDOS/!dos`.
- **Process Management**: Launches `.command` files via terminal wrapping (e.g., `konsole`, `gnome-terminal`) to ensure accurate playtime tracking.
- **Configurations**: Existing DOSBox configurations and scripts are preserved and executed without modification.
