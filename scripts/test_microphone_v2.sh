#!/bin/bash

# 麦克风功能测试脚本 v2
# 用于验证重新实现的麦克风录制功能

set -e

echo "=========================================="
echo "麦克风功能测试脚本 v2"
echo "=========================================="
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 测试结果统计
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# 测试函数
test_case() {
    local test_name=$1
    local test_result=$2
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if [ "$test_result" = "0" ]; then
        echo -e "${GREEN}✓${NC} $test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗${NC} $test_name"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

echo -e "${BLUE}1. 检查麦克风设备${NC}"
echo "----------------------------------------"

# 检查系统是否有麦克风设备
if system_profiler SPAudioDataType | grep -q "Input"; then
    echo -e "${GREEN}✓${NC} 检测到音频输入设备"
    test_case "麦克风设备检测" 0
    
    # 列出所有音频输入设备
    echo ""
    echo "可用的音频输入设备："
    system_profiler SPAudioDataType | grep -A 5 "Input" | head -20
else
    echo -e "${RED}✗${NC} 未检测到音频输入设备"
    test_case "麦克风设备检测" 1
fi

echo ""
echo -e "${BLUE}2. 检查麦克风权限${NC}"
echo "----------------------------------------"

# 检查应用的麦克风权限
APP_NAME="MacScreenCapture"
PLIST_PATH="$HOME/Library/Preferences/com.apple.TCC.plist"

if [ -f "$PLIST_PATH" ]; then
    echo "检查 TCC 权限数据库..."
    # 注意：在新版 macOS 中，TCC 数据库可能在不同位置
    if plutil -p "$PLIST_PATH" 2>/dev/null | grep -q "Microphone"; then
        echo -e "${GREEN}✓${NC} 应用已请求麦克风权限"
        test_case "麦克风权限请求" 0
    else
        echo -e "${YELLOW}⚠${NC} 未找到麦克风权限记录（可能尚未请求）"
        test_case "麦克风权限请求" 1
    fi
else
    echo -e "${YELLOW}⚠${NC} 无法访问 TCC 权限数据库"
fi

echo ""
echo -e "${BLUE}3. 检查应用配置${NC}"
echo "----------------------------------------"

# 检查 Info.plist 中的麦克风使用说明
INFO_PLIST="../MacScreenCapture/Info.plist"
if [ -f "$INFO_PLIST" ]; then
    if grep -q "NSMicrophoneUsageDescription" "$INFO_PLIST"; then
        echo -e "${GREEN}✓${NC} Info.plist 包含麦克风使用说明"
        test_case "Info.plist 配置" 0
        
        # 显示使用说明
        USAGE_DESC=$(plutil -extract NSMicrophoneUsageDescription raw "$INFO_PLIST" 2>/dev/null || echo "无法读取")
        echo "  使用说明: $USAGE_DESC"
    else
        echo -e "${RED}✗${NC} Info.plist 缺少麦克风使用说明"
        test_case "Info.plist 配置" 1
    fi
else
    echo -e "${RED}✗${NC} 找不到 Info.plist 文件"
    test_case "Info.plist 配置" 1
fi

# 检查 entitlements
ENTITLEMENTS="../MacScreenCapture/MacScreenCapture.entitlements"
if [ -f "$ENTITLEMENTS" ]; then
    if grep -q "com.apple.security.device.microphone" "$ENTITLEMENTS"; then
        echo -e "${GREEN}✓${NC} Entitlements 包含麦克风权限"
        test_case "Entitlements 配置" 0
    else
        echo -e "${RED}✗${NC} Entitlements 缺少麦克风权限"
        test_case "Entitlements 配置" 1
    fi
else
    echo -e "${RED}✗${NC} 找不到 Entitlements 文件"
    test_case "Entitlements 配置" 1
fi

echo ""
echo -e "${BLUE}4. 检查代码实现${NC}"
echo "----------------------------------------"

# 检查 PermissionManager 中的麦克风权限检查
PERMISSION_MANAGER="../MacScreenCapture/Core/PermissionManager.swift"
if [ -f "$PERMISSION_MANAGER" ]; then
    if grep -q "requestMicrophonePermissionAsync" "$PERMISSION_MANAGER"; then
        echo -e "${GREEN}✓${NC} PermissionManager 包含异步麦克风权限请求"
        test_case "异步权限请求实现" 0
    else
        echo -e "${RED}✗${NC} PermissionManager 缺少异步麦克风权限请求"
        test_case "异步权限请求实现" 1
    fi
    
    if grep -q "checkMicrophoneDeviceAvailable" "$PERMISSION_MANAGER"; then
        echo -e "${GREEN}✓${NC} PermissionManager 包含麦克风设备检测"
        test_case "设备检测实现" 0
    else
        echo -e "${RED}✗${NC} PermissionManager 缺少麦克风设备检测"
        test_case "设备检测实现" 1
    fi
else
    echo -e "${RED}✗${NC} 找不到 PermissionManager.swift"
    test_case "PermissionManager 存在" 1
fi

# 检查 CaptureManager 中的麦克风录制
CAPTURE_MANAGER="../MacScreenCapture/Core/CaptureManager.swift"
if [ -f "$CAPTURE_MANAGER" ]; then
    if grep -q "microphoneInput" "$CAPTURE_MANAGER"; then
        echo -e "${GREEN}✓${NC} CaptureManager 包含麦克风输入处理"
        test_case "麦克风输入处理" 0
    else
        echo -e "${RED}✗${NC} CaptureManager 缺少麦克风输入处理"
        test_case "麦克风输入处理" 1
    fi
    
    if grep -q "case .microphone:" "$CAPTURE_MANAGER"; then
        echo -e "${GREEN}✓${NC} CaptureManager 包含麦克风流类型处理"
        test_case "麦克风流处理" 0
    else
        echo -e "${RED}✗${NC} CaptureManager 缺少麦克风流类型处理"
        test_case "麦克风流处理" 1
    fi
    
    if grep -q "noMicrophoneAvailable" "$CAPTURE_MANAGER"; then
        echo -e "${GREEN}✓${NC} CaptureManager 包含麦克风错误处理"
        test_case "麦克风错误处理" 0
    else
        echo -e "${RED}✗${NC} CaptureManager 缺少麦克风错误处理"
        test_case "麦克风错误处理" 1
    fi
else
    echo -e "${RED}✗${NC} 找不到 CaptureManager.swift"
    test_case "CaptureManager 存在" 1
fi

echo ""
echo -e "${BLUE}5. 编译检查${NC}"
echo "----------------------------------------"

# 尝试编译项目
echo "正在编译项目..."
if xcodebuild -project ../MacScreenCapture.xcodeproj -scheme MacScreenCapture -configuration Debug clean build 2>&1 | grep -q "BUILD SUCCEEDED"; then
    echo -e "${GREEN}✓${NC} 项目编译成功"
    test_case "项目编译" 0
else
    echo -e "${RED}✗${NC} 项目编译失败"
    test_case "项目编译" 1
    echo "请检查编译错误日志"
fi

echo ""
echo "=========================================="
echo -e "${BLUE}测试总结${NC}"
echo "=========================================="
echo "总测试数: $TOTAL_TESTS"
echo -e "${GREEN}通过: $PASSED_TESTS${NC}"
echo -e "${RED}失败: $FAILED_TESTS${NC}"

if [ $FAILED_TESTS -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ 所有测试通过！${NC}"
    echo ""
    echo "下一步："
    echo "1. 运行应用并测试麦克风录制功能"
    echo "2. 检查系统偏好设置中的麦克风权限"
    echo "3. 录制一段视频并验证麦克风音频"
    echo "4. 查看控制台日志以确认麦克风音频帧正在写入"
    exit 0
else
    echo ""
    echo -e "${RED}✗ 有 $FAILED_TESTS 个测试失败${NC}"
    echo ""
    echo "请修复失败的测试项后再继续"
    exit 1
fi
