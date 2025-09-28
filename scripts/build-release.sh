#!/bin/bash

# MacScreenCapture 发布构建脚本
# 用于创建可分发的应用程序包

set -e

# 配置
PROJECT_NAME="MacScreenCapture"
SCHEME_NAME="MacScreenCapture"
CONFIGURATION="Release"
BUILD_DIR="./build"
EXPORT_DIR="$BUILD_DIR/export"
ARCHIVE_PATH="$BUILD_DIR/$PROJECT_NAME.xcarchive"

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

# 检查 Xcode 是否可用
check_xcode() {
    log_info "检查 Xcode 环境..."
    if ! command -v xcodebuild &> /dev/null; then
        log_error "Xcode 命令行工具未安装"
        exit 1
    fi
    
    XCODE_VERSION=$(xcodebuild -version | head -n 1)
    log_success "发现 $XCODE_VERSION"
}

# 清理构建目录
clean_build() {
    log_info "清理构建目录..."
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    mkdir -p "$EXPORT_DIR"
    
    # 清理 Xcode 构建缓存
    xcodebuild clean -project "$PROJECT_NAME.xcodeproj" -scheme "$SCHEME_NAME" -configuration "$CONFIGURATION"
    log_success "构建目录已清理"
}

# 更新版本号
update_version() {
    if [ -n "$1" ]; then
        VERSION="$1"
        log_info "更新版本号到 $VERSION..."
        
        # 更新 Info.plist
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PROJECT_NAME/Info.plist" 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$PROJECT_NAME/Info.plist" 2>/dev/null || true
        
        log_success "版本号已更新到 $VERSION"
    else
        log_info "未指定版本号，使用项目默认版本"
    fi
}

# 构建项目
build_project() {
    log_info "开始构建 $PROJECT_NAME..."
    
    xcodebuild archive \
        -project "$PROJECT_NAME.xcodeproj" \
        -scheme "$SCHEME_NAME" \
        -configuration "$CONFIGURATION" \
        -archivePath "$ARCHIVE_PATH" \
        -destination "generic/platform=macOS" \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGN_STYLE="Automatic" \
        DEVELOPMENT_TEAM="" \
        | xcpretty || true
    
    if [ ! -d "$ARCHIVE_PATH" ]; then
        log_error "构建失败，未找到 archive 文件"
        exit 1
    fi
    
    log_success "项目构建完成"
}

# 导出应用程序
export_app() {
    log_info "导出应用程序..."
    
    # 创建导出选项 plist
    cat > "$BUILD_DIR/ExportOptions.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>development</string>
    <key>uploadBitcode</key>
    <false/>
    <key>uploadSymbols</key>
    <false/>
    <key>compileBitcode</key>
    <false/>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF
    
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$EXPORT_DIR" \
        -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
        | xcpretty || true
    
    if [ ! -d "$EXPORT_DIR/$PROJECT_NAME.app" ]; then
        log_error "导出失败，未找到应用程序"
        exit 1
    fi
    
    log_success "应用程序导出完成"
}

# 创建分发包
create_package() {
    log_info "创建分发包..."
    
    APP_PATH="$EXPORT_DIR/$PROJECT_NAME.app"
    VERSION=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0.0")
    
    # 创建 ZIP 包
    ZIP_NAME="$PROJECT_NAME-v$VERSION-macOS.zip"
    cd "$EXPORT_DIR"
    zip -r "../$ZIP_NAME" "$PROJECT_NAME.app"
    cd - > /dev/null
    
    # 创建 DMG（如果可能）
    if command -v hdiutil &> /dev/null; then
        DMG_NAME="$PROJECT_NAME-v$VERSION-macOS.dmg"
        hdiutil create -volname "$PROJECT_NAME" -srcfolder "$APP_PATH" -ov -format UDZO "$BUILD_DIR/$DMG_NAME"
        log_success "已创建 DMG: $BUILD_DIR/$DMG_NAME"
    fi
    
    log_success "已创建 ZIP: $BUILD_DIR/$ZIP_NAME"
    
    # 显示应用信息
    log_info "应用程序信息:"
    echo "  名称: $PROJECT_NAME"
    echo "  版本: $VERSION"
    echo "  路径: $APP_PATH"
    echo "  大小: $(du -sh "$APP_PATH" | cut -f1)"
}

# 验证应用程序
verify_app() {
    log_info "验证应用程序..."
    
    APP_PATH="$EXPORT_DIR/$PROJECT_NAME.app"
    
    # 检查代码签名
    if codesign -v "$APP_PATH" 2>/dev/null; then
        log_success "代码签名验证通过"
    else
        log_warning "代码签名验证失败（开发版本正常）"
    fi
    
    # 检查权限
    if [ -f "$APP_PATH/Contents/Info.plist" ]; then
        log_success "Info.plist 存在"
    else
        log_error "Info.plist 缺失"
    fi
    
    # 检查可执行文件
    if [ -x "$APP_PATH/Contents/MacOS/$PROJECT_NAME" ]; then
        log_success "可执行文件存在且可执行"
    else
        log_error "可执行文件问题"
    fi
}

# 主函数
main() {
    echo "=================================================="
    echo "  MacScreenCapture 发布构建脚本"
    echo "=================================================="
    
    # 解析参数
    VERSION=""
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--version)
                VERSION="$2"
                shift 2
                ;;
            -h|--help)
                echo "用法: $0 [选项]"
                echo "选项:"
                echo "  -v, --version VERSION   设置版本号"
                echo "  -h, --help             显示帮助信息"
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                exit 1
                ;;
        esac
    done
    
    # 执行构建流程
    check_xcode
    clean_build
    update_version "$VERSION"
    build_project
    export_app
    verify_app
    create_package
    
    echo "=================================================="
    log_success "构建完成！"
    echo "=================================================="
    echo "构建产物位于: $BUILD_DIR/"
    ls -la "$BUILD_DIR/"*.{zip,dmg} 2>/dev/null || true
}

# 运行主函数
main "$@"