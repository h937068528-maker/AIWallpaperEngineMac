# AIWallpaperEngineMac

Give your Mac desktop a little more character.

**Languages:** English | [简体中文](README.zh-Hans.md)

AIWallpaperEngineMac is a native macOS wallpaper app for people who want their
desktop to feel a little more like their own. Pick a favorite video, photo,
GIF, Live Photo, web scene, or live effect, then let it quietly stay with you
while you work, study, or take a break.

It is built around the practical details that matter: separate wallpapers for
multiple displays, stable playback, sensible battery behavior, and controls
that do not get in your way. Image generation is an optional tool—not the
whole story.

## Highlights

- Per-display wallpaper sessions, including display hot-plug recovery.
- MP4/MOV video, GIF, Live Photo, and static-image renderers.
- Web wallpaper renderer and configurable online wallpaper catalogs.
- Metal shader and particle wallpaper foundation.
- Performance controls for battery, low-power, fullscreen, and target FPS modes.
- Optional local and system-audio analysis for music-reactive visual effects.
- Optional OpenAI and Volcengine image-generation providers; API keys stay in the macOS Keychain.

## What it can do

- **Video:** MP4 and MOV playback with stable looping.
- **Images:** local images, GIF, and Live Photos.
- **Web:** local or remote web wallpapers.
- **Effects:** Metal shaders, particle scenes, and music-reactive effects.
- **Online catalogs:** optional video and image wallpaper sources.
- **Generation:** optional prompt-based wallpaper generation through a provider configured by the user.

## Help build it

This project is not meant to be finished by one person alone. If you enjoy
macOS, visual design, shaders, media playback, or simply have a good idea for
how a desktop wallpaper app should feel, you are welcome here.

- Share bugs, ideas, and wallpaper-use cases through GitHub Issues.
- Improve the interface, translations, performance, or compatibility through Pull Requests.
- Build and share wallpaper packages, shaders, and catalog providers.
- Help shape AIWallpaperEngineMac into a complete, community-made macOS wallpaper engine.

Please keep contributions respectful, original or properly licensed, and
friendly to users' privacy.

## Requirements

- macOS 14 or later
- Xcode 15 or later
- Apple Silicon is recommended for Metal and video performance.

## Build from source

1. Clone this repository.
2. Open the included Xcode project.
3. Select the application scheme and run it on **My Mac**.

The application product is `AIWallpaperEngineMac.app`. Some internal project
and target identifiers retain their upstream names for source compatibility;
the product name and user-facing interface use AIWallpaperEngineMac. The
project includes an Objective-C++ compatibility layer while the new UI and
engine modules are implemented in Swift and SwiftUI.

## Permissions

Depending on the wallpaper and enabled effects, macOS may request:

- **Screen Recording** for system-audio reactive effects.
- **Accessibility** only for optional advanced desktop interaction.

The normal wallpaper mode does not intercept desktop icon clicks.

## Architecture

```
UI (SwiftUI)
  -> Core (WallpaperEngine / WallpaperSession / Settings)
  -> Display (DisplayManager / ScreenController)
  -> Renderer (Video / Image / GIF / Live Photo / Web / Metal / Particle)
  -> macOS APIs (AppKit, AVFoundation, Metal, ScreenCaptureKit)
```

## License and notices

This repository is licensed under the GNU General Public License v3.0 or later. See [LICENSE](LICENSE).

The project is derived from GPL-licensed upstream work and keeps the required license and attribution obligations. Third-party reference and component notices are in [ThirdPartyNotices.md](ThirdPartyNotices.md).

## Support the project

If the app makes your desktop feel more like yours, WeChat appreciation can
support continued development. Thank you for helping keep the project moving.

<table>
  <tr>
    <td align="center"><strong>WeChat</strong><br><img src="asset/support/wechat-appreciation.jpg" width="220" alt="WeChat appreciation QR code"></td>
    <td align="center"><strong>Alipay</strong><br><img src="asset/support/alipay-appreciation.jpg" width="220" alt="Alipay appreciation QR code"></td>
    <td align="center"><strong>PayPal</strong><br><img src="asset/support/paypal-appreciation.jpg" width="220" alt="PayPal appreciation QR code"></td>
  </tr>
</table>
