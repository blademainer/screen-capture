#!/bin/bash

# 麦克风录制日志检查脚本

LOG_FILE="$HOME/Desktop/MacScreenCapture_Microphone_Debug.log"

echo "=========================================="
echo "麦克风录制日志检查工具"
echo "=========================================="
echo ""

if [ ! -f "$LOG_FILE" ]; then
    echo "❌ 日志文件不存在: $LOG_FILE"
    echo ""
    echo "请先运行应用并进行一次录制，日志文件会自动创建在桌面。"
    exit 1
fi

echo "✓ 找到日志文件: $LOG_FILE"
echo ""

# 检查关键信息
echo "========== 关键信息检查 =========="
echo ""

echo "1. 麦克风设置状态:"
grep "includeMicrophone:" "$LOG_FILE" | tail -1
echo ""

echo "2. 麦克风设备检测:"
grep "音频设备数量" "$LOG_FILE" | tail -1
grep "设备" "$LOG_FILE" | grep -v "音频设备数量" | tail -5
echo ""

echo "3. 麦克风权限状态:"
grep "麦克风权限状态" "$LOG_FILE" | tail -1
echo ""

echo "4. SCStream 配置:"
grep "captureMicrophone:" "$LOG_FILE" | tail -1
echo ""

echo "5. 麦克风流添加状态:"
grep "添加麦克风" "$LOG_FILE" | tail -1
echo ""

echo "6. AVAssetWriter 麦克风输入:"
grep "麦克风音频输入已" "$LOG_FILE" | tail -1
echo ""

echo "7. 麦克风音频帧统计:"
MIC_FRAMES=$(grep "麦克风音频帧总数" "$LOG_FILE" | tail -1)
echo "$MIC_FRAMES"

if echo "$MIC_FRAMES" | grep -q ": 0"; then
    echo "   ❌ 警告：没有录制到麦克风音频！"
else
    echo "   ✓ 成功录制到麦克风音频"
fi
echo ""

echo "8. 首个麦克风帧:"
grep "首个麦克风音频帧" "$LOG_FILE" | tail -1
echo ""

echo "=========================================="
echo "完整日志内容:"
echo "=========================================="
cat "$LOG_FILE"
echo ""
echo "=========================================="
echo "日志文件位置: $LOG_FILE"
echo "=========================================="
