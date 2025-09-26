//
//  CaptureManager.swift
//  MacScreenCapture
//
//  Created by Developer on 2025/9/25.
//

import Foundation
import SwiftUI
import ScreenCaptureKit
import AVFoundation
import CoreGraphics
import AppKit

/// 捕获管理器 - 负责截图和录制功能的核心逻辑
@available(macOS 12.3, *)
@MainActor
class CaptureManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var captureMode: CaptureMode = .fullScreen
    @Published var selectedDisplay: SCDisplay?
    @Published var selectedWindow: SCWindow?
    @Published var availableDisplays: [SCDisplay] = []
    @Published var availableWindows: [SCWindow] = []
    @Published var lastCapturedImage: NSImage?
    @Published var recordingURL: URL?
    
    // MARK: - Private Properties
    private var stream: SCStream?
    private var streamOutput: CaptureStreamOutput?
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    
    // MARK: - Configuration
    private let outputDirectory: URL = {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let captureDir = documentsPath.appendingPathComponent("ScreenCaptures")
        try? FileManager.default.createDirectory(at: captureDir, withIntermediateDirectories: true)
        return captureDir
    }()
    
    // MARK: - Initialization
    init() {
        setupNotifications()
    }
    
    deinit {
        Task {
            await stopRecording()
        }
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Methods
    
    /// 初始化捕获管理器
    func initialize() {
        Task {
            await updateAvailableContent()
        }
    }
    
    /// 截图
    func captureScreenshot() async throws -> NSImage {
        guard #available(macOS 12.3, *) else {
            return try await captureLegacyScreenshot()
        }
        
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        let filter: SCContentFilter
        
        switch captureMode {
        case .fullScreen:
            guard let display = selectedDisplay ?? content.displays.first else {
                throw CaptureError.noDisplayAvailable
            }
            filter = SCContentFilter(display: display, excludingWindows: [])
            
        case .window:
            guard let window = selectedWindow else {
                throw CaptureError.noWindowSelected
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            
        case .region:
            // 区域截图需要先选择区域
            return try await captureRegionScreenshot()
        }
        
        let configuration = SCStreamConfiguration()
        
        // 获取显示器尺寸
        let displaySize: CGSize
        if let display = selectedDisplay {
            displaySize = CGSize(width: display.width, height: display.height)
        } else {
            displaySize = CGSize(width: 1920, height: 1080) // 默认尺寸
        }
        
        configuration.width = Int(displaySize.width)
        configuration.height = Int(displaySize.height)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true
        
        // 使用旧版本兼容的截图方法
        return try await captureLegacyScreenshot()
    }
    
    /// 开始录制
    func startRecording() async throws {
        guard !isRecording else { return }
        guard #available(macOS 12.3, *) else {
            throw CaptureError.unsupportedSystem
        }
        
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        let filter: SCContentFilter
        
        switch captureMode {
        case .fullScreen:
            guard let display = selectedDisplay ?? content.displays.first else {
                throw CaptureError.noDisplayAvailable
            }
            filter = SCContentFilter(display: display, excludingWindows: [])
            
        case .window:
            guard let window = selectedWindow else {
                throw CaptureError.noWindowSelected
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            
        case .region:
            throw CaptureError.regionRecordingNotSupported
        }
        
        let configuration = SCStreamConfiguration()
        configuration.width = 1920
        configuration.height = 1080
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60) // 60 FPS
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        configuration.showsCursor = true
        if #available(macOS 13.0, *) {
            configuration.capturesAudio = true
        }
        
        // 创建输出文件URL
        let fileName = "Recording_\(DateFormatter.fileNameFormatter.string(from: Date())).mov"
        recordingURL = outputDirectory.appendingPathComponent(fileName)
        
        // 创建流输出
        streamOutput = CaptureStreamOutput(outputURL: recordingURL!)
        
        // 创建并启动流
        stream = SCStream(filter: filter, configuration: configuration, delegate: streamOutput)
        
        try stream?.addStreamOutput(streamOutput!, type: .screen, sampleHandlerQueue: DispatchQueue.global(qos: .userInitiated))
        
        try await stream?.startCapture()
        
        // 更新状态
        isRecording = true
        isPaused = false
        recordingStartTime = Date()
        startRecordingTimer()
        
        // 发送通知
        NotificationCenter.default.post(name: .recordingDidStart, object: nil)
    }
    
    /// 停止录制
    func stopRecording() async {
        guard isRecording else { return }
        
        try? await stream?.stopCapture()
        stream = nil
        streamOutput = nil
        
        isRecording = false
        isPaused = false
        recordingDuration = 0
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingStartTime = nil
        
        // 发送通知
        NotificationCenter.default.post(name: .recordingDidStop, object: recordingURL)
    }
    
    /// 暂停/恢复录制
    func togglePauseRecording() {
        guard isRecording else { return }
        
        if isPaused {
            // 恢复录制
            recordingStartTime = Date().addingTimeInterval(-recordingDuration)
            startRecordingTimer()
            isPaused = false
        } else {
            // 暂停录制
            recordingTimer?.invalidate()
            recordingTimer = nil
            isPaused = true
        }
    }
    
    /// 更新可用内容
    func updateAvailableContent() async {
        guard #available(macOS 12.3, *) else { return }
        
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            
            availableDisplays = content.displays
            availableWindows = content.windows.filter { window in
                window.title?.isEmpty == false && window.frame.width > 100 && window.frame.height > 100
            }
            
            // 设置默认选择
            if selectedDisplay == nil {
                selectedDisplay = availableDisplays.first
            }
            
        } catch {
            print("Failed to get shareable content: \(error)")
        }
    }
    
    // MARK: - Private Methods
    
    /// 设置通知监听
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDisplayConfigurationChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    /// 处理显示器配置变化
    @objc private func handleDisplayConfigurationChange() {
        Task {
            await updateAvailableContent()
        }
    }
    
    /// 开始录制计时器
    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.recordingStartTime else { return }
            self.recordingDuration = Date().timeIntervalSince(startTime)
        }
    }
    
    /// 保存截图
    private func saveScreenshot(_ image: NSImage) async throws {
        let fileName = "Screenshot_\(DateFormatter.fileNameFormatter.string(from: Date())).png"
        let fileURL = outputDirectory.appendingPathComponent(fileName)
        
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            throw CaptureError.failedToSaveImage
        }
        
        try pngData.write(to: fileURL)
        
        // 发送通知
        NotificationCenter.default.post(name: .screenshotDidSave, object: fileURL)
    }
    
    /// 区域截图
    private func captureRegionScreenshot() async throws -> NSImage {
        // 这里需要实现区域选择UI
        // 暂时返回全屏截图
        let oldMode = captureMode
        captureMode = .fullScreen
        defer { captureMode = oldMode }
        
        return try await captureScreenshot()
    }
    
    /// 旧系统截图方法
    private func captureLegacyScreenshot() async throws -> NSImage {
        let displayID = CGMainDisplayID()
        
        guard let cgImage = CGDisplayCreateImage(displayID) else {
            throw CaptureError.failedToCapture
        }
        
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        
        try await saveScreenshot(nsImage)
        lastCapturedImage = nsImage
        
        return nsImage
    }
}

// MARK: - Capture Mode

enum CaptureMode: String, CaseIterable {
    case fullScreen = "全屏"
    case window = "窗口"
    case region = "区域"
    
    var systemImage: String {
        switch self {
        case .fullScreen: return "display"
        case .window: return "macwindow"
        case .region: return "crop"
        }
    }
}

// MARK: - Capture Errors

enum CaptureError: LocalizedError {
    case noDisplayAvailable
    case noWindowSelected
    case regionRecordingNotSupported
    case unsupportedSystem
    case failedToCapture
    case failedToSaveImage
    
    var errorDescription: String? {
        switch self {
        case .noDisplayAvailable:
            return "没有可用的显示器"
        case .noWindowSelected:
            return "没有选择窗口"
        case .regionRecordingNotSupported:
            return "区域录制暂不支持"
        case .unsupportedSystem:
            return "系统版本不支持"
        case .failedToCapture:
            return "捕获失败"
        case .failedToSaveImage:
            return "保存图片失败"
        }
    }
}

// MARK: - Stream Output

@available(macOS 12.3, *)
class CaptureStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    private let outputURL: URL
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    
    init(outputURL: URL) {
        self.outputURL = outputURL
        super.init()
        setupAssetWriter()
    }
    
    private func setupAssetWriter() {
        do {
            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
            
            // 视频输入设置
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 1920,
                AVVideoHeightKey: 1080,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 5000000
                ]
            ]
            
            videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput?.expectsMediaDataInRealTime = true
            
            if let videoInput = videoInput, assetWriter?.canAdd(videoInput) == true {
                assetWriter?.add(videoInput)
            }
            
            // 音频输入设置
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128000
            ]
            
            audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput?.expectsMediaDataInRealTime = true
            
            if let audioInput = audioInput, assetWriter?.canAdd(audioInput) == true {
                assetWriter?.add(audioInput)
            }
            
        } catch {
            print("Failed to setup asset writer: \(error)")
        }
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard let assetWriter = assetWriter else { return }
        
        if assetWriter.status == .unknown {
            assetWriter.startWriting()
            assetWriter.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        }
        
        switch type {
        case .screen:
            if let videoInput = videoInput, videoInput.isReadyForMoreMediaData {
                videoInput.append(sampleBuffer)
            }
        case .audio:
            if let audioInput = audioInput, audioInput.isReadyForMoreMediaData {
                audioInput.append(sampleBuffer)
            }
        case .microphone:
            if let audioInput = audioInput, audioInput.isReadyForMoreMediaData {
                audioInput.append(sampleBuffer)
            }
        @unknown default:
            break
        }
    }
    
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("Stream stopped with error: \(error)")
        finishWriting()
    }
    
    private func finishWriting() {
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        
        assetWriter?.finishWriting {
            print("Recording finished")
        }
    }
}

// MARK: - Extensions

extension DateFormatter {
    static let fileNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}

extension Notification.Name {
    static let recordingDidStart = Notification.Name("recordingDidStart")
    static let recordingDidStop = Notification.Name("recordingDidStop")
    static let screenshotDidSave = Notification.Name("screenshotDidSave")
}