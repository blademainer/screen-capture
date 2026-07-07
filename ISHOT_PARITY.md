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
| 窗口截图 | 已实现 | `captureInteractiveWindowScreenshot()` / `MultiWindowSelectionView` | 热键和菜单会弹出窗口覆盖层，普通点击立即截单窗口；主界面仍支持预选窗口 |
| 区域截图 | 已实现 | `captureRegionScreenshot()` | 调用 macOS `screencapture -i -r` |
| 延时截图 | 已实现 | `captureDelayedScreenshot()` / `ScreenshotCountdownOverlayController` / `HotKeyAction.delayedScreenshot` | 秒数可在设置中配置，默认 `⌘⌥L` 触发；截图前显示 54321 风格倒计时浮层，方便用户摆好菜单/窗口状态 |
| 长截图 | 已实现 | `captureScrollingWindow()` / `scrollingContentAreaUnderMouse()` | 自动滚动、优先通过辅助功能识别窗口内滚动内容区并裁剪切片，识别失败时回退到鼠标所在窗口；默认最多 30 屏且可配置到 100 屏，支持向下/向上滚动方向并按阅读顺序拼接，滚动到底自动停止、检测相邻截图重叠区域并裁剪后纵向拼接 |
| 多窗口截图 | 已实现 | `captureMultipleWindowsScreenshot()` / `MultiWindowSelectionView` / `renderMultiWindowComposite()` / `HotKeyAction.multiWindowScreenshot` | 自绘窗口多选覆盖层；窗口截图时按住 Shift 可连续选择多个窗口并按 Enter 合成，独立多窗口模式默认 `⌘⌥W` 触发；选择覆盖层和合成画布支持跨显示器窗口，可点选桌面启用壁纸底板，桌面底板模式也可在设置中默认开启 |
| 全屏带壳截图 | 已实现 | `captureDeviceFramedFullScreen()` / `renderDeviceFrame()` / `HotKeyAction.deviceFramedScreenshot` | 生成 Mac 风格设备外壳，无水印；默认 `⌘⌥F` 触发，支持外壳厚度、画布留白、外壳圆角、阴影大小、外壳颜色和阴影颜色配置 |
| 圆角与阴影 | 已实现 | `applyOutputStyle()` | 可配置圆角半径、阴影大小和阴影颜色 |
| 标注 | 已实现 | `EditingTool` / `ImageEditingSession` / `EditingWindowContentView` / `FloatingWindowContentView` / `AnnotationStylePreset` | 普通截图编辑窗口和贴图浮窗共用增强画布；画笔、荧光笔、矩形、圆形、箭头、文字、数字序号、马赛克、裁剪；裁剪会进入最终保存/复制结果，数字序号支持配置起始值、连续编号和双击改号，文字/序号支持颜色、大小、描边、内置样式模板、3 套用户自定义模板、模板导入/导出和选择模式拖动位置 |
| 贴图 | 已实现 | `capturePinnedRegion()` / `FloatingWindowManager` / `FloatingWindowContentView` / `HotKeyAction.pinnedScreenshot` | 交互选择区域后打开置顶贴图浮窗，可重复创建多个贴图并继续标注；默认 `⌘⌥P` 可快速贴图 |
| 取色 | 已实现 | `pickScreenColor()` / `HotKeyAction.pickColor` | 支持颜色名称、`#HEX`、`rgb(...)`、SwiftUI 和自定义色码模板复制；默认 `⌘⇧C` 可快速取色，并可在快捷键设置中修改 |
| 录屏 | 已实现 | `startRecording()` / `HotKeyAction.startRecording` / `HotKeyAction.togglePauseRecording` / `CaptureStreamOutput.setPaused()` | 支持全屏、窗口和拖拽选择区域录制；默认 `⌥W` 开始录屏，`⌘⌥Space` 暂停/恢复并在输出层跳过暂停样本、压缩时间戳，`⌘⇧R` 停止录屏 |
| 系统音频 | 已实现 | `SCStreamConfiguration.capturesAudio` / `RecordingAudioDiagnostics` | iShot Pro 高级项；停止录制后会等待文件写入完成并验收音频帧/音轨，异常时通知用户检查 |
| 录音 | 已实现 | `startAudioRecording()` / `HotKeyAction.startAudioRecording` / `HotKeyAction.togglePauseRecording` / `CaptureStreamOutput(audioOnly:)` | 支持独立 `.m4a` 录音，可录制系统内部声音和麦克风，默认 `⌘⇧M` 开始录音，`⌘⌥Space` 暂停/恢复并复用输出层暂停处理、音频帧/音轨验收 |
| 麦克风录音 | 已实现 | `SCStreamConfiguration.captureMicrophone` | 权限和设备检查已接入 |
| 录制前参数 | 已实现 | `startRecordingWithPreflight()` / `RecordingPreflightSettingsView` / `RecordingSettingsView` / `ScreenshotCountdownOverlayController` / `CaptureStreamOutput` | 菜单、热键和主录制按钮都会先确认清晰度、FPS、开录延时、系统音频、麦克风、光标、MOV/MP4；开录延时会显示倒计时，区域录制在选区后倒计时；质量档位会实际影响 H.264 码率/编码配置 |
| OCR | 已实现 | `captureRegionAndRecognizeText()` / `recognizeTextFromLastScreenshot()` / `HotKeyAction.ocrScreenshot` | 支持从菜单或默认 `⌘⌥O` 直接框选区域截图并 OCR，也可识别最近截图；基于 Vision 本地识别并复制文本 |
| 截图翻译 | 已实现 | `captureRegionAndTranslate()` / `translateLastScreenshot()` / `translateWithAppleInstalledModel()` / `prepareAppleTranslationModels()` / `translateWithMyMemory()` / `HotKeyAction.translateScreenshot` | 支持从菜单或默认 `⌘⌥T` 直接框选区域截图并翻译，也可翻译最近截图；OCR 后优先使用 Apple 已安装本地翻译模型，模型不可用时自动切换 Google 在线端点、MyMemory 备用端点，长文本会按接口限制分段翻译，仍失败时打开网页翻译兜底；设置中可检查并准备本地翻译模型；应用内展示原文/译文并复制译文 |
| 快速打开指定 App | 已实现 | `captureRegionAndOpenInConfiguredApp()` / `openLastScreenshotInConfiguredApp()` | 可配置指定 App，支持菜单打开最近截图、双击 Option 后区域截图并保存、立即打开，也支持截图保存后自动用指定 App 打开；普通截图遵守自动保存开关，快速打开流程会强制保存以匹配 iShot“保存图片并使用指定 App 打开”的连贯操作；双击判定时间和触发冷却可在设置中调整 |

## 已知差距

1. 长截图已支持按鼠标所在窗口裁剪、优先识别 Accessibility 暴露的滚动内容区、向下/向上滚动方向、按阅读顺序拼接、滚动到底自动停止、最多 100 屏配置并检测重叠区域；后续可继续增加更多 App 的滚动容器实测样本和兼容性规则。
2. 多窗口截图已支持自绘多选、窗口截图 Shift 连选、点选桌面启用壁纸底板、桌面底板默认偏好和跨显示器合成；后续可继续在更多显示器排列方式下补充实测样本。
3. 截图翻译已有框选翻译、应用内结果窗口、Apple 已安装本地翻译模型、设置内模型检查/准备入口、主备在线端点、MyMemory 长文本分段和网页兜底；后续可继续增加更多目标语言和批量翻译体验。
4. 数字序号标注已支持起始编号、连续编号、双击改号、颜色、大小、描边、内置样式模板、3 套用户自定义模板、模板导入/导出和选择模式下拖动位置；后续可继续增加跨设备同步。
5. 快速打开指定 App 已支持菜单打开最近截图、双击 Option 手势、手势间隔、触发冷却偏好、截图保存后自动打开和快速打开时强制保存；普通截图会遵守自动保存开关；后续可继续补更多条件化触发模式。

## CI 打包

GitHub Actions 已配置 `.github/workflows/build-and-release.yml`：

- 运行环境：`macos-15` + `latest-stable` Xcode。
- 无 Apple 证书时：构建未签名 `.app`，产出 ZIP 和 DMG artifact。
- 有 Apple 证书时：走 Developer ID 导出，并在配置公证账号后执行 notarization。
- 触发方式：推送 `v*` tag 或手动 `workflow_dispatch` 输入版本号。
