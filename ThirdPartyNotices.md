# Third-Party Notices

## AI Wallpaper workflow reference

The first-stage native AI wallpaper screen was informed by the product flow
demonstrated by:

- Project: all-in-aigc/aiwallpaper
- Repository: https://github.com/all-in-aigc/aiwallpaper
- Upstream license: Apache License 2.0

AIWallpaperEngineMac reimplements the description, generation, local history,
and download workflow using original Swift and SwiftUI code. No Next.js,
TypeScript, React, database, authentication, payment, AWS, or OpenAI client
source from the upstream project is copied, linked, adapted, or bundled.

The initial `DemoAIWallpaperProvider` is an original local procedural preview
generator. It does not call the upstream website, ChatGPT, or an external AI
API. Wallpaper generation providers can be added later behind
`AIWallpaperProvider`.

`OpenAIWallpaperProvider` and `OpenAIAPIKeyStore` are original Swift
implementations using Apple URLSession, AppKit, Security, and Keychain APIs.
No OpenAI SDK source is bundled. When explicitly selected by the user, the
provider communicates with `https://api.openai.com` using the user's separately
configured OpenAI Platform API key. OpenAI services and generated output remain
subject to OpenAI's applicable terms and policies.

`VolcengineWallpaperProvider`, `VolcengineAPIKeyStore`, and
`VolcengineConfigurationStore` are original Swift implementations using Apple
URLSession, AppKit, Security, and Keychain APIs. No Volcengine SDK source is
bundled. When explicitly selected by the user, the provider communicates with
`https://ark.cn-beijing.volces.com` using the user's separately configured Ark
API key and Seedream model or endpoint ID. Volcengine services and generated
output remain subject to Volcengine's applicable terms and policies.

## GPU particle wallpaper

The `ParticleRenderer`, `GestureInputRouter`, particle target generator, and
Metal compute/render shaders were written specifically for
AIWallpaperEngineMac. No third-party particle implementation or shader source
was copied or adapted.

## Web wallpaper reference

The native `WebRenderer` was informed by the product capabilities demonstrated
by:

- Project: NoisyWinds/Wallpaper
- Repository: https://github.com/NoisyWinds/Wallpaper
- Upstream license: Apache License 2.0

`WebRenderer` is an original macOS implementation using AppKit and WKWebView.
No Qt, C++, Windows WorkerW integration, mouse-hook code, HTML demos, or other
source files from the reference project are copied, linked, adapted, or
bundled. Local HTML/Three.js/WebGL content is supplied by the user; remote
content remains supplied by its respective website.

## yaml-cpp

This application includes yaml-cpp, which is distributed under the MIT
License. The complete license text is available in `vendor/yaml-cpp/LICENSE`
in the source distribution.

Copyright (c) 2008-2015 Jesse Beder.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

No GPL or AGPL third-party code was introduced by the GPU particle wallpaper
implementation.

## Music effect architecture reference

The local music-analysis architecture was informed by Wallnetic's published
audio visualizer design (MIT License, Copyright (c) 2024-2026 Fatih Kan):

- Project: fatihkan/wallnetic
- Repository: https://github.com/fatihkan/wallnetic

`MusicEffectEngine` is an original implementation using Apple's AVFoundation,
ScreenCaptureKit, and Accelerate/vDSP frameworks. No Wallnetic Swift source,
overlay UI, assets, or shaders are copied, linked, adapted, or bundled. The
engine analyzes user-selected local audio and, when explicitly enabled and
authorized by the user through macOS Screen Recording permission, system audio.

## Wallpaper Gallery catalog interoperability

The optional online catalog interoperates with the public data format and
media endpoints published by:

- Project: IT-NuanxinPro/wallpaper-gallery
- Repository: https://github.com/IT-NuanxinPro/wallpaper-gallery
- Inspected revision: 79f7e3ee3aa576e1741146050799b799282c5a9a

`WallpaperCatalogDecoder` is a native Swift reimplementation of the catalog's
documented `v1` Base64 character-mapping decoder. The upstream README declares
the project as MIT licensed. No Vue components, JavaScript bundles, Supabase
credentials, or wallpaper media files from the upstream project are bundled
with AIWallpaperEngineMac.

Online wallpaper media remains hosted and supplied by its third-party source.
Its copyright and redistribution terms are separate from the source-code
license and remain the responsibility of the media provider and user.

## Multi-source wallpaper providers

`WallpaperCatalogProvider`, `VideoCatalogProvider`, `StaticImageProvider`,
`BingWallpaperProvider`, `BingArchiveProvider`, `UserRepositoryProvider`,
`LocalFolderProvider`, and `ImageRenderer` were written specifically for
AIWallpaperEngineMac using Apple platform APIs.

## Bing historical wallpaper metadata

The optional Bing historical catalog reads public metadata on demand from:

- Project: niumoo/bing-wallpaper
- Repository: https://github.com/niumoo/bing-wallpaper
- Metadata endpoint: docs/images.json
- Upstream license: Apache License 2.0

`BingArchiveProvider` is an original Swift implementation. No Java source code
or build artifacts from the upstream repository are copied, linked, adapted,
or bundled with AIWallpaperEngineMac. The metadata is downloaded only when
the user opens this catalog.

Wallpaper image files remain hosted by Microsoft Bing. Image descriptions in
the catalog retain their source copyright information. The Apache-2.0 license
of the metadata project does not grant additional rights to the wallpaper
images themselves.

## ML4W authorized static wallpaper source

AIWallpaperEngineMac provides an optional online static-image catalog backed
by:

- Collection: ML4W Wallpaper Collection
- Maintainer: mylinuxforwork (Stephan Raabe)
- Repository: https://github.com/mylinuxforwork/wallpaper
- Accessed branch: main

The AIWallpaperEngineMac distributor has confirmed that direct permission was
obtained for commercial use of the collection's static images, including the
third-party rights represented in that collection. The confirmed scope
includes in-app display, user-initiated download, thumbnail generation,
resizing, and use as a macOS wallpaper.

No source code from the GPL-2.0 repository is copied, linked, or adapted.
AIWallpaperEngineMac's provider is an original Swift implementation using the
GitHub HTTPS API. Images are fetched from the upstream repository only when
the user selects this source and are not bundled in the installer.

Bing wallpaper metadata and images are fetched on demand from Microsoft Bing.
User-configured manifests, GitHub repositories, and their media remain
third-party content. Users are responsible for confirming that their selected
sources permit downloading and wallpaper use. Connecting a repository does not
incorporate its source-code license into AIWallpaperEngineMac, and the app does
not redistribute those repositories in its installer.
