# VLC-Playlist-Tracks-Copy
A VLC Lua extension for macOS that copies all local tracks from the current playlist into a chosen folder.
=======
# VLC Playlist Copy (Lua Extension)

A VLC Lua extension for macOS that copies all local media files from the current VLC playlist into a folder you choose.

## Features

- Copies local `file://` items from the current playlist
- Skips network streams (http/https/rtsp)
- Preserves original filenames
- Does not overwrite existing files
- Writes a `copy_log.txt` file into the destination folder

## Installation (macOS)

1. Create the extensions folder if it does not exist:

   `~/Library/Application Support/org.videolan.vlc/lua/extensions/`

2. Copy the `.lua` file into that folder.

3. Quit VLC completely (⌘Q) and reopen it.

## Usage

1. Open VLC and load your playlist.
2. Run the extension.
3. Choose a destination folder.
4. Click "Copy".

## License

MIT — see LICENSE file.
>>>>>>> 76e3215 (Initial release)
