# iShot / iShot Pro 功能覆盖基线

资料来源：

- iShot 产品页：https://www.better365.cn/ishot.html
- iShot / iShot Pro 区别页：https://www.better365.cn/ishot/difference.html

## 覆盖目标

iShot 页面列出的核心能力包括：截图、长截图、多窗口截图、全屏带壳截图、延时截图、标注、贴图、取色、录屏、录音、OCR、截图翻译、圆角与阴影、快速打开到指定 App。

iShot Pro 差异页说明 Pro 版本本质是解锁全部高级功能：录屏/录音时录制系统内部声音、OCR、全屏带壳截图和长截图取消水印、贴图功能。当前项目不做水印限制，因此按完整功能版覆盖。

## 当前实现状态

| 功能 | 当前状态 | 实现位置 | 备注 |
| --- | --- | --- | --- |
| 全屏截图 | 已实现 | `CaptureManager.captureScreenshot()` | 基于 ScreenCaptureKit |
| 窗口截图 | 已实现 | `CaptureManager.captureScreenshot()` | 依赖窗口选择 |
| 区域截图 | 已实现 | `captureRegionScreenshot()` | 调用 macOS `screencapture -i -r` |
| 延时截图 | 已实现 | `captureDelayedScreenshot()` | 秒数可在设置中配置 |
| 长截图 | 已实现基础版 | `captureScrollingWindow()` | 自动滚动并纵向拼接多屏；后续可升级为重叠去重/窗口边界识别 |
| 多窗口截图 | 已实现基础版 | `captureMultipleWindowsScreenshot()` | 调用 macOS 交互窗口选择，按住 Shift 连续选择窗口 |
| 全屏带壳截图 | 已实现 | `captureDeviceFramedFullScreen()` | 生成 Mac 风格设备外壳，无水印 |
| 圆角与阴影 | 已实现 | `applyOutputStyle()` | 可配置圆角半径和阴影大小 |
| 标注 | 已实现 | `EditingTool` / `ImageEditingSession` / `FloatingWindowContentView` | 画笔、荧光笔、矩形、圆形、箭头、文字、数字序号、马赛克、裁剪 |
| 贴图 | 已实现基础版 | `EditingWindowController` / `FloatingWindowContentView` | 截图后打开置顶浮窗，可作为贴图参考并继续标注 |
| 取色 | 已实现 | `pickScreenColor()` | 支持 `#HEX`、`rgb(...)`、SwiftUI 颜色代码复制 |
| 录屏 | 已实现 | `startRecording()` | 支持全屏/窗口录制 |
| 系统音频 | 已实现 | `SCStreamConfiguration.capturesAudio` | iShot Pro 高级项 |
| 麦克风录音 | 已实现 | `SCStreamConfiguration.captureMicrophone` | 权限和设备检查已接入 |
| 录制前参数 | 已实现 | `RecordingSettingsView` | FPS、质量、开录延时、系统音频、麦克风、光标、MOV/MP4 |
| OCR | 已实现 | `recognizeTextFromLastScreenshot()` | 基于 Vision 本地识别并复制文本 |
| 截图翻译 | 已实现基础版 | `translateLastScreenshot()` | OCR 后打开 Google Translate；后续可接入本地/自有翻译服务 |
| 快速打开指定 App | 已实现基础版 | `openLastScreenshotInConfiguredApp()` | 可配置指定 App 并从菜单打开最近截图 |

## 已知差距

1. 长截图目前是多屏滚动拼接，尚未做内容重叠检测、重复区域裁剪、自动识别滚动容器。
2. 多窗口截图依赖 macOS 系统交互能力，尚未实现自绘多窗口选区和桌面壁纸底板合成。
3. 截图翻译当前是 OCR 后打开网页翻译，不是内嵌翻译结果浮层。
4. 数字序号标注已单独建模，尚未提供从任意起始编号继续编号的偏好设置。
5. 快速打开指定 App 已有菜单入口，尚未实现 iShot 的双击修饰键触发手势。

## CI 打包

GitHub Actions 已配置 `.github/workflows/build-and-release.yml`：

- 运行环境：`macos-15` + `latest-stable` Xcode。
- 无 Apple 证书时：构建未签名 `.app`，产出 ZIP 和 DMG artifact。
- 有 Apple 证书时：走 Developer ID 导出，并在配置公证账号后执行 notarization。
- 触发方式：推送 `v*` tag 或手动 `workflow_dispatch` 输入版本号。
