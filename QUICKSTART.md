# 🚀 MacScreenCapture 快速发布指南

## 📦 一键发布第一个版本

### 方法一：使用发布脚本（推荐）

```bash
# 创建并发布 v1.0.0 版本
./scripts/release.sh --build --push 1.0.0
```

这个命令会：
1. ✅ 检查 Git 状态
2. ✅ 更新项目版本号
3. ✅ 本地构建测试
4. ✅ 创建 Git 标签
5. ✅ 推送到 GitHub
6. ✅ 触发自动发布

### 方法二：手动步骤

```bash
# 1. 创建标签
git tag v1.0.0
git push origin v1.0.0

# 2. GitHub Actions 会自动构建和发布
```

## 🛠 自动化系统概览

### 已配置的功能

| 功能 | 状态 | 说明 |
|------|------|------|
| GitHub Actions | ✅ | 自动构建和发布 |
| 本地构建脚本 | ✅ | 测试和打包 |
| 版本管理脚本 | ✅ | 自动化版本发布 |
| 代码签名支持 | ✅ | 可选配置 |
| 公证支持 | ✅ | 可选配置 |
| DMG 创建 | ✅ | 自动生成 |
| ZIP 打包 | ✅ | 自动生成 |

### 文件结构

```
├── .github/workflows/
│   └── build-and-release.yml    # GitHub Actions 配置
├── scripts/
│   ├── build-release.sh         # 本地构建脚本
│   └── release.sh              # 版本发布脚本
├── RELEASE.md                  # 详细发布指南
└── QUICKSTART.md              # 本文件
```

## 🎯 发布流程

### 1. 准备发布

```bash
# 确保代码已提交
git add .
git commit -m "准备发布 v1.0.0"
git push origin main
```

### 2. 创建版本

```bash
# 预览发布操作
./scripts/release.sh --dry-run 1.0.0

# 执行发布（推荐）
./scripts/release.sh --build --push 1.0.0
```

### 3. 监控构建

- 访问 GitHub Actions 页面查看构建进度
- 构建完成后在 GitHub Releases 页面下载

## 📋 常用命令

### 发布脚本选项

```bash
# 基本发布
./scripts/release.sh 1.0.0

# 本地构建测试 + 发布
./scripts/release.sh --build --push 1.0.0

# 预览模式（不实际执行）
./scripts/release.sh --dry-run 1.0.0

# 强制覆盖已存在的标签
./scripts/release.sh --force 1.0.0

# 查看帮助
./scripts/release.sh --help
```

### 构建脚本选项

```bash
# 本地构建测试
./scripts/build-release.sh

# 指定版本构建
./scripts/build-release.sh --version 1.0.0

# 查看帮助
./scripts/build-release.sh --help
```

## 🔧 可选配置

### 代码签名（推荐用于正式发布）

在 GitHub 仓库设置中添加以下 Secrets：

```
CERTIFICATES_P12          # 开发者证书（Base64）
CERTIFICATES_P12_PASSWORD # 证书密码
CODE_SIGN_IDENTITY        # 签名身份
DEVELOPMENT_TEAM          # 开发团队 ID
```

### 公证配置（App Store 分发必需）

```
NOTARIZATION_USERNAME     # Apple ID
NOTARIZATION_PASSWORD     # App 专用密码
```

## 📊 发布产物

成功发布后，GitHub Releases 页面将包含：

- `MacScreenCapture-v1.0.0-macOS.dmg` - 磁盘映像（如果有代码签名）
- `MacScreenCapture-v1.0.0-macOS.zip` - ZIP 压缩包
- 自动生成的发布说明

## 🚨 故障排除

### 常见问题

1. **构建失败**
   ```bash
   # 清理构建缓存
   rm -rf ~/Library/Developer/Xcode/DerivedData
   ./scripts/build-release.sh
   ```

2. **权限错误**
   ```bash
   # 给脚本执行权限
   chmod +x scripts/*.sh
   ```

3. **Git 状态问题**
   ```bash
   # 检查未提交的更改
   git status
   git add .
   git commit -m "提交更改"
   ```

### 调试模式

```bash
# 启用详细输出
VERBOSE=1 ./scripts/build-release.sh
```

## 🎉 快速开始示例

完整的发布流程示例：

```bash
# 1. 确保在项目根目录
cd /path/to/MacScreenCapture

# 2. 提交所有更改
git add .
git commit -m "准备发布第一个版本"
git push origin main

# 3. 一键发布
./scripts/release.sh --build --push 1.0.0

# 4. 等待几分钟，然后访问 GitHub Releases 页面下载
```

## 📚 更多信息

- 详细配置说明：查看 `RELEASE.md`
- GitHub Actions 配置：`.github/workflows/build-and-release.yml`
- 构建脚本源码：`scripts/build-release.sh`
- 发布脚本源码：`scripts/release.sh`

---

**恭喜！** 🎉 您的 MacScreenCapture 项目现在已经具备完整的自动化构建和发布能力！