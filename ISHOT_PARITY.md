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
| 长截图 | 已实现 | `captureScrollingWindow()` | 自动滚动、按鼠标所在窗口裁剪切片、检测相邻截图重叠区域并裁剪后纵向拼接 |
| 多窗口截图 | 已实现 | `captureMultipleWindowsScreenshot()` / `MultiWindowSelectionView` | 自绘窗口多选覆盖层，点击选择多个窗口后按 Enter 合成；默认启用桌面底板模式，可在设置中关闭 |
| 全屏带壳截图 | 已实现 | `captureDeviceFramedFullScreen()` / `renderDeviceFrame()` | 生成 Mac 风格设备外壳，无水印；支持外壳厚度、画布留白、外壳圆角、阴影大小、外壳颜色和阴影颜色配置 |
| 圆角与阴影 | 已实现 | `applyOutputStyle()` | 可配置圆角半径、阴影大小和阴影颜色 |
| 标注 | 已实现 | `EditingTool` / `ImageEditingSession` / `EditingWindowContentView` / `FloatingWindowContentView` | 普通截图编辑窗口和贴图浮窗共用增强画布；画笔、荧光笔、矩形、圆形、箭头、文字、数字序号、马赛克、裁剪；数字序号支持配置起始值并连续编号，文字/序号支持颜色、大小、描边和选择模式拖动位置 |
| 贴图 | 已实现 | `capturePinnedRegion()` / `FloatingWindowManager` / `FloatingWindowContentView` | 交互选择区域后打开置顶贴图浮窗，可重复创建多个贴图并继续标注 |
| 取色 | 已实现 | `pickScreenColor()` | 支持颜色名称、`#HEX`、`rgb(...)`、SwiftUI 和自定义色码模板复制 |
| 录屏 | 已实现 | `startRecording()` | 支持全屏、窗口和拖拽选择区域录制 |
| 系统音频 | 已实现 | `SCStreamConfiguration.capturesAudio` / `RecordingAudioDiagnostics` | iShot Pro 高级项；停止录制后会等待文件写入完成并验收音频帧/音轨，异常时通知用户检查 |
| 录音 | 已实现 | `startAudioRecording()` / `CaptureStreamOutput(audioOnly:)` | 支持独立 `.m4a` 录音，可录制系统内部声音和麦克风，并复用音频帧/音轨验收 |
| 麦克风录音 | 已实现 | `SCStreamConfiguration.captureMicrophone` | 权限和设备检查已接入 |
| 录制前参数 | 已实现 | `RecordingSettingsView` / `CaptureStreamOutput` | FPS、质量、开录延时、系统音频、麦克风、光标、MOV/MP4；质量档位会实际影响 H.264 码率/编码配置 |
| OCR | 已实现 | `captureRegionAndRecognizeText()` / `recognizeTextFromLastScreenshot()` | 支持从菜单直接框选区域截图并 OCR，也可识别最近截图；基于 Vision 本地识别并复制文本 |
| 截图翻译 | 已实现基础版 | `captureRegionAndTranslate()` / `translateLastScreenshot()` | 支持从菜单直接框选区域截图并翻译，也可翻译最近截图；OCR 后在线翻译，应用内展示原文/译文并复制译文；在线接口失败时自动打开网页翻译兜底 |
| 快速打开指定 App | 已实现 | `captureRegionAndOpenInConfiguredApp()` / `openLastScreenshotInConfiguredApp()` | 可配置指定 App，支持菜单打开最近截图，也支持双击 Option 后区域截图并立即打开 |

## 已知差距

1. 长截图已支持按鼠标所在窗口裁剪并检测重叠区域；后续可继续升级为网页/列表内部滚动容器的精确边界识别。
2. 多窗口截图已支持自绘多选和桌面底板模式；后续可继续补多显示器跨屏合成的完整验证。
3. 截图翻译已有框选翻译和应用内结果窗口，当前默认使用在线翻译端点，尚未接入离线翻译引擎。
4. 数字序号标注已支持起始编号、颜色、大小、描边和选择模式下拖动位置；后续可继续增加样式模板。
5. 快速打开指定 App 已支持双击 Option 手势，后续可继续增加手势间隔和触发模式的高级偏好。

## CI 打包

GitHub Actions 已配置 `.github/workflows/build-and-release.yml`：

- 运行环境：`macos-15` + `latest-stable` Xcode。
- 无 Apple 证书时：构建未签名 `.app`，产出 ZIP 和 DMG artifact。
- 有 Apple 证书时：走 Developer ID 导出，并在配置公证账号后执行 notarization。
- 触发方式：推送 `v*` tag 或手动 `workflow_dispatch` 输入版本号。
