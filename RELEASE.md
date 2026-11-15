# MacScreenCapture 发布指南

## 自动测试和打包

工作流：`.github/workflows/build-and-release.yml`，名称为 **Build and Release MacScreenCapture**。

| 触发方式 | 测试 | Universal 打包 | 发布 Release |
| --- | --- | --- | --- |
| 推送到 `main` | 是 | 是 | 否 |
| 向 `main` 提交 PR | 是 | 是 | 否 |
| Actions 页面手动 Run workflow | 是 | 是 | 否 |
| 推送 `v*` tag | 是 | 是 | 是，仅在前面步骤全部成功后 |

构建使用 `macos-15` runner、Swift Package Manager 和系统自带的 Xcode 工具链。首先运行 `swift test`，再分别编译 `arm64` 和 `x86_64`，通过 `lipo` 合成 Universal 应用，支持 Apple Silicon 和 Intel。

在 [Actions 页面](https://github.com/blademainer/screen-capture/actions)打开成功的运行记录，从 Artifacts 下载 `MacScreenCapture-universal-*`。包内包含：

- `MacScreenCapture-<版本>-universal-macOS.zip`
- `MacScreenCapture-<版本>-universal-macOS.dmg`
- `SHA256SUMS`

测试日志单独保存为 `test-log-*`，失败时也会尝试上传。Artifacts 保留 14 天；Release 附件不受这个保留期限限制。普通 CI 使用 `0.0.0-dev.<运行编号>` 标记产物，不代表正式版本。

## 发布一个版本

确保当前提交已经通过测试，再创建一个未使用过的版本标签：

```bash
git switch main
git pull --ff-only
git tag -a v1.0.1 -m "Release v1.0.1"
git push origin v1.0.1
```

支持 `v1.0.1` 或 `v1.0.1-rc.1` 格式。其他匹配 `v*` 但不是有效版本号的 tag 会在打包前被拒绝。含 `-` 的版本会发布为预发布版本，且不会标记为最新稳定版。

tag 工作流测试和打包成功后，独立的发布任务下载同一次构建的产物、验证 SHA-256，再创建 [GitHub Release](https://github.com/blademainer/screen-capture/releases)，上传 ZIP、DMG 和校验和，自动生成更新说明。只有发布任务拥有 `contents: write` 权限。

不要强制移动已经发布的 tag。若测试或打包失败，修复后发布新 tag；若只是发布任务遇到临时网络问题，可在 Actions 中重新运行失败的任务。若 Release 已存在，请先检查其附件和状态，不要盲目覆盖。

## 签名、系统要求和安装

当前版本**只做 ad-hoc 签名，不做 Developer ID 正式签名或 Apple 公证**，不需要配置任何 Apple 证书或 GitHub Secrets。ad-hoc 签名用于本地代码完整性验证，并不代表 Apple 已验证开发者身份。

- 最低系统版本：macOS 15，与 `Package.swift` 一致。
- bundle identifier：`com.blademainer.MacScreenCapture`。
- ZIP 解压后将 `MacScreenCapture.app` 放到 `/Applications`；DMG 内可拖到 `Applications` 快捷方式。
- 未公证应用首次打开可能被 Gatekeeper 拦截。确认下载来源后，可按系统提示在“系统设置 > 隐私与安全性”中允许打开；受管理的设备可能仍受组织策略限制。
- 首次使用需授予屏幕录制权限；录制麦克风时还需麦克风权限。CI 无法替用户授予这些权限，也不运行真实录屏的 UI 测试。

## 本地构建和验证

```bash
swift test
./scripts/build-release.sh --version 1.0.1
# 预发布版本的 bundle 短版本仍为数字，构建编号可单独指定
./scripts/build-release.sh --version v1.0.1-rc.1 --build-number 123
cd build
shasum -a 256 -c SHA256SUMS
```

本地也需要 macOS 15 或更新系统，以及支持该系统 SDK 的 Xcode 命令行工具。脚本任一步失败即退出；不修改受版本管理的 plist，仅在 `build/export/MacScreenCapture.app` 写入版本号。最终产物位于 `build/`，资源和图标均包含在应用内。

本地手工测试前，将打包后的应用安装到固定路径，避免从 `.build` 的裸可执行文件运行：

```bash
pkill -x MacScreenCapture || true
ditto build/export/MacScreenCapture.app /Applications/MacScreenCapture.app
open -a /Applications/MacScreenCapture.app
```
