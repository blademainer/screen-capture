# MacScreenCapture 发布指南

本文档说明如何使用自动化工具构建和发布 MacScreenCapture 应用程序。

## 🚀 快速发布

### 方法一：GitHub Actions 自动发布（推荐）

1. **创建新的 Git 标签**：
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

2. **GitHub Actions 将自动**：
   - 构建应用程序
   - 创建 DMG 和 ZIP 包
   - 发布到 GitHub Releases

### 方法二：手动触发 GitHub Actions

1. 访问 GitHub 仓库的 Actions 页面
2. 选择 "Build and Release MacScreenCapture" workflow
3. 点击 "Run workflow"
4. 输入版本号（如 v1.0.0）
5. 点击 "Run workflow"

### 方法三：本地构建

```bash
# 给脚本执行权限
chmod +x scripts/build-release.sh

# 构建默认版本
./scripts/build-release.sh

# 构建指定版本
./scripts/build-release.sh --version 1.0.0
```

## 🔧 配置 GitHub Actions

### 必需的 Secrets（可选，用于代码签名）

在 GitHub 仓库设置中添加以下 Secrets：

| Secret 名称 | 描述 | 是否必需 |
|------------|------|---------|
| `CERTIFICATES_P12` | 开发者证书（Base64编码） | 可选 |
| `CERTIFICATES_P12_PASSWORD` | 证书密码 | 可选 |
| `CODE_SIGN_IDENTITY` | 代码签名身份 | 可选 |
| `DEVELOPMENT_TEAM` | 开发团队 ID | 可选 |
| `NOTARIZATION_USERNAME` | Apple ID 用户名 | 可选 |
| `NOTARIZATION_PASSWORD` | App专用密码 | 可选 |

### 获取开发者证书

1. **导出证书**：
   ```bash
   # 在 Keychain Access 中导出开发者证书为 .p12 文件
   # 然后转换为 Base64
   base64 -i Certificates.p12 | pbcopy
   ```

2. **创建 App 专用密码**：
   - 访问 [appleid.apple.com](https://appleid.apple.com)
   - 登录并生成 App 专用密码

## 📦 构建产物

成功构建后，将生成以下文件：

- `MacScreenCapture-v1.0.0-macOS.zip` - ZIP 压缩包
- `MacScreenCapture-v1.0.0-macOS.dmg` - DMG 磁盘映像（如果有代码签名）

## 🔍 构建流程详解

### GitHub Actions 流程

1. **环境准备**：
   - 使用 macOS 13 运行器
   - 安装指定版本的 Xcode

2. **代码签名**（可选）：
   - 导入开发者证书
   - 配置代码签名设置

3. **构建应用**：
   - 清理之前的构建
   - 使用 Release 配置构建
   - 创建 Archive

4. **导出应用**：
   - 导出签名的应用程序
   - 创建分发包

5. **公证**（如果有证书）：
   - 创建 DMG
   - 提交到 Apple 公证服务
   - 装订公证票据

6. **发布**：
   - 创建 GitHub Release
   - 上传构建产物
   - 生成发布说明

### 本地构建流程

1. **环境检查**：验证 Xcode 安装
2. **清理构建**：删除旧的构建文件
3. **版本更新**：更新 Info.plist 中的版本号
4. **项目构建**：使用 xcodebuild 构建项目
5. **应用导出**：导出可分发的应用程序
6. **包创建**：创建 ZIP 和 DMG 包
7. **验证**：检查应用程序完整性

## 🛠 故障排除

### 常见问题

1. **构建失败**：
   ```bash
   # 检查 Xcode 版本
   xcodebuild -version
   
   # 清理构建缓存
   rm -rf ~/Library/Developer/Xcode/DerivedData
   ```

2. **代码签名问题**：
   ```bash
   # 检查可用的签名身份
   security find-identity -v -p codesigning
   
   # 检查证书有效性
   security dump-keychain | grep "Developer ID"
   ```

3. **权限问题**：
   ```bash
   # 给脚本执行权限
   chmod +x scripts/build-release.sh
   ```

### 调试模式

启用详细输出：
```bash
# 本地构建时启用详细模式
VERBOSE=1 ./scripts/build-release.sh --version 1.0.0
```

## 📋 发布检查清单

发布前请确认：

- [ ] 代码已提交并推送到主分支
- [ ] 版本号已更新
- [ ] 功能测试通过
- [ ] 构建脚本测试通过
- [ ] 发布说明已准备
- [ ] GitHub Secrets 已配置（如需代码签名）

## 🔄 版本管理

### 版本号规范

使用语义化版本控制（SemVer）：
- `v1.0.0` - 主要版本
- `v1.1.0` - 次要版本（新功能）
- `v1.0.1` - 补丁版本（bug修复）

### 标签创建

```bash
# 创建带注释的标签
git tag -a v1.0.0 -m "Release version 1.0.0"

# 推送标签
git push origin v1.0.0

# 推送所有标签
git push origin --tags
```

## 📚 相关文档

- [Xcode Build Settings Reference](https://developer.apple.com/documentation/xcode/build-settings-reference)
- [Code Signing Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/)
- [Notarizing macOS Software](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)