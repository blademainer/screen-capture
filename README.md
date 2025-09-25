# Mac Screen Capture

一个功能强大的Mac屏幕录制与截图应用，使用SwiftUI和ScreenCaptureKit构建。

## 功能特性

### 📸 截图功能
- **全屏截图**: 捕获整个屏幕或指定显示器
- **窗口截图**: 智能识别并截取特定窗口
- **区域截图**: 自定义选择截图区域
- **多显示器支持**: 完美支持多显示器环境
- **滚动截图**: 捕获长页面内容（开发中）

### 🎥 录制功能
- **高质量录制**: 支持最高60fps的屏幕录制
- **音频录制**: 同时录制系统音频和麦克风
- **多种格式**: 支持H.264、H.265编码
- **实时控制**: 录制过程中可暂停/恢复
- **性能优化**: 低CPU占用，不影响系统性能

### ⚙️ 系统集成
- **权限管理**: 智能处理macOS权限请求
- **快捷键支持**: 全局快捷键快速操作
- **菜单栏应用**: 便捷的菜单栏访问
- **通知系统**: 及时的操作反馈
- **自动保存**: 智能文件命名和保存

## 系统要求

- macOS 12.0 或更高版本
- 支持Apple Silicon和Intel处理器
- 需要屏幕录制权限
- 录制音频需要麦克风权限

## 安装说明

### 从源码构建

1. 克隆仓库：
```bash
git clone https://github.com/your-username/mac-screen-capture.git
cd mac-screen-capture
```

2. 使用Xcode打开项目：
```bash
open MacScreenCapture.xcodeproj
```

3. 选择目标设备并构建运行

### 权限设置

首次运行时，应用会请求以下权限：

1. **屏幕录制权限**：
   - 系统偏好设置 → 安全性与隐私 → 隐私 → 屏幕录制
   - 勾选"MacScreenCapture"

2. **麦克风权限**（可选）：
   - 系统偏好设置 → 安全性与隐私 → 隐私 → 麦克风
   - 勾选"MacScreenCapture"

3. **辅助功能权限**（可选，用于全局快捷键）：
   - 系统偏好设置 → 安全性与隐私 → 隐私 → 辅助功能
   - 勾选"MacScreenCapture"

## 使用方法

### 快捷键

- `⌘⇧S`: 全屏截图
- `⌘⇧W`: 窗口截图
- `⌘⇧A`: 区域截图
- `⌘⇧R`: 开始/停止录制
- `⌘Space`: 暂停/恢复录制

### 界面操作

1. **截图**：
   - 选择截图模式（全屏/窗口/区域）
   - 选择目标显示器或窗口
   - 点击"开始截图"按钮

2. **录制**：
   - 选择录制模式（全屏/窗口）
   - 配置录制参数（帧率、质量等）
   - 点击"开始录制"按钮

3. **菜单栏**：
   - 点击菜单栏图标快速访问功能
   - 查看录制状态和时长
   - 快速设置和退出

## 技术架构

### 核心技术栈
- **UI框架**: SwiftUI
- **录制引擎**: ScreenCaptureKit (macOS 12.3+)
- **音视频处理**: AVFoundation
- **图像处理**: Core Graphics, Core Image
- **系统集成**: AppKit, Carbon

### 项目结构
```
MacScreenCapture/
├── Core/                   # 核心功能模块
│   ├── PermissionManager.swift
│   └── CaptureManager.swift
├── Views/                  # 用户界面
│   ├── ContentView.swift
│   ├── ScreenshotView.swift
│   ├── RecordingView.swift
│   ├── SettingsView.swift
│   └── MenuBarView.swift
├── Utils/                  # 工具类
│   ├── KeyboardShortcuts.swift
│   ├── NotificationManager.swift
│   └── FileManager+Extensions.swift
└── Resources/              # 资源文件
    └── Assets.xcassets
```

### 设计模式
- **MVVM架构**: 使用SwiftUI的数据绑定
- **观察者模式**: 状态管理和通知
- **单例模式**: 全局服务管理
- **策略模式**: 不同捕获模式的实现

## 开发计划

### 第一阶段 ✅ (已完成)
- [x] 项目架构搭建
- [x] 权限管理系统
- [x] 基础截图功能
- [x] 屏幕录制功能
- [x] 用户界面开发

### 第二阶段 (进行中)
- [ ] 图像编辑功能
- [ ] 视频剪辑功能
- [ ] 文件管理系统
- [ ] 批量处理功能

### 第三阶段 (计划中)
- [ ] 云存储集成
- [ ] 高级编辑工具
- [ ] 插件系统
- [ ] 性能优化

### 第四阶段 (计划中)
- [ ] 最终测试
- [ ] 应用商店发布
- [ ] 用户反馈收集
- [ ] 持续改进

## 性能指标

- **启动时间**: < 3秒
- **截图响应**: < 0.5秒
- **CPU占用**: < 30% (录制时)
- **内存使用**: < 200MB (正常使用)
- **支持分辨率**: 最高8K

## 贡献指南

欢迎贡献代码！请遵循以下步骤：

1. Fork项目
2. 创建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 创建Pull Request

### 代码规范
- 使用SwiftLint进行代码检查
- 遵循Swift官方编码规范
- 添加适当的注释和文档
- 确保单元测试覆盖率 > 80%

## 许可证

本项目采用MIT许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

## 联系方式

- 项目主页: [GitHub Repository](https://github.com/your-username/mac-screen-capture)
- 问题反馈: [Issues](https://github.com/your-username/mac-screen-capture/issues)
- 邮箱: your-email@example.com

## 致谢

感谢以下开源项目和资源：

- [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit) - Apple官方屏幕捕获框架
- [SwiftUI](https://developer.apple.com/xcode/swiftui/) - 现代化的UI框架
- [AVFoundation](https://developer.apple.com/av-foundation/) - 音视频处理框架

---

**注意**: 本应用仅用于合法用途，请遵守当地法律法规和隐私政策。