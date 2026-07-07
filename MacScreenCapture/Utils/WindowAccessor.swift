//
//  WindowAccessor.swift
//  MacScreenCapture
//
//  Created by Developer on 2025/9/28.
//

import SwiftUI
import AppKit

/// 用于获取SwiftUI视图对应的NSWindow的辅助结构
struct WindowAccessor: NSViewRepresentable {
    let onWindowChange: (NSWindow) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        
        // 在下一个运行循环中获取窗口
        DispatchQueue.main.async {
            if let window = view.window {
                self.onWindowChange(window)
            }
        }
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // 检查窗口是否发生变化
        if let window = nsView.window {
            onWindowChange(window)
        }
    }
}