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

    final class Coordinator {
        weak var lastWindow: NSWindow?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        
        // 在下一个运行循环中获取窗口
        notifyWindowChangeIfNeeded(from: view, coordinator: context.coordinator)

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // SwiftUI may call this while updating the view tree, so report changes
        // on the next run loop instead of mutating @State synchronously.
        notifyWindowChangeIfNeeded(from: nsView, coordinator: context.coordinator)
    }

    private func notifyWindowChangeIfNeeded(from view: NSView, coordinator: Coordinator) {
        DispatchQueue.main.async {
            guard let window = view.window, coordinator.lastWindow !== window else { return }
            coordinator.lastWindow = window
            onWindowChange(window)
        }
    }
}
