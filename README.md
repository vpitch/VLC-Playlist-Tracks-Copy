# VLC Playlist Tracks Copy

A VLC Lua extension for macOS that copies all local media files from the current playlist into a selected folder.

## Features

- Copies local `file://` playlist items
- Skips network streams (http, https, rtsp, etc.)
- Preserves original filenames
- Does not overwrite existing files
- Generates a `copy_log.txt` file in the destination folder

## Installation (macOS)

1. Create the extensions directory if it does not exist:

   `~/Library/Application Support/org.videolan.vlc/lua/extensions/`

2. Copy the `.lua` extension file into that folder.

3. Quit VLC completely (⌘Q) and reopen it.

## Usage

1. Open VLC.
2. Load your playlist.
3. Launch the extension.
4. Select a destination folder.
5. Click **Copy**.

## Requirements

- VLC 3.x or later
- macOS

## License

MIT License — see the LICENSE file for details.