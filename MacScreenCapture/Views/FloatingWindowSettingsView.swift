import SwiftUI

// MARK: - Floating Window Settings View
struct FloatingWindowSettingsView: View {
    @AppStorage("autoCopyToClipboard") private var autoCopyToClipboard = false
    @AppStorage("floatingWindowAlwaysOnTop") private var alwaysOnTop = true
    @AppStorage("floatingWindowShowShadow") private var showShadow = true
    @AppStorage("floatingWindowOpacity") private var opacity = 1.0
    @AppStorage("autoShowFloatingWindow") private var autoShowFloatingWindow = true
    @AppStorage("floatingWindowCloseAfterSave") private var closeAfterSave = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("浮窗设置")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                // 基础设置
                GroupBox("基础设置") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("截图后自动显示浮窗", isOn: $autoShowFloatingWindow)
                            .help("截图完成后立即显示预览浮窗")
                        
                        Toggle("自动复制到剪贴板", isOn: $autoCopyToClipboard)
                            .help("截图后自动将图片复制到系统剪贴板")
                        
                        Toggle("保存后自动关闭浮窗", isOn: $closeAfterSave)
                            .help("保存图片后自动关闭浮窗")
                    }
                    .padding(.vertical, 8)
                }
                
                // 外观设置
                GroupBox("外观设置") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("始终置顶显示", isOn: $alwaysOnTop)
                            .help("浮窗始终显示在其他窗口之上")
                        
                        Toggle("显示窗口阴影", isOn: $showShadow)
                            .help("为浮窗添加阴影效果")
                        
                        HStack {
                            Text("窗口透明度:")
                            Slider(value: $opacity, in: 0.3...1.0, step: 0.1)
                                .frame(width: 120)
                            Text("\(Int(opacity * 100))%")
                                .frame(width: 40, alignment: .trailing)
                                .foregroundColor(.secondary)
                        }
                        .help("调整浮窗的透明度")
                    }
                    .padding(.vertical, 8)
                }
                
                // 快捷操作
                GroupBox("快捷操作") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button("关闭所有浮窗") {
                                FloatingWindowManager.shared.closeAllWindows()
                            }
                            .buttonStyle(.bordered)
                            
                            Button("最小化所有浮窗") {
                                FloatingWindowManager.shared.minimizeAllWindows()
                            }
                            .buttonStyle(.bordered)
                            
                            Button("恢复所有浮窗") {
                                FloatingWindowManager.shared.restoreAllWindows()
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        Text("当前活动浮窗: \(FloatingWindowManager.shared.activeWindows.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                
                // 使用提示
                GroupBox("使用提示") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "hand.tap")
                                .foregroundColor(.blue)
                            Text("双击图片区域可以隐藏/显示工具栏")
                        }
                        
                        HStack {
                            Image(systemName: "keyboard")
                                .foregroundColor(.green)
                            Text("使用 Cmd+S 快速保存，Cmd+C 快速复制")
                        }
                        
                        HStack {
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.orange)
                            Text("拖拽浮窗边缘可以调整大小")
                        }
                    }
                    .font(.caption)
                    .padding(.vertical, 8)
                }
            }
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    FloatingWindowSettingsView()
        .frame(width: 400, height: 500)
}