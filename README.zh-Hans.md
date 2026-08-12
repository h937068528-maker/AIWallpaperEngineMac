# AIWallpaperEngineMac

让你的 Mac 桌面，多一点属于自己的感觉。

**语言：** [English](README.md) | 简体中文

AIWallpaperEngineMac 是一款原生 macOS 动态壁纸应用。你可以把喜欢的视频、照片、GIF、Live Photo、网页场景或实时特效放到桌面上，让它在工作、学习和休息时安静地陪着你。

它关心的是每天真的会遇到的细节：多块屏幕可以各自不同、视频稳定循环、电池模式不拖累续航、设置不打扰使用。生成壁纸只是其中一个可选工具，而不是这款软件的全部。

## 主要能力

- 每块显示器独立壁纸会话，并支持显示器热插拔恢复。
- MP4/MOV 视频、GIF、Live Photo 和静态图片壁纸。
- 网页壁纸渲染与可配置在线壁纸目录。
- Metal Shader 与粒子壁纸基础能力。
- 电池、低电量、全屏场景和目标帧率的性能控制。
- 可选的本地音频与系统音频分析，用于音乐响应式特效。
- 可选 OpenAI 和火山引擎生图服务，密钥保存在 macOS 钥匙串中。

## 它能做什么

- **视频：** MP4、MOV 稳定循环播放。
- **图片：** 本地静态图片、GIF 和 Live Photo。
- **网页：** 本地或在线网页壁纸。
- **特效：** Metal Shader、粒子场景和音乐响应式效果。
- **在线壁纸：** 可选的视频和图片壁纸目录。
- **生成壁纸：** 可通过用户自行配置的服务，根据描述生成壁纸。

## 一起把它做完整

这不是一个只靠一个人就能做完的项目。如果你喜欢 macOS、视觉设计、Shader、媒体播放，或者只是对“理想的动态壁纸软件”有自己的想法，都欢迎加入。

- 在 GitHub Issues 分享问题、建议和真实使用场景。
- 通过 Pull Request 改善界面、翻译、性能或兼容性。
- 制作并分享壁纸包、Shader 和在线目录来源。
- 和大家一起，把 AIWallpaperEngineMac 做成更完整、更好用的 macOS 动态壁纸引擎。

请确保提交的内容尊重版权、来源清楚，也尊重用户隐私。

## 环境要求

- macOS 14 或更高版本
- Xcode 15 或更高版本
- 推荐 Apple Silicon 设备，以获得更好的 Metal 和视频性能。

## 从源码运行

1. 克隆本仓库。
2. 使用 Xcode 打开仓库内的工程文件。
3. 选择应用 Scheme，并在“我的 Mac”上运行。

编译后的应用为 `AIWallpaperEngineMac.app`。为了保持源码兼容，部分工程和 Target 内部标识仍保留上游名称；产品名称和用户界面统一使用 AIWallpaperEngineMac。项目保留 Objective-C++ 兼容层，新的界面与核心模块以 Swift 和 SwiftUI 实现。

## 系统权限

按启用的壁纸或效果不同，macOS 可能请求：

- **屏幕录制**：用于系统音频响应式特效。
- **辅助功能**：仅用于可选的高级桌面互动。

普通壁纸模式不会拦截桌面图标点击。

## 架构

```
UI（SwiftUI）
  -> Core（WallpaperEngine / WallpaperSession / Settings）
  -> Display（DisplayManager / ScreenController）
  -> Renderer（视频 / 图片 / GIF / Live Photo / 网页 / Metal / 粒子）
  -> macOS API（AppKit、AVFoundation、Metal、ScreenCaptureKit）
```

## 许可证与声明

本仓库采用 GNU General Public License v3.0 或更高版本，详见 [LICENSE](LICENSE)。

本项目基于 GPL 上游代码演进，保留相应的许可证与署名义务。第三方参考与组件声明见 [ThirdPartyNotices.md](ThirdPartyNotices.md)。

## 支持项目

如果它让你的桌面更合心意，欢迎通过以下方式支持后续开发。谢谢你的认可，它会让这个项目继续往前走。

<table>
  <tr>
    <td align="center"><strong>微信赞赏</strong><br><img src="asset/support/wechat-appreciation.jpg" width="220" alt="微信赞赏码"></td>
    <td align="center"><strong>支付宝</strong><br><img src="asset/support/alipay-appreciation.jpg" width="220" alt="支付宝收款码"></td>
    <td align="center"><strong>PayPal</strong><br><img src="asset/support/paypal-appreciation.jpg" width="220" alt="PayPal 收款码"></td>
  </tr>
</table>
