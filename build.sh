#!/bin/bash

# Mac Screen Capture 构建脚本
# 用于自动化构建、测试和打包流程

set -e  # 遇到错误时退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 项目配置
PROJECT_NAME="MacScreenCapture"
SCHEME_NAME="MacScreenCapture"
CONFIGURATION="Release"
ARCHIVE_PATH="./build/MacScreenCapture.xcarchive"
EXPORT_PATH="./build/export"

# 函数定义
print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# 检查依赖
check_dependencies() {
    print_header "检查构建依赖"
    
    # 检查 Xcode
    if ! command -v xcodebuild &> /dev/null; then
        print_error "Xcode 未安装或未在 PATH 中"
        exit 1
    fi
    
    # 检查 SwiftLint
    if ! command -v swiftlint &> /dev/null; then
        print_warning "SwiftLint 未安装，跳过代码检查"
    else
        print_success "SwiftLint 已安装"
    fi
    
    print_success "依赖检查完成"
}

# 清理构建目录
clean_build() {
    print_header "清理构建目录"
    
    if [ -d "build" ]; then
        rm -rf build
        print_success "已清理 build 目录"
    fi
    
    # 清理 Xcode 构建缓存
    xcodebuild clean -project "${PROJECT_NAME}.xcodeproj" -scheme "$SCHEME_NAME" -configuration "$CONFIGURATION"
    print_success "已清理 Xcode 构建缓存"
}

# 代码质量检查
code_quality_check() {
    print_header "代码质量检查"
    
    if command -v swiftlint &> /dev/null; then
        echo "运行 SwiftLint..."
        swiftlint
        print_success "SwiftLint 检查通过"
    else
        print_warning "跳过 SwiftLint 检查"
    fi
}

# 运行单元测试
run_tests() {
    print_header "运行单元测试"
    
    echo "运行单元测试..."
    xcodebuild test \
        -project "${PROJECT_NAME}.xcodeproj" \
        -scheme "$SCHEME_NAME" \
        -destination "platform=macOS" \
        -configuration Debug \
        -enableCodeCoverage YES
    
    print_success "单元测试通过"
}

# 构建应用
build_app() {
    print_header "构建应用"
    
    echo "构建 $SCHEME_NAME..."
    xcodebuild build \
        -project "${PROJECT_NAME}.xcodeproj" \
        -scheme "$SCHEME_NAME" \
        -configuration "$CONFIGURATION" \
        -destination "platform=macOS"
    
    print_success "应用构建完成"
}

# 创建归档
create_archive() {
    print_header "创建应用归档"
    
    mkdir -p build
    
    echo "创建归档..."
    xcodebuild archive \
        -project "${PROJECT_NAME}.xcodeproj" \
        -scheme "$SCHEME_NAME" \
        -configuration "$CONFIGURATION" \
        -archivePath "$ARCHIVE_PATH"
    
    print_success "归档创建完成: $ARCHIVE_PATH"
}

# 导出应用
export_app() {
    print_header "导出应用"
    
    # 创建导出配置文件
    cat > ExportOptions.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>mac-application</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
EOF
    
    echo "导出应用..."
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$EXPORT_PATH" \
        -exportOptionsPlist ExportOptions.plist
    
    # 清理临时文件
    rm ExportOptions.plist
    
    print_success "应用导出完成: $EXPORT_PATH"
}

# 创建 DMG
create_dmg() {
    print_header "创建 DMG 安装包"
    
    if [ ! -d "$EXPORT_PATH" ]; then
        print_error "导出目录不存在，请先运行导出"
        return 1
    fi
    
    DMG_NAME="${PROJECT_NAME}-$(date +%Y%m%d).dmg"
    
    # 创建临时 DMG 目录
    DMG_DIR="./build/dmg"
    mkdir -p "$DMG_DIR"
    
    # 复制应用到 DMG 目录
    cp -R "$EXPORT_PATH"/*.app "$DMG_DIR/"
    
    # 创建 Applications 链接
    ln -s /Applications "$DMG_DIR/Applications"
    
    # 创建 DMG
    hdiutil create -volname "$PROJECT_NAME" -srcfolder "$DMG_DIR" -ov -format UDZO "./build/$DMG_NAME"
    
    # 清理临时目录
    rm -rf "$DMG_DIR"
    
    print_success "DMG 创建完成: ./build/$DMG_NAME"
}

# 显示帮助信息
show_help() {
    echo "Mac Screen Capture 构建脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  clean       清理构建目录"
    echo "  check       代码质量检查"
    echo "  test        运行单元测试"
    echo "  build       构建应用"
    echo "  archive     创建归档"
    echo "  export      导出应用"
    echo "  dmg         创建 DMG 安装包"
    echo "  all         执行完整构建流程"
    echo "  help        显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 all      # 执行完整构建流程"
    echo "  $0 test     # 只运行测试"
    echo "  $0 build    # 只构建应用"
}

# 主函数
main() {
    case "${1:-all}" in
        "clean")
            check_dependencies
            clean_build
            ;;
        "check")
            check_dependencies
            code_quality_check
            ;;
        "test")
            check_dependencies
            run_tests
            ;;
        "build")
            check_dependencies
            build_app
            ;;
        "archive")
            check_dependencies
            create_archive
            ;;
        "export")
            check_dependencies
            export_app
            ;;
        "dmg")
            check_dependencies
            create_dmg
            ;;
        "all")
            check_dependencies
            clean_build
            code_quality_check
            run_tests
            build_app
            create_archive
            export_app
            create_dmg
            print_success "完整构建流程完成！"
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            print_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"