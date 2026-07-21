# System permissions and runtime requirements

## Login at startup

AIWallpaperEngineMac uses `SMAppService.mainApp` to register the application as
a macOS login item. macOS may report `requiresApproval`; in that case the user
must enable the app under **System Settings > General > Login Items**.

The app no longer calls the deprecated `SMLoginItemSetEnabled` API.

## Accessibility

The current SwiftUI and AVFoundation implementation does not require
Accessibility permission. Foreground-app detection uses `NSWorkspace`, and the
app does not inspect other applications' UI or synthesize keyboard/mouse input.

## Apple Events and screen recording

The application does not automate other apps with Apple Events and does not
capture the screen, so it does not declare Apple Events or Screen Recording
usage descriptions.

## Wallpaper folders

Wallpaper directories are selected explicitly by the user through `NSOpenPanel`.
The application runs without App Sandbox in the current compatibility phase so
the existing Objective-C++ engine and daemon keep access to the selected files.
Sandboxing and security-scoped bookmarks should be introduced together in a
later packaging phase.

## MP4 and Apple Silicon

MP4 playback uses `AVQueuePlayer`, `AVPlayerLooper`, and `AVPlayerLayer`.
AVFoundation automatically selects Apple Silicon hardware decoding when the
source codec and pixel format are supported by the operating system.

Recommended commercial wallpaper assets:

- MP4 container with H.264 or HEVC video
- 8-bit 4:2:0 pixel format for widest hardware-decoder compatibility
- display-native resolution where practical
- 30 or 60 fps, with audio omitted when it is not needed

Debug and Release products must be checked with `file` or `lipo -archs` to make
sure both the app executable and bundled `wallpaperdaemon` contain native
`arm64` slices on Apple Silicon.
