import Foundation

// MARK: - UserDefaults Extensions for Floating Window Settings
extension UserDefaults {
    static var macScreenCaptureDefaults: [String: Any] {
        [
            "autoSaveScreenshots": true,
            "floatingWindowAlwaysOnTop": true,
            "floatingWindowAutoHide": false,
            "floatingWindowAutoHideDelay": 3.0,
            "floatingWindowOpacity": 0.95,
            "floatingWindowShowPreview": true,
            "floatingWindowShowShadow": true,
            "floatingWindowPosition": "topRight",
            "floatingWindowCloseAfterSave": false,
            "autoCopyToClipboard": false,
            "autoOpenAfterCaptureInConfiguredApp": false,
            "doubleOptionQuickOpenEnabled": true,
            "doubleOptionQuickOpenInterval": 0.45,
            "doubleOptionQuickOpenCooldown": 1.0,
            "numberedAnnotationStart": 1,
            "annotationStylePreset": AnnotationStylePreset.professional.rawValue,
            "annotationDefaultColorHex": AnnotationStylePreset.professional.colorHex,
            "annotationDefaultLineWidth": AnnotationStylePreset.professional.lineWidth,
            "annotationDefaultFontSize": AnnotationStylePreset.professional.fontSize,
            "annotationTextOutlined": AnnotationStylePreset.professional.textOutlined,
            "annotationCustomColorHex": AnnotationStylePreset.professional.colorHex,
            "annotationCustomLineWidth": AnnotationStylePreset.professional.lineWidth,
            "annotationCustomFontSize": AnnotationStylePreset.professional.fontSize,
            "annotationCustomTextOutlined": AnnotationStylePreset.professional.textOutlined,
            "annotationCustom2ColorHex": AnnotationStylePreset.professional.colorHex,
            "annotationCustom2LineWidth": AnnotationStylePreset.professional.lineWidth,
            "annotationCustom2FontSize": AnnotationStylePreset.professional.fontSize,
            "annotationCustom2TextOutlined": AnnotationStylePreset.professional.textOutlined,
            "annotationCustom3ColorHex": AnnotationStylePreset.professional.colorHex,
            "annotationCustom3LineWidth": AnnotationStylePreset.professional.lineWidth,
            "annotationCustom3FontSize": AnnotationStylePreset.professional.fontSize,
            "annotationCustom3TextOutlined": AnnotationStylePreset.professional.textOutlined,
            "colorCodeFormat": "#HEX",
            "customColorCodeTemplate": "{hex}",
            "multiWindowDesktopBackdrop": true,
            "delayedScreenshotSeconds": 5,
            "scrollingCaptureSlices": 30,
            "scrollingCaptureDelay": 0.8,
            "scrollingCaptureLines": 12,
            "scrollingCaptureDirection": "down",
            "scrollingCaptureTrimOverlap": true,
            "scrollingCaptureCropToWindow": true,
            "scrollingCaptureDetectContentArea": true,
            "scrollingCaptureStopWhenUnchanged": true,
            "screenshotRoundedCorners": false,
            "screenshotDropShadow": false,
            "screenshotCornerRadius": 18.0,
            "screenshotShadowRadius": 24.0,
            "screenshotShadowColorHex": "#000000",
            "includeSystemAudio": true,
            "includeMicrophone": true,
            "showCursor": true,
            "recordingFrameRate": 60.0,
            "recordingQuality": "高",
            "recordingStartDelaySeconds": 0,
            "recordingFileFormat": "MOV",
            "deviceFrameBezelWidth": 42.0,
            "deviceFramePadding": 48.0,
            "deviceFrameCornerRadius": 26.0,
            "deviceFrameShadowRadius": 28.0,
            "deviceFrameBodyColorHex": "#141414",
            "deviceFrameShadowColorHex": "#000000"
        ]
    }

    static func registerMacScreenCaptureDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: macScreenCaptureDefaults)
    }
    
    // MARK: - Floating Window Settings
    var floatingWindowAlwaysOnTop: Bool {
        get {
            return bool(forKey: "floatingWindowAlwaysOnTop")
        }
        set {
            set(newValue, forKey: "floatingWindowAlwaysOnTop")
        }
    }
    
    var floatingWindowAutoHide: Bool {
        get {
            return bool(forKey: "floatingWindowAutoHide")
        }
        set {
            set(newValue, forKey: "floatingWindowAutoHide")
        }
    }
    
    var floatingWindowAutoHideDelay: Double {
        get {
            let value = double(forKey: "floatingWindowAutoHideDelay")
            return value > 0 ? value : 3.0 // 默认3秒
        }
        set {
            set(newValue, forKey: "floatingWindowAutoHideDelay")
        }
    }
    
    var floatingWindowOpacity: Double {
        get {
            let value = double(forKey: "floatingWindowOpacity")
            return value > 0 ? value : 0.95 // 默认95%透明度
        }
        set {
            set(newValue, forKey: "floatingWindowOpacity")
        }
    }
    
    var floatingWindowShowPreview: Bool {
        get {
            return bool(forKey: "floatingWindowShowPreview")
        }
        set {
            set(newValue, forKey: "floatingWindowShowPreview")
        }
    }
    
    var floatingWindowPosition: String {
        get {
            return string(forKey: "floatingWindowPosition") ?? "topRight"
        }
        set {
            set(newValue, forKey: "floatingWindowPosition")
        }
    }
    
    var autoCopyToClipboard: Bool {
        get {
            return bool(forKey: "autoCopyToClipboard")
        }
        set {
            set(newValue, forKey: "autoCopyToClipboard")
        }
    }
    
    var showInFinderAfterSave: Bool {
        get {
            return bool(forKey: "showInFinderAfterSave")
        }
        set {
            set(newValue, forKey: "showInFinderAfterSave")
        }
    }
    
    var floatingWindowShowShadow: Bool {
        get {
            return bool(forKey: "floatingWindowShowShadow")
        }
        set {
            set(newValue, forKey: "floatingWindowShowShadow")
        }
    }
    
    // MARK: - Initialize Default Values
    static func registerFloatingWindowDefaults() {
        UserDefaults.standard.register(defaults: [
            "floatingWindowAlwaysOnTop": true,
            "floatingWindowAutoHide": false,
            "floatingWindowAutoHideDelay": 3.0,
            "floatingWindowOpacity": 0.95,
            "floatingWindowShowPreview": true,
            "floatingWindowPosition": "topRight",
            "autoCopyToClipboard": false,
            "showInFinderAfterSave": false,
            "floatingWindowShowShadow": true
        ])
    }
}
