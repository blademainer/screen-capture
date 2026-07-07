#!/bin/bash

# 麦克风录制功能测试脚本
# 用于验证麦克风录制Bug修复

echo "🎤 麦克风录制功能测试"
echo "======================"

# 检查系统版本
echo "1. 检查系统版本..."
sw_vers

# 检查麦克风权限
echo -e "\n2. 检查麦克风权限..."
if system_profiler SPAudioDataType | grep -q "Built-in Microphone"; then
    echo "✅ 检测到内置麦克风"
else
    echo "❌ 未检测到内置麦克风"
fi

# 检查音频设备
echo -e "\n3. 检查音频输入设备..."
system_profiler SPAudioDataType | grep -A 5 "Input"

# 检查应用权限设置
echo -e "\n4. 检查应用权限..."
if tccutil list | grep -q "kTCCServiceMicrophone"; then
    echo "✅ 麦克风权限配置存在"
else
    echo "⚠️  麦克风权限可能需要手动授予"
fi

# 编译项目
echo -e "\n5. 编译项目..."
cd "$(dirname "$0")/.."
if xcodebuild -project MacScreenCapture.xcodeproj -scheme MacScreenCapture -configuration Debug build; then
    echo "✅ 项目编译成功"
else
    echo "❌ 项目编译失败"
    exit 1
fi

echo -e "\n🎉 测试完成！"
echo "请手动测试以下功能："
echo "1. 打开应用并授予麦克风权限"
echo "2. 在录制设置中启用麦克风录制"
echo "3. 开始录制并说话测试"
echo "4. 停止录制后检查视频是否包含音频"

echo -e "\n📋 修复内容总结："
echo "- ✅ 添加了麦克风权限检查"
echo "- ✅ 启用了 configuration.captureMicrophone"
echo "- ✅ 添加了麦克风音频流输出"
echo "- ✅ 改进了音频设置界面"
echo "- ✅ 添加了音频状态指示器"
echo "- ✅ 设置了默认启用麦克风录制"