#!/bin/bash

# MacScreenCapture 版本发布脚本
# 用于创建新版本标签并触发自动发布

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 显示帮助信息
show_help() {
    cat << EOF
MacScreenCapture 版本发布脚本

用法: $0 [选项] <版本号>

选项:
  -h, --help          显示帮助信息
  -d, --dry-run       预览模式，不实际执行操作
  -f, --force         强制创建标签（覆盖已存在的标签）
  -p, --push          自动推送到远程仓库
  -b, --build         本地构建测试

版本号格式:
  主版本.次版本.补丁版本 (例如: 1.0.0)
  或者带 v 前缀 (例如: v1.0.0)

示例:
  $0 1.0.0                    # 创建 v1.0.0 标签
  $0 --push 1.1.0             # 创建并推送 v1.1.0 标签
  $0 --build --push 1.0.1     # 本地构建测试后创建并推送标签
  $0 --dry-run 2.0.0          # 预览创建 v2.0.0 的操作

EOF
}

# 验证版本号格式
validate_version() {
    local version="$1"
    
    # 移除可能的 v 前缀
    version="${version#v}"
    
    # 检查版本号格式 (x.y.z)
    if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_error "无效的版本号格式: $1"
        log_info "版本号应该是 x.y.z 格式，例如: 1.0.0"
        exit 1
    fi
    
    echo "$version"
}

# 检查 Git 状态
check_git_status() {
    log_info "检查 Git 状态..."
    
    # 检查是否在 Git 仓库中
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "当前目录不是 Git 仓库"
        exit 1
    fi
    
    # 检查是否有未提交的更改
    if ! git diff-index --quiet HEAD --; then
        log_warning "检测到未提交的更改"
        git status --porcelain
        echo
        read -p "是否继续？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "操作已取消"
            exit 0
        fi
    fi
    
    log_success "Git 状态检查通过"
}

# 检查标签是否已存在
check_tag_exists() {
    local tag="$1"
    
    if git tag -l | grep -q "^$tag$"; then
        return 0  # 标签存在
    else
        return 1  # 标签不存在
    fi
}

# 获取最新标签
get_latest_tag() {
    git describe --tags --abbrev=0 2>/dev/null || echo "无"
}

# 生成更新日志
generate_changelog() {
    local version="$1"
    local latest_tag=$(get_latest_tag)
    
    log_info "生成更新日志..."
    
    if [ "$latest_tag" = "无" ]; then
        log_info "这是第一个版本，显示所有提交"
        git log --oneline --pretty=format:"- %s" | head -20
    else
        log_info "显示自 $latest_tag 以来的更改"
        git log --oneline --pretty=format:"- %s" "$latest_tag"..HEAD
    fi
}

# 更新项目版本号
update_project_version() {
    local version="$1"
    
    log_info "更新项目版本号到 $version..."
    
    # 更新 Info.plist
    if [ -f "MacScreenCapture/Info.plist" ]; then
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" MacScreenCapture/Info.plist 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" MacScreenCapture/Info.plist 2>/dev/null || true
        log_success "已更新 Info.plist"
    else
        log_warning "未找到 Info.plist 文件"
    fi
    
    # 检查是否有更改需要提交
    if ! git diff-index --quiet HEAD --; then
        log_info "提交版本号更新..."
        git add MacScreenCapture/Info.plist
        git commit -m "chore: bump version to $version"
        log_success "版本号更新已提交"
    fi
}

# 本地构建测试
build_test() {
    log_info "开始本地构建测试..."
    
    if [ ! -f "scripts/build-release.sh" ]; then
        log_error "未找到构建脚本 scripts/build-release.sh"
        exit 1
    fi
    
    # 执行构建测试
    if ./scripts/build-release.sh --version "$1"; then
        log_success "本地构建测试通过"
    else
        log_error "本地构建测试失败"
        exit 1
    fi
}

# 创建标签
create_tag() {
    local version="$1"
    local tag="v$version"
    local force="$2"
    
    log_info "创建标签 $tag..."
    
    # 检查标签是否已存在
    if check_tag_exists "$tag"; then
        if [ "$force" = "true" ]; then
            log_warning "标签 $tag 已存在，将被覆盖"
            git tag -d "$tag"
        else
            log_error "标签 $tag 已存在"
            log_info "使用 --force 选项覆盖已存在的标签"
            exit 1
        fi
    fi
    
    # 生成标签消息
    local tag_message="Release $tag

## 🎉 新功能
- 高质量屏幕录制 (支持 60fps)
- 多种截图模式 (全屏、区域、窗口)
- 音频录制支持 (系统音频 + 麦克风)
- 多显示器支持
- 实时性能监控

## 🛠 技术特性
- 基于 ScreenCaptureKit 框架
- SwiftUI 现代化界面
- H.264 视频编码，兼容 QuickTime
- 优化的内存和 CPU 使用

## 📋 系统要求
- macOS 12.0 或更高版本
- 支持 ScreenCaptureKit 的 Mac 设备

## 📝 更新日志"

    # 添加提交日志
    tag_message="$tag_message
$(generate_changelog "$version")"
    
    # 创建带注释的标签
    git tag -a "$tag" -m "$tag_message"
    
    log_success "标签 $tag 创建成功"
}

# 推送标签
push_tag() {
    local tag="$1"
    
    log_info "推送标签 $tag 到远程仓库..."
    
    # 推送提交（如果有）
    git push origin main
    
    # 推送标签
    git push origin "$tag"
    
    log_success "标签 $tag 已推送到远程仓库"
    log_info "GitHub Actions 将自动开始构建和发布流程"
    log_info "查看进度: https://github.com/$(git config --get remote.origin.url | sed 's/.*github.com[:/]\([^/]*\/[^/]*\).*/\1/' | sed 's/\.git$//')/actions"
}

# 主函数
main() {
    local version=""
    local dry_run=false
    local force=false
    local push=false
    local build=false
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dry-run)
                dry_run=true
                shift
                ;;
            -f|--force)
                force=true
                shift
                ;;
            -p|--push)
                push=true
                shift
                ;;
            -b|--build)
                build=true
                shift
                ;;
            -*)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
            *)
                if [ -z "$version" ]; then
                    version="$1"
                else
                    log_error "只能指定一个版本号"
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # 检查版本号
    if [ -z "$version" ]; then
        log_error "请指定版本号"
        show_help
        exit 1
    fi
    
    # 验证版本号
    version=$(validate_version "$version")
    local tag="v$version"
    
    echo "=================================================="
    echo "  MacScreenCapture 版本发布"
    echo "=================================================="
    echo "版本号: $version"
    echo "标签: $tag"
    echo "预览模式: $dry_run"
    echo "强制覆盖: $force"
    echo "自动推送: $push"
    echo "构建测试: $build"
    echo "=================================================="
    
    if [ "$dry_run" = "true" ]; then
        log_info "预览模式 - 以下操作将被执行："
        echo "1. 检查 Git 状态"
        echo "2. 更新项目版本号到 $version"
        [ "$build" = "true" ] && echo "3. 执行本地构建测试"
        echo "4. 创建标签 $tag"
        [ "$push" = "true" ] && echo "5. 推送标签到远程仓库"
        echo
        log_info "使用不带 --dry-run 的命令来实际执行操作"
        exit 0
    fi
    
    # 确认操作
    echo
    read -p "是否继续创建版本 $tag？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "操作已取消"
        exit 0
    fi
    
    # 执行发布流程
    check_git_status
    update_project_version "$version"
    
    if [ "$build" = "true" ]; then
        build_test "$version"
    fi
    
    create_tag "$version" "$force"
    
    if [ "$push" = "true" ]; then
        push_tag "$tag"
    else
        log_info "标签已创建，使用以下命令推送到远程仓库："
        log_info "git push origin $tag"
    fi
    
    echo "=================================================="
    log_success "版本 $tag 发布流程完成！"
    echo "=================================================="
    
    if [ "$push" = "true" ]; then
        log_info "GitHub Actions 正在自动构建和发布..."
        log_info "几分钟后可在 GitHub Releases 页面查看发布包"
    fi
}

# 运行主函数
main "$@"